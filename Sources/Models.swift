import SwiftUI
import Combine

@MainActor final class LibraryModel: ObservableObject {
    @Published var games: [GameRecord] = []
    @Published var importing = false
    /// 0…1 while a copy is under way (the import button shows it).
    @Published private(set) var importProgress: Double?
    @Published var message: String?
    private let root = Storage.root
    private var indexURL: URL { root.appendingPathComponent("library.json") }

    /// Leftovers are cleared once per process: a library made again later
    /// (a scene reconnecting) could otherwise remove the file of an import
    /// still running in the first one.
    private static var clearedLeftovers = false
    init() {
        if !Self.clearedLeftovers {
            Self.clearedLeftovers = true
            let leftovers = ROMImporter.removeUnfinishedImports(root: root)
            if leftovers > 0 { NSLog("[library] removed %d unfinished import file(s)", leftovers) }
            // Move the console's storage into the Files folder now, before
            // anything can be put there by hand (Storage.consoleStorage()).
            _ = Storage.consoleStorage()
        }
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do { games = try JSONDecoder().decode([GameRecord].self, from: Data(contentsOf: indexURL)) }
            catch {
                // 11-22: the index that cannot be read is kept beside it, under a name of its own, before anything is
                // written there (an import would put one record over all the others).
                let kept = root.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: indexURL, to: kept)
                NSLog("[library] the index could not be read: kept as %@", kept.lastPathComponent)
                message = String(localized: "游戏库索引读取失败，原文件已保留：\(error.localizedDescription)")
            }
        }
        if !Self.finishedLeftoverCuts {
            Self.finishedLeftoverCuts = true
            finishLeftoverCuts()
        }
        refreshMetadataIfNeeded()
        // 铁皮盒: what the games already on the shelf bring (quietly: the
        // tin shows it as new when it is opened).
        TinBoxStore.shared.count(games.count)
    }
    private static var finishedLeftoverCuts = false
    /// Records imported before FoldArc read SMDH get their HOME Menu title,
    /// publisher and icon from the managed copy, once, in the background.
    private func refreshMetadataIfNeeded() {
        let stale = games.filter { ($0.metadataVersion ?? 0) < SMDH.metadataVersion }
        guard !stale.isEmpty else { return }
        let root = root
        Task { [weak self] in
            let refreshed = await Task.detached(priority: .utility) {
                stale.map { ROMImporter.refreshMetadata($0, root: root) }
            }.value
            self?.applyRefreshed(refreshed)
        }
    }
    private func applyRefreshed(_ refreshed: [GameRecord]) {
        let byID = Dictionary(refreshed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let next = games.map { byID[$0.id] ?? $0 }
        guard next != games else { return }
        do {
            try Storage.write(next, to: indexURL)
            games = next
        } catch { message = String(localized: "更新游戏信息时遇到问题：\(error.localizedDescription)") }
    }
    func importROM(_ source: URL) async {
        // 11-22: one at a time — a file handed over while another is being imported waits for it, not dropped.
        while importing { try? await Task.sleep(for: .milliseconds(200)) }
        importing = true
        defer { importing = false; importProgress = nil }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        // A file handed over by the system as a copy (AirDrop, Mail) arrives
        // in FoldArc's own Documents/Inbox; that copy is ours to clean up,
        // whether or not the import succeeds (a duplicate or a rejected file
        // used to leave it there). Files opened in place, and any file
        // elsewhere, are the user's own and never touched: only a file
        // directly inside this app's Inbox counts (15th round review: the
        // old test matched any path containing "/Documents/Inbox/", such as
        // a folder of that name in iCloud Drive).
        defer { if Self.isOwnInboxCopy(source) { try? FileManager.default.removeItem(at: source) } }
        do {
            let root = root
            let started = Date()
            let report: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor in if self?.importing == true { self?.importProgress = fraction } }
            }
            var record = try await Task.detached(priority: .userInitiated) {
                try ROMImporter.copyCoordinated(source, into: root, progress: report)
            }.value
            NSLog("[library] copied %lld bytes in %.1f s", record.byteCount, Date().timeIntervalSince(started))
            // 11-07: the original remembered (while its access is
            // still scoped), for the card's deletion to take it too.
            if !Self.isOwnInboxCopy(source), let bookmark = try? source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                record.originBookmark = bookmark
            }
            guard !games.contains(where: { $0.id == record.id }) else { throw ImportFailure.duplicate }
            let next = [record] + games
            try Storage.write(next, to: indexURL)
            games = next
            let imported = AzaharSession.isCoreAvailable
                ? String(localized: "已导入 \(record.title)（\(record.resolvedFormat.label)）。在游戏库里打开它即可用 Azahar 核心启动。")
                : String(localized: "已导入 \(record.title)（\(record.resolvedFormat.label)）。这个构建没有附带运行核心，文件已保存到游戏库。")
            // 铁皮盒: a new game may bring something into the tin.
            let fresh = TinBoxStore.shared.count(next.count)
            message = TinThing.arrivalLine(fresh, games: TinBoxStore.shared.games).map { imported + "\n\n" + $0 } ?? imported
        } catch {
            // 11-07: which file, then why; the log
            // keeps the kind, not the name.
            let reason: String
            if case .notSoftware(let file)? = error as? ImportFailure { reason = file.kind }
            else if let failure = error as? ImportFailure { reason = "\(failure)" }
            else { reason = "\((error as NSError).domain) \((error as NSError).code)" }
            NSLog("[library] not imported (.%@): %@", source.pathExtension.lowercased(), reason)
            message = ImportFailure.message(for: error, name: source.lastPathComponent)
        }
    }
    /// True for a file directly inside this app's Documents/Inbox.
    nonisolated static func isOwnInboxCopy(_ url: URL) -> Bool {
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        return url.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path == inbox.path
    }
    func remove(_ record: GameRecord) {
        do {
            let next = games.filter { $0.id != record.id }
            try Storage.write(next, to: indexURL)
            games = next
            // Remove only the managed copy (and its extracted icon), never the
            // original user-selected file.
            let copy = root.appendingPathComponent("ROMs").appendingPathComponent(record.fileName)
            // A session left suspended ends with the software; the instant-save
            // slot stays, as save data does (importing the same file again
            // finds it).
            SaveStates.removeResume(for: copy)
            try FileManager.default.removeItem(at: copy)
            if let icon = record.iconFileName {
                try? FileManager.default.removeItem(at: root.appendingPathComponent("Icons").appendingPathComponent(icon))
            }
        } catch { message = String(localized: "移除时遇到问题：\(error.localizedDescription)") }
    }

    // MARK: 删除 (the names say "cut" from the scissors it began as)

    /// A card deleted on the shelf: its game leaves the library at once; its copy
    /// and icon wait in `Cut/` while 撤销 is offered, then go (`finishCut`), and
    /// (11-07) the file it was imported from in Files with them; the game's own
    /// save data stay. (移除 in 数据管理 leaves the original where it is.)
    struct CutGame: Equatable {
        var record: GameRecord
        /// Where it stood in the library (撤销 puts it back there).
        var position: Int
    }
    private var cutFolder: URL { root.appendingPathComponent("Cut", isDirectory: true) }
    private func copyURL(_ record: GameRecord) -> URL { root.appendingPathComponent("ROMs").appendingPathComponent(record.fileName) }
    private func iconURL(_ icon: String) -> URL { root.appendingPathComponent("Icons").appendingPathComponent(icon) }

    func cut(_ record: GameRecord) -> CutGame? {
        guard let position = games.firstIndex(where: { $0.id == record.id }) else { return nil }
        let fm = FileManager.default
        let copy = copyURL(record), parked = cutFolder.appendingPathComponent(record.fileName)
        do {
            try fm.createDirectory(at: cutFolder, withIntermediateDirectories: true)
            try? fm.removeItem(at: parked)
            if fm.fileExists(atPath: copy.path) { try fm.moveItem(at: copy, to: parked) }
            let next = games.filter { $0.id != record.id }
            do { try Storage.write(next, to: indexURL) } catch {
                // The index could not be written: the copy goes back where it was.
                try? fm.moveItem(at: parked, to: copy)
                throw error
            }
            if let icon = record.iconFileName {
                let parkedIcon = cutFolder.appendingPathComponent("icon-" + icon)
                try? fm.removeItem(at: parkedIcon)
                try? fm.moveItem(at: iconURL(icon), to: parkedIcon)
            }
            games = next
            NSLog("[library] a card cut (%d left; 撤销 offered)", next.count)
            return CutGame(record: record, position: position)
        } catch {
            message = String(localized: "删除时遇到问题，游戏还在游戏库里：\(error.localizedDescription)")
            return nil
        }
    }
    /// 撤销: the game back in its place, its copy and icon where they were.
    func undoCut(_ cut: CutGame) {
        let fm = FileManager.default
        let copy = copyURL(cut.record), parked = cutFolder.appendingPathComponent(cut.record.fileName)
        // Imported again meanwhile: that one stays, the parked copy goes.
        guard !games.contains(where: { $0.id == cut.record.id }) else { finishCut(cut); return }
        if fm.fileExists(atPath: parked.path) {
            do { try fm.moveItem(at: parked, to: copy) } catch {
                message = String(localized: "撤销时遇到问题：\(error.localizedDescription)")
                return
            }
        }
        if let icon = cut.record.iconFileName { try? fm.moveItem(at: cutFolder.appendingPathComponent("icon-" + icon), to: iconURL(icon)) }
        var next = games
        next.insert(cut.record, at: min(cut.position, next.count))
        do {
            try Storage.write(next, to: indexURL)
            games = next
            NSLog("[library] cut undone")
        } catch { message = String(localized: "撤销时遇到问题：\(error.localizedDescription)") }
    }
    /// The cut stands: the parked copy and icon go, and the suspended
    /// session (as 移除 drops it), unless the game is back in the library.
    func finishCut(_ cut: CutGame) {
        let fm = FileManager.default
        let gone = !games.contains(where: { $0.id == cut.record.id })
        if gone { SaveStates.removeResume(for: copyURL(cut.record)) }
        try? fm.removeItem(at: cutFolder.appendingPathComponent(cut.record.fileName))
        if let icon = cut.record.iconFileName { try? fm.removeItem(at: cutFolder.appendingPathComponent("icon-" + icon)) }
        // 11-07: the file the
        // game was imported from goes too (the user's own file in Files),
        // once 撤销's time is over; a record without a bookmark (imported
        // before, or handed over as a copy) has nothing to delete.
        if gone, let bookmark = cut.record.originBookmark { Self.deleteOriginal(bookmark, of: cut.record.title) }
    }
    /// The imported file in Files deleted by its bookmark, under file
    /// coordination (it may be in iCloud Drive). Logged either way.
    nonisolated static func deleteOriginal(_ bookmark: Data, of title: String) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            NSLog("[library] the original of %@ is not where it was: nothing to delete", title); return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do { try FileManager.default.removeItem(at: target) } catch { failure = error }
        }
        if let problem = failure ?? coordinationError {
            NSLog("[library] the original of %@ could not be deleted: %@", title, problem.localizedDescription)
        } else {
            NSLog("[library] the original of %@ deleted from Files (.%@)", title, url.pathExtension.lowercased())
        }
    }
    /// Cuts FoldArc ended before they were finished (within 撤销's few
    /// seconds): finished now, once per process, as the library loads.
    private func finishLeftoverCuts() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: cutFolder.path)) ?? []
        guard !names.isEmpty else { return }
        for name in names {
            if !name.hasPrefix("icon-"), !games.contains(where: { $0.fileName == name }) {
                SaveStates.removeResume(for: root.appendingPathComponent("ROMs").appendingPathComponent(name))
            }
            try? fm.removeItem(at: cutFolder.appendingPathComponent(name))
        }
        NSLog("[library] finished %d file(s) of cuts left from before", names.count)
    }
}

@MainActor final class DemoSession: ObservableObject {
    @Published var state = DemoState()
    @Published var paused = false
    @Published private(set) var sleeping = false
    @Published private(set) var showTouchCoordinates = false
    @Published var status = String(localized: "方向键移动 · 点击下屏设置信标 · A 传送")
    @Published private(set) var held: Set<PadButton> = []
    /// When a real core is attached, inputs go to it and the demo stops
    /// interpreting them; pause/sleep/suspend still gate it the same way.
    @Published var core: AzaharSession? {
        didSet {
            if oldValue !== core {
                releaseAll(); applyCorePause()
                core?.set3DDepth(Stereo3D.percent(slider: depth3D))
            }
        }
    }
    /// The 3D slider, 0…1 in steps of 0.1, kept like the slider's position on
    /// a real console (Stereo3D). The core gets it as its 3D factor; the demo
    /// draws its stars in red/cyan depth.
    @Published private(set) var depth3D = DemoSession.startingDepth
    /// Where the slider starts: where it was left, or down while parental
    /// controls keep 3D off (round 23).
    nonisolated static var startingDepth: Double { ParentalControls.stored().restrict3D ? 0 : Stereo3D.storedSlider }
    /// MIC held: the core's microphone hears a breath; in the demo the breath
    /// blows the ship upwards. Or a breath on the iPhone's own
    /// microphone while this console listens (MicListener).
    @Published private(set) var micBlowing = false
    /// The MIC hole held (touch), and a breath on the iPhone's microphone.
    private var micHeld = false
    private var micAir = false
    /// Why this console listens to the iPhone's microphone.
    private var micReasons: Set<String> = []
    private var micAirWatch: AnyCancellable?
    /// One of the console's built-in programs (系统设置, the first-time
    /// setup) runs on this console (round 23): the demo's world holds still,
    /// the keys work the program's cursor (`menuInput`), the Circle Pad, MIC
    /// and 3D slider are still read (its tests show them).
    @Published private(set) var runningApp: ConsoleApp?
    /// The Circle Pad pushed most of the way in one direction works a menu's
    /// cursor like the D-pad (as on the handheld's own menus).
    private var stickMenuDirection: PadButton?
    private var analog = Point(x: 0, y: 0)
    private var camera = Point(x: 0, y: 0)
    private var digitalDirections: Set<PadButton> = []
    private var transient: [PadButton: Date] = [:]
    private var lastTick = Date()
    /// Time the demo has run that `state` does not carry yet (round 22).
    /// Most frames move only the clock, and publishing that made every view
    /// watching the session (the play view, the console) evaluate its body
    /// again 60 times a second, demo or game alike, with nothing changed on
    /// the screens (idle demo, 10-30 sample: SwiftUI's graph updates took
    /// over a quarter of the main thread). The clock goes into the state with
    /// the next change that shows, and into what `save()` writes.
    private var unshownSeconds = 0.0
    // A closed lid is a separate pause reason. Opening it must not undo an
    // explicit pause, a HOME menu pause, or a background suspension.
    private var requestedPause = false
    private var suspended = false
    private var saveURL: URL { Storage.root.appendingPathComponent("demo-checkpoint.json") }

    /// While the HOME menu is open the console's keys work the menu (round
    /// 17): the D-pad moves the cursor, A decides, B goes back. Returns true
    /// when the menu took the key; nothing reaches the game meanwhile.
    var menuInput: ((PadButton, Bool) -> Bool)?
    private var menuDirections: Set<PadButton> = []

    func press(_ key: PadButton, down: Bool) {
        if let menuInput, menuInput(key, down) { return }
        if let core {
            // START/SELECT are game buttons on a real console; HOME pauses.
            guard !paused else { return }
            if down { held.insert(key) } else { held.remove(key) }
            // 11-07 (按键点屏): A B X Y tap the touch screen instead,
            // in software that has it on (a key let go always lets go of both).
            if KeyTaps.keys.contains(key), core.keyTaps || !down {
                core.keyTap(key, down: down)
                if down { return }
            }
            if down, KeyTaps.keys.contains(key) { core.keyWithoutTaps() }
            core.setButton(key, pressed: down)
            return
        }
        if key == .start {
            guard !sleeping && !suspended else { return }
            if down && !held.contains(.start) {
                setPaused(!paused); held.insert(.start)
            } else if !down { held.remove(.start) }
            return
        }
        guard !paused else { return }
        if down {
            let inserted = held.insert(key).inserted
            if inserted { action(key) }
        } else { held.remove(key) }
    }
    func keyboard(_ key: PadButton) {
        if core != nil {
            // Hardware keyboard taps become a short press on the real core.
            press(key, down: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.press(key, down: false) }
            return
        }
        if key == .start { press(.start, down: true); press(.start, down: false); return }
        guard !paused else { return }
        transient[key] = Date().addingTimeInterval(0.12)
        action(key)
    }
    private func action(_ key: PadButton) {
        if key == .a {
            let before = state.collected
            state.activate()
            // The demo's sounds (round 21): the jump, a star caught.
            if core == nil { ConsoleSounds.shared.play(state.collected > before ? .star : .teleport) }
        }
        if key == .x { state.beacon = state.target; status = String(localized: "信标已对准星星，按 A 传送") }
        if key == .y { state.beacon = Point(x: 0.5, y: 0.5); status = String(localized: "信标回到中心") }
        if key == .l || key == .zl { state.beacon.x = max(0, state.beacon.x - 0.08); status = String(localized: "L / ZL：信标左移") }
        if key == .r || key == .zr { state.beacon.x = min(1, state.beacon.x + 0.08); status = String(localized: "R / ZR：信标右移") }
        if core == nil, [.x, .y, .l, .zl, .r, .zr].contains(key) { ConsoleSounds.shared.play(.beacon) }
        if key == .select { showTouchCoordinates.toggle(); status = String(localized: "SELECT：切换下屏坐标显示") }
    }
    func tick(_ now: Date) {
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        guard !paused, runningApp == nil else { return }
        transient = transient.filter { $0.value > now }
        // Worked out on a copy and published only when what the screens show
        // has changed (see unshownSeconds).
        var next = state
        next.seconds += unshownSeconds
        next.tick(delta: delta, buttons: held.union(transient.keys).union(digitalDirections), analog: analog)
        if core == nil, next.collected > state.collected { ConsoleSounds.shared.play(.star) }
        let dt = max(0, min(delta, 0.05))
        next.beacon = Point(x: next.beacon.x + camera.x * dt * 0.45, y: next.beacon.y + camera.y * dt * 0.45).clamped
        if micBlowing && core == nil { next.player = Point(x: next.player.x, y: next.player.y - dt * 0.24).clamped }
        var shown = next
        shown.seconds = state.seconds
        if shown == state {
            unshownSeconds = next.seconds - state.seconds
        } else {
            unshownSeconds = 0
            state = next
        }
    }
    func setDepth3D(_ value: Double) {
        // Parental controls can keep the slider down (round 23).
        let value = ConsoleSettings.shared.parental.restrict3D ? 0 : value
        let stepped = Double(Stereo3D.percent(slider: value)) / 100
        guard stepped != depth3D else { return }
        depth3D = stepped
        UserDefaults.standard.set(stepped, forKey: Stereo3D.defaultsKey)
        core?.set3DDepth(Stereo3D.percent(slider: stepped))
        if core == nil { status = stepped > 0 ? String(localized: "3D 滑块：深度 \(Int(stepped * 100))%（红蓝眼镜）") : String(localized: "3D 滑块：关") }
    }
    /// The MIC hole held or let go.
    func setMicBlowing(_ value: Bool) {
        micHeld = value
        applyMic()
    }
    /// This console listens to the iPhone's
    /// microphone for `reason` (相机's 闪闪, 麦克风测试, the software), or no
    /// longer does; a breath on it is the MIC held.
    func listenMic(_ reason: String, _ on: Bool) {
        let changed = on ? micReasons.insert(reason).inserted : micReasons.remove(reason) != nil
        guard changed else { return }
        MicListener.shared.want("\(ObjectIdentifier(self).hashValue):\(reason)", on)
        if micReasons.isEmpty {
            micAirWatch = nil
            if micAir { micAir = false; applyMic() }
        } else if micAirWatch == nil {
            micAirWatch = MicListener.shared.$blowing.removeDuplicates().sink { [weak self] blowing in
                MainActor.assumeIsolated {
                    self?.micAir = blowing
                    self?.applyMic()
                }
            }
        }
    }
    /// 11-06: a program of the console's own
    /// (相机's 闪闪, 麦克风测试) hears MIC with software suspended under the
    /// menu too (that pause swallowed it); the software is not told then.
    private func applyMic() {
        let blowing = (micHeld || micAir) && (!paused || runningApp != nil)
        guard blowing != micBlowing else { return }
        micBlowing = blowing
        #if DEBUG
        NSLog("[mic] the console's MIC %@ (%@%@)", blowing ? "blows" : "is quiet", micHeld ? "the hole held" : "", micAir ? " a breath on the iPhone" : "")
        #endif
        if runningApp == nil || !blowing { core?.setMicBlowing(blowing) }
        if blowing && core == nil && runningApp == nil { status = String(localized: "MIC：吹气，飞船被吹向上方") }
    }
    func setAnalog(_ point: Point) {
        // 系统设置 › 摇杆 shows the stick as held (round 23).
        StickProbe.shared.report(point)
        if menuIsOpen, let menuInput, !StickProbe.shared.active {
            // A menu is up: pushed most of the way, the stick is a D-pad
            // press (once per push); the game gets nothing meanwhile.
            let direction = Self.menuDirection(point)
            if direction != stickMenuDirection, let direction { _ = menuInput(direction, true) }
            stickMenuDirection = direction
            if analog != Point(x: 0, y: 0) { analog = Point(x: 0, y: 0); core?.setCirclePad(analog) }
            return
        }
        stickMenuDirection = nil
        // The dead zone from 系统设置 › 摇杆 (round 23).
        let tuned = StickTuning.apply(point, deadzone: ConsoleSettings.shared.stickDeadzone)
        analog = paused ? Point(x: 0, y: 0) : tuned
        core?.setCirclePad(analog)
    }
    /// The direction of a stick pushed past 0.6 (y grows downwards, as
    /// the finger's drag), else nil.
    nonisolated static func menuDirection(_ point: Point) -> PadButton? {
        guard hypot(point.x, point.y) > 0.6 else { return nil }
        if abs(point.x) > abs(point.y) { return point.x > 0 ? .right : .left }
        return point.y > 0 ? .down : .up
    }
    /// The console's HOME and POWER as assistive access names them.
    var homeKeyLabel: String { runningApp.map { String(localized: "HOME 退出\($0.title)") } ?? String(localized: "HOME 暂停菜单") }
    var powerKeyLabel: String {
        if let runningApp { return String(localized: "POWER 关闭\(runningApp.title)") }
        return String(localized: "POWER 保存进度并回到游戏库")
    }
    /// Starts or ends one of the console's built-in programs on it.
    func runApp(_ app: ConsoleApp?) {
        guard runningApp != app else { return }
        releaseAll()
        runningApp = app
        lastTick = Date()
    }
    func setCamera(_ point: Point) {
        camera = paused ? Point(x: 0, y: 0) : point
        core?.setCStick(camera)
    }
    /// The menu takes every key while it is open, releases included, so a
    /// release tells whether it is open without doing anything.
    private var menuIsOpen: Bool { menuInput?(.up, false) ?? false }
    func setDirections(_ keys: Set<PadButton>) {
        if menuIsOpen, let menuInput {
            // Each direction newly pressed is one step of the cursor; the
            // game gets no directions meanwhile.
            for key in keys.subtracting(menuDirections) { _ = menuInput(key, true) }
            menuDirections = keys
            if !digitalDirections.isEmpty { digitalDirections = []; core?.setDirections([]) }
            return
        }
        menuDirections = []
        digitalDirections = paused ? [] : keys
        core?.setDirections(digitalDirections)
    }
    func releaseAll() {
        held.removeAll(); transient.removeAll(); digitalDirections.removeAll()
        analog = Point(x: 0, y: 0); camera = Point(x: 0, y: 0)
        micHeld = false
        if micBlowing { micBlowing = false; core?.setMicBlowing(false) }
        if let core {
            for key in PadButton.allCases { core.setButton(key, pressed: false) }
            core.setCirclePad(analog); core.setCStick(camera); core.setTouch(nil, pressed: false)
        }
    }
    private func applyCorePause() {
        guard let core else { return }
        if paused { core.pause() } else { core.resume() }
    }
    func setPaused(_ value: Bool) {
        requestedPause = value
        releaseAll(); paused = requestedPause || sleeping || suspended; lastTick = Date()
        applyCorePause()
    }
    func setLidClosed(_ value: Bool) {
        guard sleeping != value else { return }
        releaseAll(); sleeping = value
        paused = requestedPause || sleeping || suspended; lastTick = Date()
        applyCorePause()
    }
    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        releaseAll(); suspended = value
        paused = requestedPause || sleeping || suspended; lastTick = Date()
        applyCorePause()
    }
    func touch(_ point: Point) {
        guard !paused else { return }
        // 系统设置 › 触摸屏's correction (round 23).
        state.touch(ConsoleSettings.shared.touch.apply(point))
        if core == nil { ConsoleSounds.shared.play(.beacon) }
        status = String(localized: "信标已放置，按 A 传送")
    }
    func save() {
        if let core {
            status = String(localized: "正在保存即时存档…")
            core.saveState { [weak self] result in
                switch result {
                case .success(let bytes): self?.status = String(localized: "即时存档已保存（\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))）")
                case .failure(let error): self?.status = String(localized: "即时存档失败：\(error.localizedDescription)")
                }
            }
            return
        }
        var saved = state
        saved.seconds += unshownSeconds
        do { try Storage.write(saved, to: saveURL); status = String(localized: "演示进度已保存到本机") }
        catch { status = String(localized: "保存失败：\(error.localizedDescription)") }
    }
    func restore() {
        if let core {
            guard core.hasSavedState else { status = String(localized: "这个游戏还没有即时存档"); return }
            status = String(localized: "正在读取即时存档…")
            releaseAll()
            core.loadState { [weak self] result in
                switch result {
                case .success: self?.status = String(localized: "已读取即时存档")
                case .failure(let error): self?.status = String(localized: "读取即时存档失败：\(error.localizedDescription)")
                }
            }
            return
        }
        do {
            let loaded = try JSONDecoder().decode(DemoState.self, from: Data(contentsOf: saveURL))
            guard loaded.isValid else { status = String(localized: "演示存档无效，未加载"); return }
            releaseAll(); state = loaded; unshownSeconds = 0; lastTick = Date(); status = String(localized: "已读取演示进度")
        } catch { status = String(localized: "没有可读取的演示存档") }
    }
}

// MARK: - 铁皮盒 (what is in the tin; the tin itself is TinBox.swift)

extension TinThing {
    var title: String {
        switch self {
        case .redFlower: return String(localized: "小红花印章")
        case .lollipop: return String(localized: "棒棒糖")
        case .musicBox: return String(localized: "八音盒")
        case .gridPaper: return String(localized: "作业本格子纸")
        case .schoolDays: return String(localized: "自行车、书包、落叶")
        case .playthings: return String(localized: "作业本、墨水、毽子、纸风车、铁皮青蛙")
        }
    }
    /// What it is for.
    var use: String {
        switch self {
        case .redFlower: return String(localized: "便签里可以盖：在便签的笔里选小红花，点一下纸就盖上一朵。")
        case .lollipop: return String(localized: "相册里编辑照片时的贴画。")
        case .musicBox: return String(localized: "在这里转一转，放金卡带短片里的那段小曲。声音大小跟着掌机的音量。")
        case .gridPaper: return String(localized: "便签的纸里多一种：撕下一张以后，隔几张就是一张作业本格子纸。")
        case .schoolDays: return String(localized: "相册里编辑照片时的三张贴画。")
        case .playthings: return String(localized: "铅笔盒托盘下面两层里的五样东西，都能贴到盒盖上。")
        }
    }
    /// What the message of its coming calls it.
    var arrival: String {
        switch self {
        case .redFlower: return String(localized: "一枚小红花印章")
        case .lollipop: return String(localized: "一根棒棒糖")
        case .musicBox: return String(localized: "一个八音盒")
        case .gridPaper: return String(localized: "一沓作业本格子纸")
        case .schoolDays: return String(localized: "自行车、书包和落叶三张贴画")
        case .playthings: return String(localized: "作业本、墨水、毽子、纸风车和铁皮青蛙")
        }
    }
    /// The message when `things` came with the `games`-th game (nil: nothing came).
    static func arrivalLine(_ things: [TinThing], games: Int) -> String? {
        guard !things.isEmpty else { return nil }
        let list = things.map(\.arrival).joined(separator: String(localized: "、"))
        return String(localized: "卡带架上有 \(games) 张游戏了：铅笔盒里多了\(list)。点游戏库角落的铅笔盒看。")
    }
}

/// What is in the tin, kept between visits; which things are new since it
/// was last opened.
@MainActor final class TinBoxStore: ObservableObject {
    static let shared = TinBoxStore()
    private static let keptKey = "FoldArc.tin.kept", unseenKey = "FoldArc.tin.unseen"
    @Published private(set) var kept: Set<TinThing>
    @Published private(set) var unseen: Set<TinThing>
    /// The player's own games on the shelf, as last counted.
    @Published private(set) var games = 0
    /// A debug build's `--foldarc-tin-games=<n>`: the tin is counted as
    /// for so many games, and nothing it gains is kept (the tests').
    static let fixedGames: Int? = {
        #if DEBUG
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--foldarc-tin-games=") {
            return Int(argument.dropFirst("--foldarc-tin-games=".count))
        }
        #endif
        return nil
    }()

    private init() {
        if Self.fixedGames == nil {
            let defaults = UserDefaults.standard
            kept = Set((defaults.stringArray(forKey: Self.keptKey) ?? []).compactMap { TinThing(rawValue: $0) })
            unseen = Set((defaults.stringArray(forKey: Self.unseenKey) ?? []).compactMap { TinThing(rawValue: $0) })
        } else {
            kept = []
            unseen = []
        }
    }
    /// The library holds `count` games of the player's own: what that
    /// brings and was not in the tin yet comes in, and is returned.
    @discardableResult func count(_ count: Int) -> [TinThing] {
        let games = Self.fixedGames ?? count
        if self.games != games { self.games = games }
        let fresh = TinThing.brought(byGames: games).filter { !kept.contains($0) }
        guard !fresh.isEmpty else { return [] }
        kept.formUnion(fresh)
        unseen.formUnion(fresh)
        store()
        NSLog("[tin] %d games: %@ into the tin", games, fresh.map(\.rawValue).joined(separator: ", "))
        return fresh
    }
    func has(_ thing: TinThing) -> Bool { kept.contains(thing) }
    /// The tin has been looked into: nothing in it is new any more.
    func seenAll() {
        guard !unseen.isEmpty else { return }
        unseen = []
        store()
    }
    private func store() {
        guard Self.fixedGames == nil else { return }
        UserDefaults.standard.set(kept.map(\.rawValue).sorted(), forKey: Self.keptKey)
        UserDefaults.standard.set(unseen.map(\.rawValue).sorted(), forKey: Self.unseenKey)
    }
}
