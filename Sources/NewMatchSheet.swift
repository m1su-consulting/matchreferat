import SwiftUI

/// Starts a new match against a new opponent. The squad and everyone's Start/Bänk/Ej med are kept.
struct NewMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State private var opponent = ""
    @State private var isHome = true
    @State private var halfLength = 25
    @State private var confirmDiscard = false

    private let halfLengths = [15, 20, 25, 30, 35, 45]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Motståndare", text: $opponent)
                        .textInputAutocapitalization(.words)
                    Picker("Vi spelar", selection: $isHome) {
                        Text("Vi hemma").tag(true)
                        Text("Vi borta").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Picker("Halvlek", selection: $halfLength) {
                        ForEach(halfLengths, id: \.self) { Text("\($0) min").tag($0) }
                    }
                } footer: {
                    Text("Truppen och vilka som startar, sitter på bänken eller inte är med behålls. Händelser, resultat och klocka nollställs." + (live.isOn ? " Den gamla livelänken slutar fungera, och du kan dela en ny för den här matchen." : ""))
                }
            }
            .navigationTitle("Ny match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starta") {
                        if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
                    }
                    .disabled(opponent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Avsluta pågående match?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Starta ny match", role: .destructive) { start() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Händelserna i den pågående matchen försvinner.")
            }
            .onAppear {
                isHome = store.state.isHome
                halfLength = store.state.halfLength
            }
        }
        .presentationDetents([.medium])
    }

    private func start() {
        let name = opponent.trimmingCharacters(in: .whitespaces)
        Task {
            await Self.startNewMatch(store: store, live: live, opponent: name, isHome: isHome, halfLength: halfLength)
            dismiss()
        }
    }

    /// Ends the old match's live link (its page stops working) and starts a fresh match.
    static func startNewMatch(store: MatchStore, live: LiveShare, opponent: String, isHome: Bool, halfLength: Int) async {
        await live.stop()
        store.newMatch(opponent: opponent, isHome: isHome, halfLength: halfLength)
    }
}
