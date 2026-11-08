import SwiftUI

struct SidebarView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.windowTopInset) private var topInset
    @Environment(\.denseLayout) private var dense
    /// Cửa sổ hẹp → chỉ hiện cột avatar.
    var compact = false
    /// Hành động xoá đang chờ người dùng xác nhận.
    @State private var pendingDelete: PendingDelete?

    private enum PendingDelete: Identifiable {
        case conversation(Conversation)
        case history(Conversation)

        var id: String {
            switch self {
            case .conversation(let c): "conv-\(c.id)"
            case .history(let c): "hist-\(c.id)"
            }
        }
    }

    var body: some View {
        content
        .background(XTheme.sidebarBackground)
        .sheet(item: Binding(
            get: { store.editor },
            set: { store.editor = $0 }
        )) { mode in
            ConversationSettingsSheet(mode: mode)
        }
        .alert(
            deleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { action in
            Button("Xoá", role: .destructive) {
                switch action {
                case .conversation(let c): store.deleteConversation(c.id)
                case .history(let c): store.clearHistory(c.id)
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { action in
            switch action {
            case .conversation(let c):
                Text("“\(c.title)” cùng \(c.messages.count) tin nhắn sẽ bị xoá vĩnh viễn, không khôi phục được.")
            case .history(let c):
                Text("Toàn bộ \(c.messages.count) tin nhắn trong “\(c.title)” sẽ bị xoá vĩnh viễn. Cấu hình AI được giữ nguyên.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if compact { compactContent } else { fullContent }
    }

    private var fullContent: some View {
        @Bindable var store = store

        return VStack(spacing: 0) {
            // Thương hiệu xTrans
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(XTheme.accent)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "character.bubble.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text("xTrans")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(XTheme.textPrimary)
                Spacer()
                Button {
                    store.editor = .add
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(XTheme.accent)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(XTheme.accentSoft))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Thêm cặp ngôn ngữ")

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(XTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(XTheme.rowHover))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Cài đặt (⌘,)")
            }
            .padding(.horizontal, 14)
            .padding(.top, topInset) // chừa chỗ cho nút đèn giao thông của cửa sổ
            .padding(.bottom, 12)

            // Ô tìm kiếm
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(XTheme.textSecondary)
                TextField("Tìm ngôn ngữ hoặc nội dung", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(XTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(XTheme.searchBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(XTheme.border))
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Text("CẶP NGÔN NGỮ")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(XTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            // Danh sách hội thoại
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.filteredConversations) { conv in
                        ChatRowView(
                            conversation: conv,
                            isSelected: conv.id == store.selectedID,
                            isTranslating: store.isTranslating(conv.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { store.select(conv.id) }
                        .contextMenu { rowMenu(conv) }
                    }
                }
                .padding(.horizontal, 8)
            }

            if store.conversations.isEmpty {
                VStack(spacing: 10) {
                    Text("Chưa có cặp ngôn ngữ nào")
                        .font(.system(size: 13))
                        .foregroundStyle(XTheme.textSecondary)
                    Button {
                        store.editor = .add
                    } label: {
                        Label("Thêm cặp ngôn ngữ", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(XTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else if store.filteredConversations.isEmpty {
                Text("Không tìm thấy kết quả")
                    .font(.system(size: 13))
                    .foregroundStyle(XTheme.textSecondary)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 20)
            }
        }
    }

    /// Chế độ thu gọn: nút thêm, cột avatar, nút cài đặt.
    private var compactContent: some View {
        VStack(spacing: dense ? 6 : 10) {
            Button {
                store.editor = .add
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: dense ? 12 : 14, weight: .semibold))
                    .foregroundStyle(XTheme.accent)
                    .frame(width: dense ? 30 : 34, height: dense ? 30 : 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(XTheme.accentSoft))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Thêm cặp ngôn ngữ")
            .padding(.top, topInset)

            ScrollView {
                LazyVStack(spacing: dense ? 4 : 6) {
                    ForEach(store.sortedConversations) { conv in
                        CompactChatRow(
                            conversation: conv,
                            isSelected: conv.id == store.selectedID,
                            isTranslating: store.isTranslating(conv.id)
                        )
                        .onTapGesture { store.select(conv.id) }
                        .contextMenu { rowMenu(conv) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)

            if dense {
                // Khung dịch nhanh: gom nút điều khiển vào đây, bỏ thanh trên cho rộng chỗ
                VStack(spacing: 2) {
                    compactButton("xmark", help: "Đóng khung (Esc)") {
                        MenuBarController.shared.closePopover()
                    }
                    compactButton("macwindow", help: "Mở cửa sổ lớn") {
                        MenuBarController.shared.closePopover()
                        MenuBarController.shared.showMainWindow()
                    }
                    compactButton("power", help: "Thoát xTrans") {
                        NSApp.terminate(nil)
                    }
                }
                .padding(.bottom, 8)
            } else {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(XTheme.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Cài đặt (⌘,)")
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func compactButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(XTheme.textSecondary)
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(help)
    }

    @ViewBuilder
    private func rowMenu(_ conv: Conversation) -> some View {
            Button {
                store.select(conv.id)
                store.openSettings(for: conv.id)
            } label: {
                Label("Cài đặt hội thoại…", systemImage: "slider.horizontal.3")
            }
            Divider()
            Button { store.togglePin(conv.id) } label: {
                Label(conv.isPinned ? "Bỏ ghim" : "Ghim", systemImage: conv.isPinned ? "pin.slash" : "pin")
            }
            Button { store.markRead(conv.id) } label: {
                Label("Đánh dấu đã đọc", systemImage: "checkmark.circle")
            }
            .disabled(conv.unreadCount == 0)
            Divider()
            Button { pendingDelete = .history(conv) } label: {
                Label("Xoá lịch sử dịch…", systemImage: "arrow.counterclockwise")
            }
                .disabled(conv.messages.isEmpty)
            Button(role: .destructive) { pendingDelete = .conversation(conv) } label: {
                Label("Xoá cặp ngôn ngữ…", systemImage: "trash")
            }
    }

    private var deleteTitle: String {
        switch pendingDelete {
        case .conversation: "Xoá cặp ngôn ngữ này?"
        case .history: "Xoá lịch sử dịch?"
        case nil: ""
        }
    }
}
