import SwiftUI
import Observation

@MainActor
@Observable
final class ChatStore {
    var conversations: [Conversation]
    var selectedID: Conversation.ID?
    var searchText: String = ""
    /// Số yêu cầu dịch đang chờ của từng hội thoại (hiện "đang dịch…").
    var pendingCounts: [Conversation.ID: Int] = [:]
    /// Nội dung đang soạn của từng hội thoại.
    var drafts: [Conversation.ID: String] = [:]
    /// Hội thoại vừa có bản dịch được tự chép vào clipboard (hiện thông báo vài giây).
    var autoCopyNotice: Conversation.ID?
    private var autoCopyNoticeTask: Task<Void, Never>?
    /// Modal cài đặt hội thoại đang mở (thêm mới hoặc sửa).
    var editor: ConversationEditorMode?

    private let service: TranslationService
    private let settings: SettingsStore
    private let persistence: Persistence?

    /// `persistence == nil` → chạy trong bộ nhớ với dữ liệu mẫu (Preview).
    init(
        service: TranslationService,
        settings: SettingsStore,
        persistence: Persistence?,
        conversations: [Conversation]? = nil
    ) {
        self.service = service
        self.settings = settings
        self.persistence = persistence
        if let conversations {
            self.conversations = conversations
        } else if let persistence {
            self.conversations = persistence.loadConversations {
                MockData.seedConversations(model: settings.defaultModel, temperature: settings.defaultTemperature)
            }
        } else {
            self.conversations = MockData.conversations
        }
        upgradeLegacyPrompts()
        self.selectedID = sortedConversations.first?.id
        if let id = selectedID { markRead(id) }
    }

    /// Hội thoại còn dùng prompt mẫu một chiều cũ (chưa tự sửa) → đổi sang prompt song ngữ.
    private func upgradeLegacyPrompts() {
        for i in conversations.indices {
            let c = conversations[i]
            guard c.aiConfig.systemPrompt == AIConfig.legacyDefaultPrompt(source: c.sourceLang, target: c.targetLang) else { continue }
            conversations[i].aiConfig.systemPrompt = AIConfig.defaultPrompt(source: c.sourceLang, target: c.targetLang)
            persistence?.saveConversationMeta(conversations[i])
        }
    }

    // MARK: - Truy vấn

    /// Ghim lên đầu, còn lại theo tin mới nhất.
    var sortedConversations: [Conversation] {
        conversations.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.lastActivity > b.lastActivity
        }
    }

    var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sortedConversations }
        return sortedConversations.filter { conv in
            conv.title.localizedCaseInsensitiveContains(query)
                || conv.sourceLang.name.localizedCaseInsensitiveContains(query)
                || conv.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedID }
    }

    func isTranslating(_ id: Conversation.ID) -> Bool { pendingCounts[id, default: 0] > 0 }

    // MARK: - Hành động

    func select(_ id: Conversation.ID) {
        selectedID = id
        markRead(id)
    }

    func markRead(_ id: Conversation.ID) {
        guard let i = index(of: id) else { return }
        conversations[i].unreadCount = 0
    }

    func togglePin(_ id: Conversation.ID) {
        guard let i = index(of: id) else { return }
        conversations[i].isPinned.toggle()
        persistence?.saveConversationMeta(conversations[i])
    }

    // MARK: Thêm / sửa / xoá hội thoại

    @discardableResult
    func addConversation(source: Language, target: Language, title: String?, config: AIConfig) -> Conversation.ID {
        let conv = Conversation(
            sourceLang: source,
            targetLang: target,
            avatarText: source.avatarText,
            avatarColors: source.avatarColors,
            aiConfig: config,
            customTitle: Self.normalizedTitle(title)
        )
        conversations.append(conv)
        persistence?.insertConversation(conv)
        select(conv.id)
        return conv.id
    }

    func saveConversation(_ id: Conversation.ID, source: Language, target: Language, title: String?, config: AIConfig) {
        guard let i = index(of: id) else { return }
        conversations[i].sourceLang = source
        conversations[i].targetLang = target
        conversations[i].avatarText = source.avatarText
        conversations[i].avatarColors = source.avatarColors
        conversations[i].customTitle = Self.normalizedTitle(title)
        conversations[i].aiConfig = config
        persistence?.saveConversationMeta(conversations[i])
    }

    func deleteConversation(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        drafts[id] = nil
        persistence?.deleteConversation(id)
        if selectedID == id {
            selectedID = sortedConversations.first?.id
        }
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    func clearHistory(_ id: Conversation.ID) {
        guard let i = index(of: id) else { return }
        conversations[i].messages.removeAll()
        persistence?.clearMessages(of: id)
    }

    /// Mở modal cài đặt (cặp ngôn ngữ + AI) của một hội thoại.
    func openSettings(for id: Conversation.ID) {
        editor = .edit(id)
    }

    func draft(for id: Conversation.ID) -> Binding<String> {
        Binding(
            get: { self.drafts[id, default: ""] },
            set: { self.drafts[id] = $0 }
        )
    }

    /// Gửi nội dung đang soạn.
    func send(in id: Conversation.ID) {
        let text = drafts[id, default: ""]
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        drafts[id] = ""
        send(text: text, in: id)
    }

    /// Nguồn của một lần dịch.
    enum SendOrigin {
        /// Gửi từ trong xTrans: Enter, "Dán & dịch", ⌘V → luôn tự chép bản dịch
        case app
        /// Copy trong app được theo dõi (WeChat) → chỉ tự chép khi là câu trả lời
        case clipboardWatch
    }

    /// Gửi thẳng một đoạn văn bản (vd: dán từ clipboard), không qua ô soạn.
    func send(text rawText: String, in id: Conversation.ID, origin: SendOrigin = .app) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let i = index(of: id) else { return }

        let outgoing = Message(text: text, isOutgoing: true, status: .sending)
        conversations[i].messages.append(outgoing)
        persistence?.appendMessage(outgoing, to: id)
        translate(messageID: outgoing.id, text: text, in: id, origin: origin)
    }

    /// Chữ vừa copy trong app được theo dõi (vd WeChat): chọn hội thoại có ngôn ngữ khớp rồi gửi dịch.
    /// Ưu tiên hội thoại đang mở. Ngôn ngữ ngoài các cặp (vd tiếng Đức) → dịch trong hội thoại đang mở,
    /// sang ngôn ngữ đích của hội thoại đó. Trả về id hội thoại, hoặc nil nếu chưa có hội thoại nào.
    func receiveClipboardText(_ text: String) -> Conversation.ID? {
        let candidates = Array(Set(conversations.flatMap { [$0.sourceLang, $0.targetLang] }))

        let conv: Conversation?
        if let lang = Language.detect(text, among: candidates) {
            conv = conversation(for: lang)
        } else {
            conv = selectedConversation ?? sortedConversations.first
        }
        guard let conv else { return nil }
        select(conv.id)
        send(text: text, in: conv.id, origin: .clipboardWatch)
        return conv.id
    }

    /// Hội thoại hợp với ngôn ngữ: hội thoại đang mở nếu có ngôn ngữ đó, không thì hội thoại đầu tiên có nó.
    private func conversation(for lang: Language) -> Conversation? {
        if let current = selectedConversation, current.sourceLang == lang || current.targetLang == lang {
            return current
        }
        return sortedConversations.first { $0.sourceLang == lang }
            ?? sortedConversations.first { $0.targetLang == lang }
    }

    /// Gửi lại một câu gốc bị lỗi.
    func retry(messageID: Message.ID, in convID: Conversation.ID) {
        guard let i = index(of: convID),
              let m = conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let text = conversations[i].messages[m].text
        updateMessage(messageID, in: convID) {
            $0.status = .sending
            $0.errorText = nil
        }
        translate(messageID: messageID, text: text, in: convID, origin: .app)
    }

    // MARK: - Private

    private func translate(messageID: Message.ID, text: String, in convID: Conversation.ID, origin: SendOrigin) {
        guard let i = index(of: convID) else { return }
        let config = conversations[i].aiConfig

        guard let account = settings.account(config.accountID) else {
            fail(messageID, in: convID, reason: "Chưa có tài khoản OpenAI. Mở Cài đặt (⌘,) để thêm API key.")
            return
        }

        let history = contextHistory(in: conversations[i], before: messageID)
        // Tự chép bản dịch:
        // - gửi từ trong xTrans → luôn chép (không cần bấm vào bản dịch nữa)
        // - copy từ WeChat → chỉ chép khi là câu trả lời (viết bằng ngôn ngữ của bạn), tin đến chỉ cần đọc
        let isReply = Language.detect(text, among: [conversations[i].sourceLang, conversations[i].targetLang])
            == conversations[i].targetLang
        let shouldCopy = origin == .app || isReply

        pendingCounts[convID, default: 0] += 1
        Task {
            do {
                let result = try await service.translate(text: text, config: config, account: account, history: history)
                updateMessage(messageID, in: convID) { $0.status = .sent }
                appendIncoming(result, model: config.model, replyTo: messageID, to: convID)
                if shouldCopy && settings.autoCopyReplies {
                    Clipboard.write(result) // sang WeChat chỉ cần ⌘V
                    showAutoCopyNotice(for: convID)
                }
            } catch {
                fail(messageID, in: convID, reason: error.localizedDescription)
            }
            pendingCounts[convID, default: 1] -= 1
        }
    }

    /// Các lượt gần nhất trước `messageID` (tối đa `contextTurns` lượt, ~12.000 ký tự) để gửi làm ngữ cảnh.
    /// "Xoá lịch sử dịch" = bắt đầu cuộc trao đổi mới, vì chỉ lấy tin còn trong hội thoại.
    private func contextHistory(in conv: Conversation, before messageID: Message.ID) -> [ChatTurn] {
        let limit = conv.aiConfig.contextTurns
        guard limit > 0 else { return [] }
        let end = conv.messages.firstIndex { $0.id == messageID } ?? conv.messages.endIndex
        let prior = Array(conv.messages[..<end])
        let outgoingByID = Dictionary(uniqueKeysWithValues: prior.filter(\.isOutgoing).map { ($0.id, $0) })

        var turns: [ChatTurn] = []
        for (k, m) in prior.enumerated() where !m.isOutgoing {
            // Ghép bản dịch với câu gốc của nó; tin cũ chưa có replyTo → lấy câu gốc ngay trước
            let source = m.replyTo.flatMap { outgoingByID[$0] }
                ?? (k > 0 && prior[k - 1].isOutgoing ? prior[k - 1] : nil)
            if let source { turns.append(ChatTurn(source: source.text, translation: m.text)) }
        }

        var picked: [ChatTurn] = []
        var budget = 12_000
        for turn in turns.suffix(limit).reversed() {
            budget -= turn.source.count + turn.translation.count
            if budget < 0 { break }
            picked.insert(turn, at: 0)
        }
        return picked
    }

    private func showAutoCopyNotice(for convID: Conversation.ID) {
        autoCopyNotice = convID
        autoCopyNoticeTask?.cancel()
        autoCopyNoticeTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            autoCopyNotice = nil
        }
    }

    private func fail(_ messageID: Message.ID, in convID: Conversation.ID, reason: String) {
        updateMessage(messageID, in: convID) {
            $0.status = .failed
            $0.errorText = reason
        }
    }

    private func index(of id: Conversation.ID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    private func updateMessage(_ messageID: Message.ID, in convID: Conversation.ID, _ change: (inout Message) -> Void) {
        guard let i = index(of: convID),
              let m = conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&conversations[i].messages[m])
        persistence?.updateMessage(conversations[i].messages[m])
    }

    private func appendIncoming(_ text: String, model: String, replyTo: Message.ID, to convID: Conversation.ID) {
        guard let i = index(of: convID) else { return }
        let message = Message(text: text, isOutgoing: false, model: model, replyTo: replyTo)
        conversations[i].messages.append(message)
        persistence?.appendMessage(message, to: convID)
        if selectedID != convID { conversations[i].unreadCount += 1 }
    }
}

/// Modal thêm mới hoặc sửa một cặp ngôn ngữ.
enum ConversationEditorMode: Identifiable {
    case add
    case edit(Conversation.ID)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let id): id.uuidString
        }
    }
}
