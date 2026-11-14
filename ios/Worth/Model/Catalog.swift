import SwiftUI

/// Currencies Worth knows, with their symbol and the locale whose number style they use (₹6,31,394 · 12’345 CHF).
enum Currency {
    static let all = ["EUR", "INR", "USD", "GBP", "CHF"]
    static let symbol: [String: String] = ["EUR": "€", "INR": "₹", "USD": "$", "GBP": "£", "CHF": "CHF"]
    static let locale: [String: String] = ["EUR": "en_IE", "INR": "en_IN", "USD": "en_US", "GBP": "en_GB", "CHF": "de_CH"]
    static let name: [String: String] = ["EUR": "Euro", "INR": "Indian rupee", "USD": "US dollar", "GBP": "British pound", "CHF": "Swiss franc"]
    /// Units per 1 EUR, used until the first live update.
    static let defaultRates: [String: Double] = ["EUR": 1, "INR": 110, "USD": 1.16, "GBP": 0.87, "CHF": 0.93]
}

/// An entry type. `liab`: a debt, entered as the positive amount owed and subtracted from net worth.
/// `dep`: physical assets get a default yearly value change (%).
struct EntryType: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    let symbol: String
    var liab = false
    var dep: Double? = nil
}

/// The same types, colours, groups and icons as the web app (index.html `TYPES` / `GROUPS` / `BGRAD` / `MI`).
enum Catalog {
    static let types: [EntryType] = [
        .init(id: "bank", name: "Savings", color: .hex(0x0A84FF), symbol: "bank"),
        .init(id: "deposit", name: "Fixed deposit", color: .hex(0x3D7BF5), symbol: "savings"),
        .init(id: "wallet", name: "E-wallet", color: .hex(0x30C48D), symbol: "account_balance_wallet"),
        .init(id: "stocks", name: "Stocks", color: .hex(0x5E5CE6), symbol: "stocks"),
        .init(id: "etf", name: "ETFs", color: .hex(0x14B8A6), symbol: "etf"),
        .init(id: "mf", name: "Mutual funds", color: .hex(0xFF9F0A), symbol: "mf"),
        .init(id: "bonds", name: "Bonds", color: .hex(0x38BDF8), symbol: "receipt_long"),
        .init(id: "rsu", name: "Employee shares", color: .hex(0x7D7AFF), symbol: "work"),
        .init(id: "gold", name: "Gold", color: .hex(0xE0A92E), symbol: "toll"),
        .init(id: "crypto", name: "Crypto", color: .hex(0xBF5AF2), symbol: "crypto"),
        .init(id: "pension", name: "Pension", color: .hex(0x30B0C7), symbol: "beach_access"),
        .init(id: "insurance", name: "Life insurance", color: .hex(0x4FA3D9), symbol: "health_and_safety"),
        .init(id: "cash", name: "Cash", color: .hex(0x34C759), symbol: "cash"),
        .init(id: "property", name: "Property", color: .hex(0xC79A3B), symbol: "property", dep: 0),
        .init(id: "vehicle", name: "Vehicle", color: .hex(0x64748B), symbol: "vehicle", dep: -15),
        .init(id: "valuables", name: "Valuables", color: .hex(0xA2845E), symbol: "valuables", dep: 0),
        .init(id: "business", name: "Business", color: .hex(0xAC8E68), symbol: "storefront"),
        .init(id: "lent", name: "Money lent", color: .hex(0x5AB8A8), symbol: "handshake"),
        .init(id: "other", name: "Other", color: .hex(0x8E8E93), symbol: "other"),
        .init(id: "mortgage", name: "Mortgage", color: .hex(0xE5484D), symbol: "mortgage", liab: true),
        .init(id: "loan", name: "Loan", color: .hex(0xF2555A), symbol: "loan", liab: true),
        .init(id: "carloan", name: "Car loan", color: .hex(0xEE5A5F), symbol: "directions_car", liab: true),
        .init(id: "student", name: "Student loan", color: .hex(0xF0606F), symbol: "school", liab: true),
        .init(id: "card", name: "Credit card", color: .hex(0xFF7A59), symbol: "card", liab: true),
        .init(id: "tax", name: "Tax owed", color: .hex(0xE8615A), symbol: "receipt", liab: true),
        .init(id: "otherdebt", name: "Other debt", color: .hex(0xD9505A), symbol: "request_quote", liab: true),
    ]
    static let type: [String: EntryType] = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
    static func type(_ k: String) -> EntryType { type[k] ?? type["other"]! }
    static func isLiab(_ k: String) -> Bool { type[k]?.liab ?? false }

    struct Group: Identifiable { let id: String; let name: String; let types: [String]; let color: Color; var liab = false }
    static let groups: [Group] = [
        .init(id: "savings", name: "Savings", types: ["bank", "deposit"], color: .hex(0x0A84FF)),
        .init(id: "cash", name: "Cash", types: ["cash", "wallet"], color: .hex(0x34C759)),
        .init(id: "inv", name: "Investments", types: ["etf", "stocks", "mf", "bonds", "rsu", "gold", "crypto"], color: .hex(0x14B8A6)),
        .init(id: "retire", name: "Retirement", types: ["pension", "insurance"], color: .hex(0x30B0C7)),
        .init(id: "property", name: "Property", types: ["property"], color: .hex(0xC79A3B)),
        .init(id: "more", name: "More", types: ["vehicle", "valuables", "business", "lent", "other"], color: .hex(0x64748B)),
        .init(id: "debt", name: "Debts", types: ["mortgage", "loan", "carloan", "student", "card", "tax", "otherdebt"], color: .hex(0xE5484D), liab: true),
    ]
    static func group(of type: String) -> Group { groups.first { $0.types.contains(type) } ?? groups.first { $0.id == "more" }! }

    /// Two-colour gradients (light → deep) for bubbles and avatars, by group or type (the web app's BGRAD).
    static let gradient: [String: (UInt32, UInt32)] = [
        "savings": (0x40B8F0, 0x0A5CFF), "bank": (0x40B8F0, 0x0A5CFF), "cash": (0x5BE37D, 0x11A08A),
        "inv": (0x2DD4BF, 0x0A84FF), "etf": (0x2DD4BF, 0x0A84FF), "stocks": (0x8B7CF6, 0x4F46E5), "mf": (0xFFB340, 0xFF6A3D),
        "crypto": (0xD77CF7, 0x7C4DFF), "property": (0xF2C14E, 0xC2763A), "more": (0x9AA8BC, 0x4A5568), "vehicle": (0x9AA8BC, 0x4A5568),
        "valuables": (0xD9AE7E, 0x8C6239), "other": (0xA1A1AA, 0x5A5A60), "deposit": (0x5B9BFF, 0x2350D9), "wallet": (0x5BE3A6, 0x119A6E),
        "bonds": (0x7DD3FC, 0x2563EB), "rsu": (0xA5A3FF, 0x5B4FE0), "gold": (0xFFD66B, 0xC98A12), "retire": (0x5AD1E6, 0x1A7FA8),
        "pension": (0x5AD1E6, 0x1A7FA8), "insurance": (0x7CC4F2, 0x2A6FB8), "business": (0xD4B48A, 0x86643C), "lent": (0x7FE0D0, 0x2A8C7E),
        "debt": (0xFF6B6B, 0xC81E5A), "mortgage": (0xFF6B6B, 0xC81E5A), "loan": (0xFF7A7A, 0xD9304F), "card": (0xFFA06B, 0xF2555A),
        "carloan": (0xFF8A80, 0xD63A4A), "student": (0xFF8A9A, 0xD6405A), "tax": (0xFF9180, 0xCC3D33), "otherdebt": (0xF2777F, 0xB8323F),
    ]
    static func gradient(_ k: String) -> LinearGradient {
        let g = gradient[k] ?? (0xA1A1AA, 0x5A5A60)
        return LinearGradient(colors: [.hex(g.0), .hex(g.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Onboarding's picks (the common types; the rest are in the entry sheet).
    static let kinds: [(t: String, n: String)] = [
        ("bank", "Bank account"), ("etf", "ETFs"), ("stocks", "Stocks"), ("mf", "Mutual funds"), ("bonds", "Bonds"), ("crypto", "Crypto"),
        ("pension", "Pension"), ("cash", "Cash"), ("property", "Home or property"), ("vehicle", "Car"), ("valuables", "Gold & valuables"),
        ("other", "Something else"), ("mortgage", "Mortgage"), ("loan", "Loan"), ("carloan", "Car loan"), ("student", "Student loan"),
        ("card", "Credit card"), ("otherdebt", "Other debt"),
    ]
    static func ask(_ t: String) -> String {
        if isLiab(t) { return "How much do you owe?" }
        return ["property", "vehicle", "valuables", "gold", "business", "insurance", "other"].contains(t) ? "What is it worth today?" : "How much is in it?"
    }

    /// The icons an entry can pick: the web app's set (Material Symbols, generated into MaterialIcons.swift).
    static var iconChoices: [String] { MaterialIcons.picker }

    /// The icon an entry shows (a Material name): its picked icon if we have it, else its type's.
    static func symbol(for a: Account) -> String {
        if let i = a.icon, MaterialIcons.paths[i] != nil { return i }
        return safeSymbol(type(a.type).symbol)
    }
    static func safeSymbol(_ s: String) -> String { MaterialIcons.paths[s] != nil ? s : "other" }
}

extension Color {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    /// The app's colours (dark), from the web app's CSS variables.
    static let up = Color.hex(0x36F5B2)
    static let down = Color.hex(0xFF6961)
    static let g1 = Color.hex(0x0EA67A)
    static let g2 = Color.hex(0x2466E0)
    static let sec = Color.hex(0x98989F)
    /// Card surface (the web app's --card).
    static let card = Color.hex(0x1C1C1E)
}
