import SwiftUI
import UniformTypeIdentifiers

/// Totals currency, live exchange rates, backup (same file format as the web app) and Erase all data.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    @State private var importing = false
    @State private var confirmErase = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                PageTitle("Settings").padding(.horizontal, -4)
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            Section {
                Picker("Currency", selection: Binding(get: { store.data.base }, set: { store.setBase($0) })) {
                    ForEach(Currency.all, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            } header: { Label13("Show totals in") }

            Section {
                ForEach(Currency.all.filter { $0 != store.data.base }, id: \.self) { c in
                    let r = (store.data.rates[c] ?? 1) / (store.data.rates[store.data.base] ?? 1)
                    HStack {
                        Text("1 \(store.data.base)").foregroundStyle(Color.sec)
                        Spacer()
                        Text("\(r.formatted(.number.precision(.significantDigits(1...6)))) \(c)").monospacedDigit()
                    }
                }
            } header: { Label13("Exchange rates") } footer: { Text(ratesNote) }

            Section {
                Toggle("Hide amounts", isOn: Binding(get: { prefs.hide }, set: { prefs.hide = $0 })).tint(Color.g1)
            } header: { Label13("Privacy") } footer: { Text("Or tap your net worth.") }

            Section {
                ShareLink(item: BackupFile(data: store.backupData()), preview: SharePreview("Worth backup", image: Image(systemName: "doc"))) { Text("Save to Files") }
                    .simultaneousGesture(TapGesture().onEnded { store.markBackedUp() })
                Button("Restore from file") { importing = true }
                Button("Copy as text") {
                    UIPasteboard.general.string = String(data: store.backupData(), encoding: .utf8)
                    store.markBackedUp(); message = "Backup copied"
                }
                Button("Paste backup") {
                    guard let txt = UIPasteboard.general.string, let d = txt.data(using: .utf8) else { message = "Nothing to paste"; return }
                    do { try store.restore(d); message = "Backup restored" } catch { message = "That isn’t a Worth backup" }
                }
            } header: { Label13("Backup") } footer: { Text(backupNote) }

            Section {
                Button { confirmErase = true } label: {
                    Text("Erase all data").font(.system(size: 15)).foregroundStyle(Color.down).frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }

            #if DEBUG
            Section {
                Button("Load sample data") { store.loadSample(); message = "Sample data loaded" }
            } header: { Label13("Developer") }
            #endif

            Section { SavedFoot().padding(.top, -20) }.listRowBackground(Color.clear)
        }
        .listSectionSpacing(18)
        .environment(\.defaultMinListHeaderHeight, 0)
        .tint(.primary) // action rows are plain white, never accent-coloured text (same rule as the web app)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Aura())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do { try store.restore(Data(contentsOf: url)); message = "Backup restored" }
            catch { message = "That file isn’t a Worth backup" }
        }
        .confirmationDialog("Erase everything on this phone?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive) { store.eraseAll() }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
    }

    /// "Only on this phone · last backup 2 hours ago"
    private var backupNote: String {
        guard let at = store.data.backupAt else { return "Only on this phone · no backup yet" }
        return "Only on this phone · last backup " + Date(timeIntervalSince1970: at / 1000).formatted(.relative(presentation: .named))
    }

    private var ratesNote: String {
        guard let src = store.data.ratesSrc, let at = store.data.ratesAt else { return "Approximate until the first live update" }
        let when = Date(timeIntervalSince1970: at / 1000).formatted(.relative(presentation: .named))
        return "Live from \(src == "er-api" ? "ExchangeRate-API" : "Coinbase") · \(when)"
    }
}

/// The backup as a shareable .json file named like the web app's (worth-backup-2026-11-14.json).
struct BackupFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let name = "worth-backup-\(Date().formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// A small grey section label (the web app's 13pt `.lbl-s`), not the large default header.
private struct Label13: View {
    let t: String
    init(_ t: String) { self.t = t }
    var body: some View { Text(t).font(.system(size: 13)).foregroundStyle(Color.sec).textCase(nil) }
}
