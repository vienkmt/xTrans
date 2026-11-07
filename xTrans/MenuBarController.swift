import AppKit
import SwiftUI

/// Điều phối cửa sổ chính, icon Dock và icon menu bar:
/// - Icon menu bar (góc phải) LUÔN hiện từ lúc mở app.
/// - Cửa sổ chính đang mở → có thêm icon Dock.
/// - Đóng cửa sổ chính → app không thoát, chỉ còn icon menu bar (icon Dock biến mất).
/// - Bấm icon menu bar → hiện khung chat nổi ở góc trên bên phải màn hình.
/// - Chuột phải icon → menu (Mở cửa sổ lớn / Ẩn cửa sổ / Thoát).
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    static let mainWindowID = "main"

    static var startsHidden: Bool {
        UserDefaults.standard.bool(forKey: SettingsStore.startInMenuBarKey)
    }

    /// Do SwiftUI cung cấp (`openWindow`) khi cửa sổ chính xuất hiện lần đầu.
    var openMainWindowAction: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var localKeyMonitor: Any?
    private var store: ChatStore?
    private var settings: SettingsStore?

    /// Gọi từ App lúc khởi tạo để khung chat nhỏ dùng chung dữ liệu với cửa sổ chính.
    func configure(store: ChatStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }
    /// Đang chờ SwiftUI tạo cửa sổ qua sự kiện "mở lại app".
    private var pendingReopen = false

    /// Gọi từ `applicationShouldHandleReopen`: true → để SwiftUI tự tạo cửa sổ chính.
    func consumePendingReopen() -> Bool {
        defer { pendingReopen = false }
        return pendingReopen
    }

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
        installStatusItem()
        if Self.startsHidden { hideToMenuBar() }
    }

    // MARK: - Chuyển trạng thái

    func hideToMenuBar() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Đóng cửa sổ chính → `windowWillClose` sẽ chuyển app về chỉ còn icon menu bar.
    func closeMainWindows() {
        mainWindows.forEach { $0.close() }
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        if let window = mainWindows.first {
            window.makeKeyAndOrderFront(nil)
        } else if let open = openMainWindowAction {
            open()
        } else {
            // Khởi động ẩn nên SwiftUI chưa từng tạo cửa sổ → gửi sự kiện "mở lại app" để SwiftUI tự tạo
            pendingReopen = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        }
    }

    // MARK: - Cửa sổ chính

    /// Cửa sổ chính = cửa sổ thường của app (bỏ qua Cài đặt, sheet, panel, cửa sổ hệ thống).
    private func isMainWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel || window.sheetParent != nil { return false }
        guard window.styleMask.contains(.titled), window.canBecomeMain else { return false }
        let id = window.identifier?.rawValue ?? ""
        if id.localizedCaseInsensitiveContains("settings") { return false }
        return true
    }

    private var mainWindows: [NSWindow] {
        NSApp.windows.filter { isMainWindow($0) && $0.isVisible }
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let closing = note.object as? NSWindow, isMainWindow(closing) else { return }
        // Chờ cửa sổ đóng hẳn rồi kiểm tra còn cửa sổ chính nào không
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.mainWindows.filter({ $0 !== closing }).isEmpty {
                self.hideToMenuBar()
            }
        }
    }

    // MARK: - Icon menu bar

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Nhớ vị trí icon: ⌘-kéo icon ra vùng hiển thị (vd khỏi vùng ẩn của Hidden Bar/Bartender) một lần là được
        item.autosaveName = "xTransStatusItem"
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "xTrans — bấm để mở"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusIcon()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            closePopover()
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Khung chat nổi ở góc trên bên phải màn hình

    private func togglePopover() {
        if panel?.isVisible == true {
            closePopover()
        } else {
            showPanel()
        }
    }

    /// Có bản dịch mới từ clipboard: hiện khung dịch nhanh nhưng KHÔNG giành focus khỏi app đang dùng (WeChat).
    func revealForIncoming(conversation: UUID) {
        if NSApp.isActive, mainWindows.contains(where: \.isKeyWindow) { return } // đang xem ở cửa sổ lớn
        if panel?.isVisible == true { return }
        showPanel(activate: false)
    }

    /// Icon menu bar tô màu xanh khi đang tự dịch clipboard.
    func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let watching = settings?.clipboardWatchEnabled == true
        button.contentTintColor = watching ? NSColor(srgbRed: 0x4A/255, green: 0x90/255, blue: 0xD9/255, alpha: 1) : nil
        button.toolTip = watching
            ? "xTrans — đang tự dịch khi copy trong WeChat · bấm để mở"
            : "xTrans — bấm để mở"
    }

    private func showPanel(activate: Bool = true) {
        guard let panel = makePanel() else { return }
        // Neo góc trên bên phải của màn hình đang chứa icon, ngay dưới menu bar
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = CGSize(
            width: min(MenuBarPopupView.size.width, visible.width - 16),
            height: min(MenuBarPopupView.size.height, visible.height - 12)
        )
        let origin = CGPoint(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - 6)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)

        panel.alphaValue = 0
        if activate {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        startDismissMonitors()
    }

    func closePopover() {
        stopDismissMonitors()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel? {
        if let panel { return panel }
        guard let store, let settings else { return nil }
        let panel = PopupPanel(
            contentRect: CGRect(origin: .zero, size: MenuBarPopupView.size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating              // nổi trên các app khác để copy qua lại
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: MenuBarPopupView()
                .environment(store)
                .environment(settings)
        )
        self.panel = panel
        return panel
    }

    /// Khung KHÔNG tự đóng khi bấm sang app khác (để copy qua lại).
    /// Chỉ đóng khi: nhấn Esc trong khung, bấm lại icon menu bar, hoặc nút đóng ở đáy cột icon.
    private func startDismissMonitors() {
        stopDismissMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, // Esc
                  let panel = self.panel, panel.isKeyWindow, panel.attachedSheet == nil else { return event }
            self.closePopover()
            return nil
        }
    }

    private func stopDismissMonitors() {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        localKeyMonitor = nil
    }

    func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Mở cửa sổ lớn", action: #selector(menuOpen), keyEquivalent: "")
        open.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        open.target = self
        menu.addItem(open)
        if !mainWindows.isEmpty {
            let hide = NSMenuItem(title: "Ẩn cửa sổ", action: #selector(menuHide), keyEquivalent: "")
            hide.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            hide.target = self
            menu.addItem(hide)
        }
        let watch = NSMenuItem(title: "Tự dịch khi copy (\(watchAppsLabel))", action: #selector(menuToggleWatch), keyEquivalent: "")
        watch.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        watch.state = settings?.clipboardWatchEnabled == true ? .on : .off
        watch.target = self
        menu.addItem(watch)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Cài đặt…", action: #selector(menuSettings), keyEquivalent: ",")
        prefs.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Thoát xTrans", action: #selector(menuQuit), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil) // hiện menu ngay dưới icon
        statusItem?.menu = nil                // trả lại hành vi bấm trái = khung chat nhỏ
    }

    @objc private func menuOpen() { showMainWindow() }
    @objc private func menuHide() { closeMainWindows() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuToggleWatch() { settings?.clipboardWatchEnabled.toggle() }

    /// "WeChat", "WeChat, Chrome"…
    private var watchAppsLabel: String {
        let names = (settings?.clipboardWatchApps ?? []).map(AppInfo.name(for:))
        return names.isEmpty ? "chưa chọn app" : names.joined(separator: ", ")
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}

/// Panel không viền nhưng vẫn nhận bàn phím (để gõ trong ô soạn).
private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
