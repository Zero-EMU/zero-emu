import SwiftUI

/// 手柄模式 (round 16; it replaces 大按键): the two screens with every 3DS
/// control around them at a size thumbs can hit — Circle Pad, cross, A B X Y,
/// C Stick, L ZL R ZR, START, SELECT, HOME, POWER, the 3D slider and the
/// microphone. Nothing scrolls; the same controls as the drawn console, so
/// every game can be played (大按键 had no START, SELECT, Circle Pad or C Stick).
struct ControllerModeView: View {
    @ObservedObject var session: DemoSession
    var finish: ShellFinish
    /// Round 31: a two-tone finish's outer colour (kept for the callers; the
    /// controller is drawn in the faces' colour, edge to edge: a rim round
    /// the edge was cut off by the display's rounded corners, 11-01).
    var outer: ShellFinish? = nil
    var brightness: Double
    var haptics: Bool
    var showHome: () -> Void
    var showPower: () -> Void
    /// Round 31: TV模式 — the iPhone is the controller; while a TV is
    /// connected its upper screen is on the TV and the iPhone says so there.
    var tv = false
    /// b41: TV模式's 选电视, before a
    /// TV is connected and while one is.
    var chooseTV: (() -> Void)? = nil
    /// A menu drawn in the LCDs instead of the game (the HOME menu, round 17).
    @Environment(\.screenOverlay) private var screenOverlay
    @ObservedObject private var tvOutput = TVOutput.shared
    /// Round 31 (接手柄自动换模式): with a controller connected its keys are
    /// the console's, and the screens take the room.
    @ObservedObject private var pads = GameControllerInput.shared
    /// On the iPhone Duo's cover (a game started there; CoverPlayLayout).
    var cover = false
    /// 11-07 沉浸模式: with a controller connected, the game's two
    /// screens alone on black (immersiveLayout); PlayView keeps 手柄模式 up
    /// while there is none.
    var immersive = false
    /// The render tool's crease (a Mac reports no fold), and its controller
    /// (none is connected there).
    var previewFold: CGRect? = nil
    var previewPad = false
    /// 沉浸模式 up: chosen, and a controller there to play it.
    private var showsImmersive: Bool { immersive && (pads.padName != nil || previewPad) }
    /// 沉浸模式: HOME and POWER shown for a moment after a touch on the black.
    @State private var immersiveKeys = false
    @State private var immersiveKeysTask: Task<Void, Never>?
    /// 手柄样式: the one chosen for each place (ControllerSkin), and the
    /// render tool's own.
    @AppStorage(ControllerSkin.Place.upright.key) private var uprightSkin = ControllerSkin.classic.rawValue
    @AppStorage(ControllerSkin.Place.cover.key) private var coverSkin = ControllerSkin.classic.rawValue
    @AppStorage(ControllerSkin.Place.across.key) private var acrossSkin = ControllerSkin.classic.rawValue
    var previewSkin: ControllerSkin? = nil
    /// 11-07: the render tool's book (BookPlayLayout, which
    /// the app draws with the Duo half folded), and the safe area a render is
    /// drawn with (it has none).
    var previewBook = false
    var previewInsets: EdgeInsets? = nil
    /// 11-07: held
    /// across on the iPhone Duo and half folded like a book, BookPlayLayout;
    /// flat, the layout before (level now: AcrossPlayLayout, GamepadRows).
    /// The hinge holds its new state 0.3 s before the keys move (as the
    /// handheld's hinge does, DuoConsoleView).
    @ObservedObject private var hingePosture = HingePosture.shared
    @State private var halfFolded = false
    @State private var halfFoldSet = false

    var body: some View {
        // The casing runs edge to edge; the controls keep out of the system's
        // areas. Insets come from the outer reader: inside ignoresSafeArea()
        // a reader reports none (as in DuoConsoleView).
        GeometryReader { safeProxy in
            GeometryReader { proxy in
                let size = proxy.size
                let insets = previewInsets ?? safeProxy.safeAreaInsets
                ZStack {
                    if showsImmersive {
                        immersiveLayout(size: size, insets: insets, fold: DeviceFoldRegions.read(proxy)?.division ?? previewFold)
                    } else {
                        FullScreenShellSurface(finish: finish)
                    }
                    if showsImmersive {
                        EmptyView()
                    } else if let name = pads.padName, previewSkin == nil {
                        padLayout(size: size, insets: insets, name: name, fold: previewFold ?? DeviceFoldRegions.read(proxy)?.division)
                    } else if cover {
                        switch skin(.cover) {
                        case .classic: coverLayout(size: size, insets: insets, cameras: DeviceFoldRegions.occlusions(proxy))
                        case .handheld: coverLayout(size: size, insets: insets, cameras: DeviceFoldRegions.occlusions(proxy), keys: CoverPlayLayout.largerKeys)
                        case .soft: coverLayout(size: size, insets: insets, cameras: DeviceFoldRegions.occlusions(proxy)).environment(\.controlLook, .soft(finish))
                        }
                    } else if size.width > size.height * 1.1 {
                        across(size: size, insets: insets, fold: previewFold ?? DeviceFoldRegions.read(proxy)?.division)
                    } else {
                        switch skin(.upright) {
                        case .classic: portrait(size: size, insets: insets)
                        case .handheld: handheldPortrait(size: size, insets: insets)
                        case .soft: softPortrait(size: size, insets: insets).environment(\.controlLook, .soft(finish))
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                // Which way the controller is laid, for VoiceOver and the UI
                // tests (11-07: the style button that said it is gone).
                .overlay(alignment: .topLeading) {
                    if !showsImmersive && previewSkin == nil {
                        Color.clear.frame(width: 2, height: 2)
                            .accessibilityElement()
                            .accessibilityLabel("手柄模式")
                            .accessibilityValue(cover ? ControllerSkin.Place.cover.title : (size.width > size.height * 1.1 ? ControllerSkin.Place.across.title : ControllerSkin.Place.upright.title))
                            .accessibilityIdentifier("controller-skin")
                    }
                }
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(finish.ink)
        .environment(\.layoutDirection, .leftToRight)
        .task(id: hingePosture.status == .partiallyOpen) {
            // At once when the view appears; after that once the hinge has
            // held still 0.3 s (a fold near the threshold does not flicker).
            let half = hingePosture.status == .partiallyOpen
            if halfFoldSet { try? await Task.sleep(nanoseconds: 300_000_000) }
            guard !Task.isCancelled else { return }
            let first = !halfFoldSet
            halfFoldSet = true
            guard first || halfFolded != half else { return }
            withAnimation(first ? nil : .easeOut(duration: 0.25)) { halfFolded = half }
            if !first { NSLog("[controller] %@", half ? "half folded: a screen on each page (book)" : "flat: the screens in the middle") }
        }
    }

    // MARK: Layouts

    private func portrait(size: CGSize, insets: EdgeInsets) -> some View {
        let usable = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        // Three columns that always fit the width: sticks and cross on the
        // left, START/SELECT/HOME in the middle, C Stick and A B X Y right.
        let width = usable.width - 28
        let left = width * 0.34, right = width * 0.40, middle = width - left - right
        let key = min(70, right / 3.05)
        let cross = min(156, left)
        let pad = min(132, left * 0.9)
        let controls = 40 + 10 + max(pad + 14 + cross, 40 + 8 + key * 3.05, 190)
        // The screens take the rest (top 5:3, bottom 4:3 at 0.8 of its width:
        // 1.2 × width high in all); controls sit at the bottom, under the thumbs.
        // 32 points each side keep room for the 3D slider beside the top screen.
        let screenWidth = max(160, min(usable.width - 88, (usable.height - controls - 36) / 1.2))
        return VStack(spacing: 10) {
            screens(width: screenWidth)
            Spacer(minLength: 0)
            shoulders.padding(.horizontal, 14)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 14) {
                    circlePad(pad)
                    DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: cross, height: cross)
                }.frame(width: left)
                VStack(spacing: 6) {
                    startKey(width: middle)
                    selectKey(width: middle)
                    homeButton.padding(.top, 6)
                    HStack(spacing: 6) {
                        MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                        powerButton
                    }
                }.frame(width: middle)
                VStack(spacing: 8) {
                    cStick.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, key * 0.2)
                    abxy(key: key)
                }.frame(width: right)
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, insets.top + 6).padding(.bottom, insets.bottom + 10)
        .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
    }

    /// 经典 held across: the screens in the middle, the keys either side —
    /// level and even where the display is high enough (AcrossPlayLayout:
    /// the iPhone Duo, 11-07), else as before (a phone on its side).
    @ViewBuilder private func landscape(size: CGSize, insets: EdgeInsets) -> some View {
        let level = AcrossPlayLayout.calculate(size: size, top: insets.top, bottom: insets.bottom, leading: insets.leading, trailing: insets.trailing)
        if level.fits { levelLandscape(level) } else { compactLandscape(size: size, insets: insets) }
    }

    private func levelLandscape(_ a: AcrossPlayLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                // The two screens (and the sliders beside the upper one) in the middle of the display.
                screens(width: a.upper.width).position(x: a.upper.midX, y: (a.upper.minY + a.lower.maxY) / 2)
                shoulder(.l).position(x: a.l.midX, y: a.l.midY)
                shoulder(.zl).position(x: a.zl.midX, y: a.zl.midY)
                shoulder(.zr).position(x: a.zr.midX, y: a.zr.midY)
                shoulder(.r).position(x: a.r.midX, y: a.r.midY)
                circlePad(a.pad.width).position(x: a.pad.midX, y: a.pad.midY)
                DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: a.cross.width, height: a.cross.height)
                    .position(x: a.cross.midX, y: a.cross.midY)
            }
            Group {
                cStick.position(x: a.cStick.midX, y: a.cStick.midY)
                abxy(key: a.key).position(x: a.abxy.midX, y: a.abxy.midY)
                VStack(spacing: 2) { startKey(width: a.startSelect.width); selectKey(width: a.startSelect.width) }
                    .position(x: a.startSelect.midX, y: a.startSelect.midY)
                homeKey(width: a.home.width).position(x: a.home.midX, y: a.home.midY)
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                    .position(x: a.mic.midX, y: a.mic.midY)
                powerButton.position(x: a.power.midX, y: a.power.midY)
            }
        }
        .frame(width: a.size.width, height: a.size.height)
    }

    private func compactLandscape(size: CGSize, insets: EdgeInsets) -> some View {
        let usable = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        let screenWidth = min(usable.width * 0.46, (usable.height - 12) / 1.2)
        let key = min(64, usable.height * 0.16)
        let cross = min(140, usable.height * 0.36)
        let pad = min(118, usable.height * 0.3)
        return HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 12) {
                HStack(spacing: 8) { shoulder(.l); shoulder(.zl) }
                circlePad(pad)
                DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: cross, height: cross)
            }
            Spacer(minLength: 4)
            screens(width: screenWidth)
            Spacer(minLength: 4)
            VStack(spacing: 10) {
                HStack(spacing: 8) { shoulder(.zr); shoulder(.r) }
                HStack(alignment: .top, spacing: 10) {
                    cStick
                    abxy(key: key)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 2) { startKey(width: 112); selectKey(width: 112) }
                    homeButton
                }
                HStack(spacing: 14) { MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }; powerButton }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, insets.top + 8).padding(.bottom, insets.bottom + 8)
        .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
    }

    /// Held across, in the style chosen for it: on the iPhone Duo half folded
    /// (the crease down the middle), a screen on each page (BookPlayLayout) —
    /// TV模式 too.
    @ViewBuilder private func across(size: CGSize, insets: EdgeInsets, fold: CGRect?) -> some View {
        if let fold, fold.height > fold.width, previewBook || halfFolded {
            let style = skin(.across)
            bookLayout(size: size, insets: insets, fold: fold, sizes: style == .classic ? .classic : .gamepad, soft: style == .soft)
        } else {
            switch skin(.across) {
            case .classic: landscape(size: size, insets: insets)
            case .handheld: gamepad(size: size, insets: insets, soft: false)
            case .soft: gamepad(size: size, insets: insets, soft: true).environment(\.controlLook, .soft(finish))
            }
        }
    }

    /// The iPhone Duo held like a book and half folded (BookPlayLayout): a
    /// screen on each page, the controls under them level row by row,
    /// nothing on the crease.
    private func bookLayout(size: CGSize, insets: EdgeInsets, fold: CGRect, sizes: BookPlayLayout.Sizes, soft: Bool) -> some View {
        let b = BookPlayLayout.calculate(size: size, fold: fold, top: insets.top, bottom: insets.bottom,
                                         leading: insets.leading, trailing: insets.trailing, sizes: sizes)
        return ZStack(alignment: .topLeading) {
            Group {
                upperScreen(width: b.upper.width).position(x: b.upper.midX, y: b.upper.midY)
                lowerScreen(width: b.lower.width).position(x: b.lower.midX, y: b.lower.midY)
                ShoulderControl(key: .l, haptics: haptics, press: session.press, width: b.l.width, height: b.l.height).position(x: b.l.midX, y: b.l.midY)
                ShoulderControl(key: .zl, haptics: haptics, press: session.press, width: b.zl.width, height: b.zl.height).position(x: b.zl.midX, y: b.zl.midY)
                ShoulderControl(key: .zr, haptics: haptics, press: session.press, width: b.zr.width, height: b.zr.height).position(x: b.zr.midX, y: b.zr.midY)
                ShoulderControl(key: .r, haptics: haptics, press: session.press, width: b.r.width, height: b.r.height).position(x: b.r.midX, y: b.r.midY)
                DepthSlider(depth: Binding(get: { session.depth3D }, set: { session.setDepth3D($0) }), ink: finish.ink, haptics: haptics)
                    .scaleEffect(0.82).position(x: b.depth.midX, y: b.depth.midY)
                VolumeSlider(ink: finish.ink, haptics: haptics)
                    .scaleEffect(0.82).position(x: b.volume.midX, y: b.volume.midY)
            }
            Group {
                circlePad(b.pad.width).position(x: b.pad.midX, y: b.pad.midY)
                DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: b.cross.width, height: b.cross.height)
                    .position(x: b.cross.midX, y: b.cross.midY)
                cStick.position(x: b.cStick.midX, y: b.cStick.midY)
                abxy(key: b.key).position(x: b.abxy.midX, y: b.abxy.midY)
                VStack(spacing: 2) { startKey(width: b.startSelect.width); selectKey(width: b.startSelect.width) }
                    .position(x: b.startSelect.midX, y: b.startSelect.midY)
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                    .position(x: b.mic.midX, y: b.mic.midY)
                powerButton.position(x: b.power.midX, y: b.power.midY)
                Group { if soft { softHomeKey } else { homeButton } }.position(x: b.home.midX, y: b.home.midY)
            }
        }
        .frame(width: size.width, height: size.height)
        .preference(key: LowerScreenWidthKey.self, value: b.lower.width)
        .environment(\.controlLook, soft ? .soft(finish) : .hardware)
        .accessibilityIdentifier("book-play")
    }

    // MARK: 手柄样式

    /// The style chosen for `place` (the render tool's, if it gives one).
    private func skin(_ place: ControllerSkin.Place) -> ControllerSkin {
        if let previewSkin { return previewSkin }
        let raw: String
        switch place {
        case .upright: raw = uprightSkin
        case .cover: raw = coverSkin
        case .across: raw = acrossSkin
        }
        return ControllerSkin(rawValue: raw) ?? .classic
    }
    // (11-07: the style is chosen in 主题 › 手柄样式 now — not by a button here.)

    /// 掌机 (upright): the upper screen, the hinge with L ZL | ZR R on it, the
    /// touch screen; under it the Circle Pad over the cross on the left, the
    /// C Stick and A B X Y on the right with START and SELECT under them, as
    /// a handheld's lower half has them; HOME in the middle of the foot.
    private func handheldPortrait(size: CGSize, insets: EdgeInsets) -> some View {
        let usable = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        let width = usable.width - 28
        let key = min(64, width * 0.155)
        let cluster = key * 3.05
        let pad = min(120, width * 0.31)
        let cross = min(128, width * 0.33)
        let hinge = 34.0
        let left = pad + 12 + cross
        let right = 40 + 4 + cluster + 8 + 72
        let foot = 58.0
        let controls = max(left, right) + 10 + foot
        let screenWidth = max(160, min(usable.width - 88, (usable.height - controls - hinge - 28) / 1.2))
        return VStack(spacing: 0) {
            upperWithSliders(width: screenWidth)
            HingeShoulderKeys(finish: outer ?? finish, haptics: haptics, press: session.press)
                .frame(width: min(usable.width - 12, screenWidth + 96), height: hinge)
                .padding(.vertical, 6)
            lowerScreen(width: screenWidth * 0.8)
                .preference(key: LowerScreenWidthKey.self, value: screenWidth * 0.8)
            Spacer(minLength: 8)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 12) {
                    circlePad(pad)
                    DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: cross, height: cross)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    cStick.frame(width: cluster, alignment: .leading)
                    abxy(key: key)
                    VStack(alignment: .leading, spacing: 0) {
                        startKey(width: 96)
                        selectKey(width: 96)
                    }
                    .frame(width: cluster, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14)
            HStack(alignment: .center, spacing: 10) {
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                Spacer(minLength: 0)
                homeButton
                Spacer(minLength: 0)
                powerButton
            }
            .frame(height: foot)
            .padding(.horizontal, 14)
        }
        .padding(.top, insets.top + 6).padding(.bottom, insets.bottom + 6)
        .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
    }

    /// 圆润 (upright; the pink skin, FoldArc's own drawing): the two
    /// screens, the touch screen as wide as the upper one, L ZL and ZR R
    /// hanging under its two lower corners; a large Circle Pad over the
    /// cross on the left, A B X Y on the right; along the foot a row of small
    /// round keys — HOME, START, SELECT — and POWER.
    private func softPortrait(size: CGSize, insets: EdgeInsets) -> some View {
        let usable = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        let width = usable.width - 28
        let key = min(66, width * 0.16)
        let cluster = key * 3.05
        let pad = min(118, width * 0.3)
        let cross = min(138, width * 0.35)
        let tabs = 36.0
        let foot = 48.0
        let controls = tabs + 8 + max(pad + 10 + cross, 40 + cluster) + 8 + foot
        // The upper screen 5:3, the touch screen 4:3 as wide: 1.35 × width.
        let screenWidth = max(160, min(usable.width - 80, (usable.height - controls - 20) / 1.35))
        let tabWidth = min(78, screenWidth * 0.23)
        return VStack(spacing: 0) {
            upperWithSliders(width: screenWidth)
            lowerScreen(width: screenWidth)
                .preference(key: LowerScreenWidthKey.self, value: screenWidth)
                .padding(.top, 8)
            // The shoulder keys hang from the touch screen's lower edge.
            HStack(spacing: 3) {
                ShoulderControl(key: .l, haptics: haptics, press: session.press, width: tabWidth, height: tabs, hanging: true)
                ShoulderControl(key: .zl, haptics: haptics, press: session.press, width: tabWidth * 0.72, height: tabs - 6, hanging: true)
                Spacer(minLength: 4)
                ShoulderControl(key: .zr, haptics: haptics, press: session.press, width: tabWidth * 0.72, height: tabs - 6, hanging: true)
                ShoulderControl(key: .r, haptics: haptics, press: session.press, width: tabWidth, height: tabs, hanging: true)
            }
            .frame(width: screenWidth, height: tabs, alignment: .top)
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 10) {
                    circlePad(pad)
                    DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: cross, height: cross)
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 0) {
                    cStick
                    abxy(key: key)
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 0) {
                softHomeKey
                Spacer(minLength: 4)
                startKey(width: 84)
                Spacer(minLength: 4)
                selectKey(width: 88)
                Spacer(minLength: 4)
                powerButton
            }
            .frame(height: foot)
            .padding(.horizontal, 16)
            .overlay(alignment: .topLeading) {
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                    .scaleEffect(0.9).offset(x: 6, y: -24)
            }
        }
        .padding(.top, insets.top + 6).padding(.bottom, insets.bottom + 4)
        .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
    }

    /// 手柄 / 圆润 (across: TV模式, or a phone on its side): a gamepad round
    /// the touch screen — L ZL, the Circle Pad and the cross on the left; ZR
    /// R, the C Stick and A B X Y on the right; SELECT, HOME, START under the
    /// touch screen. With the picture on a TV the upper screen is not shown
    /// here, and the touch screen takes its room.
    private func gamepad(size: CGSize, insets: EdgeInsets, soft: Bool) -> some View {
        let usable = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        let onTV = tv && tvOutput.display != nil
        let column = min(usable.width * 0.27, usable.height * 0.95)
        let key = min(68, usable.height * 0.17, column / 3.1)
        let pad = min(126, usable.height * 0.32, column * 0.78)
        let cross = min(144, usable.height * 0.36, column * 0.86)
        let row = 46.0
        let middle = usable.width - 2 * column - 32
        let screensHeight = usable.height - row - 22
        // Upper 5:3 over lower 4:3 at 0.8 of its width (1.2 × the upper's
        // width high), or the touch screen alone.
        let lowerWidth = onTV ? min(middle, screensHeight / 0.75) : min(middle * 0.8, screensHeight / 1.2 * 0.8)
        // 11-07: the Circle Pad level with A B X Y where there is room.
        let rows = GamepadRows.calculate(height: usable.height - 12, pad: pad, cross: cross, cluster: key * 3.05)
        return HStack(alignment: .center, spacing: 16) {
            gamepadLeft(column: column, pad: pad, cross: cross, rows: rows)
            VStack(spacing: 6) {
                if !onTV {
                    upperScreen(width: lowerWidth / 0.8)
                        .overlay(alignment: .trailing) {
                            // clear of the screen's frame (at 30 its "3D" touched it)
                            DepthSlider(depth: Binding(get: { session.depth3D }, set: { session.setDepth3D($0) }), ink: finish.ink, haptics: haptics)
                                .scaleEffect(0.7).offset(x: 40)
                        }
                        .overlay(alignment: .leading) {
                            // and the volume slider on the other side, as the other styles have it
                            VolumeSlider(ink: finish.ink, haptics: haptics)
                                .scaleEffect(0.7).offset(x: -36)
                        }
                }
                lowerScreen(width: lowerWidth)
                    .preference(key: LowerScreenWidthKey.self, value: lowerWidth)
                HStack(spacing: 8) {
                    selectKey(width: 90)
                    if soft { softHomeKey } else { homeButton }
                    startKey(width: 84)
                    if onTV, chooseTV != nil { chooseTVButton }
                }
                .frame(height: row)
            }
            .frame(width: middle)
            gamepadRight(column: column, key: key, rows: rows)
        }
        .padding(.horizontal, 10)
        .padding(.top, insets.top + 6).padding(.bottom, insets.bottom + 6)
        .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
    }

    /// 手柄 / 圆润's left column: L ZL, the Circle Pad over the cross, the
    /// microphone at the foot; with `rows`, the Circle Pad level with A B X Y.
    @ViewBuilder private func gamepadLeft(column: Double, pad: Double, cross: Double, rows: GamepadRows?) -> some View {
        let shoulders = HStack(spacing: 6) {
            ShoulderControl(key: .l, haptics: haptics, press: session.press, width: column * 0.5 - 4, height: 38)
            ShoulderControl(key: .zl, haptics: haptics, press: session.press, width: column * 0.4 - 4, height: 34)
        }
        if let rows {
            VStack(spacing: 0) {
                shoulders.frame(height: GamepadRows.shoulders)
                Color.clear.frame(height: rows.overPad)
                circlePad(pad)
                Color.clear.frame(height: GamepadRows.gap)
                DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: cross, height: cross)
                Spacer(minLength: 0)
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                    .frame(height: GamepadRows.foot)
            }
            .frame(width: column)
        } else {
            VStack(spacing: 10) {
                shoulders
                Spacer(minLength: 2)
                circlePad(pad)
                DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: cross, height: cross)
                Spacer(minLength: 2)
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
            }
            .frame(width: column)
        }
    }

    /// 手柄 / 圆润's right column: ZR R, the C Stick over A B X Y, POWER at
    /// the foot.
    @ViewBuilder private func gamepadRight(column: Double, key: Double, rows: GamepadRows?) -> some View {
        let shoulders = HStack(spacing: 6) {
            ShoulderControl(key: .zr, haptics: haptics, press: session.press, width: column * 0.4 - 4, height: 34)
            ShoulderControl(key: .r, haptics: haptics, press: session.press, width: column * 0.5 - 4, height: 38)
        }
        if let rows {
            VStack(spacing: 0) {
                shoulders.frame(height: GamepadRows.shoulders)
                Color.clear.frame(height: rows.overStick)
                cStick.frame(width: key * 3.05, alignment: .leading)
                Color.clear.frame(height: GamepadRows.gap)
                abxy(key: key)
                Spacer(minLength: 0)
                powerButton
            }
            .frame(width: column)
        } else {
            VStack(spacing: 10) {
                shoulders
                Spacer(minLength: 2)
                cStick.frame(width: key * 3.05, alignment: .leading)
                abxy(key: key)
                Spacer(minLength: 2)
                powerButton
            }
            .frame(width: column)
        }
    }

    /// The upper screen with the volume and 3D sliders beside it.
    private func upperWithSliders(width: Double) -> some View {
        upperScreen(width: width)
            .overlay(alignment: .trailing) {
                DepthSlider(depth: Binding(get: { session.depth3D }, set: { session.setDepth3D($0) }), ink: finish.ink, haptics: haptics)
                    .scaleEffect(0.82).offset(x: 34)
            }
            .overlay(alignment: .leading) {
                VolumeSlider(ink: finish.ink, haptics: haptics)
                    .scaleEffect(0.82).offset(x: -34)
            }
    }

    /// 圆润's HOME: a small round key of the casing's plastic, named.
    private var softHomeKey: some View {
        Button(action: showHome) {
            HStack(spacing: 7) {
                SoftKeyFace(shape: Circle(), finish: finish, held: false).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "house.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(finish.isLight ? 0.95 : 0.7)))
                SoftLetters(text: "HOME", finish: finish, size: 12)
            }
            .frame(minWidth: 80, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(HardwareButtonStyle(part: .homeButton, haptics: haptics))
        .accessibilityLabel(session.homeKeyLabel)
    }

    // MARK: 沉浸模式 (11-07)

    /// 沉浸模式: the game's two screens on black and nothing else — no
    /// casing, no keys, no frames; the controller plays (its HOME opens the
    /// menu). The display is cut in two halves — either side of the fold
    /// where there is one (a Duo's crease: the screens are never on it), else
    /// of the middle — the upper screen as big as its half allows (5:3), the
    /// touch screen in the other (4:3), both drawn toward the middle as a
    /// console has them: upright one over the other, across side by side.
    /// A touch on the black shows HOME and POWER along the top for a few
    /// seconds (a controller whose HOME the system keeps).
    private func immersiveLayout(size: CGSize, insets: EdgeInsets, fold: CGRect?) -> some View {
        let safe = CGRect(x: insets.leading, y: insets.top,
                          width: max(0, size.width - insets.leading - insets.trailing), height: max(0, size.height - insets.top - insets.bottom))
        let halves = ImmersiveLayout.halves(of: safe, fold: fold)
        let upper = ImmersiveLayout.fit(aspect: 5.0 / 3.0, in: halves.first, toward: halves.across ? .trailing : .bottom)
        let lower = ImmersiveLayout.fit(aspect: 4.0 / 3.0, in: halves.second, toward: halves.across ? .leading : .top)
        return ZStack(alignment: .topLeading) {
            Color.black
                .contentShape(Rectangle())
                .onTapGesture { showImmersiveKeys() }
                .accessibilityHidden(true)
            upperScreen(width: upper.width, bare: true)
                .position(x: upper.midX, y: upper.midY)
            lowerScreen(width: lower.width, bare: true)
                .position(x: lower.midX, y: lower.midY)
                .preference(key: LowerScreenWidthKey.self, value: lower.width)
            // Along the top: black in every one of the layouts (the upper
            // screen hugs the middle), over neither screen (b72 put them at
            // the foot, over the touch screen on the Duo's cover).
            immersiveKeyRow
                .opacity(immersiveKeys ? 1 : 0)
                .allowsHitTesting(immersiveKeys)
                .position(x: size.width / 2, y: insets.top + 26)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("immersive-screens")
        .accessibilityValue(halves.across ? "左右" : "上下")
    }
    /// HOME and POWER, small, light on the black (VoiceOver always has them).
    private var immersiveKeyRow: some View {
        HStack(spacing: 14) {
            Button(action: showHome) {
                Label("HOME", systemImage: "house.fill").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
            }
            .accessibilityLabel(session.homeKeyLabel)
            .accessibilityIdentifier("immersive-home")
            Button(action: showPower) {
                Image(systemName: "power").font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
            }
            .accessibilityLabel(session.powerKeyLabel)
        }
        .foregroundStyle(.white.opacity(0.85))
        .buttonStyle(MenuPressStyle())
    }
    private func showImmersiveKeys() {
        withAnimation(.easeOut(duration: 0.2)) { immersiveKeys = true }
        immersiveKeysTask?.cancel()
        immersiveKeysTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { immersiveKeys = false }
        }
    }

    /// A controller connected (round 31): the two screens as big as the
    /// display allows, HOME and POWER under them, the controller named; on
    /// a Duo held across and half folded, a screen on each page.
    @ViewBuilder private func padLayout(size: CGSize, insets: EdgeInsets, name: String, fold: CGRect?) -> some View {
        if let fold, fold.height > fold.width, size.width > size.height * 1.1, halfFolded || previewBook {
            padBook(size: size, insets: insets, name: name, fold: fold)
        } else {
            padStack(size: size, insets: insets, name: name)
        }
    }
    private static let padBarHeight = 58.0
    private func padStack(size: CGSize, insets: EdgeInsets, name: String) -> some View {
        let usable = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        let bar = Self.padBarHeight
        // The screens: 5:3 over 4:3 at 0.8 of its width, 1.2 × width high,
        // 32 points each side for the sliders beside the upper one.
        let screenWidth = max(160, min(usable.width - 88, (usable.height - bar - 40) / 1.2))
        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            screens(width: screenWidth)
            Spacer(minLength: 0)
            padBar(name: name).frame(height: bar)
        }
        .padding(.top, insets.top + 6).padding(.bottom, insets.bottom + 8)
        .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
    }
    /// Half folded: the upper screen on the left page, the touch screen on
    /// the right (each as big as its page allows, against the crease, as
    /// 沉浸模式 lays them), the controller's name, HOME and POWER under the
    /// touch screen.
    private func padBook(size: CGSize, insets: EdgeInsets, name: String, fold: CGRect) -> some View {
        let bar = Self.padBarHeight
        let safe = CGRect(x: insets.leading, y: insets.top, width: max(0, size.width - insets.leading - insets.trailing),
                          height: max(0, size.height - insets.top - insets.bottom - bar - 8))
        let halves = ImmersiveLayout.halves(of: safe, fold: fold)
        let upper = ImmersiveLayout.fit(aspect: 5.0 / 3.0, in: halves.first, toward: .trailing)
        let lower = ImmersiveLayout.fit(aspect: 4.0 / 3.0, in: halves.second, toward: .leading)
        return ZStack(alignment: .topLeading) {
            upperScreen(width: upper.width).position(x: upper.midX, y: upper.midY)
            lowerScreen(width: lower.width).position(x: lower.midX, y: lower.midY)
                .preference(key: LowerScreenWidthKey.self, value: lower.width)
            padBar(name: name).frame(height: bar)
                .position(x: (fold.maxX + size.width - insets.trailing) / 2, y: size.height - insets.bottom - 4 - bar / 2)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityIdentifier("pad-book")
    }
    private func padBar(name: String) -> some View {
        HStack(spacing: 14) {
            Label(name, systemImage: "gamecontroller.fill")
                .font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 30)
                .background(.black.opacity(finish.isLight ? 0.08 : 0.22), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("手柄已接上：\(name)")
                .accessibilityIdentifier("pad-connected")
            homeButton
            powerButton
        }
    }

    /// A game on the
    /// iPhone Duo's cover — the screens as large as fit under the camera,
    /// the shoulder keys and START / SELECT beside the touch screen, the
    /// Circle Pad, the cross, HOME and A B X Y in a band at the foot.
    private func coverLayout(size: CGSize, insets: EdgeInsets, cameras: [CGRect], keys: Double = 1) -> some View {
        let l = CoverPlayLayout.calculate(size: size, bottom: insets.bottom, cameras: cameras, keys: keys)
        return ZStack(alignment: .topLeading) {
            upperScreen(width: l.upper.width)
                .position(x: l.upper.midX, y: l.upper.midY)
            lowerScreen(width: l.lower.width)
                .position(x: l.lower.midX, y: l.lower.midY)
            VStack(spacing: 6) {
                shoulder(.l)
                shoulder(.zl)
                Spacer(minLength: 4)
                selectKey(width: l.leftColumn.width)
                MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
            }
            .frame(width: l.leftColumn.width, height: l.leftColumn.height)
            .position(x: l.leftColumn.midX, y: l.leftColumn.midY)
            VStack(spacing: 6) {
                shoulder(.r)
                shoulder(.zr)
                cStick.padding(.top, 2)
                Spacer(minLength: 4)
                startKey(width: l.rightColumn.width)
            }
            .frame(width: l.rightColumn.width, height: l.rightColumn.height)
            .position(x: l.rightColumn.midX, y: l.rightColumn.midY)
            // The band, placed piece by piece (b60's row of spacers ran a few
            // points past both edges): the Circle Pad and the cross from the
            // left, A B X Y from the right, HOME and POWER between them.
            let cluster = l.key * 3.05
            let crossRight = l.band.minX + l.pad + 4 + l.cross
            let clusterLeft = l.band.maxX - cluster
            circlePad(l.pad)
                .position(x: l.band.minX + l.pad / 2, y: l.band.midY)
            DirectionPad(changed: session.setDirections, haptics: haptics).frame(width: l.cross, height: l.cross)
                .position(x: crossRight - l.cross / 2, y: l.band.midY)
            VStack(spacing: 4) {
                homeKey(width: min(90, max(44, clusterLeft - crossRight - 4)))
                powerButton
            }
            .frame(width: max(0, clusterLeft - crossRight - 4))
            .position(x: (crossRight + clusterLeft) / 2, y: l.band.midY)
            abxy(key: l.key)
                .position(x: clusterLeft + cluster / 2, y: l.band.midY)
        }
        .frame(width: size.width, height: size.height)
        .preference(key: LowerScreenWidthKey.self, value: l.lower.width)
        .accessibilityIdentifier("cover-play")
    }

    // MARK: Parts

    private func screens(width: Double) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .trailing) {
                upperScreen(width: width)
            }
            .overlay(alignment: .trailing) {
                // The 3D slider sits beside the top screen, as on the console.
                DepthSlider(depth: Binding(get: { session.depth3D }, set: { session.setDepth3D($0) }), ink: finish.ink, haptics: haptics)
                    .scaleEffect(0.82).offset(x: 34)
            }
            .overlay(alignment: .leading) {
                // And the volume slider on the other side (round 20).
                VolumeSlider(ink: finish.ink, haptics: haptics)
                    .scaleEffect(0.82).offset(x: -34)
            }
            lowerScreen(width: width * 0.8)
        }
        .preference(key: LowerScreenWidthKey.self, value: width * 0.8)
    }

    /// The upper screen, `width` wide (5:3); `bare` (沉浸模式): no frame.
    private func upperScreen(width: Double, bare: Bool = false) -> some View {
        lcd(bare: bare) {
            Group {
                if let overlay = screenOverlay { overlay.top }
                else if tv, let display = tvOutput.display {
                    TVLinkedScreen(display: display, layout: tvOutput.layout, set: tvOutput.set, look: tvOutput.look, choose: chooseTV)
                }
                else if let core = session.core { CoreTopScreen(session: core) }
                else { StarField(state: session.state, squareCorners: true, depth: session.depth3D).screenFilter(native: ScreenPixels.upper) }
            }
            .overlay(Color.black.opacity(1 - brightness).allowsHitTesting(false))
            .overlay { if session.paused && screenOverlay == nil { pausedBadge } }
            .overlay(alignment: .top) {
                if tv, tvOutput.display == nil, screenOverlay == nil {
                    VStack(spacing: 5) {
                        noTVBadge
                        chooseTVButton
                    }
                    .padding(.top, 6)
                }
            }
        }
        .frame(width: width, height: width * 0.6)
    }

    /// The touch screen, `width` wide (4:3); `bare` (沉浸模式): no frame.
    private func lowerScreen(width: Double, bare: Bool = false) -> some View {
        lcd(bare: bare) {
            Group {
                if let overlay = screenOverlay { overlay.bottom }
                else if let core = session.core { CoreTouchScreen(session: core).disabled(session.paused) }
                else { TouchMap(state: session.state, touch: session.touch, squareCorners: true, showCoordinates: session.showTouchCoordinates).screenFilter(native: ScreenPixels.lower) }
            }
            .overlay(Color.black.opacity(1 - brightness).allowsHitTesting(false))
            // The stylus in the hand: its tip where the screen is touched (round 23).
            .modifier(StylusTrace(scale: width / ConsoleMetrics.lowerLCD.width))
        }
        .frame(width: width, height: width * 0.75)
    }

    /// The LCD's frame round `content`, or (沉浸模式) the picture alone.
    @ViewBuilder private func lcd<Content: View>(bare: Bool, @ViewBuilder content: () -> Content) -> some View {
        let view = content()
        if bare { view } else { LCDFrame { view } }
    }

    private var shoulders: some View {
        HStack(spacing: 8) {
            shoulder(.l); shoulder(.zl)
            Spacer(minLength: 8)
            shoulder(.zr); shoulder(.r)
        }
    }

    private func shoulder(_ key: PadButton) -> some View {
        ShoulderControl(key: key, haptics: haptics, press: session.press, width: 66, height: 40)
    }

    private func circlePad(_ size: Double) -> some View {
        AnalogPad(haptics: haptics, demo: session.core == nil, changed: session.setAnalog)
            .frame(width: size, height: size)
    }

    private var cStick: some View {
        AnalogPad(isCStick: true, haptics: haptics, demo: session.core == nil, changed: session.setCamera)
            .frame(width: 40, height: 40)
    }

    private func abxy(key: Double) -> some View {
        let gap = key * 1.02
        return ZStack {
            HardwareKey(key: .x, color: RetroHardwareInk.blue, haptics: haptics, press: session.press).frame(width: key, height: key).offset(y: -gap)
            HardwareKey(key: .a, color: RetroHardwareInk.red, haptics: haptics, press: session.press).frame(width: key, height: key).offset(x: gap)
            HardwareKey(key: .b, color: RetroHardwareInk.yellow, haptics: haptics, press: session.press).frame(width: key, height: key).offset(y: gap)
            HardwareKey(key: .y, color: RetroHardwareInk.green, haptics: haptics, press: session.press).frame(width: key, height: key).offset(x: -gap)
        }
        .frame(width: key * 3.05, height: key * 3.05)
    }

    private func startKey(width: Double) -> some View {
        SmallKey(title: "START", ink: finish.ink, isLight: finish.isLight, haptics: haptics,
                 accessibility: session.core != nil ? "START" : String(localized: "START 暂停或继续"), width: min(112, width)) { session.press(.start, down: $0) }
    }
    private func selectKey(width: Double) -> some View {
        SmallKey(title: "SELECT", ink: finish.ink, isLight: finish.isLight, haptics: haptics,
                 accessibility: session.core != nil ? "SELECT" : String(localized: "SELECT 游戏按键，切换地图坐标"), width: min(112, width)) { session.press(.select, down: $0) }
    }

    private var homeButton: some View { homeKey() }
    /// HOME, `width` wide (its capsule as wide as it allows, 66 at most).
    private func homeKey(width: Double = 90) -> some View {
        Button(action: showHome) {
            VStack(spacing: 5) {
                Image(systemName: "house").font(.system(size: 15, weight: .medium))
                    .frame(width: min(66, max(40, width - 8)), height: 30)
                    .background(LinearGradient(colors: [finish.dark.opacity(0.55), finish.light.opacity(0.25)], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .recessed(Capsule(), depth: 1.6, light: finish.isLight ? 0.6 : 0.2, dark: 0.55)
                Text("HOME").font(.system(size: 9, weight: .medium)).tracking(1)
            }
            .frame(width: width, height: 56).contentShape(Rectangle())
        }
        .buttonStyle(HardwareButtonStyle(part: .homeButton, haptics: haptics))
        .accessibilityLabel(session.homeKeyLabel)
    }

    private var powerButton: some View {
        Button(action: showPower) {
            Image(systemName: "power").font(.system(size: 12))
                .frame(width: 40, height: 22)
                .background(LinearGradient(colors: [finish.dark.opacity(0.55), finish.light.opacity(0.25)], startPoint: .top, endPoint: .bottom), in: Capsule())
                .recessed(Capsule(), depth: 1.4, light: finish.isLight ? 0.6 : 0.2, dark: 0.55)
                .frame(width: 48, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(HardwareButtonStyle(part: .powerButton, haptics: haptics))
        .accessibilityLabel(session.powerKeyLabel)
    }

    /// b41: 选电视 before a TV is connected — the TV the TV will show, and
    /// the way to change it.
    @ViewBuilder private var chooseTVButton: some View {
        if let chooseTV {
            Button(action: chooseTV) {
                HStack(spacing: 6) {
                    if tvOutput.set == .modern {
                        Image(systemName: "tv").font(.system(size: 11, weight: .semibold))
                    } else {
                        TVArtCanvas(set: tvOutput.set).frame(width: 22, height: 17)
                    }
                    Text("选电视 · \(tvOutput.set.title)").font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 5)
                .background(SystemMenuStyle.accent.opacity(0.92), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选电视：\(tvOutput.set.title)")
            .accessibilityIdentifier("tv-choose")
        }
    }

    /// TV模式 with no TV yet: the game stays on the iPhone, and says how.
    private var noTVBadge: some View {
        Label("TV模式 · 还没接电视：控制中心 ›「屏幕镜像」", systemImage: "tv.slash")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.62), in: Capsule())
            .accessibilityIdentifier("tv-mode-no-tv")
    }

    private var pausedBadge: some View {
        Label("PAUSED", systemImage: "pause.fill").font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
    }
}

/// TV模式 with a TV connected (round 31): on the iPhone's upper screen, that
/// the picture is on the TV (the touch screen stays here, to be touched);
/// b41: the TV it is in, and 换电视.
struct TVLinkedScreen: View {
    var display: TVOutput.Display
    var layout: TVLayout
    var set: TVSet = .modern
    var look: TVLook = .best
    var choose: (() -> Void)? = nil
    var body: some View {
        GeometryReader { proxy in
            let k = max(0.6, min(1.4, proxy.size.width / 320))
            VStack(spacing: 7 * k) {
                if set == .modern {
                    Image(systemName: "tv.fill").font(.system(size: 30 * k, weight: .medium))
                } else {
                    TVArtCanvas(set: set).frame(width: 66 * k, height: 48 * k)
                }
                Text("画面在电视上").font(.system(size: 16 * k, weight: .bold, design: .rounded))
                Text("\(display.name) · \(detail)").font(.system(size: 10.5 * k, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.7)
                if let choose {
                    Button(action: choose) {
                        Label("换电视", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 10.5 * k, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12 * k).padding(.vertical, 5 * k)
                            .background(SystemMenuStyle.accent.opacity(0.92), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("换电视（现在是\(set.title)）")
                    .accessibilityIdentifier("tv-choose")
                } else {
                    Text("下面的触摸屏照常用").font(.system(size: 10 * k, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("画面在电视上：\(set == .modern ? String(localized: "现代电视") : set.title)")
        .accessibilityIdentifier("tv-mode-linked")
    }
    private var detail: String { self.set == .modern ? String(localized: "现代电视 · \(layout.title)") : "\(self.set.title) · \(look.title)" }
}
