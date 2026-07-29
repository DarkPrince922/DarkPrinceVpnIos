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
}
