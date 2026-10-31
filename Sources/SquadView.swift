import SwiftUI

/// "Dagens trupp": this match's settings and lineup, editable during the match.
struct MatchSquadSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showNewMatch = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    TextField("Motståndare", text: $store.state.opponent)
                        .textInputAutocapitalization(.words)
                    Picker("Vi spelar", selection: $store.state.isHome) {
                        Text("Vi hemma").tag(true)
                        Text("Vi borta").tag(false)
                    }
                    .pickerStyle(.segmented)
                    FormatFields(playersOnField: $store.state.playersOnField, periods: $store.state.periods,
                                 periodLength: $store.state.halfLength, suggestsLength: false)
                } header: {
                    Text(store.state.ourTeam)
                } footer: {
                    Text("Gäller bara den här matchen. Lagets trupp och inställningar ändrar du under Lag.")
                }

                LineupSection(players: $store.state.players, playersOnField: store.state.playersOnField)

                AddMatchPlayerSection { player, saveInSquad in
                    store.state.players.append(player)
                    store.state.players.sort { $0.number < $1.number }
                    if saveInSquad, let index = store.teams.firstIndex(where: { $0.id == store.state.teamID }) {
                        var squadPlayer = player
                        squadPlayer.status = .bench
                        store.teams[index].players.append(squadPlayer)
                    }
                }

                Section {
                    Button { showNewMatch = true } label: {
                        Label("Ny match", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Dagens trupp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .sheet(isPresented: $showNewMatch, onDismiss: { if store.state.events.isEmpty { dismiss() } }) {
                NewMatchSheet()
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
