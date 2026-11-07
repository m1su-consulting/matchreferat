import SwiftUI

/// A match shared from Min fotboll: check the names and who starts in both teams, then start.
struct ImportMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State var match: ImportedMatch
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Hemma") {
                        TextField("Lagnamn", text: $match.home.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Borta") {
                        TextField("Lagnamn", text: $match.away.name)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Trupperna sparas med hela namnet på telefonen. Det som delas visar bara förnamn och nummer.")
                }
                if !match.hasSquads, let url = match.safariURL {
                    Section {
                        Link(destination: url) {
                            Label("Hämta trupperna", systemImage: "safari")
                        }
                    } footer: {
                        Text("Matchen öppnas i Safari. Dela den till Matchreferat igen, så kommer trupperna med. De publiceras ungefär en timme före avspark.")
                    }
                }
                if !match.home.players.isEmpty { squad($match.home) }
                if !match.away.players.isEmpty { squad($match.away) }
            }
            .navigationTitle("Kommande match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starta") {
                        if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
                    }
                }
            }
            .onChange(of: store.plannedMatches) {
                // New squads shared from Safari while this sheet was open.
                if let latest = store.plannedMatches.first(where: { $0.id == match.id }) { match = latest }
            }
            .alert("Avsluta pågående match?", isPresented: $confirmDiscard) {
                Button("Starta ny match", role: .destructive) { start() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Händelserna i den pågående matchen försvinner.")
            }
        }
        .tint(Theme.accent)
    }

    private func squad(_ team: Binding<ImportedTeam>) -> some View {
        Section {
            ForEach(team.players) { $player in
                if match.sport == nil {
                    Toggle(isOn: $player.starts) { row(player) }
                        .tint(Theme.accent)
                } else {
                    row(player)  // Floorball changes lines all the time, so nobody is marked as starting.
                }
            }
        } header: {
            HStack {
                Text(team.wrappedValue.name)
                Spacer()
                if match.sport == nil {
                    Text("\(team.wrappedValue.players.filter(\.starts).count) startar")
                }
            }
        }
    }

    private func row(_ player: ImportedPlayer) -> some View {
        HStack(spacing: 10) {
            Text("\(player.number)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 32, alignment: .trailing)
            Text("\(player.firstName) \(player.lastName)")
        }
    }

    private func start() {
        Task {
            await live.stop()
            store.startImportedMatch(match)
            dismiss()
        }
    }
}
