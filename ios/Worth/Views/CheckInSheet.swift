import SwiftUI

/// The monthly check-in. A new month starts from the last one (with each entry's yearly value change applied), and
/// only asks about what moves: one card per entry that usually changes (bank accounts, investments, debts being paid
/// down), each showing last month's value with "Same as October" or the new amount. Entries that rarely change
/// (property, cars, valuables, anything untouched for three months) are carried over and wait on the review screen,
/// where any entry can be opened again. After saving, a reveal shows the month's total, its change and what moved it.
struct CheckInSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let start: String
    var onSaved: ((String) -> Void)? = nil

    @State private var month = Month.key()
    @State private var text: [String: String] = [:]      // id -> the amount as shown
    @State private var sugg: [String: Double] = [:]      // id -> the carried-over value
    @State private var carriedFrom: String?
    @State private var isNew = false
    @State private var movers: [String] = []             // ids that get a card, in order (fixed when the month loads)
    @State private var deck: [String] = []               // the cards being gone through
    @State private var step: Int?                        // the card on screen; nil = the review screen
    @State private var forward = true                    // which way the cards slide
    @State private var drag: CGFloat = 0
    @State private var revealed: String?
    @State private var addingEntry = false
    @State private var focus: String?                    // the amount being typed in
    @State private var opened: String?                   // the entry last opened from the review screen

    private var accs: [Account] { store.data.accounts.sorted { (Catalog.isLiab($0.type) ? 1 : 0) < (Catalog.isLiab($1.type) ? 1 : 0) } }
    private func acc(_ id: String) -> Account? { store.data.accounts.first { $0.id == id } }

    var body: some View {
        NavigationStack {
            Group {
                if let m = revealed { Reveal(month: m) { dismiss() } }
                else if let i = step, deck.indices.contains(i), let a = acc(deck[i]) { card(a, i) }
                else { review }
            }
            .background(Color(.systemBackground))
            .navigationTitle(revealed.map(Month.long) ?? (step != nil && deck.count > 1 ? "\(Month.name(month)) check-in" : Month.long(month)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if revealed != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    if step != nil, deck.count > 1 {
                        // skip the rest: they keep last month's values
                        ToolbarItem(placement: .confirmationAction) { Button("Review") { go(nil) } }
                    }
                }
            }
            .tint(.primary)
            .sheet(isPresented: $addingEntry) {
                EntrySheet(account: nil, after: { a in if let a { text[a.id] = EntrySheet.show(a.bal, a.cur) } })
            }
        }
        .onAppear { month = min(start, Month.key()); fill(); if isNew, !movers.isEmpty { deck = movers; step = 0 } }
    }

    // MARK: one card per entry

    private func card(_ a: Account, _ i: Int) -> some View {
        let t = Catalog.type(a.type), last = store.lastRecorded(a, before: month)
        let v = value(a.id), same = last.map { l in v.map { abs($0 - l.value) < 0.005 } ?? false } ?? false
        let lastLabel = last.map { store.vsLabel(month, $0.month) }
        return VStack(spacing: 0) {
            if deck.count > 1 {
                // progress through the cards
                VStack(spacing: 8) {
                    GeometryReader { g in
                        Capsule().fill(Color.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [.g1, .g2], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * CGFloat(i + 1) / CGFloat(deck.count))
                            }
                    }
                    .frame(height: 5)
                    Text("\(i + 1) of \(deck.count)").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sec).monospacedDigit()
                }
                .padding(.horizontal, 20).padding(.top, 8)
                .animation(.spring(duration: 0.4), value: i)
            }

            Spacer(minLength: 12)

            VStack(spacing: 14) {
                Avatar(symbol: Catalog.symbol(for: a), color: t.color, size: 60, grad: t.id)
                VStack(spacing: 4) {
                    Text(a.name).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
                    Text(a.platform.isEmpty ? t.name : a.platform).font(.system(size: 15)).foregroundStyle(Color.sec)
                }
                HStack(alignment: .center, spacing: 6) {
                    Text(Currency.symbol[a.cur] ?? a.cur).font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.sec)
                    AmountField(text: binding(a), cur: a.cur, size: 38, weight: .bold, align: .center,
                                focused: Binding(get: { focus == a.id }, set: { f in if f { focus = a.id } else if focus == a.id { focus = nil } }),
                                onReturn: next) // the keyboard's ✓ confirms the amount and moves on
                        .fixedSize()
                }
                .padding(.horizontal, 18).frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(focus == a.id ? 0.1 : 0.06)))
                .contentShape(Rectangle())
                .onTapGesture { focus = a.id }
                .masked()
                Group {
                    if let last, let lastLabel {
                        if same { Text("Tap the amount to change it").foregroundStyle(Color.sec) } // the button already says "Same as October"
                        else if let v {
                            let d = v - last.value, good = t.liab ? d < 0 : d > 0
                            (Text((d > 0 ? "+" : "−") + Money.format(abs(d), a.cur)).foregroundStyle(good ? Color.up : Color.down).fontWeight(.semibold)
                             + Text(" since \(lastLabel) · was \(Money.format(last.value, a.cur))").foregroundStyle(Color.sec))
                        }
                    } else { Text(t.liab ? "What you owe now" : "First value for this entry").foregroundStyle(Color.sec) }
                }
                .font(.system(size: 14)).masked()
                .contentTransition(.numericText()).animation(.snappy, value: v)
            }
            .padding(.horizontal, 24).padding(.vertical, 28).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 28).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 16)
            // swipe right: next (keeps the value); swipe left: back
            .offset(x: drag).rotationEffect(.degrees(Double(drag) / 40))
            .gesture(DragGesture(minimumDistance: 20)
                .onChanged { g in if abs(g.translation.width) > abs(g.translation.height) { drag = g.translation.width } }
                .onEnded { g in
                    let w = g.translation.width
                    if w > 90 { next() } else if w < -90, i > 0 { go(i - 1) }
                    withAnimation(.spring(duration: 0.35)) { drag = 0 }
                })
            .id(deck[i])
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Button(primaryLabel(same: same, lastLabel: lastLabel, isLast: i == deck.count - 1), action: next)
                    .buttonStyle(PrimaryButton())
                HStack {
                    if i > 0 {
                        Button { go(i - 1) } label: { Label("Back", systemImage: "chevron.left") }
                    }
                    Spacer()
                    if deck.count > 1 { Text("Swipe right for next").foregroundStyle(Color.sec) }
                }
                .font(.system(size: 14, weight: .medium)).frame(height: 30).padding(.horizontal, 6)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .sensoryFeedback(.selection, trigger: i)
    }

    private func primaryLabel(same: Bool, lastLabel: String?, isLast: Bool) -> String {
        if deck.count == 1 { return "Done" }
        if same, let lastLabel { return "Same as \(lastLabel)" }
        return isLast ? "Review" : "Next"
    }

    private func binding(_ a: Account) -> Binding<String> { Binding(get: { text[a.id] ?? "" }, set: { text[a.id] = $0 }) }

    /// Leaving a field tidies the amount ("14,921." → "14,921").
    private func tidy(_ a: Account) { text[a.id] = value(a.id).map { EntrySheet.show($0, a.cur) } ?? "" }

    private func next() {
        if let i = step, deck.indices.contains(i), let a = acc(deck[i]) { tidy(a) }
        focus = nil
        guard let i = step else { return }
        go(i + 1 < deck.count ? i + 1 : nil)
    }

    private func go(_ to: Int?) {
        focus = nil
        forward = (to ?? .max) > (step ?? -1)
        withAnimation(.spring(duration: 0.42, bounce: 0.12)) { step = to }
        if to == nil { deck = movers }
    }

    /// Open one entry's card from the review screen.
    private func open(_ id: String) {
        deck = [id]; forward = true; opened = id
        withAnimation(.spring(duration: 0.42, bounce: 0.12)) { step = 0 }
    }

    // MARK: review

    private var review: some View {
        let carriedIDs = accs.map(\.id).filter { !movers.contains($0) }
        return ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monthRow
                if isNew {
                    if !movers.isEmpty {
                        Text("Usually change").sectionLabel().padding(.top, 22)
                        list(movers)
                    }
                    if !carriedIDs.isEmpty {
                        (Text("Carried over") + Text(carriedFrom.map { " from \(store.label($0))" } ?? ""))
                            .sectionLabel().padding(.top, 22)
                        list(carriedIDs, addRow: true)
                        Text("These rarely change, so they keep their last value (cars and property with their yearly value change). Tap one to change it.")
                            .font(.system(size: 12)).foregroundStyle(Color.sec).padding(.horizontal, 16).padding(.top, 8)
                    }
                } else {
                    Text("Balances").sectionLabel().padding(.top, 22)
                    list(accs.map(\.id), addRow: true)
                }
                totalRow.padding(.top, 22)
                Button("Save \(Month.name(month))", action: save).buttonStyle(PrimaryButton()).padding(.top, 16)
                if isNew, !movers.isEmpty {
                    Button("Go through the cards again") { opened = nil; deck = movers; forward = true; withAnimation(.spring(duration: 0.42, bounce: 0.12)) { step = 0 } }
                        .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity).padding(.top, 14)
                }
            }
            .padding(16)
        }
        // back from an entry's card: where that entry is, not the top
        .onAppear { if let id = opened { proxy.scrollTo(id, anchor: .center) } }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func list(_ ids: [String], addRow: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(ids, id: \.self) { id in
                if let a = acc(id) {
                    Button { open(id) } label: { row(a) }.buttonStyle(.plain).id(id)
                    if addRow || id != ids.last { Divider().padding(.leading, 66) }
                }
            }
            if addRow {
                Button { addingEntry = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.g1)
                            .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08)))
                        Text("New entry").font(.system(size: 15, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func row(_ a: Account) -> some View {
        let t = Catalog.type(a.type)
        return HStack(spacing: 12) {
            Avatar(symbol: Catalog.symbol(for: a), color: t.color, grad: t.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                hint(a).font(.system(size: 12)).foregroundStyle(Color.sec).lineLimit(1).masked()
            }
            Spacer(minLength: 8)
            Text(value(a.id).map { (t.liab ? "−" : "") + Money.format($0, a.cur) } ?? "—")
                .font(.system(size: 15, weight: .medium)).monospacedDigit().masked()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.hex(0x5C5C61))
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
    }

    private var monthRow: some View {
        let options = (0..<36).map { Month.shift(Month.key(), by: -$0) }
        return HStack {
            Text("Month").font(.system(size: 15))
            Spacer()
            Menu {
                ForEach(options, id: \.self) { m in Button(Month.long(m) + (store.data.snaps[m] != nil ? "  ✓" : "")) { month = m; fill() } }
            } label: {
                HStack(spacing: 4) { Text(Month.long(month)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)) }
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.sec)
            }
        }
        .padding(.horizontal, 16).frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    /// "Oct: €14,922 · +€500": the change in green, red when it's the bad way.
    private func hint(_ a: Account) -> Text {
        let t = Catalog.type(a.type)
        guard let last = store.lastRecorded(a, before: month) else { return Text((a.platform.isEmpty ? t.name : a.platform) + (t.liab ? " · owed" : "")) }
        var h = Text("\(Month.date(last.month).formatted(.dateTime.month(.abbreviated))): \(Money.format(last.value, a.cur))")
        if let v = value(a.id), abs(v - last.value) >= 0.005 {
            let d = v - last.value, good = t.liab ? d < 0 : d > 0
            h = h + Text(" · ") + Text((d > 0 ? "+" : "−") + Money.format(abs(d), a.cur)).foregroundStyle(good ? Color.up : Color.down)
        }
        return h
    }

    private var totalRow: some View {
        let rates = store.rates(for: month)
        let t = accs.reduce(0.0) { s, a in s + (value(a.id).map { (Catalog.isLiab(a.type) ? -1 : 1) * store.conv($0, a.cur, rates: rates) } ?? 0) }
        return HStack(alignment: .firstTextBaseline) {
            Text("Net worth").font(.system(size: 15, weight: .semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(t, store.data.base, decimals: 0)).font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText(value: t)).animation(.snappy, value: t)
                if let pk = store.prevKey(month), let ps = store.data.snaps[pk] {
                    let d = t - store.total(of: ps)
                    if abs(d) < 0.5 { Text("Same as \(store.vsLabel(month, pk))").font(.system(size: 13)).foregroundStyle(Color.sec) }
                    else {
                        (Text("\(d > 0 ? "▲" : "▼") \(Money.format(abs(d), store.data.base, decimals: 0))").foregroundStyle(d > 0 ? Color.up : Color.down)
                         + Text(" vs \(store.vsLabel(month, pk))").foregroundStyle(Color.sec)).font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .masked()
        }
        .padding(.horizontal, 4)
    }

    // MARK: logic

    private func value(_ id: String) -> Double? { EntrySheet.parse(text[id] ?? "") }

    /// Whether an entry gets a card: things that are appraised now and then (property, cars, valuables) don't, nor does
    /// anything whose last three records were the same; everything else does (bank accounts, investments, debts).
    private func moves(_ a: Account) -> Bool {
        if Catalog.type(a.type).dep != nil { return false }
        let recs = store.data.snaps.keys.sorted(by: >).filter { $0 < month }.compactMap { store.data.snaps[$0]?.items[a.id]?.bal }.prefix(3)
        guard recs.count == 3 else { return true }
        return Set(recs.map { ($0 * 100).rounded() }).count > 1
    }

    /// A recorded month shows its own values; a new month (or the current month before its check-in) starts from the
    /// last one, with the yearly value changes applied.
    private func fill() {
        let cm = Month.key(), snap = store.data.snaps[month]
        isNew = month == cm ? store.data.lastCheckin != cm : snap == nil
        sugg = [:]; carriedFrom = nil; text = [:]; focus = nil
        for a in accs {
            var v: Double?
            if !isNew, let snap { v = snap.items[a.id]?.bal ?? (month == cm ? a.bal : nil) }
            else {
                let c = store.carried(a, to: month); v = c.value
                if let cv = c.value { sugg[a.id] = cv }
                if let f = c.from, carriedFrom == nil || f > carriedFrom! { carriedFrom = f }
            }
            text[a.id] = v.map { EntrySheet.show($0, a.cur) } ?? ""
        }
        movers = isNew ? accs.filter(moves).map(\.id) : []
        deck = movers
    }

    private func save() {
        focus = nil
        var vals: [String: Double?] = [:]
        for a in accs { vals[a.id] = value(a.id) }
        store.saveCheckIn(month: month, values: vals)
        onSaved?(month)
        if store.data.snaps[month] != nil { withAnimation(.spring(duration: 0.45)) { revealed = month } } else { dismiss() }
    }
}

/// After saving: "Your November", the total, the change vs the month before, a "New high" / "N months up" badge, and
/// up to five groups that moved (gross, so paying down debt shows as "Debts paid").
private struct Reveal: View {
    @Environment(Store.self) private var store
    let month: String
    let close: () -> Void
    @State private var shown = false

    var body: some View {
        let snap = store.data.snaps[month]!, total = store.total(of: snap), pk = store.prevKey(month)
        ScrollView {
            VStack(spacing: 14) {
                Text("Your \(Month.name(month))").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.sec).stagger(0, shown)
                Text(Money.format(total, store.data.base, decimals: 0)).font(.system(size: 42, weight: .bold)).monospacedDigit().masked().stagger(1, shown)
                if let pk, let ps = store.data.snaps[pk] {
                    let pv = store.total(of: ps), d = total - pv
                    Group {
                        if abs(d) < 0.5 { Text("Same as \(store.vsLabel(month, pk))").foregroundStyle(Color.sec) }
                        else { ChangeLabel(change: d, from: pv, cur: store.data.base, suffix: "  vs " + store.vsLabel(month, pk)) }
                    }
                    .masked().stagger(2, shown)
                    if let badge = store.streakBadge(total: total, month: month) {
                        Text(badge).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 30)
                            .background(Capsule().fill(LinearGradient(colors: [.g1, .g2], startPoint: .leading, endPoint: .trailing)))
                            .stagger(3, shown)
                    }
                    let mv = Array(store.moves(from: store.rows(of: ps), to: store.rows(of: snap)).prefix(5))
                    if mv.isEmpty { Text("No change").foregroundStyle(Color.sec).stagger(4, shown) }
                    else {
                        VStack(spacing: 12) {
                            ForEach(mv) { x in
                                HStack {
                                    Circle().fill(Catalog.groups.first { $0.id == x.groupID }?.color ?? .gray).frame(width: 9, height: 9)
                                    Text(x.debt ? (x.change > 0 ? "Debts paid" : "Debts added") : x.name).font(.system(size: 15))
                                    Spacer()
                                    Text(Money.signed(x.change, store.data.base)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(x.change > 0 ? Color.up : Color.down).masked()
                                }
                            }
                        }
                        .padding(16).background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
                        .stagger(4, shown)
                    }
                } else if let nk = store.nextKey(month), let ns = store.data.snaps[nk] {
                    let d = store.total(of: ns) - total
                    (Text("\(d >= 0 ? "▲" : "▼") \(Money.format(abs(d), store.data.base, decimals: 0))").foregroundStyle(d >= 0 ? Color.up : Color.down)
                     + Text(" to \(store.label(nk))").foregroundStyle(Color.sec)).masked().stagger(2, shown)
                } else {
                    Text("First month recorded").foregroundStyle(Color.sec).stagger(2, shown)
                }
                Button("Done", action: close).buttonStyle(PrimaryButton()).padding(.top, 10).stagger(5, shown)
            }
            .padding(24).padding(.top, 20)
        }
        .onAppear { shown = true }
        .sensoryFeedback(.success, trigger: shown)
    }
}

private extension View {
    /// Rise and fade in, one after another.
    func stagger(_ k: Int, _ on: Bool) -> some View {
        self.opacity(on ? 1 : 0).offset(y: on ? 0 : 10)
            .animation(.spring(duration: 0.5, bounce: 0.15).delay(0.08 + Double(k) * 0.09), value: on)
    }
}
