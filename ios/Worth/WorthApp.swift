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
    @Namespace private var addNS

    var body: some View {
        ZStack {
            // The + sits on its own round button at the bottom right, beside the tab bar (like the web app's button):
            // it's the tab bar's separate trailing tab, which opens the new-entry sheet instead of a page.
            TabView(selection: Binding(get: { tab }, set: { t in
                if t == "add" { if store.isEmpty { onboarding = true } else { adding = true } } else { tab = t }
            })) {
                Tab(value: "worth") { NetWorthView() } label: { Label { Text("Net worth") } icon: { Image(uiImage: SVGIcon.chart) } } // the web app's icon
                Tab("Monthly", systemImage: "calendar", value: "monthly") { MonthlyView() }
                    .badge(store.checkInDue ? Text("") : nil) // a dot while this month's check-in is due
                Tab("Settings", systemImage: "gearshape.fill", value: "settings") { SettingsView() }
                if #available(iOS 27, *) {
                    Tab(value: "add", role: .prominent) { Color.clear } label: { Label { Text("Add entry") } icon: { Image(uiImage: ClearIcon.image) } }
                } else {
                    Tab(value: "add", role: .search) { Color.clear } label: { Label { Text("Add entry") } icon: { Image(uiImage: ClearIcon.image) } }
                }
            }
            // The + is drawn here, exactly over the tab bar's own trailing button: the web app's accent circle with a white
            // plus. Catching the tap here also means the tab bar never switches to the empty "add" page (no black flash).
            // The new-entry sheet zooms out of it (iOS's zoom transition, as in Structured): the circle lifts and
            // grows, turns into a pill as the keyboard rises, then opens into the sheet; closing runs it in reverse.
            .overlay {
                // measured from the screen's edges (not the safe area), where the tab bar's own button sits
                ZStack(alignment: .bottomTrailing) {
                    Color.clear.allowsHitTesting(false)
                    Button { if store.isEmpty { onboarding = true } else { adding = true } } label: {
                        AddButtonFace().matchedTransitionSource(id: "add", in: addNS) { $0.clipShape(RoundedRectangle(cornerRadius: 31)).background(.clear) } // just the circle (r = half of 62), no box
                    }
                    .buttonStyle(AddPressStyle())
                    .padding(.trailing, 21).padding(.bottom, 21)
                    .accessibilityLabel("Add entry")
                    .sensoryFeedback(.impact(weight: .light), trigger: adding)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $adding) {
                EntrySheet(account: nil).navigationTransition(.zoom(sourceID: "add", in: addNS))
            }
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

/// The + button's face: the accent gradient circle (the web app's green → blue) with a white plus.
struct AddButtonFace: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 62, height: 62)
            .background(Circle().fill(LinearGradient(colors: [Color.g1, Color.hex(0x0B82A6), Color.g2], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .contentShape(Circle())
    }
}
/// The press: the circle grows a little under the finger and springs back.
struct AddPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // grows under the finger (like the tab bar's items do) and brightens, then springs back
        configuration.label
            .overlay(Circle().fill(.white.opacity(configuration.isPressed ? 0.18 : 0)))
            .scaleEffect(configuration.isPressed ? 1.12 : 1)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .animation(.spring(duration: 0.35, bounce: 0.45), value: configuration.isPressed)
    }
}

/// An empty icon for the tab bar's own trailing button, which only holds the space under our drawn + button.
enum ClearIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in }.withRenderingMode(.alwaysOriginal)
}
