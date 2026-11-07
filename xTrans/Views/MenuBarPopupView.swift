import SwiftUI
import AppKit

/// Khung chat nổi ở góc trên bên phải khi bấm icon xTrans trên menu bar.
struct MenuBarPopupView: View {
    /// Kích thước tối đa (tự thu nhỏ nếu màn hình nhỏ hơn).
    static let size = CGSize(width: 820, height: 720)

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
    }
}
