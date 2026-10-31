import SwiftUI

/// Starts a new match: team, opponent and home/away. Everything else comes from the team
/// and can be changed on the match page via ⋯.
struct NewMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State private var teamID: UUID?
    @State private var opponent = ""
    @State private var isHome = true
    @State private var confirmDiscard = false

    private var team: Team? { store.teams.first { $0.id == teamID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Lag", selection: $teamID) {
                        ForEach(store.teams) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Motståndare", text: $opponent)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.go)
                        .onSubmit(tryStart)
                    Picker("Vi spelar", selection: $isHome) {
                        Text("Hemma").tag(true)
                        Text("Borta").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if let team {
                        Text("\(Team.formatLabel(team.playersOnField)) · \(team.periods) × \(team.periodLength) min · senaste uppställningen. Ändras under ⋯ på matchsidan."
                             + (live.isOn ? " Den gamla livelänken slutar fungera." : ""))
                    }
                }
            }
            .navigationTitle("Ny match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starta", action: tryStart)
                        .disabled(team == nil || opponent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Avsluta pågående match?", isPresented: $confirmDiscard) {
                Button("Starta ny match", role: .destructive) { start() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Händelserna i den pågående matchen försvinner.")
            }
            .onAppear {
                teamID = store.teams.first { $0.id == store.state.teamID }?.id ?? store.teams.first?.id
                isHome = store.state.isHome
            }
        }
        .presentationDetents([.medium])
    }

    private func tryStart() {
        guard team != nil, !opponent.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
    }

    private func start() {
        guard let team else { return }
        let name = opponent.trimmingCharacters(in: .whitespaces)
        Task {
            await Self.startNewMatch(store: store, live: live, team: team, opponent: name, isHome: isHome)
            dismiss()
        }
    }

    /// Ends the old match's live link (its page stops working) and starts a fresh match.
    static func startNewMatch(store: MatchStore, live: LiveShare, team: Team, opponent: String, isHome: Bool) async {
        await live.stop()
        store.newMatch(team: team, opponent: opponent, isHome: isHome)
    }
}
