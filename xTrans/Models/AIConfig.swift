import Foundation

/// Một tài khoản OpenAI (mỗi tài khoản một API key).
struct AIAccount: Identifiable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var organizationID: String
    var baseURL: String
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        apiKey: String = "",
        organizationID: String = "",
        baseURL: String = AIAccount.defaultBaseURL,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.organizationID = organizationID
        self.baseURL = baseURL
        self.isDefault = isDefault
    }

    static let defaultBaseURL = "https://api.openai.com/v1"

    /// "sk-…a1b2" — không hiển thị toàn bộ key.
    var maskedKey: String {
        guard apiKey.count > 8 else { return apiKey.isEmpty ? "Chưa có API key" : "••••" }
        return "\(apiKey.prefix(3))…\(apiKey.suffix(4))"
    }
}

/// Cấu hình AI riêng cho từng hội thoại.
struct AIConfig: Hashable {
    /// nil = dùng tài khoản mặc định trong Settings.
    var accountID: UUID?
    var model: String
    var temperature: Double
    var systemPrompt: String
    /// Số lượt (câu gốc + bản dịch) gần nhất gửi kèm để AI hiểu đây là cuộc trao đổi liền mạch. 0 = tắt.
    var contextTurns: Int = AIConfig.defaultContextTurns
    /// Ghi chú bối cảnh do người dùng viết, vd "Đang mua tụ điện từ NCC ở Thâm Quyến".
    var contextNote: String = ""

    static let defaultContextTurns = 10

    static let suggestedModels = [
        "gpt-4.1",
        "gpt-4.1-mini",
        "gpt-4.1-nano",
        "gpt-4o",
        "gpt-4o-mini",
        "o4-mini",
    ]

    static let defaultModel = "gpt-4.1-mini"

    /// Prompt song ngữ: tự nhận ngôn ngữ đầu vào và dịch sang ngôn ngữ còn lại của cặp.
    static func defaultPrompt(source: Language, target: Language) -> String {
        let usesChinese = source.code == "zh" || target.code == "zh"
        return """
        Bạn là phiên dịch viên song ngữ \(source.name) ⇄ \(target.name).

        Tự nhận diện ngôn ngữ của nội dung người dùng gửi, rồi chọn hướng dịch:
        - Nếu nội dung chủ yếu là \(source.name) → dịch sang \(target.name).
        - Nếu nội dung chủ yếu là \(target.name) → dịch sang \(source.name).
        - Nếu là ngôn ngữ khác → dịch sang \(target.name).

        Yêu cầu:
        - Chỉ trả về bản dịch. Không giải thích, không ghi chú, không lặp lại bản gốc.
        - Giữ nguyên định dạng, xuống dòng, số liệu, mã sản phẩm, tên riêng, @mention và URL.
        - Văn phong tự nhiên, đúng ngữ cảnh trao đổi công việc.\(usesChinese ? "\n- Tiếng Trung dùng chữ Giản thể." : "")
        """
    }

    /// Prompt mẫu một chiều của các bản trước — dùng để nhận ra và nâng cấp tự động.
    static func legacyDefaultPrompt(source: Language, target: Language) -> String {
        """
        Bạn là phiên dịch viên chuyên nghiệp. Hãy dịch nội dung người dùng gửi từ \(source.name) sang \(target.name).
        - Chỉ trả về bản dịch, không giải thích.
        - Giữ nguyên định dạng, xuống dòng, số liệu và tên riêng.
        - Văn phong tự nhiên, đúng ngữ cảnh.
        """
    }

    static func makeDefault(source: Language, target: Language) -> AIConfig {
        AIConfig(
            accountID: nil,
            model: defaultModel,
            temperature: 0.3,
            systemPrompt: defaultPrompt(source: source, target: target)
        )
    }
}
