import SwiftUI

/// Keys and defaults for the settings, so the store, the views and tests read them the same way.
enum AppSettings {
    static let keepScreenOnKey = "keepScreenOn"
    static let hapticsKey = "haptics"
    static let startSportKey = "startSport"

    /// What the app opens to: the sport used last time (default), or always the same sport.
    enum StartSport: String, CaseIterable, Identifiable {
        case last, football, floorball

        var id: String { rawValue }

        var label: String {
            switch self {
            case .last: "Senast vald"
            case .football: "Fotboll"
            case .floorball: "Innebandy"
            }
        }

        var sport: Sport? { Sport(rawValue: rawValue) }
    }

    static func keepScreenOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: keepScreenOnKey) as? Bool ?? true
    }

    static func haptics(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: hapticsKey) as? Bool ?? true
    }

    /// The sport to open on launch: the fixed one if chosen, otherwise the last used (nil shows the picker).
    static func launchSport(_ defaults: UserDefaults = .standard, last: Sport?) -> Sport? {
        let choice = defaults.string(forKey: startSportKey).flatMap(StartSport.init(rawValue:)) ?? .last
        return choice.sport ?? last
    }
}

/// App settings, reachable from the sport picker and each sport's start page. New settings get
/// their own section above "Om appen".
struct SettingsView: View {
    @Environment(LiveShare.self) private var live
    @AppStorage(AppSettings.keepScreenOnKey) private var keepScreenOn = true
    @AppStorage(AppSettings.hapticsKey) private var haptics = true
    @AppStorage(AppSettings.startSportKey) private var startSport = AppSettings.StartSport.last.rawValue

    var body: some View {
        List {
            Section {
                Toggle(isOn: $keepScreenOn) {
                    Label("Håll skärmen tänd under match", systemImage: "sun.max")
                }
                Toggle(isOn: $haptics) {
                    Label("Vibration vid knapptryck", systemImage: "iphone.radiowaves.left.and.right")
                }
                Picker(selection: $startSport) {
                    ForEach(AppSettings.StartSport.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    Label("Sport vid start", systemImage: "sportscourt")
                }
            } header: {
                Text("Match")
            } footer: {
                Text("Skärmen hålls tänd när matchsidan är öppen och matchen inte är slut.")
            }
            .tint(Theme.accent)

            Section {
                NavigationLink(value: Route.liveServer) {
                    LabeledContent {
                        Text(live.server?.name ?? "Ingen")
                    } label: {
                        Label("Live-server", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            } header: {
                Text("Live")
            } footer: {
                Text("Visa, testa, byt eller koppla från live-servern. Behövs för att dela matcher med en länk och se andras matcher under Pågår nu.")
            }

            Section("Om appen") {
                NavigationLink(value: Route.help) {
                    Label("Så hämtar du en match", systemImage: "questionmark.circle")
                }
                NavigationLink(value: Route.licenses) {
                    Label("Licenser", systemImage: "doc.text")
                }
                Link(destination: URL(string: "\(LiveServer.viewerHost)/integritet")!) {
                    Label("Integritetspolicy", systemImage: "hand.raised")
                }
                Link(destination: URL(string: "\(LiveServer.viewerHost)/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                LabeledContent {
                    Text(MadeBy.version)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Inställningar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
