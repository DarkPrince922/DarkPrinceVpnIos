import Foundation
import UIKit

struct TariffOffer: Identifiable, Equatable {
    let id: Int64
    let name: String
    let description: String?
    let periods: [PeriodPrice]
    let trafficLimitGb: Int?
    let deviceLimit: Int?
}

struct PeriodPrice: Equatable, Hashable {
    let days: Int
    let priceKopeks: Int64
}

struct DevicesInfo: Equatable {
    var deviceLimit: Int?
    var connectedCount: Int?
    var pricePerDeviceKopeks: Int64?
    var maxDeviceLimit: Int?
    var purchaseAvailable: Bool
    var reduceAvailable: Bool
}

struct TrafficPackage: Equatable, Hashable {
    let gb: Int
    let priceKopeks: Int64
}

final class SubscriptionRepository {

    static let shared = SubscriptionRepository()

    private let api = ApiClient.shared
    private let store = SharedStore.shared

    private init() {}

    private var isLoggedIn: Bool { store.isLoggedIn }

    var ownHwid: String { store.hwid }

    // MARK: - Подписки

    func status() async throws -> SubscriptionStatusResponse {
        try await api.get("cabinet/subscription")
    }

    /// Список подписок пользователя; пусто без аккаунта и без мультитарифа.
    func subscriptions() async -> [SubscriptionListItem] {
        guard isLoggedIn else { return [] }
        do {
            let response: SubscriptionsListResponse = try await api.get("cabinet/subscriptions")
            return response.subscriptions
        } catch {
            return []
        }
    }

    func selectSubscription(id: Int64?) {
        // данные каждой подписки лежат отдельно, поэтому ничего не удаляем:
        // серверы и выбранный узел прошлой подписки остаются на месте
        store.selectedSubscriptionId = id
    }

    // MARK: - Гостевой доступ

    /// Разбирает ссылку, полученную от владельца подписки: принимаем и прямую
    /// ссылку Remnawave, и наш deep link darkprincevpn://sub?url=…
    func parseSharedSubscription(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.lowercased().hasPrefix("darkprincevpn://") {
            let components = URLComponents(string: text)
            if let url = components?.queryItems?.first(where: { $0.name == "url" })?.value {
                return url.hasPrefix("http") ? url : nil
            }
            return nil
        }
        let lowered = text.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return text }
        return nil
    }

    /// Включает гостевой режим по ссылке подписки и сразу проверяет её.
    func activateGuestSubscription(_ rawLink: String) async -> String? {
        guard let url = parseSharedSubscription(rawLink) else {
            return "Ссылка не распознана. Нужна ссылка на подписку или QR из приложения владельца."
        }
        store.guestSubUrl = url
        do {
            let (servers, _) = try await downloadSubscription(subId: nil, url: url)
            if servers.isEmpty {
                store.guestSubUrl = nil
                return "По ссылке не нашлось серверов. Проверьте, что подписка активна."
            }
            return nil
        } catch {
            store.guestSubUrl = nil
            return "Не удалось загрузить подписку: \(error.localizedDescription)"
        }
    }

    func exitGuestMode() {
        store.guestSubUrl = nil
        store.setServersRaw(nil, for: nil)
    }

    // MARK: - Серверы

    /// Гостевая ссылка — запасной вариант: пока у зарегистрировавшегося гостя
    /// нет своей подписки, он продолжает пользоваться той, которой с ним
    /// поделились, и не остаётся без VPN во время оплаты.
    func resolveSubscriptionUrl() async -> String? {
        guard isLoggedIn else { return store.guestSubUrl }
        return await ownSubscriptionUrl() ?? store.guestSubUrl
    }

    private func ownSubscriptionUrl() async -> String? {
        let selectedId = store.selectedSubscriptionId
        if let selectedId {
            let fromList = await subscriptions()
                .first { $0.id == selectedId }?
                .subscriptionUrl
            if let fromList {
                store.setSubUrl(fromList, for: selectedId)
                return fromList
            }
            if let cached = store.subUrl(for: selectedId) { return cached }
        }

        // `??` не пропускает через себя await, поэтому запасной запрос делаем явно
        let link: ConnectionLinkResponse? = try? await api.get("cabinet/subscription/connection-link")
        var fromServer = link?.subscriptionUrl
        if fromServer == nil {
            fromServer = try? await status().subscriptionUrl
        }
        let url = fromServer ?? store.subUrl(for: nil)
        if let url { store.setSubUrl(url, for: nil) }
        return url
    }

    func cachedServers(for subId: Int64?) -> ([ProxyProfile], SubscriptionUserInfo?)? {
        guard let raw = store.serversRaw(for: subId), !raw.isEmpty else { return nil }
        let profiles = LinkParser.parseSubscriptionContent(raw)
        guard !profiles.isEmpty else { return nil }
        return (profiles, store.userInfo(for: subId))
    }

    func fetchServers(forceRefresh: Bool = false) async throws -> ([ProxyProfile], SubscriptionUserInfo?) {
        let subId = store.selectedSubscriptionId
        if !forceRefresh, let cached = cachedServers(for: subId) { return cached }

        do {
            guard let url = await resolveSubscriptionUrl() else {
                throw ApiError.network("Нет активной подписки")
            }
            let result = try await downloadSubscription(subId: subId, url: url)
            // своя подписка заработала — чужую отпускаем, чтобы не занимать
            // место в лимите устройств владельца
            if let guestUrl = store.guestSubUrl, url != guestUrl, !result.0.isEmpty {
                store.guestSubUrl = nil
            }
            return result
        } catch {
            // сеть недоступна — работаем с сохранённой копией подписки
            if let cached = cachedServers(for: subId) { return cached }
            throw error
        }
    }

    /// Догружает серверы для всех подписок, чтобы переключение было мгновенным
    /// и работало без сети.
    func prefetchAllSubscriptions() async {
        for sub in await subscriptions() {
            guard let url = sub.subscriptionUrl else { continue }
            _ = try? await downloadSubscription(subId: sub.id, url: url)
        }
    }

    /// Скачивает подписку Remnawave и складывает результат в кэш.
    ///
    /// HWID-заголовки нужны панели, чтобы считать устройства и применять лимит
    /// из тарифа; без `x-hwid` панель с включённым лимитом отдаёт 404.
    /// Устройство регистрируется именно здесь — в момент загрузки подписки,
    /// а не при подключении VPN.
    @discardableResult
    func downloadSubscription(
        subId: Int64?,
        url: String
    ) async throws -> ([ProxyProfile], SubscriptionUserInfo?) {
        guard let requestUrl = URL(string: url) else {
            throw ApiError.network("Некорректная ссылка подписки")
        }
        let device = await deviceInfo()
        var request = URLRequest(url: requestUrl)
        request.setValue("v2rayNG/1.10.7", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.setValue(store.hwid, forHTTPHeaderField: "x-hwid")
        request.setValue("iOS", forHTTPHeaderField: "x-device-os")
        request.setValue(device.systemVersion, forHTTPHeaderField: "x-ver-os")
        request.setValue(device.model, forHTTPHeaderField: "x-device-model")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError.network("Неожиданный ответ сервера")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiError.http(http.statusCode, "Подписка недоступна (HTTP \(http.statusCode))")
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        let profiles = LinkParser.parseSubscriptionContent(body)
        if !profiles.isEmpty { store.setServersRaw(body, for: subId) }

        var userInfo: SubscriptionUserInfo?
        if let header = http.value(forHTTPHeaderField: "subscription-userinfo") {
            userInfo = parseUserInfo(header)
            store.setUserInfo(userInfo, for: subId)
        }
        return (profiles, userInfo)
    }

    private func parseUserInfo(_ header: String) -> SubscriptionUserInfo {
        var values: [String: Int64] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let value = Int64(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = value
        }
        return SubscriptionUserInfo(
            uploadBytes: values["upload"],
            downloadBytes: values["download"],
            totalBytes: values["total"],
            expireUnix: values["expire"]
        )
    }

    /// UIDevice живёт на главном потоке, поэтому данные устройства собираем
    /// одним заходом и дальше работаем с обычными строками.
    @MainActor
    private func deviceInfo() -> (model: String, systemVersion: String) {
        let device = UIDevice.current
        return ("\(device.model) \(device.name)", device.systemVersion)
    }

    // MARK: - Покупка и продление

    func trialInfo() async -> TrialInfoResponse? {
        try? await api.get("cabinet/subscription/trial")
    }

    func activateTrial() async -> Bool {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/subscription/trial",
                body: EmptyBody()
            )
            return true
        } catch {
            return false
        }
    }

    /// Адаптивно разбирает purchase-options: ищет массив тарифов в известных полях.
    func tariffs() async -> [TariffOffer] {
        guard let root: JSONValue = try? await api.get("cabinet/subscription/purchase-options") else {
            return []
        }
        var arrays: [[JSONValue]] = []
        func collect(_ value: JSONValue, depth: Int) {
            guard depth <= 3 else { return }
            if let array = value.arrayValue {
                arrays.append(array)
                return
            }
            for key in ["tariffs", "items", "options", "plans"] {
                if let nested = value[key] { collect(nested, depth: depth + 1) }
            }
        }
        collect(root, depth: 0)

        var offers: [TariffOffer] = []
        for array in arrays {
            for item in array {
                guard let id = item["id"]?.int64Value else { continue }
                let periods = parsePeriods(item)
                guard !periods.isEmpty else { continue }
                offers.append(
                    TariffOffer(
                        id: id,
                        name: item["name"]?.stringValue ?? "Тариф \(id)",
                        description: item["description"]?.stringValue,
                        periods: periods,
                        trafficLimitGb: item["traffic_limit_gb"]?.intValue
                            ?? item["trafficLimitGb"]?.intValue,
                        deviceLimit: item["device_limit"]?.intValue
                            ?? item["deviceLimit"]?.intValue
                    )
                )
            }
        }
        var seen = Set<Int64>()
        return offers.filter { seen.insert($0.id).inserted }
    }

    private func parsePeriods(_ item: JSONValue) -> [PeriodPrice] {
        let element = item["period_prices"] ?? item["periods"] ?? item["prices"]
        guard let array = element?.arrayValue else { return [] }
        return array.compactMap { period in
            guard let days = period["days"]?.intValue ?? period["period_days"]?.intValue,
                  let price = period["price_kopeks"]?.int64Value ?? period["price"]?.int64Value
            else { return nil }
            return PeriodPrice(days: days, priceKopeks: price)
        }.sorted { $0.days < $1.days }
    }

    func purchaseTariff(tariffId: Int64, periodDays: Int) async -> String? {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/subscription/purchase-tariff",
                body: PurchaseTariffRequest(tariffId: tariffId, periodDays: periodDays)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func renewalOptions() async -> [PeriodPrice] {
        guard let root: JSONValue = try? await api.get("cabinet/subscription/renewal-options") else {
            return []
        }
        let array = root.arrayValue
            ?? root["options"]?.arrayValue
            ?? root["items"]?.arrayValue
            ?? []
        return array.compactMap { item in
            guard let days = item["period_days"]?.intValue ?? item["days"]?.intValue,
                  let price = item["price_kopeks"]?.int64Value ?? item["price"]?.int64Value
            else { return nil }
            return PeriodPrice(days: days, priceKopeks: price)
        }.sorted { $0.days < $1.days }
    }

    func renew(periodDays: Int) async -> String? {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/subscription/renew",
                body: RenewRequest(periodDays: periodDays)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Устройства

    private func subscriptionQuery(_ id: Int64?) -> [String: String?] {
        ["subscription_id": id.map(String.init)]
    }

    func devicesInfo(subscriptionId: Int64? = nil) async -> DevicesInfo {
        var limit: Int?
        var connected: Int?

        if let devices: JSONValue = try? await api.get(
            "cabinet/subscription/devices",
            query: subscriptionQuery(subscriptionId)
        ) {
            limit = devices["device_limit"]?.intValue
            connected = devices["total"]?.intValue ?? devices["devices"]?.arrayValue?.count
        }

        var pricePerDevice: Int64?
        var maxLimit: Int?
        var purchaseAvailable = false
        var priceQuery = subscriptionQuery(subscriptionId)
        priceQuery["devices"] = "1"
        if let price: JSONValue = try? await api.get(
            "cabinet/subscription/devices/price",
            query: priceQuery
        ) {
            purchaseAvailable = price["available"]?.boolValue ?? true
            pricePerDevice = price["price_per_device_kopeks"]?.int64Value
            maxLimit = price["max_device_limit"]?.intValue
            if limit == nil { limit = price["current_device_limit"]?.intValue }
        }

        var reduceAvailable = false
        if let reduction: JSONValue = try? await api.get(
            "cabinet/subscription/devices/reduction-info",
            query: subscriptionQuery(subscriptionId)
        ) {
            reduceAvailable = reduction["available"]?.boolValue ?? false
            if limit == nil { limit = reduction["current_device_limit"]?.intValue }
            if connected == nil { connected = reduction["connected_devices_count"]?.intValue }
        }

        return DevicesInfo(
            deviceLimit: limit,
            connectedCount: connected,
            pricePerDeviceKopeks: pricePerDevice,
            maxDeviceLimit: maxLimit,
            purchaseAvailable: purchaseAvailable && pricePerDevice != nil,
            reduceAvailable: reduceAvailable
        )
    }

    func devicesList(subscriptionId: Int64? = nil) async -> [DeviceDto] {
        do {
            let response: DevicesListResponse = try await api.get(
                "cabinet/subscription/devices",
                query: subscriptionQuery(subscriptionId)
            )
            return response.devices
        } catch {
            return []
        }
    }

    func deleteDevice(hwid: String, subscriptionId: Int64? = nil) async -> String? {
        do {
            let _: EmptyResponse = try await api.delete(
                "cabinet/subscription/devices/\(hwid)",
                query: subscriptionQuery(subscriptionId)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteAllDevices(subscriptionId: Int64? = nil) async -> String? {
        do {
            let _: EmptyResponse = try await api.delete(
                "cabinet/subscription/devices",
                query: subscriptionQuery(subscriptionId)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func renameDevice(hwid: String, name: String, subscriptionId: Int64? = nil) async -> String? {
        do {
            let _: EmptyResponse = try await api.patch(
                "cabinet/subscription/devices/\(hwid)/name",
                body: RenameDeviceRequest(name: name),
                query: subscriptionQuery(subscriptionId)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func buyDevices(count: Int, subscriptionId: Int64? = nil) async -> String? {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/subscription/devices/purchase",
                body: DevicesPurchaseRequest(devices: count),
                query: subscriptionQuery(subscriptionId)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func reduceDevices(newLimit: Int, subscriptionId: Int64? = nil) async -> String? {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/subscription/devices/reduce",
                body: ReduceDevicesRequest(newDeviceLimit: newLimit),
                query: subscriptionQuery(subscriptionId)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Трафик

    func trafficPackages() async -> [TrafficPackage] {
        guard let root: JSONValue = try? await api.get("cabinet/subscription/traffic-packages") else {
            return []
        }
        let array = root.arrayValue
            ?? root["packages"]?.arrayValue
            ?? root["items"]?.arrayValue
            ?? root["traffic_packages"]?.arrayValue
            ?? []
        return array.compactMap { item in
            guard let gb = item["gb"]?.intValue ?? item["traffic_gb"]?.intValue,
                  let price = item["price_kopeks"]?.int64Value ?? item["price"]?.int64Value
            else { return nil }
            return TrafficPackage(gb: gb, priceKopeks: price)
        }.sorted { $0.gb < $1.gb }
    }

    func buyTraffic(gb: Int) async -> String? {
        do {
            let _: EmptyResponse = try await api.post(
                "cabinet/subscription/traffic",
                body: TrafficPurchaseRequest(gb: gb)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
