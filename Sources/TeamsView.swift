import SwiftUI

/// The "Lag" tab: the teams the user reports for, each with its squad and default match settings.
struct TeamsView: View {
    @Environment(MatchStore.self) private var store
    @State private var showNewMatch = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    Button { showNewMatch = true } label: {
                        Label("Ny match", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .disabled(store.teams.isEmpty)
                }

                Section("Mina lag") {
                    if store.teams.isEmpty {
                        Text("Inga lag än").foregroundStyle(.secondary)
                    }
                    ForEach($store.teams) { $team in
                        NavigationLink {
                            TeamEditor(team: $team)
                        } label: {
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
                    Button("Lägg till exempellag") { store.addExampleTeam() }
                        .disabled(store.teams.contains { $0.id == MatchState.exampleTeamID })
                    Button("Återställ exempelmatch", role: .destructive) { confirmReset = true }
                } header: {
                    Text("Exempel")
                } footer: {
                    Text("Exempellaget och exempelmatchen har påhittade spelare.")
                }
            }
            .navigationTitle("Lag")
            .sheet(isPresented: $showNewMatch) { NewMatchSheet() }
            .alert("Återställa exempelmatchen?", isPresented: $confirmReset) {
                Button("Återställ", role: .destructive) { store.reset() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Den pågående matchen ersätts med exempelmatchen.")
            }
        }
    }
}

struct TeamEditor: View {
    @Binding var team: Team
    @State private var newFirstName = ""
    @State private var newLastName = ""
    @State private var newNumber = ""

    var body: some View {
        Form {
            Section("Lag") {
                TextField("Lagnamn", text: $team.name)
                    .textInputAutocapitalization(.words)
                FormatFields(playersOnField: $team.playersOnField, periods: $team.periods,
                             periodLength: $team.periodLength)
            }

            Section {
                ForEach($team.players) { $player in
                    HStack(spacing: 10) {
                        TextField("Nr", value: $player.number, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 40)
                            .padding(.vertical, 6)
                            .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        TextField("Förnamn", text: $player.firstName)
                            .textInputAutocapitalization(.words)
                        TextField("Efternamn", text: $player.lastName)
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { team.players.remove(atOffsets: $0) }
                .onMove { team.players.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Trupp · \(team.players.count) spelare")
            } footer: {
                Text("Efternamn är frivilligt och visas bara i appen. Det som delas visar förnamn och nummer.")
            }

            Section("Lägg till spelare") {
                TextField("Förnamn", text: $newFirstName)
                    .textInputAutocapitalization(.words)
                TextField("Efternamn (frivilligt)", text: $newLastName)
                    .textInputAutocapitalization(.words)
                TextField("Nummer", text: $newNumber)
                    .keyboardType(.numberPad)
                Button("Lägg till") {
                    team.players.append(Player(firstName: newFirstName.trimmingCharacters(in: .whitespaces),
                                               lastName: newLastName.trimmingCharacters(in: .whitespaces),
                                               number: Int(newNumber) ?? 0))
                    newFirstName = ""
                    newLastName = ""
                    newNumber = ""
                }
                .disabled(newFirstName.trimmingCharacters(in: .whitespaces).isEmpty || Int(newNumber) == nil)
            }
        }
        .navigationTitle(team.name.isEmpty ? "Lag" : team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}

/// Spelform, number of periods and minutes per period.
struct FormatFields: View {
    @Binding var playersOnField: Int
    @Binding var periods: Int
    @Binding var periodLength: Int
    /// In the team editor a new format also suggests a typical period length.
    var suggestsLength = true

    var body: some View {
        Picker("Spelform", selection: $playersOnField) {
            ForEach(Team.formats, id: \.self) { Text(Team.formatLabel($0)).tag($0) }
        }
        .onChange(of: playersOnField) { _, format in
            if suggestsLength { periodLength = Team.defaultPeriodLength(for: format) }
        }
        Stepper("Perioder: \(periods)", value: $periods, in: 1...4)
        Picker("Minuter per period", selection: $periodLength) {
            ForEach(Team.periodLengths, id: \.self) { Text("\($0) min").tag($0) }
        }
    }
}

/// Today's lineup: everyone in the squad with Start / Bänk / Ej med and a count against the format.
struct LineupSection: View {
    @Binding var players: [Player]
    let playersOnField: Int

    var body: some View {
        let starting = players.filter { $0.status == .start }.count
        Section {
            ForEach($players) { $player in
                PlayerRow(player: $player)
            }
            .onDelete { players.remove(atOffsets: $0) }
        } header: {
            HStack {
                Text("Trupp")
                Spacer()
                Text("\(starting) av \(playersOnField) på plan")
                    .foregroundStyle(starting == playersOnField ? Color.secondary : Color.orange)
            }
        } footer: {
            if starting != playersOnField {
                Text(starting > playersOnField ? "Fler än \(playersOnField) står på Start." : "Färre än \(playersOnField) står på Start.")
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Adds a player to this match, optionally also to the team's squad.
struct AddMatchPlayerSection: View {
    let add: (Player, Bool) -> Void
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var number = ""
    @State private var saveInSquad = true

    var body: some View {
        Section("Lägg till spelare") {
            TextField("Förnamn", text: $firstName)
                .textInputAutocapitalization(.words)
            TextField("Efternamn (frivilligt)", text: $lastName)
                .textInputAutocapitalization(.words)
            TextField("Nummer", text: $number)
                .keyboardType(.numberPad)
            Toggle("Spara i truppen", isOn: $saveInSquad)
                .tint(Theme.green)
            Button("Lägg till") {
                add(Player(firstName: firstName.trimmingCharacters(in: .whitespaces),
                           lastName: lastName.trimmingCharacters(in: .whitespaces),
                           number: Int(number) ?? 0, status: .bench), saveInSquad)
                firstName = ""
                lastName = ""
                number = ""
            }
            .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || Int(number) == nil)
        }
    }
}
