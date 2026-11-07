import SwiftUI

/// A new match: paste a link from Min fotboll or Innebandy Play, or make one by hand.
struct NewMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var link = ""
    @State private var working = false
    @State private var failed = false
    @State private var showHelp = false

    private var sport: Sport { store.sport ?? store.state.sport }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Klistra in länk till matchen", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                    Button(action: useLink) {
                        if working { ProgressView() } else { Text("Hämta matchen") }
                    }
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                } header: {
                    Text("Från \(sport.matchSite)")
                } footer: {
                    Text(failed ? "Hittade ingen länk i texten." : "Matchen öppnas i Safari. Dela den därifrån till Matchreferat, så kommer lagen och trupperna med.")
                        .foregroundStyle(failed ? Color.orange : Color.secondary)
                }
                Section {
                    Button("Så här gör du") { showHelp = true }
                    NavigationLink("Lägg upp egen match") { OwnMatchForm(sport: sport, close: { dismiss() }) }
                }
            }
            .navigationTitle(sport == .football ? "Ny fotbollsmatch" : "Ny innebandymatch")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showHelp) { HelpView() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }

    /// A text shared from the Min fotboll app has the team names, so that match is saved right away. The short link
    /// in it leads to the match page, which is what Safari needs. A plain link just opens in Safari for sharing.
    private func useLink() {
        guard let pasted = MatchImport.pasted(link) else {
            failed = true
            return
        }
        failed = false
        // A live link from someone else's match opens to follow, right here in the app.
        if let url = URL(string: pasted.url), let match = LiveMatchLink(url: url, fallback: live.server) {
            live.openedMatch = match
            dismiss()
            return
        }
        working = true
        Task {
            let page = await Self.matchPage(pasted.url)
            working = false
            if pasted.names.count == 2 {
                MatchImport.add(ImportedMatch(home: ImportedTeam(name: pasted.names[0], players: []),
                                              away: ImportedTeam(name: pasted.names[1], players: []), url: page,
                                              sport: sport == .football ? nil : "floorball"))
                store.refreshPlanned()
            } else if let url = URL(string: "x-safari-" + page) {
                openURL(url)
            }
            dismiss()
        }
    }

    /// Min fotboll's short links hide the match page in the landing page they lead to.
    private static func matchPage(_ url: String) async -> String {
        guard url.contains("app.link"), let link = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: link) else { return url }
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: #"https://minfotboll\.svenskfotboll\.se/game-view/\d+"#, options: .regularExpression) else { return url }
        return String(text[range])
    }

    /// Ends the old match's live link (its page stops working) and starts a fresh match.
    static func startNewMatch(store: MatchStore, live: LiveShare, team: Team, opponent: String, isHome: Bool) async {
        await live.stop()
        store.newMatch(team: team, opponent: opponent, isHome: isHome)
    }
}

/// Two team names and the format. Players can be added afterwards under Dagens trupp.
struct OwnMatchForm: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live

    let sport: Sport
    let close: () -> Void

    @State private var home = ""
    @State private var away = ""
    @State private var playersOnField = 11
    @State private var periods = 2
    @State private var periodLength = 45
    @State private var confirmDiscard = false

    private var homeName: String { home.trimmingCharacters(in: .whitespaces) }
    private var awayName: String { away.trimmingCharacters(in: .whitespaces) }
    private var canStart: Bool { !homeName.isEmpty && !awayName.isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Hemmalag", text: $home)
                    .textInputAutocapitalization(.words)
                TextField("Bortalag", text: $away)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    .onSubmit(tryStart)
            }
            Section {
                FormatFields(sport: sport, playersOnField: $playersOnField, periods: $periods, periodLength: $periodLength)
            } footer: {
                if live.isOn { Text("Den gamla livelänken slutar fungera.") }
            }
        }
        .navigationTitle("Egen match")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Starta", action: tryStart)
                    .disabled(!canStart)
            }
        }
        .alert("Avsluta pågående match?", isPresented: $confirmDiscard) {
            Button("Starta ny match", role: .destructive) { start() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Händelserna i den pågående \(store.state.sport == .football ? "fotbollsmatchen" : "innebandymatchen") försvinner.")
        }
        .onAppear {
            let defaults = Team.new(sport)
            playersOnField = defaults.playersOnField
            periods = defaults.periods
            periodLength = defaults.periodLength
        }
    }

    private func tryStart() {
        guard canStart else { return }
        if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
    }

    private func start() {
        var team = Team.new(sport, name: homeName)
        team.playersOnField = playersOnField
        team.periods = periods
        team.periodLength = periodLength
        Task {
            await NewMatchSheet.startNewMatch(store: store, live: live, team: team, opponent: awayName, isHome: true)
            close()
        }
    }
}
