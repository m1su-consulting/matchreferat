import SwiftUI

@main
struct MatchreferatApp: App {
    @State private var store: MatchStore
    @State private var live: LiveShare

    init() {
        LiveBackend.configure()
        _store = State(initialValue: MatchStore())
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
                .task {
                    // Refresh the viewers' copy on launch, e.g. after the app was closed mid-match.
                    if live.isOn { live.sync(store.state) }
                    #if DEBUG
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

enum Theme {
    static let green = Color(red: 0.13, green: 0.55, blue: 0.29)
    static let rust = Color(red: 0.74, green: 0.34, blue: 0.17)
    static let slab = Color(red: 0.09, green: 0.11, blue: 0.14)
    static let clock = Color(red: 1.0, green: 0.84, blue: 0.2)

    static func color(_ side: Side) -> Color { side == .us ? green : rust }
}

struct RootView: View {
    @Environment(MatchStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            StartView()
                .navigationDestination(isPresented: $store.showMatch) {
                    MatchView()
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .tint(Theme.green)
    }
}
