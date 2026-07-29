import Foundation

/// Итог создания платежа. Обычный `Result` не подходит: у него тип ошибки
/// должен соответствовать `Error`, а кабинет отдаёт просто текст для показа.
enum TopupResult {
    case created(TopupResponse)
    case failed(String)
}

struct PaymentMethod: Identifiable, Equatable {
    let id: String
    let name: String
    let enabled: Bool
    let minAmountKopeks: Int64?
    let maxAmountKopeks: Int64?
}

final class BalanceRepository {

    static let shared = BalanceRepository()

    private let api = ApiClient.shared

    private init() {}

    func balance() async -> Int64? {
        let response: BalanceResponse? = try? await api.get("cabinet/balance")
        return response?.kopeks
    }

    /// Способы оплаты приходят в разной форме в зависимости от версии бота.
    func paymentMethods() async -> [PaymentMethod] {
        guard let root: JSONValue = try? await api.get("cabinet/balance/payment-methods") else {
            return []
        }
        let array = root.arrayValue
            ?? root["methods"]?.arrayValue
            ?? root["items"]?.arrayValue
            ?? root["payment_methods"]?.arrayValue
            ?? []
        return array.compactMap { item in
            let id = item["method"]?.stringValue ?? item["id"]?.stringValue
            guard let id, !id.isEmpty else { return nil }
            return PaymentMethod(
                id: id,
                name: item["title"]?.stringValue ?? item["name"]?.stringValue ?? id,
                enabled: item["enabled"]?.boolValue ?? item["is_enabled"]?.boolValue ?? true,
                minAmountKopeks: item["min_amount_kopeks"]?.int64Value,
                maxAmountKopeks: item["max_amount_kopeks"]?.int64Value
            )
        }
    }

    func topup(amountKopeks: Int64, method: String) async -> TopupResult {
        do {
            let response: TopupResponse = try await api.post(
                "cabinet/balance/topup",
                body: TopupRequest(amountKopeks: amountKopeks, paymentMethod: method)
            )
            return .created(response)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func transactions() async -> [TransactionDto] {
        let response: TransactionsResponse? = try? await api.get(
            "cabinet/balance/transactions",
            query: ["page": "1", "per_page": "30"]
        )
        return response?.list ?? []
    }

    func referralInfo() async -> ReferralInfoResponse? {
        try? await api.get("cabinet/referral")
    }

    func activatePromocode(_ code: String) async -> (success: Bool, message: String) {
        do {
            let response: PromoActivateResponse = try await api.post(
                "cabinet/promocode/activate",
                body: PromoActivateRequest(code: code.trimmingCharacters(in: .whitespaces))
            )
            let text = response.bonusDescription
                ?? response.message
                ?? "Промокод активирован"
            return (response.success ?? true, text)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
