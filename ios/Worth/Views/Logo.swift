import SwiftUI

/// The Worth mark: a rising curve ending in a ring (the web app's 120×120 SVG path), drawn as a stroke.
struct CurveShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 120, ox = r.midX - 60 * s, oy = r.midY - 60 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        path.move(to: p(20, 84))
        path.addCurve(to: p(56, 66), control1: p(34, 84), control2: p(40, 64))
        path.addCurve(to: p(82, 56), control1: p(72, 68), control2: p(72, 74))   // the SVG "S" reflects the previous control
        path.addCurve(to: p(98, 30), control1: p(92, 38), control2: p(92, 34))
        return path
    }
}
struct CurveDot: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 120, ox = r.midX - 60 * s, oy = r.midY - 60 * s
        return Path(ellipseIn: CGRect(x: ox + (98 - 6.5) * s, y: oy + (30 - 6.5) * s, width: 13 * s, height: 13 * s))
    }
}

/// The logo drawing itself: the curve traces in, then the ring pops.
struct DrawnLogo: View {
    var lineWidth: CGFloat = 9
    var delay: Double = 0.2
    @State private var trim: CGFloat = 0
    @State private var dot: CGFloat = 0

    var body: some View {
        ZStack {
            CurveShape().trim(from: 0, to: trim).stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            CurveDot().stroke(.white, lineWidth: lineWidth * 0.56).scaleEffect(dot, anchor: UnitPoint(x: 98 / 120, y: 30 / 120))
        }
        .onAppear {
            withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.85).delay(delay)) { trim = 1 }
            withAnimation(.spring(duration: 0.5, bounce: 0.45).delay(delay + 0.75)) { dot = 1 }
        }
    }
}

/// Launch splash: the icon's green full screen, the curve draws itself, the ring pops, "Worth" fades in; then it
/// scales up and fades away.
struct Splash: View {
    @State private var word = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [.hex(0x34D69E), .hex(0x11A27C), .hex(0x0B7F68)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 420)
            VStack(spacing: 14) {
                DrawnLogo(lineWidth: 9).frame(width: 124, height: 124)
                Text("Worth").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .opacity(word ? 1 : 0).offset(y: word ? 0 : 6)
            }
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.9)) { word = true } }
    }
}
