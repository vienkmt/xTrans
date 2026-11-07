import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Màu tự đổi theo chế độ sáng/tối của hệ thống.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Bảng màu riêng của xTrans (tông xanh dương #4A90D9, nền xám xanh nhạt có chấm).
enum XTheme {
    static let accent = Color.dynamic(light: 0x4A90D9, dark: 0x5EA2E8)
    static let accentSoft = Color.dynamic(light: 0xE7F1FB, dark: 0x1E3046)

    // Sidebar
    static let sidebarBackground = Color.dynamic(light: 0xF6F8FB, dark: 0x151A21)
    static let rowHover = Color.dynamic(light: 0xEDF1F6, dark: 0x1D242D)
    static let rowSelected = accentSoft
    static let searchBackground = Color.dynamic(light: 0xFFFFFF, dark: 0x1D242D)
    static let border = Color.dynamic(light: 0xDFE5EC, dark: 0x27303B)
    static let divider = border

    // Text
    static let textPrimary = Color.dynamic(light: 0x1A1B23, dark: 0xECEDF2)
    static let textSecondary = Color.dynamic(light: 0x8A8C99, dark: 0x8A8C9E)

    // Chat
    static let headerBackground = Color.dynamic(light: 0xFFFFFF, dark: 0x151A21)
    static let composerBackground = Color.dynamic(light: 0xFFFFFF, dark: 0x151A21)
    static let chatBackground = Color.dynamic(light: 0xEFF3F8, dark: 0x0E1318)
    static let chatDots = Color.dynamic(light: 0xC5D2E0, dark: 0x232C37)
    /// Câu gốc của người dùng: nền accent, chữ trắng.
    static let bubbleOut = accent
    static let bubbleOutText = Color.white
    static let bubbleOutMeta = Color.white.opacity(0.75)
    /// Bản dịch: thẻ trắng có viền.
    static let bubbleIn = Color.dynamic(light: 0xFFFFFF, dark: 0x1B222B)
    static let bubbleInHover = Color.dynamic(light: 0xF4F8FD, dark: 0x212C38)
    /// Bản dịch trên nền trắng: xám rất nhạt để tách khỏi nền.
    static let bubbleInOnWhite = Color.dynamic(light: 0xF0F2F5, dark: 0x1B222B)
    static let bubbleInOnWhiteHover = Color.dynamic(light: 0xE7EBF0, dark: 0x212C38)
    static let bubbleInMeta = textSecondary
    static let chatBackgroundWhite = Color.dynamic(light: 0xFFFFFF, dark: 0x0E1318)

    static func incomingFill(on wallpaper: ChatWallpaper, hovering: Bool) -> Color {
        switch wallpaper {
        case .white: hovering ? bubbleInOnWhiteHover : bubbleInOnWhite
        default: hovering ? bubbleInHover : bubbleIn
        }
    }

    /// Nền khung chat theo lựa chọn trong Cài đặt.
    static var wallpaper: some View { ChatWallpaperView() }
}

/// Các kiểu hình nền khung chat.
enum ChatWallpaper: String, CaseIterable, Identifiable {
    case white
    case gradient
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: "Trắng"
        case .gradient: "Gradient xanh (kiểu Telegram)"
        case .dots: "Lưới chấm"
        }
    }
}

struct ChatWallpaperView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        switch settings.chatWallpaper {
        case .white: XTheme.chatBackgroundWhite
        case .gradient: GradientWallpaper()
        case .dots: DotGridBackground()
        }
    }
}

/// Gradient mềm nhiều điểm màu, tông xanh dương nhạt như hình nền mặc định của Telegram.
private struct GradientWallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x0F1B2A), Color(hex: 0x13253A), Color(hex: 0x0E1720)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(colors: [Color(hex: 0x1E3A5C).opacity(0.6), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 600)
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xCFE3F5), Color(hex: 0xB7D4EE), Color(hex: 0xD9EAF3), Color(hex: 0xC2DCEB)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(colors: [Color(hex: 0xE6F1FA).opacity(0.9), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 650)
                RadialGradient(colors: [Color(hex: 0xA9CBE8).opacity(0.7), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 600)
                RadialGradient(colors: [Color(hex: 0xD4E9E4).opacity(0.6), .clear],
                               center: .center, startRadius: 0, endRadius: 450)
            }
        }
    }
}

private struct DotGridBackground: View {
    var body: some View {
        XTheme.chatBackground
            .overlay(
                Canvas { context, size in
                    let step: CGFloat = 18
                    var path = Path()
                    var y: CGFloat = step / 2
                    while y < size.height {
                        var x: CGFloat = step / 2
                        while x < size.width {
                            path.addEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                            x += step
                        }
                        y += step
                    }
                    context.fill(path, with: .color(XTheme.chatDots))
                }
            )
    }
}
