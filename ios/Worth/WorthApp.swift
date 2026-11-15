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
            TabView(selection: Binding(get: { tab }, set: { t in
                if t == "add" { openAdd() } else { tab = t }
            })) {
                Tab(value: "worth") { NetWorthView() } label: { Label { Text("Net worth") } icon: { Image(uiImage: SVGIcon.chart) } } // the web app's icon
                Tab("Monthly", systemImage: "calendar", value: "monthly") { MonthlyView() }
                    .badge(store.checkInDue ? Text("") : nil) // a dot while this month's check-in is due
                Tab("Settings", systemImage: "gearshape.fill", value: "settings") { SettingsView() }
                // the tab bar's separate trailing slot, left empty: it only keeps the space the + sits in
                if #available(iOS 27, *) {
                    Tab(value: "add", role: .prominent) { Color.clear } label: { Label { Text("Add entry") } icon: { Image(uiImage: ClearIcon.image) } }
                } else {
                    Tab(value: "add", role: .search) { Color.clear } label: { Label { Text("Add entry") } icon: { Image(uiImage: ClearIcon.image) } }
                }
            }
            // The +: a tinted glass button over that slot. The new-entry sheet morphs out of it (its glass opens into the
            // page, as in Shortcuts) and back into it; a tab can't be a morph source, which is why it isn't the tab itself.
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear.allowsHitTesting(false)
                    AddButton(ns: addNS, action: openAdd).padding(.trailing, 21).padding(.bottom, 21)
                }
                .ignoresSafeArea()
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

/// The +: iOS's prominent glass button (the sheets' X family, so the system's own press) in the accent gradient, and
/// the source the new-entry sheet morphs out of. Before iOS 26 (no Liquid Glass) it's a plain gradient circle.
struct AddButton: View {
    /// the web app's accent: green → blue
    static let gradient = LinearGradient(colors: [Color.g1, Color.hex(0x0B82A6), Color.g2], startPoint: .topLeading, endPoint: .bottomTrailing)
    let ns: Namespace.ID
    let action: () -> Void
    var body: some View {
        let plus = Image(systemName: "plus").font(.system(size: 24, weight: .semibold))
        Group {
            if #available(iOS 26, *) {
                // its tint can only be one colour, so the accent gradient is painted inside it, out to its glass rim
                // (the button's padding around the 48pt label is 7pt); it presses and morphs with the button
                Button(action: action) {
                    plus.foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(Circle().fill(Self.gradient).padding(-7))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Color.hex(0x0B82A6))
            } else {
                Button(action: action) {
                    plus.foregroundStyle(.white).frame(width: 62, height: 62).background(Circle().fill(Self.gradient))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("Add entry")
        // the morph takes just the circle, not the button's square frame (left out, it sometimes grew from a square);
        // it only accepts a rounded rectangle, so r = half of the 62pt button
        .matchedTransitionSource(id: "add", in: ns) { $0.clipShape(RoundedRectangle(cornerRadius: 31)) }
    }
}

/// An empty icon for the tab bar's trailing slot, which only holds the space under the +.
enum ClearIcon {
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in }.withRenderingMode(.alwaysOriginal)
}
