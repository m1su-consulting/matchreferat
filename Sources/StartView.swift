import SwiftUI

/// The first page: logo, start or continue a match, and the user's teams.
struct StartView: View {
    @Environment(MatchStore.self) private var store
    @State private var showNewMatch = false

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lägg till ditt första lag för att kunna starta en match.")
                            .foregroundStyle(.secondary)
                        Button("Prova med ett exempellag") { store.addExampleTeam() }
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
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
                MadeBy()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewMatch) { NewMatchSheet() }
        .onAppear {
            // `-demoSheet newMatch` opens the new match sheet (used for screenshots).
            if LaunchArgument.string("demoSheet") == "newMatch" { showNewMatch = true }
        }
    }
}

/// The app logo (a girl kicking a football) with the app name.
struct Logo: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .accessibilityHidden(true)
            Text("Matchreferat")
                .font(.title.weight(.heavy))
        }
    }
}

/// Small "Utvecklad av" credit with Mikael's M1SU Consulting logo. The logo is a JPG with a
/// white background, so it sits on a white card that also looks deliberate in dark mode.
struct MadeBy: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Utvecklad av")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08)))
                .opacity(0.9)
                .accessibilityLabel("M1SU Consulting")
            HStack(spacing: 16) {
                Link("Integritetspolicy", destination: URL(string: "https://matchreferat.web.app/integritet")!)
                Link("Support", destination: URL(string: "https://matchreferat.web.app/support")!)
            }
            .font(.caption)
            .padding(.top, 6)
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
