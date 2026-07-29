import Foundation

/// Приложение общается с расширением короткими JSON-сообщениями через
/// `NETunnelProviderSession.sendProviderMessage`.
enum TunnelMessage: Codable {
    case stats
}

struct TunnelStats: Codable, Equatable {
    var uploadBytes: Int64
    var downloadBytes: Int64
    var running: Bool

    static let zero = TunnelStats(uploadBytes: 0, downloadBytes: 0, running: false)
}
