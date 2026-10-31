import Foundation
import Observation

@MainActor
@Observable
final class MatchStore {
    struct Toast: Equatable {
        let id = UUID()
        let eventID: UUID
        let text: String
    }

    var state: MatchState
    var toast: Toast?

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("match.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           var saved = try? JSONDecoder().decode(MatchState.self, from: data) {
            // Older versions logged saves separately and had blocked shots; a save is now
            // implied by a shot on target, and blocked shots count as off target.
            saved.events.removeAll { $0.kind == .save }
            for index in saved.events.indices where saved.events[index].shot == .blocked {
                saved.events[index].shot = .off
            }
            state = saved
        } else {
            state = .example()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
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
        case .firstHalf: "Halvtid"
        case .halfTime: "Starta 2:a halvlek"
        case .secondHalf: "Slutsignal"
        case .finished: "Matchen är slut"
        }
    }

    var primaryIcon: String {
        switch state.phase {
        case .notStarted, .halfTime: "play.fill"
        case .firstHalf: "pause.circle.fill"
        case .secondHalf, .finished: "flag.checkered"
        }
    }

    func advancePhase() {
        let now = Date.now
        switch state.phase {
        case .notStarted:
            startClock(.firstHalf, now)
            addPeriod("Avspark", MatchMinute(minute: 1), now)
        case .firstHalf:
            let minute = state.clock(at: now)
            stopClock(.halfTime)
            addPeriod("Halvtid \(state.scoreText)", minute, now)
        case .halfTime:
            startClock(.secondHalf, now)
            addPeriod("Andra halvlek startar", MatchMinute(minute: state.halfLength + 1), now)
        case .secondHalf:
            let minute = state.clock(at: now)
            stopClock(.finished)
            addPeriod("Slutsignal \(state.scoreText)", minute, now)
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

    private func startClock(_ phase: Phase, _ now: Date) {
        state.phase = phase
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

    func addPlayer(name: String, number: Int) {
        state.players.append(Player(name: name, number: number, status: .bench))
        state.players.sort { $0.number < $1.number }
    }

    func reset() {
        state = .example()
        toast = nil
    }
}
