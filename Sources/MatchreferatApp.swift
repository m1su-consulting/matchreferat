import SwiftUI

@main
struct MatchreferatApp: App {
    @State private var store = MatchStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onChange(of: store.state) { store.save() }
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
    // `-tab 1` as a launch argument opens another tab (used for screenshots).
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")

    var body: some View {
        TabView(selection: $tab) {
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
