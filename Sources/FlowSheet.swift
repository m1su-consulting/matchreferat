import SwiftUI

struct FlowSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let flow: Flow

    @State private var step = 0
    @State private var firstPlayer: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                content.padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step > 0 {
                        Button("Tillbaka") { step -= 1 }
                    } else {
                        Button("Avbryt") { dismiss() }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
    }

    private var title: String {
        switch flow {
        case .goal: "Mål – Vi"
        case .shot(let result): result == .onTarget ? "Skott på mål" : "Skott utanför"
        case .card(let kind): kind.label
        case .sub: "Byte"
        }
    }

    @ViewBuilder
    private var content: some View {
        let state = store.state
        switch flow {
        case .goal:
            if step == 0 {
                PlayerPicker(prompt: "Vem gjorde målet?", players: state.onField, skip: "Okänd") { id in
                    firstPlayer = id
                    step = 1
                }
            } else {
                PlayerPicker(prompt: "Assist?", players: state.onField.filter { $0.id != firstPlayer },
                             skip: "Ingen assist") { id in
                    finish(.goal, .us, player: firstPlayer, otherPlayer: id)
                }
            }
        case .shot(let result):
            PlayerPicker(prompt: "Vem sköt?", players: state.onField, skip: "Hoppa över") { id in
                finish(.shot, .us, player: id, shot: result)
            }
        case .card(let kind):
            PlayerPicker(prompt: "Vem fick kortet?", players: state.playingToday, skip: "Okänd") { id in
                finish(kind, .us, player: id)
            }
        case .sub:
            if step == 0 {
                PlayerPicker(prompt: "Vem går ut?", players: state.onField, skip: nil) { id in
                    firstPlayer = id
                    step = 1
                }
            } else {
                PlayerPicker(prompt: "Vem kommer in?", players: state.bench, skip: nil) { id in
                    finish(.sub, .us, player: firstPlayer, otherPlayer: id)
                }
            }
        }
    }

    private func finish(_ kind: EventKind, _ side: Side, player: UUID? = nil, otherPlayer: UUID? = nil, shot: ShotResult? = nil) {
        store.log(kind, side: side, player: player, otherPlayer: otherPlayer, shot: shot)
        dismiss()
    }
}

struct PlayerPicker: View {
    let prompt: String
    let players: [Player]
    let skip: String?
    let pick: (UUID?) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(prompt).font(.title3.bold())
                Spacer()
                if let skip {
                    Button(skip) { pick(nil) }
                        .font(.headline)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(Theme.green)
                }
            }
            if players.isEmpty {
                Text("Inga spelare att välja").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(players) { player in
                    Button { pick(player.id) } label: { PlayerChip(player: player) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PlayerChip: View {
    let player: Player

    var body: some View {
        HStack(spacing: 10) {
            Text("\(player.number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Theme.green, in: Circle())
            Text(player.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
