import SwiftUI

struct SquadView: View {
    @Environment(MatchStore.self) private var store
    @State private var newName = ""
    @State private var newNumber = ""
    @State private var confirmReset = false

    private let halfLengths = [15, 20, 25, 30, 35, 45]

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Match") {
                    LabeledContent("Vårt lag") {
                        TextField("Vårt lag", text: $store.state.ourTeam)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Motståndare") {
                        TextField("Motståndare", text: $store.state.opponent)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Plats", selection: $store.state.isHome) {
                        Text("Hemma").tag(true)
                        Text("Borta").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Picker("Halvlek", selection: $store.state.halfLength) {
                        ForEach(halfLengths, id: \.self) { Text("\($0) min").tag($0) }
                    }
                }

                Section {
                    ForEach($store.state.players) { $player in
                        PlayerRow(player: $player)
                    }
                    .onDelete { store.state.players.remove(atOffsets: $0) }
                } header: {
                    Text("Trupp · \(store.state.onField.count) på plan · \(store.state.bench.count) bänk")
                }

                Section("Lägg till spelare") {
                    TextField("Namn", text: $newName)
                        .textContentType(.name)
                    TextField("Nummer", text: $newNumber)
                        .keyboardType(.numberPad)
                    Button("Lägg till") {
                        store.addPlayer(name: newName.trimmingCharacters(in: .whitespaces), number: Int(newNumber) ?? 0)
                        newName = ""
                        newNumber = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || Int(newNumber) == nil)
                }

                Section {
                    Button("Återställ exempelmatch", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Trupp")
            .confirmationDialog("Återställa exempelmatchen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Återställ", role: .destructive) { store.reset() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Alla händelser och ändringar i truppen ersätts med exempeldata.")
            }
        }
    }
}

struct PlayerRow: View {
    @Binding var player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(player.number)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(player.status == .out ? Color.gray : Theme.green, in: Circle())
                Text(player.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(player.status == .out ? .secondary : .primary)
            }
            Picker("Status", selection: $player.status) {
                ForEach(PlayerStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
