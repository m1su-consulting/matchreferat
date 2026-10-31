import Foundation
import Observation
import OSLog

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
    /// Selected tab; `-tab 1` as a launch argument opens another tab (used for screenshots).
    var selectedTab = UserDefaults.standard.integer(forKey: "tab")

    private static func fileURL(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }
    private static let matchURL = fileURL("match.json")
    private static let teamsURL = fileURL("teams.json")

    init() {
        var match = MatchState.example()
        if let data = try? Data(contentsOf: Self.matchURL),
           var saved = try? JSONDecoder().decode(MatchState.self, from: data) {
            // Older versions logged saves separately and had blocked shots; a save is now
            // implied by a shot on target, and blocked shots count as off target.
            saved.events.removeAll { $0.kind == .save }
            for index in saved.events.indices where saved.events[index].shot == .blocked {
                saved.events[index].shot = .off
            }
            match = saved
        }

        if let data = try? Data(contentsOf: Self.teamsURL),
           let saved = try? JSONDecoder().decode([Team].self, from: data) {
            teams = saved
        } else if match.teamID == MatchState.exampleTeamID {
            teams = [MatchState.exampleTeam()]
        } else {
            // Before teams existed, the squad lived in the match: it becomes the first team.
            let team = Team(name: match.ourTeam, playersOnField: match.playersOnField, periods: match.periods,
                            periodLength: match.halfLength,
                            players: match.players.map { var p = $0; p.status = .bench; return p })
            teams = [team]
            match.teamID = team.id
        }
        state = match
        if !FileManager.default.fileExists(atPath: Self.teamsURL.path) {
            saveTeams()
            save()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) { Self.write(data, to: Self.matchURL) }
    }

    func saveTeams() {
        if let data = try? JSONEncoder().encode(teams) { Self.write(data, to: Self.teamsURL) }
    }

    private static let log = Logger(subsystem: "se.matchreferat.app", category: "store")

    /// Atomic replace where possible; some environments refuse the rename, so fall back to a plain write.
    private static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Atomic save failed: \(String(describing: error), privacy: .public)")
            do {
                do { try FileManager.default.removeItem(at: url) } catch {
                    log.error("Remove failed: \(String(describing: error), privacy: .public)")
                }
                try data.write(to: url)
            } catch {
                log.error("Save failed: \(String(describing: error), privacy: .public)")
            }
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
        case .interval: "Starta \(state.periods == 2 ? "2:a halvlek" : "period \(state.period + 1)")"
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
            let text = state.periods == 2 ? "Andra halvlek startar" : "Period \(state.period) startar"
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

    /// Starts a fresh match for `team` with this match's settings and lineup.
    func newMatch(team: Team, opponent: String, isHome: Bool, playersOnField: Int, periods: Int,
                  periodLength: Int, players: [Player]) {
        state = MatchState(teamID: team.id, ourTeam: team.name, opponent: opponent, isHome: isHome,
                           halfLength: periodLength, periods: periods, playersOnField: playersOnField,
                           players: players.sorted { $0.number < $1.number }, events: [], phase: .notStarted,
                           period: 1, isRunning: false, accumulated: 0, runningSince: nil)
        toast = nil
        selectedTab = 0
    }

    /// The lineup a new match for `team` starts from: the current match's choices if it is
    /// the same team, otherwise the first players (by squad order) up to the format on the field.
    func suggestedLineup(for team: Team, playersOnField: Int) -> [Player] {
        team.players.enumerated().map { index, player in
            var p = player
            if state.teamID == team.id, let current = state.players.first(where: { $0.id == player.id }) {
                p.status = current.status
            } else {
                p.status = index < playersOnField ? .start : .bench
            }
            return p
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
