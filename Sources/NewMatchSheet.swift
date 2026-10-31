import SwiftUI

/// Starts a new match: pick a team (when there are several), then adjust this match's
/// settings and lineup, prefilled from the team.
struct NewMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State private var team: Team?
    @State private var opponent = ""
    @State private var isHome = true
    @State private var playersOnField = 9
    @State private var periods = 2
    @State private var periodLength = 25
    @State private var players: [Player] = []
    @State private var newSquadPlayers: [Player] = []
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if let team {
                    form(team)
                } else {
                    teamPicker
                }
            }
            .navigationTitle(team == nil ? "Välj lag" : "Ny match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                if team != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Starta") {
                            if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
                        }
                        .disabled(opponent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog("Avsluta pågående match?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Starta ny match", role: .destructive) { start() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Händelserna i den pågående matchen försvinner.")
            }
        }
        .onAppear {
            if store.teams.count == 1 { select(store.teams[0]) }
        }
    }

    private var teamPicker: some View {
        List(store.teams) { team in
            Button { select(team) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.headline).foregroundStyle(.primary)
                    Text("\(Team.formatLabel(team.playersOnField)) · \(team.players.count) spelare")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func form(_ team: Team) -> some View {
        Form {
            Section {
                if store.teams.count > 1 {
                    LabeledContent("Lag") {
                        Button(team.name) { self.team = nil }
                    }
                }
                TextField("Motståndare", text: $opponent)
                    .textInputAutocapitalization(.words)
                Picker("Vi spelar", selection: $isHome) {
                    Text("Vi hemma").tag(true)
                    Text("Vi borta").tag(false)
                }
                .pickerStyle(.segmented)
                FormatFields(playersOnField: $playersOnField, periods: $periods, periodLength: $periodLength,
                             suggestsLength: false)
            } header: {
                Text(team.name)
            } footer: {
                Text("Ändringarna gäller bara den här matchen." + (live.isOn ? " Den gamla livelänken slutar fungera, och du kan dela en ny." : ""))
            }

            LineupSection(players: $players, playersOnField: playersOnField)

            AddMatchPlayerSection { player, saveInSquad in
                players.append(player)
                if saveInSquad { newSquadPlayers.append(player) }
            }
        }
    }

    private func select(_ team: Team) {
        self.team = team
        isHome = store.state.isHome
        playersOnField = team.playersOnField
        periods = team.periods
        periodLength = team.periodLength
        players = store.suggestedLineup(for: team, playersOnField: team.playersOnField)
        newSquadPlayers = []
    }

    private func start() {
        guard var team else { return }
        if !newSquadPlayers.isEmpty, let index = store.teams.firstIndex(where: { $0.id == team.id }) {
            store.teams[index].players += newSquadPlayers.map { var p = $0; p.status = .bench; return p }
            team = store.teams[index]
        }
        let settings = (opponent.trimmingCharacters(in: .whitespaces), isHome, playersOnField, periods, periodLength, players)
        Task {
            await Self.startNewMatch(store: store, live: live, team: team, opponent: settings.0, isHome: settings.1,
                                     playersOnField: settings.2, periods: settings.3, periodLength: settings.4,
                                     players: settings.5)
            dismiss()
        }
    }

    /// Ends the old match's live link (its page stops working) and starts a fresh match.
    static func startNewMatch(store: MatchStore, live: LiveShare, team: Team, opponent: String, isHome: Bool,
                              playersOnField: Int, periods: Int, periodLength: Int, players: [Player]) async {
        await live.stop()
        store.newMatch(team: team, opponent: opponent, isHome: isHome, playersOnField: playersOnField,
                       periods: periods, periodLength: periodLength, players: players)
    }
}
