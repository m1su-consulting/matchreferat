import Foundation
import SwiftData
import Testing
@testable import Matchreferat

@MainActor
private func makeStore(_ state: MatchState? = nil, container: ModelContainer = Persistence.container(inMemory: true),
                       legacy: URL? = nil) -> MatchStore {
    let directory = legacy ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "matchreferat-tests-\(UUID().uuidString)"
    let store = MatchStore(container: container, legacyDirectory: directory, defaults: UserDefaults(suiteName: suite)!)
    if let state { store.state = state }
    return store
}

private func floorballMatch(periods: Int = 3) -> MatchState {
    var match = MatchState.exampleFloorball()
    match.periods = periods
    match.events = []
    match.phase = .notStarted
    match.period = 1
    match.isRunning = false
    match.runningSince = nil
    return match
}

@Suite("Innebandy")
@MainActor
struct FloorballTests {
    @Test func newFloorballTeamHasFloorballDefaults() {
        let team = Team.new(.floorball)
        #expect(team.sport == .floorball)
        #expect(team.periods == 3)
        #expect(team.periodLength == 20)
        #expect(team.playersOnField == 5)
        #expect(Sport.floorball.periodRange == 2...3)
    }

    @Test func newMatchTakesSportFromTeam() {
        let store = makeStore()
        let team = store.addTeam(.floorball)
        store.newMatch(team: team, opponent: "Sjövik IBK", isHome: true)
        #expect(store.state.sport == .floorball)
        #expect(store.state.periods == 3)
    }

    @Test func everyoneCanBePickedInFloorball() {
        var match = MatchState.exampleFloorball()
        match.players[0].status = .bench
        #expect(match.pickable == match.playingToday)
    }

    @Test func newFootballTeamIsElevenASide() {
        let team = Team.new(.football)
        #expect(team.playersOnField == 11)
        #expect(team.periods == 2)
        #expect(team.periodLength == 45)
    }

    @Test func newMatchWithoutLineupStartsLowestNumbers() {
        let store = makeStore()
        var team = Team.new(.floorball)
        team.players = [Player(firstName: "Bea", number: 7), Player(firstName: "Ada", number: 3)]
        store.newMatch(team: team, opponent: "Sjövik IBK", isHome: true)
        // Two new players (on the bench by default) in 5 mot 5: both start, so Byte can pick who goes out.
        #expect(store.state.onField.map(\.firstName) == ["Ada", "Bea"])
        #expect(store.state.bench.isEmpty)
    }

    @Test(arguments: [2, 3])
    func periodsRunInOrder(periods: Int) {
        let store = makeStore(floorballMatch(periods: periods))
        #expect(store.primaryTitle == "Start period 1")
        store.advancePhase()
        #expect(store.state.periodText == "Period 1")
        #expect(store.state.events.last?.note == "Start period 1")
        for next in 2...periods {
            #expect(store.primaryTitle == "Periodpaus")
            store.advancePhase()
            #expect(store.state.phase == .interval)
            #expect(store.state.periodText == "Periodpaus")
            #expect(store.primaryTitle == "Start period \(next)")
            store.advancePhase()
            #expect(store.state.periodText == "Period \(next)")
            #expect(store.state.events.last?.note == "Start period \(next)")
        }
        #expect(store.state.isLastPeriod)
        #expect(store.primaryTitle == "Slutsignal")
        store.advancePhase()
        #expect(store.state.phase == .finished)
        // Never "halvlek" anywhere in a floorball match.
        #expect(!store.state.events.contains { $0.note?.contains("halvlek") == true })
        #expect(!store.state.report(at: .now).contains("halvlek"))
        #expect(!store.state.events.contains { $0.note?.contains("Avspark") == true })
    }

    @Test func eventsUseFloorballTerms() {
        let match = MatchState.exampleFloorball()
        #expect(EventKind.freeKick.label(for: .floorball) == "Frislag")
        #expect(EventKind.freeKick.label(for: .football) == "Frispark")
        let freeKick = match.events.first { $0.kind == .freeKick }!
        #expect(match.describe(freeKick) == "Frislag")
        #expect(MatchState.periodName(3, sport: .floorball) == "Period 3")
    }

    @Test func exampleScoreAndStats() {
        let match = MatchState.exampleFloorball()
        #expect(match.goals(.us) == 2)          // one of them a penalty
        #expect(match.goals(.them) == 1)
        #expect(match.penaltyGoals(.us) == 1)
        #expect(match.shots(.us) == 3)
        #expect(match.shotsOnTarget(.them) == 2)
        #expect(match.suspensions() == 2)
        #expect(match.statsLine == "Skott 3–3 · På mål 3–2 · Utvisningar 2 (4 min)")
        #expect(match.statsLine.count <= 120)   // the Firestore rules allow 120 characters
    }

    @Test func suspensionsAreLoggedForUsWithPlayer() throws {
        let store = makeStore(MatchState.exampleFloorball())
        let saga = try #require(store.state.players.first { $0.number == 10 })
        let before = store.state.suspensions()
        store.log(.suspension, side: .us, player: saga.id, suspension: .five)
        store.log(.suspension, side: .us, player: saga.id, suspension: .match)
        #expect(store.state.suspensions() == before + 2)
        #expect(store.state.suspensions(.match) == 1)
        let event = try #require(store.state.events.last)
        #expect(store.state.describe(event, publicNames: true) == "Matchstraff – Saga (10)")
        #expect(store.toast?.text.hasSuffix("Matchstraff – Saga Berg") == true)
        let five = store.state.events[store.state.events.count - 2]
        #expect(store.state.describe(five) == "Utvisning 5 min – Saga Berg")
        #expect(store.state.report(at: .now).contains("⛔ \(event.minute.text) Saga (10), Matchstraff"))
        #expect(!store.state.report(at: .now).contains("Berg"))
        #expect(store.state.suspensionMinutes == 4 + 5 + 5)
        #expect(store.state.statsLine.hasSuffix("Utvisningar 4 (14 min)"))
        #expect(store.state.report(at: .now).contains("Utvisningar 4 (14 min)"))
        #expect(Suspension.ten.minutes == 10)
        #expect(Suspension.two.teamMinutes == 2 && Suspension.ten.teamMinutes == 0 && Suspension.match.teamMinutes == 5)
    }

    @Test func undoSuspension() throws {
        let store = makeStore(MatchState.exampleFloorball())
        let before = store.state.suspensions()
        store.log(.suspension, side: .us, suspension: .two)
        store.undo(try #require(store.toast))
        #expect(store.state.suspensions() == before)
    }

    @Test func opponentPenaltyCountsAsShotAndGoal() {
        let store = makeStore(MatchState.exampleFloorball())
        store.logPenalty(side: .them, result: .scored)
        #expect(store.state.goals(.them) == 2)
        #expect(store.state.penalties(.them) == 1)
        #expect(store.state.describe(store.state.events.last!) == "Mål Ekbacka IBK (straff)")
        #expect(store.state.report(at: .now).contains("🥅"))
    }
}

@Suite("Straff i fotboll")
@MainActor
struct PenaltyTests {
    @Test func scoredPenaltyIsAGoal() throws {
        let store = makeStore(.example())
        let selma = try #require(store.state.players.first { $0.number == 10 })
        store.logPenalty(side: .us, player: selma.id, result: .scored)
        #expect(store.state.goals(.us) == 3)
        #expect(store.state.scoreText == "3–1")
        #expect(store.state.penalties(.us) == 1)
        #expect(store.state.penaltyGoals(.us) == 1)
        #expect(store.state.shots(.us) == 4)
        let goal = try #require(store.state.events.last)
        #expect(goal.kind == .goal && goal.isPenalty == true)
        #expect(store.state.describe(goal, publicNames: true) == "Straffmål! Selma (10)")
        #expect(store.state.report(at: .now).contains("⚽ \(goal.minute.text) Selma (10) (straff)"))
    }

    @Test func savedAndMissedPenaltiesAreLoggedButNotGoals() throws {
        let store = makeStore(.example())
        let elias = try #require(store.state.players.first { $0.number == 9 })
        store.logPenalty(side: .us, player: elias.id, result: .saved)
        store.logPenalty(side: .them, result: .missed)
        #expect(store.state.scoreText == "2–1")
        #expect(store.state.penalties(.us) == 1)
        #expect(store.state.penalties(.them) == 1)
        #expect(store.state.shots(.us) == 4)
        #expect(store.state.shotsOnTarget(.us) == 4)    // a saved penalty was on target
        #expect(store.state.shotsOnTarget(.them) == 2)  // a missed one was not
        let saved = store.state.events[store.state.events.count - 2]
        #expect(store.state.describe(saved, publicNames: true) == "Straff räddad – Elias (9)")
        #expect(store.state.describe(store.state.events.last!) == "Straff miss")
        #expect(store.toast?.text.hasSuffix("Straff miss (Ekbacka IK)") == true)
        let report = store.state.report(at: .now)
        #expect(report.contains("Straff räddad, Elias (9)"))
        #expect(report.contains("Straff miss, Ekbacka IK"))
    }

    @Test func footballBehaviourIsUnchanged() {
        let match = MatchState.example()
        #expect(match.statsLine == "Skott 3–3 · På mål 3–2 · Hörnor 2–1")
        #expect(match.periodName(2) == "2:a halvlek")
        #expect(match.intervalName == "Halvtid")
        #expect(match.periodStartText(2) == "Andra halvlek startar")
        #expect(match.periodStartText(1) == "Avspark")
        #expect(MatchState.halfName(3) == "3:e halvlek")
        #expect(match.penalties(.us) == 0)
    }
}

@Suite("Migrering till 1.0.3")
@MainActor
struct SportMigrationTests {
    /// A team and a match exactly as 1.0.2 encoded them: no `sport`, no `isPenalty`, no `suspension`.
    private let legacyTeam = #"{"id":"6E6F8B6A-0E1D-4C55-9D7B-3A3E2C9A1F0A","name":"Björkdalens IF","playersOnField":7,"periods":2,"periodLength":20,"players":[{"id":"6E6F8B6A-0E1D-4C55-9D7B-000000000001","firstName":"Alva","lastName":"Berg","number":1,"status":"start"}]}"#
    private let legacyMatch = #"{"teamID":"6E6F8B6A-0E1D-4C55-9D7B-3A3E2C9A1F0A","ourTeam":"Björkdalens IF","opponent":"Sjövik FF","isHome":true,"halfLength":20,"periods":2,"playersOnField":7,"players":[],"events":[{"id":"6E6F8B6A-0E1D-4C55-9D7B-0000000000AA","kind":"goal","side":"us","minute":{"minute":3},"createdAt":700000000}],"phase":"playing","period":1,"isRunning":false,"accumulated":120}"#

    @Test func legacyJSONDecodesAsFootball() throws {
        let team = try JSONDecoder().decode(Team.self, from: Data(legacyTeam.utf8))
        #expect(team.sport == .football)
        #expect(team.periodLength == 20)
        let match = try JSONDecoder().decode(MatchState.self, from: Data(legacyMatch.utf8))
        #expect(match.sport == .football)
        #expect(match.events.first?.isPenalty == nil)
        #expect(match.goals(.us) == 1)
    }

    @Test func swiftDataFrom102BecomesFootball() throws {
        let container = Persistence.container(inMemory: true)
        container.mainContext.insert(StoredTeam(id: UUID(), order: 0, payload: Data(legacyTeam.utf8)))
        container.mainContext.insert(StoredMatch(payload: Data(legacyMatch.utf8)))
        try container.mainContext.save()

        let store = makeStore(container: container)
        #expect(store.teams.count == 1)
        #expect(store.teams(for: .football).count == 1)
        #expect(store.teams(for: .floorball).isEmpty)
        #expect(store.state.sport == .football)
        #expect(store.state.opponent == "Sjövik FF")
        #expect(store.hasMatchInProgress)

        // Saving writes the sport, and it survives a reload.
        store.saveTeams()
        store.save()
        let reloaded = makeStore(container: container)
        #expect(reloaded.teams.first?.sport == .football)
        #expect(reloaded.state.sport == .football)
    }

    @Test func legacyFilesImportAsFootball() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("[\(legacyTeam)]".utf8).write(to: directory.appendingPathComponent("teams.json"))
        try Data(legacyMatch.utf8).write(to: directory.appendingPathComponent("match.json"))
        let store = makeStore(legacy: directory)
        #expect(store.teams.map(\.sport) == [.football])
        #expect(store.state.sport == .football)
    }

    @Test func floorballRoundTrips() throws {
        let match = MatchState.exampleFloorball()
        let decoded = try JSONDecoder().decode(MatchState.self, from: JSONEncoder().encode(match))
        #expect(decoded == match)
        let team = MatchState.exampleFloorballTeam()
        #expect(try JSONDecoder().decode(Team.self, from: JSONEncoder().encode(team)) == team)
    }
}

@Suite("Sportval och filter")
@MainActor
struct SportFilterTests {
    @Test func teamsAreFilteredBySport() {
        let store = makeStore()
        store.addExampleTeam(.football)
        store.addExampleTeam(.floorball)
        _ = store.addTeam(.floorball)
        #expect(store.teams(for: .football).map(\.id) == [MatchState.exampleTeamID])
        #expect(store.teams(for: .floorball).count == 2)
        #expect(store.teams(for: .floorball).allSatisfy { $0.sport == .floorball })
    }

    @Test func deletingFilteredTeamsKeepsTheOtherSport() {
        let store = makeStore()
        store.addExampleTeam(.football)
        store.addExampleTeam(.floorball)
        store.deleteTeams(store.teams(for: .floorball).map(\.id))
        #expect(store.teams.map(\.id) == [MatchState.exampleTeamID])
    }

    @Test func sportChoiceIsRemembered() {
        let defaults = UserDefaults(suiteName: "matchreferat-sport-\(UUID().uuidString)")!
        let container = Persistence.container(inMemory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = MatchStore(container: container, legacyDirectory: directory, defaults: defaults)
        #expect(first.sport == nil)                 // a fresh install shows the sport picker
        first.sport = .floorball
        let second = MatchStore(container: container, legacyDirectory: directory, defaults: defaults)
        #expect(second.sport == .floorball)
        second.sport = nil                          // Byt sport
        #expect(MatchStore(container: container, legacyDirectory: directory, defaults: defaults).sport == nil)
    }

    @Test func matchInProgressShowsOnlyInItsSport() {
        let store = makeStore(MatchState.exampleFloorball())
        #expect(store.hasMatchInProgress(in: .floorball))
        #expect(!store.hasMatchInProgress(in: .football))
        store.state = .example()
        #expect(store.hasMatchInProgress(in: .football))
        #expect(!store.hasMatchInProgress(in: .floorball))
    }

    @Test func ongoingListIsFilteredBySport() {
        let list = OngoingList.loaded(OngoingMatch.examples)
        guard case .loaded(let football) = list.filtered(.football),
              case .loaded(let floorball) = list.filtered(.floorball) else { Issue.record("inte laddad"); return }
        #expect(football.count == 2 && football.allSatisfy { $0.sport == .football })
        #expect(floorball.map(\.homeName) == ["Sjövik IBK"])
        #expect(OngoingList.loading.filtered(.floorball) == .loading)
    }

    @Test func ongoingSportFromFieldOrPeriodText() {
        #expect(OngoingMatch.sport("floorball", periodText: "Halvtid") == .floorball)
        #expect(OngoingMatch.sport(nil, periodText: "Period 2") == .floorball)
        #expect(OngoingMatch.sport(nil, periodText: "Periodpaus") == .floorball)
        #expect(OngoingMatch.sport(nil, periodText: "2:a halvlek") == .football)
        #expect(OngoingMatch.sport("tennis", periodText: "Halvtid") == .football)
    }

    @Test func livePayloadSendsSportOnlyForFloorball() {
        let football = LiveShare.payload(.example(), owner: "u")
        #expect(football["sport"] == nil)          // identical to 1.0.2, so old rules accept it
        #expect(LiveShare.summary(.example())["sport"] == nil)

        let floorball = LiveShare.payload(.exampleFloorball(), owner: "u")
        #expect(floorball["sport"] as? String == "floorball")
        #expect(floorball["periodText"] as? String == "Period 2")
        #expect(LiveShare.summary(.exampleFloorball())["sport"] as? String == "floorball")
        // Without the field for servers whose rules predate it.
        #expect(LiveShare.payload(.exampleFloorball(), owner: "u", sport: false)["sport"] == nil)

        let events = floorball["events"] as? [[String: Any]] ?? []
        #expect(events.contains { $0["type"] as? String == "suspension" && ($0["text"] as? String)?.hasPrefix("Utvisning 2 min") == true })
        #expect(events.contains { $0["text"] as? String == "Straffmål! Saga (10)" })
    }
}

@Suite("Inställningar")
@MainActor
struct SettingsTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "matchreferat-settings-\(UUID().uuidString)")! }

    @Test func screenAndHapticsAreOnByDefault() {
        let d = defaults()
        #expect(AppSettings.keepScreenOn(d))
        #expect(AppSettings.haptics(d))
        d.set(false, forKey: AppSettings.hapticsKey)
        d.set(false, forKey: AppSettings.keepScreenOnKey)
        #expect(!AppSettings.haptics(d))
        #expect(!AppSettings.keepScreenOn(d))
    }

    @Test func startSportIsLastUsedUnlessFixed() {
        let d = defaults()
        #expect(AppSettings.launchSport(d, last: .floorball) == .floorball)
        #expect(AppSettings.launchSport(d, last: nil) == nil)
        d.set("football", forKey: AppSettings.startSportKey)
        #expect(AppSettings.launchSport(d, last: .floorball) == .football)
        d.set("floorball", forKey: AppSettings.startSportKey)
        #expect(AppSettings.launchSport(d, last: nil) == .floorball)
        d.set("last", forKey: AppSettings.startSportKey)
        #expect(AppSettings.launchSport(d, last: .football) == .football)
    }

    @Test func storeOpensTheFixedStartSport() {
        let d = defaults()
        d.set("floorball", forKey: "sport")              // last used
        d.set("football", forKey: AppSettings.startSportKey)
        let store = MatchStore(container: Persistence.container(inMemory: true),
                               legacyDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                               defaults: d)
        #expect(store.sport == .football)
    }
}

@Suite("Import från Min fotboll")
@MainActor
struct MatchImportTests {
    // Fictional page text in the order the page has it.
    private let lines = ["Björkdalens IF", "Björkdalens IF P14", "2-1", "Ekbacka IK", "Lineup",
                         "Matchtrupp", "3", "Alva", "Berg", "7", "Liam", "Af Sandberg Holm", "99", "Noah", "Ek", "Målvakt",
                         "Ersättare", "12", "Ines", "Dahl", "Ledare", "Maja", "Holm", "Tränare",
                         "Matchtrupp", "1", "Saga", "Lund", "Ersättare", "4", "Moa", "Ek", "Ledare", "Ebba", "Ek"]

    @Test func readsBothTeamsWithFullNames() throws {
        let match = try #require(MatchImport.parse(names: ["Björkdalens IF P14", "Ekbacka IK"], lines: lines))
        #expect(match.home.name == "Björkdalens IF P14")
        #expect(match.away.name == "Ekbacka IK")
        #expect(match.home.players.map(\.number) == [3, 7, 99, 12])
        #expect(match.home.players.map(\.firstName) == ["Alva", "Liam", "Noah", "Ines"])
        #expect(match.home.players.map(\.lastName) == ["Berg", "Af Sandberg Holm", "Ek", "Dahl"])
        #expect(match.home.players.map(\.starts) == [true, true, true, false])
        #expect(match.away.players.map(\.firstName) == ["Saga", "Moa"])
    }

    @Test func opponentNamesStayOnThePhone() throws {
        let store = makeStore()
        store.startImportedMatch(players: [ImportedPlayer(number: 3, firstName: "Alva", lastName: "Berg", starts: true)],
                                 opponentPlayers: [ImportedPlayer(number: 9, firstName: "Saga", lastName: "Lund", starts: true)],
                                 teamID: nil, teamName: "Björkdalens IF", opponent: "Ekbacka IK", isHome: true)
        store.log(.goal, side: .them, player: store.state.opponentPlayers[0].id)
        store.log(.goal, side: .us, player: store.state.players[0].id)
        let them = try #require(store.state.events.first)
        #expect(store.state.describe(them) == "Mål Ekbacka IK – Saga Lund")
        #expect(store.state.describe(them, publicNames: true) == "Mål Ekbacka IK")
        let shared = store.state.report(at: .now) + String(describing: LiveShare.payload(store.state, owner: "test"))
        #expect(!shared.contains("Saga") && !shared.contains("Lund") && !shared.contains("Berg"))
    }

    @Test func aPageWithoutLineupIsNotAMatch() {
        #expect(MatchImport.parse(names: [], lines: ["Flöde", "Tabell"]) == nil)
    }

    @Test func importKeepsSurnamesAndLeavesOutOthers() throws {
        let store = makeStore()
        var team = Team.new(.football, name: "Björkdalens IF")
        team.players = [Player(firstName: "Alva", lastName: "Berg", number: 3), Player(firstName: "Leo", number: 5)]
        store.teams.append(team)
        store.startImportedMatch(players: [ImportedPlayer(number: 3, firstName: "Alva", starts: true),
                                           ImportedPlayer(number: 8, firstName: "Ines", starts: false)],
                                 teamID: team.id, teamName: "", opponent: "Ekbacka IK", isHome: false)
        let saved = try #require(store.teams.first { $0.id == team.id })
        #expect(saved.players.map(\.number) == [3, 5, 8])
        #expect(saved.players[0].lastName == "Berg")
        #expect(saved.players.map(\.status) == [.start, .out, .bench])
        #expect(store.state.opponent == "Ekbacka IK")
        #expect(store.state.isHome == false)
    }

    @Test func importWithoutTeamCreatesOneAndUsesTheFormat() throws {
        let store = makeStore()
        let players = (1...7).map { ImportedPlayer(number: $0, firstName: "Spelare", starts: true) }
        store.startImportedMatch(players: players, teamID: nil, teamName: "Nya laget", opponent: "Ekbacka IK", isHome: true)
        let team = try #require(store.teams.first { $0.name == "Nya laget" })
        #expect(team.sport == .football)
        #expect(team.playersOnField == 7)
        #expect(store.state.teamID == team.id)
    }
}
