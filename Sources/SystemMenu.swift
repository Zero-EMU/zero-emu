import SwiftUI

// The system menu drawn inside the console's screens (round 17). The HOME
// menu lives in the handheld's two LCDs the way a handheld's own system menu
// does: the upper screen shows the suspended software, the lower screen a
// grid of square tiles with a dark bar of two chunky buttons along the
// bottom, a status strip carries the clock and the battery, and the console's
// own keys work the menu (D-pad moves the cursor, A decides, B goes back,
// HOME resumes). The structure is the one every handheld owner knows; the
// drawing, the names and the marks are FoldArc's own.

enum SystemMenuStyle {
    /// 11-07: the colours come from 主题 (MenuPalette.current).
    static var palette: MenuPalette { MenuPalette.current }
    /// Plastic-coloured paper the menus are printed on.
    static var paper: Color { palette.paper }
    static var paperDeep: Color { palette.paperDeep }
    static var tile: Color { palette.tile }
    static var tileEdge: Color { palette.tileEdge }
    static var ink: Color { palette.ink }
    static var inkSoft: Color { palette.inkSoft }
    /// The cursor.
    static var accent: Color { palette.accent }
    static var bar: Color { palette.bar }
    static var status: Color { palette.status }
    static var go: Color { palette.go }
    static var stop: Color { palette.stop }
}

/// The colours the console's own menus are printed in. 11-07: 主题's palette (the library's) colours
/// the console's screens too — the HOME menu and the console's programs, on
/// the console in the library and in a game. Always dark ink on light paper
/// with white tiles, as the menus are drawn; a dark palette (靛蓝, 碳黑)
/// keeps its colour in the bars, the paper's tint and the accent.
/// `standard` is the blue-grey the menus had since round 17; the camera, the
/// album and 游戏笔记, which are not menus, keep it (FixedMenuStyle).
struct MenuPalette {
    var paper: Color
    var paperDeep: Color
    var tile: Color
    var tileEdge: Color
    var ink: Color
    /// The softer ink of notes and values, deep enough for small print:
    /// 5:1 or more on `paper` in every palette (WCAG's contrast ratio),
    /// about 4.5:1 halfway down the backdrop to `paperDeep`. It is also
    /// what a quiet button is filled with, under white words.
    var inkSoft: Color
    var accent: Color
    var bar: Color
    var status: Color
    var go: Color
    var stop: Color

    /// The one 主题 has chosen (UserDefaults; read where it is drawn).
    static var current: MenuPalette { LibraryTheme.chosen.menu }

    static let standard = MenuPalette(
        paper: Color(red: 0.85, green: 0.89, blue: 0.93), paperDeep: Color(red: 0.74, green: 0.81, blue: 0.88),
        tile: .white, tileEdge: Color(red: 0.60, green: 0.68, blue: 0.77),
        ink: Color(red: 0.13, green: 0.18, blue: 0.25), inkSoft: Color(red: 0.32, green: 0.37, blue: 0.44),
        accent: Color(red: 0.18, green: 0.49, blue: 0.90),
        bar: Color(red: 0.17, green: 0.22, blue: 0.29), status: Color(red: 0.10, green: 0.13, blue: 0.18),
        go: Color(red: 0.20, green: 0.60, blue: 0.40), stop: Color(red: 0.84, green: 0.38, blue: 0.22))
    /// 奶油红: cream paper, brown ink, the burgundy of the library's buttons.
    static let cream = MenuPalette(
        paper: Color(red: 0.94, green: 0.90, blue: 0.81), paperDeep: Color(red: 0.85, green: 0.79, blue: 0.66),
        tile: Color(red: 1.0, green: 0.99, blue: 0.96), tileEdge: Color(red: 0.74, green: 0.66, blue: 0.53),
        ink: Color(red: 0.24, green: 0.17, blue: 0.16), inkSoft: Color(red: 0.42, green: 0.36, blue: 0.32),
        accent: Color(red: 0.66, green: 0.19, blue: 0.18),
        bar: Color(red: 0.28, green: 0.20, blue: 0.19), status: Color(red: 0.17, green: 0.12, blue: 0.11),
        go: Color(red: 0.22, green: 0.50, blue: 0.36), stop: Color(red: 0.84, green: 0.38, blue: 0.22))
    /// 灰四色: grey paper, navy ink, red.
    static let grey = MenuPalette(
        paper: Color(red: 0.85, green: 0.86, blue: 0.89), paperDeep: Color(red: 0.71, green: 0.72, blue: 0.77),
        tile: .white, tileEdge: Color(red: 0.58, green: 0.59, blue: 0.66),
        ink: Color(red: 0.17, green: 0.18, blue: 0.24), inkSoft: Color(red: 0.31, green: 0.33, blue: 0.40),
        accent: Color(red: 0.83, green: 0.22, blue: 0.22),
        bar: Color(red: 0.19, green: 0.20, blue: 0.27), status: Color(red: 0.11, green: 0.12, blue: 0.17),
        go: Color(red: 0.18, green: 0.58, blue: 0.36), stop: Color(red: 0.86, green: 0.47, blue: 0.13))
    /// 豆绿: the green of a dot-matrix screen.
    static let pea = MenuPalette(
        paper: Color(red: 0.78, green: 0.84, blue: 0.60), paperDeep: Color(red: 0.62, green: 0.70, blue: 0.40),
        tile: Color(red: 0.96, green: 0.98, blue: 0.90), tileEdge: Color(red: 0.43, green: 0.51, blue: 0.27),
        ink: Color(red: 0.09, green: 0.21, blue: 0.09), inkSoft: Color(red: 0.22, green: 0.33, blue: 0.17),
        accent: Color(red: 0.16, green: 0.42, blue: 0.20),
        bar: Color(red: 0.09, green: 0.22, blue: 0.10), status: Color(red: 0.05, green: 0.13, blue: 0.06),
        go: Color(red: 0.13, green: 0.47, blue: 0.27), stop: Color(red: 0.80, green: 0.36, blue: 0.16))
    /// 靛蓝: the library's indigo in the bars, a lavender paper, amber.
    static let indigo = MenuPalette(
        paper: Color(red: 0.83, green: 0.84, blue: 0.95), paperDeep: Color(red: 0.68, green: 0.70, blue: 0.89),
        tile: .white, tileEdge: Color(red: 0.55, green: 0.57, blue: 0.80),
        ink: Color(red: 0.11, green: 0.12, blue: 0.30), inkSoft: Color(red: 0.29, green: 0.31, blue: 0.50),
        accent: Color(red: 0.80, green: 0.46, blue: 0.05),
        bar: Color(red: 0.17, green: 0.18, blue: 0.42), status: Color(red: 0.11, green: 0.12, blue: 0.30),
        go: Color(red: 0.18, green: 0.55, blue: 0.40), stop: Color(red: 0.80, green: 0.22, blue: 0.26))
    /// 碳黑: near-black bars, a neutral grey paper, violet.
    static let charcoal = MenuPalette(
        paper: Color(red: 0.87, green: 0.87, blue: 0.88), paperDeep: Color(red: 0.73, green: 0.73, blue: 0.76),
        tile: .white, tileEdge: Color(red: 0.58, green: 0.58, blue: 0.62),
        ink: Color(red: 0.10, green: 0.10, blue: 0.12), inkSoft: Color(red: 0.34, green: 0.34, blue: 0.37),
        accent: Color(red: 0.42, green: 0.30, blue: 0.86),
        bar: Color(red: 0.13, green: 0.13, blue: 0.15), status: Color(red: 0.06, green: 0.06, blue: 0.08),
        go: Color(red: 0.20, green: 0.60, blue: 0.40), stop: Color(red: 0.84, green: 0.38, blue: 0.22))
}

/// The round-17 colours, unchanged by 主题: the camera, the album and 游戏笔记
/// (11-07; they are not menus, as a handheld's camera keeps its own look
/// whatever its menu's theme).
enum FixedMenuStyle {
    static let paper = MenuPalette.standard.paper
    static let paperDeep = MenuPalette.standard.paperDeep
    static let tile = MenuPalette.standard.tile
    static let tileEdge = MenuPalette.standard.tileEdge
    static let ink = MenuPalette.standard.ink
    static let inkSoft = MenuPalette.standard.inkSoft
    static let accent = MenuPalette.standard.accent
    static let bar = MenuPalette.standard.bar
    static let status = MenuPalette.standard.status
    static let go = MenuPalette.standard.go
    static let stop = MenuPalette.standard.stop
}

/// Paper with a faint staggered pattern of small squares.
struct SystemMenuBackdrop: View {
    /// 11-07: nil is 主题's (MenuPalette.current); the camera and 游戏笔记
    /// pass `.standard`.
    var palette: MenuPalette? = nil
    var body: some View {
        let colours = palette ?? MenuPalette.current
        let dot = colours.ink.opacity(0.045)
        ZStack {
            LinearGradient(colors: [colours.paper, colours.paperDeep], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let pitch: CGFloat = 18
                var y: CGFloat = 5
                var row = 0
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? 5 : 5 + pitch / 2
                    while x < size.width {
                        context.fill(Path(roundedRect: CGRect(x: x, y: y, width: 7, height: 7), cornerRadius: 2),
                                     with: .color(dot))
                        x += pitch
                    }
                    y += pitch
                    row += 1
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Zero's mark, in one colour: half of the app icon's ring (until then
/// an arc with a dot riding on it). The upper half, its band as thick for its
/// width as the icon's ring (56 of 634 px in AppIcon's 1024 px picture), cut
/// square where the ring is cut. `size` wide, half as tall.
struct MenuArcMark: View {
    var size: Double
    var color: Color = .white
    /// The icon's ring: its band over its outer diameter.
    static let band = 56.0 / 634.0
    /// The half ring's middle line: the circle's centre on the cut, its
    /// outer radius, its band.
    static func path(centre: CGPoint, outer: Double, band: Double) -> Path {
        var arc = Path()
        arc.addArc(center: centre, radius: outer - band / 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return arc
    }
    var body: some View {
        Canvas { context, _ in
            let band = max(1, size * Self.band)
            let arc = Self.path(centre: CGPoint(x: size / 2, y: size / 2), outer: size / 2, band: band)
            context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: band, lineCap: .butt))
        }
        .frame(width: size, height: size * 0.5)
        .accessibilityHidden(true)
    }
}

/// The battery as the console draws it: an outline with the level filled in,
/// a bolt while charging. Nothing when the level is unknown (the Simulator).
struct MenuBatteryGlyph: View {
    var level: Double?
    var charging: Bool
    var s: Double
    /// The outline and the fill (white on the dark strip; the library draws
    /// it in its ink, round 18), and the bolt over the fill.
    var tint: Color = .white
    var bolt: Color = SystemMenuStyle.status
    var body: some View {
        if let level {
            HStack(spacing: 1.5 * s) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2 * s).strokeBorder(tint.opacity(0.85), lineWidth: max(1, 1 * s))
                        .frame(width: 18 * s, height: 9 * s)
                    RoundedRectangle(cornerRadius: 1 * s)
                        .fill(level <= 0.2 && !charging ? SystemMenuStyle.stop : tint.opacity(0.9))
                        .frame(width: max(1.5 * s, (18 * s - 4 * s) * level), height: 5 * s)
                        .padding(.leading, 2 * s)
                    if charging {
                        Image(systemName: "bolt.fill").font(.system(size: 6 * s, weight: .bold)).foregroundStyle(bolt)
                            .frame(width: 18 * s, height: 9 * s)
                    }
                }
                RoundedRectangle(cornerRadius: 0.5 * s).fill(tint.opacity(0.85)).frame(width: 1.5 * s, height: 4 * s)
            }
            .accessibilityElement().accessibilityLabel("电量 \(Int((level * 100).rounded()))%\(charging ? String(localized: "，正在充电") : "")")
        }
    }
}

/// The strip across the top of a screen: the mark and a title on the left,
/// the clock in the middle, the battery on the right.
struct MenuStatusStrip: View {
    var s: Double
    var title: String
    var trailing: String? = nil
    /// The level as a number next to the glyph (the library, round 18).
    var showsPercent = false
    @ObservedObject private var battery = BatteryLight.shared
    var body: some View {
        ZStack {
            HStack(spacing: 6 * s) {
                MenuArcMark(size: 11 * s)
                Text(title).font(.system(size: 8.5 * s, weight: .bold, design: .monospaced)).tracking(1.2 * s)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing).font(.system(size: 8 * s, weight: .semibold, design: .monospaced)).opacity(0.8)
                }
                if showsPercent, let level = battery.level {
                    Text("\(Int((level * 100).rounded()))%").font(.system(size: 8 * s, weight: .semibold, design: .monospaced)).opacity(0.9)
                        .accessibilityHidden(true)
                }
                MenuBatteryGlyph(level: battery.level, charging: battery.pluggedIn, s: s)
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 10 * s, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10 * s)
        .frame(height: 19 * s)
        .background(SystemMenuStyle.status)
    }
}

/// A button prompt as handheld menus print them: the key in a ring, then
/// what it does. Only for keys the menu really listens to.
struct MenuKeyHint: View {
    var key: String
    var text: String
    var s: Double
    var body: some View {
        HStack(spacing: 3 * s) {
            Text(key).font(.system(size: 7 * s, weight: .heavy, design: .rounded))
                .frame(minWidth: 12 * s, minHeight: 12 * s)
                .padding(.horizontal, key.count > 1 ? 3 * s : 0)
                .background(SystemMenuStyle.ink.opacity(0.85), in: Capsule())
                .foregroundStyle(.white)
            Text(text).font(.system(size: 8 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
        }
        .accessibilityHidden(true)
    }
}

/// The cursor: a ring the D-pad moves, breathing slowly.
struct MenuCursorRing<S: InsettableShape>: View {
    var shape: S
    var s: Double
    var color = SystemMenuStyle.accent
    var body: some View {
        shape.strokeBorder(color, lineWidth: max(2, 2.5 * s))
            .shadow(color: color.opacity(0.55), radius: 3 * s)
            .phaseAnimator([1.0, 0.55]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
            .allowsHitTesting(false)
    }
}

struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A square tile with its name under it.
struct MenuTile: View {
    var id: String
    var title: String
    var symbol: String
    var size: Double
    var s: Double
    var tint = SystemMenuStyle.ink
    var accessibilityText: String? = nil
    @ObservedObject var model: HomeMenuModel
    var action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11 * s, style: .continuous)
        Button { model.focus = id; action() } label: {
            VStack(spacing: 4 * s) {
                ZStack {
                    shape.fill(SystemMenuStyle.tile)
                        .shadow(color: SystemMenuStyle.ink.opacity(0.22), radius: 0, y: 1.5 * s)
                    shape.strokeBorder(SystemMenuStyle.tileEdge.opacity(0.55), lineWidth: 1)
                    Image(systemName: symbol).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(tint)
                }
                .frame(width: size, height: size)
                .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
                Text(title).font(.system(size: 9.5 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(SystemMenuStyle.ink).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: size)
            }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(accessibilityText ?? title)
    }
}

/// One of the two chunky buttons in the bottom bar.
struct MenuBarButton {
    var id: String
    var title: String
    var symbol: String
    var color: Color
    var action: () -> Void
}

/// The dark bar along the bottom of the lower screen.
struct MenuBar: View {
    var s: Double
    var left: MenuBarButton?
    var right: MenuBarButton?
    /// The cursor, where a menu has one (HOME); the library's bar has none.
    var focus: String? = nil
    var setFocus: ((String) -> Void)? = nil
    var disabledLeft = false
    /// The library's bar takes its theme's colour (round 18) and a third,
    /// smaller button in the middle (设置).
    var background: Color = SystemMenuStyle.bar
    var middle: MenuBarButton? = nil
    var body: some View {
        HStack(spacing: 8 * s) {
            if let left { button(left) }
            if let middle { button(middle, compact: true) }
            Spacer(minLength: 0)
            if let right { button(right) }
        }
        .padding(.horizontal, 8 * s).padding(.vertical, 4 * s)
        .frame(height: 30 * s)
        .background(background)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }
    private func button(_ item: MenuBarButton, compact: Bool = false) -> some View {
        Button { setFocus?(item.id); item.action() } label: {
            HStack(spacing: 5 * s) {
                Image(systemName: item.symbol).font(.system(size: 9 * s, weight: .bold))
                Text(item.title).font(.system(size: 10 * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 * s : 12 * s)
            .frame(minWidth: compact ? 0 : 86 * s, maxHeight: .infinity)
            .background(
                Capsule().fill(LinearGradient(colors: [item.color.opacity(1), item.color.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            )
            .overlay { if focus == item.id { MenuCursorRing(shape: Capsule(), s: s, color: .white) } }
        }
        .buttonStyle(MenuPressStyle())
        .disabled(disabledLeft && item.id == left?.id)
        .opacity(disabledLeft && item.id == left?.id ? 0.6 : 1)
        .accessibilityLabel(item.title)
    }
}

/// A row in a settings page: white, with the cursor ring when focused.
struct MenuRow<Content: View>: View {
    var id: String
    var s: Double
    var selected = false
    @ObservedObject var model: HomeMenuModel
    @ViewBuilder var content: () -> Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
        content()
            .padding(.horizontal, 10 * s).padding(.vertical, 7 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? SystemMenuStyle.accent.opacity(0.12) : SystemMenuStyle.tile))
            .overlay(shape.strokeBorder(selected ? SystemMenuStyle.accent.opacity(0.5) : SystemMenuStyle.tileEdge.opacity(0.4), lineWidth: 1))
            .overlay { if model.focus == id { MenuCursorRing(shape: shape, s: s) } }
    }
}

/// A page's title line under the status strip.
struct MenuPageTitle: View {
    var title: String
    var symbol: String
    var s: Double
    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: symbol).font(.system(size: 10 * s, weight: .bold))
            Text(title).font(.system(size: 11 * s, weight: .bold, design: .rounded))
            Spacer()
        }
        .foregroundStyle(SystemMenuStyle.ink)
        .padding(.horizontal, 12 * s).padding(.top, 8 * s).padding(.bottom, 4 * s)
    }
}

// MARK: - Model

/// What the HOME menu shows and where its cursor is. The pages' views tell
/// it which items can take the cursor (`layout`, rows of ids, in reading
/// order) and what each does; the console's keys drive it.
@MainActor final class HomeMenuModel: ObservableObject {
    enum Page: Equatable, CaseIterable {
        case root, modes, finish, feel, guide, developer
        var title: String {
            switch self {
            case .root: return "HOME"
            case .modes: return String(localized: "游玩模式")
            case .finish: return String(localized: "机身配色")
            case .feel: return String(localized: "画面与手感")
            case .guide: return String(localized: "操作指南")
            case .developer: return String(localized: "开发者")
            }
        }
        var symbol: String {
            switch self {
            case .root: return "house.fill"
            case .modes: return "rectangle.on.rectangle"
            case .finish: return "paintpalette"
            case .feel: return "slider.horizontal.3"
            case .guide: return "book"
            case .developer: return "wrench.and.screwdriver"
            }
        }
    }
    static let barLeft = "bar.left"
    static let barRight = "bar.right"
    /// L / R step through these.
    static let tabs: [Page] = [.root, .modes, .finish, .feel]

    @Published private(set) var isOpen = false
    @Published private(set) var page: Page = .root
    @Published var focus: String?
    /// The focusable items of the page on screen, as rows in reading order.
    /// The page's view sets it while drawing (plain storage: nothing to publish).
    var layout: [[String]] = []
    var handlers: [String: () -> Void] = [:]
    /// Left / right on a focused slider.
    var adjusters: [String: (Int) -> Void] = [:]
    /// B while a dialog is up (set by the dialog while it shows).
    var escape: (() -> Void)?
    /// Round 30: the pages are opened from the console's menu (its small
    /// icons along the top), which is their root: B and 返回 on a page go
    /// back to it, not to a root page of their own.
    var exitToMenu: (() -> Void)?

    func open(_ page: Page = .root) {
        clear()
        self.page = page
        isOpen = true
        focus = page == .root ? Self.barRight : nil
    }
    func close() {
        clear()
        isOpen = false
        page = .root
        focus = nil
    }
    func show(_ page: Page) {
        clear()
        self.page = page
        focus = nil
    }
    /// B, or the bar's 返回: back to the root page. False at the root.
    @discardableResult func back() -> Bool {
        if let escape { escape(); return true }
        guard page != .root else { return false }
        if let exitToMenu { exitToMenu(); return true }
        show(.root)
        return true
    }
    private func clear() { layout = []; handlers = [:]; adjusters = [:]; escape = nil }

    /// A key from the console or a controller while the menu is open. True
    /// when the menu took it (always, while open: the game must not see it).
    @discardableResult func handle(_ key: PadButton, down: Bool) -> Bool {
        guard isOpen else { return false }
        guard down else { return true }
        switch key {
        case .up: move(rows: -1)
        case .down: move(rows: 1)
        case .left: step(-1)
        case .right: step(1)
        case .a:
            if let focus, let action = handlers[focus] { action() }
            else if focus == nil { focus = layout.first?.first }
        case .b: back()
        case .l: turnPage(-1)
        case .r: turnPage(1)
        default: break
        }
        return true
    }
    private func turnPage(_ delta: Int) {
        // From the console's menu (round 30) the pages have no root of
        // their own to turn to.
        let tabs = exitToMenu == nil ? Self.tabs : Self.tabs.filter { $0 != .root }
        guard escape == nil, let index = tabs.firstIndex(of: page) else { return }
        let next = (index + delta + tabs.count) % tabs.count
        show(tabs[next])
    }
    private func position(of id: String) -> (row: Int, column: Int)? {
        for (row, ids) in layout.enumerated() {
            if let column = ids.firstIndex(of: id) { return (row, column) }
        }
        return nil
    }
    private func move(rows delta: Int) {
        guard !layout.isEmpty else { return }
        guard let focus, let at = position(of: focus) else { self.focus = layout.first?.first; return }
        let row = min(layout.count - 1, max(0, at.row + delta))
        let ids = layout[row]
        self.focus = ids[min(at.column, ids.count - 1)]
    }
    private func step(_ delta: Int) {
        if let focus, let adjust = adjusters[focus] { adjust(delta); return }
        guard !layout.isEmpty else { return }
        guard let focus, let at = position(of: focus) else { self.focus = layout.first?.first; return }
        let ids = layout[at.row]
        self.focus = ids[min(ids.count - 1, max(0, at.column + delta))]
    }
}

// MARK: - Screens take over the LCDs

/// What the console draws in its two LCDs instead of the game while a menu
/// is up. PlayView puts it in the environment; the consoles read it where
/// they draw the screens.
struct ScreenOverlay {
    var top: AnyView
    var bottom: AnyView
}

private struct ScreenOverlayKey: EnvironmentKey {
    static let defaultValue: ScreenOverlay? = nil
}

extension EnvironmentValues {
    var screenOverlay: ScreenOverlay? {
        get { self[ScreenOverlayKey.self] }
        set { self[ScreenOverlayKey.self] = newValue }
    }
}

/// How wide the lower LCD is on screen, in points, reported by whichever
/// console is drawn. Under `HomeMenuModel.minimumScreenWidth` the HOME menu
/// is drawn over the whole display instead (a phone in 掌机模式 or 桌面模式:
/// the LCDs are too small to read a menu in).
struct LowerScreenWidthKey: PreferenceKey {
    static let defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = max(value, nextValue()) }
}

extension HomeMenuModel {
    static let minimumScreenWidth = 230.0
}
