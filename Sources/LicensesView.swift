import SwiftUI

/// Copyright and third-party licenses.
struct LicensesView: View {
    private let apache = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

    var body: some View {
        List {
            Section("Matchreferat") {
                Text("© 2026 M1SU Consulting AB. Källkoden finns på github.com/m1su-consulting/matchreferat.")
            }
            Section {
                Text("Appen använder inga tredjepartsbibliotek, bara Apples egna ramverk.")
            } header: {
                Text("I appen")
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Firebase JavaScript SDK").font(.headline)
                    Text("Google LLC · Apache License 2.0").font(.subheadline).foregroundStyle(.secondary)
                    Text("Används av webbsidan som visar livelänkar.").font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink("Apache License 2.0") {
                    ScrollView {
                        Text(apache)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle("Apache License 2.0")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } header: {
                Text("Livesidan")
            }
        }
        .navigationTitle("Licenser")
        .navigationBarTitleDisplayMode(.inline)
    }
}
