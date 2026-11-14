import SwiftUI

/// A match shared from Min fotboll: check the names and who starts in both teams, then start.
struct ImportMatchSheet: View {
    @Environment(MatchStore.self) private var store
    @Environment(LiveShare.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State var match: ImportedMatch
    @State private var confirmDiscard = false
    @State private var fetching = false
    @State private var shareLive = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Hemma") {
                        TextField("Lagnamn", text: $match.home.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Borta") {
                        TextField("Lagnamn", text: $match.away.name)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Trupperna sparas med hela namnet på telefonen. Det som delas visar bara förnamn och nummer.")
                }
                Section {
                    if let day = match.kickoffDay {
                        DatePicker("Dag", selection: Binding(get: { day }, set: { setKickoff(day: $0) }),
                                   displayedComponents: .date)
                    } else {
                        Button("Välj dag") { setKickoff(day: .now) }
                    }
                    if match.kickoffTime != nil {
                        DatePicker("Tid", selection: Binding(get: { kickoffClock }, set: { setKickoff(time: $0) }),
                                   displayedComponents: .hourAndMinute)
                    } else {
                        Button("Välj tid") { setKickoff(time: kickoffClock) }
                    }
                } header: {
                    Text("Avspark")
                } footer: {
                    if match.kickoffDay == nil {
                        Text("Sidan visar inte vilken dag matchen spelas. Välj den här, så står den under Kommande matcher.")
                    }
                }
                // Also once the squads are in: the lineup can change right up to kickoff.
                if match.sport != nil, match.url != nil {
                    Section {
                        Button(action: fetchSquads) {
                            if fetching {
                                ProgressView()
                            } else {
                                Label(match.hasSquads ? "Uppdatera trupperna" : "Hämta trupperna",
                                      systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(fetching)
                    } footer: {
                        Text(match.hasSquads ? "Trupperna hämtas på nytt från Innebandy Play."
                             : "Trupperna hämtas från Innebandy Play när lagen har lagt in dem.")
                    }
                } else if let url = match.safariURL {
                    Section {
                        Link(destination: url) {
                            Label(match.hasSquads ? "Uppdatera trupperna" : "Hämta trupperna", systemImage: "safari")
                        }
                    } footer: {
                        Text(match.hasSquads
                             ? "Matchen öppnas i Safari, där du är inloggad. Öppna fliken Lineup och dela den till Matchreferat igen, så uppdateras trupperna."
                             : "Matchen öppnas i Safari. Dela den till Matchreferat igen, så kommer trupperna med. De publiceras ungefär en timme före avspark.")
                    }
                }
                if live.isConfigured {
                    Section {
                        Toggle("Dela live direkt", isOn: $shareLive)
                            .tint(Theme.accent)
                    } footer: {
                        Text("Matchen syns under Pågår nu och kan följas med en länk. Spelare visas med förnamn och nummer.")
                    }
                }
                if !match.home.players.isEmpty { squad($match.home) }
                if !match.away.players.isEmpty { squad($match.away) }
            }
            .navigationTitle("Kommande match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starta") {
                        if store.hasUnfinishedMatch { confirmDiscard = true } else { start() }
                    }
                }
            }
            .onChange(of: store.plannedMatches) {
                // New squads shared from Safari while this sheet was open.
                if let latest = store.plannedMatches.first(where: { $0.id == match.id }) { match = latest }
            }
            .alert("Avsluta pågående match?", isPresented: $confirmDiscard) {
                Button("Starta ny match", role: .destructive) { start() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Händelserna i den pågående matchen försvinner.")
            }
        }
        .tint(Theme.accent)
    }

    private func squad(_ team: Binding<ImportedTeam>) -> some View {
        Section {
            ForEach(team.players) { $player in
                if match.sport == nil {
                    Toggle(isOn: $player.starts) { row(player) }
                        .tint(Theme.accent)
                } else {
                    row(player)  // Floorball changes lines all the time, so nobody is marked as starting.
                }
            }
        } header: {
            HStack {
                Text(team.wrappedValue.name)
                Spacer()
                if match.sport == nil {
                    Text("\(team.wrappedValue.players.filter(\.starts).count) startar")
                }
            }
        }
    }

    /// The kickoff time as a date today, for the time picker. 12:00 until a time is set.
    private var kickoffClock: Date {
        let parts = (match.kickoffTime ?? "12:00").split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 12, minute: parts.count > 1 ? parts[1] : 0,
                                     second: 0, of: .now) ?? .now
    }

    /// Saves the kickoff right away, so it shows under Kommande matcher even if the match isn't started.
    private func setKickoff(day: Date? = nil, time: Date? = nil) {
        if let day { match.kickoffDay = Calendar.current.startOfDay(for: day) }
        if let time {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            match.kickoffTime = formatter.string(from: time)
        }
        MatchImport.update(match)
        store.refreshPlanned()
    }

    private func fetchSquads() {
        guard let url = match.url else { return }
        fetching = true
        Task {
            if let read = await FloorballPage.read(url, in: NewMatchSheet.window) {
                MatchImport.add(read)
                store.refreshPlanned()
            }
            fetching = false
        }
    }

    private func row(_ player: ImportedPlayer) -> some View {
        HStack(spacing: 10) {
            Text("\(player.number)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 32, alignment: .trailing)
            Text("\(player.firstName) \(player.lastName)")
        }
    }

    private func start() {
        Task {
            await live.stop()
            store.startImportedMatch(match)
            if shareLive { await live.start(store.state) }
            dismiss()
        }
    }
}
