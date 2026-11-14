import UIKit

/// Draws the web app's Material Symbols icons (SVG path data, viewBox 0 -960 960 960) as tintable images, so the
/// native app can show exactly the same glyphs where it matters (the Net worth tab icon is the app's signature).
enum SVGIcon {
    /// The web app's tab icon for Net worth (MI.chart in index.html).
    static let chart = image("M93-266q0-13 10-23l234-234q17-17 42.5-17.5T422-523l118 118 278-312q8-9 20.5-10t21.5 8q8 8 8.5 20t-7.5 21L582-363q-17 20-43 20.5T495-360L380-474 149-243q-10 10-23 10t-23-10q-10-10-10-23Z")

    /// A template image (tinted by the tab bar) from Material path data.
    static func image(_ d: String, size: CGFloat = 33) -> UIImage {
        let path = parse(d)
        let s = size / 960
        path.apply(CGAffineTransform(scaleX: s, y: s).translatedBy(x: 0, y: 960))
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            UIColor.black.setFill(); path.fill()
        }.withRenderingMode(.alwaysTemplate)
    }

    /// A small SVG path reader: M L H V C S Q T Z, absolute and relative.
    static func parse(_ d: String) -> UIBezierPath {
        var tokens: [String] = []
        var num = ""
        func flush() { if !num.isEmpty { tokens.append(num); num = "" } }
        for ch in d {
            if ch.isLetter { flush(); tokens.append(String(ch)) }
            else if ch == "-" { if !num.isEmpty && !num.hasSuffix("e") { flush() }; num.append(ch) }
            else if ch == "." { if num.contains(".") { flush() }; num.append(ch) }
            else if ch == " " || ch == "," { flush() }
            else { num.append(ch) }
        }
        flush()

        let p = UIBezierPath()
        var i = 0, cmd = "M"
        var cur = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint? = nil, lastCmd = ""
        func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = tokens[i]; i += 1; if cmd == "z" || cmd == "Z" { p.close(); cur = start; lastCtrl = nil; lastCmd = cmd; continue } }
            let rel = cmd == cmd.lowercased()
            let o = rel ? cur : .zero
            switch cmd.uppercased() {
            case "M":
                cur = CGPoint(x: o.x + n(), y: o.y + n()); p.move(to: cur); start = cur
                cmd = rel ? "l" : "L"; lastCtrl = nil   // more pairs after M are line-tos
            case "L": cur = CGPoint(x: o.x + n(), y: o.y + n()); p.addLine(to: cur); lastCtrl = nil
            case "H": cur = CGPoint(x: (rel ? cur.x : 0) + n(), y: cur.y); p.addLine(to: cur); lastCtrl = nil
            case "V": cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + n()); p.addLine(to: cur); lastCtrl = nil
            case "C":
                let c1 = CGPoint(x: o.x + n(), y: o.y + n()), c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addCurve(to: e, controlPoint1: c1, controlPoint2: c2); cur = e; lastCtrl = c2
            case "S":
                let c1 = (["C", "S"].contains(lastCmd.uppercased()) && lastCtrl != nil) ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                let c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addCurve(to: e, controlPoint1: c1, controlPoint2: c2); cur = e; lastCtrl = c2
            case "Q":
                let c = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addQuadCurve(to: e, controlPoint: c); cur = e; lastCtrl = c
            case "T":
                let c = (["Q", "T"].contains(lastCmd.uppercased()) && lastCtrl != nil) ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                let e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addQuadCurve(to: e, controlPoint: c); cur = e; lastCtrl = c
            default: i += 1
            }
            lastCmd = cmd
        }
        return p
    }
}
