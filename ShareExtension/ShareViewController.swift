import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet entry: reads the Min fotboll page open in Safari and leaves the match for the app.
final class ShareViewController: UIViewController {
    private var host: UIHostingController<ShareResultView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        show(.reading)
        Task { await read() }
    }

    private func show(_ state: ShareResultView.State) {
        let root = ShareResultView(state: state) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        if let host {
            host.rootView = root
            return
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        self.host = host
    }

    private func read() async {
        guard let match = await pageMatch() else {
            show(.failed)
            return
        }
        MatchImport.add(match)
        show(.done(match))
    }

    private func pageMatch() async -> ImportedMatch? {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let type = UTType.propertyList.identifier
        guard let provider = items.flatMap({ $0.attachments ?? [] }).first(where: { $0.hasItemConformingToTypeIdentifier(type) }),
              let item = try? await provider.loadItem(forTypeIdentifier: type),
              let dictionary = item as? NSDictionary,
              let page = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
              page["supported"] as? Bool == true else { return nil }
        if page["sport"] as? String == "floorball" {
            let url = page["url"] as? String ?? ""
            return FloorballPage.isMatchLink(url) ? await FloorballPage.read(url, in: view) : nil
        }
        return MatchImport.parse(names: page["names"] as? [String] ?? [], lines: page["lines"] as? [String] ?? [], url: page["url"] as? String)
    }
}

struct ShareResultView: View {
    enum State {
        case reading, failed
        case done(ImportedMatch)
    }

    let state: State
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            switch state {
            case .reading:
                ProgressView("Läser matchen…")
            case .failed:
                Image(systemName: "exclamationmark.circle").font(.largeTitle).foregroundStyle(.orange)
                Text("Det här är ingen matchsida").font(.title3.bold())
                Text("Tryck på själva matchen på Min fotboll eller Innebandy Play, så att båda lagen syns, och dela igen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .done(let match):
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("\(match.home.name) – \(match.away.name)").font(.title3.bold()).multilineTextAlignment(.center)
                Text(match.hasSquads
                     ? "Matchen ligger under Kommande matcher i Matchreferat."
                     : "Matchen ligger under Kommande matcher. Trupperna hämtas när du delar fliken Lineup efter att de är publicerade.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Klar", action: close)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
    }
}
