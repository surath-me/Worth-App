import SwiftUI
import Charts

/// One month at a time (‹ November 2026 ›, or swipe): its total and change, one action (check in or edit), what moved
/// since the month before (exchange rates on their own line), the unchanged entries folded away, allocation, and
/// "Remove <month>" at the very bottom.
struct MonthlyView: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    @Environment(\.openOnboarding) private var openOnboarding
    @State private var month = Month.key()
    @State private var dir: Edge = .trailing
    @State private var checkIn: String?
    @State private var editing: Account?
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switcher
                    Group {
                        if store.isEmpty {
                            emptyCard("Nothing recorded yet.")
                            Button("Get started") { openOnboarding() }.buttonStyle(PrimaryButton()).padding(.top, 16)
                        } else if store.data.snaps[month] == nil {
                            emptyCard("Not recorded yet.")
                            Button("Start \(Month.name(month))") { checkIn = month }.buttonStyle(PrimaryButton()).padding(.top, 16)
                        } else {
                            detail
                        }
                    }
                    .id(month)
                    .transition(.asymmetric(insertion: .move(edge: dir).combined(with: .opacity), removal: .opacity))
                    if !store.isEmpty { Allocation(month: month).padding(.top, 26) }
                    if store.data.snaps[month] != nil {
                        Button("Remove \(Month.long(month))", role: .destructive) { confirmRemove = true }
                            .font(.system(size: 15)).foregroundStyle(Color.down.opacity(0.9))
                            .frame(maxWidth: .infinity).padding(.top, 28)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(Aura())
            .navigationTitle("Monthly")
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in // sideways only; vertical scrolling stays normal
                guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                step(v.translation.width < 0 ? 1 : -1)
            })
            .sheet(item: Binding(get: { checkIn.map(TypeChoice.init) }, set: { checkIn = $0?.id })) { CheckInSheet(start: $0.id) { month = $0 } }
            .sheet(item: $editing) { EntrySheet(account: $0) }
            .confirmationDialog("Remove \(Month.long(month))?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { store.removeMonth(month) }
            } message: { Text("Its balances are deleted. Your entries stay.") }
        }
    }

    // MARK: parts

    private var switcher: some View {
        let ms = store.monthList, i = ms.firstIndex(of: month) ?? ms.count - 1
        return HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40) }
                .disabled(i <= 0)
            Spacer()
            Text(Month.long(month)).font(.system(size: 17, weight: .semibold)).contentTransition(.numericText())
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40) }
                .disabled(i >= ms.count - 1)
        }
        .tint(.white)
        .padding(.bottom, 10)
    }

    private func step(_ d: Int) {
        let ms = store.monthList
        guard let i = ms.firstIndex(of: month), ms.indices.contains(i + d) else { return }
        dir = d > 0 ? .trailing : .leading
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { month = ms[i + d] }
    }

    private func emptyCard(_ t: String) -> some View {
        Text(t).font(.system(size: 15)).foregroundStyle(Color.sec)
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder private var detail: some View {
        let snap = store.data.snaps[month]!
        let v = store.total(of: snap), pm = store.prevKey(month)
        let due = month == Month.key() && store.data.lastCheckin != month
        VStack(alignment: .leading, spacing: 4) {
            Text(Money.format(v, store.data.base, decimals: 0)).font(.system(size: 34, weight: .bold)).monospacedDigit().masked()
            if let pm, let ps = store.data.snaps[pm] {
                let pv = store.total(of: ps)
                ChangeLabel(change: v - pv, from: pv, cur: store.data.base, suffix: "  vs " + store.vsLabel(month, pm)).masked()
            } else {
                Text("First month on record").font(.system(size: 15)).foregroundStyle(Color.sec)
            }
        }
        if due {
            Button("Check in for \(Month.name(month))") { checkIn = month }.buttonStyle(PrimaryButton()).padding(.top, 16)
        } else {
            Button { checkIn = month } label: { Label("Edit \(Month.name(month))", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(GhostButton()).padding(.top, 16)
        }
        MovedList(month: month, due: due, onOpen: { editing = $0 }).padding(.top, 22)
    }
}

/// That month's story, not a ledger: what moved since the previous record (biggest effect first, new and no-longer-
/// recorded entries too), what exchange rates did to foreign balances, and the rest folded into "N unchanged".
private struct MovedList: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    let month: String
    let due: Bool
    let onOpen: (Account) -> Void

    struct Row: Identifiable {
        let id: String; let bal: Double; let cur: String; let type: String; let name: String
        let acc: Account?; var prevBal: Double?; var same = false; var gone = false; var changed = false; var impact = 0.0; var v = 0.0
    }

    var body: some View {
        let snap = store.data.snaps[month]!, pm = store.prevKey(month), ps = pm.flatMap { store.data.snaps[$0] }
        let rates = snap.rates ?? store.data.rates, prates = ps?.rates ?? store.data.rates
        let rows = makeRows(snap, ps, rates, prates)
        VStack(alignment: .leading, spacing: 0) {
            if ps == nil {
                Text("Entries").sectionLabel()
                card(rows.sorted(by: byValue).map { AnyView(row($0, change: nil)) })
            } else {
                let moved = rows.filter(\.changed).sorted { abs($0.impact) > abs($1.impact) }
                let still = rows.filter { !$0.changed }.sorted(by: byValue)
                let fx = fxEffect(rows, rates, prates)
                Text("Since \(store.vsLabel(month, pm!))").sectionLabel()
                let views = moved.map { AnyView(row($0, change: changeText($0))) } + (abs(fx.total) >= 1 ? [AnyView(fxRow(fx.total, fx.curs))] : [])
                if views.isEmpty { card([AnyView(Text("No changes").font(.system(size: 15)).foregroundStyle(Color.sec).frame(maxWidth: .infinity).padding(.vertical, 18))]) }
                else { card(views) }
                if !still.isEmpty {
                    Button { withAnimation(.spring(duration: 0.45, bounce: 0.1)) { prefs.unchangedOpen.toggle() } } label: {
                        HStack(spacing: 6) {
                            Text("\(still.count) \(due ? "to update" : "unchanged")")
                            Image(systemName: "chevron.down").rotationEffect(.degrees(prefs.unchangedOpen ? 180 : 0))
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.sec).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if prefs.unchangedOpen { card(still.map { AnyView(row($0, change: nil)) }).transition(.opacity.combined(with: .move(edge: .top))) }
                }
            }
        }
    }

    /// What the month's rates did to foreign balances, counted on last month's balance for every foreign entry (changed
    /// or not), so the rows plus this line add up to the month's change.
    private func fxEffect(_ rows: [Row], _ rates: [String: Double], _ prates: [String: Double]) -> (total: Double, curs: [String]) {
        var fx = 0.0, curs = Set<String>()
        for a in rows where a.same && a.cur != store.data.base {
            guard let pb = a.prevBal else { continue }
            let d = (Catalog.isLiab(a.type) ? -1 : 1) * (store.conv(pb, a.cur, rates: rates) - store.conv(pb, a.cur, rates: prates))
            if abs(d) >= 0.5 { fx += d; curs.insert(a.cur) }
        }
        return (fx, curs.sorted())
    }

    private func byValue(_ x: Row, _ y: Row) -> Bool {
        (Catalog.isLiab(x.type) ? 1 : 0, -x.v) < (Catalog.isLiab(y.type) ? 1 : 0, -y.v)
    }

    private func makeRows(_ snap: Snap, _ ps: Snap?, _ rates: [String: Double], _ prates: [String: Double]) -> [Row] {
        var out: [Row] = snap.items.map { id, it in
            let acc = store.data.accounts.first { $0.id == id }, prev = ps?.items[id]
            let sg: Double = Catalog.isLiab(it.type) ? -1 : 1, v = store.conv(it.bal, it.cur, rates: rates)
            let same = prev != nil && prev!.cur == it.cur, pb = same ? prev!.bal : nil
            let changed = ps != nil && (!same || abs(it.bal - (pb ?? 0)) >= 0.005)
            let impact: Double = ps == nil ? 0 : same ? sg * (v - store.conv(pb!, it.cur, rates: rates))
                : sg * v - (prev.map { (Catalog.isLiab($0.type) ? -1 : 1) * store.conv($0.bal, $0.cur, rates: prates) } ?? 0)
            return Row(id: id, bal: it.bal, cur: it.cur, type: it.type, name: acc?.name ?? it.name ?? "Removed entry", acc: acc,
                       prevBal: pb, same: same, changed: changed, impact: impact, v: v)
        }
        if let ps {
            for (id, it) in ps.items where snap.items[id] == nil {
                let acc = store.data.accounts.first { $0.id == id }
                out.append(Row(id: id, bal: it.bal, cur: it.cur, type: it.type, name: acc?.name ?? it.name ?? "Removed entry", acc: acc,
                               gone: true, changed: true, impact: -(Catalog.isLiab(it.type) ? -1 : 1) * store.conv(it.bal, it.cur, rates: prates),
                               v: store.conv(it.bal, it.cur, rates: prates)))
            }
        }
        return out
    }

    private func changeText(_ a: Row) -> Text {
        if a.gone { return Text(a.acc != nil ? "Not recorded" : "Removed").foregroundStyle(Color.sec) }
        if !a.same { return Text("New").foregroundStyle(Color.sec) }
        let d = a.bal - (a.prevBal ?? 0), liab = Catalog.isLiab(a.type), good = liab ? d < 0 : d > 0
        let txt = liab ? "\(Money.format(abs(d), a.cur)) \(d < 0 ? "paid off" : "more owed")" : Money.signed(d, a.cur)
        return Text(txt).foregroundStyle(good ? Color.up : Color.down)
    }

    private func card(_ views: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(views.indices, id: \.self) { i in
                views[i].padding(.horizontal, 14).padding(.vertical, 10)
                if i < views.count - 1 { Divider().padding(.leading, 66) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func row(_ a: Row, change: Text?) -> some View {
        let t = Catalog.type(a.type)
        let sub = (a.acc?.platform.isEmpty == false ? a.acc!.platform : t.name) + (t.liab ? " · owed" : "")
            + (a.cur != store.data.base && !a.gone ? " · ≈ " + Money.format(a.v, store.data.base, decimals: 0) : "")
        return Button { if let acc = a.acc, !a.gone { onOpen(acc) } } label: {
            HStack(spacing: 12) {
                Avatar(symbol: a.acc.map(Catalog.symbol(for:)) ?? Catalog.safeSymbol(t.symbol), color: t.color, grad: t.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Text(sub).font(.system(size: 13)).foregroundStyle(Color.sec).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text((t.liab ? "−" : "") + Money.format(a.bal, a.cur)).font(.system(size: 15, weight: .medium)).monospacedDigit()
                    if let change { change.font(.system(size: 13, weight: .medium)).monospacedDigit() }
                }
                .masked()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(a.acc == nil || a.gone)
    }

    private func fxRow(_ fx: Double, _ curs: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.g1)
                .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Exchange rates").font(.system(size: 15, weight: .medium))
                Text(curs.joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(Color.sec)
            }
            Spacer()
            Text(Money.signed(fx, store.data.base)).font(.system(size: 15, weight: .medium)).monospacedDigit()
                .foregroundStyle(fx > 0 ? Color.up : Color.down).masked()
        }
    }
}

/// Allocation for the month shown: that month's record, or today's balances for the current month before it's
/// recorded. Pie (a ring with net worth in the middle) or bars; debts listed under it and subtracted.
struct Allocation: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    let month: String

    var body: some View {
        let snap = store.data.snaps[month]
        let rows = snap.map { store.rows(of: $0) } ?? (month == Month.key() ? store.liveRows : [])
        let sp = store.split(rows), groups = sp.groups.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let owned = max(1, groups.reduce(0) { $0 + $1.value }), net = owned - sp.debts
        if !groups.isEmpty || sp.debts > 0 {
            @Bindable var prefs = prefs
            VStack(alignment: .leading, spacing: 0) {
                Text("Allocation").sectionLabel()
                VStack(spacing: 14) {
                    Picker("View", selection: $prefs.allocBar) { Text("Pie").tag(false); Text("Bar").tag(true) }.pickerStyle(.segmented)
                    if !prefs.allocBar {
                        ZStack {
                            Chart(groups) { g in
                                SectorMark(angle: .value("Value", g.value), innerRadius: .ratio(0.72), angularInset: 1.5)
                                    .foregroundStyle(g.group.color).cornerRadius(3)
                            }
                            .frame(height: 200)
                            VStack(spacing: 2) {
                                Text(Money.format(net, store.data.base, decimals: 0)).font(.system(size: 20, weight: .bold)).monospacedDigit().masked()
                                Text("Net worth").font(.system(size: 12)).foregroundStyle(Color.sec)
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(groups) { g in
                            let pct = g.value / owned * 100
                            VStack(spacing: 6) {
                                HStack {
                                    Circle().fill(g.group.color).frame(width: 9, height: 9)
                                    Text(g.group.id == "property" && sp.netted ? "Property equity" : g.group.name).font(.system(size: 15))
                                    Spacer()
                                    Text(pct > 0 && pct < 1 ? "<1%" : "\(Int(pct.rounded()))%").font(.system(size: 13)).foregroundStyle(Color.sec).monospacedDigit()
                                    Text(Money.format(g.value, store.data.base, decimals: 0)).font(.system(size: 15, weight: .medium)).monospacedDigit()
                                        .frame(minWidth: 84, alignment: .trailing).masked()
                                }
                                if prefs.allocBar {
                                    GeometryReader { geo in
                                        Capsule().fill(Color.white.opacity(0.08))
                                            .overlay(alignment: .leading) { Capsule().fill(g.group.color).frame(width: geo.size.width * g.value / (groups.first?.value ?? 1)) }
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                        if sp.debts > 0 {
                            HStack {
                                Circle().fill(Catalog.groups.last!.color).frame(width: 9, height: 9)
                                Text("Debts").font(.system(size: 15)); Spacer()
                                Text("−" + Money.format(sp.debts, store.data.base, decimals: 0)).font(.system(size: 15, weight: .medium)).monospacedDigit().masked()
                            }
                            Divider()
                            HStack {
                                Text("Net worth").font(.system(size: 15, weight: .semibold)); Spacer()
                                Text(Money.format(net, store.data.base, decimals: 0)).font(.system(size: 15, weight: .semibold)).monospacedDigit().masked()
                            }
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
                .animation(.spring(duration: 0.4), value: prefs.allocBar)
            }
        }
    }
}
