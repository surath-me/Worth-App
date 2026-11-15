import SwiftUI

/// Add or edit an entry: name, balance, type, icon, currency, platform, and (for physical assets) the yearly value change.
struct EntrySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: Account?
    var startType: String? = nil
    /// Called with the saved entry (or nil when cancelled) instead of just closing; the check-in uses this.
    var after: ((Account?) -> Void)? = nil

    @State private var name = ""
    @State private var amount = ""
    @State private var amountFocused = false
    @State private var type = "bank"
    @State private var cur = "EUR"
    @State private var platform = ""
    @State private var dep = ""
    @State private var icon: String?
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    /// What to do once the question's popover has gone: closing the sheet from inside it would only close the popover.
    @State private var leaving: Leave?
    enum Leave { case discard, delete }
    /// Which field is being typed in. Nothing is focused when the sheet opens: the keyboard comes up only on a tap.
    @FocusState private var focus: Field?
    enum Field { case name, amount, dep, platform }

    var body: some View {
        let t = Catalog.type(type)
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        TextField("Name, e.g. Savings", text: $name).focused($focus, equals: .name).submitLabel(.done)
                            .multilineTextAlignment(.center).font(.system(size: 17))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Currency.symbol[cur] ?? cur).font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.sec)
                            // the native number pad; grouped as you type ("14,921.66")
                            AmountField(text: $amount, cur: cur, size: 40, weight: .bold, align: .left, numberPad: true, focused: $amountFocused)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                } footer: { if t.liab { Text("What you still owe") } }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(Catalog.groups) { g in
                            Section(g.name) {
                                ForEach(g.types, id: \.self) { k in Text(Catalog.type(k).name).tag(k) }
                            }
                        }
                    }
                    NavigationLink {
                        IconPicker(selected: $icon, typeSymbol: Catalog.safeSymbol(t.symbol), color: t.color)
                    } label: {
                        HStack {
                            Text("Icon"); Spacer()
                            Avatar(symbol: currentSymbol, color: t.color, size: 30)
                        }
                    }
                    if t.dep != nil {
                        HStack {
                            Text("Value change / year")
                            TextField("0", text: $dep).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                                .focused($focus, equals: .dep).submitLabel(.done)
                            Text("%").foregroundStyle(Color.sec)
                        }
                    }
                    Picker("Currency", selection: $cur) {
                        ForEach(Currency.all, id: \.self) { c in Text("\(c) \(Currency.symbol[c] ?? "")").tag(c) }
                    }
                    TextField("Platform (optional)", text: $platform).focused($focus, equals: .platform).submitLabel(.done)
                } footer: { if t.dep != nil { Text("Applied at each new month.") } }

                if let account {
                    // a secondary full-width button at the end of the options; its question comes out of the button itself
                    Section {
                        Button { confirmDelete = true } label: {
                            // the secondary button: our soft filled capsule (as GhostButton), red for a destructive action
                            Label("Delete entry", systemImage: "trash")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.down)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Delete \(account.name.isEmpty ? "this entry" : account.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete entry", role: .destructive) { leaving = .delete }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("Months already recorded keep its balance.") }
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            .scrollDismissesKeyboard(.interactively) // dragging the form down closes the keyboard (the number pad has no ✓)
            .navigationTitle(account == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Group {
                        if #available(iOS 26, *) { Button(role: .close, action: close) } else { Button("Cancel", action: close) }
                    }
                    // closing with unsaved changes asks first (the iOS pattern), anchored to the close button
                    .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                        Button("Discard changes", role: .destructive) { leaving = .discard }
                        Button("Keep editing", role: .cancel) {}
                    }
                }
            }
            // Save (Add for a new entry) floats at the bottom, above the keyboard when it's up
            .safeAreaInset(edge: .bottom) { actions }
            .interactiveDismissDisabled(changed) // a swipe down can't silently throw changes away…
            .background(DismissAttempt { confirmDiscard = true }) // …it asks instead, as the X does
            // close once both have happened (the choice made, the popover gone), in whichever order iOS runs them
            .onChange(of: confirmDiscard || confirmDelete) { _, open in if !open { finishLeaving() } }
            .onChange(of: leaving) { _, l in if l != nil, !confirmDiscard, !confirmDelete { finishLeaving() } }
            .onChange(of: cur) { _, c in amount = Self.parse(amount).map { Self.show($0, c) } ?? "" } // regrouped for its currency
            .onChange(of: type) { _, k in if let d = Catalog.type(k).dep, dep.isEmpty || account == nil { dep = Self.fmt(d) } }
            .onAppear(perform: load)
            // the text fields' keyboards have the blue ✓ in the return key's spot; it finishes typing (the amount uses
            // the number pad, which has none: Save sits right above it, and scrolling or tapping elsewhere closes it)
            .onSubmit { focus = nil }
        }
    }

    private var currentSymbol: String {
        if let icon, MaterialIcons.paths[icon] != nil { return icon }
        return Catalog.safeSymbol(Catalog.type(type).symbol)
    }

    /// Save (Add for a new entry), on its own and only there once something has changed (a new entry: once it has a
    /// name and an amount).
    private var actions: some View {
        VStack {
            if canSave {
                Button(account == nil ? "Add" : "Save", action: save)
                    .buttonStyle(PrimaryButton())
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                    // hidden until there's something to save; then it rises into view (and drops away if undone)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: canSave)
    }

    private func finishLeaving() {
        guard let l = leaving else { return }
        leaving = nil
        if l == .delete, let account { store.delete(account) } else { after?(nil) }
        dismiss()
    }

    private var named: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Needs a name and an amount (an emptied amount would otherwise save as 0 without a word; type 0 if that's meant),
    /// and, when editing, a change.
    private var canSave: Bool { named && Self.parse(amount) != nil && (account == nil || changed) }
    private func close() { if changed { confirmDiscard = true } else { after?(nil); dismiss() } }

    /// Whether anything differs from the saved entry, compared as values (so "1500" and "1500.00", or a default yearly
    /// change filled in for display, don't count as edits). A new entry counts as changed once anything is typed.
    private var changed: Bool {
        guard let a = account else {
            // a new entry: anything typed or picked away from how it opened
            let startT = startType.flatMap { Catalog.type[$0] != nil ? $0 : nil } ?? "bank"
            let def = Catalog.type(type).dep
            return named || !amount.isEmpty || !platform.trimmingCharacters(in: .whitespaces).isEmpty
                || type != startT || cur != store.data.base || icon != nil
                || (def != nil && Self.parse(dep) != def)
        }
        let def = Catalog.type(type).dep
        let nowDep = def != nil ? (Self.parse(dep) ?? def) : nil
        let wasDep = Catalog.type(a.type).dep != nil ? (a.dep ?? Catalog.type(a.type).dep) : nil
        return name.trimmingCharacters(in: .whitespaces) != a.name
            || abs(abs(Self.parse(amount) ?? 0) - a.bal) > 0.001
            || type != (Catalog.type[a.type] != nil ? a.type : "other")
            || cur != a.cur
            || platform.trimmingCharacters(in: .whitespaces) != a.platform
            || icon != a.icon
            || nowDep != wasDep
    }

    private func load() {
        if let a = account {
            name = a.name; amount = Self.show(a.bal, a.cur); type = Catalog.type[a.type] != nil ? a.type : "other"
            cur = a.cur; platform = a.platform; icon = a.icon
            if let d = a.dep ?? Catalog.type(type).dep { dep = Self.fmt(d) }
        } else {
            cur = store.data.base
            if let t = startType, Catalog.type[t] != nil { type = t; if let d = Catalog.type(t).dep { dep = Self.fmt(d) } }
        }
    }

    private func save() {
        let bal = abs(Self.parse(amount) ?? 0)
        var a = account ?? Account(name: "", type: type, cur: cur, bal: 0)
        a.name = name.trimmingCharacters(in: .whitespaces); a.type = type; a.cur = cur; a.bal = bal
        a.platform = platform.trimmingCharacters(in: .whitespaces); a.icon = icon
        a.dep = Catalog.type(type).dep != nil ? (Self.parse(dep) ?? Catalog.type(type).dep) : nil
        store.upsert(a)
        after?(a)
        dismiss()
    }

    /// Accepts "1,234.5", "1.234,5" or "1234,5".
    static func parse(_ s: String) -> Double? {
        var t = s.filter { "0123456789.,-".contains($0) }
        if t.isEmpty { return nil }
        if t.contains(","), t.contains(".") {
            t = t.lastIndex(of: ",")! > t.lastIndex(of: ".")! ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        } else if t.contains(",") {
            let parts = t.split(separator: ",", omittingEmptySubsequences: false)
            t = (parts.count > 2 || parts.last?.count == 3) ? t.replacingOccurrences(of: ",", with: "") : t.replacingOccurrences(of: ",", with: ".")
        }
        return Double(t)
    }
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }

    /// An amount written the way its currency writes it: "14,921.66", "₹6,31,394.57", "CHF 12’500".
    static func show(_ v: Double, _ cur: String) -> String {
        let f: NumberFormatter
        if let hit = formatters[cur] { f = hit } else {
            f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
            f.locale = Locale(identifier: Currency.locale[cur] ?? "en_IE")
            formatters[cur] = f
        }
        return f.string(from: NSNumber(value: v)) ?? fmt(v)
    }
    private static var formatters: [String: NumberFormatter] = [:] // one per currency, made once

    /// The amount as it's being typed, kept grouped the way its currency writes it (so editing "14,921.66" never
    /// turns it into "14921.66"). The keyboard's "," or "." both start the cents (at most two); deleting a grouping
    /// separator deletes the digit before it, as nothing would change otherwise.
    static func live(_ new: String, was old: String, cur: String) -> String {
        _ = show(0, cur) // makes the currency's formatter
        let dec = Character(formatters[cur]?.decimalSeparator ?? ".")
        if new.count == old.count + 1, new.hasPrefix(old), let c = new.last, c == "," || c == "." {
            return old.contains(dec) ? old : (old.isEmpty ? "0" : old) + String(dec)
        }
        var s = new
        let digits = { (x: String) in x.filter(\.isNumber) }
        if new.count < old.count, digits(new) == digits(old) {
            var o = Array(old)
            let i = zip(o, new).prefix { $0 == $1 }.count
            if i < o.count, o[i] != dec { // a grouping separator (deleting the decimal point just removes it)
                o.remove(at: i)
                var j = i - 1
                while j >= 0, !o[j].isNumber { j -= 1 }
                if j >= 0 { o.remove(at: j) }
                s = String(o)
            }
        }
        let parts = s.split(separator: dec, maxSplits: 1, omittingEmptySubsequences: false)
        var int = String((parts.first ?? "").filter(\.isNumber))
        while int.count > 1, int.hasPrefix("0") { int.removeFirst() }
        let frac = parts.count > 1 ? String(parts[1].filter(\.isNumber).prefix(2)) : nil
        if int.isEmpty && frac == nil { return "" }
        return show(Double(int) ?? 0, cur) + (frac.map { String(dec) + $0 } ?? "")
    }
}

/// A grid of icons; the first is the type's own (choosing it clears the custom icon). Picking one goes back.
struct IconPicker: View {
    @Binding var selected: String?
    let typeSymbol: String
    let color: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                cell(symbol: typeSymbol, on: selected == nil) { selected = nil }
                ForEach(Catalog.iconChoices.filter { $0 != typeSymbol }, id: \.self) { k in
                    cell(symbol: k, on: selected == k) { selected = k }
                }
            }
            .padding(16)
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cell(symbol: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            pick()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { dismiss() } // the pick lights up, then back
        } label: {
            MIcon(symbol, size: 24)
                .foregroundStyle(on ? .white : .primary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(on ? AnyShapeStyle(color) : AnyShapeStyle(Color(.tertiarySystemFill))))
                .overlay(Circle().stroke(on ? color : .clear, lineWidth: 2).padding(-4))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }
}

/// Hooks the sheet's swipe-down while it's blocked (`interactiveDismissDisabled`), so the attempt can ask "Discard
/// your changes?" instead of just springing back. It wraps the delegate SwiftUI set on the sheet and forwards
/// everything else to it, so the sheet's own handling is untouched.
private struct DismissAttempt: UIViewRepresentable {
    let onAttempt: () -> Void
    func makeUIView(context: Context) -> Hook { Hook() }
    func updateUIView(_ v: Hook, context: Context) { v.proxy.onAttempt = onAttempt; v.install() }

    final class Hook: UIView {
        let proxy = Proxy()
        override func didMoveToWindow() { super.didMoveToWindow(); install() }
        func install() {
            // the sheet is the topmost view controller holding this view
            var r: UIResponder? = self
            while let x = r, !(x is UIViewController) { r = x.next }
            guard var vc = r as? UIViewController else { return }
            while let p = vc.parent { vc = p }
            guard let pc = vc.presentationController, pc.delegate !== proxy else { return }
            proxy.original = pc.delegate
            pc.delegate = proxy
        }
    }

    final class Proxy: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var original: UIAdaptivePresentationControllerDelegate?
        var onAttempt: () -> Void = {}
        func presentationControllerDidAttemptToDismiss(_ p: UIPresentationController) {
            onAttempt()
            original?.presentationControllerDidAttemptToDismiss?(p)
        }
        override func responds(to s: Selector!) -> Bool { super.responds(to: s) || (original?.responds(to: s) ?? false) }
        override func forwardingTarget(for s: Selector!) -> Any? { original?.responds(to: s) == true ? original : nil }
    }
}
