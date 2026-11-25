import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#endif

// 机型: the camera's
// simulated bodies — the look of a kind of old camera laid over the
// module's picture, after the lens's finish: a colour cast and tone curve,
// grain, a vignette, a light leak, scan lines, a date stamp, a sheet of
// photo paper. Everything here is FoldArc's own: the names, the paper's
// proportions, the stamp's lettering, the colours. No maker's name or
// model name, no body shape of theirs, no frame of theirs (the
// equal-bordered paper below is not any instant film's border).
// 11-06: eight more — 00后梦核 from 36 reference pictures (中式梦核, 千禧年,
// 00后: the tones measured, nothing of them kept), and looks such apps
// have, under names of our own. 00后梦核 again, from five more reference
// pictures (the same way: measured only); the stronger of the three levels
// shown.

/// A simulated body. `native` is the module as it is (the default).
enum CameraBody: String, CaseIterable, Identifiable, Codable, Sendable {
    case native, oldCCD, goldenFilm, instantPaper, disposable, tapeDV, silverMono, pixelY2K
    case dreamcore00, coolCCD, flashSnap, slideFilm, fadedPrint, crossProcess, toyCamera, cinemaReel
    case afterSchool, computerClass, birthdayNight, vcdStill
    case overcastRich, keyPhone, earlyFilter, warmFlash, coolDaily, photoBooth, brightDisposable, earlySummer
    case paleYellow, winterSun, nostalgicCompact, summerStreet, pinkWinter, warmDaylight, cherryPink, sunsetOrange
    case yellowGreenHaze, freshWarm, duskFilm, quietTeal
    case snackStall
    case receipt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: return String(localized: "原生")
        case .oldCCD: return String(localized: "老 CCD")
        case .goldenFilm: return String(localized: "暖金胶卷")
        case .instantPaper: return String(localized: "即显相纸")
        case .disposable: return String(localized: "一次性胶卷")
        case .tapeDV: return String(localized: "磁带 DV")
        case .silverMono: return String(localized: "银盐黑白")
        case .pixelY2K: return String(localized: "千禧像素")
        case .dreamcore00: return String(localized: "00后梦核")
        case .coolCCD: return String(localized: "冷蓝 CCD")
        case .flashSnap: return String(localized: "闪光直拍")
        case .slideFilm: return String(localized: "正片")
        case .fadedPrint: return String(localized: "褪色老照片")
        case .crossProcess: return String(localized: "交叉冲印")
        case .toyCamera: return String(localized: "玩具相机")
        case .cinemaReel: return String(localized: "电影卷")
        case .afterSchool: return String(localized: "放学路上")
        case .computerClass: return String(localized: "微机课")
        case .birthdayNight: return String(localized: "生日那晚")
        case .vcdStill: return String(localized: "VCD 截图")
        case .overcastRich: return String(localized: "阴天浓彩")
        case .keyPhone: return String(localized: "翻盖手机")
        case .earlyFilter: return String(localized: "早年滤镜")
        case .warmFlash: return String(localized: "暖黄直闪")
        case .coolDaily: return String(localized: "清冷日常")
        case .photoBooth: return String(localized: "大头贴")
        case .brightDisposable: return String(localized: "艳色一次性")
        case .earlySummer: return String(localized: "初夏")
        case .paleYellow: return String(localized: "淡黄胶片")
        case .winterSun: return String(localized: "冬日暖阳")
        case .nostalgicCompact: return String(localized: "怀旧卡片机")
        case .summerStreet: return String(localized: "夏日街景")
        case .pinkWinter: return String(localized: "粉白初冬")
        case .warmDaylight: return String(localized: "暖黄日光")
        case .cherryPink: return String(localized: "樱花季")
        case .sunsetOrange: return String(localized: "落日橘")
        case .yellowGreenHaze: return String(localized: "黄绿薄雾")
        case .freshWarm: return String(localized: "清新暖调")
        case .duskFilm: return String(localized: "黄昏胶卷")
        case .quietTeal: return String(localized: "静谧青")
        case .snackStall: return String(localized: "小卖部")
        case .receipt: return String(localized: "小票")
        }
    }
    /// What it does, in a few words (the picker's cards).
    var blurb: String {
        switch self {
        case .native: return String(localized: "像掌机自带的相机拍的：偏软、边缘发亮，暗处有色斑")
        case .oldCCD: return String(localized: "偏暖、高光发晕、细颗粒，右下角橙色日期")
        case .goldenFilm: return String(localized: "暖金的底片色，蓝天深、红色明快，颗粒")
        case .instantPaper: return String(localized: "一张奶白相纸，画面柔、偏粉，四边等宽")
        case .disposable: return String(localized: "偏黄绿、粗颗粒、蓝天很深，边上漏一道橙光，日期")
        case .tapeDV: return String(localized: "低清、偏灰、扫描线，角上 REC 和时间")
        case .silverMono: return String(localized: "高反差的黑白，银盐的细颗粒")
        case .pixelY2K: return String(localized: "像素化、锐过头、偏蓝，色阶断")
        case .dreamcore00: return String(localized: "像隔着一层薄薄的光雾：发白发亮、颜色淡淡的、高光奶黄，软")
        case .coolCCD: return String(localized: "偏蓝、明亮通透、黑不到底，橙色日期")
        case .flashSnap: return String(localized: "闪光灯直打：中间亮、四周暗、偏冷，日期")
        case .slideFilm: return String(localized: "反转片：颜色浓、黑得深、对比强")
        case .fadedPrint: return String(localized: "放了二十年的照片：发白、偏粉、软")
        case .crossProcess: return String(localized: "冲错了药水：高光黄绿、暗部发青")
        case .toyCamera: return String(localized: "塑料镜头：四角很暗、颜色很艳、边上发虚")
        case .cinemaReel: return String(localized: "电影感：青橙色、上下黑边、细颗粒")
        case .afterSchool: return String(localized: "树荫下的黄绿色：不太亮、有点软，阴影也偏黄绿")
        case .computerClass: return String(localized: "日光灯和蓝窗帘：偏青蓝、暗处发灰、平平的")
        case .birthdayNight: return String(localized: "屋里开着灯、闪光灯直打：暖橙，中间亮四周暗")
        case .vcdStill: return String(localized: "像从糊掉的录像里截的：涂抹、色阶断开、方块")
        case .overcastRich: return String(localized: "黑不到底、白不到顶，颜色沉而浓，绿色偏冷")
        case .keyPhone: return String(localized: "低清、亮处一片白、边上发紫，暗处有彩色噪点")
        case .earlyFilter: return String(localized: "暗部发紫、亮部奶黄，褪色、四角暗")
        case .warmFlash: return String(localized: "整体黄绿，闪光灯直打，白的发奶黄")
        case .coolDaily: return String(localized: "颜色淡、偏冷、干净，高光柔和")
        case .photoBooth: return String(localized: "暖调的黑白，反差柔，细颗粒")
        case .brightDisposable: return String(localized: "暗部发青、橙红很艳、蓝偏青，细颗粒")
        case .earlySummer: return String(localized: "蓝和绿清冷柔和，画面细，暗部微蓝")
        case .paleYellow: return String(localized: "淡淡的暖黄，反差低，温和")
        case .winterSun: return String(localized: "暖、有雾感和粗一点的颗粒，蓝色好看")
        case .nostalgicCompact: return String(localized: "暗部发青发灰、亮部偏黄，软，细噪点")
        case .summerStreet: return String(localized: "颜色浓而亮，暗部偏青、亮部偏暖")
        case .pinkWinter: return String(localized: "明亮通透、偏冷，白里透粉")
        case .warmDaylight: return String(localized: "暖黄，红和蓝很出彩，细颗粒，四角暗")
        case .cherryPink: return String(localized: "奶油粉，柔光发朦，颗粒")
        case .sunsetOrange: return String(localized: "整张橘红，对比和饱和都高，留给晚霞")
        case .yellowGreenHaze: return String(localized: "黄绿色、像隔着薄雾，反差低，有年代感")
        case .freshWarm: return String(localized: "明亮、通透、偏暖黄，粗一点的颗粒")
        case .duskFilm: return String(localized: "暖黄，白的不亮，暗部沉，胶卷颗粒")
        case .quietTeal: return String(localized: "颜色柔和、偏青，白的不刺眼，安静")
        case .snackStall: return String(localized: "暗部发蓝、亮部奶黄，红色褪成粉，黄色最显眼，颗粒")
        case .receipt: return String(localized: "印成热敏小票：黑白点阵，纸色微暖，淡淡褪色；取景是彩色的")
        }
    }
    var symbol: String {
        switch self {
        case .native: return "camera.aperture"
        case .oldCCD: return "camera.metering.center.weighted"
        case .goldenFilm: return "film"
        case .instantPaper: return "photo"
        case .disposable: return "camera.on.rectangle"
        case .tapeDV: return "video"
        case .silverMono: return "circle.lefthalf.filled"
        case .pixelY2K: return "square.grid.3x3"
        case .dreamcore00: return "cloud.sun"
        case .coolCCD: return "snowflake"
        case .flashSnap: return "bolt.fill"
        case .slideFilm: return "camera.filters"
        case .fadedPrint: return "photo.on.rectangle.angled"
        case .crossProcess: return "drop"
        case .toyCamera: return "smallcircle.filled.circle"
        case .cinemaReel: return "film.fill"
        case .afterSchool: return "figure.walk"
        case .computerClass: return "desktopcomputer"
        case .birthdayNight: return "birthday.cake"
        case .vcdStill: return "opticaldisc"
        case .overcastRich: return "cloud.fill"
        case .keyPhone: return "candybarphone"
        case .earlyFilter: return "iphone"
        case .warmFlash: return "bolt.circle"
        case .coolDaily: return "leaf"
        case .photoBooth: return "person.2.fill"
        case .brightDisposable: return "camera.on.rectangle.fill"
        case .earlySummer: return "leaf.fill"
        case .paleYellow: return "sun.min"
        case .winterSun: return "sun.haze"
        case .nostalgicCompact: return "camera.fill"
        case .summerStreet: return "sun.max.fill"
        case .pinkWinter: return "heart"
        case .warmDaylight: return "sun.max"
        case .cherryPink: return "camera.macro"
        case .sunsetOrange: return "sunset.fill"
        case .yellowGreenHaze: return "cloud.fog"
        case .freshWarm: return "sparkles"
        case .duskFilm: return "sunset"
        case .quietTeal: return "water.waves"
        case .snackStall: return "umbrella.fill"
        case .receipt: return "doc.plaintext"
        }
    }
    /// Two colours for the card's swatch.
    var swatch: (Color, Color) {
        switch self {
        case .native: return (Color(red: 0.91, green: 0.93, blue: 0.96), Color(red: 0.72, green: 0.78, blue: 0.85))
        case .oldCCD: return (Color(red: 0.95, green: 0.80, blue: 0.55), Color(red: 0.45, green: 0.32, blue: 0.24))
        case .goldenFilm: return (Color(red: 0.98, green: 0.86, blue: 0.56), Color(red: 0.62, green: 0.44, blue: 0.22))
        case .instantPaper: return (Color(red: 0.98, green: 0.95, blue: 0.90), Color(red: 0.86, green: 0.70, blue: 0.70))
        case .disposable: return (Color(red: 0.78, green: 0.88, blue: 0.78), Color(red: 0.95, green: 0.55, blue: 0.25))
        case .tapeDV: return (Color(red: 0.62, green: 0.66, blue: 0.72), Color(red: 0.28, green: 0.30, blue: 0.36))
        case .silverMono: return (Color(red: 0.92, green: 0.92, blue: 0.92), Color(red: 0.12, green: 0.12, blue: 0.12))
        case .pixelY2K: return (Color(red: 0.60, green: 0.80, blue: 0.98), Color(red: 0.20, green: 0.40, blue: 0.75))
        case .dreamcore00: return (Color(red: 0.97, green: 0.94, blue: 0.86), Color(red: 0.78, green: 0.85, blue: 0.79))
        case .coolCCD: return (Color(red: 0.86, green: 0.93, blue: 1.0), Color(red: 0.30, green: 0.45, blue: 0.70))
        case .flashSnap: return (Color(red: 1.0, green: 1.0, blue: 0.98), Color(red: 0.10, green: 0.10, blue: 0.14))
        case .slideFilm: return (Color(red: 0.98, green: 0.70, blue: 0.20), Color(red: 0.10, green: 0.30, blue: 0.65))
        case .fadedPrint: return (Color(red: 0.96, green: 0.88, blue: 0.84), Color(red: 0.72, green: 0.55, blue: 0.55))
        case .crossProcess: return (Color(red: 0.88, green: 0.95, blue: 0.45), Color(red: 0.15, green: 0.55, blue: 0.60))
        case .toyCamera: return (Color(red: 0.98, green: 0.50, blue: 0.45), Color(red: 0.15, green: 0.12, blue: 0.20))
        case .cinemaReel: return (Color(red: 0.98, green: 0.65, blue: 0.40), Color(red: 0.10, green: 0.40, blue: 0.45))
        case .afterSchool: return (Color(red: 0.82, green: 0.87, blue: 0.62), Color(red: 0.40, green: 0.50, blue: 0.34))
        case .computerClass: return (Color(red: 0.74, green: 0.89, blue: 0.93), Color(red: 0.26, green: 0.40, blue: 0.62))
        case .birthdayNight: return (Color(red: 1.0, green: 0.82, blue: 0.55), Color(red: 0.40, green: 0.19, blue: 0.11))
        case .vcdStill: return (Color(red: 0.80, green: 0.76, blue: 0.87), Color(red: 0.36, green: 0.46, blue: 0.40))
        case .overcastRich: return (Color(red: 0.78, green: 0.80, blue: 0.80), Color(red: 0.16, green: 0.24, blue: 0.24))
        case .keyPhone: return (Color(red: 0.93, green: 0.90, blue: 1.00), Color(red: 0.42, green: 0.36, blue: 0.72))
        case .earlyFilter: return (Color(red: 0.98, green: 0.95, blue: 0.80), Color(red: 0.45, green: 0.25, blue: 0.42))
        case .warmFlash: return (Color(red: 0.96, green: 0.92, blue: 0.72), Color(red: 0.36, green: 0.36, blue: 0.20))
        case .coolDaily: return (Color(red: 0.92, green: 0.95, blue: 0.96), Color(red: 0.45, green: 0.56, blue: 0.62))
        case .photoBooth: return (Color(red: 0.92, green: 0.88, blue: 0.80), Color(red: 0.24, green: 0.18, blue: 0.14))
        case .brightDisposable: return (Color(red: 0.98, green: 0.62, blue: 0.30), Color(red: 0.10, green: 0.36, blue: 0.44))
        case .earlySummer: return (Color(red: 0.90, green: 0.96, blue: 0.90), Color(red: 0.36, green: 0.56, blue: 0.46))
        case .paleYellow: return (Color(red: 0.98, green: 0.95, blue: 0.82), Color(red: 0.62, green: 0.56, blue: 0.40))
        case .winterSun: return (Color(red: 0.98, green: 0.88, blue: 0.66), Color(red: 0.34, green: 0.46, blue: 0.66))
        case .nostalgicCompact: return (Color(red: 0.96, green: 0.94, blue: 0.80), Color(red: 0.30, green: 0.42, blue: 0.44))
        case .summerStreet: return (Color(red: 0.99, green: 0.90, blue: 0.84), Color(red: 0.08, green: 0.36, blue: 0.50))
        case .pinkWinter: return (Color(red: 0.98, green: 0.90, blue: 0.94), Color(red: 0.50, green: 0.56, blue: 0.76))
        case .warmDaylight: return (Color(red: 0.99, green: 0.86, blue: 0.52), Color(red: 0.10, green: 0.28, blue: 0.34))
        case .cherryPink: return (Color(red: 0.99, green: 0.88, blue: 0.86), Color(red: 0.80, green: 0.52, blue: 0.56))
        case .sunsetOrange: return (Color(red: 0.99, green: 0.70, blue: 0.36), Color(red: 0.46, green: 0.14, blue: 0.10))
        case .yellowGreenHaze: return (Color(red: 0.86, green: 0.92, blue: 0.80), Color(red: 0.44, green: 0.40, blue: 0.36))
        case .freshWarm: return (Color(red: 1.00, green: 0.97, blue: 0.88), Color(red: 0.84, green: 0.70, blue: 0.48))
        case .duskFilm: return (Color(red: 0.92, green: 0.80, blue: 0.60), Color(red: 0.30, green: 0.18, blue: 0.12))
        case .quietTeal: return (Color(red: 0.82, green: 0.90, blue: 0.90), Color(red: 0.20, green: 0.42, blue: 0.46))
        case .snackStall: return (Color(red: 0.96, green: 0.90, blue: 0.72), Color(red: 0.12, green: 0.16, blue: 0.36))
        case .receipt: return (Color(red: 0.97, green: 0.96, blue: 0.94), Color(red: 0.20, green: 0.18, blue: 0.23))
        }
    }
    /// The bodies that print a date on the picture, and the ones on paper.
    /// (小票 prints the date and time on its own slip, under ZERO.)
    var hasDateStamp: Bool { recipe.stamp != nil || recipe.thermal != nil }
    var hasPaper: Bool { self == .instantPaper }
    /// A body whose colour is a grade is given the camera's own picture,
    /// not the module's.
    private static let plainBodies = Set(allCases.filter { $0.recipe.plain })
    var isPlain: Bool { Self.plainBodies.contains(self) }

    static let defaultsKey = "FoldArc.camera.body"
    static let pinnedKey = "FoldArc.camera.pinnedBodies"
    /// The body kept in the settings, and the ones pinned into the lens row.
    static func stored(_ defaults: UserDefaults = .standard) -> CameraBody {
        CameraBody(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .native
    }
    static func storedPins(_ defaults: UserDefaults = .standard) -> [CameraBody] {
        (defaults.stringArray(forKey: pinnedKey) ?? []).compactMap(CameraBody.init(rawValue:)).filter { $0 != .native }
    }
}

/// What makes a body's look (round 32, b18 — the
/// stages a retro camera's picture goes through, each a number here; a
/// body is a recipe, so a new one is a few lines). The order follows how
/// an old camera and its lens make a picture: the lens's colour fringes,
/// its softness, the sensor's/film's colour and tone, the highlights
/// blooming in the lens, the grain and the noise in the dark, the
/// vignette, light leaking in, the signal's scan lines and blocks, the
/// camera's own sharpening, the paper or the date it prints.
struct CameraBodyRecipe {
    /// The tone curve (five points, input → output).
    var curve: [(Double, Double)] = [(0, 0), (0.25, 0.25), (0.5, 0.5), (0.75, 0.75), (1, 1)]
    var saturation: Float = 1
    var contrast: Float = 1
    /// A colour cast: each channel's gain and offset.
    var cast: (r: (CGFloat, CGFloat), g: (CGFloat, CGFloat), b: (CGFloat, CGFloat)) = ((1, 0), (1, 0), (1, 0))
    /// A gentle colour mix (CIColorPolynomial coefficients), nil for none.
    var polynomial: (r: CIVector, g: CIVector, b: CIVector)? = nil
    /// The lens: colour fringes at the edges (pixels of red/blue shift at
    /// the corners), and softness (a blur radius).
    var fringe: CGFloat = 0
    var softness: Float = 0
    /// Highlights blooming: above `threshold` the light spreads `radius`
    /// pixels at `strength`, tinted `warmth` (0 white, 1 orange).
    var bloomThreshold: Float = 1
    var bloomRadius: Float = 8
    var bloomStrength: Float = 0
    var bloomWarmth: Float = 0
    /// Grain everywhere, and noise that lives in the dark (weighted by
    /// 1 − luminance), as a sensor's does.
    var grain: Double = 0
    var shadowNoise: Double = 0
    var vignette: Float = 0
    var vignetteRadius: Float = 1.6
    var leak: Bool = false
    var scanlines: Bool = false
    /// Fewer pixels (the picture scaled down and up again), posterised
    /// colours (levels, 0 for none), a sharpening pass, the JPEG blocks of a
    /// still (quality 0…1, 1 for none; stills only).
    var pixel: CGFloat = 1
    var levels: Float = 0
    var sharpen: Float = 0
    var jpegQuality: Float = 1
    var stamp: CameraBodyLook.StampStyle? = nil
    var paper: Bool = false
    var monochrome: Bool = false
    /// 11-06: a flash fired from the camera (the middle lit, the corners
    /// dark), the exposure (EV) before the rest, detail smeared (median
    /// passes at half size: an old small picture blown up and cleaned), black
    /// bars leaving a picture of this aspect (0 for none).
    var flashLit = false
    var exposure: Float = 0
    var smear = 0
    var letterbox: CGFloat = 0
    /// 11-19: an ordered dither before the colours are stepped (`levels`):
    /// a threshold pattern eight cells square, a cell one of the signal's
    /// pixels, pushing each colour up or down by up to half of `dither`.
    var dither: Float = 0
    /// A strong light on a small sensor: running along the rows (`flare`)
    /// and, fainter, up and down the columns (`streak`).
    var flare: Float = 0
    var streak: Float = 0
    /// Film: grain strongest in the middle tones, and red-orange light
    /// round the highlights where they meet the dark.
    var midGrain: Double = 0
    var halation: Float = 0
    /// A tape's colour dragged to the right of its brightness (pixels).
    var chromaTrail: CGFloat = 0
    /// Moving pictures only (the viewfinder, a recording; not a kept
    /// still): the frame weaving in the gate (pixels), the lamp's flicker
    /// (± this share), the bottom of a tape's picture breaking up.
    var weave: CGFloat = 0
    var flicker: Float = 0
    var trackingBand: Float = 0
    /// A colour grade, looked up in a cube (after the tone and the cast
    /// above, which a body with a grade leaves as they are), and the
    /// picture such a body is given: the camera's own with a little of
    /// the sensor's grain (`plain`), not the module's.
    var grade: CameraGrade? = nil
    var plain = false
    /// A till's thermal print (小票): a picture kept is printed in dots on a
    /// slip of thermal paper (CameraReceiptPrint, when it is taken and when
    /// one brought in is developed); the viewfinder and a video keep the
    /// colour picture. Nil for every other body.
    var thermal: CameraThermal? = nil
}

/// How a till's thermal head prints a picture (小票, mock/cr7.js's four
/// steps): the picture at the dots' size, grey, sharpened against its
/// surroundings, its tones spread between a black and a white point and
/// bent by an S-curve; dithered to dots by error diffusion; each dot a
/// faded violet-black on warm paper, lighter towards the slip's far side and
/// its end, a few left out; one worn dot of the head leaves a pale line down
/// the whole slip; the slip a little paler towards its end.
struct CameraThermal {
    /// Dots across the photo (the slip is CameraReceiptPrint.width pixels).
    var dots = 270
    /// The picture less the mean of its 5 × 5 dots round it, this much more.
    var sharpen: Float = 1.2
    /// What becomes black, and what is left as paper, before the S-curve.
    var black: Float = 0.2
    var white: Float = 0.95
    /// The paper and the ink (0…255), the ink at its palest and its darkest.
    var paper: (r: CGFloat, g: CGFloat, b: CGFloat) = (247, 245, 239)
    var ink: (r: CGFloat, g: CGFloat, b: CGFloat) = (50, 45, 58)
    var palest: CGFloat = 0.55
    var darkest: CGFloat = 0.88
    /// The share of dots the head leaves out; where the worn line runs (a
    /// share of the width) and how pale; how much paler the slip's end is.
    var dropped: Double = 0.03
    var wornLine: CGFloat = 0.63
    var wornShade: CGFloat = 0.55
    var fade: CGFloat = 0.2
}

/// 浓淡 kept: a body's name to its step (CameraBodyStrength, in Domain).
extension CameraBodyStrength {
    static func stored(_ defaults: UserDefaults = .standard) -> [String: Int] {
        kept(defaults.dictionary(forKey: defaultsKey), names: Set(CameraBody.allCases.filter { $0 != .native }.map(\.rawValue)))
    }
    static func store(_ steps: [String: Int], _ defaults: UserDefaults = .standard) {
        let kept = steps.filter { $0.value != 0 }
        if kept.isEmpty { defaults.removeObject(forKey: defaultsKey) } else { defaults.set(kept, forKey: defaultsKey) }
    }
}

extension CameraBodyRecipe {
    /// The recipe taken further: each amount `k` times as far from none
    /// (k above 1). What is on or off stays so, as do the kinds of things
    /// (the stamp, the paper, the bars, where the bloom begins).
    func stronger(_ k: Double) -> CameraBodyRecipe {
        guard k > 1 else { return self }
        var r = self
        let f = CGFloat(k), g = Float(k)
        r.curve = curve.map { ($0.0, min(1, max(0, $0.0 + ($0.1 - $0.0) * k))) }
        r.saturation = max(0, 1 + (saturation - 1) * g)
        r.contrast = max(0.2, 1 + (contrast - 1) * g)
        r.cast = ((1 + (cast.r.0 - 1) * f, cast.r.1 * f), (1 + (cast.g.0 - 1) * f, cast.g.1 * f), (1 + (cast.b.0 - 1) * f, cast.b.1 * f))
        if let p = polynomial {
            // (Constant, linear, square, cube: none is 0, 1, 0, 0.)
            func further(_ v: CIVector) -> CIVector { CIVector(x: v.x * f, y: 1 + (v.y - 1) * f, z: v.z * f, w: v.w * f) }
            r.polynomial = (further(p.r), further(p.g), further(p.b))
        }
        r.fringe = fringe * f
        r.softness = softness * g
        r.bloomStrength = min(1, bloomStrength * g)
        r.grain = grain * k
        r.shadowNoise = shadowNoise * k
        r.vignette = vignette * g
        r.exposure = exposure * g
        r.sharpen = sharpen * g
        r.dither = dither * g
        r.flare = min(1, flare * g)
        r.streak = min(1, streak * g)
        r.midGrain = midGrain * k
        r.halation = min(1, halation * g)
        r.chromaTrail = chromaTrail * f
        r.weave = weave * f
        r.flicker = flicker * g
        r.grade = grade?.stronger(k)
        if pixel < 1 { r.pixel = max(0.2, 1 - (1 - pixel) * f) }
        if jpegQuality < 1 { r.jpegQuality = max(0.05, 1 - (1 - jpegQuality) * g) }
        return r
    }
}

extension CameraBody {
    /// The recipe of each body. All of it is FoldArc's: the numbers were
    /// chosen by eye on the module's pictures, not taken from anyone's.
    var recipe: CameraBodyRecipe {
        var r = CameraBodyRecipe()
        switch self {
        case .native:
            break
        case .oldCCD:
            // A small sensor around 2003: warm, rich, the highlights blooming
            // in a tiny lens, a strong light streaking sideways (lightly: a
            // white wall is as bright as a lamp to this picture), fine noise,
            // sharpened in the camera, a date.
            r.curve = [(0, 0.02), (0.25, 0.24), (0.5, 0.54), (0.75, 0.84), (0.9, 1.0)]
            r.saturation = 1.14; r.contrast = 1.06
            r.cast = ((1.05, 0.025), (1.0, 0.0), (0.93, -0.015))
            r.fringe = 1.4
            r.bloomThreshold = 0.78; r.bloomRadius = 9; r.bloomStrength = 0.55; r.bloomWarmth = 0.35
            r.flare = 0.1; r.streak = 0.03
            r.grain = 0.035; r.shadowNoise = 0.07
            r.vignette = 0.2; r.vignetteRadius = 1.9
            r.sharpen = 0.6
            r.jpegQuality = 0.55
            r.stamp = .orange
        case .goldenFilm:
            // A warm colour negative in the sun: gold through the middle, the
            // black warm, blue skies deep, reds lively, grain, a soft vignette, a
            // little halation.
            r.plain = true
            r.grade = CameraGrade(red: [0.041, 0.342, 0.65, 0.845, 0.95], green: [0.026, 0.301, 0.6, 0.809, 0.943], blue: [0.018, 0.251, 0.531, 0.757, 0.933],
                                   saturation: 1.13, strength: [1.12, 1, 1, 1, 1.1, 1.2, 1, 1], light: [0, 0, 0, 0, 0, -0.08, 0, 0])
            r.bloomThreshold = 0.85; r.bloomRadius = 12; r.bloomStrength = 0.25; r.bloomWarmth = 0.8
            r.halation = 0.3
            r.grain = 0.035; r.midGrain = 0.06; r.shadowNoise = 0.02
            r.vignette = 0.3; r.vignetteRadius = 1.7
            r.fringe = 0.5
        case .instantPaper:
            // Instant film: soft, the white gone pink and the black a little
            // blue, a faint vignette, on a cream sheet.
            r.plain = true
            r.grade = CameraGrade(red: [0.016, 0.373, 0.647, 0.813, 0.958], green: [0.007, 0.344, 0.605, 0.767, 0.914], blue: [0.033, 0.358, 0.61, 0.767, 0.909],
                                   saturation: 1.02)
            r.softness = 0.6
            r.bloomThreshold = 0.8; r.bloomRadius = 14; r.bloomStrength = 0.25; r.bloomWarmth = 0.2
            r.vignette = 0.3; r.vignetteRadius = 1.8
            r.grain = 0.03
            r.paper = true
        case .disposable:
            // A disposable's plastic lens and fast film: yellow-green through the
            // middle, the black lifted, blue skies deep, coarse grain, fringes, a
            // vignette, a leak of light, a date.
            r.plain = true
            r.grade = CameraGrade(red: [0.088, 0.326, 0.603, 0.826, 0.999], green: [0.095, 0.331, 0.607, 0.828, 1], blue: [0.094, 0.273, 0.516, 0.751, 0.965],
                                   saturation: 1.15, turn: [0, 0, -4, -10, 0, 0, 0, 0], strength: [1, 1, 1, 1, 1, 1.3, 1, 1], light: [0, 0, 0, 0, 0, -0.1, 0, 0])
            r.fringe = 2.0; r.softness = 0.3
            r.bloomThreshold = 0.82; r.bloomRadius = 10; r.bloomStrength = 0.3; r.bloomWarmth = 0.6
            r.halation = 0.3
            r.grain = 0.06; r.midGrain = 0.12; r.shadowNoise = 0.05
            r.vignette = 0.5; r.vignetteRadius = 1.5
            r.leak = true
            r.stamp = .orange
        case .tapeDV:
            // A tape camcorder: fewer pixels, grey and flat, cool through the
            // middle, colours bleeding, scan lines, noise in the dark, REC and the time.
            r.plain = true
            r.grade = CameraGrade(red: [0.03, 0.325, 0.579, 0.769, 0.933], green: [0.04, 0.355, 0.618, 0.798, 0.941], blue: [0.049, 0.39, 0.662, 0.829, 0.942],
                                   saturation: 0.7, turn: [0, 0, -5, -12, 0, 0, 0, 0])
            r.pixel = 0.5
            r.fringe = 1.4
            r.scanlines = true
            r.chromaTrail = 7; r.trackingBand = 0.7
            r.grain = 0.03; r.shadowNoise = 0.07
            r.sharpen = 0.5
            r.stamp = .tape
        case .silverMono:
            // Black-and-white film: bite, fine grain, a touch of vignette,
            // the highlights glowing a little.
            r.monochrome = true
            r.curve = [(0, 0.0), (0.2, 0.14), (0.5, 0.52), (0.8, 0.88), (1.0, 1.0)]
            r.contrast = 1.18
            r.bloomThreshold = 0.88; r.bloomRadius = 10; r.bloomStrength = 0.25
            r.grain = 0.035; r.midGrain = 0.11; r.shadowNoise = 0.03
            r.vignette = 0.35; r.vignetteRadius = 1.7
        case .pixelY2K:
            // An early digital camera: blocks of pixels, sharpened too much,
            // blue-cyan, colours in steps with a faint dither's pattern where
            // one step meets the next (about half a step: the lightest of the
            // four tried, flat tones stay flat),
            // JPEG blocks, a pale-yellow date.
            r.pixel = 1 / 3
            r.sharpen = 1.3
            r.saturation = 1.25; r.contrast = 1.1
            r.cast = ((0.97, 0.0), (1.0, 0.01), (1.05, 0.03))
            r.levels = 16; r.dither = 0.035
            r.jpegQuality = 0.35
            r.shadowNoise = 0.05
            r.stamp = .yellow
        case .dreamcore00:
            // 11-06: five more reference pictures, measured (median
            // of each): blacks lifted to about 0.14, the middle at 0.56,
            // 7 % of it clipped white, saturation 0.20 (the 36 before:
            // 0.07, 0.42, 4 %, 0.25), about half their fine detail, the
            // highlights cream. A summer remembered through a veil of light:
            // everything lifted towards a milky white (the polynomial's
            // offset), pale colour, the light spilling wide and warm, soft
            // and smeared, no sharpening, fine noise, JPEG blocks. Fitted on
            // six test pictures through a copy of this pipeline and checked
            // with Core Image itself on the Mac (b37, logs/r32/ci932); the
            // tone is all in the polynomial, which Core Image applies to the
            // sRGB values as they are (CIToneCurve works on their square
            // roots — measured — so the curve stays straight here).
            // The 浓一点 row of that
            // sheet — a thinner veil (the offset 0.16 instead of 0.19), a
            // little more colour (0.6), the glow a touch tighter.
            r.smear = 1
            r.fringe = 1.2
            r.softness = 1.1
            r.saturation = 0.6
            r.polynomial = (CIVector(x: 0.1598, y: 1.486, z: -0.8412, w: 0.2881),
                            CIVector(x: 0.1398, y: 1.506, z: -0.8412, w: 0.2881),
                            CIVector(x: 0.1298, y: 1.466, z: -0.8812, w: 0.2881))
            r.bloomThreshold = 0.75; r.bloomRadius = 26; r.bloomStrength = 0.8; r.bloomWarmth = 0.35
            r.grain = 0.02; r.shadowNoise = 0.02
            r.jpegQuality = 0.55
        case .coolCCD:
            // A small sensor in winter light: blue, bright and clear, the black
            // lifted, a strong light streaking sideways, grain, sharpened, the date.
            r.plain = true
            r.grade = CameraGrade(red: [0.11, 0.471, 0.648, 0.81, 0.965], green: [0.124, 0.485, 0.663, 0.818, 0.964], blue: [0.129, 0.506, 0.69, 0.844, 0.981],
                                   saturation: 0.82, turn: [0, 0, 0, 0, 6, 4, 0, 0], strength: [0.9, 0.85, 1, 1, 1, 1.15, 1, 1])
            r.fringe = 1.0
            r.bloomThreshold = 0.82; r.bloomRadius = 8; r.bloomStrength = 0.35
            r.flare = 0.12; r.streak = 0.035
            r.grain = 0.045; r.shadowNoise = 0.04
            r.sharpen = 0.6
            r.jpegQuality = 0.55
            r.stamp = .orange
        case .flashSnap:
            // The flash fired straight on: the middle lit, the corners falling
            // into the dark, cold through the middle, contrasty, strong colour, the date.
            r.plain = true
            r.grade = CameraGrade(red: [0.011, 0.196, 0.466, 0.724, 0.935], green: [0.009, 0.22, 0.506, 0.761, 0.956], blue: [0.026, 0.271, 0.572, 0.812, 0.971],
                                   saturation: 1.2)
            r.flashLit = true
            r.vignette = 0.5; r.vignetteRadius = 1.3
            r.grain = 0.035; r.shadowNoise = 0.04
            r.sharpen = 0.5
            r.jpegQuality = 0.6
            r.stamp = .orange
        case .slideFilm:
            // Slide film: dense colour, deep blacks, contrast, cool shadows.
            r.curve = [(0, 0.0), (0.25, 0.18), (0.5, 0.5), (0.75, 0.83), (1.0, 1.0)]
            r.saturation = 1.35; r.contrast = 1.2
            r.polynomial = (CIVector(x: 0.0, y: 1.0, z: 0.03, w: -0.03), CIVector(x: 0.0, y: 1.0, z: 0, w: 0), CIVector(x: 0.02, y: 0.98, z: -0.02, w: 0))
            r.grain = 0.015; r.midGrain = 0.05
            r.vignette = 0.25; r.vignetteRadius = 1.8
        case .fadedPrint:
            // A print kept twenty years: washed out and bright, the white gone
            // pink and the black plum, soft, hazy.
            r.plain = true
            r.grade = CameraGrade(red: [0.134, 0.583, 0.707, 0.797, 0.941], green: [0.094, 0.517, 0.631, 0.729, 0.892], blue: [0.14, 0.52, 0.62, 0.718, 0.884],
                                   saturation: 0.75, turn: [0, 0, 0, 0, 4, 6, 0, 0])
            r.softness = 0.6
            r.bloomThreshold = 0.8; r.bloomRadius = 16; r.bloomStrength = 0.3; r.bloomWarmth = 0.3
            r.grain = 0.04
            r.vignette = 0.25; r.vignetteRadius = 1.6
        case .crossProcess:
            // Film through the wrong chemicals: yellow-green light, cyan
            // shadows, loud colour and contrast.
            r.curve = [(0, 0.04), (0.25, 0.2), (0.5, 0.52), (0.75, 0.86), (1.0, 1.0)]
            r.saturation = 1.3; r.contrast = 1.2
            r.polynomial = (CIVector(x: -0.02, y: 1.05, z: 0.1, w: -0.12), CIVector(x: 0.02, y: 1.02, z: 0.06, w: -0.08), CIVector(x: 0.12, y: 0.62, z: 0.1, w: 0))
            r.vignette = 0.4; r.vignetteRadius = 1.6
            r.grain = 0.05
        case .toyCamera:
            // A plastic lens: very dark corners, loud colour, soft edges,
            // fringes, a leak of light.
            r.softness = 0.5
            r.fringe = 2.4
            r.curve = [(0, 0.02), (0.25, 0.2), (0.5, 0.52), (0.75, 0.84), (1.0, 1.0)]
            r.saturation = 1.4; r.contrast = 1.2
            r.vignette = 0.95; r.vignetteRadius = 1.15
            r.leak = true
            r.grain = 0.07
        case .cinemaReel:
            // A film still: teal shadows, warm light, a little glow, fine
            // grain, black bars leaving a 2:1 picture.
            r.curve = [(0, 0.03), (0.25, 0.22), (0.5, 0.5), (0.75, 0.8), (1.0, 0.97)]
            r.saturation = 0.95; r.contrast = 1.08
            r.polynomial = (CIVector(x: 0.0, y: 0.95, z: 0.12, w: -0.07), CIVector(x: 0.02, y: 0.97, z: 0, w: 0), CIVector(x: 0.06, y: 0.95, z: -0.08, w: 0))
            r.bloomThreshold = 0.85; r.bloomRadius = 12; r.bloomStrength = 0.2; r.bloomWarmth = 0.5
            r.halation = 0.25
            r.grain = 0.012; r.midGrain = 0.045
            r.weave = 1.9; r.flicker = 0.035
            r.letterbox = 2.0
        // 11-06: the 36 reference pictures,
        // sorted by how they look; the four groups furthest from
        // 00后梦核, each measured (the median of its
        // pictures) and fitted the same way as 00后梦核 (b37: the tone in the
        // polynomial, checked with Core Image on the Mac). Nothing of the
        // pictures kept; the names are memories, no maker's.
        case .afterSchool:
            // Tree-lined streets in the afternoon (eight pictures): yellow-
            // green in the light and in the shade, not bright (the middle at
            // about 0.39), a little soft, an early digital camera's
            // sharpening and JPEG.
            r.fringe = 0.8
            r.softness = 0.5
            r.saturation = 0.6
            r.polynomial = (CIVector(x: 0.0209, y: 1.1661, z: -0.2583, w: 0.069),
                            CIVector(x: 0.042, y: 1.102, z: -0.1977, w: 0.069),
                            CIVector(x: 0.016, y: 0.7091, z: 0.2151, w: 0.069))
            r.bloomThreshold = 0.85; r.bloomRadius = 14; r.bloomStrength = 0.4; r.bloomWarmth = 0.15
            r.grain = 0.03; r.shadowNoise = 0.03
            r.vignette = 0.15; r.vignetteRadius = 1.8
            r.sharpen = 0.35
            r.jpegQuality = 0.6
        case .computerClass:
            // A computer room, blue curtains, a kitchen under a tube (six
            // pictures): cyan-blue through the middle and the light, the
            // dark grey and noisy, flat, soft; the glow cold.
            r.smear = 1
            r.fringe = 0.6
            r.softness = 0.8
            r.saturation = 0.7
            r.polynomial = (CIVector(x: -0.0815, y: 1.2929, z: -0.242, w: 0.0703),
                            CIVector(x: -0.0028, y: 1.272, z: -0.2836, w: 0.0703),
                            CIVector(x: -0.0022, y: 1.748, z: -0.6409, w: 0.0703))
            r.bloomThreshold = 0.8; r.bloomRadius = 18; r.bloomStrength = 0.35; r.bloomWarmth = -0.3
            r.grain = 0.03; r.shadowNoise = 0.05
            r.vignette = 0.1; r.vignetteRadius = 1.8
            r.jpegQuality = 0.5
        case .birthdayNight:
            // Indoors at night with the flash (a birthday cake, a living
            // room, a New Year table): warm orange from the lamps, the flash
            // lighting the middle and the corners falling dark, what is near
            // blown white.
            r.flashLit = true
            r.fringe = 0.8
            r.softness = 0.6
            r.saturation = 0.5
            r.polynomial = (CIVector(x: 0.0435, y: 0.6909, z: 0.3286, w: 0.1597),
                            CIVector(x: 0.0221, y: 0.6704, z: 0.214, w: 0.1597),
                            CIVector(x: -0.0864, y: 0.9741, z: -0.0483, w: 0.1597))
            r.bloomThreshold = 0.75; r.bloomRadius = 12; r.bloomStrength = 0.35; r.bloomWarmth = 0.7
            r.grain = 0.03; r.shadowNoise = 0.06
            r.vignette = 0.3; r.vignetteRadius = 1.6
            r.sharpen = 0.2
            r.jpegQuality = 0.5
        case .vcdStill:
            // A still from a worn-out video (the smeared ones): half the
            // pixels, smeared four times over, colours bleeding at the edges,
            // the tones in steps, heavy JPEG blocks.
            r.pixel = 0.5
            r.smear = 4
            r.fringe = 2.0
            r.softness = 0.6
            r.saturation = 0.45
            r.polynomial = (CIVector(x: 0.0341, y: 1.1768, z: -0.3301, w: 0.0579),
                            CIVector(x: 0.0525, y: 1.1074, z: -0.2396, w: 0.0579),
                            CIVector(x: 0.0261, y: 0.9471, z: -0.0654, w: 0.0579))
            r.levels = 20
            r.chromaTrail = 5
            r.grain = 0.02
            r.jpegQuality = 0.3
        // Twenty more, and seven of those above (暖金胶卷, 即显相纸, 一次性胶卷,
        // 磁带 DV, 褪色老照片, 冷蓝 CCD, 闪光直拍), each from a set of reference
        // pictures measured: the colour of their black and of their white,
        // the tint between, how the tones are spread, where their blues,
        // greens and warm colours sit, their grain. The colour is a grade
        // fitted to those numbers on test pictures (with the same
        // arithmetic as CameraGrade's); the grain, the lens and the light
        // by eye. Nothing of the pictures kept; the names are our own.
        case .overcastRich:
            // Rich colour under a grey sky: the black lifted and a little blue, the
            // white held down, greens deep and cool, fine grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.093, 0.236, 0.424, 0.607, 0.795], green: [0.095, 0.258, 0.455, 0.628, 0.795], blue: [0.109, 0.273, 0.47, 0.644, 0.811],
                                   saturation: 1, turn: [0, 0, 0, 8, 0, 0, 0, 0], strength: [1, 1, 1, 1.1, 1, 1, 1, 1], light: [0, 0, 0, -0.1, 0, 0, 0, 0])
            r.grain = 0.03; r.midGrain = 0.04
            r.vignette = 0.2; r.vignetteRadius = 1.8
            r.sharpen = 0.2
        case .keyPhone:
            // A phone with keys: half the pixels and smeared, the light blown out
            // and glowing cold, blues gone violet, fringes, noise in the dark, heavy JPEG, a pale date.
            r.plain = true
            r.grade = CameraGrade(red: [0.011, 0.295, 0.674, 0.895, 1], green: [0.006, 0.291, 0.672, 0.895, 1], blue: [0.021, 0.326, 0.712, 0.921, 1],
                                   saturation: 1.15, turn: [0, 0, 0, 0, 10, 15, 8, 0])
            r.pixel = 0.5; r.smear = 1
            r.exposure = 0.3
            r.fringe = 2.6; r.softness = 0.9
            r.bloomThreshold = 0.7; r.bloomRadius = 14; r.bloomStrength = 0.6; r.bloomWarmth = -0.3
            r.grain = 0.03; r.shadowNoise = 0.08
            r.jpegQuality = 0.4
            r.stamp = .yellow
        case .earlyFilter:
            // An early phone's filter: the dark lifted to plum, the light gone
            // cream, soft, the corners dark.
            r.plain = true
            r.grade = CameraGrade(red: [0.228, 0.441, 0.661, 0.851, 1], green: [0.128, 0.367, 0.614, 0.828, 0.995], blue: [0.221, 0.412, 0.61, 0.781, 0.914],
                                   saturation: 0.95)
            r.softness = 0.7
            r.vignette = 0.5; r.vignetteRadius = 1.5
            r.grain = 0.03
            r.jpegQuality = 0.6
        case .warmFlash:
            // The flash straight on, and everything yellow-green: whites cream,
            // the middle lit and the corners falling off.
            r.plain = true
            r.grade = CameraGrade(red: [0.021, 0.311, 0.56, 0.727, 0.892], green: [0.016, 0.291, 0.529, 0.694, 0.861], blue: [0.015, 0.228, 0.428, 0.592, 0.777],
                                   saturation: 0.95, turn: [0, 8, 6, 0, 0, 0, 0, 0])
            r.flashLit = true
            r.vignette = 0.35; r.vignetteRadius = 1.5
            r.grain = 0.03; r.shadowNoise = 0.03
            r.sharpen = 0.3
        case .coolDaily:
            // An ordinary day, clean: pale colour, a little cool, the highlights
            // soft, crisp.
            r.plain = true
            r.grade = CameraGrade(red: [0.06, 0.456, 0.643, 0.77, 0.903], green: [0.051, 0.448, 0.635, 0.762, 0.895], blue: [0.041, 0.428, 0.61, 0.745, 0.893],
                                   saturation: 0.75, turn: [0, 0, 0, 0, 0, 5, 0, 0])
            r.bloomThreshold = 0.85; r.bloomRadius = 10; r.bloomStrength = 0.2
            r.sharpen = 0.35
        case .photoBooth:
            // A photo booth's strip: black-and-white on warm paper, gentle, the
            // light glowing a little, grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.094, 0.315, 0.574, 0.767, 0.901], green: [0.054, 0.277, 0.538, 0.733, 0.868], blue: [0.042, 0.253, 0.499, 0.684, 0.811],
                                   saturation: 1)
            r.monochrome = true
            r.softness = 0.3
            r.bloomThreshold = 0.85; r.bloomRadius = 10; r.bloomStrength = 0.25
            r.grain = 0.04; r.midGrain = 0.08
            r.vignette = 0.35; r.vignetteRadius = 1.7
        case .brightDisposable:
            // A disposable's daylight film: teal in the dark, orange and red loud,
            // blues towards cyan, fine grain, a little halation.
            r.plain = true
            r.grade = CameraGrade(red: [0.064, 0.333, 0.604, 0.804, 0.947], green: [0.108, 0.369, 0.628, 0.815, 0.943], blue: [0.125, 0.36, 0.6, 0.783, 0.919],
                                   saturation: 1.1, turn: [0, 0, 0, 0, -4, -6, 0, 0], strength: [1.2, 1.3, 1, 1, 1, 1, 1, 1])
            r.fringe = 1.2
            r.bloomThreshold = 0.85; r.bloomRadius = 10; r.bloomStrength = 0.25; r.bloomWarmth = 0.5
            r.halation = 0.25
            r.grain = 0.03; r.midGrain = 0.05
            r.vignette = 0.35; r.vignetteRadius = 1.6
        case .earlySummer:
            // Leaves and shade in early summer: greens and blues cool and gentle,
            // a touch of blue in the dark, fine.
            r.plain = true
            r.grade = CameraGrade(red: [0.017, 0.276, 0.512, 0.722, 0.954], green: [0.015, 0.297, 0.543, 0.745, 0.958], blue: [0.038, 0.294, 0.528, 0.736, 0.966],
                                   saturation: 0.95, turn: [0, 0, -5, -12, -8, -8, 0, 0], strength: [1, 1, 1, 0.9, 1, 1, 1, 1])
            r.grain = 0.01
            r.sharpen = 0.15
        case .paleYellow:
            // A gentle colour negative: a faint warm yellow through the middle,
            // low contrast, a little grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.009, 0.308, 0.57, 0.771, 0.96], green: [0.007, 0.287, 0.541, 0.749, 0.956], blue: [0.008, 0.254, 0.494, 0.718, 0.96],
                                   saturation: 0.9, turn: [0, 0, 0, 0, 0, -5, 0, 0])
            r.bloomThreshold = 0.85; r.bloomRadius = 12; r.bloomStrength = 0.2; r.bloomWarmth = 0.4
            r.grain = 0.02; r.midGrain = 0.03
            r.vignette = 0.15; r.vignetteRadius = 1.8
        case .winterSun:
            // Low winter sun: warm, the black lifted, a haze, coarser grain, blues
            // kept strong.
            r.plain = true
            r.grade = CameraGrade(red: [0.095, 0.401, 0.604, 0.762, 0.927], green: [0.09, 0.402, 0.609, 0.766, 0.929], blue: [0.072, 0.35, 0.542, 0.716, 0.914],
                                   saturation: 1.2, strength: [1, 1.15, 1, 1, 1, 1.1, 1, 1])
            r.softness = 0.4
            r.bloomThreshold = 0.8; r.bloomRadius = 16; r.bloomStrength = 0.35; r.bloomWarmth = 0.4
            r.grain = 0.045; r.midGrain = 0.08
            r.vignette = 0.2; r.vignetteRadius = 1.8
        case .nostalgicCompact:
            // A pocket camera remembered: the dark lifted to a grey teal, the
            // light yellowish, soft and glowing, fine noise.
            r.plain = true
            r.grade = CameraGrade(red: [0.163, 0.338, 0.563, 0.767, 0.96], green: [0.196, 0.362, 0.576, 0.769, 0.953], blue: [0.204, 0.335, 0.523, 0.709, 0.898],
                                   saturation: 0.9, turn: [0, 0, 0, 0, -4, -6, 0, 0])
            r.softness = 0.5
            r.bloomThreshold = 0.8; r.bloomRadius = 14; r.bloomStrength = 0.35; r.bloomWarmth = 0.3
            r.grain = 0.025; r.shadowNoise = 0.03
            r.jpegQuality = 0.6
        case .summerStreet:
            // A street in summer: rich and bright, teal in the dark and warm in
            // the light, a little grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.018, 0.327, 0.626, 0.826, 0.986], green: [0.045, 0.338, 0.621, 0.811, 0.962], blue: [0.061, 0.347, 0.624, 0.81, 0.958],
                                   saturation: 1.12, turn: [0, 0, 0, 0, 0, -5, 0, 0], strength: [1, 1, 1, 1, 1, 1.1, 1, 1])
            r.halation = 0.2
            r.grain = 0.025; r.midGrain = 0.04
            r.vignette = 0.2; r.vignetteRadius = 1.8
            r.sharpen = 0.25
        case .pinkWinter:
            // The first cold days: bright and clear, cool through the middle, the
            // whites with a pink blush.
            r.plain = true
            r.grade = CameraGrade(red: [0.097, 0.423, 0.658, 0.842, 0.96], green: [0.084, 0.409, 0.642, 0.826, 0.943], blue: [0.102, 0.461, 0.71, 0.878, 0.96],
                                   saturation: 0.85, turn: [-5, -5, 0, 0, 0, -6, 0, 0])
            r.bloomThreshold = 0.82; r.bloomRadius = 10; r.bloomStrength = 0.3
            r.grain = 0.03
            r.sharpen = 0.3
            r.jpegQuality = 0.6
        case .warmDaylight:
            // Sunlight on a street: warm yellow, reds and blues standing out, teal
            // in the black, fine grain, the corners dark.
            r.plain = true
            r.grade = CameraGrade(red: [0.015, 0.233, 0.546, 0.8, 0.96], green: [0.052, 0.234, 0.517, 0.766, 0.939], blue: [0.057, 0.191, 0.448, 0.707, 0.917],
                                   saturation: 1.25, strength: [1.15, 1, 1, 1, 1, 1.15, 1, 1])
            r.halation = 0.2
            r.grain = 0.025; r.midGrain = 0.04
            r.vignette = 0.5; r.vignetteRadius = 1.5
        case .cherryPink:
            // Blossom in April: cream and pink, a soft glow over everything,
            // grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.032, 0.323, 0.572, 0.764, 0.952], green: [0.055, 0.315, 0.544, 0.73, 0.92], blue: [0.032, 0.268, 0.485, 0.678, 0.887],
                                   saturation: 1.05, turn: [0, 0, 0, -4, 0, 0, 0, 0], strength: [1.1, 1, 1, 1, 1, 1, 1, 1.1])
            r.softness = 0.5
            r.bloomThreshold = 0.75; r.bloomRadius = 18; r.bloomStrength = 0.5; r.bloomWarmth = 0.3
            r.grain = 0.05; r.midGrain = 0.06
        case .sunsetOrange:
            // Made for the sky at sunset: orange from the black to the white,
            // strong colour, the light glowing warm.
            r.plain = true
            r.grade = CameraGrade(red: [0.194, 0.377, 0.569, 0.749, 0.933], green: [0.073, 0.268, 0.471, 0.662, 0.858], blue: [0.04, 0.196, 0.36, 0.514, 0.671],
                                   saturation: 1.35, strength: [1, 1.1, 1, 1, 1, 1.2, 1, 1])
            r.bloomThreshold = 0.8; r.bloomRadius = 14; r.bloomStrength = 0.35; r.bloomWarmth = 0.8
            r.grain = 0.015
            r.vignette = 0.25; r.vignetteRadius = 1.7
        case .yellowGreenHaze:
            // Years ago, outdoors: yellow-green through the middle, the black
            // lifted to plum and the white held down and greenish, a thin haze.
            r.plain = true
            r.grade = CameraGrade(red: [0.166, 0.363, 0.561, 0.694, 0.814], green: [0.126, 0.355, 0.585, 0.739, 0.88], blue: [0.141, 0.313, 0.514, 0.684, 0.869],
                                   saturation: 0.85, turn: [0, 0, -4, -10, 0, 0, 0, 0], strength: [1, 1, 1, 0.9, 1, 1, 1, 1])
            r.softness = 0.4
            r.bloomThreshold = 0.8; r.bloomRadius = 16; r.bloomStrength = 0.3; r.bloomWarmth = 0.1
            r.grain = 0.035
            r.jpegQuality = 0.6
        case .freshWarm:
            // A grey day made bright: lifted, clear, a warm yellow through the
            // middle, coarser grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.014, 0.454, 0.682, 0.889, 0.997], green: [0.009, 0.424, 0.643, 0.862, 1], blue: [0.022, 0.396, 0.597, 0.828, 0.999],
                                   saturation: 0.85)
            r.bloomThreshold = 0.85; r.bloomRadius = 12; r.bloomStrength = 0.25; r.bloomWarmth = 0.3
            r.grain = 0.05; r.midGrain = 0.07
        case .duskFilm:
            // Film at the end of the day: amber through the middle, the white
            // held down and warm, grain, a little halation.
            r.plain = true
            r.grade = CameraGrade(red: [0.022, 0.296, 0.538, 0.727, 0.884], green: [0.018, 0.254, 0.476, 0.673, 0.856], blue: [0.018, 0.194, 0.385, 0.594, 0.818],
                                   saturation: 1)
            r.halation = 0.3
            r.grain = 0.035; r.midGrain = 0.06
            r.vignette = 0.3; r.vignetteRadius = 1.6
        case .quietTeal:
            // Quiet water and sky: soft colour leaning teal, the white held down,
            // greens towards yellow, gentle.
            r.plain = true
            r.grade = CameraGrade(red: [0.03, 0.302, 0.49, 0.654, 0.831], green: [0.055, 0.334, 0.522, 0.669, 0.818], blue: [0.058, 0.355, 0.552, 0.695, 0.832],
                                   saturation: 1, turn: [0, 0, -5, -12, -5, -5, 0, 0], strength: [1, 1, 1, 1, 1, 0.9, 1, 1])
            r.softness = 0.2
            r.bloomThreshold = 0.85; r.bloomRadius = 12; r.bloomStrength = 0.2
            r.grain = 0.02
        case .snackStall:
            // One more, from a single reference picture (the others shown with
            // it were not of the same look).
            // A stall by the water, on film kept too long: the black gone navy,
            // the white cream, green through the middle, reds faded to salmon,
            // blues to a pale teal, yellow left strong, grain.
            r.plain = true
            r.grade = CameraGrade(red: [0.026, 0.408, 0.6, 0.762, 0.963], green: [0.022, 0.413, 0.607, 0.745, 0.899], blue: [0.203, 0.434, 0.552, 0.658, 0.794],
                                   saturation: 1, turn: [0, 0, 0, -6, -8, -14, 0, 0], strength: [0.82, 1.15, 1.25, 0.85, 1, 0.6, 1, 0.85], light: [0.1, 0, 0, 0, 0, 0.06, 0, 0])
            r.softness = 0.25
            r.bloomThreshold = 0.85; r.bloomRadius = 10; r.bloomStrength = 0.2; r.bloomWarmth = 0.4
            r.halation = 0.15
            r.grain = 0.04; r.midGrain = 0.06
            r.vignette = 0.15; r.vignetteRadius = 1.8
        case .receipt:
            // A small shop's till, its slip printed by a thermal head: black
            // and white, hard, in dots, on paper a little warm, a little faded.
            // None of the stages above (they would be seen in the viewfinder,
            // which shows the camera's own colour picture): the slip is
            // printed when a picture is kept (CameraThermal's own numbers).
            r.plain = true
            r.thermal = CameraThermal()
        }
        return r
    }
}

/// The looks themselves, on the module's 640 × 480 picture (Core Image,
/// origin at the bottom).
enum CameraBodyLook {
    private static var rect: CGRect { CameraLook.photoRect }

    /// The body's look over the finished picture. `seed` moves the grain
    /// and the leak from frame to frame (a picture taken keeps the frame's);
    /// `still` adds what only a kept picture gets (the JPEG blocks);
    /// `strength` is 浓淡 (1: the look as made).
    /// `frame`: the part of the picture that will be kept (the cover's
    /// shapes): what is printed in a corner goes to that part's corner.
    static func develop(_ image: CIImage, body: CameraBody, strength: Double = 1, seed: Int, date: Date, still: Bool = false, frame: CGRect? = nil) -> CIImage {
        guard body != .native else { return image }
        return develop(image, recipe: body.recipe, strength: strength, seed: seed, date: date, still: still, frame: frame)
    }

    static func develop(_ image: CIImage, recipe r: CameraBodyRecipe, strength: Double = 1, seed: Int, date: Date, still: Bool, frame: CGRect? = nil) -> CIImage {
        printed(look(image, recipe: r, strength: strength, seed: seed, still: still), recipe: r, seed: seed, date: date, frame: frame)
    }

    /// The body's picture at a strength (浓淡), before anything is printed
    /// on it. Stronger than made: the recipe's amounts taken further.
    /// Lighter: so much of the body's picture, the rest the one before it.
    static func look(_ image: CIImage, recipe r: CameraBodyRecipe, strength: Double, seed: Int, still: Bool) -> CIImage {
        if strength > 1 { return look(image, recipe: r.stronger(strength), seed: seed, still: still) }
        let made = look(image, recipe: r, seed: seed, still: still)
        return strength < 1 ? mixed(image, made, share: strength) : made
    }

    /// `share` of `made` and the rest of `plain` (0…1) — of the two as they
    /// would be seen (what a picture has above white or below black is cut
    /// off first, so that half the look is halfway between the two).
    private static func mixed(_ plain: CIImage, _ made: CIImage, share: Double) -> CIImage {
        func seen(_ image: CIImage) -> CIImage {
            let clamp = CIFilter.colorClamp()
            clamp.inputImage = image.cropped(to: rect)
            clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            return (clamp.outputImage ?? image).cropped(to: rect)
        }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = seen(plain)
        mix.targetImage = seen(made)
        mix.time = Float(min(1, max(0, share)))
        return (mix.outputImage ?? made).cropped(to: rect)
    }

    /// The body's picture before anything is printed on it: the light, the
    /// lens, the colour and tone, the grain, the signal.
    static func look(_ image: CIImage, recipe r: CameraBodyRecipe, seed: Int, still: Bool) -> CIImage {
        var out = image
        // The light: a flash from the camera, the exposure.
        if r.flashLit { out = flashLit(out) }
        if r.exposure != 0 { out = exposure(out, ev: r.exposure) }
        // The signal's pixels (a camcorder's, an early digital camera's).
        if r.pixel < 1 {
            let small = CameraLook.scaled(out, by: r.pixel)
            out = small.transformed(by: CGAffineTransform(scaleX: 1 / r.pixel, y: 1 / r.pixel)).clampedToExtent().cropped(to: rect)
        }
        if r.smear > 0 { out = smear(out, passes: r.smear) }
        // The lens.
        if r.fringe > 0 { out = fringes(out, pixels: r.fringe) }
        if r.softness > 0 { out = blur(out, radius: r.softness) }
        // The film's or sensor's colour and tone.
        if r.monochrome { out = mono(out) }
        out = curve(out, r.curve)
        if r.saturation != 1 || r.contrast != 1 { out = controls(out, saturation: r.saturation, contrast: r.contrast) }
        if r.cast.r != (1, 0) || r.cast.g != (1, 0) || r.cast.b != (1, 0) { out = cast(out, r: r.cast.r, g: r.cast.g, b: r.cast.b) }
        if let poly = r.polynomial { out = polynomial(out, poly) }
        if let grade = r.grade { out = graded(out, grade) }
        // A tape's colour, trailing behind its brightness.
        if r.chromaTrail > 0 { out = chromaTrail(out, pixels: r.chromaTrail) }
        // Light blooming in the lens, the highlights spilling; film's
        // halation; a strong light streaking across a small sensor.
        if r.bloomStrength > 0 { out = bloom(out, threshold: r.bloomThreshold, radius: r.bloomRadius, strength: r.bloomStrength, warmth: r.bloomWarmth) }
        if r.halation > 0 { out = halation(out, strength: r.halation) }
        if r.flare > 0 || r.streak > 0 { out = streaks(out, flare: r.flare, streak: r.streak) }
        // The grain, the noise in the dark.
        if r.grain > 0 { out = CameraLook.addGrain(out, amount: r.grain, seed: seed &+ 11) }
        if r.midGrain > 0 { out = midGrain(out, amount: r.midGrain, seed: seed &+ 17) }
        if r.shadowNoise > 0 { out = shadowNoise(out, amount: r.shadowNoise, seed: seed &+ 29) }
        if r.vignette > 0 { out = vignette(out, intensity: r.vignette, radius: r.vignetteRadius) }
        if r.leak { out = leak(out, seed: seed) }
        // The signal: scan lines, posterised colours, the camera's sharpening.
        if r.scanlines { out = scanlines(out) }
        if r.levels > 0 {
            if r.dither > 0 { out = ordered(out, spread: r.dither, cell: 1 / r.pixel) }
            out = posterize(out, levels: r.levels)
        }
        if r.sharpen > 0 { out = sharpen(out, intensity: r.sharpen) }
        if !still { out = moving(out, recipe: r, seed: seed) }
        if still, r.jpegQuality < 1 { out = jpegBlocks(out, quality: r.jpegQuality) }
        return out
    }

    /// What is put on the picture afterwards: the black bars, the date the
    /// camera prints, the sheet of paper.
    static func printed(_ image: CIImage, recipe r: CameraBodyRecipe, seed: Int, date: Date, frame: CGRect? = nil) -> CIImage {
        var out = image
        if r.letterbox > 0 { out = letterbox(out, aspect: r.letterbox) }
        if let style = r.stamp { out = stamp(out, date: date, style: style, frame: frame) }
        if r.paper { out = paper(out, seed: seed) }
        return out
    }

    /// The upper screen's picture for a body: the middle 5:3 as always, or,
    /// on paper, the whole sheet fitted (its borders are part of the look).
    static func screen(_ photo: CIImage, body: CameraBody) -> CIImage {
        guard body.hasPaper else { return CameraLook.screen(photo) }
        let size = CameraLook.screenSize
        let scale = size.height / rect.height
        let sheet = CameraLook.scaled(photo, by: scale).cropped(to: CGRect(x: 0, y: 0, width: rect.width * scale, height: size.height))
        let background = CIImage(color: CIColor(red: 0.16, green: 0.15, blue: 0.14)).cropped(to: CGRect(origin: .zero, size: size))
        let moved = sheet.transformed(by: CGAffineTransform(translationX: (size.width - rect.width * scale) / 2, y: 0))
        let over = CIFilter.sourceOverCompositing()
        over.inputImage = moved
        over.backgroundImage = background
        return (over.outputImage ?? moved).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// 11-06: the shooting settings over the lens's finish, before the body
    /// (the sensor's part): the exposure and the ISO's gain, the white
    /// balance's colour, the ISO's noise and dullness.
    static func shoot(_ image: CIImage, _ settings: CameraShooting, seed: Int) -> CIImage {
        var r = CameraBodyRecipe()
        r.exposure = Float(settings.exposure) + settings.iso.gainEV
        let g = settings.whiteBalance.gains
        r.cast = ((g.r, 0), (g.g, 0), (g.b, 0))
        r.saturation = settings.iso.saturation
        r.grain = settings.iso.grain
        r.shadowNoise = settings.iso.noise
        return develop(image, recipe: r, seed: seed &+ 7, date: Date(), still: false)
    }
    /// The date an old camera prints (orange, lower right), for the 日期
    /// setting when the body prints none of its own.
    static func dateStamp(_ image: CIImage, date: Date, frame: CGRect? = nil) -> CIImage {
        stamp(image, date: date, style: .orange, frame: frame)
    }

    // MARK: The pieces

    static func exposure(_ image: CIImage, ev: Float) -> CIImage {
        let f = CIFilter.exposureAdjust()
        f.inputImage = image
        f.ev = ev
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// A flash fired from the camera: the middle lit (+1 EV), falling off to
    /// −0.6 EV at the corners, a little colder.
    static func flashLit(_ image: CIImage) -> CIImage {
        let lit = exposure(image, ev: 1.0)
        let dim = exposure(image, ev: -0.6)
        let mask = CIFilter.radialGradient()
        mask.center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        mask.radius0 = Float(rect.width) * 0.12
        mask.radius1 = Float(rect.width) * 0.62
        mask.color0 = CIColor(red: 1, green: 1, blue: 1)
        mask.color1 = CIColor(red: 0, green: 0, blue: 0)
        guard let gradient = mask.outputImage?.cropped(to: rect) else { return lit }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = lit
        blend.backgroundImage = dim
        blend.maskImage = gradient
        return cast((blend.outputImage ?? lit).cropped(to: rect), r: (0.98, 0), g: (1.0, 0), b: (1.04, 0.01))
    }
    /// Detail smeared, as an old small picture blown up and cleaned up is:
    /// a median at half size, then up again (a sharpening after it brings
    /// the halos).
    private static func smear(_ image: CIImage, passes: Int) -> CIImage {
        var small = CameraLook.scaled(image, by: 0.5)
        let extent = small.extent
        for _ in 0..<passes {
            let f = CIFilter.median()
            f.inputImage = small.clampedToExtent()
            small = (f.outputImage ?? small).cropped(to: extent)
        }
        return small.transformed(by: CGAffineTransform(scaleX: 2, y: 2)).clampedToExtent().cropped(to: rect)
    }
    /// Black bars above and below, leaving a picture `aspect` wide to 1 high.
    private static func letterbox(_ image: CIImage, aspect: CGFloat) -> CIImage {
        let bar = max(0, (rect.height - rect.width / aspect) / 2)
        guard bar > 0 else { return image }
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
        let bars = black.cropped(to: CGRect(x: 0, y: rect.maxY - bar, width: rect.width, height: bar))
            .composited(over: black.cropped(to: CGRect(x: 0, y: 0, width: rect.width, height: bar)))
        return bars.composited(over: image).cropped(to: rect)
    }

    private static func curve(_ image: CIImage, _ points: [(Double, Double)]) -> CIImage {
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = CGPoint(x: points[0].0, y: points[0].1)
        f.point1 = CGPoint(x: points[1].0, y: points[1].1)
        f.point2 = CGPoint(x: points[2].0, y: points[2].1)
        f.point3 = CGPoint(x: points[3].0, y: points[3].1)
        f.point4 = CGPoint(x: points[4].0, y: points[4].1)
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func controls(_ image: CIImage, saturation: Float, contrast: Float) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = saturation
        f.contrast = contrast
        f.brightness = 0
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// A colour cast: each channel scaled and offset.
    private static func cast(_ image: CIImage, r: (CGFloat, CGFloat), g: (CGFloat, CGFloat), b: (CGFloat, CGFloat)) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: r.0, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: g.0, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: b.0, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: r.1, y: g.1, z: b.1, w: 0)
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func polynomial(_ image: CIImage, _ p: (r: CIVector, g: CIVector, b: CIVector)) -> CIImage {
        let f = CIFilter.colorPolynomial()
        f.inputImage = image
        f.redCoefficients = p.r
        f.greenCoefficients = p.g
        f.blueCoefficients = p.b
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// A grade's cube, kept: a body's is made once (浓淡 above 100% makes
    /// another).
    private static var cubes: [CameraGrade: Data] = [:]
    private static let cubeLock = NSLock()
    private static let cubeSide = 32
    private static func cube(_ grade: CameraGrade) -> Data {
        cubeLock.lock(); defer { cubeLock.unlock() }
        if let kept = cubes[grade] { return kept }
        if cubes.count > 48 { cubes.removeAll() }
        let made = grade.cube(side: cubeSide).withUnsafeBufferPointer { Data(buffer: $0) }
        cubes[grade] = made
        return made
    }
    private static func graded(_ image: CIImage, _ grade: CameraGrade) -> CIImage {
        let f = CIFilter.colorCube()
        f.inputImage = image
        f.cubeDimension = Float(cubeSide)
        f.cubeData = cube(grade)
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func mono(_ image: CIImage) -> CIImage {
        let f = CIFilter.photoEffectMono()
        f.inputImage = image
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func blur(_ image: CIImage, radius: Float) -> CIImage {
        let f = CIFilter.gaussianBlur()
        f.inputImage = image.clampedToExtent()
        f.radius = radius
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func sharpen(_ image: CIImage, intensity: Float) -> CIImage {
        let f = CIFilter.unsharpMask()
        f.inputImage = image.clampedToExtent()
        f.radius = 1.2
        f.intensity = intensity
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func posterize(_ image: CIImage, levels: Float) -> CIImage {
        let f = CIFilter.colorPosterize()
        f.inputImage = image
        f.levels = levels
        return (f.outputImage ?? image).cropped(to: rect)
    }
    private static func vignette(_ image: CIImage, intensity: Float, radius: Float) -> CIImage {
        let f = CIFilter.vignetteEffect()
        f.inputImage = image
        f.center = CGPoint(x: rect.midX, y: rect.midY)
        f.radius = Float(rect.width) * 0.5 * radius
        f.intensity = intensity
        f.falloff = 0.5
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// One channel of a picture, as a picture (the others black).
    private static func channel(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// Two one-channel pictures into one: the larger of each component.
    /// b37: was an addition, which added the alphas too — each channel
    /// picture is opaque, so the fringed picture had an alpha of up to 3,
    /// and every filter after it that works on unpremultiplied colour
    /// (the polynomial, the tone curve) or composites (the scan lines'
    /// multiply) went wrong away from the middle: offsets counted three
    /// times (brighter), the scan lines black. The maximum keeps alpha 1.
    private static func merge(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.maximumCompositing()
        f.inputImage = a
        f.backgroundImage = b
        return (f.outputImage ?? b).cropped(to: rect)
    }
    /// The lens's colour fringes: red shifted one way and blue the other,
    /// only towards the edges (a radial mask keeps the middle clean), as a
    /// cheap lens does.
    private static func fringes(_ image: CIImage, pixels: CGFloat) -> CIImage {
        let red = channel(image, r: 1, g: 0, b: 0).transformed(by: CGAffineTransform(translationX: pixels, y: 0)).clampedToExtent().cropped(to: rect)
        let green = channel(image, r: 0, g: 1, b: 0)
        let blue = channel(image, r: 0, g: 0, b: 1).transformed(by: CGAffineTransform(translationX: -pixels, y: 0)).clampedToExtent().cropped(to: rect)
        let shifted = merge(merge(red, green), blue)
        let mask = CIFilter.radialGradient()
        mask.center = CGPoint(x: rect.midX, y: rect.midY)
        mask.radius0 = Float(rect.width) * 0.18
        mask.radius1 = Float(rect.width) * 0.62
        mask.color0 = CIColor(red: 0, green: 0, blue: 0)
        mask.color1 = CIColor(red: 1, green: 1, blue: 1)
        guard let gradient = mask.outputImage?.cropped(to: rect) else { return shifted }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = shifted
        blend.backgroundImage = image
        blend.maskImage = gradient
        return (blend.outputImage ?? shifted).cropped(to: rect)
    }
    /// Highlights blooming: what is brighter than `threshold` is taken out,
    /// blurred, tinted, and screened back over the picture.
    private static func bloom(_ image: CIImage, threshold: Float, radius: Float, strength: Float, warmth: Float) -> CIImage {
        let t = CGFloat(min(0.98, threshold))
        let gain = 1 / (1 - t)
        let lift = CIFilter.colorPolynomial()
        lift.inputImage = image
        let coefficients = CIVector(x: -t * gain, y: gain, z: 0, w: 0)
        lift.redCoefficients = coefficients
        lift.greenCoefficients = coefficients
        lift.blueCoefficients = coefficients
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = lift.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let highlights = clamp.outputImage?.cropped(to: rect) else { return image }
        let glow = CIFilter.gaussianBlur()
        glow.inputImage = highlights.clampedToExtent()
        glow.radius = radius
        guard let blurred = glow.outputImage?.cropped(to: rect) else { return image }
        let tint = CIFilter.colorMatrix()
        tint.inputImage = blurred
        let s = CGFloat(strength), w = CGFloat(warmth)
        tint.rVector = CIVector(x: s, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: s * (1 - 0.35 * w), z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: s * (1 - 0.7 * w), w: 0)
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let screen = CIFilter.screenBlendMode()
        screen.inputImage = tint.outputImage
        screen.backgroundImage = image
        return (screen.outputImage ?? image).cropped(to: rect)
    }
    /// What is nearly white, as a picture of its own: nothing where the
    /// picture's brightness is below `threshold`, 1 at white. (By
    /// brightness, not by each colour: a strong red is not a strong light.)
    private static func highlights(_ image: CIImage, above threshold: CGFloat) -> CIImage? {
        let t = min(0.98, threshold), gain = 1 / (1 - t)
        let luma = CIFilter.colorMatrix()
        luma.inputImage = image
        luma.rVector = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        luma.gVector = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        luma.bVector = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        luma.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let lift = CIFilter.colorPolynomial()
        lift.inputImage = luma.outputImage
        let coefficients = CIVector(x: -t * gain, y: gain, z: 0, w: 0)
        lift.redCoefficients = coefficients
        lift.greenCoefficients = coefficients
        lift.blueCoefficients = coefficients
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = lift.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return clamp.outputImage?.cropped(to: rect)
    }
    /// A light of a colour laid over the picture (a screen: it can only
    /// brighten, and never past white).
    private static func screened(_ light: CIImage, r: CGFloat, g: CGFloat, b: CGFloat, strength s: CGFloat, over image: CIImage) -> CIImage {
        let tint = CIFilter.colorMatrix()
        tint.inputImage = light
        tint.rVector = CIVector(x: s * r, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: s * g, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: s * b, w: 0)
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let screen = CIFilter.screenBlendMode()
        screen.inputImage = tint.outputImage
        screen.backgroundImage = image
        return (screen.outputImage ?? image).cropped(to: rect)
    }
    /// Film's halation: the highlights' light spread wide and red-orange
    /// (it shows where a highlight meets the dark; over white it is lost).
    private static func halation(_ image: CIImage, strength: Float) -> CIImage {
        guard let light = highlights(image, above: 0.8) else { return image }
        // (At half size: the light is spread wide anyway.)
        let small = CameraLook.scaled(light, by: 0.5)
        let glow = CIFilter.gaussianBlur()
        glow.inputImage = small.clampedToExtent()
        glow.radius = 9
        guard let spread = glow.outputImage?.cropped(to: small.extent).transformed(by: CGAffineTransform(scaleX: 2, y: 2)).clampedToExtent().cropped(to: rect) else { return image }
        return screened(spread, r: 1, g: 0.34, b: 0.12, strength: CGFloat(strength), over: image)
    }
    /// A strong light on a small sensor: it runs along the rows (`flare`)
    /// and, fainter, up and down the columns (`streak`), a little blue.
    /// (A small light spread so far is faint, so it is brought up.)
    private static func streaks(_ image: CIImage, flare: Float, streak: Float) -> CIImage {
        guard let light = highlights(image, above: 0.88) else { return image }
        var out = image
        // (At half size, the runs half as long.)
        let small = CameraLook.scaled(light, by: 0.5)
        for (angle, radius, strength) in [(Float(0), Float(22), flare), (Float.pi / 2, Float(32), streak)] where strength > 0 {
            let run = CIFilter.motionBlur()
            run.inputImage = small
            run.radius = radius
            run.angle = angle
            guard let spread = run.outputImage?.cropped(to: small.extent).transformed(by: CGAffineTransform(scaleX: 2, y: 2)).cropped(to: rect) else { continue }
            out = screened(spread, r: 0.92, g: 0.96, b: 1.08, strength: CGFloat(strength) * 2.2, over: out)
        }
        return out
    }
    /// Film's grain: random grey strongest in the middle tones
    /// (4 · L · (1 − L)), next to nothing in black and in white.
    private static func midGrain(_ image: CIImage, amount: Double, seed: Int) -> CIImage {
        guard let patch = CameraLook.noisePatch(seed: seed, mx: 4513, my: 71_993) else { return image }
        let a = CGFloat(amount)
        let grey = CIFilter.colorMatrix()
        grey.inputImage = patch
        grey.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.gVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.bVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.biasVector = CIVector(x: -a / 2, y: -a / 2, z: -a / 2, w: 1)
        let luma = CIFilter.colorMatrix()
        luma.inputImage = image
        luma.rVector = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        luma.gVector = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        luma.bVector = CIVector(x: 0.3, y: 0.59, z: 0.11, w: 0)
        luma.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let middle = CIFilter.colorPolynomial()
        middle.inputImage = luma.outputImage
        let hump = CIVector(x: 0, y: 4, z: -4, w: 0)
        middle.redCoefficients = hump
        middle.greenCoefficients = hump
        middle.blueCoefficients = hump
        let weighted = CIFilter.multiplyCompositing()
        weighted.inputImage = grey.outputImage
        weighted.backgroundImage = middle.outputImage
        guard let noise = weighted.outputImage?.cropped(to: rect) else { return image }
        return CameraLook.addNoise(noise, to: image)
    }
    /// A tape's colour dragged to the right of its brightness: the picture
    /// smeared along its rows and moved over lends its colour; the
    /// brightness stays the sharp picture's.
    private static func chromaTrail(_ image: CIImage, pixels: CGFloat) -> CIImage {
        let drag = CIFilter.motionBlur()
        drag.inputImage = image.clampedToExtent()
        drag.radius = Float(pixels)
        drag.angle = 0
        guard let dragged = drag.outputImage?.transformed(by: CGAffineTransform(translationX: pixels, y: 0)).cropped(to: rect) else { return image }
        let f = CIFilter.colorBlendMode()
        f.inputImage = dragged
        f.backgroundImage = image
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// The threshold pattern of an ordered dither, eight cells square: each
    /// of 0 … 63 once, spread so that neighbours are far apart in value.
    private static let thresholds: CIImage? = {
        var order = [[0]]
        for _ in 0..<3 {
            let n = order.count
            var next = Array(repeating: Array(repeating: 0, count: n * 2), count: n * 2)
            for y in 0..<n {
                for x in 0..<n {
                    let v = order[y][x] * 4
                    next[y][x] = v; next[y][x + n] = v + 2; next[y + n][x] = v + 3; next[y + n][x + n] = v + 1
                }
            }
            order = next
        }
        var bytes = [UInt8]()
        for row in order {
            for v in row {
                let b = UInt8((Double(v) + 0.5) / 64 * 255)
                bytes.append(contentsOf: [b, b, b, 255])
            }
        }
        return CIImage(bitmapData: Data(bytes), bytesPerRow: 32, size: CGSize(width: 8, height: 8), format: .RGBA8, colorSpace: nil)
    }()
    /// An ordered dither: each colour pushed up or down by its cell's
    /// threshold (± spread / 2) before the colours are stepped, so that a
    /// tone between two steps becomes a pattern of the two. `cell`: a
    /// cell's side in pixels (one of the signal's pixels).
    private static func ordered(_ image: CIImage, spread: Float, cell: CGFloat) -> CIImage {
        guard let thresholds else { return image }
        let tile = CIFilter.affineTile()
        tile.inputImage = thresholds.samplingNearest().transformed(by: CGAffineTransform(scaleX: cell, y: cell))
        tile.transform = .identity
        guard let pattern = tile.outputImage?.cropped(to: rect) else { return image }
        let s = CGFloat(spread)
        let push = CIFilter.colorMatrix()
        push.inputImage = pattern
        push.rVector = CIVector(x: s, y: 0, z: 0, w: 0)
        push.gVector = CIVector(x: s, y: 0, z: 0, w: 0)
        push.bVector = CIVector(x: s, y: 0, z: 0, w: 0)
        push.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        push.biasVector = CIVector(x: -s / 2, y: -s / 2, z: -s / 2, w: 1)
        guard let pushed = push.outputImage?.cropped(to: rect) else { return image }
        return CameraLook.addNoise(pushed, to: image)
    }
    /// 0 … 1 from a whole number, the same each time.
    private static func unit(_ n: Int) -> Double { Double(((n &* 2_654_435_761 &+ 12_345) >> 7) & 0xFFFF) / 65_535 }
    /// What only a moving picture has (the viewfinder, a recording; not a
    /// kept still): the frame weaving in the gate, the lamp's flicker, the
    /// bottom of a tape's picture breaking up. `seed` counts the frames.
    private static func moving(_ image: CIImage, recipe r: CameraBodyRecipe, seed: Int) -> CIImage {
        var out = image
        let s = Double(seed)
        if r.weave > 0 {
            let dx = r.weave * 0.8 * CGFloat(0.7 * sin(s * 0.37) + 0.3 * sin(s * 0.113 + 1.3))
            let dy = r.weave * CGFloat(0.7 * sin(s * 0.29 + 2.1) + 0.3 * sin(s * 0.091 + 0.4))
            out = out.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: rect)
        }
        if r.flicker > 0 {
            let k = 1 + CGFloat(r.flicker) * CGFloat(unit(seed) * 2 - 1)
            out = cast(out, r: (k, 0), g: (k, 0), b: (k, 0))
        }
        if r.trackingBand > 0 { out = trackingBand(out, amount: r.trackingBand, seed: seed) }
        return out
    }
    /// The bottom of a tape's picture: a strip of noise, strongest at the
    /// edge, its height changing a few times a second.
    private static func trackingBand(_ image: CIImage, amount: Float, seed: Int) -> CIImage {
        guard let patch = CameraLook.noisePatch(seed: seed &+ 43, mx: 3571, my: 50_021) else { return image }
        let height = rect.height * CGFloat(0.035 + 0.02 * unit(seed / 4))
        let a = CGFloat(amount)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: rect.midX, y: rect.minY)
        gradient.point1 = CGPoint(x: rect.midX, y: rect.minY + height)
        gradient.color0 = CIColor(red: a, green: a, blue: a, alpha: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let mask = gradient.outputImage?.cropped(to: rect) else { return image }
        let f = CIFilter.blendWithMask()
        f.inputImage = mono(patch)
        f.backgroundImage = image
        f.maskImage = mask
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// Noise that lives in the dark: random grey, weighted by how dark the
    /// picture is there (1 − luminance), added to it (11-06: the noise made
    /// opaque first and laid on as CameraLook.addNoise does — see there).
    private static func shadowNoise(_ image: CIImage, amount: Double, seed: Int) -> CIImage {
        guard let patch = CameraLook.noisePatch(seed: seed, mx: 6131, my: 92_821) else { return image }
        let a = CGFloat(amount)
        let grey = CIFilter.colorMatrix()
        grey.inputImage = patch
        grey.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.gVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.bVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.biasVector = CIVector(x: -a / 2, y: -a / 2, z: -a / 2, w: 1)
        let dark = CIFilter.colorMatrix()
        dark.inputImage = image
        dark.rVector = CIVector(x: -0.3, y: -0.59, z: -0.11, w: 0)
        dark.gVector = CIVector(x: -0.3, y: -0.59, z: -0.11, w: 0)
        dark.bVector = CIVector(x: -0.3, y: -0.59, z: -0.11, w: 0)
        dark.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        dark.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        let weighted = CIFilter.multiplyCompositing()
        weighted.inputImage = grey.outputImage
        weighted.backgroundImage = dark.outputImage
        guard let noise = weighted.outputImage?.cropped(to: rect) else { return image }
        return CameraLook.addNoise(noise, to: image)
    }
    /// Scan lines: every other row a little darker.
    private static func scanlines(_ image: CIImage) -> CIImage {
        let stripes = CIFilter.stripesGenerator()
        stripes.center = CGPoint(x: 0, y: 0)
        stripes.color0 = CIColor(red: 1, green: 1, blue: 1)
        stripes.color1 = CIColor(red: 0.84, green: 0.84, blue: 0.86)
        stripes.width = 1.5
        stripes.sharpness = 1
        guard let lines = stripes.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: rect) else { return image }
        let f = CIFilter.multiplyCompositing()
        f.inputImage = lines
        f.backgroundImage = image
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// A leak of light at the right or left edge: orange, fading in from
    /// the edge, its place and strength from the seed (steady for a few
    /// seconds, so the preview does not flicker).
    private static func leak(_ image: CIImage, seed: Int) -> CIImage {
        let phase = (seed / 90) % 4
        let fromRight = phase % 2 == 0
        let strength = phase < 2 ? 0.55 : 0.4
        let gradient = CIFilter.linearGradient()
        let x0 = fromRight ? rect.maxX : rect.minX
        let x1 = fromRight ? rect.maxX - 230 : rect.minX + 230
        gradient.point0 = CGPoint(x: x0, y: rect.midY)
        gradient.point1 = CGPoint(x: x1, y: rect.midY)
        gradient.color0 = CIColor(red: 1.0 * strength, green: 0.45 * strength, blue: 0.12 * strength, alpha: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let light = gradient.outputImage?.cropped(to: rect) else { return image }
        let f = CIFilter.screenBlendMode()
        f.inputImage = light
        f.backgroundImage = image
        return (f.outputImage ?? image).cropped(to: rect)
    }
    /// The JPEG blocks of a cheap camera's file: the picture written as a
    /// JPEG of low quality and read back (stills only; a shared context).
    private static let blockContext = CIContext(options: [.cacheIntermediates: false])
    private static func jpegBlocks(_ image: CIImage, quality: Float) -> CIImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let data = blockContext.jpegRepresentation(of: image, colorSpace: space, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]),
              let back = CIImage(data: data) else { return image }
        return back.cropped(to: rect)
    }

    // MARK: The date stamp and the paper (drawn with Core Graphics, cached)

    enum StampStyle { case orange, yellow, tape }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var stampCache: [String: CIImage] = [:]
    nonisolated(unsafe) private static var paperCache: CIImage?
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yy MM dd"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd/yyyy  HH:mm"
        return f
    }()

    /// The date in the corner, as a film camera's data back prints it:
    /// orange or pale-yellow figures with a glow at the bottom right; the
    /// tape's style is small white text with REC at the top left.
    private static func stamp(_ image: CIImage, date: Date, style: StampStyle, frame: CGRect? = nil) -> CIImage {
        #if os(iOS)
        let text = style == .tape ? timeFormatter.string(from: date) : "'" + dateFormatter.string(from: date)
        let key = "\(style)|\(text)"
        cacheLock.lock()
        var overlay = stampCache[key]
        cacheLock.unlock()
        if overlay == nil {
            overlay = drawStamp(text: text, style: style)
            cacheLock.lock()
            if stampCache.count > 8 { stampCache.removeAll() }
            stampCache[key] = overlay
            cacheLock.unlock()
        }
        guard let overlay else { return image }
        // The date is drawn in the whole picture's lower right corner: for a
        // part of the picture it is moved to that part's.
        var placed = overlay
        if let frame, frame != rect {
            placed = overlay.transformed(by: CGAffineTransform(translationX: frame.maxX - rect.maxX, y: frame.minY - rect.minY))
        }
        let f = CIFilter.sourceOverCompositing()
        f.inputImage = placed
        f.backgroundImage = image
        return (f.outputImage ?? image).cropped(to: rect)
        #else
        return image
        #endif
    }

    #if os(iOS)
    private static func drawStamp(text: String, style: StampStyle) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            switch style {
            case .orange, .yellow:
                let colour = style == .orange ? UIColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 0.95) : UIColor(red: 0.98, green: 0.92, blue: 0.55, alpha: 0.95)
                let font = UIFont.monospacedDigitSystemFont(ofSize: 27, weight: .bold)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour, .kern: 2.5]
                let size = (text as NSString).size(withAttributes: attributes)
                let origin = CGPoint(x: rect.width - size.width - 26, y: rect.height - size.height - 18)
                cg.setShadow(offset: .zero, blur: 7, color: colour.withAlphaComponent(0.85).cgColor)
                (text as NSString).draw(at: origin, withAttributes: attributes)
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                (text as NSString).draw(at: origin, withAttributes: attributes)
            case .tape:
                let white = UIColor(white: 0.95, alpha: 0.92)
                let font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: white]
                cg.setShadow(offset: CGSize(width: 1, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.7).cgColor)
                ("● REC" as NSString).draw(at: CGPoint(x: 22, y: 16), withAttributes: [.font: font, .foregroundColor: UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 0.95)])
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: CGPoint(x: rect.width - size.width - 22, y: rect.height - size.height - 16), withAttributes: attributes)
            }
        }
        guard let cg = image.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }
    #endif

    /// A sheet of cream paper with the picture inset, four equal borders
    /// (36 px), the corners barely rounded, a faint grain in the paper.
    private static func paper(_ image: CIImage, seed: Int) -> CIImage {
        let border: CGFloat = 36
        let inner = rect.insetBy(dx: border, dy: border)
        let scale = inner.width / rect.width
        let picture = CameraLook.scaled(image, by: scale).cropped(to: CGRect(x: 0, y: 0, width: inner.width, height: inner.height))
            .transformed(by: CGAffineTransform(translationX: inner.minX, y: inner.minY))
        var sheet = CIImage(color: CIColor(red: 0.97, green: 0.95, blue: 0.90)).cropped(to: rect)
        sheet = CameraLook.addGrain(sheet, amount: 0.025, seed: 5)
        let f = CIFilter.sourceOverCompositing()
        f.inputImage = picture
        f.backgroundImage = sheet
        return (f.outputImage ?? image).cropped(to: rect)
    }
}

#if DEBUG
// MARK: - The bench (a DEBUG build)

/// A drawn chart through every body, away from the camera: what each makes
/// of it (numbers a test holds the bodies to) and how long a frame of it
/// takes on this device. `--foldarc-camera-bench` runs it a few seconds
/// after the launch; what it found is a text file beside the traces, a line
/// a body.
enum CameraBench {
    static let argument = "--foldarc-camera-bench"
    /// The file's layout: a change to the chart or to what is measured
    /// counts it up (the numbers kept by the test are of one revision).
    static let revision = 2
    static let fileName = "camera-bench.txt"
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldArcTrace", isDirectory: true).appendingPathComponent(fileName)
    }

    static func runIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) { run() }
    }

    // The chart, 640 × 480 (Core Graphics, origin at the bottom): eight
    // greys across the top, eight colours under them; below, a flat grey
    // field on the left (its corner against its inner end: the vignette;
    // how much its pixels differ: the grain) and a dark one on the right
    // with a white disc (what spills round it: the bloom).
    static let greys: [CGFloat] = [0, 1.0 / 7, 2.0 / 7, 3.0 / 7, 4.0 / 7, 5.0 / 7, 6.0 / 7, 1]
    static let colours: [(name: String, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        ("red", 0.80, 0.20, 0.20), ("green", 0.20, 0.70, 0.25), ("blue", 0.20, 0.30, 0.80), ("cyan", 0.20, 0.75, 0.80),
        ("magenta", 0.80, 0.25, 0.75), ("yellow", 0.90, 0.85, 0.20), ("skin", 0.85, 0.65, 0.52), ("sky", 0.55, 0.72, 0.92),
    ]
    static let disc = (centre: CGPoint(x: 480, y: 150), radius: CGFloat(28))

    static func chart() -> CGImage? {
        guard let c = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CameraLook.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ box: CGRect) {
            c.setFillColor(CGColor(colorSpace: CameraLook.colorSpace, components: [r, g, b, 1]) ?? CGColor(gray: 0.5, alpha: 1))
            c.fill(box)
        }
        fill(0.5, 0.5, 0.5, CGRect(x: 0, y: 0, width: 640, height: 480))
        for (i, v) in greys.enumerated() { fill(v, v, v, CGRect(x: CGFloat(i) * 80, y: 360, width: 80, height: 120)) }
        for (i, k) in colours.enumerated() { fill(k.r, k.g, k.b, CGRect(x: CGFloat(i) * 80, y: 240, width: 80, height: 120)) }
        fill(0.08, 0.08, 0.08, CGRect(x: 320, y: 0, width: 320, height: 240))
        c.setFillColor(CGColor(colorSpace: CameraLook.colorSpace, components: [1, 1, 1, 1]) ?? CGColor(gray: 1, alpha: 1))
        c.fillEllipse(in: CGRect(x: disc.centre.x - disc.radius, y: disc.centre.y - disc.radius, width: disc.radius * 2, height: disc.radius * 2))
        return c.makeImage()
    }

    /// What a body made of the chart (all 0…1).
    struct Reading {
        /// The eight greys' brightness, dark to light.
        var tone: [Double] = []
        /// The eight colours, r g b each.
        var colours: [Double] = []
        /// The flat field's corner against its inner end (1: no vignette).
        var corner = 0.0
        /// How much the flat field's pixels differ (the grain).
        var noise = 0.0
        /// The dark round the disc, less the dark far from it (the bloom).
        var glow = 0.0
        /// The whole picture with what is printed on it: r g b.
        var whole: [Double] = []
    }

    /// A drawn picture's pixels: RGBA, the top row first (as a CGImage has
    /// them), `rowBytes` to a row.
    private struct Pixels {
        var data: [UInt8] = []
        var rowBytes = 0
        var isEmpty: Bool { data.isEmpty || rowBytes < 640 * 4 }
        init(_ image: CIImage, context: CIContext) {
            guard let drawn = context.createCGImage(image, from: CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace),
                  drawn.width == 640, drawn.height == 480,
                  let stored = drawn.dataProvider?.data, let start = CFDataGetBytePtr(stored) else { return }
            data = Array(UnsafeBufferPointer(start: start, count: CFDataGetLength(stored)))
            rowBytes = drawn.bytesPerRow
        }
        /// Where the pixel at (x, y) is — the chart's coordinates, origin at the bottom.
        func index(_ x: Int, _ y: Int) -> Int { (479 - y) * rowBytes + x * 4 }
        func luma(_ x: Int, _ y: Int) -> Double {
            let p = index(x, y)
            return (0.299 * Double(data[p]) + 0.587 * Double(data[p + 1]) + 0.114 * Double(data[p + 2])) / 255
        }
        /// The mean r g b of a box.
        func mean(_ box: CGRect) -> (r: Double, g: Double, b: Double) {
            var r = 0, g = 0, b = 0, n = 0
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    let p = index(x, y)
                    r += Int(data[p]); g += Int(data[p + 1]); b += Int(data[p + 2]); n += 1
                }
            }
            guard n > 0 else { return (0, 0, 0) }
            return (Double(r) / Double(n) / 255, Double(g) / Double(n) / 255, Double(b) / Double(n) / 255)
        }
    }
    private static func luma(_ c: (r: Double, g: Double, b: Double)) -> Double { 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }

    static func read(look: CIImage, whole: CIImage, context: CIContext) -> Reading {
        var reading = Reading()
        let pixels = Pixels(look, context: context)
        guard !pixels.isEmpty else { return reading }
        for i in 0..<8 { reading.tone.append(luma(pixels.mean(CGRect(x: i * 80 + 20, y: 390, width: 40, height: 60)))) }
        for i in 0..<8 {
            let c = pixels.mean(CGRect(x: i * 80 + 20, y: 270, width: 40, height: 60))
            reading.colours += [c.r, c.g, c.b]
        }
        let inner = CGRect(x: 250, y: 180, width: 56, height: 48)
        let innerLuma = luma(pixels.mean(inner))
        reading.corner = innerLuma > 0 ? luma(pixels.mean(CGRect(x: 8, y: 8, width: 48, height: 36))) / innerLuma : 0
        // The grain: how far the field's pixels lie from their mean.
        var sum = 0.0, squares = 0.0, n = 0.0
        for y in Int(inner.minY)..<Int(inner.maxY) {
            for x in Int(inner.minX)..<Int(inner.maxX) {
                let v = pixels.luma(x, y)
                sum += v; squares += v * v; n += 1
            }
        }
        reading.noise = n > 0 ? (max(0, squares / n - (sum / n) * (sum / n))).squareRoot() : 0
        // The bloom: a ring just outside the disc against the far dark.
        var ring = 0.0, ringCount = 0.0
        let cx = Int(disc.centre.x), cy = Int(disc.centre.y)
        for y in (cy - 58)...(cy + 58) {
            for x in (cx - 58)...(cx + 58) {
                let d = hypot(Double(x - cx), Double(y - cy))
                guard d >= Double(disc.radius) + 6, d <= Double(disc.radius) + 28 else { continue }
                ring += pixels.luma(x, y)
                ringCount += 1
            }
        }
        reading.glow = (ringCount > 0 ? ring / ringCount : 0) - luma(pixels.mean(CGRect(x: 336, y: 184, width: 44, height: 44)))
        let all = Pixels(whole, context: context)
        if !all.isEmpty {
            let m = all.mean(CameraLook.photoRect)
            reading.whole = [m.r, m.g, m.b]
        }
        return reading
    }

    /// The picture a body shows of `chart` (as the camera makes a frame:
    /// the module, then the body), without and with what is printed on it.
    static func pictures(of chart: CIImage, body: CameraBody, seed: Int, date: Date) -> (look: CIImage, whole: CIImage) {
        if body == .native {
            let picture = CameraLook.module3DS(chart, grain: 0.075, seed: seed, mean: 0.45)
            return (picture, picture)
        }
        let recipe = body.recipe
        let look = CameraBodyLook.look(CameraLook.given(chart, body: body, grain: 0.075, seed: seed), recipe: recipe, seed: seed, still: false)
        return (look, CameraBodyLook.printed(look, recipe: recipe, seed: seed, date: date))
    }

    /// A line of the file: `kind=name`, then the numbers (`body` lines
    /// have the time of a frame after the name).
    static func line(_ kind: String, _ name: String, _ reading: Reading, milliseconds: Double? = nil, base: Int? = nil) -> String {
        func list(_ values: [Double]) -> String { values.map { String(format: "%.3f", $0) }.joined(separator: ",") }
        var out = "\(kind)=\(name)"
        if let milliseconds { out += " ms=" + String(format: "%.2f", milliseconds) }
        // Which picture the body was given: 0 the module's, 1 the camera's own.
        if let base { out += " base=\(base)" }
        out += " tone=" + list(reading.tone) + " colours=" + list(reading.colours)
        out += " corner=" + String(format: "%.3f", reading.corner) + " noise=" + String(format: "%.4f", reading.noise)
        out += " glow=" + String(format: "%.3f", reading.glow) + " whole=" + list(reading.whole)
        return out
    }

    static func run() {
        guard let drawn = chart() else { return }
        let card = CIImage(cgImage: drawn)
        let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CameraLook.colorSpace, .outputColorSpace: CameraLook.colorSpace])
        let date = Date(timeIntervalSince1970: 1_086_091_200)
        let began = ProcessInfo.processInfo.systemUptime
        var lines = ["camera bench \(revision)"]
        // The picture the bodies are given (the module's), by itself.
        let given = CameraLook.module(card, grain: 0.075, seed: 7)
        lines.append(line("plain", "module", read(look: given, whole: given, context: context)))
        // And the camera's own, which the bodies with a grade are given.
        let own = CameraLook.given(card, plain: true, grain: 0.075, seed: 7)
        lines.append(line("plain", "camera", read(look: own, whole: own, context: context)))
        for body in CameraBody.allCases {
            let fixed = pictures(of: card, body: body, seed: 7, date: date)
            let reading = read(look: fixed.look, whole: fixed.whole, context: context)
            // The time of a frame: the whole picture drawn, a new grain
            // each time, after one that does not count.
            let frames = 20
            var total = 0.0
            for i in 0...frames {
                let picture = pictures(of: card, body: body, seed: 100 + i, date: date).whole
                let start = ProcessInfo.processInfo.systemUptime
                _ = context.createCGImage(picture, from: CameraLook.photoRect, format: .RGBA8, colorSpace: CameraLook.colorSpace)
                if i > 0 { total += ProcessInfo.processInfo.systemUptime - start }
            }
            let milliseconds = total / Double(frames) * 1000
            lines.append(line("body", body.rawValue, reading, milliseconds: milliseconds, base: body.isPlain ? 1 : 0))
            // 浓淡: the body at half and at one and a half (nothing printed).
            if body != .native {
                for (kind, strength) in [("half", 0.5), ("strong", 1.5)] {
                    let picture = CameraBodyLook.look(body.isPlain ? own : given, recipe: body.recipe, strength: strength, seed: 7, still: false)
                    lines.append(line(kind, body.rawValue, read(look: picture, whole: picture, context: context)))
                }
            }
            let said = String(format: "camera bench %@: %.2f ms a frame", body.rawValue, milliseconds)
            NSLog("[camera] %@", said)
            #if os(iOS)
            DispatchQueue.main.async { OrientationTrace.shared.event(said) }
            #endif
        }
        // The bodies' pictures of the drawn street, kept beside the file (to
        // be looked at, and to lay one build's beside another's): a kept
        // still, and a frame as the viewfinder shows it.
        let folder = fileURL.deletingLastPathComponent().appendingPathComponent("bench-pictures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let street = CameraTestScene.frame(side: .outer, time: 0) {
            let scene = CameraLook.module(CIImage(cgImage: street), grain: 0.075, seed: 7)
            let ownScene = CameraLook.given(CIImage(cgImage: street), plain: true, grain: 0.075, seed: 7)
            for body in CameraBody.allCases {
                for (kind, still) in [("still", true), ("moving", false)] {
                    let picture = body == .native ? scene : CameraBodyLook.develop(body.isPlain ? ownScene : scene, body: body, strength: 1, seed: 7, date: date, still: still)
                    if let data = context.jpegRepresentation(of: picture.cropped(to: CameraLook.photoRect), colorSpace: CameraLook.colorSpace, options: [:]) {
                        try? data.write(to: folder.appendingPathComponent("\(body.rawValue)-\(kind).jpg"), options: .atomic)
                    }
                }
            }
        }
        lines.append(String(format: "done %d bodies in %.1f s", CameraBody.allCases.count, ProcessInfo.processInfo.systemUptime - began))
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: url, options: .atomic)
        NSLog("[camera] bench: %d lines written", lines.count)
    }
}
#endif

/// The kind of camera a body is: what its small drawing on the menu's
/// card shows.
enum CameraShell: String, Sendable {
    case console, pocket, disposable, instant, camcorder, keyPhone, compact, toy
    /// 小票's: no camera at all, a small shop's till that prints a slip.
    case register
    /// The kind's name, as a 机型 card says it under a name that does not.
    var machineTitle: String {
        switch self {
        case .console: return String(localized: "掌机")
        case .pocket: return String(localized: "数码卡片机")
        case .disposable: return String(localized: "一次性相机")
        case .instant: return String(localized: "拍立得")
        case .camcorder: return String(localized: "摄像机")
        case .keyPhone: return String(localized: "翻盖手机")
        case .compact: return String(localized: "胶片机")
        case .toy: return String(localized: "玩具相机")
        case .register: return String(localized: "收银机")
        }
    }
}

extension CameraBody {
    var shell: CameraShell {
        switch self {
        case .native:
            return .console
        case .oldCCD, .coolCCD, .pixelY2K, .flashSnap, .nostalgicCompact, .pinkWinter, .coolDaily, .warmFlash, .earlySummer, .overcastRich,
             .computerClass, .birthdayNight, .afterSchool, .dreamcore00, .sunsetOrange:
            return .pocket
        case .snackStall, .disposable, .brightDisposable, .summerStreet, .freshWarm:
            return .disposable
        case .instantPaper, .cherryPink, .photoBooth:
            return .instant
        case .tapeDV, .vcdStill:
            return .camcorder
        case .keyPhone, .earlyFilter:
            return .keyPhone
        case .goldenFilm, .slideFilm, .silverMono, .fadedPrint, .cinemaReel, .crossProcess, .paleYellow, .winterSun, .warmDaylight, .duskFilm,
             .yellowGreenHaze, .quietTeal:
            return .compact
        case .toyCamera:
            return .toy
        case .receipt:
            return .register
        }
    }
}

/// A small drawing of the kind of camera a body is, in the body's own two
/// colours: its front as a camera of that kind has it — the lens's rings,
/// the flash's window, the finder's, the shutter's button — drawn here,
/// with no maker's shape or mark.
struct CameraShellIcon: View {
    var shell: CameraShell
    var light: Color
    var dark: Color
    var body: some View {
        Canvas { context, size in
            let g = context
            let w = Double(size.width), h = Double(size.height)
            let ink = Color(white: 0.1)
            let flash = Color(red: 0.98, green: 0.96, blue: 0.86), finder = Color(red: 0.16, green: 0.2, blue: 0.26)
            let silver = Color(white: 0.88), steel = Color(white: 0.56), black = Color(white: 0.17), coal = Color(white: 0.07)
            func box(_ x: Double, _ y: Double, _ bw: Double, _ bh: Double) -> CGRect { CGRect(x: x * w, y: y * h, width: bw * w, height: bh * h) }
            func slab(_ r: CGRect, _ corner: Double, _ top: Color, _ bottom: Color) {
                let p = Path(roundedRect: r, cornerRadius: corner * h)
                g.fill(p, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
                g.stroke(p, with: .color(ink.opacity(0.55)), lineWidth: max(0.5, h * 0.035))
            }
            func patch(_ r: CGRect, _ corner: Double, _ colour: Color) {
                g.fill(Path(roundedRect: r, cornerRadius: corner * h), with: .color(colour))
            }
            func lens(_ cx: Double, _ cy: Double, _ radius: Double, _ ring: Color) {
                let c = CGPoint(x: cx * w, y: cy * h), r = radius * h
                func disc(_ k: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: r * k * 2, height: r * k * 2)) }
                g.fill(disc(1), with: .linearGradient(Gradient(colors: [ring, ink]), startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
                g.stroke(disc(1), with: .color(ink.opacity(0.6)), lineWidth: max(0.4, h * 0.025))
                g.fill(disc(0.72), with: .color(ink))
                g.fill(disc(0.48), with: .radialGradient(Gradient(colors: [Color(red: 0.34, green: 0.42, blue: 0.6), Color(red: 0.05, green: 0.06, blue: 0.1)]),
                                                          center: c, startRadius: 0, endRadius: r * 0.5))
                g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.34, y: c.y - r * 0.36, width: r * 0.22, height: r * 0.22)), with: .color(.white.opacity(0.85)))
            }
            func window(_ r: CGRect, _ fill: Color) {
                let p = Path(roundedRect: r, cornerRadius: h * 0.02)
                g.fill(p, with: .color(fill))
                g.stroke(p, with: .color(ink.opacity(0.6)), lineWidth: max(0.4, h * 0.025))
            }
            switch shell {
            case .console:
                // The shut handheld from outside: its lid and the two eyes on it.
                slab(box(0.12, 0.2, 0.76, 0.6), 0.12, light, dark)
                patch(box(0.14, 0.72, 0.72, 0.06), 0.02, ink.opacity(0.35))
                lens(0.4, 0.44, 0.11, silver)
                lens(0.6, 0.44, 0.11, silver)
            case .pocket:
                slab(box(0.16, 0.08, 0.18, 0.14), 0.04, silver, steel)
                slab(box(0.04, 0.18, 0.92, 0.72), 0.14, light, dark)
                patch(box(0.05, 0.2, 0.17, 0.68), 0.1, ink.opacity(0.22))
                lens(0.62, 0.56, 0.27, silver)
                window(box(0.27, 0.28, 0.19, 0.14), flash)
                window(box(0.27, 0.5, 0.09, 0.1), finder)
            case .disposable:
                slab(box(0.12, 0.07, 0.16, 0.12), 0.04, dark, dark)
                slab(box(0.05, 0.16, 0.9, 0.74), 0.08, black, coal)
                patch(box(0.07, 0.34, 0.54, 0.52), 0.03, light)
                patch(box(0.07, 0.34, 0.54, 0.1), 0.02, dark)
                lens(0.36, 0.66, 0.19, black)
                window(box(0.66, 0.24, 0.24, 0.2), flash)
                window(box(0.42, 0.2, 0.14, 0.11), finder)
            case .instant:
                slab(box(0.12, 0.05, 0.76, 0.9), 0.16, light, light)
                patch(box(0.14, 0.66, 0.72, 0.27), 0.12, dark.opacity(0.3))
                lens(0.5, 0.4, 0.29, dark)
                window(box(0.18, 0.12, 0.15, 0.12), flash)
                window(box(0.69, 0.12, 0.12, 0.11), finder)
                patch(box(0.24, 0.79, 0.52, 0.055), 0.01, ink)
            case .camcorder:
                // From the side: the lens's barrel, the body, the eyepiece, the strap.
                slab(box(0.78, 0.13, 0.16, 0.2), 0.04, black, coal)
                slab(box(0.3, 0.26, 0.64, 0.52), 0.1, light, dark)
                slab(box(0.05, 0.34, 0.3, 0.36), 0.06, steel, black)
                g.fill(Path(ellipseIn: box(0.03, 0.37, 0.1, 0.3)), with: .color(Color(red: 0.12, green: 0.16, blue: 0.26)))
                slab(box(0.44, 0.4, 0.34, 0.24), 0.03, black, coal)
                patch(box(0.36, 0.84, 0.54, 0.05), 0.02, ink.opacity(0.6))
            case .keyPhone:
                slab(box(0.3, 0.03, 0.4, 0.94), 0.1, dark, coal)
                window(box(0.36, 0.11, 0.28, 0.36), light)
                slab(box(0.43, 0.52, 0.14, 0.11), 0.03, silver, steel)
                for row in 0..<3 {
                    for column in 0..<3 {
                        patch(box(0.37 + Double(column) * 0.095, 0.67 + Double(row) * 0.08, 0.07, 0.05), 0.015, silver.opacity(0.85))
                    }
                }
            case .compact:
                slab(box(0.14, 0.09, 0.18, 0.13), 0.04, silver, steel)
                slab(box(0.04, 0.2, 0.92, 0.7), 0.14, black, coal)
                g.fill(Path(roundedRect: box(0.08, 0.25, 0.84, 0.08), cornerRadius: h * 0.03),
                       with: .linearGradient(Gradient(colors: [light, dark]), startPoint: CGPoint(x: 0.08 * w, y: 0), endPoint: CGPoint(x: 0.92 * w, y: 0)))
                patch(box(0.06, 0.38, 0.13, 0.48), 0.08, Color(white: 0.26))
                lens(0.56, 0.63, 0.24, silver)
                window(box(0.74, 0.38, 0.15, 0.11), flash)
                window(box(0.26, 0.38, 0.11, 0.1), finder)
            case .toy:
                slab(box(0.4, 0.07, 0.2, 0.2), 0.04, dark, dark)
                slab(box(0.08, 0.22, 0.84, 0.68), 0.2, light, dark)
                lens(0.5, 0.57, 0.27, .white)
                g.fill(Path(ellipseIn: CGRect(x: 0.17 * w, y: 0.32 * h, width: 0.12 * h, height: 0.12 * h)), with: .color(flash))
            case .register:
                // A till from the front: a slip out of its printer, the
                // display, two rows of keys and the red total key, the
                // drawer under it all.
                patch(box(0.56, 0.02, 0.18, 0.24), 0.01, flash)
                patch(box(0.59, 0.07, 0.12, 0.025), 0, ink.opacity(0.45))
                patch(box(0.59, 0.12, 0.09, 0.025), 0, ink.opacity(0.45))
                slab(box(0.08, 0.2, 0.84, 0.54), 0.08, light, dark)
                patch(box(0.54, 0.22, 0.22, 0.035), 0.01, ink)
                window(box(0.14, 0.27, 0.34, 0.17), finder)
                for row in 0..<2 {
                    for column in 0..<4 {
                        patch(box(0.14 + Double(column) * 0.095, 0.5 + Double(row) * 0.1, 0.07, 0.07), 0.015, silver.opacity(0.9))
                    }
                }
                patch(box(0.6, 0.48, 0.15, 0.18), 0.02, Color(red: 0.83, green: 0.23, blue: 0.18))
                slab(box(0.04, 0.72, 0.92, 0.22), 0.04, steel, black)
                patch(box(0.4, 0.8, 0.2, 0.05), 0.01, silver)
            }
        }
    }
}

/// The body menu's samples: one picture from the camera as every body makes
/// it, small (the upper screen's part of it at half its size), each handed
/// back as it is made.
enum CameraBodySamples {
    private static let queue = DispatchQueue(label: "foldarc.camera.samples", qos: .userInitiated)
    private static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CameraLook.colorSpace, .outputColorSpace: CameraLook.colorSpace])

    static func make(from plain: CGImage, each: @escaping @Sendable (CameraBody, CGImage) -> Void) {
        queue.async {
            let picture = CIImage(cgImage: plain)
            let date = Date()
            let size = CGSize(width: CameraLook.screenSize.width / 2, height: CameraLook.screenSize.height / 2)
            for body in CameraBody.allCases {
                let made: CIImage
                if body == .native {
                    made = CameraLook.module3DS(picture, grain: 0.075, seed: 7, mean: 0.45)
                } else {
                    made = CameraBodyLook.develop(CameraLook.given(picture, body: body, grain: 0.075, seed: 7), body: body, strength: 1, seed: 7, date: date, still: false)
                }
                let small = CameraLook.scaled(CameraBodyLook.screen(made, body: body), by: 0.5)
                if let image = context.createCGImage(small, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CameraLook.colorSpace) {
                    each(body, image)
                }
            }
        }
    }
}
