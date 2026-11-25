import SwiftUI

// The play modes (round 16). The HOME menu itself is drawn in the console's
// screens since round 17 (SystemMenu.swift, HomeMenuScreens.swift).

/// The ways to play; round 31: four, TV模式 among them, chosen
/// in the menu's 游玩模式. Raw values are stored in UserDefaults
/// (`foldarc.mode`).
enum ScreenLayout: String, CaseIterable, Identifiable {
    /// The iPhone is the handheld: on iPhone Duo the two halves of the drawn
    /// console sit on the two halves of the display, the fold is the hinge.
    case handheld
    /// The whole console lies on the screen; its hinge works: fold the lid,
    /// shut it to sleep.
    case tabletop
    /// The screens with every control enlarged around them (was "大按键",
    /// which lacked START, SELECT and both sticks).
    case controller
    /// Round 31: the TV shows the two screens
    /// (AirPlay or a cable), the iPhone in the hands is the controller —
    /// keys and the touch screen (TVOutput).
    case tv
    /// 11-07: 沉浸模式 — with a controller
    /// connected, the display shows the game's two screens and nothing else
    /// (no casing, no keys); without one it waits in 手柄模式 (PlayView).
    case immersive
    var id: Self { self }
    static let defaultsKey = "foldarc.mode"

    var title: String {
        switch self {
        case .handheld: return String(localized: "掌机模式")
        case .tabletop: return String(localized: "桌面模式")
        case .controller: return String(localized: "手柄模式")
        case .tv: return String(localized: "TV模式")
        case .immersive: return String(localized: "沉浸模式")
        }
    }
    var summary: String {
        switch self {
        case .handheld: return String(localized: "iPhone 就是掌机：上下两半对着两块屏，折痕当铰链。")
        case .tabletop: return String(localized: "整台掌机摆在屏幕上。拖动铰链开合上盖，合上就休眠。")
        case .controller: return String(localized: "画面在上，所有按键放大排在下面，小屏 iPhone 也好按。")
        case .tv: return String(localized: "电视上放游戏画面（装在你选的电视里），iPhone 拿在手里当手柄：按键和下屏都在 iPhone 上。")
        case .immersive: return String(localized: "接上外置手柄，整块屏幕只放游戏的两块屏，没有机身和按键；用手柄玩，手柄的 HOME 打开主菜单。")
        }
    }
    var symbol: String {
        switch self {
        case .handheld: return "iphone"
        case .tabletop: return "laptopcomputer"
        case .controller: return "gamecontroller"
        case .tv: return "tv"
        case .immersive: return "arrow.up.left.and.arrow.down.right"
        }
    }
    /// TV模式 is Zero EMU Pro's; the others are everyone's.
    var isOpen: Bool { self != .tv || ProAccess.isPro }
    /// The mode the user last chose; 掌机模式 the first time. TV模式 kept
    /// from a time with Pro is not used without it (it stays kept, and is
    /// the mode again once Pro is back).
    static var stored: ScreenLayout {
        let kept = UserDefaults.standard.string(forKey: defaultsKey).flatMap(ScreenLayout.init(rawValue:)) ?? .handheld
        return kept.isOpen ? kept : .handheld
    }
}
