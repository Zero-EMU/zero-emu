import SwiftUI

/// Actual hardware information is kept separate from manual preview geometry.
/// Define FOLDARC_DUO_SDK only with the Xcode 27.1 SDK (see build-duo-ios.sh).
enum DeviceFoldRegions {
    static func occlusions(_ proxy: GeometryProxy) -> [CGRect] {
        #if os(iOS) && FOLDARC_DUO_SDK
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed).map(\.frame)
        }
        #endif
        return []
    }
    static func read(_ proxy: GeometryProxy) -> FoldRegionSnapshot? {
        #if os(iOS) && FOLDARC_DUO_SDK
        if #available(iOS 27.1, *) {
            // Include inactive divisions: fully open must still honor the crease.
            let divisions = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
            guard let fold = divisions.max(by: { max($0.frame.width, $0.frame.height) < max($1.frame.width, $1.frame.height) }) else { return nil }
            return FoldRegionSnapshot(division: fold.frame, occlusions: occlusions(proxy), fromDevice: true)
        }
        #endif
        return nil
    }
}

/// While the iPhone Duo's
/// inner camera runs, the system blacks out the display over it (a pill with
/// the green light, at the right edge of the lower half as the handheld is
/// held) and reports that patch as an occluded region; the handheld's
/// layout kept clear of it by shrinking the whole console about 10% and
/// sliding it left (b56 device shots 3720/3721). From b59 the regions were
/// left out while one of FoldArc's cameras ran; the console still moved
/// when the patch was there with no camera of ours running — the microphone
/// on for a film's breath lights the system's privacy light too, and the
/// system gives a patch back a while after. On the inner display that patch
/// is the only region the system reports (besides one for a moment at
/// launch), so the handheld now lays out by none of them, and nothing moves
/// whatever lights it. The patch sits over the A key while it is lit; L, R
/// and 拍照 on the touch screen take the picture as A does. (b59 also held the
/// safe area still; the camera never changed it on the device, and a
/// launch-time inset held that way shrank the console: only the regions.)
@MainActor enum CameraSteadyInsets {
    private static var cameraOn = false
    private static var running: Set<ObjectIdentifier> = []
    private static var offTask: Task<Void, Never>?
    #if DEBUG
    private static var reported: Set<String> = []
    #endif
    /// From the camera feed: running or not. Off only a moment after the
    /// camera stops (the system gives its region back a little later).
    static func setCamera(_ on: Bool, feed: ObjectIdentifier) {
        if on { running.insert(feed) } else { running.remove(feed) }
        offTask?.cancel(); offTask = nil
        if !running.isEmpty { cameraOn = true; return }
        offTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            cameraOn = false
        }
    }
    /// The device's reported regions to lay the handheld out by: none (the
    /// inner display's only one is the camera's patch, lit by a camera or
    /// the microphone). (b59–b61 kept the regions seen with no camera on
    /// for the view's size instead; one reported for a moment at launch was
    /// kept that way and shrank the handheld with the outer camera — 983's
    /// 3720. Nothing is kept now.) What was left out goes in the log and
    /// the trace once for each size and set of regions, with whether a
    /// camera or the microphone was on.
    static func steady(_ snapshot: FoldRegionSnapshot, size: CGSize) -> FoldRegionSnapshot {
        guard snapshot.fromDevice, !snapshot.occlusions.isEmpty else { return snapshot }
        #if DEBUG
        let key = "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        let line = "\(key) regions \(snapshot.occlusions.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" }.joined(separator: " ")) (camera \(cameraOn ? "on" : "off"), microphone \(MicListener.shared.on ? "on" : "off"))"
        if reported.insert(line).inserted {
            NSLog("[layout] the device's regions left out: %@", line)
            #if os(iOS)
            // (after this view update: the trace publishes its last lines)
            Task { @MainActor in OrientationTrace.shared.event("duo regions left out: " + line) }
            #endif
        }
        #endif
        var copy = snapshot
        copy.occlusions = []
        return copy
    }
}

/// Draws the handheld in the inner panel's fixed frame (FixedFrameTransform):
/// the lower screen stays on the side-button half of the hardware whatever
/// interface orientation the system gives the window, like a real clamshell.
/// Fold regions and safe-area insets are read in window coordinates and handed
/// to the console already converted to the reference frame, so the console
/// never reads geometry from inside the rotated frame.
struct HandheldFixedFrame<Content: View>: View {
    var enabled: Bool
    @ViewBuilder var content: (_ snapshot: FoldRegionSnapshot?, _ insets: ViewportInsets?) -> Content
    #if os(iOS)
    @ObservedObject private var displayRole = DisplayRoleMonitor.shared
    #endif

    var body: some View {
        #if os(iOS)
        if enabled {
            GeometryReader { safeProxy in
                GeometryReader { proxy in
                    let size = proxy.size
                    if let turn = displayRole.handheldTurn(for: size) {
                        let transform = FixedFrameTransform(turn: turn, window: size)
                        let reference = transform.reference
                        let safe = safeProxy.safeAreaInsets
                        let insets = transform.toReference(ViewportInsets(top: safe.top, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing))
                        let snapshot = DeviceFoldRegions.read(proxy).map { transform.toReference($0) }
                            ?? FoldRegionSnapshot.preview(size: reference, axis: .horizontal, fraction: 0.5, gap: 0)
                        content(snapshot, insets)
                            .frame(width: reference.width, height: reference.height)
                            .rotationEffect(.degrees(turn))
                            .position(x: size.width / 2, y: size.height / 2)
                            // The console's pull-down navigation starts at its own
                            // top edge; keep the system gesture on that window
                            // edge from taking the first swipe.
                            .defersSystemGestures(on: Self.edges(transform.referenceTopEdge))
                            .onChange(of: turn, initial: true) { _, value in
                                OrientationTrace.shared.event("handheld fixed frame turn=\(Int(value)) window=\(Int(size.width))x\(Int(size.height))")
                            }
                    } else {
                        Color.clear
                    }
                }
                .ignoresSafeArea()
            }
        } else {
            content(nil, nil)
        }
        #else
        content(nil, nil)
        #endif
    }

    private static func edges(_ edge: FixedFrameTransform.WindowEdge) -> Edge.Set {
        switch edge {
        case .top: return .top
        case .leading: return .leading
        case .bottom: return .bottom
        case .trailing: return .trailing
        }
    }
}

struct DuoConsoleView: View {
    @ObservedObject var session: DemoSession
    var finish: ShellFinish = .graphite
    /// Round 31: a two-tone finish's outer colour — the hinge and the
    /// shoulder keys on it (`finish` is the faces'); nil: one colour.
    var outer: ShellFinish? = nil
    var brightness = 1.0
    var haptics = true
    var previewAxis: FoldAxis = .horizontal
    var previewFraction = 0.5
    var previewGap = 0.0
    var showGuides = false
    // Snapshot overrides are for the render tool and layout tests only.
    var previewSnapshot: FoldRegionSnapshot?
    var previewInsets: ViewportInsets?
    /// The render tool's hinge: half open (true) or flat (false); nil: the device's.
    var previewHalfOpen: Bool? = nil
    var showHome: () -> Void
    /// Kept for the render tool; the guide is a HOME page (round 17).
    var showHelp: () -> Void
    /// The way out when the fold cannot show the handheld at all.
    var close: () -> Void
    var showPower: (() -> Void)?
    /// The HOME menu in the LCDs (round 17), handed to the faces.
    @Environment(\.screenOverlay) private var screenOverlay
    /// 11-06: the hinge half
    /// open moves the hinge, its shoulder keys on it, down off the crease
    /// (FoldPlacement.loweredHinge); flat again, it goes back. The move
    /// waits until the hinge has held its new status a moment (a fold near
    /// the threshold does not make it jump about).
    @ObservedObject private var hingePosture = HingePosture.shared
    @ViewState private var hingeLowered = false
    @ViewState private var hingePlaceSet = false
    private var halfOpen: Bool { previewHalfOpen ?? (hingePosture.status == .partiallyOpen) }

    var body: some View {
        // Read system insets before the inner canvas covers the full viewport.
        // The full-screen proxy has zero insets after ignoresSafeArea(), which
        // would place the toolbar underneath a camera cutout on ordinary iPhones.
        GeometryReader { safeProxy in
            GeometryReader { proxy in
                // Not moved over by the camera's patch when it is lit (CameraSteadyInsets).
                let snapshot = CameraSteadyInsets.steady(previewSnapshot ?? DeviceFoldRegions.read(proxy) ??
                    FoldRegionSnapshot.preview(size: proxy.size, axis: previewAxis, fraction: previewFraction, gap: previewGap), size: proxy.size)
                let insets = previewInsets ?? ViewportInsets(top: safeProxy.safeAreaInsets.top, leading: safeProxy.safeAreaInsets.leading,
                                                             bottom: safeProxy.safeAreaInsets.bottom, trailing: safeProxy.safeAreaInsets.trailing)
                let placement = FoldPlacement.handheld(size: proxy.size, insets: insets, snapshot: snapshot)
                let lowered = (previewHalfOpen ?? hingeLowered) ? placement.loweredHinge : nil
                ZStack(alignment: .topLeading) {
                    finish.light
                    if placement.canShowHandheld {
                        // Each physical half owns its artwork, toolbar and input
                        // surface; clipping and hit bounds stay within that half.
                        // The hinge moved down (half open): the upper casing
                        // goes on down to it, over the crease.
                        let upperArea = lowered.map { Self.upperRegion(placement.upperRegion, downTo: $0.minY) } ?? placement.upperRegion
                        panelRegion(upperArea) {
                            FullScreenShellSurface(finish: finish, upper: true)
                            shellPart(hardware.upperFace, in: local(placement.upperBody, to: upperArea), scale: placement.scale)
                        }
                        panelRegion(placement.lowerRegion) {
                            FullScreenShellSurface(finish: finish)
                            shellPart(hardware.lowerFace, in: local(placement.lowerBody, to: placement.lowerRegion), scale: placement.scale)
                            // Round 29: the shoulder keys are on the hinge
                            // (HingeShoulderKeys), which goes down a little
                            // while the Duo is half open; only where
                            // the fold is a real gap with no display in it do
                            // they stay along the lower half's foot.
                            if !placement.shouldersOnHinge {
                                footer(placement).frame(width: placement.footer.width, height: placement.footer.height)
                                    .position(x: placement.footer.midX - placement.lowerRegion.minX, y: placement.footer.midY - placement.lowerRegion.minY)
                            }
                        }
                        seam(placement, hinge: lowered)
                        if showGuides { guides(placement).allowsHitTesting(false) }
                        Color.clear.frame(width: 0, height: 0)
                            .preference(key: LowerScreenWidthKey.self, value: ConsoleMetrics.lowerLCD.width * placement.scale)
                    } else if placement.canPresent {
                        // A vertical crease is a left/right pair. Do not pretend
                        // it is the upper/lower handheld mapping requested here.
                        panelRegion(placement.upperRegion) {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 48, weight: .light)).foregroundStyle(finish.ink)
                                .position(x: placement.upperRegion.width / 2, y: placement.upperRegion.height / 2)
                        }
                        panelRegion(placement.lowerRegion) {
                            orientationPrompt.frame(width: placement.lowerRegion.width, height: placement.lowerRegion.height)
                        }
                    } else {
                        Button("返回游戏库", action: close).buttonStyle(ActionStyle()).position(x: proxy.size.width / 2, y: 32)
                    }
                    // No pull-down bar since round 17: the library, the cover
                    // preview and the settings are in HOME, behind the
                    // console's own key.
                }
                .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                .onChange(of: placement) { _, _ in session.releaseAll() }
                #if os(iOS)
                .onChange(of: placement, initial: true) { _, value in
                    // (with where the two bodies stand, their scale and the safe area they were laid out by: a
                    // console standing off to one side shows here)
                    OrientationTrace.shared.event("duo placement viewport=\(Int(proxy.size.width))x\(Int(proxy.size.height)) axis=\(value.axis.rawValue) fromDevice=\(value.fromDevice) upper=\(Int(value.upperRegion.height)) lower=\(Int(value.lowerRegion.height)) handheld=\(value.canShowHandheld) scale=\(String(format: "%.3f", value.scale)) bodies x=\(Int(value.upperBody.minX))…\(Int(value.upperBody.maxX)) / \(Int(value.lowerBody.minX))…\(Int(value.lowerBody.maxX)) insets t\(Int(insets.top)) l\(Int(insets.leading)) b\(Int(insets.bottom)) r\(Int(insets.trailing))")
                }
                .onAppear { OrientationTrace.shared.event("DuoConsoleView appeared") }
                .onDisappear { OrientationTrace.shared.event("DuoConsoleView disappeared") }
                #endif
                .task(id: halfOpen) {
                    // Where the hinge is: at once when the view appears,
                    // otherwise once the hinge has held still 0.3 s.
                    if hingePlaceSet { try? await Task.sleep(nanoseconds: 300_000_000) }
                    guard !Task.isCancelled else { return }
                    let first = !hingePlaceSet
                    hingePlaceSet = true
                    guard first || hingeLowered != halfOpen else { return }
                    withAnimation(first ? nil : .easeOut(duration: 0.2)) { hingeLowered = halfOpen }
                    #if os(iOS)
                    OrientationTrace.shared.event("hinge and shoulder keys \(halfOpen ? "moved down off the crease (half open)" : "on the crease")")
                    #endif
                }
            }
            // The root covers the physical viewport. Insets are applied independently
            // after splitting; a safe-area midpoint is NOT the physical fold midpoint.
            .ignoresSafeArea()
        }
        .environment(\.layoutDirection, .leftToRight)
        #if os(iOS)
        .statusBarHidden(!CameraTry.overlays)
        .persistentSystemOverlays(CameraTry.overlays ? .automatic : .hidden)
        .defersSystemGestures(on: .top)
        #endif
    }
    private var hardware: HardwareConsole {
        HardwareConsole(session: session, finish: finish, brightness: brightness, haptics: haptics, showHome: showHome, showHelp: showHelp, showPower: showPower)
            .withOverlay(screenOverlay)
    }
    private func shellPart<V: View>(_ view: V, in rect: CGRect, scale: Double) -> some View {
        view.frame(width: ConsoleMetrics.panel.width, height: ConsoleMetrics.panel.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .position(x: rect.midX, y: rect.midY)
    }
    private func local(_ rect: CGRect, to region: CGRect) -> CGRect {
        rect.offsetBy(dx: -region.minX, dy: -region.minY)
    }
    /// The upper half's region run on down to `y` (the lowered hinge's top).
    static func upperRegion(_ region: CGRect, downTo y: Double) -> CGRect {
        CGRect(x: region.minX, y: region.minY, width: region.width, height: max(region.height, y - region.minY))
    }
    private func panelRegion<V: View>(_ region: CGRect, @ViewBuilder content: () -> V) -> some View {
        ZStack(alignment: .topLeading) { content() }
            .frame(width: region.width, height: region.height, alignment: .topLeading)
            .background(finish.light)
            .clipped()
            .contentShape(Rectangle())
            .position(x: region.midX, y: region.midY)
    }
    private var orientationPrompt: some View {
        VStack(spacing: 14) {
            Text("让折叠线横过屏幕").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("转动设备，让主屏在上，触摸副屏和按键在下。")
                .font(.system(size: 13)).foregroundStyle(finish.ink).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(24).foregroundStyle(finish.ink)
    }
    /// `hinge`: where the hinge is drawn when not on the crease (half open,
    /// FoldPlacement.loweredHinge).
    @ViewBuilder private func seam(_ p: FoldPlacement, hinge lowered: CGRect? = nil) -> some View {
        if p.axis == .horizontal, p.shouldersOnHinge {
            // Round 29: L and ZL, ZR and R are the hinge's
            // outer pieces, as a handheld's shoulder keys sit at the top
            // corners of its lower half, under the hinge.
            let rect = lowered ?? p.hinge
            HingeShoulderKeys(finish: outer ?? finish, haptics: haptics, press: session.press)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else if p.axis == .horizontal {
            // Hinge barrel: a cylinder lit from above (dark, bright crest just
            // above centre, dark again), split into knuckles by four seams,
            // with a shadow line where each half meets it.
            let hinge = outer ?? finish
            ZStack {
                LinearGradient(stops: [
                    .init(color: hinge.dark, location: 0), .init(color: hinge.shade, location: 0.16),
                    .init(color: hinge.light, location: 0.38), .init(color: hinge.base, location: 0.55),
                    .init(color: hinge.shade, location: 0.78), .init(color: hinge.dark, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                GlossSweep(strength: hinge.isLight ? 0.18 : 0.14, center: 0.5, width: 0.5, angle: 0)
                HStack(spacing: 0) {
                    ForEach(0..<4) { _ in
                        Spacer()
                        Rectangle().fill(.black.opacity(0.55)).frame(width: 1.2)
                            .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.18)).frame(width: 0.6).offset(x: 0.9) }
                    }
                    Spacer()
                }
                VStack { Rectangle().fill(.black.opacity(0.5)).frame(height: 1); Spacer(); Rectangle().fill(.black.opacity(0.6)).frame(height: 1) }
            }.frame(width: p.hinge.width, height: p.hinge.height)
                // (Round 29: its sheen stays on the hinge, not over the screens.)
                .clipped()
                .position(x: p.hinge.midX, y: p.hinge.midY).allowsHitTesting(false)
        } else {
            Rectangle().fill(.black.opacity(0.8)).frame(width: p.foldBand.width, height: p.foldBand.height)
                .position(x: p.foldBand.midX, y: p.foldBand.midY).allowsHitTesting(false)
        }
    }
    /// L, ZL, ZR, R along the bottom edge. Narrow footers get narrower
    /// keys, never a menu: a menu could only tap them, and games need them
    /// held (round 16).
    private func footer(_ p: FoldPlacement) -> some View {
        let width = min(50, max(34, (p.footer.width - 40) / 4))
        return HStack(spacing: 8) {
            ShoulderControl(key: .l, haptics: haptics, press: session.press, width: width)
            ShoulderControl(key: .zl, haptics: haptics, press: session.press, width: width)
            Spacer(minLength: 0)
            ShoulderControl(key: .zr, haptics: haptics, press: session.press, width: width)
            ShoulderControl(key: .r, haptics: haptics, press: session.press, width: width)
        }
    }
    private func guides(_ p: FoldPlacement) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2) { index in
                let rect = index == 0 ? p.upperScreen : p.lowerScreen
                Rectangle().strokeBorder(Palette.mint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
            Rectangle().fill(Palette.orange.opacity(0.16))
                .frame(width: p.foldBand.width, height: p.foldBand.height).position(x: p.foldBand.midX, y: p.foldBand.midY)
            if p.axis == .horizontal {
                Rectangle().fill(Palette.orange).frame(width: p.foldBand.width, height: 1)
                    .position(x: p.foldBand.midX, y: p.foldBand.midY)
            } else {
                Rectangle().fill(Palette.orange).frame(width: 1, height: p.foldBand.height)
                    .position(x: p.foldBand.midX, y: p.foldBand.midY)
            }
        }
    }
}

/// The hinge with the shoulder keys on it: the
/// band across the fold is the hinge's barrel, and its outer pieces are the
/// keys — L and ZL at the left, ZR and R at the right — where a handheld's
/// shoulder keys sit, at the top corners of its lower half under the hinge.
/// Each key is a moulded piece of the shell's own plastic, lit like the
/// barrel (a cylinder lit from above), standing in its own gap, its letter
/// pressed into it; held, it goes down into the casing (darker, its top
/// edge in shadow, a little lower), with the press felt (L and R deeper, ZL
/// and ZR shorter). A finger a little above or below the band still takes
/// the key: the band is narrower than a fingertip.
struct HingeShoulderKeys: View {
    var finish: ShellFinish
    var haptics: Bool
    var press: (PadButton, Bool) -> Void
    /// Where the pieces end, as fractions of the width: L | ZL | barrel | ZR | R.
    static let stops: [Double] = [0, 0.16, 0.29, 0.71, 0.84, 1]
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let x = Self.stops.map { $0 * w }
            ZStack(alignment: .topLeading) {
                // The barrel between the keys, and the dark of the gaps behind them all.
                Rectangle().fill(Color.black.opacity(0.55))
                HingeBarrel(finish: finish)
                    .frame(width: x[3] - x[2] - 2, height: h)
                    .position(x: (x[2] + x[3]) / 2, y: h / 2)
                    .allowsHitTesting(false)
                key(.l, from: x[0], to: x[1], height: h, outer: .leading)
                key(.zl, from: x[1], to: x[2], height: h, outer: nil)
                key(.zr, from: x[3], to: x[4], height: h, outer: nil)
                key(.r, from: x[4], to: x[5], height: h, outer: .trailing)
                // Where the two halves meet the hinge: a shadow line each side.
                VStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.5)).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(.black.opacity(0.6)).frame(height: 1)
                }
                .allowsHitTesting(false)
            }
        }
    }
    private func key(_ key: PadButton, from x0: Double, to x1: Double, height h: Double, outer: HorizontalEdge?) -> some View {
        HingeShoulderKey(key: key, finish: finish, outer: outer, haptics: haptics, press: press)
            .frame(width: max(0, x1 - x0 - 2), height: h)
            .position(x: (x0 + x1) / 2, y: h / 2)
    }
}

/// The hinge's barrel: a cylinder lit from above, its knuckle seams.
struct HingeBarrel: View {
    var finish: ShellFinish
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: finish.dark, location: 0), .init(color: finish.shade, location: 0.16),
                .init(color: finish.light, location: 0.38), .init(color: finish.base, location: 0.55),
                .init(color: finish.shade, location: 0.78), .init(color: finish.dark, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            GlossSweep(strength: finish.isLight ? 0.18 : 0.14, center: 0.5, width: 0.5, angle: 0)
            HStack(spacing: 0) {
                ForEach(0..<2) { _ in
                    Spacer()
                    Rectangle().fill(.black.opacity(0.5)).frame(width: 1.1)
                        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.18)).frame(width: 0.6).offset(x: 0.9) }
                }
                Spacer()
            }
        }
        // The sheen's square is wider than the barrel is tall: kept to the
        // barrel (b3 drew it over both screens as a pale band).
        .clipped()
    }
}

/// One shoulder key on the hinge (round 29).
struct HingeShoulderKey: View {
    var key: PadButton
    var finish: ShellFinish
    /// The end of the hinge it rounds off, if it is an outer piece.
    var outer: HorizontalEdge?
    var haptics: Bool
    var press: (PadButton, Bool) -> Void
    /// How far above and below the key a touch still takes it (points).
    var touchAbove = 10.0
    var touchBelow = 10.0
    @GestureState private var held = false
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let shape = HingeKeyShape(outer: outer, radius: h * 0.5, inner: min(4, h * 0.18))
            let sink = held ? max(1, h * 0.06) : 0
            ZStack {
                // The key's body: the shell's plastic as a lit cylinder, a
                // shade deeper than the barrel so that it reads as its own part.
                shape.fill(LinearGradient(stops: [
                    .init(color: finish.dark, location: 0), .init(color: finish.shade, location: 0.14),
                    .init(color: finish.light, location: 0.36), .init(color: finish.base, location: 0.56),
                    .init(color: finish.shade, location: 0.8), .init(color: finish.dark, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                // The gloss along its crest, and its own darker tone.
                shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.18), .init(color: .white.opacity(finish.isLight ? 0.35 : 0.22), location: 0.34),
                                                  .init(color: .white.opacity(0), location: 0.5)], startPoint: .top, endPoint: .bottom))
                shape.fill(Color.black.opacity(finish.isLight ? 0.06 : 0.1))
                // Its letter, pressed into the plastic: dark, with a light lower lip.
                ZStack {
                    Text(label).foregroundStyle(.white.opacity(finish.isLight ? 0.55 : 0.2)).offset(y: 0.7)
                    Text(label).foregroundStyle(.black.opacity(finish.isLight ? 0.42 : 0.55))
                }
                .font(.system(size: max(8, h * 0.42), weight: .bold, design: .rounded))
                .tracking(h * 0.03)
                // Held: down into the casing, its top edge in shadow.
                if held {
                    shape.fill(LinearGradient(colors: [.black.opacity(0.42), .black.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
                    shape.fill(Color.black.opacity(0.12))
                }
                // Its rim: a hairline of light along the top, a dark line round it.
                shape.stroke(LinearGradient(colors: [.white.opacity(held ? 0.05 : 0.32), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            }
            .frame(width: w, height: h)
            .offset(y: sink)
            .animation(.spring(duration: 0.08, bounce: 0.2), value: held)
        }
        // A finger a little above or below the band takes the key too.
        .contentShape(TallerTouch(above: touchAbove, below: touchBelow))
        .gesture(DragGesture(minimumDistance: 0).updating($held) { _, state, _ in state = true })
        .onChange(of: held) { _, down in
            press(key, down)
            // L and R are long levers (deeper); ZL and ZR small switches.
            ConsoleHaptics.shared.play(key == .l || key == .r ? .shoulder : .trigger, down ? .press : .release, enabled: haptics)
        }
        .onDisappear { press(key, false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) 肩键").accessibilityAddTraits(.isButton)
        .accessibilityAction { press(key, true); press(key, false) }
    }
    private var label: String { key.rawValue.uppercased() }
}

/// A touch area as wide as the view and taller: `above` points over it,
/// `below` points under it.
struct TallerTouch: Shape {
    var above: Double
    var below: Double
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - above, width: rect.width, height: rect.height + above + below))
    }
}

/// A key's outline: rounded off fully at the hinge's end (its outer side),
/// a small radius where it meets its neighbour.
struct HingeKeyShape: Shape {
    var outer: HorizontalEdge?
    var radius: Double
    var inner: Double
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2), i = min(inner, rect.height / 2)
        let left = outer == .leading ? r : i, right = outer == .trailing ? r : i
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: left, bottomLeading: left, bottomTrailing: right, topTrailing: right), style: .continuous)
    }
}

/// The closed cover's hidden bar: a swipe on the casing reveals it (round 17
/// took the open console's pull-down bar away; the cover has no HOME key).
struct PullDownConsoleNavigation<Controls: View>: View {
    @Binding var isPresented: Bool
    var rect: CGRect
    var activationRect: CGRect? = nil
    var keepsPresented = false
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        ZStack(alignment: .topLeading) {
            let trigger = activationRect ?? rect
            Color.clear.frame(width: trigger.width, height: trigger.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 18).onEnded { value in
                    if ConsoleNavigationGesture.reveals(translation: value.translation, onCover: activationRect != nil) {
                        withAnimation(.easeOut(duration: 0.18)) { isPresented = true }
                    }
                })
                .accessibilityElement()
                .accessibilityLabel("显示返回和设置")
                .accessibilityHint("从机身顶部向下滑动")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isPresented = true }
                .position(x: trigger.midX, y: trigger.midY)
            if isPresented {
                controls().padding(.horizontal, 4)
                    .frame(width: rect.width, height: rect.height)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .position(x: rect.midX, y: rect.midY)
                    .transition(.opacity)
            }
        }
        .task(id: isPresented && !keepsPresented) {
            guard isPresented && !keepsPresented else { return }
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            withAnimation(.easeOut(duration: 0.18)) { isPresented = false }
        }
    }
}
