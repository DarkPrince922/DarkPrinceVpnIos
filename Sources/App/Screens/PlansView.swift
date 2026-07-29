import SwiftUI

@MainActor
final class PlansModel: ObservableObject {
    @Published var tariffs: [TariffOffer] = []
    @Published var renewalOptions: [PeriodPrice] = []
    @Published var trafficPackages: [TrafficPackage] = []
    @Published var subscriptions: [SubscriptionListItem] = []
    @Published var devices: DevicesInfo?
    @Published var deviceSubscriptionId: Int64?
    @Published var loading = false
    @Published var purchasing = false
    @Published var error: String?
    @Published var info: String?

    private let repo = SubscriptionRepository.shared

    /// Тарифы, которые уже куплены: для них показываем «Продлить», а не «Купить».
    var ownedTariffIds: Set<Int64> {
        Set(subscriptions.compactMap(\.tariffId))
    }

    /// Лимит устройств показываем по каждому тарифу отдельно — иначе он
    /// «прыгает» при выборе другой подписки в блоке устройств.
    func deviceLimit(for tariff: TariffOffer) -> Int? {
        subscriptions.first { $0.tariffId == tariff.id }?.deviceLimit ?? tariff.deviceLimit
    }

    func refresh() async {
        loading = true
        async let tariffsTask = repo.tariffs()
        async let renewalTask = repo.renewalOptions()
        async let trafficTask = repo.trafficPackages()
        async let subsTask = repo.subscriptions()

        tariffs = await tariffsTask
        renewalOptions = await renewalTask
        trafficPackages = await trafficTask
        subscriptions = await subsTask

        if deviceSubscriptionId == nil {
            deviceSubscriptionId = subscriptions.first { $0.isActive }?.id ?? subscriptions.first?.id
        }
        devices = await repo.devicesInfo(subscriptionId: deviceSubscriptionId)
        loading = false
    }

    func selectDeviceSubscription(_ id: Int64) async {
        guard id != deviceSubscriptionId else { return }
        deviceSubscriptionId = id
        devices = await repo.devicesInfo(subscriptionId: id)
    }

    func purchase(tariff: TariffOffer, period: PeriodPrice) async {
        await run("Подписка оформлена!") {
            await self.repo.purchaseTariff(tariffId: tariff.id, periodDays: period.days)
        }
    }

    func renew(period: PeriodPrice) async {
        await run("Подписка продлена!") { await self.repo.renew(periodDays: period.days) }
    }

    func buyDevices(_ count: Int) async {
        await run("Устройства добавлены!") {
            await self.repo.buyDevices(count: count, subscriptionId: self.deviceSubscriptionId)
        }
    }

    func reduceDevices(to limit: Int) async {
        await run("Лимит устройств уменьшен") {
            await self.repo.reduceDevices(newLimit: limit, subscriptionId: self.deviceSubscriptionId)
        }
    }

    func buyTraffic(_ gb: Int) async {
        await run("Трафик добавлен!") { await self.repo.buyTraffic(gb: gb) }
    }

    private func run(_ successMessage: String, _ action: () async -> String?) async {
        purchasing = true
        error = nil
        info = nil
        let failure = await action()
        purchasing = false
        if let failure {
            error = failure
        } else {
            info = successMessage
            await refresh()
            // покупка могла дать свою подписку — перечитываем серверы, чтобы
            // бывший гость сразу перешёл с чужой ссылки на собственную
            await SubscriptionModel.shared.refresh(force: true)
        }
    }
}

struct PlansView: View {
    @StateObject private var model = PlansModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let info = model.info { banner(info, color: Theme.goldSoft) }
                        if let error = model.error { banner(error, color: .red) }

                        ForEach(model.tariffs) { tariff in
                            tariffCard(tariff)
                        }

                        if !model.trafficPackages.isEmpty { trafficCard }
                        if let devices = model.devices, devices.purchaseAvailable || devices.reduceAvailable {
                            devicesCard(devices)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await model.refresh() }

                if model.loading && model.tariffs.isEmpty { ProgressView() }
            }
            .navigationTitle("Тарифы")
        }
        .task { await model.refresh() }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text).font(.footnote).foregroundStyle(color).card()
    }

    private func tariffCard(_ tariff: TariffOffer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tariff.name).font(.headline)
                Spacer()
                if model.ownedTariffIds.contains(tariff.id) {
                    Text("Подключён")
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }
            }

            if let description = tariff.description, !description.isEmpty {
                Text(description).font(.footnote).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let traffic = tariff.trafficLimitGb {
                    Label(traffic > 0 ? "\(traffic) ГБ" : "Безлимит", systemImage: "arrow.up.arrow.down")
                }
                if let limit = model.deviceLimit(for: tariff) {
                    Label("\(limit) устройств", systemImage: "iphone")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(tariff.periods, id: \.self) { period in
                Button {
                    Task {
                        if model.ownedTariffIds.contains(tariff.id) {
                            await model.renew(period: period)
                        } else {
                            await model.purchase(tariff: tariff, period: period)
                        }
                    }
                } label: {
                    HStack {
                        Text(Format.days(period.days))
                        Spacer()
                        Text(Format.rubles(period.priceKopeks)).bold()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.purchasing)
            }
        }
        .card()
    }

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Докупить трафик").font(.headline)
            ForEach(model.trafficPackages, id: \.self) { package in
                Button {
                    Task { await model.buyTraffic(package.gb) }
                } label: {
                    HStack {
                        Text("\(package.gb) ГБ")
                        Spacer()
                        Text(Format.rubles(package.priceKopeks)).bold()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.purchasing)
            }
        }
        .card()
    }

    private func devicesCard(_ devices: DevicesInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Устройства").font(.headline)

            if model.subscriptions.count > 1 {
                // без выбора подписки лимит менялся бы не у того тарифа
                Menu {
                    ForEach(model.subscriptions) { sub in
                        Button(sub.displayName) {
                            Task { await model.selectDeviceSubscription(sub.id) }
                        }
                    }
                } label: {
                    HStack {
                        Text(deviceSubscriptionName)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                }
                .buttonStyle(.bordered)
            }

            if let limit = devices.deviceLimit {
                Text("Лимит: \(limit)" + (devices.connectedCount.map { ", подключено: \($0)" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if devices.purchaseAvailable, let price = devices.pricePerDeviceKopeks {
                Button("Добавить устройство · \(Format.rubles(price))") {
                    Task { await model.buyDevices(1) }
                }
                .buttonStyle(.bordered)
                .disabled(model.purchasing)
            }

            if devices.reduceAvailable, let limit = devices.deviceLimit, limit > 1 {
                Button("Уменьшить лимит до \(limit - 1)") {
                    Task { await model.reduceDevices(to: limit - 1) }
                }
                .buttonStyle(.bordered)
                .disabled(model.purchasing)
            }

            NavigationLink("Управление устройствами") {
                DevicesView(subscriptionId: model.deviceSubscriptionId)
            }
            .font(.footnote)
        }
        .card()
    }

    private var deviceSubscriptionName: String {
        model.subscriptions.first { $0.id == model.deviceSubscriptionId }?.displayName
            ?? "Выберите подписку"
    }
}
