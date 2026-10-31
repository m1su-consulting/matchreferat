import SwiftUI

enum Flow: Identifiable, Hashable {
    case goal
    case shot(ShotResult)
    case card(EventKind)
    case sub

    var id: String { "\(self)" }
}

struct MatchView: View {
    @Environment(MatchStore.self) private var store
    @State private var flow: Flow?
    @State private var showSquad = false
    @State private var showSettings = false
    @State private var showEvents = false
    @State private var showNewMatch = false

    var body: some View {
        // Sized to fit one screen above the tab bar on current iPhones; scrolls on smaller ones.
        // The toast sits below the scroll view, so it is always just above the tab bar.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Button { store.showMatch = false } label: {
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
                            Button { showNewMatch = true } label: { Label("Ny match", systemImage: "plus.circle") }
                            Button { store.showMatch = false } label: { Label("Till startsidan", systemImage: "house") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.green)
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
        .sensoryFeedback(.impact(weight: .medium), trigger: store.state.events.count)
        .onAppear {
            // `-demoSheet goal|squad|newMatch` opens that sheet (used for screenshots).
            switch UserDefaults.standard.string(forKey: "demoSheet") {
            case "goal": flow = .goal
            case "squad": showSquad = true
            case "settings": showSettings = true
            case "events": showEvents = true
            case "newMatch": showNewMatch = true
            default: break
            }
        }
    }
}

struct ScoreboardView: View {
    @Environment(MatchStore.self) private var store

    var body: some View {
        let state = store.state
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                team(state.homeSide)
                Text("\(state.goals(state.homeSide))–\(state.goals(state.awaySide))")
                    .font(.system(size: 50, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
                team(state.awaySide)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(state.clock(at: context.date).text)
                        .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
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
            .buttonStyle(.borderedProminent)
            .tint(Theme.green)

            if phase == .playing {
                Button { store.togglePause() } label: {
                    Image(systemName: store.state.isRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
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

    /// Events logged for both teams. The opponent is only a team name: no player data, no cards.
    private let sharedRows: [Action] = [.event(.goal), .shot(.onTarget), .shot(.off), .event(.corner), .event(.freeKick)]
    /// Events only we log, shown as one row of compact tiles.
    private let ourOnly: [EventKind] = [.yellow, .red, .sub]

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
        let (label, icon, count): (String, String, Int) = switch action {
        case .event(let kind): (kind.label, kind.icon, store.state.count(kind, side))
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
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(store.state.teamName(side)), \(count)")
    }

    private func tile(_ kind: EventKind) -> some View {
        let count = store.state.count(kind, .us)
        return Button { flow = kind == .sub ? .sub : .card(kind) } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: kind.icon)
                        .font(.body)
                        .foregroundStyle(kind == .yellow ? .yellow : kind == .red ? .red : Theme.green)
                    Text("\(count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(count > 0 ? Theme.green : Color.secondary)
                }
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.label) \(store.state.ourTeam), \(count)")
    }

    private func tap(_ action: Action, _ side: Side) {
        switch (action, side) {
        case (.event(.goal), .us): flow = .goal
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
