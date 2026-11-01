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
    var toast: Toast?
    /// The navigation stack above the start page; `-screen match` opens the match page on launch.
    var path: [Route] = LaunchArgument.string("screen") == "match" ? [.match] : []

    func openMatch() { path = [.match] }
    func goToStart() { path.removeAll() }

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private static let log = Logger(subsystem: "se.matchreferat.app", category: "store")

    /// Loads the match and teams from SwiftData. The first time, they are imported from the
    /// JSON files earlier versions wrote to `legacyDirectory`, which are kept as a backup.
    init(container: ModelContainer, legacyDirectory: URL = Persistence.legacyDirectory) {
        self.container = container
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

    // MARK: Events

    func log(_ kind: EventKind, side: Side, player: UUID? = nil, otherPlayer: UUID? = nil, shot: ShotResult? = nil) {
        let event = MatchEvent(kind: kind, side: side, minute: state.clock(at: .now), createdAt: .now,
                               player: player, otherPlayer: otherPlayer, shot: shot)
        if kind == .sub, let out = player, let into = otherPlayer {
            setStatus(out, .bench)
            setStatus(into, .start)
        }
        state.events.append(event)

        var text = "\(event.minute.text) \(state.describe(event))"
        if side == .them && kind != .goal { text += " (\(state.opponent))" }
        toast = Toast(eventID: event.id, text: text)
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
        guard let index = state.players.firstIndex(where: { $0.id == id }) else { return }
        state.players[index].status = status
    }

    // MARK: Clock

    var primaryTitle: String {
        switch state.phase {
        case .notStarted: "Avspark"
        case .playing: state.isLastPeriod ? "Slutsignal" : state.intervalName
        case .interval: "Starta \(MatchState.halfName(state.period + 1))"
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
            addPeriod("Avspark", MatchMinute(minute: 1), now)
        case .playing:
            let minute = state.clock(at: now)
            stopClock(state.isLastPeriod ? .finished : .interval)
            addPeriod("\(state.phase == .finished ? "Slutsignal" : state.intervalName) \(state.scoreText)", minute, now)
        case .interval:
            state.period += 1
            startClock(now)
            let text = state.periods == 2 ? "Andra halvlek startar" : "\(MatchState.halfName(state.period)) startar"
            addPeriod(text, MatchMinute(minute: (state.period - 1) * state.halfLength + 1), now)
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

    // MARK: Squad

    /// Whether starting a new match would throw away a match that is under way.
    var hasUnfinishedMatch: Bool {
        !state.events.isEmpty && state.phase != .finished
    }

    /// A match that has started or has events and isn't finished, so the start page offers to continue it.
    var hasMatchInProgress: Bool {
        state.phase != .finished && (state.phase != .notStarted || !state.events.isEmpty)
    }

    /// Starts a fresh match for `team` with the team's settings and its last used lineup.
    func newMatch(team: Team, opponent: String, isHome: Bool) {
        state = MatchState(teamID: team.id, ourTeam: team.name, opponent: opponent, isHome: isHome,
                           halfLength: team.periodLength, periods: team.periods, playersOnField: team.playersOnField,
                           players: team.players.sorted { $0.number < $1.number }, events: [], phase: .notStarted,
                           period: 1, isRunning: false, accumulated: 0, runningSince: nil)
        toast = nil
        openMatch()
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

    func addExampleTeam() {
        if !teams.contains(where: { $0.id == MatchState.exampleTeamID }) {
            teams.append(MatchState.exampleTeam())
        }
    }

    func reset() {
        addExampleTeam()
        state = .example()
        toast = nil
    }
}
