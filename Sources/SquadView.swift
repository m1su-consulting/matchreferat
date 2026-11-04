import SwiftUI

/// "Dagens trupp": today's lineup, editable during the match. Remembered as the team's lineup.
struct MatchSquadSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                LineupSection(players: $store.state.players, playersOnField: store.state.playersOnField,
                              countsStarters: store.state.sport == .football)
                AddMatchPlayerSection { player, saveInSquad in
                    store.addMatchPlayer(player, saveInSquad: saveInSquad)
                }
            }
            .navigationTitle("Dagens trupp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }
}

/// This match's settings: opponent, home/away, spelform, periods and minutes.
struct MatchSettingsSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    TextField("Motståndare", text: $store.state.opponent)
                        .textInputAutocapitalization(.words)
                    Picker("Vi spelar", selection: $store.state.isHome) {
                        Text("Hemma").tag(true)
                        Text("Borta").tag(false)
                    }
                    .pickerStyle(.segmented)
                    FormatFields(sport: store.state.sport, playersOnField: $store.state.playersOnField, periods: $store.state.periods,
                                 periodLength: $store.state.halfLength, suggestsLength: false)
                } header: {
                    Text(store.state.ourTeam)
                } footer: {
                    Text("Gäller bara den här matchen. Lagets standardinställningar ändrar du på startsidan under Mina lag.")
                }
            }
            .navigationTitle("Matchinställningar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                    .background(player.status == .out ? Color.gray : Theme.accent, in: Circle())
                Text(player.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(player.status == .out ? .secondary : .primary)
            }
            Picker("Status", selection: $player.status) {
                ForEach(PlayerStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Status för \(player.name), nummer \(player.number)")
        }
        .padding(.vertical, 4)
    }
}
