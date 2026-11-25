import SwiftUI
#if os(iOS)
import UIKit
#endif

/// In-app launch splash. It is drawn right after the static system launch
/// screen (the same background, LaunchBackground) and stays up until the
/// first hardware hinge report has placed the console on the right display,
/// so a closed Duo never flashes the library on its cover.
///
/// 11-07: the
/// app's mark is the icon's ring (C2), black on the icon's white — in dark
/// mode white on black, as the dark icon. The system's launch screen is the
/// background alone; here the ring is drawn from the top, clockwise, then
/// "Zero EMU" rises under it and, should the start take longer, 正在准备掌机…
/// (SplashRing's timing). On the iPhone Core Animation draws it
/// (SplashRingUIView): the main thread is at its busiest just now (round 21:
/// a SwiftUI fade went in jerks at launch).
struct SplashView: View {
    #if os(iOS)
    @ObservedObject private var displayRole = DisplayRoleMonitor.shared
    #endif
    var showsWordmark: Bool = true
    /// The render tool's moment (seconds from the start) and appearance.
    var previewTime: Double? = nil
    var previewDark: Bool? = nil
    /// LaunchBackground (Assets): the icon's white; in dark mode near black.
    static let light = Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255)
    static let dark = Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255)
    /// The background now: the system's appearance, as the launch screen was
    /// just drawn in it.
    @MainActor static var background: Color { SplashLook.dark ? dark : light }
    /// Behind a play window (its rotations): the dark it was before 11-07.
    static let windowBackground = Color(red: 14 / 255, green: 17 / 255, blue: 25 / 255)

    var body: some View {
        let dark = previewDark ?? SplashLook.dark
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                dark ? Self.dark : Self.light
                // The ring sits exactly in the middle of the screen; the
                // name hangs below it without moving it.
                mark(dark: dark)
                    .rotationEffect(.degrees(angle(for: size)))
                    .opacity(markVisible ? 1 : 0)
                    .frame(width: size.width, height: size.height)
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("launch-splash")
    }

    @ViewBuilder private func mark(dark: Bool) -> some View {
        #if os(iOS)
        if let previewTime {
            SplashRingStill(time: previewTime, dark: dark, showsWordmark: showsWordmark)
        } else {
            SplashRingAnimation(dark: dark, showsWordmark: showsWordmark)
        }
        #else
        SplashRingStill(time: previewTime ?? 10, dark: dark, showsWordmark: showsWordmark)
        #endif
    }

    /// On the cover only the background stays. A launch with the lid closed
    /// starts in the orientation SpringBoard gives the cover (landscape) and
    /// turns to the cover's portrait once play holds the window; the system
    /// animates that turn (one tilted frame, then ~0.3 s of the old frame
    /// stretched over the new one: the mark squashed and the wordmark
    /// sideways, 10-28 closed cold launch), and no rotation effect can undo
    /// it. A plain colour looks the same stretched; the casing fades in next.
    /// Known from the first frame when the displays are known (otherwise
    /// once play takes the window), so the wordmark never shows there.
    private var markVisible: Bool {
        #if os(iOS)
        return displayRole.isOuter != true && !displayRole.launchedOnCover
        #else
        return true
        #endif
    }

    /// Same fixed-print rule as the cover casing: on the outer display the
    /// mark stays put in the screen's fixed coordinate space while UIKit
    /// rotates the window; on the inner display (or before the role is
    /// known) it follows the interface.
    private func angle(for size: CGSize) -> Double {
        #if os(iOS)
        guard displayRole.isOuter == true else { return 0 }
        let rotation = displayRole.coverRotation(for: size) ?? -90
        var angle = -90 - rotation
        while angle <= -180 { angle += 360 }
        while angle > 180 { angle -= 360 }
        return angle
        #else
        return 0
        #endif
    }
}

/// The system's appearance (the launch screen follows it; the app's own
/// views are always dark: LibraryView's preferredColorScheme, which a
/// window scene's traits do not take).
@MainActor enum SplashLook {
    static var dark: Bool {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return (scene?.traitCollection ?? UITraitCollection.current).userInterfaceStyle == .dark
        #else
        return false
        #endif
    }
}

/// The splash's ring: the icon's C2 (its diameter 62 % of the icon, the line
/// 5.5 %), and the timing — the ring drawn 0.10–0.75 s, the name rising
/// 0.55–0.95 s, 正在准备掌机… 1.10–1.50 s (LibraryView keeps the splash up
/// 1.15 s at least, so the name is always seen whole).
enum SplashRing {
    static let diameter = 128.0
    static let line = diameter * 0.055 / 0.62
    static let nameGap = 26.0
    static let name = "Zero EMU"
    static let nameSize = 24.0
    static let nameTracking = 0.5
    static let status = String(localized: "正在准备掌机…")
    static let drawDelay = 0.10, drawDuration = 0.65
    static let nameDelay = 0.55, nameDuration = 0.40
    static let statusDelay = 1.10, statusDuration = 0.40
    /// The ring's ink: the icon's black, or (dark) its white.
    static func ink(dark: Bool) -> Color { dark ? Color(red: 245 / 255, green: 245 / 255, blue: 243 / 255) : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255) }
    static func progress(_ time: Double, delay: Double, duration: Double) -> Double { min(1, max(0, (time - delay) / duration)) }
    /// Core Animation's easeInEaseOut and easeOut, for the stills.
    static func easeInOut(_ x: Double) -> Double { bezier(x, 0.42, 0, 0.58, 1) }
    static func easeOut(_ x: Double) -> Double { bezier(x, 0, 0, 0.58, 1) }
    /// The timing curve (0,0) (x1,y1) (x2,y2) (1,1) at `x`.
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func along(_ t: Double, _ a: Double, _ b: Double) -> Double { let u = 1 - t; return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t }
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<40 {
            if along(t, x1, x2) < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return along(t, y1, y2)
    }
}

/// The splash at a moment (the render tool's frames; the Mac preview).
struct SplashRingStill: View {
    var time: Double
    var dark: Bool
    var showsWordmark: Bool
    var body: some View {
        let ink = SplashRing.ink(dark: dark)
        let drawn = SplashRing.easeInOut(SplashRing.progress(time, delay: SplashRing.drawDelay, duration: SplashRing.drawDuration))
        let name = SplashRing.easeOut(SplashRing.progress(time, delay: SplashRing.nameDelay, duration: SplashRing.nameDuration))
        let status = SplashRing.easeOut(SplashRing.progress(time, delay: SplashRing.statusDelay, duration: SplashRing.statusDuration))
        let path = SplashRing.diameter - SplashRing.line
        Circle().trim(from: 0, to: drawn)
            .stroke(ink, style: StrokeStyle(lineWidth: SplashRing.line, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: path, height: path)
            .opacity(drawn > 0 ? 1 : 0)
            .frame(width: SplashRing.diameter, height: SplashRing.diameter)
            .overlay(alignment: .top) {
                if showsWordmark {
                    VStack(spacing: 10) {
                        Text(SplashRing.name).font(.system(size: SplashRing.nameSize, weight: .semibold)).tracking(SplashRing.nameTracking)
                            .foregroundStyle(ink).opacity(name).offset(y: 6 * (1 - name))
                        Text(SplashRing.status).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ink.opacity(0.45)).opacity(status).offset(y: 6 * (1 - status))
                    }
                    .fixedSize()
                    .offset(y: SplashRing.diameter + SplashRing.nameGap)
                }
            }
            .accessibilityHidden(true)
    }
}

#if os(iOS)
/// The splash drawn by Core Animation, from the moment it is in a window.
struct SplashRingAnimation: UIViewRepresentable {
    var dark: Bool
    var showsWordmark: Bool
    func makeUIView(context: Context) -> SplashRingUIView { SplashRingUIView(dark: dark, showsWordmark: showsWordmark) }
    func updateUIView(_ view: SplashRingUIView, context: Context) {}
}

final class SplashRingUIView: UIView {
    private let ring = CAShapeLayer()
    private let name = UILabel()
    private let status = UILabel()
    private var started = false

    init(dark: Bool, showsWordmark: Bool) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        let ink = UIColor(SplashRing.ink(dark: dark))
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = ink.cgColor
        ring.lineWidth = SplashRing.line
        ring.lineCap = .round
        // Nothing until it is in a window and its animations are on.
        ring.strokeEnd = 0
        layer.addSublayer(ring)
        name.attributedText = NSAttributedString(string: SplashRing.name, attributes: [
            .font: UIFont.systemFont(ofSize: SplashRing.nameSize, weight: .semibold), .foregroundColor: ink, .kern: SplashRing.nameTracking])
        status.attributedText = NSAttributedString(string: SplashRing.status, attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.45)])
        for label in [name, status] {
            label.alpha = 0
            label.isHidden = !showsWordmark
            addSubview(label)
        }
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = bounds
        ring.path = UIBezierPath(arcCenter: centre, radius: (SplashRing.diameter - SplashRing.line) / 2,
                                 startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        name.sizeToFit()
        status.sizeToFit()
        name.center = CGPoint(x: centre.x, y: centre.y + SplashRing.diameter / 2 + SplashRing.nameGap + name.bounds.height / 2)
        status.center = CGPoint(x: centre.x, y: name.frame.maxY + 10 + status.bounds.height / 2)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !started else { return }
        started = true
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        // The finished state underneath; each animation runs up to it, and
        // shows its start (`.backwards`) until it begins.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = 1
        name.alpha = 1
        status.alpha = 1
        CATransaction.commit()
        if UIAccessibility.isReduceMotionEnabled {
            // 减弱动态效果: the ring and the name fade in together.
            for target in [ring, name.layer, status.layer] { Self.fade(target, at: now + SplashRing.drawDelay, duration: 0.3) }
            return
        }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.beginTime = now + SplashRing.drawDelay
        draw.duration = SplashRing.drawDuration
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        draw.fillMode = .backwards
        ring.add(draw, forKey: "draw")
        Self.rise(name.layer, at: now + SplashRing.nameDelay, duration: SplashRing.nameDuration)
        Self.rise(status.layer, at: now + SplashRing.statusDelay, duration: SplashRing.statusDuration)
    }

    private static func fade(_ layer: CALayer, at time: CFTimeInterval, duration: Double) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = time
        fade.duration = duration
        fade.fillMode = .backwards
        layer.add(fade, forKey: "fade")
    }
    private static func rise(_ layer: CALayer, at time: CFTimeInterval, duration: Double) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = 6
        move.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fade, move]
        group.beginTime = time
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .backwards
        layer.add(group, forKey: "rise")
    }
}
#endif

/// The demo's icon (Orbit Garden's, in the HOME menu): until 11-07 also the
/// splash's placeholder mark (the ring took its place there).
struct SplashMark: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 1024
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            func square(_ half: CGFloat) -> CGRect {
                CGRect(x: centre.x - half * unit, y: centre.y - half * unit, width: 2 * half * unit, height: 2 * half * unit)
            }
            context.fill(Path(roundedRect: square(296), cornerRadius: 96 * unit),
                         with: .color(Color(red: 166 / 255, green: 240 / 255, blue: 196 / 255)))
            context.fill(Path(ellipseIn: square(176)),
                         with: .color(Color(red: 255 / 255, green: 168 / 255, blue: 104 / 255)))
            context.fill(Path(ellipseIn: square(30)), with: .color(Color(red: 14 / 255, green: 17 / 255, blue: 25 / 255)))
        }
        .accessibilityHidden(true)
    }
}
