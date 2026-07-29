import SwiftUI

@main
struct DarkPrinceVpnApp: App {
    @StateObject private var session = SessionModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(VpnManager.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
    }
}

/// Состояние сессии: вошёл ли пользователь и пользуется ли он чужой подпиской.
///
/// Гостевой режим — это «чужая подписка и нет аккаунта». Гость может завести
/// свой аккаунт, не теряя доступ: подписка, которой с ним поделились,
/// работает, пока не заработает его собственная.
@MainActor
final class SessionModel: ObservableObject {

    @Published var isLoggedIn: Bool
    @Published var usingSharedSubscription: Bool

    private let store = SharedStore.shared

    init() {
        isLoggedIn = SharedStore.shared.isLoggedIn
        usingSharedSubscription = SharedStore.shared.guestSubUrl != nil
    }

    var isGuest: Bool { usingSharedSubscription && !isLoggedIn }

    func refresh() {
        isLoggedIn = store.isLoggedIn
        usingSharedSubscription = store.guestSubUrl != nil
    }

    func didLogIn() {
        isLoggedIn = true
        usingSharedSubscription = store.guestSubUrl != nil
    }

    func didActivateGuestSubscription() {
        usingSharedSubscription = true
        isLoggedIn = store.isLoggedIn
    }

    func logOut() async {
        VpnManager.shared.disconnect()
        // чужую подписку отпускаем в любом случае: она привязана к этому
        // телефону, а не к аккаунту
        SubscriptionRepository.shared.exitGuestMode()
        if isLoggedIn { await AuthRepository.shared.logout() }
        isLoggedIn = false
        usingSharedSubscription = false
    }

    func dropSharedSubscription() {
        VpnManager.shared.disconnect()
        SubscriptionRepository.shared.exitGuestMode()
        usingSharedSubscription = false
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if session.isLoggedIn || session.usingSharedSubscription {
                MainTabView()
            } else {
                LoginView(mode: .initial)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isLoggedIn)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Главная", systemImage: "shield.lefthalf.filled") }

            ServersView()
                .tabItem { Label("Серверы", systemImage: "server.rack") }

            // без аккаунта кабинет недоступен: покупок и баланса нет
            if session.isLoggedIn {
                PlansView()
                    .tabItem { Label("Тарифы", systemImage: "cart") }

                BalanceView()
                    .tabItem { Label("Баланс", systemImage: "creditcard") }
            }

            SettingsView()
                .tabItem { Label("Ещё", systemImage: "ellipsis.circle") }
        }
    }
}
