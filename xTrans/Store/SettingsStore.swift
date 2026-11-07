import SwiftUI
import Observation
import ServiceManagement

/// Cài đặt ứng dụng.
/// - Thông tin tài khoản: SwiftData (qua `Persistence`)
/// - API key: Keychain (qua `KeychainStore`)
/// - Tuỳ chọn nhỏ: UserDefaults
@MainActor
@Observable
final class SettingsStore {
    private let persistence: Persistence?
    private let defaults = UserDefaults.standard

    var accounts: [AIAccount] {
        didSet { persistence?.saveAccounts(accounts) }
    }

    var defaultModel: String {
        didSet { defaults.set(defaultModel, forKey: Keys.defaultModel) }
    }
    var defaultTemperature: Double {
        didSet { defaults.set(defaultTemperature, forKey: Keys.defaultTemperature) }
    }
    var pasteShortcutSendsImmediately: Bool {
        didSet { defaults.set(pasteShortcutSendsImmediately, forKey: Keys.pasteShortcut) }
    }
    var clickToCopyTranslation: Bool {
        didSet { defaults.set(clickToCopyTranslation, forKey: Keys.clickToCopy) }
    }
    var chatWallpaper: ChatWallpaper {
        didSet { defaults.set(chatWallpaper.rawValue, forKey: Keys.chatWallpaper) }
    }
    /// Khi mở app (vd: cùng máy) chỉ hiện icon trên menu bar, không bật cửa sổ.
    var startInMenuBar: Bool {
        didSet { defaults.set(startInMenuBar, forKey: Self.startInMenuBarKey) }
    }
    static let startInMenuBarKey = "startInMenuBar"

    /// Tự mở xTrans khi đăng nhập macOS (SMAppService).
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    var launchAtLoginError: String?

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private enum Keys {
        static let defaultModel = "defaultModel"
        static let defaultTemperature = "defaultTemperature"
        static let pasteShortcut = "pasteShortcutSendsImmediately"
        static let clickToCopy = "clickToCopyTranslation"
        static let chatWallpaper = "chatWallpaper"
    }

    /// `persistence == nil` → chạy trong bộ nhớ (dùng cho Preview).
    init(persistence: Persistence?, accounts: [AIAccount]? = nil) {
        self.persistence = persistence
        self.accounts = accounts ?? persistence?.loadAccounts() ?? []
        defaultModel = defaults.string(forKey: Keys.defaultModel) ?? AIConfig.defaultModel
        defaultTemperature = defaults.object(forKey: Keys.defaultTemperature) as? Double ?? 0.3
        pasteShortcutSendsImmediately = defaults.object(forKey: Keys.pasteShortcut) as? Bool ?? true
        clickToCopyTranslation = defaults.object(forKey: Keys.clickToCopy) as? Bool ?? true
        chatWallpaper = defaults.string(forKey: Keys.chatWallpaper).flatMap(ChatWallpaper.init(rawValue:)) ?? .white
        startInMenuBar = defaults.bool(forKey: Self.startInMenuBarKey)
    }

    var defaultAccount: AIAccount? {
        accounts.first(where: \.isDefault) ?? accounts.first
    }

    func account(_ id: UUID?) -> AIAccount? {
        guard let id else { return defaultAccount }
        return accounts.first { $0.id == id } ?? defaultAccount
    }

    /// Tên tài khoản sẽ dùng cho một cấu hình (kể cả trường hợp "mặc định").
    func accountLabel(for config: AIConfig) -> String {
        account(config.accountID)?.name ?? "Chưa có tài khoản"
    }

    /// Có ít nhất một tài khoản dùng được (có API key)?
    var hasUsableAccount: Bool {
        accounts.contains { !$0.apiKey.isEmpty }
    }

    @discardableResult
    func addAccount() -> AIAccount {
        let acc = AIAccount(name: "Tài khoản \(accounts.count + 1)", isDefault: accounts.isEmpty)
        accounts.append(acc)
        return acc
    }

    func removeAccount(_ id: UUID) {
        KeychainStore.deleteAPIKey(for: id)
        let wasDefault = accounts.first { $0.id == id }?.isDefault ?? false
        accounts.removeAll { $0.id == id }
        if wasDefault, !accounts.isEmpty { accounts[0].isDefault = true }
    }

    func makeDefault(_ id: UUID) {
        for i in accounts.indices { accounts[i].isDefault = accounts[i].id == id }
    }

    /// Ghi key vào Keychain và giữ bản trong bộ nhớ để gọi API.
    func setAPIKey(_ key: String, for id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if persistence != nil { KeychainStore.setAPIKey(trimmed, for: id) }
        accounts[i].apiKey = trimmed
    }

    static var previewAccounts: [AIAccount] {
        [
            AIAccount(name: "Cá nhân", apiKey: "preview-fake-key-not-real-a1b2", isDefault: true),
            AIAccount(name: "Công ty", apiKey: "preview-fake-key-not-real-c3d4", organizationID: "org-demo"),
        ]
    }
}
