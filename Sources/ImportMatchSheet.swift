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
                squad($match.home)
                squad($match.away)
            }
            .navigationTitle("Importera match")
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
                Toggle(isOn: $player.starts) {
                    HStack(spacing: 10) {
                        Text("\(player.number)")
                            .font(.headline.monospacedDigit())
                            .frame(minWidth: 32, alignment: .trailing)
                        Text("\(player.firstName) \(player.lastName)")
                    }
                }
                .tint(Theme.accent)
            }
        } header: {
            HStack {
                Text(team.wrappedValue.name)
                Spacer()
                Text("\(team.wrappedValue.players.filter(\.starts).count) startar")
            }
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
