import Foundation

enum ApiError: LocalizedError {
    case http(Int, String?)
    case network(String)
    case decoding(String)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .http(let code, let message):
            if let message, !message.isEmpty { return message }
            switch code {
            case 400, 422: return "Неверные данные. Проверьте введённые значения."
            case 401: return "Неверный логин или пароль."
            case 403: return "Доступ запрещён."
            case 404: return "Сервис не найден. Проверьте адрес кабинета."
            case 429: return "Слишком много попыток. Подождите немного."
            case 500...599: return "Сервер временно недоступен."
            default: return "Ошибка сервера (\(code))."
            }
        case .network:
            return "Нет соединения с сервером. Проверьте интернет."
        case .decoding:
            return "Сервер вернул неожиданный ответ."
        case .notAuthorized:
            return "Сессия истекла, войдите заново."
        }
    }
}

/// HTTP-клиент кабинета Bedolaga.
///
/// В отличие от Android, здесь не нужен отдельный прокси для запросов к
/// кабинету: когда туннель поднят, весь трафик приложения и так идёт через
/// него, поэтому заблокированный у провайдера домен кабинета открывается сам.
actor ApiClient {

    static let shared = ApiClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let store = SharedStore.shared

    /// Обновление токена идёт в одну «нитку»: без этого несколько
    /// одновременных запросов ротируют refresh-токен наперегонки и
    /// разлогинивают пользователя.
    private var refreshTask: Task<Bool, Never>?

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Публичный интерфейс

    func get<T: Decodable>(
        _ path: String,
        query: [String: String?] = [:],
        authorized: Bool = true
    ) async throws -> T {
        try await request(path, method: "GET", query: query, body: Optional<Never>.none, authorized: authorized)
    }

    @discardableResult
    func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B?,
        query: [String: String?] = [:],
        authorized: Bool = true
    ) async throws -> T {
        try await request(path, method: "POST", query: query, body: body, authorized: authorized)
    }

    @discardableResult
    func delete<T: Decodable>(
        _ path: String,
        query: [String: String?] = [:]
    ) async throws -> T {
        try await request(path, method: "DELETE", query: query, body: Optional<Never>.none, authorized: true)
    }

    @discardableResult
    func patch<T: Decodable, B: Encodable>(
        _ path: String,
        body: B?,
        query: [String: String?] = [:]
    ) async throws -> T {
        try await request(path, method: "PATCH", query: query, body: body, authorized: true)
    }

    /// Отдельный вариант для deep-link авторизации: 202 — «ещё ждём»,
    /// 410 — токен протух. Возвращаем код, чтобы вызывающий решил сам.
    func pollDeepLink(token: String) async -> (status: Int, auth: AuthResponse?) {
        do {
            let (data, response) = try await raw(
                "cabinet/auth/deeplink/poll",
                method: "POST",
                query: [:],
                body: DeepLinkPollRequest(token: token),
                authorized: false
            )
            let auth = try? decoder.decode(AuthResponse.self, from: data)
            return (response.statusCode, auth)
        } catch {
            return (0, nil)
        }
    }

    // MARK: - Транспорт

    private func request<T: Decodable, B: Encodable>(
        _ path: String,
        method: String,
        query: [String: String?],
        body: B?,
        authorized: Bool
    ) async throws -> T {
        let (data, response) = try await raw(
            path, method: method, query: query, body: body, authorized: authorized
        )

        if response.statusCode == 401, authorized {
            // токен мог протухнуть, пока запрос был в пути
            guard await refreshTokens() else { throw ApiError.notAuthorized }
            let (retryData, retryResponse) = try await raw(
                path, method: method, query: query, body: body, authorized: true
            )
            return try decode(retryData, response: retryResponse)
        }

        return try decode(data, response: response)
    }

    private func raw<B: Encodable>(
        _ path: String,
        method: String,
        query: [String: String?],
        body: B?,
        authorized: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: "\(store.baseUrl)/api/\(path)") else {
            throw ApiError.network("Некорректный адрес кабинета")
        }
        let items = query.compactMap { key, value in
            value.map { URLQueryItem(name: key, value: $0) }
        }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else {
            throw ApiError.network("Некорректный адрес кабинета")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        if authorized {
            if await ensureFreshToken(), let token = store.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ApiError.network("Неожиданный ответ сервера")
            }
            return (data, http)
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError.network(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ data: Data, response: HTTPURLResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            throw ApiError.http(response.statusCode, serverMessage(from: data))
        }
        // часть эндпоинтов отвечает пустым телом
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ApiError.decoding(error.localizedDescription)
        }
    }

    private func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["detail", "message", "error"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: - Токены

    private func ensureFreshToken() async -> Bool {
        guard store.refreshToken != nil else { return false }
        guard let expiresAt = store.accessExpiresAt else { return store.accessToken != nil }
        // обновляем заранее, чтобы не ловить 401 на каждом первом запросе
        if expiresAt.timeIntervalSinceNow > 60 { return true }
        return await refreshTokens()
    }

    private func refreshTokens() async -> Bool {
        if let existing = refreshTask { return await existing.value }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performRefresh()
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> Bool {
        guard let refresh = store.refreshToken else { return false }
        do {
            let (data, response) = try await raw(
                "cabinet/auth/refresh",
                method: "POST",
                query: [:],
                body: RefreshRequest(refreshToken: refresh),
                authorized: false
            )
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 401 { store.clearSession() }
                return false
            }
            let auth = try decoder.decode(AuthResponse.self, from: data)
            guard let access = auth.accessToken else { return false }
            store.accessToken = access
            if let newRefresh = auth.refreshToken { store.refreshToken = newRefresh }
            store.accessExpiresAt = auth.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            return true
        } catch {
            return false
        }
    }
}

struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
