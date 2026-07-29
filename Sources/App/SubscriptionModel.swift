import Foundation
import Network
import SwiftUI

/// Общая модель подписки для «Главной» и «Серверов»: список узлов, выбранный
/// узел, пинги и переключение между подписками.
@MainActor
final class SubscriptionModel: ObservableObject {

    static let shared = SubscriptionModel()

    @Published private(set) var servers: [ProxyProfile] = []
    @Published private(set) var selectedServer: Int = 0
    @Published private(set) var subscription: SubscriptionStatusResponse?
    @Published private(set) var userInfo: SubscriptionUserInfo?
    @Published private(set) var subscriptions: [SubscriptionListItem] = []
    @Published private(set) var selectedSubscriptionId: Int64?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var pings: [Int: Int64] = [:]
    @Published private(set) var pinging = false

    private let repo = SubscriptionRepository.shared
    private let store = SharedStore.shared

    private init() {
        selectedSubscriptionId = store.selectedSubscriptionId
        loadCached()
    }

    var selectedProfile: ProxyProfile? {
        servers.indices.contains(selectedServer) ? servers[selectedServer] : nil
    }

    /// Мгновенно показываем сохранённую подписку — приложение открывается с
    /// готовым списком серверов даже без сети.
    private func loadCached() {
        guard let (cached, info) = repo.cachedServers(for: selectedSubscriptionId) else { return }
        servers = cached
        userInfo = info
        selectedServer = min(
            store.selectedServerIndex(for: selectedSubscriptionId),
            max(cached.count - 1, 0)
        )
    }

    func refresh(force: Bool = false) async {
        loading = true
        error = nil
        loadCached()

        var failure: String?

        let subs = await repo.subscriptions()
        var selectedId = store.selectedSubscriptionId
        if !subs.isEmpty, !subs.contains(where: { $0.id == selectedId }) {
            // выбранной подписки больше нет — берём активную, иначе первую
            selectedId = (subs.first { $0.isActive } ?? subs[0]).id
            store.selectedSubscriptionId = selectedId
        }
        subscriptions = subs
        selectedSubscriptionId = selectedId

        // без аккаунта кабинет недоступен — только подписка по ссылке
        if store.isLoggedIn {
            do {
                subscription = try await repo.status()
            } catch {
                failure = error.localizedDescription
            }
        } else {
            subscription = nil
        }

        do {
            let (fresh, info) = try await repo.fetchServers(forceRefresh: force)
            servers = fresh
            if let info { userInfo = info }
        } catch {
            if failure == nil { failure = error.localizedDescription }
        }

        selectedServer = min(
            store.selectedServerIndex(for: selectedId),
            max(servers.count - 1, 0)
        )
        // если данные в итоге есть — сетевую ошибку не показываем
        self.error = servers.isEmpty ? failure : nil
        loading = false

        if subs.count > 1 {
            Task.detached { await SubscriptionRepository.shared.prefetchAllSubscriptions() }
        }
    }

    func selectServer(_ index: Int) {
        guard servers.indices.contains(index) else { return }
        selectedServer = index
        store.setSelectedServerIndex(index, for: selectedSubscriptionId)

        // при активном VPN сразу переключаемся на выбранный сервер
        let profile = servers[index]
        Task { await VpnManager.shared.switchServer(to: profile) }
    }

    func selectSubscription(_ id: Int64) async {
        guard id != selectedSubscriptionId else { return }
        VpnManager.shared.disconnect()
        repo.selectSubscription(id: id)
        selectedSubscriptionId = id

        // серверы этой подписки уже могут лежать в кэше — показываем сразу
        if let (cached, info) = repo.cachedServers(for: id) {
            servers = cached
            userInfo = info
        } else {
            servers = []
            userInfo = nil
        }
        selectedServer = store.selectedServerIndex(for: id)
        pings = [:]
        await refresh(force: true)
    }

    /// Замер задержки через ядро Xray — как «real ping» в v2rayNG.
    ///
    /// Ядро живёт в расширении, а не в приложении, поэтому замер работает
    /// только при поднятом туннеле; иначе показываем время ответа сервера
    /// по TCP.
    func pingAll() async {
        guard !pinging, !servers.isEmpty else { return }
        pinging = true
        pings = [:]

        await withTaskGroup(of: (Int, Int64?).self) { group in
            for (index, profile) in servers.enumerated() {
                group.addTask {
                    let delay = await TcpPing.measure(host: profile.address, port: profile.port)
                    return (index, delay)
                }
            }
            for await (index, delay) in group {
                pings[index] = delay ?? -1
            }
        }
        pinging = false
    }
}

/// Простой замер задержки до узла: открываем TCP-соединение и засекаем время.
enum TcpPing {

    static func measure(host: String, port: Int, timeout: TimeInterval = 3) async -> Int64? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ping.\(host).\(port)")
            // ответить можно только один раз: соединение и таймаут срабатывают
            // на разных потоках и оба зовут finish
            let once = OnceGuard()

            @Sendable func finish(_ value: Int64?) {
                guard once.claim() else { return }
                continuation.resume(returning: value)
            }

            let started = Date()
            let connection = NWConnectionFactory.make(host: host, port: port)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Date().timeIntervalSince(started)
                    connection.cancel()
                    finish(Int64(elapsed * 1000))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                finish(nil)
            }
        }
    }
}

/// Одноразовый флаг под замком: продолжение корутины нельзя возобновлять дважды.
private final class OnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

enum NWConnectionFactory {
    static func make(host: String, port: Int) -> NWConnection {
        NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? .https,
            using: .tcp
        )
    }
}
