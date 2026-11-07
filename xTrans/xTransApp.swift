//
//  xTransApp.swift
//  xTrans
//
//  Created by VienLv on 7/11/26.
//

import SwiftUI
import AppKit

@main
struct xTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var store: ChatStore

    init() {
        // SwiftData (SQLite) cho tài khoản, hội thoại, tin nhắn — API key nằm riêng trong Keychain.
        let persistence: Persistence?
        do {
            persistence = try Persistence()
        } catch {
            print("[xTrans] Không mở được database, chạy tạm trong bộ nhớ: \(error)")
            persistence = try? Persistence(inMemory: true)
        }
        let settings = SettingsStore(persistence: persistence)
        let store = ChatStore(
            service: OpenAITranslationService(),
            settings: settings,
            persistence: persistence
        )
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        MenuBarController.shared.configure(store: store, settings: settings)
    }

    var body: some Scene {
        // Cửa sổ chính
        WindowGroup(id: MenuBarController.mainWindowID) {
            ContentView()
                .environment(store)
                .environment(settings)
                .background(OpenWindowRegistrar())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        // "Khi mở app: ẩn sẵn trên menu bar" → không tự bật cửa sổ
        // Luôn mở cửa sổ khi khởi động (không phụ thuộc trạng thái lần trước, vd đã đóng cửa sổ rồi thoát)
        .defaultLaunchBehavior(MenuBarController.startsHidden ? .suppressed : .presented)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}

/// Ghi lại hành động mở cửa sổ của SwiftUI để icon menu bar (AppKit) gọi được.
private struct OpenWindowRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            MenuBarController.shared.openMainWindowAction = { openWindow(id: MenuBarController.mainWindowID) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if MenuBarController.startsHidden {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarController.shared.start()
    }

    /// Đóng cửa sổ chính không thoát app — app ẩn vào menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Mở lại app từ Finder / Launchpad / Spotlight khi đang ẩn → hiện cửa sổ chính.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        if MenuBarController.shared.consumePendingReopen() { return true } // SwiftUI tự tạo cửa sổ
        MenuBarController.shared.showMainWindow()
        return false
    }
}
