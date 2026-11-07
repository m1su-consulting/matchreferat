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

/// Both teams of a match shared from Safari, waiting for the app to pick it up.
struct ImportedMatch: Codable, Equatable, Identifiable {
    var id = UUID()
    var home: ImportedTeam
    var away: ImportedTeam
}

enum MatchImport {
    /// Shared by the app and the share extension.
    private static let suite = "group.se.matchreferat.app"
    private static let pendingKey = "pendingImport"

    /// Reads the text of a Min fotboll match page, line by line: for each team "Matchtrupp", then number,
    /// first name and surname (and sometimes "Målvakt") per player, then "Ersättare" and "Ledare".
    /// `names` are the two team names from the page's header.
    static func parse(names: [String], lines: [String]) -> ImportedMatch? {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let starts = lines.indices.filter { lines[$0].caseInsensitiveCompare("Matchtrupp") == .orderedSame }
        guard starts.count == 2 else { return nil }
        let home = players(lines[(starts[0] + 1)..<starts[1]])
        let away = players(lines[(starts[1] + 1)...])
        guard !home.isEmpty, !away.isEmpty else { return nil }
        return ImportedMatch(home: ImportedTeam(name: names.first ?? "", players: home),
                             away: ImportedTeam(name: names.dropFirst().first ?? "", players: away))
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

    static func save(_ match: ImportedMatch) {
        UserDefaults(suiteName: suite)?.set(try? JSONEncoder().encode(match), forKey: pendingKey)
    }

    /// The match waiting to be imported, which is removed from the shared storage.
    static func takePending() -> ImportedMatch? {
        guard let defaults = UserDefaults(suiteName: suite), let data = defaults.data(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        return try? JSONDecoder().decode(ImportedMatch.self, from: data)
    }
}
