import SwiftUI

#if DEBUG
/// Example data for SwiftUI previews: a fictional team in the middle of a match.
@MainActor
enum PreviewData {
    static func store(_ match: MatchState = .example(), live: Bool = true) -> MatchStore {
        let store = MatchStore(container: Persistence.container(inMemory: true),
                               legacyDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("preview"))
        var team = MatchState.exampleTeam()
        team.name = "Björkdalens IF"
        var state = match
        state.ourTeam = team.name
        store.teams = [team]
        store.state = state
        return store
    }

    static func liveShare(connected: Bool = true) -> LiveShare {
        let defaults = UserDefaults(suiteName: "matchreferat-previews")!
        defaults.removePersistentDomain(forName: "matchreferat-previews")
        if connected {
            let server = LiveServer(projectID: "bjorkdalen-live", apiKey: "AIzaPREVIEW0123456789abcdefghijklmno", name: "Björkdalens IF")
            defaults.set(try? JSONEncoder().encode(server), forKey: "liveServer")
        }
        return LiveShare(client: OfflineClient(), defaults: defaults)
    }

    /// Answers every request with "not found", so previews never touch the network.
    struct OfflineClient: HTTPClient {
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }

    static var player: Player { MatchState.example().players[9] }
}

private extension View {
    func previewEnvironment(_ store: MatchStore = PreviewData.store(), live: LiveShare = PreviewData.liveShare()) -> some View {
        environment(store).environment(live).tint(Theme.green)
    }
}

// MARK: Start page

#Preview("Startsida") { RootView().previewEnvironment() }
#Preview("Startsida – första start") {
    let store = PreviewData.store(.empty)
    store.teams = []
    return NavigationStack { StartView() }.previewEnvironment(store, live: PreviewData.liveShare(connected: false))
}
#Preview("Logga") { Logo() }
#Preview("Utvecklad av") { MadeBy() }
#Preview("Fortsätt match") { List { ContinueCard() }.previewEnvironment() }
#Preview("Ny match") { NewMatchSheet().previewEnvironment() }

// MARK: Match page

#Preview("Matchsida") { MatchView().previewEnvironment() }
#Preview("Resultattavla") { ScoreboardView().padding().previewEnvironment() }
#Preview("Resultattavla – stor text") {
    ScoreboardView().padding().previewEnvironment().environment(\.dynamicTypeSize, .accessibility2)
}
#Preview("Klockknappar") { ClockControls().padding().previewEnvironment() }
#Preview("Händelseknappar") {
    @Previewable @State var flow: Flow?
    EventGrid(flow: $flow).padding().previewEnvironment()
}
#Preview("Hemma/borta") { HomeAwayPicker().padding().previewEnvironment() }
#Preview("Ångra-ruta") {
    ToastView(toast: .init(eventID: UUID(), text: "31' Mål! Elias Forsberg, assist Freja Håkansson")).previewEnvironment()
}
#Preview("Välj målskytt") { FlowSheet(flow: .goal).previewEnvironment() }
#Preview("Välj spelare") {
    PlayerPicker(prompt: "Vem gjorde målet?", players: MatchState.example().onField, skip: "Okänd") { _ in }.padding()
}
#Preview("Spelarbricka") { PlayerChip(player: PreviewData.player).padding() }

// MARK: Events, squad and settings

#Preview("Händelser och referat") { EventsView().previewEnvironment() }
#Preview("Händelserad") {
    List { EventRow(event: MatchState.example().events.first { $0.kind == .goal }!) }.previewEnvironment()
}
#Preview("Dagens trupp") { MatchSquadSheet().previewEnvironment() }
#Preview("Matchinställningar") { MatchSettingsSheet().previewEnvironment() }
#Preview("Spelarrad") {
    @Previewable @State var player = PreviewData.player
    List { PlayerRow(player: $player) }
}
#Preview("Redigera lag") {
    @Previewable @State var team = MatchState.exampleTeam()
    NavigationStack { TeamEditor(team: $team) }
}
#Preview("Spelform") {
    @Previewable @State var onField = 9
    @Previewable @State var periods = 2
    @Previewable @State var length = 25
    Form { FormatFields(playersOnField: $onField, periods: $periods, periodLength: $length) }
}
#Preview("Uppställning") {
    @Previewable @State var players = MatchState.example().players
    Form { LineupSection(players: $players, playersOnField: 9) }
}
#Preview("Lägg till spelare") { Form { AddMatchPlayerSection { _, _ in } } }

// MARK: Live link and licenses

#Preview("Dela live-knapp") { LiveRow().padding().previewEnvironment() }
#Preview("Livelänk") { LiveShareSheet().previewEnvironment() }
#Preview("Livelänk – ingen server") { LiveShareSheet().previewEnvironment(live: PreviewData.liveShare(connected: false)) }
#Preview("Live-server – kopplad") { NavigationStack { LiveServerView() }.previewEnvironment() }
#Preview("Live-server – ej kopplad") {
    NavigationStack { LiveServerView() }.previewEnvironment(live: PreviewData.liveShare(connected: false))
}
#Preview("Licenser") { NavigationStack { LicensesView() } }
#endif
