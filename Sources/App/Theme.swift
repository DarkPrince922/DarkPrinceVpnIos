import SwiftUI

/// Оформление под логотип: тёмный синий фон и золото.
enum Theme {
    static let gold = Color(red: 0.85, green: 0.68, blue: 0.32)
    static let goldSoft = Color(red: 0.96, green: 0.85, blue: 0.55)
    static let deepBlue = Color(red: 0.04, green: 0.07, blue: 0.15)
    static let midBlue = Color(red: 0.07, green: 0.12, blue: 0.24)

    static var background: some View {
        LinearGradient(
            colors: [deepBlue, midBlue, deepBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let cardBackground = Color.white.opacity(0.06)
}

/// Карточка в общем стиле: полупрозрачная подложка со скруглением.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

enum Format {
    static func rubles(_ kopeks: Int64) -> String {
        let value = Double(kopeks) / 100
        return String(format: value == value.rounded() ? "%.0f ₽" : "%.2f ₽", value)
    }

    static func bytes(_ value: Int64) -> String {
        let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        var size = Double(value)
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        return String(format: index == 0 ? "%.0f %@" : "%.1f %@", size, units[index])
    }

    static func days(_ count: Int) -> String {
        let remainder100 = count % 100
        let remainder10 = count % 10
        if remainder100 >= 11 && remainder100 <= 14 { return "\(count) дней" }
        if remainder10 == 1 { return "\(count) день" }
        if (2...4).contains(remainder10) { return "\(count) дня" }
        return "\(count) дней"
    }
}
