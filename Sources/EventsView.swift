import SwiftUI

struct EventsView: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let timeline = store.state.events.sorted { $0.createdAt > $1.createdAt }
        NavigationStack {
            List {
                Section("Tidslinje") {
                    if timeline.isEmpty {
                        Text("Inga händelser än").foregroundStyle(.secondary)
                    }
                    ForEach(timeline) { event in
                        EventRow(event: event, state: store.state)
                    }
                    .onDelete { offsets in
                        offsets.map { timeline[$0].id }.forEach(store.deleteEvent)
                    }
                }

                Section("Referat för Messenger") {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(store.state.report(at: context.date))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = store.state.report(at: .now)
                            copied = true
                        } label: {
                            Label(copied ? "Kopierat" : "Kopiera", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        ShareLink(item: store.state.report(at: .now)) {
                            Label("Dela", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Theme.accent)
                }
            }
            .navigationTitle("Händelser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
    }
}

/// A saved match: the result, the timeline with full names and the report to share.
struct SavedMatchView: View {
    let match: SavedMatch

    var body: some View {
        let state = match.state
        List {
            Section {
                VStack(spacing: 6) {
                    Text(state.scoreText).font(.largeTitle.weight(.heavy).monospacedDigit())
                    Text(state.statsLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text(match.savedAt, format: .dateTime.day().month().year())
            }
            Section("Tidslinje") {
                ForEach(state.events.sorted { $0.createdAt > $1.createdAt }) { event in
                    EventRow(event: event, state: state)
                }
            }
            Section {
                ShareLink(item: state.report(at: match.savedAt)) {
                    Label("Dela referat", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("\(state.teamName(state.homeSide)) – \(state.teamName(state.awaySide))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EventRow: View {
    let event: MatchEvent
    let state: MatchState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.minute.text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 48, alignment: .leading)
            Image(systemName: event.kind == .goal && event.isPenalty == true ? EventKind.penalty.icon : event.kind.icon(for: state.sport))
                .accessibilityHidden(true)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.describe(event))
                    .fontWeight(event.kind == .goal ? .semibold : .regular)
                Text(event.kind == .period ? "Match" : state.teamName(event.side))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch event.kind {
        case .period: .secondary
        case .yellow: .yellow
        case .red: .red
        case .suspension: .orange
        default: Theme.color(event.side)
        }
    }
}
