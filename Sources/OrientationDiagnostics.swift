import SwiftUI
#if os(iOS)
import UIKit
import QuartzCore
import os

// MARK: - Trace log

/// Timestamped trace of the Duo display migration. Debug builds write it to
/// FOLDARC_TRACE_DIRECTORY (when set, e.g. from the scheme) and to the app's
/// Documents directory, and keep the last lines for an on-screen overlay.
/// Everything here only observes; it never changes orientation or layout.
@MainActor final class OrientationTrace: ObservableObject {
    static let shared = OrientationTrace()
    @Published private(set) var recent: [String] = []
    private(set) var locations: [URL] = []
    private var handles: [FileHandle] = []
    private let started = CACurrentMediaTime()
    private var lastLine = ""
    private var repeats = 0
    let stamp: String

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        stamp = formatter.string(from: Date()) + "-\(ProcessInfo.processInfo.processIdentifier)"
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["FOLDARC_TRACE_DIRECTORY"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        candidates.append(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldArcTrace", isDirectory: true))
        #if DEBUG
        for base in candidates {
            let folder = base.appendingPathComponent("trace-\(stamp)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent("orientation.log")
                guard FileManager.default.createFile(atPath: file.path, contents: nil) else { continue }
                handles.append(try FileHandle(forWritingTo: file))
                locations.append(folder)
            } catch {
                print("[FoldArc trace] cannot use \(folder.path): \(error.localizedDescription)")
            }
        }
        #endif
        let wall = DateFormatter()
        wall.dateFormat = "HH:mm:ss.SSS"
        event("trace start pid=\(ProcessInfo.processInfo.processIdentifier) wall=\(wall.string(from: Date())) dirs=\(locations.map(\.path))")
        #if DEBUG
        // 11-06 (no crash report on the phone): how a run
        // ends, in the trace — exit(), a signal, an Objective-C exception;
        // none of them means the system ended it (SIGKILL cannot be heard).
        if let handle = handles.first { ExitWatch.install(fd: handle.fileDescriptor) }
        #endif
        for name in [UIScene.willConnectNotification, UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.didDisconnectNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let scene = note.object as? UIWindowScene
                Task { @MainActor in
                    // Which scene it is (the app's window, the cover's
                    // camera accessory, a TV's) — the role says.
                    let role = scene?.session.role.rawValue ?? "-"
                    let io = scene.map { OrientationFormat.orientation($0.effectiveGeometry.interfaceOrientation) } ?? "-"
                    let screen = scene.map { OrientationFormat.screen($0.screen) } ?? "-"
                    OrientationTrace.shared.event("scene \(name.rawValue) role=\(role) io=\(io) screen=\(screen)")
                }
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in OrientationTrace.shared.event("memory warning \(ExitWatch.memory())") }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { OrientationTrace.shared.event("the system ends FoldArc (willTerminate)") }
        }
    }

    var milliseconds: Double { (CACurrentMediaTime() - started) * 1000 }

    func event(_ message: String) {
        if message == lastLine { repeats += 1; return }
        if repeats > 0 { emit("  (previous line repeated \(repeats)x)"); repeats = 0 }
        lastLine = message
        emit(message)
    }
    private func emit(_ message: String) {
        let line = String(format: "%9.1f  ", milliseconds) + message
        #if DEBUG
        print("[FoldArc trace] " + line)
        #endif
        if let data = (line + "\n").data(using: .utf8) {
            for handle in handles { try? handle.write(contentsOf: data) }
        }
        recent.append(line)
        if recent.count > 40 { recent.removeFirst(recent.count - 40) }
    }
    var frameDirectory: URL? { locations.first }
}

/// 11-06 (987: no crash report, no jetsam report, the
/// traces of six runs just stop): what ends a run, written into its trace
/// as it happens — exit() (with the calls that led to it), a signal, an
/// Objective-C exception. A run whose trace ends without one of these was
/// ended from outside (SIGKILL: the system, or swiped away). The memory in
/// use and left before the system's limit goes into the heartbeats.
enum ExitWatch {
    nonisolated(unsafe) private static var fd: Int32 = -1
    /// "… signal N (NAME)\n" per signal number, made before any can come (a
    /// signal handler may only write what is already there).
    nonisolated(unsafe) private static var lines = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 33)
    nonisolated(unsafe) private static var installed = false
    static let signals: [(Int32, String)] = [(SIGABRT, "SIGABRT"), (SIGSEGV, "SIGSEGV"), (SIGBUS, "SIGBUS"), (SIGILL, "SIGILL"),
                                             (SIGTRAP, "SIGTRAP"), (SIGFPE, "SIGFPE"), (SIGSYS, "SIGSYS"), (SIGPIPE, "SIGPIPE"),
                                             (SIGTERM, "SIGTERM"), (SIGHUP, "SIGHUP"), (SIGINT, "SIGINT"), (SIGQUIT, "SIGQUIT"),
                                             (SIGXCPU, "SIGXCPU"), (SIGXFSZ, "SIGXFSZ")]
    static func install(fd: Int32) {
        guard !installed, fd >= 0 else { return }
        installed = true
        Self.fd = fd
        for i in 0..<33 { lines[i] = nil }
        for (number, name) in signals where number > 0 && number < 33 {
            lines[Int(number)] = strdup("  -------  run ends: signal \(number) (\(name))\n")
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { number in
                if ExitWatch.fd >= 0, number > 0, number < 33, let line = ExitWatch.lines[Int(number)] {
                    _ = Darwin.write(ExitWatch.fd, line, strlen(line))
                }
                // The default action now (the crash report as before).
                signal(number, SIG_DFL)
                raise(number)
            }
            action.sa_flags = SA_RESETHAND
            action.sa_mask = sigset_t()
            sigaction(number, &action, nil)
        }
        atexit {
            ExitWatch.write("  -------  run ends: exit() called; the calls:\n" + Thread.callStackSymbols.prefix(24).map { "    " + $0 }.joined(separator: "\n") + "\n")
        }
        NSSetUncaughtExceptionHandler { exception in
            ExitWatch.write("  -------  run ends: exception \(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.prefix(24).map { "    " + $0 }.joined(separator: "\n") + "\n")
        }
    }
    static func write(_ text: String) {
        guard fd >= 0 else { return }
        text.utf8CString.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress { _ = Darwin.write(fd, base, max(0, buffer.count - 1)) }
        }
    }
    /// The memory FoldArc uses (its footprint, what the system's limit counts)
    /// and what is left before that limit.
    static func memory() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let used = result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
        let left = Double(os_proc_available_memory()) / 1_048_576
        return String(format: "mem=%.0fMB left=%.0fMB", used, left)
    }
}

enum OrientationFormat {
    static func orientation(_ value: UIInterfaceOrientation) -> String {
        switch value {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        default: return "unknown"
        }
    }
    static func mask(_ value: UIInterfaceOrientationMask) -> String {
        if value == .all { return "all" }
        if value == .portrait { return "portrait" }
        if value == .landscape { return "landscape" }
        if value == .landscapeLeft { return "landscapeLeft" }
        if value == .landscapeRight { return "landscapeRight" }
        if value == .portraitUpsideDown { return "portraitUpsideDown" }
        return "raw(\(value.rawValue))"
    }
    static func screen(_ screen: UIScreen?) -> String {
        guard let screen else { return "nil" }
        let id = String(describing: ObjectIdentifier(screen)).replacingOccurrences(of: "ObjectIdentifier(", with: "").replacingOccurrences(of: ")", with: "")
        return "\(id)/\(size(screen.bounds.size))@\(size(screen.nativeBounds.size))"
    }
    static func size(_ s: CGSize) -> String { String(format: "%.0fx%.0f", s.width, s.height) }
    static func rect(_ r: CGRect) -> String { String(format: "(%.0f,%.0f %.0fx%.0f)", r.minX, r.minY, r.width, r.height) }
    static func transform(_ t: CGAffineTransform) -> String {
        if t.isIdentity { return "id" }
        let degrees = atan2(t.b, t.a) * 180 / .pi
        return String(format: "rot%.1f[%.2f %.2f %.2f %.2f %.0f %.0f]", degrees, t.a, t.b, t.c, t.d, t.tx, t.ty)
    }
    static func insets(_ i: UIEdgeInsets) -> String { String(format: "%.0f/%.0f/%.0f/%.0f", i.top, i.left, i.bottom, i.right) }
}

// MARK: - Per-frame sampler

/// Samples window/scene/screen state on every display refresh and logs a
/// line whenever anything changes. While something recently changed it also
/// saves a small render of the window's presentation tree, so in-flight
/// Core Animation transforms (a UIKit rotation animation) are visible.
@MainActor final class OrientationSampler: NSObject {
    private weak var window: UIWindow?
    private var link: CADisplayLink?
    private var lastSignature = ""
    private var lastHeartbeat = 0.0
    private var captureUntil = 0.0
    private var frameIndex = 0
    private let encodeQueue = DispatchQueue(label: "foldarc.trace.frames", qos: .utility)
    var hingeDescription = "n/a"
    var lidDescription = "nil"
    var captureFrames = true

    func attach(_ window: UIWindow) {
        self.window = window
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        markInteresting(3)
    }
    func detach() {
        link?.invalidate(); link = nil; window = nil
    }
    func markInteresting(_ seconds: Double = 2.5) {
        captureUntil = max(captureUntil, CACurrentMediaTime() + seconds)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let window else { return }
        let scene = window.windowScene
        var parts: [String] = []
        parts.append("screen=\(OrientationFormat.screen(scene?.screen))")
        if let scene { parts.append("io=\(OrientationFormat.orientation(scene.effectiveGeometry.interfaceOrientation)) theta=\(Int(DisplayRoleMonitor.interfaceRotation(of: scene.screen)))") }
        parts.append("wb=\(OrientationFormat.size(window.bounds.size)) wf=\(OrientationFormat.rect(window.frame))")
        parts.append("wt=\(OrientationFormat.transform(window.transform))")
        if let presentation = window.layer.presentation() {
            parts.append("wpt=\(OrientationFormat.transform(presentation.affineTransform())) wpb=\(OrientationFormat.size(presentation.bounds.size))")
        }
        if let root = window.rootViewController?.view {
            parts.append("rb=\(OrientationFormat.size(root.bounds.size)) rt=\(OrientationFormat.transform(root.transform))")
            if let presentation = root.layer.presentation() {
                parts.append("rpt=\(OrientationFormat.transform(presentation.affineTransform())) rpb=\(OrientationFormat.size(presentation.bounds.size))")
            }
            parts.append("safe=\(OrientationFormat.insets(root.safeAreaInsets))")
        }
        parts.append("hinge=\(hingeDescription) lid=\(lidDescription)")
        let signature = parts.joined(separator: " ")
        let now = CACurrentMediaTime()
        if signature != lastSignature {
            lastSignature = signature
            OrientationTrace.shared.event("frame#\(frameIndex) " + signature)
            markInteresting()
        } else if now - lastHeartbeat > 5 {
            lastHeartbeat = now
            OrientationTrace.shared.event("heartbeat frame#\(frameIndex) " + signature + " " + ExitWatch.memory())
        }
        if captureFrames, now < captureUntil, let directory = OrientationTrace.shared.frameDirectory {
            capture(window, index: frameIndex, directory: directory)
        }
        frameIndex += 1
    }

    private func capture(_ window: UIWindow, index: Int, directory: URL) {
        let scale = 0.18
        let size = CGSize(width: max(1, (window.bounds.width * scale).rounded()), height: max(1, (window.bounds.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            // The presentation tree shows what Core Animation is drawing now.
            if let presentation = window.layer.presentation() { presentation.render(in: context.cgContext) }
            else { window.layer.render(in: context.cgContext) }
        }
        let url = directory.appendingPathComponent(String(format: "frame-%05d-%08.1fms.png", index, OrientationTrace.shared.milliseconds))
        encodeQueue.async { if let data = image.pngData() { try? data.write(to: url) } }
    }
}

// MARK: - Display migration host (fix)

/// Which built-in display currently shows the game window. Published from
/// UIKit callbacks so SwiftUI can choose the cover or the handheld by the
/// screen the window is actually on, instead of by hinge status, which the
/// trace showed arriving ~100-400 ms before the display migration (and
/// once more, stale, right after it).
@MainActor final class DisplayRoleMonitor: ObservableObject {
    static let shared = DisplayRoleMonitor()
    @Published private(set) var isOuter: Bool?
    /// Rotation (degrees, clockwise in a y-down space) of the window's
    /// interface coordinate space relative to the screen's fixed, portrait-up
    /// space: 0 = portrait, ±90 = landscape, 180 = upside down. The casing
    /// artwork subtracts it so the print stays fixed to the hardware whatever
    /// interface orientation UIKit gives the outer display at any moment.
    /// nil until the first UIKit hook has run; the cover then falls back to
    /// its viewport-based guess instead of assuming an upright portrait.
    @Published private(set) var interfaceRotation: Double?
    /// True once the window has reached the orientation its display is held
    /// at (CoverOrientationPolicy: cover portrait, inner the handheld
    /// reference) and stayed there briefly. A migrated window can arrive in
    /// another orientation and is turned by the policy ~0.45 s later; the
    /// casing and the handheld stay hidden until this is true, so no turn is
    /// ever seen. If the system never complies, the content shows after a cap
    /// (it is drawn in the panel's fixed frame, so it is still right).
    @Published private(set) var displaySettled = false
    /// Without a game (the library) on Duo hardware: true while the window
    /// is on the cover display. The library then shows the closed casing, as
    /// play does (LibraryView, PlayView coverOnly).
    @Published private(set) var libraryOnCover = false
    /// 11-07: the Duo held across,
    /// like a book (crease up and down, the USB-C edge down or up), as
    /// FoldArc reads the hold (CoverOrientationPolicy.heldInterface). Play
    /// turns 掌机模式 and 桌面模式 into 手柄模式 then, and the game's window
    /// on the inner display turns with the hold.
    @Published private(set) var heldAcross = false
    func publish(heldAcross value: Bool) {
        guard heldAcross != value else { return }
        heldAcross = value
        OrientationTrace.shared.event("held \(value ? "across (a book)" : "as the handheld")")
    }
    /// True from the moment the window moves to the other display (a lid
    /// close or open) until that display has settled. The play view keeps a
    /// black backdrop meanwhile: once in a while SpringBoard turns the inner
    /// display away and back again (~0.35 s) after the window has arrived
    /// there, and the backdrop was seen turning with it (10-28 recordings,
    /// Docs/LID-OPEN-WOBBLE-20261028.md). Black on a display that is just
    /// coming on shows nothing of it. Not set when play starts on a display
    /// (nil -> inner), so the library does not blink black into the game.
    @Published private(set) var switchingDisplay = false
    func publishLibrary(onCover value: Bool) {
        guard libraryOnCover != value else { return }
        libraryOnCover = value
        OrientationTrace.shared.event("library display -> \(value ? "cover" : "inner")")
    }
    /// The scene was created on the cover display: a launch with the lid
    /// closed on a Duo whose displays are already known. Set once by the scene
    /// delegate before the first frame; the splash then shows only its
    /// background (SplashView.markVisible).
    var launchedOnCover = false
    var coverSettled: Bool { displaySettled && isOuter == true }
    var innerSettled: Bool { displaySettled && isOuter == false }
    static let coverTargetRotation: Double = 0
    static let settleDelay: Duration = .milliseconds(150)
    static let settleCap: TimeInterval = 1.5
    private var settleTask: Task<Void, Never>?
    private var arrivedAt = Date()
    func publish(_ value: Bool?) {
        guard isOuter != value else { return }
        let moved = isOuter != nil && value != nil
        isOuter = value
        arrivedAt = Date()
        if value == nil { interfaceRotation = nil }
        if switchingDisplay != moved { switchingDisplay = moved }
        OrientationTrace.shared.event("display role -> \(value.map { $0 ? "outer" : "inner" } ?? "unknown")")
        restartSettle()
    }
    func publish(interfaceRotation value: Double) {
        guard interfaceRotation != value else { return }
        interfaceRotation = value
        OrientationTrace.shared.event("interface rotation -> \(Int(value))")
        restartSettle()
    }
    private func restartSettle() {
        settleTask?.cancel()
        if displaySettled { displaySettled = false }
        guard let outer = isOuter else { return }
        let target = outer ? Self.coverTargetRotation : Self.handheldReferenceRotation
        // 11-07: a game window turning with the hold (手柄模式 held across)
        // is where it should be whichever way it has turned.
        let atTarget = interfaceRotation == target || (!outer && CoverOrientationPolicy.shared.playFollowsHold)
        let capLeft = Self.settleCap - Date().timeIntervalSince(arrivedAt)
        settleTask = Task { @MainActor [weak self] in
            if atTarget || capLeft <= 0 {
                try? await Task.sleep(for: DisplayRoleMonitor.settleDelay)
            } else {
                try? await Task.sleep(for: .milliseconds(Int(capLeft * 1000)))
            }
            guard let self, !Task.isCancelled, self.isOuter == outer else { return }
            OrientationTrace.shared.event("display settled rotation=\(Int(self.interfaceRotation ?? -1)) \(outer ? "cover" : "inner") \(atTarget ? "at target" : "by cap")")
            self.displaySettled = true
            if self.switchingDisplay { self.switchingDisplay = false }
        }
    }
    /// Interface rotation of the handheld reference pose on the inner display:
    /// lower screen on the side-button half, which UIKit reports as
    /// portraitUpsideDown (180) when the device is held that way (Device Hub
    /// "Open" pose; 10-26 and 10-27 traces).
    static let handheldReferenceRotation: Double = 180
    /// Rotation (degrees, for `rotationEffect`) that draws the handheld in the
    /// inner panel's fixed frame for a viewport of this size. nil when the
    /// window is not on the inner display or the published orientation does
    /// not match the size yet (mid-transition): draw nothing then.
    func handheldTurn(for size: CGSize) -> Double? {
        guard isOuter == false, let theta = interfaceRotation else { return nil }
        let portraitTheta = theta == 0 || theta == 180
        guard (size.height >= size.width) == portraitTheta else { return nil }
        return FixedFrameTransform.normalized(Self.handheldReferenceRotation - theta)
    }
    /// Rotation to use for a viewport of this size on the cover display.
    /// The cover mask allows portrait only, so a portrait viewport is always
    /// rotation 0 — decided from the size, which SwiftUI gets synchronously
    /// with the window resize, not from the published value, which reaches
    /// the view one update later (the 10-26 recording showed the casing and
    /// splash drawn upright for 40–600 ms after a launch snap because of it).
    func coverRotation(for size: CGSize) -> Double? {
        // A portrait viewport is portrait-up unless UIKit has told us the
        // window is upside down (a lid closed from the handheld pose keeps
        // the inner display's portraitUpsideDown, see CoverOrientationPolicy).
        if size.height >= size.width { return interfaceRotation == 180 ? 180 : 0 }
        return interfaceRotation
    }
    /// Angle of the interface x-axis measured in the fixed coordinate space.
    static func interfaceRotation(of screen: UIScreen) -> Double {
        let origin = screen.coordinateSpace.convert(CGPoint.zero, to: screen.fixedCoordinateSpace)
        let unit = screen.coordinateSpace.convert(CGPoint(x: 1, y: 0), to: screen.fixedCoordinateSpace)
        let degrees = atan2(unit.y - origin.y, unit.x - origin.x) * 180 / .pi
        return FixedFrameTransform.normalized(degrees)
    }
}

/// A zero-size child view controller that hears UIKit's size/trait
/// transitions. On Duo these fire exactly when the window moves between the
/// inner and outer display (observed: `viewWillTransition` with the new
/// screen already set, `animated == false`). It refreshes the display role
/// and, optionally, suppresses any rotation animation for the transition.
struct DisplayMigrationHost: UIViewControllerRepresentable {
    var snapTransitions: Bool
    func makeUIViewController(context: Context) -> MigrationViewController {
        let controller = MigrationViewController()
        controller.snapTransitions = snapTransitions
        return controller
    }
    func updateUIViewController(_ controller: MigrationViewController, context: Context) { controller.snapTransitions = snapTransitions }

    final class MigrationViewController: UIViewController {
        var snapTransitions = false
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }
        /// Interface rotation and display seen at the last layout pass, so a
        /// transition can tell a rotation on the same panel from a migration.
        private var lastInterfaceRotation: Double?
        private var lastNativeSize: CGSize?
        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            if let window = view.window {
                CoverOrientationPolicy.shared.refreshRole(window)
                if let screen = window.windowScene?.screen {
                    lastInterfaceRotation = DisplayRoleMonitor.interfaceRotation(of: screen)
                    lastNativeSize = screen.nativeBounds.size
                }
            }
        }
        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            let scene = view.window?.windowScene
            let previousRotation = lastInterfaceRotation
            let previousNativeSize = lastNativeSize
            if let window = view.window { CoverOrientationPolicy.shared.refreshRole(window) }
            // Only the cover display snaps: its print is fixed to the casing, so
            // any UIKit rotation there must be invisible. The inner display keeps
            // the system's own rotation behaviour.
            // Both displays are fixed to the handheld orientation; any
            // rotation UIKit performs in place is a correction and must not
            // animate (the content is hidden until it settles anyway).
            let snap = snapTransitions && DisplayRoleMonitor.shared.isOuter != nil
            let sameDisplay = scene?.screen.nativeBounds.size == previousNativeSize
            let newRotation = scene.map { DisplayRoleMonitor.interfaceRotation(of: $0.screen) }
            let rotates = sameDisplay && previousRotation != nil && newRotation != nil && previousRotation != newRotation
            OrientationTrace.shared.event("viewWillTransition to=\(OrientationFormat.size(size)) animated=\(coordinator.isAnimated) duration=\(String(format: "%.2f", coordinator.transitionDuration)) io=\(scene.map { OrientationFormat.orientation($0.effectiveGeometry.interfaceOrientation) } ?? "-") screen=\(OrientationFormat.screen(scene?.screen)) snap=\(snap) rotates=\(rotates) \(previousRotation.map { String(Int($0)) } ?? "-")->\(newRotation.map { String(Int($0)) } ?? "-")")
            guard snap else { return }
            if coordinator.isAnimated { UIView.setAnimationsEnabled(false) }
            // Even a non-animated rotation put a frame or two of the old
            // layout on screen, squashed into the new bounds (10-26 screen
            // recording, launch with the lid closed): SwiftUI lays the
            // hosting view out one pass after UIKit resizes the window. Force
            // that layout inside the transition so the first committed frame
            // already has the new geometry.
            coordinator.animate(alongsideTransition: { [weak self] _ in
                guard rotates, let window = self?.view.window else { return }
                window.rootViewController?.view.setNeedsLayout()
                window.rootViewController?.view.layoutIfNeeded()
                window.layoutIfNeeded()
                OrientationTrace.shared.event("forced layout alongside rotation wb=\(OrientationFormat.size(window.bounds.size)) root=\(OrientationFormat.size(window.rootViewController?.view.bounds.size ?? .zero))")
            }, completion: { _ in
                if coordinator.isAnimated { UIView.setAnimationsEnabled(true) }
                OrientationTrace.shared.event("transition completed")
            })
        }
        override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
            super.willTransition(to: newCollection, with: coordinator)
            OrientationTrace.shared.event("willTransition traits hsc=\(newCollection.horizontalSizeClass.rawValue) vsc=\(newCollection.verticalSizeClass.rawValue) scale=\(newCollection.displayScale)")
            if let window = view.window { CoverOrientationPolicy.shared.refreshRole(window) }
        }
    }
}

// MARK: - Overlay

struct TraceOverlay: View {
    @ObservedObject private var trace = OrientationTrace.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("trace → \(trace.locations.first?.path ?? "no writable directory")")
                .foregroundStyle(.yellow)
            ForEach(Array(trace.recent.suffix(16).enumerated()), id: \.offset) { item in
                Text(item.element)
            }
        }
        .font(.system(size: 8, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(6)
        .background(Color.black.opacity(0.72))
        .allowsHitTesting(false)
    }
}
#endif
