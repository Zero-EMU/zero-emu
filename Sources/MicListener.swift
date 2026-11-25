import SwiftUI
import AVFoundation
import Combine
#if os(iOS)
import UIKit
#endif

/// 11-06: the iPhone's own microphone, on while
/// something listens for a breath — 相机's 闪闪, 系统设置 › 麦克风测试,
/// software that has opened its microphone. Blowing on it is the MIC held
/// (DemoSession): the software gets the console's breath, 闪闪 its pieces.
/// What it hears is neither kept nor sent anywhere: a level for the meter,
/// and whether that is someone blowing (the wind of a breath on a
/// microphone is loud, and low). The MIC hole on the casing still works,
/// for where blowing will not do (or the microphone is not allowed).
@MainActor final class MicListener: ObservableObject {
    static let shared = MicListener()
    enum Access: Equatable {
        /// Not asked yet.
        case unknown
        case granted
        /// Turned off in 设置 › FoldArc.
        case denied
        /// None to use (the Simulator; the Mac preview).
        case unavailable
    }
    @Published private(set) var access: Access
    /// The microphone is on.
    @Published private(set) var on = false
    /// What it hears, 0…1 (−60…0 dBFS), while on.
    @Published private(set) var level = 0.0
    /// Someone is blowing on it.
    @Published private(set) var blowing = false
    /// A breath, as the cartridges' films hear one (BreathGate): measured
    /// against what the microphone hears anyway, so that a film's own sound
    /// from the speaker does not hide it.
    @Published private(set) var breathing = false
    /// The arrow to the microphone (MicPointer): from when it comes on until
    /// the first breath, or a while.
    @Published private(set) var pointerShown = false
    /// Who listens (each one's own name).
    private var reasons: Set<String> = []
    private var asking = false
    #if DEBUG
    /// The levels in the trace once a second while it listens (the loudest
    /// low level in that second), to see what a breath and a film's sound
    /// come to on the device.
    private var traceAt = Date.distantPast
    private var tracePeak = -120.0
    private var tracePeakAll = -120.0
    private var traceAll = -120.0
    #endif
    private var phaseWatch: AnyCancellable?
    private var pointerTask: Task<Void, Never>?
    /// Nothing but digital silence coming in (every sample zero), and how many times since it came on.
    private var silentNow = false
    private var silences = 0
    #if os(iOS)
    private let engine = MicEngine()
    #endif

    private init() {
        #if os(iOS) && !targetEnvironment(simulator)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: access = .granted
        case .denied: access = .denied
        default: access = .unknown
        }
        #else
        access = .unavailable
        #endif
        #if os(iOS)
        // Off in the background (the system would stop it anyway), on
        // again when FoldArc is back in front and someone still listens.
        phaseWatch = AppScenePhase.shared.$phase.removeDuplicates().sink { _ in
            DispatchQueue.main.async { MicListener.shared.refresh() }
        }
        #endif
    }

    /// `key` listens (true) or no longer does.
    func want(_ key: String, _ listening: Bool) {
        let changed = listening ? reasons.insert(key).inserted : reasons.remove(key) != nil
        guard changed else { return }
        NSLog("[mic] %@ %@ (%d listening)", key, listening ? "listens" : "stops listening", reasons.count)
        #if DEBUG && os(iOS)
        OrientationTrace.shared.event("mic: \(key) \(listening ? "listens" : "stops listening") (\(reasons.count) listening)")
        #endif
        refresh()
    }

    private func refresh() {
        #if os(iOS)
        let wanted = !reasons.isEmpty && AppScenePhase.shared.phase != .background
        #else
        let wanted = false
        #endif
        if wanted { start() } else { stop() }
    }

    private func start() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard !on, !asking else { return }
        // 11-07: a silent test run (`--foldarc-silent`) leaves the
        // microphone alone; the MIC hole still blows.
        guard !SilentRun.on else { NSLog("[mic] silent run: not listening"); return }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            access = .granted
            begin()
        case .denied:
            access = .denied
            NSLog("[mic] the microphone is not allowed (设置 › FoldArc): the MIC hole only")
        default:
            // The system asks once (NSMicrophoneUsageDescription).
            asking = true
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    let listener = MicListener.shared
                    listener.asking = false
                    listener.access = granted ? .granted : .denied
                    NSLog("[mic] the microphone %@", granted ? "allowed" : "not allowed")
                    listener.refresh()
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private func begin() {
        on = true
        silentNow = false
        silences = 0
        showPointer()
        engine.start { heard in
            Task { @MainActor in MicListener.shared.heard(heard) }
        } failed: { reason in
            Task { @MainActor in
                NSLog("[mic] did not start: %@", reason)
                MicListener.shared.stopped()
            }
        } noted: { line in
            Task { @MainActor in MicListener.shared.note(line) }
        }
        NSLog("[mic] on")
        #if DEBUG
        OrientationTrace.shared.event("mic: on")
        #endif
    }
    /// A line from the engine (what it listens to, the input changing, an interruption): the log, and the trace.
    private func note(_ line: String) {
        NSLog("[mic] %@", line)
        #if DEBUG
        OrientationTrace.shared.event("mic: \(line)")
        #endif
    }
    #endif

    private func stop() {
        guard on else { return }
        #if os(iOS)
        engine.stop()
        #endif
        stopped()
        NSLog("[mic] off")
        #if DEBUG && os(iOS)
        OrientationTrace.shared.event("mic: off")
        #endif
    }
    private func stopped() {
        on = false
        if level != 0 { level = 0 }
        if blowing { blowing = false }
        if breathing { breathing = false }
        hidePointer()
    }

    #if os(iOS)
    /// From the engine's analysis (on the main queue, at most ~15 a second,
    /// and at once when blowing or a breath starts or stops).
    private func heard(_ heard: MicEngine.Heard) {
        guard on else { return }
        let next = min(1, max(0, (heard.decibels + 60) / 60))
        if abs(next - level) > 0.01 { level = next }
        if heard.blowing != blowing {
            blowing = heard.blowing
            NSLog("[mic] %@ (low %.1f dBFS, all %.1f dBFS)", heard.blowing ? "blowing" : "quiet again", heard.lowDecibels, heard.decibels)
            #if DEBUG
            OrientationTrace.shared.event(String(format: "mic: %@ (low %.1f dBFS, all %.1f)", heard.blowing ? "blowing" : "quiet again", heard.lowDecibels, heard.decibels))
            #endif
            if heard.blowing { hidePointer() }
        }
        // 11-23: nothing but silence (seen on the iPhone Duo: every sample zero for as long as the app listened):
        // the input started once more, on the system's own choice of microphone; noted again if that gives none too
        if heard.silent != silentNow {
            silentNow = heard.silent
            if heard.silent {
                silences += 1
                note((silences == 1 ? "nothing but silence comes in (every sample zero): " : "still nothing but silence after starting again: ") + MicEngine.describe())
                if silences == 1 { engine.restart("nothing but silence", anyMicrophone: true) }
            } else if silences > 0, heard.decibels > BreathGate.silence {
                note(String(format: "sound comes in (%.1f dBFS)", heard.decibels))
            }
        }
        if heard.breath != breathing {
            breathing = heard.breath
            NSLog("[mic] a breath %@ (low %.1f dBFS, heard anyway %.1f dBFS)", heard.breath ? "begins" : "ends", heard.lowDecibels, heard.floor)
            #if DEBUG
            OrientationTrace.shared.event(String(format: "mic: a breath %@ (low %.1f dBFS, heard anyway %.1f, all %.1f)", heard.breath ? "begins" : "ends", heard.lowDecibels, heard.floor, heard.decibels))
            #endif
            if heard.breath { hidePointer() }
        }
        #if DEBUG
        if heard.lowPeak > tracePeak { tracePeak = heard.lowPeak; tracePeakAll = heard.lowPeakAll }
        traceAll = max(traceAll, heard.decibels)
        let now = Date()
        if now.timeIntervalSince(traceAt) >= 1 {
            if traceAt != .distantPast {
                OrientationTrace.shared.event(String(format: "mic: loudest low %.1f dBFS (all %.1f in that buffer), heard anyway %.1f, a breath needs %.1f, loudest all %.1f%@%@", tracePeak, tracePeakAll, heard.floor, heard.needs, traceAll, breathing ? " (a breath)" : "", blowing ? " (blowing)" : ""))
            }
            traceAt = now
            tracePeak = -120
            tracePeakAll = -120
            traceAll = -120
        }
        #endif
    }
    #endif

    private func showPointer() {
        pointerTask?.cancel()
        // 11-23: on a new console only, the first time the microphone listens (OnceHint); never after
        guard !OnceHint.seen("blow-arrow") else { return }
        OnceHint.mark("blow-arrow")
        pointerShown = true
        pointerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            MicListener.shared.pointerShown = false
        }
    }
    private func hidePointer() {
        pointerTask?.cancel(); pointerTask = nil
        if pointerShown { pointerShown = false }
    }
}

#if os(iOS)
/// The input engine and its analysis, on a queue of their own (starting an
/// engine, changing the session, can block). 11-23: it starts again by itself
/// when the input changes under it (the engine stops then), after an
/// interruption, after the media services reset, and once when nothing but
/// silence comes in; what it listens to is noted each time.
final class MicEngine: @unchecked Sendable {
    struct Heard: Sendable {
        var decibels: Double
        var lowDecibels: Double
        var blowing: Bool
        /// A breath as the films hear one (BreathGate), and what the low
        /// level is anyway.
        var breath: Bool
        var floor: Double
        /// The loudest low level since the last report, and the whole level of that buffer.
        var lowPeak: Double
        var lowPeakAll: Double
        /// The low level a breath has to pass now (BreathGate).
        var needs: Double
        /// Nothing at all has come in for a second and a half (every sample zero).
        var silent: Bool
    }
    private let queue = DispatchQueue(label: "FoldArc.mic", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private let analysis = MicAnalysis()
    // (the rest on `queue`)
    private var listening = false
    private var heard: (@Sendable (Heard) -> Void)?
    private var failed: (@Sendable (String) -> Void)?
    private var noted: (@Sendable (String) -> Void)?
    private var restarts = 0
    /// The bottom microphone chosen (MicPointer points at it); false after it gave nothing but silence.
    private var bottom = true
    private var engineWatch: NSObjectProtocol?
    private var sessionWatch: [NSObjectProtocol] = []

    func start(heard: @escaping @Sendable (Heard) -> Void, failed: @escaping @Sendable (String) -> Void, noted: @escaping @Sendable (String) -> Void) {
        queue.async {
            guard !self.listening else { return }
            self.listening = true
            self.heard = heard
            self.failed = failed
            self.noted = noted
            self.restarts = 0
            self.bottom = true
            self.watchSession()
            self.run("on")
        }
    }

    func stop() {
        queue.async {
            guard self.listening else { return }
            self.finish()
        }
    }

    /// The input again, from nothing (`why` for the log); `anyMicrophone`: the system's own choice of built-in
    /// microphone from now on, not the bottom one.
    func restart(_ why: String, anyMicrophone: Bool = false) {
        queue.async {
            guard self.listening else { return }
            guard self.restarts < 6 else {
                self.noted?("not started again (\(why)): six times already")
                return
            }
            self.restarts += 1
            if anyMicrophone { self.bottom = false }
            self.teardown()
            self.run(why)
        }
    }

    /// The engine and its tap (on the queue).
    private func run(_ why: String) {
        // Play and record, out of the speaker (AudioPolicy).
        AudioPolicy.shared.setListening(true)
        if bottom { MicEngine.preferBottomMicrophone() } else { MicEngine.preferAnyMicrophone() }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            fail("no input (\(format))")
            return
        }
        analysis.reset(report: heard)
        let analysis = self.analysis
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in analysis.add(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("\(error)")
            return
        }
        self.engine = engine
        // (the engine stops when the input changes in a way it cannot follow, and says so: AVAudioEngine.h)
        engineWatch = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.restart("the input changed")
        }
        noted?("listening (\(why)): \(Int(format.sampleRate)) Hz, \(format.channelCount) channel(s); \(MicEngine.describe())")
    }

    private func teardown() {
        if let engineWatch { NotificationCenter.default.removeObserver(engineWatch) }
        engineWatch = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Stopped for good (asked to, or it could not start): the session plays only again.
    private func finish() {
        listening = false
        teardown()
        for token in sessionWatch { NotificationCenter.default.removeObserver(token) }
        sessionWatch = []
        analysis.reset(report: nil)
        AudioPolicy.shared.setListening(false)
        heard = nil
        failed = nil
        noted = nil
    }

    private func fail(_ reason: String) {
        let failed = self.failed
        finish()
        failed?(reason)
    }

    /// An interruption (a call, Siri, the microphone muted), the route changing, the media services reset: noted;
    /// after an interruption and a reset the input starts again (as AzaharSession's engine does: iOS 27 reports an
    /// interruption as the session going inactive and a resumption after, earlier versions as began / ended).
    private func watchSession() {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        if #available(iOS 27.0, *) {
            tokens.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: nil) { [weak self] note in
                let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
                guard context?.source != .app else { return }
                let detail = context?.interruptionContext.map { "reason \($0.reason.rawValue)" } ?? "no reason given"
                self?.queue.async { self?.noted?("the audio session was interrupted (\(detail))") }
            })
            tokens.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: nil) { [weak self] note in
                let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
                self?.restart(context.map { $0.recommendation == .shouldResume ? "after an interruption" : "after an interruption (not recommended)" } ?? "after an interruption")
            })
        } else {
            tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began {
                    self?.queue.async { self?.noted?("the audio session was interrupted") }
                } else {
                    self?.restart("after an interruption")
                }
            })
        }
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "-"
            self?.queue.async { self?.noted?("the audio route changed (reason \(reason)): \(MicEngine.describe())") }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.restart("the media services were reset")
        })
        sessionWatch = tokens
    }

    /// What the session listens to now, for the log: the inputs (their kind and which microphone, not their names:
    /// a headset's is its owner's), the category and mode, whether the app's input is muted, whether there is any.
    static func describe() -> String {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map { "\($0.portType.rawValue) \($0.selectedDataSource?.dataSourceName ?? "-")" }.joined(separator: ", ")
        return "input \(inputs.isEmpty ? "none" : inputs), \(AudioPolicy.name(session.category)) \(session.mode.rawValue), the app's input muted: \(AVAudioApplication.shared.isInputMuted ? "yes" : "no"), input available: \(session.isInputAvailable ? "yes" : "no")"
    }

    /// The built-in microphone, whichever the system picks (the bottom one gave nothing).
    private static func preferAnyMicrophone() {
        let session = AVAudioSession.sharedInstance()
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        do {
            try session.setPreferredInput(builtIn)
            try builtIn.setPreferredDataSource(nil)
        } catch {
            NSLog("[mic] the built-in microphone not chosen: %@", "\(error)")
        }
    }

    /// The built-in microphone at the bottom edge (by the USB-C port) where
    /// the iPhone has one to choose: the one MicPointer points at. What the
    /// device offers is logged.
    private static func preferBottomMicrophone() {
        let session = AVAudioSession.sharedInstance()
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            NSLog("[mic] no built-in microphone among the inputs")
            return
        }
        let sources = builtIn.dataSources ?? []
        NSLog("[mic] built-in microphones: %@", sources.map { "\($0.dataSourceName) (\($0.orientation?.rawValue ?? "-"), \($0.location?.rawValue ?? "-"))" }.joined(separator: "; "))
        do {
            try session.setPreferredInput(builtIn)
            if let bottom = sources.first(where: { $0.orientation == .bottom }) {
                try builtIn.setPreferredDataSource(bottom)
            }
        } catch {
            NSLog("[mic] the bottom microphone not chosen: %@", "\(error)")
        }
    }
}

/// What a buffer holds: its level, the level under ~300 Hz (a breath's wind
/// is mostly there; a voice or the game's sound from the speaker much less),
/// and blowing — the low level over −22 dBFS for two buffers running, until
/// it stays under −32 dBFS for six (a buffer is about a tenth of a second on
/// the device). And a breath as the cartridges' films hear one (BreathGate:
/// nearly all low, against what the microphone hears anyway), and whether
/// nothing but digital silence has come in for a while.
final class MicAnalysis: @unchecked Sendable {
    private let lock = NSLock()
    private var low: Float = 0
    private var coefficient: Float = 0.04
    private var loud = 0
    private var quiet = 0
    private var blowing = false
    private var gate = BreathGate()
    private var lowPeak = -120.0
    private var lowPeakAll = -120.0
    private var lastReport = Date.distantPast
    private var report: (@Sendable (MicEngine.Heard) -> Void)?
    #if DEBUG
    private var lastLog = Date.distantPast
    #endif
    static let blowOn = -22.0
    static let blowOff = -32.0

    /// How long nothing but digital silence has come in (seconds), and whether that is long enough to say so.
    private var silentFor = 0.0
    private var silent = false

    func reset(report: (@Sendable (MicEngine.Heard) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        low = 0; loud = 0; quiet = 0; blowing = false; lastReport = .distantPast
        gate = BreathGate(); lowPeak = -120; lowPeakAll = -120
        silentFor = 0; silent = false
        self.report = report
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let data = buffer.floatChannelData?[0] else { return }
        let rate = max(8_000, buffer.format.sampleRate)
        let seconds = Double(frames) / rate
        lock.lock()
        // (the low-pass for ~300 Hz at the buffer's own rate)
        coefficient = Float(1 - exp(-2 * Double.pi * 300 / rate))
        var sum: Float = 0, lowSum: Float = 0, lp = low
        let a = coefficient
        for i in 0..<frames {
            let x = data[i]
            sum += x * x
            lp += a * (x - lp)
            lowSum += lp * lp
        }
        low = lp
        let decibels = 20 * log10(Double(max(1e-6, (sum / Float(frames)).squareRoot())))
        let lowDecibels = 20 * log10(Double(max(1e-6, (lowSum / Float(frames)).squareRoot())))
        let was = blowing, wasBreath = gate.on, wasSilent = silent
        if lowDecibels > Self.blowOn { loud += 1; quiet = 0 } else if lowDecibels < Self.blowOff { quiet += 1; loud = 0 } else { loud = 0; quiet = 0 }
        if !blowing && loud >= 2 { blowing = true }
        if blowing && quiet >= 6 { blowing = false }
        gate.add(lowDecibels, all: decibels, seconds: seconds)
        silentFor = decibels <= BreathGate.silence ? silentFor + seconds : 0
        silent = silentFor >= 1.5
        if lowDecibels > lowPeak { lowPeak = lowDecibels; lowPeakAll = decibels }
        let now = Date()
        let due = was != blowing || wasBreath != gate.on || wasSilent != silent || now.timeIntervalSince(lastReport) > 0.066
        if due { lastReport = now }
        let heard = MicEngine.Heard(decibels: decibels, lowDecibels: lowDecibels, blowing: blowing, breath: gate.on, floor: gate.floor,
                                    lowPeak: lowPeak, lowPeakAll: lowPeakAll, needs: gate.level, silent: silent)
        if due { lowPeak = -120; lowPeakAll = -120 }
        let report = self.report
        #if DEBUG
        // Levels only (four a second): enough to set the thresholds on a device.
        let log = now.timeIntervalSince(lastLog) > 0.25
        if log { lastLog = now }
        #endif
        lock.unlock()
        #if DEBUG
        if log { NSLog("[mic] level %.1f dBFS, low %.1f dBFS (heard anyway %.1f)%@%@", decibels, lowDecibels, heard.floor, heard.blowing ? " (blowing)" : "", heard.breath ? " (a breath)" : "") }
        #endif
        if due { report?(heard) }
    }
}
#endif

// MARK: - Where the microphone is

/// Where the console's MIC is drawn (MicHole), for MicPointer: every MIC on
/// screen reports its bounds (the largest is the console's own; a style's
/// little preview in 主题 draws one too), and every screen and control
/// round it its own (`micPointerObstacle()`), so that the arrow and its
/// words go where they cover none of them (11-07, the b75 renders: above
/// the MIC they covered the touch screen's corner on the handheld, SELECT
/// and the touch screen's edge on the cover).
struct MicPointerMap {
    var holes: [Anchor<CGRect>] = []
    var obstacles: [Anchor<CGRect>] = []
}
struct MicHoleAnchorKey: PreferenceKey {
    static let defaultValue = MicPointerMap()
    static func reduce(value: inout MicPointerMap, nextValue: () -> MicPointerMap) {
        let next = nextValue()
        value.holes += next.holes
        value.obstacles += next.obstacles
    }
}
extension View {
    /// A screen or control MicPointer's arrow and words keep off.
    func micPointerObstacle() -> some View {
        transformAnchorPreference(key: MicHoleAnchorKey.self, value: .bounds) { $0.obstacles.append($1) }
    }
}

/// 11-07: while the
/// microphone listens and nobody has blown yet, an arrow at the console's
/// MIC with 「对着这边吹气」, on the side of it where they cover no screen or
/// control (MicPointerLayout). Where no MIC is drawn (沉浸模式, a full-screen
/// program) it points at the edge of the display the iPhone's microphone
/// is on, as before: the bottom edge by the USB-C port (MicEngine chooses
/// it; on the iPhone Duo's inner display the right edge of its own
/// portrait, its upper half — b59's camera). Not a control: touches go
/// through.
struct MicPointer: View {
    @ObservedObject private var mic = MicListener.shared
    /// The MICs drawn under it, and the screens and controls round them.
    var map = MicPointerMap()
    var body: some View {
        // The display's safe area (the home indicator, the status bar), kept
        // clear too; the drawing itself covers the whole display.
        GeometryReader { safe in
        let insets = safe.safeAreaInsets
        GeometryReader { proxy in
            #if os(iOS)
            if mic.pointerShown {
                let holes = map.holes.map { proxy[$0] }.filter { $0.width > 16 && $0.height > 8 && proxy.frame(in: .local).intersects($0) }
                if let hole = holes.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                    MicPointerAtHole(hole: hole, obstacles: map.obstacles.map { proxy[$0] }, size: proxy.size, safe: insets)
                        .transition(.opacity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("对着这边吹气：箭头指着掌机上的 MIC")
                        .accessibilityIdentifier("mic-pointer")
                } else if let spot = Self.spot(in: proxy.size) {
                    MicPointerArrow(edge: spot.edge)
                        .position(spot.point)
                        .transition(.opacity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("对着这边吹气")
                        .accessibilityIdentifier("mic-pointer")
                }
            }
            #endif
        }
        .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.25), value: mic.pointerShown)
        .allowsHitTesting(false)
    }

    #if os(iOS)
    /// Where the microphone is on the display's own upright portrait (0…1,
    /// y down): the Duo's inner display, or the bottom edge's middle.
    static func nativeSpot(innerDisplay: Bool) -> CGPoint {
        innerDisplay ? CGPoint(x: 1, y: 0.25) : CGPoint(x: 0.5, y: 1)
    }
    /// That point in the window, as the interface is turned on the display
    /// (UIKit's landscapeRight: the display's right edge is the window's top).
    static func windowSpot(_ p: CGPoint, orientation: UIInterfaceOrientation) -> CGPoint {
        switch orientation {
        case .portraitUpsideDown: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        case .landscapeRight: return CGPoint(x: p.y, y: 1 - p.x)
        case .landscapeLeft: return CGPoint(x: 1 - p.y, y: p.x)
        default: return p
        }
    }
    /// The arrow's place in a window of `size` and the edge it points at.
    @MainActor static func spot(in size: CGSize) -> (point: CGPoint, edge: Edge)? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.session.role == .windowApplication }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first, size.width > 0, size.height > 0 else { return nil }
        // The Duo's inner display (learned from the hinge); else the cover
        // or an iPhone without a hinge: the bottom edge.
        let inner = CoverOrientationPolicy.KnownDisplays.role(of: scene.screen) == false
        let p = windowSpot(nativeSpot(innerDisplay: inner), orientation: scene.effectiveGeometry.interfaceOrientation)
        let inset = 16.0
        let edge: Edge
        if p.x >= 0.99 { edge = .trailing } else if p.x <= 0.01 { edge = .leading } else if p.y <= 0.01 { edge = .top } else { edge = .bottom }
        let x = edge == .trailing ? size.width - inset : edge == .leading ? inset : p.x * size.width
        let y = edge == .bottom ? size.height - inset : edge == .top ? inset : p.y * size.height
        // The arrow's tip at the edge; the whole drawing is laid out round
        // its middle, so move it in by half its length.
        let half = MicPointerArrow.length / 2
        switch edge {
        case .trailing: return (CGPoint(x: x - half, y: y), edge)
        case .leading: return (CGPoint(x: x + half, y: y), edge)
        case .top: return (CGPoint(x: x, y: y + half), edge)
        case .bottom: return (CGPoint(x: x, y: y - half), edge)
        }
    }
    #endif
}

/// Where the arrow and its words go round a MIC drawn at `hole` (its 64 × 30
/// frame, the dot and the word MIC in its middle): above it, to its right,
/// to its left or under it — the words full size, then smaller — the first
/// that covers no screen or control and stays on the display; failing all,
/// the one that covers least (the words count more than the arrow).
enum MicPointerLayout {
    struct Plan: Equatable {
        /// Where the words are, from the MIC; the arrow between, pointing at it.
        var side: Edge
        var compact: Bool
        var arrow: CGRect
        var words: CGRect
    }
    /// The words' capsule (MicPointerArrow.words), about.
    static func wordsSize(compact: Bool) -> CGSize { compact ? CGSize(width: 90, height: 25) : CGSize(width: 110, height: 31) }
    /// The arrow, along it and across it.
    static let arrowLength = 34.0
    static let arrowBreadth = 30.0
    static let order: [Edge] = [.top, .trailing, .leading, .bottom]

    static func plan(hole: CGRect, obstacles: [CGRect], bounds: CGRect, safe: EdgeInsets = EdgeInsets()) -> Plan {
        evaluate(hole: hole, obstacles: obstacles, bounds: bounds, safe: safe).plan
    }
    /// The plan and what it covers (0: nothing).
    static func evaluate(hole: CGRect, obstacles: [CGRect], bounds: CGRect, safe: EdgeInsets = EdgeInsets()) -> (plan: Plan, cost: Double) {
        let all = candidates(hole: hole, obstacles: obstacles, bounds: bounds, safe: safe)
        return all.first(where: { $0.cost == 0 }) ?? all.min(by: { $0.cost < $1.cost })!
    }
    /// Every placement in the order tried, with what it covers.
    static func candidates(hole: CGRect, obstacles: [CGRect], bounds: CGRect, safe: EdgeInsets = EdgeInsets()) -> [(plan: Plan, cost: Double)] {
        let area = CGRect(x: bounds.minX + safe.leading + 4, y: bounds.minY + safe.top + 4,
                          width: max(1, bounds.width - safe.leading - safe.trailing - 8), height: max(1, bounds.height - safe.top - safe.bottom - 8))
        // The dot and the word: 23 × 8 of the hole's 64 × 30.
        let scale = max(0.3, hole.height / 30)
        let mark = CGRect(x: hole.midX - 12 * scale, y: hole.midY - 5 * scale, width: 24 * scale, height: 10 * scale)
        var out: [(plan: Plan, cost: Double)] = []
        for compact in [false, true] {
            for side in order {
                let plan = place(side: side, compact: compact, mark: mark, area: area)
                out.append((plan, cost(plan, mark: mark, obstacles: obstacles, area: area)))
            }
        }
        return out
    }

    static func place(side: Edge, compact: Bool, mark: CGRect, area: CGRect) -> Plan {
        let words = wordsSize(compact: compact)
        let gap = 3.0
        func clampX(_ x: Double) -> Double { min(max(x, area.minX), max(area.minX, area.maxX - words.width)) }
        func clampY(_ y: Double) -> Double { min(max(y, area.minY), max(area.minY, area.maxY - words.height)) }
        switch side {
        case .top:
            let arrow = CGRect(x: mark.midX - arrowBreadth / 2, y: mark.minY - gap - arrowLength, width: arrowBreadth, height: arrowLength)
            let box = CGRect(x: clampX(mark.midX - words.width / 2), y: arrow.minY - 2 - words.height, width: words.width, height: words.height)
            return Plan(side: side, compact: compact, arrow: arrow, words: box)
        case .bottom:
            let arrow = CGRect(x: mark.midX - arrowBreadth / 2, y: mark.maxY + gap, width: arrowBreadth, height: arrowLength)
            let box = CGRect(x: clampX(mark.midX - words.width / 2), y: arrow.maxY + 2, width: words.width, height: words.height)
            return Plan(side: side, compact: compact, arrow: arrow, words: box)
        case .trailing:
            let arrow = CGRect(x: mark.maxX + gap, y: mark.midY - arrowBreadth / 2, width: arrowLength, height: arrowBreadth)
            let box = CGRect(x: arrow.maxX + 4, y: clampY(mark.midY - words.height / 2), width: words.width, height: words.height)
            return Plan(side: side, compact: compact, arrow: arrow, words: box)
        case .leading:
            let arrow = CGRect(x: mark.minX - gap - arrowLength, y: mark.midY - arrowBreadth / 2, width: arrowLength, height: arrowBreadth)
            let box = CGRect(x: arrow.minX - 4 - words.width, y: clampY(mark.midY - words.height / 2), width: words.width, height: words.height)
            return Plan(side: side, compact: compact, arrow: arrow, words: box)
        }
    }

    /// What a plan covers: the words' overlap with screens, controls and the
    /// MIC itself in full, the arrow's at a third, and anything off the
    /// display ten times over.
    static func cost(_ plan: Plan, mark: CGRect, obstacles: [CGRect], area: CGRect) -> Double {
        func overlap(_ a: CGRect, _ b: CGRect) -> Double {
            let i = a.intersection(b)
            return i.isNull ? 0 : Double(i.width * i.height)
        }
        func outside(_ r: CGRect) -> Double { Double(r.width * r.height) - overlap(r, area) }
        var cost = 10 * (outside(plan.words) + outside(plan.arrow)) + overlap(plan.words, mark.insetBy(dx: -2, dy: -2))
        for obstacle in obstacles {
            cost += overlap(plan.words, obstacle.insetBy(dx: -2, dy: -2)) + overlap(plan.arrow, obstacle) / 3
        }
        return cost
    }
}

/// The arrow and its words at the console's MIC (MicPointerLayout), the
/// arrow's tip a few points off it, nudging towards it.
struct MicPointerAtHole: View {
    var hole: CGRect
    /// The screens and controls round it, in the same space.
    var obstacles: [CGRect] = []
    var size: CGSize
    /// The display's safe area, kept clear (the home indicator, the status bar).
    var safe = EdgeInsets()
    @State private var nudge = false
    /// 减弱动态效果: the arrow stands still (it has faded in, once).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let moving = nudge && !reduceMotion
        let plan = MicPointerLayout.plan(hole: hole, obstacles: obstacles, bounds: CGRect(origin: .zero, size: size), safe: safe)
        let symbol: String = switch plan.side {
        case .top: "arrow.down"
        case .bottom: "arrow.up"
        case .trailing: "arrow.left"
        case .leading: "arrow.right"
        }
        let towards: CGSize = switch plan.side {
        case .top: CGSize(width: 0, height: 7)
        case .bottom: CGSize(width: 0, height: -7)
        case .trailing: CGSize(width: -7, height: 0)
        case .leading: CGSize(width: 7, height: 0)
        }
        ZStack(alignment: .topLeading) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(MicPointerArrow.colour)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .position(x: plan.arrow.midX, y: plan.arrow.midY)
            MicPointerArrow.words(compact: plan.compact)
                .position(x: plan.words.midX, y: plan.words.midY)
        }
        .frame(width: size.width, height: size.height)
        .offset(moving ? towards : .zero)
        .animation(moving ? Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true) : nil, value: moving)
        .onAppear { nudge = true }
    }
}

/// The arrow and its words, pointing at `edge`, nudging towards it.
struct MicPointerArrow: View {
    var edge: Edge
    /// A deep orange: white words on it read on any finish.
    static let colour = Color(red: 0.93, green: 0.4, blue: 0.08)
    /// Along the arrow, words and all (points).
    static let length = 150.0
    /// The words' capsule, about (points).
    static let wordsWidth = 120.0
    /// 11-07: the words alone (the USB-C line is gone); `compact`
    /// where the full size covers something (MicPointerLayout).
    static func words(compact: Bool = false) -> some View {
        Text("对着这边吹气").font(.system(size: compact ? 12 : 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 9 : 12).padding(.vertical, compact ? 5 : 7)
            .background(Capsule().fill(colour).shadow(color: .black.opacity(0.35), radius: 3, y: 1))
            .fixedSize()
    }
    @State private var nudge = false
    /// 减弱动态效果: the arrow stands still (it has faded in, once).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let moving = nudge && !reduceMotion
        let across = edge == .leading || edge == .trailing
        let symbol: String = switch edge {
        case .trailing: "arrow.right"
        case .leading: "arrow.left"
        case .top: "arrow.up"
        case .bottom: "arrow.down"
        }
        let arrow = Image(systemName: symbol)
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(Self.colour)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        let words = Self.words()
        let towards: CGSize = switch edge {
        case .trailing: CGSize(width: 7, height: 0)
        case .leading: CGSize(width: -7, height: 0)
        case .top: CGSize(width: 0, height: -7)
        case .bottom: CGSize(width: 0, height: 7)
        }
        Group {
            if across {
                HStack(spacing: 6) {
                    if edge == .trailing { words; arrow } else { arrow; words }
                }
            } else {
                VStack(spacing: 4) {
                    if edge == .bottom { words; arrow } else { arrow; words }
                }
            }
        }
        .offset(moving ? towards : .zero)
        .animation(moving ? Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true) : nil, value: moving)
        .onAppear { nudge = true }
    }
}

#if DEBUG && os(iOS)
/// 11-23 `--foldarc-mic-probe` (a check on the device, DEBUG only): the microphone tried each way once — each built-in
/// microphone, the session mixing or not, the measurement mode, record only, a recorder in place of the engine — two
/// seconds each, and what came in written to the trace: how many samples were not zero, the loudest, the level. Only
/// numbers; nothing is kept. (Seen on the iPhone Duo: every sample zero, whichever way the app listened; this says
/// whether any way gets sound.)
enum MicProbe {
    private struct Way {
        var name: String
        var category: AVAudioSession.Category = .playAndRecord
        var mode: AVAudioSession.Mode = .default
        var mixes = true
        /// One of the built-in microphones (its data source's ID); nil: the system's choice.
        var source: NSNumber?
        var recorder = false
        var options: AVAudioSession.CategoryOptions {
            guard category == .playAndRecord else { return mixes ? [.mixWithOthers] : [] }
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay]
            if mixes { options.insert(.mixWithOthers) }
            return options
        }
    }

    static func start() {
        DispatchQueue(label: "FoldArc.micProbe", qos: .userInitiated).async { run() }
    }

    private static func say(_ line: String) {
        NSLog("[mic probe] %@", line)
        Task { @MainActor in OrientationTrace.shared.event("mic probe: \(line)") }
    }

    private static func run() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: Way(name: "").options)
            try session.setActive(true)
        } catch {
            say("the session not set at first (\(error.localizedDescription))")
        }
        say("permission \(AVAudioApplication.shared.recordPermission == .granted ? "granted" : "not granted"), the app's input muted \(AVAudioApplication.shared.isInputMuted ? "yes" : "no"), input available \(session.isInputAvailable ? "yes" : "no"), other audio playing \(session.isOtherAudioPlaying ? "yes" : "no"), secondary audio silenced \(session.secondaryAudioShouldBeSilencedHint ? "yes" : "no"), input gain \(String(format: "%.2f", session.inputGain)) (settable \(session.isInputGainSettable ? "yes" : "no")), \(Int(session.sampleRate)) Hz")
        let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic })
        let sources = builtIn?.dataSources ?? []
        say("inputs: \(session.availableInputs?.map(\.portType.rawValue).joined(separator: ", ") ?? "none"); built-in microphones: \(sources.map { "\($0.dataSourceName) (\($0.orientation?.rawValue ?? "-"))" }.joined(separator: ", "))")
        var ways = sources.map { Way(name: "mixes, \($0.dataSourceName)", source: $0.dataSourceID) }
        ways += [
            Way(name: "mixes, the system's microphone"),
            Way(name: "does not mix", mixes: false),
            Way(name: "does not mix, measurement", mode: .measurement, mixes: false),
            Way(name: "record only", category: .record, mixes: false),
            Way(name: "a recorder, mixes", recorder: true),
            Way(name: "a recorder, does not mix", mixes: false, recorder: true),
        ]
        for way in ways { attempt(way) }
        // the app's own session again (AudioPolicy), as before the probe
        AudioPolicy.shared.setListening(false)
        say("done")
    }

    private static func attempt(_ way: Way) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(way.category, mode: way.mode, options: way.options)
            try session.setActive(true)
        } catch {
            say("\(way.name): the session not set (\(error.localizedDescription))")
            return
        }
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            do {
                try session.setPreferredInput(builtIn)
                try builtIn.setPreferredDataSource(way.source.flatMap { id in builtIn.dataSources?.first(where: { $0.dataSourceID == id }) })
            } catch {
                say("\(way.name): the microphone not chosen (\(error.localizedDescription))")
            }
        }
        Thread.sleep(forTimeInterval: 0.3)
        let result = way.recorder ? record() : listen()
        let route = session.currentRoute.inputs.map { "\($0.portType.rawValue) \($0.selectedDataSource?.dataSourceName ?? "-")" }.joined(separator: ", ")
        say("\(way.name): \(result); input \(route.isEmpty ? "none" : route)")
    }

    /// Two seconds through an engine's tap.
    private static func listen() -> String {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return "no input format" }
        let tally = Tally()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in tally.add(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return "the engine did not start (\(error.localizedDescription))"
        }
        Thread.sleep(forTimeInterval: 2)
        input.removeTap(onBus: 0)
        engine.stop()
        return tally.summary + String(format: " (%.0f Hz, %d channel(s))", format.sampleRate, format.channelCount)
    }

    /// Two seconds into a recorder (a file in tmp, removed after): its meters.
    private static func record() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mic-probe.caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return "the recorder did not start" }
            var peak: Float = -160, average: Float = -160
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 0.1)
                recorder.updateMeters()
                peak = max(peak, recorder.peakPower(forChannel: 0))
                average = max(average, recorder.averagePower(forChannel: 0))
            }
            recorder.stop()
            return String(format: "the recorder's meters: loudest %.1f dB, average up to %.1f dB", peak, average)
        } catch {
            return "no recorder (\(error.localizedDescription))"
        }
    }

    /// What came through a tap (on the audio thread; read after).
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var samples = 0
        private var notZero = 0
        private var peak: Float = 0
        private var squares = 0.0
        func add(_ buffer: AVAudioPCMBuffer) {
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var count = 0, loudest: Float = 0, sum = 0.0
            for i in 0..<frames {
                let x = data[i]
                if x != 0 { count += 1 }
                loudest = max(loudest, abs(x))
                sum += Double(x) * Double(x)
            }
            lock.lock()
            samples += frames; notZero += count; peak = max(peak, loudest); squares += sum
            lock.unlock()
        }
        var summary: String {
            lock.lock(); defer { lock.unlock() }
            guard samples > 0 else { return "nothing came in" }
            let rms = (squares / Double(samples)).squareRoot()
            return String(format: "%d samples, %d not zero, loudest %.5f, level %.1f dBFS", samples, notZero, peak, rms > 0 ? 20 * log10(rms) : -160)
        }
    }
}
#endif
