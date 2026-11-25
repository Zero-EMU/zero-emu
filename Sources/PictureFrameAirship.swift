import SwiftUI

// 画框's fourth scenery, 云上的飞艇, drawn by hand in coloured pencil. The
// eye is up among the clouds' tops: the sea of cloud runs off to just under
// the horizon, far peaks stand out of it, a small island floats at the
// right with a tree, a hut and a waterfall falling into the cloud. An old
// airship holds its place against the wind: its propeller pushes it forward
// (to the left), the wind pushes it back, so it stays where it is while the
// clouds drift past under it to the right and its pennants stream back
// toward the stern. One light in each picture: by day the sun high at the
// upper right, at dusk the low sun behind the island, by night the moon at
// the upper left (the ship's round windows lit).
//
// The sky with the peaks, the far cloud and the island is a picture for
// each light, passed from one to the next; the two nearer bands of cloud are
// pictures that tile across and slide; the ship is a picture too. Drawn each
// frame: the bands' drift, the ship's slow rise and fall, its propeller and
// pennants, its shadow on the cloud, the waterfall, the stars, the birds,
// the low sun's light up the sky.

// MARK: - 云上的飞艇: where things are

enum AirshipView {
    static let width = 1000.0, height = 600.0, horizon = 228.0
    /// The ship's picture (380 × 210 units, the envelope's middle at 180, 78) and where that middle hangs.
    static let shipSize = CGSize(width: 380, height: 210), shipAnchor = CGPoint(x: 180, y: 78), shipAt = CGPoint(x: 360, y: 150)
    /// On the ship (from the envelope's middle): the propeller's hub; the pennants' line, from the nose by a bow to the gondola's bow.
    static let hub = CGPoint(x: 86, y: 102), bladeLength = 19.0
    static let lineFrom = CGPoint(x: -161, y: 6), lineBend = CGPoint(x: -135, y: 60), lineTo = CGPoint(x: -85, y: 82)
    /// The gondola's clock (the ship's picture has its face; its hands keep the phone's time): middle, face's radius.
    static let clock = CGPoint(x: 36, y: 103), clockR = 12.5
    /// The two bands of cloud that slide (2000 units across, tiling): their tops, their speeds to the right (units a second).
    static let midTop = 230.0, nearTop = 290.0, midSpeed = 2.6, nearSpeed = 6.0, stripWidth = 2000.0
    /// Where the waterfall leaves the island's edge, and where it meets the cloud.
    static let fallTop = CGPoint(x: 860, y: 236), fallFoot = 292.0
    /// The low sun at dusk (behind the island).
    static let sun = CGPoint(x: 820, y: 232)
    static let pictures = ["frame-air-night.jpg", "frame-air-dusk.jpg", "frame-air-day.jpg"]
    static let mids = ["frame-air-cloud-mid-night.png", "frame-air-cloud-mid-dusk.png", "frame-air-cloud-mid-day.png"]
    static let nears = ["frame-air-cloud-near-night.png", "frame-air-cloud-near-dusk.png", "frame-air-cloud-near-day.png"]
    static let ships = ["frame-air-ship-night.png", "frame-air-ship-dusk.png", "frame-air-ship-day.png"]
    /// Stars that twinkle over the night's picture (sheet points), the same every time.
    static let stars: [CGPoint] = {
        var r = FrameRandom(919)
        return (0..<40).map { _ in CGPoint(x: r.next() * width, y: r.next() * (horizon - 40)) }
    }()
    static let bob = FrameNoise(17)
}

/// The scenery's pictures, held while it shows: for each light (night,
/// dusk, day) the sky, the two bands of cloud and the ship.
struct AirshipKept {
    var backs: [CGImage], mids: [CGImage], nears: [CGImage], ships: [CGImage]
    /// (One set serves every light.)
    static func step(_ light: Double) -> Int { 0 }
    static func loaded() -> AirshipKept? {
        func read(_ files: [String]) -> [CGImage]? {
            let images = files.compactMap { TramArt.shared.image($0) }
            return images.count == files.count ? images : nil
        }
        guard let backs = read(AirshipView.pictures), let mids = read(AirshipView.mids), let nears = read(AirshipView.nears), let ships = read(AirshipView.ships) else { return nil }
        return AirshipKept(backs: backs, mids: mids, nears: nears, ships: ships)
    }
}

/// Reads the scenery's pictures when it is shown, lets them go when another is.
@MainActor final class AirshipKeptStore: ObservableObject {
    @Published private(set) var kept: AirshipKept?
    func prepare(light: Double, pixelWidth: Int) {
        guard kept == nil else { return }
        kept = AirshipKept.loaded()
    }
    func release() {
        guard kept != nil else { return }
        kept = nil
        TramArt.shared.forget()
    }
}

// MARK: - 云上的飞艇: drawing it

struct AirshipPainter {
    /// Seconds the scenery has been moving.
    var t: Double
    /// 0 the night's light, a half dusk, 1 the day's.
    var light: Double
    /// The hour of the clock with its minutes, for the gondola clock's hands (none: no hands).
    var hour: Double? = nil

    private typealias V = AirshipView
    private static let W = AirshipView.width, H = AirshipView.height

    func draw(in context: GraphicsContext, size: CGSize, kept: AirshipKept? = nil, drift: CGSize = .zero) {
        let unit = max(size.width / Self.W, size.height / Self.H) * (drift == .zero ? 1 : 1.02)
        var g = context
        g.translateBy(x: (size.width - Self.W * unit) / 2 + drift.width, y: (size.height - Self.H * unit) / 2 + drift.height)
        g.scaleBy(x: unit, y: unit)
        let pen = FramePen(g: g)
        let whole = CGRect(x: 0, y: 0, width: Self.W, height: Self.H)
        let (a, b, d) = TramStopPainter.blend(light)
        let dark = TramStopPainter.night(light)
        let dusk = frameClamp(1 - abs(light - 0.5) * 3, 0, 1)
        guard let art = kept ?? AirshipKept.loaded() else {
            pen.fade(Path(whole), FrameRGB(31, 39, 71).mixed(FrameRGB(111, 159, 208), light).color(), FrameRGB(70, 85, 126).mixed(FrameRGB(228, 232, 238), light).color(), y0: 0, y1: Self.H)
            return
        }
        func both(_ images: [CGImage], _ draw: (GraphicsContext, CGImage) -> Void) {
            draw(g, images[a])
            if d > 0.002 { var over = g; over.opacity = d; draw(over, images[b]) }
        }
        both(art.backs) { c, image in c.draw(Image(decorative: image, scale: 1), in: whole) }
        stars(pen, dark)
        sunLight(pen, dusk)
        waterfall(pen, dark)
        // The far band of cloud that slides, then the ship's shadow on it.
        both(art.mids) { c, image in strip(c, image, top: V.midTop, height: 170, offset: t * V.midSpeed) }
        let rise = 4 * sin(t * 0.45) + 3 * (V.bob.fbm(t * 0.06, 2) - 0.5)
        shadow(pen, rise, light: light, dark: dark, dusk: dusk)
        birds(pen, light, dark)
        ship(g, pen, art, rise: rise, a: a, b: b, d: d, dark: dark)
        both(art.nears) { c, image in strip(c, image, top: V.nearTop, height: 310, offset: t * V.nearSpeed) }
        // The frame's own dusk at its corners.
        g.fill(Path(whole), with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.22)]), center: CGPoint(x: 500, y: 300), startRadius: 280, endRadius: 680))
    }

    /// A band of cloud across the frame, slid `offset` units to the right (it tiles every 2000).
    private func strip(_ g: GraphicsContext, _ image: CGImage, top: Double, height: Double, offset: Double) {
        let w = V.stripWidth
        let shift = offset.truncatingRemainder(dividingBy: w)
        var x = shift - w
        while x < Self.W {
            g.draw(Image(decorative: image, scale: 1), in: CGRect(x: x, y: top, width: w, height: height))
            x += w
        }
    }

    private func stars(_ pen: FramePen, _ dark: Double) {
        guard dark > 0.1 else { return }
        for (i, s) in V.stars.enumerated() {
            let k = TramRain.flicker.at(t * 0.9 + Double(i) * 13)
            guard k > 0.55 else { continue }
            pen.disc(s.x, s.y, 0.9, FrameRGB(250, 244, 220), (k - 0.55) * 1.6 * dark)
        }
    }

    /// At dusk the sun's light fans up the sky from behind the island, breathing a little.
    private func sunLight(_ pen: FramePen, _ dusk: Double) {
        guard dusk > 0.05 else { return }
        var layer = pen.g
        layer.blendMode = .plusLighter
        for k in 0..<5 {
            let angle = -Double.pi / 2 - 0.55 + Double(k) * 0.2 + 0.03 * sin(t * 0.1 + Double(k))
            // (The beams come out from behind the island: they begin past its tree and roof.)
            let reach = 520.0, spread = 0.035, from = 82.0
            let p0 = CGPoint(x: V.sun.x + cos(angle - spread * 0.4) * from, y: V.sun.y + sin(angle - spread * 0.4) * from)
            let p3 = CGPoint(x: V.sun.x + cos(angle + spread * 0.4) * from, y: V.sun.y + sin(angle + spread * 0.4) * from)
            let p1 = CGPoint(x: V.sun.x + cos(angle - spread) * reach, y: V.sun.y + sin(angle - spread) * reach)
            let p2 = CGPoint(x: V.sun.x + cos(angle + spread) * reach, y: V.sun.y + sin(angle + spread) * reach)
            var beam = Path()
            beam.move(to: p0); beam.addLine(to: p1); beam.addLine(to: p2); beam.addLine(to: p3); beam.closeSubpath()
            let breathe = 0.6 + 0.4 * TramRain.flicker.at(t * 0.05 + Double(k) * 9)
            layer.fill(beam, with: .linearGradient(Gradient(colors: [FrameRGB(255, 220, 170).color(0.16 * dusk * breathe), FrameRGB(255, 220, 170).color(0)]),
                                                   startPoint: V.sun, endPoint: CGPoint(x: V.sun.x + cos(angle) * reach, y: V.sun.y + sin(angle) * reach)))
        }
    }

    /// The island's water falling into the cloud: streaks going down, mist where it meets the cloud.
    private func waterfall(_ pen: FramePen, _ dark: Double) {
        let top = V.fallTop, foot = V.fallFoot
        let c = FrameRGB(224, 236, 246).mixed(FrameRGB(150, 166, 204), dark)
        var r = FrameRandom(321)
        for _ in 0..<14 {
            let dx = (r.next() - 0.5) * 6, speed = 70 + r.next() * 40, len = 10 + r.next() * 12, ph = r.next()
            let u = (t * speed / (foot - top.y) + ph).truncatingRemainder(dividingBy: 1)
            let y = top.y + u * (foot - top.y)
            // It spreads a little as it falls.
            let x = top.x + dx * (1 + u * 1.5) + u * 2
            pen.line([(x, y), (x + 0.4, min(foot, y + len))], c, 0.55 * (1 - u * 0.5), width: 1.4)
        }
        pen.line([(top.x - 2, top.y), (top.x + 1, foot)], c, 0.3, width: 4)
        pen.soft(top.x + 3, foot, 16, 6, c, 0.45)
    }

    /// The ship's shadow on the cloud under it, away from the light (none at dusk: the low sun throws it far off).
    private func shadow(_ pen: FramePen, _ rise: Double, light: Double, dark: Double, dusk: Double) {
        let day = frameClamp((light - 0.5) * 2, 0, 1)
        let side = day > 0 ? -1.0 : 1.0
        let k = max(day * 0.16, dark * 0.08) * (1 - dusk)
        guard k > 0.005 else { return }
        let x = V.shipAt.x + side * 100, y = V.midTop + 96 + rise * 0.3
        pen.soft(x, y, 130, 10, FrameRGB(40, 50, 80), k, core: 0.4)
    }

    /// Now and then a few birds go over, wings beating (not at night).
    private func birds(_ pen: FramePen, _ light: Double, _ dark: Double) {
        guard dark < 0.6 else { return }
        let period = 150.0, cross = 60.0
        let since = (t + 40).truncatingRemainder(dividingBy: period)
        guard since < cross else { return }
        let u = since / cross
        let c = FrameRGB(60, 56, 70).mixed(FrameRGB(90, 84, 96), light)
        for k in 0..<5 {
            let x = 1060 - u * 1180 + Double(k) * 26 + (k % 2 == 0 ? 0 : 8)
            let y = 120 + Double(k) * 7 - (k % 2 == 0 ? 0 : 6) + 3 * sin(t * 0.8 + Double(k))
            let beat = sin(t * 9 + Double(k) * 1.3) * 3.5
            pen.line([(x - 6, y - beat), (x, y), (x + 6, y - beat)], c, 0.8 * (1 - dark), width: 1.2)
        }
    }

    private func ship(_ g: GraphicsContext, _ pen: FramePen, _ art: AirshipKept, rise: Double, a: Int, b: Int, d: Double, dark: Double) {
        let at = CGPoint(x: V.shipAt.x, y: V.shipAt.y + rise)
        let tilt = 0.012 * sin(t * 0.45 + 0.9)
        var s = g
        s.translateBy(x: at.x, y: at.y)
        s.rotate(by: .radians(tilt))
        let rect = CGRect(x: -V.shipAnchor.x, y: -V.shipAnchor.y, width: V.shipSize.width, height: V.shipSize.height)
        s.draw(Image(decorative: art.ships[a], scale: 1), in: rect)
        if d > 0.002 { var over = s; over.opacity = d; over.draw(Image(decorative: art.ships[b], scale: 1), in: rect) }
        let p = FramePen(g: s)
        // The gondola clock's hands, riding with the ship.
        if let hour { p.clockHands(V.clock.x, V.clock.y, V.clockR, hour: hour, FrameRGB(58, 48, 52), width: 1.1) }
        // The propeller: two blades going round about the shaft, seen from the side (a faint disc where they sweep).
        let hub = V.hub, turn = t * 28
        let wood = FrameRGB(120, 86, 58).mixed(FrameRGB(70, 52, 44), dark)
        p.oval(hub.x + 1, hub.y, 2, V.bladeLength + 2, FrameRGB(210, 210, 210), 0.12)
        for half in [0.0, Double.pi] {
            let reach = cos(turn + half) * V.bladeLength
            p.line([(hub.x + 1, hub.y), (hub.x + 2, hub.y + reach)], wood, 0.9, width: 3.4)
        }
        // The pennants on their line, streaming back toward the stern, flapping.
        let colours = [FrameRGB(216, 88, 74), FrameRGB(232, 194, 90), FrameRGB(90, 142, 200), FrameRGB(106, 168, 106), FrameRGB(239, 232, 218)]
        let shade = 1 - 0.45 * dark
        for k in 0..<9 {
            let u = (Double(k) + 0.5) / 9
            let x = (1 - u) * (1 - u) * V.lineFrom.x + 2 * u * (1 - u) * V.lineBend.x + u * u * V.lineTo.x
            let y = (1 - u) * (1 - u) * V.lineFrom.y + 2 * u * (1 - u) * V.lineBend.y + u * u * V.lineTo.y
            let flap = sin(t * 6 + Double(k) * 0.9) * 2.5, reach = 13 + sin(t * 4.3 + Double(k)) * 1.2
            let c = colours[k % 5]
            p.shape([(x, y - 4), (x, y + 4), (x + reach, y + 1 + flap)], FrameRGB(c.r * shade, c.g * shade, c.b * shade), 0.95)
        }
    }
}
