import SwiftUI
import AppKit
import Combine

struct MessageBubbleView: View {
    let message: Message
    /// Tin cuối của một nhóm liên tiếp → góc phía người gửi bo nhỏ lại.
    let isLastInGroup: Bool
    var onRetry: () -> Void = {}

    @Environment(SettingsStore.self) private var settings
    @Environment(\.bubbleMaxWidth) private var bubbleMaxWidth
    @Environment(\.denseLayout) private var dense
    @State private var isHovering = false
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    private var tapToCopy: Bool { !message.isOutgoing && settings.clickToCopyTranslation }

    /// Tin cũ chưa lưu model → hiện "AI".
    private var senderName: String { message.model ?? "AI" }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            bubbleRow
            if message.isOutgoing, message.status == .failed {
                errorRow
            }
        }
    }

    /// Lý do lỗi + nút thử lại dưới câu gốc gửi thất bại.
    private var errorRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message.errorText ?? "Gửi thất bại.")
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            Button(action: onRetry) {
                Label("Thử lại", systemImage: "arrow.clockwise")
            }
                .buttonStyle(.link)
                .pointerStyle(.link)
        }
        .font(.system(size: 11))
        .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
    }

    private var bubbleRow: some View {
        HStack(alignment: .bottom, spacing: dense ? 6 : 8) {
            if message.isOutgoing { Spacer(minLength: 32) }

            if !message.isOutgoing {
                // Avatar chỉ ở tin cuối của nhóm; các tin trước chừa chỗ để thẳng hàng
                if isLastInGroup {
                    AIAvatarView(model: message.model)
                        .help("Dịch bởi \(senderName)")
                } else {
                    Color.clear.frame(width: dense ? AIAvatarView.denseSize : AIAvatarView.size, height: 1)
                }
            }

            // VStack căn phải: giờ nằm góc dưới phải mà bubble không bị giãn hết chiều ngang.
            VStack(alignment: .trailing, spacing: 3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.system(size: dense ? 13 : 14))
                        .foregroundStyle(message.isOutgoing ? XTheme.bubbleOutText : XTheme.textPrimary)
                        .modifier(SelectableText(enabled: message.isOutgoing))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Không hiện giờ — chỉ báo trạng thái khi cần
                if copied {
                    Label("Đã sao chép", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(XTheme.accent)
                } else if message.isOutgoing && message.status == .sending {
                    StatusIcon(status: .sending, tint: XTheme.bubbleOutMeta)
                }
            }
            .padding(.horizontal, dense ? 10 : 12)
            .padding(.vertical, dense ? 5 : 8)
            .background(
                BubbleShape(isOutgoing: message.isOutgoing, showsTail: isLastInGroup)
                    .fill(message.isOutgoing ? XTheme.bubbleOut : XTheme.incomingFill(on: settings.chatWallpaper, hovering: isHovering))
            )
            .overlay(
                Group {
                    if !message.isOutgoing {
                        BubbleShape(isOutgoing: false, showsTail: isLastInGroup)
                            .stroke(copied || isHovering ? XTheme.accent.opacity(copied ? 0.9 : 0.4) : XTheme.border,
                                    lineWidth: copied ? 1.5 : 1)
                    }
                }
            )
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.15), value: copied)
            // Nút sao chép nổi bên phải bản dịch khi rê chuột
            .overlay(alignment: .bottomTrailing) {
                if !message.isOutgoing && (isHovering || copied) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? XTheme.accent : XTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(XTheme.bubbleIn))
                        .overlay(Circle().stroke(XTheme.border))
                        .offset(x: 32)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(BubbleShape(isOutgoing: message.isOutgoing, showsTail: isLastInGroup))
            .onTapGesture {
                // Bấm vào bản dịch (nội dung AI trả về) → sao chép ngay
                if tapToCopy { copy() }
            }
            .contextMenu {
                Button(action: copy) {
                    Label("Sao chép", systemImage: "doc.on.doc")
                }
            }
            .onHover { hovering in
                guard tapToCopy else { return }
                isHovering = hovering
            }
            // Con trỏ dạng bàn tay (pointer) khi rê vào bản dịch
            .pointerStyle(tapToCopy ? .link : nil)
            .help(tapToCopy ? "Bấm để sao chép bản dịch" : "")
            .frame(maxWidth: bubbleMaxWidth, alignment: message.isOutgoing ? .trailing : .leading)

            if !message.isOutgoing { Spacer(minLength: 32) }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// Bubble bo góc 16pt; tin cuối nhóm có góc dưới phía người gửi bo nhỏ (4pt).
struct BubbleShape: Shape {
    let isOutgoing: Bool
    let showsTail: Bool
    var radius: CGFloat = 16
    var smallRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let small = showsTail ? smallRadius : radius
        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: isOutgoing ? radius : small,
            bottomTrailingRadius: isOutgoing ? small : radius,
            topTrailingRadius: radius,
            style: .continuous
        ).path(in: rect)
    }
}

struct TypingIndicatorView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.denseLayout) private var dense
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(XTheme.accent)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(.horizontal, dense ? 11 : 14)
        .padding(.vertical, dense ? 8 : 12)
        .background(
            BubbleShape(isOutgoing: false, showsTail: true)
                .fill(XTheme.incomingFill(on: settings.chatWallpaper, hovering: false))
        )
        .overlay(
            BubbleShape(isOutgoing: false, showsTail: true)
                .stroke(XTheme.border, lineWidth: 1)
        )
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

/// Câu gốc cho chọn chữ; bản dịch thì không (để một cú click là sao chép).
private struct SelectableText: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

/// Avatar tròn của AI — đặt cạnh bản dịch như avatar người gửi trong Telegram.
/// Model của OpenAI / Claude / Gemini / Grok → logo hãng; model khác → avatar ✨ mặc định.
struct AIAvatarView: View {
    static let size: CGFloat = 32
    static let denseSize: CGFloat = 24
    var model: String?
    @Environment(\.denseLayout) private var dense

    var body: some View {
        let size = dense ? Self.denseSize : Self.size
        let provider = AIProvider(model: model)
        return Circle()
            .fill(LinearGradient(colors: background(provider), startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                if let provider {
                    Image(provider.logoAsset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: size * logoScale(provider), height: size * logoScale(provider))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }

    /// Màu nền theo nhận diện thương hiệu của từng hãng.
    private func background(_ provider: AIProvider?) -> [Color] {
        switch provider {
        case .openAI: [Color(hex: 0x2B2B2B), Color(hex: 0x000000)]
        case .claude: [Color(hex: 0xE08A6A), Color(hex: 0xC96442)]
        case .gemini: [Color(hex: 0x4F8DF7), Color(hex: 0x9B72CB), Color(hex: 0xD96570)]
        case .grok: [Color(hex: 0x3A3A3A), Color(hex: 0x111111)]
        case nil: [Color(hex: 0x7DB8F0), XTheme.accent]
        }
    }

    /// Logo chiếm bao nhiêu phần đường kính (mỗi logo có độ "đặc" khác nhau).
    private func logoScale(_ provider: AIProvider) -> CGFloat {
        switch provider {
        case .openAI, .claude: 0.58
        case .gemini: 0.54
        case .grok: 0.56
        }
    }
}

#Preview("Avatar AI") {
    HStack(spacing: 12) {
        ForEach(["gpt-4.1-mini", "claude-sonnet-4-5", "gemini-2.5-pro", "grok-4", "deepseek-chat"], id: \.self) { model in
            VStack(spacing: 6) {
                AIAvatarView(model: model)
                AIAvatarView(model: model).environment(\.denseLayout, true)
                Text(model).font(.caption2)
            }
        }
    }
    .padding()
}
