import Foundation
import Security

/// Stores API keys in the macOS login keychain rather than in plain-text preferences.
///
/// All keys live in a single keychain item, read once per launch. macOS asks "TESS wants to access
/// key …" per item whenever the app's signature is new to it (after each install or update, until TESS
/// is signed with an Apple Developer ID), so one item means at most one prompt.
enum Keychain {
    /// "app.tess.assistant" for TESS, "app.tess.assistant.dev" for TESS Dev (see `AppFlavor`).
    static let service = AppFlavor.current.keychainService
    private static let bundleAccount = "api-keys"
    /// Older versions stored one item per key.
    private static let legacyAccounts = ["anthropic", "openai"]

    private static var cache: [String: String]?

    static func get(_ account: String) -> String {
        load()[account] ?? ""
    }

    static func set(_ value: String, for account: String) {
        var all = load()
        if value.isEmpty { all[account] = nil } else { all[account] = value }
        guard all != cache else { return }
        cache = all
        write(all)
    }

    private static func load() -> [String: String] {
        if let cache { return cache }
        if let data = read(bundleAccount), let keys = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = keys
            return keys
        }
        // First launch after the change: move the separate items into one.
        var keys: [String: String] = [:]
        for account in legacyAccounts {
            if let data = read(account), let value = String(data: data, encoding: .utf8), !value.isEmpty {
                keys[account] = value
            }
        }
        cache = keys
        if !keys.isEmpty {
            write(keys)
            legacyAccounts.forEach(delete)
        }
        return keys
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ keys: [String: String]) {
        delete(bundleAccount)
        guard !keys.isEmpty, let data = try? JSONEncoder().encode(keys) else { return }
        var add = query(bundleAccount)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "TESS API keys"
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
