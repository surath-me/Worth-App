import SwiftUI
import Observation

/// View preferences (the web app's `worth.ui`): chart range, hidden amounts, allocation style, folds and dismissals.
@Observable
final class Prefs {
    private let d = UserDefaults.standard
    /// Months shown on the chart (1, 6, 12; 0 = all). Also sets what the headline change compares against.
    var range: Int { didSet { d.set(range, forKey: "range") } }
    /// Blur every amount (tap the total, or Settings → Hide amounts).
    var hide: Bool { didSet { d.set(hide, forKey: "hide") } }
    var allocBar: Bool { didSet { d.set(allocBar, forKey: "allocBar") } }
    /// Monthly's "N unchanged" fold.
    var unchangedOpen: Bool { didSet { d.set(unchangedOpen, forKey: "mUnch") } }
    /// The "Add past months" card was dismissed.
    var backfillDone: Bool { didSet { d.set(backfillDone, forKey: "bfDone") } }
    /// Bubble order you arranged by press-and-drag, per level ("top" or a group key): bubble ids in order.
    var bubOrder: [String: [String]] { didSet { d.set(try? JSONEncoder().encode(bubOrder), forKey: "bubOrder") } }

    init() {
        range = d.object(forKey: "range") as? Int ?? 12
        hide = d.bool(forKey: "hide")
        allocBar = d.bool(forKey: "allocBar")
        unchangedOpen = d.bool(forKey: "mUnch")
        backfillDone = d.bool(forKey: "bfDone")
        bubOrder = (d.data(forKey: "bubOrder")).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
    }
}

/// Amounts blur while "Hide amounts" is on (the web app's `body.hide .amt`).
struct Masked: ViewModifier {
    @Environment(Prefs.self) private var prefs
    func body(content: Content) -> some View {
        content.blur(radius: prefs.hide ? 9 : 0, opaque: false)
    }
}
extension View {
    func masked() -> some View { modifier(Masked()) }
}
