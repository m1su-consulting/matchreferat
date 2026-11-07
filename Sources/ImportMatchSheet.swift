import SwiftUI

/// A match shared from Min fotboll: choose your team, check who starts and start the match.
struct ImportMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    let match: ImportedMatch

    @State private var isHome = true
    @State private var opponent = ""
    @State private var teamID: UUID?
    @State private var players: [ImportedPlayer] = []
    @State private var confirmDiscard = false

    private var footballTeams: [Team] { store.teams(for: .football) }
    private var mine: ImportedTeam { isHome ? match.home : match.away }
    private var starters: Int { players.filter(\.starts).count }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vilket lag är ert?") {
                    Picker("Vårt lag", selection: $isHome) {
                        Text(match.home.name).tag(true)
                        Text(match.away.name).tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    LabeledContent("Motståndare") {
                        TextField("Lagnamn", text: $opponent)
                            .textInputAutocapitalization(.words)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Spara i lag", selection: $teamID) {
                        Text("Nytt lag").tag(UUID?.none)
                        ForEach(footballTeams) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    ForEach($players) { $player in
                        Toggle(isOn: $player.starts) {
                            HStack(spacing: 10) {
                                Text("\(player.number)")
                                    .font(.headline.monospacedDigit())
                                    .frame(minWidth: 32, alignment: .trailing)
                                Text(player.firstName)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } header: {
                    HStack {
                        Text("Startar")
                        Spacer()
                        Text("\(starters) av \(players.count)")
                    }
                } footer: {
                    Text("Bara förnamn och tröjnummer sparas. Efternamn från sidan följer inte med.")
                }
            }
            .navigationTitle("Importera match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starta", action: tryStart)
                        .disabled(opponent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Avsluta pågående match?", isPresented: $confirmDiscard) {
                Button("Starta ny match", role: .destructive) { start() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Händelserna i den pågående matchen försvinner.")
            }
            .onAppear {
                isHome = !footballTeams.contains { matches($0, match.away) } || footballTeams.contains { matches($0, match.home) }
                load()
            }
            .onChange(of: isHome) { load() }
        }
        .tint(Theme.accent)
    }

    private func matches(_ team: Team, _ imported: ImportedTeam) -> Bool {
        team.name.caseInsensitiveCompare(imported.name) == .orderedSame
    }

    private func load() {
        players = mine.players
        opponent = (isHome ? match.away : match.home).name
        teamID = footballTeams.first { matches($0, mine) }?.id
    }

    private func tryStart() {
        if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
    }

    private func start() {
        Task {
            await live.stop()
            store.startImportedMatch(players: players, teamID: teamID, teamName: mine.name,
                                     opponent: opponent.trimmingCharacters(in: .whitespaces), isHome: isHome)
            dismiss()
        }
    }
}
