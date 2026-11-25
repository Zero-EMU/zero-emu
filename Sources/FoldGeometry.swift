import Foundation
import CoreGraphics

/// The axis along which the physical crease runs (not the axis between panels).
enum FoldAxis: String, CaseIterable { case horizontal, vertical }
struct ViewportInsets: Equatable {
    var top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0
}
struct FoldRegionSnapshot: Equatable {
    var division: CGRect
    var occlusions: [CGRect] = []
    var fromDevice = false
    static func preview(size: CGSize, axis: FoldAxis = .horizontal, fraction: Double = 0.5, gap: Double = 16) -> Self {
        let f = min(0.8, max(0.2, fraction)), g = max(0, gap)
        let rect = axis == .horizontal
            ? CGRect(x: 0, y: size.height * f - g / 2, width: size.width, height: g)
            : CGRect(x: size.width * f - g / 2, y: 0, width: g, height: size.height)
        return Self(division: rect)
    }
}

/// Maps a window's interface coordinates to a reference frame that is drawn
/// rotated by `turn` degrees (clockwise in y-down space, a multiple of 90)
/// about the window centre. FoldArc draws the Duo handheld in such a frame so
/// that it stays fixed to the inner panel — lower screen on the side-button
/// half — whatever interface orientation the system gives the window.
struct FixedFrameTransform: Equatable {
    let turn: Double
    let window: CGSize
    init(turn: Double, window: CGSize) {
        self.turn = Self.normalized(turn)
        self.window = window
    }
    /// Snap to a quarter turn in (-180, 180].
    static func normalized(_ degrees: Double) -> Double {
        var d = (degrees / 90).rounded() * 90
        while d <= -180 { d += 360 }
        while d > 180 { d -= 360 }
        return d
    }
    var isQuarterTurn: Bool { abs(turn) == 90 }
    /// Size of the reference frame (the window's, swapped for a quarter turn).
    var reference: CGSize { isQuarterTurn ? CGSize(width: window.height, height: window.width) : window }

    func toReference(_ p: CGPoint) -> CGPoint {
        let a = -turn * .pi / 180
        let c = cos(a).rounded(), s = sin(a).rounded()   // exact for quarter turns
        let dx = p.x - window.width / 2, dy = p.y - window.height / 2
        return CGPoint(x: reference.width / 2 + dx * c - dy * s, y: reference.height / 2 + dx * s + dy * c)
    }
    func toReference(_ r: CGRect) -> CGRect {
        let a = toReference(CGPoint(x: r.minX, y: r.minY)), b = toReference(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
    func toReference(_ snapshot: FoldRegionSnapshot) -> FoldRegionSnapshot {
        FoldRegionSnapshot(division: toReference(snapshot.division), occlusions: snapshot.occlusions.map { toReference($0) },
                           fromDevice: snapshot.fromDevice)
    }
    /// Window insets as seen from the reference frame's own edges.
    func toReference(_ i: ViewportInsets) -> ViewportInsets {
        switch turn {
        case 90: return ViewportInsets(top: i.trailing, leading: i.top, bottom: i.leading, trailing: i.bottom)
        case -90: return ViewportInsets(top: i.leading, leading: i.bottom, bottom: i.trailing, trailing: i.top)
        case 180: return ViewportInsets(top: i.bottom, leading: i.trailing, bottom: i.top, trailing: i.leading)
        default: return i
        }
    }
    enum WindowEdge: Equatable { case top, leading, bottom, trailing }
    /// The window edge on which the reference frame's top edge is drawn.
    var referenceTopEdge: WindowEdge {
        switch turn {
        case 90: return .trailing
        case -90: return .leading
        case 180: return .bottom
        default: return .top
        }
    }
}

/// The source artwork and live console share these exact screen rectangles.
/// 500×300 / 400×300 = 400×240 / 320×240 at a common scale.
enum ConsoleMetrics {
    static let panel = CGSize(width: 760, height: 440)
    static let hingeHeight = 32.0
    static let upperLCD = CGRect(x: 130, y: 76, width: 500, height: 300)
    static let lowerLCD = CGRect(x: 180, y: 48, width: 400, height: 300)
}

enum ConsoleNavigationGesture {
    static func reveals(translation: CGSize, onCover: Bool = false) -> Bool {
        // A sleeping cover has no game gestures to preserve. Accept a swipe in
        // any direction, including when the outside display is turned around.
        if onCover { return hypot(translation.width, translation.height) >= 38 }
        return translation.height >= 38 && translation.height > abs(translation.width) * 1.3
    }
}

/// Closed-shell preview sizing only; this does not detect a physical display.
struct ClosedShellPlacement {
    let scale: Double
    let rotated: Bool
    static func calculate(size: CGSize) -> Self {
        let rotated = size.height > size.width
        let design = rotated ? CGSize(width: 440, height: 760) : CGSize(width: 760, height: 440)
        return Self(scale: max(0, min((size.width - 32) / design.width, (size.height - 24) / design.height)), rotated: rotated)
    }
}

/// A real cover is attached to its hardware, not to the last gravity reading.
/// The closed iOS scene is locked to portrait; its print is always -90 degrees.
/// Landscape sizing exists for source renders and resizable Mac previews only.
/// Camera regions affect the toolbar, never the orientation of the print.
struct FullScreenCoverPlacement: Equatable {
    let canvasSize: CGSize
    let rotationDegrees: Double

    /// `interfaceRotation` is the rotation of the window's coordinate space
    /// relative to the screen's fixed portrait-up space (0, ±90, 180). The
    /// print is fixed at -90° in that fixed space, so the angle applied inside
    /// the window is -90 minus the interface rotation. Without it (previews,
    /// renders, tests) a portrait viewport is assumed upright and a landscape
    /// one assumed to be the -90° interface, which reproduces the old values.
    static func calculate(size: CGSize, flipped: Bool = false, interfaceRotation: Double? = nil) -> Self {
        let w = max(0, size.width), h = max(0, size.height)
        let portrait = h > w
        let canvas = portrait ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        let rotation = interfaceRotation ?? (portrait ? 0 : -90)
        var angle = (-90 - rotation + (flipped ? 180 : 0)).truncatingRemainder(dividingBy: 360)
        if angle <= -180 { angle += 360 }
        if angle > 180 { angle -= 360 }
        return Self(canvasSize: canvas, rotationDegrees: angle)
    }

    static func toolbar(size: CGSize, insets: ViewportInsets, occlusions: [CGRect]) -> CGRect {
        let safe = CGRect(x: max(0, insets.leading) + 8, y: max(0, insets.top) + 6,
                          width: max(0, size.width - max(0, insets.leading) - max(0, insets.trailing) - 16),
                          height: max(0, size.height - max(0, insets.top) - max(0, insets.bottom) - 12))
        var bar = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: min(44, safe.height))
        for camera in occlusions.sorted(by: { $0.minY < $1.minY }) where bar.intersects(camera) {
            bar.origin.y = camera.maxY + 8
        }
        // No reachable slot is preferable to drawing controls through hardware.
        if bar.maxY > safe.maxY { return .zero }
        return bar
    }
}

struct FoldPlacement: Equatable {
    let axis: FoldAxis
    let upperRegion: CGRect
    let lowerRegion: CGRect
    let foldBand: CGRect
    // Artwork clearance can straddle a zero-thickness physical crease.
    // It must never be reported as the hardware division's actual width.
    let hinge: CGRect
    let upperBody: CGRect
    let lowerBody: CGRect
    let toolbar: CGRect
    let footer: CGRect
    let scale: Double
    let fromDevice: Bool

    var upperScreen: CGRect { transform(ConsoleMetrics.upperLCD, into: upperBody) }
    var lowerScreen: CGRect { transform(ConsoleMetrics.lowerLCD, into: lowerBody) }
    var canPresent: Bool { scale > 0 && toolbar.width > 0 && footer.width > 0 }
    var canShowHandheld: Bool { canPresent && axis == .horizontal }
    /// Round 29: the shoulder keys sit on the drawn hinge.
    /// The Duo's fold is a band of its one display (about 40
    /// points that bend, drawn and touched like the rest: b2's screenshot
    /// shows the hinge in it), so the hinge is on screen however thick the
    /// band. Only a hinge too thin for a finger keeps them along the lower
    /// half's foot (`footer`).
    var shouldersOnHinge: Bool { axis == .horizontal && hinge.height >= 12 }
    /// 11-06 (the keys at the lower half's
    /// top corners are gone again): the hinge with its keys for the iPhone Duo
    /// half open — the same band, moved down off the crease by three quarters
    /// of its height, or as far as the lower casing leaves room: the band and
    /// the touch its keys take below them (HingeShoulderKey.touchBelow) stay
    /// clear of the lower screen's frame. The halves stay where they are.
    /// Points, in the viewport. nil without a hinge across (the keys are along
    /// the foot then) or with no room to move it.
    var loweredHinge: CGRect? {
        guard axis == .horizontal, shouldersOnHinge, scale > 0 else { return nil }
        let frameTop = lowerBody.minY + Self.lowerFrameTop * scale
        let room = frameTop - Self.loweredClearance - hinge.maxY
        let drop = min(hinge.height * Self.loweredDrop, room)
        guard drop >= 1 else { return nil }
        return hinge.offsetBy(dx: 0, dy: drop)
    }
    /// The lower screen's frame's top edge, in the panel's units (the frame is
    /// 6 round ConsoleMetrics.lowerLCD, whose top is 48).
    static let lowerFrameTop = 42.0
    /// How far the hinge goes down, as a part of its height.
    static let loweredDrop = 0.75
    /// Kept between the lowered band and the lower screen's frame: the keys'
    /// touch below them (10 points) and a little more.
    static let loweredClearance = 12.0
    private func transform(_ rect: CGRect, into body: CGRect) -> CGRect {
        CGRect(x: body.minX + rect.minX * scale, y: body.minY + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    static func calculate(size: CGSize, insets: ViewportInsets = .init(), snapshot: FoldRegionSnapshot) -> Self {
        let w = max(0, size.width), h = max(0, size.height)
        let safe = CGRect(x: max(0, insets.leading), y: max(0, insets.top),
                          width: max(0, w - max(0, insets.leading) - max(0, insets.trailing)),
                          height: max(0, h - max(0, insets.top) - max(0, insets.bottom)))
        let fold = snapshot.division
        let axis: FoldAxis = fold.width >= fold.height ? .horizontal : .vertical
        let horizontal = axis == .horizontal
        let extent = horizontal ? h : w
        let center = min(extent, max(0, horizontal ? fold.midY : fold.midX))
        // Include the inactive, zero-thickness division when completely flat.
        // Region.frame already contains hardware margins; do not invent more.
        let gap = min(extent, max(0, horizontal ? fold.height : fold.width))
        let start = max(0, center - gap / 2), end = min(extent, center + gap / 2)
        let band = horizontal ? CGRect(x: 0, y: start, width: w, height: end - start)
                              : CGRect(x: start, y: 0, width: end - start, height: h)
        let first = horizontal ? CGRect(x: 0, y: 0, width: w, height: start)
                               : CGRect(x: 0, y: 0, width: start, height: h)
        let second = horizontal ? CGRect(x: 0, y: end, width: w, height: h - end)
                                : CGRect(x: end, y: 0, width: w - end, height: h)
        let upper = avoid(snapshot.occlusions, in: intersection(first, safe))
        let lower = avoid(snapshot.occlusions, in: intersection(second, safe))
        let toolbar = CGRect(x: upper.minX + 12, y: upper.minY + 6, width: max(0, upper.width - 24), height: min(34, upper.height))
        let footer = CGRect(x: lower.minX + 12, y: max(lower.minY, lower.maxY - 50), width: max(0, lower.width - 24), height: min(44, lower.height))
        // An occlusion on just one half must not offset the two lids. Use the
        // overlap of their available horizontal ranges as one shared column.
        let columnX = max(upper.minX, lower.minX)
        let columnWidth = max(0, min(upper.maxX, lower.maxX) - columnX)
        let topSpace = CGRect(x: (horizontal ? columnX : upper.minX) + 8, y: upper.minY + 48,
                              width: max(0, (horizontal ? columnWidth : upper.width) - 16), height: max(0, upper.height - 48))
        let bottomSpace = CGRect(x: (horizontal ? columnX : lower.minX) + 8, y: lower.minY,
                                 width: max(0, (horizontal ? columnWidth : lower.width) - 16), height: max(0, lower.height - 58))
        var s = max(0, min(topSpace.width / ConsoleMetrics.panel.width, topSpace.height / ConsoleMetrics.panel.height,
                           bottomSpace.width / ConsoleMetrics.panel.width, bottomSpace.height / ConsoleMetrics.panel.height))
        if horizontal {
            // Each lid needs half the artwork hinge. When the real division is
            // wider, that reserved band already provides some/all of the room.
            let halfHingePanel = ConsoleMetrics.panel.height + ConsoleMetrics.hingeHeight / 2
            s = max(0, min(s, (topSpace.height + band.height / 2) / halfHingePanel,
                             (bottomSpace.height + band.height / 2) / halfHingePanel))
        }
        let hingeHeight = horizontal ? max(band.height, ConsoleMetrics.hingeHeight * s) : band.height
        let clearance = horizontal ? max(0, hingeHeight - band.height) / 2 : 0
        let bw = ConsoleMetrics.panel.width * s, bh = ConsoleMetrics.panel.height * s
        // Keep the artwork hinge centered on the physical crease, with the
        // upper lid entirely above it and the controls entirely below it.
        let topBody = CGRect(x: horizontal ? topSpace.midX - bw / 2 : topSpace.maxX - bw,
                             y: horizontal ? topSpace.maxY - bh - clearance : topSpace.midY - bh / 2, width: bw, height: bh)
        let bottomBody = CGRect(x: horizontal ? bottomSpace.midX - bw / 2 : bottomSpace.minX,
                                y: horizontal ? bottomSpace.minY + clearance : bottomSpace.midY - bh / 2, width: bw, height: bh)
        let hinge = horizontal ? CGRect(x: topBody.minX, y: band.midY - hingeHeight / 2, width: bw, height: hingeHeight) : band
        return Self(axis: axis, upperRegion: upper, lowerRegion: lower, foldBand: band,
                    hinge: hinge, upperBody: topBody, lowerBody: bottomBody, toolbar: toolbar, footer: footer, scale: s, fromDevice: snapshot.fromDevice)
    }

    private static func intersection(_ a: CGRect, _ b: CGRect) -> CGRect {
        let r = a.intersection(b)
        return r.isNull ? CGRect(x: a.minX, y: a.minY, width: 0, height: 0) : r
    }
    private static func avoid(_ occlusions: [CGRect], in initial: CGRect) -> CGRect {
        var area = initial
        for original in occlusions {
            let obstruction = original.insetBy(dx: -4, dy: -4)
            guard area.intersects(obstruction) else { continue }
            let cuts = [
                CGRect(x: area.minX, y: area.minY, width: max(0, obstruction.minX - area.minX), height: area.height),
                CGRect(x: min(area.maxX, obstruction.maxX), y: area.minY, width: max(0, area.maxX - obstruction.maxX), height: area.height),
                CGRect(x: area.minX, y: area.minY, width: area.width, height: max(0, obstruction.minY - area.minY)),
                CGRect(x: area.minX, y: min(area.maxY, obstruction.maxY), width: area.width, height: max(0, area.maxY - obstruction.maxY))
            ].map { intersection($0, area) }
            area = cuts.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
        }
        return area
    }

    /// The physical display is the console casing. Safe areas and cameras only
    /// constrain LCDs, controls and temporary navigation, never the shell paint.
    static func immersive(size: CGSize, insets: ViewportInsets = .init(), snapshot: FoldRegionSnapshot) -> Self {
        var unoccluded = snapshot
        unoccluded.occlusions = []
        let physical = calculate(size: size, snapshot: unoccluded)
        if physical.axis == .vertical { return calculate(size: size, insets: insets, snapshot: snapshot) }
        let w = max(0, size.width), h = max(0, size.height)
        let safe = CGRect(x: max(0, insets.leading), y: max(0, insets.top),
                          width: max(0, w - max(0, insets.leading) - max(0, insets.trailing)),
                          height: max(0, h - max(0, insets.top) - max(0, insets.bottom)))
        let upperSafe = avoid(snapshot.occlusions, in: intersection(physical.upperRegion, safe))
        let lowerSafe = avoid(snapshot.occlusions, in: intersection(physical.lowerRegion, safe))
        let columnX = max(upperSafe.minX, lowerSafe.minX)
        let columnWidth = max(0, min(upperSafe.maxX, lowerSafe.maxX) - columnX)
        // The shoulder controls belong to the lower casing, not a separate bar.
        // Round 29: they are on the hinge (FoldPlacement.shouldersOnHinge),
        // and the foot keeps no room for them — unless the hinge, at the
        // scale the console then gets, would be too thin to hold them.
        let footHeight = min(44.0, lowerSafe.height * 0.14)
        let fullScale = max(0, min(columnWidth / ConsoleMetrics.panel.width,
                                   max(0, upperSafe.height - 8) / 456,
                                   max(0, lowerSafe.height - 8) / 456))
        let onHinge = physical.axis == .horizontal && max(physical.foldBand.height, ConsoleMetrics.hingeHeight * fullScale) >= 12
        let shoulderHeight = onHinge ? 0 : footHeight
        let s = max(0, min(columnWidth / ConsoleMetrics.panel.width,
                           max(0, upperSafe.height - 8) / 456,
                           max(0, lowerSafe.height - shoulderHeight - 8) / 456))
        let hingeHeight = physical.axis == .horizontal ? max(physical.foldBand.height, ConsoleMetrics.hingeHeight * s) : physical.foldBand.height
        let clearance = physical.axis == .horizontal ? max(0, hingeHeight - physical.foldBand.height) / 2 : 0
        let bw = ConsoleMetrics.panel.width * s, bh = ConsoleMetrics.panel.height * s
        let upperSpace = CGRect(x: columnX, y: upperSafe.minY,
                                width: columnWidth, height: max(0, upperSafe.height - clearance))
        let lowerSpace = CGRect(x: columnX, y: lowerSafe.minY + clearance,
                                width: columnWidth, height: max(0, lowerSafe.height - clearance - shoulderHeight))
        let topBody = CGRect(x: upperSpace.midX - bw / 2, y: upperSpace.midY - bh / 2, width: bw, height: bh)
        let bottomBody = CGRect(x: lowerSpace.midX - bw / 2, y: lowerSpace.midY - bh / 2, width: bw, height: bh)
        let toolbar = CGRect(x: upperSafe.minX + 8, y: upperSafe.minY + 6,
                             width: max(0, upperSafe.width - 16), height: min(44, max(0, upperSafe.height - 12)))
        let footer = CGRect(x: lowerSafe.minX + 8, y: lowerSafe.maxY - shoulderHeight,
                            width: max(0, lowerSafe.width - 16), height: shoulderHeight)
        let hinge = physical.axis == .horizontal
            ? CGRect(x: 0, y: physical.foldBand.midY - hingeHeight / 2, width: w, height: hingeHeight)
            : physical.foldBand
        return Self(axis: physical.axis, upperRegion: physical.upperRegion, lowerRegion: physical.lowerRegion,
                    foldBand: physical.foldBand, hinge: hinge, upperBody: topBody, lowerBody: bottomBody,
                    toolbar: toolbar, footer: footer, scale: s, fromDevice: snapshot.fromDevice)
    }
}

// MARK: - The camera on the cover (round 32)

/// How the shut console is
/// held, as the person holding it sees the cover. Upright portrait is the
/// cover's own orientation — its camera in the top-right corner, the hinge
/// down the left edge, the side button and the Camera Control down the right
/// one (Apple's "Designing for iPhone Duo"); the others are that turned.
enum CoverHold: String, CaseIterable {
    case portrait, clockwise, counterclockwise, upsideDown
    /// How far the console is turned clockwise from upright portrait.
    var degrees: Double {
        switch self {
        case .portrait: return 0
        case .clockwise: return 90
        case .counterclockwise: return -90
        case .upsideDown: return 180
        }
    }
    var isLandscape: Bool { self == .clockwise || self == .counterclockwise }
    /// 11-15: the hold gravity points to (`x` right, `y` up the shut
    /// console's face, as UIKit's device orientation reads it): the edge it
    /// pulls towards most; away from `current` only once that edge is
    /// clearly the lower one (by a quarter of the pull); lying flat, none.
    static func fromGravity(x: Double, y: Double, current: CoverHold) -> CoverHold? {
        let pull = (x * x + y * y).squareRoot()
        guard pull > 0.45 else { return nil }
        let down: [(CoverHold, Double)] = [(.portrait, -y), (.upsideDown, y), (.clockwise, x), (.counterclockwise, -x)]
        guard let best = down.max(by: { $0.1 < $1.1 }), let now = down.first(where: { $0.0 == current }) else { return nil }
        return best.1 > now.1 + 0.25 * pull ? best.0 : current
    }
    var title: String {
        switch self {
        case .portrait: return String(localized: "竖着拿")
        case .clockwise: return String(localized: "横着拿 · 铰链朝上")
        case .counterclockwise: return String(localized: "横着拿 · 铰链朝下")
        case .upsideDown: return String(localized: "倒着竖拿")
        }
    }
}

/// The cover as built, in its own upright portrait frame (points). The
/// display is the Duo simulator's (466 × 678; its mask rounds the two right
/// corners 59 points and the hinge side's 8). Apple puts the cover's camera
/// in the top-right corner at the head of the controls that run down the
/// right edge, and the Camera Control on the right edge under the side
/// button; neither has a published size or place in points, so these are
/// estimates. They are used where the system reports nothing: on the cover
/// itself the camera's reserved region (ReservedRegion, .occlusion) wins.
struct CoverHardware: Equatable {
    var size = CGSize(width: 466, height: 678)
    /// The camera's region (measured on a screenshot of the cover deck): an
    /// upright pill about 38 × 63
    /// points, 27 down from the top and 29 in from the right edge (it was
    /// taken as a 38-point circle in the very corner, and 外侧 went under it).
    var camera = CGRect(x: 398, y: 25, width: 42, height: 67)
    /// The Camera Control's middle along the right edge, from the top.
    var controlCentre = 0.62
    /// How far the system's overlay for the Camera Control reaches in from
    /// that edge, and how long it is along it.
    var overlayDepth = 72.0
    var overlayLength = 240.0
    static let duo = CoverHardware()
    /// The overlay's area (HIG Camera Control: "the overlay and control
    /// labels occupy the screen area adjacent to the Camera Control").
    var overlay: CGRect {
        CGRect(x: size.width - overlayDepth, y: size.height * controlCentre - overlayLength / 2,
               width: overlayDepth, height: overlayLength)
    }
    /// The same hardware on a frame of another size (a preview drawn on the
    /// inner display or on a phone): the camera keeps its size and its
    /// distance from the top-right corner; the Camera Control its place
    /// along the edge.
    func fitted(to frame: CGSize) -> CoverHardware {
        guard size.width > 0, size.height > 0, frame.width > 0, frame.height > 0 else { return self }
        var copy = self
        copy.camera = CGRect(x: frame.width - (size.width - camera.minX), y: camera.minY, width: camera.width, height: camera.height)
        copy.size = frame
        return copy
    }
}

/// The deck on a window: turned so that it stands upright for the person
/// holding the console, whatever the window's own interface orientation.
struct CoverHoldPlacement: Equatable {
    let hold: CoverHold
    let window: CGSize
    /// The window's size in the hardware's own portrait frame.
    let fixedSize: CGSize
    /// For `rotationEffect` (degrees, clockwise, y down).
    let rotationDegrees: Double
    /// The canvas the deck is laid out on (upright for the holder).
    var canvasSize: CGSize { FixedFrameTransform(turn: rotationDegrees, window: window).reference }

    /// `interfaceRotation` as `DisplayRoleMonitor.interfaceRotation`: the
    /// window's coordinate space against the screen's fixed portrait one
    /// (0, ±90, 180). The hold is against that fixed frame too, so the
    /// canvas is turned by minus both.
    static func calculate(window: CGSize, interfaceRotation: Double, hold: CoverHold) -> Self {
        let theta = FixedFrameTransform.normalized(interfaceRotation)
        let fixed = abs(theta) == 90 ? CGSize(width: window.height, height: window.width) : window
        return Self(hold: hold, window: window, fixedSize: fixed,
                    rotationDegrees: FixedFrameTransform.normalized(-hold.degrees - theta))
    }
    /// A window rect (a reserved region, read in the window) on the canvas.
    func canvas(fromWindow rect: CGRect) -> CGRect {
        FixedFrameTransform(turn: rotationDegrees, window: window).toReference(rect)
    }
    /// Window safe-area insets as the canvas's own edges.
    func canvas(fromWindow insets: ViewportInsets) -> ViewportInsets {
        FixedFrameTransform(turn: rotationDegrees, window: window).toReference(insets)
    }
    /// A rect in the hardware's portrait frame (`fixedSize`) on the canvas.
    func canvas(fromFixed rect: CGRect) -> CGRect {
        FixedFrameTransform(turn: -hold.degrees, window: fixedSize).toReference(rect)
    }
    /// The reserved regions a window reports, on the canvas — only those
    /// that lie in the window (a point of slack). On the shut Duo the
    /// simulator handed over the camera's region still in the window's
    /// earlier, landscape frame (611,399 in a 466-point-wide window, 954)
    /// for a moment after the window turned portrait; such a rect is
    /// nowhere on this window, and the hardware's estimate stands in.
    func canvas(fromReported rects: [CGRect]) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: window).insetBy(dx: -1, dy: -1)
        return rects.filter { !$0.isNull && $0.width > 0 && $0.height > 0 && bounds.contains($0) }.map { canvas(fromWindow: $0) }
    }
}

/// The shut console's camera deck, laid out for the hold on the
/// upright canvas (points). Apple's guidance, as it is applied here:
/// - "Designing for iPhone Duo": on the cover the controls run down the
///   trailing edge with the camera at their head; the camera's region is
///   reserved (nothing is drawn over it); "keep controls' relative positions
///   as similar as possible" as the pose changes.
/// - "Camera Control": the overlay comes in from the edge beside the button;
///   "place your UI outside of the overlay areas", and "allow the overlay to
///   appear and disappear over" the viewfinder.
/// - "Accessibility": controls at least 44 × 44 points.
/// So: the controls in a column on the right, the right thumb's side, in
/// every hold; 拍照 where the thumb rests, clear of the camera and of the
/// overlay; the picture on the left, and on the Camera Control's side when
/// that is the long top or bottom edge; the zoom inside the picture (as on
/// the iPhone's own camera) at the edge away from the overlay; the rows
/// under (or over) the picture stepping aside for the camera and the
/// overlay.
/// 11-19, a camera body's own back on the cover, laid out for the Duo's
/// cover as it is (466 × 678 held upright): the column the picture and
/// the keys have, and the strip down the trailing side that is left to
/// the phone's own camera and to the Camera Control's overlay (in it only
/// what does not matter under the overlay, and the shutter under the
/// thumb, below it). None when the deck is not upright, or the camera or
/// the overlay is not down that side (the deck the other way up).
struct CoverBackFrame: Equatable {
    var canvas: CGSize
    var column: CGRect
    var strip: CGRect
    var keepOut: [CGRect]
    var overlay: CGRect?
    /// The column's width on the Duo's cover: the measure the parts are
    /// drawn to (narrower columns scale across).
    static let designWidth = 372.0

    static func calculate(canvas: CGSize, safe: ViewportInsets = ViewportInsets(), cameras: [CGRect], overlay: CGRect?) -> CoverBackFrame? {
        let w = max(0, canvas.width), h = max(0, canvas.height)
        guard h > w, w > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let keep = cameras.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }.map { $0.insetBy(dx: -8, dy: -8) }
        let zone: CGRect? = overlay.flatMap { r in
            let c = r.intersection(bounds)
            return c.isNull || c.width <= 0 || c.height <= 0 ? nil : c
        }
        let blockers = keep + (zone.map { [$0] } ?? [])
        guard !blockers.isEmpty, blockers.allSatisfy({ $0.minX >= w * 0.6 }) else { return nil }
        let edge = Double(blockers.map(\.minX).min() ?? w) - 4
        let left = max(0, safe.leading) + 14, top = max(0, safe.top) + 14
        let bottom = Double(h) - max(0, safe.bottom)
        guard edge - left >= 240, bottom - top >= 560 else { return nil }
        let column = CGRect(x: left, y: top, width: edge - left, height: bottom - top)
        let strip = CGRect(x: edge + 6, y: top, width: max(0, Double(w) - max(0, safe.trailing) - 8 - edge - 6), height: bottom - top)
        guard strip.width >= 44 else { return nil }
        return CoverBackFrame(canvas: canvas, column: column, strip: strip, keepOut: keep, overlay: zone)
    }
}

/// The cover held across, for a camera body's own back: the camera and the
/// Camera Control's overlay lie along one long edge, in a band where nothing
/// is pressed but in its clear runs; the rest is the picture's screen at the
/// left and the keys in a column at the right (the Duo's cover's points:
/// the band 78 high, the column 200 by 356).
struct CoverBackAcross: Equatable {
    var canvas: CGSize
    var band: CGRect
    /// The band's clear runs, the longer first (zero where there is none).
    var run: CGRect
    var spare: CGRect
    var screen: CGRect
    var keys: CGRect
    var keepOut: [CGRect]
    var overlay: CGRect?
    /// 11-22: all that is not the band, inside the safe area at its sides (the home indicator's edge, the lower
    /// one, taking no more than its 22 points): where a body laid out its own way puts its parts (the retro
    /// computer's desk).
    var area = CGRect.zero
    static let bandHeight = 78.0
    static let keysWidth = 200.0
    static let keysHeight = 356.0
    /// The picture's place begins this far inside the screen's surround.
    static let reach = 14.0

    static func calculate(canvas: CGSize, safe: ViewportInsets = ViewportInsets(), cameras: [CGRect], overlay: CGRect?) -> CoverBackAcross? {
        let w = Double(max(0, canvas.width)), h = Double(max(0, canvas.height))
        guard w > h, h > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let keep = cameras.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }.map { $0.insetBy(dx: -8, dy: -8) }
        let zone: CGRect? = overlay.flatMap { r in
            let c = r.intersection(bounds)
            return c.isNull || c.width <= 0 || c.height <= 0 ? nil : c
        }
        let blockers = keep + (zone.map { [$0] } ?? [])
        guard !blockers.isEmpty else { return nil }
        // (What is kept out may reach a little past the band, over the
        // screen's surround at its corner — the corner the shut Duo reserves
        // round its camera is 84 deep — but never over the picture, which
        // begins `reach` in, or the keys.)
        let atTop = blockers.allSatisfy { Double($0.maxY) <= bandHeight + reach }
        let atBottom = blockers.allSatisfy { Double($0.minY) >= h - bandHeight - reach }
        guard atTop || atBottom else { return nil }
        let band = CGRect(x: 0, y: atTop ? 0 : h - bandHeight, width: w, height: bandHeight)
        // The rest: inside the safe area at its sides; the home indicator's
        // edge, when it is the lower one, takes no more than its own 22
        // points (the keys end over the indicator, not on it).
        let left = max(0, safe.leading) + 10, right = w - max(0, safe.trailing) - 12
        let top = atTop ? bandHeight : max(0, safe.top) + 6
        let bottom = atTop ? h - min(max(0, safe.bottom), 22) : h - bandHeight
        let over = bottom - top - keysHeight
        guard over >= 4, right - left >= keysWidth + 8 + 300 else { return nil }
        let keysTop = top + min(12, max(4, over / 2))
        let keys = CGRect(x: right - keysWidth, y: keysTop, width: keysWidth, height: keysHeight)
        let screenTop = max(top, keysTop - 6)
        let screen = CGRect(x: left, y: screenTop, width: Double(keys.minX) - 8 - left, height: min(343, bottom - 2 - screenTop))
        // (More than half a point over one another: edges that meet are clear.)
        func crosses(_ a: CGRect, _ b: CGRect) -> Bool {
            a.minX < b.maxX - 0.5 && b.minX < a.maxX - 0.5 && a.minY < b.maxY - 0.5 && b.minY < a.maxY - 0.5
        }
        let pictureBox = screen.insetBy(dx: reach, dy: reach)
        guard !blockers.contains(where: { crosses($0, keys) || crosses($0, pictureBox) }) else { return nil }
        // The band's clear runs between and beside what is kept out of it.
        let spans = blockers.map { (Double($0.minX) - 8, Double($0.maxX) + 8) }.sorted { $0.0 < $1.0 }
        var free: [(Double, Double)] = []
        var at = 12.0
        for span in spans {
            if span.0 > at { free.append((at, span.0)) }
            at = max(at, span.1)
        }
        if w - 12 > at { free.append((at, w - 12)) }
        let ranked = free.filter { $0.1 - $0.0 >= 40 }.sorted { $0.1 - $0.0 > $1.1 - $1.0 }
        func place(_ index: Int) -> CGRect {
            guard index < ranked.count else { return .zero }
            return CGRect(x: ranked[index].0, y: Double(band.minY) + 6, width: ranked[index].1 - ranked[index].0, height: bandHeight - 12)
        }
        return CoverBackAcross(canvas: canvas, band: band, run: place(0), spare: place(1), screen: screen, keys: keys, keepOut: keep, overlay: zone,
                               area: CGRect(x: left, y: top, width: right - left, height: bottom - top))
    }
}

struct CoverDeckLayout: Equatable {
    var canvas: CGSize
    /// The camera (with a margin), and the Camera Control's overlay.
    var keepOut: [CGRect]
    var overlay: CGRect?
    var viewfinder: CGRect
    /// The zoom stops on the picture: a column down its edge beside 拍照
    /// held across, a row along its lower edge upright (`zoomColumn`).
    var zoomBar: CGRect
    var lensRow: CGRect
    var toolRow: CGRect
    var shootingRow: CGRect
    var album: CGRect
    var flip: CGRect
    var shutter: CGRect
    /// A line of help text; .zero when there is no room for it.
    var hint: CGRect
    /// Where 切换机型's menu opens (over the rows; the picture stays seen).
    var bodyMenu: CGRect
    /// The rows are over the picture (the Camera Control along the bottom).
    var pictureBelow: Bool
    /// A camera body's own back (11-19): the room kept over and under the
    /// picture for that body's own parts (a print's slot, a screen's bars),
    /// and the block under them, down to the canvas's lower margin, where
    /// its keys are laid out — .zero where the rows are over the picture.
    var above = 0.0
    var below = 0.0
    var keys = CGRect.zero

    static let target = 44.0
    /// A lens chip (and a pinned body's).
    static let lensChip = CGSize(width: 56, height: 52)
    static let margin = 12.0
    static let lensHeight = 52.0
    static let rowHeight = 44.0
    static let rowGap = 6.0
    static let tileHeight = 60.0
    /// The zoom stops' circles as seen (each is pressed as `target`): the
    /// chosen one larger, with the zoom written in it.
    static let stopDot = 28.0
    static let chosenStopDot = 34.0

    /// How far the picture's own chips reach in from its top edge (and its
    /// bottom one): CameraLiveTop's strips, a 5-point margin and a 15-point
    /// chip at the picture's scale (its width / 400), with a little room.
    static func chipBand(pictureWidth: Double) -> Double { max(0.4, pictureWidth / 400) * 22 }

    /// The rects a finger presses whole (the rows hold chips and pills of
    /// at least `target` in height).
    var targets: [CGRect] { [album, flip, shutter, zoomBar, lensRow, toolRow, shootingRow] }
    /// The zoom stops run down the picture's edge (held across).
    var zoomColumn: Bool { zoomBar.height > zoomBar.width }
    /// The picture inside its bezel (what CameraTopScreen fills).
    var picture: CGRect { viewfinder.width > 12 && viewfinder.height > 12 ? viewfinder.insetBy(dx: 6, dy: 6) : .zero }
    /// Points of the picture its own chips keep clear for the zoom stops: in
    /// from its lower edge (a row there) and from its trailing edge (a column).
    var stopsClearance: (bottom: Double, trailing: Double) {
        let p = picture
        guard zoomBar.width > 0, p.width > 0 else { return (0, 0) }
        if zoomColumn { return (0, max(0, Double(p.maxX - zoomBar.minX))) }
        if zoomBar.midY > p.midY { return (max(0, Double(p.maxY - zoomBar.minY)), 0) }
        return (0, 0)
    }

    static func calculate(canvas: CGSize, safe: ViewportInsets = ViewportInsets(), cameras: [CGRect], overlay: CGRect?,
                          zoomStops: Int = 3, aspect: Double = 5.0 / 3,
                          above: Double = 0, below: Double = 0, keysHeight: Double? = nil) -> Self {
        let w = max(0, canvas.width), h = max(0, canvas.height)
        let area = CGRect(x: max(0, safe.leading) + margin, y: max(0, safe.top) + margin,
                          width: max(0, w - max(0, safe.leading) - max(0, safe.trailing) - 2 * margin),
                          height: max(0, h - max(0, safe.top) - max(0, safe.bottom) - 2 * margin))
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let keep = cameras.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }.map { $0.insetBy(dx: -8, dy: -8) }
        let zone: CGRect? = overlay.flatMap { r in
            let c = r.intersection(bounds)
            return c.isNull || c.width <= 0 || c.height <= 0 ? nil : c
        }
        let blockers = keep + (zone.map { [$0] } ?? [])
        let landscape = w > h
        let columnWidth = landscape ? 148.0 : 100.0
        let column = CGRect(x: area.maxX - columnWidth, y: area.minY, width: columnWidth, height: area.height)
        let main = CGRect(x: area.minX, y: area.minY, width: max(0, column.minX - 12 - area.minX), height: area.height)

        // The column: 拍照 where the right thumb rests (the middle of the
        // right side held across, the lower right held upright), then the
        // switch and the album, then the help line.
        var taken: [ClosedRange<Double>] = blockers.filter { $0.maxX > column.minX && $0.minX < column.maxX }
            .map { (Double($0.minY) - 6)...(Double($0.maxY) + 6) }
        var shutterSize = landscape ? 104.0 : 96.0
        let thumb = Double(area.minY) + Double(area.height) * (landscape ? 0.52 : 0.86)
        // Where the thumb rests, a little smaller (not under 72) rather than
        // away from it: 955, the shut Duo's own cover — its home-indicator edge
        // is 34 points, not the 20 taken before, which left 86 points under
        // the Camera Control's overlay held upright, and 拍照 went up above
        // the overlay, out of the thumb's reach.
        let stretches = free(column, taken)
        func distance(_ s: ClosedRange<Double>) -> Double { thumb < s.lowerBound ? s.lowerBound - thumb : max(0, thumb - s.upperBound) }
        if let nearest = stretches.min(by: { distance($0) < distance($1) }), distance(nearest) < shutterSize / 2,
           nearest.upperBound - nearest.lowerBound < shutterSize, nearest.upperBound - nearest.lowerBound >= 72 {
            shutterSize = (nearest.upperBound - nearest.lowerBound).rounded(.down)
        }
        let shutterY = place(shutterSize, near: thumb, in: stretches) ?? (thumb - shutterSize / 2)
        let shutter = CGRect(x: Double(column.midX) - shutterSize / 2, y: shutterY, width: shutterSize, height: shutterSize)
        taken.append((shutterY - 12)...(shutterY + shutterSize + 12))
        var album = CGRect.zero, flip = CGRect.zero
        let columnX = Double(column.minX), columnTop = Double(column.minY)
        if landscape {
            let tileWidth = (columnWidth - 8) / 2
            let y = place(tileHeight, near: shutterY - 12 - tileHeight / 2, in: free(column, taken))
                ?? place(tileHeight, near: shutterY + shutterSize + 12 + tileHeight / 2, in: free(column, taken)) ?? columnTop
            flip = CGRect(x: columnX, y: y, width: tileWidth, height: tileHeight)
            album = CGRect(x: columnX + columnWidth - tileWidth, y: y, width: tileWidth, height: tileHeight)
            taken.append((y - 6)...(y + tileHeight + 6))
        } else {
            let block = tileHeight * 2 + 8
            let y = place(block, near: columnTop, in: free(column, taken)) ?? columnTop
            flip = CGRect(x: columnX, y: y, width: columnWidth, height: tileHeight)
            album = CGRect(x: columnX, y: y + tileHeight + 8, width: columnWidth, height: tileHeight)
            taken.append((y - 6)...(y + block + 6))
        }
        var hint = place(36, near: shutterY + shutterSize + 12 + 18, in: free(column, taken))
            .map { CGRect(x: columnX, y: $0, width: columnWidth, height: 36) } ?? .zero
        if hint != .zero, abs(Double(hint.midY) - (shutterY + shutterSize / 2)) > shutterSize { hint = .zero }

        // The picture: on the left, and on the Camera Control's side when its
        // overlay comes in from the long bottom edge (rows over the picture).
        let pictureBelow = zone.map { $0.maxY >= h - 1 && $0.maxX > main.minX && $0.minX < main.maxX } ?? false
        // Upright there is the height for two lines of lenses and of the
        // old camera's settings (and the width is short for one).
        let twoLines = !landscape
        let lensHeight = twoLines ? Self.lensHeight * 2 + rowGap : Self.lensHeight
        let shootingHeight = twoLines ? rowHeight * 2 + rowGap : rowHeight
        let rowsHeight = lensHeight + rowHeight + shootingHeight + 2 * rowGap
        // (A body's own back: its own height of keys under the picture, and
        // its bands over and under it; none of them where the rows are over
        // the picture.)
        let over = pictureBelow ? 0 : max(0, above), under = pictureBelow ? 0 : max(0, below)
        let kept = pictureBelow ? rowsHeight : max(0, keysHeight ?? rowsHeight)
        let pictureSpace = CGRect(x: main.minX, y: pictureBelow ? main.minY + rowsHeight + 8 : main.minY + over,
                                  width: main.width, height: max(0, main.height - kept - 8 - over - under))
        var candidates = [pictureSpace]
        for k in keep where k.intersects(pictureSpace) {
            candidates.append(CGRect(x: pictureSpace.minX, y: pictureSpace.minY, width: k.minX - pictureSpace.minX, height: pictureSpace.height))
            candidates.append(CGRect(x: k.maxX, y: pictureSpace.minY, width: pictureSpace.maxX - k.maxX, height: pictureSpace.height))
            candidates.append(CGRect(x: pictureSpace.minX, y: pictureSpace.minY, width: pictureSpace.width, height: k.minY - pictureSpace.minY))
            candidates.append(CGRect(x: pictureSpace.minX, y: k.maxY, width: pictureSpace.width, height: pictureSpace.maxY - k.maxY))
        }
        let viewfinder = candidates.map { fitPicture(in: $0, alignBottom: pictureBelow, aspect: aspect) }
            .filter { v in v.width > 0 && !keep.contains { $0.intersects(v) } }
            .max { $0.width < $1.width } ?? .zero

        // The rows, next to the picture, stepping aside for the camera and the overlay.
        func row(_ y: Double, _ height: Double) -> CGRect {
            var r = CGRect(x: Double(main.minX), y: y, width: Double(main.width), height: height)
            for b in blockers where b.intersects(r) {
                if b.midX <= r.midX {
                    r = CGRect(x: b.maxX + 6, y: r.minY, width: max(0, r.maxX - b.maxX - 6), height: r.height)
                } else {
                    r.size.width = max(0, b.minX - 6 - r.minX)
                }
            }
            return r
        }
        let rowsTop: Double = pictureBelow ? Double(viewfinder.minY) - 8 - rowsHeight : Double(viewfinder.maxY) + 8 + under
        let lensRow = row(rowsTop, lensHeight)
        let toolRow = row(Double(lensRow.maxY) + rowGap, rowHeight)
        let shootingRow = row(Double(toolRow.maxY) + rowGap, shootingHeight)
        let menuHeight = max(rowsHeight, 156.0)
        let menuTop: Double = pictureBelow ? max(Double(area.minY), rowsTop + rowsHeight - menuHeight) : rowsTop
        let bodyMenu = CGRect(x: Double(main.minX), y: menuTop, width: Double(main.width), height: menuHeight)

        // The zoom stops on the picture (HIG Camera
        // Control: a large preview with as few distractions as possible) —
        // small see-through circles, each pressed as 44 points, nothing
        // behind them. Held across: a column down the picture's edge beside
        // 拍照 (the right thumb's), at 拍照's height as near as the picture's
        // chips, the overlay and the camera let it. Upright, or where that
        // column does not fit (a phone's short picture): a row along the
        // picture's lower edge (toward 拍照 held across), or under its top
        // chips when the overlay or the camera is at the lower edge.
        let stops = Double(max(1, zoomStops))
        let run = stops * target
        let picture = viewfinder.width > 12 && viewfinder.height > 12 ? viewfinder.insetBy(dx: 6, dy: 6) : .zero
        let band = Self.chipBand(pictureWidth: Double(picture.width))
        var zoomBar = CGRect.zero
        if landscape, picture.width > target, Double(picture.height) > band + 2 + run {
            let strip = CGRect(x: Double(picture.maxX) - 2 - target, y: Double(picture.minY) + band,
                               width: target, height: Double(picture.height) - band - 2)
            let inStrip = blockers.filter { $0.intersects(strip) }.map { (Double($0.minY) - 6)...(Double($0.maxY) + 6) }
            if let top = place(run, near: Double(shutter.midY), in: free(strip, inStrip)) {
                zoomBar = CGRect(x: Double(strip.minX), y: top, width: target, height: run)
            }
        }
        if zoomBar == .zero, picture.width > 0 {
            let x = landscape ? Double(picture.maxX) - 2 - run : Double(picture.midX) - run / 2
            zoomBar = CGRect(x: x, y: Double(picture.maxY) - 2 - target, width: run, height: target)
            if blockers.contains(where: { $0.intersects(zoomBar) }) { zoomBar.origin.y = Double(picture.minY) + band }
        }

        // Upright, with the room under the rows: the help line goes there.
        if hint == .zero, !pictureBelow, Double(area.maxY - shootingRow.maxY) >= 44 {
            hint = row(Double(shootingRow.maxY) + 10, 34)
        }
        var made = Self(canvas: canvas, keepOut: keep, overlay: zone, viewfinder: viewfinder, zoomBar: zoomBar,
                        lensRow: lensRow, toolRow: toolRow, shootingRow: shootingRow, album: album, flip: flip,
                        shutter: shutter, hint: hint, bodyMenu: bodyMenu, pictureBelow: pictureBelow)
        made.above = over
        made.below = under
        // (No block where the camera or the overlay would be in it: the
        // deck turned the other way up keeps the rows, which step aside.)
        let block = CGRect(x: Double(main.minX), y: rowsTop, width: Double(main.width), height: max(0, Double(area.maxY) - rowsTop))
        if !pictureBelow, viewfinder.width > 0, !blockers.contains(where: { $0.intersects(block) }) { made.keys = block }
        return made
    }

    /// The picture (the upper screen's 5:3, or the shape the cover's camera
    /// is set to: `aspect`, width over height) in a 6-point bezel, as large
    /// as fits in `r`. A square or an upright one stands in the middle of
    /// the width.
    static func fitPicture(in r: CGRect, alignBottom: Bool, aspect: Double = 5.0 / 3) -> CGRect {
        guard r.width > 24, r.height > 24, aspect > 0 else { return .zero }
        let screen = abs(aspect - 5.0 / 3) < 1e-9
        var width = r.width, height = screen ? (width - 12) * 3 / 5 + 12 : (width - 12) / aspect + 12
        if height > r.height { height = r.height; width = screen ? (height - 12) * 5 / 3 + 12 : (height - 12) * aspect + 12 }
        let x = aspect < 1.3 ? r.minX + (r.width - width) / 2 : r.minX
        return CGRect(x: x, y: alignBottom ? r.maxY - height : r.minY, width: width, height: height)
    }
    /// The free stretches of a column with `taken` ranges out, top to bottom.
    static func free(_ column: CGRect, _ taken: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var stretches = [Double(column.minY)...Double(column.maxY)]
        for t in taken {
            stretches = stretches.flatMap { s -> [ClosedRange<Double>] in
                guard t.upperBound > s.lowerBound, t.lowerBound < s.upperBound else { return [s] }
                var parts: [ClosedRange<Double>] = []
                if t.lowerBound > s.lowerBound { parts.append(s.lowerBound...t.lowerBound) }
                if t.upperBound < s.upperBound { parts.append(t.upperBound...s.upperBound) }
                return parts
            }
        }
        return stretches
    }
    /// The top of a `size` that fits in one of the stretches with its middle
    /// as near `target` as it can be; nil when none holds it.
    static func place(_ size: Double, near target: Double, in stretches: [ClosedRange<Double>]) -> Double? {
        var best: (top: Double, distance: Double)?
        for s in stretches where s.upperBound - s.lowerBound >= size {
            let top = min(max(target - size / 2, s.lowerBound), s.upperBound - size)
            let distance = abs(top + size / 2 - target)
            if best == nil || distance < best!.distance { best = (top, distance) }
        }
        return best?.top
    }
}

/// Stood half open like a tent the cover is held clockwise (hinge up); the
/// cover faces the people in the picture. The picture as large as fits, a
/// line of words over it, the controls along the bottom — the edge on the
/// table, the steady one (touches near the hinge would tip the console) —
/// clear of the camera, which sits in the bottom-right corner.
struct CoverTentLayout: Equatable {
    var canvas: CGSize
    var keepOut: [CGRect]
    var header: CGRect
    var picture: CGRect
    var bar: CGRect
    /// The camera, for 「看这里」 while counting down.
    var camera: CGRect?

    static func calculate(canvas: CGSize, safe: ViewportInsets = ViewportInsets(), cameras: [CGRect]) -> Self {
        let w = max(0, canvas.width), h = max(0, canvas.height), m = CoverDeckLayout.margin
        let area = CGRect(x: max(0, safe.leading) + m, y: max(0, safe.top) + 8,
                          width: max(0, w - max(0, safe.leading) - max(0, safe.trailing) - 2 * m),
                          height: max(0, h - max(0, safe.top) - max(0, safe.bottom) - 8 - m))
        let real = cameras.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        let keep = real.map { $0.insetBy(dx: -8, dy: -8) }
        var bar = CGRect(x: area.minX, y: area.maxY - (CoverDeckLayout.target + 8), width: area.width, height: CoverDeckLayout.target + 8)
        for k in keep where k.intersects(bar) {
            if k.midX >= bar.midX { bar.size.width = max(0, k.minX - 8 - bar.minX) }
            else { bar = CGRect(x: k.maxX + 8, y: bar.minY, width: max(0, bar.maxX - k.maxX - 8), height: bar.height) }
        }
        let header = CGRect(x: area.minX, y: area.minY, width: area.width, height: 26)
        let space = CGRect(x: area.minX, y: header.maxY + 4, width: area.width, height: max(0, bar.minY - 8 - header.maxY - 4))
        var picture = CoverDeckLayout.fitPicture(in: space, alignBottom: false)
        picture.origin.x = space.midX - picture.width / 2
        for _ in 0..<4 {
            guard let k = keep.first(where: { $0.intersects(picture) }) else { break }
            // Smaller about its middle (still 5:3) until it clears the camera.
            let overlap = picture.intersection(k)
            let cut = min(overlap.width * 3 / 5, overlap.height) + 1
            picture = picture.insetBy(dx: cut * 5 / 3, dy: cut)
        }
        return Self(canvas: canvas, keepOut: keep, header: header, picture: picture, bar: bar, camera: real.first)
    }
}

/// A game started from
/// the library on the iPhone Duo's cover plays there (PlayView.playsOnCover),
/// laid out after the console's own lower half — the shoulder keys at the
/// top corners beside the touch screen, START and SELECT small at the
/// side, the thumbs' controls in a band at the foot: the Circle Pad and the
/// cross for the left thumb, A B X Y for the right, HOME between them.
/// The two screens take the rest, as large as fits (5:3 over 4:3, 6 points
/// apart). Only the camera itself is kept clear (the region the system
/// reserves for it, or the hardware's estimate): the cover's safe area runs
/// its whole right edge 84 points in for that corner (a device trace), and
/// following it would give up a sixth of the width to a 37-point lens. The
/// foot keeps clear of the home indicator. Keys at least 44 points (HIG).
struct CoverPlayLayout: Equatable {
    var size: CGSize
    var upper: CGRect
    var lower: CGRect
    /// Beside the touch screen: L, ZL, SELECT on the left; R, ZR, the C
    /// Stick, START on the right.
    var leftColumn: CGRect
    var rightColumn: CGRect
    /// Under the screens, for the thumbs.
    var band: CGRect
    var key: Double
    var cross: Double
    var pad: Double
    /// The screens' scale against the console's own (400 × 240, 320 × 240).
    var scale: Double { upper.width / 400 }

    static let margin = 10.0
    /// 手柄样式 大按键: A B X Y this much larger (HOME narrower, so
    /// the Circle Pad and the cross keep their size).
    static let largerKeys = 1.18
    static func calculate(size: CGSize, bottom: Double, cameras: [CGRect], keys: Double = 1) -> Self {
        let w = max(0, size.width), h = max(0, size.height), m = margin
        let inner = max(0, w - 2 * m)
        let key = min(52, max(44, inner * 0.1)) * max(1, keys)
        let cluster = key * 3.05
        // The Circle Pad and the cross share what HOME (90; 70 with the
        // larger keys) and A B X Y leave.
        let home = keys > 1 ? 70.0 : 90.0
        let cross = min(120 * max(1, keys), max(76, (inner - home - cluster - 12) / 2))
        let pad = cross
        let bandHeight = max(cluster, cross) + 8
        let band = CGRect(x: m, y: max(0, h - max(0, bottom) - 6 - bandHeight), width: inner, height: bandHeight)
        // The camera itself: the smallest region reported near the top (or
        // the estimate), with a few points round it.
        let real = cameras.filter { !$0.isNull && $0.width > 0 && $0.height > 0 && $0.minY < h * 0.3 }
        let lens = (real.min { $0.width * $0.height < $1.width * $1.height } ?? CoverHardware.duo.fitted(to: size).camera).insetBy(dx: -4, dy: -4)
        let stack = 480.0, gap = 6.0, toBand = 8.0
        func upperRect(scale: Double, top: Double) -> CGRect {
            CGRect(x: (w - 400 * scale) / 2, y: top, width: 400 * scale, height: 240 * scale)
        }
        // Either the screens start at the top and stay narrow enough to pass
        // beside the lens, or they start under it: the larger of the two —
        // and narrow enough to leave L and R (66 points) room on either side
        // of the touch screen. Any height left over goes above and below the
        // two, evenly.
        let underTop = lens.maxY + 2
        let fromUnder = max(0, (band.minY - toBand - gap - underTop) / stack)
        var fromTop = max(0, (band.minY - toBand - gap - m) / stack)
        let beside = (2 * (lens.minX - 2) - w) / 400
        if upperRect(scale: fromTop, top: m).intersects(lens) { fromTop = min(fromTop, max(0, beside)) }
        let useTop = fromTop >= fromUnder
        let columns = max(0, (w - 2 * (66 + 2 * m) - 0.5) / 320)
        let scale = min(1.2, columns, useTop ? fromTop : fromUnder)
        let top = useTop ? m : underTop
        let spare = max(0, band.minY - toBand - top - (stack * scale + gap))
        let upper = upperRect(scale: scale, top: top + spare / 2)
        let lower = CGRect(x: (w - 320 * scale) / 2, y: upper.maxY + gap, width: 320 * scale, height: 240 * scale)
        let leftColumn = CGRect(x: m, y: lower.minY, width: max(0, lower.minX - 2 * m), height: lower.height)
        let rightColumn = CGRect(x: lower.maxX + m, y: lower.minY, width: max(0, w - m - lower.maxX - m), height: lower.height)
        return Self(size: size, upper: upper, lower: lower, leftColumn: leftColumn, rightColumn: rightColumn,
                    band: band, key: key, cross: cross, pad: pad)
    }
}

/// 11-07 (held across, the screens lay over the
/// crease, L ZL and ZR R sat at two heights, the right side was crowded at
/// the foot): 手柄模式 on the iPhone Duo's inner display held like a book (951
/// × 669, the 41-point crease down the middle) and half folded (flat: AcrossPlayLayout). Each screen on a page of its
/// own — the upper screen on the left page, the touch screen on the right,
/// the same height, each in the middle of its page — and nothing on the
/// crease. Under them the controls, level row by row on both pages: L ZL
/// and ZR R at the outer edges with the volume and the 3D slider by the
/// crease (VOL on the left page, 3D on the right); the Circle Pad level with A B X Y (the C Stick at its upper
/// left); the cross level with START over SELECT; at the foot, by the
/// crease, the microphone and POWER on the left page, HOME on the right.
struct BookPlayLayout: Equatable {
    /// The keys' sizes: 经典 as the across layout has them; 手柄 and 圆润 a
    /// little larger, with the gamepad's wider shoulder keys.
    struct Sizes: Equatable {
        var key: Double
        var pad: Double
        var cross: Double
        /// L and R (at the edges); ZL and ZR (inside them).
        var shoulder: CGSize
        var innerShoulder: CGSize
        static let classic = Sizes(key: 64, pad: 118, cross: 140, shoulder: CGSize(width: 66, height: 40), innerShoulder: CGSize(width: 66, height: 40))
        static let gamepad = Sizes(key: 68, pad: 126, cross: 144, shoulder: CGSize(width: 100, height: 38), innerShoulder: CGSize(width: 80, height: 34))
    }
    var size: CGSize
    var fold: CGRect
    var upper: CGRect
    var lower: CGRect
    var l: CGRect
    var zl: CGRect
    var zr: CGRect
    var r: CGRect
    /// The 3D slider and the volume, as drawn (at 0.82).
    var depth: CGRect
    var volume: CGRect
    var pad: CGRect
    var cross: CGRect
    var cStick: CGRect
    var abxy: CGRect
    /// START over SELECT.
    var startSelect: CGRect
    var mic: CGRect
    var power: CGRect
    var home: CGRect
    var key: Double

    static let margin = 14.0
    /// From the crease band to the nearest key.
    static let toFold = 16.0
    static let gap = 12.0
    static let slider = CGSize(width: 41, height: 89)
    /// Every control, named (for the checks: none on the crease, none over another).
    var controls: [(String, CGRect)] {
        [("L", l), ("ZL", zl), ("ZR", zr), ("R", r), ("3D", depth), ("VOL", volume), ("Circle Pad", pad), ("cross", cross),
         ("C Stick", cStick), ("A B X Y", abxy), ("START SELECT", startSelect), ("MIC", mic), ("POWER", power), ("HOME", home)]
    }

    static func calculate(size: CGSize, fold: CGRect, top: Double = 0, bottom: Double = 0,
                          leading: Double = 0, trailing: Double = 0, sizes: Sizes = .classic) -> Self {
        let m = margin, g = gap
        let height = max(0, size.height - top - bottom)
        let left = CGRect(x: leading, y: top, width: max(0, fold.minX - leading), height: height)
        let right = CGRect(x: fold.maxX, y: top, width: max(0, size.width - trailing - fold.maxX), height: height)
        let foot = left.maxY - 8
        let cluster = sizes.key * 3.05
        // From the foot up: the cross; the Circle Pad over it, A B X Y level
        // with the Circle Pad; the shoulder keys over the taller of the two.
        let cross = CGRect(x: left.minX + m + 8, y: foot - sizes.cross, width: sizes.cross, height: sizes.cross)
        let middle = cross.minY - g - sizes.pad / 2
        let pad = CGRect(x: left.minX + m, y: middle - sizes.pad / 2, width: sizes.pad, height: sizes.pad)
        let abxy = CGRect(x: right.maxX - m - cluster, y: middle - cluster / 2, width: cluster, height: cluster)
        let row = max(sizes.shoulder.height, sizes.innerShoulder.height)
        let shoulders = min(pad.minY, abxy.minY) - g - row
        // The screens: the same height, as large as the pages and the room
        // over the shoulder keys allow, each in the middle of its page, a
        // little further from the edges than the keys (the display's
        // rounded corners).
        let screenTop = top + 16, aside = 26.0
        let screen = max(0, min((left.width - 2 * aside) * 0.6, (right.width - 2 * aside) * 0.75, shoulders - g - screenTop))
        let upper = CGRect(x: left.midX - screen / 0.6 / 2, y: screenTop, width: screen / 0.6, height: screen)
        let lower = CGRect(x: right.midX - screen / 0.75 / 2, y: screenTop, width: screen / 0.75, height: screen)
        func inRow(_ s: CGSize, x: Double) -> CGRect { CGRect(x: x, y: shoulders + (row - s.height) / 2, width: s.width, height: s.height) }
        let l = inRow(sizes.shoulder, x: left.minX + m)
        let zl = inRow(sizes.innerShoulder, x: l.maxX + 8)
        let r = inRow(sizes.shoulder, x: right.maxX - m - sizes.shoulder.width)
        let zr = inRow(sizes.innerShoulder, x: r.minX - 8 - sizes.innerShoulder.width)
        // 11-07: the volume on the left page, the
        // 3D slider on the right, as they read on the console (VOL to the
        // left of the upper screen, 3D to its right).
        let volume = CGRect(x: fold.minX - toFold - slider.width, y: shoulders, width: slider.width, height: slider.height)
        let depth = CGRect(x: fold.maxX + toFold, y: shoulders, width: slider.width, height: slider.height)
        let cStick = CGRect(x: abxy.minX - 6, y: abxy.minY - 4, width: 40, height: 40)
        let startSelect = CGRect(x: abxy.midX - 56, y: max(abxy.maxY + 4, cross.midY - 37), width: 112, height: 74)
        let power = CGRect(x: fold.minX - toFold - 48, y: foot - 34, width: 48, height: 34)
        let mic = CGRect(x: power.minX - 8 - 64, y: foot - 32, width: 64, height: 30)
        let home = CGRect(x: fold.maxX + toFold, y: foot - 56, width: 90, height: 56)
        return Self(size: size, fold: fold, upper: upper, lower: lower, l: l, zl: zl, zr: zr, r: r, depth: depth, volume: volume,
                    pad: pad, cross: cross, cStick: cStick, abxy: abxy, startSelect: startSelect, mic: mic, power: power, home: home,
                    key: sizes.key)
    }
}

/// 11-07: 手柄模式 经典 held across as it was — the screens one over
/// the other in the middle, the keys either side — now even: the screens in
/// the middle of the display; the two columns as wide as each other and as
/// far from the edges, each key in the middle of its column; their rows
/// level — L ZL with ZR R, the Circle Pad with A B X Y (the C Stick at its
/// upper left), the cross with START over SELECT and HOME; the microphone
/// and POWER under them. Where the display is too low for the rows (a phone
/// on its side) `fits` is false and the layout before stays.
struct AcrossPlayLayout: Equatable {
    var size: CGSize
    var upper: CGRect
    var lower: CGRect
    var l: CGRect
    var zl: CGRect
    var zr: CGRect
    var r: CGRect
    var pad: CGRect
    var cross: CGRect
    var cStick: CGRect
    var abxy: CGRect
    /// START over SELECT.
    var startSelect: CGRect
    var home: CGRect
    var mic: CGRect
    var power: CGRect
    var key: Double
    var fits: Bool
    /// How far the volume and 3D sliders reach past the upper screen's sides.
    static let sliderReach = 34.0
    var controls: [(String, CGRect)] {
        [("L", l), ("ZL", zl), ("ZR", zr), ("R", r), ("Circle Pad", pad), ("cross", cross), ("C Stick", cStick), ("A B X Y", abxy),
         ("START SELECT", startSelect), ("HOME", home), ("MIC", mic), ("POWER", power)]
    }

    static func calculate(size: CGSize, top: Double = 0, bottom: Double = 0, leading: Double = 0, trailing: Double = 0) -> Self {
        let uw = max(0, size.width - leading - trailing), uh = max(0, size.height - top - bottom)
        // The sizes the layout before had.
        let screen = max(0, min(uw * 0.46, (uh - 12) / 1.2))
        let key = min(64, uh * 0.16), cross = min(140, uh * 0.36), pad = min(118, uh * 0.3)
        let cluster = key * 3.05
        let x0 = leading + 16, x1 = size.width - trailing - 16
        let y0 = top + 8, y1 = size.height - bottom - 8
        let middle = leading + uw / 2
        let stack = screen * 1.2 + 8
        let upper = CGRect(x: middle - screen / 2, y: y0 + max(0, (y1 - y0 - stack) / 2), width: screen, height: screen * 0.6)
        let lower = CGRect(x: middle - screen * 0.4, y: upper.maxY + 8, width: screen * 0.8, height: screen * 0.6)
        // START / SELECT and HOME side by side; the columns as wide as the
        // wider needs.
        let small = 100.0, homeWidth = 84.0, gap = 10.0
        let row = small + gap + homeWidth
        let column = max(140, cluster, row, 64 + 14 + 48)
        let left = x0 + column / 2, right = x1 - column / 2
        let second = max(pad, cluster), third = max(cross, 74)
        let block = 40 + 12 + second + 12 + third + 12 + 34
        let blockTop = y0 + max(0, (y1 - y0 - block) / 2)
        let secondMid = blockTop + 52 + second / 2
        let thirdMid = blockTop + 52 + second + 12 + third / 2
        let footMid = blockTop + block - 17
        func shoulder(_ x: Double) -> CGRect { CGRect(x: x, y: blockTop, width: 66, height: 40) }
        let abxy = CGRect(x: right - cluster / 2, y: secondMid - cluster / 2, width: cluster, height: cluster)
        let startSelect = CGRect(x: right - row / 2, y: thirdMid - 37, width: small, height: 74)
        let mic = CGRect(x: right - 63, y: footMid - 15, width: 64, height: 30)
        // Over Y, left of X: a little in from the frame's corner (b74's
        // render had it close by the 3D slider).
        let cStick = CGRect(x: abxy.minX + 8, y: abxy.minY - 4, width: 40, height: 40)
        // Both columns clear of the screens and the sliders beside them.
        let leftEdge = left + max(70, pad / 2, cross / 2)
        let rightEdge = min(cStick.minX, startSelect.minX, right - 70, mic.minX)
        let fits = block <= y1 - y0 && stack <= y1 - y0
            && leftEdge <= upper.minX - sliderReach && upper.maxX + sliderReach <= rightEdge
        return Self(size: size, upper: upper, lower: lower,
                    l: shoulder(left - 70), zl: shoulder(left + 4), zr: shoulder(right - 70), r: shoulder(right + 4),
                    pad: CGRect(x: left - pad / 2, y: secondMid - pad / 2, width: pad, height: pad),
                    cross: CGRect(x: left - cross / 2, y: thirdMid - cross / 2, width: cross, height: cross),
                    cStick: cStick, abxy: abxy, startSelect: startSelect,
                    home: CGRect(x: startSelect.maxX + gap, y: thirdMid - 28, width: homeWidth, height: 56),
                    mic: mic, power: CGRect(x: mic.maxX + 14, y: footMid - 17, width: 48, height: 34),
                    key: key, fits: fits)
    }
}

/// 11-07 (the same, for 手柄 and 圆润 held across): in their columns the
/// Circle Pad level with A B X Y (the C Stick over its left side), the
/// cross under the Circle Pad; the two together in the middle of the room
/// between the shoulder keys and the foot (the microphone, POWER). Nil
/// where they cannot be level (a phone on its side): the columns as before.
struct GamepadRows: Equatable {
    /// From the column's top: the room over the Circle Pad, over the C Stick.
    var overPad: Double
    var overStick: Double
    /// The Circle Pad's and A B X Y's middle.
    var middle: Double
    static let shoulders = 38.0, foot = 34.0, gap = 10.0, stick = 40.0
    static func calculate(height: Double, pad: Double, cross: Double, cluster: Double) -> Self? {
        let top = shoulders + gap, bottom = height - foot - gap
        let lowest = max(top + pad / 2, top + stick + gap + cluster / 2)
        let highest = min(bottom - pad / 2 - gap - cross, bottom - cluster / 2)
        guard lowest <= highest else { return nil }
        let below = max(pad / 2 + gap + cross, cluster / 2), above = max(pad / 2, cluster / 2 + gap + stick)
        let middle = min(highest, max(lowest, (top + bottom) / 2 - (below - above) / 2))
        return Self(overPad: middle - pad / 2 - shoulders, overStick: middle - cluster / 2 - gap - stick - shoulders, middle: middle)
    }
}

/// 11-06 (真机): which of the iPhone Duo's screens is which, from what the
/// hinge has taught (sizes in pixels, `UIScreen.nativeBounds`). The Duo puts
/// the window on three: the cover (1398 × 2034), the inner display (2007 ×
/// 2853) and, with the lid part open, half of the inner display (1407 ×
/// 2007), a little smaller than the cover. There is one cover; once it is
/// known every other screen is the inner display. The cover is learned where
/// the window stays while the hinge is closed, the inner display where it
/// stays while the hinge is fully open (a wrong guess mends itself then);
/// a screen with a side as long as one of the inner display's is a part of
/// it. Kept by CoverOrientationPolicy.KnownDisplays.
/// 11-19: the inner display is the largest of the three, and its half has
/// a side of its: a smaller screen with no side of the inner display's is
/// never taken for it (11-17 on the device: the lid shut over the app in
/// the background, the hinge saying "fully open" a quarter of an hour later
/// with the window still on the cover — the cover went among the inner
/// display's sizes, and from there it could not be learned as the cover
/// again). A book kept from before that has it so is mended (`mend`).
struct DisplayRoleBook: Equatable {
    var cover: CGSize?
    var inner: [CGSize] = []

    static func sharesSide(_ a: CGSize, _ b: CGSize) -> Bool {
        [a.width, a.height].contains { side in abs(side - b.width) < 1 || abs(side - b.height) < 1 }
    }
    static func area(_ size: CGSize) -> Double { size.width * size.height }

    /// true = the cover, false = the inner display (whole or half), nil = not known.
    func role(of size: CGSize) -> Bool? {
        if let cover { return cover == size }
        if inner.contains(size) || inner.contains(where: { Self.sharesSide(size, $0) }) { return false }
        return nil
    }
    /// What the hinge says of the screen the window has stayed on; true if
    /// anything changed.
    @discardableResult mutating func learn(_ size: CGSize, outer: Bool) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let mended = mend()
        if outer {
            // Never a size known as the inner display or a part of it (the
            // whole inner display shares a side with its half), nor, in
            // place of the cover known, one much larger than that.
            guard cover != size, !inner.contains(where: { $0 == size || Self.sharesSide(size, $0) }),
                  cover.map({ Self.area(size) < Self.area($0) * 1.1 }) ?? true else { return mended }
            cover = size
        } else {
            guard !inner.contains(size) else { return mended }
            // Smaller than what is known of the inner display and with no
            // side of it: not the inner display, whatever the hinge says.
            if let largest = inner.map(Self.area).max(), Self.area(size) < largest, !inner.contains(where: { Self.sharesSide(size, $0) }) { return mended }
            if cover == size { cover = nil }
            inner.append(size)
            mend()
        }
        return true
    }
    /// What cannot be is forgotten, to be learned again: a size among the
    /// inner display's that is smaller than the largest there and has no
    /// side of it. true if anything was taken out.
    @discardableResult mutating func mend() -> Bool {
        guard let whole = inner.max(by: { Self.area($0) < Self.area($1) }) else { return false }
        let kept = inner.filter { $0 == whole || Self.sharesSide($0, whole) }
        guard kept.count != inner.count else { return false }
        inner = kept
        return true
    }
}

extension FoldPlacement {
    /// The handheld on the iPhone Duo's inner display (DuoConsoleView): laid out by the fold and the safe area,
    /// never by the occlusions the device reports. There the only one is the inner camera's patch, blacked out
    /// while a camera or the microphone is on (the system's privacy light); laid out by it, the whole console
    /// shrank about 10% and slid left (b56; again on 11-15, with the films listening for a breath).
    static func handheld(size: CGSize, insets: ViewportInsets = .init(), snapshot: FoldRegionSnapshot) -> Self {
        var steady = snapshot
        steady.occlusions = []
        return immersive(size: size, insets: insets, snapshot: steady)
    }
}
