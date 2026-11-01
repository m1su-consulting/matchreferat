import SwiftUI

/// The first page: logo, start or continue a match, and the user's teams.
struct StartView: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @State private var showNewMatch = false
    @State private var confirmDelete = false
    @State private var browserPage: BrowserPage?

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
                    Button { store.openMatch() } label: { ContinueCard() }
                        .buttonStyle(.plain)
                        .contextMenu { matchActions }
                        .swipeActions { matchActions }
                }
            }

            if let server = live.server {
                OngoingSection(list: live.ongoing, serverName: server.name) { match in
                    browserPage = BrowserPage(url: server.viewerURL(matchID: match.id))
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
                ForEach(store.teams) { team in
                    NavigationLink(value: Route.team(team.id)) {
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
                NavigationLink(value: Route.liveServer) {
                    LabeledContent {
                        Text(live.server?.name ?? "Ingen")
                    } label: {
                        Label("Live-server", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                NavigationLink(value: Route.licenses) {
                    Label("Licenser", systemImage: "doc.text")
                }
            } header: {
                Text("Inställningar")
            }

            Section {
                MadeBy()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await live.refreshOngoing() }
        .task(id: live.server?.projectID) {
            // Poll while the start page is visible; the task is cancelled when it disappears.
            while live.isConfigured, !Task.isCancelled {
                await live.refreshOngoing()
                try? await Task.sleep(for: .seconds(25))
            }
        }
        .sheet(item: $browserPage) { page in SafariView(url: page.url).ignoresSafeArea() }
        .sheet(isPresented: $showNewMatch) { NewMatchSheet() }
        .modifier(DeleteMatchConfirmation(isPresented: $confirmDelete))
        .onAppear {
            // `-demoSheet newMatch` opens the new match sheet (used for screenshots).
            if LaunchArgument.string("demoSheet") == "newMatch" { showNewMatch = true }
        }
    }

    /// End or delete the ongoing match without opening it.
    @ViewBuilder private var matchActions: some View {
        Button(role: .destructive) { confirmDelete = true } label: { Label("Ta bort match", systemImage: "trash") }
        Button { store.endMatch() } label: { Label("Avsluta match", systemImage: "flag.checkered") }
            .tint(Theme.green)
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

/// Small "Utvecklad av" credit with Mikael's M1SU Consulting logo.
struct MadeBy: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Utvecklad av")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The logo has its own metal frame on white, so it only needs rounded corners and a soft shadow.
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .accessibilityLabel("M1SU Consulting")
            HStack(spacing: 16) {
                Link("Integritetspolicy", destination: URL(string: "https://matchreferat.web.app/integritet")!)
                Link("Support", destination: URL(string: "https://matchreferat.web.app/support")!)
            }
            .font(.caption)
            .padding(.top, 6)
            Text("Version \(Self.version)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Appversion \(Self.version)")
        }
    }

    /// Marketing version and build number from the bundle, e.g. "1.0.2 (3)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

struct ContinueCard: View {
    @Environment(MatchStore.self) private var store
    @ScaledMetric(relativeTo: .title) private var scoreSize: CGFloat = 30

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
                .font(.system(size: scoreSize, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fortsätt match: \(state.teamName(state.homeSide)) mot \(state.teamName(state.awaySide)), \(state.scoreText)")
    }
}
