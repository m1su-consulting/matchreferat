import SwiftUI

/// A shared match to follow: which server it is on, and its id. The match is readable by anyone with the id.
struct LiveMatchLink: Identifiable, Equatable {
    let server: LiveServer
    let matchID: String

    var id: String { matchID }
    var webURL: URL { server.viewerURL(matchID: matchID) }

    init(server: LiveServer, matchID: String) {
        self.server = server
        self.matchID = matchID
    }

    /// Reads a live link, https://matchreferat.web.app/m/<id>#p=…&k=…, which names its server in the fragment.
    init?(url: URL, fallback: LiveServer? = nil) {
        let parts = url.path.split(separator: "/")
        guard url.host == URL(string: LiveServer.viewerHost)?.host, parts.count == 2, parts[0] == "m",
              let server = LiveServer.parse(url.absoluteString) ?? fallback else { return nil }
        self.init(server: server, matchID: String(parts[1]))
    }
}

/// What the live page shows: the document a shared match keeps on the server.
struct LiveMatch: Equatable {
    struct Event: Identifiable, Equatable {
        let id: Int
        let minute: String
        let kind: EventKind?
        let side: Side
        let text: String
        let team: String
    }

    var homeName: String
    var awayName: String
    /// Whether the logging team plays at home, which decides the colours.
    var isHome = true
    var homeScore: Int
    var awayScore: Int
    var phase: Phase
    var running: Bool
    var accumulated: Double
    var startedAt: Date?
    var halfLength: Int
    var period: Int
    var periodText: String
    var clockLabel: String
    var stats: String
    var events: [Event]
    var sport: Sport

    /// Parses a Firestore REST document.
    static func parse(_ data: Data) -> LiveMatch? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: [String: Any]] else { return nil }
        func string(_ key: String, _ from: [String: [String: Any]]) -> String? { from[key]?["stringValue"] as? String }
        func int(_ key: String) -> Int? { (fields[key]?["integerValue"] as? String).flatMap { Int($0) } }
        func double(_ key: String) -> Double? {
            fields[key]?["doubleValue"] as? Double ?? (fields[key]?["integerValue"] as? String).flatMap { Double($0) }
        }
        guard let home = string("homeName", fields), let away = string("awayName", fields),
              let homeScore = int("homeScore"), let awayScore = int("awayScore"),
              let phase = string("phase", fields).flatMap(Phase.init(rawValue:)) else { return nil }
        let items = (fields["events"]?["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]] ?? []
        let events = items.enumerated().compactMap { index, item -> Event? in
            guard let event = (item["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]],
                  let text = string("text", event) else { return nil }
            return Event(id: index, minute: string("m", event) ?? "", kind: string("type", event).flatMap(EventKind.init(rawValue:)),
                         side: string("side", event).flatMap(Side.init(rawValue:)) ?? .us, text: text, team: string("team", event) ?? "")
        }
        let periodText = string("periodText", fields) ?? ""
        return LiveMatch(homeName: home, awayName: away, isHome: fields["isHome"]?["booleanValue"] as? Bool ?? true, homeScore: homeScore, awayScore: awayScore, phase: phase,
                         running: fields["running"]?["booleanValue"] as? Bool ?? false, accumulated: double("accumulated") ?? 0,
                         startedAt: (fields["startedAt"]?["timestampValue"] as? String).flatMap(OngoingMatch.parseTimestamp),
                         halfLength: int("halfLength") ?? 25, period: int("period") ?? 1, periodText: periodText,
                         clockLabel: string("clockLabel", fields) ?? "", stats: string("stats", fields) ?? "", events: events,
                         sport: OngoingMatch.sport(string("sport", fields), periodText: periodText))
    }

    /// The running clock, counted the same way as on the phone that logs the match.
    func clock(at now: Date) -> String {
        guard phase == .playing, running, let startedAt else { return clockLabel }
        var state = MatchState.empty
        state.phase = .playing
        state.period = period
        state.halfLength = halfLength
        state.isRunning = true
        state.accumulated = accumulated
        state.runningSince = startedAt
        return state.clock(at: now).text
    }
}

/// Follows a shared match inside the app, without a browser.
struct LiveMatchView: View {
    @Environment(\.dismiss) private var dismiss
    let link: LiveMatchLink
    var client: any HTTPClient = URLSessionClient()

    @State private var match: LiveMatch?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Följ match")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Klar") { dismiss() }
                    }
                }
        }
        .task {
            #if DEBUG
            // `-demoSheet follow` shows the example match without a server (used for screenshots).
            if LaunchArgument.string("demoSheet") == "follow" {
                let fields = LiveShare.payload(.example(), owner: "demo").mapValues { LiveShare.value($0) }
                match = (try? JSONSerialization.data(withJSONObject: ["fields": fields])).flatMap(LiveMatch.parse)
                return
            }
            #endif
            // Refreshes while the page is open. A finished match doesn't change any more.
            while !Task.isCancelled, match?.phase != .finished {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let match {
            List {
                Section {
                    LiveHeader(match: match)
                        .listRowInsets(EdgeInsets())
                }
                Section("Händelser") {
                    if match.events.isEmpty {
                        Text("Inga händelser än").foregroundStyle(.secondary)
                    }
                    ForEach(match.events.reversed()) { LiveEventRow(event: $0, sport: match.sport) }
                }
                Section {
                    ShareLink(item: link.webURL) {
                        Label("Dela länken", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .refreshable { await load() }
        } else if failed {
            ContentUnavailableView("Matchen hittades inte", systemImage: "antenna.radiowaves.left.and.right.slash",
                                   description: Text("Delningen kan ha stängts av, eller så har länken gått ut."))
        } else {
            ProgressView("Hämtar matchen…")
        }
    }

    private func load() async {
        let url = link.server.documentsURL.appendingPathComponent("matches/\(link.matchID)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: link.server.apiKey)]
        guard let (data, response) = try? await client.data(for: URLRequest(url: components.url!, timeoutInterval: 15)) else {
            if match == nil { failed = true }   // otherwise keep showing the last state on a brief network hiccup
            return
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(code), let loaded = LiveMatch.parse(data) {
            match = loaded
            failed = false
        } else {
            match = nil
            failed = true
        }
    }
}

private struct LiveHeader: View {
    let match: LiveMatch
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var clockSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                team(match.homeName, match.isHome ? .us : .them)
                Text("\(match.homeScore)–\(match.awayScore)")
                    .font(.system(size: scoreSize, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
                team(match.awayName, match.isHome ? .them : .us)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if match.phase == .playing {
                        Text(match.clock(at: context.date))
                            .font(.system(size: clockSize, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.clock)
                    }
                    Text(match.periodText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Text(match.stats)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.slab)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.homeName) \(match.homeScore), \(match.awayName) \(match.awayScore). \(match.periodText). \(match.stats)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func team(_ name: String, _ side: Side) -> some View {
        VStack(spacing: 4) {
            Circle().fill(Theme.color(side)).frame(width: 8, height: 8)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LiveEventRow: View {
    let event: LiveMatch.Event
    let sport: Sport

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.minute)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 48, alignment: .leading)
            if let kind = event.kind {
                Image(systemName: kind.icon(for: sport))
                    .accessibilityHidden(true)
                    .foregroundStyle(kind == .period ? Color.secondary : kind == .yellow ? .yellow : kind == .red ? .red : Theme.color(event.side))
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.text).fontWeight(event.kind == .goal ? .semibold : .regular)
                Text(event.team).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
