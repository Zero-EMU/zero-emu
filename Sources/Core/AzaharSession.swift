import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#endif

#if FOLDARC_CORE
/// Swift face of the libretro host: owns the core lifecycle for one game,
/// publishes the two screens as images, plays the core's audio, and maps
/// FoldArc's pad model onto libretro inputs. The core itself (Azahar) is a
/// separate GPL binary loaded from the app bundle; nothing here decrypts,
/// downloads or ships game content.
@MainActor final class AzaharSession: NSObject, ObservableObject {
    @Published private(set) var top: CGImage?
    @Published private(set) var bottom: CGImage?
    @Published private(set) var running = false
    @Published private(set) var status = String(localized: "核心未加载")
    @Published private(set) var lastMessage: String?
    /// The core said the software cannot go on (PlayView shows an alert).
    @Published private(set) var softwareStop: SoftwareStop?
    @Published private(set) var log: [String] = []
    @Published private(set) var framesPerSecond: Double = 0

    private let host = FALibretroCore.shared
    private var engine: AVAudioEngine?
    private var fpsWindowStart = Date()
    private var fpsWindowFrames = 0
    private var fpsLogCounter = 0
    private let mailbox = FrameMailbox()
    private let messages = MessageMailbox()
    #if os(iOS)
    /// Audio-session and engine notifications (see observeAudioSession()).
    private let audioObservers = AudioObservers()
    /// The system has taken the audio session (a call, Siri, an alarm).
    private var audioInterrupted = false
    #endif
    #if DEBUG
    private let mixerMeter = MixerMeter()
    #endif
    /// The console's volume slider (round 20) while a game runs.
    private var volumeWatch: ObserverToken?

    /// Where the core binary lives in the bundle: `azahar_libretro.framework`,
    /// made by the "Embed libretro core" build phase (iOS takes dynamic
    /// libraries only inside framework bundles). The bare dylib of builds
    /// before the 15th round is still found.
    static var corePath: String? {
        guard let dir = Bundle.main.privateFrameworksURL else { return nil }
        let candidates = ["azahar_libretro.framework/azahar_libretro", "azahar_libretro.dylib"]
        for name in candidates {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url.path }
        }
        return nil
    }
    static var isCoreAvailable: Bool { corePath != nil }

    /// Compressed game files (Z3DS) are looked into through the core's own
    /// reader: the library's import is given the way (at launch).
    static func installCompressedReader() {
        guard let core = corePath else { return }
        ROMImporter.openCompressed = { url in
            FACompressedGameFile.open(path: url.path, corePath: core).map { CoreCompressedSource(file: $0) }
        }
    }
    #if DEBUG
    /// `--foldarc-compress=<file>=><compressed file>`: the core compresses a
    /// game file (the tests make their .z3dsx this way, before importing it).
    static func compressForTests() {
        guard let core = corePath else { return }
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--foldarc-compress=") {
            let parts = String(argument.dropFirst("--foldarc-compress=".count)).components(separatedBy: "=>")
            guard parts.count == 2, let head = try? FileHandle(forReadingFrom: URL(fileURLWithPath: parts[0])).read(upToCount: 0x200) else {
                NSLog("[core] compress: cannot read %@", argument); continue
            }
            // What the file is: "3DSX" at its start, or "NCSD" / "NCCH" at 0x100.
            let magic = head.prefix(4).elementsEqual(Array("3DSX".utf8)) ? Data(head.prefix(4)) : (head.count >= 0x104 ? Data(head[0x100..<0x104]) : Data())
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: parts[1]).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: parts[1])
            let done = FACompressedGameFile.compress(path: parts[0], to: parts[1], magic: magic, corePath: core)
            let size = ((try? FileManager.default.attributesOfItem(atPath: parts[1])[.size]) as? Int64) ?? -1
            NSLog("[core] compress %@ -> %@: %@ (%lld bytes)", (parts[0] as NSString).lastPathComponent, (parts[1] as NSString).lastPathComponent, done ? "done" : "failed", size)
        }
    }
    #endif

    /// Core options for the software renderer: interpreter CPU (iOS has no
    /// JIT), native resolution. `loadGame(_:dirs:vulkan:)` switches the
    /// graphics options when a Vulkan context is available.
    nonisolated static let defaultVariables: [String: String] = [
        "citra_graphics_api": "Software",
        "citra_use_cpu_jit": "disabled",
        "citra_use_shader_jit": "disabled",
        "citra_resolution_factor": "1",
        "citra_layout_option": "Default Top-Bottom Screen",
        "citra_is_new_3ds": "enabled",
        "citra_region_value": "Auto",
        "citra_audio_emulation": "HLE",
        "citra_use_hw_shader": "disabled",
        "citra_touch_touchscreen": "enabled",
        "citra_mouse_touchscreen": "disabled",
        "citra_use_virtual_sd": "enabled",
        "citra_swap_screen": "disabled",
        // The microphone is FoldArc's (LibretroCore.mm): silence, or a breath
        // while MIC is held. The iPhone's microphone is never opened.
        "citra_input_type": "frontend",
        "citra_factor_3d": "0",
        "citra_render_3d": "off",
    ]

    override init() {
        super.init()
        host.delegate = self
        #if os(iOS)
        observeAudioSession()
        #endif
        // The volume slider moves: a running game follows it at once.
        volumeWatch = ObserverToken(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.setVolume(1)
            }
        })
        #if DEBUG
        host.echoLogToConsole = true
        #endif
    }

    /// The core's system folder (FoldArc's own, empty: no system files are
    /// shipped or fetched) and its save folder, which is the Files folder
    /// (`Storage.consoleStorage()`).
    var directories: (system: URL, saves: URL) {
        let root = Storage.root.appendingPathComponent("Azahar", isDirectory: true)
        return (root.appendingPathComponent("system", isDirectory: true), Storage.consoleStorage())
    }

    /// Which renderer to try first: the core's Vulkan renderer on MoltenVK
    /// unless the user (or the DEBUG launch argument
    /// `--foldarc-renderer=software`) chose software. Any Vulkan failure falls
    /// back to software for that load.
    enum Renderer: String { case vulkan, software }
    static var preferredRenderer: Renderer {
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-renderer=") }),
           let choice = Renderer(rawValue: String(arg.dropFirst("--foldarc-renderer=".count))) { return choice }
        #endif
        return Renderer(rawValue: UserDefaults.standard.string(forKey: "FoldArc.renderer") ?? "") ?? .vulkan
    }
    /// Internal resolution of the Vulkan renderer (1 = the 3DS's own 400×240).
    static var vulkanResolutionFactor: Int {
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-resolution=") }),
           let value = Int(arg.dropFirst("--foldarc-resolution=".count)), (1...4).contains(value) { return value }
        #endif
        let stored = UserDefaults.standard.integer(forKey: "FoldArc.resolutionFactor")
        return (1...4).contains(stored) ? stored : 1
    }

    /// Vulkan frames are read back off the emulation thread unless the DEBUG
    /// launch argument `--foldarc-readback=sync` asks for the old synchronous
    /// copy (A/B measurements).
    nonisolated static var asyncReadback: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-readback=sync") { return false }
        #endif
        return true
    }

    /// DEBUG launch argument `--foldarc-unthrottled`: frames run back to back
    /// without pacing (throughput benchmarks; excess audio is dropped).
    nonisolated static var benchmarkUnthrottled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--foldarc-unthrottled")
        #else
        return false
        #endif
    }

    /// True while `load(game:)` runs on its background thread.
    @Published private(set) var loading = false
    /// The 3D percentage the core was last given (set3DDepth).
    private var appliedDepth: Int?
    private var stopAfterLoad = false

    /// Loads the core and the game off the main thread: with the Vulkan
    /// renderer, device creation and the renderer's start-up take seconds
    /// (10-27: ~5 s in the Simulator), which froze the UI mid-rotation.
    func load(game url: URL) async throws {
        guard let path = Self.corePath else {
            status = String(localized: "App 包里没有核心二进制（azahar_libretro.framework）")
            throw NSError(domain: "FoldArc.Azahar", code: 1, userInfo: [NSLocalizedDescriptionKey: status])
        }
        guard !loading else { throw Self.error(String(localized: "核心正在启动")) }
        softwareStop = nil
        loading = true
        stopAfterLoad = false
        defer { loading = false }
        let host = self.host
        let dirs = directories
        let preferVulkan = Self.preferredRenderer == .vulkan
        // The console's system settings (round 23): power saving renders at
        // the 3DS's own resolution; parental controls keep 3D off; the
        // language and region its software reads.
        let system = ConsoleSettings.shared
        let factor = system.powerSaving ? 1 : Self.vulkanResolutionFactor
        let depth = system.parental.restrict3D ? 0 : Stereo3D.percent(slider: Stereo3D.storedSlider)
        let options = system.profile.coreOptions
        let notes = try await Task.detached(priority: .userInitiated) {
            try Self.loadBlocking(host: host, corePath: path, game: url, dirs: dirs, preferVulkan: preferVulkan,
                                  resolutionFactor: factor, depth: depth, options: options)
        }.value
        appliedDepth = depth
        notes.forEach { appendLog($0) }
        appendLog("system: \(options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))\(system.powerSaving ? ", power saving" : "")")
        if stopAfterLoad {
            // The view went away while the game was loading.
            stopAfterLoad = false
            host.stop()
            throw Self.error(String(localized: "已取消"))
        }
        gameURL = url
        host.speed = 1
        speed = 1
        keyTaps = KeyTaps.isOn(gameKey)
        keyTapPoint = KeyTaps.point(for: gameKey)
        status = String(localized: "\(host.coreName) \(host.coreVersion) · \(Int(host.frameSize.width))×\(Int(host.frameSize.height)) · \(host.hardwareRenderer ?? String(localized: "软件渲染"))")
        appendLog("renderer: \(host.hardwareRenderer ?? "software")")
        startAudio()
    }

    /// The blocking part of `load(game:)`; returns log lines for the main actor.
    nonisolated private static func loadBlocking(host: FALibretroCore, corePath: String, game url: URL,
                                                 dirs: (system: URL, saves: URL), preferVulkan: Bool,
                                                 resolutionFactor: Int, depth: Int, options: [String: String]) throws -> [String] {
        var notes: [String] = []
        host.variables = defaultVariables
        try host.loadCore(path: corePath)
        ensureDSPComponentPlaceholder(saves: dirs.saves)
        var vulkanDevice: String?
        if preferVulkan {
            do { vulkanDevice = try host.probeVulkan() } catch { notes.append(String(localized: "Vulkan 不可用：\(error.localizedDescription)")) }
        }
        if let device = vulkanDevice {
            do {
                try loadGame(host: host, game: url, dirs: dirs, vulkan: true, resolutionFactor: resolutionFactor, depth: depth, options: options)
            } catch {
                notes.append(String(localized: "Vulkan（\(device)）启动失败，改用软件渲染：\(error.localizedDescription)"))
                try loadGame(host: host, game: url, dirs: dirs, vulkan: false, resolutionFactor: 1, depth: depth, options: options)
            }
        } else {
            try loadGame(host: host, game: url, dirs: dirs, vulkan: false, resolutionFactor: 1, depth: depth, options: options)
        }
        return notes
    }

    nonisolated private static func loadGame(host: FALibretroCore, game url: URL, dirs: (system: URL, saves: URL),
                                             vulkan: Bool, resolutionFactor: Int, depth: Int, options: [String: String]) throws {
        var variables = defaultVariables
        variables.merge(Stereo3D.coreOptions(percent: depth)) { _, new in new }
        variables.merge(options) { _, new in new }
        if vulkan {
            variables["citra_graphics_api"] = "Vulkan"
            variables["citra_use_hw_shader"] = "enabled"
            variables["citra_resolution_factor"] = String(resolutionFactor)
        }
        host.variables = variables
        host.vulkanEnabled = vulkan
        host.vulkanAsyncReadback = asyncReadback
        host.unthrottled = benchmarkUnthrottled
        try host.loadGame(path: url.path, systemDirectory: dirs.system.path, saveDirectory: dirs.saves.path)
    }

    /// Starts the emulation thread if needed and lets it run.
    func start() {
        guard host.gameLoaded, !loading else { return }
        host.start(); host.resume(); running = true
        #if os(iOS)
        // The system does not promise an end for every interruption; a game
        // the player resumes plays again, and later configuration changes
        // restart the engine as usual.
        audioInterrupted = false
        // 系统设置 › 声音's 把音乐停掉 (11-05): the game holds the audio
        // from here until it is closed; activating a session that does not
        // mix stops the music app.
        Self.audioQueue.async {
            AudioPolicy.shared.gameStarts()
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        ensureAudioRunning(reason: "resume")
        #endif
        setVolume(1)
        // The game's own sound is on: the console's sounds keep quiet.
        ConsoleSounds.shared.gameAudio = true
    }
    func pause() { host.pause(); running = false; setVolume(0); ConsoleSounds.shared.gameAudio = false }
    /// On the audio queue too, after the start it may still be waiting for.
    private func setVolume(_ value: Float) {
        guard let engine else { return }
        // Running: as loud as the console's volume slider says (round 20);
        // silent while another app's music plays, with 游戏不出声 (11-05).
        // (11-07: and silent in a silent test run, `--foldarc-silent`.)
        let volume = AudioPolicy.shared.gameYields || SilentRun.on ? 0 : value * ConsoleVolume.shared.gain
        Self.audioQueue.async { engine.mainMixerNode.outputVolume = volume }
    }
    func resume() { start() }
    func stop() {
        if loading { stopAfterLoad = true; return }   // finished by load(game:)
        host.stop(); running = false
        ConsoleSounds.shared.gameAudio = false
        softwareStop = nil
        // The render block keeps reading the host's ring buffer (silence once
        // the core has stopped) until the queue gets to this. Then the audio
        // is the console's again (AudioPolicy: a game that stopped the music
        // lets it go on).
        let stopping = engine
        Self.audioQueue.async {
            stopping?.stop()
            #if os(iOS)
            AudioPolicy.shared.gameEnds()
            #endif
        }
        engine = nil
        #if os(iOS)
        audioObservers.engine = nil
        #endif
        top = nil; bottom = nil
    }

    // MARK: Save states

    /// The manual slot of the running game (HOME "保存进度" / "读取进度").
    private var gameURL: URL?
    var stateURL: URL? { gameURL.map(SaveStates.manual(for:)) }
    /// The running game's file, and its 存档位 in use (系统设置's page of it).
    var stateGame: URL? { gameURL }
    var stateSlot: Int { gameURL.map(SaveStates.currentSlot(for:)) ?? 1 }
    var hasSavedState: Bool { stateURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    /// Which core made a state; a state from another core is not loaded.
    var coreIdentity: String { "\(host.coreName) \(host.coreVersion)" }

    func saveState(completion: @escaping @MainActor (Result<Int, Error>) -> Void) {
        guard let url = stateURL else { completion(.failure(Self.error(String(localized: "没有正在运行的游戏")))); return }
        // (Past the free 存档位 only Pro saves; what is there can be read.)
        guard StateSlots.canSave(slot: stateSlot, pro: ProAccess.isPro) else {
            completion(.failure(Self.error(String(localized: "存档位 \(stateSlot) 要典藏卡带才能存（免费的是前 \(ProAccess.freeStateSlots) 个）")))); return
        }
        saveState(to: url, completion: completion)
    }
    func loadState(completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        guard let url = stateURL else { completion(.failure(Self.error(String(localized: "没有正在运行的游戏")))); return }
        loadState(from: url, completion: completion)
    }

    /// Serializes on a background queue (the host waits for the running frame
    /// and Azahar drains pending operations), writes atomically with a small
    /// JSON beside it (core, app version, time), reports back on the main
    /// actor. The game keeps running meanwhile.
    func saveState(to url: URL, completion: @escaping @MainActor (Result<Int, Error>) -> Void) {
        guard gameURL != nil else { completion(.failure(Self.error(String(localized: "没有正在运行的游戏")))); return }
        let host = host, core = coreIdentity
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Int, Error>
            do {
                let data = try host.saveState()
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                try SaveStates.writeInfo(.init(core: core, app: SaveStates.appVersion, saved: Date(), bytes: data.count), for: url)
                result = .success(data.count)
            } catch { result = .failure(error) }
            Task { @MainActor in
                if case .success(let bytes) = result { self.appendLog("state saved: \(bytes) bytes -> \(url.lastPathComponent)") }
                else if case .failure(let error) = result { self.appendLog("state save failed: \(error.localizedDescription)") }
                completion(result)
            }
        }
    }
    /// Loads a state made by this core. A state whose JSON names another core
    /// is refused before the core sees it (unserializing another version's
    /// state can fail half-way and leave the emulation inconsistent); states
    /// from before the JSON existed are tried as they are.
    func loadState(from url: URL, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        guard gameURL != nil else { completion(.failure(Self.error(String(localized: "没有正在运行的游戏")))); return }
        if let info = SaveStates.readInfo(for: url), info.core != coreIdentity {
            appendLog("state refused: made by \(info.core), running \(coreIdentity)")
            completion(.failure(Self.error(String(localized: "这份进度由另一个版本的核心（\(info.core)）保存，当前是 \(coreIdentity)；为避免出错没有读取。"))))
            return
        }
        let host = host
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Void, Error>
            do {
                let data = try Data(contentsOf: url)
                try host.loadState(data)
                result = .success(())
            } catch { result = .failure(error) }
            Task { @MainActor in
                if case .failure(let error) = result { self.appendLog("state load failed: \(error.localizedDescription)") }
                else { self.appendLog("state loaded <- \(url.lastPathComponent)") }
                completion(result)
            }
        }
    }
    /// Starts the emulation thread without running a frame, so a state can be
    /// loaded before the game shows anything (resuming a session).
    func startPaused() {
        guard host.gameLoaded, !loading else { return }
        host.startPaused()
    }
    nonisolated private static func error(_ message: String) -> NSError {
        NSError(domain: "FoldArc.Azahar", code: 20, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: Input

    func setButton(_ button: PadButton, pressed: Bool) {
        let id: FACoreButton
        switch button {
        case .a: id = .A; case .b: id = .B; case .x: id = .X; case .y: id = .Y
        case .l: id = .L; case .r: id = .R; case .zl: id = .ZL; case .zr: id = .ZR
        case .start: id = .start; case .select: id = .select
        case .up: id = .up; case .down: id = .down; case .left: id = .left; case .right: id = .right
        }
        host.setButton(id, pressed: pressed)
    }
    func setDirections(_ keys: Set<PadButton>) {
        for key in [PadButton.up, .down, .left, .right] { setButton(key, pressed: keys.contains(key)) }
    }
    func setCirclePad(_ point: Point) { host.setCirclePadX(Float(point.x), y: Float(point.y)) }
    func setCStick(_ point: Point) { host.setCStickX(Float(point.x), y: Float(point.y)) }
    func setTouch(_ point: Point?, pressed: Bool) {
        host.setTouchX(Float(point?.x ?? 0), y: Float(point?.y ?? 0), pressed: pressed)
    }

    // MARK: 倍速 (11-07)

    /// How many times as fast the software runs (1, 2, 4); the sound is off above 1.
    @Published private(set) var speed: Double = 1
    func setSpeed(_ value: Double) {
        host.speed = value
        speed = host.speed
        appendLog(String(localized: "倍速 \(Int(speed))×"))
        NSLog("[core] speed %.0fx", speed)
    }

    // MARK: 按键点屏 (11-07, KeyTaps)

    /// The software's own name for its settings (its library copy's).
    var gameKey: String? { gameURL?.deletingPathExtension().lastPathComponent }
    /// A B X Y tap the touch screen in this software.
    @Published private(set) var keyTaps = false
    /// Where they tap, on the touch screen's picture (0…1).
    @Published private(set) var keyTapPoint = KeyTaps.middle
    /// A key is tapping now (the marker fills).
    @Published private(set) var keyTapping = false
    private var tappingKeys: Set<PadButton> = []
    private var fingerDown = false
    private var fingerPoint: Point?
    /// 按键点屏's hint is on the upper screen now (a few seconds, once per
    /// software: KeyTapsHint).
    @Published private(set) var keyTapsHintShown = false
    private var keyTapsHint = KeyTapsHint()
    private var keyTapsHintTask: Task<Void, Never>?

    func setKeyTaps(_ on: Bool) {
        guard let game = gameKey else { return }
        KeyTaps.set(on, for: game)
        keyTaps = on
        if !on { releaseKeyTaps() }
        if on {
            // Found: the hint is not needed in this software any more.
            KeyTaps.setHinted(game)
            keyTapsHintTask?.cancel()
            keyTapsHintShown = false
        }
        appendLog(String(localized: "按键点屏 \(on ? "on" : "off")"))
        NSLog("[input] key taps %@", on ? "on" : "off")
    }
    /// A finger on the touch screen (CoreTouchScreen): where it is on the
    /// picture (0…1), nil as it lifts. Where it last was is where the keys
    /// tap, in this software, from then on.
    func finger(at point: Point?) {
        if let point {
            releaseKeyTaps()
            if !fingerDown { keyTapsHint.touched() }
            fingerDown = true
            fingerPoint = point.clamped
            // 系统设置 › 触摸屏's correction (round 23).
            setTouch(ConsoleSettings.shared.touch.apply(point.clamped), pressed: true)
        } else {
            fingerDown = false
            setTouch(nil, pressed: false)
            if let last = fingerPoint {
                keyTapPoint = last
                KeyTaps.remember(last, for: gameKey)
            }
        }
    }
    /// A B X Y with 按键点屏 on: down touches the screen where the keys tap,
    /// up lets go (several held: the last one up). A finger on the screen
    /// has it: the keys then do nothing.
    func keyTap(_ key: PadButton, down: Bool) {
        if down {
            guard !fingerDown else { return }
            let first = tappingKeys.isEmpty
            tappingKeys.insert(key)
            guard first else { return }
            setTouch(ConsoleSettings.shared.touch.apply(keyTapPoint), pressed: true)
            keyTapping = true
        } else {
            guard tappingKeys.remove(key) != nil, tappingKeys.isEmpty else { return }
            setTouch(nil, pressed: false)
            keyTapping = false
        }
    }
    private func releaseKeyTaps() {
        guard !tappingKeys.isEmpty else { return }
        tappingKeys.removeAll()
        setTouch(nil, pressed: false)
        keyTapping = false
    }
    /// One of A B X Y went down with 按键点屏 off. In software that looks
    /// played on the touch screen alone, the upper screen says once where
    /// the switch is.
    func keyWithoutTaps() {
        guard !keyTaps, keyTapsHint.pressed(), !KeyTaps.wasHinted(gameKey) else { return }
        KeyTaps.setHinted(gameKey)
        NSLog("[input] key taps: the hint shown")
        keyTapsHintTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { keyTapsHintShown = true }
        keyTapsHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.4)) { self.keyTapsHintShown = false }
        }
    }
    /// The 3D slider moved (see Stereo3D). The core takes it before its next
    /// frame; the game reads the new slider position, and the picture turns
    /// red/cyan while it is above 0.
    func set3DDepth(_ percent: Int) {
        let options = Stereo3D.coreOptions(percent: percent)
        let value = Int(options["citra_factor_3d"] ?? "0") ?? 0
        guard value != appliedDepth else { return }
        appliedDepth = value
        for (key, option) in options.sorted(by: { $0.key < $1.key }) { host.setVariable(key, value: option) }
        appendLog("3D depth \(value)%")
    }
    /// The software is sampling its microphone (FALibretroCore).
    var micListening: Bool { host.micListening }
    /// MIC held or let go (see FALibretroCore.micBlowing).
    func setMicBlowing(_ blowing: Bool) {
        guard host.micBlowing != blowing else { return }
        host.micBlowing = blowing
        appendLog(blowing ? "mic: breath" : "mic: quiet")
    }

    // MARK: Audio

    /// Homebrew built with libctru reads `sdmc:/3ds/dspfirm.cdc` in `ndspInit()`
    /// and plays nothing when it is missing. Azahar's HLE DSP (FoldArc's only
    /// audio mode) never runs that component — `DspHle::LoadComponent` just logs
    /// a hash of it — so a placeholder is enough. It contains no DSP code and a
    /// file the user put there is never replaced. The core's user folder is
    /// `<saves>/Azahar/` because `citra_use_libretro_save_path` stays at its
    /// "LibRetro Default".
    nonisolated static func ensureDSPComponentPlaceholder(saves: URL) {
        let file = saves.appendingPathComponent("Azahar/sdmc/3ds/dspfirm.cdc")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        var data = Data("FoldArc placeholder for Azahar's HLE audio. It contains no DSP code; the HLE DSP does not run this file, but homebrew looks for it before it plays sound.\n".utf8)
        data.append(Data(count: max(0, 4096 - data.count)))
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Activating the audio session and starting or stopping the engine can
    /// block (the system flags each call on the main thread as a hang risk:
    /// 12 runtime faults in a four-game UI test run, 10-27). They run here, in
    /// order, so a stop always follows the start it belongs to.
    private static let audioQueue = DispatchQueue(label: "FoldArc.audio", qos: .userInitiated)

    private func startAudio() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: host.sampleRate, channels: 2, interleaved: true) else { return }
        let host = self.host
        let mix = SoundMix.shared
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let base = buffers[0].mData else { return noErr }
            let samples = base.assumingMemoryBound(to: Int16.self)
            let got = Int(host.readAudio(into: samples, frames: UInt(frameCount)))
            // 系统设置 › 声音: stereo as it comes, mono or wider (round 23).
            mix.apply(samples, frames: got)
            if got < Int(frameCount) {
                // Underrun: silence the remainder rather than repeat stale audio.
                (samples + got * 2).update(repeating: 0, count: (Int(frameCount) - got) * 2)
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        #if DEBUG
        let meter = mixerMeter
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in meter.add(buffer) }
        #endif
        // Owned from here on, so pause() mutes it and stop() stops it even
        // before the queue has started it.
        self.engine = engine
        #if os(iOS)
        observeEngine(engine)
        #endif
        let sampleRate = host.sampleRate
        Self.audioQueue.async { [weak self] in
            #if os(iOS)
            // As 系统设置 › 声音 says (AudioPolicy, 11-05).
            AudioPolicy.shared.configure("game audio")
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            let line: String
            do {
                try engine.start()
                let out = engine.outputNode.outputFormat(forBus: 0)
                line = String(format: "audio engine running: core %.0f Hz -> output %.0f Hz × %d ch", sampleRate, out.sampleRate, Int(out.channelCount))
            } catch { line = "audio engine: \(error.localizedDescription)" }
            DispatchQueue.main.async { self?.appendLog(line) }
        }
    }

    #if os(iOS)
    /// Starts the engine again if something has stopped it: an audio
    /// interruption (a call, Siri, an alarm), a change of output hardware the
    /// engine could not follow, the system suspending the app. Nothing
    /// restarted it before 10-28, so a game resumed after one of these could
    /// stay silent. Cheap when the engine runs (checked on the audio queue,
    /// after any start still queued there).
    private func ensureAudioRunning(reason: String) {
        guard let engine else { return }
        Self.audioQueue.async { [weak self] in
            guard !engine.isRunning else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            let line: String
            do { try engine.start(); line = "audio engine restarted (\(reason))" }
            catch { line = "audio engine restart failed (\(reason)): \(error.localizedDescription)" }
            DispatchQueue.main.async { self?.appendLog(line) }
        }
    }

    /// The engine stops itself when the output hardware changes in a way it
    /// cannot follow, then posts this (AVAudioEngine.h). While the game is
    /// paused it stays stopped; the next resume starts it.
    private func observeEngine(_ engine: AVAudioEngine) {
        audioObservers.engine = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine === engine else { return }
                self.appendLog("audio engine configuration changed")
                if self.running && !self.audioInterrupted { self.ensureAudioRunning(reason: "configuration change") }
            }
        }
    }

    /// A call, Siri or an alarm takes the audio session and stops the engine;
    /// a media-services reset invalidates it. iOS 27 reports an interruption
    /// as the session becoming inactive and, later, a resumption
    /// recommendation; earlier versions as one notification with began /
    /// ended, deprecated from 27.0 (AVAudioSessionTypes.h, iOS 27.1 SDK).
    private func observeAudioSession() {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        if #available(iOS 27.0, *) {
            tokens.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] note in
                let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
                guard context?.source != .app else { return }   // FoldArc's own deactivation (none today)
                let detail = context?.interruptionContext.map { "reason \($0.reason.rawValue)" } ?? ""
                MainActor.assumeIsolated { self?.audioInterruption(began: true, detail: detail) }
            })
            tokens.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main) { [weak self] note in
                let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
                let detail = context.map { $0.recommendation == .shouldResume ? "should resume" : "should not resume" } ?? ""
                MainActor.assumeIsolated { self?.audioInterruption(began: false, detail: detail) }
            })
        } else {
            tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                let detail = type == .ended && options.contains(.shouldResume) ? "should resume" : ""
                MainActor.assumeIsolated { self?.audioInterruption(began: type == .began, detail: detail) }
            })
        }
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildAudioAfterReset() }
        })
        // 游戏不出声 (11-05): another app's primary audio began or ended.
        tokens.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                // (…HintTypeBegin is 1, AVAudioSessionTypes.h.)
                self.appendLog("other audio \(raw == 1 ? "began" : "ended")\(AudioPolicy.shared.otherAudio == .yield ? " (game quiet while it plays)" : "")")
                self.setVolume(self.running ? 1 : 0)
            }
        })
        audioObservers.session = tokens
    }

    /// An audio interruption does not pause the game by itself: a call or
    /// Siri makes the scene inactive and the play view pauses it for that; an
    /// alarm does not, and the game goes on without sound until the session
    /// can resume. FoldArc's session mixes with other audio unless 系统设置 ›
    /// 声音 says 把音乐停掉 (AudioPolicy), so it comes back whatever the
    /// recommendation.
    private func audioInterruption(began: Bool, detail: String) {
        appendLog("audio session \(began ? "interrupted" : "can resume")\(detail.isEmpty ? "" : " (\(detail))")")
        audioInterrupted = began
        if !began && running { ensureAudioRunning(reason: "interruption ended") }
    }

    /// After a media-services reset every audio object is invalid: the loaded
    /// game gets a new engine (AVAudioSessionTypes.h).
    private func rebuildAudioAfterReset() {
        appendLog("media services were reset; rebuilding the audio engine")
        audioObservers.engine = nil
        if let old = engine { Self.audioQueue.async { old.stop() } }
        engine = nil
        audioInterrupted = false
        guard host.gameLoaded else { return }
        startAudio()
        setVolume(running ? 1 : 0)
    }
    #endif

    #if DEBUG && os(iOS)
    /// `--foldarc-core-input-script=…,<s>:AUDIOINT|AUDIOCFG|AUDIORESET`: what
    /// the system does, without a phone call or new hardware. AUDIOINT stops
    /// the engine, posts the interruption, and `seconds` later its end;
    /// AUDIOCFG stops the engine and posts its configuration change;
    /// AUDIORESET posts a media-services reset. The notifications carry no
    /// userInfo: their context objects can only be made by the system.
    func debugSimulateAudio(_ event: String, seconds: Double = 6) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        switch event {
        case "AUDIOINT":
            guard let engine else { return }
            // Post-mixer level just before, and in the second after the restart:
            // sound before, sound after = the restarted engine plays.
            let before = mixerMeter.take()
            appendLog(String(format: "simulated interruption: mixer out before rms %.4f peak %.3f", before.rms, before.peak))
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 1.0) { [weak self] in
                guard let self else { return }
                let after = self.mixerMeter.take()
                self.appendLog(String(format: "simulated interruption: mixer out in the second after the restart rms %.4f peak %.3f", after.rms, after.peak))
            }
            Self.audioQueue.async {
                engine.stop()
                DispatchQueue.main.async {
                    if #available(iOS 27.0, *) {
                        center.post(name: AVAudioSession.didBecomeInactiveNotification, object: session)
                    } else {
                        center.post(name: AVAudioSession.interruptionNotification, object: session,
                                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                        if #available(iOS 27.0, *) {
                            center.post(name: AVAudioSession.resumptionRecommendationNotification, object: session)
                        } else {
                            center.post(name: AVAudioSession.interruptionNotification, object: session,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
                        }
                    }
                }
            }
        case "AUDIOCFG":
            guard let engine else { return }
            Self.audioQueue.async {
                engine.stop()
                DispatchQueue.main.async { center.post(name: .AVAudioEngineConfigurationChange, object: engine) }
            }
        case "AUDIORESET":
            center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: session)
        default: break
        }
    }
    #endif

    private func appendLog(_ line: String, echo: Bool = true) {
        log.append(line)
        if log.count > 400 { log.removeFirst(log.count - 400) }
        #if DEBUG
        if echo { NSLog("[azahar] %@", line) }
        #endif
    }
}

extension AzaharSession: FALibretroCoreDelegate {
    nonisolated func core(_ core: FALibretroCore, didPresentTop top: CGImage?, bottom: CGImage?) {
        // Emulation thread. Keep only the newest frame; publish on main at most once per runloop turn.
        guard mailbox.post(top: top, bottom: bottom) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let (t, b) = self.mailbox.take()
            self.top = t; self.bottom = b
            self.fpsWindowFrames += 1
            let elapsed = Date().timeIntervalSince(self.fpsWindowStart)
            if elapsed >= 1 {
                self.framesPerSecond = Double(self.fpsWindowFrames) / elapsed
                self.fpsWindowFrames = 0; self.fpsWindowStart = Date()
                #if DEBUG
                self.fpsLogCounter += 1
                if self.fpsLogCounter % 5 == 0 {
                    NSLog("[azahar] %.1f fps presented (core frames %llu)", self.framesPerSecond, self.host.presentedFrames)
                    let f = self.host.takeFrameStats()
                    NSLog("[azahar] frames 5s: %llu, run avg %.2f ms max %.2f ms; %@ read-back %llu, fence wait avg %.2f ms max %.2f ms; waited in sync-index %.1f ms, for a slot %.1f ms",
                          f.frames, f.runAverage, f.runMax, (self.host.vulkanAsyncReadback ? "async" : "sync") as NSString, f.readbacks,
                          f.readbackWaitAverage, f.readbackWaitMax, f.syncIndexWait, f.slotWait)
                    #if os(iOS)
                    // A core test's frames also go into the trace file: on an
                    // iPhone the log cannot be read from outside, the file can.
                    if ProcessInfo.processInfo.arguments.contains("--foldarc-core-test") {
                        let file = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--foldarc-core-file=") }.map { String($0.dropFirst("--foldarc-core-file=".count)) } ?? "first file"
                        let line = String(format: "core test (%@) frames 5s: %llu, run avg %.2f ms max %.2f ms, presented %.1f a second", file as NSString, f.frames, f.runAverage, f.runMax, self.framesPerSecond)
                        Task { @MainActor in OrientationTrace.shared.event(line) }
                    }
                    #endif
                    let a = self.host.takeAudioStats()
                    let m = self.mixerMeter.take()
                    NSLog("[azahar] audio 5s: core %llu fr, output read %llu fr, underrun %llu fr, buffered %llu fr, int16 peak %.0f rms %.1f; mixer out rms %.4f peak %.3f, volume %.3f",
                          a.framesIn, a.framesOut, a.underrunFrames, a.buffered, a.peak, a.rms, m.rms, m.peak, self.engine?.mainMixerNode.outputVolume ?? -1)
                }
                #endif
            }
        }
    }
    nonisolated func core(_ core: FALibretroCore, didLog line: String, level: Int) {
        guard level >= 1 else { return }   // skip RETRO_LOG_DEBUG
        let echoed = core.echoLogToConsole  // already printed synchronously by the host
        DispatchQueue.main.async { [weak self] in self?.appendLog(line, echo: !echoed) }
    }
    nonisolated func core(_ core: FALibretroCore, didRequestMessage message: String) {
        // A core can repeat a message without end (10-27: a core stuck in an
        // error loop queued ~990 000 of them in 47 s and the main thread did
        // nothing else). Count repeats instead of queueing them, and keep at
        // most one main-thread publish pending.
        guard messages.post(message) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for (text, count) in self.messages.take() {
                // The status line shows a message's first line: a CPU exception
                // report runs on with every register (10-28: one .3dsx
                // starting another .3dsx). The log keeps the whole text.
                self.lastMessage = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
                self.appendLog(count > 1 ? "[msg] \(text) (×\(count))" : "[msg] \(text)")
                if self.softwareStop == nil, let stop = SoftwareStop(coreMessage: text) {
                    self.softwareStop = stop
                    self.appendLog("software stopped: \(stop.title)")
                }
            }
        }
    }
    nonisolated func core(_ core: FALibretroCore, didStopWithReason reason: String) {
        DispatchQueue.main.async { [weak self] in self?.running = false; self?.status = String(localized: "核心已停止：\(reason)") }
    }
}

/// A notification token, removed with its holder.
private final class ObserverToken {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

#if os(iOS)
/// Notification tokens of one session, removed with it.
private final class AudioObservers {
    var session: [NSObjectProtocol] = [] {
        didSet { oldValue.forEach { NotificationCenter.default.removeObserver($0) } }
    }
    var engine: NSObjectProtocol? {
        didSet { if let oldValue { NotificationCenter.default.removeObserver(oldValue) } }
    }
    deinit {
        session.forEach { NotificationCenter.default.removeObserver($0) }
        if let engine { NotificationCenter.default.removeObserver(engine) }
    }
}
#endif

#if DEBUG
/// Post-mixer level meter for the DEBUG audio log line (tap thread -> main).
private final class MixerMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = 0, squares = 0.0
    private var peak: Float = 0
    func add(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        var sq = 0.0
        var pk: Float = 0
        for c in 0..<channels {
            for i in 0..<frames { let v = data[c][i]; sq += Double(v * v); pk = max(pk, abs(v)) }
        }
        lock.lock(); samples += frames * channels; squares += sq; peak = max(peak, pk); lock.unlock()
    }
    func take() -> (rms: Double, peak: Float) {
        lock.lock(); defer { samples = 0; squares = 0; peak = 0; lock.unlock() }
        return (samples > 0 ? (squares / Double(samples)).squareRoot() : 0, peak)
    }
}
#endif

#else
/// Stub for builds without the Objective-C++ host (Mac preview, logic checks):
/// same surface, never available.
@MainActor final class AzaharSession: ObservableObject {
    @Published private(set) var top: CGImage?
    @Published private(set) var bottom: CGImage?
    @Published private(set) var running = false
    @Published private(set) var status = String(localized: "此构建不含核心")
    @Published private(set) var lastMessage: String?
    @Published private(set) var softwareStop: SoftwareStop?
    @Published private(set) var log: [String] = []
    @Published private(set) var framesPerSecond: Double = 0
    var loading: Bool { false }
    enum Renderer: String { case vulkan, software }
    static var corePath: String? { nil }
    static var isCoreAvailable: Bool { false }
    static func installCompressedReader() {}
    static func compressForTests() {}
    func load(game url: URL) async throws {
        throw NSError(domain: "FoldArc.Azahar", code: 1, userInfo: [NSLocalizedDescriptionKey: status])
    }
    func start() {}
    func pause() {}
    func resume() {}
    func stop() {}
    func setButton(_ button: PadButton, pressed: Bool) {}
    func setDirections(_ keys: Set<PadButton>) {}
    func setCirclePad(_ point: Point) {}
    func setCStick(_ point: Point) {}
    func setTouch(_ point: Point?, pressed: Bool) {}
    var gameKey: String? { nil }
    var speed: Double { 1 }
    func setSpeed(_ value: Double) {}
    var keyTaps: Bool { false }
    var keyTapPoint: Point { KeyTaps.middle }
    var keyTapping: Bool { false }
    var keyTapsHintShown: Bool { false }
    func setKeyTaps(_ on: Bool) {}
    func finger(at point: Point?) {}
    func keyTap(_ key: PadButton, down: Bool) {}
    func keyWithoutTaps() {}
    func set3DDepth(_ percent: Int) {}
    func setMicBlowing(_ blowing: Bool) {}
    var micListening: Bool { false }
    var hasSavedState: Bool { false }
    var stateGame: URL? { nil }
    var stateSlot: Int { 1 }
    func saveState(completion: @escaping @MainActor (Result<Int, Error>) -> Void) {
        completion(.failure(NSError(domain: "FoldArc.Azahar", code: 1, userInfo: [NSLocalizedDescriptionKey: status])))
    }
    func loadState(completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        completion(.failure(NSError(domain: "FoldArc.Azahar", code: 1, userInfo: [NSLocalizedDescriptionKey: status])))
    }
    func saveState(to url: URL, completion: @escaping @MainActor (Result<Int, Error>) -> Void) { saveState(completion: completion) }
    func loadState(from url: URL, completion: @escaping @MainActor (Result<Void, Error>) -> Void) { loadState(completion: completion) }
    func startPaused() {}
}
#endif

#if FOLDARC_CORE
/// What is inside a compressed game file, from the core's reader.
final class CoreCompressedSource: CompressedSource {
    private let file: FACompressedGameFile
    init(file: FACompressedGameFile) { self.file = file }
    var size: UInt64 { file.size }
    func read(offset: UInt64, count: Int) -> Data { file.read(offset: offset, count: UInt(max(0, count))) }
    func close() { file.close() }
}
#endif

/// Where save states live, and the small JSON written next to each one
/// (which core made it, when). Shared by the session and the library.
enum SaveStates {
    static var folder: URL { Storage.root.appendingPathComponent("Azahar/states", isDirectory: true) }
    /// The manual state (HOME "保存进度" / "读取进度") of a game file, keyed
    /// by the managed copy's name (its SHA-256 for library imports): the one
    /// in the 存档位 in use (StateSlots; the first until another is chosen).
    static func manual(for game: URL) -> URL { manual(for: game, slot: currentSlot(for: game)) }
    static func manual(for game: URL, slot: Int) -> URL {
        folder.appendingPathComponent(StateSlots.fileName(base: base(game), slot: slot))
    }
    static func base(_ game: URL) -> String { game.deletingPathExtension().lastPathComponent }
    /// The 存档位 each game uses, by the game's name (only those not the first).
    static let slotsKey = "FoldArc.stateSlots"
    static func currentSlot(for game: URL) -> Int {
        let slot = (UserDefaults.standard.dictionary(forKey: slotsKey)?[base(game)] as? Int) ?? 1
        return min(max(slot, 1), StateSlots.most)
    }
    static func setCurrentSlot(_ slot: Int, for game: URL) {
        var all = UserDefaults.standard.dictionary(forKey: slotsKey) ?? [:]
        if slot <= 1 { all[base(game)] = nil } else { all[base(game)] = slot }
        UserDefaults.standard.set(all, forKey: slotsKey)
    }
    /// The 存档位 of a game with something in them.
    static func usedSlots(for game: URL) -> Set<Int> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let name = base(game)
        return Set(names.compactMap { StateSlots.slot(ofFile: $0, base: name) })
    }
    /// Saved when FoldArc leaves the foreground with a game running, so the
    /// session survives the system ending FoldArc in the background. Offered
    /// as "继续上次" in the library; gone once used, or when the software is
    /// closed (closing discards unsaved progress).
    static func resume(for game: URL) -> URL {
        folder.appendingPathComponent(game.deletingPathExtension().lastPathComponent + ".resume.state")
    }
    static func info(for state: URL) -> URL { state.appendingPathExtension("json") }
    struct Info: Codable, Equatable {
        var core: String
        var app: String
        var saved: Date
        var bytes: Int
    }
    static func readInfo(for state: URL) -> Info? {
        guard let data = try? Data(contentsOf: info(for: state)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Info.self, from: data)
    }
    static func writeInfo(_ value: Info, for state: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: info(for: state), options: .atomic)
    }
    /// When the resume state of this game was saved; nil without one.
    static func resumeDate(for game: URL) -> Date? {
        let url = resume(for: game)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return readInfo(for: url)?.saved
            ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }
    static func removeResume(for game: URL) {
        let url = resume(for: game)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: info(for: url))
    }
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

/// Latest-frame handoff between the emulation thread and the main actor.
/// Core messages, emulation thread -> main: consecutive repeats are counted,
/// at most 20 distinct messages wait, and one main-thread publish is pending.
final class MessageMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [(text: String, count: Int)] = []
    private var scheduled = false
    /// Returns true when the caller should schedule a main-thread publish.
    func post(_ text: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let last = pending.last, last.text == text {
            pending[pending.count - 1].count += 1
        } else {
            pending.append((text, 1))
            if pending.count > 20 { pending.removeFirst(pending.count - 20) }
        }
        let schedule = !scheduled
        scheduled = true
        return schedule
    }
    func take() -> [(text: String, count: Int)] {
        lock.lock(); defer { lock.unlock() }
        scheduled = false
        let taken = pending
        pending = []
        return taken
    }
}

final class FrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var top: CGImage?
    private var bottom: CGImage?
    private var scheduled = false
    /// Returns true when the caller should schedule a main-thread publish.
    func post(top: CGImage?, bottom: CGImage?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        self.top = top; self.bottom = bottom
        let schedule = !scheduled
        scheduled = true
        return schedule
    }
    func take() -> (CGImage?, CGImage?) {
        lock.lock(); defer { lock.unlock() }
        scheduled = false
        return (top, bottom)
    }
}

/// One emulated screen: nearest-neighbour scaling keeps the 3DS pixels crisp.
/// With 像素原尺寸显示 (round 18) the picture is drawn at a whole multiple of
/// its pixels, centred with a border; otherwise it fills the LCD.
struct CoreScreen: View {
    var image: CGImage?
    /// b41: an old TV's filter and whole pixels (OldTVScreen) instead of the
    /// settings' 画面滤镜 and 整数倍像素; nil, the settings.
    var screenFilter: ScreenFilter? = nil
    var wholePixels: Bool? = nil
    @AppStorage("FoldArc.retroPixels") private var retroPixels = false
    /// 画面滤镜 (round 31): smooth scaling for 柔和 and 老电视, the lines over it.
    @AppStorage(ScreenFilter.defaultsKey) private var filterID = ScreenFilter.sharp.rawValue
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        GeometryReader { proxy in
            if let image {
                let fit = Self.frame(for: image, in: proxy.size, scale: displayScale, wholePixels: wholePixels ?? retroPixels)
                let filter = screenFilter ?? ScreenFilter(rawValue: filterID) ?? .sharp
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(filter.smooths ? .medium : .none)
                    .saturation(filter == .crt ? 1.12 : 1)
                    .frame(width: fit.width, height: fit.height)
                    .overlay {
                        ScreenFilterOverlay(filter: filter, native: Self.native(image)).equatable()
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            } else {
                Rectangle().fill(.black)
                    .overlay(ProgressView().tint(.white.opacity(0.6)))
            }
        }
        .background(.black)
    }
    /// Which of the 3DS's screens a picture is, by its shape: the upper
    /// (5:3, 400 × 240 pixels) or the lower (4:3, 320 × 240), whatever its
    /// internal resolution.
    nonisolated static func native(_ image: CGImage) -> CGSize {
        Double(image.width) >= Double(image.height) * 1.5 ? CGSize(width: 400, height: 240) : CGSize(width: 320, height: 240)
    }
    /// The picture's size in points: at a whole multiple of its pixels when
    /// it fits at 1× or more and `wholePixels` asks for it, else the LCD.
    nonisolated static func frame(for image: CGImage, in size: CGSize, scale: Double, wholePixels: Bool) -> CGSize {
        guard wholePixels, image.width > 0, image.height > 0 else { return size }
        let k = floor(min(size.width * scale / Double(image.width), size.height * scale / Double(image.height)))
        guard k >= 1 else { return size }
        return CGSize(width: Double(image.width) * k / scale, height: Double(image.height) * k / scale)
    }
}

/// 画面滤镜 (round 31) over one of the game's screens: `native` is the
/// screen's 3DS pixels (400 × 240 upper, 320 × 240 lower), so the lines fall
/// between them whatever the picture's internal resolution; they fade out
/// where a pixel is smaller than about a point (ScreenFilter.strength).
struct ScreenFilterOverlay: View, Equatable {
    var filter: ScreenFilter
    var native: CGSize
    var body: some View {
        switch filter {
        case .sharp, .smooth: Color.clear
        case .scanlines: lines(0.34)
        case .lcd: grid
        case .crt:
            ZStack {
                lines(0.42)
                EllipticalGradient(stops: [.init(color: .clear, location: 0.58), .init(color: .black.opacity(0.42), location: 1)])
            }
        }
    }
    private func lines(_ opacity: Double) -> some View {
        Canvas { context, size in
            let rows = max(1, Int(native.height))
            let h = size.height / Double(rows)
            let strength = ScreenFilter.strength(pointsPerPixel: h)
            guard strength > 0 else { return }
            var path = Path()
            for row in 0..<rows { path.addRect(CGRect(x: 0, y: (Double(row) + 0.56) * h, width: size.width, height: h * 0.44)) }
            context.fill(path, with: .color(.black.opacity(opacity * strength)))
        }
    }
    private var grid: some View {
        Canvas { context, size in
            let columns = max(1, Int(native.width)), rows = max(1, Int(native.height))
            let w = size.width / Double(columns), h = size.height / Double(rows)
            let strength = ScreenFilter.strength(pointsPerPixel: min(w, h))
            guard strength > 0 else { return }
            let line = max(0.3, min(w, h) * 0.18)
            var path = Path()
            for column in 0...columns { path.addRect(CGRect(x: Double(column) * w - line / 2, y: 0, width: line, height: size.height)) }
            for row in 0...rows { path.addRect(CGRect(x: 0, y: Double(row) * h - line / 2, width: size.width, height: line)) }
            context.fill(path, with: .color(.black.opacity(0.3 * strength)))
        }
    }
}

// MARK: - The old TVs

extension TVArt.RGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

extension TVArt {
    /// A drawing into `context`, its top left at the origin, `k` wide.
    static func draw(_ drawing: Drawing, in context: GraphicsContext, width k: Double) {
        for shape in drawing.shapes {
            var layer = context
            layer.opacity = shape.opacity
            let n = shape.numbers
            var path = Path()
            switch shape.kind {
            case "R":
                let rect = CGRect(x: n[0] * k, y: n[1] * k, width: n[2] * k, height: n[3] * k)
                let corner = min(n[4] * k, rect.width / 2, rect.height / 2)
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner), style: .circular)
            case "C":
                path.addEllipse(in: CGRect(x: (n[0] - n[2]) * k, y: (n[1] - n[2]) * k, width: n[2] * 2 * k, height: n[2] * 2 * k))
            case "E":
                path.addEllipse(in: CGRect(x: (n[0] - n[2]) * k, y: (n[1] - n[3]) * k, width: n[2] * 2 * k, height: n[3] * 2 * k))
            case "D":
                for row in 0..<Int(n[3]) {
                    for column in 0..<Int(n[2]) {
                        let x = n[0] + Double(column) * n[4], y = n[1] + Double(row) * n[5]
                        path.addEllipse(in: CGRect(x: (x - n[6]) * k, y: (y - n[6]) * k, width: n[6] * 2 * k, height: n[6] * 2 * k))
                    }
                }
            case "G":
                for row in 0..<Int(n[3]) {
                    for column in 0..<Int(n[2]) {
                        let rect = CGRect(x: (n[0] + Double(column) * n[4]) * k, y: (n[1] + Double(row) * n[5]) * k, width: n[6] * k, height: n[7] * k)
                        let corner = min(rect.width, rect.height) / 2
                        path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner), style: .circular)
                    }
                }
            case "P":
                var point = CGPoint.zero
                for step in shape.steps {
                    switch step {
                    case let .move(x, y): point = CGPoint(x: x * k, y: y * k); path.move(to: point)
                    case let .line(x, y): point = CGPoint(x: x * k, y: y * k); path.addLine(to: point)
                    case let .horizontal(x): point = CGPoint(x: x * k, y: point.y); path.addLine(to: point)
                    case let .vertical(y): point = CGPoint(x: point.x, y: y * k); path.addLine(to: point)
                    case let .quad(cx, cy, x, y):
                        point = CGPoint(x: x * k, y: y * k)
                        path.addQuadCurve(to: point, control: CGPoint(x: cx * k, y: cy * k))
                    case .close: path.closeSubpath()
                    }
                }
            case "T":
                // On its baseline, as the sheet's SVG put it (near enough for
                // a clock's figures).
                guard let fill = shape.fill else { continue }
                var text = layer.resolve(Text(shape.text).font(.system(size: n[2] * k, weight: .medium, design: .monospaced)))
                text.shading = .color(fill.color)
                layer.draw(text, at: CGPoint(x: n[0] * k, y: n[1] * k), anchor: UnitPoint(x: 0.5, y: 0.8))
                continue
            default:
                continue
            }
            if let fill = shape.fill { layer.fill(path, with: .color(fill.color)) }
            if let stroke = shape.stroke, shape.lineWidth > 0 {
                layer.stroke(path, with: .color(stroke.color), lineWidth: shape.lineWidth * k)
            }
        }
    }
}

/// An old TV drawn as big as its frame allows, centred (nothing for 现代电视).
struct TVArtCanvas: View, Equatable {
    var set: TVSet
    var body: some View {
        Canvas { context, size in
            guard let drawing = TVArt.drawing(set) else { return }
            let k = min(size.width, size.height / drawing.height)
            context.translateBy(x: (size.width - k) / 2, y: (size.height - k * drawing.height) / 2)
            TVArt.draw(drawing, in: context, width: k)
        }
        .accessibilityHidden(true)
    }
}

/// The upper screen in an old TV (b41): the TV drawn as big as the frame
/// allows, and in its screen `picture` — drawn with the 画面滤镜 it is
/// given, filling its frame — with what a screen of that kind did to it
/// then (当年的画面) or nothing more (最好的画面). `shadow`: a soft shadow
/// under the TV, that part of its width (0: none).
struct OldTVView<Picture: View>: View {
    var set: TVSet
    var look: TVLook
    var shadow: Double = 0
    @ViewBuilder var picture: (ScreenFilter) -> Picture
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if let drawing = TVArt.drawing(set) {
                let k = min(size.width, size.height / drawing.height)
                let screen = CGRect(x: (size.width - k) / 2 + drawing.screen.minX * k,
                                    y: (size.height - k * drawing.height) / 2 + drawing.screen.minY * k,
                                    width: drawing.screen.width * k, height: drawing.screen.height * k)
                ZStack(alignment: .topLeading) {
                    if shadow > 0 {
                        TVArtCanvas(set: set).equatable()
                            .shadow(color: .black.opacity(0.55), radius: shadow * k, y: shadow * 0.5 * k)
                    } else {
                        TVArtCanvas(set: set).equatable()
                    }
                    OldTVScreen(tube: set.isTube, look: look, corner: drawing.screenCorner * k, picture: picture)
                        .frame(width: screen.width, height: screen.height)
                        .offset(x: screen.minX, y: screen.minY)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            } else {
                OldTVScreen(tube: set.isTube, look: look, corner: 0, picture: picture)
            }
        }
    }
}

/// An old TV's screen (b41): black round the upper screen (5:3, so bars
/// above and below on a 4:3 screen, at the sides on a 16:9 one), and the
/// look. 当年的画面 on a tube: 老电视's lines over the picture, light spread
/// a little round what is bright, the glass bowed and dark at its edges; on
/// an early flat panel: the picture soft, its blacks grey and a little
/// blue, light leaking at the corners. 最好的画面: the picture sharp and
/// even — drawn at a whole number of the TV's pixels to each of its own,
/// then made the screen's size smoothly (a tube's glass still over it).
struct OldTVScreen<Picture: View>: View {
    var tube: Bool
    var look: TVLook
    var corner: Double
    @ViewBuilder var picture: (ScreenFilter) -> Picture
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fit = TVArt.upperScreen(in: size)
            // One of the upper screen's 240 lines.
            let line = fit.height / 240
            let filter = look.filter(tube: tube)
            ZStack {
                Color.black
                Group {
                    switch (look, tube) {
                    case (.period, true):
                        ZStack {
                            picture(filter)
                            picture(.smooth).blur(radius: line * 1.6).blendMode(.screen).opacity(0.3)
                        }
                    case (.period, false):
                        picture(filter)
                            .blur(radius: line * 0.6, opaque: true)
                            .colorMultiply(Color(red: 0.97, green: 0.99, blue: 1))
                    case (.best, _):
                        // Whole pixels at or over the screen's size, then
                        // down to it smoothly: every pixel as big as the
                        // next, nothing blurred (b41: whole pixels alone left
                        // the picture at 1x in a screen 1.8x its size).
                        let k = max(1, (fit.width / 400).rounded(.up))
                        picture(filter)
                            .frame(width: 400 * k, height: 240 * k)
                            .drawingGroup()
                            .scaleEffect(fit.width / (400 * k))
                    }
                }
                .frame(width: fit.width, height: fit.height)
                if look == .period && !tube {
                    Color(red: 0.07, green: 0.075, blue: 0.095).blendMode(.screen)
                    PanelCornerLight().blendMode(.screen)
                }
                if tube {
                    EllipticalGradient(stops: [.init(color: .clear, location: 0.6),
                                               .init(color: .black.opacity(look == .period ? 0.42 : 0.28), location: 1)])
                    LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

/// An early flat panel's backlight showing at its four corners.
private struct PanelCornerLight: View {
    var body: some View {
        GeometryReader { proxy in
            let r = max(proxy.size.width, proxy.size.height) * 0.3
            ZStack {
                ForEach(0..<4, id: \.self) { corner in
                    RadialGradient(colors: [.white.opacity(0.08), .white.opacity(0)],
                                   center: UnitPoint(x: corner % 2 == 0 ? 0 : 1, y: corner < 2 ? 0 : 1), startRadius: 0, endRadius: r)
                }
            }
        }
    }
}

/// An old TV on the TV (b41): as big as it fits, a little room round it, on
/// a dim wall, its shadow under it.
struct OldTVRoom<Picture: View>: View {
    var set: TVSet
    var look: TVLook
    var size: CGSize
    @ViewBuilder var picture: (ScreenFilter) -> Picture
    var body: some View {
        let height = TVArt.drawing(set)?.height ?? 0.75
        let width = min(size.width * 0.92, size.height * 0.92 / height)
        ZStack {
            RadialGradient(colors: [Color(red: 0.17, green: 0.155, blue: 0.14), Color(red: 0.045, green: 0.04, blue: 0.036)],
                           center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: max(size.width, size.height) * 0.7)
            OldTVView(set: set, look: look, shadow: 0.025, picture: picture)
                .frame(width: width, height: width * height)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// TV模式 with nothing playing, on an old TV (b41): its blue screen, as a
/// set of those years showed with no picture coming in, saying what it
/// waits for.
struct OldTVNoSignal: View {
    var filter: ScreenFilter
    var body: some View {
        GeometryReader { proxy in
            let k = proxy.size.height / 240
            ZStack(alignment: .topLeading) {
                Color(red: 0.10, green: 0.22, blue: 0.74)
                Text("AV").font(.system(size: 17 * k, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.92))
                    .padding(.leading, 20 * k).padding(.top, 14 * k)
                VStack(spacing: 7 * k) {
                    Text("TV模式").font(.system(size: 30 * k, weight: .heavy, design: .rounded))
                    Text("在掌机上开启一个软件，画面会出现在这里").font(.system(size: 12 * k, weight: .semibold)).opacity(0.78)
                }
                .foregroundStyle(.white)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .saturation(filter == .crt ? 1.12 : 1)
            .overlay { ScreenFilterOverlay(filter: filter, native: CGSize(width: 400, height: 240)).equatable() }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bottom screen that forwards touches to the core as normalized coordinates.
/// 按键点屏's mark on the touch screen: a ring where A B X Y tap.
struct KeyTapMarker: View {
    var tapping: Bool
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.35), lineWidth: 3.5)
            Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.6)
            Circle().fill(Color.white.opacity(tapping ? 0.55 : 0)).padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .scaleEffect(tapping ? 0.86 : 1)
        .animation(.easeOut(duration: 0.08), value: tapping)
        .accessibilityHidden(true)
    }
}

/// The upper screen of a running software, and 倍速's mark in its corner
/// while it runs faster.
struct CoreTopScreen: View {
    @ObservedObject var session: AzaharSession
    var body: some View {
        CoreScreen(image: session.top)
            .overlay(alignment: .topTrailing) {
                if session.speed > 1 {
                    Text("\(Int(session.speed))×")
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(5)
                        .allowsHitTesting(false)
                        .accessibilityLabel("倍速 \(Int(session.speed)) 倍")
                        .accessibilityIdentifier("speed-mark")
                }
            }
            // 按键点屏's hint: once per software, a few seconds.
            .overlay(alignment: .bottom) {
                if session.keyTapsHintShown {
                    Text("只靠点屏幕玩？按 HOME 打开「按键点屏」，A B X Y 就能代替手指")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.62)))
                        .padding(6)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("keytaps-hint")
                }
            }
    }
}

struct CoreTouchScreen: View {
    @ObservedObject var session: AzaharSession
    var body: some View {
        GeometryReader { proxy in
            CoreScreen(image: session.bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        session.finger(at: Point(x: value.location.x / max(1, proxy.size.width), y: value.location.y / max(1, proxy.size.height)))
                    }
                    .onEnded { _ in session.finger(at: nil) })
                // 按键点屏: where A B X Y tap, faintly (filled while one does).
                .overlay {
                    if session.keyTaps {
                        KeyTapMarker(tapping: session.keyTapping, size: max(14, proxy.size.width * 0.07))
                            .position(x: session.keyTapPoint.x * proxy.size.width, y: session.keyTapPoint.y * proxy.size.height)
                            .allowsHitTesting(false)
                    }
                }
        }
        .accessibilityLabel("掌机触摸屏")
    }
}
