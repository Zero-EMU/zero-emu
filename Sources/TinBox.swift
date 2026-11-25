import SwiftUI
import Combine
#if os(iOS)
import AVFoundation
#endif

// 铁皮盒's things (TinThing), drawn small (TinArt: 游戏笔记 draws the red
// flower with it), and the music box's tune. Where they are kept and shown
// is 铅笔盒 now (PencilBox.swift): a red flower stamp for 便签, a lollipop
// and three more stickers for 相册's editing, a music box that plays the
// gold cartridge's little tune, squared exercise paper for 便签, and at
// twelve games a bicycle, a school bag and a leaf.

// MARK: - The music box

/// The music box's tune, played once from its file (on its own queue:
/// reading the file and setting the session can block).
final class TinMusicBoxSound: @unchecked Sendable {
    static let shared = TinMusicBoxSound()
    private let queue = DispatchQueue(label: "FoldArc.tin.musicbox", qos: .userInitiated)
    #if os(iOS)
    private var player: AVAudioPlayer?
    #endif
    /// The tune once, at `gain`; `done` on the main queue when it has run out.
    func play(gain: Float, done: @escaping @Sendable () -> Void) {
        #if os(iOS)
        queue.async {
            self.player?.stop()
            guard let url = Bundle.main.url(forResource: "tin-music-box", withExtension: "m4a"),
                  let made = try? AVAudioPlayer(contentsOf: url) else {
                NSLog("[tin] the music box's tune is not in the app")
                DispatchQueue.main.async(execute: done)
                return
            }
            AudioPolicy.shared.configure("tin box")
            try? AVAudioSession.sharedInstance().setActive(true)
            made.volume = gain
            made.prepareToPlay()
            made.play()
            self.player = made
            NSLog("[tin] the music box plays (%.1f s)", made.duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + made.duration + 0.2, execute: done)
        }
        #else
        DispatchQueue.main.async(execute: done)
        #endif
    }
    func stop() {
        #if os(iOS)
        queue.async {
            self.player?.stop()
            self.player = nil
        }
        #endif
    }
}

/// Whether the music box is playing (the row's 转一转 / 停).
@MainActor final class TinMusicBox: ObservableObject {
    static let shared = TinMusicBox()
    @Published private(set) var playing = false
    private var turn = 0
    func toggle() { if playing { stop() } else { play() } }
    func play() {
        turn += 1
        let mine = turn
        playing = true
        TinMusicBoxSound.shared.play(gain: SilentRun.on ? 0 : ConsoleVolume.shared.gain) {
            Task { @MainActor in TinMusicBox.shared.ended(mine) }
        }
    }
    func stop() {
        turn += 1
        playing = false
        TinMusicBoxSound.shared.stop()
    }
    private func ended(_ which: Int) {
        guard which == turn else { return }
        playing = false
    }
}

// MARK: - Drawing the things

/// The things drawn, each in a square 0 … 1 across (y down); a thing still
/// to come is its shape only, faint.
struct TinArt {
    var locked = false
    private var alpha: Double { locked ? 0.42 : 1 }
    private func c(_ colour: FrameRGB) -> FrameRGB { locked ? FrameRGB(132, 122, 112) : colour }

    /// `thing` into `rect` of `context`.
    func draw(_ thing: TinThing, in context: GraphicsContext, rect: CGRect) {
        var g = context
        g.translateBy(x: rect.minX, y: rect.minY)
        g.scaleBy(x: rect.width, y: rect.height)
        let pen = FramePen(g: g)
        switch thing {
        case .redFlower: flower(pen)
        case .lollipop: lollipop(pen)
        case .musicBox: musicBox(pen)
        case .gridPaper: gridPaper(pen)
        case .schoolDays: schoolDays(pen)
        case .playthings: gridPaper(pen)
        }
    }

    /// An oval round (x, y), turned `degrees`.
    static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ degrees: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(CGAffineTransform(translationX: x, y: y)))
    }

    /// The red paper flower a teacher gives: two rings of petals, a yellow
    /// heart, a stem with two leaves.
    private func flower(_ pen: FramePen) {
        let red = c(FrameRGB(222, 40, 46)), deep = c(FrameRGB(172, 22, 34)), leaf = c(FrameRGB(70, 150, 70)), heart = c(FrameRGB(255, 206, 60))
        var stem = Path()
        stem.move(to: CGPoint(x: 0.5, y: 0.55))
        stem.addQuadCurve(to: CGPoint(x: 0.47, y: 0.96), control: CGPoint(x: 0.54, y: 0.78))
        pen.stroke(stem, leaf, alpha, width: 0.045)
        pen.fill(Self.ellipse(0.36, 0.8, 0.12, 0.05, -30), leaf, alpha)
        pen.fill(Self.ellipse(0.63, 0.74, 0.12, 0.05, 25), leaf, alpha)
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * Double.pi
            pen.fill(Self.ellipse(0.5 + cos(a) * 0.17, 0.36 + sin(a) * 0.17, 0.13, 0.09, a * 180 / Double.pi), red, alpha)
        }
        for k in 0..<6 {
            let a = (Double(k) + 0.5) / 6 * 2 * Double.pi
            pen.fill(Self.ellipse(0.5 + cos(a) * 0.09, 0.36 + sin(a) * 0.09, 0.08, 0.055, a * 180 / Double.pi), deep, alpha)
        }
        pen.disc(0.5, 0.36, 0.06, heart, alpha)
    }

    /// A round lollipop: a pink swirl on a stick.
    private func lollipop(_ pen: FramePen) {
        let pink = c(FrameRGB(240, 96, 150)), cream = c(FrameRGB(255, 246, 236)), stick = c(FrameRGB(240, 232, 214))
        pen.box(0.475, 0.6, 0.05, 0.38, stick, alpha)
        pen.disc(0.5, 0.38, 0.3, pink, alpha)
        var swirl = Path()
        for i in 0...64 {
            let u = Double(i) / 64
            let a = u * 4.2 * Double.pi, r = 0.03 + u * 0.24
            let point = CGPoint(x: 0.5 + cos(a) * r, y: 0.38 + sin(a) * r)
            if i == 0 { swirl.move(to: point) } else { swirl.addLine(to: point) }
        }
        pen.stroke(swirl, cream, alpha, width: 0.05)
        if !locked { pen.oval(0.38, 0.24, 0.07, 0.035, FrameRGB(255, 255, 255), 0.5) }
    }

    /// A small wooden music box with a brass crank at its side.
    private func musicBox(_ pen: FramePen) {
        let wood = c(FrameRGB(150, 92, 52)), dark = c(FrameRGB(100, 58, 32)), brass = c(FrameRGB(222, 178, 84)), lid = c(FrameRGB(186, 124, 74))
        pen.fill(Path(roundedRect: CGRect(x: 0.1, y: 0.42, width: 0.68, height: 0.42), cornerRadius: 0.04), wood, alpha)
        pen.fill(Path(roundedRect: CGRect(x: 0.08, y: 0.33, width: 0.72, height: 0.13), cornerRadius: 0.03), lid, alpha)
        pen.box(0.1, 0.6, 0.68, 0.025, dark, alpha)
        pen.disc(0.44, 0.71, 0.03, brass, alpha)
        pen.line([(0.78, 0.62), (0.9, 0.62), (0.9, 0.48)], brass, alpha, width: 0.035)
        pen.disc(0.9, 0.45, 0.04, dark, alpha)
        if !locked {
            // A note rising from it.
            pen.oval(0.3, 0.22, 0.05, 0.035, FrameRGB(110, 80, 60), 0.85)
            pen.line([(0.345, 0.22), (0.345, 0.06), (0.42, 0.1)], FrameRGB(110, 80, 60), 0.85, width: 0.025)
        }
    }

    /// A sheet of squared exercise paper, a little askew, its margin red.
    private func gridPaper(_ pen: FramePen) {
        var g = pen.g
        g.translateBy(x: 0.5, y: 0.52)
        g.rotate(by: .degrees(-6))
        g.translateBy(x: -0.5, y: -0.52)
        let sheet = FramePen(g: g)
        let paper = c(FrameRGB(250, 248, 236)), grid = c(FrameRGB(96, 170, 120)), margin = c(FrameRGB(220, 80, 80)), edge = c(FrameRGB(196, 190, 172))
        let face = Path(CGRect(x: 0.18, y: 0.1, width: 0.64, height: 0.82))
        sheet.fill(face, paper, alpha)
        var lines = Path()
        var x = 0.26
        while x < 0.8 {
            lines.move(to: CGPoint(x: x, y: 0.16))
            lines.addLine(to: CGPoint(x: x, y: 0.88))
            x += 0.08
        }
        var y = 0.18
        while y < 0.9 {
            lines.move(to: CGPoint(x: 0.22, y: y))
            lines.addLine(to: CGPoint(x: 0.78, y: y))
            y += 0.08
        }
        sheet.stroke(lines, grid, 0.75 * alpha, width: 0.009)
        sheet.line([(0.23, 0.1), (0.23, 0.92)], margin, 0.8 * alpha, width: 0.01)
        sheet.stroke(face, edge, alpha, width: 0.012)
    }

    /// A bicycle, a school bag, a fallen ginkgo leaf.
    private func schoolDays(_ pen: FramePen) {
        let frame = c(FrameRGB(40, 110, 180)), tyre = c(FrameRGB(56, 56, 62))
        pen.ovalLine(0.17, 0.36, 0.11, 0.11, tyre, alpha, width: 0.025)
        pen.ovalLine(0.45, 0.36, 0.11, 0.11, tyre, alpha, width: 0.025)
        pen.line([(0.17, 0.36), (0.28, 0.22), (0.41, 0.22), (0.45, 0.36)], frame, alpha, width: 0.022)
        pen.line([(0.28, 0.22), (0.31, 0.36), (0.17, 0.36)], frame, alpha, width: 0.022)
        pen.line([(0.41, 0.22), (0.39, 0.14), (0.44, 0.13)], frame, alpha, width: 0.02)
        pen.line([(0.25, 0.18), (0.31, 0.18)], tyre, alpha, width: 0.03)
        let bag = c(FrameRGB(214, 70, 60)), flap = c(FrameRGB(172, 46, 44)), buckle = c(FrameRGB(240, 200, 90))
        var handle = Path()
        handle.move(to: CGPoint(x: 0.69, y: 0.2))
        handle.addQuadCurve(to: CGPoint(x: 0.81, y: 0.2), control: CGPoint(x: 0.75, y: 0.1))
        pen.stroke(handle, flap, alpha, width: 0.025)
        pen.fill(Path(roundedRect: CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.36), cornerRadius: 0.05), bag, alpha)
        pen.fill(Path(roundedRect: CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.16), cornerRadius: 0.05), flap, alpha)
        pen.box(0.735, 0.33, 0.03, 0.05, buckle, alpha)
        let gold = c(FrameRGB(236, 176, 50)), vein = c(FrameRGB(190, 128, 34))
        var fan = Path()
        fan.move(to: CGPoint(x: 0.5, y: 0.86))
        fan.addLine(to: CGPoint(x: 0.32, y: 0.67))
        fan.addQuadCurve(to: CGPoint(x: 0.68, y: 0.67), control: CGPoint(x: 0.5, y: 0.5))
        fan.closeSubpath()
        pen.fill(fan, gold, alpha)
        pen.line([(0.5, 0.6), (0.5, 0.86)], vein, 0.6 * alpha, width: 0.012)
        pen.line([(0.5, 0.86), (0.5, 0.97)], vein, alpha, width: 0.02)
    }
}
