import Foundation
import NetworkExtension
import Combine

enum VpnState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting

    init(_ status: NEVPNStatus) {
        switch status {
        case .connected: self = .connected
        case .connecting, .reasserting: self = .connecting
        case .disconnecting: self = .disconnecting
        default: self = .disconnected
        }
    }
}

/// Управление сетевым расширением со стороны приложения.
///
/// Профиль VPN в системе один; при смене сервера мы не пересоздаём его, а
/// кладём новый узел в общий контейнер и перезапускаем туннель — так
/// переключение между серверами не требует подтверждения от пользователя.
@MainActor
final class VpnManager: ObservableObject {

    static let shared = VpnManager()

    @Published private(set) var state: VpnState = .disconnected
    @Published private(set) var stats: TunnelStats = .zero
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var statsTimer: Timer?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let session = notification.object as? NEVPNConnection else { return }
            Task { @MainActor [weak self] in
                self?.apply(status: session.status)
            }
        }
        Task { await prepare() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Загружает существующий профиль VPN или создаёт новый.
    @discardableResult
    func prepare() async -> NETunnelProviderManager? {
        do {
            let existing = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = existing.first ?? NETunnelProviderManager()
            configure(manager)
            self.manager = manager
            apply(status: manager.connection.status)
            return manager
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func configure(_ manager: NETunnelProviderManager) {
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppGroup.tunnelBundleIdentifier
        // адрес показывается в настройках iOS; конкретный узел живёт в
        // общем контейнере и меняется без пересоздания профиля
        proto.serverAddress = "DarkPrince VPN"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "DarkPrince VPN"
    }

    func connect(profile: ProxyProfile) async {
        lastError = nil
        SharedStore.shared.activeProfile = profile

        guard let manager = await prepare() else { return }
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            // после сохранения настройки нужно перечитать, иначе система
            // может запустить туннель со старой конфигурацией
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
            state = .connecting
        } catch {
            lastError = humanReadable(error)
            state = .disconnected
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        state = .disconnecting
    }

    /// Мгновенное переключение сервера: профиль подменяем и перезапускаем
    /// туннель, разрешение у пользователя больше не спрашивается.
    func switchServer(to profile: ProxyProfile) async {
        guard state == .connected || state == .connecting else {
            SharedStore.shared.activeProfile = profile
            return
        }
        SharedStore.shared.activeProfile = profile
        manager?.connection.stopVPNTunnel()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await connect(profile: profile)
    }

    // MARK: - Состояние и статистика

    private func apply(status: NEVPNStatus) {
        state = VpnState(status)
        if state == .connected {
            startStatsPolling()
        } else {
            stopStatsPolling()
            if state == .disconnected { stats = .zero }
        }
    }

    private func startStatsPolling() {
        guard statsTimer == nil else { return }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshStats() }
        }
    }

    private func stopStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func refreshStats() async {
        guard let session = manager?.connection as? NETunnelProviderSession,
              let request = try? JSONEncoder().encode(TunnelMessage.stats)
        else { return }

        let reply: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(request) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(returning: nil)
            }
        }
        guard let reply, let decoded = try? JSONDecoder().decode(TunnelStats.self, from: reply) else {
            return
        }
        stats = decoded
    }

    private func humanReadable(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NEVPNErrorDomain,
           nsError.code == NEVPNError.configurationReadWriteFailed.rawValue {
            return "Разрешите добавить конфигурацию VPN и попробуйте снова."
        }
        return error.localizedDescription
    }
}
