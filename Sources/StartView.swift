import SwiftUI

/// The first page: logo, start or continue a match, and the user's teams.
struct StartView: View {
    @Environment(MatchStore.self) private var store
    @State private var showNewMatch = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                VStack(spacing: 18) {
                    Logo()
                    Button { showNewMatch = true } label: {
                        Label("Ny match", systemImage: "plus.circle.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                    .disabled(store.teams.isEmpty)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if store.hasMatchInProgress {
                Section("Pågående match") {
                    Button { store.showMatch = true } label: { ContinueCard() }
                        .buttonStyle(.plain)
                }
            }

            Section("Mina lag") {
                if store.teams.isEmpty {
                    Text("Lägg till ditt första lag för att kunna starta en match.").foregroundStyle(.secondary)
                }
                ForEach($store.teams) { $team in
                    NavigationLink {
                        TeamEditor(team: $team)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name.isEmpty ? "Namnlöst lag" : team.name).font(.headline)
                            Text("\(Team.formatLabel(team.playersOnField)) · \(team.periods) × \(team.periodLength) min · \(team.players.count) spelare")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { store.teams.remove(atOffsets: $0) }
                Button {
                    store.teams.append(Team(name: "Nytt lag"))
                } label: {
                    Label("Lägg till lag", systemImage: "plus")
                }
            }

            Section {
                Button("Lägg till exempellag") { store.addExampleTeam() }
                    .disabled(store.teams.contains { $0.id == MatchState.exampleTeamID })
                Button("Visa exempelmatch", role: .destructive) { confirmReset = true }
            } header: {
                Text("Exempel")
            } footer: {
                Text("Exempellaget och exempelmatchen har påhittade spelare.")
            }
        }
        .navigationTitle("Matchreferat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewMatch) { NewMatchSheet() }
        .alert("Visa exempelmatchen?", isPresented: $confirmReset) {
            Button("Visa", role: .destructive) {
                store.reset()
                store.showMatch = true
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Den pågående matchen ersätts med exempelmatchen.")
        }
        .onAppear {
            // `-demoSheet newMatch` opens the new match sheet (used for screenshots).
            if UserDefaults.standard.string(forKey: "demoSheet") == "newMatch" { showNewMatch = true }
        }
    }
}

/// Mikael's logo from the asset catalog ("Logo"); a simple placeholder until the real file is added.
struct Logo: View {
    var body: some View {
        if UIImage(named: "Logo") != nil {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 120)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "soccerball")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Theme.green, in: Circle())
                Text("Matchreferat")
                    .font(.title2.weight(.heavy))
            }
        }
    }
}

struct ContinueCard: View {
    @Environment(MatchStore.self) private var store

    var body: some View {
        let state = store.state
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(state.teamName(state.homeSide)) – \(state.teamName(state.awaySide))")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(state.clock(at: context.date).text) · \(state.periodText)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(state.scoreText)
                .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
