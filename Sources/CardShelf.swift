import SwiftUI

// The shelf of game cards. Round 26 drew the cards flat (SwiftUI's
// projection effect) with a round ▶ on the middle one and a music player's
// bar (⏮ ▶ ⏭) under them; round 27 made the cards solids in the console's
// RealityKit scene (CardModel3D, ShelfScene) with a retro handheld's
// controls under them. Round 28: no controls at all. The cards are handled as cards:
// a sideways drag flips through them, a tap on one beside the middle brings
// it to the middle, a tap on the middle one puts it into the console (the
// console's menu then starts it), a drag upward lifts it. This view is the
// shelf's touch; the cards themselves are drawn by the stage (on the Mac
// preview, which has no RealityKit stage, flat pictures stand in for them).
//
// 11-07: held across (the console on the left) the cards stand in a
// column and slide up and down; a
// card is lifted toward the console, to the left. 11-07: a card held
// still comes up into the hand (the
// console turns round to take it, as for a card dragged up); taken away from
// the console instead — down off a row, out to the right off a column — its
// foot goes over the shelf's edge and it comes apart into pixels, a block at
// a time, the further the more; past a point it is all loose, and let go
// there it bursts and its game leaves the library (撤销 for a few seconds,
// LibraryMenuView). Let go before that, or brought back, it is whole again.

/// Where the shelf and its cards are (library coordinates).
struct ShelfGeometry: Equatable {
    var frame: CGRect
    var s: CGFloat
    /// Where the cards stand (round 28: all of the shelf's frame).
    var flow: CGRect
    var optics: ShelfOptics
    /// 11-07: the cards in a column beside the console (held across).
    var vertical: Bool { optics.vertical }
    init(frame: CGRect, s: CGFloat, viewSize: CGSize, vertical: Bool = false) {
        self.frame = frame
        self.s = s
        flow = frame
        let aspect = CGFloat(CardDimensions.aspect)
        if vertical {
            // The middle card in the middle of the column, a little larger
            // than in a row: the column has the height.
            let cw = min(frame.width * 0.56, frame.height * 0.34 / aspect)
            let ch = cw * aspect
            optics = ShelfOptics(viewSize: viewSize, centre: CGPoint(x: flow.midX, y: flow.midY), cardWidth: cw, floorY: flow.midY + ch / 2, vertical: true)
        } else {
            let cw = min(frame.width * 0.40, flow.height * 0.56 / aspect)
            let ch = cw * aspect
            let floorY = flow.minY + flow.height * 0.80
            optics = ShelfOptics(viewSize: viewSize, centre: CGPoint(x: flow.midX, y: floorY - ch / 2), cardWidth: cw, floorY: floorY)
        }
    }
}

/// Under the cards (drawn below the stage's RealityView): the floor they
/// stand on, a seamless backdrop as in a product photograph, a little darker
/// toward where they stand, and a soft pool of the studio's light behind
/// them (round 28: no longer the colour of the middle card's label). A
/// column (11-07) has no floor: the light alone, tall behind it.
struct ShelfBackdrop: View {
    var geometry: ShelfGeometry
    var theme: LibraryTheme
    var shown: Bool
    var body: some View {
        let o = geometry.optics
        let ch = o.cardWidth * CGFloat(CardDimensions.aspect)
        let k = theme.isDark ? 0.16 : 0.07
        ZStack(alignment: .topLeading) {
            if !geometry.vertical {
                LinearGradient(stops: [.init(color: theme.ink.opacity(0), location: 0),
                                       .init(color: theme.ink.opacity(k), location: 0.55),
                                       .init(color: theme.ink.opacity(k * 0.55), location: 0.8),
                                       .init(color: theme.ink.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: geometry.flow.width, height: ch * 1.5)
                    .position(x: geometry.flow.midX, y: o.floorY - ch * 0.3)
            }
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(theme.isDark ? 0.10 : 0.30), Color.white.opacity(0)], center: .center, startRadius: 0,
                                     endRadius: geometry.vertical ? ch * 1.6 : o.cardWidth * 1.5))
                .frame(width: geometry.vertical ? o.cardWidth * 2.2 : o.cardWidth * 3.2, height: geometry.vertical ? ch * 3.4 : o.cardWidth * 1.9)
                .blur(radius: 20 * geometry.s)
                .position(x: o.centre.x, y: o.centre.y)
        }
        .frame(width: o.viewSize.width, height: o.viewSize.height, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: shown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The shelf's touch and controls: a drag along the shelf flicks through the
/// cards, a tap on one brings it to the middle (on the middle one: a hop), a
/// drag toward the console lifts the middle card out (it goes into the
/// console where it is let go); round 28: a tap on the middle one puts it
/// into the console. 11-07: a press held still lifts the middle card too, and
/// a lifted card taken away from the console, over the shelf's edge, comes
/// apart into pixels and is deleted (`onDelete`). VoiceOver also has
/// 插入并开启, 取出掌机里的卡带 and 删除 on the cards.
struct CardShelfView: View {
    var shelf: ShelfScene
    var geometry: ShelfGeometry
    var cards: [GameCardInfo]
    /// The cards on the shelf, in order (indices into `cards`).
    var order: [Int]
    /// The scroll, in shelf positions (where it settles).
    @Binding var offset: Double
    /// The card in the middle (an index into `cards`).
    var centre: Int
    /// The card in the hand: its place on the shelf stays empty.
    var hidden: Int?
    /// The card in the console (VoiceOver can take it out).
    var inserted: Int?
    var theme: LibraryTheme
    var onTap: (Int) -> Void
    /// A lift's phases; true when `.began` took the card (11-07: a held
    /// card is lifted this way too).
    var onLift: (Int, CGPoint, LibraryMenuView.LiftPhase) -> Bool
    var onStart: (Int) -> Void
    var onEject: () -> Void
    /// Round 30: off while a program runs on the console (its cards have
    /// sunk into the floor): no touch, nothing for VoiceOver and the tests.
    /// The view itself stays (b6 took the whole shelf out of the library and
    /// put it back after: XCUITest then found its cards but could not touch
    /// them, 11-01).
    var active = true
    /// Round 31: where the console, brought close by a pinch, reaches over
    /// the shelf (in this view's coordinates): a finger there is the
    /// console's, the shelf keeps the rest.
    var hole: CGRect? = nil
    /// A tap in the shelf's area that met no card (where it was, in the
    /// library's coordinates): the console may stand there.
    var onMiss: (CGPoint) -> Void = { _ in }
    /// 11-07: may the card be deleted (not the built-in demo)…
    var canDelete: (Int) -> Bool = { _ in false }
    /// …it burst in the hand (let go all loose): the lift is over at once
    /// (the hand empty, the console back as it stood); the card's place on
    /// the shelf stays empty while the eraser rubs the remains out…
    var onBurst: (Int) -> Void = { _ in }
    /// …and then its game leaves the library (on the device: cut at
    /// the burst, the next card came to the middle under the eraser's
    /// strokes, which then seemed to rub that one out). False when it could
    /// not after all (whoever said so puts the card back onto the shelf; the
    /// remains just go).
    var onDelete: (Int) -> Bool = { _ in false }
    /// Renders (Scripts/RenderPreview `--shelf`): the lifted card drawn flat
    /// at one moment of a deletion, without a finger.
    var previewCrumble: CrumblePreview? = nil
    /// 11-11: what a deleted card goes into (主题 › 删除方式; DeleteStyle):
    /// the bin unless another is chosen; a render's own.
    var previewStyle: DeleteStyle? = nil
    @AppStorage(DeleteStyle.key) private var styleID = DeleteStyle.bin.rawValue
    private var style: DeleteStyle { previewStyle ?? DeleteStyle(rawValue: styleID) ?? .bin }

    struct CrumblePreview: Equatable {
        var index: Int
        /// How far over the shelf's edge, in points (0: just lifted).
        var over: Double
        /// Let go: seconds into the burst.
        var burst: Double? = nil
    }

    private enum DragMode: Equatable { case flick(start: Double), lift(index: Int) }
    @ViewState private var mode: DragMode?

    /// The lifted card coming apart (11-07).
    struct Crumble: Equatable {
        var index: Int
        var card: GameCardInfo
        /// The held card's face on the screen.
        var rect: CGRect
        /// 0 at the shelf's edge, 1 where it is all loose.
        var progress: Double
        /// Let go all loose: breaking up since.
        var burst: Date? = nil
    }
    @ViewState private var crumble: Crumble?
    /// What the thing a deleted card goes into is shown (DeletePropView):
    /// how near the card is to the edge (0 far … 1 at it), over it how
    /// loose (0 … 1), the card's face on the screen, and the moment it was
    /// let go all loose (a render: how long ago).
    struct DeleteMoment: Equatable {
        var near: Double
        var progress: Double
        var card: CGRect
        var burst: Date? = nil
        var previewBurst: Double? = nil
    }
    /// Where the lifted card's far edge (its foot in a row, its right edge in
    /// a column) was when it was picked up (the held card centres on the
    /// finger): it has to go `deadZone` past that, and past the shelf's edge,
    /// before it comes apart.
    @ViewState private var liftedEdge: Double?
    /// The finger came down at (a press held this long, still, lifts the card).
    @ViewState private var touchDown: Date?
    @ViewState private var pressTimer: Task<Void, Never>?
    /// The press moved a card to the middle (or was refused): letting go is
    /// not a tap.
    @ViewState private var pressUsed = false
    /// A hold lifted the card before any move came in: the first move says
    /// whether it was a hold at all (see `touchChanged`).
    @ViewState private var holdUnchecked = false
    /// The demo was taken over the edge this lift: said once.
    @ViewState private var refusedThisLift = false
    /// Where the finger carrying the lifted card is (the well under the
    /// shelf brightens as it comes near the edge).
    @ViewState private var finger: CGPoint?
    @ViewState private var note: String?
    private static let pressTime = 0.45

    private var s: CGFloat { geometry.s }
    private var vertical: Bool { geometry.vertical }
    private var cardHeight: Double { Double(geometry.optics.cardWidth) * CardDimensions.aspect }
    /// Points of drag per card along the shelf.
    private var dragScale: Double { vertical ? cardHeight * 0.8 : Double(geometry.optics.cardWidth) * 0.85 }
    /// Over the shelf's edge: this far further and the card is all loose.
    private var reach: Double { 50 * Double(s) }
    /// 11-11: how much smaller a card that goes into the floor whole is by
    /// the time it is all loose (DeleteStyle.lowersCard): its far edge then
    /// about at the shelf's edge, where the thing in the floor begins.
    private var lowering: Double {
        let size = Double(geometry.optics.cardWidth) * 1.12 * (vertical ? 1 : CardDimensions.aspect)
        return min(0.55, max(0.3, 2 * reach / max(1, size)))
    }
    /// A lifted card has to move this far away from where it was picked up
    /// before it starts to come apart (picked up by its foot, it would be
    /// over the edge at once).
    private var deadZone: Double { 12 * Double(s) }

    private struct Contents: Equatable {
        var keys: [String]
        var order: [Int]
        var hidden: Int?
    }
    private var contents: Contents { Contents(keys: cards.map(CardArtPrints.key), order: order, hidden: hidden) }

    var body: some View {
        let size = geometry.optics.viewSize
        ZStack(alignment: .topLeading) {
            if order.isEmpty {
                if active {
                    emptyShelf
                        .frame(width: geometry.flow.width, height: geometry.flow.height)
                        .position(x: geometry.flow.midX, y: geometry.flow.midY)
                }
            } else {
                #if !os(iOS)
                flatCards
                #endif
                if active {
                    Color.clear
                        .contentShape(touchShape, eoFill: true)
                        .frame(width: geometry.flow.width, height: geometry.flow.height)
                        // 11-07: one gesture for all of it (a tap, a held
                        // press, a flick, a lift, a deletion), from the
                        // moment the finger comes down.
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("library"))
                            .onChanged { value in touchChanged(value) }
                            .onEnded { value in touchEnded(value) })
                        .position(x: geometry.flow.midX, y: geometry.flow.midY)
                    accessibilityPlaces
                }
            }
            if active { summary }
            // 11-11: the thing in the floor (or the eraser, the scissors)
            // and the card coming apart, in their layers.
            DeleteLayers(style: style, geometry: geometry, theme: theme, moment: propMoment, crumble: shownCrumble,
                         previewBurst: previewCrumble?.burst,
                         hand: (crumble == nil || style.keepsCardWhole) && crumble?.burst == nil && previewCrumble == nil ? shelf : nil,
                         solid: previewCrumble == nil && style.keepsCardWhole, lowering: style.lowersCard ? lowering : 0)
            if let note {
                Text(note).font(.system(size: 12 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 12 * s).padding(.vertical, 7 * s)
                    .background(Capsule().fill(.regularMaterial))
                    .position(x: geometry.optics.centre.x, y: geometry.optics.centre.y)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear {
            shelf.setLayout(geometry.optics)
            shelf.setCards(cards, order: order, hidden: hidden)
            shelf.setGoal(offset, animated: false)
        }
        .onChange(of: geometry) { _, value in shelf.setLayout(value.optics) }
        .onChange(of: contents) { _, _ in shelf.setCards(cards, order: order, hidden: hidden) }
        .onChange(of: offset) { _, value in if mode == nil { shelf.setGoal(value) } }
    }

    /// The shelf's touch: its whole area, less the console's part of it
    /// (`hole`), in the touch layer's own coordinates.
    private var touchShape: Path {
        let flow = geometry.flow
        var path = Path(CGRect(origin: .zero, size: flow.size))
        if let hole {
            let cut = hole.intersection(flow)
            if !cut.isNull, !cut.isEmpty { path.addRect(cut.offsetBy(dx: -flow.minX, dy: -flow.minY)) }
        }
        return path
    }
    private var position: Int? { order.firstIndex(of: centre) }
    private var placeText: String {
        guard let position else { return inserted == centre ? String(localized: "在掌机里") : "" }
        return "\(position + 1)/\(order.count)"
    }
    /// Round 28: nothing names the middle card on the screen any more (its
    /// label does); for VoiceOver and the UI tests an element along the
    /// floor still does (the place as its value).
    private var summary: some View {
        let card = cards.indices.contains(centre) ? cards[centre] : nil
        return Color.clear
            .frame(width: geometry.flow.width, height: max(8, 24 * s))
            .position(x: geometry.flow.midX, y: min(geometry.flow.maxY - 12 * s, geometry.optics.floorY + 30 * s))
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(card.map { "\($0.title)，\($0.subtitle)" } ?? "没有卡带")
            .accessibilityValue(placeText)
            .accessibilityIdentifier("shelf-title")
    }

    private var emptyShelf: some View {
        VStack(spacing: 10 * s) {
            CardShellShape(cut: 10 * s).stroke(theme.inkSoft.opacity(0.5), style: StrokeStyle(lineWidth: 2 * s, dash: [7 * s, 5 * s]))
                .frame(width: 80 * s, height: 86 * s)
            Text("架子上没有卡带").font(.system(size: 14 * s, weight: .bold, design: .rounded))
            Text("在掌机主菜单里点「导入」，从「文件」添加软件").font(.system(size: 10 * s, weight: .semibold)).foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24 * s)
    }

    // MARK: Which card, where

    /// The cards as they stand now (the scene's scroll), for a tap.
    private var livePlaces: [(index: Int, rel: Double, quad: [CGPoint])] {
        #if os(iOS)
        return shelf.places()
        #else
        return geometry.optics.places(order: order, hidden: hidden, offset: offset)
        #endif
    }
    /// The card under `location`: the one whose face it is on, nearest the
    /// middle; beside the middle a little round its face too.
    private func card(at location: CGPoint) -> Int? {
        var best: (Int, Double)?
        for place in livePlaces {
            let bounds = Self.bounds(place.quad)
            guard Self.contains(place.quad, location) || abs(place.rel) > 0.5 && bounds.insetBy(dx: -6, dy: -6).contains(location) else { continue }
            if best == nil || abs(place.rel) < best!.1 { best = (place.index, abs(place.rel)) }
        }
        return best?.0
    }
    private func tapped(_ location: CGPoint) {
        guard let index = card(at: location) else { onMiss(location); return }
        onTap(index)
    }
    private static func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }
    private static func contains(_ quad: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = quad.count - 1
        for i in 0..<quad.count {
            let a = quad[i], b = quad[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / max(0.0001, b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Where each card is, for VoiceOver and the UI tests: an element over
    /// the part of its face that shows once the shelf has settled (taps
    /// there go to the shelf itself).
    private var accessibilityPlaces: some View {
        let places = geometry.optics.places(order: order, hidden: hidden, offset: offset)
        return ZStack(alignment: .topLeading) {
            ForEach(places, id: \.index) { place in
                let rect = visibleRect(place, among: places)
                let isCentre = place.index == centre
                Rectangle().fill(Color.white.opacity(0.001))
                    .frame(width: max(8, rect.width), height: max(8, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(cards[place.index].title)
                    .accessibilityValue(cards[place.index].subtitle)
                    .accessibilityAddTraits(isCentre ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onTap(place.index) }
                    // Round 28 (no buttons under the shelf): what A and B did.
                    .accessibilityAction(named: Text("插入并开启")) { onStart(place.index) }
                    .accessibilityAction(named: Text("取出掌机里的卡带")) { onEject() }
                    // 11-07: deletion, for VoiceOver (撤销 follows).
                    .accessibilityAction(named: Text("删除（从游戏库移除）")) { if canDelete(place.index) { _ = onDelete(place.index) } }
                    .zIndex(100 - abs(place.rel))
            }
        }
    }
    /// The part of a card's face not covered by its neighbour toward the
    /// middle (all of it for the middle one): beside it in a row, above or
    /// below it in a column.
    private func visibleRect(_ place: (index: Int, rel: Double, quad: [CGPoint]), among places: [(index: Int, rel: Double, quad: [CGPoint])]) -> CGRect {
        var rect = Self.bounds(place.quad)
        guard abs(place.rel) > 0.5 else { return rect }
        let sign: Double = place.rel < 0 ? -1 : 1
        if let inner = places.first(where: { abs($0.rel - (place.rel - sign)) < 0.5 }) {
            let innerRect = Self.bounds(inner.quad)
            if vertical {
                if sign < 0 {
                    rect.size.height = max(8, min(rect.maxY, innerRect.minY) - rect.minY)
                } else {
                    let top = max(rect.minY, innerRect.maxY)
                    rect.size.height = max(8, rect.maxY - top)
                    rect.origin.y = top
                }
            } else if sign < 0 {
                rect.size.width = max(8, min(rect.maxX, innerRect.minX) - rect.minX)
            } else {
                let left = max(rect.minX, innerRect.maxX)
                rect.size.width = max(8, rect.maxX - left)
                rect.origin.x = left
            }
        }
        return rect
    }

    #if !os(iOS)
    /// The Mac preview: flat pictures where the solids would stand.
    private var flatCards: some View {
        let places = geometry.optics.places(order: order, hidden: hiddenForPreview, offset: offset).sorted { abs($0.rel) > abs($1.rel) }
        return ZStack(alignment: .topLeading) {
            ForEach(places, id: \.index) { place in
                let rect = Self.bounds(place.quad)
                let turn = -min(1, max(-1, place.rel)) * 64
                GameCardFace(card: cards[place.index], s: 1)
                    .frame(width: geometry.optics.cardWidth, height: geometry.optics.cardWidth * CGFloat(CardDimensions.aspect))
                    .rotation3DEffect(.degrees(vertical ? -turn : turn), axis: vertical ? (x: 1, y: 0, z: 0) : (x: 0, y: 1, z: 0), perspective: 0.5)
                    .scaleEffect(vertical ? rect.width / max(1, geometry.optics.cardWidth) : rect.height / max(1, geometry.optics.cardWidth * CGFloat(CardDimensions.aspect)))
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
    /// (A card being deleted is off the shelf in the preview too.)
    private var hiddenForPreview: Int? { previewCrumble?.index ?? hidden }
    #endif

    // MARK: The finger (11-07: one gesture)

    private func touchChanged(_ value: DragGesture.Value) {
        if touchDown == nil {
            touchDown = value.time
            pressUsed = false
            holdUnchecked = false
            // 11-11 (the iPhone Duo held across, a press of 0.9 s then a
            // drag): the shelf heard of the finger 0.1 to 0.65 s after it
            // came down (the main thread not held), and a hold counted from
            // then was a flick by the time it was up. The hold counts from
            // when the finger came down, by the event's own clock.
            let late = Self.lateness(of: value)
            #if DEBUG
            NSLog("[shelf] finger down at (%.0f, %.0f), heard %.0f ms after, moved %.0f", value.startLocation.x, value.startLocation.y,
                  late * 1000, hypot(value.translation.width, value.translation.height))
            #endif
            holdAfterPress(at: value.startLocation, already: late)
        }
        if holdUnchecked, case .lift(let index) = mode {
            // The hold's timer fired before this, the finger's first move,
            // came in (the app busy for a moment, b76d on the iPhone 17e).
            // By its time the finger had gone 10 points within the press
            // time, along the shelf: a flick, not a hold. The card goes back
            // and the flick goes on.
            holdUnchecked = false
            let early = touchDown.map { value.time.timeIntervalSince($0) < Self.pressTime } ?? false
            let t = value.translation
            // (11-11: any way but toward the console — a finger heard of
            // late is lifted at once now, and one already going off the
            // shelf's far edge was no hold either: no card deleted by it.)
            if early, hypot(t.width, t.height) >= 10, !isTowardConsole(t) {
                NSLog("[shelf] not held after all: the finger was already moving")
                _ = onLift(index, CGPoint(x: -1000, y: -1000), .ended)
                liftedEdge = nil
                finger = nil
                mode = .flick(start: shelf.position)
            }
        }
        dragChanged(value)
        if mode != nil { pressTimer?.cancel(); pressTimer = nil }
    }
    /// How long ago the finger of `value` came down, when this is its first
    /// event: a drag's time is on the clock a touch's timestamp is on (the
    /// system's uptime, as a date from the reference date: iOS 27.2, the
    /// Simulator and the iPhone Duo, 11-11); were it the wall clock, that is
    /// tried too. 0 when neither gives a sensible answer.
    private static func lateness(of value: DragGesture.Value) -> Double {
        let byUptime = ProcessInfo.processInfo.systemUptime - value.time.timeIntervalSinceReferenceDate
        let byClock = Date().timeIntervalSince(value.time)
        for late in [byUptime, byClock] where late >= 0 && late < 10 { return late }
        return 0
    }
    /// Toward the console: up from a row under it, left from a column
    /// beside it (the finger's way mostly that way).
    private func isTowardConsole(_ t: CGSize) -> Bool {
        vertical ? abs(t.width) > abs(t.height) * 1.2 && t.width < 0 : abs(t.height) > abs(t.width) * 1.2 && t.height < 0
    }
    private func touchEnded(_ value: DragGesture.Value) {
        pressTimer?.cancel()
        pressTimer = nil
        let held = touchDown.map { value.time.timeIntervalSince($0) } ?? 0
        #if DEBUG
        NSLog("[shelf] finger up at (%.0f, %.0f) after %.2f s, mode %@%@", value.location.x, value.location.y, held, String(describing: mode),
              touchDown == nil ? " (no finger was down)" : "")
        #endif
        touchDown = nil
        guard mode != nil else {
            // A tap: short, and the finger stayed where it came down.
            let t = value.translation
            if !pressUsed, held < Self.pressTime, hypot(t.width, t.height) < 10 { tapped(value.location) }
            return
        }
        dragEnded(value)
    }
    /// A press held still on the middle card lifts it into the hand (the
    /// console turns round to take it); on another card it brings that card
    /// to the middle.
    private func holdAfterPress(at location: CGPoint, already: Double = 0) {
        pressTimer?.cancel()
        let wait = max(0, Self.pressTime - already)
        pressTimer = Task { @MainActor in
            if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
            guard !Task.isCancelled else { return }
            // (11-11, the iPhone Duo held across: a press held on the middle
            // card came to nothing twice in six runs, with nothing in the
            // log. Why a held press lifts nothing is said from here on.)
            guard touchDown != nil, mode == nil, !shelf.pinching, shelf.handIndex == nil else {
                NSLog("[shelf] a press held at (%.0f, %.0f), nothing lifted: the finger %@, mode %@, pinching %d, in the hand %ld",
                      location.x, location.y, touchDown == nil ? "up" : "down", String(describing: mode), shelf.pinching ? 1 : 0, shelf.handIndex ?? -1)
                return
            }
            guard let index = card(at: location) else {
                let places = livePlaces
                let middle = places.first { $0.index == centre }.map { Self.bounds($0.quad) }
                NSLog("[shelf] a press held at (%.0f, %.0f): no card there (%ld cards placed; the middle one at %@)",
                      location.x, location.y, places.count, middle.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none")
                return
            }
            pressUsed = true
            guard index == centre else {
                ConsoleHaptics.shared.play(.stickTouch, .press)
                onTap(index)
                return
            }
            guard onLift(index, location, .began) else {
                NSLog("[shelf] a press held on the middle card: the library did not lift it")
                return
            }
            mode = .lift(index: index)
            holdUnchecked = true
            refusedThisLift = false
            liftedEdge = heldFarEdge(finger: location)
            withAnimation(.easeOut(duration: 0.25)) { finger = location }
            NSLog("[shelf] a card held: lifted")
        }
    }
    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { note = text }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            if note == text { withAnimation(.easeIn(duration: 0.3)) { note = nil } }
        }
    }

    // MARK: Moving

    private func dragChanged(_ value: DragGesture.Value) {
        // Round 30: one finger of a pinch (the whole library's) neither
        // flicks the shelf nor lifts a card; a finger decides what it does
        // only once it has gone 10 points, by when a pinch has said so.
        if shelf.pinching, !isLifting { return }
        if mode == nil {
            let t = value.translation
            guard hypot(t.width, t.height) >= 10 else { return }
            // Toward the console lifts the middle card: up from a row under
            // it, left from a column beside it.
            if isTowardConsole(t) {
                guard onLift(centre, value.location, .began) else { return }
                mode = .lift(index: centre)
                refusedThisLift = false
                liftedEdge = heldFarEdge(finger: value.location)
                withAnimation(.easeOut(duration: 0.25)) { finger = value.location }
            } else {
                mode = .flick(start: shelf.position)
            }
        }
        switch mode {
        case .flick(let start):
            let raw = start - along(value.translation) / dragScale
            // Past either end the shelf gives a little, then stops.
            let limit = Double(max(0, order.count - 1))
            let soft = raw < 0 ? raw * 0.35 : (raw > limit ? limit + (raw - limit) * 0.35 : raw)
            shelf.drag(to: soft)
        case .lift(let index):
            _ = onLift(index, value.location, .moved)
            liftMoved(index, finger: value.location)
        case nil:
            break
        }
    }
    /// A drag's part along the shelf: across a row, down a column.
    private func along(_ t: CGSize) -> Double { Double(vertical ? t.height : t.width) }
    /// …and across it.
    private func across(_ t: CGSize) -> Double { Double(vertical ? t.width : t.height) }
    private var isLifting: Bool { if case .lift = mode { return true } else { return false } }
    private func dragEnded(_ value: DragGesture.Value) {
        // A flick that a pinch took over settles where the shelf stood.
        if shelf.pinching, case .flick = mode {
            shelf.release(to: offset, velocity: 0)
            mode = nil
            return
        }
        switch mode {
        case .flick(let start):
            let projected = start - along(value.predictedEndTranslation) / dragScale
            let target = min(Double(max(0, order.count - 1)), max(0, projected.rounded()))
            let velocity = -along(CGSize(width: value.velocity.width, height: value.velocity.height)) / dragScale
            shelf.release(to: target, velocity: velocity)
            mode = nil
            let index = Int(target)
            if index < order.count, order[index] != centre {
                onTap(order[index])
            } else if offset != target {
                offset = target
            }
            return
        case .lift(let index):
            withAnimation(.easeIn(duration: 0.2)) { finger = nil }
            if liftEnded(index) { return }
            _ = onLift(index, value.location, .ended)
        case nil:
            break
        }
        mode = nil
    }

    // MARK: Coming apart (11-07, 删除)

    /// The lifted card's far edge: its foot in a row (away from the console
    /// is down), its right edge in a column (away is to the right).
    private func farEdge(_ rect: CGRect) -> Double { Double(vertical ? rect.maxX : rect.maxY) }
    /// The shelf's edge the card goes over: the floor its cards stand on (a
    /// row), a line short of the column's right edge.
    private var shelfEdge: Double {
        vertical ? Double(geometry.flow.maxX - geometry.optics.cardWidth * 0.45) : Double(geometry.optics.floorY) + 22 * Double(s)
    }
    /// The held card's face on the screen: where the scene has it, else (no
    /// scene: a render) centred on the finger at the held size.
    private func heldRect(finger: CGPoint) -> CGRect {
        if let quad = shelf.handQuad() { return Self.bounds(quad) }
        let w = geometry.optics.cardWidth * 1.12, h = w * CGFloat(CardDimensions.aspect)
        return CGRect(x: finger.x - w / 2, y: finger.y - h / 2, width: w, height: h)
    }
    /// Where the held card's far edge is for a finger at `finger` (the held
    /// card, 1.12 of a shelf card wide, centres on the finger).
    private func heldFarEdge(finger: CGPoint) -> Double {
        let w = Double(geometry.optics.cardWidth) * 1.12
        return vertical ? Double(finger.x) + w / 2 : Double(finger.y) + w * CardDimensions.aspect / 2
    }
    /// How far the lifted card is over the edge, in points (0: not over), by
    /// the finger (the solid follows it a moment behind: by the finger the
    /// answer is the same whether the scene keeps up or not).
    private func overEdge(finger: CGPoint) -> Double {
        let line = max(shelfEdge, (liftedEdge ?? shelfEdge) + deadZone)
        return max(0, heldFarEdge(finger: finger) - line)
    }
    /// The lifted card moved: over the shelf's edge it comes apart (the solid
    /// hidden, its face drawn flat in blocks); back, it is whole again.
    private func liftMoved(_ index: Int, finger: CGPoint) {
        self.finger = finger
        guard crumble?.burst == nil, cards.indices.contains(index) else { return }
        let rect = heldRect(finger: finger)
        let over = overEdge(finger: finger)
        guard canDelete(index) else {
            if over > 0, !refusedThisLift {
                refusedThisLift = true
                ConsoleHaptics.shared.play(.sliderStop, .press)
                show(String(localized: "自带的演示卡删不掉"))
            }
            return
        }
        let progress = min(1.5, over / reach)
        let was = crumble?.progress ?? 0
        if over > 0 {
            if crumble == nil {
                ConsoleHaptics.shared.play(.stickTouch, .press)
                // (A card that goes in whole stays the solid in the hand.)
                if !style.keepsCardWhole { shelf.setHandVisible(false) }
                NSLog("[shelf] the lifted card is over the edge: far edge %.0f (the solid's %.0f), the shelf's edge %.0f, picked up at %.0f (+%.0f), reach %.0f",
                      heldFarEdge(finger: finger), farEdge(rect), shelfEdge, liftedEdge ?? -1, deadZone, reach)
            }
            if (was >= 1) != (progress >= 1) {
                ConsoleHaptics.shared.play(.sliderNotch, progress >= 1 ? .press : .release)
                NSLog("[shelf] the lifted card is %@ loose (over by %.0f)", progress >= 1 ? "all" : "no longer all", over)
            }
            crumble = Crumble(index: index, card: cards[index], rect: rect, progress: progress)
            if style.lowersCard { shelf.setHandLower(lowering * min(1, progress)) }
        } else if crumble != nil {
            shelf.setHandVisible(true)
            shelf.setHandLower(0)
            withAnimation(.easeOut(duration: 0.12)) { crumble = nil }
        }
    }
    /// The finger let go of the lifted card: all loose, it bursts and its
    /// game is deleted (true: the lift is over); else it is whole again and
    /// the lift ends as usual (back onto the shelf, or into the console).
    private func liftEnded(_ index: Int) -> Bool {
        liftedEdge = nil
        guard var state = crumble, state.burst == nil else { return false }
        guard state.progress >= 1, canDelete(index) else {
            NSLog("[shelf] the lifted card let go over the edge, not all loose (%.2f): whole again", state.progress)
            shelf.setHandVisible(true)
            shelf.setHandLower(0)
            withAnimation(.easeOut(duration: 0.12)) { crumble = nil }
            return false
        }
        if let quad = shelf.handQuad() { state.rect = Self.bounds(quad) }
        state.burst = Date()
        crumble = state
        mode = nil
        ConsoleSounds.shared.play(style.sound)
        ConsoleHaptics.shared.play(.powerButton, .press)
        NSLog("[shelf] the lifted card bursts")
        // The lift is over now; the game goes once the thing the card went
        // into has done (its place on the shelf stays empty meanwhile, its
        // solid in the hand gone). The bin (11-11, the default again, as on
        // 11-07): at once.
        onBurst(index)
        let style = self.style
        let burst = state.burst
        if style.burstTime <= 0 {
            let deleted = onDelete(index)
            NSLog("[shelf] burst (%@): the game %@", style.rawValue, deleted ? "deleted" : "could NOT be deleted (the card back)")
            if !deleted {
                withAnimation(.easeOut(duration: 0.15)) { crumble = nil }
                return true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(style.tailTime * 1000)))
                if crumble?.burst == burst { crumble = nil }
            }
            return true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(style.burstTime * 1000)))
            let deleted = onDelete(index)
            NSLog("[shelf] the remains gone (%@): the game %@", style.rawValue, deleted ? "deleted" : "could NOT be deleted (the card back)")
            if !deleted {
                if crumble?.burst == burst { withAnimation(.easeOut(duration: 0.15)) { crumble = nil } }
                return
            }
            try? await Task.sleep(for: .milliseconds(Int(style.tailTime * 1000)))
            if crumble?.burst == burst { crumble = nil }
        }
        return true
    }

    /// What the thing a deleted card goes into is shown, while a deletable
    /// card is in the hand and while it goes (11-07 the bin's well;
    /// then the eraser; 11-11 whichever is chosen). The bin's well goes at
    /// the burst, as it did.
    private var propMoment: DeleteMoment? {
        let style = self.style
        if let preview = previewCrumble, let shown = shownCrumble {
            if style == .bin, preview.burst != nil { return nil }
            return DeleteMoment(near: preview.over > 0 ? 1 : style.restNear, progress: min(1, preview.over / reach), card: shown.rect,
                                burst: shown.burst, previewBurst: preview.burst)
        }
        if let crumble, let burst = crumble.burst {
            return style == .bin ? nil : DeleteMoment(near: 1, progress: 1, card: crumble.rect, burst: burst)
        }
        guard case .lift(let index) = mode, let finger, canDelete(index) else { return nil }
        let line = max(shelfEdge, (liftedEdge ?? shelfEdge) + deadZone)
        let near = min(1, max(0, 1 - (line - heldFarEdge(finger: finger)) / (style.nearRange * Double(s))))
        return DeleteMoment(near: near, progress: min(1, crumble?.progress ?? 0), card: crumble?.rect ?? heldRect(finger: finger))
    }

    /// The deletion as it stands, or as a render asks for it.
    private var shownCrumble: Crumble? {
        if let crumble { return crumble }
        guard let preview = previewCrumble, cards.indices.contains(preview.index) else { return nil }
        let place = geometry.optics.places(order: order, hidden: nil, offset: offset).first { $0.index == preview.index }
        let rest = place.map { Self.bounds($0.quad) } ?? .zero
        let w = geometry.optics.cardWidth * 1.12, h = w * CGFloat(CardDimensions.aspect)
        // Lifted: its far edge at the shelf's edge, then `over` past it.
        let edge = CGFloat(shelfEdge + preview.over)
        let rect = vertical ? CGRect(x: edge - w, y: rest.midY - h / 2, width: w, height: h)
                            : CGRect(x: rest.midX - w / 2, y: edge - h, width: w, height: h)
        return Crumble(index: preview.index, card: cards[preview.index], rect: rect, progress: min(1.5, preview.over / reach),
                       burst: preview.burst == nil ? nil : Date())
    }
}

// MARK: - How a deleted card goes (11-11, 主题 › 删除方式)

/// 11-11: what a card taken over the
/// shelf's edge goes into. The bin is the default, as it was on
/// 11-07 (DeleteWellView; its card bursts and its game goes at once); the
/// eraser came next; the grate, the sofa's seam, the scissors and the
/// manhole are the other four of that evening's sketches. Whichever it is,
/// the hand does the same: a card held, taken away from the console over
/// the shelf's edge, let go there.
enum DeleteStyle: String, CaseIterable, Identifiable {
    case bin, grate, sofa, eraser, scissors, manhole
    /// Where 主题 keeps the choice (@AppStorage).
    static let key = "foldarc.deleteStyle"
    var id: String { rawValue }
    static var stored: DeleteStyle { DeleteStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .bin }

    var title: String {
        switch self {
        case .bin: return String(localized: "像素回收口")
        case .grate: return String(localized: "下水道格栅")
        case .sofa: return String(localized: "沙发缝")
        case .eraser: return String(localized: "橡皮擦")
        case .scissors: return String(localized: "小剪刀")
        case .manhole: return String(localized: "井盖")
        }
    }
    var blurb: String {
        switch self {
        case .bin: return String(localized: "架子边上一条虚线、一个像素小桶。卡带过了线碎成方块，松手就删。")
        case .grate: return String(localized: "小时候东西掉进去就再也捡不回来的地方。卡带一侧身，从栅条中间掉下去，扑通一声。")
        case .sofa: return String(localized: "卡带、硬币、玩具都在那里失踪过。缝张开，卡带侧身滑进去，垫子一合，扬起一点灰。")
        case .eraser: return String(localized: "写错的字、画坏的画都是这么没的。橡皮来回几下，把卡带擦成屑。")
        case .scissors: return String(localized: "一把小剪刀，靠近了才张开。咔嚓，从中间剪成两半。")
        case .manhole: return String(localized: "地上的井盖滑开，卡带掉进井里，井盖再滑回来。")
        }
    }
    /// From the moment the card is let go all loose until its game leaves
    /// the library (撤销's bar comes then, over the floor: whatever the
    /// thing in the floor does, it has done by then). The bin: at once.
    var burstTime: Double {
        switch self {
        case .bin: return 0
        case .grate: return 0.82
        case .sofa: return 0.92
        case .eraser: return EraseStrokes.total
        case .scissors: return 0.8
        case .manhole: return 0.96
        }
    }
    /// After that the remains (and the thing) are still drawn this long, going.
    var tailTime: Double {
        switch self {
        case .bin: return 0.8
        case .eraser: return 0.5
        default: return 0.25
        }
    }
    /// How near the card has to be before the thing starts to answer
    /// (points at s = 1, before the edge), and how awake it is in a render
    /// of the card just lifted.
    var nearRange: Double { self == .bin ? 70 : 90 }
    var restNear: Double { self == .bin ? 0.55 : 0.5 }
    /// What it draws: under the card, between its loose blocks and its
    /// whole part, over all of it.
    var layers: [DeletePropView.Layer] {
        switch self {
        case .bin: return [.under]
        case .grate, .sofa, .manhole: return [.under, .over]
        case .eraser, .scissors: return [.top]
        }
    }
    /// 11-11: the card stays whole — the solid in the hand all the
    /// while it is held, over the edge too — and goes in as a card: on its
    /// edge between the grate's bars, on its edge into the sofa's seam, down
    /// the manhole's shaft. (The scissors' card is whole until it is cut.)
    /// The bin's and the eraser's card comes apart in blocks, as it did.
    var keepsCardWhole: Bool { self == .grate || self == .sofa || self == .manhole || self == .scissors }
    /// …and, over the shelf's edge, it is lowered toward the thing in the
    /// floor: smaller the further over it is (CardShelfView.lowering at all
    /// loose), so that the thing shows under it and the card is at its
    /// mouth when it is let go. (Not the scissors': they come to the card.)
    var lowersCard: Bool { self == .grate || self == .sofa || self == .manhole }
    /// What is heard as the card is let go.
    var sound: ConsoleSound {
        switch self {
        case .bin, .eraser: return .crumble
        case .scissors: return .snip
        case .grate, .sofa, .manhole: return .drop
        }
    }
    /// The scissors cut across the card in this long (then the halves drop).
    static let scissorsCut = 0.28
    /// A card going into the floor: turned on its edge (the grate, the
    /// seam) in this long, then in in this long; down the shaft in this long.
    static let turnTime = 0.2
    static let slipTime = 0.36
    static let shaftTime = 0.5
}

/// Where the things in the floor are (the grate, the sofa's seam, the
/// manhole): a strip along the shelf's edge, under a row, right of a column,
/// as long as a card and a bit, as deep as the floor there has room for.
struct DeleteSlot: Equatable {
    var vertical: Bool
    var centre: CGPoint
    /// Along the shelf's edge.
    var length: CGFloat
    /// Away from the shelf.
    var depth: CGFloat
    init(geometry: ShelfGeometry) {
        let o = geometry.optics, flow = geometry.flow, s = geometry.s
        vertical = geometry.vertical
        length = o.cardWidth * 1.2
        if vertical {
            let near = flow.maxX - o.cardWidth * 0.45 - 6 * s
            depth = max(20 * s, min(o.cardWidth * 0.3, flow.maxX - 6 * s - near))
            centre = CGPoint(x: near + depth / 2, y: flow.midY)
        } else {
            let near = o.floorY + 8 * s
            depth = max(20 * s, min(o.cardWidth * 0.3, flow.maxY - 6 * s - near))
            centre = CGPoint(x: flow.midX, y: near + depth / 2)
        }
    }
    /// A point of it: `u` along the edge from its middle, `v` away from the
    /// shelf from its middle.
    func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        vertical ? CGPoint(x: centre.x + v, y: centre.y + u) : CGPoint(x: centre.x + u, y: centre.y + v)
    }
    /// A rectangle of it, by its middle and its sizes along the edge and away.
    func rect(u: CGFloat, v: CGFloat, along: CGFloat, away: CGFloat) -> CGRect {
        let c = point(u, v)
        return vertical ? CGRect(x: c.x - away / 2, y: c.y - along / 2, width: away, height: along)
                        : CGRect(x: c.x - along / 2, y: c.y - away / 2, width: along, height: away)
    }
    /// A point of the screen in its terms.
    func local(_ p: CGPoint) -> (u: CGFloat, v: CGFloat) {
        vertical ? (p.y - centre.y, p.x - centre.x) : (p.x - centre.x, p.y - centre.y)
    }
    /// The grate's bars (11-11: six, were nine — a card on its edge
    /// has to go between two of them), the gap between two, and the middle
    /// of the gap nearest `u`.
    static let grateBars = 6
    var grateGapWidth: CGFloat { length / CGFloat(Self.grateBars + 1) * 0.66 }
    func grateGap(near u: CGFloat) -> CGFloat {
        let pitch = length / CGFloat(Self.grateBars + 1)
        let index = min(CGFloat(Self.grateBars), max(0, ((u + length / 2) / pitch).rounded(.down)))
        return -length / 2 + (index + 0.5) * pitch
    }
    /// The manhole: half as long along the edge, half as deep (round, seen
    /// from where the floor is seen).
    var manhole: (a: CGFloat, b: CGFloat) { (min(length * 0.26, depth * 1.15), depth * 0.42) }
    /// The sofa's seam at its widest.
    var seam: CGFloat { length * 0.17 }
}

/// The deletion's layers, bottom to top: what is in the floor; the card's
/// loose blocks; what lies over those (a grate's bars, the cushions, a
/// manhole's cover); the card's whole part; what works on the card (the
/// eraser, the scissors). The shelf draws them over the stage; 主题's
/// preview draws them small (DeleteStyleDemo).
struct DeleteLayers: View {
    var style: DeleteStyle
    var geometry: ShelfGeometry
    var theme: LibraryTheme
    var moment: CardShelfView.DeleteMoment?
    /// The card's face, flat (over the edge; in a render or a preview, all
    /// the while).
    var crumble: CardShelfView.Crumble?
    var previewBurst: Double? = nil
    /// The scene while the solid in the hand is whole: the things in the
    /// floor are not drawn over it (they lie behind it).
    var hand: ShelfScene? = nil
    /// The solid is in the hand all the while the card is held (a way that
    /// keeps the card whole, on the shelf itself): its flat face is drawn
    /// only once it is let go. (A render, 主题's preview: no solid; the flat
    /// face stands for it.)
    var solid = false
    /// How much smaller the card is when it is all loose (a card lowered
    /// toward the thing in the floor: DeleteStyle.lowersCard; else 0).
    var lowering: Double = 0
    /// How far the card's blocks move (1: as on the shelf; 主题's small
    /// preview: its card's size to the shelf's).
    var motion: Double = 1

    var body: some View {
        let split = style.layers.contains(.over)
        ZStack(alignment: .topLeading) {
            if let moment, style.layers.contains(.under) { prop(.under, moment) }
            if let crumble { face(crumble, split ? .loose : .all) }
            if let moment, split { prop(.over, moment) }
            if let crumble, split { face(crumble, .whole) }
            if let moment, style.layers.contains(.top) { prop(.top, moment) }
        }
        .frame(width: geometry.optics.viewSize.width, height: geometry.optics.viewSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    private func prop(_ layer: DeletePropView.Layer, _ moment: CardShelfView.DeleteMoment) -> some View {
        DeletePropView(style: style, layer: layer, geometry: geometry, theme: theme, moment: moment, hand: hand)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
    private func face(_ state: CardShelfView.Crumble, _ part: PixelCardView.Part) -> some View {
        PixelCardView(card: state.card, rect: state.rect, front: min(1, state.progress), vertical: geometry.vertical,
                      burst: state.burst, previewBurst: previewBurst, style: style, part: part, slot: DeleteSlot(geometry: geometry), motion: motion,
                      solid: solid, lowering: lowering)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// What a deleted card goes into, drawn (one layer of it): the bin's well
/// and the eraser are their own views (as they were); the grate, the sofa's
/// seam, the manhole and the scissors are drawn here.
struct DeletePropView: View {
    enum Layer { case under, over, top }
    var style: DeleteStyle
    var layer: Layer
    var geometry: ShelfGeometry
    var theme: LibraryTheme
    var moment: CardShelfView.DeleteMoment
    var hand: ShelfScene? = nil

    private var s: CGFloat { geometry.s }
    private var vertical: Bool { geometry.vertical }
    private var slot: DeleteSlot { DeleteSlot(geometry: geometry) }
    private static let warm = Color(red: 0.93, green: 0.36, blue: 0.26)
    private static let iron = Color(red: 0.31, green: 0.32, blue: 0.34)
    private static let ironLight = Color(red: 0.52, green: 0.53, blue: 0.55)
    private static let ironDark = Color(red: 0.15, green: 0.16, blue: 0.18)

    var body: some View {
        switch style {
        case .bin:
            DeleteWellView(geometry: geometry, theme: theme, near: moment.near, progress: moment.progress)
        case .eraser:
            EraserView(geometry: geometry, near: moment.near, progress: moment.progress, card: moment.card, burst: moment.burst, previewBurst: moment.previewBurst)
        case .grate, .sofa, .scissors, .manhole:
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let quad = hand?.handQuad()
                Canvas(rendersAsynchronously: false) { context, _ in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    draw(&context, time: now, since: moment.previewBurst ?? moment.burst.map { now - $0.timeIntervalSinceReferenceDate }, quad: quad)
                }
            }
            .frame(width: geometry.optics.viewSize.width, height: geometry.optics.viewSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(_ context: inout GraphicsContext, time: Double, since: Double?, quad: [CGPoint]?) {
        // Going, once the game has left the library.
        if let since, since > style.burstTime { context.opacity = max(0, 1 - (since - style.burstTime) / style.tailTime) }
        // The solid in the hand, whole, is in front of what is in the floor.
        if layer != .top, since == nil, let quad, quad.count == 4 {
            var outside = Path(CGRect(origin: .zero, size: geometry.optics.viewSize))
            var face = Path()
            face.move(to: quad[0])
            for corner in quad.dropFirst() { face.addLine(to: corner) }
            face.closeSubpath()
            outside.addPath(face)
            context.clip(to: outside, style: FillStyle(eoFill: true))
        }
        switch (style, layer) {
        case (.grate, .under): gratePit(&context, since: since)
        case (.grate, .over): grateBars(&context, since: since)
        case (.sofa, .under): sofaSeam(&context, since: since)
        case (.sofa, .over): sofaCushions(&context, since: since)
        case (.manhole, .under): manholeShaft(&context, since: since)
        case (.manhole, .over): manholeCover(&context, since: since)
        case (.scissors, .top): scissors(&context, time: time, since: since)
        default: break
        }
    }

    /// The light from below: faint while the card is far, brighter near,
    /// warm once the card is all loose (let go there and it is gone), going
    /// out once the blocks are in.
    private func glow(_ cool: Color, since: Double?) -> (color: Color, strength: Double) {
        let armed = moment.progress >= 1 || since != nil
        var strength = armed ? 1.0 : 0.2 + 0.35 * moment.near + 0.35 * moment.progress
        if let since { strength = max(0.25, 1 - max(0, since - 0.5) / 0.25) }
        return (armed ? Self.warm : cool, strength)
    }
    private func smooth(_ x: Double) -> CGFloat { let k = min(1, max(0, x)); return CGFloat(k * k * (3 - 2 * k)) }

    // MARK: The grate (下水道格栅)

    /// The pit under the bars: dark, a light in it.
    private func gratePit(_ context: inout GraphicsContext, since: Double?) {
        let slot = self.slot
        let shape = Path(roundedRect: slot.rect(u: 0, v: 0, along: slot.length, away: slot.depth), cornerRadius: 5 * s)
        context.fill(shape, with: .color(Color(red: 0.05, green: 0.06, blue: 0.07)))
        let g = glow(Color(red: 0.62, green: 0.90, blue: 0.72), since: since)
        context.fill(shape, with: .radialGradient(Gradient(colors: [g.color.opacity(0.6 * g.strength), g.color.opacity(0)]),
                                                  center: slot.point(0, slot.depth * 0.3), startRadius: 0, endRadius: slot.length * 0.5))
    }
    /// The bars over it (the card goes down between two of them, on its
    /// edge), one across the middle, an iron frame round; the card in, drops
    /// of water come up between the bars where it went.
    private func grateBars(_ context: inout GraphicsContext, since: Double?) {
        let slot = self.slot, length = slot.length, depth = slot.depth
        let pitch = length / CGFloat(DeleteSlot.grateBars + 1)
        for i in 1...DeleteSlot.grateBars {
            let u = -length / 2 + CGFloat(i) * pitch
            context.fill(Path(slot.rect(u: u, v: 0, along: pitch * 0.34, away: depth)), with: .color(Self.iron))
            context.fill(Path(slot.rect(u: u - pitch * 0.12, v: 0, along: pitch * 0.07, away: depth)), with: .color(Self.ironLight.opacity(0.7)))
        }
        context.fill(Path(slot.rect(u: 0, v: 0, along: length, away: depth * 0.13)), with: .color(Self.iron))
        context.fill(Path(slot.rect(u: 0, v: -depth * 0.05, along: length, away: depth * 0.025)), with: .color(Self.ironLight.opacity(0.6)))
        let frame = Path(roundedRect: slot.rect(u: 0, v: 0, along: length, away: depth), cornerRadius: 5 * s)
        context.stroke(frame, with: .color(Self.ironDark), lineWidth: 5 * s)
        context.stroke(frame, with: .color(Self.ironLight.opacity(0.55)), lineWidth: 1.2 * s)
        // The splash: a few drops up out of the gap the card went down,
        // toward the shelf and back.
        let landed = DeleteStyle.turnTime + DeleteStyle.slipTime * 0.8
        if let since, since > landed {
            let t = since - landed
            let gap = slot.grateGap(near: slot.local(CGPoint(x: moment.card.midX, y: moment.card.midY)).u)
            for i in 0..<7 {
                let seed = Double(i) * 0.6180339887
                let a = (seed * 3.7).truncatingRemainder(dividingBy: 1), b = (seed * 7.3).truncatingRemainder(dividingBy: 1)
                let alpha = max(0, 0.9 - t * 3)
                guard alpha > 0.02 else { continue }
                let rise = CGFloat((120 + 110 * a) * t - 420 * t * t) * s
                let size = CGFloat(3 + 3 * a) * s
                let p = slot.point(gap + CGFloat((b - 0.5) * 120 * t) * s, -rise)
                context.fill(Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)),
                             with: .color(Color(red: 0.72, green: 0.88, blue: 0.92).opacity(alpha)))
            }
        }
    }

    // MARK: The sofa's seam (沙发缝)

    /// How far the seam stands open: a line while the card is far, open as
    /// it comes near; the blocks in, it shuts.
    private func seamGap(_ since: Double?) -> CGFloat {
        var open = smooth(moment.near)
        if let since { open = 1 - smooth((since - 0.6) / 0.18) }
        return 2 * s + slot.seam * open
    }
    /// Inside the seam: dark (warm once the card is all loose).
    private func sofaSeam(_ context: inout GraphicsContext, since: Double?) {
        let slot = self.slot
        let inside = Path(slot.rect(u: 0, v: 0, along: seamGap(since) + 8 * s, away: slot.depth * 0.84))
        context.fill(inside, with: .color(Color(red: 0.09, green: 0.06, blue: 0.05)))
        if moment.progress >= 1 || since != nil {
            context.fill(inside, with: .color(Self.warm.opacity(0.4 * glow(.clear, since: since).strength)))
        }
    }
    /// The two cushions, one each side of the seam (the blocks go down
    /// between them); shut again, they give once, and dust comes up.
    private func sofaCushions(_ context: inout GraphicsContext, since: Double?) {
        let slot = self.slot, depth = slot.depth
        let gap = seamGap(since)
        let width = (slot.length - 2 * s) / 2
        var give: CGFloat = 0
        if let since, since > 0.78 { give = CGFloat(sin(min(1, (since - 0.78) / 0.14) * Double.pi)) * 0.07 }
        let leather = Color(red: 0.55, green: 0.36, blue: 0.24)
        for side in [CGFloat(-1), CGFloat(1)] {
            let rect = slot.rect(u: side * (gap / 2 + width / 2), v: 0, along: width, away: depth * (1 - give))
            let radius = min(rect.width, rect.height) * 0.3
            let shape = Path(roundedRect: rect, cornerRadius: radius)
            var shadow = context
            shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 5 * s, x: 0, y: 3 * s))
            shadow.fill(shape, with: .color(leather))
            context.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.66, green: 0.46, blue: 0.31), Color(red: 0.44, green: 0.28, blue: 0.18)]),
                                                      startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            context.stroke(shape, with: .color(Color(red: 0.29, green: 0.17, blue: 0.10)), lineWidth: 1.5 * s)
            // The stitching, a little way in.
            let inset = min(5 * s, min(rect.width, rect.height) * 0.16)
            let stitch = Path(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: max(1, radius - inset))
            context.stroke(stitch, with: .color(Color(red: 0.88, green: 0.73, blue: 0.55).opacity(0.75)),
                           style: StrokeStyle(lineWidth: max(0.8, 1 * s), lineCap: .round, dash: [3 * s, 3 * s]))
        }
        // Dust out of the seam as it shuts: pale blocks, up toward the shelf.
        if let since, since > 0.66 {
            let t = since - 0.66
            for i in 0..<18 {
                let seed = Double(i) * 0.6180339887
                let a = (seed * 3.7).truncatingRemainder(dividingBy: 1), b = (seed * 7.3).truncatingRemainder(dividingBy: 1)
                let alpha = max(0, 0.95 - t * 2.6)
                guard alpha > 0.02 else { continue }
                let rise = CGFloat((90 + 130 * a) * t - 150 * t * t) * s
                let size = CGFloat(3 + 3.5 * a) * s
                let p = slot.point(CGFloat((b - 0.5) * 200 * t) * s, -depth * 0.3 - rise)
                context.fill(Path(CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)),
                             with: .color(Color(red: 0.80, green: 0.72, blue: 0.62).opacity(alpha)))
            }
        }
    }

    // MARK: The manhole (井盖)

    private func ellipse(u: CGFloat, v: CGFloat, a: CGFloat, b: CGFloat) -> Path {
        Path(ellipseIn: slot.rect(u: u, v: v, along: a * 2, away: b * 2))
    }
    /// How far the cover has slid off the shaft (0: on it; 1: clear of it):
    /// off as the card comes near, back once the blocks are in.
    private func coverSlide(_ since: Double?) -> CGFloat {
        if let since { return 1 - smooth((since - 0.6) / 0.26) }
        return smooth(moment.near)
    }
    /// The shaft and its rim in the floor: dark, a light far down.
    private func manholeShaft(_ context: inout GraphicsContext, since: Double?) {
        let (a, b) = slot.manhole
        context.fill(ellipse(u: 0, v: 0, a: a + 5 * s, b: b + 3.5 * s), with: .color(Self.ironDark))
        context.fill(ellipse(u: 0, v: 0, a: a + 2.2 * s, b: b + 1.6 * s), with: .color(Self.ironLight.opacity(0.8)))
        let shaft = ellipse(u: 0, v: 0, a: a, b: b)
        context.fill(shaft, with: .color(Color(red: 0.03, green: 0.04, blue: 0.06)))
        let g = glow(Color(red: 0.50, green: 0.72, blue: 1.0), since: since)
        context.fill(shaft, with: .radialGradient(Gradient(colors: [g.color.opacity(0.65 * g.strength), g.color.opacity(0)]),
                                                  center: slot.point(0, b * 0.35), startRadius: 0, endRadius: a))
    }
    /// The cover: cast iron, two rings and the bars between them, two holes
    /// for the hook; slid along the edge off the shaft; back on, it settles.
    private func manholeCover(_ context: inout GraphicsContext, since: Double?) {
        let (a, b) = slot.manhole
        var settle: CGFloat = 0
        if let since, since > 0.86 { settle = CGFloat(sin(min(1, (since - 0.86) / 0.1) * Double.pi)) * 1.6 * s }
        let u = coverSlide(since) * a * 1.9, v = -settle
        let lid = ellipse(u: u, v: v, a: a, b: b)
        var shadow = context
        shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: 4 * s, x: 0, y: 2.5 * s))
        shadow.fill(lid, with: .color(Self.iron))
        let top = slot.rect(u: u, v: v, along: a * 2, away: b * 2)
        context.fill(lid, with: .linearGradient(Gradient(colors: [Self.ironLight, Self.iron]),
                                                startPoint: CGPoint(x: top.midX, y: top.minY), endPoint: CGPoint(x: top.midX, y: top.maxY)))
        context.stroke(lid, with: .color(Self.ironDark), lineWidth: 1.5 * s)
        context.stroke(ellipse(u: u, v: v, a: a * 0.78, b: b * 0.78), with: .color(Self.ironDark.opacity(0.8)), lineWidth: 1.2 * s)
        context.stroke(ellipse(u: u, v: v, a: a * 0.45, b: b * 0.45), with: .color(Self.ironDark.opacity(0.7)), lineWidth: 1.2 * s)
        for i in 0..<12 {
            let angle = Double(i) / 12 * 2 * Double.pi
            var bar = Path()
            bar.move(to: slot.point(u + a * 0.50 * CGFloat(cos(angle)), v + b * 0.50 * CGFloat(sin(angle))))
            bar.addLine(to: slot.point(u + a * 0.73 * CGFloat(cos(angle)), v + b * 0.73 * CGFloat(sin(angle))))
            context.stroke(bar, with: .color(Self.ironDark.opacity(0.75)), lineWidth: 1.4 * s)
        }
        for side in [CGFloat(-1), CGFloat(1)] {
            context.fill(ellipse(u: u + side * a * 0.22, v: v, a: a * 0.055, b: b * 0.1), with: .color(.black.opacity(0.7)))
        }
    }

    // MARK: The scissors (小剪刀)

    /// A small pair (four tenths of a card long), red handles, in the top
    /// layer. They cut along the shelf's edge, across the middle of the
    /// card, from its side (a row: from the left; a column: from above):
    /// under the card's far edge there is no room for them, and the hand is
    /// there. Far from the edge they lie shut in the floor to that side; as
    /// the card comes near they come up to its side and open; over the edge
    /// they snip at it, and a dashed line across the card says how far it
    /// has to go; let go all loose, they cut across the card
    /// (DeleteStyle.scissorsCut) and are gone, the halves parting behind
    /// them (PixelCardView).
    private func scissors(_ context: inout GraphicsContext, time: Double, since: Double?) {
        let slot = self.slot, card = moment.card
        let size = geometry.optics.cardWidth * 0.4
        let blade = size * 0.55
        // The way they cut, where the cut starts, how long it is.
        let along = vertical ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0)
        let start = vertical ? CGPoint(x: card.midX, y: card.minY) : CGPoint(x: card.minX, y: card.midY)
        let span = vertical ? card.height : card.width
        let follow = smooth((moment.near - 0.25) / 0.75)
        let rest = slot.point(-slot.length * 0.3, 0)
        // Their tips just on the card's side, the pivot a blade's length out.
        let at = CGPoint(x: start.x - along.dx * blade * 0.9, y: start.y - along.dy * blade * 0.9)
        var pivot = CGPoint(x: rest.x + (at.x - rest.x) * follow, y: rest.y + (at.y - rest.y) * follow)
        var open = 3 + 21 * Double(follow)          // each blade, degrees off the middle
        var alpha = 1.0
        if let since {
            // Across the card, snipping; past its other side, gone.
            let run = CGFloat(min(1.25, since / DeleteStyle.scissorsCut))
            pivot = CGPoint(x: at.x + along.dx * span * run, y: at.y + along.dy * span * run)
            open = 5 + 20 * abs(sin(since * 34))
            alpha = max(0, 1 - max(0, since - DeleteStyle.scissorsCut) / 0.16)
        } else if moment.progress > 0 {
            let beat = abs(sin(time * (5 + 6 * moment.progress)))
            open = (moment.progress >= 1 ? 27 : 24) * (0.3 + 0.7 * beat)
            pivot.x += along.dx * CGFloat(beat) * 3 * s
            pivot.y += along.dy * CGFloat(beat) * 3 * s
            // How far it has to go: a dashed line across the card.
            var line = Path()
            line.move(to: start)
            line.addLine(to: CGPoint(x: start.x + along.dx * span * CGFloat(moment.progress), y: start.y + along.dy * span * CGFloat(moment.progress)))
            context.stroke(line, with: .color((moment.progress >= 1 ? Self.warm : Color.white).opacity(0.9)),
                           style: StrokeStyle(lineWidth: max(1.5, 2 * s), lineCap: .round, dash: [5 * s, 5 * s]))
        }
        guard alpha > 0 else { return }
        var tool = context
        tool.opacity = alpha
        tool.translateBy(x: pivot.x, y: pivot.y)
        // Drawn pointing up; turned to point along the edge (a row: to the
        // right; a column: down).
        tool.rotate(by: .degrees(vertical ? 180 : 90))
        let steel = Color(red: 0.82, green: 0.84, blue: 0.87), edge = Color(red: 0.42, green: 0.45, blue: 0.50)
        let red = Color(red: 0.86, green: 0.22, blue: 0.20)
        for side in [CGFloat(-1), CGFloat(1)] {
            var half = tool
            half.rotate(by: .degrees(Double(side) * open))
            // The handle: a shank down from the pivot, a ring at its end
            // (set out to its own side).
            let ring = CGRect(x: -side * size * 0.07 - size * 0.085, y: size * 0.22, width: size * 0.17, height: size * 0.23)
            var shank = Path()
            shank.move(to: .zero)
            shank.addLine(to: CGPoint(x: -side * size * 0.05, y: size * 0.24))
            var shadow = half
            shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 3 * s, x: 0, y: 2 * s))
            shadow.stroke(shank, with: .color(red), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
            shadow.stroke(Path(ellipseIn: ring), with: .color(red), lineWidth: size * 0.055)
            // The blade: a long steel point.
            var steelPath = Path()
            steelPath.move(to: CGPoint(x: -size * 0.055, y: size * 0.03))
            steelPath.addLine(to: CGPoint(x: 0, y: -blade))
            steelPath.addLine(to: CGPoint(x: size * 0.055, y: size * 0.03))
            steelPath.closeSubpath()
            shadow.fill(steelPath, with: .color(steel))
            half.stroke(steelPath, with: .color(edge), lineWidth: max(0.8, 0.9 * s))
        }
        tool.fill(Path(ellipseIn: CGRect(x: -size * 0.03, y: -size * 0.03, width: size * 0.06, height: size * 0.06)), with: .color(edge))
    }
}

// MARK: - The well under the shelf (11-07, 删除)

/// Shown while a card that can be deleted is in the hand: where a card taken
/// over the shelf's edge goes. A dark trough along the edge (under a row,
/// right of a column) with a dashed line at the edge itself, a small bin
/// built of pixel blocks in the middle of it, its lid lifting as the card
/// comes near, and loose blocks drifting up out of it. Dim while the card
/// is far, bright near the edge, warm once the card is all loose (let go
/// there and it bursts). No words: the bin says it.
struct DeleteWellView: View {
    var geometry: ShelfGeometry
    var theme: LibraryTheme
    /// 0 far … 1 at the edge.
    var near: Double
    /// Over the edge, 0 … 1 (all loose at 1).
    var progress: Double

    private var s: CGFloat { geometry.s }
    private var vertical: Bool { geometry.vertical }
    private static let warm = Color(red: 0.93, green: 0.36, blue: 0.26)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas(rendersAsynchronously: false) { context, _ in
                draw(&context, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: geometry.optics.viewSize.width, height: geometry.optics.viewSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The trough along the edge, inside the shelf's frame.
    private var trough: CGRect {
        let flow = geometry.flow
        if vertical {
            let x = flow.maxX - geometry.optics.cardWidth * 0.45 - 6 * s
            return CGRect(x: x, y: flow.minY + 24 * s, width: flow.maxX - x - 6 * s, height: flow.height - 48 * s)
        }
        let y = geometry.optics.floorY + 8 * s
        return CGRect(x: flow.minX + 24 * s, y: y, width: flow.width - 48 * s, height: max(20 * s, flow.maxY - y - 8 * s))
    }
    /// The edge itself (CardShelfView.shelfEdge): a row's floor line, a
    /// little below it; a column's line short of its right edge.
    private var edge: CGFloat {
        vertical ? geometry.flow.maxX - geometry.optics.cardWidth * 0.45 : geometry.optics.floorY + 22 * s
    }

    private func draw(_ context: inout GraphicsContext, time: Double) {
        let t = trough
        let glow = progress >= 1 ? 1.0 : 0.0
        let tint = glow > 0 ? Self.warm : theme.ink
        let lift = 0.35 + 0.65 * near
        // The trough: darker away from the shelf.
        let troughPath = Path(roundedRect: t, cornerRadius: 12 * s)
        let shade = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [theme.ink.opacity(0.04 * lift), theme.ink.opacity(0.20 * lift)]),
            startPoint: vertical ? CGPoint(x: t.minX, y: t.midY) : CGPoint(x: t.midX, y: t.minY),
            endPoint: vertical ? CGPoint(x: t.maxX, y: t.midY) : CGPoint(x: t.midX, y: t.maxY))
        context.fill(troughPath, with: shade)
        if glow > 0 {
            context.fill(troughPath, with: .color(Self.warm.opacity(0.10)))
        }
        // The edge: a dashed line, solid and warm once the card is all loose.
        var line = Path()
        if vertical {
            line.move(to: CGPoint(x: edge, y: t.minY + 6 * s)); line.addLine(to: CGPoint(x: edge, y: t.maxY - 6 * s))
        } else {
            line.move(to: CGPoint(x: t.minX + 6 * s, y: edge)); line.addLine(to: CGPoint(x: t.maxX - 6 * s, y: edge))
        }
        context.stroke(line, with: .color(tint.opacity(0.25 + 0.55 * near)),
                       style: StrokeStyle(lineWidth: max(1, 1.5 * s), lineCap: .round, dash: glow > 0 ? [] : [4 * s, 5 * s]))
        // The bin: pixel blocks, 7 wide by 8 tall; the lid the top two rows.
        let b = 4.6 * s
        let bin = vertical ? CGPoint(x: t.midX - 3.5 * b, y: t.midY - 4 * b) : CGPoint(x: t.midX - 3.5 * b, y: t.midY - 4.6 * b)
        let body: [(Int, Int)] = {
            var cells: [(Int, Int)] = []
            for row in 2...7 { for col in 1...5 where !(col == 3 && row >= 3 && row <= 6) { cells.append((col, row)) } }
            return cells
        }()
        let lid: [(Int, Int)] = (0...6).map { ($0, 1) } + [(3, 0)]
        let ink = tint.opacity(0.45 + 0.5 * near)
        for (col, row) in body {
            context.fill(Path(CGRect(x: bin.x + CGFloat(col) * b, y: bin.y + CGFloat(row) * b, width: b - 1, height: b - 1)), with: .color(ink))
        }
        // The slot in the bin's front, a little lighter: the blocks go in there.
        for row in 3...6 {
            context.fill(Path(CGRect(x: bin.x + 3 * b, y: bin.y + CGFloat(row) * b, width: b - 1, height: b - 1)), with: .color(tint.opacity(0.18 + 0.2 * near)))
        }
        // The lid tips up and back as the card comes near (about its left end).
        var lidContext = context
        let hinge = CGPoint(x: bin.x, y: bin.y + 2 * b)
        lidContext.translateBy(x: hinge.x, y: hinge.y)
        lidContext.rotate(by: .degrees(-38 * near))
        lidContext.translateBy(x: -hinge.x, y: -hinge.y)
        for (col, row) in lid {
            lidContext.fill(Path(CGRect(x: bin.x + CGFloat(col) * b, y: bin.y + CGFloat(row) * b, width: b - 1, height: b - 1)), with: .color(ink))
        }
        // Loose blocks drifting up out of the bin (faster, brighter, the nearer).
        let rise = 46 * s * CGFloat(0.6 + 0.4 * near)
        for i in 0..<14 {
            let seed = Double(i) * 0.6180339887
            let phase = (seed * 7.13).truncatingRemainder(dividingBy: 1)
            let speed = (0.14 + 0.1 * (seed * 3.3).truncatingRemainder(dividingBy: 1)) * (1 + 0.8 * near + progress)
            let u = (time * speed + phase).truncatingRemainder(dividingBy: 1)
            let sway = CGFloat(sin(time * 1.7 + seed * 9)) * 5 * s
            let size = CGFloat(2.2 + 2.2 * (seed * 5.7).truncatingRemainder(dividingBy: 1)) * s
            let x = bin.x + 3.5 * b + CGFloat((seed * 2.9).truncatingRemainder(dividingBy: 1) - 0.5) * 7 * b + sway
            let y = bin.y + 2 * b - CGFloat(u) * rise
            // Far from the edge only a few blocks drift; near it, all of them.
            guard i < 6 || near > 0.3 else { continue }
            let alpha = (1 - u) * (0.25 + 0.6 * near)
            guard alpha > 0.02 else { continue }
            context.fill(Path(CGRect(x: x, y: y, width: size, height: size)), with: .color(tint.opacity(alpha)))
        }
    }
}

// MARK: - The eraser (11-07, 删除)

/// Shown while a card that can be deleted is in the hand: a school eraser
/// (white rubber, a blue paper sleeve) lying under the shelf (a row: below
/// the floor; a column: right of it). As the card comes near it rises to
/// meet the card's far edge and tilts; over the edge it rubs back and forth
/// along that edge, and the loose blocks of the card (PixelCardView) are
/// what it rubs off, with pale crumbs round it; let go all loose, it rubs
/// the card out stroke by stroke (EraseStrokes) and the card is gone (as a
/// wrong word or a spoilt drawing is rubbed out; the crumbs are the pixels).
struct EraserView: View {
    var geometry: ShelfGeometry
    /// 0 far … 1 at the edge.
    var near: Double
    /// Over the edge, 0 … 1 (all loose at 1).
    var progress: Double
    /// The card's face on the screen.
    var card: CGRect
    /// Let go all loose: since when (the strokes start then).
    var burst: Date?
    /// Renders: this far into the strokes, still.
    var previewBurst: Double?

    private var s: CGFloat { geometry.s }
    private var vertical: Bool { geometry.vertical }
    /// The eraser's length and thickness, from the cards' size.
    private var length: CGFloat { geometry.optics.cardWidth * 0.46 }
    private var thick: CGFloat { length * 0.42 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas(rendersAsynchronously: false) { context, _ in
                let now = timeline.date.timeIntervalSinceReferenceDate
                draw(&context, time: now, erasing: previewBurst ?? burst.map { now - $0.timeIntervalSinceReferenceDate })
            }
        }
        .frame(width: geometry.optics.viewSize.width, height: geometry.optics.viewSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the eraser lies when the card is far: under the shelf's edge.
    private var rest: CGPoint {
        let flow = geometry.flow
        if vertical { return CGPoint(x: min(flow.maxX - thick * 0.7, flow.maxX - geometry.optics.cardWidth * 0.45 + thick * 0.9), y: flow.midY) }
        return CGPoint(x: flow.midX, y: min(flow.maxY - thick * 0.7, geometry.optics.floorY + 22 * s + thick * 0.9))
    }
    /// The card's far edge's middle: its foot (a row), its right edge (a column).
    private var foot: CGPoint { vertical ? CGPoint(x: card.maxX, y: card.midY) : CGPoint(x: card.midX, y: card.maxY) }

    private func draw(_ context: inout GraphicsContext, time: Double, erasing: Double?) {
        // Where it is: at rest far away; near, up against the card's far
        // edge, following the card; over the edge it rubs back and forth
        // along that edge; let go, it rubs the card out stroke by stroke
        // (EraseStrokes), then goes.
        let follow = CGFloat(min(1, max(0, (near - 0.25) / 0.75)))
        var centre: CGPoint
        if vertical {
            centre = CGPoint(x: rest.x + (foot.x + thick * 0.55 - rest.x) * follow, y: rest.y + (foot.y - rest.y) * follow)
        } else {
            centre = CGPoint(x: rest.x + (foot.x - rest.x) * follow, y: rest.y + (foot.y + thick * 0.55 - rest.y) * follow)
        }
        var tilt = -8.0 + 20 * near
        var alpha = 1.0
        if let erasing {
            let e = EraseStrokes.eraser(at: erasing)
            if !e.done {
                // On the card: its middle on the band being rubbed, its way
                // along it; a quick sway as it goes.
                let across = vertical ? card.height : card.width, span = vertical ? card.width : card.height
                if vertical {
                    centre = CGPoint(x: card.maxX - CGFloat(e.far) * span, y: card.minY + CGFloat(e.along) * across)
                } else {
                    centre = CGPoint(x: card.minX + CGFloat(e.along) * across, y: card.maxY - CGFloat(e.far) * span)
                }
                tilt = 10 + sin(erasing * 34) * 7
            } else {
                // Done: off and away, fading.
                let after = erasing - EraseStrokes.total
                let away = CGFloat(min(1, after / 0.3))
                if vertical { centre = CGPoint(x: card.minX + away * thick * 1.5, y: card.midY) } else { centre = CGPoint(x: card.midX, y: card.minY + away * thick * 1.5) }
                tilt = 10
                alpha = max(0, 1 - after / 0.3)
            }
        } else if progress > 0 {
            // Rubbing at the foot: along the card's edge, faster the looser.
            let rub = sin(time * (6 + 6 * progress)) * Double(length) * (0.18 + 0.2 * progress)
            if vertical { centre.y += CGFloat(rub) } else { centre.x += CGFloat(rub) }
            tilt += sin(time * (6 + 6 * progress) + 1.2) * 6
        }
        guard alpha > 0 else { return }
        // Crumbs round the rubbing: pale bits, more the looser; while the
        // strokes run they gather where the eraser has been.
        if progress > 0 || erasing != nil {
            let count = erasing == nil ? Int(6 + 22 * progress) : 30
            for i in 0..<count {
                let seed = Double(i) * 0.7548776662
                let u = (seed * 3.3).truncatingRemainder(dividingBy: 1), v = (seed * 7.1).truncatingRemainder(dividingBy: 1)
                var p: CGPoint
                var a = 0.5 + 0.4 * v
                var size = CGFloat(2.2 + 2.6 * (seed * 5.7).truncatingRemainder(dividingBy: 1)) * s
                if let erasing {
                    // Each crumb falls off the card where a stroke passed, a
                    // moment after.
                    let along = u, far = (seed * 1.7).truncatingRemainder(dividingBy: 1)
                    let t = erasing - EraseStrokes.passTime(along: along, far: far)
                    guard t > 0 else { continue }
                    let start = vertical ? CGPoint(x: card.maxX - CGFloat(far) * card.width, y: card.minY + CGFloat(along) * card.height)
                                         : CGPoint(x: card.minX + CGFloat(along) * card.width, y: card.maxY - CGFloat(far) * card.height)
                    let fall = CGFloat(60 * t + 700 * t * t), drift = CGFloat((v - 0.5) * 180 * t)
                    p = vertical ? CGPoint(x: start.x + fall, y: start.y + drift) : CGPoint(x: start.x + drift, y: start.y + fall)
                    a *= max(0, 1 - t * 1.6); size *= 1 - 0.3 * min(1, t * 2)
                } else {
                    var dx = CGFloat(u - 0.5) * length * 1.6, dy = CGFloat(v) * thick * (vertical ? 1.6 : 1.1)
                    if vertical { swap(&dx, &dy); dx = -dx }
                    p = CGPoint(x: foot.x + dx, y: foot.y + dy)
                }
                guard a > 0.02 else { continue }
                context.fill(Path(roundedRect: CGRect(x: p.x, y: p.y, width: size * 1.4, height: size), cornerRadius: size * 0.4),
                             with: .color(Color(red: 0.90, green: 0.87, blue: 0.80).opacity(a * alpha)))
            }
        }
        // The eraser itself.
        var body = context
        body.opacity = alpha
        body.translateBy(x: centre.x, y: centre.y)
        body.rotate(by: .degrees(tilt + (vertical ? 90 : 0)))
        let rect = CGRect(x: -length / 2, y: -thick / 2, width: length, height: thick)
        let shape = Path(roundedRect: rect, cornerRadius: thick * 0.18)
        var shadow = body
        shadow.addFilter(.shadow(color: .black.opacity(0.28), radius: 6 * s, x: 0, y: 4 * s))
        shadow.fill(shape, with: .color(Color(red: 0.96, green: 0.95, blue: 0.91)))
        // The rubbing end a little grey and worn.
        body.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.86, green: 0.84, blue: 0.79), Color(red: 0.97, green: 0.96, blue: 0.92)]),
                                               startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.minX + length * 0.4, y: 0)))
        // The paper sleeve over the back half, a dark band at its mouth.
        var sleeve = Path(roundedRect: CGRect(x: rect.minX + length * 0.42, y: rect.minY, width: length * 0.58, height: thick), cornerRadius: thick * 0.18)
        sleeve.addRect(CGRect(x: rect.minX + length * 0.42, y: rect.minY, width: thick * 0.3, height: thick))
        body.fill(sleeve, with: .color(Color(red: 0.28, green: 0.44, blue: 0.76)))
        body.fill(Path(CGRect(x: rect.minX + length * 0.42, y: rect.minY, width: 2.5 * s, height: thick)), with: .color(Color(red: 0.17, green: 0.29, blue: 0.56)))
        body.stroke(shape, with: .color(.black.opacity(0.22)), lineWidth: max(1, 1 * s))
        let mark = Text("ZERO").font(.system(size: thick * 0.3, weight: .heavy, design: .rounded)).foregroundColor(.white.opacity(0.9))
        body.draw(mark, at: CGPoint(x: rect.minX + length * 0.71, y: 0))
    }
}

/// 11-07: once the
/// card is let go all loose, the eraser rubs it out in strokes — across the
/// card's far band first, back across the next, and so on up (a row: from
/// the foot; a column: from the right edge) — and the card is gone where the
/// eraser has passed, its blocks flying off as crumbs. The card
/// (PixelCardView) and the eraser (EraserView) follow the same schedule.
enum EraseStrokes {
    static let strokes = 4
    static let stroke = 0.27
    /// All the strokes.
    static var total: Double { Double(strokes) * stroke }
    /// For a point of the card (`along` 0…1 across the stroke's way, `far`
    /// 0…1 from the card's far edge inward): when the eraser passes it.
    static func passTime(along: Double, far: Double) -> Double {
        let band = min(strokes - 1, max(0, Int(far * Double(strokes))))
        let forward = band % 2 == 0
        let frac = forward ? along : 1 - along
        return Double(band) * stroke + frac * stroke
    }
    /// Where the eraser's middle is at `t` seconds in: its way across
    /// (0…1) and its band from the far edge (0…1, the band's middle).
    static func eraser(at t: Double) -> (along: Double, far: Double, done: Bool) {
        if t >= total { return (1, 1, true) }
        let band = min(strokes - 1, Int(t / stroke))
        let frac = min(1, max(0, (t - Double(band) * stroke) / stroke))
        let eased = frac * frac * (3 - 2 * frac)
        let along = band % 2 == 0 ? eased : 1 - eased
        return (along, (Double(band) + 0.5) / Double(strokes), false)
    }
}

// MARK: - The card in pixels (11-07, 删除)

/// A card's face drawn flat, coming apart into square blocks from its far
/// side: `front` of it (from the foot in a row, from the right edge in a
/// column) is loose, the blocks there slipping away the deeper they are.
/// `burst` set, it goes the way of what it went into (11-11, DeleteStyle):
/// the bin — every block flies off and fades (about 0.7 s); the eraser —
/// rubbed out band by band (EraseStrokes). The other ways keep the card
/// whole (11-11; held, it is the solid in the hand, and nothing is
/// drawn here): the scissors cut it across the middle, the halves dropping
/// away; into the grate and the sofa's seam it slips on its edge; down the
/// manhole it drops, smaller as it falls.
struct PixelCardView: View {
    /// 11-11: what of the card a layer draws: all of it; or, where
    /// something lies between (a grate's bars, the cushions, a manhole's
    /// cover: the loose blocks go under it, the whole part stays over it),
    /// one of the two.
    enum Part { case all, whole, loose }
    var card: GameCardInfo
    var rect: CGRect
    var front: Double
    var vertical: Bool
    var burst: Date?
    /// Renders: this far into the burst, still.
    var previewBurst: Double?
    /// 11-11: what the card goes into (how it goes once let go).
    var style: DeleteStyle = .bin
    var part: Part = .all
    /// Where the thing in the floor is (a burst card's blocks go there).
    var slot: DeleteSlot? = nil
    /// How far the blocks slip and fly, to the shelf's own (1; the
    /// distances are in points, for a card as the shelf holds it).
    var motion: Double = 1
    /// The solid is in the hand while the card is held (see DeleteLayers):
    /// a card that stays whole is not drawn until it is let go.
    var solid = false
    /// A card lowered toward the thing in the floor: this much smaller when
    /// all loose. (The solid is lowered in the scene, and `rect` is its
    /// face as it is; with no solid — a render, 主题's preview — `rect` is
    /// the card at its full size, and the lowering is done here.)
    var lowering: Double = 0

    /// Blocks across the card's width (a row) or down its height (a column).
    static let across = 10

    var body: some View {
        if burst != nil, previewBurst == nil {
            TimelineView(.animation) { timeline in
                canvas(time: burst.map { timeline.date.timeIntervalSince($0) } ?? 0)
            }
        } else {
            canvas(time: previewBurst ?? 0)
        }
    }
    /// A face's shape in black (the face's own alpha), by the card's key:
    /// drawn over the face, however faintly, it dims it. (11-11: without a
    /// filter — `.brightness` on the card going down the manhole took half a
    /// second of frames on the 17e simulator, job 1115.)
    private static var shades: [String: CGImage] = [:]
    private static func shade(_ card: GameCardInfo, face: CGImage) -> CGImage? {
        let key = CardArtPrints.key(card)
        if let image = shades[key] { return image }
        guard let context = CGContext(data: nil, width: face.width, height: face.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let all = CGRect(x: 0, y: 0, width: face.width, height: face.height)
        context.draw(face, in: all)
        context.setBlendMode(.sourceAtop)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(all)
        guard let image = context.makeImage() else { return nil }
        if shades.count >= 12 { shades.removeAll() }
        shades[key] = image
        return image
    }

    private func canvas(time: Double) -> some View {
        let face = CardArtPrints.face(card)
        let grid = CardArtPrints.blocks(card, across: Self.across)
        // (Only a card dropped into the floor is dimmed as it goes.)
        let dark = style.lowersCard && burst != nil ? face.flatMap { Self.shade(card, face: $0) } : nil
        return Canvas(rendersAsynchronously: false) { context, _ in
            guard let face, let grid else { return }
            let image = Image(decorative: face, scale: 1)
            let shade = dark.map { Image(decorative: $0, scale: 1) }
            // A card that stays whole: the scissors cut it once it is let
            // go; into the grate, the seam, the manhole it goes as a card.
            if style.keepsCardWhole {
                guard burst != nil else {
                    // Held: the solid itself; where there is none (a render,
                    // 主题's preview), the face, lowered as the solid would be.
                    let low = CGFloat(1 - lowering * min(1, front))
                    if !solid, part != .loose { drawCard(context, image: image, centre: CGPoint(x: rect.midX, y: rect.midY), along: low, away: low) }
                    return
                }
                // Let go: from the size it was lowered to.
                let low = solid ? 1 : CGFloat(1 - lowering)
                let card = CGRect(x: rect.midX - rect.width * low / 2, y: rect.midY - rect.height * low / 2, width: rect.width * low, height: rect.height * low)
                switch style {
                case .scissors: if part != .loose { cutInTwo(&context, image: image, grid: grid, time: time) }
                case .manhole: if part != .loose { downTheShaft(context, image: image, shade: shade, card: card, time: time) }
                default: slipIn(context, image: image, shade: shade, card: card, time: time)
                }
                return
            }
            let block = (vertical ? rect.height : rect.width) / CGFloat(Self.across)
            let bursting = burst != nil
            let span = vertical ? rect.width : rect.height
            if part != .loose {
                // The whole part, as it is: above the loose line while held;
                // being erased, what the eraser has not passed yet.
                var keep = Path()
                if !bursting {
                    keep.addRect(vertical ? CGRect(x: rect.minX, y: rect.minY, width: rect.width * (1 - front), height: rect.height)
                                          : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * (1 - front)))
                } else if style == .eraser {
                    let e = EraseStrokes.eraser(at: time)
                    if !e.done {
                        let band = Int(e.far * Double(EraseStrokes.strokes))
                        let bandFar = CGFloat(band + 1) / CGFloat(EraseStrokes.strokes) * span     // the band's inner edge, from the far side
                        // The bands not reached yet: all of them.
                        if vertical {
                            keep.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width - bandFar, height: rect.height))
                        } else {
                            keep.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - bandFar))
                        }
                        // The band being erased: the part ahead of the eraser.
                        let bandNear = bandFar - span / CGFloat(EraseStrokes.strokes)
                        let forward = band % 2 == 0
                        let across = vertical ? rect.height : rect.width
                        let front = CGFloat(e.along) * across
                        let ahead = forward ? CGRect(x: front, y: 0, width: across - front, height: 1) : CGRect(x: 0, y: 0, width: front, height: 1)
                        if vertical {
                            keep.addRect(CGRect(x: rect.maxX - bandFar, y: rect.minY + ahead.minX, width: bandFar - bandNear, height: ahead.width))
                        } else {
                            keep.addRect(CGRect(x: rect.minX + ahead.minX, y: rect.maxY - bandFar, width: ahead.width, height: bandFar - bandNear))
                        }
                    }
                }
                if !keep.isEmpty {
                    var whole = context
                    whole.clip(to: keep)
                    whole.addFilter(.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6))
                    whole.draw(image, in: rect)
                }
            }
            guard part != .whole else { return }
            // The loose blocks.
            let line = span * (1 - front)
            for b in grid.samples {
                let cx = (CGFloat(b.column) + 0.5) * block, cy = (CGFloat(b.row) + 0.5) * block
                let far = vertical ? cx : cy            // along the away axis, from the card's near side
                var dx = 0.0, dy = 0.0, alpha = 1.0, size = Double(block) - 2.5 * motion
                if bursting {
                    switch style {
                    case .eraser:
                        // Off as a crumb once the eraser has passed it.
                        let along = Double(vertical ? cy / rect.height : cx / rect.width)
                        let fromFar = 1 - Double(far / span)
                        let t = time - EraseStrokes.passTime(along: along, far: fromFar)
                        guard t > 0 else { continue }
                        let fly = (b.vy * 160 * t + 900 * t * t) * motion
                        let drift = b.vx * 220 * t * motion
                        if vertical { dx = fly; dy = drift } else { dx = drift; dy = fly }
                        alpha = max(0, 1 - 2.2 * t)
                        size *= 1 - 0.5 * min(1, t * 2.5)
                    default:
                        // The bin (b76k): every block flies off and fades.
                        let t = max(0, time - b.delay * 0.45)
                        let fly = (b.vy * 420 * t + 1100 * t * t - 30 * t) * motion
                        let drift = b.vx * 320 * t * motion
                        if vertical { dx = fly; dy = drift } else { dx = drift; dy = fly }
                        alpha = max(0, 1 - 1.5 * t)
                        size *= 1 - 0.45 * min(1, t * 1.7)
                    }
                } else {
                    guard far > line else { continue }
                    let depth = min(1, max(0, (far - line) / max(1, span * front)))
                    let slip = (b.vy * 24 + 6) * depth * front * motion
                    let drift = b.vx * 9 * depth * front * motion
                    if vertical { dx = slip; dy = drift } else { dx = drift; dy = slip }
                    alpha = 1 - 0.5 * depth * front
                    size -= 5 * depth * front * motion
                }
                guard alpha > 0.02, size > 1 else { continue }
                let x = rect.minX + cx - size / 2 + dx, y = rect.minY + cy - size / 2 + dy
                context.fill(Path(CGRect(x: x, y: y, width: size, height: size)), with: .color(b.color.opacity(alpha)))
            }
        }
        .accessibilityHidden(true)
    }

    /// The card's face at `centre`, as wide (along the shelf's edge) and
    /// as tall (away from it) as given, to its own size; turned; dimmer;
    /// inside `clip`. `edge` (0 … 1): seen on its edge, the shell's side
    /// stands for the face.
    private func drawCard(_ context: GraphicsContext, image: Image, shade: Image? = nil, centre: CGPoint, along: CGFloat = 1, away: CGFloat = 1,
                          turn: Double = 0, dim: Double = 0, alpha: Double = 1, clip: Path? = nil, shadow: Bool = true, edge: Double = 0) {
        // (`along` and `away` are to `rect`, the card's face as the view was given it.)
        var c = context
        if let clip { c.clip(to: clip) }
        c.translateBy(x: centre.x, y: centre.y)
        if turn != 0 { c.rotate(by: .degrees(turn)) }
        if shadow { c.addFilter(.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)) }
        if edge < 1 {
            var face = c
            face.opacity = alpha * (1 - edge)
            face.scaleBy(x: vertical ? away : along, y: vertical ? along : away)
            face.translateBy(x: -rect.midX, y: -rect.midY)
            face.draw(image, in: rect)
            if dim > 0, let shade {
                face.opacity = alpha * (1 - edge) * dim
                face.draw(shade, in: rect)
            }
        }
        if edge > 0 {
            let w = (vertical ? rect.height : rect.width) * along, h = (vertical ? rect.width : rect.height) * away
            let slab = vertical ? CGRect(x: -h / 2, y: -w / 2, width: h, height: w) : CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let shape = Path(roundedRect: slab, cornerRadius: min(slab.width, slab.height) * 0.28)
            var side = c
            side.opacity = alpha * edge
            // The shell's side: grey, lit along one edge, the grip's ridges
            // at its near end (the card's top).
            side.fill(shape, with: .color(Color(red: 0.72, green: 0.73, blue: 0.76)))
            let lit = vertical ? CGRect(x: slab.minX, y: slab.minY + slab.height * 0.12, width: slab.width, height: slab.height * 0.2)
                               : CGRect(x: slab.minX + slab.width * 0.12, y: slab.minY, width: slab.width * 0.2, height: slab.height)
            side.fill(Path(lit), with: .color(.white.opacity(0.45)))
            for i in 1...4 {
                let at = CGFloat(i) * 0.035
                let ridge = vertical ? CGRect(x: slab.minX + slab.width * at, y: slab.minY, width: 1, height: slab.height)
                                     : CGRect(x: slab.minX, y: slab.minY + slab.height * at, width: slab.width, height: 1)
                side.fill(Path(ridge), with: .color(Color(red: 0.45, green: 0.47, blue: 0.51).opacity(0.8)))
            }
            side.stroke(shape, with: .color(Color(red: 0.45, green: 0.47, blue: 0.51)), lineWidth: 1)
            if dim > 0 { side.fill(shape, with: .color(.black.opacity(dim))) }
        }
    }

    /// 11-11 (the grate, the sofa's seam): let go, the card turns on its edge (DeleteStyle.turnTime)
    /// as it comes over the gap — the one between two bars under it, the
    /// seam — its far edge at the thing's near edge; then it slips in
    /// (DeleteStyle.slipTime), down by its own height and the thing's depth,
    /// dimmer as it goes. Above the thing's near edge it is in front of
    /// everything (the whole part's layer); past it, it shows in the gap
    /// only, under the bars and the cushions (the loose part's layer).
    private func slipIn(_ context: GraphicsContext, image: Image, shade: Image?, card: CGRect, time: Double) {
        guard let slot else { return }
        // (`card`: the face as it was let go — lowered; `low`: to `rect`.)
        let low = card.width / max(1, rect.width)
        let l = slot.local(CGPoint(x: card.midX, y: card.midY))
        let gap: CGFloat = style == .grate ? slot.grateGap(near: l.u) : 0
        let width: CGFloat = style == .grate ? slot.grateGapWidth : slot.seam
        let height = vertical ? card.width : card.height
        let thin = CGFloat(CardDimensions.thickness / CardDimensions.width)
        let a = min(1, max(0, time / DeleteStyle.turnTime)), turn = a * a * (3 - 2 * a)
        let d = min(1, max(0, (time - DeleteStyle.turnTime) / DeleteStyle.slipTime)), slip = d * d
        guard d < 1 else { return }
        // On its edge it is as thick as the gap is wide at most, and a
        // little smaller all over (further from the eye).
        let size = CGFloat(1 - 0.12 * turn)
        let squeeze = max(min(thin, width * 0.8 / max(1, vertical ? card.height : card.width)), CGFloat(cos(turn * Double.pi / 2)))
        let entry = -slot.depth / 2 - height * size / 2 + 2
        let v = l.v + (entry - l.v) * CGFloat(turn) + (height * size + slot.depth) * CGFloat(slip)
        let centre = slot.point(l.u + (gap - l.u) * CGFloat(turn), v)
        let edge = Double(min(1, max(0, (0.4 - squeeze) / 0.22)))
        if time < DeleteStyle.turnTime {
            // Still in the air: in front of everything.
            if part != .loose { drawCard(context, image: image, centre: centre, along: squeeze * size * low, away: size * low, edge: edge) }
            return
        }
        let near = slot.point(0, -slot.depth / 2)
        let far: CGFloat = 1500, wide = slot.length
        if part != .loose {
            let above = vertical ? CGRect(x: near.x - far, y: near.y - wide, width: far, height: 2 * wide)
                                 : CGRect(x: near.x - wide, y: near.y - far, width: 2 * wide, height: far)
            drawCard(context, image: image, centre: centre, along: squeeze * size * low, away: size * low, clip: Path(above), shadow: false, edge: edge)
        }
        if part != .whole {
            drawCard(context, image: image, shade: shade, centre: centre, along: squeeze * size * low, away: size * low, dim: 0.25 + 0.4 * slip,
                     clip: Path(slot.rect(u: gap, v: 0, along: width, away: slot.depth)), shadow: false, edge: edge)
        }
    }

    /// 11-11 (the manhole): let go, the card drops down the shaft
    /// (DeleteStyle.shaftTime) — a little toss toward the shelf first, then
    /// over the mouth and down, smaller and dimmer as it falls away, turning
    /// a little. Above the floor it is whole; below it, it shows through the
    /// shaft's mouth only; past the mouth's near rim it is gone.
    private func downTheShaft(_ context: GraphicsContext, image: Image, shade: Image?, card: CGRect, time: Double) {
        guard let slot else { return }
        let k = min(1, max(0, time / DeleteStyle.shaftTime))
        guard k < 1 else { return }
        let (a, b) = slot.manhole
        let fall = CGFloat(k * k), over = CGFloat(k * k * (3 - 2 * k))
        // Smaller as it falls: narrower than the mouth by the time it is in it.
        let low = card.width / max(1, rect.width)
        let narrow = min(1, a * 1.5 / max(1, vertical ? card.height : card.width))
        let size = (1 - (1 - narrow * 0.9) * fall) * low
        let height = (vertical ? rect.width : rect.height) * size
        let l = slot.local(CGPoint(x: card.midX, y: card.midY))
        // Its top at the mouth's near rim at the end: all of it down.
        let end = b + height / 2
        let toss = CGFloat(sin(k * Double.pi)) * -16 * CGFloat(motion)
        let centre = slot.point(l.u * (1 - over), l.v + (end - l.v) * fall + toss)
        // Above the floor (the shelf's side of the mouth's middle), and the mouth.
        let middle = slot.point(0, 0)
        let far: CGFloat = 1500, wide = slot.length * 1.5
        var clip = Path(vertical ? CGRect(x: middle.x - far, y: middle.y - wide, width: far, height: 2 * wide)
                                 : CGRect(x: middle.x - wide, y: middle.y - far, width: 2 * wide, height: far))
        clip.addEllipse(in: slot.rect(u: 0, v: 0, along: a * 2, away: b * 2))
        drawCard(context, image: image, shade: shade, centre: centre, along: size, away: size, turn: (vertical ? -20 : 20) * Double(fall),
                 dim: 0.6 * Double(fall), clip: clip, shadow: false)
    }

    /// 11-11, the scissors: held, the card is whole (the scissors snip at
    /// its side); let go all loose, they cut across its middle, along the
    /// shelf's edge (DeleteStyle.scissorsCut: a line behind their tips,
    /// chips of the card's own colours off it), and the two halves drop
    /// away — the far one at once, the near one after it — turning a little,
    /// and fade.
    private func cutInTwo(_ context: inout GraphicsContext, image: Image, grid: CardArtPrints.BlockGrid, time: Double) {
        let cutTime = DeleteStyle.scissorsCut
        // (clip, which way it turns, how far it drops, when it starts)
        let halves: [(CGRect, Double, Double, Double)]
        if vertical {
            halves = [(CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height), 5, 44, 0.1),
                      (CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height), -6, 70, 0)]
        } else {
            halves = [(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2), -5, 44, 0.1),
                      (CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), 6, 70, 0)]
        }
        for (clip, turn, fall, wait) in halves {
            let k = min(1, max(0, (time - cutTime - wait) / 0.5))
            let alpha = 1 - max(0, (k - 0.4) / 0.6)
            guard alpha > 0 else { continue }
            let drop = CGFloat(fall * k * k * motion)
            var half = context
            half.opacity = alpha
            half.translateBy(x: clip.midX + (vertical ? drop : 0), y: clip.midY + (vertical ? 0 : drop))
            half.rotate(by: .degrees(turn * k * k * (3 - 2 * k)))
            half.translateBy(x: -clip.midX, y: -clip.midY)
            half.clip(to: Path(clip))
            half.addFilter(.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6))
            half.draw(image, in: rect)
        }
        // The cut behind the scissors' tips, until the halves part.
        let length = vertical ? rect.height : rect.width
        if time < cutTime + 0.04 {
            let cut = CGFloat(min(1, time / cutTime)) * length
            var line = Path()
            line.move(to: vertical ? CGPoint(x: rect.midX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.midY))
            line.addLine(to: vertical ? CGPoint(x: rect.midX, y: rect.minY + cut) : CGPoint(x: rect.minX + cut, y: rect.midY))
            context.stroke(line, with: .color(.black.opacity(0.6)), lineWidth: 2.5)
            context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
        }
        // Chips off the cut, as the tips pass: away from the shelf.
        let block = (vertical ? rect.height : rect.width) / CGFloat(Self.across)
        let middle = (vertical ? rect.width : rect.height) / 2
        for b in grid.samples {
            let cx = (CGFloat(b.column) + 0.5) * block, cy = (CGFloat(b.row) + 0.5) * block
            let far = vertical ? cx : cy, along = vertical ? cy : cx
            guard abs(far - middle) < block else { continue }
            let t = time - Double(along / length) * cutTime
            guard t > 0 else { continue }
            let fade = max(0, 1 - 2.4 * t)
            guard fade > 0.02 else { continue }
            let side = b.vx * 70 * t * motion
            let away = (b.vy * 50 * t + 520 * t * t) * motion
            let size = (Double(block) - 2.5 * motion) * 0.55 * (1 - 0.4 * min(1, t * 2))
            let dx = vertical ? away : side, dy = vertical ? side : away
            let x = rect.minX + cx - size / 2 + dx, y = rect.minY + cy - size / 2 + dy
            context.fill(Path(CGRect(x: x, y: y, width: size, height: size)), with: .color(b.color.opacity(fade)))
        }
    }
}

// MARK: - 主题's preview of a way to delete (11-11)

/// A card deleted the chosen way, small, over and over: lifted toward the
/// shelf's edge, over it, let go, gone — the shelf's own layers
/// (DeleteLayers) at a small shelf's size, the hand played by a clock.
/// `still` (a render): this far into the loop.
struct DeleteStyleDemo: View {
    var style: DeleteStyle
    var theme: LibraryTheme
    var size: CGSize
    var scale: CGFloat
    var still: Double? = nil

    /// The loop: toward the edge, over it, held there, let go, a rest.
    private var approach: Double { 0.9 }
    private var over: Double { 0.9 }
    private var held: Double { 0.45 }
    private var gone: Double { max(0.9, style.burstTime + 0.25) + 0.3 }
    private var rest: Double { 0.55 }
    private var loop: Double { approach + over + held + gone + rest }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            scene(at: still ?? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        .accessibilityHidden(true)
    }
    private func scene(at t: Double) -> some View {
        let geometry = ShelfGeometry(frame: CGRect(origin: .zero, size: size), s: scale, viewSize: size)
        let o = geometry.optics
        let width = o.cardWidth * 1.12, height = width * CGFloat(CardDimensions.aspect)
        let edge = o.floorY + 22 * scale, reach = 50 * Double(scale)
        // Where the hand is in its round.
        var near = 0.0, past = 0.0
        var burst: Double? = nil
        var shown = true
        if t < approach {
            let k = t / approach
            near = k * k * (3 - 2 * k)
        } else if t < approach + over {
            near = 1
            past = (t - approach) / over * 1.05
        } else if t < approach + over + held {
            near = 1; past = 1.05
        } else if t < approach + over + held + gone {
            near = 1; past = 1.05
            burst = t - approach - over - held
        } else {
            shown = false
        }
        let foot = edge - CGFloat((1 - near) * style.nearRange) * scale + CGFloat(past * reach)
        let rect = CGRect(x: geometry.flow.midX - width / 2, y: foot - height, width: width, height: height)
        let card = GameCardInfo(title: String(localized: "示例游戏"), subtitle: "Homebrew", icon: nil, isDemo: false)
        let moment = CardShelfView.DeleteMoment(near: near, progress: min(1, past), card: rect, burst: burst == nil ? nil : Date(), previewBurst: burst)
        let crumble = CardShelfView.Crumble(index: 0, card: card, rect: rect, progress: past, burst: burst == nil ? nil : Date())
        // The bin's well goes at the burst, as on the shelf.
        let prop = shown && !(style == .bin && burst != nil)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [theme.paper, theme.paperDeep], startPoint: .top, endPoint: .bottom)
            ShelfBackdrop(geometry: geometry, theme: theme, shown: true)
            DeleteLayers(style: style, geometry: geometry, theme: theme, moment: prop ? moment : nil, crumble: shown ? crumble : nil, previewBurst: burst,
                         lowering: style.lowersCard ? min(0.55, max(0.3, 2 * reach / Double(max(1, height)))) : 0, motion: Double(width / 283))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
