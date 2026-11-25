import SwiftUI
#if os(iOS)
import UIKit
#endif
// Round 26: only a device build links MediaPlayer (the system's volume
// slider). The Simulator's MPVolumeView has no slider in it (10-31 probe), so
// a Simulator build has nothing to use it for. (It was taken out while
// looking for why the iPhone 17e Simulator launched FoldArc so slowly that
// day; it was not that: the launch took as long without it.)
#if os(iOS) && !targetEnvironment(simulator)
import MediaPlayer
#endif

// All hardware is drawn with native vector shapes. No photograph is used as an input surface.
/// The body colours, in families. Values are sRGB; two-tone bodies keep a
/// separate inner colour.
///
/// The raw values are the stored identifiers ("foldarc.finish" in
/// UserDefaults; StoredFinishName finds the four that had another note in
/// their brackets). What the app shows is `name` and `Family.label`.
enum ShellFinish: String, CaseIterable, Identifiable {
    // 经典
    case aqua = "水蓝", graphite = "宇宙黑", red = "烈焰红", mistyPink = "雾粉", iceWhite = "冰白"
    case cobalt = "钴蓝", midnightPurple = "午夜紫", cerulean = "蔚蓝", shimmerPink = "闪粉"
    case lightBlue = "浅蓝", glossPink = "亮粉", metallicRed = "金属红", pureWhite = "纯白", clearBlack = "透黑"
    // 双拼
    case xlSilverBlack = "银·黑", xlRedBlack = "红·黑", xlBlueBlack = "蓝·黑", xlWhite = "白（XL）"
    case xlPinkWhite = "粉·白", xlBlack = "黑（XL）", xlMintWhite = "薄荷·白"
    // 缤纷
    case flatBlackBlue = "黑·蓝", flatBlackRed = "黑·红", flatWhiteRed = "白·红", flatPinkWhite = "粉·白（缤纷）"
    case flatSeaGreen = "海绿·白", flatCrystalBlue = "晶蓝", flatCrystalRed = "晶红", flatClearBlack = "透黑（缤纷）"
    case flatBlue = "蓝（2016）", flatRed = "红（2016）", flatLavender = "薰衣草", flatPink = "粉（缤纷）"
    case flatWhiteYellow = "黄·白", flatLightBlue = "浅蓝（缤纷）"
    // 素色
    case newWhite = "新·白", newBlack = "新·黑"
    // 光泽
    case blue = "金属蓝", metallicBlack = "金属黑", pearl = "珍珠白", newMetallicRed = "金属绯红"
    case limeBlack = "青柠·黑", newPinkWhite = "粉·白（New）", orangeBlack = "橙·黑"
    // 撞色
    case flatBlackTurquoise = "黑·青", flatWhiteOrange = "白·橙", flatBlackLime = "黑·青柠"
    case flatWhiteLavender = "白·薰衣草", flatPurpleSilver = "紫·银"
    // Zero
    case retro = "复古灰"

    var id: Self { self }

    enum Family: String, CaseIterable, Identifiable {
        case original, originalXL, flat, new, newXL, newFlatXL, foldArc
        var id: Self { self }
        /// The group's name in the app.
        var label: String {
            switch self {
            case .original: return String(localized: "经典")
            case .originalXL: return String(localized: "双拼")
            case .flat: return String(localized: "缤纷")
            case .new: return String(localized: "素色")
            case .newXL: return String(localized: "光泽")
            case .newFlatXL: return String(localized: "撞色")
            case .foldArc: return "Zero"
            }
        }
    }
    /// The colour's name in the app.
    var name: String {
        switch self {
        case .aqua: return String(localized: "深海青")
        case .graphite: return String(localized: "曜石黑")
        case .red: return String(localized: "朱红")
        case .mistyPink: return String(localized: "樱花粉")
        case .iceWhite: return String(localized: "瓷白")
        case .cobalt: return String(localized: "藏蓝")
        case .midnightPurple: return String(localized: "葡萄紫")
        case .cerulean: return String(localized: "琉璃蓝")
        case .shimmerPink: return String(localized: "桃花粉")
        case .lightBlue: return String(localized: "天青")
        case .glossPink: return String(localized: "莓果粉")
        case .metallicRed: return String(localized: "酒红")
        case .pureWhite: return String(localized: "雪白")
        case .clearBlack: return String(localized: "烟晶黑")
        case .xlSilverBlack: return String(localized: "银·黑")
        case .xlRedBlack: return String(localized: "红·黑")
        case .xlBlueBlack: return String(localized: "蓝·黑")
        case .xlWhite: return String(localized: "象牙白")
        case .xlPinkWhite: return String(localized: "粉·白")
        case .xlBlack: return String(localized: "墨黑")
        case .xlMintWhite: return String(localized: "浅碧·白")
        case .flatBlackBlue: return String(localized: "黑·宝蓝")
        case .flatBlackRed: return String(localized: "黑·石榴红")
        case .flatWhiteRed: return String(localized: "白·赤红")
        case .flatPinkWhite: return String(localized: "淡粉·白")
        case .flatSeaGreen: return String(localized: "孔雀绿·白")
        case .flatCrystalBlue: return String(localized: "透光蓝")
        case .flatCrystalRed: return String(localized: "透光红")
        case .flatClearBlack: return String(localized: "透光黑")
        case .flatBlue: return String(localized: "海蓝")
        case .flatRed: return String(localized: "番茄红")
        case .flatLavender: return String(localized: "丁香紫")
        case .flatPink: return String(localized: "蜜桃粉")
        case .flatWhiteYellow: return String(localized: "金盏黄·白")
        case .flatLightBlue: return String(localized: "晴空蓝")
        case .newWhite: return String(localized: "云白")
        case .newBlack: return String(localized: "夜黑")
        case .blue: return String(localized: "星夜蓝")
        case .metallicBlack: return String(localized: "钛黑")
        case .pearl: return String(localized: "羊脂白")
        case .newMetallicRed: return String(localized: "枫红")
        case .limeBlack: return String(localized: "草绿·黑")
        case .newPinkWhite: return String(localized: "柔粉·白")
        case .orangeBlack: return String(localized: "橙·黑")
        case .flatBlackTurquoise: return String(localized: "黑·青")
        case .flatWhiteOrange: return String(localized: "白·橙")
        case .flatBlackLime: return String(localized: "黑·草绿")
        case .flatWhiteLavender: return String(localized: "白·丁香紫")
        case .flatPurpleSilver: return String(localized: "紫·银")
        case .retro: return String(localized: "复古灰")
        }
    }
    var family: Family {
        switch self {
        case .aqua, .graphite, .red, .mistyPink, .iceWhite, .cobalt, .midnightPurple, .cerulean, .shimmerPink,
             .lightBlue, .glossPink, .metallicRed, .pureWhite, .clearBlack: return .original
        case .xlSilverBlack, .xlRedBlack, .xlBlueBlack, .xlWhite, .xlPinkWhite, .xlBlack, .xlMintWhite: return .originalXL
        case .flatBlackBlue, .flatBlackRed, .flatWhiteRed, .flatPinkWhite, .flatSeaGreen, .flatCrystalBlue, .flatCrystalRed,
             .flatClearBlack, .flatBlue, .flatRed, .flatLavender, .flatPink, .flatWhiteYellow, .flatLightBlue: return .flat
        case .newWhite, .newBlack: return .new
        case .blue, .metallicBlack, .pearl, .newMetallicRed, .limeBlack, .newPinkWhite, .orangeBlack: return .newXL
        case .flatBlackTurquoise, .flatWhiteOrange, .flatBlackLime, .flatWhiteLavender, .flatPurpleSilver: return .newFlatXL
        case .retro: return .foldArc
        }
    }
    static func finishes(in family: Family) -> [ShellFinish] { allCases.filter { $0.family == family } }

    /// Body pigment (sRGB hex). Light/shade/dark are derived unless tuned below.
    private var baseHex: UInt32 {
        switch self {
        case .aqua: return 0x005F80
        case .graphite: return 0x242326
        case .red: return 0xC70923
        case .mistyPink: return 0xE7A4BC
        case .iceWhite: return 0xF1F1EE
        case .cobalt: return 0x1B3F8B
        case .midnightPurple: return 0x3B2A5E
        case .cerulean: return 0x2F7FC1
        case .shimmerPink: return 0xF0A7C9
        case .lightBlue: return 0x86C4E0
        case .glossPink: return 0xE85C93
        case .metallicRed: return 0x8F1D2C
        case .pureWhite: return 0xF6F6F4
        case .clearBlack: return 0x1C1B1E
        case .xlSilverBlack: return 0xC2C6CA
        case .xlRedBlack: return 0xC8202F
        case .xlBlueBlack: return 0x1F57A8
        case .xlWhite: return 0xF1F1EE
        case .xlPinkWhite: return 0xF2A7C0
        case .xlBlack: return 0x1E1E20
        case .xlMintWhite: return 0xA4D9C8
        case .flatBlackBlue: return 0x212226
        case .flatBlackRed: return 0x212226
        case .flatWhiteRed: return 0xF4F3EE
        case .flatPinkWhite: return 0xF1A9C4
        case .flatSeaGreen: return 0x2DA48C
        case .flatCrystalBlue: return 0x2E6DB4
        case .flatCrystalRed: return 0xB5203A
        case .flatClearBlack: return 0x1C1B1E
        case .flatBlue: return 0x1F5FBF
        case .flatRed: return 0xD7252F
        case .flatLavender: return 0xB8A1D9
        case .flatPink: return 0xF2A3BF
        case .flatWhiteYellow: return 0xF2C530
        case .flatLightBlue: return 0x9CCBE6
        case .newWhite: return 0xF4F3F0
        case .newBlack: return 0x202022
        case .blue: return 0x004687
        case .metallicBlack: return 0x2D2D31
        case .pearl: return 0xEEEEED
        case .newMetallicRed: return 0x961F2E
        case .limeBlack: return 0xA6CF3A
        case .newPinkWhite: return 0xF3A8C2
        case .orangeBlack: return 0xF07A1F
        case .flatBlackTurquoise: return 0x1F2023
        case .flatWhiteOrange: return 0xF4F3EE
        case .flatBlackLime: return 0x1F2023
        case .flatWhiteLavender: return 0xF4F3EE
        case .flatPurpleSilver: return 0x5B4B8A
        case .retro: return 0xBEC1C4
        }
    }
    /// Colour of the inner body / second tone. Same finish means single-tone.
    var innerShell: ShellFinish {
        switch self {
        case .xlSilverBlack, .xlRedBlack, .xlBlueBlack, .limeBlack, .orangeBlack: return .xlBlack
        case .xlPinkWhite, .xlMintWhite, .newPinkWhite, .flatPinkWhite, .flatSeaGreen, .flatWhiteYellow: return .xlWhite
        case .flatBlackBlue: return .flatBlue
        case .flatBlackRed, .flatWhiteRed: return .flatRed
        case .flatBlackTurquoise: return .flatSeaGreen
        case .flatWhiteOrange: return .orangeBlack
        case .flatBlackLime: return .limeBlack
        case .flatWhiteLavender: return .flatLavender
        case .flatPurpleSilver: return .xlSilverBlack
        default: return self
        }
    }
    var isTwoTone: Bool { innerShell != self }
    /// Translucent shells get a slightly glassy highlight.
    var isTranslucent: Bool {
        switch self {
        case .flatCrystalBlue, .flatCrystalRed, .flatClearBlack, .clearBlack: return true
        default: return false
        }
    }

    private static func component(_ hex: UInt32, _ shift: UInt32) -> Double { Double((hex >> shift) & 255) / 255 }
    private static func mix(_ hex: UInt32, toward target: Double, by amount: Double) -> Color {
        func m(_ c: Double) -> Double { c + (target - c) * amount }
        return Color(.sRGB, red: m(component(hex, 16)), green: m(component(hex, 8)), blue: m(component(hex, 0)), opacity: 1)
    }
    private var luminance: Double {
        0.2126 * Self.component(baseHex, 16) + 0.7152 * Self.component(baseHex, 8) + 0.0722 * Self.component(baseHex, 0)
    }
    var isLight: Bool { luminance > 0.6 }

    // The six original finishes keep their hand-tuned highlight/shadow values.
    var light: Color {
        switch self {
        case .retro: return Color(shellRGB: 0xC7C9CC)
        case .aqua: return Color(shellRGB: 0x008FAE)
        case .graphite: return Color(shellRGB: 0x454447)
        case .red: return Color(shellRGB: 0xE42137)
        case .pearl: return Color(shellRGB: 0xF7F7F5)
        case .blue: return Color(shellRGB: 0x00539F)
        default: return Self.mix(baseHex, toward: 1, by: isLight ? 0.4 : (isTranslucent ? 0.22 : 0.12))
        }
    }
    var base: Color { Color(shellRGB: baseHex) }
    var shade: Color {
        switch self {
        case .retro: return Color(shellRGB: 0xB3B6BA)
        case .aqua: return Color(shellRGB: 0x003C58)
        case .graphite: return Color(shellRGB: 0x121215)
        case .red: return Color(shellRGB: 0x9C061C)
        case .pearl: return Color(shellRGB: 0xDFE1E2)
        case .blue: return Color(shellRGB: 0x002D61)
        default: return Self.mix(baseHex, toward: 0, by: isLight ? 0.06 : 0.14)
        }
    }
    var dark: Color {
        switch self {
        case .retro: return Color(shellRGB: 0x8D9196)
        case .aqua: return Color(shellRGB: 0x001A31)
        case .graphite: return Color(shellRGB: 0x070809)
        case .red: return Color(shellRGB: 0x650619)
        case .pearl: return Color(shellRGB: 0xC1C5C7)
        case .blue: return Color(shellRGB: 0x031B34)
        default: return Self.mix(baseHex, toward: 0, by: isLight ? 0.2 : 0.45)
        }
    }
    var ink: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.65) }
}

extension Color {
    init(shellRGB: UInt32) {
        self.init(.sRGB, red: Double((shellRGB >> 16) & 255) / 255,
                  green: Double((shellRGB >> 8) & 255) / 255, blue: Double(shellRGB & 255) / 255, opacity: 1)
    }
}

enum RetroHardwareInk {
    static let blue = Color(shellRGB: 0x005CB5)
    static let green = Color(shellRGB: 0x009562)
    static let yellow = Color(shellRGB: 0xE8B927)
    static let red = Color(shellRGB: 0xCC2638)
    static let panel = Color(shellRGB: 0x85898F)
    static let print = Color(shellRGB: 0xE3E5E6)
    /// The four capsules on the lid: one neutral grey (they were blue, green,
    /// yellow and red until the 15th round).
    static let capsule = Color(shellRGB: 0x6E7277)
    /// The arc mark's groove, and the small print at the lid's lower edge
    /// (15o: they replaced the printed power/reset switches and the red strip).
    static let groove = Color(shellRGB: 0x777B81)
    static let ink = Color(shellRGB: 0x5C6067)
}

struct HardwareConsole: View {
    @ObservedObject var session: DemoSession
    var finish: ShellFinish
    /// Round 31: a two-tone finish's outer colour — the casing round each
    /// face and the hinge (`finish` is the faces'); nil: one colour.
    var outer: ShellFinish? = nil
    /// How far the lid is folded towards closed, in degrees (0 = open flat).
    /// 桌面模式 sets it through its hinge; other modes leave it at 0.
    var lidTilt = 0.0
    /// 桌面模式: the hinge is a control (drag to fold, tap to click between
    /// the two detents, fold past the stop to shut the lid and sleep).
    var hinge: HingeControl? = nil
    var brightness: Double = 1
    var haptics = true
    var showHome: () -> Void
    var showHelp: () -> Void
    var showPower: (() -> Void)?
    /// The charge light follows the iPhone's charging state.
    @ObservedObject var battery = BatteryLight.shared
    /// A menu drawn in the LCDs instead of the game (the HOME menu, round
    /// 17). Set by whoever draws the faces: `body` from the environment,
    /// DuoConsoleView from its own (the faces are drawn outside this view's
    /// hierarchy there, where an environment read is not allowed).
    var screenOverlay: ScreenOverlay? = nil
    @Environment(\.screenOverlay) private var environmentOverlay

    static let designWidth = 760.0
    static let designHeight = ConsoleMetrics.panel.height * 2 + ConsoleMetrics.hingeHeight

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.designWidth
            let console = withOverlay(environmentOverlay)
            VStack(spacing: 0) {
                console.upperShell
                    .rotation3DEffect(.degrees(-lidTilt), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.22)
                console.hingeBarrel
                console.lowerShell
            }
            // The hinge's touch area lies over both halves, above everything:
            // once the lid was tilted, its 3D projection took the touches on
            // the hinge (10-28, iPhone 17e Simulator: the second tap on a
            // slightly folded lid did nothing).
            .overlay(alignment: .top) {
                if let hinge {
                    HingeHandle(control: hinge)
                        .padding(.top, ConsoleMetrics.panel.height + ConsoleMetrics.hingeHeight / 2 - HingeHandle.height / 2)
                }
            }
            .frame(width: Self.designWidth, height: Self.designHeight)
            .shadow(color: .black.opacity(0.6), radius: 28, x: 0, y: 24)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .preference(key: LowerScreenWidthKey.self, value: ConsoleMetrics.lowerLCD.width * scale)
        }
        .aspectRatio(Self.designWidth / Self.designHeight, contentMode: .fit)
    }

    func withOverlay(_ overlay: ScreenOverlay?) -> HardwareConsole {
        var console = self
        console.screenOverlay = overlay
        return console
    }

    var upperShell: some View {
        ZStack {
            shellPlate(height: 440)
            RoundedRectangle(cornerRadius: 34).fill(Color(white: 0.045))
                .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(.white.opacity(0.10), lineWidth: 1.5))
                .padding(11)
                .overlay {
                    if finish.isLight {
                        RoundedRectangle(cornerRadius: 34).fill(finish.light.opacity(0.94)).padding(11)
                            .allowsHitTesting(false)
                    }
                }
            // A subtle diagonal sheen across the glass surround, away from the LCD.
            RoundedRectangle(cornerRadius: 29)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.085), location: 0), .init(color: .clear, location: 0.45), .init(color: .white.opacity(0.015), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(15).allowsHitTesting(false)
            upperFace
        }.frame(width: 760, height: 440)
    }

    var upperFace: some View {
        ZStack {
            lens.position(x: 380, y: 27)
            Circle().fill(Color(white: 0.14)).frame(width: 7, height: 7).position(x: 406, y: 27)
            LCDFrame {
                Group {
                    if let overlay = screenOverlay {
                        overlay.top
                    } else if let core = session.core {
                        CoreTopScreen(session: core)
                    } else {
                        StarField(state: session.state, squareCorners: true, depth: session.depth3D)
                            .screenFilter(native: ScreenPixels.upper)
                    }
                }
                    .overlay(Color.black.opacity(1 - brightness).allowsHitTesting(false))
                    .overlay { if session.paused && screenOverlay == nil { pauseBadge } }
            }.frame(width: ConsoleMetrics.upperLCD.width + 12, height: ConsoleMetrics.upperLCD.height + 12)
                .position(x: ConsoleMetrics.upperLCD.midX, y: ConsoleMetrics.upperLCD.midY)
            SpeakerGrille().position(x: 74, y: 211)
            SpeakerGrille().position(x: 686, y: 211)
            DepthSlider(depth: Binding(get: { session.depth3D }, set: { session.setDepth3D($0) }), ink: finish.ink, haptics: haptics)
                .position(x: 706, y: 313)
            VolumeSlider(ink: finish.ink, haptics: haptics)
                .position(x: 54, y: 313)
            ForEach([46.0, 714.0], id: \.self) { x in
                bumper.position(x: x, y: 42)
                bumper.position(x: x, y: 406)
            }
        }.frame(width: 760, height: 440)
    }

    var lowerShell: some View {
        ZStack {
            shellPlate(height: 440)
            RoundedRectangle(cornerRadius: 35)
                .fill(LinearGradient(colors: [finish.light, finish.dark.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 35).strokeBorder(.white.opacity(0.1)))
                .padding(.horizontal, 9).padding(.top, 3).padding(.bottom, 10)
            lowerFace
        }.frame(width: 760, height: 440)
    }

    var lowerFace: some View {
        ZStack {
            LCDFrame {
                Group {
                    if let overlay = screenOverlay {
                        overlay.bottom
                    } else if let core = session.core {
                        CoreTouchScreen(session: core).disabled(session.paused)
                    } else {
                        TouchMap(state: session.state, touch: session.touch, squareCorners: true, showCoordinates: session.showTouchCoordinates)
                            .screenFilter(native: ScreenPixels.lower)
                    }
                }
                    .overlay(Color.black.opacity(1 - brightness).allowsHitTesting(false))
                    // The stylus in the hand: its tip where the screen is touched (round 23).
                    .modifier(StylusTrace())
            }.frame(width: ConsoleMetrics.lowerLCD.width + 12, height: ConsoleMetrics.lowerLCD.height + 12)
                .position(x: ConsoleMetrics.lowerLCD.midX, y: ConsoleMetrics.lowerLCD.midY)
            AnalogPad(haptics: haptics, demo: session.core == nil, changed: session.setAnalog)
                .frame(width: 94, height: 94).position(x: 91, y: 116)
            DirectionPad(changed: session.setDirections, haptics: haptics)
                .frame(width: 96, height: 96).position(x: 91, y: 276)
            AnalogPad(isCStick: true, haptics: haptics, demo: session.core == nil, changed: session.setCamera)
                .frame(width: 30, height: 30).position(x: 632, y: 76)
            abxy.position(x: 670, y: 187)
            smallKey(.start, title: "START", y: 309)
            smallKey(.select, title: "SELECT", y: 350)
            Button(action: showHome) {
                VStack(spacing: 5) {
                    Image(systemName: "house").font(.system(size: 12, weight: .medium))
                        .frame(width: 53, height: 22)
                        .background(LinearGradient(colors: [finish.dark.opacity(0.55), finish.light.opacity(0.25)], startPoint: .top, endPoint: .bottom), in: Capsule())
                        .recessed(Capsule(), depth: 1.6, light: finish.isLight ? 0.6 : 0.2, dark: 0.55)
                    Text("HOME").font(.system(size: 8, weight: .medium)).tracking(1)
                }.foregroundStyle(finish.ink).frame(width: 80, height: 50)
                    .contentShape(Rectangle())
            }.buttonStyle(HardwareButtonStyle(part: .homeButton, haptics: haptics))
                .accessibilityLabel(session.homeKeyLabel)
                .position(x: 380, y: 399)
            MicHole(ink: finish.ink, haptics: haptics, blowing: session.micBlowing) { session.setMicBlowing($0) }
                .position(x: 480, y: 391)
            Button(action: showPower ?? showHome) {
                Image(systemName: "power").font(.system(size: 10)).foregroundStyle(finish.ink)
                    .accessibilityHidden(true)
                    .frame(width: 34, height: 17)
                    .background(LinearGradient(colors: [finish.dark.opacity(0.55), finish.light.opacity(0.25)], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .recessed(Capsule(), depth: 1.4, light: finish.isLight ? 0.6 : 0.2, dark: 0.55)
                    // The switch is small, its touch area is not (64×40, about
                    // 56×35 pt on iPhone Duo): a 34×17 target missed taps
                    // (round 16 suite, a tap on POWER during a game).
                    .frame(width: 64, height: 40).contentShape(Rectangle())
            }.buttonStyle(HardwareButtonStyle(part: .powerButton, haptics: haptics))
                // Labelled on the button, before it is positioned: XCUITest
                // sometimes reported the whole lower half as POWER's frame.
                .accessibilityLabel(session.powerKeyLabel)
                .position(x: 691, y: 419)
            HStack(spacing: 9) {
                LED(color: session.paused ? .orange : .cyan)
                // Round 26: it comes on and goes out softly as the iPhone
                // is plugged in or out (out once full, as on the handheld).
                LED(color: .orange, lit: battery.charging)
                    .animation(.easeInOut(duration: 0.45), value: battery.charging)
                    .accessibilityElement().accessibilityLabel(battery.charging ? "充电指示灯：正在充电" : (battery.pluggedIn ? "充电指示灯：已充满" : "充电指示灯：未充电"))
            }.allowsHitTesting(false).position(x: 703, y: 435)
            Text("Z E R O").font(.system(size: 8, weight: .semibold)).foregroundStyle(finish.ink).position(x: 83, y: 406)
            // Headphones connected: the plug in the jack on the front edge,
            // its cable falling away (round 23; the 3D console shows the
            // whole pair).
            EarphonePlugTop(finish: finish)
                .position(x: 180, y: 440 + 75)
                .allowsHitTesting(false)
        }.frame(width: 760, height: 440)
    }

    var hingeBarrel: some View {
        let casing = outer ?? finish
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(stops: [.init(color: casing.dark, location: 0), .init(color: casing.light, location: 0.25), .init(color: casing.light.opacity(0.85), location: 0.43), .init(color: casing.dark, location: 0.95)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.75), lineWidth: 1))
            HStack(spacing: 0) {
                hingeSeam; Spacer(); hingeSeam; Spacer().frame(width: 30); hingeSeam; Spacer(); hingeSeam
            }.padding(.horizontal, 70)
            Capsule().fill(.white.opacity(0.12)).frame(width: 252, height: 2).offset(y: -5)
        }.frame(width: 742, height: ConsoleMetrics.hingeHeight)
    }
    private var hingeSeam: some View { Rectangle().fill(.black.opacity(0.6)).frame(width: 2, height: 29).overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.15)).frame(width: 0.5) } }
    /// Rubber stand-off on the lid face.
    private var bumper: some View {
        Capsule().fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
            .frame(width: 22, height: 6)
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
    }
    private var lens: some View {
        ZStack {
            // Bezel ring, glass, iris, two catch-lights.
            Circle().fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.black).padding(1.5)
            Circle().fill(RadialGradient(colors: [Color(red: 0.16, green: 0.30, blue: 0.42), Color(red: 0.04, green: 0.08, blue: 0.13), .black], center: UnitPoint(x: 0.42, y: 0.4), startRadius: 0, endRadius: 7)).padding(3.5)
            Circle().fill(Color(red: 0.30, green: 0.12, blue: 0.32).opacity(0.5)).frame(width: 4).offset(x: 1.5, y: 1.5)
            Circle().fill(.white.opacity(0.55)).frame(width: 2.6).offset(x: -2.6, y: -2.8)
            Circle().fill(.white.opacity(0.22)).frame(width: 1.4).offset(x: 2.4, y: 2.8)
            Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.8).padding(1.5)
        }.frame(width: 18, height: 18)
    }
    private var abxy: some View {
        ZStack {
            hardwareKey(.x, color: RetroHardwareInk.blue).offset(y: -44)
            hardwareKey(.a, color: RetroHardwareInk.red).offset(x: 44)
            hardwareKey(.b, color: RetroHardwareInk.yellow).offset(y: 44)
            hardwareKey(.y, color: RetroHardwareInk.green).offset(x: -44)
        }.frame(width: 150, height: 150)
    }
    private func hardwareKey(_ key: PadButton, color: Color) -> some View {
        // Dark caps with coloured letters on every finish. The retro grey had
        // fully coloured caps until round 15o.
        HardwareKey(key: key, color: color, haptics: haptics, press: session.press).frame(width: 41, height: 41)
    }
    private func smallKey(_ key: PadButton, title: String, y: Double) -> some View {
        SmallKey(title: title, ink: finish.ink, isLight: finish.isLight, haptics: haptics,
                 accessibility: session.core != nil ? title : (key == .start ? String(localized: "START 暂停或继续") : String(localized: "SELECT 游戏按键，切换地图坐标"))) { down in
            session.press(key, down: down)
        }.position(x: 669, y: y)
    }
    private func shellPlate(height: Double) -> some View {
        let casing = outer ?? finish
        return RoundedRectangle(cornerRadius: 42)
            .fill(LinearGradient(colors: [casing.light, casing.dark, casing.light.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 42).strokeBorder(.white.opacity(0.28), lineWidth: 1.5))
            .overlay(RoundedRectangle(cornerRadius: 40).inset(by: 4).strokeBorder(.black.opacity(0.7), lineWidth: 2))
            .frame(width: 760, height: height)
    }
    private var pauseBadge: some View {
        Label("PAUSED", systemImage: "pause.fill").font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 12)
            .background(.black.opacity(0.7), in: Capsule())
    }
}

/// The casing reaches all physical display edges. `upper` is the inside of
/// the lid: a glossy black (or, on light shells, light) face with a
/// reflection sweep. It is drawn edge to edge so the device's rounded
/// screen corners never expose a rim of casing colour.
struct FullScreenShellSurface: View {
    var finish: ShellFinish
    var upper = false
    var cover = false
    // (Round 31 b2 drew a rim of a two-tone finish's outer colour round the
    // edge; the display's rounded corners cut it off: gone again. The casing stays edge to edge in
    // the faces' colour; the outer colour is the hinge's. b5: the fine bevel
    // that ran along the very edge (a dark hairline 0.75 pt in, a light one
    // 2 pt in) went too: the rounded corners cut it the same way. Nothing
    // is drawn along the edges now; the vignette darkens the corners softly.)
    var body: some View {
        ZStack {
            // Casing colour: a broad top-left light, mid tone, deeper bottom-right.
            Rectangle().fill(LinearGradient(stops: [
                .init(color: finish.light, location: 0), .init(color: finish.base, location: cover && !finish.isLight ? 0.2 : 0.32),
                .init(color: cover && !finish.isLight ? finish.shade : finish.base, location: 0.64),
                .init(color: cover && !finish.isLight ? finish.dark : finish.shade, location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            if upper {
                // Inside of the lid.
                if finish.isLight {
                    Rectangle().fill(LinearGradient(colors: [finish.light, finish.base], startPoint: .top, endPoint: .bottom))
                } else {
                    Rectangle().fill(LinearGradient(stops: [
                        .init(color: Color(shellRGB: 0x2B2C31), location: 0),
                        .init(color: Color(shellRGB: 0x19191C), location: 0.42),
                        .init(color: Color(shellRGB: 0x0A0B0D), location: 1)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                GlossSweep(strength: finish.isLight ? 0.22 : 0.12, center: 0.34, width: 0.30, angle: -34)
                Vignette(strength: finish.isLight ? 0.10 : 0.42)
                Grain(opacity: finish.isLight ? 0.05 : 0.035, count: 1400)
            } else {
                // Matte casing: faint grain, soft sheen, corners fall away.
                Grain(opacity: finish.isLight ? 0.09 : 0.07, count: 1600)
                GlossSweep(strength: finish.isLight ? 0.10 : 0.09, center: 0.26, width: 0.34, angle: -30)
                Vignette(strength: finish.isLight ? 0.08 : 0.22)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The chosen 画面滤镜 over a game screen (the demo's drawn ones; the core's
/// picture does it in CoreScreen, where it also scales smoothly).
struct ScreenFilterModifier: ViewModifier {
    var native: CGSize
    /// b41: an old TV's filter (OldTVScreen) instead of the settings'.
    var fixed: ScreenFilter? = nil
    @AppStorage(ScreenFilter.defaultsKey) private var filterID = ScreenFilter.sharp.rawValue
    func body(content: Content) -> some View {
        let filter = fixed ?? ScreenFilter(rawValue: filterID) ?? .sharp
        content
            .saturation(filter == .crt ? 1.12 : 1)
            .overlay { ScreenFilterOverlay(filter: filter, native: native).equatable().allowsHitTesting(false).accessibilityHidden(true) }
    }
}
extension View {
    /// 画面滤镜 over a screen of `native` 3DS pixels (`filter`: that one, not
    /// the settings').
    func screenFilter(native: CGSize, filter: ScreenFilter? = nil) -> some View { modifier(ScreenFilterModifier(native: native, fixed: filter)) }
}
enum ScreenPixels {
    static let upper = CGSize(width: 400, height: 240)
    static let lower = CGSize(width: 320, height: 240)
}

struct LCDFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        content()
            .overlay {
                // Glass over the panel: a faint diagonal reflection and a
                // shadow line where the bezel overhangs the top edge.
                ZStack {
                    LinearGradient(stops: [.init(color: .white.opacity(0.07), location: 0), .init(color: .white.opacity(0.02), location: 0.35), .init(color: .clear, location: 0.36)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom).frame(height: 7)
                        Spacer(minLength: 0)
                    }
                }.allowsHitTesting(false)
            }
            .padding(6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.02))
                    RoundedRectangle(cornerRadius: 6).strokeBorder(LinearGradient(colors: [.black, Color(white: 0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    RoundedRectangle(cornerRadius: 5).inset(by: 1).strokeBorder(.white.opacity(0.07), lineWidth: 0.8)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
    }
}
struct SpeakerGrille: View {
    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<5) { row in
                HStack(spacing: 5) {
                    ForEach(0..<3) { column in
                        // Drilled holes: dark inside, a hair of light on the lower rim.
                        Circle().fill(RadialGradient(colors: [Color(white: 0.0), Color(white: 0.06)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 3))
                            .frame(width: 4.2, height: 4.2)
                            .overlay(Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.9), .white.opacity(0.18)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                            .opacity((row == 0 || row == 4) && column == 1 ? 1 : ((row == 0 || row == 4) ? 0 : 1))
                    }
                }
            }
        }.frame(width: 30, height: 52).accessibilityHidden(true)
    }
}
struct LED: View {
    var color: Color
    var lit = true
    var body: some View {
        ZStack {
            Capsule().fill(.black.opacity(0.55))
            Capsule().fill(lit ? color : Color(white: 0.12)).padding(0.8)
            Capsule().fill(LinearGradient(colors: [.white.opacity(lit ? 0.55 : 0.18), .clear], startPoint: .top, endPoint: .center)).padding(1.2)
        }
        .frame(width: 5, height: 8)
        .shadow(color: lit ? color.opacity(0.7) : .clear, radius: 5)
    }
}
struct HardwareButtonStyle: ButtonStyle {
    /// HOME and POWER feel like their switches (round 16); plain otherwise.
    var part: HapticPart? = nil
    var haptics = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if let part { ConsoleHaptics.shared.play(part, pressed ? .press : .release, enabled: haptics) }
            }
            .micPointerObstacle()
    }
}

/// START and SELECT: small membrane buttons that can be held (round 16;
/// before, a tap sent press and release at once and could be missed).
struct SmallKey: View {
    var title: String
    var ink: Color
    var isLight: Bool
    var haptics = true
    var accessibility: String
    /// Width of the touch area (the dome and its label).
    var width = 112.0
    var press: (Bool) -> Void
    @GestureState private var held = false
    /// 手柄样式 圆润: the casing's own plastic, a size larger.
    @Environment(\.controlLook) private var look
    /// In b67b's render 圆润 on the cover read 「SEL…」: in a narrow
    /// column the soft key's name goes under it.
    private var stacked: Bool {
        if case .soft = look { return width < 84 }
        return false
    }
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        HStack(spacing: 9) {
            if case .soft(let finish) = look {
                if stacked {
                    VStack(spacing: 2) {
                        SoftKeyFace(shape: Circle(), finish: finish, held: held).frame(width: 26, height: 26)
                        SoftLetters(text: title, finish: finish, size: 10).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    SoftKeyFace(shape: Circle(), finish: finish, held: held).frame(width: 26, height: 26)
                    SoftLetters(text: title, finish: finish, size: 12).minimumScaleFactor(0.6)
                }
            } else {
                ZStack {
                    Circle().fill(Color(white: 0.03))
                    DomeCap(color: Color(white: held ? 0.15 : 0.22), pressed: held).padding(2)
                        .offset(y: held ? 0.4 : 0)
                        .shadow(color: .black.opacity(0.5), radius: held ? 0.4 : 1.2, y: held ? 0.4 : 1.5)
                }.frame(width: 18, height: 18)
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .shadow(color: isLight ? .white.opacity(0.7) : .black.opacity(0.7), radius: 0, y: isLight ? 0.7 : -0.7)
            }
        }
        .frame(width: width, height: stacked ? 42 : 36, alignment: stacked ? .center : .leading).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).updating($held) { _, state, _ in state = true })
        .onChange(of: held) { _, down in
            press(down)
            ConsoleHaptics.shared.play(.smallButton, down ? .press : .release, enabled: haptics)
        }
        .onDisappear { press(false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility).accessibilityAddTraits(.isButton)
        .accessibilityAction { press(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { press(false) } }
    }
}

/// The 3D slider (round 16: it works). Its position is the 3D slider the game
/// reads, 0–100 % in the core's 10 % steps; while it is up the picture is
/// red/cyan anaglyph (Stereo3D), and the 3D light beside it is on. Each step
/// is a notch you feel; the bottom is a firm stop at OFF.
struct DepthSlider: View {
    @Binding var depth: Double
    var ink: Color
    var haptics = true
    /// Knob travel along the 65-point track (knob 19 high).
    static let travel = 46.0
    @ViewState private var dragStart: Double?
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("3D").font(.system(size: 11, weight: .semibold))
                LED(color: Color(red: 0.45, green: 0.8, blue: 1), lit: depth > 0).scaleEffect(0.8)
            }
            ZStack(alignment: .bottom) {
                Capsule().fill(Color(white: 0.02)).frame(width: 5, height: 65)
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(LinearGradient(colors: [Color(white: 0.46), Color(white: 0.26)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 13, height: 19)
                    .overlay(VStack(spacing: 2.5) { ForEach(0..<3) { _ in Capsule().fill(.black.opacity(0.35)).frame(width: 7, height: 1) } })
                    .raised(RoundedRectangle(cornerRadius: 2.5), light: 0.45, dark: 0.6, lift: 1.5)
                    .offset(y: -depth * Self.travel)
            }.frame(height: 65)
            Text("OFF").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? depth
                if dragStart == nil { dragStart = start }
                let next = (min(1, max(0, start - value.translation.height / Self.travel)) * 10).rounded() / 10
                guard next != depth else { return }
                ConsoleHaptics.shared.play(next == 0 ? .sliderStop : .sliderNotch, enabled: haptics)
                depth = next
            }
            .onEnded { _ in dragStart = nil })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3D 滑块")
        .accessibilityValue(depth == 0 ? "关" : "\(Int((depth * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: depth = min(1, ((depth * 10).rounded() + 1) / 10)
            case .decrement: depth = max(0, ((depth * 10).rounded() - 1) / 10)
            @unknown default: break
            }
        }
    }
}

// ConsoleVolume, the volume this slider sets, is in Haptics.swift (round 21:
// next to the console's sounds, which follow it too).

#if os(iOS) && !targetEnvironment(simulator)
/// The iPhone's own volume slider (round 26). MPVolumeView is the one public
/// way an app lets its user set the system volume (AVAudioSession's
/// outputVolume is read only, MPMusicPlayerController.volume deprecated
/// since iOS 7). It is laid along the console's track, turned so that up is
/// louder; its thumb and track are left transparent, so what shows is the
/// console's own knob, drawn where the volume is (ConsoleVolume follows
/// it), and what a finger on the knob holds is the system's slider. A real
/// iPhone has it; the iOS 27.1 Simulator's MPVolumeView holds no slider
/// (10-31 probe). Round 29: where it is not there, the knob is FoldArc's own
/// volume (ConsoleVolume), so a finger always moves it.
enum SystemVolumeSlider {
    /// The system's slider is there to hold (asked once, before the volume
    /// decides what it follows). 11-06 (真机): an iPhone has it, but an MPVolumeView builds it only after it has
    /// been in a window a while (about 1.5 s on the iPhone Duo, iOS 27.2); the
    /// probe at launch, in no window, found none, so the knob was FoldArc's own
    /// volume and the iPhone's keys moved it and the system's volume both. On
    /// a device it is there (SystemVolumeHost logs when its slider comes).
    @MainActor static let present: Bool = {
        NSLog("[audio] the system's volume slider: a device has it (built once its view is in a window): the knob is the iPhone's volume")
        return true
    }()
    /// The knob is the iPhone's volume, held through the system's slider
    /// (not with the UI tests' `--foldarc-volume-own`).
    @MainActor static var available: Bool { present && ConsoleVolume.shared.followsSystem }
}

/// The system's slider in a view of its own: turned to run along this view's
/// height (up louder), as long as the view is tall, and only its thumb takes
/// a finger (anywhere else the touch goes on to what is under it).
final class SystemVolumeHost: UIView {
    let volumeView = MPVolumeView(frame: .zero)
    /// The thumb (the console's knob) along and across the track, in points.
    var thumb = CGSize(width: 19, height: 13) { didSet { if thumb != oldValue { dress() } } }
    /// Extra room round the thumb for a finger.
    var slop: CGFloat = 10
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        volumeView.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        addSubview(volumeView)
        dress()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    /// Thumb and track transparent: the console draws its own.
    private func dress() {
        let size = CGSize(width: max(1, thumb.width), height: max(1, thumb.height))
        let clearThumb = UIGraphicsImageRenderer(size: size).image { _ in }
        volumeView.setVolumeThumbImage(clearThumb, for: .normal)
        volumeView.setVolumeThumbImage(clearThumb, for: .highlighted)
        let clearTrack = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }.resizableImage(withCapInsets: .zero)
        volumeView.setMinimumVolumeSliderImage(clearTrack, for: .normal)
        volumeView.setMaximumVolumeSliderImage(clearTrack, for: .normal)
        setNeedsLayout()
    }
    /// Its slider has been seen (logged once: it comes a while after
    /// the view is in a window).
    private var sliderSeen = false
    override func layoutSubviews() {
        super.layoutSubviews()
        // Before its turn the slider lies along x: as long as this view is tall.
        volumeView.bounds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
        volumeView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !sliderSeen else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard let self, self.window != nil, !self.sliderSeen else { return }
            let track = self.volumeView.volumeSliderRect(forBounds: self.volumeView.bounds)
            self.sliderSeen = !track.isEmpty
            NSLog("[audio] 2.5 s in a window, the system's volume slider %@ (%@)", track.isEmpty ? "is still not there" : "is under the knob", NSCoder.string(for: track))
        }
    }
    /// Only on the thumb (and a finger's width round it): elsewhere the touch
    /// is not this view's (the console under it turns; a drag along the
    /// track away from the knob is the console's to answer).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let bounds = volumeView.bounds
        let track = volumeView.volumeSliderRect(forBounds: bounds)
        guard !track.isEmpty else { return nil }
        let value = Float(ConsoleVolume.shared.level)
        let thumbRect = volumeView.volumeThumbRect(forBounds: bounds, volumeSliderRect: track, value: value).insetBy(dx: -slop, dy: -slop)
        guard thumbRect.contains(convert(point, to: volumeView)) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// SystemVolumeHost for SwiftUI.
struct SystemVolumeTrack: UIViewRepresentable {
    var thumb: CGSize
    var slop: CGFloat = 10
    func makeUIView(context: Context) -> SystemVolumeHost {
        let host = SystemVolumeHost(frame: .zero)
        host.thumb = thumb
        host.slop = slop
        return host
    }
    func updateUIView(_ host: SystemVolumeHost, context: Context) {
        host.thumb = thumb
        host.slop = slop
    }
}
#elseif os(iOS)
/// The Simulator: no system volume slider (its MPVolumeView has none, 10-31
/// probe), and MediaPlayer is not linked. Round 29: the knob there is
/// FoldArc's own volume, which a finger moves (round 26 only showed the
/// system volume on it, and the knob could not be moved).
enum SystemVolumeSlider {
    @MainActor static let present: Bool = {
        NSLog("[audio] the system's volume slider is not here (the Simulator has none): the knob is FoldArc's own volume")
        return false
    }()
    @MainActor static var available: Bool { false }
}
/// Never shown in the Simulator (`SystemVolumeSlider.available` is false).
struct SystemVolumeTrack: View {
    var thumb: CGSize
    var slop: CGFloat = 10
    var body: some View { Color.clear }
}
#endif

/// The volume slider (round 20), left of the upper screen as the 3D slider
/// is right of it (where a later handheld put its volume slider). Up is
/// louder, down to the bottom is silent. Round 26: on the iPhone it is the
/// iPhone's own volume — the knob shows the system volume and a finger on it
/// moves the system's slider (SystemVolumeTrack), so the slider and the
/// iPhone's volume keys are one and the same. Elsewhere (round 29: the
/// Simulator, which has no system slider; the Mac preview; the UI tests'
/// `--foldarc-volume-own`) it is FoldArc's own volume, and a finger moves it.
struct VolumeSlider: View {
    @ObservedObject private var volume = ConsoleVolume.shared
    /// The iPhone's volume keys (round 24): each press shows beside the
    /// slider, the knob glides to its new place, and at an end of the track
    /// it knocks against it.
    @ObservedObject private var audio = SystemAudio.shared
    var ink: Color
    var haptics = true
    /// Knob travel along the 65-point track (knob 19 high).
    static let travel = 46.0
    @ViewState private var dragStart: Double?
    @ViewState private var shownPress: VolumePress?
    @ViewState private var pressStamp = 0
    @ViewState private var bump = 0.0
    /// The system's own slider lies under the knob (a real iPhone).
    private var systemSlider: Bool {
        #if os(iOS)
        return SystemVolumeSlider.available
        #else
        return false
        #endif
    }
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        VStack(spacing: 10) {
            Image(systemName: volume.level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 13)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color(white: 0.02)).frame(width: 5, height: 65)
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(LinearGradient(colors: [Color(white: 0.46), Color(white: 0.26)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 13, height: 19)
                    .overlay(VStack(spacing: 2.5) { ForEach(0..<3) { _ in Capsule().fill(.black.opacity(0.35)).frame(width: 7, height: 1) } })
                    .raised(RoundedRectangle(cornerRadius: 2.5), light: 0.45, dark: 0.6, lift: 1.5)
                    .offset(y: -volume.level * Self.travel + bump)
                    // Moved by the keys it glides; under a finger it follows.
                    .animation(dragStart == nil ? .spring(duration: 0.26, bounce: 0.18) : nil, value: volume.level)
            }
            .frame(height: 65)
            // Round 26: the iPhone's own slider under the knob (transparent;
            // the knob above shows where the system volume is).
            .overlay {
                #if os(iOS)
                if systemSlider {
                    SystemVolumeTrack(thumb: CGSize(width: 19, height: 13), slop: 9)
                        .frame(width: 33, height: 65)
                }
                #endif
            }
            Text("VOL").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(ink)
        .overlay(alignment: .leading) {
            if let shownPress {
                Text(shownPress.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.74), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .fixedSize()
                    .offset(x: 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: audio.keyPresses) { _, _ in
            guard let press = audio.lastPress else { return }
            pressStamp += 1
            let stamp = pressStamp
            withAnimation(.easeOut(duration: 0.15)) { shownPress = press }
            if press.atLimit {
                withAnimation(.easeOut(duration: 0.06)) { bump = press.up ? -3 : 3 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(70))
                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) { bump = 0 }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                guard pressStamp == stamp else { return }
                withAnimation(.easeOut(duration: 0.25)) { shownPress = nil }
            }
        }
        .padding(.horizontal, 10).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Round 26: on a real iPhone the knob is the iPhone's volume,
                // and a finger on it holds the system's slider
                // (SystemVolumeTrack); one beside it does nothing. Round 29:
                // everywhere else (the Simulator has no such slider) the knob
                // is FoldArc's own volume, and the finger moves it.
                if volume.followsSystem { return }
                let start = dragStart ?? volume.level
                if dragStart == nil { dragStart = start }
                let next = (min(1, max(0, start - value.translation.height / Self.travel)) * 20).rounded() / 20
                guard next != volume.level else { return }
                // A notch every tenth, a stop at the bottom.
                if Int((next * 10).rounded(.down)) != Int((volume.level * 10).rounded(.down)) || next == 0 {
                    ConsoleHaptics.shared.play(next == 0 ? .sliderStop : .sliderNotch, enabled: haptics)
                }
                volume.level = next
                // Heard at the new volume (round 21; quiet under a game's
                // own sound, which is what then shows the volume).
                ConsoleSounds.shared.play(.tick)
            }
            .onEnded { _ in dragStart = nil })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shownName("音量滑块"))
        .accessibilityValue(volume.level == 0 ? "静音" : "\(Int((volume.level * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            // The system volume cannot be set from here (round 26): VoiceOver
            // reads it; the iPhone's keys change it.
            guard !volume.followsSystem else { return }
            switch direction {
            case .increment: volume.level = min(1, ((volume.level * 10).rounded() + 1) / 10)
            case .decrement: volume.level = max(0, ((volume.level * 10).rounded() - 1) / 10)
            @unknown default: break
            }
            ConsoleSounds.shared.play(.tick)
        }
    }
}

/// The microphone hole (round 16). No switch under it on the real console
/// either; holding it is blowing into the microphone: games that listen for a
/// breath get one (FALibretroCore.micBlowing), the demo's ship is blown up.
struct MicHole: View {
    var ink: Color
    var haptics = true
    var blowing = false
    var blow: (Bool) -> Void
    @GestureState private var held = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.black.opacity(blowing ? 0.9 : 0.6)).frame(width: 4, height: 4)
                .overlay(Circle().stroke(Palette.mint.opacity(blowing ? 0.7 : 0), lineWidth: 1.5).scaleEffect(blowing ? 3 : 1))
                .animation(.easeOut(duration: 0.25), value: blowing)
            Text("MIC").font(.system(size: 7))
        }
        .foregroundStyle(ink)
        .frame(width: 64, height: 30).contentShape(Rectangle())
        // 11-07: where MicPointer's arrow points (MicHoleAnchorKey).
        .transformAnchorPreference(key: MicHoleAnchorKey.self, value: .bounds) { $0.holes.append($1) }
        .gesture(DragGesture(minimumDistance: 0).updating($held) { _, state, _ in state = true })
        .onChange(of: held) { _, down in
            blow(down)
            if down { ConsoleHaptics.shared.play(.micTouch, enabled: haptics) }
        }
        .onDisappear { blow(false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MIC 麦克风，按住即吹气").accessibilityAddTraits(.isButton)
        .accessibilityAction { blow(true); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { blow(false) } }
    }
}

/// 桌面模式's hinge as a control.
struct HingeControl {
    /// Lid angle away from open, degrees.
    var tilt: Binding<Double>
    /// Fold past the stop: the lid shuts and the console sleeps. Nil where a
    /// real hinge decides (iPhone Duo): the drawn lid then stops at its detent.
    var shut: (() -> Void)?
    var haptics = true
}

/// Drag on the hinge (or just above / below it) to fold the lid; a tap clicks
/// it between open flat and the slight fold; past `shutAngle` it closes.
struct HingeHandle: View {
    var control: HingeControl
    static let detents: [Double] = [0, 24]
    static let shutAngle = 62.0
    /// Touch area: the barrel and a margin above and below it.
    static let height = 92.0
    /// Degrees per design point dragged (the upper shell is 440 high).
    static let degreesPerPoint = 110.0 / 440
    @ViewState private var dragStart: Double?
    @ViewState private var moved = false
    var body: some View {
        Color.clear.frame(width: 742, height: Self.height).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStart ?? control.tilt.wrappedValue
                    if dragStart == nil { dragStart = start }
                    if abs(value.translation.height) > 6 { moved = true }
                    guard moved else { return }
                    let limit = control.shut == nil ? Self.detents.last ?? 24 : 88
                    let next = min(limit, max(0, start + value.translation.height * Self.degreesPerPoint))
                    let old = control.tilt.wrappedValue
                    for mark in Self.detents + (control.shut == nil ? [] : [Self.shutAngle]) where (old - mark) * (next - mark) < 0 {
                        ConsoleHaptics.shared.play(.hingeDetent, enabled: control.haptics)
                    }
                    control.tilt.wrappedValue = next
                }
                .onEnded { _ in
                    defer { dragStart = nil; moved = false }
                    let current = control.tilt.wrappedValue
                    if !moved { click(); return }
                    if current >= Self.shutAngle, let shut = control.shut {
                        ConsoleHaptics.shared.play(.lidShut, enabled: control.haptics)
                        withAnimation(.easeIn(duration: 0.16)) { control.tilt.wrappedValue = 90 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { shut() }
                        return
                    }
                    let target = Self.detents.min(by: { abs($0 - current) < abs($1 - current) }) ?? 0
                    if abs(target - current) > 2 { ConsoleHaptics.shared.play(.hingeDetent, enabled: control.haptics) }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { control.tilt.wrappedValue = target }
                })
            .accessibilityElement()
            .accessibilityLabel("铰链")
            .accessibilityValue(control.tilt.wrappedValue < 1 ? "完全打开" : "微微合上")
            .accessibilityHint("向下拖动合上上盖，轻点在打开和微合之间切换")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { click() }
            .accessibilityAction(named: "合上") {
                guard let shut = control.shut else { return }
                ConsoleHaptics.shared.play(.lidShut, enabled: control.haptics)
                shut()
            }
    }
    private func click() {
        let target = control.tilt.wrappedValue < 12 ? 24.0 : 0
        ConsoleHaptics.shared.play(.hingeDetent, enabled: control.haptics)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { control.tilt.wrappedValue = target }
    }
}

/// The iPhone's charger and battery (round 16; round 26 split the two):
/// `pluggedIn` while it is on its charger (charging or full) — the console
/// has its charger's cable in then (ConsoleStage.setCharger) — and the charge
/// light (`charging`) on while it charges, out once it is full, as the
/// handheld's goes out when charging is complete (before round 26 it stayed
/// on while full). The Simulator reports no state (batteryState unknown,
/// level -1, 10-31): DEBUG `--foldarc-battery=charging|full|unplugged` sets
/// one, `--foldarc-battery-script=<state>@<seconds>,…` changes it on a
/// schedule (the cable's moves recorded without a charger).
@MainActor final class BatteryLight: ObservableObject {
    static let shared = BatteryLight()
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    /// 0…1, nil while unknown (the Simulator reports -1). The system menu's
    /// status strip draws it (round 17).
    @Published private(set) var level: Double?
    /// Bumped when a charger is plugged in or out after the start (one
    /// plugged in while FoldArc was away too, when it comes back): the
    /// library shows it.
    @Published private(set) var plugChanges = 0
    /// When the last of those changes came: the library, coming up a moment
    /// after one it did not see (FoldArc opening, a program closing), plays
    /// it then (`takeRecentPlugChange`).
    private var lastPlugChange: Date?
    /// A plug change in the last `seconds` not yet shown; taking it clears it.
    func takeRecentPlugChange(within seconds: TimeInterval) -> Bool {
        defer { lastPlugChange = nil }
        guard let at = lastPlugChange else { return false }
        return Date().timeIntervalSince(at) < seconds
    }
    #if os(iOS)
    private var observers: [NSObjectProtocol] = []
    #if DEBUG
    private var override: UIDevice.BatteryState?
    #endif
    private var started = false
    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let given = arguments.first(where: { $0.hasPrefix("--foldarc-battery=") }) {
            override = Self.state(String(given.dropFirst("--foldarc-battery=".count)))
        }
        #endif
        read()
        started = true
        // Coming back to the foreground too: a charger plugged in or out
        // while FoldArc was away is seen then.
        for name in [UIDevice.batteryStateDidChangeNotification, UIDevice.batteryLevelDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in BatteryLight.shared.read() }
            })
        }
        #if DEBUG
        if let script = arguments.first(where: { $0.hasPrefix("--foldarc-battery-script=") }) {
            for step in script.dropFirst("--foldarc-battery-script=".count).split(separator: ",") {
                let parts = step.split(separator: "@")
                guard parts.count == 2, let state = Self.state(String(parts[0])), let seconds = Double(parts[1]) else { continue }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                    NSLog("[power] debug: battery %@", String(parts[0]))
                    BatteryLight.shared.override = state
                    BatteryLight.shared.read()
                }
            }
        }
        #endif
    }
    #if DEBUG
    private static func state(_ name: String) -> UIDevice.BatteryState? {
        switch name {
        case "charging": return .charging
        case "full": return .full
        case "unplugged": return .unplugged
        default: return nil
        }
    }
    #endif
    private func read() {
        var state = UIDevice.current.batteryState
        var value = Double(UIDevice.current.batteryLevel)
        #if DEBUG
        if let override {
            state = override
            if value < 0 { value = state == .full ? 1 : 0.62 }
        }
        #endif
        let plugged = state == .charging || state == .full
        let changed = started && plugged != pluggedIn
        if charging != (state == .charging) { charging = state == .charging }
        if pluggedIn != plugged { pluggedIn = plugged }
        let shown = value >= 0 ? min(1, value) : nil
        if level != shown { level = shown }
        if changed { lastPlugChange = Date(); plugChanges += 1 }
        NSLog("[power] battery state %d level %.2f%@", state.rawValue, value, changed ? (plugged ? ", plugged in" : ", unplugged") : "")
    }
    #else
    private init() {}
    #endif
}
struct HardwareKey: View {
    var key: PadButton
    var color = Color.white.opacity(0.7)
    var capColor: Color?
    var haptics = true
    var press: (PadButton, Bool) -> Void
    @GestureState private var held = false
    /// 手柄样式 圆润: the casing's own plastic instead of a dark key.
    @Environment(\.controlLook) private var look
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        GeometryReader { proxy in
            Group {
                if case .soft(let finish) = look {
                    ZStack {
                        SoftKeyFace(shape: Circle(), finish: finish, held: held)
                        SoftLetters(text: key.rawValue.uppercased(), finish: finish, size: proxy.size.width * 0.38)
                            .offset(y: held ? 1.1 : -0.4)
                    }
                } else {
                    hardwareFace(proxy)
                }
            }
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).updating($held) { _, state, _ in state = true })
                .onChange(of: held) { _, value in
                    press(key, value)
                    ConsoleHaptics.shared.play(.faceButton, value ? .press : .release, enabled: haptics)
                }
        }
        .accessibilityLabel("\(key.rawValue.uppercased()) 按键").accessibilityAddTraits(.isButton)
        .accessibilityAction { press(key, true); press(key, false) }
        .onDisappear { press(key, false) }
    }
    private func hardwareFace(_ proxy: GeometryProxy) -> some View {
            Circle().fill(RadialGradient(colors: [Color(white: 0.02), Color(white: 0.09)], center: .center, startRadius: 0, endRadius: proxy.size.width * 0.5))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.85), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                .overlay {
                    DomeCap(color: capColor ?? Color(white: held ? 0.16 : 0.24), pressed: held)
                        .padding(2.5).offset(y: held ? 0.5 : -1.5)
                        .shadow(color: .black.opacity(0.7), radius: held ? 0.5 : 2.5, x: 0, y: held ? 0.5 : 3)
                }
                .overlay(Text(key.rawValue.uppercased()).font(.system(size: proxy.size.width * 0.40, weight: .semibold, design: .rounded)).foregroundStyle(color)
                    .shadow(color: .black.opacity(0.6), radius: 0.5, y: 0.5).offset(y: held ? 0.5 : -1.5))
    }
}

struct AnalogPad: View {
    var isCStick = false
    var haptics = true
    /// The Orbit Garden demo gives the sticks a meaning; a real game does not.
    var demo = true
    var changed: (Point) -> Void
    @GestureState private var translation = CGSize.zero
    @GestureState private var active = false
    /// For the feel: the pad reached its rim / was pushed off centre.
    @ViewState private var atRim = false
    @ViewState private var displaced = false
    /// 手柄样式 圆润: the casing's own plastic.
    @Environment(\.controlLook) private var look
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        GeometryReader { proxy in
            let diameter = proxy.size.width
            let limit = diameter * (isCStick ? 0.12 : 0.19)
            let magnitude = hypot(translation.width, translation.height)
            let ratio = magnitude > limit ? limit / magnitude : 1
            Group {
                if case .soft(let finish) = look {
                    SoftStickFace(finish: finish, held: active, offset: CGSize(width: translation.width * ratio, height: translation.height * ratio), isCStick: isCStick)
                } else {
                    hardwareFace(diameter: diameter, ratio: ratio)
                }
            }.contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($translation) { value, state, _ in state = value.translation }
                    .updating($active) { _, state, _ in state = true }
                    .onChanged { value in
                        let length = hypot(value.translation.width, value.translation.height)
                        let divisor = max(limit, length)
                        changed(length < 2 ? Point(x: 0, y: 0) : Point(x: value.translation.width / divisor, y: value.translation.height / divisor))
                        if length > limit * 0.25 { displaced = true }
                        let rim = length >= limit * 0.97
                        if rim != atRim {
                            atRim = rim
                            if rim { ConsoleHaptics.shared.play(.stickRim, enabled: haptics) }
                        }
                    })
                .onChange(of: active) { _, value in
                    if value {
                        ConsoleHaptics.shared.play(.stickTouch, enabled: haptics)
                    } else {
                        changed(Point(x: 0, y: 0))
                        if displaced { ConsoleHaptics.shared.play(.stickReturn, enabled: haptics) }
                        atRim = false; displaced = false
                    }
                }
        }.accessibilityLabel(isCStick ? (demo ? "小摇杆，拖动移动信标" : "小摇杆") : (demo ? "摇杆，拖动移动飞船" : "摇杆"))
            .onDisappear { changed(Point(x: 0, y: 0)) }
    }
    private func hardwareFace(diameter: Double, ratio: Double) -> some View {
        ZStack {
            Dish()
            // Cap: matte grey with a shallow concave top; light from top-left.
            ZStack {
                Circle().fill(RadialGradient(stops: [
                    .init(color: isCStick ? Color(white: 0.52) : Color(white: 0.84), location: 0),
                    .init(color: isCStick ? Color(white: 0.40) : Color(white: 0.70), location: 0.62),
                    .init(color: isCStick ? Color(white: 0.20) : Color(white: 0.40), location: 1)
                ], center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: diameter * 0.45))
                // Concave centre: darker rim ring, slightly lighter floor.
                Circle().fill(RadialGradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.18)], center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: diameter * 0.30))
                    .padding(diameter * 0.12)
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .clear, .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                Circle().inset(by: diameter * 0.12).strokeBorder(LinearGradient(colors: [.black.opacity(0.22), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1)
            }
            .padding(diameter * 0.13)
            .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 4)
            .offset(x: translation.width * ratio, y: translation.height * ratio)
        }
    }
}
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(Double, Double)] = [(0.34,0),(0.66,0),(0.66,0.34),(1,0.34),(1,0.66),(0.66,0.66),(0.66,1),(0.34,1),(0.34,0.66),(0,0.66),(0,0.34),(0.34,0.34)]
        var p = Path()
        for (i, point) in points.enumerated() {
            let pt = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath(); return p
    }
}
struct DirectionPad: View {
    var changed: (Set<PadButton>) -> Void
    var haptics = true
    @GestureState private var active = false
    /// The directions held at the last change: rolling onto another one
    /// clicks again, like the rocker going down on a new dome.
    @ViewState private var lastKeys: Set<PadButton> = []
    /// 手柄样式 圆润: the casing's own plastic.
    @Environment(\.controlLook) private var look
    // 11-07: MicPointer keeps its arrow and words off it.
    var body: some View { obstacleBody.micPointerObstacle() }
    @ViewBuilder private var obstacleBody: some View {
        GeometryReader { proxy in
            Group {
                if case .soft(let finish) = look {
                    SoftCrossFace(finish: finish, held: active)
                } else {
                    hardwareFace(proxy)
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($active) { _, state, _ in state = true }.onChanged { value in
                    let dx = (value.location.x / proxy.size.width - 0.5) * 2
                    let dy = (value.location.y / proxy.size.height - 0.5) * 2
                    var keys: Set<PadButton> = []
                    if dx < -0.3 { keys.insert(.left) }; if dx > 0.3 { keys.insert(.right) }
                    if dy < -0.3 { keys.insert(.up) }; if dy > 0.3 { keys.insert(.down) }
                    if keys != lastKeys {
                        if !keys.isEmpty && !keys.isSubset(of: lastKeys) {
                            ConsoleHaptics.shared.play(.dpad, .press, enabled: haptics)
                        } else if keys.isEmpty {
                            ConsoleHaptics.shared.play(.dpad, .release, enabled: haptics)
                        }
                        lastKeys = keys
                    }
                    changed(keys)
                })
                .onChange(of: active) { _, value in
                    guard !value else { return }
                    if !lastKeys.isEmpty { ConsoleHaptics.shared.play(.dpad, .release, enabled: haptics) }
                    lastKeys = []
                    changed([])
                }
        }
            // One element for VoiceOver (it was four arrow images, each with
            // the cross's label and actions).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("十字方向键，支持斜向滑动")
            .accessibilityAction(named: "向上") { pulse(.up) }
            .accessibilityAction(named: "向下") { pulse(.down) }
            .accessibilityAction(named: "向左") { pulse(.left) }
            .accessibilityAction(named: "向右") { pulse(.right) }
            .onDisappear { changed([]) }
    }
    private func hardwareFace(_ proxy: GeometryProxy) -> some View {
        ZStack {
            // Well in the casing, then the cross with bevelled arms.
            CrossShape().fill(Color(white: 0.03)).padding(-3)
            CrossShape().stroke(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 1).padding(-3)
            CrossShape().fill(Color(white: 0.30)).offset(x: -0.8, y: -0.8)   // lit edge
            CrossShape().fill(Color(white: 0.05)).offset(x: 0.8, y: 1.2)     // shaded edge
            CrossShape().fill(LinearGradient(colors: [Color(white: active ? 0.17 : 0.25), Color(white: active ? 0.10 : 0.13), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(0.6)
                .shadow(color: .black.opacity(0.6), radius: active ? 1 : 3, x: 0, y: active ? 1 : 4)
            // Centre dimple.
            Circle().fill(RadialGradient(colors: [.black.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: proxy.size.width * 0.13)).frame(width: proxy.size.width * 0.26)
            Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.5), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 1).frame(width: proxy.size.width * 0.22)
            ForEach(0..<4) { index in
                Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(.white.opacity(0.14))
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 0.6)
                    .offset(y: -proxy.size.width * 0.36).rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }
    private func pulse(_ direction: PadButton) {
        changed([direction])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { changed([]) }
    }
}
