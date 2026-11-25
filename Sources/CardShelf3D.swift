import CoreGraphics
import simd
#if os(iOS)
import SwiftUI
import RealityKit

// Round 27: the shelf's cards are solids (CardModel3D) in the console's own RealityKit
// scene, lit by its studio, hung under its camera so that the shelf stays
// where it is on the screen whatever the console does. Round 26 drew them
// flat with SwiftUI's projection effect.
//
// Motion is physical: the scroll is a spring the finger pulls on (it follows
// the finger closely, and once let go glides to the card it was flung
// toward, overshooting a little); every card's place and turn follow from
// where the scroll stands, frame by frame, so a flick sweeps the light
// across the labels as they turn. Cards come up out of the floor one after
// another when the shelf appears, sink into it when the console starts
// something, and a card taken off the shelf stays the same solid in the
// hand, on its way into the console and back.

/// The shelf in the scene (owned by ConsoleStage, driven by CardShelfView
/// and the library).
@MainActor final class ShelfScene {
    /// Two fingers are bringing the console closer (round 30: the pinch is
    /// the whole library's): a finger of it on the shelf neither flicks nor
    /// lifts a card.
    var pinching = false
    /// Where the shelf is on the screen and the camera's optics (ShelfOptics).
    private(set) var layout = ShelfOptics()
    /// Under the stage's camera (it looks along -z, never turns).
    let root = Entity()
    private var studio: Entity?

    private var depth: Float { ShelfOptics.depth }
    private var focal: Float { layout.focal }
    private var shelfScale: Float { layout.shelfScale }
    private var cardLengthM: Float { layout.cardLengthM }
    private var cardThicknessM: Float { layout.cardThicknessM }
    private var floorLevel: Float { layout.floorLevel }

    // MARK: What is on the shelf

    private struct Entry {
        var index: Int
        var model: ModelEntity?
        let reflection: ModelEntity
        let shadow: ModelEntity
        /// Round 28: the wider, fainter shadow round the contact one.
        let ambient: ModelEntity
        /// 0 under the floor, 1 standing (it comes up when it arrives).
        var appear: Float
        var appearDelay: Float = 0
    }
    private var entries: [String: Entry] = [:]
    private var cards: [GameCardInfo] = []
    /// Card indices in shelf order.
    private var order: [Int] = []
    /// The card in the hand: its place on the shelf stays empty.
    private var hidden: Int?
    /// 11-07: cards whose solid is still to be made, nearest the middle
    /// first — one per frame (makePending), not all in refresh(): the hang
    /// reports on the iPhone Duo (one per launch, 0.45 s "heavy") were the
    /// library's four card solids — their printed faces uploaded as textures —
    /// made in one go inside the stage's first build. A card without its
    /// solid yet is simply not drawn; it rises into place when it has one.
    private var pending: [String] = []

    // MARK: Motion

    /// Where the scroll stands (shelf positions, fractional) and moves.
    private(set) var position = 0.0
    private var speed = 0.0
    private var goal = 0.0
    private var dragging = false
    private var dragGoal = 0.0
    /// Shown (the shelf up) or not, and how far it is; the pinch's recession.
    private var shownGoal: Float = 0
    private var shown: Float = 0
    private var recession: Float = 0
    private var recessionGoal: Float = 0
    private var attached = false

    func attach(to camera: Entity, studio: Entity?) {
        guard !attached else { return }
        attached = true
        self.studio = studio
        root.name = ""
        camera.addChild(root)
        camera.addChild(handHolder)
        refresh()
    }

    func setLayout(_ value: ShelfOptics) {
        guard value != layout else { return }
        layout = value
        refresh()
    }

    /// The cards and the shelf's order (the card in the hand keeps its place empty).
    func setCards(_ cards: [GameCardInfo], order: [Int], hidden: Int?) {
        self.cards = cards
        self.order = order
        self.hidden = hidden
        refresh()
    }

    /// The scroll goes to `offset` (a spring; at once when not animated).
    func setGoal(_ offset: Double, animated: Bool = true) {
        dragging = false
        goal = offset
        if !animated { position = offset; speed = 0 }
    }
    /// The finger has the shelf: it follows `offset` closely.
    func drag(to offset: Double) {
        if !dragging { dragging = true }
        dragGoal = offset
    }
    /// The finger let go, flinging the shelf at `velocity` (positions per
    /// second) toward `offset`.
    func release(to offset: Double, velocity: Double) {
        dragging = false
        goal = offset
        speed = max(-30, min(30, velocity))
    }
    /// The shelf comes up (its cards rising from the floor one after another
    /// from the middle out) or goes down into the floor.
    func setShown(_ on: Bool, rise: Bool = true) {
        let goal: Float = on ? 1 : 0
        guard goal != shownGoal else { return }
        shownGoal = goal
        if on, rise {
            for key in entries.keys {
                guard var entry = entries[key] else { continue }
                let rel = Float(abs(Double(slot(of: entry.index) ?? 0) - position))
                entry.appear = 0
                entry.appearDelay = min(0.45, rel * 0.07)
                entries[key] = entry
            }
            shown = 1
        }
    }
    /// The pinch (0 as it stands, 1 at the closest): smaller, fainter.
    func setRecession(_ p: Double) {
        recessionGoal = Float(max(0, min(1, p)))
    }

    private func slot(of index: Int) -> Int? { order.firstIndex(of: index) }

    /// The middle of the cards made last (refresh makes the cards within six
    /// places of the scroll and of where it is going; a long shelf is not
    /// all made at once).
    private var madeAround = Int.min
    /// Makes and drops entries for the cards now on the shelf near the scroll.
    private func refresh() {
        guard attached else { return }
        let here = Int(position.rounded()), there = Int(goal.rounded())
        madeAround = here
        let low = min(here, there) - 6, high = max(here, there) + 6
        var wanted: [String: Int] = [:]
        var kept: Set<String> = []
        for (slotIndex, index) in order.enumerated() where cards.indices.contains(index) {
            let key = CardArtPrints.key(cards[index])
            if slotIndex >= low && slotIndex <= high { wanted[key] = index }
            if slotIndex >= low - 3 && slotIndex <= high + 3 { kept.insert(key) }
        }
        for (key, entry) in entries where wanted[key] == nil && !kept.contains(key) {
            entry.model?.removeFromParent()
            entry.reflection.removeFromParent()
            entry.shadow.removeFromParent()
            entry.ambient.removeFromParent()
            entries.removeValue(forKey: key)
        }
        // Entries kept but outside the window still learn their place.
        for index in order where cards.indices.contains(index) {
            let key = CardArtPrints.key(cards[index])
            if var entry = entries[key], entry.index != index { entry.index = index; entries[key] = entry }
        }
        for (key, index) in wanted {
            if var entry = entries[key] {
                entry.index = index
                entries[key] = entry
                continue
            }
            let card = cards[index]
            let reflection = ModelEntity(mesh: Self.facePlane, materials: [CardModel3D.reflectionMaterial(card)])
            let shadow = ModelEntity(mesh: Self.shadowPlane, materials: [Self.shadowMaterial])
            let ambient = ModelEntity(mesh: Self.ambientPlane, materials: [Self.ambientMaterial])
            root.addChild(ambient)
            root.addChild(shadow)
            root.addChild(reflection)
            // A card held in the hand (or flying) joins its entry when it lands;
            // any other gets its solid from makePending, a frame at a time.
            if hand?.key != key, !pending.contains(key) { pending.append(key) }
            // A card that comes onto the shelf while it is up rises into its place.
            entries[key] = Entry(index: index, model: nil, reflection: reflection, shadow: shadow, ambient: ambient, appear: shown > 0.5 ? 0 : 1)
        }
        pending.removeAll { entries[$0] == nil }
        // Nearest the middle first.
        pending.sort { abs(Double(slot(of: entries[$0]?.index ?? 0) ?? 0) - position) < abs(Double(slot(of: entries[$1]?.index ?? 0) ?? 0) - position) }
        place()
    }
    /// One pending card's solid made (every frame, from update): the printed
    /// face as textures, a mesh, lit by the studio.
    private func makePending() {
        while !pending.isEmpty {
            let key = pending.removeFirst()
            guard var entry = entries[key], entry.model == nil, hand?.key != key, cards.indices.contains(entry.index) else { continue }
            let made = CardModel3D.make(cards[entry.index], name: "")
            light(made)
            root.addChild(made)
            entry.model = made
            entries[key] = entry
            return
        }
    }
    private func light(_ entity: Entity) {
        guard let studio else { return }
        if entity is ModelEntity { entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: studio)) }
        for child in entity.children { light(child) }
    }

    // MARK: Every frame

    func update(_ dt: Float) {
        guard attached, layout.cardWidth > 0 else { return }
        makePending()
        let dt = min(0.05, max(0, dt))
        // The scroll: a spring toward the finger, or toward the card it was
        // flung to (a little overshoot), small steps for stability.
        let steps = max(1, Int((dt / (1 / 240)).rounded(.up)))
        let h = Double(dt) / Double(steps)
        for _ in 0..<steps {
            if dragging {
                let w = 2 * Double.pi / 0.07
                speed += (w * w * (dragGoal - position) - 2 * w * speed) * h
            } else {
                let w = 2 * Double.pi / 0.62, z = 0.78
                speed += (w * w * (goal - position) - 2 * z * w * speed) * h
            }
            position += speed * h
        }
        if !dragging, abs(goal - position) < 0.0004, abs(speed) < 0.002 { position = goal; speed = 0 }
        // Shown, receded.
        shown += (shownGoal - shown) * min(1, dt / 0.16)
        if abs(shownGoal - shown) < 0.002 { shown = shownGoal }
        recession += (recessionGoal - recession) * min(1, dt / 0.08)
        for key in entries.keys {
            guard var entry = entries[key] else { continue }
            if entry.appearDelay > 0 {
                entry.appearDelay = max(0, entry.appearDelay - dt)
            } else if entry.appear < 1 {
                entry.appear = min(1, entry.appear + dt / 0.5)
            }
            entries[key] = entry
        }
        // A flick far along the shelf: the cards there are made.
        if abs(Int(position.rounded()) - madeAround) >= 2 { refresh() }
        place()
        stepHand(dt)
    }

    /// Where the card `rel` places from the middle stands (ShelfOptics.pose).
    func pose(_ rel: Double) -> (centre: SIMD3<Float>, turn: simd_quatf) { layout.pose(rel) }

    /// Puts every card where the scroll says (and its reflection, its shadow).
    private func place() {
        guard attached, layout.cardWidth > 0 else { return }
        let r = recession * recession * (3 - 2 * recession)
        // Receding about the middle card's centre.
        let middle = pose(0).centre
        let scale = 1 - 0.72 * r
        root.scale = [scale, scale, scale]
        root.position = middle * (1 - scale)
        let sc = shelfScale
        for (_, entry) in entries {
            guard let slotIndex = slot(of: entry.index) else { continue }
            let rel = Double(slotIndex) - position
            let far = abs(rel) > 5.5
            // (In the hand or on its way: its place, its reflection and its
            // shadow stay empty until it lands.)
            let isHidden = entry.index == hidden || entry.model == nil
            // Rising out of the floor: lower, smaller, fainter until it stands.
            let a = entry.appear
            let rise = 1 - (1 - a) * (1 - a) * (1 - a)
            let fade = (abs(rel) > 4.5 ? Float(max(0, 5.5 - abs(rel))) : 1) * min(1, shown) * (1 - r)
            let standing = pose(rel)
            var centre = standing.centre
            // (A column has no floor: its cards come in from the side away
            // from the console.)
            if layout.vertical { centre.x += (1 - rise) * layout.cardWidthM * 0.5 } else { centre.y -= (1 - rise) * cardLengthM * 0.55 }
            let turn = standing.turn
            let visible = !far && !isHidden && fade > 0.003 && rise > 0.001
            if let model = entry.model, model.parent === root {
                model.isEnabled = visible
                if visible {
                    model.position = centre
                    model.orientation = turn
                    let grow = 0.94 + 0.06 * rise
                    model.scale = [sc * grow, sc * grow, sc * grow]
                    let opacity = fade * min(1, rise * 1.6)
                    if opacity < 0.995 { model.components.set(OpacityComponent(opacity: opacity)) } else { model.components.remove(OpacityComponent.self) }
                }
            }
            // The reflection: the face mirrored in the floor, under it.
            let showReflection = visible && rise > 0.6 && !layout.vertical
            entry.reflection.isEnabled = showReflection
            if showReflection {
                let out = turn.act([0, 0, 1])
                let face = centre + out * (cardThicknessM / 2)
                entry.reflection.position = [face.x, floorLevel - cardLengthM / 2 - (centre.y - (floorLevel + cardLengthM / 2)), face.z]
                entry.reflection.orientation = turn * simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                entry.reflection.scale = [sc, sc, sc]
                entry.reflection.components.set(OpacityComponent(opacity: fade * (rise - 0.6) / 0.4 * (1 - shade(rel) * 0.8)))
            }
            let grounded = visible && !layout.vertical
            entry.shadow.isEnabled = grounded
            entry.ambient.isEnabled = grounded
            if grounded {
                entry.shadow.position = [centre.x, floorLevel + 0.0004, centre.z]
                entry.shadow.orientation = turn
                entry.shadow.scale = [sc, sc, sc]
                // Lighter as the card rises off the floor.
                let lift = max(0, centre.y - (floorLevel + cardLengthM / 2)) / cardLengthM
                entry.shadow.components.set(OpacityComponent(opacity: fade * rise * max(0, 1 - lift * 3)))
                // The studio's light comes from in front and above: the soft
                // shadow lies a little behind the card.
                let back = turn.act([0, 0, -1]) * (cardThicknessM * 1.2)
                entry.ambient.position = [centre.x + back.x, floorLevel + 0.0002, centre.z + back.z]
                entry.ambient.orientation = turn
                entry.ambient.scale = [sc, sc, sc]
                entry.ambient.components.set(OpacityComponent(opacity: fade * rise * max(0, 1 - lift * 1.5)))
            }
        }
    }
    /// How much darker a card stands away from the light in the middle.
    private func shade(_ rel: Double) -> Float { Float(min(0.3, max(0, abs(rel) - 0.12) * 0.15)) }

    // MARK: On the screen

    /// The cards a tap could be meant for, as they stand now (the shelf
    /// shrinking with a pinch included): index, how far from the middle,
    /// the face's corners on the screen.
    func places() -> [(index: Int, rel: Double, quad: [CGPoint])] {
        var out: [(index: Int, rel: Double, quad: [CGPoint])] = []
        for (slotIndex, index) in order.enumerated() where index != hidden {
            let rel = Double(slotIndex) - position
            if abs(rel) < 4.5 { out.append((index, rel, layout.faceQuad(rel: rel, rootPosition: root.position, rootScale: root.scale.x))) }
        }
        return out
    }

    // MARK: Meshes and materials shared by every card

    /// The face's size as a plane (lying in XZ; turned up by its entity).
    private static let facePlane: MeshResource = MeshResource.generatePlane(width: Float(CardDimensions.width) * ConsoleModel.u,
                                                                             depth: Float(CardDimensions.length) * ConsoleModel.u,
                                                                             cornerRadius: 6.5 * ConsoleModel.u)
    /// The contact shadow: a tight dark spot about as wide as the card and
    /// a couple of thicknesses deep, right under its edge (lying on the
    /// floor); round 28: tighter, with a wide faint one round it.
    private static let shadowPlane: MeshResource = MeshResource.generatePlane(width: Float(CardDimensions.width) * 1.08 * ConsoleModel.u,
                                                                               depth: Float(CardDimensions.thickness) * 2.4 * ConsoleModel.u)
    private static let ambientPlane: MeshResource = MeshResource.generatePlane(width: Float(CardDimensions.width) * 1.6 * ConsoleModel.u,
                                                                                depth: Float(CardDimensions.thickness) * 9 * ConsoleModel.u)
    private static func shadowSpot(_ strength: Float) -> UnlitMaterial {
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: UIColor(white: 0, alpha: 1))
        if let spot = CardModel3D.spotTexture {
            m.blending = .transparent(opacity: .init(scale: strength, texture: CardModel3D.clamped(spot)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: strength * 0.5))
        }
        m.writesDepth = false
        return m
    }
    private static let shadowMaterial = shadowSpot(0.72)
    private static let ambientMaterial = shadowSpot(0.26)

    // MARK: The hand

    /// The card in the hand: off the shelf, out of the console, or flying
    /// between them. The same solid throughout.
    private struct Hand {
        var key: String
        var index: Int
        var model: ModelEntity
        var mode: Mode
        enum Mode {
            case held(CGPoint)
            case flying(Flight)
        }
    }
    struct Flight {
        /// Where it starts, in the hand holder's space (under the camera).
        /// The path is drawn in the camera's space: the camera moves while
        /// the console turns round (it comes up close to the slot), and a
        /// path drawn in the world was left behind by it, so the card swung
        /// toward the player, grew and jumped (round 27, first build).
        var from: Transform
        /// Where it ends (world, asked every frame: the console may be moving).
        var to: () -> Transform?
        var duration: Double
        var elapsed: Double = 0
        /// How far toward the player the path bows (metres).
        var bow: Float
        var landed: (ModelEntity) -> Void
    }
    private var hand: Hand?
    /// Holds the card in the hand: under the camera like the shelf, but not
    /// shrunk or faded with it.
    private let handHolder = Entity()
    private var handVelocity: SIMD3<Float> = .zero
    private var lastHandPoint: CGPoint?
    private var handPointSpeed = CGVector.zero

    /// `--foldarc-hand-log` (DEBUG): where the card in the hand is when it
    /// changes hands and as each flight starts (round 27).
    #if DEBUG
    static let debugHand = ProcessInfo.processInfo.arguments.contains("--foldarc-hand-log")
    #else
    static let debugHand = false
    #endif
    /// Puts `entity` under `parent` where it stands: its place in the world
    /// taken before the move and given back after it (round 27: a card out
    /// of the console's slot began its flight home from the wrong place).
    static func reparent(_ entity: Entity, to parent: Entity, _ what: String) {
        let world = entity.transformMatrix(relativeTo: nil)
        parent.addChild(entity, preservingWorldTransform: true)
        #if DEBUG
        if debugHand {
            let kept = entity.transformMatrix(relativeTo: nil).columns.3
            NSLog("[hand] %@: world (%.3f %.3f %.3f), kept by the move (%.3f %.3f %.3f)", what,
                  world.columns.3.x, world.columns.3.y, world.columns.3.z, kept.x, kept.y, kept.z)
        }
        #endif
        entity.setTransformMatrix(world, relativeTo: nil)
    }

    var handIndex: Int? { hand?.index }
    /// 11-07 (删除): the card in the hand hidden while its face is drawn flat
    /// over it, coming apart in blocks (shown again when it is whole again).
    func setHandVisible(_ on: Bool) { hand?.model.isEnabled = on }
    /// 11-11 (删除方式: a card that goes into the floor whole): the held
    /// card lowered toward the thing in the floor — this much smaller (0:
    /// as it is held; the hand eases to it) — so that the thing shows under
    /// it and the card is at its mouth when it is let go.
    func setHandLower(_ amount: Double) { handLower = Float(min(0.7, max(0, amount))) }
    private var handLower: Float = 0
    /// 11-07 (删除): the face of the card in the hand on the screen (its
    /// corners), for the blocks drawn over it.
    func handQuad() -> [CGPoint]? {
        guard let model = hand?.model else { return nil }
        let w = Float(CardDimensions.width) * ConsoleModel.u / 2, l = Float(CardDimensions.length) * ConsoleModel.u / 2
        let t = Float(CardDimensions.thickness) * ConsoleModel.u / 2
        let corners: [SIMD3<Float>] = [[-w, l, t], [w, l, t], [w, -l, t], [-w, -l, t]]
        return corners.map { layout.project(model.position + model.orientation.act($0 * model.scale)) }
    }
    var isHandFlying: Bool {
        guard let mode = hand?.mode else { return false }
        if case .flying = mode { return true }
        return false
    }

    /// Takes the card in the middle off the shelf into the hand.
    @discardableResult func takeFromShelf(_ index: Int, at point: CGPoint) -> Bool {
        guard hand == nil, cards.indices.contains(index) else { return false }
        let key = CardArtPrints.key(cards[index])
        guard var entry = entries[key], let model = entry.model else { return false }
        entry.model = nil
        entries[key] = entry
        model.stopAllAnimations()
        model.components.remove(OpacityComponent.self)
        model.isEnabled = true
        Self.reparent(model, to: handHolder, "off the shelf")
        hand = Hand(key: key, index: index, model: model, mode: .held(point))
        handLower = 0
        handPoint = point
        lastHandPoint = point
        handPointSpeed = .zero
        handVelocity = .zero
        hidden = index
        return true
    }
    /// A card from somewhere else (out of the console's slot) into the
    /// hand: it flies from where it is up to the finger (position and size
    /// change together, so it does not shrink on the way), then follows it.
    func takeIntoHand(_ model: ModelEntity, index: Int, at point: CGPoint) {
        guard hand == nil, cards.indices.contains(index) else { return }
        // (A move the console gave it, still running, would go on writing
        // the slot's coordinates into the hand's.)
        model.stopAllAnimations()
        light(model)
        Self.reparent(model, to: handHolder, "into the hand")
        handLower = 0
        handPoint = point
        lastHandPoint = point
        handPointSpeed = .zero
        handVelocity = .zero
        let flight = Flight(from: model.transform, to: { [weak self] in self.map { $0.heldTransform(at: $0.handPoint) } }, duration: 0.24, bow: 0.02) { [weak self] model in
            guard let self, var current = self.hand else { return }
            self.handVelocity = .zero
            current.mode = .held(self.handPoint)
            self.hand = current
        }
        hand = Hand(key: CardArtPrints.key(cards[index]), index: index, model: model, mode: .flying(flight))
    }
    /// Where the finger last was (a card flying up to it goes there).
    private var handPoint = CGPoint.zero
    /// The finger carrying the card.
    func moveHand(to point: CGPoint) {
        handPoint = point
        guard var current = hand, case .held = current.mode else { return }
        current.mode = .held(point)
        hand = current
    }
    /// The card in the hand is carried to `point` along a smooth path, then
    /// held there (a card put in by A: round 27).
    func carryHand(to point: CGPoint, duration: Double) {
        guard var current = hand else { return }
        handPoint = point
        current.mode = .flying(Flight(from: current.model.transform, to: { [weak self] in self.map { $0.heldTransform(at: $0.handPoint) } }, duration: duration, bow: 0.03) { [weak self] _ in
            guard let self, var held = self.hand else { return }
            self.handVelocity = .zero
            self.lastHandPoint = self.handPoint
            held.mode = .held(self.handPoint)
            self.hand = held
        })
        hand = current
    }
    /// The card held at `point`, in the world: nearer than the shelf, as wide
    /// as 0.9 of a shelf card, leaning back a little.
    private func heldTransform(at point: CGPoint) -> Transform {
        let (position, scale) = heldPlace(point)
        let local = Transform(scale: [scale, scale, scale], rotation: simd_quatf(angle: -0.16, axis: [1, 0, 0]), translation: position)
        return Transform(matrix: handHolder.transformMatrix(relativeTo: nil) * local.matrix)
    }
    /// The held card's place (holder space) and scale for a point.
    private func heldPlace(_ point: CGPoint) -> (SIMD3<Float>, Float) {
        let d = depth * 0.8
        let f = focal
        let p = SIMD3<Float>((Float(point.x) - Float(layout.viewSize.width) / 2) * d / f,
                             -(Float(point.y) - Float(layout.viewSize.height) / 2) * d / f, -d)
        return (p, shelfScale * 0.9 * (d / depth) * (1 - handLower))
    }
    /// The card flies from wherever it is to `to` (world), bowing toward
    /// the player, and is handed over when it lands.
    func flyHand(to target: @escaping () -> Transform?, duration: Double, bow: Float = 0.06, landed: @escaping (ModelEntity) -> Void) {
        guard var current = hand else { return }
        current.mode = .flying(Flight(from: current.model.transform, to: target, duration: duration, bow: bow, landed: landed))
        hand = current
    }
    /// The card in the hand goes back to its place on the shelf (the place
    /// the shelf's order gives it now) and stands there again.
    func flyHandHome(duration: Double = 0.42) {
        guard let current = hand else { return }
        let index = current.index
        flyHand(to: { [weak self] in self?.homeTransform(of: index) }, duration: duration, bow: 0.02) { [weak self] model in
            self?.land(model, index: index)
        }
    }
    /// Where a card's place on the shelf is, in world space.
    private func homeTransform(of index: Int) -> Transform? {
        guard let slotIndex = slot(of: index) else { return nil }
        let (centre, turn) = pose(Double(slotIndex) - position)
        let local = Transform(scale: [shelfScale, shelfScale, shelfScale], rotation: turn, translation: centre)
        return Transform(matrix: root.transformMatrix(relativeTo: nil) * local.matrix)
    }
    /// The card has landed on the shelf: it stands in its place again.
    private func land(_ model: ModelEntity, index: Int) {
        hand = nil
        if hidden == index { hidden = nil }
        guard cards.indices.contains(index) else { model.removeFromParent(); return }
        let key = CardArtPrints.key(cards[index])
        Self.reparent(model, to: root, "onto the shelf")
        if var entry = entries[key] {
            entry.model?.removeFromParent()
            entry.model = model
            entry.appear = 1
            entry.appearDelay = 0
            entries[key] = entry
        } else {
            // Not on the shelf (any more): it goes.
            model.removeFromParent()
        }
        place()
    }
    /// The card in the hand has gone into the console: the hand is empty.
    func handOver() {
        hand = nil
    }
    /// Drops whatever is in the hand (the library going away).
    func dropHand() {
        hand?.model.removeFromParent()
        hand = nil
    }
    /// 11-07 (删除): a card whose solid went with the hand (it burst) but
    /// which stays in the library after all: its entry is made anew, so a
    /// solid rises into its place again. (One that has its solid: nothing.)
    func showAgain(_ index: Int) {
        guard cards.indices.contains(index), hand?.index != index else { return }
        let key = CardArtPrints.key(cards[index])
        if let entry = entries[key], entry.model == nil {
            entry.reflection.removeFromParent()
            entry.shadow.removeFromParent()
            entry.ambient.removeFromParent()
            entries.removeValue(forKey: key)
        }
        if hidden == index { hidden = nil }
        refresh()
    }

    /// Every frame: the held card follows the finger (a spring), leaning
    /// with its motion; a flying one goes along its path.
    private func stepHand(_ dt: Float) {
        guard var current = hand else { return }
        switch current.mode {
        case .held(let point):
            // Where the finger is, nearer the player than the shelf.
            let (target, sc) = heldPlace(point)
            // The finger's speed on the screen (for the lean).
            if let last = lastHandPoint, dt > 0 {
                let vx = Double((point.x - last.x)) / Double(dt), vy = Double((point.y - last.y)) / Double(dt)
                let k = Double(min(1, dt / 0.08))
                handPointSpeed = CGVector(dx: handPointSpeed.dx + (vx - handPointSpeed.dx) * k, dy: handPointSpeed.dy + (vy - handPointSpeed.dy) * k)
            }
            lastHandPoint = point
            let model = current.model
            // Position: a critically damped spring in the holder's space.
            let w: Float = 2 * .pi / 0.16
            let steps = max(1, Int((dt / (1 / 240)).rounded(.up)))
            let h = dt / Float(steps)
            var p = model.position
            for _ in 0..<steps {
                handVelocity += (w * w * (target - p) - 2 * w * handVelocity) * h
                p += handVelocity * h
            }
            model.position = p
            // Size: as wide as 0.9 of a shelf card at the hand's depth.
            let k = min(1, dt / 0.09)
            model.scale += ([sc, sc, sc] - model.scale) * k
            // Leaning back a little, swaying with the finger's motion.
            let sway = Float(max(-1, min(1, handPointSpeed.dx / 1400)))
            let pitch = Float(max(-1, min(1, handPointSpeed.dy / 1400)))
            let lean = simd_quatf(angle: -0.16 + pitch * 0.18, axis: [1, 0, 0])
                * simd_quatf(angle: -sway * 0.20, axis: [0, 0, 1])
                * simd_quatf(angle: sway * 0.28, axis: [0, 1, 0])
            model.orientation = simd_slerp(model.orientation, lean, min(1, dt / 0.07))
            hand = current
        case .flying(var flight):
            // (Where it is going may not be known yet: the shelf making room
            // for it. It waits there.)
            guard let world = flight.to() else { return }
            // Where it is going, in the camera's space (the holder's).
            let end = Transform(matrix: handHolder.transformMatrix(relativeTo: nil).inverse * world.matrix)
            #if DEBUG
            if Self.debugHand, flight.elapsed == 0 {
                let a = flight.from.translation, now = current.model.position, b = end.translation
                NSLog("[hand] flight %.2f s: from (%.3f %.3f %.3f) scale %.3f, now (%.3f %.3f %.3f), to (%.3f %.3f %.3f) scale %.3f", flight.duration,
                      a.x, a.y, a.z, flight.from.scale.x, now.x, now.y, now.z, b.x, b.y, b.z, end.scale.x)
            }
            #endif
            flight.elapsed += Double(dt)
            let t = min(1, flight.elapsed / max(0.01, flight.duration))
            let e = Float(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
            let a = flight.from.translation, b = end.translation
            // A quadratic path bowing toward the camera (the holder's
            // origin) and up.
            let mid = (a + b) / 2
            let toCamera = simd_normalize(-mid + SIMD3<Float>(0, 0.0001, 0))
            let control = mid + toCamera * flight.bow + SIMD3<Float>(0, flight.bow * 0.5, 0)
            let u = 1 - e
            let pa: SIMD3<Float> = a * (u * u)
            let pc: SIMD3<Float> = control * (2 * u * e)
            let pb: SIMD3<Float> = b * (e * e)
            let p = pa + pc + pb
            let rotation = simd_slerp(flight.from.rotation, end.rotation, e)
            let scale = flight.from.scale + (end.scale - flight.from.scale) * e
            current.model.transform = Transform(scale: scale, rotation: rotation, translation: p)
            if t >= 1 {
                hand = current
                let landed = flight.landed
                let model = current.model
                landed(model)
                return
            }
            current.mode = .flying(flight)
            hand = current
        }
    }
}
#else
import SwiftUI
/// The Mac preview has no RealityKit stage: the shelf's calls do nothing
/// there (CardShelfView draws flat cards itself).
@MainActor final class ShelfScene {
    var pinching = false
    private(set) var layout = ShelfOptics()
    private(set) var position = 0.0
    var handIndex: Int? { nil }
    var isHandFlying: Bool { false }
    func handQuad() -> [CGPoint]? { nil }
    @discardableResult func takeFromShelf(_ index: Int, at point: CGPoint) -> Bool { false }
    func setHandVisible(_ on: Bool) {}
    func setHandLower(_ amount: Double) {}
    func setLayout(_ value: ShelfOptics) { layout = value }
    func setCards(_ cards: [GameCardInfo], order: [Int], hidden: Int?) {}
    func setGoal(_ offset: Double, animated: Bool = true) { position = offset }
    func drag(to offset: Double) { position = offset }
    func release(to offset: Double, velocity: Double) { position = offset }
    func setShown(_ on: Bool, rise: Bool = true) {}
    func setRecession(_ p: Double) {}
    func places() -> [(index: Int, rel: Double, quad: [CGPoint])] { [] }
    func carryHand(to point: CGPoint, duration: Double) {}
    func moveHand(to point: CGPoint) {}
    func flyHandHome(duration: Double = 0.42) {}
    func handOver() {}
    func dropHand() {}
    func showAgain(_ index: Int) {}
}
#endif

/// The card's size in the console's design units (round 27; the solid,
/// CardModel3D, and the slot use these). Round 28: a real game card is 35 × 33 × 3.8 mm, a little wider than it
/// is tall; round 27's was 187 × 200, taller than wide.
enum CardDimensions {
    static let width: Double = 187
    static let length: Double = 176
    static let thickness: Double = 21
    /// Length over width (the face's aspect, height / width).
    static var aspect: Double { length / width }
}

/// Where the shelf is on the screen and how the stage's camera sees it
/// (round 27): plain arithmetic, shared by the RealityKit shelf, the taps,
/// VoiceOver and the Mac preview. Camera space: x right, y up, the camera
/// looking along -z with the stage's vertical field of view.
struct ShelfOptics: Equatable {
    /// The library's size (the RealityView covers it).
    var viewSize: CGSize = .zero
    /// The face of the card in the middle: its centre and width (points).
    var centre: CGPoint = .zero
    var cardWidth: CGFloat = 0
    /// The line the cards stand on.
    var floorY: CGFloat = 0
    /// 11-07: held across, the
    /// console on the left, the cards stand in a column beside it and slide
    /// up and down: the middle one faces the player, those above and below
    /// tip back toward it (no floor under them: no reflection, no shadow).
    var vertical = false

    /// Metres from the camera to the middle card: near enough that the
    /// console (4–9 m away) is always behind the shelf.
    static let depth: Float = 0.55
    var focal: Float { Float(max(1, viewSize.height)) / (2 * tan(ConsoleModel.fieldOfView / 2 * .pi / 180)) }
    /// Metres per point at the middle card's depth.
    var metresPerPoint: Float { Self.depth / focal }
    /// The cards' scale on the shelf (they are modelled at the console's size).
    var shelfScale: Float { Float(cardWidth) * metresPerPoint / (Float(CardDimensions.width) * ConsoleModel.u) }
    var cardWidthM: Float { Float(CardDimensions.width) * ConsoleModel.u * shelfScale }
    var cardLengthM: Float { Float(CardDimensions.length) * ConsoleModel.u * shelfScale }
    var cardThicknessM: Float { Float(CardDimensions.thickness) * ConsoleModel.u * shelfScale }
    /// The floor: a level plane under the camera's eye line.
    var floorLevel: Float { -(Float(floorY) - Float(viewSize.height) / 2) * metresPerPoint }

    /// Where the card `rel` places from the middle stands (camera space,
    /// metres: the middle of the card) and how it is turned: the middle one
    /// faces the player, a little forward; beside it each turns 64° toward
    /// the middle and stands back; the rest crowd behind them. In a row
    /// they turn about the upright; in a column (`vertical`) about the
    /// level, those above tipping their faces down toward the middle, those
    /// below up, the column kept straight on the screen however far back.
    func pose(_ rel: Double) -> (centre: SIMD3<Float>, turn: simd_quatf) {
        let a = abs(rel), sign: Double = rel < 0 ? -1 : 1
        let t = min(1, a)
        let e = t * t * (3 - 2 * t)
        let k = Double(metresPerPoint)
        let angle = Float(-sign * e * 64 * .pi / 180)
        if vertical {
            let ch = Double(cardWidth) * CardDimensions.aspect
            let near = ch * 0.84, spacing = ch * 0.31, back = ch * 1.25, back2 = ch * 0.26
            let down = a <= 1 ? sign * e * near : sign * (near + (a - 1) * spacing)
            var z = a <= 1 ? -e * back : -(back + (a - 1) * back2)
            z += (1 - e) * ch * 0.12
            let cz = -Self.depth + Float(z * k)
            let reach = Double(-cz) / Double(Self.depth)
            let cx = Float((Double(centre.x) - Double(viewSize.width) / 2) * k * reach)
            let cy = Float(-(Double(centre.y) - Double(viewSize.height) / 2 + down) * k)
            return ([cx, cy, cz], simd_quatf(angle: angle, axis: [1, 0, 0]))
        }
        let cw = Double(cardWidth)
        let near = cw * 0.84, spacing = cw * 0.31, back = cw * 1.25, back2 = cw * 0.26
        let x = a <= 1 ? sign * e * near : sign * (near + (a - 1) * spacing)
        var z = a <= 1 ? -e * back : -(back + (a - 1) * back2)
        z += (1 - e) * cw * 0.12
        let cx = Float((Double(centre.x) - Double(viewSize.width) / 2 + x) * k)
        let cz = -Self.depth + Float(z * k)
        return ([cx, floorLevel + cardLengthM / 2, cz], simd_quatf(angle: angle, axis: [0, 1, 0]))
    }
    /// A point of camera space on the screen (library coordinates).
    func project(_ p: SIMD3<Float>) -> CGPoint {
        let f = focal
        let d = max(0.001, -p.z)
        return CGPoint(x: CGFloat(Float(viewSize.width) / 2 + f * p.x / d),
                       y: CGFloat(Float(viewSize.height) / 2 - f * p.y / d))
    }
    /// The corners of the card's label face on the screen (the shelf moved
    /// and scaled by `rootPosition`, `rootScale` as a pinch shrinks it).
    func faceQuad(rel: Double, rootPosition: SIMD3<Float> = .zero, rootScale: Float = 1) -> [CGPoint] {
        let (middle, turn) = pose(rel)
        let w = cardWidthM / 2, l = cardLengthM / 2, t = cardThicknessM / 2
        let corners: [SIMD3<Float>] = [[-w, l, t], [w, l, t], [w, -l, t], [-w, -l, t]]
        return corners.map { project(rootPosition + rootScale * (middle + turn.act($0))) }
    }
    /// The faces of the cards on the shelf when the scroll stands at
    /// `offset`: index, how far from the middle, corners on the screen.
    func places(order: [Int], hidden: Int?, offset: Double) -> [(index: Int, rel: Double, quad: [CGPoint])] {
        var out: [(index: Int, rel: Double, quad: [CGPoint])] = []
        guard cardWidth > 0 else { return out }
        for (slotIndex, index) in order.enumerated() where index != hidden {
            let rel = Double(slotIndex) - offset
            if abs(rel) < 4.5 { out.append((index, rel, faceQuad(rel: rel))) }
        }
        return out
    }
}
