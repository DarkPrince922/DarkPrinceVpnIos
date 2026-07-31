import Foundation

enum ProxyProtocol: String, Codable {
    case vless, vmess, trojan, shadowsocks
}

/// Узел подписки. Если панель отдала подписку в формате Xray JSON, полный
/// конфиг лежит в `rawConfig` — тогда роутинг, правила и балансировщики
/// панели сохраняются целиком, а мы подменяем только inbounds.
struct ProxyProfile: Codable, Identifiable, Equatable {
    var id: String { "\(name)|\(address):\(port)" }

    var proxyProtocol: ProxyProtocol
    var name: String
    var address: String
    var port: Int
    var userId: String

    var flow: String?
    var encryption: String?
    var network: String = "tcp"
    var security: String = "none"
    var sni: String?
    var alpn: String?
    var fingerprint: String?
    var allowInsecure: Bool = false
    var publicKey: String?
    var shortId: String?
    var spiderX: String?
    var host: String?
    var path: String?
    var serviceName: String?
    var grpcMultiMode: Bool = false
    var headerType: String?
    var vmessSecurity: String = "auto"
    var rawConfig: String?

    /// Как узел выглядит в списке серверов: протокол, шифрование и транспорт.
    /// Адрес и домен намеренно не показываем — пользователю они ничего не
    /// говорят, а на чужом экране или скриншоте выдают инфраструктуру.
    var transportLabel: String {
        [
            proxyProtocol.rawValue,
            security.isEmpty || security == "none" ? nil : security,
            networkLabel,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var networkLabel: String {
        switch network.lowercased() {
        case "ws": return "websocket"
        case "grpc": return "gRPC"
        case "h2", "http": return "http/2"
        case "kcp": return "mkcp"
        case "": return "tcp"
        case let other: return other
        }
    }
}
