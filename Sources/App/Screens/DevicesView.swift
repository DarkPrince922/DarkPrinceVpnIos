import SwiftUI

@MainActor
final class DevicesModel: ObservableObject {
    @Published var devices: [DeviceDto] = []
    @Published var deviceLimit: Int?
    @Published var subscriptions: [SubscriptionListItem] = []
    @Published var selectedSubscriptionId: Int64?
    @Published var loading = false
    @Published var busy = false
    @Published var error: String?
    @Published var info: String?

    private let repo = SubscriptionRepository.shared

    var ownHwid: String { repo.ownHwid }

    func load(subscriptionId: Int64?) async {
        loading = true
        subscriptions = await repo.subscriptions()
        if selectedSubscriptionId == nil {
            selectedSubscriptionId = subscriptionId
                ?? subscriptions.first { $0.isActive }?.id
                ?? subscriptions.first?.id
        }
        devices = await repo.devicesList(subscriptionId: selectedSubscriptionId)
        deviceLimit = await repo.devicesInfo(subscriptionId: selectedSubscriptionId).deviceLimit
        loading = false
    }

    func selectSubscription(_ id: Int64) async {
        selectedSubscriptionId = id
        await load(subscriptionId: id)
    }

    func delete(_ hwid: String) async {
        await run("Устройство отключено") {
            await self.repo.deleteDevice(hwid: hwid, subscriptionId: self.selectedSubscriptionId)
        }
    }

    func deleteAll() async {
        await run("Все устройства отключены") {
            await self.repo.deleteAllDevices(subscriptionId: self.selectedSubscriptionId)
        }
    }

    func rename(_ hwid: String, to name: String) async {
        await run("Название сохранено") {
            await self.repo.renameDevice(
                hwid: hwid,
                name: name,
                subscriptionId: self.selectedSubscriptionId
            )
        }
    }

    /// Панель заводит устройство в момент загрузки подписки, поэтому
    /// «регистрация» — это просто повторный запрос подписки с HWID-заголовками.
    func registerThisDevice() async {
        busy = true
        error = nil
        info = nil
        do {
            _ = try await repo.fetchServers(forceRefresh: true)
            info = "Запрос отправлен, обновляю список…"
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
        await load(subscriptionId: selectedSubscriptionId)
    }

    private func run(_ successMessage: String, _ action: () async -> String?) async {
        busy = true
        error = nil
        info = nil
        let failure = await action()
        busy = false
        if let failure {
            error = failure
        } else {
            info = successMessage
            await load(subscriptionId: selectedSubscriptionId)
        }
    }
}

struct DevicesView: View {
    let subscriptionId: Int64?

    @StateObject private var model = DevicesModel()
    @State private var confirmDelete: DeviceDto?
    @State private var confirmDeleteAll = false
    @State private var renaming: DeviceDto?
    @State private var newName = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if model.loading {
                        ProgressView()
                    } else if model.devices.isEmpty {
                        emptyState
                    } else {
                        if !model.devices.contains(where: { $0.hwid == model.ownHwid }) {
                            registerCard
                        }
                        ForEach(model.devices) { device in
                            deviceRow(device)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Устройства")
        .task { await model.load(subscriptionId: subscriptionId) }
        .alert("Отключить устройство?", isPresented: .constant(confirmDelete != nil)) {
            Button("Отмена", role: .cancel) { confirmDelete = nil }
            Button("Отключить", role: .destructive) {
                if let device = confirmDelete {
                    Task { await model.delete(device.hwid) }
                }
                confirmDelete = nil
            }
        } message: {
            if let device = confirmDelete, device.hwid == model.ownHwid {
                Text("Это устройство, с которого вы сейчас пользуетесь VPN. После отключения придётся подключиться заново.")
            } else {
                Text("Устройство потеряет доступ к подписке и освободит место в лимите.")
            }
        }
        .alert("Отключить все устройства?", isPresented: $confirmDeleteAll) {
            Button("Отмена", role: .cancel) {}
            Button("Отключить все", role: .destructive) {
                Task { await model.deleteAll() }
            }
        } message: {
            Text("Доступ потеряют все устройства, включая это.")
        }
        .alert("Название устройства", isPresented: .constant(renaming != nil)) {
            TextField("Например: телефон жены", text: $newName)
            Button("Отмена", role: .cancel) { renaming = nil }
            Button("Сохранить") {
                if let device = renaming {
                    Task { await model.rename(device.hwid, to: newName) }
                }
                renaming = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.subscriptions.count > 1 {
                Menu {
                    ForEach(model.subscriptions) { sub in
                        Button(sub.displayName) {
                            Task { await model.selectSubscription(sub.id) }
                        }
                    }
                } label: {
                    HStack {
                        Text(subscriptionName)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Text("Подключено: \(model.devices.count)" +
                     (model.deviceLimit.map { " из \($0)" } ?? ""))
                    .font(.subheadline)
                Spacer()
                if !model.devices.isEmpty {
                    Button("Отключить все") { confirmDeleteAll = true }
                        .font(.footnote)
                        .disabled(model.busy)
                }
            }

            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let info = model.info {
                Text(info).font(.footnote).foregroundStyle(Theme.goldSoft)
            }
        }
        .card()
    }

    private var subscriptionName: String {
        model.subscriptions.first { $0.id == model.selectedSubscriptionId }?.displayName
            ?? "Выберите подписку"
    }

    private func deviceRow(_ device: DeviceDto) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.title).font(.headline)
                    if device.hwid == model.ownHwid {
                        Text("это устройство")
                            .font(.caption)
                            .foregroundStyle(Theme.gold)
                    }
                }
                if let subtitle = device.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                if let created = device.createdAt {
                    Text("Подключено: \(String(created.prefix(10)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                newName = device.localName ?? device.title
                renaming = device
            } label: {
                Image(systemName: "pencil")
            }
            .disabled(model.busy)

            Button {
                confirmDelete = device
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .disabled(model.busy)
        }
        .card()
    }

    private var registerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Этого телефона нет в списке").font(.headline)
            Text("Устройство регистрируется при загрузке подписки. Нажмите, чтобы запросить её заново.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Зарегистрировать") { Task { await model.registerThisDevice() } }
                .buttonStyle(.bordered)
                .disabled(model.busy)
            Text("ID этого устройства: \(String(model.ownHwid.prefix(13)))…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Устройств пока нет").font(.headline)
            Text("Панель заводит устройство в момент загрузки подписки — нажмите кнопку ниже, если этот телефон не появился в списке.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Зарегистрировать это устройство") {
                Task { await model.registerThisDevice() }
            }
            .buttonStyle(.bordered)
            .disabled(model.busy)
        }
        .card()
    }
}
