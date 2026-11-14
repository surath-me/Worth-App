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
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Show totals in") {
                    Picker("Currency", selection: Binding(get: { store.data.base }, set: { store.setBase($0) })) {
                        ForEach(Currency.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(Currency.all.filter { $0 != store.data.base }, id: \.self) { c in
                        let r = (store.data.rates[c] ?? 1) / (store.data.rates[store.data.base] ?? 1)
                        HStack {
                            Text("1 \(store.data.base)")
                            Spacer()
                            Text("\(r.formatted(.number.precision(.significantDigits(1...6)))) \(c)").monospacedDigit().foregroundStyle(Color.sec)
                        }
                    }
                } header: { Text("Exchange rates") } footer: { Text(ratesNote) }

                Section {
                    Toggle("Hide amounts", isOn: Binding(get: { prefs.hide }, set: { prefs.hide = $0 })).tint(Color.g1)
                } header: { Text("Privacy") } footer: { Text("Or tap your net worth.") }

                Section {
                    ShareLink(item: BackupFile(data: store.backupData()), preview: SharePreview("Worth backup", image: Image(systemName: "doc"))) {
                        Label("Save backup", systemImage: "square.and.arrow.up")
                    }
                    Button { importing = true } label: { Label("Restore from file", systemImage: "square.and.arrow.down") }
                } header: { Text("Backup") } footer: {
                    Text("Same file as the web app’s backup, so you can move your data between the two.")
                }

                Section {
                    Button("Erase all data", role: .destructive) { confirmErase = true }
                }

                #if DEBUG
                Section("Developer") {
                    Button("Load sample data") { store.loadSample(); message = "Sample data loaded" }
                }
                #endif
            }
            .tint(.primary) // action rows are plain white, never accent-coloured text (same rule as the web app)
            .navigationTitle("Settings")
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
