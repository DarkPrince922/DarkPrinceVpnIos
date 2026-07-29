import Foundation

// Поля кабинета приходят в snake_case; ключи не переписываем руками —
// декодер настроен на .convertFromSnakeCase.

// MARK: - Авторизация

struct DeepLinkRequestResponse: Decodable {
    let token: String
    let botUsername: String?
    let expiresIn: Int?
}

struct DeepLinkPollRequest: Encodable {
    let token: String
}

struct EmailLoginRequest: Encodable {
    let email: String
    let password: String
}

struct EmailRegisterRequest: Encodable {
    let email: String
    let password: String
    var firstName: String?
    var language: String? = "ru"
    var referralCode: String?
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct LogoutRequest: Encodable {
    let refreshToken: String
}

struct ForgotPasswordRequest: Encodable {
    let email: String
}

struct UserDto: Codable, Equatable {
    var id: Int64?
    var telegramId: Int64?
    var email: String?
    var username: String?
    var firstName: String?
    var lastName: String?
    var balanceKopeks: Int64?
    var language: String?

    var displayName: String {
        if let email, !email.isEmpty { return email }
        if let username, !username.isEmpty { return "@\(username)" }
        if let telegramId { return "Telegram ID: \(telegramId)" }
        return "—"
    }
}

struct AuthResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var tokenType: String?
    var expiresIn: Int?
    var user: UserDto?
    /// Регистрация может вернуть просьбу подтвердить почту вместо токенов.
    var message: String?
    var requiresEmailVerification: Bool?
}

// MARK: - Подписка

struct SubscriptionStatusResponse: Decodable, Equatable {
    var id: Int64?
    var status: String?
    var isTrial: Bool?
    var isActive: Bool?
    var endDate: String?
    var daysLeft: Int?
    var trafficUsedGb: Double?
    var trafficLimitGb: Double?
    var deviceLimit: Int?
    var subscriptionUrl: String?
    var tariffName: String?
    var autopayEnabled: Bool?
    var actualStatus: String?
}

struct SubscriptionListItem: Decodable, Equatable, Identifiable {
    let id: Int64
    var status: String?
    var tariffId: Int64?
    var tariffName: String?
    var trafficLimitGb: Double?
    var trafficUsedGb: Double?
    var deviceLimit: Int?
    var endDate: String?
    var subscriptionUrl: String?
    var isTrial: Bool?
    var autopayEnabled: Bool?

    var displayName: String {
        if let tariffName, !tariffName.isEmpty { return tariffName }
        return isTrial == true ? "Пробная подписка" : "Подписка #\(id)"
    }

    var isActive: Bool {
        guard let status = status?.lowercased() else { return false }
        return ["active", "trial", "активна"].contains(status)
    }
}

struct SubscriptionsListResponse: Decodable {
    var subscriptions: [SubscriptionListItem] = []
    var multiTariffEnabled: Bool = false
}

struct ConnectionLinkResponse: Decodable {
    var subscriptionUrl: String?
    var happSchemeLink: String?
}

struct TrialInfoResponse: Decodable {
    var available: Bool?
    var isAvailable: Bool?
    var durationDays: Int?
    var message: String?

    var offered: Bool { available ?? isAvailable ?? false }
}

struct PurchaseTariffRequest: Encodable {
    let tariffId: Int64
    let periodDays: Int
    var trafficGb: Int?
}

struct RenewRequest: Encodable {
    let periodDays: Int
}

struct DeviceDto: Decodable, Equatable, Identifiable {
    let hwid: String
    var platform: String?
    var deviceModel: String?
    var localName: String?
    var createdAt: String?

    var id: String { hwid }

    var title: String {
        for candidate in [localName, deviceModel, platform] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return "Устройство"
    }

    var subtitle: String? {
        let parts = [platform, deviceModel]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != title }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct DevicesListResponse: Decodable {
    var devices: [DeviceDto] = []
    var total: Int?
    var deviceLimit: Int?
}

struct RenameDeviceRequest: Encodable {
    let name: String
}

struct DevicesPurchaseRequest: Encodable {
    let devices: Int
}

struct ReduceDevicesRequest: Encodable {
    let newDeviceLimit: Int
}

struct TrafficPurchaseRequest: Encodable {
    let gb: Int
}

// MARK: - Баланс и оплата

struct BalanceResponse: Decodable {
    var balanceKopeks: Int64?
    var balanceRubles: Double?
    var currency: String?

    var kopeks: Int64 {
        balanceKopeks ?? balanceRubles.map { Int64(($0 * 100).rounded()) } ?? 0
    }
}

struct TopupRequest: Encodable {
    let amountKopeks: Int64
    let paymentMethod: String
    var paymentOption: String?
    var language: String? = "ru"
}

struct TopupResponse: Decodable {
    var paymentId: String?
    var paymentUrl: String?
    var amountKopeks: Int64?
    var status: String?
    var message: String?
}

struct TransactionDto: Decodable, Identifiable {
    var id: Int64?
    var type: String?
    var amountKopeks: Int64?
    var description: String?
    var createdAt: String?
    var status: String?
}

struct TransactionsResponse: Decodable {
    var items: [TransactionDto]?
    var transactions: [TransactionDto]?
    var total: Int?
    var page: Int?

    var list: [TransactionDto] { items ?? transactions ?? [] }
}

// MARK: - Рефералка и промокоды

struct ReferralInfoResponse: Decodable {
    var referralCode: String?
    var referralLink: String?
    var botReferralLink: String?
    var totalReferrals: Int?
    var activeReferrals: Int?
    var totalEarningsKopeks: Int64?
    var availableBalanceKopeks: Int64?
    var commissionPercent: Double?

    var shareLink: String? { botReferralLink ?? referralLink }
}

struct PromoActivateRequest: Encodable {
    let code: String
}

struct PromoActivateResponse: Decodable {
    var success: Bool?
    var message: String?
    var bonusDescription: String?
}

// MARK: - Разбор ответов переменной формы

/// Часть эндпоинтов кабинета (тарифы, пакеты трафика, цены на устройства)
/// отвечает по-разному в разных версиях бота, поэтому такие ответы держим
/// как сырой JSON и разбираем адаптивно — как и в Android-приложении.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case .number(let value): return Int64(value)
        case .string(let value): return Int64(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }
}
