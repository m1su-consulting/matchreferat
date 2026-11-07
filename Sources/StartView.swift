import SwiftUI

/// The start page for one sport: picture, start or continue a match, and the sport's teams.
struct StartView: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @State private var showNewMatch = false
    @State private var confirmDelete = false
    @State private var browserPage: BrowserPage?
    @State private var importing: ImportedMatch?

    private var sport: Sport { store.sport ?? .football }

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                VStack(spacing: 18) {
                    SportHeader(sport: sport, changeSport: { store.sport = nil }, openSettings: { store.path.append(.settings) })
                    Button { showNewMatch = true } label: {
                        Label("Ny match", systemImage: "plus.circle.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if store.hasMatchInProgress(in: sport) {
                Section("Pågående match") {
                    Button { store.openMatch() } label: { ContinueCard() }
                        .buttonStyle(.plain)
                        .contextMenu { matchActions }
                        .swipeActions { matchActions }
                }
            } else if store.hasMatchInProgress {
                // Only one match at a time: say discreetly that the other sport has one.
                Section {
                    Button { store.sport = store.state.sport } label: {
                        Label("Pågående \(store.state.sport.label.lowercased())match – tryck för att byta sport",
                              systemImage: store.state.sport.icon)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let server = live.server {
                OngoingSection(list: live.ongoing.filtered(sport), serverName: server.name) { match in
                    browserPage = BrowserPage(url: server.viewerURL(matchID: match.id))
                }
            }

            let planned = store.plannedMatches.filter { ($0.sport == nil) == (sport == .football) }
            if planned.isEmpty && !store.hasMatchInProgress(in: sport) {
                Section {
                    NavigationLink(value: Route.help) {
                        Text("Så här hämtar du en match från \(sport.matchSite)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !planned.isEmpty {
                Section("Kommande matcher") {
                    ForEach(planned) { match in
                        Button { importing = match } label: { PlannedMatchRow(match: match) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in offsets.map { planned[$0].id }.forEach(store.deletePlanned) }
                }
            }

            let saved = store.savedMatches.filter { $0.state.sport == sport }
            if !saved.isEmpty {
                Section("Sparade matcher") {
                    ForEach(saved) { match in
                        NavigationLink(value: Route.savedMatch(match.id)) {
                            LabeledContent {
                                Text(match.state.scoreText)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.primary)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(match.state.teamName(match.state.homeSide)) – \(match.state.teamName(match.state.awaySide))")
                                        .font(.headline)
                                    Text(match.savedAt, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { saved[$0].id }.forEach(store.deleteSavedMatch) }
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
        .sheet(item: $importing) { ImportMatchSheet(match: $0) }
        .modifier(DeleteMatchConfirmation(isPresented: $confirmDelete))
        .onAppear {
            // `-demoSheet newMatch` opens the new match sheet (used for screenshots).
            if LaunchArgument.string("demoSheet") == "newMatch" { showNewMatch = true }
            // `-demoSheet import` shows an imported match with fictional players.
            if LaunchArgument.string("demoSheet") == "import" { importing = .example }
            // `-demoSheet planned` adds it to Kommande matcher.
            if LaunchArgument.string("demoSheet") == "planned" {
                MatchImport.add(.example)
                store.refreshPlanned()
            }
        }
    }

    /// End or delete the ongoing match without opening it.
    @ViewBuilder private var matchActions: some View {
        Button(role: .destructive) { confirmDelete = true } label: { Label("Ta bort match", systemImage: "trash") }
        Button { store.endMatch() } label: { Label("Avsluta match", systemImage: "flag.checkered") }
            .tint(Theme.accent)
    }
}

/// The sport's picture with the app name, a button back to the sport picker and the settings gear.
/// The buttons sit beside the name, not on the picture, so they are easy to see whatever the picture shows.
struct SportHeader: View {
    let sport: Sport
    let changeSport: () -> Void
    let openSettings: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 12) {
            SportPicture(sport: sport)
            // With the largest text sizes the buttons go under the name, so nothing is cut off.
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    title
                    buttons
                }
            } else {
                HStack(spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    buttons
                }
            }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Image(systemName: sport.icon)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Matchreferat")
                .font(.title.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Matchreferat, \(sport.label)")
        .accessibilityAddTraits(.isHeader)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            SettingsButton(action: openSettings)
            changeButton
        }
    }

    private var changeButton: some View {
        Button(action: changeSport) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                Text("Byt sport").lineLimit(1)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            // Same glass as "Dela live" on the match page; Ny match below stays the only filled button.
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHint("Visar sportvalet")
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
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: Capsule())
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
            VStack(spacing: 14) {
                HStack {
                    Logo()
                    Spacer(minLength: 8)
                    SettingsButton { store.path.append(.settings) }
                }
                Text("Vilken sport ska du referera?")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                ForEach(Sport.allCases) { sport in
                    Button { store.sport = sport } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            SportPicture(sport: sport)
                            Text(statusText(sport))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(sport.label), \(statusText(sport))")
                    .accessibilityAddTraits(.isButton)
                }
                MadeBy(logoHeight: 40)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        // Everything fits on one screen, and only scrolls with large text.
        .scrollBounceBehavior(.basedOnSize)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func statusText(_ sport: Sport) -> String {
        if store.hasMatchInProgress(in: sport) { return "Pågående match" }
        let planned = store.plannedMatches.filter { ($0.sport == nil) == (sport == .football) }.count
        let saved = store.savedMatches.filter { $0.state.sport == sport }.count
        return planned > 0 ? "\(planned) kommande" : saved > 0 ? "\(saved) sparade" : "Inga matcher än"
    }
}

/// A shared match waiting to be started.
struct PlannedMatchRow: View {
    let match: ImportedMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(match.home.name) – \(match.away.name)").font(.headline)
            Text(match.hasSquads ? "\(match.home.players.count) och \(match.away.players.count) spelare" : "Trupperna är inte hämtade än")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The round gear that opens the settings, on the sport picker and the start page.
struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inställningar")
    }
}

/// The app name as the sport picker's heading.
struct Logo: View {
    var body: some View {
        Text("Matchreferat")
            .font(.largeTitle.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Small "Utvecklad av" credit with Mikael's M1SU Consulting logo.
struct MadeBy: View {
    var logoHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 8) {
            Text("Utvecklad av")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The logo has its own metal frame on white, so it only needs rounded corners and a soft shadow.
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: logoHeight)
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
                .foregroundStyle(Theme.accent)
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
