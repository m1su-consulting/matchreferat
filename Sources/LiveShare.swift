import CoreImage.CIFilterBuiltins
import Observation
import OSLog
import SwiftUI

/// A Firebase project that receives shared matches. The app has no built-in server: the
/// user connects one with a link (their own, or one they were given) and can disconnect it.
struct LiveServer: Codable, Equatable {
    var projectID: String
    var apiKey: String
    var name: String

    static let viewerHost = "https://matchreferat.web.app"

    /// `matchreferat://koppla?p=…&k=…&n=…` opens the app and connects it.
    var appLink: URL {
        var c = URLComponents()
        c.scheme = "matchreferat"
        c.host = "koppla"
        c.queryItems = [URLQueryItem(name: "p", value: projectID), URLQueryItem(name: "k", value: apiKey),
                        URLQueryItem(name: "n", value: name)]
        return c.url!
    }

    /// The same link as a web page that works anywhere and shows a QR code.
    var webLink: URL {
        URL(string: "\(Self.viewerHost)/koppla#\(fragment)&n=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")")!
    }

    /// Server details go in the fragment, which browsers never send to the web server.
    private var fragment: String { "p=\(projectID)&k=\(apiKey)" }

    func viewerURL(matchID: String) -> URL {
        URL(string: "\(Self.viewerHost)/m/\(matchID)#\(fragment)")!
    }

    /// Accepts the app link, the web link, or just the `p=…&k=…` part.
    static func parse(_ text: String) -> LiveServer? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var pairs = trimmed
        if let url = URL(string: trimmed), url.scheme != nil {
            pairs = [url.query, url.fragment].compactMap { $0 }.joined(separator: "&")
        }
        var values: [String: String] = [:]
        for pair in pairs.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { values[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
        }
        guard let project = values["p"], let key = values["k"],
              project.range(of: "^[a-z0-9-]{4,40}$", options: .regularExpression) != nil,
              key.range(of: "^[A-Za-z0-9_-]{20,60}$", options: .regularExpression) != nil else { return nil }
        let name = values["n"].flatMap { $0.isEmpty ? nil : $0 } ?? project
        return LiveServer(projectID: project, apiKey: key, name: String(name.prefix(40)))
    }

    var documentsURL: URL {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents")!
    }

    func documentName(_ matchID: String) -> String {
        "projects/\(projectID)/databases/(default)/documents/matches/\(matchID)"
    }
}

/// Anonymous Firebase sign-in over REST (Identity Toolkit and Secure Token APIs), so the app
/// needs no Firebase SDK and no built-in project.
struct AnonymousSession: Codable {
    var projectID: String
    var uid: String
    var idToken: String
    var refreshToken: String
    var expiresAt: Date

    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func signUp(_ server: LiveServer) async throws -> AnonymousSession {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(server.apiKey)")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let json = try await fetchJSON(request)
        guard let uid = json["localId"] as? String, let token = json["idToken"] as? String,
              let refresh = json["refreshToken"] as? String else { throw Failure(message: "Oväntat svar från inloggningen") }
        let expires = Double(json["expiresIn"] as? String ?? "3600") ?? 3600
        return AnonymousSession(projectID: server.projectID, uid: uid, idToken: token, refreshToken: refresh,
                                expiresAt: .now.addingTimeInterval(expires - 120))
    }

    func refreshed(_ server: LiveServer) async throws -> AnonymousSession {
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(server.apiKey)")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=refresh_token&refresh_token=\(refreshToken)".utf8)
        let json = try await Self.fetchJSON(request)
        guard let token = json["id_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw Failure(message: "Oväntat svar vid förnyad inloggning")
        }
        let expires = Double(json["expires_in"] as? String ?? "3600") ?? 3600
        return AnonymousSession(projectID: projectID, uid: json["user_id"] as? String ?? uid, idToken: token,
                                refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires - 120))
    }

    private static func fetchJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            let code = ((json["error"] as? [String: Any])?["message"] as? String) ?? "okänt fel"
            throw Failure(message: code)
        }
        return json
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
    private(set) var server: LiveServer?
    private(set) var matchID: String?
    private(set) var lastSynced: Date?
    /// A connection link opened from outside the app, waiting for the user to confirm.
    var pendingLink: String?
    private var session: AnonymousSession?
    private var pending: Task<Void, Never>?

    private static let idKey = "liveMatchID"
    private static let serverKey = "liveServer"
    private static let sessionKey = "liveSession"
    private static let log = Logger(subsystem: "se.matchreferat.app", category: "live")
    private static let lifetime: TimeInterval = 7 * 24 * 3600

    init() {
        let defaults = UserDefaults.standard
        let savedServer = defaults.data(forKey: Self.serverKey).flatMap { try? JSONDecoder().decode(LiveServer.self, from: $0) }
        server = savedServer
        session = defaults.data(forKey: Self.sessionKey).flatMap { try? JSONDecoder().decode(AnonymousSession.self, from: $0) }
        if savedServer == nil {
            // Matches shared before servers were configurable can't be reached any more.
            defaults.removeObject(forKey: Self.idKey)
            status = .unconfigured
            return
        }
        let saved = defaults.string(forKey: Self.idKey)
        matchID = saved
        status = saved == nil ? .off : .live
    }

    var isConfigured: Bool { server != nil }
    var isOn: Bool { matchID != nil }
    var url: URL? {
        guard let server, let matchID else { return nil }
        return server.viewerURL(matchID: matchID)
    }

    // MARK: Server

    /// Signs in to the server to check it, then remembers it.
    func connect(_ newServer: LiveServer) async throws {
        let newSession = try await AnonymousSession.signUp(newServer)
        if isOn { await stop() }
        server = newServer
        session = newSession
        persist()
        status = .off
    }

    func disconnect() async {
        if isOn { await stop() }
        server = nil
        session = nil
        persist()
        status = .unconfigured
    }

    /// Checks sign-in, that Firestore exists and that the Matchreferat rules are deployed.
    func test(_ candidate: LiveServer? = nil) async -> Result<String, AnonymousSession.Failure> {
        guard let target = candidate ?? server else { return .failure(.init(message: "Ingen server kopplad")) }
        do {
            let testSession = try await AnonymousSession.signUp(target)
            let probe = target.documentsURL.appendingPathComponent("matches/\(Self.makeID())")
            var request = URLRequest(url: probe, timeoutInterval: 15)
            request.setValue("Bearer \(testSession.idToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(decoding: data, as: UTF8.self)
            switch code {
            case 404 where body.contains("does not exist") && body.contains("database"):
                return .failure(.init(message: "Inloggningen fungerar, men Firestore-databasen är inte skapad."))
            case 404:
                return .success("Allt fungerar: inloggning, databas och säkerhetsregler.")
            case 403:
                return .failure(.init(message: "Inloggningen fungerar, men säkerhetsreglerna för Matchreferat är inte inlagda."))
            default:
                return .failure(.init(message: "Databasen svarade med kod \(code)."))
            }
        } catch let failure as AnonymousSession.Failure {
            let text = failure.message.contains("ADMIN_ONLY_OPERATION") || failure.message.contains("OPERATION_NOT_ALLOWED")
                ? "Anonym inloggning är inte påslagen i Firebase-projektet."
                : failure.message.contains("API_KEY") || failure.message.contains("API key")
                ? "API-nyckeln stämmer inte."
                : "Inloggningen misslyckades (\(failure.message))."
            return .failure(.init(message: text))
        } catch {
            return .failure(.init(message: "Ingen kontakt med servern. Kontrollera nätet."))
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(server.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.serverKey)
        defaults.set(session.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.sessionKey)
    }

    // MARK: Sharing

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
        status = isConfigured ? .off : .unconfigured
        guard let server else { return }
        do {
            try await send(authorizedRequest(server.documentsURL.appendingPathComponent("matches/\(id)"), method: "DELETE"))
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
        guard let server, let url = URL(string: server.documentsURL.absoluteString + ":commit") else { return }
        let current = try await validSession()
        let body: [String: Any] = [
            "writes": [[
                "update": ["name": server.documentName(id), "fields": payload(state, owner: current.uid).mapValues(Self.value)],
                "updateTransforms": [["fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"]],
            ]],
        ]
        var request = try await authorizedRequest(url, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await send(request)
    }

    /// The stored anonymous session for the connected server, refreshed when it is about to expire.
    private func validSession() async throws -> AnonymousSession {
        guard let server else { throw AnonymousSession.Failure(message: "Ingen server kopplad") }
        if let session, session.projectID == server.projectID {
            if session.expiresAt > .now { return session }
            if let renewed = try? await session.refreshed(server) {
                self.session = renewed
                persist()
                return renewed
            }
        }
        let fresh = try await AnonymousSession.signUp(server)
        session = fresh
        persist()
        return fresh
    }

    private func authorizedRequest(_ url: URL, method: String) async throws -> URLRequest {
        let token = try await validSession().idToken
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
            if LaunchArgument.string("demoSheet") == "live" { showSheet = true }
        }
    }
}

struct LiveShareSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showServer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if live.isConfigured {
                        configured
                    } else {
                        ContentUnavailableView {
                            Label("Ingen live-server kopplad", systemImage: "antenna.radiowaves.left.and.right.slash")
                        } description: {
                            Text("För att dela en livelänk behöver appen en live-server: en gratis Firebase-databas som du skapar själv, eller en kopplingslänk från någon som redan har en.")
                        } actions: {
                            Button("Koppla live-server") { showServer = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.green)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Livelänk")
            .sheet(isPresented: $showServer) { NavigationStack { LiveServerView() } }
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

/// Connect, test and disconnect the live server.
struct LiveServerView: View {
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var working = false
    @State private var result: (ok: Bool, text: String)?
    @State private var confirmDisconnect = false
    @State private var handledPending = false

    var body: some View {
        Form {
            if let server = live.server {
                Section {
                    LabeledContent("Server", value: server.name)
                    LabeledContent("Projekt", value: server.projectID)
                    Button("Testa anslutningen") { Task { await runTest(nil) } }
                        .disabled(working)
                    ShareLink(item: server.webLink) { Label("Dela kopplingslänken", systemImage: "square.and.arrow.up") }
                } header: {
                    Text("Kopplad")
                } footer: {
                    Text("Ge bara kopplingslänken till personer du litar på. Deras delade matcher hamnar i den här servern.")
                }
                Section {
                    Button("Koppla från", role: .destructive) { confirmDisconnect = true }
                }
            } else {
                Section {
                    TextField("Klistra in kopplingslänk", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    Button("Koppla") { Task { await connect() } }
                        .disabled(working || LiveServer.parse(link) == nil)
                } header: {
                    Text("Koppla live-server")
                } footer: {
                    Text("Livelänken kräver en egen gratis Firebase-databas, eller en kopplingslänk från någon som har en. Öppnar du länken på telefonen kopplas appen automatiskt.")
                }
                Section {
                    Link(destination: URL(string: "\(LiveServer.viewerHost)/egen-server")!) {
                        Label("Så skapar du en egen live-server", systemImage: "book")
                    }
                }
            }
            if working {
                Section { ProgressView("Kontrollerar…") }
            } else if let result {
                Section {
                    Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.ok ? Theme.green : .orange)
                }
            }
        }
        .navigationTitle("Live-server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Klar") { dismiss() } }
        }
        .alert("Koppla från live-servern?", isPresented: $confirmDisconnect) {
            Button("Koppla från", role: .destructive) { Task { await live.disconnect(); result = nil } }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("En pågående livelänk stängs av. Du kan koppla igen med kopplingslänken.")
        }
        .onAppear {
            // The sheet for an opened link stays up until dismissed, so handle the link only once.
            if !handledPending, let pending = live.pendingLink {
                handledPending = true
                if let server = LiveServer.parse(pending), server != live.server {
                    link = pending
                    if live.server == nil { Task { await connect() } }
                }
            }
        }
    }

    private func runTest(_ candidate: LiveServer?) async {
        working = true
        defer { working = false }
        switch await live.test(candidate) {
        case .success(let text): result = (true, text)
        case .failure(let failure): result = (false, failure.message)
        }
    }

    private func connect() async {
        guard let server = LiveServer.parse(link) else { return }
        working = true
        defer { working = false }
        let check = await live.test(server)
        guard case .success = check else {
            if case .failure(let failure) = check { result = (false, failure.message) }
            return
        }
        do {
            try await live.connect(server)
            result = (true, "Kopplad till \(server.name). Du kan nu dela matcher live.")
            link = ""
        } catch {
            result = (false, "Kunde inte koppla: \(error)")
        }
    }
}
