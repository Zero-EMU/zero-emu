import SwiftUI
import Combine

/// `--foldarc-cover-size=466x678`: the camera's cover deck drawn at that
/// size (the Duo's cover's own, upright or across) and scaled into the
/// window — a preview on a phone of another shape, for the tests' pictures.
/// (A DEBUG build's: a release takes no such word.)
private let coverPreviewSize: CGSize? = {
    #if DEBUG
    let flag = "--foldarc-cover-size="
    guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(flag) })?.dropFirst(flag.count) else { return nil }
    let parts = raw.split(separator: "x").compactMap { Double($0) }
    guard parts.count == 2, parts[0] >= 200, parts[1] >= 200 else { return nil }
    return CGSize(width: parts[0], height: parts[1])
    #else
    return nil
    #endif
}()

struct PlayView: View {
    var close: () -> Void
    /// A fixed mode (render previews); nil = the mode the user last chose.
    var initialLayout: ScreenLayout?
    var deviceLidClosed: Bool?
    /// A game file to run on the real core instead of the Orbit Garden demo.
    var game: URL?
    /// Only the closed casing, for a lid closed over the library: nothing is
    /// drawn on the inner display, and `onReopen` hands back to the library
    /// once the window has settled there.
    var coverOnly = false
    /// 11-15: the lid shut over the library with 铅笔盒 or 画框 open: the
    /// cover is the box's lid, or the frame's scenery (over anything else of
    /// the library's, the console's shell).
    var coverInside: ConsoleApp?
    /// 11-15: the camera opens on its album (it was open inside when the lid shut).
    var cameraAlbum = false
    var onReopen: (() -> Void)?
    /// Started from the library on the iPhone Duo's cover, the game plays
    /// there (ControllerModeView's cover layout) until the lid opens; the
    /// handheld after that, and a lid closed then shows the casing again.
    @ViewState private var playsOnCover = false
    /// Start the game from its resume state ("继续上次" in the library).
    var resume = false
    /// One of the console's built-in programs instead of a game (round 23):
    /// 系统设置, or the first-time setup. It takes both LCDs and the keys;
    /// HOME and POWER leave it.
    var app: ConsoleApp?
    /// What the program needs from the library.
    var appGames: [GameRecord] = []
    var appRemove: (GameRecord) -> Void = { _ in }
    var appTestFiles: [URL] = []
    var appLaunchTestFile: (URL) -> Void = { _ in }
    /// The console's menu (round 26): what it opens, the library does.
    var appOpenHome: (ConsoleHomeRequest) -> Void = { _ in }
    /// 系统设置 and the like: the model of the one on the screens (round 30:
    /// a new one each time the menu opens one in place).
    @StateObject private var apps: ConsoleAppHolder
    /// Round 30: the program on the console's screens now — the one the play
    /// view was opened for (`app`), or one the menu opened in place (相机,
    /// 设置, 游戏记录, 主题, 说明书);
    /// nil: the software, or the menu over it.
    @ViewState private var running: ConsoleApp?
    /// Round 31: the small icon of the menu the program on the screens was
    /// opened from (屏幕亮度): its way out comes back onto it.
    @ViewState private var programShortcut: ConsoleHomeShortcut?
    /// b41: the program on the screens is 选电视, opened by TV模式's own button
    /// over the game: its way out goes back to the game, not the menu.
    @ViewState private var programReturnsToGame = false
    /// The program on the screens was started from the card in the slot
    /// (金卡带's films): left, the menu is on the card again.
    @ViewState private var programFromCard = false
    /// 相机 (round 25): made with every play view, started only for 相机.
    @StateObject private var camera = CameraAppModel()
    /// Round 32: 游戏笔记 (GameNotes.swift), a program of the menu.
    @StateObject private var notes = GameNotesModel()
    /// The console's menu as a program (round 26), started only for it.
    @StateObject private var homeProgram = ConsoleHomeProgram()
    /// Power saving keeps the screens a little darker (round 23).
    @ObservedObject private var system = ConsoleSettings.shared
    @StateObject private var session = DemoSession()
    @StateObject private var azahar = AzaharSession()
    @ViewState private var layout: ScreenLayout
    /// 桌面模式's lid, degrees folded from open flat (HingeHandle).
    @ViewState private var lidTilt = 0.0
    /// The HOME menu, drawn in the console's screens (SystemMenu.swift).
    @StateObject private var homeMenu = HomeMenuModel()
    /// The lower LCD's width on screen (LowerScreenWidthKey): under
    /// HomeMenuModel.minimumScreenWidth the menu takes the whole display.
    @ViewState private var lowerScreenWidth = 0.0
    private var homeInScreens: Bool { lowerScreenWidth >= HomeMenuModel.minimumScreenWidth }
    /// The casing colour, kept across games and launches like a real shell.
    @AppStorage("foldarc.finish") private var finish: ShellFinish = .aqua
    @ViewState private var previewFraction = 0.5
    @ViewState private var previewGap = 0.0
    @ViewState private var showGuides = false
    @ViewState private var showingHome = false
    @ViewState private var resumeAfterMenu = false
    @ViewState private var previewClosed = false
    /// Said once that the play view is on screen (LibraryView's curtain).
    @ViewState private var announced = false
    /// The core's frames seen so far (up to 8), and whether the wait for
    /// them has gone on long enough (4 s) to lift the curtain anyway.
    @ViewState private var framesShown = 0
    @ViewState private var waitedLongEnough = false
    /// Round 32: POWER saves the progress and leaves, once; no menu, no question.
    @ViewState private var poweringOff = false
    /// HOME Menu "关闭软件" asks first.
    @ViewState private var confirmingClose = false
    /// Last real change of the lid (a display switch also passes through
    /// the inactive scene phase; no resume state is saved around it).
    @ViewState private var lastLidChange = Date.distantPast
    /// "继续上次" could not use the saved state: why, shown in an alert
    /// while the game waits paused at its start. Only the HOME status line
    /// said so before, and the frame rate replaced it within a second
    /// (10-28: a state from another core version and a damaged state both
    /// started the game over without a word on screen).
    @ViewState private var resumeProblem: String?
    /// HOME Menu title and icon of the running game (from its SMDH).
    @ViewState private var gameInfo: SMDH?
    /// This view's hold on the external controller (GameControllerInput).
    @ViewState private var controllerHold: UUID?
    @AppStorage("foldarc.haptics") private var haptics = true
    /// Round 31 (接手柄自动换模式): a controller connected brings 手柄模式
    /// (its screens big, the keys the controller's), and the mode before it
    /// back when it goes; not stored as the chosen mode meanwhile.
    @ObservedObject private var pads = GameControllerInput.shared
    @AppStorage(GamepadLayout.autoModeKey) private var padAutoMode = true
    @ViewState private var modeBeforePad: ScreenLayout?
    /// 11-07 沉浸模式 chosen with no controller connected (or the controller
    /// gone): 手柄模式 stands in until one connects, then 沉浸模式 again.
    @ViewState private var immersiveWaiting = false
    /// 11-07: turned on its side,
    /// 掌机模式 and 桌面模式 become 手柄模式 (its across layout: the screens in
    /// the middle, the keys at the sides), and upright again the mode
    /// before comes back; not stored as the chosen mode meanwhile, and a
    /// mode chosen while on its side stays (SidewaysMode). On its side: a
    /// phone's window wider than tall; a Duo's inner display held across,
    /// like a book (CoverOrientationPolicy's reading of the hold — a game
    /// keeps the handheld's one orientation, so its window does not say).
    @ViewState private var sidewaysState = SidewaysMode.State()
    @ViewState private var windowWide = false
    /// 11-07: 掌机模式 upright on the Duo as the
    /// console (掌机机身) or as 手柄模式 in a style chosen for it (DuoUprightLook).
    @AppStorage(DuoUprightLook.key) private var duoUprightLook = DuoUprightLook.console
    @AppStorage(ConsoleHaptics.strengthKey) private var hapticStrength = ConsoleHaptics.defaultStrength
    @AppStorage("foldarc.brightness") private var brightness = 1.0
    #if os(iOS)
    // Which built-in display the window is on, published from UIKit hooks.
    @ObservedObject private var displayRole = DisplayRoleMonitor.shared
    // On the cover display any UIKit rotation (a sheet dismissal triggered
    // animated ones in the trace) must be instant, because the print is
    // counter-rotated to stay fixed on the casing.
    @AppStorage("foldarc.debug.snapTransitions") private var snapTransitions = true
    @AppStorage("foldarc.debug.traceOverlay") private var traceOverlay = false
    // Off unless asked for (HOME › 开发者): saving a picture of the window
    // on every frame for the first seconds of play held the main thread up
    // just as the game came in (10-30 profile; debug builds only).
    @AppStorage("foldarc.debug.captureFrames") private var captureFrames = false
    #endif
    #if os(iOS)
    // UIKit scene lifecycle on iOS (see FoldArcAppDelegate): the scene phase
    // comes from the scene delegate, not from a SwiftUI scene.
    @ObservedObject private var appPhase = AppScenePhase.shared
    private var scenePhase: ScenePhase { appPhase.phase }
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif
    @FocusState private var focused: Bool
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    init(close: @escaping () -> Void, initialLayout: ScreenLayout? = nil,
         deviceLidClosed: Bool? = nil, initiallyClosed: Bool = false, game: URL? = nil,
         coverOnly: Bool = false, coverInside: ConsoleApp? = nil, onReopen: (() -> Void)? = nil, playsOnCover: Bool = false, resume: Bool = false,
         app: ConsoleApp? = nil, cameraAlbum: Bool = false, appGames: [GameRecord] = [], appRemove: @escaping (GameRecord) -> Void = { _ in },
         appTestFiles: [URL] = [], appLaunchTestFile: @escaping (URL) -> Void = { _ in },
         appOpenHome: @escaping (ConsoleHomeRequest) -> Void = { _ in }) {
        self.close = close
        self.appOpenHome = appOpenHome
        self.resume = resume
        self.app = app
        self.appGames = appGames
        self.appRemove = appRemove
        self.appTestFiles = appTestFiles
        self.appLaunchTestFile = appLaunchTestFile
        _apps = StateObject(wrappedValue: ConsoleAppHolder(app: app ?? .settings))
        _running = ViewState(initialValue: app)
        self.initialLayout = initialLayout
        self.deviceLidClosed = deviceLidClosed
        self.game = game
        self.coverOnly = coverOnly
        self.coverInside = coverInside
        self.cameraAlbum = cameraAlbum
        self.onReopen = onReopen
        _playsOnCover = ViewState(initialValue: playsOnCover && !coverOnly && deviceLidClosed != nil)
        _layout = ViewState(initialValue: initialLayout ?? ScreenLayout.stored)
        #if DEBUG
        _previewClosed = ViewState(initialValue: initiallyClosed || ProcessInfo.processInfo.arguments.contains("--foldarc-cover"))
        #else
        _previewClosed = ViewState(initialValue: initiallyClosed)
        #endif
    }
    /// Hinge state: drives sleeping/pausing and menu dismissal.
    private var lidClosed: Bool { deviceLidClosed ?? previewClosed }
    /// The lid shut over the console, or the Duo stood half open with the
    /// system showing the cover (the hinge is not "closed" then), and not a
    /// game played on the cover: the game sleeps, the keys do nothing.
    private var asleep: Bool { (lidClosed || showsCover) && !playsOnCover }
    @ObservedObject private var hinge = HingePosture.shared
    /// 11-05: the camera running when the cover is what shows goes on
    /// there — the control deck with the lid shut, the tent (帐篷) with the
    /// console stood half open (the system has put FoldArc on the cover while
    /// the hinge is half open).
    private var cameraDeck: CameraAppModel.Deck {
        // (11-15: 相册 too — what is open inside goes on outside)
        guard running == .camera || running == .album else { return .screens }
        #if DEBUG
        if let forced = Self.forcedCameraDeck { return forced }
        #endif
        guard showsCover, !coverOnly else { return .screens }
        return hinge.status == .partiallyOpen ? .tent : .closed
    }
    /// 画框 on the cover (FrameStand): 画框 open inside and the system
    /// showing Zero EMU on the cover, the Duo shut or stood half open like a
    /// tent, nothing played on the cover. It does not come up by itself over
    /// a game or the console's menu: the cover is the shell then.
    private var frameStands: Bool {
        #if DEBUG
        if Self.forcedFrameStand { return true }
        #endif
        return FrameStand.shows(frameOpen: (coverOnly ? coverInside : running) == .pictureFrame, onCover: showsCover, playsOnCover: playsOnCover)
    }
    #if DEBUG
    /// `--foldarc-frame-stand`: the standing frame drawn where the console is
    /// (screenshots and UI tests without standing the simulator's Duo up).
    private static let forcedFrameStand = ProcessInfo.processInfo.arguments.contains("--foldarc-frame-stand")
    #endif
    #if DEBUG
    /// `--foldarc-camera-deck=closed|tent`: the camera's cover deck drawn
    /// where the console is (screenshots and UI tests without shutting the
    /// lid of the simulator someone is using).
    private static let forcedCameraDeck: CameraAppModel.Deck? = ProcessInfo.processInfo.arguments
        .first { $0.hasPrefix("--foldarc-camera-deck=") }
        .flatMap { CameraAppModel.Deck(rawValue: String($0.dropFirst("--foldarc-camera-deck=".count))) }
    #endif
    /// What to draw. On Duo the hinge reports "closed" ~100-400 ms before
    /// the window actually moves to the outer display (and reports a stale
    /// "closed" once more right after moving to the inner one), which drew
    /// the sideways cover on the inner screen and the handheld on the outer
    /// screen for a few frames. The casing therefore follows the display the
    /// window is on; the hinge only pauses the game.
    private var showsCover: Bool {
        #if os(iOS)
        if deviceLidClosed != nil, let onOuterDisplay = displayRole.isOuter { return onOuterDisplay }
        #endif
        return lidClosed
    }

    /// On Duo hardware the handheld appears only once the inner display has
    /// settled in the handheld orientation (DisplayRoleMonitor); the system
    /// may hand the window over in the other portrait orientation first and
    /// the correction must not be seen. Previews and other devices: always.
    private var innerVisible: Bool {
        #if os(iOS)
        guard deviceLidClosed != nil else { return true }
        return displayRole.innerSettled
        #else
        return true
        #endif
    }

    /// The game is what the person sees: the handheld settled on the inner
    /// display, or the game played on the cover.
    private var onScreen: Bool { (!showsCover && innerVisible) || (showsCover && playsOnCover) }

    /// Black behind everything while the window is moving between Duo's
    /// displays, until the new one has settled (DisplayRoleMonitor.switchingDisplay).
    private var blackBackdrop: Bool {
        #if os(iOS)
        return deviceLidClosed != nil && displayRole.switchingDisplay
        #else
        return false
        #endif
    }

    var body: some View {
        // Keep presentation and lifecycle modifiers on one stable container.
        // A transparent Group forwards them to the branch being replaced.
        ZStack {
            // The instant camera's print comes out here when the Duo is opened after a picture.
            if running == .camera, cameraDeck == .screens, let print = camera.printToCome {
                InstantPrintOut(model: camera, url: print).zIndex(1000).transition(.opacity)
            }
            if cameraDeck != .screens {
                if let size = coverPreviewSize, !(deviceLidClosed != nil && showsCover) {
                    // (A preview at the cover's own size, scaled into this window.)
                    GeometryReader { geo in
                        CameraCoverDeck(model: camera, finish: finish, fromDevice: false, tent: cameraDeck == .tent,
                                        previewBottom: size.height > size.width ? 34 : 21,
                                        previewRegions: size.height > size.width ? [CGRect(x: 399, y: 29, width: 37, height: 37), CGRect(x: 382, y: 0, width: 84, height: 82)] : [])
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(min(geo.size.width / size.width, geo.size.height / size.height))
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                } else {
                    CameraCoverDeck(model: camera, finish: finish, fromDevice: deviceLidClosed != nil && showsCover, tent: cameraDeck == .tent)
                }
            } else if frameStands {
                // 画框 open inside: the cover is its scenery, shut or stood up like a tent.
                PictureFrameStand(fromDevice: deviceLidClosed != nil && showsCover)
            } else if showsCover && playsOnCover {
                // The game on the cover, full screen.
                ControllerModeView(session: session, finish: finish.innerShell, outer: finish, brightness: shownBrightness, haptics: haptics,
                                   showHome: toggleHome, showPower: openPower, cover: true, immersive: layout == .immersive)
            } else if showsCover {
                // (closed over the library, 返回游戏库 brings the library onto the cover)
                // 11-15: the cover goes with what is inside: 铅笔盒's lid over
                // the box, the console's shell over the console.
                ClosedConsoleView(finish: $finish, fromDevice: deviceLidClosed != nil, showsBack: true,
                                  lid: (coverOnly ? coverInside : running) == .tinBox,
                                  openPreview: openLid, close: closeSoftware)
            } else if coverOnly {
                Color.clear
                    .onChange(of: innerVisible, initial: true) { _, visible in if visible { onReopen?() } }
            } else if presentedLayout == .handheld {
                // On Duo hardware the handheld is drawn in the inner panel's
                // fixed frame: lower screen on the side-button half, whatever
                // orientation the system gives the window.
                HandheldFixedFrame(enabled: deviceLidClosed != nil) { snapshot, insets in
                    // Round 31: a two-tone finish's faces are its inner
                    // colour, the hinge and the rim its outer one (as on the
                    // console in the library).
                    DuoConsoleView(session: session, finish: finish.innerShell, outer: finish, brightness: shownBrightness, haptics: haptics,
                                   previewFraction: previewFraction, previewGap: previewGap, showGuides: showGuides,
                                   previewSnapshot: snapshot, previewInsets: insets,
                                   showHome: toggleHome, showHelp: openHelp, close: closeSoftware,
                                   showPower: openPower)
                }
                .opacity(innerVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: innerVisible)
            } else if presentedLayout == .tabletop {
                tabletopPlay
            } else {
                // 手柄模式, and TV模式 (round 31): the iPhone is the controller,
                // its upper screen on the TV while one is connected.
                // 11-07: and 沉浸模式 (the game's screens alone, with a controller);
                // 掌机模式 and 桌面模式 on a Duo held across, 掌机模式
                // upright in a style chosen for it (presentedLayout).
                ControllerModeView(session: session, finish: finish.innerShell, outer: finish, brightness: shownBrightness, haptics: haptics,
                                   showHome: toggleHome, showPower: openPower, tv: layout == .tv, chooseTV: { openTVChooser() },
                                   immersive: layout == .immersive)
            }
            // Not over the camera's deck or tent (b31: a phone's full-screen
            // camera covered the tent DEBUG draws, and the UI test's touch
            // went to its 拍照, 918-920).
            // (铅笔盒 always: it opens over the whole display, its hinge on a Duo's fold.)
            if layer != .none && (!homeInScreens || layer == .program(.tinBox)) && (!showsCover || playsOnCover) && !coverOnly && cameraDeck == .screens && !frameStands {
                fullScreenLayer
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        // The HOME menu takes over the two LCDs while it is open (round 17):
        // the consoles draw these instead of the game. On LCDs too small to
        // read it in (a phone's 掌机模式 / 桌面模式) it covers the display.
        // A built-in program has them for as long as it runs (round 23).
        .environment(\.screenOverlay, screenOverlay)
        // The system keyboard (a name typed in 系统设置) comes up over the
        // console; the console stays where it is.
        .ignoresSafeArea(.keyboard)
        .onPreferenceChange(LowerScreenWidthKey.self) { lowerScreenWidth = $0 }
        // After a lid close or open, black until the display has settled: the
        // casing or the handheld then comes up from black, like a screen
        // turning on, and a turn the system still makes during the swap is
        // not seen (see blackBackdrop). Animated on its own layer only.
        .background {
            Color.black.opacity(blackBackdrop ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: blackBackdrop)
                .ignoresSafeArea()
        }
        // Drawn by the GPU in its own layer (round 21: Core Graphics drew it
        // on the CPU, full screen, several times as the game came in).
        .background(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.055)], center: .init(x: 0.5, y: 0.35), startRadius: 20, endRadius: 800).drawingGroup())
        // Not over the closed casing: with the lid closed the alert waits and
        // comes back once the handheld is settled on the inner display again
        // (the game stays paused meanwhile), not while the window is still
        // being turned. Its buttons settle it; the write-back SwiftUI makes
        // while dismissing (inside a view update) must not publish anything.
        .alert("没能继续上次的进度", isPresented: Binding(get: { resumeProblem != nil && onScreen }, set: { _ in })) {
            Button("从头开始") { startOverAfterResumeProblem() }
            Button("返回游戏库") { resumeProblem = nil; closeSoftware() }
        } message: {
            Text((resumeProblem ?? "") + String(localized: "\n游戏会从头开始。"))
        }
        // The software cannot go on (a CPU exception, missing system files,
        // the software ending itself): say so instead of a stopped picture.
        // Same rules as the alert above.
        .alert(azahar.softwareStop?.title ?? String(localized: "软件已停止运行"),
               isPresented: Binding(get: { azahar.softwareStop != nil && onScreen }, set: { _ in })) {
            Button("关闭软件") { closeSoftware() }
        } message: {
            Text(azahar.softwareStop?.message ?? "")
        }
        .onChange(of: azahar.softwareStop) { _, stop in if stop != nil { session.setPaused(true) } }
        // Software running keeps the iPhone awake: a controller's keys, or
        // the TV with the phone put down, are not touches. Paused — HOME up,
        // the lid shut, Zero not in front — it may sleep again.
        .onChange(of: app == nil && !coverOnly && !session.paused, initial: true) { _, playing in ScreenAwake.set("software", playing) }
        #if os(iOS)
        // On the hardware the status bar stays hidden across the swap between
        // casing and handheld; set per branch it flashed for ~0.15 s on the
        // cover while the views were exchanged (10-27 recording). On a phone
        // too since the 15th round: a handheld plays full screen, and the
        // white status text vanished against the light shells.
        .statusBarHidden(true)
        #endif
        .foregroundStyle(Color(white: 0.91))
        // 11-07: whether the window is wider than tall (a phone on its side).
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width > proxy.size.height * 1.1, initial: true) { _, wide in
                        if windowWide != wide { windowWide = wide }
                    }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
        #if os(iOS)
        .background {
            // Keep the outer-display policy alive across Duo's inner/outer
            // view replacement. Releasing it on open and acquiring it after
            // close causes a visible corrective rotation on the first frame.
            // The policy recognizes the actual screen so its portrait mask
            // applies only outside. Ordinary iPhone previews keep their scope.
            if deviceLidClosed != nil || lidClosed {
                CoverOrientationLock(deviceLidClosed: deviceLidClosed, captureFrames: captureFrames).frame(width: 0, height: 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            if deviceLidClosed != nil {
                // Hears the display migration and publishes which screen the
                // window is on (see DisplayMigrationHost).
                DisplayMigrationHost(snapTransitions: snapTransitions).frame(width: 0, height: 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            #if DEBUG
            if traceOverlay { TraceOverlay().padding(.top, 40) }
            #endif
        }
        #endif
        #if os(macOS)
        // Whole-console keyboard focus is for the Mac preview. On iOS it
        // creates a focus halo over the touch controls in the Simulator.
        .focusable().focused($focused)
        .onKeyPress { press in
            guard !asleep else { return .ignored }
            if press.key == .escape { toggleHome(); return .handled }
            let map: [KeyEquivalent: PadButton] = [.upArrow: .up, .downArrow: .down, .leftArrow: .left, .rightArrow: .right,
                "w": .up, "s": .down, "a": .left, "d": .right, "j": .a, "k": .b, "u": .x, "i": .y, "q": .l, "e": .r]
            if layer != .none {
                if press.key == .return { _ = routeKey(.a, down: true); return .handled }
                if let key = map[press.key] { _ = routeKey(key, down: true); return .handled }
                return .ignored
            }
            if press.key == .return { session.keyboard(.start); return .handled }
            if let key = map[press.key] { session.keyboard(key); return .handled }
            return .ignored
        }
        #endif
        .onReceive(timer) { now in
            session.tick(now)
            // Not while paused: the HOME menu keeps the last line (the frame
            // rate before the pause, or what a save or load reported) instead
            // of turning it into "0 fps" a second later.
            // The software listening for a breath (it has opened its
            // microphone): the iPhone's microphone is on meanwhile.
            if Int(now.timeIntervalSinceReferenceDate * 60) % 60 == 0 {
                session.listenMic("software", session.core != nil && !session.paused && azahar.micListening)
            }
            if session.core != nil, !session.paused, Int(now.timeIntervalSinceReferenceDate * 60) % 60 == 0 {
                // No measurement yet in the first second after start: leave
                // the rate out rather than show "0 fps" (a stalled core keeps
                // its last rate; the rate is only measured on presented frames).
                let rate = azahar.framesPerSecond > 0 ? " · \(Int(azahar.framesPerSecond.rounded())) fps" : ""
                session.status = azahar.status + rate + (azahar.lastMessage.map { " · \($0)" } ?? "")
            }
        }
        .onAppear {
            focused = true; bootCoreIfNeeded(); ConsoleHaptics.shared.warmUp()
            #if os(iOS)
            // 11-07: how the Duo is held, read from the start (a game started
            // held across comes up in 手柄模式). (b70c: the play view can come
            // up before the hinge's first report — 1031 on the iPhone Duo —
            // so also once it has come, below.)
            if !coverOnly {
                if deviceLidClosed != nil { CoverOrientationPolicy.shared.watchHoldForPlay() }
                #if DEBUG
                CoverOrientationPolicy.shared.startHoldScript()
                #endif
            }
            #endif
            if let app {
                // A built-in program: its cursor takes the keys, HOME and
                // POWER (and its own way out) go back to the library.
                startProgram(app, fresh: false)
                LastRun.note("app \(app.rawValue)")
            }
            // Round 30: the keys go to whatever is on the screens over the
            // software (a program, the menu, one of its pages), else to it.
            session.menuInput = { key, down in routeKey(key, down: down) }
            homeMenu.exitToMenu = { closeHomePage() }
            // 游戏记录 (round 20): the time on screen counts for this software.
            if !coverOnly && app == nil {
                PlayLog.shared.begin(id: game?.lastPathComponent ?? "demo",
                                     title: game?.deletingPathExtension().lastPathComponent ?? "Orbit Garden")
                // TV输出 (round 30): with a TV connected, its screens there.
                TVOutput.shared.attach(owner: session, demo: game == nil ? session : nil, core: game == nil ? nil : azahar,
                                       title: game?.deletingPathExtension().lastPathComponent ?? "Orbit Garden")
            }
            // Round 31: the TV gets the screens in TV模式 (游玩模式) only.
            TVOutput.shared.setTVMode(layout == .tv)
            // 存档同步 (round 31) leaves a running game's saves alone.
            if game != nil, !coverOnly { SaveSyncModel.shared.gameRunning = true }
            #if DEBUG
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(2050))
                FrameMeter.shared.begin("play.steady")
                FrameMeter.shared.end(after: 3)
            }
            // The input script drives the demo too (round 22: checking that
            // its screens still draw what changes).
            if game == nil, !coverOnly { runCoreInputSelfTestIfRequested() }
            // `--foldarc-auto-home=<seconds>[:<keys>]` (round 30): HOME that
            // long after the play view appeared (in a program: the program's
            // keys), then the keys (a, b, x, y, l, r, up, down, left, right,
            // start, select, home), one every 0.7 s from 1.5 s after
            // (screenshots of the menu over the software without a UI test).
            if !coverOnly, let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-auto-home=") }) {
                let parts = value.dropFirst("--foldarc-auto-home=".count).split(separator: ":").map(String.init)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int((Double(parts.first ?? "2") ?? 2) * 1000)))
                    if app == nil { NSLog("[home] debug: HOME"); toggleHome() }
                    guard parts.count > 1 else { return }
                    try? await Task.sleep(for: .milliseconds(1500))
                    let keys: [String: PadButton] = ["a": .a, "b": .b, "x": .x, "y": .y, "l": .l, "r": .r, "up": .up, "down": .down,
                                                     "left": .left, "right": .right, "start": .start, "select": .select]
                    for name in parts[1].split(separator: ",").map(String.init) {
                        NSLog("[home] debug: key %@", name)
                        if name == "home" { toggleHome() } else if let key = keys[name] { _ = routeKey(key, down: true); _ = routeKey(key, down: false) }
                        try? await Task.sleep(for: .milliseconds(700))
                    }
                }
            }
            // `--foldarc-finish-tour-play=<seconds>` (round 31): every finish
            // on the handheld in turn, that long each, "[tour] <n> <finish>"
            // logged as each comes (the probe's screenshot follows; the
            // user's colour is put back by the probe).
            if !coverOnly, let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-finish-tour-play=") }) {
                let seconds = Double(value.dropFirst("--foldarc-finish-tour-play=".count)) ?? 3
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(2500))
                    for (index, item) in ShellFinish.allCases.enumerated() {
                        finish = item
                        NSLog("[tour] %d %@", index + 1, item.rawValue)
                        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                    }
                    NSLog("[tour] done")
                }
            }
            // `--foldarc-auto-close=<seconds>`: back to the library that long
            // after the game appeared (recordings of both changes).
            if !coverOnly, let after = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-auto-close=") })
                .flatMap({ Double($0.dropFirst("--foldarc-auto-close=".count)) }) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(after * 1000)))
                    NSLog("[stage] debug: auto close")
                    closeSoftware()
                }
            }
            // `--foldarc-auto-power=<seconds>` (round 32): POWER that long
            // after the software appeared (recordings of the save-and-leave).
            if !coverOnly, let after = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-auto-power=") })
                .flatMap({ Double($0.dropFirst("--foldarc-auto-power=".count)) }) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(after * 1000)))
                    NSLog("[play] debug: auto POWER")
                    openPower()
                }
            }
            #endif
        }
        // In place once the handheld is on screen (on iPhone Duo it comes up
        // over 0.2 s once the inner display has settled) with something on
        // its screens: LibraryView lifts the curtain it put up for the
        // change (announceIfReady).
        .onChange(of: innerVisible, initial: true) { _, _ in announceIfReady() }
        .onReceive(azahar.$top) { image in
            guard image != nil, framesShown < 8 else { return }
            framesShown += 1
            if framesShown == 8 { announceIfReady() }
        }
        .onChange(of: resumeProblem) { _, _ in announceIfReady() }
        // 相机 runs only while the console is open, on screen and FoldArc in
        // the foreground (round 25).
        .onChange(of: cameraAwake, initial: true) { _, awake in if running == .camera { camera.setAwake(awake) } }
        .onChange(of: cameraDeck, initial: true) { _, deck in camera.setDeck(deck) }
        .onChange(of: azahar.softwareStop) { _, _ in announceIfReady() }
        .task {
            try? await Task.sleep(for: .seconds(4))
            waitedLongEnough = true
            announceIfReady()
        }
        .task(id: game) {
            guard let game else { gameInfo = nil; return }
            gameInfo = await Task.detached(priority: .utility) { SMDH.read(contentsOf: game) }.value
            if let title = gameInfo?.preferredTitle?.short, !coverOnly { PlayLog.shared.retitle(title) }
        }
        .onDisappear {
            #if os(iOS)
            if !coverOnly { CoverOrientationPolicy.shared.setPlayFollowsHold(false) }
            #endif
            if running == .camera || app == .camera || running == .album || app == .album { camera.close() }
            if running == .notes || app == .notes { notes.closeProgram() }
            // Nothing of this console listens to the microphone any more.
            for reason in ["software", "camera", "mic-test"] { session.listenMic(reason, false) }
            if !coverOnly && app == nil { PlayLog.shared.end() }
            TVOutput.shared.detach(owner: session)
            TVOutput.shared.setTVMode(ScreenLayout.stored == .tv)
            if game != nil, !coverOnly { SaveSyncModel.shared.gameRunning = false }
            ConsoleHaptics.shared.coolDown()
            GameControllerInput.shared.detach(controllerHold); controllerHold = nil
            if !coverOnly { GameControllerInput.shared.homeForApp = false }
            session.setPaused(true); if game != nil { azahar.stop() }
            ScreenAwake.set("software", false)
        }
        .onReceive(GameControllerInput.shared.$notice.dropFirst()) { session.status = $0 }
        .onChange(of: scenePhase) { old, phase in
            if old == .active, phase != .active { saveResumeState() }
            session.setSuspended(phase != .active)
            // A real background transition remains paused on return. A brief
            // inactive interval while displays switch does not cancel lid wake.
            if phase == .background { session.setPaused(true); resumeAfterMenu = false }
            if phase == .active { ConsoleHaptics.shared.warmUp() } else if phase == .background { ConsoleHaptics.shared.coolDown() }
        }
        .onChange(of: layout) { _, mode in
            session.releaseAll()
            lidTilt = 0
            // 11-07 沉浸模式: the controller's Home is Zero's while it is up.
            GameControllerInput.shared.homeForApp = mode == .immersive
            if mode == .immersive, pads.padName == nil, initialLayout == nil, !coverOnly { waitForController(); return }
            if initialLayout == nil, modeBeforePad == nil, sidewaysState.before == nil, !immersiveWaiting { UserDefaults.standard.set(mode.rawValue, forKey: ScreenLayout.defaultsKey) }
            TVOutput.shared.setTVMode(mode == .tv)
            NSLog("[play] mode %@%@%@", mode.rawValue, modeBeforePad == nil ? "" : " (a controller is connected)", sidewaysState.before == nil ? "" : " (on its side)")
        }
        .onChange(of: pads.padName != nil, initial: true) { _, connected in padChanged(connected) }
        // 11-07: on its side → 手柄模式, upright → the mode before.
        .onChange(of: heldSideways, initial: true) { _, _ in sidewaysCheck() }
        .onChange(of: showsCover) { _, _ in sidewaysCheck() }
        .onChange(of: running) { _, _ in sidewaysCheck(); logLayer() }
        #if os(iOS)
        .onChange(of: followsHold, initial: true) { _, on in CoverOrientationPolicy.shared.setPlayFollowsHold(on) }
        .onChange(of: deviceLidClosed != nil) { _, known in if known, !coverOnly { CoverOrientationPolicy.shared.watchHoldForPlay() } }
        #endif
        #if os(iOS)
        .onChange(of: showsCover) { _, cover in
            OrientationTrace.shared.event("playview showsCover=\(cover) role=\(displayRole.isOuter.map { $0 ? "outer" : "inner" } ?? "unknown") lid=\(lidClosed)")
            // A game played on the cover goes on as the handheld once
            // the lid is open; shut again, it is the casing.
            if !cover && playsOnCover {
                playsOnCover = false
                NSLog("[display] the lid opened over a game on the cover: the handheld")
            }
            if cover && !playsOnCover { dismissMenusForCover() }
            // 11-15: 铅笔盒 open here, shut and opened with the lid: heard (its lid then on the cover, the box open)
            if running == .tinBox, !coverOnly { ConsoleSounds.shared.play(cover ? .lidShut : .lidOpen) }
        }
        #endif
        .onChange(of: asleep, initial: true) { old, closed in
            if old != closed { lastLidChange = Date() }
            #if os(iOS)
            OrientationTrace.shared.event("playview lidClosed=\(lidClosed) asleep=\(closed) device=\(deviceLidClosed.map { String($0) } ?? "nil") preview=\(previewClosed) showsCover=\(showsCover) coverPlay=\(playsOnCover)")
            #endif
            session.setLidClosed(closed)
            if !coverOnly && app == nil { if closed { PlayLog.shared.pause("lid") } else { PlayLog.shared.resume("lid") } }
            if closed { dismissMenusForCover() }
            // The controller's handler reads the lid state captured with it
            // (`deviceLidClosed` is a plain property of this view): take the
            // controller again whenever it changes, and on appearing.
            takeController()
        }
    }

    /// 桌面模式: the whole console on the screen and nothing scrolls. The hinge
    /// works (HingeHandle): drag to fold the lid, tap to click between open
    /// flat and the slight fold, fold past the stop to shut it and sleep
    /// (the cover; lift it to open). On iPhone Duo the real hinge decides
    /// sleep, so the drawn lid only tilts.
    private var tabletopPlay: some View {
        VStack(spacing: 10) {
            tabletopBar.padding(.horizontal, 20).padding(.top, 10)
            Spacer(minLength: 0)
            HardwareConsole(session: session, finish: finish.innerShell, outer: finish, lidTilt: lidTilt,
                            hinge: HingeControl(tilt: $lidTilt, shut: deviceLidClosed == nil ? { previewClosed = true } : nil, haptics: haptics),
                            brightness: shownBrightness, haptics: haptics, showHome: toggleHome, showHelp: openHelp, showPower: openPower)
                .frame(maxWidth: 720)
                .padding(.horizontal, 14)
            // The shoulder buttons stay with the console (not at the bottom
            // edge with a gap above them on a tall phone).
            shoulderButtons.padding(.horizontal, 20).padding(.top, 6)
            Spacer(minLength: 0)
            Text(session.status).font(.system(size: 11)).foregroundStyle(Palette.muted)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(minHeight: 30).padding(.horizontal, 20).padding(.bottom, 6)
        }
    }

    /// A title line. Everything else (the library, the settings) is in HOME,
    /// behind the console's own key (round 17).
    private var tabletopBar: some View {
        VStack(spacing: 2) {
            Text(game == nil ? "Orbit Garden" : runningTitle).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
            Text(ScreenLayout.tabletop.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
    }

    private var shoulderButtons: some View {
        HStack(spacing: 10) {
            shoulder(.l); shoulder(.zl)
            Spacer(minLength: 12)
            shoulder(.zr); shoulder(.r)
        }.frame(maxWidth: 560)
    }
    private func shoulder(_ key: PadButton) -> some View {
        ShoulderControl(key: key, haptics: haptics, press: session.press)
    }

    /// The lid lifted again on the cover preview: the console is back, open flat.
    private func openLid() {
        previewClosed = false
        lidTilt = 0
        ConsoleHaptics.shared.play(.lidOpen, enabled: haptics)
    }
    /// Take any sheet or alert down with the casing. Keep its pause reason,
    /// so opening cannot unexpectedly resume a paused game. No animation: an
    /// animated dismissal on the outer display re-evaluated the scene's
    /// orientation mid-flight and produced visible 0.3 s rotations.
    /// What the alert says when the resume state could not be used.
    /// AzaharSession's own refusals (another core version) are written for
    /// the player already; anything from the core or the file system is not.
    private static func resumeProblemText(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == "FoldArc.Azahar" { return error.localizedDescription }
        return String(localized: "保存的进度不完整或已损坏，没能读取。")
    }
    private func startOverAfterResumeProblem() {
        resumeProblem = nil
        focused = true
        session.setPaused(false)
    }

    /// Tells LibraryView that the game is on the screen, once: the handheld
    /// is shown and it has something on its screens: the demo at once, a
    /// game once the core has put 8 frames up (round 21: the curtain used
    /// to lift on the handheld with black screens while the core was still
    /// starting, and the game then popped in), a problem's alert at once;
    /// after 4 s whatever there is.
    private func announceIfReady() {
        guard !announced, innerVisible else { return }
        let content = game == nil || framesShown >= 8 || azahar.softwareStop != nil || resumeProblem != nil || waitedLongEnough
        guard content else { return }
        announced = true
        #if DEBUG
        NSLog("[stage] play ready: %d frames%@", framesShown, waitedLongEnough && framesShown < 8 && game != nil ? " (gave up waiting)" : "")
        #endif
        // A program on the console (round 26) says so sooner and asks for a
        // shorter calm than the demo, whose first second is uneven.
        let program = app != nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(program || game != nil ? 60 : 200))
            NotificationCenter.default.post(name: .foldArcScreenReady, object: program ? "program" : "play")
        }
    }

    /// Closing the software ends the session: unsaved progress
    /// is gone, and so is the resume state.
    private func closeSoftware() {
        if let game { SaveStates.removeResume(for: game) }
        close()
    }
    /// FoldArc is leaving the foreground with a game running: keep its state,
    /// so the session survives the system ending FoldArc in the background
    /// ("继续上次" in the library). Saved on the way out (scene inactive),
    /// while the GPU can still be used; Vulkan states read surfaces back
    /// from the GPU, which a backgrounded app may not do. Also with the lid
    /// closed (leaving FoldArc from the cover, the game asleep); the paused
    /// emulation thread still carries out the save. Not right after the lid
    /// moved: the display switch also passes through inactive.
    private func saveResumeState() {
        guard let game, session.core != nil, !azahar.loading, resumeProblem == nil, azahar.softwareStop == nil,
              Date().timeIntervalSince(lastLidChange) > 2 else { return }
        #if os(iOS)
        let task = UIApplication.shared.beginBackgroundTask(withName: "FoldArc.resume-state")
        #endif
        azahar.saveState(to: SaveStates.resume(for: game)) { _ in
            #if os(iOS)
            UIApplication.shared.endBackgroundTask(task)
            #endif
        }
    }
    private func bootCoreIfNeeded(selfTest: Bool = true) {
        guard let game, session.core == nil, !azahar.loading else { return }
        session.status = String(localized: "正在启动核心…")
        // The core loads off the main thread (Vulkan start-up takes seconds);
        // the casing stays live meanwhile.
        Task { @MainActor in
            // 11-22: 存档同步 copying saves as the game starts stops at its next file (gameRunning, set as the play
            // view comes); the game waits for that — a moment — so it never starts on a save being replaced.
            var waited = 0
            while SaveSyncModel.shared.running, waited < 100 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            do {
                try await azahar.load(game: game)
                var resumed: String?
                if resume, FileManager.default.fileExists(atPath: SaveStates.resume(for: game).path) {
                    // Load the state before the game runs a frame, then let
                    // the usual pause rules decide whether it runs.
                    session.status = String(localized: "正在恢复上次的进度…")
                    azahar.startPaused()
                    let url = SaveStates.resume(for: game)
                    let result = await withCheckedContinuation { continuation in
                        azahar.loadState(from: url) { continuation.resume(returning: $0) }
                    }
                    SaveStates.removeResume(for: game)   // used (or unusable) either way
                    switch result {
                    case .success: resumed = String(localized: "已从上次离开的地方继续")
                    case .failure(let error):
                        resumed = String(localized: "上次的进度没能恢复：\(error.localizedDescription)")
                        // Ask first; the game stays at its start until then.
                        // (A state that fails is rejected before it changes
                        // the emulation: by its JSON, Azahar's header check or
                        // decompression; the game is the fresh one.)
                        resumeProblem = Self.resumeProblemText(error)
                        session.setPaused(true)
                    }
                }
                session.core = azahar
                session.status = resumed ?? azahar.status
                if !session.paused { azahar.start() }
                #if DEBUG
                if selfTest { runCoreInputSelfTestIfRequested() }
                #endif
            } catch {
                session.status = String(localized: "核心启动失败：\(error.localizedDescription)")
            }
        }
    }

    #if DEBUG
    /// `--foldarc-core-input-test`: the Simulator offers no way to deliver
    /// real touches from this harness, so a scripted sequence drives the
    /// same `DemoSession` entry points the on-screen controls use. Each step
    /// is logged so a screenshot can be matched to the core's reaction.
    /// An optional `--foldarc-core-input-script=5:Y,10:B,15:T0.50x0.30`
    /// replaces the default sequence: `<seconds>:<BUTTON>` taps a button for
    /// 150 ms, `<seconds>:T<x>x<y>` touches the bottom screen (0…1) for 200 ms
    /// (`F<x>x<y>`: the same as a finger on its view would),
    /// `<seconds>:DEPTH<percent>` moves the 3D slider, `<seconds>:MIC<seconds>`
    /// holds MIC (round 16),
    /// `<seconds>:SAVE` / `LOAD` exercise the save-state path; `<seconds>:HOME`
    /// opens the HOME menu; `<seconds>:RESTART` stops the core and loads the
    /// game again in place (the stop → load path that leaving a game for the
    /// library and starting another takes; the Vulkan context is destroyed and
    /// recreated); `<seconds>:MSGFLOOD` posts 200 000 identical core messages
    /// from a background thread (a core stuck repeating an error);
    /// `AUDIOINT[<seconds>]` / `AUDIOCFG` / `AUDIORESET` act out an audio interruption,
    /// an engine configuration change and a media-services reset
    /// (AzaharSession.debugSimulateAudio); `VC<input>` presses an input of the
    /// hidden virtual controller made by `--foldarc-virtual-controller`
    /// (GameControllerInput.debugVirtualInput).
    private func runCoreInputSelfTestIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--foldarc-core-input-test") else { return }
        var script = "5:Y,10:B,15:START,20:T0.50x0.50,25:B"
        if let custom = args.first(where: { $0.hasPrefix("--foldarc-core-input-script=") }) {
            script = String(custom.dropFirst("--foldarc-core-input-script=".count))
        }
        let names: [String: PadButton] = ["A": .a, "B": .b, "X": .x, "Y": .y, "L": .l, "R": .r, "ZL": .zl, "ZR": .zr,
                                          "START": .start, "SELECT": .select, "UP": .up, "DOWN": .down, "LEFT": .left, "RIGHT": .right]
        for step in script.split(separator: ",") {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let at = Double(parts[0]) else { continue }
            let token = parts[1].uppercased()
            let schedule: (Double, String, @escaping () -> Void) -> Void = { delay, label, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSLog("[azahar] input self-test: %@", label)
                    action()
                }
            }
            if token == "SAVE" { schedule(at, "save state") { session.save() }; continue }
            // DEPTH<percent>: the 3D slider; MIC<seconds>: hold MIC that long.
            if token.hasPrefix("DEPTH"), let percent = Double(token.dropFirst("DEPTH".count)) {
                schedule(at, "3D slider \(Int(percent))%") { session.setDepth3D(percent / 100) }
                continue
            }
            // VOL<percent>: the volume slider (round 21).
            if token.hasPrefix("VOL"), let percent = Double(token.dropFirst("VOL".count)) {
                schedule(at, "volume \(Int(percent))%") { ConsoleVolume.shared.level = percent / 100 }
                continue
            }
            if token.hasPrefix("MIC") {
                let seconds = Double(token.dropFirst("MIC".count)) ?? 1
                schedule(at, "MIC held") { session.setMicBlowing(true) }
                schedule(at + seconds, "MIC released") { session.setMicBlowing(false) }
                continue
            }
            if token == "HOME" { schedule(at, "home menu") { openHome() }; continue }
            if token == "LOAD" { schedule(at, "load state") { session.restore() }; continue }
            #if FOLDARC_CORE
            if token == "MSGFLOOD" {
                schedule(at, "message flood") {
                    guard let core = session.core else { return }
                    DispatchQueue.global(qos: .userInitiated).async {
                        for _ in 0..<200_000 { core.core(FALibretroCore.shared, didRequestMessage: "flood test") }
                        NSLog("[azahar] input self-test: message flood posted")
                    }
                }
                continue
            }
            #endif
            #if FOLDARC_CORE && os(iOS)
            if token.hasPrefix("AUDIOINT") || token == "AUDIOCFG" || token == "AUDIORESET" {
                // AUDIOINT<seconds>: how long the interruption lasts (default 6).
                let seconds = token.hasPrefix("AUDIOINT") ? Double(token.dropFirst("AUDIOINT".count)) ?? 6 : 6
                let event = token.hasPrefix("AUDIOINT") ? "AUDIOINT" : token
                schedule(at, "simulated \(token)") { azahar.debugSimulateAudio(event, seconds: seconds) }
                continue
            }
            #endif
            if token.hasPrefix("VC") {
                #if os(iOS)
                schedule(at, "virtual controller \(token.dropFirst(2))") { GameControllerInput.shared.debugVirtualInput(String(token.dropFirst(2))) }
                #endif
                continue
            }
            if token == "RESTART" {
                schedule(at, "restart core") { session.core = nil; azahar.stop(); bootCoreIfNeeded(selfTest: false) }
                continue
            }
            // F<x>X<y>: a finger on the touch screen, as the touch screen's
            // own view reports one (AzaharSession.finger: 按键点屏 and its hint
            // count it), down for 200 ms.
            if token.hasPrefix("F"), let x = token.dropFirst().split(separator: "X").first.flatMap({ Double($0) }),
               let y = token.dropFirst().split(separator: "X").last.flatMap({ Double($0) }) {
                let point = Point(x: x, y: y).clamped
                schedule(at, "finger \(x),\(y) down") { session.core?.finger(at: point) }
                schedule(at + 0.2, "finger up") { session.core?.finger(at: nil) }
                continue
            }
            if token.hasPrefix("T"), let x = token.dropFirst().split(separator: "X").first.flatMap({ Double($0) }),
               let y = token.dropFirst().split(separator: "X").last.flatMap({ Double($0) }) {
                let point = Point(x: x, y: y).clamped
                // The demo takes a touch as the beacon (round 22: the script
                // drives the demo too).
                schedule(at, "touch \(x),\(y) down") { if let core = session.core { core.setTouch(point, pressed: true) } else { session.touch(point) } }
                schedule(at + 0.2, "touch up") { session.core?.setTouch(nil, pressed: false) }
            } else if let button = names[token] {
                schedule(at, "\(token) down") { session.press(button, down: true) }
                schedule(at + 0.15, "\(token) up") { session.press(button, down: false) }
            }
        }
    }
    #endif

    /// An external controller plays this console while it is on screen. Its
    /// Home button opens HOME, and in HOME continues the game; losing the controller
    /// in the middle of play opens HOME too, so the game waits (nothing is
    /// held down any more either way).
    private func takeController() {
        let closed = asleep
        // While a menu or dialog is up (or the lid is closed) presses don't
        // reach the console, as with the on-screen keys and the keyboard;
        // releases always do.
        let blocked = { closed || showingHome || poweringOff || resumeProblem != nil || azahar.softwareStop != nil }
        // While HOME is open the session hands the keys to the menu (round 17).
        controllerHold = GameControllerInput.shared.attach(.init(
            press: { key, down in if showingHome || !down || !blocked() { session.press(key, down: down) } },
            directions: { session.setDirections(blocked() && !showingHome ? [] : $0) },
            circlePad: { session.setAnalog(blocked() ? Point(x: 0, y: 0) : $0) },
            cStick: { session.setCamera(blocked() ? Point(x: 0, y: 0) : $0) },
            home: {
                // Round 30: as the console's own HOME key.
                if layer != .none || !blocked() { toggleHome() }
            },
            lost: { if app == nil && !blocked() && !session.paused { openHome() } }))
    }

    private func dismissMenusForCover() {
        // 11-05: the camera goes on, on the cover (CameraCoverDeck). 11-15:
        // its album, 相册, 铅笔盒 and 画框 too — the cover goes with them.
        if let running, [.camera, .album, .tinBox, .pictureFrame].contains(running) { return }
        guard showingHome || resumeAfterMenu else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resumeAfterMenu = false; showingHome = false; confirmingClose = false
            programReturnsToGame = false
            homeMenu.close()
            // Round 30: a program the menu opened over the software goes too.
            if app == nil, let current = running {
                if current == .camera || current == .album { camera.close() }
                if current == .notes { notes.closeProgram() }
                running = nil
                session.runApp(nil)
            }
            homeProgram.dialog = nil
        }
    }
    private func beginMenu() { resumeAfterMenu = !session.paused; session.setPaused(true) }
    /// HOME in a game (round 30: the console's one menu, as in the library,
    /// over the suspended software; round 17 had a menu of its own here).
    /// In a built-in program HOME leaves it (round 23).
    private func openHome(page: HomeMenuModel.Page = .root) {
        if app != nil { leaveApp(); return }
        if showingHome { if page != .root { homeMenu.open(page) }; return }
        beginMenu()
        homeProgram.games = appGames
        homeProgram.keyTaps = session.core?.keyTaps ?? false
        homeProgram.speed = session.core?.speed ?? 1
        homeProgram.slot = session.core?.stateSlot ?? 1
        homeProgram.showSuspended(suspendedCard, shortcuts: menuShortcuts)
        homeProgram.open = { request in menuRequest(request) }
        homeProgram.leave = { resumeFromHome() }
        showingHome = true
        if page != .root { homeMenu.open(page) }
        logLayer()
    }
    /// 11-07: where the menu or a program is drawn (the run log says).
    private func logLayer() {
        guard layer != .none else { return }
        NSLog("[home] %@ %@ (lower LCD %.0f pt, %@)", String(describing: layer), homeInScreens ? "on the console's screens" : "over the whole display",
              lowerScreenWidth, layout.rawValue)
    }
    /// The HOME key: opens the menu, and in the menu goes back to the game
    /// (as the console's own HOME key returns to the suspended software);
    /// in a program the menu opened, back to the menu.
    private func toggleHome() {
        switch layer {
        case .program(let current):
            if app == current { leaveApp() } else { leaveProgram() }
        case .page:
            if app == nil { resumeFromHome() } else { closeHomePage() }
        case .menu:
            if homeProgram.dialog != nil { homeProgram.dialog = nil; return }
            if app == nil { resumeFromHome() } else { leaveApp() }
        case .none:
            if app == nil { openHome() } else { leaveApp() }
        }
    }
    private func openHelp() { if app == nil { openHome(page: .guide) } }
    /// b41: TV模式's 选电视 on the
    /// iPhone — 游玩模式's page of TVs on the screens over the paused game,
    /// as HOME would open it; its 返回 (or HOME) goes straight back to the game.
    private func openTVChooser() {
        guard app == nil, running == nil else { return }
        if !showingHome { openHome() }
        programShortcut = nil
        programReturnsToGame = true
        NSLog("[tv] 选电视 from TV模式's button")
        startProgram(.modes, page: .tvSet)
    }

    // MARK: The console's menu and its programs, in place (round 30)

    /// What is on the console's screens over the software.
    private enum Layer: Equatable { case none, program(ConsoleApp), menu, page }
    private var layer: Layer {
        if let running, running != .home { return .program(running) }
        if homeMenu.isOpen { return .page }
        if running == .home || showingHome { return .menu }
        return .none
    }
    /// A key of the console or a controller: for what is on the screens.
    private func routeKey(_ key: PadButton, down: Bool) -> Bool {
        switch layer {
        case .program(.camera), .program(.album): return camera.handle(key, down: down)
        case .program(.notes): return notes.handle(key, down: down)
        case .program: return apps.model.handle(key, down: down)
        case .page: return homeMenu.handle(key, down: down)
        case .menu: return homeProgram.handle(key, down: down)
        case .none: return false
        }
    }
    /// A program of the console's own takes the screens: the one the play
    /// view was opened for, or one the menu opens in place.
    private func startProgram(_ next: ConsoleApp, fresh: Bool = true, page: ConsoleAppModel.Page? = nil) {
        if running == .camera || running == .album, running != next { camera.close() }
        if running == .notes, next != .notes { notes.closeProgram() }
        running = next
        session.runApp(next)
        switch next {
        case .camera:
            // 相机 (round 25): L, R, A, the D-pad and B are the camera's.
            camera.session = session
            camera.leave = { leaveProgram() }
            camera.open()
            camera.setAwake(cameraAwake)
            // 11-15: its album was what was open when the lid shut over it.
            if !fresh, cameraAlbum { camera.openAlbum() }
        case .album:
            // Round 32: 相册 by itself (the camera's album, no feed).
            camera.session = session
            camera.leave = { leaveProgram() }
            camera.open(albumOnly: true)
        case .notes:
            // Round 32: 游戏笔记; with software suspended under the menu its
            // two screens can go onto a page.
            notes.screens = { app == nil ? lastFrames() : nil }
            notes.hasScreens = app == nil
            notes.softwareTitle = app == nil ? suspendedCard.title : nil
            notes.leave = { leaveProgram() }
            notes.openProgram()
        case .home:
            // The console's menu (round 26): the D-pad, A and B work it.
            homeProgram.games = appGames
            homeProgram.open = { request in menuRequest(request) }
            homeProgram.leave = { closeSoftware() }
        default:
            if fresh { apps.start(next, page: page) }
            apps.model.session = session
            apps.model.leave = { leaveProgram() }
        }
        NSLog("[home] %@ on the screens", next.rawValue)
    }
    /// Out of a program the menu opened (its own way out, or HOME): back
    /// to the menu; the program the play view was opened for goes back to
    /// the library.
    private func leaveProgram() {
        guard let current = running, current != .home else { return }
        if app == current { leaveApp(); return }
        ConsoleSounds.shared.play(.back)
        if current == .camera || current == .album { camera.close() }
        if current == .notes { notes.closeProgram() }
        NSLog("[home] %@ back to the menu", current.rawValue)
        if app == .home {
            startProgram(.home)
        } else {
            running = nil
            session.runApp(nil)
        }
        // b41: 选电视 from TV模式's button: back to the game.
        if programReturnsToGame {
            programReturnsToGame = false
            programShortcut = nil
            NSLog("[tv] 选电视 closed: back to the game")
            resumeFromHome()
            return
        }
        // Round 31: back onto the small icon that opened it (屏幕亮度).
        if let shortcut = programShortcut {
            programShortcut = nil
            homeProgram.slot = session.core?.stateSlot ?? 1
            homeProgram.reopen(shortcut: shortcut)
        } else if programFromCard {
            programFromCard = false
            homeProgram.reopen(selecting: .card)
        } else {
            homeProgram.reopen(selecting: current.homeItem)
        }
    }
    /// What a tile, a button or a small icon of the menu asks for.
    private func menuRequest(_ request: ConsoleHomeRequest) {
        switch request {
        case .item(.card, .continueGame), .item(.card, .continueDemo):
            resumeFromHome()
        case .item(.card, .closeGame):
            homeProgram.ask(ConsoleHomeDialog(title: String(localized: "关闭软件？"), message: String(localized: "未保存的进度会丢失。关闭后回到游戏库。"), confirm: String(localized: "关闭")) { closeFromMenu() })
        case .item(.card, .closeDemo):
            closeFromMenu()
        case .item(.card, _), .setup:
            // A 典藏卡带's card in the slot: its films, in place on the screens.
            if case .item(.card, _) = request, app == .home,
               let cartridge = Cartridge(rawValue: UserDefaults.standard.string(forKey: "FoldArc.insertedCard") ?? ""), ProAccess.cartridges.contains(cartridge) {
                NSLog("[gold] the %@ card started from the menu on the handheld", cartridge.rawValue)
                GoldReel.shared.rewind(cartridge)
                programShortcut = nil
                programReturnsToGame = false
                programFromCard = true
                startProgram(.settings, page: .reel)
                return
            }
            // The menu alone (the console gone into): the library starts it.
            appOpenHome(request)
        case .item(let item, _):
            // 相机, 设置 (round 31: over suspended software too, in place),
            // 游戏记录, 主题, 说明书, 游玩模式 (round 31: a tile of its own).
            // (导入 is not on the handheld's menu since 11-01.)
            programShortcut = nil
            programReturnsToGame = false
            programFromCard = false
            if let program = ConsoleApp(homeItem: item) { startProgram(program) } else { homeProgram.reopen() }
        case .shortcut(let shortcut):
            useShortcut(shortcut)
        }
    }
    /// One of the small icons along the top of the menu (software suspended).
    private func useShortcut(_ shortcut: ConsoleHomeShortcut) {
        homeProgram.reopen()
        programReturnsToGame = false
        switch shortcut {
        // What a save or a load reports is the status line on the upper
        // screen with the software: the cursor goes back onto its tile, so
        // that screen is up ("即时存档已保存…"; b8: it stayed on the small
        // icon and the line was not on the screen).
        // (A 存档位 past the free ones is saved into with Pro only: its
        // page in place, B back onto the icon. What is in it can be read.)
        case .save:
            if let core = session.core, !StateSlots.canSave(slot: core.stateSlot, pro: ProAccess.isPro) {
                programShortcut = .save; startProgram(.settings, page: .pro); return
            }
            homeProgram.reopen(selecting: .card); session.save()
        case .load: homeProgram.reopen(selecting: .card); session.restore()
        // 存档位: 系统设置's page of it in place, B back onto the icon.
        case .slots: programShortcut = .slots; startProgram(.settings, page: .stateSlot)
        // Round 31: 系统设置's 屏幕亮度 page in place, B back onto the icon.
        case .brightness: programShortcut = .brightness; startProgram(.settings, page: .brightness)
        // 画面滤镜 beside it, the same way.
        case .filter: programShortcut = .filter; startProgram(.settings, page: .filter)
        // Round 32: 游戏笔记 is a small icon; B / HOME
        // back onto it.
        case .notes: programShortcut = .notes; startProgram(.notes)
        // 铅笔盒 beside it, the same way.
        case .pencilBox: programShortcut = .pencilBox; startProgram(.tinBox)
        // 11-07: 按键点屏 on or off for this game; the menu stays, the
        // cursor on the icon, which shows it.
        case .keyTaps:
            guard let core = session.core else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
            core.setKeyTaps(!core.keyTaps)
            homeProgram.keyTaps = core.keyTaps
            homeProgram.reopen(shortcut: .keyTaps)
            ConsoleSounds.shared.play(core.keyTaps ? .select : .back)
        // 11-07: 倍速 1× → 2× → 4× → 1×, the menu staying on its icon.
        // It is Zero EMU Pro's: without Pro its icon opens Pro's page in
        // place, B back onto the icon.
        case .speed:
            guard ProAccess.isPro else { programShortcut = .speed; startProgram(.settings, page: .pro); return }
            guard let core = session.core else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
            core.setSpeed(core.speed >= 4 ? 1 : core.speed * 2)
            homeProgram.speed = core.speed
            homeProgram.reopen(shortcut: .speed)
            ConsoleSounds.shared.play(core.speed > 1 ? .select : .back)
        }
    }
    /// One of HOME's pages back to the menu it was opened from, the cursor
    /// on the suspended software (its 继续 and 关闭 in the bar).
    private func closeHomePage() {
        homeMenu.close()
        homeProgram.reopen(selecting: app == nil ? .card : nil)
    }
    /// 关闭软件 on the menu (asked first for a game).
    private func closeFromMenu() {
        resumeAfterMenu = false
        closeHome()
        closeSoftware()
    }
    /// The suspended software's record in the library (nil for the demo,
    /// or nothing suspended): 系统设置 will not remove it from under itself.
    private var suspendedRecord: GameRecord? {
        guard app == nil, let game else { return nil }
        return appGames.first { ConsoleHomeProgram.file(for: $0).standardizedFileURL == game.standardizedFileURL }
    }
    /// The suspended software, as the menu's first tile shows it.
    private var suspendedCard: GameCardInfo {
        if game == nil { return GameCardInfo(title: "Orbit Garden", subtitle: String(localized: "原创演示 · 内置"), icon: nil, isDemo: true) }
        return GameCardInfo(title: runningTitle, subtitle: gameInfo?.preferredTitle?.publisher ?? String(localized: "3DS 软件"),
                            icon: gameInfo?.largeIconImage(), isDemo: false)
    }
    /// The small icons along the top of the menu while software is
    /// suspended (round 31: only what has no tile or page of its own; a
    /// debug build's 开发者 is in 系统设置 › 其他设置 since 11-01).
    private var menuShortcuts: [ConsoleHomeShortcut] { session.core != nil ? ConsoleHomeShortcut.suspendedGameAll : ConsoleHomeShortcut.suspendedAll }
    /// With software suspended under the menu: it, as HOME shows it (its
    /// picture, its name, its status).
    private var suspendedTop: AnyView? {
        app == nil ? AnyView(HomeMenuTopScreen(ctx: homeContext)) : nil
    }
    /// On LCDs too small to read (a phone's 掌机模式, 桌面模式): over the
    /// whole display.
    @ViewBuilder private var fullScreenLayer: some View {
        switch layer {
        case .program(.camera), .program(.album): CameraFullScreen(model: camera)
        case .program(.notes): GameNotesFullScreen(model: notes)
        case .program(.tinBox): PencilBoxOpen(model: apps.model)
        case .program: ConsoleAppFullScreen(model: apps.model, ctx: appContext)
        case .menu: ConsoleHomeProgramFullScreen(model: homeProgram, suspendedTop: suspendedTop)
        case .page: fullScreenHome
        case .none: EmptyView()
        }
    }
    /// HOME or POWER in a built-in program: back to the library at once
    /// (its settings are kept as they are changed; an unfinished setup
    /// waits on the console's screens for next time).
    private func leaveApp() {
        guard let app else { return }
        ConsoleSounds.shared.play(.back)
        NSLog("[system] %@ left by HOME/POWER", app.rawValue)
        closeSoftware()
    }
    private func resumeFromHome() { resumeAfterMenu = true; closeHome() }
    private func closeHome() {
        showingHome = false; confirmingClose = false
        homeMenu.close()
        homeProgram.dialog = nil
        dismissMenu()
    }
    private func openPower() {
        if app != nil { leaveApp(); return }
        // Round 30: a program the menu opened over the software goes first.
        if case .program = layer { leaveProgram() }
        powerOff()
    }
    /// Round 32: POWER saves the progress — the software's 即时存档 (HOME's
    /// 保存进度), and the same state as 继续上次 for the library — and
    /// leaves for the library at once, the software's last frames carried
    /// to the console there (ConsoleStage.handoff), which comes down from
    /// full screen with them on its LCDs. Round 23's question is gone; HOME's
    /// 关闭软件 still closes without saving (and asks).
    private func powerOff() {
        guard !poweringOff else { return }
        poweringOff = true
        session.setPaused(true)
        closeHome()
        ConsoleHaptics.shared.play(.faceButton, .press)
        if let game, let core = session.core {
            session.status = String(localized: "正在保存进度…")
            // (A 存档位 only Pro saves into, without Pro: the state goes to
            // 继续上次 alone, and what the place holds stays.)
            guard StateSlots.canSave(slot: core.stateSlot, pro: ProAccess.isPro) else {
                core.saveState(to: SaveStates.resume(for: game)) { result in
                    if case .failure(let error) = result { NSLog("[play] POWER: state not saved: %@", error.localizedDescription) }
                    else { NSLog("[play] POWER: state saved for 继续上次 only (the 存档位 is Pro's), back to the library") }
                    leaveAfterPower()
                }
                return
            }
            core.saveState { result in
                switch result {
                case .success(let bytes):
                    // The same state as 继续上次 in the library (the manual
                    // slot copied; `SaveStates` names both).
                    let manual = SaveStates.manual(for: game), resume = SaveStates.resume(for: game)
                    try? FileManager.default.removeItem(at: resume)
                    try? FileManager.default.removeItem(at: SaveStates.info(for: resume))
                    try? FileManager.default.copyItem(at: manual, to: resume)
                    try? FileManager.default.copyItem(at: SaveStates.info(for: manual), to: SaveStates.info(for: resume))
                    session.status = String(localized: "进度已保存（\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))）")
                    NSLog("[play] POWER: state saved (%d bytes), back to the library", bytes)
                case .failure(let error):
                    session.status = String(localized: "进度没能保存：\(error.localizedDescription)")
                    NSLog("[play] POWER: state not saved: %@", error.localizedDescription)
                }
                leaveAfterPower()
            }
        } else {
            session.save()
            NSLog("[play] POWER: demo saved, back to the library")
            leaveAfterPower()
        }
    }
    private func leaveAfterPower() {
        ConsoleStage.handoff = lastFrames()
        close()
    }
    /// The two screens as they are now, for the console in the library to
    /// carry down (the core's frames; the demo's drawn).
    private func lastFrames() -> (top: CGImage, bottom: CGImage)? {
        if let core = session.core, let top = core.top, let bottom = core.bottom { return (top, bottom) }
        guard game == nil else { return nil }
        let top = ImageRenderer(content: StarField(state: session.state, squareCorners: true, depth: session.depth3D).frame(width: 400, height: 240))
        top.scale = 2
        let bottom = ImageRenderer(content: TouchMap(state: session.state, touch: nil, squareCorners: true, showCoordinates: session.showTouchCoordinates).frame(width: 320, height: 240))
        bottom.scale = 2
        guard let t = top.cgImage, let b = bottom.cgImage else { return nil }
        return (t, b)
    }
    private func dismissMenu() {
        if resumeAfterMenu && scenePhase == .active { session.setPaused(false) }
        resumeAfterMenu = false; focused = true
    }
    /// What the HOME menu's screens show and do (HomeMenuScreens.swift).
    private var homeContext: HomeMenuContext {
        HomeMenuContext(
            isDemo: game == nil,
            title: game == nil ? String(localized: "Orbit Garden 演示") : runningTitle,
            publisher: game == nil ? nil : gameInfo?.preferredTitle?.publisher,
            icon: game == nil ? nil : gameInfo?.largeIconImage(),
            status: session.status,
            paused: session.paused,
            mode: $layout,
            // (A colour only Pro has is not taken without Pro.)
            finish: Binding(get: { finish }, set: { if $0.isOpen { finish = $0 } }),
            brightness: $brightness,
            depth: Binding(get: { session.depth3D }, set: { session.setDepth3D($0) }),
            haptics: $haptics,
            hapticStrength: $hapticStrength,
            showGuides: $showGuides,
            previewFraction: $previewFraction,
            previewGap: $previewGap,
            confirmingClose: $confirmingClose,
            canCloseLid: deviceLidClosed == nil,
            showsGuidesToggle: layout == .handheld,
            showsFoldCalibration: layout == .handheld && deviceLidClosed == nil,
            screen: AnyView(topScreenPicture),
            guide: game == nil ? Self.demoControls : Self.gameControls,
            guideNote: game == nil ? String(localized: "这是原创演示，按键用途不代表真实游戏的按键。屏幕小的时候可以在 HOME 里换成「手柄模式」。")
                                   : String(localized: "按键原样交给正在运行的软件，具体用途以游戏为准。屏幕小的时候可以在 HOME 里换成「手柄模式」。"),
            developer: developerContent,
            resume: resumeFromHome,
            requestClose: {
                if game == nil { resumeAfterMenu = false; closeHome(); closeSoftware() } else { confirmingClose = true }
            },
            confirmClose: { resumeAfterMenu = false; closeHome(); closeSoftware() },
            save: { session.save() },
            restore: { session.restore() },
            closeLid: { previewClosed = true },
            testHaptic: { ConsoleHaptics.shared.play(.faceButton, enabled: haptics) })
    }
    /// What the LCDs show instead of the game: a built-in program (round
    /// 23), or the HOME menu while it is open (round 17).
    private var screenOverlay: ScreenOverlay? {
        guard homeInScreens else { return nil }
        switch layer {
        case .program(.camera), .program(.album):
            return ScreenOverlay(top: AnyView(CameraTopScreen(model: camera)), bottom: AnyView(CameraBottomScreen(model: camera)))
        case .program(.notes):
            return ScreenOverlay(top: AnyView(GameNotesTopScreen(model: notes)), bottom: AnyView(GameNotesBottomScreen(model: notes)))
        case .program:
            return ScreenOverlay(top: AnyView(ConsoleAppTopScreen(model: apps.model, ctx: appContext)),
                                 bottom: AnyView(ConsoleAppBottomScreen(model: apps.model, ctx: appContext)))
        case .menu:
            return ScreenOverlay(top: AnyView(ConsoleHomeProgramTop(model: homeProgram, suspendedTop: suspendedTop)),
                                 bottom: AnyView(ConsoleHomeProgramBottom(model: homeProgram)))
        case .page:
            return ScreenOverlay(top: AnyView(HomeMenuTopScreen(ctx: homeContext)),
                                 bottom: AnyView(HomeMenuBottomScreen(model: homeMenu, ctx: homeContext)))
        case .none:
            return nil
        }
    }
    /// 相机 may run: the lid open, the handheld on screen, FoldArc active.
    private var cameraAwake: Bool {
        scenePhase == .active && ((!lidClosed && !showsCover && innerVisible) || cameraDeck != .screens)
    }
    /// What a built-in program works with.
    private var appContext: ConsoleAppContext {
        // Round 31: 系统设置 opens over suspended software too; what cannot
        // be done under it (格式化, removing it) says to close it first.
        ConsoleAppContext(games: appGames, remove: appRemove, session: session,
                          testFiles: appTestFiles, launchTestFile: appLaunchTestFile,
                          suspended: app == nil ? suspendedCard.title : nil, suspendedID: suspendedRecord?.id,
                          play: playModeContext)
    }
    /// A controller came or went (round 31, 接手柄自动换模式): 手柄模式 while
    /// it is there (not over TV模式, which has the iPhone as the controller
    /// anyway), the mode before it after.
    private func padChanged(_ connected: Bool) {
        GameControllerInput.shared.homeForApp = layout == .immersive
        // 11-07 沉浸模式 is played on the controller: without one, 手柄模式's
        // keys on the screen until it is back, then 沉浸模式 again.
        if initialLayout == nil, !coverOnly {
            if !connected, layout == .immersive { waitForController(); return }
            if connected, immersiveWaiting {
                immersiveWaiting = false
                guard layout == .controller else { return }
                NSLog("[play] controller connected: 沉浸模式 again")
                withAnimation(.easeInOut(duration: 0.3)) { layout = .immersive }
                return
            }
        }
        guard padAutoMode, initialLayout == nil, !coverOnly else { return }
        if connected {
            guard layout != .controller, layout != .tv, layout != .immersive else { return }
            NSLog("[play] controller connected: 手柄模式 (was %@)", layout.rawValue)
            modeBeforePad = layout
            withAnimation(.easeInOut(duration: 0.3)) { layout = .controller }
        } else if let before = modeBeforePad {
            modeBeforePad = nil
            guard layout == .controller else { return }
            NSLog("[play] controller gone: back to %@", before.rawValue)
            withAnimation(.easeInOut(duration: 0.3)) { layout = before }
        }
    }
    /// 沉浸模式 with no controller: 手柄模式 stands in (the mode kept as
    /// 沉浸模式 for the next game).
    private func waitForController() {
        NSLog("[play] 沉浸模式 without a controller: 手柄模式 until one connects")
        immersiveWaiting = true
        withAnimation(.easeInOut(duration: 0.3)) { layout = .controller }
    }
    /// 11-07: on its side — a phone's window wider than tall, the Duo held
    /// across like a book (its inner display; a game window there keeps the
    /// handheld's orientation, so the hold says, not the window).
    private var heldSideways: Bool {
        #if os(iOS)
        if deviceLidClosed != nil { return displayRole.heldAcross }
        #endif
        return windowWide
    }
    /// What is drawn for the mode (SidewaysMode.presented): on a Duo's inner
    /// display held across, 掌机模式 and 桌面模式 as 手柄模式 (11-07);
    /// upright, 掌机模式 as 手柄模式 when a style is chosen for it.
    /// Not where the mode is set from outside. 11-15: for a program the
    /// library opened too (铅笔盒 from the library's corner, 系统设置…): held
    /// across, it had kept the handheld's upright window, and the system
    /// showed that in its small 469 × 669 one, black either side.
    private var presentedLayout: ScreenLayout {
        guard deviceLidClosed != nil, initialLayout == nil, !coverOnly else { return layout }
        let shown = SidewaysMode.presented(mode: layout.rawValue, across: heldSideways, cover: showsCover,
                                           uprightController: duoUprightLook != DuoUprightLook.console)
        return ScreenLayout(rawValue: shown) ?? layout
    }
    /// 11-07: the Duo held across — the game's window on the inner display
    /// turns with the hold (CoverOrientationPolicy), in every mode.
    private var followsHold: Bool {
        // 11-07: under a program the menu opened too.
        // b70 turned the window back to the handheld's for one, and the Duo
        // held across showed it in the system's small 469 × 669 window, the
        // controller's LCDs too small, so over the whole of it. Now the
        // program stays on the controller's two screens, as the menu is.
        // 11-15: a play view the library opened for a program as well (its
        // window had stayed the handheld's; see presentedLayout).
        guard deviceLidClosed != nil, !coverOnly else { return false }
        return SidewaysMode.followsHold(mode: layout.rawValue, across: heldSideways, cover: showsCover)
    }
    /// On its side: 掌机模式 / 桌面模式 → 手柄模式; upright again: the mode
    /// before, unless another was chosen meanwhile (SidewaysMode). Not on
    /// the cover (the lid shut), not under a built-in program (the camera,
    /// the album, the notes: they are laid out for the handheld), nor where
    /// the mode is set from outside.
    private func sidewaysCheck() {
        // 11-07: under a program of the menu's too (it stays on the screens
        // of whichever mode the hold gives; see followsHold).
        guard initialLayout == nil, !coverOnly, !showsCover, app == nil else { return }
        let sideways = heldSideways
        var state = sidewaysState
        let next = state.settle(mode: layout.rawValue, sideways: sideways).flatMap(ScreenLayout.init(rawValue:))
        if state != sidewaysState { sidewaysState = state }
        guard let mode = next else { return }
        NSLog("[play] %@: %@ → %@", sideways ? "on its side" : "upright again", layout.rawValue, mode.rawValue)
        withAnimation(.easeInOut(duration: 0.3)) { layout = mode }
    }
    /// What 游玩模式 changes here (round 31: a program of the menu; it was
    /// one of HOME's pages): the mode at once, the guides and the pretend
    /// fold of 掌机模式, 合上掌机 on an iPhone with no hinge.
    private var playModeContext: PlayModeContext {
        PlayModeContext(mode: layout,
                        setMode: { mode in withAnimation(.easeInOut(duration: 0.25)) { modeBeforePad = nil; immersiveWaiting = false; sidewaysState.chosen(); layout = mode } },
                        showGuides: $showGuides,
                        foldFraction: deviceLidClosed == nil ? $previewFraction : nil,
                        foldGap: deviceLidClosed == nil ? $previewGap : nil,
                        closeLid: deviceLidClosed == nil ? { previewClosed = true } : nil)
    }
    /// The screens' brightness as shown: power saving caps it (round 23).
    private var shownBrightness: Double { BrightnessSteps.effective(brightness, powerSaving: system.powerSaving) }
    /// The menu over the whole display: the two screens one above the other,
    /// a hinge line between, the system's own edges left clear.
    private var fullScreenHome: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            // The upper screen keeps the LCD's 5:3 (plus the strip), as far
            // as the display's height allows.
            let topHeight = min(proxy.size.height * 0.42, proxy.size.width * 0.6 + 20)
            VStack(spacing: 0) {
                HomeMenuTopScreen(ctx: homeContext)
                    .padding(.top, insets.top)
                    .background(SystemMenuStyle.status)
                    .frame(height: topHeight + insets.top)
                Rectangle().fill(SystemMenuStyle.bar).frame(height: 4)
                HomeMenuBottomScreen(model: homeMenu, ctx: homeContext)
                    .padding(.bottom, insets.bottom)
                    .background(SystemMenuStyle.bar)
            }
            .ignoresSafeArea()
        }
        .transition(.opacity)
        .zIndex(5)
    }
    /// The suspended software's upper screen, live, for the HOME banner.
    @ViewBuilder private var topScreenPicture: some View {
        if let core = session.core { CoreTopScreen(session: core) }
        else { StarField(state: session.state, squareCorners: true, depth: session.depth3D) }
    }
    private var developerContent: AnyView? {
        #if os(iOS) && DEBUG
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            Toggle("外屏上抑制 UIKit 旋转动画", isOn: $snapTransitions)
            Toggle("显示方向诊断叠层", isOn: $traceOverlay)
            Toggle("记录过渡帧 PNG", isOn: $captureFrames)
            Text("日志：\(OrientationTrace.shared.locations.first?.path ?? String(localized: "无可写目录"))").font(.caption2)
                .foregroundStyle(SystemMenuStyle.inkSoft).textSelection(.enabled)
        })
        #else
        return nil
        #endif
    }
    static let demoControls = PlayControls.demo
    static let gameControls = PlayControls.game
    static let controllerHelp = PlayControls.controllerHelp
    /// The running software's HOME Menu title (SMDH), else its file name.
    private var runningTitle: String {
        gameInfo?.preferredTitle?.short ?? game?.deletingPathExtension().lastPathComponent ?? ""
    }
}

/// The model of the settings-like program on the screens (round 30: the
/// menu can start another one in place, with a model of its own).
@MainActor final class ConsoleAppHolder: ObservableObject {
    @Published private(set) var model: ConsoleAppModel
    init(app: ConsoleApp) { model = ConsoleAppModel(app: app) }
    /// Round 31: at one of its pages (屏幕亮度 from the menu's small icon).
    func start(_ app: ConsoleApp, page: ConsoleAppModel.Page? = nil) { model = ConsoleAppModel(app: app, page: page) }
}

/// What the keys do (the HOME menu's 操作指南, 说明书): not tied to the
/// play view, so the manual's text can be built anywhere (round 30).
enum PlayControls {
    static let demo: [(String, String)] = [(String(localized: "摇杆 / 十字键"), String(localized: "移动飞船；支持斜向移动")), (String(localized: "下屏 / 小摇杆"), String(localized: "触摸下屏或拖动小摇杆移动信标")),
                                       ("A / B", String(localized: "传送到信标 / 按住加速")), ("X / Y", String(localized: "对准星星 / 信标归中")),
                                       ("L · ZL / R · ZR", String(localized: "信标向左 / 向右微调")), ("START / SELECT", String(localized: "游戏暂停继续 / 切换下屏坐标")),
                                       ("HOME / POWER", String(localized: "暂停菜单 / 保存演示进度并回到游戏库（按一下就走）")),
                                       (String(localized: "3D 滑块"), String(localized: "推上去，星空分成红蓝两层：戴红蓝眼镜能看到深度；拉到底是 OFF")),
                                       ("MIC", String(localized: "按住它，或者对着 iPhone 的麦克风吹气：把飞船吹向上方")),
                                       (String(localized: "铰链（桌面模式）"), String(localized: "拖动开合上盖，轻点在打开和微合之间切换；合到底就休眠，从下沿往上推打开")),
                                       (String(localized: "外接手柄"), controllerHelp)]
    static let game: [(String, String)] = [(String(localized: "摇杆 / 十字键"), String(localized: "方向输入；摇杆是模拟的，推得越远输入越大")),
                                       (String(localized: "下屏"), String(localized: "掌机的触摸屏：直接点按或拖动")),
                                       ("A / B / X / Y", String(localized: "动作键")),
                                       ("L · ZL / R · ZR", String(localized: "肩键")),
                                       (String(localized: "小摇杆"), String(localized: "右边的第二个摇杆，做什么由软件决定")),
                                       ("START / SELECT", String(localized: "软件自己的菜单与功能键")),
                                       ("HOME", String(localized: "暂停并打开主菜单（和游戏库里掌机上的是同一个）：第一个图标是正在玩的软件，继续游戏或关闭软件；上面一排小图标是保存进度、读取进度、游戏笔记、屏幕亮度；相机、相册、设置、游戏记录、主题、说明书、游玩模式暂停时也能开，HOME 回来（导入在游戏库里）；游戏笔记能把暂停的画面放到纸上")),
                                       ("POWER", String(localized: "保存进度（即时存档）并回到游戏库，按一下就走；下次在游戏库里「继续上次」接着玩。不保存就关闭用 HOME 里的「关闭软件」")),
                                       (String(localized: "3D 滑块"), String(localized: "游戏读到的 3D 滑块位置；推上去时画面变成红蓝 3D（戴红蓝眼镜看），拉到底是 OFF")),
                                       ("MIC", String(localized: "要吹气的游戏：对着 iPhone 吹气（麦克风在 USB-C 口旁边），或者按住 MIC；游戏开始听的时候，有箭头指着掌机上的 MIC。Zero EMU 只听有没有在吹，不录音")),
                                       (String(localized: "铰链（桌面模式）"), String(localized: "拖动开合上盖，轻点在打开和微合之间切换；合到底就休眠")),
                                       (String(localized: "外接手柄"), controllerHelp)]
    static let controllerHelp = String(localized: "A B X Y 默认按位置对应（右 A、下 B、上 X、左 Y），可以在 系统设置 › 其他设置 › 手柄 换成按字母（Xbox 手柄上印着 A 的键就是 A），或一个个改；L / R 肩键，ZL / ZR 扳机；左摇杆就是掌机的摇杆，右摇杆就是小摇杆；Menu = START，Options = SELECT；Home 键（系统不占用它时）打开 HOME，再按继续。接上手柄会自动换到手柄模式（两块屏放大，屏幕上不再有按键），拔掉换回原来的模式，也可以在「手柄」里关掉")
}

struct ShoulderControl: View {
    var key: PadButton
    var haptics: Bool
    var press: (PadButton, Bool) -> Void
    var width = 50.0
    var height = 36.0
    @GestureState private var held = false
    /// 手柄样式 圆润: a tab of the casing's own plastic; `hanging`
    /// rounds only its lower corners (it hangs under the touch screen).
    @Environment(\.controlLook) private var look
    var hanging = false
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        face
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).updating($held) { _, state, _ in state = true })
            .onChange(of: held) { _, down in
                press(key, down)
                // L and R are long levers (deeper); ZL and ZR small switches.
                ConsoleHaptics.shared.play(key == .l || key == .r ? .shoulder : .trigger, down ? .press : .release, enabled: haptics)
            }
            .onDisappear { press(key, false) }
            .accessibilityLabel("\(key.rawValue.uppercased()) 肩键").accessibilityAddTraits(.isButton)
            .accessibilityAction { press(key, true); press(key, false) }
    }
    @ViewBuilder private var face: some View {
        if case .soft(let finish) = look {
            let r = min(12, height * 0.36)
            let shape = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: hanging ? 2 : r, bottomLeading: r, bottomTrailing: r, topTrailing: hanging ? 2 : r), style: .continuous)
            ZStack {
                SoftKeyFace(shape: shape, finish: finish, held: held)
                SoftLetters(text: key.rawValue.uppercased(), finish: finish, size: height > 38 ? 14 : 12.5)
                    .offset(y: held ? 1.1 : -0.4)
            }
        } else {
            Text(key.rawValue.uppercased()).font(.system(size: height > 38 ? 14 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(held ? 1 : 0.7))
                .shadow(color: .black.opacity(0.6), radius: 0, y: 0.6)
                .frame(width: width, height: height)
                .background(LinearGradient(colors: [Color(white: held ? 0.14 : 0.27), Color(white: held ? 0.09 : 0.14), Color(white: 0.08)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
                .raised(RoundedRectangle(cornerRadius: 9), light: 0.3, dark: 0.6, lift: held ? 0.5 : 2)
                .offset(y: held ? 2 : 0)
        }
    }
}


/// A colour chip: solid for single-tone finishes, split for two-tone ones.
struct FinishSwatch: View {
    var finish: ShellFinish
    var selected: Bool
    var size: Double = 22
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [finish.light, finish.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
            if finish.isTwoTone {
                Circle().fill(LinearGradient(colors: [finish.innerShell.light, finish.innerShell.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .mask(Rectangle().frame(width: size / 2).offset(x: size / 4))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(selected ? Color.white.opacity(0.9) : .white.opacity(0.18), lineWidth: selected ? 2 : 1))
        .padding(2)
    }
}
