import SwiftUI

/// Общие элементы интерфейса: заголовки секций, сгруппированные карточки,
/// строки настроек, плитки-иконки и чипы. Оформление повторяет
/// Android-версию, чтобы приложения выглядели одинаково.

/// Подпись над группой: капсом, с разрядкой, приглушённым цветом.
struct SectionHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.medium)
            .kerning(1.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }
}

/// Карточка-группа: внутри идут строки, разделённые тонкой линией.
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

/// Разделитель между строками группы — с отступом под плитку-иконку.
struct RowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
            .padding(.leading, 68)
            .padding(.trailing, 16)
    }
}

/// Квадратная плитка с иконкой: подложка и рамка в цвет акцента.
struct IconTile: View {
    let systemName: String
    var tint: Color = Theme.gold

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
    }
}

/// То же, но вместо иконки — символ: флаг страны из названия сервера.
struct EmojiTile: View {
    let emoji: String
    var tint: Color = Theme.gold

    var body: some View {
        Text(emoji)
            .font(.title2)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

/// Мелкая метка под названием: транспорт, формат подписки и т.п.
struct TagChip: View {
    let text: String
    var tint: Color = Theme.gold

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Строка группы: плитка-иконка, заголовок с пояснением, значение справа
/// и стрелка. Вместо значения можно подставить свой элемент.
struct SettingsRow<Trailing: View>: View {
    let systemName: String
    let title: String
    var subtitle: String?
    var value: String?
    var tint: Color = Theme.gold
    var showChevron: Bool = true
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let content = HStack(spacing: 12) {
            IconTile(systemName: systemName, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing

            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        systemName: String,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        tint: Color = Theme.gold,
        showChevron: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.init(
            systemName: systemName,
            title: title,
            subtitle: subtitle,
            value: value,
            tint: tint,
            showChevron: showChevron,
            action: action,
            trailing: { EmptyView() }
        )
    }
}

/// Круглая кнопка-действие рядом с заголовком карточки.
struct CircleActionButton: View {
    let systemName: String
    var tint: Color = Theme.gold
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Ведущий символ названия — флаг страны. Панель обычно ставит его в начало
/// имени узла; в списке он уезжает в отдельную плитку, а из заголовка
/// убирается, чтобы не дублироваться.
func leadingEmoji(_ name: String) -> String? {
    let trimmed = name.drop { $0 == " " }
    guard let first = trimmed.first else { return nil }
    guard first.unicodeScalars.allSatisfy({ $0.properties.isEmoji && $0.value > 0x238C })
            || first.unicodeScalars.contains(where: { (0x1F1E6...0x1F1FF).contains($0.value) })
    else { return nil }
    return String(first)
}

/// Название без ведущего флага.
func nameWithoutEmoji(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard let emoji = leadingEmoji(name) else { return trimmed }
    let stripped = trimmed.dropFirst(emoji.count).trimmingCharacters(in: .whitespaces)
    return stripped.isEmpty ? trimmed : stripped
}
