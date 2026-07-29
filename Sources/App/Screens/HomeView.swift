import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vpn: VpnManager
    @StateObject private var model = SubscriptionModel.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        connectButton
                        statusCard
                        if model.subscriptions.count > 1 { subscriptionPicker }
                        subscriptionCard
                        if let error = model.error { errorCard(error) }
                    }
                    .padding(16)
                }
                .refreshable { await model.refresh(force: true) }
            }
            .navigationTitle("Главная")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await model.refresh() }
    }

    // MARK: - Кнопка подключения

    private var connectButton: some View {
        Button {
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
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.gold.opacity(0.35), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 130
                        )
                    )
                Circle()
                    .stroke(strokeColor, lineWidth: 3)
                    .frame(width: 190, height: 190)
                VStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 56))
                        .foregroundStyle(strokeColor)
                    Text(stateTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            .frame(height: 240)
        }
        .buttonStyle(.plain)
    }

    private var strokeColor: Color {
        switch vpn.state {
        case .connected: return Theme.gold
        case .connecting, .disconnecting: return Theme.goldSoft.opacity(0.6)
        case .disconnected: return Color.white.opacity(0.25)
        }
    }

    private var iconName: String {
        switch vpn.state {
        case .connected: return "shield.lefthalf.filled"
        case .connecting, .disconnecting: return "shield.lefthalf.filled.slash"
        case .disconnected: return "power"
        }
    }

    private var stateTitle: String {
        switch vpn.state {
        case .connected: return "Подключено"
        case .connecting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        case .disconnected: return "Отключено"
        }
    }

    // MARK: - Карточки

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    model.selectedProfile?.name ?? "Сервер не выбран",
                    systemImage: "globe"
                )
                .font(.headline)
                Spacer()
            }
            if vpn.state == .connected {
                HStack(spacing: 16) {
                    Label(Format.bytes(vpn.stats.downloadBytes), systemImage: "arrow.down")
                    Label(Format.bytes(vpn.stats.uploadBytes), systemImage: "arrow.up")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let error = vpn.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .card()
    }

    private var subscriptionPicker: some View {
        Menu {
            ForEach(model.subscriptions) { sub in
                Button(sub.displayName) {
                    Task { await model.selectSubscription(sub.id) }
                }
            }
        } label: {
            HStack {
                Text(currentSubscriptionName)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var currentSubscriptionName: String {
        model.subscriptions.first { $0.id == model.selectedSubscriptionId }?.displayName
            ?? "Подписка"
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Подписка").font(.headline)

            if let days = model.subscription?.daysLeft {
                Text("Осталось \(Format.days(days))")
                    .font(.subheadline)
            } else if let expire = model.userInfo?.expireUnix, expire > 0 {
                let left = Int((Double(expire) - Date().timeIntervalSince1970) / 86400)
                Text(left >= 0 ? "Осталось \(Format.days(left))" : "Подписка истекла")
                    .font(.subheadline)
            }

            if let info = model.userInfo, let total = info.totalBytes, total > 0 {
                let used = (info.uploadBytes ?? 0) + (info.downloadBytes ?? 0)
                ProgressView(value: Double(used), total: Double(total))
                    .tint(Theme.gold)
                Text("\(Format.bytes(used)) из \(Format.bytes(total))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Серверов доступно: \(model.servers.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .card()
    }
}
