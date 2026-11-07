import SwiftUI

/// Modal duy nhất cho một hội thoại: cặp ngôn ngữ + tên + tài khoản + model + nhiệt độ + system prompt.
/// Dùng cho cả "Thêm" (nút +) và "Sửa" (header, nút ☰, chuột phải).
struct ConversationSettingsSheet: View {
    @Environment(ChatStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let mode: ConversationEditorMode

    @State private var source: Language = .english
    @State private var target: Language = .vietnamese
    @State private var title = ""
    @State private var config = AIConfig.makeDefault(source: .english, target: .vietnamese)
    @State private var useCustomModel = false
    @State private var loaded = false

    private static let customTag = "__custom__"

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        source != target && !config.model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                languageSection
                contextSection
                modelSection
                promptSection
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 560, height: 700)
        .onAppear(perform: load)
        // Prompt vẫn là mặc định của cặp cũ → tự đổi theo cặp mới; đã tự sửa thì giữ nguyên.
        .onChange(of: source) { old, new in followDefaultPrompt(from: (old, target), to: (new, target)) }
        .onChange(of: target) { old, new in followDefaultPrompt(from: (source, old), to: (source, new)) }
    }

    // MARK: - Các phần

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(text: source.avatarText, colors: source.avatarColors, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Cài đặt hội thoại" : "Thêm cặp ngôn ngữ")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(previewTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(source.shortName) ⇄ \(target.shortName) · \(config.model)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(XTheme.accent)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(XTheme.accent)
        }
        .padding(16)
    }

    private var languageSection: some View {
        Section {
            Picker("Ngôn ngữ 1", selection: $source) {
                ForEach(Language.all, id: \.self) { Text(label(for: $0)).tag($0) }
            }
            LabeledContent {
                Button {
                    swap(&source, &target)
                } label: {
                    Label("Đảo chiều", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.link)
                .pointerStyle(.link)
            } label: {
                EmptyView()
            }
            Picker("Ngôn ngữ 2", selection: $target) {
                ForEach(Language.all, id: \.self) { Text(label(for: $0)).tag($0) }
            }
            TextField("Tên hiển thị", text: $title, prompt: Text(Conversation.defaultTitle(source: source, target: target)))
        } header: {
            Text("Cặp ngôn ngữ")
        } footer: {
            if source == target {
                Label("Ngôn ngữ nguồn và đích phải khác nhau", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Dịch hai chiều: gửi ngôn ngữ 1 → ra ngôn ngữ 2 và ngược lại. Ngôn ngữ khác sẽ dịch sang ngôn ngữ 2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contextSection: some View {
        Section {
            Stepper(value: $config.contextTurns, in: 0...30) {
                LabeledContent("Nhớ các lượt gần nhất") {
                    Text(config.contextTurns == 0 ? "Tắt" : "\(config.contextTurns) lượt")
                        .monospacedDigit()
                        .foregroundStyle(config.contextTurns == 0 ? .secondary : .primary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Ghi chú bối cảnh")
                TextField(
                    "Ghi chú bối cảnh",
                    text: $config.contextNote,
                    prompt: Text("VD: Đang đàm phán mua tụ điện với nhà cung cấp ở Thâm Quyến. Xưng hô: tôi – anh Zhu."),
                    axis: .vertical
                )
                .labelsHidden()
                .lineLimit(2...5)
            }
        } header: {
            Text("Ngữ cảnh cuộc trao đổi")
        } footer: {
            Text("Mỗi lần dịch, các lượt gần nhất (câu gốc + bản dịch) được gửi kèm để AI hiểu đây là cuộc trao đổi liền mạch: giữ xưng hô, thuật ngữ, tên hàng, giá. Xoá lịch sử (nút ↺ trên header) để bắt đầu cuộc trao đổi mới.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Tài khoản OpenAI", selection: $config.accountID) {
                Text("Mặc định (\(settings.defaultAccount?.name ?? "chưa có"))").tag(UUID?.none)
                if !settings.accounts.isEmpty { Divider() }
                ForEach(settings.accounts) { acc in
                    Text("\(acc.name)  ·  \(acc.maskedKey)").tag(UUID?.some(acc.id))
                }
            }

            Picker("Model", selection: modelSelection) {
                ForEach(AIConfig.suggestedModels, id: \.self) { Text($0).tag($0) }
                Divider()
                Text("Tuỳ chỉnh…").tag(Self.customTag)
            }
            if useCustomModel {
                TextField("Tên model", text: $config.model, prompt: Text("vd: gpt-4.1-2025-04-14"))
                    .font(.system(.body, design: .monospaced))
            }

            LabeledContent("Nhiệt độ") {
                HStack {
                    Slider(value: $config.temperature, in: 0...2, step: 0.1)
                    Text(config.temperature, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .frame(width: 28)
                }
            }
            .disabled(!OpenAITranslationService.supportsTemperature(config.model))
        } header: {
            HStack {
                Text("Tài khoản & model")
                Spacer()
                OpenAIConsoleButton()
                    .buttonStyle(.link)
                    .font(.caption)
            }
        } footer: {
            if !OpenAITranslationService.supportsTemperature(config.model) {
                Text("Model \(config.model) không hỗ trợ chỉnh nhiệt độ — sẽ dùng mặc định.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var promptSection: some View {
        Section {
            TextEditor(text: $config.systemPrompt)
                .font(.system(size: 13))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
        } header: {
            HStack {
                Text("System prompt")
                Spacer()
                Button {
                    config.systemPrompt = AIConfig.defaultPrompt(source: source, target: target)
                } label: {
                    Label("Khôi phục mặc định", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        } footer: {
            Text("\(config.systemPrompt.count) ký tự · Gửi kèm mọi tin nhắn trong hội thoại này.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if settings.accounts.isEmpty {
                Label("Chưa có tài khoản — thêm trong Cài đặt (⌘,)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isEditing {
                Text("Lịch sử dịch được giữ nguyên.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Huỷ") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Lưu" : "Thêm") { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding(14)
    }

    // MARK: - Logic

    private var previewTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? Conversation.defaultTitle(source: source, target: target) : t
    }

    private func label(for lang: Language) -> String {
        "\(lang.name) (\(lang.shortName))"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .edit(let id):
            guard let conv = store.conversations.first(where: { $0.id == id }) else { return }
            source = conv.sourceLang
            target = conv.targetLang
            title = conv.customTitle ?? ""
            config = conv.aiConfig
        case .add:
            config = AIConfig.makeDefault(source: source, target: target)
            config.model = settings.defaultModel
            config.temperature = settings.defaultTemperature
        }
        useCustomModel = !AIConfig.suggestedModels.contains(config.model)
    }

    private func followDefaultPrompt(from old: (Language, Language), to new: (Language, Language)) {
        guard loaded, config.systemPrompt == AIConfig.defaultPrompt(source: old.0, target: old.1) else { return }
        config.systemPrompt = AIConfig.defaultPrompt(source: new.0, target: new.1)
    }

    private func submit() {
        guard isValid else { return }
        switch mode {
        case .add:
            store.addConversation(source: source, target: target, title: title, config: config)
        case .edit(let id):
            store.saveConversation(id, source: source, target: target, title: title, config: config)
        }
        dismiss()
    }

    /// Picker model: chọn trong danh sách gợi ý hoặc "Tuỳ chỉnh…".
    private var modelSelection: Binding<String> {
        Binding(
            get: { useCustomModel ? Self.customTag : config.model },
            set: { newValue in
                if newValue == Self.customTag {
                    useCustomModel = true
                } else {
                    useCustomModel = false
                    config.model = newValue
                }
            }
        )
    }
}
