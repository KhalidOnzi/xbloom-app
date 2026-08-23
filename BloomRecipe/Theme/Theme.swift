import SwiftUI

enum BloomTheme {
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.89)
    static let foam = Color(red: 0.99, green: 0.97, blue: 0.94)
    static let espresso = Color(red: 0.27, green: 0.16, blue: 0.11)
    static let roast = Color(red: 0.45, green: 0.24, blue: 0.14)
    static let clay = Color(red: 0.72, green: 0.38, blue: 0.24)
    static let moss = Color(red: 0.42, green: 0.48, blue: 0.36)
    static let ink = Color(red: 0.16, green: 0.12, blue: 0.09)
    static let muted = Color(red: 0.45, green: 0.38, blue: 0.32)
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(BloomTheme.foam, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BloomTheme.espresso.opacity(0.06), lineWidth: 1)
            }
    }
}

extension View {
    func bloomCard() -> some View {
        modifier(CardSurface())
    }

    func bloomBackground() -> some View {
        background(BloomTheme.cream.ignoresSafeArea())
    }
}

struct BloomButtonStyle: ButtonStyle {
    var filled: Bool = true
    var tint: Color = BloomTheme.roast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(filled ? Color.white : tint)
            .background(
                filled ? tint : tint.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
