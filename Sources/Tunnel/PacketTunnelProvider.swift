import Foundation
import NetworkExtension
import Tun2SocksKit
import os

/// Схема ровно та же, что в Android-приложении: ядро Xray поднимает локальный
/// SOCKS, а hev-socks5-tunnel перекладывает в него пакеты из TUN.
///
/// Расширение работает в жёстком лимите памяти (около 50 МБ), поэтому libXray
/// под iOS сам ограничивает Go-рантайм 30 МБ и раз в секунду отдаёт память
/// системе. Ничего тяжёлого здесь делать нельзя: сеть за подпиской ходит
/// приложение, сюда попадает уже готовый профиль.
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = Logger(subsystem: "ru.darkprince.vpn", category: "tunnel")
    private var tunnelIsUp = false

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let profile = SharedStore.shared.activeProfile else {
            log.error("Не выбран сервер: приложение не положило профиль в общий контейнер")
            throw TunnelError.noProfile
        }

        let settings = makeTunnelSettings()
        try await setTunnelNetworkSettings(settings)

        let config = XrayConfigBuilder.build(profile: profile)
        do {
            try LibXrayBridge.runXray(configJSON: config)
        } catch {
            log.error("Ядро не запустилось: \(error.localizedDescription, privacy: .public)")
            throw TunnelError.coreFailed(error.localizedDescription)
        }

        try await startSocksBridge()
        tunnelIsUp = true
        log.info("Туннель поднят: \(profile.name, privacy: .public)")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        log.info("Останавливаю туннель, причина \(reason.rawValue, privacy: .public)")
        Socks5Tunnel.quit()
        LibXrayBridge.stopXray()
        tunnelIsUp = false
    }

    /// Приложение спрашивает статистику трафика через `sendProviderMessage`.
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let request = try? JSONDecoder().decode(TunnelMessage.self, from: messageData) else {
            return nil
        }
        switch request {
        case .stats:
            let stats = Socks5Tunnel.stats
            let reply = TunnelStats(
                uploadBytes: Int64(stats.up.bytes),
                downloadBytes: Int64(stats.down.bytes),
                running: tunnelIsUp
            )
            return try? JSONEncoder().encode(reply)
        }
    }

    // MARK: - Настройки туннеля

    private func makeTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // локальные сети оставляем в обход туннеля, иначе перестают работать
        // принтеры, роутеры и прочее оборудование в домашней сети
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
        ]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        settings.mtu = 8500
        return settings
    }

    // MARK: - Мост TUN → SOCKS

    private func startSocksBridge() async throws {
        let config = """
        tunnel:
          mtu: 8500
        socks5:
          port: \(XrayConfigBuilder.socksPort)
          address: 127.0.0.1
          udp: udp
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-level: warn
          limit-nofile: 65535
        """

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            Socks5Tunnel.run(withConfig: .string(content: config)) { [weak self] code in
                // колбэк приходит, когда мост завершился: при нормальной работе
                // это происходит только после quit()
                guard let self else { return }
                if code != 0 {
                    self.log.error("Мост TUN→SOCKS завершился с кодом \(code, privacy: .public)")
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: TunnelError.bridgeFailed(code))
                        return
                    }
                    self.cancelTunnelWithError(TunnelError.bridgeFailed(code))
                }
            }
            // hev блокируется до самого завершения, поэтому ждать здесь нечего:
            // если он не смог стартовать, ошибка придёт колбэком выше
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if !resumed {
                    resumed = true
                    continuation.resume()
                }
            }
        }
    }
}

enum TunnelError: LocalizedError {
    case noProfile
    case coreFailed(String)
    case bridgeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noProfile:
            return "Сервер не выбран. Откройте приложение и выберите узел."
        case .coreFailed(let message):
            return "Ядро не запустилось: \(message)"
        case .bridgeFailed(let code):
            return "Не удалось поднять туннель (код \(code))"
        }
    }
}
