import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(account: String) -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String)
}

extension SecretStore {
    public func hasKey(for provider: NotesProviderKind) -> Bool {
        !(read(account: provider.keychainAccount) ?? "").isEmpty
    }
}

extension NotesProviderKind {
    public var keychainAccount: String { "api-key.\(rawValue)" }
}

public struct KeychainError: Error, Equatable { public let status: OSStatus }

/// Generic-password items in the login keychain. Keys never touch disk, defaults or logs.
public struct KeychainStore: SecretStore {
    public let service: String
    public init(service: String = "nl.techchamps.hush") { self.service = service }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            let s = SecItemAdd(add as CFDictionary, nil)
            if s != errSecSuccess { throw KeychainError(status: s) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(account: String) { SecItemDelete(query(account) as CFDictionary) }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func read(account: String) -> String? { lock.withLock { values[account] } }
    public func write(_ value: String, account: String) throws { lock.withLock { values[account] = value } }
    public func delete(account: String) { _ = lock.withLock { values.removeValue(forKey: account) } }
}
