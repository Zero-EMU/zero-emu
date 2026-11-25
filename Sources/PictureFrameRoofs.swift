import SwiftUI

// 画框's second scenery, 黄昏小镇的屋顶, drawn by hand in coloured pencil: a
// small town seen from a window high in a house near its edge. Just below,
// a flat roof with a chimney stack and washing on a line; across the street
// the next house's tiled slope with a cat sitting on its ridge, its back to
// us; a string of lamps over the street; the roofs row behind row down to
// the hills, the clock tower standing out of them; on the knoll at the right
// a mill. One eye, one horizon, one vanishing point: everything stands where
// its metres put it, the pictures were drawn with the same numbers, and
// what is drawn here over them (sheet points, 1000 × 600) meets them.
//
// What does not move is three pictures, one for each light (night, dusk,
// day), passed from one to the next as the light goes. What moves is drawn
// each frame: the tower clock's hands keeping the phone's time, the mill's
// sails, the vane on the spire, the smoke from a few chimneys, the cat's
// tail, the lamps' twinkle, the stars and now and then a falling star, by
// day the birds going over.

// MARK: - 黄昏小镇的屋顶: where things are

enum RoofsView {
    static let width = 1000.0, height = 600.0
    /// The tower clock: the middle of its face and the face's radius (the
    /// pictures have the face; its hands keep the phone's time).
    static let clock = CGPoint(x: 210.1, y: 231.3), clockR = 15.25
    /// The mill's hub, its sails' length, how much their circle is narrowed
    /// (they turn in a plane facing the front left, seen across 45°).
    static let millHub = CGPoint(x: 758.8, y: 222.6), sailLength = 23.7, sailSquash = 0.71
    /// The vane's pivot over the spire and how many points a metre is there.
    /// (A metre nearer the eye, up there, shows 1.79 points higher.)
    static let vane = CGPoint(x: 216.9, y: 82.8), vaneK = 7.63, vaneRise = 1.79
    /// The cat's tail, from its root down the slope toward the eye to its tip, and its thickness at the root.
    static let tail = [CGPoint(x: 876.4, y: 529.2), CGPoint(x: 895.6, y: 541.6), CGPoint(x: 912.3, y: 565.6), CGPoint(x: 916.4, y: 591.0)]
    static let tailWidth = 5.0
    /// The chimney tops that smoke and a metre there; the last is the stack on the flat roof below the window.
    static let smokers: [(x: Double, y: Double, k: Double)] = [(625.2, 339.1, 16.2), (385.1, 369.4, 16.5), (861.2, 342.7, 10.2), (162.5, 434.5, 51.1)]
    /// The lamps on the string over the street: their middles and sizes.
    static let lamps: [(x: Double, y: Double, r: Double)] = [
        (433.6, 429.3, 2.9), (448.7, 436.2, 2.8), (462.4, 441.9, 2.7), (475.0, 446.8, 2.6), (486.4, 450.8, 2.5), (497.0, 454.1, 2.4),
        (506.7, 456.8, 2.3), (515.7, 459.0, 2.2), (524.1, 460.6, 2.1), (531.9, 461.8, 2.0), (539.2, 462.5, 2.0), (546.0, 462.9, 1.9),
        (552.4, 463.0, 1.8), (558.3, 462.8, 1.8), (564.0, 462.3, 1.7), (569.3, 461.5, 1.7), (574.3, 460.5, 1.6), (579.1, 459.3, 1.6),
        (583.6, 457.9, 1.5), (587.8, 456.4, 1.5), (591.9, 454.6, 1.5), (595.7, 452.7, 1.4), (599.4, 450.7, 1.4), (602.9, 448.5, 1.4),
        (606.3, 446.2, 1.3), (609.4, 443.8, 1.3), (612.5, 441.3, 1.3), (615.4, 438.7, 1.3), (618.2, 436.0, 1.2), (620.9, 433.2, 1.2)]
    /// Stars that twinkle over the night's picture, where its sky shows.
    static let stars: [CGPoint] = [
        CGPoint(x: 16, y: 131), CGPoint(x: 81, y: 154), CGPoint(x: 252, y: 140), CGPoint(x: 254, y: 78), CGPoint(x: 289, y: 146), CGPoint(x: 380, y: 34),
        CGPoint(x: 568, y: 159), CGPoint(x: 593, y: 66), CGPoint(x: 624, y: 47), CGPoint(x: 647, y: 215), CGPoint(x: 652, y: 12), CGPoint(x: 675, y: 66),
        CGPoint(x: 687, y: 109), CGPoint(x: 716, y: 175), CGPoint(x: 759, y: 118), CGPoint(x: 761, y: 169), CGPoint(x: 809, y: 12), CGPoint(x: 878, y: 119),
        CGPoint(x: 921, y: 204), CGPoint(x: 990, y: 131)]
    /// The pictures: night, dusk, day.
    static let pictures = ["frame-town-night.jpg", "frame-town-dusk.jpg", "frame-town-day.jpg"]
    static let wind = FrameNoise(83), turning = FrameNoise(9)

    /// A colour as it is by night, at dusk and by day, and between them.
    static func tone(_ night: FrameRGB, _ dusk: FrameRGB, _ day: FrameRGB, _ light: Double) -> FrameRGB {
        let l = frameClamp(light, 0, 1)
        return l < 0.5 ? night.mixed(dusk, l * 2) : dusk.mixed(day, (l - 0.5) * 2)
    }
}

// MARK: - 黄昏小镇的屋顶: drawing it

/// The town's pictures, held while it shows.
struct RoofsKept {
    /// Night, dusk, day.
    var backs: [CGImage]
    /// (One set serves every light.)
    static func step(_ light: Double) -> Int { 0 }
    /// What is to hand without a store: the pictures read (or none).
    static func loaded() -> RoofsKept? {
        let backs = RoofsView.pictures.compactMap { TramArt.shared.image($0) }
        return backs.count == RoofsView.pictures.count ? RoofsKept(backs: backs) : nil
    }
}

/// The town at one moment.
struct RoofsPainter {
    /// Seconds the scenery has been moving.
    var t: Double
    /// 0 the night's light, a half dusk, 1 the day's.
    var light: Double
    /// The hour of the clock with its minutes (the tower's hands).
    var hour: Double

    private typealias V = RoofsView
    private static let W = RoofsView.width, H = RoofsView.height

    /// The two pictures to show for a light and how much of the second.
    static func blend(_ light: Double) -> (Int, Int, Double) {
        let l = frameClamp(light, 0, 1)
        return l < 0.5 ? (0, 1, l * 2) : (1, 2, (l - 0.5) * 2)
    }
    /// 1 at night … 0 by day.
    static func night(_ light: Double) -> Double { frameClamp(1 - light * 1.4, 0, 1) }

    /// The whole picture into `context`, covering `size`; `drift`: the
    /// picture's place moved by so many points (it is drawn a little larger
    /// than the screen so that its edge never shows).
    func draw(in context: GraphicsContext, size: CGSize, kept: RoofsKept? = nil, drift: CGSize = .zero) {
        let unit = max(size.width / Self.W, size.height / Self.H) * (drift == .zero ? 1 : 1.02)
        var g = context
        g.translateBy(x: (size.width - Self.W * unit) / 2 + drift.width, y: (size.height - Self.H * unit) / 2 + drift.height)
        g.scaleBy(x: unit, y: unit)
        let pen = FramePen(g: g)
        let whole = CGRect(x: 0, y: 0, width: Self.W, height: Self.H)
        let (a, b, d) = Self.blend(light)
        if let art = kept ?? RoofsKept.loaded() {
            g.draw(Image(decorative: art.backs[a], scale: 1), in: whole)
            if d > 0.002 {
                var over = g
                over.opacity = d
                over.draw(Image(decorative: art.backs[b], scale: 1), in: whole)
            }
        } else {
            pen.fade(Path(whole), FrameRGB(18, 25, 51).mixed(FrameRGB(118, 166, 212), light).color(), FrameRGB(57, 66, 111).mixed(FrameRGB(220, 232, 238), light).color(), y0: 0, y1: Self.H)
        }
        let dark = Self.night(light)
        let wind = (V.wind.fbm(t * 0.2, 2) - 0.5) * 2
        let ink = V.tone(FrameRGB(33, 30, 40), FrameRGB(59, 46, 53), FrameRGB(56, 52, 52), light)
        stars(pen, dark)
        birds(pen, dark)
        sails(pen)
        smoke(pen, wind)
        pen.clockHands(V.clock.x, V.clock.y, V.clockR, hour: hour, ink, width: 1.2)
        vane(pen, ink, wind)
        lamps(pen)
        tail(pen)
        // The frame's own dusk at its corners.
        g.fill(Path(whole), with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color(.sRGB, red: 10.0 / 255, green: 0, blue: 20.0 / 255, opacity: frameLerp(0.32, 0.18, light))]),
                                                 center: CGPoint(x: 500, y: 300), startRadius: 260, endRadius: 660))
    }

    // MARK: The sky

    /// Stars twinkling where the night's sky shows, and now and then one falling.
    private func stars(_ pen: FramePen, _ dark: Double) {
        let night = dark * dark
        guard night > 0.02 else { return }
        let starlight = FrameRGB(245, 238, 214)
        for (i, s) in V.stars.enumerated() {
            let twinkle = 0.5 + 0.5 * sin(t * (0.6 + Double(i % 5) * 0.21) + Double(i) * 2.9)
            let alpha = night * twinkle * twinkle * 0.8
            pen.disc(s.x, s.y, i % 4 == 0 ? 1.3 : 0.9, starlight, alpha)
            if i % 4 == 0 { pen.glow(s.x, s.y, 6, starlight, alpha * 0.4) }
        }
        let phase = (t + 11).truncatingRemainder(dividingBy: 47)
        guard phase < 1.1 else { return }
        var random = FrameRandom(UInt32(900 + Int(((t + 11) / 47).rounded(.down)) % 100_000))
        let x0: Double = 420 + random.next() * 300, y0: Double = 25 + random.next() * 70
        let u = phase / 1.1
        let x = x0 + u * 150, y = y0 + u * 56
        let alpha = sin(Double.pi * u) * night
        var trail = Path()
        trail.move(to: CGPoint(x: x - 60, y: y - 22))
        trail.addLine(to: CGPoint(x: x, y: y))
        pen.g.stroke(trail, with: .linearGradient(Gradient(colors: [Color.white.opacity(0), starlight.color(alpha)]), startPoint: CGPoint(x: x - 60, y: y - 22), endPoint: CGPoint(x: x, y: y)),
                     style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    /// Seven birds across the sky for fourteen seconds in every thirty-one
    /// (not at night).
    private func birds(_ pen: FramePen, _ dark: Double) {
        let phase = (t + 6).truncatingRemainder(dividingBy: 31)
        guard phase < 14, dark < 0.6 else { return }
        var random = FrameRandom(UInt32(40 + Int(((t + 6) / 31).rounded(.down)) % 100_000))
        let y0 = 70 + random.next() * 110
        let dir: Double = random.next() < 0.5 ? 1 : -1
        let start = dir > 0 ? -60.0 : Self.W + 60
        var path = Path()
        for i in 0..<7 {
            let place = Double(i % 4), rank = Double(i / 4)
            let bx = start + dir * (phase / 14) * (Self.W + 160) - dir * place * 22 - dir * rank * 8
            let side = i % 2 == 1 ? 1.0 : -1.0
            let by = y0 + place * 9 * side + sin(t * 1.1 + Double(i)) * 4
            let flap = sin(t * 7 + Double(i) * 1.3) * 4
            path.move(to: CGPoint(x: bx - 6, y: by - flap))
            path.addQuadCurve(to: CGPoint(x: bx, y: by + 1), control: CGPoint(x: bx - 2, y: by - 1))
            path.addQuadCurve(to: CGPoint(x: bx + 6, y: by - flap), control: CGPoint(x: bx + 2, y: by - 1))
        }
        pen.stroke(path, V.tone(FrameRGB(42, 37, 48), FrameRGB(59, 46, 53), FrameRGB(56, 52, 52), light), 0.9 * (1 - dark), width: 1.3)
    }

    // MARK: The mill, the smoke, the tower

    /// The mill's four sails, turning slowly as the wind lets them: each a
    /// spar and a lattice frame of cloth, the circle they turn in narrowed
    /// as their plane is seen across.
    private func sails(_ pen: FramePen) {
        let hx = Double(V.millHub.x), hy = Double(V.millHub.y), R = V.sailLength, sq = V.sailSquash
        let cloth = V.tone(FrameRGB(44, 49, 78), FrameRGB(144, 118, 134), FrameRGB(186, 192, 199), light)
        let ink = V.tone(FrameRGB(38, 38, 57), FrameRGB(101, 80, 87), FrameRGB(99, 100, 104), light)
        let a0 = 0.35 + t * 0.2 + 1.2 * V.turning.fbm(t * 0.04, 2)
        for i in 0..<4 {
            let a = a0 + Double(i) * Double.pi / 2
            let ca = cos(a), sa = sin(a)
            func at(_ along: Double, _ off: Double) -> (Double, Double) {
                (hx + (ca * along - sa * off) * sq, hy - (sa * along + ca * off))
            }
            let frame = [at(0.22 * R, 0), at(R, 0), at(R, 0.17 * R), at(0.22 * R, 0.17 * R)]
            pen.shape(frame, cloth, 0.6)
            pen.line([at(0, 0), at(R, 0)], ink, 0.9, width: 1.1)
            pen.line(frame + [frame[0]], ink, 0.75, width: 0.55)
            for j in 1..<5 {
                let u = 0.22 * R + Double(j) * 0.156 * R
                pen.line([at(u, 0), at(u, 0.17 * R)], ink, 0.6, width: 0.4)
            }
        }
        pen.disc(hx, hy, 1.5, ink, 0.9)
    }

    /// Smoke from a few chimneys and from the stack below the window, going
    /// up and drifting off to the right.
    private func smoke(_ pen: FramePen, _ wind: Double) {
        let colour = V.tone(FrameRGB(125, 132, 158), FrameRGB(168, 160, 178), FrameRGB(216, 216, 220), light)
        for (c, chimney) in V.smokers.enumerated() {
            let k = chimney.k
            for i in 0..<8 {
                let n = Double(i)
                let life = (t * 0.055 + n / 8 + Double(c) * 0.29).truncatingRemainder(dividingBy: 1)
                let carried = (1.68 + 0.5 * wind) * life * life * k
                let curl = sin(n * 2.1 + t * 0.35 + Double(c)) * 0.15 * life * k
                let x = chimney.x + carried + curl, y = chimney.y - 3.2 * life * k
                let r = (0.22 + 0.55 * life) * k
                let alpha = sin(Double.pi * pow(life, 0.5)) * 0.3 * (1 - life * 0.8)
                pen.soft(x, y, r, r * 0.8, colour, alpha, core: 0.25)
            }
        }
    }

    /// The vane over the spire: its arrow points into the wind, to the front
    /// left, and swings as the wind goes (drawn in the ground's plane, seen
    /// from below and across).
    private func vane(_ pen: FramePen, _ ink: FrameRGB, _ wind: Double) {
        let a = 2.36 + 0.35 * wind + 0.06 * sin(t * 0.9)
        let ax = cos(a), az = -sin(a), length = 0.88
        let vx = Double(V.vane.x), vy = Double(V.vane.y), k = V.vaneK, rise = V.vaneRise
        func at(_ m: Double, _ side: Double) -> (Double, Double) {
            // `m` metres along the arrow, `side` metres across it, as the sheet shows them
            let across = ax * m - az * side, toward = az * m + ax * side
            return (vx + across * k, vy + toward * rise)
        }
        pen.line([at(-length, 0), at(length, 0)], ink, 0.92, width: 0.6)
        pen.shape([at(length + 0.2, 0), at(length - 0.12, 0.16), at(length - 0.12, -0.16)], ink, 0.92)
        pen.shape([at(-length + 0.25, 0), at(-length - 0.08, 0.3), at(-length - 0.08, -0.26)], ink, 0.92)
    }

    // MARK: Near by

    /// The lamps on the string over the street, twinkling a little, from dusk on.
    private func lamps(_ pen: FramePen) {
        let l = frameClamp(light, 0, 1)
        let on = l < 0.5 ? frameLerp(1, 0.7, l * 2) : frameLerp(0.7, 0, (l - 0.5) * 2)
        guard on > 0.01 else { return }
        for (i, lamp) in V.lamps.enumerated() {
            let twinkle = max(0, sin(t * 1.3 + Double(i) * 2.4))
            pen.glow(lamp.x, lamp.y, max(3.5, lamp.r * 2.2), FrameRGB(255, 217, 138), 0.2 * on * twinkle * twinkle)
        }
    }

    /// The cat's tail, hanging down the slope from where it sits: now and
    /// then the tip flicks, now and then the whole of it sweeps a little.
    private func tail(_ pen: FramePen) {
        let flick = pow(max(0, sin(t * 0.45 + 1)), 3) * sin(t * 4.2)
        let sweep = sin(t * 0.6) * 0.3
        let s = 0.7 * flick + sweep
        let count = V.tail.count
        var xs: [Double] = [], ys: [Double] = []
        for (i, p) in V.tail.enumerated() {
            let u = Double(i) / Double(count - 1)
            xs.append(Double(p.x) + s * u * u * 9)
            ys.append(Double(p.y) - abs(s) * u * u * 2)
        }
        // Along a smooth line through them (Catmull-Rom), thinner toward the tip, round at both ends.
        func curve(_ v: [Double], _ i: Int, _ u: Double) -> Double {
            let a = v[max(0, i - 1)], b = v[i], c = v[i + 1], d = v[min(count - 1, i + 2)]
            let k1 = c - a
            let k2 = 2 * a - 5 * b + 4 * c - d
            let k3 = 3 * b - a - 3 * c + d
            return b + 0.5 * (k1 * u + k2 * u * u + k3 * u * u * u)
        }
        var line: [(Double, Double)] = []
        for i in 0..<(count - 1) {
            for j in 0..<8 {
                let u = Double(j) / 8
                line.append((curve(xs, i, u), curve(ys, i, u)))
            }
        }
        line.append((xs[count - 1], ys[count - 1]))
        let colour = V.tone(FrameRGB(19, 17, 23), FrameRGB(32, 26, 31), FrameRGB(38, 32, 34), light)
        var left: [(Double, Double)] = [], right: [(Double, Double)] = []
        let last = Double(line.count - 1)
        for (i, p) in line.enumerated() {
            let q0 = line[max(0, i - 1)], q1 = line[min(line.count - 1, i + 1)]
            let dx = q1.0 - q0.0, dy = q1.1 - q0.1
            let length = max(0.001, (dx * dx + dy * dy).squareRoot())
            let half = V.tailWidth / 2 * (1 - 0.55 * Double(i) / last)
            let nx = -dy / length * half, ny = dx / length * half
            left.append((p.0 + nx, p.1 + ny))
            right.append((p.0 - nx, p.1 - ny))
        }
        pen.shape(left + right.reversed(), colour)
        pen.disc(line[0].0, line[0].1, V.tailWidth / 2, colour)
        pen.disc(line[line.count - 1].0, line[line.count - 1].1, V.tailWidth / 2 * 0.45, colour)
    }
}

// MARK: - The kept pictures

/// Reads the town's pictures when the scenery is shown, lets them go when another is.
@MainActor final class RoofsKeptStore: ObservableObject {
    @Published private(set) var kept: RoofsKept?
    func prepare(light: Double, pixelWidth: Int) {
        guard kept == nil else { return }
        kept = RoofsKept.loaded()
    }
    /// The pictures let go (another scenery is showing).
    func release() {
        guard kept != nil else { return }
        kept = nil
        TramArt.shared.forget()
    }
}
