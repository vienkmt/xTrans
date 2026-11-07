import Foundation
import SwiftData

// MARK: - Bản ghi SwiftData (SQLite trong thư mục sandbox của app)
// Lưu ý: KHÔNG có trường nào chứa API key — key chỉ nằm trong Keychain.

@Model
final class AccountRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var organizationID: String
    var baseURL: String
    var isDefault: Bool
    var createdAt: Date

    init(id: UUID, name: String, organizationID: String, baseURL: String, isDefault: Bool, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.organizationID = organizationID
        self.baseURL = baseURL
        self.isDefault = isDefault
        self.createdAt = createdAt
    }
}

@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var sourceCode: String
    var targetCode: String
    var isPinned: Bool
    var accountID: UUID?
    var model: String
    var temperature: Double
    var systemPrompt: String
    var contextTurns: Int?
    var contextNote: String?
    var customTitle: String?
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messages: [MessageRecord] = []

    init(from conv: Conversation) {
        id = conv.id
        sourceCode = conv.sourceLang.code
        targetCode = conv.targetLang.code
        isPinned = conv.isPinned
        accountID = conv.aiConfig.accountID
        model = conv.aiConfig.model
        temperature = conv.aiConfig.temperature
        systemPrompt = conv.aiConfig.systemPrompt
        contextTurns = conv.aiConfig.contextTurns
        contextNote = conv.aiConfig.contextNote
        customTitle = conv.customTitle
        createdAt = .now
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var isOutgoing: Bool
    var date: Date
    var statusRaw: String
    var errorText: String?
    var model: String?
    var replyTo: UUID?
    var conversation: ConversationRecord?

    init(from m: Message) {
        id = m.id
        text = m.text
        isOutgoing = m.isOutgoing
        date = m.date
        statusRaw = m.status.rawValue
        errorText = m.errorText
        model = m.model
        replyTo = m.replyTo
    }
}

// MARK: - Lớp truy cập dữ liệu

@MainActor
final class Persistence {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let config = ModelConfiguration("xTrans", isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(
            for: AccountRecord.self, ConversationRecord.self, MessageRecord.self,
            configurations: config
        )
    }

    private func save() {
        do { try context.save() } catch { print("[Persistence] Lưu thất bại: \(error)") }
    }

    // MARK: Tài khoản

    func loadAccounts() -> [AIAccount] {
        let descriptor = FetchDescriptor<AccountRecord>(sortBy: [SortDescriptor(\.createdAt)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map {
            AIAccount(
                id: $0.id,
                name: $0.name,
                apiKey: KeychainStore.apiKey(for: $0.id) ?? "",
                organizationID: $0.organizationID,
                baseURL: $0.baseURL,
                isDefault: $0.isDefault
            )
        }
    }

    /// Đồng bộ thông tin tài khoản (không gồm key) vào database.
    func saveAccounts(_ accounts: [AIAccount]) {
        let existing = (try? context.fetch(FetchDescriptor<AccountRecord>())) ?? []
        let ids = Set(accounts.map(\.id))
        for record in existing where !ids.contains(record.id) {
            context.delete(record)
        }
        for acc in accounts {
            if let r = existing.first(where: { $0.id == acc.id }) {
                r.name = acc.name
                r.organizationID = acc.organizationID
                r.baseURL = acc.baseURL
                r.isDefault = acc.isDefault
            } else {
                context.insert(AccountRecord(
                    id: acc.id, name: acc.name, organizationID: acc.organizationID,
                    baseURL: acc.baseURL, isDefault: acc.isDefault
                ))
            }
        }
        save()
    }

    // MARK: Hội thoại & tin nhắn

    /// Lần chạy đầu: tạo sẵn các cặp ngôn ngữ (chưa có tin nhắn).
    func loadConversations(seed: () -> [Conversation]) -> [Conversation] {
        let descriptor = FetchDescriptor<ConversationRecord>(sortBy: [SortDescriptor(\.createdAt)])
        var records = (try? context.fetch(descriptor)) ?? []
        // Chỉ tạo sẵn ở lần chạy đầu — người dùng xoá hết thì không tạo lại.
        let seededKey = "didSeedConversations"
        if records.isEmpty && !UserDefaults.standard.bool(forKey: seededKey) {
            for conv in seed() { context.insert(ConversationRecord(from: conv)) }
            save()
            records = (try? context.fetch(descriptor)) ?? []
        }
        UserDefaults.standard.set(true, forKey: seededKey)
        return records.map { r in
            let source = Language.from(code: r.sourceCode)
            let target = Language.from(code: r.targetCode)
            let messages = r.messages
                .sorted { $0.date < $1.date }
                .map {
                    Message(
                        id: $0.id, text: $0.text, isOutgoing: $0.isOutgoing, date: $0.date,
                        // Tin đang gửi dở khi thoát app → coi như lỗi để người dùng thử lại.
                        status: Message.Status(rawValue: $0.statusRaw).map { $0 == .sending ? .failed : $0 } ?? .sent,
                        errorText: $0.statusRaw == Message.Status.sending.rawValue ? "Bị gián đoạn khi đóng app." : $0.errorText,
                        model: $0.model,
                        replyTo: $0.replyTo
                    )
                }
            return Conversation(
                id: r.id,
                sourceLang: source,
                targetLang: target,
                avatarText: source.avatarText,
                avatarColors: source.avatarColors,
                messages: messages,
                isPinned: r.isPinned,
                aiConfig: AIConfig(
                    accountID: r.accountID, model: r.model,
                    temperature: r.temperature, systemPrompt: r.systemPrompt,
                    contextTurns: r.contextTurns ?? AIConfig.defaultContextTurns,
                    contextNote: r.contextNote ?? ""
                ),
                customTitle: r.customTitle
            )
        }
    }

    private func conversationRecord(_ id: UUID) -> ConversationRecord? {
        var d = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func messageRecord(_ id: UUID) -> MessageRecord? {
        var d = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func insertConversation(_ conv: Conversation) {
        context.insert(ConversationRecord(from: conv))
        save()
    }

    /// Xoá hội thoại cùng toàn bộ tin nhắn (cascade).
    func deleteConversation(_ id: UUID) {
        guard let r = conversationRecord(id) else { return }
        context.delete(r)
        save()
    }

    func saveConversationMeta(_ conv: Conversation) {
        guard let r = conversationRecord(conv.id) else { return }
        r.sourceCode = conv.sourceLang.code
        r.targetCode = conv.targetLang.code
        r.customTitle = conv.customTitle
        r.isPinned = conv.isPinned
        r.accountID = conv.aiConfig.accountID
        r.model = conv.aiConfig.model
        r.temperature = conv.aiConfig.temperature
        r.systemPrompt = conv.aiConfig.systemPrompt
        r.contextTurns = conv.aiConfig.contextTurns
        r.contextNote = conv.aiConfig.contextNote
        save()
    }

    func appendMessage(_ m: Message, to convID: UUID) {
        guard let conv = conversationRecord(convID) else { return }
        let r = MessageRecord(from: m)
        context.insert(r)
        r.conversation = conv
        save()
    }

    func updateMessage(_ m: Message) {
        guard let r = messageRecord(m.id) else { return }
        r.text = m.text
        r.statusRaw = m.status.rawValue
        r.errorText = m.errorText
        save()
    }

    func clearMessages(of convID: UUID) {
        guard let conv = conversationRecord(convID) else { return }
        for m in conv.messages { context.delete(m) }
        save()
    }
}
