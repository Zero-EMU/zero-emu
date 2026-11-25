import SwiftUI

// The HOME menu's two screens (round 17; see SystemMenu.swift). PlayView
// builds a HomeMenuContext from its state and puts the screens into the
// environment as the ScreenOverlay; the consoles draw them in their LCDs.

struct HomeMenuContext {
    var isDemo: Bool
    var title: String
    var publisher: String?
    var icon: CGImage?
    /// The session's status line (what the last key did, the core's state).
    var status: String
    var paused: Bool
    var mode: Binding<ScreenLayout>
    var finish: Binding<ShellFinish>
    var brightness: Binding<Double>
    var depth: Binding<Double>
    var haptics: Binding<Bool>
    var hapticStrength: Binding<Double>
    var showGuides: Binding<Bool>
    var previewFraction: Binding<Double>
    var previewGap: Binding<Double>
    var confirmingClose: Binding<Bool>
    /// A phone: 合上掌机 shows the cover preview.
    var canCloseLid: Bool
    /// 掌机模式: the screen-edge guides toggle.
    var showsGuidesToggle: Bool
    /// 掌机模式 on a phone: where the pretend fold is.
    var showsFoldCalibration: Bool
    /// The suspended software's upper screen, live.
    var screen: AnyView
    var guide: [(String, String)]
    var guideNote: String
    var developer: AnyView?
    var resume: () -> Void
    /// 关闭软件 (asks first) or 返回游戏库 (the demo).
    var requestClose: () -> Void
    var confirmClose: () -> Void
    var save: () -> Void
    var restore: () -> Void
    var closeLid: () -> Void
    var testHaptic: () -> Void
}

/// Upper screen: the status strip, the suspended software's banner with its
/// live picture, and the key prompts.
struct HomeMenuTopScreen: View {
    var ctx: HomeMenuContext
    var body: some View {
        GeometryReader { proxy in
            let s = max(0.55, min(1, proxy.size.width / 440))
            ZStack {
                SystemMenuBackdrop()
                VStack(spacing: 0) {
                    MenuStatusStrip(s: s, title: "HOME", trailing: ctx.mode.wrappedValue.title, showsPercent: true)
                    Spacer(minLength: 0)
                    HStack(alignment: .center, spacing: 14 * s) {
                        ctx.screen
                            .aspectRatio(5 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 5 * s))
                            .overlay(RoundedRectangle(cornerRadius: 5 * s).strokeBorder(SystemMenuStyle.ink.opacity(0.4), lineWidth: 1))
                            .shadow(color: SystemMenuStyle.ink.opacity(0.3), radius: 5 * s, y: 3 * s)
                            .frame(width: proxy.size.width * 0.5)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5 * s) {
                            HStack(spacing: 7 * s) {
                                Group {
                                    if let icon = ctx.icon {
                                        Image(decorative: icon, scale: 1).resizable().interpolation(.high)
                                    } else if ctx.isDemo {
                                        SplashMark().background(Palette.panel)
                                    } else {
                                        Image(systemName: "gamecontroller.fill").font(.system(size: 12 * s)).foregroundStyle(.white)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(SystemMenuStyle.inkSoft)
                                    }
                                }
                                .frame(width: 30 * s, height: 30 * s)
                                .clipShape(RoundedRectangle(cornerRadius: 7 * s, style: .continuous))
                                .accessibilityHidden(true)
                                Text(ctx.title).font(.system(size: 14 * s, weight: .bold, design: .rounded))
                                    .foregroundStyle(SystemMenuStyle.ink).lineLimit(2).minimumScaleFactor(0.8)
                            }
                            if let publisher = ctx.publisher, !publisher.isEmpty {
                                Text(publisher).font(.system(size: 9.5 * s)).foregroundStyle(SystemMenuStyle.inkSoft).lineLimit(1)
                            }
                            Text(ctx.status).font(.system(size: 8.5 * s, design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
                                .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 5 * s) {
                                if ctx.paused {
                                    Text("PAUSED").font(.system(size: 7.5 * s, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6 * s).padding(.vertical, 2.5 * s)
                                        .foregroundStyle(.white).background(SystemMenuStyle.ink, in: Capsule())
                                }
                                Text(ctx.isDemo ? "原创演示" : "Azahar 核心").font(.system(size: 7.5 * s, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6 * s).padding(.vertical, 2.5 * s)
                                    .foregroundStyle(SystemMenuStyle.ink).background(SystemMenuStyle.ink.opacity(0.1), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14 * s)
                    Spacer(minLength: 0)
                    HStack(spacing: 12 * s) {
                        MenuKeyHint(key: "✚", text: String(localized: "移动"), s: s)
                        MenuKeyHint(key: "A", text: String(localized: "决定"), s: s)
                        MenuKeyHint(key: "B", text: String(localized: "返回"), s: s)
                        MenuKeyHint(key: "HOME", text: ctx.isDemo ? String(localized: "继续演示") : String(localized: "继续游戏"), s: s)
                    }
                    .padding(.bottom, 6 * s)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .environment(\.colorScheme, .light)
        }
    }
}

/// Lower screen: the pages (tiles at the root, settings pages, the guide)
/// over the bar with 关闭 / 返回 on the left and 继续 on the right.
struct HomeMenuBottomScreen: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var body: some View {
        GeometryReader { proxy in
            let s = max(0.55, min(1, proxy.size.width / 324))
            ZStack {
                SystemMenuBackdrop()
                VStack(spacing: 0) {
                    Group {
                        // Nothing a page draws may grow past the screen.
                        switch model.page {
                        case .root: HomeRootPage(model: model, ctx: ctx, s: s, width: proxy.size.width, height: proxy.size.height - 30 * s)
                        case .modes: HomeModesPage(model: model, ctx: ctx, s: s)
                        case .finish: HomeFinishPage(model: model, ctx: ctx, s: s)
                        case .feel: HomeFeelPage(model: model, ctx: ctx, s: s)
                        case .guide: HomeGuidePage(model: model, ctx: ctx, s: s)
                        case .developer: HomeDeveloperPage(model: model, ctx: ctx, s: s)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A page opens with the cursor on its first item (the root
                    // on 继续, set when the menu opens).
                    .id(model.page)
                    .onAppear { if model.focus == nil { model.focus = model.layout.first?.first } }
                    MenuBar(s: s, left: leftButton, right: rightButton, focus: model.focus, setFocus: { model.focus = $0 })
                }
                if ctx.confirmingClose.wrappedValue {
                    HomeCloseDialog(model: model, ctx: ctx, s: s)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .foregroundStyle(SystemMenuStyle.ink)
            .tint(SystemMenuStyle.accent)
            .environment(\.colorScheme, .light)
        }
    }
    private var leftButton: MenuBarButton {
        if model.page == .root {
            return MenuBarButton(id: HomeMenuModel.barLeft, title: ctx.isDemo ? String(localized: "返回游戏库") : String(localized: "关闭软件"),
                                 symbol: ctx.isDemo ? "house" : "xmark", color: SystemMenuStyle.stop, action: ctx.requestClose)
        }
        return MenuBarButton(id: HomeMenuModel.barLeft, title: String(localized: "返回"), symbol: "chevron.left", color: SystemMenuStyle.inkSoft) { model.back() }
    }
    private var rightButton: MenuBarButton {
        MenuBarButton(id: HomeMenuModel.barRight, title: ctx.isDemo ? String(localized: "继续演示") : String(localized: "继续游戏"), symbol: "play.fill",
                      color: SystemMenuStyle.go, action: ctx.resume)
    }
}

// MARK: - Pages

private struct HomeRootPage: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var width: Double
    var height: Double
    private struct Tile { var id: String; var title: String; var symbol: String; var accessibility: String? = nil }
    private var tiles: [Tile] {
        var list = [Tile(id: "save", title: String(localized: "保存进度"), symbol: "square.and.arrow.down"),
                    Tile(id: "load", title: String(localized: "读取进度"), symbol: "clock.arrow.circlepath"),
                    Tile(id: "guide", title: String(localized: "操作指南"), symbol: "book"),
                    Tile(id: "modes", title: String(localized: "游玩模式"), symbol: ctx.mode.wrappedValue.symbol),
                    Tile(id: "finish", title: String(localized: "机身配色"), symbol: "paintpalette"),
                    Tile(id: "feel", title: String(localized: "画面与手感"), symbol: "slider.horizontal.3")]
        if ctx.canCloseLid { list.append(Tile(id: "lid", title: String(localized: "合上掌机"), symbol: "rectangle.compress.vertical", accessibility: String(localized: "合上掌机 · 外屏预览"))) }
        if ctx.developer != nil { list.append(Tile(id: "developer", title: String(localized: "开发者"), symbol: "wrench.and.screwdriver")) }
        return list
    }
    var body: some View {
        let tiles = tiles
        let columns = width >= 290 ? 4 : 3
        let gap = 10 * s, inset = 12 * s
        let rows = stride(from: 0, to: tiles.count, by: columns).map { Array(tiles[$0..<min($0 + columns, tiles.count)]) }
        // As big as the width allows, then no taller than the rows fit (label
        // 16 under each tile; the small screen's tile size at least).
        let byWidth = (width - 2 * inset - Double(columns - 1) * gap) / Double(columns)
        let byHeight = (height - 18 * s - Double(rows.count - 1) * 8 * s) / Double(rows.count) - 16 * s
        let tile = max(40 * s, min(byWidth, byHeight, 84 * s))
        register(rows)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8 * s) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(row, id: \.id) { item in
                            MenuTile(id: item.id, title: item.title, symbol: item.symbol, size: tile, s: s,
                                     accessibilityText: item.accessibility, model: model) { activate(item.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, inset).padding(.top, 10 * s).padding(.bottom, 6 * s)
            .frame(width: width, alignment: .leading)
        }
    }
    private func register(_ rows: [[Tile]]) {
        model.layout = rows.map { $0.map(\.id) } + [[HomeMenuModel.barLeft, HomeMenuModel.barRight]]
        var handlers: [String: () -> Void] = [HomeMenuModel.barLeft: ctx.requestClose, HomeMenuModel.barRight: ctx.resume]
        for row in rows { for item in row { handlers[item.id] = { activate(item.id) } } }
        model.handlers = handlers
        model.adjusters = [:]
    }
    private func activate(_ id: String) {
        switch id {
        case "save": ctx.save()
        case "load": ctx.restore()
        case "guide": model.show(.guide)
        case "modes": model.show(.modes)
        case "finish": model.show(.finish)
        case "feel": model.show(.feel)
        case "lid": ctx.closeLid()
        case "developer": model.show(.developer)
        default: break
        }
    }
}

private struct HomeModesPage: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var body: some View {
        register()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6 * s) {
                MenuPageTitle(title: String(localized: "游玩模式"), symbol: "rectangle.on.rectangle", s: s).padding(.horizontal, -12 * s)
                ForEach(ScreenLayout.allCases) { mode in
                    let selected = ctx.mode.wrappedValue == mode
                    Button { model.focus = "mode.\(mode.rawValue)"; choose(mode) } label: {
                        MenuRow(id: "mode.\(mode.rawValue)", s: s, selected: selected, model: model) {
                            HStack(spacing: 9 * s) {
                                Image(systemName: mode.symbol).font(.system(size: 14 * s, weight: .medium))
                                    .frame(width: 28 * s, height: 28 * s)
                                    .foregroundStyle(selected ? .white : SystemMenuStyle.ink)
                                    .background(selected ? SystemMenuStyle.accent : SystemMenuStyle.paperDeep, in: RoundedRectangle(cornerRadius: 7 * s, style: .continuous))
                                VStack(alignment: .leading, spacing: 2 * s) {
                                    Text(mode.title).font(.system(size: 11 * s, weight: .bold, design: .rounded))
                                    Text(mode.summary).font(.system(size: 8.5 * s)).foregroundStyle(SystemMenuStyle.inkSoft)
                                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 2 * s)
                                if !mode.isOpen { ProLockBadge(size: 12 * s) }
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13 * s)).foregroundStyle(selected ? SystemMenuStyle.accent : SystemMenuStyle.tileEdge)
                            }
                        }
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(mode.title)
                    .accessibilityValue(mode.isOpen ? "" : String(localized: "典藏卡带"))
                    .accessibilityHint(mode.isOpen ? mode.summary : String(localized: "TV模式要典藏卡带：在系统设置的「典藏卡带」里"))
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
                if ctx.showsFoldCalibration {
                    Text("折叠位置校准").font(.system(size: 9.5 * s, weight: .bold, design: .rounded)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .padding(.top, 6 * s)
                    MenuSliderRow(id: "cal.fraction", title: String(localized: "折叠位置"), value: ctx.previewFraction, range: 0.35...0.65, step: 0.01,
                                  valueText: "\(Int(ctx.previewFraction.wrappedValue * 100))%", s: s, model: model)
                    MenuSliderRow(id: "cal.gap", title: String(localized: "折叠预留"), value: ctx.previewGap, range: 0...56, step: 1,
                                  valueText: "\(Int(ctx.previewGap.wrappedValue)) pt", s: s, model: model)
                    Text("在没有折叠屏的 iPhone 上模拟折痕的位置；iPhone Duo 用系统给的真实分区。")
                        .font(.system(size: 8 * s)).foregroundStyle(SystemMenuStyle.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12 * s).padding(.bottom, 8 * s)
        }
    }
    /// TV模式 is Pro's: without it the row only buzzes (Pro's page is in 系统设置).
    private func choose(_ mode: ScreenLayout) {
        guard mode.isOpen else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        ctx.mode.wrappedValue = mode
    }
    private func register() {
        var layout = ScreenLayout.allCases.map { ["mode.\($0.rawValue)"] }
        var handlers: [String: () -> Void] = [HomeMenuModel.barLeft: { model.back() }, HomeMenuModel.barRight: ctx.resume]
        var adjusters: [String: (Int) -> Void] = [:]
        for mode in ScreenLayout.allCases { handlers["mode.\(mode.rawValue)"] = { choose(mode) } }
        if ctx.showsFoldCalibration {
            layout += [["cal.fraction"], ["cal.gap"]]
            adjusters["cal.fraction"] = { ctx.previewFraction.wrappedValue = min(0.65, max(0.35, ctx.previewFraction.wrappedValue + Double($0) * 0.01)) }
            adjusters["cal.gap"] = { ctx.previewGap.wrappedValue = min(56, max(0, ctx.previewGap.wrappedValue + Double($0) * 2)) }
        }
        model.layout = layout + [[HomeMenuModel.barLeft, HomeMenuModel.barRight]]
        model.handlers = handlers
        model.adjusters = adjusters
    }
}

private struct HomeFinishPage: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var body: some View {
        register()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5 * s) {
                HStack {
                    MenuPageTitle(title: String(localized: "机身配色"), symbol: "paintpalette", s: s).padding(.horizontal, -12 * s)
                    Text("\(ctx.finish.wrappedValue.family.label) · \(ctx.finish.wrappedValue.name)")
                        .font(.system(size: 8.5 * s, weight: .semibold, design: .monospaced)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .lineLimit(1).padding(.top, 4 * s)
                }
                ForEach(ShellFinish.Family.allCases) { family in
                    HStack(alignment: .top, spacing: 8 * s) {
                        Text(family.label).font(.system(size: 8.5 * s, weight: .semibold)).foregroundStyle(SystemMenuStyle.inkSoft)
                            .frame(width: 40 * s, alignment: .leading).padding(.top, 5 * s)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 24 * s), spacing: 3 * s)], alignment: .leading, spacing: 3 * s) {
                            ForEach(ShellFinish.finishes(in: family)) { item in
                                let selected = ctx.finish.wrappedValue == item
                                Button { model.focus = "finish.\(item.rawValue)"; ctx.finish.wrappedValue = item } label: {
                                    FinishSwatch(finish: item, selected: selected, size: 19 * s)
                                        .overlay(alignment: .bottomTrailing) { if !item.isOpen { ProLockBadge(size: 9 * s) } }
                                        .overlay { if model.focus == "finish.\(item.rawValue)" { MenuCursorRing(shape: Circle(), s: s) } }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("机身配色：\(item.name)")
                                .accessibilityValue(Text(verbatim: item.isOpen ? "" : String(localized: "典藏卡带")))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                    .padding(.horizontal, 8 * s).padding(.vertical, 4 * s)
                    .background(SystemMenuStyle.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                }
                if !ProAccess.isPro {
                    Text("带锁的是典藏卡带的配色：在「系统设置 › 典藏卡带」里开通。")
                        .font(.system(size: 8.5 * s, weight: .medium)).foregroundStyle(SystemMenuStyle.inkSoft)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4 * s)
                }
            }
            .padding(.horizontal, 12 * s).padding(.bottom, 8 * s)
        }
    }
    private func register() {
        var handlers: [String: () -> Void] = [HomeMenuModel.barLeft: { model.back() }, HomeMenuModel.barRight: ctx.resume]
        var layout: [[String]] = []
        for family in ShellFinish.Family.allCases {
            let items = ShellFinish.finishes(in: family)
            layout.append(items.map { "finish.\($0.rawValue)" })
            for item in items { handlers["finish.\(item.rawValue)"] = { ctx.finish.wrappedValue = item } }
        }
        model.layout = layout + [[HomeMenuModel.barLeft, HomeMenuModel.barRight]]
        model.handlers = handlers
        model.adjusters = [:]
    }
}

private struct HomeFeelPage: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var body: some View {
        register()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6 * s) {
                MenuPageTitle(title: String(localized: "画面与手感"), symbol: "slider.horizontal.3", s: s).padding(.horizontal, -12 * s)
                MenuSliderRow(id: "feel.brightness", title: String(localized: "屏幕亮度"), value: ctx.brightness, range: 0.4...1, step: nil,
                              valueText: "\(Int((ctx.brightness.wrappedValue * 100).rounded()))%", s: s, model: model)
                MenuSliderRow(id: "feel.depth", title: String(localized: "3D 深度"), value: ctx.depth, range: 0...1, step: 0.1,
                              valueText: ctx.depth.wrappedValue == 0 ? String(localized: "关") : String(localized: "\(Int((ctx.depth.wrappedValue * 100).rounded()))% · 红蓝眼镜"), s: s, model: model)
                #if os(iOS)
                MenuToggleRow(id: "feel.haptics", title: String(localized: "按键震动"), isOn: ctx.haptics, s: s, model: model)
                if ctx.haptics.wrappedValue {
                    MenuSliderRow(id: "feel.strength", title: String(localized: "震动强度"), value: ctx.hapticStrength, range: 0.2...1, step: nil,
                                  valueText: "\(Int((ctx.hapticStrength.wrappedValue * 100).rounded()))%", s: s, model: model,
                                  onEditingEnded: ctx.testHaptic)
                }
                #endif
                if ctx.showsGuidesToggle {
                    MenuToggleRow(id: "feel.guides", title: String(localized: "屏幕边界与折叠参考线"), isOn: ctx.showGuides, s: s, model: model)
                }
            }
            .padding(.horizontal, 12 * s).padding(.bottom, 8 * s)
        }
    }
    private func register() {
        var layout: [[String]] = [["feel.brightness"], ["feel.depth"]]
        var handlers: [String: () -> Void] = [HomeMenuModel.barLeft: { model.back() }, HomeMenuModel.barRight: ctx.resume]
        var adjusters: [String: (Int) -> Void] = [
            "feel.brightness": { ctx.brightness.wrappedValue = min(1, max(0.4, ctx.brightness.wrappedValue + Double($0) * 0.05)) },
            "feel.depth": { ctx.depth.wrappedValue = min(1, max(0, ctx.depth.wrappedValue + Double($0) * 0.1)) }
        ]
        #if os(iOS)
        layout.append(["feel.haptics"])
        handlers["feel.haptics"] = { ctx.haptics.wrappedValue.toggle() }
        if ctx.haptics.wrappedValue {
            layout.append(["feel.strength"])
            adjusters["feel.strength"] = { ctx.hapticStrength.wrappedValue = min(1, max(0.2, ctx.hapticStrength.wrappedValue + Double($0) * 0.1)); ctx.testHaptic() }
        }
        #endif
        if ctx.showsGuidesToggle {
            layout.append(["feel.guides"])
            handlers["feel.guides"] = { ctx.showGuides.wrappedValue.toggle() }
        }
        model.layout = layout + [[HomeMenuModel.barLeft, HomeMenuModel.barRight]]
        model.handlers = handlers
        model.adjusters = adjusters
    }
}

private struct HomeGuidePage: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var body: some View {
        register()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 7 * s) {
                Text("掌机操作指南").font(.system(size: 12 * s, weight: .bold, design: .rounded)).padding(.top, 8 * s)
                ForEach(ctx.guide, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 1.5 * s) {
                        Text(item.0).font(.system(size: 9 * s, weight: .bold, design: .monospaced))
                        Text(item.1).font(.system(size: 8.5 * s)).foregroundStyle(SystemMenuStyle.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                }
                #if os(macOS)
                Text("键盘：方向键 / WASD，J K U I = A B X Y，Q E = L R，回车暂停，Esc 打开 HOME。").font(.system(size: 8 * s)).foregroundStyle(SystemMenuStyle.inkSoft)
                #endif
                Text(ctx.guideNote).font(.system(size: 8 * s)).foregroundStyle(SystemMenuStyle.inkSoft).fixedSize(horizontal: false, vertical: true)
                Button { model.focus = "guide.ok"; model.back() } label: {
                    Text("知道了").font(.system(size: 10 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 16 * s).padding(.vertical, 6 * s)
                        .background(SystemMenuStyle.accent, in: Capsule())
                        .overlay { if model.focus == "guide.ok" { MenuCursorRing(shape: Capsule(), s: s, color: .white) } }
                }
                .buttonStyle(MenuPressStyle())
                .padding(.bottom, 8 * s)
            }
            .padding(.horizontal, 12 * s)
        }
    }
    private func register() {
        model.layout = [["guide.ok"], [HomeMenuModel.barLeft, HomeMenuModel.barRight]]
        model.handlers = ["guide.ok": { model.back() }, HomeMenuModel.barLeft: { model.back() }, HomeMenuModel.barRight: ctx.resume]
        model.adjusters = [:]
    }
}

private struct HomeDeveloperPage: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var body: some View {
        register()
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6 * s) {
                MenuPageTitle(title: String(localized: "开发者（调试构建）"), symbol: "wrench.and.screwdriver", s: s).padding(.horizontal, -12 * s)
                if let developer = ctx.developer {
                    developer.font(.system(size: 9.5 * s)).foregroundStyle(SystemMenuStyle.ink)
                        .padding(10 * s)
                        .background(SystemMenuStyle.tile, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
                }
            }
            .padding(.horizontal, 12 * s).padding(.bottom, 8 * s)
        }
    }
    private func register() {
        model.layout = [[HomeMenuModel.barLeft, HomeMenuModel.barRight]]
        model.handlers = [HomeMenuModel.barLeft: { model.back() }, HomeMenuModel.barRight: ctx.resume]
        model.adjusters = [:]
    }
}

/// 关闭软件 asks first, drawn in the lower screen like the console's own
/// dialogs (never a system alert over the console; see PlayView).
private struct HomeCloseDialog: View {
    @ObservedObject var model: HomeMenuModel
    var ctx: HomeMenuContext
    var s: Double
    var body: some View {
        register()
        return ZStack {
            Color.black.opacity(0.45)
                .onTapGesture { ctx.confirmingClose.wrappedValue = false }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text("关闭软件？").font(.system(size: 12 * s, weight: .bold, design: .rounded))
                Text("未保存的进度会丢失。关闭后回到游戏库。").font(.system(size: 9 * s)).foregroundStyle(SystemMenuStyle.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8 * s) {
                    dialogButton("取消", id: "close.cancel", color: SystemMenuStyle.inkSoft, identifier: "close-cancel") { ctx.confirmingClose.wrappedValue = false }
                    dialogButton("关闭软件", id: "close.confirm", color: SystemMenuStyle.stop, identifier: "close-confirm", action: ctx.confirmClose)
                }
            }
            .padding(14 * s).frame(maxWidth: 260 * s, alignment: .leading)
            .background(SystemMenuStyle.paper, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(SystemMenuStyle.tileEdge, lineWidth: 1))
            .padding(16 * s)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { model.focus = "close.cancel" }
        .onDisappear { model.escape = nil; if model.focus == "close.cancel" || model.focus == "close.confirm" { model.focus = HomeMenuModel.barLeft } }
    }
    private func dialogButton(_ title: String, id: String, color: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button { model.focus = id; action() } label: {
            Text(title).font(.system(size: 10 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 12 * s).padding(.vertical, 6 * s)
                .background(color, in: Capsule())
                .overlay { if model.focus == id { MenuCursorRing(shape: Capsule(), s: s, color: .white) } }
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityIdentifier(identifier)
    }
    private func register() {
        model.layout = [["close.cancel", "close.confirm"]]
        model.handlers = ["close.cancel": { ctx.confirmingClose.wrappedValue = false }, "close.confirm": ctx.confirmClose]
        model.adjusters = [:]
        model.escape = { ctx.confirmingClose.wrappedValue = false }
    }
}

// MARK: - Rows

struct MenuSliderRow: View {
    var id: String
    var title: String
    var value: Binding<Double>
    var range: ClosedRange<Double>
    var step: Double?
    var valueText: String
    var s: Double
    @ObservedObject var model: HomeMenuModel
    var onEditingEnded: (() -> Void)? = nil
    var body: some View {
        MenuRow(id: id, s: s, model: model) {
            VStack(alignment: .leading, spacing: 3 * s) {
                HStack {
                    Text(title).font(.system(size: 10 * s, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(valueText).font(.system(size: 8.5 * s, design: .monospaced).monospacedDigit()).foregroundStyle(SystemMenuStyle.inkSoft)
                }
                Group {
                    if let step {
                        Slider(value: value, in: range, step: step) { editing in if !editing { onEditingEnded?() } }
                    } else {
                        Slider(value: value, in: range) { editing in if !editing { onEditingEnded?() } }
                    }
                }
                .tint(SystemMenuStyle.accent)
                .accessibilityLabel(title).accessibilityValue(valueText)
            }
        }
        .onTapGesture { model.focus = id }
    }
}

struct MenuToggleRow: View {
    var id: String
    var title: String
    var isOn: Binding<Bool>
    var s: Double
    @ObservedObject var model: HomeMenuModel
    var body: some View {
        MenuRow(id: id, s: s, model: model) {
            Toggle(isOn: isOn) {
                Text(title).font(.system(size: 10 * s, weight: .semibold, design: .rounded))
            }
            .tint(SystemMenuStyle.accent)
        }
        .onTapGesture { model.focus = id }
    }
}
