import Foundation

enum Side: String, Codable, Hashable {
    case us, them
}

/// The sport a team plays and a match is reported in. Everything saved before 1.0.3 is football.
enum Sport: String, Codable, CaseIterable, Identifiable, Hashable {
    case football, floorball

    var id: String { rawValue }

    var label: String {
        switch self {
        case .football: "Fotboll"
        case .floorball: "Innebandy"
        }
    }

    var icon: String {
        switch self {
        case .football: "soccerball"
        case .floorball: "figure.hockey"
        }
    }

    /// The wide picture on the sport picker and the start page.
    var startImage: String {
        switch self {
        case .football: "StartFootball"
        case .floorball: "StartFloorball"
        }
    }

    /// "halvlek" in football, "period" in floorball.
    var periodWord: String { self == .football ? "halvlek" : "period" }
    var periodWordPlural: String { self == .football ? "halvlekar" : "perioder" }

    /// Number of periods a team can choose.
    var periodRange: ClosedRange<Int> { self == .football ? 1...4 : 2...3 }
}

enum PlayerStatus: String, Codable, CaseIterable, Identifiable {
    case start, bench, out

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start: "Start"
        case .bench: "Bänk"
        case .out: "Ej med"
        }
    }
}

struct Player: Identifiable, Equatable, Hashable {
    var id = UUID()
    var firstName: String
    var lastName: String = ""
    var number: Int
    var status: PlayerStatus = .bench

    var name: String { lastName.isEmpty ? firstName : "\(firstName) \(lastName)" }

    /// Splits "Selma Lund" into first and last name at the first space.
    init(id: UUID = UUID(), name: String, number: Int, status: PlayerStatus = .bench) {
        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        self.init(id: id, firstName: parts.first.map(String.init) ?? "", lastName: parts.count > 1 ? String(parts[1]) : "",
                  number: number, status: status)
    }

    init(id: UUID = UUID(), firstName: String, lastName: String = "", number: Int, status: PlayerStatus = .bench) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.number = number
        self.status = status
    }
}

extension Player: Codable {
    private enum CodingKeys: String, CodingKey { case id, firstName, lastName, name, number, status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let number = try c.decode(Int.self, forKey: .number)
        let status = try c.decodeIfPresent(PlayerStatus.self, forKey: .status) ?? .bench
        if let first = try c.decodeIfPresent(String.self, forKey: .firstName) {
            self.init(id: id, firstName: first, lastName: try c.decodeIfPresent(String.self, forKey: .lastName) ?? "",
                      number: number, status: status)
        } else {
            // Saved before first and last name were separate.
            self.init(id: id, name: try c.decode(String.self, forKey: .name), number: number, status: status)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encode(number, forKey: .number)
        try c.encode(status, forKey: .status)
    }
}

/// A team the user reports for, with its squad and default match settings.
struct Team: Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var sport: Sport = .football
    var playersOnField: Int = 9
    var periods: Int = 2
    var periodLength: Int = 25
    var players: [Player] = []

    /// A new team with the usual settings for its sport: 9 mot 9, 2 × 25 in football; 5 mot 5, 3 × 15 in floorball.
    static func new(_ sport: Sport, name: String = "Nytt lag") -> Team {
        switch sport {
        case .football: Team(name: name, sport: .football)
        case .floorball: Team(name: name, sport: .floorball, playersOnField: 5, periods: 3, periodLength: 15)
        }
    }

    static func formats(_ sport: Sport) -> [Int] { sport == .football ? [5, 7, 9, 11] : [3, 4, 5] }
    static func periodLengths(_ sport: Sport) -> [Int] {
        sport == .football ? [10, 12, 15, 20, 25, 30, 35, 40, 45] : [8, 10, 12, 15, 20]
    }

    /// Floorball formats count outfield players, as in "5 mot 5" plus keepers.
    static func formatLabel(_ playersOnField: Int) -> String { "\(playersOnField) mot \(playersOnField)" }

    static func defaultPeriodLength(for playersOnField: Int, sport: Sport = .football) -> Int {
        if sport == .floorball { return playersOnField >= 5 ? 15 : 12 }
        switch playersOnField {
        case ...5: return 15
        case 6...7: return 20
        case 8...9: return 25
        default: return 35
        }
    }

    var summary: String {
        "\(Self.formatLabel(playersOnField)) · \(periods) × \(periodLength) min · \(players.count) spelare"
    }
}

extension Team: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, sport, playersOnField, periods, periodLength, players }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Teams saved before 1.0.3 have no sport and are football teams.
        sport = try c.decodeIfPresent(Sport.self, forKey: .sport) ?? .football
        playersOnField = try c.decode(Int.self, forKey: .playersOnField)
        periods = try c.decode(Int.self, forKey: .periods)
        periodLength = try c.decode(Int.self, forKey: .periodLength)
        players = try c.decode([Player].self, forKey: .players)
    }
}

enum EventKind: String, Codable, Hashable {
    /// `penalty` is a penalty that was saved or missed; a scored penalty is a `goal` with `isPenalty`.
    /// `suspension` is a floorball utvisning.
    case goal, shot, corner, freeKick, yellow, red, sub, save, period, penalty, suspension

    var label: String { label(for: .football) }

    func label(for sport: Sport) -> String {
        switch self {
        case .goal: "Mål"
        case .shot: "Skott"
        case .corner: "Hörna"
        case .freeKick: sport == .floorball ? "Frislag" : "Frispark"
        case .yellow: "Gult kort"
        case .red: "Rött kort"
        case .sub: "Byte"
        case .save: "Räddning"
        case .period: "Period"
        case .penalty: "Straff"
        case .suspension: "Utvisning"
        }
    }

    var icon: String { icon(for: .football) }

    func icon(for sport: Sport) -> String {
        switch self {
        case .goal: sport.icon
        case .shot: "scope"
        case .corner: "flag.fill"
        case .freeKick: sport == .floorball ? "arrowshape.forward.fill" : "figure.soccer"
        case .yellow, .red: "rectangle.portrait.fill"
        case .sub: "arrow.left.arrow.right"
        case .save: "hand.raised.fill"
        case .period: "stopwatch"
        case .penalty: "target"
        case .suspension: "timer"
        }
    }
}

/// How a penalty (straff) ended. A scored penalty is logged as a goal.
enum PenaltyResult: String, CaseIterable, Hashable {
    case scored, saved, missed

    var label: String {
        switch self {
        case .scored: "Mål"
        case .saved: "Räddad"
        case .missed: "Miss"
        }
    }

    var icon: String {
        switch self {
        case .scored: "checkmark.circle.fill"
        case .saved: "hand.raised.fill"
        case .missed: "arrow.up.right"
        }
    }
}

/// A floorball utvisning. Logged only for our own team, like cards in football.
enum Suspension: String, Codable, CaseIterable, Hashable, Identifiable {
    case two, five, ten, match

    var id: String { rawValue }

    var label: String {
        switch self {
        case .two: "2 min"
        case .five: "5 min"
        case .ten: "10 min"
        case .match: "Matchstraff"
        }
    }

    var detail: String {
        switch self {
        case .two: "Lagstraff, laget spelar en färre i 2 minuter"
        case .five: "Lagstraff, laget spelar en färre i 5 minuter"
        case .ten: "Personligt straff, spelaren sitter 10 minuter"
        case .match: "Spelaren utvisas resten av matchen, laget får 5 min"
        }
    }

    /// Minutes the team plays short-handed: a match penalty also costs the team five minutes.
    var teamMinutes: Int {
        switch self {
        case .two: 2
        case .five, .match: 5
        case .ten: 0
        }
    }
}

enum ShotResult: String, Codable, CaseIterable, Hashable {
    case onTarget, off, blocked

    var label: String {
        switch self {
        case .onTarget: "På mål"
        case .off: "Utanför"
        case .blocked: "Täckt"
        }
    }

    var icon: String {
        switch self {
        case .onTarget: "scope"
        case .off: "arrow.up.right"
        case .blocked: "shield.fill"
        }
    }
}

enum Phase: String, Codable {
    /// `interval` is the break after `period` (half-time when there are two periods).
    case notStarted, playing, interval, finished
}

struct MatchMinute: Codable, Equatable {
    var minute: Int
    var added: Int? = nil

    var text: String {
        if let added { return "\(minute)+\(added)'" }
        return "\(minute)'"
    }
}

struct MatchEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: EventKind
    var side: Side
    var minute: MatchMinute
    var createdAt: Date
    /// Scorer, shooter, carded player or player going out.
    var player: UUID? = nil
    /// Assist or player coming in.
    var otherPlayer: UUID? = nil
    var shot: ShotResult? = nil
    var note: String? = nil
    /// A goal scored from a penalty (straff). Missing in matches saved before 1.0.3.
    var isPenalty: Bool? = nil
    /// The kind of utvisning for a `suspension` event.
    var suspension: Suspension? = nil
}

struct MatchState: Equatable {
    var sport: Sport = .football
    var teamID: UUID?
    var ourTeam: String
    var opponent: String
    var isHome: Bool
    /// Minutes per period.
    var halfLength: Int
    var periods: Int = 2
    var playersOnField: Int = 9
    var players: [Player]
    var events: [MatchEvent]
    var phase: Phase
    /// The period being played, or the one just finished during an interval.
    var period: Int = 1
    var isRunning: Bool
    var accumulated: TimeInterval
    var runningSince: Date?
}

extension MatchState: Codable {
    private enum CodingKeys: String, CodingKey {
        case sport, teamID, ourTeam, opponent, isHome, halfLength, periods, playersOnField, players, events
        case phase, period, isRunning, accumulated, runningSince
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Matches saved before 1.0.3 have no sport and are football matches.
        sport = try c.decodeIfPresent(Sport.self, forKey: .sport) ?? .football
        teamID = try c.decodeIfPresent(UUID.self, forKey: .teamID)
        ourTeam = try c.decode(String.self, forKey: .ourTeam)
        opponent = try c.decode(String.self, forKey: .opponent)
        isHome = try c.decode(Bool.self, forKey: .isHome)
        halfLength = try c.decode(Int.self, forKey: .halfLength)
        periods = try c.decodeIfPresent(Int.self, forKey: .periods) ?? 2
        playersOnField = try c.decodeIfPresent(Int.self, forKey: .playersOnField) ?? 9
        players = try c.decode([Player].self, forKey: .players)
        events = try c.decode([MatchEvent].self, forKey: .events)
        isRunning = try c.decode(Bool.self, forKey: .isRunning)
        accumulated = try c.decode(TimeInterval.self, forKey: .accumulated)
        runningSince = try c.decodeIfPresent(Date.self, forKey: .runningSince)
        // Older versions always had two halves with their own phase names.
        switch try c.decode(String.self, forKey: .phase) {
        case "firstHalf": phase = .playing; period = 1
        case "halfTime": phase = .interval; period = 1
        case "secondHalf": phase = .playing; period = 2
        case let raw:
            phase = Phase(rawValue: raw) ?? .notStarted
            period = try c.decodeIfPresent(Int.self, forKey: .period) ?? 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sport, forKey: .sport)
        try c.encodeIfPresent(teamID, forKey: .teamID)
        try c.encode(ourTeam, forKey: .ourTeam)
        try c.encode(opponent, forKey: .opponent)
        try c.encode(isHome, forKey: .isHome)
        try c.encode(halfLength, forKey: .halfLength)
        try c.encode(periods, forKey: .periods)
        try c.encode(playersOnField, forKey: .playersOnField)
        try c.encode(players, forKey: .players)
        try c.encode(events, forKey: .events)
        try c.encode(phase, forKey: .phase)
        try c.encode(period, forKey: .period)
        try c.encode(isRunning, forKey: .isRunning)
        try c.encode(accumulated, forKey: .accumulated)
        try c.encodeIfPresent(runningSince, forKey: .runningSince)
    }
}

extension MatchState {
    var homeSide: Side { isHome ? .us : .them }
    var awaySide: Side { isHome ? .them : .us }

    func teamName(_ side: Side) -> String { side == .us ? ourTeam : opponent }
    func name(_ id: UUID?) -> String? { players.first { $0.id == id }?.name }

    /// First name and shirt number, e.g. "Selma (10)". The only form of a player name that may leave the phone.
    func publicName(_ id: UUID?) -> String? {
        guard let player = players.first(where: { $0.id == id }) else { return nil }
        return "\(player.firstName) (\(player.number))"
    }

    var onField: [Player] { players.filter { $0.status == .start }.sorted { $0.number < $1.number } }
    var bench: [Player] { players.filter { $0.status == .bench }.sorted { $0.number < $1.number } }
    var playingToday: [Player] { players.filter { $0.status != .out }.sorted { $0.number < $1.number } }
    /// Players to pick from for goals and shots: those on the pitch, or everyone playing today if no starters are set.
    var pickable: [Player] { onField.isEmpty ? playingToday : onField }

    func count(_ kind: EventKind, _ side: Side) -> Int {
        events.filter { $0.kind == kind && $0.side == side }.count
    }

    func goals(_ side: Side) -> Int { count(.goal, side) }

    /// Logged shots that were not goals; blocked shots from older versions count as off target.
    func shotCount(_ result: ShotResult, _ side: Side) -> Int {
        events.filter { e in
            guard e.kind == .shot, e.side == side else { return false }
            let onTarget = e.shot == nil || e.shot == .onTarget
            return result == .onTarget ? onTarget : !onTarget
        }.count
    }

    /// Shots include goals and penalties.
    func shots(_ side: Side) -> Int {
        events.filter { $0.side == side && ($0.kind == .goal || $0.kind == .shot || $0.kind == .penalty) }.count
    }

    /// A saved penalty was on target; a missed one was not.
    func shotsOnTarget(_ side: Side) -> Int {
        events.filter {
            $0.side == side && ($0.kind == .goal || (($0.kind == .shot || $0.kind == .penalty) && $0.shot == .onTarget))
        }.count
    }

    /// All penalties taken: scored ones (goals) and saved or missed ones.
    func penalties(_ side: Side) -> Int {
        events.filter { $0.side == side && ($0.kind == .penalty || ($0.kind == .goal && $0.isPenalty == true)) }.count
    }

    func penaltyGoals(_ side: Side) -> Int {
        events.filter { $0.side == side && $0.kind == .goal && $0.isPenalty == true }.count
    }

    /// Our utvisningar, optionally only one kind.
    func suspensions(_ kind: Suspension? = nil) -> Int {
        events.filter { $0.kind == .suspension && $0.side == .us && (kind == nil || $0.suspension == kind) }.count
    }

    var scoreText: String { "\(goals(homeSide))–\(goals(awaySide))" }

    var statsLine: String {
        let shotsText = "Skott \(shots(homeSide))–\(shots(awaySide)) · På mål \(shotsOnTarget(homeSide))–\(shotsOnTarget(awaySide))"
        switch sport {
        case .football:
            return shotsText + " · Hörnor \(count(.corner, homeSide))–\(count(.corner, awaySide))"
        case .floorball:
            return shotsText + " · Utvisningar \(suspensions())"
        }
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard isRunning, let runningSince else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(runningSince))
    }

    var isLastPeriod: Bool { period >= periods }

    func clock(at now: Date) -> MatchMinute {
        switch phase {
        case .notStarted:
            return MatchMinute(minute: 0)
        case .interval:
            return MatchMinute(minute: period * halfLength)
        case .finished:
            return MatchMinute(minute: periods * halfLength)
        case .playing:
            let base = (period - 1) * halfLength
            let full = base + Int(elapsed(at: now) / 60) + 1
            let limit = base + halfLength
            return full > limit ? MatchMinute(minute: limit, added: full - limit) : MatchMinute(minute: full)
        }
    }

    /// "1:a halvlek", "3:e halvlek" in football; "1:a period", "3:e period" in floorball.
    static func periodName(_ number: Int, sport: Sport = .football) -> String {
        "\(number)\(number <= 2 ? ":a" : ":e") \(sport.periodWord)"
    }

    static func halfName(_ number: Int) -> String { periodName(number) }

    func periodName(_ number: Int) -> String { Self.periodName(number, sport: sport) }

    var intervalName: String {
        switch sport {
        case .football: periods == 2 ? "Halvtid" : "Paus"
        case .floorball: "Periodpaus"
        }
    }

    /// The event text when a period after the first starts.
    func periodStartText(_ number: Int) -> String {
        sport == .football && periods == 2 && number == 2 ? "Andra halvlek startar" : "\(periodName(number)) startar"
    }

    var periodText: String {
        switch phase {
        case .notStarted: "Ej startad"
        case .playing: periodName(period) + (isRunning ? "" : " · pausad")
        case .interval: intervalName
        case .finished: "Slut"
        }
    }

    func statusLine(at now: Date) -> String {
        switch phase {
        case .notStarted: "Ej startad"
        case .playing: "Pågår, \(clock(at: now).text)" + (isRunning ? "" : " (pausad)")
        case .interval: intervalName
        case .finished: "Slut"
        }
    }

    func describe(_ e: MatchEvent, publicNames: Bool = false) -> String {
        let name: (UUID?) -> String? = publicNames ? { publicName($0) } : { self.name($0) }
        let who = name(e.player)
        switch e.kind {
        case .goal:
            let penalty = e.isPenalty == true
            guard e.side == .us else { return "Mål \(opponent)" + (penalty ? " (straff)" : "") }
            var text = (penalty ? "Straffmål! " : "Mål! ") + (who ?? "Okänd målskytt")
            if let assist = name(e.otherPlayer) { text += ", assist \(assist)" }
            return text
        case .penalty:
            let base = e.shot == .onTarget ? "Straff räddad" : "Straff miss"
            return base + (who.map { " – \($0)" } ?? "")
        case .suspension:
            let label = e.suspension.map { $0 == .match ? "Matchstraff" : "Utvisning \($0.label)" } ?? "Utvisning"
            return label + (who.map { " – \($0)" } ?? "")
        case .shot:
            // A shot on target that isn't a goal was saved by the other team's keeper.
            let base = e.shot == .off || e.shot == .blocked ? "Skott utanför" : "Skott på mål, räddning"
            return base + (who.map { " – \($0)" } ?? "")
        case .yellow, .red:
            return e.kind.label + (who.map { " – \($0)" } ?? "")
        case .sub:
            return "Byte: \(who ?? "Okänd") ut, \(name(e.otherPlayer) ?? "Okänd") in"
        case .period:
            return e.note ?? ""
        case .corner, .freeKick, .save:
            return e.kind.label(for: sport)
        }
    }

    /// Shared outside the app, so players appear only as first name and shirt number.
    func report(at now: Date) -> String {
        let sorted = events.sorted { $0.createdAt < $1.createdAt }
        var lines = ["\(teamName(homeSide)) – \(teamName(awaySide))  \(scoreText)", statusLine(at: now)]

        func group(_ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("")
            lines.append(contentsOf: items)
        }

        let goalEmoji = sport == .football ? "⚽" : "🥅"
        group(sorted.filter { $0.kind == .goal }.map { e in
            let penalty = e.isPenalty == true ? " (straff)" : ""
            guard e.side == .us else { return "\(goalEmoji) \(e.minute.text) \(opponent)\(penalty)" }
            var text = "\(goalEmoji) \(e.minute.text) \(publicName(e.player) ?? ourTeam)\(penalty)"
            if let assist = publicName(e.otherPlayer) { text += ", assist \(assist)" }
            return text
        })
        group(sorted.filter { $0.kind == .penalty }.map { e in
            let what = e.shot == .onTarget ? "Straff räddad" : "Straff miss"
            let who = e.side == .us ? publicName(e.player) ?? ourTeam : opponent
            return "❌ \(e.minute.text) \(what), \(who)"
        })
        group(sorted.filter { $0.kind == .suspension }.map { e in
            "⛔ \(e.minute.text) \(publicName(e.player) ?? ourTeam), \(e.suspension?.label ?? "utvisning")"
        })
        group(sorted.filter { $0.kind == .yellow || $0.kind == .red }.map { e in
            let emoji = e.kind == .yellow ? "🟨" : "🟥"
            let who = publicName(e.player) ?? ourTeam
            return "\(emoji) \(e.minute.text) \(who)"
        })
        group(sorted.filter { $0.kind == .sub }.map { e in
            "🔁 \(e.minute.text) \(publicName(e.otherPlayer) ?? "Okänd") in, \(publicName(e.player) ?? "Okänd") ut"
        })
        group(sorted.filter { $0.kind == .period }.map { "⏱ \($0.minute.text) \($0.note ?? "")" })
        lines.append("")
        lines.append(statsLine)
        return lines.joined(separator: "\n")
    }
}

extension MatchState {
    /// No team and no match yet, as on first launch.
    static let empty = MatchState(teamID: nil, ourTeam: "", opponent: "", isHome: true, halfLength: 25, periods: 2,
                                  playersOnField: 9, players: [], events: [], phase: .notStarted, period: 1,
                                  isRunning: false, accumulated: 0, runningSince: nil)

    /// Fake squad for the example team. Clearly marked as made up in the UI.
    static let exampleTeamID = UUID(uuidString: "6E6F8B6A-0E1D-4C55-9D7B-3A3E2C9A1F00")!

    static func exampleTeam() -> Team {
        Team(id: exampleTeamID, name: "Ditt lag (exempel)", playersOnField: 9, periods: 2, periodLength: 25,
             players: example().players.map { var p = $0; p.status = .bench; return p })
    }

    static func example(now: Date = .now) -> MatchState {
        let roster: [(Int, String, PlayerStatus)] = [
            (1, "Alva Berg", .start), (2, "Leo Andersson", .start), (3, "Noah Lindqvist", .bench),
            (4, "Ella Nyström", .start), (5, "Hugo Ek", .start), (6, "Maja Holm", .start),
            (7, "Liam Sandberg", .bench), (8, "Wilma Strand", .start), (9, "Elias Forsberg", .start),
            (10, "Selma Lund", .start), (11, "Oscar Wikström", .bench), (12, "Ines Dahl", .bench),
            (13, "William Sjöberg", .bench), (14, "Freja Håkansson", .start), (15, "Theo Björk", .bench),
            (16, "Nora Engström", .out),
        ]
        // Stable ids so the example match and the example team share players.
        let players = roster.map {
            Player(id: UUID(uuidString: String(format: "6E6F8B6A-0E1D-4C55-9D7B-0000000000%02d", $0.0))!,
                   name: $0.1, number: $0.0, status: $0.2)
        }
        func id(_ number: Int) -> UUID { players.first { $0.number == number }!.id }

        let specs: [(Int, EventKind, Side, UUID?, UUID?, ShotResult?, String?)] = [
            (1, .period, .us, nil, nil, nil, "Avspark"),
            (4, .shot, .us, id(9), nil, .onTarget, nil),
            (6, .corner, .us, nil, nil, nil, nil),
            (9, .goal, .us, id(10), id(8), nil, nil),
            (13, .shot, .them, nil, nil, .off, nil),
            (15, .corner, .them, nil, nil, nil, nil),
            (17, .goal, .them, nil, nil, nil, nil),
            (21, .yellow, .us, id(5), nil, nil, nil),
            (25, .period, .us, nil, nil, nil, "Halvtid 1–1"),
            (26, .period, .us, nil, nil, nil, "Andra halvlek startar"),
            (26, .sub, .us, id(7), id(14), nil, nil),
            (28, .shot, .them, nil, nil, .onTarget, nil),
            (31, .goal, .us, id(9), id(14), nil, nil),
            (32, .corner, .us, nil, nil, nil, nil),
        ]
        let events = specs.enumerated().map { index, s in
            MatchEvent(kind: s.1, side: s.2, minute: MatchMinute(minute: s.0),
                       createdAt: now.addingTimeInterval(Double(index - specs.count) * 60),
                       player: s.3, otherPlayer: s.4, shot: s.5, note: s.6)
        }

        return MatchState(teamID: exampleTeamID, ourTeam: "Ditt lag (exempel)", opponent: "Ekbacka IK", isHome: true,
                          halfLength: 25, periods: 2, playersOnField: 9, players: players, events: events,
                          phase: .playing, period: 2, isRunning: true,
                          accumulated: 0, runningSince: now.addingTimeInterval(-500))
    }

    /// Fake floorball team, also clearly marked as made up.
    static let exampleFloorballTeamID = UUID(uuidString: "6E6F8B6A-0E1D-4C55-9D7B-3A3E2C9A1F01")!

    static func exampleFloorballTeam() -> Team {
        Team(id: exampleFloorballTeamID, name: "Ditt innebandylag (exempel)", sport: .floorball, playersOnField: 5,
             periods: 3, periodLength: 15,
             players: exampleFloorball().players.map { var p = $0; p.status = .bench; return p })
    }

    /// A floorball match in the second period with goals, a penalty shot and two utvisningar.
    static func exampleFloorball(now: Date = .now) -> MatchState {
        let roster: [(Int, String, PlayerStatus)] = [
            (1, "Tilde Ek", .start), (3, "Agnes Holm", .start), (5, "Lova Strand", .start),
            (7, "Ebba Lund", .start), (10, "Saga Berg", .start), (12, "Moa Dahl", .start),
            (14, "Vera Björk", .bench), (17, "Elsa Nyström", .bench), (19, "Juni Sandberg", .bench),
            (21, "Alice Wikström", .bench), (23, "Stella Forsberg", .out),
        ]
        let players = roster.map {
            Player(id: UUID(uuidString: String(format: "6E6F8B6A-0E1D-4C55-9D7B-1000000000%02d", $0.0))!,
                   name: $0.1, number: $0.0, status: $0.2)
        }
        func id(_ number: Int) -> UUID { players.first { $0.number == number }!.id }

        typealias Spec = (Int, EventKind, Side, UUID?, UUID?, ShotResult?, String?, Bool?, Suspension?)
        let specs: [Spec] = [
            (1, .period, .us, nil, nil, nil, "Avspark", nil, nil),
            (3, .shot, .us, id(10), nil, .onTarget, nil, nil, nil),
            (5, .goal, .us, id(7), id(10), nil, nil, nil, nil),
            (8, .shot, .them, nil, nil, .off, nil, nil, nil),
            (9, .suspension, .us, id(5), nil, nil, nil, nil, .two),
            (10, .goal, .them, nil, nil, nil, nil, nil, nil),
            (13, .freeKick, .us, nil, nil, nil, nil, nil, nil),
            (15, .period, .us, nil, nil, nil, "Periodpaus 1–1", nil, nil),
            (16, .period, .us, nil, nil, nil, "2:a period startar", nil, nil),
            (17, .sub, .us, id(12), id(14), nil, nil, nil, nil),
            (19, .goal, .us, id(10), nil, nil, nil, true, nil),
            (21, .shot, .them, nil, nil, .onTarget, nil, nil, nil),
            (22, .freeKick, .them, nil, nil, nil, nil, nil, nil),
            (24, .suspension, .us, id(3), nil, nil, nil, nil, .two),
        ]
        let events = specs.enumerated().map { index, s in
            MatchEvent(kind: s.1, side: s.2, minute: MatchMinute(minute: s.0),
                       createdAt: now.addingTimeInterval(Double(index - specs.count) * 60),
                       player: s.3, otherPlayer: s.4, shot: s.5, note: s.6, isPenalty: s.7, suspension: s.8)
        }

        return MatchState(sport: .floorball, teamID: exampleFloorballTeamID, ourTeam: "Ditt innebandylag (exempel)",
                          opponent: "Ekbacka IBK", isHome: true, halfLength: 15, periods: 3, playersOnField: 5,
                          players: players, events: events, phase: .playing, period: 2, isRunning: true,
                          accumulated: 0, runningSince: now.addingTimeInterval(-560))
    }
}
