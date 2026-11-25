import SwiftUI

// 手柄样式: the
// touch controller's styles — on a phone without a hinge, on the iPhone
// Duo's cover, and across (TV模式, or a phone held sideways) — and the
// button that picks one. Layouts only take ideas from other emulators'
// skins (their arrangement); every shape here is FoldArc's own.

/// One of the controller's styles. The same three names everywhere; what
/// each looks like depends on where it is (ControllerSkin.Place).
enum ControllerSkin: String, CaseIterable, Identifiable, Sendable {
    /// The controller as it was: three columns under the screens.
    case classic
    /// 掌机 (upright): the hinge with its shoulder keys between the two
    /// screens, the keys where a handheld's lower half has them. 手柄
    /// (across): a gamepad round the touch screen. 大按键 (the cover): the
    /// cover's layout with keys a size larger.
    case handheld
    /// 圆润 (the pink skin, drawn FoldArc's own way): keys of the
    /// casing's own plastic, the shoulder keys hanging under the touch
    /// screen, a row of small round keys at the foot.
    case soft
    var id: String { rawValue }

    enum Place: String, Sendable {
        case upright, cover, across
        var key: String { "foldarc.controller.\(rawValue)" }
        var title: String {
            switch self {
            case .upright: return String(localized: "竖着拿")
            case .cover: return String(localized: "外屏")
            case .across: return String(localized: "横着拿")
            }
        }
    }
    func title(in place: Place) -> String {
        switch self {
        case .classic: return String(localized: "经典")
        case .handheld: return place == .across ? String(localized: "手柄") : (place == .cover ? String(localized: "大按键") : String(localized: "掌机"))
        case .soft: return String(localized: "圆润")
        }
    }
    /// What the style looks like in that place (经典 said 「按键分三列」 on the cover and across too, 圆润 on
    /// the cover said its L R hang under the touch screen — only upright do they).
    func blurb(in place: Place) -> String {
        switch (self, place) {
        case (.classic, .upright): return String(localized: "两块屏在上，下面按键分三列：左边摇杆和十字键，中间 START、SELECT、HOME，右边小摇杆和 A B X Y")
        case (.handheld, .upright): return String(localized: "肩键在两块屏中间的铰链上，按键像掌机下半那样摆")
        case (.soft, .upright): return String(localized: "机身同色的圆润按键，L R 挂在触摸屏下沿，底下一排小圆键")
        case (.classic, .cover): return String(localized: "两块屏在上；L ZL、SELECT 在触摸屏左边，R ZR、小摇杆、START 在右边；摇杆、十字键、HOME、A B X Y 在最下面一排")
        case (.handheld, .cover): return String(localized: "和经典一样的摆法，A B X Y 大一号")
        case (.soft, .cover): return String(localized: "和经典一样的摆法，按键是机身同色的圆润塑料")
        case (.classic, .across): return String(localized: "两块屏在中间，左边 L ZL、摇杆、十字键，右边 ZR R、A B X Y、START SELECT HOME，左右对齐；Duo 半折时一页一块屏")
        case (.handheld, .across): return String(localized: "两块屏在中间，SELECT HOME START 在触摸屏下面，两边是摇杆、十字键和 A B X Y；接着电视时只留触摸屏；Duo 半折时一页一块屏")
        case (.soft, .across): return String(localized: "手柄的摆法，按键是机身同色的圆润塑料；Duo 半折时一页一块屏")
        }
    }
    static func stored(_ place: Place) -> ControllerSkin {
        UserDefaults.standard.string(forKey: place.key).flatMap(ControllerSkin.init(rawValue:)) ?? .classic
    }
}

/// 11-07: how the iPhone Duo looks held
/// upright in 掌机模式 — the console as it is (掌机机身, the default), or
/// one of the controller's styles, chosen in 主题 › 手柄样式 (which then
/// is 竖着拿's style for 手柄模式 too). A key of its own: a style chosen
/// for 竖着拿 before 11-07 (the controller's) does not change the console.
enum DuoUprightLook {
    static let key = "foldarc.duo.upright"
    static let console = "console"
    static let title = String(localized: "掌机机身")
    static let blurb = String(localized: "现在这个：像真掌机一样，上屏在折痕上面，铰链和肩键在折痕上，触摸屏和按键在下面（默认）")
    /// The controller style it is, nil: the console.
    static var style: ControllerSkin? {
        UserDefaults.standard.string(forKey: key).flatMap(ControllerSkin.init(rawValue:))
    }
}

// MARK: - The keys' look

/// How the controller's keys are drawn: the handheld's dark keys, or (圆润)
/// keys of the casing's own plastic in its colours.
enum ControlLook: Equatable {
    case hardware
    case soft(ShellFinish)
}
private struct ControlLookKey: EnvironmentKey {
    static let defaultValue = ControlLook.hardware
}
extension EnvironmentValues {
    var controlLook: ControlLook {
        get { self[ControlLookKey.self] }
        set { self[ControlLookKey.self] = newValue }
    }
}

/// A key of the casing's own plastic: `shape` in the shell's colours, lit
/// from above, standing in a slightly darker well; pressed, it goes down
/// into it and its light goes.
struct SoftKeyFace<S: Shape>: View {
    var shape: S
    var finish: ShellFinish
    var held: Bool
    var body: some View {
        let light = finish.isLight
        ZStack {
            // The well round it.
            shape.fill(light ? finish.dark.opacity(0.38) : Color.black.opacity(0.42)).offset(y: 1.6)
            ZStack {
                shape.fill(LinearGradient(colors: held ? [finish.base, finish.shade] : [finish.light, finish.base], startPoint: .top, endPoint: .bottom))
                // A soft sheen along its upper edge.
                shape.stroke(LinearGradient(colors: [.white.opacity(light ? (held ? 0.2 : 0.65) : (held ? 0.06 : 0.24)), .clear], startPoint: .top, endPoint: .center), lineWidth: 1.6)
                    .padding(1.2)
                shape.stroke(light ? finish.dark.opacity(0.5) : Color.black.opacity(0.5), lineWidth: 0.9)
            }
            .offset(y: held ? 1.1 : -0.4)
            .shadow(color: .black.opacity(held ? 0.06 : 0.18), radius: held ? 0.4 : 1.6, y: held ? 0.3 : 1.4)
        }
    }
}

/// Letters on the plastic (the skin: white on the pink keys), the
/// cut's upper edge in shadow.
struct SoftLetters: View {
    var text: String
    var finish: ShellFinish
    var size: Double
    var body: some View {
        ZStack {
            Text(text).foregroundStyle(finish.isLight ? finish.dark.opacity(0.75) : Color.black.opacity(0.55)).offset(y: -0.8)
            Text(text).foregroundStyle(finish.isLight ? Color.white : Color.white.opacity(0.7))
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }
}

/// The cross with rounded ends (the soft D-pad).
struct RoundedCross: Shape {
    /// An arm's width, as a part of the whole.
    var arm = 0.36
    func path(in rect: CGRect) -> Path {
        let w = rect.width * arm, h = rect.height * arm
        let r = min(w, h) * 0.24
        let across = Path(roundedRect: CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h), cornerRadius: r, style: .continuous)
        let down = Path(roundedRect: CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height), cornerRadius: r, style: .continuous)
        return across.union(down)
    }
}

/// The soft D-pad's face: the cross, a line along each arm, as moulded.
struct SoftCrossFace: View {
    var finish: ShellFinish
    var held: Bool
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                SoftKeyFace(shape: RoundedCross(), finish: finish, held: held)
                ForEach(0..<4) { index in
                    Capsule().fill(finish.isLight ? Color.white.opacity(0.95) : Color.white.opacity(0.32))
                        .frame(width: max(1.5, size * 0.016), height: size * 0.13)
                        .offset(y: -size * 0.32 + (held ? 1.1 : -0.4))
                        .rotationEffect(.degrees(Double(index) * 90))
                }
            }
        }
    }
}

/// The soft Circle Pad / C Stick: a shallow dish in the casing, a round
/// cap of its plastic with a dimpled top.
struct SoftStickFace: View {
    var finish: ShellFinish
    var held: Bool
    var offset: CGSize
    var isCStick: Bool
    var body: some View {
        GeometryReader { proxy in
            let d = proxy.size.width
            ZStack {
                Circle().fill(finish.isLight ? finish.dark.opacity(0.3) : Color.black.opacity(0.4))
                Circle().strokeBorder(finish.isLight ? finish.dark.opacity(0.35) : Color.black.opacity(0.45), lineWidth: 1)
                ZStack {
                    SoftKeyFace(shape: Circle(), finish: finish, held: held)
                    Circle().strokeBorder(finish.isLight ? finish.dark.opacity(0.28) : Color.black.opacity(0.3), lineWidth: 1)
                        .padding(d * (isCStick ? 0.12 : 0.16))
                }
                .padding(d * 0.13)
                .offset(offset)
            }
        }
    }
}

// (11-07: the button that picked a style on the controller is gone;
// 主题 › 手柄样式 picks it — SkinsAppPage in SystemSettingsApp.swift.)
