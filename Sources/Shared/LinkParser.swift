import Foundation

/// Разбор содержимого подписки Remnawave: либо Xray JSON (панель отдаёт его,
/// когда настроены роутинг и балансировщики), либо base64-список ссылок,
/// либо ссылки построчно (vless://, vmess://, trojan://, ss://).
enum LinkParser {

    static func parseSubscriptionContent(_ content: String) -> [ProxyProfile] {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("[") || text.hasPrefix("{") {
            let fromJson = parseXrayJsonSubscription(text)
            if !fromJson.isEmpty { return fromJson }
        }

        let looksLikeLinks = ["vless://", "vmess://", "trojan://", "ss://"]
            .contains { text.hasPrefix($0) }
        let decoded = looksLikeLinks ? text : (decodeBase64(text) ?? text)

        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            let fromJson = parseXrayJsonSubscription(trimmed)
            if !fromJson.isEmpty { return fromJson }
        }

        return decoded
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(parseLink)
    }

    // MARK: - Xray JSON

    /// Каждый элемент — полный конфиг Xray (remarks, outbounds, routing,
    /// balancers…). Сохраняем конфиг целиком; имя, адрес и протокол достаём
    /// из первого прокси-аутбаунда только для показа в списке серверов.
    static func parseXrayJsonSubscription(_ text: String) -> [ProxyProfile] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        let configs: [[String: Any]]
        if let array = root as? [Any] {
            configs = array.compactMap { $0 as? [String: Any] }
        } else if let object = root as? [String: Any], object["outbounds"] != nil {
            configs = [object]
        } else {
            configs = []
        }

        return configs.enumerated().compactMap { index, config in
            guard let outbounds = config["outbounds"] as? [Any] else { return nil }

            var proxyProtocol = ProxyProtocol.vless
            var address = ""
            var port = 443

            for outbound in outbounds {
                guard let object = outbound as? [String: Any],
                      let proto = object["protocol"] as? String,
                      let parsed = ProxyProtocol(rawValue: proto) else { continue }
                proxyProtocol = parsed
                let settings = object["settings"] as? [String: Any]
                let server = (settings?["vnext"] as? [Any])?.first
                    ?? (settings?["servers"] as? [Any])?.first
                if let server = server as? [String: Any] {
                    address = server["address"] as? String ?? address
                    port = intValue(server["port"]) ?? port
                }
                break
            }

            let remarks = (config["remarks"] as? String)?
                .trimmingCharacters(in: .whitespaces)
            let name = (remarks?.isEmpty == false ? remarks! : nil)
                ?? (address.isEmpty ? "Конфиг \(index + 1)" : address)

            guard let raw = try? JSONSerialization.data(withJSONObject: config),
                  let rawConfig = String(data: raw, encoding: .utf8) else { return nil }

            return ProxyProfile(
                proxyProtocol: proxyProtocol,
                name: name,
                address: address.isEmpty ? "-" : address,
                port: port,
                userId: "",
                rawConfig: rawConfig
            )
        }
    }

    // MARK: - Ссылки

    static func parseLink(_ link: String) -> ProxyProfile? {
        if link.hasPrefix("vless://") { return parseVless(link) }
        if link.hasPrefix("trojan://") { return parseTrojan(link) }
        if link.hasPrefix("vmess://") { return parseVmess(link) }
        if link.hasPrefix("ss://") { return parseShadowsocks(link) }
        return nil
    }

    private static func parseVless(_ link: String) -> ProxyProfile? {
        guard let components = URLComponents(string: link),
              let host = components.host,
              let userId = components.user, !userId.isEmpty else { return nil }
        let q = query(of: components)
        return ProxyProfile(
            proxyProtocol: .vless,
            name: name(of: components, fallback: host),
            address: host,
            port: components.port ?? 443,
            userId: userId,
            flow: q["flow"]?.nilIfBlank,
            encryption: q["encryption"] ?? "none",
            network: q["type"] ?? "tcp",
            security: q["security"] ?? "none",
            sni: q["sni"],
            alpn: q["alpn"],
            fingerprint: q["fp"],
            allowInsecure: q["allowInsecure"] == "1" || q["allowInsecure"] == "true",
            publicKey: q["pbk"],
            shortId: q["sid"],
            spiderX: q["spx"],
            host: q["host"],
            path: q["path"],
            serviceName: q["serviceName"],
            grpcMultiMode: q["mode"] == "multi",
            headerType: q["headerType"]
        )
    }

    private static func parseTrojan(_ link: String) -> ProxyProfile? {
        guard let components = URLComponents(string: link),
              let host = components.host,
              let password = components.user, !password.isEmpty else { return nil }
        let q = query(of: components)
        return ProxyProfile(
            proxyProtocol: .trojan,
            name: name(of: components, fallback: host),
            address: host,
            port: components.port ?? 443,
            userId: password.removingPercentEncoding ?? password,
            network: q["type"] ?? "tcp",
            security: q["security"] ?? "tls",
            sni: q["sni"],
            alpn: q["alpn"],
            fingerprint: q["fp"],
            allowInsecure: q["allowInsecure"] == "1" || q["allowInsecure"] == "true",
            host: q["host"],
            path: q["path"],
            serviceName: q["serviceName"],
            grpcMultiMode: q["mode"] == "multi"
        )
    }

    private static func parseVmess(_ link: String) -> ProxyProfile? {
        let payload = String(link.dropFirst("vmess://".count))
        guard let decoded = decodeBase64(payload),
              let data = decoded.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func str(_ key: String) -> String? {
            if let value = object[key] as? String { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
            return nil
        }
        guard let address = str("add"), let userId = str("id") else { return nil }

        let network = str("net") ?? "tcp"
        return ProxyProfile(
            proxyProtocol: .vmess,
            name: str("ps") ?? address,
            address: address,
            port: Int(str("port") ?? "") ?? 443,
            userId: userId,
            network: network,
            security: str("tls") == "tls" ? "tls" : "none",
            sni: str("sni")?.nilIfBlank,
            alpn: str("alpn")?.nilIfBlank,
            fingerprint: str("fp")?.nilIfBlank,
            host: str("host")?.nilIfBlank,
            path: str("path")?.nilIfBlank,
            serviceName: network == "grpc" ? str("path")?.nilIfBlank : nil,
            headerType: str("type").flatMap { $0 == "none" ? nil : $0.nilIfBlank },
            vmessSecurity: str("scy") ?? "auto"
        )
    }

    private static func parseShadowsocks(_ link: String) -> ProxyProfile? {
        // Форма 1: ss://base64(method:password)@host:port#name
        if let components = URLComponents(string: link),
           let host = components.host,
           let userInfo = components.user {
            let plain = decodeBase64(padBase64(userInfo)) ?? userInfo
            let parts = plain.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return ProxyProfile(
                    proxyProtocol: .shadowsocks,
                    name: name(of: components, fallback: host),
                    address: host,
                    port: components.port ?? 8388,
                    userId: parts[1],
                    encryption: parts[0]
                )
            }
        }

        // Форма 2: ss://base64(method:password@host:port)#name
        let withoutScheme = String(link.dropFirst("ss://".count))
        let body = withoutScheme.components(separatedBy: "#").first ?? withoutScheme
        guard let decoded = decodeBase64(padBase64(body)) else { return nil }

        let pattern = #"^(.+?):(.+)@(.+):(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: decoded,
                range: NSRange(decoded.startIndex..., in: decoded)
              ),
              match.numberOfRanges == 5
        else { return nil }

        func group(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: decoded) else { return "" }
            return String(decoded[range])
        }

        let host = group(3)
        let fragment = withoutScheme.components(separatedBy: "#").dropFirst().first
        let name = fragment?.removingPercentEncoding?.nilIfBlank ?? host

        return ProxyProfile(
            proxyProtocol: .shadowsocks,
            name: name,
            address: host,
            port: Int(group(4)) ?? 8388,
            userId: group(2),
            encryption: group(1)
        )
    }

    // MARK: - Вспомогательное

    private static func query(of components: URLComponents) -> [String: String] {
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private static func name(of components: URLComponents, fallback: String) -> String {
        components.fragment?.nilIfBlank ?? fallback
    }

    private static func decodeBase64(_ text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let data = Data(base64Encoded: padBase64(cleaned)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func padBase64(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = cleaned.count % 4
        return remainder == 0 ? cleaned : cleaned + String(repeating: "=", count: 4 - remainder)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespaces).isEmpty ? nil : self
    }
}
