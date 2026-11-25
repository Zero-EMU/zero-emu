import SwiftUI

/// The hinge as the Duo SDK reports it (11-06): its status and angle (the
/// SDK's `DeviceHinge.angle`). The camera's tent (帐篷) is the cover in use
/// with the hinge half open. nil: no hinge, or no report yet.
@MainActor final class HingePosture: ObservableObject {
    static let shared = HingePosture()
    enum Status: String, Sendable { case closed, partiallyOpen, fullyOpen }
    /// Published only when it changes: the play view redraws on it (b33:
    /// before, every report of a fold redrew it).
    @Published private(set) var status: Status?
    /// Kept, not published: nothing is drawn from it, and a fold reports it
    /// many times.
    private(set) var angle: Double?
    /// Left half open although the system calls the hinge closed
    /// (HalfOpenRest): the cover is in use with the Duo stood up. Published
    /// only when it changes, and written to the trace; nothing is drawn
    /// from it.
    @Published private(set) var restsHalfOpen = false
    private var rest = HalfOpenRest()
    private var restCheck: Task<Void, Never>?
    private func noteRest(_ now: Bool) {
        guard now != restsHalfOpen else { return }
        restsHalfOpen = now
        let line = now ? "hinge rests half open\(angle.map { String(format: " at %.0f°", $0) } ?? "") though the system calls it closed" : "hinge no longer rests half open"
        NSLog("[hinge] %@", line)
        #if os(iOS)
        OrientationTrace.shared.event(line)
        #endif
    }
    func update(status next: Status?, angle degrees: Double?) {
        angle = degrees
        // (the SDK's angle is in degrees here; the rule reads radians)
        let time = ProcessInfo.processInfo.systemUptime
        noteRest(rest.report(closed: next == .closed, angle: degrees.map { $0 * .pi / 180 }, at: time))
        restCheck?.cancel()
        if let due = rest.due {
            restCheck = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(max(0, due - time) * 1000) + 20))
                guard !Task.isCancelled, let self else { return }
                self.noteRest(self.rest.tick(at: ProcessInfo.processInfo.systemUptime))
            }
        }
        guard next != status else { return }
        NSLog("[hinge] %@%@", next?.rawValue ?? "none", degrees.map { String(format: " %.0f°", $0) } ?? "")
        status = next
        #if os(iOS)
        // 11-06: which display is which is learned from the hinge (the
        // iPhone Duo has three screens; CoverOrientationPolicy.screenRole).
        CoverOrientationPolicy.shared.hingeChanged()
        #endif
    }
}

/// The SDK adapter reports hardware state only. Window size is never used to
/// guess that a normal iPhone, a split window, or a rotated Duo is closed.
struct DeviceHingeObserver: ViewModifier {
    var changed: (Bool?) -> Void
    #if os(iOS) && FOLDARC_DUO_SDK
    @available(iOS 27.1, *)
    private func describe(_ hinge: DeviceHinge?) -> String {
        guard let hinge else { return "nil" }
        switch hinge.status {
        case .closed: return "closed"
        case .partiallyOpen: return "partiallyOpen"
        case .fullyOpen: return "fullyOpen"
        default: return "other"
        }
    }
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS) && FOLDARC_DUO_SDK
        if #available(iOS 27.1, *) {
            content.onHingeChange { previous, context in
                OrientationTrace.shared.event("swiftui onHingeChange \(describe(previous.hinge)) -> \(describe(context.hinge))")
                let status: HingePosture.Status? = context.hinge.map {
                    $0.status == .closed ? .closed : $0.status == .partiallyOpen ? .partiallyOpen : .fullyOpen
                }
                let degrees = context.hinge.map { $0.angle.degrees }
                // After this update, not inside it (b33: 924 logged ten
                // "Publishing changes from within view updates" as a report
                // came in on the half-open Duo).
                Task { @MainActor in HingePosture.shared.update(status: status, angle: degrees) }
                changed(context.hinge.map { $0.status == .closed })
            }
        } else { content }
        #else
        content
        #endif
    }
}

struct ClosedConsoleView: View {
    @Binding var finish: ShellFinish
    var fromDevice = false
    /// No "back to the library" when the library is what the lid closed over.
    var showsBack = true
    /// 铅笔盒's lid (PencilBoxLid): what was open inside was the pencil box
    /// (11-15: the cover is what goes with what is inside — the box's lid
    /// over the box, the console's shell over the console; nothing to switch).
    var lid = false
    var openPreview: () -> Void
    var close: () -> Void

    @ViewState private var navigationVisible = false
    @ViewState private var finishPickerVisible = false
    /// A colour only Pro has was touched: the picker says where Pro is.
    @ViewState private var finishLockedNote = false
    @AppStorage("foldarc.coverFlipped") private var coverFlipped = false
    private var showsLid: Bool { lid }
    #if os(iOS)
    @ObservedObject private var displayRole = DisplayRoleMonitor.shared
    #endif
    /// On the hardware cover the casing appears only once the display has
    /// settled in its final orientation (see DisplayRoleMonitor.coverSettled);
    /// manual previews are always visible.
    private var coverVisible: Bool {
        #if os(iOS)
        return !fromDevice || displayRole.coverSettled
        #else
        return true
        #endif
    }
    /// Interface rotation of the hardware display, or nil for manual previews.
    private func interfaceRotation(for size: CGSize) -> Double? {
        #if os(iOS)
        guard fromDevice else { return nil }
        return displayRole.coverRotation(for: size)
        #else
        return nil
        #endif
    }

    var body: some View {
        GeometryReader { safeProxy in
            GeometryReader { proxy in
                let safe = safeProxy.safeAreaInsets
                let cameras = DeviceFoldRegions.occlusions(proxy)
                let toolbar = FullScreenCoverPlacement.toolbar(size: proxy.size,
                    insets: ViewportInsets(top: safe.top, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing),
                    occlusions: cameras)
                ZStack(alignment: .topLeading) {
                    if showsLid {
                        // The pencil box's lid: what is on it takes the touch; the
                        // menu comes down from the top edge only.
                        PencilBoxLid(flipped: coverFlipped, interfaceRotation: interfaceRotation(for: proxy.size), fillsCover: fromDevice)
                    } else {
                        FullScreenClosedShellArtwork(finish: finish, flipped: coverFlipped, interfaceRotation: interfaceRotation(for: proxy.size))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("闭合的 \(finish.name) 全屏掌机外壳，游戏休眠")
                            .accessibilityHidden(finishPickerVisible)
                    }
                    PullDownConsoleNavigation(isPresented: $navigationVisible, rect: toolbar,
                                              activationRect: showsLid ? CGRect(x: 0, y: 0, width: proxy.size.width, height: 56) : CGRect(origin: .zero, size: proxy.size),
                                              keepsPresented: finishPickerVisible) {
                        HStack(spacing: 8) {
                            if showsBack {
                                Button { navigationVisible = false; close() } label: {
                                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                                }.accessibilityLabel("返回游戏库")
                            }
                            Spacer(minLength: 0)
                            Button { coverFlipped.toggle(); navigationVisible = false } label: {
                                Image(systemName: "rotate.right").frame(width: 44, height: 44)
                            }.accessibilityLabel("翻转外壳方向")
                            if !fromDevice {
                                Button { navigationVisible = false; openPreview() } label: {
                                    Image(systemName: "rectangle.expand.vertical").frame(width: 44, height: 44)
                                }.accessibilityLabel("展开掌机").accessibilityIdentifier("open-cover-preview")
                            }
                            if !showsLid {
                                Button { finishPickerVisible = true } label: {
                                    Image(systemName: "paintpalette").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("更换外壳：\(finish.name)")
                            }
                            Button { navigationVisible = false } label: {
                                Image(systemName: "chevron.up").frame(width: 44, height: 44)
                            }.accessibilityLabel("收起导航")
                        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
                    }.accessibilityHidden(finishPickerVisible)
                    if !fromDevice && !finishPickerVisible {
                        // Lift the lid by its front edge, where the latch is
                        // (round 16): a swipe up on the lower part of the cover
                        // opens the console. iPhone Duo opens with its hinge.
                        // (On the pencil box's lid only its very foot: the
                        // rest is for what is stuck on it.)
                        Color.clear.frame(width: proxy.size.width, height: showsLid ? 30 : proxy.size.height * 0.3)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                                if value.translation.height < -40 && abs(value.translation.width) < abs(value.translation.height) { openPreview() }
                            })
                            .position(x: proxy.size.width / 2, y: showsLid ? proxy.size.height - 15 : proxy.size.height * 0.85)
                            .accessibilityElement()
                            .accessibilityLabel("掀开上盖")
                            .accessibilityHint("从外壳下沿向上推")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { openPreview() }
                    }
                    if finishPickerVisible {
                        // Keep the picker in this locked window. A system
                        // popover can acquire a different interface orientation.
                        Button { finishPickerVisible = false } label: {
                            Color.black.opacity(0.25).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("收起配色")
                        VStack(spacing: 0) {
                            HStack {
                                Text("外壳配色").font(.headline)
                                Spacer()
                                Text(finish.name).font(.caption).foregroundStyle(.white.opacity(0.7))
                                Button { finishPickerVisible = false } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }.accessibilityLabel("关闭配色")
                            }
                            if finishLockedNote {
                                Text("带锁的是典藏卡带的配色：打开掌机，在「系统设置 › 典藏卡带」里开通。")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(ShellFinish.Family.allCases) { family in
                                        Text(family.label).font(.caption2).foregroundStyle(.white.opacity(0.6))
                                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6), alignment: .leading, spacing: 6) {
                                            ForEach(ShellFinish.finishes(in: family)) { choice in
                                                Button {
                                                    // (A colour only Pro has stays where it is.)
                                                    guard choice.isOpen else { finishLockedNote = true; return }
                                                    finish = choice
                                                    finishPickerVisible = false
                                                    navigationVisible = false
                                                } label: {
                                                    FinishSwatch(finish: choice, selected: finish == choice, size: 26).contentShape(Rectangle())
                                                        .overlay(alignment: .bottomTrailing) { if !choice.isOpen { ProLockBadge(size: 11) } }
                                                }.accessibilityLabel("外壳配色：\(choice.name)")
                                                    .accessibilityValue(Text(verbatim: choice.isOpen ? "" : String(localized: "典藏卡带")))
                                                    .accessibilityAddTraits(finish == choice ? .isSelected : [])
                                            }
                                        }
                                    }
                                }.padding(.vertical, 6)
                            }.frame(maxHeight: 300)
                        }.buttonStyle(.plain).foregroundStyle(.white)
                            .padding(12).frame(width: min(270, max(0, proxy.size.width - 32)))
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .rotationEffect(.degrees(FullScreenCoverPlacement.calculate(size: proxy.size, interfaceRotation: interfaceRotation(for: proxy.size)).rotationDegrees))
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    .opacity(coverVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: coverVisible)
                    .background(SplashView.background)
            }.ignoresSafeArea()
        }
        .environment(\.layoutDirection, .leftToRight)
        #if os(iOS)
        .statusBarHidden().persistentSystemOverlays(.hidden).defersSystemGestures(on: .top)
        .onAppear { OrientationTrace.shared.event("ClosedConsoleView appeared fromDevice=\(fromDevice)") }
        .onDisappear { OrientationTrace.shared.event("ClosedConsoleView disappeared") }
        #endif
    }
}

/// Adapt the casing to the display, keeping lettering and lenses undistorted.
struct FullScreenClosedShellArtwork: View {
    var finish: ShellFinish
    var flipped = false
    var interfaceRotation: Double? = nil
    var body: some View {
        GeometryReader { proxy in
            let placement = FullScreenCoverPlacement.calculate(size: proxy.size, flipped: flipped, interfaceRotation: interfaceRotation)
            face(size: placement.canvasSize).frame(width: placement.canvasSize.width, height: placement.canvasSize.height)
                .rotationEffect(.degrees(placement.rotationDegrees))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                // Screen changes can carry an implicit rotation transaction.
                // Snap the printed casing to its new hardware coordinates.
                .transaction { $0.animation = nil }
                #if os(iOS)
                .onChange(of: placement, initial: true) { _, value in
                    OrientationTrace.shared.event("cover placement viewport=\(Int(proxy.size.width))x\(Int(proxy.size.height)) canvas=\(Int(value.canvasSize.width))x\(Int(value.canvasSize.height)) rotation=\(Int(value.rotationDegrees)) theta=\(interfaceRotation.map { String(Int($0)) } ?? "nil")")
                }
                #endif
        }.background(finish.base).allowsHitTesting(false)
    }
    private func face(size: CGSize) -> some View {
        let w = size.width, h = size.height
        let unit = min(w / 760, h / 440)
        let hingeHeight = max(8, 21 * unit)
        return ZStack {
            FullScreenShellSurface(finish: finish, cover: true)
            if !finish.isLight {
                // Glossy lid: one thin, sharper reflection streak on top of the
                // broad sheen the surface already carries.
                GlossSweep(strength: finish.isTranslucent ? 0.22 : 0.15, center: 0.44, width: 0.07, angle: -34)
            }
            // Hinge barrel along the top edge: lit cylinder, knuckle seams,
            // and a shadow where the lid meets it.
            ZStack {
                LinearGradient(stops: [.init(color: finish.dark, location: 0), .init(color: finish.shade, location: 0.14),
                                      .init(color: finish.light, location: 0.36), .init(color: finish.base, location: 0.55),
                                      .init(color: finish.shade, location: 0.8), .init(color: finish.dark, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                GlossSweep(strength: finish.isLight ? 0.18 : 0.12, center: 0.5, width: 0.5, angle: 0)
                VStack(spacing: 0) { Spacer(minLength: 0); Rectangle().fill(.black.opacity(0.55)).frame(height: 1) }
            }
            .frame(width: w, height: hingeHeight).position(x: w / 2, y: hingeHeight / 2)
            ForEach([0.08, 0.3, 0.7, 0.92], id: \.self) { fraction in
                Rectangle().fill(.black.opacity(0.6)).frame(width: 1.2, height: hingeHeight)
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.22)).frame(width: 0.6).offset(x: 0.9) }
                    .position(x: w * fraction, y: hingeHeight / 2)
            }
            // Soft shadow the barrel casts onto the lid.
            LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: max(4, 9 * unit)).position(x: w / 2, y: hingeHeight + max(2, 4.5 * unit))
            if finish == .retro {
                RoundedRectangle(cornerRadius: 8).fill(RetroHardwareInk.panel)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.1), lineWidth: 0.6))
                    .frame(width: w * 0.84, height: h * 0.39).position(x: w * 0.5, y: h * 0.32)
                VStack(alignment: .leading, spacing: 7 * unit) {
                    Text("ZERO").font(.system(size: max(16, 30 * unit), weight: .heavy, design: .rounded)).tracking(2)
                    Text("FOLDING HANDHELD").font(.system(size: max(6, 11 * unit), design: .monospaced))
                    Rectangle().fill(.white.opacity(0.2)).frame(width: w * 0.42, height: 2)
                }.foregroundStyle(RetroHardwareInk.print).position(x: w * 0.44, y: h * 0.32)
                // FoldArc's own mark where the printed power/reset switches
                // and cartridge slot were until round 15o.
                RetroArcMark(unit: unit).frame(width: w * 0.48, height: h * 0.15).position(x: w * 0.5, y: h * 0.7)
                HStack(spacing: 4 * unit) {
                    ForEach(0..<4) { _ in
                        Capsule().fill(RetroHardwareInk.capsule).frame(width: 10 * unit, height: 21 * unit)
                    }
                }.rotationEffect(.degrees(-30)).position(x: w * 0.88, y: h * 0.15)
                HStack(spacing: 4 * unit) {
                    ForEach(0..<10) { _ in Rectangle().fill(finish.dark.opacity(0.65)).frame(width: max(1, unit), height: 26 * unit) }
                }.position(x: w * 0.84, y: h * 0.88)
                VStack(alignment: .leading, spacing: 2 * unit) {
                    Text("ZERO").font(.system(size: max(8, 12 * unit), weight: .heavy)).italic()
                    Text("TWO SCREENS · ONE FOLD").font(.system(size: max(4, 5 * unit), weight: .semibold))
                }.foregroundStyle(RetroHardwareInk.ink).position(x: w * 0.2, y: h * 0.87)
                Rectangle().fill(RetroHardwareInk.ink.opacity(0.8)).frame(width: 21 * unit, height: max(2, 4 * unit))
                    .position(x: w * 0.79, y: h * 0.9)
            } else {
                // Debossed wordmark: a dark impression with a light lower edge.
                ZStack {
                    Text("ZERO").font(.system(size: max(11, 18 * unit), weight: .medium, design: .rounded)).tracking(5)
                        .foregroundStyle(.white.opacity(finish.isLight ? 0.9 : 0.16)).offset(y: 0.8)
                    Text("ZERO").font(.system(size: max(11, 18 * unit), weight: .medium, design: .rounded)).tracking(5)
                        .foregroundStyle(.black.opacity(finish.isLight ? 0.28 : 0.45))
                }
            }
            // Outer cameras with the recording LED between them.
            ForEach([0.39, 0.61], id: \.self) { fraction in
                coverLens(diameter: max(5, 12 * unit)).position(x: w * fraction, y: h - max(9, 19 * unit))
            }
            Circle().fill(Color(white: 0.05)).frame(width: max(2, 4 * unit), height: max(2, 4 * unit))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
                .position(x: w * 0.5, y: h - max(9, 19 * unit))
            // Latch notch at the front edge and the power light.
            Capsule().fill(Color(white: 0.02)).frame(width: 72 * unit, height: max(2, 3 * unit))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
                .position(x: w / 2, y: h - 4)
            LED(color: .cyan).scaleEffect(max(0.6, unit * 0.9)).position(x: w * 0.9, y: h - 5)
        }
    }
    private func coverLens(diameter: Double) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [finish.light.opacity(0.7), finish.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.black).padding(diameter * 0.1)
            Circle().fill(RadialGradient(colors: [Color(red: 0.14, green: 0.27, blue: 0.38), Color(red: 0.03, green: 0.07, blue: 0.11), .black],
                                         center: UnitPoint(x: 0.42, y: 0.4), startRadius: 0, endRadius: diameter * 0.38)).padding(diameter * 0.2)
            Circle().fill(.white.opacity(0.5)).frame(width: diameter * 0.16).offset(x: -diameter * 0.16, y: -diameter * 0.17)
            Circle().fill(.white.opacity(0.18)).frame(width: diameter * 0.08).offset(x: diameter * 0.14, y: diameter * 0.16)
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.8).padding(diameter * 0.1)
        }.frame(width: diameter, height: diameter)
    }
}

/// Zero's mark on the retro grey lid, moulded: a dark groove with a light
/// lower edge, like the debossed wordmark on the other finishes. 11-07:
/// half of the app icon's ring (MenuArcMark), no longer an arc with a dot;
/// as wide as the frame allows (twice its height at most), standing on the
/// frame's foot in the middle. `unit` scales the lip.
struct RetroArcMark: View {
    var unit: Double
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let outer = min(w, 2 * h) / 2
            let band = max(1.5, 2 * outer * MenuArcMark.band)
            let arc = MenuArcMark.path(centre: CGPoint(x: w / 2, y: h), outer: outer, band: band)
            let lip = max(1, 1.2 * unit)
            ZStack {
                arc.stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: band, lineCap: .butt)).offset(y: lip)
                arc.stroke(RetroHardwareInk.groove, style: StrokeStyle(lineWidth: band, lineCap: .butt))
            }
        }
    }
}

/// Rebuilt from the official closed-lid photos: hinge at the rear, two outer
/// camera lenses on the front edge, a layered rim and subdued lacquer sheen.
/// The retro grey print is FoldArc's own artwork: wordmark, arc mark and four
/// grey capsules (round 15o removed the console-top switches and the red strip).
struct ClosedShellArtwork: View {
    var finish: ShellFinish
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46)
                .fill(LinearGradient(colors: [finish.dark, .black, finish.dark], startPoint: .top, endPoint: .bottom))
                .frame(width: 760, height: 418).offset(y: 10)
                .shadow(color: .black.opacity(0.65), radius: 22, y: 18)
            RoundedRectangle(cornerRadius: 44)
                .fill(finish.dark).frame(width: 758, height: 406).offset(y: 12)
                .overlay { RoundedRectangle(cornerRadius: 44).strokeBorder(.white.opacity(0.13), lineWidth: 1).frame(width: 758, height: 406).offset(y: 12) }
            RoundedRectangle(cornerRadius: 41)
                .fill(LinearGradient(stops: [
                    .init(color: finish.light, location: 0), .init(color: finish.light.opacity(0.9), location: 0.35),
                    .init(color: finish.dark, location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 754, height: 390).offset(y: 6)
                .overlay { RoundedRectangle(cornerRadius: 41).strokeBorder(.white.opacity(finish.isLight ? 0.5 : 0.3), lineWidth: 2).frame(width: 754, height: 390).offset(y: 6) }
                .overlay { RoundedRectangle(cornerRadius: 37).strokeBorder(.black.opacity(0.22), lineWidth: 1).frame(width: 738, height: 374).offset(y: 6) }
            if finish == .retro { retroPrint }
            else {
                Text("ZERO").font(.system(size: 15, weight: .medium, design: .rounded)).tracking(5)
                    .foregroundStyle(finish.ink.opacity(0.24)).position(x: 380, y: 216)
                RoundedRectangle(cornerRadius: 36)
                    .fill(LinearGradient(stops: [.init(color: .white.opacity(0.15), location: 0), .init(color: .clear, location: 0.48), .init(color: .clear, location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 730, height: 360).offset(y: 5)
            }
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [finish.dark, finish.light, finish.dark], startPoint: .top, endPoint: .bottom))
                .frame(width: 742, height: 32).position(x: 380, y: 22)
                .overlay {
                    HStack { seam; Spacer(); seam; Spacer().frame(width: 420); seam; Spacer(); seam }
                        .frame(width: 690).position(x: 380, y: 22)
                }
            ForEach([296.0, 464.0], id: \.self) { x in
                Circle().fill(Color(white: 0.055)).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(finish.light.opacity(0.4), lineWidth: 1.5))
                    .overlay(Circle().fill(Color(red: 0.035, green: 0.11, blue: 0.14)).frame(width: 6))
                    .overlay(Circle().fill(.white.opacity(0.28)).frame(width: 2).offset(x: -1, y: -1))
                    .position(x: x, y: 403)
            }
            Capsule().fill(.black.opacity(0.65)).frame(width: 72, height: 4).position(x: 380, y: 422)
            Capsule().fill(.cyan.opacity(0.7)).frame(width: 4, height: 7).position(x: 681, y: 423)
        }.frame(width: 760, height: 440).allowsHitTesting(false).accessibilityHidden(true)
    }
    private var seam: some View { Rectangle().fill(.black.opacity(0.55)).frame(width: 2, height: 30) }
    private var retroPrint: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.39)).frame(width: 638, height: 184).position(x: 380, y: 158)
            VStack(alignment: .leading, spacing: 7) {
                Text("ZERO").font(.system(size: 24, weight: .heavy, design: .rounded)).tracking(2)
                Text("FOLDING HANDHELD").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                HStack(spacing: 5) {
                    ForEach(0..<19) { _ in Rectangle().fill(.white.opacity(0.22)).frame(width: 17, height: 2) }
                }.padding(.top, 14)
            }.foregroundStyle(Color(white: 0.8)).position(x: 323, y: 164)
            RetroArcMark(unit: 1).frame(width: 300, height: 66).position(x: 380, y: 306)
            HStack(spacing: 5) {
                ForEach(0..<4) { _ in
                    Capsule().fill(Color(white: 0.34)).frame(width: 10, height: 21)
                }
            }.rotationEffect(.degrees(-30)).position(x: 654, y: 76)
            Text("TWO SCREENS · ONE FOLD").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                .foregroundStyle(Color(white: 0.34)).position(x: 171, y: 374)
            Rectangle().fill(Color(white: 0.34)).frame(width: 24, height: 6).position(x: 651, y: 371)
        }
    }
}
