import SwiftUI
import GameController

/// External game controllers (the system's extended gamepad profile), and grips
/// that hold the phone. The controller last used (`GCController.current`,
/// which the system moves to whichever controller the player touches) drives
/// the console through `GamepadMapping` (Domain.swift): face
/// buttons by position as on the handheld, shoulders L / R, triggers ZL / ZR,
/// left stick Circle Pad, right stick C Stick, Menu START, Options SELECT.
/// Its Home button opens and closes FoldArc's HOME menu when the system passes
/// the press on (by default the system's own gestures see it first; FoldArc
/// leaves that setting alone). A controller lost in the middle of play lets
/// go of everything it held, and the play view pauses the game.
@MainActor final class GameControllerInput: ObservableObject {
    static let shared = GameControllerInput()
    /// The controller in use; nil when there is none.
    @Published private(set) var controllerName: String?
    /// Round 31: the controller in use unless it is the Simulator's own
    /// stand-in (a "Gamepad", MFi, always connected there, round 15): what
    /// 接上手柄自动换模式 and 手柄模式's layout for a controller go by.
    @Published private(set) var padName: String?
    private static func isStandIn(_ controller: GCController) -> Bool {
        #if targetEnvironment(simulator)
        return controller.vendorName == "Gamepad"
        #else
        return false
        #endif
    }
    /// What the status line says when controllers come and go (set once per
    /// change, also when the text repeats).
    @Published private(set) var notice = ""
    /// Round 31 (按键重新映射): which button is which 3DS key (系统设置 ›
    /// 其他设置 › 手柄), and the last button pressed with the key it gave, for
    /// that page to show.
    @Published private(set) var layout = GamepadLayout.stored
    @Published private(set) var lastPress: String?
    /// Only while the 手柄 page is up (a change published with every press
    /// in a game would redraw the views watching the controller).
    var reportsPresses = false { didSet { if !reportsPresses { lastPress = nil } } }
    /// A button the 手柄 page is waiting for (the next one pressed goes to
    /// it instead of the console).
    private var capture: ((GamepadSource) -> Void)?
    private var rawHeld: Set<GamepadSource> = []

    /// What the play view on screen does with the readings.
    struct Handler {
        var press: (PadButton, Bool) -> Void
        var directions: (Set<PadButton>) -> Void
        var circlePad: (Point) -> Void
        var cStick: (Point) -> Void
        var home: () -> Void
        var lost: () -> Void
    }
    private var handler: Handler?
    private var handlerID: UUID?
    private var controller: GCController?
    private var held: Set<PadButton> = []
    private var directions: Set<PadButton> = []
    private var pad = Point(x: 0, y: 0), stick = Point(x: 0, y: 0)
    private var homeHeld = false
    /// 11-07 沉浸模式 (nothing on the screen opens HOME): the controller's
    /// Home button goes straight to Zero, not first to the system's own
    /// gesture (GCControllerElement.SystemGestureState.disabled — the SDK:
    /// "Input is passed directly to the app"); the system's again after.
    var homeForApp = false { didSet { if homeForApp != oldValue { applyHomeGesture() } } }
    private func applyHomeGesture() {
        guard let button = controller?.extendedGamepad?.buttonHome else { return }
        button.preferredSystemGestureState = homeForApp ? .disabled : .enabled
        NSLog("[gamepad] Home button: %@", homeForApp ? String(localized: "Zero's (沉浸模式)") : "the system's first")
    }
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            let added = note.object as? GCController
            MainActor.assumeIsolated { self?.connected(added) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] note in
            let current = note.object as? GCController
            MainActor.assumeIsolated { if let current { self?.becameCurrent(current) } }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            let gone = note.object as? GCController
            MainActor.assumeIsolated { self?.disconnected(gone) }
        })
        if let first = Self.candidate(except: nil) { use(first) }
        #if DEBUG && os(iOS)
        connectDebugVirtualControllerIfRequested()
        #endif
    }

    /// The play view takes the controller while it is on screen. The id
    /// lets a play view that is going away leave a newer one's handler alone.
    func attach(_ handler: Handler) -> UUID {
        release()
        let id = UUID()
        self.handler = handler
        handlerID = id
        return id
    }
    func detach(_ id: UUID?) {
        guard let id, id == handlerID else { return }
        release()
        handler = nil
        handlerID = nil
    }

    /// The current controller, else any connected one with an extended gamepad.
    private static func candidate(except gone: GCController?) -> GCController? {
        if let current = GCController.current, current !== gone, current.extendedGamepad != nil { return current }
        return GCController.controllers().first { $0 !== gone && $0.extendedGamepad != nil }
    }

    private func connected(_ added: GCController?) {
        NSLog("[gamepad] connected %@ (%@)", added?.vendorName ?? "(no name)", added?.productCategory ?? "?")
        if controller == nil, let next = added ?? Self.candidate(except: nil), use(next) {
            // (The Simulator's stand-in is used quietly: no notice on HOME.)
            if padName != nil { notice = String(localized: "已连接手柄：\(controllerName ?? "")") }
        } else if let current = controller, Self.isStandIn(current), let added, !Self.isStandIn(added), use(added) {
            // Round 31: a controller of its own over the Simulator's stand-in.
            notice = String(localized: "已连接手柄：\(controllerName ?? "")")
        }
    }

    /// Switches to `next`: the old controller lets go of what it held, and
    /// whatever is already held on the new one counts from now. False when
    /// `next` is already in use or has no extended gamepad.
    @discardableResult private func use(_ next: GCController) -> Bool {
        guard next !== controller, let gamepad = next.extendedGamepad else { return false }
        controller?.extendedGamepad?.valueChangedHandler = nil
        release()
        controller = next
        next.handlerQueue = .main
        controllerName = next.vendorName ?? String(localized: "外接手柄")
        padName = Self.isStandIn(next) ? nil : controllerName
        NSLog("[gamepad] using %@ (%@)", next.vendorName ?? "(no name)", next.productCategory)
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            let reading = GamepadReading(gamepad)
            MainActor.assumeIsolated { self?.apply(reading) }
        }
        apply(GamepadReading(gamepad))
        if homeForApp { applyHomeGesture() }
        return true
    }

    /// When the controller in use goes away while another one is connected,
    /// the system makes the other one current before it reports the
    /// disconnection (Simulator, 10-28): the one in use is then already
    /// missing from `GCController.controllers()`, and counts as lost.
    private func becameCurrent(_ next: GCController) {
        guard next !== controller, next.extendedGamepad != nil else { return }
        let hadOne = controller != nil
        var lost = false
        if let old = controller, !GCController.controllers().contains(old) { lose(old); lost = true }
        use(next)
        let name = controllerName ?? ""
        notice = lost ? String(localized: "手柄已断开，改用：\(name)") : hadOne ? String(localized: "改用手柄：\(name)") : String(localized: "已连接手柄：\(name)")
    }

    private func disconnected(_ gone: GCController?) {
        guard let gone, gone === controller else { return }
        lose(gone)
        if let next = Self.candidate(except: gone), use(next) {
            notice = String(localized: "手柄已断开，改用：\(controllerName ?? "")")
        } else {
            notice = String(localized: "手柄已断开")
        }
    }

    /// The controller in use is gone: it lets go of everything, and the play
    /// view pauses.
    private func lose(_ gone: GCController) {
        NSLog("[gamepad] lost %@", gone.vendorName ?? "(no name)")
        gone.extendedGamepad?.valueChangedHandler = nil
        controller = nil
        controllerName = nil
        padName = nil
        release()
        handler?.lost()
    }

    /// Round 31: another layout chosen (kept for the next launch too).
    func setLayout(_ new: GamepadLayout) {
        guard new != layout else { return }
        release()
        layout = new
        new.store()
        NSLog("[gamepad] layout %@: %@", new.presetName, GamepadLayout.keys.map { "\($0.rawValue)=\(new.source(for: $0)?.rawValue ?? "-")" }.joined(separator: " "))
    }
    /// The next button pressed goes to `handler` (the 手柄 page choosing a
    /// key's button), not to the console.
    func captureNext(_ handler: @escaping (GamepadSource) -> Void) { capture = handler }
    func cancelCapture() { capture = nil }
    var capturing: Bool { capture != nil }

    private func apply(_ reading: GamepadReading) {
        let raw = GamepadSource.pressed(reading)
        let newlyPressed = raw.subtracting(rawHeld)
        rawHeld = raw
        if let source = GamepadSource.allCases.first(where: { newlyPressed.contains($0) }) {
            if let capture {
                // Taken by the 手柄 page: the console does not see it (it
                // sees it come up later as nothing held).
                self.capture = nil
                swallowed.insert(source)
                lastPress = String(localized: "\(source.title) → 选好了")
                NSLog("[gamepad] captured %@", source.rawValue)
                capture(source)
                return
            }
            if reportsPresses {
                let key = layout.key(for: source)
                lastPress = "\(source.title) → " + (key.map { String(localized: "3DS 的 \($0.rawValue.uppercased())") } ?? String(localized: "（没有用）"))
            }
        }
        guard let handler else { return }
        let buttons = layout.buttons(reading).subtracting(capturedHold(raw))
        #if DEBUG
        if buttons != held { NSLog("[gamepad] buttons: %@", buttons.isEmpty ? "-" : buttons.map(\.rawValue).sorted().joined(separator: " ")) }
        #endif
        for key in buttons.subtracting(held) { handler.press(key, true) }
        for key in held.subtracting(buttons) { handler.press(key, false) }
        held = buttons
        let newDirections = GamepadMapping.directions(reading)
        if newDirections != directions { directions = newDirections; handler.directions(newDirections) }
        let newPad = GamepadMapping.stick(reading.leftStick)
        if newPad != pad { pad = newPad; handler.circlePad(newPad) }
        let newStick = GamepadMapping.stick(reading.rightStick)
        if newStick != stick { stick = newStick; handler.cStick(newStick) }
        if reading.home && !homeHeld { handler.home() }
        homeHeld = reading.home
    }

    /// Buttons still held from a press the 手柄 page took: not the console's
    /// until they come up.
    private var swallowed: Set<GamepadSource> = []
    private func capturedHold(_ raw: Set<GamepadSource>) -> Set<PadButton> {
        swallowed.formIntersection(raw)
        return Set(swallowed.compactMap { layout.key(for: $0) })
    }

    /// Lets go of everything the controller holds.
    private func release() {
        let zero = Point(x: 0, y: 0)
        if let handler {
            for key in held { handler.press(key, false) }
            if !directions.isEmpty { handler.directions([]) }
            if pad != zero { handler.circlePad(zero) }
            if stick != zero { handler.cStick(zero) }
        }
        held = []; directions = []; pad = zero; stick = zero; homeHeld = false
    }

    #if DEBUG && os(iOS)
    /// `--foldarc-virtual-controller`: a hidden `GCVirtualController` (iOS 17
    /// can drive one from code) stands in for a real controller in the
    /// Simulator. It connects like one and goes through the same handler;
    /// `--foldarc-core-input-script` steps `VC…` press its inputs
    /// (`debugVirtualInput`).
    private var debugVirtual: GCVirtualController?
    private func connectDebugVirtualControllerIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--foldarc-virtual-controller") else { return }
        let configuration = GCVirtualController.Configuration()
        configuration.elements = [GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                                  GCInputLeftShoulder, GCInputRightShoulder, GCInputLeftTrigger, GCInputRightTrigger,
                                  GCInputDirectionPad, GCInputLeftThumbstick, GCInputRightThumbstick,
                                  GCInputButtonMenu, GCInputButtonOptions]
        configuration.isHidden = true
        let virtual = GCVirtualController(configuration: configuration)
        debugVirtual = virtual
        virtual.connect { error in
            NSLog("[gamepad] virtual controller %@", error.map { "failed: \($0.localizedDescription)" } ?? "connected")
        }
    }
    /// One scripted input on the virtual controller: `SOUTH`, `EAST`, `WEST`,
    /// `NORTH`, `L`, `R`, `ZL`, `ZR`, `MENU`, `OPTIONS` press a button for
    /// 150 ms; `UP` / `DOWN` / `LEFT` / `RIGHT` the D-pad; `LS<x>_<y>` /
    /// `RS<x>_<y>` hold a stick for 500 ms (the script separates steps with
    /// commas); `DISCONNECT` disconnects it; `HOME` acts out the Home button.
    func debugVirtualInput(_ step: String) {
        guard let virtual = debugVirtual else { NSLog("[gamepad] no virtual controller"); return }
        let buttons = ["SOUTH": GCInputButtonA, "EAST": GCInputButtonB, "WEST": GCInputButtonX, "NORTH": GCInputButtonY,
                       "L": GCInputLeftShoulder, "R": GCInputRightShoulder, "ZL": GCInputLeftTrigger, "ZR": GCInputRightTrigger,
                       "MENU": GCInputButtonMenu, "OPTIONS": GCInputButtonOptions]
        let dpad = ["UP": CGPoint(x: 0, y: 1), "DOWN": CGPoint(x: 0, y: -1), "LEFT": CGPoint(x: -1, y: 0), "RIGHT": CGPoint(x: 1, y: 0)]
        if let element = buttons[step] {
            virtual.setValue(1, forButtonElement: element)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { virtual.setValue(0, forButtonElement: element) }
        } else if let point = dpad[step] {
            virtual.setPosition(point, forDirectionPadElement: GCInputDirectionPad)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { virtual.setPosition(.zero, forDirectionPadElement: GCInputDirectionPad) }
        } else if step.hasPrefix("LS") || step.hasPrefix("RS") {
            let values = step.dropFirst(2).split(separator: "_").compactMap { Double($0) }
            guard values.count == 2 else { return }
            let element = step.hasPrefix("LS") ? GCInputLeftThumbstick : GCInputRightThumbstick
            virtual.setPosition(CGPoint(x: values[0], y: values[1]), forDirectionPadElement: element)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { virtual.setPosition(.zero, forDirectionPadElement: element) }
        } else if step == "DISCONNECT" {
            virtual.disconnect()
        } else if step == "HOME" {
            // The virtual controller has no Home button (configuring one
            // raises an exception, 10-28): a press and release of it as
            // `apply` sees them.
            var reading = controller?.extendedGamepad.map { GamepadReading($0) } ?? GamepadReading()
            reading.home = true; apply(reading)
            reading.home = false; apply(reading)
        }
    }
    #endif
}

extension GamepadReading {
    /// The current state of an extended gamepad (main queue: FoldArc sets the
    /// controller's handler queue to main).
    init(_ g: GCExtendedGamepad) {
        self.init()
        south = g.buttonA.isPressed; east = g.buttonB.isPressed
        west = g.buttonX.isPressed; north = g.buttonY.isPressed
        leftShoulder = g.leftShoulder.isPressed; rightShoulder = g.rightShoulder.isPressed
        leftTrigger = Double(g.leftTrigger.value); rightTrigger = Double(g.rightTrigger.value)
        up = g.dpad.up.isPressed; down = g.dpad.down.isPressed
        left = g.dpad.left.isPressed; right = g.dpad.right.isPressed
        leftStick = Point(x: Double(g.leftThumbstick.xAxis.value), y: Double(g.leftThumbstick.yAxis.value))
        rightStick = Point(x: Double(g.rightThumbstick.xAxis.value), y: Double(g.rightThumbstick.yAxis.value))
        menu = g.buttonMenu.isPressed
        options = g.buttonOptions?.isPressed ?? false
        home = g.buttonHome?.isPressed ?? false
    }
}
