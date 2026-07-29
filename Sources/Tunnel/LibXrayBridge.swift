import Foundation
import LibXray

/// Тонкая обёртка над libXray. Библиотека принимает и возвращает JSON через
/// одну C-функцию `CGoInvoke`; память ответа выделяет Go, поэтому её
/// обязательно освобождать через `CGoFree`.
enum LibXrayBridge {

    struct InvokeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Response: Decodable {
        let success: Bool
        let error: String?
    }

    private struct PingResponse: Decodable {
        struct Payload: Decodable { let delay: Int64? }
        let success: Bool
        let error: String?
        let data: Payload?
    }

    /// Поднимает ядро с конфигом, переданным строкой: файл на диск не пишем,
    /// чтобы конфиг с ключами не оставался в контейнере.
    static func runXray(configJSON: String) throws {
        let response = try invoke(
            method: "runXrayFromJson",
            payload: ["configJSON": configJSON]
        )
        guard response.success else {
            throw InvokeError(message: response.error ?? "Не удалось запустить ядро")
        }
    }

    static func stopXray() {
        _ = try? invoke(method: "stopXray", payload: [:])
    }

    static var isRunning: Bool {
        guard let raw = call(method: "getXrayState", payload: [:]),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any]
        else { return false }
        return payload["running"] as? Bool ?? false
    }

    /// Реальная задержка через ядро — аналог «real ping» в v2rayNG.
    static func ping(configJSON: String, url: String, timeoutSeconds: Int = 5) -> Int64? {
        // ping умеет работать только с файлом, поэтому кладём конфиг во
        // временный каталог и убираем сразу после замера
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: path) }

        guard (try? configJSON.write(to: path, atomically: true, encoding: .utf8)) != nil,
              let raw = call(
                method: "ping",
                payload: [
                    "configPath": path.path,
                    "timeout": timeoutSeconds,
                    "url": url,
                ]
              ),
              let data = raw.data(using: .utf8),
              let response = try? JSONDecoder().decode(PingResponse.self, from: data),
              response.success
        else { return nil }
        return response.data?.delay
    }

    // MARK: - Транспорт

    @discardableResult
    private static func invoke(method: String, payload: [String: Any]) throws -> Response {
        guard let raw = call(method: method, payload: payload),
              let data = raw.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data)
        else { throw InvokeError(message: "Ядро вернуло неожиданный ответ") }
        return response
    }

    private static func call(method: String, payload: [String: Any]) -> String? {
        let request: [String: Any] = [
            "apiVersion": 1,
            "method": method,
            "payload": payload,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8) else { return nil }

        return json.withCString { pointer -> String? in
            guard let mutable = strdup(pointer) else { return nil }
            defer { free(mutable) }
            guard let result = CGoInvoke(mutable) else { return nil }
            defer { CGoFree(result) }
            return String(cString: result)
        }
    }
}
