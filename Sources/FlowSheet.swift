import SwiftUI

struct FlowSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let flow: Flow

    @State private var step = 0
    @State private var firstPlayer: UUID?
    @AppStorage(AppSettings.hapticsKey) private var haptics = true
    /// 2 min unless another kind is chosen.
    @State private var suspension: Suspension = .two

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
        .sensoryFeedback(.selection, trigger: step) { _, _ in haptics }
    }

    private var title: String {
        switch flow {
        case .goal(let side): "Mål – \(store.state.teamName(side))"
        case .card(let kind, let side): "\(kind.label) – \(store.state.teamName(side))"
        case .sub(let side): "Byte – \(store.state.teamName(side))"
        case .penalty(let side): "Straff – \(store.state.teamName(side))"
        case .suspension(let side): "Utvisning – \(store.state.teamName(side))"
        }
    }

    @ViewBuilder
    private var content: some View {
        let state = store.state
        switch flow {
        case .goal(let side):
            if step == 0 {
                PlayerPicker(prompt: "Vem gjorde målet?", players: state.pickable(side), skip: "Okänd") { id in
                    firstPlayer = id
                    step = 1
                }
            } else {
                PlayerPicker(prompt: "Assist?", players: state.pickable(side).filter { $0.id != firstPlayer },
                             skip: "Ingen assist") { id in
                    finish(.goal, side, player: firstPlayer, otherPlayer: id)
                }
            }
        case .card(let kind, let side):
            PlayerPicker(prompt: "Vem fick kortet?", players: state.playingToday(side), skip: "Okänd") { id in
                finish(kind, side, player: id)
            }
        case .penalty(let side):
            // Without a squad, as for a team that is just a name, only the result is asked for.
            if step == 0 && !state.playingToday(side).isEmpty {
                PlayerPicker(prompt: "Vem slog straffen?", players: state.pickable(side), skip: "Okänd") { id in
                    firstPlayer = id
                    step = 1
                }
            } else {
                PenaltyResultPicker { result in
                    store.logPenalty(side: side, player: firstPlayer, result: result)
                    dismiss()
                }
            }
        case .suspension(let side):
            VStack(alignment: .leading, spacing: 18) {
                SuspensionPicker(selection: $suspension)
                PlayerPicker(prompt: "Vem blev utvisad?", players: state.playingToday(side), skip: "Okänd") { id in
                    finish(.suspension, side, player: id, suspension: suspension)
                }
            }
        case .sub(let side):
            // Normally Start goes out and Bänk comes in. If either list is empty (no lineup set),
            // everyone playing today can be picked instead of leaving an empty sheet.
            let onField = state.onField(side), bench = state.bench(side), everyone = state.playingToday(side)
            if step == 0 {
                PlayerPicker(prompt: "Vem går ut?", players: onField.isEmpty ? everyone : onField, skip: nil) { id in
                    firstPlayer = id
                    step = 1
                }
            } else {
                PlayerPicker(prompt: "Vem kommer in?", players: bench.isEmpty ? everyone.filter { $0.id != firstPlayer } : bench,
                             skip: nil) { id in
                    finish(.sub, side, player: firstPlayer, otherPlayer: id)
                }
            }
            if onField.isEmpty || bench.isEmpty {
                Text("Vilka som startar och sitter på bänken väljer du under ⋯ → Dagens trupp.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finish(_ kind: EventKind, _ side: Side, player: UUID? = nil, otherPlayer: UUID? = nil,
                        shot: ShotResult? = nil, suspension: Suspension? = nil) {
        store.log(kind, side: side, player: player, otherPlayer: otherPlayer, shot: shot, suspension: suspension)
        dismiss()
    }
}

/// Mål, Räddad or Miss for a penalty.
struct PenaltyResultPicker: View {
    let pick: (PenaltyResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hur gick straffen?").font(.title3.bold())
            ForEach(PenaltyResult.allCases, id: \.self) { result in
                Button { pick(result) } label: {
                    Label(result.label, systemImage: result.icon)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(result == .scored ? Theme.accent : .primary)
                .accessibilityLabel("Straff: \(result.label)")
            }
        }
    }
}

/// 2 min (preselected), 5 min, 10 min or Matchstraff for a floorball utvisning.
struct SuspensionPicker: View {
    @Binding var selection: Suspension

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Utvisning").font(.title3.bold())
            Picker("Utvisning", selection: $selection) {
                ForEach(Suspension.allCases) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(selection.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                        .tint(Theme.accent)
                }
            }
            if players.isEmpty, let skip {
                Text("Inga spelare inlagda. Tryck på \"\(skip)\" för att spara utan spelare.")
                    .foregroundStyle(.secondary)
            } else if players.isEmpty {
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
                .background(Theme.accent, in: Circle())
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.name), nummer \(player.number)")
        .accessibilityAddTraits(.isButton)
    }
}
