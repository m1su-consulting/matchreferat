import Foundation
import OSLog
import Security
import SwiftData

/// The current match, stored as one SwiftData record holding the encoded `MatchState`.
@Model
final class StoredMatch {
    var payload: Data
    var updatedAt: Date

    init(payload: Data, updatedAt: Date = .now) {
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// One record per team, in the order shown on the start page.
@Model
final class StoredTeam {
    @Attribute(.unique) var id: UUID
    var order: Int
    var payload: Data

    init(id: UUID, order: Int, payload: Data) {
        self.id = id
        self.order = order
        self.payload = payload
    }
}

/// A finished match kept on the phone, stored as its encoded `MatchState`.
@Model
final class StoredSavedMatch {
    @Attribute(.unique) var id: UUID
    var savedAt: Date
    var payload: Data

    init(id: UUID, savedAt: Date, payload: Data) {
        self.id = id
        self.savedAt = savedAt
        self.payload = payload
    }
}

enum Persistence {
    static let models: [any PersistentModel.Type] = [StoredMatch.self, StoredTeam.self, StoredSavedMatch.self]

    private static let log = Logger(subsystem: "se.matchreferat.app", category: "persistence")

    /// Opens the database. If the file can't be opened, the app keeps working with an in-memory
    /// store (re-importing the JSON backup on each launch) instead of crashing.
    static func container(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        if !inMemory {
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
            } catch {
                log.error("Database unavailable, using memory: \(String(describing: error), privacy: .public)")
            }
        }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            fatalError("Could not create an in-memory database: \(error)")
        }
    }

    /// Where versions before 1.0.2 kept `match.json` and `teams.json`. The files are left in place as a backup.
    static var legacyDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

/// Generic-password items in the app's Keychain.
enum Keychain {
    static let service = "se.matchreferat.app"

    static func data(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    /// Stores `data`, or removes the item when it is nil.
    @discardableResult
    static func set(_ data: Data?, for key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let data else { return true }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// The network calls the live link makes, so tests can replace them.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}
