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
        MatchImport.save(match)
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
        return MatchImport.parse(names: page["names"] as? [String] ?? [], lines: page["lines"] as? [String] ?? [])
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
                Text("Hittade ingen trupp").font(.title3.bold())
                Text("Öppna matchen på Min fotboll i Safari, välj fliken Lineup och dela igen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .done(let match):
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("\(match.home.name) – \(match.away.name)").font(.title3.bold()).multilineTextAlignment(.center)
                Text("Öppna Matchreferat för att starta matchen.")
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
