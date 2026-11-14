import SwiftUI

@main
struct WorthApp: App {
    @State private var store = Store()
    @State private var prefs = Prefs()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(prefs)
                .preferredColorScheme(.dark)
                .task { await store.fetchRates() }
                .onChange(of: phase) { _, p in if p == .active { Task { await store.fetchRates() } } }
        }
    }
}

/// Three tabs, like the web app: Net worth · Monthly · Settings. The launch splash plays first; with no data at all
/// (first launch, after Erase all data) the onboarding takes over the screen.
struct RootView: View {
    @Environment(Store.self) private var store
    @State private var tab = "worth"
    @State private var splash = true
    @State private var onboarding = false
    @State private var pastMonth: String?
    @State private var adding = false

    var body: some View {
        ZStack {
            // The + sits on its own round button at the bottom right, beside the tab bar (like the web app's button):
            // it's the tab bar's separate trailing tab, which opens the new-entry sheet instead of a page.
            TabView(selection: Binding(get: { tab }, set: { t in
                if t == "add" { if store.isEmpty { onboarding = true } else { adding = true } } else { tab = t }
            })) {
                Tab("Net worth", systemImage: "chart.line.uptrend.xyaxis", value: "worth") { NetWorthView() }
                Tab("Monthly", systemImage: "calendar", value: "monthly") { MonthlyView() }
                    .badge(store.checkInDue ? Text("") : nil) // a dot while this month's check-in is due
                Tab("Settings", systemImage: "gearshape.fill", value: "settings") { SettingsView() }
                if #available(iOS 27, *) {
                    Tab(value: "add", role: .prominent) { Color.clear } label: { Label { Text("Add entry") } icon: { Image(uiImage: AccentPlus.image) } }
                } else {
                    Tab(value: "add", role: .search) { Color.clear } label: { Label { Text("Add entry") } icon: { Image(uiImage: AccentPlus.image) } }
                }
            }
            // The + is caught here, on top of the native button, so the tab bar never switches to the empty "add" page
            // (which flashed black for a frame before switching back).
            .overlay(alignment: .bottomTrailing) {
                Button { if store.isEmpty { onboarding = true } else { adding = true } } label: {
                    Circle().fill(Color.white.opacity(0.001)).frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20).padding(.bottom, 21)
                .ignoresSafeArea()
                .accessibilityLabel("Add entry")
                .sensoryFeedback(.impact(weight: .light), trigger: adding)
            }
            .sheet(isPresented: $adding) { EntrySheet(account: nil) }
            .environment(\.openOnboarding, { onboarding = true })

            if splash {
                Splash().transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.12))))
                    .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $onboarding) {
            Onboarding(onPastMonths: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pastMonth = Month.shift(Month.key(), by: -1) }
            })
        }
        .sheet(item: Binding(get: { pastMonth.map(TypeChoice.init) }, set: { pastMonth = $0?.id })) { CheckInSheet(start: $0.id) }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if store.isEmpty { onboarding = true }
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6)) { splash = false }
            }
        }
        .onChange(of: store.isEmpty) { _, empty in if empty && !splash { tab = "worth"; onboarding = true } }
    }
}

/// The + drawn in the app's accent (green → blue, like the web app's + button), kept in its own colours in the tab bar.
enum AccentPlus {
    static let image: UIImage = {
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        guard let glyph = UIImage(systemName: "plus", withConfiguration: cfg) else { return UIImage() }
        let size = glyph.size
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            glyph.withRenderingMode(.alwaysTemplate).draw(in: CGRect(origin: .zero, size: size))
            cg.setBlendMode(.sourceIn)
            let colors = [UIColor(red: 0x36/255, green: 0xF5/255, blue: 0xB2/255, alpha: 1).cgColor,
                          UIColor(red: 0x3A/255, green: 0xA4/255, blue: 0xFF/255, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
        }
        return img.withRenderingMode(.alwaysOriginal)
    }()
}
