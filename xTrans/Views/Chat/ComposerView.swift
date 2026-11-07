import SwiftUI
import AppKit

/// Ô soạn chỉ nhận văn bản thuần — không đính kèm, không emoji.
struct ComposerView: View {
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void
    /// Gửi ngay một đoạn văn bản lấy từ clipboard.
    let onPasteSend: (String) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.denseLayout) private var dense
    @FocusState private var focused: Bool
    @State private var pasteMonitor = PasteShortcutMonitor()
    @State private var notice: String?

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.vertical, 6)
                    .onKeyPress(.return, phases: .down) { press in
                        // Shift/Option+Enter → xuống dòng, Enter → dịch
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            text += "\n"
                            return .handled
                        }
                        send()
                        return .handled
                    }

                // Dán nội dung clipboard và gửi luôn
                Button(action: pasteAndSend) {
                    // Hẹp thì chỉ còn biểu tượng
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Dán & dịch")
                                .font(.system(size: 12, weight: .semibold))
                                .fixedSize()
                        }
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(XTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(XTheme.accentSoft)
                    )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Dán nội dung trong clipboard và dịch ngay (⌘V)")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(canSend ? XTheme.accent : XTheme.textSecondary.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(!canSend)
                .help("Dịch (Enter)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(XTheme.chatBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(focused ? XTheme.accent.opacity(0.6) : XTheme.border, lineWidth: 1)
                    )
            )

            if !dense || notice != nil {
            HStack {
                if let notice {
                    Text(notice).foregroundStyle(.orange)
                } else {
                    // Hẹp dần thì rút gọn gợi ý
                    ViewThatFits(in: .horizontal) {
                        Text("Enter để dịch · Shift + Enter xuống dòng · ⌘V khi ô trống: dán & dịch ngay")
                        Text("Enter dịch · ⇧Enter xuống dòng · ⌘V dán & dịch")
                        Text("Enter dịch · ⇧Enter xuống dòng")
                    }
                    .lineLimit(1)
                }
                Spacer()
                Text("\(text.count) ký tự")
            }
            .font(.system(size: 10))
            .foregroundStyle(XTheme.textSecondary)
            .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, dense ? 10 : 16)
        .padding(.top, dense ? 8 : 10)
        .padding(.bottom, 8)
        .background(XTheme.composerBackground)
        .onAppear {
            focused = true
            pasteMonitor.isComposerFocused = true
            pasteMonitor.start { [text = $text, settings] in
                guard settings.pasteShortcutSendsImmediately else { return false }
                // Ô soạn đang có chữ → để hệ thống dán bình thường (chèn vào chỗ con trỏ).
                guard text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                pasteAndSend()
                return true
            }
        }
        .onDisappear { pasteMonitor.stop() }
        .onChange(of: focused) { _, isFocused in
            pasteMonitor.isComposerFocused = isFocused
        }
    }

    private func send() {
        guard canSend else { return }
        onSend()
    }

    private func pasteAndSend() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        guard !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNotice("Clipboard đang trống hoặc không phải văn bản")
            return
        }
        onPasteSend(clip)
        focused = true
    }

    private func showNotice(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notice == message { notice = nil }
        }
    }
}

/// Bắt ⌘V / Ctrl+V khi ô soạn đang focus, trước khi menu Edit > Paste xử lý.
final class PasteShortcutMonitor {
    var isComposerFocused = false
    private var monitor: Any?

    /// `handler` trả về true nếu đã xử lý (nuốt phím), false để dán bình thường.
    func start(handler: @escaping () -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isComposerFocused else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isPasteKey = event.charactersIgnoringModifiers?.lowercased() == "v"
                && (mods == .command || mods == .control)
            guard isPasteKey else { return event }
            return handler() ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}
