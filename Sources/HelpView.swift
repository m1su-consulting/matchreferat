import SwiftUI

/// How to bring a match into the app: it comes from the page in Safari, where the login is.
struct HelpView: View {
    var body: some View {
        List {
            Section("Fotboll – Min fotboll") {
                step(1, "Öppna minfotboll.svenskfotboll.se i Safari på telefonen och logga in.")
                step(2, "Öppna matchen.")
                step(3, "Tryck på de tre prickarna (…) i adressfältet och välj Dela.")
                step(4, "Välj Matchreferat. Syns den inte: tryck på Mer och slå på den.")
                Link("Öppna Min fotboll i Safari", destination: URL(string: "x-safari-https://minfotboll.svenskfotboll.se")!)
            }
            Section("Innebandy – Innebandy Play") {
                step(1, "Öppna play.innebandy.se i Safari på telefonen. Ingen inloggning behövs.")
                step(2, "Öppna matchen under Matcher.")
                step(3, "Tryck på de tre prickarna (…) i adressfältet och välj Dela.")
                step(4, "Välj Matchreferat.")
                Link("Öppna Innebandy Play i Safari", destination: URL(string: "x-safari-https://play.innebandy.se")!)
            }
            Section("Sedan") {
                Text("Matchen hamnar under Kommande matcher i appen. Du kan dela den redan dagen innan.")
                Text("Trupperna publiceras oftast ungefär en timme före avspark. Saknas de: tryck på matchen, välj Hämta trupperna och dela igen.")
                Text("Tryck på Starta när det är dags.")
            }
            Section("Länk från Min fotboll-appen") {
                Text("Under Ny match kan du klistra in länken eller texten du får när du delar matchen i Min fotboll-appen. Trupperna måste ändå hämtas från Safari, eftersom det bara är där du är inloggad.")
            }
        }
        .navigationTitle("Så hämtar du en match")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.accent)
            Text(text)
        }
    }
}
