import Foundation
import Observation

/// Holds the app state, saves it to a JSON file on every change, and has the same sums as the web app.
@Observable
final class Store {
    var data: WorthData { didSet { save() } }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("worth.v1.json")
    }

    init() {
        if let raw = try? Data(contentsOf: Store.fileURL), let d = try? JSONDecoder().decode(WorthData.self, from: raw) {
            data = d
        } else {
            data = WorthData()
        }
    }

    /// Writes happen off the main thread, one after another in order, so a long history never stalls an animation.
    private static let io = DispatchQueue(label: "worth.save", qos: .utility)
    private func save() {
        let snapshot = data
        Store.io.async {
            guard let raw = try? JSONEncoder().encode(snapshot) else { return }
            try? raw.write(to: Store.fileURL, options: .atomic)
        }
    }

    var isEmpty: Bool { data.accounts.isEmpty && data.snaps.isEmpty }

    // MARK: money

    /// `amount` in `cur`, converted to `base` with the given rates (units per 1 EUR).
    func conv(_ amount: Double, _ cur: String, rates: [String: Double]? = nil, base: String? = nil) -> Double {
        let r = rates ?? data.rates, b = base ?? data.base
        let rc = r[cur] ?? data.rates[cur] ?? 1, rb = r[b] ?? data.rates[b] ?? 1
        return amount / rc * rb
    }
    private func sign(_ type: String) -> Double { Catalog.isLiab(type) ? -1 : 1 }

    var liveTotal: Double { data.accounts.reduce(0) { $0 + sign($1.type) * conv($1.bal, $1.cur) } }
    var liveDebts: Double { data.accounts.reduce(0) { $0 + (Catalog.isLiab($1.type) ? conv($1.bal, $1.cur) : 0) } }

    func total(of snap: Snap) -> Double {
        snap.items.values.reduce(0) { $0 + sign($1.type) * conv($1.bal, $1.cur, rates: snap.rates ?? data.rates) }
    }

    /// Every recorded month, oldest first.
    var series: [(month: String, value: Double)] {
        data.snaps.keys.sorted().map { ($0, total(of: data.snaps[$0]!)) }
    }

    // MARK: groups (same rules as the web app's splitGroups)

    struct GroupTotal: Identifiable { let group: Catalog.Group; let value: Double; var id: String { group.id } }
    struct Split { var groups: [GroupTotal]; var debts: Double; var netted: Bool }

    /// A mortgage is set against property, so Property shows your equity, as long as the property is worth more than
    /// what's owed; otherwise the mortgage stays a plain debt. Groups minus debts always equals net worth.
    func split(_ rows: [(type: String, v: Double)], gross: Bool = false) -> Split {
        var by: [String: Double] = [:]; var mort = 0.0, debts = 0.0
        for r in rows {
            let v = max(0, r.v)
            if r.type == "mortgage" { mort += v }
            else if Catalog.isLiab(r.type) { debts += v }
            else { by[Catalog.group(of: r.type).id, default: 0] += v }
        }
        let prop = by["property"] ?? 0, netted = !gross && mort > 0 && prop > mort
        if netted { by["property"] = prop - mort } else { debts += mort }
        return Split(groups: Catalog.groups.filter { !$0.liab }.map { GroupTotal(group: $0, value: by[$0.id] ?? 0) }, debts: debts, netted: netted)
    }
    var liveSplit: Split { split(data.accounts.map { ($0.type, conv($0.bal, $0.cur)) }) }

    /// The entries listed under a group: a netted mortgage sits with Property, every other debt under Debts.
    func accounts(in g: Catalog.Group) -> [Account] {
        let netted = liveSplit.netted
        return data.accounts.filter { a in
            if a.type == "mortgage" { return g.id == (netted ? "property" : "debt") }
            return Catalog.group(of: a.type).id == g.id
        }.sorted { conv($0.bal, $0.cur) > conv($1.bal, $1.cur) }
    }

    // MARK: changes

    /// The current month's record always mirrors today's balances.
    private func syncCurrentMonth(_ d: inout WorthData) {
        let m = Month.key()
        if d.accounts.isEmpty { d.snaps[m] = nil; return }
        var items: [String: SnapItem] = [:]
        for a in d.accounts { items[a.id] = SnapItem(bal: a.bal, cur: a.cur, type: a.type, name: a.name) }
        d.snaps[m] = Snap(items: items, rates: d.rates)
    }

    /// One change, saved once: edits run on a copy, the current month is synced, then it's written back.
    func commit(keepMonth: Bool = false, _ change: (inout WorthData) -> Void) {
        var d = data
        change(&d)
        if !keepMonth { syncCurrentMonth(&d) }
        d.updatedAt = Date().timeIntervalSince1970 * 1000
        data = d
    }

    func upsert(_ a: Account) {
        commit { d in
            if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { d.accounts[i] = a } else { d.accounts.append(a) }
        }
    }
    func delete(_ a: Account) { commit { $0.accounts.removeAll { $0.id == a.id } } }
    func setBase(_ c: String) { commit(keepMonth: true) { $0.base = c } }
    func eraseAll() { let base = data.base; commit(keepMonth: true) { d in d = WorthData(); d.base = base } }

    // MARK: backup

    enum BackupError: LocalizedError { case notWorth; var errorDescription: String? { "That file isn’t a Worth backup" } }

    func restore(_ raw: Data) throws {
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any], obj["accounts"] is [Any] else { throw BackupError.notWorth }
        let d = try JSONDecoder().decode(WorthData.self, from: raw)
        data = d
    }
    func backupData() -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(data)) ?? Data()
    }
    func markBackedUp() { commit(keepMonth: true) { $0.backupAt = Date().timeIntervalSince1970 * 1000 } }

    #if DEBUG
    /// Development only: a year of sample data (made by the web app's dev/sample-data.js), moved so its last month is now.
    func loadSample() {
        guard let url = Bundle.main.url(forResource: "DevSample", withExtension: "json"),
              let raw = try? Data(contentsOf: url), var d = try? JSONDecoder().decode(WorthData.self, from: raw),
              let last = d.snaps.keys.max() else { return }
        let shift = Month.index(Month.key()) - Month.index(last)
        if shift != 0 { d.snaps = Dictionary(uniqueKeysWithValues: d.snaps.map { (Month.shift($0.key, by: shift), $0.value) }) }
        d.lastCheckin = Month.key()
        if data.ratesSrc != nil { d.rates = data.rates; d.ratesAt = data.ratesAt; d.ratesSrc = data.ratesSrc } // keep live rates
        d.base = data.base
        syncCurrentMonth(&d) // the current month takes today's live rates, like any other change
        d.updatedAt = Date().timeIntervalSince1970 * 1000
        data = d // one write
    }
    #endif

    // MARK: live exchange rates (same sources as the web app)

    private var ratesBusy = false
    static let ratesTTL: Double = 30 * 60 * 1000

    @MainActor
    func fetchRates(force: Bool = false) async {
        let now = Date().timeIntervalSince1970 * 1000
        if ratesBusy { return }
        if !force, let at = data.ratesAt, data.ratesSrc != nil, now - at < Store.ratesTTL { return }
        ratesBusy = true; defer { ratesBusy = false }
        // a source counts only when it has every currency; otherwise the next one is tried
        var next: [String: Double]? = nil, src = ""
        if let r = Store.complete(await Store.coinbase()) { next = r; src = "coinbase" }
        else if let r = Store.complete(await Store.erAPI()) { next = r; src = "er-api" }
        guard let next else { return }
        commit(keepMonth: data.accounts.isEmpty) { d in
            d.rates.merge(next) { _, n in n }; d.ratesAt = now; d.ratesSrc = src
        }
    }
    /// The rates Worth needs (per 1 EUR), or nil when any is missing.
    private static func complete(_ raw: [String: Double]?) -> [String: Double]? {
        guard let raw else { return nil }
        var out = ["EUR": 1.0]
        for c in Currency.all where c != "EUR" { guard let v = raw[c], v > 0 else { return nil }; out[c] = v }
        return out
    }
    private static func coinbase() async -> [String: Double]? {
        struct R: Decodable { struct D: Decodable { let rates: [String: String] }; let data: D }
        guard let url = URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=EUR"),
              let (raw, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(R.self, from: raw) else { return nil }
        return r.data.rates.compactMapValues(Double.init)
    }
    private static func erAPI() async -> [String: Double]? {
        struct R: Decodable { let result: String; let rates: [String: Double] }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/EUR"),
              let (raw, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(R.self, from: raw), r.result == "success" else { return nil }
        return r.rates
    }
}

/// Money formatting in each currency's own style; whole units except for tiny amounts, like the web app.
enum Money {
    private static var cache: [String: NumberFormatter] = [:]
    static func format(_ v: Double, _ cur: String, decimals: Int? = nil) -> String {
        let dec = decimals ?? ((abs(v) >= 10 || v == 0) ? 0 : 2)
        let key = cur + String(dec)
        let f: NumberFormatter
        if let c = cache[key] { f = c } else {
            f = NumberFormatter()
            f.numberStyle = .currency
            f.locale = Locale(identifier: Currency.locale[cur] ?? "en_IE")
            f.currencyCode = cur
            f.minimumFractionDigits = dec; f.maximumFractionDigits = dec
            cache[key] = f
        }
        return f.string(from: NSNumber(value: v)) ?? "\(v) \(cur)"
    }
    static func signed(_ v: Double, _ cur: String) -> String { (v >= 0 ? "+" : "−") + format(abs(v), cur) }
}
