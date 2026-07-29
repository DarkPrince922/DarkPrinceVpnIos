import Foundation

enum DeepLinkAuthEvent {
    /// Ссылку нужно открыть в Telegram.
    case openTelegram(telegram: URL, web: URL)
    case waiting
    case success(UserDto?)
    case failed(String)
}

final class AuthRepository {

    static let shared = AuthRepository()

    private let api = ApiClient.shared
    private let store = SharedStore.shared

    private init() {}

    var isLoggedIn: Bool { store.isLoggedIn }

    var currentUser: UserDto? {
        guard let json = store.userJson, let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(UserDto.self, from: data)
    }

    private func save(_ auth: AuthResponse) {
        if let access = auth.accessToken {
            store.accessToken = access
            store.refreshToken = auth.refreshToken
            store.accessExpiresAt = auth.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        }
        if let user = auth.user {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            if let data = try? encoder.encode(user) {
                store.userJson = String(data: data, encoding: .utf8)
            }
        }
    }

    /// Авторизация через Telegram: запрашиваем одноразовый токен, отдаём ссылку
    /// на бота (t.me/<bot>?start=webauth_<token>) и опрашиваем сервер до
    /// подтверждения в боте.
    func telegramDeepLinkAuth(onEvent: @escaping (DeepLinkAuthEvent) -> Void) async {
        let request: DeepLinkRequestResponse
        do {
            request = try await api.post(
                "cabinet/auth/deeplink/request",
                body: Optional<EmptyBody>.none,
                authorized: false
            )
        } catch {
            onEvent(.failed(error.localizedDescription))
            return
        }

        guard let bot = request.botUsername else {
            onEvent(.failed("Сервер не вернул имя бота"))
            return
        }

        let startParam = "webauth_\(request.token)"
        guard let telegram = URL(string: "tg://resolve?domain=\(bot)&start=\(startParam)"),
              let web = URL(string: "https://t.me/\(bot)?start=\(startParam)") else {
            onEvent(.failed("Не удалось собрать ссылку на бота"))
            return
        }
        onEvent(.openTelegram(telegram: telegram, web: web))

        let deadline = Date().addingTimeInterval(TimeInterval(request.expiresIn ?? 300))
        while Date() < deadline {
            if Task.isCancelled { return }
            let (status, auth) = await api.pollDeepLink(token: request.token)
            switch status {
            case 200:
                if let auth, auth.accessToken != nil {
                    save(auth)
                    onEvent(.success(auth.user))
                } else {
                    onEvent(.failed("Пустой ответ сервера"))
                }
                return
            case 410:
                onEvent(.failed("Время авторизации истекло, попробуйте ещё раз"))
                return
            default:
                onEvent(.waiting)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        onEvent(.failed("Время авторизации истекло, попробуйте ещё раз"))
    }

    /// Возвращает nil при успехе, иначе текст ошибки.
    func emailLogin(email: String, password: String) async -> String? {
        do {
            let auth: AuthResponse = try await api.post(
                "cabinet/auth/email/login",
                body: EmailLoginRequest(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                ),
                authorized: false
            )
            guard auth.accessToken != nil else { return auth.message ?? "Не удалось войти" }
            save(auth)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// При успехе без токенов сервер прислал письмо для подтверждения почты.
    func emailRegister(
        email: String,
        password: String,
        referralCode: String?
    ) async -> (success: Bool, message: String?) {
        do {
            let auth: AuthResponse = try await api.post(
                "cabinet/auth/email/register/standalone",
                body: EmailRegisterRequest(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    referralCode: referralCode?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                ),
                authorized: false
            )
            if auth.accessToken != nil {
                save(auth)
                return (true, nil)
            }
            return (true, auth.message ?? "Подтвердите e-mail по ссылке из письма, затем войдите.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    @discardableResult
    func forgotPassword(email: String) async -> Bool {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/auth/password/forgot",
                body: ForgotPasswordRequest(email: email.trimmingCharacters(in: .whitespaces)),
                authorized: false
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func me() async -> UserDto? {
        do {
            let user: UserDto = try await api.get("cabinet/auth/me")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            if let data = try? encoder.encode(user) {
                store.userJson = String(data: data, encoding: .utf8)
            }
            return user
        } catch {
            return nil
        }
    }

    func logout() async {
        if let refresh = store.refreshToken {
            let _: EmptyResponse? = try? await api.post(
                "cabinet/auth/logout",
                body: LogoutRequest(refreshToken: refresh)
            )
        }
        store.clearSession()
    }
}

struct EmptyBody: Encodable {}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
