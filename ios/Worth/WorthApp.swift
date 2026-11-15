import SwiftUI

@main
struct WorthApp: App {
    @State private var store = Store()
    @State private var prefs = Prefs()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .background(TapOutsideEndsEditing()) // a tap outside any field closes the keyboard
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
    @State private var addClosing = false   // the new-entry sheet is on its way out
    @State private var addAgain = false     // + tapped meanwhile: open it again once it's gone
    @Namespace private var addNS

    /// Open the new-entry sheet (or the onboarding while there's nothing yet). iOS ignores a new sheet while the last one
    /// is still closing, so a tap in that moment is kept and opens it as soon as the close has finished.
    private func openAdd() {
        // (an open sheet covers the +, so a tap while `adding` is still set means it's on its way out after a swipe)
        if store.isEmpty { onboarding = true } else if adding || addClosing { addAgain = true } else { adding = true }
    }

    var body: some View {
        ZStack {
            // The + sits on its own round button at the bottom right, beside the tab bar (like the web app's button):
            // it's the tab bar's separate trailing tab, which opens the new-entry sheet instead of a page.
            TabView(selection: Binding(get: { tab }, set: { t in
                if t == "add" { openAdd() } else { tab = t }
            })) {
                Tab(value: "worth") { NetWorthView() } label: { Label { Text("Net worth") } icon: { Image(uiImage: SVGIcon.chart) } } // the web app's icon
                Tab("Monthly", systemImage: "calendar", value: "monthly") { MonthlyView() }
                    .badge(store.checkInDue ? Text("") : nil) // a dot while this month's check-in is due
                Tab("Settings", systemImage: "gearshape.fill", value: "settings") { SettingsView() }
                // the + is the tab bar's own separate trailing tab (as in Shortcuts or Structured), so it has the system's
                // press: the glass lens swells under the finger. Selecting it opens the new-entry sheet instead of a page.
                if #available(iOS 27, *) {
                    Tab("Add entry", systemImage: "plus", value: "add", role: .prominent) { Color.clear }
                } else {
                    Tab("Add entry", systemImage: "plus", value: "add", role: .search) { Color.clear }
                }
            }
            // The sheet zooms out of the + (as in Shortcuts) and back into it. A tab can't be a zoom source itself, so an
            // invisible circle sits exactly over the tab bar's + to anchor it; the tab underneath keeps its native press.
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                    Circle().fill(Color.white.opacity(0.001)).frame(width: 62, height: 62)
                        .matchedTransitionSource(id: "add", in: addNS) { $0.clipShape(RoundedRectangle(cornerRadius: 31)) }
                        .padding(.trailing, 21).padding(.bottom, 21)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .sensoryFeedback(trigger: adding) { _, open in open ? .impact(weight: .light) : nil } // on open only
            .onChange(of: adding) { _, open in if !open { addClosing = true } }
            .sheet(isPresented: $adding, onDismiss: {
                addClosing = false
                if addAgain { addAgain = false; adding = true }
            }) {
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
