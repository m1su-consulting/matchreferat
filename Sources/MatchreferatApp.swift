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
                .task {
                    // Refresh the viewers' copy on launch, e.g. after the app was closed mid-match.
                    if live.isOn { live.sync(store.state) }
                    #if DEBUG
                    // `-demoLive YES` starts sharing on launch (used for emulator tests).
                    if UserDefaults.standard.bool(forKey: "demoLive") && !live.isOn {
                        await live.start(store.state)
                    }
                    // `-demoNewMatch "Lag"` runs the Ny match flow on launch (used for tests).
                    if let opponent = UserDefaults.standard.string(forKey: "demoNewMatch") {
                        await NewMatchSheet.startNewMatch(store: store, live: live, opponent: opponent,
                                                          isHome: false, halfLength: store.state.halfLength)
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
        TabView(selection: $store.selectedTab) {
            MatchView()
                .tabItem { Label("Match", systemImage: "sportscourt.fill") }
                .tag(0)
            EventsView()
                .tabItem { Label("Händelser", systemImage: "list.bullet.rectangle") }
                .tag(1)
            SquadView()
                .tabItem { Label("Trupp", systemImage: "person.3.fill") }
                .tag(2)
        }
        .tint(Theme.green)
    }
}
