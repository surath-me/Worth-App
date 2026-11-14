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
    @FocusState private var nameFocused: Bool

    var body: some View {
        let t = Catalog.type(type)
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        TextField("Name, e.g. Savings", text: $name).focused($nameFocused)
                            .multilineTextAlignment(.center).font(.system(size: 17))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Currency.symbol[cur] ?? cur).font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.sec)
                            TextField("0", text: $amount).keyboardType(.decimalPad)
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
                            Text("%").foregroundStyle(Color.sec)
                        }
                    }
                    Picker("Currency", selection: $cur) {
                        ForEach(Currency.all, id: \.self) { c in Text("\(c) \(Currency.symbol[c] ?? "")").tag(c) }
                    }
                    TextField("Platform (optional)", text: $platform)
                } footer: { if t.dep != nil { Text("Applied at each new month.") } }

                if account != nil {
                    Section {
                        Button("Delete entry", role: .destructive) { confirmDelete = true }
                    } footer: { Text("Past months keep it.") }
                }
            }
            .navigationTitle(account == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { after?(nil); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(account == nil ? "Add" : "Done", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let account { store.delete(account) }; dismiss() }
            }
            .onChange(of: type) { _, k in if let d = Catalog.type(k).dep, dep.isEmpty || account == nil { dep = Self.fmt(d) } }
            .onAppear(perform: load)
            .defaultFocus($nameFocused, account == nil) // a new entry types its name straight away: the keyboard rises with the opening
        }
    }

    private var currentSymbol: String {
        if let icon, let s = Catalog.materialToSF[icon] { return Catalog.safeSymbol(s) }
        return Catalog.safeSymbol(Catalog.type(type).symbol)
    }

    private func load() {
        if let a = account {
            name = a.name; amount = Self.fmt(a.bal); type = Catalog.type[a.type] != nil ? a.type : "other"
            cur = a.cur; platform = a.platform; icon = a.icon
            if let d = a.dep ?? Catalog.type(type).dep { dep = Self.fmt(d) }
        } else {
            cur = store.data.base
            if let t = startType, Catalog.type[t] != nil { type = t; if let d = Catalog.type(t).dep { dep = Self.fmt(d) } }
            nameFocused = true
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
                ForEach(Catalog.iconChoices, id: \.self) { k in
                    let s = Catalog.safeSymbol(Catalog.materialToSF[k] ?? "circle")
                    if s != typeSymbol { cell(symbol: s, on: selected == k) { selected = k } }
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
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(on ? .white : .primary)
                .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                .background(Circle().fill(on ? AnyShapeStyle(color) : AnyShapeStyle(Color(.tertiarySystemFill))))
                .overlay(Circle().stroke(on ? color : .clear, lineWidth: 2).padding(-4))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }
}
