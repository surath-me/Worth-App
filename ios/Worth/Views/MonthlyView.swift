import SwiftUI

/// Every recorded month, newest first, with its total and the change vs the month before; tap one for its entries.
struct MonthlyView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            let s = store.series
            List {
                if s.isEmpty {
                    Text("Months appear here once you have entries.").foregroundStyle(Color.sec)
                }
                ForEach(Array(s.enumerated().reversed()), id: \.element.month) { i, p in
                    NavigationLink {
                        MonthDetailView(month: p.month)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Month.long(p.month)).font(.system(size: 15, weight: .medium))
                                if i > 0 {
                                    let prev = s[i - 1].value
                                    ChangeLabel(change: p.value - prev, from: prev, cur: store.data.base).font(.system(size: 13))
                                }
                            }
                            Spacer()
                            Text(Money.format(p.value, store.data.base, decimals: 0)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Monthly")
        }
    }
}

/// One month's record: its total and every entry as saved that month.
struct MonthDetailView: View {
    @Environment(Store.self) private var store
    let month: String

    var body: some View {
        let snap = store.data.snaps[month]
        let rates = snap?.rates ?? store.data.rates
        let items = (snap?.items ?? [:]).map { (id: $0.key, it: $0.value) }
            .sorted { (Catalog.isLiab($0.it.type) ? 1 : 0, -store.conv($0.it.bal, $0.it.cur, rates: rates)) < (Catalog.isLiab($1.it.type) ? 1 : 0, -store.conv($1.it.bal, $1.it.cur, rates: rates)) }
        List {
            if let snap {
                Section {
                    Text(Money.format(store.total(of: snap), store.data.base, decimals: 0))
                        .font(.system(size: 34, weight: .bold)).monospacedDigit()
                }
            }
            Section("Entries") {
                ForEach(items, id: \.id) { row in
                    let t = Catalog.type(row.it.type)
                    let acc = store.data.accounts.first { $0.id == row.id }
                    HStack(spacing: 12) {
                        Avatar(symbol: acc.map(Catalog.symbol(for:)) ?? Catalog.safeSymbol(t.symbol), color: t.color, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acc?.name ?? row.it.name ?? "Removed entry").font(.system(size: 15, weight: .medium))
                            Text(t.name).font(.system(size: 13)).foregroundStyle(Color.sec)
                        }
                        Spacer()
                        Text((t.liab ? "−" : "") + Money.format(row.it.bal, row.it.cur)).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(Month.long(month))
        .navigationBarTitleDisplayMode(.inline)
    }
}
