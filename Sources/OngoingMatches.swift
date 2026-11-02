import SafariServices
import SwiftUI

/// Another person's shared match, as listed in the server's `ongoing` collection.
struct OngoingMatch: Identifiable, Equatable, Sendable {
    var id: String
    var ownerUid: String
    var homeName: String
    var awayName: String
    var homeScore: Int
    var awayScore: Int
    var phase: Phase
    var periodText: String
    var clockLabel: String
    var updatedAt: Date
    var expireAt: Date
    var sport: Sport = .football

    /// Matches nobody has touched for this long are treated as abandoned.
    static let staleAfter: TimeInterval = 6 * 3600

    var title: String { "\(homeName) – \(awayName)" }
    var scoreText: String { "\(homeScore)–\(awayScore)" }

    var statusText: String {
        switch phase {
        case .notStarted: "Inte startad"
        case .playing: "\(clockLabel) · \(periodText)"
        case .interval, .finished: periodText
        }
    }

    /// Parses a Firestore REST list response (`{"documents": [...]}`); bad documents are skipped.
    static func parseList(_ data: Data) -> [OngoingMatch] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documents = json["documents"] as? [[String: Any]] else { return [] }
        return documents.compactMap(parse)
    }

    static func parse(_ document: [String: Any]) -> OngoingMatch? {
        guard let name = document["name"] as? String, let fields = document["fields"] as? [String: Any] else { return nil }
        func string(_ key: String) -> String? { (fields[key] as? [String: Any])?["stringValue"] as? String }
        func int(_ key: String) -> Int? { ((fields[key] as? [String: Any])?["integerValue"] as? String).flatMap { Int($0) } }
        func date(_ key: String) -> Date? { ((fields[key] as? [String: Any])?["timestampValue"] as? String).flatMap(parseTimestamp) }
        guard let id = name.split(separator: "/").last.map(String.init),
              let owner = string("ownerUid"), let home = string("homeName"), let away = string("awayName"),
              let homeScore = int("homeScore"), let awayScore = int("awayScore"),
              let phase = string("phase").flatMap(Phase.init(rawValue:)),
              let updated = date("updatedAt"), let expires = date("expireAt") else { return nil }
        let periodText = string("periodText") ?? ""
        return OngoingMatch(id: id, ownerUid: owner, homeName: home, awayName: away, homeScore: homeScore,
                            awayScore: awayScore, phase: phase, periodText: periodText,
                            clockLabel: string("clockLabel") ?? "", updatedAt: updated, expireAt: expires,
                            sport: sport(string("sport"), periodText: periodText))
    }

    /// The `sport` field, or – from servers whose rules predate it – the period text ("Period 2", "Periodpaus").
    static func sport(_ field: String?, periodText: String) -> Sport {
        if let sport = field.flatMap(Sport.init(rawValue:)) { return sport }
        return periodText.lowercased().contains("period") ? .floorball : .football
    }

    /// Firestore timestamps can have up to nine fractional digits, which `ISO8601DateFormatter` rejects.
    private static func parseTimestamp(_ text: String) -> Date? {
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: whole)
    }

    /// Matches whose `expireAt` passed over an hour ago (a margin for a phone clock that runs fast),
    /// for the app to delete from the server. Never the match this phone is sharing.
    static func expired(_ all: [OngoingMatch], ownMatch: String?, now: Date) -> [String] {
        all.filter { $0.id != ownMatch && $0.expireAt < now.addingTimeInterval(-3600) }.prefix(100).map(\.id)
    }

    /// Other people's matches that are still live, most recently updated first.
    static func visible(_ all: [OngoingMatch], excludingOwner uid: String?, ownMatch: String?, now: Date) -> [OngoingMatch] {
        all.filter { match in
            match.ownerUid != uid && match.id != ownMatch && match.phase != .finished
                && match.expireAt > now && now.timeIntervalSince(match.updatedAt) < staleAfter
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }
}

enum OngoingList: Equatable {
    case loading
    case loaded([OngoingMatch])
    case failed(String)

    /// Only the matches in one sport; each sport's start page lists its own.
    func filtered(_ sport: Sport) -> OngoingList {
        guard case .loaded(let matches) = self else { return self }
        return .loaded(matches.filter { $0.sport == sport })
    }
}

/// "Pågår nu" on the start page: matches others share live on the same server.
struct OngoingSection: View {
    let list: OngoingList
    let serverName: String
    let open: (OngoingMatch) -> Void

    var body: some View {
        Section {
            switch list {
            case .loading:
                HStack {
                    ProgressView()
                    Text("Hämtar matcher…").foregroundStyle(.secondary)
                }
            case .loaded(let matches) where matches.isEmpty:
                Text("Inga matcher pågår just nu")
                    .foregroundStyle(.secondary)
            case .loaded(let matches):
                ForEach(matches) { match in
                    Button { open(match) } label: { OngoingRow(match: match) }
                        .buttonStyle(.plain)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Pågår nu")
        } footer: {
            Text("Matcher som andra delar live via \(serverName).")
        }
    }
}

struct OngoingRow: View {
    let match: OngoingMatch
    @ScaledMetric(relativeTo: .title2) private var scoreSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: match.sport.icon)
                .font(.title3)
                .foregroundStyle(Theme.green)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if match.phase == .playing {
                        Circle().fill(.red).frame(width: 8, height: 8)
                    }
                    Text(match.title).font(.headline)
                }
                Text(match.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(match.scoreText)
                .font(.system(size: scoreSize, weight: .heavy, design: .rounded).monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.sport.label): \(match.title), \(match.homeScore) mot \(match.awayScore), \(match.statusText)")
        .accessibilityHint("Öppnar livesidan")
        .accessibilityAddTraits(.isButton)
    }
}

/// A web page to show in the in-app browser.
struct BrowserPage: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

#if DEBUG
extension OngoingMatch {
    static let examples: [OngoingMatch] = [
        OngoingMatch(id: "AbCdEfGhIjKlMnOpQrStUv12", ownerUid: "anna", homeName: "Ekbacka IK", awayName: "Björkdalens IF P14",
                     homeScore: 1, awayScore: 3, phase: .playing, periodText: "2:a halvlek", clockLabel: "41'",
                     updatedAt: .now, expireAt: .now.addingTimeInterval(7 * 86400)),
        OngoingMatch(id: "ZyXwVuTsRqPoNmLkJiHgFe98", ownerUid: "per", homeName: "Björkdalens IF F12", awayName: "Sjövik FF",
                     homeScore: 0, awayScore: 0, phase: .interval, periodText: "Halvtid", clockLabel: "25'",
                     updatedAt: .now, expireAt: .now.addingTimeInterval(7 * 86400)),
        OngoingMatch(id: "QwErTyUiOpAsDfGhJkLzXc45", ownerUid: "lena", homeName: "Sjövik IBK", awayName: "Björkdalens IBK F13",
                     homeScore: 4, awayScore: 2, phase: .playing, periodText: "Period 3", clockLabel: "38'",
                     updatedAt: .now, expireAt: .now.addingTimeInterval(7 * 86400), sport: .floorball),
    ]
}

#Preview("Pågår nu") {
    List {
        OngoingSection(list: .loaded(OngoingMatch.examples), serverName: "Björkdalens IF") { _ in }
    }
}
#Preview("Pågår nu – tomt") {
    List { OngoingSection(list: .loaded([]), serverName: "Björkdalens IF") { _ in } }
}
#Preview("Pågår nu – laddar och fel") {
    List {
        OngoingSection(list: .loading, serverName: "Björkdalens IF") { _ in }
        OngoingSection(list: .failed("Kunde inte hämta pågående matcher. Dra nedåt för att försöka igen."), serverName: "Björkdalens IF") { _ in }
    }
}
#Preview("Matchrad") { List { OngoingRow(match: OngoingMatch.examples[0]) } }
#endif
