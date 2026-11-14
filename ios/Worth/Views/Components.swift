import SwiftUI

/// The round coloured icon used for an entry (white glyph on the type's colour).
struct Avatar: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
    }
}

/// One entry: icon, name, platform or type, balance (debts shown with a minus).
struct EntryRow: View {
    @Environment(Store.self) private var store
    let account: Account

    var body: some View {
        let t = Catalog.type(account.type)
        HStack(spacing: 12) {
            Avatar(symbol: Catalog.symbol(for: account), color: t.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(subtitle(t)).font(.system(size: 13)).foregroundStyle(Color.sec).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((t.liab ? "−" : "") + Money.format(account.bal, account.cur))
                .font(.system(size: 15, weight: .medium)).monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ t: EntryType) -> String {
        let what = account.platform.isEmpty ? t.name : account.platform
        guard account.cur != store.data.base else { return what }
        return what + " · ≈ " + Money.format(store.conv(account.bal, account.cur), store.data.base, decimals: 0)
    }
}

/// "▲ €4,069 (6.1%)" in green, or red when down.
struct ChangeLabel: View {
    let change: Double
    let from: Double
    let cur: String
    var suffix: String = ""

    var body: some View {
        let pct = from != 0 ? change / abs(from) * 100 : 0
        HStack(spacing: 4) {
            Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 9))
            Text(Money.format(abs(change), cur, decimals: 0) + (from != 0 ? String(format: " (%.1f%%)", abs(pct)) : "") + suffix)
                .monospacedDigit()
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(change >= 0 ? Color.up : Color.down)
    }
}
