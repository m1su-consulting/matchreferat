import SwiftUI

/// The start page for one sport: picture, start or continue a match, and the sport's teams.
struct StartView: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @State private var showNewMatch = false
    @State private var confirmDelete = false
    @State private var browserPage: BrowserPage?

    private var sport: Sport { store.sport ?? .football }

    var body: some View {
        @Bindable var store = store
        let teams = store.teams(for: sport)
        List {
            Section {
                VStack(spacing: 18) {
                    SportHeader(sport: sport) { store.sport = nil }
                    Button { showNewMatch = true } label: {
                        Label("Ny match", systemImage: "plus.circle.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.green)
                    .disabled(teams.isEmpty)
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

            Section {
                if teams.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lägg till ditt första \(sport == .football ? "fotbollslag" : "innebandylag") för att kunna starta en match.")
                            .foregroundStyle(.secondary)
                        Button("Prova med ett exempellag") { store.addExampleTeam(sport) }
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(teams) { team in
                    NavigationLink(value: Route.team(team.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name.isEmpty ? "Namnlöst lag" : team.name).font(.headline)
                            Text(team.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in store.deleteTeams(offsets.map { teams[$0].id }) }
                Button {
                    _ = store.addTeam(sport)
                } label: {
                    Label("Lägg till lag", systemImage: "plus")
                }
            } header: {
                Text("Mina lag · \(sport.label)")
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

/// The sport's picture with the app name and a button back to the sport picker.
struct SportHeader: View {
    let sport: Sport
    let changeSport: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            SportPicture(sport: sport)
                .overlay(alignment: .topTrailing) {
                    Button(action: changeSport) {
                        Label("Byt sport", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .padding(10)
                    .accessibilityHint("Visar sportvalet")
                }
            HStack(spacing: 8) {
                Image(systemName: sport.icon)
                    .foregroundStyle(Theme.green)
                    .accessibilityHidden(true)
                Text("Matchreferat")
                    .font(.title.weight(.heavy))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Matchreferat, \(sport.label)")
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The wide start picture for a sport, with the sport's name.
struct SportPicture: View {
    let sport: Sport
    var height: CGFloat? = nil

    var body: some View {
        Image(sport.startImage)
            .resizable()
            .aspectRatio(1024 / 572, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Label(sport.label, systemImage: sport.icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(10)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sport.label)
    }
}

/// The first page on a fresh install and after "Byt sport": Fotboll or Innebandy.
struct SportPickerView: View {
    @Environment(MatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Logo()
                Text("Vilken sport ska du referera?")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                ForEach(Sport.allCases) { sport in
                    Button { store.sport = sport } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            SportPicture(sport: sport)
                            Text(teamsText(sport))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(sport.label), \(teamsText(sport))")
                    .accessibilityAddTraits(.isButton)
                }
                Text("Appen kommer ihåg valet. Du byter sport med Byt sport på startsidan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                MadeBy()
                    .padding(.top, 12)
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func teamsText(_ sport: Sport) -> String {
        let count = store.teams(for: sport).count
        let match = store.hasMatchInProgress && store.state.sport == sport ? " · pågående match" : ""
        return (count == 0 ? "Inga lag än" : count == 1 ? "1 lag" : "\(count) lag") + match
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
            Image(systemName: state.sport.icon)
                .font(.title3)
                .foregroundStyle(Theme.green)
                .accessibilityHidden(true)
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
        .accessibilityLabel("Fortsätt \(state.sport.label.lowercased())match: \(state.teamName(state.homeSide)) mot \(state.teamName(state.awaySide)), \(state.scoreText)")
    }
}
