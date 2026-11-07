import SwiftUI

enum MockData {
    /// Các cặp ngôn ngữ tạo sẵn ở lần chạy đầu (chưa có tin nhắn).
    static func seedConversations(model: String, temperature: Double) -> [Conversation] {
        let sources: [Language] = [.english, .chinese, .japanese, .korean, .french]
        return sources.enumerated().map { index, source in
            var config = AIConfig.makeDefault(source: source, target: .vietnamese)
            config.model = model
            config.temperature = temperature
            return Conversation(
                sourceLang: source,
                targetLang: .vietnamese,
                avatarText: source.avatarText,
                avatarColors: source.avatarColors,
                isPinned: index == 0,
                aiConfig: config
            )
        }
    }

    /// Tạo mốc thời gian tương đối: `days` ngày trước, lúc `hour:minute`.
    private static func at(_ days: Int, _ hour: Int, _ minute: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -days, to: .now) ?? .now
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func pair(_ source: String, _ translated: String, _ date: Date) -> [Message] {
        [
            Message(text: source, isOutgoing: true, date: date),
            Message(text: translated, isOutgoing: false, date: date.addingTimeInterval(4)),
        ]
    }

    static var conversations: [Conversation] {
        [
            Conversation(
                sourceLang: .english, targetLang: .vietnamese,
                avatarText: "EN",
                avatarColors: [Color(hex: 0x72D5FD), Color(hex: 0x2A9EF1)],
                messages:
                    pair("Good morning! How are you today?", "Chào buổi sáng! Hôm nay bạn thế nào?", at(1, 8, 12))
                    + pair("Could you please send me the report before Friday?", "Bạn có thể gửi cho tôi bản báo cáo trước thứ Sáu được không?", at(1, 8, 20))
                    + pair("The meeting has been moved to 3 PM.", "Cuộc họp đã được dời sang 3 giờ chiều.", at(0, 9, 41))
                    + pair("Thank you so much for your help, I really appreciate it.", "Cảm ơn bạn rất nhiều vì đã giúp đỡ, tôi thực sự trân trọng điều đó.", at(0, 10, 5)),
                isPinned: true
            ),
            Conversation(
                sourceLang: .chinese, targetLang: .vietnamese,
                avatarText: "中",
                avatarColors: [Color(hex: 0xFF885E), Color(hex: 0xFF516A)],
                messages:
                    pair("你好，很高兴认识你。", "Xin chào, rất vui được làm quen với bạn.", at(2, 14, 30))
                    + pair("这个产品的价格是多少？", "Giá của sản phẩm này là bao nhiêu?", at(0, 11, 2))
                    + pair("我们明天上午十点见面吧。", "Chúng ta gặp nhau lúc 10 giờ sáng mai nhé.", at(0, 11, 15)),
                unreadCount: 2
            ),
            Conversation(
                sourceLang: .japanese, targetLang: .vietnamese,
                avatarText: "日",
                avatarColors: [Color(hex: 0xE0A2F3), Color(hex: 0xD669ED)],
                messages:
                    pair("ありがとうございます。", "Xin cảm ơn.", at(3, 16, 0))
                    + pair("駅はどこですか？", "Nhà ga ở đâu vậy?", at(3, 16, 2))
                    + pair("少々お待ちください。", "Xin vui lòng đợi một chút.", at(1, 19, 45))
            ),
            Conversation(
                sourceLang: .korean, targetLang: .vietnamese,
                avatarText: "한",
                avatarColors: [Color(hex: 0xA0DE7E), Color(hex: 0x54CB68)],
                messages:
                    pair("안녕하세요, 만나서 반갑습니다.", "Xin chào, rất vui được gặp bạn.", at(5, 10, 10))
                    + pair("이거 얼마예요?", "Cái này bao nhiêu tiền?", at(4, 13, 22)),
                unreadCount: 1
            ),
            Conversation(
                sourceLang: .french, targetLang: .vietnamese,
                avatarText: "FR",
                avatarColors: [Color(hex: 0x53EDD6), Color(hex: 0x28C9B7)],
                messages:
                    pair("Bonjour, je voudrais réserver une table pour deux.", "Xin chào, tôi muốn đặt một bàn cho hai người.", at(8, 18, 30))
                    + pair("L'addition, s'il vous plaît.", "Làm ơn cho tôi hóa đơn.", at(8, 20, 5))
            ),
        ]
    }
}
