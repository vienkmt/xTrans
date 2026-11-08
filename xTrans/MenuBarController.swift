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
    /// Do SwiftUI cung cấp (`openSettings`) — gọi `showSettingsWindow:` trực tiếp bị SwiftUI chặn.
    var openSettingsAction: (() -> Void)?

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification, object: nil
        )
        installStatusItem()
        if Self.startsHidden {
            hideToMenuBar()
            // Không mở cửa sổ lớn → bật sẵn khung dịch nhanh để dùng được ngay.
            // Chờ một vòng run loop để icon menu bar có vị trí trên màn hình trước khi neo khung.
            DispatchQueue.main.async { [weak self] in self?.showPanel() }
        }
    }

    // MARK: - Chuyển trạng thái

    func hideToMenuBar() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Đóng cửa sổ chính → `windowWillClose` sẽ chuyển app về chỉ còn icon menu bar.
    func closeMainWindows() {
        mainWindows.forEach { $0.close() }
    }

    /// Chỉ một trong hai được hiện: mở cửa sổ lớn thì đóng khung dịch nhanh.
    func showMainWindow() {
        closePopover()
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

    /// Cửa sổ lớn hiện ra bằng bất kỳ cách nào (⌘N, Dock, Finder…) → đóng khung dịch nhanh.
    @objc private func windowDidBecomeMain(_ note: Notification) {
        guard let window = note.object as? NSWindow, isMainWindow(window) else { return }
        closePopover()
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

    /// Bấm icon: luôn ra khung dịch nhanh. Cửa sổ lớn đang mở thì đóng lại (chỉ một trong hai được hiện).
    private func togglePopover() {
        if !mainWindows.isEmpty {
            closeMainWindows()
            hideToMenuBar() // chuyển ngay, không chờ `windowWillClose` để khung mới mở không bị mất focus
            showPanel()
        } else if panel?.isVisible == true {
            closePopover()
        } else {
            showPanel()
        }
    }

    /// Có bản dịch mới từ clipboard: hiện khung dịch nhanh nhưng KHÔNG giành focus khỏi app đang dùng (WeChat).
    func revealForIncoming(conversation: UUID) {
        if !mainWindows.isEmpty { return } // cửa sổ lớn đang mở (kể cả nằm sau WeChat) → bản dịch hiện ở đó
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
        let preferred = PopupResizeGrip.savedSize ?? MenuBarPopupView.size
        let size = CGSize(
            width: min(max(preferred.width, PopupResizeGrip.minSize.width), visible.width - 16),
            height: min(max(preferred.height, PopupResizeGrip.minSize.height), visible.height - 12)
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
        // Panel không có .resizable → không co giãn được từ các cạnh khác;
        // chỉ có tay nắm ở cạnh trái, cạnh dưới và góc trái-dưới (cạnh phải + cạnh trên luôn ghim).
        let container = NSView(frame: CGRect(origin: .zero, size: MenuBarPopupView.size))
        let hosting = NSHostingView(
            rootView: MenuBarPopupView()
                .environment(store)
                .environment(settings)
        )
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        PopupResizeGrip.install(in: container)

        panel.contentView = container
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
        if let openSettingsAction {
            openSettingsAction()
        } else if let appMenu = NSApp.mainMenu?.items.first?.submenu,
                  let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            // Khởi động ẩn nên chưa có cửa sổ SwiftUI nào → bấm hộ mục "Cài đặt…" (⌘,) trong menu app
            appMenu.performActionForItem(at: index)
        }
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

/// Tay nắm vô hình ở cạnh trái, cạnh dưới và góc trái-dưới của khung dịch nhanh.
/// Kéo để đổi kích thước: cạnh phải và cạnh trên giữ nguyên (ghim dưới icon menu bar),
/// chỉ cạnh trái và cạnh dưới di chuyển. Kích thước được nhớ cho lần mở sau.
final class PopupResizeGrip: NSView {
    enum Edge {
        case left        // chỉ đổi chiều rộng
        case bottom      // chỉ đổi chiều cao
        case bottomLeft  // đổi cả hai
    }

    static let side: CGFloat = 14
    /// Độ dày vùng kéo dọc cạnh trái / cạnh dưới.
    static let edgeThickness: CGFloat = 5
    static let minSize = CGSize(width: 460, height: 380)
    private static let sizeKey = "popupPanelSize"

    static var savedSize: CGSize? {
        guard let raw = UserDefaults.standard.string(forKey: sizeKey) else { return nil }
        let size = NSSizeFromString(raw)
        return size.width > 0 && size.height > 0 ? size : nil
    }

    let edge: Edge
    private var startFrame: CGRect = .zero
    private var startMouse: CGPoint = .zero

    init(edge: Edge, frame: CGRect) {
        self.edge = edge
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Tạo đủ 3 tay nắm (cạnh trái, cạnh dưới, góc trái-dưới) bám theo kích thước của `container`.
    static func install(in container: NSView) {
        let b = container.bounds
        let left = PopupResizeGrip(edge: .left, frame: CGRect(x: 0, y: side, width: edgeThickness, height: b.height - side))
        left.autoresizingMask = [.height, .maxXMargin]
        let bottom = PopupResizeGrip(edge: .bottom, frame: CGRect(x: side, y: 0, width: b.width - side, height: edgeThickness))
        bottom.autoresizingMask = [.width, .maxYMargin]
        let corner = PopupResizeGrip(edge: .bottomLeft, frame: CGRect(x: 0, y: 0, width: side, height: side))
        corner.autoresizingMask = [.maxXMargin, .maxYMargin]
        [left, bottom, corner].forEach(container.addSubview)
    }

    private var cursor: NSCursor {
        switch edge {
        case .left: .frameResize(position: .left, directions: .all)
        case .bottom: .frameResize(position: .bottom, directions: .all)
        case .bottomLeft: .frameResize(position: .bottomLeft, directions: .all)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
        cursor.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        // Cạnh trái chỉ đổi chiều rộng, cạnh dưới chỉ đổi chiều cao
        let dx = edge == .bottom ? 0 : mouse.x - startMouse.x
        let dy = edge == .left ? 0 : mouse.y - startMouse.y

        // Không vượt ra ngoài vùng hiển thị của màn hình (bên trái và bên dưới)
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        let maxWidth = max(Self.minSize.width, startFrame.maxX - visible.minX)
        let maxHeight = max(Self.minSize.height, startFrame.maxY - visible.minY)

        let width = min(max(startFrame.width - dx, Self.minSize.width), maxWidth)
        let height = min(max(startFrame.height - dy, Self.minSize.height), maxHeight)

        // Ghim cạnh phải (maxX) và cạnh trên (maxY)
        let frame = CGRect(x: startFrame.maxX - width, y: startFrame.maxY - height, width: width, height: height)
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Self.sizeKey)
        window.invalidateCursorRects(for: self)
    }
}
