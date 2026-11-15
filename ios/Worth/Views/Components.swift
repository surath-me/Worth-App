import SwiftUI

/// The round coloured icon used for an entry (white glyph on the type's colour).
struct Avatar: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    /// A type or group key for the two-colour gradient (falls back to `color`).
    var grad: String? = nil

    var body: some View {
        MIcon(symbol, size: size * 0.6) // the web app's Material icon (it fills ~22/40 of the avatar)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(grad.map { AnyShapeStyle(Catalog.gradient($0)) } ?? AnyShapeStyle(color.gradient)))
    }
}

/// One entry: icon, name, platform or type, balance (debts shown with a minus).
struct EntryRow: View {
    @Environment(Store.self) private var store
    let account: Account

    var body: some View {
        let t = Catalog.type(account.type)
        HStack(spacing: 12) {
            Avatar(symbol: Catalog.symbol(for: account), color: t.color, grad: t.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(subtitle(t)).font(.system(size: 13)).foregroundStyle(Color.sec).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((t.liab ? "−" : "") + Money.format(account.bal, account.cur))
                .font(.system(size: 15, weight: .medium)).monospacedDigit().masked()
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ t: EntryType) -> String {
        let what = account.platform.isEmpty ? t.name : account.platform
        guard account.cur != store.data.base else { return what }
        return what + " · ≈ " + Money.format(store.conv(account.bal, account.cur), store.data.base, decimals: 0)
    }
}

/// "↑ €4,069 (6.1%) vs October": the figure in green (red when down), the label after it in grey, like the web app.
struct ChangeLabel: View {
    let change: Double
    let from: Double
    let cur: String
    var suffix: String = ""
    var size: CGFloat = 15

    var body: some View {
        let pct = from != 0 ? change / abs(from) * 100 : 0
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down").font(.system(size: size * 0.75, weight: .heavy))
                Text(Money.format(abs(change), cur, decimals: 0) + (from != 0 ? String(format: " (%.1f%%)", abs(pct)) : "")).monospacedDigit()
            }
            .fontWeight(.semibold)
            .foregroundStyle(change >= 0 ? Color.up : Color.down)
            if !suffix.isEmpty { Text(suffix.trimmingCharacters(in: .whitespaces)).foregroundStyle(Color.sec) }
        }
        .font(.system(size: size))
        .lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// The page title right under the status bar (the web app's 22pt `h1.large`), in place of a navigation bar.
struct PageTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 22, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 6)
    }
}

/// A section title ("Breakdown", "Allocation"): 19pt bold white.
struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 19, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.top, 28).padding(.bottom, 8)
    }
}

/// "Saved on this device" at the bottom of each tab.
struct SavedFoot: View {
    var body: some View {
        Text("Saved on this device").font(.system(size: 12)).foregroundStyle(Color.hex(0x5C5C61))
            .frame(maxWidth: .infinity).padding(.top, 28)
    }
}

/// The app's main button: a full-width capsule with the green→blue gradient and white text (never gradient text).
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Capsule().fill(LinearGradient(colors: [Color.g1, Color.hex(0x0B82A6), Color.g2], startPoint: .leading, endPoint: .trailing)))
            // inactive: darkened (label included), not faded, so it stays opaque when it floats over content
            .overlay(Capsule().fill(Color.black.opacity(enabled ? 0 : 0.6)).allowsHitTesting(false))
            .shadow(color: Color.hex(0x36F5B2).opacity(enabled ? 0.28 : 0), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A quiet full-width button (secondary actions).
struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
    }
}

extension Text {
    /// Small grey section heading, like the web app's `.lbl-s`.
    func sectionLabel() -> some View {
        self.font(.system(size: 13)).foregroundStyle(Color.sec).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 7)
    }
}

/// Opens the full-screen onboarding from anywhere (the empty state, Monthly while empty).
private struct OpenOnboardingKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var openOnboarding: () -> Void {
        get { self[OpenOnboardingKey.self] }
        set { self[OpenOnboardingKey.self] = newValue }
    }
}

/// Tapping anywhere that isn't a text field closes the keyboard, everywhere in the app (sheets included: they share
/// the window). A window-wide tap that never takes the touch from what was tapped, so a button tapped while typing still
/// works, and it closes the keyboard too.
struct TapOutsideEndsEditing: UIViewRepresentable {
    func makeUIView(context: Context) -> Installer { Installer() }
    func updateUIView(_ v: Installer, context: Context) {}

    final class Installer: UIView, UIGestureRecognizerDelegate {
        private weak var host: UIWindow?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let w = window, host !== w else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false // never hold back a touch's end from the view it's on (buttons, drags, the chart)
            tap.delegate = self
            w.addGestureRecognizer(tap)
            host = w
        }
        @objc private func tapped() { host?.endEditing(true) } // a no-op when nothing is being typed in
        // a tap on a text field (or inside one) is for typing, not for closing the keyboard
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var v = touch.view
            while let x = v { if x is UITextField || x is UITextView { return false }; v = x.superview }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
}

/// An amount field that keeps the amount grouped the way its currency writes it while you type ("14,921.66",
/// "₹6,31,394.57"), with the cursor staying where you're typing. A UIKit field: SwiftUI's TextField can't regroup
/// the text mid-typing without losing the cursor.
struct AmountField: UIViewRepresentable {
    @Binding var text: String
    let cur: String
    var size: CGFloat = 16
    var weight: UIFont.Weight = .medium
    var align: NSTextAlignment = .right
    /// The number pad (no return key) or the full keyboard with its ✓ in the return key's spot.
    var numberPad = false
    @Binding var focused: Bool
    /// The keyboard's ✓ (after it closes the keyboard).
    var onReturn: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.delegate = context.coordinator
        f.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        f.textAlignment = align
        f.textColor = .label
        f.attributedPlaceholder = NSAttributedString(string: "0", attributes: [.foregroundColor: UIColor.tertiaryLabel])
        f.keyboardType = numberPad ? .decimalPad : .numbersAndPunctuation
        f.returnKeyType = .done
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.setContentHuggingPriority(.required, for: .horizontal)
        f.setContentCompressionResistancePriority(.required, for: .horizontal)
        return f
    }

    func updateUIView(_ f: UITextField, context: Context) {
        context.coordinator.parent = self
        if f.text != text { f.text = text; f.invalidateIntrinsicContentSize() }
        if focused, !f.isFirstResponder { DispatchQueue.main.async { f.becomeFirstResponder() } }
        if !focused, f.isFirstResponder { DispatchQueue.main.async { f.resignFirstResponder() } }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView f: UITextField, context: Context) -> CGSize? {
        CGSize(width: f.intrinsicContentSize.width + 2, height: f.intrinsicContentSize.height) // its text (+ the cursor)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AmountField
        init(_ p: AmountField) { parent = p }

        func textField(_ f: UITextField, shouldChangeCharactersIn range: NSRange, replacementString s: String) -> Bool {
            let old = f.text ?? ""
            let new = (old as NSString).replacingCharacters(in: range, with: s)
            // digits (and the decimal point) after the cursor: the cursor keeps that many after it once regrouped
            let after = (new as NSString).substring(from: min(range.location + (s as NSString).length, (new as NSString).length))
            let tail = after.filter { $0.isNumber || $0 == "." }.count
            let g = EntrySheet.live(new, was: old, cur: parent.cur)
            f.text = g
            f.invalidateIntrinsicContentSize()
            var i = g.endIndex, k = 0
            while i > g.startIndex, k < tail { i = g.index(before: i); if g[i].isNumber || g[i] == "." { k += 1 } }
            if let p = f.position(from: f.beginningOfDocument, offset: g.utf16.distance(from: g.startIndex, to: i)) {
                f.selectedTextRange = f.textRange(from: p, to: p)
            }
            parent.text = g
            return false
        }
        func textFieldDidBeginEditing(_ f: UITextField) { if !parent.focused { parent.focused = true } }
        func textFieldDidEndEditing(_ f: UITextField) { if parent.focused { parent.focused = false } }
        func textFieldShouldReturn(_ f: UITextField) -> Bool { f.resignFirstResponder(); parent.onReturn?(); return false }
    }
}
