import SwiftUI

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
    var title = "Trupp"
    /// Floorball changes lines all the time, so only football counts against the format.
    var countsStarters = true

    var body: some View {
        let starting = players.filter { $0.status == .start }.count
        Section {
            ForEach($players) { $player in
                PlayerRow(player: $player)
            }
            .onDelete { players.remove(atOffsets: $0) }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if countsStarters {
                    Text("\(starting) av \(playersOnField) på plan")
                        .foregroundStyle(starting == playersOnField ? Color.secondary : Color.orange)
                }
            }
        } footer: {
            if countsStarters && starting != playersOnField {
                Text(starting > playersOnField ? "Fler än \(playersOnField) står på Start." : "Färre än \(playersOnField) står på Start.")
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Adds a player to one of today's teams.
struct AddMatchPlayerSection: View {
    let names: [(side: Side, name: String)]
    let add: (Player, Side) -> Void
    @State private var side = Side.us
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var number = ""

    var body: some View {
        Section("Lägg till spelare") {
            Picker("Lag", selection: $side) {
                ForEach(names, id: \.side) { Text($0.name).tag($0.side) }
            }
            TextField("Förnamn", text: $firstName)
                .textInputAutocapitalization(.words)
            TextField("Efternamn (frivilligt)", text: $lastName)
                .textInputAutocapitalization(.words)
            TextField("Nummer", text: $number)
                .keyboardType(.numberPad)
            Button("Lägg till") {
                add(Player(firstName: firstName.trimmingCharacters(in: .whitespaces),
                           lastName: lastName.trimmingCharacters(in: .whitespaces),
                           number: Int(number) ?? 0, status: .bench), side)
                firstName = ""
                lastName = ""
                number = ""
            }
            .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || Int(number) == nil)
        }
    }
}
