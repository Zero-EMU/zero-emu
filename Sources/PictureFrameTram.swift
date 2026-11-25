import SwiftUI
import ImageIO

// 画框's third scenery, 下雨的电车站, drawn by hand in coloured pencil. The
// eye stands on the path across the line from a country tram stop, 1.4 m
// up, and looks straight over the track at its wooden shelter: a bench, a
// timetable board with no words on it, one lamp under the eave, a round
// sign beside it; behind, the paddies, a farmhouse with a window lit, the
// hills. One eye, one horizon, one vanishing point: everything stands
// where its metres put it, the pictures were drawn with the same numbers,
// and what is drawn here over them meets them.
//
// What does not move is three pictures, one for each light (night, dusk,
// day), passed from one to the next as the light goes. What moves is drawn
// each frame: the rain, the rings in the puddles, the drips off the eave,
// the lamp, the far windows, the lightning, and every four minutes a tram
// that comes in from the right, stands at the shelter and goes on to the
// left: its near side is a picture too, its windows open onto the car's
// ceiling and the far side's windows (the stop seen through them), the end
// facing the eye is drawn from its metres, and its colours lie in the
// puddles where a mirror on the ground puts them.

// MARK: - 下雨的电车站: where things are

/// Where things stand (metres: x to the right, y up, z away from the eye)
/// and how they are seen.
enum TramStop {
    static let width = 1000.0, height = 600.0
    static let focal = 900.0, centreX = 500.0, horizon = 260.0, eye = 1.4
    /// A point onto the sheet (1000 × 600).
    static func pt(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        CGPoint(x: centreX + x * focal / z, y: horizon - (y - eye) * focal / z)
    }
    /// The near rail's top (the wheels stand on it).
    static let railTop = 0.37
    /// The tram: its near and far sides, its length; the heights of its skirt, belt, windows, the edge of its roof.
    static let near = 7.77, far = 10.17, length = 11.0
    static let skirt = 0.55, belt = 1.45, sill = 1.55, head = 2.45, eave = 3.1
    /// Its window and door slots, from its left end; a slot's width; which slots are doors (their windows are smaller).
    static func slot(_ i: Int) -> Double { 0.8 + Double(i) * 1.2 }
    static let slotWidth = 0.95, windows = [0, 2, 3, 4, 5, 7], doors = [1, 6]
    /// What the picture of its near side covers (metres from its left end; heights).
    static let spriteLeft = -0.15, spriteWidth = 11.3, spriteTop = 3.45, spriteBottom = 0.3
    /// The shelter's lamp; the front edge of its roof and its ends; the platform's top.
    static let lampX = -0.8, lampY = 2.88, lampZ = 12.25
    static let eaveZ = 11.72, eaveY = 3.3, shelterX0 = -3.75, shelterX1 = 2.15, platform = 0.55
    /// The station clock hung from the beam right of the lamp: its middle and
    /// its face's radius (the picture has its face; its hands keep the phone's time).
    static let clockX = 1.15, clockY = 2.6, clockZ = 11.88, clockR = 0.2
    /// The puddles on the path: middle (x, z), half their size across and along.
    static let puddles: [(x: Double, z: Double, rx: Double, rz: Double)] = [(-0.35, 4.0, 0.85, 0.26), (1.55, 3.92, 0.5, 0.2), (-2.25, 5.35, 0.8, 0.2), (2.35, 5.9, 0.65, 0.17)]
    /// The lit windows at the hills' foot that show past the shelter and the farm (sheet points, a size).
    static let farLights: [(x: Double, y: Double, s: Double)] = [(196.6, 255.1, 0.85), (668.8, 256.0, 1.05), (735.0, 256.5, 1.68), (759.9, 256.0, 1.07), (807.2, 257.0, 0.9), (858.1, 256.8, 1.36)]
    /// The pictures: the stop by night, at dusk, by day; the tram's near side by night and by day.
    static let pictures = ["frame-tram-night.jpg", "frame-tram-dusk.jpg", "frame-tram-day.jpg"]
    static let tramSides = ["frame-tram-side-night.png", "frame-tram-side-day.png"]

    /// A puddle on the sheet, a little inside its drawn edge.
    static func puddle(_ p: (x: Double, z: Double, rx: Double, rz: Double), inset: Double = 0.9) -> CGRect {
        let c = pt(p.x, 0, p.z)
        let rx = p.rx * inset * focal / p.z
        let far = pt(p.x, 0, p.z + p.rz * inset).y, near = pt(p.x, 0, p.z - p.rz * inset).y
        return CGRect(x: c.x - rx, y: far, width: rx * 2, height: near - far)
    }
}

/// The rain's streaks in three layers (where across, where in its fall),
/// as many as the heaviest rain has; the same every time.
enum TramRain {
    struct Drop { var a: Double, b: Double }
    static let layers: [[Drop]] = [360, 240, 90].enumerated().map { layer, count in
        var r = FrameRandom(4242 + UInt32(layer))
        return (0..<count).map { _ in Drop(a: r.next(), b: r.next()) }
    }
    static let lit: [Drop] = {
        var r = FrameRandom(77)
        return (0..<110).map { _ in Drop(a: r.next(), b: r.next()) }
    }()
    static let heavy = FrameNoise(41), wind = FrameNoise(83), flicker = FrameNoise(7)
}

/// The tram's coming and going, every `period` seconds of the scenery's
/// clock from `first` (its sound is a FrameCue on the same clock): in from
/// the right for nine seconds, slowing; twelve seconds at the shelter; then
/// away to the left, faster and faster, until it is past the frame.
enum TramRun {
    static let period = FrameCue.tramPeriod, first = FrameCue.tramAt
    /// Where its left end stands when it comes into the picture and at the shelter (metres).
    static let from = 7.5, stop = -6.4
    struct State { var left: Double, speed: Double }
    static func at(_ t: Double) -> State? {
        guard t >= first else { return nil }
        let since = (t - first).truncatingRemainder(dividingBy: period)
        if since < 9 {
            let u = since / 9
            return State(left: from + (stop - from) * (1 - (1 - u) * (1 - u)), speed: (from - stop) * 2 * (1 - u) / 9)
        }
        if since < 21 { return State(left: stop, speed: 0) }
        let s = since - 21, a = 0.9, top = 12.0, tv = top / a
        let gone = s < tv ? 0.5 * a * s * s : 0.5 * a * tv * tv + top * (s - tv)
        let left = stop - gone
        // (Its back past the frame's edge, even seen at its far side: gone.)
        if left + TramStop.length < -7 { return nil }
        return State(left: left, speed: min(top, a * s))
    }
}

// MARK: - The pictures

/// The stop's pictures, read once and kept (the Mac renderer finds them in
/// the folder FOLDARC_RESOURCES names).
final class TramArt: @unchecked Sendable {
    static let shared = TramArt()
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]
    func image(_ file: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = images[file] { return hit }
        guard let found = Self.read(file) else { return nil }
        images[file] = found
        return found
    }
    func forget() { lock.lock(); images.removeAll(); lock.unlock() }
    private static func read(_ file: String) -> CGImage? {
        var url: URL?
        if let folder = ProcessInfo.processInfo.environment["FOLDARC_RESOURCES"] {
            let candidate = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: candidate.path) { url = candidate }
        }
        if url == nil { url = Bundle.main.url(forResource: file, withExtension: nil) }
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Decoded now, not at the first frame that shows it.
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// The stop's pictures, held while the scenery shows.
struct TramKept {
    /// Night, dusk, day.
    var backs: [CGImage]
    /// The tram's near side: by night, by day.
    var sides: [CGImage]
    /// (One set serves every light.)
    static func step(_ light: Double) -> Int { 0 }
    /// What is to hand without a store: the pictures read (or none).
    static func loaded(tram: Bool) -> TramKept? {
        let backs = TramStop.pictures.compactMap { TramArt.shared.image($0) }
        guard backs.count == TramStop.pictures.count else { return nil }
        let sides = tram ? TramStop.tramSides.compactMap { TramArt.shared.image($0) } : []
        return TramKept(backs: backs, sides: sides)
    }
}

/// Reads the stop's pictures when the scenery is shown, lets them go when
/// another is.
@MainActor final class TramKeptStore: ObservableObject {
    @Published private(set) var kept: TramKept?
    func prepare(light: Double, pixelWidth: Int) {
        guard kept == nil else { return }
        if let all = TramKept.loaded(tram: true), all.sides.count == TramStop.tramSides.count { kept = all }
    }
    func release() {
        guard kept != nil else { return }
        kept = nil
        TramArt.shared.forget()
    }
}

// MARK: - 下雨的电车站: drawing it

/// The stop at one moment.
struct TramStopPainter {
    /// Seconds the scenery has been moving.
    var t: Double
    /// 0 the night's light, a half dusk, 1 the day's.
    var light: Double
    /// The hour of the clock with its minutes, for the station clock's hands (none: no hands).
    var hour: Double? = nil

    private typealias S = TramStop
    private static let W = TramStop.width, H = TramStop.height

    /// The two pictures to show for a light and how much of the second.
    static func blend(_ light: Double) -> (Int, Int, Double) {
        let l = frameClamp(light, 0, 1)
        return l < 0.5 ? (0, 1, l * 2) : (1, 2, (l - 0.5) * 2)
    }
    /// 1 at night … 0 by day: how much the lamps count.
    static func night(_ light: Double) -> Double { frameClamp(1 - light * 1.4, 0, 1) }

    /// The whole picture into `context`, covering `size`; `drift`: the
    /// picture's place moved by so many points (it is drawn a little larger
    /// than the screen so that its edge never shows).
    func draw(in context: GraphicsContext, size: CGSize, kept: TramKept? = nil, drift: CGSize = .zero) {
        let unit = max(size.width / Self.W, size.height / Self.H) * (drift == .zero ? 1 : 1.02)
        var g = context
        g.translateBy(x: (size.width - Self.W * unit) / 2 + drift.width, y: (size.height - Self.H * unit) / 2 + drift.height)
        g.scaleBy(x: unit, y: unit)
        let pen = FramePen(g: g)
        let whole = CGRect(x: 0, y: 0, width: Self.W, height: Self.H)
        let tram = TramRun.at(t)
        let art = kept ?? TramKept.loaded(tram: tram != nil)
        let dark = Self.night(light)
        let (a, b, d) = Self.blend(light)
        if let art {
            g.draw(Image(decorative: art.backs[a], scale: 1), in: whole)
            if d > 0.002 {
                var over = g
                over.opacity = d
                over.draw(Image(decorative: art.backs[b], scale: 1), in: whole)
            }
        } else {
            pen.fade(Path(whole), FrameRGB(54, 64, 95).mixed(FrameRGB(154, 165, 181), light).color(), FrameRGB(86, 88, 97).mixed(FrameRGB(143, 141, 136), light).color(), y0: 0, y1: Self.H)
        }
        let rain = 0.55 + 0.45 * TramRain.heavy.fbm(t / 300, 2)
        let wind = (TramRain.wind.fbm(t * 0.15, 2) - 0.5) * 2
        let lamp = lampLight(dark)
        // The lightning lights the sky, and a little everything under it.
        let flash = Self.lightning(t) * (0.3 + 0.7 * dark)
        if flash > 0 {
            pen.box(0, 0, Self.W, S.horizon + 4, FrameRGB(200, 210, 240), 0.32 * flash)
            pen.box(0, 0, Self.W, Self.H, FrameRGB(200, 210, 240), 0.08 * flash)
        }
        farLights(pen, dark)
        lampGlow(pen, lamp)
        // The station clock's hands (a tram at the stop passes in front of them).
        if let hour {
            let c = S.pt(S.clockX, S.clockY, S.clockZ)
            pen.clockHands(c.x, c.y, S.clockR * S.focal / S.clockZ, hour: hour, FrameRGB(44, 42, 46), width: 1.2)
        }
        drips(pen, lamp)
        if let tram, let art, art.sides.count == S.tramSides.count {
            drawTram(g, pen, art, tram, dark: dark)
        }
        rings(pen, rain, dark)
        // (A tram standing before the lamp keeps its light off the rain in front of it.)
        let lampHidden = tram.map { $0.left < S.lampX && $0.left + S.length > S.lampX } ?? false
        splashes(pen, rain, lamp, tram)
        rainfall(pen, rain, wind, dark, lampHidden ? 0 : lamp)
        // A thin mist low over the fields, thicker as the rain is.
        let haze = FrameRGB(70, 80, 108).mixed(FrameRGB(196, 202, 208), light)
        pen.g.fill(Path(CGRect(x: 0, y: S.horizon - 60, width: Self.W, height: 110)),
                   with: .linearGradient(Gradient(stops: [.init(color: haze.color(0), location: 0), .init(color: haze.color(0.22 * rain), location: 0.6), .init(color: haze.color(0), location: 1)]),
                                         startPoint: CGPoint(x: 0, y: S.horizon - 60), endPoint: CGPoint(x: 0, y: S.horizon + 50)))
        // The frame's own dusk at its corners.
        g.fill(Path(whole), with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.28)]), center: CGPoint(x: 500, y: 300), startRadius: 260, endRadius: 660))
    }

    /// The lightning: a flash and a smaller one after it, once every
    /// sixty-one seconds of the scenery's clock (the thunder follows: FrameCue).
    static func lightning(_ t: Double) -> Double {
        let e = (t - FrameCue.flashAt).truncatingRemainder(dividingBy: FrameCue.flashPeriod)
        let ph = e < 0 ? e + FrameCue.flashPeriod : e
        if ph < 0.1 { return 1 - ph / 0.1 }
        if ph > 0.2 && ph < 0.32 { return (0.32 - ph) / 0.12 * 0.6 }
        return 0
    }
    /// The shelter's lamp now: on as it gets dark, a little unsteady.
    private func lampLight(_ dark: Double) -> Double {
        let on = frameClamp(dark * 1.6, 0, 1)
        guard on > 0 else { return 0 }
        return on * (0.93 + 0.07 * TramRain.flicker.at(t * 3.1))
    }

    // MARK: Lights

    private func farLights(_ pen: FramePen, _ dark: Double) {
        guard dark > 0.05 else { return }
        for (i, l) in S.farLights.enumerated() {
            let twinkle = 0.65 + 0.35 * TramRain.flicker.at(t * 0.7 + Double(i) * 37)
            pen.glow(l.x, l.y, 6 * l.s, FrameRGB(255, 206, 130), 0.35 * dark * twinkle)
        }
    }

    private func lampGlow(_ pen: FramePen, _ k: Double) {
        guard k > 0.01 else { return }
        let bulb = S.pt(S.lampX, S.lampY - 0.04, S.lampZ)
        pen.glow(bulb.x, bulb.y + 4, 46, FrameRGB(255, 214, 140), 0.28 * k)
        pen.glow(bulb.x, bulb.y + 2, 14, FrameRGB(255, 240, 200), 0.5 * k)
    }

    // MARK: The tram

    private func drawTram(_ g: GraphicsContext, _ pen: FramePen, _ art: TramKept, _ tram: TramRun.State, dark: Double) {
        let left = tram.left
        let m = S.focal / S.near
        let sprite = CGRect(x: S.centreX + (left + S.spriteLeft) * m, y: S.horizon - (S.spriteTop - S.eye) * m,
                            width: S.spriteWidth * m, height: (S.spriteTop - S.spriteBottom) * m)
        let day = frameClamp((light - 0.3) / 0.4, 0, 1)
        // Its lamp's light on the line ahead of it, and its windows' on the stones before it.
        if dark > 0.02 {
            if left > -9 {
                let ahead = S.pt(left - 2.6, 0.3, 9.0)
                pen.glow(ahead.x, ahead.y, 3.4 * S.focal / 9, FrameRGB(255, 226, 170), 0.32 * dark, squash: 0.09)
            }
            let x0 = S.pt(left, 0.15, S.near - 0.25).x, x1 = S.pt(left + S.length, 0.15, S.near - 0.25).x
            let y0 = S.pt(0, 0.15, S.near).y, y1 = S.pt(0, 0.15, 7.3).y
            var band = g
            band.blendMode = .plusLighter
            band.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)),
                      with: .linearGradient(Gradient(colors: [FrameRGB(255, 200, 130).color(0.12 * dark), FrameRGB(255, 200, 130).color(0)]),
                                            startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1)))
        }
        interior(g, left, dark)
        side(g, art, sprite, day: day, opacity: 1)
        ends(pen, left, dark)
        pantograph(pen, left, dark)
        // In the puddles: what a mirror on the ground shows of it (the picture turned over about the line it stands on).
        var water = g
        var pools = Path()
        for p in S.puddles { pools.addEllipse(in: S.puddle(p)) }
        water.clip(to: pools)
        let ground = S.pt(0, 0, S.near).y
        water.translateBy(x: 0, y: ground * 2)
        water.scaleBy(x: 1, y: -1)
        side(water, art, sprite, day: day, opacity: 0.42)
    }

    private func side(_ g: GraphicsContext, _ art: TramKept, _ rect: CGRect, day: Double, opacity: Double) {
        var layer = g
        layer.opacity = opacity
        layer.draw(Image(decorative: art.sides[0], scale: 1), in: rect)
        if day > 0.002 {
            var over = g
            over.opacity = opacity * day
            over.draw(Image(decorative: art.sides[1], scale: 1), in: rect)
        }
    }

    /// What its windows show: the car's ceiling, the far wall, and through
    /// the far side's windows (the same slots) the stop behind it.
    private func interior(_ g: GraphicsContext, _ left: Double, _ dark: Double) {
        let zN = S.near, zF = S.far - 0.07, ceilingY = 2.55
        let ceiling = FrameRGB(200, 194, 178).mixed(FrameRGB(250, 216, 152), dark)
        let wall = FrameRGB(146, 134, 116).mixed(FrameRGB(190, 146, 96), dark)
        func pane(_ i: Int, _ z: Double, _ x: Double) -> CGRect {
            let door = S.doors.contains(i)
            let x0 = x + S.slot(i) + (door ? 0.12 : 0), x1 = x + S.slot(i) + S.slotWidth - (door ? 0.12 : 0)
            let a = S.pt(x0, door ? S.head - 0.05 : S.head, z), b = S.pt(x1, door ? 1.65 : S.sill, z)
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        }
        let slots = S.windows + S.doors
        let farPanes = slots.map { pane($0, zF, left) }
        let ceilingFoot = S.pt(0, ceilingY, zF).y, lamps = S.pt(0, ceilingY, (zN + zF) / 2).y
        for i in slots {
            let glass = pane(i, zN, left)
            if glass.maxX < 0 || glass.minX > S.width { continue }
            var inside = g
            inside.clip(to: Path(roundedRect: glass, cornerRadius: 0.06 * S.focal / zN))
            var wallPath = Path(glass)
            for far in farPanes where far.intersects(glass) { wallPath.addRect(far) }
            inside.fill(wallPath, with: .color(wall.color(0.94)), style: FillStyle(eoFill: true))
            inside.fill(Path(CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: max(0, ceilingFoot - glass.minY))), with: .color(ceiling.color(0.96)))
            if dark > 0.05 {
                inside.fill(Path(CGRect(x: glass.minX, y: lamps - 1.6, width: glass.width, height: 3.2)), with: .color(FrameRGB(255, 246, 220).color(0.9 * dark)))
            }
            // Two panes of glass: at night the lit car's warmth on them, by day the grey sky.
            inside.fill(Path(glass), with: .color(FrameRGB(250, 214, 150).color(0.12 * dark)))
            inside.fill(Path(glass), with: .color(FrameRGB(200, 208, 218).color(0.24 * (1 - dark))))
        }
    }

    /// The end that faces the eye (only one does, and only once that end is
    /// off to one side): its front going left, its back going away.
    private func ends(_ pen: FramePen, _ left: Double, _ dark: Double) {
        let right = left + S.length
        let zN = S.near, zF = S.far, zM = (zN + zF) / 2
        let cream = FrameRGB(236, 224, 194).mixed(FrameRGB(132, 130, 144), dark)
        let green = FrameRGB(63, 109, 87).mixed(FrameRGB(40, 66, 66), dark)
        let red = FrameRGB(168, 68, 60).mixed(FrameRGB(110, 60, 68), dark)
        let ink = FrameRGB(58, 45, 48)
        var faces: [(x: Double, front: Bool)] = []
        if left > 0 { faces.append((left, true)) }
        if right < 0 { faces.append((right, false)) }
        for face in faces {
            let x = face.x
            func quad(_ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double) -> Path {
                FramePen.outline([S.pt(x, y0, z0), S.pt(x, y0, z1), S.pt(x, y1, z1), S.pt(x, y1, z0)].map { ($0.x, $0.y) })
            }
            pen.fill(quad(S.railTop, S.skirt, zN + 0.25, zF - 0.25), FrameRGB(40, 42, 48))
            pen.fill(quad(S.skirt, S.belt, zN, zF), green)
            pen.fill(quad(S.belt, S.eave, zN, zF), cream)
            pen.fill(quad(S.belt - 0.03, S.belt + 0.04, zN, zF), red)
            // The big window (the cab dark, a little warm at night) and a blank board over it.
            let glass = quad(1.62, 2.5, zN + 0.32, zF - 0.32)
            pen.fill(glass, FrameRGB(150, 160, 172).mixed(FrameRGB(70, 58, 52), dark))
            pen.stroke(glass, FrameRGB(185, 189, 193).mixed(FrameRGB(150, 140, 120), dark), width: 1.4)
            pen.fill(quad(2.62, 2.92, zM - 0.5, zM + 0.5), FrameRGB(52, 52, 58))
            if face.front {
                let c = S.pt(x, 1.05, zM)
                let rx = abs(S.pt(x, 1.05, zM - 0.14).x - S.pt(x, 1.05, zM + 0.14).x) / 2, ry = 0.14 * S.focal / zM
                pen.oval(c.x, c.y, max(1, rx), ry, FrameRGB(220, 214, 196).mixed(FrameRGB(255, 244, 210), dark))
                if dark > 0.02 { pen.glow(c.x, c.y, 34, FrameRGB(255, 238, 200), 0.55 * dark) }
            } else {
                for z in [zN + 0.42, zF - 0.42] {
                    let c = S.pt(x, 1.0, z), ry = 0.08 * S.focal / z
                    let rx = abs(S.pt(x, 1.0, z - 0.08).x - S.pt(x, 1.0, z + 0.08).x) / 2
                    pen.oval(c.x, c.y, max(0.8, rx), ry, FrameRGB(150, 40, 40).mixed(FrameRGB(255, 70, 60), dark))
                    if dark > 0.02 { pen.glow(c.x, c.y, 16, FrameRGB(255, 60, 50), 0.45 * dark) }
                }
            }
            pen.stroke(quad(S.skirt, S.eave, zN, zF), ink, 0.85, width: 1.3)
        }
    }

    /// Its pantograph rising off the roof to the wire above the frame.
    private func pantograph(_ pen: FramePen, _ left: Double, _ dark: Double) {
        let x = left + S.length / 2, z = (S.near + S.far) / 2
        let c = FrameRGB(70, 72, 78).mixed(FrameRGB(36, 38, 44), dark)
        for side in [-1.0, 1.0] {
            let foot = S.pt(x + side * 0.6, 3.38, z), knee = S.pt(x + side * 0.1, 4.7, z)
            pen.line([(foot.x, foot.y), (knee.x, knee.y)], c, 0.95, width: 1.4)
        }
        let base = S.pt(x - 0.7, 3.3, z), top = S.pt(x + 0.7, 3.42, z)
        pen.box(base.x, top.y, top.x - base.x, base.y - top.y, c)
    }

    // MARK: Water

    private func rings(_ pen: FramePen, _ rain: Double, _ dark: Double) {
        var r = FrameRandom(909)
        let c = FrameRGB(214, 222, 236).mixed(FrameRGB(196, 204, 220), dark)
        for p in S.puddles {
            let box = S.puddle(p, inset: 0.86)
            var inside = pen.g
            inside.clip(to: Path(ellipseIn: box))
            let wet = FramePen(g: inside)
            for _ in 0..<9 {
                let ph = r.next(), ax = (r.next() - 0.5) * 1.4, az = (r.next() - 0.5) * 1.2, rate = 0.7 + r.next() * 0.7
                let u = (t * rate + ph * 7).truncatingRemainder(dividingBy: 1.1) / 1.1
                if r.next() > rain + 0.15 { continue }
                let x = p.x + ax * p.rx, z = p.z + az * p.rz
                let centre = S.pt(x, 0, z), radius = 0.03 + u * 0.15
                // A circle on the ground: as wide as it is, as deep as the low eye sees it.
                let rx = radius * S.focal / z, ry = radius * S.focal * S.eye / (z * z)
                wet.ovalLine(centre.x, centre.y, rx, ry, c, (1 - u) * (0.3 + 0.25 * dark), width: 0.8)
            }
        }
    }

    private func drips(_ pen: FramePen, _ k: Double) {
        var r = FrameRandom(55)
        let floor = S.pt(0, S.platform, S.eaveZ).y
        for _ in 0..<10 {
            let x = frameLerp(S.shelterX0 + 0.1, S.shelterX1 - 0.1, r.next())
            let period = 1 + r.next() * 1.4
            let age = (t + r.next() * period).truncatingRemainder(dividingBy: period)
            let y = S.eaveY - 0.04 - 4.9 * age * age
            let lit = k * frameClamp(1 - abs(x - S.lampX) / 3, 0, 1)
            let c = FrameRGB(214, 224, 238).mixed(FrameRGB(255, 222, 170), lit)
            let p = S.pt(x, max(S.platform, y), S.eaveZ)
            if y > S.platform {
                pen.oval(p.x, p.y, 1.1, 2.4, c, 0.75)
            } else {
                let s = (S.platform - y) / 1.2
                if s < 1 {
                    for side in [-1.0, 1.0] {
                        pen.line([(p.x + side * 1.5, floor), (p.x + side * (3 + 4 * s), floor - 4 * sin(s * 3.14))], c, 0.55 * (1 - s), width: 0.8)
                    }
                }
            }
        }
    }

    private func splashes(_ pen: FramePen, _ rain: Double, _ k: Double, _ tram: TramRun.State?) {
        var r = FrameRandom(31)
        let count = Int((80 * rain).rounded(.up))
        for _ in 0..<count {
            // On the path, on the stones by the line, on the platform.
            let place = r.next()
            let x = -6 + r.next() * 12
            let y: Double, z: Double
            if place < 0.6 { y = 0; z = 3.7 + r.next() * 2.9 } else if place < 0.85 { y = 0.15; z = 7.3 + r.next() * 3.2 } else { y = S.platform; z = 11.05 + r.next() * 3.4 }
            let rate = 1.5 + r.next() * 2, ph = r.next() * 9
            let u = (t * rate + ph).truncatingRemainder(dividingBy: 1)
            if u > 0.25 { continue }
            // (Not behind a tram standing in front of them.)
            if let tram, z > S.near, x > tram.left, x < tram.left + S.length { continue }
            let p = S.pt(x, y, z), s = 2.2 * 5 / z
            let lit = k * frameClamp(1 - hypot(x - S.lampX, z - S.lampZ) / 5, 0, 1)
            let c = FrameRGB(212, 222, 234).mixed(FrameRGB(255, 216, 164), lit)
            for side in [-1.0, 1.0] {
                pen.line([(p.x + side * s, p.y), (p.x + side * (2 + 9 * u) * s, p.y - 7 * s * sin(u / 0.25 * 3.14))], c, 0.5 * (1 - u / 0.25), width: 0.9)
            }
        }
    }

    // MARK: Rain

    private func rainfall(_ pen: FramePen, _ rain: Double, _ wind: Double, _ dark: Double, _ k: Double) {
        let slant = 0.12 + 0.08 * wind
        let lengths = [11.0, 22, 40], speeds = [700.0, 1150, 1700], widths = [0.6, 0.9, 1.25]
        let alphas = [0.14, 0.2, 0.26].map { $0 * (0.85 + 0.25 * (1 - dark)) }
        let colour = FrameRGB(196, 206, 226).mixed(FrameRGB(244, 246, 250), 1 - dark)
        for layer in 0..<3 {
            let drops = TramRain.layers[layer]
            let count = min(drops.count, Int((Double(drops.count) * rain).rounded()))
            var streaks = Path()
            for drop in drops.prefix(count) {
                let x0 = drop.a * (Self.W + 240) - 120
                let y = (drop.b * (Self.H + 100) + t * speeds[layer]).truncatingRemainder(dividingBy: Self.H + 100) - 50
                let x = x0 + y * slant
                streaks.move(to: CGPoint(x: x, y: y))
                streaks.addLine(to: CGPoint(x: x - lengths[layer] * slant, y: y - lengths[layer]))
            }
            pen.stroke(streaks, colour, alphas[layer], width: widths[layer])
        }
        // Near the lamp, the rain lit.
        guard k > 0.02 else { return }
        let b = S.pt(S.lampX, S.lampY, S.lampZ)
        var near = pen.g
        near.clip(to: Path(ellipseIn: CGRect(x: b.x - 110, y: b.y - 40, width: 220, height: 220)))
        var streaks = Path()
        for drop in TramRain.lit.prefix(Int((110 * rain).rounded(.up))) {
            let x0 = b.x - 120 + drop.a * 240
            let y = (drop.b * 300 + t * 1300).truncatingRemainder(dividingBy: 300) + b.y - 60
            let x = x0 + (y - b.y) * slant
            streaks.move(to: CGPoint(x: x, y: y))
            streaks.addLine(to: CGPoint(x: x - 18 * slant, y: y - 18))
        }
        FramePen(g: near).stroke(streaks, FrameRGB(255, 222, 168), 0.4 * k, width: 0.9)
    }
}
