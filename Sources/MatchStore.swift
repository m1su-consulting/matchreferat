import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class MatchStore {
    struct Toast: Equatable {
        let id = UUID()
        let eventID: UUID
        let text: String
    }

    var state: MatchState
    var teams: [Team]
    /// Finished matches the user chose to keep, newest first.
    private(set) var savedMatches: [SavedMatch] = []
    var toast: Toast?
    /// The sport chosen on the first page, remembered between launches. Nil shows the sport picker.
    var sport: Sport? {
        didSet { defaults.set(sport?.rawValue, forKey: Self.sportKey) }
    }
    /// The navigation stack above the start page; `-screen match|settings` opens that page on launch.
    var path: [Route] = switch LaunchArgument.string("screen") {
    case "match": [.match]
    case "settings": [.settings]
    default: []
    }

    func openMatch() { path = [.match] }
    func goToStart() { path.removeAll() }

    private let container: ModelContainer
    private let defaults: UserDefaults
    private static let sportKey = "sport"
    private var context: ModelContext { container.mainContext }
    private static let log = Logger(subsystem: "se.matchreferat.app", category: "store")

    /// Loads the match and teams from SwiftData. The first time, they are imported from the
    /// JSON files earlier versions wrote to `legacyDirectory`, which are kept as a backup.
    init(container: ModelContainer, legacyDirectory: URL = Persistence.legacyDirectory, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
        // `-sport football|floorball` picks the sport on launch (used for screenshots and tests).
        let last = defaults.string(forKey: Self.sportKey).flatMap(Sport.init(rawValue:))
        if let argument = LaunchArgument.string("sport") {
            sport = Sport(rawValue: argument)
        } else {
            sport = AppSettings.launchSport(defaults, last: last)
        }
        let context = container.mainContext
        let decoder = JSONDecoder()
        let storedMatch = (try? context.fetch(FetchDescriptor<StoredMatch>()))?.first
        let storedTeams = (try? context.fetch(FetchDescriptor<StoredTeam>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let importing = storedMatch == nil && storedTeams.isEmpty

        var match = MatchState.empty
        if let storedMatch, let saved = try? decoder.decode(MatchState.self, from: storedMatch.payload) {
            match = saved
        } else if importing, let data = try? Data(contentsOf: legacyDirectory.appendingPathComponent("match.json")),
                  var saved = try? decoder.decode(MatchState.self, from: data) {
            // Older versions logged saves separately and had blocked shots; a save is now
            // implied by a shot on target, and blocked shots count as off target.
            saved.events.removeAll { $0.kind == .save }
            for index in saved.events.indices where saved.events[index].shot == .blocked {
                saved.events[index].shot = .off
            }
            match = saved
        }

        if !storedTeams.isEmpty {
            teams = storedTeams.compactMap { try? decoder.decode(Team.self, from: $0.payload) }
        } else if importing, let data = try? Data(contentsOf: legacyDirectory.appendingPathComponent("teams.json")),
                  let saved = try? decoder.decode([Team].self, from: data) {
            teams = saved
        } else if match.teamID == MatchState.exampleTeamID {
            teams = [MatchState.exampleTeam()]
        } else if match.players.isEmpty {
            // First launch: no teams yet.
            teams = []
        } else {
            // Before teams existed, the squad lived in the match: it becomes the first team.
            let team = Team(name: match.ourTeam, playersOnField: match.playersOnField, periods: match.periods,
                            periodLength: match.halfLength,
                            players: match.players.map { var p = $0; p.status = .bench; return p })
            teams = [team]
            match.teamID = team.id
        }
        state = match
        let saved = (try? context.fetch(FetchDescriptor<StoredSavedMatch>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)]))) ?? []
        savedMatches = saved.compactMap { stored in
            (try? decoder.decode(MatchState.self, from: stored.payload)).map { SavedMatch(id: stored.id, savedAt: stored.savedAt, state: $0) }
        }
        if importing {
            save()
            saveTeams()
        }
    }

    func save() {
        guard let payload = try? JSONEncoder().encode(state) else { return }
        if let stored = (try? context.fetch(FetchDescriptor<StoredMatch>()))?.first {
            stored.payload = payload
            stored.updatedAt = .now
        } else {
            context.insert(StoredMatch(payload: payload))
        }
        commit()
    }

    func saveTeams() {
        let encoder = JSONEncoder()
        let existing = (try? context.fetch(FetchDescriptor<StoredTeam>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (order, team) in teams.enumerated() {
            guard let payload = try? encoder.encode(team) else { continue }
            if let stored = byID.removeValue(forKey: team.id) {
                stored.order = order
                stored.payload = payload
            } else {
                context.insert(StoredTeam(id: team.id, order: order, payload: payload))
            }
        }
        byID.values.forEach(context.delete)
        commit()
    }

    private func commit() {
        do { try context.save() } catch {
            Self.log.error("Save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The teams of one sport, in the order shown on the start page.
    func teams(for sport: Sport) -> [Team] { teams.filter { $0.sport == sport } }

    func addTeam(_ sport: Sport) -> Team {
        let team = Team.new(sport)
        teams.append(team)
        return team
    }

    func deleteTeams(_ ids: [UUID]) {
        teams.removeAll { ids.contains($0.id) }
    }

    // MARK: Events

    func log(_ kind: EventKind, side: Side, player: UUID? = nil, otherPlayer: UUID? = nil, shot: ShotResult? = nil,
             isPenalty: Bool? = nil, suspension: Suspension? = nil) {
        let event = MatchEvent(kind: kind, side: side, minute: state.clock(at: .now), createdAt: .now,
                               player: player, otherPlayer: otherPlayer, shot: shot, isPenalty: isPenalty,
                               suspension: suspension)
        if kind == .sub, let out = player, let into = otherPlayer {
            setStatus(out, .bench)
            setStatus(into, .start)
        }
        state.events.append(event)

        var text = "\(event.minute.text) \(state.describe(event))"
        if side == .them && kind != .goal { text += " (\(state.opponent))" }
        toast = Toast(eventID: event.id, text: text)
    }

    /// A scored penalty is a goal (so it counts in the score); a saved or missed one is a penalty event.
    func logPenalty(side: Side, player: UUID? = nil, result: PenaltyResult) {
        switch result {
        case .scored: log(.goal, side: side, player: player, isPenalty: true)
        case .saved: log(.penalty, side: side, player: player, shot: .onTarget)
        case .missed: log(.penalty, side: side, player: player, shot: .off)
        }
    }

    func undo(_ toast: Toast) {
        deleteEvent(toast.eventID)
        self.toast = nil
    }

    func deleteEvent(_ id: UUID) {
        guard let index = state.events.firstIndex(where: { $0.id == id }) else { return }
        let event = state.events.remove(at: index)
        if event.kind == .sub, let out = event.player, let into = event.otherPlayer {
            setStatus(out, .start)
            setStatus(into, .bench)
        }
        if toast?.eventID == id { toast = nil }
    }

    private func setStatus(_ id: UUID, _ status: PlayerStatus) {
        if let index = state.players.firstIndex(where: { $0.id == id }) {
            state.players[index].status = status
        } else if let index = state.opponentPlayers.firstIndex(where: { $0.id == id }) {
            state.opponentPlayers[index].status = status
        }
    }

    // MARK: Clock

    var primaryTitle: String {
        switch state.phase {
        case .notStarted: state.periodStartText(1)
        case .playing: state.isLastPeriod ? "Slutsignal" : state.intervalName
        case .interval:
            state.sport == .football ? "Starta \(state.periodName(state.period + 1))" : state.periodStartText(state.period + 1)
        case .finished: "Ny match"
        }
    }

    var primaryIcon: String {
        switch state.phase {
        case .notStarted, .interval: "play.fill"
        case .playing: state.isLastPeriod ? "flag.checkered" : "pause.circle.fill"
        case .finished: "plus.circle.fill"
        }
    }

    func advancePhase() {
        let now = Date.now
        switch state.phase {
        case .notStarted:
            state.period = 1
            startClock(now)
            addPeriod(state.periodStartText(1), MatchMinute(minute: 1), now)
        case .playing:
            let minute = state.clock(at: now)
            stopClock(state.isLastPeriod ? .finished : .interval)
            addPeriod("\(state.phase == .finished ? "Slutsignal" : state.intervalName) \(state.scoreText)", minute, now)
        case .interval:
            state.period += 1
            startClock(now)
            addPeriod(state.periodStartText(state.period), MatchMinute(minute: (state.period - 1) * state.halfLength + 1), now)
        case .finished:
            break
        }
    }

    func togglePause() {
        let now = Date.now
        if state.isRunning {
            state.accumulated = state.elapsed(at: now)
            state.runningSince = nil
            state.isRunning = false
        } else {
            state.runningSince = now
            state.isRunning = true
        }
    }

    private func startClock(_ now: Date) {
        state.phase = .playing
        state.accumulated = 0
        state.runningSince = now
        state.isRunning = true
    }

    private func stopClock(_ phase: Phase) {
        state.phase = phase
        state.accumulated = 0
        state.runningSince = nil
        state.isRunning = false
    }

    private func addPeriod(_ text: String, _ minute: MatchMinute, _ now: Date) {
        state.events.append(MatchEvent(kind: .period, side: .us, minute: minute, createdAt: now, note: text))
    }

    /// Ends the match at the current score, like Slutsignal, from any phase.
    func endMatch() {
        guard state.phase != .finished else { return }
        let now = Date.now
        let minute = state.phase == .playing ? state.clock(at: now) : MatchMinute(minute: max(1, (state.period - 1) * state.halfLength))
        stopClock(.finished)
        addPeriod("Slutsignal \(state.scoreText)", minute, now)
    }

    /// Throws the current match away. Stop live sharing first so the server copy is deleted.
    func discardMatch() {
        state = .empty
        toast = nil
        goToStart()
    }

    // MARK: Squad

    /// Whether starting a new match would throw away a match that is under way.
    var hasUnfinishedMatch: Bool {
        !state.events.isEmpty && state.phase != .finished
    }

    /// A match that has started or has events and isn't finished, so the start page offers to continue it.
    var hasMatchInProgress: Bool {
        state.phase != .finished && (state.phase != .notStarted || !state.events.isEmpty)
    }

    /// The match in progress, if it is in `sport`: each sport's start page shows only its own.
    func hasMatchInProgress(in sport: Sport) -> Bool {
        hasMatchInProgress && state.sport == sport
    }

    /// Starts a fresh match for `team` with the team's settings and its last used lineup.
    func newMatch(team: Team, opponent: String, isHome: Bool) {
        var players = team.players.sorted { $0.number < $1.number }
        if !players.contains(where: { $0.status == .start }) {
            // No lineup yet (new players are on the bench): the lowest numbers start, so Byte has someone to take off.
            for index in players.indices where players[index].status != .out {
                players[index].status = players[..<index].filter { $0.status == .start }.count < team.playersOnField
                    ? .start : .bench
            }
        }
        state = MatchState(sport: team.sport, teamID: team.id, ourTeam: team.name, opponent: opponent, isHome: isHome,
                           halfLength: team.periodLength, periods: team.periods, playersOnField: team.playersOnField,
                           players: players, events: [], phase: .notStarted,
                           period: 1, isRunning: false, accumulated: 0, runningSince: nil)
        toast = nil
        openMatch()
    }

    var isMatchSaved: Bool { savedMatches.contains { $0.state == state } }

    func saveMatch() {
        guard !isMatchSaved, let payload = try? JSONEncoder().encode(state) else { return }
        let match = SavedMatch(id: UUID(), savedAt: .now, state: state)
        savedMatches.insert(match, at: 0)
        container.mainContext.insert(StoredSavedMatch(id: match.id, savedAt: match.savedAt, payload: payload))
        commit()
    }

    func deleteSavedMatch(_ id: UUID) {
        savedMatches.removeAll { $0.id == id }
        let stored = (try? container.mainContext.fetch(FetchDescriptor<StoredSavedMatch>(predicate: #Predicate { $0.id == id }))) ?? []
        stored.forEach(container.mainContext.delete)
        commit()
    }

    /// Starts a football match from an imported match. Both squads belong to the match, not to Mina lag.
    func startImportedMatch(_ match: ImportedMatch) {
        func squad(_ team: ImportedTeam) -> [Player] {
            team.players.sorted { $0.number < $1.number }.map {
                Player(firstName: $0.firstName, lastName: $0.lastName, number: $0.number, status: $0.starts ? .start : .bench)
            }
        }
        var team = Team.new(.football, name: match.home.name)
        team.players = squad(match.home)
        let starters = match.home.players.filter(\.starts).count
        if Team.formats(.football).contains(starters) {
            team.playersOnField = starters
            team.periodLength = Team.defaultPeriodLength(for: starters)
        }
        sport = .football
        newMatch(team: team, opponent: match.away.name, isHome: true)
        state.opponentPlayers = squad(match.away)
    }

    /// Remembers today's Start/Bänk/Ej med as the team's lineup for next time.
    func saveLineupToTeam() {
        guard let index = teams.firstIndex(where: { $0.id == state.teamID }) else { return }
        for player in state.players {
            if let i = teams[index].players.firstIndex(where: { $0.id == player.id }) {
                teams[index].players[i].status = player.status
            }
        }
    }

    /// Adds a player to today's match and, if asked, to the team's squad.
    func addMatchPlayer(_ player: Player, saveInSquad: Bool) {
        state.players.append(player)
        state.players.sort { $0.number < $1.number }
        if saveInSquad, let index = teams.firstIndex(where: { $0.id == state.teamID }) {
            teams[index].players.append(player)
        }
    }

    func addExampleTeam(_ sport: Sport = .football) {
        let team = sport == .football ? MatchState.exampleTeam() : MatchState.exampleFloorballTeam()
        if !teams.contains(where: { $0.id == team.id }) {
            teams.append(team)
        }
    }

    func reset() {
        addExampleTeam()
        state = .example()
        toast = nil
    }
}
