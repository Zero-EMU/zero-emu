import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import AVFoundation
import OSLog
#endif

// The console's built-in software (round 23): 系统设置 and the first-time
// setup run on the handheld like any software — both screens are theirs,
// the D-pad moves the cursor, A decides, B goes back, HOME and POWER leave.
// They are started from the console's menu in the library (设置), or by the
// library itself the first time the console is switched on. The structure
// is a handheld's system settings; names, drawings and marks are FoldArc's.

/// What the software needs from outside it.
struct ConsoleAppContext {
    /// The library's software, for 数据管理.
    var games: [GameRecord]
    var remove: (GameRecord) -> Void
    /// The console it runs on: the MIC, the Circle Pad, the 3D slider.
    var session: DemoSession
    /// Homebrew test files in the data folder's CoreTest (developer aid,
    /// listed in 数据管理 when there are any), and the way to start one.
    var testFiles: [URL] = []
    var launchTestFile: (URL) -> Void = { _ in }
    /// Round 31: 系统设置 opened from HOME over suspended software (in
    /// place): its name, and its record in the library (nil for
    /// the demo). 格式化 and removing it wait until it is closed.
    var suspended: String? = nil
    var suspendedID: String? = nil
    /// Round 31: 游玩模式 in a game — the mode on screen and what goes with
    /// it; nil in the library, where the choice is for the next game.
    var play: PlayModeContext? = nil
}

/// What 游玩模式 works with in a game (PlayView).
struct PlayModeContext {
    var mode: ScreenLayout
    var setMode: (ScreenLayout) -> Void
    /// 掌机模式: guides along the screens' edges.
    var showGuides: Binding<Bool>
    /// 掌机模式 on an iPhone with no fold: where the pretend fold is.
    var foldFraction: Binding<Double>?
    var foldGap: Binding<Double>?
    /// An iPhone with no hinge: the closed console's outer screen.
    var closeLid: (() -> Void)?
}

// MARK: - Model

@MainActor final class ConsoleAppModel: ObservableObject {
    enum PinPurpose: Hashable { case create, confirm, unlock, change, changeConfirm }
    enum Page: Hashable {
        case root, internet
        case parental, parentalPIN(PinPurpose), parentalQuestion, parentalAnswer, parentalRestrictions, parentalForgot
        case data, dataSoftware, dataGame(String), dataStates, dataStorage, dataTests
        case other, profile, profileName, profileBirthday, profileCountry, profileRegion
        case dateTime, touch, touchCalibrate, circlePad, sound, mic, language, screen3D
        case power, brightness, rendering, haptics, about, licenses, eula, update, format
        /// TV输出 (round 30).
        case tv
        /// 游玩模式 › 选电视 (b41).
        case tvSet
        case setupWelcome, setupLanguage, setupDateTime, setupName, setupBirthday, setupCountry, setupFinish
        /// Round 30: 游戏记录, 主题 and 说明书 as programs of their own (their
        /// first pages), and one of the manual's sections.
        case activity, theme, manual, manualSection(Int)
        /// Round 31: 游玩模式 (a program of the menu), 主题's 机身配色;
        /// 其他设置's fifth page: 画面滤镜, 手柄.
        case modes, finish, filter, gamepad
        /// 11-07: 主题 › 手柄样式 (the controller's button for it is gone).
        case skins
        /// 11-11: 主题 › 删除方式 (what a card taken over the shelf's edge
        /// goes into: DeleteStyle).
        case deleteStyle
        /// 主题 › 铅笔盒: the pencil box's style and colour (PencilBoxLook).
        case pencilBox
        /// 数据管理 › 存档同步 (round 31).
        case dataSync
        /// 数据管理 › 备份 (11-07): the saves exported as a zip, and back.
        case dataBackup
        /// 其他设置 › 开发者 (round 31; it
        /// was a small icon of HOME's): a debug build's switches.
        case developer
        /// Zero EMU Pro: what it opens, the three prices, 恢复购买 (the first
        /// page's last item; a lock anywhere opens it too).
        case pro
        /// 存档位: which of the running game's numbered places 保存进度 and
        /// 读取进度 use (HOME's small icon opens it in place).
        case stateSlot
        /// 金卡带's films (its card started on the console, or the last row
        /// of 金卡带's page): the film on the upper screen, which one and the
        /// way to the next on the lower.
        case reel
        /// 卡带证: the card playing, its number, the day it became the
        /// player's, 首发版 (金卡带 bought at the launch price).
        case cartridgePass
        /// 开箱仪式 (Unboxing.swift): the box of a card just bought, opened.
        case unbox
        /// 画框 (PictureFrame.swift): the scenery on the upper screen, the
        /// clock and its switches on the lower.
        case pictureFrame
        /// 铅笔盒 (PencilBox.swift; it was 铁皮盒): the inside of the lid on
        /// the upper screen, the tray on the lower.
        case tinBox
        /// 其他设置 › 主菜单顶上的按键 (11-15): which small icons the menu's
        /// top row has.
        case homeRow

        var title: String {
            switch self {
            case .root: return String(localized: "系统设置")
            case .internet: return String(localized: "互联网设置")
            case .parental, .parentalPIN, .parentalQuestion, .parentalAnswer, .parentalRestrictions: return String(localized: "家长控制")
            case .parentalForgot: return String(localized: "忘记密码")
            case .data: return String(localized: "数据管理")
            case .dataSoftware: return String(localized: "软件")
            case .dataGame: return String(localized: "软件详情")
            case .dataStates: return String(localized: "data.states.title")
            case .dataStorage: return String(localized: "主机存储")
            case .dataTests: return String(localized: "核心测试文件")
            case .other: return String(localized: "其他设置")
            case .profile: return String(localized: "用户信息")
            case .profileName: return String(localized: "用户名")
            case .profileBirthday: return String(localized: "生日")
            case .profileCountry: return String(localized: "国家/地区")
            case .profileRegion: return String(localized: "主机区域")
            case .dateTime: return String(localized: "日期和时间")
            case .touch: return shownName("触摸屏")
            case .touchCalibrate: return String(localized: "触摸屏校正")
            case .circlePad: return String(localized: "摇杆")
            case .sound: return String(localized: "声音")
            case .mic: return String(localized: "麦克风测试")
            case .language: return String(localized: "语言")
            case .screen3D: return String(localized: "3D 画面")
            case .power: return String(localized: "省电模式")
            case .brightness: return String(localized: "屏幕亮度")
            case .rendering: return String(localized: "画面渲染")
            case .haptics: return String(localized: "按键震动")
            case .homeRow: return String(localized: "主菜单顶上的按键")
            case .about: return String(localized: "关于本机")
            case .licenses: return String(localized: "开源许可")
            case .eula: return String(localized: "用户协议")
            case .update: return String(localized: "系统更新")
            case .format: return String(localized: "格式化主机")
            case .tv: return String(localized: "TV输出")
            case .tvSet: return String(localized: "选电视")
            case .setupWelcome: return String(localized: "欢迎")
            case .setupLanguage: return String(localized: "语言")
            case .setupDateTime: return String(localized: "日期和时间")
            case .setupName: return String(localized: "用户名")
            case .setupBirthday: return String(localized: "生日")
            case .setupCountry: return String(localized: "国家/地区")
            case .setupFinish: return String(localized: "完成")
            case .activity: return String(localized: "游戏记录")
            case .theme: return String(localized: "主题")
            case .manual: return String(localized: "说明书")
            case .manualSection(let index): return ManualText.section(index).title
            case .modes: return String(localized: "游玩模式")
            case .finish: return String(localized: "机身配色")
            case .skins: return String(localized: "手柄样式")
            case .deleteStyle: return String(localized: "删除方式")
            case .pencilBox: return String(localized: "铅笔盒")
            case .filter: return String(localized: "画面滤镜")
            case .gamepad: return String(localized: "手柄")
            case .dataSync: return String(localized: "存档同步")
            case .dataBackup: return String(localized: "备份")
            case .developer: return String(localized: "开发者")
            case .pro: return String(localized: "典藏卡带")
            case .stateSlot: return String(localized: "存档位")
            case .reel: return String(localized: "小时候")
            case .cartridgePass: return String(localized: "卡带证")
            case .unbox: return String(localized: "开箱")
            case .pictureFrame: return String(localized: "画框")
            case .tinBox: return String(localized: "铅笔盒")
            }
        }
        /// Where the page stands in the first-time setup (1-based), or nil.
        var setupStep: Int? {
            let steps: [Page] = [.setupWelcome, .setupLanguage, .setupDateTime, .setupName, .setupBirthday, .setupCountry, .setupFinish]
            return steps.firstIndex(of: self).map { $0 + 1 }
        }
    }
    struct Dialog {
        var title: String
        var message: String
        var confirm: String
        var destructive = true
        var identifier = "dialog-confirm"
        var action: () -> Void
    }
    static let barLeft = "app.bar.left"
    static let barRight = "app.bar.right"
    static let setupSteps = 7

    let app: ConsoleApp
    @Published private(set) var stack: [Page]
    @Published var focus: String? { didSet { focusKeyed = takingKey } }
    /// The cursor is where a key put it (a touch that moves it clears this):
    /// 铅笔盒 shows its cursor only then, so a touch leaves no mark there.
    private(set) var focusKeyed = false
    private var takingKey = false
    @Published var dialog: Dialog? { didSet { if dialog != nil { focus = "dialog.cancel" } } }
    /// The profile being set up or edited.
    @Published var draft: ConsoleProfile
    /// Digits typed on the PIN pad; the first PIN while it is confirmed.
    @Published var pin = ""
    @Published var firstPin = ""
    @Published var pinNote: String?
    /// The secret answer being typed (set up or answered).
    @Published var answer = ""
    /// 其他设置 has pages of four.
    @Published var otherPage = 0
    /// 触摸屏校正: where each target was touched; the trial area's dots.
    @Published var calibrationTouches: [Point] = []
    @Published var trialTouches: [Point] = []
    /// The PIN was given in this visit to 家长控制.
    @Published var unlocked = false
    /// A short line over the bar ("已保存").
    @Published var toast: String?
    /// What the last purchase or 恢复购买 came to, on 典藏卡带's page: it
    /// stays while the page is on the stack (the box and the films opened
    /// from it come back to it) and is gone when the page is opened afresh.
    @Published var proNote: String?
    /// Plain storage the page on screen fills in while drawing (as HOME's).
    var layout: [[String]] = []
    var handlers: [String: () -> Void] = [:]
    var adjusters: [String: (Int) -> Void] = [:]
    /// L / R on a page that has pages.
    var pageTurner: ((Int) -> Void)?
    var leave: () -> Void = {}
    /// The console the program runs on (its 3D slider goes down when
    /// parental controls restrict 3D).
    weak var session: DemoSession?
    private var returnFocus: [String?] = []
    private var toastStamp = 0
    /// Where the cursor goes on the page on screen when it has none there
    /// (set while the page draws; the cursor itself is moved after the
    /// drawing, not during it: a change published from inside a view
    /// update is not allowed).
    private var initialFocus: String?
    private var settleScheduled = false
    private var deferredKey = false

    /// `page`: where it starts instead of its first page (round 31: 屏幕亮度
    /// from the menu's small icon; B there leaves).
    init(app: ConsoleApp, page: Page? = nil) {
        self.app = app
        stack = [page ?? Self.firstPage(of: app)]
        draft = ConsoleSettings.shared.profile
    }
    /// Where each program starts.
    static func firstPage(of app: ConsoleApp) -> Page {
        switch app {
        case .setup: return .setupWelcome
        case .activity: return .activity
        case .theme: return .theme
        case .manual: return .manual
        case .modes: return .modes
        case .pictureFrame: return .pictureFrame
        case .tinBox: return .tinBox
        case .settings, .camera, .album, .notes, .home: return .root
        }
    }
    var page: Page { stack.last ?? .root }
    var trail: String { stack.map(\.title).joined(separator: " › ") }

    func push(_ next: Page) {
        returnFocus.append(focus)
        clear()
        // 其他设置 opened from the first page starts on its first page (coming
        // back to it from one of its items keeps the page it was on).
        if next == .other { otherPage = 0 }
        if next == .pro { proNote = nil }
        stack.append(next)
        focus = nil
        ConsoleSounds.shared.play(.select)
    }
    /// B, or the bar's 返回: one page back; from the first page, out.
    func pop() {
        if page == .unbox {
            UnboxRun.shared.skip()
            UnboxScreen.finish(self)
            return
        }
        guard stack.count > 1 else { leave(); return }
        clear()
        stack.removeLast()
        focus = returnFocus.popLast() ?? nil
        ConsoleSounds.shared.play(.back)
    }
    /// Back to `page` if it is on the stack (after a flow of several pages).
    func pop(to target: Page) {
        guard let index = stack.lastIndex(of: target) else { return }
        clear()
        let removed = stack.count - 1 - index
        stack.removeLast(removed)
        let kept = returnFocus.count - removed
        let focusBack = kept >= 0 && kept < returnFocus.count ? returnFocus[kept] : nil
        returnFocus.removeLast(min(removed, returnFocus.count))
        focus = focusBack
    }
    /// The next page of a flow in place of this one (the PIN's second entry).
    func replace(with next: Page) {
        clear()
        stack[stack.count - 1] = next
        focus = nil
    }
    private func clear() { layout = []; handlers = [:]; adjusters = [:]; pageTurner = nil; dialog = nil; initialFocus = nil }

    /// The page on screen has told what it holds (from its body): the
    /// cursor goes to `initial` once the drawing is done, if it is on
    /// nothing of this page.
    func registered(initial: String?) {
        initialFocus = initial
        guard !settleScheduled else { return }
        settleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settleScheduled = false
            self.settleFocus()
        }
    }
    private func settleFocus() {
        if let focus, focus.hasPrefix("dialog.") { return }
        if let focus, layout.contains(where: { $0.contains(focus) }) { return }
        guard let wanted = initialFocus ?? layout.first?.first, wanted != focus else { return }
        focus = wanted
    }

    func say(_ text: String) {
        toastStamp += 1
        let stamp = toastStamp
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            if toastStamp == stamp { withAnimation(.easeIn(duration: 0.25)) { toast = nil } }
        }
    }
    func confirm(_ dialog: Dialog) { self.dialog = dialog }

    /// A key from the console or a controller. Always taken: the software
    /// owns the console while it runs.
    @discardableResult func handle(_ key: PadButton, down: Bool) -> Bool {
        guard down else { return true }
        // (the cursor is the keys' from here on, until a touch moves it)
        if !focusKeyed { objectWillChange.send(); focusKeyed = true }
        takingKey = true
        defer { takingKey = false }
        // (画框: any key lights its lower screen again, and wakes it.)
        if page == .pictureFrame { PictureFrameRun.shared.touch() }
        // A page has just come and not yet said what it holds: the key
        // waits for it (once), rather than moving over nothing.
        if layout.isEmpty, dialog == nil, !deferredKey {
            deferredKey = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.handle(key, down: true)
                self.deferredKey = false
            }
            return true
        }
        if let dialog {
            switch key {
            case .left, .right, .up, .down: focus = focus == "dialog.confirm" ? "dialog.cancel" : "dialog.confirm"
            case .a:
                if focus == "dialog.confirm" { self.dialog = nil; dialog.action() } else { self.dialog = nil }
            case .b: self.dialog = nil
            default: break
            }
            ConsoleSounds.shared.play(.move)
            return true
        }
        #if DEBUG
        let before = focus
        defer { if Self.logsKeys { NSLog("[system] key %@ on %@: %@ -> %@", key.rawValue, String(describing: page), before ?? "-", focus ?? "-") } }
        #endif
        switch key {
        case .up: move(rows: -1)
        case .down: move(rows: 1)
        case .left: step(-1)
        case .right: step(1)
        case .a:
            if let focus, let action = handlers[focus] { action() }
            else if focus == nil { focus = layout.first?.first }
        case .b: pop()
        case .l: pageTurner?(-1)
        case .r: pageTurner?(1)
        default: break
        }
        return true
    }
    #if DEBUG
    /// `--foldarc-app-log`: each key the program takes, with the cursor.
    private static let logsKeys = ProcessInfo.processInfo.arguments.contains("--foldarc-app-log")
    #endif
    private func position(of id: String) -> (row: Int, column: Int)? {
        for (row, ids) in layout.enumerated() {
            if let column = ids.firstIndex(of: id) { return (row, column) }
        }
        return nil
    }
    private func move(rows delta: Int) {
        guard !layout.isEmpty else { return }
        guard let focus, let at = position(of: focus) else { self.focus = layout.first?.first; return }
        let row = min(layout.count - 1, max(0, at.row + delta))
        let ids = layout[row]
        let next = ids[min(at.column, ids.count - 1)]
        if next != focus { ConsoleSounds.shared.play(.move) }
        self.focus = next
    }
    private func step(_ delta: Int) {
        if let focus, let adjust = adjusters[focus] { adjust(delta); return }
        guard !layout.isEmpty else { return }
        guard let focus, let at = position(of: focus) else { self.focus = layout.first?.first; return }
        let ids = layout[at.row]
        if ids.count == 1, let turn = pageTurner { turn(delta); return }
        let next = ids[min(ids.count - 1, max(0, at.column + delta))]
        if next != focus { ConsoleSounds.shared.play(.move) }
        self.focus = next
    }
}

/// What an item on a page is and does, for the upper screen: the focused
/// item explains itself there, as on a handheld's settings.
enum AppItemInfo {
    /// The item that opens a page (its words stand for the page).
    static func key(for page: ConsoleAppModel.Page) -> String? {
        switch page {
        case .internet: return "root.internet"
        case .parental, .parentalAnswer, .parentalForgot: return "root.parental"
        case .data: return "root.data"
        case .dataSoftware, .dataGame: return "data.software"
        case .dataStates: return "data.states"
        case .dataStorage: return "data.storage"
        case .dataTests: return "data.tests"
        case .profile, .profileName, .profileBirthday, .profileCountry, .profileRegion: return "other.profile"
        case .dateTime: return "other.dateTime"
        case .touch: return "other.touch"
        case .circlePad: return "other.circlePad"
        case .sound: return "other.sound"
        case .mic: return "other.mic"
        case .language: return "other.language"
        case .screen3D: return "other.screen3D"
        case .power: return "other.power"
        case .brightness: return "other.brightness"
        case .rendering: return "other.rendering"
        case .haptics: return "other.haptics"
        case .homeRow: return "other.homeRow"
        case .about: return "other.about"
        case .eula: return "other.eula"
        case .update: return "other.update"
        case .format: return "other.format"
        case .filter: return "other.filter"
        case .gamepad: return "other.gamepad"
        case .developer: return "other.developer"
        case .dataSync: return "data.sync"
        case .dataBackup: return "data.backup"
        case .tv: return "root.tv"
        case .pro: return "root.pro"
        case .stateSlot: return "states.slot"
        default: return nil
        }
    }
    static let catalog: [String: (title: String, symbol: String, text: String)] = [
        "root.internet": (String(localized: "互联网设置"), "wifi", String(localized: "看看这台 iPhone 现在有没有网络。Zero EMU 没有账号，也没有自己的服务器：游戏、存档和设置都在本机；存档同步是可选的，走你自己的 iCloud。")),
        "root.parental": (String(localized: "家长控制"), "lock.fill", String(localized: "设一个 4 位密码，就能限制 3D 影像、导入软件、删除软件和数据。")),
        "root.data": (String(localized: "数据管理"), "externaldrive.fill", String(localized: "查看和删除游戏库里的软件、即时存档、继续进度，看主机存储用了多少。")),
        "root.tv": (String(localized: "TV输出"), "tv", String(localized: "接电视：AirPlay 屏幕镜像，或转接线。在电视上玩，到主菜单的「游玩模式」选 TV模式，电视也在那里选。")),
        "states.slot": (String(localized: "存档位"), "square.stack.3d.up", String(localized: "每个游戏有好几个存档位。「保存进度」存进选中的那一个，「读取进度」读的也是它；换一个存档位，原来那个里的进度还在。")),
        "root.pro": (String(localized: "典藏卡带"), "star.circle.fill", String(localized: "铜、银、金三张卡带，各放各的动画；有任何一张，就有全部机身配色、相机的全部机型、不限个数的存档位、存档同步、TV模式和倍速。月付、年付，或者一次买断；买过的也在这里恢复。")),
        "root.other": (String(localized: "其他设置"), "slider.horizontal.3", String(localized: "用户信息、日期和时间、手柄、语言、声音、麦克风、触摸屏、摇杆、画面滤镜、3D、省电、亮度、画面渲染、震动、主菜单顶上的按键、关于本机。")),
        "mode.handheld": (ScreenLayout.handheld.title, ScreenLayout.handheld.symbol, ScreenLayout.handheld.summary),
        "mode.tabletop": (ScreenLayout.tabletop.title, ScreenLayout.tabletop.symbol, ScreenLayout.tabletop.summary),
        "mode.controller": (ScreenLayout.controller.title, ScreenLayout.controller.symbol, ScreenLayout.controller.summary),
        "mode.tv": (ScreenLayout.tv.title, ScreenLayout.tv.symbol, ScreenLayout.tv.summary + String(localized: "接电视：控制中心 ›「屏幕镜像」。") + String(localized: "TV模式是典藏卡带的。")),
        "modes.guides": (String(localized: "屏幕边缘参考线"), "rectangle.dashed", String(localized: "掌机模式下在两块屏的边缘画参考线，看掌机和 iPhone 的折痕、圆角对得准不准。")),
        "modes.fold": (String(localized: "折叠位置"), "arrow.up.and.down", String(localized: "没有折痕的 iPhone 上，假装的折痕在屏幕高度的哪里。")),
        "modes.gap": (String(localized: "折叠预留"), "arrow.up.and.down.square", String(localized: "假装的折痕上下各空出多少。")),
        "modes.tvLayout": (String(localized: "电视上的布局"), "rectangle.split.1x2", String(localized: "现代电视上两块屏怎么摆：上下两屏、左右并排，或只显示上屏。（旧电视里只放上屏，下屏在 iPhone 上。）")),
        "modes.tvSet": (String(localized: "选电视"), "tv", String(localized: "TV模式在电视上画哪台电视：七台旧电视（游戏的上屏装在它的屏幕里），或者现代电视（不画外壳，画面铺满）。没接电视也能先选好。")),
        "modes.tvLook": (String(localized: "画面"), "sparkles", String(localized: "当年的画面：显像管的扫描线、早期液晶的发虚，像那时候看到的；最好的画面：像素清楚、颜色准，还是装在那台电视里。")),
        "modes.lid": (String(localized: "合上掌机"), "rectangle.compress.vertical", String(localized: "看合上盖子时的外屏；掀开就回来。（没有铰链的 iPhone）")),
        "other.profile": (String(localized: "用户信息"), "person.crop.circle", String(localized: "用户名、生日、国家/地区，和主机区域。")),
        "other.dateTime": (String(localized: "日期和时间"), "clock", String(localized: "主机的时间跟着这台 iPhone。")),
        "other.touch": (shownName("触摸屏"), "hand.point.up.left", String(localized: "点三个目标校正触摸位置，再在空白处试一试。")),
        "other.circlePad": (String(localized: "摇杆"), "circle.circle", String(localized: "看摇杆推到了哪里，调中间的死区。")),
        "other.sound": (String(localized: "声音"), "speaker.wave.2", String(localized: "立体声、单声道或环绕声；静音模式时出不出声，别的 App 放音乐时怎么办；也看耳机有没有接上。")),
        "sound.silent": (String(localized: "静音模式时也出声"), "speaker.slash", String(localized: "开着（默认）：iPhone 拨到静音，游戏照样出声，像掌机一样只听 VOL 滑块。关掉：跟着 iPhone 的静音走。")),
        "sound.others": (String(localized: "别的 App 在放音乐时"), "music.note", String(localized: "一起放：游戏和音乐混在一起。把音乐停掉：开始玩游戏时音乐停下，关掉游戏后它可以接着放。游戏不出声：音乐在放时游戏不出声。")),
        "other.mic": (String(localized: "麦克风测试"), "mic", String(localized: "对着 iPhone 吹气（或者按住掌机上的 MIC），看主机收到的声音。")),
        "other.language": (String(localized: "语言"), "character.bubble", String(localized: "菜单和软件用哪种语言显示。")),
        "other.screen3D": (String(localized: "3D 画面"), "cube.transparent", String(localized: "推 3D 滑块，看上屏的立体测试图。")),
        "other.power": (String(localized: "省电模式"), "leaf", String(localized: "画面亮度最高 75%，游戏用复古 1× 分辨率。")),
        "other.brightness": (String(localized: "屏幕亮度"), "sun.max", String(localized: "两块屏的亮度，五档。")),
        "other.rendering": (String(localized: "画面渲染"), "cpu", String(localized: "渲染器、内部分辨率、像素原尺寸显示。下次开启软件时生效。")),
        "other.haptics": (String(localized: "按键震动"), "iphone.radiowaves.left.and.right", String(localized: "按键时 iPhone 震不震、震多重。")),
        "other.about": (String(localized: "关于本机"), "info.circle", String(localized: "版本、模拟核心、用户名、上次运行，开源许可。")),
        "other.eula": (String(localized: "用户协议"), "doc.text", String(localized: "Zero EMU 的许可和声明。")),
        "other.update": (String(localized: "系统更新"), "arrow.down.circle", String(localized: "Zero EMU 的版本和更新方式。")),
        "other.homeRow": (String(localized: "主菜单顶上的按键"), "rectangle.topthird.inset.filled", String(localized: "主菜单最上面那一排小按键放哪几个：保存进度、游戏笔记、屏幕亮度、画面滤镜……开着的才出现。")),
        "other.format": (String(localized: "格式化主机"), "trash", String(localized: "删除主机里的所有数据和设置，回到第一次开机的样子。")),
        "other.filter": (String(localized: "画面滤镜"), "camera.filters", String(localized: "给游戏画面加一层效果：原样、柔和、扫描线、LCD 网格、老电视。马上生效，电视上也一样。")),
        "other.gamepad": (String(localized: "手柄"), "gamecontroller.fill", String(localized: "接上手柄时自动换到手柄模式；手柄上的键对应 3DS 的哪个键，可以改。")),
        "other.developer": (String(localized: "开发者"), "wrench.and.screwdriver", String(localized: "调试构建才有：方向诊断的开关。正式版没有这一项。")),
        "pad.auto": (String(localized: "接上手柄自动换模式"), "arrow.triangle.2.circlepath", String(localized: "接上手柄时换到手柄模式（两块屏放大，按键交给手柄），拔掉就换回原来的模式。TV模式下不换。")),
        "pad.preset": (String(localized: "按键布局"), "square.grid.2x2", String(localized: "按位置：和 3DS 一样，右边的键是 A。按字母：Xbox 手柄上印着 A 的键就是 A。改了某个键就是自定义。")),
        "pad.reset": (String(localized: "恢复默认"), "arrow.counterclockwise", String(localized: "按键布局回到按位置（和 3DS 一样）。")),
        "data.software": (String(localized: "软件"), "square.stack.3d.up", String(localized: "游戏库里的每个软件：大小、存档，和移除。")),
        "data.states": (String(localized: "data.states.title"), "clock.arrow.circlepath", String(localized: "主菜单里「保存进度」存下的档，和离开时自动存的继续进度。")),
        "data.storage": (String(localized: "主机存储"), "internaldrive", String(localized: "游戏副本、即时存档、主机存储各占多少；主机存储在「文件」App 里。")),
        "data.sync": (String(localized: "存档同步"), "icloud.and.arrow.up", String(localized: "把游戏存档和即时存档同步到 iCloud 云盘里的一个文件夹（或 App 自己的 iCloud 空间），换一台设备接着玩。")),
        "data.backup": (String(localized: "备份"), "externaldrive.badge.timemachine", String(localized: "把游戏存档和即时存档导出成一个 zip 留一份，或从导出过的备份放回来；不用 iCloud。")),
        "sync.pro": (String(localized: "典藏卡带"), "star.circle.fill", String(localized: "存档同步是典藏卡带的功能。备份（把存档导出成一个 zip）不用典藏卡带。")),
        "sync.enabled": (String(localized: "存档同步"), "icloud.and.arrow.up", String(localized: "开着时：打开 Zero EMU、关掉游戏、切到后台时各同步一次。游戏开着时不同步。")),
        "sync.folder": (String(localized: "文件夹"), "folder", String(localized: "在「文件」里选一个文件夹，最好在 iCloud 云盘里；Zero EMU 在里面建一个「Zero EMU Saves」（以前的「Zero EMU 存档」「FoldArc 存档」会改成这个名字）。")),
        "sync.icloud": (String(localized: "App 自己的 iCloud 空间"), "icloud", String(localized: "不用选文件夹，存档放在 Zero EMU 自己的 iCloud 空间里。")),
        "sync.place.icloud": (String(localized: "App 自己的 iCloud 空间"), "icloud", String(localized: "存到哪之一：不用选文件夹，存档放在 Zero EMU 自己的 iCloud 空间里，同一个 Apple ID 的设备都能拿到；在「文件」里是 iCloud 云盘 › Zero EMU。")),
        "sync.place.folder": (String(localized: "「文件」里的文件夹"), "folder", String(localized: "存到哪之二：你在「文件」里选的一个文件夹（选 iCloud 云盘里的就是 iCloud 同步），别的设备选同一个文件夹。")),
        "sync.now": (String(localized: "现在同步"), "arrow.triangle.2.circlepath", String(localized: "马上比一遍两边，改过的传过去。")),
        "sync.repair": (String(localized: "修复同步"), "wrench.and.screwdriver", String(localized: "不信上次的记录，两边每个文件按内容重新比一遍，缺的补上；什么都不删，两边不一样的旧的那份放进 Conflicts。")),
        "game.sync": (String(localized: "同步这个游戏的存档"), "icloud", String(localized: "关掉时，这个游戏的存档和即时存档只留在这台设备上，不传也不拿。")),
        "data.tests": (String(localized: "核心测试文件"), "cpu", String(localized: "数据文件夹 CoreTest 里的 Homebrew（开发用）：点一个直接在核心上开启，不用导入。")),
        "parental.start": (String(localized: "开始设置"), "lock.open", String(localized: "先设密码，再选一个秘密问题，最后选要限制什么。")),
        "parental.restrict3D": (String(localized: "3D 影像"), "cube.transparent", String(localized: "开着时，3D 滑块推不上去，画面一直是 2D。")),
        "parental.restrictImport": (String(localized: "导入软件"), "square.and.arrow.down", String(localized: "开着时，主菜单里的「导入」不能用。")),
        "parental.restrictDelete": (String(localized: "删除软件和数据"), "trash", String(localized: "开着时，不能移除软件、删除存档，也不能格式化主机。")),
        "parental.change": (String(localized: "更改密码"), "key", String(localized: "换一个 4 位密码。")),
        "parental.clear": (String(localized: "清除家长控制"), "lock.slash", String(localized: "去掉密码和所有限制。")),
        "parental.forgot": (String(localized: "忘记密码"), "questionmark.circle", String(localized: "回答设置时选的秘密问题，答对就清除家长控制。")),
    ]
}

// MARK: - Screens

/// The upper screen of the running software.
struct ConsoleAppTopScreen: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    /// 11-07: printed in 主题's colours (SystemMenuStyle); drawn again when
    /// they change.
    @AppStorage(LibraryTheme.storageKey) private var themeID = LibraryTheme.cream.rawValue
    @AppStorage(PencilBoxLook.key) private var pencilLook = PencilBoxLook.standard.id
    var body: some View {
        GeometryReader { proxy in
            let s = max(0.55, min(1, proxy.size.width / 440))
            ZStack {
                if model.page == .reel {
                    // 金卡带's films fill the upper screen, as software's picture does.
                    GoldReelScreen(s: s)
                } else if model.page == .unbox {
                    // The box of a card just bought.
                    UnboxScreen(model: model)
                } else if model.page == .pictureFrame {
                    // 画框's scenery fills it too.
                    PictureFrameScreen(s: s)
                } else if model.page == .tinBox {
                    // 铅笔盒 opens over the whole display (PencilBoxOpen); where the
                    // console's screens still show (the picture frame stood up, the
                    // camera's deck), the inside of its lid, quiet.
                    PencilImages.image("pencilbox-lid-inside.jpg", look: PencilBoxLook(id: pencilLook)).resizable().scaledToFill()
                } else {
                    SystemMenuBackdrop()
                    VStack(spacing: 0) {
                        MenuStatusStrip(s: s, title: Self.stripTitle(model.app), trailing: model.app.title)
                        header(s: s)
                        AppTopContent(model: model, ctx: ctx, s: s)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .id(themeID)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .foregroundStyle(SystemMenuStyle.ink)
            .environment(\.colorScheme, .light)
        }
    }
    static func stripTitle(_ app: ConsoleApp) -> String {
        switch app {
        case .setup: return "SETUP"
        case .activity: return "PLAY LOG"
        case .theme: return "THEMES"
        case .manual: return "MANUAL"
        case .modes: return "PLAY MODE"
        case .pictureFrame: return "FRAME"
        case .tinBox: return "PENCIL BOX"
        default: return "SETTINGS"
        }
    }
    @ViewBuilder private func header(s: Double) -> some View {
        if let step = model.page.setupStep {
            HStack(spacing: 5 * s) {
                ForEach(1...ConsoleAppModel.setupSteps, id: \.self) { index in
                    Capsule().fill(index <= step ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge.opacity(0.5))
                        .frame(width: index == step ? 18 * s : 7 * s, height: 5 * s)
                }
                Spacer(minLength: 0)
                Text("\(step) / \(ConsoleAppModel.setupSteps)").font(.system(size: 8 * s, weight: .bold, design: .monospaced))
                    .foregroundStyle(SystemMenuStyle.inkSoft)
            }
            .padding(.horizontal, 14 * s).padding(.top, 8 * s)
            .accessibilityElement().accessibilityLabel("第 \(step) 步，共 \(ConsoleAppModel.setupSteps) 步")
        } else {
            HStack(spacing: 5 * s) {
                Image(systemName: model.app.symbol).font(.system(size: 9 * s, weight: .bold))
                Text(model.trail).font(.system(size: 9 * s, weight: .semibold, design: .rounded)).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SystemMenuStyle.inkSoft)
            .padding(.horizontal, 14 * s).padding(.top, 7 * s)
        }
    }
}

/// The lower screen: the page, the bar, a dialog over them.
struct ConsoleAppBottomScreen: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    @AppStorage(LibraryTheme.storageKey) private var themeID = LibraryTheme.cream.rawValue
    @AppStorage(PencilBoxLook.key) private var pencilLook = PencilBoxLook.standard.id
    var body: some View {
        GeometryReader { proxy in
            let s = max(0.55, min(1, proxy.size.width / 324))
            ZStack {
                if model.page == .pictureFrame {
                    // 画框's lower screen is all its own: dim, no paper, no bar.
                    PictureFramePanel(model: model, s: s)
                } else if model.page == .tinBox {
                    // (and its tray: HOME leaves it)
                    PencilImages.image("pencilbox-tray.jpg", look: PencilBoxLook(id: pencilLook)).resizable().scaledToFill()
                } else {
                    SystemMenuBackdrop()
                    VStack(spacing: 0) {
                        AppPageView(model: model, ctx: ctx, s: s, width: proxy.size.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .id(model.page)
                        if let toast = model.toast {
                            Text(toast).font(.system(size: AppMetrics.text(9, s), weight: .bold, design: .rounded))
                                .foregroundStyle(.white).padding(.horizontal, 10 * s).padding(.vertical, 4 * s)
                                .background(SystemMenuStyle.ink.opacity(0.85), in: Capsule())
                                .padding(.bottom, 4 * s)
                                .transition(.opacity)
                                .accessibilityIdentifier("app-toast")
                        }
                        AppBar(model: model, ctx: ctx, s: s)
                    }
                }
                if let dialog = model.dialog { AppDialogView(model: model, dialog: dialog, s: s) }
            }
            .id(themeID)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .foregroundStyle(SystemMenuStyle.ink)
            .tint(SystemMenuStyle.accent)
            .environment(\.colorScheme, .light)
        }
    }
}

/// The two screens over the whole display, for LCDs too small to read
/// (a phone's 掌机模式 and 桌面模式), as HOME does.
struct ConsoleAppFullScreen: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    @AppStorage(LibraryTheme.storageKey) private var themeID = LibraryTheme.cream.rawValue
    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let topHeight = min(proxy.size.height * 0.42, proxy.size.width * 0.6 + 20)
            let palette = LibraryTheme(rawValue: themeID)?.menu ?? MenuPalette.current
            // (画框 has no paper round it: black to the display's edges.)
            let frame = model.page == .pictureFrame
            VStack(spacing: 0) {
                ConsoleAppTopScreen(model: model, ctx: ctx)
                    .padding(.top, insets.top)
                    .background(frame ? Color.black : palette.status)
                    .frame(height: topHeight + insets.top)
                Rectangle().fill(frame ? Color.black : palette.bar).frame(height: 4)
                ConsoleAppBottomScreen(model: model, ctx: ctx)
                    .padding(.bottom, insets.bottom)
                    .background(frame ? Color.black : palette.bar)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - The bar

private struct AppBar: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    var body: some View {
        MenuBar(s: s, left: left, right: right, focus: model.focus, setFocus: { model.focus = $0 })
    }
    private var left: MenuBarButton? {
        switch model.page {
        case .setupWelcome:
            return MenuBarButton(id: ConsoleAppModel.barLeft, title: String(localized: "稍后"), symbol: "xmark", color: SystemMenuStyle.inkSoft) { model.leave() }
        case .unbox:
            return MenuBarButton(id: ConsoleAppModel.barLeft, title: String(localized: "跳过"), symbol: "forward.end", color: SystemMenuStyle.inkSoft) { model.pop() }
        case .root, .activity, .theme, .manual, .pictureFrame, .tinBox:
            return MenuBarButton(id: ConsoleAppModel.barLeft, title: String(localized: "返回"), symbol: "house", color: SystemMenuStyle.inkSoft) { model.leave() }
        default:
            return MenuBarButton(id: ConsoleAppModel.barLeft, title: String(localized: "返回"), symbol: "chevron.left", color: SystemMenuStyle.inkSoft) { model.pop() }
        }
    }
    private var right: MenuBarButton? { AppPageView.rightButton(model: model) }
}

private struct AppDialogView: View {
    @ObservedObject var model: ConsoleAppModel
    var dialog: ConsoleAppModel.Dialog
    var s: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).onTapGesture { model.dialog = nil }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text(dialog.title).font(.system(size: AppMetrics.text(12, s), weight: .bold, design: .rounded))
                Text(dialog.message).font(.system(size: AppMetrics.text(9, s))).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8 * s) {
                    button(String(localized: "取消"), id: "dialog.cancel", color: SystemMenuStyle.inkSoft, identifier: "dialog-cancel") { model.dialog = nil }
                    button(dialog.confirm, id: "dialog.confirm", color: dialog.destructive ? SystemMenuStyle.stop : SystemMenuStyle.go,
                           identifier: dialog.identifier) {
                        let action = dialog.action
                        model.dialog = nil
                        action()
                    }
                }
            }
            .padding(14 * s).frame(maxWidth: 270 * s, alignment: .leading)
            .background(SystemMenuStyle.paper, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(SystemMenuStyle.tileEdge, lineWidth: 1))
            .padding(16 * s)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
    private func button(_ title: String, id: String, color: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button { model.focus = id; action() } label: {
            Text(title).font(.system(size: AppMetrics.text(10, s), weight: .bold, design: .rounded)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity).frame(height: 28 * s)
                .background(color, in: Capsule())
                .overlay { if model.focus == id { MenuCursorRing(shape: Capsule(), s: s, color: .white) } }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Building blocks

/// What the pages keep whatever the screen's scale `s`: a row has a
/// finger's height to be touched in, and words that explain are never
/// smaller than a caption.
enum AppMetrics {
    /// The least height (and width) of what is touched, in points.
    static let touch = 44.0
    /// The gap between two rows of a page (AppScroll's spacing), in design
    /// points: half of it over a row and half under it are touched with it.
    static let rowGap = 6.0
    /// The least height a row is drawn at: with the gap it is touched
    /// through, a finger's height.
    static func row(_ s: Double) -> Double { max(touch - rowGap * s, 30 * s) }
    /// The least size of words that explain, in points.
    static let caption = 11.0
    /// `points` at the screen's scale, never under `caption`.
    static func text(_ points: Double, _ s: Double) -> Double { max(caption, points * s) }
}

/// The name of the row a control stands in: AppRow says it to what it holds
/// at its end, so that a control there can say what it changes.
private struct AppRowTitleKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var appRowTitle: String {
        get { self[AppRowTitleKey.self] }
        set { self[AppRowTitleKey.self] = newValue }
    }
}

/// A big button of a menu page, as a handheld's settings have them.
struct AppBigButton: View {
    var id: String
    var title: String
    var symbol: String
    var note: String? = nil
    /// How many lines the note may take. One where the buttons stand in a
    /// column that does not scroll (其他设置, 数据管理): it shrinks a little
    /// before it is cut. More on a page that scrolls, for a note that says
    /// what the button will do (whole, in a longer language too).
    var noteLines = 1
    /// How tall at least (design points; round 30: the first page of 系统设置
    /// has five; with Zero EMU Pro it has six, each lower still, its mark
    /// smaller).
    var height: Double = 38
    var s: Double
    @ObservedObject var model: ConsoleAppModel
    var action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
        let low = height < 32
        let mark = low ? height - 6 : 26
        // A note of one line is not scaled under a caption's size, and must
        // not make the button taller where the column does not scroll: its
        // room comes out of the padding (the least height keeps the rest).
        let pad = note != nil && noteLines == 1 ? 1.0 : (low ? 3.0 : (height < 38 ? 4.0 : 6.0))
        Button { model.focus = id; action() } label: {
            HStack(spacing: 9 * s) {
                Image(systemName: symbol).font(.system(size: (low ? 12 : 13) * s, weight: .semibold))
                    .frame(width: mark * s, height: mark * s)
                    .foregroundStyle(.white)
                    .background(SystemMenuStyle.accent, in: RoundedRectangle(cornerRadius: 7 * s, style: .continuous))
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(title).font(.system(size: 11.5 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    if let note {
                        Text(note).font(.system(size: AppMetrics.text(8, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                            .lineLimit(noteLines).minimumScaleFactor(noteLines == 1 ? 0.85 : 1)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.inkSoft)
            }
            .padding(.horizontal, 10 * s).padding(.vertical, pad * s)
            .frame(maxWidth: .infinity, minHeight: height * s)
            .background(shape.fill(SystemMenuStyle.tile).shadow(color: SystemMenuStyle.ink.opacity(0.2), radius: 0, y: 1.5 * s))
            .overlay(shape.strokeBorder(SystemMenuStyle.tileEdge.opacity(0.5), lineWidth: 1))
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier("app.\(id)")
        .id(id)
    }
}

/// A row: a name, its value, the cursor ring. A row whose end holds
/// controls of its own (a stepper, a picker) keeps them reachable for
/// assistive access (`interactive`); any other row reads as one element.
/// With the gap to its neighbours, which is touched with it, never lower
/// than a finger (AppMetrics.touch), however small the screen is drawn: the
/// pages scroll.
struct AppRow<Trailing: View>: View {
    var id: String
    var title: String
    var s: Double
    var selected = false
    var interactive = false
    @ObservedObject var model: ConsoleAppModel
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
        let row = HStack(spacing: 8 * s) {
            Text(title).font(.system(size: AppMetrics.text(10.5, s), weight: .semibold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 4 * s)
            trailing().environment(\.appRowTitle, title)
        }
        .padding(.horizontal, 10 * s).padding(.vertical, 7 * s)
        .frame(maxWidth: .infinity, minHeight: AppMetrics.row(s), alignment: .leading)
        .background(shape.fill(selected ? SystemMenuStyle.accent.opacity(0.12) : SystemMenuStyle.tile))
        .overlay(shape.strokeBorder(selected ? SystemMenuStyle.accent.opacity(0.5) : SystemMenuStyle.tileEdge.opacity(0.4), lineWidth: 1))
        .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
        .contentShape(Rectangle().inset(by: -AppMetrics.rowGap * s / 2))
        .id(id)
        Group {
            if let action {
                Button { model.focus = id; action() } label: { row }.buttonStyle(MenuPressStyle())
                    .accessibilityElement(children: .combine)
            } else if interactive {
                row.onTapGesture { model.focus = id }
                    .accessibilityElement(children: .contain)
            } else {
                row.onTapGesture { model.focus = id }
                    .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("app.\(id)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The value at the end of a row, with a chevron when it opens a page.
struct AppValue: View {
    var text: String
    var s: Double
    var opens = true
    var body: some View {
        HStack(spacing: 4 * s) {
            // One line, as a row's end is; a long one shrinks a little before it is cut.
            Text(text).font(.system(size: AppMetrics.text(9.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.85)
            if opens { Image(systemName: "chevron.right").font(.system(size: 8 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.inkSoft) }
        }
    }
}

/// On / off, as two words in a capsule (left and right also flip it).
struct AppSwitch: View {
    var isOn: Bool
    var s: Double
    var body: some View {
        HStack(spacing: 0) {
            Text("关").frame(width: 24 * s, height: 18 * s)
                .background(isOn ? Color.clear : SystemMenuStyle.inkSoft, in: Capsule())
                .foregroundStyle(isOn ? SystemMenuStyle.inkSoft : .white)
            Text("开").frame(width: 24 * s, height: 18 * s)
                .background(isOn ? SystemMenuStyle.accent : Color.clear, in: Capsule())
                .foregroundStyle(isOn ? .white : SystemMenuStyle.inkSoft)
        }
        .font(.system(size: 9 * s, weight: .bold, design: .rounded))
        .padding(2 * s)
        .background(SystemMenuStyle.paperDeep.opacity(0.7), in: Capsule())
        .accessibilityValue(isOn ? "开" : "关")
    }
}

/// ‹ value ›, stepped by left / right or the arrows. Each arrow is drawn as
/// small as before and touched over a finger's square round it
/// (AppMetrics.touch): in a row, that is the row's height, and sideways it
/// reaches over the gap and the value's edge, not the other arrow.
struct AppStepper: View {
    var text: String
    var s: Double
    /// It steps through choices (a layout, a look), not along a scale: the
    /// arrows are 上一项 and 下一项 to assistive access, not 减少 and 增加.
    var choices = false
    var step: (Int) -> Void
    /// The row it stands in (AppRow says so): what the arrows change.
    @Environment(\.appRowTitle) private var rowTitle
    var body: some View {
        HStack(spacing: 6 * s) {
            arrow(-1)
            // (not touched itself: an arrow's reach goes over its edge)
            Text(text).font(.system(size: AppMetrics.text(10.5, s), weight: .bold, design: .rounded).monospacedDigit()).frame(minWidth: 40 * s)
                .allowsHitTesting(false)
            arrow(1)
        }
        .font(.system(size: 9 * s, weight: .bold))
        .foregroundStyle(SystemMenuStyle.ink)
        .buttonStyle(MenuPressStyle())
    }
    private func arrow(_ delta: Int) -> some View {
        // How far the touch reaches past the drawn arrow on each side.
        let reach = max(0, (AppMetrics.touch - 22 * s) / 2)
        return Button { step(delta) } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right").frame(width: 22 * s, height: 22 * s)
                .padding(reach)
                .contentShape(Rectangle())
        }
        // (the arrows stay where they were: the reach takes no room)
        .padding(-reach)
        .accessibilityLabel(name(delta))
        .accessibilityValue(text)
        // The UI tests find the two by the short names they had before.
        .accessibilityIdentifier(delta < 0 ? "减" : "加")
    }
    /// What an arrow is called: what it does, and to which row.
    private func name(_ delta: Int) -> String {
        guard !rowTitle.isEmpty else { return delta < 0 ? String(localized: "减") : String(localized: "加") }
        if choices { return delta < 0 ? String(localized: "上一项：\(rowTitle)") : String(localized: "下一项：\(rowTitle)") }
        return delta < 0 ? String(localized: "减少：\(rowTitle)") : String(localized: "增加：\(rowTitle)")
    }
}

/// A line of information (no cursor).
struct AppInfoLine: View {
    var title: String
    var value: String
    var s: Double
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
            Text(title).font(.system(size: AppMetrics.text(9.5, s), weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
            Spacer(minLength: 4 * s)
            Text(value).font(.system(size: AppMetrics.text(9.5, s), weight: .semibold, design: .rounded)).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10 * s).padding(.vertical, 4 * s)
        .accessibilityElement(children: .combine)
    }
}

/// Text that explains a page, on the paper.
struct AppNote: View {
    var text: String
    var s: Double
    var body: some View {
        Text(text).font(.system(size: AppMetrics.text(9, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4 * s)
    }
}

/// 11-23: what a hint says, shown only on a new console (OnceHint): the first time it would come it stays as
/// long as it is there, and is remembered once it has been there `seconds`; it does not come again (格式化主机
/// brings it back).
struct OnceHintView<Content: View>: View {
    private let name: String
    private let seconds: Double
    private let content: Content
    /// Whether it shows this time: decided as it first comes, not taken away while it is there.
    @State private var showing: Bool
    init(_ name: String, seconds: Double = 5, @ViewBuilder content: () -> Content) {
        self.name = name
        self.seconds = seconds
        self.content = content()
        _showing = State(initialValue: !OnceHint.seen(name))
    }
    var body: some View {
        if showing {
            content.task {
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { OnceHint.mark(name) }
            }
        }
    }
}

/// A scrolling column that keeps the cursor in view.
struct AppScroll<Content: View>: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6 * s) { content() }
                    .padding(.horizontal, 12 * s).padding(.vertical, 8 * s)
            }
            .onChange(of: model.focus) { _, focus in
                guard let focus, !focus.hasPrefix("app.bar"), !focus.hasPrefix("dialog") else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(focus, anchor: .center) }
            }
            // b41: back on a page (返回 from one it opened), the row the
            // cursor came back to is in view (it was below the screen).
            .onAppear {
                guard let focus = model.focus, !focus.hasPrefix("app.bar"), !focus.hasPrefix("dialog") else { return }
                proxy.scrollTo(focus, anchor: .center)
            }
        }
    }
}

// MARK: - The pages (lower screen)

struct AppPageView: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    var width: Double
    @ObservedObject private var settings = ConsoleSettings.shared

    var body: some View {
        switch model.page {
        case .root: RootPage(model: model, s: s)
        case .internet: InternetPage(model: model, s: s)
        case .parental: ParentalPage(model: model, s: s)
        case .parentalPIN(let purpose): PinPage(model: model, purpose: purpose, s: s)
        case .parentalQuestion: QuestionPage(model: model, s: s)
        case .parentalAnswer, .parentalForgot: AnswerPage(model: model, s: s)
        case .parentalRestrictions: RestrictionsPage(model: model, s: s)
        case .data: DataPage(model: model, ctx: ctx, s: s)
        case .dataSoftware: SoftwarePage(model: model, ctx: ctx, s: s)
        case .dataGame(let id): GamePage(model: model, ctx: ctx, id: id, s: s)
        case .dataStates: StatesPage(model: model, ctx: ctx, s: s)
        case .dataStorage: StoragePage(model: model, ctx: ctx, s: s)
        case .dataTests: TestFilesPage(model: model, ctx: ctx, s: s)
        case .other: OtherPage(model: model, s: s)
        case .profile: ProfilePage(model: model, s: s)
        case .profileName, .setupName: NamePage(model: model, s: s)
        case .profileBirthday, .setupBirthday: BirthdayPage(model: model, s: s)
        case .profileCountry, .setupCountry: CountryPage(model: model, s: s)
        case .profileRegion: RegionPage(model: model, s: s)
        case .dateTime, .setupDateTime: DateTimePage(model: model, s: s)
        case .touch: TouchPage(model: model, s: s)
        case .touchCalibrate: CalibratePage(model: model, s: s)
        case .circlePad: CirclePadPage(model: model, ctx: ctx, s: s)
        case .sound: SoundPage(model: model, s: s)
        case .mic: MicPage(model: model, session: ctx.session, s: s)
        case .language, .setupLanguage: LanguagePage(model: model, s: s)
        case .screen3D: Screen3DPage(model: model, session: ctx.session, s: s)
        case .power: PowerPage(model: model, s: s)
        case .brightness: BrightnessPage(model: model, s: s)
        case .rendering: RenderingPage(model: model, s: s)
        case .haptics: HapticsPage(model: model, s: s)
        case .homeRow: HomeRowPage(model: model, s: s)
        case .about: AboutPage(model: model, s: s)
        case .licenses: LicensesPage(model: model, s: s)
        case .eula: EulaPage(model: model, s: s)
        case .update: UpdatePage(model: model, s: s)
        case .format: FormatPage(model: model, ctx: ctx, s: s)
        case .tv: TVPage(model: model, s: s)
        case .modes: ModesPage(model: model, ctx: ctx, s: s)
        case .tvSet: TVSetPage(model: model, ctx: ctx, s: s)
        case .finish: FinishAppPage(model: model, s: s)
        case .skins: SkinsAppPage(model: model, s: s)
        case .deleteStyle: DeleteStylePage(model: model, s: s)
        case .pencilBox: PencilLookPage(model: model, s: s)
        case .filter: FilterPage(model: model, s: s)
        case .gamepad: GamepadPage(model: model, s: s)
        case .developer: DeveloperPage(model: model, s: s)
        case .pro: ProPage(model: model, s: s)
        case .stateSlot: StateSlotPage(model: model, ctx: ctx, s: s)
        case .reel: GoldReelPage(model: model, s: s)
        case .cartridgePass: CartridgePassPage(model: model, s: s)
        case .unbox: UnboxPage(model: model, s: s)
        case .pictureFrame: PictureFramePanel(model: model, s: s)
        case .tinBox: Color.clear
        case .dataSync: SyncPage(model: model, s: s)
        case .dataBackup: BackupPage(model: model, ctx: ctx, s: s)
        case .activity: ActivityAppPage(model: model, ctx: ctx, s: s)
        case .theme: ThemeAppPage(model: model, s: s)
        case .manual: ManualAppPage(model: model, s: s)
        case .manualSection(let index): ManualSectionPage(model: model, index: index, s: s)
        case .setupWelcome: WelcomePage(model: model, s: s)
        case .setupFinish: FinishPage(model: model, s: s)
        }
    }

    /// The bar's right-hand button for the page on screen.
    static func rightButton(model: ConsoleAppModel) -> MenuBarButton? {
        func next(_ title: String = String(localized: "下一步"), enabled: Bool = true, _ action: @escaping () -> Void) -> MenuBarButton {
            MenuBarButton(id: ConsoleAppModel.barRight, title: title, symbol: "chevron.right",
                          color: enabled ? SystemMenuStyle.go : SystemMenuStyle.inkSoft.opacity(0.6)) { if enabled { action() } }
        }
        switch model.page {
        case .setupWelcome: return next { model.push(.setupLanguage) }
        case .setupLanguage: return next { model.push(.setupDateTime) }
        case .setupDateTime: return next { model.push(.setupName) }
        case .setupName: return next(enabled: model.draft.nameIsValid) { model.draft = model.draft.cleaned; model.push(.setupBirthday) }
        case .setupBirthday: return next { model.push(.setupCountry) }
        case .setupCountry: return next { model.push(.setupFinish) }
        case .setupFinish:
            return MenuBarButton(id: ConsoleAppModel.barRight, title: String(localized: "完成"), symbol: "checkmark", color: SystemMenuStyle.go) {
                ConsoleSettings.shared.completeSetup(with: model.draft)
                ConsoleSounds.shared.play(.launch)
                model.leave()
            }
        case .profileName:
            return MenuBarButton(id: ConsoleAppModel.barRight, title: String(localized: "确定"), symbol: "checkmark",
                                 color: model.draft.nameIsValid ? SystemMenuStyle.go : SystemMenuStyle.inkSoft.opacity(0.6)) {
                guard model.draft.nameIsValid else { return }
                ConsoleSettings.shared.profile.userName = ConsoleProfile.cleanName(model.draft.userName)
                model.say(String(localized: "用户名已保存"))
                model.pop()
            }
        case .profileBirthday:
            return MenuBarButton(id: ConsoleAppModel.barRight, title: String(localized: "确定"), symbol: "checkmark", color: SystemMenuStyle.go) {
                ConsoleSettings.shared.profile.birthMonth = model.draft.birthMonth
                ConsoleSettings.shared.profile.birthDay = model.draft.birthDay
                model.say(String(localized: "生日已保存"))
                model.pop()
            }
        case .parentalAnswer:
            let ok = !ParentalControls.normalized(model.answer).isEmpty
            return MenuBarButton(id: ConsoleAppModel.barRight, title: String(localized: "确定"), symbol: "checkmark",
                                 color: ok ? SystemMenuStyle.go : SystemMenuStyle.inkSoft.opacity(0.6)) {
                guard ok else { return }
                var parental = ConsoleSettings.shared.parental
                parental.pin = model.firstPin
                parental.answer = model.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                ConsoleSettings.shared.parental = parental
                model.unlocked = true
                model.answer = ""
                model.pop(to: .parental)
                model.push(.parentalRestrictions)
                model.say(String(localized: "家长控制已开启"))
            }
        case .parentalForgot:
            let ok = !ParentalControls.normalized(model.answer).isEmpty
            return MenuBarButton(id: ConsoleAppModel.barRight, title: String(localized: "确定"), symbol: "checkmark",
                                 color: ok ? SystemMenuStyle.go : SystemMenuStyle.inkSoft.opacity(0.6)) {
                guard ok else { return }
                if ConsoleSettings.shared.parental.answers(model.answer) {
                    ConsoleSettings.shared.parental = ParentalControls()
                    model.answer = ""
                    model.unlocked = false
                    model.pop(to: .parental)
                    model.say(String(localized: "答对了：家长控制已清除"))
                } else {
                    model.answer = ""
                    model.say(String(localized: "答案不对"))
                }
            }
        case .touchCalibrate:
            guard model.calibrationTouches.count == TouchCalibration.targets.count else { return nil }
            return MenuBarButton(id: ConsoleAppModel.barRight, title: String(localized: "保存"), symbol: "checkmark", color: SystemMenuStyle.go) {
                if let fit = TouchCalibration.fit(targets: TouchCalibration.targets, touches: model.calibrationTouches) {
                    ConsoleSettings.shared.touch = fit
                    model.say(String(localized: "校正已保存"))
                    model.pop()
                } else {
                    model.calibrationTouches = []
                    model.say(String(localized: "偏得太多，再点一次"))
                }
            }
        default:
            return nil
        }
    }
}

// MARK: Root and the big menus

private struct RootPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    /// Round 30: TV输出 among them (a page of its own). Zero EMU Pro last:
    /// six fit as lower buttons (6 × 29 + 5 × 4 + 2 × 5 = 204 of the 213
    /// above the bar, what five took before).
    private let items: [(String, ConsoleAppModel.Page)] = [("root.internet", .internet), ("root.parental", .parental), ("root.data", .data), ("root.tv", .tv), ("root.other", .other), ("root.pro", .pro)]
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        register()
        return VStack(spacing: 4 * s) {
            ForEach(items, id: \.0) { id, page in
                let info = AppItemInfo.catalog[id]!
                AppBigButton(id: id, title: id == "root.pro" && pro.isPro ? String(localized: "典藏卡带 · 已开通") : info.title, symbol: info.symbol,
                             height: 29, s: s, model: model) { model.push(page) }
            }
        }
        .padding(.horizontal, 14 * s).padding(.vertical, 5 * s)
        .frame(maxHeight: .infinity, alignment: .center)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .root else { return }
        model.layout = items.map { [$0.0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.leave() }]
        for (id, page) in items { handlers[id] = { model.push(page) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: items.first?.0)
    }
}

private struct OtherPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    /// 11-07: 手柄 and 语言 on the first page, 触摸屏 and 摇杆
    /// under 麦克风测试, 画面滤镜 first on the third; the rest moved along in
    /// their order. A debug build's 开发者 last (round 31; it was a small
    /// icon of HOME's until 11-01).
    static let pages: [[(String, ConsoleAppModel.Page)]] = [
        [("other.profile", .profile), ("other.dateTime", .dateTime), ("other.gamepad", .gamepad), ("other.language", .language)],
        [("other.sound", .sound), ("other.mic", .mic), ("other.touch", .touch), ("other.circlePad", .circlePad)],
        [("other.filter", .filter), ("other.screen3D", .screen3D), ("other.power", .power), ("other.brightness", .brightness)],
        [("other.rendering", .rendering), ("other.haptics", .haptics), ("other.about", .about), ("other.eula", .eula)],
        [("other.homeRow", .homeRow), ("other.update", .update), ("other.format", .format)] + developerItem,
    ]
    #if os(iOS) && DEBUG
    static let developerItem: [(String, ConsoleAppModel.Page)] = [("other.developer", .developer)]
    #else
    static let developerItem: [(String, ConsoleAppModel.Page)] = []
    #endif
    var body: some View {
        let items = Self.pages[model.otherPage]
        register(items)
        return VStack(spacing: 6 * s) {
            ForEach(items, id: \.0) { id, page in
                let info = AppItemInfo.catalog[id]!
                AppBigButton(id: id, title: info.title, symbol: info.symbol, note: note(for: page), s: s, model: model) { model.push(page) }
            }
            HStack(spacing: 10 * s) {
                Button { turn(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.system(size: 16 * s)) }
                    .accessibilityLabel("上一页").accessibilityIdentifier("app.other.previous")
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    Circle().fill(index == model.otherPage ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge.opacity(0.6))
                        .frame(width: 6 * s, height: 6 * s)
                }
                Button { turn(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.system(size: 16 * s)) }
                    .accessibilityLabel("下一页").accessibilityIdentifier("app.other.next")
            }
            .foregroundStyle(SystemMenuStyle.accent)
            .buttonStyle(MenuPressStyle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("第 \(model.otherPage + 1) 页，共 \(Self.pages.count) 页")
        }
        .padding(.horizontal, 14 * s).padding(.top, 8 * s).padding(.bottom, 4 * s)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    private func note(for page: ConsoleAppModel.Page) -> String? {
        let settings = ConsoleSettings.shared
        switch page {
        case .profile: return settings.profile.userName.isEmpty ? nil : settings.profile.userName
        case .sound: return settings.soundOutput.title
        case .language: return settings.profile.language.title
        case .power: return settings.powerSaving ? String(localized: "开") : String(localized: "关")
        case .filter: return ScreenFilter.stored.title
        case .gamepad: return GameControllerInput.shared.padName ?? String(localized: "没有接手柄")
        default: return nil
        }
    }
    private func turn(_ delta: Int) {
        let count = Self.pages.count
        model.otherPage = (model.otherPage + delta + count) % count
        model.focus = Self.pages[model.otherPage].first?.0
        ConsoleSounds.shared.play(.move)
    }
    private func register(_ items: [(String, ConsoleAppModel.Page)]) {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .other else { return }
        model.layout = items.map { [$0.0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for (id, page) in items { handlers[id] = { model.push(page) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.pageTurner = { turn($0) }
        model.registered(initial: items.first?.0)
    }
}

// MARK: Internet

private struct InternetPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    #if os(iOS)
    @ObservedObject private var network = NetworkStatus.shared
    #endif
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            VStack(alignment: .leading, spacing: 2 * s) {
                #if os(iOS)
                AppInfoLine(title: String(localized: "这台 iPhone 的网络"), value: network.summary, s: s)
                #endif
                AppInfoLine(title: String(localized: "Zero EMU 自己的服务器"), value: String(localized: "没有"), s: s)
                AppInfoLine(title: String(localized: "账号与好友"), value: String(localized: "没有"), s: s)
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            AppNote(text: String(localized: "游戏、存档和设置都存在这台 iPhone 上，Zero EMU 没有自己的服务器，也不收集数据。购买走 App Store；存档同步是可选的，走你自己的 iCloud。软件自己想上网的功能（在线对战、商店）在模拟的主机里连不上。"), s: s)
        }
        #if os(iOS)
        .onAppear { NetworkStatus.shared.start() }
        #endif
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .internet else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

// MARK: Parental controls

private struct ParentalPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        let on = settings.parental.isOn
        register(on: on)
        return AppScroll(model: model, s: s) {
            if on {
                AppNote(text: String(localized: "家长控制已开启，限制了 \(settings.parental.restrictions) 项。输入密码后可以更改。"), s: s)
                AppBigButton(id: "parental.unlock", title: String(localized: "输入密码"), symbol: "lock.open", s: s, model: model) { unlock() }
                AppBigButton(id: "parental.forgot", title: String(localized: "忘记密码"), symbol: "questionmark.circle", s: s, model: model) { forgot() }
            } else {
                AppNote(text: String(localized: "家长控制还没有开启。设一个 4 位密码，就可以限制 3D 影像、导入软件、删除软件和数据。"), s: s)
                AppBigButton(id: "parental.start", title: String(localized: "开始设置"), symbol: "lock.fill", s: s, model: model) { start() }
            }
        }
    }
    private func unlock() { model.pin = ""; model.pinNote = nil; model.push(.parentalPIN(.unlock)) }
    private func forgot() { model.answer = ""; model.push(.parentalForgot) }
    private func start() { model.pin = ""; model.firstPin = ""; model.pinNote = nil; model.push(.parentalPIN(.create)) }
    private func register(on: Bool) {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .parental else { return }
        let ids = on ? ["parental.unlock", "parental.forgot"] : ["parental.start"]
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "parental.unlock": unlock, "parental.forgot": forgot, "parental.start": start]
        model.adjusters = [:]
        model.registered(initial: ids.first)
    }
}

/// The PIN pad: four dots, the digits 0-9 and 删除.
private struct PinPage: View {
    @ObservedObject var model: ConsoleAppModel
    var purpose: ConsoleAppModel.PinPurpose
    var s: Double
    private static let keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["del", "0", "ok"]]
    private var prompt: String {
        switch purpose {
        case .create: return String(localized: "设一个 4 位密码")
        case .confirm: return String(localized: "再输一次，确认密码")
        case .unlock: return String(localized: "输入家长控制的密码")
        case .change: return String(localized: "输入新的 4 位密码")
        case .changeConfirm: return String(localized: "再输一次新密码")
        }
    }
    var body: some View {
        register()
        return VStack(spacing: 6 * s) {
            Text(model.pinNote ?? prompt).font(.system(size: AppMetrics.text(10, s), weight: .bold, design: .rounded))
                .foregroundStyle(model.pinNote == nil ? SystemMenuStyle.ink : SystemMenuStyle.stop)
                .accessibilityIdentifier("pin-prompt")
            HStack(spacing: 10 * s) {
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(index < model.pin.count ? SystemMenuStyle.ink : Color.clear)
                        .overlay(Circle().strokeBorder(SystemMenuStyle.ink, lineWidth: 1.5))
                        .frame(width: 11 * s, height: 11 * s)
                }
            }
            .accessibilityElement().accessibilityLabel("已输入 \(model.pin.count) 位").accessibilityIdentifier("pin-dots")
            VStack(spacing: 4 * s) {
                ForEach(Self.keys, id: \.self) { row in
                    HStack(spacing: 4 * s) {
                        ForEach(row, id: \.self) { key in keyButton(key) }
                    }
                }
            }
        }
        .padding(.horizontal, 30 * s).padding(.vertical, 6 * s)
        .frame(maxHeight: .infinity)
    }
    private func keyButton(_ key: String) -> some View {
        let id = "pin.\(key)"
        let shape = RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
        return Button { model.focus = id; press(key) } label: {
            Group {
                if key == "del" { Image(systemName: "delete.left") }
                else if key == "ok" { Image(systemName: "checkmark") }
                else { Text(key) }
            }
            .font(.system(size: 12 * s, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity).frame(height: 24 * s)
            .foregroundStyle(key == "ok" ? .white : SystemMenuStyle.ink)
            .background(shape.fill(key == "ok" ? SystemMenuStyle.go : SystemMenuStyle.tile))
            .overlay(shape.strokeBorder(SystemMenuStyle.tileEdge.opacity(0.5), lineWidth: 1))
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(key == "del" ? String(localized: "删除") : key == "ok" ? String(localized: "确定") : key)
        .accessibilityIdentifier(id)
    }
    private func press(_ key: String) {
        switch key {
        case "del": if !model.pin.isEmpty { model.pin.removeLast() }
        case "ok": submit()
        default:
            guard model.pin.count < 4 else { return }
            model.pin.append(key)
            model.pinNote = nil
            if model.pin.count == 4 { submit() }
        }
        ConsoleSounds.shared.play(.move)
    }
    private func submit() {
        guard ParentalControls.isValidPIN(model.pin) else { return }
        let entered = model.pin
        model.pin = ""
        switch purpose {
        case .create, .change:
            model.firstPin = entered
            model.replace(with: .parentalPIN(purpose == .create ? .confirm : .changeConfirm))
        case .confirm:
            if entered == model.firstPin { model.replace(with: .parentalQuestion) }
            else { model.pinNote = String(localized: "两次不一样，重新设"); model.replace(with: .parentalPIN(.create)) }
        case .changeConfirm:
            if entered == model.firstPin {
                ConsoleSettings.shared.parental.pin = entered
                model.pop(to: .parentalRestrictions)
                model.say(String(localized: "密码已更改"))
            } else { model.pinNote = String(localized: "两次不一样，重新输"); model.replace(with: .parentalPIN(.change)) }
        case .unlock:
            if ConsoleSettings.shared.parental.unlocks(entered) {
                model.unlocked = true
                model.replace(with: .parentalRestrictions)
            } else {
                model.pinNote = String(localized: "密码不对")
                ConsoleHaptics.shared.play(.sliderStop, .press)
            }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .parentalPIN(purpose) else { return }
        model.layout = Self.keys.map { $0.map { "pin.\($0)" } } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for row in Self.keys { for key in row { handlers["pin.\(key)"] = { press(key) } } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "pin.1")
    }
}

private struct QuestionPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "选一个秘密问题。忘记密码时，答对它就能清除家长控制。"), s: s)
            ForEach(Array(ParentalControls.questions.enumerated()), id: \.offset) { index, question in
                AppRow(id: "question.\(index)", title: question, s: s, selected: settings.parental.question == index, model: model, action: { choose(index) }) {
                    AppValue(text: "", s: s)
                }
            }
        }
    }
    private func choose(_ index: Int) {
        ConsoleSettings.shared.parental.question = index
        model.answer = ""
        model.push(.parentalAnswer)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .parentalQuestion else { return }
        let ids = ParentalControls.questions.indices.map { "question.\($0)" }
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for index in ParentalControls.questions.indices { handlers["question.\(index)"] = { choose(index) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: ids.first)
    }
}

/// The secret answer: typed on the upper screen (the keyboard covers the
/// lower one), checked or kept with 确定.
private struct AnswerPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: model.page == .parentalForgot
                    ? String(localized: "回答设置家长控制时选的问题。答对了，密码和所有限制都会清除。")
                    : String(localized: "在上屏输入答案（键盘会盖住这块屏），再点「确定」。答案不分大小写。"), s: s)
            AppRow(id: "answer.field", title: String(localized: "答案"), s: s, model: model, action: nil) {
                AppValue(text: model.answer.isEmpty ? String(localized: "未输入") : String(repeating: "•", count: model.answer.count), s: s, opens: false)
            }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .parentalAnswer || model.page == .parentalForgot else { return }
        model.layout = [["answer.field"], [ConsoleAppModel.barLeft, ConsoleAppModel.barRight]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        model.adjusters = [:]
        model.registered(initial: "answer.field")
    }
}

private struct RestrictionsPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    private static let rows: [(String, WritableKeyPath<ParentalControls, Bool>)] = [
        ("parental.restrict3D", \.restrict3D), ("parental.restrictImport", \.restrictImport), ("parental.restrictDelete", \.restrictDelete)]
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "「开」的项目被限制。离开家长控制时自动锁上。"), s: s)
            ForEach(Self.rows, id: \.0) { id, path in
                let info = AppItemInfo.catalog[id]!
                AppRow(id: id, title: info.title, s: s, model: model, action: { toggle(path) }) {
                    AppSwitch(isOn: settings.parental[keyPath: path], s: s)
                }
            }
            AppBigButton(id: "parental.change", title: String(localized: "更改密码"), symbol: "key", s: s, model: model) { change() }
            AppBigButton(id: "parental.clear", title: String(localized: "清除家长控制"), symbol: "lock.slash", s: s, model: model) { clear() }
        }
        .onDisappear { if !model.stack.contains(.parentalRestrictions) { model.unlocked = false } }
    }
    private func toggle(_ path: WritableKeyPath<ParentalControls, Bool>) {
        ConsoleSettings.shared.parental[keyPath: path].toggle()
        // 3D restricted: the slider of this console goes down now.
        if path == \ParentalControls.restrict3D, ConsoleSettings.shared.parental.restrict3D { model.session?.setDepth3D(0) }
        ConsoleSounds.shared.play(.click)
    }
    private func change() { model.pin = ""; model.firstPin = ""; model.pinNote = nil; model.push(.parentalPIN(.change)) }
    private func clear() {
        model.confirm(.init(title: String(localized: "清除家长控制？"), message: String(localized: "密码、秘密问题和所有限制都会去掉。"), confirm: String(localized: "清除"), identifier: "parental-clear-confirm") {
            ConsoleSettings.shared.parental = ParentalControls()
            model.unlocked = false
            model.pop(to: .parental)
            model.say(String(localized: "家长控制已清除"))
        })
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .parentalRestrictions else { return }
        let ids = Self.rows.map(\.0) + ["parental.change", "parental.clear"]
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }, "parental.change": change, "parental.clear": clear]
        var adjusters: [String: (Int) -> Void] = [:]
        for (id, path) in Self.rows {
            handlers[id] = { toggle(path) }
            adjusters[id] = { delta in
                let want = delta > 0
                if ConsoleSettings.shared.parental[keyPath: path] != want { toggle(path) }
            }
        }
        model.handlers = handlers
        model.adjusters = adjusters
        model.registered(initial: ids.first)
    }
}

// MARK: Data management

/// The file of a record in the library.
private func gameFile(_ record: GameRecord) -> URL {
    Storage.root.appendingPathComponent("ROMs").appendingPathComponent(record.fileName)
}
private func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
private func folderSize(_ url: URL) -> Int64 {
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let file as URL in walker {
        let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }
    return total
}
private func fileSize(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
}

private struct DataPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    private var items: [(String, ConsoleAppModel.Page)] {
        [("data.software", .dataSoftware), ("data.states", .dataStates), ("data.storage", .dataStorage), ("data.sync", .dataSync), ("data.backup", .dataBackup)]
            + (AzaharSession.isCoreAvailable && !ctx.testFiles.isEmpty ? [("data.tests", .dataTests)] : [])
    }
    var body: some View {
        register()
        return VStack(spacing: 7 * s) {
            ForEach(items, id: \.0) { id, page in
                let info = AppItemInfo.catalog[id]!
                AppBigButton(id: id, title: info.title, symbol: info.symbol, note: note(id), s: s, model: model) { model.push(page) }
            }
        }
        .padding(.horizontal, 14 * s).padding(.vertical, 10 * s)
        .frame(maxHeight: .infinity)
    }
    private func note(_ id: String) -> String? {
        switch id {
        case "data.software": return String(localized: "\(ctx.games.count) 个")
        case "data.tests": return String(localized: "\(ctx.testFiles.count) 个")
        case "data.sync": return !ProAccess.isPro ? String(localized: "典藏卡带") : (SaveSyncModel.shared.enabled ? String(localized: "开") : String(localized: "关"))
        default: return nil
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .data else { return }
        model.layout = items.map { [$0.0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for (id, page) in items { handlers[id] = { model.push(page) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: items.first?.0)
    }
}

private struct SoftwarePage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            if ctx.games.isEmpty {
                AppNote(text: String(localized: "游戏库里还没有软件。回到游戏库，在掌机的主菜单点「导入」，从「文件」添加。"), s: s)
            }
            ForEach(ctx.games) { game in
                AppRow(id: "game.\(game.id)", title: game.title, s: s, model: model, action: { model.push(.dataGame(game.id)) }) {
                    AppValue(text: sizeText(game.byteCount), s: s)
                }
            }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .dataSoftware else { return }
        let ids = ctx.games.map { "game.\($0.id)" }
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for game in ctx.games { handlers["game.\(game.id)"] = { model.push(.dataGame(game.id)) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: ids.first ?? ConsoleAppModel.barLeft)
    }
}

private struct GamePage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var id: String
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    @ObservedObject private var sync = SaveSyncModel.shared
    var body: some View {
        let game = ctx.games.first { $0.id == id }
        register(game)
        return AppScroll(model: model, s: s) {
            if let game {
                let file = gameFile(game)
                let used = SaveStates.usedSlots(for: file)
                let hasManual = !used.isEmpty
                let manualBytes = used.reduce(Int64(0)) { $0 + fileSize(SaveStates.manual(for: file, slot: $1)) }
                let resume = SaveStates.resumeDate(for: file)
                VStack(alignment: .leading, spacing: 1 * s) {
                    AppInfoLine(title: String(localized: "名称"), value: game.title, s: s)
                    if let publisher = game.publisher, !publisher.isEmpty { AppInfoLine(title: String(localized: "发行"), value: publisher, s: s) }
                    AppInfoLine(title: String(localized: "格式"), value: game.resolvedFormat.label, s: s)
                    AppInfoLine(title: String(localized: "大小"), value: sizeText(game.byteCount), s: s)
                    AppInfoLine(title: String(localized: "导入于"), value: game.importedAt.formatted(date: .abbreviated, time: .shortened), s: s)
                    AppInfoLine(title: shownName("即时存档"), value: hasManual ? (used.count > 1 ? String(localized: "\(used.count) 份 · \(sizeText(manualBytes))") : sizeText(manualBytes)) : String(localized: "没有"), s: s)
                    AppInfoLine(title: shownName("继续进度"), value: resume.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "没有"), s: s)
                }
                .padding(.vertical, 4 * s)
                .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
                // 11-05: this game's
                // saves kept on this device only.
                AppRow(id: "game.sync", title: String(localized: "同步这个游戏的存档"), s: s, model: model, action: { toggleSync(game) }) {
                    AppSwitch(isOn: !sync.leftOut.contains(game.id), s: s)
                }
                if settings.parental.restrictDelete {
                    AppNote(text: String(localized: "家长控制限制了删除。"), s: s)
                } else if ctx.suspendedID == game.id {
                    AppNote(text: String(localized: "这个软件正在运行（暂停在主菜单下面）。要移除它，先按 HOME，在主菜单里选它、「关闭软件」。"), s: s)
                        .accessibilityIdentifier("game-running")
                } else {
                    AppBigButton(id: "game.remove", title: String(localized: "移除 \(game.title)"), symbol: "trash", note: String(localized: "游戏副本和图标；手动存档留着，原文件不动"), noteLines: 3, s: s, model: model) { remove(game) }
                }
            } else {
                AppNote(text: String(localized: "这个软件已经不在游戏库里了。"), s: s)
            }
        }
    }
    private func toggleSync(_ game: GameRecord) {
        let out = !sync.leftOut.contains(game.id)
        sync.setLeftOut(game.id, out)
        ConsoleSounds.shared.play(.click)
        model.say(out ? String(localized: "「\(game.title)」的存档只留在这台设备上") : String(localized: "「\(game.title)」的存档跟着同步"))
    }
    private func remove(_ game: GameRecord) {
        model.confirm(.init(title: String(localized: "移除「\(game.title)」？"), message: String(localized: "删除 Zero EMU 里的游戏副本和图标，继续进度也一起删掉。手动存档留着，「文件」里的原文件不动；再导入同一个文件就回来了。"),
                            confirm: String(localized: "移除副本"), identifier: "移除副本") {
            ctx.remove(game)
            model.pop()
            model.say(String(localized: "已移除 \(game.title)"))
        })
    }
    private func register(_ game: GameRecord?) {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .dataGame(id) else { return }
        let removable = game != nil && !ConsoleSettings.shared.parental.restrictDelete && ctx.suspendedID != id
        model.layout = (game != nil ? [["game.sync"]] : []) + (removable ? [["game.remove"]] : []) + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        if let game { handlers["game.sync"] = { toggleSync(game) } }
        if let game, removable { handlers["game.remove"] = { remove(game) } }
        model.handlers = handlers
        model.adjusters = game.map { game in ["game.sync": { delta in if sync.leftOut.contains(game.id) == (delta > 0) { toggleSync(game) } }] } ?? [:]
        model.registered(initial: game != nil ? "game.sync" : ConsoleAppModel.barLeft)
    }
}

/// Every state file: the manual slot and the resume state of each game.
private struct StatesPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    @ViewState private var revision = 0
    private struct Entry: Identifiable { var id: String; var title: String; var kind: String; var url: URL; var date: Date?; var bytes: Int64 }
    private var entries: [Entry] {
        var list: [Entry] = []
        for game in ctx.games {
            let file = gameFile(game)
            // Every 存档位 with something in it (the first keeps the id it had).
            for slot in SaveStates.usedSlots(for: file).sorted() {
                let manual = SaveStates.manual(for: file, slot: slot)
                list.append(Entry(id: slot == 1 ? "state.m.\(game.id)" : "state.m\(slot).\(game.id)", title: slot == 1 ? game.title : "\(game.title) · \(slot)", kind: "即时存档", url: manual,
                                  date: SaveStates.readInfo(for: manual)?.saved, bytes: fileSize(manual)))
            }
            let resume = SaveStates.resume(for: file)
            if FileManager.default.fileExists(atPath: resume.path) {
                list.append(Entry(id: "state.r.\(game.id)", title: game.title, kind: "继续进度", url: resume,
                                  date: SaveStates.resumeDate(for: file), bytes: fileSize(resume)))
            }
        }
        return list
    }
    var body: some View {
        let list = entries
        let _ = revision
        register(list)
        return AppScroll(model: model, s: s) {
            if list.isEmpty { AppNote(text: String(localized: "还没有即时存档。游戏里按 HOME，点「保存进度」就会存一个。"), s: s) }
            ForEach(list) { entry in
                AppRow(id: entry.id, title: "\(entry.title) · \(shownName(entry.kind))", s: s, model: model, action: { delete(entry) }) {
                    AppValue(text: [entry.date?.formatted(date: .numeric, time: .shortened), sizeText(entry.bytes)].compactMap { $0 }.joined(separator: " · "), s: s, opens: false)
                }
            }
            if !list.isEmpty {
                AppNote(text: settings.parental.restrictDelete ? String(localized: "家长控制限制了删除。") : String(localized: "点一项可以删除它。"), s: s)
            }
        }
    }
    private func delete(_ entry: Entry) {
        guard !ConsoleSettings.shared.parental.restrictDelete else { model.say(String(localized: "家长控制限制了删除")); return }
        let synced = SaveSyncModel.shared.active && entry.kind == "即时存档"
        model.confirm(.init(title: String(localized: "删除\(shownName(entry.kind))？"), message: String(localized: "「\(entry.title)」的\(shownName(entry.kind))会被删除，删掉就找不回来了。") + (synced ? UILanguage.gap + String(localized: "存档同步开着：别的设备上的这一份下次同步时也会删掉（放进 Conflicts）。") : ""), confirm: String(localized: "删除"), identifier: "state-delete-confirm") {
            // 11-05: the deletion goes across with 存档同步.
            if entry.kind == "即时存档" { SaveSyncModel.shared.noteDeleted(state: entry.url) }
            try? FileManager.default.removeItem(at: entry.url)
            try? FileManager.default.removeItem(at: SaveStates.info(for: entry.url))
            revision += 1
            model.focus = nil
            model.say(String(localized: "已删除"))
        })
    }
    private func register(_ list: [Entry]) {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .dataStates else { return }
        model.layout = list.map { [$0.id] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for entry in list { handlers[entry.id] = { delete(entry) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: list.first?.id ?? ConsoleAppModel.barLeft)
    }
}

/// The core's test files (developer aid; the library's settings page had
/// them before round 23).
private struct TestFilesPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "Application Support/FoldArc/CoreTest 里的文件，直接在核心上开启（不进游戏库）。"), s: s)
            if let suspended = ctx.suspended {
                AppNote(text: String(localized: "「\(suspended)」正在运行：先在主菜单里关闭它，再开测试文件。"), s: s)
            } else {
                testList
            }
        }
    }
    private var testList: some View {
        ForEach(ctx.testFiles, id: \.self) { url in
            AppRow(id: "test.\(url.lastPathComponent)", title: url.lastPathComponent, s: s, model: model, action: { ctx.launchTestFile(url) }) {
                Image(systemName: "play.fill").font(.system(size: 9 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.inkSoft)
            }
            .accessibilityLabel("核心测试：\(url.lastPathComponent)")
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .dataTests else { return }
        let ids = ctx.suspended == nil ? ctx.testFiles.map { "test.\($0.lastPathComponent)" } : []
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        if ctx.suspended == nil { for url in ctx.testFiles { handlers["test.\(url.lastPathComponent)"] = { ctx.launchTestFile(url) } } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: ids.first ?? ConsoleAppModel.barLeft)
    }
}

private struct StoragePage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ViewState private var sizes: (games: Int64, states: Int64, console: Int64)?
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            VStack(alignment: .leading, spacing: 1 * s) {
                AppInfoLine(title: String(localized: "游戏副本（\(ctx.games.count) 个）"), value: sizes.map { sizeText($0.games) } ?? String(localized: "计算中…"), s: s)
                AppInfoLine(title: String(localized: "即时存档和继续进度"), value: sizes.map { sizeText($0.states) } ?? String(localized: "计算中…"), s: s)
                AppInfoLine(title: String(localized: "主机存储（SD 卡、系统存储、游戏存档）"), value: sizes.map { sizeText($0.console) } ?? String(localized: "计算中…"), s: s)
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            AppNote(text: String(localized: "主机存储在「文件」App 的「我的 iPhone › Zero EMU › Azahar」里，可以备份、拷到电脑，或者放 Homebrew。"), s: s)
        }
        .task {
            let roms = Storage.root.appendingPathComponent("ROMs")
            let states = SaveStates.folder
            let console = Storage.filesFolder.appendingPathComponent("Azahar")
            sizes = await Task.detached(priority: .utility) { (folderSize(roms), folderSize(states), folderSize(console)) }.value
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .dataStorage else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

// MARK: Profile

private struct ProfilePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        let profile = settings.profile
        register()
        return AppScroll(model: model, s: s) {
            AppRow(id: "profile.name", title: String(localized: "用户名"), s: s, model: model, action: { open(.profileName) }) {
                AppValue(text: profile.userName.isEmpty ? String(localized: "未设置") : profile.userName, s: s)
            }
            AppRow(id: "profile.birthday", title: String(localized: "生日"), s: s, model: model, action: { open(.profileBirthday) }) {
                AppValue(text: profile.birthdayText, s: s)
            }
            AppRow(id: "profile.country", title: String(localized: "国家/地区"), s: s, model: model, action: { open(.profileCountry) }) {
                AppValue(text: profile.countryName, s: s)
            }
            AppRow(id: "profile.region", title: String(localized: "主机区域"), s: s, model: model, action: { open(.profileRegion) }) {
                AppValue(text: profile.region.title, s: s)
            }
            AppNote(text: String(localized: "语言和主机区域在下次开启软件时交给模拟的主机。"), s: s)
        }
    }
    private func open(_ page: ConsoleAppModel.Page) {
        model.draft = ConsoleSettings.shared.profile
        model.push(page)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .profile else { return }
        let ids = ["profile.name", "profile.birthday", "profile.country", "profile.region"]
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          "profile.name": { open(.profileName) }, "profile.birthday": { open(.profileBirthday) },
                          "profile.country": { open(.profileCountry) }, "profile.region": { open(.profileRegion) }]
        model.adjusters = [:]
        model.registered(initial: ids.first)
    }
}

/// The name: typed on the upper screen; here what it is and the limit.
private struct NamePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        let name = model.draft.userName
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "在上屏的输入框里输入名字（键盘会盖住这块屏），最多 10 个字。软件里显示的主人的名字就是它。"), s: s)
            AppRow(id: "name.field", title: String(localized: "用户名"), s: s, model: model, action: nil) {
                AppValue(text: name.isEmpty ? String(localized: "未输入") : name, s: s, opens: false)
            }
            if model.draft.nameLength > ConsoleProfile.nameLimit {
                AppNote(text: String(localized: "名字最多 10 个字（汉字算 1 个，表情符号可能算 2 个）。"), s: s)
            }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .profileName || model.page == .setupName else { return }
        model.layout = [["name.field"], [ConsoleAppModel.barLeft, ConsoleAppModel.barRight]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        model.adjusters = [:]
        model.registered(initial: "name.field")
    }
}

private struct BirthdayPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "用十字键左右，或者点箭头。生日那天，有的软件会祝你生日快乐。"), s: s)
            AppRow(id: "birthday.month", title: String(localized: "月"), s: s, interactive: true, model: model, action: nil) {
                AppStepper(text: String(localized: "\(model.draft.birthMonth) 月"), s: s) { model.draft.stepBirthday(month: $0); ConsoleSounds.shared.play(.move) }
            }
            AppRow(id: "birthday.day", title: String(localized: "日"), s: s, interactive: true, model: model, action: nil) {
                AppStepper(text: String(localized: "\(model.draft.birthDay) 日"), s: s) { model.draft.stepBirthday(day: $0); ConsoleSounds.shared.play(.move) }
            }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .profileBirthday || model.page == .setupBirthday else { return }
        let right = model.page == .setupBirthday || model.page == .profileBirthday
        model.layout = [["birthday.month"], ["birthday.day"], right ? [ConsoleAppModel.barLeft, ConsoleAppModel.barRight] : [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        model.adjusters = ["birthday.month": { model.draft.stepBirthday(month: $0); ConsoleSounds.shared.play(.move) },
                           "birthday.day": { model.draft.stepBirthday(day: $0); ConsoleSounds.shared.play(.move) }]
        model.registered(initial: "birthday.month")
    }
}

private struct CountryPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(ConsoleCountry.all) { country in
                AppRow(id: "country.\(country.code)", title: country.name, s: s, selected: model.draft.country == country.code, model: model,
                       action: { choose(country) }) {
                    if model.draft.country == country.code { Image(systemName: "checkmark").font(.system(size: 10 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.accent) }
                }
            }
        }
    }
    private func choose(_ country: ConsoleCountry) {
        model.draft.country = country.code
        ConsoleSounds.shared.play(.click)
        if model.page == .profileCountry {
            ConsoleSettings.shared.profile.country = country.code
            model.say(String(localized: "国家/地区：\(country.name)"))
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .profileCountry || model.page == .setupCountry else { return }
        let ids = ConsoleCountry.all.map { "country.\($0.code)" }
        let setup = model.page == .setupCountry
        model.layout = ids.map { [$0] } + [setup ? [ConsoleAppModel.barLeft, ConsoleAppModel.barRight] : [ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() },
                                              ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        for country in ConsoleCountry.all { handlers["country.\(country.code)"] = { choose(country) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "country.\(model.draft.country)")
    }
}

private struct RegionPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "有的软件只在自己的区域开得了。「自动」跟着软件。下次开启软件时生效。"), s: s)
            ForEach(ConsoleRegion.allCases) { region in
                AppRow(id: "region.\(region.rawValue)", title: region.title, s: s, selected: settings.profile.region == region, model: model,
                       action: { choose(region) }) {
                    Text(region.code).font(.system(size: AppMetrics.text(8.5, s), weight: .bold, design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
                }
            }
        }
    }
    private func choose(_ region: ConsoleRegion) {
        ConsoleSettings.shared.profile.region = region
        ConsoleSounds.shared.play(.click)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .profileRegion else { return }
        let ids = ConsoleRegion.allCases.map { "region.\($0.rawValue)" }
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for region in ConsoleRegion.allCases { handlers["region.\(region.rawValue)"] = { choose(region) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "region.\(ConsoleSettings.shared.profile.region.rawValue)")
    }
}

// MARK: Date, touch, stick

private struct DateTimePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 1 * s) {
                    AppInfoLine(title: String(localized: "日期"), value: context.date.formatted(.dateTime.locale(UILanguage.locale).year().month().day().weekday(.wide)), s: s)
                    AppInfoLine(title: String(localized: "时间"), value: context.date.formatted(.dateTime.locale(UILanguage.locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)), s: s)
                }
                .padding(.vertical, 4 * s)
                .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            }
            AppNote(text: String(localized: "主机的时间跟着这台 iPhone，软件读到的也是它。要改，到 iPhone 的「设置 › 通用 › 日期与时间」里改。"), s: s)
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .dateTime || model.page == .setupDateTime else { return }
        let setup = model.page == .setupDateTime
        model.layout = [setup ? [ConsoleAppModel.barLeft, ConsoleAppModel.barRight] : [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        model.adjusters = [:]
        model.registered(initial: setup ? ConsoleAppModel.barRight : ConsoleAppModel.barLeft)
    }
}

private struct TouchPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return VStack(alignment: .leading, spacing: 6 * s) {
            AppBigButton(id: "touch.calibrate", title: String(localized: "校正"), symbol: "scope",
                         note: settings.touch.isNeutral ? String(localized: "现在没有校正") : String(format: String(localized: "现在偏移 %+.1f%%, %+.1f%%"), settings.touch.dx * 100, settings.touch.dy * 100),
                         s: s, model: model) { calibrate() }
            HStack(spacing: 6 * s) {
                Text("试一试：在下面点或画").font(.system(size: AppMetrics.text(9, s), weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                Spacer()
                if !settings.touch.isNeutral {
                    Button("恢复默认") { settings.touch = TouchCalibration(); model.say(String(localized: "已恢复默认")) }
                        .font(.system(size: AppMetrics.text(9, s), weight: .bold)).accessibilityIdentifier("touch-reset")
                }
            }
            TrialArea(model: model, s: s)
        }
        .padding(.horizontal, 12 * s).padding(.vertical, 8 * s)
    }
    private func calibrate() { model.calibrationTouches = []; model.push(.touchCalibrate) }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .touch else { return }
        model.layout = [["touch.calibrate"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "touch.calibrate": calibrate]
        model.adjusters = [:]
        model.registered(initial: "touch.calibrate")
    }
}

/// Dots where the screen was touched, with the correction applied.
private struct TrialArea: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous).fill(SystemMenuStyle.tile)
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous).strokeBorder(SystemMenuStyle.tileEdge.opacity(0.5), lineWidth: 1)
                ForEach(Array(model.trialTouches.suffix(40).enumerated()), id: \.offset) { _, point in
                    Circle().fill(SystemMenuStyle.accent.opacity(0.8)).frame(width: 5 * s, height: 5 * s)
                        .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard proxy.size.width > 0, proxy.size.height > 0 else { return }
                let raw = Point(x: value.location.x / proxy.size.width, y: value.location.y / proxy.size.height)
                model.trialTouches.append(ConsoleSettings.shared.touch.apply(raw))
            })
        }
        .accessibilityElement().accessibilityLabel("触摸试验区").accessibilityIdentifier("touch-trial")
    }
}

/// Three targets, one after the other; each touch is kept.
private struct CalibratePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        let index = model.calibrationTouches.count
        let targets = TouchCalibration.targets
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.35)
                if index < targets.count {
                    let target = targets[index]
                    ZStack {
                        Circle().strokeBorder(SystemMenuStyle.stop, lineWidth: 2).frame(width: 22 * s, height: 22 * s)
                        Rectangle().fill(SystemMenuStyle.stop).frame(width: 30 * s, height: 1.5)
                        Rectangle().fill(SystemMenuStyle.stop).frame(width: 1.5, height: 30 * s)
                    }
                    .position(x: target.x * proxy.size.width, y: target.y * proxy.size.height)
                    .accessibilityElement().accessibilityLabel("校正目标 \(index + 1)").accessibilityIdentifier("calibration-target")
                    Text("点红色十字的中心（\(index + 1)/\(targets.count)）").font(.system(size: AppMetrics.text(9, s), weight: .bold))
                        .foregroundStyle(SystemMenuStyle.inkSoft).frame(maxWidth: .infinity).padding(.top, 4 * s)
                } else {
                    let fit = TouchCalibration.fit(targets: targets, touches: model.calibrationTouches)
                    Text(fit.map { String(format: String(localized: "偏移 %+.1f%%、%+.1f%%。点「保存」用它。"), $0.dx * 100, $0.dy * 100) } ?? String(localized: "偏得太多，点「保存」会重来。"))
                        .font(.system(size: AppMetrics.text(10, s), weight: .bold)).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("calibration-result")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard index < targets.count, proxy.size.width > 0, proxy.size.height > 0 else { return }
                model.calibrationTouches.append(Point(x: location.x / proxy.size.width, y: location.y / proxy.size.height))
                ConsoleSounds.shared.play(.click)
            }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .touchCalibrate else { return }
        let done = model.calibrationTouches.count == TouchCalibration.targets.count
        model.layout = [done ? [ConsoleAppModel.barLeft, ConsoleAppModel.barRight] : [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        model.adjusters = [:]
        model.registered(initial: done ? ConsoleAppModel.barRight : ConsoleAppModel.barLeft)
    }
}

private struct CirclePadPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "推一推掌机的摇杆（或外接手柄的左摇杆），上屏显示它推到了哪里。死区是中间不算数的范围：摇杆回不到正中时调大一点。"), s: s)
            AppRow(id: "stick.deadzone", title: String(localized: "死区"), s: s, interactive: true, model: model, action: nil) {
                AppStepper(text: "\(Int((settings.stickDeadzone * 100).rounded()))%", s: s) { adjust($0) }
            }
        }
    }
    private func adjust(_ delta: Int) {
        settings.stickDeadzone = min(StickTuning.maximumDeadzone, max(0, ((settings.stickDeadzone * 100).rounded() + Double(delta) * 2) / 100))
        ConsoleSounds.shared.play(.move)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .circlePad else { return }
        model.layout = [["stick.deadzone"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = ["stick.deadzone": { adjust($0) }]
        model.registered(initial: "stick.deadzone")
    }
}

// MARK: Sound, mic, language, 3D

private struct SoundPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    @ObservedObject private var volume = ConsoleVolume.shared
    #if os(iOS)
    @ObservedObject private var audio = SystemAudio.shared
    #endif
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(SoundOutput.allCases) { mode in
                AppRow(id: "sound.\(mode.rawValue)", title: mode.title, s: s, selected: settings.soundOutput == mode, model: model, action: { choose(mode) }) {
                    if settings.soundOutput == mode { Image(systemName: "checkmark").font(.system(size: 10 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.accent) }
                }
            }
            // 11-05: the silent switch, and another
            // app's music (AudioPolicy).
            AppRow(id: "sound.silent", title: String(localized: "静音模式时也出声"), s: s, model: model, action: { setSilent(!settings.soundInSilentMode) }) {
                AppSwitch(isOn: settings.soundInSilentMode, s: s)
            }
            AppRow(id: "sound.others", title: String(localized: "别的 App 在放音乐时"), s: s, interactive: true, model: model, action: nil) {
                AppStepper(text: settings.otherAudio.title, s: s, choices: true) { stepOthers($0) }
            }
            AppNote(text: (settings.soundInSilentMode
                           ? String(localized: "iPhone 拨到静音时游戏照样出声，像掌机一样只听左边的 VOL 滑块；想跟着 iPhone 的静音走，就关掉这一项。")
                           : String(localized: "iPhone 拨到静音时游戏不出声，和 iPhone 的铃声一样。"))
                    + UILanguage.gap + String(localized: "别的 App 在放音乐时「\(settings.otherAudio.title)」：\(settings.otherAudio.detail)"), s: s)
                .accessibilityIdentifier("sound-policy-note")
            VStack(alignment: .leading, spacing: 1 * s) {
                AppInfoLine(title: String(localized: "音量"), value: volume.level == 0 ? String(localized: "静音") : "\(Int((volume.level * 100).rounded()))%", s: s)
                #if os(iOS)
                AppInfoLine(title: String(localized: "耳机"), value: audio.headphones ? String(localized: "已接上（\(audio.outputName)）") : String(localized: "没有接"), s: s)
                #endif
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            AppNote(text: volume.followsSystem ? String(localized: "音量就是 iPhone 的音量：掌机左边的 VOL 滑块和 iPhone 的音量键调的是同一个。") : String(localized: "音量用掌机左边的 VOL 滑块，或者 iPhone 的音量键。"), s: s)
        }
    }
    private func choose(_ mode: SoundOutput) {
        settings.soundOutput = mode
        ConsoleSounds.shared.play(.click)
    }
    private func setSilent(_ on: Bool) {
        guard settings.soundInSilentMode != on else { return }
        settings.soundInSilentMode = on
        ConsoleSounds.shared.play(.click)
        NSLog("[audio] 静音模式时也出声: %@", on ? "on" : "off")
    }
    private func stepOthers(_ delta: Int) {
        let all = OtherAudio.allCases
        let at = all.firstIndex(of: settings.otherAudio) ?? 0
        settings.otherAudio = all[(at + delta + all.count) % all.count]
        ConsoleSounds.shared.play(.move)
        NSLog("[audio] 别的 App 在放音乐时: %@", settings.otherAudio.rawValue)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .sound else { return }
        let ids = SoundOutput.allCases.map { "sound.\($0.rawValue)" }
        model.layout = ids.map { [$0] } + [["sound.silent"], ["sound.others"], [ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }, "sound.silent": { setSilent(!settings.soundInSilentMode) }]
        for mode in SoundOutput.allCases { handlers["sound.\(mode.rawValue)"] = { choose(mode) } }
        model.handlers = handlers
        model.adjusters = ["sound.silent": { delta in setSilent(delta > 0) }, "sound.others": { stepOthers($0) }]
        model.registered(initial: "sound.\(settings.soundOutput.rawValue)")
    }
}

private struct MicPage: View {
    @ObservedObject var model: ConsoleAppModel
    @ObservedObject var session: DemoSession
    /// The iPhone's microphone, on while this page is.
    @ObservedObject private var mic = MicListener.shared
    var s: Double
    var body: some View {
        register()
        return VStack(spacing: 10 * s) {
            Image(systemName: session.micBlowing ? "mic.fill" : "mic").font(.system(size: 26 * s, weight: .semibold))
                .foregroundStyle(session.micBlowing ? SystemMenuStyle.go : SystemMenuStyle.inkSoft)
            Text(session.micBlowing ? String(localized: "收到了：呼——") : prompt).font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("mic-state")
            AppNote(text: note, s: s)
        }
        .padding(.horizontal, 16 * s)
        .frame(maxHeight: .infinity)
        .onAppear { session.listenMic("mic-test", true) }
        .onDisappear { session.listenMic("mic-test", false) }
    }
    private var prompt: String {
        switch mic.access {
        case .granted, .unknown: return String(localized: "对着 iPhone 吹气")
        case .denied: return String(localized: "麦克风没打开：设置 › Zero EMU › 麦克风")
        case .unavailable: return String(localized: "按住掌机上的 MIC 吹气")
        }
    }
    private var note: String {
        switch mic.access {
        case .unavailable:
            return String(localized: "这里没有麦克风：按住掌机上的 MIC，主机就收到一阵吹气的声音，要吹气的软件用它。")
        default:
            return String(localized: "对着 iPhone 吹气（箭头指着掌机上的 MIC；iPhone 的麦克风在 USB-C 口旁边），或者按住 MIC 孔，主机都收到一阵吹气的声音。Zero EMU 只听有没有在吹，不录音。")
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .mic else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

private struct LanguagePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        let current = model.page == .setupLanguage ? model.draft.language : ConsoleSettings.shared.profile.language
        return AppScroll(model: model, s: s) {
            ForEach(ConsoleLanguage.allCases) { language in
                AppRow(id: "language.\(language.rawValue)", title: language.title, s: s, selected: current == language, model: model, action: { choose(language) }) {
                    if current == language { Image(systemName: "checkmark").font(.system(size: 10 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.accent) }
                }
            }
        }
    }
    private func choose(_ language: ConsoleLanguage) {
        model.draft.language = language
        if model.page == .language { ConsoleSettings.shared.chooseLanguage(language); model.say(String(localized: "下次打开 Zero EMU 时，菜单和软件都换成这个语言")) }
        ConsoleSounds.shared.play(.click)
        model.objectWillChange.send()
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .language || model.page == .setupLanguage else { return }
        let ids = ConsoleLanguage.allCases.map { "language.\($0.rawValue)" }
        let setup = model.page == .setupLanguage
        model.layout = ids.map { [$0] } + [setup ? [ConsoleAppModel.barLeft, ConsoleAppModel.barRight] : [ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() },
                                              ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        for language in ConsoleLanguage.allCases { handlers["language.\(language.rawValue)"] = { choose(language) } }
        model.handlers = handlers
        model.adjusters = [:]
        let current = setup ? model.draft.language : ConsoleSettings.shared.profile.language
        model.registered(initial: "language.\(current.rawValue)")
    }
}

private struct Screen3DPage: View {
    @ObservedObject var model: ConsoleAppModel
    @ObservedObject var session: DemoSession
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppInfoLine(title: String(localized: "3D 滑块"), value: session.depth3D == 0 ? String(localized: "关") : "\(Int((session.depth3D * 100).rounded()))%", s: s)
            AppNote(text: settings.parental.restrict3D
                    ? String(localized: "家长控制限制了 3D 影像：滑块推不上去。")
                    : String(localized: "推一推上屏右边的 3D 滑块，上屏的测试图分成红蓝两层。戴红蓝眼镜看，离得越远的越靠后。拉到底是 2D。"), s: s)
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .screen3D else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

// MARK: Power, brightness, rendering, haptics

private struct PowerPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppRow(id: "power.toggle", title: String(localized: "省电模式"), s: s, model: model, action: { toggle() }) { AppSwitch(isOn: settings.powerSaving, s: s) }
            AppNote(text: String(localized: "开着时：两块屏的亮度最高 75%；游戏用复古 1× 分辨率（下次开启时生效），GPU 少算很多。"), s: s)
        }
    }
    private func toggle() { settings.powerSaving.toggle(); ConsoleSounds.shared.play(.click) }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .power else { return }
        model.layout = [["power.toggle"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "power.toggle": toggle]
        model.adjusters = ["power.toggle": { delta in if settings.powerSaving != (delta > 0) { toggle() } }]
        model.registered(initial: "power.toggle")
    }
}

private struct BrightnessPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("foldarc.brightness") private var brightness = 1.0
    var body: some View {
        register()
        let level = BrightnessSteps.level(for: brightness)
        return AppScroll(model: model, s: s) {
            AppRow(id: "brightness.level", title: String(localized: "亮度"), s: s, interactive: true, model: model, action: nil) {
                AppStepper(text: "\(level) / 5", s: s) { step($0) }
            }
            HStack(spacing: 4 * s) {
                ForEach(1...5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3 * s).fill(index <= level ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge.opacity(0.5))
                        .frame(height: 8 * s + Double(index) * 2 * s)
                }
            }
            .frame(height: 20 * s, alignment: .bottom)
            .padding(.horizontal, 10 * s)
            if ConsoleSettings.shared.powerSaving { AppNote(text: String(localized: "省电模式开着：最亮也只有 75%。"), s: s) }
        }
    }
    private func step(_ delta: Int) {
        let level = min(5, max(1, BrightnessSteps.level(for: brightness) + delta))
        brightness = BrightnessSteps.levels[level - 1]
        ConsoleSounds.shared.play(.move)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .brightness else { return }
        model.layout = [["brightness.level"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = ["brightness.level": { step($0) }]
        model.registered(initial: "brightness.level")
    }
}

/// The settings that were in the library's 设置 page before round 23.
private struct RenderingPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("FoldArc.renderer") private var renderer = AzaharSession.Renderer.vulkan.rawValue
    @AppStorage("FoldArc.resolutionFactor") private var resolutionFactor = 1
    @AppStorage("FoldArc.retroPixels") private var retroPixels = false
    var body: some View {
        register()
        let vulkan = renderer == AzaharSession.Renderer.vulkan.rawValue
        return AppScroll(model: model, s: s) {
            AppRow(id: "render.renderer", title: String(localized: "渲染器"), s: s, interactive: true, model: model, action: nil) {
                Picker("渲染器", selection: $renderer) {
                    Text("Vulkan").tag(AzaharSession.Renderer.vulkan.rawValue)
                    Text("软件").tag(AzaharSession.Renderer.software.rawValue)
                }
                .pickerStyle(.segmented).frame(width: 128 * s)
                .accessibilityIdentifier("renderer-picker")
            }
            AppRow(id: "render.resolution", title: String(localized: "内部分辨率"), s: s, interactive: true, model: model, action: nil) {
                Picker("内部分辨率", selection: $resolutionFactor) {
                    Text("复古 1×").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                }
                .pickerStyle(.segmented).frame(width: 186 * s)
                .disabled(!vulkan)
                .accessibilityIdentifier("resolution-picker")
            }
            AppRow(id: "render.pixels", title: String(localized: "像素原尺寸显示"), s: s, model: model, action: { retroPixels.toggle() }) {
                AppSwitch(isOn: retroPixels, s: s)
            }
            .accessibilityIdentifier("retro-pixels-toggle")
            AppNote(text: vulkan
                    ? String(localized: "Vulkan 经 MoltenVK 跑在 Metal 上，不能用时自动改用软件渲染。复古 1× 是原机的 400×240，最省电。像素原尺寸：按整数倍放大，画面小一圈但每个像素方正。下次开启软件时生效。")
                    : String(localized: "软件渲染只有原生分辨率，最稳但最慢。像素原尺寸：按整数倍放大，每个像素方正。下次开启软件时生效。"), s: s)
            if ConsoleSettings.shared.powerSaving { AppNote(text: String(localized: "省电模式开着：游戏会用复古 1×。"), s: s) }
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .rendering else { return }
        model.layout = [["render.renderer"], ["render.resolution"], ["render.pixels"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "render.pixels": { retroPixels.toggle() }]
        model.adjusters = [
            "render.renderer": { delta in renderer = delta < 0 ? AzaharSession.Renderer.vulkan.rawValue : AzaharSession.Renderer.software.rawValue },
            "render.resolution": { delta in if renderer == AzaharSession.Renderer.vulkan.rawValue { resolutionFactor = min(3, max(1, resolutionFactor + delta)) } },
            "render.pixels": { delta in retroPixels = delta > 0 },
        ]
        model.registered(initial: "render.renderer")
    }
}

private struct HapticsPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("foldarc.haptics") private var haptics = true
    @AppStorage(ConsoleHaptics.strengthKey) private var strength = ConsoleHaptics.defaultStrength
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppRow(id: "haptics.toggle", title: String(localized: "按键震动"), s: s, model: model, action: { haptics.toggle() }) { AppSwitch(isOn: haptics, s: s) }
            if haptics {
                AppRow(id: "haptics.strength", title: String(localized: "震动强度"), s: s, interactive: true, model: model, action: nil) {
                    AppStepper(text: "\(Int((strength * 100).rounded()))%", s: s) { step($0) }
                }
            }
            AppNote(text: String(localized: "掌机的每个键按下、松开时 iPhone 震一下，像按到真的键。模拟器里感觉不到。"), s: s)
        }
    }
    private func step(_ delta: Int) {
        strength = min(1, max(0.2, ((strength * 10).rounded() + Double(delta)) / 10))
        ConsoleHaptics.shared.play(.faceButton, .press, enabled: true)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .haptics else { return }
        model.layout = (haptics ? [["haptics.toggle"], ["haptics.strength"]] : [["haptics.toggle"]]) + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "haptics.toggle": { haptics.toggle() }]
        model.adjusters = ["haptics.toggle": { delta in haptics = delta > 0 }, "haptics.strength": { step($0) }]
        model.registered(initial: "haptics.toggle")
    }
}

/// 其他设置 › 主菜单顶上的按键 (11-15): each of the menu's small icons on
/// or off (a new console has all but 铅笔盒, which has its tile). 保存进度
/// and 读取进度 only ever come with software suspended under the menu;
/// 存档位, 按键点屏 and 倍速 with a game.
private struct HomeRowPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(ConsoleHomeShortcut.hiddenKey) private var hiddenText = ConsoleHomeShortcut.hiddenAtFirst
    var body: some View {
        register()
        let hidden = ConsoleHomeShortcut.parse(hiddenText)
        return AppScroll(model: model, s: s) {
            ForEach(ConsoleHomeShortcut.listed) { shortcut in
                AppRow(id: Self.id(shortcut), title: shortcut.title, s: s, model: model, action: { toggle(shortcut) }) {
                    HStack(spacing: 7 * s) {
                        Image(systemName: shortcut.symbol).font(.system(size: 11 * s, weight: .semibold))
                            .foregroundStyle(SystemMenuStyle.inkSoft).accessibilityHidden(true)
                        AppSwitch(isOn: !hidden.contains(shortcut), s: s)
                    }
                }
                .accessibilityValue(hidden.contains(shortcut) ? Text("关") : Text("开"))
            }
            AppNote(text: String(localized: "开着的才出现在主菜单最上面那一排。保存进度、读取进度只在有软件暂停着时出现；存档位、按键点屏、倍速只在游戏暂停着时出现。铅笔盒、画面滤镜这些也都在主菜单的图标里或系统设置里。"), s: s)
        }
    }
    static func id(_ shortcut: ConsoleHomeShortcut) -> String { "homeRow.\(shortcut.rawValue)" }
    /// The upper screen on a row: the icon and what it does, and when it is there.
    static func info(_ id: String) -> (title: String, symbol: String, text: String)? {
        guard id.hasPrefix("homeRow."), let shortcut = ConsoleHomeShortcut(rawValue: String(id.dropFirst("homeRow.".count))) else { return nil }
        let when = shortcut.onlyOverGame ? String(localized: "（只在游戏暂停着时出现）")
            : shortcut.onlyOverSoftware ? String(localized: "（只在有软件暂停着时出现）") : ""
        return (shortcut.title, shortcut.symbol, shortcut.blurb + when)
    }
    private func set(_ shortcut: ConsoleHomeShortcut, _ on: Bool) {
        var hidden = ConsoleHomeShortcut.parse(hiddenText)
        guard hidden.contains(shortcut) == on else { return }
        if on { hidden.remove(shortcut) } else { hidden.insert(shortcut) }
        hiddenText = ConsoleHomeShortcut.text(hidden)
        ConsoleSounds.shared.play(.click)
        NSLog("[home] row: %@ %@", shortcut.rawValue, on ? "on" : "off")
    }
    private func toggle(_ shortcut: ConsoleHomeShortcut) {
        set(shortcut, ConsoleHomeShortcut.parse(hiddenText).contains(shortcut))
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .homeRow else { return }
        let ids = ConsoleHomeShortcut.listed.map(Self.id)
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        var adjusters: [String: (Int) -> Void] = [:]
        for shortcut in ConsoleHomeShortcut.listed {
            handlers[Self.id(shortcut)] = { toggle(shortcut) }
            adjusters[Self.id(shortcut)] = { delta in set(shortcut, delta > 0) }
        }
        model.handlers = handlers
        model.adjusters = adjusters
        model.registered(initial: ids[0])
    }
}

// MARK: 画面滤镜, 手柄

/// 画面滤镜: one of five, at once (the upper screen shows it on a picture).
private struct FilterPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(ScreenFilter.defaultsKey) private var filterID = ScreenFilter.sharp.rawValue
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(ScreenFilter.allCases) { filter in
                let selected = filter.rawValue == filterID
                AppRow(id: "filter.\(filter.rawValue)", title: filter.title, s: s, selected: selected, model: model, action: { choose(filter) }) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12 * s))
                        .foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
                }
            }
            AppNote(text: String(localized: "滤镜只盖在游戏画面上（主菜单和设置不变），换了马上生效，电视上也一样。一个像素在屏幕上小于一个点时，线条会自动变淡。"), s: s)
        }
    }
    private func choose(_ filter: ScreenFilter) {
        guard filter.rawValue != filterID else { return }
        filterID = filter.rawValue
        ConsoleSounds.shared.play(.select)
        NSLog("[filter] %@", filter.rawValue)
        model.say(String(localized: "画面滤镜：\(filter.title)"))
    }
    private func register() {
        guard model.page == .filter else { return }
        let ids = ScreenFilter.allCases.map { "filter.\($0.rawValue)" }
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for filter in ScreenFilter.allCases { handlers["filter.\(filter.rawValue)"] = { choose(filter) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "filter.\(filterID)")
    }
}

/// The upper screen of 画面滤镜: the focused (or chosen) filter on a small
/// picture of FoldArc's own, big pixels, so the lines show.
struct FilterTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(ScreenFilter.defaultsKey) private var filterID = ScreenFilter.sharp.rawValue
    var body: some View {
        let chosen = ScreenFilter(rawValue: filterID) ?? .sharp
        let focused = model.focus.flatMap { focus in ScreenFilter.allCases.first { "filter.\($0.rawValue)" == focus } }
        let filter = focused ?? chosen
        HStack(spacing: 14 * s) {
            Group {
                if let image = FilterSample.image {
                    Image(decorative: image, scale: 1).resizable()
                        .interpolation(filter.smooths ? .medium : .none)
                        .saturation(filter == .crt ? 1.12 : 1)
                        .overlay { ScreenFilterOverlay(filter: filter, native: FilterSample.pixels).equatable() }
                } else {
                    Color.black
                }
            }
            .frame(width: 176 * s, height: 105.6 * s)
            .clipShape(RoundedRectangle(cornerRadius: 3 * s))
            .overlay(RoundedRectangle(cornerRadius: 3 * s).strokeBorder(.black.opacity(0.55), lineWidth: 1.5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5 * s) {
                Text(filter.title).font(.system(size: 17 * s, weight: .bold, design: .rounded))
                Text(filter.summary).font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(filter == chosen ? "现在用的滤镜" : "按 A 换成这个")
                    .font(.system(size: 9.5 * s, weight: .bold)).foregroundStyle(filter == chosen ? SystemMenuStyle.go : SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
}

/// A small pixel picture of FoldArc's own for 画面滤镜's upper screen: a sky,
/// a sun, clouds, two hills, a tree (80 × 48 pixels).
enum FilterSample {
    static let pixels = CGSize(width: 80, height: 48)
    static let image: CGImage? = {
        let w = 80, h = 48
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.setShouldAntialias(false)
        // Drawn top down.
        c.translateBy(x: 0, y: Double(h)); c.scaleBy(x: 1, y: -1)
        func fill(_ r: Double, _ g: Double, _ b: Double, _ rect: CGRect) {
            c.setFillColor(red: r, green: g, blue: b, alpha: 1); c.fill(rect)
        }
        let sky: [(Double, Double, Double)] = [(0.27, 0.52, 0.92), (0.36, 0.62, 0.95), (0.47, 0.71, 0.97), (0.60, 0.80, 0.99), (0.74, 0.88, 1.0)]
        for (i, color) in sky.enumerated() { fill(color.0, color.1, color.2, CGRect(x: 0, y: i * 6, width: w, height: 6)) }
        // The sun, a stepped disc.
        for (dy, half) in [(0, 2), (1, 4), (2, 5), (3, 5), (4, 5), (5, 4), (6, 2)] {
            fill(1.0, 0.84, 0.32, CGRect(x: 60 - half, y: 4 + dy, width: half * 2, height: 1))
        }
        // Clouds.
        for (x, y, width) in [(10, 8, 12), (13, 6, 6), (32, 13, 10), (34, 11, 5)] {
            fill(0.97, 0.98, 1.0, CGRect(x: x, y: y, width: width, height: 2))
        }
        // The far hill, then the near one, stepped.
        for x in 0..<w {
            let far = 28 - Int(7 * sin(Double(x) / 13 + 0.6))
            fill(0.36, 0.64, 0.45, CGRect(x: x, y: far, width: 1, height: h - far))
        }
        for x in 0..<w {
            let near = 35 - Int(5 * sin(Double(x) / 9 + 2.2))
            fill(0.20, 0.50, 0.30, CGRect(x: x, y: near, width: 1, height: h - near))
        }
        // The ground and its grass edge.
        fill(0.56, 0.40, 0.25, CGRect(x: 0, y: 42, width: w, height: 6))
        fill(0.30, 0.66, 0.30, CGRect(x: 0, y: 41, width: w, height: 1))
        // A tree.
        fill(0.40, 0.25, 0.14, CGRect(x: 22, y: 33, width: 2, height: 8))
        fill(0.14, 0.42, 0.22, CGRect(x: 18, y: 26, width: 10, height: 8))
        fill(0.18, 0.52, 0.27, CGRect(x: 20, y: 24, width: 6, height: 3))
        return c.makeImage()
    }()
}

/// 手柄: the controller connected; 接上手柄自动换模式; which of its buttons is
/// which 3DS key — two layouts, or a key's button chosen by pressing it
/// (the D-pad, the sticks and Home stay as they are).
/// 其他设置 › 开发者 (debug builds; round 31): the orientation
/// diagnostics' switches, which were HOME's 开发者 small icon.
private struct DeveloperPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("foldarc.debug.snapTransitions") private var snapTransitions = true
    @AppStorage("foldarc.debug.traceOverlay") private var traceOverlay = false
    @AppStorage("foldarc.debug.captureFrames") private var captureFrames = false
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppRow(id: "dev.snap", title: String(localized: "外屏上抑制 UIKit 旋转动画"), s: s, model: model, action: { flip($snapTransitions) }) { AppSwitch(isOn: snapTransitions, s: s) }
            AppRow(id: "dev.trace", title: String(localized: "显示方向诊断叠层"), s: s, model: model, action: { flip($traceOverlay) }) { AppSwitch(isOn: traceOverlay, s: s) }
            AppRow(id: "dev.frames", title: String(localized: "记录过渡帧 PNG"), s: s, model: model, action: { flip($captureFrames) }) { AppSwitch(isOn: captureFrames, s: s) }
            #if DEBUG
            // Zero EMU Pro in a debug build: the pretend store (no money)
            // or the App Store, and what was "bought" in the pretend one.
            AppRow(id: "dev.store", title: String(localized: "内购用假商店（不扣款）"), s: s, model: model, action: { flipStore() }) { AppSwitch(isOn: pro.pretend, s: s) }
            AppRow(id: "dev.storeClear", title: String(localized: "清掉假商店里买过的"), s: s, model: model, action: { clearStore() }) {
                AppValue(text: pro.isPro ? String(localized: "典藏卡带") : String(localized: "没买"), s: s, opens: false)
            }
            #endif
            #if os(iOS)
            AppNote(text: String(localized: "日志：\(OrientationTrace.shared.locations.first?.path ?? String(localized: "无可写目录"))"), s: s)
            #endif
            AppNote(text: String(localized: "只有调试构建有这一页；正式版里没有。"), s: s)
        }
    }
    private func flip(_ value: Binding<Bool>) {
        value.wrappedValue.toggle()
        ConsoleSounds.shared.play(.click)
    }
    /// (The two rows of the pretend store are a debug build's.)
    private func flipStore() {
        #if DEBUG
        ConsoleSounds.shared.play(.click)
        pro.usePretendStore(!pro.pretend)
        model.say(pro.pretend ? String(localized: "内购：假商店，不扣款") : String(localized: "内购：App Store（沙盒）"))
        #endif
    }
    private func clearStore() {
        #if DEBUG
        ConsoleSounds.shared.play(.click)
        guard pro.pretend else { model.say(String(localized: "现在用的是 App Store：这里清不了")); return }
        pro.clearPretendPurchases()
        model.say(String(localized: "清掉了：现在是没买的样子"))
        #endif
    }
    private func register() {
        guard model.page == .developer else { return }
        #if DEBUG
        let store = [["dev.store"], ["dev.storeClear"]]
        #else
        let store: [[String]] = []
        #endif
        model.layout = [["dev.snap"], ["dev.trace"], ["dev.frames"]] + store + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "dev.snap": { flip($snapTransitions) },
                          "dev.trace": { flip($traceOverlay) }, "dev.frames": { flip($captureFrames) },
                          "dev.store": { flipStore() }, "dev.storeClear": { clearStore() }]
        model.adjusters = ["dev.snap": { delta in if snapTransitions != (delta > 0) { flip($snapTransitions) } },
                           "dev.trace": { delta in if traceOverlay != (delta > 0) { flip($traceOverlay) } },
                           "dev.frames": { delta in if captureFrames != (delta > 0) { flip($captureFrames) } }]
        model.registered(initial: "dev.snap")
    }
}

private struct GamepadPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var pads = GameControllerInput.shared
    @AppStorage(GamepadLayout.autoModeKey) private var autoMode = true
    @State private var listening: PadButton?
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            HStack(spacing: 8 * s) {
                Image(systemName: pads.padName == nil ? "gamecontroller" : "gamecontroller.fill").font(.system(size: 14 * s, weight: .semibold))
                    .foregroundStyle(pads.padName == nil ? SystemMenuStyle.inkSoft : SystemMenuStyle.go)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(pads.padName.map { "已连接：\($0)" } ?? "没有接手柄").font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                    Text(pads.padName == nil ? "蓝牙手柄在 iPhone 的 设置 › 蓝牙 里配对" : (pads.lastPress.map { "刚按的：\($0)" } ?? "按一下手柄上的键试试"))
                        .font(.system(size: AppMetrics.text(8.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pad-status")
            AppRow(id: "pad.auto", title: String(localized: "接上手柄自动换模式"), s: s, model: model, action: { toggleAuto() }) { AppSwitch(isOn: autoMode, s: s) }
            AppRow(id: "pad.preset", title: String(localized: "按键布局"), s: s, interactive: true, model: model, action: nil) {
                AppStepper(text: pads.layout.presetName, s: s, choices: true) { stepPreset($0) }
            }
            ForEach(GamepadLayout.keys, id: \.self) { key in
                let source = pads.layout.source(for: key)
                AppRow(id: "pad.key.\(key.rawValue)", title: String(localized: "3DS 的 \(key.rawValue.uppercased())"), s: s, selected: listening == key, model: model,
                       action: { listen(key) }) {
                    AppValue(text: listening == key ? String(localized: "按一下手柄上的键…") : (source?.title ?? "—"), s: s, opens: false)
                }
                .accessibilityValue(listening == key ? String(localized: "等手柄") : (source?.title ?? ""))
            }
            AppRow(id: "pad.reset", title: String(localized: "恢复默认"), s: s, model: model, action: { reset() }) { AppValue(text: String(localized: "按位置"), s: s, opens: false) }
            AppNote(text: String(localized: "改一个键：选中它按 A（或点它），再按一下手柄上想用的键；那个键原来管的 3DS 键会换成这个键原来的。十字键、两个摇杆和 Home 键不变。"), s: s)
        }
        .onAppear { pads.reportsPresses = true }
        .onDisappear { pads.reportsPresses = false; pads.cancelCapture() }
    }
    private func toggleAuto() {
        autoMode.toggle()
        ConsoleSounds.shared.play(.click)
    }
    private func stepPreset(_ delta: Int) {
        let presets = [GamepadLayout.byPosition, GamepadLayout.byLetter]
        let index = presets.firstIndex(of: pads.layout) ?? (delta > 0 ? -1 : presets.count)
        let next = presets[(index + delta + presets.count) % presets.count]
        pads.setLayout(next)
        ConsoleSounds.shared.play(.move)
    }
    private func listen(_ key: PadButton) {
        guard pads.padName != nil else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
            model.say(String(localized: "先接上手柄"))
            return
        }
        listening = key
        ConsoleSounds.shared.play(.select)
        pads.captureNext { source in
            var layout = pads.layout
            layout.assign(source, to: key)
            pads.setLayout(layout)
            listening = nil
            ConsoleSounds.shared.play(.click)
            model.say(String(localized: "3DS 的 \(key.rawValue.uppercased())：\(source.title)"))
        }
    }
    private func reset() {
        pads.cancelCapture()
        listening = nil
        pads.setLayout(.byPosition)
        ConsoleSounds.shared.play(.click)
        model.say(String(localized: "按键布局：按位置"))
    }
    private func register() {
        guard model.page == .gamepad else { return }
        model.layout = [["pad.auto"], ["pad.preset"]] + GamepadLayout.keys.map { ["pad.key.\($0.rawValue)"] } + [["pad.reset"], [ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { pads.cancelCapture(); model.pop() }, "pad.auto": { toggleAuto() }, "pad.reset": { reset() }]
        for key in GamepadLayout.keys { handlers["pad.key.\(key.rawValue)"] = { listen(key) } }
        model.handlers = handlers
        model.adjusters = ["pad.auto": { delta in if autoMode != (delta > 0) { toggleAuto() } }, "pad.preset": { stepPreset($0) }]
        model.registered(initial: "pad.auto")
    }
}

/// 数据管理 › 存档同步 (round 31): on or off, where to (a folder picked in
/// Files, or the app's own iCloud container when it has one), now, and how
/// the last one went.
private struct SyncPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var sync = SaveSyncModel.shared
    /// 存档同步 is Pro's: without it the page says so, and every row opens
    /// Pro's page (what was set up before stays as it was, for when Pro is
    /// back).
    @ObservedObject private var pro = ProStore.shared
    @State private var picking = false
    var body: some View {
        let open = pro.isPro
        register(open: open)
        return AppScroll(model: model, s: s) {
            HStack(spacing: 8 * s) {
                Image(systemName: !open ? "lock.fill" : (sync.enabled ? "icloud.and.arrow.up" : "icloud.slash")).font(.system(size: 14 * s, weight: .semibold))
                    .foregroundStyle(open && sync.enabled ? SystemMenuStyle.go : SystemMenuStyle.inkSoft)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(!open ? String(localized: "典藏卡带的功能") : (sync.enabled ? (sync.running ? String(localized: "正在同步…") : String(localized: "开着")) : String(localized: "没开")))
                        .font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                    Text(statusLine).font(.system(size: AppMetrics.text(8.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync-status")
            if let progress = sync.progress, progress.total > 0 {
                // 11-05: how far the run is.
                ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                    .tint(SystemMenuStyle.go)
                    .padding(.horizontal, 8 * s)
                    .accessibilityIdentifier("sync-progress")
            }
            if !open {
                AppBigButton(id: "sync.pro", title: String(localized: "典藏卡带"), symbol: "star.circle.fill", note: String(localized: "存档同步要典藏卡带：看看有什么、多少钱"), noteLines: 3, s: s, model: model) { model.push(.pro) }
            }
            AppRow(id: "sync.enabled", title: String(localized: "存档同步"), s: s, model: model, action: { toggle() }) { AppSwitch(isOn: sync.active, s: s) }
            // One sync, two places — the app's own iCloud
            // space (11-07: the paid account has the capability; the
            // entitlement is in Sources/FoldArc.entitlements) or a folder
            // picked in Files.
            AppRow(id: "sync.place.icloud", title: String(localized: "存到 App 自己的 iCloud 空间"), s: s, selected: sync.place == .iCloud, model: model, action: { useICloud() }) {
                if sync.place == .iCloud {
                    Image(systemName: "checkmark").font(.system(size: 10 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.accent)
                } else {
                    AppValue(text: sync.iCloudAvailable ? "" : String(localized: "还不能用"), s: s, opens: false)
                }
            }
            AppRow(id: "sync.place.folder", title: String(localized: "存到「文件」里的文件夹"), s: s, selected: sync.place == .folder, model: model, action: { useFolder() }) {
                HStack(spacing: 4 * s) {
                    if sync.place == .folder { Image(systemName: "checkmark").font(.system(size: 10 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.accent) }
                    AppValue(text: sync.folderName ?? String(localized: "选一个"), s: s)
                }
            }
            AppRow(id: "sync.now", title: String(localized: "现在同步"), s: s, model: model, action: { now() }) {
                AppValue(text: sync.running ? String(localized: "同步中") : "", s: s, opens: false)
            }
            AppRow(id: "sync.repair", title: String(localized: "修复同步"), s: s, model: model, action: { repair() }) {
                AppValue(text: "", s: s, opens: false)
            }
            VStack(alignment: .leading, spacing: 1 * s) {
                AppInfoLine(title: String(localized: "占用"), value: sync.lastReport.map { ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file) } ?? String(localized: "同步一次以后显示"), s: s)
                if let report = sync.lastReport, !report.waitingFiles.isEmpty {
                    AppInfoLine(title: String(localized: "在等 iCloud 下载"), value: report.waitingFiles.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: String(localized: "、")) + (report.waitingFiles.count > 3 ? String(localized: " 等") : ""), s: s)
                }
                if let report = sync.lastReport, !report.errors.isEmpty {
                    AppInfoLine(title: String(localized: "没成功的"), value: report.errors.prefix(2).joined(separator: String(localized: "；")), s: s)
                }
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync-details")
            AppNote(text: String(localized: "同步的：游戏自己的存档（模拟 SD 卡里的存档和附加数据）和 HOME 里「保存进度」存的即时存档。不同步：游戏本体、装进模拟 SD 卡的软件、离开时自动存的继续进度、照片。两边都改过时留新的那份，另一份放进「文件」› Zero EMU › Conflicts。在这里删掉的即时存档，别的设备上同一份也会删掉（放进 Conflicts › Deleted by Sync）；别的存档删了不会跟着删。游戏开着时不同步。某个游戏不想同步：数据管理 › 软件 › 那个游戏。"), s: s)
            if !sync.iCloudAvailable {
                AppNote(text: String(localized: "App 自己的 iCloud 空间现在用不了：这台 iPhone 要登录 iCloud，并在 设置 › Apple 账户 › iCloud 里允许 Zero EMU 使用 iCloud 云盘。也可以先选 iCloud 云盘里的一个文件夹，一样能同步。"), s: s)
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { sync.setFolder(url) }
        }
        .onAppear { sync.checkICloud() }
    }
    private var statusLine: String {
        guard pro.isPro else {
            return sync.enabled ? String(localized: "典藏卡带没有开着，同步停了。存档都还在这台设备上，同步过的也还在原来的地方。")
                : String(localized: "存档同步要典藏卡带。备份（导出成 zip）不用。")
        }
        if sync.running, let progress = sync.progress, progress.total > 0 {
            return String(localized: "正在同步 \(min(progress.done + 1, progress.total))/\(progress.total)") + (progress.current.isEmpty ? "" : " · \((progress.current as NSString).lastPathComponent)")
        }
        if let problem = sync.problem { return problem }
        let place = sync.place == .iCloud ? String(localized: "App 的 iCloud 空间") : (sync.folderName.map { String(localized: "「\($0)」文件夹") } ?? String(localized: "还没选文件夹"))
        guard let last = sync.lastSync else { return String(localized: "同步到：\(place)") }
        let time = last.formatted(.dateTime.locale(UILanguage.locale).month().day().hour().minute(.twoDigits))
        return String(localized: "同步到：\(place) · 上次 \(time)") + (sync.lastReport.map { String(localized: "：\($0.repaired ? String(localized: "修复，") : "")\($0.summary)") } ?? "")
    }
    /// Without Pro a row opens Pro's page instead of doing what it does.
    private func needsPro() -> Bool {
        guard !ProAccess.isPro else { return false }
        model.push(.pro)
        return true
    }
    private func toggle() {
        guard !needsPro() else { return }
        ConsoleSounds.shared.play(.click)
        if !sync.enabled, sync.place == .folder, sync.folderName == nil { picking = true; return }
        sync.setEnabled(!sync.enabled)
    }
    private func useICloud() {
        guard !needsPro() else { return }
        guard sync.iCloudAvailable else {
            ConsoleSounds.shared.play(.back)
            model.say(String(localized: "还不能用：这台 iPhone 要登录 iCloud，并在 设置 › Apple 账户 › iCloud 里允许 Zero EMU 使用 iCloud 云盘"))
            return
        }
        ConsoleSounds.shared.play(.click)
        sync.use(.iCloud)
    }
    private func useFolder() {
        guard !needsPro() else { return }
        ConsoleSounds.shared.play(.click)
        if sync.place == .folder || sync.folderName == nil { picking = true; return }
        sync.use(.folder)
    }
    private func now() {
        guard !needsPro() else { return }
        guard sync.enabled else { model.say(String(localized: "先打开存档同步")); return }
        ConsoleSounds.shared.play(.select)
        sync.syncNow("asked")
    }
    private func repair() {
        guard !needsPro() else { return }
        guard sync.enabled else { model.say(String(localized: "先打开存档同步")); return }
        guard !sync.running else { model.say(String(localized: "正在同步，等它做完")); return }
        ConsoleSounds.shared.play(.select)
        model.say(String(localized: "修复同步：两边每个文件按内容重新比一遍"))
        sync.repair()
    }
    private func register(open: Bool) {
        guard model.page == .dataSync else { return }
        model.layout = (open ? [] : [["sync.pro"]]) + [["sync.enabled"], ["sync.place.icloud"], ["sync.place.folder"], ["sync.now"], ["sync.repair"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "sync.pro": { model.push(.pro) }, "sync.enabled": { toggle() }, "sync.place.icloud": { useICloud() },
                          "sync.place.folder": { useFolder() }, "sync.now": { now() }, "sync.repair": { repair() }]
        model.adjusters = ["sync.enabled": { delta in if sync.active != (delta > 0) { toggle() } }]
        model.registered(initial: open ? "sync.enabled" : "sync.pro")
    }
}

// MARK: 存档位

/// 存档位: the running game's numbered places for 即时存档. 保存进度 and
/// 读取进度 use the one chosen here; the first five are everybody's to save
/// into, further ones Pro's (what is already in one can still be read).
private struct StateSlotPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var pro = ProStore.shared
    @ViewState private var revision = 0
    var body: some View {
        let game = ctx.session.core?.stateGame
        let _ = revision
        register(game)
        return AppScroll(model: model, s: s) {
            if let game {
                let slot = SaveStates.currentSlot(for: game)
                let url = SaveStates.manual(for: game, slot: slot)
                let filled = FileManager.default.fileExists(atPath: url.path)
                let open = StateSlots.canSave(slot: slot, pro: pro.isPro)
                AppRow(id: "states.slot", title: String(localized: "存档位"), s: s, interactive: true, model: model, action: nil) {
                    AppStepper(text: "\(slot)", s: s) { step($0, game) }
                }
                HStack(spacing: 6 * s) {
                    Image(systemName: !open ? "lock.fill" : (filled ? "clock.arrow.circlepath" : "circle.dashed")).font(.system(size: 11 * s, weight: .semibold))
                        .foregroundStyle(filled && open ? SystemMenuStyle.go : SystemMenuStyle.inkSoft)
                    Text(line(slot: slot, url: url, filled: filled, open: open)).font(.system(size: AppMetrics.text(9, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8 * s).padding(.vertical, 2 * s)
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(slot)")
                .accessibilityIdentifier("state-slot-status")
                let used = SaveStates.usedSlots(for: game).sorted()
                let usedList = used.map { "\($0)" }.joined(separator: String(localized: "、"))
                AppNote(text: used.isEmpty ? String(localized: "这个游戏还没有即时存档。") : String(localized: "有进度的存档位：\(usedList)"), s: s)
                    .accessibilityIdentifier("state-slot-used")
                AppNote(text: pro.isPro ? String(localized: "存档位不限个数（典藏卡带）。删除某一个里的进度：系统设置 › 数据管理 › 即时存档。")
                        : String(localized: "前 \(ProAccess.freeStateSlots) 个存档位都能用；更多的要典藏卡带（往后再按一下就是典藏卡带的那一页）。删除某一个里的进度：系统设置 › 数据管理 › 即时存档。"), s: s)
            } else {
                AppNote(text: String(localized: "存档位是游戏里用的：现在没有正在运行的游戏。"), s: s)
            }
        }
    }
    private func line(slot: Int, url: URL, filled: Bool, open: Bool) -> String {
        if !filled { return open ? String(localized: "这一个还是空的：「保存进度」会存到这里。") : String(localized: "这一个是典藏卡带的。") }
        let when = SaveStates.readInfo(for: url)?.saved.formatted(.dateTime.locale(UILanguage.locale).month().day().hour().minute(.twoDigits)) ?? "—"
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return open ? String(localized: "存于 \(when) · \(size)") : String(localized: "存于 \(when) · \(size)。能读，再存要典藏卡带。")
    }
    private func step(_ delta: Int, _ game: URL) {
        let slot = SaveStates.currentSlot(for: game)
        switch StateSlots.step(from: slot, by: delta, pro: ProAccess.isPro, used: SaveStates.usedSlots(for: game)) {
        case .to(let next):
            SaveStates.setCurrentSlot(next, for: game)
            ConsoleSounds.shared.play(.move)
            NSLog("[states] slot %d -> %d", slot, next)
            revision += 1
        case .end: ConsoleHaptics.shared.play(.sliderStop, .press)
        case .needsPro: model.push(.pro)
        }
    }
    private func register(_ game: URL?) {
        guard model.page == .stateSlot else { return }
        model.layout = (game == nil ? [] : [["states.slot"]]) + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        if let game { model.adjusters = ["states.slot": { delta in step(delta, game) }] } else { model.adjusters = [:] }
        model.registered(initial: game == nil ? nil : "states.slot")
    }
}

// MARK: Zero EMU Pro

/// Zero EMU Pro: whether it is open, the three prices as the store gives
/// them (月付 and 年付 renew, 永久 is bought once), 恢复购买, 管理订阅, the
/// terms and the privacy policy. A purchase is confirmed on the system's
/// own sheet; the page only says what the store answered.
private struct ProPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var pro = ProStore.shared
    /// 减弱动态效果: a purchase does not start the box's ceremony by itself.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the last purchase or 恢复购买 came to (kept by the model, so it
    /// is still there after the box and the films).
    private var message: String? {
        get { model.proNote }
        nonmutating set {
            model.proNote = newValue
            // (It stands at the page's top, maybe out of sight: VoiceOver says it.)
            #if os(iOS)
            if let newValue { UIAccessibility.post(notification: .announcement, argument: newValue) }
            #endif
        }
    }
    /// The cards the purchases owned bring: bronze, silver, gold.
    private var owned: [Cartridge] { Cartridge.owned(pro.holdings.plans) }
    var body: some View {
        let rows = self.rows
        let owned = self.owned
        // Something is for sale: the prices have come, and 永久 is not owned.
        let selling = rows.contains { $0.hasPrefix("pro.buy.") }
        register(rows)
        return AppScroll(model: model, s: s) {
            status
            if let message { AppNote(text: message, s: s).accessibilityIdentifier("pro-message") }
            switch pro.catalog {
            case .loading:
                AppNote(text: String(localized: "正在读取价格…"), s: s).accessibilityIdentifier("pro-loading")
            case .unavailable(let why):
                AppNote(text: String(localized: "现在读不到价格：\(why)"), s: s).accessibilityIdentifier("pro-unavailable")
                AppRow(id: "pro.reload", title: String(localized: "再试一次"), s: s, model: model, action: { reload() }) { AppValue(text: "", s: s, opens: false) }
            case .ready(let offers):
                ForEach(offers.filter { shows($0.plan) }) { offer in planRow(offer) }
                // What a subscription is, right under the prices (it was the
                // page's last note, a long way down).
                if selling { renewalNote }
            }
            AppRow(id: "pro.restore", title: String(localized: "恢复购买"), s: s, model: model, action: { restore() }) {
                AppValue(text: pro.restoring ? String(localized: "正在恢复…") : "", s: s, opens: false)
            }
            AppRow(id: "pro.manage", title: String(localized: "管理订阅"), s: s, model: model, action: { manage() }) { AppValue(text: "", s: s) }
            linkRow("pro.terms", String(localized: "使用条款"), AppLinks.terms)
            linkRow("pro.privacy", String(localized: "隐私政策"), AppLinks.privacy)
            // The cards' films from here too (the cards themselves are on the shelf).
            ForEach(owned, id: \.self) { cartridge in
                AppRow(id: "pro.reel.\(cartridge.rawValue)", title: String(localized: "放\(cartridge.title)：\(cartridge.subtitle)"), s: s, model: model, action: { playReel(cartridge) }) { AppValue(text: "", s: s) }
            }
            if !owned.isEmpty {
                AppNote(text: String(localized: "你的卡带就在卡带架上：把它放进掌机、按「开启」，放的是它自己的动画。每一盘都有自己的编号。"), s: s)
                    .accessibilityIdentifier("pro-gold-note")
            }
            if pro.holdings.plans.contains(.lifetime), pro.holdings.plans.count > 1 {
                AppNote(text: String(localized: "你有永久了，原来的订阅不会自己停：记得在「管理订阅」里取消，免得继续扣款。"), s: s)
                    .accessibilityIdentifier("pro-cancel-note")
            }
            AppNote(text: String(localized: "月付带铜卡带，年付带银卡带，永久带金卡带，三张各放各的动画。月付、年付的卡带跟着订阅：订阅停了，卡带收回去；再订，卡带回来。金卡带一直在。"), s: s)
                .accessibilityIdentifier("pro-cards-note")
            AppNote(text: String(localized: "典藏卡带多出来的（铜、银、金都一样）：全部 \(ShellFinish.allCases.count) 种机身配色（免费 \(ProAccess.freeFinishes) 种）、相机的全部 \(CameraBody.allCases.count) 种机型（免费 \(ProAccess.freeBodies) 种）、每个游戏不限个数的存档位（免费 \(ProAccess.freeStateSlots) 个）、存档同步、TV模式（游戏画面上电视，iPhone 当手柄）、倍速。游戏、存档、备份和别的功能不用典藏卡带。"), s: s)
            // (with no price on the page it stays where it was)
            if !selling { renewalNote }
            #if DEBUG
            // `--foldarc-pro-as-shipped`: the page as a release build shows it.
            if pro.pretend, !ProcessInfo.processInfo.arguments.contains("--foldarc-pro-as-shipped") {
                AppNote(text: String(localized: "调试构建的假商店：点了不扣款，也不连 App Store。在「其他设置 › 开发者」里可以清掉买过的，或换成 App Store。"), s: s)
                    .accessibilityIdentifier("pro-pretend-note")
            }
            #endif
        }
        .task {
            // What is owned is asked again as the page opens (not as a part
            // of this task: leaving the page must not cut the asking short).
            Task { @MainActor in await pro.refresh() }
            await pro.loadOffers()
            // The prices have come: the cursor onto the first of them, if it
            // was only where the page had put it.
            if model.page == .pro, model.focus == nil || model.focus == "pro.restore", let first = self.rows.first { model.focus = first }
        }
    }
    /// That 月付 and 年付 renew by themselves, when they are charged and how
    /// to cancel; that 永久 is paid once.
    private var renewalNote: some View {
        AppNote(text: String(localized: "月付和年付是自动续期的订阅：确认购买时从 Apple 账户扣款，每一期结束前 24 小时内自动续下一期并扣款，除非在那之前取消。取消或换方案：点「管理订阅」，或到 iPhone 的 设置 › Apple 账户 › 订阅。永久是一次买断，不续期。"), s: s)
            .accessibilityIdentifier("pro-renewal-note")
    }
    /// Whether it is open, and as what.
    private var status: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: pro.isPro ? "star.circle.fill" : "star.circle").font(.system(size: 14 * s, weight: .semibold))
                .foregroundStyle(pro.isPro ? SystemMenuStyle.go : SystemMenuStyle.inkSoft)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(pro.isPro ? String(localized: "典藏卡带已开通") : String(localized: "还没有开通典藏卡带")).font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                Text(statusLine).font(.system(size: AppMetrics.text(8.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pro-status")
    }
    private var statusLine: String {
        guard pro.isPro else { return String(localized: "免费的部分一直能用。典藏卡带多出来的写在上屏。") }
        guard let plan = ProAccess.plan(owning: pro.holdings.plans) else { return "" }
        if plan == .lifetime { return String(localized: "永久 · 金卡带：一次买断，不续期。") }
        let name = Self.rowTitle(plan)
        guard let end = pro.holdings.expires else { return name }
        // Still open past its day: the App Store is trying the payment again.
        if end < Date() { return String(localized: "\(name) · 这一期的付款还没完成：到「管理订阅」里看看付款方式") }
        return String(localized: "\(name) · 续期或到期：\(end.formatted(.dateTime.locale(UILanguage.locale).year().month().day()))")
    }
    static func title(_ plan: ProPlan) -> String {
        switch plan {
        case .monthly: return String(localized: "月付")
        case .yearly: return String(localized: "年付")
        case .lifetime: return String(localized: "永久")
        }
    }
    /// The plan with the card it brings: "年付 · 银卡带".
    static func rowTitle(_ plan: ProPlan) -> String { "\(title(plan)) · \(Cartridge(plan: plan).title)" }
    /// The price as the store words it, with what it is for.
    static func price(_ offer: ProOffer) -> String {
        switch offer.plan {
        case .monthly: return String(localized: "\(offer.price)/月")
        case .yearly: return String(localized: "\(offer.price)/年")
        case .lifetime: return offer.price
        }
    }
    private func terms(_ plan: ProPlan) -> String {
        switch plan {
        case .monthly: return String(localized: "每月自动续期，可随时取消")
        case .yearly: return String(localized: "每年自动续期，可随时取消")
        case .lifetime:
            guard let end = pro.offerEnd else { return String(localized: "一次付清，不续期") }
            return String(localized: "一次付清，不续期 · 首发价到 \(end.formatted(.dateTime.locale(UILanguage.locale).month().day()))")
        }
    }
    /// With 永久 there is nothing left to buy; with a subscription the
    /// other two can still be changed to.
    private func shows(_ plan: ProPlan) -> Bool { !pro.holdings.plans.contains(.lifetime) }
    private func planRow(_ offer: ProOffer) -> some View {
        let plan = offer.plan
        let owned = pro.holdings.plans.contains(plan)
        return AppRow(id: "pro.buy.\(plan.rawValue)", title: Self.rowTitle(plan), s: s, selected: owned, model: model, action: { buy(plan) }) {
            VStack(alignment: .trailing, spacing: 1 * s) {
                // What is charged, largest: a point over the line under it at
                // the least, and whole (not wrapped, not cut).
                Text(Self.price(offer)).font(.system(size: max(AppMetrics.caption + 1, 12 * s), weight: .heavy, design: .rounded)).foregroundStyle(SystemMenuStyle.ink)
                    .fixedSize()
                // What it is, with its price: how often it renews and that it
                // can be cancelled, or that it is paid once. Never under a
                // caption's size and not shrunk: on as many lines as it takes.
                Text(pro.buying == plan ? String(localized: "正在购买…") : (owned ? String(localized: "现在的方案") : terms(plan)))
                    .font(.system(size: AppMetrics.text(8, s), weight: .medium)).foregroundStyle(owned ? SystemMenuStyle.go : SystemMenuStyle.inkSoft)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func linkRow(_ id: String, _ title: String, _ url: URL?) -> some View {
        AppRow(id: id, title: title, s: s, model: model, action: { open(url) }) { AppValue(text: url?.host ?? "", s: s) }
    }
    private func open(_ url: URL?) {
        ConsoleSounds.shared.play(.select)
        guard let url else { return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
    private func buy(_ plan: ProPlan) {
        guard !pro.busy else { return }
        guard !pro.holdings.plans.contains(plan) else { model.say(String(localized: "这就是现在的方案")); return }
        ConsoleSounds.shared.play(.select)
        message = nil
        Task { @MainActor in
            switch await pro.buy(plan) {
            case .bought:
                ConsoleSounds.shared.play(.launch)
                // The card is said to have come only when it has (a change to a
                // cheaper plan waits for the period's end).
                message = pro.holdings.plans.contains(plan)
                    ? String(localized: "\(Cartridge(plan: plan).title)到了，谢谢支持。它就在卡带架上。") : String(localized: "买好了，谢谢支持。")
                // The card's box, opened (开箱仪式), then its films. With
                // 减弱动态效果 on neither starts by itself: the page says the
                // card has come (as it does where the ceremony is off), and
                // its films are a row away on this page, played when asked.
                if pro.holdings.plans.contains(plan), UnboxRun.enabled, !reduceMotion, model.page == .pro {
                    UnboxRun.shared.start(Cartridge(plan: plan))
                    model.push(.unbox)
                }
            case .cancelled: break
            case .pending: message = String(localized: "这笔购买在等批准或等付款完成；好了以后会自动开通。")
            case .failed(let why): message = String(localized: "没有买成：\(why)")
            }
        }
    }
    private func restore() {
        guard !pro.busy else { return }
        ConsoleSounds.shared.play(.select)
        message = nil
        Task { @MainActor in
            let was = pro.isPro
            if let problem = await pro.restore() {
                if !problem.isEmpty { message = String(localized: "恢复购买没有成功：\(problem)") }
                return
            }
            if !pro.isPro {
                message = String(localized: "这个 Apple 账户下没有找到典藏卡带的购买。")
            } else if was {
                message = String(localized: "购买都在：典藏卡带开着。")
            } else {
                ConsoleSounds.shared.play(.launch)
                message = String(localized: "找到了以前的购买：典藏卡带回来了。")
            }
        }
    }
    private func manage() {
        ConsoleSounds.shared.play(.select)
        Task { @MainActor in
            if let problem = await pro.manageSubscriptions() { message = problem }
        }
    }
    private func reload() {
        ConsoleSounds.shared.play(.select)
        Task { @MainActor in await pro.loadOffers() }
    }
    /// The rows the cursor walks, top to bottom.
    private var rows: [String] {
        var ids: [String] = []
        switch pro.catalog {
        case .ready(let offers): ids = offers.filter { shows($0.plan) }.map { "pro.buy.\($0.plan.rawValue)" }
        case .unavailable: ids = ["pro.reload"]
        case .loading: break
        }
        return ids + ["pro.restore", "pro.manage", "pro.terms", "pro.privacy"] + owned.map { "pro.reel.\($0.rawValue)" }
    }
    private func playReel(_ cartridge: Cartridge) {
        GoldReel.shared.rewind(cartridge)
        model.push(.reel)
    }
    private func register(_ rows: [String]) {
        guard model.page == .pro else { return }
        model.layout = rows.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }, "pro.reload": { reload() }, "pro.restore": { restore() },
                                              "pro.manage": { manage() }, "pro.terms": { open(AppLinks.terms) }, "pro.privacy": { open(AppLinks.privacy) }]
        for plan in ProPlan.allCases { handlers["pro.buy.\(plan.rawValue)"] = { buy(plan) } }
        for cartridge in Cartridge.allCases { handlers["pro.reel.\(cartridge.rawValue)"] = { playReel(cartridge) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: rows.first)
    }
}

/// A 典藏卡带's lower screen while its films play: which film it is; the
/// films as a strip of small pictures (a touch, or the cursor and A, plays
/// that one; L and R the one before and the next); the card's 卡带证; a
/// place to swipe a finger across for a gust over the picture.
private struct GoldReelPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    @ObservedObject private var pro = ProStore.shared
    /// The card playing is still owned (a subscription's card goes back when it ends).
    private var owned: Bool { pro.holdings.plans.contains(reel.cartridge.plan) }
    /// The strip's pictures in a row (银卡带's four seasons two by two).
    private var columns: Int { reel.cartridge == .silver ? 2 : 3 }
    var body: some View {
        let owned = self.owned
        register(owned)
        return AppScroll(model: model, s: s) {
            if owned {
                HStack(spacing: 8 * s) {
                    Image(systemName: "film.fill").font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
                    VStack(alignment: .leading, spacing: 1 * s) {
                        Text(verbatim: "\(reel.cartridge.title) · \(reel.title)").font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                        Text(reel.ended ? String(localized: "放完了：画面停在最后一段") : String(localized: "第 \(reel.index + 1) 段，共 \(reel.count) 段"))
                            .font(.system(size: AppMetrics.text(8.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(verbatim: "\(reel.cartridge.rawValue).\(reel.key)"))
                .accessibilityIdentifier("gold-reel-status")
                strip
                AppRow(id: "reel.next", title: String(localized: "下一段"), s: s, model: model, action: { step(1) }) { AppValue(text: "R", s: s, opens: false) }
                AppRow(id: "reel.previous", title: String(localized: "上一段"), s: s, model: model, action: { step(-1) }) { AppValue(text: "L", s: s, opens: false) }
                AppRow(id: "reel.pass", title: String(localized: "卡带证"), s: s, model: model, action: { model.push(.cartridgePass) }) {
                    AppValue(text: "No. \(reel.plan.code)", s: s)
                }
                ReelWindPad(model: model, s: s) { right in blow(right) }
                if reel.isFilm {
                    AppNote(text: String(localized: "这盘卡带的编号是 \(reel.plan.code)。"), s: s)
                        .accessibilityIdentifier("gold-reel-number")
                    AppNote(text: String(localized: "「一台掌机的回忆」一共九段，一口气放下去；放完了，画面停在掌机亮起来的那一刻，灰尘还在光里飘。点胶片条里的哪一格，就从那一段放起；L、R 换上一段、下一段。B 回到上一页。"), s: s)
                } else if reel.isSeasons {
                    AppNote(text: String(localized: "这盘卡带的编号是 \(reel.plan.code)。"), s: s)
                        .accessibilityIdentifier("gold-reel-number")
                    AppNote(text: String(localized: "春、夏、秋、冬，一季一段，每段一分钟。从春天放起，一季接一季；放完冬天，画面就停在那里。点胶片条里的哪一格，就从那一季放起；L、R 换上一季、下一季。起一阵风，画面上会刮过那一季的东西：春天的柳絮、夏天的萤火虫、秋天的落叶、冬天的雪。B 回到上一页。"), s: s)
                } else {
                    AppNote(text: String(localized: "这盘卡带的编号是 \(reel.plan.code)。每一盘放的顺序和画面里的小东西都不一样；你的这一盘，每次放都是这样。"), s: s)
                        .accessibilityIdentifier("gold-reel-number")
                    AppNote(text: String(localized: "一段接一段放下去，放完最后一段，画面就停在那里。点胶片条里的哪一格就放哪一段；L、R 换上一段、下一段。B 回到上一页。"), s: s)
                }
            } else {
                AppNote(text: String(localized: "这张卡带已经收回去了，现在放不了。"), s: s).accessibilityIdentifier("gold-reel-closed")
            }
        }
        // a breath on the microphone blows over the film too, heard against the film's own sound
        // (MicListener.breathing, not the camera's blowing): while this page is out, the card owned and its film
        // playing — not stood still with its screen gone (HOME over it, the app away), when the microphone is off
        .onAppear { MicListener.shared.want("reel", listens) }
        .onChange(of: listens) { _, now in
            MicListener.shared.want("reel", now)
            if !now { reel.breathing(false) }
        }
        .onDisappear { MicListener.shared.want("reel", false); reel.breathing(false) }
        .onReceive(MicListener.shared.$breathing) { reel.breathing($0 && listens) }
    }
    /// The microphone listens for a breath: the card owned and its film playing (a drawn film never stands still).
    private var listens: Bool { owned && (reel.pausedAt == nil || !reel.playsVideo) }
    /// The films in rows of three (银卡带's in rows of two): a small picture
    /// of each, its number (银卡带's: its season's name); the one playing
    /// ringed in the card's metal.
    private var strip: some View {
        let count = reel.count, columns = self.columns
        let rows = stride(from: 0, to: count, by: columns).map { Array($0..<min($0 + columns, count)) }
        return VStack(spacing: 5 * s) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 5 * s) {
                    ForEach(row, id: \.self) { index in cell(index) }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.aspectRatio(5.0 / 3.0, contentMode: .fit) }
                }
            }
        }
        .padding(.horizontal, 2 * s)
    }
    private func cell(_ index: Int) -> some View {
        let id = Self.filmID(index)
        let playing = index == reel.index
        let cartridge = reel.cartridge
        let game = reel.plan.games[index % reel.plan.games.count], season = reel.seasons[index % reel.seasons.count]
        let numbers = reel.plan.random(for: game)
        let name = cartridge == .gold ? GoldFilm.title(index) : (cartridge == .bronze ? game.title : season.title)
        let metal = Color(red: cartridge.tint.metal.0, green: cartridge.tint.metal.1, blue: cartridge.tint.metal.2)
        let shape = RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
        let badge = cartridge == .silver ? (playing ? String(localized: "\(season.title) 正在放") : season.title)
            : (playing ? String(localized: "\(index + 1) 正在放") : "\(index + 1)")
        return Button { model.focus = id; jump(index) } label: {
            ZStack(alignment: .bottomLeading) {
                if cartridge == .gold {
                    GoldFilmPicture(file: GoldFilm.picture(index))
                } else if cartridge == .silver {
                    GoldFilmPicture(file: season.picture)
                } else {
                    Canvas { context, size in
                        FlipBookPainter(game: game, random: numbers, t: 4).draw(context, size: size)
                    }
                    .background(Color.black)
                }
                Text(badge)
                    .font(.system(size: 7.5 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(playing ? Color(red: 0.17, green: 0.12, blue: 0.11) : .white)
                    .padding(.horizontal, 4 * s).padding(.vertical, 1 * s)
                    .background(Capsule().fill(playing ? metal : Color.black.opacity(0.6)))
                    .padding(3 * s)
            }
            .aspectRatio(5.0 / 3.0, contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.strokeBorder(playing ? metal : SystemMenuStyle.tileEdge.opacity(0.6), lineWidth: playing ? 2.2 * s : 1 * s))
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(index + 1) \(name)"))
        .accessibilityValue(playing ? Text("正在放") : Text(verbatim: ""))
        .accessibilityAddTraits(playing ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("app.\(id)")
        .id(id)
    }
    private static func filmID(_ index: Int) -> String { "reel.film.\(index)" }
    private func step(_ delta: Int) {
        ConsoleSounds.shared.play(.move)
        reel.step(delta)
    }
    private func jump(_ index: Int) {
        ConsoleSounds.shared.play(.select)
        reel.jump(index)
    }
    private func blow(_ right: Bool) {
        ConsoleHaptics.shared.play(.sliderStop, .press)
        reel.gust(right: right)
    }
    private func register(_ owned: Bool) {
        guard model.page == .reel else { return }
        let count = reel.count, columns = self.columns
        let films = stride(from: 0, to: count, by: columns).map { start in (start..<min(start + columns, count)).map(Self.filmID) }
        model.layout = (owned ? films + [["reel.next"], ["reel.previous"], ["reel.pass"], ["reel.wind"]] : []) + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }, "reel.next": { step(1) }, "reel.previous": { step(-1) },
                                              "reel.pass": { model.push(.cartridgePass) }, "reel.wind": { blow(true) }]
        for index in 0..<count { handlers[Self.filmID(index)] = { jump(index) } }
        // A while the opening shows: the opening goes, nothing else happens.
        if reel.opening != nil {
            for (id, action) in handlers where id != ConsoleAppModel.barLeft {
                handlers[id] = { if GoldReel.shared.opening != nil { GoldReel.shared.skipOpening() } else { action() } }
            }
        }
        model.handlers = handlers
        model.adjusters = ["reel.wind": { blow($0 > 0) }]
        if owned { model.pageTurner = { delta in step(delta) } } else { model.pageTurner = nil }
        model.registered(initial: owned ? "reel.next" : ConsoleAppModel.barLeft)
    }
}

/// Where a finger swipes for a gust over the picture (the way it swipes is
/// the way the wind blows); A, or left and right on it, do it too.
private struct ReelWindPad: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var blow: (Bool) -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
        HStack(spacing: 7 * s) {
            Image(systemName: "wind").font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text("手指在这里划一下，起一阵风").font(.system(size: AppMetrics.text(10, s), weight: .bold, design: .rounded))
                Text("往哪边划，风就往哪边吹；对着麦克风吹一口气也行").font(.system(size: AppMetrics.text(8, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * s).padding(.vertical, 9 * s)
        .frame(maxWidth: .infinity, minHeight: 44 * s)
        .background(shape.fill(SystemMenuStyle.tile.opacity(0.5)))
        .overlay(shape.strokeBorder(SystemMenuStyle.tileEdge, style: StrokeStyle(lineWidth: 1.4 * s, dash: [5 * s, 4 * s])))
        .overlay { if model.focus == "reel.wind" { MenuCursorRing(shape: shape, s: s) } }
        .contentShape(shape)
        .highPriorityGesture(DragGesture(minimumDistance: 14 * s).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
            model.focus = "reel.wind"
            blow(drag.translation.width > 0)
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { blow(true) }
        .accessibilityIdentifier("reel-wind")
        .id("reel.wind")
    }
}

/// 卡带证's upper screen: the card, and its certificate — what it is, its
/// number, the day it became the player's, 首发版's stamp for 金卡带 bought
/// at the launch price.
private struct CartridgePassTopCard: View {
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    var body: some View {
        let cartridge = reel.cartridge
        let since = CartridgeRecord.since(cartridge)
        let launch = CartridgeEdition.launch(cartridge, since: since)
        let ink = Color(red: 0.24, green: 0.17, blue: 0.16)
        HStack(spacing: 14 * s) {
            GameCardFace(card: GameCardInfo.card(for: cartridge), s: 1)
                .frame(width: 84 * s, height: 80 * s)
                .shadow(color: SystemMenuStyle.ink.opacity(0.3), radius: 2 * s, y: 2 * s)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(verbatim: "ZERO EMU").font(.system(size: 7.5 * s, weight: .semibold, design: .rounded)).tracking(2.5 * s).foregroundStyle(ink.opacity(0.7))
                Text(cartridge.title).font(.system(size: 17 * s, weight: .bold, design: .serif)).foregroundStyle(ink)
                Text(cartridge.subtitle).font(.system(size: 10 * s, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 2 * s)
                Text(verbatim: "No. \(reel.plan.code)").font(.system(size: 9.5 * s, weight: .semibold, design: .monospaced)).foregroundStyle(ink)
                Text(String(localized: "\(CartridgeRecord.sinceText(cartridge))入手")).font(.system(size: 9 * s, weight: .medium)).foregroundStyle(ink.opacity(0.85))
            }
            .padding(.horizontal, 13 * s).padding(.vertical, 11 * s)
            .frame(width: 150 * s, height: 112 * s, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 7 * s).fill(Color(red: 1.0, green: 0.99, blue: 0.96)))
            .overlay(RoundedRectangle(cornerRadius: 7 * s).strokeBorder(Color(red: 0.74, green: 0.66, blue: 0.53), lineWidth: 1.5 * s))
            .overlay(alignment: .topTrailing) {
                if launch {
                    Text("首发版")
                        .font(.system(size: 10 * s, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.66, green: 0.19, blue: 0.18))
                        .frame(width: 48 * s, height: 48 * s)
                        .overlay(Circle().strokeBorder(Color(red: 0.66, green: 0.19, blue: 0.18), lineWidth: 2.2 * s))
                        .rotationEffect(.degrees(-14))
                        .opacity(0.88)
                        .padding(.top, 8 * s).padding(.trailing, 8 * s)
                }
            }
        }
        .padding(.horizontal, 16 * s)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: "\(cartridge.rawValue) \(reel.plan.code)\(launch ? " launch" : "")"))
        .accessibilityIdentifier("cartridge-pass-top")
    }
}

/// 卡带证's lower screen: the number, the day, the edition, the purchase.
private struct CartridgePassPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var reel = GoldReel.shared
    var body: some View {
        register()
        let cartridge = reel.cartridge
        let launch = CartridgeEdition.launch(cartridge, since: CartridgeRecord.since(cartridge))
        return AppScroll(model: model, s: s) {
            row("pass.code", String(localized: "编号"), reel.plan.code)
            row("pass.since", String(localized: "入手"), CartridgeRecord.sinceText(cartridge))
            row("pass.edition", String(localized: "版次"), cartridge == .gold ? (launch ? String(localized: "首发版") : String(localized: "常规版")) : "—")
            row("pass.plan", String(localized: "方案"), ProPage.title(cartridge.plan))
            AppNote(text: String(localized: "2027 年 1 月 1 日（含）以前入手的金卡带，卡带证上有「首发版」的印。编号和日期只记在这台设备上，不会上传到任何地方。"), s: s)
        }
    }
    private func row(_ id: String, _ title: String, _ value: String) -> some View {
        AppRow(id: id, title: title, s: s, model: model, action: nil) { AppValue(text: value, s: s, opens: false) }
            .accessibilityValue(Text(verbatim: value))
    }
    private func register() {
        guard model.page == .cartridgePass else { return }
        model.layout = [["pass.code"], ["pass.since"], ["pass.edition"], ["pass.plan"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: "pass.code")
    }
}

/// Zero EMU Pro's upper screen: what it adds, and whether it is open.
private struct ProTopCard: View {
    var s: Double
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        HStack(alignment: .center, spacing: 14 * s) {
            // The three cards as they stand on the shelf: bronze, silver, gold
            // (with something owned, the ones not owned stand back).
            ZStack {
                ForEach(Array(Cartridge.allCases.enumerated()), id: \.element) { place, cartridge in
                    GameCardFace(card: GameCardInfo.card(for: cartridge), s: 1)
                        .frame(width: 66 * s, height: 63 * s)
                        .opacity(pro.isPro && !pro.holdings.plans.contains(cartridge.plan) ? 0.4 : 1)
                        .shadow(color: SystemMenuStyle.ink.opacity(0.28), radius: 2 * s, y: 2 * s)
                        .offset(x: Double(place - 1) * 30 * s, y: Double(1 - place) * 5 * s)
                }
            }
            .frame(width: 128 * s, height: 80 * s)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text("典藏卡带").font(.system(size: 17 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                ForEach(lines, id: \.symbol) { line in
                    HStack(spacing: 5 * s) {
                        Image(systemName: line.symbol).font(.system(size: 9 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.accent).frame(width: 13 * s)
                        Text(line.text).font(.system(size: 10 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Text(pro.isPro ? String(localized: "已开通") : String(localized: "还没有开通"))
                    .font(.system(size: 9.5 * s, weight: .bold)).foregroundStyle(pro.isPro ? SystemMenuStyle.go : SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20 * s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
    private var lines: [(symbol: String, text: String)] {
        [("paintpalette.fill", String(localized: "全部 \(ShellFinish.allCases.count) 种机身配色")),
         ("camera.fill", String(localized: "相机的全部 \(CameraBody.allCases.count) 种机型")),
         ("square.stack.3d.up.fill", String(localized: "即时存档的存档位不限个数")),
         ("icloud.fill", String(localized: "存档同步")),
         ("tv.fill", String(localized: "TV模式，倍速 2× 和 4×"))]
    }
}

// MARK: 备份 (11-07)

/// 数据管理 › 备份: 导出存档 (a zip to the share sheet) and 从备份恢复 (a
/// folder picked in Files; SaveBackup). Restoring waits while software runs
/// (it would write its saves over the restored ones).
private struct BackupPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @State private var picking = false
    @State private var working = false
    @State private var result: String?
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppRow(id: "backup.export", title: String(localized: "导出存档"), s: s, model: model, action: { export() }) {
                AppValue(text: working ? String(localized: "正在打包…") : "", s: s, opens: false)
            }
            AppRow(id: "backup.restore", title: String(localized: "从备份恢复"), s: s, model: model, action: { restore() }) {
                AppValue(text: "", s: s)
            }
            if let result {
                AppNote(text: result, s: s).accessibilityIdentifier("backup-result")
            }
            AppNote(text: String(localized: "导出存档：游戏自己的存档和「保存进度」存的即时存档打成一个 zip，用分享面板存进「文件」、发到电脑或 AirDrop 给另一台设备。换手机、重装之前留一份。"), s: s)
            AppNote(text: String(localized: "从备份恢复：先在「文件」里点一下 zip 解开，再在这里选解开的文件夹。这台设备上没有的存档放回来，一样的不动；不一样的用备份里的，这台设备原来那份先放进「文件」› Zero EMU › Conflicts。什么都不删。"), s: s)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { picked in
            if case .success(let urls) = picked, let url = urls.first { restore(from: url) }
        }
    }
    private func areas() -> [SaveSync.Area] { SaveSync.areas(console: Storage.consoleStorage(), states: SaveStates.folder) }
    private func export() {
        guard !working else { return }
        working = true
        result = nil
        let areas = areas()
        DispatchQueue.global(qos: .userInitiated).async {
            let made = Result { try SaveBackup.makeArchive(areas: areas) }
            DispatchQueue.main.async {
                working = false
                switch made {
                case .success(let zip):
                    #if os(iOS)
                    if !SharePresenter.share(zip) { result = String(localized: "没能打开分享面板") }
                    #else
                    result = zip.path
                    #endif
                case .failure(let error):
                    result = error.localizedDescription
                    model.say(error.localizedDescription)
                }
            }
        }
    }
    private func restore() {
        if let suspended = ctx.suspended {
            model.say(String(localized: "「\(suspended)」正在运行：先在主菜单里关闭它，再恢复存档。"))
            return
        }
        picking = true
    }
    private func restore(from url: URL) {
        guard !working else { return }
        working = true
        let areas = areas(), conflicts = SaveSyncModel.conflictsFolder()
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            let report = SaveBackup.restore(from: url, areas: areas, conflicts: conflicts)
            if scoped { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                working = false
                result = report.summary
                model.say(report.summary)
            }
        }
    }
    private func register() {
        guard model.page == .dataBackup else { return }
        model.layout = [["backup.export"], ["backup.restore"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "backup.export": { export() }, "backup.restore": { restore() }]
        model.adjusters = [:]
        model.registered(initial: "backup.export")
    }
}

// MARK: TV输出 (round 30; round 31: only the TV's connection)

/// Round 31: whether a TV is connected and
/// how to connect one; playing on it is TV模式, chosen in 游玩模式 (with the
/// screens' layout there).
private struct TVPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var tv = TVOutput.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            HStack(spacing: 8 * s) {
                Image(systemName: !tv.connected ? "tv.slash" : "tv.fill").font(.system(size: 14 * s, weight: .semibold))
                    .foregroundStyle(!tv.connected ? SystemMenuStyle.inkSoft : SystemMenuStyle.go)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(!tv.connected ? "没有接电视" : "已接上电视").font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                    Text(statusLine).font(.system(size: AppMetrics.text(8.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tv-status")
            AppInfoLine(title: "AirPlay", value: String(localized: "控制中心 ›「屏幕镜像」，选 Apple TV 或支持 AirPlay 的电视"), s: s)
            AppInfoLine(title: String(localized: "转接线"), value: String(localized: "Lightning 或 USB-C 转 HDMI，接电视的 HDMI 口"), s: s)
            AppInfoLine(title: String(localized: "在电视上玩"), value: String(localized: "主菜单 ›「游玩模式」› TV模式（在那里选电视；TV模式是典藏卡带的）"), s: s)
            AppNote(text: String(localized: "TV模式：电视上画一台你选的电视，游戏的上屏装在它的屏幕里（选「现代电视」就不画外壳，画面铺满电视）；iPhone 拿在手里当手柄，按键和下屏都在 iPhone 上。别的模式下接电视，电视上和 iPhone 一模一样（屏幕镜像）。"), s: s)
        }
    }
    private var statusLine: String {
        guard tv.connected else { return String(localized: "接上以后，这里会写电视的名字和分辨率") }
        return tv.statusText + (tv.tvMode ? String(localized: " · TV模式：电视上是游戏画面（\(tv.set.title)）") : String(localized: " · 屏幕镜像：电视上和 iPhone 一样"))
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .tv else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

// MARK: 游玩模式 (round 31)

/// 游玩模式 (round 31; it was a
/// small icon and a page of HOME's): the four ways to play, and what goes
/// with the one chosen — the guides and the pretend fold for 掌机模式, the
/// TV's layout for TV模式, 合上掌机 on an iPhone with no hinge. In a game
/// the mode changes at once under the program; in the library it is the
/// one the next game starts in.
private struct ModesPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @AppStorage(ScreenLayout.defaultsKey) private var storedMode = ScreenLayout.handheld.rawValue
    @ObservedObject private var tv = TVOutput.shared
    /// 11-07 沉浸模式 is for a connected controller.
    @ObservedObject private var pads = GameControllerInput.shared
    @ObservedObject private var pro = ProStore.shared
    /// The mode in use: the game's, else the kept one (read here, so that
    /// the page follows it) — TV模式 kept without 金卡带 is not the mode.
    private var mode: ScreenLayout {
        if let play = ctx.play { return play.mode }
        let kept = ScreenLayout(rawValue: storedMode) ?? .handheld
        return kept.isOpen ? kept : .handheld
    }
    private func available(_ item: ScreenLayout) -> Bool { item != .immersive || pads.padName != nil || item == mode }
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(ScreenLayout.allCases) { item in
                ModeRow(mode: item, selected: item == mode, available: available(item), locked: !item.isOpen, s: s, model: model) { choose(item) }
            }
            if mode == .handheld, let play = ctx.play {
                AppRow(id: "modes.guides", title: String(localized: "屏幕边缘参考线"), s: s, model: model, action: { toggleGuides() }) {
                    AppSwitch(isOn: play.showGuides.wrappedValue, s: s)
                }
                if let fraction = play.foldFraction, let gap = play.foldGap {
                    AppRow(id: "modes.fold", title: String(localized: "折叠位置"), s: s, interactive: true, model: model, action: nil) {
                        AppStepper(text: "\(Int((fraction.wrappedValue * 100).rounded()))%", s: s) { stepFold($0) }
                    }
                    AppRow(id: "modes.gap", title: String(localized: "折叠预留"), s: s, interactive: true, model: model, action: nil) {
                        AppStepper(text: "\(Int(gap.wrappedValue)) pt", s: s) { stepGap($0) }
                    }
                }
            }
            if mode == .tv {
                tvStatus
                // b41: the TV the TV
                // shows, chosen before one is connected too; an old one's
                // 画面, or 现代电视's layout.
                AppRow(id: "modes.tvSet", title: String(localized: "选电视"), s: s, model: model, action: { model.push(.tvSet) }) {
                    HStack(spacing: 6 * s) {
                        TVSetThumbnail(set: tv.set).frame(width: 34 * s, height: 24 * s)
                        AppValue(text: tv.set.title, s: s)
                    }
                }
                if tv.set == .modern {
                    AppRow(id: "modes.tvLayout", title: String(localized: "电视上的布局"), s: s, interactive: true, model: model, action: nil) {
                        AppStepper(text: tv.layout.title, s: s, choices: true) { stepLayout($0) }
                    }
                } else {
                    AppRow(id: "modes.tvLook", title: String(localized: "画面"), s: s, interactive: true, model: model, action: nil) {
                        AppStepper(text: tv.look.title, s: s, choices: true) { stepLook($0) }
                    }
                }
            }
            if lidRow {
                AppRow(id: "modes.lid", title: String(localized: "合上掌机（看外屏）"), s: s, model: model, action: { closeLid() }) {
                    AppValue(text: "", s: s)
                }
            }
            AppNote(text: ctx.play == nil ? String(localized: "在这里选的模式，下次开始游戏时用。游戏里按 HOME 也能换，马上生效。")
                                          : String(localized: "换了马上生效。下次开始游戏也用这个模式。"), s: s)
        }
    }
    private var lidRow: Bool { ctx.play?.closeLid != nil && (mode == .handheld || mode == .tabletop) }
    private var tvStatus: some View {
        HStack(spacing: 7 * s) {
            Image(systemName: !tv.connected ? "tv.slash" : "tv.fill").font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(!tv.connected ? SystemMenuStyle.inkSoft : SystemMenuStyle.go)
            Text(!tv.connected ? "还没接电视：控制中心 ›「屏幕镜像」选 Apple TV 或 AirPlay 电视" : "电视：\(tv.statusText)")
                .font(.system(size: AppMetrics.text(8.5, s), weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6 * s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modes-tv-status")
    }
    private func choose(_ item: ScreenLayout) {
        guard item != mode else { return }
        // TV模式 is Zero EMU Pro's: its row opens Pro's page.
        guard item.isOpen else {
            NSLog("[pro] TV模式 asked for without Pro")
            model.push(.pro)
            return
        }
        guard available(item) else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
            model.say(String(localized: "先接上外置手柄（蓝牙或 USB-C），才能用沉浸模式"))
            return
        }
        ConsoleSounds.shared.play(.select)
        ConsoleHaptics.shared.play(.smallButton, .press)
        NSLog("[modes] %@ chosen (%@)", item.rawValue, ctx.play == nil ? "for the next game" : "in the game")
        if let play = ctx.play {
            play.setMode(item)
        } else {
            storedMode = item.rawValue
            TVOutput.shared.setTVMode(item == .tv)
        }
        // b41: TV模式 chosen, the cursor goes on to 选电视 (the TV is chosen
        // before one is connected).
        if item == .tv { model.focus = "modes.tvSet" }
        model.say(String(localized: "换成了「\(item.title)」"))
    }
    private func toggleGuides() {
        guard let play = ctx.play else { return }
        play.showGuides.wrappedValue.toggle()
        ConsoleSounds.shared.play(.click)
    }
    private func stepFold(_ delta: Int) {
        guard let fraction = ctx.play?.foldFraction else { return }
        fraction.wrappedValue = min(0.65, max(0.35, fraction.wrappedValue + Double(delta) * 0.01))
        ConsoleSounds.shared.play(.move)
    }
    private func stepGap(_ delta: Int) {
        guard let gap = ctx.play?.foldGap else { return }
        gap.wrappedValue = min(56, max(0, gap.wrappedValue + Double(delta) * 2))
        ConsoleSounds.shared.play(.move)
    }
    private func stepLayout(_ delta: Int) {
        let all = TVLayout.allCases
        let index = all.firstIndex(of: tv.layout) ?? 0
        tv.layout = all[(index + delta + all.count) % all.count]
        ConsoleSounds.shared.play(.move)
    }
    private func stepLook(_ delta: Int) {
        let all = TVLook.allCases
        let index = all.firstIndex(of: tv.look) ?? 0
        tv.look = all[(index + delta + all.count) % all.count]
        ConsoleSounds.shared.play(.move)
    }
    private func closeLid() {
        guard let close = ctx.play?.closeLid else { return }
        ConsoleSounds.shared.play(.select)
        close()
    }
    private func register() {
        guard model.page == .modes else { return }
        var layout = ScreenLayout.allCases.map { ["mode.\($0.rawValue)"] }
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        var adjusters: [String: (Int) -> Void] = [:]
        for item in ScreenLayout.allCases { handlers["mode.\(item.rawValue)"] = { choose(item) } }
        if mode == .handheld, let play = ctx.play {
            layout.append(["modes.guides"])
            handlers["modes.guides"] = { toggleGuides() }
            adjusters["modes.guides"] = { delta in if play.showGuides.wrappedValue != (delta > 0) { toggleGuides() } }
            if play.foldFraction != nil, play.foldGap != nil {
                layout += [["modes.fold"], ["modes.gap"]]
                adjusters["modes.fold"] = { stepFold($0) }
                adjusters["modes.gap"] = { stepGap($0) }
            }
        }
        if mode == .tv {
            layout.append(["modes.tvSet"])
            handlers["modes.tvSet"] = { model.push(.tvSet) }
            if tv.set == .modern {
                layout.append(["modes.tvLayout"])
                adjusters["modes.tvLayout"] = { stepLayout($0) }
            } else {
                layout.append(["modes.tvLook"])
                adjusters["modes.tvLook"] = { stepLook($0) }
            }
        }
        if lidRow {
            layout.append(["modes.lid"])
            handlers["modes.lid"] = { closeLid() }
        }
        model.layout = layout + [[ConsoleAppModel.barLeft]]
        model.handlers = handlers
        model.adjusters = adjusters
        model.registered(initial: "mode.\(mode.rawValue)")
    }
}

/// One way to play: its mark, its name and what it is, ticked when chosen.
private struct ModeRow: View {
    var mode: ScreenLayout
    var selected: Bool
    /// 11-07: 沉浸模式 with no controller connected cannot be chosen (it
    /// says what it needs instead of what it is).
    var available = true
    /// Zero EMU Pro's (TV模式) and Pro not open: a small lock; the row opens Pro's page.
    var locked = false
    var s: Double
    @ObservedObject var model: ConsoleAppModel
    var action: () -> Void
    var body: some View {
        let id = "mode.\(mode.rawValue)"
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
        Button { model.focus = id; action() } label: {
            HStack(spacing: 8 * s) {
                Image(systemName: mode.symbol).font(.system(size: 12 * s, weight: .semibold))
                    .frame(width: 26 * s, height: 26 * s)
                    .foregroundStyle(selected ? .white : SystemMenuStyle.ink)
                    .background(selected ? SystemMenuStyle.accent : SystemMenuStyle.paperDeep, in: RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
                VStack(alignment: .leading, spacing: 1.5 * s) {
                    Text(mode.title).font(.system(size: AppMetrics.text(10.5, s), weight: .bold, design: .rounded))
                    // What the mode is, whole: at a caption's size it takes
                    // more than the two lines it was cut to (the page scrolls).
                    Text(available ? mode.summary : String(localized: "要先接上外置手柄（蓝牙或 USB-C）：接上以后，整块屏幕只放游戏的两块屏。"))
                        .font(.system(size: AppMetrics.text(8, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2 * s)
                if locked { ProLockBadge(size: 12 * s) }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12 * s))
                    .foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
            }
            .padding(.horizontal, 9 * s).padding(.vertical, 6 * s)
            .frame(maxWidth: .infinity, minHeight: AppMetrics.touch, alignment: .leading)
            .background(shape.fill(selected ? SystemMenuStyle.accent.opacity(0.12) : SystemMenuStyle.tile))
            .overlay(shape.strokeBorder(selected ? SystemMenuStyle.accent.opacity(0.5) : SystemMenuStyle.tileEdge.opacity(0.4), lineWidth: 1))
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
            .contentShape(shape)
            .opacity(available ? 1 : 0.55)
        }
        .buttonStyle(MenuPressStyle())
        .id(id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityHint(available ? mode.summary : String(localized: "要先接上外置手柄"))
        .accessibilityValue(available ? (locked ? String(localized: "典藏卡带") : "") : String(localized: "没接手柄"))
        .accessibilityIdentifier("app.\(id)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: 选电视 (b41)

/// 游玩模式 › 选电视: which
/// TV TV模式 draws on the TV — eight, four to a row, the one in use ticked —
/// and an old one's 画面. The upper screen shows the TV under the cursor
/// with the game in it as it will look. Opened from 游玩模式's TV模式, and from
/// TV模式's own button on the iPhone, before a TV is connected or while one
/// is (the TV changes at once).
private struct TVSetPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var tv = TVOutput.shared
    private static let rows: [[TVSet]] = [Array(TVSet.allCases.prefix(4)), Array(TVSet.allCases.dropFirst(4))]
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            Grid(horizontalSpacing: 4 * s, verticalSpacing: 4 * s) {
                ForEach(Self.rows, id: \.first) { row in
                    GridRow {
                        ForEach(row) { set in tile(set) }
                    }
                }
            }
            if tv.set == .modern {
                AppNote(text: String(localized: "现代电视不画外壳，总是最好的画面；两块屏怎么摆，在「游玩模式」›「电视上的布局」里选。"), s: s)
            } else {
                ForEach(TVLook.allCases) { look in
                    let selected = look == tv.look
                    AppRow(id: "tvlook.\(look.rawValue)", title: look.title, s: s, selected: selected, model: model, action: { choose(look) }) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12 * s))
                            .foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
                    }
                }
            }
            AppNote(text: String(localized: "电视上画的就是这台电视，正在玩的上屏在它的屏幕里；下屏和按键在 iPhone 上。换了马上生效，没接电视也能先选好。"), s: s)
        }
    }
    private func tile(_ set: TVSet) -> some View {
        let id = "tvset.\(set.rawValue)"
        let selected = set == tv.set
        let shape = RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
        return Button { model.focus = id; choose(set) } label: {
            VStack(spacing: 3 * s) {
                TVSetThumbnail(set: set).frame(height: 38 * s)
                Text(set.title).font(.system(size: 8 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(SystemMenuStyle.ink)
            }
            .padding(.horizontal, 4 * s).padding(.top, 6 * s).padding(.bottom, 4 * s)
            .frame(maxWidth: .infinity)
            .background(shape.fill(selected ? SystemMenuStyle.accent.opacity(0.12) : SystemMenuStyle.tile))
            .overlay(shape.strokeBorder(selected ? SystemMenuStyle.accent.opacity(0.6) : SystemMenuStyle.tileEdge.opacity(0.4), lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9 * s)).foregroundStyle(SystemMenuStyle.accent)
                        .background(Circle().fill(.white)).padding(2.5 * s)
                }
            }
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
            .contentShape(shape)
        }
        .buttonStyle(MenuPressStyle())
        .id(id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("电视：\(set.title)")
        .accessibilityValue(set.era)
        .accessibilityIdentifier("app.\(id)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func choose(_ set: TVSet) {
        guard set != tv.set else { return }
        tv.set = set
        ConsoleSounds.shared.play(.select)
        model.say(String(localized: "电视换成了「\(set.title)」"))
    }
    private func choose(_ look: TVLook) {
        guard look != tv.look else { return }
        tv.look = look
        ConsoleSounds.shared.play(.select)
        model.say(String(localized: "画面：\(look.title)"))
    }
    private func register() {
        guard model.page == .tvSet else { return }
        var layout = Self.rows.map { $0.map { "tvset.\($0.rawValue)" } }
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for set in TVSet.allCases { handlers["tvset.\(set.rawValue)"] = { choose(set) } }
        if tv.set != .modern {
            for look in TVLook.allCases {
                layout.append(["tvlook.\(look.rawValue)"])
                handlers["tvlook.\(look.rawValue)"] = { choose(look) }
            }
        }
        model.layout = layout + [[ConsoleAppModel.barLeft]]
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "tvset.\(tv.set.rawValue)")
    }
}

/// The upper screen of 选电视 (b41): the TV under the cursor (else the one in
/// use) big, with the game in it as it will look (the software's last
/// picture; the demo's, or in the library its first); its name, its years,
/// what it is or what the 画面 does, and whether it is the one in use.
struct TVSetTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var tv = TVOutput.shared
    var body: some View {
        let focusedSet = model.focus.flatMap { focus in TVSet.allCases.first { "tvset.\($0.rawValue)" == focus } }
        let focusedLook = model.focus.flatMap { focus in TVLook.allCases.first { "tvlook.\($0.rawValue)" == focus } }
        let set = focusedSet ?? tv.set
        let look = focusedLook ?? tv.look
        let inUse = focusedLook.map { $0 == tv.look } ?? (set == tv.set)
        HStack(spacing: 12 * s) {
            Group {
                if set == .modern {
                    ModernTVShape { ModernTVPreview(layout: tv.layout, session: ctx.session) }
                } else {
                    OldTVView(set: set, look: look, shadow: 0.02) { filter in
                        TVPreviewUpper(session: ctx.session, filter: filter, wholePixels: false)
                    }
                }
            }
            .frame(width: 204 * s, height: 164 * s)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(set.title).font(.system(size: 17 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(set == .modern ? set.era : "\(set.era) · \(look.title)").font(.system(size: 8.5 * s, weight: .semibold))
                    .foregroundStyle(SystemMenuStyle.inkSoft).fixedSize(horizontal: false, vertical: true)
                Text(focusedLook != nil && set != .modern ? look.summary(on: set) : set.summary)
                    .font(.system(size: 9 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(inUse ? (focusedLook != nil ? "现在用的画面" : "现在用的电视") : "按 A 换成这个")
                    .font(.system(size: 9.5 * s, weight: .bold)).foregroundStyle(inUse ? SystemMenuStyle.go : SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
}

/// A TV of 选电视, small (b41): its drawing with FoldArc's own little
/// picture in its screen; 现代电视 a thin black panel on a foot.
struct TVSetThumbnail: View {
    var set: TVSet
    var body: some View {
        if set == .modern {
            ModernTVShape { TVSampleUpper(filter: .sharp) }
        } else {
            OldTVView(set: set, look: .best) { filter in TVSampleUpper(filter: filter) }
        }
    }
}

/// 现代电视 as 选电视 draws it (b41): a thin black 16:9 panel on a small foot,
/// `screen` filling the panel.
struct ModernTVShape<Screen: View>: View {
    @ViewBuilder var screen: () -> Screen
    var body: some View {
        GeometryReader { proxy in
            // The panel 16:9, the foot under it: 0.6 of the width high in all.
            let w = min(proxy.size.width, proxy.size.height / 0.6)
            let bezel = w * 0.014
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    screen()
                }
                .frame(width: w - bezel * 2, height: w * 9 / 16 - bezel * 2)
                .clipShape(RoundedRectangle(cornerRadius: w * 0.006))
                .padding(bezel)
                .background(RoundedRectangle(cornerRadius: w * 0.016, style: .continuous).fill(Color(red: 0.04, green: 0.04, blue: 0.047)))
                Rectangle().fill(Color(red: 0.165, green: 0.17, blue: 0.19)).frame(width: w * 0.16, height: w * 0.025)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// FoldArc's own little picture (FilterSample) as an upper screen, drawn
/// with `filter`, 5:3 wherever it is put.
private struct TVSampleUpper: View {
    var filter: ScreenFilter
    var body: some View {
        Group {
            if let image = FilterSample.image {
                Image(decorative: image, scale: 1).resizable()
                    .interpolation(filter.smooths ? .medium : .none)
                    .saturation(filter == .crt ? 1.12 : 1)
                    .overlay { ScreenFilterOverlay(filter: filter, native: FilterSample.pixels).equatable() }
            } else {
                Color.black
            }
        }
        .aspectRatio(5 / 3, contentMode: .fit)
    }
}

/// The upper screen in 选电视's preview (b41): the software's last picture,
/// else the demo's.
private struct TVPreviewUpper: View {
    @ObservedObject var session: DemoSession
    var filter: ScreenFilter?
    var wholePixels: Bool?
    var body: some View {
        if let core = session.core, let image = core.top {
            CoreScreen(image: image, screenFilter: filter, wholePixels: wholePixels)
        } else {
            StarField(state: session.state, squareCorners: true, depth: 0).screenFilter(native: ScreenPixels.upper, filter: filter)
        }
    }
}

/// 现代电视 in 选电视's preview (b41): the screens where 电视上的布局 puts
/// them, with the 画面滤镜 of the settings (as on the TV).
private struct ModernTVPreview: View {
    var layout: TVLayout
    @ObservedObject var session: DemoSession
    var body: some View {
        GeometryReader { proxy in
            let frames = layout.frames(in: proxy.size)
            ZStack(alignment: .topLeading) {
                TVPreviewUpper(session: session, filter: nil, wholePixels: false)
                    .frame(width: frames.top.width, height: frames.top.height)
                    .position(x: frames.top.midX, y: frames.top.midY)
                if let bottom = frames.bottom {
                    lower.frame(width: bottom.width, height: bottom.height)
                        .position(x: bottom.midX, y: bottom.midY)
                }
            }
        }
    }
    @ViewBuilder private var lower: some View {
        if let core = session.core, let image = core.bottom {
            CoreScreen(image: image, wholePixels: false)
        } else {
            TouchMap(state: session.state, touch: nil, squareCorners: true, showCoordinates: false).screenFilter(native: ScreenPixels.lower)
        }
    }
}

// MARK: About, licences, EULA, update, format

@MainActor private enum BuildInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "\(short)（\(build)）")
    }
    static var core: String {
        AzaharSession.isCoreAvailable ? String(localized: "\(OpenSourceNotice.coreRelease)（libretro）") : String(localized: "这个构建没有附带")
    }
    static var edition: String {
        #if DEBUG
        return String(localized: "开发版")
        #else
        return String(localized: "正式版")
        #endif
    }
}

/// 关于 › 导出日志 (11-05): one text
/// file a tester can send — the build, the iPhone, the settings that change
/// how things run, this run's and the last unclean run's steps (LastRun),
/// and FoldArc's own log lines of this run ("[tag] …"). The owner's name,
/// birthday and country are taken out (the first-time setup's line is left
/// out whole), and the app's folder path is shortened to "~".
@MainActor private enum RunLogExport {
    static func make() async -> URL? {
        let settings = ConsoleSettings.shared
        let profile = settings.profile
        var text = String(localized: "Zero EMU 日志 · \(stamp(Date(), "yyyy-MM-dd HH:mm:ss"))\n")
        text += String(localized: "版本 \(BuildInfo.version) · \(BuildInfo.edition) · 核心 \(BuildInfo.core)\n")
        text += device()
        text += String(localized: "声音 \(settings.soundOutput.title) · 静音模式时也出声 \(settings.soundInSilentMode ? String(localized: "开") : String(localized: "关")) · 别的 App 在放音乐时「\(settings.otherAudio.title)」\n")
        let haptics = UserDefaults.standard.object(forKey: "foldarc.haptics") as? Bool ?? true
        text += String(localized: "省电 \(settings.powerSaving ? String(localized: "开") : String(localized: "关")) · 画面滤镜 \(ScreenFilter.stored.title) · 震动 \(haptics ? String(localized: "开") : String(localized: "关"))\n")
        text += String(localized: "手柄 \(GameControllerInput.shared.padName ?? String(localized: "没有")) · 存档同步 \(SaveSyncModel.shared.enabled ? String(localized: "开") : String(localized: "关"))\n")
        text += String(localized: "上次运行 \(LastRun.previousSummary.map { String(localized: "没有正常结束（最后：\($0)）") } ?? String(localized: "正常结束"))\n")
        let records = LastRun.records()
        text += String(localized: "\n== 这次运行（lastrun.txt）\n") + (records.current ?? String(localized: "（没有）\n"))
        if LastRun.previousSummary != nil, let previous = records.previous {
            text += String(localized: "\n== 上次没有正常结束的运行\n") + previous
        }
        let lines = await logLines()
        text += String(localized: "\n== 这次运行的记录（\(lines.count) 行）\n") + lines.joined(separator: "\n") + "\n"
        let clean = scrub(text, profile)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Zero-EMU-日志-\(stamp(Date(), "yyyyMMdd-HHmmss")).txt")
        do { try clean.write(to: file, atomically: true, encoding: .utf8) } catch {
            NSLog("[about] log not written: %@", "\(error)")
            return nil
        }
        NSLog("[about] log exported: %@ (%d lines of this run)", file.lastPathComponent, lines.count)
        return file
    }
    private static func stamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format
        return f.string(from: date)
    }
    private static func device() -> String {
        #if os(iOS)
        var info = utsname(); uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { String(localized: "\($0)（模拟器）") } ?? machine
        let screens = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { scene in
            String(localized: "\(scene.session.role == .windowApplication ? String(localized: "屏幕") : scene.session.role.rawValue) \(Int(scene.screen.bounds.width))×\(Int(scene.screen.bounds.height)) pt @\(Int(scene.screen.scale))x")
        }
        return String(localized: "设备 \(model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(screens.joined(separator: String(localized: "；")))\n")
        #else
        return String(localized: "设备 Mac 预览\n")
        #endif
    }
    /// FoldArc's own lines of this run, the last 3000 (off the main thread:
    /// the store is read through).
    private static func logLines() async -> [String] {
        #if os(iOS)
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let clock = DateFormatter(); clock.locale = Locale(identifier: "en_US_POSIX"); clock.dateFormat = "HH:mm:ss.SSS"
                var kept: [String] = []
                for case let entry as OSLogEntryLog in try store.getEntries() where entry.composedMessage.hasPrefix("[") {
                    kept.append("\(clock.string(from: entry.date)) \(entry.composedMessage)")
                    if kept.count > 3600 { kept.removeFirst(600) }
                }
                return Array(kept.suffix(3000))
            } catch {
                return [String(localized: "（读不到这次运行的记录：\(error.localizedDescription)）")]
            }
        }.value
        #else
        return []
        #endif
    }
    /// The owner's name, birthday and country out; the setup's line (which
    /// says all three) left out; the app's folder as "~".
    private static func scrub(_ text: String, _ profile: ConsoleProfile) -> String {
        var lines = text.components(separatedBy: "\n").filter { !$0.contains("[system] setup done") }
        let home = NSHomeDirectory()
        let name = profile.userName.trimmingCharacters(in: .whitespaces)
        for index in lines.indices {
            var line = lines[index].replacingOccurrences(of: home, with: "~")
            if name.count >= 2 { line = line.replacingOccurrences(of: name, with: String(localized: "‹用户名›")) }
            line = line.replacingOccurrences(of: profile.birthdayText, with: String(localized: "‹生日›"))
            if profile.countryName.count >= 2 { line = line.replacingOccurrences(of: profile.countryName, with: String(localized: "‹国家›")) }
            lines[index] = line
        }
        return lines.joined(separator: "\n")
    }
}

#if os(iOS)
/// The system's share sheet for a file (导出日志), from the window on the
/// iPhone's own screen (not a TV's), over whatever is presented there.
@MainActor enum SharePresenter {
    static func share(_ url: URL) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive && $0.session.role != .windowExternalDisplayNonInteractive }
        let windows = scenes.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first, var top = window.rootViewController else {
            NSLog("[about] no window for the share sheet")
            return false
        }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
        NSLog("[about] share sheet up: %@", url.lastPathComponent)
        return true
    }
}
#endif

private struct AboutPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @State private var exporting = false
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            VStack(alignment: .leading, spacing: 1 * s) {
                AppInfoLine(title: "Zero EMU", value: "\(BuildInfo.version) · \(BuildInfo.edition)", s: s)
                AppInfoLine(title: String(localized: "模拟核心"), value: BuildInfo.core, s: s)
                AppInfoLine(title: String(localized: "用户名"), value: ConsoleSettings.shared.profile.userName.isEmpty ? String(localized: "未设置") : ConsoleSettings.shared.profile.userName, s: s)
                AppInfoLine(title: String(localized: "上次运行"), value: LastRun.previousSummary.map { String(localized: "没有正常结束（最后记录：\($0)）") } ?? String(localized: "正常结束"), s: s)
                    .accessibilityIdentifier("last-run")
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            // 11-05: the runs' record as one
            // text file, for a report from a tester on another iPhone.
            AppBigButton(id: "about.export", title: exporting ? String(localized: "正在整理日志…") : String(localized: "导出日志"), symbol: "square.and.arrow.up",
                         note: String(localized: "这次和上次没正常结束的运行记录，不含名字、生日"), noteLines: 3, s: s, model: model) { export() }
            // The links where they are seen (they were only inside 开源许可).
            linkRow("about.privacy", String(localized: "隐私政策"), AppLinks.privacy)
            linkRow("about.support", String(localized: "反馈与支持"), AppLinks.support)
            linkRow("about.source", String(localized: "源码（GPLv3）"), AppLinks.source)
            AppBigButton(id: "about.licenses", title: String(localized: "开源许可与声明（GPLv3）"), symbol: "doc.plaintext", s: s, model: model) { model.push(.licenses) }
            AppNote(text: AzaharSession.isCoreAvailable
                    ? String(localized: "内置 Azahar 3DS 模拟核心（默认 Vulkan 硬件渲染），运行不带加密保护的游戏与 Homebrew；3D 以红蓝方式呈现，裸眼 3D 尚未实现。Zero EMU 不附带、不下载任何游戏。掌机模型、卡带、主菜单和配色都是 Zero EMU 的原创造型。")
                    : String(localized: "这个构建没有附带 3DS 模拟核心：界面、导入与原创演示可用。掌机模型、卡带、主菜单和配色都是 Zero EMU 的原创造型。"), s: s)
            AppNote(text: String(localized: "支持 .3ds / .cci / .cxi / .app 和 Homebrew .3dsx / .elf（仅限不带加密保护的文件）；也可以在「文件」里选择「用 Zero EMU 打开」。"), s: s)
        }
    }
    private func linkRow(_ id: String, _ title: String, _ url: URL?) -> some View {
        AppRow(id: id, title: title, s: s, model: model, action: { open(url, title) }) {
            AppValue(text: url.map { $0.host ?? $0.absoluteString } ?? String(localized: "上架前填"), s: s)
        }
    }
    private func open(_ url: URL?, _ title: String) {
        ConsoleSounds.shared.play(.select)
        guard let url else { model.say(String(localized: "\(title)的网址还没填（上架前填好）")); return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
    private func export() {
        guard !exporting else { return }
        ConsoleSounds.shared.play(.select)
        exporting = true
        Task { @MainActor in
            let file = await RunLogExport.make()
            exporting = false
            guard let file else { model.say(String(localized: "没能整理出日志")); return }
            #if os(iOS)
            if !SharePresenter.share(file) { model.say(String(localized: "日志放在：\(file.lastPathComponent)")) }
            #endif
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .about else { return }
        model.layout = [["about.export"], ["about.privacy"], ["about.support"], ["about.source"], ["about.licenses"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "about.licenses": { model.push(.licenses) }, "about.export": { export() },
                          "about.privacy": { open(AppLinks.privacy, String(localized: "隐私政策")) }, "about.support": { open(AppLinks.support, String(localized: "反馈与支持")) },
                          "about.source": { open(AppLinks.source, String(localized: "源码")) }]
        model.adjusters = [:]
        model.registered(initial: "about.export")
    }
}

private struct LicensesPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    /// 11-07: the full licence texts, one component at a time (a tap
    /// on a name opens its text under it).
    @State private var opened: Set<Int> = []
    var body: some View {
        register()
        return ScrollView {
            VStack(alignment: .leading, spacing: 6 * s) {
                Text(OpenSourceNotice.summary).font(.system(size: AppMetrics.text(9, s))).fixedSize(horizontal: false, vertical: true)
                // The addresses live in AppLinks (Domain.swift); a missing
                // one is left out (development builds say so for the source,
                // which the GPL needs before anything ships).
                if let source = AppLinks.source {
                    Link(destination: source) { Label("源码仓库", systemImage: "chevron.left.forwardslash.chevron.right") }
                        .font(.system(size: AppMetrics.text(9.5, s), weight: .bold))
                } else {
                    #if DEBUG
                    Text("源码仓库地址还没填（AppLinks.source），上架前要填。").font(.system(size: AppMetrics.text(8.5, s), weight: .semibold)).foregroundStyle(SystemMenuStyle.stop)
                    #endif
                }
                if let privacy = AppLinks.privacy {
                    Link(destination: privacy) { Label("隐私政策", systemImage: "hand.raised") }.font(.system(size: AppMetrics.text(9.5, s), weight: .bold))
                }
                if let support = AppLinks.support {
                    Link(destination: support) { Label("反馈与支持", systemImage: "bubble.left") }.font(.system(size: AppMetrics.text(9.5, s), weight: .bold))
                }
                ForEach(OpenSourceNotice.components, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 1 * s) {
                        Text(item.name).font(.system(size: AppMetrics.text(9, s), weight: .semibold))
                        Text(item.license).font(.system(size: AppMetrics.text(8.5, s), design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
                    }
                }
                Text("This program comes with ABSOLUTELY NO WARRANTY. See the GNU General Public License for details.")
                    .font(.system(size: AppMetrics.text(8, s))).foregroundStyle(SystemMenuStyle.inkSoft)
                if !ThirdPartyLicenses.blocks.isEmpty {
                    Text("完整许可文本").font(.system(size: AppMetrics.text(10, s), weight: .bold)).padding(.top, 6 * s)
                    Text("点一项展开它的许可证原文（英文）。").font(.system(size: AppMetrics.text(8, s))).foregroundStyle(SystemMenuStyle.inkSoft)
                    ForEach(ThirdPartyLicenses.blocks) { block in
                        VStack(alignment: .leading, spacing: 2 * s) {
                            Button {
                                if opened.contains(block.id) { opened.remove(block.id) } else { opened.insert(block.id) }
                            } label: {
                                HStack(spacing: 4 * s) {
                                    Image(systemName: opened.contains(block.id) ? "chevron.down" : "chevron.right").font(.system(size: 7 * s, weight: .bold))
                                    Text(block.name).font(.system(size: AppMetrics.text(9, s), weight: .semibold))
                                    Spacer(minLength: 0)
                                    Text(block.licence).font(.system(size: AppMetrics.text(7.5, s), design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("licenses.block.\(block.id)")
                            if opened.contains(block.id) {
                                Text(block.text).font(.system(size: 7 * s, design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 10 * s)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12 * s).padding(.vertical, 8 * s)
        }
        .accessibilityIdentifier("licenses-text")
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .licenses else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

private struct EulaPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            // The summary of Zero EMU's own user agreement; the full text is
            // the web page (and the App Store page's License Agreement).
            VStack(alignment: .leading, spacing: 6 * s) {
                Text("Zero EMU 用户协议").font(.system(size: AppMetrics.text(11, s), weight: .bold, design: .rounded))
                Text("这是 Zero EMU 用户协议的摘要。完整文字见下面的链接，以完整文字为准。")
                Text("开源：Zero EMU 的程序代码以 GPL 第 3 版公开，内置的开源组件按各自的许可证授权。你依这些许可证享有的权利，用户协议不限制。")
                Text("游戏文件：Zero EMU 不含、也不提供任何游戏、固件或密钥。请只导入你有权使用的文件；带加密保护的文件会被拒收。")
                Text("购买：付费功能是可选的，走 App Store。月付、年付自动续期，可以在「管理订阅」里取消；退款由 Apple 处理。")
                Text("其他：Zero EMU 按现状提供，不保证每个游戏都能运行。它没有账号，也没有自己的服务器。它与任何游戏机或游戏的厂商没有关联。")
            }
            .font(.system(size: AppMetrics.text(9, s)))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12 * s).padding(.vertical, 8 * s)
            AppRow(id: "eula.full", title: String(localized: "完整的用户协议"), s: s, model: model, action: { openFull() }) {
                AppValue(text: AppLinks.terms.map { $0.host ?? $0.absoluteString } ?? String(localized: "上架前填"), s: s)
            }
        }
    }
    private func openFull() {
        ConsoleSounds.shared.play(.select)
        let title = String(localized: "完整的用户协议")
        guard let url = AppLinks.terms else { model.say(String(localized: "\(title)的网址还没填（上架前填好）")); return }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .eula else { return }
        model.layout = [["eula.full"], [ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "eula.full": { openFull() }]
        model.adjusters = [:]
        model.registered(initial: "eula.full")
    }
}

private struct UpdatePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            VStack(alignment: .leading, spacing: 1 * s) {
                AppInfoLine(title: String(localized: "现在的版本"), value: BuildInfo.version, s: s)
                AppInfoLine(title: String(localized: "模拟核心"), value: BuildInfo.core, s: s)
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            AppNote(text: String(localized: "Zero EMU 跟着 App Store 更新：有新版本时 App Store 会提示，更新后游戏库、存档和设置都在。即时存档要用同一个版本的核心才读得回来；换了核心版本，「继续上次」会说明原因。"), s: s)
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .update else { return }
        model.layout = [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

/// 格式化主机: asked twice; the library, the states, the console's storage
/// and every setting go, and the console sets itself up again.
private struct FormatPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            AppNote(text: String(localized: "格式化会删除：游戏库里的游戏副本和图标、即时存档和继续进度、主机存储（SD 卡、系统存储、软件自己的存档）、演示的进度、游戏记录，和所有系统设置（用户信息、家长控制、触摸屏、声音、亮度、画面渲染、主题）。「文件」里你自己的原文件不会动；机身配色、音量和 3D 滑块也不变。删掉就找不回来了。"), s: s)
            if settings.parental.restrictDelete {
                AppNote(text: String(localized: "家长控制限制了删除，不能格式化。"), s: s)
            } else if let suspended = ctx.suspended {
                AppNote(text: String(localized: "「\(suspended)」正在运行（暂停在主菜单下面）。格式化要先关闭它：按 HOME，在主菜单里选它、「关闭软件」。"), s: s)
                    .accessibilityIdentifier("format-blocked")
            } else {
                AppBigButton(id: "format.start", title: String(localized: "格式化"), symbol: "trash", s: s, model: model) { ask() }
            }
        }
    }
    private func ask() {
        model.confirm(.init(title: String(localized: "格式化主机？"), message: String(localized: "游戏副本、存档、主机存储和所有设置都会删掉。"), confirm: String(localized: "继续"), identifier: "format-first") {
            model.confirm(.init(title: String(localized: "真的要格式化吗？"), message: String(localized: "这是最后一次确认。格式化以后，主机会回到第一次开机的样子。"), confirm: String(localized: "格式化"), identifier: "format-confirm") {
                ConsoleFormatter.formatEverything(games: ctx.games, remove: ctx.remove)
                model.leave()
            })
        })
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .format else { return }
        let can = !settings.parental.restrictDelete && ctx.suspended == nil
        model.layout = (can ? [["format.start"]] : []) + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }, "format.start": ask]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barLeft)
    }
}

/// What 格式化 deletes. DEBUG `--foldarc-format-dry-run` only logs it.
enum ConsoleFormatter {
    @MainActor static func formatEverything(games: [GameRecord], remove: (GameRecord) -> Void) {
        var dryRun = ConsoleSettings.shared.dryRun
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-format-dry-run") { dryRun = true }
        #endif
        let console = Storage.filesFolder.appendingPathComponent("Azahar", isDirectory: true)
        NSLog("[system] format%@: %d games, states %@, console storage %@", dryRun ? " (dry run)" : "", games.count, SaveStates.folder.path, console.path)
        guard !dryRun else { return }
        for game in games { remove(game) }
        let manager = FileManager.default
        try? manager.removeItem(at: SaveStates.folder)
        try? manager.removeItem(at: console)
        try? manager.removeItem(at: Storage.root.appendingPathComponent("demo-checkpoint.json"))
        PlayLog.shared.forgetAll()
        // The console's settings and the card it read. What is the console's
        // body stays as it is (a format does not repaint the shell or move
        // its sliders): the finish, the volume and 3D sliders, the play mode.
        for key in ["FoldArc.insertedCard", "FoldArc.insertedCardOut", "FoldArc.libraryTheme",
                    "foldarc.brightness", "foldarc.haptics", ConsoleHaptics.strengthKey, ConsoleHomeShortcut.hiddenKey,
                    "FoldArc.renderer", "FoldArc.resolutionFactor", "FoldArc.retroPixels"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        ConsoleSettings.shared.forgetEverything()
        // 11-23: a new console again: its hints come once more (OnceHint)
        OnceHint.forgetAll()
    }
}

// MARK: Setup only

private struct WelcomePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        return VStack(spacing: 8 * s) {
            MenuArcMark(size: 52 * s, color: SystemMenuStyle.ink)
            Text("你好！").font(.system(size: 16 * s, weight: .heavy, design: .rounded))
            AppNote(text: String(localized: "这台主机第一次开机。先设几样：语言、时间、你的名字、生日、国家/地区，一分钟就好。"), s: s)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22 * s)
        .frame(maxHeight: .infinity)
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .setupWelcome else { return }
        model.layout = [[ConsoleAppModel.barLeft, ConsoleAppModel.barRight]]
        model.handlers = [ConsoleAppModel.barLeft: { model.leave() },
                          ConsoleAppModel.barRight: { model.push(.setupLanguage) }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barRight)
    }
}

private struct FinishPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        let draft = model.draft
        return AppScroll(model: model, s: s) {
            VStack(alignment: .leading, spacing: 1 * s) {
                AppInfoLine(title: String(localized: "语言"), value: draft.language.title, s: s)
                AppInfoLine(title: String(localized: "用户名"), value: draft.userName, s: s)
                AppInfoLine(title: String(localized: "生日"), value: draft.birthdayText, s: s)
                AppInfoLine(title: String(localized: "国家/地区"), value: draft.countryName, s: s)
            }
            .padding(.vertical, 4 * s)
            .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
            AppNote(text: String(localized: "点「完成」，主机就设好了。这些以后都能在「系统设置 › 其他设置」里改。"), s: s)
        }
    }
    private func register() {
        // Only the page on screen says what it holds (a page on its way
        // out can still be drawn once more).
        guard model.page == .setupFinish else { return }
        model.layout = [[ConsoleAppModel.barLeft, ConsoleAppModel.barRight]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() },
                          ConsoleAppModel.barRight: { AppPageView.rightButton(model: model)?.action() }]
        model.adjusters = [:]
        model.registered(initial: ConsoleAppModel.barRight)
    }
}

// MARK: - The upper screen's content

private struct AppTopContent: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    var body: some View {
        switch model.page {
        case .profileName, .setupName: TextEntry(model: model, s: s, title: String(localized: "用户名"), placeholder: String(localized: "最多 10 个字"), secret: false)
        case .parentalAnswer, .parentalForgot:
            TextEntry(model: model, s: s, title: ParentalControls.questions[min(ConsoleSettings.shared.parental.question, ParentalControls.questions.count - 1)],
                      placeholder: String(localized: "答案"), secret: false)
        case .dateTime, .setupDateTime: BigClock(s: s)
        case .screen3D: StereoTestCard(session: ctx.session, s: s)
        case .circlePad: StickView(s: s)
        case .mic: MicMeter(session: ctx.session, s: s)
        case .about, .update: AboutCard(s: s)
        case .setupWelcome, .setupLanguage, .setupBirthday, .setupCountry, .setupFinish: SetupCard(model: model, s: s)
        case .profile: ProfileCard(s: s)
        case .activity: ActivityTopCard(model: model, ctx: ctx, s: s)
        case .theme: ThemeTopCard(model: model, s: s)
        case .finish: FinishTopCard(model: model, s: s)
        case .skins: SkinsTopCard(model: model, s: s)
        case .deleteStyle: DeleteStyleTopCard(model: model, s: s)
        case .pencilBox: PencilLookTopCard(model: model, s: s)
        case .filter: FilterTopCard(model: model, s: s)
        case .tvSet: TVSetTopCard(model: model, ctx: ctx, s: s)
        case .manual, .manualSection: ManualTopCard(model: model, s: s)
        case .pro: ProTopCard(s: s)
        case .cartridgePass: CartridgePassTopCard(s: s)
        default: FocusCard(model: model, s: s)
        }
    }
}

/// The focused item explains itself; else the page does.
private struct FocusCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        // The focused item explains itself; on a page whose items have no
        // words of their own (a switch, the bar's 返回) the page does.
        let info = model.focus.flatMap { AppItemInfo.catalog[$0] ?? HomeRowPage.info($0) } ?? AppItemInfo.catalog[AppItemInfo.key(for: model.page) ?? ""]
        HStack(alignment: .center, spacing: 16 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(SystemMenuStyle.tile)
                    .shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 2 * s)
                Image(systemName: info?.symbol ?? model.app.symbol).font(.system(size: 30 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.accent)
            }
            .frame(width: 70 * s, height: 70 * s)
            VStack(alignment: .leading, spacing: 5 * s) {
                Text(info?.title ?? model.page.title).font(.system(size: 17 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                // What the item is, never under a caption's size (the upper
                // screen is drawn smaller than the lower one): the lines it
                // needs there instead of five, which the screen has room for.
                Text(info?.text ?? pageText).font(.system(size: AppMetrics.text(10, s), weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .lineLimit(9).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20 * s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
    private var pageText: String {
        switch model.page {
        case .root: return String(localized: "主机的设置。用十字键选，A 打开，B 返回；也可以直接点下屏。")
        case .other: return String(localized: "第 \(model.otherPage + 1) 页，共 \(OtherPage.pages.count) 页。用 L / R 或下屏的箭头翻页。")
        case .data: return String(localized: "游戏库里的软件和存档。")
        case .parental: return String(localized: "限制孩子能用的功能。")
        case .parentalPIN: return String(localized: "用下屏的数字键输入。")
        case .parentalQuestion: return String(localized: "忘记密码时要回答它。")
        case .parentalRestrictions: return String(localized: "开着的项目被限制。")
        case .internet: return String(localized: "没有账号，没有自己的服务器。")
        case .sound: return ConsoleSettings.shared.soundOutput.detail
        case .language: return String(localized: "菜单和软件都用这个语言：菜单只有中文和英文，选别的语言时菜单用英文；软件要支持这个语言才会换。下次打开 Zero EMU 时生效。")
        case .rendering: return String(localized: "下次开启软件时生效。")
        case .touch: return String(localized: "点三个目标做校正；下面的空白处可以试一试。")
        case .touchCalibrate: return String(localized: "用手指（或触控笔）点准红色十字的中心。")
        case .format: return String(localized: "删除所有数据，回到第一次开机的样子。")
        case .licenses: return String(localized: "Zero EMU 用到的开源软件和它们的许可证。")
        case .eula: return String(localized: "使用 Zero EMU 的条件。")
        case .tv: return String(localized: "接上电视：控制中心 ›「屏幕镜像」选 Apple TV 或支持 AirPlay 的电视，或用转接线接 HDMI。")
        case .modes: return String(localized: "选一种玩法。在游戏里换马上生效；在游戏库里换，下次开始游戏时用。")
        default: return ""
        }
    }
}

/// Text typed on the upper screen (the keyboard covers the lower one, as a
/// handheld's keyboard does).
private struct TextEntry: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var title: String
    var placeholder: String
    var secret: Bool
    @FocusState private var focused: Bool
    private var isName: Bool { model.page == .profileName || model.page == .setupName }
    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text(title).font(.system(size: 12 * s, weight: .bold, design: .rounded))
            // Nothing is cut while typing (an input method still composing
            // would break); a name too long shows red and is not taken.
            TextField(placeholder, text: Binding(
                get: { isName ? model.draft.userName : model.answer },
                set: { text in
                    if isName { model.draft.userName = text } else { model.answer = text }
                }))
                .font(.system(size: 16 * s, weight: .semibold, design: .rounded))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10 * s).padding(.vertical, 8 * s)
                .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9 * s, style: .continuous).strokeBorder(focused ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge, lineWidth: focused ? 2 : 1))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { submit() }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier(isName ? "name-field" : "answer-field")
            if isName {
                let length = model.draft.nameLength
                Text(length > ConsoleProfile.nameLimit ? "\(length) / \(ConsoleProfile.nameLimit)：太长了" : "\(length) / \(ConsoleProfile.nameLimit)")
                    .font(.system(size: 9 * s, weight: .semibold, design: .monospaced))
                    .foregroundStyle(length > ConsoleProfile.nameLimit ? SystemMenuStyle.stop : SystemMenuStyle.inkSoft)
                    .accessibilityIdentifier("name-count")
            }
        }
        .padding(.horizontal, 22 * s)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                focused = true
            }
        }
    }
    private func submit() {
        focused = false
        AppPageView.rightButton(model: model)?.action()
    }
}

private struct BigClock: View {
    var s: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4 * s) {
                Text(context.date.formatted(.dateTime.locale(UILanguage.locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                    .font(.system(size: 52 * s, weight: .heavy, design: .rounded).monospacedDigit())
                Text(context.date.formatted(.dateTime.locale(UILanguage.locale).year().month().day().weekday(.wide)))
                    .font(.system(size: 12 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
            }
        }
        .accessibilityIdentifier("app-clock")
    }
}

/// A red/cyan test picture that follows the 3D slider: three plates at
/// three depths.
private struct StereoTestCard: View {
    @ObservedObject var session: DemoSession
    var s: Double
    var body: some View {
        let depth = session.depth3D
        Canvas { context, size in
            let plates: [(CGFloat, CGFloat, CGFloat)] = [(0.30, 0.55, 0.2), (0.52, 0.45, 0.6), (0.72, 0.5, 1.0)]
            func draw(_ eye: CGFloat, _ color: Color, in ctx: inout GraphicsContext) {
                for (x, y, z) in plates {
                    let shift = eye * depth * z * size.width * 0.03
                    let rect = CGRect(x: x * size.width - 34 * s + shift, y: y * size.height - 26 * s, width: 68 * s, height: 52 * s)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 8 * s), with: .color(color))
                }
            }
            if depth > 0 {
                context.blendMode = .multiply
                var left = context
                draw(-1, Color(red: 1, green: 0.25, blue: 0.25), in: &left)
                var right = context
                draw(1, Color(red: 0.2, green: 0.85, blue: 0.95), in: &right)
            } else {
                draw(0, SystemMenuStyle.ink.opacity(0.75), in: &context)
            }
        }
        .padding(.horizontal, 20 * s)
        .overlay(alignment: .bottom) {
            Text(depth == 0 ? "3D：关" : "3D：\(Int((depth * 100).rounded()))%").font(.system(size: 10 * s, weight: .bold, design: .monospaced))
                .foregroundStyle(SystemMenuStyle.inkSoft).padding(.bottom, 6 * s)
        }
        .accessibilityElement().accessibilityLabel("3D 测试图").accessibilityValue(depth == 0 ? "关" : "\(Int((depth * 100).rounded()))%")
    }
}

/// Where the Circle Pad is, inside its circle, with the dead zone: the
/// grey dot is the stick as held, the blue one what the software gets.
private struct StickView: View {
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    @ObservedObject private var probe = StickProbe.shared
    var body: some View {
        let raw = probe.raw
        let tuned = StickTuning.apply(raw, deadzone: settings.stickDeadzone)
        let radius = 58 * s
        ZStack {
            Circle().fill(SystemMenuStyle.tile).frame(width: radius * 2, height: radius * 2)
            Circle().strokeBorder(SystemMenuStyle.tileEdge, lineWidth: 2).frame(width: radius * 2, height: radius * 2)
            Path { p in
                p.move(to: CGPoint(x: 0, y: radius)); p.addLine(to: CGPoint(x: 2 * radius, y: radius))
                p.move(to: CGPoint(x: radius, y: 0)); p.addLine(to: CGPoint(x: radius, y: 2 * radius))
            }
            .stroke(SystemMenuStyle.tileEdge.opacity(0.6), lineWidth: 1)
            .frame(width: radius * 2, height: radius * 2)
            Circle().fill(SystemMenuStyle.stop.opacity(0.18))
                .frame(width: max(2, radius * 2 * settings.stickDeadzone), height: max(2, radius * 2 * settings.stickDeadzone))
            Circle().fill(SystemMenuStyle.inkSoft.opacity(0.45)).frame(width: 10 * s, height: 10 * s)
                .offset(x: raw.x * radius, y: raw.y * radius)
            Circle().fill(SystemMenuStyle.accent).frame(width: 16 * s, height: 16 * s)
                .shadow(color: SystemMenuStyle.accent.opacity(0.5), radius: 3 * s)
                .offset(x: tuned.x * radius, y: tuned.y * radius)
            // Up is + as people say it (the finger's drag grows downwards).
            Text(String(format: "x %+.2f   y %+.2f", tuned.x, -tuned.y)).font(.system(size: 9 * s, weight: .semibold, design: .monospaced))
                .foregroundStyle(SystemMenuStyle.inkSoft)
                .offset(y: radius + 13 * s)
        }
        .onAppear { StickProbe.shared.active = true }
        .onDisappear { StickProbe.shared.active = false }
        .accessibilityElement().accessibilityLabel("摇杆位置").accessibilityValue(String(format: "%.2f, %.2f", tuned.x, -tuned.y))
        .accessibilityIdentifier("stick-view")
    }
}

private struct MicMeter: View {
    @ObservedObject var session: DemoSession
    /// What the iPhone's microphone hears, while it is on.
    @ObservedObject private var mic = MicListener.shared
    var s: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !session.micBlowing && !mic.on)) { context in
            HStack(alignment: .center, spacing: 3 * s) {
                ForEach(0..<24, id: \.self) { index in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let wobble = abs(sin(t * 9 + Double(index) * 0.7)) * abs(cos(t * 3.1 + Double(index)))
                    let level = mic.on ? max(0.04, mic.level * (0.55 + 0.45 * wobble)) : (session.micBlowing ? 0.35 + 0.6 * wobble : 0.04)
                    Capsule().fill(session.micBlowing ? SystemMenuStyle.go : (mic.on && mic.level > 0.08 ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge))
                        .frame(width: 5 * s, height: max(4 * s, level * 90 * s))
                }
            }
        }
        .accessibilityElement().accessibilityLabel("麦克风电平")
        .accessibilityValue(session.micBlowing ? "有人在吹" : (mic.on ? "\(Int((mic.level * 100).rounded()))%" : "安静"))
        .accessibilityIdentifier("mic-meter")
    }
}

private struct AboutCard: View {
    var s: Double
    var body: some View {
        VStack(spacing: 8 * s) {
            MenuArcMark(size: 60 * s, color: SystemMenuStyle.ink)
            Text("ZERO").font(.system(size: 22 * s, weight: .heavy, design: .rounded)).tracking(5 * s)
            Text(BuildInfo.version).font(.system(size: 11 * s, weight: .semibold, design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
        }
    }
}

private struct ProfileCard: View {
    var s: Double
    @ObservedObject private var settings = ConsoleSettings.shared
    var body: some View {
        let profile = settings.profile
        HStack(spacing: 16 * s) {
            ZStack {
                Circle().fill(SystemMenuStyle.accent)
                Text(String(profile.userName.prefix(1)).uppercased()).font(.system(size: 30 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: 72 * s, height: 72 * s)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(profile.userName.isEmpty ? String(localized: "未设置") : profile.userName).font(.system(size: 20 * s, weight: .bold, design: .rounded))
                Text("生日 \(profile.birthdayText) · \(profile.countryName)").font(.system(size: 10 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                Text("\(profile.language.title) · 区域 \(profile.region.title)").font(.system(size: 10 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22 * s)
        .accessibilityElement(children: .combine).accessibilityIdentifier("profile-card")
    }
}

private struct SetupCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            Text(title).font(.system(size: 19 * s, weight: .bold, design: .rounded))
            Text(text).font(.system(size: 11 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24 * s)
        .accessibilityElement(children: .combine).accessibilityIdentifier("setup-card")
    }
    private var title: String {
        switch model.page {
        case .setupWelcome: return String(localized: "主机初始设置")
        case .setupLanguage: return String(localized: "选择语言")
        case .setupBirthday: return String(localized: "你的生日")
        case .setupCountry: return String(localized: "你住在哪里")
        case .setupFinish: return String(localized: "设置好了")
        default: return model.page.title
        }
    }
    private var text: String {
        switch model.page {
        case .setupWelcome: return String(localized: "欢迎！这台主机还没有设置过。点「下一步」开始。")
        case .setupLanguage: return String(localized: "菜单和软件都用这个语言：菜单只有中文和英文，选别的语言时菜单用英文；软件要支持这个语言才会换。下次打开 Zero EMU 时生效。")
        case .setupBirthday: return String(localized: "只存在这台主机里。")
        case .setupCountry: return String(localized: "用来显示时间和日期的习惯。主机区域保持「自动」，跟着软件。")
        case .setupFinish: return String(localized: "看一眼，没问题就点「完成」。")
        default: return ""
        }
    }
}


// MARK: - 游戏记录, 主题, 说明书 (round 30)

// The three were pages laid over the shelf (round 20); now they run on the
// console's two screens like 系统设置, as a handheld's play log and its
// electronic manual do — the list on the touch screen, what is chosen
// explained on the upper screen, the D-pad (or the Circle Pad) to move, A to
// choose, B to go back, HOME back to the menu.

/// The manual's text: the library and the console, the keys in a game, a
/// controller. Grouped as its list shows it.
enum ManualText {
    struct Section { var title: String; var symbol: String; var text: String }
    static let groups: [(title: String, sections: [Section])] = [
        (String(localized: "游戏库"), [
            Section(title: String(localized: "开机"), symbol: "power", text: String(localized: "第一次开机先做初始设置（语言、日期和时间、用户名、生日、国家/地区）。设好以后，掌机里插着卡带时打开 Zero EMU 会直接进那个软件；没插卡带（或没插到底）就停在游戏库。在游戏库里按台子上掌机的电源键也是开机：插着游戏卡带，就接着上次开这个游戏；没插卡带，掌机拿起来铺满屏幕，进主菜单，相机、相册这些都在大屏上用（在里面按 HOME 回主菜单）；在主菜单再按一下电源键，掌机放回台子。")),
            Section(title: String(localized: "挑卡带"), symbol: "rectangle.stack", text: String(localized: "在下面的架子上左右滑动，或点两边的卡带；中间那张面对你，它背后的光是它标签的颜色。")),
            Section(title: String(localized: "插卡带"), symbol: "arrow.up.square", text: String(localized: "把中间那张往上拖起来，掌机会转到背面、打开卡槽；放到掌机上就插进去，咔嗒一声，掌机转回原来的样子。插着的卡带不在架子上。点卡带上的 ▶，它会自己插进掌机并开启。")),
            Section(title: String(localized: "manual.start.title"), symbol: "play.fill", text: String(localized: "插好后，掌机下屏主菜单的第一个图标就是这张卡带：点一下选中（上屏显示它），再点一下、点「开启」或按掌机上的 A 键开始。有上次的进度时是「继续上次」和「重新开始」。")),
            Section(title: String(localized: "拔卡带"), symbol: "arrow.down.square", text: String(localized: "长按掌机翻到背面，按住露出来的卡带往外拉：拉到哪就停在哪，没插到底时掌机读不到它；推回去到底会咔嗒一声接上。拉出来以后放到架子上；轻点卡带它会自己出来回到架子上。")),
            Section(title: String(localized: "主菜单"), symbol: "square.grid.2x2", text: String(localized: "掌机下屏的主菜单一页两排各四个图标：卡带、相机、相册、设置；导入、游戏记录、主题、说明书——「游玩模式」和「画框」在第二页：在下屏左右滑动翻页（或点底栏中间的小圆点，十字键走过一排的头尾也会翻过去）。最上面一排是小图标：游戏笔记、铅笔盒、屏幕亮度、画面滤镜（游戏暂停时前面还有保存进度、读取进度），点一下就开。十字键或摇杆移动选择，A 打开，B 返回。在游戏库里、按电源键或两指放大进掌机、游戏里按 HOME，看到的都是同一个主菜单；只有「导入」只在游戏库里有（导入的卡带落在游戏库的架子上）。没插卡带时其他的也能用。")),
            Section(title: String(localized: "相机"), symbol: "camera.fill", text: String(localized: "主菜单的「相机」（或点一下掌机的 L、R 肩键）直接在掌机上打开：卡带收起来，掌机放大铺平，上屏是取景，下屏是相机的按钮（手机屏幕小，相机铺满屏幕）。按 L、R 或 A 拍照；下屏可以换内侧（iPhone 前置）/ 外侧（iPhone 后置）相机，选镜头：普通、闪闪（按住 MIC 吹气）、合体（先外侧拍对方、再内侧拍自己）、白日梦、暗处、针孔、不可思议；还有 3 秒 / 10 秒定时、手动调整（胶片、亮度、对比度、锐度）。十字键开关水平仪，B 返回，HOME 回到主菜单。iPhone 的「相机控制」键也能用：相机开着时按下就拍照（音量键、设成相机的操作按钮一样），轻按滑出的小菜单里能换镜头和变焦；相机关了就还给系统。相机开着时合上 iPhone Duo，外屏就是相机的操作台：左边是取景，右手拇指下面是拍照键，取景下面一排镜头；在取景上左右划换镜头，两指捏合放大（也可以点取景上的 1、2、4，用外侧还有 .5；当前那颗是蓝的、写着倍数，横着拿时这排竖着靠在取景挨着拍照键的那一边），「相册」翻看刚拍的；取景下面右边的「切换机型」打开和里面一样的机型菜单（取景下面那排镜头不变），点哪台取景里马上就是它的样子，★ 固定到镜头栏，「收起」关上；最下面一排是老相机的设置——闪光（关、自动、开、防红眼）、白平衡（自动、日光、阴天、白炽灯、荧光灯；设错了光，照片就偏那个颜色）、ISO（自动、100 到 1600：越高越亮、噪点越多）、曝光补偿（±2，半档一级）、日期（印在照片右下角），所有镜头都用，里面的「调整」也有这一排；相机控制键、音量键照样能拍。半开着立起来像帐篷、外屏朝外时，外屏整个是画面，给被拍的人看：点一下画面倒数 3 秒（定时设得更长就按定时）再拍，倒数时再点一下取消。底栏的「机型」（或按 Y）是模拟的老相机：原生、老 CCD、暖金胶卷、即显相纸、一次性胶卷、磁带 DV、银盐黑白、千禧像素、00后梦核、冷蓝 CCD、闪光直拍、正片、褪色老照片、交叉冲印、玩具相机、电影卷、放学路上、微机课、生日那晚、VCD 截图（色调、颗粒、暗角、漏光、日期印、相纸都是 Zero EMU 自己做的，不是哪个牌子的），十字键在卡片间走、A 用、X 固定到镜头栏（最多四台，接在九个镜头后面，再点一下回到原生）、B 返回；L、R（或卡片下面的 − ＋）调这台机型的浓淡：25% 到 150%，100% 是原样，每台各记各的，外屏的机型菜单里也有；机型和镜头叠着用。镜头里的「两联」按两次（两张竖着的半格并排成一张），「四连拍」按四次（四张拼在一张相纸上），拍够了才存进相册；中途按 B 这一张重新拼。照片是 640 × 480 的 JPEG，存在「文件」App 的 我的 iPhone › Zero EMU › Azahar › sdmc › DCIM › 100FOLDA，下屏「相册」里可以看和删除。快门声不受音量滑块影响。")),
            Section(title: String(localized: "相册"), symbol: "photo.on.rectangle.angled", text: String(localized: "主菜单的「相册」直接打开相机拍的照片（相机里的「相册」是同一个）：下屏翻看，上屏放大，X 或「删除」删掉一张，B 回主菜单。「导入」从 iPhone 的「照片」里挑一张（只有挑的那张会交给 Zero EMU），上屏马上是它被机型冲出来的样子：下屏点机型换一台，L、R 或 − ＋ 调浓淡，「保存」存成相册里的一张新照片（原来那张不动；竖着的照片还是竖着，日期印在侧边），「不保存」就什么都不留。相机拍的照片都在这里（游戏笔记的存稿留在游戏笔记里，不进相册；想放进 iPhone 的「照片」，在存稿里点「存到照片」）。照片放在主机的「SD 卡」文件夹里——iPhone 没有 SD 卡，Zero EMU 用一个文件夹模拟 3DS 的 SD 卡（「文件」› Zero EMU › Azahar › sdmc），游戏自己的存档也在那里，相机里的「SD 卡 · 剩余」说的就是它：按 iPhone 实际还剩的空间和照片的大小算还能拍多少张。")),
            Section(title: String(localized: "游戏笔记"), symbol: "pencil.and.outline", text: String(localized: "主菜单最上面一排的小图标「游戏笔记」：下屏是一叠便签，用起来就像真的一叠，想记多少张都行。用手指或 Apple Pencil 在翻开的这一张上写字画画（iPhone Duo 支持 USB-C 的 Apple Pencil；笔不分轻重）。左下角是黑笔、红笔、第三支笔和橡皮：点第三支笔打开「更多颜色」，十二种颜色里挑一种；十字键左右换笔，上打开更多颜色，下拿橡皮，Y 撤销。两个手指在纸上往上推（触控板上两指往上滑也行），这一张就翻过去折在上面，下一张露出来；写过的最后一张翻过去，下面就是新的一页（没写字的空白页不留），「新的一张」（A）直接翻到新的一页。两个手指往下拉，折过去的那张翻回来（L / R 也能翻；手机上纸下面有「上一张」「下一张」）。「撕掉」（X）把这一张撕掉扔了，存稿里它的那几份也一起撕掉。写的东西离开这一张就存好，下次打开还停在你翻到的那一张；「保存」（START）把这一张的样子存成一份存稿，留在游戏笔记里（不进相册）。有存稿时便签右上角夹着一个别针，点它打开存稿：一页八张，上屏放大看，「放回便签」（A）把它放回便签本，「存到照片」（Y）把这份存稿的图片存进 iPhone 的「照片」（第一次会问能不能添加，存稿里的还在），「撕掉」（X）撕掉这份存稿。游戏暂停时按 HOME 打开它，「截屏」（或 SELECT）把游戏的上屏、下屏画面放到纸下面，照着画面做记号。")),
            Section(title: String(localized: "系统设置"), symbol: "gearshape.fill", text: String(localized: "主菜单的「设置」直接在掌机的两块屏上打开：互联网设置、家长控制、数据管理、TV输出、其他设置（用户信息、日期和时间、手柄、语言、声音、麦克风、触摸屏、摇杆、画面滤镜、3D、省电、亮度、画面渲染、震动、关于本机、格式化），和典藏卡带。十字键或摇杆选，A 确定，B 返回，HOME 回到主菜单。")),
            Section(title: String(localized: "游戏记录、主题、说明书"), symbol: "book.closed.fill", text: String(localized: "也在掌机的两块屏上打开：下屏是列表，上屏是选中那一项的详情。游戏记录记每个软件玩了多久（在前台、开着盖的时间才算）；主题换配色：游戏库的纸面，和掌机屏幕上的主菜单、设置这些程序（游戏库里的掌机和游戏里的掌机一样；相机、相册、游戏笔记保持原样）；也换掌机的机身配色（游戏库里的掌机马上换，游戏里的掌机也一样；两种颜色的配色，面板是第二种颜色，铰链、边框和背面是第一种）；说明书就是你正在看的这个。")),
            Section(title: String(localized: "触控笔"), symbol: "pencil", text: String(localized: "掌机背面右边插着触控笔：翻到背面点一下就拔出来拿在手里，再点一下收回去。拿着它的时候，点掌机下屏会看到笔尖点在那里。")),
            Section(title: String(localized: "耳机"), symbol: "headphones", text: String(localized: "iPhone 接上耳机（有线、USB-C 或蓝牙）时，掌机正面左边的耳机孔会插上一副白色线控耳机；拔掉就空着。")),
            Section(title: String(localized: "看掌机"), symbol: "rotate.3d", text: String(localized: "拖动旋转，两指缩放（游戏库里任何地方两指都行）。掌机上的按键点了就是按下去：十字键和摇杆移动主菜单的光标，A 打开，B 和 HOME 返回；3D 滑块和音量滑块可以拖。在掌机旁边的空白处连点两下，掌机回到正面。两指放大时下面的卡带跟着变小直到消失，放到最大就进入掌机：掌机铺满屏幕，屏幕上是同一个主菜单；HOME 回到游戏库。放大到哪里，主菜单都照样能点、能打开；打开的程序关掉以后，掌机回到打开前那么大、那个角度。")),
            Section(title: String(localized: "充电"), symbol: "bolt.fill", text: String(localized: "iPhone 在充电时，掌机背面的充电口插着充电线，正面的充电灯亮橙色，充满了就灭（线还插着）。在游戏库里插上或拔掉充电器，掌机会转过来让你看到插头插进去或拔出来，再转回去。")),
            Section(title: String(localized: "音量"), symbol: "speaker.wave.2.fill", text: String(localized: "上屏左边的 VOL 滑块就是 iPhone 自己的音量：往上大、往下小，按 iPhone 的音量键它跟着动，在 iPhone 上直接拖滑钮就是调系统音量，两边永远是同一个数。iOS 不让软件自己改系统音量，只能用系统的音量滑块，所以 Zero EMU 把系统滑块放在滑钮下面。模拟器里没有系统的音量滑块，那里的 VOL 是 Zero EMU 自己的音量（游戏和掌机的声音），手指照样能拖，按侧面的音量键它也跟着动。按起来上下反了的话，到 iPhone 的 设置 › 声音与触感 关掉“固定位置音量控制”（Fixed Position Volume Controls），按键就跟着方向走。")),
            Section(title: String(localized: "游玩模式、TV模式"), symbol: "rectangle.on.rectangle", text: String(localized: "主菜单的「游玩模式」选怎么玩：掌机模式（iPhone 就是掌机，折痕当铰链）、桌面模式（整台掌机摆在屏幕上，铰链能开合）、手柄模式（画面在上，按键放大排在下面）、TV模式（电视上放游戏画面，iPhone 拿在手里当手柄，按键和下屏都在 iPhone 上）、沉浸模式（接上外置手柄以后，整块屏幕只放游戏的两块屏，没有机身和按键：竖着拿上下各一半，横着拿左右各一半，iPhone Duo 上都不压在折痕上；手柄的 HOME 打开主菜单，点一下屏幕上黑的地方也会出来 HOME 和 POWER；没接手柄选不了，玩着手柄断了先换成手柄模式，连上又回来）。在游戏里换马上生效，在游戏库里换就是下次开始游戏用的模式。TV模式要先接电视：控制中心 ›「屏幕镜像」选 Apple TV 或支持 AirPlay 的电视，或用转接线接 HDMI。「选电视」选电视上画哪台电视：七台旧电视，游戏的上屏装在它的屏幕里，「画面」可以选当年的画面（显像管的扫描线、早期液晶的发虚）或最好的画面；或者现代电视，不画外壳，两块屏怎么摆（上下两屏、左右并排、只显示上屏）也在这里选。没接电视也能先选好；TV模式里 iPhone 上也有「选电视」的按钮。别的模式下接电视，电视上和 iPhone 一模一样（屏幕镜像）。系统设置 › TV输出 看接没接上、怎么接。")),
            Section(title: String(localized: "画框"), symbol: "photo.artframe", text: String(localized: "主菜单第二页的「画框」：上屏是一幅一直在动的风景，下屏是时间、几幅风景的小图和几个开关。选好就在放，不用另外开始。把 iPhone 立在桌上（iPhone Duo 半折着放），它就是一个会动的画框；iPhone Duo 开着画框合上，外屏就是这幅画（左右划换一幅），再打开回到画框。点小图换风景：「篝火旁的存档点」「黄昏小镇的屋顶」「下雨的电车站」和「云上的飞艇」。风景的光跟着手机的时间走：夜里是星星和灯火，清晨和傍晚天是粉的，白天亮起来；屋顶那一幅里塔上的钟走的是手机的时间，白天整点会敲钟；电车站那一幅每隔几分钟有一趟电车进站，停一会儿再开走，偶尔还会打雷；飞艇在云海上慢慢漂，偶尔有一群鸟飞过。每幅风景看上一会儿，铅笔盒里就多一张它的明信片。「声音」开着时每幅有自己的声音（柴火、风和风铃、雨声和蛙鸣、高空的风和远远的引擎、虫鸣、鸟叫），音量就是 iPhone 的音量；「早晚的光跟着手机的时间」关掉就一直是夜里；「多久以后熄屏」选了时间，到点两块屏全黑，碰一下屏幕或按任何键亮回来。开着画框时 iPhone 不会自动锁屏（熄屏以后照常）；一会儿没碰，下屏会自己变暗。B 或「返回」回主菜单。不用典藏卡带。")),
            Section(title: String(localized: "铅笔盒"), symbol: "pencil.and.ruler", text: String(localized: "游戏库右下角的小铅笔盒（主菜单里也有它的图标）：一只老铁皮文具盒。打开以后，上屏是盒盖里面，印着乘法口诀表，旁边是攒到的东西，还没攒到的用铅笔画个框，写着还差几张；下屏是盒子里的托盘，没贴出去的东西放在大格子里；托盘有三层，点红布条掀到下一层，下面两层是暖水瓶、搪瓷杯、算盘、小皮球这些老物件，点一下各有各的动静——弹珠在罐子里跳，电话响两声，青蛙蹦两下，风车转两圈——动完响完再贴到盒盖上；贴在盒盖上的，点它可以一直玩。盒盖里的课程表点一下拿出来放大，点哪一格就直接写在哪一格里，下面那排科目点一下也能填进去。亮面塑料那款的盒盖里有面小镜子，点一下打开——真的照得见（用的是朝着你的摄像头，第一次要允许用相机），再点一下关上。帆布那款盒盖里的网兜装着一张纸条和一块橡皮，隔着网点一下，它们会弹一下。自己的照片和便条多了，在松紧带那里左右划着翻页，点带子下面的小圆点也能翻。点一样东西，可以贴到盒盖上，或放回铅笔盒。底下的「照片」从掌机相册或 iPhone 照片里挑一张贴上（iPhone 照片只拿你选的那几张）；「游戏笔记」挑一页写过的便签贴上；「写便条」用手指或 Apple Pencil 写，也能打字，字是手写体（第一次用时 iPhone 会下载一次这种字体）。照片按住选「换一张」，在原来的位置换成别的照片。托盘里有一把尺子和两支铅笔，都能贴到盒盖上；按住一支铅笔拖到卷笔刀的口上，它就转着削起来，削下的木屑落进卷笔刀的小窗，削短了松手就换一支新的；点一下小窗里的木屑，贴一片到盒盖上；每款盒子的卷笔刀各装各的木屑，新换的一款里先有三片。点红按钮，笔架立起来，另外七支彩色铅笔插在上面（一共九种颜色）：点一支就拿到托盘里（托盘满了，先拿出来的那支插回笔架），把托盘里的铅笔拖到笔架上就插回去。日历旁边有一块 ZERO 布标，想贴就贴到盒盖上。松紧带可以拨一下，会弹一两下；它下面压着自己的照片和便条，竖着拿一页两样、横着拿一页三样。明信片在盒盖里有自己的一个槽，摞成一摞，只露最上面一张：往上划换下一张，划过最后一张又是第一张，往下划是上一张；点一下贴到盒盖上，槽里就换成下一张；按住能写背面、换照片。画框里的哪幅风景看过一会儿，就寄来一张那幅的明信片，放进槽里；贴到盒盖上点一下，它翻过来是背面，邮票上是那幅风景的小画，再点一下翻回来。背面朝上时，点邮编的格子或右边的横线，键盘就弹出来，字直接写在那里；点别的地方还是翻面。画框寄来的明信片不会扔掉。点槽上面的纸签「明信片」，出来一只小铁盒，明信片一张张竖在里面，各露出上面一截：点哪一张，它就抽出来变成一张大明信片——点一下翻面；背面点横线或邮编的格子，字就直接写在明信片上，点邮票换一张；正面底下能换照片、贴到盒盖上或拿回铅笔盒；点「完成」，槽里就翻到它。最前面空白的那张是新做一张：大明信片正面中间有「添加照片」，这张照片也当它的邮票，背面空着等你写，什么都没放就不留；自己做的可以扔掉。自己的照片放到明信片正面以后，在大明信片上直接拖动照片，就能挑露出来的部分，两指可以放大。开着铅笔盒合上手机，外屏就是这只铅笔盒的盒盖，样式和颜色跟里面的一样（开着掌机合上，外屏是同一配色的掌机外壳）：一根手指拖动；两根手指转动、缩放刚碰过的那一样；点一下，八音盒放小曲，老物件各动各的、各响各的，明信片翻个面，照片和便条放大看——照片左右划着换一张，便条再点一下就能打字接着写；按住出菜单（放回铅笔盒、摆正、大一点、小一点，还有朝上那一面能做的事：照片「换一张」，便条「写字」，明信片正面「换照片」、背面「写字」——背面的三条横线和邮编的六个格子都能填，邮票能换成别的风景或自己的照片）。按住盒盖上空着的地方，盒盖缩到一边，旁边出来一排小盒盖，四款盒子各一段：点一个就换上，贴着的东西都不动；点一下盒盖或「选好了」回去。这时盒盖底下有个「存为壁纸」，把外屏上这只盒盖（连同贴着的东西）存到「照片」里。再打开手机，铅笔盒还开着。没有外屏的 iPhone，把盒盖边上的搭扣往下拉（横着拿时往右拉），盒盖就跟着手指翻过来合上，点一下搭扣也行；合上后看到的是盒盖外面，摆法一样，点盒盖边上的搭扣或「打开盒盖」，盒盖再翻开。卡带架上自己导入的游戏多起来（演示卡不算），盒子里就多一样小东西——1 张：小红花印章，便签里也能盖；3 张：棒棒糖，相册编辑的贴画里也有；5 张：八音盒；8 张：作业本格子纸，便签和便条多一种纸；12 张：自行车、书包、落叶；18 张：作业本、墨水、毽子、纸风车、铁皮青蛙。得到的东西一直留着，删了游戏也不会收回。不用典藏卡带。")),
        ]),
        (String(localized: "游戏里"), [
            Section(title: String(localized: "游戏里按 HOME"), symbol: "house.fill", text: String(localized: "游戏里按 HOME：游戏暂停，下屏是同一个主菜单，第一个图标是正在玩的软件（「继续游戏」「关闭软件」），上屏是它暂停时的画面。主菜单上面一排小图标：保存进度（把这个软件此刻的样子整个存下来，叫即时存档，和游戏自己的存档无关）、读取进度（回到上次保存进度的那一刻）、存档位（每个游戏有好几个，保存和读取用的是选中的那一个）、游戏笔记、屏幕亮度、画面滤镜、按键点屏、倍速；放哪几个，在系统设置 › 其他设置（第 5 页）›「主菜单顶上的按键」里选，铅笔盒也能放上来。相机、相册、设置、游戏记录、主题、说明书、游玩模式和小图标里的游戏笔记都可以在游戏暂停时直接打开，不换模式，HOME 回到主菜单；只有格式化主机和移除正在玩的软件要先关闭它。导入在游戏库的主菜单里。再按一次 HOME 继续游戏。按 POWER 不进菜单：保存进度（即时存档）后直接回游戏库，掌机带着游戏最后的画面缩回台子上；下次在游戏库里「继续上次」就接着玩。")),
        ] + PlayControls.game.map { Section(title: $0.0, symbol: "gamecontroller", text: $0.1) } + [
            Section(title: String(localized: "画面滤镜"), symbol: "camera.filters", text: String(localized: "系统设置 › 其他设置（第 3 页）› 画面滤镜：原样（像素方方正正）、柔和、扫描线、LCD 网格、老电视。只盖在游戏画面上，换了马上生效，电视上也一样。")),
        ]),
        (String(localized: "典藏卡带"), [
            Section(title: String(localized: "典藏卡带多了什么"), symbol: "star.circle.fill", text: String(localized: "系统设置里的「典藏卡带」：月付带铜卡带，年付带银卡带，一次买断带金卡带。有了任何一张，都多出全部机身配色（免费的是前 \(ProAccess.freeFinishes) 种）、相机的全部机型（免费的是前 \(ProAccess.freeBodies) 种）、每个游戏不限个数的存档位（免费的是前 \(ProAccess.freeStateSlots) 个）、存档同步、TV模式（游戏画面放到电视上，iPhone 当手柄），和游戏里的倍速；带小锁的就是典藏卡带的，点它会带你到那一页。三张卡带各放各的动画：放进掌机、按「开启」，先是开场（卡带的名字、编号、入手的日子），再一段一段放，放完停在最后一段的画面；下屏的胶片条点哪格放哪格，划一下起一阵风；「卡带证」上有编号和日子，2027 年 1 月 1 日（含）以前买的金卡带还有「首发版」的印。月付、年付的卡带跟着订阅，订阅停了就收回去，再订就回来；金卡带一直在。游戏、存档、备份和别的功能不用典藏卡带。换了手机或重装以后，在那一页点「恢复购买」；订阅在「管理订阅」里取消。")),
        ]),
        (String(localized: "外接手柄"), [
            Section(title: String(localized: "手柄"), symbol: "gamecontroller.fill", text: PlayControls.controllerHelp),
        ]),
    ]
    static let sections: [Section] = groups.flatMap(\.sections)
    static func section(_ index: Int) -> Section {
        sections.indices.contains(index) ? sections[index] : Section(title: String(localized: "说明书"), symbol: "book.closed.fill", text: "")
    }
}

/// 游戏记录: each software, longest played first; the upper screen tells
/// the chosen one's time, sessions, first and last day.
private struct ActivityAppPage: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var log = PlayLog.shared
    var body: some View {
        let entries = ActivityTopCard.entries(log)
        register(entries)
        return AppScroll(model: model, s: s) {
            if entries.isEmpty {
                AppNote(text: String(localized: "还没有记录。开启一个软件（演示也算），玩的时间会记在这里：在前台、开着盖的时间才算。"), s: s)
                    .accessibilityIdentifier("activity-empty")
            }
            ForEach(entries) { entry in
                AppRow(id: "activity.\(entry.id)", title: ActivityTopCard.title(of: entry, games: ctx.games), s: s, model: model, action: nil) {
                    AppValue(text: PlayLog.duration(entry.seconds), s: s, opens: false)
                }
            }
        }
    }
    private func register(_ entries: [PlayLog.Entry]) {
        guard model.page == .activity else { return }
        model.layout = entries.map { ["activity.\($0.id)"] } + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.leave() }]
        model.adjusters = [:]
        model.registered(initial: entries.first.map { "activity.\($0.id)" } ?? ConsoleAppModel.barLeft)
    }
}

struct ActivityTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var ctx: ConsoleAppContext
    var s: Double
    @ObservedObject private var log = PlayLog.shared
    private static let chinese = UILanguage.locale
    static func entries(_ log: PlayLog) -> [PlayLog.Entry] { log.entries.values.sorted { $0.seconds > $1.seconds } }
    static func title(of entry: PlayLog.Entry, games: [GameRecord]) -> String {
        games.first { $0.fileName == entry.id }?.title ?? entry.title
    }
    var body: some View {
        let entries = Self.entries(log)
        let longest = max(1, entries.first?.seconds ?? 1)
        let total = entries.reduce(0) { $0 + $1.seconds }
        let chosen = model.focus.flatMap { focus in entries.first { "activity.\($0.id)" == focus } }
        VStack(alignment: .leading, spacing: 7 * s) {
            if let entry = chosen {
                Text(Self.title(of: entry, games: ctx.games)).font(.system(size: 17 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                    Text(PlayLog.duration(entry.seconds)).font(.system(size: 22 * s, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("玩过 \(entry.sessions) 次").font(.system(size: 10 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SystemMenuStyle.tileEdge.opacity(0.35))
                        Capsule().fill(SystemMenuStyle.accent).frame(width: max(6 * s, proxy.size.width * entry.seconds / longest))
                    }
                }
                .frame(height: 7 * s)
                Text("第一次 \(entry.first.formatted(.dateTime.locale(Self.chinese).year().month().day())) · 最近 \(entry.last.formatted(.dateTime.locale(Self.chinese).month().day().hour().minute(.twoDigits)))")
                    .font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                HStack(spacing: 10 * s) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 26 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.accent)
                    VStack(alignment: .leading, spacing: 3 * s) {
                        Text("游戏记录").font(.system(size: 17 * s, weight: .bold, design: .rounded))
                        Text(entries.isEmpty ? "还没有玩过的软件" : "\(entries.count) 个软件 · 合计 \(PlayLog.duration(total))")
                            .font(.system(size: 10 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    }
                }
            }
        }
        .padding(.horizontal, 20 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
}

/// 主题: the library's paper colours; the upper screen shows the chosen one.
private struct ThemeAppPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("FoldArc.libraryTheme") private var themeID = LibraryTheme.cream.rawValue
    @AppStorage("foldarc.finish") private var finish: ShellFinish = .aqua
    @AppStorage(DeleteStyle.key) private var deleteStyle = DeleteStyle.bin.rawValue
    @AppStorage(PencilBoxLook.key) private var pencilLook = PencilBoxLook.standard.id
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            // Round 31: the console's colour is here too (it was a small icon
            // of HOME's, only in a game).
            Text("掌机").font(.system(size: AppMetrics.text(9.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                .padding(.leading, 4 * s).accessibilityAddTraits(.isHeader)
            AppRow(id: "theme.finish", title: String(localized: "机身配色"), s: s, model: model, action: { model.push(.finish) }) {
                HStack(spacing: 5 * s) {
                    FinishSwatch(finish: finish, selected: false, size: 15 * s)
                    AppValue(text: finish.name, s: s)
                }
            }
            // 11-07: the controller's styles.
            AppRow(id: "theme.skins", title: String(localized: "手柄样式"), s: s, model: model, action: { model.push(.skins) }) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "gamecontroller").font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    AppValue(text: String(localized: "竖 \(ControllerSkin.stored(.upright).title(in: .upright)) · 横 \(ControllerSkin.stored(.across).title(in: .across))"), s: s)
                }
            }
            // 11-11: what a
            // card dragged off the shelf goes into.
            Text("游戏卡").font(.system(size: AppMetrics.text(9.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                .padding(.top, 2 * s).padding(.leading, 4 * s).accessibilityAddTraits(.isHeader)
            AppRow(id: "theme.delete", title: String(localized: "删除方式"), s: s, model: model, action: { model.push(.deleteStyle) }) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "trash").font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    AppValue(text: (DeleteStyle(rawValue: deleteStyle) ?? .bin).title, s: s)
                }
            }
            // The pencil box's style and colour.
            Text("铅笔盒").font(.system(size: AppMetrics.text(9.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                .padding(.top, 2 * s).padding(.leading, 4 * s).accessibilityAddTraits(.isHeader)
            AppRow(id: "theme.pencil", title: String(localized: "款式和颜色"), s: s, model: model, action: { model.push(.pencilBox) }) {
                let look = PencilBoxLook(id: pencilLook)
                HStack(spacing: 5 * s) {
                    PencilColourSwatch(colour: look.colour, style: look.style, selected: false, size: 15 * s)
                    AppValue(text: "\(look.style.title) · \(look.colour.name)", s: s)
                }
            }
            Text("配色（游戏库和主菜单）").font(.system(size: AppMetrics.text(9.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                .padding(.top, 2 * s).padding(.leading, 4 * s).accessibilityAddTraits(.isHeader)
            ForEach(LibraryTheme.allCases) { theme in
                let selected = theme.rawValue == themeID
                AppRow(id: "theme.\(theme.rawValue)", title: theme.name, s: s, selected: selected, model: model, action: { choose(theme) }) {
                    HStack(spacing: 6 * s) {
                        ThemeSwatch(theme: theme, s: s)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12 * s))
                            .foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
                    }
                }
            }
            AppNote(text: String(localized: "这几种配色换游戏库的纸面，也换掌机屏幕上主菜单和程序的颜色（游戏库里、游戏里都是；相机、相册、游戏笔记不变）。机身配色换掌机的颜色，游戏库里的掌机和游戏里的掌机一起换。手柄样式是手柄模式、外屏上的按键怎么摆。"), s: s)
        }
    }
    private func choose(_ theme: LibraryTheme) {
        guard theme.rawValue != themeID else { return }
        withAnimation(.easeInOut(duration: 0.3)) { themeID = theme.rawValue }
        ConsoleSounds.shared.play(.select)
        model.say(String(localized: "配色换成了「\(theme.name)」"))
    }
    private func register() {
        guard model.page == .theme else { return }
        let ids = LibraryTheme.allCases.map { "theme.\($0.rawValue)" }
        model.layout = [["theme.finish"], ["theme.skins"], ["theme.delete"], ["theme.pencil"]] + ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.leave() }, "theme.finish": { model.push(.finish) },
                                              "theme.skins": { model.push(.skins) }, "theme.delete": { model.push(.deleteStyle) },
                                              "theme.pencil": { model.push(.pencilBox) }]
        for theme in LibraryTheme.allCases { handlers["theme.\(theme.rawValue)"] = { choose(theme) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "theme.\(themeID)")
    }
}

/// 主题 › 手柄样式: the controller's three styles for each way it
/// is laid — 竖着拿, 横着拿 and, on an iPhone Duo, 外屏 — each kept on its
/// own (ControllerSkin.Place's keys, as the button on the controller kept
/// them). In a game the controller round the screens takes the one chosen
/// at once; the upper screen draws the one under the cursor.
private struct SkinsAppPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(ControllerSkin.Place.upright.key) private var upright = ControllerSkin.classic.rawValue
    @AppStorage(ControllerSkin.Place.across.key) private var across = ControllerSkin.classic.rawValue
    @AppStorage(ControllerSkin.Place.cover.key) private var cover = ControllerSkin.classic.rawValue
    /// 11-07: the Duo upright — the console (掌机机身) or a style.
    @AppStorage(DuoUprightLook.key) private var duoUpright = DuoUprightLook.console
    @ObservedObject private var hinge = HingePosture.shared
    /// 外屏 only where there is one (a hinge reports: an iPhone Duo).
    static func places(duo: Bool) -> [ControllerSkin.Place] { duo ? [.upright, .across, .cover] : [.upright, .across] }
    private var duo: Bool { hinge.status != nil }
    private var places: [ControllerSkin.Place] { Self.places(duo: duo) }
    /// A place's rows: its styles; on the Duo 竖着拿 the console first.
    static func options(_ place: ControllerSkin.Place, duo: Bool) -> [String] {
        let styles = ControllerSkin.allCases.map(\.rawValue)
        return place == .upright && duo ? [DuoUprightLook.console] + styles : styles
    }
    static func title(_ option: String, in place: ControllerSkin.Place) -> String {
        if option == DuoUprightLook.console { return DuoUprightLook.title + String(localized: "（默认）") }
        return ControllerSkin(rawValue: option)?.title(in: place) ?? option
    }
    private func chosen(_ place: ControllerSkin.Place) -> String {
        switch place {
        case .upright:
            if duo { return ControllerSkin(rawValue: duoUpright)?.rawValue ?? DuoUprightLook.console }
            return (ControllerSkin(rawValue: upright) ?? .classic).rawValue
        case .across: return (ControllerSkin(rawValue: across) ?? .classic).rawValue
        case .cover: return (ControllerSkin(rawValue: cover) ?? .classic).rawValue
        }
    }
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(places, id: \.self) { place in
                Text(place.title).font(.system(size: AppMetrics.text(9.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .padding(.leading, 4 * s).padding(.top, place == places.first ? 0 : 2 * s).accessibilityAddTraits(.isHeader)
                ForEach(Self.options(place, duo: duo), id: \.self) { option in
                    let selected = chosen(place) == option
                    AppRow(id: "skins.\(place.rawValue).\(option)", title: Self.title(option, in: place), s: s, selected: selected, model: model,
                           action: { choose(option, for: place) }) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12 * s))
                            .foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
                    }
                }
            }
            AppNote(text: duo ? String(localized: "竖着拿、横着拿和外屏各选各的。竖着拿默认是掌机机身；选了别的样式，Duo 竖过来就换成那一款。上屏是光标停着的那一种，游戏里换了马上生效。")
                              : String(localized: "竖着拿、横着拿各选各的；上屏是光标停着的那一种。游戏里换了马上生效。"), s: s)
        }
    }
    private func choose(_ option: String, for place: ControllerSkin.Place) {
        guard chosen(place) != option else { return }
        switch place {
        case .upright:
            if duo {
                duoUpright = option
                // A style is 手柄模式's upright one too.
                if ControllerSkin(rawValue: option) != nil { upright = option }
            } else {
                upright = option
            }
        case .across: across = option
        case .cover: cover = option
        }
        ConsoleSounds.shared.play(.select)
        NSLog("[controller] style %@ (%@), from 主题", option, place.rawValue)
        model.say(String(localized: "\(place.title)换成了「\(Self.title(option, in: place))」"))
    }
    private func register() {
        guard model.page == .skins else { return }
        let rows = places.flatMap { place in Self.options(place, duo: duo).map { "skins.\(place.rawValue).\($0)" } }
        model.layout = rows.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for place in places {
            for option in Self.options(place, duo: duo) { handlers["skins.\(place.rawValue).\(option)"] = { choose(option, for: place) } }
        }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "skins.upright.\(chosen(.upright))")
    }
}

/// 主题 › 删除方式: what a card taken over the shelf's edge goes into — the pixel bin (the
/// default), a drain grate, a sofa's seam, an eraser, a small pair of
/// scissors, a manhole (DeleteStyle, CardShelf.swift). The upper screen
/// plays the one under the cursor (DeleteStyleTopCard).
private struct DeleteStylePage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(DeleteStyle.key) private var styleID = DeleteStyle.bin.rawValue
    private var chosen: DeleteStyle { DeleteStyle(rawValue: styleID) ?? .bin }
    static func title(_ style: DeleteStyle) -> String { style == .bin ? style.title + String(localized: "（默认）") : style.title }
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(DeleteStyle.allCases) { style in
                let selected = chosen == style
                AppRow(id: "delete.\(style.rawValue)", title: Self.title(style), s: s, selected: selected, model: model, action: { choose(style) }) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 12 * s))
                        .foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
                }
            }
            AppNote(text: String(localized: "在游戏库里按住一张游戏卡把它拿起来，朝离开掌机的方向拖出架子边缘，它就开始碎；全碎了松手就删除，几秒内可以撤销。这里选它掉进什么里。上屏演示的是光标停着的那一种。"), s: s)
        }
    }
    private func choose(_ style: DeleteStyle) {
        guard chosen != style else { return }
        styleID = style.rawValue
        ConsoleSounds.shared.play(.select)
        NSLog("[shelf] delete style %@, from 主题", style.rawValue)
        model.say(String(localized: "删除方式换成了「\(style.title)」"))
    }
    private func register() {
        guard model.page == .deleteStyle else { return }
        let rows = DeleteStyle.allCases.map { "delete.\($0.rawValue)" }
        model.layout = rows.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for style in DeleteStyle.allCases { handlers["delete.\(style.rawValue)"] = { choose(style) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "delete.\(chosen.rawValue)")
    }
}

/// 删除方式's upper screen: the way under the cursor (from 主题's row: the one
/// in use), played small over and over (DeleteStyleDemo: the shelf's own
/// drawing), with its name and what it is.
struct DeleteStyleTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(DeleteStyle.key) private var styleID = DeleteStyle.bin.rawValue
    @AppStorage("FoldArc.libraryTheme") private var themeID = LibraryTheme.cream.rawValue
    /// Renders: the demo still, this far into its loop; and whose.
    var still: Double? = nil
    var previewStyle: DeleteStyle? = nil
    private var chosen: DeleteStyle { DeleteStyle(rawValue: styleID) ?? .bin }
    private var focused: DeleteStyle {
        if let previewStyle { return previewStyle }
        if let focus = model.focus, focus.hasPrefix("delete."), let style = DeleteStyle(rawValue: String(focus.dropFirst("delete.".count))) { return style }
        return chosen
    }
    var body: some View {
        let style = focused
        HStack(spacing: 12 * s) {
            DeleteStyleDemo(style: style, theme: LibraryTheme(rawValue: themeID) ?? .cream, size: CGSize(width: 170 * s, height: 150 * s), scale: 0.5 * s, still: still)
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).strokeBorder(SystemMenuStyle.ink.opacity(0.3), lineWidth: 1))
                .id(style)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(style.title).font(.system(size: 15 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(style.blurb).font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                Text(chosen == style ? "现在用的" : "按 A 换成这个").font(.system(size: 9 * s, weight: .semibold))
                    .foregroundStyle(SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
}

/// 主题 › 铅笔盒: the four styles, each a row of its colours. The one chosen is
/// worn at once: the box opened, its lid on the cover, its icon in the
/// library; what is in it stays where it is. The upper screen draws the one
/// under the cursor (PencilLookTopCard). Each style keeps its own last colour.
private struct PencilLookPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(PencilBoxLook.key) private var lookID = PencilBoxLook.standard.id
    private var chosen: PencilBoxLook { PencilBoxLook(id: lookID) }
    static func itemID(_ look: PencilBoxLook) -> String { "pencil.\(look.id)" }
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(PencilBoxStyle.allCases) { style in
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text(style.title).font(.system(size: AppMetrics.text(8.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 2 * s) {
                        ForEach(style.colours) { colour in swatch(PencilBoxLook(style: style, colour: colour)).frame(width: 24 * s) }
                    }
                }
                .padding(.horizontal, 8 * s).padding(.vertical, 5 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SystemMenuStyle.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
            }
            AppNote(text: String(localized: "选好的马上换上：打开的铅笔盒、外屏上的盒盖、游戏库角落里的小盒子都跟着变。格子里的东西、贴在盒盖上的、夹在绑带下的照片和便条都不动。"), s: s)
        }
    }
    private func swatch(_ look: PencilBoxLook) -> some View {
        let id = Self.itemID(look)
        let selected = look == chosen
        return Button { model.focus = id; choose(look) } label: {
            PencilColourSwatch(colour: look.colour, style: look.style, selected: selected, size: 20 * s)
                .overlay { if model.focus == id { MenuCursorRing(shape: Circle(), s: s) } }
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel("\(look.style.title)：\(look.colour.name)")
        .accessibilityIdentifier("app.\(id)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func choose(_ look: PencilBoxLook) {
        guard look != chosen else { return }
        lookID = look.id
        UserDefaults.standard.set(look.colour.id, forKey: PencilBoxLook.colourKey(look.style))
        ConsoleSounds.shared.play(.select)
        NSLog("[pencil] look %@, from 主题", look.id)
        model.say(String(localized: "铅笔盒换成了「\(look.style.title) · \(look.colour.name)」"))
    }
    private func register() {
        guard model.page == .pencilBox else { return }
        var layout: [[String]] = []
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for style in PencilBoxStyle.allCases {
            let looks = style.colours.map { PencilBoxLook(style: style, colour: $0) }
            layout.append(looks.map(Self.itemID))
            for look in looks { handlers[Self.itemID(look)] = { choose(look) } }
        }
        model.layout = layout + [[ConsoleAppModel.barLeft]]
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: Self.itemID(chosen))
    }
}

/// A pencil box colour as a dot: its colour from light to deep; the plastic's
/// with a gleam, the wood's and the canvas's with a little of their grain.
struct PencilColourSwatch: View {
    var colour: PencilBoxColour
    var style: PencilBoxStyle
    var selected: Bool
    var size: Double
    var body: some View {
        let c = colour.rgb
        let light = Color(red: min(1, c.x * 0.7 + 0.3), green: min(1, c.y * 0.7 + 0.3), blue: min(1, c.z * 0.7 + 0.3))
        let deep = Color(red: c.x * 0.72, green: c.y * 0.72, blue: c.z * 0.72)
        ZStack {
            Circle().fill(LinearGradient(colors: [light, Color(red: c.x, green: c.y, blue: c.z), deep], startPoint: .topLeading, endPoint: .bottomTrailing))
            switch style {
            case .plastic: Circle().fill(Color.white.opacity(0.75)).frame(width: size * 0.22, height: size * 0.14).offset(x: -size * 0.18, y: -size * 0.22)
            case .wood:
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(deep.opacity(0.5)).frame(width: size * 0.7, height: max(0.6, size * 0.035)).offset(y: Double(i - 1) * size * 0.2)
                }
                .clipShape(Circle())
            case .canvas: Circle().strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: max(0.6, size * 0.04), dash: [size * 0.08, size * 0.06])).padding(size * 0.12)
            case .tin: EmptyView()
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(selected ? SystemMenuStyle.accent : SystemMenuStyle.ink.opacity(0.3), lineWidth: selected ? max(1.5, size * 0.1) : 1))
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(SystemMenuStyle.accent)
                    .background(Circle().fill(Color.white).padding(size * 0.04))
                    .offset(x: size * 0.12, y: size * 0.12)
            }
        }
        .padding(2)
        .accessibilityHidden(true)
    }
}

/// 铅笔盒's upper screen in 主题: the box under the cursor (from 主题's row:
/// the one worn), closed and open, with its name and what it is like.
struct PencilLookTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage(PencilBoxLook.key) private var lookID = PencilBoxLook.standard.id
    private var chosen: PencilBoxLook { PencilBoxLook(id: lookID) }
    private var focused: PencilBoxLook {
        if let focus = model.focus, focus.hasPrefix("pencil.") { return PencilBoxLook(id: String(focus.dropFirst("pencil.".count))) }
        return chosen
    }
    var body: some View {
        let look = focused
        HStack(spacing: 10 * s) {
            HStack(spacing: 5 * s) {
                picture("pencilbox-lid.jpg", look: look, height: 150 * s)
                picture("pencilbox-open.jpg", look: look, height: 150 * s)
            }
            .id(look.id)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(look.style.title).font(.system(size: 14 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(look.colour.name).font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                Text(look.style.blurb).font(.system(size: 8.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                Text(look == chosen ? String(localized: "现在用的") : String(localized: "按 A 换成这个")).font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(look == chosen ? SystemMenuStyle.go : SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
    @ViewBuilder private func picture(_ file: String, look: PencilBoxLook, height: Double) -> some View {
        if let picture = PencilImages.preview(file, look: look, height: height * 3) {
            PencilImages.image(picture).resizable().scaledToFit().frame(height: height)
                .shadow(color: SystemMenuStyle.ink.opacity(0.25), radius: 0, x: 0, y: 2 * s)
        } else {
            RoundedRectangle(cornerRadius: 6 * s).fill(SystemMenuStyle.tile).frame(width: height * 0.7, height: height)
        }
    }
}

/// 11-07: the shapes this iPhone gives the controller, for 手柄样式's previews —
/// on an iPhone Duo its inner display upright (669 × 951) and across (the
/// crease down the middle) and its cover (466 × 678); on any other iPhone
/// its own screen, both ways, with its own cut-out's room (PhoneScreen).
struct PreviewShape: Equatable {
    var size: CGSize
    var insets: EdgeInsets
    var fold: CGRect?
    @MainActor static func of(_ place: ControllerSkin.Place, duo: Bool) -> PreviewShape {
        if duo {
            switch place {
            case .upright: return PreviewShape(size: CGSize(width: 669, height: 951), insets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0), fold: nil)
            case .across: return PreviewShape(size: CGSize(width: 951, height: 669), insets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0),
                                              fold: CGRect(x: 455, y: 0, width: 41, height: 669))
            case .cover: return PreviewShape(size: CGSize(width: 466, height: 678), insets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 0), fold: nil)
            }
        }
        let phone = PhoneScreen.current
        return place == .across ? PreviewShape(size: phone.across, insets: phone.acrossInsets, fold: nil)
                                : PreviewShape(size: phone.upright, insets: phone.uprightInsets, fold: nil)
    }
}

/// This iPhone's screen (points), upright and on its side, and the room its
/// cut-out and home indicator take each way: read from the window (the
/// screen's size; the safe area as it is now, turned for the other way).
struct PhoneScreen: Equatable {
    var upright: CGSize
    var across: CGSize
    var uprightInsets: EdgeInsets
    var acrossInsets: EdgeInsets
    static let fallback = PhoneScreen(upright: CGSize(width: 390, height: 844), across: CGSize(width: 844, height: 390),
                                      uprightInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
                                      acrossInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59))
    /// From a screen of `size` and the safe area `top`/`side` now (whichever
    /// way it is held): a cut-out of more than 24 points is a notch or the
    /// Dynamic Island (with a home indicator); none, a home button.
    static func make(size: CGSize, cutout: Double) -> PhoneScreen {
        let short = min(size.width, size.height), long = max(size.width, size.height)
        guard short > 0 else { return fallback }
        if cutout > 24 {
            return PhoneScreen(upright: CGSize(width: short, height: long), across: CGSize(width: long, height: short),
                               uprightInsets: EdgeInsets(top: cutout, leading: 0, bottom: 34, trailing: 0),
                               acrossInsets: EdgeInsets(top: 0, leading: cutout, bottom: 21, trailing: cutout))
        }
        return PhoneScreen(upright: CGSize(width: short, height: long), across: CGSize(width: long, height: short),
                           uprightInsets: EdgeInsets(), acrossInsets: EdgeInsets())
    }
    @MainActor static var current: PhoneScreen {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            let i = window?.safeAreaInsets ?? .zero
            return make(size: scene.screen.bounds.size, cutout: max(i.top, i.left, i.right))
        }
        #endif
        return fallback
    }
}

/// 手柄样式's upper screen: the style under the cursor (or, from 主题, the
/// one held across now), drawn small — the controller itself at that
/// style, its screens showing the demo — with its name and what it is.
struct SkinsTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("foldarc.finish") private var finish: ShellFinish = .aqua
    @StateObject private var demo = DemoSession()
    /// An iPhone Duo (it has a hinge): its own shapes in the previews.
    @ObservedObject private var hinge = HingePosture.shared
    private var duo: Bool { hinge.status != nil }
    /// The place and the option under the cursor: a style, or (the Duo
    /// upright) the console.
    private var focused: (ControllerSkin.Place, String) {
        if let focus = model.focus, focus.hasPrefix("skins.") {
            let parts = focus.split(separator: ".").map(String.init)
            if parts.count == 3, let place = ControllerSkin.Place(rawValue: parts[1]),
               parts[2] == DuoUprightLook.console || ControllerSkin(rawValue: parts[2]) != nil { return (place, parts[2]) }
        }
        return (.across, ControllerSkin.stored(.across).rawValue)
    }
    /// What is in use there now.
    private func current(_ place: ControllerSkin.Place) -> String {
        if place == .upright, duo { return DuoUprightLook.style?.rawValue ?? DuoUprightLook.console }
        return ControllerSkin.stored(place).rawValue
    }
    var body: some View {
        let (place, option) = focused
        let skin = ControllerSkin(rawValue: option)
        HStack(spacing: 12 * s) {
            preview(place, option)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text("\(place.title) · \(skin?.title(in: place) ?? DuoUprightLook.title)").font(.system(size: 15 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(skin?.blurb(in: place) ?? DuoUprightLook.blurb).font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                Text(current(place) == option ? "现在用的" : "按 A 换成这个").font(.system(size: 9 * s, weight: .semibold))
                    .foregroundStyle(SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
    /// The controller at that style (or the console), laid as this iPhone
    /// lays it (PreviewShape), scaled down; nothing in it can be pressed.
    private func preview(_ place: ControllerSkin.Place, _ option: String) -> some View {
        let shape = PreviewShape.of(place, duo: duo)
        let size = shape.size
        let scale = min(150 * s / size.height, 230 * s / size.width)
        return Group {
            if let skin = ControllerSkin(rawValue: option) {
                ControllerModeView(session: demo, finish: finish.innerShell, outer: finish, brightness: 1, haptics: false,
                                   showHome: {}, showPower: {}, cover: place == .cover, previewFold: shape.fold, previewSkin: skin,
                                   previewInsets: shape.insets)
            } else {
                // 掌机机身: the Duo's console, its crease where the hardware's is.
                DuoConsoleView(session: demo, finish: finish.innerShell, outer: finish, haptics: false, previewGap: 41,
                               previewSnapshot: FoldRegionSnapshot.preview(size: size, axis: .horizontal, fraction: 0.5, gap: 41),
                               previewInsets: ViewportInsets(top: shape.insets.top, leading: 0, bottom: shape.insets.bottom, trailing: 0),
                               previewHalfOpen: false, showHome: {}, showHelp: {}, close: {})
            }
        }
        .environment(\.screenOverlay, nil)
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
        .clipShape(RoundedRectangle(cornerRadius: 40 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 40 * scale, style: .continuous).strokeBorder(Color.black.opacity(0.55), lineWidth: max(1, 10 * scale)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ThemeSwatch: View {
    var theme: LibraryTheme
    var s: Double
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [theme.paper, theme.paperDeep], startPoint: .top, endPoint: .bottom))
            Circle().fill(theme.accent).frame(width: 8 * s, height: 8 * s).offset(x: 5 * s, y: 5 * s)
            Circle().strokeBorder(theme.ink.opacity(0.35), lineWidth: 1)
        }
        .frame(width: 20 * s, height: 20 * s)
    }
}

/// The upper screen of 主题: the chosen (or focused) paper as the library
/// would show it, with the console's screen in its colours (11-07).
struct ThemeTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("FoldArc.libraryTheme") private var themeID = LibraryTheme.cream.rawValue
    @AppStorage("foldarc.finish") private var finish: ShellFinish = .aqua
    var body: some View {
        if model.focus == "theme.finish" {
            FinishCard(finish: finish, chosen: true, s: s)
        } else if model.focus == "theme.skins" {
            SkinsTopCard(model: model, s: s)
        } else if model.focus == "theme.delete" {
            DeleteStyleTopCard(model: model, s: s)
        } else if model.focus == "theme.pencil" {
            PencilLookTopCard(model: model, s: s)
        } else {
            themeCard
        }
    }
    @ViewBuilder private var themeCard: some View {
        let focused = model.focus.flatMap { focus in LibraryTheme.allCases.first { "theme.\($0.rawValue)" == focus } }
        let theme = focused ?? LibraryTheme(rawValue: themeID) ?? .cream
        HStack(spacing: 14 * s) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                    .fill(LinearGradient(colors: [theme.paper, theme.paperDeep], startPoint: .top, endPoint: .bottom))
                VStack(spacing: 6 * s) {
                    Text("12:00").font(.system(size: 7 * s, weight: .semibold, design: .rounded)).foregroundStyle(theme.inkSoft)
                    // 11-07: the console's screen as the menus will be in
                    // this palette (MenuPalette), in a dark bezel.
                    themeScreen(theme.menu)
                    HStack(spacing: 5 * s) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2.5 * s).fill(index == 1 ? theme.accent : theme.tile)
                                .overlay(RoundedRectangle(cornerRadius: 2.5 * s).strokeBorder(theme.tileEdge, lineWidth: 0.8))
                                .frame(width: 16 * s, height: 20 * s)
                        }
                    }
                }
                .padding(.top, 5 * s)
            }
            .frame(width: 92 * s, height: 92 * s)
            .overlay(RoundedRectangle(cornerRadius: 8 * s, style: .continuous).strokeBorder(SystemMenuStyle.ink.opacity(0.3), lineWidth: 1))
            .shadow(color: SystemMenuStyle.ink.opacity(0.25), radius: 0, y: 2 * s)
            VStack(alignment: .leading, spacing: 5 * s) {
                Text(theme.name).font(.system(size: 18 * s, weight: .bold, design: .rounded))
                Text(theme.rawValue == themeID ? "现在用的配色：游戏库和主菜单" : "按 A 换成这个配色")
                    .font(.system(size: 10 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
    /// A console screen with the menu on it: the strip, three tiles (the
    /// cursor on the first), the bar.
    private func themeScreen(_ menu: MenuPalette) -> some View {
        ZStack {
            LinearGradient(colors: [menu.paper, menu.paperDeep], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 3 * s) {
                menu.status.frame(height: 4 * s)
                HStack(spacing: 3 * s) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5 * s).fill(menu.tile)
                            .overlay(RoundedRectangle(cornerRadius: 1.5 * s)
                                .strokeBorder(index == 0 ? menu.accent : menu.tileEdge, lineWidth: index == 0 ? 1.5 * s : 0.6 * s))
                            .frame(width: 9 * s, height: 9 * s)
                    }
                }
                Spacer(minLength: 0)
                menu.bar.frame(height: 4 * s)
            }
        }
        .frame(width: 46 * s, height: 30 * s)
        .clipShape(RoundedRectangle(cornerRadius: 3 * s))
        .overlay(RoundedRectangle(cornerRadius: 3 * s).strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5 * s))
    }
}

/// 主题 › 机身配色 (round 31: it was a small icon of HOME's, only in a
/// game). The console's colour, by the family of consoles it is after; the
/// console on the stage takes it at once (LibraryMenuView), the handheld in
/// a game too. A two-tone colour is two-tone everywhere the same way: its
/// faces the second colour, its hinge, rim and back the first.
private struct FinishAppPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("foldarc.finish") private var finish: ShellFinish = .aqua
    /// The first ten are everybody's; the rest wear a small lock until Pro
    /// is open.
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        register()
        return AppScroll(model: model, s: s) {
            ForEach(ShellFinish.Family.allCases) { family in
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text(family.label).font(.system(size: AppMetrics.text(8.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .accessibilityAddTraits(.isHeader)
                    // Nine to a row, every one made (b4: a lazy grid made only
                    // the rows on the screen, so the UI test found 15 of 50).
                    Grid(alignment: .leading, horizontalSpacing: 3 * s, verticalSpacing: 3 * s) {
                        ForEach(rows(of: family), id: \.first) { row in
                            GridRow {
                                ForEach(row) { item in swatch(item).frame(width: 25 * s) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8 * s).padding(.vertical, 5 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SystemMenuStyle.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
            }
            if !pro.isPro {
                AppNote(text: String(localized: "带锁的是典藏卡带的配色：点一下先看看样子，再点一次看典藏卡带。"), s: s).accessibilityIdentifier("finish-pro-note")
            }
            AppNote(text: String(localized: "两种颜色的配色（比如「粉·白」）：面板是第二种颜色，铰链、边框和背面是第一种。想要整台一个颜色，选单色的。"), s: s)
        }
    }
    private func rows(of family: ShellFinish.Family) -> [[ShellFinish]] {
        let items = ShellFinish.finishes(in: family)
        return stride(from: 0, to: items.count, by: 9).map { Array(items[$0..<min($0 + 9, items.count)]) }
    }
    private func swatch(_ item: ShellFinish) -> some View {
        let id = "finish.\(item.rawValue)"
        let selected = item == finish
        let locked = !item.isOpen
        return Button { touch(item, id: id) } label: {
            FinishSwatch(finish: item, selected: selected, size: 21 * s)
                .overlay(alignment: .bottomTrailing) { if locked { ProLockBadge(size: 9.5 * s) } }
                .overlay { if model.focus == id { MenuCursorRing(shape: Circle(), s: s) } }
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel("机身配色：\(item.name)")
        .accessibilityValue(Text(verbatim: locked ? String(localized: "典藏卡带") : ""))
        .accessibilityIdentifier("app.\(id)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    /// A touch on a swatch. A colour only Pro has is shown first (the upper
    /// screen draws the console in it); touched again, or with A, it opens
    /// Pro's page.
    private func touch(_ item: ShellFinish, id: String) {
        if !item.isOpen, model.focus != id {
            model.focus = id
            ConsoleSounds.shared.play(.move)
            model.say(String(localized: "「\(item.name)」是典藏卡带的配色：再点一次看典藏卡带"))
            return
        }
        model.focus = id
        choose(item)
    }
    private func choose(_ item: ShellFinish) {
        guard item.isOpen else { model.push(.pro); return }
        guard item != finish else { return }
        finish = item
        ConsoleSounds.shared.play(.select)
        NSLog("[finish] %@", item.rawValue)
        model.say(String(localized: "机身换成了「\(item.name)」"))
    }
    private func register() {
        guard model.page == .finish else { return }
        var layout: [[String]] = []
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }]
        for family in ShellFinish.Family.allCases {
            let items = ShellFinish.finishes(in: family)
            layout.append(items.map { "finish.\($0.rawValue)" })
            for item in items { handlers["finish.\(item.rawValue)"] = { choose(item) } }
        }
        model.layout = layout + [[ConsoleAppModel.barLeft]]
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: "finish.\(finish.rawValue)")
    }
}

/// The upper screen of 机身配色: the colour focused (or chosen), drawn as
/// the console opened, its two colours where they go.
struct FinishTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @AppStorage("foldarc.finish") private var finish: ShellFinish = .aqua
    @ObservedObject private var pro = ProStore.shared
    var body: some View {
        let focused = model.focus.flatMap { focus in ShellFinish.allCases.first { "finish.\($0.rawValue)" == focus } }
        let shown = focused ?? finish
        FinishCard(finish: shown, chosen: shown == finish, locked: !(shown.isFree || pro.isPro), s: s)
    }
}

/// A colour of the console: the console opened in it, its name, and where
/// a two-tone colour's colours go.
struct FinishCard: View {
    var finish: ShellFinish
    var chosen: Bool
    /// Only Pro has it, and Pro is not open: A opens Pro's page.
    var locked = false
    var s: Double
    var body: some View {
        HStack(spacing: 16 * s) {
            FinishPreview(finish: finish, s: s)
            VStack(alignment: .leading, spacing: 5 * s) {
                Text(finish.name).font(.system(size: 18 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(finish.isTwoTone ? "两种颜色：面板\(finish.innerShell.name)，铰链、边框和背面是外壳色" : "单色：整台一个颜色")
                    .font(.system(size: 9.5 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(chosen ? String(localized: "掌机现在的颜色") : (locked ? String(localized: "典藏卡带的配色：按 A 看典藏卡带") : String(localized: "按 A 换成这个颜色")))
                    .font(.system(size: 9.5 * s, weight: .bold)).foregroundStyle(chosen ? SystemMenuStyle.go : SystemMenuStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
}

/// The console opened, small: the lid and the lower half in the outer
/// colour with their faces in the inner one (the upper face black on a dark
/// colour, as on the handheld), the hinge between in the outer colour.
struct FinishPreview: View {
    var finish: ShellFinish
    var s: Double
    var body: some View {
        VStack(spacing: 0) {
            half(upper: true)
            RoundedRectangle(cornerRadius: 3 * s).fill(LinearGradient(colors: [finish.light, finish.dark], startPoint: .top, endPoint: .bottom))
                .frame(width: 66 * s, height: 7 * s)
            half(upper: false)
        }
        .accessibilityHidden(true)
    }
    private func half(upper: Bool) -> some View {
        let inner = finish.innerShell
        let face: LinearGradient = upper && !inner.isLight
            ? LinearGradient(colors: [Color(white: 0.17), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [inner.light, inner.base], startPoint: .top, endPoint: .bottom)
        return ZStack {
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(LinearGradient(colors: [finish.light, finish.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 7 * s, style: .continuous).fill(face).padding(3 * s)
            RoundedRectangle(cornerRadius: 2 * s).fill(Color(white: 0.06))
                .frame(width: upper ? 44 * s : 34 * s, height: 26 * s)
        }
        .frame(width: 82 * s, height: 46 * s)
    }
}

/// 说明书: its sections, grouped; A opens one.
private struct ManualAppPage: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        register()
        var start = 0
        let groups = ManualText.groups.map { group -> (String, Int, [ManualText.Section]) in
            defer { start += group.sections.count }
            return (group.title, start, group.sections)
        }
        return AppScroll(model: model, s: s) {
            ForEach(groups, id: \.0) { title, first, sections in
                Text(title).font(.system(size: AppMetrics.text(9.5, s), weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .padding(.top, 2 * s).padding(.leading, 4 * s)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(sections.enumerated()), id: \.offset) { offset, section in
                    let index = first + offset
                    AppRow(id: "manual.\(index)", title: section.title, s: s, model: model, action: { model.push(.manualSection(index)) }) {
                        Image(systemName: "chevron.right").font(.system(size: 8 * s, weight: .bold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    }
                }
            }
        }
    }
    private func register() {
        guard model.page == .manual else { return }
        let ids = ManualText.sections.indices.map { "manual.\($0)" }
        model.layout = ids.map { [$0] } + [[ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.leave() }]
        for index in ManualText.sections.indices { handlers["manual.\(index)"] = { model.push(.manualSection(index)) } }
        model.handlers = handlers
        model.adjusters = [:]
        model.registered(initial: ids.first)
    }
}

/// One section of the manual: its text in paragraphs the cursor steps
/// through (the D-pad scrolls), L / R to the section before or after.
private struct ManualSectionPage: View {
    @ObservedObject var model: ConsoleAppModel
    var index: Int
    var s: Double
    static func paragraphs(_ text: String) -> [String] {
        // Sentences, two at a time.
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "。" || character == "；" { sentences.append(current); current = "" }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { sentences.append(current) }
        return stride(from: 0, to: sentences.count, by: 2).map { sentences[$0..<min($0 + 2, sentences.count)].joined() }
    }
    var body: some View {
        let section = ManualText.section(index)
        let parts = Self.paragraphs(section.text)
        register(parts.count)
        return AppScroll(model: model, s: s) {
            ForEach(Array(parts.enumerated()), id: \.offset) { offset, text in
                let id = "manual.p.\(offset)"
                let shape = RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                Text(text).font(.system(size: AppMetrics.text(10.5, s), weight: .medium)).foregroundStyle(SystemMenuStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8 * s).padding(.vertical, 5 * s)
                    .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
                    .contentShape(shape)
                    .onTapGesture { model.focus = id }
                    .id(id)
            }
            Text("L / R：上一节、下一节").font(.system(size: AppMetrics.text(8, s), weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                .padding(.leading, 8 * s)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("manual-text")
    }
    private func turn(_ delta: Int) {
        let next = index + delta
        guard ManualText.sections.indices.contains(next) else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        model.replace(with: .manualSection(next))
        ConsoleSounds.shared.play(.move)
    }
    private func register(_ count: Int) {
        guard model.page == .manualSection(index) else { return }
        model.layout = (0..<count).map { ["manual.p.\($0)"] } + [[ConsoleAppModel.barLeft]]
        model.handlers = [ConsoleAppModel.barLeft: { model.pop() }]
        model.adjusters = [:]
        model.pageTurner = { turn($0) }
        model.registered(initial: count > 0 ? "manual.p.0" : ConsoleAppModel.barLeft)
    }
}

/// The upper screen of 说明书: the section chosen, or the one open.
struct ManualTopCard: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    var body: some View {
        let open: Int? = { if case .manualSection(let index) = model.page { return index } else { return nil } }()
        let focused = model.focus.flatMap { focus -> Int? in
            guard focus.hasPrefix("manual."), !focus.hasPrefix("manual.p.") else { return nil }
            return Int(focus.dropFirst("manual.".count))
        }
        let index = open ?? focused
        HStack(alignment: .top, spacing: 14 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(SystemMenuStyle.tile)
                    .shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 2 * s)
                Image(systemName: index.map { ManualText.section($0).symbol } ?? "book.closed.fill")
                    .font(.system(size: 24 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.accent)
            }
            .frame(width: 58 * s, height: 58 * s)
            VStack(alignment: .leading, spacing: 5 * s) {
                if let index {
                    Text(ManualText.section(index).title).font(.system(size: 16 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    if open != nil {
                        Text("第 \(index + 1) 节，共 \(ManualText.sections.count) 节 · 十字键往下看，B 回到目录")
                            .font(.system(size: 9.5 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                    } else {
                        Text(ManualText.section(index).text).font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                            .lineLimit(6).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("说明书").font(.system(size: 16 * s, weight: .bold, design: .rounded))
                    Text("游戏库、掌机和游戏里的用法。十字键选一节，A 打开。").font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18 * s).padding(.top, 10 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-top-card")
    }
}


// MARK: - TV输出 (round 30)

/// TV输出: the console's picture on a TV. The names are 系统设置 ›
/// TV输出, and TV模式 for playing on the TV. Round 31: TV模式 is one of the play modes
/// (游玩模式); in it, with a TV connected (AirPlay screen mirroring from
/// Control Centre, or a cable), the TV shows the console's two screens big
/// (TVScreenView) and the iPhone is the controller in the hands; in the
/// other modes the TV mirrors the iPhone, as any app's. 系统设置 › TV输出
/// says whether a TV is connected and how. Where the screens go on the TV:
/// TVLayout (ConsoleSystem.swift, where the unit checks reach it).
///
/// The TV, and what the console plays for it.
@MainActor final class TVOutput: ObservableObject {
    static let shared = TVOutput()
    static let layoutKey = "foldarc.tv.layout"
    /// TV模式 is the play mode (the stored one in the library, the play
    /// view's while it is up): the TV gets the screens; else it mirrors.
    @Published private(set) var tvMode: Bool
    func setTVMode(_ on: Bool) {
        guard on != tvMode else { return }
        tvMode = on
        NSLog("[tv] TV模式 %@", on ? "on" : "off")
        #if os(iOS)
        updateAccessory()
        refresh()
        #endif
    }
    @Published var layout: TVLayout { didSet { UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey) } }
    /// b41 (选电视): the TV drawn on
    /// the TV (现代电视: none, the screens in `layout`), and an old one's 画面.
    @Published var set: TVSet {
        didSet {
            guard set != oldValue else { return }
            UserDefaults.standard.set(set.rawValue, forKey: TVSet.defaultsKey)
            NSLog("[tv] 选电视: %@", set.rawValue)
        }
    }
    @Published var look: TVLook {
        didSet {
            guard look != oldValue else { return }
            UserDefaults.standard.set(look.rawValue, forKey: TVLook.defaultsKey)
            NSLog("[tv] 画面: %@", look.rawValue)
        }
    }
    /// The TV connected now, nil without one.
    @Published private(set) var display: Display?
    struct Display: Equatable {
        /// AirPlay's name for the TV, else what kind of connection it is.
        var name: String
        var pixels: CGSize
    }
    /// Bumped when what plays changes (the weak references are not published).
    @Published private(set) var feed = 0
    /// What the console is playing (PlayView says so as it appears): the
    /// demo's session, or the core with the software's name.
    private(set) weak var demo: DemoSession?
    private(set) weak var core: AzaharSession?
    private(set) var title: String?
    private var owner: ObjectIdentifier?
    /// A play view has said what it plays (it says its own mode too).
    var attached: Bool { owner != nil }

    private init() {
        let defaults = UserDefaults.standard
        tvMode = ScreenLayout.stored == .tv
        layout = TVLayout(rawValue: defaults.string(forKey: Self.layoutKey) ?? "") ?? .stacked
        self.set = TVSet.stored
        look = TVLook.stored
        #if DEBUG
        // `--foldarc-tv-fake` (round 31): as if a TV were connected, without
        // its window (the Simulator's external display cannot be added from
        // the command line): what the iPhone shows in TV模式, and the pages.
        if ProcessInfo.processInfo.arguments.contains("--foldarc-tv-fake") {
            display = Display(name: String(localized: "调试电视"), pixels: CGSize(width: 1920, height: 1080))
        }
        #endif
    }
    /// The console now plays the demo (`demo`) or software (`core`).
    func attach(owner: AnyObject, demo: DemoSession?, core: AzaharSession?, title: String) {
        self.owner = ObjectIdentifier(owner)
        self.demo = demo
        self.core = core
        self.title = title
        feed += 1
    }
    /// The play view that attached has gone (another may have taken over).
    func detach(owner: AnyObject) {
        guard self.owner == ObjectIdentifier(owner) else { return }
        self.owner = nil
        demo = nil
        core = nil
        title = nil
        feed += 1
    }
    /// What the settings say about the TV now.
    var statusText: String {
        if let display { return "\(display.name) · \(Int(display.pixels.width))×\(Int(display.pixels.height))" }
        #if os(iOS)
        // iOS 27, the iPhone only mirrored: the system says a TV is there,
        // but no scene of ours is on it (so no size to give).
        if accessoryAvailable { return Self.connectionName() }
        #endif
        return String(localized: "没有接电视")
    }
    /// A TV is connected: its scene is ours (TV模式, or iOS 26 always), or,
    /// on iOS 27, the system says one is there while it mirrors the iPhone.
    var connected: Bool {
        #if os(iOS)
        return display != nil || accessoryAvailable
        #else
        return display != nil
        #endif
    }

    #if os(iOS)
    private weak var scene: UIWindowScene?
    private var window: UIWindow?
    // b37 (11-06): iOS 27 gives an app a scene on an external display only
    // through a scene accessory a view controller registers
    // (UISceneAccessory.externalNonInteractive(sceneConfiguration:),
    // UIViewController.registerSceneAccessory(_:), both iOS 27.0 in the
    // SDK's UISceneAccessory.h / UIViewController.h); the system decides when
    // to put it up, and the scene it connects has TVSceneDelegate. iOS 26
    // asks the app delegate instead (configurationForConnecting), which
    // stays. The registration (a UISceneAccessoryRegistration, kept untyped
    // for the iOS 26 build) is turned on for TV模式 only: off, the TV
    // mirrors the iPhone as before; its isAvailable says a TV is there.
    private var accessory: AnyObject?
    private weak var accessoryOwner: UIViewController?
    @Published private(set) var accessoryAvailable = false
    static let accessoryInfo = "foldarc.tv"
    /// The app's main view controller registers TV输出's accessory (once;
    /// again if that controller has gone).
    func registerAccessory(on controller: UIViewController) {
        guard #available(iOS 27.0, *) else { return }
        guard accessoryOwner == nil else { return }
        let configuration = UISceneConfiguration(name: "TV输出", sessionRole: .windowExternalDisplayNonInteractive)
        configuration.delegateClass = TVSceneDelegate.self
        let registration = controller.registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration, userInfo: Self.accessoryInfo))
        registration.isEnabled = tvMode
        accessory = registration
        accessoryOwner = controller
        NSLog("[tv] scene accessory registered (iOS 27): %@", tvMode ? String(localized: "on, TV模式") : "off, the TV mirrors")
    }
    /// From the owner's updateProperties, where UIKit tracks isAvailable
    /// and runs it again when it changes. Published on the next turn, not
    /// inside the pass.
    func readAccessory(from controller: UIViewController) {
        guard #available(iOS 27.0, *), controller === accessoryOwner,
              let registration = accessory as? UISceneAccessoryRegistration else { return }
        let available = registration.isAvailable
        guard available != accessoryAvailable else { return }
        Task { @MainActor in
            guard self.accessoryAvailable != available else { return }
            self.accessoryAvailable = available
            NSLog("[tv] scene accessory %@", available ? "available: a TV is connected" : "not available")
        }
    }
    private func updateAccessory() {
        guard #available(iOS 27.0, *), let registration = accessory as? UISceneAccessoryRegistration else { return }
        registration.isEnabled = tvMode
        NSLog("[tv] scene accessory %@", tvMode ? "on" : "off")
    }
    /// A TV's scene connected (TVSceneDelegate).
    func connect(_ scene: UIWindowScene) {
        // Should both ways bring a scene (iOS 27's accessory and the app
        // delegate's), the one with the console's screens on it stays.
        if let current = self.scene, current !== scene, window != nil {
            NSLog("[tv] another TV scene connected; the first one keeps the screens")
            return
        }
        self.scene = scene
        display = Display(name: Self.connectionName(), pixels: scene.screen.nativeBounds.size)
        NSLog("[tv] connected: %@", statusText)
        refresh()
    }
    func disconnect(_ scene: UIScene) {
        guard scene === self.scene else { return }
        window?.isHidden = true
        window = nil
        self.scene = nil
        display = nil
        NSLog("[tv] disconnected")
    }
    /// TV模式: the TV gets a window of its own (UIKit then stops
    /// mirroring); another mode: the window goes and the TV mirrors the
    /// iPhone again.
    private func refresh() {
        guard let scene else { return }
        if tvMode, window == nil {
            let window = UIWindow(windowScene: scene)
            window.backgroundColor = .black
            window.rootViewController = UIHostingController(rootView: TVScreenView())
            window.isHidden = false
            self.window = window
            NSLog("[tv] TV模式: the game on the TV (%@)", set == .modern ? layout.rawValue : "\(set.rawValue), \(look.rawValue)")
        } else if !tvMode, let window {
            window.isHidden = true
            self.window = nil
            NSLog("[tv] not TV模式: the TV mirrors the iPhone")
        }
    }
    /// AirPlay's name for the TV when the sound goes there too, else the kind
    /// of connection (iOS gives no name for the display itself).
    private static func connectionName() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if let airPlay = outputs.first(where: { $0.portType == .airPlay }) { return String(localized: "AirPlay：\(airPlay.portName)") }
        if outputs.contains(where: { $0.portType == .HDMI }) { return "HDMI" }
        return String(localized: "外接显示器")
    }
    #endif
}

/// What the TV shows in TV模式: the TV chosen in 选电视 (b41) with the upper
/// screen in it, or (现代电视) the console's screens big on black; in the
/// library (nothing playing) a quiet card saying so.
struct TVScreenView: View {
    @ObservedObject private var tv = TVOutput.shared
    var body: some View {
        let _ = tv.feed
        TVPicture(layout: tv.layout, set: tv.set, look: tv.look, demo: tv.demo, core: tv.core)
    }
}

/// The TV's picture for a TV, a layout and what plays (also drawn by the
/// source renderer, RenderPreview --tv-preview).
struct TVPicture: View {
    var layout: TVLayout
    var set: TVSet = .modern
    var look: TVLook = .best
    var demo: DemoSession?
    var core: AzaharSession?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if set == .modern {
                    Color.black
                    if let core {
                        TVCoreScreens(azahar: core, layout: layout, size: proxy.size)
                    } else if let demo {
                        TVDemoScreens(session: demo, layout: layout, size: proxy.size)
                    } else {
                        TVIdleScreen()
                    }
                } else {
                    // An old TV (b41): the upper screen alone in it; the
                    // lower one is on the iPhone.
                    OldTVRoom(set: set, look: look, size: proxy.size) { filter in
                        if let core {
                            TVCoreUpper(azahar: core, filter: filter)
                        } else if let demo {
                            TVDemoUpper(session: demo, filter: filter)
                        } else {
                            OldTVNoSignal(filter: filter)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// The software's upper screen alone, in an old TV (b41).
private struct TVCoreUpper: View {
    @ObservedObject var azahar: AzaharSession
    var filter: ScreenFilter
    var body: some View {
        CoreScreen(image: azahar.top, screenFilter: filter, wholePixels: false)
    }
}

/// The demo's upper screen alone, in an old TV (b41).
private struct TVDemoUpper: View {
    @ObservedObject var session: DemoSession
    var filter: ScreenFilter
    var body: some View {
        StarField(state: session.state, squareCorners: true, depth: session.depth3D)
            .screenFilter(native: ScreenPixels.upper, filter: filter)
    }
}

private struct TVCoreScreens: View {
    @ObservedObject var azahar: AzaharSession
    var layout: TVLayout
    var size: CGSize
    var body: some View {
        let frames = layout.frames(in: size)
        ZStack(alignment: .topLeading) {
            CoreScreen(image: azahar.top)
                .frame(width: frames.top.width, height: frames.top.height)
                .position(x: frames.top.midX, y: frames.top.midY)
            if let bottom = frames.bottom {
                CoreScreen(image: azahar.bottom)
                    .frame(width: bottom.width, height: bottom.height)
                    .position(x: bottom.midX, y: bottom.midY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct TVDemoScreens: View {
    @ObservedObject var session: DemoSession
    var layout: TVLayout
    var size: CGSize
    var body: some View {
        let frames = layout.frames(in: size)
        ZStack(alignment: .topLeading) {
            StarField(state: session.state, squareCorners: true, depth: session.depth3D)
                .screenFilter(native: ScreenPixels.upper)
                .frame(width: frames.top.width, height: frames.top.height)
                .position(x: frames.top.midX, y: frames.top.midY)
            if let bottom = frames.bottom {
                TouchMap(state: session.state, touch: nil, squareCorners: true, showCoordinates: session.showTouchCoordinates)
                    .screenFilter(native: ScreenPixels.lower)
                    .frame(width: bottom.width, height: bottom.height)
                    .position(x: bottom.midX, y: bottom.midY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Nothing playing: the TV says what TV模式 is waiting for.
private struct TVIdleScreen: View {
    var body: some View {
        VStack(spacing: 18) {
            MenuArcMark(size: 90, color: .white.opacity(0.85))
            Text("TV模式").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("在掌机上开启一个软件，两块屏会出现在这里")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
/// The TV's scene (AirPlay screen mirroring or a cable): UIKit asks for one
/// of the external display role when a TV connects (FoldArcAppDelegate).
@MainActor final class TVSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        if #available(iOS 27.0, *) {
            let viaAccessory = (connectionOptions.sceneAccessoryUserInfo as? String) == TVOutput.accessoryInfo
            NSLog("[tv] TV scene connecting (%@)", viaAccessory ? "iOS 27 scene accessory" : "app delegate")
        }
        TVOutput.shared.connect(windowScene)
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        TVOutput.shared.disconnect(scene)
    }
}
#endif
