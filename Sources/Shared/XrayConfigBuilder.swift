import Foundation

/// Сборка конфигурации Xray-core: локальный SOCKS-инбаунд, аутбаунд по
/// выбранному профилю, статистика для подсчёта трафика.
enum XrayConfigBuilder {

    static let socksPort = 10808

    static func build(profile: ProxyProfile) -> String {
        if let raw = profile.rawConfig, let merged = buildFromRawConfig(raw) {
            return merged
        }
        return buildFromParsedProfile(profile)
    }

    /// Подписка в формате Xray JSON: конфиг панели используется как есть
    /// (роутинг, правила, балансировщики сохраняются). Подменяем только
    /// inbounds на локальный SOCKS и включаем статистику, если её нет.
    private static func buildFromRawConfig(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        config["inbounds"] = [socksInbound()]
        if config["stats"] == nil {
            config["stats"] = [String: Any]()
        }
        if config["policy"] == nil {
            config["policy"] = [
                "system": [
                    "statsOutboundUplink": true,
                    "statsOutboundDownlink": true,
                ],
            ]
        }
        if config["log"] == nil {
            config["log"] = ["loglevel": "warning"]
        }
        return encode(config)
    }

    /// Теги прокси-аутбаундов конфига — для опроса статистики трафика.
    static func statsTags(profile: ProxyProfile) -> [String] {
        guard let raw = profile.rawConfig,
              let data = raw.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = config["outbounds"] as? [Any]
        else { return ["proxy"] }

        let skip: Set<String> = ["freedom", "blackhole", "dns", "loopback"]
        let tags = outbounds
            .compactMap { $0 as? [String: Any] }
            .filter { object in
                guard let proto = object["protocol"] as? String else { return true }
                return !skip.contains(proto)
            }
            .compactMap { $0["tag"] as? String }
        return tags.isEmpty ? ["proxy"] : tags
    }

    private static func socksInbound() -> [String: Any] {
        [
            "tag": "socks",
            "listen": "127.0.0.1",
            "port": socksPort,
            "protocol": "socks",
            "settings": [
                "auth": "noauth",
                "udp": true,
            ],
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls"],
                "routeOnly": false,
            ],
        ]
    }

    private static func buildFromParsedProfile(_ profile: ProxyProfile) -> String {
        let config: [String: Any] = [
            "log": ["loglevel": "warning"],
            "stats": [String: Any](),
            "policy": [
                "levels": [
                    "8": [
                        "handshake": 4,
                        "connIdle": 300,
                        "uplinkOnly": 1,
                        "downlinkOnly": 1,
                    ],
                ],
                "system": [
                    "statsOutboundUplink": true,
                    "statsOutboundDownlink": true,
                ],
            ],
            "dns": ["servers": ["1.1.1.1", "8.8.8.8"]],
            "inbounds": [socksInbound()],
            "outbounds": [
                buildOutbound(profile),
                ["tag": "direct", "protocol": "freedom", "settings": [String: Any]()],
                ["tag": "block", "protocol": "blackhole", "settings": [String: Any]()],
            ],
            "routing": [
                "domainStrategy": "IPIfNonMatch",
                "rules": [
                    [
                        "type": "field",
                        "ip": [
                            "10.0.0.0/8",
                            "172.16.0.0/12",
                            "192.168.0.0/16",
                            "127.0.0.0/8",
                            "169.254.0.0/16",
                            "100.64.0.0/10",
                        ],
                        "outboundTag": "direct",
                    ],
                ],
            ],
        ]
        return encode(config) ?? "{}"
    }

    private static func buildOutbound(_ p: ProxyProfile) -> [String: Any] {
        var outbound: [String: Any] = ["tag": "proxy"]

        switch p.proxyProtocol {
        case .vless:
            var user: [String: Any] = [
                "id": p.userId,
                "encryption": p.encryption ?? "none",
                "level": 8,
            ]
            if let flow = p.flow { user["flow"] = flow }
            outbound["protocol"] = "vless"
            outbound["settings"] = [
                "vnext": [["address": p.address, "port": p.port, "users": [user]]],
            ]
        case .vmess:
            let user: [String: Any] = [
                "id": p.userId,
                "security": p.vmessSecurity,
                "alterId": 0,
                "level": 8,
            ]
            outbound["protocol"] = "vmess"
            outbound["settings"] = [
                "vnext": [["address": p.address, "port": p.port, "users": [user]]],
            ]
        case .trojan:
            outbound["protocol"] = "trojan"
            outbound["settings"] = [
                "servers": [[
                    "address": p.address,
                    "port": p.port,
                    "password": p.userId,
                    "level": 8,
                ]],
            ]
        case .shadowsocks:
            outbound["protocol"] = "shadowsocks"
            outbound["settings"] = [
                "servers": [[
                    "address": p.address,
                    "port": p.port,
                    "method": p.encryption ?? "aes-256-gcm",
                    "password": p.userId,
                    "level": 8,
                ]],
            ]
        }

        outbound["streamSettings"] = buildStreamSettings(p)
        outbound["mux"] = ["enabled": false]
        return outbound
    }

    private static func buildStreamSettings(_ p: ProxyProfile) -> [String: Any] {
        var stream: [String: Any] = [
            "network": p.network,
            "security": p.security,
        ]

        switch p.security {
        case "tls":
            var tls: [String: Any] = [
                "serverName": p.sni ?? p.host ?? p.address,
                "allowInsecure": p.allowInsecure,
            ]
            if let fingerprint = p.fingerprint { tls["fingerprint"] = fingerprint }
            if let alpn = p.alpn {
                tls["alpn"] = alpn.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
            stream["tlsSettings"] = tls
        case "reality":
            stream["realitySettings"] = [
                "serverName": p.sni ?? "",
                "fingerprint": p.fingerprint ?? "chrome",
                "publicKey": p.publicKey ?? "",
                "shortId": p.shortId ?? "",
                "spiderX": p.spiderX ?? "",
            ]
        default:
            break
        }

        switch p.network {
        case "ws":
            var ws: [String: Any] = ["path": p.path ?? "/"]
            if let host = p.host { ws["headers"] = ["Host": host] }
            stream["wsSettings"] = ws
        case "grpc":
            stream["grpcSettings"] = [
                "serviceName": p.serviceName ?? "",
                "multiMode": p.grpcMultiMode,
            ]
        case "httpupgrade":
            var settings: [String: Any] = ["path": p.path ?? "/"]
            if let host = p.host { settings["host"] = host }
            stream["httpupgradeSettings"] = settings
        case "xhttp":
            var settings: [String: Any] = ["path": p.path ?? "/"]
            if let host = p.host { settings["host"] = host }
            stream["xhttpSettings"] = settings
        case "tcp":
            if p.headerType == "http" {
                stream["tcpSettings"] = [
                    "header": [
                        "type": "http",
                        "request": [
                            "path": [p.path ?? "/"],
                            "headers": ["Host": [p.host ?? ""]],
                        ],
                    ],
                ]
            }
        default:
            break
        }

        return stream
    }

    private static func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
