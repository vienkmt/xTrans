import SwiftUI

struct ChatRowView: View {
    let conversation: Conversation
    let isSelected: Bool
    let isTranslating: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(text: conversation.avatarText, colors: conversation.avatarColors, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? XTheme.accent : XTheme.textPrimary)
                        .lineLimit(1)
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(XTheme.textSecondary)
                    }
                    Spacer(minLength: 4)
                    if conversation.lastMessage != nil {
                        Text(conversation.lastActivity.chatListTimestamp)
                            .font(.system(size: 11))
                            .foregroundStyle(XTheme.textSecondary)
                    }
                }

                HStack(spacing: 4) {
                    previewText
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(RoundedRectangle(cornerRadius: 5).fill(XTheme.accent))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? XTheme.rowSelected : (isHovering ? XTheme.rowHover : .clear))
        )
        .overlay(alignment: .leading) {
            // Vạch accent bên trái hàng đang chọn
            if isSelected {
                Capsule().fill(XTheme.accent).frame(width: 3, height: 24).offset(x: -6)
            }
        }
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
    }

    @ViewBuilder
    private var previewText: some View {
        if isTranslating {
            Text("Đang dịch…")
                .foregroundStyle(XTheme.accent)
        } else if let last = conversation.lastMessage {
            (last.isOutgoing
                ? Text("Bạn: ").foregroundStyle(XTheme.textPrimary)
                : Text(""))
            + Text(last.text).foregroundStyle(XTheme.textSecondary)
        } else {
            Text("Chưa có nội dung").foregroundStyle(XTheme.textSecondary)
        }
    }
}

/// Trạng thái câu gốc: chỉ hiện khi đang gửi hoặc lỗi.
struct StatusIcon: View {
    let status: Message.Status
    let tint: Color

    var body: some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 9))
                .foregroundStyle(tint)
        case .sent:
            EmptyView()
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }
}

extension Date {
    /// Hôm nay → "10:05", trong tuần → "T3", cũ hơn → "25/10/26"
    var chatListTimestamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            return formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: self), to: cal.startOfDay(for: .now)).day, days < 7 {
            return formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "vi_VN")))
        }
        return formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
    }

    var bubbleTime: String {
        formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

/// Hàng hội thoại ở chế độ sidebar thu gọn: chỉ avatar + badge.
struct CompactChatRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isTranslating: Bool
    @Environment(\.denseLayout) private var dense

    @State private var isHovering = false

    var body: some View {
        AvatarView(text: conversation.avatarText, colors: conversation.avatarColors, size: dense ? 34 : 42)
            .overlay(alignment: .topTrailing) {
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(XTheme.accent))
                        .overlay(Capsule().stroke(XTheme.sidebarBackground, lineWidth: 2))
                        .offset(x: 5, y: -5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isTranslating {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(2)
                        .background(Circle().fill(XTheme.sidebarBackground))
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: dense ? 46 : 58, height: dense ? 42 : 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? XTheme.rowSelected : (isHovering ? XTheme.rowHover : .clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule().fill(XTheme.accent).frame(width: 3, height: dense ? 20 : 24).offset(x: dense ? -4 : -6)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .pointerStyle(.link)
            .help(conversation.title)
    }
}
