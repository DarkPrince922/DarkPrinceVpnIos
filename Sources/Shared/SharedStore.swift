import Foundation

enum AppGroup {
    static let identifier = "group.ru.darkprince.vpn"
    static let keychainService = "ru.darkprince.vpn"

    static let tunnelBundleIdentifier = "ru.darkprince.vpn.tunnel"
    /// Адрес кабинета по умолчанию — клиенту вводить ничего не нужно.
    static let defaultBaseUrl = "https://cabinet.darkprincepanel.ru"
}

/// Настройки и кэш подписки. Лежат в контейнере группы, потому что читать их
/// должно и приложение, и сетевое расширение.
///
/// Данные каждой подписки хранятся отдельно (ключ с её id), поэтому
/// переключение между тарифами ничего не теряет и работает без сети.
final class SharedStore {

    static let shared = SharedStore()

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private enum Key {
        static let baseUrl = "base_url"
        static let userJson = "user_json"
        static let selectedSubscription = "selected_subscription"
        static let guestSubUrl = "guest_sub_url"
        static let hwid = "hwid"
        static let activeProfile = "active_profile"
        static let lastExpiryNotifyDay = "last_expiry_notify_day"

        static func servers(_ id: Int64?) -> String { "servers_raw_\(id.map(String.init) ?? "default")" }
        static func subUrl(_ id: Int64?) -> String { "sub_url_\(id.map(String.init) ?? "default")" }
        static func userInfo(_ id: Int64?) -> String { "sub_userinfo_\(id.map(String.init) ?? "default")" }
        static func selectedServer(_ id: Int64?) -> String { "selected_server_\(id.map(String.init) ?? "default")" }
    }

    // MARK: - Кабинет

    var baseUrl: String {
        get { defaults.string(forKey: Key.baseUrl) ?? AppGroup.defaultBaseUrl }
        set { defaults.set(newValue.trimmedUrl, forKey: Key.baseUrl) }
    }

    var userJson: String? {
        get { defaults.string(forKey: Key.userJson) }
        set { defaults.set(newValue, forKey: Key.userJson) }
    }

    /// Идентификатор устройства для учёта в панели. Живёт в Keychain, потому
    /// что на iOS нет стабильного идентификатора железа, а `identifierForVendor`
    /// сбрасывается при удалении приложения — панель считала бы каждую
    /// переустановку новым устройством и съедала лимит.
    var hwid: String {
        if let existing = Keychain.get(Key.hwid), !existing.isEmpty { return existing }
        let generated = UUID().uuidString
        Keychain.set(generated, for: Key.hwid)
        return generated
    }

    // MARK: - Подписки

    var selectedSubscriptionId: Int64? {
        get {
            let value = defaults.object(forKey: Key.selectedSubscription) as? NSNumber
            return value?.int64Value
        }
        set {
            if let newValue {
                defaults.set(NSNumber(value: newValue), forKey: Key.selectedSubscription)
            } else {
                defaults.removeObject(forKey: Key.selectedSubscription)
            }
        }
    }

    /// Подписка, полученная по QR от другого человека.
    var guestSubUrl: String? {
        get { defaults.string(forKey: Key.guestSubUrl) }
        set { defaults.set(newValue, forKey: Key.guestSubUrl) }
    }

    func serversRaw(for id: Int64?) -> String? { defaults.string(forKey: Key.servers(id)) }

    func setServersRaw(_ raw: String?, for id: Int64?) {
        defaults.set(raw, forKey: Key.servers(id))
    }

    func subUrl(for id: Int64?) -> String? { defaults.string(forKey: Key.subUrl(id)) }

    func setSubUrl(_ url: String?, for id: Int64?) {
        defaults.set(url, forKey: Key.subUrl(id))
    }

    func userInfo(for id: Int64?) -> SubscriptionUserInfo? {
        guard let raw = defaults.string(forKey: Key.userInfo(id)),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SubscriptionUserInfo.self, from: data)
    }

    func setUserInfo(_ info: SubscriptionUserInfo?, for id: Int64?) {
        guard let info, let data = try? JSONEncoder().encode(info) else {
            defaults.removeObject(forKey: Key.userInfo(id))
            return
        }
        defaults.set(String(data: data, encoding: .utf8), forKey: Key.userInfo(id))
    }

    func selectedServerIndex(for id: Int64?) -> Int {
        defaults.integer(forKey: Key.selectedServer(id))
    }

    func setSelectedServerIndex(_ index: Int, for id: Int64?) {
        defaults.set(index, forKey: Key.selectedServer(id))
    }

    var lastExpiryNotifyDay: String? {
        get { defaults.string(forKey: Key.lastExpiryNotifyDay) }
        set { defaults.set(newValue, forKey: Key.lastExpiryNotifyDay) }
    }

    // MARK: - Профиль, с которым работает расширение

    /// Расширение не ходит в сеть за подпиской: приложение кладёт сюда узел,
    /// выбранный пользователем, и расширение просто поднимает по нему туннель.
    var activeProfile: ProxyProfile? {
        get {
            guard let data = defaults.data(forKey: Key.activeProfile) else { return nil }
            return try? JSONDecoder().decode(ProxyProfile.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Key.activeProfile)
                return
            }
            defaults.set(data, forKey: Key.activeProfile)
        }
    }

    // MARK: - Сессия

    var accessToken: String? {
        get { Keychain.get("access_token") }
        set { Keychain.set(newValue, for: "access_token") }
    }

    var refreshToken: String? {
        get { Keychain.get("refresh_token") }
        set { Keychain.set(newValue, for: "refresh_token") }
    }

    var accessExpiresAt: Date? {
        get {
            let value = defaults.double(forKey: "access_expires_at")
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "access_expires_at") }
    }

    var isLoggedIn: Bool { refreshToken?.isEmpty == false }

    func clearSession() {
        accessToken = nil
        refreshToken = nil
        accessExpiresAt = nil
        userJson = nil
        defaults.removeObject(forKey: Key.servers(nil))
    }
}

struct SubscriptionUserInfo: Codable, Equatable {
    var uploadBytes: Int64?
    var downloadBytes: Int64?
    var totalBytes: Int64?
    var expireUnix: Int64?
}

// MARK: - Keychain

/// Токены держим в Keychain, а не в UserDefaults: расширение читает их через
/// общую группу доступа, а из бэкапа устройства они не утекают в открытом виде.
enum Keychain {

    static func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    /// Группу доступа намеренно не указываем: iOS возьмёт первую из
    /// entitlements, а она одинаковая у приложения и расширения. Прописать её
    /// строкой нельзя — настоящее имя группы содержит префикс команды
    /// разработчика, который известен только на этапе подписи.
    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppGroup.keychainService,
            kSecAttrAccount as String: key,
        ]
    }
}

extension String {
    var trimmedUrl: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
