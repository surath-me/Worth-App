import Foundation

/// The whole app state, in exactly the shape the web app keeps in localStorage (`worth.v1`) and writes to a backup
/// file. Keeping the same shape means a web backup imports as-is, and a native backup opens in the web app.
struct WorthData: Codable, Equatable {
    var v: Int = 1
    /// Totals are shown in this currency.
    var base: String = "EUR"
    /// Units of each currency per 1 EUR.
    var rates: [String: Double] = Currency.defaultRates
    var ratesAt: Double? = nil
    var ratesSrc: String? = nil
    var accounts: [Account] = []
    /// One record per month, keyed "YYYY-MM".
    var snaps: [String: Snap] = [:]
    var lastCheckin: String? = nil
    var updatedAt: Double = 0
    var backupAt: Double? = nil

    init() {}

    // Lenient decoding: missing or odd fields fall back to defaults instead of failing the whole import.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decode(Int.self, forKey: .v)) ?? 1
        base = (try? c.decode(String.self, forKey: .base)).flatMap { Currency.all.contains($0) ? $0 : nil } ?? "EUR"
        let r = (try? c.decode([String: Double].self, forKey: .rates)) ?? [:]
        rates = Currency.defaultRates.merging(r) { _, new in new }
        ratesAt = try? c.decode(Double.self, forKey: .ratesAt)
        ratesSrc = try? c.decode(String.self, forKey: .ratesSrc)
        accounts = (try? c.decode([Account].self, forKey: .accounts)) ?? []
        snaps = (try? c.decode([String: Snap].self, forKey: .snaps)) ?? [:]
        lastCheckin = try? c.decode(String.self, forKey: .lastCheckin)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        backupAt = try? c.decode(Double.self, forKey: .backupAt)
    }
}

/// One entry: a bank account, a fund, a home, a loan… Debts (`liab` types) hold the positive amount owed.
struct Account: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var type: String
    var platform: String = ""
    var cur: String
    var bal: Double
    /// Yearly value change in % (physical assets), applied when a month is carried over.
    var dep: Double? = nil
    /// An icon picked instead of the type's own (a Material Symbols name in the web app; mapped to an SF Symbol here).
    var icon: String? = nil

    init(id: String = Account.newID(), name: String, type: String, platform: String = "", cur: String, bal: Double, dep: Double? = nil, icon: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.platform = platform; self.cur = cur; self.bal = bal; self.dep = dep; self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? "other"
        platform = (try? c.decode(String.self, forKey: .platform)) ?? ""
        cur = (try? c.decode(String.self, forKey: .cur)) ?? "EUR"
        bal = c.flexibleDouble(.bal) ?? 0
        dep = c.flexibleDouble(.dep)
        icon = try? c.decode(String.self, forKey: .icon)
    }

    static func newID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in chars.randomElement()! }) + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36).suffix(4)
    }
}

/// A month's record: every entry's balance, currency, type and name, plus that month's exchange rates.
struct Snap: Codable, Equatable {
    var items: [String: SnapItem]
    var rates: [String: Double]?
}

/// Stored as a JSON array `[balance, currency, type, name]`, like the web app.
struct SnapItem: Codable, Equatable {
    var bal: Double
    var cur: String
    var type: String
    var name: String?

    init(bal: Double, cur: String, type: String, name: String?) { self.bal = bal; self.cur = cur; self.type = type; self.name = name }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        if let d = try? c.decode(Double.self) { bal = d }
        else if let s = try? c.decode(String.self) { bal = Double(s) ?? 0 }
        else { bal = 0 }
        cur = (try? c.decode(String.self)) ?? "EUR"
        type = (try? c.decode(String.self)) ?? "other"
        name = try? c.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(bal); try c.encode(cur); try c.encode(type)
        if let name { try c.encode(name) }
    }
}

private extension KeyedDecodingContainer {
    /// A number that may have been saved as a string (older web data).
    func flexibleDouble(_ key: Key) -> Double? {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

/// Month keys ("2026-11") and labels.
enum Month {
    static func key(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }
    static func date(_ k: String) -> Date {
        let p = k.split(separator: "-").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(year: p.first, month: p.count > 1 ? p[1] : 1, day: 1)) ?? Date()
    }
    static func index(_ k: String) -> Int {
        let p = k.split(separator: "-").compactMap { Int($0) }
        return (p.first ?? 0) * 12 + ((p.count > 1 ? p[1] : 1) - 1)
    }
    static func shift(_ k: String, by n: Int) -> String {
        key(Calendar.current.date(byAdding: .month, value: n, to: date(k)) ?? Date())
    }
    static func long(_ k: String) -> String { date(k).formatted(.dateTime.month(.wide).year()) }
    static func short(_ k: String) -> String { date(k).formatted(.dateTime.month(.abbreviated).year()) }
    static func name(_ k: String) -> String { date(k).formatted(.dateTime.month(.wide)) }
}
