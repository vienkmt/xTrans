import SwiftUI

struct MainView: View {
    @Environment(ChatStore.self) private var store
    /// Độ rộng sidebar do người dùng kéo, nhớ qua các lần mở app.
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 300
    @State private var dragStartWidth: Double?
    @Environment(\.denseLayout) private var dense

    static let sidebarRange: ClosedRange<Double> = 240...420
    /// Dưới mức này sidebar tự thu thành cột avatar.
    static let compactBreakpoint: CGFloat = 720

    var body: some View {
        GeometryReader { geo in
            let compact = dense || geo.size.width < Self.compactBreakpoint
            // Luôn chừa tối thiểu ~380pt cho khung chat
            let maxSidebar = min(Self.sidebarRange.upperBound, max(Self.sidebarRange.lowerBound, Double(geo.size.width) - 380))
            let width = compact ? (dense ? 56 : 76) : min(max(sidebarWidth, Self.sidebarRange.lowerBound), maxSidebar)

            HStack(spacing: 0) {
                SidebarView(compact: compact)
                    .frame(width: width)

                Rectangle()
                    .fill(XTheme.divider)
                    .frame(width: 1)
                    .overlay {
                        if !compact {
                            // Tay nắm kéo đổi độ rộng sidebar
                            Color.clear
                                .frame(width: 9)
                                .contentShape(Rectangle())
                                .pointerStyle(.columnResize)
                                .gesture(
                                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                        .onChanged { value in
                                            let start = dragStartWidth ?? width
                                            dragStartWidth = start
                                            sidebarWidth = min(max(start + value.translation.width, Self.sidebarRange.lowerBound), maxSidebar)
                                        }
                                        .onEnded { _ in dragStartWidth = nil }
                                )
                                .onTapGesture(count: 2) { sidebarWidth = 300 }
                                .help("Kéo để đổi độ rộng · bấm đúp để về mặc định")
                        }
                    }
                    .zIndex(1)

            Group {
                if let conv = store.selectedConversation {
                    ChatView(conversation: conv)
                        .id(conv.id)
                } else {
                    EmptyChatView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct EmptyChatView: View {
    var body: some View {
        ZStack {
            XTheme.wallpaper
            VStack(spacing: 10) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(XTheme.accent)
                Text("Chọn một cặp ngôn ngữ để bắt đầu dịch")
                    .font(.system(size: 13))
                    .foregroundStyle(XTheme.textSecondary)
            }
        }
    }
}

/// Dải phân cách ngày: chữ nhỏ ở giữa, hai bên là đường kẻ mảnh.
struct ServiceChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            line
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(XTheme.textSecondary)
            line
        }
        .padding(.horizontal, 24)
    }

    private var line: some View {
        Rectangle().fill(XTheme.border).frame(height: 1)
    }
}

extension EnvironmentValues {
    /// Khoảng chừa phía trên cho nút đỏ/vàng/xanh của cửa sổ (popup menu bar không có → nhỏ hơn).
    @Entry var windowTopInset: CGFloat = 38
    /// Bố cục gọn (khung dịch nhanh trên menu bar): sidebar chỉ icon, khoảng cách nhỏ, ưu tiên chỗ cho nội dung.
    @Entry var denseLayout: Bool = false
}
