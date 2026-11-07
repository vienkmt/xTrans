import SwiftUI

/// Cửa sổ Cài đặt (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettingsView()
                .tabItem { Label("Tài khoản OpenAI", systemImage: "key.fill") }
            GeneralSettingsView()
                .tabItem { Label("Chung", systemImage: "gearshape") }
        }
        .frame(width: 680, height: 440)
    }
}

// MARK: - Tài khoản

struct AccountsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selectedID: AIAccount.ID?

    var body: some View {
        HStack(spacing: 0) {
            // Danh sách tài khoản
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(settings.accounts) { acc in
                        AccountRow(account: acc).tag(acc.id)
                    }
                }
                .listStyle(.inset)

                Divider()
                HStack(spacing: 0) {
                    Button {
                        selectedID = settings.addAccount().id
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 22)
                    }
                    .help("Thêm tài khoản")
                    Divider().frame(height: 16)
                    Button {
                        guard let id = selectedID else { return }
                        settings.removeAccount(id)
                        selectedID = settings.accounts.first?.id
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 22)
                    }
                    .disabled(selectedID == nil)
                    .help("Xoá tài khoản")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 230)

            Divider()

            if let id = selectedID, settings.accounts.contains(where: { $0.id == id }) {
                AccountDetailView(accountID: id)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "Chưa chọn tài khoản",
                    systemImage: "key",
                    description: Text("Thêm hoặc chọn một tài khoản OpenAI để nhập API key.")
                )
            }
        }
        .onAppear { selectedID = selectedID ?? settings.defaultAccount?.id }
    }
}

private struct AccountRow: View {
    let account: AIAccount

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(XTheme.accent.gradient)
                .frame(width: 26, height: 26)
                .overlay(
                    Text(account.name.prefix(1).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name).font(.system(size: 13, weight: .medium))
                Text(account.maskedKey)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if account.isDefault {
                Text("Mặc định")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(XTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(XTheme.accentSoft))
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AccountDetailView: View {
    @Environment(SettingsStore.self) private var settings
    let accountID: AIAccount.ID

    @State private var revealKey = false
    @State private var testStatus: TestStatus?

    private enum TestStatus: Equatable {
        case running
        case ok(String)
        case failed(String)
    }

    private var index: Int? { settings.accounts.firstIndex { $0.id == accountID } }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { settings.accounts.first { $0.id == accountID }?.apiKey ?? "" },
            set: { settings.setAPIKey($0, for: accountID); testStatus = nil }
        )
    }

    var body: some View {
        @Bindable var settings = settings

        if let i = index {
            Form {
                Section("Thông tin") {
                    TextField("Tên hiển thị", text: $settings.accounts[i].name)
                    Toggle("Dùng làm tài khoản mặc định", isOn: Binding(
                        get: { settings.accounts[i].isDefault },
                        set: { if $0 { settings.makeDefault(accountID) } }
                    ))
                    .disabled(settings.accounts[i].isDefault)
                }

                Section {
                    LabeledContent("API key") {
                        Group {
                            if revealKey {
                                TextField("API key", text: apiKeyBinding, prompt: Text("sk-..."))
                            } else {
                                SecureField("API key", text: apiKeyBinding, prompt: Text("sk-..."))
                            }
                        }
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealKey ? "Ẩn key" : "Hiện key")
                    }
                    TextField("Organization ID", text: $settings.accounts[i].organizationID, prompt: Text("Không bắt buộc"))
                    TextField("Base URL", text: $settings.accounts[i].baseURL)
                } header: {
                    Text("Kết nối OpenAI")
                } footer: {
                    HStack {
                        Label("Key được lưu trong Keychain của macOS, không ghi ra file.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        OpenAIConsoleButton()
                    }
                }

                Section {
                    HStack {
                        Button {
                            let account = settings.accounts[i]
                            testStatus = .running
                            Task {
                                do {
                                    let count = try await OpenAITranslationService.testConnection(account: account)
                                    testStatus = .ok("Kết nối thành công · \(count) model khả dụng")
                                } catch {
                                    testStatus = .failed(error.localizedDescription)
                                }
                            }
                        } label: {
                            Label("Kiểm tra kết nối", systemImage: "network")
                        }
                        .disabled(testStatus == .running)
                        switch testStatus {
                        case .none:
                            EmptyView()
                        case .running:
                            ProgressView().controlSize(.small)
                        case .ok(let text):
                            Label(text, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .failed(let text):
                            Label(text, systemImage: "xmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Chung

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Mặc định cho hội thoại mới") {
                Picker("Model", selection: $settings.defaultModel) {
                    ForEach(AIConfig.suggestedModels, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Nhiệt độ") {
                    HStack {
                        Slider(value: $settings.defaultTemperature, in: 0...2, step: 0.1)
                        Text(settings.defaultTemperature, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                }
            }
            Section {
                Toggle("Mở xTrans khi đăng nhập máy", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                Toggle("Khi mở app: ẩn sẵn trên menu bar", isOn: $settings.startInMenuBar)
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Hiển thị & khởi động")
            } footer: {
                Text("Icon xTrans luôn có ở góc phải menu bar — bấm để mở khung chat nhỏ, chuột phải để mở cửa sổ lớn hoặc thoát. Đóng cửa sổ lớn thì app không thoát mà chỉ còn icon đó.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Khung chat") {
                Picker("Hình nền", selection: $settings.chatWallpaper) {
                    ForEach(ChatWallpaper.allCases) { Text($0.title).tag($0) }
                }
                Toggle("⌘V khi ô soạn trống: dán & dịch ngay", isOn: $settings.pasteShortcutSendsImmediately)
                Toggle("Bấm vào bản dịch để sao chép", isOn: $settings.clickToCopyTranslation)
            }
        }
        .formStyle(.grouped)
    }
}

/// Nút mở trang quản lý API key của OpenAI trong trình duyệt.
struct OpenAIConsoleButton: View {
    @Environment(\.openURL) private var openURL
    var title = "Mở OpenAI Console"

    static let apiKeysURL = URL(string: "https://platform.openai.com/api-keys")!

    var body: some View {
        Button {
            openURL(Self.apiKeysURL)
        } label: {
            Label(title, systemImage: "arrow.up.right.square")
        }
        .pointerStyle(.link)
        .help(Self.apiKeysURL.absoluteString)
    }
}
