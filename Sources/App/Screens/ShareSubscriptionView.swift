import SwiftUI

/// Поделиться подпиской.
///
/// Аккаунтом поделиться нельзя — вход идёт через Telegram, — поэтому делимся
/// ссылкой на саму подписку: близкий человек подключается по QR и получает
/// VPN, но не получает доступа к кабинету, балансу и оплате.
struct ShareSubscriptionView: View {

    @State private var subscriptions: [SubscriptionListItem] = []
    @State private var selectedId: Int64?
    @State private var link: String?
    @State private var qrImage: UIImage?
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if subscriptions.count > 1 { picker }

                    if loading {
                        ProgressView()
                    } else if let qrImage {
                        VStack(spacing: 12) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260)
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("Пусть друг откроет приложение и отсканирует этот код или пришлите ему картинку.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            if let link {
                                ShareLink(item: link) {
                                    Label("Отправить ссылку", systemImage: "link")
                                }
                                .buttonStyle(.bordered)
                            }

                            ShareLink(
                                item: Image(uiImage: qrImage),
                                preview: SharePreview("QR-код подписки", image: Image(uiImage: qrImage))
                            ) {
                                Label("Отправить картинкой", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)
                        }
                        .card()
                    } else {
                        Text("Не удалось получить ссылку на подписку.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .card()
                    }

                    warning
                }
                .padding(16)
            }
        }
        .navigationTitle("Поделиться")
        .task { await load() }
    }

    private var picker: some View {
        Menu {
            ForEach(subscriptions) { sub in
                Button(sub.displayName) {
                    selectedId = sub.id
                    Task { await buildLink() }
                }
            }
        } label: {
            HStack {
                Text(subscriptions.first { $0.id == selectedId }?.displayName ?? "Выберите подписку")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Важно").font(.headline)
            Text("Каждый подключившийся занимает место в лимите устройств вашей подписки. Отключить лишних можно в разделе «Подключённые устройства».")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func load() async {
        subscriptions = await SubscriptionRepository.shared.subscriptions()
        if selectedId == nil {
            selectedId = SharedStore.shared.selectedSubscriptionId
                ?? subscriptions.first { $0.isActive }?.id
                ?? subscriptions.first?.id
        }
        await buildLink()
    }

    private func buildLink() async {
        loading = true
        defer { loading = false }

        let url: String?
        if let selectedId, let fromList = subscriptions.first(where: { $0.id == selectedId })?.subscriptionUrl {
            url = fromList
        } else {
            url = await SubscriptionRepository.shared.resolveSubscriptionUrl()
        }
        guard let url else {
            link = nil
            qrImage = nil
            return
        }

        // свой префикс, чтобы приложение отличало наш код от чужих
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let deepLink = "darkprincevpn://sub?url=\(encoded)"
        link = deepLink
        qrImage = QrUtils.generate(from: deepLink)
    }
}
