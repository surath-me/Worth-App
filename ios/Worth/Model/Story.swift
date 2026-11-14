import Foundation

/// The logic behind the story the app tells: comparisons over a range, a new high or a run of up months, what moved,
/// carrying a month over, and saving a check-in. Same rules as the web app (index.html: renderInsight, setDelta,
/// rangeLabel, carried, updateSheet's doSave, the reveal).
extension Store {
    struct Point: Identifiable, Equatable { let month: String; let value: Double; var id: String { month }; var x: Int { Month.index(month) } }

    var points: [Point] { series.map { Point(month: $0.month, value: $0.value) } }

    /// The months shown for a range (0 = all), counted back from this month.
    func points(range: Int) -> [Point] {
        let all = points
        guard range > 0 else { return all }
        let from = Month.index(Month.key()) - range
        return all.filter { $0.x >= from }
    }

    /// "vs October", "in 6 months", "in the past year", "since Mar 2025".
    func rangeLabel(ref: Point, range: Int) -> String {
        let n = Month.index(Month.key()) - ref.x
        if n == 1 { return "vs " + Month.name(ref.month) }
        if range == 12 && n == 12 { return "in the past year" }
        if range > 0 && n == range { return "in \(n) months" }
        return "since " + Month.short(ref.month)
    }

    // MARK: groups over time

    func rows(of snap: Snap) -> [(type: String, v: Double)] {
        snap.items.values.map { ($0.type, conv($0.bal, $0.cur, rates: snap.rates ?? data.rates)) }
    }
    var liveRows: [(type: String, v: Double)] { data.accounts.map { ($0.type, conv($0.bal, $0.cur)) } }

    struct Move: Identifiable { let name: String; let groupID: String; let change: Double; var debt = false; var id: String { groupID } }

    /// What moved between two sets of balances, by group. Compared gross (the mortgage as a plain debt), so a property
    /// crossing its mortgage doesn't read as a debt change; paying debt down counts as a gain.
    func moves(from a: [(type: String, v: Double)], to b: [(type: String, v: Double)]) -> [Move] {
        let sa = split(a, gross: true), sb = split(b, gross: true)
        var out = zip(sa.groups, sb.groups).map { Move(name: $1.group.name, groupID: $1.group.id, change: $1.value - $0.value) }
        out.append(Move(name: "Debts", groupID: "debt", change: sa.debts - sb.debts, debt: true))
        return out.filter { abs($0.change) >= 1 }.sorted { abs($0.change) > abs($1.change) }
    }

    /// "New high" when today beats every earlier month, else "N months up" for a run of 3+ rising months.
    func streakBadge(total: Double, month: String = Month.key()) -> String? {
        let others = points.filter { $0.month != month }
        if others.count >= 2, total > (others.map(\.value).max() ?? 0) + 0.5 { return "New high" }
        var vs = points.filter { $0.month < month }.map { ($0.x, $0.value) }
        vs.append((Month.index(month), total))
        var run = 0, i = vs.count - 1
        while i > 0, vs[i].0 - vs[i - 1].0 == 1, vs[i].1 > vs[i - 1].1 + 0.5 { run += 1; i -= 1 }
        return run >= 3 ? "\(run) months up" : nil
    }

    /// The one line under the change: a new high or a run of up months, and what moved most since the range's start.
    func insight(total: Double, ref: Point?) -> (badge: String?, move: String?) {
        let badge = streakBadge(total: total)
        var move: String? = nil
        if let ref, let snap = data.snaps[ref.month], let top = moves(from: rows(of: snap), to: liveRows).first {
            let amt = Money.format(abs(top.change), data.base, decimals: 0)
            move = top.debt ? "Debts \(top.change > 0 ? "−" : "+")\(amt)" : "\(top.name) \(top.change > 0 ? "+" : "−")\(amt)"
        }
        return (badge, move)
    }

    // MARK: months

    /// Every month with a record, plus the current month even before it has one.
    var monthList: [String] { Array(Set(data.snaps.keys).union([Month.key()])).sorted() }
    func prevKey(_ m: String) -> String? { data.snaps.keys.filter { $0 < m }.max() }
    func nextKey(_ m: String) -> String? { data.snaps.keys.filter { $0 > m }.min() }
    /// "October" when it's the month right before, else "Oct 2025".
    func vsLabel(_ m: String, _ prev: String) -> String { Month.index(m) - Month.index(prev) == 1 ? Month.name(prev) : Month.short(prev) }
    /// Month name alone in the current year, with the year otherwise.
    func label(_ m: String) -> String { Month.date(m).formatted(.dateTime.year()) == Date().formatted(.dateTime.year()) ? Month.name(m) : Month.short(m) }

    var checkInDue: Bool { !data.accounts.isEmpty && data.lastCheckin != Month.key() }

    /// The months 1, 3, 6 and 12 back that aren't recorded yet (the "Add past months" card).
    var backfillMonths: [String] {
        [1, 3, 6, 12].map { Month.shift(Month.key(), by: -$0) }.filter { data.snaps[$0] == nil }
    }

    func lastRecorded(_ a: Account, before m: String) -> (month: String, value: Double)? {
        for k in data.snaps.keys.sorted(by: >) where k < m { if let it = data.snaps[k]?.items[a.id] { return (k, it.bal) } }
        return nil
    }

    /// What to suggest for entry `a` in month `m` when `m` has no record of it yet: its value from the latest earlier
    /// month, moved by its yearly value change for the months in between.
    func carried(_ a: Account, to m: String) -> (value: Double?, from: String?) {
        let cm = Month.key()
        var from = data.snaps.keys.sorted(by: >).first { $0 < m && data.snaps[$0]?.items[a.id] != nil }
        var v: Double, gap = 0
        if m == cm {
            // the current balance already carries last month's value, unless it was edited since
            v = a.bal
            if let f = from, v == data.snaps[f]?.items[a.id]?.bal { gap = Month.index(m) - Month.index(f) }
        } else if let f = from {
            v = data.snaps[f]!.items[a.id]!.bal; gap = Month.index(m) - Month.index(f)
        } else if let later = data.snaps.keys.sorted().first(where: { $0 > m && data.snaps[$0]?.items[a.id] != nil }) {
            // filling in history before the first record: start from the nearest later month, value change undone
            from = later; v = data.snaps[later]!.items[a.id]!.bal; gap = Month.index(m) - Month.index(later)
        } else if m < cm {
            from = cm; v = a.bal; gap = Month.index(m) - Month.index(cm)
        } else { return (nil, nil) }
        if let dep = a.dep ?? Catalog.type(a.type).dep, dep != 0, gap != 0 {
            v = (v * pow(1 + dep / 100, Double(gap) / 12) * 100).rounded() / 100
        }
        return (v, from)
    }

    /// The rates a month is valued at: its own once recorded, today's for the current month.
    func rates(for m: String) -> [String: Double] { m != Month.key() ? (data.snaps[m]?.rates ?? data.rates) : data.rates }

    /// Save a check-in. The current month updates the live balances (and marks the check-in done); a past month
    /// writes its record and keeps the exchange rates it was saved with. Entries left blank are left out.
    func saveCheckIn(month m: String, values: [String: Double?]) {
        if m == Month.key() {
            commit { d in
                // a blank field keeps the entry's balance as it is (it never becomes 0)
                for i in d.accounts.indices { if let v = values[d.accounts[i].id] ?? nil { d.accounts[i].bal = abs(v) } }
                d.lastCheckin = m
            }
        } else {
            commit(keepMonth: true) { d in
                let old = d.snaps[m]
                var items: [String: SnapItem] = [:]
                if let old { for (id, it) in old.items where !d.accounts.contains(where: { $0.id == id }) { items[id] = it } }
                for a in d.accounts { if let v = values[a.id] ?? nil { items[a.id] = SnapItem(bal: abs(v), cur: a.cur, type: a.type, name: a.name) } }
                d.snaps[m] = items.isEmpty ? nil : Snap(items: items, rates: old?.rates ?? d.rates)
            }
        }
    }

    func removeMonth(_ m: String) {
        commit(keepMonth: true) { d in d.snaps[m] = nil; if m == Month.key() { d.lastCheckin = nil } }
    }

    /// First-run setup: create the entries, set the main currency, mark this month checked in.
    func finishSetup(base: String, entries: [Account]) {
        commit { d in d.base = base; d.accounts.append(contentsOf: entries); d.lastCheckin = Month.key() }
    }
}
