import Foundation

struct Message: Identifiable, Hashable {
    enum Status: String, Hashable {
        case sending
        case sent
        case failed
    }

    let id: UUID
    var text: String
    /// true = câu gốc của người dùng (bubble bên phải), false = bản dịch trả về (bên trái)
    var isOutgoing: Bool
    var date: Date
    var status: Status
    /// Lý do lỗi khi gửi thất bại (hiện dưới bubble, kèm nút "Thử lại").
    var errorText: String?
    /// Model AI đã tạo ra bản dịch này (hiện làm "tên người gửi").
    var model: String?
    /// Bản dịch này dịch cho câu gốc nào (để ghép cặp làm ngữ cảnh).
    var replyTo: UUID?

    init(
        id: UUID = UUID(),
        text: String,
        isOutgoing: Bool,
        date: Date = .now,
        status: Status = .sent,
        errorText: String? = nil,
        model: String? = nil,
        replyTo: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.isOutgoing = isOutgoing
        self.date = date
        self.status = status
        self.errorText = errorText
        self.model = model
        self.replyTo = replyTo
    }
}
