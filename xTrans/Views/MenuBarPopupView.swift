import SwiftUI
import AppKit

/// Khung chat nổi ở góc trên bên phải khi bấm icon xTrans trên menu bar.
struct MenuBarPopupView: View {
    /// Kích thước mặc định (tự thu nhỏ nếu màn hình nhỏ hơn). Người dùng kéo góc trái-dưới để đổi, kích thước được nhớ lại.
    static let size = CGSize(width: 656, height: 576) // ~80% của 820×720 trước đây

    var body: some View {
        // Bố cục gọn: sidebar chỉ icon (nút mở cửa sổ lớn / cài đặt / thoát nằm ở đáy cột icon)
        MainView()
            .environment(\.windowTopInset, 8)
            .environment(\.denseLayout, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(XTheme.border, lineWidth: 1)
        )
        // Khởi động ẩn thì chưa có cửa sổ chính → lấy `openWindow` từ đây để nút "Mở cửa sổ lớn" dùng được
        .background(OpenWindowRegistrar())
    }
}
