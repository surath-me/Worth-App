import SwiftUI

@main
struct WorthApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { await store.fetchRates() }
                .onChange(of: phase) { _, p in if p == .active { Task { await store.fetchRates() } } }
        }
    }
}

/// Three tabs, like the web app: Net worth · Monthly · Settings.
struct RootView: View {
    @State private var tab = "worth"

    var body: some View {
        TabView(selection: $tab) {
            NetWorthView()
                .tabItem { Label("Net worth", systemImage: "chart.line.uptrend.xyaxis") }
                .tag("worth")
            MonthlyView()
                .tabItem { Label("Monthly", systemImage: "calendar") }
                .tag("monthly")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
    }
}
