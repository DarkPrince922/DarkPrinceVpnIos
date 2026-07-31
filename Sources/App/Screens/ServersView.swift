import SwiftUI

struct ServersView: View {
    @StateObject private var model = SubscriptionModel.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Серверы").font(.title2).fontWeight(.semibold)
                        Spacer()
                        if model.pinging {
                            ProgressView()
                        } else {
                            CircleActionButton(systemName: "speedometer") {
                                Task { await model.pingAll() }
                            }
                        }
                        CircleActionButton(systemName: "arrow.clockwise") {
                            Task { await model.refresh(force: true) }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                    if model.servers.isEmpty {
                        emptyState
                    } else {
                        SectionHeader("Доступные узлы · \(model.servers.count)")
                        VStack(spacing: 10) {
                            ForEach(Array(model.servers.enumerated()), id: \.offset) { index, server in
                                ServerRow(
                                    server: server,
                                    selected: index == model.selectedServer,
                                    ping: model.pings[index]
                                ) {
                                    model.selectServer(index)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh(force: true) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Список серверов пуст").font(.headline)
            Text("Потяните вниз, чтобы загрузить подписку заново.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Строка сервера: слева плитка с флагом из названия, справа — метки
/// транспорта и формата конфига. Выбранный узел обведён акцентной рамкой.
private struct ServerRow: View {
    let server: ProxyProfile
    let selected: Bool
    let ping: Int64?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                EmojiTile(emoji: leadingEmoji(server.name) ?? "🌐")

                VStack(alignment: .leading, spacing: 6) {
                    Text(nameWithoutEmoji(server.name))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        TagChip(server.transportLabel, tint: Theme.goldSoft)
                        if server.rawConfig != nil { TagChip("JSON") }
                    }
                }

                Spacer()

                if let ping {
                    Text(ping >= 0 ? "\(ping) мс" : "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(pingColor(ping))
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.gold)
                }
            }
            .padding(14)
            .background(selected ? Theme.gold.opacity(0.07) : Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        selected ? Theme.gold.opacity(0.7) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func pingColor(_ value: Int64) -> Color {
        switch value {
        case ..<0: return .secondary
        case 0..<150: return .green
        case 150..<400: return Theme.goldSoft
        default: return .orange
        }
    }
}
