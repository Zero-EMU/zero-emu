import SwiftUI
import Combine

// 开箱仪式: the moment a 典藏卡带 has been bought. An old paper box rises
// on the upper screen; a finger across the lower one tears its seal (or it
// tears by itself a little after the box has risen); the lid comes off,
// light comes out of the box, the card rises, turns once in the air and
// drops into the console's slot with a click. Then its films begin, with
// their opening. Each metal has its own box: 金 a yellowed gold one with a
// red band and seal, 银 grey-blue with blue, 铜 kraft paper with dark green.

/// Where the ceremony is: since when, and when the seal tore.
@MainActor final class UnboxRun: ObservableObject {
    static let shared = UnboxRun()
    @Published private(set) var cartridge = Cartridge.gold
    @Published private(set) var began = Date()
    @Published private(set) var tornAt: Date?
    /// The card has clicked into the slot.
    @Published private(set) var seated = false
    private var sounded: Set<String> = []
    private var over = false
    /// A debug build's `--foldarc-unbox=off`: a purchase goes straight on,
    /// as before there was a ceremony (the tests written before it). The
    /// last such argument counts.
    static var enabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.last(where: { $0.hasPrefix("--foldarc-unbox=") }) != "--foldarc-unbox=off"
        #else
        return true
        #endif
    }
    func start(_ cartridge: Cartridge) {
        self.cartridge = cartridge
        began = Date()
        tornAt = nil
        seated = false
        sounded = []
        over = false
        NSLog("[unbox] the %@ box", cartridge.rawValue)
    }
    /// The seal torn (a finger, A, or the wait run out).
    func tear(by finger: Bool) {
        guard tornAt == nil else { return }
        tornAt = Date()
        ConsoleSounds.shared.play(.rip)
        ConsoleHaptics.shared.play(.lidOpen, .press)
        NSLog("[unbox] the seal torn (%@)", finger ? "a finger" : "by itself")
    }
    /// Seconds into the ceremony, and since the tear (nil: not torn yet).
    func times(_ now: Date) -> (t: Double, torn: Double?) {
        (now.timeIntervalSince(began), tornAt.map { now.timeIntervalSince($0) })
    }
    /// The clock's tick: the box landing, the seal tearing by itself, the
    /// lid's chime, the card's click. True once, when it is all over.
    func tick(_ now: Date) -> Bool {
        let (t, torn) = times(now)
        if t >= UnboxTimes.boxRise - 0.12, sounded.insert("land").inserted { ConsoleHaptics.shared.play(.lidShut, .press) }
        if tornAt == nil, t >= UnboxTimes.boxRise + UnboxTimes.wait { tear(by: false) }
        guard let torn else { return false }
        if torn >= UnboxTimes.lid, sounded.insert("lid").inserted { ConsoleSounds.shared.play(.chime) }
        if torn >= UnboxTimes.seated, sounded.insert("seat").inserted {
            seated = true
            ConsoleSounds.shared.play(.click)
            ConsoleHaptics.shared.play(.shoulder, .press)
            NSLog("[unbox] the %@ card in the slot", cartridge.rawValue)
        }
        if torn >= UnboxTimes.over, !over {
            over = true
            return true
        }
        return false
    }
    /// B: the ceremony left at once (its films begin all the same).
    func skip() {
        guard !over else { return }
        over = true
        NSLog("[unbox] skipped")
    }
    var phase: String {
        guard let tornAt else { return Date().timeIntervalSince(began) < UnboxTimes.boxRise ? "rising" : "waiting" }
        let torn = Date().timeIntervalSince(tornAt)
        return torn < UnboxTimes.drop ? "opening" : (torn < UnboxTimes.seated ? "dropping" : "seated")
    }
}

/// The ceremony's times (seconds): the box's rise, the wait before the seal
/// tears by itself; after the tear, each step, and the end.
enum UnboxTimes {
    static let boxRise = 0.9, wait = 2.0
    static let seal = 0.0, lid = 0.3, rise = 0.75, sink = 1.35, spin = 1.4, slot = 1.5, drop = 2.25, seated = 2.6, over = 3.1
}

/// One box's colours.
struct UnboxStyle {
    var box: (Double, Double, Double), boxDeep: (Double, Double, Double), frame: (Double, Double, Double)
    var band: (Double, Double, Double), seal: (Double, Double, Double), sealInk: (Double, Double, Double)
    var glow: (Double, Double, Double)
    static func of(_ cartridge: Cartridge) -> UnboxStyle {
        switch cartridge {
        case .gold:
            return UnboxStyle(box: (0.85, 0.69, 0.33), boxDeep: (0.66, 0.50, 0.20), frame: (0.55, 0.40, 0.14),
                              band: (0.66, 0.17, 0.16), seal: (0.97, 0.93, 0.84), sealInk: (0.66, 0.17, 0.16), glow: (1.0, 0.86, 0.50))
        case .silver:
            return UnboxStyle(box: (0.66, 0.71, 0.77), boxDeep: (0.48, 0.53, 0.61), frame: (0.82, 0.85, 0.89),
                              band: (0.20, 0.33, 0.56), seal: (0.93, 0.95, 0.98), sealInk: (0.20, 0.33, 0.56), glow: (0.86, 0.92, 1.0))
        case .bronze:
            return UnboxStyle(box: (0.75, 0.59, 0.40), boxDeep: (0.58, 0.43, 0.27), frame: (0.70, 0.42, 0.24),
                              band: (0.16, 0.36, 0.28), seal: (0.83, 0.70, 0.50), sealInk: (0.16, 0.36, 0.28), glow: (1.0, 0.80, 0.56))
        }
    }
}

/// The ceremony drawn at a moment: `t` seconds in, `torn` seconds after the
/// tear (nil: not yet); the card's face comes in as a resolved symbol. The
/// sheet is 400 × 240, fitted to the screen.
struct UnboxPainter {
    var cartridge: Cartridge
    var t: Double
    var torn: Double?
    var title: String
    var subtitle: String

    private func c(_ v: (Double, Double, Double), _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }
    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    private static func smooth(_ v: Double) -> Double { let k = clamp(v); return k * k * (3 - 2 * k) }
    private static func back(_ v: Double) -> Double { // ease out with a small overshoot
        let k = clamp(v) - 1, s = 1.6
        return 1 + (s + 1) * k * k * k + s * k * k
    }
    private static func easeIn(_ v: Double) -> Double { let k = clamp(v); return k * k * k }

    func draw(_ context: GraphicsContext, size: CGSize, card: GraphicsContext.ResolvedSymbol?) {
        let unit = min(Double(size.width) / 400, Double(size.height) / 240)
        var g = context
        g.translateBy(x: (Double(size.width) - 400 * unit) / 2, y: (Double(size.height) - 240 * unit) / 2)
        g.scaleBy(x: unit, y: unit)
        let style = UnboxStyle.of(cartridge)
        // The room: dark, a warm light from above.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.12, green: 0.085, blue: 0.075)))
        g.fill(Path(ellipseIn: CGRect(x: 60, y: -140, width: 280, height: 360)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.62).opacity(0.22), .clear]), center: CGPoint(x: 200, y: 40), startRadius: 4, endRadius: 190))
        let after = torn ?? -1
        // Where the box is: rising, at rest, sinking away.
        let riseOffset = 200 * (1 - Self.back(t / UnboxTimes.boxRise))
        let sinkOffset = after > UnboxTimes.sink ? 230 * Self.easeIn((after - UnboxTimes.sink) / 0.6) : 0
        let boxY = riseOffset + sinkOffset
        let top = 72.0 + boxY, left = 152.0, w = 96.0, h = 112.0, depth = (24.0, -14.0), lidH = 22.0
        // With the lid off, the box opens at the top of its body.
        let mouthY = top + lidH
        // The shadow under it.
        g.fill(Path(ellipseIn: CGRect(x: left - 10, y: top + h - 8, width: w + 52, height: 18)), with: .color(.black.opacity(0.35 * (1 - Self.clamp(boxY / 120)))))
        // The light coming out of the open box.
        let open = after >= UnboxTimes.lid ? Self.smooth((after - UnboxTimes.lid) / 0.4) : 0
        let light = open * (1 - Self.smooth((after - UnboxTimes.sink) / 0.5))
        if light > 0.01 {
            let mouth = CGPoint(x: left + w / 2 + depth.0 / 2, y: mouthY + depth.1 / 2)
            for k in 0..<7 {
                let a = (-0.5 + Double(k) / 6) * 1.25 - Double.pi / 2
                var ray = Path()
                ray.move(to: CGPoint(x: mouth.x - 16, y: mouth.y))
                ray.addLine(to: CGPoint(x: mouth.x + cos(a - 0.08) * 170, y: mouth.y + sin(a - 0.08) * 170))
                ray.addLine(to: CGPoint(x: mouth.x + cos(a + 0.08) * 170, y: mouth.y + sin(a + 0.08) * 170))
                ray.addLine(to: CGPoint(x: mouth.x + 16, y: mouth.y))
                ray.closeSubpath()
                g.fill(ray, with: .linearGradient(Gradient(colors: [c(style.glow, 0.42 * light), c(style.glow, 0)]), startPoint: mouth,
                                                  endPoint: CGPoint(x: mouth.x + cos(a) * 170, y: mouth.y + sin(a) * 170)))
            }
            g.fill(Path(ellipseIn: CGRect(x: mouth.x - 70, y: mouth.y - 40, width: 140, height: 80)),
                   with: .radialGradient(Gradient(colors: [c(style.glow, 0.55 * light), c(style.glow, 0)]), center: mouth, startRadius: 2, endRadius: 70))
        }
        // The box's inside, seen when the lid is off.
        if open > 0 {
            var inside = Path()
            inside.move(to: CGPoint(x: left + 3, y: mouthY))
            inside.addLine(to: CGPoint(x: left + 3 + depth.0, y: mouthY + depth.1 + 2))
            inside.addLine(to: CGPoint(x: left + w - 3 + depth.0, y: mouthY + depth.1 + 2))
            inside.addLine(to: CGPoint(x: left + w - 3, y: mouthY))
            inside.closeSubpath()
            g.fill(inside, with: .color(c(style.boxDeep, 1).opacity(0.9)))
            g.fill(inside, with: .color(c(style.glow, 0.35 * light)))
        }
        // The card: rising out of the box, turning, dropping into the slot.
        let slotY = 214.0
        if after >= UnboxTimes.rise, let card {
            let rise = Self.smooth((after - UnboxTimes.rise) / 0.6)
            let drop = Self.easeIn((after - UnboxTimes.drop) / (UnboxTimes.seated - UnboxTimes.drop))
            let restY = 66.0
            let startY = mouthY + 40
            let cy = after < UnboxTimes.drop ? startY + (restY - startY) * rise : restY + (slotY + 40 - restY) * drop
            let spin = Self.smooth((after - UnboxTimes.spin) / 0.7) * 2 * Double.pi
            let face = cos(spin)
            var cardContext = g
            if after < UnboxTimes.sink + 0.1 {
                // Still in the box: only what is above its mouth shows.
                cardContext.clip(to: Path(CGRect(x: 0, y: -200, width: 400, height: mouthY + 200)))
            }
            if after >= UnboxTimes.drop - 0.05 {
                // Into the slot: what is below its line is inside the console.
                cardContext.clip(to: Path(CGRect(x: 0, y: -200, width: 400, height: slotY + 200)))
            }
            // Larger while it is out in the air, its own size again going into the slot.
            let big = 1 + 0.45 * Self.smooth((after - UnboxTimes.rise) / 0.6) - 0.45 * Self.smooth((after - UnboxTimes.drop) / 0.25)
            cardContext.translateBy(x: 200, y: cy)
            cardContext.scaleBy(x: big * max(0.04, abs(face)), y: big)
            if face >= 0 {
                cardContext.draw(card, at: .zero, anchor: .center)
            } else {
                // Its back: plain moulded plastic in the card's metal.
                let tint = cartridge.tint.metal
                cardContext.fill(Path(roundedRect: CGRect(x: -31, y: -29.5, width: 62, height: 59), cornerRadius: 5),
                                 with: .color(Color(red: tint.0 * 0.85, green: tint.1 * 0.85, blue: tint.2 * 0.85)))
                cardContext.stroke(Path(roundedRect: CGRect(x: -25, y: -23, width: 50, height: 40), cornerRadius: 3), with: .color(.black.opacity(0.18)), lineWidth: 1)
            }
            // A glint when the turn is done.
            let glint = after - (UnboxTimes.spin + 0.7)
            if glint > 0, glint < 0.45, after < UnboxTimes.drop {
                let x = -40 + glint / 0.45 * 80
                var streak = Path()
                streak.move(to: CGPoint(x: x - 8, y: -32)); streak.addLine(to: CGPoint(x: x + 6, y: -32))
                streak.addLine(to: CGPoint(x: x - 6, y: 32)); streak.addLine(to: CGPoint(x: x - 20, y: 32)); streak.closeSubpath()
                var shine = cardContext
                shine.clip(to: Path(roundedRect: CGRect(x: -31, y: -29.5, width: 62, height: 59), cornerRadius: 5))
                shine.fill(streak, with: .color(.white.opacity(0.55)))
            }
        }
        // The console's slot, below.
        let slotShown = Self.smooth((after - UnboxTimes.slot) / 0.5)
        if slotShown > 0 {
            var slot = g
            slot.opacity = slotShown
            let rim = Path(roundedRect: CGRect(x: 150, y: slotY - 7, width: 100, height: 22), cornerRadius: 7)
            slot.fill(rim, with: .color(Color(red: 0.20, green: 0.42, blue: 0.53)))
            slot.fill(Path(roundedRect: CGRect(x: 160, y: slotY - 2, width: 80, height: 7), cornerRadius: 3), with: .color(Color(red: 0.04, green: 0.04, blue: 0.05)))
            let flash = after - UnboxTimes.seated
            if flash > 0, flash < 0.6 {
                slot.fill(Path(ellipseIn: CGRect(x: 120, y: slotY - 30, width: 160, height: 60)),
                          with: .radialGradient(Gradient(colors: [c(style.glow, 0.7 * (1 - flash / 0.6)), c(style.glow, 0)]), center: CGPoint(x: 200, y: slotY), startRadius: 2, endRadius: 80))
            }
        }
        // The box's body (its front below the lid, its side) and the lid.
        if boxY < 235 {
            drawBody(g, style: style, left: left, top: top, w: w, h: h, depth: depth, lidH: lidH)
            if open > 0 {
                var rim = Path()
                rim.move(to: CGPoint(x: left, y: mouthY)); rim.addLine(to: CGPoint(x: left + w, y: mouthY))
                rim.addLine(to: CGPoint(x: left + w + depth.0, y: mouthY + depth.1))
                g.stroke(rim, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
            }
            drawSeal(g, style: style, left: left, top: top, w: w, lidH: lidH, after: after, lower: true)
            let lift = after >= UnboxTimes.lid ? Self.smooth((after - UnboxTimes.lid) / 0.45) : 0
            let gone = after >= UnboxTimes.lid + 0.35 ? Self.smooth((after - UnboxTimes.lid - 0.35) / 0.35) : 0
            if gone < 1 {
                var lid = g
                lid.opacity = 1 - gone
                lid.translateBy(x: left + w + depth.0, y: top + depth.1)
                lid.rotate(by: .degrees(14 * lift))
                lid.translateBy(x: -(left + w + depth.0) + 26 * lift, y: -(top + depth.1) - 46 * lift)
                drawLid(lid, style: style, left: left, top: top, w: w, depth: depth, lidH: lidH)
                drawSeal(lid, style: style, left: left, top: top, w: w, lidH: lidH, after: after, lower: false)
            }
        }
        // Bits of the seal flying off as it tears.
        if after >= 0, after < 0.9 {
            var bits = ReelRandom(seed: 0x5EA1)
            for k in 0..<10 {
                let vx = (bits.unit() - 0.5) * 140, vy = -60 - 80 * bits.unit(), spin = (bits.unit() - 0.5) * 12
                let x = left + w / 2 + vx * after, y = top + lidH + vy * after + 260 * after * after
                var bit = g
                bit.opacity = 1 - after / 0.9
                bit.translateBy(x: x, y: y)
                bit.rotate(by: .radians(spin * after))
                bit.fill(Path(CGRect(x: -2.5, y: -1.5, width: 5, height: 3)), with: .color(k % 3 == 0 ? c(style.sealInk) : c(style.seal)))
            }
        }
    }

    /// The front below the lid, and the side.
    private func drawBody(_ g: GraphicsContext, style: UnboxStyle, left: Double, top: Double, w: Double, h: Double, depth: (Double, Double), lidH: Double) {
        let y0 = top + lidH
        // the side
        var side = Path()
        side.move(to: CGPoint(x: left + w, y: y0)); side.addLine(to: CGPoint(x: left + w + depth.0, y: y0 + depth.1))
        side.addLine(to: CGPoint(x: left + w + depth.0, y: top + h + depth.1)); side.addLine(to: CGPoint(x: left + w, y: top + h)); side.closeSubpath()
        g.fill(side, with: .color(c(style.boxDeep)))
        g.stroke(side, with: .color(.black.opacity(0.25)), lineWidth: 0.6)
        // the front
        let front = Path(CGRect(x: left, y: y0, width: w, height: h - lidH))
        g.fill(front, with: .linearGradient(Gradient(colors: [c(style.box), c(style.boxDeep, 1).opacity(0.95)]), startPoint: CGPoint(x: left, y: y0), endPoint: CGPoint(x: left + w, y: top + h)))
        // foil frame, worn corners
        g.stroke(Path(CGRect(x: left + 4, y: y0 + 2, width: w - 8, height: h - lidH - 6)), with: .color(c(style.frame, 0.8)), lineWidth: 0.9)
        for (x, y) in [(left, top + h), (left + w, top + h)] {
            g.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(.white.opacity(0.13)))
        }
        // the label: cream, a thin frame in the band's colour, the console (open) in white on a
        // rounded square in the middle, a small four-pointed sparkle either side (no rays, no disc)
        let label = CGRect(x: left + 12, y: y0 + 8, width: w - 24, height: 44)
        g.fill(Path(label), with: .color(Color(red: 0.96, green: 0.92, blue: 0.82)))
        g.stroke(Path(label.insetBy(dx: 2.5, dy: 2.5)), with: .color(c(style.band, 0.75)), lineWidth: 0.6)
        g.stroke(Path(label), with: .color(c(style.frame, 0.7)), lineWidth: 0.7)
        let center = CGPoint(x: label.midX, y: label.midY)
        let tile = CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26)
        g.fill(Path(roundedRect: tile, cornerRadius: 5, style: .continuous), with: .color(c(style.band)))
        g.stroke(Path(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerRadius: 3.5, style: .continuous), with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 1.5]))
        for side in [-1.0, 1.0] {
            let sx = center.x + side * 24, sy = center.y - 3, r = 3.5
            var spark = Path()
            spark.move(to: CGPoint(x: sx, y: sy - r))
            spark.addLine(to: CGPoint(x: sx + r * 0.25, y: sy - r * 0.25))
            spark.addLine(to: CGPoint(x: sx + r, y: sy))
            spark.addLine(to: CGPoint(x: sx + r * 0.25, y: sy + r * 0.25))
            spark.addLine(to: CGPoint(x: sx, y: sy + r))
            spark.addLine(to: CGPoint(x: sx - r * 0.25, y: sy + r * 0.25))
            spark.addLine(to: CGPoint(x: sx - r, y: sy))
            spark.addLine(to: CGPoint(x: sx - r * 0.25, y: sy - r * 0.25))
            spark.closeSubpath()
            g.fill(spark, with: .color(c(style.band, 0.7)))
        }
        // the console: its lid and its base in white; the lid's wide screen, the base's small one,
        // the round pad above the cross at the left and the four buttons at the right in the band's colour
        var shell = Path()
        shell.addRoundedRect(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 7.6), cornerSize: CGSize(width: 1.8, height: 1.8))
        shell.addRoundedRect(in: CGRect(x: center.x - 8, y: center.y + 0.6, width: 16, height: 7.6), cornerSize: CGSize(width: 1.8, height: 1.8))
        g.fill(shell, with: .color(.white))
        var marks = Path()
        marks.addRect(CGRect(x: center.x - 5.4, y: center.y - 6.4, width: 10.8, height: 4.6))
        marks.addRect(CGRect(x: center.x - 3.2, y: center.y + 2.1, width: 6.4, height: 4.4))
        marks.addEllipse(in: CGRect(x: center.x - 6.85, y: center.y + 2.05, width: 1.9, height: 1.9))
        marks.addRect(CGRect(x: center.x - 6.4, y: center.y + 4.8, width: 1, height: 2.6))
        marks.addRect(CGRect(x: center.x - 7.2, y: center.y + 5.6, width: 2.6, height: 1))
        for (bx, by) in [(5.9, 3.2), (6.8, 4.4), (5.0, 4.4), (5.9, 5.6)] {
            marks.addEllipse(in: CGRect(x: center.x + bx - 0.55, y: center.y + by - 0.55, width: 1.1, height: 1.1))
        }
        g.fill(marks, with: .color(c(style.band)))
        // the band, its words (the box's art, as the seal's 封 and date: the same in every language)
        let band = CGRect(x: left, y: y0 + 58, width: w, height: 13)
        g.fill(Path(band), with: .color(c(style.band)))
        g.draw(Text(verbatim: "典藏卡带").font(.system(size: 7.5, weight: .heavy, design: .serif)).foregroundStyle(Color(red: 1, green: 0.96, blue: 0.86)),
               at: CGPoint(x: band.midX, y: band.midY), anchor: .center)
        g.draw(Text(verbatim: "\(title) · \(subtitle)").font(.system(size: 5.5, weight: .bold)).foregroundStyle(c(style.frame).opacity(0.95)),
               at: CGPoint(x: left + w / 2, y: y0 + 80), anchor: .center)
    }

    /// The lid: its front band (the wordmark on it), its top, its side band.
    private func drawLid(_ g: GraphicsContext, style: UnboxStyle, left: Double, top: Double, w: Double, depth: (Double, Double), lidH: Double) {
        var topFace = Path()
        topFace.move(to: CGPoint(x: left, y: top)); topFace.addLine(to: CGPoint(x: left + depth.0, y: top + depth.1))
        topFace.addLine(to: CGPoint(x: left + w + depth.0, y: top + depth.1)); topFace.addLine(to: CGPoint(x: left + w, y: top)); topFace.closeSubpath()
        g.fill(topFace, with: .color(c(style.box).opacity(1)))
        g.fill(topFace, with: .color(.white.opacity(0.12)))
        var side = Path()
        side.move(to: CGPoint(x: left + w, y: top)); side.addLine(to: CGPoint(x: left + w + depth.0, y: top + depth.1))
        side.addLine(to: CGPoint(x: left + w + depth.0, y: top + lidH + depth.1)); side.addLine(to: CGPoint(x: left + w, y: top + lidH)); side.closeSubpath()
        g.fill(side, with: .color(c(style.boxDeep)))
        let front = Path(CGRect(x: left, y: top, width: w, height: lidH))
        g.fill(front, with: .color(c(style.box)))
        g.stroke(front, with: .color(.black.opacity(0.22)), lineWidth: 0.6)
        g.stroke(Path(CGRect(x: left + 3, y: top + 3, width: w - 6, height: lidH - 6)), with: .color(c(style.frame, 0.7)), lineWidth: 0.7)
        // the wordmark: the arc and ZERO
        var arc = Path()
        arc.addArc(center: CGPoint(x: left + 14, y: top + 13), radius: 4.2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        g.stroke(arc, with: .color(Color(red: 0.25, green: 0.16, blue: 0.10)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        g.draw(Text(verbatim: "ZERO").font(.system(size: 6.5, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.10)),
               at: CGPoint(x: left + 22, y: top + 12), anchor: .leading)
        g.stroke(topFace, with: .color(.black.opacity(0.2)), lineWidth: 0.6)
    }

    /// The seal over the lid's edge: its upper part on the lid, its lower on
    /// the box; the stamp across the line where it tears.
    private func drawSeal(_ g: GraphicsContext, style: UnboxStyle, left: Double, top: Double, w: Double, lidH: Double, after: Double, lower: Bool) {
        let x = left + w / 2 + 14, sw = 13.0
        let line = top + lidH
        var part = g
        if lower {
            // Torn: the lower part swings down and falls.
            if after >= 0 {
                let u = after / 0.7
                guard u < 1 else { return }
                part.opacity = 1 - Self.smooth((u - 0.5) / 0.5)
                part.translateBy(x: x - sw / 2, y: line)
                part.rotate(by: .degrees(-70 * Self.smooth(u)))
                part.translateBy(x: -(x - sw / 2) - 10 * u, y: -line + 60 * u * u)
            }
            part.clip(to: Path(CGRect(x: x - sw / 2 - 1, y: line, width: sw + 2, height: 40)))
        } else {
            part.clip(to: Path(CGRect(x: x - sw / 2 - 1, y: top - 12, width: sw + 2, height: lidH + 12)))
        }
        // over the lid's top, then down the front
        var onTop = Path()
        onTop.move(to: CGPoint(x: x - sw / 2, y: top)); onTop.addLine(to: CGPoint(x: x - sw / 2 + 9, y: top - 5.25))
        onTop.addLine(to: CGPoint(x: x + sw / 2 + 9, y: top - 5.25)); onTop.addLine(to: CGPoint(x: x + sw / 2, y: top)); onTop.closeSubpath()
        part.fill(onTop, with: .color(c(style.seal)))
        let strip = Path(CGRect(x: x - sw / 2, y: top, width: sw, height: lidH + 26))
        part.fill(strip, with: .color(c(style.seal)))
        part.stroke(Path(CGRect(x: x - sw / 2 + 1.2, y: top - 1, width: sw - 2.4, height: lidH + 28)), with: .color(c(style.sealInk, 0.8)), lineWidth: 0.6)
        // the stamp, 封, right on the line
        part.fill(Path(ellipseIn: CGRect(x: x - 5.8, y: line - 5.8, width: 11.6, height: 11.6)), with: .color(c(style.sealInk)))
        part.draw(Text(verbatim: "封").font(.system(size: 6.5, weight: .heavy, design: .serif)).foregroundStyle(Color(red: 1, green: 0.96, blue: 0.88)),
                  at: CGPoint(x: x, y: line), anchor: .center)
        part.draw(Text(verbatim: "二〇二六").font(.system(size: 3.6, weight: .bold, design: .serif)).foregroundStyle(c(style.sealInk)),
                  at: CGPoint(x: x, y: line + 14), anchor: .center)
        if !lower || after >= 0 {
            // the torn edge: a ragged white line
            if after >= 0 {
                var rag = Path()
                rag.move(to: CGPoint(x: x - sw / 2, y: line))
                for i in 1...6 { rag.addLine(to: CGPoint(x: x - sw / 2 + Double(i) * sw / 6, y: line + (i % 2 == 0 ? 0.9 : -0.9))) }
                part.stroke(rag, with: .color(.white.opacity(0.9)), lineWidth: 0.8)
            }
        }
    }
}

/// The upper screen while the box is opened.
struct UnboxScreen: View {
    @ObservedObject var model: ConsoleAppModel
    @ObservedObject private var run = UnboxRun.shared
    private let clock = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    var body: some View {
        let cartridge = run.cartridge
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let moment = run.times(timeline.date)
            Canvas { context, size in
                UnboxPainter(cartridge: cartridge, t: moment.t, torn: moment.torn, title: cartridge.title, subtitle: cartridge.subtitle)
                    .draw(context, size: size, card: context.resolveSymbol(id: 0))
            } symbols: {
                GameCardFace(card: GameCardInfo.card(for: cartridge), s: 1).frame(width: 62, height: 59).tag(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.12, green: 0.085, blue: 0.075))
        .onReceive(clock) { now in
            if run.tick(now) { UnboxScreen.finish(model) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(cartridge.title)"))
        .accessibilityValue(Text(verbatim: run.phase))
        .accessibilityIdentifier("unbox-screen")
    }
    /// Over: the card's films, from their opening.
    static func finish(_ model: ConsoleAppModel) {
        guard model.page == .unbox else { return }
        GoldReel.shared.rewind(UnboxRun.shared.cartridge)
        model.replace(with: .reel)
    }
}

/// The lower screen: where a finger tears the seal; A tears it too; B
/// leaves the ceremony for the films at once.
struct UnboxPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var run = UnboxRun.shared
    var body: some View {
        register()
        let shape = RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
        // What the pad says: before the tear, while the card is in the air,
        // once it has clicked in.
        let words: (symbol: String, title: String, note: String) = run.tornAt == nil
            ? ("hand.draw", String(localized: "划一下，撕开封条"), String(localized: "不想划也行：等两秒，它自己开。"))
            : (run.seated ? ("sparkles", String(localized: "卡带进掌机了"), String(localized: "接着就是开场。"))
                          : ("shippingbox", String(localized: "盒子打开了"), String(localized: "卡带马上就进掌机。")))
        return VStack(spacing: 10 * s) {
            VStack(spacing: 6 * s) {
                Image(systemName: words.symbol)
                    .font(.system(size: 22 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
                Text(words.title)
                    .font(.system(size: 13 * s, weight: .bold, design: .rounded))
                Text(words.note)
                    .font(.system(size: 9 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(SystemMenuStyle.tile.opacity(0.5)))
            .overlay(shape.strokeBorder(SystemMenuStyle.tileEdge, style: StrokeStyle(lineWidth: 1.6 * s, dash: [6 * s, 5 * s])))
            .overlay { if model.focus == "unbox.tear" { MenuCursorRing(shape: shape, s: s) } }
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 16 * s).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                run.tear(by: true)
            })
            .onTapGesture { model.focus = "unbox.tear" }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { run.tear(by: true) }
            .accessibilityIdentifier("unbox-swipe")
            AppNote(text: String(localized: "B 跳过，直接放片子。"), s: s)
        }
        .padding(10 * s)
    }
    private func register() {
        guard model.page == .unbox else { return }
        model.layout = [["unbox.tear"], [ConsoleAppModel.barLeft]]
        model.handlers = ["unbox.tear": { run.tear(by: true) }, ConsoleAppModel.barLeft: { leave() }]
        model.adjusters = ["unbox.tear": { _ in run.tear(by: true) }]
        model.registered(initial: "unbox.tear")
    }
    private func leave() {
        run.skip()
        UnboxScreen.finish(model)
    }
}
