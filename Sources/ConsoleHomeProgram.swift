import SwiftUI
import Combine

// The console's menu as a program on the handheld (round 26). In the library
// a pinch brings the console closer, the shelf of cards shrinks away as it
// comes, and at the closest the console is gone into: the handheld fills the
// screen with its own menu on its two LCDs — the menu the console on the
// stage shows (ConsoleHomeTopArt, ConsoleHomeBottomArt in ConsoleStage3D.swift)
// — worked there with the touch screen and the console's keys: the D-pad
// moves the cursor, A or a second tap opens, B lets go of the cursor. The
// card in the slot starts from it (开启 / 继续上次 / 重新开始); HOME or POWER
// goes back to the library, as from the console's other programs.
//
// Round 30: it is the one menu
// everywhere, as a handheld has one. 相机, 设置, 游戏记录, 主题 and 说明书 open
// in place on the handheld (PlayView), not back in the library. HOME in a
// game brings the same menu up over the suspended software: the card's tile
// is the software (继续游戏 / 关闭软件), a row of small icons along the top
// holds what only means something with software running, and the programs
// can be used while it waits. Round 31: 设置 and 导入 in place too (they
// closed the software first); 游玩模式 is the eighth tile, and the small
// icons are only 保存进度, 读取进度 and 屏幕亮度, each named.

/// What the menu asks the library to open.
enum ConsoleHomeRequest: Equatable {
    case item(ConsoleHomeItem, ConsoleHomeAction)
    /// The first-time setup (the console is not set up yet).
    case setup
    /// One of the small icons along the top (round 30, software suspended).
    case shortcut(ConsoleHomeShortcut)
}

/// A question the menu asks before it does something it cannot undo
/// (round 30: closing the suspended software).
struct ConsoleHomeDialog {
    var title: String
    var message: String
    var confirm: String
    /// Round 31: nil for a notice (what an import said): one button, and B
    /// or a touch beside it reads it too.
    var cancel: String? = String(localized: "取消")
    var action: () -> Void
}

/// The cursor on the console's menu, kept between the console on the stage
/// and the program: going into the console, it is where it was.
@MainActor enum ConsoleHomeCursor {
    static var selection: ConsoleHomeItem?
}

@MainActor final class ConsoleHomeProgram: ObservableObject {
    @Published private(set) var selection: ConsoleHomeItem?
    /// One of the small icons along the top chosen instead (round 30).
    @Published private(set) var shortcut: ConsoleHomeShortcut?
    /// What it opens (LibraryView: software, a program, a page of the library).
    var open: (ConsoleHomeRequest) -> Void = { _ in }
    /// Back to the library (HOME and POWER do it on the console; a phone,
    /// whose display the menu covers, has a button for it); with software
    /// suspended, back to the software.
    var leave: () -> Void = {}
    /// The library's software (for the card in the slot).
    var games: [GameRecord] = []
    /// Round 30: the software suspended under the menu (HOME in a game):
    /// its card is the first tile; nil on the menu alone.
    @Published var suspended: GameCardInfo?
    /// The small icons along the top (round 32: 游戏笔记 and 屏幕亮度 with
    /// nothing suspended; 保存进度 and 读取进度 before them over software).
    @Published var shortcuts: [ConsoleHomeShortcut] = ConsoleHomeShortcut.idle
    /// 按键点屏 for the suspended software (its small icon shows it).
    @Published var keyTaps = false
    /// 倍速 of the suspended software.
    @Published var speed: Double = 1
    /// The 存档位 the suspended game uses (its small icon names it).
    @Published var slot = 1
    /// Round 32: the page of tiles (two rows of four each).
    @Published private(set) var page = 0
    /// A question over the touch screen (closing the software).
    @Published var dialog: ConsoleHomeDialog?
    @Published var dialogFocus = "dialog.cancel"
    /// Something was opened: the program is on its way out.
    private var opened = false

    init() {
        // (The library's cursor on 导入, which this menu does not have: 卡带.)
        let carried = ConsoleHomeCursor.selection
        selection = (carried == nil || carried == .importFiles) ? .card : carried
        if let selection { page = ConsoleHomeLayout.page(of: selection, onHandheld: true) }
    }
    /// The menu is up again after what it opened came back to it (round 30:
    /// 相机 and the others open in place and come back to the menu).
    func reopen(selecting item: ConsoleHomeItem? = nil) {
        opened = false
        dialog = nil
        refreshRow()
        if let item { selection = item; shortcut = nil; page = ConsoleHomeLayout.page(of: item, onHandheld: true) }
    }
    /// Back from what a small icon opened (round 31: 屏幕亮度): onto it.
    func reopen(shortcut item: ConsoleHomeShortcut) {
        opened = false
        dialog = nil
        refreshRow()
        guard shortcuts.contains(item) else { return }
        shortcut = item
        selection = nil
    }
    /// The whole row this menu could have; 系统设置 › 主菜单顶上的按键 may
    /// leave some out (11-15).
    private var row: [ConsoleHomeShortcut] = ConsoleHomeShortcut.idleAll
    /// The row again as 主菜单顶上的按键 has it now (back from 系统设置).
    private func refreshRow() {
        let now = ConsoleHomeShortcut.shown(row)
        guard now != shortcuts else { return }
        shortcuts = now
        if let current = shortcut, !now.contains(current) { shortcut = nil; selection = .card }
    }
    /// HOME brings the menu up over suspended software: the cursor on it
    /// (the row as many as there can be: the menu leaves out what
    /// 主菜单顶上的按键 has off).
    func showSuspended(_ card: GameCardInfo, shortcuts row: [ConsoleHomeShortcut]) {
        suspended = card
        self.row = row
        self.shortcuts = ConsoleHomeShortcut.shown(row)
        selection = .card
        shortcut = nil
        dialog = nil
        opened = false
    }

    /// The menu as the console shows it: the card in the slot as the library
    /// keeps it (FoldArc.insertedCard, how far out), the clock, the battery.
    var state: ConsoleHomeState {
        var state = ConsoleHomeState()
        state.selection = selection
        state.shortcut = shortcut
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "FoldArc.insertedCard") ?? ""
        let out = defaults.double(forKey: "FoldArc.insertedCardOut")
        state.shortcuts = shortcuts
        state.keyTaps = keyTaps
        state.speed = speed
        state.speedLocked = !ProAccess.isPro
        state.slot = slot
        state.page = page
        if let suspended {
            state.card = suspended
            state.suspended = true
        } else if let card = Self.card(id: id, games: games) {
            if out < 0.0001 { state.card = card } else { state.looseTitle = card.title }
            if let game = games.first(where: { $0.id == id }) {
                state.coreMissing = !AzaharSession.isCoreAvailable
                if AzaharSession.isCoreAvailable { state.resumeDate = SaveStates.resumeDate(for: Self.file(for: game)) }
            }
        }
        state.minute = Int(Date().timeIntervalSince1970 / 60)
        state.battery = BatteryLight.shared.level
        state.charging = BatteryLight.shared.pluggedIn
        state.setupPending = !ConsoleSettings.shared.setupDone
        state.onHandheld = true
        return state
    }
    static func card(id: String, games: [GameRecord]) -> GameCardInfo? {
        if id == LaunchPlan.demoCardID { return GameCardInfo(title: "Orbit Garden", subtitle: String(localized: "原创演示 · 内置"), icon: nil, isDemo: true) }
        // A 典藏卡带's card (its films play as a program; here it shows as the card in the slot), while its purchase is owned.
        if let cartridge = Cartridge(rawValue: id) { return ProAccess.cartridges.contains(cartridge) ? GameCardInfo.card(for: cartridge) : nil }
        guard !id.isEmpty, let game = games.first(where: { $0.id == id }) else { return nil }
        return GameCardInfo(title: game.title, subtitle: game.publisher ?? game.resolvedFormat.label, icon: GameIconCache.image(named: game.iconFileName), isDemo: false)
    }
    static func file(for game: GameRecord) -> URL {
        Storage.root.appendingPathComponent("ROMs").appendingPathComponent(game.fileName)
    }
    /// The menu at a moment (the upper screen's clock).
    func state(at date: Date) -> ConsoleHomeState {
        var state = self.state
        state.minute = Int(date.timeIntervalSince1970 / 60)
        return state
    }

    // MARK: The keys and the touch screen

    /// A key from the console or a controller (DemoSession.menuInput): the
    /// program has the console while it runs.
    @discardableResult func handle(_ key: PadButton, down: Bool) -> Bool {
        guard down else { return true }
        if let dialog {
            switch key {
            case .left, .right, .up, .down:
                guard dialog.cancel != nil else { break }
                dialogFocus = dialogFocus == "dialog.confirm" ? "dialog.cancel" : "dialog.confirm"
                ConsoleSounds.shared.play(.move)
            case .a:
                self.dialog = nil
                if dialogFocus == "dialog.confirm" || dialog.cancel == nil { dialog.action() } else { ConsoleSounds.shared.play(.back) }
            case .b:
                self.dialog = nil
                ConsoleSounds.shared.play(.back)
                if dialog.cancel == nil { dialog.action() }
            default: break
            }
            return true
        }
        switch key {
        case .up: move(.up)
        case .down: move(.down)
        case .left: move(.left)
        case .right: move(.right)
        case .a: confirm()
        case .b: back()
        default: break
        }
        return true
    }
    /// A touch on the touch screen, at a point of its picture (400 × 300).
    func tap(_ point: CGPoint) {
        guard dialog == nil, let hit = ConsoleHomeLayout.hit(point, state: state) else { return }
        switch hit {
        case .tile(let item):
            if selection == item, shortcut == nil { confirm() } else { choose(item) }
        case .bar(let action):
            perform(action)
        case .setup:
            start(.setup)
        case .shortcut(let item):
            // The small icons open at the first touch, as small buttons do.
            pick(item)
            confirm()
        case .page(let page):
            turn(to: page)
        }
    }
    func choose(_ item: ConsoleHomeItem) {
        guard !opened else { return }
        selection = item
        shortcut = nil
        page = ConsoleHomeLayout.page(of: item, onHandheld: true)
        ConsoleHomeCursor.selection = item
        ConsoleHaptics.shared.play(.smallButton, .press)
        ConsoleSounds.shared.play(.move)
    }
    /// Round 32: a swipe over the tiles (left: the next page) or a touch on
    /// a page dot; the cursor lands on the same place of the new page.
    func flip(_ delta: Int) { turn(to: page + delta) }
    func turn(to next: Int) {
        guard !opened, dialog == nil else { return }
        let pages = ConsoleHomeLayout.pageCount(onHandheld: true)
        let target = max(0, min(pages - 1, next))
        guard target != page else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        page = target
        shortcut = nil
        selection = ConsoleHomeLayout.landing(on: target, from: selection, onHandheld: true)
        ConsoleHomeCursor.selection = selection
        ConsoleHaptics.shared.play(.smallButton, .press)
        ConsoleSounds.shared.play(.move)
        NSLog("[home] page %d", page + 1)
    }
    /// One of the small icons chosen (the D-pad up into their row).
    private func pick(_ item: ConsoleHomeShortcut) {
        guard !opened else { return }
        if shortcut != item { ConsoleSounds.shared.play(.move) }
        shortcut = item
        selection = nil
        ConsoleHaptics.shared.play(.smallButton, .press)
    }
    private func move(_ direction: ConsoleDirection) {
        guard !opened, ConsoleSettings.shared.setupDone else { return }
        if let current = shortcut, let index = shortcuts.firstIndex(of: current) {
            switch direction {
            case .left: pick(shortcuts[max(0, index - 1)])
            case .right: pick(shortcuts[min(shortcuts.count - 1, index + 1)])
            case .down:
                // Down onto the nearest tile of the first row under it.
                let x = ConsoleHomeLayout.shortcut(index, of: shortcuts.count).midX
                let firstRow = ConsoleHomeLayout.items(onHandheld: true, page: page).prefix(ConsoleHomeLayout.columns)
                let below = firstRow.min { abs(ConsoleHomeLayout.tile($0, onHandheld: true, shortcuts: true).midX - x) < abs(ConsoleHomeLayout.tile($1, onHandheld: true, shortcuts: true).midX - x) } ?? .card
                choose(below)
            case .up: break
            }
            return
        }
        if direction == .up, !shortcuts.isEmpty, let item = selection,
           let index = ConsoleHomeLayout.items(onHandheld: true, page: page).firstIndex(of: item), index < ConsoleHomeLayout.columns {
            // From the first row up into the small icons, the nearest one.
            let x = ConsoleHomeLayout.tile(item, onHandheld: true, shortcuts: true).midX
            let nearest = shortcuts.indices.min { abs(ConsoleHomeLayout.shortcut($0, of: shortcuts.count).midX - x) < abs(ConsoleHomeLayout.shortcut($1, of: shortcuts.count).midX - x) } ?? 0
            pick(shortcuts[nearest])
            return
        }
        choose(ConsoleHomeLayout.move(from: selection, direction, onHandheld: true))
    }
    /// A, or a second tap on what is chosen: its first way in.
    func confirm() {
        guard !opened else { return }
        if !ConsoleSettings.shared.setupDone { start(.setup); return }
        if let shortcut { start(.shortcut(shortcut)); return }
        guard selection != nil else { choose(.card); return }
        if let action = state.bar.right {
            perform(action)
        } else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
        }
    }
    /// B: the cursor goes.
    private func back() {
        guard !opened, selection != nil || shortcut != nil else { return }
        selection = nil
        shortcut = nil
        ConsoleHomeCursor.selection = nil
        ConsoleSounds.shared.play(.back)
    }
    func perform(_ action: ConsoleHomeAction) {
        guard !opened, let item = selection else { return }
        guard ConsoleSettings.shared.setupDone else { start(.setup); return }
        if item == .card, state.bar.right == nil { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        start(.item(item, action))
    }
    private func start(_ request: ConsoleHomeRequest) {
        guard !opened else { return }
        opened = true
        ConsoleHaptics.shared.play(.smallButton, .press)
        switch request {
        case .item(.card, .continueGame), .item(.card, .continueDemo), .item(.card, .closeGame), .item(.card, .closeDemo): break
        case .item(.card, _), .item(.camera, _), .item(.album, _), .item(.settings, _), .item(.activity, _), .item(.theme, _), .item(.manual, _), .item(.modes, _), .item(.pictureFrame, _), .item(.tinBox, _), .setup:
            ConsoleSounds.shared.play(.launch)
        default: ConsoleSounds.shared.play(.select)
        }
        NSLog("[home] open %@", String(describing: request))
        open(request)
    }
    /// A question before something that cannot be undone; 取消 (or B) leaves
    /// the menu as it was.
    func ask(_ dialog: ConsoleHomeDialog) {
        opened = false
        dialogFocus = dialog.cancel == nil ? "dialog.confirm" : "dialog.cancel"
        self.dialog = dialog
    }
    /// The dialog put away without its button (a touch beside it): a
    /// question is not answered; a notice has been read.
    func dismissDialog() {
        guard let dialog else { return }
        self.dialog = nil
        if dialog.cancel == nil { dialog.action() }
    }
}

// MARK: - The two screens

/// The upper LCD: the clock, the battery and what is chosen. With software
/// suspended under the menu and its tile chosen (round 30), the software as
/// it was left (`suspendedTop`: its picture, its name, the key prompts).
struct ConsoleHomeProgramTop: View {
    @ObservedObject var model: ConsoleHomeProgram
    var suspendedTop: AnyView? = nil
    @ObservedObject private var battery = BatteryLight.shared
    var body: some View {
        if let suspendedTop, model.suspended != nil, model.shortcut == nil, model.selection == .card || model.selection == nil {
            suspendedTop
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home-top")
        } else {
            menuTop
        }
    }
    private var menuTop: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width / 500, proxy.size.height / 300)
            // The clock turns over with the minute (a timer kept in the view
            // was made anew with every redraw).
            TimelineView(.everyMinute) { context in
                ConsoleHomeTopArt(state: model.state(at: context.date))
                    .frame(width: 500, height: 300)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: 500 * s, height: 300 * s, alignment: .topLeading)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(SystemMenuStyle.status)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-top")
    }
}

/// The touch screen: the tiles and the bar, touched where they are drawn.
/// Each tile and button also has an element of its own for assistive access
/// and the UI tests, named as on the console in the library ("主菜单：相机",
/// "开启").
struct ConsoleHomeProgramBottom: View {
    @ObservedObject var model: ConsoleHomeProgram
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width / 400, proxy.size.height / 300)
            let origin = CGPoint(x: (proxy.size.width - 400 * s) / 2, y: (proxy.size.height - 300 * s) / 2)
            let state = model.state
            ZStack(alignment: .topLeading) {
                SystemMenuBackdrop()
                ConsoleHomeBottomArt(state: state)
                    .frame(width: 400, height: 300)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: 400 * s, height: 300 * s, alignment: .topLeading)
                    .offset(x: origin.x, y: origin.y)
                    .accessibilityHidden(true)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { location in
                        model.tap(CGPoint(x: (location.x - origin.x) / s, y: (location.y - origin.y) / s))
                    }
                    // Round 32: a swipe sideways turns the page of tiles.
                    .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard abs(dx) > abs(dy), abs(dx) > 36 * s else { return }
                        model.flip(dx < 0 ? 1 : -1)
                    })
                markers(state: state, s: s, origin: origin)
                if let dialog = model.dialog {
                    ConsoleHomeDialogView(model: model, dialog: dialog, s: max(0.55, min(1.2, s)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-bottom")
    }
    @ViewBuilder private func markers(state: ConsoleHomeState, s: Double, origin: CGPoint) -> some View {
        if state.setupPending {
            let button = ConsoleHomeLayout.setupButton
            marker(String(localized: "主菜单：开始设置"), rect: button, s: s, origin: origin)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.tap(CGPoint(x: button.midX, y: button.midY)) }
        } else {
            ForEach(Array(state.shortcuts.enumerated()), id: \.element) { index, shortcut in
                let rect = ConsoleHomeLayout.shortcut(index, of: state.shortcuts.count)
                marker(shortcut.title, rect: rect, s: s, origin: origin)
                    .accessibilityValue(shortcut == .keyTaps ? (state.keyTaps ? String(localized: "开") : String(localized: "关")) : shortcut == .speed ? (state.speedLocked ? String(localized: "典藏卡带") : "\(Int(state.speed))×") : shortcut == .slots ? "\(state.slot)" : shortcut.blurb)
                    .accessibilityAddTraits(state.shortcut == shortcut ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { model.tap(CGPoint(x: rect.midX, y: rect.midY)) }
            }
            ForEach(ConsoleHomeLayout.items(onHandheld: true, page: state.page)) { item in
                let rect = ConsoleHomeLayout.tile(item, onHandheld: true, shortcuts: !state.shortcuts.isEmpty)
                marker(String(localized: "主菜单：\(item.title)"), rect: rect, s: s, origin: origin)
                    .accessibilityValue(item == .card ? (state.card?.title ?? (state.looseTitle == nil ? String(localized: "没有卡带") : String(localized: "没插到底"))) : item.blurb)
                    .accessibilityAddTraits(state.selection == item ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { model.tap(CGPoint(x: rect.midX, y: rect.midY)) }
            }
            // Round 32: the other pages, by their dots.
            let pages = state.pageCount
            if pages > 1 {
                ForEach(0..<pages, id: \.self) { page in
                    if page != state.page {
                        marker(String(localized: "主菜单：第 \(page + 1) 页"), rect: ConsoleHomeLayout.pageDot(page, of: pages).insetBy(dx: -4, dy: -5), s: s, origin: origin)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.turn(to: page) }
                    }
                }
            }
            let bar = state.bar
            if let left = bar.left {
                let rect = ConsoleHomeLayout.leftButton
                marker(left.title, rect: rect, s: s, origin: origin)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.perform(left) }
            }
            if let right = bar.right {
                let rect = ConsoleHomeLayout.rightButton
                marker(right.title, rect: rect, s: s, origin: origin)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.perform(right) }
            }
        }
    }
    private func marker(_ label: String, rect: CGRect, s: Double, origin: CGPoint) -> some View {
        Rectangle().fill(Color.white.opacity(0.001))
            .frame(width: rect.width * s, height: rect.height * s)
            .position(x: origin.x + rect.midX * s, y: origin.y + rect.midY * s)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

/// On a phone (its LCDs too small to read the menu in), the two screens over
/// the whole display, one above the other; the console's HOME key is under
/// them, so a button below says 返回游戏库.
struct ConsoleHomeProgramFullScreen: View {
    @ObservedObject var model: ConsoleHomeProgram
    var suspendedTop: AnyView? = nil
    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let topHeight = min(proxy.size.height * 0.42, proxy.size.width * 0.6)
            // With software suspended (round 30) the bar's 继续 is the way
            // back: no button of its own below.
            let leaveButton = model.suspended == nil
            VStack(spacing: 0) {
                ConsoleHomeProgramTop(model: model, suspendedTop: suspendedTop)
                    .frame(width: proxy.size.width, height: topHeight)
                    .padding(.top, insets.top)
                    .background(SystemMenuStyle.status)
                Rectangle().fill(SystemMenuStyle.bar).frame(height: 4)
                ConsoleHomeProgramBottom(model: model)
                    .frame(height: max(120, proxy.size.height - topHeight - insets.top - insets.bottom - (leaveButton ? 62 : 4)))
                    .background(SystemMenuStyle.bar)
                if leaveButton {
                    Button {
                        ConsoleSounds.shared.play(.back)
                        model.leave()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "house").font(.system(size: 13, weight: .bold))
                            Text("返回游戏库").font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 40)
                        .background(Capsule().fill(.white.opacity(0.14)))
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityIdentifier("home-leave")
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .padding(.bottom, insets.bottom)
                    .background(SystemMenuStyle.bar)
                } else {
                    SystemMenuStyle.bar.frame(height: insets.bottom + 4)
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// The menu's question over the touch screen (round 30): 取消 on the left,
/// what it does on the right, the cursor on 取消 first.
struct ConsoleHomeDialogView: View {
    @ObservedObject var model: ConsoleHomeProgram
    var dialog: ConsoleHomeDialog
    var s: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).onTapGesture { model.dismissDialog() }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text(dialog.title).font(.system(size: 13 * s, weight: .bold, design: .rounded))
                Text(dialog.message).font(.system(size: 10 * s)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8 * s) {
                    if let cancel = dialog.cancel {
                        button(cancel, id: "dialog.cancel", color: SystemMenuStyle.inkSoft, identifier: "close-cancel") {
                            model.dialog = nil
                            ConsoleSounds.shared.play(.back)
                        }
                    }
                    // A notice's one button is the menu's blue, not 关闭's red.
                    button(dialog.confirm, id: "dialog.confirm", color: dialog.cancel == nil ? SystemMenuStyle.accent : SystemMenuStyle.stop,
                           identifier: dialog.cancel == nil ? "dialog-ok" : "close-confirm") {
                        let action = dialog.action
                        model.dialog = nil
                        action()
                    }
                }
            }
            .padding(14 * s).frame(maxWidth: 280 * s, alignment: .leading)
            .background(SystemMenuStyle.paper, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(SystemMenuStyle.tileEdge, lineWidth: 1))
            .foregroundStyle(SystemMenuStyle.ink)
            .padding(16 * s)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .environment(\.colorScheme, .light)
    }
    private func button(_ title: String, id: String, color: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button { model.dialogFocus = id; action() } label: {
            Text(title).font(.system(size: 11 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 30 * s)
                .background(color, in: Capsule())
                .overlay { if model.dialogFocus == id { MenuCursorRing(shape: Capsule(), s: s, color: .white) } }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
