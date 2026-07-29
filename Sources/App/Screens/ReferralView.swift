import SwiftUI

struct ReferralView: View {
    @State private var info: ReferralInfoResponse?
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if loading {
                        ProgressView()
                    } else if let info {
                        linkCard(info)
                        statsCard(info)
                    } else {
                        Text("Реферальная программа недоступна.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .card()
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Пригласить друга")
        .task {
            info = await BalanceRepository.shared.referralInfo()
            loading = false
        }
    }

    private func linkCard(_ info: ReferralInfoResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ваша ссылка").font(.headline)
            if let link = info.shareLink {
                Text(link)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                ShareLink(item: link) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            } else if let code = info.referralCode {
                Text(code).font(.title3.monospaced())
            }

            if let percent = info.commissionPercent {
                Text("Вы получаете \(Int(percent))% с платежей приглашённых.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func statsCard(_ info: ReferralInfoResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Статистика").font(.headline)
            if let total = info.totalReferrals {
                Text("Приглашено: \(total)").font(.subheadline)
            }
            if let active = info.activeReferrals {
                Text("Активных: \(active)").font(.subheadline)
            }
            if let earned = info.totalEarningsKopeks {
                Text("Заработано: \(Format.rubles(earned))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.gold)
            }
        }
        .card()
    }
}
