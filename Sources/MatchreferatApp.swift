import SwiftData
import SwiftUI

@main
struct MatchreferatApp: App {
    @State private var store: MatchStore
    @State private var live: LiveShare

    init() {
        _store = State(initialValue: MatchStore(container: Persistence.container()))
        _live = State(initialValue: LiveShare())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(live)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onChange(of: store.state) {
                    store.save()
                    live.sync(store.state)
                }
                .onChange(of: store.teams) { store.saveTeams() }
                // matchreferat://koppla?p=…&k=…&n=… connects a live server.
                .onOpenURL { url in
                    if url.scheme == "matchreferat" { live.pendingLink = url.absoluteString }
                }
                .task {
                    // Refresh the viewers' copy on launch, e.g. after the app was closed mid-match.
                    if live.isOn { live.sync(store.state) }
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
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }
}

enum Theme {
    static let green = Color(red: 0.13, green: 0.55, blue: 0.29)
    static let rust = Color(red: 0.74, green: 0.34, blue: 0.17)
    static let slab = Color(red: 0.09, green: 0.11, blue: 0.14)
    static let clock = Color(red: 1.0, green: 0.84, blue: 0.2)

    static func color(_ side: Side) -> Color { side == .us ? green : rust }
}

/// Screens pushed on the navigation stack above the start page.
enum Route: Hashable {
    case match
    case team(UUID)
    case liveServer
    case licenses
}

struct RootView: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live

    var body: some View {
        @Bindable var store = store
        let showConnect = Binding(get: { live.pendingLink != nil }, set: { if !$0 { live.pendingLink = nil } })
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
                case .team(let id):
                    if let index = store.teams.firstIndex(where: { $0.id == id }) {
                        TeamEditor(team: $store.teams[index])
                    }
                case .liveServer:
                    LiveServerView()
                case .licenses:
                    LicensesView()
                }
            }
        }
        .tint(Theme.green)
        .sheet(isPresented: showConnect) { NavigationStack { LiveServerView() } }
    }
}
