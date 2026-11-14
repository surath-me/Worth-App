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
                            TextField("0", text: $amount).keyboardType(.numbersAndPunctuation).focused($focus, equals: .amount).submitLabel(.done)
                                .font(.system(size: 40, weight: .bold)).monospacedDigit()
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

            }
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
            // the actions sit at the bottom, above the keyboard when it's up: delete (editing only) and Save/Add
            .safeAreaInset(edge: .bottom) { actions }
            .interactiveDismissDisabled(changed) // a swipe down can't silently throw changes away
            .onChange(of: confirmDiscard || confirmDelete) { _, open in if !open { finishLeaving() } }
            .onChange(of: type) { _, k in if let d = Catalog.type(k).dep, dep.isEmpty || account == nil { dep = Self.fmt(d) } }
            .onAppear(perform: load)
            // every field's keyboard has the blue ✓ in the return key's spot (the amount too: numbers + ✓ rather than
            // the number pad, which has no return key); it finishes typing
            .onSubmit { focus = nil }
        }
    }

    private var currentSymbol: String {
        if let icon, MaterialIcons.paths[icon] != nil { return icon }
        return Catalog.safeSymbol(Catalog.type(type).symbol)
    }

    /// Delete on the left (a small round button, only when editing), the main action filling the rest: Save is only
    /// active once something has changed; a new entry's Add once it has a name.
    private var actions: some View {
        HStack(spacing: 12) {
            if let account {
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.down)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Delete entry")
                .confirmationDialog("Delete \(account.name.isEmpty ? "this entry" : account.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete entry", role: .destructive) { leaving = .delete }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Months already recorded keep its balance.") }
            }
            Button(account == nil ? "Add" : "Save", action: save)
                .buttonStyle(PrimaryButton())
                .disabled(!canSave)
                .animation(.easeOut(duration: 0.2), value: canSave)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
        // the form scrolls under the bar and fades out behind it, rather than showing through between the buttons
        .background {
            let bg = Color(.systemGroupedBackground)
            VStack(spacing: 0) {
                LinearGradient(colors: [bg.opacity(0), bg], startPoint: .top, endPoint: .bottom).frame(height: 20)
                bg
            }
            .ignoresSafeArea(.container, edges: .bottom) // down to the sheet's edge, but not behind the keyboard
        }
    }

    private func finishLeaving() {
        guard let l = leaving else { return }
        leaving = nil
        if l == .delete, let account { store.delete(account) } else { after?(nil) }
        dismiss()
    }

    private var named: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { named && (account == nil || changed) }
    private func close() { if changed { confirmDiscard = true } else { after?(nil); dismiss() } }

    /// Whether anything differs from the saved entry, compared as values (so "1500" and "1500.00", or a default yearly
    /// change filled in for display, don't count as edits). A new entry counts as changed once anything is typed.
    private var changed: Bool {
        guard let a = account else { return named || !amount.isEmpty || !platform.isEmpty }
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
            name = a.name; amount = Self.fmt(a.bal); type = Catalog.type[a.type] != nil ? a.type : "other"
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

/// A small press-in for round icon buttons.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
