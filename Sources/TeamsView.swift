import SwiftUI

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
                LabeledContent("Sport") {
                    // A Label here gets a tall empty row on iOS 27, so icon and text are laid out by hand.
                    HStack(spacing: 6) {
                        Image(systemName: team.sport.icon).foregroundStyle(Theme.accent)
                        Text(team.sport.label)
                    }
                }
                FormatFields(sport: team.sport, playersOnField: $team.playersOnField, periods: $team.periods,
                             periodLength: $team.periodLength)
            }

            Section {
                ForEach($team.players) { $player in
                    HStack(spacing: 10) {
                        TextField("Nr", value: $player.number, format: .number)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Tröjnummer för \(player.firstName)")
                            .multilineTextAlignment(.center)
                            .frame(width: 40)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        TextField("Förnamn", text: $player.firstName)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel("Förnamn, nummer \(player.number)")
                        TextField("Efternamn", text: $player.lastName)
                            .accessibilityLabel("Efternamn för \(player.firstName)")
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { team.players.remove(atOffsets: $0) }
            } header: {
                Text("Trupp · \(team.players.count) spelare")
            } footer: {
                Text("Svep åt vänster för att ta bort en spelare. Efternamn är frivilligt och visas bara i appen. Det som delas visar förnamn och nummer.")
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
                    // Matches list players by number, so the squad does too.
                    team.players.sort { $0.number < $1.number }
                    newFirstName = ""
                    newLastName = ""
                    newNumber = ""
                }
                .disabled(newFirstName.trimmingCharacters(in: .whitespaces).isEmpty || Int(newNumber) == nil)
            }
        }
        .navigationTitle(team.name.isEmpty ? "Lag" : team.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Spelform, number of periods and minutes per period: 1–4 halvlekar in football, 2 or 3 perioder in floorball.
struct FormatFields: View {
    var sport: Sport = .football
    @Binding var playersOnField: Int
    @Binding var periods: Int
    @Binding var periodLength: Int
    /// In the team editor a new format also suggests a typical period length.
    var suggestsLength = true

    var body: some View {
        Picker("Spelform", selection: $playersOnField) {
            ForEach(Self.options(Team.formats(sport), including: playersOnField), id: \.self) {
                Text(Team.formatLabel($0)).tag($0)
            }
        }
        .onChange(of: playersOnField) { _, format in
            if suggestsLength { periodLength = Team.defaultPeriodLength(for: format, sport: sport) }
        }
        switch sport {
        case .football:
            Stepper("Antal halvlekar: \(periods)", value: $periods, in: sport.periodRange)
        case .floorball:
            Picker("Antal perioder", selection: $periods) {
                ForEach(Self.options(Array(sport.periodRange), including: periods), id: \.self) {
                    Text("\($0) perioder").tag($0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Antal perioder")
        }
        Picker("Minuter per \(sport.periodWord)", selection: $periodLength) {
            ForEach(Self.options(Team.periodLengths(sport), including: periodLength), id: \.self) { Text("\($0) min").tag($0) }
        }
    }

    /// The choices plus the current value, so a picker never shows an empty selection.
    static func options(_ values: [Int], including current: Int) -> [Int] {
        values.contains(current) ? values : (values + [current]).sorted()
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
                .tint(Theme.accent)
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
