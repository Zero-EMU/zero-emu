import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import ImageIO
import Vision
#if os(iOS)
import AVFoundation
import CoreMotion
import Photos
import UIKit
#endif

// The console's camera (round 25): the iPhone's cameras seen through a
// handheld's camera module. The inner camera is the one over the upper
// screen, facing the player (the iPhone's front camera); the outer cameras
// look out of the lid (the iPhone's back camera; the handheld has two there
// for 3D pictures, the iPhone gives one picture, so FoldArc's are 2D).
//
// What the module does to a picture is FoldArc's own reading of how such a
// camera looks: a VGA picture (640 × 480), a little soft and sharpened back,
// flat colours, lifted shadows, highlights quick to burn out, grain that
// moves; the upper screen shows the middle 5:3 of it at the LCD's 400 × 240.
// The lenses (普通、闪闪、合体、白日梦、暗处、针孔、不可思议) follow what the
// handheld's camera offers; how each looks is FoldArc's. No picture, sound
// or mark of the handheld's is used. The pictures go where a handheld puts
// them: the SD card's DCIM folder (the emulated SD card, Azahar/sdmc).

/// Which cameras face the person looking at the display FoldArc is
/// on and which face away — iOS 27.1's direction map for iPhone Duo
/// (AVKit's AVCaptureDeviceDirectionCoordinator, read where the capture keys
/// are heard, CaptureKeyCatcher). Empty until the map has come (any other
/// iPhone, the Simulator, iOS before 27.1): the cameras' positions decide.
final class CameraDirections: @unchecked Sendable {
    static let shared = CameraDirections()
    private let lock = NSLock()
    private var forward: [String] = []
    private var backward: [String] = []
    /// Posted when the map changes (the feeds look again at their camera).
    static let changed = Notification.Name("FoldArc.camera.directions")
    /// Unique IDs, best first (see `CameraFeed.device(for:)`).
    func update(forward: [String], backward: [String]) {
        lock.lock()
        let changed = forward != self.forward || backward != self.backward
        self.forward = forward; self.backward = backward
        lock.unlock()
        if changed { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }
    func uniqueIDs(facing side: CameraSide) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return side == .inner ? forward : backward
    }
    /// Whether a camera faces the person looking at the display; nil when the
    /// map does not list it.
    func isForward(_ uniqueID: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        if forward.contains(uniqueID) { return true }
        if backward.contains(uniqueID) { return false }
        return nil
    }
}

/// 11-06 (after a restart the iPhone's
/// own Camera shows a picture, FoldArc's stays black): what FoldArc does
/// differently, one thing at a time, from a DEBUG build's launch arguments.
/// A release build does none of them.
enum CameraTry {
    #if DEBUG
    private static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }
    #else
    private static func has(_ flag: String) -> Bool { false }
    #endif
    /// Frames as 4:2:0 YUV (what the iPhone's camera makes), not BGRA.
    static var yuv: Bool { has("--foldarc-camera-420") }
    /// No Camera Control menu, no cover picture for the people taken, no
    /// rotation coordinator: the session and its one output only.
    static var plain: Bool { has("--foldarc-camera-plain") || bare }
    /// Plain, and no capture keys and no direction map either (AVKit's
    /// AVCaptureEventInteraction and AVCaptureDeviceDirectionCoordinator):
    /// the cameras FoldArc falls back to (内侧 the Virtual Front Camera).
    static var bare: Bool { has("--foldarc-camera-bare") }
    /// 1080p, the inner camera's own size (no scaling in the camera).
    static var hd1080: Bool { has("--foldarc-camera-1080") }
    /// 内侧 through the Virtual Front Camera (the front camera of the display in use).
    static var virtualFront: Bool { has("--foldarc-camera-virtual-front") }
    /// The status bar and the home indicator left showing (the console and
    /// the camera hide them).
    static var overlays: Bool { has("--foldarc-camera-overlays") }
    static var summary: String {
        [yuv ? "420" : nil, bare ? "bare" : plain ? "plain" : nil, hd1080 ? "1080p" : nil, virtualFront ? "virtual front" : nil, overlays ? "overlays" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Which camera.
enum CameraSide: String, Sendable {
    case inner, outer
    var title: String { self == .inner ? String(localized: "内侧相机") : String(localized: "外侧相机") }
    var short: String { self == .inner ? String(localized: "内侧") : String(localized: "外侧") }
    var other: CameraSide { self == .inner ? .outer : .inner }
}

/// The camera's lenses (camera modes).
enum CameraLens: String, CaseIterable, Identifiable, Sendable {
    case normal, sparkle, merge, dream, lowLight, pinhole, mystery, pair, quad
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: return String(localized: "普通")
        case .sparkle: return String(localized: "闪闪")
        case .merge: return String(localized: "合体")
        case .dream: return String(localized: "白日梦")
        case .lowLight: return String(localized: "暗处")
        case .pinhole: return String(localized: "针孔")
        case .mystery: return String(localized: "不可思议")
        case .pair: return String(localized: "两联")
        case .quad: return String(localized: "四连拍")
        }
    }
    var symbol: String {
        switch self {
        case .normal: return "camera"
        case .sparkle: return "sparkles"
        case .merge: return "person.2.fill"
        case .dream: return "ellipsis.bubble.fill"
        case .lowLight: return "moon.fill"
        case .pinhole: return "circle.dashed"
        case .mystery: return "questionmark.circle.fill"
        case .pair: return "rectangle.split.2x1"
        case .quad: return "square.grid.2x2"
        }
    }
    var blurb: String {
        switch self {
        case .normal: return String(localized: "普通地拍")
        case .sparkle: return String(localized: "对着 iPhone 吹气（或者按住掌机的 MIC），画面里飘出星星、爱心、音符和泡泡")
        case .merge: return String(localized: "外侧相机拍对面的人，内侧相机拍自己，两张脸合成一张")
        case .dream: return String(localized: "柔光、泛白，像在梦里")
        case .lowLight: return String(localized: "暗的地方用：画面亮一些，颗粒更粗，动的东西会拖影")
        case .pinhole: return String(localized: "中间亮、四周暗，像针孔相机拍的")
        case .mystery: return String(localized: "拍下来之前，不知道会变成什么颜色")
        case .pair: return String(localized: "按两次：两张竖着的半格，并排成一张")
        case .quad: return String(localized: "按四次：四张拼在一张相纸上")
        }
    }
    /// 不可思议 decides its finish only when the picture is taken: nothing
    /// of it can be adjusted (as on the handheld).
    var adjustable: Bool { self != .mystery }
    /// 两联 and 四连拍: how many pictures make the one that is kept (1 for
    /// every other lens).
    var sheetCount: Int { self == .pair ? 2 : (self == .quad ? 4 : 1) }
}

/// The film of 手动调整.
enum CameraFilm: String, CaseIterable, Codable, Sendable {
    case color, sepia, mono
    var title: String {
        switch self {
        case .color: return String(localized: "彩色")
        case .sepia: return String(localized: "棕褐")
        case .mono: return String(localized: "黑白")
        }
    }
}

/// 手动调整 for one lens: the film, and brightness, contrast and
/// sharpness from −2 to +2.
struct CameraManual: Codable, Equatable, Sendable {
    var film = CameraFilm.color
    var brightness = 0
    var contrast = 0
    var sharpness = 0
    var isDefault: Bool { self == CameraManual() }
}

/// 11-06 (外屏): an old compact camera's shooting settings, for every lens —
/// exposure compensation, white balance, ISO, the flash, the date printed
/// on the picture. A white-balance preset is what it was on those cameras:
/// set for the wrong light, the picture takes that colour.
struct CameraShooting: Codable, Equatable, Sendable {
    /// EV, −2…+2 in halves.
    var exposure = 0.0
    var whiteBalance = CameraWhiteBalance.auto
    var iso = CameraISO.auto
    var flash = CameraFlashMode.off
    var dateStamp = false
    var isDefault: Bool { self == CameraShooting() }
    static let defaultsKey = "FoldArc.camera.shooting"
    static func stored(_ defaults: UserDefaults = .standard) -> CameraShooting {
        guard let data = defaults.data(forKey: defaultsKey), let value = try? JSONDecoder().decode(CameraShooting.self, from: data) else { return CameraShooting() }
        return value
    }
    func store(_ defaults: UserDefaults = .standard) {
        if isDefault { defaults.removeObject(forKey: Self.defaultsKey) }
        else if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
    var exposureTitle: String { exposure == 0 ? "±0" : String(format: "%+.1f", exposure) }
    /// The viewfinder's chip: what is not the default.
    var summary: String {
        var parts: [String] = []
        if exposure != 0 { parts.append(exposureTitle) }
        if iso != .auto { parts.append("ISO \(iso.rawValue)") }
        if whiteBalance != .auto { parts.append(whiteBalance.title) }
        if flash != .off { parts.append(flash == .redEye ? String(localized: "防红眼") : String(localized: "闪光\(flash.title)")) }
        if dateStamp { parts.append(String(localized: "日期")) }
        return parts.joined(separator: " · ")
    }
}
enum CameraWhiteBalance: String, CaseIterable, Codable, Sendable {
    case auto, daylight, cloudy, tungsten, fluorescent
    var title: String {
        switch self {
        case .auto: return String(localized: "自动")
        case .daylight: return String(localized: "日光")
        case .cloudy: return String(localized: "阴天")
        case .tungsten: return String(localized: "白炽灯")
        case .fluorescent: return String(localized: "荧光灯")
        }
    }
    var symbol: String {
        switch self {
        case .auto: return "a.circle"
        case .daylight: return "sun.max"
        case .cloudy: return "cloud"
        case .tungsten: return "lightbulb"
        case .fluorescent: return "line.3.horizontal"
        }
    }
    /// The picture is already balanced by the module: a preset moves it the
    /// way a camera set for that light moves daylight (白炽灯 blue, 阴天 warm).
    var gains: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .auto: return (1, 1, 1)
        case .daylight: return (1.02, 1.0, 0.97)
        case .cloudy: return (1.08, 1.0, 0.88)
        case .tungsten: return (0.82, 0.95, 1.22)
        case .fluorescent: return (0.97, 0.9, 1.08)
        }
    }
}
enum CameraISO: Int, CaseIterable, Codable, Sendable {
    case auto = 0, iso100 = 100, iso200 = 200, iso400 = 400, iso800 = 800, iso1600 = 1600
    var title: String { self == .auto ? String(localized: "自动") : "\(rawValue)" }
    /// What the sensitivity does: brighter, and noisier and duller.
    var gainEV: Float {
        switch self { case .auto, .iso200: return 0; case .iso100: return -0.2; case .iso400: return 0.2; case .iso800: return 0.45; case .iso1600: return 0.7 }
    }
    var noise: Double {
        switch self { case .auto, .iso100: return 0; case .iso200: return 0.015; case .iso400: return 0.04; case .iso800: return 0.07; case .iso1600: return 0.11 }
    }
    var grain: Double {
        switch self { case .auto, .iso100, .iso200: return 0; case .iso400: return 0.02; case .iso800: return 0.04; case .iso1600: return 0.07 }
    }
    var saturation: Float {
        switch self { case .auto, .iso100, .iso200: return 1; case .iso400: return 0.98; case .iso800: return 0.94; case .iso1600: return 0.88 }
    }
}
enum CameraFlashMode: String, CaseIterable, Codable, Sendable {
    case off, auto, on, redEye
    var title: String {
        switch self {
        case .off: return String(localized: "关")
        case .auto: return String(localized: "自动")
        case .on: return String(localized: "开")
        case .redEye: return String(localized: "防红眼")
        }
    }
    var symbol: String {
        switch self {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.a"
        case .on: return "bolt.fill"
        case .redEye: return "eye"
        }
    }
}

/// The self-timer.
enum CameraTimer: Int, CaseIterable, Sendable {
    case off = 0, three = 3, ten = 10
    var title: String { self == .off ? String(localized: "关") : String(localized: "\(rawValue) 秒") }
    var next: CameraTimer { self == .off ? .three : self == .three ? .ten : .off }
}

// MARK: - The camera module's look

enum CameraLook {
    static let photoSize = CGSize(width: 640, height: 480)
    static let photoRect = CGRect(origin: .zero, size: photoSize)
    static let screenSize = CGSize(width: 400, height: 240)
    /// The part of the picture the upper screen shows (its middle 5:3), in
    /// Core Image's coordinates (origin at the bottom).
    static let screenCrop = CGRect(x: 0, y: 48, width: 640, height: 384)
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// The frame as the module sees it: the middle 4:3 of what the iPhone
    /// gives, at 640 × 480.
    static func sensor(_ frame: CIImage, zoom: Double = 1) -> CIImage {
        let extent = frame.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return frame }
        var crop = extent
        if extent.width / extent.height > 4.0 / 3.0 {
            crop.size.width = extent.height * 4 / 3
            crop.origin.x += (extent.width - crop.width) / 2
        } else {
            crop.size.height = extent.width * 3 / 4
            crop.origin.y += (extent.height - crop.height) / 2
        }
        if zoom > 1.001 {
            // Digital zoom (11-06): a smaller middle, brought up to 640 × 480.
            let z = min(4, zoom), w = crop.width / z, h = crop.height / z
            crop = CGRect(x: crop.midX - w / 2, y: crop.midY - h / 2, width: w, height: h)
        }
        let moved = frame.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        return scaled(moved, by: photoSize.width / crop.width).cropped(to: photoRect)
    }

    static func scaled(_ image: CIImage, by scale: Double) -> CIImage {
        guard abs(scale - 1) > 0.0001 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        return filter.outputImage ?? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// What the module itself does: fewer real pixels than it saves and a
    /// small plastic lens (soft), sharpened back in the camera (a light halo
    /// on edges), colours a little flat and cool, the shadows lifted, the
    /// highlights quick to burn out, and grain that moves from frame to frame.
    static func module(_ image: CIImage, grain: Double, seed: Int) -> CIImage {
        let small = scaled(image, by: 0.72)
        let soft = small.transformed(by: CGAffineTransform(scaleX: 1 / 0.72, y: 1 / 0.72)).clampedToExtent().cropped(to: photoRect)
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = soft.clampedToExtent()
        sharpen.radius = 1.7
        sharpen.intensity = 0.6
        let tone = CIFilter.toneCurve()
        tone.inputImage = (sharpen.outputImage ?? soft).cropped(to: photoRect)
        tone.point0 = CGPoint(x: 0, y: 0.045)
        tone.point1 = CGPoint(x: 0.25, y: 0.25)
        tone.point2 = CGPoint(x: 0.5, y: 0.55)
        tone.point3 = CGPoint(x: 0.75, y: 0.86)
        tone.point4 = CGPoint(x: 0.92, y: 1.0)
        let colour = CIFilter.colorControls()
        colour.inputImage = tone.outputImage
        colour.saturation = 0.86
        colour.contrast = 1.0
        colour.brightness = 0
        let cast = CIFilter.colorMatrix()
        cast.inputImage = colour.outputImage
        cast.rVector = CIVector(x: 0.98, y: 0, z: 0, w: 0)
        cast.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
        cast.bVector = CIVector(x: 0, y: 0, z: 1.035, w: 0)
        cast.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        cast.biasVector = CIVector(x: 0, y: 0.004, z: 0.01, w: 0)
        let out = (cast.outputImage ?? image).cropped(to: photoRect)
        return addGrain(out, amount: grain, seed: seed)
    }

    /// The picture a body is given: the module's, or — a body whose
    /// colour is a grade — the camera's own with a little of the sensor's
    /// grain (the grade was fitted on pictures as a camera gives them).
    static func given(_ image: CIImage, plain: Bool, grain: Double, seed: Int) -> CIImage {
        plain ? addGrain(image.cropped(to: photoRect), amount: grain * 0.3, seed: seed) : module(image, grain: grain, seed: seed)
    }
    static func given(_ image: CIImage, body: CameraBody, grain: Double, seed: Int) -> CIImage {
        given(image, plain: body.isPlain, grain: grain, seed: seed)
    }

    /// 11-06: the handheld's own camera module — soft, the fine
    /// detail smeared by the module's noise reduction, then sharpened hard
    /// (light halos along edges); colours that follow the room: warm and a
    /// little olive under indoor lamps (its white balance stops short), a
    /// touch cool in bright light; shadows lifted and muddy, more so in the
    /// dark; highlights that burn out early and glow; blotchy colour noise
    /// that grows as the light goes; the corners a little darker. `mean`:
    /// the scene's brightness (0…1), measured by the feed. The 原生 body's
    /// look; the other bodies keep `module` under their own.
    static func module3DS(_ image: CIImage, grain: Double, seed: Int, mean: Double) -> CIImage {
        let dark = min(1, max(0, (0.42 - mean) / 0.3))
        let bright = min(1, max(0, (mean - 0.5) / 0.25))
        // Fewer real pixels than it saves; the noise reduction's smear.
        let s = 0.62
        var small = scaled(image, by: s)
        let smear = CIFilter.median()
        smear.inputImage = small
        small = (smear.outputImage ?? small).cropped(to: small.extent)
        let soft = small.transformed(by: CGAffineTransform(scaleX: 1 / s, y: 1 / s)).clampedToExtent().cropped(to: photoRect)
        // Sharpened back hard (less in the dark, where it would sharpen noise).
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = soft.clampedToExtent()
        sharpen.radius = 2.2
        sharpen.intensity = Float(0.95 - 0.35 * dark)
        var out = (sharpen.outputImage ?? soft).cropped(to: photoRect)
        let tone = CIFilter.toneCurve()
        tone.inputImage = out
        tone.point0 = CGPoint(x: 0, y: 0.05 + 0.035 * dark)
        tone.point1 = CGPoint(x: 0.25, y: 0.27 + 0.02 * dark)
        tone.point2 = CGPoint(x: 0.5, y: 0.57)
        tone.point3 = CGPoint(x: 0.72, y: 0.87)
        tone.point4 = CGPoint(x: 0.88, y: 1.0)
        out = tone.outputImage ?? out
        let colour = CIFilter.colorControls()
        colour.inputImage = out
        colour.saturation = Float(0.9 - 0.16 * dark)
        colour.contrast = Float(1.0 - 0.07 * dark)
        colour.brightness = 0
        out = colour.outputImage ?? out
        // The white balance that stops short: warm and olive in the dark,
        // a little cool in bright light.
        let cast = CIFilter.colorMatrix()
        cast.inputImage = out
        cast.rVector = CIVector(x: 0.985 + 0.075 * dark - 0.01 * bright, y: 0, z: 0, w: 0)
        cast.gVector = CIVector(x: 0, y: 1.0 + 0.01 * dark, z: 0, w: 0)
        cast.bVector = CIVector(x: 0, y: 0, z: 1.03 - 0.17 * dark + 0.012 * bright, w: 0)
        cast.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        cast.biasVector = CIVector(x: 0.012 * dark, y: 0.004 + 0.008 * dark, z: 0.01 - 0.018 * dark, w: 0)
        out = cast.outputImage ?? out
        // Highlights that glow (lamps, a glass, a window).
        let glow = CIFilter.bloom()
        glow.inputImage = out.clampedToExtent()
        glow.radius = Float(5 + 6 * dark)
        glow.intensity = Float(0.16 + 0.26 * dark)
        out = (glow.outputImage ?? out).cropped(to: photoRect)
        let corners = CIFilter.vignette()
        corners.inputImage = out
        corners.intensity = 0.42
        corners.radius = 1.45
        out = (corners.outputImage ?? out).cropped(to: photoRect)
        out = addBlotches(out, amount: 0.03 + 0.075 * dark, seed: seed)
        return addGrain(out, amount: grain * (1 + 0.8 * dark), seed: seed)
    }

    /// Colour noise in blotches, as a small sensor's comes out of its noise
    /// reduction: noise a sixth of the size, brought up smooth; purple
    /// against green, a different patch each frame.
    static func addBlotches(_ image: CIImage, amount: Double, seed: Int) -> CIImage {
        guard amount > 0, let patch = noisePatch(seed: seed &+ 7, mx: 6007, my: 92_821) else { return image }
        let small = patch.cropped(to: CGRect(x: 0, y: 0, width: 110, height: 84))
        let big = scaled(small, by: 6).clampedToExtent().cropped(to: photoRect)
        let a = CGFloat(amount)
        let tint = CIFilter.colorMatrix()
        tint.inputImage = big
        tint.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: a * 0.6, z: 0, w: 0)
        tint.bVector = CIVector(x: a, y: 0, z: 0, w: 0)
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        tint.biasVector = CIVector(x: -a / 2, y: -a * 0.3, z: -a / 2, w: 0)
        guard let centred = tint.outputImage else { return image }
        return addNoise(centred, to: image)
    }

    /// Grain: a different patch of noise each frame, mostly in brightness,
    /// a little in colour.
    static func addGrain(_ image: CIImage, amount: Double, seed: Int) -> CIImage {
        guard amount > 0, let patch = noisePatch(seed: seed, mx: 7919, my: 104_729) else { return image }
        let a = CGFloat(amount), c = CGFloat(amount * 0.45)
        let noise = CIFilter.colorMatrix()
        noise.inputImage = patch
        // Red of the noise for brightness; green and blue as small colour;
        // centred on 0 (±a/2), opaque.
        noise.rVector = CIVector(x: a, y: c, z: 0, w: 0)
        noise.gVector = CIVector(x: a, y: 0, z: 0, w: 0)
        noise.bVector = CIVector(x: a, y: 0, z: c, w: 0)
        noise.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        noise.biasVector = CIVector(x: -(a + c) / 2, y: -a / 2, z: -(a + c) / 2, w: 0)
        guard let centred = noise.outputImage else { return image }
        return addNoise(centred, to: image)
    }
    /// 11-06: noise as an opaque picture. CIRandomGenerator's four channels
    /// are each random, alpha too, and a colour filter reads its picture as
    /// premultiplied and divides by that alpha: where the alpha was near 0 a
    /// texel came out many times too bright — the white dots, ringed black
    /// by the sharpening, that every body with grain showed. Laid over
    /// opaque black first, the noise keeps its values (0…1) and is opaque.
    static func noisePatch(seed: Int, mx: Int, my: Int) -> CIImage? {
        guard let random = CIFilter.randomGenerator().outputImage else { return nil }
        let dx = Double((seed &* mx) % 2048), dy = Double((seed &* my) % 2048)
        let patch = random.transformed(by: CGAffineTransform(translationX: -dx, y: -dy)).cropped(to: photoRect)
        return patch.composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: photoRect))
    }
    /// Adds an opaque noise picture centred on 0 to `image`: moved to
    /// 0.5 + n/2 and laid on with a linear-light blend (base + 2·blend − 1),
    /// so the two pictures' alphas never add up.
    static func addNoise(_ noise: CIImage, to image: CIImage) -> CIImage {
        let half = CIFilter.colorMatrix()
        half.inputImage = noise
        half.rVector = CIVector(x: 0.5, y: 0, z: 0, w: 0)
        half.gVector = CIVector(x: 0, y: 0.5, z: 0, w: 0)
        half.bVector = CIVector(x: 0, y: 0, z: 0.5, w: 0)
        half.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        half.biasVector = CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0)
        let blend = CIFilter.linearLightBlendMode()
        blend.inputImage = half.outputImage
        blend.backgroundImage = image
        return (blend.outputImage ?? image).cropped(to: photoRect)
    }

    /// The lens's finish, on the module's picture (not 不可思议's, which is
    /// chosen when the picture is taken, nor 闪闪's, drawn over it).
    /// `gain`: 暗处's brightening in stops (the feed measures the scene).
    static func finish(_ image: CIImage, lens: CameraLens, gain: Double = 1.5) -> CIImage {
        switch lens {
        case .dream: return dream(image)
        case .pinhole: return pinhole(image)
        case .lowLight: return lowLight(image, ev: gain)
        case .normal, .sparkle, .merge, .mystery, .pair, .quad: return image
        }
    }

    /// 暗处 brightens a dark scene, not a light one: the stops that bring
    /// the picture's mean brightness up to about 0.45, at most 2.4.
    static func lowLightGain(mean: Double) -> Double {
        min(2.4, max(0, log2(0.45 / max(mean, 0.025))))
    }

    /// 白日梦: a glow round everything light, half of it out of focus,
    /// pale soft colours a little pink, the edges going white.
    static func dream(_ image: CIImage) -> CIImage {
        let bloom = CIFilter.bloom()
        bloom.inputImage = image.clampedToExtent()
        bloom.radius = 12
        bloom.intensity = 0.55
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = 4
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = (bloom.outputImage ?? image).cropped(to: photoRect)
        mix.targetImage = (blur.outputImage ?? image).cropped(to: photoRect)
        mix.time = 0.35
        let pastel = CIFilter.colorControls()
        pastel.inputImage = mix.outputImage
        pastel.saturation = 0.88
        pastel.brightness = 0.025
        pastel.contrast = 0.94
        let pink = CIFilter.colorMatrix()
        pink.inputImage = pastel.outputImage
        pink.rVector = CIVector(x: 1.03, y: 0, z: 0, w: 0)
        pink.gVector = CIVector(x: 0, y: 0.97, z: 0, w: 0)
        pink.bVector = CIVector(x: 0, y: 0, z: 1.02, w: 0)
        pink.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        pink.biasVector = CIVector(x: 0.02, y: 0.004, z: 0.03, w: 0)
        let haze = CIFilter.radialGradient()
        haze.center = CGPoint(x: photoSize.width / 2, y: photoSize.height / 2)
        haze.radius0 = 210
        haze.radius1 = 470
        haze.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        haze.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0.32)
        let screen = CIFilter.screenBlendMode()
        screen.inputImage = haze.outputImage?.cropped(to: photoRect)
        screen.backgroundImage = pink.outputImage
        return (screen.outputImage ?? image).cropped(to: photoRect)
    }

    /// 针孔: the middle lit, the edges dark and a little soft, warm.
    static func pinhole(_ image: CIImage) -> CIImage {
        let centre = CGPoint(x: photoSize.width / 2, y: photoSize.height / 2)
        let lit = CIFilter.exposureAdjust()
        lit.inputImage = image
        lit.ev = 0.35
        let inner = CIFilter.radialGradient()
        inner.center = centre
        inner.radius0 = 40
        inner.radius1 = 230
        inner.color0 = CIColor(red: 1, green: 1, blue: 1)
        inner.color1 = CIColor(red: 0, green: 0, blue: 0)
        let middle = CIFilter.blendWithMask()
        middle.inputImage = lit.outputImage
        middle.backgroundImage = image
        middle.maskImage = inner.outputImage?.cropped(to: photoRect)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = (middle.outputImage ?? image).clampedToExtent()
        blur.radius = 3.5
        let outer = CIFilter.radialGradient()
        outer.center = centre
        outer.radius0 = 160
        outer.radius1 = 340
        outer.color0 = CIColor(red: 0, green: 0, blue: 0)
        outer.color1 = CIColor(red: 1, green: 1, blue: 1)
        let edges = CIFilter.blendWithMask()
        edges.inputImage = blur.outputImage?.cropped(to: photoRect)
        edges.backgroundImage = middle.outputImage
        edges.maskImage = outer.outputImage?.cropped(to: photoRect)
        let vignette = CIFilter.vignetteEffect()
        vignette.inputImage = edges.outputImage
        vignette.center = centre
        vignette.radius = 300
        vignette.intensity = 1.0
        vignette.falloff = 0.55
        let warm = CIFilter.colorMatrix()
        warm.inputImage = vignette.outputImage
        warm.rVector = CIVector(x: 1.06, y: 0, z: 0, w: 0)
        warm.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
        warm.bVector = CIVector(x: 0, y: 0, z: 0.88, w: 0)
        warm.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        warm.biasVector = CIVector(x: 0.01, y: 0, z: 0, w: 0)
        return (warm.outputImage ?? image).cropped(to: photoRect)
    }

    /// 暗处: brighter by `ev` stops, the shadows opened, the colour drained a
    /// little (the grain and the afterimage are the feed's).
    static func lowLight(_ image: CIImage, ev: Double) -> CIImage {
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = Float(ev)
        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = exposure.outputImage
        gamma.power = 0.8
        let colour = CIFilter.colorControls()
        colour.inputImage = gamma.outputImage
        colour.saturation = 0.7
        colour.contrast = 0.94
        colour.brightness = 0
        return (colour.outputImage ?? image).cropped(to: photoRect)
    }

    /// 手动调整: brightness, contrast, sharpness, then the film.
    static func manual(_ image: CIImage, _ m: CameraManual) -> CIImage {
        guard !m.isDefault else { return image }
        var out = image
        if m.brightness != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = out; f.ev = Float(m.brightness) * 0.35
            out = f.outputImage ?? out
        }
        if m.contrast != 0 {
            let f = CIFilter.colorControls(); f.inputImage = out
            f.contrast = 1 + Float(m.contrast) * 0.13; f.saturation = 1; f.brightness = 0
            out = f.outputImage ?? out
        }
        if m.sharpness > 0 {
            let f = CIFilter.unsharpMask(); f.inputImage = out.clampedToExtent(); f.radius = 1.4; f.intensity = Float(m.sharpness) * 0.45
            out = (f.outputImage ?? out).cropped(to: photoRect)
        } else if m.sharpness < 0 {
            let f = CIFilter.gaussianBlur(); f.inputImage = out.clampedToExtent(); f.radius = Float(-m.sharpness) * 0.8
            out = (f.outputImage ?? out).cropped(to: photoRect)
        }
        switch m.film {
        case .color: break
        case .sepia:
            let f = CIFilter.sepiaTone(); f.inputImage = out; f.intensity = 0.85
            out = f.outputImage ?? out
        case .mono:
            let f = CIFilter.photoEffectMono(); f.inputImage = out
            out = f.outputImage ?? out
        }
        return out.cropped(to: photoRect)
    }

    /// The upper screen's picture: the middle 5:3 at 400 × 240.
    /// A part of the picture as the cover's viewfinder shows it (five
    /// eighths of its size, as the upper screen's picture is).
    static let shapedScale = 0.625
    static func shaped(_ photo: CIImage, _ part: CGRect) -> CIImage {
        let moved = photo.cropped(to: part).transformed(by: CGAffineTransform(translationX: -part.minX, y: -part.minY))
        return scaled(moved, by: shapedScale).cropped(to: CGRect(x: 0, y: 0, width: part.width * shapedScale, height: part.height * shapedScale))
    }
    static func screen(_ photo: CIImage) -> CIImage {
        let moved = photo.cropped(to: screenCrop).transformed(by: CGAffineTransform(translationX: 0, y: -screenCrop.minY))
        return scaled(moved, by: screenSize.width / screenCrop.width).cropped(to: CGRect(origin: .zero, size: screenSize))
    }

    // MARK: 不可思议

    /// What 不可思议 can turn a picture into (one, by chance, when it is taken).
    enum Mystery: CaseIterable, Sendable {
        case falseColour, poster, negative, duotone, swap, solarise, infrared
        var title: String {
            switch self {
            case .falseColour: return String(localized: "伪彩")
            case .poster: return String(localized: "海报")
            case .negative: return String(localized: "负片")
            case .duotone: return String(localized: "单色")
            case .swap: return String(localized: "换色")
            case .solarise: return String(localized: "日晒")
            case .infrared: return String(localized: "红外")
            }
        }
    }

    static func mystery(_ image: CIImage, _ kind: Mystery, hue: Double) -> CIImage {
        func colour(_ h: Double, _ s: Double, _ b: Double) -> CIColor {
            let (r, g, bl) = rgb(hue: h, saturation: s, brightness: b)
            return CIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(bl))
        }
        switch kind {
        case .falseColour:
            let f = CIFilter.falseColor(); f.inputImage = image
            f.color0 = colour(hue, 0.9, 0.35); f.color1 = colour(hue + 0.45, 0.6, 1.0)
            return (f.outputImage ?? image).cropped(to: photoRect)
        case .poster:
            let p = CIFilter.colorPosterize(); p.inputImage = image; p.levels = 4
            let h = CIFilter.hueAdjust(); h.inputImage = p.outputImage; h.angle = Float(hue * 2 * .pi)
            return (h.outputImage ?? image).cropped(to: photoRect)
        case .negative:
            let f = CIFilter.colorInvert(); f.inputImage = image
            return (f.outputImage ?? image).cropped(to: photoRect)
        case .duotone:
            let f = CIFilter.colorMonochrome(); f.inputImage = image; f.color = colour(hue, 0.7, 0.9); f.intensity = 1
            let c = CIFilter.colorControls(); c.inputImage = f.outputImage; c.contrast = 1.25; c.saturation = 1.2; c.brightness = 0
            return (c.outputImage ?? image).cropped(to: photoRect)
        case .swap:
            let f = CIFilter.colorMatrix(); f.inputImage = image
            f.rVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: 0, z: 1, w: 0)
            f.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            return (f.outputImage ?? image).cropped(to: photoRect)
        case .solarise:
            let f = CIFilter.toneCurve(); f.inputImage = image
            f.point0 = CGPoint(x: 0, y: 0); f.point1 = CGPoint(x: 0.3, y: 0.62); f.point2 = CGPoint(x: 0.55, y: 0.95)
            f.point3 = CGPoint(x: 0.78, y: 0.5); f.point4 = CGPoint(x: 1, y: 0.12)
            return (f.outputImage ?? image).cropped(to: photoRect)
        case .infrared:
            let f = CIFilter.colorMatrix(); f.inputImage = image
            f.rVector = CIVector(x: 0.1, y: 1.2, z: 0, w: 0)
            f.gVector = CIVector(x: 0.3, y: 0.3, z: 0.3, w: 0)
            f.bVector = CIVector(x: 0.6, y: 0, z: 0.4, w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            f.biasVector = CIVector(x: 0, y: 0, z: 0.05, w: 0)
            return (f.outputImage ?? image).cropped(to: photoRect)
        }
    }

    /// HSB (0…1 each, hue wrapping) to RGB.
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6, f = h - floor(h)
        let p = brightness * (1 - saturation), q = brightness * (1 - saturation * f), t = brightness * (1 - saturation * (1 - f))
        switch i {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }
}

// MARK: - 闪闪

/// 闪闪's pieces: stars, hearts, notes, bubbles and confetti that the breath
/// blows up from the bottom of the picture; they drift and fade. Positions
/// in the picture's pixels (640 × 480, origin top left).
struct SparkleField: Sendable {
    enum Kind: CaseIterable, Sendable { case star, heart, note, bubble, confetti }
    struct Piece: Sendable {
        var kind: Kind
        var x: Double, y: Double
        var vx: Double, vy: Double
        var angle: Double, spin: Double
        var size: Double
        var hue: Double
        var age = 0.0
        var life: Double
    }
    private(set) var pieces: [Piece] = []
    private var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var owed = 0.0

    var isEmpty: Bool { pieces.isEmpty }

    private mutating func random() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// One frame: new pieces while the breath goes on, the others move.
    mutating func step(dt: Double, blowing: Bool) {
        if blowing {
            owed += dt * 34
            while owed >= 1 && pieces.count < 160 {
                owed -= 1
                let kind = Kind.allCases[Int(random() * Double(Kind.allCases.count)) % Kind.allCases.count]
                let x = 120 + random() * 400
                let vx = (x - 320) * 0.35 + (random() - 0.5) * 80, vy = -(150 + random() * 170)
                let angle = random() * .pi * 2, spin = (random() - 0.5) * 5
                let size = kind == .confetti ? 9 + random() * 6 : 16 + random() * 16
                let hue = random(), life = 2.6 + random() * 1.8
                let piece = Piece(kind: kind, x: x, y: 470, vx: vx, vy: vy, angle: angle, spin: spin, size: size, hue: hue, life: life)
                pieces.append(piece)
            }
        } else {
            owed = 0
        }
        for i in pieces.indices {
            pieces[i].age += dt
            pieces[i].x += pieces[i].vx * dt
            pieces[i].y += pieces[i].vy * dt
            pieces[i].vy += (pieces[i].kind == .bubble ? -12 : 26) * dt
            pieces[i].vx *= 1 - min(0.9, dt * 0.6)
            pieces[i].angle += pieces[i].spin * dt
        }
        pieces.removeAll { $0.age > $0.life || $0.y < -60 || $0.x < -60 || $0.x > 700 }
    }

    /// The pieces over a picture: the whole 640 × 480 one, or the upper
    /// screen's 400 × 240 (its part of the picture).
    func drawn(over image: CGImage) -> CGImage? {
        guard !pieces.isEmpty else { return image }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Picture pixels (origin top left) to this image's (origin bottom left).
        let screen = width == Int(CameraLook.screenSize.width)
        let scale = screen ? CameraLook.screenSize.width / CameraLook.photoSize.width : Double(width) / CameraLook.photoSize.width
        let top = screen ? (CameraLook.photoSize.height - CameraLook.screenCrop.maxY) : 0
        for piece in pieces {
            let fade = min(1, (piece.life - piece.age) / 0.6) * min(1, piece.age / 0.12)
            guard fade > 0.01 else { continue }
            let x = piece.x * scale, y = Double(height) - (piece.y - top) * scale
            let size = piece.size * scale
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.rotate(by: piece.angle)
            context.setAlpha(fade)
            let (r, g, b) = CameraLook.rgb(hue: piece.hue, saturation: 0.75, brightness: 1)
            let fill = CGColor(colorSpace: CameraLook.colorSpace, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1]) ?? CGColor(gray: 1, alpha: 1)
            let white = CGColor(gray: 1, alpha: 0.95)
            context.setFillColor(fill)
            context.setStrokeColor(white)
            context.setLineWidth(max(1, size * 0.09))
            Self.draw(piece.kind, size: size, fill: fill, in: context)
            context.restoreGState()
        }
        return context.makeImage()
    }

    private static func draw(_ kind: Kind, size: Double, fill: CGColor, in context: CGContext) {
        let r = size / 2
        switch kind {
        case .star:
            let path = CGMutablePath()
            for i in 0..<10 {
                let radius = i % 2 == 0 ? r : r * 0.45
                let a = Double(i) * .pi / 5 - .pi / 2
                let p = CGPoint(x: cos(a) * radius, y: sin(a) * radius)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            context.addPath(path); context.drawPath(using: .fillStroke)
        case .heart:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -r * 0.9))
            path.addCurve(to: CGPoint(x: 0, y: r * 0.45), control1: CGPoint(x: r * 1.4, y: -r * 0.1), control2: CGPoint(x: r * 0.7, y: r * 1.15))
            path.addCurve(to: CGPoint(x: 0, y: -r * 0.9), control1: CGPoint(x: -r * 0.7, y: r * 1.15), control2: CGPoint(x: -r * 1.4, y: -r * 0.1))
            path.closeSubpath()
            context.addPath(path); context.drawPath(using: .fillStroke)
        case .note:
            context.fillEllipse(in: CGRect(x: -r * 0.55, y: -r * 0.85, width: r * 0.8, height: r * 0.6))
            context.fill(CGRect(x: r * 0.12, y: -r * 0.6, width: max(1, r * 0.14), height: r * 1.5))
            let flag = CGMutablePath()
            flag.move(to: CGPoint(x: r * 0.26, y: r * 0.9))
            flag.addQuadCurve(to: CGPoint(x: r * 0.7, y: r * 0.2), control: CGPoint(x: r * 0.8, y: r * 0.75))
            context.setLineWidth(max(1, r * 0.16))
            context.setStrokeColor(fill)
            context.addPath(flag); context.strokePath()
        case .bubble:
            context.setLineWidth(max(1, r * 0.14))
            context.strokeEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
            context.setFillColor(CGColor(gray: 1, alpha: 0.85))
            context.fillEllipse(in: CGRect(x: -r * 0.55, y: r * 0.15, width: r * 0.4, height: r * 0.3))
        case .confetti:
            context.fill(CGRect(x: -r, y: -r * 0.45, width: 2 * r, height: r * 0.9))
        }
    }
}

// MARK: - Faces (合体)

enum CameraFaces {
    /// A face in a 640 × 480 picture (Core Image's coordinates, origin at
    /// the bottom): its box and, when found, the two eyes (left one first,
    /// as they lie in the picture).
    struct Face: Sendable {
        var box: CGRect
        var eyes: (CGPoint, CGPoint)?
    }

    static func find(in image: CIImage, eyes: Bool) -> Face? {
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else { return nil }
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let faces: [VNFaceObservation]
        if eyes {
            let request = VNDetectFaceLandmarksRequest()
            do { try handler.perform([request]) } catch { return nil }
            faces = request.results ?? []
        } else {
            let request = VNDetectFaceRectanglesRequest()
            do { try handler.perform([request]) } catch { return nil }
            faces = request.results ?? []
        }
        guard let face = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return nil }
        let box = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
        var pair: (CGPoint, CGPoint)?
        if eyes, let landmarks = face.landmarks {
            func centre(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
                guard let points = region?.pointsInImage(imageSize: size), !points.isEmpty else { return nil }
                let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                return CGPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
            }
            if let a = centre(landmarks.leftPupil) ?? centre(landmarks.leftEye),
               let b = centre(landmarks.rightPupil) ?? centre(landmarks.rightEye), abs(a.x - b.x) > 4 {
                pair = a.x < b.x ? (a, b) : (b, a)
            }
        }
        return Face(box: box.offsetBy(dx: image.extent.minX, dy: image.extent.minY), eyes: pair)
    }
}

/// One of 合体's two pictures.
struct CameraMergePart: @unchecked Sendable {
    var image: CGImage
    var face: CameraFaces.Face?
}

enum CameraMerge {
    /// Your face (`second`, the inner camera) laid over the face of the
    /// person opposite (`first`, the outer camera), half and half, the eyes
    /// on the eyes: one face made of two. Without faces, the middles.
    static func merge(_ first: CameraMergePart, _ second: CameraMergePart, context: CIContext) -> CIImage {
        let a = CIImage(cgImage: first.image), b = CIImage(cgImage: second.image)
        let rect = CameraLook.photoRect
        let defaultBox = CGRect(x: 200, y: 110, width: 240, height: 290)
        let boxA = first.face?.box ?? defaultBox, boxB = second.face?.box ?? defaultBox
        var move: CGAffineTransform
        if let ea = first.face?.eyes, let eb = second.face?.eyes {
            move = similarity(from: eb, to: ea)
        } else {
            let s = boxA.width / max(1, boxB.width)
            move = CGAffineTransform(translationX: boxA.midX, y: boxA.midY).scaledBy(x: s, y: s).translatedBy(x: -boxB.midX, y: -boxB.midY)
        }
        // B's face brought most of the way to A's colour, so the two halves
        // read as one skin.
        var faceB = b
        if let ca = average(of: a, in: boxA.intersection(rect), context: context), let cb = average(of: b, in: boxB.intersection(rect), context: context) {
            func gain(_ x: Double, _ y: Double) -> CGFloat { CGFloat(1 + 0.7 * ((x + 0.02) / (y + 0.02) - 1)) }
            let f = CIFilter.colorMatrix()
            f.inputImage = b
            f.rVector = CIVector(x: gain(ca.0, cb.0), y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: gain(ca.1, cb.1), z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: gain(ca.2, cb.2), w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            faceB = f.outputImage ?? b
        }
        let warped = faceB.transformed(by: move).clampedToExtent().cropped(to: rect)
        // Where it shows: an oval over A's face, half at its middle, nothing
        // at its edge.
        let rx = boxA.width * 0.62, ry = boxA.height * 0.74
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = Float(rx * 0.5)
        gradient.radius1 = Float(rx)
        gradient.color0 = CIColor(red: 0.55, green: 0.55, blue: 0.55)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        let mask = (gradient.outputImage ?? CIImage.empty())
            .transformed(by: CGAffineTransform(scaleX: 1, y: ry / max(1, rx)))
            .transformed(by: CGAffineTransform(translationX: boxA.midX, y: boxA.midY - boxA.height * 0.04))
            .cropped(to: rect)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = warped
        blend.backgroundImage = a
        blend.maskImage = mask
        return (blend.outputImage ?? a).cropped(to: rect)
    }

    /// The turn, scale and move that puts the points `from` on `to`.
    static func similarity(from: (CGPoint, CGPoint), to: (CGPoint, CGPoint)) -> CGAffineTransform {
        let v1 = CGPoint(x: from.1.x - from.0.x, y: from.1.y - from.0.y)
        let v2 = CGPoint(x: to.1.x - to.0.x, y: to.1.y - to.0.y)
        let l1 = max(1, hypot(v1.x, v1.y)), l2 = hypot(v2.x, v2.y)
        let s = min(4, max(0.25, l2 / l1))
        let angle = atan2(v2.y, v2.x) - atan2(v1.y, v1.x)
        return CGAffineTransform(translationX: to.0.x, y: to.0.y).rotated(by: angle).scaledBy(x: s, y: s).translatedBy(x: -from.0.x, y: -from.0.y)
    }

    private static func average(of image: CIImage, in rect: CGRect, context: CIContext) -> (Double, Double, Double)? {
        guard rect.width >= 4, rect.height >= 4 else { return nil }
        let f = CIFilter.areaAverage()
        f.inputImage = image
        f.extent = rect
        guard let output = f.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CameraLook.colorSpace)
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}

// MARK: - The SD card

/// One picture on the SD card.
struct CameraPhoto: Identifiable, Equatable, Sendable {
    var url: URL
    var date: Date
    var id: URL { url }
    var name: String { url.lastPathComponent }
    /// 录像: a video the camera recorded (or one copied in).
    var isVideo: Bool { CameraRoll.videoExtensions.contains(url.pathExtension.lowercased()) }
}

/// The pictures on the emulated SD card: `Azahar/sdmc/DCIM` in the console's
/// storage (the Files app shows it under 我的 iPhone › FoldArc › Azahar ›
/// sdmc › DCIM). Zero's go in `100_ZERO`… (before 11-07 `100FOLDA`); pictures copied there from
/// elsewhere are shown too, and left as they are.
/// 11-06: each picture the camera
/// takes also goes into the iPhone's Photos, as it is on the SD card. Add
/// only: FoldArc never reads the library (NSPhotoLibraryAddUsageDescription;
/// the system asks the first time). DEBUG `--foldarc-no-photos` leaves it
/// out (the Simulator's UI tests, which have no one to answer the question).
enum SystemPhotos {
    enum Outcome: Sendable { case added, notAllowed, failed(String), off }
    static func add(_ url: URL, video: Bool = false) async -> Outcome {
        #if os(iOS)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-no-photos") { return .off }
        #endif
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .notAllowed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: video ? .video : .photo, fileURL: url, options: nil)
            }
            return .added
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .off
        #endif
    }
}

enum CameraRoll {
    static let limit = 3000
    static let pictureExtensions: Set<String> = ["jpg", "jpeg"]
    /// 录像: the camera's videos are MP4; a QuickTime one copied in is shown too.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static var dcim: URL {
        #if DEBUG
        // (11-22: the UI tests run on a phone keep the pictures they take apart from its own album)
        if ProcessInfo.processInfo.arguments.contains("--foldarc-camera-scratch") {
            return Storage.consoleStorage().appendingPathComponent("FoldArcTrace/test-DCIM", isDirectory: true)
        }
        #endif
        return Storage.consoleStorage().appendingPathComponent("Azahar/sdmc/DCIM", isDirectory: true)
    }

    static func list(in dcim: URL = CameraRoll.dcim) -> [CameraPhoto] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        guard let folders = try? fm.contentsOfDirectory(at: dcim, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var photos: [CameraPhoto] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            for file in files where pictureExtensions.contains(file.pathExtension.lowercased()) || videoExtensions.contains(file.pathExtension.lowercased()) {
                let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                photos.append(CameraPhoto(url: file, date: values?.creationDate ?? values?.contentModificationDate ?? .distantPast))
            }
        }
        return photos.sorted { $0.date == $1.date ? $0.name > $1.name : $0.date > $1.date }
    }

    /// 11-07: the
    /// pictures and videos taken before under their new names, in place on
    /// the SD card — `100FOLDA/FARC0001.JPG` → `100_ZERO/ZERO0001.JPG`, the
    /// numbers kept; nothing copied, nothing deleted. A name already taken is
    /// left as it was (the album shows every picture whatever its name).
    /// Once (the key notes it); off the main thread at launch.
    static let renamedKey = "foldarc.dcf.renamedToZero"
    static func renameOldPicturesOnce() {
        guard !UserDefaults.standard.bool(forKey: renamedKey) else { return }
        DispatchQueue.global(qos: .utility).async {
            let (files, folders) = renameOldPictures()
            UserDefaults.standard.set(true, forKey: renamedKey)
            NSLog("[camera] the SD card's old names: %d pictures and %d folders renamed (FARC → ZERO, FOLDA → _ZERO)", files, folders)
        }
    }
    @discardableResult static func renameOldPictures(in dcim: URL = CameraRoll.dcim) -> (files: Int, folders: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dcim.path) else { return (0, 0) }
        var files = 0, folders = 0
        for name in names {
            guard let newName = CameraFileNames.renamed(folder: name) else { continue }
            let old = dcim.appendingPathComponent(name, isDirectory: true)
            for file in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] {
                guard let renamed = CameraFileNames.renamed(file: file) else { continue }
                let to = old.appendingPathComponent(renamed)
                guard !fm.fileExists(atPath: to.path) else { continue }
                if (try? fm.moveItem(at: old.appendingPathComponent(file), to: to)) != nil { files += 1 }
            }
            let target = dcim.appendingPathComponent(newName, isDirectory: true)
            if !fm.fileExists(atPath: target.path) {
                if (try? fm.moveItem(at: old, to: target)) != nil { folders += 1 }
            } else {
                // Zero's folder of that number is there already: its free
                // names take the old ones; the rest stay where they are.
                for file in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where CameraFileNames.fileNumber(file) != nil {
                    let to = target.appendingPathComponent(file)
                    if !fm.fileExists(atPath: to.path) { try? fm.moveItem(at: old.appendingPathComponent(file), to: to) }
                }
            }
        }
        return (files, folders)
    }

    /// 11-07: the size a picture takes on the card, on average over the
    /// newest pictures (videos left out); nil while there are none.
    static func averagePictureBytes(_ photos: [CameraPhoto], newest: Int = 40) -> Int64? {
        let sizes = photos.lazy.filter { !$0.isVideo }.prefix(newest)
            .compactMap { (try? $0.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
        guard !sizes.isEmpty else { return nil }
        return Int64(sizes.reduce(0, +) / sizes.count)
    }

    static func freeBytes(at url: URL = CameraRoll.dcim) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) && probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Writes a picture under the next free number; returns where it went.
    static func save(_ jpeg: Data, in dcim: URL = CameraRoll.dcim) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dcim, withIntermediateDirectories: true)
        let folders = (try? fm.contentsOfDirectory(atPath: dcim.path)) ?? []
        guard let next = CameraFileNames.next(folders: folders, files: { (try? fm.contentsOfDirectory(atPath: dcim.appendingPathComponent($0).path)) ?? [] }) else {
            throw NSError(domain: "FoldArc.camera", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "SD 卡上的相片编号用完了")])
        }
        let folder = dcim.appendingPathComponent(next.folder, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(next.file)
        // Never over another picture (`.withoutOverwriting` cannot be had
        // together with `.atomic`: Foundation stops the app, 10-31).
        try jpeg.write(to: url, options: .withoutOverwriting)
        return url
    }

    static func delete(_ photo: CameraPhoto) throws {
        try FileManager.default.removeItem(at: photo.url)
    }

    /// The picture as a JPEG, with the time it was taken and what took it.
    static func jpeg(_ image: CGImage, side: CameraSide, lens: CameraLens, note: String?, date: Date, quality: Double = 0.82) -> Data? {
        let lensName = lens == .lowLight ? "low light" : lens.rawValue
        return jpeg(image, model: "Zero camera (\(side.rawValue))", description: "lens: \(lensName)" + (note == nil ? "" : " (mystery)"),
                    date: date, quality: quality)
    }

    /// A JPEG with the time and what made it (`model`, `description`): a
    /// picture taken, or an album picture drawn on and kept anew.
    static func jpeg(_ image: CGImage, model: String, description: String, date: Date, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let stamp = formatter.string(from: date)
        let exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
            kCGImagePropertyExifPixelXDimension: image.width,
            kCGImagePropertyExifPixelYDimension: image.height,
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Zero",
            kCGImagePropertyTIFFModel: model,
            kCGImagePropertyTIFFSoftware: "Zero EMU",
            kCGImagePropertyTIFFDateTime: stamp,
            kCGImagePropertyTIFFImageDescription: description,
        ]
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: 1,
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A picture read back, at most `maxPixel` on its long side.
    static func image(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - 冲洗 (a picture brought in, developed by a body)

/// A picture brought in from the iPhone's Photos, made what the camera would
/// have handed a body: upright, the middle cut to the camera's proportions
/// (4:3, or 3:4 for an upright picture) at the camera's size.
struct CameraImport: @unchecked Sendable {
    /// 640 × 480, or 480 × 640 for an upright picture.
    let picture: CGImage
    /// When it was taken, if the picture says.
    let taken: Date?
    var upright: Bool { picture.height > picture.width }

    init?(image: CGImage, taken: Date?) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let size = h > w ? CGSize(width: CameraLook.photoSize.height, height: CameraLook.photoSize.width) : CameraLook.photoSize
        // The middle, filling the camera's picture.
        let scale = max(size.width / CGFloat(w), size.height / CGFloat(h))
        let drawn = CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        guard let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .high
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        c.fill(CGRect(origin: .zero, size: size))
        c.draw(image, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        guard let made = c.makeImage() else { return nil }
        picture = made
        self.taken = taken
    }

    /// From a picture file's bytes (nil: not a picture that can be read).
    /// Turned upright as the file says; at most 1600 across before the cut.
    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        var taken: Date?
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let text = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = "yyyy:MM:dd HH:mm:ss"
            taken = format.date(from: text)
        }
        self.init(image: image, taken: taken)
    }
}

/// 冲洗: a picture brought in, through a body as the camera would have made
/// it — the module's look, then the body's at its 浓淡, with what a kept
/// picture gets (the JPEG blocks). An upright picture is developed lying
/// down, as a camera held on its side takes it (its date runs up the side).
enum CameraDarkroom {
    private static let context = CIContext(options: [.cacheIntermediates: false,
                                                     .workingColorSpace: CameraLook.colorSpace, .outputColorSpace: CameraLook.colorSpace])

    static func develop(_ source: CameraImport, body: CameraBody, strength: Double, seed: Int, date: Date) -> CGImage? {
        var picture = CIImage(cgImage: source.picture)
        if source.upright { picture = atOrigin(picture.oriented(.right)) }
        guard Int(picture.extent.width) == Int(CameraLook.photoSize.width), Int(picture.extent.height) == Int(CameraLook.photoSize.height) else { return nil }
        let made: CIImage
        if body == .native {
            made = CameraLook.module3DS(picture, grain: 0.075, seed: seed, mean: mean(of: picture) ?? 0.45)
        } else {
            made = CameraBodyLook.develop(CameraLook.given(picture, body: body, grain: 0.075, seed: seed), body: body, strength: strength, seed: seed, date: date, still: true)
        }
        var out = made.cropped(to: CameraLook.photoRect)
        if source.upright { out = atOrigin(out.oriented(.left)) }
        // 小票: printed on the till's slip, under the number it will be kept by.
        if let thermal = body.recipe.thermal {
            guard let picture = context.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: CameraLook.colorSpace) else { return nil }
            return CameraReceiptPrint.slip(picture, thermal: thermal, strength: strength, date: date, number: CameraReceiptPrint.nextNumber()) ?? picture
        }
        return context.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: CameraLook.colorSpace)
    }

    private static func atOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
    /// The picture's mean brightness (0…1).
    private static func mean(of image: CIImage) -> Double? {
        let f = CIFilter.areaAverage()
        f.inputImage = image
        f.extent = image.extent
        guard let output = f.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CameraLook.colorSpace)
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
    }
}

// MARK: - The test picture

/// 两联 and 四连拍: the pictures taken, laid on the one sheet that is kept
/// (where each goes and the part of it used: CameraSheetLayout).
enum CameraSheets {
    static func compose(_ shots: [CGImage]) -> CGImage? {
        let width = Int(CameraLook.photoSize.width), height = Int(CameraLook.photoSize.height)
        guard shots.count == 2 || shots.count == 4,
              let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ground = CameraSheetLayout.ground(count: shots.count)
        c.setFillColor(CGColor(colorSpace: CameraLook.colorSpace, components: [CGFloat(ground.r), CGFloat(ground.g), CGFloat(ground.b), 1]) ?? CGColor(gray: 0.5, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        c.interpolationQuality = .high
        let cells = CameraSheetLayout.cells(count: shots.count, width: Double(width), height: Double(height))
        let part = CameraSheetLayout.part(count: shots.count, width: Double(width), height: Double(height))
        for (shot, cell) in zip(shots, cells) {
            let w = Double(shot.width), h = Double(shot.height)
            guard let cut = shot.cropping(to: CGRect(x: part.minX * w, y: part.minY * h, width: part.width * w, height: part.height * h)) else { continue }
            // (Core Graphics counts rows from the bottom; the layout from the top.)
            c.draw(cut, in: CGRect(x: cell.minX, y: Double(height) - cell.maxY, width: cell.width, height: cell.height))
        }
        return c.makeImage()
    }

    private static let context = CIContext(options: [.cacheIntermediates: false,
                                                     .workingColorSpace: CameraLook.colorSpace, .outputColorSpace: CameraLook.colorSpace])
    /// 两联's sheet with what the body prints on a picture (bars, its date,
    /// the paper), or the 日期 setting's date: once, on the whole sheet (the
    /// half frames were taken without).
    static func printed(_ sheet: CGImage, body: CameraBody, dated: Bool, date: Date) -> CGImage? {
        var image = CIImage(cgImage: sheet)
        if body != .native { image = CameraBodyLook.printed(image, recipe: body.recipe, seed: Int(date.timeIntervalSinceReferenceDate), date: date) }
        if dated, !body.hasDateStamp { image = CameraBodyLook.dateStamp(image, date: date) }
        return context.createCGImage(image.cropped(to: CameraLook.photoRect), from: CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace)
    }
}

/// What the camera shows where there is no camera (the Simulator, the Mac
/// preview): a drawn scene that moves, a street outside for the outer
/// camera and a room with a drawn face for the inner one, marked as a test.
enum CameraTestScene {
    /// Used on the feed's queue only.
    private static let clockFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
    /// `wide`: the outer camera at 0.5× (standing in for a rear
    /// ultra wide): the same street from further back.
    static func frame(side: CameraSide, time: Double, wide: Bool = false) -> CGImage? {
        let width = 640, height = 480
        guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: CameraLook.colorSpace, components: [r, g, b, a]) ?? CGColor(gray: 0.5, alpha: a)
        }
        func gradient(_ top: CGColor, _ bottom: CGColor, from y0: Double, to y1: Double) {
            guard let g = CGGradient(colorsSpace: CameraLook.colorSpace, colors: [bottom, top] as CFArray, locations: [0, 1]) else { return }
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        if side == .outer && wide {
            // Twice the field: sky and far hills round the street, drawn at
            // half size in the middle.
            gradient(colour(0.36, 0.58, 0.86), colour(0.80, 0.88, 0.95), from: 120, to: 480)
            c.setFillColor(colour(0.40, 0.60, 0.36))
            c.fillEllipse(in: CGRect(x: -260, y: -40, width: 620, height: 330))
            c.setFillColor(colour(0.35, 0.56, 0.32))
            c.fillEllipse(in: CGRect(x: 300, y: -60, width: 640, height: 320))
            c.setFillColor(colour(0.55, 0.50, 0.42))
            c.fill(CGRect(x: 0, y: 0, width: 640, height: 175))
            c.saveGState()
            c.translateBy(x: 160, y: 120)
            c.scaleBy(x: 0.5, y: 0.5)
            // The street's sky gradient fills its clip: only its own frame.
            c.clip(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        if side == .outer {
            // Sky, sun, clouds, hills, a house, trees, a ball going by.
            gradient(colour(0.36, 0.58, 0.86), colour(0.80, 0.88, 0.95), from: 180, to: 480)
            c.setFillColor(colour(1.0, 0.92, 0.55))
            c.fillEllipse(in: CGRect(x: 470 + sin(time * 0.1) * 30, y: 360, width: 70, height: 70))
            c.setFillColor(colour(1, 1, 1, 0.85))
            for i in 0..<3 {
                let x = (Double(i) * 230 + time * 18).truncatingRemainder(dividingBy: 820) - 120
                c.fillEllipse(in: CGRect(x: x, y: 380 + Double(i % 2) * 30, width: 110, height: 36))
                c.fillEllipse(in: CGRect(x: x + 30, y: 395 + Double(i % 2) * 30, width: 70, height: 36))
            }
            c.setFillColor(colour(0.42, 0.62, 0.36))
            c.fillEllipse(in: CGRect(x: -120, y: 60, width: 520, height: 260))
            c.setFillColor(colour(0.33, 0.55, 0.30))
            c.fillEllipse(in: CGRect(x: 260, y: 40, width: 560, height: 250))
            c.setFillColor(colour(0.55, 0.50, 0.42))
            c.fill(CGRect(x: 0, y: 0, width: 640, height: 110))
            c.setFillColor(colour(0.93, 0.90, 0.82))
            c.fill(CGRect(x: 250, y: 110, width: 130, height: 100))
            c.setFillColor(colour(0.72, 0.20, 0.18))
            c.beginPath(); c.move(to: CGPoint(x: 236, y: 208)); c.addLine(to: CGPoint(x: 315, y: 268)); c.addLine(to: CGPoint(x: 394, y: 208)); c.closePath(); c.fillPath()
            c.setFillColor(colour(0.35, 0.50, 0.70))
            c.fill(CGRect(x: 270, y: 150, width: 30, height: 30)); c.fill(CGRect(x: 330, y: 150, width: 30, height: 30))
            c.setFillColor(colour(0.40, 0.27, 0.18))
            c.fill(CGRect(x: 300, y: 110, width: 28, height: 46))
            for (x, s) in [(90.0, 1.0), (170.0, 0.8), (470.0, 1.15), (560.0, 0.9)] {
                c.setFillColor(colour(0.42, 0.30, 0.20))
                c.fill(CGRect(x: x - 6 * s, y: 100, width: 12 * s, height: 60 * s))
                c.setFillColor(colour(0.22, 0.45, 0.22))
                c.fillEllipse(in: CGRect(x: x - 40 * s, y: 140 * s + 10, width: 80 * s, height: 90 * s))
            }
            let bx = 320 + sin(time * 0.9) * 250, by = 40 + abs(sin(time * 2.2)) * 70
            c.setFillColor(colour(0.95, 0.55, 0.15))
            c.fillEllipse(in: CGRect(x: bx - 18, y: by, width: 36, height: 36))
            if wide { c.restoreGState() }
        } else {
            // A room: the wall, a window, a lamp, and a drawn face.
            gradient(colour(0.86, 0.80, 0.70), colour(0.70, 0.64, 0.56), from: 0, to: 480)
            c.setFillColor(colour(0.55, 0.42, 0.30))
            c.fill(CGRect(x: 0, y: 0, width: 640, height: 70))
            c.setFillColor(colour(0.96, 0.96, 0.94))
            c.fill(CGRect(x: 420, y: 230, width: 170, height: 190))
            c.setFillColor(colour(0.55, 0.75, 0.95))
            c.fill(CGRect(x: 432, y: 242, width: 146, height: 166))
            c.setFillColor(colour(1.0, 0.95, 0.75, 0.9))
            c.fillEllipse(in: CGRect(x: 60, y: 300, width: 80, height: 60))
            let fx = 300 + sin(time * 0.7) * 14, fy = 250 + sin(time * 1.1) * 8
            c.setFillColor(colour(0.20, 0.16, 0.14))
            c.fillEllipse(in: CGRect(x: fx - 100, y: fy - 85, width: 200, height: 225))
            c.setFillColor(colour(0.93, 0.76, 0.64))
            c.fillEllipse(in: CGRect(x: fx - 85, y: fy - 110, width: 170, height: 205))
            c.setFillColor(colour(0.25, 0.30, 0.55))
            c.fill(CGRect(x: fx - 130, y: 0, width: 260, height: fy - 110))
            let blink = (time.truncatingRemainder(dividingBy: 3.4)) < 0.15
            c.setFillColor(colour(0.15, 0.12, 0.12))
            for ex in [fx - 36, fx + 36] {
                c.fillEllipse(in: CGRect(x: ex - 11, y: fy + 4, width: 22, height: blink ? 4 : 20))
            }
            c.setStrokeColor(colour(0.55, 0.25, 0.22))
            c.setLineWidth(6)
            c.beginPath()
            c.addArc(center: CGPoint(x: fx, y: fy - 22), radius: 38, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
            c.strokePath()
        }
        // Marked as a test picture, with the time (it moves).
        let clock = clockFormat.string(from: Date(timeIntervalSinceReferenceDate: time))
        label(side == .outer ? String(localized: "测试画面 · 外侧\(wide ? " 0.5×" : "") \(clock)") : String(localized: "测试画面 · 内侧 \(clock)"), in: c, centredAt: 320, top: 378)
        return c.makeImage()
    }

    private static func label(_ text: String, in c: CGContext, centredAt x: Double, top: Double) {
        let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 20, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.92),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let point = CGPoint(x: x - bounds.width / 2, y: top - bounds.height)
        c.setFillColor(CGColor(gray: 0, alpha: 0.45))
        c.fill(CGRect(x: point.x - 8, y: point.y - 8, width: bounds.width + 16, height: bounds.height + 14))
        c.textPosition = point
        CTLineDraw(line, c)
    }
}

#if DEBUG
// MARK: - What the work costs (a DEBUG build)

/// What the camera's work costs, for the trace: a line every ten seconds —
/// and when the body, the lens or a recording changes — with how many
/// frames came, how long the work on one took, how many the camera dropped
/// and what the system says of its load; before them, how long the first
/// picture took after opening.
struct CameraCost {
    /// What a line is about: another starts a new one.
    struct Subject: Equatable {
        var body: String
        var lens: String
        var recording: Bool
    }
    static let window = 10.0
    private var subject: Subject?
    private var first = true
    /// The line's start (uptime, s).
    private var began = 0.0
    private var frames = 0, slow = 0, dropped = 0
    private var total = 0.0, longest = 0.0
    private var reasons: [String: Int] = [:]

    mutating func drop(_ reason: String?) {
        dropped += 1
        reasons[reason ?? "no reason given", default: 0] += 1
    }

    /// The work on a frame took `from`…`to` (uptime): the lines to write now.
    mutating func frame(from: Double, to: Double, subject next: Subject, opened: Double, load: () -> String) -> [String] {
        var lines: [String] = []
        if first {
            first = false
            lines.append(String(format: "the first picture %.0f ms after opening (its work %.1f ms)", (to - opened) * 1000, (to - from) * 1000))
        }
        if subject != next {
            if let ended = line(until: from, load: load) { lines.append(ended) }
            subject = next
            began = from
        }
        frames += 1
        total += to - from
        longest = max(longest, to - from)
        if to - from > 1.0 / 30 { slow += 1 }
        if to - began >= Self.window, let full = line(until: to, load: load) { lines.append(full) }
        return lines
    }

    /// The line of what was counted since the last one (nil: nothing was),
    /// and the count begins again.
    mutating func line(until now: Double, load: () -> String) -> String? {
        defer { began = now; frames = 0; slow = 0; dropped = 0; total = 0; longest = 0; reasons = [:] }
        guard let subject, frames > 0 else { return nil }
        let seconds = max(0.001, now - began)
        var text = String(format: "%@ / %@%@: %d frames in %.1f s (%.1f a second), the work %.1f ms a frame, the longest %.1f ms, %d over 33 ms",
                          subject.body, subject.lens, subject.recording ? " / recording" : "", frames, seconds, Double(frames) / seconds,
                          total / Double(frames) * 1000, longest * 1000, slow)
        text += ", dropped \(dropped)"
        if !reasons.isEmpty { text += " (" + reasons.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ")" }
        return text + ", " + load()
    }

    static func note(_ line: String) {
        NSLog("[camera] cost: %@", line)
        #if os(iOS)
        DispatchQueue.main.async { OrientationTrace.shared.event("camera cost: " + line) }
        #endif
    }
}
#endif

// MARK: - The feed

/// Pictures in, the upper screen's picture and the taken pictures out.
/// Everything here runs on its own queues; what it reports goes out through
/// the callbacks, on its frame queue.
final class CameraFeed: NSObject, @unchecked Sendable {
    struct Settings: Equatable, Sendable {
        var side = CameraSide.outer
        var lens = CameraLens.normal
        var manual = CameraManual()
        /// Round 32 (机型): the simulated body laid over the lens's finish.
        var body = CameraBody.native
        /// 浓淡: how much of the body's look (1: as made; CameraBodyStrength).
        var strength = 1.0
        /// 11-06: digital zoom, 1–4× (the middle of the module's picture);
        /// 0.5× too where the camera has an ultra wide (the rear dual
        /// camera zooms itself then, and nothing is cropped).
        var zoom = 1.0
        /// 11-06: an old compact's shooting settings (every lens).
        var shooting = CameraShooting()
        /// 11-15: the picture's rotation set from outside (the cover's
        /// deck: from how the shut console is held), instead of the
        /// system's horizon angle. On the phone that angle went its own way
        /// on the cover: stood as a tent it said a quarter less than shut
        /// and held the same way (the picture lay on its side), and held in
        /// turn it ran ahead of the deck. nil: the system's angle.
        var angle: Double? = nil
        /// The cover's deck: the shape its picture is kept in (and shown
        /// in). nil: the whole picture, shown as the upper screen shows it.
        var aspect: CameraAspect? = nil
    }
    /// The upper screen's picture, and where a face is in it (合体).
    struct Frame: @unchecked Sendable {
        var screen: CGImage
        var face: CGRect?
        var side: CameraSide
    }
    enum Request: @unchecked Sendable {
        case single
        case mergeFirst
        case mergeSecond(CameraMergePart)
    }
    enum Result: @unchecked Sendable {
        case photo(CGImage, note: String?)
        case mergePart(CameraMergePart)
        case failed(String)
    }
    enum Event: Sendable {
        case running(test: Bool)
        case failed(String)
        case interrupted(String)
        case resumed
        /// Round 32: a lens picked in the Camera Control's small menu (the
        /// index into CameraLens.allCases), and that menu shown or hidden.
        case lensPicked(Int)
        case bodyPicked(Int)
        case controls(active: Bool, fullscreen: Bool)
        /// Whether the camera in use has an ultra wide to go to 0.5×
        /// (the Duo's rear dual camera; the test picture's outer camera).
        case lenses(ultraWide: Bool)
        /// The zoom (as shown, 0.5–4×) changed by the system — the Camera
        /// Control's zoom slider on a camera that zooms itself.
        case zoomed(Double)
        /// The camera sends no picture (what to say), or it does again (nil).
        case blank(String?)
        /// Another camera is being put in place of the one in use because
        /// it now faces that way (the Duo opened or shut): the picture of
        /// the one before is no longer this side's.
        case switching
        /// The camera asked for could not be had (what to say); the one
        /// before is in again, and that is the side it serves.
        case switchFailed(String, stays: CameraSide)
    }

    var onFrame: (@Sendable (Frame) -> Void)?
    var onResult: (@Sendable (Result) -> Void)?
    var onEvent: (@Sendable (Event) -> Void)?

    private let queue = DispatchQueue(label: "FoldArc.camera.frames", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "FoldArc.camera.session", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false,
                                              .workingColorSpace: CameraLook.colorSpace, .outputColorSpace: CameraLook.colorSpace])
    private let lock = NSLock()
    // Shared with the main thread, under `lock`.
    private var settings = Settings()
    private var blowing = false
    private var request: Request?
    /// One picture as the camera gives it (before the module, the lens's
    /// finish and the body), asked for once and given from the frame
    /// queue: what the body menu's samples are made from.
    private var sampleWanted: (@Sendable (CGImage) -> Void)?
    func sample(_ done: @escaping @Sendable (CGImage) -> Void) {
        lock.lock(); sampleWanted = done; lock.unlock()
    }
    private var running = false
    // The frame queue's own.
    private var sparkles = SparkleField()
    private var afterimage: CGImage?
    private var frames = 0
    #if DEBUG
    /// Frames the camera has handed over since it last started (the frame queue's own).
    private var rawFrames = 0
    #endif
    #if DEBUG
    /// What the work costs, for the trace (the frame queue's own).
    private var cost = CameraCost()
    /// When the camera was asked to open (the system's uptime, s; under `lock`).
    private var openedAt = 0.0
    #endif
    /// The blank-picture check (the frame queue's own).
    private var blankFrames = 0
    private var flatChecks = 0
    private var blankShown: String?
    private var lastTime = 0.0
    private var face: CGRect?
    /// 暗处's brightening, following the scene (stops).
    private var lowLightEV = 1.0
    /// The scene's brightness (0…1) for the handheld module's look, kept
    /// a while (nil until measured).
    private var sceneMean: Double?
    private var testTimer: DispatchSourceTimer?
    private var testSide = CameraSide.outer
    /// A camera that zooms itself (the rear dual camera: its ultra
    /// wide below the switch-over, the wide above): the device zoom factor
    /// that shows as 1×. The picture is then not cropped for the zoom. Under
    /// `lock`.
    private var deviceZoomBase: Double?

    private var directionsWatch: NSObjectProtocol?
    override init() {
        super.init()
        #if os(iOS)
        directionsWatch = NotificationCenter.default.addObserver(forName: CameraDirections.changed, object: nil, queue: nil) { [weak self] _ in
            self?.directionsChanged()
        }
        #endif
    }
    deinit {
        if let directionsWatch { NotificationCenter.default.removeObserver(directionsWatch) }
    }

    func configure(_ next: Settings) {
        lock.lock()
        let changedLens = next.lens != settings.lens, changedZoom = next.zoom != settings.zoom
        let changedAngle = next.angle != settings.angle
        settings = next
        let zoomsItself = deviceZoomBase != nil
        lock.unlock()
        #if os(iOS)
        if changedAngle { applyAngle() }
        #endif
        if changedLens { queue.async { self.afterimage = nil; self.face = nil; if next.lens != .sparkle { self.sparkles = SparkleField() } } }
        #if os(iOS)
        if changedZoom && zoomsItself { applyDeviceZoom() }
        #endif
    }
    func setBlowing(_ value: Bool) { lock.lock(); blowing = value; lock.unlock() }
    func take(_ next: Request) { lock.lock(); request = next; lock.unlock() }

    // MARK: 录像 (11-06)

    /// The video being written (under the lock).
    private var recorder: CameraRecorder?
    /// Starts writing what the camera shows (and, `sound`, what the iPhone's
    /// microphone hears) into a new file in the app's temporary folder.
    func startRecording(sound: Bool) throws {
        let recorder = try CameraRecorder(url: CameraRecorder.temporaryURL(), audio: sound)
        lock.lock(); self.recorder = recorder; lock.unlock()
        #if os(iOS)
        if sound { sessionQueue.async { self.addMicrophone() } }
        #endif
        NSLog("[camera] video: recording%@", sound ? " with sound" : " (no sound)")
    }
    /// How long the video being written is so far (s).
    var recordedSeconds: Double {
        lock.lock(); let recorder = self.recorder; lock.unlock()
        return recorder?.seconds ?? 0
    }
    /// The video being written has stopped by itself.
    var recordingFailed: Bool {
        lock.lock(); let recorder = self.recorder; lock.unlock()
        return recorder?.failed ?? false
    }
    /// Ends the video: `done` has its finished file (on any queue).
    func stopRecording(_ done: @escaping @Sendable (Swift.Result<URL, CameraFailure>) -> Void) {
        lock.lock(); let recorder = self.recorder; self.recorder = nil; lock.unlock()
        #if os(iOS)
        sessionQueue.async { self.removeMicrophone() }
        #endif
        guard let recorder else { done(.failure(CameraFailure(message: String(localized: "没有在录像")))); return }
        // After the frame being made now.
        queue.async { recorder.finish(done) }
    }

    /// Whether this device has no camera to use, so the test picture is
    /// shown instead (the Simulator; `--foldarc-camera-test` on a device).
    static var usesTestPicture: Bool {
        #if os(iOS)
        #if targetEnvironment(simulator)
        if device(for: .outer) == nil && device(for: .inner) == nil { return true }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-camera-test") { return true }
        #endif
        return false
        #else
        return true
        #endif
    }

    // MARK: Starting and stopping

    func start(side: CameraSide) {
        lock.lock(); running = true; lock.unlock()
        #if DEBUG
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); openedAt = now; lock.unlock()
        queue.async { self.cost = CameraCost() }
        #endif
        // The layouts keep their safe area while it runs.
        let id = ObjectIdentifier(self)
        Task { @MainActor in CameraSteadyInsets.setCamera(true, feed: id) }
        if Self.usesTestPicture {
            startTestPicture(side: side)
        } else {
            #if os(iOS)
            startCapture(side: side)
            #endif
        }
    }
    func stop() {
        lock.lock(); running = false; let orphan = recorder; recorder = nil; lock.unlock()
        // (The model ends a recording before it stops the camera; one left
        // going is finished here so that its file is complete.)
        if let orphan {
            NSLog("[camera] video: still recording when the camera stopped")
            queue.async { orphan.finish { _ in } }
            #if os(iOS)
            sessionQueue.async { self.removeMicrophone() }
            #endif
        }
        let id = ObjectIdentifier(self)
        Task { @MainActor in CameraSteadyInsets.setCamera(false, feed: id) }
        queue.async {
            self.testTimer?.cancel(); self.testTimer = nil
            self.afterimage = nil; self.face = nil; self.lastTime = 0
            #if DEBUG
            if let line = self.cost.line(until: ProcessInfo.processInfo.systemUptime, load: { self.load }) { CameraCost.note(line + " (the camera stopped)") }
            #endif
        }
        #if os(iOS)
        sessionQueue.async {
            if let session = self.session, session.isRunning { session.stopRunning() }
        }
        #endif
    }
    func switchSide(_ side: CameraSide) {
        if Self.usesTestPicture {
            queue.async { self.testSide = side; self.afterimage = nil; self.face = nil; self.onEvent?(.lenses(ultraWide: side == .outer)) }
        } else {
            #if os(iOS)
            startCapture(side: side)
            #endif
        }
    }

    private func startTestPicture(side: CameraSide) {
        queue.async { [weak self] in
            guard let self else { return }
            self.testSide = side
            guard self.testTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let time = Date().timeIntervalSinceReferenceDate
                self.lock.lock(); let zoom = self.settings.zoom; self.lock.unlock()
                // The test picture's outer camera stands in for a rear
                // dual camera: below 1× it draws the scene from further back.
                let wide = self.testSide == .outer && zoom < 0.99
                guard let picture = CameraTestScene.frame(side: self.testSide, time: time, wide: wide) else { return }
                self.process(CIImage(cgImage: picture), side: self.testSide, time: time)
            }
            self.testTimer = timer
            timer.resume()
            self.onEvent?(.running(test: true))
            self.onEvent?(.lenses(ultraWide: side == .outer))
        }
    }

    // MARK: The iPhone's cameras

    #if os(iOS)
    private var session: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    /// Round 32 (相机控制): the session's controls for the Camera Control's
    /// light press — FoldArc's lenses, the system's zoom for the device in
    /// use — and the delegate they need to become active.
    private var lensPicker: AVCaptureIndexPicker?
    private var bodyPicker: AVCaptureIndexPicker?
    private var zoomSlider: AVCaptureSystemZoomSlider?
    private let controlsWatcher = CaptureControlsWatcher()
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationWatch: NSKeyValueObservation?
    private var watches: [NSObjectProtocol] = []
    private var captureSide = CameraSide.outer

    /// 内侧 is the camera facing the person looking at the display
    /// FoldArc is on, 外侧 the one facing away (the handheld's two sides).
    /// On iPhone Duo that is the cover's own camera with the lid shut and the
    /// inner one open, and the rear dual camera either way: iOS 27.1's
    /// direction map says so where it has been read (CameraDirections);
    /// otherwise by position — the front camera, which on Duo follows the
    /// display in use (the Duo's front cameras are ultra wides, so those
    /// count too), and the back one, the dual (wide + ultra wide) camera
    /// first, for 0.5×.
    static func device(for side: CameraSide) -> AVCaptureDevice? {
        if side == .inner, CameraTry.virtualFront,
           let front = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front).devices.first {
            return front
        }
        for id in CameraDirections.shared.uniqueIDs(facing: side) {
            if let device = AVCaptureDevice(uniqueID: id) { return device }
        }
        let types: [AVCaptureDevice.DeviceType] = side == .inner
            ? [.builtInWideAngleCamera, .builtInUltraWideCamera]
            : [.builtInDualWideCamera, .builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video,
                                                position: side == .inner ? .front : .back).devices.first
    }
    /// The direction map changed (the console opened or shut, so the
    /// display changed): the camera in use is swapped if another one now
    /// faces that way.
    func directionsChanged() {
        sessionQueue.async {
            self.lock.lock(); let wanted = self.running; let side = self.requestedSide; self.lock.unlock()
            guard wanted, let current = self.input?.device, let next = Self.device(for: side), next.uniqueID != current.uniqueID else { return }
            NSLog("[camera] directions changed: %@ camera now %@", side.rawValue, next.localizedName)
            // The frames the camera before still sends are not this side's
            // picture any more: dropped until the new one is in, and said
            // (the picture is taken off, the shutter waits).
            self.lock.lock(); self.swapping = true; self.lock.unlock()
            self.onEvent?(.switching)
            self.startCapture(side: side)
        }
    }
    private var requestedSide = CameraSide.outer
    /// A camera is being put in place of the one in use (under the lock).
    private var swapping = false
    /// The system's angle for the picture as it last was (under the lock):
    /// a new connection begins at it.
    private var lastSystemAngle: Double?
    private var zoomWatch: NSKeyValueObservation?
    /// The iPhone Duo's black pictures: a camera the system has
    /// suspended (AVCaptureDevice.isSuspended: "some devices disallow data
    /// capture due to a feature on the device") sends black frames; that is
    /// said on the screen instead of a black picture.
    private var suspendWatch: NSKeyValueObservation?
    #if DEBUG
    /// The session, for the DEBUG preview layer beside FoldArc's own picture.
    nonisolated(unsafe) static weak var debugSession: AVCaptureSession?
    #endif
    /// The zoom as shown (0.5–4×) as the device's own zoom factor.
    private func applyDeviceZoom() {
        sessionQueue.async {
            self.lock.lock(); let base = self.deviceZoomBase; let zoom = self.settings.zoom; self.lock.unlock()
            guard let base, let device = self.input?.device else { return }
            let factor = min(max(CGFloat(zoom * base), device.minAvailableVideoZoomFactor), min(device.maxAvailableVideoZoomFactor, CGFloat(base * 8)))
            guard abs(device.videoZoomFactor - factor) > 0.001 else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
            } catch {
                NSLog("[camera] zoom %.1f not set: %@", zoom, error.localizedDescription)
            }
        }
    }

    private func startCapture(side: CameraSide) {
        lock.lock(); requestedSide = side; lock.unlock()
        sessionQueue.async {
            let session = self.session ?? self.makeSession()
            let device = Self.device(for: side) ?? Self.device(for: side.other)
            guard let device else {
                self.lock.lock(); self.swapping = false; self.lock.unlock()
                self.onEvent?(.failed(String(localized: "这台 iPhone 上没有找到摄像头")))
                return
            }
            session.beginConfiguration()
            let before = self.input
            if let before { session.removeInput(before); self.input = nil }
            var why: String?
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input); self.input = input }
            } catch {
                why = error.localizedDescription
            }
            if self.input == nil {
                // The camera asked for cannot be had: the one before goes
                // back in (its picture stays), and it is said; with none to
                // go back to, the camera has failed.
                if let before, session.canAddInput(before) { session.addInput(before); self.input = before }
                session.commitConfiguration()
                self.lock.lock(); self.swapping = false; let stays = self.captureSide; self.lock.unlock()
                NSLog("[camera] %@ camera: %@ cannot be used (%@); %@", side.rawValue, device.localizedName, why ?? "the session does not take it",
                      self.input == nil ? "no camera now" : "the one before is in again")
                if self.input == nil {
                    self.onEvent?(.failed(why.map { String(localized: "打不开摄像头：\($0)") } ?? String(localized: "打不开摄像头")))
                } else {
                    self.onEvent?(.switchFailed(String(localized: "这个镜头现在用不了，还是原来那个"), stays: stays))
                }
                return
            }
            // Round 32: the zoom slider in the Camera Control's menu is the
            // device's (the inner and outer cameras differ): the old one out,
            // this device's in.
            if session.supportsControls, !CameraTry.plain {
                if let old = self.zoomSlider { session.removeControl(old); self.zoomSlider = nil }
                let slider = AVCaptureSystemZoomSlider(device: device)
                if session.canAddControl(slider) { session.addControl(slider); self.zoomSlider = slider }
                else { NSLog("[camera] controls: the zoom slider cannot be added (%d of %d)", session.controls.count, session.maxControlsCount) }
            }
            // 720p from the camera: the module's 4:3 is cut out of it upright
            // however the iPhone is held, and made 640 × 480.
            if CameraTry.hd1080, session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
            else if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
            else if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
            if !session.outputs.contains(self.output), session.canAddOutput(self.output) { session.addOutput(self.output) }
            // Mirrored when it faces the person looking at the display (as a
            // mirror is), by the direction map where there is one.
            let front = CameraDirections.shared.isForward(device.uniqueID) ?? (device.position == .front)
            if let connection = self.output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
            // A new input makes a new connection, at the system's own angle:
            // it begins at the one last known (the cover's hold, or what the
            // system last said), so that its first frames are already the
            // right way up; what the system says for this camera follows.
            self.lock.lock(); let known = self.settings.angle ?? self.lastSystemAngle; self.lock.unlock()
            if let known, let connection = self.output.connection(with: .video),
               connection.isVideoRotationAngleSupported(known), connection.videoRotationAngle != known {
                connection.videoRotationAngle = known
            }
            session.commitConfiguration()
            // The rear dual camera zooms itself (0.5× is its ultra
            // wide): 1× is where its wide takes over.
            let base: Double? = device.isVirtualDevice && device.deviceType == .builtInDualWideCamera
                ? (device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 2) : nil
            self.lock.lock(); self.captureSide = front ? .inner : .outer; self.deviceZoomBase = base; self.swapping = false; self.lock.unlock()
            self.zoomWatch = nil
            let report = self.onEvent
            self.suspendWatch = device.observe(\.isSuspended, options: [.initial, .new]) { device, _ in
                NSLog("[camera] %@ %@", device.localizedName, device.isSuspended ? "suspended by the system" : "not suspended")
                report?(device.isSuspended ? .interrupted(String(localized: "系统暂停了这个镜头（画面会是黑的）")) : .resumed)
            }
            if let base {
                // The handler is the feed's (set when the camera opens); the
                // feed itself is not held by the watch.
                let report = self.onEvent
                self.zoomWatch = device.observe(\.videoZoomFactor, options: [.new]) { device, _ in
                    report?(.zoomed(Double(device.videoZoomFactor) / base))
                }
                self.applyDeviceZoom()
            }
            NSLog("[camera] %@ camera: %@ (%@%@)", side.rawValue, device.localizedName, device.deviceType.rawValue, base.map { String(format: ", 1× at zoom %.1f", $0) } ?? "")
            self.onEvent?(.lenses(ultraWide: base != nil))
            self.queue.async {
                self.afterimage = nil; self.face = nil
                #if DEBUG
                self.rawFrames = 0
                #endif
                self.blankFrames = 0; self.flatChecks = 0
                if self.blankShown != nil { self.blankShown = nil; self.onEvent?(.blank(nil)) }
            }
            #if DEBUG
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let sub = CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)
            let fourCC = String((0..<4).map { Character(UnicodeScalar(UInt8((sub >> (8 * (3 - $0))) & 0xFF))) })
            NSLog("[camera] session: %d input(s), %d output(s), preset %@, format %dx%d %@ (%@, virtual %d), %d control(s), tries: %@, %@",
                  session.inputs.count, session.outputs.count, session.sessionPreset.rawValue, dims.width, dims.height, fourCC,
                  device.deviceType.rawValue, device.isVirtualDevice ? 1 : 0, session.controls.count,
                  CameraTry.summary.isEmpty ? "none" : CameraTry.summary, session.inputs.isEmpty ? "NO INPUT" : "input in")
            // The system's video effects (Control Center's 视频效果),
            // which the iPhone's own Camera never has, as they stand for FoldArc.
            var effects: [String] = []
            if AVCaptureDevice.isPortraitEffectEnabled { effects.append("portrait") }
            if AVCaptureDevice.isStudioLightEnabled { effects.append("studio light") }
            if AVCaptureDevice.reactionEffectsEnabled { effects.append("reactions") }
            if AVCaptureDevice.isBackgroundReplacementEnabled { effects.append("background") }
            if AVCaptureDevice.isCenterStageEnabled { effects.append("center stage") }
            if #available(iOS 26.2, *), AVCaptureDevice.isEdgeLightEnabled { effects.append("edge light") }
            NSLog("[camera] video effects on for FoldArc: %@", effects.isEmpty ? "none" : effects.joined(separator: ", "))
            #endif
            if !CameraTry.plain { DispatchQueue.main.async { self.followRotation(of: device) } }
            self.lock.lock(); let wanted = self.running; self.lock.unlock()
            if wanted, !session.isRunning { session.startRunning() }
            #if DEBUG
            self.lock.lock(); let opened = self.openedAt; self.lock.unlock()
            CameraCost.note(String(format: "the session runs %.0f ms after opening", (ProcessInfo.processInfo.systemUptime - opened) * 1000))
            #endif
            self.onEvent?(.running(test: false))
        }
    }

    // 录像: the microphone joins the session while a video takes
    // sound (and leaves it after: the iPhone's microphone light is on only then).
    private let soundOutput = AVCaptureAudioDataOutput()
    private let soundQueue = DispatchQueue(label: "FoldArc.camera.sound", qos: .userInitiated)
    private var soundInput: AVCaptureDeviceInput?
    /// On the session queue.
    private func addMicrophone() {
        guard let session, soundInput == nil else { return }
        guard let microphone = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: microphone) else {
            NSLog("[camera] video: no microphone to record from")
            return
        }
        AudioPolicy.shared.setRecording(true)
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input); soundInput = input }
        if !session.outputs.contains(soundOutput), session.canAddOutput(soundOutput) {
            session.addOutput(soundOutput)
            soundOutput.setSampleBufferDelegate(self, queue: soundQueue)
        }
        session.commitConfiguration()
        NSLog("[camera] video: microphone %@ (%@)", soundInput == nil ? "not added" : "on", microphone.localizedName)
    }
    /// On the session queue.
    private func removeMicrophone() {
        guard soundInput != nil || session?.outputs.contains(soundOutput) == true else { return }
        if let session {
            session.beginConfiguration()
            if let soundInput { session.removeInput(soundInput) }
            if session.outputs.contains(soundOutput) { session.removeOutput(soundOutput) }
            session.commitConfiguration()
        }
        soundInput = nil
        AudioPolicy.shared.setRecording(false)
        NSLog("[camera] video: microphone off")
    }

    private func makeSession() -> AVCaptureSession {
        let session = AVCaptureSession()
        // 录像: the app's audio session is AudioPolicy's (play and
        // record from the speaker while a video takes sound), not the camera's.
        session.automaticallyConfiguresApplicationAudioSession = false
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: CameraTry.yuv ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        let center = NotificationCenter.default
        watches.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            let reason = raw.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
            self?.onEvent?(.interrupted(Self.describe(reason)))
        })
        watches.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.onEvent?(.resumed)
        })
        watches.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.onEvent?(.failed(String(localized: "相机出错了") + (error.map { String(localized: "：\($0.localizedDescription)") } ?? "")))
            // Try once more, as the camera app would after a hiccup.
            self?.sessionQueue.asyncAfter(deadline: .now() + 1) {
                guard let self, let session = self.session, !session.isRunning else { return }
                self.lock.lock(); let wanted = self.running; self.lock.unlock()
                if wanted { session.startRunning(); if session.isRunning { self.onEvent?(.resumed) } }
            }
        })
        if !CameraTry.plain { installControls(on: session) }
        self.session = session
        #if DEBUG
        Self.debugSession = session
        #endif
        return session
    }

    /// Round 32 (相机控制): the Camera Control's light press slides the
    /// session's controls over the picture — FoldArc's seven lenses as an
    /// index picker (the zoom slider joins per device in startCapture). The
    /// session only shows them with a controls delegate set; the picker's
    /// action and its `selectedIndex` live on the session queue.
    private func installControls(on session: AVCaptureSession) {
        guard session.supportsControls else { NSLog("[camera] controls: not supported here"); return }
        let picker = AVCaptureIndexPicker(String(localized: "镜头"), symbolName: "camera.filters", localizedIndexTitles: CameraLens.allCases.map(\.title))
        picker.accessibilityIdentifier = "camera-control-lens"
        picker.setActionQueue(sessionQueue) { [weak self] index in
            NSLog("[camera] controls: lens %d picked", index)
            self?.onEvent?(.lensPicked(index))
        }
        if session.canAddControl(picker) { session.addControl(picker); lensPicker = picker }
        else { NSLog("[camera] controls: the lens picker cannot be added") }
        // Round 32 (机型): the simulated bodies, the same way.
        let bodies = AVCaptureIndexPicker(String(localized: "机型"), symbolName: "camera.on.rectangle", localizedIndexTitles: CameraBody.allCases.map(\.title))
        bodies.accessibilityIdentifier = "camera-control-body"
        bodies.setActionQueue(sessionQueue) { [weak self] index in
            NSLog("[camera] controls: body %d picked", index)
            self?.onEvent?(.bodyPicked(index))
        }
        if session.canAddControl(bodies) { session.addControl(bodies); bodyPicker = bodies }
        else { NSLog("[camera] controls: the body picker cannot be added") }
        controlsWatcher.onChange = { [weak self] active, fullscreen in self?.onEvent?(.controls(active: active, fullscreen: fullscreen)) }
        session.setControlsDelegate(controlsWatcher, queue: sessionQueue)
        NSLog("[camera] controls: %d installed (max %d)", session.controls.count, session.maxControlsCount)
    }
    /// The lens and the body chosen on the screens, shown in the Camera
    /// Control's menu too.
    func syncControls(lens: CameraLens? = nil, body: CameraBody? = nil) {
        let lensIndex = lens.flatMap { CameraLens.allCases.firstIndex(of: $0) }
        let bodyIndex = body.flatMap { CameraBody.allCases.firstIndex(of: $0) }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let lensIndex, let picker = self.lensPicker, picker.selectedIndex != lensIndex { picker.selectedIndex = lensIndex }
            if let bodyIndex, let picker = self.bodyPicker, picker.selectedIndex != bodyIndex { picker.selectedIndex = bodyIndex }
        }
    }

    private static func describe(_ reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceInUseByAnotherClient?: return String(localized: "摄像头正被别的 App 使用")
        case .videoDeviceNotAvailableWithMultipleForegroundApps?: return String(localized: "同时开着别的 App 时不能用相机")
        case .videoDeviceNotAvailableDueToSystemPressure?: return String(localized: "iPhone 太热了，相机先停一下")
        case .videoDeviceNotAvailableInBackground?: return String(localized: "Zero EMU 不在前台时不能用相机")
        default: return String(localized: "相机暂时不能用")
        }
    }

    /// The picture stays level with the horizon however the iPhone is held
    /// (in 90° steps, as the iPhone's own camera turns it).
    private func followRotation(of device: AVCaptureDevice) {
        rotationWatch = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotation = coordinator
        let name = device.localizedName
        rotationWatch = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            // 11-15 (the picture not turning with the hold, on the phone): the
            // angle each time it changes, beside the hold, in the run's trace.
            DispatchQueue.main.async {
                OrientationTrace.shared.event("camera picture angle -> \(Int(angle)) (\(name); device \(UIDevice.current.orientation.rawValue))")
            }
            self?.applyAngle(system: angle)
        }
    }
    /// The angle the picture is turned by: the one set from outside
    /// (Settings.angle), else the system's (`system`, or its last).
    private func applyAngle(system: Double? = nil) {
        lock.lock(); let fixed = settings.angle; if let system { lastSystemAngle = system }; lock.unlock()
        let angle = fixed ?? system ?? rotation?.videoRotationAngleForHorizonLevelCapture ?? 0
        sessionQueue.async { [weak self] in
            guard let self, let connection = self.output.connection(with: .video) else { return }
            guard connection.isVideoRotationAngleSupported(angle) else {
                let kept = connection.videoRotationAngle
                DispatchQueue.main.async { OrientationTrace.shared.event("camera picture angle \(Int(angle)) not supported: left at \(Int(kept))") }
                return
            }
            guard connection.videoRotationAngle != angle else { return }
            connection.videoRotationAngle = angle
            if fixed != nil { DispatchQueue.main.async { OrientationTrace.shared.event("camera picture angle set -> \(Int(angle)) (the cover's hold)") } }
        }
    }
    #endif

    // MARK: A frame

    /// A frame through the camera's work. A DEBUG build keeps what it cost
    /// (`CameraCost`: lines in the trace).
    fileprivate func process(_ frame: CIImage, side: CameraSide, time: Double) {
        #if DEBUG
        let began = ProcessInfo.processInfo.systemUptime
        work(frame, side: side, time: time)
        let ended = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let subject = CameraCost.Subject(body: settings.body.rawValue, lens: settings.lens.rawValue, recording: recorder != nil)
        let wanted = running, opened = openedAt
        lock.unlock()
        guard wanted else { return }
        for line in cost.frame(from: began, to: ended, subject: subject, opened: opened, load: { self.load }) { CameraCost.note(line) }
        #else
        work(frame, side: side, time: time)
        #endif
    }
    #if DEBUG
    /// What the system says of its load now: the camera's pressure (and
    /// what it comes from), the iPhone's heat.
    private var load: String {
        var parts: [String] = []
        #if os(iOS)
        if let state = input?.device.systemPressureState {
            parts.append("pressure " + state.level.rawValue.replacingOccurrences(of: "AVCaptureSystemPressureLevel", with: "").lowercased()
                         + (state.factors.rawValue == 0 ? "" : " (factors \(state.factors.rawValue))"))
        }
        #endif
        parts.append("heat \(ProcessInfo.processInfo.thermalState.rawValue)")
        return parts.joined(separator: ", ")
    }
    #endif

    private func work(_ frame: CIImage, side: CameraSide, time: Double) {
        lock.lock()
        let settings = self.settings, blowing = self.blowing, request = self.request, wanted = running
        self.request = nil
        lock.unlock()
        guard wanted else { return }
        frames += 1
        let dt = lastTime == 0 ? 1.0 / 30 : min(0.1, max(0, time - lastTime))
        lastTime = time
        // 暗处 works at half the frame rate (a longer exposure), as dim-light
        // modes do; a picture asked for is taken at once.
        if settings.lens == .lowLight, request == nil, frames % 2 == 1 { return }
        let grain = settings.lens == .lowLight ? 0.13 : 0.075
        lock.lock(); let zoomsItself = deviceZoomBase != nil; lock.unlock()
        let crop = zoomsItself ? 1 : max(1, settings.zoom)
        let raw = CameraLook.sensor(frame, zoom: crop)
        lock.lock(); let sampleWanted = self.sampleWanted; self.sampleWanted = nil; lock.unlock()
        if let sampleWanted, let plain = context.createCGImage(raw, from: CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace) {
            sampleWanted(plain)
        }
        // The room's light, for the handheld module's own look (a few times a second).
        if settings.body == .native, frames % 8 == 1 || sceneMean == nil, let measured = meanBrightness(of: raw) {
            sceneMean = sceneMean.map { $0 + (measured - $0) * 0.35 } ?? measured
        }
        let sensor = settings.body == .native
            ? CameraLook.module3DS(raw, grain: grain, seed: frames, mean: sceneMean ?? 0.45)
            : CameraLook.given(raw, body: settings.body, grain: grain, seed: frames)
        if settings.lens == .lowLight, frames % 4 == 0 || afterimage == nil, let mean = meanBrightness(of: sensor) {
            lowLightEV += (CameraLook.lowLightGain(mean: mean) - lowLightEV) * (afterimage == nil ? 1 : 0.35)
        }
        var finished = CameraLook.finish(sensor, lens: settings.lens, gain: lowLightEV)
        if settings.lens == .lowLight {
            // The light of the frames before stays a moment: moving things trail.
            if let before = afterimage {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = CIImage(cgImage: before)
                mix.targetImage = finished
                mix.time = 0.45
                finished = (mix.outputImage ?? finished).cropped(to: CameraLook.photoRect)
            }
            afterimage = context.createCGImage(finished, from: CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace)
        }
        if settings.lens.adjustable { finished = CameraLook.manual(finished, settings.manual) }
        // 11-06: the shooting settings (exposure, white balance, ISO) — the
        // sensor's, so before the body.
        if !settings.shooting.isDefault { finished = CameraBodyLook.shoot(finished, settings.shooting, seed: frames) }
        // Round 32 (机型): the body's look over the lens's finish (its date
        // is now; a picture taken keeps this frame's).
        // The picture before the body (a taken picture is developed again
        // with what only a still gets — the JPEG blocks, the flash — from this).
        let undeveloped = finished
        // The cover's deck: the part of the picture kept (a date goes inside it).
        let shape = settings.aspect?.crop
        if settings.body != .native { finished = CameraBodyLook.develop(finished, body: settings.body, strength: settings.strength, seed: frames, date: Date(), frame: shape) }
        // The date the camera prints, when the body has none of its own.
        let printsDate = settings.shooting.dateStamp && !settings.body.hasDateStamp
        if printsDate { finished = CameraBodyLook.dateStamp(finished, date: Date(), frame: shape) }
        if settings.lens == .sparkle { sparkles.step(dt: dt, blowing: blowing) }
        // 合体: where the face is, five times a second.
        if settings.lens == .merge {
            if frames % 6 == 0 { face = CameraFaces.find(in: finished, eyes: false)?.box }
        } else {
            face = nil
        }
        // 录像: the frame, as shown, into the video being written.
        lock.lock(); let recorder = self.recorder; lock.unlock()
        if let recorder {
            if settings.lens == .sparkle, !sparkles.isEmpty,
               let picture = context.createCGImage(finished, from: CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace),
               let drawn = sparkles.drawn(over: picture) {
                recorder.append(drawn, at: time)
            } else {
                recorder.append(finished, context: context, at: time)
            }
        }
        let shown = shape.map { CameraLook.shaped(finished, $0) } ?? CameraBodyLook.screen(finished, body: settings.body)
        let shownSize = shape.map { CGSize(width: $0.width * CameraLook.shapedScale, height: $0.height * CameraLook.shapedScale) } ?? CameraLook.screenSize
        guard var screen = context.createCGImage(shown, from: CGRect(origin: .zero, size: shownSize),
                                                 format: .RGBA8, colorSpace: CameraLook.colorSpace) else { return }
        if settings.lens == .sparkle, !sparkles.isEmpty, let drawn = sparkles.drawn(over: screen) { screen = drawn }
        onFrame?(Frame(screen: screen, face: face, side: side))
        if let request {
            // The flash fires for the picture only (自动: when it is dark).
            let fires: Bool
            switch settings.shooting.flash {
            case .off: fires = false
            case .on, .redEye: fires = true
            case .auto: fires = (meanBrightness(of: undeveloped) ?? 1) < 0.32
            }
            var still = finished
            // 两联 keeps the middle of each picture: what a body prints on a
            // picture (bars, its date, the paper) and the 日期 setting's date
            // would be cut with it, so its pictures come without, and it is
            // printed on the sheet they are laid on (CameraSheets.printed).
            let onSheet = settings.lens == .pair
            if fires || onSheet || (settings.body != .native && settings.body.recipe.jpegQuality < 1) {
                let lit = fires ? CameraBodyLook.flashLit(undeveloped) : undeveloped
                if settings.body == .native {
                    still = lit
                } else if onSheet {
                    still = CameraBodyLook.look(lit, recipe: settings.body.recipe, strength: settings.strength, seed: frames, still: true)
                } else {
                    still = CameraBodyLook.develop(lit, body: settings.body, strength: settings.strength, seed: frames, date: Date(), still: true, frame: shape)
                }
                if printsDate, !onSheet { still = CameraBodyLook.dateStamp(still, date: Date(), frame: shape) }
            }
            if fires { NSLog("[camera] flash fired (%@)", settings.shooting.flash.rawValue) }
            capture(request, finished: still, settings: settings)
        }
    }

    /// The picture's mean brightness (0…1).
    private func meanBrightness(of image: CIImage) -> Double? {
        let f = CIFilter.areaAverage()
        f.inputImage = image
        f.extent = CameraLook.photoRect
        guard let output = f.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CameraLook.colorSpace)
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
    }

    private func capture(_ request: Request, finished: CIImage, settings: Settings) {
        func render(_ image: CIImage, _ part: CGRect? = nil) -> CGImage? {
            context.createCGImage(image, from: part ?? CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace)
        }
        switch request {
        case .single:
            var image = finished
            var note: String?
            if settings.lens == .mystery {
                let kind = CameraLook.Mystery.allCases.randomElement() ?? .negative
                image = CameraLook.mystery(image, kind, hue: Double.random(in: 0..<1))
                note = kind.title
            }
            // The cover's shapes: the part kept is the picture.
            guard var picture = render(image, settings.aspect?.crop) else { onResult?(.failed(String(localized: "没拍下来，再试一次"))); return }
            if settings.lens == .sparkle, let drawn = sparkles.drawn(over: picture) { picture = drawn }
            // 小票: the picture kept is the till's slip, printed in dots under
            // ZERO, the time and the number it is saved under (one of several
            // laid on a sheet: in dots only, at its own size).
            if let thermal = settings.body.recipe.thermal {
                let printed: CGImage? = settings.lens.sheetCount > 1
                    ? CameraReceiptPrint.dots(picture, thermal: thermal, strength: settings.strength)
                    : CameraReceiptPrint.slip(picture, thermal: thermal, strength: settings.strength, date: Date(), number: CameraReceiptPrint.nextNumber())
                if let printed { picture = printed }
            }
            onResult?(.photo(picture, note: note))
        case .mergeFirst:
            guard let picture = render(finished) else { onResult?(.failed(String(localized: "没拍下来，再试一次"))); return }
            onResult?(.mergePart(CameraMergePart(image: picture, face: CameraFaces.find(in: finished, eyes: true))))
        case .mergeSecond(let first):
            guard let picture = render(finished) else { onResult?(.failed(String(localized: "没拍下来，再试一次"))); return }
            let second = CameraMergePart(image: picture, face: CameraFaces.find(in: finished, eyes: true))
            guard let merged = render(CameraMerge.merge(first, second, context: context)) else { onResult?(.failed(String(localized: "没合成出来，再试一次"))); return }
            // 小票: the two merged, printed on the till's slip.
            if let thermal = settings.body.recipe.thermal,
               let slip = CameraReceiptPrint.slip(merged, thermal: thermal, strength: settings.strength, date: Date(), number: CameraReceiptPrint.nextNumber()) {
                onResult?(.photo(slip, note: nil))
                return
            }
            onResult?(.photo(merged, note: nil))
        }
    }
}

#if os(iOS)
extension CameraFeed: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 录像: the microphone's sound, while a video is written.
        if output is AVCaptureAudioDataOutput {
            lock.lock(); let recorder = self.recorder; lock.unlock()
            recorder?.appendSound(sampleBuffer)
            return
        }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        lock.lock(); let side = captureSide; let swapping = self.swapping; lock.unlock()
        // (While another camera is being put in, the one before still sends.)
        guard !swapping else { return }
        let frame = CIImage(cvPixelBuffer: buffer)
        #if DEBUG
        // The iPhone Duo: what the camera
        // itself hands over, before any of the module's look — a few frames
        // after each start.
        rawFrames += 1
        if [1, 15, 60, 150].contains(rawFrames) || rawFrames % 600 == 0 { describeRaw(frame, buffer: buffer, connection: connection) }
        #endif
        blankFrames += 1
        if blankFrames % 15 == 0 { checkBlank(frame) }
        process(frame, side: side, time: time.isFinite ? time : Date().timeIntervalSinceReferenceDate)
    }
    /// A frame the camera made and did not hand over (the work on the
    /// ones before took too long, or their buffers were still held): a DEBUG
    /// build counts them, with the reason the system gives.
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        #if DEBUG
        guard output is AVCaptureVideoDataOutput else { return }
        cost.drop(CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) as? String)
        #endif
    }
    /// On the iPhone Duo: frames that come
    /// flat and dark — every pixel the same — are no picture at all. If the
    /// camera's exposure says the lens sees light (an ISO well under its
    /// highest, near its target), the system is not handing the picture over
    /// (976/981: ISO ~340 at 1/60 s, on target, every frame flat; the
    /// iPhone's own Camera black too); otherwise the lens is covered or it
    /// is dark. Said over the picture (the shutter waits) instead of a black
    /// picture; checked twice a second, said after three flat checks.
    private func checkBlank(_ frame: CIImage) {
        let f = CIFilter.areaMinMax()
        f.inputImage = frame
        f.extent = frame.extent
        guard let output = f.outputImage else { return }
        var px = [UInt8](repeating: 0, count: 8)
        context.render(output, toBitmap: &px, rowBytes: 8, bounds: CGRect(x: 0, y: 0, width: 2, height: 1), format: .RGBA8, colorSpace: CameraLook.colorSpace)
        let flat = (0..<3).allSatisfy { Int(px[4 + $0]) - Int(px[$0]) <= 4 && px[4 + $0] <= 28 }
        flatChecks = flat ? flatChecks + 1 : 0
        var message: String?
        if flatChecks >= 3 {
            let device = input?.device
            let lit = device.map { $0.iso < $0.activeFormat.maxISO * 0.6 && $0.exposureTargetOffset > -2 } ?? false
            message = lit ? String(localized: "摄像头没有送来画面\n（iPhone 自带的相机也黑的话，重启 iPhone 再试）") : String(localized: "画面一片黑：镜头被挡住了，或者太暗")
        }
        guard message != blankShown else { return }
        blankShown = message
        NSLog("[camera] %@", message.map { "no picture: " + $0.replacingOccurrences(of: "\n", with: " ") } ?? "the picture is back")
        onEvent?(.blank(message))
    }
    #if DEBUG
    /// The raw frame's size, format and average colour, and how the camera
    /// exposed it (a dark scene: a long exposure at a high ISO; a frame black
    /// for another reason: a short one at a low ISO).
    private func describeRaw(_ frame: CIImage, buffer: CVPixelBuffer, connection: AVCaptureConnection) {
        let f = CIFilter.areaAverage()
        f.inputImage = frame
        f.extent = frame.extent
        var pixel = [UInt8](repeating: 0, count: 4)
        if let output = f.outputImage {
            context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CameraLook.colorSpace)
        }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let code = String((0..<4).map { Character(UnicodeScalar(UInt8((format >> (8 * (3 - $0))) & 0xFF))) })
        let device = input?.device
        let exposure = device.map { String(format: "%.4f s, ISO %.0f, offset %.2f", $0.exposureDuration.seconds, $0.iso, $0.exposureTargetOffset) } ?? "no device"
        let access: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = "authorized"
        case .denied: access = "denied"
        case .restricted: access = "restricted"
        case .notDetermined: access = "not determined"
        @unknown default: access = "other"
        }
        let state = "suspended \(device?.isSuspended == true ? 1 : 0), access \(access), running \(session?.isRunning == true ? 1 : 0), interrupted \(session?.isInterrupted == true ? 1 : 0)"
        NSLog("[camera] raw frame %d: %dx%d %@, average %d/%d/%d, %@ (%@), rotation %.0f, mirrored %d, %@; bytes %@",
              rawFrames, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), code,
              Int(pixel[0]), Int(pixel[1]), Int(pixel[2]), exposure, device?.localizedName ?? "-",
              connection.videoRotationAngle, connection.isVideoMirrored ? 1 : 0, state, Self.sampleBytes(buffer))
    }
    /// The frame's own bytes, read straight from the buffer (not
    /// through Core Image): the lowest, highest and mean brightness of 144
    /// points across it (BGRA: (B + 2G + R) / 4; YUV: Y), and the colour
    /// tags the camera put on it. A picture has a spread; a blanked frame none.
    static func sampleBytes(_ buffer: CVPixelBuffer) -> String {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        let w = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let h = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        var low = 255, high = 0, sum = 0, count = 0
        if let base, w > 1, h > 1 {
            let p = base.assumingMemoryBound(to: UInt8.self)
            for gy in 0..<12 {
                for gx in 0..<12 {
                    let x = (w - 1) * gx / 11, y = (h - 1) * gy / 11
                    let o = y * rowBytes + x * (planar ? 1 : 4)
                    let v = planar ? Int(p[o]) : (Int(p[o]) + 2 * Int(p[o + 1]) + Int(p[o + 2])) / 4
                    low = min(low, v); high = max(high, v); sum += v; count += 1
                }
            }
        }
        let tags = (CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any]) ?? [:]
        func tag(_ key: CFString) -> String { (tags[key as String] as? String).map { $0.replacingOccurrences(of: "ITU_R_", with: "") } ?? "-" }
        let surface = CVPixelBufferGetIOSurface(buffer) != nil
        return count == 0 ? "none (no base address)" : String(format: "min %d max %d mean %d of %d points, %@/%@/%@, %@",
                                                              low, high, sum / count, count, tag(kCVImageBufferColorPrimariesKey),
                                                              tag(kCVImageBufferTransferFunctionKey), tag(kCVImageBufferYCbCrMatrixKey),
                                                              surface ? "IOSurface" : "no IOSurface")
    }
    #endif
}

// MARK: - The level

/// 水平仪: how far the console is turned from level, from the iPhone's
/// motion sensor (none in the Simulator).
@MainActor final class CameraLevel {
    private let motion = CMMotionManager()
    var available: Bool { motion.isDeviceMotionAvailable }

    /// `update` gets the roll in radians: positive when the right side of
    /// the upper screen is low.
    func start(_ update: @escaping @MainActor (Double) -> Void) {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let g = data?.gravity else { return }
            let x = g.x, y = g.y
            MainActor.assumeIsolated { update(Self.roll(x: x, y: y, orientation: Self.interfaceOrientation())) }
        }
    }
    func stop() { motion.stopDeviceMotionUpdates() }

    nonisolated static func roll(x: Double, y: Double, orientation: UIInterfaceOrientation) -> Double {
        switch orientation {
        case .landscapeLeft: return atan2(y, x)
        case .landscapeRight: return atan2(-y, -x)
        case .portraitUpsideDown: return atan2(-x, y)
        default: return atan2(x, -y)
        }
    }
    private static func interfaceOrientation() -> UIInterfaceOrientation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive && $0.session.role == .windowApplication }
        return scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }
}
#endif

// MARK: - 小票: the till's slip

/// 小票 (CameraBody.receipt): a picture kept is the slip a till prints — the
/// picture in dots as its CameraThermal says, under ZERO, the date and the
/// time and the number the picture is saved under (the next one on the
/// card); the paper a little warm, a worn line down it, paler towards its
/// end. The slip is the whole picture that is kept and that goes into Photos
/// (CameraRoll keeps it as any picture); the silver coat over its photo is
/// the cover's own (the cash register's back), never on the slip.
enum CameraReceiptPrint {
    /// The slip's width in pixels (a narrow till roll; a width no camera or
    /// screen gives a picture, so that a slip read back is known by it), the
    /// rows over its photo and under it, the paper beside it.
    static let width = 732
    static let head = 350
    static let foot = 120
    static let side = 36
    static var photoWidth: Int { width - 2 * side }

    /// A picture of this size is a slip (read back at its own size).
    static func isSlip(width w: Int, height h: Int) -> Bool { w == width && h > head + foot }
    /// The photo's place on a slip drawn at `size` (its pixels, or points;
    /// the origin at its top left).
    static func photoRect(in size: CGSize) -> CGRect {
        let k = size.width / CGFloat(width)
        return CGRect(x: CGFloat(side) * k, y: CGFloat(head) * k, width: CGFloat(photoWidth) * k,
                      height: max(0, size.height - CGFloat(head + foot) * k))
    }

    /// The number the next picture is saved under, found as CameraRoll.save finds it.
    static func nextNumber(in dcim: URL = CameraRoll.dcim) -> Int? {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(atPath: dcim.path)) ?? []
        let next = CameraFileNames.next(folders: folders, files: { (try? fm.contentsOfDirectory(atPath: dcim.appendingPathComponent($0).path)) ?? [] })
        return next.flatMap { CameraFileNames.fileNumber($0.file) }
    }

    /// The picture printed as the slip (its photo as wide as the slip lets
    /// it be, as high as its shape makes it); nil when it cannot be drawn.
    /// `strength` is 浓淡: the print darker or lighter.
    static func slip(_ picture: CGImage, thermal: CameraThermal, strength: Double, date: Date, number: Int?) -> CGImage? {
        guard picture.width > 0, picture.height > 0 else { return nil }
        let columns = max(16, thermal.dots)
        let shape = Double(picture.height) / Double(picture.width)
        let rows = max(8, Int((Double(columns) * shape).rounded()))
        guard let marks = dither(picture, columns: columns, rows: rows, thermal: thermal, strength: strength) else { return nil }
        let cell = CGFloat(photoWidth) / CGFloat(columns)
        let photoHeight = (CGFloat(rows) * cell).rounded(.up)
        let height = head + foot + Int(photoHeight)
        guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        let stamp = UInt64(truncatingIfNeeded: Int(date.timeIntervalSince1970))
        var random = SlipRandom(state: stamp &* 2_654_435_761 &+ UInt64(truncatingIfNeeded: number ?? 0))
        // The paper, its fine grain, its edges curling a little.
        c.setFillColor(colour(thermal.paper, 1))
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        grain(c, width: w, height: h, random: &random)
        let edge = colour((r: 0, g: 0, b: 0), 0.05), inner = colour((r: 0, g: 0, b: 0), 0)
        if let curl = CGGradient(colorsSpace: CameraLook.colorSpace, colors: [edge, inner, inner, edge] as CFArray, locations: [0, 0.12, 0.88, 1]) {
            c.drawLinearGradient(curl, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: 0), options: [])
        }
        // ZERO, a star between two rules, the date and the time, the number
        // and the photo's shape, a dashed rule.
        let ink = colour(thermal.ink, thermal.darkest)
        let soft = colour(thermal.ink, thermal.palest + 0.1)
        words("ZERO", size: 76, kern: 18, in: c, x: w / 2, baseline: 140, align: 0.5, ink: ink, height: h)
        c.setFillColor(soft)
        c.fill(CGRect(x: w / 2 - 62, y: h - 180 - 1.5, width: 40, height: 3))
        c.fill(CGRect(x: w / 2 + 22, y: h - 180 - 1.5, width: 40, height: 3))
        star(c, centre: CGPoint(x: w / 2, y: h - 180), radius: 10)
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let day = format.string(from: date)
        format.dateFormat = "HH:mm:ss"
        let time = format.string(from: date)
        let numbered = number.map { "No." + String(format: "%04d", $0) } ?? "No.----"
        let ratio = Double(picture.width) / Double(picture.height)
        let nearest = CameraAspect.allCases.min { abs($0.ratio - ratio) < abs($1.ratio - ratio) }
        words(day, size: 33, in: c, x: 44, baseline: 248, align: 0, ink: ink, height: h)
        words(time, size: 33, in: c, x: w - 44, baseline: 248, align: 1, ink: ink, height: h)
        words(numbered, size: 33, in: c, x: 44, baseline: 302, align: 0, ink: ink, height: h)
        words(nearest?.title ?? "", size: 33, in: c, x: w - 44, baseline: 302, align: 1, ink: ink, height: h)
        rule(c, top: 328, width: w, ink: soft, height: h)
        // The photo, dot by dot.
        printDots(c, marks, columns: columns, rows: rows, left: CGFloat(side), top: CGFloat(head), cell: cell, cellHeight: cell, height: h,
                  thermal: thermal, random: &random)
        // A dashed rule and three small stars under it.
        let below = CGFloat(head) + photoHeight
        rule(c, top: below + 34, width: w, ink: soft, height: h)
        c.setFillColor(soft)
        for k in -1...1 { star(c, centre: CGPoint(x: w / 2 + CGFloat(k) * 34, y: h - below - 80), radius: 7) }
        // One worn dot of the head: a pale line down the whole slip; and
        // the slip paler towards its end.
        c.setFillColor(colour(thermal.paper, thermal.wornShade))
        c.fill(CGRect(x: (w * thermal.wornLine).rounded(), y: 0, width: 3.6, height: h))
        let clear = colour(thermal.paper, 0), faded = colour(thermal.paper, thermal.fade)
        if let fade = CGGradient(colorsSpace: CameraLook.colorSpace, colors: [clear, faded] as CFArray, locations: [0, 1]) {
            c.drawLinearGradient(fade, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        }
        return c.makeImage()
    }

    /// One of several pictures laid on one sheet (两联, 四连拍): its dots
    /// alone on the paper, at the picture's own size (the sheet is made of
    /// pictures of one shape).
    static func dots(_ picture: CGImage, thermal: CameraThermal, strength: Double) -> CGImage? {
        let pw = picture.width, ph = picture.height
        guard pw > 0, ph > 0 else { return nil }
        let columns = max(16, thermal.dots)
        let cell = CGFloat(pw) / CGFloat(columns)
        let rows = max(8, Int((CGFloat(ph) / cell).rounded()))
        guard let marks = dither(picture, columns: columns, rows: rows, thermal: thermal, strength: strength),
              let c = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let h = CGFloat(ph)
        c.setFillColor(colour(thermal.paper, 1))
        c.fill(CGRect(x: 0, y: 0, width: CGFloat(pw), height: h))
        var random = SlipRandom(state: 0x5EED_0D07)
        printDots(c, marks, columns: columns, rows: rows, left: 0, top: 0, cell: cell, cellHeight: h / CGFloat(rows), height: h,
                  thermal: thermal, random: &random)
        return c.makeImage()
    }

    /// The picture at the dots' size, grey (0 black … 1 paper), sharpened
    /// against the mean round each dot, its tones spread between the black
    /// and the white point and bent by an S-curve, darker or lighter by 浓淡;
    /// then each dot printed or not, what it was off by handed on to the
    /// dots not yet done (Floyd–Steinberg, every other row backwards): true
    /// where a dot is printed. The first row is the picture's top.
    private static func dither(_ picture: CGImage, columns: Int, rows: Int, thermal: CameraThermal, strength: Double) -> [Bool]? {
        let n = columns * rows
        guard n > 0 else { return nil }
        var bytes = [UInt8](repeating: 255, count: n * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                    space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.interpolationQuality = .high
            c.draw(picture, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return nil }
        var grey = [Float](repeating: 1, count: n)
        for i in 0..<n {
            let r = Float(bytes[4 * i]), g = Float(bytes[4 * i + 1]), b = Float(bytes[4 * i + 2])
            grey[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        }
        // The mean round each dot, five across and then five down.
        var across = [Float](repeating: 1, count: n)
        for y in 0..<rows {
            for x in 0..<columns {
                var sum: Float = 0, count: Float = 0
                for dx in -2...2 where x + dx >= 0 && x + dx < columns {
                    sum += grey[y * columns + x + dx]
                    count += 1
                }
                across[y * columns + x] = sum / count
            }
        }
        let spread = max(0.05, thermal.white - thermal.black)
        let darker = Float(min(1.5, max(0.25, strength)))
        var tone = [Float](repeating: 1, count: n)
        for y in 0..<rows {
            for x in 0..<columns {
                var sum: Float = 0, count: Float = 0
                for dy in -2...2 where y + dy >= 0 && y + dy < rows {
                    sum += across[(y + dy) * columns + x]
                    count += 1
                }
                let i = y * columns + x
                let sharp: Float = grey[i] + thermal.sharpen * (grey[i] - sum / count)
                let level: Float = min(1, max(0, (sharp - thermal.black) / spread))
                let bent: Float = level < 0.5 ? 2 * level * level : 1 - 2 * (1 - level) * (1 - level)
                tone[i] = Float(pow(Double(bent), Double(darker)))
            }
        }
        var marks = [Bool](repeating: false, count: n)
        for y in 0..<rows {
            let step = y % 2 == 1 ? -1 : 1
            for t in 0..<columns {
                let x = step < 0 ? columns - 1 - t : t
                let i = y * columns + x
                let was = tone[i]
                let printed: Float = was < 0.5 ? 0 : 1
                let off = was - printed
                marks[i] = printed == 0
                let ahead = x + step, behind = x - step
                if ahead >= 0, ahead < columns { tone[i + step] += off * 7 / 16 }
                if y + 1 < rows {
                    if behind >= 0, behind < columns { tone[i + columns - step] += off * 3 / 16 }
                    tone[i + columns] += off * 5 / 16
                    if ahead >= 0, ahead < columns { tone[i + columns + step] += off / 16 }
                }
            }
        }
        return marks
    }

    /// The dots on the paper: each a little wider than its cell (they run
    /// together), the ink lighter towards the far side and the end and by
    /// chance, a few left out. `left`, `top`: the photo's corner (down from
    /// the top).
    private static func printDots(_ c: CGContext, _ marks: [Bool], columns: Int, rows: Int, left: CGFloat, top: CGFloat, cell: CGFloat, cellHeight: CGFloat,
                                  height h: CGFloat, thermal: CameraThermal, random: inout SlipRandom) {
        let radius = max(cell, cellHeight) * 0.56
        let buckets = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]
        for y in 0..<rows {
            for x in 0..<columns where marks[y * columns + x] {
                if random.next() < thermal.dropped { continue }
                let across: Double = 0.2 * Double(x) / Double(columns)
                let down: Double = 0.08 * Double(y) / Double(rows)
                let share: Double = 0.92 - across - down - 0.1 * random.next()
                let bucket = min(3, max(0, Int(((share - 0.5) / 0.11).rounded(.down))))
                let cx = left + (CGFloat(x) + 0.5) * cell
                let cy = h - (top + (CGFloat(y) + 0.5) * cellHeight)
                buckets[bucket].addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: 2 * radius, height: 2 * radius))
            }
        }
        for (index, path) in buckets.enumerated() {
            let strength = thermal.palest + (thermal.darkest - thermal.palest) * CGFloat(index) / 3
            c.setFillColor(colour(thermal.ink, strength))
            c.addPath(path)
            c.fillPath()
        }
    }

    /// The paper's fine grain: specks a little darker and a little lighter.
    private static func grain(_ c: CGContext, width w: CGFloat, height h: CGFloat, random: inout SlipRandom) {
        let darker = CGMutablePath(), lighter = CGMutablePath()
        for _ in 0..<Int(w * h / 90) {
            let at = CGRect(x: CGFloat(random.next()) * w, y: CGFloat(random.next()) * h, width: 1.6, height: 1.6)
            if random.next() < 0.5 { darker.addRect(at) } else { lighter.addRect(at) }
        }
        c.setFillColor(colour((r: 96, g: 88, b: 72), 0.05))
        c.addPath(darker)
        c.fillPath()
        c.setFillColor(colour((r: 255, g: 255, b: 255), 0.35))
        c.addPath(lighter)
        c.fillPath()
    }

    /// Words on the slip: `x` where they begin (align 0), stand centred
    /// (0.5) or end (1); `baseline` down from the top.
    private static func words(_ text: String, size: CGFloat, kern: CGFloat = 0, in c: CGContext, x: CGFloat, baseline: CGFloat, align: CGFloat,
                              ink: CGColor, height h: CGFloat) {
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ]
        if kern > 0 { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kern }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        // (The space kerned after the last letter is not part of the words.)
        let wide = max(0, bounds.width - kern)
        c.textPosition = CGPoint(x: x - wide * align, y: h - baseline)
        CTLineDraw(line, c)
    }

    /// A dashed rule across the slip, `top` down from its top.
    private static func rule(_ c: CGContext, top: CGFloat, width w: CGFloat, ink: CGColor, height h: CGFloat) {
        c.saveGState()
        c.setStrokeColor(ink)
        c.setLineWidth(2.6)
        c.setLineDash(phase: 0, lengths: [9, 7.5])
        c.move(to: CGPoint(x: CGFloat(side), y: h - top))
        c.addLine(to: CGPoint(x: w - CGFloat(side), y: h - top))
        c.strokePath()
        c.restoreGState()
    }

    /// A small five-pointed star (Core Graphics' own coordinates), in the fill colour set.
    private static func star(_ c: CGContext, centre: CGPoint, radius: CGFloat) {
        let path = CGMutablePath()
        for index in 0..<10 {
            let r = index % 2 == 0 ? radius : radius * 0.45
            let angle = Double(index) * Double.pi / 5 + Double.pi / 2
            let point = CGPoint(x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        c.addPath(path)
        c.fillPath()
    }

    private static func colour(_ rgb: (r: CGFloat, g: CGFloat, b: CGFloat), _ alpha: CGFloat) -> CGColor {
        CGColor(colorSpace: CameraLook.colorSpace, components: [rgb.r / 255, rgb.g / 255, rgb.b / 255, alpha]) ?? CGColor(gray: rgb.g / 255, alpha: alpha)
    }

    /// The slip's own run of chance (the same slip draws the same).
    private struct SlipRandom {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
        }
    }
}
