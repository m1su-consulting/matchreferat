import SwiftUI

/// Starts a match by hand: two team names and the format. Squads can be added under Dagens trupp.
/// A match from Min fotboll is shared from Safari instead and comes with both squads.
struct NewMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State private var home = ""
    @State private var away = ""
    @State private var playersOnField = 11
    @State private var periods = 2
    @State private var periodLength = 45
    @State private var confirmDiscard = false

    private var sport: Sport { store.sport ?? store.state.sport }
    private var homeName: String { home.trimmingCharacters(in: .whitespaces) }
    private var awayName: String { away.trimmingCharacters(in: .whitespaces) }
    private var canStart: Bool { !homeName.isEmpty && !awayName.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Hemmalag", text: $home)
                        .textInputAutocapitalization(.words)
                    TextField("Bortalag", text: $away)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.go)
                        .onSubmit(tryStart)
                } footer: {
                    if sport == .football {
                        Text("Vill du ha trupperna från Min fotboll? Öppna matchen i Safari och dela den till Matchreferat.")
                    }
                }
                Section {
                    FormatFields(sport: sport, playersOnField: $playersOnField, periods: $periods, periodLength: $periodLength)
                } footer: {
                    if live.isOn { Text("Den gamla livelänken slutar fungera.") }
                }
            }
            .navigationTitle(sport == .football ? "Ny fotbollsmatch" : "Ny innebandymatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
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
        .tint(Theme.accent)
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
            await Self.startNewMatch(store: store, live: live, team: team, opponent: awayName, isHome: true)
            dismiss()
        }
    }

    /// Ends the old match's live link (its page stops working) and starts a fresh match.
    static func startNewMatch(store: MatchStore, live: LiveShare, team: Team, opponent: String, isHome: Bool) async {
        await live.stop()
        store.newMatch(team: team, opponent: opponent, isHome: isHome)
    }
}
