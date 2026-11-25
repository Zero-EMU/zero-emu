import SwiftUI
import Combine
#if os(iOS)
import UIKit
import AVFoundation
#endif

// 画框 (the picture frame): a program of the console's menu, free for
// everyone. The upper screen is a scenery that keeps moving — drawn from
// nothing every frame, as the cartridges' films are — and its light
// follows the hour of the iPhone's clock. The lower screen is dim: the
// clock, the sceneries to choose from, a few switches. The iPhone does not
// go to sleep while the frame is up (unless asked to after a while), the
// lower screen dims when nobody touches it, and the picture drifts by a
// point or two over minutes so that nothing stands still on the display.
// The scenery has its sounds: loops that play as loud as the hour makes
// each (PictureFrameSound).
//
// The first scenery is 篝火旁的存档点: a clearing in the pines, a tent, a
// fire, a lantern on a forked stick and an old alarm clock on a log, drawn
// by hand in coloured pencil. What does not move is three pictures, one for
// each light (CampfireKept), and only the flames, the sparks, the lantern's
// flame, the clock's hands, the stars and the fireflies are drawn again each
// frame. The second, 黄昏小镇的屋顶, is drawn the same way in
// PictureFrameRoofs.swift, the third, 下雨的电车站, in PictureFrameTram.swift,
// the fourth, 云上的飞艇, in PictureFrameAirship.swift.

// MARK: - Names and settings

extension FrameScene {
    var title: String {
        switch self {
        case .campfire: return String(localized: "篝火旁的存档点")
        case .roofs: return String(localized: "黄昏小镇的屋顶")
        case .tramStop: return String(localized: "下雨的电车站")
        case .airship: return String(localized: "云上的飞艇")
        }
    }
}

/// What the frame keeps between visits.
@MainActor final class PictureFrameSettings: ObservableObject {
    static let shared = PictureFrameSettings()
    private static let sceneKey = "FoldArc.frame.scene", clockKey = "FoldArc.frame.followsClock", sleepKey = "FoldArc.frame.sleepMinutes"
    private static let soundKey = "FoldArc.frame.sound"
    @Published var scene: FrameScene { didSet { UserDefaults.standard.set(scene.rawValue, forKey: Self.sceneKey) } }
    /// 声音: the scenery's own sounds.
    @Published var sound: Bool { didSet { UserDefaults.standard.set(sound, forKey: Self.soundKey) } }
    /// 早晚的光跟着手机的时间 (off: the scenery stays at its night).
    @Published var followsClock: Bool { didSet { UserDefaults.standard.set(followsClock, forKey: Self.clockKey) } }
    /// 多久以后熄屏 (0: never).
    @Published var sleepMinutes: Int { didSet { UserDefaults.standard.set(sleepMinutes, forKey: Self.sleepKey) } }

    private init() {
        let defaults = UserDefaults.standard
        let stored = FrameScene(rawValue: defaults.string(forKey: Self.sceneKey) ?? "") ?? .campfire
        scene = stored.isReady ? stored : .campfire
        sound = defaults.object(forKey: Self.soundKey) == nil ? true : defaults.bool(forKey: Self.soundKey)
        followsClock = defaults.object(forKey: Self.clockKey) == nil ? true : defaults.bool(forKey: Self.clockKey)
        let minutes = defaults.integer(forKey: Self.sleepKey)
        sleepMinutes = FrameSleep.choices.contains(minutes) ? minutes : 0
    }
    /// The next scenery that is drawn (`delta` +1 on, -1 back), going round.
    func step(_ delta: Int) {
        let all = FrameScene.allCases.filter(\.isReady)
        guard let at = all.firstIndex(of: scene), !all.isEmpty else { return }
        scene = all[((at + delta) % all.count + all.count) % all.count]
    }
    /// The scenery's light at `date`.
    func light(at date: Date) -> Double {
        guard followsClock else { return 0 }
        return FrameLight.level(hour: Self.fixedHour ?? FrameLight.hour(of: date))
    }
    /// The hour of the clock at `date` with its minutes: what a clock in a
    /// scenery shows (whether or not the light follows the clock).
    func hour(at date: Date) -> Double { Self.fixedHour ?? FrameLight.hour(of: date) }
    /// A debug build's `--foldarc-frame-hour=<0 ..< 24>`: the hour the
    /// frame's light is drawn for, whatever the clock says (the tests').
    static let fixedHour: Double? = {
        #if DEBUG
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--foldarc-frame-hour=") {
            return Double(argument.dropFirst("--foldarc-frame-hour=".count))
        }
        #endif
        return nil
    }()
    var sleepTitle: String { Self.sleepTitle(sleepMinutes) }
    static func sleepTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: return String(localized: "一直亮")
        case 60: return String(localized: "1 小时")
        default: return String(localized: "\(minutes) 分钟")
        }
    }
}

/// The frame while it is up: since when, whether it has gone dark, whether
/// the lower screen has dimmed. The iPhone is kept awake while it shows.
@MainActor final class PictureFrameRun: ObservableObject {
    static let shared = PictureFrameRun()
    /// 熄屏: both screens black until something is touched.
    @Published private(set) var asleep = false
    /// Nobody has touched it for a while: the lower screen is fainter.
    @Published private(set) var dimmed = false
    private(set) var opened = Date()
    private(set) var lastActive = Date()
    private var showing = 0
    /// A debug build's `--foldarc-frame-fast`: the frame's waits are short
    /// (dim after three seconds, a minute of 熄屏 is a second), for the tests.
    static let fast: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--foldarc-frame-fast")
        #else
        return false
        #endif
    }()
    /// The lower screen dims after this long untouched (seconds).
    static let dimAfter = fast ? 3.0 : 20.0

    /// Whether it keeps the iPhone awake while it shows (standing on the
    /// cover on the battery it does not: the iPhone locks as it would).
    private var holdsAwake = true
    func appear(holdsAwake: Bool = true) {
        showing += 1
        guard showing == 1 else { return }
        opened = Date()
        lastActive = opened
        asleep = false
        dimmed = false
        self.holdsAwake = holdsAwake
        keepAwake(holdsAwake)
        NSLog(holdsAwake ? "[frame] up: the iPhone stays awake" : "[frame] up: the iPhone may lock (on the battery)")
    }
    /// Plugged in or taken off while it stands.
    func holdAwake(_ on: Bool) {
        guard showing > 0, on != holdsAwake else { return }
        holdsAwake = on
        if !asleep { keepAwake(on) }
        NSLog("[frame] %@", on ? "plugged in: the iPhone stays awake" : "on the battery: the iPhone may lock")
    }
    func disappear() {
        showing = max(0, showing - 1)
        guard showing == 0 else { return }
        keepAwake(false)
        if asleep { asleep = false }
        NSLog("[frame] down")
    }
    /// A finger or a key: lit again.
    func touch() {
        lastActive = Date()
        if dimmed { dimmed = false }
        if asleep {
            asleep = false
            keepAwake(showing > 0 && holdsAwake)
            NSLog("[frame] awake again")
        }
    }
    /// Once a second while the frame shows.
    func tick(_ now: Date, sleepMinutes: Int) {
        let idle = now.timeIntervalSince(lastActive)
        if !dimmed, idle >= Self.dimAfter { dimmed = true }
        if !asleep, FrameSleep.isDue(minutes: sleepMinutes, idle: idle, minute: Self.fast ? 1 : 60) {
            asleep = true
            keepAwake(false)
            NSLog("[frame] dark after %d minutes untouched", sleepMinutes)
        }
    }
    /// Seconds the scenery has been moving.
    func seconds(at date: Date) -> Double { max(0, date.timeIntervalSince(opened)) }
    /// The frame is on a screen somewhere.
    var isUp: Bool { showing > 0 }
    private func keepAwake(_ on: Bool) { ScreenAwake.set("frame", on) }
}

// MARK: - The scenery's sound

/// 画框's sound: the scenery's loops — what is heard in it all day (the
/// campfire's fire, the wind over the roofs), what by night, what by day —
/// each as loud as the hour makes it (FrameSoundLayer); now and then one of
/// its single sounds (FrameMoment: a crack of the fire, an owl, a chime, a
/// gust), as loud as its layer; the tram stop's thunder and tram on the
/// scenery's clock (FrameCue); and over the roofs, the tower's bell on the
/// hour by day (FrameBell). A loop's file holds half a second of the loop's
/// end before it and of its start after it, so that wherever a decoder
/// begins counting, what is read from half a second in is one whole turn.
/// Everything here runs on its own queue: reading the files and starting an
/// engine can block.
final class PictureFrameSound: @unchecked Sendable {
    static let shared = PictureFrameSound()
    /// Each loop's length (seconds).
    static func seconds(_ layer: FrameSoundLayer, in scene: FrameScene) -> Double {
        switch (scene, layer) {
        case (.campfire, .always): return 48
        case (.campfire, .night): return 40
        case (.campfire, .day): return 44
        case (.roofs, .always): return 52
        case (.roofs, .night): return 44
        case (.roofs, .day): return 46
        case (.tramStop, .always): return 50
        case (.tramStop, .night): return 42
        case (.tramStop, .day): return 46
        case (.airship, .always): return 50
        case (.airship, .night): return 40
        case (.airship, .day): return 44
        }
    }
    /// Seconds between the bell's strokes.
    static let strokeApart = 2.4
    /// A debug build's `--foldarc-frame-sound-dry`: in a silent run the
    /// loops are read and played all the same, with the volume at nothing
    /// (the tests': the files and the engine are tried, nothing is heard).
    static let dry: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--foldarc-frame-sound-dry")
        #else
        return false
        #endif
    }()
    private let queue = DispatchQueue(label: "FoldArc.frame.sound", qos: .utility)
    #if os(iOS)
    private var engine: AVAudioEngine?
    private var nodes: [FrameSoundLayer: AVAudioPlayerNode] = [:]
    private var buffers: [FrameSoundLayer: AVAudioPCMBuffer] = [:]
    private var loaded: FrameScene?
    private var sounding = false
    private var master: Float = 0
    private var rampCount = 0
    /// The tower's bell (over the roofs): its one stroke, and the hour it last rang for.
    private var bell: AVAudioPlayerNode?
    private var bellStroke: AVAudioPCMBuffer?
    private var lastChime = -1
    /// What the scenery plays at its moments (FrameCue), each read whole,
    /// and where on its clock the last look was.
    private var cueNodes: [FrameCue: AVAudioPlayerNode] = [:]
    private var cueSounds: [FrameCue: AVAudioPCMBuffer] = [:]
    private var lastCueSeconds: Double?
    /// The scenery's single sounds (FrameMoment): a player for each, and
    /// its variants read out of the scenery's file.
    private var momentNodes: [FrameMoment: AVAudioPlayerNode] = [:]
    private var momentSounds: [FrameMoment: [AVAudioPCMBuffer]] = [:]
    /// The light the loops were last set for (the single sounds follow it).
    private var light = 0.0
    #endif

    /// What should be heard now: `scene` nil for nothing; `gain` the
    /// console's volume; `muted`: played with the volume at nothing.
    func update(scene: FrameScene?, light: Double, gain: Float, muted: Bool = false) {
        #if os(iOS)
        queue.async { self.apply(scene: scene, light: light, gain: muted ? 0 : gain, muted: muted) }
        #endif
    }
    /// The tower's bell, if the scenery has one and it is time: on the hour
    /// (within its first ten seconds), as many strokes as the hour, by day.
    func chime(scene: FrameScene?, at date: Date, calendar: Calendar = .current) {
        #if os(iOS)
        guard let scene, FrameBell.rings(in: scene) else { return }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard parts.minute == 0, (parts.second ?? 60) < 10 else { return }
        let strokes = FrameBell.strokes(hour: parts.hour ?? 0)
        let hourIndex = Int((date.timeIntervalSince1970 / 3600).rounded(.down))
        queue.async { self.ring(strokes, hourIndex: hourIndex) }
        #endif
    }
    /// The scenery's own moments (FrameCue): what has come on its clock
    /// since the last look is played (once a second; a moment missed by more
    /// than two seconds is let go).
    func cue(scene: FrameScene?, seconds: Double) {
        #if os(iOS)
        queue.async { self.play(scene: scene, seconds: seconds) }
        #endif
    }

    #if os(iOS)
    private func apply(scene: FrameScene?, light: Double, gain: Float, muted: Bool) {
        guard let scene, gain > 0.0001 || muted else { quiet(); return }
        self.light = light
        guard prepare(scene), let engine else { return }
        if !engine.isRunning {
            AudioPolicy.shared.configure("frame")
            try? AVAudioSession.sharedInstance().setActive(true)
            do { try engine.start() } catch {
                NSLog("[frame] sound: the engine did not start: %@", "\(error)")
                return
            }
            sounding = false
        }
        for (layer, node) in nodes {
            node.volume = Float(layer.level(light: light, in: scene))
            if !sounding, let buffer = buffers[layer] {
                node.stop()
                node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                node.play()
            }
        }
        if !sounding {
            sounding = true
            master = 0
            engine.mainMixerNode.outputVolume = 0
            NSLog("[frame] sound: %@ playing (%@)%@", scene.rawValue, nodes.keys.map(\.rawValue).sorted().joined(separator: ", "), muted ? ", muted" : "")
        }
        ramp(to: gain, then: nil)
    }
    /// Nothing is to be heard: down over half a second, then everything let go.
    private func quiet() {
        guard sounding else { return }
        sounding = false
        ramp(to: 0) { [weak self] in
            guard let self, !self.sounding else { return }
            for node in self.nodes.values { node.stop() }
            self.bell?.stop()
            self.engine?.stop()
            self.engine = nil
            self.nodes = [:]
            self.buffers = [:]
            self.bell = nil
            self.bellStroke = nil
            for node in self.cueNodes.values { node.stop() }
            self.cueNodes = [:]
            self.cueSounds = [:]
            self.lastCueSeconds = nil
            for node in self.momentNodes.values { node.stop() }
            self.momentNodes = [:]
            self.momentSounds = [:]
            self.loaded = nil
            NSLog("[frame] sound: stopped")
        }
    }
    /// The whole sound's volume to `target` in a few steps (no click).
    private func ramp(to target: Float, then done: (() -> Void)?) {
        rampCount += 1
        let count = rampCount, from = master
        guard abs(from - target) > 0.001 else { done?(); return }
        let steps = 8
        for step in 1...steps {
            queue.asyncAfter(deadline: .now() + .milliseconds(step * 70)) {
                guard self.rampCount == count else { return }
                let value = from + (target - from) * Float(step) / Float(steps)
                self.master = value
                self.engine?.mainMixerNode.outputVolume = value
                if step == steps { done?() }
            }
        }
    }
    /// The engine with the scenery's loops read into memory (again when the
    /// scenery is another). False when the scenery has no sound.
    private func prepare(_ scene: FrameScene) -> Bool {
        if loaded == scene, engine != nil { return !buffers.isEmpty }
        var read: [FrameSoundLayer: AVAudioPCMBuffer] = [:]
        for layer in FrameSoundLayer.layers(in: scene) {
            guard let url = Bundle.main.url(forResource: layer.file(in: scene), withExtension: "m4a"),
                  let buffer = Self.loop(at: url, seconds: Self.seconds(layer, in: scene)) else { continue }
            read[layer] = buffer
        }
        engine?.stop()
        engine = nil
        nodes = [:]
        bell = nil
        bellStroke = nil
        cueNodes = [:]
        cueSounds = [:]
        lastCueSeconds = nil
        momentNodes = [:]
        momentSounds = [:]
        buffers = read
        loaded = scene
        sounding = false
        master = 0
        guard !read.isEmpty else {
            NSLog("[frame] sound: %@ has no loops in the app", scene.rawValue)
            return false
        }
        let made = AVAudioEngine()
        for (layer, buffer) in read {
            let node = AVAudioPlayerNode()
            made.attach(node)
            made.connect(node, to: made.mainMixerNode, format: buffer.format)
            nodes[layer] = node
        }
        if FrameBell.rings(in: scene), let url = Bundle.main.url(forResource: FrameBell.file, withExtension: "m4a"), let stroke = Self.whole(at: url) {
            let node = AVAudioPlayerNode()
            made.attach(node)
            made.connect(node, to: made.mainMixerNode, format: stroke.format)
            bell = node
            bellStroke = stroke
        }
        for cue in FrameCue.cues(in: scene) {
            guard let url = Bundle.main.url(forResource: cue.file, withExtension: "m4a"), let sound = Self.whole(at: url) else { continue }
            let node = AVAudioPlayerNode()
            made.attach(node)
            made.connect(node, to: made.mainMixerNode, format: sound.format)
            cueNodes[cue] = node
            cueSounds[cue] = sound
        }
        let moments = FrameMoment.moments(in: scene)
        if !moments.isEmpty, let url = Bundle.main.url(forResource: FrameMoment.file(in: scene), withExtension: "m4a"), let all = Self.whole(at: url) {
            for moment in moments {
                let pieces = (0..<moment.variants).compactMap { Self.slice(all, from: moment.start(variant: $0), seconds: moment.slot) }
                guard pieces.count == moment.variants else { continue }
                let node = AVAudioPlayerNode()
                made.attach(node)
                made.connect(node, to: made.mainMixerNode, format: all.format)
                momentNodes[moment] = node
                momentSounds[moment] = pieces
            }
            NSLog("[frame] sound: %@ single sounds ready (%@)", scene.rawValue, momentNodes.keys.map(\.rawValue).sorted().joined(separator: ", "))
        }
        made.mainMixerNode.outputVolume = 0
        engine = made
        return true
    }
    private func play(scene: FrameScene?, seconds: Double) {
        guard let scene, loaded == scene, sounding, let engine, engine.isRunning else { lastCueSeconds = nil; return }
        defer { lastCueSeconds = seconds }
        guard let last = lastCueSeconds, seconds > last, seconds - last < 5 else { return }
        for cue in FrameCue.cues(in: scene) {
            guard let ago = cue.began(after: last, upTo: seconds), ago < 2, let node = cueNodes[cue], let sound = cueSounds[cue] else { continue }
            node.scheduleBuffer(sound, at: nil, options: [], completionHandler: nil)
            if !node.isPlaying { node.play() }
            NSLog("[frame] sound: the %@", cue.rawValue)
        }
        for moment in FrameMoment.moments(in: scene) {
            guard let hit = moment.began(after: last, upTo: seconds), hit.ago < 2,
                  let node = momentNodes[moment], let sounds = momentSounds[moment], hit.variant < sounds.count else { continue }
            let loud = Float(moment.layer.level(light: light, in: scene))
            guard loud > 0.001 else { continue }
            node.volume = loud
            node.scheduleBuffer(sounds[hit.variant], at: nil, options: [], completionHandler: nil)
            if !node.isPlaying { node.play() }
        }
    }
    private func ring(_ strokes: Int, hourIndex: Int) {
        guard hourIndex != lastChime else { return }
        lastChime = hourIndex
        guard strokes > 0, sounding, let engine, engine.isRunning, let bell, let stroke = bellStroke,
              let rung = Self.peal(stroke, strokes: strokes, apart: Self.strokeApart) else { return }
        bell.scheduleBuffer(rung, at: nil, options: [], completionHandler: nil)
        if !bell.isPlaying { bell.play() }
        NSLog("[frame] sound: the bell, %d strokes", strokes)
    }
    /// A whole file read into memory (the bell's stroke).
    private static func whole(at url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let count = AVAudioFrameCount(file.length)
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return nil }
        do { try file.read(into: buffer, frameCount: count) } catch {
            NSLog("[frame] sound: %@ not read: %@", url.lastPathComponent, "\(error)")
            return nil
        }
        return buffer.frameLength > 0 ? buffer : nil
    }
    /// `seconds` of a buffer from `from` seconds in (a variant of a single sound).
    private static func slice(_ all: AVAudioPCMBuffer, from: Double, seconds: Double) -> AVAudioPCMBuffer? {
        let rate = all.format.sampleRate
        let start = Int((from * rate).rounded()), total = Int(all.frameLength)
        let count = min(Int((seconds * rate).rounded()), total - start)
        guard start >= 0, count > 0, let out = AVAudioPCMBuffer(pcmFormat: all.format, frameCapacity: AVAudioFrameCount(count)),
              let source = all.floatChannelData, let target = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        for channel in 0..<Int(all.format.channelCount) {
            let into = target[channel], piece = source[channel]
            for i in 0..<count { into[i] = piece[start + i] }
        }
        return out
    }
    /// `strokes` strokes of the bell, `apart` seconds from one to the next,
    /// each ringing on under the ones after it.
    private static func peal(_ stroke: AVAudioPCMBuffer, strokes: Int, apart: Double) -> AVAudioPCMBuffer? {
        let format = stroke.format
        let gap = Int((apart * format.sampleRate).rounded())
        let length = Int(stroke.frameLength)
        let total = length + gap * max(0, strokes - 1)
        guard strokes > 0, total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let source = stroke.floatChannelData, let target = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(total)
        for channel in 0..<Int(format.channelCount) {
            let into = target[channel], from = source[channel]
            for i in 0..<total { into[i] = 0 }
            for k in 0..<strokes {
                let start = k * gap
                let loud: Float = k == strokes - 1 ? 1 : 0.9
                for i in 0..<min(length, total - start) { into[start + i] += from[i] * loud }
            }
        }
        return out
    }
    /// One whole turn of a loop out of its file.
    private static func loop(at url: URL, seconds: Double) -> AVAudioPCMBuffer? {
        guard seconds > 0, let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let start = AVAudioFramePosition((0.5 * format.sampleRate).rounded())
        let left = file.length - start
        guard left > 0 else { return nil }
        let wanted = AVAudioFramePosition((seconds * format.sampleRate).rounded())
        let count = AVAudioFrameCount(min(wanted, left))
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return nil }
        file.framePosition = start
        do { try file.read(into: buffer, frameCount: count) } catch {
            NSLog("[frame] sound: %@ not read: %@", url.lastPathComponent, "\(error)")
            return nil
        }
        if buffer.frameLength != count { NSLog("[frame] sound: %@ gave %d of %d frames", url.lastPathComponent, Int(buffer.frameLength), Int(count)) }
        return buffer.frameLength > 0 ? buffer : nil
    }
    #endif
}

// MARK: - Numbers and colours

/// The same numbers for the same seed, every time: the scenery is made of them.
struct FrameRandom {
    private var state: UInt32
    init(_ seed: UInt32) { state = seed }
    /// 0 ..< 1.
    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296.0
    }
}

/// Smooth noise along a line: 512 numbers, eased from one to the next.
struct FrameNoise {
    private let values: [Double]
    init(_ seed: UInt32) {
        var random = FrameRandom(seed)
        var made: [Double] = []
        made.reserveCapacity(512)
        for _ in 0..<512 { made.append(random.next()) }
        values = made
    }
    func at(_ x: Double) -> Double {
        let whole = x.rounded(.down)
        let f = x - whole
        let u = f * f * (3 - 2 * f)
        let i = Int(whole)
        let a = values[((i % 512) + 512) % 512]
        let b = values[(((i + 1) % 512) + 512) % 512]
        return a + (b - a) * u
    }
    /// Several octaves of it.
    func fbm(_ x: Double, _ octaves: Int) -> Double {
        var sum = 0.0, amplitude = 0.5, frequency = 1.0, total = 0.0
        for i in 0..<octaves {
            sum += amplitude * at(x * frequency + Double(i) * 17.3)
            total += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / total
    }
}

/// A colour as three numbers 0 ... 255, to mix.
struct FrameRGB {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    func mixed(_ other: FrameRGB, _ t: Double) -> FrameRGB {
        FrameRGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
    /// Toward `warm` by `k` (0 ... 1): what the fire's light does to a thing.
    func lit(_ warm: FrameRGB, _ k: Double) -> FrameRGB { mixed(warm, min(1, max(0, k))) }
    /// A thing's own colour in daylight (`k`: how much of the day there is):
    /// brighter, a little warmer.
    func sunlit(_ k: Double) -> FrameRGB {
        mixed(FrameRGB(min(255, r * 2.0 + 16), min(255, g * 1.9 + 14), min(255, b * 1.6 + 10)), min(1, max(0, k)))
    }
    func color(_ alpha: Double = 1) -> Color {
        Color(.sRGB, red: min(1, max(0, r / 255)), green: min(1, max(0, g / 255)), blue: min(1, max(0, b / 255)), opacity: min(1, max(0, alpha)))
    }
}

func frameLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func frameClamp(_ x: Double, _ low: Double, _ high: Double) -> Double { max(low, min(high, x)) }

/// The pen the sceneries are drawn with: a canvas whose units are the
/// sheet's (1000 across, 600 down).
extension FramePen {
    /// A scenery clock's two hands at (x, y) on a face `r` from its middle to
    /// its rim: the hour hand half of it and thicker, the minute hand four fifths.
    func clockHands(_ x: Double, _ y: Double, _ r: Double, hour: Double, _ c: FrameRGB, width: Double) {
        let a = FrameClock.hands(hour: hour)
        line([(x, y), (x + sin(a.hour) * r * 0.52, y - cos(a.hour) * r * 0.52)], c, 0.95, width: width * 1.5)
        line([(x, y), (x + sin(a.minute) * r * 0.8, y - cos(a.minute) * r * 0.8)], c, 0.95, width: width)
        oval(x, y, width * 0.9, width * 0.9, c)
    }
}

struct FramePen {
    var g: GraphicsContext
    func fill(_ path: Path, _ c: FrameRGB, _ alpha: Double = 1) { g.fill(path, with: .color(c.color(alpha))) }
    func stroke(_ path: Path, _ c: FrameRGB, _ alpha: Double = 1, width: Double, dash: [CGFloat] = []) {
        g.stroke(path, with: .color(c.color(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }
    func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ c: FrameRGB, _ alpha: Double = 1) {
        guard rx > 0, ry > 0, alpha > 0.002 else { return }
        g.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), with: .color(c.color(alpha)))
    }
    func ovalLine(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ c: FrameRGB, _ alpha: Double, width: Double) {
        g.stroke(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)), with: .color(c.color(alpha)), lineWidth: width)
    }
    func disc(_ x: Double, _ y: Double, _ radius: Double, _ c: FrameRGB, _ alpha: Double = 1) { oval(x, y, radius, radius, c, alpha) }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: FrameRGB, _ alpha: Double = 1) {
        g.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c.color(alpha)))
    }
    func line(_ points: [(Double, Double)], _ c: FrameRGB, _ alpha: Double = 1, width: Double) {
        guard points.count > 1 else { return }
        var path = Path()
        path.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.0, y: p.1)) }
        stroke(path, c, alpha, width: width)
    }
    func shape(_ points: [(Double, Double)], _ c: FrameRGB, _ alpha: Double = 1) {
        fill(Self.outline(points), c, alpha)
    }
    static func outline(_ points: [(Double, Double)]) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        path.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.0, y: p.1)) }
        path.closeSubpath()
        return path
    }
    /// Light added round a point: the colour at the middle, nothing at
    /// `radius` (`squash`: how flat the pool of light lies).
    func glow(_ x: Double, _ y: Double, _ radius: Double, _ c: FrameRGB, _ alpha: Double, squash: Double = 1) {
        guard alpha > 0.003, radius > 0 else { return }
        var layer = g
        layer.blendMode = .plusLighter
        layer.translateBy(x: x, y: y)
        layer.scaleBy(x: 1, y: squash)
        let gradient = Gradient(stops: [.init(color: c.color(alpha), location: 0), .init(color: c.color(alpha * 0.34), location: 0.45), .init(color: c.color(0), location: 1)])
        layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: radius))
    }
    /// An oval with a soft edge (smoke, mist, a thin cloud): whole to
    /// `core` of the way out, nothing at its rim.
    func soft(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ c: FrameRGB, _ alpha: Double, core: Double = 0.35) {
        guard alpha > 0.003, rx > 0, ry > 0 else { return }
        var layer = g
        layer.translateBy(x: x, y: y)
        layer.scaleBy(x: 1, y: ry / rx)
        let gradient = Gradient(stops: [.init(color: c.color(alpha), location: 0), .init(color: c.color(alpha), location: core), .init(color: c.color(0), location: 1)])
        layer.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)),
                   with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: rx))
    }
    /// From one colour at `y0` to another at `y1`, over `path`.
    func fade(_ path: Path, _ top: Color, _ low: Color, y0: Double, y1: Double) {
        g.fill(path, with: .linearGradient(Gradient(colors: [top, low]), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1)))
    }
}

// MARK: - 篝火旁的存档点: where things are

/// The clearing, drawn by hand in coloured pencil: the eye 1.5 m up at the
/// edge of a clearing in the pines; a tent and a pack at the left, the fire
/// in its ring of stones, a log with an old twin-bell alarm clock standing
/// on it, a lantern hanging from a forked stick pushed into the ground; the
/// ranges and the sky behind. One eye, one horizon, one vanishing point: the
/// pictures were drawn with the same metres, and what is drawn here over
/// them (sheet points, 1000 × 600) meets them.
///
/// What does not move is three pictures, one for each light (night, dusk,
/// day), passed from one to the next as the light goes; what moves is drawn
/// each frame: the flames and their light, the sparks, a thin smoke, the
/// lantern's flame, the alarm clock's hands keeping the phone's time, the
/// stars and now and then a falling star, the fireflies.
enum CampfireView {
    static let width = 1000.0, height = 600.0
    /// The fire's foot on the ash, and how many points a metre is there (7.26 m off).
    static let fire = CGPoint(x: 500, y: 479.8), fireK = 124.0
    /// The lantern's flame (the pictures have its glass lit at dusk and by night) and a metre there.
    static let lanternFlame = CGPoint(x: 671.3, y: 363.6), lanternK = 128.0
    /// The alarm clock on the log: the middle of its face and the face's
    /// radius (the pictures have the face; its hands keep the phone's time).
    static let alarm = CGPoint(x: 638.1, y: 455.9), alarmR = 12.0
    /// The pictures: night, dusk, day.
    static let pictures = ["frame-camp-night.jpg", "frame-camp-dusk.jpg", "frame-camp-day.jpg"]
    /// Stars that twinkle over the night's picture, where its sky shows between the pines.
    static let stars: [CGPoint] = [
        CGPoint(x: 164, y: 82), CGPoint(x: 176, y: 130), CGPoint(x: 181, y: 11), CGPoint(x: 197, y: 170), CGPoint(x: 201, y: 71), CGPoint(x: 311, y: 16),
        CGPoint(x: 315, y: 55), CGPoint(x: 317, y: 117), CGPoint(x: 356, y: 91), CGPoint(x: 381, y: 13), CGPoint(x: 408, y: 123), CGPoint(x: 436, y: 55),
        CGPoint(x: 444, y: 173), CGPoint(x: 469, y: 31), CGPoint(x: 479, y: 136), CGPoint(x: 513, y: 40), CGPoint(x: 518, y: 98), CGPoint(x: 525, y: 169),
        CGPoint(x: 570, y: 100), CGPoint(x: 587, y: 132), CGPoint(x: 669, y: 23), CGPoint(x: 686, y: 177), CGPoint(x: 713, y: 77), CGPoint(x: 792, y: 105)]
    /// A firefly: where it roams about, how far across and up, how fast, how often it blinks.
    struct Fly { var x: Double, y: Double, ax: Double, ay: Double, w: Double, b: Double, p: Double, q: Double }
    /// Fireflies over the grass at night, away from the fire, the tent and the log.
    static let flies: [Fly] = {
        var r = FrameRandom(606)
        let places: [(Double, Double)] = [(62, 541), (118, 562), (257, 554), (402, 352), (588, 350), (849, 357), (746, 571), (877, 527),
                                          (805, 459), (679, 572), (897, 469), (749, 426), (849, 581), (906, 389), (961, 410)]
        return places.map { Fly(x: $0.0, y: $0.1, ax: 8 + r.next() * 14, ay: 4 + r.next() * 8, w: 0.2 + r.next() * 0.35, b: 0.6 + r.next() * 1.1, p: r.next() * 6.28, q: r.next() * 6.28) }
    }()
    static let flame = FrameNoise(77), flame2 = FrameNoise(78), wind = FrameNoise(79), lamp = FrameNoise(80)
}

// MARK: - 篝火旁的存档点: drawing it

/// The clearing's pictures, held while it shows.
struct CampfireKept {
    /// Night, dusk, day.
    var backs: [CGImage]
    /// (One set serves every light.)
    static func step(_ light: Double) -> Int { 0 }
    /// What is to hand without a store: the pictures read (or none).
    static func loaded() -> CampfireKept? {
        let backs = CampfireView.pictures.compactMap { TramArt.shared.image($0) }
        return backs.count == CampfireView.pictures.count ? CampfireKept(backs: backs) : nil
    }
}

/// The clearing at one moment.
struct CampfirePainter {
    /// Seconds the scenery has been moving.
    var t: Double
    /// 0 the night's light, a half dusk, 1 the day's.
    var light: Double
    /// The hour of the clock with its minutes, for the alarm clock's hands (none: no hands).
    var hour: Double? = nil

    private typealias V = CampfireView
    private static let W = CampfireView.width, H = CampfireView.height

    /// The two pictures to show for a light and how much of the second.
    static func blend(_ light: Double) -> (Int, Int, Double) {
        let l = frameClamp(light, 0, 1)
        return l < 0.5 ? (0, 1, l * 2) : (1, 2, (l - 0.5) * 2)
    }
    /// 1 at night … 0 by day.
    static func night(_ light: Double) -> Double { frameClamp(1 - light * 1.4, 0, 1) }
    /// How big the fire is: full at night, lower at dusk, small by day (as the pictures have its light).
    static func size(_ light: Double) -> Double {
        let l = frameClamp(light, 0, 1)
        return l < 0.5 ? frameLerp(1, 0.8, l * 2) : frameLerp(0.8, 0.55, (l - 0.5) * 2)
    }

    /// The whole picture into `context`, covering `size`; `drift`: the
    /// picture's place moved by so many points (it is drawn a little larger
    /// than the screen so that its edge never shows).
    func draw(in context: GraphicsContext, size: CGSize, kept: CampfireKept? = nil, drift: CGSize = .zero) {
        let unit = max(size.width / Self.W, size.height / Self.H) * (drift == .zero ? 1 : 1.02)
        var g = context
        g.translateBy(x: (size.width - Self.W * unit) / 2 + drift.width, y: (size.height - Self.H * unit) / 2 + drift.height)
        g.scaleBy(x: unit, y: unit)
        let pen = FramePen(g: g)
        let whole = CGRect(x: 0, y: 0, width: Self.W, height: Self.H)
        let (a, b, d) = Self.blend(light)
        if let art = kept ?? CampfireKept.loaded() {
            g.draw(Image(decorative: art.backs[a], scale: 1), in: whole)
            if d > 0.002 {
                var over = g
                over.opacity = d
                over.draw(Image(decorative: art.backs[b], scale: 1), in: whole)
            }
        } else {
            pen.fade(Path(whole), FrameRGB(28, 36, 67).mixed(FrameRGB(127, 169, 209), light).color(), FrameRGB(46, 61, 56).mixed(FrameRGB(111, 154, 92), light).color(), y0: 0, y1: Self.H)
        }
        let dark = Self.night(light), fire = Self.size(light)
        let flicker = 0.8 + 0.2 * V.flame.fbm(t * 3.1, 3) + 0.1 * sin(t * 11.3) * V.flame2.at(t * 5)
        let wind = (V.wind.fbm(t * 0.22, 2) - 0.5) * 2
        stars(pen, dark)
        smoke(pen, fire, dark, wind)
        fireLight(pen, fire, dark, flicker)
        flames(g, fire, flicker, wind)
        sparks(pen, fire, dark, wind)
        lantern(pen)
        if let hour { pen.clockHands(V.alarm.x, V.alarm.y, V.alarmR, hour: hour, FrameRGB(44, 42, 46), width: 1.1) }
        fireflies(pen, dark)
        // The frame's own dusk at its corners.
        g.fill(Path(whole), with: .radialGradient(Gradient(colors: [Color.black.opacity(0), Color.black.opacity(frameLerp(0.3, 0.18, light))]), center: CGPoint(x: 500, y: 320), startRadius: 260, endRadius: 660))
    }

    // MARK: The fire

    /// The fire's light round the flames, and on the clearing as they rise
    /// and fall (the pictures have it at its middle).
    private func fireLight(_ pen: FramePen, _ fire: Double, _ dark: Double, _ flicker: Double) {
        let k = V.fireK, more = frameClamp((flicker - 0.62) / 0.5, 0, 1)
        let fx = Double(V.fire.x), fy = Double(V.fire.y)
        pen.glow(fx, fy - 0.35 * k * fire, 1.2 * k * fire, FrameRGB(240, 164, 86), (0.12 + 0.26 * dark) * (0.7 + 0.3 * more))
        guard dark > 0.02 else { return }
        pen.glow(fx, fy + 4, 330, FrameRGB(255, 160, 72), 0.14 * dark * more, squash: 0.36)
    }

    /// The flames: three coats of tongues (deep orange, orange, the pale
    /// heart), each tongue swaying on its own and all leaning with the wind;
    /// the paper shows through them in fine slanting strokes, as it does
    /// through coloured pencil.
    private func flames(_ g: GraphicsContext, _ fire: Double, _ flicker: Double, _ wind: Double) {
        let fx = Double(V.fire.x), fy = Double(V.fire.y), k = V.fireK
        let coats: [(colour: FrameRGB, tongues: [(dx: Double, h: Double, w: Double, ph: Double)])] = [
            (FrameRGB(226, 104, 58), [(-0.12, 0.78, 0.13, 0.3), (0.1, 0.66, 0.12, 1.7), (0, 0.95, 0.16, 3.1)]),
            (FrameRGB(242, 162, 70), [(-0.06, 0.55, 0.1, 0.9), (0.05, 0.7, 0.11, 2.4)]),
            (FrameRGB(255, 230, 160), [(0, 0.42, 0.07, 4.2)])]
        let t = self.t
        g.drawLayer { layer in
            for coat in coats {
                var path = Path()
                for tongue in coat.tongues {
                    let reach = tongue.h * k * fire * (0.78 + 0.32 * V.flame.at(t * 2.6 + tongue.ph * 3.1)) * (0.82 + 0.22 * flicker)
                    let w = tongue.w * k * (0.75 + 0.25 * fire)
                    var right: [CGPoint] = [], left: [CGPoint] = []
                    for i in 0...14 {
                        let u = Double(i) / 14
                        let sway = (V.flame2.fbm(t * 2.1 + tongue.ph + u * 1.7, 2) - 0.5) * w * 1.6 * u + wind * w * 0.9 * u * u
                        let half = w * (1 - u) * sin(Double.pi * min(1, u * 1.3)) * 0.9
                        right.append(CGPoint(x: fx + tongue.dx * k + sway + half, y: fy - reach * u))
                        left.append(CGPoint(x: fx + tongue.dx * k + sway - half, y: fy - reach * u))
                    }
                    path.addPath(Self.rounded(right + left.reversed()))
                }
                layer.fill(path, with: .color(coat.colour.color(0.95)))
            }
            // The paper's tooth through the colour: the same fine strokes every frame.
            var tooth = layer
            tooth.blendMode = .destinationOut
            var strokes = Path()
            var r = FrameRandom(321)
            var y = fy - 1.3 * k * fire
            while y < fy + 6 {
                let x = fx - 0.5 * k + r.next() * k, length = 4 + r.next() * 9
                strokes.move(to: CGPoint(x: x, y: y))
                strokes.addLine(to: CGPoint(x: x + length * 0.5, y: y - length * 0.87))
                y += 0.9 + r.next() * 0.9
            }
            tooth.stroke(strokes, with: .color(Color.black.opacity(0.2)), lineWidth: 0.7)
        }
    }

    /// A closed outline through `points`, its corners rounded (each side's middle on it).
    private static func rounded(_ points: [CGPoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n > 2 else { return path }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(points[n - 1], points[0]))
        for i in 0..<n { path.addQuadCurve(to: mid(points[i], points[(i + 1) % n]), control: points[i]) }
        path.closeSubpath()
        return path
    }

    /// Sparks going up from the flames (fewer to be seen by day).
    private func sparks(_ pen: FramePen, _ fire: Double, _ dark: Double, _ wind: Double) {
        let fx = Double(V.fire.x), fy = Double(V.fire.y) - 0.6 * V.fireK * fire
        for i in 0..<18 {
            let n = Double(i)
            let speed = 0.14 + Double(i * 13 % 7) * 0.025
            let life = (t * speed + n * 0.137).truncatingRemainder(dividingBy: 1)
            let alpha = pow(1 - life, 1.5) * (0.25 + 0.75 * dark)
            guard alpha > 0.02 else { continue }
            let jitter = sin(n * 2.7) * 10 + sin(t * 1.3 + n) * 9 * life
            let carried = wind * 40 * life * life
            let spread = Double(i % 5 - 2) * 7 * life
            let px = fx + jitter + carried + spread
            let rise = 110 + Double(i * 7 % 50)
            let py = fy - life * rise * (0.6 + 0.4 * fire)
            pen.glow(px, py, 4.5, FrameRGB(255, 176, 80), alpha * 0.6)
            pen.disc(px, py, 0.9, FrameRGB(255, 220, 150), alpha)
        }
    }

    /// A thin smoke going up from the fire and drifting off with the wind, seen best by day.
    private func smoke(_ pen: FramePen, _ fire: Double, _ dark: Double, _ wind: Double) {
        let fx = Double(V.fire.x), fy = Double(V.fire.y) - 0.7 * V.fireK * fire
        let colour = FrameRGB(150, 158, 190).mixed(FrameRGB(236, 236, 238), light)
        for i in 0..<8 {
            let n = Double(i)
            let life = (t * 0.07 + n / 8).truncatingRemainder(dividingBy: 1)
            let wander = sin(n * 1.9 + t * 0.4) * 26 * life
            let sx = fx + wind * 60 * life + wander + 56 * life * life
            let sy = fy - life * 220
            let puff = sin(Double.pi * pow(life, 0.6))
            pen.soft(sx, sy, 14 + life * 60, 12 + life * 30, colour, puff * (0.05 + 0.07 * (1 - dark)) * (1 - life * 0.5), core: 0.15)
        }
    }

    // MARK: The lantern, the sky, the fireflies

    /// The lantern's flame, a little unsteady: its light round the glass.
    private func lantern(_ pen: FramePen) {
        let l = frameClamp(light, 0, 1)
        let on = l < 0.5 ? frameLerp(1, 0.55, l * 2) : frameLerp(0.55, 0, (l - 0.5) * 2)
        guard on > 0.01 else { return }
        let f = 0.86 + 0.14 * V.lamp.fbm(t * 4.3, 2) + 0.04 * sin(t * 17)
        let p = V.lanternFlame, k = V.lanternK
        pen.glow(p.x, p.y, 0.55 * k, FrameRGB(255, 212, 138), 0.34 * on * f)
        pen.glow(p.x, p.y, 0.16 * k, FrameRGB(255, 242, 204), 0.45 * on * f)
    }

    /// Stars twinkling where the night's sky shows, and now and then one
    /// falling across the open sky over the ranges.
    private func stars(_ pen: FramePen, _ dark: Double) {
        let night = dark * dark
        guard night > 0.02 else { return }
        let starlight = FrameRGB(245, 238, 214)
        for (i, s) in V.stars.enumerated() {
            let twinkle = 0.5 + 0.5 * sin(t * (0.7 + Double(i % 5) * 0.23) + Double(i) * 2.3)
            let alpha = night * twinkle * twinkle * 0.8
            pen.disc(s.x, s.y, i % 4 == 0 ? 1.3 : 0.9, starlight, alpha)
            if i % 4 == 0 { pen.glow(s.x, s.y, 6, starlight, alpha * 0.4) }
        }
        let phase = (t + 23).truncatingRemainder(dividingBy: 53)
        guard phase < 1 else { return }
        var random = FrameRandom(UInt32(700 + Int(((t + 23) / 53).rounded(.down)) % 100_000))
        let x0: Double = 330 + random.next() * 90, y0: Double = 18 + random.next() * 24
        let x = x0 + phase * 120, y = y0 + phase * 45
        let alpha = sin(Double.pi * phase) * night
        var trail = Path()
        trail.move(to: CGPoint(x: x - 50, y: y - 19))
        trail.addLine(to: CGPoint(x: x, y: y))
        pen.g.stroke(trail, with: .linearGradient(Gradient(colors: [Color.white.opacity(0), starlight.color(alpha)]), startPoint: CGPoint(x: x - 50, y: y - 19), endPoint: CGPoint(x: x, y: y)),
                     style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    /// Fireflies over the grass at night, each roaming about its place and blinking.
    private func fireflies(_ pen: FramePen, _ dark: Double) {
        let night = dark * dark
        guard night > 0.05 else { return }
        for fly in V.flies {
            let blink = max(0, sin(t * fly.b + fly.p))
            let bright = blink * blink * night
            guard bright > 0.02 else { continue }
            let x = fly.x + sin(t * fly.w + fly.p) * fly.ax + sin(t * fly.w * 2.3 + fly.q) * 4
            let y = fly.y + cos(t * fly.w * 1.3 + fly.q) * fly.ay
            pen.glow(x, y, 10, FrameRGB(214, 250, 120), 0.6 * bright)
            pen.disc(x, y, 1.2, FrameRGB(250, 255, 214), bright)
        }
    }
}

// MARK: - The kept pictures

/// Reads the clearing's pictures when the scenery is shown, lets them go when another is.
@MainActor final class CampfireKeptStore: ObservableObject {
    @Published private(set) var kept: CampfireKept?
    func prepare(light: Double, pixelWidth: Int) {
        guard kept == nil else { return }
        kept = CampfireKept.loaded()
    }
    /// The pictures let go (another scenery is showing).
    func release() {
        guard kept != nil else { return }
        kept = nil
        TramArt.shared.forget()
    }
}

// MARK: - The two screens

/// 画框's upper screen: the scenery, drawn again thirty times a second.
struct PictureFrameScreen: View {
    var s: Double
    /// Standing on the cover (FrameStand): whether the iPhone is plugged in; nil on the console's screen.
    var standCharging: Bool? = nil
    @ObservedObject private var settings = PictureFrameSettings.shared
    @ObservedObject private var run = PictureFrameRun.shared
    @StateObject private var store = CampfireKeptStore()
    @StateObject private var roofsStore = RoofsKeptStore()
    @StateObject private var tramStore = TramKeptStore()
    @StateObject private var airshipStore = AirshipKeptStore()
    @Environment(\.displayScale) private var displayScale
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let pixels = Int((proxy.size.width * displayScale).rounded())
            ZStack {
                Color.black
                if !run.asleep {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let seconds = Self.fixedSeconds ?? run.seconds(at: timeline.date)
                        let light = settings.light(at: timeline.date)
                        let hour = settings.hour(at: timeline.date)
                        let scene = settings.scene
                        let kept = store.kept, roofsKept = roofsStore.kept, tramKept = tramStore.kept, airshipKept = airshipStore.kept
                        let drift = Self.drift(seconds)
                        Canvas { context, size in
                            if scene == .roofs {
                                RoofsPainter(t: seconds, light: light, hour: hour).draw(in: context, size: size, kept: roofsKept, drift: drift)
                            } else if scene == .tramStop {
                                TramStopPainter(t: seconds, light: light, hour: hour).draw(in: context, size: size, kept: tramKept, drift: drift)
                            } else if scene == .airship {
                                AirshipPainter(t: seconds, light: light, hour: hour).draw(in: context, size: size, kept: airshipKept, drift: drift)
                            } else {
                                CampfirePainter(t: seconds, light: light, hour: hour).draw(in: context, size: size, kept: kept, drift: drift)
                            }
                        }
                        .onChange(of: Self.keptKey(scene, light: light, pixels: pixels), initial: true) { keep(scene, light: light, pixels: pixels) }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: run.asleep)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { run.touch() }
        .onAppear { run.appear(holdsAwake: standCharging ?? true); hear(Date()) }
        .onChange(of: standCharging) { _, charging in run.holdAwake(charging ?? true) }
        .onDisappear {
            run.disappear()
            if !run.isUp { PictureFrameSound.shared.update(scene: nil, light: 0, gain: 0) }
        }
        .onReceive(clock) { now in
            run.tick(now, sleepMinutes: standCharging.map { FrameStand.sleepMinutes(charging: $0, chosen: settings.sleepMinutes) } ?? settings.sleepMinutes)
            hear(now)
        }
        .onChange(of: settings.sound) { _, _ in hear(Date()) }
        .onChange(of: run.asleep) { _, _ in hear(Date()) }
        // 11-15: a scenery looked at a little while sends its postcard to 铅笔盒 (once; PencilPostcards)
        .task(id: run.asleep ? nil : settings.scene) {
            guard !run.asleep else { return }
            let scene = settings.scene
            try? await Task.sleep(nanoseconds: UInt64(PencilPostcards.seenSeconds * 1_000_000_000))
            guard !Task.isCancelled, settings.scene == scene, !run.asleep else { return }
            PencilBoxStore.shared.sendPostcard(scene)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: settings.scene.title))
        .accessibilityValue(Text(verbatim: status))
        .accessibilityIdentifier("picture-frame-screen")
    }
    /// The scenery's sound as it should be now: on with 声音, off in the
    /// dark, as loud as the console's volume. (Once a second: the light
    /// moves on, and an engine something stopped starts again.)
    private func hear(_ now: Date) {
        let wanted = settings.sound && !run.asleep
        let silent = SilentRun.on
        let scene: FrameScene? = wanted && (!silent || PictureFrameSound.dry) ? settings.scene : nil
        PictureFrameSound.shared.update(scene: scene, light: settings.light(at: now), gain: ConsoleVolume.shared.gain, muted: silent)
        PictureFrameSound.shared.chime(scene: scene, at: now)
        PictureFrameSound.shared.cue(scene: scene, seconds: Self.fixedSeconds ?? run.seconds(at: now))
    }
    /// What the kept pictures are made for: the scenery, its light's step, the screen's width in pixels.
    private static func keptKey(_ scene: FrameScene, light: Double, pixels: Int) -> Int {
        switch scene {
        case .roofs: return 100_000_000 + RoofsKept.step(light) * 10_000 + min(9_999, pixels)
        case .tramStop: return 200_000_000 + TramKept.step(light) * 10_000 + min(9_999, pixels)
        case .airship: return 300_000_000 + AirshipKept.step(light) * 10_000 + min(9_999, pixels)
        default: return CampfireKept.step(light) * 10_000 + min(9_999, pixels)
        }
    }
    /// The kept pictures of the scenery showing made (those of the other let go).
    private func keep(_ scene: FrameScene, light: Double, pixels: Int) {
        if scene != .campfire { store.release() }
        if scene != .roofs { roofsStore.release() }
        if scene != .tramStop { tramStore.release() }
        if scene != .airship { airshipStore.release() }
        switch scene {
        case .roofs: roofsStore.prepare(light: light, pixelWidth: pixels)
        case .tramStop: tramStore.prepare(light: light, pixelWidth: pixels)
        case .airship: airshipStore.prepare(light: light, pixelWidth: pixels)
        default: store.prepare(light: light, pixelWidth: pixels)
        }
    }
    /// For assistive access and the tests: the scenery, its light as a
    /// hundredth, and whether the frame has dimmed or gone dark.
    private var status: String {
        let light = Int((settings.light(at: Date()) * 100).rounded())
        return "\(settings.scene.rawValue).\(light)" + (run.asleep ? ".asleep" : (run.dimmed ? ".dim" : ""))
    }
    /// The picture's place moves a point or two over minutes, so that
    /// nothing of it stands on the same dots of the display for hours.
    static func drift(_ seconds: Double) -> CGSize {
        CGSize(width: sin(seconds / 97) * 2.5, height: cos(seconds / 131) * 2)
    }
    /// A debug build's `--foldarc-frame-still=<seconds>`: the scenery
    /// stands at that moment (a picture for the tests that is the same
    /// every time).
    static let fixedSeconds: Double? = {
        #if DEBUG
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--foldarc-frame-still=") {
            return Double(argument.dropFirst("--foldarc-frame-still=".count))
        }
        #endif
        return nil
    }()
}

/// 画框 on the cover (FrameStand): 画框 open inside and the Duo shut or stood
/// half open like a tent, the scenery fills the cover turned the way the tent
/// stands (hinge up), drawn as on the console's upper screen, its clocks keeping the
/// phone's time. A swipe sideways brings the next scenery; a touch wakes it.
/// Plugged in it stays lit; on the battery the iPhone locks as it would.
struct PictureFrameStand: View {
    /// On the hardware cover (its rotation, shown once it has settled); otherwise a preview.
    var fromDevice: Bool
    @ObservedObject private var settings = PictureFrameSettings.shared
    @StateObject private var power = FramePower()
    #if os(iOS)
    @ObservedObject private var displayRole = DisplayRoleMonitor.shared
    #endif
    private var visible: Bool {
        #if os(iOS)
        return !fromDevice || displayRole.coverSettled
        #else
        return true
        #endif
    }
    /// The window's turn against the cover's own portrait (as the camera's tent has it).
    private func interfaceRotation(for size: CGSize) -> Double {
        #if os(iOS)
        if fromDevice, let rotation = displayRole.coverRotation(for: size) { return rotation }
        if let rotation = CoverHoldMonitor.sceneInterfaceRotation(),
           (abs(FixedFrameTransform.normalized(rotation)) == 90) == (size.width > size.height) { return rotation }
        #endif
        return size.height >= size.width ? 0 : -90
    }

    var body: some View {
        GeometryReader { proxy in
            let placement = CoverHoldPlacement.calculate(window: proxy.size, interfaceRotation: interfaceRotation(for: proxy.size), hold: .clockwise)
            let canvas = placement.canvasSize
            PictureFrameScreen(s: 1, standCharging: power.charging)
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                    let dx = drag.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(drag.translation.height) * 1.5 else { return }
                    PictureFrameRun.shared.touch()
                    settings.step(dx < 0 ? 1 : -1)
                    NSLog("[frame] standing: %@", settings.scene.rawValue)
                })
                .frame(width: canvas.width, height: canvas.height)
                .rotationEffect(.degrees(placement.rotationDegrees))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .animation(nil, value: placement)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: visible)
        #if os(iOS)
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
        #endif
        .onAppear { NSLog("[frame] standing on the cover: %@, %@", settings.scene.rawValue, power.charging ? "plugged in" : "on the battery") }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picture-frame-stand")
    }
}

/// Whether the iPhone is plugged in (charging or full), as UIKit tells it.
@MainActor final class FramePower: ObservableObject {
    @Published private(set) var charging = false
    private var watching: AnyCancellable?
    init() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        charging = Self.pluggedIn()
        watching = NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.charging = Self.pluggedIn() } }
        #endif
    }
    #if os(iOS)
    private static func pluggedIn() -> Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }
    #endif
}

/// A scenery small, standing still: what the lower screen offers to choose.
private struct FrameThumbnail: View {
    var scene: FrameScene
    var s: Double
    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.09, opacity: 1)
            if scene == .campfire {
                Canvas { context, size in CampfirePainter(t: 6.5, light: 0, hour: 21 + 40.0 / 60).draw(in: context, size: size) }
            } else if scene == .roofs {
                Canvas { context, size in RoofsPainter(t: 9, light: 0.5, hour: 18.5).draw(in: context, size: size) }
            } else if scene == .tramStop {
                Canvas { context, size in TramStopPainter(t: 8, light: 0).draw(in: context, size: size) }
            } else if scene == .airship {
                Canvas { context, size in AirshipPainter(t: 18, light: 0.5).draw(in: context, size: size) }
            } else {
                VStack(spacing: 2 * s) {
                    Image(systemName: "paintbrush.pointed.fill").font(.system(size: 9 * s, weight: .semibold)).accessibilityHidden(true)
                    Text("还在画").font(.system(size: 7 * s, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }
}

/// 画框's lower screen: dim — the clock, the sceneries, the switches. It
/// fades when nobody touches it, and is black once the frame has gone dark.
struct PictureFramePanel: View {
    @ObservedObject var model: ConsoleAppModel
    var s: Double
    @ObservedObject private var settings = PictureFrameSettings.shared
    @ObservedObject private var run = PictureFrameRun.shared
    /// 11-15: a postcard come into 铅笔盒 is said here.
    @ObservedObject private var box = PencilBoxStore.shared
    /// A Duo (the hinge reports): the cover is where the frame goes.
    @ObservedObject private var hinge = HingePosture.shared

    private static let paper = Color(.sRGB, red: 0.075, green: 0.062, blue: 0.066, opacity: 1)
    private static let tile = Color(.sRGB, red: 0.155, green: 0.128, blue: 0.130, opacity: 1)
    private static let edge = Color(.sRGB, red: 0.36, green: 0.29, blue: 0.27, opacity: 1)
    private static let ink = Color(.sRGB, red: 0.96, green: 0.92, blue: 0.82, opacity: 1)
    private static let inkSoft = Color(.sRGB, red: 0.92, green: 0.87, blue: 0.78, opacity: 0.74)
    private static let gold = Color(.sRGB, red: 0.92, green: 0.81, blue: 0.53, opacity: 1)
    static func sceneID(_ scene: FrameScene) -> String { "frame.scene.\(scene.rawValue)" }

    var body: some View {
        register()
        return ZStack {
            Color.black
            if !run.asleep {
                VStack(spacing: 5 * s) {
                    clockLine
                    scenes
                    // 11-15: nothing to start — how it becomes the frame.
                    (hinge.status == nil ? Text("选好就在放了。把手机立在桌上，它就是一个会动的画框。")
                                         : Text("选好就在放了。合上手机，外屏就是这幅画；半开立在桌上也是。"))
                        .font(.system(size: 8.5 * s, weight: .medium, design: .rounded))
                        .foregroundStyle(Self.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("frame-how")
                    row(id: "frame.sound", title: String(localized: "声音"), says: settings.sound ? String(localized: "开") : String(localized: "关"),
                        action: { toggleSound() }) { onOff(settings.sound) }
                    row(id: "frame.clock", title: String(localized: "早晚的光跟着手机的时间"), says: settings.followsClock ? String(localized: "开") : String(localized: "关"),
                        action: { toggleClock() }) { onOff(settings.followsClock) }
                    row(id: "frame.sleep", title: String(localized: "多久以后熄屏"), says: settings.sleepTitle, action: { stepSleep(1) }) { value(settings.sleepTitle) }
                    Spacer(minLength: 0)
                    bar
                }
                .padding(.horizontal, 12 * s).padding(.top, 8 * s).padding(.bottom, 5 * s)
                .background(Self.paper)
                .opacity(run.dimmed ? 0.42 : 1)
                .animation(.easeInOut(duration: 0.8), value: run.dimmed)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: run.asleep)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in run.touch() })
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .dark)
        .onChange(of: box.arrived) { _, _ in
            if let scene = box.lastArrived { model.say(String(localized: "铅笔盒里多了一张明信片：\(scene.title)")) }
        }
    }

    /// The time, large, and the day under it; it stands a little
    /// elsewhere each minute.
    private var clockLine: some View {
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            let minute = Calendar.current.component(.minute, from: date)
            HStack(alignment: .firstTextBaseline, spacing: 8 * s) {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 27 * s, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Self.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4 * s)
                Text(date.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 10 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4 * s)
            .offset(x: Double(minute % 5 - 2) * 1.5 * s, y: Double(minute % 3 - 1) * 1 * s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("frame-clock")
        }
    }

    /// The four sceneries; the one showing has a gold edge.
    private var scenes: some View {
        HStack(spacing: 6 * s) {
            ForEach(FrameScene.allCases) { scene in
                let id = Self.sceneID(scene)
                let chosen = settings.scene == scene
                let shape = RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                Button { model.focus = id; choose(scene) } label: {
                    FrameThumbnail(scene: scene, s: s)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38 * s)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(chosen ? Self.gold : Self.edge, lineWidth: chosen ? max(2, 2.5 * s) : 1))
                        .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s, color: Self.gold) } }
                        .contentShape(shape)
                }
                .buttonStyle(MenuPressStyle())
                .accessibilityLabel(Text(verbatim: scene.title))
                .accessibilityValue(scene.isReady ? Text(verbatim: "") : Text("还在画"))
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
                .accessibilityIdentifier("app.\(id)")
            }
        }
    }

    /// A row: its name, what it is set to (`says`: the same for assistive access), the cursor's ring.
    private func row<Trailing: View>(id: String, title: String, says: String, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
        return Button { model.focus = id; action() } label: {
            HStack(spacing: 8 * s) {
                Text(title).font(.system(size: 10.5 * s, weight: .semibold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 4 * s)
                trailing()
            }
            .padding(.horizontal, 10 * s).padding(.vertical, 5 * s)
            .frame(maxWidth: .infinity, minHeight: 27 * s, alignment: .leading)
            .background(shape.fill(Self.tile))
            .overlay(shape.strokeBorder(Self.edge, lineWidth: 1))
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s, color: Self.gold) } }
            .contentShape(shape)
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: says))
        .accessibilityIdentifier("app.\(id)")
    }
    /// 开 or 关, the one that holds in gold.
    private func onOff(_ on: Bool) -> some View {
        (on ? Text("开") : Text("关"))
            .font(.system(size: 9.5 * s, weight: .bold, design: .rounded))
            .foregroundStyle(on ? Color.black.opacity(0.85) : Self.ink)
            .frame(minWidth: 34 * s, minHeight: 18 * s)
            .background(on ? Self.gold : Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Self.edge, lineWidth: 1))
    }
    private func value(_ text: String) -> some View {
        HStack(spacing: 4 * s) {
            Image(systemName: "chevron.left").font(.system(size: 7 * s, weight: .bold)).foregroundStyle(Self.inkSoft).accessibilityHidden(true)
            Text(text).font(.system(size: 9.5 * s, weight: .bold, design: .rounded)).foregroundStyle(Self.ink).frame(minWidth: 40 * s)
            Image(systemName: "chevron.right").font(.system(size: 7 * s, weight: .bold)).foregroundStyle(Self.inkSoft).accessibilityHidden(true)
        }
    }
    /// 返回, where the other programs have their bar.
    private var bar: some View {
        let shape = Capsule()
        return HStack {
            Button { model.focus = ConsoleAppModel.barLeft; model.pop() } label: {
                HStack(spacing: 4 * s) {
                    Image(systemName: "house").font(.system(size: 8.5 * s, weight: .bold)).accessibilityHidden(true)
                    Text("返回").font(.system(size: 9.5 * s, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 11 * s)
                .frame(minHeight: 22 * s)
                .background(shape.fill(Self.tile))
                .overlay(shape.strokeBorder(Self.edge, lineWidth: 1))
                .overlay { if model.focus == ConsoleAppModel.barLeft { MenuCursorRing(shape: shape, s: s, color: Self.gold) } }
                .contentShape(shape)
            }
            .buttonStyle(MenuPressStyle())
            .accessibilityLabel(Text("返回"))
            .accessibilityIdentifier("app.bar.left")
            Spacer(minLength: 0)
            if let toast = model.toast {
                Text(toast).font(.system(size: 8.5 * s, weight: .bold, design: .rounded)).foregroundStyle(Self.gold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .transition(.opacity)
                    .accessibilityIdentifier("app-toast")
            }
        }
    }

    // MARK: What the keys and the touches do

    private func choose(_ scene: FrameScene) {
        run.touch()
        guard scene.isReady else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
            model.say(String(localized: "这一幅还在画"))
            return
        }
        guard settings.scene != scene else { return }
        ConsoleSounds.shared.play(.select)
        settings.scene = scene
    }
    private func toggleSound() {
        run.touch()
        ConsoleSounds.shared.play(.select)
        settings.sound.toggle()
    }
    private func toggleClock() {
        run.touch()
        ConsoleSounds.shared.play(.select)
        settings.followsClock.toggle()
    }
    private func stepSleep(_ delta: Int) {
        run.touch()
        ConsoleSounds.shared.play(.move)
        settings.sleepMinutes = FrameSleep.choice(after: settings.sleepMinutes, by: delta)
    }
    /// The page tells the program what it holds (the D-pad moves over it, A
    /// presses, left and right change a row's value), as every page does.
    private func register() {
        guard model.page == .pictureFrame else { return }
        let ids = FrameScene.allCases.map(Self.sceneID)
        model.layout = [ids, ["frame.sound"], ["frame.clock"], ["frame.sleep"], [ConsoleAppModel.barLeft]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { model.pop() }, "frame.sound": { toggleSound() }, "frame.clock": { toggleClock() }, "frame.sleep": { stepSleep(1) }]
        for scene in FrameScene.allCases { handlers[Self.sceneID(scene)] = { choose(scene) } }
        model.handlers = handlers
        model.adjusters = ["frame.sound": { _ in toggleSound() }, "frame.clock": { _ in toggleClock() }, "frame.sleep": { stepSleep($0) }]
        model.registered(initial: Self.sceneID(settings.scene))
    }
}
