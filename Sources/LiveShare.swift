import CoreImage.CIFilterBuiltins
import FirebaseAuth
import FirebaseCore
import Observation
import OSLog
import SwiftUI

/// Configures Firebase if the app has a GoogleService-Info.plist (or, in DEBUG, the
/// `-liveEmulator YES` launch argument). Without either the app works fully offline.
/// Firebase is used only for anonymous sign-in; the match is written with the
/// Firestore REST API, authorised by the user's ID token.
enum LiveBackend {
    enum Mode { case unconfigured, production, emulator }

    private(set) static var mode: Mode = .unconfigured
    static let emulatorHost = "127.0.0.1"
    static let emulatorProject = "demo-matchreferat"

    static func configure() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "liveEmulator") {
            let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0000000000000000", gcmSenderID: "1234567890")
            options.projectID = emulatorProject
            options.apiKey = "AIza" + String(repeating: "0", count: 35)
            FirebaseApp.configure(options: options)
            Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
            mode = .emulator
            return
        }
        #endif
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        mode = .production
    }

    private static var projectID: String? {
        mode == .emulator ? emulatorProject : FirebaseApp.app()?.options.projectID
    }

    /// `.../databases/(default)/documents`
    static var documentsURL: URL? {
        guard let projectID else { return nil }
        let host = mode == .emulator ? "http://\(emulatorHost):8080" : "https://firestore.googleapis.com"
        return URL(string: "\(host)/v1/projects/\(projectID)/databases/(default)/documents")
    }

    static func documentName(_ matchID: String) -> String? {
        projectID.map { "projects/\($0)/databases/(default)/documents/matches/\(matchID)" }
    }

    static func viewerURL(for matchID: String) -> URL? {
        switch mode {
        case .unconfigured:
            return nil
        case .emulator:
            return URL(string: "http://\(emulatorHost):5002/m/\(matchID)")
        case .production:
            guard let projectID else { return nil }
            return URL(string: "https://\(projectID).web.app/m/\(matchID)")
        }
    }
}

@MainActor
@Observable
final class LiveShare {
    enum Status: Equatable {
        case unconfigured, off, connecting, live
        case failed(String)
    }

    struct RequestError: Error, CustomStringConvertible {
        let status: Int
        let body: String
        var description: String { "HTTP \(status): \(body)" }
    }

    private(set) var status: Status
    private(set) var matchID: String?
    private(set) var lastSynced: Date?
    private var pending: Task<Void, Never>?

    private static let idKey = "liveMatchID"
    private static let log = Logger(subsystem: "se.matchreferat.app", category: "live")
    private static let lifetime: TimeInterval = 7 * 24 * 3600

    init() {
        guard LiveBackend.mode != .unconfigured else {
            status = .unconfigured
            return
        }
        let saved = UserDefaults.standard.string(forKey: Self.idKey)
        matchID = saved
        status = saved == nil ? .off : .live
    }

    var isConfigured: Bool { status != .unconfigured }
    var isOn: Bool { matchID != nil }
    var url: URL? { matchID.flatMap(LiveBackend.viewerURL) }

    func start(_ state: MatchState) async {
        guard isConfigured, matchID == nil else { return }
        status = .connecting
        do {
            let id = Self.makeID()
            try await write(state, to: id)
            matchID = id
            UserDefaults.standard.set(id, forKey: Self.idKey)
            lastSynced = .now
            status = .live
        } catch {
            Self.log.error("Start failed: \(String(describing: error), privacy: .public)")
            status = .failed("Kunde inte starta live-delningen. Kontrollera nätet och försök igen.")
        }
    }

    /// Stops sharing and deletes the match from the server, so the link stops working.
    func stop() async {
        guard let id = matchID else { return }
        pending?.cancel()
        matchID = nil
        lastSynced = nil
        UserDefaults.standard.removeObject(forKey: Self.idKey)
        status = .off
        do {
            guard let url = LiveBackend.documentsURL?.appendingPathComponent("matches/\(id)") else { return }
            try await send(authorizedRequest(url, method: "DELETE"))
        } catch {
            Self.log.error("Delete failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sends the whole public snapshot, debounced so a burst of taps becomes one write.
    func sync(_ state: MatchState) {
        guard let id = matchID else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            do {
                try await write(state, to: id)
                lastSynced = .now
                status = .live
            } catch {
                Self.log.error("Sync failed: \(String(describing: error), privacy: .public)")
                status = .failed("Senaste uppdateringen gick inte fram. Appen försöker igen vid nästa händelse.")
            }
        }
    }

    /// Replaces the match document in one commit, with `updatedAt` set to the server time.
    private func write(_ state: MatchState, to id: String) async throws {
        guard let documents = LiveBackend.documentsURL, let name = LiveBackend.documentName(id),
              let url = URL(string: documents.absoluteString + ":commit") else { return }
        let user = try await signedInUser()
        let body: [String: Any] = [
            "writes": [[
                "update": ["name": name, "fields": payload(state, owner: user.uid).mapValues(Self.value)],
                "updateTransforms": [["fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"]],
            ]],
        ]
        var request = try await authorizedRequest(url, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await send(request)
    }

    private func signedInUser() async throws -> User {
        if let user = Auth.auth().currentUser { return user }
        return try await Auth.auth().signInAnonymously().user
    }

    private func authorizedRequest(_ url: URL, method: String) async throws -> URLRequest {
        let token = try await signedInUser().getIDToken()
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RequestError(status: status, body: String(decoding: data.prefix(400), as: UTF8.self))
        }
    }

    /// Everything a viewer sees. Players appear only as first name and shirt number,
    /// and the opponent only as a team name. `updatedAt` is added by the server.
    private func payload(_ s: MatchState, owner: String) -> [String: Any] {
        let events = s.events.sorted { $0.createdAt < $1.createdAt }.suffix(200).map { e -> [String: Any] in
            [
                "m": e.minute.text,
                "type": e.kind.rawValue,
                "side": e.side.rawValue,
                "text": s.describe(e, publicNames: true),
                "team": e.kind == .period ? "Match" : s.teamName(e.side),
            ]
        }
        var data: [String: Any] = [
            "v": 1,
            "ownerUid": owner,
            "ourTeam": s.ourTeam,
            "opponent": s.opponent,
            "isHome": s.isHome,
            "homeName": s.teamName(s.homeSide),
            "awayName": s.teamName(s.awaySide),
            "homeScore": s.goals(s.homeSide),
            "awayScore": s.goals(s.awaySide),
            "phase": s.phase.rawValue,
            "running": s.isRunning,
            "accumulated": s.accumulated,
            "halfLength": s.halfLength,
            "period": s.period,
            "periods": s.periods,
            "periodText": s.periodText,
            "clockLabel": s.clock(at: .now).text,
            "stats": s.statsLine,
            "events": Array(events),
            "expireAt": Date.now.addingTimeInterval(Self.lifetime),
        ]
        if s.isRunning, let since = s.runningSince {
            data["startedAt"] = since
        }
        return data
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Encodes a Swift value as a Firestore REST `Value`.
    private static func value(_ v: Any) -> Any {
        switch v {
        case let b as Bool: ["booleanValue": b]
        case let i as Int: ["integerValue": String(i)]
        case let d as Double: ["doubleValue": d]
        case let s as String: ["stringValue": s]
        case let date as Date: ["timestampValue": timestampFormatter.string(from: date)]
        case let array as [Any]: ["arrayValue": ["values": array.map(value)]]
        case let map as [String: Any]: ["mapValue": ["fields": map.mapValues(value)]]
        default: ["nullValue": NSNull()]
        }
    }

    /// 24 random base62 characters (~143 bits), so links cannot be guessed.
    static func makeID() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<24).map { _ in alphabet.randomElement(using: &generator)! })
    }
}

struct LiveRow: View {
    @Environment(LiveShare.self) private var live
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: live.isOn ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                Text(live.isOn ? "LIVE" : "Dela live")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(live.isOn ? Color.white : Theme.green)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(live.isOn ? Color.red : Theme.green.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .accessibilityLabel(live.isOn ? "Livelänken är aktiv, visa länk" : "Dela live")
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            LiveShareSheet().presentationDetents([.large])
        }
        .onAppear {
            // `-demoSheet live` opens the live sheet (used for screenshots).
            if UserDefaults.standard.string(forKey: "demoSheet") == "live" { showSheet = true }
        }
    }
}

struct LiveShareSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if live.isConfigured {
                        configured
                    } else {
                        ContentUnavailableView(
                            "Live-delning är inte konfigurerad än",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("Appen fungerar som vanligt. För att kunna dela en livelänk behöver Firebase sättas upp enligt FIREBASE.md.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Livelänk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var configured: some View {
        Toggle(isOn: Binding(
            get: { live.isOn || live.status == .connecting },
            set: { on in Task { on ? await live.start(store.state) : await live.stop() } }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dela live").font(.headline)
                Text("Alla med länken kan följa matchen. Bara förnamn och tröjnummer visas. Länken slutar fungera 7 dagar efter senaste händelsen, eller direkt när du stänger av.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(Theme.green)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

        switch live.status {
        case .connecting:
            ProgressView("Startar…")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }

        if let url = live.url {
            if let qr = qrImage(url.absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("QR-kod till livelänken")
            }
            Text(url.absoluteString)
                .font(.footnote.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.url = url
                    copied = true
                } label: {
                    Label(copied ? "Kopierad" : "Kopiera länk", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                ShareLink(item: url) {
                    Label("Dela", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Theme.green)
            if let last = live.lastSynced {
                Text("Senast skickad \(last.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
