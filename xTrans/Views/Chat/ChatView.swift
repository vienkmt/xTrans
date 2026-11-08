import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                conversation: conversation,
                isTranslating: store.isTranslating(conversation.id)
            )
            Rectangle().fill(XTheme.divider).frame(height: 1)

            if !settings.hasUsableAccount {
                MissingKeyBanner()
            }

            MessageListView(
                messages: conversation.messages,
                sourceLanguage: conversation.sourceLang,
                targetLanguage: conversation.targetLang,
                isTranslating: store.isTranslating(conversation.id),
                model: conversation.aiConfig.model,
                onRetry: { store.retry(messageID: $0, in: conversation.id) }
            )
            .background(XTheme.wallpaper)
            .overlay {
                if conversation.messages.isEmpty && !store.isTranslating(conversation.id) {
                    VStack(spacing: 8) {
                        Image(systemName: "character.bubble")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(XTheme.accent)
                        Text("Dán \(conversation.sourceLang.name) hoặc \(conversation.targetLang.name) — tự dịch sang ngôn ngữ còn lại")
                            .font(.system(size: 13))
                            .foregroundStyle(XTheme.textSecondary)
                        Text("\(conversation.aiConfig.model) · \(settings.accountLabel(for: conversation.aiConfig))")
                            .font(.system(size: 11))
                            .foregroundStyle(XTheme.textSecondary.opacity(0.8))
                    }
                    .allowsHitTesting(false)
                }
            }

            Rectangle().fill(XTheme.divider).frame(height: 1)
            ComposerView(
                text: store.draft(for: conversation.id),
                placeholder: "Nhập \(conversation.sourceLang.name) hoặc \(conversation.targetLang.name)…",
                onSend: { store.send(in: conversation.id) },
                onPasteSend: { store.send(text: $0, in: conversation.id) }
            )
        }
        // Toast nổi ở khoảng 1/3 chiều cao tính từ đáy: chỉ mờ dần vào/ra, không đẩy bố cục nên không gây giật
        .overlay {
            GeometryReader { proxy in
                ZStack {
                    if store.autoCopyNotice == conversation.id {
                        CopiedToast()
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height * 2 / 3)
            }
            .animation(.easeInOut(duration: 0.25), value: store.autoCopyNotice)
            .allowsHitTesting(false)
        }
    }
}

private struct CopiedToast: View {
    var body: some View {
        Label("Đã chép bản dịch · ⌘V để dán", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(XTheme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

struct ChatHeaderView: View {
    @Environment(ChatStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    let conversation: Conversation
    let isTranslating: Bool
    @Environment(\.denseLayout) private var dense
    @State private var confirmNewSession = false

    /// "gpt-4.1 · ChatGPT1 · nhớ 10 lượt"
    private var headerSubtitle: String {
        var parts = [conversation.aiConfig.model, settings.accountLabel(for: conversation.aiConfig)]
        let turns = conversation.aiConfig.contextTurns
        parts.append(turns > 0 ? "nhớ \(turns) lượt" : "không nhớ ngữ cảnh")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: dense ? 8 : 10) {
            Button {
                store.openSettings(for: conversation.id)
            } label: {
                HStack(spacing: dense ? 8 : 10) {
                    AvatarView(text: conversation.avatarText, colors: conversation.avatarColors, size: dense ? 26 : 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(conversation.title)
                            .font(.system(size: dense ? 13 : 14, weight: .semibold))
                            .foregroundStyle(XTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 4) {
                            if isTranslating {
                                ProgressView().controlSize(.mini)
                                Text("Đang dịch…")
                                    .foregroundStyle(XTheme.accent)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                    .foregroundStyle(XTheme.accent)
                                Text(headerSubtitle)
                                    .foregroundStyle(XTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .font(.system(size: 11))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Cài đặt hội thoại: cặp ngôn ngữ, model, system prompt")

            Spacer(minLength: 8)

            // Huy hiệu hướng dịch
            HStack(spacing: 6) {
                Text(conversation.sourceLang.shortName)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9, weight: .bold))
                Text(conversation.targetLang.shortName)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(XTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(XTheme.accentSoft))
            .fixedSize()

            // Bắt đầu cuộc trao đổi mới = xoá lịch sử (AI không còn nhớ các lượt cũ)
            Button {
                confirmNewSession = true
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(XTheme.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .disabled(conversation.messages.isEmpty)
            .help("Bắt đầu cuộc trao đổi mới (xoá lịch sử dịch)")
            .confirmationDialog(
                "Bắt đầu cuộc trao đổi mới?",
                isPresented: $confirmNewSession
            ) {
                Button("Xoá \(conversation.messages.count) tin và bắt đầu lại", role: .destructive) {
                    store.clearHistory(conversation.id)
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Lịch sử dịch của “\(conversation.title)” sẽ bị xoá vĩnh viễn. AI sẽ không còn nhớ các lượt trao đổi trước. Cấu hình và ghi chú bối cảnh được giữ nguyên.")
            }

            Button {
                store.openSettings(for: conversation.id)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(XTheme.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Cài đặt hội thoại")
        }
        .padding(.horizontal, dense ? 10 : 16)
        .padding(.top, dense ? 0 : 6)
        .frame(height: dense ? 42 : 56)
        .background(XTheme.headerBackground)
    }
}

/// Thanh nhắc khi chưa có tài khoản/API key nào.
struct MissingKeyBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            Text("Chưa có API key OpenAI — thêm key để bắt đầu dịch.")
                .foregroundStyle(XTheme.textPrimary)
            Spacer()
            SettingsLink {
                Text("Mở Cài đặt")
                    .fontWeight(.semibold)
                    .foregroundStyle(XTheme.accent)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}
