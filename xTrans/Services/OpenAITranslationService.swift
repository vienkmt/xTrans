import Foundation

enum OpenAIError: LocalizedError {
    case missingKey(accountName: String)
    case invalidURL(String)
    case http(status: Int, message: String)
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let name):
            "Tài khoản “\(name)” chưa có API key. Mở Cài đặt (⌘,) để thêm."
        case .invalidURL(let url):
            "Base URL không hợp lệ: \(url)"
        case .http(401, let message):
            "API key không hợp lệ hoặc đã bị thu hồi (401). \(message)"
        case .http(404, let message):
            "Không tìm thấy model hoặc endpoint (404). \(message)"
        case .http(429, let message):
            "Vượt giới hạn tốc độ hoặc hết credit (429). \(message)"
        case .http(let status, let message):
            "OpenAI trả lỗi \(status). \(message)"
        case .emptyResponse:
            "OpenAI không trả về nội dung."
        case .network(let message):
            "Lỗi mạng: \(message)"
        }
    }
}

/// Gọi thẳng OpenAI Chat Completions API.
struct OpenAITranslationService: TranslationService {
    var session: URLSession = .shared

    func translate(text: String, config: AIConfig, account: AIAccount, history: [ChatTurn]) async throws -> String {
        guard !account.apiKey.isEmpty else { throw OpenAIError.missingKey(accountName: account.name) }

        // system → các lượt trước (user = câu gốc, assistant = bản dịch) → câu cần dịch
        var messages: [[String: String]] = [["role": "system", "content": Self.systemPrompt(config: config, hasHistory: !history.isEmpty)]]
        for turn in history {
            messages.append(["role": "user", "content": turn.source])
            messages.append(["role": "assistant", "content": turn.translation])
        }
        messages.append(["role": "user", "content": text])

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
        ]
        if Self.supportsTemperature(config.model) {
            body["temperature"] = config.temperature
        }

        var request = try Self.request(account: account, path: "chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let data = try await Self.perform(request, session: session)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw OpenAIError.emptyResponse }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kiểm tra key: gọi GET /models, trả về số model tài khoản dùng được.
    static func testConnection(account: AIAccount, session: URLSession = .shared) async throws -> Int {
        guard !account.apiKey.isEmpty else { throw OpenAIError.missingKey(accountName: account.name) }
        var request = try request(account: account, path: "models")
        request.timeoutInterval = 20
        let data = try await perform(request, session: session)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["data"] as? [Any])?.count ?? 0
    }

    // MARK: - Helpers

    /// Prompt người dùng + bối cảnh + nhắc AI rằng đây là cuộc trao đổi liền mạch.
    static func systemPrompt(config: AIConfig, hasHistory: Bool) -> String {
        var prompt = config.systemPrompt
        let note = config.contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            prompt += "\n\nBối cảnh cuộc trao đổi (người dùng cung cấp):\n\(note)"
        }
        if hasHistory {
            prompt += """
            \n\nĐây là một cuộc trao đổi liên tục giữa hai bên. Các lượt trước (bản gốc và bản dịch) được gửi kèm \
            để bạn hiểu ngữ cảnh và giữ nhất quán xưng hô, thuật ngữ, tên sản phẩm, số liệu. \
            Chỉ dịch tin nhắn cuối cùng; không trả lời, không bình luận nội dung.
            """
        }
        return prompt
    }

    /// Các model suy luận (o1, o3, o4…, gpt-5…) chỉ nhận temperature mặc định.
    static func supportsTemperature(_ model: String) -> Bool {
        let m = model.lowercased()
        return !(m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") || m.hasPrefix("gpt-5"))
    }

    private static func request(account: AIAccount, path: String) throws -> URLRequest {
        let base = account.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmedBase)/\(path)"), url.scheme?.hasPrefix("http") == true else {
            throw OpenAIError.invalidURL(account.baseURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(account.apiKey)", forHTTPHeaderField: "Authorization")
        let org = account.organizationID.trimmingCharacters(in: .whitespaces)
        if !org.isEmpty { request.setValue(org, forHTTPHeaderField: "OpenAI-Organization") }
        return request
    }

    private static func perform(_ request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw OpenAIError.http(status: http.statusCode, message: message)
        }
        return data
    }
}
