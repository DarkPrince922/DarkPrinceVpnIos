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

/// Вкладки приложения. Стандартный TabView заменён своим: системная панель
/// не умеет «таблетку» под активным пунктом, а она — заметная часть
/// выбранного оформления.
enum AppTab: Hashable {
    case home, servers, plans, balance, settings

    var title: String {
        switch self {
        case .home: return "Главная"
        case .servers: return "Серверы"
        case .plans: return "Тарифы"
        case .balance: return "Баланс"
        case .settings: return "Ещё"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .servers: return "server.rack"
        case .plans: return "cart.fill"
        case .balance: return "creditcard.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionModel
    @State private var tab: AppTab = .home

    private var tabs: [AppTab] {
        // без аккаунта кабинет недоступен: покупок и баланса нет
        session.isLoggedIn
            ? [.home, .servers, .plans, .balance, .settings]
            : [.home, .servers, .settings]
    }

    var body: some View {
        Group {
            switch tab {
            case .home: HomeView()
            case .servers: ServersView()
            case .plans: PlansView()
            case .balance: BalanceView()
            case .settings: SettingsView()
            }
        }
        // safeAreaInset сам резервирует место под панель и поднимает её над
        // домашним индикатором — содержимое под неё не уезжает
        .safeAreaInset(edge: .bottom) {
            NavPillBar(tabs: tabs, selection: $tab)
        }
        .onChange(of: session.isLoggedIn) { _ in
            if !tabs.contains(tab) { tab = .home }
        }
    }
}

/// Плавающая панель со скруглением; под активным пунктом — «таблетка».
struct NavPillBar: View {
    let tabs: [AppTab]
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { item in
                let selected = item == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { selection = item }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
                        Text(item.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Theme.gold : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected ? Theme.gold.opacity(0.16) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Theme.midBlue.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}
