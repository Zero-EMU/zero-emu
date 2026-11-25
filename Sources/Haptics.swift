import Foundation
import AVFoundation
import Combine
#if os(iOS)
import UIKit
import CoreHaptics
#endif

/// The parts of the handheld a finger presses, grouped by how each is built,
/// because that decides how it feels (round 16). Each has its own recipe for
/// going down and for coming back up.
enum HapticPart: String, CaseIterable, Sendable {
    /// A, B, X, Y: a hard cap on a rubber dome. A crisp snap as the dome
    /// collapses, a lighter, sharper tick as it springs back.
    case faceButton
    /// The cross: one rocker over four domes. Short and sharp; rolling the
    /// thumb onto another direction clicks again.
    case dpad
    /// L and R: long levers over a tact switch. A deeper, heavier click.
    case shoulder
    /// ZL and ZR: small tact switches. Firm and short.
    case trigger
    /// START, SELECT: soft membrane buttons.
    case smallButton
    /// HOME: a wide membrane key with a firm bottom.
    case homeButton
    /// POWER: a small hard switch.
    case powerButton
    /// Circle Pad and C Stick slide without a click: a faint touch when the
    /// thumb lands, a soft bump at the rim, the spring when it is let go.
    case stickTouch, stickRim, stickReturn
    /// The 3D slider: a notch every 10 %, a firm stop at OFF.
    case sliderNotch, sliderStop
    /// The hinge: detents while folding, the lid shutting, the lid opening.
    case hingeDetent, lidShut, lidOpen
    /// The microphone hole: no switch under it; a soft touch only.
    case micTouch
}

enum HapticPhase: String, Sendable { case press, release }

/// One haptic as plain numbers: transient taps at a time offset (s) with an
/// intensity and a sharpness (0…1, Core Haptics' parameters). Kept apart
/// from Core Haptics so the recipes can be checked anywhere (Tests/Main.swift).
/// The values are starting points: the Simulator has no motor, so they can
/// only be judged and tuned on a device (DEVICE-TEST-PLAN).
struct HapticRecipe: Equatable, Sendable {
    struct Tap: Equatable, Sendable {
        var time: Double
        var intensity: Double
        var sharpness: Double
    }
    var taps: [Tap]

    static func of(_ part: HapticPart, _ phase: HapticPhase) -> HapticRecipe? {
        func r(_ taps: (Double, Double, Double)...) -> HapticRecipe {
            HapticRecipe(taps: taps.map { Tap(time: $0.0, intensity: $0.1, sharpness: $0.2) })
        }
        switch (part, phase) {
        case (.faceButton, .press): return r((0, 0.88, 0.72), (0.008, 0.32, 0.30))
        case (.faceButton, .release): return r((0, 0.40, 0.88))
        case (.dpad, .press): return r((0, 0.76, 0.95))
        case (.dpad, .release): return r((0, 0.28, 1.0))
        case (.shoulder, .press): return r((0, 1.0, 0.36), (0.014, 0.42, 0.12))
        case (.shoulder, .release): return r((0, 0.50, 0.50))
        case (.trigger, .press): return r((0, 0.84, 0.62))
        case (.trigger, .release): return r((0, 0.38, 0.75))
        case (.smallButton, .press): return r((0, 0.50, 0.22))
        case (.smallButton, .release): return r((0, 0.22, 0.32))
        case (.homeButton, .press): return r((0, 0.70, 0.42), (0.010, 0.28, 0.20))
        case (.homeButton, .release): return r((0, 0.32, 0.50))
        case (.powerButton, .press): return r((0, 0.92, 0.58))
        case (.powerButton, .release): return r((0, 0.40, 0.62))
        case (.stickTouch, .press): return r((0, 0.22, 0.18))
        case (.stickRim, .press): return r((0, 0.34, 0.55))
        case (.stickReturn, .press): return r((0, 0.30, 0.25))
        case (.sliderNotch, .press): return r((0, 0.38, 0.90))
        case (.sliderStop, .press): return r((0, 0.85, 0.70))
        case (.hingeDetent, .press): return r((0, 0.60, 0.45))
        case (.lidShut, .press): return r((0, 0.45, 0.25), (0.045, 1.0, 0.42))
        case (.lidOpen, .press): return r((0, 0.75, 0.50))
        case (.micTouch, .press): return r((0, 0.18, 0.10))
        default: return nil
        }
    }
}

/// Plays the recipes on the Taptic Engine through Core Haptics: one engine
/// kept running while a console is on screen, one prepared player per recipe,
/// so a press costs a single `start`. Strength (HOME "震动强度") scales every
/// intensity; the players are rebuilt when it changes. Devices without Core
/// Haptics fall back to UIKit's impact generators; the Simulator has no
/// motor, so nothing is felt there (DEBUG builds can log every event with
/// the launch argument `--foldarc-haptics-log`).
@MainActor final class ConsoleHaptics {
    static let shared = ConsoleHaptics()
    static let strengthKey = "foldarc.hapticStrength"
    static let defaultStrength = 0.8

    #if os(iOS)
    private var engine: CHHapticEngine?
    private var players: [String: CHHapticPatternPlayer] = [:]
    private var builtStrength: Double?
    private var engineRunning = false
    /// 11-07: the engine is being started (off the main thread), and whether
    /// it should stop again once it has (the console went meanwhile).
    private var engineStarting = false
    private var stopWhenStarted = false
    private lazy var supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private lazy var fallbackLight = UIImpactFeedbackGenerator(style: .light)
    private lazy var fallbackRigid = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var fallbackHeavy = UIImpactFeedbackGenerator(style: .heavy)
    #endif
    #if DEBUG
    private let logsEvents = ProcessInfo.processInfo.arguments.contains("--foldarc-haptics-log")
    #endif

    /// The user's strength, 0.2…1.
    var strength: Double {
        let stored = UserDefaults.standard.object(forKey: Self.strengthKey) as? Double ?? Self.defaultStrength
        return min(1, max(0.2, stored))
    }

    /// Start the engine before the first press (a console appeared, the app
    /// came back to the foreground).
    func warmUp() {
        #if os(iOS)
        guard supportsCoreHaptics else { fallbackLight.prepare(); fallbackRigid.prepare(); fallbackHeavy.prepare(); return }
        startEngineIfNeeded()
        #endif
    }

    /// Stop the engine (no console on screen, app in the background).
    func coolDown() {
        #if os(iOS)
        if engineStarting { stopWhenStarted = true; return }
        guard let engine, engineRunning else { return }
        engine.stop(completionHandler: nil)
        engineRunning = false
        #endif
    }

    func play(_ part: HapticPart, _ phase: HapticPhase = .press, enabled: Bool = true) {
        guard enabled, let recipe = HapticRecipe.of(part, phase) else { return }
        #if DEBUG
        if logsEvents { NSLog("[haptics] %@ %@", part.rawValue, phase.rawValue) }
        #endif
        // 11-07: a silent run (DEBUG `--foldarc-silent`) does not buzz either.
        guard !SilentRun.on else { return }
        #if os(iOS)
        if supportsCoreHaptics {
            startEngineIfNeeded()
            if builtStrength != strength { players.removeAll(); builtStrength = strength }
            let key = part.rawValue + "." + phase.rawValue
            if players[key] == nil { players[key] = makePlayer(recipe) }
            do { try players[key]?.start(atTime: CHHapticTimeImmediate) }
            catch {
                // The engine may have stopped under us (audio session
                // interruption): start it again and try once more.
                engineRunning = false
                startEngineIfNeeded()
                try? players[key]?.start(atTime: CHHapticTimeImmediate)
            }
        } else {
            let peak = recipe.taps.map(\.intensity).max() ?? 0
            let sharp = recipe.taps.first?.sharpness ?? 0
            let generator = sharp > 0.6 ? fallbackRigid : (peak > 0.85 ? fallbackHeavy : fallbackLight)
            generator.impactOccurred(intensity: CGFloat(peak * strength))
        }
        #endif
    }

    #if os(iOS)
    private func startEngineIfNeeded() {
        if engine == nil {
            do {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = false
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in self?.engineRunning = false }
                }
                engine.resetHandler = { [weak self] in
                    // The server restarted: players made before are invalid.
                    Task { @MainActor in
                        guard let self else { return }
                        self.players.removeAll(); self.engineRunning = false
                        self.startEngineIfNeeded()
                    }
                }
                self.engine = engine
            } catch {
                supportsCoreHaptics = false
                return
            }
        }
        stopWhenStarted = false
        guard !engineRunning, !engineStarting, let engine else { return }
        // 11-07: started without waiting for it. The synchronous
        // `start()` held the main thread 0.61 s as a game came up on the
        // iPhone Duo (its HangTracer report, 11-06); now the screen goes on
        // and a press in the moment before the engine is up is not felt.
        engineStarting = true
        let began = Date()
        engine.start { [weak self] error in
            let ok = error == nil
            Task { @MainActor in
                guard let self else { return }
                self.engineStarting = false
                self.engineRunning = ok
                NSLog("[haptics] engine %@ in %.0f ms (off the main thread)", ok ? "started" : "did not start", Date().timeIntervalSince(began) * 1000)
                if ok, self.stopWhenStarted {
                    self.stopWhenStarted = false
                    self.coolDown()
                }
            }
        }
    }

    private func makePlayer(_ recipe: HapticRecipe) -> CHHapticPatternPlayer? {
        guard let engine else { return nil }
        let scale = Float(strength)
        let events = recipe.taps.map { tap in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(tap.intensity) * scale),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(tap.sharpness))
            ], relativeTime: tap.time)
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return nil }
        return try? engine.makePlayer(with: pattern)
    }
    #endif
}


// MARK: - The console's volume

/// The volume. Rounds 20-25: the game's own, under the iPhone's, kept across
/// launches like the position of a real slider. Round 26: on the iPhone the console's slider is the iPhone's own volume.
/// An app cannot set the system volume itself (AVAudioSession.outputVolume
/// is read only; MPMusicPlayerController.volume is deprecated since iOS 7);
/// the one public way is the system's own slider (MPVolumeView), which the
/// console's knob now is (SystemVolumeHost). So `level` follows the system
/// volume as SystemAudio hears it, and the game and the console's sounds play
/// at full volume under it. FoldArc's own volume is kept for the Mac preview
/// and the checks, and for the UI tests (`--foldarc-volume-own`), which must
/// not move the Simulator's volume for its owner. (Here since round 21, next
/// to the console's sounds that follow it too.)
///
/// Round 29: where there is no system
/// slider to hold — the Simulator's MPVolumeView has none, and there the
/// knob only showed the system volume, so a finger could not move it — the
/// knob is FoldArc's own volume again (the game's and the console's sounds),
/// moved by a finger like any slider; the iPhone's keys move it too, as in
/// round 23. Where the system's slider is there (a real iPhone) the knob is
/// the iPhone's volume, as in round 26.
@MainActor final class ConsoleVolume: ObservableObject {
    static let shared = ConsoleVolume()
    static let key = "foldarc.volume"
    /// The level is the iPhone's volume (round 26), not FoldArc's own: only
    /// where the system's own slider lies under the knob (round 29).
    let followsSystem: Bool
    @Published var level: Double {
        didSet { if !followsSystem { UserDefaults.standard.set(level, forKey: Self.key) } }
    }
    private init() {
        let system = Self.followsSystemVolume
        followsSystem = system
        #if os(iOS)
        // Until SystemAudio listens: the volume as the session last had it.
        level = system ? Double(AVAudioSession.sharedInstance().outputVolume) : (UserDefaults.standard.object(forKey: Self.key) as? Double ?? 1)
        #else
        level = UserDefaults.standard.object(forKey: Self.key) as? Double ?? 1
        #endif
    }
    /// The iPhone's volume on an iPhone whose system slider is there to
    /// hold (round 29: not the Simulator, which has none) — unless the UI
    /// tests ask for FoldArc's own (DEBUG `--foldarc-volume-own`); the Mac
    /// preview has its own. (A function of its own: worked out in the
    /// initializer, a Release build warned that the own-volume branch would
    /// never run.)
    private static var followsSystemVolume: Bool {
        #if os(iOS)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-volume-own") { return false }
        #endif
        return SystemVolumeSlider.present
        #else
        return false
        #endif
    }
    /// The system volume as heard: the slider shows it (round 26).
    func follow(system value: Float) {
        guard followsSystem else { return }
        let next = (Double(min(1, max(0, value))) * 10_000).rounded() / 10_000
        if next != level { level = next }
    }
    /// The mixer's volume: under the iPhone's own volume, full; FoldArc's own
    /// slider, a curve, as the ear hears loudness (half way is about a
    /// quarter of the power).
    var gain: Float { followsSystem ? 1 : Float(level * level) }
}

// MARK: - The console's sounds

/// What the console says out loud (round 21). FoldArc makes these short
/// tones itself; no recorded or borrowed sound is used.
enum ConsoleSound: String, CaseIterable, Sendable {
    /// The volume slider moved a step (heard at the new volume).
    case tick
    /// The cursor moved on the console's menu; a card turned up on the shelf.
    case move
    /// Something opened.
    case select
    /// Back, closed.
    case back
    /// The card seated in the slot, or let go of its contacts.
    case click
    /// Software starting.
    case launch
    /// The demo: the beacon placed, the ship jumping to it, a star caught.
    case beacon, teleport, star
    /// The camera (round 25): the shutter, the self-timer's beeps (its last
    /// two seconds quicker).
    case shutter, timerTick, timerLast
    /// 11-07 (删除): a card bursting into pixels.
    case crumble
    /// 11-11 (删除方式): a card dropped whole into the floor (a falling
    /// whistle, a knock far down); the scissors (two quick snips).
    case drop, snip
    /// 开箱仪式: the box's paper seal torn; the light out of the open box.
    case rip, chime
    /// 铅笔盒: a turn of a pencil in the sharpener (the blade on the wood); an
    /// elastic strap plucked and let go.
    case sharpen, twang
    /// 11-15, 铅笔盒 shut and opened with the phone (the lid on the cover then,
    /// the box open inside): the tin lid coming down (a clack, a thud, a short
    /// ring of the tin); the latch let go and the pencils shifting in the tray.
    case lidShut, lidOpen
    /// 11-15, 铅笔盒's lid: a magnet put down on it (a print's, a note's, a
    /// postcard's, a plastic letter's) snapping on; a postcard turned over.
    case magnet, cardFlip
    /// 11-17, 铅笔盒's old everyday things, each touched (PencilPlay; the moments are PencilPlayTimes's, as the
    /// movements' are): glass marbles knocking in their jar; a telephone's bell, twice; a tin frog's spring
    /// and its feet coming down; a top whipped and humming; a rubber ball bouncing; a shuttlecock kicked and
    /// its washers landing; a paper windmill's sails; a skipping rope swung, its handles knocking; pencils in
    /// a tin box; a pencil's strokes on paper; a thermos's stopper and its cup; an enamel mug knocked and
    /// rocking; a glass bottle and the fizz in it; a biscuit tin's lid; an exercise book's cover lifted and
    /// let fall; ink going from side to side in its bottle; an abacus's beads.
    case marbles, phoneRing, tinFrog, topSpin, ballBounce, shuttleKick, pinwheel, ropeSwing, tinRattle, scribble
    case corkPop, enamelClang, sodaFizz, tinLid, pageFlip, inkGlug, beads
    /// 11-19, the camera's bodies on the cover, each key sounding as that
    /// kind of machine's does: a metal button's click, a rubber key's dull
    /// knock, a slide switch arriving, one notch of a dial; a keypad
    /// phone's key tones (a telephone's pairs of two tones), its soft keys'
    /// beep and the noise its camera makes for a shutter; an instant
    /// camera's shutter, and its motor pushing the print out.
    case keyMetal, keyRubber, keySlide, keyRatchet
    case phoneTone1, phoneTone2, phoneTone3, phoneTone4, phoneTone5, phoneTone6, phoneTone7, phoneTone8, phoneSoft, phoneShutter
    case instantShutter, instantEject
    /// 11-22, the canvas box's net pocket: the folded note and the eraser in it, touched through the net (the
    /// strings brushing; the paper's crinkle, or the rubber's dull bump; the net springing back).
    case netNote, netEraser
}

/// The console's own sounds (round 21): the menu, the card, the volume
/// slider, the demo. They play as loud as the volume slider says
/// (`ConsoleVolume`), in the session 系统设置 › 声音 sets (AudioPolicy: with
/// or past the silent switch, mixed with other audio), and keep quiet while
/// a game's own sound runs (`gameAudio`). Before round 21 nothing in the library or
/// the demo made a sound, so the volume slider seemed to do nothing there.
@MainActor final class ConsoleSounds {
    static let shared = ConsoleSounds()
    /// A game's sound is on (AzaharSession): the console's sounds wait.
    var gameAudio = false
    private let player = ConsoleSoundPlayer()
    #if DEBUG
    /// `--foldarc-haptics-log` logs the sounds too (`[sound] <name> <gain>`).
    private let log = ProcessInfo.processInfo.arguments.contains("--foldarc-haptics-log")
    #endif

    func play(_ sound: ConsoleSound) {
        play(sound, atLeast: 0)
    }
    /// At least `floor`, whatever the volume slider says: the camera's
    /// shutter is always heard (round 25), so a picture is never taken
    /// unnoticed. The iPhone's own volume and silent switch still apply.
    /// Softer than the volume slider says, by `scale` (a strap plucked a
    /// little twangs a little).
    func play(_ sound: ConsoleSound, scale: Float) {
        let gain = ConsoleVolume.shared.gain * max(0, min(1, scale))
        #if DEBUG
        if log { NSLog("[sound] %@ %.2f%@", sound.rawValue, gain, gameAudio ? " (game audio: skipped)" : "") }
        #endif
        guard !gameAudio, gain > 0.0001, !SilentRun.on else { return }
        player.play(sound, gain: gain)
    }
    func play(_ sound: ConsoleSound, atLeast floor: Float) {
        let gain = max(ConsoleVolume.shared.gain, floor)
        #if DEBUG
        if log { NSLog("[sound] %@ %.2f%@", sound.rawValue, gain, gameAudio ? " (game audio: skipped)" : "") }
        #endif
        guard !gameAudio, gain > 0.0001, !SilentRun.on else { return }
        player.play(sound, gain: gain)
    }
}

/// 11-07: DEBUG
/// `--foldarc-silent`, for test runs nobody is listening to — on the iPhone
/// Duo at night above all. FoldArc makes no sound of its own (not even the
/// shutter's floor, which is there so that a picture is never taken
/// unnoticed), no haptics; the game's sound and the album's videos are
/// muted; the microphone is not used (a video is recorded without sound,
/// MIC does not listen). The `[sound]` and `[haptics]` log lines are still
/// written. A Release build never reads it.
enum SilentRun {
    static let on: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--foldarc-silent")
        #else
        return false
        #endif
    }()
}

/// The engine behind ConsoleSounds. Everything here runs on its own queue:
/// starting an audio engine or activating the session can block.
private final class ConsoleSoundPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FoldArc.sounds", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [ConsoleSound: AVAudioPCMBuffer] = [:]
    /// Counts the sounds played, so a stop scheduled after one can tell
    /// whether another came since.
    private var played = 0

    /// On the iPhone only, as the haptics (the Mac preview and the checks
    /// in Scripts/test.sh stay quiet).
    func play(_ sound: ConsoleSound, gain: Float) {
        #if os(iOS)
        queue.async { self.playNow(sound, gain: gain) }
        #endif
    }
    private func playNow(_ sound: ConsoleSound, gain: Float) {
        guard let engine = readyEngine(), let buffer = buffers[sound], !nodes.isEmpty else { return }
        engine.mainMixerNode.outputVolume = gain
        let node = nodes[next]
        next = (next + 1) % nodes.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        node.play()
        // Stopped after a few quiet seconds (a running engine keeps the
        // audio hardware awake); the next sound starts it again.
        played += 1
        let count = played
        queue.asyncAfter(deadline: .now() + 6) {
            guard self.played == count, let engine = self.engine, engine.isRunning else { return }
            engine.stop()
        }
    }
    /// The engine, made on first use and started again whenever something
    /// (an interruption, the app going to the background) has stopped it.
    private func readyEngine() -> AVAudioEngine? {
        if engine == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return nil }
            let made = AVAudioEngine()
            for _ in 0..<4 {
                let node = AVAudioPlayerNode()
                made.attach(node)
                made.connect(node, to: made.mainMixerNode, format: format)
                nodes.append(node)
            }
            for sound in ConsoleSound.allCases { buffers[sound] = ConsoleSoundSynth.render(sound, format: format) }
            engine = made
        }
        guard let engine else { return nil }
        if !engine.isRunning {
            #if os(iOS)
            // As 系统设置 › 声音 says (AudioPolicy, 11-05; it was always
            // `.ambient`, so the silent switch silenced the console's sounds).
            AudioPolicy.shared.configure("sounds")
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            do { try engine.start() } catch { return nil }
        }
        return engine
    }
}

/// The tones: a few notes each, sine or triangle (or a burst of noise for
/// the card's click), a 3 ms attack and an exponential fall.
enum ConsoleSoundSynth {
    enum Wave { case sine, triangle, noise }
    struct Note {
        var start: Double
        var length: Double
        var from: Double
        var to: Double
        var level: Float
        var wave: Wave = .sine
    }
    static func notes(for sound: ConsoleSound) -> [Note] {
        switch sound {
        case .tick:
            return [Note(start: 0, length: 0.03, from: 1760, to: 1760, level: 0.2)]
        case .move:
            return [Note(start: 0, length: 0.045, from: 1046.5, to: 1046.5, level: 0.14, wave: .triangle)]
        case .select:
            return [Note(start: 0, length: 0.06, from: 784, to: 784, level: 0.16, wave: .triangle),
                    Note(start: 0.05, length: 0.1, from: 1174.7, to: 1174.7, level: 0.16, wave: .triangle)]
        case .back:
            return [Note(start: 0, length: 0.06, from: 987.8, to: 987.8, level: 0.14, wave: .triangle),
                    Note(start: 0.05, length: 0.09, from: 659.3, to: 659.3, level: 0.14, wave: .triangle)]
        case .click:
            return [Note(start: 0, length: 0.012, from: 0, to: 0, level: 0.22, wave: .noise),
                    Note(start: 0, length: 0.06, from: 170, to: 110, level: 0.3)]
        case .launch:
            return [523.25, 659.25, 783.99, 1046.5].enumerated().map { index, frequency in
                Note(start: Double(index) * 0.07, length: index == 3 ? 0.35 : 0.14, from: frequency, to: frequency, level: 0.13, wave: .triangle)
            }
        case .beacon:
            return [Note(start: 0, length: 0.08, from: 1318.5, to: 1318.5, level: 0.13)]
        case .teleport:
            return [Note(start: 0, length: 0.18, from: 330, to: 1320, level: 0.14, wave: .triangle)]
        case .star:
            return [1046.5, 1318.5, 1568].enumerated().map { index, frequency in
                Note(start: Double(index) * 0.06, length: index == 2 ? 0.22 : 0.09, from: frequency, to: frequency, level: 0.13)
            }
        case .shutter:
            // Two clicks, the blade opening and closing, each with a thud
            // of the little body behind it.
            return [Note(start: 0, length: 0.014, from: 0, to: 0, level: 0.5, wave: .noise),
                    Note(start: 0, length: 0.045, from: 900, to: 320, level: 0.12),
                    Note(start: 0.062, length: 0.022, from: 0, to: 0, level: 0.42, wave: .noise),
                    Note(start: 0.062, length: 0.08, from: 260, to: 110, level: 0.28)]
        case .timerTick:
            return [Note(start: 0, length: 0.07, from: 1318.5, to: 1318.5, level: 0.14, wave: .triangle)]
        case .timerLast:
            return [Note(start: 0, length: 0.05, from: 1760, to: 1760, level: 0.14, wave: .triangle),
                    Note(start: 0.1, length: 0.05, from: 1760, to: 1760, level: 0.14, wave: .triangle)]
        case .crumble:
            // A short falling run of blips, like a sprite breaking up, with a
            // soft rush under it.
            return [Note(start: 0, length: 0.045, from: 1500, to: 1100, level: 0.13, wave: .triangle),
                    Note(start: 0.055, length: 0.045, from: 1050, to: 700, level: 0.12, wave: .triangle),
                    Note(start: 0.11, length: 0.05, from: 660, to: 380, level: 0.11, wave: .triangle),
                    Note(start: 0.03, length: 0.16, from: 0, to: 0, level: 0.07, wave: .noise)]
        case .drop:
            return [Note(start: 0.04, length: 0.34, from: 900, to: 240, level: 0.10),
                    Note(start: 0.46, length: 0.02, from: 0, to: 0, level: 0.30, wave: .noise),
                    Note(start: 0.46, length: 0.11, from: 150, to: 75, level: 0.26)]
        case .snip:
            return [Note(start: 0, length: 0.014, from: 0, to: 0, level: 0.30, wave: .noise),
                    Note(start: 0, length: 0.03, from: 2600, to: 1900, level: 0.10, wave: .triangle),
                    Note(start: 0.11, length: 0.014, from: 0, to: 0, level: 0.30, wave: .noise),
                    Note(start: 0.11, length: 0.03, from: 2400, to: 1700, level: 0.10, wave: .triangle)]
        case .rip:
            // Paper parting: a quick ragged run of small bursts, the last one long.
            return [0.0, 0.028, 0.05, 0.081, 0.104, 0.139, 0.162, 0.196].enumerated().map { index, start in
                Note(start: start, length: index == 7 ? 0.09 : 0.018 + 0.006 * Double(index % 3), from: 0, to: 0, level: Float(0.2 - 0.012 * Double(index)), wave: .noise)
            }
        case .chime:
            return [Note(start: 0, length: 0.5, from: 1318.5, to: 1318.5, level: 0.09),
                    Note(start: 0.09, length: 0.55, from: 1975.5, to: 1975.5, level: 0.07),
                    Note(start: 0.18, length: 0.7, from: 2637, to: 2637, level: 0.05)]
        case .sharpen:
            // the blade shaving the wood: a ragged run of small scrapes over a low grind
            return [0.0, 0.026, 0.049, 0.077, 0.101, 0.128, 0.152].enumerated().map { index, start in
                Note(start: start, length: 0.02 + 0.004 * Double(index % 3), from: 0, to: 0, level: Float(0.075 + 0.02 * Double(index % 2)), wave: .noise)
            } + [Note(start: 0, length: 0.19, from: 118, to: 104, level: 0.05, wave: .triangle)]
        case .lidShut:
            // the tin lid down on the box: a sharp clack, the box's low thud, the tin ringing a moment
            return [Note(start: 0, length: 0.012, from: 0, to: 0, level: 0.34, wave: .noise),
                    Note(start: 0, length: 0.09, from: 150, to: 92, level: 0.3),
                    Note(start: 0.002, length: 0.13, from: 2350, to: 2300, level: 0.035, wave: .triangle),
                    Note(start: 0.002, length: 0.1, from: 3420, to: 3380, level: 0.02)]
        case .lidOpen:
            // the latch let go (a small click), then the pencils knocking against each other in the tray
            let latch = [Note(start: 0, length: 0.008, from: 0, to: 0, level: 0.24, wave: .noise),
                         Note(start: 0, length: 0.025, from: 1900, to: 1300, level: 0.06, wave: .triangle)]
            var knocks: [Note] = []
            for (index, start) in [0.075, 0.104, 0.127, 0.161, 0.19].enumerated() {
                let i = Double(index), pitch = 820 + 90 * Double(index % 3)
                knocks.append(Note(start: start, length: 0.007 + 0.002 * Double(index % 2), from: 0, to: 0, level: Float(0.11 - 0.012 * i), wave: .noise))
                knocks.append(Note(start: start, length: 0.035, from: pitch, to: pitch - 60, level: Float(0.05 - 0.006 * i), wave: .triangle))
            }
            return latch + knocks
        case .twang:
            // an elastic band let go: a low wobbling note falling a little, a soft slap at the start
            return [Note(start: 0, length: 0.012, from: 0, to: 0, level: 0.12, wave: .noise),
                    Note(start: 0, length: 0.34, from: 196, to: 150, level: 0.17),
                    Note(start: 0.005, length: 0.24, from: 392, to: 300, level: 0.05, wave: .triangle)]
        case .magnet:
            // pulled the last bit by itself: a hard little tick, a dull knock of the lid, the tin ringing a moment
            return [Note(start: 0, length: 0.006, from: 0, to: 0, level: 0.30, wave: .noise),
                    Note(start: 0, length: 0.028, from: 1250, to: 880, level: 0.07, wave: .triangle),
                    Note(start: 0, length: 0.045, from: 210, to: 150, level: 0.18),
                    Note(start: 0.001, length: 0.08, from: 2900, to: 2860, level: 0.02, wave: .triangle)]
        case .cardFlip:
            // a card turned over: its edge brushing the lid, a soft flick
            return [Note(start: 0, length: 0.05, from: 0, to: 0, level: 0.07, wave: .noise),
                    Note(start: 0.045, length: 0.012, from: 0, to: 0, level: 0.11, wave: .noise),
                    Note(start: 0.045, length: 0.03, from: 520, to: 380, level: 0.05, wave: .triangle)]
        case .keyMetal:
            // a small metal button: its click, the plate under it
            return [Note(start: 0, length: 0.008, from: 0, to: 0, level: 0.30, wave: .noise),
                    Note(start: 0, length: 0.03, from: 2400, to: 1700, level: 0.10, wave: .triangle),
                    Note(start: 0, length: 0.05, from: 320, to: 200, level: 0.14)]
        case .keyRubber:
            // a rubber key going down on its dome: dull, no ring
            return [Note(start: 0, length: 0.01, from: 0, to: 0, level: 0.12, wave: .noise),
                    Note(start: 0, length: 0.07, from: 210, to: 120, level: 0.30)]
        case .keySlide:
            // a slide switch: let go of one end, home at the other
            return [Note(start: 0, length: 0.006, from: 0, to: 0, level: 0.26, wave: .noise),
                    Note(start: 0, length: 0.02, from: 1500, to: 900, level: 0.10, wave: .triangle),
                    Note(start: 0.035, length: 0.01, from: 0, to: 0, level: 0.36, wave: .noise),
                    Note(start: 0.035, length: 0.05, from: 520, to: 260, level: 0.20)]
        case .keyRatchet:
            // one notch of a dial
            return [Note(start: 0, length: 0.005, from: 0, to: 0, level: 0.30, wave: .noise),
                    Note(start: 0, length: 0.018, from: 3200, to: 2300, level: 0.08, wave: .triangle)]
        case .phoneTone1: return pair(697, 1209)
        case .phoneTone2: return pair(697, 1336)
        case .phoneTone3: return pair(697, 1477)
        case .phoneTone4: return pair(770, 1209)
        case .phoneTone5: return pair(770, 1336)
        case .phoneTone6: return pair(770, 1477)
        case .phoneTone7: return pair(852, 1209)
        case .phoneTone8: return pair(852, 1336)
        case .phoneSoft:
            return [Note(start: 0, length: 0.07, from: 1480, to: 1480, level: 0.12, wave: .triangle)]
        case .phoneShutter:
            // what a phone plays for a shutter, thin through its little
            // speaker: two bright clicks, each with a falling chirp
            return [Note(start: 0, length: 0.012, from: 0, to: 0, level: 0.36, wave: .noise),
                    Note(start: 0, length: 0.05, from: 2600, to: 1500, level: 0.13, wave: .triangle),
                    Note(start: 0.09, length: 0.016, from: 0, to: 0, level: 0.40, wave: .noise),
                    Note(start: 0.09, length: 0.09, from: 1900, to: 900, level: 0.14, wave: .triangle)]
        case .instantShutter:
            // a big plastic body: the shutter's clunk, the mirror's knock after it
            return [Note(start: 0, length: 0.016, from: 0, to: 0, level: 0.50, wave: .noise),
                    Note(start: 0, length: 0.09, from: 240, to: 90, level: 0.40),
                    Note(start: 0.05, length: 0.02, from: 0, to: 0, level: 0.30, wave: .noise)]
        case .instantEject:
            // the motor and its gears pushing the sheet out through the
            // rollers: a run of quick teeth over a low hum and the rollers'
            // hiss, a clack as it stops
            var out: [Note] = [Note(start: 0, length: 1.5, from: 0, to: 0, level: 0.035, wave: .noise)]
            for tooth in 0..<64 {
                let at = 0.05 + Double(tooth) * 0.022
                out.append(Note(start: at, length: 0.02, from: 330 + 14 * Double(tooth % 3), to: 290, level: 0.085, wave: .triangle))
                if tooth % 4 == 0 { out.append(Note(start: at, length: 0.07, from: 118, to: 112, level: 0.10)) }
            }
            out.append(Note(start: 1.47, length: 0.012, from: 0, to: 0, level: 0.34, wave: .noise))
            out.append(Note(start: 1.47, length: 0.07, from: 300, to: 150, level: 0.24))
            return out
        case .netNote:
            return [Note(start: 0, length: 0.035, from: 0, to: 0, level: 0.05, wave: .noise),
                    Note(start: 0.012, length: 0.07, from: 0, to: 0, level: 0.035, wave: .noise),
                    Note(start: 0, length: 0.06, from: 170, to: 120, level: 0.10),
                    Note(start: 0.07, length: 0.05, from: 330, to: 290, level: 0.025, wave: .triangle)]
        case .netEraser:
            return [Note(start: 0, length: 0.03, from: 0, to: 0, level: 0.045, wave: .noise),
                    Note(start: 0, length: 0.08, from: 150, to: 95, level: 0.22),
                    Note(start: 0.075, length: 0.05, from: 310, to: 270, level: 0.03, wave: .triangle)]
        case .marbles, .phoneRing, .tinFrog, .topSpin, .ballBounce, .shuttleKick, .pinwheel, .ropeSwing, .tinRattle, .scribble,
             .corkPop, .enamelClang, .sodaFizz, .tinLid, .pageFlip, .inkGlug, .beads:
            return playNotes(for: sound)
        }
    }
    /// A telephone key's tone: two steady tones together.
    private static func pair(_ low: Double, _ high: Double) -> [Note] {
        [Note(start: 0, length: 0.11, from: low, to: low, level: 0.10), Note(start: 0, length: 0.11, from: high, to: high, level: 0.10)]
    }

    /// A short burst of noise (a tick, a knock's edge, a breath).
    private static func hiss(_ start: Double, _ length: Double, _ level: Float) -> Note {
        Note(start: start, length: length, from: 0, to: 0, level: level, wave: .noise)
    }
    /// A tone, steady or sliding.
    private static func tone(_ start: Double, _ length: Double, _ from: Double, _ to: Double, _ level: Float, _ wave: Wave = .sine) -> Note {
        Note(start: start, length: length, from: from, to: to, level: level, wave: wave)
    }

    /// 11-17: the sounds of 铅笔盒's old everyday things (PencilPlay).
    private static func playNotes(for sound: ConsoleSound) -> [Note] {
        typealias T = PencilPlayTimes
        var notes: [Note] = []
        switch sound {
        case .marbles:
            // glass on glass: a clatter as the jar is jolted, then each lot of marbles coming down (and its
            // little bounce); under it the jar itself, struck from inside
            func clack(_ at: Double, _ pitch: Double, _ level: Float) {
                notes.append(hiss(at, 0.004, level * 0.9))
                notes.append(tone(at, 0.03, pitch, pitch * 0.985, level * 0.42))
                notes.append(tone(at, 0.018, pitch * 1.83, pitch * 1.8, level * 0.22))
            }
            let first: [Double] = [5200, 4300, 6100, 4700, 5600]
            for (index, at) in [0.0, 0.022, 0.05, 0.085, 0.13].enumerated() { clack(at, first[index], 0.2 - 0.02 * Float(index)) }
            var index = 0
            for lot in T.marbles {
                for (bounce, hop) in lot.enumerated() {
                    let level = Float(0.24) / Float(1 + bounce * 2) - 0.02 * Float(index % 2)
                    clack(hop.to, 4500 + 480 * Double(index % 4), level)
                    clack(hop.to + 0.016, 5800 - 390 * Double(index % 3), level * 0.6)
                    index += 1
                }
            }
            notes.append(tone(0, 0.22, 1720, 1700, 0.035))
        case .phoneRing:
            // the clapper between two gongs, a little apart in pitch: two bursts, each ringing on a moment
            for ring in T.rings {
                let strikes = Int(((ring.to - ring.from) * T.ringHz).rounded())
                for strike in 0..<strikes {
                    let at = ring.from + Double(strike) / T.ringHz
                    let last = strike == strikes - 1
                    let low = strike % 2 == 0
                    notes.append(hiss(at, 0.003, 0.05))
                    notes.append(tone(at, last ? 0.5 : 0.11, low ? 2064 : 2460, low ? 2064 : 2460, 0.075))
                    notes.append(tone(at, last ? 0.4 : 0.09, low ? 4392 : 5232, low ? 4392 : 5232, 0.04))
                    notes.append(tone(at, last ? 0.3 : 0.07, low ? 6780 : 8076, low ? 6780 : 8076, 0.02))
                }
            }
        case .tinFrog:
            // the spring let go (a run of ratchet clicks), the spring's push at each hop, the tin feet coming down
            for click in 0..<9 {
                let at = 0.005 + Double(click) * 0.03
                notes.append(hiss(at, 0.004, 0.12 - 0.008 * Float(click)))
                notes.append(tone(at, 0.012, 2500 + 60 * Double(click % 3), 2300, 0.05, .triangle))
            }
            for (index, hop) in T.frogHops.enumerated() {
                let level: Float = index == 0 ? 1 : 0.7
                notes.append(tone(hop.from, 0.07, 380, 760, 0.12 * level))
                notes.append(hiss(hop.to, 0.008, 0.26 * level))
                notes.append(tone(hop.to, 0.07, 230, 150, 0.2 * level))
                notes.append(tone(hop.to, 0.09, 1680, 1640, 0.05 * level, .triangle))
                notes.append(tone(hop.to, 0.07, 2950, 2950, 0.025 * level))
            }
        case .topSpin:
            // a flick of the whip; then the top humming on its point, lower as it slows, its point scratching
            notes.append(hiss(0, 0.016, 0.22))
            notes.append(tone(0, 0.05, 1800, 600, 0.06, .triangle))
            notes.append(tone(0.02, 1.25, 168, 118, 0.11, .triangle))
            notes.append(tone(0.02, 1.1, 336, 236, 0.035))
            for turn in 0..<16 { notes.append(hiss(0.05 + Double(turn) * 0.07, 0.02, 0.035 * (1 - Float(turn) / 18))) }
        case .ballBounce:
            // rubber on the lid: a soft thump with a hollow note in it, each time it comes down
            let levels: [Float] = [0.3, 0.3, 0.2, 0.11]
            for (index, at) in T.ball.enumerated() {
                let level = levels[min(index, levels.count - 1)]
                notes.append(hiss(at, 0.006, level * 0.5))
                notes.append(tone(at, 0.1, 230, 140, level))
                notes.append(tone(at, 0.08, 610, 540, level * 0.22, .triangle))
            }
        case .shuttleKick:
            // the foot's knock (the washers jingle); the feathers through the air; the washers down on the lid, twice
            notes.append(hiss(0, 0.014, 0.2))
            notes.append(tone(0, 0.08, 210, 120, 0.26))
            notes.append(tone(0, 0.03, 2700, 2500, 0.04, .triangle))
            notes.append(hiss(0.06, 0.3, 0.022))
            for (index, hop) in T.kick.enumerated() {
                let level: Float = index == 0 ? 1 : 0.45
                notes.append(hiss(hop.to, 0.006, 0.22 * level))
                notes.append(tone(hop.to, 0.09, 2850, 2800, 0.07 * level, .triangle))
                notes.append(tone(hop.to, 0.12, 4300, 4300, 0.035 * level))
                notes.append(tone(hop.to, 0.05, 240, 170, 0.12 * level))
            }
        case .pinwheel:
            // a breath of wind; a flutter of paper each time a sail's edge comes by, quick at first, then slower
            notes.append(hiss(0, 0.3, 0.03))
            let edges = Int(T.wheelTurns * 8)
            for edge in 1..<edges {
                let at = T.wheelMoment(Double(edge) / Double(edges))
                notes.append(hiss(at, 0.022, 0.1 - 0.004 * Float(edge)))
                notes.append(tone(at, 0.03, 300, 220, 0.03, .triangle))
            }
        case .ropeSwing:
            // the rope through the air and its slap on the ground, twice; then the wooden handles knocking
            for at in T.rope {
                notes.append(hiss(at, 0.13, 0.05))
                notes.append(tone(at, 0.12, 380, 820, 0.03))
                notes.append(hiss(at + 0.12, 0.008, 0.16))
                notes.append(tone(at + 0.12, 0.05, 180, 110, 0.14))
            }
            for (index, at) in T.ropeHandles.enumerated() {
                notes.append(hiss(at, 0.004, 0.14))
                notes.append(tone(at, 0.03, 1150, 980, 0.09 - 0.02 * Float(index), .triangle))
                notes.append(tone(at, 0.04, 420, 380, 0.06))
            }
        case .tinRattle:
            // pencils knocking about in a shut tin, the tin ringing a little
            for (index, at) in T.rattle.enumerated() {
                let pitch = 820 + 110 * Double(index % 3)
                notes.append(hiss(at, 0.006, 0.15 - 0.012 * Float(index)))
                notes.append(tone(at, 0.035, pitch, pitch - 70, 0.06 - 0.005 * Float(index), .triangle))
            }
            notes.append(tone(0, 0.2, 2380, 2340, 0.03, .triangle))
            notes.append(tone(0.09, 0.16, 3400, 3400, 0.016))
        case .scribble:
            // the lead on the paper: a stroke each way
            let strokes = Int(0.56 * T.scribbleHz * 2)
            for stroke in 0..<strokes {
                notes.append(hiss(Double(stroke) / (T.scribbleHz * 2), 0.05 + 0.01 * Double(stroke % 2), 0.06 + 0.02 * Float(stroke % 2)))
            }
            notes.append(tone(0, 0.5, 240, 210, 0.012, .triangle))
        case .corkPop:
            // the stopper out (a pop, the hollow flask sounding under it); the aluminium cup down again, twice
            notes.append(hiss(0, 0.006, 0.2))
            notes.append(tone(0, 0.045, 340, 980, 0.22))
            notes.append(tone(0.01, 0.22, 205, 190, 0.09))
            for (index, hop) in T.cup.enumerated() {
                let level: Float = index == 0 ? 1 : 0.5
                notes.append(hiss(hop.to, 0.003, 0.08 * level))
                notes.append(tone(hop.to, index == 0 ? 0.16 : 0.1, 2380, 2380, 0.06 * level))
                notes.append(tone(hop.to, 0.1, 3920, 3920, 0.03 * level))
            }
        case .enamelClang:
            // enamel on steel, rung; then its foot knocking on the lid each time it rocks back
            notes.append(hiss(0, 0.006, 0.22))
            notes.append(tone(0, 0.55, 1176, 1170, 0.12))
            notes.append(tone(0, 0.4, 2470, 2470, 0.06))
            notes.append(tone(0, 0.25, 3890, 3890, 0.03))
            notes.append(tone(0, 0.08, 300, 220, 0.1))
            for knock in 1...4 {
                let at = Double(knock) / (2 * T.mugHz)
                notes.append(hiss(at, 0.005, 0.1 - 0.02 * Float(knock)))
                notes.append(tone(at, 0.04, 190, 140, 0.12 - 0.025 * Float(knock)))
            }
        case .sodaFizz:
            // the glass knocked; the fizz rising, bubbles breaking at the top
            notes.append(hiss(0, 0.004, 0.14))
            notes.append(tone(0, 0.16, 2140, 2140, 0.06))
            notes.append(tone(0, 0.12, 3460, 3460, 0.03))
            notes.append(hiss(0.05, 0.8, 0.045))
            for (index, at) in [0.16, 0.23, 0.27, 0.36, 0.41, 0.5, 0.58, 0.69].enumerated() {
                let pitch = 2600 + 320 * Double((index * 5) % 7)
                notes.append(tone(at, 0.012, pitch, pitch + 400, 0.035))
            }
        case .tinLid:
            // the lid let go; then down on the tin: a clang, the box's thud, and once more, smaller
            notes.append(hiss(0, 0.006, 0.14))
            notes.append(tone(0, 0.05, 430, 560, 0.08, .triangle))
            for (index, hop) in T.tinLid.enumerated() {
                let level: Float = index == 0 ? 1 : 0.5
                notes.append(hiss(hop.to, 0.01, 0.3 * level))
                notes.append(tone(hop.to, 0.2, 648, 610, 0.11 * level, .triangle))
                notes.append(tone(hop.to, 0.24, 1530, 1530, 0.05 * level))
                notes.append(tone(hop.to, 0.2, 2290, 2290, 0.03 * level))
                notes.append(tone(hop.to, 0.06, 170, 110, 0.16 * level))
            }
        case .pageFlip:
            // the cover lifted (paper bending), and let fall on the pages
            notes.append(hiss(0, 0.1, 0.05))
            notes.append(hiss(0.06, 0.12, 0.07))
            notes.append(hiss(T.cover.shut - 0.01, 0.012, 0.14))
            notes.append(tone(T.cover.shut - 0.01, 0.06, 260, 170, 0.1))
        case .inkGlug:
            // the glass knocked; the ink going over, a gulp each half sway, smaller each time
            notes.append(hiss(0, 0.005, 0.16))
            notes.append(tone(0, 0.09, 880, 850, 0.1))
            notes.append(tone(0, 0.12, 2320, 2320, 0.03))
            for gulp in 0..<3 {
                let at = (Double(gulp) + 0.9) / (2 * T.inkHz)
                let small = Double(gulp)
                notes.append(tone(at, 0.07, 290 - 20 * small, 520 - 40 * small, 0.15 - 0.04 * Float(gulp)))
                notes.append(tone(at + 0.07, 0.05, 180, 150, 0.05))
            }
        case .beads:
            // wooden beads knocking on each other and on the beam
            for (index, at) in T.beads.enumerated() {
                let pitch = 1350 + 170 * Double((index * 3) % 5)
                notes.append(hiss(at, 0.004, 0.14 - 0.008 * Float(index)))
                notes.append(tone(at, 0.02, pitch, pitch * 0.93, 0.09 - 0.005 * Float(index), .triangle))
                notes.append(tone(at, 0.03, pitch * 0.5, pitch * 0.5, 0.03))
            }
        default:
            break
        }
        return notes
    }
    static func render(_ sound: ConsoleSound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes = notes(for: sound)
        let rate = format.sampleRate
        let total = (notes.map { $0.start + $0.length }.max() ?? 0) + 0.01
        let frames = AVAudioFrameCount(total * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let count = Int(frames)
        for i in 0..<count { out[i] = 0 }
        var seed: UInt32 = 0x2545_F491
        for note in notes {
            let first = Int(note.start * rate)
            let samples = Int(note.length * rate)
            var phase = 0.0
            for j in 0..<samples where first + j < count {
                let t = Double(j) / rate
                let progress = t / note.length
                phase += (note.from + (note.to - note.from) * progress) / rate
                let envelope = Float(min(1, t / 0.003) * exp(-4.5 * progress))
                let value: Float
                switch note.wave {
                case .sine:
                    value = Float(sin(2 * .pi * phase))
                case .triangle:
                    let p = phase - phase.rounded(.down)
                    value = Float(4 * abs(p - 0.5) - 1)
                case .noise:
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    value = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                }
                out[first + j] += value * envelope * note.level
            }
        }
        for i in 0..<count { out[i] = max(-1, min(1, out[i])) }
        return buffer
    }
}
