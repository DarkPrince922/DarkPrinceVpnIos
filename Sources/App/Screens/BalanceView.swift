import SwiftUI

@MainActor
final class BalanceModel: ObservableObject {
    @Published var balanceKopeks: Int64 = 0
    @Published var methods: [PaymentMethod] = []
    @Published var transactions: [TransactionDto] = []
    @Published var loading = false
    @Published var error: String?
    @Published var info: String?
    @Published var paymentUrl: URL?

    private let repo = BalanceRepository.shared
    private var watchTask: Task<Void, Never>?

    func refresh() async {
        loading = true
        async let balanceTask = repo.balance()
        async let methodsTask = repo.paymentMethods()
        async let transactionsTask = repo.transactions()
        if let value = await balanceTask { balanceKopeks = value }
        methods = await methodsTask.filter(\.enabled)
        transactions = await transactionsTask
        loading = false
    }

    func topup(rubles: Int, method: PaymentMethod) async {
        error = nil
        info = nil
        let result = await repo.topup(amountKopeks: Int64(rubles) * 100, method: method.id)
        switch result {
        case .created(let response):
            if let urlString = response.paymentUrl, let url = URL(string: urlString) {
                paymentUrl = url
                startPaymentWatch()
            } else {
                info = response.message ?? "Платёж создан"
                startPaymentWatch()
            }
        case .failed(let message):
            error = message
        }
    }

    /// После ухода на оплату баланс подтягиваем сами: сначала часто, потом
    /// пореже — чтобы деньги появлялись без ручного обновления экрана.
    func startPaymentWatch() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            let before = self.balanceKopeks
            for delay in Array(repeating: 5, count: 6) + Array(repeating: 15, count: 8) {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                if Task.isCancelled { return }
                if let value = await self.repo.balance() {
                    self.balanceKopeks = value
                    if value != before {
                        self.info = "Баланс пополнен"
                        self.transactions = await self.repo.transactions()
                        return
                    }
                }
            }
        }
    }

    func activatePromocode(_ code: String) async {
        error = nil
        info = nil
        let result = await repo.activatePromocode(code)
        if result.success {
            info = result.message
            await refresh()
        } else {
            error = result.message
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }
}

struct BalanceView: View {
    @StateObject private var model = BalanceModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var amount = "500"
    @State private var promocode = ""
    @State private var selectedMethod: PaymentMethod?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        balanceCard
                        if let info = model.info { banner(info, color: Theme.goldSoft) }
                        if let error = model.error { banner(error, color: .red) }
                        topupCard
                        promocodeCard
                        if !model.transactions.isEmpty { historyCard }
                    }
                    .padding(16)
                }
                .refreshable { await model.refresh() }
            }
            .navigationTitle("Баланс")
        }
        .task { await model.refresh() }
        .onChange(of: model.paymentUrl) { url in
            guard let url else { return }
            openURL(url)
            model.paymentUrl = nil
        }
        .onChange(of: scenePhase) { phase in
            // вернулись из браузера — сразу проверяем, дошли ли деньги
            if phase == .active { Task { await model.refresh() } }
        }
        .onDisappear { model.stopWatching() }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("На счету").font(.footnote).foregroundStyle(.secondary)
            Text(Format.rubles(model.balanceKopeks))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
        }
        .card()
    }

    private var topupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Пополнить").font(.headline)

            HStack {
                TextField("Сумма, ₽", text: $amount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                ForEach([300, 500, 1000], id: \.self) { preset in
                    Button("\(preset)") { amount = String(preset) }
                        .buttonStyle(.bordered)
                }
            }

            if model.methods.isEmpty {
                Text("Способы оплаты недоступны").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(model.methods) { method in
                    Button {
                        selectedMethod = method
                        guard let rubles = Int(amount), rubles > 0 else { return }
                        Task { await model.topup(rubles: rubles, method: method) }
                    } label: {
                        HStack {
                            Text(method.name)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .card()
    }

    private var promocodeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Промокод").font(.headline)
            HStack {
                TextField("Код", text: $promocode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Применить") {
                    Task { await model.activatePromocode(promocode) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(promocode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("История").font(.headline)
            ForEach(Array(model.transactions.prefix(10).enumerated()), id: \.offset) { _, item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.description ?? item.type ?? "Операция")
                            .font(.subheadline)
                        if let date = item.createdAt {
                            Text(String(date.prefix(10)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let amount = item.amountKopeks {
                        Text(Format.rubles(amount))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(amount >= 0 ? Theme.gold : .secondary)
                    }
                }
            }
        }
        .card()
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text).font(.footnote).foregroundStyle(color).card()
    }
}
