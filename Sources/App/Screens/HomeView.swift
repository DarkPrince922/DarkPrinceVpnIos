import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vpn: VpnManager
    @StateObject private var model = SubscriptionModel.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    PowerButton(state: vpn.state) {
                        switch vpn.state {
                        case .connected, .connecting:
                            vpn.disconnect()
                        default:
                            guard let profile = model.selectedProfile else {
                                Task { await model.refresh(force: true) }
                                return
                            }
                            Task { await vpn.connect(profile: profile) }
                        }
                    }
                    .padding(.top, 12)

                    Text(stateTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    if vpn.state == .connected {
                        HStack(spacing: 16) {
                            Text("↑ \(Format.bytes(vpn.stats.uploadBytes))")
                            Text("↓ \(Format.bytes(vpn.stats.downloadBytes))")
                        }
                        .font(.subheadline)
                        .padding(.top, 6)
                    }

                    if let error = vpn.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }

                    SectionHeader("Текущая подписка")
                        .padding(.top, 28)

                    SubscriptionCard(model: model)

                    if let error = model.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh(force: true) }
        }
        .task { await model.refresh() }
    }

    private var stateTitle: String {
        switch vpn.state {
        case .connected: return "Подключено"
        case .connecting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        case .disconnected: return "Нажмите для подключения"
        }
    }
}

/// Большая круглая кнопка: тонкое кольцо вокруг тёмного круга, при активном
/// туннеле — расходящиеся волны.
private struct PowerButton: View {
    let state: VpnState
    let action: () -> Void

    @State private var wave = false

    private var accent: Color {
        switch state {
        case .connected: return Theme.gold
        case .connecting, .disconnecting: return Theme.goldSoft.opacity(0.7)
        case .disconnected: return Color.white.opacity(0.35)
        }
    }

    var body: some View {
        ZStack {
            if state == .connected {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(accent.opacity(wave ? 0 : 0.3), lineWidth: 2)
                        .scaleEffect(wave ? 1.0 : 0.72)
                        .animation(
                            .linear(duration: 2.6)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 1.3),
                            value: wave
                        )
                }
            }

            Circle()
                .fill(Theme.midBlue.opacity(0.7))
                .frame(width: 230, height: 230)
                .overlay(Circle().stroke(accent.opacity(0.55), lineWidth: 2))
                .overlay {
                    if state == .connecting {
                        ProgressView().tint(accent).scaleEffect(1.4)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 74, weight: .regular))
                            .foregroundStyle(accent)
                    }
                }
                .onTapGesture {
                    guard state != .connecting else { return }
                    action()
                }
        }
        .frame(width: 268, height: 268)
        .onAppear { wave = true }
    }
}

/// Карточка подписки: название с переключателем тарифов, срок и трафик
/// полосой, ниже — выбранный сервер.
private struct SubscriptionCard: View {
    @ObservedObject var model: SubscriptionModel

    /// При нескольких подписках общий статус кабинета относится не к той,
    /// что выбрана, — сведения берём из самой выбранной подписки.
    private var current: SubscriptionListItem? {
        model.subscriptions.count > 1
            ? model.subscriptions.first { $0.id == model.selectedSubscriptionId }
            : nil
    }

    private var title: String {
        current?.displayName ?? model.subscription?.tariffName ?? "Подписка"
    }

    private var daysLeft: Int? {
        if let end = current?.endDate, let days = daysUntil(end) { return days }
        if let days = model.subscription?.daysLeft { return days }
        if let expire = model.userInfo?.expireUnix, expire > 0 {
            return max(0, Int((Double(expire) - Date().timeIntervalSince1970) / 86400))
        }
        return nil
    }

    private var usedGb: Double? {
        if let used = current?.trafficUsedGb { return used }
        if let used = model.subscription?.trafficUsedGb { return used }
        guard let info = model.userInfo else { return nil }
        let total = (info.uploadBytes ?? 0) + (info.downloadBytes ?? 0)
        return total > 0 || info.totalBytes != nil ? Double(total) / 1_073_741_824 : nil
    }

    private var limitGb: Double? {
        if let limit = current?.trafficLimitGb { return limit }
        if let limit = model.subscription?.trafficLimitGb { return limit }
        if let total = model.userInfo?.totalBytes, total > 0 {
            return Double(total) / 1_073_741_824
        }
        return nil
    }

    var body: some View {
        GroupCard {
            HStack(spacing: 8) {
                if model.subscriptions.count > 1 {
                    Menu {
                        ForEach(model.subscriptions) { item in
                            Button {
                                Task { await model.selectSubscription(item.id) }
                            } label: {
                                Text(item.displayName)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.down")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Text(title).font(.headline)
                }

                Spacer()

                CircleActionButton(systemName: "arrow.clockwise") {
                    Task { await model.refresh(force: true) }
                }
                CircleActionButton(systemName: "speedometer") {
                    Task { await model.pingAll() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                Text(daysLeft.map { "Осталось \($0) дн." } ?? "Срок неизвестен")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .tint(Theme.gold)

                Text(trafficText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            selectedServerRow
                .padding(.top, 10)
        }
    }

    private var progress: Double {
        guard let limit = limitGb, limit > 0, let used = usedGb else { return 0.06 }
        return min(max(used / limit, 0), 1)
    }

    private var trafficText: String {
        let used = String(format: "%.1f ГБ", usedGb ?? 0)
        // ноль в лимите означает безлимит, а не «нисколько»
        guard let limit = limitGb, limit > 0 else { return "\(used) / ∞" }
        return "\(used) / " + String(format: "%.0f", limit)
    }

    private var selectedServerRow: some View {
        let server = model.selectedProfile
        return HStack(spacing: 12) {
            EmojiTile(emoji: server.flatMap { leadingEmoji($0.name) } ?? "🌐")
            VStack(alignment: .leading, spacing: 6) {
                Text(server.map { nameWithoutEmoji($0.name) } ?? "Нет доступных серверов")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let server {
                    HStack(spacing: 6) {
                        TagChip(server.transportLabel, tint: Theme.goldSoft)
                        if server.rawConfig != nil { TagChip("JSON") }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

/// Сколько дней осталось до даты окончания подписки. Кабинет отдаёт дату
/// строкой ISO — берём из неё только календарный день.
func daysUntil(_ endDate: String) -> Int? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    guard let date = formatter.date(from: String(endDate.prefix(10))) else { return nil }
    let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
    return max(0, days)
}
