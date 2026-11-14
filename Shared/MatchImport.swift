import Foundation

/// A player read from a match page. Names stay on the phone: what is shared is only first name and number.
struct ImportedPlayer: Codable, Equatable, Identifiable {
    var number: Int
    var firstName: String
    var lastName = ""
    var starts: Bool

    var id: Int { number }
}

struct ImportedTeam: Codable, Equatable {
    var name: String
    var players: [ImportedPlayer]
}

/// A match shared from Safari, waiting under Kommande matcher. The squads are empty until they are published.
struct ImportedMatch: Codable, Equatable, Identifiable {
    var id = UUID()
    var home: ImportedTeam
    var away: ImportedTeam
    /// The page on Min fotboll. Sharing the same page again updates this match.
    var url: String?
    var sharedAt = Date()
    /// "floorball" for Innebandy Play. Nil is football from Min fotboll.
    var sport: String?
    /// Kickoff as the page shows it, "17:00". Min fotboll only shows the time, so the day may be missing
    /// until it is set in the app.
    var kickoffTime: String?
    var kickoffDay: Date?

    var hasSquads: Bool { !home.players.isEmpty && !away.players.isEmpty }
    /// Opens the page in Safari, where the login is, and not in the Min fotboll app.
    var safariURL: URL? { url.flatMap { URL(string: "x-safari-" + $0) } }

    /// "lör 15 nov 17:00", "kl. 17:00" without a day, or nil when nothing is known.
    var kickoffText: String? {
        let day = kickoffDay?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale(identifier: "sv_SE")))
        switch (day, kickoffTime) {
        case let (day?, time?): return "\(day) \(time)"
        case let (day?, nil): return day
        case let (nil, time?): return "kl. \(time)"
        case (nil, nil): return nil
        }
    }

    /// Soonest first. Matches without a day come last, in the order they were shared.
    static func byKickoff(_ a: ImportedMatch, _ b: ImportedMatch) -> Bool {
        (a.kickoffDay ?? .distantFuture, a.kickoffTime ?? "99:99") < (b.kickoffDay ?? .distantFuture, b.kickoffTime ?? "99:99")
    }
}

enum MatchImport {
    /// Shared by the app and the share extension.
    private static let suite = "group.se.matchreferat.app"
    private static let plannedKey = "plannedMatches"
    /// A match nobody started is forgotten after this long, so the squads don't stay on the phone.
    private static let keptFor: TimeInterval = 14 * 24 * 3600

    /// Reads the text of a Min fotboll match page, line by line: for each team "Matchtrupp", then number,
    /// first name and surname (and sometimes "Målvakt") per player, then "Ersättare" and "Ledare".
    /// `names` are the two team names from the page's header. Before the squads are out only the names are there.
    static func parse(names: [String], lines: [String], url: String? = nil, kickoff: String? = nil,
                      now: Date = .now) -> ImportedMatch? {
        guard names.count == 2, !names.contains(where: \.isEmpty) else { return nil }
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let starts = lines.indices.filter { lines[$0].caseInsensitiveCompare("Matchtrupp") == .orderedSame }
        var home: [ImportedPlayer] = [], away: [ImportedPlayer] = []
        if starts.count == 2 {
            home = players(lines[(starts[0] + 1)..<starts[1]])
            away = players(lines[(starts[1] + 1)...])
        }
        var match = ImportedMatch(home: ImportedTeam(name: names[0], players: home),
                                  away: ImportedTeam(name: names[1], players: away), url: url)
        (match.kickoffTime, match.kickoffDay) = Self.kickoff(from: kickoff, sharedAt: now)
        return match
    }

    /// Reads Innebandy Play, where the page lists each player with number and full name.
    static func parseFloorball(names: [String], teams: [[[String: String]]], url: String?, kickoff: String? = nil,
                               now: Date = .now) -> ImportedMatch? {
        guard names.count == 2, !names.contains(where: \.isEmpty) else { return nil }
        func squad(_ index: Int) -> [ImportedPlayer] {
            guard teams.indices.contains(index) else { return [] }
            return teams[index].compactMap { player in
                guard let number = player["number"].flatMap(Int.init), let name = player["name"] else { return nil }
                let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
                return ImportedPlayer(number: number, firstName: parts.first ?? "", lastName: parts.count > 1 ? parts[1] : "", starts: true)
            }
        }
        var match = ImportedMatch(home: ImportedTeam(name: names[0], players: squad(0)),
                                  away: ImportedTeam(name: names[1], players: squad(1)), url: url, sport: "floorball")
        (match.kickoffTime, match.kickoffDay) = Self.kickoff(from: kickoff, sharedAt: now)
        return match
    }

    private static let weekdays = [["sön", "sun"], ["mån", "mon"], ["tis", "tue"], ["ons", "wed"], ["tor", "thu"],
                                   ["fre", "fri"], ["lör", "sat"]]
    private static let months = ["jan", "feb", "mar", "apr", "maj|may", "jun", "jul", "aug", "sep", "okt|oct", "nov", "dec"]

    /// Reads kickoff from the page's text: "17:00", "lör 17:00", "Idag 18.30", "15 nov 14:00", "lör 14 nov. 2026 20:00"
    /// or "2026-11-15 14:00".
    /// A day without a year is the next one from when the match was shared. Scores and "Pågår" give nothing.
    static func kickoff(from text: String?, sharedAt: Date) -> (time: String?, day: Date?) {
        guard let text = text?.lowercased(), !text.isEmpty else { return (nil, nil) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: sharedAt)
        var time: String?
        if let match = text.firstMatch(of: /(?:^|[^\d.:])(\d{1,2})[:.](\d{2})(?![\d.:])/),
           let hour = Int(match.1), let minute = Int(match.2), hour < 24, minute < 60 {
            time = String(format: "%02d:%02d", hour, minute)
        }
        func next(month: Int, day: Int, year given: Int? = nil) -> Date? {
            if let given { return calendar.date(from: DateComponents(year: given, month: month, day: day)) }
            let year = calendar.component(.year, from: today)
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            // Shared after the match, or around new year: a date long past is next year's.
            return date < calendar.date(byAdding: .day, value: -30, to: today)!
                ? calendar.date(byAdding: .year, value: 1, to: date) : date
        }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        var day: Date?
        if words.contains("idag") || words.contains("today") {
            day = today
        } else if words.contains("imorgon") || words.contains("tomorrow") {
            day = calendar.date(byAdding: .day, value: 1, to: today)
        } else if let match = text.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            day = calendar.date(from: DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3)))
        } else if let match = text.matches(of: /(\d{1,2})\.?\s*([a-zåäö]{3})[a-zåäö]*\.?(?:\s+(\d{4})(?![:.\d]))?/)
                    .first(where: { match in months.contains { $0.split(separator: "|").contains(Substring(match.2)) } }),
                  let month = months.firstIndex(where: { $0.split(separator: "|").contains(Substring(match.2)) }) {
            day = next(month: month + 1, day: Int(match.1) ?? 1, year: match.3.flatMap { Int($0) })
        } else if let match = text.firstMatch(of: /(?:^|[^\d:.])(\d{1,2})\/(\d{1,2})(?![\d])/) {
            day = next(month: Int(match.2) ?? 1, day: Int(match.1) ?? 1)
        } else if let weekday = weekdays.firstIndex(where: { names in words.contains { word in names.contains { word.hasPrefix($0) } } }) {
            day = calendar.nextDate(after: today.addingTimeInterval(-1), matching: DateComponents(weekday: weekday + 1),
                                    matchingPolicy: .nextTime)
        }
        return (time, day.map { calendar.startOfDay(for: $0) })
    }

    /// A pasted text from Min fotboll's share button: "Hemmalag - Bortalag" and a link. Without names, only the link.
    static func pasted(_ text: String) -> (url: String, names: [String])? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let url = match.url?.absoluteString else { return nil }
        let names = (text.components(separatedBy: .newlines).first ?? "").components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return (url, names.count == 2 && !names.contains(where: { $0.isEmpty || $0.contains("://") }) ? names : [])
    }

    /// Adds a shared match to the list, or updates it if the same page was shared before.
    /// A page without a squad doesn't remove the one already read.
    static func merge(_ match: ImportedMatch, into list: [ImportedMatch], now: Date = .now) -> [ImportedMatch] {
        var list = list.filter { now.timeIntervalSince($0.sharedAt) < keptFor }
        var new = match
        new.sharedAt = now
        if let index = list.firstIndex(where: { $0.url == match.url && match.url != nil }) {
            new.id = list[index].id
            if new.home.players.isEmpty { new.home.players = list[index].home.players }
            if new.away.players.isEmpty { new.away.players = list[index].away.players }
            // A page that doesn't show the day (or the time) keeps what was read or set before.
            if new.kickoffTime == nil { new.kickoffTime = list[index].kickoffTime }
            if new.kickoffDay == nil { new.kickoffDay = list[index].kickoffDay }
            list[index] = new
        } else {
            list.append(new)
        }
        return list
    }

    static func planned() -> [ImportedMatch] {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: plannedKey),
              let list = try? JSONDecoder().decode([ImportedMatch].self, from: data) else { return [] }
        return list.filter { Date.now.timeIntervalSince($0.sharedAt) < keptFor }
    }

    static func add(_ match: ImportedMatch) {
        store(merge(match, into: planned()))
    }

    /// Saves a change made in the app, such as the kickoff, to a match waiting under Kommande matcher.
    static func update(_ match: ImportedMatch) {
        store(planned().map { $0.id == match.id ? match : $0 })
    }

    static func remove(_ id: UUID) {
        store(planned().filter { $0.id != id })
    }

    private static func store(_ list: [ImportedMatch]) {
        UserDefaults(suiteName: suite)?.set(try? JSONEncoder().encode(list), forKey: plannedKey)
    }

    private static let headings: Set<String> = ["ersättare", "ledare", "matchtrupp"]

    private static func players(_ lines: ArraySlice<String>) -> [ImportedPlayer] {
        var result: [ImportedPlayer] = []
        var starts = true
        var index = lines.startIndex
        while index < lines.endIndex {
            let line = lines[index]
            if line.caseInsensitiveCompare("Ledare") == .orderedSame { break }
            if line.caseInsensitiveCompare("Ersättare") == .orderedSame {
                starts = false
            } else if let number = Int(line), number >= 0, index + 1 < lines.endIndex, Int(lines[index + 1]) == nil {
                // Number, first name, then the surname until the next number or heading; "Målvakt" is a label.
                var parts: [String] = []
                var next = index + 2
                while next < lines.endIndex, Int(lines[next]) == nil, !headings.contains(lines[next].lowercased()) {
                    if lines[next].caseInsensitiveCompare("Målvakt") != .orderedSame { parts.append(lines[next]) }
                    next += 1
                }
                result.append(ImportedPlayer(number: number, firstName: lines[index + 1],
                                             lastName: parts.joined(separator: " "), starts: starts))
                index = next
                continue
            }
            index += 1
        }
        return result
    }
}
