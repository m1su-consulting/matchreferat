import SwiftUI

enum Flow: Identifiable, Hashable {
    case goal
    case shot(ShotResult)
    case card(EventKind)
    case sub
    case penalty(Side)
    case suspension

    var id: String { "\(self)" }
}

struct MatchView: View {
    @Environment(MatchStore.self) private var store
    @State private var flow: Flow?
    @State private var showSquad = false
    @State private var showSettings = false
    @State private var showEvents = false
    @State private var showNewMatch = false
    @State private var confirmDelete = false
    @AppStorage(AppSettings.keepScreenOnKey) private var keepScreenOn = true
    @AppStorage(AppSettings.hapticsKey) private var haptics = true

    /// The screen stays on while this page is open and the match isn't over, if the setting allows.
    private var screenStaysOn: Bool { keepScreenOn && store.state.phase != .finished }

    var body: some View {
        // Sized to fit one screen above the tab bar on current iPhones; scrolls on smaller ones.
        // The toast sits below the scroll view, so it is always just above the tab bar.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Button { store.goToStart() } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.semibold))
                                .frame(width: 30, height: 34)
                        }
                        .accessibilityLabel("Till startsidan")
                        HomeAwayPicker()
                        Menu {
                            Button { showEvents = true } label: { Label("Händelser och referat", systemImage: "list.bullet.rectangle") }
                            Button { showSquad = true } label: { Label("Dagens trupp", systemImage: "person.2") }
                            Button { showSettings = true } label: { Label("Matchinställningar", systemImage: "slider.horizontal.3") }
                            Divider()
                            if store.state.phase != .finished {
                                Button { store.endMatch() } label: { Label("Avsluta match", systemImage: "flag.checkered") }
                            }
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Ta bort match", systemImage: "trash") }
                            Divider()
                            Button { showNewMatch = true } label: { Label("Ny match", systemImage: "plus.circle") }
                            Button { store.goToStart() } label: { Label("Till startsidan", systemImage: "house") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("Mer")
                        LiveRow()
                    }
                    ScoreboardView()
                    ClockControls()
                    EventGrid(flow: $flow)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.bottom, 12, for: .scrollContent)

            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .task(id: store.toast?.id) {
            guard store.toast != nil else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            store.toast = nil
        }
        .sheet(isPresented: $showSquad, onDismiss: store.saveLineupToTeam) { MatchSquadSheet() }
        .sheet(isPresented: $showSettings) { MatchSettingsSheet() }
        .sheet(isPresented: $showEvents) { EventsView() }
        .sheet(isPresented: $showNewMatch) { NewMatchSheet() }
        .sheet(item: $flow) { flow in
            FlowSheet(flow: flow)
                .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: store.state.events.count) { _, _ in haptics }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = screenStaysOn }
        .onChange(of: screenStaysOn) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .modifier(DeleteMatchConfirmation(isPresented: $confirmDelete))
        .onAppear {
            // `-demoSheet goal|squad|newMatch` opens that sheet (used for screenshots).
            switch LaunchArgument.string("demoSheet") {
            case "goal": flow = .goal
            case "shot": flow = .shot(.onTarget)
            case "penalty": flow = .penalty(.us)
            case "suspension": flow = .suspension
            case "squad": showSquad = true
            case "settings": showSettings = true
            case "events": showEvents = true
            case "newMatch": showNewMatch = true
            default: break
            }
        }
    }
}

/// Asks before throwing the match away, then stops live sharing (deleting the server copy) and discards it.
struct DeleteMatchConfirmation: ViewModifier {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog("Ta bort matchen?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Ta bort match", role: .destructive) {
                Task {
                    await live.stop()
                    store.discardMatch()
                }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Matchen och alla händelser raderas. Om den delas live slutar länken att fungera.")
        }
    }
}

struct ScoreboardView: View {
    @Environment(MatchStore.self) private var store
    /// Score and clock grow with Dynamic Type, from these sizes at the default setting.
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 50
    @ScaledMetric(relativeTo: .title) private var clockSize: CGFloat = 26

    var body: some View {
        let state = store.state
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                team(state.homeSide)
                Text("\(state.goals(state.homeSide))–\(state.goals(state.awaySide))")
                    .font(.system(size: scoreSize, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
                team(state.awaySide)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(state.clock(at: context.date).text)
                        .font(.system(size: clockSize, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.clock)
                    Text(state.periodText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Text(state.statsLine)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.slab, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var accessibilitySummary: String {
        let s = store.state
        return "\(s.teamName(s.homeSide)) \(s.goals(s.homeSide)), \(s.teamName(s.awaySide)) \(s.goals(s.awaySide)). "
            + "\(s.clock(at: .now).text.replacingOccurrences(of: "'", with: "")) minuter, \(s.periodText). \(s.statsLine)"
    }

    private func team(_ side: Side) -> some View {
        VStack(spacing: 4) {
            Circle().fill(Theme.color(side)).frame(width: 8, height: 8)
            Text(store.state.teamName(side))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ClockControls: View {
    @Environment(MatchStore.self) private var store
    @State private var confirmEnd = false
    @State private var showNewMatch = false

    var body: some View {
        let phase = store.state.phase
        HStack(spacing: 12) {
            Button {
                switch phase {
                case .playing where store.state.isLastPeriod: confirmEnd = true
                case .finished: showNewMatch = true
                default: store.advancePhase()
                }
            } label: {
                Label(store.primaryTitle, systemImage: store.primaryIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)

            if phase == .playing {
                Button { store.togglePause() } label: {
                    Image(systemName: store.state.isRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(store.state.isRunning ? "Pausa klockan" : "Starta klockan")
            }
        }
        .sheet(isPresented: $showNewMatch) { NewMatchSheet() }
        .alert("Blås slutsignal?", isPresented: $confirmEnd) {
            Button("Slutsignal") { store.advancePhase() }
            Button("Avbryt", role: .cancel) {}
        }
    }
}

struct EventGrid: View {
    @Environment(MatchStore.self) private var store
    @Binding var flow: Flow?

    private enum Action: Hashable {
        case event(EventKind)
        case shot(ShotResult)
    }

    /// Events logged for both teams. The opponent is only a team name: no player data, no cards or utvisningar.
    private var sharedRows: [Action] {
        switch store.state.sport {
        case .football: [.event(.goal), .shot(.onTarget), .shot(.off), .event(.corner), .event(.freeKick), .event(.penalty)]
        case .floorball: [.event(.goal), .shot(.onTarget), .shot(.off), .event(.freeKick), .event(.penalty)]
        }
    }

    /// Events only we log, shown as one row of compact tiles.
    private var ourOnly: [EventKind] {
        switch store.state.sport {
        case .football: [.yellow, .red, .sub]
        case .floorball: [.suspension]  // Floorball subs happen all the time, so they aren't logged.
        }
    }

    var body: some View {
        let sides = [store.state.homeSide, store.state.awaySide]
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(sides, id: \.self) { side in
                    header(store.state.teamName(side), side)
                }
            }
            ForEach(sharedRows, id: \.self) { action in
                GridRow {
                    ForEach(sides, id: \.self) { side in button(action, side) }
                }
            }
            GridRow {
                header("Bara för \(store.state.ourTeam)", .us)
                    .gridCellColumns(2)
                    .padding(.top, 2)
            }
            GridRow {
                HStack(spacing: 8) {
                    ForEach(ourOnly, id: \.self) { kind in tile(kind) }
                }
                .gridCellColumns(2)
            }
        }
    }

    private func header(_ title: String, _ side: Side) -> some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .foregroundStyle(Theme.color(side))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func button(_ action: Action, _ side: Side) -> some View {
        let color = Theme.color(side)
        let sport = store.state.sport
        let (label, icon, count): (String, String, Int) = switch action {
        case .event(.penalty): (EventKind.penalty.label(for: sport), EventKind.penalty.icon(for: sport), store.state.penalties(side))
        case .event(let kind): (kind.label(for: sport), kind.icon(for: sport), store.state.count(kind, side))
        case .shot(let result): (result == .onTarget ? "Skott på mål" : "Skott utanför", result.icon, store.state.shotCount(result, side))
        }
        return Button { tap(action, side) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Text("\(count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(count > 0 ? color : Color.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .depthBackground(color)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressDownButtonStyle())
        .accessibilityLabel("\(label) \(store.state.teamName(side)), \(count)")
    }

    /// Football has one more row (Straff) than before 1.0.3, so its rows are a little lower to keep one screen.
    private var rowHeight: CGFloat { sharedRows.count > 5 ? 46 : 50 }

    private func tile(_ kind: EventKind) -> some View {
        let count = store.state.count(kind, .us)
        let label = kind.label(for: store.state.sport)
        return Button {
            switch kind {
            case .sub: flow = .sub
            case .suspension: flow = .suspension
            default: flow = .card(kind)
            }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: kind.icon(for: store.state.sport))
                        .font(.body)
                        .foregroundStyle(kind == .yellow ? .yellow : kind == .red ? .red : Theme.accent)
                    Text("\(count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(count > 0 ? Theme.accent : Color.secondary)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 54)
            .depthBackground(Theme.accent)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressDownButtonStyle())
        .accessibilityLabel("\(label) \(store.state.ourTeam), \(count)")
    }

    private func tap(_ action: Action, _ side: Side) {
        switch (action, side) {
        case (.event(.goal), .us): flow = .goal
        case (.event(.penalty), _): flow = .penalty(side)
        case (.shot(let result), .us): flow = .shot(result)
        case (.shot(let result), .them): store.log(.shot, side: .them, shot: result)
        case (.event(let kind), _): store.log(kind, side: side)
        }
    }
}

struct HomeAwayPicker: View {
    @Environment(MatchStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Picker("Vi spelar", selection: $store.state.isHome) {
            Text("Hemma").tag(true)
            Text("Borta").tag(false)
        }
        .pickerStyle(.segmented)
    }
}

struct ToastView: View {
    @Environment(MatchStore.self) private var store
    let toast: MatchStore.Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Button("Ångra") { store.undo(toast) }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.clock)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.slab.opacity(0.95), in: Capsule())
        .shadow(radius: 8, y: 3)
        .padding(.horizontal)
    }
}

/// The event buttons sink a little when pressed.
struct PressDownButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Subtle depth for the event buttons: a soft gradient, a light top edge and a small shadow.
    /// Not glass, because these have to stay easy to read in sunlight by the touchline.
    func depthBackground(_ color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return background {
            shape
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
        }
    }
}
