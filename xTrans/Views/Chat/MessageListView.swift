import SwiftUI

struct MessageListView: View {
    let messages: [Message]
    let sourceLanguage: Language
    let targetLanguage: Language
    let isTranslating: Bool
    var onRetry: (Message.ID) -> Void = { _ in }
    @Environment(\.denseLayout) private var dense

    private let bottomID = "bottom"

    var body: some View {
        GeometryReader { geo in
            list
                // Bubble tối đa ~75% chiều rộng khung chat, trong khoảng 240…720pt
                .environment(\.bubbleMaxWidth, min(max((geo.size.width - 32) * 0.75, 240), 720))
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let prev = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil

                        if prev == nil || !Calendar.current.isDate(prev!.date, inSameDayAs: message.date) {
                            ServiceChip(text: message.date.daySeparatorTitle)
                                .padding(.vertical, dense ? 6 : 10)
                        }

                        let isLastInGroup = next == nil
                            || next!.isOutgoing != message.isOutgoing
                            || !Calendar.current.isDate(next!.date, inSameDayAs: message.date)

                        MessageBubbleView(
                            message: message,
                            isLastInGroup: isLastInGroup,
                            onRetry: { onRetry(message.id) }
                        )
                        .padding(.bottom, isLastInGroup ? (dense ? 6 : 10) : (dense ? 2 : 3))
                            .id(message.id)
                    }

                    if isTranslating {
                        HStack(alignment: .bottom, spacing: dense ? 6 : 8) {
                            AIAvatarView()
                            TypingIndicatorView()
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.horizontal, dense ? 10 : 16)
                .padding(.top, dense ? 4 : 8)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: isTranslating) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
        }
    }
}

extension Date {
    var daySeparatorTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Hôm nay" }
        if cal.isDateInYesterday(self) { return "Hôm qua" }
        return formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "vi_VN")))
    }
}

extension EnvironmentValues {
    /// Chiều rộng tối đa của một bubble, tính theo kích thước khung chat.
    @Entry var bubbleMaxWidth: CGFloat = 520
}
