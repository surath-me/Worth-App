import SwiftUI

/// The monthly check-in. A new month starts from the last one (with depreciation applied): tick what hasn't changed,
/// type what has. A progress bar counts the rows you've been through (saving is never blocked). Each row shows its
/// last recorded value and the change. After saving, a reveal shows the month's total, its change and what moved it.
struct CheckInSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let start: String
    var onSaved: ((String) -> Void)? = nil

    @State private var month = Month.key()
    @State private var text: [String: String] = [:]      // id -> what's in the field
    @State private var done: Set<String> = []
    @State private var sugg: [String: Double] = [:]
    @State private var carriedFrom: String?
    @State private var blank = false
    @State private var isNew = false
    @State private var revealed: String?
    @State private var addingEntry = false
    @FocusState private var focus: String?

    private var accs: [Account] { store.data.accounts.sorted { (Catalog.isLiab($0.type) ? 1 : 0) < (Catalog.isLiab($1.type) ? 1 : 0) } }

    var body: some View {
        NavigationStack {
            Group {
                if let m = revealed { Reveal(month: m) { dismiss() } }
                else { form }
            }
            .background(Color(.systemBackground))
            .navigationTitle(revealed.map(Month.long) ?? "Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if revealed == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
            }
            .tint(.primary)
            .sheet(isPresented: $addingEntry) {
                EntrySheet(account: nil, after: { a in if let a { text[a.id] = Self.show(a.bal, a.cur); done.insert(a.id) } })
            }
        }
        .onAppear { month = min(start, Month.key()); fill() }
    }

    // MARK: form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monthRow
                Text("Balances").sectionLabel().padding(.top, 22)
                status
                if isNew {
                    GeometryReader { g in
                        Capsule().fill(Color.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [.g1, .g2], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * CGFloat(doneCount) / CGFloat(max(1, accs.count)))
                            }
                    }
                    .frame(height: 5).padding(.horizontal, 4).padding(.bottom, 10)
                    .animation(.spring(duration: 0.4), value: doneCount)
                }
                VStack(spacing: 0) {
                    ForEach(accs) { a in
                        row(a)
                        Divider().padding(.leading, 66)
                    }
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
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
                if isNew, accs.count - doneCount > 1, doneCount > 0 {
                    Button("Mark rest unchanged") { markRest() }.buttonStyle(GhostButton()).padding(.top, 12)
                }
                totalRow.padding(.top, 20)
                Button("Save \(Month.long(month))", action: save).buttonStyle(PrimaryButton()).padding(.top, 16)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
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

    @ViewBuilder private var status: some View {
        HStack {
            if !isNew { Text("Saved values") }
            else {
                Text(blank ? "Blank" : carriedFrom.map { "From \(store.label($0))" } ?? "")
                + Text(blank || carriedFrom != nil ? " · " : "")
                + Text(doneCount == accs.count ? "All checked" : "\(doneCount)/\(accs.count) checked").fontWeight(.semibold).foregroundStyle(.white)
                Spacer()
                if carriedFrom != nil && !blank {
                    Button("Clear all") { accs.forEach { text[$0.id] = "" }; done = []; blank = true }.font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .font(.system(size: 13)).foregroundStyle(Color.sec).padding(.horizontal, 4).padding(.bottom, 8)
    }

    private func row(_ a: Account) -> some View {
        let t = Catalog.type(a.type), ok = isNew && done.contains(a.id)
        return HStack(spacing: 10) {
            Avatar(symbol: Catalog.symbol(for: a), color: t.color, grad: t.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.system(size: 15, weight: .medium)).lineLimit(2)
                hint(a).font(.system(size: 12)).foregroundStyle(Color.sec).lineLimit(1).masked()
            }
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                Text(Currency.symbol[a.cur] ?? a.cur).foregroundStyle(Color.sec)
                TextField("0", text: Binding(get: { text[a.id] ?? "" }, set: { v in text[a.id] = v; if isNew, focus == a.id { done.insert(a.id) } }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    .focused($focus, equals: a.id)
                    .frame(minWidth: 70, maxWidth: 110)
            }
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .masked()
            if isNew {
                Button { toggle(a) } label: {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ok ? .white : Color.sec)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(ok ? AnyShapeStyle(LinearGradient(colors: [.g1, .g2], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.08))))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .sensoryFeedback(.selection, trigger: ok)
                .accessibilityLabel("Unchanged: \(a.name)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onChange(of: focus) { old, new in
            if new == a.id, let v = value(a.id) { text[a.id] = EntrySheet.fmt(v) }          // plain while typing
            if old == a.id, new != a.id { text[a.id] = value(a.id).map { Self.show($0, a.cur) } ?? "" }  // formatted again
        }
    }

    private func hint(_ a: Account) -> Text {
        let t = Catalog.type(a.type)
        guard let last = store.lastRecorded(a, before: month) else { return Text((a.platform.isEmpty ? t.name : a.platform) + (t.liab ? " · owed" : "")) }
        var h = Text("\(Month.date(last.month).formatted(.dateTime.month(.abbreviated))): \(Money.format(last.value, a.cur))")
        if let v = value(a.id), abs(v - last.value) >= 0.005 {
            let d = v - last.value, good = t.liab ? d < 0 : d > 0
            h = h + Text(" · ") + Text((d > 0 ? "+" : "−") + Money.format(abs(d), a.cur)).foregroundStyle(good ? Color.up : Color.down)
            if let s = sugg[a.id], abs(v - s) < 0.005, let dp = a.dep ?? t.dep, dp != 0 { h = h + Text(" (\(dp > 0 ? "+" : "−")\(EntrySheet.fmt(abs(dp)))%/yr)") }
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

    private var doneCount: Int { accs.filter { done.contains($0.id) }.count }
    private func value(_ id: String) -> Double? { EntrySheet.parse(text[id] ?? "") }
    static func show(_ v: Double, _ cur: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        f.locale = Locale(identifier: Currency.locale[cur] ?? "en_IE")
        return f.string(from: NSNumber(value: v)) ?? EntrySheet.fmt(v)
    }

    /// A recorded month shows its own values; a new month (or the current month before its check-in) starts from the
    /// last one, with depreciation applied.
    private func fill() {
        let cm = Month.key(), snap = store.data.snaps[month]
        isNew = month == cm ? store.data.lastCheckin != cm : snap == nil
        done = []; sugg = [:]; carriedFrom = nil; blank = false; text = [:]
        for a in accs {
            var v: Double?
            if !isNew, let snap { v = snap.items[a.id]?.bal ?? (month == cm ? a.bal : nil) }
            else {
                let c = store.carried(a, to: month); v = c.value
                if let cv = c.value { sugg[a.id] = cv }
                if let f = c.from, carriedFrom == nil || f > carriedFrom! { carriedFrom = f }
            }
            text[a.id] = v.map { Self.show($0, a.cur) } ?? ""
        }
    }

    /// Tick: unchanged (or the suggested value for things that lose or gain value); tap again to untick.
    private func toggle(_ a: Account) {
        if done.contains(a.id) { done.remove(a.id) }
        else { done.insert(a.id); if value(a.id) == nil, let s = sugg[a.id] { text[a.id] = Self.show(s, a.cur) } }
    }
    private func markRest() {
        for a in accs where !done.contains(a.id) { done.insert(a.id); if value(a.id) == nil, let s = sugg[a.id] { text[a.id] = Self.show(s, a.cur) } }
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
