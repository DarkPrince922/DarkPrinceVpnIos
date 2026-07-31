import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var showUpgrade = false
    @State private var path: [Route] = []

    private enum Route: Hashable { case share, referral, devices }

    private var user: UserDto? { AuthRepository.shared.currentUser }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Настройки")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        SectionHeader("Аккаунт")
                        GroupCard {
                            SettingsRow(
                                systemName: "checkmark.shield.fill",
                                title: identity,
                                subtitle: accountHint,
                                showChevron: false
                            )
                            if session.isGuest {
                                RowDivider()
                                SettingsRow(
                                    systemName: "bag.fill",
                                    title: "Своя подписка",
                                    subtitle: "Зарегистрируйтесь и купите собственную"
                                ) {
                                    showUpgrade = true
                                }
                            }
                        }

                        SectionHeader("Подключение").padding(.top, 22)
                        GroupCard {
                            SettingsRow(
                                systemName: "square.grid.2x2.fill",
                                title: "Приложения через VPN",
                                subtitle: "iOS не даёт выбирать приложения — только корпоративным профилям",
                                tint: .gray,
                                showChevron: false
                            )
                        }

                        if session.isLoggedIn {
                            SectionHeader("Подписка").padding(.top, 22)
                            GroupCard {
                                SettingsRow(
                                    systemName: "iphone.gen3",
                                    title: "Подключённые устройства",
                                    subtitle: "Отключите лишние, чтобы освободить лимит"
                                ) {
                                    path.append(.devices)
                                }
                                RowDivider()
                                SettingsRow(
                                    systemName: "qrcode",
                                    title: "Поделиться подпиской",
                                    subtitle: "QR-код для близких, без доступа к оплате"
                                ) {
                                    path.append(.share)
                                }
                                RowDivider()
                                SettingsRow(
                                    systemName: "person.badge.plus",
                                    title: "Пригласить друга",
                                    subtitle: "Бонусы с платежей приглашённых",
                                    tint: Theme.goldSoft
                                ) {
                                    path.append(.referral)
                                }
                            }
                        }

                        GroupCard {
                            if session.isLoggedIn && session.usingSharedSubscription {
                                SettingsRow(
                                    systemName: "qrcode.viewfinder",
                                    title: "Отключить гостевой доступ",
                                    subtitle: "Перестать пользоваться чужой подпиской",
                                    showChevron: false
                                ) {
                                    session.dropSharedSubscription()
                                    Task { await SubscriptionModel.shared.refresh(force: true) }
                                }
                                RowDivider()
                            }
                            SettingsRow(
                                systemName: "rectangle.portrait.and.arrow.right",
                                title: session.isGuest ? "Отключить гостевой доступ" : "Выйти из аккаунта",
                                tint: .red,
                                showChevron: false
                            ) {
                                Task { await session.logOut() }
                            }
                        }
                        .padding(.top, 22)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationDestination(for: Route.self) { destination in
                switch destination {
                case .share: ShareSubscriptionView()
                case .referral: ReferralView()
                case .devices: DevicesView(subscriptionId: nil)
                }
            }
        }
        .sheet(isPresented: $showUpgrade) {
            LoginView(mode: .upgrade) { showUpgrade = false }
                .environmentObject(session)
        }
    }

    private var identity: String {
        session.isGuest ? "Гостевой доступ по подписке" : (user?.displayName ?? "—")
    }

    private var accountHint: String? {
        if session.isGuest { return "Оплата и управление подпиской — у владельца" }
        if session.usingSharedSubscription {
            return "Работает чужая подписка. Купите свою — переключится сама"
        }
        return user?.firstName
    }
}
