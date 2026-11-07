import UIKit
import WebKit

/// Reads a match on Innebandy Play. The pages are public, so the app can open them itself in a hidden web view,
/// and it shows one team at a time, so it opens the lineup once per team.
@MainActor
enum FloorballPage {
    private struct Snapshot: Decodable {
        var names: [String]
        var players: [[String: String]]
    }

    private static let script = """
    (function() {
      function all(name, root) { return Array.prototype.slice.call((root || document).querySelectorAll("[class*=" + name + "]")); }
      function text(name, root) { var found = all(name, root)[0]; return found ? found.textContent.trim() : ""; }
      return JSON.stringify({
        names: all("TeamInfoItem_Title").slice(0, 2).map(function(title) { return title.textContent.trim(); }),
        players: all("LineupPlayers_PlayerItem").map(function(item) {
          return { number: text("LineupPlayers_PlayerNumber", item), name: text("LineupPlayers_PlayerName", item) };
        })
      });
    })()
    """

    static func isMatchLink(_ url: String) -> Bool {
        URLComponents(string: url)?.host == "play.innebandy.se" && url.contains("/games/g/")
    }

    /// `host` keeps the web view in a window, or the page may not run. Nil if the page shows no match.
    static func read(_ url: String, in host: UIView?) async -> ImportedMatch? {
        guard var components = URLComponents(string: url) else { return nil }
        components.queryItems = nil
        components.fragment = nil
        guard let base = components.string else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        page.alpha = 0
        page.isUserInteractionEnabled = false
        host?.addSubview(page)
        defer { page.removeFromSuperview() }

        guard let home = await snapshot(page, base + "?tab=lineup&team=home"), home.names.count == 2 else { return nil }
        let away = await snapshot(page, base + "?tab=lineup&team=away")
        return MatchImport.parseFloorball(names: home.names, teams: [home.players, away?.players ?? []], url: base)
    }

    /// Waits for the page's own script to show the lineup. A team without a lineup never gets one, so it gives up.
    private static func snapshot(_ page: WKWebView, _ url: String) async -> Snapshot? {
        guard let link = URL(string: url) else { return nil }
        page.load(URLRequest(url: link))
        var latest: Snapshot?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(300))
            guard let json = try? await page.evaluateJavaScript(script) as? String,
                  let current = try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)) else { continue }
            latest = current
            if !current.players.isEmpty { return current }
        }
        return latest
    }
}
