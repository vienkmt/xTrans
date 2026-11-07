import Foundation
import Security

/// Lưu API key trong macOS Keychain — không bao giờ ghi ra file, database hay log.
/// Mỗi tài khoản OpenAI là một mục "generic password", khoá theo UUID của tài khoản.
enum KeychainStore {
    private static let service = "com.nan.xTrans.openai-api-key"

    private static func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }

    /// Ghi (hoặc ghi đè) key. Key rỗng = xoá.
    @discardableResult
    static func setAPIKey(_ key: String, for accountID: UUID) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteAPIKey(for: accountID)
            return true
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(for: accountID)

        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "xTrans – OpenAI API key"
        // Chỉ đọc được khi máy đã mở khoá, không đồng bộ iCloud.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func apiKey(for accountID: UUID) -> String? {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(for accountID: UUID) {
        SecItemDelete(baseQuery(for: accountID) as CFDictionary)
    }
}
