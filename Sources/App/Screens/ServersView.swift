import SwiftUI

struct ServersView: View {
    @StateObject private var model = SubscriptionModel.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if model.servers.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(model.servers.enumerated()), id: \.offset) { index, server in
                            Button {
                                model.selectServer(index)
                            } label: {
                                row(index: index, server: server)
                            }
                            .listRowBackground(Theme.cardBackground)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable { await model.refresh(force: true) }
                }
            }
            .navigationTitle("Серверы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.pingAll() }
                    } label: {
                        if model.pinging {
                            ProgressView()
                        } else {
                            Image(systemName: "bolt.horizontal")
                        }
                    }
                    .disabled(model.pinging || model.servers.isEmpty)
                }
            }
        }
    }

    private func row(index: Int, server: ProxyProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .foregroundStyle(.primary)
                Text("\(server.proxyProtocol.rawValue.uppercased()) · \(server.address)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let ping = model.pings[index] {
                Text(ping >= 0 ? "\(ping) мс" : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(pingColor(ping))
            }
            if index == model.selectedServer {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(.vertical, 4)
    }

    private func pingColor(_ value: Int64) -> Color {
        switch value {
        case ..<0: return .secondary
        case 0..<150: return .green
        case 150..<400: return Theme.goldSoft
        default: return .orange
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Список серверов пуст")
                .font(.headline)
            Text("Потяните вниз, чтобы загрузить подписку заново.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Обновить") { Task { await model.refresh(force: true) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
