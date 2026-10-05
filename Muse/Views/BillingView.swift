import SwiftUI

struct BillingScreen: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationView {
            List {
                Section("当前状态") {
                    HStack {
                        Text(store.data.subscription.planText)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.1f", store.data.subscription.credits))
                                .font(.title3.weight(.bold))
                                .foregroundColor(Theme.accent2)
                            Text("剩余积分")
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    Text("下个账单日：\(store.data.subscription.renewAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }

                Section("充值与订阅（模拟支付渠道：PayPal / 信用卡）") {
                    ForEach(AppStore.topUpOptions) { option in
                        Button {
                            store.purchase(option)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(option.price)
                                        .font(.caption)
                                        .foregroundColor(Theme.accent2)
                                }
                                Spacer()
                                Text("立即购买")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("额度流水") {
                    if store.data.subscription.transactions.isEmpty {
                        Text("暂无流水")
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                    }
                    ForEach(store.data.subscription.transactions.prefix(20)) { t in
                        HStack {
                            Text(t.time.formatted(date: .numeric, time: .shortened))
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text(String(format: "%+.1f", t.credits))
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                        }
                        Text(t.note)
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("订阅与额度")
        }
        .navigationViewStyle(.stack)
    }
}
