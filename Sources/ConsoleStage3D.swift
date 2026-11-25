import SwiftUI
import simd
import ImageIO
#if os(iOS)
import RealityKit
import UIKit
import Metal
#endif

// The console as a solid (round 18). The library's upper screen shows it in
// three dimensions: the player turns it with a finger, looks at every part,
// and watches it turn round to take a game card. It is built from the same
// numbers as the flat console (ConsoleMetrics, HardwareConsole's positions):
// the faces are the flat drawings printed on the solid, the raised parts
// (keys, pads, sliders, the hinge, the card slot) are geometry.
//
// No photograph or model file is used: every mesh is generated here from the
// 2D design (rounded rectangles extruded, capsules, cylinders, a cross).

/// Design units → metres: the 760-unit console is 1 m wide in the scene.
enum ConsoleModel {
    static let u: Float = 1.0 / 760
    /// Thickness of the lower half, the lid, the hinge barrel radius.
    static let lowerDepth: Float = 64 * u
    static let lidDepth: Float = 52 * u
    static let hingeRadius: Float = 22 * u
    /// The hinge axis (lower-half space, Y up, Z toward the player): the
    /// barrel rides on the rear edge, bulging above it and a little behind,
    /// so the rear face under it (the card slot) stays in view from behind.
    static let hingeY: Float = 52 * u
    static let hingeZ: Float = -210 * u
    /// The card slot on the rear face of the lower half (design x, slot
    /// width/height, card size). The card goes in label up,
    /// into the back of the console.
    static let slotX: Float = -140 * u
    static let slotY: Float = 16 * u
    static let slotWidth: Float = 200 * u
    static let slotHeight: Float = 26 * u
    static let cardWidth: Float = 187 * u
    /// Round 28: as CardDimensions.length (a real card is a little wider than long).
    static let cardLength: Float = Float(CardDimensions.length) * u
    static let cardThickness: Float = 21 * u
    /// How far the inserted card stands out of the slot.
    static let cardLip: Float = 20 * u
    /// Camera: vertical field of view.
    static let fieldOfView: Float = 30
    /// The bounding radius used to frame the open console on the stage.
    static let stageRadius: Float = 0.55

    /// Flat-drawing coordinates → lower-half space (x right, z toward the player).
    static func lower(_ x: Double, _ y: Double) -> SIMD3<Float> {
        SIMD3(Float(x - 380) * u, 0, Float(y - 220) * u)
    }
    /// Flat-drawing coordinates of the lid face → lid space (hinge side at +z).
    static func lid(_ x: Double, _ y: Double) -> SIMD3<Float> {
        SIMD3(Float(x - 380) * u, 0, Float(y - 456) * u)
    }
}

/// Where the console is: on the stage for looking at, turned round for the
/// card, or flat and filling the screen (the way into the game). Round 30:
/// `program`, flat and face up, as big as the display allows with the
/// paper round it, a program of the console's own on its two screens
/// (ConsoleStage.showProgram).
enum ConsolePose: Equatable {
    case stage, back, flat, program
}

/// Where the console stands and how it is turned: saved before a card is
/// lifted, put back when the card is put down (round 19).
struct ConsoleView: Equatable {
    var yaw: Double
    var tilt: Double
    var zoom: Double
    var pose: ConsolePose
}

/// What a finger touched on the console (ConsoleStage.touch).
struct ConsoleTouch {
    var part: String
    /// On the touch screen: the point of its picture (400 × 300).
    var screenPoint: CGPoint?
    /// On the D-pad: the arm.
    var direction: ConsoleDirection?
}
enum ConsoleDirection { case up, down, left, right }

// MARK: - The console's own menu (round 20)

/// The console on the stage has a menu of its own in its two LCDs, the way
/// a handheld does: on the touch screen the game card's icon and the
/// console's own functions, a bar of buttons along the bottom; on the upper
/// screen the clock and what is chosen. A card is started there — touch its
/// icon, then 开启 (or press A) — and the functions work with no card in.
/// The structure is a handheld's; the drawing, names and marks are FoldArc's.
/// Round 31: 游玩模式 is the eighth tile (it was a small icon that only came
/// with software running), two full rows of four. Round 32 (11-05):
/// 相册 is a tile too; 游戏笔记 is one of the small icons
/// along the top, and the tiles stay two rows
/// of four, the ninth and any more on a second page a swipe away.
enum ConsoleHomeItem: String, CaseIterable, Identifiable {
    case card, camera, album, settings, importFiles, activity, theme, manual, modes, pictureFrame, tinBox
    var id: String { rawValue }
    var title: String {
        switch self {
        case .card: return String(localized: "卡带")
        case .camera: return String(localized: "相机")
        case .album: return String(localized: "相册")
        case .settings: return String(localized: "设置")
        case .importFiles: return String(localized: "导入")
        case .activity: return String(localized: "游戏记录")
        case .theme: return String(localized: "主题")
        case .manual: return String(localized: "说明书")
        case .modes: return String(localized: "游玩模式")
        case .pictureFrame: return String(localized: "画框")
        case .tinBox: return String(localized: "铅笔盒")
        }
    }
    var symbol: String {
        switch self {
        case .card: return "memorychip"
        case .camera: return "camera.fill"
        case .album: return "photo.on.rectangle.angled"
        case .settings: return "gearshape.fill"
        case .importFiles: return "square.and.arrow.down.fill"
        case .activity: return "chart.bar.fill"
        case .theme: return "paintpalette.fill"
        case .manual: return "book.closed.fill"
        case .modes: return "rectangle.on.rectangle"
        case .pictureFrame: return "photo.artframe"
        case .tinBox: return "pencil.and.ruler"
        }
    }
    var blurb: String {
        switch self {
        case .card: return String(localized: "插在卡槽里的软件")
        case .camera: return String(localized: "用 iPhone 的前后摄像头拍照：L、R 或 A 拍，九种镜头，照片存进主机的 SD 卡")
        case .album: return String(localized: "SD 卡上的照片：翻看、删除")
        case .settings: return String(localized: "主机的系统设置：用户信息、声音、触摸屏、家长控制、画面渲染、数据管理…")
        case .importFiles: return String(localized: "从「文件」导入 3DS 软件或 Homebrew，做成卡带放到架子上")
        case .activity: return String(localized: "每个软件玩了多久、玩过几次、最近一次是什么时候")
        case .theme: return String(localized: "游戏库和主菜单的配色、掌机的机身配色")
        case .manual: return String(localized: "游戏库和掌机按键的用法")
        case .modes: return String(localized: "掌机、桌面、手柄、TV、沉浸五种玩法：iPhone 怎么拿，画面放在哪里")
        case .pictureFrame: return String(localized: "一幅一直在动的风景，早晚的光跟着时间走；把 iPhone 立在桌上，就是一个会动的画框")
        case .tinBox: return String(localized: "攒到的小东西放在这里，挑几样贴到盒盖上；合上手机，外屏就是这只铅笔盒")
        }
    }
}

/// The programs the menu's tiles start (round 30: 游戏记录, 主题 and 说明书
/// are programs on the console's screens too).
extension ConsoleApp {
    /// What the console's menu calls it (its tile), when it has one.
    var homeItem: ConsoleHomeItem? {
        switch self {
        case .settings: return .settings
        case .camera: return .camera
        case .album: return .album
        case .activity: return .activity
        case .theme: return .theme
        case .manual: return .manual
        case .modes: return .modes
        case .pictureFrame: return .pictureFrame
        case .tinBox: return .tinBox
        // (游戏笔记 is a small icon, ConsoleHomeShortcut.notes.)
        case .notes, .setup, .home: return nil
        }
    }
    /// The program a tile of the console's menu starts (nil: the card in
    /// the slot, or 导入, which are not programs).
    init?(homeItem: ConsoleHomeItem) {
        switch homeItem {
        case .camera: self = .camera
        case .album: self = .album
        case .settings: self = .settings
        case .activity: self = .activity
        case .theme: self = .theme
        case .manual: self = .manual
        case .modes: self = .modes
        case .pictureFrame: self = .pictureFrame
        case .tinBox: self = .tinBox
        case .card, .importFiles: return nil
        }
    }
}

/// A button in the bar along the bottom of the touch screen.
enum ConsoleHomeAction: String {
    case open, resume, restart
    /// Round 30: the software suspended under the menu (HOME in a game):
    /// back to it, or closed (the demo goes back to the library).
    case continueGame, continueDemo, closeGame, closeDemo
    var title: String {
        switch self {
        case .open: return String(localized: "开启")
        case .resume: return String(localized: "继续上次")
        case .restart: return String(localized: "重新开始")
        case .continueGame: return String(localized: "继续游戏")
        case .continueDemo: return String(localized: "继续演示")
        case .closeGame: return String(localized: "关闭软件")
        case .closeDemo: return String(localized: "返回游戏库")
        }
    }
    var symbol: String {
        switch self {
        case .open, .resume, .continueGame, .continueDemo: return "play.fill"
        case .restart: return "arrow.counterclockwise"
        case .closeGame: return "xmark"
        case .closeDemo: return "house"
        }
    }
    /// Drawn quieter, on the left (it does not start anything).
    var isQuiet: Bool { self == .restart || self == .closeGame || self == .closeDemo }
}

/// Round 30: the row of small icons over the tiles while software is
/// suspended under the menu, as a handheld's menu has its small icons along
/// the top. Round 31: only a few belong there, each a thing of its own;
/// so only what has no tile or page
/// elsewhere stays, each with its name under it: 保存进度, 读取进度, 屏幕亮度.
/// 游玩模式 became a tile, 机身配色 is in 主题, 画面与手感 was 系统设置's pages
/// again, 操作指南 is in 说明书, 合上掌机 in 游玩模式, and a debug
/// build's 开发者 is in 系统设置 › 其他设置. 保存进度 / 读取进度 are FoldArc's
/// save state of the running software (one per software, outside the
/// game's own saves): what the banner explains.
/// Round 32: 游戏笔记 is one of them,
/// and the row is there with no software too (the library's console,
/// the handheld gone into): 游戏笔记 and 屏幕亮度 then.
enum ConsoleHomeShortcut: String, CaseIterable, Identifiable {
    case save, load, notes, brightness
    /// 铅笔盒 (PencilBox.swift), beside 游戏笔记: two things of the stationer's.
    case pencilBox
    /// 系统设置 › 画面滤镜, beside 屏幕亮度.
    case filter
    /// 11-07: 按键点屏, on or off for the
    /// suspended software (KeyTaps).
    case keyTaps
    /// 11-07: 倍速, 1× → 2× → 4× → 1×.
    case speed
    /// 存档位: which of a game's numbered places 保存进度 and 读取进度 use
    /// (系统设置's page of it, in place).
    case slots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .save: return String(localized: "保存进度")
        case .load: return String(localized: "读取进度")
        case .notes: return String(localized: "游戏笔记")
        case .pencilBox: return String(localized: "铅笔盒")
        case .brightness: return String(localized: "屏幕亮度")
        case .filter: return String(localized: "画面滤镜")
        case .keyTaps: return String(localized: "按键点屏")
        case .speed: return String(localized: "倍速")
        case .slots: return String(localized: "存档位")
        }
    }
    var symbol: String {
        switch self {
        case .save: return "square.and.arrow.down"
        case .load: return "clock.arrow.circlepath"
        case .notes: return "pencil.and.outline"
        case .pencilBox: return "pencil.and.ruler"
        case .brightness: return "sun.max"
        case .filter: return "camera.filters"
        case .keyTaps: return "hand.tap"
        case .speed: return "forward"
        case .slots: return "square.stack.3d.up"
        }
    }
    /// The icon as the state has it (按键点屏 on, 倍速 above 1×: filled).
    func symbol(in state: ConsoleHomeState) -> String {
        switch self {
        case .keyTaps: return state.keyTaps ? "hand.tap.fill" : symbol
        case .speed: return state.speed > 1 ? "forward.fill" : symbol
        default: return symbol
        }
    }
    /// The name as the state has it (按键点屏：开 / 关, 倍速：2×; 倍速 without
    /// Pro: that it is Pro's).
    func title(in state: ConsoleHomeState) -> String {
        switch self {
        case .keyTaps: return String(localized: "按键点屏：\(state.keyTaps ? String(localized: "开") : String(localized: "关"))")
        case .speed: return state.speedLocked ? String(localized: "倍速 · 典藏卡带") : String(localized: "倍速：\(Int(state.speed))×")
        case .slots: return String(localized: "存档位 \(state.slot)")
        default: return title
        }
    }
    /// What it does, as the state has it (倍速 without Pro: where to open it).
    func blurb(in state: ConsoleHomeState) -> String {
        guard self == .speed, state.speedLocked else { return blurb }
        return String(localized: "让游戏跑快一些（2×、4×）。这是典藏卡带的功能：点一下看典藏卡带")
    }
    var blurb: String {
        switch self {
        case .save: return String(localized: "把这个软件此刻的样子整个存下来（即时存档，存进现在用的存档位，和游戏自己的存档无关）")
        case .load: return String(localized: "回到现在用的存档位里「保存进度」存下的那一刻；没存过就没有可读的")
        case .slots: return String(localized: "每个游戏有好几个存档位：保存进度、读取进度用的是选中的那一个。点一下换一个")
        case .notes: return String(localized: "一叠便签，用手指或 Apple Pencil 写写画画，两个手指翻页，撕掉、保存成存稿；游戏暂停时能把画面放到纸下面")
        case .pencilBox: return String(localized: "攒到的小东西放在这里，挑几样贴到盒盖上；合上手机，外屏就是这只铅笔盒")
        case .brightness: return String(localized: "两块屏的亮度，五档")
        case .filter: return String(localized: "给游戏画面加一层效果：原样、柔和、扫描线、LCD 网格、老电视")
        case .keyTaps: return String(localized: "A、B、X、Y 按下去等于点一下触摸屏，点在你最后点过的地方（没点过就点正中间）。只对这个游戏，给只靠点屏幕玩的游戏用")
        case .speed: return String(localized: "让游戏跑快一些：点一下在 1×、2×、4× 之间换。快的时候没有声音；本来就跑不满速的游戏快不了多少")
        }
    }
    /// The row with software suspended under the menu (a game's: 按键点屏
    /// at the end), and without, as many as there can be; what shows is
    /// what 系统设置 › 其他设置 › 主菜单顶上的按键 leaves on (11-15:
    /// 铅笔盒 off unless turned on there).
    static let suspendedAll: [ConsoleHomeShortcut] = [.save, .load, .notes, .pencilBox, .brightness, .filter]
    static let suspendedGameAll: [ConsoleHomeShortcut] = [.save, .load, .slots, .notes, .pencilBox, .brightness, .filter, .keyTaps, .speed]
    static let idleAll: [ConsoleHomeShortcut] = [.notes, .pencilBox, .brightness, .filter]
    static var suspended: [ConsoleHomeShortcut] { shown(suspendedAll) }
    static var suspendedGame: [ConsoleHomeShortcut] { shown(suspendedGameAll) }
    static var idle: [ConsoleHomeShortcut] { shown(idleAll) }
    /// In the order 系统设置 lists them.
    static let listed: [ConsoleHomeShortcut] = [.save, .load, .slots, .notes, .pencilBox, .brightness, .filter, .keyTaps, .speed]
    /// Which are left out of the row: their names, a comma between (a
    /// string, so @AppStorage can watch it); a new console leaves out 铅笔盒
    /// (it has its tile).
    static let hiddenKey = "foldarc.home.hidden"
    static let hiddenAtFirst = "pencilBox"
    static func hidden(_ defaults: UserDefaults = .standard) -> Set<ConsoleHomeShortcut> {
        parse(defaults.string(forKey: hiddenKey) ?? hiddenAtFirst)
    }
    static func parse(_ text: String) -> Set<ConsoleHomeShortcut> {
        Set(text.split(separator: ",").compactMap { ConsoleHomeShortcut(rawValue: String($0)) })
    }
    static func text(_ hidden: Set<ConsoleHomeShortcut>) -> String {
        listed.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }
    static func shown(_ row: [ConsoleHomeShortcut], _ defaults: UserDefaults = .standard) -> [ConsoleHomeShortcut] {
        let off = hidden(defaults)
        return row.filter { !off.contains($0) }
    }
    /// Only over a game (保存进度 and 读取进度 also over a built-in program).
    var onlyOverGame: Bool { [.slots, .keyTaps, .speed].contains(self) }
    var onlyOverSoftware: Bool { [.save, .load].contains(self) }
}

/// Everything the menu draws.
struct ConsoleHomeState: Equatable {
    var selection: ConsoleHomeItem?
    /// The card home in the slot (the console reads it).
    var card: GameCardInfo?
    /// A card is in the slot but not pushed home.
    var looseTitle: String?
    /// When the card's software was left (its resume state).
    var resumeDate: Date?
    /// The card is a game and this build has no core to run it.
    var coreMissing = false
    /// The clock, to the minute, and the battery (nil: unknown).
    var minute = 0
    var battery: Double?
    var charging = false
    /// The console has not been set up yet (round 23): its screens offer
    /// the first-time setup instead of the menu.
    var setupPending = false
    /// Drawn by the menu running on the handheld (round 26), where there is
    /// no shelf below to take a card from: the words say to go back first.
    var onHandheld = false
    /// Round 30: the card's software is suspended under the menu (HOME in a
    /// game); the row of small icons over the tiles, the one chosen there.
    var suspended = false
    var shortcuts: [ConsoleHomeShortcut] = []
    var shortcut: ConsoleHomeShortcut?
    /// 按键点屏 is on for the suspended software.
    var keyTaps = false
    /// 倍速 of the suspended software.
    var speed: Double = 1
    /// 倍速 is Zero EMU Pro's and Pro is not open: its icon wears a lock.
    var speedLocked = false
    /// The 存档位 the suspended game uses.
    var slot = 1
    /// Round 31: the play mode now (游玩模式's tile says it on the upper screen).
    var mode = ScreenLayout.stored
    /// Round 32: the page of tiles on the touch screen (two rows of four
    /// each; a swipe turns it).
    var page = 0
    var pageCount: Int { ConsoleHomeLayout.pageCount(onHandheld: onHandheld) }

    /// The bar's two buttons for what is chosen.
    var bar: (left: ConsoleHomeAction?, right: ConsoleHomeAction?) {
        guard !setupPending, shortcut == nil else { return (nil, nil) }
        switch selection {
        case .card?:
            if suspended, let card { return card.isDemo ? (.closeDemo, .continueDemo) : (.closeGame, .continueGame) }
            guard let card, !coreMissing || card.isDemo else { return (nil, nil) }
            if resumeDate != nil, !card.isDemo { return (.restart, .resume) }
            return (nil, .open)
        case .some: return (nil, .open)
        case nil: return (nil, nil)
        }
    }
    private var cardKey: String {
        guard let card else { return "-" }
        return "\(card.title)|\(card.subtitle)|\(card.isDemo ? 1 : 0)|\(card.icon == nil ? 0 : 1)|\(card.cartridge?.rawValue ?? "-")"
    }
    /// What the touch screen shows, as a key for its printed picture.
    var bottomKey: String {
        let bar = self.bar
        return "\(selection?.rawValue ?? "-")|\(cardKey)|\(bar.left?.rawValue ?? "-")|\(bar.right?.rawValue ?? "-")|\(looseTitle == nil ? 0 : 1)|\(setupPending ? "setup" : "")|\(suspended ? 1 : 0)|\(shortcuts.map(\.rawValue).joined(separator: ","))|\(shortcut?.rawValue ?? "-")|\(onHandheld ? "h" : "")|p\(page)|\(LibraryTheme.chosen.rawValue)"
    }
    /// What the upper screen shows.
    var topKey: String {
        let level = battery.map { Int(($0 * 20).rounded()) } ?? -1
        return "\(selection?.rawValue ?? "-")|\(cardKey)|\(looseTitle ?? "-")|\(Int(resumeDate?.timeIntervalSince1970 ?? 0))|\(coreMissing ? 1 : 0)|\(minute)|\(level)|\(charging ? 1 : 0)|\(setupPending ? "setup" : "")|\(onHandheld ? "h" : "")|\(suspended ? 1 : 0)|\(shortcut?.rawValue ?? "-")|\(mode.rawValue)|\(LibraryTheme.chosen.rawValue)"
    }
}

/// Where things are on the touch screen's picture (400 × 300 points).
/// Round 25: four tiles to a row (相机 came in after the card, where a
/// handheld's menu has its camera), seven tiles in two rows; round 31:
/// eight (游玩模式 last) in the library, seven on the full-screen handheld;
/// round 32: 相册 after 相机 — nine in the library, eight on the handheld,
/// still two rows of four a page, the
/// rest on the next page, which a swipe (or the D-pad past the row's end)
/// turns to.
enum ConsoleHomeLayout {
    static let size = CGSize(width: 400, height: 300)
    /// The library's console: all ten (铅笔盒, the eleventh, is a small
    /// icon now, and lies in a corner of the library).
    static let items: [ConsoleHomeItem] = [.card, .camera, .album, .settings, .importFiles, .activity, .theme, .manual, .modes, .pictureFrame]
    /// Round 31: on the full-screen handheld (software suspended under the menu,
    /// or the console pinched into) 导入 is not among them — the file picker
    /// and the shelf the new card lands on are the library's.
    static func items(onHandheld: Bool) -> [ConsoleHomeItem] {
        onHandheld ? items.filter { $0 != .importFiles } : items
    }
    static let columns = 4
    static let rows = 2
    static let perPage = columns * rows
    static let tileSize = CGSize(width: 86, height: 94)
    static func pageCount(onHandheld: Bool) -> Int { max(1, (items(onHandheld: onHandheld).count + perPage - 1) / perPage) }
    /// The tiles on one page.
    static func items(onHandheld: Bool, page: Int) -> [ConsoleHomeItem] {
        let all = items(onHandheld: onHandheld)
        let start = max(0, min(all.count, page * perPage))
        return Array(all[start..<min(all.count, start + perPage)])
    }
    /// The page a tile is on.
    static func page(of item: ConsoleHomeItem, onHandheld: Bool) -> Int {
        (items(onHandheld: onHandheld).firstIndex(of: item) ?? 0) / perPage
    }
    /// Round 30: with the row of small icons along the top, the tiles stand
    /// a little lower and closer. (Where it is on its own page.)
    static func tile(_ item: ConsoleHomeItem, onHandheld: Bool = false, shortcuts: Bool = false) -> CGRect {
        let index = (items(onHandheld: onHandheld).firstIndex(of: item) ?? 0) % perPage
        let column = Double(index % columns), row = Double(index / columns)
        return CGRect(x: 13 + column * 96, y: (shortcuts ? 43 : 16) + row * (shortcuts ? 98 : 106), width: tileSize.width, height: tileSize.height)
    }
    /// The page dots (only with more than one page): in the bar, between
    /// its two buttons.
    static func pageDot(_ page: Int, of count: Int) -> CGRect {
        let pitch = 14.0, width = Double(count) * pitch
        return CGRect(x: 200 - width / 2 + Double(page) * pitch + 3, y: 258, width: 8, height: 8)
    }
    /// A touch on the dots' strip: the page (nil elsewhere).
    static func pageHit(_ point: CGPoint, state: ConsoleHomeState) -> Int? {
        let count = state.pageCount
        guard count > 1 else { return nil }
        return (0..<count).first { pageDot($0, of: count).insetBy(dx: -4, dy: -6).contains(point) }
    }
    /// The small icons along the top (round 30), `count` of them, centred;
    /// round 31: each with its name under it.
    static let shortcutSize = CGSize(width: 60, height: 36)
    static func shortcut(_ index: Int, of count: Int) -> CGRect {
        // (Six fit across the 400-wide screen with the gaps halved, seven
        // a little narrower, eight narrower still, nine with the gaps
        // smaller again.)
        let gap = count > 8 ? 3.0 : count > 5 ? 4.0 : 8.0
        let each = count > 8 ? 41.0 : count > 7 ? 45.5 : count > 6 ? 52.0 : shortcutSize.width
        let width = Double(count) * each + Double(max(0, count - 1)) * gap
        return CGRect(x: 200 - width / 2 + Double(index) * (each + gap), y: 3, width: each, height: shortcutSize.height)
    }
    static let bar = CGRect(x: 0, y: 248, width: 400, height: 52)
    static let leftButton = CGRect(x: 12, y: 256, width: 168, height: 36)
    static let rightButton = CGRect(x: 220, y: 256, width: 168, height: 36)
    /// 开始设置 while the console is not set up (round 23).
    static let setupButton = CGRect(x: 100, y: 196, width: 200, height: 46)
    enum Hit: Equatable { case tile(ConsoleHomeItem), bar(ConsoleHomeAction), setup, shortcut(ConsoleHomeShortcut), page(Int) }
    /// What a touch at `point` of the picture means.
    static func hit(_ point: CGPoint, state: ConsoleHomeState) -> Hit? {
        // Not set up: the whole screen is the way into the setup.
        if state.setupPending { return CGRect(origin: .zero, size: size).contains(point) ? .setup : nil }
        if let page = pageHit(point, state: state) { return .page(page) }
        if point.y >= bar.minY - 4 {
            let buttons = state.bar
            if let left = buttons.left, leftButton.insetBy(dx: -8, dy: -8).contains(point) { return .bar(left) }
            if let right = buttons.right, rightButton.insetBy(dx: -8, dy: -8).contains(point) { return .bar(right) }
            return nil
        }
        let row = state.shortcuts
        if !row.isEmpty, let index = row.indices.first(where: { shortcut($0, of: row.count).insetBy(dx: -3, dy: -3).contains(point) }) {
            return .shortcut(row[index])
        }
        return items(onHandheld: state.onHandheld, page: state.page).first { tile($0, onHandheld: state.onHandheld, shortcuts: !row.isEmpty).insetBy(dx: -4, dy: -6).contains(point) }.map { .tile($0) }
    }
    /// The tile the D-pad moves to from `item`: within its page, and past
    /// the row's end onto the next page (round 32), before its start onto
    /// the one before.
    static func move(from item: ConsoleHomeItem?, _ direction: ConsoleDirection, onHandheld: Bool = false) -> ConsoleHomeItem {
        let items = items(onHandheld: onHandheld)
        guard let item, let index = items.firstIndex(of: item) else { return .card }
        let page = index / perPage, pages = pageCount(onHandheld: onHandheld)
        let onPage = min(perPage, items.count - page * perPage)
        let rows = (onPage + columns - 1) / columns
        var column = (index % perPage) % columns, row = (index % perPage) / columns
        var target = page
        switch direction {
        case .left:
            if column > 0 { column -= 1 } else if page > 0 { target = page - 1; column = columns - 1 } else { return item }
        case .right:
            if column < columns - 1, (index % perPage) + 1 < onPage { column += 1 }
            else if page + 1 < pages { target = page + 1; column = 0 }
            else { return item }
        case .up: row = max(0, row - 1)
        case .down: row = min(rows - 1, row + 1)
        }
        // A short row or page: past its end, its last tile.
        let start = target * perPage
        let count = min(perPage, items.count - start)
        return items[start + min(count - 1, row * columns + column)]
    }
    /// The tile a page turn lands on: the same place on the new page, or
    /// the last tile there.
    static func landing(on page: Int, from item: ConsoleHomeItem?, onHandheld: Bool) -> ConsoleHomeItem {
        let items = items(onHandheld: onHandheld)
        let start = max(0, min(items.count - 1, page * perPage))
        let count = min(perPage, items.count - start)
        let place = item.flatMap { items.firstIndex(of: $0) }.map { $0 % perPage } ?? 0
        return items[start + min(count - 1, place)]
    }
}

#if os(iOS)
@MainActor final class ConsoleStage: ObservableObject {
    /// Round 31: changed in place (主题 › 机身配色 with the console on the
    /// stage): setFinish.
    private(set) var finish: ShellFinish
    /// Set by the view: the size of the RealityView and the rectangle, in
    /// its coordinates, where the console should appear centred.
    var viewSize = CGSize.zero
    var stageRect = CGRect.zero
    /// The user's turn of the console (degrees). `tilt` is the angle between
    /// the line of sight and the lower face's normal: 0 looks straight down.
    /// Not published (round 20): a drag changes them every frame, and the
    /// whole library redrew with each change; `moving` and `settled` tell
    /// the views what they need.
    var yaw = 0.0
    var tilt = 52.0
    var zoom = 1.0
    @Published private(set) var pose = ConsolePose.stage
    /// The console is turning, coming up or going down (the shadow follows
    /// it frame by frame only then; the markers over it hide meanwhile).
    @Published private(set) var moving = false
    /// The name of the part last tapped (shown as a callout).
    @Published var calloutName: String?
    @Published var calloutPoint = CGPoint.zero
    /// Bumped with every callout, so the same name twice shows twice.
    @Published var calloutStamp = 0
    /// The slot is offered a card: its door open, the mark over it lit.
    @Published private(set) var slotOpen = false
    /// A card is in the slot and pushed home: the console reads it.
    @Published private(set) var cardInserted = false
    /// A card is in the slot but not pushed home (drawn out part of the way
    /// and let go, round 20): the console does not read it.
    @Published private(set) var cardLoose = false
    /// How far the card in the slot is drawn out: 0 home, 1 clear of it.
    private(set) var cardOut = 0.0
    /// Bumped when a pose animation has finished (the markers over the
    /// console re-project themselves).
    @Published private(set) var settled = 0
    private(set) var animating = false

    let root = Entity()
    let camera = PerspectiveCamera()
    private let lowerHalf = Entity()
    private let lidPivot = Entity()
    private let doorPivot = Entity()
    private let slotMouth = Entity()
    private var slotMark: ModelEntity?
    /// The studio light the plastic reflects (an image-based light).
    private let studio = Entity()
    /// The shelf of cards (round 27): solids in this scene, under the camera.
    let shelf = ShelfScene()
    private var shelfSubscription: EventSubscription?
    private var card: ModelEntity?
    private var cardTitle = ""
    /// What the LCDs show (kept for a build that comes after the call).
    private var homeState = ConsoleHomeState()
    private var shownTopKey: String?
    private var shownBottomKey: String?
    private var upperScreen: ModelEntity?
    private var lowerScreen: ModelEntity?
    /// The 3D slider's knob (round 30: it follows the 3D setting, dragged).
    private var depthKnob: ModelEntity?
    /// Keys that move when pressed, by part name, with where they rest.
    private var keys: [String: (entity: Entity, rest: SIMD3<Float>)] = [:]
    private var volumeKnob: ModelEntity?
    /// The stylus (round 23): its body and end cap, sliding along its hole
    /// in the rear face; out of the console it is in the hand (not drawn).
    private let stylus = Entity()
    private(set) var stylusOut = false
    /// Wired earphones in the jack (round 23), made the first time
    /// headphones are connected; shown while they are.
    private let earphones = Entity()
    private var earphonesBuilt = false
    private(set) var earphonesIn = false
    /// The charger's cable in the rear port (round 26), shown while the
    /// iPhone is on its charger; see `setCharger`.
    private let charger = Entity()
    private let chargerPlug = Entity()
    private let chargerCable = ModelEntity()
    private let chargerShadow = ModelEntity()
    private var chargerMesh: LowLevelMesh?
    private var chargerShadowMesh: LowLevelMesh?
    private var chargerBuilt = false
    /// The charger is in (or on its way in).
    private(set) var chargerIn = false
    /// Where the cable is: 0 away, 1 laid on the table behind the console
    /// with its plug on the table, 2 plugged in; moving to `chargerTarget`.
    private var chargerPhase: Float = 0
    private var chargerTarget: Float = 0
    private var chargerShown: Float = -1
    /// Called when the plug seats in the port or leaves it (the library
    /// clicks and names it).
    var chargerSeated: ((Bool) -> Void)?
    /// The charge light's lit cap and its glow (round 26: lit while the
    /// iPhone charges, out once it is full, as on the handheld).
    private let chargeLight = Entity()
    private(set) var chargeLightOn = false
    private var chargeLightLevel: Float = 0
    private(set) var built = false
    private var lidAngle = 40.0

    init(finish: ShellFinish) { self.finish = finish }

    var view: ConsoleView { ConsoleView(yaw: yaw, tilt: tilt, zoom: zoom, pose: pose) }
    /// The rear of the console faces the player (the slot can be seen).
    var rearVisible: Bool {
        let y = (yaw.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return y > 90 && y < 270
    }
    /// What the card in the slot is called (the software's title).
    var insertedTitle: String? { cardInserted ? cardTitle : nil }
    /// The card in the slot, home or not.
    var titleInSlot: String? { card == nil ? nil : cardTitle }

    /// `--foldarc-stage-debug`: the printed faces are written to Documents/
    /// stage/ and the entity tree is logged after the build.
    #if DEBUG
    nonisolated static let debugDump = ProcessInfo.processInfo.arguments.contains("--foldarc-stage-debug")
    #else
    nonisolated static let debugDump = false
    #endif
    private static func dump(_ image: CGImage, name: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("stage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
    private func logTree(_ entity: Entity, depth: Int = 0) {
        let p = entity.position(relativeTo: nil)
        var line = String(repeating: "  ", count: depth) + (entity.name.isEmpty ? "-" : entity.name)
        if let model = entity as? ModelEntity, let mesh = model.model?.mesh {
            let b = mesh.bounds
            line += String(format: " mesh[%.3f %.3f %.3f → %.3f %.3f %.3f] materials=%d", b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z, model.model?.materials.count ?? 0)
        }
        line += String(format: " world(%.3f %.3f %.3f) enabled=%d", p.x, p.y, p.z, entity.isEnabled ? 1 : 0)
        NSLog("[stage] %@", line)
        for child in entity.children { logTree(child, depth: depth + 1) }
    }

    // MARK: Building

    func build(into content: inout RealityViewCameraContent) {
        guard !built else { return }
        built = true
        let started = Date()
        // Printing time of this build only (the total runs on across builds
        // and the warm-up).
        let printing = Self.printingTime
        content.camera = .virtual
        content.renderingEffects.antialiasing = .multisample4X
        camera.components.set(PerspectiveCameraComponent(near: 0.05, far: 100, fieldOfViewInDegrees: ConsoleModel.fieldOfView, fieldOfViewOrientation: .vertical))
        camera.position = [0, 0, 6]
        content.add(camera)

        let key = DirectionalLight()
        key.light.intensity = 2200
        key.light.color = .init(white: 1, alpha: 1)
        // The console stands 4–9 m from the camera; the shadow must reach it.
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 16, depthBias: 1.5)
        key.look(at: [0, 0, 0], from: -Self.keyLightDirection * 4.5, relativeTo: nil)
        content.add(key)
        let fill = DirectionalLight()
        fill.light.intensity = 700
        fill.light.color = .init(red: 0.86, green: 0.92, blue: 1, alpha: 1)
        fill.look(at: [0, 0, 0], from: [2.4, 1.0, 2.0], relativeTo: nil)
        content.add(fill)
        let rim = PointLight()
        rim.light.intensity = 8000
        rim.light.attenuationRadius = 12
        rim.position = [0.8, 1.6, -2.4]
        content.add(rim)
        // A studio around the console for the plastic to reflect: a soft
        // light from above, a bright band at the horizon, a dark floor. Drawn
        // here, never shown (no skybox), only mirrored in the surfaces.
        if let image = Self.studioImage(), let environment = try? EnvironmentResource(equirectangular: image, withName: nil) {
            // Round 29: the room is darker and the lights brighter by contrast;
            // the whole is lifted to light the plastic about as before.
            studio.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: Self.studioExponent))
            content.add(studio)
        }

        buildConsole()
        // The charger's cable, if the iPhone was on its charger before the
        // console was built (round 26).
        if chargerIn { buildCharger() }
        shownTopKey = nil; shownBottomKey = nil
        showHome(homeState)
        buildShadow(into: &content)
        content.add(root)
        if studio.components.has(ImageBasedLightComponent.self) {
            Self.receiveLight(root, from: studio)
        }
        // The shelf's cards (round 27), lit by the same studio, moved every frame.
        shelf.attach(to: camera, studio: studio.components.has(ImageBasedLightComponent.self) ? studio : nil)
        shelfSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated { self?.shelf.update(dt) }
        }
        applyPose(animated: false)
        NSLog("[stage] built in %.0f ms (printing %.0f ms)", Date().timeIntervalSince(started) * 1000, (Self.printingTime - printing) * 1000)
        if Self.debugDump {
            logTree(root)
            NSLog("[stage] camera (%.3f %.3f %.3f) view %@ stage %@", camera.position.x, camera.position.y, camera.position.z, String(describing: viewSize), String(describing: stageRect))
        }
    }

    /// The studio as an equirectangular picture. Round 29, after a product photographer's studio: round 24's was
    /// bright almost all round, so the gloss on the plastic came out as a
    /// wash and the console looked painted. Now the room is a dim grey and
    /// the lights are shapes the gloss can show: a large soft box overhead,
    /// a broad one in front of the console and one behind it, tall strips at
    /// either side, a warm bounce off the paper just below the horizon; and
    /// (b3) a lower, softer one straight in front, for the faces that look
    /// at the camera — the cards' labels and plastic — to carry a sheen. How
    /// the picture is wrapped round the scene, seen with b2's
    /// `--foldarc-studio-marks`: toward the camera (+z) is the picture's two
    /// ends, -x a quarter in, -z the middle, +x three quarters in. Never
    /// shown (no skybox), only mirrored in the surfaces and lighting them.
    private static func studioImage() -> CGImage? {
        let width = 1024, height = 512
        let W = CGFloat(width), H = CGFloat(height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let stops: [(CGFloat, CGColor)] = [
            (0.0, CGColor(red: 0.36, green: 0.36, blue: 0.37, alpha: 1)),
            (0.40, CGColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1)),
            (0.50, CGColor(red: 0.25, green: 0.245, blue: 0.24, alpha: 1)),
            (0.535, CGColor(red: 0.36, green: 0.33, blue: 0.29, alpha: 1)),
            (0.62, CGColor(red: 0.19, green: 0.18, blue: 0.165, alpha: 1)),
            (1.0, CGColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1))]
        guard let gradient = CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0)) else { return nil }
        // Row 0 of the picture is the top (the ceiling): drawn from y = H down.
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        /// A soft box: `u`, `v` its middle (0…1 across and down the
        /// picture), its size the same way, its edge softened over `soft`.
        func box(u: CGFloat, v: CGFloat, width w: CGFloat, height h: CGFloat, soft: CGFloat, level: CGFloat) {
            let rect = CGRect(x: (u - w / 2) * W, y: H - (v + h / 2) * H, width: w * W, height: h * H)
            let layers = 8
            for k in 0..<layers {
                let grow = soft * W * CGFloat(layers - k) / CGFloat(layers)
                let r = rect.insetBy(dx: -grow, dy: -grow)
                context.setFillColor(CGColor(red: level, green: level, blue: level * 0.985, alpha: 0.14))
                context.addPath(CGPath(roundedRect: r, cornerWidth: min(r.width, r.height) * 0.3, cornerHeight: min(r.width, r.height) * 0.3, transform: nil))
                context.fillPath()
            }
            context.setFillColor(CGColor(red: level, green: level, blue: level * 0.985, alpha: 1))
            context.fill(rect)
        }
        // Overhead: the whole top of the picture (the zenith's cap).
        box(u: 0.5, v: 0.05, width: 1.0, height: 0.10, soft: 0.02, level: 1.0)
        // In front and behind (the picture's middle and its two ends).
        for u in [CGFloat(0), 0.5, 1.0] {
            box(u: u, v: 0.31, width: 0.15, height: 0.15, soft: 0.022, level: 1.0)
        }
        // Tall strips at either side.
        for u in [CGFloat(0.25), 0.75] {
            box(u: u, v: 0.35, width: 0.036, height: 0.30, soft: 0.012, level: 0.92)
        }
        // Low and soft, straight toward the camera (both ends of the picture).
        for u in [CGFloat(0), 1.0] {
            box(u: u, v: 0.49, width: 0.12, height: 0.13, soft: 0.03, level: 0.62)
        }
        #if DEBUG
        // `--foldarc-studio-marks` (round 29): the four quarters of the
        // picture in four colours, top to bottom (red at its ends, green a
        // quarter in, blue in the middle, yellow three quarters in), to see in
        // a screenshot which way the picture is wrapped round the scene.
        if ProcessInfo.processInfo.arguments.contains("--foldarc-studio-marks") {
            let marks: [(CGFloat, CGColor)] = [(0, CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.9)), (0.25, CGColor(red: 0.1, green: 1, blue: 0.1, alpha: 0.9)),
                                               (0.5, CGColor(red: 0.15, green: 0.3, blue: 1, alpha: 0.9)), (0.75, CGColor(red: 1, green: 0.9, blue: 0.1, alpha: 0.9)),
                                               (1, CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.9))]
            for (u, color) in marks {
                context.setFillColor(color)
                context.fill(CGRect(x: (u - 0.1) * W, y: 0, width: 0.2 * W, height: H))
            }
            NSLog("[stage] debug: studio marks (red at the picture's ends, green 1/4, blue 1/2, yellow 3/4)")
        }
        #endif
        return context.makeImage()
    }
    /// How bright the studio lights the scene (round 24: 0.3 with the bright room).
    static let studioExponent: Float = 1.1
    private static func receiveLight(_ entity: Entity, from studio: Entity) {
        if entity is ModelEntity { entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: studio)) }
        for child in entity.children { receiveLight(child, from: studio) }
    }

    /// Builds a console once, out of sight (round 22), so its printed faces
    /// and meshes are in the shared caches and RealityKit's engine is up
    /// before the library first needs them. Called while the logo fades over
    /// the demo: Core Animation draws that fade, so the main thread can be
    /// busy meanwhile. Without it the first trip from the demo to the library
    /// did all of this under the white curtain (0.8-1.6 s, 10-30).
    static func warmUp(finish: ShellFinish) {
        let started = Date()
        let printing = printingTime
        ConsoleStage(finish: finish).buildConsole()
        // The card's solid (round 27): its meshes made once, here.
        _ = CardModel3D.meshes()
        NSLog("[stage] warmed up in %.0f ms (printing %.0f ms)", Date().timeIntervalSince(started) * 1000, (printingTime - printing) * 1000)
    }

    private func buildConsole() {
        let u = ConsoleModel.u
        // The pivot sits at the middle of the open console's footprint
        // (lid raised 40°: the footprint reaches 589 units behind the
        // lower half's centre and 220 in front).
        lowerHalf.position = [0, -ConsoleModel.lowerDepth / 2, 130 * u]
        root.addChild(lowerHalf)
        buildLowerHalf()
        buildHinge()
        buildLid()
    }

    // MARK: The stylus and the earphones (round 23)

    /// The stylus's end cap in the rear face, home (lower-half space).
    private static var stylusHome: SIMD3<Float> { [250 * ConsoleModel.u, 22 * ConsoleModel.u, 0] }
    /// How far it travels to come out of its hole: its whole length.
    private static let stylusTravel: Float = 300 * ConsoleModel.u
    /// The headphone jack's mouth in the front face (lower-half space).
    private static var jackPosition: SIMD3<Float> { [-200 * ConsoleModel.u, 32 * ConsoleModel.u, 220.5 * ConsoleModel.u] }

    /// The stylus: a slim body in its hole along the rear face's right side,
    /// the light end cap flush with the face. Only the cap shows while it is
    /// in; the body is inside the shell.
    private func buildStylus() {
        let u = ConsoleModel.u
        let along = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let cap = cylinder(radius: 9 * u, height: 8 * u, material: plastic(0.9, roughness: 0.4), name: "触控笔")
        cap.orientation = along
        cap.position = [0, 0, -223 * u]
        stylus.addChild(cap)
        let body = cylinder(radius: 5.5 * u, height: 262 * u, material: colored(UIColor(white: 0.78, alpha: 1), roughness: 0.3), name: "触控笔")
        body.orientation = along
        body.position = [0, 0, -219 * u + 131 * u]
        stylus.addChild(body)
        let tip = ModelEntity(mesh: .generateSphere(radius: 5.5 * u), materials: [plastic(0.22, roughness: 0.6)])
        tip.name = "触控笔"
        tip.scale = [1, 1, 1.6]
        tip.position = [0, 0, -219 * u + 262 * u]
        stylus.addChild(tip)
        stylus.name = "触控笔"
        stylus.position = Self.stylusHome
        lowerHalf.addChild(stylus)
        applyStylus(animated: false)
    }
    /// The stylus comes out of its hole (into the hand) or goes back in.
    func setStylus(out: Bool, animated: Bool) {
        guard out != stylusOut || !animated else { return }
        stylusOut = out
        applyStylus(animated: animated && built)
    }
    private func applyStylus(animated: Bool) {
        let home = Self.stylusHome
        let away = home + [0, 0, -Self.stylusTravel]
        stylus.stopAllAnimations()
        guard animated else {
            stylus.position = stylusOut ? away : home
            stylus.isEnabled = !stylusOut
            return
        }
        holdStill(for: 0.6)
        stylus.isEnabled = true
        if stylusOut {
            // Drawn out along its hole, then it is in the hand.
            stylus.position = home
            stylus.move(to: Transform(scale: stylus.scale, rotation: stylus.orientation, translation: away), relativeTo: lowerHalf, duration: 0.42, timingFunction: .easeIn)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, self.stylusOut else { return }
                self.stylus.isEnabled = false
            }
        } else {
            // From the hand, slid home until the cap is flush.
            stylus.position = away
            stylus.move(to: Transform(scale: stylus.scale, rotation: stylus.orientation, translation: home), relativeTo: lowerHalf, duration: 0.42, timingFunction: .easeOut)
        }
    }
    /// The stylus's hole on the screen (assistive access, the UI tests).
    func stylusPoint() -> CGPoint? {
        let u = ConsoleModel.u
        return project(lowerHalf.convert(position: Self.stylusHome + [0, 0, -223 * u], to: nil))
    }
    /// The jack on the screen (assistive access, the UI tests).
    func jackPoint() -> CGPoint? {
        project(lowerHalf.convert(position: Self.jackPosition, to: nil))
    }

    /// Headphones connected or not: the earphones in the jack, or nothing.
    func setEarphones(_ on: Bool) {
        earphonesIn = on
        // Before the console is built: remembered, built with it.
        guard lowerHalf.parent != nil else { return }
        if on && !earphonesBuilt {
            earphonesBuilt = true
            buildEarphones()
            if studio.components.has(ImageBasedLightComponent.self) { Self.receiveLight(earphones, from: studio) }
        }
        earphones.isEnabled = on
    }

    /// FoldArc's drawing of white wired earphones with an in-line remote:
    /// the plug's metal ring and white housing in the jack, the cable down
    /// onto the table and along the front of the console, the remote with
    /// its volume buttons, the split, and the two earbuds lying by the
    /// console's front-left corner. Shapes made here; no model file.
    private func buildEarphones() {
        let u = ConsoleModel.u
        var whiteMaterial = PhysicallyBasedMaterial()
        whiteMaterial.baseColor = .init(tint: UIColor(white: 0.97, alpha: 1))
        whiteMaterial.roughness = 0.3
        whiteMaterial.clearcoat = 0.7
        whiteMaterial.clearcoatRoughness = 0.1
        var metal = PhysicallyBasedMaterial()
        metal.baseColor = .init(tint: UIColor(white: 0.78, alpha: 1))
        metal.metallic = 1.0
        metal.roughness = 0.22
        let grille = plastic(0.32, roughness: 0.85)
        let along = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let jack = Self.jackPosition
        func part(_ entity: ModelEntity) { entity.name = "耳机"; earphones.addChild(entity) }
        // The plug, straight out of the jack.
        let ring = cylinder(radius: 6.5 * u, height: 4 * u, material: metal, name: "耳机")
        ring.orientation = along
        ring.position = jack + [0, 0, 2 * u]
        part(ring)
        let housing = cylinder(radius: 8.5 * u, height: 28 * u, material: whiteMaterial, name: "耳机")
        housing.orientation = along
        housing.position = jack + [0, 0, 18 * u]
        touchable(housing, size: [24 * u, 24 * u, 40 * u])
        part(housing)
        let rounded = ModelEntity(mesh: .generateSphere(radius: 8.5 * u), materials: [whiteMaterial])
        rounded.scale = [1, 1, 0.45]
        rounded.position = jack + [0, 0, 32 * u]
        part(rounded)
        let relief = cylinder(radius: 4.4 * u, height: 14 * u, material: whiteMaterial, name: "耳机")
        relief.orientation = along
        relief.position = jack + [0, 0, 40 * u]
        part(relief)
        // The cable: down onto the table, then along the front, leftwards.
        let table: Float = -2.6 * u + 2.2 * u
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { [x * u, y * u, z * u] }
        let toRemote: [SIMD3<Float>] = [
            jack + [0, 0, 46 * u], p(-200, 27, 271), p(-201, 18, 276), p(-204, 8, 276),
            [-208 * u, table, 271 * u], [-222 * u, table, 264 * u], [-242 * u, table, 259 * u], [-262 * u, table, 257 * u]]
        tube(toRemote, radius: 2.2 * u, material: whiteMaterial)
        // The remote: a slim white pill with + and − pressed into it.
        let remote = box([46 * u, 6.5 * u, 12 * u], corner: 3.2 * u, material: whiteMaterial, name: "耳机线控")
        remote.position = [-285 * u, -2.6 * u + 3.25 * u, 256 * u]
        remote.orientation = simd_quatf(angle: 0.06, axis: [0, 1, 0])
        touchable(remote, size: [50 * u, 12 * u, 18 * u])
        earphones.addChild(remote)
        for (x, plus) in [(Float(-11), true), (Float(11), false)] {
            let bar = box([6 * u, 0.8 * u, 1.3 * u], material: plastic(0.62, roughness: 0.6), name: "耳机线控")
            bar.position = [x * u, 3.4 * u, 0]
            remote.addChild(bar)
            if plus {
                let stem = box([1.3 * u, 0.8 * u, 6 * u], material: plastic(0.62, roughness: 0.6), name: "耳机线控")
                stem.position = [x * u, 3.4 * u, 0]
                remote.addChild(stem)
            }
        }
        let afterRemote: [SIMD3<Float>] = [[-308 * u, table, 254 * u], [-322 * u, table, 251 * u], [-336 * u, table, 249 * u]]
        tube(afterRemote, radius: 2.2 * u, material: whiteMaterial)
        // The split, then a cable to each earbud.
        let split = ModelEntity(mesh: .generateSphere(radius: 3.4 * u), materials: [whiteMaterial])
        split.scale = [1.3, 0.8, 1]
        split.position = [-338 * u, table + 0.6 * u, 249 * u]
        part(split)
        let leftCable: [SIMD3<Float>] = [[-338 * u, table, 249 * u], [-348 * u, table, 242 * u], [-356 * u, table, 235 * u], [-361 * u, table, 229 * u]]
        let rightCable: [SIMD3<Float>] = [[-338 * u, table, 249 * u], [-350 * u, table, 255 * u], [-360 * u, table, 263 * u], [-366 * u, table, 270 * u]]
        tube(leftCable, radius: 1.8 * u, material: whiteMaterial)
        tube(rightCable, radius: 1.8 * u, material: whiteMaterial)
        earbud(at: [-372 * u, 0, 222 * u], pointing: simd_normalize([0.6, 0, 0.8]), white: whiteMaterial, grille: grille)
        earbud(at: [-378 * u, 0, 278 * u], pointing: simd_normalize([0.75, 0, -0.66]), white: whiteMaterial, grille: grille)
    }
    /// One earbud lying on the table: the head, the stem toward its cable,
    /// the dark speaker openings.
    private func earbud(at base: SIMD3<Float>, pointing stemWay: SIMD3<Float>, white: PhysicallyBasedMaterial, grille: PhysicallyBasedMaterial) {
        let u = ConsoleModel.u
        let lying: Float = -2.6 * u
        let head = ModelEntity(mesh: .generateSphere(radius: 12 * u), materials: [white])
        head.name = "耳机"
        head.scale = [1, 0.72, 1]
        head.position = base + [0, lying + 8.6 * u, 0]
        touchable(head, size: [30 * u, 22 * u, 30 * u])
        earphones.addChild(head)
        let speaker = ModelEntity(mesh: .generateSphere(radius: 6 * u), materials: [grille])
        speaker.scale = [1, 0.35, 1]
        speaker.position = base + [0, lying + 16 * u, 0] - stemWay * (4 * u)
        earphones.addChild(speaker)
        let stemStart = base + stemWay * (8 * u) + [0, lying + 4.2 * u, 0]
        let stemEnd = stemStart + stemWay * (26 * u)
        tube([stemStart, stemEnd], radius: 4.2 * u, material: white)
        let end = ModelEntity(mesh: .generateSphere(radius: 4.2 * u), materials: [white])
        end.position = stemEnd
        earphones.addChild(end)
    }
    /// A round cable through `points`: a cylinder for each stretch, a ball at
    /// each bend so the turns are smooth.
    private func tube(_ points: [SIMD3<Float>], radius: Float, material: RealityKit.Material) {
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let length = simd_length(b - a)
            guard length > 0.00001 else { continue }
            let segment = ModelEntity(mesh: .generateCylinder(height: length, radius: radius), materials: [material])
            segment.name = "耳机线"
            segment.orientation = simd_quatf(from: [0, 1, 0], to: (b - a) / length)
            segment.position = (a + b) / 2
            earphones.addChild(segment)
            if index > 0 {
                let joint = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
                joint.position = a
                earphones.addChild(joint)
            }
        }
    }

    // MARK: The charging cable (round 26)

    // While the iPhone is on its charger the console has its charger's cable
    // in the port on its rear face, as a handheld charged at a desk does: a
    // plug (strain relief, body, metal tip), a dark cable down onto the table
    // behind it, round its right side and away to the front right. Plugged
    // in while the library is up, the cable comes along the table, drawn by
    // its plug, which then rises and goes into the port with a click, and
    // the charge light comes on; unplugged, the plug comes out and down onto
    // the table and the cable is drawn away. The cable is one mesh worked out
    // again in each frame of the move (LowLevelMesh, as the shadow), with its
    // own soft shadow on the table. FoldArc's own shapes: no model file, no
    // maker's plug or mark.

    /// Sizes in design units: the cable's radius; where the plug's strain
    /// relief meets the cable, seated in the port and lying on the table.
    private static let cableRadius: Float = 5.5
    private static let plugSeated: SIMD3<Float> = [60, 22, -292]
    private static let plugResting: SIMD3<Float> = [60, 8.4, -420]
    /// How much cable is drawn (design units): it reaches far out of sight.
    private static let cableLength: Float = 2600
    /// The cable's way (lower-half space, design units): from where the
    /// plug rests on the table behind the console, back, round the console's
    /// right side and away to its front right. The cable lies along it and
    /// comes and goes along it.
    private static let cableWay: [SIMD3<Float>] = {
        let y: Float = -2.6 + cableRadius
        return [[60, y, -438], [64, y, -478], [112, y, -532], [250, y, -556], [410, y, -505], [500, y, -372],
                [530, y, -170], [538, y, 60], [566, y, 262], [650, y, 452], [830, y, 742], [1120, y, 1180], [1560, y, 1880], [2100, y, 2760]]
    }()
    /// The way, sampled densely near the console and coarser far out, with
    /// the distance along it at each sample.
    private static let cableTrack: (points: [SIMD3<Float>], along: [Float]) = {
        let way = cableWay
        var points: [SIMD3<Float>] = []
        for i in 0..<(way.count - 1) {
            let p0 = way[max(0, i - 1)], p1 = way[i], p2 = way[i + 1], p3 = way[min(way.count - 1, i + 2)]
            let steps = max(2, Int((simd_length(p2 - p1) / (i < 8 ? 9 : 40)).rounded(.up)))
            for k in 0..<steps { points.append(catmullRom(p0, p1, p2, p3, Float(k) / Float(steps))) }
        }
        points.append(way[way.count - 1])
        var along: [Float] = [0]
        for i in 1..<points.count { along.append(along[i - 1] + simd_length(points[i] - points[i - 1])) }
        return (points, along)
    }()
    private static func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let t2 = t * t, t3 = t2 * t
        let a = 2 * p1
        let b = (p2 - p0) * t
        let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let d = (3 * p1 - p0 - 3 * p2 + p3) * t3
        return 0.5 * (a + b + c + d)
    }
    /// The point `s` units along the way (past its end: straight on).
    private static func trackPoint(_ s: Float) -> SIMD3<Float> {
        let (points, along) = cableTrack
        let n = points.count
        guard let last = along.last, n >= 2 else { return .zero }
        if s <= 0 { return points[0] }
        if s >= last { return points[n - 1] + simd_normalize(points[n - 1] - points[n - 2]) * (s - last) }
        var lo = 0, hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if along[mid] <= s { lo = mid } else { hi = mid }
        }
        let t = (s - along[lo]) / max(0.0001, along[hi] - along[lo])
        return points[lo] + (points[hi] - points[lo]) * t
    }
    /// Track samples from `s0` on, `length` long (the dense samples where
    /// they fall, the two ends exact).
    private static func trackLine(from s0: Float, length: Float) -> [SIMD3<Float>] {
        let (points, along) = cableTrack
        let s1 = s0 + length
        var out = [trackPoint(s0)]
        for (i, s) in along.enumerated() where s > s0 + 0.5 && s < s1 - 0.5 { out.append(points[i]) }
        if s1 > (along.last ?? 0) {
            // Past the way's end: a few more samples straight on.
            let start = max(s0, along.last ?? 0)
            var s = start + 60
            while s < s1 { out.append(trackPoint(s)); s += 60 }
        }
        out.append(trackPoint(s1))
        return out
    }

    /// The charger plugged in or not. Animated: it comes along the table and
    /// goes in, or comes out and is drawn away; else it is just there or not.
    func setCharger(_ plugged: Bool, animated: Bool) {
        chargerIn = plugged
        chargerTarget = plugged ? 2 : 0
        if !animated { chargerPhase = chargerTarget }
        // Before the console is built: remembered, built with it.
        guard lowerHalf.parent != nil else { return }
        if plugged && !chargerBuilt { buildCharger() }
    }
    /// The charge light on or off (fading).
    func setChargeLight(_ on: Bool, animated: Bool) {
        chargeLightOn = on
        if !animated {
            chargeLightLevel = on ? 1 : 0
            chargeLight.components.set(OpacityComponent(opacity: chargeLightLevel))
            chargeLight.isEnabled = on
        }
    }
    /// The charger's port on the screen (its callout, its marker).
    func chargerPortPoint() -> CGPoint? {
        let u = ConsoleModel.u
        return project(lowerHalf.convert(position: [60 * u, 22 * u, -222 * u], to: nil))
    }
    /// The charge light on the screen (its marker).
    func chargeLightPoint() -> CGPoint? {
        guard chargeLight.parent != nil else { return nil }
        return project(chargeLight.position(relativeTo: nil))
    }
    /// The charger's plug on the screen while it is in (a callout over it).
    func chargerPlugPoint() -> CGPoint? {
        guard chargerBuilt, charger.isEnabled else { return nil }
        let u = ConsoleModel.u
        return project(chargerPlug.convert(position: [0, 0, 40 * u], to: nil))
    }

    /// Where a point of the lower face's print (760 × 440, printed 748 ×
    /// 428 within the face's flat) lies on the lower half, `above` its bottom.
    private static func onLowerPrint(_ x: Double, _ y: Double, above: Float) -> SIMD3<Float> {
        let u = ConsoleModel.u
        return [Float(x - 380) * 748 / 760 * u, above, Float(y - 220) * 428 / 440 * u]
    }
    /// The same for the lid's inner print (its middle at z = -236 units).
    private static func onLidPrint(_ x: Double, _ y: Double, above: Float) -> SIMD3<Float> {
        let u = ConsoleModel.u
        return [Float(x - 380) * 748 / 760 * u, above, -236 * u + Float(y - 220) * 428 / 440 * u]
    }
    /// A hole's dark bore (a speaker's, the microphone's): no gloss.
    private static let boreMaterial: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.006, alpha: 1))
        m.roughness = 1.0
        m.metallic = 0.0
        m.specular = 0.1
        return m
    }()
    /// The power light (round 29, a solid where it was printed): a small
    /// lit cap in its window, left of the charge light's.
    private func buildPowerLight() {
        let u = ConsoleModel.u
        var lit = UnlitMaterial(color: UIColor(red: 0.42, green: 0.86, blue: 1.0, alpha: 1))
        lit.writesDepth = true
        let cap = raised(Path(roundedRect: CGRect(x: -2.3, y: -3.7, width: 4.6, height: 7.4), cornerRadius: 2.2), depth: 0.5 * u, material: lit, name: "指示灯：电源 · 充电")
        cap.position = Self.onLowerPrint(696, 435, above: ConsoleModel.lowerDepth + 0.75 * u)
        lowerHalf.addChild(cap)
        var glow = UnlitMaterial(applyPostProcessToneMap: false)
        glow.color = .init(tint: UIColor(red: 0.35, green: 0.80, blue: 1.0, alpha: 1))
        if let texture = Self.glowTexture {
            glow.blending = .transparent(opacity: .init(scale: 0.5, texture: .init(texture)))
        } else {
            glow.blending = .transparent(opacity: .init(floatLiteral: 0.2))
        }
        glow.writesDepth = false
        let halo = ModelEntity(mesh: .generatePlane(width: 22 * u, depth: 22 * u), materials: [glow])
        halo.position = Self.onLowerPrint(696, 435, above: ConsoleModel.lowerDepth + 1.45 * u)
        lowerHalf.addChild(halo)
    }
    /// The charge light over the printed one: a lit cap and a soft glow
    /// round it (the light's place on the print: 710, 435 of the 760 × 440
    /// face, printed 748 × 428).
    private func buildChargeLight() {
        let u = ConsoleModel.u
        let d = ConsoleModel.lowerDepth
        let at: SIMD3<Float> = [(710 - 380) * 748 / 760 * u, d + 0.75 * u, (435 - 220) * 428 / 440 * u]
        var lit = UnlitMaterial(color: UIColor(red: 1.0, green: 0.62, blue: 0.16, alpha: 1))
        lit.writesDepth = true
        let cap = raised(Path(roundedRect: CGRect(x: -2.5, y: -3.9, width: 5, height: 7.8), cornerRadius: 2.4), depth: 0.5 * u, material: lit)
        chargeLight.addChild(cap)
        var glow = UnlitMaterial(applyPostProcessToneMap: false)
        glow.color = .init(tint: UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 1))
        if let texture = Self.glowTexture {
            glow.blending = .transparent(opacity: .init(scale: 0.85, texture: .init(texture)))
        } else {
            glow.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        }
        glow.writesDepth = false
        let halo = ModelEntity(mesh: .generatePlane(width: 34 * u, depth: 34 * u), materials: [glow])
        halo.position = [0, 0.7 * u, 0]
        chargeLight.addChild(halo)
        chargeLight.position = at
        chargeLight.components.set(OpacityComponent(opacity: chargeLightLevel))
        chargeLight.isEnabled = chargeLightLevel > 0.001
        lowerHalf.addChild(chargeLight)
    }
    /// A round soft spot: full in the middle, nothing at the rim.
    private static let glowTexture: TextureResource? = {
        let w = 64
        var pixels = [UInt8](repeating: 0, count: w * w * 4)
        for y in 0..<w {
            for x in 0..<w {
                let dx = (Float(x) + 0.5) / Float(w) * 2 - 1, dy = (Float(y) + 0.5) / Float(w) * 2 - 1
                let r = min(1, (dx * dx + dy * dy).squareRoot())
                let a = r >= 1 ? 0 : pow(1 - r, 2.2) * 0.9 + (r < 0.18 ? 0.1 : 0)
                let v = UInt8(max(0, min(255, (a * 255).rounded())))
                let k = (y * w + x) * 4
                pixels[k] = v; pixels[k + 1] = v; pixels[k + 2] = v; pixels[k + 3] = v
            }
        }
        return texture(pixels, width: w, height: w)
    }()
    /// Across the cable's shadow: clear at both edges, deepest in the middle.
    private static let cableShadowTexture: TextureResource? = {
        let w = 64, h = 2
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let s = abs((Float(x) + 0.5) / Float(w) * 2 - 1)
                let a = pow(max(0, 1 - s), 1.6)
                let v = UInt8(max(0, min(255, (a * 255).rounded())))
                let k = (y * w + x) * 4
                pixels[k] = v; pixels[k + 1] = v; pixels[k + 2] = v; pixels[k + 3] = v
            }
        }
        return texture(pixels, width: w, height: h)
    }()
    private static func texture(_ pixels: [UInt8], width: Int, height: Int) -> TextureResource? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .raw))
    }

    /// The plug and the cable's two meshes (the cable, its shadow), made the
    /// first time the iPhone is on its charger.
    private func buildCharger() {
        guard !chargerBuilt else { return }
        let u = ConsoleModel.u
        chargerBuilt = true
        // The plug, in its own frame: +z toward its tip, the strain relief
        // from z 0 (where the cable meets it) to 28, the body to 72, the
        // metal tip to 94.
        var rubber = PhysicallyBasedMaterial()
        rubber.baseColor = .init(tint: UIColor(white: 0.11, alpha: 1))
        rubber.roughness = 0.5
        rubber.clearcoat = 0.25
        rubber.clearcoatRoughness = 0.3
        var body = PhysicallyBasedMaterial()
        body.baseColor = .init(tint: UIColor(white: 0.14, alpha: 1))
        body.roughness = 0.34
        body.clearcoat = 0.6
        body.clearcoatRoughness = 0.12
        let along = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        for (radius, z0, z1) in [(Float(7.2), Float(0), Float(12)), (Float(8.6), Float(12), Float(22)), (Float(10.2), Float(22), Float(28))] {
            let ring = cylinder(radius: radius * u, height: (z1 - z0) * u, material: rubber, name: "充电线")
            ring.orientation = along
            ring.position = [0, 0, (z0 + z1) / 2 * u]
            chargerPlug.addChild(ring)
        }
        let housing = box([60 * u, 22 * u, 44 * u], corner: 6 * u, material: body, name: "充电线")
        housing.position = [0, 0, 50 * u]
        touchable(housing, size: [66 * u, 28 * u, 50 * u])
        chargerPlug.addChild(housing)
        // Two grip lines across the top of the body.
        for z in [Float(40), 46] {
            let groove = box([46 * u, 0.8 * u, 1.6 * u], material: plastic(0.03, roughness: 0.9), name: "充电线")
            groove.position = [0, 11.1 * u, z * u]
            chargerPlug.addChild(groove)
        }
        let tip = box([46 * u, 10 * u, 22 * u], corner: 1.5 * u, material: metalMaterial, name: "充电线")
        tip.position = [0, 0, 83 * u]
        chargerPlug.addChild(tip)
        charger.addChild(chargerPlug)
        // The cable and its shadow, worked out in each frame of a move.
        func makeMesh(vertices: Int, indices: Int) -> LowLevelMesh? {
            var descriptor = LowLevelMesh.Descriptor()
            descriptor.vertexCapacity = vertices
            descriptor.indexCapacity = indices
            descriptor.indexType = .uint16
            descriptor.vertexAttributes = [
                LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: MemoryLayout<ShadowVertex>.offset(of: \.position) ?? 0),
                LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: MemoryLayout<ShadowVertex>.offset(of: \.normal) ?? 16),
                LowLevelMesh.Attribute(semantic: .uv0, format: .float2, offset: MemoryLayout<ShadowVertex>.offset(of: \.uv) ?? 32)]
            descriptor.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<ShadowVertex>.stride)]
            return try? LowLevelMesh(descriptor: descriptor)
        }
        if let mesh = makeMesh(vertices: Self.cableVertexCapacity, indices: Self.cableIndexCapacity),
           let shade = makeMesh(vertices: Self.cableShadowVertexCapacity, indices: Self.cableShadowIndexCapacity) {
            let y = -2.6 * u
            let seed = [ShadowVertex(position: [0, y, 0], normal: [0, 1, 0], uv: [0, 0]),
                        ShadowVertex(position: [u, y, 0], normal: [0, 1, 0], uv: [0, 0]),
                        ShadowVertex(position: [0, y, u], normal: [0, 1, 0], uv: [0, 0])]
            write(seed, [0, 1, 2], bounds: BoundingBox(min: [0, y - u, 0], max: [u, y + u, u]), into: mesh)
            write(seed, [0, 1, 2], bounds: BoundingBox(min: [0, y - u, 0], max: [u, y + u, u]), into: shade)
            if let resource = try? MeshResource(from: mesh), let shadeResource = try? MeshResource(from: shade) {
                chargerCable.model = ModelComponent(mesh: resource, materials: [rubber])
                chargerCable.name = "充电线"
                chargerShadow.model = ModelComponent(mesh: shadeResource, materials: [cableShadowMaterial()])
                chargerMesh = mesh
                chargerShadowMesh = shade
            }
        }
        charger.addChild(chargerCable)
        charger.addChild(chargerShadow)
        charger.isEnabled = false
        chargerShown = -1
        lowerHalf.addChild(charger)
        if studio.components.has(ImageBasedLightComponent.self) { Self.receiveLight(charger, from: studio) }
    }
    private static let cableVertexCapacity = 4096
    private static let cableIndexCapacity = 24_000
    private static let cableShadowVertexCapacity = 900
    private static let cableShadowIndexCapacity = 2700
    private static let cableSides = 10

    private func cableShadowMaterial() -> UnlitMaterial {
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: shadowTint)
        if let texture = Self.cableShadowTexture {
            m.blending = .transparent(opacity: .init(scale: shadowStrength * 0.95, texture: .init(texture)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: shadowStrength * 0.4))
        }
        m.writesDepth = false
        m.faceCulling = .none
        return m
    }

    /// Every frame (with the shadow): the charge light's fade and the cable's
    /// move, the cable worked out again while it moves or the console turns.
    private func stepCharger(_ dt: Float) {
        let step = min(0.1, max(0, dt))
        let lightTarget: Float = chargeLightOn ? 1 : 0
        if chargeLightLevel != lightTarget {
            chargeLightLevel = lightTarget > chargeLightLevel ? min(1, chargeLightLevel + step / 0.35) : max(0, chargeLightLevel - step / 0.55)
            chargeLight.components.set(OpacityComponent(opacity: chargeLightLevel * chargeLightLevel * (3 - 2 * chargeLightLevel)))
            let on = chargeLightLevel > 0.001
            if chargeLight.isEnabled != on { chargeLight.isEnabled = on }
        }
        guard chargerBuilt, chargerMesh != nil else { return }
        let before = chargerPhase
        if chargerPhase != chargerTarget {
            // The cable along the table: 0.85 s; the plug into the port or
            // out of it: 0.5 s.
            let up = chargerTarget > chargerPhase
            let plugPart = up ? chargerPhase >= 1 : chargerPhase > 1
            let rate: Float = plugPart ? 2.0 : 1.18
            var next = chargerPhase + (up ? 1 : -1) * step * rate
            // Each part ends at 1 first (the plug rests on the table a moment).
            if up, before < 1, next > 1 { next = 1 }
            if !up, before > 1, next < 1 { next = 1 }
            chargerPhase = up ? min(chargerTarget, next) : max(chargerTarget, next)
            if before < 2, chargerPhase >= 2 { chargerSeated?(true) }
            if before >= 2, chargerPhase < 2 { chargerSeated?(false) }
        }
        let visible = chargerPhase > 0.0005
        if charger.isEnabled != visible { charger.isEnabled = visible }
        guard visible else { chargerShown = -1; return }
        // The cable's shadow follows the light as the console turns.
        let light = root.orientation.inverse.act(Self.keyLightDirection)
        let key = chargerPhase * 1000 + light.x * 7 + light.y * 13 + light.z * 17 + shadowLevel * 3
        guard key != chargerShown else { return }
        chargerShown = key
        updateCharger(phase: chargerPhase, light: light)
    }

    /// The plug's place and the cable's centre line for `phase` (design units).
    private func chargerPose(_ phase: Float) -> (attach: SIMD3<Float>, pointing: SIMD3<Float>, line: [SIMD3<Float>]) {
        if phase <= 1 {
            // Along the table: the plug at the head of the cable, lying on
            // the table, nose first; it comes from far out of sight. The
            // plug's tail is 18 units ahead of where the cable meets the
            // track, at the height of the plug's axis.
            let e = 1 - pow(1 - min(1, max(0, phase)), 3)
            let s = (1 - e) * Self.cableLength
            let ahead = Self.trackPoint(max(0, s - 1)), here = Self.trackPoint(s)
            var pointing = s <= 0.001 ? SIMD3<Float>(0, 0, 1) : ahead - here
            pointing.y = 0
            pointing = simd_length(pointing) > 0.001 ? simd_normalize(pointing) : [0, 0, 1]
            let attach = SIMD3<Float>(here.x, Self.plugResting.y, here.z) + pointing * 18
            let middle = SIMD3<Float>((attach.x + here.x) / 2, (attach.y + here.y) / 2 - 1.2, (attach.z + here.z) / 2)
            var line: [SIMD3<Float>] = [attach, middle]
            line += Self.trackLine(from: s, length: Self.cableLength)
            return (attach, pointing, line)
        }
        // Into the port: lifted off the table, over and in, the last of it
        // straight along the port.
        let f = min(1, max(0, phase - 1))
        let e = f * f * (3 - 2 * f)
        let p0 = Self.plugResting, p3 = Self.plugSeated
        let p1: SIMD3<Float> = [60, 46, -404], p2: SIMD3<Float> = [60, 24, -326]
        let k = 1 - e
        let attach = k * k * k * p0 + 3 * k * k * e * p1 + 3 * k * e * e * p2 + e * e * e * p3
        let tangent = 3 * k * k * (p1 - p0) + 6 * k * e * (p2 - p1) + 3 * e * e * (p3 - p2)
        let swing = sin(.pi * e)
        var pointing = simd_normalize(SIMD3<Float>(0, 0, 1) * (1 - swing) + (simd_length(tangent) > 0.001 ? simd_normalize(tangent) : [0, 0, 1]) * swing)
        if pointing.z < 0.2 { pointing = simd_normalize(pointing + [0, 0, 0.5]) }
        // The lead: from the plug back and down to where the cable lies.
        let start = Self.trackPoint(0), towardEnd = simd_normalize(Self.trackPoint(8) - start)
        let reach = max(6, 0.42 * simd_length(attach - start))
        let c1 = attach - pointing * reach, c2 = start - towardEnd * reach
        var line: [SIMD3<Float>] = []
        let leadSteps = 14
        for i in 0...leadSteps {
            let t = Float(i) / Float(leadSteps), m = 1 - t
            line.append(m * m * m * attach + 3 * m * m * t * c1 + 3 * m * t * t * c2 + t * t * t * start)
        }
        line += Self.trackLine(from: 0, length: Self.cableLength).dropFirst()
        return (attach, pointing, line)
    }

    private func updateCharger(phase: Float, light: SIMD3<Float>) {
        guard let mesh = chargerMesh, let shade = chargerShadowMesh else { return }
        let u = ConsoleModel.u
        let pose = chargerPose(phase)
        // The plug.
        chargerPlug.position = pose.attach * u
        chargerPlug.orientation = simd_quatf(from: [0, 0, 1], to: pose.pointing)
        // The cable: a ring of sides round each point of its line, the
        // rings' frames carried along the line without twisting.
        let line = pose.line
        let sides = Self.cableSides
        let r = Self.cableRadius
        var vertices: [ShadowVertex] = []
        vertices.reserveCapacity(min(Self.cableVertexCapacity, line.count * (sides + 1)))
        var indices: [UInt16] = []
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var normal = SIMD3<Float>(0, 1, 0)
        var travelled: Float = 0
        let maxPoints = min(line.count, Self.cableVertexCapacity / (sides + 1))
        for i in 0..<maxPoints {
            let p = line[i]
            let a = line[max(0, i - 1)], b = line[min(line.count - 1, i + 1)]
            var tangent = b - a
            tangent = simd_length(tangent) > 0.0001 ? simd_normalize(tangent) : [0, 0, -1]
            // Parallel transport: the last normal, made square to this tangent.
            normal = normal - tangent * simd_dot(normal, tangent)
            if simd_length(normal) < 0.001 { normal = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]; normal = normal - tangent * simd_dot(normal, tangent) }
            normal = simd_normalize(normal)
            let binormal = simd_cross(tangent, normal)
            if i > 0 { travelled += simd_length(p - line[i - 1]) }
            for j in 0...sides {
                let angle = Float(j) / Float(sides) * 2 * .pi
                let radial = normal * cos(angle) + binormal * sin(angle)
                let position = (p + radial * r) * u
                vertices.append(ShadowVertex(position: position, normal: radial, uv: [Float(j) / Float(sides), travelled / 40]))
                low = pointwiseMin(low, position); high = pointwiseMax(high, position)
            }
            if i > 0 {
                let ring = sides + 1
                let base0 = UInt16((i - 1) * ring), base1 = UInt16(i * ring)
                for j in 0..<sides {
                    let a0 = base0 + UInt16(j), a1 = base0 + UInt16(j + 1)
                    let b0 = base1 + UInt16(j), b1 = base1 + UInt16(j + 1)
                    indices += [a0, b0, a1, a1, b0, b1]
                }
            }
        }
        if indices.count <= Self.cableIndexCapacity, !indices.isEmpty {
            write(vertices, indices, bounds: BoundingBox(min: low, max: high), into: mesh)
        }
        // Its shadow on the table: the line thrown along the light, a soft
        // band, wider and lighter where the cable is off the table.
        let tableY: Float = -2.6
        var shadeVertices: [ShadowVertex] = []
        var shadeIndices: [UInt16] = []
        var shadeLow = SIMD3<Float>(repeating: .greatestFiniteMagnitude), shadeHigh = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let down = max(0.2, -light.y)
        var thrown: [(SIMD2<Float>, Float)] = []
        for p in line.prefix(Self.cableShadowVertexCapacity / 2) {
            let t = max(0, (p.y - r * 0.6 - tableY) / down)
            let q = p + light * t
            thrown.append((SIMD2(q.x, q.z), p.y - tableY - r))
        }
        for i in 0..<thrown.count {
            let (q, height) = thrown[i]
            let a = thrown[max(0, i - 1)].0, b = thrown[min(thrown.count - 1, i + 1)].0
            var along2 = b - a
            along2 = simd_length(along2) > 0.0001 ? simd_normalize(along2) : [0, -1]
            let side = SIMD2<Float>(-along2.y, along2.x)
            let half = r * 1.35 + max(0, height) * 0.22
            let fade = max(0.25, 1 - max(0, height) / 60)
            for (k, sign) in [(Float(0), Float(-1)), (Float(1), Float(1))] {
                let v = q + side * (half * sign)
                let position = SIMD3<Float>(v.x, tableY + 0.25, v.y) * u
                shadeVertices.append(ShadowVertex(position: position, normal: [0, 1, 0], uv: [k, fade]))
                shadeLow = pointwiseMin(shadeLow, position); shadeHigh = pointwiseMax(shadeHigh, position)
            }
            if i > 0 {
                let base = UInt16((i - 1) * 2)
                shadeIndices += [base, base + 2, base + 1, base + 1, base + 2, base + 3]
            }
        }
        if !shadeIndices.isEmpty, shadeIndices.count <= Self.cableShadowIndexCapacity {
            write(shadeVertices, shadeIndices, bounds: BoundingBox(min: shadeLow, max: shadeHigh), into: shade)
        }
        let shadowShown = shadowLevel * shadowLevel * (3 - 2 * shadowLevel)
        chargerShadow.components.set(OpacityComponent(opacity: shadowShown))
        chargerShadow.isEnabled = shadowShown > 0.01
    }

    // MARK: The shadow on the table (round 24: part of the scene)

    /// The key light's direction (the way the light travels), in the world.
    private static let keyLightDirection = simd_normalize(SIMD3<Float>(2.6, -3.0, -1.4))
    /// The table the console stands on: the plane just under its feet, in
    /// the console's own frame (it tilts with the console).
    private static var tableY: Float { -ConsoleModel.lowerDepth / 2 - 2.6 * ConsoleModel.u }

    /// The console's shadow on its table, drawn by RealityKit with the
    /// console (round 24). Before, the library drew it in SwiftUI under the
    /// RealityView, 30 times a second while the console moved and a frame or
    /// two behind RealityKit's own frames: it trailed the console and went
    /// in jerks as it turned. Now it is a mesh lying
    /// on the table, worked out again in the very frame the console moves
    /// (SceneEvents.Update): the outline of the two halves thrown along the
    /// key light onto the table, filled, soft at its edge through an opacity
    /// ramp, softer and lighter where it was thrown from higher up (the
    /// lid's far edge) than at the feet. The console hides it where it
    /// stands on it.
    private let shadow = ModelEntity()
    private var shadowMesh: LowLevelMesh?
    private var shadowSubscription: EventSubscription?
    /// What the shadow was last worked out for (the console's turn, the lid's).
    private var shadowKey: [Float] = []
    /// Shown or not (the library shows it once the console stands on the
    /// paper, not while the console comes up to fill the screen for a
    /// game), and how far it has faded in.
    private var shadowTarget: Float = 0
    private var shadowLevel: Float = 0
    private var shadowFade: Float = 0.35
    private var shadowTint = UIColor(red: 0.27, green: 0.25, blue: 0.20, alpha: 1)
    private var shadowStrength: Float = 0.55
    /// Times the shadow was worked out (the frame meter's companion: a
    /// debug run logs it once the console has settled).
    private var shadowBuilds = 0

    private struct ShadowVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
    }
    private static let shadowVertexCapacity = 512
    private static let shadowIndexCapacity = 2400

    /// The shadow's colour and depth: a darker shade of the paper it falls
    /// on (on dark paper, deeper).
    func setShadow(tint: Color, strength: Float) {
        shadowTint = UIColor(tint)
        shadowStrength = strength
        if shadowMesh != nil, var model = shadow.model {
            model.materials = [shadowMaterial()]
            shadow.model = model
        }
    }
    /// Shows or hides the shadow, fading over `fade` seconds.
    func showShadow(_ on: Bool, fade: Double = 0.35) {
        shadowTarget = on ? 1 : 0
        shadowFade = Float(max(0.01, fade))
    }

    private func buildShadow(into content: inout RealityViewCameraContent) {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = Self.shadowVertexCapacity
        descriptor.indexCapacity = Self.shadowIndexCapacity
        descriptor.indexType = .uint16
        descriptor.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: MemoryLayout<ShadowVertex>.offset(of: \.position) ?? 0),
            LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: MemoryLayout<ShadowVertex>.offset(of: \.normal) ?? 16),
            LowLevelMesh.Attribute(semantic: .uv0, format: .float2, offset: MemoryLayout<ShadowVertex>.offset(of: \.uv) ?? 32)]
        descriptor.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<ShadowVertex>.stride)]
        do {
            let mesh = try LowLevelMesh(descriptor: descriptor)
            // A first, tiny triangle: the resource is made from a mesh that
            // has something in it.
            let u = ConsoleModel.u, y = Self.tableY
            write([ShadowVertex(position: [0, y, 0], normal: [0, 1, 0], uv: [0, 0]),
                   ShadowVertex(position: [u, y, 0], normal: [0, 1, 0], uv: [0, 0]),
                   ShadowVertex(position: [0, y, u], normal: [0, 1, 0], uv: [0, 0])],
                  [0, 1, 2], bounds: BoundingBox(min: [0, y - u, 0], max: [u, y + u, u]), into: mesh)
            let resource = try MeshResource(from: mesh)
            shadow.model = ModelComponent(mesh: resource, materials: [shadowMaterial()])
            shadowMesh = mesh
        } catch {
            NSLog("[stage] no shadow mesh: %@", "\(error)")
            return
        }
        shadow.components.set(OpacityComponent(opacity: 0))
        shadow.isEnabled = false
        shadowLevel = 0
        shadowKey = []
        root.addChild(shadow)
        shadowSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated {
                self?.stepShadow(dt)
                self?.stepCharger(dt)
            }
        }
    }

    private func shadowMaterial() -> UnlitMaterial {
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: shadowTint)
        if let ramp = Self.shadowRamp {
            m.blending = .transparent(opacity: .init(scale: shadowStrength, texture: .init(ramp)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: shadowStrength * 0.5))
        }
        m.writesDepth = false
        m.faceCulling = .none
        return m
    }

    /// The ramp the shadow's edge fades along: across, from inside the
    /// outline (opaque) to its rim (clear); down, from a shadow thrown from
    /// the feet to one thrown from a lid's height (lighter). The same value
    /// in every channel, whichever one the opacity reads. Its ends are
    /// repeated a few texels beyond where the mesh reaches: at a triangle's
    /// edge the GPU may sample a hair outside it, and a sampler that wraps
    /// then read the far end of the ramp (10-30: light specks along edges
    /// inside the shadow).
    private static let rampSize = (width: 72, height: 20, padX: 4, padY: 2)
    private static let shadowRamp: TextureResource? = {
        let (w, h, padX, padY) = rampSize
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let far = min(1, max(0, Float(y - padY) / Float(h - 2 * padY - 1)))
            for x in 0..<w {
                let s = min(1, max(0, Float(x - padX) / Float(w - 2 * padX - 1)))
                let edge = 1 - s * s * (3 - 2 * s)
                let a = pow(edge, 1.4) * (1 - 0.45 * far)
                let v = UInt8(max(0, min(255, (a * 255).rounded())))
                let k = (y * w + x) * 4
                pixels[k] = v; pixels[k + 1] = v; pixels[k + 2] = v; pixels[k + 3] = v
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: .raw))
    }()

    /// Every frame (SceneEvents.Update): the fade, and the outline again if
    /// the console or its lid has turned since the last one.
    private func stepShadow(_ dt: Float) {
        guard built, shadowMesh != nil else { return }
        let light = root.orientation.inverse.act(Self.keyLightDirection)
        // Seen from under the table the light comes from below it: no shadow.
        let fromAbove = min(1, max(0, (-light.y - 0.05) / 0.15))
        let target = shadowTarget * fromAbove
        if shadowLevel != target {
            let step = min(1, max(0, dt)) / shadowFade
            shadowLevel = shadowLevel < target ? min(target, shadowLevel + step) : max(target, shadowLevel - step)
            shadow.components.set(OpacityComponent(opacity: shadowLevel * shadowLevel * (3 - 2 * shadowLevel)))
        }
        let visible = shadowLevel > 0.002
        if shadow.isEnabled != visible { shadow.isEnabled = visible }
        guard visible, let lid = lidPivot.children.first else { return }
        let r = root.orientation.vector, l = lidPivot.orientation.vector
        let key = [r.x, r.y, r.z, r.w, l.x, l.y, l.z, l.w]
        guard key != shadowKey else { return }
        shadowKey = key
        updateShadowMesh(light: light, lid: lid)
    }

    private func updateShadowMesh(light: SIMD3<Float>, lid: Entity) {
        guard let mesh = shadowMesh else { return }
        let u = ConsoleModel.u
        let tableY = Self.tableY
        // The outline of each half from above (its rounded corners, top and
        // bottom), thrown onto the table: x, z there, and how far the light
        // carried it (how high above the table it is, in effect).
        var thrown: [SIMD3<Float>] = []
        thrown.reserveCapacity(96)
        let corner: Float = 42 * u
        func outline(_ entity: Entity, from z0: Float, to z1: Float, depth: Float) {
            for (cx, sx) in [(-380 * u + corner, Float(-1)), (380 * u - corner, Float(1))] {
                for (cz, sz) in [(z0 + corner, Float(-1)), (z1 - corner, Float(1))] {
                    for a in [Float(0), .pi / 4, .pi / 2] {
                        let x = cx + sx * corner * cos(a), z = cz + sz * corner * sin(a)
                        for y in [Float(0), depth] {
                            let p = entity.convert(position: [x, y, z], to: root)
                            let t = max(0, (p.y - tableY) / -light.y)
                            let q = p + light * t
                            thrown.append([q.x, q.z, t])
                        }
                    }
                }
            }
        }
        outline(lowerHalf, from: -220 * u, to: 220 * u, depth: ConsoleModel.lowerDepth)
        // The lid's body lies at z −456…−16 in its own space (buildLid).
        outline(lid, from: -456 * u, to: -16 * u, depth: ConsoleModel.lidDepth)
        guard let hull = Self.hull(thrown), hull.count >= 3 else {
            mesh.parts.removeAll()
            return
        }
        let n = hull.count
        var centre = SIMD2<Float>(0, 0)
        var meanT: Float = 0
        for p in hull { centre += SIMD2(p.x, p.y); meanT += p.z }
        centre /= Float(n); meanT /= Float(n)
        // 0 at the feet … 1 for a shadow thrown from a lid's height away.
        func far(_ t: Float) -> Float { min(1, t / (520 * u)) }
        // Texel centres of the ramp, inside its repeated ends.
        let (rw, rh, padX, padY) = Self.rampSize
        func ramp(_ across: Float, _ down: Float) -> SIMD2<Float> {
            [(Float(padX) + 0.5 + across * Float(rw - 2 * padX - 1)) / Float(rw),
             (Float(padY) + 0.5 + down * Float(rh - 2 * padY - 1)) / Float(rh)]
        }
        var vertices: [ShadowVertex] = []
        vertices.reserveCapacity(Self.shadowVertexCapacity)
        var indices: [UInt16] = []
        indices.reserveCapacity(Self.shadowIndexCapacity)
        var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude), high = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        func vertex(_ p: SIMD2<Float>, _ uv: SIMD2<Float>) -> UInt16 {
            vertices.append(ShadowVertex(position: [p.x, tableY, p.y], normal: [0, 1, 0], uv: uv))
            low = pointwiseMin(low, p); high = pointwiseMax(high, p)
            return UInt16(vertices.count - 1)
        }
        let middle = vertex(centre, ramp(0, far(meanT)))
        var inner: [UInt16] = []
        var arcs: [[UInt16]] = []
        for i in 0..<n {
            let v = SIMD2<Float>(hull[i].x, hull[i].y), t = hull[i].z, units = t / u
            // Contact hardening: sharp and dark at the feet, wide and light
            // far from them. (Round 29: wider, as under a studio's big soft
            // lights.)
            let inset = (7 + 0.05 * units) * u, reach = (18 + 0.19 * units) * u
            let toward = v - centre, length = simd_length(toward)
            let k = length > 0 ? max(0, length - inset) / length : 0
            inner.append(vertex(centre + toward * k, ramp(0, far(t))))
            let previous = SIMD2<Float>(hull[(i + n - 1) % n].x, hull[(i + n - 1) % n].y)
            let next = SIMD2<Float>(hull[(i + 1) % n].x, hull[(i + 1) % n].y)
            let d0 = v - previous, d1 = next - v
            // The outward normals of the two edges (the hull runs
            // anticlockwise in x, z), and the round corner between them.
            let a0 = atan2(-d0.x, d0.y)
            var sweep = atan2(-d1.x, d1.y) - a0
            while sweep < 0 { sweep += 2 * .pi }
            while sweep > 2 * .pi { sweep -= 2 * .pi }
            if sweep > .pi { sweep = 0 }
            let steps = max(1, min(6, Int((sweep / (.pi / 6)).rounded(.up))))
            var arc: [UInt16] = []
            for j in 0...steps {
                let a = a0 + sweep * Float(j) / Float(steps)
                arc.append(vertex(v + reach * SIMD2(cos(a), sin(a)), ramp(1, far(t))))
            }
            arcs.append(arc)
        }
        for i in 0..<n {
            let j = (i + 1) % n
            indices += [middle, inner[i], inner[j]]
            let arc = arcs[i]
            for k in 0..<(arc.count - 1) { indices += [inner[i], arc[k], arc[k + 1]] }
            indices += [inner[i], arc[arc.count - 1], arcs[j][0], inner[i], arcs[j][0], inner[j]]
        }
        guard vertices.count <= Self.shadowVertexCapacity, indices.count <= Self.shadowIndexCapacity else {
            NSLog("[stage] shadow outline too big: %d vertices, %d indices", vertices.count, indices.count)
            return
        }
        write(vertices, indices, bounds: BoundingBox(min: [low.x, tableY - u, low.y], max: [high.x, tableY + u, high.y]), into: mesh)
        shadowBuilds += 1
    }

    private func write(_ vertices: [ShadowVertex], _ indices: [UInt16], bounds: BoundingBox, into mesh: LowLevelMesh) {
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { target in
            vertices.withUnsafeBytes { source in target.copyMemory(from: source) }
        }
        mesh.withUnsafeMutableIndices { target in
            indices.withUnsafeBytes { source in target.copyMemory(from: source) }
        }
        mesh.parts.replaceAll([LowLevelMesh.Part(indexOffset: 0, indexCount: indices.count, topology: .triangle, materialIndex: 0, bounds: bounds)])
    }

    /// The convex hull (monotone chain) of points given as x, z on the
    /// table and a third value carried along; anticlockwise in x, z.
    private static func hull(_ input: [SIMD3<Float>]) -> [SIMD3<Float>]? {
        let pts = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard pts.count >= 3 else { return nil }
        func cross(_ o: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [SIMD3<Float>] = []
        for p in pts {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD3<Float>] = []
        for p in pts.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast(); upper.removeLast()
        let hull = lower + upper
        return hull.count >= 3 ? hull : nil
    }
    #if DEBUG
    /// How many times the shadow was worked out (logged by debug runs).
    var shadowBuildCount: Int { shadowBuilds }
    #endif

    /// The casing: its outer shells and the hinge. Round 31: a two-tone
    /// finish's inner shells (the faces' side) are its second colour
    /// (`innerShellMaterial`), as on the handheld in a game.
    private var shellMaterial: PhysicallyBasedMaterial { Self.plasticShell(finish) }
    private var innerShellMaterial: PhysicallyBasedMaterial { Self.plasticShell(finish.innerShell) }
    private static func plasticShell(_ finish: ShellFinish) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Self.uiColor(finish.base))
        m.roughness = finish.isLight ? 0.42 : 0.26
        m.metallic = 0.0
        m.clearcoat = finish.isLight ? 0.5 : 0.85
        m.clearcoatRoughness = 0.12
        return m
    }
    /// Glass over an LCD: nearly clear, glossy, so the studio shows in it.
    private var glassMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.05, alpha: 1))
        m.roughness = 0.04
        m.metallic = 0.0
        m.clearcoat = 1.0
        m.clearcoatRoughness = 0.05
        m.blending = .transparent(opacity: .init(floatLiteral: 0.14))
        return m
    }
    /// L and R: the shell's own colour, a shade deeper (round 24: black,
    /// they read from the front as blocks at the hinge's ends).
    private var shoulderMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Self.uiColor(finish.dark))
        m.roughness = 0.4
        m.clearcoat = 0.5
        return m
    }
    /// START, SELECT, HOME, POWER: on the face, the face's colour deeper.
    private var darkMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Self.uiColor(finish.innerShell.dark))
        m.roughness = 0.5
        return m
    }
    /// The Circle Pad's and the C Stick's cap: light grey, a soft rubbery
    /// sheen (round 24, as on the photographs and the drawn console).
    private var capMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.70, alpha: 1))
        m.roughness = 0.62
        m.clearcoat = 0.15
        return m
    }
    /// A key's cap: dark, glossy (ABXY, round 24).
    private var keyMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.12, alpha: 1))
        m.roughness = 0.32
        m.clearcoat = 0.7
        m.clearcoatRoughness = 0.1
        return m
    }
    /// Bright metal: the ring round the headphone jack and the lens.
    private var metalMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.78, alpha: 1))
        m.metallic = 1.0
        m.roughness = 0.28
        return m
    }
    /// Dark metal: the ring round the camera's lens.
    private var darkMetalMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.32, alpha: 1))
        m.metallic = 1.0
        m.roughness = 0.35
        return m
    }
    /// The black glass round a screen: its edge catches the light.
    private var bezelMaterial: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.03, alpha: 1))
        m.roughness = 0.12
        m.clearcoat = 1.0
        m.clearcoatRoughness = 0.04
        return m
    }
    private func plastic(_ white: CGFloat, roughness: Float = 0.6) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: white, alpha: 1))
        m.roughness = .init(floatLiteral: roughness)
        return m
    }
    private func colored(_ color: UIColor, roughness: Float = 0.5) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        return m
    }
    /// The moulded mark over the slot: the shell's own plastic, a shade
    /// apart so the relief reads; lit warm while a card is offered.
    /// The slot hint's two looks, made once (round 22: a new material each
    /// time it lit up or went out).
    private lazy var slotMarkLit = slotMarkMaterial(lit: true)
    private lazy var slotMarkUnlit = slotMarkMaterial(lit: false)
    /// Round 31: the parts in the finish's colours, changed in place by
    /// setFinish (the casing's outer shells and hinge, the inner shells, L
    /// and R, the small keys on the face, the four printed faces).
    private var outerParts: [ModelEntity] = []
    private var innerParts: [ModelEntity] = []
    private var shoulderParts: [ModelEntity] = []
    private var keyCapParts: [ModelEntity] = []
    enum PrintedFace { case lowerFace, bottom, lidInner, cover }
    private var printedFaces: [(entity: ModelEntity, face: PrintedFace)] = []
    private var reprint: Task<Void, Never>?
    /// A printed face for the finish: the faces (the lower one, the lid's
    /// inside) in its inner colour, the bottom and the lid's cover in its
    /// outer one.
    private func faceMaterial(_ face: PrintedFace) -> RealityKit.Material {
        let outer = finish, inner = finish.innerShell
        switch face {
        case .lowerFace: return Self.cached("face-\(inner.rawValue)") { Self.material(for: LowerFaceArt(finish: inner), unlit: false) }
        case .bottom: return Self.cached("bottom-\(outer.rawValue)") { Self.material(for: BottomArt(finish: outer), unlit: false) }
        case .lidInner: return Self.cached("lid-\(inner.rawValue)") { Self.material(for: LidInnerArt(finish: inner), unlit: false) }
        case .cover: return Self.cached("cover29-\(outer.rawValue)") { Self.material(for: LidCoverArt(finish: outer), unlit: false) }
        }
    }
    private func printedFace(_ face: PrintedFace, width: Float, depth: Float, corner: Float, name: String) -> ModelEntity {
        let entity = ModelEntity(mesh: Self.plane(width: width, depth: depth, corner: corner), materials: [faceMaterial(face)])
        entity.name = name
        printedFaces.append((entity, face))
        return entity
    }
    /// Round 31: another finish chosen with the console on the stage (主题 ›
    /// 机身配色): its plastic at once, its printed faces a moment later (a
    /// run of choices prints only the last).
    func setFinish(_ new: ShellFinish) {
        guard new != finish else { return }
        finish = new
        NSLog("[stage] finish %@", new.rawValue)
        let outer = shellMaterial, inner = innerShellMaterial, shoulder = shoulderMaterial, dark = darkMaterial
        for part in outerParts { part.model?.materials = [outer] }
        for part in innerParts { part.model?.materials = [inner] }
        for part in shoulderParts { part.model?.materials = [shoulder] }
        for part in keyCapParts { part.model?.materials = [dark] }
        slotMarkUnlit = slotMarkMaterial(lit: false)
        if !slotOpen { slotMark?.model?.materials = [slotMarkUnlit] }
        reprint?.cancel()
        reprint = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, self.finish == new else { return }
            let started = Date()
            for (entity, face) in self.printedFaces {
                guard !Task.isCancelled, self.finish == new else { return }
                entity.model?.materials = [self.faceMaterial(face)]
                await Task.yield()
            }
            NSLog("[stage] finish %@ printed in %.0f ms", new.rawValue, Date().timeIntervalSince(started) * 1000)
        }
    }
    private func slotMarkMaterial(lit: Bool) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if lit {
            m.baseColor = .init(tint: UIColor(red: 1.0, green: 0.62, blue: 0.30, alpha: 1))
            m.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.55, blue: 0.22, alpha: 1))
            m.emissiveIntensity = 2.4
            m.roughness = 0.5
        } else {
            m.baseColor = .init(tint: Self.uiColor(finish.isLight ? finish.dark : finish.light).withAlphaComponent(1))
            m.roughness = 0.55
            m.clearcoat = 0.3
        }
        m.metallic = 0.0
        return m
    }
    private static func uiColor(_ color: Color) -> UIColor { UIColor(color) }

    /// Which edges of a raised shape are rounded: both, or only the top's
    /// or only the bottom's (round 24: a shell rounded wide into its outer
    /// face and a little into its inner one, as on the real thing).
    enum RoundedEdges: String { case both, top, bottom }

    /// A flat shape raised off a face: the design path (points) extruded by
    /// `depth`, lying in the XZ plane with its underside at y = 0.
    private func raised(_ path: Path, depth: Float, chamfer: Float = 0, rounded: RoundedEdges = .both, material: RealityKit.Material, name: String = "") -> ModelEntity {
        let entity: ModelEntity
        if let mesh = Self.raisedMesh(path, depth: depth, chamfer: chamfer, rounded: rounded) {
            entity = ModelEntity(mesh: mesh, materials: [material])
            // The path lies in XY and is extruded along Z. Lay it flat: path
            // y → z (the drawing's down is toward the player), extrusion → up
            // (the mesh's far end, max z, at the bottom).
            let bounds = mesh.bounds
            entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            entity.position = [0, bounds.max.z, 0]
        } else {
            entity = ModelEntity(mesh: .generateBox(size: [0.01, depth, 0.01]), materials: [material])
        }
        entity.name = name
        let holder = ModelEntity()
        holder.name = name
        holder.addChild(entity)
        return holder
    }
    /// Raised shapes' meshes, made once (round 24): the console is built
    /// again each time the library comes back, and the warm-up at launch
    /// makes them all.
    private static var raisedMeshes: [String: MeshResource] = [:]
    /// Which end of an extrusion `.front` rounds (max z or min z), read
    /// from the first mesh made that way rather than assumed.
    private static var frontRoundsFarEnd: Bool?
    private static func raisedMesh(_ path: Path, depth: Float, chamfer: Float, rounded: RoundedEdges) -> MeshResource? {
        let key = "\(path.description)|\(depth)|\(chamfer)|\(rounded.rawValue)"
        if let mesh = raisedMeshes[key] { return mesh }
        let u = ConsoleModel.u
        let scaled = path.applying(CGAffineTransform(scaleX: CGFloat(u), y: CGFloat(u)))
        func make(_ mode: MeshResource.ShapeExtrusionOptions.ChamferMode, ends: Float) -> MeshResource? {
            var options = MeshResource.ShapeExtrusionOptions()
            // The chamfers add their radius to the depth (measured 10-29:
            // 64 + 2 × 7 units for the lower half): ask for the rest.
            options.extrusionMethod = .linear(depth: max(0.0005, depth - ends * chamfer))
            options.chamferRadius = chamfer
            options.chamferMode = mode
            options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 10)
            options.chamferResolution = .uniformSegmentsPerSpan(segmentCount: chamfer > 6 * u ? 8 : 4)
            return try? MeshResource(extruding: scaled, extrusionOptions: options)
        }
        let mesh: MeshResource?
        switch rounded {
        case .both:
            mesh = make(.both, ends: 2)
        case .top, .bottom:
            if frontRoundsFarEnd == nil, let probe = make(.front, ends: 1) {
                frontRoundsFarEnd = roundedEndIsFar(probe)
                NSLog("[stage] extrusion: .front rounds the %@ end", frontRoundsFarEnd == true ? "far (max z)" : "near (min z)")
            }
            // Laid flat (see `raised`) the far end is the bottom.
            let farWanted = rounded == .bottom
            mesh = make((frontRoundsFarEnd ?? true) == farWanted ? .front : .back, ends: 1)
        }
        if let mesh { raisedMeshes[key] = mesh }
        return mesh
    }
    /// The rounded end of a one-sided extrusion is the one whose outline is
    /// the smaller (the rounding draws it in).
    private static func roundedEndIsFar(_ mesh: MeshResource) -> Bool {
        var points: [SIMD3<Float>] = []
        for model in mesh.contents.models { for part in model.parts { points.append(contentsOf: part.positions.elements) } }
        guard let first = points.first else { return true }
        var near = first.z, far = first.z
        for p in points { near = min(near, p.z); far = max(far, p.z) }
        let slack = max(1e-6, (far - near) * 0.002)
        func width(at z: Float) -> Float {
            var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
            for p in points where abs(p.z - z) <= slack { low = min(low, p.x); high = max(high, p.x) }
            return high - low
        }
        return width(at: far) < width(at: near)
    }
    /// A circle and a ring in design points, centred on the origin.
    private static func circle(_ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    }
    private static func ring(outer: CGFloat, inner: CGFloat) -> Path {
        circle(outer).subtracting(circle(inner))
    }
    private func box(_ size: SIMD3<Float>, corner: Float = 0, material: RealityKit.Material, name: String = "") -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner), materials: [material])
        e.name = name
        return e
    }
    private func cylinder(radius: Float, height: Float, material: RealityKit.Material, name: String = "") -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material])
        e.name = name
        return e
    }
    /// A printed face: the drawing rendered to a texture on a plane lying in XZ.
    private func printed<V: View>(_ view: V, width: Float, depth: Float, corner: Float = 0, unlit: Bool = false, scale: CGFloat = 2.5, name: String = "", cacheKey: String? = nil) -> ModelEntity {
        let mesh = Self.plane(width: width, depth: depth, corner: corner)
        let material: RealityKit.Material
        if let cacheKey {
            material = Self.cached(cacheKey) { Self.material(for: view, unlit: unlit, scale: scale) }
        } else {
            material = Self.material(for: view, unlit: unlit, scale: scale)
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        return entity
    }
    /// Printed faces and menu pictures, kept across visits to the library
    /// (round 20: printing them took 150–650 ms each time the library came
    /// back, and a menu picture printed in the middle of an animation made
    /// it jump). The most recently used 40 stay.
    private static var materialCache: [String: RealityKit.Material] = [:]
    private static var materialOrder: [String] = []
    /// Plane meshes by size and the card's body, made once (round 20: made
    /// anew for each card that went in, with its label printed then too).
    private static var planes: [String: MeshResource] = [:]
    private static func plane(width: Float, depth: Float, corner: Float) -> MeshResource {
        let key = "\(width)|\(depth)|\(corner)"
        if let mesh = planes[key] { return mesh }
        let mesh = MeshResource.generatePlane(width: width, depth: depth, cornerRadius: corner)
        planes[key] = mesh
        return mesh
    }
    /// A card's label (and the back every card has) printed ahead, while
    /// the library is idle, so putting the card in does not hold up the
    /// frames to print it.
    func prepareCard(_ info: GameCardInfo) {
        // Round 27: the card is a solid (CardModel3D); its label printed here.
        CardModel3D.prepare(info)
    }
    private static func cached(_ key: String, make: () -> RealityKit.Material) -> RealityKit.Material {
        if let material = materialCache[key] {
            materialOrder.removeAll { $0 == key }
            materialOrder.append(key)
            return material
        }
        let material = make()
        materialCache[key] = material
        materialOrder.append(key)
        if materialOrder.count > 40 { materialCache.removeValue(forKey: materialOrder.removeFirst()) }
        return material
    }
    /// Time spent rendering the printed faces (logged with the build).
    private static var printingTime = 0.0
    private static func material<V: View>(for view: V, unlit: Bool, scale: CGFloat = 2.5) -> RealityKit.Material {
        let started = Date()
        defer { printingTime += Date().timeIntervalSince(started) }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else {
            NSLog("[stage] no image for %@", String(describing: V.self))
            return SimpleMaterial(color: .darkGray, isMetallic: false)
        }
        let texture: TextureResource
        do {
            texture = try TextureResource(image: image, withName: nil, options: .init(semantic: .color))
        } catch {
            NSLog("[stage] no texture for %@ (%dx%d): %@", String(describing: V.self), image.width, image.height, String(describing: error))
            return SimpleMaterial(color: .darkGray, isMetallic: false)
        }
        if debugDump { dump(image, name: String(describing: V.self)) }
        if unlit {
            var m = UnlitMaterial()
            m.color = .init(tint: .white, texture: .init(texture))
            return m
        }
        // A glossy clear coat over the print (round 24, as the photographs'
        // casings are): the studio's light runs across the faces. Round 29:
        // a full coat, a little sharper, over a satin print (the studio's
        // lights now show in it as shapes).
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(texture))
        m.roughness = 0.42
        m.metallic = 0.0
        m.clearcoat = 1.0
        m.clearcoatRoughness = 0.05
        return m
    }
    /// Part names for the callout: a box the finger can hit.
    private func touchable(_ entity: Entity, size: SIMD3<Float>, offset: SIMD3<Float> = .zero) {
        entity.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: size).offsetBy(translation: offset)]))
    }

    /// A half's casing as two shells (round 24, after photographs of the
    /// real thing): the outer one rounded wide into the outer face, the
    /// inner one only a little into the face with the controls, the parting
    /// line between them. (Before: one block, both edges rounded alike and
    /// tight, which read as a slab.)
    private func shells(depth d: Float, outerRound: Float, name: String) -> (body: ModelEntity, split: Float) {
        let u = ConsoleModel.u
        let outline = Path(roundedRect: CGRect(x: -380, y: -220, width: 760, height: 440), cornerRadius: 42)
        let split = (d * 0.46 / u).rounded() * u
        let body = raised(outline, depth: split, chamfer: outerRound, rounded: .bottom, material: shellMaterial, name: name)
        let inner = raised(outline, depth: d - split, chamfer: 7.5 * u, rounded: .top, material: innerShellMaterial, name: name)
        // (Round 31: the holder's first child is the solid.)
        if let solid = body.children.first as? ModelEntity { outerParts.append(solid) }
        if let solid = inner.children.first as? ModelEntity { innerParts.append(solid) }
        inner.position = [0, split, 0]
        body.addChild(inner)
        let seam = raised(Path(roundedRect: CGRect(x: -380.8, y: -220.8, width: 761.6, height: 441.6), cornerRadius: 42.8)
                            .subtracting(Path(roundedRect: CGRect(x: -378, y: -218, width: 756, height: 436), cornerRadius: 40)),
                          depth: 1.1 * u, material: plastic(0.03, roughness: 0.9))
        seam.position = [0, split - 0.55 * u, 0]
        body.addChild(seam)
        return (body, split)
    }

    private func buildLowerHalf() {
        let u = ConsoleModel.u
        let d = ConsoleModel.lowerDepth
        let (body, _) = shells(depth: d, outerRound: 17 * u, name: "机身下半")
        touchable(body, size: [760 * u, d, 440 * u], offset: [0, d / 2, 0])
        lowerHalf.addChild(body)
        // The face, printed; the bottom, printed.
        let face = printedFace(.lowerFace, width: 748 * u, depth: 428 * u, corner: 38 * u, name: "机身下半")
        face.position = [0, d + 0.3 * u, 0]
        lowerHalf.addChild(face)
        // Within the flat of the outer face (its edge is rounded 17 units in).
        let bottom = printedFace(.bottom, width: 722 * u, depth: 402 * u, corner: 26 * u, name: "底部")
        bottom.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        bottom.position = [0, -0.3 * u, 0]
        lowerHalf.addChild(bottom)
        // Lower LCD: the console's own menu (round 20), printed by showHome.
        let lcd = ModelEntity(mesh: .generatePlane(width: 400 * u, depth: 300 * u), materials: [UnlitMaterial(color: .black)])
        lcd.name = "触摸屏"
        lcd.position = ConsoleModel.lower(380, 198) + [0, d + 0.9 * u, 0]
        touchable(lcd, size: [400 * u, 2 * u, 300 * u])
        lowerHalf.addChild(lcd)
        lowerScreen = lcd
        let lowerGlass = ModelEntity(mesh: .generatePlane(width: 412 * u, depth: 312 * u, cornerRadius: 4 * u), materials: [glassMaterial])
        lowerGlass.name = "触摸屏"
        lowerGlass.position = ConsoleModel.lower(380, 198) + [0, d + 1.6 * u, 0]
        lowerHalf.addChild(lowerGlass)
        let lowerBezel = raised(Path(roundedRect: CGRect(x: -214, y: -164, width: 428, height: 328), cornerRadius: 8)
                                    .subtracting(Path(roundedRect: CGRect(x: -206, y: -156, width: 412, height: 312), cornerRadius: 4)),
                                depth: 2 * u, chamfer: 0.7 * u, material: bezelMaterial, name: "触摸屏")
        lowerBezel.position = ConsoleModel.lower(380, 198) + [0, d, 0]
        lowerHalf.addChild(lowerBezel)

        // Circle Pad (round 24, after photographs): a light cap, dished,
        // riding in a dark well under a raised ring. (Before: a black puck on
        // a black disc.)
        let padCentre = ConsoleModel.lower(91, 116)
        let padRing = raised(Self.ring(outer: 50, inner: 41.5), depth: 3 * u, chamfer: 1.2 * u, material: plastic(0.06, roughness: 0.4))
        padRing.position = padCentre + [0, d, 0]
        lowerHalf.addChild(padRing)
        let pad = raised(Self.circle(35), depth: 7 * u, chamfer: 2.6 * u, material: capMaterial, name: "滑动摇杆")
        pad.position = padCentre + [0, d + 1 * u, 0]
        touchable(pad, size: [100 * u, 20 * u, 100 * u], offset: [0, 4 * u, 0])
        let padDish = raised(Self.circle(25), depth: 0.6 * u, chamfer: 0.25 * u, material: plastic(0.58, roughness: 0.7), name: "滑动摇杆")
        padDish.position = [0, 7 * u - 0.42 * u, 0]
        pad.addChild(padDish)
        // Round 29: the grip on the cap, fine rings standing off the dish.
        for radius in [8.0, 13.5, 19.0] {
            let grip = raised(Self.ring(outer: radius + 0.9, inner: radius - 0.9), depth: 0.35 * u, chamfer: 0.12 * u, material: plastic(0.50, roughness: 0.8), name: "滑动摇杆")
            grip.position = [0, 7 * u + 0.12 * u, 0]
            pad.addChild(grip)
        }
        lowerHalf.addChild(pad)
        // D-pad: the cross in a cross-shaped well (round 24: no round disc
        // under it), its arms marked.
        let well = raised(CrossShape().path(in: CGRect(x: -53, y: -53, width: 106, height: 106)), depth: 0.8 * u, chamfer: 0.3 * u, material: plastic(0.02, roughness: 0.9))
        well.position = ConsoleModel.lower(91, 276) + [0, d + 0.05 * u, 0]
        lowerHalf.addChild(well)
        let cross = raised(CrossShape().path(in: CGRect(x: -48, y: -48, width: 96, height: 96)), depth: 9 * u, chamfer: 2.5 * u, material: plastic(0.18, roughness: 0.5), name: "十字键")
        cross.position = ConsoleModel.lower(91, 276) + [0, d + 0.8 * u, 0]
        touchable(cross, size: [96 * u, 12 * u, 96 * u], offset: [0, 5 * u, 0])
        // Round 29: the arms' marks moulded in the cross's own plastic, a
        // small raised arrow pointing out along each (they were white
        // bars, printed-looking), and a shallow dimple in the middle.
        var arrowMark = Path()
        arrowMark.move(to: CGPoint(x: 0, y: -5.5))
        arrowMark.addLine(to: CGPoint(x: 4.6, y: 2.2))
        arrowMark.addLine(to: CGPoint(x: -4.6, y: 2.2))
        arrowMark.closeSubpath()
        for (x, z, turn) in [(Float(0), Float(-32), 0.0), (0, 32, Double.pi), (-32, 0, -Double.pi / 2), (32, 0, Double.pi / 2)] {
            let mark = raised(arrowMark.applying(CGAffineTransform(rotationAngle: CGFloat(turn))), depth: 0.6 * u, chamfer: 0.25 * u, material: plastic(0.15, roughness: 0.42), name: "十字键")
            mark.position = [x * u, 9 * u - 0.1 * u, z * u]
            cross.addChild(mark)
        }
        let dimple = raised(Self.circle(9), depth: 0.35 * u, chamfer: 0.15 * u, material: plastic(0.12, roughness: 0.6), name: "十字键")
        dimple.position = [0, 9 * u - 0.2 * u, 0]
        cross.addChild(dimple)
        lowerHalf.addChild(cross)
        self.keys["十字键"] = (entity: cross as Entity, rest: cross.position)
        // C Stick: the small light nub in a dark ring.
        let stickRing = raised(Self.ring(outer: 18.5, inner: 13.5), depth: 1.6 * u, chamfer: 0.6 * u, material: plastic(0.06, roughness: 0.5))
        stickRing.position = ConsoleModel.lower(632, 76) + [0, d, 0]
        lowerHalf.addChild(stickRing)
        let stick = raised(Self.circle(12.5), depth: 7 * u, chamfer: 2.8 * u, material: capMaterial, name: "C 摇杆")
        stick.position = ConsoleModel.lower(632, 76) + [0, d + 0.4 * u, 0]
        touchable(stick, size: [34 * u, 12 * u, 34 * u], offset: [0, 3.5 * u, 0])
        lowerHalf.addChild(stick)
        // A B X Y: dark caps, their edges rounded (round 24: flat-topped
        // cylinders before), the letter in colour on top.
        let keys: [(String, Double, Double, Color)] = [
            ("X", 670, 187 - 44, RetroHardwareInk.blue), ("A", 670 + 44, 187, RetroHardwareInk.red),
            ("B", 670, 187 + 44, RetroHardwareInk.yellow), ("Y", 670 - 44, 187, RetroHardwareInk.green)]
        for (letter, x, y, color) in keys {
            let cap = raised(Self.circle(20), depth: 7 * u, chamfer: 2.6 * u, material: keyMaterial, name: "\(letter) 键")
            cap.position = ConsoleModel.lower(x, y) + [0, d + 0.4 * u, 0]
            touchable(cap, size: [41 * u, 12 * u, 41 * u], offset: [0, 3.5 * u, 0])
            lowerHalf.addChild(cap)
            let print = printed(KeyLetterArt(letter: letter, color: color), width: 30 * u, depth: 30 * u, corner: 15 * u, unlit: false, scale: 4, name: "\(letter) 键", cacheKey: "key-\(letter)")
            print.position = [0, 7 * u + 0.12 * u, 0]
            cap.addChild(print)
            self.keys["\(letter) 键"] = (entity: cap as Entity, rest: cap.position)
        }
        // START and SELECT: capsules standing a little proud.
        for (title, y) in [("START", 309.0), ("SELECT", 350.0)] {
            let cap = raised(Path(roundedRect: CGRect(x: -23, y: -7, width: 46, height: 14), cornerRadius: 7), depth: 4 * u, chamfer: 1.5 * u, material: darkMaterial, name: "\(title) 键")
            if let solid = cap.children.first as? ModelEntity { keyCapParts.append(solid) }
            cap.position = ConsoleModel.lower(669, y) + [0, d + 0.4 * u, 0]
            touchable(cap, size: [46 * u, 8 * u, 14 * u], offset: [0, 2 * u, 0])
            lowerHalf.addChild(cap)
            self.keys["\(title) 键"] = (entity: cap as Entity, rest: cap.position)
        }
        // HOME and POWER.
        let home = raised(Path(roundedRect: CGRect(x: -26.5, y: -11, width: 53, height: 22), cornerRadius: 11), depth: 3.5 * u, chamfer: 1.5 * u, material: darkMaterial, name: "HOME 键")
        if let solid = home.children.first as? ModelEntity { keyCapParts.append(solid) }
        home.position = ConsoleModel.lower(380, 388) + [0, d + 0.4 * u, 0]
        touchable(home, size: [53 * u, 8 * u, 22 * u], offset: [0, 2 * u, 0])
        lowerHalf.addChild(home)
        self.keys["HOME 键"] = (entity: home as Entity, rest: home.position)
        let power = raised(Path(roundedRect: CGRect(x: -17, y: -8.5, width: 34, height: 17), cornerRadius: 8.5), depth: 3 * u, chamfer: 1.2 * u, material: darkMaterial, name: "电源键")
        if let solid = power.children.first as? ModelEntity { keyCapParts.append(solid) }
        power.position = ConsoleModel.lower(691, 419) + [0, d + 0.4 * u, 0]
        touchable(power, size: [34 * u, 8 * u, 17 * u], offset: [0, 2 * u, 0])
        lowerHalf.addChild(power)
        self.keys["电源键"] = (entity: power as Entity, rest: power.position)
        // Parts that are print only: a box to name them.
        for (name, x, y, w, h) in [("麦克风", 480.0, 391.0, 20.0, 20.0), ("指示灯：电源 · 充电", 703.0, 435.0, 30.0, 12.0), ("ZERO 铭牌", 83.0, 406.0, 70.0, 14.0)] {
            let marker = Entity(); marker.name = name
            marker.position = ConsoleModel.lower(x, y) + [0, d, 0]
            touchable(marker, size: [Float(w) * u, 4 * u, Float(h) * u])
            lowerHalf.addChild(marker)
        }
        // Round 29: the microphone's hole a matte black bore over its print
        // (the gloss over the print no longer runs across it), and the power
        // light lit beside the charge light's window.
        let mic = cylinder(radius: 2.6 * u, height: 0.4 * u, material: Self.boreMaterial, name: "麦克风")
        mic.position = Self.onLowerPrint(480, 391, above: d + 0.5 * u)
        lowerHalf.addChild(mic)
        buildPowerLight()
        // Shoulder keys on the rear edge, L and R, under the ends of the
        // hinge (round 24: they stood up over it and read from the front as
        // two black blocks at its ends).
        for (name, x) in [("L 肩键", -300.0), ("R 肩键", 300.0)] {
            let key = box([116 * u, 12 * u, 20 * u], corner: 5 * u, material: shoulderMaterial, name: name)
            shoulderParts.append(key)
            key.position = [Float(x) * u, d - 1 * u, -224 * u]
            touchable(key, size: [116 * u, 18 * u, 26 * u])
            lowerHalf.addChild(key)
            // Pressed when tapped (round 25: L and R open the camera).
            self.keys[name] = (entity: key as Entity, rest: key.position)
        }
        // Rear face: the card slot (open, as on the handheld: dark when no
        // card is in; round 21 took out the door, whose shell-coloured face
        // read as a card in the slot), the stylus, the charging port.
        let slotBack = box([ConsoleModel.slotWidth, ConsoleModel.slotHeight, 2 * u], material: plastic(0.02, roughness: 1), name: "卡槽")
        slotBack.position = [ConsoleModel.slotX, ConsoleModel.slotY, -219.5 * u]
        touchable(slotBack, size: [ConsoleModel.slotWidth + 10 * u, ConsoleModel.slotHeight + 10 * u, 8 * u])
        lowerHalf.addChild(slotBack)
        // A raised shape turned onto the rear face stands off it toward +z
        // (into the body): it is set back by its own depth to sit proud.
        let slotRim = raised(Path(roundedRect: CGRect(x: -106, y: -16, width: 212, height: 32), cornerRadius: 6).subtracting(Path(roundedRect: CGRect(x: -100, y: -13, width: 200, height: 26), cornerRadius: 4)), depth: 1.6 * u, material: plastic(0.07, roughness: 0.8), name: "卡槽")
        slotRim.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        slotRim.position = [ConsoleModel.slotX, ConsoleModel.slotY, -221.6 * u]
        lowerHalf.addChild(slotRim)
        // The mark beside the slot: a plain triangle moulded into the shell,
        // pointing at the slot, the kind of mark pressed into a handheld's
        // casing (round 19; FoldArc's own). It lights up while a card is
        // offered. (The hinge overhangs the face above the slot, so the mark
        // stands beside it.) Path x is the face's x; the apex points +x.
        var arrow = Path()
        arrow.move(to: CGPoint(x: 0, y: -9))
        arrow.addLine(to: CGPoint(x: 0, y: 9))
        arrow.addLine(to: CGPoint(x: 17, y: 0))
        arrow.closeSubpath()
        let mark = raised(arrow, depth: 1.6 * u, material: slotMarkMaterial(lit: false), name: "卡槽")
        mark.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        mark.position = [ConsoleModel.slotX - ConsoleModel.slotWidth / 2 - 30 * u, ConsoleModel.slotY, -221.6 * u]
        lowerHalf.addChild(mark)
        slotMark = mark.children.first as? ModelEntity
        doorPivot.position = [ConsoleModel.slotX, ConsoleModel.slotY + ConsoleModel.slotHeight / 2, -221 * u]
        lowerHalf.addChild(doorPivot)
        slotMouth.position = [ConsoleModel.slotX, ConsoleModel.slotY, -232 * u]
        lowerHalf.addChild(slotMouth)
        let stylusHole = cylinder(radius: 12 * u, height: 3 * u, material: plastic(0.02, roughness: 1), name: "触控笔")
        stylusHole.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        stylusHole.position = [250 * u, 22 * u, -220.5 * u]
        touchable(stylusHole, size: [30 * u, 30 * u, 10 * u])
        lowerHalf.addChild(stylusHole)
        buildStylus()
        let port = box([60 * u, 16 * u, 3 * u], corner: 3 * u, material: plastic(0.02, roughness: 1), name: "充电口")
        port.position = [60 * u, 22 * u, -220 * u]
        touchable(port, size: [66 * u, 22 * u, 10 * u])
        lowerHalf.addChild(port)
        // Front edge: headphone jack and the LED window. Right edge: the
        // wireless switch. (The volume slider is on the lid, beside the upper
        // screen, as on the drawn console: round 20.)
        let jack = cylinder(radius: 8.2 * u, height: 3 * u, material: plastic(0.02, roughness: 1), name: "耳机孔")
        jack.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        jack.position = Self.jackPosition
        touchable(jack, size: [34 * u, 34 * u, 10 * u])
        lowerHalf.addChild(jack)
        // Its bright ring (round 24), standing a hair off the front face.
        let jackRing = raised(Self.ring(outer: 11, inner: 8.2), depth: 0.8 * u, chamfer: 0.3 * u, material: metalMaterial, name: "耳机孔")
        jackRing.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        jackRing.position = [Self.jackPosition.x, Self.jackPosition.y, 220 * u]
        lowerHalf.addChild(jackRing)
        earphones.isEnabled = false
        lowerHalf.addChild(earphones)
        if earphonesIn { setEarphones(true) }
        let wireless = box([8 * u, 8 * u, 36 * u], corner: 3 * u, material: plastic(0.18, roughness: 0.6), name: "无线开关")
        wireless.position = [380 * u, 32 * u, -70 * u]
        touchable(wireless, size: [16 * u, 24 * u, 50 * u])
        lowerHalf.addChild(wireless)
        // Rubber feet.
        for (x, z) in [(-320.0, -170.0), (320.0, -170.0), (-320.0, 170.0), (320.0, 170.0)] {
            let foot = cylinder(radius: 11 * u, height: 2.5 * u, material: plastic(0.12, roughness: 0.95))
            foot.position = [Float(x) * u, -1.2 * u, Float(z) * u]
            lowerHalf.addChild(foot)
        }
        // The charge light, lit over its print while the iPhone charges (round 26).
        buildChargeLight()
    }

    /// The hinge (round 24, after photographs): the lid's barrel between
    /// two knuckles of the lower half, a little fuller than it, their outer
    /// ends rounded off. (Before: one barrel the whole width, cut in five.)
    private func buildHinge() {
        let u = ConsoleModel.u
        let r = ConsoleModel.hingeRadius
        let along = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        let barrel = cylinder(radius: r, height: 596 * u, material: shellMaterial, name: "铰链")
        outerParts.append(barrel)
        barrel.orientation = along
        barrel.position = [0, ConsoleModel.hingeY, ConsoleModel.hingeZ]
        touchable(barrel, size: [742 * u, 2 * r, 2 * r])
        lowerHalf.addChild(barrel)
        for side in [Float(-1), 1] {
            // The gap between barrel and knuckle.
            let gap = cylinder(radius: r - 1.5 * u, height: 3 * u, material: plastic(0.03, roughness: 0.9))
            gap.orientation = along
            gap.position = [side * 299.5 * u, ConsoleModel.hingeY, ConsoleModel.hingeZ]
            lowerHalf.addChild(gap)
            let knuckle = cylinder(radius: r + 1.6 * u, height: 62 * u, material: shellMaterial, name: "铰链")
            outerParts.append(knuckle)
            knuckle.orientation = along
            knuckle.position = [side * 332 * u, ConsoleModel.hingeY, ConsoleModel.hingeZ]
            lowerHalf.addChild(knuckle)
            // The rounded end: a sphere pressed flat against it.
            let end = ModelEntity(mesh: .generateSphere(radius: r + 1.6 * u), materials: [shellMaterial])
            outerParts.append(end)
            end.name = "铰链"
            end.scale = [0.36, 1, 1]
            end.position = [side * 363 * u, ConsoleModel.hingeY, ConsoleModel.hingeZ]
            lowerHalf.addChild(end)
        }
    }

    private func buildLid() {
        let u = ConsoleModel.u
        let d = ConsoleModel.lidDepth
        lidPivot.position = [0, ConsoleModel.hingeY, ConsoleModel.hingeZ]
        lowerHalf.addChild(lidPivot)
        let lid = Entity()
        // Flat open, the lid lies behind the hinge at the lower half's
        // height; its children use ConsoleModel.lid() (hinge side at z = -16).
        lid.position = [0, ConsoleModel.lowerDepth + 2 * u - ConsoleModel.hingeY - d, 0]
        lidPivot.addChild(lid)
        let (body, _) = shells(depth: d, outerRound: 15 * u, name: "上盖")
        body.position = [0, 0, -236 * u]
        touchable(body, size: [760 * u, d, 440 * u], offset: [0, d / 2, 0])
        lid.addChild(body)
        let inner = printedFace(.lidInner, width: 748 * u, depth: 428 * u, corner: 38 * u, name: "上盖内侧")
        inner.position = [0, d + 0.3 * u, -236 * u]
        lid.addChild(inner)
        // Within the flat of the outer face (its edge is rounded 15 units in).
        // Round 29: the lid as moulded, not the closed console's lit drawing.
        let cover = printedFace(.cover, width: 726 * u, depth: 406 * u, corner: 28 * u, name: "外盖")
        cover.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        cover.position = [0, -0.3 * u, -236 * u]
        lid.addChild(cover)
        // Upper LCD, emissive.
        let lcd = ModelEntity(mesh: .generatePlane(width: 500 * u, depth: 300 * u), materials: [UnlitMaterial(color: .black)])
        lcd.name = "上屏"
        lcd.position = ConsoleModel.lid(380, 226) + [0, d + 0.9 * u, 0]
        touchable(lcd, size: [500 * u, 2 * u, 300 * u])
        lid.addChild(lcd)
        upperScreen = lcd
        let upperGlass = ModelEntity(mesh: .generatePlane(width: 512 * u, depth: 312 * u, cornerRadius: 4 * u), materials: [glassMaterial])
        upperGlass.name = "上屏"
        upperGlass.position = ConsoleModel.lid(380, 226) + [0, d + 1.6 * u, 0]
        lid.addChild(upperGlass)
        // The black glass's edge round the screen, standing a hair proud of
        // the face so that it catches the light (round 24).
        let upperBezel = raised(Path(roundedRect: CGRect(x: -264, y: -164, width: 528, height: 328), cornerRadius: 8)
                                    .subtracting(Path(roundedRect: CGRect(x: -256, y: -156, width: 512, height: 312), cornerRadius: 4)),
                                depth: 2 * u, chamfer: 0.7 * u, material: bezelMaterial, name: "上屏")
        upperBezel.position = ConsoleModel.lid(380, 226) + [0, d, 0]
        lid.addChild(upperBezel)
        // Camera: the lens in a bright ring, between the LCD and the hinge
        // side's far edge, the light sensor beside it.
        let lensRing = raised(Self.ring(outer: 8, inner: 5.2), depth: 1.1 * u, chamfer: 0.4 * u, material: darkMetalMaterial, name: "内侧相机")
        lensRing.position = ConsoleModel.lid(380, 27) + [0, d, 0]
        lid.addChild(lensRing)
        let lens = raised(Self.circle(5.4), depth: 0.7 * u, chamfer: 0.25 * u, material: bezelMaterial, name: "内侧相机")
        lens.position = ConsoleModel.lid(380, 27) + [0, d, 0]
        touchable(lens, size: [30 * u, 6 * u, 30 * u])
        lid.addChild(lens)
        // 3D depth slider: the knob rides on the track printed on the face.
        let knob = box([13 * u, 5 * u, 19 * u], corner: 2 * u, material: plastic(0.36, roughness: 0.5), name: "3D 景深滑块")
        knob.position = ConsoleModel.lid(706, Self.depthKnobY(Stereo3D.storedSlider)) + [0, d + 2.5 * u, 0]
        touchable(knob, size: [24 * u, 10 * u, 26 * u])
        lid.addChild(knob)
        depthKnob = knob
        // Round 30: the knob is dragged along its track like the volume's.
        let depthTrack = Entity(); depthTrack.name = "3D 景深滑块"
        depthTrack.position = ConsoleModel.lid(706, 313) + [0, d, 0]
        touchable(depthTrack, size: [24 * u, 4 * u, 80 * u])
        lid.addChild(depthTrack)
        // The volume slider on the other side (round 20): its knob stands
        // where the volume is set, up is louder.
        let volume = box([13 * u, 5 * u, 19 * u], corner: 2 * u, material: plastic(0.36, roughness: 0.5), name: "音量滑块")
        volume.position = ConsoleModel.lid(54, Self.volumeKnobY(ConsoleVolume.shared.level)) + [0, d + 2.5 * u, 0]
        touchable(volume, size: [24 * u, 10 * u, 26 * u])
        lid.addChild(volume)
        volumeKnob = volume
        let volumeTrack = Entity(); volumeTrack.name = "音量滑块"
        volumeTrack.position = ConsoleModel.lid(54, 313) + [0, d, 0]
        touchable(volumeTrack, size: [24 * u, 4 * u, 80 * u])
        lid.addChild(volumeTrack)
        for (name, x, y, w, h) in [("扬声器", 74.0, 211.0, 34.0, 56.0), ("扬声器", 686.0, 211.0, 34.0, 56.0)] {
            let marker = Entity(); marker.name = name
            marker.position = ConsoleModel.lid(x, y) + [0, d, 0]
            touchable(marker, size: [Float(w) * u, 4 * u, Float(h) * u])
            lid.addChild(marker)
            // Round 29: each hole a matte black bore over its print, where
            // the print is (it is printed a little smaller than the face).
            for hole in SpeakerHoles.holes {
                let bore = cylinder(radius: 3.6 * u, height: 0.4 * u, material: Self.boreMaterial, name: name)
                bore.position = Self.onLidPrint(x + hole.0, y + hole.1, above: d + 0.5 * u)
                lid.addChild(bore)
            }
        }
        // Rubber stand-offs on the lid face (round 24, after photographs):
        // round ones along the far edge, square ones by the hinge.
        for (x, y, round) in [(46.0, 34.0, true), (714.0, 34.0, true), (40.0, 410.0, false), (720.0, 410.0, false)] {
            let shape = round ? Self.circle(6.5) : Path(roundedRect: CGRect(x: -6.5, y: -6.5, width: 13, height: 13), cornerRadius: 2.5)
            let bumper = raised(shape, depth: 2.2 * u, chamfer: 0.9 * u, material: plastic(0.10, roughness: 0.95))
            bumper.position = ConsoleModel.lid(x, y) + [0, d, 0]
            lid.addChild(bumper)
        }
        // Cover cameras, print only: name them.
        for x in [0.39, 0.61] {
            let marker = Entity(); marker.name = "外侧相机"
            marker.position = ConsoleModel.lid(760 * x, 440 - 19) + [0, 0, 0]
            touchable(marker, size: [16 * u, 4 * u, 16 * u])
            lid.addChild(marker)
        }
        lidPivot.orientation = simd_quatf(angle: Float(lidAngle * .pi / 180), axis: [1, 0, 0])
    }

    // MARK: Pictures on the screens

    /// Redraws both LCDs for the card in the console (nil: the idle picture).
    /// The console's own menu in its two LCDs (round 20). Each screen is
    /// printed only when what it shows changed, and from the cache when it
    /// was printed before (see `prepareHome`).
    func showHome(_ state: ConsoleHomeState) {
        homeState = state
        guard built else { return }
        // Round 32: the software's last frames are on the LCDs while the
        // console comes down from a game; the menu takes over after.
        if holdingPictures { return }
        let top = "T" + state.topKey, bottom = "B" + state.bottomKey
        // A picture that has not been printed yet waits while the console or
        // a card moves; the screens keep what they show until then (round 21:
        // printed as a card slid in, it held the frames up 20-140 ms).
        let unprinted = (top != shownTopKey && Self.materialCache[top] == nil) || (bottom != shownBottomKey && Self.materialCache[bottom] == nil)
        if unprinted && busy {
            showHomeWhenStill()
            return
        }
        if top != shownTopKey {
            upperScreen?.model?.materials = [Self.cached(top) { Self.material(for: ConsoleHomeTopArt(state: state), unlit: true, scale: 2) }]
            shownTopKey = top
        }
        if bottom != shownBottomKey {
            lowerScreen?.model?.materials = [Self.cached(bottom) { Self.material(for: ConsoleHomeBottomArt(state: state), unlit: true, scale: 2) }]
            shownBottomKey = bottom
        }
    }
    /// The console or a card in it moves (or did a moment ago).
    var busy: Bool { moving || CACurrentMediaTime() < stillAfter }
    private var stillAfter: CFTimeInterval = 0
    private var homeWaiting = false
    private func holdStill(for seconds: Double) {
        stillAfter = max(stillAfter, CACurrentMediaTime() + seconds)
    }
    private func showHomeWhenStill() {
        guard !homeWaiting else { return }
        homeWaiting = true
        Task { @MainActor [weak self] in
            while let self, self.busy { try? await Task.sleep(for: .milliseconds(50)) }
            guard let self else { return }
            self.homeWaiting = false
            self.showHome(self.homeState)
        }
    }
    /// Prints a menu ahead of showing it (the card in the middle of the
    /// shelf, while nothing moves), so the swap at the insert is instant.
    func prepareHome(_ state: ConsoleHomeState) {
        _ = Self.cached("T" + state.topKey) { Self.material(for: ConsoleHomeTopArt(state: state), unlit: true, scale: 2) }
        _ = Self.cached("B" + state.bottomKey) { Self.material(for: ConsoleHomeBottomArt(state: state), unlit: true, scale: 2) }
    }
    func isPrepared(_ state: ConsoleHomeState) -> Bool {
        Self.materialCache["T" + state.topKey] != nil && Self.materialCache["B" + state.bottomKey] != nil
    }

    // MARK: The software's last frames on the LCDs (round 32)

    /// What the play view saw last on the two screens, handed to the
    /// library as the software is left: the
    /// console comes down from the flat, full-screen pose with the game
    /// still on its LCDs, so the picture is seen shrinking with it; the
    /// menu takes the screens back with a short fade once it stands.
    nonisolated(unsafe) static var handoff: (top: CGImage, bottom: CGImage)?
    private var pictureOverlays: [ModelEntity] = []
    private var holdingPictures = false
    private var pictureFade: Task<Void, Never>?
    /// The two frames laid over the LCDs (a thin plane each, a hair above
    /// the screen, under its glass); the menu's own print waits.
    func showPictures(top: CGImage, bottom: CGImage) {
        guard built, let upper = upperScreen, let lower = lowerScreen else { return }
        pictureFade?.cancel()
        for overlay in pictureOverlays { overlay.removeFromParent() }
        pictureOverlays = []
        for (lcd, image) in [(upper, top), (lower, bottom)] {
            guard let mesh = lcd.model?.mesh,
                  let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) else { continue }
            var m = UnlitMaterial()
            m.color = .init(tint: .white, texture: .init(texture))
            let overlay = ModelEntity(mesh: mesh, materials: [m])
            overlay.name = lcd.name
            overlay.position = [0, 0.3 * ConsoleModel.u, 0]
            lcd.addChild(overlay)
            pictureOverlays.append(overlay)
        }
        holdingPictures = !pictureOverlays.isEmpty
        NSLog("[stage] the software's last frames on the LCDs (%d)", pictureOverlays.count)
    }
    /// The frames fade out over `seconds`, the menu under them printed
    /// first (what it shows now), so the change is a dissolve, not a cut.
    func releasePictures(fade seconds: Double = 0.35) {
        guard holdingPictures else { return }
        holdingPictures = false
        showHome(homeState)
        let overlays = pictureOverlays
        pictureOverlays = []
        pictureFade?.cancel()
        pictureFade = Task { @MainActor in
            let started = CACurrentMediaTime()
            while !Task.isCancelled {
                let t = min(1, (CACurrentMediaTime() - started) / max(0.01, seconds))
                let opacity = Float(1 - t * t * (3 - 2 * t))
                for overlay in overlays { overlay.components.set(OpacityComponent(opacity: opacity)) }
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            for overlay in overlays { overlay.removeFromParent() }
        }
    }

    // MARK: Pose

    private func stageDistance() -> Float {
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        guard viewSize.height > 0, stageRect.height > 0 else { return 6 }
        let r = ConsoleModel.stageRadius
        let byHeight = r * Float(viewSize.height / stageRect.height) * 1.06 / f
        let byWidth = r * Float(viewSize.width / stageRect.width) * 1.0 / (f * Float(viewSize.width / viewSize.height))
        return max(byHeight, byWidth)
    }
    /// Camera height so that the origin appears at the stage's centre.
    private func cameraY(distance: Float, bias: CGFloat = 0.15) -> Float {
        guard viewSize.height > 0 else { return 0 }
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        // The raised lid makes the console taller above the pivot than below:
        // the pivot sits a little under the stage's middle.
        let centre = stageRect.midY + stageRect.height * bias
        return Float((centre - viewSize.height / 2) / (viewSize.height / 2)) * distance * f
    }
    /// Camera offset sideways so that the origin appears at the stage's
    /// middle (the stage is the left half in landscape on one display).
    private func cameraX(distance: Float) -> Float {
        guard viewSize.width > 0, viewSize.height > 0 else { return 0 }
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        let aspect = Float(viewSize.width / viewSize.height)
        // Moving the camera right puts the scene further left on the screen.
        return -Float((stageRect.midX - viewSize.width / 2) / (viewSize.width / 2)) * distance * f * aspect
    }
    private func flatDistance() -> Float {
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        guard viewSize.height > 0 else { return 3 }
        let aspect = Float(viewSize.width / viewSize.height)
        let halfHeight: Float = 460 * ConsoleModel.u
        let halfWidth: Float = 0.5
        return max(halfHeight / f, halfWidth / (f * aspect)) * 1.02
    }
    private func rotation(yaw: Double, tilt: Double) -> simd_quatf {
        simd_quatf(angle: Float((90 - tilt) * .pi / 180), axis: [1, 0, 0]) * simd_quatf(angle: Float(yaw * .pi / 180), axis: [0, 1, 0])
    }

    /// The corners of the two halves in the console's frame, the lid at
    /// `lidAngle` (the box the camera frames).
    private func consoleCorners(lidAngle: Double) -> [SIMD3<Float>] {
        let u = ConsoleModel.u
        var out: [SIMD3<Float>] = []
        let base = lowerHalf.position
        for x in [Float(-380), 380] { for z in [Float(-220), 220] { for y in [Float(0), ConsoleModel.lowerDepth] {
            out.append(base + [x * u, y, z * u])
        } } }
        let pivot = base + [0, ConsoleModel.hingeY, ConsoleModel.hingeZ]
        let lidOrigin: SIMD3<Float> = [0, ConsoleModel.lowerDepth + 2 * u - ConsoleModel.hingeY - ConsoleModel.lidDepth, 0]
        let turn = simd_quatf(angle: Float(lidAngle * .pi / 180), axis: [1, 0, 0])
        for x in [Float(-380), 380] { for z in [Float(-456), -16] { for y in [Float(0), ConsoleModel.lidDepth] {
            out.append(pivot + turn.act(lidOrigin + [x * u, y, z * u]))
        } } }
        return out
    }

    /// The camera that frames `corners` (turned by `orientation`) in the
    /// stage rectangle, filling `fill` of its width and of its height less
    /// the hint line at the bottom; `zoom` then brings it closer about the
    /// console's middle. Worked out by a few rounds of fitting (the
    /// perspective is mild). Round 19: the framing used to put the pivot at
    /// a fixed spot, which left the console low in the stage.
    private func fitCamera(_ corners: [SIMD3<Float>], orientation: simd_quatf, fill: Float, zoom: Double) -> SIMD3<Float> {
        let w = Float(viewSize.width), h = Float(viewSize.height)
        guard w > 0, h > 0, stageRect.width > 0, stageRect.height > 0 else { return [0, 0, 6] }
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        let aspect = w / h
        // The stage in normalised device coordinates (y up).
        let sx0 = (Float(stageRect.minX) - w / 2) / (w / 2), sx1 = (Float(stageRect.maxX) - w / 2) / (w / 2)
        let sy0 = (h / 2 - (Float(stageRect.maxY) - 16)) / (h / 2), sy1 = (h / 2 - Float(stageRect.minY)) / (h / 2)
        let points = corners.map { orientation.act($0) }
        let meanZ = points.map(\.z).reduce(0, +) / Float(points.count)
        var cx: Float = 0, cy: Float = 0, d: Float = 6
        for _ in 0..<5 {
            var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
            var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
            for p in points {
                let depth = max(0.05, d - p.z)
                let x = (p.x - cx) / (depth * f * aspect), y = (p.y - cy) / (depth * f)
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
            let k = max((maxX - minX) / ((sx1 - sx0) * fill), (maxY - minY) / ((sy1 - sy0) * fill))
            d = meanZ + (d - meanZ) * k
            let depth = d - meanZ
            cx += ((minX + maxX) / 2 - (sx0 + sx1) / 2) * depth * f * aspect
            cy += ((minY + maxY) / 2 - (sy0 + sy1) / 2) * depth * f
        }
        // Closer, about the console's middle (what the camera looks at).
        let z = Float(zoom)
        let mid = SIMD3<Float>(cx + (sx0 + sx1) / 2 * (d - meanZ) * f * aspect, cy + (sy0 + sy1) / 2 * (d - meanZ) * f, meanZ)
        return [mid.x - (mid.x - cx) / z, mid.y - (mid.y - cy) / z, meanZ + (d - meanZ) / z]
    }

    /// Where the camera stands for the stage and back poses: the console
    /// (as it stands before any turn) framed in the stage, or (turned
    /// round) its rear edge, where the slot is, big and in the middle
    /// (round 19). A turn by the finger leaves the camera where it is.
    private func stageCamera(for orientation: simd_quatf) -> SIMD3<Float> {
        guard pose == .back else {
            return fitCamera(consoleCorners(lidAngle: 40), orientation: rotation(yaw: 0, tilt: 52), fill: 0.9, zoom: zoom)
        }
        var d = stageDistance() / Float(zoom)
        let u = ConsoleModel.u
        var lookX = ConsoleModel.slotX * 0.6
        if let wider = backFit(distance: d) { lookX = wider.x; d = wider.distance }
        let rear = orientation.act(lowerHalf.position + [lookX, ConsoleModel.lowerDepth * 0.6, -220 * u])
        return [cameraX(distance: d) + rear.x, cameraY(distance: d, bias: 0.2) + rear.y, d + rear.z]
    }

    /// Round 23: the stylus's end cap is in the rear face too, at the far
    /// end from the slot, and has to be in view to be pulled out. On a
    /// narrow stage (a phone: 10-30 the cap was 33 points off the 17e's
    /// left edge) the slot's close-up leaves it out; then the camera looks
    /// between the two and stands back until both are in. Worked out for
    /// the console turned fully round, so that a turn by the finger does
    /// not make the camera jump. Nil: the close-up has both.
    private func backFit(distance: Float) -> (x: Float, distance: Float)? {
        let w = Float(viewSize.width), h = Float(viewSize.height)
        guard w > 0, h > 0, stageRect.width > 0 else { return nil }
        let u = ConsoleModel.u
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        let aspect = w / h
        // Half the stage's width in normalised device coordinates, less a
        // margin (the cap is a finger's width).
        let room = Float(stageRect.width) / w * 0.9
        let turned = rotation(yaw: 180, tilt: 80)
        func rear(_ x: Float) -> SIMD3<Float> { turned.act(lowerHalf.position + [x, ConsoleModel.lowerDepth * 0.6, -220 * u]) }
        let slotEnd = ConsoleModel.slotX - ConsoleModel.slotWidth / 2, capEnd = Self.stylusHome.x + 18 * u
        let look = rear(ConsoleModel.slotX * 0.6)
        let ends = [rear(slotEnd), rear(capEnd)]
        let inView = ends.allSatisfy { abs($0.x - look.x) / (max(0.05, distance - ($0.z - look.z)) * f * aspect) <= room }
        if inView { return nil }
        let half = abs(ends[0].x - ends[1].x) / 2
        return ((slotEnd + capEnd) / 2, max(distance, half / (room * f * aspect)))
    }

    /// The user's turn (a drag): immediate.
    func applyUserPose() {
        guard pose == .stage || pose == .back, !animating else { return }
        let orientation = rotation(yaw: yaw, tilt: tilt)
        root.orientation = orientation
        camera.position = stageCamera(for: orientation)
        markMoving(for: 0.15)
    }

    /// `moving` from now for at least `seconds`, and for as long as the
    /// moves RealityKit was given are still playing (at most 4 s more: it
    /// can run them late, as at a phone's cold start under the splash, and
    /// the shadow and the menu's markers then kept the starting pose,
    /// 10-30); when it ends, `settled`.
    private var movingUntil: CFTimeInterval = 0
    private var movingWatch: Task<Void, Never>?
    private var moves: [AnimationPlaybackController] = []
    private func markMoving(for seconds: Double) {
        movingUntil = max(movingUntil, CACurrentMediaTime() + seconds)
        if !moving { moving = true }
        guard movingWatch == nil else { return }
        movingWatch = Task { @MainActor [weak self] in
            while let self {
                let now = CACurrentMediaTime()
                let playing = now < self.movingUntil + 4 && self.moves.contains { $0.isPlaying }
                guard now < self.movingUntil || playing else { break }
                let left = max(self.movingUntil - now, 0.05)
                try? await Task.sleep(for: .milliseconds(max(16, Int(left * 1000))))
            }
            guard let self else { return }
            #if DEBUG
            let late = CACurrentMediaTime() - self.movingUntil
            if late > 0.1 { NSLog("[stage] the moves ended %.0f ms after their time", late * 1000) }
            #endif
            self.moves.removeAll()
            self.movingWatch = nil
            self.moving = false
            self.settled += 1
        }
    }

    func applyPose(animated: Bool, duration: Double = 0.9) {
        let targetRotation: simd_quatf
        let cameraPosition: SIMD3<Float>
        let lid: Double
        switch pose {
        case .stage:
            targetRotation = rotation(yaw: yaw, tilt: tilt)
            cameraPosition = stageCamera(for: targetRotation)
            lid = 40
        case .back:
            // The lid stands up, so the rear face under the hinge is in view.
            targetRotation = rotation(yaw: yaw, tilt: tilt)
            cameraPosition = stageCamera(for: targetRotation)
            lid = 115
        case .flat:
            // Flat open, the console's middle is 106 units behind the pivot;
            // seen from above that is 106 units up: the camera follows.
            targetRotation = rotation(yaw: 0, tilt: 0)
            cameraPosition = [0, 106 * ConsoleModel.u, flatDistance()]
            lid = 0
        case .program:
            targetRotation = rotation(yaw: 0, tilt: 0)
            root.stopAllAnimations()
            lidPivot.stopAllAnimations()
            cameraPosition = programCamera()
            lid = 0
        }
        lidAngle = lid
        let lidRotation = simd_quatf(angle: Float(lid * .pi / 180), axis: [1, 0, 0])
        if Self.debugDump {
            NSLog("[stage] pose %@ animated %d view %.0fx%.0f stage (%.0f,%.0f %.0fx%.0f) camera (%.3f %.3f %.3f)", String(describing: pose), animated ? 1 : 0,
                  viewSize.width, viewSize.height, stageRect.minX, stageRect.minY, stageRect.width, stageRect.height, cameraPosition.x, cameraPosition.y, cameraPosition.z)
        }
        // A move issued while an earlier one runs is dropped by RealityKit
        // (10-29: the library's first framing kept the splash's layout):
        // stop what runs, then move on from wherever things are.
        root.stopAllAnimations()
        camera.stopAllAnimations()
        lidPivot.stopAllAnimations()
        if animated {
            animating = true
            animationStamp += 1
            let stamp = animationStamp
            markMoving(for: duration + 0.03)
            moves = [
                root.move(to: Transform(scale: root.scale, rotation: targetRotation, translation: root.position), relativeTo: root.parent, duration: duration, timingFunction: .easeInOut),
                camera.move(to: Transform(scale: camera.scale, rotation: camera.orientation, translation: cameraPosition), relativeTo: camera.parent, duration: duration, timingFunction: .easeInOut),
                lidPivot.move(to: Transform(scale: lidPivot.scale, rotation: lidRotation, translation: lidPivot.position), relativeTo: lidPivot.parent, duration: duration * 0.9, timingFunction: .easeInOut)]
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 30))
                guard let self, self.animationStamp == stamp else { return }
                self.animating = false
            }
        } else {
            root.orientation = targetRotation
            camera.position = cameraPosition
            lidPivot.orientation = lidRotation
            if moving { markMoving(for: 0) } else { settled += 1 }
        }
    }
    private var animationStamp = 0

    /// Turns the console round, rear toward the player, the lid raised out
    /// of the way of the slot.
    func turnToBack() {
        pose = .back
        yaw = 180; tilt = 80; zoom = 1.8
        applyPose(animated: true, duration: 1.0)
    }
    /// Back to the stage, front toward the player.
    func turnToFront(animated: Bool = true) {
        pose = .stage
        yaw = 0; tilt = 52; zoom = 1
        applyPose(animated: animated, duration: 1.0)
    }
    /// The other side (a two-finger tap).
    func flip() {
        guard pose == .stage || pose == .back else { return }
        if rearVisible { turnToFront() } else { turnToBack() }
    }
    /// Back to where the console stood before a card was lifted (round 19).
    func restore(_ saved: ConsoleView, duration: Double = 0.9) {
        guard saved.pose == .stage || saved.pose == .back else { return }
        pose = saved.pose
        yaw = saved.yaw; tilt = saved.tilt; zoom = saved.zoom
        applyPose(animated: true, duration: duration)
    }
    /// Flat and filling the screen: the way into the game.
    func fillScreen(duration: Double = 1.2) {
        pose = .flat
        offerSlot(false)
        applyPose(animated: true, duration: duration)
    }
    /// Flat and filling the screen at once (round 24: the library coming
    /// back from a game shows it so while the game's picture dissolves).
    func placeFlat() {
        pose = .flat
        applyPose(animated: false)
    }
    /// Round 30: a program of the console's own (系统设置, 相机, 游戏记录, 主题,
    /// 说明书) opens on the console where it is: it lies down flat, face up,
    /// and comes up as big as the display allows, the paper round it (on
    /// iPhone Duo the hinge on the fold, each screen on its own half); the
    /// library draws the program in its two screens (`screenRects`).
    func showProgram(duration: Double = 0.85) {
        pose = .program
        yaw = 0; tilt = 0; zoom = 1
        offerSlot(false)
        applyPose(animated: true, duration: duration)
    }
    /// The fold of the display in the view's coordinates (iPhone Duo), set
    /// by the library: a program's console has its hinge there.
    var programFold: CGRect?
    /// Where the camera stands for `program`: straight above the console
    /// lying open and flat, as close as lets all of it in with a margin;
    /// the hinge on the fold when there is one, else the console in the
    /// middle. Measured on the console as it will lie (its turn and lid
    /// set for a moment, then put back).
    private func programCamera() -> SIMD3<Float> {
        let w = Float(viewSize.width), h = Float(viewSize.height)
        guard w > 0, h > 0 else { return [0, 106 * ConsoleModel.u, flatDistance()] }
        let savedRoot = root.orientation, savedLid = lidPivot.orientation
        root.orientation = rotation(yaw: 0, tilt: 0)
        lidPivot.orientation = simd_quatf(angle: 0, axis: [1, 0, 0])
        let points = consoleCorners(lidAngle: 0).map { root.convert(position: $0, to: nil) }
        let pivot = lidPivot.position(relativeTo: nil)
        root.orientation = savedRoot
        lidPivot.orientation = savedLid
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        let minX = points.map(\.x).min() ?? -0.5, maxX = points.map(\.x).max() ?? 0.5
        let minY = points.map(\.y).min() ?? -0.5, maxY = points.map(\.y).max() ?? 0.5
        let face = points.map(\.z).max() ?? 0
        let margin = Float(min(viewSize.width, viewSize.height)) * 0.045
        let above = max(0.01, maxY - pivot.y), below = max(0.01, pivot.y - minY)
        // Points of the view per metre, and where the hinge goes.
        var k = (w - 2 * margin) / (maxX - minX)
        let hingeY: Float
        if let fold = programFold, fold.width >= fold.height, fold.midY > 0, Float(fold.midY) < h {
            hingeY = Float(fold.midY)
            k = min(k, (hingeY - margin) / above, (h - hingeY - margin) / below)
        } else {
            k = min(k, (h - 2 * margin) / (above + below))
            hingeY = (h - (above + below) * k) / 2 + above * k
        }
        let distance = (h / 2) / (k * f)
        let cy = pivot.y - (h / 2 - hingeY) / k
        return [(minX + maxX) / 2, cy, face + distance]
    }
    /// Where the console is on the view as it stands now: the box round
    /// its corners (round 31: brought close by a pinch it reaches over the
    /// shelf, and a finger there is the console's).
    func screenBounds() -> CGRect? {
        let points = consoleCorners(lidAngle: lidAngle).compactMap { project(root.convert(position: $0, to: nil)) }
        guard points.count == 16, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    /// The two screens on the view (round 30): where the library lays the
    /// program's own screens over them. Nil until the console lies for a
    /// program and stands still.
    func screenRects() -> (upper: CGRect, lower: CGRect)? {
        guard pose == .program, !moving, let upper = upperScreen, let lower = lowerScreen else { return nil }
        func rect(_ lcd: ModelEntity, _ width: Float, _ depth: Float) -> CGRect? {
            let corners: [SIMD3<Float>] = [[-width / 2, 0, -depth / 2], [width / 2, 0, -depth / 2], [-width / 2, 0, depth / 2], [width / 2, 0, depth / 2]]
            let points = corners.compactMap { project(lcd.convert(position: $0, to: nil)) }
            guard points.count == 4 else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        let u = ConsoleModel.u
        guard let top = rect(upper, 500 * u, 300 * u), let bottom = rect(lower, 400 * u, 300 * u) else { return nil }
        return (top, bottom)
    }
    /// Back from a flat start to the stage (the library coming back).
    func settleOnStage(from flat: Bool) {
        if flat {
            pose = .flat
            applyPose(animated: false)
            pose = .stage
            yaw = 0; tilt = 52; zoom = 1
            applyPose(animated: true, duration: 1.0)
        } else {
            pose = .stage
            applyPose(animated: false)
        }
    }
    func resetView() {
        guard pose == .stage || pose == .back else { return }
        #if DEBUG
        NSLog("[stage] reset from %@ yaw %.0f tilt %.0f", String(describing: pose), yaw, tilt)
        #endif
        pose = .stage
        yaw = 0; tilt = 52; zoom = 1
        applyPose(animated: true, duration: 0.6)
    }
    /// The turn carries on a little after the finger lifts (round 18).
    func coast(yawBy carry: Double) {
        guard pose == .stage || pose == .back, !animating, abs(carry) > 1 else { return }
        yaw += max(-120, min(120, carry))
        markMoving(for: 0.62)
        moves = [root.move(to: Transform(scale: root.scale, rotation: rotation(yaw: yaw, tilt: tilt), translation: root.position),
                           relativeTo: root.parent, duration: 0.6, timingFunction: .easeOut)]
    }
    /// The stage rectangle moved (layout): keep the framing. During an
    /// animation the target moves with it (the first layout on iPhone Duo
    /// comes with the splash's insets, the real one a moment later).
    func reframe() {
        guard built else { return }
        if animating { applyPose(animated: true, duration: 0.35) } else { applyPose(animated: false) }
    }

    /// The slot is offered a card (or not): the mark over it lights, the
    /// door swings in. The door stays in while a card is inside, and closes
    /// once the slot is empty and nothing is offered.
    func offerSlot(_ on: Bool) {
        slotOpen = on
        slotMark?.model?.materials = [on ? slotMarkLit : slotMarkUnlit]
        setDoor(open: on || card != nil)
    }
    private var doorOpen = false
    private func setDoor(open: Bool) {
        guard open != doorOpen else { return }
        doorOpen = open
        let target = simd_quatf(angle: open ? -1.9 : 0, axis: [1, 0, 0])
        doorPivot.move(to: Transform(scale: doorPivot.scale, rotation: target, translation: doorPivot.position), relativeTo: doorPivot.parent, duration: 0.4, timingFunction: .easeOut)
    }

    /// A point of the scene in the RealityView's coordinates.
    private func project(_ p: SIMD3<Float>) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let c = camera.position
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        let aspect = Float(viewSize.width / viewSize.height)
        let depth = c.z - p.z
        guard depth > 0.01 else { return nil }
        let x = (p.x - c.x) / depth / (f * aspect)
        let y = (p.y - c.y) / depth / f
        return CGPoint(x: viewSize.width / 2 + CGFloat(x) * viewSize.width / 2,
                       y: viewSize.height / 2 - CGFloat(y) * viewSize.height / 2)
    }
    /// The slot's mouth in the RealityView's coordinates (for the drop).
    func slotPoint() -> CGPoint? {
        project(slotMouth.position(relativeTo: nil))
    }
    /// `--foldarc-stage-debug`: a few known points of the console on the
    /// screen (drawn by the library to check the projection against the
    /// picture).
    func debugPoints() -> [(String, CGPoint)] {
        let u = ConsoleModel.u
        var out: [(String, CGPoint)] = []
        if let p = project(root.convert(position: .zero, to: nil)) { out.append(("O", p)) }
        if let p = project(lowerHalf.convert(position: [0, ConsoleModel.lowerDepth, 220 * u], to: nil)) { out.append(("F", p)) }
        if let p = project(lowerHalf.convert(position: [-380 * u, ConsoleModel.lowerDepth, 220 * u], to: nil)) { out.append(("L", p)) }
        if let lid = lidPivot.children.first, let p = project(lid.convert(position: [0, ConsoleModel.lidDepth, -456 * u], to: nil)) { out.append(("T", p)) }
        if let p = slotPoint() { out.append(("S", p)) }
        return out
    }
    /// The middle of the lower screen (a tap there chooses the card inside).
    func lowerScreenPoint() -> CGPoint? {
        guard let lowerScreen else { return nil }
        return project(lowerScreen.position(relativeTo: nil))
    }
    /// 11-23: the MIC printed on the lower half's face (LowerFaceArt: its dot at 480, 391 of the drawing, the
    /// word under it) on the view, as MicHole's box is round its own (64 × 30 of the drawing, the mark in its
    /// middle): where MicPointer's arrow points while a program on the console listens. Nil until the console
    /// lies for a program and stands still.
    func micRect() -> CGRect? {
        guard pose == .program, !moving else { return nil }
        func at(_ x: Double, _ y: Double) -> CGPoint? {
            project(lowerHalf.convert(position: ConsoleModel.lower(x, y) + [0, ConsoleModel.lowerDepth, 0], to: nil))
        }
        guard let c = at(480, 397), let a = at(448, 397), let b = at(512, 397) else { return nil }
        // (one unit of the drawing on the view, whichever way the console lies on it)
        let unit = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() / 64
        guard unit > 0.05 else { return nil }
        return CGRect(x: c.x - 32 * unit, y: c.y - 15 * unit, width: 64 * unit, height: 30 * unit)
    }
    /// The lip of the card in the slot, where a finger takes hold of it.
    func cardPoint() -> CGPoint? {
        guard let card else { return nil }
        let lip = card.position + [0, 0, -(ConsoleModel.cardLength / 2 - ConsoleModel.cardLip / 2)]
        return project(lowerHalf.convert(position: lip, to: nil))
    }
    /// The way a card comes out of the slot, on the screen: the direction
    /// and how many points a full pull (one card length) covers. Nil when
    /// the slot points straight at the player (nothing to pull along).
    func pullVector() -> (direction: CGVector, length: CGFloat)? {
        guard let a = project(slotMouth.position(relativeTo: nil)),
              let b = project(lowerHalf.convert(position: slotMouth.position + [0, 0, -ConsoleModel.cardLength], to: nil)) else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 4 else { return nil }
        return (CGVector(dx: dx / length, dy: dy / length), length)
    }

    // MARK: The card

    /// Where a card going in starts its slide, from its place in the slot.
    private static var cardEntryOffset: SIMD3<Float> { [0, 2 * ConsoleModel.u, -300 * ConsoleModel.u] }
    /// Where a card going in first shows (round 24): the middle of the card
    /// at the start of its slide into the slot, and how wide it is on the
    /// screen there. The card in the hand shrinks and tips onto it.
    func cardEntry() -> (point: CGPoint, width: CGFloat)? {
        let start = cardHome + Self.cardEntryOffset
        let half = ConsoleModel.cardWidth / 2
        guard let c = project(lowerHalf.convert(position: start, to: nil)),
              let a = project(lowerHalf.convert(position: start + [-half, 0, 0], to: nil)),
              let b = project(lowerHalf.convert(position: start + [half, 0, 0], to: nil)) else { return nil }
        return (c, hypot(b.x - a.x, b.y - a.y))
    }
    private var cardHome: SIMD3<Float> {
        let u = ConsoleModel.u
        return [ConsoleModel.slotX, ConsoleModel.slotY, -220 * u + ConsoleModel.cardLength / 2 - ConsoleModel.cardLip]
    }

    /// Slides a card into the slot until it clicks home; not animated, it
    /// is simply there, drawn out `out` of the way (the library coming back
    /// to a console that holds one). The label faces the bottom of the
    /// console, as a handheld's manual asks (round 20): from above and from
    /// behind one sees the card's back.
    func insertCard(_ info: GameCardInfo, animated: Bool = true, out: Double = 0, adopting: ModelEntity? = nil, completion: @escaping () -> Void) {
        // Still again once it has clicked home (before the screens hear of
        // the card: see showHome).
        if animated { holdStill(for: 0.75) }
        ejectCard(animated: false)
        let u = ConsoleModel.u
        let name = "游戏卡 · \(info.title)"
        // Round 27: the card is a solid (CardModel3D), its label down, its
        // grip out of the slot; the one that flew in from the hand goes on
        // as it is, where it landed (the start of the slide).
        let entity: ModelEntity
        if let adopting {
            entity = adopting
            entity.stopAllAnimations()
            Self.rename(entity, name)
            entity.components.remove(OpacityComponent.self)
            ShelfScene.reparent(entity, to: lowerHalf, "into the slot")
        } else {
            entity = CardModel3D.make(info, name: name)
            entity.orientation = Self.slotCardOrientation
            lowerHalf.addChild(entity)
        }
        // The lip is small: the finger may take hold a little beyond it (the
        // box in the solid's own axes: across, along toward the grip, through).
        touchable(entity, size: [ConsoleModel.cardWidth + 10 * u, ConsoleModel.cardLength + 50 * u, ConsoleModel.cardThickness + 12 * u], offset: [0, 25 * u, 0])
        if studio.components.has(ImageBasedLightComponent.self) { Self.receiveLight(entity, from: studio) }
        card = entity
        cardTitle = info.title
        cardOut = animated ? 0 : min(1, max(0, out))
        cardInserted = cardOut == 0
        cardLoose = cardOut > 0
        setDoor(open: true)
        if animated {
            if adopting == nil {
                entity.position = cardHome + Self.cardEntryOffset
            }
            entity.move(to: Transform(scale: [1, 1, 1], rotation: Self.slotCardOrientation, translation: cardHome),
                        relativeTo: lowerHalf, duration: 0.55, timingFunction: .easeIn)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(620))
                completion()
            }
        } else {
            entity.scale = [1, 1, 1]
            entity.orientation = Self.slotCardOrientation
            entity.position = cardHome + [0, 0, -Float(cardOut) * ConsoleModel.cardLength]
            completion()
        }
    }
    /// How a card lies in the slot (round 27, in the solid's axes: x across
    /// the label, y toward the grip, z out of the label): the grip out of
    /// the slot (-z), the label facing the bottom of the console (-y). A
    /// half turn about the line halfway between up and out.
    static let slotCardOrientation = simd_quatf(angle: .pi, axis: simd_normalize(SIMD3<Float>(0, 1, -1)))
    private static func rename(_ entity: Entity, _ name: String) {
        entity.name = name
        for child in entity.children { rename(child, name) }
    }
    /// Where a card going in starts its slide, in the world (round 27: the
    /// card in the hand flies there, then slides in).
    func cardEntryTransform() -> Transform? {
        guard built else { return nil }
        let local = Transform(scale: [1, 1, 1], rotation: Self.slotCardOrientation, translation: cardHome + Self.cardEntryOffset)
        return Transform(matrix: lowerHalf.transformMatrix(relativeTo: nil) * local.matrix)
    }
    /// The card leaves the slot: slides out and is gone (animated), or is
    /// simply gone (a finger has it now). With `keep`, it is not gone: it is
    /// handed over (the same solid, for the hand: round 27), after its slide
    /// when animated.
    func ejectCard(animated: Bool, keep: ((ModelEntity) -> Void)? = nil) {
        guard let entity = card else { return }
        if animated { holdStill(for: 0.6) }
        card = nil
        cardInserted = false
        cardLoose = false
        cardOut = 0
        if !slotOpen { setDoor(open: false) }
        if keep != nil { entity.components.remove(CollisionComponent.self) }
        entity.stopAllAnimations()
        if animated {
            var out = entity.position
            out.z -= 320 * ConsoleModel.u
            let slid = Transform(scale: entity.scale, rotation: entity.orientation, translation: out)
            entity.move(to: slid, relativeTo: lowerHalf, duration: 0.5, timingFunction: .easeOut)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                // Where the slide ends, whether or not RealityKit has got
                // there yet (a move still running would go on writing the
                // slot's coordinates after the hand took the card).
                entity.stopAllAnimations()
                if entity.parent === self.lowerHalf { entity.transform = slid }
                #if DEBUG
                if ShelfScene.debugHand {
                    let p = entity.position, w = entity.transformMatrix(relativeTo: nil).columns.3
                    let c = (self.lowerHalf.transformMatrix(relativeTo: nil) * entity.transform.matrix).columns.3
                    NSLog("[hand] slid out: in the console %d, local (%.3f %.3f %.3f), world (%.3f %.3f %.3f), console's half * local (%.3f %.3f %.3f)",
                          entity.parent === self.lowerHalf ? 1 : 0, p.x, p.y, p.z, w.x, w.y, w.z, c.x, c.y, c.z)
                }
                #endif
                if let keep { keep(entity) } else { entity.removeFromParent() }
            }
        } else {
            if let keep { keep(entity) } else { entity.removeFromParent() }
        }
    }

    // MARK: The card in the hand (round 27)

    /// The card in the middle of the shelf, taken into the hand.
    @discardableResult func liftFromShelf(_ index: Int, at point: CGPoint) -> Bool {
        shelf.takeFromShelf(index, at: point)
    }
    /// The finger carrying the card in the hand.
    func moveLifted(to point: CGPoint) {
        shelf.moveHand(to: point)
    }
    /// The card in the hand carried to `point` along a smooth path (A).
    func carryLifted(to point: CGPoint, duration: Double) {
        shelf.carryHand(to: point, duration: duration)
    }
    /// The card in the hand flies to the slot's mouth and slides in.
    func insertLifted(_ info: GameCardInfo, completion: @escaping () -> Void) {
        guard shelf.handIndex != nil else { insertCard(info, completion: completion); return }
        holdStill(for: 1.2)
        shelf.flyHand(to: { [weak self] in self?.cardEntryTransform() }, duration: 0.46, bow: 0.05) { [weak self] model in
            guard let self else { return }
            self.shelf.handOver()
            self.insertCard(info, animated: true, adopting: model, completion: completion)
        }
    }
    /// The card in the hand goes back to its place on the shelf.
    func putLiftedBack() {
        shelf.flyHandHome()
    }
    /// The card in the slot comes out into the hand (a finger drew it out).
    func liftFromSlot(_ index: Int, at point: CGPoint) {
        ejectCard(animated: false) { [weak self] model in
            self?.shelf.takeIntoHand(model, index: index, at: point)
        }
    }
    /// The card in the slot slides out by itself and goes back to the shelf.
    func ejectToShelf(_ index: Int, landed: @escaping () -> Void) {
        ejectCard(animated: true) { [weak self] model in
            guard let self else { return }
            self.shelf.takeIntoHand(model, index: index, at: self.shelf.layout.centre)
            landed()
            self.shelf.flyHandHome(duration: 0.55)
        }
    }
    /// A finger moves the card in the slot: 0 is home, 1 is clear of the
    /// slot. Off home, the console no longer reads it (round 20: a card
    /// drawn out part of the way stays there, as a real one does).
    func pullCard(progress: Double) {
        guard let card else { return }
        holdStill(for: 0.35)
        cardOut = min(1, max(0, progress))
        card.stopAllAnimations()
        card.position = cardHome + [0, 0, -Float(cardOut) * ConsoleModel.cardLength]
        let home = cardOut <= 0.0001
        if cardInserted != home { cardInserted = home }
        if cardLoose == home { cardLoose = !home }
    }
    /// The finger let go of the card. Within the last few millimetres it
    /// clicks home (the contacts pull it in); anywhere else it stays where it
    /// was let go. True when it clicked home.
    @discardableResult func releaseCard() -> Bool {
        guard let card, cardOut > 0, cardOut < 0.08 else { return false }
        cardOut = 0
        card.move(to: Transform(scale: card.scale, rotation: card.orientation, translation: cardHome), relativeTo: lowerHalf, duration: 0.1, timingFunction: .easeIn)
        cardInserted = true
        cardLoose = false
        return true
    }
    /// The part under a point is the card in the slot.
    func isCard(at point: CGPoint) -> Bool {
        card != nil && (partName(at: point)?.hasPrefix("游戏卡") ?? false)
    }

    // MARK: Looking at parts

    /// The nearest thing under a point of the RealityView.
    private func raycast(_ point: CGPoint) -> CollisionCastHit? {
        guard viewSize.width > 0, let scene = root.scene else { return nil }
        let f = tan(ConsoleModel.fieldOfView / 2 * .pi / 180)
        let aspect = Float(viewSize.width / viewSize.height)
        let nx = Float(point.x / viewSize.width * 2 - 1) * f * aspect
        let ny = Float(1 - point.y / viewSize.height * 2) * f
        let direction = simd_normalize(SIMD3<Float>(nx, ny, -1))
        return scene.raycast(origin: camera.position, direction: direction, length: 50, query: .nearest, mask: .all, relativeTo: nil).first
    }
    /// The part under a point of the RealityView, by name.
    func partName(at point: CGPoint) -> String? {
        touch(at: point)?.part
    }
    /// What a finger at `point` touches: the part, and on the touch screen
    /// the point of its picture (400 × 300, round 20: the console's menu
    /// answers taps), on the D-pad the arm.
    func touch(at point: CGPoint) -> ConsoleTouch? {
        guard let hit = raycast(point) else { return nil }
        var entity: Entity? = hit.entity
        while let e = entity, e.name.isEmpty { entity = e.parent }
        guard let named = entity else { return nil }
        var result = ConsoleTouch(part: named.name)
        if let lcd = lowerScreen, hit.entity === lcd {
            let local = lcd.convert(position: hit.position, from: nil)
            result.screenPoint = CGPoint(x: Double(local.x / ConsoleModel.u) + 200, y: Double(local.z / ConsoleModel.u) + 150)
        }
        #if DEBUG
        if let lcd = lowerScreen {
            // Round 32 (b16): where a hit lies against the touch screen, for
            // the taps that land on the body instead (888, 891: the small
            // icons along the screen's top edge).
            let local = lcd.convert(position: hit.position, from: nil)
            NSLog("[stage] debug: hit %@ (%@) at touch-screen local (%.0f, %.0f, %.1f)", hit.entity.name, named.name,
                  Double(local.x / ConsoleModel.u) + 200, Double(local.z / ConsoleModel.u) + 150, Double(local.y / ConsoleModel.u))
        }
        #endif
        if named.name == "十字键" {
            let local = named.convert(position: hit.position, from: nil)
            if abs(local.x) > abs(local.z) { result.direction = local.x > 0 ? .right : .left } else { result.direction = local.z > 0 ? .down : .up }
        }
        return result
    }
    /// A key goes down under the finger and comes back up.
    func press(_ part: String) {
        guard let key = keys[part] else { return }
        let entity = key.entity, rest = key.rest
        entity.stopAllAnimations()
        var down = rest
        down.y -= 2.2 * ConsoleModel.u
        entity.move(to: Transform(scale: entity.scale, rotation: entity.orientation, translation: down), relativeTo: entity.parent, duration: 0.05, timingFunction: .easeOut)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(85))
            entity.move(to: Transform(scale: entity.scale, rotation: entity.orientation, translation: rest), relativeTo: entity.parent, duration: 0.12, timingFunction: .easeOut)
        }
    }
    /// A key's top on the screen (for assistive access to A, B, HOME).
    func keyPoint(_ part: String) -> CGPoint? {
        guard let key = keys[part] else { return nil }
        return project(key.entity.position(relativeTo: nil) + [0, 4 * ConsoleModel.u, 0])
    }
    /// A point of a key away from its middle (design units in its own
    /// plane): the D-pad's arms (round 30).
    func keyPoint(_ part: String, dx: Float, dz: Float) -> CGPoint? {
        guard let key = keys[part] else { return nil }
        let u = ConsoleModel.u
        return project(key.entity.convert(position: [dx * u, 9 * u, dz * u], to: nil))
    }
    /// A point of the touch screen's picture (400 × 300) on the screen.
    func lowerScreenPoint(art: CGPoint) -> CGPoint? {
        guard let lcd = lowerScreen else { return nil }
        let local = SIMD3<Float>(Float(art.x - 200) * ConsoleModel.u, 0, Float(art.y - 150) * ConsoleModel.u)
        return project(lcd.convert(position: local, to: nil))
    }
    /// The touch screen faces the camera well enough to be touched.
    var lowerScreenFacing: Bool {
        guard let lcd = lowerScreen else { return false }
        let p = lcd.position(relativeTo: nil)
        let normal = lcd.convert(direction: [0, 1, 0], to: nil)
        return simd_dot(simd_normalize(normal), simd_normalize(camera.position - p)) > 0.3
    }
    /// The volume knob follows the volume (it is set in the game, round 20).
    func showVolume(_ level: Double) {
        guard let knob = volumeKnob else { return }
        var position = knob.position
        let target = ConsoleModel.lid(54, Self.volumeKnobY(level))
        position.z = target.z
        knob.move(to: Transform(scale: knob.scale, rotation: knob.orientation, translation: position), relativeTo: knob.parent, duration: 0.2, timingFunction: .easeOut)
    }
    /// A volume key pressed with the volume already at that end (round 24):
    /// the knob knocks against the end of its track and settles back.
    func bumpVolume(up: Bool) {
        guard let knob = volumeKnob else { return }
        let rest = ConsoleModel.lid(54, Self.volumeKnobY(ConsoleVolume.shared.level))
        var home = knob.position
        home.z = rest.z
        var past = home
        // Up is toward the hinge's far side: smaller z on the lid.
        past.z += (up ? -2.5 : 2.5) * ConsoleModel.u
        knob.stopAllAnimations()
        knob.move(to: Transform(scale: knob.scale, rotation: knob.orientation, translation: past), relativeTo: knob.parent, duration: 0.06, timingFunction: .easeOut)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard let knob = self?.volumeKnob else { return }
            knob.move(to: Transform(scale: knob.scale, rotation: knob.orientation, translation: home), relativeTo: knob.parent, duration: 0.22, timingFunction: .easeOut)
        }
    }
    /// The volume knob's place along its track (design points; up is louder).
    static func volumeKnobY(_ level: Double) -> Double { 335 - 46 * min(1, max(0, level)) }
    /// The volume knob or its track under a point (round 21: it is dragged
    /// like the real slider).
    func isVolume(at point: CGPoint) -> Bool { touch(at: point)?.part == "音量滑块" }
    /// The volume track on the screen: from silent (bottom) to loudest
    /// (top), and how long it is there in points.
    func volumeVector() -> (direction: CGVector, length: CGFloat)? {
        guard let knob = volumeKnob, let lid = knob.parent else { return nil }
        let quiet = lid.convert(position: ConsoleModel.lid(54, Self.volumeKnobY(0)), to: nil)
        let loud = lid.convert(position: ConsoleModel.lid(54, Self.volumeKnobY(1)), to: nil)
        guard let a = project(quiet), let b = project(loud) else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 1 else { return nil }
        return (CGVector(dx: dx / length, dy: dy / length), length)
    }
    /// Where the volume knob is on the screen (its callout, its marker).
    func volumeKnobPoint() -> CGPoint? {
        guard let knob = volumeKnob else { return nil }
        return project(knob.position(relativeTo: nil))
    }
    /// The volume knob's travel on the screen (round 26: the iPhone's own
    /// volume slider is laid along it): the knob's middle at silent and at
    /// loudest, and the knob's size there (along the track, across it).
    func volumeTrack() -> VolumeTrackMarker? {
        guard let knob = volumeKnob, let lid = knob.parent else { return nil }
        let u = ConsoleModel.u
        let lift = SIMD3<Float>(0, ConsoleModel.lidDepth + 2.5 * u, 0)
        let quiet3 = ConsoleModel.lid(54, Self.volumeKnobY(0)) + lift
        let loud3 = ConsoleModel.lid(54, Self.volumeKnobY(1)) + lift
        guard let quiet = project(lid.convert(position: quiet3, to: nil)),
              let loud = project(lid.convert(position: loud3, to: nil)),
              let along = project(lid.convert(position: quiet3 + [0, 0, -19 * u], to: nil)),
              let across = project(lid.convert(position: quiet3 + [13 * u, 0, 0], to: nil)) else { return nil }
        guard hypot(loud.x - quiet.x, loud.y - quiet.y) > 6 else { return nil }
        return VolumeTrackMarker(quiet: quiet, loud: loud,
                                 knobLength: hypot(along.x - quiet.x, along.y - quiet.y),
                                 knobWidth: hypot(across.x - quiet.x, across.y - quiet.y))
    }

    // MARK: The 3D slider and the Circle Pad in the library (round 30)

    /// The 3D knob's place along its track (design points; up is deeper, the
    /// bottom is OFF, as the volume's).
    static func depthKnobY(_ depth: Double) -> Double { 335 - 46 * min(1, max(0, depth)) }
    /// The 3D knob follows the 3D setting.
    func showDepth(_ depth: Double) {
        guard let knob = depthKnob else { return }
        var position = knob.position
        position.z = ConsoleModel.lid(706, Self.depthKnobY(depth)).z
        knob.move(to: Transform(scale: knob.scale, rotation: knob.orientation, translation: position), relativeTo: knob.parent, duration: 0.2, timingFunction: .easeOut)
    }
    /// The 3D knob or its track under a point.
    func isDepth(at point: CGPoint) -> Bool { touch(at: point)?.part == "3D 景深滑块" }
    /// The 3D track on the screen: from OFF (bottom) to deepest (top), and
    /// how long it is there in points.
    func depthVector() -> (direction: CGVector, length: CGFloat)? {
        guard let knob = depthKnob, let lid = knob.parent else { return nil }
        let off = lid.convert(position: ConsoleModel.lid(706, Self.depthKnobY(0)), to: nil)
        let deep = lid.convert(position: ConsoleModel.lid(706, Self.depthKnobY(1)), to: nil)
        guard let a = project(off), let b = project(deep) else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 1 else { return nil }
        return (CGVector(dx: dx / length, dy: dy / length), length)
    }
    /// Where the 3D knob is on the screen (its marker).
    func depthKnobPoint() -> CGPoint? {
        guard let knob = depthKnob else { return nil }
        return project(knob.position(relativeTo: nil))
    }
    /// The Circle Pad under a point (a push on it moves the menu's cursor).
    func isCirclePad(at point: CGPoint) -> Bool { touch(at: point)?.part == "滑动摇杆" }
}


/// The RealityView that shows the stage. It covers the whole library; the
/// console is framed into the stage rectangle by the camera.
struct ConsoleStageView: View {
    @ObservedObject var stage: ConsoleStage
    var body: some View {
        RealityView { content in
            stage.build(into: &content)
        }
        .accessibilityHidden(true)
    }
}
#else
/// The macOS render preview has no RealityKit stage: the same surface, doing nothing.
@MainActor final class ConsoleStage: ObservableObject {
    private(set) var finish: ShellFinish
    func setFinish(_ new: ShellFinish) { finish = new }
    var viewSize = CGSize.zero
    var stageRect = CGRect.zero
    var yaw = 0.0
    var tilt = 52.0
    var zoom = 1.0
    @Published var calloutName: String?
    @Published var calloutPoint = CGPoint.zero
    @Published var calloutStamp = 0
    @Published private(set) var slotOpen = false
    @Published private(set) var cardInserted = false
    @Published private(set) var cardLoose = false
    @Published private(set) var moving = false
    @Published private(set) var settled = 0
    private(set) var cardOut = 0.0
    nonisolated static let debugDump = false
    var view: ConsoleView { ConsoleView(yaw: yaw, tilt: tilt, zoom: zoom, pose: .stage) }
    var rearVisible: Bool { false }
    var insertedTitle: String? { nil }
    var titleInSlot: String? { nil }
    var lowerScreenFacing: Bool { false }
    init(finish: ShellFinish) { self.finish = finish }
    func applyUserPose() {}
    func turnToBack() {}
    func turnToFront(animated: Bool = true) {}
    func flip() {}
    func restore(_ saved: ConsoleView, duration: Double = 0.9) {}
    func fillScreen(duration: Double = 1.2) {}
    func settleOnStage(from flat: Bool) {}
    func placeFlat() {}
    func showProgram(duration: Double = 0.85) {}
    var programFold: CGRect?
    func screenRects() -> (upper: CGRect, lower: CGRect)? { nil }
    func screenBounds() -> CGRect? { nil }
    func resetView() {}
    func coast(yawBy carry: Double) {}
    func reframe() {}
    func showHome(_ state: ConsoleHomeState) {}
    nonisolated(unsafe) static var handoff: (top: CGImage, bottom: CGImage)?
    func showPictures(top: CGImage, bottom: CGImage) {}
    func releasePictures(fade seconds: Double = 0.35) {}
    func prepareHome(_ state: ConsoleHomeState) {}
    func prepareCard(_ info: GameCardInfo) {}
    func isPrepared(_ state: ConsoleHomeState) -> Bool { true }
    func showVolume(_ level: Double) {}
    func bumpVolume(up: Bool) {}
    var built: Bool { true }
    var busy: Bool { false }
    func isVolume(at point: CGPoint) -> Bool { false }
    func volumeVector() -> (direction: CGVector, length: CGFloat)? { nil }
    func volumeKnobPoint() -> CGPoint? { nil }
    func volumeTrack() -> VolumeTrackMarker? { nil }
    func showDepth(_ depth: Double) {}
    func isDepth(at point: CGPoint) -> Bool { false }
    func depthVector() -> (direction: CGVector, length: CGFloat)? { nil }
    func depthKnobPoint() -> CGPoint? { nil }
    func isCirclePad(at point: CGPoint) -> Bool { false }
    func press(_ part: String) {}
    func touch(at point: CGPoint) -> ConsoleTouch? { nil }
    func lowerScreenPoint(art: CGPoint) -> CGPoint? { nil }
    func keyPoint(_ part: String) -> CGPoint? { nil }
    func keyPoint(_ part: String, dx: Float, dz: Float) -> CGPoint? { nil }
    func offerSlot(_ on: Bool) {}
    func slotPoint() -> CGPoint? { nil }
    func cardPoint() -> CGPoint? { nil }
    func cardEntry() -> (point: CGPoint, width: CGFloat)? { nil }
    func lowerScreenPoint() -> CGPoint? { nil }
    func micRect() -> CGRect? { nil }
    func debugPoints() -> [(String, CGPoint)] { [] }
    func setShadow(tint: Color, strength: Float) {}
    func showShadow(_ on: Bool, fade: Double = 0.35) {}
    func pullVector() -> (direction: CGVector, length: CGFloat)? { nil }
    func insertCard(_ info: GameCardInfo, animated: Bool = true, out: Double = 0, completion: @escaping () -> Void) { completion() }
    func ejectCard(animated: Bool) {}
    let shelf = ShelfScene()
    @discardableResult func liftFromShelf(_ index: Int, at point: CGPoint) -> Bool { true }
    func moveLifted(to point: CGPoint) {}
    func carryLifted(to point: CGPoint, duration: Double) {}
    func insertLifted(_ info: GameCardInfo, completion: @escaping () -> Void) { completion() }
    func putLiftedBack() {}
    func liftFromSlot(_ index: Int, at point: CGPoint) {}
    func ejectToShelf(_ index: Int, landed: @escaping () -> Void) { landed() }
    func pullCard(progress: Double) {}
    @discardableResult func releaseCard() -> Bool { false }
    func isCard(at point: CGPoint) -> Bool { false }
    func partName(at point: CGPoint) -> String? { nil }
    private(set) var stylusOut = false
    private(set) var earphonesIn = false
    func setStylus(out: Bool, animated: Bool) { stylusOut = out }
    func setEarphones(_ on: Bool) { earphonesIn = on }
    private(set) var chargerIn = false
    private(set) var chargeLightOn = false
    var chargerSeated: ((Bool) -> Void)?
    func setCharger(_ plugged: Bool, animated: Bool) { chargerIn = plugged }
    func setChargeLight(_ on: Bool, animated: Bool) { chargeLightOn = on }
    func chargerPortPoint() -> CGPoint? { nil }
    func chargerPlugPoint() -> CGPoint? { nil }
    func chargeLightPoint() -> CGPoint? { nil }
    var pose: ConsolePose { .stage }
    func stylusPoint() -> CGPoint? { nil }
    func jackPoint() -> CGPoint? { nil }
}
struct ConsoleStageView: View {
    @ObservedObject var stage: ConsoleStage
    var body: some View { Color.clear }
}
#endif

/// What a card knows about its software, for the label and the screens.
struct GameCardInfo: Equatable {
    var title: String
    var subtitle: String
    var icon: CGImage?
    var isDemo: Bool
    /// A 典藏卡带's own card (bronze, silver or gold, on the shelf while its
    /// purchase is owned): in the console it plays its films.
    var cartridge: Cartridge? = nil
    var isCartridge: Bool { cartridge != nil }
    static func == (a: GameCardInfo, b: GameCardInfo) -> Bool {
        a.title == b.title && a.subtitle == b.subtitle && a.isDemo == b.isDemo && a.cartridge == b.cartridge && (a.icon == nil) == (b.icon == nil)
    }
    /// A 典藏卡带's card, named in the language of the moment.
    static func card(for cartridge: Cartridge) -> GameCardInfo {
        GameCardInfo(title: cartridge.title, subtitle: cartridge.subtitle, icon: nil, isDemo: false, cartridge: cartridge)
    }
}

// MARK: - The faces, drawn flat for printing on the solid

/// The lower half's face without its raised parts: the casing, the LCD
/// surround, the labels, the pads' wells, the microphone, the lights' windows.
/// Round 29: one colour, as the plastic is
/// moulded. Round 24's print carried light and shade of its own (a gradient
/// across the face and a lighter plateau), which read as paint under the
/// studio's real light; now the studio does all the shading, and the gloss
/// over the print shows its lights as the console turns.
struct LowerFaceArt: View {
    var finish: ShellFinish
    var body: some View {
        ZStack {
            Rectangle().fill(finish.base)
            // The LCD's black surround (its frame, glass and picture are solids above).
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.02))
                .frame(width: ConsoleMetrics.lowerLCD.width + 26, height: ConsoleMetrics.lowerLCD.height + 26)
                .position(x: ConsoleMetrics.lowerLCD.midX, y: ConsoleMetrics.lowerLCD.midY)
            // The wells the Circle Pad, the C Stick and the four keys sit in:
            // the dark gap round each, a hair of light on the lower lip.
            well(98).position(x: 91, y: 116)
            well(34).position(x: 632, y: 76)
            ForEach(Array([(670.0, 143.0), (714.0, 187.0), (670.0, 231.0), (626.0, 187.0)].enumerated()), id: \.offset) { _, key in
                well(45).position(x: key.0, y: key.1)
            }
            Text("START").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(finish.ink).position(x: 669, y: 324)
            Text("SELECT").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(finish.ink).position(x: 669, y: 365)
            Text("HOME").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(finish.ink).position(x: 380, y: 413)
            Circle().fill(Color(white: 0.03)).frame(width: 5, height: 5).position(x: 480, y: 391)
            Text("MIC").font(.system(size: 6, weight: .semibold)).foregroundStyle(finish.ink.opacity(0.7)).position(x: 480, y: 402)
            // The lights' windows (the lights themselves are solids, lit).
            HStack(spacing: 9) {
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(Color(white: 0.06)).frame(width: 5, height: 8) }
            }.position(x: 703, y: 435)
            Text("Z E R O").font(.system(size: 8, weight: .semibold)).foregroundStyle(finish.ink).position(x: 83, y: 406)
        }
        .frame(width: 760, height: 440)
        .background(finish.base)
    }
    private func well(_ size: CGFloat) -> some View {
        Circle().fill(Color(white: 0.03))
            .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// The inside of the lid without its raised parts: the black glass panel
/// round the LCD, the grilles' holes, the sliders' tracks and marks. Round
/// 29: flat colours (no light painted on; see LowerFaceArt).
struct LidInnerArt: View {
    var finish: ShellFinish
    var body: some View {
        ZStack {
            Rectangle().fill(finish.base)
            RoundedRectangle(cornerRadius: 34).fill(finish.isLight ? finish.light.opacity(0.94) : Color(white: 0.035))
                .padding(11)
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.015))
                .frame(width: ConsoleMetrics.upperLCD.width + 26, height: ConsoleMetrics.upperLCD.height + 26)
                .position(x: ConsoleMetrics.upperLCD.midX, y: ConsoleMetrics.upperLCD.midY)
            Circle().fill(Color(white: 0.12)).frame(width: 20, height: 20).position(x: 380, y: 27)
            Circle().fill(Color(white: 0.08)).frame(width: 7, height: 7).position(x: 406, y: 27)
            SpeakerHoles().position(x: 74, y: 211)
            SpeakerHoles().position(x: 686, y: 211)
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("3D").font(.system(size: 11, weight: .semibold))
                    Capsule().fill(Color(white: 0.06)).frame(width: 4, height: 6.5)
                }
                Capsule().fill(Color(white: 0.02)).frame(width: 5, height: 65)
            }
            .foregroundStyle(finish.ink).position(x: 706, y: 313)
            // The volume slider's track (round 20), mirrored on the left.
            VStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 10, weight: .semibold)).frame(height: 13)
                Capsule().fill(Color(white: 0.02)).frame(width: 5, height: 65)
                Text("VOL").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(finish.ink).position(x: 54, y: 313)
        }
        .frame(width: 760, height: 440)
        .background(finish.base)
    }
}

/// A speaker's holes on the lid (round 24, after photographs): five in a
/// cross. Round 29: plain dark bores in the print, each covered by a matte
/// black disc in the solid (SpeakerHoles.holes), so the gloss over the print
/// does not run across them.
struct SpeakerHoles: View {
    static let holes: [(Double, Double)] = [(0, -15), (-15, 0), (0, 0), (15, 0), (0, 15)]
    var body: some View {
        ZStack {
            ForEach(Array(Self.holes.enumerated()), id: \.offset) { _, hole in
                Circle().fill(Color(white: 0.02)).frame(width: 7.5, height: 7.5).offset(x: hole.0, y: hole.1)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// The underside of the lower half: battery door, screws, the model plate.
/// Round 29: the shell's own colour, flat (the studio shades it).
struct BottomArt: View {
    var finish: ShellFinish
    var body: some View {
        ZStack {
            Rectangle().fill(finish.base)
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.black.opacity(0.35), lineWidth: 1.5)
                .frame(width: 420, height: 300).position(x: 380, y: 230)
            ForEach(Array([(190.0, 100.0), (570.0, 100.0), (190.0, 360.0), (570.0, 360.0)].enumerated()), id: \.offset) { _, screw in
                Circle().fill(Color(white: 0.08)).frame(width: 9, height: 9)
                    .overlay(Rectangle().fill(.white.opacity(0.25)).frame(width: 6, height: 1))
                    .position(x: screw.0, y: screw.1)
            }
            VStack(spacing: 3) {
                Text("ZERO").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(3)
                Text("FOLDING HANDHELD · MODEL FA-01").font(.system(size: 6, weight: .semibold, design: .monospaced))
                Text(verbatim: "ORIGINAL DESIGN").font(.system(size: 5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(finish.ink.opacity(0.8)).position(x: 380, y: 230)
            // Inlet grille for the speaker chamber.
            HStack(spacing: 5) {
                ForEach(0..<9) { _ in Capsule().fill(.black.opacity(0.5)).frame(width: 2, height: 26) }
            }.position(x: 90, y: 230)
        }
        .frame(width: 760, height: 440)
        .background(finish.base)
    }
}

/// The outside of the lid as the solid wears it (round 29). The closed
/// console's drawing (FullScreenClosedShellArtwork) is a picture of a lit
/// lid — a sheen, a streak, the hinge drawn along its top — and printed on
/// the solid that light was painted under the studio's. Here: the shell's
/// colour, the debossed wordmark (or the retro grey's own print), the two
/// outer cameras and the light between them, the latch's notch.
struct LidCoverArt: View {
    var finish: ShellFinish
    var body: some View {
        ZStack {
            Rectangle().fill(finish.base)
            if finish == .retro {
                RoundedRectangle(cornerRadius: 8).fill(RetroHardwareInk.panel)
                    .frame(width: 638, height: 172).position(x: 380, y: 141)
                VStack(alignment: .leading, spacing: 7) {
                    Text("ZERO").font(.system(size: 30, weight: .heavy, design: .rounded)).tracking(2)
                    Text("FOLDING HANDHELD").font(.system(size: 11, design: .monospaced))
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 320, height: 2)
                }.foregroundStyle(RetroHardwareInk.print).position(x: 334, y: 141)
                RetroArcMark(unit: 1).frame(width: 365, height: 66).position(x: 380, y: 308)
                HStack(spacing: 4) {
                    ForEach(0..<4) { _ in Capsule().fill(RetroHardwareInk.capsule).frame(width: 10, height: 21) }
                }.rotationEffect(.degrees(-30)).position(x: 669, y: 66)
                HStack(spacing: 4) {
                    ForEach(0..<10) { _ in Rectangle().fill(finish.dark.opacity(0.65)).frame(width: 1, height: 26) }
                }.position(x: 638, y: 387)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZERO").font(.system(size: 12, weight: .heavy)).italic()
                    Text("TWO SCREENS · ONE FOLD").font(.system(size: 5, weight: .semibold))
                }.foregroundStyle(RetroHardwareInk.ink).position(x: 152, y: 383)
            } else {
                // Debossed wordmark: a dark impression with a light lower edge.
                ZStack {
                    Text("ZERO").font(.system(size: 18, weight: .medium, design: .rounded)).tracking(5)
                        .foregroundStyle(.white.opacity(finish.isLight ? 0.9 : 0.16)).offset(y: 0.8)
                    Text("ZERO").font(.system(size: 18, weight: .medium, design: .rounded)).tracking(5)
                        .foregroundStyle(.black.opacity(finish.isLight ? 0.28 : 0.45))
                }
                .position(x: 380, y: 220)
            }
            // Outer cameras with the recording light between them.
            ForEach([0.39, 0.61], id: \.self) { fraction in
                lens(12).position(x: 760 * fraction, y: 421)
            }
            Circle().fill(Color(white: 0.05)).frame(width: 4, height: 4).position(x: 380, y: 421)
            // The latch's notch at the front edge.
            Capsule().fill(Color(white: 0.02)).frame(width: 72, height: 3).position(x: 380, y: 436)
        }
        .frame(width: 760, height: 440)
        .background(finish.base)
    }
    private func lens(_ diameter: Double) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            Circle().fill(RadialGradient(colors: [Color(red: 0.14, green: 0.27, blue: 0.38), Color(red: 0.03, green: 0.07, blue: 0.11), .black],
                                         center: UnitPoint(x: 0.42, y: 0.4), startRadius: 0, endRadius: diameter * 0.38)).padding(diameter * 0.2)
            Circle().fill(.white.opacity(0.4)).frame(width: diameter * 0.14).offset(x: -diameter * 0.15, y: -diameter * 0.16)
        }.frame(width: diameter, height: diameter)
    }
}

/// A key's letter in its colour on the dark cap.
struct KeyLetterArt: View {
    var letter: String
    var color: Color
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
            Text(letter).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(color)
        }
        .frame(width: 36, height: 36)
        .background(Color(white: 0.1))
    }
}

/// The console's upper screen in the library (round 20): the clock, the
/// date and the battery along the top, under it what is chosen on the touch
/// screen — the card's software, one of the console's functions, or the
/// console's name when nothing is.
struct ConsoleHomeTopArt: View {
    var state: ConsoleHomeState
    private static let chinese = UILanguage.locale
    private var date: Date { Date(timeIntervalSince1970: Double(state.minute) * 60) }
    var body: some View {
        ZStack {
            SystemMenuBackdrop()
            VStack(spacing: 0) {
                status
                Spacer(minLength: 0)
                banner.padding(.horizontal, 34)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 500, height: 300)
        .foregroundStyle(SystemMenuStyle.ink)
        .environment(\.colorScheme, .light)
    }
    private var status: some View {
        HStack(spacing: 8) {
            MenuArcMark(size: 16, color: .white)
            Text(state.setupPending ? "初始设置" : "主菜单").font(.system(size: 12, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
            // Formatted to strings: Text(_:format:) would take the locale of
            // the environment (English in the Simulator), not the format's.
            Text(date.formatted(.dateTime.locale(Self.chinese).month(.abbreviated).day().weekday(.abbreviated)))
                .font(.system(size: 12, weight: .semibold))
            Text(date.formatted(.dateTime.locale(Self.chinese).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            if let level = state.battery {
                Text("\(Int((level * 100).rounded()))%").font(.system(size: 11, weight: .semibold, design: .monospaced))
                MenuBatteryGlyph(level: level, charging: state.charging, s: 1.3)
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(SystemMenuStyle.status)
    }
    @ViewBuilder private var banner: some View {
        if state.setupPending {
            setupBanner
        } else if let shortcut = state.shortcut {
            shortcutBanner(shortcut)
        } else {
            switch state.selection {
            case .card?: cardBanner
            case let item?: itemBanner(item)
            case nil: idleBanner
            }
        }
    }
    /// The console switched on for the first time (round 23).
    private var setupBanner: some View {
        VStack(spacing: 12) {
            MenuArcMark(size: 70, color: SystemMenuStyle.ink)
            Text("你好！").font(.system(size: 36, weight: .heavy, design: .rounded))
            Text("这台主机第一次开机，先做一下初始设置")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
        }
    }
    @ViewBuilder private var cardBanner: some View {
        if let card = state.card {
            HStack(alignment: .center, spacing: 24) {
                ConsoleHomeIcon(card: card, size: 108)
                VStack(alignment: .leading, spacing: 7) {
                    Text(card.title).font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                    Text(card.subtitle).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft).lineLimit(1)
                    if state.suspended {
                        Text("暂停中 · 按 HOME 或「继续」回到软件").font(.system(size: 13, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
                    } else if state.coreMissing, !card.isDemo {
                        Text("这个构建没有附带 3DS 模拟核心，不能开启").font(.system(size: 13, weight: .semibold)).foregroundStyle(SystemMenuStyle.stop)
                    } else if let left = state.resumeDate, !card.isDemo {
                        Text("上次离开于 \(left.formatted(.dateTime.locale(Self.chinese).month(.abbreviated).day().hour().minute(.twoDigits)))")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
                    } else {
                        // Round 26: the demo's too (its subtitle above already
                        // says 原创演示 · 内置; it was there twice).
                        Text("点「开启」或按 A 开始").font(.system(size: 13, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                CardShellShape(cut: 9).stroke(SystemMenuStyle.inkSoft.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    .frame(width: 66, height: 70)
                Text(state.looseTitle == nil ? "没有卡带" : "卡带没插到底").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(state.looseTitle.map { state.onHandheld ? "回到游戏库，在掌机背面把「\($0)」推进去" : "在掌机背面把「\($0)」推进去，咔嗒一声就好" }
                     ?? (state.onHandheld ? "回到游戏库，从架子上拿一张卡带插进来" : "从下面的架子拿起一张卡带，放到掌机上"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft).multilineTextAlignment(.center)
            }
        }
    }
    private func itemBanner(_ item: ConsoleHomeItem) -> some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SystemMenuStyle.tile)
                    .shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 2.5)
                Image(systemName: item.symbol).font(.system(size: 46, weight: .medium)).foregroundStyle(ConsoleHomeTileArt.tint(item))
            }
            .frame(width: 108, height: 108)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(item.blurb).font(.system(size: 14, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if item == .modes {
                    Label("现在：\(state.mode.title)", systemImage: state.mode.symbol)
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func shortcutBanner(_ shortcut: ConsoleHomeShortcut) -> some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SystemMenuStyle.tile)
                    .shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 2.5)
                Image(systemName: shortcut.symbol(in: state)).font(.system(size: 44, weight: .medium)).foregroundStyle(SystemMenuStyle.ink)
            }
            .frame(width: 108, height: 108)
            VStack(alignment: .leading, spacing: 8) {
                Text(shortcut.title(in: state)).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(shortcut.blurb(in: state)).font(.system(size: 14, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var idleBanner: some View {
        VStack(spacing: 12) {
            MenuArcMark(size: 86, color: SystemMenuStyle.ink)
            Text("ZERO").font(.system(size: 34, weight: .heavy, design: .rounded)).tracking(8)
            Text(date.formatted(.dateTime.locale(Self.chinese).year().month().day().weekday(.wide)))
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
        }
    }
}

/// A software's icon as the menu shows it: its own (SMDH), the demo's mark,
/// or a plain one.
struct ConsoleHomeIcon: View {
    var card: GameCardInfo
    var size: Double
    var body: some View {
        Group {
            if let icon = card.icon {
                Image(decorative: icon, scale: 1).resizable().interpolation(.high)
            } else if card.isDemo {
                SplashMark().background(Palette.panel)
            } else if let tint = card.cartridge?.tint {
                // A 典藏卡带's: a square of its metal with the card's own mark.
                ZStack {
                    LinearGradient(colors: [tint.iconLight, tint.iconMid, tint.iconDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                    MenuArcMark(size: size * 0.46, color: tint.mark)
                }
            } else {
                Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.4)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(SystemMenuStyle.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .shadow(color: SystemMenuStyle.ink.opacity(0.35), radius: size * 0.05, y: size * 0.03)
    }
}

/// The console's touch screen in the library (round 20): the tiles — the
/// card in the slot first, then the camera (round 25) and the console's own
/// functions — and the bar with the buttons for what is chosen.
struct ConsoleHomeBottomArt: View {
    var state: ConsoleHomeState
    var body: some View {
        if state.setupPending { setup } else { menu }
    }
    /// Not set up yet (round 23): one big way in.
    private var setup: some View {
        ZStack(alignment: .topLeading) {
            SystemMenuBackdrop()
            VStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 34, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
                Text("主机初始设置").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.ink)
                Text("语言、日期和时间、用户名、生日、国家/地区\n设好以后，主菜单就能用了")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 400)
            .position(x: 200, y: 98)
            HStack(spacing: 8) {
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 16, weight: .bold))
                Text("开始设置").font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(width: ConsoleHomeLayout.setupButton.width, height: ConsoleHomeLayout.setupButton.height)
            .background(Capsule().fill(LinearGradient(colors: [SystemMenuStyle.go, SystemMenuStyle.go.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1)))
            .overlay(Capsule().strokeBorder(SystemMenuStyle.accent, lineWidth: 3.5).padding(-5).shadow(color: SystemMenuStyle.accent.opacity(0.5), radius: 4))
            .position(x: ConsoleHomeLayout.setupButton.midX, y: ConsoleHomeLayout.setupButton.midY)
            Text("点屏幕或按 A").font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                .position(x: 200, y: 268)
        }
        .frame(width: 400, height: 300)
        .environment(\.colorScheme, .light)
    }
    private var menu: some View {
        let row = state.shortcuts
        return ZStack(alignment: .topLeading) {
            SystemMenuBackdrop()
            // Round 30: the small icons along the top while software is
            // suspended under the menu.
            ForEach(Array(row.enumerated()), id: \.element) { index, shortcut in
                let rect = ConsoleHomeLayout.shortcut(index, of: row.count)
                ConsoleHomeShortcutArt(shortcut: shortcut, selected: state.shortcut == shortcut, state: state)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            ForEach(ConsoleHomeLayout.items(onHandheld: state.onHandheld, page: state.page)) { item in
                let rect = ConsoleHomeLayout.tile(item, onHandheld: state.onHandheld, shortcuts: !row.isEmpty)
                ConsoleHomeTileArt(item: item, state: state)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            if state.selection == nil, state.shortcut == nil {
                Text("点一下图标选中 · 再点一下或按 A 打开")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(SystemMenuStyle.inkSoft)
                    .position(x: 200, y: row.isEmpty ? 233 : 241)
            }
            // Round 32: the page dots (a swipe or the D-pad turns the page).
            let pages = state.pageCount
            if pages > 1 {
                ForEach(0..<pages, id: \.self) { page in
                    let dot = ConsoleHomeLayout.pageDot(page, of: pages)
                    Circle().fill(page == state.page ? SystemMenuStyle.ink : SystemMenuStyle.inkSoft.opacity(0.35))
                        .frame(width: dot.width, height: dot.height)
                        .position(x: dot.midX, y: dot.midY)
                }
            }
            // The bar is drawn past the picture's sides and its foot: on a
            // screen wider or taller than the picture (the picture is fitted
            // into it whole) the bar still reaches the screen's edges.
            ZStack(alignment: .top) {
                Rectangle().fill(SystemMenuStyle.bar)
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
            .frame(width: ConsoleHomeLayout.bar.width + 240, height: ConsoleHomeLayout.bar.height + 120)
            .position(x: ConsoleHomeLayout.bar.midX, y: ConsoleHomeLayout.bar.midY + 60)
            let bar = state.bar
            if let left = bar.left {
                button(left).position(x: ConsoleHomeLayout.leftButton.midX, y: ConsoleHomeLayout.leftButton.midY)
            }
            if let right = bar.right {
                button(right).position(x: ConsoleHomeLayout.rightButton.midX, y: ConsoleHomeLayout.rightButton.midY)
            }
            if bar.left == nil, bar.right == nil, state.selection == .card {
                Text(state.card == nil ? "没有卡带" : "不能开启")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                    .position(x: ConsoleHomeLayout.bar.midX, y: ConsoleHomeLayout.bar.midY)
            }
            if let shortcut = state.shortcut {
                Text("\(shortcut.title(in: state)) · 点一下或按 A")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.75))
                    .position(x: ConsoleHomeLayout.bar.midX, y: ConsoleHomeLayout.bar.midY)
            }
        }
        .frame(width: 400, height: 300)
        .environment(\.colorScheme, .light)
    }
    private func button(_ action: ConsoleHomeAction) -> some View {
        let color = action == .closeGame ? SystemMenuStyle.stop : action.isQuiet ? SystemMenuStyle.inkSoft : SystemMenuStyle.go
        return HStack(spacing: 7) {
            Image(systemName: action.symbol).font(.system(size: 13, weight: .bold))
            Text(action.title).font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: ConsoleHomeLayout.rightButton.width, height: ConsoleHomeLayout.rightButton.height)
        .background(
            Capsule().fill(LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        )
    }
}

/// One tile of the touch screen.
struct ConsoleHomeTileArt: View {
    var item: ConsoleHomeItem
    var state: ConsoleHomeState
    static func tint(_ item: ConsoleHomeItem) -> Color {
        switch item {
        case .card, .settings: return SystemMenuStyle.ink
        case .camera: return Color(red: 0.42, green: 0.30, blue: 0.62)
        case .album: return Color(red: 0.80, green: 0.45, blue: 0.20)
        case .importFiles: return SystemMenuStyle.accent
        case .activity: return SystemMenuStyle.go
        case .theme: return SystemMenuStyle.stop
        case .manual: return SystemMenuStyle.inkSoft
        case .modes: return Color(red: 0.13, green: 0.50, blue: 0.62)
        case .pictureFrame: return Color(red: 0.27, green: 0.31, blue: 0.62)
        case .tinBox: return Color(red: 0.70, green: 0.20, blue: 0.22)
        }
    }
    var body: some View {
        let selected = state.selection == item
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                shape.fill(SystemMenuStyle.tile)
                    .shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 2)
                shape.strokeBorder(SystemMenuStyle.tileEdge.opacity(0.55), lineWidth: 1)
                icon
            }
            .frame(width: 72, height: 64)
            .overlay {
                if selected {
                    shape.strokeBorder(SystemMenuStyle.accent, lineWidth: 3.5).padding(-4)
                        .shadow(color: SystemMenuStyle.accent.opacity(0.5), radius: 4)
                }
            }
            Text(title).font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(SystemMenuStyle.ink).lineLimit(1).minimumScaleFactor(0.55)
                .frame(width: ConsoleHomeLayout.tileSize.width - 4)
        }
        .frame(width: ConsoleHomeLayout.tileSize.width, height: ConsoleHomeLayout.tileSize.height)
    }
    private var title: String {
        guard item == .card else { return item.title }
        if let card = state.card { return card.title }
        return state.looseTitle == nil ? String(localized: "没有卡带") : String(localized: "没插到底")
    }
    @ViewBuilder private var icon: some View {
        if item == .card {
            if let card = state.card {
                GameCardFace(card: card, s: 1).frame(width: 49, height: 49 * CardDimensions.aspect)
            } else {
                CardShellShape(cut: 6).stroke(SystemMenuStyle.inkSoft.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 38, height: 40)
            }
        } else {
            Image(systemName: item.symbol).font(.system(size: 27, weight: .medium)).foregroundStyle(Self.tint(item))
        }
    }
}

/// One of the small icons along the top of the menu (round 30); round 31:
/// its name under it.
struct ConsoleHomeShortcutArt: View {
    var shortcut: ConsoleHomeShortcut
    var selected: Bool
    /// The menu's state (按键点屏 on, 倍速: their icons show it).
    var state = ConsoleHomeState()
    private var on: Bool { shortcut == .keyTaps ? state.keyTaps : shortcut == .speed ? state.speed > 1 : false }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            shape.fill(SystemMenuStyle.tile).shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 1.5)
            shape.strokeBorder(SystemMenuStyle.tileEdge.opacity(0.55), lineWidth: 1)
            VStack(spacing: 2) {
                Image(systemName: shortcut.symbol(in: state)).font(.system(size: 13, weight: .semibold)).frame(height: 15)
                Text(shortcut == .speed && state.speed > 1 ? String(localized: "倍速 \(Int(state.speed))×") : shortcut == .slots ? shortcut.title(in: state) : shortcut.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(SystemMenuStyle.ink)
            .padding(.horizontal, 3)
        }
        .overlay {
            if selected {
                shape.strokeBorder(SystemMenuStyle.accent, lineWidth: 3).padding(-3.5)
                    .shadow(color: SystemMenuStyle.accent.opacity(0.5), radius: 3)
            }
        }
        // 按键点屏 on, 倍速 above 1×: a small green light in the corner;
        // 倍速 without Pro: a small lock there.
        .overlay(alignment: .topTrailing) {
            if on {
                Circle().fill(Color(red: 0.2, green: 0.72, blue: 0.4)).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .padding(4)
            } else if shortcut == .speed, state.speedLocked {
                ProLockBadge(size: 11).padding(2)
            }
        }
    }
}

// MARK: - The game card

/// FoldArc's own game card: a small near-square card with the label on the
/// front, a chamfered corner as the orientation key, a grip ridge on the
/// top edge and the contacts along the bottom edge. The card is
/// about 33 × 35 mm, label up; the shape,
/// the ridge and the mark are FoldArc's.
struct GameCardFace: View {
    var card: GameCardInfo
    var s: Double
    /// The card seen flat from the front, drawn after the solid (round 28,
    /// CardModel3D after CardLayout: 187 × 176, the paper label in its
    /// recess, the fine grip along the top, the arrow). Used small on the
    /// console's menu, for the solid's reflection and on the Mac preview's
    /// shelf.
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let W = CardLayout.width, H = CardLayout.length
            let k = w / W
            // Design units of the solid (y up there, down here).
            let x = { (v: Double) in w * (v + W / 2) / W }
            let y = { (v: Double) in h * (H / 2 - v) / H }
            let shell = CardShellShape(cut: CardLayout.cut * k, radius: CardLayout.cornerRadius * k)
            ZStack {
                // Round 29: the light grey of the solid's plastic (a 典藏卡带's card: its metal).
                shell.fill(LinearGradient(colors: card.cartridge.map { [$0.tint.shellLight, $0.tint.shellDark] }
                                                  ?? [Color(red: 0.76, green: 0.765, blue: 0.77), Color(red: 0.62, green: 0.625, blue: 0.63)], startPoint: .topLeading, endPoint: .bottomTrailing))
                shell.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.5, 1.2 * k))
                // The grip's fine ribs along the top.
                Path { p in
                    let span = Double(CardLayout.ribCount - 1) * CardLayout.ribPitch + CardLayout.ribWidth
                    for i in 0..<CardLayout.ribCount {
                        let rx = CardLayout.ribsCentreX - span / 2 + Double(i) * CardLayout.ribPitch
                        p.addRoundedRect(in: CGRect(x: x(rx), y: y(CardLayout.ribsTop), width: CardLayout.ribWidth * k, height: (CardLayout.ribsTop - CardLayout.ribsBottom) * k),
                                         cornerSize: CGSize(width: 0.8 * k, height: 0.8 * k))
                    }
                }
                .fill(LinearGradient(colors: [Color(white: 0.84), Color(white: 0.58)], startPoint: .top, endPoint: .bottom))
                // The way in, toward the contacts.
                Path { p in
                    p.addLines(CardLayout.arrow.map { CGPoint(x: x(Double($0.x)), y: y(Double($0.y))) })
                    p.closeSubpath()
                }
                .fill(Color(white: 0.56))
                // The label's recess, and the paper label in it.
                RoundedRectangle(cornerRadius: (CardLayout.labelCornerRadius + 1.2) * k, style: .continuous)
                    .fill(Color(white: 0.52))
                    .frame(width: CardLayout.wellSize.width * k, height: CardLayout.wellSize.height * k)
                    .position(x: x(0), y: y(CardLayout.labelCentreY))
                GameCardLabelArt(card: card)
                    .frame(width: CardLayout.labelSize.width * k, height: CardLayout.labelSize.height * k)
                    .clipShape(RoundedRectangle(cornerRadius: CardLayout.labelCornerRadius * k, style: .continuous))
                    .position(x: x(0), y: y(CardLayout.labelCentreY))
            }
        }
        .aspectRatio(CGFloat(CardLayout.width / CardLayout.length), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The back of a game card (round 20): it faces up in the slot, the label
/// facing the bottom of the console. Seen from this side the cut corner is
/// on the right; the wordmark and the arrow toward the contacts are
/// moulded in.
struct GameCardBackArt: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let shell = CardShellShape(cut: w * 0.13)
            ZStack {
                shell.fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.67)], startPoint: .topTrailing, endPoint: .bottomLeading))
                    .scaleEffect(x: -1, y: 1)
                shell.strokeBorder(.black.opacity(0.3), lineWidth: max(1, w * 0.012))
                    .scaleEffect(x: -1, y: 1)
                HStack(spacing: w * 0.018) {
                    ForEach(0..<14) { _ in Capsule().fill(.black.opacity(0.18)).frame(width: w * 0.022, height: h * 0.045) }
                }
                .position(x: w * 0.44, y: h * 0.055)
                RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
                    .strokeBorder(.black.opacity(0.12), lineWidth: max(1, w * 0.01))
                    .frame(width: w * 0.72, height: h * 0.5)
                    .position(x: w * 0.5, y: h * 0.48)
                Text("ZERO").font(.system(size: w * 0.085, weight: .heavy, design: .rounded)).tracking(w * 0.02)
                    .foregroundStyle(.black.opacity(0.26)).position(x: w * 0.5, y: h * 0.42)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.44, y: h * 0.56))
                    p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.56))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.65))
                    p.closeSubpath()
                }
                .fill(.black.opacity(0.24))
            }
        }
        .aspectRatio(35 / 37, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The card's outline: rounded, with the top-left corner cut as the key.
struct CardShellShape: InsettableShape {
    var cut: Double
    /// The other corners' radius (round 28: the real card's; by default
    /// 0.07 of the shorter side, as before).
    var radius: Double? = nil
    var inset = 0.0
    func inset(by amount: CGFloat) -> CardShellShape { var s = self; s.inset += amount; return s }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = self.radius.map { max(0, $0 - inset) } ?? min(r.width, r.height) * 0.07
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }
}
