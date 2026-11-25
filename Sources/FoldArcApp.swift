import SwiftUI
import UniformTypeIdentifiers
import ImageIO
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

#if !RENDER_PREVIEW && os(macOS)
@main struct FoldArcApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView().preferredColorScheme(.dark)
                .frame(minWidth: 600, minHeight: 640)
        }
        .defaultSize(width: 900, height: 1050)
        .windowStyle(.hiddenTitleBar)
    }
}
#endif

/// A breadcrumb of the run, so an unexpected end (a crash, a kill by the
/// system) can be told from a normal one the next time FoldArc starts
/// (round 18 reports). `lastrun.txt` in the data root gets a line
/// per step (start, library, launch <title>, active, background, clean);
/// a file left without "clean" or "background" as its last line is an
/// unexpected end, kept as `lastrun-previous.txt` and summarised for 设置.
enum LastRun {
    private static var url: URL { Storage.root.appendingPathComponent("lastrun.txt") }
    private static var previousURL: URL { Storage.root.appendingPathComponent("lastrun-previous.txt") }
    /// The previous run's last line when it did not end cleanly; nil otherwise.
    nonisolated(unsafe) private(set) static var previousSummary: String?
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"; return f
    }()
    static func begin() {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let lines = text.split(separator: "\n").map(String.init)
            if let last = lines.last, !last.hasSuffix("clean"), !last.hasSuffix("background") {
                previousSummary = last
                NSLog("[lastrun] the previous run did not end cleanly; last line: %@", last)
                try? FileManager.default.removeItem(at: previousURL)
                try? FileManager.default.copyItem(at: url, to: previousURL)
            }
        }
        try? FileManager.default.createDirectory(at: Storage.root, withIntermediateDirectories: true)
        try? "\(clock.string(from: Date())) start\n".write(to: url, atomically: true, encoding: .utf8)
    }
    static func note(_ step: String) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(clock.string(from: Date())) \(step)\n".utf8))
    }
    static func end() { note("clean") }
    /// This run's breadcrumbs and the last unclean run's (关于 › 导出日志).
    static func records() -> (current: String?, previous: String?) {
        (try? String(contentsOf: url, encoding: .utf8), try? String(contentsOf: previousURL, encoding: .utf8))
    }
}

#if os(iOS)
/// 长按图标的快捷方式 (11-05): "继续玩
/// 上次的游戏" and the two played before it (游戏记录), each resumed where it
/// was left when it was. Set each time FoldArc goes to the background. A
/// launch from one goes through LaunchPlan (`atLaunch`); one tapped while
/// FoldArc runs waits in `pending` for the library (with a software up it
/// is not started).
@MainActor final class HomeScreenShortcuts: ObservableObject {
    static let shared = HomeScreenShortcuts()
    static let type = "com.foldarc.play"
    struct Request: Equatable { var id: String; var resume: Bool }
    @Published var pending: Request?
    private(set) var atLaunch: Request?
    /// LaunchPlan has decided where this process opened: a quick action
    /// that connects another scene later waits in `pending` instead.
    var launchDecided = false

    private init() {
        #if DEBUG
        // `--foldarc-shortcut=<file name, title or demo>[|<another>…]`: this
        // launch is one from a quick action (UI tests; the first that is in
        // the library is taken).
        if let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-shortcut=") }) {
            atLaunch = Request(id: String(value.dropFirst("--foldarc-shortcut=".count)), resume: true)
        }
        #endif
    }
    /// The quick action this launch came from, if any (before the library is
    /// built: LaunchPlan reads it).
    func launched(with item: UIApplicationShortcutItem?) {
        guard let item, let request = Self.request(item) else { return }
        NSLog("[shortcuts] launched with %@", request.id)
        if launchDecided { pending = request } else { atLaunch = request }
    }
    /// One tapped while FoldArc was running.
    func perform(_ item: UIApplicationShortcutItem) -> Bool {
        guard let request = Self.request(item) else { return false }
        NSLog("[shortcuts] tapped: %@", request.id)
        pending = request
        return true
    }
    static func request(_ item: UIApplicationShortcutItem) -> Request? {
        guard item.type == type, let id = item.userInfo?["id"] as? String else { return nil }
        return Request(id: id, resume: item.userInfo?["resume"] as? Bool ?? true)
    }
    /// What a request opens: the demo, or the game (resumed when it was left
    /// and the request says so); nil when it is not in the library any more.
    static func plan(for request: Request, games: [GameRecord], root: URL) -> LaunchPlan? {
        for wanted in request.id.split(separator: "|").map(String.init) {
            if wanted == LaunchPlan.demoCardID { return .demo }
            #if DEBUG
            // Tests name a game by the start of its title or file name.
            let lower = wanted.lowercased()
            let found = games.first { $0.fileName == wanted }
                ?? games.first { $0.title.lowercased().hasPrefix(lower) || $0.fileName.lowercased().hasPrefix(lower) }
            #else
            let found = games.first { $0.fileName == wanted }
            #endif
            guard let game = found else { continue }
            let file = root.appendingPathComponent("ROMs").appendingPathComponent(game.fileName)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            return .game(file, resume: request.resume && FileManager.default.fileExists(atPath: SaveStates.resume(for: file).path))
        }
        return nil
    }
    /// The quick actions, from 游戏记录 (the last played first).
    func refresh() {
        let root = Storage.root
        let games = (try? JSONDecoder().decode([GameRecord].self, from: Data(contentsOf: root.appendingPathComponent("library.json")))) ?? []
        var items: [UIApplicationShortcutItem] = []
        for entry in PlayLog.shared.entries.values.sorted(by: { $0.last > $1.last }) where items.count < 3 {
            let demo = entry.id == LaunchPlan.demoCardID
            guard demo || games.contains(where: { $0.fileName == entry.id }) else { continue }
            let resumable = !demo && FileManager.default.fileExists(atPath: SaveStates.resume(for: root.appendingPathComponent("ROMs").appendingPathComponent(entry.id)).path)
            let first = items.isEmpty
            items.append(UIApplicationShortcutItem(type: Self.type,
                                                   localizedTitle: first ? String(localized: "继续玩上次的游戏") : entry.title,
                                                   localizedSubtitle: first ? entry.title : (resumable ? String(localized: "从上次的地方接着玩") : String(localized: "开始游戏")),
                                                   icon: UIApplicationShortcutIcon(systemImageName: first ? "play.fill" : "gamecontroller.fill"),
                                                   userInfo: ["id": entry.id as NSString, "resume": NSNumber(value: true)]))
        }
        UIApplication.shared.shortcutItems = items
        NSLog("[shortcuts] set %d: %@", items.count, items.map { "\($0.localizedTitle) · \($0.localizedSubtitle ?? "")" }.joined(separator: " | "))
    }
}
#endif

/// Waits until the display's frames come on time again — a few in a row
/// no later than they should — or at most `timeout` seconds, then calls
/// `done` (round 20: the curtain over a change lifts only then).
@MainActor final class FrameCalm: NSObject {
    private static var waiting: [FrameCalm] = []
    private var done: (() -> Void)?
    private var needed: Int
    private var streak = 0
    private var last: CFTimeInterval = 0
    private let deadline: CFTimeInterval
    #if os(iOS)
    private var link: CADisplayLink?
    #endif
    private init(frames: Int, timeout: Double, done: @escaping () -> Void) {
        needed = frames
        deadline = CACurrentMediaTime() + timeout
        self.done = done
        super.init()
    }
    static func wait(frames: Int = 6, timeout: Double = 1.5, _ done: @escaping () -> Void) {
        #if os(iOS)
        let calm = FrameCalm(frames: frames, timeout: timeout, done: done)
        let link = CADisplayLink(target: calm, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        calm.link = link
        waiting.append(calm)
        #else
        done()
        #endif
    }
    #if os(iOS)
    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if last > 0 { streak = now - last < 0.022 ? streak + 1 : 0 }
        last = now
        guard streak >= needed || CACurrentMediaTime() > deadline else { return }
        link.invalidate()
        self.link = nil
        let done = self.done
        self.done = nil
        Self.waiting.removeAll { $0 === self }
        done?()
    }
    #endif
}

#if os(iOS)
/// The white curtain over a change between the library and a game, as a
/// plain UIKit view (round 20). Its fades are Core Animation animations,
/// which the render server runs by itself: they stay even while the view
/// coming in underneath still holds up the main thread now and then. As a
/// SwiftUI opacity the fade was stepped on the main thread and went in
/// jerks (10-30: 7-9 frames in 0.5 s).
struct WhiteCurtain: UIViewRepresentable {
    /// White (up) or clear, how long the change takes (0: at once) and how
    /// long it waits before it starts.
    var up: Bool
    var fade: Double
    var delay: Double = 0
    // Touches go through: a tap on the game just as it comes in reaches it
    // (on the phone a tap on HOME then was swallowed by the curtain, 10-30).
    func makeUIView(context: Context) -> UIView {
        let view = CurtainUIView()
        view.backgroundColor = .white
        view.isUserInteractionEnabled = false
        view.layer.opacity = up ? 1 : 0
        CurtainUIView.current = view
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        let target: Float = up ? 1 : 0
        guard view.layer.opacity != target else { return }
        let curtain = view as? CurtainUIView
        // Raised the usual way: white, not a picture left from before.
        if up { curtain?.dropPicture() }
        let from = view.layer.presentation()?.opacity ?? view.layer.opacity
        view.layer.removeAnimation(forKey: "curtain")
        view.layer.opacity = target
        guard fade > 0 else {
            if !up { curtain?.dropPicture() }
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = fade
        if delay > 0 {
            // Held at the start until then (the console's zoom runs first).
            animation.beginTime = view.layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        // Lifting starts gently: the first frames of the game under it
        // hardly show, so a late first frame is not seen as a jump.
        animation.timingFunction = CAMediaTimingFunction(name: up ? .easeIn : .easeInEaseOut)
        CATransaction.begin()
        if !up {
            // Lifted: the picture it held goes once it is clear.
            CATransaction.setCompletionBlock { [weak curtain] in
                guard let curtain, curtain.layer.opacity == 0 else { return }
                curtain.dropPicture()
            }
        }
        view.layer.add(animation, forKey: "curtain")
        CATransaction.commit()
    }
}

/// The curtain's own view (round 24). Besides white it can hold a still
/// picture of the screen, taken at once, before the views under it change:
/// a change between the library and a game then dissolves from the old
/// screen straight into the new one (10-30: they passed through ~0.8 s of
/// white). The picture is the render server's own
/// (`snapshotView`), so the 3D console in it is as it was on the screen.
/// If the new screen keeps it waiting, the picture whitens, as a
/// handheld's screens do while software starts.
final class CurtainUIView: UIView {
    static weak var current: CurtainUIView?
    private var picture: UIView?
    private let whitening = UIView()
    private var stamp = 0
    /// Puts a picture of the window up, fully opaque, at once, drifting
    /// slowly toward `drift` (its scale) while it is up, so that the screen
    /// never stands still between the two (round 24: the console going on
    /// growing as the game comes up, the game moving off as the library
    /// comes back). False if none could be taken.
    func coverWithPicture(whitenAfter delay: Double, drift: CGFloat) -> Bool {
        guard let window, let shot = window.snapshotView(afterScreenUpdates: false) else { return false }
        dropPicture()
        stamp += 1
        shot.frame = convert(window.bounds, from: window)
        shot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(shot)
        picture = shot
        if drift != 1 {
            let growing = CABasicAnimation(keyPath: "transform.scale")
            growing.fromValue = 1
            growing.toValue = drift
            growing.duration = 1.6
            growing.timingFunction = CAMediaTimingFunction(name: .easeOut)
            growing.fillMode = .forwards
            growing.isRemovedOnCompletion = false
            shot.layer.add(growing, forKey: "drift")
        }
        whitening.backgroundColor = .white
        whitening.frame = bounds
        whitening.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        whitening.alpha = 0
        addSubview(whitening)
        backgroundColor = .clear
        layer.removeAnimation(forKey: "curtain")
        layer.opacity = 1
        let current = stamp
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.stamp == current, self.picture != nil, self.layer.opacity == 1 else { return }
            UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) { self.whitening.alpha = 1 }
        }
        return true
    }
    func dropPicture() {
        guard picture != nil else { return }
        stamp += 1
        picture?.removeFromSuperview()
        picture = nil
        whitening.layer.removeAllAnimations()
        whitening.removeFromSuperview()
        backgroundColor = .white
    }
}
#endif

#if os(iOS)
/// The logo over the start, faded by Core Animation (round 21): as a SwiftUI
/// opacity its fade was stepped on the main thread just while the console's
/// first frames were drawn, and went in jerks (10-30 recording: from dark to
/// a third of the way in two frames, then 25-47 ms steps). The logo is the
/// same SwiftUI view, hosted in a UIKit view whose layer fades.
struct SplashCurtain: UIViewControllerRepresentable {
    var shown: Bool
    var fade: Double
    func makeUIViewController(context: Context) -> UIHostingController<SplashView> {
        let host = UIHostingController(rootView: SplashView())
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = shown
        host.view.layer.opacity = shown ? 1 : 0
        return host
    }
    func updateUIViewController(_ host: UIHostingController<SplashView>, context: Context) {
        host.view.isUserInteractionEnabled = shown
        let layer = host.view.layer
        let target: Float = shown ? 1 : 0
        guard layer.opacity != target else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: "splash")
        layer.opacity = target
        guard fade > 0 else { return }
        // Going: let through a hair at once and held there a moment, so
        // what is under the logo is drawn for the first time unseen, not in
        // the fade's first frames (10-30: those came 30-37 ms apart and
        // jumped a fifth of the way); then a fade that starts gently.
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        if shown {
            animation.values = [from, target]
            animation.keyTimes = [0, 1]
            animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut)]
            animation.duration = fade
        } else {
            let hold = LibraryView.splashHold, total = hold + fade
            let hair: Float = min(from, 0.97)
            animation.values = [from, hair, hair, target]
            animation.keyTimes = [0, NSNumber(value: 0.016 / total), NSNumber(value: hold / total), 1]
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear),
                                         CAMediaTimingFunction(name: .easeInEaseOut)]
            animation.duration = total
        }
        layer.add(animation, forKey: "splash")
    }
}
#endif

/// The curtain's state, kept apart from LibraryView's own (round 20):
/// raising or lifting it redraws the curtain alone, not the game under it,
/// so the change reaches the screen at once (10-30 recording: the first
/// step of the lift came 80 ms late while the whole view was redrawn).
@MainActor final class CurtainState: ObservableObject {
    @Published private(set) var up = false
    /// How long the last change takes (0: at once), and how long it waits.
    private(set) var fade = 0.0
    private(set) var delay = 0.0
    func set(_ up: Bool, fade: Double, delay: Double = 0) {
        guard up != self.up else { return }
        self.fade = fade
        self.delay = delay
        self.up = up
    }
    /// Up at once, holding a still picture of the screen as it is now
    /// (round 24): the change under it then dissolves from that picture.
    /// The picture whitens if the change keeps it up longer than `whitenAfter`.
    /// False when no picture could be taken (raise it white then).
    func coverWithPicture(whitenAfter delay: Double = 0.9, drift: Double = 1) -> Bool {
        #if os(iOS)
        guard let view = CurtainUIView.current, view.coverWithPicture(whitenAfter: delay, drift: CGFloat(drift)) else { return false }
        fade = 0
        self.delay = 0
        if !up { up = true }
        return true
        #else
        return false
        #endif
    }
}

struct CurtainView: View {
    @ObservedObject var state: CurtainState
    var body: some View {
        #if os(iOS)
        WhiteCurtain(up: state.up, fade: state.fade, delay: state.delay)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #else
        Color.white.opacity(state.up ? 1 : 0)
            .animation(state.fade > 0 ? .easeInOut(duration: state.fade).delay(state.delay) : nil, value: state.up)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #endif
    }
}

/// `--foldarc-frame-meter` (DEBUG): how evenly the main thread kept up with
/// the display over a labelled stretch, from a display link (round 20: the
/// insert, the launch zoom and the hand-over to the game were choppy).
/// Logged as `[frames] <label>: …` — the longest gap between two frames,
/// how many gaps were longer than 25 ms (one frame or more missed at 60 Hz)
/// and longer than 50 ms, and an estimate of the frames missed in all.
@MainActor final class FrameMeter: NSObject {
    static let shared = FrameMeter()
    #if DEBUG
    static let enabled = ProcessInfo.processInfo.arguments.contains("--foldarc-frame-meter")
    #else
    static let enabled = false
    #endif
    #if os(iOS)
    private var link: CADisplayLink?
    #endif
    private var label = ""
    private var last: CFTimeInterval = 0
    private var started: CFTimeInterval = 0
    private var gaps: [Double] = []
    func begin(_ label: String) {
        guard Self.enabled else { return }
        end()
        self.label = label
        gaps = []; last = 0; started = CACurrentMediaTime()
        #if os(iOS)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        #endif
    }
    #if os(iOS)
    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { gaps.append((link.timestamp - last) * 1000) }
        last = link.timestamp
    }
    #endif
    /// Ends the stretch (only the one named, when a name is given).
    func end(_ expected: String? = nil) {
        #if os(iOS)
        guard let link, expected == nil || expected == label else { return }
        link.invalidate()
        self.link = nil
        let total = (CACurrentMediaTime() - started) * 1000
        let longest = gaps.max() ?? 0
        let over25 = gaps.filter { $0 > 25 }.count
        let over50 = gaps.filter { $0 > 50 }.count
        let missed = gaps.reduce(0) { $0 + Swift.max(0, Int(($1 / 16.67).rounded()) - 1) }
        NSLog("[frames] %@: %.0f ms, %d frames, longest %.0f ms, >25 ms %d, >50 ms %d, missed ~%d", label, total, gaps.count, longest, over25, over50, missed)
        #endif
    }
    /// Ends the stretch `seconds` from now (if it is still the same one).
    func end(after seconds: Double) {
        guard Self.enabled else { return }
        let current = label
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            self.end(current)
        }
    }
}

#if DEBUG && os(iOS)
/// 11-11 (the iPhone Duo held across): a press held on the middle card came
/// to the shelf only as the finger moved off, 0.9 s late, once in eight runs
/// — was the main thread held, or the touch held back? This says whenever
/// the main thread was held more than 200 ms (`[stall] …`), DEBUG only: a
/// timer off the main thread asks it for the time every 50 ms.
final class MainThreadWatch: @unchecked Sendable {
    static let shared = MainThreadWatch()
    private let queue = DispatchQueue(label: "foldarc.main-thread-watch", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var waiting = false
    func start() {
        queue.async {
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: .milliseconds(50))
            timer.setEventHandler { [weak self] in
                guard let self, !self.waiting else { return }
                self.waiting = true
                let asked = CACurrentMediaTime()
                DispatchQueue.main.async {
                    let held = CACurrentMediaTime() - asked
                    if held > 0.2 { NSLog("[stall] the main thread was held %.0f ms", held * 1000) }
                    self.queue.async { self.waiting = false }
                }
            }
            timer.resume()
            self.timer = timer
        }
    }
}
#endif

#if DEBUG && os(iOS)
/// 11-11: when UIKit itself hears of a finger, before any gesture does
/// (`[touch] down at … heard N ms after`): next to the shelf's own "finger
/// down … heard N ms after" it says whether a press heard late came late
/// into the app or was held back among the gestures. DEBUG only.
final class TouchProbeWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches, let touches = event.allTouches {
            for touch in touches where touch.phase == .began {
                let point = touch.location(in: self)
                NSLog("[touch] down at (%.0f, %.0f), heard %.0f ms after", point.x, point.y,
                      (ProcessInfo.processInfo.systemUptime - touch.timestamp) * 1000)
            }
        }
        super.sendEvent(event)
    }
}
#endif

#if os(iOS)
/// iOS runs on the UIKit scene lifecycle so that FoldArc owns the scene
/// delegate and the window's root view controller, the two places UIKit asks
/// for a scene's supported orientations (iOS 27 adds the per-scene
/// `supportedInterfaceOrientationsForWindowScene:`). SwiftUI's WindowGroup
/// answers neither, and on Duo the cover display only held still once the
/// scene-level answer was FoldArc's (10-27 trace). See
/// Docs/ORIENTATION-FIXED-20261027.md.
@main
@MainActor final class FoldArcAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        // 11-22: after the UI tests on a phone, its settings put back as they were before them (a copy of its
        // preferences the Mac put in Documents), and this run ends there: the next launch reads them fresh.
        if let asked = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-restore-defaults=") }),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let domain = Bundle.main.bundleIdentifier {
            let url = documents.appendingPathComponent(String(asked.dropFirst("--foldarc-restore-defaults=".count)))
            if let data = try? Data(contentsOf: url),
               let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                UserDefaults.standard.setPersistentDomain(saved, forName: domain)
                UserDefaults.standard.synchronize()
                NSLog("[debug] the settings put back as they were before the tests: %d keys", saved.count)
            } else {
                NSLog("[debug] the settings to put back could not be read")
            }
            exit(0)
        }
        #endif
        // A body colour chosen in an earlier build, under the name it has now
        // (before any view reads it).
        if let stored = UserDefaults.standard.string(forKey: StoredFinishName.key),
           let name = StoredFinishName.current(for: stored, isName: { ShellFinish(rawValue: $0) != nil }) {
            UserDefaults.standard.set(name, forKey: StoredFinishName.key)
        }
        // Compressed game files are read through the core.
        AzaharSession.installCompressedReader()
        #if DEBUG
        AzaharSession.compressForTests()
        #endif
        // Zero EMU Pro: what is owned (the last answer first, then the
        // store's), before any view reads a choice only Pro has.
        ProStore.shared.start()
        #if DEBUG
        MainThreadWatch.shared.start()
        // The iPhone Duo itself: with FOLDARC_LOG_TO_FILE — the UI
        // tests on a device set it, and OS_ACTIVITY_DT_MODE so that NSLog
        // writes to stderr too — the run's log goes on in
        // Caches/foldarc-run.log, which the Mac copies over with devicectl
        // (`log collect` from a device needs root).
        // One launch in a run leaves nothing in the file now and then
        // (the device tests of b76l: the deletion's launch); what happened to
        // the redirect is kept and said at the next launch.
        let environment = ProcessInfo.processInfo.environment
        let redirectKey = "foldarc.logRedirect"
        let lastRedirect = UserDefaults.standard.string(forKey: redirectKey)
        if environment["FOLDARC_LOG_TO_FILE"] != nil,
           let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let redirected = freopen(caches.appendingPathComponent("foldarc-run.log").path, "a", stderr) != nil
            let code = errno
            if redirected { setvbuf(stderr, nil, _IOLBF, 0) }
            UserDefaults.standard.set(redirected ? "ok (pid \(ProcessInfo.processInfo.processIdentifier))" : "freopen failed, errno \(code) (pid \(ProcessInfo.processInfo.processIdentifier))", forKey: redirectKey)
            NSLog("[run] the log goes to Caches/foldarc-run.log from here (pid %d); the launch before: %@",
                  ProcessInfo.processInfo.processIdentifier, lastRedirect ?? "nothing kept")
        } else {
            UserDefaults.standard.set(environment["FOLDARC_LOG_TO_FILE"] == nil ? "not asked for (FOLDARC_LOG_TO_FILE unset; DT mode \(environment["OS_ACTIVITY_DT_MODE"] ?? "unset"))" : "no Caches folder", forKey: redirectKey)
        }
        #endif
        LastRun.begin()
        // 11-07: the camera's pictures from before under Zero's names (once).
        CameraRoll.renameOldPicturesOnce()
        #if DEBUG
        // 11-06: how the run before this one ended, in this trace.
        OrientationTrace.shared.event("last run: " + (LastRun.previousSummary.map { "did not end cleanly; its last step \"\($0)\"" } ?? "ended cleanly or in the background"))
        // The camera's bodies on a drawn chart, when asked for
        // (`--foldarc-camera-bench`): what each makes of it, and its cost here.
        CameraBench.runIfAsked()
        // That the trace hears a run end, and that the phone keeps a crash
        // report: a run that stops itself on purpose, 3 s in.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--foldarc-crash-test") || arguments.contains("--foldarc-exit-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSLog("[run] %@: ending this run on purpose", arguments.contains("--foldarc-crash-test") ? "--foldarc-crash-test" : "--foldarc-exit-test")
                if arguments.contains("--foldarc-exit-test") { exit(3) }
                fatalError("--foldarc-crash-test")
            }
        }
        #endif
        // A scene session saved by a build that used SwiftUI's app lifecycle
        // reconnects with the delegate class it was created with (SwiftUI's
        // own), which builds no window under this lifecycle: a black screen
        // (10-27, first launch after the switch). Take such scenes over.
        NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: nil) { note in
            MainActor.assumeIsolated {
                if let scene = note.object as? UIScene { NSLog("[scene] connecting: role %@", scene.session.role.rawValue) }
                // Round 30: not a TV's scene (TV输出 has a delegate of its own).
                // Nor any other that is not an app window — the camera
                // capture accessory SwiftUI puts on the cover (iOS 27.1) was
                // taken over and given the library (946).
                guard let scene = note.object as? UIWindowScene, scene.session.role == .windowApplication,
                      !(scene.delegate is FoldArcSceneDelegate) else { return }
                OrientationTrace.shared.event("scene connecting with delegate \(scene.delegate.map { String(describing: type(of: $0)) } ?? "nil"); taking over")
                let delegate = FoldArcSceneDelegate()
                scene.delegate = delegate
                delegate.install(in: scene, urls: [])
            }
        }
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        NSLog("[scene] configuration asked for role %@", connectingSceneSession.role.rawValue)
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        // Round 30: a TV (AirPlay screen mirroring, or a cable) is TV输出's:
        // its delegate puts the console's screens there or leaves the TV
        // mirroring the iPhone. Before, the TV got a second library of its own.
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = TVSceneDelegate.self
            return configuration
        }
        configuration.delegateClass = FoldArcSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        CoverOrientationPolicy.shared.mask(for: window)
    }
    func applicationWillTerminate(_ application: UIApplication) { LastRun.end() }
}

@MainActor final class FoldArcSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // 11-05: a launch from a Home Screen quick action (read by
        // LaunchPlan when the library is built, just below).
        HomeScreenShortcuts.shared.launched(with: connectionOptions.shortcutItem)
        install(in: scene, urls: connectionOptions.urlContexts.map(\.url))
    }
    /// A Home Screen quick action while FoldArc was running.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(HomeScreenShortcuts.shared.perform(shortcutItem))
    }
    /// Builds the one window (idempotent: the take-over path in the app
    /// delegate may already have done it).
    func install(in scene: UIScene, urls: [URL]) {
        ExternalDocumentInbox.shared.receive(urls)
        guard window == nil, let windowScene = scene as? UIWindowScene else { return }
        if CoverOrientationPolicy.shared.isOnCoverDisplay(windowScene) {
            DisplayRoleMonitor.shared.launchedOnCover = true
            OrientationTrace.shared.event("scene created on the cover display")
        }
        #if DEBUG
        let window: UIWindow = TouchProbeWindow(windowScene: windowScene)
        #else
        let window = UIWindow(windowScene: windowScene)
        #endif
        window.backgroundColor = UIColor(SplashView.background)
        window.rootViewController = FoldArcRootController(rootView: AnyView(LibraryView().preferredColorScheme(.dark)))
        self.window = window
        window.makeKeyAndVisible()
        OrientationTrace.shared.event("scene window installed io=\(OrientationFormat.orientation(windowScene.effectiveGeometry.interfaceOrientation)) screen=\(OrientationFormat.screen(windowScene.screen))")
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        ExternalDocumentInbox.shared.receive(URLContexts.map(\.url))
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        AppScenePhase.shared.phase = .active; LastRun.note("active")
        // Zero EMU Pro: asked again whenever the app comes forward (a
        // subscription can have run out, or been bought on another device).
        Task { await ProStore.shared.refresh() }
        // 存档同步 (round 31): what changed elsewhere, before playing.
        SaveSyncModel.shared.syncSoon("active")
    }
    func sceneWillResignActive(_ scene: UIScene) { AppScenePhase.shared.phase = .inactive }
    func sceneWillEnterForeground(_ scene: UIScene) { AppScenePhase.shared.phase = .inactive }
    func sceneDidEnterBackground(_ scene: UIScene) {
        AppScenePhase.shared.phase = .background; LastRun.note("background")
        SaveSyncModel.shared.syncNow("background")
        // The quick actions on the icon follow 游戏记录 (11-05).
        HomeScreenShortcuts.shared.refresh()
    }

    /// Each change of the scene's interface orientation as UIKit applies it:
    /// traced, and handed to the play view's display gate (the masks are
    /// answered below; this is what actually happened).
    /// Pixel size of the display the scene was last seen on.
    private var lastScreenNativeSize: CGSize?

    @available(iOS 26.0, *)
    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry) {
        let before = previousEffectiveGeometry.interfaceOrientation
        let now = windowScene.effectiveGeometry.interfaceOrientation
        // A move to the other display need not change the orientation. (Not
        // via the geometries' coordinateSpace: the previous geometry of the
        // first call, during scene creation, has none, and reading it crashed
        // at launch, 10-27.)
        let screenSize = windowScene.screen.nativeBounds.size
        let moved = lastScreenNativeSize.map { $0 != screenSize } ?? false
        lastScreenNativeSize = screenSize
        guard before != now || moved else { return }
        OrientationTrace.shared.event("scene geometry io \(OrientationFormat.orientation(before)) -> \(OrientationFormat.orientation(now))\(moved ? " (other display)" : "") device=\(UIDevice.current.orientation.rawValue) screen=\(OrientationFormat.screen(windowScene.screen))")
        // A turn the system makes on its own (no viewWillTransition reached the
        // play view on the cover's arrival turn, 10-27) must still move
        // the display gate, or the casing waits for the 1.5 s cap.
        if let window { CoverOrientationPolicy.shared.refreshRole(window) }
    }

    /// iOS 27: replaces the Info.plist orientations for this scene. Same
    /// answer as the app delegate and the root view controller, so the three
    /// can never disagree (an empty intersection is fatal in UIKit).
    @available(iOS 27.0, *)
    @objc(supportedInterfaceOrientationsForWindowScene:)
    func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
        CoverOrientationPolicy.shared.sceneMask(for: windowScene, source: "scene")
    }
}

/// The root of the one window. Everything else is SwiftUI.
@MainActor final class FoldArcRootController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        CoverOrientationPolicy.shared.sceneMask(for: view.window?.windowScene, source: "root")
    }
    /// While a game holds the window, and whenever the window is on the cover
    /// display, the status bar is hidden at the UIKit level, not only through
    /// the hosted views' SwiftUI preference (which arrives later). The short
    /// status bar that still shows on the cover while it turns on after a lid
    /// close is the system's own: it appears with the app's bar hidden the
    /// whole time, in play too (10-28 recordings; Docs/STATUSBAR-COVER-20261028.md).
    override var prefersStatusBarHidden: Bool {
        let policy = CoverOrientationPolicy.shared, scene = view.window?.windowScene
        let lease = policy.hasLease(in: scene), cover = policy.isOnCoverDisplay(scene)
        let swiftUI = super.prefersStatusBarHidden
        let hidden = lease || cover || swiftUI
        if hidden != lastStatusBarHidden {
            lastStatusBarHidden = hidden
            OrientationTrace.shared.event("status bar \(hidden ? "hidden" : "shown") lease=\(lease) cover=\(cover) swiftui=\(swiftUI)")
        }
        return hidden
    }
    private var lastStatusBarHidden: Bool?
    /// b37: TV输出's scene accessory (iOS 27; see TVOutput) belongs to the
    /// app's main view controller, and its availability is read here, in the
    /// pass UIKit re-runs when it changes.
    override func viewDidLoad() {
        super.viewDidLoad()
        TVOutput.shared.registerAccessory(on: self)
    }
    /// 11-06: the window may have moved to another of the iPhone Duo's
    /// screens (CoverOrientationPolicy learns which is which).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let window = view.window { CoverOrientationPolicy.shared.rootLaidOut(window) }
    }
    #if DEBUG
    /// Which edge
    /// the system's safe area grows on (the iPhone Duo's inner camera).
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let scene = view.window?.windowScene
        let line = "safe area \(OrientationFormat.insets(view.safeAreaInsets)) view=\(OrientationFormat.size(view.bounds.size)) io=\(OrientationFormat.orientation(scene?.effectiveGeometry.interfaceOrientation ?? .unknown)) screen=\(OrientationFormat.screen(scene?.screen))"
        OrientationTrace.shared.event(line)
        NSLog("[layout] %@", line)
    }
    #endif
    override func updateProperties() {
        super.updateProperties()
        TVOutput.shared.readAccessory(from: self)
    }
    // Not overridden: prefersInterfaceOrientationLocked (iOS 26). It was
    // tried on 10-27 and the system never engaged it on either Duo display
    // (effectiveGeometry.isInterfaceOrientationLocked stayed false); the
    // single-orientation masks of a full-screen scene are what hold both
    // displays still. A lock that engaged later could block the one turn the
    // policy needs when the scene arrives on the inner display.
}

/// Scene phase for SwiftUI views hosted under the UIKit lifecycle, where the
/// `scenePhase` environment value is not driven by a SwiftUI scene.
@MainActor final class AppScenePhase: ObservableObject {
    static let shared = AppScenePhase()
    @Published var phase: ScenePhase = .inactive
}

/// Files handed to FoldArc by the system ("Open in FoldArc"), queued until
/// the library takes them. Replaces SwiftUI's onOpenURL, which only fires
/// under the SwiftUI app lifecycle.
@MainActor final class ExternalDocumentInbox: ObservableObject {
    static let shared = ExternalDocumentInbox()
    @Published private(set) var pending: [URL] = []
    func receive(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { pending.append(contentsOf: files) }
    }
    func take() -> [URL] {
        let taken = pending
        if !taken.isEmpty { pending = [] }
        return taken
    }
}

/// Orientation policy for the game window on Duo's two displays.
///
/// What the 10-27 traces and recordings established (iPhone Duo simulator,
/// iOS 27.1): by default the inner display runs in a windowing mode that
/// ignores masks, refuses geometry requests and turns the scene with gravity
/// (animated, system-driven); with `UIRequiresFullScreen` it honours masks
/// like an iPhone. The cover display honours the per-scene mask. So while a
/// game holds the window each display gets exactly one orientation (cover:
/// portrait, inner: the handheld reference), the masks are re-read on every
/// change of display and the display's orientation is requested once; the
/// casing and the handheld are drawn in the panel's fixed frame and stay
/// hidden until that orientation is reached. Nothing turns afterwards.
@MainActor final class CoverOrientationPolicy {
    static let shared = CoverOrientationPolicy()
    private let owners = NSMapTable<UIWindow, NSNumber>.weakToStrongObjects()
    private let displayAnchors = NSMapTable<UIWindow, DisplayAnchor>.weakToStrongObjects()
    private let lastMaskReports = NSMapTable<UIWindow, NSString>.weakToStrongObjects()
    /// Latest hardware hinge state per game window (true = closed / closing).
    private let lidStates = NSMapTable<UIWindow, NSNumber>.weakToStrongObjects()
    private var queryCount = 0
    private var lastLockReport = ""
    /// Until play first takes the window (or the library is shown without
    /// it), the scene holds the orientation it was launched in. See `heldMask`.
    private(set) var launchHold = true

    /// Orientation each display is asked for while the game holds the window:
    /// the cover's native portrait, and on the inner display the handheld
    /// reference pose (lower screen on the side-button half, which UIKit calls
    /// portraitUpsideDown there). Preferences only — the layout never depends
    /// on them being honoured.
    static let coverMask: UIInterfaceOrientationMask = .portrait
    static let innerMask: UIInterfaceOrientationMask = .portraitUpsideDown
    /// 11-06: the library on the inner display, no game holding the
    /// window, turns with the Duo — but by FoldArc's own reading of how it is
    /// held, one orientation at a time (heldInterface). Upside-down portrait
    /// alone (the handheld's pose) put a Duo held across into the small
    /// 469 × 669 window (真机 traces); b66's three orientations
    /// let the system choose, and it chose landscape for the handheld's pose
    /// (a trace: device 4 →
    /// landscapeLeft). A game takes the window back to `innerMask`.
    ///
    /// How the Duo is held, as the device reports it (from its traces):
    /// the handheld's pose — crease across, the side-button half down — is
    /// the device's landscapeRight, and its interface is portraitUpsideDown
    /// (the inner display's own portrait turned round); held across like a
    /// book, the USB-C edge down, is the device's portrait, whose interface
    /// is landscapeLeft (the window launched so from the Home Screen). The
    /// inner display is turned a quarter against the device: each pose's
    /// interface is the usual one a quarter on.
    static func innerInterface(held device: UIDeviceOrientation) -> UIInterfaceOrientation? {
        switch device {
        case .landscapeRight: return .portraitUpsideDown
        case .landscapeLeft: return .portrait
        case .portrait: return .landscapeLeft
        case .portraitUpsideDown: return .landscapeRight
        default: return nil
        }
    }
    static func mask(_ orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portraitUpsideDown
        }
    }
    /// The library's orientation on the inner display, from how the Duo is
    /// held (the handheld's pose until the device says otherwise; flat on a
    /// table it keeps the last).
    private(set) var heldInterface = UIInterfaceOrientation.portraitUpsideDown
    private var heldToken: NSObjectProtocol?
    private func watchHold() {
        guard heldToken == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        heldToken = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CoverOrientationPolicy.shared.deviceMaybeTurned() }
        }
        if let first = Self.innerInterface(held: deviceHold) {
            heldInterface = first
        } else if let shown = shownInnerInterface() {
            // 11-11 (真机: the Duo lying flat on a table, across; 系统设置 in
            // the small 469 × 669 window, black to both sides): flat, the device
            // says nothing of how it is held (face up), so the hold stayed
            // the handheld's pose it starts as, the library asked for that
            // orientation, and the system — showing the window across, as
            // it had launched it (951 × 669 landscapeLeft in the run's log)
            // — put it in the small window a second and a half after launch.
            // Flat, the hold is the way the window is shown now.
            heldInterface = shown
        }
        OrientationTrace.shared.event("hold first read: device \(deviceHold.rawValue) -> \(OrientationFormat.orientation(heldInterface))")
        NSLog("[hold] first read: device %d -> %@", deviceHold.rawValue, OrientationFormat.orientation(heldInterface))
        // (Asked from UIKit's mask queries, which can come during a view
        // update: published after it.)
        let across = heldInterface.isLandscape
        DispatchQueue.main.async { DisplayRoleMonitor.shared.publish(heldAcross: across) }
    }
    /// How the inner display's window is shown now (the app's own window,
    /// not the cover's): the hold, when the device does not say (flat).
    private func shownInnerInterface() -> UIInterfaceOrientation? {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where scene.session.role == .windowApplication {
            guard hardwareRole(in: scene) == false else { continue }
            let shown = scene.effectiveGeometry.interfaceOrientation
            if shown == .portrait || shown == .portraitUpsideDown || shown == .landscapeLeft || shown == .landscapeRight { return shown }
        }
        return nil
    }
    /// Play on a Duo (11-07): the hold is read from the start, so that a
    /// game started held across comes up in 手柄模式.
    func watchHoldForPlay() { watchHold() }
    /// How the device is held, as UIDevice says (DEBUG: as a test says).
    private var deviceHold: UIDeviceOrientation {
        #if DEBUG
        if let forcedHold { return forcedHold }
        #endif
        return UIDevice.current.orientation
    }
    /// 11-15 (真机, b80x: half open, the device's reading went between the
    /// handheld's pose and the book's several times a second, and the whole
    /// screen turned with each): a turn counts once the reading has stayed
    /// put — half a second, nine tenths with the hinge half open.
    private var turnCheck: Task<Void, Never>?
    private func deviceMaybeTurned() {
        turnCheck?.cancel()
        let seen = deviceHold
        let wait: Duration = HingePosture.shared.status == .partiallyOpen ? .milliseconds(900) : .milliseconds(500)
        turnCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, !Task.isCancelled, self.deviceHold == seen else { return }
            self.deviceTurned()
        }
    }
    private func deviceTurned() {
        let device = deviceHold
        guard let next = Self.innerInterface(held: device), next != heldInterface else { return }
        heldInterface = next
        OrientationTrace.shared.event("held: device \(device.rawValue) -> the library \(OrientationFormat.orientation(next))")
        DisplayRoleMonitor.shared.publish(heldAcross: next.isLandscape)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where scene.session.role == .windowApplication {
            // 11-07: a game in 手柄模式 held across turns with the hold too
            // (back to the handheld's own orientation when the hold is the
            // handheld's: b70d on the iPhone Duo turned it to the hold's
            // first, then back — two turns).
            if playFollowsHold, let window = leasedWindow(in: scene), role(of: window) == false {
                updatePreferences(window)
                if window.windowScene?.effectiveGeometry.interfaceOrientation != playInnerInterface { requestOrientation(window, playInnerMask) }
                continue
            }
            // The library's window on the inner display (no game holding it)
            // turns now.
            guard !launchHold, leasedWindow(in: scene) == nil, hardwareRole(in: scene) == false else { continue }
            for window in scene.windows where window.rootViewController is FoldArcRootController {
                updatePreferences(window)
                if window.windowScene?.effectiveGeometry.interfaceOrientation != next { requestOrientation(window, Self.mask(next)) }
            }
        }
    }

    /// 11-07: while play is in 手柄模式
    /// (or TV模式) on the inner display and the Duo is held across, the
    /// game's window turns with the hold as the library's does, so the
    /// controller lies across the whole display; otherwise it keeps the
    /// handheld's one orientation (innerMask). PlayView says which.
    private(set) var playFollowsHold = false
    /// The game window's orientation on the inner display: the hold's while
    /// play follows it held across, else the handheld's (innerMask).
    private var playInnerInterface: UIInterfaceOrientation {
        playFollowsHold && heldInterface.isLandscape ? heldInterface : .portraitUpsideDown
    }
    private var playInnerMask: UIInterfaceOrientationMask { Self.mask(playInnerInterface) }
    func setPlayFollowsHold(_ on: Bool) {
        guard playFollowsHold != on else { return }
        playFollowsHold = on
        OrientationTrace.shared.event("play follows the hold: \(on) (held \(OrientationFormat.orientation(heldInterface)))")
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where scene.session.role == .windowApplication {
            guard let window = leasedWindow(in: scene), role(of: window) == false else { continue }
            updatePreferences(window)
            if window.windowScene?.effectiveGeometry.interfaceOrientation != playInnerInterface { requestOrientation(window, playInnerMask) }
        }
    }
    #if DEBUG
    /// `--foldarc-hold=book|book-down|handheld|handheld-down`, and
    /// `--foldarc-hold-script=<seconds>:<hold>,…` (seconds after play first
    /// asks): how the Duo is held, as UIDevice would say it — for the Duo
    /// Simulator, which XCUIDevice cannot turn (11-07).
    private var forcedHold: UIDeviceOrientation? = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--foldarc-hold=") }
        .flatMap { CoverOrientationPolicy.debugHold(String($0.dropFirst("--foldarc-hold=".count))) }
    static func debugHold(_ name: String) -> UIDeviceOrientation? {
        switch name {
        case "book": return .portrait
        case "book-down": return .portraitUpsideDown
        case "handheld": return .landscapeRight
        case "handheld-down": return .landscapeLeft
        default: return nil
        }
    }
    private var holdScriptStarted = false
    func startHoldScript() {
        guard !holdScriptStarted, let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-hold-script=") }) else { return }
        holdScriptStarted = true
        let steps = argument.dropFirst("--foldarc-hold-script=".count).split(separator: ",").compactMap { step -> (Double, UIDeviceOrientation)? in
            let parts = step.split(separator: ":")
            guard parts.count == 2, let at = Double(parts[0]), let hold = Self.debugHold(String(parts[1])) else { return nil }
            return (at, hold)
        }
        for (at, hold) in steps {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(at * 1000)))
                NSLog("[hold] script: device orientation %d", hold.rawValue)
                self.forcedHold = hold
                self.watchHold()
                self.deviceTurned()
            }
        }
    }
    #endif

    @MainActor private final class DisplayAnchor: NSObject {
        let screen: UIScreen
        let nativeSize: CGSize
        /// The hinge when play took the window: the last answer, when the
        /// screen is not known and the hinge has not been heard.
        var isOuter: Bool
        init(screen: UIScreen, isOuter: Bool) {
            self.screen = screen
            self.nativeSize = screen.nativeBounds.size
            self.isOuter = isOuter
        }
    }

    /// Which built-in display a screen is: true the cover, false the inner
    /// display (whole, or its half while the lid is part open), nil not
    /// known (no hinge: not a Duo).
    ///
    /// 11-06 (真机, a trace): the iPhone Duo puts the window on three
    /// screens, not two — the cover (466 × 678 points, 1398 × 2034 pixels),
    /// the inner display (669 × 951, 2007 × 2853) and, with the lid part
    /// open, half of the inner display (469 × 669, 1407 × 2007), which is a
    /// little smaller than the cover. The rule before ("of the two displays
    /// the smaller is the cover") took that half for the cover and the cover
    /// for the inner display, and kept it: the casing on the inner display,
    /// the library (or the handheld) on the cover. The inner display also
    /// comes back as a new UIScreen object after a move, so identity says
    /// nothing either. Now: the sizes learned from the hinge (KnownDisplays),
    /// else what the hinge says now (it reports ~50 ms before the window
    /// moves on the device), else the hinge when play took the window.
    private func screenRole(_ screen: UIScreen?, anchor: DisplayAnchor?) -> Bool? {
        if let known = KnownDisplays.role(of: screen) { return known }
        if let status = HingePosture.shared.status { return status == .closed }
        return anchor?.isOuter
    }

    /// The displays' pixel sizes, learned from the hinge (DisplayRoleBook)
    /// and kept across launches. New keys: what the old rule saved can be
    /// wrong (a trace saved the cover as the inner display).
    @MainActor enum KnownDisplays {
        private static let coverKey = "foldarc.display.cover.v2"
        private static let innerKey = "foldarc.display.inner.v2"
        static var book: DisplayRoleBook {
            let defaults = UserDefaults.standard
            var kept = DisplayRoleBook(cover: defaults.string(forKey: coverKey).map { NSCoder.cgSize(for: $0) },
                                       inner: (defaults.stringArray(forKey: innerKey) ?? []).map { NSCoder.cgSize(for: $0) })
            // What the rule before could leave (the cover among the inner
            // display's sizes) is taken out here, once, and learned again.
            if kept.mend() {
                save(kept)
                OrientationTrace.shared.event("known displays: mended; the inner display \(kept.inner.map { OrientationFormat.size($0) }.joined(separator: ", ")), the cover \(kept.cover.map { OrientationFormat.size($0) } ?? "not known")")
                NSLog("[display] the kept displays were mended")
            }
            return kept
        }
        private static func save(_ book: DisplayRoleBook) {
            let defaults = UserDefaults.standard
            if let cover = book.cover { defaults.set(NSCoder.string(for: cover), forKey: coverKey) } else { defaults.removeObject(forKey: coverKey) }
            defaults.set(book.inner.map { NSCoder.string(for: $0) }, forKey: innerKey)
        }
        /// true = cover display, false = inner display, nil = not learned.
        static func role(of screen: UIScreen?) -> Bool? {
            guard let screen else { return nil }
            return book.role(of: screen.nativeBounds.size)
        }
        /// true if what is known changed.
        @discardableResult static func learn(_ screen: UIScreen, outer: Bool) -> Bool {
            let size = screen.nativeBounds.size
            var next = book
            guard next.learn(size, outer: outer) else { return false }
            save(next)
            let now = next.role(of: size).map { $0 ? "the cover" : "the inner display" } ?? "not known"
            OrientationTrace.shared.event("known displays: \(OrientationFormat.size(size)) is \(now)")
            NSLog("[display] %@ is %@", OrientationFormat.size(size), now)
            return true
        }
    }

    // MARK: Learning the displays from the hinge

    private weak var watchedWindow: UIWindow?
    private var watchedSize: CGSize?
    private var learning: Task<Void, Never>?
    /// The window FoldArc draws in, from the UIKit hooks: when it is on
    /// another screen, the screen is learned once the hinge and the window
    /// have stood still for a moment.
    func noteWindow(_ window: UIWindow) {
        let size = window.windowScene?.screen.nativeBounds.size
        guard window !== watchedWindow || size != watchedSize else { return }
        watchedWindow = window
        watchedSize = size
        scheduleLearning()
    }
    /// The root controller laid out (the window may be on another screen):
    /// learning, and without a game the library's display.
    func rootLaidOut(_ window: UIWindow) {
        noteWindow(window)
        if owners.object(forKey: window) == nil { refreshLibraryRole(window) }
    }
    /// The hinge's status changed (HingePosture).
    func hingeChanged() {
        scheduleLearning()
        // A screen not learned yet takes its role from the hinge: tell the
        // views (the library's or play's display).
        if let window = watchedWindow {
            if owners.object(forKey: window) != nil { refreshRole(window) } else { refreshLibraryRole(window) }
        }
    }
    private func scheduleLearning() {
        learning?.cancel()
        guard let window = watchedWindow, let screen = window.windowScene?.screen,
              let status = HingePosture.shared.status, status != .partiallyOpen else { return }
        let size = screen.nativeBounds.size
        learning = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, let window = self.watchedWindow, let now = window.windowScene?.screen,
                  now.nativeBounds.size == size, HingePosture.shared.status == status else { return }
            // Only with the app in front: in the background the window
            // stays on the screen it was on while the hinge goes on
            // reporting (the cover was learned as the inner display so).
            guard UIApplication.shared.applicationState == .active, window.windowScene?.activationState == .foregroundActive else { return }
            // What is known now may give the window another role: the views are told.
            if KnownDisplays.learn(now, outer: status == .closed) {
                if self.owners.object(forKey: window) != nil { self.refreshRole(window) } else { self.refreshLibraryRole(window) }
            }
        }
    }

    /// Which built-in display a scene is on while play does not hold a
    /// window. nil when the device has no hinge (not a Duo) or it never
    /// reported.
    private func hardwareRole(in scene: UIWindowScene?) -> Bool? {
        guard let scene else { return nil }
        for window in scene.windows {
            if let anchor = displayAnchors.object(forKey: window) {
                return screenRole(window.windowScene?.screen, anchor: anchor)
            }
        }
        return screenRole(scene.screen, anchor: nil)
    }

    /// The game window in this scene, if play holds the lease.
    private func leasedWindow(in scene: UIWindowScene?) -> UIWindow? {
        guard let scene else { return nil }
        return scene.windows.first { (owners.object(forKey: $0)?.intValue ?? 0) > 0 }
    }
    /// true = cover display, false = inner display, nil = no hardware anchor.
    private func role(of window: UIWindow) -> Bool? {
        guard let anchor = displayAnchors.object(forKey: window), let screen = window.windowScene?.screen else { return nil }
        return screenRole(screen, anchor: anchor)
    }

    /// One answer for the scene and every window in it (game, keyboard,
    /// sheets): UIKit intersects the scene's, the app delegate's and the root
    /// controller's masks, and an empty intersection is fatal.
    func sceneMask(for scene: UIWindowScene?, source: String) -> UIInterfaceOrientationMask {
        // A scene that is not FoldArc's window — the camera capture
        // accessory on the cover (iOS 27.1) — says nothing about where the
        // library or play is (946: it read as "the lid shut over the library").
        if let scene, scene.session.role != .windowApplication { return .all }
        queryCount += 1
        guard let window = leasedWindow(in: scene), let outer = role(of: window) else {
            // No game holds the window (the library and its sheets). On Duo
            // hardware each display keeps its one orientation anyway: answering
            // `.all` here let SpringBoard turn the inner display to portrait
            // every time a game ended (Pd -> Pu, animated, leaving the library
            // upside down for the person holding the handheld) and back, twice,
            // when the next one started (10-27 SpringBoard log).
            if !launchHold, let outer = hardwareRole(in: scene) {
                // On the cover the library hands over to the closed casing
                // (portrait, like play), so the window keeps one orientation
                // per display whatever is on it. On the inner display: as
                // the Duo is held.
                if !outer { watchHold() }
                let mask = outer ? Self.coverMask : Self.mask(heldInterface)
                if DisplayRoleMonitor.shared.libraryOnCover != outer {
                    DispatchQueue.main.async { DisplayRoleMonitor.shared.publishLibrary(onCover: outer) }
                }
                report(nil, "mask query #\(queryCount) [\(source)] no game lease, \(outer ? "outer" : "inner") display -> \(OrientationFormat.mask(mask))")
                return mask
            }
            let mask = launchHold ? heldMask(for: scene) : .all
            report(nil, "mask query #\(queryCount) [\(source)] no game lease\(launchHold ? " (launch hold)" : "") -> \(OrientationFormat.mask(mask))")
            return mask
        }
        DisplayRoleMonitor.shared.publish(outer)
        if !outer { watchHold() }
        let mask = outer ? Self.coverMask : playInnerMask
        report(window, "mask query #\(queryCount) [\(source)] role=\(outer ? "outer" : "inner") -> \(OrientationFormat.mask(mask)) io=\(OrientationFormat.orientation(window.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown)) \(lockDescription(window))")
        return mask
    }
    func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        sceneMask(for: window?.windowScene, source: "app")
    }

    /// Mask while launching (splash, before the game takes the window): the
    /// orientation the scene was launched in, i.e. the one SpringBoard is
    /// already showing, so nothing turns at launch. Not `.all`: answering
    /// `.all` the scene reported "( Pu Ll Lr )" to the system — upside down
    /// left out, as iPhone does — while the inner display's reference pose
    /// is portraitUpsideDown, so SpringBoard turned the whole inner display
    /// to portrait at every open-lid launch and the lease turned it back:
    /// two animated 180° turns over the splash (10-27 SpringBoard log:
    /// "Active interface orientation changing from portraitUpsideDown (2) to
    /// portrait (1)" and back). Not the display's play orientation either: on the
    /// cover display that made SpringBoard turn the launch zoom from
    /// landscape to portrait; the lease makes that turn later,
    /// unanimated and behind the splash, as before.
    private func heldMask(for scene: UIWindowScene?) -> UIInterfaceOrientationMask {
        guard let scene else { return .all }
        switch scene.effectiveGeometry.interfaceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default:
            if let outer = KnownDisplays.role(of: scene.screen) { return outer ? Self.coverMask : Self.innerMask }
            return .all
        }
    }

    /// The library came up without play taking the window (no hinge: not a
    /// Duo, or the hinge is silent): from now on it may turn freely.
    func endLaunchHold() {
        guard launchHold else { return }
        launchHold = false
        OrientationTrace.shared.event("launch hold ended without a game")
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows where window.rootViewController is FoldArcRootController { updatePreferences(window) }
        }
    }

    /// Whether play holds a window in this scene.
    func hasLease(in scene: UIWindowScene?) -> Bool { leasedWindow(in: scene) != nil }
    /// On Duo hardware the cover display only ever shows the closed casing
    /// (or the splash), so the app never asks for a status bar there, game
    /// or not.
    func isOnCoverDisplay(_ scene: UIWindowScene?) -> Bool { hardwareRole(in: scene) == true }

    private func lockDescription(_ window: UIWindow) -> String {
        if #available(iOS 26.0, *) {
            return "locked=\(window.windowScene?.effectiveGeometry.isInterfaceOrientationLocked == true)"
        }
        return "locked=n/a"
    }

    /// Recompute which display the window is on and publish it. Call from
    /// every UIKit hook that can fire around a display migration.
    func refreshRole(_ window: UIWindow) {
        noteWindow(window)
        guard owners.object(forKey: window) != nil, let outer = role(of: window),
              let screen = window.windowScene?.screen else {
            DisplayRoleMonitor.shared.publish(nil)
            refreshLibraryRole(window)
            return
        }
        DisplayRoleMonitor.shared.publish(outer)
        DisplayRoleMonitor.shared.publish(interfaceRotation: DisplayRoleMonitor.interfaceRotation(of: screen))
        let io = window.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown
        let line = "role=\(outer ? "outer" : "inner") io=\(OrientationFormat.orientation(io)) \(lockDescription(window))"
        if line != lastLockReport {
            lastLockReport = line
            OrientationTrace.shared.event("orientation state \(line)")
        }
        // Each display has exactly one supported orientation while playing
        // (cover: portrait, inner: the handheld reference). With the scene
        // full screen (UIRequiresFullScreen) the inner display honours masks
        // like an iPhone instead of turning with gravity; UIKit only re-reads
        // them when asked, so ask on every change of display, then request the
        // display's orientation in case the scene arrived in another one. The
        // turn happens behind the settle gate (content hidden), and from then
        // on nothing can rotate the scene.
        if outer != preferencesRole {
            preferencesRole = outer
            // (11-07: 手柄模式 held across: the hold's.)
            let target: UIInterfaceOrientation = outer ? .portrait : playInnerInterface
            let mask = outer ? Self.coverMask : playInnerMask
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.owners.object(forKey: window) != nil else { return }
                self.updatePreferences(window)
                let now = window.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown
                if now != target { self.requestOrientation(window, mask) }
            }
        }
    }
    /// Display for which the masks were last re-read (nil = not yet).
    private var preferencesRole: Bool?

    /// Without a game on Duo hardware: publish which display the library is
    /// on (the cover hands over to the closed casing) and have UIKit re-read
    /// the masks for it. UIKit does not always ask again by itself after the
    /// window moves display: the second lid close over the library in a row
    /// left the library on the cover, sideways (10-27 trace).
    private func refreshLibraryRole(_ window: UIWindow) {
        guard !launchHold, let scene = window.windowScene, let outer = hardwareRole(in: scene),
              DisplayRoleMonitor.shared.libraryOnCover != outer else { return }
        DisplayRoleMonitor.shared.publishLibrary(onCover: outer)
        updatePreferences(window)
        // The library comes to the inner display turned as the Duo is held.
        if !outer {
            watchHold()
            let held = heldInterface
            if window.windowScene?.effectiveGeometry.interfaceOrientation != held {
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.owners.object(forKey: window) == nil else { return }
                    self.requestOrientation(window, Self.mask(held))
                }
            }
        }
        // 11-06: the library stays on the cover now (no casing to take the
        // window and turn it): ask for the cover's upright once, should the
        // window have come over turned.
        if outer, window.windowScene?.effectiveGeometry.interfaceOrientation != .portrait {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.owners.object(forKey: window) == nil else { return }
                self.requestOrientation(window, Self.coverMask)
            }
        }
    }

    private func requestOrientation(_ window: UIWindow, _ mask: UIInterfaceOrientationMask) {
        OrientationTrace.shared.event("requestGeometryUpdate \(OrientationFormat.mask(mask))")
        window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            Task { @MainActor in OrientationTrace.shared.event("requestGeometryUpdate \(OrientationFormat.mask(mask)) error: \(error.localizedDescription)") }
        }
    }

    /// Hardware hinge state for a leased window (trace only: the lock and the
    /// fixed-frame drawing do not depend on the hinge report).
    func lidStateChanged(_ window: UIWindow, closed: Bool?) {
        let previous = lidStates.object(forKey: window)?.boolValue
        if let closed { lidStates.setObject(NSNumber(value: closed), forKey: window) } else { lidStates.removeObject(forKey: window) }
        if previous != closed {
            OrientationTrace.shared.event("lid \(closed.map { $0 ? "closing" : "open" } ?? "unknown") reported on \(DisplayRoleMonitor.shared.isOuter.map { $0 ? "cover" : "inner" } ?? "unknown") display \(lockDescription(window))")
        }
    }

    /// Log only when the answer or its inputs change; UIKit queries often.
    private var lastWindowlessReport = ""
    private func report(_ window: UIWindow?, _ message: String) {
        let key = message.replacingOccurrences(of: "#\(queryCount)", with: "#")
        if let window {
            if lastMaskReports.object(forKey: window) as String? == key { return }
            lastMaskReports.setObject(key as NSString, forKey: window)
        } else {
            if lastWindowlessReport == key { return }
            lastWindowlessReport = key
        }
        OrientationTrace.shared.event(message)
    }

    func attachHardwareContext(_ window: UIWindow, deviceLidClosed: Bool?) {
        // A debug cover preview can enter play before the first hinge report.
        // Bind that first report without releasing/reacquiring the window lease.
        // Once bound, subsequent hinge updates must not relabel either display.
        guard owners.object(forKey: window) != nil,
              displayAnchors.object(forKey: window) == nil,
              let deviceLidClosed, let screen = window.windowScene?.screen else { return }
        displayAnchors.setObject(DisplayAnchor(screen: screen, isOuter: deviceLidClosed), forKey: window)
        OrientationTrace.shared.event("attachHardwareContext late anchor=\(deviceLidClosed ? "outer" : "inner") screen=\(OrientationFormat.screen(screen))")
        refreshRole(window)
        updatePreferences(window)
    }

    func acquire(_ window: UIWindow, deviceLidClosed: Bool?) {
        let count = owners.object(forKey: window)?.intValue ?? 0
        owners.setObject(NSNumber(value: count + 1), forKey: window)
        launchHold = false
        if count == 0 {
            if let deviceLidClosed, let screen = window.windowScene?.screen {
                displayAnchors.setObject(DisplayAnchor(screen: screen, isOuter: deviceLidClosed), forKey: window)
                lidStates.setObject(NSNumber(value: deviceLidClosed), forKey: window)
            } else {
                // A preview without hinge: no anchor left over from an earlier game.
                displayAnchors.removeObject(forKey: window)
            }
            OrientationTrace.shared.event("acquired handheld window; anchor=\(deviceLidClosed.map { $0 ? "outer" : "inner" } ?? "preview") screen=\(OrientationFormat.screen(window.windowScene?.screen)) io=\(OrientationFormat.orientation(window.windowScene?.effectiveGeometry.interfaceOrientation ?? .unknown))")
            refreshRole(window)
            updatePreferences(window)
        }
    }

    func release(_ window: UIWindow) {
        let count = owners.object(forKey: window)?.intValue ?? 0
        if count > 1 {
            owners.setObject(NSNumber(value: count - 1), forKey: window)
        } else if count == 1 {
            owners.removeObject(forKey: window)
            // The display anchor stays: the window is still on the same
            // hardware, and without a game it keeps that display's
            // orientation (see sceneMask).
            lastMaskReports.removeObject(forKey: window)
            lidStates.removeObject(forKey: window)
            preferencesRole = nil
            OrientationTrace.shared.event("released handheld window")
            DisplayRoleMonitor.shared.publish(nil)
            updatePreferences(window)
        }
    }

    /// Ask UIKit to re-read the masks (geometry requests are made separately,
    /// once per change of display, in refreshRole).
    private func updatePreferences(_ window: UIWindow) {
        UIView.performWithoutAnimation {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                current.setNeedsStatusBarAppearanceUpdate()
                controller = current.presentedViewController
            }
        }
        OrientationTrace.shared.event("preferences updated lease=\(leasedWindow(in: window.windowScene) != nil) \(lockDescription(window))")
    }
}

/// A window-scoped lease survives Duo lid changes and ends when play leaves.
struct CoverOrientationLock: UIViewRepresentable {
    var deviceLidClosed: Bool?
    var captureFrames = false
    func makeUIView(context: Context) -> LockView {
        let view = LockView()
        view.deviceLidClosed = deviceLidClosed
        #if DEBUG
        view.captureFrames = captureFrames
        #endif
        return view
    }
    func updateUIView(_ uiView: LockView, context: Context) {
        uiView.deviceLidClosed = deviceLidClosed
        #if DEBUG
        uiView.captureFrames = captureFrames
        #endif
    }
    static func dismantleUIView(_ uiView: LockView, coordinator: ()) { uiView.detach() }

    final class LockView: UIView {
        var deviceLidClosed: Bool? {
            didSet {
                if oldValue != deviceLidClosed {
                    OrientationTrace.shared.event("swiftui lid=\(deviceLidClosed.map { String($0) } ?? "nil") (from \(oldValue.map { String($0) } ?? "nil"))")
                    #if DEBUG
                    sampler.lidDescription = deviceLidClosed.map { String($0) } ?? "nil"
                    sampler.markInteresting(3)
                    #endif
                }
                if let registeredWindow {
                    CoverOrientationPolicy.shared.attachHardwareContext(registeredWindow, deviceLidClosed: deviceLidClosed)
                    CoverOrientationPolicy.shared.lidStateChanged(registeredWindow, closed: deviceLidClosed)
                }
            }
        }
        private weak var registeredWindow: UIWindow?
        #if DEBUG
        private let sampler = OrientationSampler()
        private var hingeInteraction: UIInteraction?
        var captureFrames: Bool {
            get { sampler.captureFrames }
            set { sampler.captureFrames = newValue }
        }
        #endif
        /// The lease is taken one main-queue turn after the view reaches its
        /// window, and given back one turn after it leaves (see didMoveToWindow).
        private var leaseTaken = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window !== registeredWindow else { return }
            detach()
            if let window {
                registeredWindow = window
                // Behind the play window's turns: the casing's dark (11-07: the
                // splash's own background follows the system's appearance).
                window.backgroundColor = UIColor(SplashView.windowBackground)
                // SwiftUI adds this view inside a view update, and taking the
                // lease publishes the display role: "Publishing changes from
                // within view updates is not allowed", three to eight runtime
                // faults at every game start (10-27 log, matched to the trace).
                // One main-queue turn later is outside the update. Until then
                // the play view goes by the hinge state and keeps the handheld
                // behind the display gate, as on every arrival; masks answer
                // the same per display with or without the lease.
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window, self.registeredWindow === window, !self.leaseTaken else { return }
                    self.leaseTaken = true
                    CoverOrientationPolicy.shared.acquire(window, deviceLidClosed: self.deviceLidClosed)
                }
                #if DEBUG
                sampler.lidDescription = deviceLidClosed.map { String($0) } ?? "nil"
                sampler.attach(window)
                installHingeObserver()
                #endif
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let window { CoverOrientationPolicy.shared.refreshRole(window) }
        }
        private var traitRegistration: (any UITraitChangeRegistration)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            // Size classes and display scale change when the window moves
            // between Duo's displays; refresh the role on each of them.
            traitRegistration = registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self, UITraitDisplayScale.self]) { (view: LockView, _) in
                if let window = view.window { CoverOrientationPolicy.shared.refreshRole(window) }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        func detach() {
            // Also outside SwiftUI's update (dismantleUIView runs inside it).
            if let registeredWindow, leaseTaken {
                leaseTaken = false
                DispatchQueue.main.async { CoverOrientationPolicy.shared.release(registeredWindow) }
            }
            registeredWindow = nil
            #if DEBUG
            sampler.detach()
            #endif
        }
        #if DEBUG
        /// UIKit-level hinge updates, timestamped next to the per-frame samples.
        private func installHingeObserver() {
            guard hingeInteraction == nil else { return }
            #if FOLDARC_DUO_SDK
            if #available(iOS 27.1, *) {
                let interaction = UIHingeInteraction { [weak self] _, update in
                    guard let self else { return }
                    let description: String
                    if let hinge = update.hinge {
                        let status: String
                        switch hinge.status {
                        case .closed: status = "closed"
                        case .partiallyOpen: status = "partiallyOpen"
                        case .fullyOpen: status = "fullyOpen"
                        default: status = "unknown"
                        }
                        description = "\(status)/\(String(format: "%.2f", hinge.angle))"
                    } else { description = "nil" }
                    self.sampler.hingeDescription = description
                    self.sampler.markInteresting(3)
                    let scene = self.window?.windowScene
                    OrientationTrace.shared.event("uikit hinge \(description) screen=\(OrientationFormat.screen(scene?.screen)) io=\(OrientationFormat.orientation(scene?.effectiveGeometry.interfaceOrientation ?? .unknown)) wb=\(OrientationFormat.size(self.window?.bounds.size ?? .zero))")
                }
                addInteraction(interaction)
                hingeInteraction = interaction
            }
            #endif
        }
        #endif
    }
}
#endif

struct LibraryView: View {
    @StateObject private var library = LibraryModel()
    @ViewState private var importing = false
    @ViewState private var showingDemo = false
    @ViewState private var selected: GameRecord?
    @ViewState private var deviceLidClosed: Bool?
    /// Set when a game should run on the real core instead of the demo.
    @ViewState private var coreGame: URL?
    /// One of the console's built-in programs (round 23): 系统设置, or the
    /// first-time setup. Runs in the play view like software.
    @ViewState private var consoleApp: ConsoleApp?
    /// Start `coreGame` from its resume state ("继续上次").
    @ViewState private var resumeGame = false
    /// One of the library's own functions the console's menu (round 26:
    /// the program) asked for: the library opens it once it is back.
    @ViewState private var homeItemOnArrival: ConsoleHomeItem?
    /// The lid was closed over the library with 铅笔盒 or 画框 open on its
    /// console: PlayView shows only its cover (the box's lid, the frame's
    /// scenery) and hands back to the library when the lid opens.
    @ViewState private var coverOnly = false
    /// The library asked for on the cover (the cover's menu, 返回游戏库): it
    /// stays there until the lid opens.
    @ViewState private var libraryAskedOnCover = false
    /// 11-15: the lid shut over the library with 铅笔盒 or 画框 open on its
    /// console: the cover goes with it (the box's lid, the frame's scenery),
    /// and it opens again with the lid.
    @ViewState private var coverInside: ConsoleApp?
    /// 11-15: the camera's album was open inside when the lid shut: the
    /// cover's camera opens on its album.
    @ViewState private var cameraAlbumFirst = false
    @ViewState private var showingSplash = true      // opaque / fading
    @ViewState private var splashMounted = true      // still in the hierarchy
    @ViewState private var splashMinimumElapsed = false
    @ViewState private var splashReady = false
    /// Its fade is on its way (waiting for calm frames, then fading).
    @ViewState private var splashLeaving = false
    /// The library is built once it is known to be the screen to show
    /// (round 22): on iPhone Duo the first hinge report puts the handheld up
    /// instead, and building the 3D console under the logo first, for
    /// nothing, held up the first frame and that report (RealityKit's set-up
    /// on the main thread).
    @ViewState private var libraryAllowed = false
    /// Set once the cover has had long enough to reach its orientation; after
    /// this the splash no longer waits for it (a silent snap must not strand
    /// the logo on screen).
    @ViewState private var splashCoverCapped = false
    /// A white curtain over a change between the library and a game
    /// (round 20), and which change it belongs to (for its time-out).
    /// Held, not observed: only CurtainView redraws when it changes.
    @ViewState private var curtain = CurtainState()
    @ViewState private var curtainStamp = 0
    #if os(iOS)
    @ObservedObject private var displayRole = DisplayRoleMonitor.shared
    #endif
    /// The library is on the iPhone Duo's cover (the lid shut over it, or
    /// the Duo stood half open with the system showing the cover: the hinge
    /// is not "closed" then): what is started from it plays there
    /// (PlayView.playsOnCover).
    private var startsOnCover: Bool {
        #if os(iOS)
        return deviceLidClosed != nil && displayRole.libraryOnCover
        #else
        return false
        #endif
    }

    /// How long the logo stays up at least; how long we wait for the first
    /// hinge report before assuming a single-display device; and how long
    /// after that report the logo keeps covering the screen so the console
    /// can take its window lease and snap to the cover orientation underneath.
    /// 11-07: long enough for the ring to be drawn and the name to rise
    /// whole (SplashRing: 0.95 s).
    private static let splashMinimum: Duration = .milliseconds(1150)
    private static let splashTimeout: Duration = .milliseconds(2500)
    /// How long a Duo build waits for the hinge before it builds the library
    /// under the logo anyway (round 22). A Duo reports within a fraction of a
    /// second (simulator: 0.1 s after the process starts); a phone without a
    /// hinge never does and shows the library once `splashTimeout` has run
    /// out, so it has it built meanwhile, as before round 22.
    private static let hingeGrace: Duration = .milliseconds(400)
    private static let splashSettle: Duration = .milliseconds(600)
    /// Longest the splash waits, after the first hinge report, for the cover
    /// window to leave landscape (the 10-27 trace needed ~0.9 s on a slow
    /// launch; 10-26 needed 0.6 s).
    private static let splashCoverCap: Duration = .milliseconds(3000)
    private static let splashFade: Double = 0.35
    /// The logo let through a hair before it fades (SplashCurtain).
    static let splashHold: Double = 0.12

    /// Where this launch opens (round 23), decided once per process: the
    /// software of the card in the console, or the library.
    private static let launchPlan = LaunchPlan.atLaunch()

    init() {
        // A console that is set up and holds a card goes straight into its
        // software (resumed where it was left, when it was); otherwise the
        // library (round 23). Built under the logo, like the demo was.
        switch Self.launchPlan {
        case .game(let file, let resume):
            _coreGame = ViewState(initialValue: file)
            _resumeGame = ViewState(initialValue: resume)
            _showingDemo = ViewState(initialValue: true)
        case .demo:
            _showingDemo = ViewState(initialValue: true)
        case .library:
            break
        }
        #if DEBUG
        // Xcode can open the real play view when Simulator input is unavailable.
        // This changes only the initial navigation, not the demo or its inputs.
        if ProcessInfo.processInfo.arguments.contains("--foldarc-demo") || ProcessInfo.processInfo.arguments.contains("--foldarc-cover") {
            _showingDemo = ViewState(initialValue: true)
        }
        // `--foldarc-open-app=settings|setup`: a built-in program on the
        // console right away (screenshots, the input script driving it).
        if let app = Self.openAppArgument {
            _consoleApp = ViewState(initialValue: app)
            _showingDemo = ViewState(initialValue: true)
        }
        // `--foldarc-core-test`: boot the first file in CoreTest/ (or the one
        // named by `--foldarc-core-file=<name>`) on the real core right away
        // (simulator validation without touch input).
        if ProcessInfo.processInfo.arguments.contains("--foldarc-core-test"), AzaharSession.isCoreAvailable {
            let wanted = ProcessInfo.processInfo.arguments
                .first { $0.hasPrefix("--foldarc-core-file=") }
                .map { String($0.dropFirst("--foldarc-core-file=".count)) }
            let dir = Storage.root.appendingPathComponent("CoreTest", isDirectory: true)
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["3dsx", "cxi", "3ds", "cci", "elf", "app"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let first = files.first(where: { wanted == nil || $0.lastPathComponent == wanted }) {
                _coreGame = ViewState(initialValue: first)
                _showingDemo = ViewState(initialValue: true)
            }
        }
        #endif
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ZStack {
            // 11-15: the library stays under the cover's face while the lid is shut
            // over it, so what was open on its console (铅笔盒, 画框) is still open
            // when the lid opens (it had been made again, and opened the box again).
            if libraryAllowed && (!showingDemo || coverOnly) {
                // The library as a system menu (round 17; LibraryMenu.swift);
                // the console on its stage, the cards on the shelf (round 18).
                // The library brings the console up to full screen before a
                // game and the two cross-fade (`fade`).
                LibraryMenuView(library: library, selected: $selected,
                                startDemo: { curtainSwap { showingDemo = true } },
                                launch: { file, resume in curtainSwap { launch(file, resume: resume) } },
                                openApp: { app in curtainSwap(whitenAfter: Self.programWhitening) { consoleApp = app; selected = nil; showingDemo = true } },
                                importFiles: { importing = true },
                                curtain: curtain,
                                openOnArrival: homeItemOnArrival,
                                arrivalOpened: { homeItemOnArrival = nil })
                    .transition(.opacity)
                    // (under the cover's face: not touched, not read out)
                    .allowsHitTesting(!showingDemo)
                    .accessibilityHidden(showingDemo)
            }
            if showingDemo {
                PlayView(close: {
                             if coverOnly { libraryAskedOnCover = true }
                             coverInside = nil
                             cameraAlbumFirst = false
                             closeWithCurtain { showingDemo = false; coreGame = nil; consoleApp = nil; resumeGame = false; coverOnly = false }
                         },
                         deviceLidClosed: deviceLidClosed, game: coreGame,
                         coverOnly: coverOnly, coverInside: coverInside,
                         onReopen: {
                             // (the library under it, as it was: the box or the frame still open;
                             // the box heard opening, its latch and its pencils)
                             if coverInside == .tinBox { ConsoleSounds.shared.play(.lidOpen) }
                             coverInside = nil
                             coverOnly = false; showingDemo = false
                         },
                         playsOnCover: startsOnCover, resume: resumeGame,
                         app: consoleApp, cameraAlbum: cameraAlbumFirst, appGames: library.games, appRemove: { library.remove($0) },
                         appTestFiles: testFiles, appLaunchTestFile: { file in launchFromApp(file) },
                         appOpenHome: { request in openFromHome(request) })
                    .id(playID)
                    .transition(.opacity)
            }
            }
            // While the microphone listens, an arrow (11-07:
            // at the console's MIC, where one is drawn; MicHoleAnchorKey).
            .overlayPreferenceValue(MicHoleAnchorKey.self) { map in MicPointer(map: map) }
            .zIndex(8.5)
            CurtainView(state: curtain).zIndex(9)
            if splashMounted {
                // Above everything until the console is on the right display,
                // so a closed Duo shows logo -> casing and never the library.
                // It stays mounted while fading (a view in a removal
                // transition is not re-laid out, and the cover snap can
                // rotate the window during the fade). Faded by Core
                // Animation on iOS (SplashCurtain).
                #if os(iOS)
                SplashCurtain(shown: showingSplash, fade: LibraryView.splashFade)
                    .ignoresSafeArea()
                    .allowsHitTesting(showingSplash)
                    .zIndex(10)
                #else
                SplashView()
                    .opacity(showingSplash ? 1 : 0)
                    .allowsHitTesting(showingSplash)
                    .zIndex(10)
                #endif
            }
        }
        .foregroundStyle(.white)
        .tint(Palette.mint)
        #if os(iOS)
        // The menu draws its own clock and battery (round 17).
        .statusBarHidden(true)
        #endif
        // The banner follows the library: a newly imported title is shown,
        // a removed one is not.
        .onChange(of: library.games) { old, games in
            if let added = games.first(where: { game in !old.contains(game) }) { selected = added }
            else if let current = selected, !games.contains(where: { $0.id == current.id }) { selected = nil }
        }
        .task {
            try? await Task.sleep(for: LibraryView.splashMinimum)
            splashMinimumElapsed = true
            dismissSplashIfReady()
        }
        .task {
            // The game controller framework loads the first time anything
            // asks for controllers (100-160 ms on the main thread): here,
            // under the logo, not as the first game comes up (round 21).
            try? await Task.sleep(for: .milliseconds(300))
            _ = GameControllerInput.shared
            // The volume keys and headphones (round 23): after the logo's
            // first frames, off the launch path (activating the audio
            // session can take a moment).
            try? await Task.sleep(for: .milliseconds(400))
            SystemAudio.shared.start()
        }
        .task {
            // Only a build with the Duo SDK on iOS 27.1 or later can hear the
            // hinge; anywhere else no report will come, so there is nothing
            // to wait for beyond the minimum (15th round: a phone on iOS 27.0
            // kept the logo up for 4.2 s).
            #if os(iOS) && FOLDARC_DUO_SDK
            if #available(iOS 27.1, *) {
                try? await Task.sleep(for: LibraryView.hingeGrace)
                // No report yet: most likely a phone without a hinge, which
                // will show the library. It is built under the logo while the
                // rest of the wait runs out; built only after the wait, the
                // logo would stay up for the length of the build as well.
                if deviceLidClosed == nil {
                    libraryAllowed = true
                    OrientationTrace.shared.event("splash: no hinge report after 0.4 s, library built under the logo")
                }
                try? await Task.sleep(for: LibraryView.splashTimeout - LibraryView.hingeGrace)
            }
            #endif
            // No hinge report by now: not a Duo, or the hinge is silent.
            // Either way the library is the right first screen.
            libraryAllowed = true
            splashReady = true
            dismissSplashIfReady()
        }
        .modifier(DeviceHingeObserver { closed in
            #if DEBUG
            // `--foldarc-no-hinge`: act as a phone without a hinge (the
            // reports are ignored), to try that start on the Duo simulator.
            if Self.ignoresHinge { return }
            #endif
            let firstHardwareReport = deviceLidClosed == nil && closed != nil
            deviceLidClosed = closed
            // On Duo the first foreground display is already the handheld
            // when this launch goes into software (round 23: the card in a
            // set-up console; before, the demo, always). Subsequent hinge
            // angle updates must not reopen a dismissed game.
            if firstHardwareReport && !Self.staysInLibrary {
                showingDemo = true
                #if os(iOS)
                OrientationTrace.shared.event("splash: first hinge report, console placed; lid=\(closed.map { String($0) } ?? "nil")")
                #endif
                Task { @MainActor in
                    try? await Task.sleep(for: LibraryView.splashSettle)
                    splashReady = true
                    dismissSplashIfReady()
                }
                Task { @MainActor in
                    try? await Task.sleep(for: LibraryView.splashCoverCap)
                    splashCoverCapped = true
                    dismissSplashIfReady()
                }
            }
            // `--foldarc-library` (DEBUG): the report has come, so the library
            // is the first screen; no need to wait out the 2.5 s.
            if firstHardwareReport && Self.staysInLibrary {
                libraryAllowed = true
                Task { @MainActor in
                    try? await Task.sleep(for: LibraryView.splashSettle)
                    splashReady = true
                    dismissSplashIfReady()
                }
            }
        })
        // Back from a game, or anywhere the library is to be shown after the
        // start: it is built then.
        .onChange(of: showingDemo) { _, demo in if !demo { libraryAllowed = true } }
        .onReceive(NotificationCenter.default.publisher(for: .foldArcScreenReady)) { note in
            // Once the new view has stopped holding up the frames: a curtain
            // lifted while it still did went up in three jerks (10-30). A
            // game asks for a longer calm (10 frames): the demo's first
            // second is uneven.
            guard curtain.up else { return }
            FrameCalm.wait(frames: (note.object as? String) == "play" ? 10 : 6) { liftCurtain() }
        }
        #if os(iOS)
        .onChange(of: displayRole.displaySettled) { _, _ in dismissSplashIfReady() }
        .onChange(of: displayRole.isOuter) { _, _ in dismissSplashIfReady() }
        // Duo: the lid closed over the library (or the Duo stood half open
        // and the system showing the cover). The cover goes with what is
        // inside (CoverFace): the library goes on on the cover, as it is;
        // 铅笔盒 open on its console, the box's lid; 画框 open there, the
        // frame's scenery; the camera (its album too), the camera's own
        // deck. Opening the lid brings the library back inside (the box or
        // the frame open again, if it was). A game started from the library
        // on the cover plays there (PlayView.playsOnCover). The console's
        // shell is the cover of the console full screen, not of the library
        // (11-15 to 11-16 it was the library's too).
        .onChange(of: displayRole.libraryOnCover) { _, onCover in
            guard deviceLidClosed != nil else { return }
            guard onCover else { libraryAskedOnCover = false; return }
            guard !showingDemo else { return }
            // 11-06: the camera running on the console on the stage goes on as
            // the cover's control deck (a camera of play's own, the stage's
            // put away first; the lid opened, it is the camera on the console
            // full size, and HOME comes back to the library).
            // (11-15: its album, and 相册, go on as the deck's album: the
            // album closed, the library went on on the cover with the camera
            // in it, its two screens squeezed onto the cover.)
            if let stage = CameraAppModel.stageCamera, stage.isOpen {
                let album = stage.albumOnly, inAlbum = stage.phase == .album
                OrientationTrace.shared.event("library: lid closed with the \(album ? "album" : "camera") on, the \(inAlbum ? "album" : "camera") on the cover")
                NSLog("[camera] lid shut over the library's camera: the cover's deck%@", inAlbum ? " (its album)" : "")
                stage.close()
                selected = nil
                consoleApp = album ? .album : .camera
                cameraAlbumFirst = inAlbum && !album
                coverOnly = false; showingDemo = true
                return
            }
            if libraryAskedOnCover {
                OrientationTrace.shared.event("library: on the cover, asked for there")
                return
            }
            let stage = StageProgram.shown
            let inside: CoverFace.Inside = stage == ConsoleApp.tinBox ? .pencilBox : stage == ConsoleApp.pictureFrame ? .pictureFrame : .console
            let face = CoverFace.shown(fullScreen: false, inside: inside)
            guard face != .library else {
                OrientationTrace.shared.event("library: lid closed over the library, the cover: the library")
                NSLog("[display] the lid shut over the library: the library on the cover")
                return
            }
            coverInside = stage
            // (the box shut with the phone: its lid heard coming down, and seen on the cover)
            if face == .pencilLid { ConsoleSounds.shared.play(.lidShut) }
            let name = face == .pencilLid ? "the pencil box's lid" : "the picture frame"
            OrientationTrace.shared.event("library: lid closed over the library, the cover: \(name)")
            NSLog("[display] the lid shut over the library: the cover (%@)", name)
            coverOnly = true
            showingDemo = true
        }
        #endif
        #if DEBUG
        // `--foldarc-import=<path>`: run the real import path at launch
        // (simulator validation without the document picker's touch input).
        .task {
            for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--foldarc-import=") {
                await library.importROM(URL(fileURLWithPath: String(argument.dropFirst("--foldarc-import=".count))))
            }
        }
        #endif
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await library.importROM(url) } }
            case .failure(let error): library.message = error.localizedDescription
            }
        }
        // "Open in FoldArc" from Files / AirDrop / Mail: the system hands the
        // file over (document types in Info.plist); it is copied like any import
        // and the handed-over original is left where the system put it.
        #if os(iOS)
        .onReceive(ExternalDocumentInbox.shared.$pending) { urls in
            guard !urls.isEmpty else { return }
            // Take the queue on the next turn, not inside its own publisher.
            Task { @MainActor in
                for url in ExternalDocumentInbox.shared.take() { await library.importROM(url) }
            }
        }
        // 11-05: a Home Screen quick action tapped while FoldArc ran:
        // from the library that software starts; over a software it waits no
        // longer (it would close what is being played).
        .onReceive(HomeScreenShortcuts.shared.$pending) { request in
            guard let request else { return }
            Task { @MainActor in
                HomeScreenShortcuts.shared.pending = nil
                guard !showingDemo else { NSLog("[shortcuts] %@: a software is up, not started", request.id); return }
                guard ConsoleSettings.shared.setupDone else { NSLog("[shortcuts] %@: the console is not set up yet", request.id); return }
                switch HomeScreenShortcuts.plan(for: request, games: library.games, root: Storage.root) {
                case .demo?:
                    NSLog("[shortcuts] starting the demo")
                    curtainSwap { showingDemo = true }
                case .game(let file, let resume)? where AzaharSession.isCoreAvailable:
                    NSLog("[shortcuts] starting %@%@", file.lastPathComponent, resume ? " (resume)" : "")
                    curtainSwap { launch(file, resume: resume) }
                default: library.message = String(localized: "这个游戏已经不在游戏库里了")
                }
            }
        }
        #else
        .onOpenURL { url in
            guard url.isFileURL else { return }
            Task { await library.importROM(url) }
        }
        #endif
        // Library messages wait while a sheet or a game is up: SwiftUI would
        // present the alert from the sheet (or the HOME menu), and an alert
        // presented from a sheet lets the inner display turn with the device
        // (see PlayView.closeConfirmation). "Open in FoldArc" can finish an
        // import at any time.
        // "知道了" clears the message. SwiftUI's write-back while it dismisses
        // the alert (inside a view update) must not: it also comes when the
        // alert is only held back, e.g. an import finished at launch just
        // before the console covered the library. Clearing there published
        // from a view update and dropped the message unseen (10-28 traces:
        // LibraryModel.message.setter from this closure, twice per import at
        // launch); now it waits and shows once the library is back.
        .alert("Zero EMU", isPresented: Binding(get: { library.message != nil && !showingDemo && !importing },
                                               set: { _ in })) {
            Button("知道了") { library.message = nil }
        } message: { Text(library.message ?? "") }
    }

    /// `--foldarc-library` (DEBUG): a Duo stays on the library after the
    /// splash instead of placing the console (round 18: stage screenshots
    /// without a UI test).
    #if DEBUG
    private static let ignoresHinge = ProcessInfo.processInfo.arguments.contains("--foldarc-no-hinge")
    #endif
    private static var staysInLibrary: Bool {
        // Round 23: the library is the first screen unless this launch goes
        // into software (LaunchPlan); `--foldarc-demo` / `--foldarc-cover`
        // (DEBUG) still put the console up.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-library") { return true }
        if ProcessInfo.processInfo.arguments.contains("--foldarc-demo") || ProcessInfo.processInfo.arguments.contains("--foldarc-cover") { return false }
        if ProcessInfo.processInfo.arguments.contains("--foldarc-core-test") && AzaharSession.isCoreAvailable { return false }
        if openAppArgument != nil { return false }
        #endif
        return launchPlan == .library
    }
    #if DEBUG
    private static var openAppArgument: ConsoleApp? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--foldarc-open-app=") }
            .flatMap { ConsoleApp(rawValue: String($0.dropFirst("--foldarc-open-app=".count))) }
    }
    #endif

    /// Library ↔ console: a cross-fade (round 18).
    private func fade(_ change: () -> Void) {
        FrameMeter.shared.begin(showingDemo ? "close.swap" : "launch.swap")
        FrameMeter.shared.end(after: 1.2)
        withAnimation(.easeInOut(duration: 0.45), change)
    }

    /// Library → game (round 20). The library has brought the console up
    /// and turned the screens white; the game's view comes in under a white
    /// curtain, without a cross-fade (both views drawn at once held the frame
    /// rate near 15 a second for the length of it, 10-29 measurement), and
    /// the curtain lifts once the game's view is in place.
    private func curtainSwap(whitenAfter: Double = 0.9, _ change: () -> Void) {
        FrameMeter.shared.begin("launch.swap")
        // Round 24: under a still picture of the screen as it is (the
        // console filling it), not white; the game's screens dissolve out of
        // it (white only if no picture can be taken, or after 0.9 s).
        // Round 26: a program on the console (主菜单, 相机, 设置) takes about
        // that long to come up (相机 909 ms in round 25; the console's menu
        // longer, and its picture went white for 0.3 s): those hold the
        // picture up to 1.7 s instead.
        let pictured = curtain.coverWithPicture(whitenAfter: whitenAfter, drift: 1.045)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if !pictured { curtain.set(true, fade: 0) }
            change()
        }
        holdCurtain()
    }
    /// Game → library: a still picture of the game holds the screen while
    /// the library comes in under it (round 24; before, the game faded to
    /// white first), then dissolves as the console comes down onto its
    /// stage from where the game left it.
    private func closeWithCurtain(_ change: @escaping () -> Void) {
        // Round 32: after POWER the software's last frames ride down on the
        // console (ConsoleStage.handoff), so the picture is given longer
        // before it would whiten: the change should be seen whole.
        if curtain.coverWithPicture(whitenAfter: ConsoleStage.handoff == nil ? 0.9 : 2.2, drift: 0.965) {
            FrameMeter.shared.begin("close.swap")
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { change() }
            holdCurtain()
            return
        }
        FrameMeter.shared.begin("close.fade")
        curtain.set(true, fade: 0.2)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            FrameMeter.shared.begin("close.swap")
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { change() }
            holdCurtain()
        }
    }
    /// The curtain lifts when the new view says it is in place, at the
    /// latest 6 s after the change (round 21: a game says so only once its
    /// first frames are on the screens, PlayView gives up waiting after 4 s;
    /// the library once its console is built).
    private func holdCurtain() {
        curtainStamp += 1
        let stamp = curtainStamp
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(6000))
            if curtainStamp == stamp, curtain.up { liftCurtain() }
        }
    }
    private func liftCurtain() {
        guard curtain.up else { return }
        curtainStamp += 1
        FrameMeter.shared.begin("curtain.lift")
        curtain.set(false, fade: 0.45)
        FrameMeter.shared.end(after: 0.5)
    }

    private func launch(_ file: URL, resume: Bool) {
        coreGame = file
        resumeGame = resume
        consoleApp = nil
        selected = nil
        showingDemo = true
    }
    /// What the console's menu, full size on the handheld, opens (round 26):
    /// the card in the slot (the demo's or a game, fresh or where it was
    /// left), the first-time setup. Round 31: everything else (相机, 设置,
    /// 游戏记录, 主题, 说明书, 游玩模式) opens in place on the handheld, and
    /// 导入 is the library's alone (not on the handheld's menu); the
    /// library's way below is only a fallback.
    private func openFromHome(_ request: ConsoleHomeRequest) {
        switch request {
        case .shortcut:
            // The small icons are the play view's own (software suspended).
            break
        case .setup:
            curtainSwap(whitenAfter: Self.programWhitening) { consoleApp = .setup }
        case .item(let item, let action):
            switch item {
            case .card:
                let id = UserDefaults.standard.string(forKey: "FoldArc.insertedCard") ?? ""
                if id == LaunchPlan.demoCardID {
                    curtainSwap { consoleApp = nil; coreGame = nil; resumeGame = false }
                    return
                }
                guard AzaharSession.isCoreAvailable, let game = library.games.first(where: { $0.id == id }) else { return }
                let file = ConsoleHomeProgram.file(for: game)
                if action == .restart { SaveStates.removeResume(for: file) }
                curtainSwap { launch(file, resume: action == .resume) }
            case .camera, .album, .settings, .importFiles, .activity, .theme, .manual, .modes, .pictureFrame, .tinBox:
                // Round 31: the play view opens these in place and does not
                // send them here; were one to come, the library opens it on
                // its console once it is back.
                homeItemOnArrival = item
                closeWithCurtain { showingDemo = false; coreGame = nil; consoleApp = nil; resumeGame = false; coverOnly = false }
            }
        }
    }
    /// 数据管理's core test files (DEBUG aid): from the settings straight
    /// into the file, under the white curtain.
    private func launchFromApp(_ file: URL) {
        curtainSwap { consoleApp = nil; resumeGame = false; coreGame = file }
    }
    /// How long the picture over a change into a program on the console
    /// (主菜单, 相机, 设置, the setup) is held before it whitens (round 26;
    /// see curtainSwap).
    static let programWhitening = 1.7
    /// What the play view is showing: a new one for each (its own session).
    private var playID: String {
        if let consoleApp { return "app." + consoleApp.rawValue }
        return coreGame?.path ?? "demo"
    }

    /// On the cover display the window may still be in the landscape
    /// orientation UIKit created it with; the casing underneath only reads
    /// right once the snap to portrait has happened. Keep the logo up until
    /// then (10-27 recording: the casing showed sideways for 0.9 s when the
    /// splash timed out before the snap on a slow launch).
    private var splashWaitingForCover: Bool {
        #if os(iOS)
        guard !splashCoverCapped, displayRole.isOuter != nil else { return false }
        return !displayRole.displaySettled
        #else
        return false
        #endif
    }

    private func dismissSplashIfReady() {
        guard showingSplash, !splashLeaving, splashMinimumElapsed, splashReady, !splashWaitingForCover else { return }
        splashLeaving = true
        // Once the frames come on time (at most 0.5 s): what is under the
        // logo still drawing its first frames would show through the fade
        // in jerks (round 21).
        FrameCalm.wait(frames: 6, timeout: 0.5) { fadeSplash() }
    }
    private func fadeSplash() {
        // The cover may have begun to turn meanwhile: wait for it again.
        guard !splashWaitingForCover else { splashLeaving = false; return }
        libraryAllowed = true
        #if os(iOS)
        OrientationTrace.shared.event("splash: fade out")
        // Core Animation fades it (SplashCurtain).
        showingSplash = false
        #else
        withAnimation(.easeOut(duration: LibraryView.splashFade)) { showingSplash = false }
        #endif
        #if os(iOS)
        if !showingDemo { CoverOrientationPolicy.shared.endLaunchHold() }
        // The demo is up and the library is not built yet (round 22): a
        // console is built once out of sight while the fade runs, so the
        // first trip to the library finds RealityKit started and the faces
        // printed.
        if showingDemo && coreGame == nil {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                ConsoleStage.warmUp(finish: ShellFinish(rawValue: UserDefaults.standard.string(forKey: "foldarc.finish") ?? "") ?? .aqua)
            }
        }
        #endif
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((LibraryView.splashHold + LibraryView.splashFade) * 1000) + 150))
            splashMounted = false
            #if os(iOS)
            OrientationTrace.shared.event("splash: removed")
            #endif
        }
    }

    /// Developer aid: homebrew test files dropped into Application Support/FoldArc/CoreTest/
    /// (via Finder/simctl) can be launched on the core without importing.
    private var testFiles: [URL] {
        let dir = Storage.root.appendingPathComponent("CoreTest", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { ["3dsx", "cxi", "3ds", "cci", "elf", "app"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// A game's HOME Menu icon (from its SMDH, saved at import), or the generic
/// controller glyph when the title has none.
struct GameIcon: View {
    let record: GameRecord
    var size: CGFloat = 40
    var body: some View {
        if let image = GameIconCache.image(named: record.iconFileName) {
            let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            Image(decorative: image, scale: 1)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gamecontroller.fill").foregroundStyle(Palette.orange)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

@MainActor enum GameIconCache {
    private static var images: [String: CGImage] = [:]
    static func image(named name: String?) -> CGImage? {
        guard let name else { return nil }
        if let cached = images[name] { return cached }
        let url = Storage.root.appendingPathComponent("Icons", isDirectory: true).appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[name] = image
        return image
    }
}
