import SwiftUI
import NaturalLanguage

struct Language: Hashable {
    let code: String   // "en", "zh", "vi"...
    let name: String   // "English"
    let shortName: String // "EN"
}

extension Language {
    static let english = Language(code: "en", name: "English", shortName: "EN")
    static let vietnamese = Language(code: "vi", name: "Vietnamese", shortName: "VI")
    static let chinese = Language(code: "zh", name: "Chinese", shortName: "ZH")
    static let japanese = Language(code: "ja", name: "Japanese", shortName: "JA")
    static let korean = Language(code: "ko", name: "Korean", shortName: "KO")
    static let french = Language(code: "fr", name: "French", shortName: "FR")
    static let german = Language(code: "de", name: "German", shortName: "DE")
    static let spanish = Language(code: "es", name: "Spanish", shortName: "ES")
    static let russian = Language(code: "ru", name: "Russian", shortName: "RU")
    static let thai = Language(code: "th", name: "Thai", shortName: "TH")
    static let indonesian = Language(code: "id", name: "Indonesian", shortName: "ID")
    static let portuguese = Language(code: "pt", name: "Portuguese", shortName: "PT")
    static let italian = Language(code: "it", name: "Italian", shortName: "IT")
    static let lao = Language(code: "lo", name: "Lao", shortName: "LO")

    static let all: [Language] = [
        .english, .vietnamese, .chinese, .japanese, .korean, .french, .german,
        .spanish, .russian, .thai, .indonesian, .portuguese, .italian, .lao,
    ]

    static func from(code: String) -> Language {
        all.first { $0.code == code } ?? Language(code: code, name: code.uppercased(), shortName: code.uppercased())
    }

    /// Chữ và màu avatar của hội thoại có ngôn ngữ nguồn này.
    var avatarText: String {
        switch code {
        case "zh": "中"
        case "ja": "日"
        case "ko": "한"
        case "th": "ไท"
        case "ru": "Ру"
        default: shortName
        }
    }

    var avatarColors: [Color] {
        switch code {
        case "en": [Color(hex: 0x72D5FD), Color(hex: 0x2A9EF1)]
        case "zh": [Color(hex: 0xFF885E), Color(hex: 0xFF516A)]
        case "ja": [Color(hex: 0xE0A2F3), Color(hex: 0xD669ED)]
        case "ko": [Color(hex: 0xA0DE7E), Color(hex: 0x54CB68)]
        case "fr": [Color(hex: 0x53EDD6), Color(hex: 0x28C9B7)]
        case "vi": [Color(hex: 0xFF8A8A), Color(hex: 0xE5484D)]
        case "de", "ru": [Color(hex: 0x9AA9BC), Color(hex: 0x5F7085)]
        case "es", "pt", "it": [Color(hex: 0xFFB36B), Color(hex: 0xF07C3A)]
        case "th", "lo", "id": [Color(hex: 0x7FC8F8), Color(hex: 0x3C8DD8)]
        default: [Color(hex: 0xFFCD6A), Color(hex: 0xFFA85C)]
        }
    }
}

struct Conversation: Identifiable, Hashable {
    let id: UUID
    var sourceLang: Language
    var targetLang: Language
    var avatarText: String
    var avatarColors: [Color]
    var messages: [Message]
    var unreadCount: Int
    var isPinned: Bool
    var aiConfig: AIConfig
    /// Tên do người dùng đặt; nil → dùng tên mặc định "ENGLISH - VIETNAMESE".
    var customTitle: String?

    init(
        id: UUID = UUID(),
        sourceLang: Language,
        targetLang: Language,
        avatarText: String,
        avatarColors: [Color],
        messages: [Message] = [],
        unreadCount: Int = 0,
        isPinned: Bool = false,
        aiConfig: AIConfig? = nil,
        customTitle: String? = nil
    ) {
        self.id = id
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.avatarText = avatarText
        self.avatarColors = avatarColors
        self.messages = messages
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.aiConfig = aiConfig ?? .makeDefault(source: sourceLang, target: targetLang)
        self.customTitle = customTitle
    }

    static func defaultTitle(source: Language, target: Language) -> String {
        "\(source.name.uppercased()) - \(target.name.uppercased())"
    }

    var title: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespaces).isEmpty { return customTitle }
        return Self.defaultTitle(source: sourceLang, target: targetLang)
    }
    var directionLabel: String { "\(sourceLang.shortName) ⇄ \(targetLang.shortName)" }
    var lastMessage: Message? { messages.last }
    var lastActivity: Date { messages.last?.date ?? .distantPast }
}

extension Language {
    private var nlLanguages: [NLLanguage] {
        switch code {
        case "zh": [.simplifiedChinese, .traditionalChinese]
        default: [NLLanguage(rawValue: code)]
        }
    }

    /// Đoán đoạn văn thuộc ngôn ngữ nào trong `candidates` (vd: cặp nguồn/đích).
    static func detect(_ text: String, among candidates: [Language]) -> Language? {
        // 1) Ngôn ngữ có bảng chữ riêng: chỉ cần thấy chữ đó là đủ (kể cả câu lẫn Latin, mã hàng…)
        if let byScript = detectByScript(text, among: candidates) { return byScript }
        // 2) Ngôn ngữ dùng chữ Latin: nhờ NaturalLanguage phân biệt
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.flatMap(\.nlLanguages)
        recognizer.processString(text)
        guard let found = recognizer.dominantLanguage else { return nil }
        return candidates.first { $0.nlLanguages.contains(found) }
    }

    private static func detectByScript(_ text: String, among candidates: [Language]) -> Language? {
        var counts: [String: Int] = [:]
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF: counts["ja", default: 0] += 1                 // Hiragana / Katakana
            case 0xAC00...0xD7AF, 0x1100...0x11FF: counts["ko", default: 0] += 1  // Hangul
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: counts["han", default: 0] += 1 // Chữ Hán
            case 0x0E00...0x0E7F: counts["th", default: 0] += 1                 // Thái
            case 0x0E80...0x0EFF: counts["lo", default: 0] += 1                 // Lào
            case 0x0400...0x04FF: counts["ru", default: 0] += 1                 // Kirin
            default: break
            }
        }
        let codes = Set(candidates.map(\.code))
        func pick(_ code: String) -> Language? { candidates.first { $0.code == code } }

        if counts["ja", default: 0] > 0, codes.contains("ja") { return pick("ja") }
        if counts["ko", default: 0] > 0, codes.contains("ko") { return pick("ko") }
        if counts["han", default: 0] > 0 {
            if codes.contains("zh") { return pick("zh") }
            if codes.contains("ja") { return pick("ja") }
        }
        for code in ["th", "lo", "ru"] where counts[code, default: 0] > 0 && codes.contains(code) {
            return pick(code)
        }
        return nil
    }
}
