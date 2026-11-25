import SwiftUI
import ImageIO
import AVFoundation
#if os(iOS)
import UIKit
import PencilKit
import PhotosUI
#if DEBUG
import GameController
#endif
#endif

// 铅笔盒 open (PencilBox.swift has the box and what is kept): over the whole
// inner display, the box lying open as a real one does, the Duo's fold its
// hinge (PencilBoxOpen). Above, the inside of the lid: the multiplication
// table, the timetable in its sleeve, one's own photos and notes under two
// elastic straps (a finger plucks them: they bounce and settle), paper
// tags (返回, 贴照片 · 游戏笔记 · 写便条). Below, the box: a ruler and two
// pencils in their grooves, the sharpener (a pencil held in it is
// sharpened, its shavings dropping into it), the rack (the other pencils,
// one of each colour, standing in it), and a well for each of its own things. A tap puts a thing on the cover and
// leaves its hollow; a tap on the hollow takes it back. 照片: the album's,
// or Photos' own picker (only the photos picked come to the app); 游戏笔记:
// a page of the pad; 写便条: a note written with a finger or Apple Pencil,
// or typed in the handwriting typeface.

/// A thing in the open box: one of its own, or one's own photo or note
/// (its id is what the cursor is on, and the test's way to it).
enum PencilEntry: Hashable {
    case thing(PencilThing)
    case own(UUID)
    var id: String {
        switch self {
        case .thing(let thing): return "pencil.item.\(thing.rawValue)"
        case .own(let id): return "pencil.item.\(id.uuidString)"
        }
    }
    static func from(focus: String?) -> PencilEntry? {
        guard let focus, focus.hasPrefix("pencil.item.") else { return nil }
        let rest = String(focus.dropFirst("pencil.item.".count))
        if let thing = PencilThing(rawValue: rest) { return .thing(thing) }
        return UUID(uuidString: rest).map { .own($0) }
    }
}

private enum PencilInk {
    static let ink = Color(red: 0.23, green: 0.17, blue: 0.14)
    static let pencil = Color(red: 0.36, green: 0.36, blue: 0.40)
    static let paper = Color(red: 0.97, green: 0.94, blue: 0.87)
    static let teal = Color(red: 0.25, green: 0.52, blue: 0.48)
    static let tealDeep = Color(red: 0.17, green: 0.37, blue: 0.34)
    /// A well's floor, and the light and the shade on the walls of a hollow in it.
    static let floor = Color(red: 0.84, green: 0.80, blue: 0.714)
    static let hollowLit = Color(red: 0.98, green: 0.965, blue: 0.925)
    static let hollowShade = Color(red: 0.47, green: 0.415, blue: 0.337)
}

/// Where the keys' cursor is in the open box: a soft light over the thing,
/// and only when a key put the cursor there (ConsoleAppModel.focusKeyed). A
/// touch leaves no mark: no frame is drawn round what was touched last.
private struct PencilCursorGlow<S: Shape>: View {
    var shape: S
    var s: Double
    var body: some View {
        shape.fill(Color.white.opacity(0.36))
            .blur(radius: 1.2 * s)
            .phaseAnimator([1.0, 0.5]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
            .allowsHitTesting(false)
    }
}

// MARK: - The box open

/// 铅笔盒 open over the whole inner display (PencilOpenLayout has where
/// each thing lies). A thing tapped in its well goes onto the cover (the
/// lid's outside); its place keeps a hollow of its shape, and a tap on that
/// takes it off again. One's own photos and notes are tucked
/// under the lid's strap the same way (pressed long: 写字 for a note, 扔掉),
/// side by side and a page at a time (11-16: one strap, the things larger;
/// two to a page upright, three across): a swipe along the strap turns the
/// page, a tap on its dots too. The tray has three layers (11-16: the box's
/// first things on the top one, old everyday things on the two under it): the
/// red ribbon lifts one out to the next. The postcards have a slot of their own on the
/// lid's inside (11-16): a pile, the one on top showing; a swipe up turns to
/// the next, round and round; a tap puts the one on top on the cover and the
/// next shows; the tag over it lays them all out and makes a new one. The
/// paper tags: 返回, and 贴照片 (the
/// album's, or Photos' own picker: only what is picked comes to the app),
/// 游戏笔记 (a page of the pad), 写便条. The ruler and the pencils go onto the
/// cover too; a pencil held and dragged into the sharpener is sharpened, a
/// curl of shaving dropping into it now and then, and a tap there puts a curl
/// on the cover. The red button (笔架) springs the rack up, the pencils not in
/// the grooves standing in it (a tap takes one out into a groove; one dragged
/// onto it from a groove goes back in), and folds it flat again. On a
/// Duo the box's hinge is on the display's fold, drawn for the way it is
/// held (upright, or across like a book); on a phone it is as big as fits.
struct PencilBoxOpen: View {
    @ObservedObject var model: ConsoleAppModel
    @ObservedObject private var store = PencilBoxStore.shared
    @ObservedObject private var tin = TinBoxStore.shared
    /// The style and colour chosen in 主题 › 铅笔盒: the pictures are that box's.
    @AppStorage(PencilBoxLook.key) private var lookID = PencilBoxLook.standard.id
    /// The page under the strap (one's own, a page at a time: PencilOpenLayout.pages), and the way the last turn went.
    @State private var layer = 0
    @State private var pageForward = true
    /// The tray's layer that shows (the top one first; the red ribbon lifts it out to the next).
    @State private var tray = 0
    /// 11-17: the things in the wells that are playing (touched: PencilPlay), and since when.
    @State private var played: [PencilThing: Date] = [:]
    /// The postcard on top of the pile in the slot, and the way the pile last turned.
    @State private var cardIndex = 0
    @State private var cardForward = true
    @State private var sheet: PencilSheet?
    /// 11-19: the plastic box's mirror is open (the camera's picture in it).
    @State private var mirrorOpen = false
    @ObservedObject private var hand = PencilHandFont.shared
    /// One's own photos and notes in the order they were there while the box
    /// is open: one stuck on or taken off stays in its place; what is new
    /// goes at the end.
    @State private var order: [UUID] = []
    /// The rack, sprung up by its red button (not kept: shut, the box folds it flat).
    @State private var rackUp = false
    /// A pencil a finger holds: where its back is (drawing points), where the finger took it, whether its
    /// point is in the sharpener, whether it came out of the rack, and whether the finger is over the rack.
    private struct Held: Equatable {
        var tool: PencilTool; var back: CGPoint; var grab: CGVector; var inSharpener: Bool
        var fromRack = false; var overRack = false
    }
    @State private var held: Held?
    /// Turned in the sharpener: it shakes a little each turn.
    @State private var wobble = false
    /// A pencil too short to sharpen any more (let go of, a new one takes its place).
    @State private var stub: PencilTool?
    /// A photo being changed for another (PencilPhotoSwap).
    @State private var swapping: UUID?
    /// 11-22: how far the net pocket's note and eraser have grown for a moment, touched (PencilNetPocket).
    @State private var netBounce: [String: Double] = [:]
    /// 11-15, a phone (no cover to close the box onto): the lid closed and
    /// looked at here, as a Duo's cover shows it.
    @State private var lidShut = false
    /// The lid turning over onto the box (a finger on its latch, or let go
    /// of): 0 open … 1 shut over the box (LidTurnFace); while it moves by
    /// itself, `lidFlipping`.
    @State private var lidTurn = 0.0
    @State private var lidFlipping = false
    /// The shut box lifted and turned upright to be looked at: 0 lying where
    /// the box is, as it came down (its hinge at the top, held upright) … 1
    /// filling the view, its hinge on the left.
    @State private var shutLift = 1.0
    @ObservedObject private var hinge = HingePosture.shared
    /// No hinge reports: a phone (a Duo shows the lid when it is closed).
    private var noCover: Bool { hinge.status == nil }
    @StateObject private var strapMotion = PencilStrapMotion()
    private typealias Spot = PencilOpenLayout.Spot
    private static let space = "pencil-open"

    /// `rackUp`: the rack sprung up from the start (a source render's).
    init(model: ConsoleAppModel, rackUp: Bool = false) {
        _model = ObservedObject(wrappedValue: model)
        _rackUp = State(initialValue: rackUp)
    }

    private var look: PencilBoxLook { PencilBoxLook(id: lookID) }

    private var own: [PencilPiece] {
        let all = (store.tray + store.lid).filter(\.isOwn)
        var byID: [UUID: PencilPiece] = [:]
        for piece in all { byID[piece.id] = piece }
        let known = Set(order)
        return order.compactMap { byID[$0] } + all.filter { !known.contains($0.id) }
    }
    /// How many of one's own a page under the strap holds, the way the box is drawn now.
    @State private var perPage = PencilOpenLayout.upright.perPage
    /// What is tucked under the strap (one's own photos and notes), and the postcards, which have the slot.
    private var tucked: [PencilPiece] { own.filter { $0.kind != .postcard } }
    private var cards: [PencilPiece] { own.filter { $0.kind == .postcard } }
    /// The pile in the slot: the postcards that are in the box (one on the cover has left it).
    private var pile: [PencilPiece] {
        let out = Set(store.lid.map(\.id))
        return cards.filter { !out.contains($0.id) }
    }
    private var layers: Int { PencilOpenLayout.pages(own: tucked.count, perPage: perPage) }
    private var shownLayer: Int { min(layer, layers - 1) }
    /// The wells whose things the box has.
    private var gathered: Int { PencilOpenLayout.things(layer: tray).filter { $0.contains { store.has($0) } }.count }

    var body: some View {
        register()
        return GeometryReader { proxy in
            let place = PencilOpenPlacement.calculate(size: proxy.size, fold: DeviceFoldRegions.read(proxy)?.division)
            let layout = place.layout, k = place.k
            ZStack(alignment: .topLeading) {
                box(layout, k: k)
                    .mask(alignment: .topLeading) { boxShown(layout, k: k) }
                    .accessibilityHidden(lidShut)
                // 11-15 (a phone): the lid turning over onto the box, its inside, then its outside
                if lidMoving {
                    box(layout, k: k)
                        .mask(alignment: .topLeading) { lidHalf(layout, k: k) }
                        .modifier(LidTurnFace(turn: lidTurn, outside: false, across: layout.toolsAcross))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    lidOutside(layout, k: k)
                        .modifier(LidTurnFace(turn: lidTurn, outside: true, across: layout.toolsAcross))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if noCover && !lidShut { latch(layout, k: k) }
                if lidShut { shutLid(layout, k: k) }
            }
            .frame(width: layout.size.width * k, height: layout.size.height * k)
            .position(place.center)
        }
        .background(Color(red: look.backdrop.x, green: look.backdrop.y, blue: look.backdrop.z))
        .ignoresSafeArea()
        .foregroundStyle(PencilInk.ink)
        .environment(\.colorScheme, .light)
        .sheet(item: $sheet) { which in
            switch which {
            case .photos: PencilPhotoSheet { data in sheet = nil; stickPhoto(data) }
            case .pad: PencilPadSheet { note in sheet = nil; store.addNote(note); showLast(); model.say(String(localized: "贴到盒盖上了")) }
            case .write(let id): PencilNoteEditor(id: id) { sheet = nil; if id == nil { showLast() } }
            case .card(let id): PencilCardDesk(start: .card(id)) { _ in sheet = nil }
            case .cards: PencilCardDesk(start: .tin, cards: cards) { id in sheet = nil; if let id { showCard(id) } }
            case .timetable: PencilTimetableSheet(style: look.style) { sheet = nil }
            }
        }
        .onAppear {
            hand.ensure(.notes)
            if order.isEmpty { order = own.map(\.id) }
            // (a postcard that has just come is the one on top of the pile)
            if let fresh = pile.firstIndex(where: { piece in piece.scene.map { store.freshPostcards.contains($0) } ?? false }) { cardIndex = fresh }
        }
        // (what is new keeps its place from the moment it is there)
        .onChange(of: (store.tray + store.lid).filter(\.isOwn).map(\.id)) { _, ids in
            let known = Set(order)
            order += ids.filter { !known.contains($0) }
        }
        .onDisappear { tin.seenAll(); store.seenPostcards(); mirrorOpen = false }
        // (the mirror is shut with the lid, and with a change of box)
        .onChange(of: lidShut) { _, shut in if shut { mirrorOpen = false } }
        .onChange(of: lookID) { _, _ in mirrorOpen = false }
        .task(id: sharpening) { if let tool = sharpening { await sharpen(tool) } }
    }

    private func box(_ layout: PencilOpenLayout, k: Double) -> some View {
        ZStack(alignment: .topLeading) {
            PencilImages.image(layout.background, look: look).resizable()
                .frame(width: layout.size.width * k, height: layout.size.height * k)
                .accessibilityElement()
                .accessibilityLabel(Text("铅笔盒"))
                .accessibilityValue(Text(verbatim: "\(gathered)/\(PencilOpenLayout.things(layer: tray).count)"))
                .accessibilityIdentifier("pencil-box-open")
            netPocket(layout, k: k)
            shavings(layout, k: k)
            rack(layout, k: k)
            butts(layout, k: k)
            redButton(layout, k: k)
            // (the wells' things of the layer that shows: one layer lifted out, the next comes up from under it)
            ZStack(alignment: .topLeading) {
                ForEach(0..<layout.wells.count, id: \.self) { index in well(layout, index, k: k) }
            }
            .id(tray)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)), removal: .opacity.combined(with: .offset(y: -18 * k))))
            tool(.ruler, layout, k: k)
            ForEach(store.grooves.compactMap { $0 }) { pencil in self.tool(pencil, layout, k: k) }
            heldPencil(layout, k: k)
            cardSlot(layout, k: k)
            mirror(layout, k: k)
            timetable(layout, k: k)
            straps(layout, k: k)
            tags(layout, k: k)
            ribbon(layout, k: k)
            if let toast = model.toast {
                Text(verbatim: toast).font(.system(size: 10.5 * k, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white).padding(.horizontal, 12 * k).padding(.vertical, 5 * k)
                    .background(PencilInk.ink.opacity(0.88), in: Capsule())
                    .frame(maxWidth: 420 * k)
                    .position(x: layout.toast.x * k, y: layout.toast.y * k)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("app-toast")
            }
            if let id = swapping, let piece = store.piece(id) {
                PencilPhotoSwap(piece: piece, target: piece.kind == .postcard ? .cardFront : .photo) { withAnimation(.easeOut(duration: 0.15)) { swapping = nil } }
                    .frame(width: layout.size.width * k, height: layout.size.height * k)
            }
        }
        .coordinateSpace(name: Self.space)
    }

    // MARK: The lid shut and opened on a phone (11-15)

    /// The lid is turning, or turned over onto the box.
    private var lidMoving: Bool { lidFlipping || lidTurn > 0 }
    /// What shows of the open box: all of it; while the lid turns, only the box half (the lid is drawn turning).
    private func boxShown(_ layout: PencilOpenLayout, k: Double) -> some View {
        let w = layout.size.width * k, h = layout.size.height * k, half = lidMoving
        return Rectangle()
            .frame(width: layout.toolsAcross && half ? w / 2 : w, height: !layout.toolsAcross && half ? h / 2 : h)
            .offset(x: layout.toolsAcross && half ? w / 2 : 0, y: !layout.toolsAcross && half ? h / 2 : 0)
    }
    /// The lid's half of the open box (upright the top half, across the left).
    private func lidHalf(_ layout: PencilOpenLayout, k: Double) -> some View {
        let w = layout.size.width * k, h = layout.size.height * k
        return Rectangle().frame(width: layout.toolsAcross ? w / 2 : w, height: layout.toolsAcross ? h : h / 2)
    }
    /// The lid's outside, come down over the box: upright, a quarter turn to the right (its hinge at the top).
    private func lidOutside(_ layout: PencilOpenLayout, k: Double) -> some View {
        let r = layout.lidOutside
        return PencilBoxLid(interfaceRotation: layout.toolsAcross ? nil : -90)
            .frame(width: r.width * k, height: r.height * k)
            .position(x: r.midX * k, y: r.midY * k)
            .frame(width: layout.size.width * k, height: layout.size.height * k)
    }

    /// The latch at the lid's edge and its tag, for a finger: pulled toward the hinge, the lid turns over onto
    /// the box with it (let go of past half way, or flicked, it comes down; else it falls open again); a tap
    /// shuts it.
    private func latch(_ layout: PencilOpenLayout, k: Double) -> some View {
        let rect = layout.latch, reach = layout.lidReach * k
        return Color.clear
            .frame(width: rect.width * k, height: rect.height * k)
            .contentShape(Rectangle())
            .onTapGesture { model.focus = "pencil.lid"; shutLidNow() }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard !lidFlipping else { return }
                        let pulled = layout.toolsAcross ? value.translation.width : value.translation.height
                        lidTurn = acos(min(1, max(-1, 1 - pulled / reach))) / .pi
                    }
                    .onEnded { value in
                        guard !lidFlipping else { return }
                        let flung = layout.toolsAcross ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                        if lidTurn > 0.5 || flung > reach * 1.2 {
                            shutLidNow()
                        } else {
                            lidFlipping = true
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { lidTurn = 0 } completion: { lidFlipping = false }
                        }
                    }
            )
            .position(x: rect.midX * k, y: rect.midY * k)
            .accessibilityHidden(true)
    }

    /// The box closed (a phone): its lid as a Duo's cover shows it, what is
    /// stuck on it moved, turned and opened up close there too; its latch (a
    /// tap, or pushed back) or 打开盒盖 opens it again. It comes in lying
    /// where the box is, as the lid came down, and is lifted and turned upright
    /// (`shutLift`).
    private func shutLid(_ layout: PencilOpenLayout, k: Double) -> some View {
        let frame = CGSize(width: layout.size.width * k, height: layout.size.height * k)
        let foot = 56 * k
        let room = CGSize(width: frame.width, height: frame.height - foot)
        let canvas = PencilLidPlacement.calculate(size: room).canvas
        // (lying where the box is: upright the lid a quarter turn to the right, its hinge at the top)
        let target = layout.lidOutside, turned = !layout.toolsAcross
        let small = target.width * k / max(1, turned ? canvas.height : canvas.width)
        let dx = target.midX * k - room.width / 2, dy = target.midY * k - room.height / 2
        let t = shutLift
        // the latch on the lid's outside: the middle of its free edge (the right, as the cover shows it)
        let u = canvas.width / PencilArt.lid.width
        let latchAt = CGPoint(x: (room.width + canvas.width) / 2 - 22 * u, y: room.height / 2)
        return ZStack(alignment: .topLeading) {
            // (the open box under it is not touched while it is shut)
            Color(red: look.backdrop.x, green: look.backdrop.y, blue: look.backdrop.z)
                .opacity(t)
                .contentShape(Rectangle())
            PencilBoxLid()
                .frame(width: room.width, height: room.height)
                .rotationEffect(.degrees(turned ? 90 * (1 - t) : 0))
                .scaleEffect(small + (1 - small) * t)
                .offset(x: dx * (1 - t), y: dy * (1 - t))
                .allowsHitTesting(t > 0.99)
            // the latch: a tap, or pushed back toward the hinge, opens the box
            Color.clear
                .frame(width: 70 * u, height: 150 * u)
                .contentShape(Rectangle())
                .onTapGesture { openLid() }
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in if value.translation.width < -12 { openLid() } })
                .position(latchAt)
                .allowsHitTesting(t > 0.99)
                .accessibilityHidden(true)
            Button { openLid() } label: {
                Label("打开盒盖", systemImage: "chevron.up")
                    .font(.system(size: 13 * k, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18 * k)
                    .frame(minHeight: max(44, 40 * k))
                    .background(Capsule().fill(PencilInk.paper))
                    .overlay(Capsule().strokeBorder(PencilInk.ink.opacity(0.9), lineWidth: max(0.8, 1 * k)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(PencilInk.ink)
            .opacity(t)
            .position(x: frame.width / 2, y: frame.height - foot / 2)
            .accessibilityIdentifier("app.pencil.open-lid")
        }
        .frame(width: frame.width, height: frame.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pencil-lid-shut")
    }
    /// The lid brought down over the box (from where a finger left it), then the shut box lifted and turned to be
    /// looked at.
    private func shutLidNow() {
        guard !lidShut, !lidFlipping else { return }
        // (the turning lid drawn first where it is, then brought down)
        let drawn = lidMoving
        lidFlipping = true
        let down = {
            withAnimation(.easeIn(duration: 0.16 + 0.3 * (1 - lidTurn))) { lidTurn = 1 } completion: { lidCameDown() }
        }
        if drawn { down() } else { DispatchQueue.main.async(execute: down) }
    }
    private func lidCameDown() {
        ConsoleSounds.shared.play(.lidShut)
        ConsoleHaptics.shared.play(.faceButton, .press)
        NSLog("[pencil] the box shut, its lid looked at (no cover)")
        shutLift = 0
        lidShut = true
        // (drawn first lying where the box is, then lifted)
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { shutLift = 1 } completion: {
                // (under the shut box now: the open box as it was)
                lidFlipping = false
                lidTurn = 0
            }
        }
    }
    /// The shut box put down where it lies, then its lid turned back over, open.
    private func openLid() {
        guard lidShut, !lidFlipping else { return }
        lidFlipping = true
        lidTurn = 1
        // (the shut lid drawn over the box first, under the shut box; then the shut box put down onto it)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) { shutLift = 0 } completion: {
                lidShut = false
                ConsoleSounds.shared.play(.lidOpen)
                ConsoleHaptics.shared.play(.smallButton, .press)
                withAnimation(.easeOut(duration: 0.42)) { lidTurn = 0 } completion: { lidFlipping = false; shutLift = 1 }
            }
        }
    }

    // MARK: The rack and its red button

    /// The rack, lying flat in its recess or sprung up (the pencils not in the
    /// grooves standing in it: butts), as the red button last left it.
    private func rack(_ layout: PencilOpenLayout, k: Double) -> some View {
        let rect = layout.rack
        return ZStack {
            PencilImages.image(layout.rackFile, look: look).resizable().opacity(rackUp ? 0 : 1)
            PencilImages.image(layout.rackUpFile, look: look).resizable().opacity(rackUp ? 1 : 0)
                .scaleEffect(rackUp ? 1 : 0.96)
        }
        .frame(width: rect.width * k, height: rect.height * k)
        .position(x: rect.midX * k, y: rect.midY * k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func redButton(_ layout: PencilOpenLayout, k: Double) -> some View {
        Button { model.focus = "pencil.rack"; toggleRack() } label: {
            PencilImages.image("pencilbox-open-button.png").resizable()
                .frame(width: 64 * k, height: 64 * k)
                .frame(width: 48 * k, height: 48 * k)
                .contentShape(Circle())
                .overlay { if model.focusKeyed, model.focus == "pencil.rack" { PencilCursorGlow(shape: Circle(), s: k) } }
        }
        .buttonStyle(PencilPushStyle())
        .position(x: layout.button.x * k, y: layout.button.y * k)
        .accessibilityLabel(Text("红按钮"))
        .accessibilityValue(rackUp ? Text("笔架弹起来了") : Text("笔架放平"))
        .accessibilityIdentifier("app.pencil.rack")
        .overlay(alignment: .topLeading) { rackLabel(layout, k: k) }
    }

    /// 笔架, printed beside its button (upright: down the narrow strip right of it; held across: under it).
    private func rackLabel(_ layout: PencilOpenLayout, k: Double) -> some View {
        let words = Text("笔架").font(.system(size: 10 * k, weight: .bold, design: .rounded)).foregroundStyle(PencilInk.ink.opacity(0.78))
        return Group {
            if layout.toolsAcross {
                words
            } else {
                VStack(spacing: 0) { Text(verbatim: "笔"); Text(verbatim: "架") }
                    .font(.system(size: 10 * k, weight: .bold, design: .rounded)).foregroundStyle(PencilInk.ink.opacity(0.78))
            }
        }
        .position(x: (layout.button.x + (layout.toolsAcross ? 0 : 39)) * k, y: (layout.button.y + (layout.toolsAcross ? 36 : 0)) * k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func toggleRack() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { rackUp.toggle() }
        ConsoleSounds.shared.play(rackUp ? .select : .back)
        ConsoleHaptics.shared.play(.faceButton)
        if rackUp { model.say(store.rack.isEmpty ? String(localized: "笔架立起来了（铅笔都拿出来了）") : String(localized: "笔架立起来了：点一支拿出来，拖一支过来插回去")) }
        else { model.say(String(localized: "笔架放平了")) }
    }

    // MARK: The tools: the ruler, the pencils, the sharpener, the rack's pencils

    /// Where a tool lies: its back, and which way it points (down the channel).
    private struct Pose { var back: CGPoint; var axis: CGVector }
    private func channel(_ layout: PencilOpenLayout) -> CGVector { layout.toolsAcross ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0) }
    /// In its groove: the ruler's, or a pencil's of the two beside it (a pencil standing in the rack: the
    /// first's, only the way it points counts).
    private func lying(_ tool: PencilTool, _ layout: PencilOpenLayout) -> Pose {
        let line = tool == .ruler ? layout.rulerLine : layout.grooveLines[store.groove(of: tool) ?? 0]
        return layout.toolsAcross ? Pose(back: CGPoint(x: line, y: layout.toolBack), axis: channel(layout))
                                  : Pose(back: CGPoint(x: layout.toolBack, y: line), axis: channel(layout))
    }
    /// From a pencil's back to its point, in points of the drawing.
    private func reach(_ tool: PencilTool, _ layout: PencilOpenLayout) -> Double {
        (PencilToolArt.bodyLength * store.length(tool) + PencilToolArt.tip.width) * layout.toolScale
    }
    /// A pencil in the sharpener: its point pushed into the hole, most of the cone inside.
    private func sharpeningBack(_ tool: PencilTool, _ layout: PencilOpenLayout) -> CGPoint {
        let way = channel(layout), inside = PencilToolArt.tip.width * 0.55 * layout.toolScale, r = reach(tool, layout)
        return CGPoint(x: layout.hole.x - way.dx * (r - inside), y: layout.hole.y - way.dy * (r - inside))
    }
    private var sharpening: PencilTool? { held?.inSharpener == true ? held?.tool : nil }

    /// A tool drawn at a pose (`template`: its shape only).
    private func toolPicture(_ tool: PencilTool, at p: Pose, layout: PencilOpenLayout, k: Double, template: Bool = false) -> some View {
        let ts = layout.toolScale, left = store.length(tool)
        let size = PencilToolPicture.size(tool, left: left)
        let inset = tool == .ruler ? 1.0 : PencilToolArt.bodyBack
        let mid = (size.width / 2 - inset) * ts
        return PencilToolPicture(tool: tool, left: left, k: k * ts, template: template)
            .rotationEffect(.radians(atan2(p.axis.dy, p.axis.dx)))
            .position(x: (p.back.x + p.axis.dx * mid) * k, y: (p.back.y + p.axis.dy * mid) * k)
    }

    /// The ruler in its groove, or a pencil in one of the two beside it; while it is on the cover, the hollow
    /// it left there. A tap puts it on the cover or takes it back; a pencil held and dragged goes into the
    /// sharpener, or, let go of over the rack, back into the rack.
    @ViewBuilder private func tool(_ tool: PencilTool, _ layout: PencilOpenLayout, k: Double) -> some View {
        let onLid = store.onLid(tool), p = lying(tool, layout), id = "pencil.tool.\(tool.rawValue)"
        if onLid {
            ZStack {
                toolPicture(tool, at: p, layout: layout, k: k, template: true).foregroundStyle(PencilInk.hollowLit.opacity(0.75)).offset(x: 1 * k, y: 1 * k)
                toolPicture(tool, at: p, layout: layout, k: k, template: true).foregroundStyle(PencilInk.hollowShade.opacity(0.55)).offset(x: -1 * k, y: -1 * k)
                toolPicture(tool, at: p, layout: layout, k: k, template: true).foregroundStyle(PencilInk.floor)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            toolPicture(tool, at: p, layout: layout, k: k)
                .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.3), radius: 1.0 * k, x: 1.6 * k, y: 2.2 * k)
                .opacity(held?.tool == tool ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // what a finger takes: the tool's length, a little wider than it is thick
        let size = PencilToolPicture.size(tool, left: store.length(tool))
        let length = size.width * layout.toolScale, thick = max(28, size.height * layout.toolScale + 8)
        let inset = (tool == .ruler ? 1.0 : PencilToolArt.bodyBack) * layout.toolScale
        let center = CGPoint(x: p.back.x + p.axis.dx * (length / 2 - inset), y: p.back.y + p.axis.dy * (length / 2 - inset))
        let shape = RoundedRectangle(cornerRadius: 6 * k, style: .continuous)
        let area = Color.clear
            .frame(width: length * k, height: thick * k)
            .contentShape(shape)
            .overlay { if model.focusKeyed, model.focus == id { PencilCursorGlow(shape: shape, s: k) } }
            .onTapGesture { model.focus = id; if onLid { takeOffTool(tool) } else { stickTool(tool) } }
        Group {
            if tool.isPencil {
                area.gesture(onLid ? nil : drag(tool, layout, k: k, fromRack: false))
            } else {
                area.contextMenu {
                    Text(verbatim: tool.use)
                    if onLid {
                        Button { takeOffTool(tool) } label: { Label("放回铅笔盒", systemImage: "tray.and.arrow.down") }
                    } else {
                        Button { stickTool(tool) } label: { Label("贴到盒盖上", systemImage: "pin") }
                    }
                }
            }
        }
            .rotationEffect(.radians(atan2(p.axis.dy, p.axis.dx)))
            .position(x: center.x * k, y: center.y * k)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: tool.title))
            .accessibilityValue(Text(verbatim: toolValue(tool)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if onLid { takeOffTool(tool) } else { stickTool(tool) } }
            .accessibilityAction(named: Text("削一削")) { if tool.isPencil { turnOnce(tool) } }
            .accessibilityAction(named: Text("插回笔架")) { if tool.isPencil, !onLid { putBackPencil(tool) } }
            .accessibilityIdentifier("app.\(id)")
    }
    private func toolValue(_ tool: PencilTool) -> String {
        let place = store.onLid(tool) ? String(localized: "盒盖上") : (store.inRack(tool) ? String(localized: "笔架上") : String(localized: "托盘里"))
        guard tool.isPencil else { return place }
        return String(localized: "\(place)，还剩 \(Int((store.length(tool) * 100).rounded()))%")
    }

    /// The pencils standing in the rack while it is up, each in its own hole, seen end on: a tap takes one out
    /// into a groove; one dragged out goes there when it is let go of (by way of the sharpener, if it is
    /// brought there). A pencil from a groove held over the rack shows where it will stand.
    @ViewBuilder private func butts(_ layout: PencilOpenLayout, k: Double) -> some View {
        if rackUp {
            ForEach(store.rack) { pencil in butt(pencil, layout, k: k).transition(.opacity) }
            if let h = held, h.overRack, !h.fromRack {
                buttPicture(h.tool, layout, k: k).opacity(0.5).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
    private func buttPicture(_ pencil: PencilTool, _ layout: PencilOpenLayout, k: Double) -> some View {
        let hole = layout.rackHoles[pencil.hole ?? 0], s = layout.toolScale
        let size = PencilToolArt.butt, mid = PencilToolArt.buttMiddle
        return PencilImages.image(pencil.buttFile).resizable()
            .frame(width: size.width * s * k, height: size.height * s * k)
            .position(x: (hole.x + (size.width / 2 - mid.x) * s) * k, y: (hole.y + (size.height / 2 - mid.y) * s) * k)
    }
    private func butt(_ pencil: PencilTool, _ layout: PencilOpenLayout, k: Double) -> some View {
        let hole = layout.rackHoles[pencil.hole ?? 0], id = "pencil.butt.\(pencil.rawValue)"
        // (what a finger takes: the hole and round it, most of the way to the next)
        let pitch = layout.toolsAcross ? 46.75 : 55.5
        let w = layout.toolsAcross ? 70.0 : pitch - 4, h = layout.toolsAcross ? pitch - 4 : 70.0
        let shape = RoundedRectangle(cornerRadius: 8 * k, style: .continuous)
        return ZStack {
            buttPicture(pencil, layout, k: k)
                .opacity(held?.tool == pencil ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: w * k, height: h * k)
                .contentShape(shape)
                .overlay { if model.focusKeyed, model.focus == id { PencilCursorGlow(shape: shape, s: k) } }
                .onTapGesture { model.focus = id; takeOutPencil(pencil) }
                .gesture(drag(pencil, layout, k: k, fromRack: true))
                .position(x: hole.x * k, y: hole.y * k)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: pencil.title))
                .accessibilityValue(Text(verbatim: toolValue(pencil)))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { takeOutPencil(pencil) }
                .accessibilityIdentifier("app.\(id)")
        }
    }
    /// A pencil out of the rack into a groove (to make room, the one taken out before goes back).
    private func takeOutPencil(_ pencil: PencilTool) {
        let done = withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { store.takeOut(pencil) }
        guard let done else { return }
        model.focus = "pencil.tool.\(pencil.rawValue)"
        ConsoleSounds.shared.play(.click)
        ConsoleHaptics.shared.play(.smallButton, .press)
        if let back = done.back { model.say(String(localized: "拿出了\(pencil.title)，\(back.title)插回笔架了")) }
        else { model.say(String(localized: "拿出了\(pencil.title)")) }
    }
    /// A pencil from its groove back into the rack (sprung up first if it lay flat).
    private func putBackPencil(_ pencil: PencilTool) {
        guard store.groove(of: pencil) != nil, !store.onLid(pencil) else { return }
        if !rackUp { withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { rackUp = true } }
        withAnimation(.easeOut(duration: 0.25)) { store.putBack(pencil) }
        if model.focus == "pencil.tool.\(pencil.rawValue)" { model.focus = "pencil.butt.\(pencil.rawValue)" }
        ConsoleSounds.shared.play(.click)
        ConsoleHaptics.shared.play(.smallButton, .press)
        model.say(String(localized: "\(pencil.title)插回笔架了"))
    }

    /// Held by a finger: it lies down the channel and follows the finger; its point brought to the sharpener's
    /// hole, it goes in (and is sharpened while it is held there). Out of a groove, let go of over the rack it
    /// goes into the rack, anywhere else back to its groove; out of the rack, let go of anywhere off it, it
    /// goes into a groove.
    private func drag(_ tool: PencilTool, _ layout: PencilOpenLayout, k: Double, fromRack: Bool) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let at = CGPoint(x: value.location.x / k, y: value.location.y / k)
                let way = channel(layout)
                if held?.tool != tool {
                    let start = CGPoint(x: value.startLocation.x / k, y: value.startLocation.y / k)
                    // (in a groove it is taken where the finger is; out of the rack, by its middle)
                    let back = lying(tool, layout).back
                    let grab = fromRack ? CGVector(dx: -way.dx * reach(tool, layout) * 0.45, dy: -way.dy * reach(tool, layout) * 0.45)
                                        : CGVector(dx: back.x - start.x, dy: back.y - start.y)
                    held = Held(tool: tool, back: CGPoint(x: start.x + grab.dx, y: start.y + grab.dy), grab: grab, inSharpener: false,
                                fromRack: fromRack, overRack: fromRack)
                    model.focus = fromRack ? "pencil.butt.\(tool.rawValue)" : "pencil.tool.\(tool.rawValue)"
                    ConsoleHaptics.shared.play(.smallButton, .press)
                }
                guard var h = held else { return }
                h.back = CGPoint(x: at.x + h.grab.dx, y: at.y + h.grab.dy)
                let r = reach(tool, layout)
                let point = CGPoint(x: h.back.x + way.dx * r, y: h.back.y + way.dy * r)
                let near = hypot(point.x - layout.hole.x, point.y - layout.hole.y) < (h.inSharpener ? 46 : 30)
                if near && !h.inSharpener { ConsoleSounds.shared.play(.click); ConsoleHaptics.shared.play(.faceButton, .press) }
                h.inSharpener = near
                // (over the rack: the finger on it; a pencil from a groove springs it up if it lies flat)
                let over = !near && layout.rack.contains(at)
                if over && !h.overRack && !h.fromRack {
                    ConsoleHaptics.shared.play(.smallButton, .press)
                    if !rackUp {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { rackUp = true }
                        ConsoleSounds.shared.play(.select)
                    }
                }
                h.overRack = over
                if h != held { held = h }
            }
            .onEnded { _ in
                guard let h = held, h.tool == tool else { return }
                if h.inSharpener { ConsoleHaptics.shared.play(.smallButton, .release) }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { held = nil }
                if h.fromRack && !h.overRack { takeOutPencil(tool) }
                else if !h.fromRack && h.overRack { putBackPencil(tool) }
                // a stub that would not sharpen any more: put back, it is a new pencil
                if stub == tool {
                    stub = nil
                    withAnimation(.easeOut(duration: 0.3)) { store.newPencil(tool) }
                    model.say(String(localized: "换了一支新的\(tool.title)"))
                }
            }
    }

    /// The pencil a finger holds, over everything in the box; in the sharpener, its point hidden in the hole.
    @ViewBuilder private func heldPencil(_ layout: PencilOpenLayout, k: Double) -> some View {
        if let h = held {
            let back = h.inSharpener ? sharpeningBack(h.tool, layout) : h.back
            let picture = toolPicture(h.tool, at: Pose(back: back, axis: channel(layout)), layout: layout, k: k)
                .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.3), radius: 2.2 * k, x: 3 * k, y: 4.5 * k)
            Group {
                if h.inSharpener {
                    picture
                        .rotationEffect(.degrees(wobble ? 0.5 : -0.5), anchor: UnitPoint(x: layout.hole.x / layout.size.width, y: layout.hole.y / layout.size.height))
                        .mask(alignment: .topLeading) {
                            Rectangle().frame(width: (layout.toolsAcross ? layout.size.width : layout.hole.x) * k,
                                              height: (layout.toolsAcross ? layout.hole.y : layout.size.height) * k)
                        }
                } else {
                    picture
                }
            }
            .frame(width: layout.size.width * k, height: layout.size.height * k, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Held in the sharpener: a turn every so often, the pencil a little shorter each time.
    private func sharpen(_ tool: PencilTool) async {
        model.say(String(localized: "按住别松手，在削\(tool.title)"))
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(PencilSharpening.turnSeconds))
            guard !Task.isCancelled, sharpening == tool else { return }
            if !turnOnce(tool) { return }
        }
    }
    @discardableResult private func turnOnce(_ tool: PencilTool) -> Bool {
        let done = withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { store.sharpen(tool) }
        guard done.turned else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
            stub = tool
            model.say(String(localized: "这支\(tool.title)只剩一小截了，削不动了：松手放回去，换一支新的"))
            return false
        }
        withAnimation(.linear(duration: 0.08)) { wobble.toggle() }
        ConsoleSounds.shared.play(.sharpen)
        ConsoleHaptics.shared.play(.smallButton, .press)
        return true
    }

    /// The curls of shaving in the sharpener (a new one drops out of the blade's slot into them); a tap puts the
    /// newest on the cover.
    private func shavings(_ layout: PencilOpenLayout, k: Double) -> some View {
        let r = layout.shavings, ts = layout.toolScale, size = PencilToolArt.shaving
        let count = store.sharpener.count
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(store.sharpener) { bit in
                    let at = CGPoint(x: r.minX + bit.x * r.width, y: r.minY + bit.y * r.height)
                    PencilImages.image(bit.tool.shavingFile(bit.shape)).resizable()
                        .frame(width: size.width * ts * k, height: size.height * ts * k)
                        .rotationEffect(.radians(bit.turn))
                        .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.25), radius: 0.6 * k, x: 0.8 * k, y: 1.0 * k)
                        .position(x: at.x * k, y: at.y * k)
                        .transition(.asymmetric(insertion: .offset(x: (layout.hole.x - at.x) * k, y: (layout.hole.y - at.y) * k).combined(with: .scale(scale: 0.4)),
                                                removal: .scale(scale: 1.3).combined(with: .opacity)))
                }
            }
            .frame(width: layout.size.width * k, height: layout.size.height * k, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8 * k, style: .continuous)
                    .frame(width: r.width * k, height: (r.height + 6) * k)
                    .offset(x: r.minX * k, y: (r.minY - 6) * k)
            }
            .allowsHitTesting(false)
            Button { model.focus = "pencil.shavings"; stickShaving() } label: {
                Color.clear.frame(width: r.width * k, height: r.height * k).contentShape(Rectangle())
                    .overlay { if model.focusKeyed, model.focus == "pencil.shavings" { PencilCursorGlow(shape: RoundedRectangle(cornerRadius: 8 * k), s: k) } }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button { stickShaving() } label: { Label("贴一片到盒盖上", systemImage: "pin") }
                Button(role: .destructive) { withAnimation { store.emptySharpener() }; model.say(String(localized: "木屑倒掉了")) } label: { Label("倒掉", systemImage: "trash") }
            }
            .position(x: r.midX * k, y: r.midY * k)
            .accessibilityLabel(Text("卷笔刀里的木屑"))
            .accessibilityValue(Text(verbatim: String(localized: "\(count) 片")))
            .accessibilityIdentifier("app.pencil.shavings")
        }
    }
    private func stickShaving() {
        let done = withAnimation(.easeOut(duration: 0.2)) { store.stickShaving() }
        if done {
            ConsoleSounds.shared.play(.click)
            model.say(String(localized: "一片木屑贴到盒盖上了"))
        } else {
            ConsoleHaptics.shared.play(.sliderStop, .press)
            model.say(String(localized: "卷笔刀里还没有木屑：按住一支铅笔，拖到卷笔刀里削一削"))
        }
    }
    private func stickTool(_ tool: PencilTool) {
        withAnimation(.easeOut(duration: 0.2)) { store.stick(tool) }
        ConsoleSounds.shared.play(.click)
        model.say(String(localized: "贴到盒盖上了"))
    }
    private func takeOffTool(_ tool: PencilTool) {
        if let piece = store.lid.first(where: { $0.kind == .tool && $0.tool == tool }) { withAnimation(.easeOut(duration: 0.2)) { store.takeOff(piece.id) } }
        ConsoleSounds.shared.play(.back)
        model.say(String(localized: "放回铅笔盒了"))
    }

    // MARK: The wells

    @ViewBuilder private func well(_ layout: PencilOpenLayout, _ index: Int, k: Double) -> some View {
        let rect = layout.wells[index], spots = layout.spots(layer: tray)[index]
        if let first = spots.first, !spots.contains(where: { store.has($0.thing) }), let source = first.thing.source {
            missing(rect, title: first.thing.title, source: source, k: k)
        } else {
            ForEach(spots, id: \.thing) { spot in thing(spot, in: rect, k: k) }
            if spots.count == 1, let only = spots.first, store.onLid(only.thing) {
                Text("在盒盖上").font(.system(size: 9.5 * k, weight: .medium, design: .rounded)).foregroundStyle(PencilInk.pencil.opacity(0.85))
                    .position(x: rect.midX * k, y: (rect.maxY - 12) * k)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// One of the box's things in its well, or, while it is on the cover, the hollow it left.
    private func thing(_ spot: Spot, in rect: CGRect, k: Double) -> some View {
        let art = spot.thing.art, u = spot.u * k
        let onLid = store.onLid(spot.thing)
        let entry = PencilEntry.thing(spot.thing)
        let w = art.size.width * u, h = art.size.height * u
        let shape = RoundedRectangle(cornerRadius: 6 * k, style: .continuous)
        return Button { if onLid { takeOff(entry) } else { touch(spot.thing) } } label: {
            ZStack {
                if onLid {
                    hollow(art.file, w: w, h: h, k: k)
                } else {
                    PencilImages.image(art.shadowFile).resizable().frame(width: w, height: h)
                        .offset(Self.unturned(CGSize(width: art.shadow.width * u, height: art.shadow.height * u), by: spot.turn))
                    ZStack {
                        if spot.thing.play != nil {
                            PencilThingFace(thing: spot.thing, k: u, played: played[spot.thing])
                        } else {
                            PencilImages.image(art.file).resizable()
                        }
                        if spot.thing == .calendar { PencilCalendarPage(k: u) }
                    }
                    .frame(width: w, height: h)
                }
                if isNew(spot.thing) {
                    Text("新").font(.system(size: 7.5 * k, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 3.5 * k).background(Color(red: 0.78, green: 0.24, blue: 0.2), in: Capsule())
                        .rotationEffect(.radians(-spot.turn))
                        .offset(x: w * 0.3, y: -h * 0.3)
                }
            }
            // (the touch: about what is drawn; the picture's edges are its shadow's room)
            .frame(width: w * 0.74, height: h * 0.74)
            .contentShape(shape)
            .overlay { if model.focusKeyed, model.focus == entry.id { PencilCursorGlow(shape: shape, s: k) } }
            .rotationEffect(.radians(spot.turn))
        }
        .buttonStyle(MenuPressStyle())
        .contextMenu {
            Text(verbatim: Self.words(spot.thing))
            if onLid {
                Button { takeOff(entry) } label: { Label("放回铅笔盒", systemImage: "tray.and.arrow.down") }
            } else {
                Button { stick(entry) } label: { Label("贴到盒盖上", systemImage: "pin") }
            }
        }
        .position(x: (rect.midX + spot.dx) * k, y: (rect.midY + spot.dy) * k)
        .accessibilityLabel(Text(verbatim: spot.thing.title))
        .accessibilityValue(onLid ? Text("盒盖上") : Text("托盘里"))
        .accessibilityIdentifier("app.\(entry.id)")
    }

    /// The hollow a thing leaves in its well: its shape pressed in, the
    /// light from the upper left (its upper left wall in shade, its lower
    /// right lit).
    private func hollow(_ file: String, w: Double, h: Double, k: Double) -> some View {
        let image = PencilImages.image(file).renderingMode(.template).resizable()
        return ZStack {
            image.foregroundStyle(PencilInk.hollowLit.opacity(0.75)).offset(x: 1 * k, y: 1 * k)
            image.foregroundStyle(PencilInk.hollowShade.opacity(0.55)).offset(x: -1 * k, y: -1 * k)
            image.foregroundStyle(PencilInk.floor)
        }
        .frame(width: w, height: h)
    }

    /// A well whose thing the box does not have yet: drawn round in pencil, what it is and how far off it is.
    private func missing(_ rect: CGRect, title: String, source: TinThing, k: Double) -> some View {
        let left = String(localized: "还差 \(max(1, source.games - tin.games)) 张游戏")
        return Button {
            ConsoleHaptics.shared.play(.sliderStop, .press)
            model.say(String(localized: "卡带架上攒到 \(source.games) 张游戏，它就来了"))
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8 * k, style: .continuous)
                    .strokeBorder(PencilInk.pencil.opacity(0.65), style: StrokeStyle(lineWidth: max(0.6, 1 * k), dash: [5 * k, 4 * k]))
                    .padding(10 * k)
                VStack(spacing: 3 * k) {
                    Text(verbatim: title).font(.system(size: 10.5 * k, weight: .semibold, design: .rounded))
                    Text(verbatim: left).font(.system(size: 9.5 * k, weight: .regular, design: .rounded))
                }
                .foregroundStyle(PencilInk.pencil.opacity(0.9))
            }
            .frame(width: rect.width * k, height: rect.height * k)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: rect.midX * k, y: rect.midY * k)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: left))
    }

    // MARK: The straps

    private func straps(_ layout: PencilOpenLayout, k: Double) -> some View {
        let all = tucked
        let page = shownLayer, count = layers
        let pieces = Array(all[PencilOpenLayout.onPage(page, own: all.count, perPage: layout.perPage)])
        let length = layout.strapX1 - layout.strapX0
        let slide = (layout.strapX1 - layout.strapX0) * 0.5 * k
        return TimelineView(.animation(paused: !strapMotion.running)) { context in
            let _ = strapMotion.advance(to: context.date, length: length)
            ZStack(alignment: .topLeading) {
                // a swipe along the strap's place turns the page (behind what is tucked there, which takes its own touches)
                Color.clear
                    .frame(width: (length + 16) * k, height: 150 * k)
                    .contentShape(Rectangle())
                    .position(x: (layout.strapX0 + layout.strapX1) / 2 * k, y: layout.slots[0].y * k)
                    .accessibilityHidden(true)
                // what is tucked under the strap moves a little with it
                ZStack(alignment: .topLeading) {
                    ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                        let slot = layout.slots[index]
                        ownPiece(piece, at: CGPoint(x: slot.x, y: slot.y), turn: slot.turn, u: layout.strapScale, k: k)
                            .offset(y: strapMotion.give(0, at: slot.x - layout.strapX0) * 0.28 * k)
                    }
                }
                .id(page)
                .transition(.asymmetric(insertion: .offset(x: pageForward ? slide : -slide).combined(with: .opacity),
                                        removal: .offset(x: pageForward ? -slide : slide).combined(with: .opacity)))
                PencilStrapBands(layout: layout, k: k, look: look, motion: strapMotion)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(0..<layout.strapLines.count, id: \.self) { strap in strapHandle(strap, layout, k: k) }
                if all.isEmpty {
                    // (11-23: only on a new console the first time)
                    OnceHintView("pencil-straps") {
                        Text("照片和便条夹在这里").font(.system(size: 9.5 * k, weight: .regular, design: .rounded)).foregroundStyle(PencilInk.pencil.opacity(0.75))
                            .position(x: layout.strapsHint.x * k, y: layout.strapsHint.y * k)
                            .allowsHitTesting(false)
                    }
                }
                if count > 1 {
                    // (a tap on the dots turns the page too: after the last, the first)
                    Button { model.focus = "pencil.pages"; turnPage(1, around: true) } label: {
                        HStack(spacing: 5 * k) {
                            ForEach(0..<count, id: \.self) { index in
                                Circle().fill(PencilInk.pencil.opacity(index == page ? 0.85 : 0.3))
                                    .frame(width: (index == page ? 5.5 : 4.5) * k, height: (index == page ? 5.5 : 4.5) * k)
                            }
                        }
                        .padding(.horizontal, 10 * k).padding(.vertical, 7 * k)
                        .contentShape(Rectangle())
                        .overlay { if model.focusKeyed, model.focus == "pencil.pages" { PencilCursorGlow(shape: Capsule(), s: k) } }
                    }
                    .buttonStyle(MenuPressStyle())
                    .position(x: layout.pageDots.x * k, y: layout.pageDots.y * k)
                    .accessibilityLabel(Text("松紧带下的东西"))
                    .accessibilityValue(Text(verbatim: "\(page + 1)/\(count)"))
                    .accessibilityIdentifier("app.pencil.pages")
                }
            }
            // (with what is tucked there too: a swipe begun on a photo still turns the page)
            .simultaneousGesture(DragGesture(minimumDistance: 24, coordinateSpace: .named(Self.space)).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                let lo = layout.slots[0].y - 80, hi = layout.slots[0].y + 80
                guard abs(dx) > 44 * k, abs(dx) > abs(dy) * 1.6, value.startLocation.y / k > lo, value.startLocation.y / k < hi,
                      value.startLocation.x / k > layout.strapX0 - 12, value.startLocation.x / k < layout.strapX1 + 12 else { return }
                turnPage(dx < 0 ? 1 : -1)
            })
            .onChange(of: layout.perPage, initial: true) { _, held in if perPage != held { perPage = held } }
        }
    }

    /// The next page of one's own under the strap, or the one before; at an end it stays (a small knock).
    private func turnPage(_ by: Int, around: Bool = false) {
        let count = layers, now = shownLayer
        var next = now + by
        if around { next = (next % count + count) % count } else { next = min(max(0, next), count - 1) }
        guard next != now else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        pageForward = by > 0
        withAnimation(.easeOut(duration: 0.22)) { layer = next }
        ConsoleSounds.shared.play(.move)
    }

    /// Where a finger takes the strap: the band and a little round it. Pulled, it follows the finger; let go, it
    /// bounces; a tap gives it a little flick.
    private func strapHandle(_ strap: Int, _ layout: PencilOpenLayout, k: Double) -> some View {
        let line = layout.strapLines[strap], x0 = layout.strapX0, x1 = layout.strapX1, mid = line + layout.strapH / 2
        return Color.clear
            .frame(width: (x1 - x0 - 16) * k, height: (layout.strapH + 14) * k)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    let x = value.location.x / k - x0
                    let moved = hypot(value.translation.width, value.translation.height) / k
                    let pull = moved < 3 ? 0 : value.location.y / k - mid
                    strapMotion.pull(strap, at: x, by: pull)
                }
                .onEnded { value in
                    let moved = hypot(value.translation.width, value.translation.height) / k
                    if moved < 3 { strapMotion.pull(strap, at: value.location.x / k - x0, by: 7) }
                    let give = abs(strapMotion.strings[strap].largest)
                    strapMotion.letGo()
                    ConsoleSounds.shared.play(.twang, scale: Float(min(1, 0.35 + give / 30)))
                    ConsoleHaptics.shared.play(give > 12 ? .faceButton : .smallButton, .release)
                })
            .position(x: (x0 + x1) / 2 * k, y: mid * k)
            .accessibilityElement()
            .accessibilityLabel(Text("松紧带"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("拨一下")) { strapMotion.pull(strap, at: (x1 - x0) / 2, by: 16); strapMotion.letGo(); ConsoleSounds.shared.play(.twang) }
            .accessibilityAction(named: Text("下一页")) { turnPage(1) }
            .accessibilityAction(named: Text("上一页")) { turnPage(-1) }
            .accessibilityIdentifier("app.pencil.strap.\(strap)")
    }

    /// One's own photo, note or postcard under the strap, or, while it is on the cover, its place drawn round.
    private func ownPiece(_ piece: PencilPiece, at point: CGPoint, turn: Double, u: Double, k: Double) -> some View {
        let onLid = store.lid.contains { $0.id == piece.id }
        let entry = PencilEntry.own(piece.id)
        let art = piece.art, uk = u * k
        let w = art.size.width * uk, h = art.size.height * uk
        let shape = RoundedRectangle(cornerRadius: 6 * k, style: .continuous)
        return Button { if onLid { takeOff(entry) } else { stick(entry) } } label: {
            ZStack {
                if onLid {
                    shape.strokeBorder(PencilInk.pencil.opacity(0.6), style: StrokeStyle(lineWidth: max(0.6, 1 * k), dash: [5 * k, 4 * k]))
                        .frame(width: w * 0.66, height: h * 0.66)
                    Text("在盒盖上").font(.system(size: 8.5 * k, weight: .medium, design: .rounded)).foregroundStyle(PencilInk.pencil.opacity(0.85))
                } else {
                    PencilPieceView(piece: piece, u: uk, scale: 1, layer: .shadow, magnets: false)
                        .offset(Self.unturned(CGSize(width: art.shadow.width * uk, height: art.shadow.height * uk), by: turn))
                    PencilPieceView(piece: piece, u: uk, scale: 1, layer: .face, magnets: false)
                    if let scene = piece.scene, piece.kind == .postcard, store.freshPostcards.contains(scene) {
                        Text("新").font(.system(size: 7.5 * k, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 3.5 * k).background(Color(red: 0.78, green: 0.24, blue: 0.2), in: Capsule())
                            .offset(x: w * 0.3, y: -h * 0.28)
                    }
                }
            }
            .frame(width: w * 0.78, height: h * 0.78)
            .contentShape(shape)
            .overlay { if model.focusKeyed, model.focus == entry.id { PencilCursorGlow(shape: shape, s: k) } }
            .rotationEffect(.radians(onLid ? 0 : turn))
        }
        .buttonStyle(MenuPressStyle())
        .contextMenu {
            if onLid {
                Button { takeOff(entry) } label: { Label("放回铅笔盒", systemImage: "tray.and.arrow.down") }
            } else {
                Button { stick(entry) } label: { Label("贴到盒盖上", systemImage: "pin") }
            }
            if piece.kind == .note {
                Button { sheet = .write(piece.id) } label: { Label("写字", systemImage: "pencil.line") }
            }
            if piece.kind == .photo {
                Button { withAnimation(.easeOut(duration: 0.15)) { swapping = piece.id } } label: { Label("换一张", systemImage: "photo.on.rectangle.angled") }
            }
            if piece.kind == .postcard {
                // (11-16: made one's own, here as on the lid)
                Button { withAnimation(.easeOut(duration: 0.15)) { swapping = piece.id } } label: { Label("换照片", systemImage: "photo.on.rectangle.angled") }
                if piece.ownFront == true, !piece.isMadeCard {
                    Button { store.clearCardFront(piece.id) } label: { Label("换回原来的风景", systemImage: "arrow.uturn.backward") }
                }
                Button { sheet = .card(piece.id) } label: { Label("写背面", systemImage: "pencil.line") }
                if piece.isMadeCard {
                    Button(role: .destructive) { discard(piece.id) } label: { Label("扔掉", systemImage: "trash") }
                } else {
                    Text("画框寄来的：看过哪幅风景，就来一张那幅的明信片。贴到盒盖上，点一下翻到背面。")
                }
            } else {
                Button(role: .destructive) { discard(piece.id) } label: { Label("扔掉", systemImage: "trash") }
            }
        }
        .position(x: point.x * k, y: point.y * k)
        .accessibilityLabel(Text(verbatim: title(piece)))
        .accessibilityValue(onLid ? Text("盒盖上") : Text("托盘里"))
        .accessibilityIdentifier("app.\(entry.id)")
    }

    // MARK: The postcards' slot (11-16)

    /// The postcard on top of the pile (past the last, the first: one put on the cover gives way to the next).
    private var shownCard: Int { cardIndex >= 0 && cardIndex < pile.count ? cardIndex : 0 }

    /// The postcards in their slot on the lid's inside: a pile, the one on top showing whole, the edges of the next
    /// two above it. A swipe up turns to the next (after the last, the first again), a swipe down to the one
    /// before; a tap puts the one on top on the cover, as anything in the box, and the next of the pile shows
    /// (one on the cover is no longer of the pile: the cover's own menu, or 明信片, puts it back); pressed long,
    /// its menu (its back written, its picture changed).
    private func cardSlot(_ layout: PencilOpenLayout, k: Double) -> some View {
        let slot = PencilCardSlot.rect(look.style, across: layout.toolsAcross)
        let all = pile, index = shownCard, u = PencilCardSlot.scale
        let middle = CGPoint(x: slot.midX, y: slot.midY + 3)
        let rise = slot.height * 0.85 * k
        let top = all.isEmpty ? nil : all[index]
        // (the next two round the pile, under the one on top)
        let under: [PencilPiece] = all.count < 2 ? [] : (1...min(2, all.count - 1)).reversed().map { all[PencilCardSlot.turned(index, by: $0, count: all.count)] }
        let lie: [(dx: Double, dy: Double, turn: Double)] = [(-5, -12, -2.2), (4, -6.5, 1.6)]
        return ZStack(alignment: .topLeading) {
            // (a swipe begins anywhere in the slot)
            Color.clear
                .frame(width: slot.width * k, height: slot.height * k)
                .contentShape(Rectangle())
                .position(x: slot.midX * k, y: slot.midY * k)
                .accessibilityHidden(true)
            if let top {
                ForEach(Array(under.enumerated()), id: \.element.id) { place, piece in
                    let at = lie[lie.count - under.count + place]
                    PencilPieceView(piece: piece, u: u * k, scale: 1, layer: .face, magnets: false)
                        .brightness(-0.05)
                        .rotationEffect(.degrees(at.turn))
                        .position(x: (middle.x + at.dx) * k, y: (middle.y + at.dy) * k)
                        .accessibilityHidden(true)
                }
                ownPiece(top, at: middle, turn: 0, u: u, k: k)
                    .id(top.id)
                    .zIndex(1)
                    .transition(cardForward
                        ? .asymmetric(insertion: .opacity, removal: .offset(y: -rise).combined(with: .opacity))
                        : .asymmetric(insertion: .offset(y: -rise).combined(with: .opacity), removal: .opacity))
            } else {
                (cards.isEmpty ? Text("明信片放在这里") : Text("都贴在盒盖上了"))
                    .font(.system(size: 9.5 * k, weight: .regular, design: .rounded)).foregroundStyle(PencilInk.pencil.opacity(0.75))
                    .position(x: slot.midX * k, y: slot.midY * k)
                    .allowsHitTesting(false)
            }
        }
        // (one put on the cover goes as one turned from goes)
        .animation(.easeOut(duration: 0.24), value: all.map(\.id))
        // (before the card's own tap: a swipe begun on it turns the pile and does not put it on the cover)
        .highPriorityGesture(DragGesture(minimumDistance: 16, coordinateSpace: .named(Self.space)).onEnded { value in
            let dx = value.translation.width, dy = value.translation.height
            let began = CGPoint(x: value.startLocation.x / k, y: value.startLocation.y / k)
            guard slot.insetBy(dx: -8, dy: -8).contains(began), abs(dy) > 26 * k, abs(dy) > abs(dx) * 1.3 else { return }
            turnCard(dy < 0 ? 1 : -1)
        })
    }

    /// The tag over the slot: 明信片, and which of how many is on top. It brings their tin up (PencilCardDesk).
    private func cardTag(_ layout: PencilOpenLayout, k: Double) -> some View {
        let rect = PencilCardSlot.tag(over: PencilCardSlot.rect(look.style, across: layout.toolsAcross))
        let count = pile.count
        return paperTag(rect, turn: 1.4, k: k, id: "pencil.card", run: { sheet = .cards }) {
            HStack(spacing: 4 * k) {
                Text("明信片").font(.system(size: 10.5 * k, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                if count > 1 {
                    Text(verbatim: "\(shownCard + 1)/\(count)").font(.system(size: 8 * k, weight: .semibold, design: .rounded)).opacity(0.7)
                }
            }
        }
        .accessibilityLabel(Text("明信片"))
        .accessibilityValue(Text(verbatim: count > 0 ? "\(shownCard + 1)/\(count)" : "0"))
        .accessibilityIdentifier("app.pencil.card")
    }

    /// The next postcard of the pile, or the one before: round and round; with one, a small knock.
    private func turnCard(_ by: Int) {
        let count = pile.count
        guard count > 1 else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        cardForward = by > 0
        withAnimation(.easeOut(duration: 0.24)) { cardIndex = PencilCardSlot.turned(shownCard, by: by, count: count) }
        ConsoleSounds.shared.play(.move)
    }
    /// That postcard on top of the pile (chosen among all of them, or just made).
    private func showCard(_ id: UUID) {
        DispatchQueue.main.async {
            guard let index = pile.firstIndex(where: { $0.id == id }), index != shownCard else { return }
            cardForward = true
            withAnimation(.easeOut(duration: 0.24)) { cardIndex = index }
        }
    }

    // MARK: The paper tags and the ribbon

    private func tags(_ layout: PencilOpenLayout, k: Double) -> some View {
        ZStack(alignment: .topLeading) {
            paperTag(layout.back, turn: -2, k: k, id: ConsoleAppModel.barLeft, run: { model.pop() }) {
                HStack(spacing: 3 * k) {
                    Image(systemName: "chevron.left").font(.system(size: 9 * k, weight: .bold)).accessibilityHidden(true)
                    Text("返回").font(.system(size: 11 * k, weight: .bold, design: .rounded))
                }
            }
            .accessibilityLabel(Text("返回"))
            .accessibilityIdentifier(ConsoleAppModel.barLeft)
            if noCover {
                // 11-15: hung under the lid's latch (held across, along the lid's edge, read turned)
                let tag = layout.lidTag, across = layout.toolsAcross
                paperTag(across ? CGRect(x: tag.midX - tag.height / 2, y: tag.midY - tag.width / 2, width: tag.height, height: tag.width) : tag,
                         turn: across ? -88.5 : 1.2, k: k, id: "pencil.lid", run: { shutLidNow() }) {
                    HStack(spacing: 5 * k) {
                        Image(systemName: "chevron.down").font(.system(size: 9 * k, weight: .bold)).accessibilityHidden(true)
                        (across ? Text("往右拉，合上盒盖") : Text("往下拉，合上盒盖")).font(.system(size: 10 * k, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .accessibilityLabel(Text("合上盒盖"))
                .accessibilityIdentifier("app.pencil.lid")
            }
            entryTag(layout.photo, turn: -2, title: String(localized: "贴照片"), id: "pencil.photo", k: k) { sheet = .photos }
            entryTag(layout.notes, turn: 1.2, title: String(localized: "游戏笔记"), id: "pencil.notes", k: k) { sheet = .pad }
            entryTag(layout.write, turn: -1, title: String(localized: "写便条"), id: "pencil.write", k: k) { sheet = .write(nil) }
            cardTag(layout, k: k)
        }
    }

    private func entryTag(_ rect: CGRect, turn: Double, title: String, id: String, k: Double, run: @escaping () -> Void) -> some View {
        paperTag(rect, turn: turn, k: k, id: id, run: run) {
            Text(verbatim: title).font(.system(size: 10.5 * k, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier("app.\(id)")
    }

    /// A little paper tag on the lid, its edge in ink, a soft shadow to the lower right.
    private func paperTag<Label: View>(_ rect: CGRect, turn: Double, k: Double, id: String, run: @escaping () -> Void,
                                       @ViewBuilder label: () -> Label) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5 * k, style: .continuous)
        return Button { model.focus = id; run() } label: {
            label()
                .foregroundStyle(PencilInk.ink)
                .frame(width: rect.width * k, height: rect.height * k)
                .background(shape.fill(PencilInk.paper))
                .overlay(shape.strokeBorder(PencilInk.ink.opacity(0.9), lineWidth: max(0.8, 1 * k)))
                .compositingGroup()
                .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.25), radius: 0.6 * k, x: 1.5 * k, y: 2 * k)
                .overlay { if model.focusKeyed, model.focus == id { PencilCursorGlow(shape: shape, s: k) } }
                .contentShape(shape)
        }
        .buttonStyle(MenuPressStyle())
        .rotationEffect(.degrees(turn))
        .position(x: rect.midX * k, y: rect.midY * k)
    }

    /// 11-19: the lid's mirror (the plastic box has one), over its drawn glass: a touch opens it, another shuts it.
    @ViewBuilder private func mirror(_ layout: PencilOpenLayout, k: Double) -> some View {
        if let glass = PencilMirror.glass(look.style, across: layout.toolsAcross) {
            PencilMirrorGlass(open: $mirrorOpen, k: k, lit: model.focusKeyed && model.focus == "pencil.mirror")
                .frame(width: glass.width * k, height: glass.height * k)
                .position(x: glass.midX * k, y: glass.midY * k)
        }
    }

    /// 11-19: the lid's timetable: what is written in its boxes, over the card in the picture; a touch takes it
    /// out big, to be written on (PencilTimetableSheet).
    private func timetable(_ layout: PencilOpenLayout, k: Double) -> some View {
        let place = PencilTimetable.place(look.style, across: layout.toolsAcross)
        let cells = PencilTimetable.whole(store.lessons(in: look.style))
        let shape = RoundedRectangle(cornerRadius: 5 * k, style: .continuous)
        return Button { model.focus = "pencil.timetable"; ConsoleSounds.shared.play(.select); sheet = .timetable } label: {
            ZStack(alignment: .topLeading) {
                ForEach(0..<PencilTimetable.count, id: \.self) { index in
                    if !cells[index].isEmpty {
                        let at = PencilTimetable.middle(place, index: index)
                        Text(verbatim: cells[index])
                            .font(hand.font(.notes, size: 9.2 * k)).foregroundStyle(Color(red: 0.33, green: 0.32, blue: 0.35).opacity(0.85))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(width: (place.cell.width - 3) * k, height: place.cell.height * k)
                            .position(x: (at.x - place.card.minX) * k, y: (at.y - place.card.minY) * k)
                    }
                }
            }
            .frame(width: place.card.width * k, height: place.card.height * k, alignment: .topLeading)
            .contentShape(shape)
            .overlay { if model.focusKeyed, model.focus == "pencil.timetable" { PencilCursorGlow(shape: shape, s: k) } }
        }
        .buttonStyle(.plain)
        .position(x: place.card.midX * k, y: place.card.midY * k)
        .accessibilityLabel(Text("课程表"))
        .accessibilityValue(Text(verbatim: "\(cells.filter { !$0.isEmpty }.count)/\(PencilTimetable.count)"))
        .accessibilityIdentifier("app.pencil.timetable")
    }

    /// 11-22: the canvas box's net pocket. The folded note and the eraser drawn in it answer a touch: pressed
    /// through the net, each gives and bounces back (the part of the picture where it lies, drawn again over it
    /// and grown for a moment, its edge melting into the net), with a sound of its own.
    @ViewBuilder private func netPocket(_ layout: PencilOpenLayout, k: Double) -> some View {
        if look.style == .canvas {
            ForEach(PencilNetPocket.things, id: \.name) { thing in netThing(thing, layout: layout, k: k) }
        }
    }
    private func netThing(_ thing: PencilNetPocket.Thing, layout: PencilOpenLayout, k: Double) -> some View {
        let r = thing.patch
        let grown = netBounce[thing.name] ?? 1
        let edge = Gradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78), .init(color: .clear, location: 1)])
        return ZStack {
            PencilImages.image(layout.background, look: look).resizable()
                .frame(width: layout.size.width * k, height: layout.size.height * k)
                .offset(x: (layout.size.width / 2 - r.midX) * k, y: (layout.size.height / 2 - r.midY) * k)
                .frame(width: r.width * k, height: r.height * k)
                .clipped()
                .mask { RadialGradient(gradient: edge, center: .center, startRadius: 0, endRadius: min(r.width, r.height) / 2 * k) }
                .scaleEffect(grown)
                .offset(y: thing.hops ? -(grown - 1) * 40 * k : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: thing.touch.width * k, height: thing.touch.height * k)
                .contentShape(Rectangle())
                .onTapGesture { netTouched(thing) }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: thing.title))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("pencil-net-\(thing.name)")
        }
        .position(x: r.midX * k, y: r.midY * k)
    }
    private func netTouched(_ thing: PencilNetPocket.Thing) {
        ConsoleSounds.shared.play(thing.sound)
        ConsoleHaptics.shared.play(.smallButton, .press)
        withAnimation(.easeOut(duration: 0.06)) { netBounce[thing.name] = 1.06 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { netBounce[thing.name] = 1 }
        }
    }

    /// The red ribbon: 下一层, the tray's layer lifted out to the one under it; under the last, the top one again.
    private func ribbon(_ layout: PencilOpenLayout, k: Double) -> some View {
        let rect = layout.ribbon, count = PencilOpenLayout.trays
        return Button { model.focus = "pencil.layer"; nextTray() } label: {
            HStack(spacing: 4 * k) {
                Text("下一层").font(.system(size: 10.5 * k, weight: .bold, design: .rounded))
                Text(verbatim: "\(tray + 1)/\(count)").font(.system(size: 8 * k, weight: .semibold, design: .rounded)).opacity(0.85)
            }
            .foregroundStyle(Color(red: 0.97, green: 0.9, blue: 0.84))
            .frame(width: rect.width * k, height: rect.height * k)
            .contentShape(Rectangle())
            .overlay { if model.focusKeyed, model.focus == "pencil.layer" { PencilCursorGlow(shape: RoundedRectangle(cornerRadius: 7 * k), s: k) } }
        }
        .buttonStyle(MenuPressStyle())
        .position(x: rect.midX * k, y: rect.midY * k)
        .accessibilityLabel(Text("下一层"))
        .accessibilityValue(Text(verbatim: "\(tray + 1)/\(count)"))
        .accessibilityIdentifier("app.pencil.layer")
    }

    // MARK: What can be done

    /// One of the box's things touched in its well: onto the lid. One of the old everyday things (PencilPlay)
    /// first does what it does, and is heard; then (PencilPlayRule) it goes onto the lid as the others do —
    /// touched again meanwhile, at once — or it stays in its well, to be touched again.
    private func touch(_ thing: PencilThing) {
        guard let play = thing.play else { stick(.thing(thing)); return }
        if !PencilPlayRule.staysInTray, played[thing] != nil {
            played[thing] = nil
            stick(.thing(thing))
            return
        }
        let now = Date()
        played[thing] = now
        model.focus = PencilEntry.thing(thing).id
        ConsoleSounds.shared.play(play.sound)
        ConsoleHaptics.shared.play(.smallButton, .press)
        DispatchQueue.main.asyncAfter(deadline: .now() + play.length + 0.05) {
            guard played[thing] == now else { return }
            played[thing] = nil
            if !PencilPlayRule.staysInTray { stick(.thing(thing)) }
        }
    }
    private func stick(_ entry: PencilEntry) {
        switch entry {
        case .thing(let thing): store.stick(thing)
        case .own(let id): store.stick(id)
        }
        ConsoleSounds.shared.play(.click)
        model.focus = entry.id
        model.say(String(localized: "贴到盒盖上了"))
    }
    private func takeOff(_ entry: PencilEntry) {
        switch entry {
        case .thing(let thing): if let piece = store.lid.first(where: { $0.thing == thing }) { store.takeOff(piece.id) }
        case .own(let id): store.takeOff(id)
        }
        ConsoleSounds.shared.play(.back)
        model.focus = entry.id
        model.say(String(localized: "放回铅笔盒了"))
    }
    private func discard(_ id: UUID) {
        store.discard(id)
        order.removeAll { $0 == id }
        model.focus = nil
        model.say(String(localized: "扔掉了"))
    }
    /// The red ribbon: the tray's layer lifted out, the one under it showing (under the last, the top one again).
    private func nextTray() {
        withAnimation(.easeOut(duration: 0.26)) { tray = PencilOpenLayout.tray(after: tray) }
        ConsoleSounds.shared.play(.move)
        ConsoleHaptics.shared.play(.sliderStop, .press)
    }
    private func stickPhoto(_ data: Data) {
        if store.addPhoto(data) != nil { showLast(); model.say(String(localized: "贴到盒盖上了")) } else { model.say(String(localized: "这张照片读不出来")) }
    }
    /// Something new is at the end: the strap turns to its last page.
    private func showLast() {
        DispatchQueue.main.async { if layer != layers - 1 { pageForward = true; withAnimation(.easeOut(duration: 0.22)) { layer = layers - 1 } } }
    }
    private func isNew(_ thing: PencilThing) -> Bool { thing.source.map { tin.unseen.contains($0) } ?? false }

    /// What VoiceOver (and a test) reads for one's own: a note with words, its words too.
    private func title(_ piece: PencilPiece) -> String {
        let words = piece.kind == .note ? (store.note(piece.id)?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return words.isEmpty ? piece.fullTitle : String(localized: "\(piece.title)：\(String(words.prefix(24)))")
    }
    /// What a thing is and where it came from (its menu, pressed long).
    static func words(_ thing: PencilThing) -> String {
        let came: String
        if let source = thing.source { came = String(localized: "卡带架上有 \(source.games) 张游戏时来的。") } else { came = String(localized: "铅笔盒里本来就有。") }
        return [thing.use, came].joined(separator: "\n")
    }
    /// A shadow's offset, as it must be given to something turned by `turn`
    /// so that it still falls to the lower right.
    static func unturned(_ offset: CGSize, by turn: Double) -> CGSize {
        CGSize(width: offset.width * cos(turn) + offset.height * sin(turn), height: -offset.width * sin(turn) + offset.height * cos(turn))
    }

    // MARK: The keys

    private func register() {
        guard model.page == .tinBox else { return }
        let pieces = tucked
        let mirrored = PencilMirror.glass(look.style, across: false) != nil
        var rows: [[String]] = [[ConsoleAppModel.barLeft] + (noCover ? ["pencil.lid"] : []),
                                (mirrored ? ["pencil.mirror"] : []) + ["pencil.card", "pencil.photo", "pencil.notes", "pencil.write", "pencil.timetable"]]
        var handlers: [String: () -> Void] = [ConsoleAppModel.barLeft: { if lidShut { openLid() } else { model.pop() } }, "pencil.lid": { shutLidNow() },
                                              "pencil.photo": { sheet = .photos }, "pencil.notes": { sheet = .pad }, "pencil.write": { sheet = .write(nil) },
                                              "pencil.card": { sheet = .cards }, "pencil.layer": { nextTray() }, "pencil.shavings": { stickShaving() },
                                              "pencil.pages": { turnPage(1, around: true) },
                                              "pencil.mirror": { mirrorOpen.toggle() }, "pencil.timetable": { sheet = .timetable }]
        for tool in PencilTool.allCases {
            handlers["pencil.tool.\(tool.rawValue)"] = { if store.onLid(tool) { takeOffTool(tool) } else { stickTool(tool) } }
            if tool.isPencil { handlers["pencil.butt.\(tool.rawValue)"] = { takeOutPencil(tool) } }
        }
        func add(_ entries: [PencilEntry]) {
            for entry in entries {
                let onLid: Bool
                switch entry {
                case .thing(let thing): onLid = store.onLid(thing)
                case .own(let id): onLid = store.lid.contains { $0.id == id }
                }
                handlers[entry.id] = {
                    if onLid { takeOff(entry) } else if case .thing(let thing) = entry { touch(thing) } else { stick(entry) }
                }
            }
        }
        // the postcard on top of the pile (left and right turn the pile), then the page under the strap
        var adjusters: [String: (Int) -> Void] = [:]
        let heap = pile
        if !heap.isEmpty {
            let top = PencilEntry.own(heap[shownCard].id)
            rows.append([top.id]); add([top])
            adjusters[top.id] = { turnCard($0) }
        }
        let strap = pieces[PencilOpenLayout.onPage(shownLayer, own: pieces.count, perPage: perPage)].map { PencilEntry.own($0.id) }
        if !strap.isEmpty { rows.append(strap.map(\.id) + (layers > 1 ? ["pencil.pages"] : [])) }
        add(Array(strap))
        // the channel's tools and the sharpener, the rack's pencils while it is up, then the wells (as they lie,
        // top to bottom)
        rows.append(["pencil.tool.ruler"] + store.grooves.compactMap { $0 }.map { "pencil.tool.\($0.rawValue)" } + ["pencil.shavings"])
        if rackUp, !store.rack.isEmpty { rows.append(store.rack.map { "pencil.butt.\($0.rawValue)" }) }
        let had = { (index: Int) in PencilOpenLayout.things(layer: tray)[index].filter { store.has($0) }.map { PencilEntry.thing($0) } }
        for half in [0..<4, 4..<8] {
            let row = half.flatMap(had)
            if !row.isEmpty { rows.append(row.map(\.id)); add(row) }
        }
        rows.append(["pencil.rack", "pencil.layer"])
        handlers["pencil.rack"] = { toggleRack() }
        model.layout = rows
        model.handlers = handlers
        model.adjusters = adjusters
        model.registered(initial: rows.dropFirst(2).first?.first ?? "pencil.photo")
    }
}

/// 11-15 (a phone): the lid turning over onto the box, 0 open … 1 shut,
/// drawn flat: its inside foreshortened toward the hinge (the drawing's
/// middle) until it stands on edge, then its outside coming down over the
/// box; darker the more it stands up. Each frame of a turn drawn as it is
/// (Animatable), the inside giving way to the outside half way.
private struct LidTurnFace: ViewModifier, Animatable {
    var turn: Double
    let outside: Bool
    let across: Bool
    var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }
    func body(content: Content) -> some View {
        let c = cos(min(1, max(0, turn)) * Double.pi)
        let open = outside ? max(0, -c) : max(0, c)
        return content
            .colorMultiply(Color(white: 1 - 0.38 * (1 - open)))
            .scaleEffect(x: across ? max(0.001, open) : 1, y: across ? 1 : max(0.001, open), anchor: .center)
            .opacity(open > 0.002 ? 1 : 0)
    }
}

/// The red button pressed: it goes down into its socket, a little darker.
private struct PencilPushStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// The two straps' strings, run while either moves (PencilStrapString: a pull let go of bounces and settles).
/// Plain values, not published: the straps' TimelineView reads them each frame; `running` starts and stops it.
@MainActor final class PencilStrapMotion: ObservableObject {
    private(set) var strings = [PencilStrapString(length: 242), PencilStrapString(length: 242)]
    private var held: Int?
    private var last: Date?
    @Published private(set) var running = false
    /// Each frame: on by the time since the last (a held one stays as the finger has it).
    func advance(to date: Date, length: Double) {
        if abs(strings[0].length - length) > 0.5 { strings = [PencilStrapString(length: length), PencilStrapString(length: length)]; held = nil }
        let dt = last.map { date.timeIntervalSince($0) } ?? 0
        last = date
        for i in strings.indices where i != held { strings[i].step(dt) }
        if held == nil, !strings.contains(where: \.moving), running {
            last = nil
            DispatchQueue.main.async { if self.held == nil, !self.strings.contains(where: \.moving) { self.running = false } }
        }
    }
    func pull(_ strap: Int, at x: Double, by d: Double) {
        guard strings.indices.contains(strap) else { return }
        held = strap
        strings[strap].pull(at: x, by: d)
        if !running { running = true }
    }
    func letGo() {
        held = nil
        last = nil
        if !running { running = true }
    }
    func give(_ strap: Int, at x: Double) -> Double { strings.indices.contains(strap) ? strings[strap].give(at: x) : 0 }
}

/// The straps drawn as their strings lie: each band cut into thin upright slices, each slice moved by the give
/// where it is; the soft shadow under the band follows it; the ends (clips, caps, tacks, stitched ends) stay.
struct PencilStrapBands: View {
    var layout: PencilOpenLayout
    var k: Double
    var look: PencilBoxLook
    @ObservedObject var motion: PencilStrapMotion
    private static let slices = 36
    var body: some View {
        let band = PencilImages.image("pencilbox-strap-band.png", look: look).resizable()
        let end = PencilImages.image("pencilbox-strap-end.png", look: look).resizable()
        Canvas { context, _ in
            let bandImage = context.resolve(band), endImage = context.resolve(end)
            let x0 = layout.strapX0, x1 = layout.strapX1, h = layout.strapH, n = Self.slices
            for (strap, line) in layout.strapLines.enumerated() {
                let w = (x1 - x0) / Double(n)
                // the shadow: the band's shape, a little to the lower right, soft
                var shade = Path()
                for i in 0...n { let x = x0 + Double(i) * w; let p = CGPoint(x: (x + 1.5) * k, y: (line + 3.5 + motion.give(strap, at: x - x0)) * k); if i == 0 { shade.move(to: p) } else { shade.addLine(to: p) } }
                for i in stride(from: n, through: 0, by: -1) { let x = x0 + Double(i) * w; shade.addLine(to: CGPoint(x: (x + 1.5) * k, y: (line + 3.5 + h + motion.give(strap, at: x - x0)) * k)) }
                shade.closeSubpath()
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2.4 * k))
                    layer.fill(shade, with: .color(Color(red: 0.16, green: 0.12, blue: 0.07).opacity(0.38)))
                }
                // the band, slice by slice (its picture is 420 points long, 11 + 2 high, the band from 1 down)
                for i in 0..<n {
                    let x = x0 + Double(i) * w, give = motion.give(strap, at: x + w / 2 - x0)
                    let slice = CGRect(x: x * k, y: (line - 12 + give) * k, width: w * k + 0.6, height: (h + 24) * k)
                    context.drawLayer { layer in
                        layer.clip(to: Path(slice))
                        layer.draw(bandImage, in: CGRect(x: x0 * k, y: (line - 1 + give) * k, width: 420 * k, height: 13 * k))
                    }
                }
                // the ends (their picture 18 × 23 points, the band's line 6 down)
                for x in [x0, x1] { context.draw(endImage, in: CGRect(x: (x - 9) * k, y: (line - 6) * k, width: 18 * k, height: 23 * k)) }
            }
        }
        .frame(width: layout.size.width * k, height: layout.size.height * k)
    }
}

enum PencilSheet: Identifiable, Equatable {
    /// (11-16: `card`, a postcard taken out big, its back up to be written on; `cards`, the postcards' tin)
    /// (11-19: `timetable`, the lid's timetable taken out big to be written on)
    case photos, pad, write(UUID?), card(UUID), cards, timetable
    var id: String {
        switch self {
        case .photos: return "photos"
        case .cards: return "cards"
        case .timetable: return "timetable"
        case .pad: return "pad"
        case .write(let id): return "write-\(id?.uuidString ?? "new")"
        case .card(let id): return "card-\(id.uuidString)"
        }
    }
}

// MARK: - 照片

/// The album's pictures (newest first) and, above them, Photos' own picker.
struct PencilPhotoSheet: View {
    /// (11-16: the picture is for a postcard made of it)
    var forCard = false
    var picked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [CameraPhoto] = []
    #if os(iOS)
    @State private var item: PhotosPickerItem?
    #endif
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    #if os(iOS)
                    PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                        Label("从 iPhone 照片里选", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(red: 0.97, green: 0.94, blue: 0.87), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityIdentifier("pencil-photos-picker")
                    Text("只有你选的那几张会给 App，App 不读相册里别的照片。").font(.footnote).foregroundStyle(.white.opacity(0.85))
                    #endif
                    Text("掌机相册").font(.headline).foregroundStyle(.white).padding(.top, 6)
                    if photos.isEmpty {
                        Text("掌机相册里还没有照片：用相机拍几张。").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(photos) { photo in
                                Button { if let data = try? Data(contentsOf: photo.url) { picked(data) } } label: {
                                    PencilThumb(url: photo.url).frame(height: 92).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: photo.name))
                                .accessibilityIdentifier("pencil-album-photo")
                            }
                        }
                    }
                }
                .padding()
            }
            // (its own ground, as the box's other sheets have: the system's is dark in Dark Mode, under words drawn dark)
            .frame(maxWidth: .infinity)
            .background(PencilSheetGround())
            .navigationTitle(forCard ? Text("做一张明信片") : Text("贴一张照片"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task { photos = CameraRoll.list().filter { !$0.isVideo }.sorted { $0.date > $1.date }.prefix(90).map { $0 } }
        #if os(iOS)
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            Task { @MainActor in
                if let data = try? await chosen.loadTransferable(type: Data.self) { picked(data) }
            }
        }
        #endif
    }
}

/// A picture's small copy, read off the main thread.
struct PencilThumb: View {
    var url: URL
    @State private var image: CGImage?
    var body: some View {
        ZStack {
            Color(white: 0.85)
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
        }
        .task(id: url) {
            let url = url
            image = await Task.detached(priority: .userInitiated) { PencilThumb.read(url) }.value
        }
    }
    nonisolated static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 300,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - 游戏笔记

/// The pad's written pages, newest first: one copied onto a note.
struct PencilPadSheet: View {
    var picked: (PencilNote) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sheets: [StickySheet] = []
    var body: some View {
        NavigationStack {
            ScrollView {
                if sheets.isEmpty {
                    Text("游戏笔记里还没有写过的便签。").font(.subheadline).foregroundStyle(.white.opacity(0.85)).padding()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(sheets) { sheet in
                            Button { picked(PencilNote(drawing: sheet.drawing, width: sheet.width, height: sheet.height, text: "", grid: sheet.grid == true)) } label: {
                                PencilPadThumb(sheet: sheet).frame(height: 140)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pencil-pad-sheet")
                        }
                    }
                    .padding()
                }
            }
            // (as wide as the sheet whatever it holds: with no pages yet it was only as wide as its one line)
            .frame(maxWidth: .infinity)
            .background(PencilSheetGround())
            .navigationTitle(Text("贴一页游戏笔记"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task { sheets = Array(StickyPadFiles.load().sheets.filter { $0.strokes > 0 }.reversed()) }
    }
}

struct PencilPadThumb: View {
    var sheet: StickySheet
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(StickyPaper.of(sheet).face)
            #if os(iOS)
            if let drawing = try? PKDrawing(data: sheet.drawing) {
                Image(uiImage: drawing.image(from: CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height), scale: 1))
                    .resizable().scaledToFit().padding(6)
            }
            #endif
        }
        .shadow(color: .black.opacity(0.15), radius: 2, x: 1, y: 2)
    }
}

// MARK: - 镜子 (11-19)

#if os(iOS)
/// The plastic box's mirror, really one: the camera that faces the person looking at the display (the camera
/// program's 内侧 one), its picture running only while the mirror is open. Nothing of it is kept.
final class PencilMirrorCamera: NSObject, ObservableObject, @unchecked Sendable {
    enum State: Equatable { case off, asking, on, refused, blank }
    @Published private(set) var state = State.off
    /// Counts up each time the picture has started running (the glass sets its picture level then).
    @Published private(set) var runs = 0
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?
    private let queue = DispatchQueue(label: "foldarc.pencil.mirror")
    private var wanted = false

    func open() {
        wanted = true
        guard !CameraFeed.usesTestPicture else { state = .blank; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            state = .asking
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.wanted else { return }
                    NSLog("[pencil] the mirror: the camera %@", granted ? "may be used" : "may not be used")
                    if granted { self.start() } else { self.state = .refused }
                }
            }
        default:
            state = .refused
        }
    }

    func close() {
        wanted = false
        guard state != .off else { return }
        state = .off
        let running = session
        queue.async { if running.isRunning { running.stopRunning() } }
        NSLog("[pencil] the mirror shut")
    }

    private func start() {
        guard let device = CameraFeed.device(for: .inner), let input = try? AVCaptureDeviceInput(device: device) else {
            state = .blank
            NSLog("[pencil] the mirror: no camera faces this way")
            return
        }
        self.device = device
        state = .on
        NSLog("[pencil] the mirror open")
        let wanted = session
        queue.async { [weak self] in
            wanted.beginConfiguration()
            for old in wanted.inputs { wanted.removeInput(old) }
            if wanted.canSetSessionPreset(.high) { wanted.sessionPreset = .high }
            if wanted.canAddInput(input) { wanted.addInput(input) }
            wanted.commitConfiguration()
            if !wanted.isRunning { wanted.startRunning() }
            DispatchQueue.main.async { self?.runs += 1 }
        }
    }
}

/// The camera's picture in the mirror's glass: filling it, level however the iPhone is held, and the wrong way
/// round as a mirror's is.
private struct PencilMirrorPicture: UIViewRepresentable {
    @ObservedObject var camera: PencilMirrorCamera
    final class Glass: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var rotation: AVCaptureDevice.RotationCoordinator?
        var watch: NSKeyValueObservation?
        var followed: String?
        func level() {
            guard let connection = preview.connection else { return }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            guard let angle = rotation?.videoRotationAngleForHorizonLevelPreview, connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
    func makeUIView(context: Context) -> Glass {
        let view = Glass()
        view.preview.videoGravity = .resizeAspectFill
        view.preview.session = camera.session
        view.backgroundColor = UIColor(red: 0.79, green: 0.84, blue: 0.87, alpha: 1)
        view.isUserInteractionEnabled = false
        follow(view)
        return view
    }
    func updateUIView(_ view: Glass, context: Context) {
        _ = camera.runs
        follow(view)
        view.level()
    }
    private func follow(_ view: Glass) {
        guard let device = camera.device, view.followed != device.uniqueID else { return }
        view.followed = device.uniqueID
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.preview)
        view.rotation = coordinator
        view.watch = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak view] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { view?.level() } }
        }
    }
}
#endif

/// The plastic box's mirror, over its drawn glass. Shut it is the drawing, as it was; a touch opens it — the
/// camera's picture in the glass, a streak of light over it and the glass's edge — and another shuts it. It
/// shuts by itself when the box is left or the app is.
struct PencilMirrorGlass: View {
    @Binding var open: Bool
    /// Screen points a point of the box's picture.
    var k: Double
    var lit: Bool
    #if os(iOS)
    @StateObject private var camera = PencilMirrorCamera()
    #endif
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PencilMirror.corner * k, style: .continuous)
        return Button { open.toggle() } label: {
            ZStack {
                if open {
                    reflection
                    // (the glass over it)
                    GeometryReader { proxy in
                        Path { path in
                            path.move(to: CGPoint(x: proxy.size.width * 0.2, y: proxy.size.height + 10))
                            path.addLine(to: CGPoint(x: proxy.size.width * 0.62, y: -10))
                        }
                        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 8 * k, lineCap: .round))
                    }
                    .allowsHitTesting(false)
                    shape.strokeBorder(PencilInk.ink.opacity(0.9), lineWidth: max(0.8, 0.9 * k))
                } else {
                    Color.clear
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .overlay { if lit { PencilCursorGlow(shape: shape, s: k) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("镜子"))
        .accessibilityValue(open ? Text("开着") : Text("关着"))
        .accessibilityIdentifier("app.pencil.mirror")
        #if os(iOS)
        .onChange(of: open) { _, now in
            if now { camera.open() } else { camera.close() }
            ConsoleHaptics.shared.play(.smallButton, .press)
        }
        .onChange(of: phase) { _, now in if now != .active { open = false } }
        .onDisappear { camera.close(); open = false }
        #endif
    }

    @ViewBuilder private var reflection: some View {
        #if os(iOS)
        switch camera.state {
        case .on:
            PencilMirrorPicture(camera: camera)
        case .refused:
            ZStack {
                silver
                Text("没有相机权限")
                    .font(.system(size: 9.5 * k, weight: .bold, design: .rounded)).foregroundStyle(PencilInk.ink.opacity(0.8))
                    .multilineTextAlignment(.center).padding(4 * k)
            }
        case .off, .asking, .blank:
            silver
        }
        #else
        silver
        #endif
    }
    /// A mirror with nothing to show: the light of a ceiling in it.
    private var silver: some View {
        LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 0.97), Color(red: 0.71, green: 0.78, blue: 0.83)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 课程表 (11-19)

/// The timetable taken out of the lid, big, to be written on where it lies: a touch on a box and what is typed
/// goes into it (one field nobody sees holds it; the card shows it, and a mark where the next goes); the return
/// key goes on to the lesson under it. Under the card a row of subjects to put in the box with one touch, the
/// box rubbed out, all of them rubbed out. 完成 keeps it; 取消 leaves it as it was.
struct PencilTimetableSheet: View {
    var style: PencilBoxStyle
    var done: () -> Void
    @ObservedObject private var store = PencilBoxStore.shared
    @ObservedObject private var hand = PencilHandFont.shared
    @State private var cells: [String]
    /// The box being written in.
    @State private var chosen: Int?
    @FocusState private var typing: Bool
    private static let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
    private static let pencil = Color(red: 0.33, green: 0.32, blue: 0.35)
    /// The card's own size, in the points its picture draws it with (the big one is this, scaled).
    private static let card = CGSize(width: 214, height: 152)
    private static let subjects = [String(localized: "语文"), String(localized: "数学"), String(localized: "英语"), String(localized: "体育"), String(localized: "音乐"),
                                   String(localized: "美术"), String(localized: "自然"), String(localized: "劳动"), String(localized: "自习")]

    init(style: PencilBoxStyle, done: @escaping () -> Void) {
        self.style = style
        self.done = done
        _cells = State(initialValue: PencilTimetable.whole(PencilBoxStore.shared.lessons(in: style)))
    }

    /// The colours each box's card is printed in: its title and days, its lines.
    private var colours: (title: Color, lines: Color) {
        switch style {
        case .tin: return (Color(red: 0.42, green: 0.54, blue: 0.35), Color(red: 0.56, green: 0.69, blue: 0.54))
        case .plastic: return (Color(red: 0.69, green: 0.31, blue: 0.25), Color(red: 0.88, green: 0.65, blue: 0.60))
        case .wood: return (Color(red: 0.31, green: 0.48, blue: 0.61), Color(red: 0.62, green: 0.71, blue: 0.79))
        case .canvas: return (Color(red: 0.24, green: 0.36, blue: 0.49), Color(red: 0.62, green: 0.70, blue: 0.78))
        }
    }
    private var typed: Binding<String> {
        Binding(get: { chosen.map { cells[$0] } ?? "" },
                set: { new in if let chosen { cells[chosen] = PencilTimetable.held(new) } })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PencilSheetGround()
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            card(width: min(proxy.size.width - 28, 540))
                            Text("点一格，直接写在里面；按换行写下一节。")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                                .multilineTextAlignment(.center).padding(.horizontal, 18)
                            chips
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14).padding(.bottom, 24)
                        // (a touch beside the card and the buttons: the keyboard away)
                        .contentShape(Rectangle())
                        .onTapGesture { typing = false }
                    }
                }
            }
            .navigationTitle(Text("课程表"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { typing = false; done() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        typing = false
                        store.setTimetable(cells)
                        ConsoleSounds.shared.play(.click)
                        done()
                    }
                    .accessibilityIdentifier("pencil-timetable-done")
                }
            }
            .onAppear { hand.ensure(.notes) }
        }
    }

    private func choose(_ index: Int) {
        chosen = index
        typing = true
    }
    /// On to the box written in next (after the last, the keyboard is put away).
    private func goOn() {
        guard let chosen else { return }
        if let next = PencilTimetable.next(after: chosen) {
            self.chosen = next
        } else {
            self.chosen = nil
            typing = false
        }
    }

    private func card(width: Double) -> some View {
        let s = width / Self.card.width, height = Self.card.height * s
        let place = PencilTimetable.Place(card: CGRect(origin: .zero, size: Self.card))
        let printed = colours
        let shape = RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Self.paper)
            shape.strokeBorder(PencilInk.ink.opacity(0.85), lineWidth: max(1, 0.7 * s))
            Text(verbatim: "课 程 表")
                .font(.system(size: 12 * s, weight: .bold)).foregroundStyle(printed.title)
                .position(x: width / 2, y: 18 * s)
                .accessibilityHidden(true)
            Path { path in
                for column in 0...PencilTimetable.days {
                    let x = (place.grid.x + place.cell.width * Double(column)) * s
                    path.move(to: CGPoint(x: x, y: place.grid.y * s))
                    path.addLine(to: CGPoint(x: x, y: (place.grid.y + place.cell.height * Double(PencilTimetable.lessons + 1)) * s))
                }
                for row in 0...(PencilTimetable.lessons + 1) {
                    let y = (place.grid.y + place.cell.height * Double(row)) * s
                    path.move(to: CGPoint(x: place.grid.x * s, y: y))
                    path.addLine(to: CGPoint(x: (place.grid.x + place.cell.width * Double(PencilTimetable.days)) * s, y: y))
                }
            }
            .stroke(printed.lines, lineWidth: max(0.8, 0.6 * s))
            .accessibilityHidden(true)
            ForEach(0..<PencilTimetable.days, id: \.self) { day in
                Text(verbatim: PencilTimetable.dayNames[day])
                    .font(.system(size: 9 * s, weight: .semibold)).foregroundStyle(printed.title)
                    .position(x: (place.grid.x + place.cell.width * (Double(day) + 0.5)) * s, y: (place.grid.y + place.cell.height / 2) * s)
                    .accessibilityHidden(true)
            }
            ForEach(0..<PencilTimetable.count, id: \.self) { index in
                box(index, place: place, s: s)
            }
            // (what is typed goes into this; nothing of it is seen, and no touch reaches it)
            TextField("", text: typed)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .foregroundStyle(.clear)
                .tint(.clear)
                .focused($typing)
                .onSubmit {
                    goOn()
                    // (the return key puts the keyboard away: it is wanted again for the next box)
                    if chosen != nil { DispatchQueue.main.async { typing = true } }
                }
                .frame(width: place.cell.width * s, height: place.cell.height * s)
                .position(x: PencilTimetable.middle(place, index: chosen ?? 0).x * s, y: PencilTimetable.middle(place, index: chosen ?? 0).y * s)
                .allowsHitTesting(false)
                .accessibilityLabel(Text("课程表"))
                .accessibilityIdentifier("pencil-timetable-field")
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 7, x: 2, y: 5)
    }

    /// One box of the card: what is written in it, the mark where the next goes when it is the one written in.
    private func box(_ index: Int, place: PencilTimetable.Place, s: Double) -> some View {
        let at = PencilTimetable.middle(place, index: index)
        let day = index % PencilTimetable.days, lesson = index / PencilTimetable.days
        return Button { choose(index) } label: {
            HStack(spacing: 0.6 * s) {
                Text(verbatim: cells[index])
                    .font(hand.font(.notes, size: 10.5 * s)).foregroundStyle(Self.pencil)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if chosen == index {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Rectangle().fill(PencilInk.tealDeep)
                            .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.12)
                    }
                    .frame(width: max(1.5, 0.5 * s), height: place.cell.height * 0.66 * s)
                }
            }
            .frame(width: (place.cell.width - 2) * s, height: (place.cell.height - 1) * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: at.x * s, y: at.y * s)
        .accessibilityLabel(Text("星期\(PencilTimetable.dayNames[day])，第 \(lesson + 1) 节"))
        .accessibilityValue(Text(verbatim: cells[index]))
        .accessibilityAddTraits(chosen == index ? .isSelected : [])
        .accessibilityIdentifier("pencil-timetable-\(day)-\(lesson)")
    }

    /// Under the card: a subject put into the box being written in (then on to the next), that box rubbed out,
    /// all of them rubbed out.
    private var chips: some View {
        let columns = [GridItem(.adaptive(minimum: 68), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(Self.subjects.enumerated()), id: \.offset) { place, subject in
                chip(Text(verbatim: subject), name: "pencil-timetable-subject-\(place)") {
                    let index = chosen ?? cells.firstIndex(where: \.isEmpty) ?? 0
                    cells[index] = subject
                    chosen = index
                    goOn()
                    ConsoleSounds.shared.play(.click)
                }
            }
            chip(Text("擦掉这一格"), name: "pencil-timetable-rub") {
                if let chosen { cells[chosen] = ""; ConsoleSounds.shared.play(.back) }
            }
            .disabled(chosen == nil)
            .opacity(chosen == nil ? 0.5 : 1)
            chip(Text("全部擦掉"), name: "pencil-timetable-rub-all") {
                cells = Array(repeating: "", count: PencilTimetable.count)
                ConsoleSounds.shared.play(.back)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 540)
    }
    private func chip(_ title: Text, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(PencilInk.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(PencilInk.paper))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(name)
    }
}

// MARK: - 明信片: the tin and the big postcard

/// 11-17, 明信片's sheet. A little tin with every postcard standing in it, a blank one in front of them; the one
/// touched is taken out and shown big (PencilBigCard): looked at on both sides, given a picture, written on.
/// Opened for one postcard (held in its slot, or on the cover), it shows that one big at once, its back up.
struct PencilCardDesk: View {
    enum Start: Equatable { case tin, card(UUID) }
    var start: Start
    /// The postcards, in the order the box has them.
    var cards: [PencilPiece] = []
    /// Shut: the postcard the pile is to turn to (nil: none).
    var done: (UUID?) -> Void
    /// 11-22: opened by a touch on the postcode or the lines of the postcard on the lid: written there first.
    var writeFirst: PencilBigCard.Field?
    @ObservedObject private var store = PencilBoxStore.shared
    @State private var out: UUID?
    /// The one out was made just now, of nothing yet (given up, or left with nothing on it, it is thrown away).
    @State private var made = false
    /// The one touched in the tin, on its way out.
    @State private var lifted: UUID?

    init(start: Start, cards: [PencilPiece] = [], writeFirst: PencilBigCard.Field? = nil, done: @escaping (UUID?) -> Void) {
        self.start = start
        self.cards = cards
        self.writeFirst = writeFirst
        self.done = done
        if case .card(let id) = start { _out = State(initialValue: id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PencilSheetGround()
                if let out {
                    PencilBigCard(id: out, backFirst: start != .tin, made: made, toTin: start == .tin ? backToTin : nil,
                                  writeFirst: start == .tin ? nil : writeFirst, done: { kept in done(kept ? out : nil) })
                        .id(out)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    PencilCardTin(cards: cards, onLid: Set(store.lid.map(\.id)), lifted: lifted, take: take, make: make)
                        .transition(.opacity)
                        .navigationTitle(Text("明信片"))
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { done(nil) } } }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// The big postcard put back: the tin again.
    private func backToTin(_ kept: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { out = nil; made = false; lifted = nil }
    }
    /// One touched in the tin: it rises a little, and is out.
    private func take(_ id: UUID) {
        guard lifted == nil else { return }
        ConsoleSounds.shared.play(.cardFlip)
        ConsoleHaptics.shared.play(.smallButton, .press)
        withAnimation(.easeOut(duration: 0.16)) { lifted = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            withAnimation(.easeOut(duration: 0.22)) { made = false; out = id }
        }
    }
    /// The blank one in front: a new postcard, nothing on it yet.
    private func make() {
        guard lifted == nil, let id = store.addBlankCard() else { return }
        ConsoleSounds.shared.play(.cardFlip)
        ConsoleHaptics.shared.play(.smallButton, .press)
        withAnimation(.easeOut(duration: 0.22)) { made = true; out = id }
    }
}

/// The postcards' tin (PencilCardTinLayout): its lid open behind, the postcards standing in a row, each showing
/// its top over the one in front; in front of them all a blank one, a new one's place; the tin's front wall over
/// their feet.
struct PencilCardTin: View {
    var cards: [PencilPiece]
    var onLid: Set<UUID>
    var lifted: UUID?
    var take: (UUID) -> Void
    var make: () -> Void
    private static let ink = Color(red: 0.23, green: 0.17, blue: 0.14)
    private static let teal = Color(red: 0.17, green: 0.37, blue: 0.34)
    /// A postcard with nothing on it (the place of a new one).
    private static let blank = PencilPiece(id: UUID(), kind: .postcard, x: 0.5, y: 0.5, angle: 0, scale: 1, z: 0, magnet: nil)

    var body: some View {
        GeometryReader { proxy in
            let size = PencilCardTinLayout.size
            let k = max(0.6, min(1.7, min((proxy.size.width - 24) / size.width, (proxy.size.height - 86) / size.height)))
            ScrollView {
                VStack(spacing: 12) {
                    tin(k)
                    Text("点一张，抽出来看；最前面空白的那张是新做一张。")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center).padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
    }

    private func tin(_ k: Double) -> some View {
        let size = PencilCardTinLayout.size, count = cards.count
        let head = PencilCardTinLayout.headroom(count: count)
        // (index 0, the first the box has, stands nearest the front, just behind the blank one)
        let row = Array(cards.reversed().enumerated())
        let wall = size.height - PencilCardTinLayout.rim
        return ZStack(alignment: .topLeading) {
            PencilImages.image("pencilbox-cardtin-back.png").resizable()
                .frame(width: size.width * k, height: size.height * k)
                .position(x: size.width / 2 * k, y: (head + size.height / 2) * k)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ForEach(row, id: \.element.id) { place, piece in
                standing(piece, place: place, name: cards.count - 1 - place, head: head, k: k)
            }
            standing(Self.blank, place: count, name: nil, head: head, k: k)
            // (its front wall, over the cards' feet; no touch goes through it to them)
            PencilImages.image("pencilbox-cardtin-front.png").resizable()
                .frame(width: size.width * k, height: size.height * k)
                .position(x: size.width / 2 * k, y: (head + size.height / 2) * k)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: size.width * k, height: wall * k)
                .contentShape(Rectangle())
                .onTapGesture { }
                .position(x: size.width / 2 * k, y: (head + PencilCardTinLayout.rim + wall / 2) * k)
                .accessibilityHidden(true)
        }
        .frame(width: size.width * k, height: (size.height + head) * k, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 9 * k, x: 3 * k, y: 6 * k)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pencil-cardtin")
    }

    /// One postcard standing in the tin (`name`: which of the box's it is; nil, the blank one).
    private func standing(_ piece: PencilPiece, place: Int, name: Int?, head: Double, k: Double) -> some View {
        let at = PencilCardTinLayout.place(place, count: cards.count)
        let face = CGSize(width: PencilCard.face.width * at.scale * k, height: PencilCard.face.height * at.scale * k)
        // (what is touched is what shows of it: its top, down to the one in front, or to the tin's rim; the rest
        // of its picture hangs below, behind them)
        let strip = PencilCardTinLayout.shows(place, count: cards.count) * k
        let hang = (face.height - strip) / 2
        let art = piece.art
        var shown = piece
        shown.back = nil
        let rise = lifted == piece.id ? -46.0 * k : 0
        return Button { if name == nil { make() } else { take(piece.id) } } label: {
            ZStack {
                PencilPieceView(piece: shown, u: k, scale: at.scale, layer: .shadow, magnets: false)
                    .offset(x: art.shadow.width * k * at.scale, y: hang + art.shadow.height * k * at.scale)
                PencilPieceView(piece: shown, u: k, scale: at.scale, layer: .face, magnets: false)
                    .offset(y: hang)
                if name == nil {
                    Label("新做一张", systemImage: "plus")
                        .font(.system(size: 13 * k, weight: .heavy, design: .rounded)).foregroundStyle(Self.teal)
                        .offset(y: -strip / 2 + 20 * k)
                } else if onLid.contains(piece.id) {
                    Text("在盒盖上")
                        .font(.system(size: 8.5 * k, weight: .heavy, design: .rounded)).foregroundStyle(Self.ink)
                        .padding(.horizontal, 5 * k).padding(.vertical, 1.5 * k)
                        .background(Color(red: 0.97, green: 0.94, blue: 0.87), in: Capsule())
                        .offset(x: face.width / 2 - 30 * k, y: -strip / 2 + 11 * k)
                }
            }
            .frame(width: face.width, height: strip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: rise)
        .position(x: at.middle.x * k, y: (at.top + head) * k + strip / 2)
        .accessibilityLabel(Text(verbatim: name == nil ? String(localized: "新做一张") : piece.fullTitle))
        .accessibilityValue(Text(verbatim: onLid.contains(piece.id) ? String(localized: "盒盖上") : ""))
        .accessibilityIdentifier(name.map { "pencil-cards-\($0)" } ?? "pencil-cards-new")
    }
}

/// 11-17: a postcard taken out and shown big. Its picture side: a touch turns it over (one made here with no
/// picture yet has 添加照片 in its middle); under it, a new picture for it, onto the lid or back off it, thrown
/// away (one made here). Its back is written on where it lies: a touch on the postcode's boxes or on the lines
/// and what is typed goes straight into them (two fields nobody sees hold it; the card shows it, and a mark
/// where the next goes); a touch on the stamp goes to the stamps under the card (another scenery's, a picture of
/// one's own); a touch anywhere else puts the keyboard away, or turns the card back. 11-22: the postcode's whole
/// row and the whole right part under the stamp take the touch (PencilCard.part); opened to be written on, the
/// keyboard comes up at once, on the part touched on the lid (`writeFirst`) or on the lines.
struct PencilBigCard: View {
    var id: UUID
    var backFirst = false
    /// Opened by a touch on the postcode or on the lines of the postcard on the lid: written there first.
    var writeFirst: Field?
    /// Made just now: given up, or left with nothing on it, it is thrown away.
    var made = false
    /// Back to the tin it came out of (nil: it was opened by itself); `true`: the postcard is still there.
    var toTin: ((Bool) -> Void)?
    /// Finished with (`true`: the postcard is there, to be turned to in its slot).
    var done: (Bool) -> Void
    @ObservedObject private var store = PencilBoxStore.shared
    @State private var back: Bool
    /// Half way over (squeezed to its edge).
    @State private var turning = false
    @State private var words: String
    @State private var postcode: String
    @State private var choosingStamp = false
    @State private var choosingPhoto = false
    @State private var stampsLit = false
    @State private var discarding = false
    @State private var said: String?
    /// The three lines are full: said for a moment.
    @State private var full = false
    /// 11-22: its own picture being dragged and pinched on its front (PencilCardPlace).
    @GestureState private var moving: CGSize = .zero
    @GestureState private var pinching: Double = 1
    @FocusState private var focus: Field?
    #if os(iOS)
    /// The keyboard on the screen (its own notes say).
    @State private var keyboardUp = false
    #endif
    @ObservedObject private var hand = PencilHandFont.shared
    enum Field { case postcode, words }
    private static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
    private static let ink = Color(red: 0.23, green: 0.17, blue: 0.14)
    private static let tealDeep = Color(red: 0.17, green: 0.37, blue: 0.34)

    init(id: UUID, backFirst: Bool = false, made: Bool = false, toTin: ((Bool) -> Void)? = nil, writeFirst: Field? = nil,
         done: @escaping (Bool) -> Void) {
        self.id = id
        self.backFirst = backFirst
        self.writeFirst = writeFirst
        self.made = made
        self.toTin = toTin
        self.done = done
        let piece = PencilBoxStore.shared.piece(id)
        _back = State(initialValue: backFirst)
        _words = State(initialValue: piece?.words ?? "")
        _postcode = State(initialValue: piece?.postcode ?? "")
    }

    /// The postcard as it will be: the side that is up, what is typed on its back.
    private var shown: PencilPiece? {
        guard var piece = store.piece(id) else { return nil }
        let held = PencilCard.held(words), digits = PencilCard.digits(postcode)
        piece.back = back ? true : nil
        piece.words = held.isEmpty ? nil : held
        piece.postcode = digits.isEmpty ? nil : digits
        return piece
    }
    private var onLid: Bool { store.lid.contains { $0.id == id } }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 14) {
                        if let piece = shown {
                            card(piece, width: min(proxy.size.width - 28, 500)) {
                                focus = nil
                                withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo("stamps", anchor: .bottom); stampsLit = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { withAnimation(.easeOut(duration: 0.4)) { stampsLit = false } }
                            }
                            // (11-23: how to use it, only on a new console the first time: OnceHintView)
                            if back {
                                OnceHintView("postcard-back") { Text("点横线或邮编的格子，直接写在明信片上；点邮票换一张；点别处翻回正面。").modifier(Hint()) }
                                if full {
                                    Text("三条横线写满了，后面的字不会写上去。").modifier(Hint())
                                }
                                stamps.id("stamps")
                            } else {
                                if piece.isMadeCard && piece.ownFront != true {
                                    OnceHintView("postcard-add-photo") { Text("点中间的按钮添加照片；点别处翻到背面。").modifier(Hint()) }
                                } else if piece.ownFront == true {
                                    OnceHintView("postcard-crop") { Text("在明信片上拖动照片，挑露出来的部分（两指可以放大）；点一下翻到背面。").modifier(Hint()) }
                                } else {
                                    OnceHintView("postcard-flip") { Text("点一下明信片，翻到背面。").modifier(Hint()) }
                                }
                                actions(piece)
                            }
                            if let said {
                                Text(verbatim: said).modifier(Hint())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14).padding(.bottom, 24)
                }
            }
        }
        // (what is typed is kept to what the card holds: six digits; the three lines' worth of words)
        .onChange(of: postcode) { _, typed in
            let kept = PencilCard.digits(typed)
            if kept != typed { postcode = kept }
        }
        .onChange(of: words) { _, typed in
            let kept = PencilCard.held(typed)
            guard kept != typed else { return }
            words = kept
            withAnimation(.easeOut(duration: 0.15)) { full = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation(.easeOut(duration: 0.3)) { full = false } }
        }
        .onAppear {
            hand.ensure(.notes)
            // Opened to be written on (写字, 写背面, a touch on the card on the lid): the keyboard comes up at once,
            // on the part touched there, else on the lines, as a note's 写字 does.
            // Asked for once the sheet has come up (asked for while it was still coming, on the phone the focus was
            // kept but the text field never took it: the mark where the words go, and no keyboard); asked for again
            // if the keyboard has not come by then.
            if backFirst {
                let first = writeFirst ?? .words
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if back, focus == nil { write(first) } }
                #if os(iOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if back, focus == first, !keyboardUp { write(first) } }
                #endif
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardUp = false }
        #endif
        #if DEBUG && os(iOS)
        // 11-23: on the phone the keyboard does not come for a postcard opened from the lid: what the focus, the text
        // fields and the keyboard do, into the trace and the log (nothing of what is written).
        .onChange(of: focus) { _, now in keyboardTrace("focus is now " + (now == nil ? "nil" : String(describing: now!))) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            keyboardTrace("the keyboard will show at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in keyboardTrace("the keyboard did show") }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardTrace("the keyboard did hide") }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in keyboardTrace("a text field began editing") }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in keyboardTrace("a text view began editing") }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in keyboardTrace("a text field ended editing") }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in keyboardTrace("a text view ended editing") }
        #endif
        .navigationTitle(back ? Text("明信片背面") : Text("明信片正面"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let toTin {
                    Button { toTin(leave(keeping: true)) } label: { Label("铁盒", systemImage: "chevron.backward").labelStyle(.titleAndIcon) }
                        .accessibilityIdentifier("pencil-bigcard-tin")
                } else {
                    Button("取消") { done(leave(keeping: false)) }
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("完成") { done(leave(keeping: true)) }.accessibilityIdentifier("pencil-card-done") }
        }
        .overlay {
            if choosingStamp, let piece = store.piece(id) {
                PencilPhotoSwap(piece: piece, target: .stamp) { withAnimation(.easeOut(duration: 0.15)) { choosingStamp = false } }
            }
        }
        .sheet(isPresented: $choosingPhoto) {
            PencilPhotoSheet(forCard: true) { data in
                choosingPhoto = false
                if store.setCardFront(id, picture: data) {
                    ConsoleSounds.shared.play(.click)
                    said = nil
                } else {
                    said = String(localized: "这张照片读不出来")
                }
            }
        }
        .confirmationDialog(Text("扔掉这张明信片？"), isPresented: $discarding, titleVisibility: .visible) {
            Button("扔掉", role: .destructive) {
                store.discard(id)
                ConsoleSounds.shared.play(.back)
                if let toTin { toTin(false) } else { done(false) }
            }
            Button("留着", role: .cancel) { }
        }
    }

    private struct Hint: ViewModifier {
        func body(content: Content) -> some View {
            content.font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center).padding(.horizontal, 18)
        }
    }

    /// Leaving it: what is typed is written on its back (`keeping`), or left as it was; one made just now with
    /// nothing on it, or given up, is thrown away. True: the postcard is still there.
    private func leave(keeping: Bool) -> Bool {
        focus = nil
        if keeping { store.write(card: id, words: words, postcode: postcode) }
        if made, !keeping || store.piece(id)?.isBlankCard == true {
            store.discard(id)
            return false
        }
        if keeping { ConsoleSounds.shared.play(.click) }
        return store.piece(id) != nil
    }

    /// A touch on the card, at a point of it (its middle at 0, 0, in a lid's points): on its back the postcode's
    /// row, the lines or the stamp (PencilCard.part); anywhere else the keyboard put away, or the card turned over.
    private func touched(_ point: CGPoint, stampTouched: () -> Void) {
        switch back ? PencilCard.part(at: point) : .none {
        case .postcode: write(.postcode)
        case .lines: write(.words)
        case .stamp: stampTouched()
        case .none: if focus != nil { focus = nil } else { flip() }
        }
    }

    /// The keyboard asked for, at `field`. A focus that is already there but has no keyboard (the text field never
    /// took it) does not change by being asked for again: it is let go of first and asked for on the next turn.
    private func write(_ field: Field) {
        #if DEBUG && os(iOS)
        keyboardTrace("asked for \(field)")
        #endif
        #if os(iOS)
        if focus == field, !keyboardUp {
            focus = nil
            DispatchQueue.main.async { focus = field }
            return
        }
        #endif
        focus = field
    }
    #if DEBUG && os(iOS)
    /// One line about the keyboard: the focus, whether the keyboard is up, a hardware keyboard joined to the phone,
    /// the key window's screen and its scene's state.
    private func keyboardTrace(_ what: String) {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows: [UIWindow] = scenes.flatMap { $0.windows }
        let key: UIWindow? = windows.first { $0.isKeyWindow }
        var keyText = "none"
        if let key, let scene = key.windowScene {
            keyText = "\(Int(scene.screen.bounds.width))x\(Int(scene.screen.bounds.height)) state \(scene.activationState.rawValue)"
        }
        let focusText: String = focus == nil ? "nil" : String(describing: focus!)
        let upText = keyboardUp ? "up" : "down"
        let hardText = GCKeyboard.coalesced == nil ? "none" : "joined"
        let line = "[keyboard] \(what) · focus \(focusText) · on-screen keyboard \(upText) · hardware keyboard \(hardText) · key window \(keyText) · windows \(windows.count)"
        NSLog("%@", line)
        OrientationTrace.shared.event(line)
    }
    #endif

    private func flip() {
        guard !turning else { return }
        focus = nil
        withAnimation(.easeIn(duration: 0.11)) { turning = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            back.toggle()
            withAnimation(.easeOut(duration: 0.14)) { turning = false }
        }
        ConsoleSounds.shared.play(.cardFlip)
        ConsoleHaptics.shared.play(.smallButton, .press)
    }

    /// The mark where the next that is typed goes: a thin bar, coming and going.
    private func caret(height: Double, k: Double) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Rectangle().fill(Self.tealDeep)
                .frame(width: max(1.5, 0.45 * k), height: height)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.12)
        }
        .frame(width: max(1.5, 0.45 * k), height: height)
        .accessibilityHidden(true)
    }

    private func card(_ piece: PencilPiece, width: Double, stampTouched: @escaping () -> Void) -> some View {
        let art = piece.art, k = width / art.size.width
        let first = PencilCard.box(0), last = PencilCard.box(PencilCard.boxes - 1)
        let top = PencilCard.lineYs[0] - 10, bottom = PencilCard.lineYs[PencilCard.lineYs.count - 1] + 3
        let blank = piece.isMadeCard && piece.ownFront != true
        let boxesSize = CGSize(width: (last.x - first.x + PencilCard.boxSide + 4) * k, height: (PencilCard.boxSide + 6) * k)
        let boxesAt = CGSize(width: (first.x + last.x) / 2 * k, height: first.y * k)
        let linesSize = CGSize(width: (PencilCard.lineLength + 6) * k, height: (bottom - top) * k)
        let linesAt = CGSize(width: (PencilCard.lineStart + PencilCard.lineLength / 2) * k, height: (top + bottom) / 2 * k)
        // where the next digit goes, and the next word: the line the words have come to, and what is on it
        let digits = PencilCard.digits(postcode).count
        let written = PencilCard.held(words), lines = PencilCard.lines(of: written)
        let endsLine = written.last?.isNewline == true
        let reached = endsLine ? lines.count : max(0, lines.count - 1)
        let line = min(PencilCard.lineYs.count - 1, reached)
        let onLine = line < lines.count ? lines[line] : ""
        return ZStack {
            PencilPieceView(piece: piece, u: 1, scale: k, layer: .shadow, magnets: false).offset(x: art.shadow.width * k, y: art.shadow.height * k)
                .accessibilityHidden(true)
            PencilPieceView(piece: piece, u: 1, scale: k, layer: .face, magnets: false)
                .accessibilityHidden(true)
            #if os(iOS)
            // (its own picture while a finger drags or pinches it: drawn from the picture as it was given)
            if !back, piece.ownFront == true, moving != .zero || pinching != 1, let source = store.cardSource(piece.id) {
                livePicture(source, piece: piece, k: k)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            #endif
            // (anywhere a touch has nothing of its own: the keyboard put away, or the card turned over; 11-22: on a
            // front with a picture of one's own, a drag or a pinch places the picture)
            Color.clear.contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    // (the point on the card: its middle at 0, 0, in a lid's points)
                    let w = Double(art.size.width) * k, h = Double(art.size.height) * k
                    let at = CGPoint(x: (Double(value.location.x) - w / 2) / k, y: (Double(value.location.y) - h / 2) / k)
                    touched(at, stampTouched: stampTouched)
                })
                #if os(iOS)
                .gesture(placing(piece, k: k), including: !back && piece.ownFront == true ? .all : .subviews)
                #endif
                .accessibilityElement()
                .accessibilityLabel(back ? Text("明信片背面") : Text("明信片正面"))
                .accessibilityValue(Text(verbatim: back ? [piece.postcode ?? "", piece.words ?? ""].filter { !$0.isEmpty }.joined(separator: "，") : piece.cardName))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: back ? Text("翻到正面") : Text("翻到背面")) { flip() }
                #if os(iOS)
                .modifier(PencilPlaceActions(on: !back && piece.ownFront == true) { dx, dy, closer in
                    let window = PencilCard.frontWindow
                    place(piece.id, moved: CGSize(width: dx * window.width * k * 0.12, height: dy * window.height * k * 0.12), pinched: closer, k: k)
                })
                #endif
                .accessibilityIdentifier(back ? "pencil-card-back" : "pencil-card-front")
            #if DEBUG
            // (for the UI tests: where its own picture sits)
            if !back, piece.ownFront == true {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("pencil-card-place")
                    .accessibilityValue(Text(verbatim: (piece.frontPlace ?? PencilCardPlace.middle).map { String(format: "%.2f", $0) }.joined(separator: " ")))
                    .allowsHitTesting(false)
            }
            #endif
            if back {
                // being written on: the mark where the next goes (the paper itself stays as it is everywhere)
                if focus == .postcode {
                    caret(height: 6.2 * k, k: k)
                        .offset(x: (digits < PencilCard.boxes ? PencilCard.box(digits).x : last.x + 2.7) * k, y: first.y * k)
                }
                if focus == .words {
                    HStack(alignment: .bottom, spacing: 0.6 * k) {
                        Text(verbatim: onLine).font(hand.font(.notes, size: PencilCard.wordSize * k)).lineLimit(1).hidden()
                        caret(height: 7.4 * k, k: k)
                    }
                    .frame(width: PencilCard.lineLength * k, height: 10 * k, alignment: .bottomLeading)
                    .offset(x: (PencilCard.lineStart + PencilCard.lineLength / 2) * k, y: (PencilCard.lineYs[line] - 5.4) * k)
                    .allowsHitTesting(false)
                }
                // what is typed goes into these two; nothing of them is seen (the card shows it), and no touch
                // reaches them (the card's own touch takes it, so the typing always goes on at the end)
                TextField("", text: $postcode)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textFieldStyle(.plain)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .focused($focus, equals: .postcode)
                    .frame(width: boxesSize.width, height: boxesSize.height)
                    .offset(boxesAt)
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text("邮编"))
                    .accessibilityIdentifier("pencil-card-postcode")
                TextField("", text: $words, axis: .vertical)
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .focused($focus, equals: .words)
                    .frame(width: linesSize.width, height: linesSize.height)
                    .offset(linesAt)
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text("横线上"))
                    .accessibilityIdentifier("pencil-card-words")
            } else if blank {
                Button { choosingPhoto = true } label: {
                    Label("添加照片", systemImage: "plus")
                        .font(.system(size: max(15, 6.4 * k), weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, max(16, 7 * k)).frame(minHeight: max(44, 15 * k))
                        .background(Capsule().fill(Color(red: 0.25, green: 0.52, blue: 0.48)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pencil-bigcard-add")
            }
        }
        .frame(width: art.size.width * k, height: art.size.height * k)
        .scaleEffect(x: turning ? 0.04 : 1, y: 1)
        // (a drag down on the picture moves the picture, not the sheet)
        .interactiveDismissDisabled(!back && piece.ownFront == true)
    }

    #if os(iOS)
    /// 11-22: a drag or a pinch on the front places its own picture; when the finger lifts the window's part is
    /// cut again (PencilBoxStore.placeCardFront). Each counts for itself, so a drag and a pinch at once both hold.
    private func placing(_ piece: PencilPiece, k: Double) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 6)
                .updating($moving) { value, state, _ in state = value.translation }
                .onEnded { value in place(piece.id, moved: value.translation, pinched: 1, k: k) },
            MagnifyGesture()
                .updating($pinching) { value, state, _ in state = Double(value.magnification) }
                .onEnded { value in place(piece.id, moved: .zero, pinched: Double(value.magnification), k: k) }
        )
    }
    private func place(_ id: UUID, moved: CGSize, pinched: Double, k: Double) {
        guard let card = store.piece(id), let source = store.cardSource(id) else { return }
        let window = PencilCard.frontWindow
        let place = PencilCardPlace.moved(card.frontPlace, size: source.size, window: CGSize(width: window.width * k, height: window.height * k),
                                          moved: moved, pinched: pinched)
        store.placeCardFront(id, place: place)
    }
    /// The picture as it sits while it is dragged or pinched, in the front's window.
    private func livePicture(_ source: UIImage, piece: PencilPiece, k: Double) -> some View {
        let window = PencilCard.frontWindow
        let size = CGSize(width: window.width * k, height: window.height * k)
        let place = PencilCardPlace.moved(piece.frontPlace, size: source.size, window: size, moved: moving, pinched: pinching)
        let part = PencilCardPlace.part(of: source.size, place: place)
        let s = size.width / max(1, part.width)
        return Image(uiImage: source).resizable()
            .frame(width: source.size.width * s, height: source.size.height * s)
            .offset(x: (source.size.width / 2 - part.midX) * s, y: (source.size.height / 2 - part.midY) * s)
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(Rectangle().strokeBorder(PencilCardBack.line, lineWidth: max(0.5, 0.45 * k)))
            .offset(x: window.midX * k, y: window.midY * k)
    }
    #endif

    /// Under its picture side: what can be done with it.
    private func actions(_ piece: PencilPiece) -> some View {
        let blank = piece.isMadeCard && piece.ownFront != true
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                if !blank {
                    chip("换照片", symbol: "photo.on.rectangle.angled", name: "pencil-bigcard-photo") { choosingPhoto = true }
                }
                if piece.ownFront == true, !piece.isMadeCard {
                    chip("换回原来的风景", symbol: "arrow.uturn.backward", name: "pencil-bigcard-scenery") { store.clearCardFront(id); ConsoleSounds.shared.play(.click) }
                }
                chip("翻到背面", symbol: "arrow.left.arrow.right", name: "pencil-bigcard-turn") { flip() }
            }
            HStack(spacing: 10) {
                if onLid {
                    chip("拿回铅笔盒", symbol: "tray.and.arrow.down", name: "pencil-bigcard-lid") { store.takeOff(id); ConsoleSounds.shared.play(.back) }
                } else {
                    chip("贴到盒盖上", symbol: "pin", name: "pencil-bigcard-lid") { store.stick(id); ConsoleSounds.shared.play(.magnet) }
                }
                if piece.isMadeCard {
                    chip("扔掉", symbol: "trash", name: "pencil-bigcard-discard") { discarding = true }
                }
            }
        }
        .padding(.horizontal, 14)
    }
    private func chip(_ title: LocalizedStringKey, symbol: String, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Self.ink)
                .padding(.horizontal, 14).frame(minHeight: 42)
                .background(Capsule().fill(Self.paper))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(name)
    }

    private var stamps: some View {
        let piece = store.piece(id)
        let current: FrameScene? = piece?.ownStamp == true ? nil : (piece?.stampScene ?? piece?.scene)
        return VStack(alignment: .leading, spacing: 8) {
            Text("邮票").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
            HStack(spacing: 10) {
                ForEach(FrameScene.allCases) { scene in
                    Button {
                        store.setStamp(id, scene: scene)
                        ConsoleSounds.shared.play(.click)
                    } label: {
                        PencilStampPicture(id: id, own: false, scene: scene, k: 1.9, revision: store.revision)
                            .padding(4)
                            .background(Self.paper)
                            .overlay(alignment: .bottomTrailing) { if current == scene { chosenMark } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: scene.title))
                    .accessibilityAddTraits(current == scene ? .isSelected : [])
                    .accessibilityIdentifier("pencil-card-stamp-\(scene.rawValue)")
                }
                Button { focus = nil; withAnimation(.easeOut(duration: 0.15)) { choosingStamp = true } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 17, weight: .semibold)).accessibilityHidden(true)
                        Text("自己的照片").font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Self.ink)
                    .frame(width: PencilCard.stampPicture.width * 1.9 + 22, height: PencilCard.stampPicture.height * 1.9 + 8)
                    .background(Self.paper)
                    .overlay(alignment: .bottomTrailing) { if piece?.ownStamp == true { chosenMark } }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pencil-card-stamp-own")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .frame(maxWidth: 480, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(stampsLit ? 0.22 : 0)).padding(.horizontal, 8))
    }
    /// The stamp that is on the card now: a small tick at its corner.
    private var chosenMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white, Self.tealDeep)
            .offset(x: 5, y: 5)
            .accessibilityHidden(true)
    }
}

// MARK: - 写便条

/// A note written with a finger or Apple Pencil, or typed in the
/// handwriting typeface; squared paper once the tin has it.
struct PencilNoteEditor: View {
    var id: UUID?
    /// 11-15: opened on the cover (no Apple Pencil there): typing at once.
    var typingFirst = false
    var done: () -> Void
    @ObservedObject private var store = PencilBoxStore.shared
    @ObservedObject private var hand = PencilHandFont.shared
    @State private var text = ""
    @State private var grid = false
    @State private var tool: Tool = .pencil
    @State private var typing = false
    @State private var face: PencilHand = .notes
    @FocusState private var typingFocus: Bool
    #if os(iOS)
    /// The keyboard on the screen (its own notes say).
    @State private var keyboardUp = false
    #endif
    #if os(iOS)
    @State private var drawing = PKDrawing()
    @State private var history: [PKDrawing] = []
    #endif
    @State private var loaded = false
    /// The writing square's side, fixed when the note opens (a note written
    /// at another size is scaled to it).
    @State private var side = 300.0
    enum Tool { case pencil, red, eraser }
    private static let ink = Color(red: 0.22, green: 0.22, blue: 0.28)

    init(id: UUID?, typingFirst: Bool = false, done: @escaping () -> Void) {
        self.id = id
        self.typingFirst = typingFirst
        self.done = done
        // A note being written on again starts as it was: its words, its
        // paper, its lines at the size they were written (the canvas has
        // them from the first moment).
        if let id, let note = PencilBoxStore.shared.note(id) {
            _text = State(initialValue: note.text)
            _grid = State(initialValue: note.grid)
            _side = State(initialValue: note.width)
            _face = State(initialValue: note.hand ?? .notes)
            #if os(iOS)
            if !note.drawing.isEmpty, let saved = try? PKDrawing(data: note.drawing) { _drawing = State(initialValue: saved) }
            #endif
        } else {
            _grid = State(initialValue: PencilBoxStore.shared.squaredPaper)
        }
    }

    /// The writing square for a sheet of this size: as wide as fits beside
    /// the paper's edges, at most 300 points.
    static func side(for size: CGSize) -> Double {
        let art = PencilArt.notePlain, area = PencilArt.noteArea
        let byWidth = (size.width - 36) * area.width / art.size.width
        let byHeight = (size.height - 150) * area.height / art.size.height
        return max(150, min(300, byWidth, byHeight))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let fit = Self.side(for: proxy.size)
                VStack(spacing: 16) {
                    paper(side: loaded || id != nil ? min(side, fit) : fit)
                    tools
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
                .onAppear { load(side: fit) }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in keyboardUp = true }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardUp = false }
                #endif
            }
            .background(PencilSheetGround())
            .navigationTitle(id == nil ? Text("写一张便条") : Text("写字"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { done() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { finish() }.accessibilityIdentifier("pencil-note-done") }
            }
        }
    }

    private func paper(side: Double) -> some View {
        let art = grid ? PencilArt.noteGrid : PencilArt.notePlain
        let area = PencilArt.noteArea
        let k = side / area.width
        return ZStack {
            PencilImages.image(art.file).resizable().frame(width: art.size.width * k, height: art.size.height * k)
            ZStack(alignment: .topLeading) {
                #if os(iOS)
                // While typing, the lines drawn stay where they are, under the words.
                if typing, !drawing.strokes.isEmpty {
                    Image(uiImage: drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 2))
                        .resizable().frame(width: side, height: side)
                        .allowsHitTesting(false)
                }
                #endif
                if typing {
                    TextField("", text: $text, prompt: Text("打字写在这里"), axis: .vertical)
                        .font(hand.font(face, size: 9.5 * k))
                        .lineSpacing(1.5 * k)
                        .foregroundStyle(Self.ink)
                        .lineLimit(1...6)
                        .focused($typingFocus)
                        .padding(.horizontal, 3 * k).padding(.top, 2 * k)
                        .accessibilityIdentifier("pencil-note-text")
                } else if !text.isEmpty {
                    // Drawing: the words under the lines, as the lid shows them.
                    Text(verbatim: text)
                        .font(hand.font(face, size: 9.5 * k))
                        .lineSpacing(1.5 * k)
                        .foregroundStyle(Self.ink)
                        .padding(.horizontal, 3 * k).padding(.top, 2 * k)
                        .frame(width: side, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pencil-note-words")
                }
                #if os(iOS)
                if !typing {
                    PencilCanvas(drawing: $drawing, tool: tool) { before in history.append(before); if history.count > 40 { history.removeFirst() } }
                        .accessibilityValue(drawing.strokes.isEmpty ? Text("空白") : Text("写过"))
                        .accessibilityIdentifier("pencil-note-canvas")
                }
                #endif
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .offset(x: area.midX * k, y: area.midY * k)
            PencilImages.image((PencilMagnet.red).art.file).resizable()
                .frame(width: PencilArt.magnetRed.size.width * k * 0.8, height: PencilArt.magnetRed.size.height * k * 0.8)
                .offset(x: PencilArt.noteMagnet.x * k, y: PencilArt.noteMagnet.y * k)
                .allowsHitTesting(false)
        }
        .frame(width: art.size.width * k, height: art.size.height * k)
    }

    private var tools: some View {
        HStack(spacing: 10) {
            toolButton("铅笔", "pencil", on: !typing && tool == .pencil) { draw(.pencil) }
            toolButton("红笔", "pencil.tip", on: !typing && tool == .red) { draw(.red) }
            toolButton("橡皮", "eraser", on: !typing && tool == .eraser) { draw(.eraser) }
            toolButton("打字", "keyboard", on: typing) {
                if typing { typingFocus = false; typing = false; return }
                typing = true
                hand.ensure(face)
                DispatchQueue.main.async { typingFocus = true }
            }
            if typing {
                faceButton
            } else {
                #if os(iOS)
                toolButton("撤销", "arrow.uturn.backward", on: false) { if let last = history.popLast() { drawing = last } }
                #endif
            }
            if store.squaredPaper { toolButton(grid ? LocalizedStringKey("格子纸") : LocalizedStringKey("横线纸"), "square.grid.3x3", on: grid) { grid.toggle() } }
        }
        .font(.subheadline.weight(.semibold))
    }

    /// Which handwriting the words are in: 手札体, 翩翩体, 娃娃体 in turn,
    /// the button showing a character in the one chosen.
    private var faceButton: some View {
        Button {
            face = face.next
            hand.ensure(face)
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: "字").font(hand.font(face, size: 19)).frame(height: 21).accessibilityHidden(true)
                Text(verbatim: face.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(minWidth: 46, minHeight: 46)
            .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.14))
            .background(Color(red: 0.97, green: 0.94, blue: 0.87), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("字体"))
        .accessibilityValue(Text(verbatim: face.title))
        .accessibilityIdentifier("pencil-note-face")
    }

    private func draw(_ chosen: Tool) {
        typingFocus = false
        typing = false
        tool = chosen
    }

    private func toolButton(_ title: LocalizedStringKey, _ symbol: String, on: Bool, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).accessibilityHidden(true)
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(minWidth: 46, minHeight: 46)
            .foregroundStyle(on ? Color.white : Color(red: 0.23, green: 0.17, blue: 0.14))
            .background(on ? Color(red: 0.72, green: 0.27, blue: 0.18) : Color(red: 0.97, green: 0.94, blue: 0.87), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("pencil-note-\(symbol)")
    }

    private func load(side fit: Double) {
        guard !loaded else { return }
        if id == nil {
            side = fit
        } else if side > fit + 0.5 {
            // Written on a bigger square than fits here: the lines scaled down to it.
            #if os(iOS)
            let k = fit / max(1, side)
            drawing = drawing.transformed(using: CGAffineTransform(scaleX: k, y: k))
            #endif
            side = fit
        }
        loaded = true
        if !text.isEmpty { hand.ensure(face) }
        if typingFirst {
            typing = true
            hand.ensure(face)
            // (as the postcard's: asked for once the sheet has come up, and again if no keyboard came)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if typing { typingFocus = true } }
            #if os(iOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard typing, !keyboardUp else { return }
                typingFocus = false
                DispatchQueue.main.async { typingFocus = true }
            }
            #endif
        }
    }

    private func finish() {
        // The keyboard lets go first, so that words still being put together
        // (pinyin not yet chosen) are kept as they stand.
        typingFocus = false
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        DispatchQueue.main.async { save() }
    }

    private func save() {
        #if os(iOS)
        let data = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
        #else
        let data = Data()
        #endif
        let note = PencilNote(drawing: data, width: side, height: side, text: text, grid: grid, hand: face)
        if let id { store.update(id, note: note) } else if !note.isBlank { store.addNote(note) }
        done()
    }
}

#if os(iOS)
/// PencilKit's canvas: a finger or Apple Pencil; the pencil grey, the red,
/// the eraser.
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: PencilNoteEditor.Tool
    var willChange: (PKDrawing) -> Void
    func makeUIView(context: Context) -> NoteCanvasView {
        let view = NoteCanvasView()
        view.drawingPolicy = .anyInput
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isScrollEnabled = false
        view.coordinator = context.coordinator
        view.delegate = context.coordinator
        apply(view)
        // A canvas shows lines given to it only once it is on screen with a
        // size: they wait until then.
        view.pending = drawing.strokes.isEmpty ? nil : drawing
        return view
    }
    func updateUIView(_ view: NoteCanvasView, context: Context) {
        context.coordinator.parent = self
        apply(view)
        if view.pending == nil, view.drawing != drawing { context.coordinator.quiet = true; view.drawing = drawing; context.coordinator.quiet = false }
    }
    private func apply(_ view: NoteCanvasView) {
        switch tool {
        case .pencil: view.tool = PKInkingTool(.pencil, color: UIColor(red: 0.22, green: 0.22, blue: 0.28, alpha: 1), width: 4)
        case .red: view.tool = PKInkingTool(.pencil, color: UIColor(red: 0.78, green: 0.2, blue: 0.22, alpha: 1), width: 4)
        case .eraser: view.tool = PKEraserTool(.vector)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class NoteCanvasView: PKCanvasView {
        var pending: PKDrawing?
        weak var coordinator: Coordinator?
        override func didMoveToWindow() { super.didMoveToWindow(); showPending() }
        override func layoutSubviews() { super.layoutSubviews(); showPending() }
        private func showPending() {
            guard let lines = pending, window != nil, bounds.width > 1, bounds.height > 1 else { return }
            pending = nil
            coordinator?.quiet = true
            drawing = lines
            coordinator?.quiet = false
        }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        var quiet = false
        private var before: PKDrawing?
        init(_ parent: PencilCanvas) { self.parent = parent }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { before = canvasView.drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !quiet else { return }
            if let before { parent.willChange(before); self.before = nil }
            let drawing = canvasView.drawing
            DispatchQueue.main.async { self.parent.drawing = drawing }
        }
    }
}
#endif

// MARK: - The corner of the library

/// The box in a corner of the library, small and quiet; its lid open a
/// crack, a petal showing, while something new is in it.
struct PencilBoxCorner: View {
    var s: Double
    var open: () -> Void
    @ObservedObject private var tin = TinBoxStore.shared
    @ObservedObject private var box = PencilBoxStore.shared
    @AppStorage(PencilBoxLook.key) private var lookID = PencilBoxLook.standard.id
    var body: some View {
        let fresh = !tin.unseen.isEmpty || !box.freshPostcards.isEmpty
        Button(action: open) {
            PencilImages.image(fresh ? "pencilbox-icon-open.png" : "pencilbox-icon-closed.png", look: PencilBoxLook(id: lookID)).resizable()
                .frame(width: 90 * s * 0.85, height: 48 * s * 0.85)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel(Text("铅笔盒"))
        .accessibilityValue(fresh ? Text("有新东西") : Text(verbatim: ""))
        .accessibilityIdentifier("library-pencil-box")
    }
}

#if os(iOS)
/// 11-22: VoiceOver's way to place a postcard's own picture (what a finger does on the big postcard by dragging and
/// pinching): moved a little each way, brought closer or further. Nothing on a front without such a picture.
private struct PencilPlaceActions: ViewModifier {
    var on: Bool
    /// across, down (each -1, 0 or 1), how much closer
    var nudge: (Double, Double, Double) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if on {
            content
                .accessibilityAction(named: Text("往左挪")) { nudge(-1, 0, 1) }
                .accessibilityAction(named: Text("往右挪")) { nudge(1, 0, 1) }
                .accessibilityAction(named: Text("往上挪")) { nudge(0, -1, 1) }
                .accessibilityAction(named: Text("往下挪")) { nudge(0, 1, 1) }
                .accessibilityAction(named: Text("大一点")) { nudge(0, 0, 1.25) }
                .accessibilityAction(named: Text("小一点")) { nudge(0, 0, 0.8) }
        } else {
            content
        }
    }
}
#endif

/// 11-22: the ground of the pencil box's own sheets (a photo, the pad, the timetable, the postcards, a note): the
/// outside of the box chosen — its tin, plastic, wood or canvas, in its colour; the lid's upper middle, none of its
/// edge or of the little picture in its corner — darkened a little so the words on it read. (They were all one teal
/// before, whatever the box; teal is still there while the picture is read, and in the Mac preview.)
struct PencilSheetGround: View {
    @AppStorage(PencilBoxLook.key) private var lookID = PencilBoxLook.standard.id
    private static let teal = Color(red: 0.25, green: 0.52, blue: 0.48)
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Self.teal
                #if os(iOS)
                if let ground = Self.ground(PencilBoxLook(id: lookID)) {
                    Image(uiImage: ground).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    Color.black.opacity(0.3)
                }
                #endif
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
    #if os(iOS)
    @MainActor private static var grounds: [String: UIImage] = [:]
    @MainActor private static func ground(_ look: PencilBoxLook) -> UIImage? {
        if let hit = grounds[look.id] { return hit }
        guard let lid = PencilImages.picture("pencilbox-lid.jpg", look: look), let whole = lid.cgImage else { return nil }
        let w = Double(whole.width), h = Double(whole.height)
        guard let part = whole.cropping(to: CGRect(x: w * 0.2, y: h * 0.1, width: w * 0.6, height: h * 0.45).integral) else { return nil }
        let made = UIImage(cgImage: part)
        grounds[look.id] = made
        return made
    }
    #endif
}

/// 11-22: the canvas box's net pocket (PencilBoxProgram.netPocket): the folded note and the eraser drawn in it, in
/// the drawing's points — the same upright and across (the lid's inside begins at the same corner in both).
enum PencilNetPocket {
    struct Thing {
        let name: String
        let title: String
        let sound: ConsoleSound
        /// What takes the touch (around the thing's middle).
        let touch: CGSize
        /// The part of the picture drawn again over it (the thing and a little of the net around it).
        let patch: CGRect
        /// It hops a little as it grows (the eraser); the note only gives.
        let hops: Bool
    }
    static let things: [Thing] = [
        Thing(name: "note", title: String(localized: "网兜里的纸条"), sound: .netNote, touch: CGSize(width: 78, height: 80),
              patch: CGRect(x: 54, y: 152, width: 102, height: 104), hops: false),
        Thing(name: "eraser", title: String(localized: "网兜里的橡皮"), sound: .netEraser, touch: CGSize(width: 66, height: 53),
              patch: CGRect(x: 92, y: 306, width: 90, height: 77), hops: true),
    ]
}
