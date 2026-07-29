import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var showUpgrade = false

    private var user: UserDto? { AuthRepository.shared.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        accountCard

                        if session.isGuest {
                            Button { showUpgrade = true } label: { ownSubscriptionCard }
                                .buttonStyle(.plain)
                        }

                        if session.isLoggedIn {
                            NavigationLink { ShareSubscriptionView() } label: { shareCard }
                                .buttonStyle(.plain)
                            NavigationLink { ReferralView() } label: { referralCard }
                                .buttonStyle(.plain)
                            NavigationLink { DevicesView(subscriptionId: nil) } label: { devicesCard }
                                .buttonStyle(.plain)
                        }

                        splitTunnelNote

                        if session.isLoggedIn && session.usingSharedSubscription {
                            Button("Отключить гостевой доступ") {
                                session.dropSharedSubscription()
                                Task { await SubscriptionModel.shared.refresh(force: true) }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }

                        Button(session.isGuest ? "Отключить гостевой доступ" : "Выйти из аккаунта") {
                            Task { await session.logOut() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Ещё")
        }
        .sheet(isPresented: $showUpgrade) {
            LoginView(mode: .upgrade) { showUpgrade = false }
                .environmentObject(session)
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Аккаунт").font(.caption).foregroundStyle(.secondary)
            Text(session.isGuest ? "Гостевой доступ по подписке" : (user?.displayName ?? "—"))
                .font(.headline)

            if session.isGuest {
                Text("Оплата и управление подпиской доступны у её владельца")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if session.usingSharedSubscription {
                Text("Пока работает подписка, которой с вами поделились. Купите свою — приложение переключится на неё само.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var ownSubscriptionCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Своя подписка").font(.headline)
            Text("Зарегистрируйтесь через Telegram или почту и купите собственную подписку. Гостевой доступ будет работать, пока не заработает ваша.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Поделиться подпиской").font(.headline)
            Text("QR-код для близких: они подключатся к вашей подписке без доступа к оплате")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var referralCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Пригласить друга").font(.headline)
            Text("Делитесь ссылкой и получайте бонусы с платежей приглашённых")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Подключённые устройства").font(.headline)
            Text("Отключите лишние, чтобы освободить места в лимите подписки")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    /// На Android здесь выбор приложений для VPN. На iOS такого API нет:
    /// per-app VPN доступен только под управлением MDM, поэтому честно
    /// объясняем это вместо неработающего экрана.
    private var splitTunnelNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Приложения через VPN").font(.headline)
            Text("iOS не разрешает приложениям выбирать, какие программы идут через VPN, — такой доступ есть только у корпоративных профилей. Разделение по сайтам и адресам настраивается на стороне сервиса.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}
