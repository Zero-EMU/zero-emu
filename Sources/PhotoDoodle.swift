import SwiftUI
import CoreGraphics

// 相册里的编辑: a picture in the album drawn on — four tools
// along the top of the touch screen — a pencil, stamps, an eraser, a puffy
// pen — the picture under the finger, 缩小 / 放大 / 移动 along the foot, 完成
// keeping the result as a new picture beside the old one (the SD card and
// the iPhone's Photos), 不保存 leaving it as it was. The upper screen shows
// the whole picture as it becomes. Nothing in the camera itself. Every
// stamp is drawn here (FoldArc's own shapes); no
// symbol set's pictures in what is saved.

// MARK: - Tools, inks, sizes

/// The four tools, along the top of the touch screen.
enum DoodleTool: String, CaseIterable, Identifiable, Sendable {
    case pencil, stamp, eraser, puffy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pencil: return String(localized: "铅笔")
        case .stamp: return String(localized: "贴画")
        case .eraser: return String(localized: "橡皮")
        case .puffy: return String(localized: "泡泡笔")
        }
    }
    var symbol: String {
        switch self {
        case .pencil: return "pencil.tip"
        case .stamp: return "heart.fill"
        case .eraser: return "eraser.fill"
        case .puffy: return "scribble.variable"
        }
    }
    /// A line's width, or a stamp's size, in the picture's units (640 across).
    func width(_ size: DoodleSize) -> Double {
        switch (self, size) {
        case (.pencil, .small): return 3
        case (.pencil, .medium): return 6
        case (.pencil, .large): return 12
        case (.puffy, .small): return 10
        case (.puffy, .medium): return 16
        case (.puffy, .large): return 26
        case (.eraser, .small): return 10
        case (.eraser, .medium): return 24
        case (.eraser, .large): return 48
        case (.stamp, .small): return 46
        case (.stamp, .medium): return 76
        case (.stamp, .large): return 120
        }
    }
    func sizeTitle(_ size: DoodleSize) -> String {
        switch self {
        case .stamp: return [String(localized: "小"), String(localized: "中"), String(localized: "大")][size.rawValue]
        default: return [String(localized: "细"), String(localized: "中"), String(localized: "粗")][size.rawValue]
        }
    }
}

enum DoodleSize: Int, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: Int { rawValue }
}

/// The pencil's inks.
enum DoodleInk: String, CaseIterable, Identifiable, Sendable {
    case black, white, red, pink, orange, yellow, green, mint, sky, blue, purple, brown
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .black: return Color(red: 0.10, green: 0.10, blue: 0.12)
        case .white: return .white
        case .red: return Color(red: 0.92, green: 0.16, blue: 0.22)
        case .pink: return Color(red: 1.00, green: 0.45, blue: 0.68)
        case .orange: return Color(red: 1.00, green: 0.56, blue: 0.12)
        case .yellow: return Color(red: 1.00, green: 0.86, blue: 0.16)
        case .green: return Color(red: 0.20, green: 0.70, blue: 0.30)
        case .mint: return Color(red: 0.42, green: 0.88, blue: 0.76)
        case .sky: return Color(red: 0.36, green: 0.74, blue: 1.00)
        case .blue: return Color(red: 0.16, green: 0.34, blue: 0.88)
        case .purple: return Color(red: 0.58, green: 0.32, blue: 0.88)
        case .brown: return Color(red: 0.52, green: 0.33, blue: 0.20)
        }
    }
    var title: String {
        switch self {
        case .black: return String(localized: "黑")
        case .white: return String(localized: "白")
        case .red: return String(localized: "红")
        case .pink: return String(localized: "粉")
        case .orange: return String(localized: "橙")
        case .yellow: return String(localized: "黄")
        case .green: return String(localized: "绿")
        case .mint: return String(localized: "薄荷")
        case .sky: return String(localized: "天蓝")
        case .blue: return String(localized: "蓝")
        case .purple: return String(localized: "紫")
        case .brown: return String(localized: "棕")
        }
    }
}

/// The puffy pen's colours: 彩虹 changes along the line.
enum DoodlePuff: String, CaseIterable, Identifiable, Sendable {
    case rainbow, pink, sky, lemon, mint, lilac, white
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rainbow: return String(localized: "彩虹")
        case .pink: return String(localized: "粉")
        case .sky: return String(localized: "蓝")
        case .lemon: return String(localized: "黄")
        case .mint: return String(localized: "绿")
        case .lilac: return String(localized: "紫")
        case .white: return String(localized: "白")
        }
    }
    /// The colour `distance` units along the line.
    func color(at distance: Double) -> Color {
        switch self {
        case .rainbow:
            let hue = (distance / 140).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue, saturation: 0.52, brightness: 1)
        case .pink: return Color(red: 1.00, green: 0.62, blue: 0.80)
        case .sky: return Color(red: 0.55, green: 0.80, blue: 1.00)
        case .lemon: return Color(red: 1.00, green: 0.92, blue: 0.45)
        case .mint: return Color(red: 0.55, green: 0.92, blue: 0.70)
        case .lilac: return Color(red: 0.78, green: 0.64, blue: 1.00)
        case .white: return Color(white: 0.97)
        }
    }
}

// MARK: - What is drawn

/// One thing done to the picture, in its units (640 across, y down): a
/// line (its points), a stamp (one point, its centre), or 全部擦掉.
struct DoodleMark: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case pencil(DoodleInk)
        case puffy(DoodlePuff)
        case eraser
        case stamp(DoodleStamp)
        case clear
    }
    var kind: Kind
    var points: [CGPoint]
    var size: Double

    /// Puts something on the picture (not the eraser, not 全部擦掉).
    var inks: Bool {
        switch kind {
        case .pencil, .puffy, .stamp: return true
        case .eraser, .clear: return false
        }
    }
}

// MARK: - The editor's state

/// A picture of the album being doodled on. The camera's
/// model holds it while the album's touch screen is the editor; 完成 and 不保存
/// are the camera's (CameraAppModel.finishDoodle / endDoodle).
@MainActor final class PhotoDoodle: ObservableObject {
    let photo: CameraPhoto
    let image: CGImage
    /// The picture in the marks' units: 640 across.
    let units: CGSize
    @Published private(set) var marks: [DoodleMark]
    /// The line or stamp under the finger now.
    @Published private(set) var live: DoodleMark?
    @Published var tool: DoodleTool { didSet { store() } }
    @Published var ink: DoodleInk { didSet { store() } }
    @Published var puff: DoodlePuff { didSet { store() } }
    @Published var stamp: DoodleStamp { didSet { store() } }
    @Published private(set) var sizes: [DoodleTool: DoodleSize]
    /// 放大: 1×, 2× or 3×; the middle of what the touch screen shows.
    @Published private(set) var zoom = 1
    @Published private(set) var center: CGPoint
    /// 移动: a finger on the picture moves it (when it is larger than the screen).
    @Published private(set) var moving = false
    /// 不保存？ asked (something was drawn).
    @Published var askingDiscard = false
    /// 完成 pressed: being kept.
    @Published var saving = false

    static let unitWidth = 640.0
    static let maxZoom = 3
    private static let key = "FoldArc.camera.doodle."

    init(photo: CameraPhoto, image: CGImage, marks: [DoodleMark] = []) {
        self.photo = photo
        self.image = image
        let w = Double(max(1, image.width)), h = Double(max(1, image.height))
        let units = CGSize(width: Self.unitWidth, height: Self.unitWidth * h / w)
        self.units = units
        self.marks = marks
        center = CGPoint(x: units.width / 2, y: units.height / 2)
        let d = UserDefaults.standard
        tool = DoodleTool(rawValue: d.string(forKey: Self.key + "tool") ?? "") ?? .pencil
        ink = DoodleInk(rawValue: d.string(forKey: Self.key + "ink") ?? "") ?? .pink
        puff = DoodlePuff(rawValue: d.string(forKey: Self.key + "puff") ?? "") ?? .rainbow
        stamp = DoodleStamp(rawValue: d.string(forKey: Self.key + "stamp") ?? "") ?? .redHeart
        var sizes: [DoodleTool: DoodleSize] = [:]
        for tool in DoodleTool.allCases {
            sizes[tool] = DoodleSize(rawValue: d.object(forKey: Self.key + "size." + tool.rawValue) as? Int ?? 1) ?? .medium
        }
        self.sizes = sizes
    }

    private func store() {
        let d = UserDefaults.standard
        d.set(tool.rawValue, forKey: Self.key + "tool")
        d.set(ink.rawValue, forKey: Self.key + "ink")
        d.set(puff.rawValue, forKey: Self.key + "puff")
        d.set(stamp.rawValue, forKey: Self.key + "stamp")
        for (tool, size) in sizes { d.set(size.rawValue, forKey: Self.key + "size." + tool.rawValue) }
    }

    var size: DoodleSize { sizes[tool] ?? .medium }
    func setSize(_ next: DoodleSize) {
        guard next != size else { return }
        sizes[tool] = next
        store()
        ConsoleSounds.shared.play(.move)
    }
    func choose(_ next: DoodleTool) {
        guard next != tool else { return }
        tool = next
        ConsoleSounds.shared.play(.move)
    }
    func nextTool() {
        let all = DoodleTool.allCases
        choose(all[((all.firstIndex(of: tool) ?? 0) + 1) % all.count])
    }

    /// Something was drawn (不保存 asks first).
    var touched: Bool { !marks.isEmpty }
    /// Something shows on the picture now (after the last 全部擦掉).
    var hasInk: Bool {
        let since = marks.lastIndex { $0.kind == .clear }.map { $0 + 1 } ?? 0
        return marks[since...].contains { $0.inks }
    }

    // The finger on the picture (points in units).

    func begin(_ point: CGPoint) {
        guard !saving, !askingDiscard else { return }
        let width = tool.width(size)
        switch tool {
        case .pencil: live = DoodleMark(kind: .pencil(ink), points: [point], size: width)
        case .puffy: live = DoodleMark(kind: .puffy(puff), points: [point], size: width)
        case .eraser: live = DoodleMark(kind: .eraser, points: [point], size: width)
        case .stamp: live = DoodleMark(kind: .stamp(stamp), points: [point], size: width * stamp.scale)
        }
    }
    func move(_ point: CGPoint) {
        guard var mark = live else { return }
        if case .stamp = mark.kind {
            mark.points = [point]
        } else {
            guard let last = mark.points.last, hypot(point.x - last.x, point.y - last.y) >= 1.2 / Double(zoom) else { return }
            mark.points.append(point)
        }
        live = mark
    }
    func end() {
        guard let mark = live else { return }
        live = nil
        marks.append(mark)
        if case .stamp = mark.kind { ConsoleSounds.shared.play(.click) }
    }
    func undo() {
        guard live == nil, !marks.isEmpty else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        marks.removeLast()
        ConsoleSounds.shared.play(.back)
    }
    /// 全部擦掉 (撤销 brings it all back).
    func clearAll() {
        guard hasInk else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        marks.append(DoodleMark(kind: .clear, points: [], size: 0))
        ConsoleSounds.shared.play(.back)
    }

    // 缩小 / 放大 / 移动.

    /// The part of the picture the touch screen shows (in units).
    var region: CGRect {
        let w = units.width / Double(zoom), h = units.height / Double(zoom)
        let x = min(max(0, center.x - w / 2), units.width - w)
        let y = min(max(0, center.y - h / 2), units.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    func zoomIn() {
        guard zoom < Self.maxZoom else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        zoom += 1
        setCenter(center)
        ConsoleSounds.shared.play(.move)
    }
    func zoomOut() {
        guard zoom > 1 else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        zoom -= 1
        if zoom == 1 { moving = false }
        setCenter(center)
        ConsoleSounds.shared.play(.move)
    }
    func toggleMoving() {
        guard zoom > 1 else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        moving.toggle()
        ConsoleSounds.shared.play(moving ? .select : .back)
    }
    /// The middle of what is shown, kept so that it stays on the picture.
    func setCenter(_ point: CGPoint) {
        let w = units.width / Double(zoom), h = units.height / Double(zoom)
        center = CGPoint(x: min(max(w / 2, point.x), units.width - w / 2),
                         y: min(max(h / 2, point.y), units.height - h / 2))
    }
    /// Source renders: shown larger, without a sound.
    func preview(zoom: Int, at point: CGPoint) {
        self.zoom = min(max(1, zoom), Self.maxZoom)
        setCenter(point)
    }
    /// The D-pad or the Circle Pad while zoomed: a quarter of a screen.
    func nudge(_ dx: Double, _ dy: Double) {
        guard zoom > 1 else { return }
        let r = region
        setCenter(CGPoint(x: center.x + dx * r.width / 4, y: center.y + dy * r.height / 4))
    }

    // 完成.

    /// The picture with its doodle, at the picture's own size.
    func render() -> CGImage? {
        let width = Double(image.width), height = Double(image.height)
        let picture = DoodlePicture(image: image, units: units, marks: marks, live: nil, region: CGRect(origin: .zero, size: units))
            .frame(width: width, height: height)
        let renderer = ImageRenderer(content: picture)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// The DEBUG script's `doodle` step: the sample below, drawn on.
    func addSample() {
        marks += Self.sample(units: units)
        NSLog("[camera] edit: a sample drawn (%d marks)", marks.count)
    }

    /// A doodle to show the tools with (source renders; the DEBUG script's
    /// `doodle` step): a picture taken with the inner camera's test scene in
    /// mind — cat ears and blush on its face, hearts by the window, a
    /// rainbow line along the foot with a gap rubbed out of it.
    static func sample(units: CGSize) -> [DoodleMark] {
        let k = units.width / unitWidth
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        var marks: [DoodleMark] = []
        // A hand-drawn heart in red pencil, by the lamp.
        let heart = stride(from: 0.0, through: 2 * Double.pi, by: Double.pi / 40).map { t -> CGPoint in
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return p(105 + x * 3.2, 300 - y * 3.2)
        }
        marks.append(DoodleMark(kind: .pencil(.red), points: heart, size: 6 * k))
        // A wavy line in black, under it.
        marks.append(DoodleMark(kind: .pencil(.black), points: stride(from: 40.0, through: 180, by: 4).map { p($0, 372 + sin($0 / 14) * 7) }, size: 3 * k))
        // The rainbow along the foot, and a gap rubbed out of it.
        marks.append(DoodleMark(kind: .puffy(.rainbow), points: stride(from: 30.0, through: 610, by: 5).map { p($0, 432 + sin($0 / 34) * 16) }, size: 16 * k))
        marks.append(DoodleMark(kind: .eraser, points: stride(from: 395.0, through: 470, by: 4).map { p(432, $0) }, size: 24 * k))
        // On the face: cat ears and blush.
        marks.append(DoodleMark(kind: .stamp(.catEars), points: [p(300, 66)], size: 150 * k))
        marks.append(DoodleMark(kind: .stamp(.blush), points: [p(300, 262)], size: 200 * k))
        // By the window, and round the picture.
        marks.append(DoodleMark(kind: .stamp(.angelHeart), points: [p(505, 150)], size: 110 * k))
        marks.append(DoodleMark(kind: .stamp(.redHeart), points: [p(580, 300)], size: 60 * k))
        marks.append(DoodleMark(kind: .stamp(.pinkHeart), points: [p(540, 345)], size: 42 * k))
        marks.append(DoodleMark(kind: .stamp(.sparkle), points: [p(70, 80)], size: 80 * k))
        marks.append(DoodleMark(kind: .stamp(.star), points: [p(150, 150)], size: 54 * k))
        return marks
    }
}

// MARK: - Drawing

/// The picture, or `region` of it, with the doodle over it, filling the view
/// (which has the picture's proportions).
struct DoodlePicture: View {
    let image: CGImage
    let units: CGSize
    var marks: [DoodleMark]
    var live: DoodleMark?
    var region: CGRect
    var body: some View {
        Canvas { context, size in
            let k = size.width / max(1, region.width)
            var c = context
            c.scaleBy(x: k, y: k)
            c.translateBy(x: -region.minX, y: -region.minY)
            c.draw(Image(decorative: image, scale: 1).interpolation(.none), in: CGRect(origin: .zero, size: units))
            DoodleArt.draw(marks, live: live, in: c)
        }
    }
}

enum DoodleArt {
    /// The doodle, in a layer of its own over the picture (the eraser takes
    /// away what was drawn, never the picture).
    static func draw(_ marks: [DoodleMark], live: DoodleMark?, in context: GraphicsContext) {
        context.drawLayer { layer in
            for mark in marks { draw(mark, in: layer) }
            if let live { draw(live, in: layer) }
        }
    }

    static func draw(_ mark: DoodleMark, in context: GraphicsContext) {
        switch mark.kind {
        case .pencil(let ink):
            line(mark.points, width: mark.size, shading: .color(ink.color), in: context)
        case .puffy(let puff):
            puffy(mark, puff, in: context)
        case .eraser:
            var rub = context
            rub.blendMode = .destinationOut
            line(mark.points, width: mark.size, shading: .color(.black), in: rub)
        case .stamp(let stamp):
            guard let at = mark.points.first else { return }
            DoodleStampArt.draw(stamp, at: at, size: mark.size, in: context)
        case .clear:
            var rub = context
            rub.blendMode = .clear
            rub.fill(Path(CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)), with: .color(.black))
        }
    }

    /// The points as a smooth line (through the middles of its steps).
    static func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 2 else {
            p.addLine(to: points.last ?? first)
            return p
        }
        for i in 1..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        p.addLine(to: points[points.count - 1])
        return p
    }

    static func round(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    /// A line (a dot, for a touch that did not move).
    static func line(_ points: [CGPoint], width: Double, shading: GraphicsContext.Shading, in context: GraphicsContext) {
        guard let first = points.first else { return }
        if points.count == 1 {
            context.fill(Path(ellipseIn: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)), with: shading)
        } else {
            context.stroke(path(points), with: shading, style: round(width))
        }
    }

    /// 泡泡笔: a fat, rounded line with a white edge, a shadow under it and a
    /// shine along its upper side, as puffy paint stands up from paper.
    static func puffy(_ mark: DoodleMark, _ puff: DoodlePuff, in context: GraphicsContext) {
        let w = mark.size
        var shadow = context
        shadow.translateBy(x: w * 0.1, y: w * 0.18)
        line(mark.points, width: w * 1.42, shading: .color(.black.opacity(0.24)), in: shadow)
        line(mark.points, width: w * 1.42, shading: .color(.white), in: context)
        if puff == .rainbow, mark.points.count > 2 {
            // The colour changes along it: runs of about 10 units each.
            var start = 0
            var travelled = 0.0, runStart = 0.0
            for i in 1..<mark.points.count {
                let a = mark.points[i - 1], b = mark.points[i]
                travelled += hypot(b.x - a.x, b.y - a.y)
                if travelled - runStart >= 10 || i == mark.points.count - 1 {
                    context.stroke(path(Array(mark.points[start...i])), with: .color(puff.color(at: runStart)), style: round(w))
                    start = i
                    runStart = travelled
                }
            }
        } else {
            line(mark.points, width: w, shading: .color(puff.color(at: 0)), in: context)
        }
        var shine = context
        shine.translateBy(x: -w * 0.13, y: -w * 0.2)
        line(mark.points, width: w * 0.28, shading: .color(.white.opacity(0.62)), in: shine)
    }
}

// MARK: - The stamps (FoldArc's own drawings)

/// Hearts of several kinds first, then the
/// small things a photo-sticker booth has. Each is drawn here.
enum DoodleStamp: String, CaseIterable, Identifiable, Sendable {
    case redHeart, pinkHeart, hollowHeart, twinHearts, angelHeart, arrowHeart, heartBubble, sparkleHeart
    case star, hollowStar, sparkle, flower, bow, crown, catEars, bunnyEars, blush, smile
    case pinkPaw, blackPaw, notes, cloud, moon, clover, drop, bolt
    /// 铁皮盒's (TinBox.swift): offered once they are in the tin.
    case lollipop, bicycle, schoolBag, leaf
    var id: String { rawValue }
    /// The thing of 铁皮盒 that brings it (nil: always offered).
    var tinThing: TinThing? {
        switch self {
        case .lollipop: return .lollipop
        case .bicycle, .schoolBag, .leaf: return .schoolDays
        default: return nil
        }
    }
    /// The stamps the picker offers: all but those 铁皮盒 has not brought yet.
    @MainActor static var offered: [DoodleStamp] {
        allCases.filter { stamp in stamp.tinThing.map { TinBoxStore.shared.has($0) } ?? true }
    }
    /// Ears and blush go across a face: larger than the rest at each size.
    var scale: Double {
        switch self {
        case .catEars, .bunnyEars, .blush: return 1.9
        case .crown: return 1.3
        default: return 1
        }
    }
    var title: String {
        switch self {
        case .redHeart: return String(localized: "红心")
        case .pinkHeart: return String(localized: "粉心")
        case .hollowHeart: return String(localized: "空心爱心")
        case .twinHearts: return String(localized: "双心")
        case .angelHeart: return String(localized: "天使心")
        case .arrowHeart: return String(localized: "一箭穿心")
        case .heartBubble: return String(localized: "爱心气泡")
        case .sparkleHeart: return String(localized: "闪亮心")
        case .star: return String(localized: "星星")
        case .hollowStar: return String(localized: "空心星")
        case .sparkle: return String(localized: "闪光")
        case .flower: return String(localized: "小花")
        case .bow: return String(localized: "蝴蝶结")
        case .crown: return String(localized: "皇冠")
        case .catEars: return String(localized: "猫耳朵")
        case .bunnyEars: return String(localized: "兔耳朵")
        case .blush: return String(localized: "腮红")
        case .smile: return String(localized: "笑脸")
        case .pinkPaw: return String(localized: "粉爪印")
        case .blackPaw: return String(localized: "黑爪印")
        case .notes: return String(localized: "音符")
        case .cloud: return String(localized: "云朵")
        case .moon: return String(localized: "月亮")
        case .clover: return String(localized: "四叶草")
        case .drop: return String(localized: "汗滴")
        case .bolt: return String(localized: "闪电")
        case .lollipop: return String(localized: "棒棒糖")
        case .bicycle: return String(localized: "自行车")
        case .schoolBag: return String(localized: "书包")
        case .leaf: return String(localized: "落叶")
        }
    }
}

/// A part of a stamp, in the stamp's own square (0…1 across, y down): a
/// shape filled, outlined, or both; `rim` parts get the sticker's white edge.
struct DoodlePiece {
    var path: Path
    var fill: GraphicsContext.Shading? = nil
    var line: Color? = nil
    var width: Double = 0
    var rim = true
}

enum DoodleStampArt {
    /// The sticker's white edge, either side of an outline (in the stamp's square).
    static let rim = 0.05

    static func draw(_ stamp: DoodleStamp, at center: CGPoint, size: Double, in context: GraphicsContext) {
        var c = context
        c.translateBy(x: center.x - size / 2, y: center.y - size / 2)
        c.scaleBy(x: size, y: size)
        if stamp == .blush { blush(in: c); return }
        let pieces = stamp.pieces
        // A soft shadow under the sticker, as one layer (overlaps not darker).
        var shade = c
        shade.opacity = 0.24
        shade.translateBy(x: 0.02, y: 0.035)
        shade.drawLayer { layer in
            for piece in pieces where piece.rim { edge(piece, colour: .black, in: layer) }
        }
        for piece in pieces {
            if piece.rim { edge(piece, colour: .white, in: c) }
            if let fill = piece.fill { c.fill(piece.path, with: fill) }
            if let line = piece.line {
                c.stroke(piece.path, with: .color(line), style: StrokeStyle(lineWidth: piece.width, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private static func edge(_ piece: DoodlePiece, colour: Color, in c: GraphicsContext) {
        c.stroke(piece.path, with: .color(colour), style: StrokeStyle(lineWidth: (piece.line == nil ? 0 : piece.width) + rim * 2, lineCap: .round, lineJoin: .round))
        if piece.fill != nil { c.fill(piece.path, with: .color(colour)) }
    }

    /// 腮红: two soft pink ovals with three short white strokes on each, no edge.
    private static func blush(in c: GraphicsContext) {
        for x in [0.24, 0.76] {
            var oval = c
            oval.translateBy(x: x, y: 0.5)
            oval.scaleBy(x: 1, y: 0.64)
            oval.fill(DoodleShapes.circle(0, 0, 0.24),
                      with: .radialGradient(Gradient(stops: [.init(color: DoodlePalette.blush.opacity(0.95), location: 0),
                                                             .init(color: DoodlePalette.blush.opacity(0.75), location: 0.55),
                                                             .init(color: DoodlePalette.blush.opacity(0), location: 1)]),
                                            center: .zero, startRadius: 0, endRadius: 0.24))
            var strokes = Path()
            for k in -1...1 {
                let dx = Double(k) * 0.075
                strokes.move(to: CGPoint(x: x + dx - 0.03, y: 0.56))
                strokes.addLine(to: CGPoint(x: x + dx + 0.03, y: 0.44))
            }
            c.stroke(strokes, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.026, lineCap: .round))
        }
    }
}

/// The stamps' colours.
enum DoodlePalette {
    static let red = Color(red: 0.94, green: 0.20, blue: 0.32)
    static let pink = Color(red: 1.00, green: 0.50, blue: 0.72)
    static let rose = Color(red: 0.96, green: 0.32, blue: 0.52)
    static let gold = Color(red: 1.00, green: 0.78, blue: 0.22)
    static let goldDeep = Color(red: 0.94, green: 0.60, blue: 0.12)
    static let yellow = Color(red: 1.00, green: 0.84, blue: 0.20)
    static let paleYellow = Color(red: 1.00, green: 0.94, blue: 0.52)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.12)
    static let petal = Color(red: 1.00, green: 0.60, blue: 0.76)
    static let bow = Color(red: 1.00, green: 0.45, blue: 0.66)
    static let bowDeep = Color(red: 0.88, green: 0.28, blue: 0.50)
    static let ruby = Color(red: 0.90, green: 0.12, blue: 0.26)
    static let sapphire = Color(red: 0.22, green: 0.46, blue: 0.95)
    static let fur = Color(red: 0.25, green: 0.21, blue: 0.23)
    static let earPink = Color(red: 1.00, green: 0.68, blue: 0.78)
    static let bunnyEdge = Color(red: 0.74, green: 0.70, blue: 0.76)
    static let blush = Color(red: 1.00, green: 0.42, blue: 0.52)
    static let sun = Color(red: 1.00, green: 0.85, blue: 0.28)
    static let faceInk = Color(red: 0.30, green: 0.19, blue: 0.13)
    static let cheek = Color(red: 1.00, green: 0.55, blue: 0.60).opacity(0.75)
    static let pawPink = Color(red: 1.00, green: 0.60, blue: 0.74)
    static let pawBlack = Color(red: 0.17, green: 0.15, blue: 0.18)
    static let violet = Color(red: 0.48, green: 0.36, blue: 0.92)
    static let cloudEdge = Color(red: 0.56, green: 0.74, blue: 0.95)
    static let moon = Color(red: 1.00, green: 0.86, blue: 0.36)
    static let clover = Color(red: 0.32, green: 0.76, blue: 0.36)
    static let cloverDeep = Color(red: 0.20, green: 0.56, blue: 0.26)
    static let water = Color(red: 0.42, green: 0.74, blue: 1.00)
    static let wingEdge = Color(red: 0.62, green: 0.72, blue: 0.88)
    static let candy = Color(red: 0.95, green: 0.38, blue: 0.60)
    static let stick = Color(red: 0.96, green: 0.92, blue: 0.84)
    static let tyre = Color(red: 0.22, green: 0.22, blue: 0.25)
    static let bikeBlue = Color(red: 0.16, green: 0.45, blue: 0.75)
    static let bag = Color(red: 0.84, green: 0.28, blue: 0.24)
    static let bagDeep = Color(red: 0.66, green: 0.18, blue: 0.18)
    static let ginkgo = Color(red: 0.94, green: 0.70, blue: 0.20)
    static let ginkgoDeep = Color(red: 0.76, green: 0.52, blue: 0.14)
}

/// Shapes in a stamp's square.
enum DoodleShapes {
    static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    /// An oval round (x, y), turned `degrees` (clockwise on the screen).
    static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ degrees: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(CGAffineTransform(translationX: x, y: y)))
    }
    /// A heart filling the box (its point at the bottom middle).
    static func heart(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        func q(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: x + w * a, y: y + h * b) }
        var p = Path()
        p.move(to: q(0.5, 1))
        p.addCurve(to: q(0, 0.36), control1: q(0.32, 0.84), control2: q(0, 0.62))
        p.addCurve(to: q(0.5, 0.2), control1: q(0, 0.04), control2: q(0.38, -0.04))
        p.addCurve(to: q(1, 0.36), control1: q(0.62, -0.04), control2: q(1, 0.04))
        p.addCurve(to: q(0.5, 1), control1: q(1, 0.62), control2: q(0.68, 0.84))
        p.closeSubpath()
        return p
    }
    /// A star with a point up.
    static func star(_ x: Double, _ y: Double, _ outer: Double, _ inner: Double, points: Int = 5) -> Path {
        var p = Path()
        for k in 0..<(points * 2) {
            let a = (-90 + Double(k) * 180 / Double(points)) * .pi / 180
            let r = k % 2 == 0 ? outer : inner
            let q = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
            if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
    /// A four-pointed twinkle, its sides curving in.
    static func sparkle(_ x: Double, _ y: Double, _ r: Double, waist: Double = 0.16) -> Path {
        let w = r * waist
        var p = Path()
        p.move(to: pt(x, y - r))
        p.addQuadCurve(to: pt(x + r, y), control: pt(x + w, y - w))
        p.addQuadCurve(to: pt(x, y + r), control: pt(x + w, y + w))
        p.addQuadCurve(to: pt(x - r, y), control: pt(x - w, y + w))
        p.addQuadCurve(to: pt(x, y - r), control: pt(x - w, y - w))
        p.closeSubpath()
        return p
    }
    static func polygon(_ points: [(Double, Double)]) -> Path {
        var p = Path()
        for (i, point) in points.enumerated() {
            if i == 0 { p.move(to: pt(point.0, point.1)) } else { p.addLine(to: pt(point.0, point.1)) }
        }
        p.closeSubpath()
        return p
    }
    /// Left and right swapped (x → 1 − x).
    static func mirrored(_ p: Path) -> Path {
        p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0))
    }
    static func union(_ paths: [Path]) -> Path {
        guard let first = paths.first else { return Path() }
        return paths.dropFirst().reduce(first) { $0.union($1) }
    }
    /// Turned `degrees` round (x, y).
    static func turned(_ p: Path, _ degrees: Double, about x: Double, _ y: Double) -> Path {
        p.applying(CGAffineTransform(translationX: -x, y: -y)
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: x, y: y)))
    }
    /// A heart with a shine on its upper left, as a candy's.
    static func candyHeart(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ colour: Color) -> [DoodlePiece] {
        [DoodlePiece(path: heart(x, y, w, h), fill: .color(colour)),
         DoodlePiece(path: ellipse(x + w * 0.26, y + h * 0.31, w * 0.11, h * 0.065, -38), fill: .color(.white.opacity(0.72)), rim: false),
         DoodlePiece(path: circle(x + w * 0.4, y + h * 0.22, w * 0.032), fill: .color(.white.opacity(0.62)), rim: false)]
    }
    static func paw(_ colour: Color) -> [DoodlePiece] {
        let pad = union([ellipse(0.5, 0.7, 0.25, 0.2), ellipse(0.5, 0.62, 0.16, 0.14)])
        let toes = [ellipse(0.19, 0.43, 0.095, 0.125, -22), ellipse(0.37, 0.25, 0.1, 0.13, -8),
                    ellipse(0.63, 0.25, 0.1, 0.13, 8), ellipse(0.81, 0.43, 0.095, 0.125, 22)]
        return [DoodlePiece(path: union([pad] + toes), fill: .color(colour))]
    }
}

extension DoodleStamp {
    /// The stamp's parts, back to front.
    var pieces: [DoodlePiece] {
        typealias P = DoodlePiece
        typealias S = DoodleShapes
        let pal = DoodlePalette.self
        switch self {
        case .redHeart:
            return S.candyHeart(0.04, 0.06, 0.92, 0.9, pal.red)
        case .pinkHeart:
            return S.candyHeart(0.04, 0.06, 0.92, 0.9, pal.pink)
        case .hollowHeart:
            return [P(path: S.heart(0.13, 0.15, 0.74, 0.72), line: pal.rose, width: 0.12)]
        case .twinHearts:
            return S.candyHeart(0.02, 0.04, 0.64, 0.62, pal.pink) + S.candyHeart(0.4, 0.38, 0.56, 0.55, pal.red)
        case .angelHeart:
            let wing = S.union([S.ellipse(0.2, 0.36, 0.18, 0.075, -22), S.ellipse(0.2, 0.47, 0.17, 0.07, -6), S.ellipse(0.24, 0.57, 0.13, 0.062, 10)])
            return [P(path: wing, fill: .color(.white), line: pal.wingEdge, width: 0.025),
                    P(path: S.mirrored(wing), fill: .color(.white), line: pal.wingEdge, width: 0.025)]
                + S.candyHeart(0.29, 0.29, 0.42, 0.42, pal.red)
        case .arrowHeart:
            let tail = CGPoint(x: 0.07, y: 0.88), tip = CGPoint(x: 0.95, y: 0.12)
            let length = hypot(tip.x - tail.x, tip.y - tail.y)
            let d = CGPoint(x: (tip.x - tail.x) / length, y: (tip.y - tail.y) / length)
            let n = CGPoint(x: -d.y, y: d.x)
            func at(_ base: CGPoint, _ along: CGFloat, _ across: CGFloat) -> CGPoint {
                let x: CGFloat = base.x + d.x * along + n.x * across
                let y: CGFloat = base.y + d.y * along + n.y * across
                return CGPoint(x: x, y: y)
            }
            var shaft = Path()
            shaft.move(to: at(tail, 0.02, 0))
            shaft.addLine(to: at(tip, -0.12, 0))
            var head = Path()
            head.move(to: tip)
            head.addLine(to: at(tip, -0.18, 0.08))
            head.addLine(to: at(tip, -0.18, -0.08))
            head.closeSubpath()
            var feathers = Path()
            for k: CGFloat in [0.04, 0.11] {
                let base = at(tail, k, 0)
                feathers.move(to: at(base, -0.07, 0.065))
                feathers.addLine(to: base)
                feathers.addLine(to: at(base, -0.07, -0.065))
            }
            return [P(path: shaft, line: pal.gold, width: 0.045),
                    P(path: head, fill: .color(pal.gold), line: pal.gold, width: 0.03),
                    P(path: feathers, line: pal.pink, width: 0.035)]
                + S.candyHeart(0.2, 0.2, 0.6, 0.58, pal.red)
        case .heartBubble:
            let bubble = S.union([Path(roundedRect: CGRect(x: 0.05, y: 0.08, width: 0.9, height: 0.62), cornerRadius: 0.2),
                                  S.polygon([(0.22, 0.6), (0.14, 0.92), (0.44, 0.66)])])
            return [P(path: bubble, fill: .color(.white), line: pal.rose, width: 0.04),
                    P(path: S.heart(0.33, 0.21, 0.34, 0.36), fill: .color(pal.red), rim: false)]
        case .sparkleHeart:
            return S.candyHeart(0.06, 0.22, 0.68, 0.68, pal.pink)
                + [P(path: S.sparkle(0.8, 0.2, 0.16), fill: .color(pal.yellow)),
                   P(path: S.sparkle(0.9, 0.6, 0.09), fill: .color(pal.yellow)),
                   P(path: S.sparkle(0.14, 0.13, 0.08), fill: .color(pal.yellow))]
        case .star:
            return [P(path: S.star(0.5, 0.54, 0.44, 0.21), fill: .color(pal.yellow), line: pal.yellow, width: 0.07),
                    P(path: S.ellipse(0.4, 0.4, 0.07, 0.04, -40), fill: .color(.white.opacity(0.7)), rim: false)]
        case .hollowStar:
            return [P(path: S.star(0.5, 0.54, 0.41, 0.2), line: pal.orange, width: 0.09)]
        case .sparkle:
            return [P(path: S.sparkle(0.42, 0.56, 0.4), fill: .color(pal.paleYellow)),
                    P(path: S.sparkle(0.82, 0.2, 0.15), fill: .color(pal.paleYellow)),
                    P(path: S.circle(0.84, 0.8, 0.045), fill: .color(pal.paleYellow))]
        case .flower:
            let petals = S.union([S.circle(0.5, 0.52, 0.2)] + (0..<5).map { k -> Path in
                let a = (-90 + Double(k) * 72) * .pi / 180
                return S.circle(0.5 + cos(a) * 0.24, 0.52 + sin(a) * 0.24, 0.2)
            })
            return [P(path: petals, fill: .color(pal.petal)),
                    P(path: S.circle(0.5, 0.52, 0.14), fill: .color(pal.yellow), rim: false),
                    P(path: S.circle(0.46, 0.48, 0.04), fill: .color(.white.opacity(0.6)), rim: false)]
        case .bow:
            var loop = Path()
            loop.move(to: S.pt(0.5, 0.46))
            loop.addCurve(to: S.pt(0.08, 0.2), control1: S.pt(0.36, 0.26), control2: S.pt(0.16, 0.08))
            loop.addCurve(to: S.pt(0.1, 0.74), control1: S.pt(0.0, 0.34), control2: S.pt(-0.02, 0.66))
            loop.addCurve(to: S.pt(0.5, 0.54), control1: S.pt(0.22, 0.82), control2: S.pt(0.38, 0.66))
            loop.closeSubpath()
            var fold = Path()
            fold.move(to: S.pt(0.42, 0.5))
            fold.addQuadCurve(to: S.pt(0.15, 0.45), control: S.pt(0.28, 0.42))
            let tail = S.polygon([(0.45, 0.52), (0.26, 0.92), (0.34, 0.88), (0.4, 0.97), (0.54, 0.56)])
            return [P(path: tail, fill: .color(pal.bowDeep)), P(path: S.mirrored(tail), fill: .color(pal.bowDeep)),
                    P(path: loop, fill: .color(pal.bow)), P(path: S.mirrored(loop), fill: .color(pal.bow)),
                    P(path: fold, line: pal.bowDeep, width: 0.025, rim: false), P(path: S.mirrored(fold), line: pal.bowDeep, width: 0.025, rim: false),
                    P(path: Path(roundedRect: CGRect(x: 0.4, y: 0.38, width: 0.2, height: 0.24), cornerRadius: 0.07), fill: .color(pal.bowDeep))]
        case .crown:
            let body = S.polygon([(0.12, 0.8), (0.07, 0.3), (0.3, 0.5), (0.5, 0.18), (0.7, 0.5), (0.93, 0.3), (0.88, 0.8)])
            let balls = [S.circle(0.07, 0.27, 0.065), S.circle(0.5, 0.15, 0.07), S.circle(0.93, 0.27, 0.065)]
            return balls.map { P(path: $0, fill: .color(pal.gold)) }
                + [P(path: body, fill: .color(pal.gold), line: pal.gold, width: 0.04),
                   P(path: Path(roundedRect: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.15), cornerRadius: 0.04), fill: .color(pal.goldDeep)),
                   P(path: S.circle(0.5, 0.775, 0.05), fill: .color(pal.ruby), rim: false),
                   P(path: S.circle(0.28, 0.775, 0.038), fill: .color(pal.sapphire), rim: false),
                   P(path: S.circle(0.72, 0.775, 0.038), fill: .color(pal.sapphire), rim: false),
                   P(path: S.ellipse(0.36, 0.5, 0.05, 0.025, -40), fill: .color(.white.opacity(0.6)), rim: false)]
        case .catEars:
            var ear = Path()
            ear.move(to: S.pt(0.03, 0.9))
            ear.addQuadCurve(to: S.pt(0.14, 0.1), control: S.pt(0.0, 0.42))
            ear.addQuadCurve(to: S.pt(0.42, 0.78), control: S.pt(0.34, 0.36))
            ear.addQuadCurve(to: S.pt(0.03, 0.9), control: S.pt(0.2, 0.92))
            ear.closeSubpath()
            var inner = Path()
            inner.move(to: S.pt(0.11, 0.8))
            inner.addQuadCurve(to: S.pt(0.16, 0.3), control: S.pt(0.08, 0.5))
            inner.addQuadCurve(to: S.pt(0.33, 0.72), control: S.pt(0.3, 0.46))
            inner.addQuadCurve(to: S.pt(0.11, 0.8), control: S.pt(0.2, 0.82))
            inner.closeSubpath()
            return [P(path: ear, fill: .color(pal.fur)), P(path: inner, fill: .color(pal.earPink), rim: false),
                    P(path: S.mirrored(ear), fill: .color(pal.fur)), P(path: S.mirrored(inner), fill: .color(pal.earPink), rim: false)]
        case .bunnyEars:
            let ear = S.ellipse(0.3, 0.48, 0.13, 0.44, -12)
            let inner = S.ellipse(0.31, 0.5, 0.065, 0.32, -12)
            return [P(path: ear, fill: .color(.white), line: pal.bunnyEdge, width: 0.025), P(path: inner, fill: .color(pal.earPink), rim: false),
                    P(path: S.mirrored(ear), fill: .color(.white), line: pal.bunnyEdge, width: 0.025), P(path: S.mirrored(inner), fill: .color(pal.earPink), rim: false)]
        case .blush:
            return []    // drawn by DoodleStampArt (soft, no edge)
        case .smile:
            var mouth = Path()
            mouth.move(to: S.pt(0.32, 0.6))
            mouth.addQuadCurve(to: S.pt(0.68, 0.6), control: S.pt(0.5, 0.8))
            return [P(path: S.circle(0.5, 0.5, 0.44), fill: .color(pal.sun)),
                    P(path: S.ellipse(0.35, 0.42, 0.05, 0.075), fill: .color(pal.faceInk), rim: false),
                    P(path: S.ellipse(0.65, 0.42, 0.05, 0.075), fill: .color(pal.faceInk), rim: false),
                    P(path: S.circle(0.365, 0.4, 0.017), fill: .color(.white), rim: false),
                    P(path: S.circle(0.665, 0.4, 0.017), fill: .color(.white), rim: false),
                    P(path: mouth, line: pal.faceInk, width: 0.05, rim: false),
                    P(path: S.ellipse(0.23, 0.6, 0.075, 0.05), fill: .color(pal.cheek), rim: false),
                    P(path: S.ellipse(0.77, 0.6, 0.075, 0.05), fill: .color(pal.cheek), rim: false)]
        case .pinkPaw:
            return S.paw(pal.pawPink)
        case .blackPaw:
            return S.paw(pal.pawBlack)
        case .notes:
            let heads = [S.ellipse(0.27, 0.78, 0.135, 0.095, -25), S.ellipse(0.71, 0.68, 0.135, 0.095, -25)]
            let stems = [Path(CGRect(x: 0.36, y: 0.22, width: 0.055, height: 0.56)), Path(CGRect(x: 0.8, y: 0.12, width: 0.055, height: 0.56))]
            let beam = S.polygon([(0.36, 0.2), (0.855, 0.1), (0.855, 0.22), (0.36, 0.32)])
            return [P(path: S.union(heads + stems + [beam]), fill: .color(pal.violet))]
        case .cloud:
            let puff = S.union([S.circle(0.3, 0.58, 0.19), S.circle(0.5, 0.45, 0.25), S.circle(0.72, 0.57, 0.18),
                                Path(roundedRect: CGRect(x: 0.12, y: 0.55, width: 0.76, height: 0.22), cornerRadius: 0.11)])
            return [P(path: puff, fill: .color(.white), line: pal.cloudEdge, width: 0.035)]
        case .moon:
            return [P(path: S.circle(0.48, 0.52, 0.42).subtracting(S.circle(0.68, 0.36, 0.36)), fill: .color(pal.moon))]
        case .clover:
            let leaf = S.heart(0.33, 0.06, 0.34, 0.4)    // its point at (0.5, 0.46)
            let leaves = S.union([45.0, 135, 225, 315].map { S.turned(leaf, $0, about: 0.5, 0.46) })
            var stem = Path()
            stem.move(to: S.pt(0.5, 0.48))
            stem.addQuadCurve(to: S.pt(0.6, 0.96), control: S.pt(0.52, 0.8))
            return [P(path: stem, line: pal.cloverDeep, width: 0.055), P(path: leaves, fill: .color(pal.clover))]
        case .drop:
            var drop = Path()
            drop.move(to: S.pt(0.5, 0.06))
            drop.addCurve(to: S.pt(0.84, 0.62), control1: S.pt(0.6, 0.26), control2: S.pt(0.84, 0.42))
            drop.addCurve(to: S.pt(0.5, 0.95), control1: S.pt(0.84, 0.82), control2: S.pt(0.69, 0.95))
            drop.addCurve(to: S.pt(0.16, 0.62), control1: S.pt(0.31, 0.95), control2: S.pt(0.16, 0.82))
            drop.addCurve(to: S.pt(0.5, 0.06), control1: S.pt(0.16, 0.42), control2: S.pt(0.4, 0.26))
            drop.closeSubpath()
            return [P(path: drop, fill: .color(pal.water)),
                    P(path: S.ellipse(0.36, 0.64, 0.055, 0.12, 18), fill: .color(.white.opacity(0.75)), rim: false)]
        case .bolt:
            let bolt = S.polygon([(0.55, 0.02), (0.18, 0.55), (0.45, 0.55), (0.32, 0.98), (0.82, 0.4), (0.55, 0.4), (0.78, 0.02)])
            return [P(path: bolt, fill: .color(pal.yellow), line: pal.orange, width: 0.04)]
        case .lollipop:
            var swirl = Path()
            for i in 0...56 {
                let u = Double(i) / 56
                let a = u * 4 * Double.pi, r = 0.02 + u * 0.22
                let point = S.pt(0.5 + cos(a) * r, 0.36 + sin(a) * r)
                if i == 0 { swirl.move(to: point) } else { swirl.addLine(to: point) }
            }
            return [P(path: Path(roundedRect: CGRect(x: 0.465, y: 0.55, width: 0.07, height: 0.42), cornerRadius: 0.035), fill: .color(pal.stick)),
                    P(path: S.circle(0.5, 0.36, 0.28), fill: .color(pal.candy)),
                    P(path: swirl, line: .white, width: 0.05, rim: false),
                    P(path: S.ellipse(0.39, 0.23, 0.07, 0.035, -30), fill: .color(.white.opacity(0.6)), rim: false)]
        case .bicycle:
            var frame = Path()
            frame.move(to: S.pt(0.24, 0.64))
            frame.addLine(to: S.pt(0.42, 0.42))
            frame.addLine(to: S.pt(0.64, 0.42))
            frame.addLine(to: S.pt(0.76, 0.64))
            frame.move(to: S.pt(0.42, 0.42))
            frame.addLine(to: S.pt(0.48, 0.64))
            frame.addLine(to: S.pt(0.24, 0.64))
            frame.move(to: S.pt(0.64, 0.42))
            frame.addLine(to: S.pt(0.61, 0.3))
            frame.addLine(to: S.pt(0.7, 0.28))
            return [P(path: S.circle(0.24, 0.64, 0.17), line: pal.tyre, width: 0.05),
                    P(path: S.circle(0.76, 0.64, 0.17), line: pal.tyre, width: 0.05),
                    P(path: frame, line: pal.bikeBlue, width: 0.045),
                    P(path: Path(roundedRect: CGRect(x: 0.34, y: 0.33, width: 0.13, height: 0.05), cornerRadius: 0.025), fill: .color(pal.tyre))]
        case .schoolBag:
            var handle = Path()
            handle.move(to: S.pt(0.38, 0.24))
            handle.addQuadCurve(to: S.pt(0.62, 0.24), control: S.pt(0.5, 0.06))
            return [P(path: handle, line: pal.bagDeep, width: 0.05),
                    P(path: Path(roundedRect: CGRect(x: 0.2, y: 0.22, width: 0.6, height: 0.66), cornerRadius: 0.1), fill: .color(pal.bag)),
                    P(path: Path(roundedRect: CGRect(x: 0.2, y: 0.22, width: 0.6, height: 0.3), cornerRadius: 0.1), fill: .color(pal.bagDeep), rim: false),
                    P(path: Path(roundedRect: CGRect(x: 0.45, y: 0.46, width: 0.1, height: 0.11), cornerRadius: 0.02), fill: .color(pal.yellow), rim: false)]
        case .leaf:
            var fan = Path()
            fan.move(to: S.pt(0.5, 0.78))
            fan.addLine(to: S.pt(0.14, 0.4))
            fan.addQuadCurve(to: S.pt(0.86, 0.4), control: S.pt(0.5, 0.06))
            fan.closeSubpath()
            var veins = Path()
            for k in -2...2 {
                veins.move(to: S.pt(0.5, 0.76))
                veins.addLine(to: S.pt(0.5 + Double(k) * 0.1, 0.32))
            }
            var stalk = Path()
            stalk.move(to: S.pt(0.5, 0.76))
            stalk.addQuadCurve(to: S.pt(0.56, 0.96), control: S.pt(0.5, 0.88))
            return [P(path: stalk, line: pal.ginkgoDeep, width: 0.05),
                    P(path: fan, fill: .color(pal.ginkgo)),
                    P(path: veins, line: pal.ginkgoDeep.opacity(0.45), width: 0.015, rim: false)]
        }
    }
}

// MARK: - The screens

/// The upper screen while editing: the whole
/// picture with what is drawn on it so far; when the touch screen shows
/// it larger, a frame round the part it shows.
struct DoodleTop: View {
    @ObservedObject var doodle: PhotoDoodle
    var s: Double
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let k = min(w / doodle.units.width, h / doodle.units.height)
            let fit = CGSize(width: doodle.units.width * k, height: doodle.units.height * k)
            let origin = CGPoint(x: (w - fit.width) / 2, y: (h - fit.height) / 2)
            ZStack(alignment: .topLeading) {
                Color.black
                DoodlePicture(image: doodle.image, units: doodle.units, marks: doodle.marks, live: doodle.live,
                              region: CGRect(origin: .zero, size: doodle.units))
                    .frame(width: fit.width, height: fit.height)
                    .accessibilityElement()
                    .accessibilityLabel("整张照片，正在编辑 \(doodle.photo.name)")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("doodle-top-picture")
                    .offset(x: origin.x, y: origin.y)
                if doodle.zoom > 1 {
                    let r = doodle.region
                    ZStack {
                        Rectangle().strokeBorder(.black.opacity(0.55), lineWidth: 3 * s)
                        Rectangle().strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5 * s, dash: [5 * s, 3 * s]))
                    }
                    .frame(width: r.width * k, height: r.height * k)
                    .offset(x: origin.x + r.minX * k, y: origin.y + r.minY * k)
                    .allowsHitTesting(false)
                }
                // What is in hand, beside the picture (the screen is wider than it).
                if origin.x >= 26 * s {
                    VStack(spacing: 4 * s) {
                        Image(systemName: doodle.tool.symbol).font(.system(size: 13 * s, weight: .bold))
                        Text(doodle.tool.title).font(.system(size: 8 * s, weight: .heavy, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: origin.x, height: h)
                    VStack(spacing: 4 * s) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12 * s, weight: .bold))
                        Text("\(doodle.zoom)×").font(.system(size: 9 * s, weight: .heavy, design: .rounded)).monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(doodle.zoom > 1 ? 0.9 : 0.45))
                    .frame(width: origin.x, height: h)
                    .offset(x: w - origin.x)
                }
            }
            .frame(width: w, height: h)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("doodle-top")
    }
}

/// The touch screen while editing: the four tools and 撤销 along the top,
/// the picture to draw on with the tool's choices beside it (under it on a
/// tall screen), 不保存 · 缩小 · 放大 · 移动 · 完成 along the foot.
struct DoodleBottom: View {
    @ObservedObject var model: CameraAppModel
    @ObservedObject var doodle: PhotoDoodle
    var s: Double
    var body: some View {
        GeometryReader { proxy in
            let tall = proxy.size.height > proxy.size.width * 0.95
            ZStack {
                VStack(spacing: 0) {
                    toolRow
                    if tall {
                        VStack(spacing: 8 * s) {
                            DoodleBoard(doodle: doodle, s: s)
                            DoodleOptions(doodle: doodle, horizontal: true, s: s)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .padding(.horizontal, 8 * s).padding(.top, 8 * s).padding(.bottom, 6 * s)
                        .frame(maxHeight: .infinity)
                    } else {
                        HStack(spacing: 7 * s) {
                            DoodleBoard(doodle: doodle, s: s)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            DoodleOptions(doodle: doodle, horizontal: false, s: s)
                                .frame(width: 108 * s)
                        }
                        .padding(.horizontal, 7 * s).padding(.vertical, 6 * s)
                        .frame(maxHeight: .infinity)
                    }
                    footRow
                }
                if doodle.askingDiscard { discardDialog }
                if doodle.saving {
                    ZStack {
                        Color.black.opacity(0.35)
                        HStack(spacing: 8 * s) {
                            ProgressView().tint(.white)
                            Text("正在另存…").font(.system(size: 12 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14 * s).padding(.vertical, 9 * s)
                        .background(.black.opacity(0.6), in: Capsule())
                    }
                    .accessibilityIdentifier("doodle-saving")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("doodle-bottom")
    }

    private var toolRow: some View {
        HStack(spacing: 4 * s) {
            ForEach(DoodleTool.allCases) { tool in
                let chosen = doodle.tool == tool
                Button { doodle.choose(tool) } label: {
                    HStack(spacing: 3 * s) {
                        Image(systemName: tool.symbol).font(.system(size: 10 * s, weight: .bold))
                        Text(tool.title).font(.system(size: 10.5 * s, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(chosen ? .white : FixedMenuStyle.ink)
                    .padding(.horizontal, 8 * s)
                    .frame(height: 26 * s)
                    .background(Capsule().fill(chosen ? FixedMenuStyle.accent : FixedMenuStyle.tile))
                }
                .buttonStyle(MenuPressStyle())
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("doodle-tool-\(tool.rawValue)")
            }
            Spacer(minLength: 0)
            CameraPill(title: String(localized: "撤销"), symbol: "arrow.uturn.backward", color: FixedMenuStyle.inkSoft, s: s * 0.88, identifier: "doodle-undo",
                       enabled: doodle.touched) { doodle.undo() }
        }
        .padding(.horizontal, 7 * s)
        .frame(height: 34 * s)
        .background(FixedMenuStyle.bar)
    }

    private var footRow: some View {
        HStack(spacing: 5 * s) {
            CameraPill(title: String(localized: "不保存"), symbol: "xmark", color: FixedMenuStyle.stop, s: s, identifier: "doodle-discard") { model.askDiscardDoodle() }
            Spacer(minLength: 0)
            CameraPill(title: String(localized: "缩小"), symbol: "minus.magnifyingglass", color: FixedMenuStyle.inkSoft, s: s, identifier: "doodle-zoom-out",
                       enabled: doodle.zoom > 1) { doodle.zoomOut() }
            CameraPill(title: String(localized: "放大"), symbol: "plus.magnifyingglass", color: FixedMenuStyle.inkSoft, s: s, identifier: "doodle-zoom-in",
                       enabled: doodle.zoom < PhotoDoodle.maxZoom) { doodle.zoomIn() }
            CameraPill(title: String(localized: "移动"), symbol: "arrow.up.and.down.and.arrow.left.and.right", color: doodle.moving ? FixedMenuStyle.accent : FixedMenuStyle.inkSoft,
                       s: s, identifier: "doodle-move", enabled: doodle.zoom > 1) { doodle.toggleMoving() }
            Spacer(minLength: 0)
            CameraPill(title: String(localized: "完成"), symbol: "checkmark", color: FixedMenuStyle.go, s: s, identifier: "doodle-done") { model.finishDoodle() }
        }
        .padding(.horizontal, 8 * s)
        .frame(height: 42 * s)
        .background(FixedMenuStyle.bar.opacity(0.12))
    }

    private var discardDialog: some View {
        ZStack {
            Color.black.opacity(0.45).onTapGesture { doodle.askingDiscard = false }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text("不保存这次编辑？").font(.system(size: 13 * s, weight: .bold, design: .rounded))
                Text("画上去的会丢掉，原来的照片不变。").font(.system(size: 10 * s)).foregroundStyle(FixedMenuStyle.inkSoft)
                HStack(spacing: 8 * s) {
                    CameraPill(title: String(localized: "继续画"), symbol: "pencil.tip", color: FixedMenuStyle.inkSoft, s: s, identifier: "doodle-dialog-keep") { doodle.askingDiscard = false }
                    CameraPill(title: String(localized: "不保存"), symbol: "xmark", color: FixedMenuStyle.stop, s: s, identifier: "doodle-dialog-discard") { model.endDoodle() }
                }
            }
            .padding(14 * s)
            .frame(maxWidth: 280 * s, alignment: .leading)
            .background(FixedMenuStyle.paper, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(FixedMenuStyle.tileEdge, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// The picture on the touch screen, drawn on with a finger (or, with 移动 on,
/// moved about when it is larger than the screen).
struct DoodleBoard: View {
    @ObservedObject var doodle: PhotoDoodle
    var s: Double
    /// Where the finger now on the picture came down (a new touch starts a new line).
    @State private var touchStart: CGPoint?
    @State private var panFrom: CGPoint?
    @GestureState private var touching = false
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let region = doodle.region
            DoodlePicture(image: doodle.image, units: doodle.units, marks: doodle.marks, live: doodle.live, region: region)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($touching) { _, state, _ in state = true }
                        .onChanged { value in
                            if doodle.moving {
                                let from = panFrom ?? doodle.center
                                panFrom = from
                                let k = region.width / max(1, size.width)
                                doodle.setCenter(CGPoint(x: from.x - value.translation.width * k, y: from.y - value.translation.height * k))
                                return
                            }
                            let point = CGPoint(x: region.minX + value.location.x / max(1, size.width) * region.width,
                                                y: region.minY + value.location.y / max(1, size.height) * region.height)
                            if touchStart != value.startLocation || doodle.live == nil {
                                doodle.end()
                                touchStart = value.startLocation
                                doodle.begin(point)
                            } else {
                                doodle.move(point)
                            }
                        }
                        .onEnded { _ in finish() }
                )
                .onChange(of: touching) { _, now in if !now { finish() } }
        }
        .aspectRatio(doodle.units.width / doodle.units.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3 * s))
        .overlay(RoundedRectangle(cornerRadius: 3 * s).strokeBorder(.white, lineWidth: 2 * s))
        .shadow(color: FixedMenuStyle.ink.opacity(0.35), radius: 0, y: 1.5 * s)
        .overlay(alignment: .bottom) {
            if !doodle.touched, doodle.live == nil {
                Text(doodle.tool == .stamp ? "点一下贴上「\(doodle.stamp.title)」，按住可以拖着摆" : "用手指在照片上画")
                    .font(.system(size: 9.5 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 8 * s).padding(.vertical, 3 * s)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 6 * s)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if doodle.zoom > 1 {
                Text(doodle.moving ? "\(doodle.zoom)× · 拖动照片" : "\(doodle.zoom)×")
                    .font(.system(size: 9 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
                    .background((doodle.moving ? FixedMenuStyle.accent : Color.black).opacity(0.7), in: Capsule())
                    .padding(5 * s)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("照片：在上面画")
        .accessibilityIdentifier("doodle-board")
    }

    private func finish() {
        panFrom = nil
        touchStart = nil
        doodle.end()
    }
}

/// The tool's choices: the pencil's inks, the stamps, the puffy pen's
/// colours, and each tool's sizes; 全部擦掉 with the eraser.
struct DoodleOptions: View {
    @ObservedObject var doodle: PhotoDoodle
    /// Laid out in rows under the picture (a tall touch screen).
    var horizontal: Bool
    var s: Double
    var body: some View {
        VStack(spacing: 6 * s) {
            switch doodle.tool {
            case .pencil:
                swatches(DoodleInk.allCases.map { DoodleSwatch(id: $0.rawValue, title: $0.title, style: AnyShapeStyle($0.color), chosen: doodle.ink == $0) }) { id in
                    if let next = DoodleInk(rawValue: id) { doodle.ink = next; ConsoleSounds.shared.play(.move) }
                }
                sizeRow
            case .puffy:
                swatches(DoodlePuff.allCases.map { puff -> DoodleSwatch in
                    let style = puff == .rainbow
                        ? AnyShapeStyle(AngularGradient(gradient: Gradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 0.55, brightness: 1) }), center: .center))
                        : AnyShapeStyle(puff.color(at: 0))
                    return DoodleSwatch(id: puff.rawValue, title: puff.title, style: style, chosen: doodle.puff == puff)
                }) { id in
                    if let next = DoodlePuff(rawValue: id) { doodle.puff = next; ConsoleSounds.shared.play(.move) }
                }
                sizeRow
            case .stamp:
                stamps
                sizeRow
            case .eraser:
                sizeRow
                CameraPill(title: String(localized: "全部擦掉"), symbol: "trash", color: FixedMenuStyle.stop, s: s * 0.9, identifier: "doodle-clear",
                           enabled: doodle.hasInk) { doodle.clearAll() }
                Text("只擦画上去的，照片本身擦不掉").font(.system(size: 8.5 * s, weight: .semibold)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if !horizontal { Spacer(minLength: 0) }
            }
        }
        .padding(6 * s)
        .frame(maxWidth: .infinity, maxHeight: horizontal ? nil : .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8 * s, style: .continuous).fill(.white.opacity(0.55)))
        .foregroundStyle(FixedMenuStyle.ink)
    }

    private func swatches(_ items: [DoodleSwatch], pick: @escaping (String) -> Void) -> some View {
        let columns = horizontal ? 7 : 4
        let cell: CGFloat = (horizontal ? 26 : 20) * s
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 4 * s), count: columns), spacing: 5 * s) {
            ForEach(items) { item in
                Button { pick(item.id) } label: {
                    Circle().fill(item.style)
                        .overlay(Circle().strokeBorder(FixedMenuStyle.ink.opacity(0.25), lineWidth: 1))
                        .padding(2.5 * s)
                        .overlay(Circle().strokeBorder(item.chosen ? FixedMenuStyle.accent : .clear, lineWidth: 2.2 * s))
                        .frame(width: cell, height: cell)
                }
                .buttonStyle(MenuPressStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item.chosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("doodle-colour-\(item.id)")
            }
        }
    }

    /// The stamps in rows (not a lazy grid: every cell drawn, and drawn
    /// in a source render too); three across beside the picture, seven
    /// across under it.
    private var stamps: some View {
        let columns = horizontal ? 7 : 3
        let cell: CGFloat = (horizontal ? 44 : 28) * s
        let gap: CGFloat = 4 * s
        let all = DoodleStamp.offered
        let rows: [[DoodleStamp]] = stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
        let rowWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
        let grid = VStack(spacing: gap) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(rows[r]) { stamp in stampCell(stamp, cell) }
                }
                .frame(width: rowWidth, alignment: .leading)
            }
        }
        #if RENDER_PREVIEW
        // (A scroll view's content is not drawn off screen.)
        return grid.frame(maxHeight: .infinity, alignment: .top).clipped()
        #else
        return ScrollView(.vertical, showsIndicators: false) { grid }
            .frame(maxHeight: horizontal ? CGFloat(rows.count) * cell + CGFloat(rows.count - 1) * gap : .infinity)
        #endif
    }

    private func stampCell(_ stamp: DoodleStamp, _ cell: CGFloat) -> some View {
        let chosen = doodle.stamp == stamp
        return Button { doodle.stamp = stamp; ConsoleSounds.shared.play(.move) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                    .fill(chosen ? FixedMenuStyle.accent.opacity(0.22) : Color(white: 0.55).opacity(0.28))
                DoodleStampIcon(stamp: stamp)
                    .padding(3 * s)
            }
            .overlay(RoundedRectangle(cornerRadius: 6 * s, style: .continuous).strokeBorder(chosen ? FixedMenuStyle.accent : .clear, lineWidth: 2 * s))
            .frame(width: cell, height: cell)
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(stamp.title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("doodle-stamp-\(stamp.rawValue)")
    }

    private var sizeRow: some View {
        HStack(spacing: 4 * s) {
            ForEach(DoodleSize.allCases) { size in
                let chosen = doodle.size == size
                Button { doodle.setSize(size) } label: {
                    VStack(spacing: 1 * s) {
                        ZStack {
                            if doodle.tool == .stamp {
                                Image(systemName: "heart.fill").font(.system(size: [7.0, 10, 14][size.rawValue] * s))
                            } else {
                                Circle().frame(width: [3.0, 6, 11][size.rawValue] * s, height: [3.0, 6, 11][size.rawValue] * s)
                            }
                        }
                        .frame(height: 15 * s)
                        Text(doodle.tool.sizeTitle(size)).font(.system(size: 8 * s, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(chosen ? .white : FixedMenuStyle.ink)
                    .frame(maxWidth: .infinity).frame(height: 30 * s)
                    .background(RoundedRectangle(cornerRadius: 6 * s, style: .continuous).fill(chosen ? FixedMenuStyle.accent : FixedMenuStyle.tile))
                }
                .buttonStyle(MenuPressStyle())
                .accessibilityLabel(doodle.tool.sizeTitle(size))
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("doodle-size-\(size.rawValue)")
            }
        }
        .frame(maxWidth: horizontal ? CGFloat(200 * s) : .infinity)
    }
}

/// A colour in the tool's choices.
struct DoodleSwatch: Identifiable {
    var id: String
    var title: String
    var style: AnyShapeStyle
    var chosen: Bool
}

/// A stamp drawn small (the picker's cells, the stamp sheet).
struct DoodleStampIcon: View {
    var stamp: DoodleStamp
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            DoodleStampArt.draw(stamp, at: CGPoint(x: size.width / 2, y: size.height / 2), size: side * 0.9, in: context)
        }
        .accessibilityHidden(true)
    }
}

#if RENDER_PREVIEW
/// Every stamp, large, on a picture-like ground (source renders).
struct DoodleStampSheet: View {
    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(130), spacing: 10), count: 7)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DoodleStamp.allCases) { stamp in
                VStack(spacing: 4) {
                    DoodleStampIcon(stamp: stamp)
                        .frame(width: 112, height: 112)
                        .background(LinearGradient(colors: [Color(red: 0.62, green: 0.56, blue: 0.48), Color(red: 0.36, green: 0.42, blue: 0.5)], startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 10))
                    Text(stamp.title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.16))
    }
}
#endif
