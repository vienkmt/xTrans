import Foundation

/// Một lượt trước đó trong cuộc trao đổi: câu gốc và bản dịch của nó.
struct ChatTurn: Hashable {
    let source: String
    let translation: String
}

/// Dịch vụ dịch thuật.
protocol TranslationService {
    /// `history`: các lượt gần nhất (cũ → mới) để AI hiểu ngữ cảnh cuộc trao đổi.
    func translate(text: String, config: AIConfig, account: AIAccount, history: [ChatTurn]) async throws -> String
}

/// Dịch giả lập — chỉ dùng cho Preview.
struct MockTranslationService: TranslationService {
    var delay: Duration = .milliseconds(1200)

    func translate(text: String, config: AIConfig, account: AIAccount, history: [ChatTurn]) async throws -> String {
        try await Task.sleep(for: delay)
        return "(bản dịch mẫu · \(config.model)) \(text)"
    }
}
