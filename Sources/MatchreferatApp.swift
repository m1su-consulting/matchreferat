import SwiftData
import SwiftUI

@main
struct MatchreferatApp: App {
    @State private var store: MatchStore
    @State private var live: LiveShare
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _store = State(initialValue: MatchStore(container: Persistence.container()))
        _live = State(initialValue: LiveShare())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(live)
                .onChange(of: store.state) {
                    store.save()
                    live.sync(store.state)
                }
                .onChange(of: store.teams) { store.saveTeams() }
                // matchreferat://koppla?p=…&k=…&n=… connects a live server.
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task { await live.expireIfNeeded() }
                        store.refreshPlanned()
                    }
                }
                .onOpenURL { url in
                    // The custom scheme and the web links, which open the app when it is installed.
                    if let match = LiveMatchLink(url: url, fallback: live.server) {
                        live.openedMatch = match
                    } else if url.scheme == "matchreferat" || url.path == "/koppla" {
                        live.pendingLink = url.absoluteString
                    }
                }
                .task {
                    store.refreshPlanned()
                    // A share older than 7 days is deleted. Otherwise refresh the viewers' copy, e.g. after
                    // the app was closed mid-match; a finished match isn't refreshed, so it still expires.
                    await live.expireIfNeeded()
                    if live.isOn && store.state.phase != .finished { live.sync(store.state) }
                    #if DEBUG
                    // `-demoScreenshots YES` shows a fictional team mid-match (App Store screenshots), with
                    // `-sport floorball` a floorball team.
                    if UserDefaults.standard.bool(forKey: "demoScreenshots") {
                        let floorball = store.sport == .floorball
                        var team = floorball ? MatchState.exampleFloorballTeam() : MatchState.exampleTeam()
                        team.name = floorball ? "Björkdalens IBK" : "Björkdalens IF"
                        var other = floorball ? MatchState.exampleTeam() : MatchState.exampleFloorballTeam()
                        other.name = floorball ? "Björkdalens IF" : "Björkdalens IBK"
                        var match = floorball ? MatchState.exampleFloorball() : MatchState.example()
                        match.ourTeam = team.name
                        store.teams = [team, other]
                        store.state = match
                    }
                    // `-demoLive YES` starts sharing on launch (used for emulator tests).
                    if UserDefaults.standard.bool(forKey: "demoLive") && !live.isOn {
                        await live.start(store.state)
                    }
                    // `-demoEvent YES` logs an opponent corner, `-demoTeamName X` renames the first team,
                    // `-demoLiveOff YES` turns live sharing off (used for device tests).
                    if UserDefaults.standard.bool(forKey: "demoEvent") { store.log(.corner, side: .them) }
                    if let name = UserDefaults.standard.string(forKey: "demoTeamName"), !store.teams.isEmpty {
                        store.teams[0].name = name
                    }
                    if UserDefaults.standard.bool(forKey: "demoLiveOff") { await live.stop() }
                    // `-demoNewMatch "Lag"` runs the Ny match flow on launch (used for tests).
                    if let opponent = UserDefaults.standard.string(forKey: "demoNewMatch"), let team = store.teams.first {
                        await NewMatchSheet.startNewMatch(store: store, live: live, team: team, opponent: opponent,
                                                          isHome: false)
                    }
                    #endif
                }
        }
    }
}

/// Launch arguments such as `-screen match` used for screenshots and tests; ignored in Release builds.
enum LaunchArgument {
    static func string(_ key: String) -> String? {
        #if DEBUG
        // Only the launch arguments, not saved settings that share the key (the remembered sport is "sport").
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
        #else
        nil
        #endif
    }
}

enum Theme {
    /// Our team and the app's main colour; a little lighter in dark mode so numbers stay readable.
    static let accent = adaptive(light: (0.145, 0.388, 0.922), dark: (0.231, 0.51, 0.965))
    /// The other team. Blue against orange can also be told apart with red-green colour blindness.
    static let opponent = adaptive(light: (0.918, 0.345, 0.047), dark: (0.984, 0.573, 0.235))
    static let slab = Color(red: 0.09, green: 0.11, blue: 0.14)
    static let clock = Color(red: 1.0, green: 0.84, blue: 0.2)

    static func color(_ side: Side) -> Color { side == .us ? accent : opponent }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// Screens pushed on the navigation stack above the start page.
enum Route: Hashable {
    case match
    case liveServer
    case licenses
    case settings
    case savedMatch(UUID)
    case help
}

struct RootView: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live

    var body: some View {
        @Bindable var store = store
        let showConnect = Binding(get: { live.pendingLink != nil }, set: { if !$0 { live.pendingLink = nil } })
        @Bindable var live = live
        NavigationStack(path: $store.path) {
            Group {
                if store.sport == nil { SportPickerView() } else { StartView() }
            }
            .animation(.default, value: store.sport)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .match:
                    MatchView()
                        .toolbar(.hidden, for: .navigationBar)
                case .liveServer:
                    LiveServerView()
                case .licenses:
                    LicensesView()
                case .settings:
                    SettingsView()
                case .help:
                    HelpView()
                case .savedMatch(let id):
                    if let match = store.savedMatches.first(where: { $0.id == id }) {
                        SavedMatchView(match: match)
                    }
                }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: showConnect) { NavigationStack { LiveServerView() } }
        .sheet(item: $live.openedMatch) { LiveMatchView(link: $0) }
    }
}
