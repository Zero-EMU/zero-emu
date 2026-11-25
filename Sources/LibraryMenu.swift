import SwiftUI
import Combine

// The library (rounds 18–20). One background, two things on it: the
// console as a solid on the upper screen (turned with a finger, every part
// in its place: ConsoleStage3D.swift) and the shelf of game cards on the
// lower, flicked through like album covers, the name of the middle one
// under it — nothing else. A card lifted off the shelf turns the console
// round and opens the slot; let go over the console and it goes in (and
// the console goes back to where it stood); from then on it is in the
// console, not on the shelf, until it is drawn out again from the back,
// as far as the finger takes it. The console has a menu of its own in its
// screens (round 20): the card's icon to start it with, and the console's
// functions — 设置, 导入, 游戏记录, 主题, 说明书 — which open over the shelf.
//
// On iPhone Duo the stage is the upper display and the shelf the lower; on
// one display the stage takes the upper part (side by side in landscape).

/// The library's colours: a few plain palettes in the spirit of the
/// handhelds and consoles of the 1980s and 90s (cream and burgundy, four
/// colours on grey, the green of a dot-matrix screen, indigo, charcoal).
/// FoldArc's own names and values; nothing is copied from a product.
enum LibraryTheme: String, CaseIterable, Identifiable {
    case cream, grey, pea, indigo, charcoal
    var id: Self { self }
    /// Where 主题 keeps the choice (@AppStorage).
    static let storageKey = "FoldArc.libraryTheme"
    /// The chosen one (cream until 主题 changes it).
    static var chosen: LibraryTheme {
        LibraryTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .cream
    }
    /// 11-07: the console's menus in this palette (MenuPalette).
    var menu: MenuPalette {
        switch self {
        case .cream: return .cream
        case .grey: return .grey
        case .pea: return .pea
        case .indigo: return .indigo
        case .charcoal: return .charcoal
        }
    }
    var name: String {
        switch self {
        case .cream: return String(localized: "奶油红")
        case .grey: return String(localized: "灰四色")
        case .pea: return String(localized: "豆绿")
        case .indigo: return String(localized: "靛蓝")
        case .charcoal: return String(localized: "碳黑")
        }
    }
    var isDark: Bool { self == .indigo || self == .charcoal }
    /// The console's shadow on this paper (round 24): a darker shade of the
    /// paper itself (round 19 used the ink, which on dark paper is light),
    /// deeper on dark paper.
    var shadow: Color {
        switch self {
        case .cream: return Color(red: 0.25, green: 0.19, blue: 0.13)
        case .grey: return Color(red: 0.16, green: 0.17, blue: 0.21)
        case .pea: return Color(red: 0.12, green: 0.17, blue: 0.07)
        case .indigo: return Color(red: 0.05, green: 0.05, blue: 0.17)
        case .charcoal: return Color(red: 0.02, green: 0.02, blue: 0.03)
        }
    }
    var shadowStrength: Float { isDark ? 0.62 : 0.5 }
    /// The paper, its deeper edge, the ink, the softer ink, the accent, the bar.
    var paper: Color {
        switch self {
        case .cream: return Color(red: 0.93, green: 0.89, blue: 0.80)
        case .grey: return Color(red: 0.84, green: 0.85, blue: 0.88)
        case .pea: return Color(red: 0.75, green: 0.81, blue: 0.56)
        case .indigo: return Color(red: 0.29, green: 0.31, blue: 0.62)
        case .charcoal: return Color(red: 0.20, green: 0.20, blue: 0.22)
        }
    }
    var paperDeep: Color {
        switch self {
        case .cream: return Color(red: 0.84, green: 0.78, blue: 0.64)
        case .grey: return Color(red: 0.70, green: 0.71, blue: 0.76)
        case .pea: return Color(red: 0.58, green: 0.66, blue: 0.36)
        case .indigo: return Color(red: 0.17, green: 0.18, blue: 0.42)
        case .charcoal: return Color(red: 0.10, green: 0.10, blue: 0.12)
        }
    }
    var ink: Color {
        switch self {
        case .cream: return Color(red: 0.24, green: 0.17, blue: 0.16)
        case .grey: return Color(red: 0.17, green: 0.18, blue: 0.24)
        case .pea: return Color(red: 0.09, green: 0.21, blue: 0.09)
        case .indigo: return Color(red: 0.96, green: 0.96, blue: 1.0)
        case .charcoal: return Color(red: 0.95, green: 0.95, blue: 0.95)
        }
    }
    var inkSoft: Color {
        switch self {
        case .cream: return Color(red: 0.47, green: 0.40, blue: 0.35)
        case .grey: return Color(red: 0.36, green: 0.38, blue: 0.46)
        case .pea: return Color(red: 0.25, green: 0.38, blue: 0.20)
        case .indigo: return Color(red: 0.78, green: 0.79, blue: 0.92)
        case .charcoal: return Color(red: 0.70, green: 0.70, blue: 0.74)
        }
    }
    var accent: Color {
        switch self {
        case .cream: return Color(red: 0.66, green: 0.19, blue: 0.18)
        case .grey: return Color(red: 0.85, green: 0.23, blue: 0.23)
        case .pea: return Color(red: 0.19, green: 0.39, blue: 0.19)
        case .indigo: return Color(red: 0.95, green: 0.69, blue: 0.20)
        case .charcoal: return Color(red: 0.42, green: 0.30, blue: 0.86)
        }
    }
    /// A second accent for the "go" button.
    var go: Color {
        switch self {
        case .cream: return Color(red: 0.22, green: 0.50, blue: 0.36)
        case .grey: return Color(red: 0.18, green: 0.60, blue: 0.36)
        case .pea: return Color(red: 0.15, green: 0.33, blue: 0.16)
        case .indigo: return Color(red: 0.20, green: 0.62, blue: 0.44)
        case .charcoal: return Color(red: 0.20, green: 0.60, blue: 0.40)
        }
    }
    var bar: Color {
        switch self {
        case .cream: return Color(red: 0.28, green: 0.20, blue: 0.19)
        case .grey: return Color(red: 0.19, green: 0.20, blue: 0.27)
        case .pea: return Color(red: 0.09, green: 0.22, blue: 0.10)
        case .indigo: return Color(red: 0.11, green: 0.12, blue: 0.30)
        case .charcoal: return Color(red: 0.06, green: 0.06, blue: 0.08)
        }
    }
    /// The card tiles: white paper on light themes, a lighter slate on dark.
    var tile: Color { isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.72) }
    var tileEdge: Color { isDark ? Color.white.opacity(0.22) : ink.opacity(0.18) }
}

/// One background for both screens: the paper with a soft light behind the
/// console and a faint grain, nothing drawn across the middle.
struct LibraryBackdrop: View {
    var theme: LibraryTheme
    var light: UnitPoint
    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.paper, theme.paperDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(theme.isDark ? 0.16 : 0.30), .clear], center: light, startRadius: 0, endRadius: 420)
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(theme.ink.opacity(theme.isDark ? 0.05 : 0.028)))
                    y += 4
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct LibraryMenuView: View {
    @ObservedObject var library: LibraryModel
    /// The software whose card is in the middle; nil is the built-in demo.
    @Binding var selected: GameRecord?
    var startDemo: () -> Void
    /// A game file, from its resume state or fresh.
    var launch: (URL, Bool) -> Void
    /// One of the console's built-in programs (round 23): 系统设置 from the
    /// menu's 设置, the first-time setup while the console is not set up.
    var openApp: (ConsoleApp) -> Void
    var importFiles: () -> Void
    /// LibraryView's white curtain: raised over the console's zoom when
    /// software starts (round 21: run by Core Animation, as its lift is).
    var curtain: CurtainState
    /// One of the library's functions the console's menu asked for from the
    /// handheld (round 26): opened once the library has come in.
    var openOnArrival: ConsoleHomeItem? = nil
    var arrivalOpened: () -> Void = {}

    @AppStorage("FoldArc.libraryTheme") private var themeID = LibraryTheme.cream.rawValue
    /// Round 31: 主题 › 机身配色 on the console: it takes the colour at once.
    @AppStorage("foldarc.finish") private var finishID = ShellFinish.aqua.rawValue
    /// The software whose card is in the console, kept across games and
    /// launches: the card stays in until it is taken out (round 19).
    @AppStorage("FoldArc.insertedCard") private var insertedStored = ""
    /// How far it is drawn out of the slot (0 home; round 20).
    @AppStorage("FoldArc.insertedCardOut") private var insertedOutStored = 0.0
    @StateObject private var stage: ConsoleStage
    /// How far a pinch has brought the console in (round 26): the shelf
    /// shrinks away with it; at the closest the console is gone into.
    @StateObject private var stageZoom = StageZoom()
    @ObservedObject private var battery = BatteryLight.shared
    @ObservedObject private var volume = ConsoleVolume.shared
    /// The console's system (round 23): set up or not, the stylus.
    @ObservedObject private var system = ConsoleSettings.shared
    /// Headphones: the earphones in the console's jack (round 23).
    @ObservedObject private var audio = SystemAudio.shared
    /// 金卡带: bought, its own card stands last on the shelf.
    @ObservedObject private var pro = ProStore.shared
    /// The program on the console was started from the card in it (金卡带's
    /// films): closed, the menu is on the card again.
    @ViewState private var programFromCard = false
    /// Which card is in the console (an index into `cards`), home or drawn
    /// part of the way out, and which software it is (the shelf can change
    /// under it). The card in the console is not on the shelf.
    @ViewState private var inserted: Int?
    @ViewState private var insertedID: String?
    /// When the software of the card in the console was left (its resume
    /// state), read when the card goes in and when the library comes back.
    @ViewState private var resumeDate: Date?
    /// The card in the middle of the shelf (an index into `cards`).
    @ViewState private var centre = 0
    /// The shelf's scroll, in shelf positions.
    @ViewState private var flowOffset = 0.0
    /// 11-07 (删除): the card deleted last, while 撤销 is offered.
    @ViewState private var lastCut: LibraryModel.CutGame?
    @ViewState private var lastCutTask: Task<Void, Never>?
    /// A card in the hand: lifted off the shelf, or drawn out of the console.
    @ViewState private var lifted: LiftedCard?
    /// What is chosen on the console's touch screen (its own menu).
    @ViewState private var homeSelection: ConsoleHomeItem?
    /// Round 32: one of the small icons along the top chosen instead
    /// (游戏笔记, 屏幕亮度: the row is there with no software too), the page
    /// of tiles, and the small icon a program on the console was opened from
    /// (the cursor goes back onto it).
    @ViewState private var homeShortcut: ConsoleHomeShortcut?
    @ViewState private var homePage = 0
    @ViewState private var programShortcut: ConsoleHomeShortcut?
    /// Round 30: a program of the console's own (系统设置, 相机, 游戏记录, 主题,
    /// 说明书, the first-time setup) running on the console on the stage:
    /// it lies flat and comes up big, the cards go, the program has its two
    /// screens.
    @StateObject private var program = StageProgram()
    /// Where the console's two screens are on the view while a program
    /// runs on it (nil while it moves).
    @ViewState private var programRects: ProgramRects?
    #if os(iOS)
    @ObservedObject private var appPhase = AppScenePhase.shared
    #endif
    /// Where the slot, the card's lip, the menu's tiles and buttons are on
    /// the screen (for assistive access and the UI tests; nothing is drawn).
    @ViewState private var markers = StageMarkers()
    @ViewState private var launching = false
    /// The console is coming down from filling the screen (round 24): the
    /// shelf and the names wait, and come in as it settles (before, the
    /// shelf's cards lay over the console's lower half on its way down).
    @ViewState private var arriving = true
    @ViewState private var minute = Int(Date().timeIntervalSince1970 / 60)
    @ViewState private var stageRect = CGRect.zero
    @ViewState private var lowerRect = CGRect.zero
    @ViewState private var viewSize = CGSize.zero
    @ViewState private var calloutShown = false
    @ViewState private var restoredCard = false
    /// The console's closeness when two fingers came down (round 30: the
    /// pinch is the whole library's, not only the stage's).
    @ViewState private var pinchStart: Double?
    /// Round 31: how the console stood (and how far a pinch had brought it)
    /// when a program opened on it: it goes back there when the program
    /// closes (round 30 always went back to the
    /// front, the pinch undone).
    @ViewState private var beforeProgram: (view: ConsoleView, zoom: Double)?
    /// The 3D slider as the console's settings keep it (round 30).
    @ViewState private var depthLevel = 0.0
    /// The knob named the volume a moment ago (round 26; round 29: no
    /// longer the Simulator's "use the side keys", the knob moves there).
    @ViewState private var volumeHintShown = false
    /// The charger's cable is on its way in or out (round 26), and which
    /// plug-in or plug-out that is (a newer one takes over).
    @ViewState private var chargerMoving = false
    @ViewState private var chargerStamp = 0
    /// A charger plugged in or out just before the library came: played once
    /// the console stands.
    @ViewState private var chargerReplay = false
    private static var ejected = false
    #if DEBUG
    /// `--foldarc-auto-launch` opens the card once per process (not again
    /// when the library comes back from the game).
    private static var autoLaunched = false
    /// `--foldarc-auto-camera` opens 相机 once per process (round 25).
    private static var autoCameraOpened = false
    /// `--foldarc-shelf-script`, `--foldarc-pinch-in`: once per process (round 26).
    private static var shelfScripted = false
    private static var pinchedIn = false
    /// `--foldarc-auto-program=<app>:<seconds>`: once per process (round 30).
    private static var autoProgramOpened = false
    /// `--foldarc-finish-tour`: once per process (round 31).
    private static var finishToured = false
    /// `--foldarc-mic-probe`: once per process (11-23).
    private static var micProbed = false
    #endif
    private let clock = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(library: LibraryModel, selected: Binding<GameRecord?>, startDemo: @escaping () -> Void, launch: @escaping (URL, Bool) -> Void,
         openApp: @escaping (ConsoleApp) -> Void, importFiles: @escaping () -> Void, curtain: CurtainState,
         openOnArrival: ConsoleHomeItem? = nil, arrivalOpened: @escaping () -> Void = {}) {
        self.library = library
        _selected = selected
        self.startDemo = startDemo
        self.launch = launch
        self.openApp = openApp
        self.importFiles = importFiles
        self.curtain = curtain
        self.openOnArrival = openOnArrival
        self.arrivalOpened = arrivalOpened
        let finish = ShellFinish(rawValue: UserDefaults.standard.string(forKey: "foldarc.finish") ?? "") ?? .aqua
        _stage = StateObject(wrappedValue: ConsoleStage(finish: finish))
    }

    private var theme: LibraryTheme { LibraryTheme(rawValue: themeID) ?? .cream }

    struct LiftedCard {
        var index: Int
        var point: CGPoint
        var origin: Origin
        /// Going into the slot (round 24): how wide it shows (points), and
        /// how far it has tipped over to lie down as the card in the slot
        /// does, so that the 3D card takes over where it is, as it is.
        var width: Double?
        var tilt = 0.0
        /// Off the shelf (the console turned round for it and goes back to
        /// where it stood), or out of the console's slot.
        enum Origin { case shelf(ConsoleView), console }
    }
    enum LiftPhase { case began, moved, ended }
    /// A finger drawing the card out of the console: it is clear of the
    /// slot (`out`), carried about, let go.
    enum CarryPhase { case out, moved, dropped }

    // MARK: Cards

    private var cards: [GameCardInfo] {
        var all = [GameCardInfo(title: "Orbit Garden", subtitle: String(localized: "原创演示 · 内置"), icon: nil, isDemo: true)]
        all += library.games.map { game in
            GameCardInfo(title: game.title, subtitle: game.publisher ?? game.resolvedFormat.label, icon: GameIconCache.image(named: game.iconFileName), isDemo: false)
        }
        // The 典藏卡带 owned, last: bronze, silver, gold.
        all += pro.cartridges.map { GameCardInfo.card(for: $0) }
        return all
    }
    /// The 典藏卡带 at a place on the shelf: they stand after the demo's
    /// card and the games', while their purchases are owned.
    private func cartridge(at index: Int) -> Cartridge? {
        let owned = pro.cartridges, place = index - library.games.count - 1
        return place >= 0 && place < owned.count ? owned[place] : nil
    }
    /// The cards on the shelf: all but the one in the console.
    private var shelf: [Int] { cards.indices.filter { $0 != inserted } }
    private func record(at index: Int) -> GameRecord? {
        index >= 1 && index - 1 < library.games.count ? library.games[index - 1] : nil
    }
    private func cardID(at index: Int) -> String { record(at: index)?.id ?? cartridge(at: index)?.cardID ?? "demo" }
    private func file(for record: GameRecord) -> URL {
        Storage.root.appendingPathComponent("ROMs").appendingPathComponent(record.fileName)
    }
    private func resume(at index: Int?) -> Date? {
        guard let index, let game = record(at: index), AzaharSession.isCoreAvailable else { return nil }
        return SaveStates.resumeDate(for: file(for: game))
    }

    /// What the console's menu shows.
    private var homeState: ConsoleHomeState {
        var state = ConsoleHomeState()
        state.selection = homeSelection
        state.shortcuts = ConsoleHomeShortcut.idle
        state.shortcut = homeShortcut
        state.page = homePage
        if let index = inserted, index < cards.count {
            if stage.cardInserted { state.card = cards[index] } else { state.looseTitle = cards[index].title }
            if record(at: index) != nil {
                state.resumeDate = resumeDate
                state.coreMissing = !AzaharSession.isCoreAvailable
            }
        }
        state.minute = minute
        state.battery = battery.level
        state.charging = battery.pluggedIn
        state.setupPending = !system.setupDone
        return state
    }
    /// The menu as it will be once the card `index` is home and chosen.
    private func homeState(withCard index: Int) -> ConsoleHomeState {
        var state = homeState
        state.selection = .card
        state.card = cards[index]
        state.looseTitle = nil
        state.resumeDate = resume(at: index)
        state.coreMissing = record(at: index) != nil && !AzaharSession.isCoreAvailable
        return state
    }

    /// Where the two screens and the stage are, for one size of the view.
    struct Layout: Equatable {
        var size: CGSize
        var insets: EdgeInsets
        var s: Double
        var sideBySide: Bool
        var upper: CGRect
        var lower: CGRect
        var stageArea: CGRect
        /// The display's fold (iPhone Duo), where a program's console has
        /// its hinge (round 30).
        var fold: CGRect?
        init(size: CGSize, insets: EdgeInsets, fold: CGRect?) {
            self.size = size
            self.insets = insets
            let hasFold = fold.map { $0.width >= $0.height } ?? false
            self.fold = hasFold ? fold : nil
            sideBySide = !hasFold && size.width > size.height
            s = min(1.3, (sideBySide ? size.width * 0.5 : size.width) / 420)
            if sideBySide, let crease = fold, crease.height > crease.width, crease.minX > size.width * 0.3, crease.maxX < size.width * 0.7 {
                // The iPhone Duo held across (the library turns with
                // it now): the stage and the shelf each on their own half,
                // nothing on the crease.
                upper = CGRect(x: 0, y: 0, width: crease.minX, height: size.height)
                lower = CGRect(x: crease.maxX, y: 0, width: size.width - crease.maxX, height: size.height)
            } else if sideBySide {
                upper = CGRect(x: 0, y: 0, width: size.width * 0.52, height: size.height)
                lower = CGRect(x: size.width * 0.52, y: 0, width: size.width * 0.48, height: size.height)
            } else {
                let top = hasFold ? fold!.minY : min(size.height * 0.5, size.width * 0.8 + 20 + insets.top)
                let lowerStart = hasFold ? fold!.maxY : top
                upper = CGRect(x: 0, y: 0, width: size.width, height: top)
                lower = CGRect(x: 0, y: lowerStart, width: size.width, height: size.height - lowerStart)
            }
            let stripHeight = 18 * s + insets.top
            stageArea = CGRect(x: upper.minX, y: upper.minY + stripHeight, width: upper.width, height: upper.height - stripHeight)
        }
    }

    var body: some View {
        GeometryReader { safeProxy in
            GeometryReader { proxy in
                let layout = Layout(size: proxy.size, insets: safeProxy.safeAreaInsets, fold: DeviceFoldRegions.read(proxy)?.division)
                content(layout)
                    .coordinateSpace(name: "library")
                    .onAppear {
                        viewSize = layout.size; stageRect = layout.stageArea; lowerRect = layout.lower
                        stage.viewSize = layout.size; stage.stageRect = layout.stageArea; stage.programFold = layout.fold
                    }
                    .onChange(of: layout) { _, value in
                        viewSize = value.size; stageRect = value.stageArea; lowerRect = value.lower
                        stage.viewSize = value.size; stage.stageRect = value.stageArea; stage.programFold = value.fold
                        stage.reframe()
                    }
            }
            .ignoresSafeArea()
        }
        // Round 30: on a phone the console's screens stay too small for a
        // program (as the handheld's do): it covers the display once the
        // console has come up for it.
        .overlay {
            // (铅笔盒 always: it opens over the whole display, its hinge on a Duo's fold.)
            if let app = program.app, let rects = programRects, !rects.fit || app == .tinBox {
                programFullScreen(app)
                    .ignoresSafeArea(.keyboard)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .task { await arrive() }
        .onDisappear { program.stop(); finishPendingCut() }
        #if os(iOS)
        .onChange(of: appPhase.phase) { _, phase in
            updateCameraAwake()
            // A cut stands once FoldArc leaves the screen.
            if phase == .background { finishPendingCut() }
        }
        #endif
        .onAppear {
            restoreInserted()
            syncCentre(animated: false)
            stage.setShadow(tint: theme.shadow, strength: theme.shadowStrength)
            stage.setStylus(out: system.stylusOut, animated: false)
            stage.setEarphones(audio.headphones)
            // The charger's cable as the iPhone is now (round 26); plugged in
            // or out a moment ago, while FoldArc was opening or a program was
            // up, as it was before: the change is played once the console
            // stands (arrive).
            chargerReplay = battery.takeRecentPlugChange(within: 15)
            let cableIn = chargerReplay ? !battery.pluggedIn : battery.pluggedIn
            stage.setCharger(cableIn, animated: false)
            stage.setChargeLight(chargerReplay ? cableIn : battery.charging, animated: false)
            if chargerReplay { chargerMoving = true }
            stage.chargerSeated = { seated in chargerSeated(seated) }
            stage.showHome(homeState)
            depthLevel = system.parental.restrict3D ? 0 : Stereo3D.storedSlider
            stage.showDepth(depthLevel)
        }
        // The iPhone put on its charger or taken off it while the library is
        // up (round 26): the cable comes or goes (ConsoleStage.setCharger).
        .onChange(of: battery.plugChanges) { _, _ in
            _ = battery.takeRecentPlugChange(within: 0)
            chargerChanged(battery.pluggedIn)
        }
        // Full (or charging again) with the cable in: the light follows. While
        // the cable moves, the plug seating (or leaving) sets it.
        .onChange(of: battery.charging) { _, on in if !chargerMoving { stage.setChargeLight(on, animated: true) } }
        // Headphones plugged in or out while the library is up (round 23).
        .onChange(of: audio.headphones) { _, on in
            stage.setEarphones(on)
            ConsoleSounds.shared.play(.click)
            if let point = stage.jackPoint() {
                stage.calloutPoint = point
                stage.calloutName = on ? String(localized: "耳机：插上了") : String(localized: "耳机：拔掉了")
                stage.calloutStamp += 1
            }
            refreshMarkers()
        }
        .onChange(of: homeState) { _, state in stage.showHome(state) }
        .onChange(of: homeSelection) { _, item in ConsoleHomeCursor.selection = item }
        .onChange(of: themeID) { _, _ in
            stage.setShadow(tint: theme.shadow, strength: theme.shadowStrength)
            // 11-07: the console's menu is printed in 主题's colours too.
            stage.showHome(homeState)
        }
        .onChange(of: finishID) { _, id in stage.setFinish(ShellFinish(rawValue: id) ?? .aqua) }
        .onChange(of: selected) { _, _ in syncCentre(animated: true) }
        .onChange(of: library.games.map(\.id)) { _, _ in syncCentre(animated: true) }
        // 金卡带 bought, or gone: its card comes onto the shelf, or leaves it
        // (out of the console too, if it was in).
        .onChange(of: pro.cartridges) { _, _ in syncCentre(animated: true) }
        .onChange(of: stage.settled) { _, _ in refreshMarkers() }
        .onChange(of: stage.moving) { _, moving in
            guard moving else { return }
            markers = StageMarkers()
            if programRects != nil { withAnimation(.easeOut(duration: 0.15)) { programRects = nil } }
        }
        .onChange(of: stage.cardInserted) { _, _ in refreshMarkers() }
        .onChange(of: volume.level) { _, level in stage.showVolume(level) }
        // The iPhone's volume keys (round 23): the knob says what they did,
        // every press (round 24: at an end too, where it knocks against the
        // end of its track instead of moving).
        .onChange(of: audio.keyPresses) { _, _ in
            guard !launching, let press = audio.lastPress else { return }
            if press.atLimit { stage.bumpVolume(up: press.up) }
            guard let point = stage.volumeKnobPoint() else { return }
            stage.calloutName = press.label
            stage.calloutPoint = point
            stage.calloutStamp += 1
        }
        .onChange(of: system.setupDone) { _, _ in refreshMarkers() }
        .onChange(of: centre) { _, _ in prepareCentre() }
        // Round 27: the shelf's cards rise out of the floor one after another
        // as it comes up, and sink as it goes.
        .onChange(of: shelfShown) { _, on in stage.shelf.setShown(on) }
        // The upper screen shows the time: printed ahead again (round 21).
        .onChange(of: minute) { _, _ in prepareCentre() }
        .onReceive(clock) { now in
            let value = Int(now.timeIntervalSince1970 / 60)
            if value != minute { minute = value }
        }
    }

    /// The library comes into view: the console comes down from full
    /// screen onto the stage as the curtain lifts (LibraryView).
    private func arrive() async {
        try? await Task.sleep(for: .milliseconds(100))
        // The console is there to be seen only once RealityKit has built it
        // (its screens printed with it): the curtain over a game's close
        // waits for that (round 21; before, it could lift on an empty stage).
        for _ in 0..<180 where !stage.built { try? await Task.sleep(for: .milliseconds(16)) }
        // Flat and filling the screen, as the game left it (round 24): the
        // picture of the game held over the change dissolves into this, and
        // only then does the console come down onto its stage, so the move
        // is seen whole (before, it began under the white).
        stage.placeFlat()
        // Round 32 (POWER): the software's last two
        // frames on the LCDs while the console comes down, so what shrinks
        // is the game itself; the menu dissolves in once it stands.
        let pictures = ConsoleStage.handoff
        ConsoleStage.handoff = nil
        if let pictures { stage.showPictures(top: pictures.top, bottom: pictures.bottom) }
        NotificationCenter.default.post(name: .foldArcScreenReady, object: "library")
        for _ in 0..<240 where curtain.up { try? await Task.sleep(for: .milliseconds(16)) }
        stage.settleOnStage(from: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeOut(duration: 0.45)) { arriving = false }
        }
        if pictures != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1150))
                stage.releasePictures(fade: 0.4)
            }
        }
        // The shadow comes in as the console comes down onto the paper
        // (round 24: drawn with the console now, it follows it there; round
        // 21 kept it out until the console stood, when it was drawn apart
        // and jumped as the console settled).
        stage.showShadow(true, fade: 0.8)
        stageZoom.progress = 0
        stage.shelf.setRecession(0)
        LastRun.note("library")
        prepareCentre()
        // A charger plugged in or out just before the library came: shown
        // now, as if it had happened here (round 26).
        if chargerReplay {
            chargerReplay = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1300))
                NSLog("[stage] charger changed while the library was away: shown now")
                chargerChanged(battery.pluggedIn)
            }
        }
        // Round 26: the console's menu (on the handheld) asked for one of the
        // library's functions: it opens once the console has come down.
        if let item = openOnArrival {
            arrivalOpened()
            homeSelection = item
            try? await Task.sleep(for: .milliseconds(1100))
            perform(.open)
        }
        #if DEBUG
        // `--foldarc-stage-card`: the first game's card goes in;
        // `--foldarc-stage-back`: the console turns round;
        // `--foldarc-auto-launch=<seconds>`: the card in the console opens
        // that long after (screenshots and frame measurements without a UI
        // test driving them).
        let arguments = ProcessInfo.processInfo.arguments
        // 11-23 `--foldarc-mic-probe`: the microphone tried each way once (MicProbe), what came in in the trace.
        #if os(iOS)
        if !Self.micProbed, arguments.contains("--foldarc-mic-probe") {
            Self.micProbed = true
            MicProbe.start()
        }
        #endif
        // (`--foldarc-stage-card-demo`: the demo's card.)
        if arguments.contains("--foldarc-stage-card") || arguments.contains("--foldarc-stage-card-demo") {
            try? await Task.sleep(for: .milliseconds(1200))
            // (`--foldarc-stage-card-index=<n>`: the n-th card instead.)
            let chosen = arguments.first(where: { $0.hasPrefix("--foldarc-stage-card-index=") }).flatMap { Int($0.dropFirst("--foldarc-stage-card-index=".count)) }
            let index = chosen ?? (arguments.contains("--foldarc-stage-card-demo") ? 0 : 1)
            if index < cards.count, inserted == nil {
                stage.prepareHome(homeState(withCard: index))
                inserted = index; insertedID = cardID(at: index); insertedStored = insertedID ?? ""; insertedOutStored = 0
                resumeDate = resume(at: index)
                settle(on: nil, animated: false)
                stage.insertCard(cards[index], animated: false) {}
                homeSelection = .card
            }
            NSLog("[stage] debug: card %d in (%d cards)", index, cards.count)
        }
        // `--foldarc-stage-card-flow`: the card in the middle of the shelf is
        // lifted, carried over the console and let go there, then tapped out
        // again; twice (card.lift and card.insert measured and sampled
        // without a UI test, round 21).
        if arguments.contains("--foldarc-stage-card-flow") {
            for round in 1...2 {
                try? await Task.sleep(for: .milliseconds(1500))
                let start = CGPoint(x: lowerRect.midX, y: lowerRect.minY + lowerRect.height * 0.33)
                let target = CGPoint(x: stageRect.midX, y: stageRect.midY)
                NSLog("[stage] debug: card flow %d: lift card %d", round, centre)
                lift(centre, point: start, phase: .began)
                try? await Task.sleep(for: .milliseconds(1200))
                for step in 1...24 {
                    let t = Double(step) / 24
                    lift(centre, point: CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), phase: .moved)
                    try? await Task.sleep(for: .milliseconds(16))
                }
                NSLog("[stage] debug: card flow %d: let go", round)
                lift(centre, point: target, phase: .ended)
                try? await Task.sleep(for: .milliseconds(2600))
                NSLog("[stage] debug: card flow %d: tap it out", round)
                ejectToShelf()
            }
        }
        if arguments.contains("--foldarc-stage-back") {
            try? await Task.sleep(for: .milliseconds(1300))
            NSLog("[stage] debug: back")
            stage.turnToBack()
            if inserted == nil { stage.offerSlot(true) }
        }
        // `--foldarc-stage-look=<yaw>,<tilt>,<zoom>` (round 29): the console
        // turned that way and brought that close, then left still
        // (screenshots of its detail).
        if let look = arguments.first(where: { $0.hasPrefix("--foldarc-stage-look=") }) {
            let values = look.dropFirst("--foldarc-stage-look=".count).split(separator: ",").compactMap { Double($0) }
            if values.count == 3 {
                try? await Task.sleep(for: .milliseconds(1400))
                NSLog("[stage] debug: look yaw %.0f tilt %.0f zoom %.2f", values[0], values[1], values[2])
                stage.yaw = values[0]
                stage.tilt = values[1]
                stage.zoom = min(ConsoleStageGestures.maxZoom - 0.2, max(0.55, values[2]))
                stage.applyUserPose()
                zoomed(stage.zoom)
            }
        }
        if !Self.autoLaunched, let delay = arguments.first(where: { $0.hasPrefix("--foldarc-auto-launch=") }).flatMap({ Double($0.dropFirst("--foldarc-auto-launch=".count)) }) {
            Self.autoLaunched = true
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            NSLog("[stage] debug: auto launch")
            homeSelection = .card
            if let action = homeState.bar.right { perform(action) }
        }
        // Round 26 (recordings without a UI test), once per process:
        // `--foldarc-shelf-script=<step>:<seconds>,…`: the shelf's bar
        // pressed (next, prev, start), each after its wait;
        // `--foldarc-pinch-in=<seconds>`: that long after the library came
        // in, a pinch brings the console in over 1.6 s, all the way.
        if !Self.shelfScripted, let script = arguments.first(where: { $0.hasPrefix("--foldarc-shelf-script=") }) {
            Self.shelfScripted = true
            for step in script.dropFirst("--foldarc-shelf-script=".count).split(separator: ",") {
                let parts = step.split(separator: ":")
                let wait = parts.count > 1 ? Double(parts[1]) ?? 1 : 1
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                NSLog("[stage] debug: shelf %@", String(parts[0]))
                guard let position = shelf.firstIndex(of: centre) else { continue }
                switch parts[0] {
                case "next": if position + 1 < shelf.count { tapCard(shelf[position + 1]) }
                case "prev": if position > 0 { tapCard(shelf[position - 1]) }
                case "start": quickStart(centre)
                case "tap": tapCard(centre)
                case "eject": ejectToShelf()
                default: break
                }
            }
        }
        if !Self.pinchedIn, let delay = arguments.first(where: { $0.hasPrefix("--foldarc-pinch-in=") }).flatMap({ Double($0.dropFirst("--foldarc-pinch-in=".count)) }) {
            Self.pinchedIn = true
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            NSLog("[stage] debug: pinch in")
            let begun = Date()
            while !launching {
                let t = min(1, Date().timeIntervalSince(begun) / 1.6)
                stage.zoom = 1 + (ConsoleStageGestures.maxZoom - 1) * t * t
                stage.applyUserPose()
                zoomed(stage.zoom)
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        // `--foldarc-auto-camera=<seconds>` (round 25): 相机 chosen on the
        // console's menu that long after the library came in, and opened a
        // moment later (recordings of the console coming up for it).
        if !Self.autoCameraOpened, let delay = arguments.first(where: { $0.hasPrefix("--foldarc-auto-camera=") }).flatMap({ Double($0.dropFirst("--foldarc-auto-camera=".count)) }) {
            Self.autoCameraOpened = true
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            NSLog("[stage] debug: auto camera")
            homeSelection = .camera
            try? await Task.sleep(for: .milliseconds(700))
            perform(.open)
        }
        // `--foldarc-auto-program=<app>:<seconds>[:<keys>]` (round 30): that
        // program opened on the console that long after the library came in
        // (settings, camera, activity, theme, manual, setup), then the keys
        // (a, b, x, y, l, r, up, down, left, right, start, select, home), one
        // every 0.6 s from 2.5 s after it opened (screenshots without a UI
        // test).
        if !Self.autoProgramOpened, let value = arguments.first(where: { $0.hasPrefix("--foldarc-auto-program=") }) {
            Self.autoProgramOpened = true
            let parts = value.dropFirst("--foldarc-auto-program=".count).split(separator: ":").map(String.init)
            if let app = parts.first.flatMap({ ConsoleApp(rawValue: $0) }) {
                try? await Task.sleep(for: .milliseconds(Int((parts.count > 1 ? Double(parts[1]) ?? 1 : 1) * 1000)))
                NSLog("[stage] debug: auto program %@", app.rawValue)
                openProgram(app)
                if parts.count > 2 {
                    try? await Task.sleep(for: .milliseconds(2500))
                    let names: [String: String] = ["a": "A 键", "b": "B 键", "x": "X 键", "y": "Y 键", "l": "L 肩键", "r": "R 肩键",
                                                   "start": "START 键", "select": "SELECT 键", "home": "HOME 键"]
                    for key in parts[2].split(separator: ",").map(String.init) {
                        NSLog("[stage] debug: program key %@", key)
                        switch key {
                        case "up": programKey("十字键", direction: .up)
                        case "down": programKey("十字键", direction: .down)
                        case "left": programKey("十字键", direction: .left)
                        case "right": programKey("十字键", direction: .right)
                        default: if let part = names[key] { programKey(part) }
                        }
                        try? await Task.sleep(for: .milliseconds(600))
                    }
                }
            }
        }
        // `--foldarc-finish-tour=<seconds>[:back]`: every finish on the console in turn, as 主题 ›
        // 机身配色 sets it (the stored colour; the user's is put back by the
        // probe), that long each, "[tour] <n> <finish>" logged as each comes
        // (the probe's screenshot follows); `back`: the console turned round.
        if !Self.finishToured, let value = arguments.first(where: { $0.hasPrefix("--foldarc-finish-tour=") }) {
            Self.finishToured = true
            let parts = value.dropFirst("--foldarc-finish-tour=".count).split(separator: ":").map(String.init)
            let seconds = Double(parts.first ?? "3") ?? 3
            try? await Task.sleep(for: .milliseconds(2500))
            if parts.contains("back") { stage.turnToBack(); try? await Task.sleep(for: .milliseconds(1500)) }
            for (index, finish) in ShellFinish.allCases.enumerated() {
                finishID = finish.rawValue
                NSLog("[tour] %d %@", index + 1, finish.rawValue)
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            }
            NSLog("[tour] done")
        }
        #endif
    }

    private func content(_ layout: Layout) -> some View {
        let size = layout.size, s = layout.s, stageArea = layout.stageArea, upper = layout.upper
        let light = UnitPoint(x: stageArea.midX / max(1, size.width), y: (stageArea.midY + stageArea.height * 0.1) / max(1, size.height))
        return ZStack(alignment: .topLeading) {
            // Drawn once by the GPU into its own layer (round 21: its radial
            // light was drawn by Core Graphics on the CPU, full screen, each
            // time the layers around it changed).
            LibraryBackdrop(theme: theme, light: light)
                .drawingGroup()
            // The floor the cards stand on and the studio's light behind them
            // (round 27), under the RealityView (the cards are in it).
            ShelfBackdrop(geometry: shelfGeometry(layout), theme: theme, shown: shelfShown)
                .modifier(ShelfRecedes(zoom: stageZoom, anchor: shelfAnchor(layout)))
            // The console, and its shadow on the paper (round 24: drawn by
            // RealityKit with it, ConsoleStage.shadow); the shelf's cards
            // (round 27: ConsoleStage.shelf).
            ConsoleStageView(stage: stage)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            // Round 30: with a program on it the console is the whole view's
            // (its keys anywhere on it). Round 31: brought closer by a pinch,
            // wherever it reaches too.
            let touch = consoleTouch(layout)
            stageChrome(upper: upper, stageArea: touch.area, insets: layout.insets, s: s)
                .opacity(launching || arriving ? 0 : 1)
            // Round 30: while a program runs on the console its 3D cards have
            // sunk into the floor (ConsoleStage.shelf) and their touch is off
            // (CardShelfView.active). Round 31: where the console reaches
            // over the shelf, the shelf leaves the finger to it.
            lowerScreen(layout, hole: shelfHole(touch.overShelf, layout: layout))
                .modifier(ShelfRecedes(zoom: stageZoom, anchor: shelfAnchor(layout)))
                .opacity(launching || arriving ? 0 : 1)
                .allowsHitTesting(!launching && !arriving && program.app == nil)
            // 铅笔盒, small and quiet in the shelf's lower corner; gone while
            // a program runs or the console is brought closer, and while 撤销
            // is offered along the shelf's foot (the box lay over the bar's
            // 撤销 there and took its touch).
            // (Left out of the view, not only made clear: a clear one still answered
            // the accessibility tree over 撤销.)
            let boxShown = !launching && !arriving && program.app == nil && stageZoom.progress < 0.3 && lastCut == nil
            if boxShown {
                PencilBoxCorner(s: s) { openPencilBox() }
                    .position(pencilCorner(layout))
                    .transition(.opacity)
            }
            if let app = program.app, let rects = programRects, rects.fit, app != .tinBox {
                programScreens(app, rects: rects)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .transition(.opacity)
                    .zIndex(5)
            }
            if ConsoleStage.debugDump {
                TimelineView(.animation(minimumInterval: 0.5)) { _ in
                    ForEach(Array(stage.debugPoints().enumerated()), id: \.offset) { _, item in
                        Text(item.0).font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                            .frame(width: 14, height: 14).background(Color.red, in: Circle())
                            .position(item.1)
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            }
        }
        // Round 30: two fingers anywhere bring the console closer, the shelf
        // shrinking away (round 26 had the pinch on the stage alone, the
        // upper half: a pinch about the middle of the Duo's display, where
        // the Simulator puts its two fingers, had one finger on the shelf
        // and did nothing).
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in pinch(value.magnification) }
            .onEnded { _ in
                pinchStart = nil
                settleZoom()
                // A moment later: the fingers' own drags end after it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    if pinchStart == nil { stage.shelf.pinching = false }
                }
            })
    }

    /// A pinch anywhere in the library (round 30): the console comes closer
    /// or goes back; at the closest it is gone into (`zoomed`).
    private func pinch(_ magnification: CGFloat) {
        guard stage.pose == .stage || stage.pose == .back, !launching, !arriving, lifted == nil else { return }
        if pinchStart == nil {
            pinchStart = stage.zoom
            stage.shelf.pinching = true
            if calloutShown { withAnimation(.easeIn(duration: 0.2)) { calloutShown = false } }
        }
        stage.zoom = min(ConsoleStageGestures.maxZoom, max(0.55, (pinchStart ?? 1) * Double(magnification)))
        stage.applyUserPose()
        zoomed(stage.zoom)
    }

    /// Round 31: a pinch that hardly moved the console (the shelf still
    /// all there) is undone, so the shelf keeps its whole touch.
    private func settleZoom() {
        let p = stageZoom.progress
        guard p > 0, p < 0.06, stage.pose == .stage, !launching, lifted == nil, program.app == nil else { return }
        stage.restore(ConsoleView(yaw: stage.yaw, tilt: stage.tilt, zoom: 1, pose: .stage), duration: 0.3)
        withAnimation(.easeOut(duration: 0.3)) { stageZoom.progress = 0 }
        stage.shelf.setRecession(0)
    }

    // MARK: The shelf's order

    /// The library coming back to a console that holds a card: the card is
    /// there (as far in as it was left), not on the shelf, and chosen on
    /// the console's menu, as a handheld's menu keeps its cursor on the
    /// software last played.
    private func restoreInserted() {
        guard !restoredCard else { return }
        restoredCard = true
        // `--foldarc-eject`: the UI tests start with an empty slot (once per
        // launch; the library comes back after every game).
        if ProcessInfo.processInfo.arguments.contains("--foldarc-eject"), !Self.ejected {
            Self.ejected = true
            insertedStored = ""
            insertedOutStored = 0
        }
        guard !insertedStored.isEmpty, let index = cards.indices.first(where: { cardID(at: $0) == insertedStored }) else {
            insertedStored = ""
            insertedOutStored = 0
            return
        }
        inserted = index; insertedID = insertedStored
        resumeDate = resume(at: index)
        stage.insertCard(cards[index], animated: false, out: insertedOutStored) {}
        homeSelection = .card
    }

    /// The card in the middle follows `selected` (a newly imported title is
    /// shown) and `selected` follows the card; the inserted card follows
    /// its software through imports and removals, and comes out when the
    /// software is gone.
    private func syncCentre(animated: Bool) {
        if let current = inserted {
            if let id = insertedID, let moved = cards.indices.first(where: { cardID(at: $0) == id }) {
                if moved != current { inserted = moved }
            } else {
                stage.ejectCard(animated: true)
                inserted = nil; insertedID = nil; insertedStored = ""; insertedOutStored = 0; resumeDate = nil
            }
        }
        let wanted: Int
        if let selected, let i = library.games.firstIndex(where: { $0.id == selected.id }) {
            wanted = i + 1
        } else if cartridge(at: centre) != nil {
            // A 典藏卡带's card has no record either, as the demo's has none:
            // it stays in the middle when it is there.
            wanted = centre
        } else {
            wanted = 0
        }
        settle(on: wanted, animated: animated)
    }

    /// Puts the shelf in order after it changed: the card `index` in the
    /// middle when it is on the shelf, else the card standing nearest the
    /// middle. Nothing on the shelf: the middle is the card in the console.
    private func settle(on index: Int?, animated: Bool) {
        let shelf = self.shelf
        guard !shelf.isEmpty else {
            centre = inserted ?? 0
            flowOffset = 0
            if selected?.id != record(at: centre)?.id { selected = record(at: centre) }
            return
        }
        let position: Int
        if let index, let p = shelf.firstIndex(of: index) { position = p } else { position = min(shelf.count - 1, max(0, Int(flowOffset.rounded()))) }
        centre = shelf[position]
        if flowOffset != Double(position) {
            if animated { withAnimation(.spring(duration: 0.5)) { flowOffset = Double(position) } } else { flowOffset = Double(position) }
        }
        if selected?.id != record(at: centre)?.id { selected = record(at: centre) }
    }

    /// The menu the console will show once the card in the middle is in,
    /// printed while nothing moves (an insert then only swaps pictures).
    private func prepareCentre() {
        let index = centre
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            // Once the console stands still (round 21: given up while it
            // still moved, e.g. as it came down onto the stage, so the first
            // card lifted was printed then, in the middle of the turn).
            for _ in 0..<200 where stage.busy { try? await Task.sleep(for: .milliseconds(50)) }
            guard index == centre, !stage.busy, lifted == nil, !launching, inserted != index, index < cards.count else { return }
            if !stage.isPrepared(homeState(withCard: index)) { stage.prepareHome(homeState(withCard: index)) }
            stage.prepareCard(cards[index])
        }
    }

    // MARK: The stage

    private func stageChrome(upper: CGRect, stageArea: CGRect, insets: EdgeInsets, s: Double) -> some View {
        ZStack(alignment: .topLeading) {
            LibraryStatusStrip(theme: theme, s: s)
                .padding(.top, insets.top).padding(.leading, insets.leading).padding(.trailing, insets.trailing)
                .frame(width: upper.width)
                .position(x: upper.midX, y: (18 * s + insets.top) / 2)
                .opacity(program.app == nil ? 1 : 0)
            ConsoleStageGestures(stage: stage, origin: stageArea.origin, s: s, program: program.app != nil,
                                 onTap: { point in tapStage(point) },
                                 onDoubleTap: { point in doubleTapStage(point) },
                                 onVolume: { level in setVolume(level) },
                                 onDepth: { depth in setDepth(depth) },
                                 onStick: { direction in stickPushed(direction) },
                                 onSwipe: { direction in flipHomePage(direction == .left ? 1 : -1) },
                                 onStickMove: program.app == nil ? nil : { push in
                                     program.session.setAnalog(push.map { Point(x: $0.dx, y: $0.dy) } ?? Point(x: 0, y: 0))
                                 },
                                 carry: { point, phase in carry(point, phase: phase) },
                                 pullEnded: { pullEnded() })
                .frame(width: stageArea.width, height: stageArea.height)
                .position(x: stageArea.midX, y: stageArea.midY)
                .accessibilityElement()
                // Round 30: its keys and touch screen work as the handheld's
                // (a tap named the part under the finger before).
                .accessibilityLabel(program.app == nil ? Self.stageLabel : String(localized: "掌机模型：\(program.app?.title ?? "")在它的两块屏上"))
                .accessibilityValue(stageValue)
            markerLayer(s: s)
            systemVolumeOverTheKnob
            if let name = stage.calloutName, calloutShown {
                PartCallout(theme: theme, name: name, s: s)
                    .position(x: min(max(stage.calloutPoint.x, 60 * s), stageArea.maxX - 60 * s), y: max(stageArea.minY + 16 * s, stage.calloutPoint.y - 34 * s))
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onChange(of: stage.calloutStamp) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) { calloutShown = true }
            let stamp = stage.calloutStamp
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2200))
                if stage.calloutStamp == stamp { withAnimation(.easeIn(duration: 0.3)) { calloutShown = false } }
            }
        }
    }

    /// Round 26: the iPhone's own volume slider (transparent) along the 3D
    /// knob's travel while the console faces the player and stands still:
    /// a finger on the knob moves the system volume, and the knob follows
    /// it (`volume.level`). Only where the system has the slider (a real
    /// iPhone; not the Simulator).
    @ViewBuilder private var systemVolumeOverTheKnob: some View {
        #if os(iOS)
        if SystemVolumeSlider.available, let track = markers.volumeTrack, !launching, lifted == nil, program.app == nil {
            let dx = track.loud.x - track.quiet.x, dy = track.loud.y - track.quiet.y
            let along = max(16, track.knobLength)
            SystemVolumeTrack(thumb: CGSize(width: along, height: max(14, track.knobWidth)), slop: 10)
                .frame(width: max(34, track.knobWidth + 20), height: hypot(dx, dy) + along)
                // The view's up (louder) turned onto the track, quiet to loud.
                .rotationEffect(.radians(atan2(dx, -dy)))
                .position(x: (track.quiet.x + track.loud.x) / 2, y: (track.quiet.y + track.loud.y) / 2)
                .accessibilityHidden(true)
        }
        #endif
    }

    /// The stage's name for assistive access and the UI tests (round 30).
    static let stageLabel = String(localized: "掌机模型：拖动旋转，双指缩放，按键和触摸屏可以直接按")
    private var stageValue: String {
        guard let index = inserted, index < cards.count else { return String(localized: "没有卡带") }
        return stage.cardInserted ? String(localized: "装入：\(cards[index].title)") : String(localized: "半插：\(cards[index].title)")
    }

    /// Invisible places over the console for assistive access (and the UI
    /// tests): a tap there is a tap on the console at that spot.
    @ViewBuilder private func markerLayer(s: Double) -> some View {
        if let slot = markers.slot, lifted != nil {
            marker(String(localized: "卡槽入口"), at: slot, s: s)
        }
        if let lip = markers.cardLip {
            marker(String(localized: "掌机里的卡带"), at: lip, s: s)
                .accessibilityValue(stage.titleInSlot ?? "")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { ejectToShelf() }
        }
        ForEach(ConsoleHomeLayout.items) { item in
            if let point = markers.tiles[item] {
                marker(String(localized: "主菜单：\(item.title)"), at: point, s: s)
                    .accessibilityValue(tileValue(item))
                    .accessibilityAddTraits(homeSelection == item ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { homeTap(.tile(item)) }
            }
        }
        // Round 32: the small icons along the top, and the other pages' dots.
        ForEach(ConsoleHomeShortcut.allCases) { shortcut in
            if let point = markers.shortcuts[shortcut] {
                marker(shortcut.title, at: point, s: s)
                    .accessibilityValue(shortcut.blurb)
                    .accessibilityAddTraits(homeShortcut == shortcut ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { homeTap(.shortcut(shortcut)) }
            }
        }
        ForEach(Array(markers.pages.keys.sorted()), id: \.self) { page in
            if let point = markers.pages[page] {
                marker(String(localized: "主菜单：第 \(page + 1) 页"), at: point, s: s)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { homeTap(.page(page)) }
            }
        }
        let bar = homeState.bar
        if let left = bar.left, let point = markers.left {
            marker(left.title, at: point, s: s).accessibilityAddTraits(.isButton).accessibilityAction { perform(left) }
        }
        if let right = bar.right, let point = markers.right {
            marker(right.title, at: point, s: s).accessibilityAddTraits(.isButton).accessibilityAction { perform(right) }
        }
        if let point = markers.setup {
            marker(String(localized: "主菜单：开始设置"), at: point, s: s)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { startSetup() }
        }
        if let point = markers.stylus {
            marker(String(localized: "掌机触控笔"), at: point, s: s)
                .accessibilityValue(system.stylusOut ? "拿在手里" : "插在机身里")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggleStylus(at: point) }
        }
        if let point = markers.jack {
            marker(String(localized: "掌机耳机孔"), at: point, s: s)
                .accessibilityValue(audio.headphones ? "插着耳机" : "空着")
        }
        if let point = markers.charger {
            // Round 26: the charger's port seen from behind, else the
            // charge light at the front.
            marker(String(localized: "掌机充电线"), at: point, s: s)
                .accessibilityValue(battery.pluggedIn ? (battery.charging ? "插着，正在充电" : "插着，已充满") : "没插")
        }
        if let point = markers.volume {
            // The knob on the console; dragged up and down along its track
            // (a UI test drags from here), adjustable with VoiceOver.
            marker(String(localized: "掌机音量滑块"), at: point, s: s)
                .accessibilityValue(volume.level == 0 ? "静音" : "\(Int((volume.level * 100).rounded()))%")
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 0.1 : -0.1
                    setVolume(min(1, max(0, ((volume.level + step) * 10).rounded() / 10)))
                }
        }
        if let rect = markers.mic {
            // 11-23: the MIC printed on the console: MicPointer's arrow points at it (as at MicHole's on the
            // handheld) while a program on the console listens — 金卡带's film, 相机, 麦克风测试. Nothing to touch.
            // (its box taken before it is placed: after `.position` the bounds are the whole layer's, and the
            // arrow pointed at the layer's middle, the hinge's end)
            Color.clear
                .frame(width: rect.width, height: rect.height)
                .transformAnchorPreference(key: MicHoleAnchorKey.self, value: .bounds) { $0.holes.append($1) }
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        if let point = markers.depth {
            // Round 30: the 3D slider, dragged like the volume's.
            marker(String(localized: "掌机 3D 滑块"), at: point, s: s)
                .accessibilityValue(depthLevel == 0 ? "关" : "\(Int((depthLevel * 100).rounded()))%")
                .accessibilityAdjustableAction { direction in
                    setDepth(min(1, max(0, depthLevel + (direction == .increment ? 0.1 : -0.1))))
                }
        }
        if program.app != nil {
            // Round 30: a program on the console: its keys work it, HOME
            // and POWER close it.
            ForEach(Self.programParts + Self.padArms.map(\.0), id: \.self) { part in
                if let point = markers.keys[part] {
                    marker(Self.keyLabel(part, program: program.app), at: point, s: s)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { programTap(part) }
                }
            }
        } else {
            ForEach(Self.idleKeys, id: \.self) { part in
                if let point = markers.keys[part] {
                    marker(String(localized: "掌机按键：\(shownName(part))"), at: point, s: s)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            switch part {
                            case "A 键": homeConfirm()
                            case "电源键": powerOn()
                            default: homeBack()
                            }
                        }
                }
            }
        }
        // L and R, seen from behind (round 25): they open the camera.
        ForEach(["L 肩键", "R 肩键"], id: \.self) { part in
            if program.app == nil, let point = markers.keys[part] {
                marker(String(localized: "掌机按键：\(shownName(part))"), at: point, s: s)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { shoulder(part, at: point) }
            }
        }
    }
    private func marker(_ label: String, at point: CGPoint, s: Double) -> some View {
        Rectangle().fill(Color.white.opacity(0.001)).frame(width: 30 * s, height: 30 * s)
            .position(point)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
    private func tileValue(_ item: ConsoleHomeItem) -> String {
        guard item == .card else { return item.blurb }
        guard let index = inserted, index < cards.count else { return String(localized: "没有卡带") }
        return stage.cardInserted ? cards[index].title : String(localized: "没插到底：\(cards[index].title)")
    }

    /// The markers follow the console; while it moves they are hidden and
    /// read again once it has settled.
    private func refreshMarkers() {
        guard !stage.moving else { return }
        if program.app != nil {
            // A program on the console: its keys, and where its screens are.
            var next = StageMarkers()
            if stage.pose == .program {
                for part in Self.programParts { next.keys[part] = stage.keyPoint(part) }
                for (name, dx, dz) in Self.padArms { next.keys[name] = stage.keyPoint("十字键", dx: dx, dz: dz) }
                next.volume = stage.volumeKnobPoint()
                next.volumeTrack = stage.volumeTrack()
                next.depth = stage.depthKnobPoint()
                next.mic = stage.micRect()
            }
            if next != markers { markers = next }
            if let rects = stage.screenRects() {
                let value = ProgramRects(upper: rects.upper, lower: rects.lower, fit: rects.lower.width >= HomeMenuModel.minimumScreenWidth)
                if programRects != value { withAnimation(.easeOut(duration: 0.25)) { programRects = value } }
            }
            return
        }
        var next = StageMarkers()
        next.slot = lifted != nil ? stage.slotPoint() : nil
        next.cardLip = stage.titleInSlot != nil && stage.rearVisible ? stage.cardPoint() : nil
        next.stylus = stage.rearVisible ? stage.stylusPoint() : nil
        next.jack = stage.rearVisible ? nil : stage.jackPoint()
        next.charger = launching ? nil : (stage.rearVisible ? stage.chargerPortPoint() : stage.chargeLightPoint())
        if stage.rearVisible, !launching {
            for part in ["L 肩键", "R 肩键"] { next.keys[part] = stage.keyPoint(part) }
        }
        if stage.lowerScreenFacing, !launching, !system.setupDone {
            let button = ConsoleHomeLayout.setupButton
            next.setup = stage.lowerScreenPoint(art: CGPoint(x: button.midX, y: button.midY))
            for part in Self.idleKeys { next.keys[part] = stage.keyPoint(part) }
            next.volume = stage.volumeKnobPoint()
            next.volumeTrack = stage.volumeTrack()
            next.depth = stage.depthKnobPoint()
        } else if stage.lowerScreenFacing, !launching {
            let row = ConsoleHomeShortcut.idle
            for item in ConsoleHomeLayout.items(onHandheld: false, page: homePage) {
                let rect = ConsoleHomeLayout.tile(item, shortcuts: !row.isEmpty)
                next.tiles[item] = stage.lowerScreenPoint(art: CGPoint(x: rect.midX, y: rect.midY - 8))
            }
            for (index, shortcut) in row.enumerated() {
                let rect = ConsoleHomeLayout.shortcut(index, of: row.count)
                next.shortcuts[shortcut] = stage.lowerScreenPoint(art: CGPoint(x: rect.midX, y: rect.midY))
            }
            let pages = ConsoleHomeLayout.pageCount(onHandheld: false)
            if pages > 1 {
                for page in 0..<pages where page != homePage {
                    let dot = ConsoleHomeLayout.pageDot(page, of: pages)
                    next.pages[page] = stage.lowerScreenPoint(art: CGPoint(x: dot.midX, y: dot.midY))
                }
            }
            next.left = stage.lowerScreenPoint(art: CGPoint(x: ConsoleHomeLayout.leftButton.midX, y: ConsoleHomeLayout.leftButton.midY))
            next.right = stage.lowerScreenPoint(art: CGPoint(x: ConsoleHomeLayout.rightButton.midX, y: ConsoleHomeLayout.rightButton.midY))
            for part in Self.idleKeys { next.keys[part] = stage.keyPoint(part) }
            next.volume = stage.volumeKnobPoint()
            next.volumeTrack = stage.volumeTrack()
            next.depth = stage.depthKnobPoint()
            #if DEBUG
            if next != markers, let notes = next.shortcuts[.notes], let album = next.tiles[.album] {
                // Round 32 (b17): where the small icon and a tile are put, and
                // when (888/891/892: a tap on the small icon landed above the
                // touch screen).
                NSLog("[stage] debug: markers placed: 游戏笔记 (%.0f,%.0f) 相册 (%.0f,%.0f) zoom %.2f moving %d", notes.x, notes.y, album.x, album.y, stageZoom.progress, stage.moving ? 1 : 0)
            }
            #endif
        }
        if next != markers { markers = next }
    }

    // MARK: The console's menu

    /// A tap on the console: on its touch screen the menu answers; A, B,
    /// HOME and the D-pad work the menu as they would on the handheld; the
    /// card in the slot comes out; the other keys go down and come back up
    /// with a click, as keys with nothing to do on a menu do. Round 30: no
    /// name over the finger any more ("机身下半" and the like).
    /// How close to a small icon's marker a tap that missed the screen
    /// still counts as the icon (895: the tap came 22 points from it).
    private let markerReach = 44.0
    /// Round 32 (b18/b19): a tap that misses the touch screen but is close
    /// to a small icon's marker is that icon. The small icons sit along the
    /// screen's top edge, where the stage's ray test lands on the shell
    /// instead (888–893: a tap at 游戏笔记's marker hit 机身下半, 37 units
    /// above the screen); the markers are where the icons are drawn. (b18
    /// let the markers go first for every tap — the page dots then took
    /// the tiles' taps: 894.)
    private func markerHit(near point: CGPoint) -> ConsoleHomeLayout.Hit? {
        guard program.app == nil, !launching, stage.lowerScreenFacing, !stage.moving else { return nil }
        var best: (hit: ConsoleHomeLayout.Hit, distance: CGFloat)?
        func consider(_ hit: ConsoleHomeLayout.Hit, _ at: CGPoint?) {
            guard let at else { return }
            let d = hypot(at.x - point.x, at.y - point.y)
            #if DEBUG
            NSLog("[stage] debug: tap (%.0f,%.0f) is %.0f from %@ (%.0f,%.0f)", point.x, point.y, d, String(describing: hit), at.x, at.y)
            #endif
            if d <= markerReach, d < (best?.distance ?? .infinity) { best = (hit, d) }
        }
        for (shortcut, at) in markers.shortcuts { consider(.shortcut(shortcut), at) }
        return best?.hit
    }
    private func tapStage(_ point: CGPoint) {
        guard !launching, lifted == nil else { return }
        let touch = stage.touch(at: point)
        if touch?.screenPoint == nil, let hit = markerHit(near: point) {
            // Not the screen under the finger (the shell by its top edge),
            // but a small icon's marker is right there.
            #if DEBUG
            NSLog("[stage] debug: tap (%.0f,%.0f) on %@ taken as the marker %@", point.x, point.y, touch?.part ?? "-", String(describing: hit))
            #endif
            homeTap(hit)
            return
        }
        #if DEBUG
        NSLog("[stage] tap (%.0f,%.0f) part %@", point.x, point.y, touch?.part ?? "-")
        if let notes = markers.shortcuts[.notes], let album = markers.tiles[.album] {
            NSLog("[stage] debug: markers now: 游戏笔记 (%.0f,%.0f) 相册 (%.0f,%.0f) zoom %.2f", notes.x, notes.y, album.x, album.y, stageZoom.progress)
        }
        #endif
        if program.app != nil {
            // The program's screens take their own touches; the keys round
            // them are the program's.
            if let touch { programKey(touch.part, direction: touch.direction) }
            return
        }
        if let touch, let spot = touch.screenPoint, stage.lowerScreenFacing {
            if let hit = ConsoleHomeLayout.hit(spot, state: homeState) { homeTap(hit) }
            return
        }
        // POWER is small (on a phone a few points across): a tap on the body
        // right by it is its own (1220: its marker's tap met the body 16
        // points from the key's top).
        if touch?.part != "电源键", stage.lowerScreenFacing, let key = stage.keyPoint("电源键"),
           hypot(key.x - point.x, key.y - point.y) <= Self.powerReach {
            #if DEBUG
            NSLog("[stage] debug: tap (%.0f,%.0f) on %@ taken as POWER (%.0f,%.0f)", point.x, point.y, touch?.part ?? "-", key.x, key.y)
            #endif
            stage.press("电源键"); powerOn()
            return
        }
        switch touch?.part {
        case "A 键"?:
            stage.press("A 键"); homeConfirm()
        case "B 键"?:
            stage.press("B 键"); homeBack()
        case "HOME 键"?:
            stage.press("HOME 键"); homeBack()
        case "电源键"?:
            stage.press("电源键"); powerOn()
        case "十字键"?:
            stage.press("十字键")
            if let direction = touch?.direction { homeMove(direction) }
        case "L 肩键"?, "R 肩键"?:
            shoulder(touch?.part ?? "L 肩键", at: point)
        case "触控笔"?:
            toggleStylus(at: point)
        default:
            if let part = touch?.part, part.hasPrefix("游戏卡") { ejectToShelf(); return }
            // Beside the console, or a part that is not a key: nothing (two
            // taps there: doubleTapStage).
            guard let part = touch?.part, Self.plainKeys.contains(part) else { return }
            stage.press(part)
            ConsoleSounds.shared.play(.click)
            ConsoleHaptics.shared.play(part == "C 摇杆" ? .smallButton : .faceButton, .press)
        }
    }
    /// A tap in the shelf's area that met no card. Where the stage ends and
    /// the shelf begins the console can stand a little over the line (the
    /// iPhone Duo held across, the console turned round: its L key is a few
    /// points inside the shelf's half, and a tap on it was the shelf's and
    /// came to nothing): with a key of the console under it, the tap is the
    /// console's.
    private func tapBesideCards(_ point: CGPoint) {
        guard !launching, lifted == nil, program.app == nil, let part = stage.touch(at: point)?.part, Self.shelfSideKeys.contains(part) else { return }
        NSLog("[stage] a tap in the shelf's area (%.0f,%.0f) is on %@: the console's", point.x, point.y, part)
        tapStage(point)
    }
    private static let shelfSideKeys: Set<String> = ["A 键", "B 键", "X 键", "Y 键", "HOME 键", "START 键", "SELECT 键", "电源键", "L 肩键", "R 肩键", "十字键", "C 摇杆", "触控笔"]
    /// Keys that have nothing to do on the menu (as on the handheld's): they
    /// only go down and come back up.
    private static let plainKeys: Set<String> = ["X 键", "Y 键", "START 键", "SELECT 键", "C 摇杆"]
    /// The Circle Pad pushed (round 30): the menu's cursor moves, as the
    /// D-pad moves it.
    private func stickPushed(_ direction: ConsoleDirection) {
        guard !launching, lifted == nil, stage.lowerScreenFacing else { return }
        if program.app != nil { programKey("滑动摇杆", direction: direction); return }
        homeMove(direction)
    }
    /// The keys of the console a program can use, and the D-pad's arms
    /// (for assistive access and the UI tests).
    static let programParts = ["A 键", "B 键", "X 键", "Y 键", "HOME 键", "START 键", "SELECT 键", "电源键", "L 肩键", "R 肩键"]
    static let padArms: [(String, Float, Float)] = [("十字键上", 0, -30), ("十字键下", 0, 30), ("十字键左", -30, 0), ("十字键右", 30, 0)]
    static func keyLabel(_ part: String, program: ConsoleApp?) -> String {
        if part == "HOME 键", let program { return String(localized: "HOME 退出\(program.title)") }
        return String(localized: "掌机按键：\(shownName(part))")
    }
    /// A key of the console tapped by assistive access while a program runs.
    private func programTap(_ part: String) {
        switch part {
        case "十字键上": programKey("十字键", direction: .up)
        case "十字键下": programKey("十字键", direction: .down)
        case "十字键左": programKey("十字键", direction: .left)
        case "十字键右": programKey("十字键", direction: .right)
        default: programKey(part)
        }
    }
    /// L or R on the console (round 25): as on the handheld's menu, either
    /// opens the camera; before the console is set up, or with one of the
    /// pages over the shelf, the key only goes down (round 30: no name over
    /// the finger).
    private func shoulder(_ part: String, at point: CGPoint) {
        guard !launching, lifted == nil else { return }
        stage.press(part)
        ConsoleHaptics.shared.play(.shoulder, .press)
        if system.setupDone, program.app == nil {
            homeSelection = .camera
            perform(.open)
        }
    }
    /// The iPhone put on its charger or taken off it while the library is up
    /// (round 26). With the console standing at the front and nothing going
    /// on, it turns round so that the port can be seen, the cable comes along
    /// the table and its plug goes in (or comes out and the cable is drawn
    /// away), and it turns back; else the cable moves where the console is.
    private func chargerChanged(_ plugged: Bool) {
        chargerMoving = true
        let turn = !launching && lifted == nil && program.app == nil && !stage.moving && stage.pose == .stage && !stage.rearVisible && stage.built
        NSLog("[stage] charger %@%@", plugged ? "in" : "out", turn ? " (the console turns to show it)" : "")
        let stamp = chargerStamp + 1
        chargerStamp = stamp
        guard turn else {
            stage.setCharger(plugged, animated: true)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                if chargerStamp == stamp { chargerMoving = false; stage.setChargeLight(battery.charging, animated: true) }
            }
            return
        }
        let saved = stage.view
        withAnimation(.easeIn(duration: 0.2)) { calloutShown = false }
        stage.turnToBack()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard chargerStamp == stamp else { return }
            stage.setCharger(plugged, animated: true)
            // In: along the table 0.85 s, into the port 0.5 s; out the other way.
            try? await Task.sleep(for: .milliseconds(plugged ? 1700 : 1650))
            guard chargerStamp == stamp else { return }
            // Back to where it stood, unless the player has taken it meanwhile.
            if stage.pose == .back, lifted == nil, !launching { stage.restore(saved) }
            chargerMoving = false
            stage.setChargeLight(battery.charging, animated: true)
        }
    }
    /// The plug went into the port (or came out of it): a click, the charge
    /// light. (No words over it any more.)
    private func chargerSeated(_ seated: Bool) {
        ConsoleHaptics.shared.play(seated ? .lidShut : .hingeDetent, seated ? .press : .release)
        ConsoleSounds.shared.play(.click)
        stage.setChargeLight(seated && battery.charging, animated: true)
        refreshMarkers()
    }
    /// The stylus (round 23): a tap draws it out of its hole into the hand
    /// (a touch on the handheld's lower screen then shows its tip), another
    /// puts it back.
    private func toggleStylus(at point: CGPoint) {
        let out = !system.stylusOut
        system.stylusOut = out
        stage.setStylus(out: out, animated: true)
        ConsoleHaptics.shared.play(.hingeDetent, out ? .release : .press)
        ConsoleSounds.shared.play(.click)
    }

    /// Two taps in a row beside the console, or on a part that does
    /// nothing: back to the front, where it stands. On the touch screen and
    /// the keys the second tap is one more tap (a quick second tap reaches
    /// only this gesture, not the single tap's: 10-30 log).
    private func doubleTapStage(_ point: CGPoint) {
        guard !launching, lifted == nil else { return }
        // A program on the console: the second tap is one more press.
        if program.app != nil { tapStage(point); return }
        let touch = stage.touch(at: point)
        #if DEBUG
        NSLog("[stage] double tap (%.0f,%.0f) part %@", point.x, point.y, touch?.part ?? "-")
        #endif
        if let touch {
            if (touch.screenPoint != nil && stage.lowerScreenFacing)
                || ["A 键", "B 键", "HOME 键", "电源键", "十字键"].contains(touch.part) || touch.part.hasPrefix("游戏卡") {
                tapStage(point)
                return
            }
        }
        withAnimation(.easeIn(duration: 0.2)) { calloutShown = false }
        stage.resetView()
        // The shelf comes back as the console goes back (round 26).
        withAnimation(.easeOut(duration: 0.6)) { stageZoom.progress = 0 }
        stage.shelf.setRecession(0)
    }

    /// A pinch on the console (round 26): the closer it comes, the smaller
    /// the shelf of cards below it, until it is gone; at the closest the
    /// console is gone into (`enterConsole`).
    private func zoomed(_ zoom: Double) {
        guard stage.pose == .stage, !launching, lifted == nil else { return }
        let progress = min(1, max(0, (zoom - 1) / (ConsoleStageGestures.maxZoom - 1)))
        if abs(stageZoom.progress - progress) > 0.003 || ((progress == 0 || progress == 1) && stageZoom.progress != progress) {
            stageZoom.progress = progress
            stage.shelf.setRecession(progress)
        }
        if progress >= 1 { enterConsole() }
    }
    /// Into the console: it comes up to fill the screen, as for software,
    /// and its menu is there on the handheld at full size (ConsoleApp.home);
    /// a console not set up yet starts its first-time setup instead.
    private func enterConsole(by way: String = "pinched all the way in") {
        guard !launching, lifted == nil else { return }
        NSLog("[stage] %@: into the console", way)
        ConsoleHaptics.shared.play(.hingeDetent, .press)
        guard system.setupDone else { startSetup(); return }
        ConsoleHomeCursor.selection = homeSelection ?? (inserted != nil ? .card : nil)
        beginLaunch(label: "home") { openApp(.home) }
    }
    /// The keys of the console on its stage that work its menu, and POWER.
    private static let idleKeys = ["A 键", "B 键", "HOME 键", "电源键"]
    /// How far from POWER's top a tap on the body is still POWER's (points).
    private static let powerReach: CGFloat = 24
    /// POWER on the console on its stage (11-14): it is switched on, as a
    /// real one is. A game's card all the way in (or the demo's) starts,
    /// where it was left (as POWER left it, saved); with no card, one not
    /// pushed in or a 典藏卡带's, the console comes up to fill the screen
    /// with its menu at full size (as a pinch all the way in brings it):
    /// 相机, 相册 and the rest open there, full size, with no software; HOME
    /// in one is the menu again; POWER there puts the console back.
    private func powerOn() {
        guard !launching, lifted == nil, program.app == nil else { return }
        ConsoleSounds.shared.play(.click)
        ConsoleHaptics.shared.play(.smallButton, .press)
        guard system.setupDone else { startSetup(); return }
        if let index = inserted, stage.cardInserted, index < cards.count, cartridge(at: index) == nil {
            NSLog("[stage] POWER: the card in the console starts")
            homeSelection = .card
            ConsoleHomeCursor.selection = homeSelection
            openCard(.resume)
            return
        }
        enterConsole(by: "POWER with no card to start")
    }

    /// The console's volume slider, dragged on the 3D console (round 21):
    /// a notch every tenth and a tick at the new volume, its name and level
    /// over the knob.
    private func setVolume(_ level: Double) {
        let volume = ConsoleVolume.shared
        // Round 26: on a real iPhone the knob is the iPhone's volume, and a
        // finger on it holds the system's slider (systemVolumeOverTheKnob);
        // a drag that reaches the console instead (the slider not laid over
        // the knob just then) names the volume. Round 29: everywhere else
        // (the Simulator has no system slider; it said "use the side keys"
        // and the knob would not move) the knob is FoldArc's own volume and
        // the finger moves it, below.
        if volume.followsSystem {
            guard !volumeHintShown else { return }
            volumeHintShown = true
            ConsoleHaptics.shared.play(.sliderStop, .press)
            stage.calloutName = volumeName
            stage.calloutPoint = stage.volumeKnobPoint() ?? stage.calloutPoint
            stage.calloutStamp += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                volumeHintShown = false
            }
            return
        }
        guard level != volume.level else { return }
        if Int((level * 10).rounded(.down)) != Int((volume.level * 10).rounded(.down)) || level == 0 {
            ConsoleHaptics.shared.play(level == 0 ? .sliderStop : .sliderNotch, .press)
        }
        volume.level = level
        ConsoleSounds.shared.play(.tick)
        stage.calloutName = volumeName
        stage.calloutPoint = stage.volumeKnobPoint() ?? stage.calloutPoint
        stage.calloutStamp += 1
    }
    private var volumeName: String {
        let level = ConsoleVolume.shared.level
        return level == 0 ? String(localized: "音量 静音") : String(localized: "音量 \(Int((level * 100).rounded()))%")
    }
    /// The 3D slider dragged on the 3D console (round 30): the console's 3D
    /// setting (what a game gets as its 3D slider), in its ten steps, a
    /// notch each; held at OFF while parental controls restrict 3D.
    private func setDepth(_ value: Double) {
        let wanted = system.parental.restrict3D ? 0 : value
        let stepped = Double(Stereo3D.percent(slider: wanted)) / 100
        guard stepped != depthLevel else {
            if system.parental.restrict3D, value > 0 { ConsoleHaptics.shared.play(.sliderStop, .press) }
            return
        }
        ConsoleHaptics.shared.play(stepped == 0 || stepped == 1 ? .sliderStop : .sliderNotch, .press)
        ConsoleSounds.shared.play(.tick)
        depthLevel = stepped
        UserDefaults.standard.set(stepped, forKey: Stereo3D.defaultsKey)
        stage.showDepth(stepped)
        // A program on the console reads its slider (系统设置 › 3D 画面).
        program.session.setDepth3D(stepped)
    }

    private func homeTap(_ hit: ConsoleHomeLayout.Hit) {
        switch hit {
        case .tile(let item):
            if homeSelection == item { homeConfirm() } else { choose(item) }
        case .bar(let action):
            perform(action)
        case .setup:
            startSetup()
        case .shortcut(let shortcut):
            // Round 32: the small icons open at the first touch.
            useShortcut(shortcut)
        case .page(let page):
            turnHomePage(to: page)
        }
    }
    /// Round 32: 游戏笔记 and 屏幕亮度 along the top (the library's console has
    /// no software to save or load).
    private func useShortcut(_ shortcut: ConsoleHomeShortcut) {
        guard system.setupDone else { startSetup(); return }
        homeShortcut = shortcut
        homeSelection = nil
        switch shortcut {
        case .notes: programShortcut = .notes; openProgram(.notes)
        case .pencilBox: programShortcut = .pencilBox; openProgram(.tinBox)
        case .brightness: programShortcut = .brightness; openProgram(.settings, page: .brightness)
        case .filter: programShortcut = .filter; openProgram(.settings, page: .filter)
        case .save, .load, .keyTaps, .speed, .slots: ConsoleHaptics.shared.play(.sliderStop, .press)
        }
    }
    /// 铅笔盒 from its corner of the library.
    private func openPencilBox() {
        guard system.setupDone else { startSetup(); return }
        guard !launching, lifted == nil, program.app == nil else { return }
        ConsoleSounds.shared.play(.select)
        programShortcut = nil
        openProgram(.tinBox)
    }
    /// Where the corner's box lies: the lower right of the shelf's half,
    /// clear of the home indicator.
    private func pencilCorner(_ layout: Layout) -> CGPoint {
        CGPoint(x: layout.lower.maxX - layout.insets.trailing - 46 * layout.s,
                y: layout.lower.maxY - max(layout.insets.bottom, 6) - 26 * layout.s)
    }
    /// Round 32: the page of tiles turned (a swipe over the touch screen, a
    /// dot touched, the D-pad past a row's end).
    private func flipHomePage(_ delta: Int) { turnHomePage(to: homePage + delta) }
    private func turnHomePage(to next: Int) {
        guard program.app == nil, !launching, system.setupDone else { return }
        let pages = ConsoleHomeLayout.pageCount(onHandheld: false)
        let target = max(0, min(pages - 1, next))
        guard target != homePage else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        homePage = target
        homeShortcut = nil
        homeSelection = ConsoleHomeLayout.landing(on: target, from: homeSelection, onHandheld: false)
        ConsoleHaptics.shared.play(.smallButton, .press)
        ConsoleSounds.shared.play(.move)
        NSLog("[stage] home page %d", target + 1)
        refreshMarkers()
    }
    /// The first-time setup, on the console like any software (round 23).
    private func startSetup() {
        guard !launching, lifted == nil else { return }
        ConsoleHaptics.shared.play(.smallButton, .press)
        ConsoleSounds.shared.play(.launch)
        openProgram(.setup)
    }
    private func choose(_ item: ConsoleHomeItem) {
        homeSelection = item
        homeShortcut = nil
        let page = ConsoleHomeLayout.page(of: item, onHandheld: false)
        if page != homePage { homePage = page; refreshMarkers() }
        ConsoleHaptics.shared.play(.smallButton, .press)
        ConsoleSounds.shared.play(.move)
    }
    /// One of the small icons chosen (the D-pad up into their row).
    private func pickShortcut(_ shortcut: ConsoleHomeShortcut) {
        if homeShortcut != shortcut { ConsoleSounds.shared.play(.move) }
        homeShortcut = shortcut
        homeSelection = nil
        ConsoleHaptics.shared.play(.smallButton, .press)
    }
    /// A, or a second tap on what is chosen: its first way in.
    private func homeConfirm() {
        if !system.setupDone { startSetup(); return }
        if let shortcut = homeShortcut { useShortcut(shortcut); return }
        guard homeSelection != nil else { choose(.card); return }
        if let action = homeState.bar.right {
            perform(action)
        } else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
        }
    }
    /// B or HOME: an open page closes, else the cursor goes.
    private func homeBack() {
        if program.app != nil { closeProgram(); return }
        if homeSelection != nil || homeShortcut != nil { homeSelection = nil; homeShortcut = nil; ConsoleSounds.shared.play(.back) }
    }
    private func homeMove(_ direction: ConsoleDirection) {
        guard system.setupDone else { return }
        let row = ConsoleHomeShortcut.idle
        // Round 32: along the small icons, down from them onto the first
        // row, up from the first row into them (as the handheld's menu).
        if let current = homeShortcut, let index = row.firstIndex(of: current) {
            switch direction {
            case .left: pickShortcut(row[max(0, index - 1)])
            case .right: pickShortcut(row[min(row.count - 1, index + 1)])
            case .down:
                let x = ConsoleHomeLayout.shortcut(index, of: row.count).midX
                let firstRow = ConsoleHomeLayout.items(onHandheld: false, page: homePage).prefix(ConsoleHomeLayout.columns)
                choose(firstRow.min { abs(ConsoleHomeLayout.tile($0, shortcuts: true).midX - x) < abs(ConsoleHomeLayout.tile($1, shortcuts: true).midX - x) } ?? .card)
            case .up: ConsoleHaptics.shared.play(.sliderStop, .press)
            }
            return
        }
        if direction == .up, !row.isEmpty, let item = homeSelection,
           let index = ConsoleHomeLayout.items(onHandheld: false, page: homePage).firstIndex(of: item), index < ConsoleHomeLayout.columns {
            let x = ConsoleHomeLayout.tile(item, shortcuts: true).midX
            let nearest = row.indices.min { abs(ConsoleHomeLayout.shortcut($0, of: row.count).midX - x) < abs(ConsoleHomeLayout.shortcut($1, of: row.count).midX - x) } ?? 0
            pickShortcut(row[nearest])
            return
        }
        choose(ConsoleHomeLayout.move(from: homeSelection, direction))
    }
    private func perform(_ action: ConsoleHomeAction) {
        guard !launching, let item = homeSelection else { return }
        guard system.setupDone else { startSetup(); return }
        ConsoleHaptics.shared.play(.smallButton, .press)
        if item != .card { ConsoleSounds.shared.play(ConsoleApp(homeItem: item) != nil ? .launch : .select) }
        switch item {
        case .card: openCard(action)
        // Round 30: 相机 and 系统设置 open on the console itself (rounds 23
        // and 25 started them like software, into the handheld).
        case .camera: openProgram(.camera)
        // Round 32: 相册 (the camera's album by itself); 游戏笔记 is a small
        // icon (useShortcut).
        case .album: openProgram(.album)
        case .settings: openProgram(.settings)
        case .importFiles:
            if system.parental.restrictImport {
                ConsoleHaptics.shared.play(.sliderStop, .press)
                if let point = stage.lowerScreenPoint(art: CGPoint(x: ConsoleHomeLayout.rightButton.midX, y: ConsoleHomeLayout.rightButton.midY)) {
                    stage.calloutPoint = point
                    stage.calloutName = String(localized: "家长控制限制了导入")
                    stage.calloutStamp += 1
                }
                return
            }
            importFiles()
        case .activity: openProgram(.activity)
        case .theme: openProgram(.theme)
        case .manual: openProgram(.manual)
        case .modes: openProgram(.modes)
        case .pictureFrame: openProgram(.pictureFrame)
        case .tinBox: openProgram(.tinBox)
        }
    }
    /// The card in the console starts: fresh, or where it was left.
    private func openCard(_ action: ConsoleHomeAction) {
        guard let index = inserted, stage.cardInserted, index < cards.count else { return }
        guard let game = record(at: index) else {
            if let cartridge = cartridge(at: index) { play(cartridge) } else { beginLaunch(startDemo) }
            return
        }
        guard AzaharSession.isCoreAvailable else { return }
        let file = file(for: game)
        switch action {
        case .resume: beginLaunch { launch(file, true) }
        case .restart: SaveStates.removeResume(for: file); beginLaunch { launch(file, false) }
        case .open: beginLaunch { launch(file, false) }
        // Only on the menu over suspended software (the handheld's).
        case .continueGame, .continueDemo, .closeGame, .closeDemo: break
        }
    }
    /// A 典藏卡带's card started: its films come on the console's two
    /// screens (a program of the console, as 说明书 is), from the first one;
    /// the menu stays on the card.
    private func play(_ cartridge: Cartridge) {
        guard !launching, lifted == nil, program.app == nil else { return }
        NSLog("[gold] the %@ card started", cartridge.rawValue)
        GoldReel.shared.rewind(cartridge)
        programFromCard = true
        openProgram(.settings, page: .reel)
        homeSelection = .card
        ConsoleHomeCursor.selection = homeSelection
    }
    // MARK: Programs on the console (round 30)

    /// A program opens on the console where it stands: the cards sink into
    /// the floor, the console lies down flat and comes up as big as the
    /// display allows, and the program comes on in its two screens (on a
    /// phone, whose console's screens stay too small to read, over the
    /// whole display). No change to the handheld, no curtain.
    private func openProgram(_ app: ConsoleApp, page: ConsoleAppModel.Page? = nil) {
        guard !launching, lifted == nil, program.app == nil else { programShortcut = nil; return }
        #if os(iOS)
        // 11-15: the library on the cover (asked for there, the lid shut):
        // the camera opens as the cover's own deck, as it goes on there when
        // the lid shuts over it — not the console's two screens squeezed onto
        // the cover.
        if app == .camera, DisplayRoleMonitor.shared.libraryOnCover {
            NSLog("[stage] camera asked for on the cover: the cover's deck")
            OrientationTrace.shared.event("library on the cover: the camera opens as the cover's deck")
            programShortcut = nil
            openApp(.camera)
            return
        }
        #endif
        NSLog("[stage] program %@ on the console", app.rawValue)
        withAnimation(.easeIn(duration: 0.2)) { calloutShown = false }
        if programShortcut == nil, let item = app.homeItem { homeSelection = item; homeShortcut = nil }
        ConsoleHomeCursor.selection = homeSelection
        beforeProgram = (stage.view, stageZoom.progress)
        program.start(app, page: page, leave: { closeProgram() })
        markers = StageMarkers()
        programRects = nil
        withAnimation(.easeInOut(duration: 0.5)) { stageZoom.progress = 1 }
        stage.shelf.setRecession(1)
        stage.showProgram()
        updateCameraAwake()
        LastRun.note("program \(app.rawValue)")
    }
    /// HOME or POWER on the console, or the program's own way out: its
    /// screens go, the console stands up again where it was (round 31: as
    /// close as a pinch had brought it, turned as it was), the cards come
    /// back as far as they were.
    private func closeProgram() {
        guard let app = program.app else { return }
        NSLog("[stage] program %@ closed", app.rawValue)
        ConsoleSounds.shared.play(.back)
        program.stop()
        programRects = nil
        // Round 31: back to where it stood, as close as the pinch had it.
        if let saved = beforeProgram, saved.view.pose == .stage || saved.view.pose == .back {
            stage.restore(saved.view)
            withAnimation(.easeOut(duration: 0.6)) { stageZoom.progress = saved.zoom }
            stage.shelf.setRecession(saved.zoom)
        } else {
            stage.turnToFront()
            withAnimation(.easeOut(duration: 0.6)) { stageZoom.progress = 0 }
            stage.shelf.setRecession(0)
        }
        beforeProgram = nil
        if let shortcut = programShortcut {
            // Round 32: back onto the small icon it was opened from (11-15:
            // unless 主菜单顶上的按键 has just taken it off the row).
            programShortcut = nil
            if ConsoleHomeShortcut.idle.contains(shortcut) {
                homeShortcut = shortcut
                homeSelection = nil
            } else {
                homeShortcut = nil
                homeSelection = app.homeItem ?? .card
            }
        } else if programFromCard {
            homeSelection = .card
        } else if let item = app.homeItem { homeSelection = item }
        programFromCard = false
        stage.showHome(homeState)
        LastRun.note("library")
        // Round 32 (b15): the markers over the touch screen once the zoom
        // back is over too (888: a tap on the small icon right after 相册
        // closed landed on the body — the markers were placed before the
        // console had finished coming back).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            if program.app == nil { refreshMarkers() }
        }
    }
    /// The program's two screens laid over the console's (they are drawn
    /// as the handheld draws them, touched where they are).
    private func programScreens(_ app: ConsoleApp, rects: ProgramRects) -> some View {
        ZStack(alignment: .topLeading) {
            // (11-23: MicPointer's words keep off the two screens)
            programTop(app)
                .frame(width: rects.upper.width, height: rects.upper.height)
                .clipped()
                .micPointerObstacle()
                .position(x: rects.upper.midX, y: rects.upper.midY)
            programBottom(app)
                .frame(width: rects.lower.width, height: rects.lower.height)
                .clipped()
                .micPointerObstacle()
                .position(x: rects.lower.midX, y: rects.lower.midY)
        }
    }
    @ViewBuilder private func programTop(_ app: ConsoleApp) -> some View {
        if app == .camera || app == .album { CameraTopScreen(model: program.camera) }
        else if app == .notes { GameNotesTopScreen(model: program.notes) }
        else if let model = program.model { ConsoleAppTopScreen(model: model, ctx: programContext) }
    }
    @ViewBuilder private func programBottom(_ app: ConsoleApp) -> some View {
        if app == .camera || app == .album { CameraBottomScreen(model: program.camera) }
        else if app == .notes { GameNotesBottomScreen(model: program.notes) }
        else if let model = program.model { ConsoleAppBottomScreen(model: model, ctx: programContext) }
    }
    @ViewBuilder private func programFullScreen(_ app: ConsoleApp) -> some View {
        if app == .camera || app == .album { CameraFullScreen(model: program.camera) }
        else if app == .notes { GameNotesFullScreen(model: program.notes) }
        else if app == .tinBox, let model = program.model { PencilBoxOpen(model: model) }
        else if let model = program.model { ConsoleAppFullScreen(model: model, ctx: programContext) }
    }
    /// What a program on the console works with: the library's software
    /// (数据管理), and the test files' way in.
    private var programContext: ConsoleAppContext {
        ConsoleAppContext(games: library.games, remove: { library.remove($0) }, session: program.session,
                          testFiles: [], launchTestFile: { _ in })
    }
    /// 相机 runs only while the library is on screen and FoldArc active.
    private func updateCameraAwake() {
        #if os(iOS)
        let active = appPhase.phase == .active
        #else
        let active = true
        #endif
        program.camera.setAwake(program.app == .camera && active)
    }
    /// A key of the console while a program runs on it: the program's, but
    /// HOME and POWER, which close it.
    private func programKey(_ part: String, direction: ConsoleDirection? = nil) {
        guard program.app != nil else { return }
        stage.press(part)
        let key: PadButton?
        switch part {
        case "HOME 键", "电源键":
            ConsoleHaptics.shared.play(.faceButton, .press)
            closeProgram()
            return
        case "A 键": key = .a
        case "B 键": key = .b
        case "X 键": key = .x
        case "Y 键": key = .y
        case "START 键": key = .start
        case "SELECT 键": key = .select
        case "L 肩键": key = .l
        case "R 肩键": key = .r
        case "十字键", "滑动摇杆":
            switch direction {
            case .up?: key = .up
            case .down?: key = .down
            case .left?: key = .left
            case .right?: key = .right
            case nil: key = nil
            }
        default: key = nil
        }
        ConsoleHaptics.shared.play(part.contains("肩键") ? .shoulder : .faceButton, .press)
        guard let key else { ConsoleSounds.shared.play(.click); return }
        program.press(key)
    }

    // MARK: The shelf

    /// Where the shelf and its controls are (round 27): the lower screen
    /// inside its safe area.
    private func shelfGeometry(_ layout: Layout) -> ShelfGeometry {
        let r = layout.lower
        let left = layout.sideBySide ? 0 : layout.insets.leading
        let frame = CGRect(x: r.minX + left, y: r.minY, width: max(1, r.width - left - layout.insets.trailing),
                           height: max(1, r.height - layout.insets.bottom - 8 * layout.s))
        // 11-07: beside the
        // console (held across) the cards stand in a column.
        return ShelfGeometry(frame: frame, s: layout.s, viewSize: layout.size, vertical: layout.sideBySide)
    }
    /// The point the shelf shrinks toward under a pinch (the middle card).
    private func shelfAnchor(_ layout: Layout) -> UnitPoint {
        let c = shelfGeometry(layout).optics.centre
        return UnitPoint(x: c.x / max(1, layout.size.width), y: c.y / max(1, layout.size.height))
    }
    /// The shelf is up: not while the console comes down from a game, goes
    /// up into one, or a page is open over the shelf.
    private var shelfShown: Bool { !launching && !arriving && program.app == nil }

    /// Where the console takes a finger (round 31: brought close, its lower screen reached down over the
    /// shelf, where the stage's touch did not go, and its menu could not be
    /// touched there). Its stage; brought closer by a pinch, also wherever
    /// it reaches (`overShelf`: the shelf leaves that part to it); from half
    /// way in, when the shelf has faded and takes no touch, and with a
    /// program on it, the whole view.
    private func consoleTouch(_ layout: Layout) -> (area: CGRect, overShelf: CGRect?) {
        let full = CGRect(origin: .zero, size: layout.size)
        let p = stageZoom.progress
        if program.app != nil || p >= 0.5 { return (full, nil) }
        guard p > 0, let bounds = stage.screenBounds() else { return (layout.stageArea, nil) }
        let console = bounds.insetBy(dx: -8, dy: -8).intersection(full)
        guard !console.isNull, !console.isEmpty else { return (layout.stageArea, nil) }
        return (layout.stageArea.union(console), console)
    }
    /// The console's part of the shelf's area, in the shelf's own drawing
    /// (ShelfRecedes shrinks the shelf about its middle card).
    private func shelfHole(_ console: CGRect?, layout: Layout) -> CGRect? {
        guard let console else { return nil }
        let p = stageZoom.progress, e = p * p * (3 - 2 * p), k = max(0.1, 1 - 0.72 * e)
        let c = shelfGeometry(layout).optics.centre
        return CGRect(x: c.x + (console.minX - c.x) / k, y: c.y + (console.minY - c.y) / k,
                      width: console.width / k, height: console.height / k)
    }

    private func lowerScreen(_ layout: Layout, hole: CGRect? = nil) -> some View {
        // The cards are solids in the stage's scene (round 27:
        // ConsoleStage.shelf); this is their touch (CardShelf.swift; round
        // 28: no controls under them any more; round 27: a retro handheld's;
        // round 26: flat cards, a ▶ on the middle one, a music player's bar).
        ZStack(alignment: .topLeading) {
            CardShelfView(shelf: stage.shelf, geometry: shelfGeometry(layout), cards: cards, order: shelf, offset: $flowOffset,
                          centre: centre, hidden: lifted?.index, inserted: inserted, theme: theme,
                          onTap: { tapCard($0) },
                          onLift: { index, point, phase in lift(index, point: point, phase: phase) },
                          onStart: { quickStart($0) },
                          onEject: { ejectToShelf() },
                          // Round 31: from half way in the shelf has faded and
                          // takes no touch (ShelfRecedes); nothing of it for
                          // VoiceOver and the tests either.
                          active: program.app == nil && stageZoom.progress < 0.5, hole: hole,
                          onMiss: { tapBesideCards($0) },
                          canDelete: { record(at: $0) != nil && !launching },
                          onBurst: { burstCard($0) },
                          onDelete: { cutCard($0) })
            cutUndoBar(layout)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    // MARK: 删除 (11-07 the scissors; the lifted card taken over the edge)

    /// The lifted card burst in the hand (taken away from the console, over
    /// the shelf's edge, all loose, let go): the lift is over at once — the
    /// solid goes (PixelCardView draws the remains, the eraser rubs them
    /// out), the console back as it stood. Its place on the shelf stays
    /// empty (the shelf keeps a card whose solid is gone out of sight) until
    /// cutCard, once the eraser has done.
    private func burstCard(_ index: Int) {
        guard let card = lifted, card.index == index else { return }
        lifted = nil
        stage.offerSlot(false)
        stage.shelf.dropHand()
        if case .shelf(let view) = card.origin { stage.restore(view) }
    }
    /// A card deleted on the shelf (it burst in the hand and the eraser has
    /// rubbed the remains out; or VoiceOver's 删除): its game leaves the
    /// library (LibraryModel.cut: the copy waits while 撤销 is offered); the
    /// shelf settles on the card beside it. False when it could not be: the
    /// card is then on the shelf again (a burst one's solid made anew).
    private func cutCard(_ index: Int) -> Bool {
        guard let record = record(at: index), inserted != index, !launching else {
            stage.shelf.showAgain(index)
            return false
        }
        burstCard(index)
        // The card after it (or before, at the end) comes to the middle
        // (found before the cut moves the indices).
        let shelf = self.shelf
        var next: GameRecord?
        if let p = shelf.firstIndex(of: index) {
            next = (p + 1 < shelf.count ? shelf[p + 1] : (p > 0 ? shelf[p - 1] : nil)).flatMap { self.record(at: $0) }
        }
        finishPendingCut()
        guard let done = library.cut(record) else {
            stage.shelf.showAgain(index)
            return false
        }
        selected = next
        withAnimation(.spring(duration: 0.35)) { lastCut = done }
        lastCutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, lastCut == done else { return }
            library.finishCut(done)
            withAnimation(.easeOut(duration: 0.3)) { lastCut = nil }
        }
        return true
    }
    /// 撤销: the game back in the library, its card in the middle.
    private func undoCut() {
        guard let done = lastCut else { return }
        lastCutTask?.cancel()
        lastCutTask = nil
        library.undoCut(done)
        selected = done.record
        withAnimation(.easeOut(duration: 0.25)) { lastCut = nil }
        ConsoleSounds.shared.play(.back)
    }
    /// The cut offered for 撤销 stands now.
    private func finishPendingCut() {
        lastCutTask?.cancel()
        lastCutTask = nil
        guard let done = lastCut else { return }
        library.finishCut(done)
        lastCut = nil
    }
    /// 「已删除 …  撤销」 along the foot of the shelf.
    @ViewBuilder private func cutUndoBar(_ layout: Layout) -> some View {
        if let done = lastCut {
            let flow = shelfGeometry(layout).flow
            let s = layout.s
            HStack(spacing: 12 * s) {
                Image(systemName: "trash").font(.system(size: 13 * s, weight: .bold))
                Text(done.record.originBookmark == nil ? "已删除「\(done.record.title)」" : "已删除「\(done.record.title)」和它的原文件").font(.system(size: 13 * s, weight: .semibold)).lineLimit(1)
                Button { undoCut() } label: {
                    Text("撤销").font(.system(size: 13 * s, weight: .heavy))
                        .padding(.horizontal, 10 * s).padding(.vertical, 5 * s)
                        .background(Capsule().fill(theme.accent.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cut-undo")
            }
            .foregroundStyle(theme.ink)
            .padding(.leading, 14 * s).padding(.trailing, 8 * s).padding(.vertical, 7 * s)
            .background(Capsule().fill(.regularMaterial))
            .frame(maxWidth: max(120, flow.width - 24))
            .fixedSize(horizontal: false, vertical: true)
            .position(x: flow.midX, y: flow.maxY - 22 * s)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cut-undo-bar")
        }
    }

    // MARK: Choosing, lifting, inserting, pulling out, launching

    /// A tap on a card on the shelf: brings it to the middle; in the middle
    /// already (round 28, no buttons under the shelf), it goes into the
    /// console, as a hand would put it in, and the console's menu has it
    /// chosen (开启 or the console's A starts it). A card already in the
    /// console comes out to the shelf.
    private func tapCard(_ index: Int) {
        guard !launching, lifted == nil, index < cards.count else { return }
        if index != centre {
            guard let position = shelf.firstIndex(of: index) else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.1)) { flowOffset = Double(position) }
            centre = index
            selected = record(at: index)
            return
        }
        quickStart(index, start: false)
    }

    /// The middle card into the console the way a hand would put it in —
    /// up off the shelf toward the player as the console turns round to take
    /// it, carried over, let go, a click — and, with `start`, once the
    /// console is back where it stood, started (开启, or 继续上次 when it was
    /// left part way). The card in the console comes out first. With the
    /// shelf empty (its only card is in the console), `start` starts that
    /// card. Round 28: a tap on the middle card (`start` false) and
    /// VoiceOver's 插入并开启; round 27: A under the shelf; round 26: ▶.
    private func quickStart(_ index: Int, start: Bool = true) {
        guard !launching, lifted == nil, index < cards.count else { return }
        if index == inserted {
            guard start, stage.cardInserted else { return }
            homeSelection = .card
            homeConfirm()
            return
        }
        guard index == centre else { tapCard(index); return }
        NSLog("[stage] shelf: %@ %@", start ? "in and start" : "in", cards[index].title)
        let from = stage.shelf.layout.cardWidth > 0 ? stage.shelf.layout.centre : CGPoint(x: lowerRect.midX, y: lowerRect.minY + lowerRect.height * 0.33)
        lift(index, point: from, phase: .began)
        Task { @MainActor in
            // Up off the shelf, toward the player, while the console turns
            // round (1 s) …
            try? await Task.sleep(for: .milliseconds(40))
            guard lifted?.index == index else { return }
            let up = CGPoint(x: from.x, y: from.y - max(40, stage.shelf.layout.cardWidth * 0.6))
            lifted?.point = up
            stage.carryLifted(to: up, duration: 0.42)
            try? await Task.sleep(for: .milliseconds(620))
            guard lifted?.index == index else { return }
            // … over the console …
            let over = CGPoint(x: stageRect.midX, y: stageRect.midY + stageRect.height * 0.1)
            lifted?.point = over
            stage.carryLifted(to: over, duration: 0.48)
            try? await Task.sleep(for: .milliseconds(540))
            guard lifted?.index == index else { return }
            // … and in (0.46 s to the slot, the slide and click) and back to
            // where it stood (0.9 s); then it starts, as A would start it.
            lift(index, point: over, phase: .ended)
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if inserted == index, stage.cardInserted, !stage.busy { break }
            }
            guard start, inserted == index, stage.cardInserted, !launching else { return }
            try? await Task.sleep(for: .milliseconds(250))
            homeSelection = .card
            homeConfirm()
        }
    }

    /// The card in the middle, lifted off the shelf: the console turns
    /// round and offers its slot for as long as the card is in the hand.
    /// True when `.began` took the card into the hand as the lifted one.
    @discardableResult
    private func lift(_ index: Int, point: CGPoint, phase: LiftPhase) -> Bool {
        guard !launching else {
            if phase == .began { NSLog("[library] no lift for card %ld: a game is being started", index) }
            return false
        }
        switch phase {
        case .began:
            // 11-07: it may be in the hand already (CardShelfView
            // took it): then any card; off the shelf, the middle one.
            let inHand = stage.shelf.handIndex
            guard inHand == nil ? index == centre : inHand == index, inserted != index, lifted == nil else {
                NSLog("[library] no lift for card %ld: middle %ld, in the console %@, lifted %@, in the hand %@", index, centre,
                      String(describing: inserted), String(describing: lifted?.index), String(describing: inHand))
                return false
            }
            FrameMeter.shared.begin("card.lift")
            FrameMeter.shared.end(after: 1.1)
            // Normally printed ahead (prepareCentre); if not, once the
            // console has turned, not at the start of the turn (round 21).
            if !stage.isPrepared(homeState(withCard: index)) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    for _ in 0..<60 where stage.moving { try? await Task.sleep(for: .milliseconds(30)) }
                    guard lifted?.index == index, index < cards.count else { return }
                    if !stage.isPrepared(homeState(withCard: index)) { stage.prepareHome(homeState(withCard: index)) }
                    stage.prepareCard(cards[index])
                }
            }
            // Round 27: the solid itself comes off the shelf into the hand
            // (or is there already: it follows the finger from where it is).
            if inHand == nil { stage.liftFromShelf(index, at: point) } else { stage.moveLifted(to: point) }
            lifted = LiftedCard(index: index, point: point, origin: .shelf(stage.view))
            stage.turnToBack()
            stage.offerSlot(true)
            ConsoleHaptics.shared.play(.hingeDetent, .press)
            return true
        case .moved:
            guard lifted != nil else { return false }
            lifted?.point = point
            stage.moveLifted(to: point)
        case .ended:
            guard let card = lifted else { return false }
            // Let go anywhere over the console (the stage) and it goes in;
            // anywhere else and it goes back where it came from.
            if stageRect.insetBy(dx: -20, dy: -20).contains(point) {
                insert(card)
            } else {
                putDown(card)
            }
        }
        return true
    }

    /// The finger let go of the card in the slot: it stays where it was let
    /// go, or clicks home if it was nearly there (ConsoleStage.releaseCard).
    private func pullEnded() {
        if stage.releaseCard() { ConsoleHaptics.shared.play(.lidShut, .press); ConsoleSounds.shared.play(.click) }
        insertedOutStored = stage.cardOut
        refreshMarkers()
    }

    /// The card drawn out of the console by a finger: once clear of the
    /// slot it is in the hand, like one lifted off the shelf.
    private func carry(_ point: CGPoint, phase: CarryPhase) {
        guard !launching else { return }
        switch phase {
        case .out:
            guard let index = inserted, lifted == nil, stage.shelf.handIndex == nil else { return }
            stage.offerSlot(true)
            // Round 27: the solid comes up out of the slot into the hand.
            stage.liftFromSlot(index, at: point)
            lifted = LiftedCard(index: index, point: point, origin: .console)
            refreshMarkers()
            ConsoleHaptics.shared.play(.hingeDetent, .release)
        case .moved:
            guard let card = lifted, case .console = card.origin else { return }
            lifted?.point = point
            stage.moveLifted(to: point)
        case .dropped:
            guard let card = lifted, case .console = card.origin else { return }
            if stageRect.insetBy(dx: -20, dy: -20).contains(point) {
                insert(card)
            } else {
                putDown(card)
            }
        }
    }

    /// The card in the hand goes back: onto the shelf, the console back to
    /// where it stood (lifted off the shelf), or onto the shelf as a card
    /// that was in the console (the shelf makes room for it in the middle).
    /// Round 27: the solid flies to its place and stands there again.
    private func putDown(_ card: LiftedCard) {
        stage.offerSlot(false)
        switch card.origin {
        case .shelf(let view):
            withAnimation(.spring(duration: 0.4)) { lifted = nil }
            stage.putLiftedBack()
            stage.restore(view)
        case .console:
            withAnimation(.spring(duration: 0.45)) {
                lifted = nil
                inserted = nil; insertedID = nil; insertedStored = ""; insertedOutStored = 0; resumeDate = nil
                if homeSelection == .card { homeSelection = nil }
                settle(on: card.index, animated: false)
            }
            stage.putLiftedBack()
            ConsoleHaptics.shared.play(.smallButton, .release)
        }
    }

    /// The card in the console goes back to the shelf by itself (a tap on it
    /// in the slot, or B under the shelf): it slides out, flies to the
    /// middle of the shelf, which makes room for it there, and stands. For B
    /// with the console facing the player, it turns round first to let it
    /// out, and back afterwards.
    private func ejectToShelf() {
        guard !launching, lifted == nil, let index = inserted, stage.titleInSlot != nil, stage.shelf.handIndex == nil else { return }
        let turn = !stage.rearVisible && (stage.pose == .stage || stage.pose == .back)
        let saved = stage.view
        Task { @MainActor in
            if turn {
                stage.turnToBack()
                try? await Task.sleep(for: .milliseconds(850))
                guard inserted == index, stage.titleInSlot != nil else { return }
            }
            ConsoleHaptics.shared.play(.hingeDetent, .release)
            ConsoleSounds.shared.play(.click)
            stage.ejectToShelf(index) {
                withAnimation(.spring(duration: 0.45)) {
                    inserted = nil; insertedID = nil; insertedStored = ""; insertedOutStored = 0; resumeDate = nil
                    if homeSelection == .card { homeSelection = nil }
                    settle(on: index, animated: false)
                }
                refreshMarkers()
                if turn {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        stage.restore(saved)
                    }
                }
            }
        }
    }

    /// The card goes in: the solid in the hand flies to the slot's mouth and
    /// slides in until it clicks (round 27: the same solid all the way from
    /// the shelf; round 24 handed a flat picture over to a 3D card at the
    /// mouth); the shelf closes the gap; the console's menu shows the card,
    /// chosen, and the console goes back to where it stood. A card already
    /// in the slot comes out first.
    private func insert(_ card: LiftedCard) {
        guard card.index < cards.count else { return }
        FrameMeter.shared.begin("card.insert")
        FrameMeter.shared.end(after: 2.0)
        let info = cards[card.index]
        if let old = inserted, old != card.index { stage.ejectCard(animated: true) }
        withAnimation(.easeOut(duration: 0.1)) { lifted = nil }
        stage.insertLifted(info) {
            homeSelection = .card
            ConsoleHaptics.shared.play(.lidShut, .press)
            ConsoleSounds.shared.play(.click)
            stage.offerSlot(false)
            if case .shelf(let view) = card.origin { stage.restore(view) }
        }
        Task { @MainActor in
            // On its way: the shelf closes the gap; the menu that will show
            // the card is the one printed ahead (round 21).
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(duration: 0.5)) {
                inserted = card.index; insertedID = cardID(at: card.index); insertedStored = insertedID ?? ""; insertedOutStored = 0
                settle(on: nil, animated: false)
            }
            resumeDate = resume(at: card.index)
            homeSelection = .card
        }
    }

    /// 开启 / 继续上次: the console comes up until it fills the screen, the
    /// screens go white as a handheld's do when it starts software, and the
    /// game takes over under the white (LibraryView lifts it once the game's
    /// view is on screen).
    private func beginLaunch(label: String? = nil, _ action: @escaping () -> Void) {
        guard !launching, lifted == nil else { return }
        // The shelf and the names go quickly, not at once (round 21: the
        // shelf vanished in one frame, which read as a jump).
        withAnimation(.easeOut(duration: 0.2)) { launching = true }
        stage.showShadow(false, fade: 0.3)
        markers = StageMarkers()
        FrameMeter.shared.begin("launch.zoom")
        ConsoleSounds.shared.play(.launch)
        stage.fillScreen(duration: 1.0)
        // Round 24: no white over the end of the zoom any more. LibraryView
        // holds a still picture of the console filling the screen over the
        // change, and the game's screens dissolve out of it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1040))
            FrameMeter.shared.end("launch.zoom")
            LastRun.note("launch \(label ?? inserted.flatMap { $0 < cards.count ? cards[$0].title : nil } ?? "test file")")
            action()
        }
    }
}

extension Notification.Name {
    /// A screen (the library, a game) is in place: LibraryView lifts the
    /// curtain it put up for the change (round 20).
    static let foldArcScreenReady = Notification.Name("FoldArc.screenReady")
}

/// Where things are over the console, for assistive access.
struct StageMarkers: Equatable {
    var slot: CGPoint?
    var cardLip: CGPoint?
    var tiles: [ConsoleHomeItem: CGPoint] = [:]
    /// Round 32: the small icons along the top and the other pages' dots.
    var shortcuts: [ConsoleHomeShortcut: CGPoint] = [:]
    var pages: [Int: CGPoint] = [:]
    var left: CGPoint?
    var right: CGPoint?
    /// The console's A, B and HOME keys.
    var keys: [String: CGPoint] = [:]
    /// The volume knob (round 21).
    var volume: CGPoint?
    /// The stylus's hole (seen from behind) and the headphone jack (round 23).
    var stylus: CGPoint?
    var jack: CGPoint?
    /// 开始设置 while the console is not set up (round 23).
    var setup: CGPoint?
    /// The volume knob's travel (round 26: the iPhone's slider lies along it).
    var volumeTrack: VolumeTrackMarker?
    /// The 3D slider's knob (round 30).
    var depth: CGPoint?
    /// The charger's port (seen from behind) or the charge light (round 26).
    var charger: CGPoint?
    /// 11-23: the MIC printed on the console, while a program lies on it (MicPointer's arrow points there).
    var mic: CGRect?
}

/// The volume knob's travel on the screen (round 26): its middle at silent
/// and at loudest, its size there (along the track, across it).
struct VolumeTrackMarker: Equatable {
    var quiet: CGPoint
    var loud: CGPoint
    var knobLength: CGFloat
    var knobWidth: CGFloat
}

/// How far a pinch has brought the console in (round 26): 0 as it stands,
/// 1 at the closest. Its own object, so that only the shelf redraws as it
/// changes (the whole library redrew with every frame of a pinch otherwise).
@MainActor final class StageZoom: ObservableObject {
    @Published var progress = 0.0
}

/// A program of the console's own on the console on the stage (round 30):
/// 系统设置, 相机, 游戏记录, 主题, 说明书, the first-time setup. The console
/// it runs on is a session of its own (its MIC, Circle Pad and 3D slider
/// are what the settings' tests read); nothing plays on it.
@MainActor final class StageProgram: ObservableObject {
    @Published private(set) var app: ConsoleApp?
    /// 系统设置 and the like (a new one each time one opens).
    @Published private(set) var model: ConsoleAppModel?
    let camera = CameraAppModel()
    /// Round 32: 游戏笔记 (no software under the library's console: a page
    /// has no screen to take).
    let notes = GameNotesModel()
    let session = DemoSession()
    /// 11-15: the program on the library's console now (the lid shut over
    /// 铅笔盒 makes the cover the box's lid; FoldArcApp).
    static private(set) var shown: ConsoleApp?
    init() {
        // 11-06: the lid shut over the library with the camera on this
        // console: it goes on as the cover's control deck (FoldArcApp).
        CameraAppModel.stageCamera = camera
        Self.shown = nil
    }
    func start(_ app: ConsoleApp, page: ConsoleAppModel.Page? = nil, leave: @escaping () -> Void) {
        stop()
        Self.shown = app
        session.runApp(app)
        if app == .camera || app == .album {
            camera.session = session
            camera.leave = leave
            session.menuInput = { [camera] key, down in camera.handle(key, down: down) }
            camera.open(albumOnly: app == .album)
        } else if app == .notes {
            notes.screens = { nil }
            notes.hasScreens = false
            notes.softwareTitle = nil
            notes.leave = leave
            session.menuInput = { [notes] key, down in notes.handle(key, down: down) }
            notes.openProgram()
        } else {
            let model = ConsoleAppModel(app: app, page: page)
            model.session = session
            model.leave = leave
            session.menuInput = { [model] key, down in model.handle(key, down: down) }
            self.model = model
        }
        self.app = app
    }
    func stop() {
        guard let app else { return }
        Self.shown = nil
        if app == .camera || app == .album { camera.close() }
        if app == .notes { notes.closeProgram() }
        session.menuInput = nil
        session.runApp(nil)
        model = nil
        self.app = nil
    }
    /// A key of the console, pressed and let go.
    func press(_ key: PadButton) {
        session.press(key, down: true)
        session.press(key, down: false)
    }
}

/// Where the console's two screens are while a program runs on it.
struct ProgramRects: Equatable {
    var upper: CGRect
    var lower: CGRect
    /// The program is drawn in them (else over the whole display: a phone's
    /// console, whose touch screen stays under HOME's smallest).
    var fit: Bool
}

/// The shelf of cards as the console is brought closer (round 26): smaller
/// and fainter, gone at the closest; it takes no touch once half gone.
struct ShelfRecedes: ViewModifier {
    @ObservedObject var zoom: StageZoom
    var anchor = UnitPoint(x: 0.5, y: 0.42)
    func body(content: Content) -> some View {
        let p = zoom.progress
        let e = p * p * (3 - 2 * p)
        content
            .scaleEffect(1 - 0.72 * e, anchor: anchor)
            .opacity(1 - e)
            .blur(radius: 5 * e)
            .allowsHitTesting(p < 0.5)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: p)
    }
}


// MARK: - The strip, the stage's finger, callouts

/// The time and the battery over the paper, quietly; nothing else.
struct LibraryStatusStrip: View {
    var theme: LibraryTheme
    var s: Double
    @ObservedObject private var battery = BatteryLight.shared
    var body: some View {
        ZStack {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 11 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                    // The library's landmark for assistive access and the tests.
                    .accessibilityIdentifier("游戏库")
            }
            HStack(spacing: 5 * s) {
                Spacer(minLength: 0)
                if let level = battery.level {
                    Text("\(Int((level * 100).rounded()))%").font(.system(size: 9 * s, weight: .semibold, design: .rounded)).monospacedDigit()
                        .accessibilityHidden(true)
                }
                MenuBatteryGlyph(level: battery.level, charging: battery.pluggedIn, s: s * 0.9, tint: theme.inkSoft)
            }
        }
        .foregroundStyle(theme.inkSoft)
        .padding(.horizontal, 14 * s)
        .frame(height: 18 * s)
    }
}

/// Over the stage: a drag turns the console (and keeps turning a little
/// after the finger lifts), a finger held still or a two-finger tap shows
/// the other side, a tap goes to the console (its touch screen, its keys).
/// Round 30: the pinch is the whole library's (LibraryMenuView.pinch), so
/// two fingers anywhere bring the console closer; a push on the Circle Pad
/// moves the menu's cursor; the 3D slider is dragged like the volume's. A
/// drag that starts on
/// the card in the slot moves the card instead (round 20): along the slot,
/// as far as the finger goes, and it stays where it is let go, as a real
/// card does; it takes a firmer pull to leave the contacts, and clicks home
/// when pushed nearly all the way in. Clear of the slot it is in the hand
/// (`carry`).
struct ConsoleStageGestures: View {
    @ObservedObject var stage: ConsoleStage
    var origin: CGPoint
    var s: Double
    /// A program runs on the console (round 30): it lies still under the
    /// finger (no turning it, no other side), its keys and sliders work.
    var program = false
    var onTap: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void
    /// The volume knob dragged along its track: the new level (0...1).
    var onVolume: (Double) -> Void
    /// The 3D knob dragged along its track: the new depth (0...1, round 30).
    var onDepth: (Double) -> Void = { _ in }
    /// The Circle Pad pushed most of the way: the menu's cursor moves once
    /// per push (round 30).
    var onStick: (ConsoleDirection) -> Void = { _ in }
    /// Round 32: a finger swept sideways over the touch screen (left: the
    /// next page of the menu).
    var onSwipe: (ConsoleDirection) -> Void = { _ in }
    /// Round 30: with a program on the console the Circle Pad is a stick
    /// (its push, -1…1 each way, y down; nil let go): the program's console
    /// reads it (系统设置 › 摇杆) and makes menu presses of it.
    var onStickMove: ((CGVector?) -> Void)? = nil
    var carry: (CGPoint, LibraryMenuView.CarryPhase) -> Void
    var pullEnded: () -> Void
    private enum Mode {
        case turn
        /// Along the slot on the screen, a full card's length in points,
        /// the card's place when the finger came down.
        case pull(CGVector, CGFloat, Double)
        case hand
        /// Along the volume track on the screen (silent to loudest), the
        /// points for the whole travel, the level when the finger came down.
        case volume(CGVector, CGFloat, Double)
        /// The same along the 3D track (OFF to deepest, round 30).
        case depth(CGVector, CGFloat, Double)
        /// On the Circle Pad: the direction it was last pushed (nil: back in
        /// the middle, ready for the next push).
        case stick(ConsoleDirection?)
        /// Round 30: a program on the console; the drag does nothing.
        case still
        /// Round 32: begun on the touch screen (the menu): sideways it turns
        /// the page, up or down it turns the console as before.
        case swipe
    }
    @ViewState private var mode: Mode?
    @ViewState private var lastTranslation = CGSize.zero
    /// The closest a pinch brings the console; there it is gone into (round 26).
    static let maxZoom = 2.4
    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { value in changed(value) }
                .onEnded { value in ended(value) })
            .gesture(TwoFingerTap { if !program { stage.flip() } })
            // A finger held still shows the other side too (one-handed, and
            // the UI tests cannot tap with two fingers on the Duo).
            .onLongPressGesture(minimumDuration: 0.55, maximumDistance: 10) {
                guard !program else { return }
                stage.flip()
                ConsoleHaptics.shared.play(.hingeDetent, .press)
            }
            .onTapGesture { location in
                onTap(CGPoint(x: location.x + origin.x, y: location.y + origin.y))
            }
            // Alongside, not before: a single tap is not held back to see
            // whether a second one follows (the menu answers at once).
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                onDoubleTap(CGPoint(x: value.location.x + origin.x, y: value.location.y + origin.y))
            })
    }

    private func changed(_ value: DragGesture.Value) {
        if mode == nil {
            let start = CGPoint(x: value.startLocation.x + origin.x, y: value.startLocation.y + origin.y)
            if stage.isCard(at: start), let pull = stage.pullVector() {
                mode = .pull(pull.direction, max(80 * s, pull.length), stage.cardOut)
            } else if stage.isVolume(at: start), let track = stage.volumeVector() {
                // At least 60 points for the whole travel: seen at an angle
                // the track is short, and it would be all or nothing.
                mode = .volume(track.direction, max(60 * s, track.length), ConsoleVolume.shared.level)
            } else if stage.isDepth(at: start), let track = stage.depthVector() {
                mode = .depth(track.direction, max(60 * s, track.length), Stereo3D.storedSlider)
            } else if stage.isCirclePad(at: start) {
                mode = .stick(nil)
            } else if program {
                mode = .still
            } else if stage.lowerScreenFacing, stage.touch(at: start)?.screenPoint != nil {
                mode = .swipe
            } else {
                mode = .turn
            }
        }
        let point = CGPoint(x: value.location.x + origin.x, y: value.location.y + origin.y)
        switch mode {
        case .turn:
            let dx = value.translation.width - lastTranslation.width
            let dy = value.translation.height - lastTranslation.height
            lastTranslation = value.translation
            // A finger of a pinch does not turn the console (round 30).
            if stage.shelf.pinching { return }
            stage.yaw += dx * 0.55
            stage.tilt = min(125, max(-30, stage.tilt - dy * 0.4))
            stage.applyUserPose()
        case .pull(let direction, let length, let start):
            let along = value.translation.width * direction.dx + value.translation.height * direction.dy
            var out = start + along / length
            // Leaving the contacts takes a firmer pull: the first few
            // millimetres move the card a quarter as far as the finger.
            if start == 0 { out = out < 0.06 ? max(0, out) * 0.25 : out - 0.045 }
            let wasHome = stage.cardInserted
            if out >= 1 {
                stage.pullCard(progress: 1)
                mode = .hand
                carry(point, .out)
            } else {
                stage.pullCard(progress: max(0, out))
                if wasHome != stage.cardInserted {
                    // Off the contacts, or back on them.
                    ConsoleHaptics.shared.play(wasHome ? .hingeDetent : .lidShut, .press)
                    ConsoleSounds.shared.play(.click)
                }
            }
        case .hand:
            carry(point, .moved)
        case .volume(let direction, let length, let start):
            let along = value.translation.width * direction.dx + value.translation.height * direction.dy
            onVolume((min(1, max(0, start + along / length)) * 20).rounded() / 20)
        case .depth(let direction, let length, let start):
            let along = value.translation.width * direction.dx + value.translation.height * direction.dy
            onDepth((min(1, max(0, start + along / length)) * 10).rounded() / 10)
        case .stick(let pushed):
            let dx = value.translation.width, dy = value.translation.height
            if let onStickMove {
                let full = 30 * s, length = hypot(dx, dy)
                let k = length > full ? full / length : 1
                onStickMove(CGVector(dx: dx * k / full, dy: dy * k / full))
                return
            }
            // Pushed most of the way (a third of the pad's reach on the
            // screen), it is a press of that direction; back near the
            // middle, it is ready for the next.
            let reach = hypot(dx, dy)
            if reach < 8 * s {
                if pushed != nil { mode = .stick(nil) }
            } else if reach > 18 * s, pushed == nil {
                let direction: ConsoleDirection = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                mode = .stick(direction)
                onStick(direction)
            }
        case .swipe:
            // Mostly up or down once it has gone a little way: a turn after all.
            let dx = value.translation.width, dy = value.translation.height
            if hypot(dx, dy) > 14 * s, abs(dy) > abs(dx) * 1.4 {
                mode = .turn
                lastTranslation = value.translation
            }
        case .still, nil:
            break
        }
    }

    private func ended(_ value: DragGesture.Value) {
        let point = CGPoint(x: value.location.x + origin.x, y: value.location.y + origin.y)
        switch mode {
        case .turn:
            let carryOn = (value.predictedEndTranslation.width - value.translation.width) * 0.55 * 0.35
            stage.coast(yawBy: carryOn)
        case .pull:
            pullEnded()
        case .hand:
            carry(point, .dropped)
        case .stick:
            onStickMove?(nil)
        case .swipe:
            let dx = value.translation.width, dy = value.translation.height
            if abs(dx) > 36 * s, abs(dx) > abs(dy) { onSwipe(dx < 0 ? .left : .right) }
        case .volume, .depth, .still, nil:
            break
        }
        mode = nil
        lastTranslation = .zero
    }
}

#if os(iOS)
/// A tap with two fingers (SwiftUI has no gesture for it).
struct TwoFingerTap: UIGestureRecognizerRepresentable {
    var action: () -> Void
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.numberOfTouchesRequired = 2
        recognizer.numberOfTapsRequired = 1
        return recognizer
    }
    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
}
#else
struct TwoFingerTap: Gesture {
    var action: () -> Void
    var body: some Gesture { TapGesture(count: 3).onEnded { action() } }
}
#endif

/// The name of a part, next to the finger.
struct PartCallout: View {
    var theme: LibraryTheme
    var name: String
    var s: Double
    var body: some View {
        Text(name)
            .font(.system(size: 10 * s, weight: .bold, design: .rounded))
            .foregroundStyle(theme.isDark ? theme.bar : .white)
            .padding(.horizontal, 10 * s).padding(.vertical, 5 * s)
            .background(theme.isDark ? theme.ink : theme.bar, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .accessibilityLabel("部件：\(name.hasPrefix("游戏卡 · ") ? String(localized: "游戏卡 · \(String(name.dropFirst(6)))") : shownName(name))")
    }
}

// MARK: - The shelf of cards: CardShelf.swift (round 26; CoverFlow before)

// MARK: - 游戏记录's store

/// 游戏记录 (round 20): how long each software has been played, like a
/// handheld's activity log. Counted while a game (or the demo) is on screen,
/// FoldArc in the foreground and the lid open; kept in play-log.json in the
/// data folder, by the copy's file name ("demo" for Orbit Garden).
@MainActor final class PlayLog: ObservableObject {
    static let shared = PlayLog()
    struct Entry: Codable, Identifiable {
        var id: String
        var title: String
        var seconds: Double
        var sessions: Int
        var first: Date
        var last: Date
    }
    @Published private(set) var entries: [String: Entry] = [:]
    private var current: String?
    private var since: Date?
    private var paused = Set<String>()
    private var url: URL { Storage.root.appendingPathComponent("play-log.json") }

    private init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
        #if os(iOS)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PlayLog.shared.pause("background") }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PlayLog.shared.resume("background") }
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PlayLog.shared.end() }
        }
        #endif
    }
    /// A software comes on screen.
    func begin(id: String, title: String) {
        end()
        let now = Date()
        var entry = entries[id] ?? Entry(id: id, title: title, seconds: 0, sessions: 0, first: now, last: now)
        entry.title = title
        entry.sessions += 1
        entry.last = now
        entries[id] = entry
        current = id
        paused = []
        since = now
        save()
    }
    /// The software's name, once its own is read (SMDH).
    func retitle(_ title: String) {
        guard let id = current, !title.isEmpty, entries[id]?.title != title else { return }
        entries[id]?.title = title
        save()
    }
    /// Off screen for a while (`reason`: background, lid…): not counted.
    func pause(_ reason: String) {
        guard current != nil else { return }
        add()
        paused.insert(reason)
        since = nil
    }
    func resume(_ reason: String) {
        guard current != nil else { return }
        paused.remove(reason)
        if paused.isEmpty, since == nil { since = Date() }
    }
    /// The software is closed.
    func end() {
        guard current != nil else { return }
        add()
        current = nil
        since = nil
        paused = []
        save()
    }
    private func add() {
        guard let id = current, let since else { return }
        let now = Date()
        entries[id]?.seconds += max(0, now.timeIntervalSince(since))
        entries[id]?.last = now
        self.since = paused.isEmpty ? now : nil
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: Storage.root, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
    /// 格式化主机 (round 23): the log goes with everything else.
    func forgetAll() {
        current = nil; since = nil; paused = []
        entries = [:]
        try? FileManager.default.removeItem(at: url)
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "不到 1 分钟") }
        if minutes < 60 { return String(localized: "\(minutes) 分钟") }
        return minutes % 60 == 0 ? String(localized: "\(minutes / 60) 小时") : String(localized: "\(minutes / 60) 小时 \(minutes % 60) 分")
    }
}
