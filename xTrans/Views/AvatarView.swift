import SwiftUI

/// Avatar dạng ô vuông bo góc (khác avatar tròn của Telegram).
struct AvatarView: View {
    let text: String
    let colors: [Color]
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(text)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}
