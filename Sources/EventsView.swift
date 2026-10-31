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
                        EventRow(event: event)
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
                    .tint(Theme.green)
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

struct EventRow: View {
    @Environment(MatchStore.self) private var store
    let event: MatchEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.minute.text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 48, alignment: .leading)
            Image(systemName: event.kind.icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.state.describe(event))
                    .fontWeight(event.kind == .goal ? .semibold : .regular)
                Text(event.kind == .period ? "Match" : store.state.teamName(event.side))
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
        default: Theme.color(event.side)
        }
    }
}
