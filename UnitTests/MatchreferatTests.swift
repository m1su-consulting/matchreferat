import Foundation
import SwiftData
import Testing
@testable import Matchreferat

@MainActor
private func makeStore(_ state: MatchState? = nil, legacy: URL? = nil) -> MatchStore {
    let directory = legacy ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = MatchStore(container: Persistence.container(inMemory: true), legacyDirectory: directory)
    if let state { store.state = state }
    return store
}

@Suite("Poäng och statistik")
struct ScoreTests {
    @Test func exampleMatchScore() {
        let match = MatchState.example()
        #expect(match.goals(.us) == 2)
        #expect(match.goals(.them) == 1)
        #expect(match.scoreText == "2–1")
        #expect(match.shots(.us) == 3)          // shots include goals
        #expect(match.shotsOnTarget(.them) == 2)
        #expect(match.statsLine == "Skott 3–3 · På mål 3–2 · Hörnor 2–1")
    }

    @Test func awayMatchPutsOpponentFirst() {
        var match = MatchState.example()
        match.isHome = false
        #expect(match.scoreText == "1–2")
        #expect(match.report(at: .now).hasPrefix("Ekbacka IK – \(match.ourTeam)  1–2"))
    }

    @Test func publicNameIsFirstNameAndNumber() throws {
        let match = MatchState.example()
        let selma = try #require(match.players.first { $0.number == 10 })
        #expect(match.publicName(selma.id) == "Selma (10)")
        #expect(!match.report(at: .now).contains("Lund"))
    }

    @Test func shotPickerFallsBackToSquadWithoutStarters() {
        var match = MatchState.example()
        #expect(match.pickable == match.onField)
        match.players = match.players.map { var p = $0; if p.status == .start { p.status = .bench }; return p }
        #expect(match.onField.isEmpty)
        #expect(match.pickable == match.playingToday)
        #expect(!match.pickable.isEmpty)
    }

    @Test func shotWithAndWithoutPlayer() throws {
        let match = MatchState.example()
        let selma = try #require(match.players.first { $0.number == 10 })
        let named = MatchEvent(kind: .shot, side: .us, minute: MatchMinute(minute: 5), createdAt: .now, player: selma.id, shot: .onTarget)
        let anonymous = MatchEvent(kind: .shot, side: .us, minute: MatchMinute(minute: 6), createdAt: .now, shot: .off)
        #expect(match.describe(named, publicNames: true) == "Skott på mål, räddning – Selma (10)")
        #expect(match.describe(anonymous) == "Skott utanför")
    }
}

@Suite("Klocka och halvlekar")
@MainActor
struct ClockTests {
    @Test func endMatchStopsAtCurrentScore() {
        let store = makeStore(.example())
        #expect(store.hasMatchInProgress)
        store.endMatch()
        #expect(store.state.phase == .finished)
        #expect(!store.state.isRunning)
        #expect(store.state.events.last?.note == "Slutsignal 2–1")
        #expect(!store.hasMatchInProgress)
        let count = store.state.events.count
        store.endMatch()
        #expect(store.state.events.count == count)
    }

    @Test func discardMatchRemovesIt() {
        let store = makeStore(.example())
        store.openMatch()
        store.discardMatch()
        #expect(store.state.events.isEmpty)
        #expect(!store.hasMatchInProgress)
        #expect(store.path.isEmpty)
    }

    @Test func threeHalvesWalkThroughBreaks() {
        var state = MatchState.empty
        state.periods = 3
        state.halfLength = 15
        let store = makeStore(state)

        #expect(store.primaryTitle == "Avspark")
        store.advancePhase()
        #expect(store.state.phase == .playing && store.state.period == 1)
        #expect(store.primaryTitle == "Paus")
        store.advancePhase()
        #expect(store.state.phase == .interval)
        #expect(store.primaryTitle == "Starta 2:a halvlek")
        store.advancePhase()
        store.advancePhase()
        #expect(store.primaryTitle == "Starta 3:e halvlek")
        store.advancePhase()
        #expect(store.primaryTitle == "Slutsignal")
        store.advancePhase()
        #expect(store.state.phase == .finished)
        #expect(store.state.events.compactMap(\.note).contains("Andra halvlek startar") == false)
    }

    @Test func twoHalvesUseHalftime() {
        var state = MatchState.empty
        state.periods = 2
        let store = makeStore(state)
        store.advancePhase()
        #expect(store.primaryTitle == "Halvtid")
    }

    @Test func stoppageTime() {
        var state = MatchState.empty
        state.phase = .playing
        state.period = 1
        state.halfLength = 25
        state.isRunning = true
        state.runningSince = Date.now.addingTimeInterval(-(26 * 60 + 10))
        #expect(state.clock(at: .now).text == "25+2'")
    }

    @Test func forgottenClockStopsAtMaxAddedTime() {
        var state = MatchState.empty
        state.phase = .playing
        state.period = 2
        state.halfLength = 25
        state.isRunning = true
        state.runningSince = Date.now.addingTimeInterval(-3 * 24 * 3600)
        #expect(state.clock(at: .now).text == "50+15'")
    }
}

@Suite("Händelser")
@MainActor
struct EventTests {
    @Test func substitutionAndUndo() throws {
        let store = makeStore(.example())
        let out = try #require(store.state.onField.first)
        let into = try #require(store.state.bench.first)
        store.log(.sub, side: .us, player: out.id, otherPlayer: into.id)
        #expect(store.state.players.first { $0.id == out.id }?.status == .bench)
        #expect(store.state.players.first { $0.id == into.id }?.status == .start)
        store.undo(try #require(store.toast))
        #expect(store.state.players.first { $0.id == out.id }?.status == .start)
        #expect(store.state.players.first { $0.id == into.id }?.status == .bench)
    }
}

@Suite("Migrering")
@MainActor
struct MigrationTests {
    @Test func decodesPre1_0Format() throws {
        let json = """
        {"ourTeam":"Ditt lag","opponent":"Ekbacka IK","isHome":true,"halfLength":25,
         "players":[{"id":"\(UUID().uuidString)","name":"Selma Lund","number":10,"status":"start"}],
         "events":[],"phase":"firstHalf","isRunning":false,"accumulated":0}
        """
        let state = try JSONDecoder().decode(MatchState.self, from: Data(json.utf8))
        #expect(state.phase == .playing)
        #expect(state.period == 1)
        #expect(state.periods == 2)
        #expect(state.players.first?.firstName == "Selma")
        #expect(state.players.first?.lastName == "Lund")
    }

    @Test func importsJSONIntoSwiftDataOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var match = MatchState.example()
        match.opponent = "Importerade IF"
        try JSONEncoder().encode(match).write(to: directory.appendingPathComponent("match.json"))
        try JSONEncoder().encode([MatchState.exampleTeam()]).write(to: directory.appendingPathComponent("teams.json"))

        let container = Persistence.container(inMemory: true)
        let first = MatchStore(container: container, legacyDirectory: directory)
        #expect(first.state.opponent == "Importerade IF")
        #expect(first.teams.count == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("match.json").path))

        // A later launch reads SwiftData, not JSON files (here: different files in another folder).
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try JSONEncoder().encode(MatchState.empty).write(to: other.appendingPathComponent("match.json"))
        let second = MatchStore(container: container, legacyDirectory: other)
        #expect(second.state.opponent == "Importerade IF")
        #expect(second.teams.map(\.id) == first.teams.map(\.id))
    }

    @Test func savesTeamsInOrder() {
        let store = makeStore()
        store.teams = [Team(name: "A"), Team(name: "B")]
        store.saveTeams()
        store.teams.reverse()
        store.saveTeams()
        store.teams.removeLast()
        store.saveTeams()
        #expect(store.teams.map(\.name) == ["B"])
    }

    @Test func movesSessionToKeychain() throws {
        let suite = "matchreferat-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); Keychain.set(nil, for: "liveSession") }
        let legacy = Data("{\"token\":\"abc\"}".utf8)
        defaults.set(legacy, forKey: "liveSession")

        LiveShare.migrateLegacySession(defaults: defaults)

        #expect(defaults.data(forKey: "liveSession") == nil)
        #expect(Keychain.data("liveSession") == legacy)
    }
}

@Suite("Live-server")
struct LiveServerTests {
    @Test func parsesAppAndWebLinks() throws {
        let key = "AIzaTESTKEY0123456789abcdefghijklmnop"
        let app = try #require(LiveServer.parse("matchreferat://koppla?p=mitt-lag&k=\(key)&n=Mitt%20lag"))
        #expect(app.projectID == "mitt-lag")
        #expect(app.name == "Mitt lag")
        let web = try #require(LiveServer.parse("https://matchreferat.web.app/koppla#p=mitt-lag&k=\(key)"))
        #expect(web.name == "mitt-lag")
        #expect(web.viewerURL(matchID: "X").absoluteString.hasSuffix("/m/X#p=mitt-lag"))
        #expect(LiveServer.parse("https://example.com") == nil)
        #expect(LiveServer.parse("matchreferat://koppla?p=A&k=short") == nil)
    }

    struct MockClient: HTTPClient {
        let status: Int
        let body: String
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    @Test func anonymousSignUp() async throws {
        let server = LiveServer(projectID: "mitt-lag", apiKey: "AIzaTESTKEY0123456789abcdefghijklmnop", name: "Mitt lag")
        let ok = MockClient(status: 200, body: #"{"localId":"uid1","idToken":"t","refreshToken":"r","expiresIn":"3600"}"#)
        let session = try await AnonymousSession.signUp(server, client: ok)
        #expect(session.uid == "uid1")
        #expect(session.expiresAt > .now)

        let disabled = MockClient(status: 400, body: #"{"error":{"message":"ADMIN_ONLY_OPERATION"}}"#)
        await #expect(throws: AnonymousSession.Failure.self) {
            _ = try await AnonymousSession.signUp(server, client: disabled)
        }
    }

    // MARK: Ongoing matches

    @Test func parsesOngoingList() throws {
        let json = #"""
        {"documents":[
          {"name":"projects/p/databases/(default)/documents/ongoing/AbCdEfGhIjKlMnOpQrStUv12",
           "fields":{"v":{"integerValue":"1"},"ownerUid":{"stringValue":"anna"},
             "homeName":{"stringValue":"Ekbacka IK"},"awayName":{"stringValue":"Björkdalens IF"},
             "homeScore":{"integerValue":"1"},"awayScore":{"integerValue":"3"},"phase":{"stringValue":"playing"},
             "periodText":{"stringValue":"2:a halvlek"},"clockLabel":{"stringValue":"41'"},
             "updatedAt":{"timestampValue":"2026-11-01T15:00:00.123456789Z"},
             "expireAt":{"timestampValue":"2026-11-08T15:00:00Z"}}},
          {"name":"projects/p/databases/(default)/documents/ongoing/broken","fields":{"homeName":{"stringValue":"X"}}}
        ]}
        """#
        let list = OngoingMatch.parseList(Data(json.utf8))
        let match = try #require(list.first)
        #expect(list.count == 1)
        #expect(match.id == "AbCdEfGhIjKlMnOpQrStUv12")
        #expect(match.title == "Ekbacka IK – Björkdalens IF")
        #expect(match.scoreText == "1–3")
        #expect(match.statusText == "41' · 2:a halvlek")
        #expect(OngoingMatch.parseList(Data("{}".utf8)).isEmpty)
    }

    @Test func showsOwnMatchButHidesExpiredAndStale() {
        let now = Date.now
        func match(_ id: String, owner: String = "anna", updated: TimeInterval = -60, expires: TimeInterval = 86400) -> OngoingMatch {
            OngoingMatch(id: id, ownerUid: owner, homeName: "A", awayName: "B", homeScore: 0, awayScore: 0,
                         phase: .playing, periodText: "", clockLabel: "", updatedAt: now + updated, expireAt: now + expires)
        }
        let all = [match("old", updated: -7 * 3600), match("mine", owner: "me", updated: -30), match("expired", expires: -1),
                   match("newer", updated: -10), match("live")]
        let visible = OngoingMatch.visible(all, ownerUid: "me", now: now)
        #expect(visible.map(\.id) == ["newer", "mine", "live"])
        #expect(visible.map(\.isOwn) == [false, true, false])
    }

    @MainActor
    @Test func summaryHasNoPlayersOrEvents() {
        let summary = LiveShare.summary(.example())
        #expect(Set(summary.keys) == ["v", "homeName", "awayName", "homeScore", "awayScore", "phase",
                                      "periodText", "clockLabel", "expireAt"])
        #expect(summary["homeScore"] as? Int == 2)
    }

    /// Answers sign-up, and refuses commits that include the `ongoing` summary, like a server with old rules.
    final class OldRulesServer: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var commits: [Int] = []
        var writeCounts: [Int] { lock.withLock { commits } }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let url = request.url!
            var status = 200
            var body = "{}"
            if url.host() == "identitytoolkit.googleapis.com" {
                body = #"{"localId":"uid1","idToken":"t","refreshToken":"r","expiresIn":"3600"}"#
            } else if url.absoluteString.hasSuffix(":commit") {
                let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                let count = (json?["writes"] as? [Any])?.count ?? 0
                lock.withLock { commits.append(count) }
                if count > 1 { status = 403 }
            }
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    @MainActor
    @Test func sharingWorksOnServerWithOldRules() async throws {
        let suite = "matchreferat-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = LiveServer(projectID: "gamla-regler", apiKey: "AIzaTESTKEY0123456789abcdefghijklmnop", name: "Gamla")
        defaults.set(try JSONEncoder().encode(server), forKey: "liveServer")
        let client = OldRulesServer()
        let live = LiveShare(client: client, defaults: defaults)

        await live.start(.example())
        #expect(live.isOn)
        await live.stop()
        // The first commit (match + summary) is refused and retried alone; later commits skip the summary.
        #expect(client.writeCounts == [2, 1, 1])
    }

    @Test func findsExpiredMatchesToDelete() {
        let now = Date.now
        func match(_ id: String, expires: TimeInterval) -> OngoingMatch {
            OngoingMatch(id: id, ownerUid: "anna", homeName: "A", awayName: "B", homeScore: 0, awayScore: 0,
                         phase: .playing, periodText: "", clockLabel: "", updatedAt: now - 8 * 86400, expireAt: now + expires)
        }
        let all = [match("live", expires: 86400), match("justNow", expires: -60), match("old", expires: -7200),
                   match("mine", expires: -7200)]
        #expect(OngoingMatch.expired(all, ownMatch: "mine", now: now) == ["old"])
    }

    @MainActor
    @Test func expiredShareIsDeletedOnLaunch() async throws {
        let suite = "matchreferat-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = LiveServer(projectID: "utgangen", apiKey: "AIzaTESTKEY0123456789abcdefghijklmnop", name: "Test")
        defaults.set(try JSONEncoder().encode(server), forKey: "liveServer")
        defaults.set("AbCdEfGhIjKlMnOpQrStUv12", forKey: "liveMatchID")
        let live = LiveShare(client: OldRulesServer(), defaults: defaults)
        #expect(live.isOn)

        // Shared with 1.0.2: no expiry saved yet, so it starts counting now.
        await live.expireIfNeeded()
        #expect(live.isOn)
        await live.expireIfNeeded(now: .now.addingTimeInterval(6 * 86400))
        #expect(live.isOn)
        await live.expireIfNeeded(now: .now.addingTimeInterval(8 * 86400))
        #expect(!live.isOn)
        #expect(defaults.string(forKey: "liveMatchID") == nil)
    }
}
