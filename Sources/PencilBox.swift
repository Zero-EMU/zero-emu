import SwiftUI
import Combine
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
#if os(iOS)
import UIKit
import PencilKit
import PhotosUI
#elseif os(macOS)
import AppKit
#endif

// 铅笔盒 (round 32): an old tin pencil box, on both sides of iPhone Duo.
// Closed, the cover is its lid with what has been gathered stuck on it —
// letters, a tear-off calendar, the music box, a photo from the album or
// from Photos, a page of 游戏笔记, a note written or typed here — moved,
// turned and sized with the fingers (PencilBoxLid.swift). Open, it lies
// over the whole inner display, the Duo's fold its hinge: the inside of the
// lid above, the box with a well for each of its things below
// (PencilBoxProgram.swift). What a
// filling shelf brings comes into it as it came into 铁皮盒 (TinBoxStore).
// The pictures are drawn by hand, the light from the upper left; each
// sticker's shadow is a picture of its own, laid under it and moved away
// from the light whichever way the sticker is turned.

// MARK: - The pictures (their sizes: PencilArt, Domain.swift)

/// The pictures, read once. A render on a Mac (RenderPreview) has none in
/// its bundle: FOLDARC_RESOURCES names the folder they are in. The box's own
/// pictures (PencilBoxStyle.boxFiles) are the chosen style's, in the chosen
/// colour (主题 › 铅笔盒): those are kept only while that look is worn.
@MainActor enum PencilImages {
    #if os(iOS)
    typealias Picture = UIImage
    #else
    typealias Picture = NSImage
    #endif
    private static var cache: [String: Picture] = [:]
    private static var boxCache: [String: Picture] = [:]
    private static var boxCacheLook = ""
    /// Small ones for 主题's upper screen, any look.
    private static var previews: [String: Picture] = [:]
    private static var previewOrder: [String] = []
    private static func read(_ file: String) -> Picture? {
        var found: Picture?
        if let folder = ProcessInfo.processInfo.environment["FOLDARC_RESOURCES"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(file)
            #if os(iOS)
            found = UIImage(contentsOfFile: url.path)
            #else
            found = NSImage(contentsOf: url)
            #endif
        }
        if found == nil {
            #if os(iOS)
            if let path = Bundle.main.path(forResource: file, ofType: nil) { found = UIImage(contentsOfFile: path) }
            #else
            if let url = Bundle.main.url(forResource: file, withExtension: nil) { found = NSImage(contentsOf: url) }
            #endif
        }
        return found
    }
    /// A picture by its name; the box's own in `look` (or the one chosen).
    static func picture(_ file: String, look: PencilBoxLook? = nil) -> Picture? {
        if PencilBoxStyle.boxFiles.contains(file) { return box(file, look: look ?? .stored) }
        if let hit = cache[file] { return hit }
        let found = read(file)
        if let found { cache[file] = found }
        return found
    }
    private static func box(_ file: String, look: PencilBoxLook) -> Picture? {
        if boxCacheLook != look.id { boxCache.removeAll(); boxCacheLook = look.id }
        if let hit = boxCache[file] { return hit }
        let own = look.style.file(file)
        var found = read(own)
        if let base = found, !look.isDrawn, PencilBoxStyle.colouredFiles.contains(file) {
            if let mask = read(look.style.mask(file)), let changed = PencilRecolour.apply(base, mask: mask, look: look) { found = changed }
            else { NSLog("[pencil] no colour for %@ (%@)", own, look.id) }
        }
        if let found { boxCache[file] = found }
        return found
    }
    /// A box picture `height` pixels high in `look`, for a preview (kept, a few dozen).
    static func preview(_ file: String, look: PencilBoxLook, height: Double) -> Picture? {
        let key = "\(file)|\(look.id)|\(Int(height))"
        if let hit = previews[key] { return hit }
        guard var base = read(look.style.file(file)) else { return nil }
        if !look.isDrawn, PencilBoxStyle.colouredFiles.contains(file), let mask = read(look.style.mask(file)),
           let changed = PencilRecolour.apply(base, mask: mask, look: look) {
            base = changed
        }
        guard let found = PencilRecolour.scaled(base, height: height) else { return nil }
        previews[key] = found
        previewOrder.append(key)
        if previewOrder.count > 40 { previews[previewOrder.removeFirst()] = nil }
        return found
    }
    static func image(_ file: String, look: PencilBoxLook? = nil) -> Image {
        guard let picture = picture(file, look: look) else { return Image(systemName: "square.dashed") }
        return image(picture)
    }
    static func image(_ picture: Picture) -> Image {
        #if os(iOS)
        return Image(uiImage: picture)
        #else
        return Image(nsImage: picture)
        #endif
    }
}

/// A pencil box in another colour: the same picture with its shell (where
/// its mask is white) moved to the colour chosen (PencilBoxLook.recolour,
/// laid out as a colour cube), everything else as drawn.
@MainActor enum PencilRecolour {
    private static let context = CIContext()
    private static var cubes: [String: Data] = [:]
    static let dimension = 32
    static func cube(for look: PencilBoxLook) -> Data {
        if let hit = cubes[look.id] { return hit }
        let n = dimension
        var cells = [Float](repeating: 0, count: n * n * n * 4)
        // (red changes fastest, then green, then blue: the cube's order)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let out = look.recolour(SIMD3(Double(r), Double(g), Double(b)) / Double(n - 1))
            let i = ((b * n + g) * n + r) * 4
            cells[i] = Float(out.x); cells[i + 1] = Float(out.y); cells[i + 2] = Float(out.z); cells[i + 3] = 1
        } } }
        let data = cells.withUnsafeBufferPointer { Data(buffer: $0) }
        cubes[look.id] = data
        return data
    }
    private static func cgImage(_ picture: PencilImages.Picture) -> CGImage? {
        #if os(iOS)
        return picture.cgImage
        #else
        return picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
    private static func picture(_ image: CGImage) -> PencilImages.Picture {
        #if os(iOS)
        return UIImage(cgImage: image)
        #else
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #endif
    }
    static func apply(_ picture: PencilImages.Picture, mask: PencilImages.Picture, look: PencilBoxLook) -> PencilImages.Picture? {
        guard let base = cgImage(picture), let shell = cgImage(mask) else { return nil }
        let input = CIImage(cgImage: base)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = input
        cube.cubeDimension = Float(dimension)
        cube.cubeData = Self.cube(for: look)
        cube.colorSpace = sRGB
        // (the mask's grey read as it is, not as a colour)
        var shellArea = CIImage(cgImage: shell, options: [.colorSpace: NSNull()])
        if shellArea.extent.size != input.extent.size {
            shellArea = shellArea.transformed(by: CGAffineTransform(scaleX: input.extent.width / shellArea.extent.width, y: input.extent.height / shellArea.extent.height))
        }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = cube.outputImage
        blend.backgroundImage = input
        blend.maskImage = shellArea
        guard let out = blend.outputImage, let made = context.createCGImage(out, from: input.extent, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return Self.picture(made)
    }
    /// A picture made smaller, `height` pixels high.
    static func scaled(_ picture: PencilImages.Picture, height: Double) -> PencilImages.Picture? {
        guard let base = cgImage(picture), base.height > 0 else { return nil }
        let k = min(1, height / Double(base.height))
        let small = CIImage(cgImage: base).transformed(by: CGAffineTransform(scaleX: k, y: k))
        let rect = CGRect(x: 0, y: 0, width: (Double(base.width) * k).rounded(.down), height: (Double(base.height) * k).rounded(.down))
        guard let made = context.createCGImage(small, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return Self.picture(made)
    }
}

// (What goes on the lid, and where: PencilThing, PencilPiece, PencilNote,
// PencilLayout, Domain.swift — the unit checks read them there.)

// MARK: - The box

/// What is on the lid and what waits in the tray, kept in `pencilbox/`
/// (box.json; each photo and note a file of its own beside it).
@MainActor final class PencilBoxStore: ObservableObject {
    static let shared = PencilBoxStore()
    @Published private(set) var lid: [PencilPiece] = []
    @Published private(set) var tray: [PencilPiece] = []
    /// What is left of each pencil (1: new; PencilSharpening.shortest at the least).
    @Published private(set) var lengths: [PencilTool: Double] = [:]
    /// 11-15: the two grooves beside the ruler, the pencil in each (nil: none). A pencil stuck on the lid keeps
    /// its groove, its hollow there, until a pencil taken out of the rack is wanted in it; every other pencil
    /// stands in the rack (PencilGrooves).
    @Published private(set) var grooves: [PencilTool?] = PencilTool.firstGrooves
    /// The groove filled last.
    private var lastFilled = 1
    /// The curls of shaving in each style's sharpener, oldest first (11-17: every style of box has its own; one
    /// with no list yet is a new box, three curls in its window).
    @Published private var sharpeners: [PencilBoxStyle: [PencilShaving]] = [:]
    /// 11-19: what is written in the timetable's boxes, once one of them has been changed (nil: what each box's
    /// picture had printed, PencilTimetable.printed).
    @Published private(set) var timetable: [String]?
    func lessons(in style: PencilBoxStyle) -> [String] { timetable ?? PencilTimetable.printed(style) }
    func setTimetable(_ cells: [String]) {
        let whole = PencilTimetable.whole(cells)
        guard whole != timetable else { return }
        timetable = whole
        NSLog("[pencil] the timetable written: %d of its boxes have something in them", whole.filter { !$0.isEmpty }.count)
        save()
    }
    private static let unopened: [PencilBoxStyle: [PencilShaving]] =
        Dictionary(uniqueKeysWithValues: PencilBoxStyle.allCases.map { ($0, PencilSharpening.firstShavings()) })
    func shavings(in style: PencilBoxStyle) -> [PencilShaving] { sharpeners[style] ?? Self.unopened[style] ?? [] }
    /// Those of the box in use.
    var sharpener: [PencilShaving] { shavings(in: PencilBoxLook.stored.style) }
    private func changeSharpener(_ change: (inout [PencilShaving]) -> Void) {
        let style = PencilBoxLook.stored.style
        var list = shavings(in: style)
        change(&list)
        sharpeners[style] = list
    }
    /// Turns of sharpening so far (every other one sheds a curl).
    private var turns = 0
    /// Goes up whenever a photo or a note changes (their pictures are drawn anew).
    @Published private(set) var revision = 0
    /// 11-15: postcards come from 画框 (PencilPostcards) — those not seen in the box yet (they say 新 there, and
    /// the box in the library's corner opens a crack); one more each time one comes, and which came last.
    @Published private(set) var freshPostcards: Set<FrameScene> = []
    @Published private(set) var arrived = 0
    private(set) var lastArrived: FrameScene?
    /// A debug build's `--foldarc-pencil-fresh`: the box as a new one has
    /// it, and nothing it gains is kept (the tests').
    static let fresh: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--foldarc-pencil-fresh")
        #else
        return false
        #endif
    }()
    static var folder: URL { Storage.root.appendingPathComponent("pencilbox", isDirectory: true) }
    private static var file: URL { folder.appendingPathComponent("box.json") }
    private struct Kept: Codable {
        var lid: [PencilPiece]
        var tray: [PencilPiece]
        var lengths: [String: Double]?
        var sharpener: [PencilShaving]?
        var sharpeners: [String: [PencilShaving]]?
        var grooves: [PencilTool?]?
        var freshPostcards: [FrameScene]?
        var timetable: [String]?
    }
    private var notes: [UUID: PencilNote] = [:]

    private init() {
        if !Self.fresh, let data = try? Data(contentsOf: Self.file), let kept = try? JSONDecoder().decode(Kept.self, from: data) {
            lid = kept.lid
            tray = kept.tray
            for (name, left) in kept.lengths ?? [:] { if let tool = PencilTool(rawValue: name) { lengths[tool] = left } }
            sharpeners = PencilSharpening.kept(kept.sharpeners, shared: kept.sharpener, style: PencilBoxLook.stored.style)
            grooves = PencilGrooves.sound(kept.grooves)
            freshPostcards = Set(kept.freshPostcards ?? []).intersection(PencilPostcards.had(lid + tray))
            timetable = kept.timetable.map(PencilTimetable.whole)
        } else {
            lid = Self.firstLid()
        }
    }
    static func firstLid() -> [PencilPiece] {
        PencilLayout.first.enumerated().map { index, item in
            let (thing, x, y, angle) = item
            return PencilPiece(id: UUID(), kind: thing == nil ? .note : .thing, thing: thing,
                               x: x / PencilArt.lid.width, y: y / PencilArt.lid.height, angle: angle, scale: 1, z: index,
                               magnet: thing == nil ? .red : nil, grid: thing == nil ? false : nil)
        }
    }
    private func save() {
        guard !Self.fresh else { return }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Kept(lid: lid, tray: tray, lengths: Dictionary(uniqueKeysWithValues: lengths.map { ($0.key.rawValue, $0.value) }),
                                                     sharpener: nil,
                                                     sharpeners: Dictionary(uniqueKeysWithValues: sharpeners.map { ($0.key.rawValue, $0.value) }),
                                                     grooves: grooves,
                                                     freshPostcards: freshPostcards.isEmpty ? nil : FrameScene.allCases.filter(freshPostcards.contains),
                                                     timetable: timetable))
            try data.write(to: Self.file, options: .atomic)
        } catch {
            NSLog("[pencil] could not keep the box: %@", error.localizedDescription)
        }
    }

    // MARK: What there is

    /// The tin has brought it (or it was in the box from the start).
    func has(_ thing: PencilThing) -> Bool { thing.source.map { TinBoxStore.shared.has($0) } ?? true }
    func onLid(_ thing: PencilThing) -> Bool { lid.contains { $0.thing == thing } }
    /// The box's own things it has, in order; and the player's own waiting in the tray.
    var things: [PencilThing] { PencilThing.allCases.filter(has) }
    /// New paper is squared once the tin has its exercise paper.
    var squaredPaper: Bool { TinBoxStore.shared.has(.gridPaper) }
    func piece(_ id: UUID) -> PencilPiece? { lid.first { $0.id == id } ?? tray.first { $0.id == id } }

    // MARK: Onto the lid and off it

    private var topZ: Int { (lid.map(\.z).max() ?? 0) + 1 }
    private func spot() -> (Double, Double) { PencilLayout.freeSpot(among: lid.map { ($0.x, $0.y) }) }
    /// One of the box's things onto the lid, where there is room.
    func stick(_ thing: PencilThing) {
        guard has(thing), !onLid(thing) else { return }
        let (x, y) = spot()
        lid.append(PencilPiece(id: UUID(), kind: .thing, thing: thing, x: x, y: y, angle: Double.random(in: -0.08...0.08), scale: 1, z: topZ))
        NSLog("[pencil] %@ onto the lid", thing.rawValue)
        save()
    }
    /// A photo or a note from the tray onto the lid.
    func stick(_ id: UUID) {
        guard var piece = tray.first(where: { $0.id == id }) else { return }
        tray.removeAll { $0.id == id }
        (piece.x, piece.y) = spot()
        piece.z = topZ
        lid.append(piece)
        save()
    }
    /// Off the lid: the box's own back into it (a tool to its groove; a pencil whose groove another took, into
    /// an empty one, else the rack); a photo or a note into the tray; a curl of shaving back into the sharpener.
    func takeOff(_ id: UUID) {
        guard let piece = lid.first(where: { $0.id == id }) else { return }
        lid.removeAll { $0.id == id }
        switch piece.kind {
        case .photo, .note, .postcard: tray.insert(piece, at: 0)
        case .shaving: dropInSharpener(piece.tool ?? .green, shape: piece.shape ?? 0)
        case .tool:
            if let pencil = piece.tool, pencil.isPencil, groove(of: pencil) == nil, let empty = grooves.firstIndex(where: { $0 == nil }) {
                grooves[empty] = pencil
                lastFilled = empty
            }
        case .thing: break
        }
        NSLog("[pencil] %@ off the lid", piece.thing?.rawValue ?? piece.tool?.rawValue ?? piece.kind.rawValue)
        save()
    }

    // MARK: The tools

    func length(_ tool: PencilTool) -> Double { tool.isPencil ? (lengths[tool] ?? 1) : 1 }
    func onLid(_ tool: PencilTool) -> Bool { lid.contains { $0.kind == .tool && $0.tool == tool } }
    /// The groove a pencil is in (on the lid, its hollow's), if it has one.
    func groove(of tool: PencilTool) -> Int? { grooves.firstIndex(of: tool) }
    /// Standing in the rack: a pencil in no groove and not on the lid.
    func inRack(_ tool: PencilTool) -> Bool { tool.isPencil && groove(of: tool) == nil && !onLid(tool) }
    /// The pencils standing in the rack, in the order of its holes.
    var rack: [PencilTool] { PencilTool.pencils.filter(inRack) }
    /// A pencil out of the rack into a groove (PencilGrooves.choose); the groove it went into, and the pencil that
    /// went back into the rack to make room, if one did.
    @discardableResult func takeOut(_ tool: PencilTool) -> (groove: Int, back: PencilTool?)? {
        guard inRack(tool) else { return nil }
        let slot = PencilGrooves.choose(grooves, onLid: { onLid($0) }, lastFilled: lastFilled)
        let back = grooves[slot].flatMap { onLid($0) ? nil : $0 }
        grooves[slot] = tool
        lastFilled = slot
        NSLog("[pencil] the %@ pencil out of the rack into groove %ld%@", tool.rawValue, slot, back.map { " (the \($0.rawValue) one back into the rack)" } ?? "")
        save()
        return (slot, back)
    }
    /// A pencil from its groove back into the rack (not one on the lid).
    func putBack(_ tool: PencilTool) {
        guard let slot = groove(of: tool), !onLid(tool) else { return }
        grooves[slot] = nil
        NSLog("[pencil] the %@ pencil back into the rack", tool.rawValue)
        save()
    }
    /// The ruler or a pencil onto the lid, where there is room (lying a little aslant).
    func stick(_ tool: PencilTool) {
        guard !onLid(tool) else { return }
        let (x, y) = spot()
        lid.append(PencilPiece(id: UUID(), kind: .tool, thing: nil, tool: tool, x: x, y: y, angle: Double.random(in: -0.25...0.25), scale: 1, z: topZ))
        NSLog("[pencil] the %@ onto the lid", tool.rawValue)
        save()
    }
    /// One turn of a pencil in the sharpener: a little shorter; every other turn a curl of shaving drops into the
    /// sharpener (returned). Nothing, and false, once it is a stub.
    @discardableResult func sharpen(_ tool: PencilTool) -> (turned: Bool, shaving: PencilShaving?) {
        guard tool.isPencil, !onLid(tool), PencilSharpening.canSharpen(length(tool)) else { return (false, nil) }
        lengths[tool] = PencilSharpening.after(length(tool))
        turns += 1
        var shed: PencilShaving?
        if PencilSharpening.sheds(onTurn: turns) { shed = dropInSharpener(tool, shape: Int.random(in: 0...2)) }
        save()
        return (true, shed)
    }
    @discardableResult private func dropInSharpener(_ tool: PencilTool, shape: Int) -> PencilShaving {
        // (a heap: the newer ones on top and nearer the middle)
        let bit = PencilShaving(id: UUID(), tool: tool, shape: shape, x: Double.random(in: 0.22...0.78), y: Double.random(in: 0.3...0.8),
                                turn: Double.random(in: -Double.pi...Double.pi))
        changeSharpener { list in
            list.append(bit)
            if list.count > PencilSharpening.held { list.removeFirst(list.count - PencilSharpening.held) }
        }
        return bit
    }
    /// The newest curl in the sharpener onto the lid.
    @discardableResult func stickShaving() -> Bool {
        guard let bit = sharpener.last else { return false }
        changeSharpener { $0.removeLast() }
        let (x, y) = spot()
        lid.append(PencilPiece(id: UUID(), kind: .shaving, thing: nil, tool: bit.tool, shape: bit.shape, x: x, y: y, angle: bit.turn, scale: 1, z: topZ))
        NSLog("[pencil] a curl of %@ shaving onto the lid", bit.tool.rawValue)
        save()
        return true
    }
    /// The sharpener tipped out.
    func emptySharpener() {
        changeSharpener { $0.removeAll() }
        save()
    }
    /// A pencil as new again (a stub put away, a new one taken out).
    func newPencil(_ tool: PencilTool) {
        lengths[tool] = nil
        save()
    }
    /// A photo or a note gone for good (its file too). (A postcard is kept.)
    func discard(_ id: UUID) {
        // (a postcard 画框 sent is never thrown away; one made here may be)
        guard let piece = piece(id), piece.kind != .thing, piece.kind != .postcard || piece.isMadeCard else { return }
        lid.removeAll { $0.id == id }
        tray.removeAll { $0.id == id }
        notes[id] = nil
        if let name = piece.ownFile, !Self.fresh { try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(name)) }
        if piece.kind == .postcard {
            forgetCardPicture("card-\(id.uuidString).jpg")
            forgetCardPicture("stamp-\(id.uuidString).jpg")
            #if os(iOS)
            forgetCardSource(id)
            #endif
        }
        save()
    }
    func move(_ id: UUID, x: Double, y: Double) {
        guard let index = lid.firstIndex(where: { $0.id == id }) else { return }
        (lid[index].x, lid[index].y) = PencilLayout.clamp(x, y)
        save()
    }
    func set(_ id: UUID, angle: Double, scale: Double) {
        guard let index = lid.firstIndex(where: { $0.id == id }) else { return }
        lid[index].angle = PencilLayout.snapped(angle)
        lid[index].scale = PencilLayout.clampScale(scale)
        save()
    }
    func raise(_ id: UUID) {
        guard let index = lid.firstIndex(where: { $0.id == id }), lid[index].z != topZ - 1 else { return }
        lid[index].z = topZ
    }
    /// The lid as a new box has it; photos, postcards and notes written on go into the tray.
    func reset() {
        let own = lid.filter { $0.kind == .photo || $0.kind == .postcard || ($0.kind == .note && note($0.id)?.isBlank == false) }
        tray.insert(contentsOf: own, at: 0)
        lid = Self.firstLid()
        save()
    }

    // MARK: The postcards

    /// The box has this scenery's postcard (on the lid or in it).
    func hasPostcard(_ scene: FrameScene) -> Bool { PencilPostcards.had(lid + tray).contains(scene) }
    /// A scenery looked at a while (画框): its postcard comes into the box, into the postcards' slot — once.
    @discardableResult func sendPostcard(_ scene: FrameScene) -> Bool {
        guard !hasPostcard(scene) else { return false }
        tray.insert(PencilPiece(id: UUID(), kind: .postcard, x: 0.5, y: 0.5, angle: 0, scale: 1, z: 0, magnet: .yellow, scene: scene), at: 0)
        freshPostcards.insert(scene)
        lastArrived = scene
        arrived += 1
        NSLog("[pencil] a postcard of %@ into the box", scene.rawValue)
        save()
        return true
    }
    /// The box has been open: its new postcards are seen.
    func seenPostcards() {
        guard !freshPostcards.isEmpty else { return }
        freshPostcards = []
        save()
    }
    /// A postcard on the lid turned over (its back up, or its picture again).
    func flip(_ id: UUID) {
        guard let index = lid.firstIndex(where: { $0.id == id }), lid[index].kind == .postcard else { return }
        lid[index].back = lid[index].back == true ? nil : true
        NSLog("[pencil] the %@ postcard turned to its %@", lid[index].scene?.rawValue ?? "?", lid[index].back == true ? "back" : "picture")
        save()
    }

    // MARK: A postcard made one's own (11-16)

    private func changeCard(_ id: UUID, _ change: (inout PencilPiece) -> Void) {
        if let index = lid.firstIndex(where: { $0.id == id && $0.kind == .postcard }) {
            change(&lid[index])
        } else if let index = tray.firstIndex(where: { $0.id == id && $0.kind == .postcard }) {
            change(&tray[index])
        } else {
            return
        }
        revision += 1
        save()
    }
    private func forgetCardPicture(_ name: String) {
        #if os(iOS)
        cardPictures[name] = nil
        #endif
        if !Self.fresh { try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(name)) }
    }
    /// What is written on a postcard's back: the words along its lines (what they hold), its postcode's digits.
    func write(card id: UUID, words: String, postcode: String) {
        let words = PencilCard.held(words), postcode = PencilCard.digits(postcode)
        changeCard(id) { $0.words = words.isEmpty ? nil : words; $0.postcode = postcode.isEmpty ? nil : postcode }
        NSLog("[pencil] a postcard's back written on: %d characters, %d digits", words.count, postcode.count)
    }
    /// Another scenery's stamp on a postcard's back (nil: its own scenery's again).
    func setStamp(_ id: UUID, scene: FrameScene?) {
        changeCard(id) { $0.stampScene = scene == $0.scene ? nil : scene; $0.ownStamp = nil }
        forgetCardPicture("stamp-\(id.uuidString).jpg")
        NSLog("[pencil] a postcard's stamp: %@", scene?.rawValue ?? "its own")
    }
    /// A picture of one's own as a postcard's stamp.
    @discardableResult func setStamp(_ id: UUID, picture data: Data) -> Bool {
        #if os(iOS)
        guard piece(id)?.kind == .postcard, keepCardPicture(data, as: "stamp-\(id.uuidString).jpg", longest: 360) else { return false }
        changeCard(id) { $0.ownStamp = true; $0.stampScene = nil }
        NSLog("[pencil] a postcard's stamp: a picture of one's own")
        return true
        #else
        return false
        #endif
    }
    /// A picture of one's own on a postcard's front. 11-22: kept as it was given (cardsrc-<id>.jpg) and, for every
    /// place a postcard is drawn, the part its window shows (card-<id>.jpg): its middle, until it is dragged.
    @discardableResult func setCardFront(_ id: UUID, picture data: Data) -> Bool {
        #if os(iOS)
        guard let card = piece(id), card.kind == .postcard, keepCardFront(data, id: id) else { return false }
        // (one made here that has no stamp yet: the picture, small, is its stamp too)
        let stampToo = card.isMadeCard && card.ownStamp != true && card.stampScene == nil && keepCardPicture(data, as: "stamp-\(id.uuidString).jpg", longest: 360)
        changeCard(id) { $0.ownFront = true; $0.frontPlace = nil; if stampToo { $0.ownStamp = true } }
        NSLog("[pencil] a postcard's front: a picture of one's own")
        return true
        #else
        return false
        #endif
    }
    /// A postcard made of a picture of one's own: the picture on its front and, small, as its stamp; its back
    /// blank. It comes into the postcards' slot (11-16).
    @discardableResult func addCard(_ data: Data) -> UUID? {
        #if os(iOS)
        let id = UUID()
        guard keepCardFront(data, id: id),
              keepCardPicture(data, as: "stamp-\(id.uuidString).jpg", longest: 360) else { return nil }
        tray.insert(PencilPiece(id: id, kind: .postcard, x: 0.5, y: 0.5, angle: 0, scale: 1, z: 0, magnet: .yellow, ownFront: true, ownStamp: true), at: 0)
        NSLog("[pencil] a postcard made of a picture of one's own")
        save()
        return id
        #else
        return nil
        #endif
    }
    /// 11-17: a postcard made here with nothing on it yet — no picture, its back blank (PencilBigCard gives it
    /// them). It comes into the postcards' slot with the others.
    @discardableResult func addBlankCard() -> UUID? {
        let id = UUID()
        tray.insert(PencilPiece(id: id, kind: .postcard, x: 0.5, y: 0.5, angle: 0, scale: 1, z: 0, magnet: .yellow), at: 0)
        NSLog("[pencil] a blank postcard taken to be made")
        save()
        return id
    }
    /// The scenery on a postcard's front again.
    func clearCardFront(_ id: UUID) {
        changeCard(id) { $0.ownFront = nil; $0.frontPlace = nil }
        forgetCardPicture("card-\(id.uuidString).jpg")
        #if os(iOS)
        forgetCardSource(id)
        #endif
        NSLog("[pencil] a postcard's front: its scenery again")
    }
    #if os(iOS)
    private var cardPictures: [String: UIImage] = [:]
    private func cardPicture(_ name: String) -> UIImage? {
        if let hit = cardPictures[name] { return hit }
        guard let image = UIImage(contentsOfFile: Self.folder.appendingPathComponent(name).path) else { return nil }
        cardPictures[name] = image
        return image
    }
    func cardFront(_ id: UUID) -> UIImage? { cardPicture("card-\(id.uuidString).jpg") }
    func stampPicture(_ id: UUID) -> UIImage? { cardPicture("stamp-\(id.uuidString).jpg") }
    private func keepCardPicture(_ data: Data, as name: String, longest: CGFloat) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        return keepCardImage(Self.shrunk(image, longest: longest), as: name)
    }
    private func keepCardImage(_ image: UIImage, as name: String) -> Bool {
        guard let small = image.jpegData(compressionQuality: 0.85) else { return false }
        if !Self.fresh {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            do { try small.write(to: Self.folder.appendingPathComponent(name), options: .atomic) } catch { return false }
        }
        cardPictures[name] = UIImage(data: small)
        return true
    }

    // 11-22: a front's picture as it was given, and the part of it the window shows.
    /// (a debug build's fresh box writes nothing: the pictures as given stay here while it runs)
    private var freshSources: [String: Data] = [:]
    /// The last picture as given that was read (the one being placed): only one is held.
    private var lastSource: (name: String, image: UIImage)?
    /// The picture on a front kept as given (upright, at most 2000 pixels on its longer side), and the part of it
    /// the window shows at its middle.
    private func keepCardFront(_ data: Data, id: UUID) -> Bool {
        guard let picked = UIImage(data: data) else { return false }
        let source = Self.upright(picked, longest: 2000)
        guard keepCardSource(source, id: id), let part = Self.windowPart(of: source, place: nil) else { return false }
        return keepCardImage(Self.shrunk(part, longest: 900), as: "card-\(id.uuidString).jpg")
    }
    private func keepCardSource(_ image: UIImage, id: UUID) -> Bool {
        let name = "cardsrc-\(id.uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: 0.9) else { return false }
        if Self.fresh { freshSources[name] = data } else {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            do { try data.write(to: Self.folder.appendingPathComponent(name), options: .atomic) } catch { return false }
        }
        lastSource = (name, image)
        return true
    }
    private func forgetCardSource(_ id: UUID) {
        let name = "cardsrc-\(id.uuidString).jpg"
        freshSources[name] = nil
        if lastSource?.name == name { lastSource = nil }
        if !Self.fresh { try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(name)) }
    }
    /// The picture on a postcard's front as it was given. (One given before 11-22: the front kept the whole
    /// picture then; from the first time it is placed, that is the one given.)
    func cardSource(_ id: UUID) -> UIImage? {
        let name = "cardsrc-\(id.uuidString).jpg"
        if let last = lastSource, last.name == name { return last.image }
        var data: Data?
        if Self.fresh { data = freshSources[name] } else { data = try? Data(contentsOf: Self.folder.appendingPathComponent(name)) }
        if let data, let image = UIImage(data: data) {
            lastSource = (name, image)
            return image
        }
        guard let card = piece(id), card.ownFront == true, card.frontPlace == nil, let whole = cardFront(id) else { return nil }
        let source = Self.upright(whole, longest: 2000)
        return keepCardSource(source, id: id) ? source : nil
    }
    /// The picture on a postcard's front placed again (dragged and pinched on the big postcard): the part its
    /// window shows is cut again from the picture as it was given.
    @discardableResult func placeCardFront(_ id: UUID, place: [Double]) -> Bool {
        guard let card = piece(id), card.kind == .postcard, card.ownFront == true, let source = cardSource(id) else { return false }
        let kept = PencilCardPlace.kept(place, size: source.size)
        guard let part = Self.windowPart(of: source, place: kept),
              keepCardImage(Self.shrunk(part, longest: 900), as: "card-\(id.uuidString).jpg") else { return false }
        changeCard(id) { $0.frontPlace = kept }
        NSLog("[pencil] a postcard's picture placed: %.2f, %.2f, ×%.1f", kept[0], kept[1], kept[2])
        return true
    }
    /// The part of `image` (upright, one pixel a point) a postcard front's window shows for `place`.
    static func windowPart(of image: UIImage, place: [Double]?) -> UIImage? {
        guard let whole = image.cgImage else { return nil }
        let size = CGSize(width: whole.width, height: whole.height)
        let rect = PencilCardPlace.part(of: size, place: place).integral.intersection(CGRect(origin: .zero, size: size))
        guard !rect.isEmpty, let part = whole.cropping(to: rect) else { return nil }
        return UIImage(cgImage: part)
    }
    /// A picture the right way up (its orientation drawn in), one pixel a point, at most `longest` on its longer side.
    static func upright(_ picture: UIImage, longest: CGFloat) -> UIImage {
        let size = picture.size
        let k = min(1, longest / max(1, max(size.width, size.height)))
        let target = CGSize(width: max(1, (size.width * k).rounded()), height: max(1, (size.height * k).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in picture.draw(in: CGRect(origin: .zero, size: target)) }
    }
    #endif

    // MARK: The player's own

    /// A photo (the album's, or one picked from Photos) onto the lid, kept as
    /// a small JPEG of its own.
    @discardableResult func addPhoto(_ data: Data) -> UUID? {
        #if os(iOS)
        guard let image = UIImage(data: data), let small = Self.shrunk(image, longest: 900).jpegData(compressionQuality: 0.85) else { return nil }
        let id = UUID()
        if !Self.fresh {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            do { try small.write(to: Self.folder.appendingPathComponent("photo-\(id.uuidString).jpg"), options: .atomic) } catch { return nil }
        }
        photos[id] = UIImage(data: small)
        let (x, y) = spot()
        lid.append(PencilPiece(id: id, kind: .photo, x: x, y: y, angle: Double.random(in: -0.07...0.07), scale: 1, z: topZ, magnet: .blue))
        NSLog("[pencil] a photo onto the lid")
        save()
        return id
        #else
        return nil
        #endif
    }
    /// Another picture in a photo's frame: where it is, its turn, its size and its magnet stay.
    @discardableResult func replacePhoto(_ id: UUID, with data: Data) -> Bool {
        #if os(iOS)
        guard piece(id)?.kind == .photo, let image = UIImage(data: data), let small = Self.shrunk(image, longest: 900).jpegData(compressionQuality: 0.85) else { return false }
        if !Self.fresh {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            do { try small.write(to: Self.folder.appendingPathComponent("photo-\(id.uuidString).jpg"), options: .atomic) } catch { return false }
        }
        photos[id] = UIImage(data: small)
        revision += 1
        NSLog("[pencil] a photo changed for another")
        return true
        #else
        return false
        #endif
    }
    /// A note onto the lid (written here, or a page of 游戏笔记 copied).
    @discardableResult func addNote(_ note: PencilNote) -> UUID {
        let id = UUID()
        notes[id] = note
        writeNote(id, note)
        let (x, y) = spot()
        lid.append(PencilPiece(id: id, kind: .note, x: x, y: y, angle: Double.random(in: -0.06...0.06), scale: 1, z: topZ, magnet: .red, grid: note.grid))
        NSLog("[pencil] a note onto the lid")
        save()
        return id
    }
    func note(_ id: UUID) -> PencilNote? {
        if let note = notes[id] { return note }
        guard let data = try? Data(contentsOf: Self.folder.appendingPathComponent("note-\(id.uuidString).json")),
              let note = try? JSONDecoder().decode(PencilNote.self, from: data) else {
            return piece(id)?.kind == .note ? .blank(grid: piece(id)?.grid == true) : nil
        }
        notes[id] = note
        return note
    }
    func update(_ id: UUID, note: PencilNote) {
        notes[id] = note
        writeNote(id, note)
        if let index = lid.firstIndex(where: { $0.id == id }) { lid[index].grid = note.grid }
        if let index = tray.firstIndex(where: { $0.id == id }) { tray[index].grid = note.grid }
        revision += 1
        save()
    }
    private func writeNote(_ id: UUID, _ note: PencilNote) {
        guard !Self.fresh, let data = try? JSONEncoder().encode(note) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.folder.appendingPathComponent("note-\(id.uuidString).json"), options: .atomic)
    }
    #if os(iOS)
    private var photos: [UUID: UIImage] = [:]
    func photo(_ id: UUID) -> UIImage? {
        if let hit = photos[id] { return hit }
        guard let image = UIImage(contentsOfFile: Self.folder.appendingPathComponent("photo-\(id.uuidString).jpg").path) else { return nil }
        photos[id] = image
        return image
    }
    static func shrunk(_ image: UIImage, longest: CGFloat) -> UIImage {
        let size = image.size
        let k = min(1, longest / max(size.width, size.height))
        guard k < 1 else { return image }
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
    #endif
}

extension PencilPiece {
    /// Its name as read out: a postcard's with its scenery's.
    var fullTitle: String {
        guard kind == .postcard else { return title }
        guard let scene else { return String(localized: "明信片：自己做的") }
        return String(localized: "明信片：\(scene.title)")
    }
    /// A postcard's name among the others: its scenery's, or that it is one's own.
    var cardName: String { scene?.title ?? String(localized: "自己做的") }
}

// MARK: - The handwriting typeface

/// Typed words on a note are set in one of the system's handwriting
/// typefaces (手札体), which iOS fetches the first time it is asked for;
/// until it is there, a rounded face stands in.
@MainActor final class PencilHandFont: ObservableObject {
    static let shared = PencilHandFont()
    @Published private(set) var ready: Set<PencilHand> = []
    private var asked: Set<PencilHand> = []
    private init() { ready = Set(PencilHand.allCases.filter { Self.installed($0.rawValue) }) }
    static func installed(_ name: String) -> Bool {
        #if os(iOS)
        return UIFont(name: name, size: 12) != nil
        #else
        return NSFont(name: name, size: 12) != nil
        #endif
    }
    /// Asks iOS for a handwriting once; until it is here, the words are in
    /// the rounded system face.
    func ensure(_ hand: PencilHand = .notes) {
        guard !ready.contains(hand), !asked.contains(hand) else { return }
        asked.insert(hand)
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: hand.rawValue] as CFDictionary)
        _ = CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, _ in
            if state == .didFinish {
                Task { @MainActor in PencilHandFont.shared.finished(hand) }
            }
            return true
        }
        NSLog("[pencil] asked for the handwriting typeface %@", hand.rawValue)
    }
    private func finished(_ hand: PencilHand) {
        if Self.installed(hand.rawValue) { ready.insert(hand) }
        NSLog("[pencil] the handwriting typeface %@ is %@", hand.rawValue, ready.contains(hand) ? "here" : "not here")
    }
    func font(_ hand: PencilHand = .notes, size: CGFloat) -> Font {
        ready.contains(hand) ? .custom(hand.rawValue, size: size) : .system(size: size, weight: .regular, design: .rounded)
    }
}

// MARK: - A thing that plays, drawn

/// A view placed as a pose has it: stretched and turned about a point of the picture (points of it), and moved.
struct PencilPosed: ViewModifier {
    var pose: PencilPartPose
    var pivot: CGPoint
    var size: CGSize
    /// Screen points a point of the picture.
    var k: Double
    func body(content: Content) -> some View {
        let anchor = UnitPoint(x: pivot.x / max(1, size.width), y: pivot.y / max(1, size.height))
        content
            .scaleEffect(x: pose.sx, y: pose.sy, anchor: anchor)
            .rotationEffect(.radians(pose.angle), anchor: anchor)
            .offset(x: pose.x * k, y: pose.y * k)
    }
}

/// 11-17: the face of one of the box's things that does something when it is touched (PencilPlay), at `k`
/// screen points a point of its picture: at rest, or, `played` being when it was touched, where the play has it
/// and its parts at each moment. A thing drawn in layers is always put together of them here (they make up its
/// one picture exactly), so nothing changes when a play begins or ends.
struct PencilThingFace: View {
    var thing: PencilThing
    var k: Double
    var played: Date?

    var body: some View {
        if let play = thing.play {
            if let played {
                TimelineView(.animation) { context in
                    drawn(play, play.placed(at: context.date.timeIntervalSince(played)))
                }
            } else {
                drawn(play, .still)
            }
        } else {
            PencilImages.image(thing.art.file).resizable()
                .frame(width: thing.art.size.width * k, height: thing.art.size.height * k)
        }
    }

    private func drawn(_ play: PencilPlay, _ pose: PencilPose) -> some View {
        let size = thing.art.size, w = size.width * k, h = size.height * k
        return ZStack {
            if play.layers.isEmpty {
                PencilImages.image(thing.art.file).resizable()
            } else {
                ForEach(play.layers, id: \.file) { layer in
                    let moved = PencilImages.image(layer.file).resizable()
                        .frame(width: w, height: h)
                        .modifier(PencilPosed(pose: pose.part(layer.part), pivot: layer.pivot, size: size, k: k))
                    if layer.windowed, let window = play.window {
                        moved.mask { PencilImages.image(window).resizable().frame(width: w, height: h) }
                    } else {
                        moved
                    }
                }
            }
        }
        .frame(width: w, height: h)
        .modifier(PencilPosed(pose: pose.whole, pivot: play.pivot, size: size, k: k))
    }
}

// MARK: - A piece, drawn

/// A piece as the lid shows it, at `u` screen points a lid point, sized by
/// `scale`: its shadows (laid under it, moved away from the light by the
/// caller) or its face.
struct PencilPieceView: View {
    enum Layer { case shadow, face }
    var piece: PencilPiece
    var u: Double
    var scale: Double
    var layer: Layer
    /// The magnet that holds a print or a note on the lid (under the open
    /// box's straps, none).
    var magnets = true
    /// 11-17: when one of the box's things was touched (it plays: PencilPlay); nil, at rest.
    var played: Date? = nil
    @ObservedObject private var store = PencilBoxStore.shared

    var body: some View {
        let art = piece.art, k = u * scale
        ZStack {
            switch layer {
            case .shadow: shadows(art: art, k: k)
            case .face: face(art: art, k: k)
            }
        }
        .frame(width: art.size.width * k, height: art.size.height * k)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func shadows(art: PencilArt, k: Double) -> some View {
        switch piece.kind {
        case .tool:
            PencilToolPicture(tool: piece.tool ?? .ruler, left: store.length(piece.tool ?? .ruler), k: k * PencilToolArt.onLid, template: true)
                .foregroundStyle(PencilToolPicture.shade).blur(radius: 1.4 * k)
        case .shaving:
            PencilImages.image(art.file).renderingMode(.template).resizable()
                .foregroundStyle(PencilToolPicture.shade).blur(radius: 1.0 * k)
        default:
            standardShadows(art: art, k: k)
        }
    }
    /// Where the magnet holds it, from its middle.
    private var magnetAt: CGPoint {
        switch piece.kind {
        case .photo: return PencilArt.photoMagnet
        case .postcard: return PencilArt.postcardMagnet
        default: return PencilArt.noteMagnet
        }
    }
    @ViewBuilder private func standardShadows(art: PencilArt, k: Double) -> some View {
        PencilImages.image(art.shadowFile).resizable()
        if magnets, let magnet = piece.magnet {
            let at = magnetAt
            PencilImages.image(magnet.art.shadowFile).resizable()
                .frame(width: magnet.art.size.width * k, height: magnet.art.size.height * k)
                .offset(x: at.x * k, y: at.y * k)
        }
    }

    @ViewBuilder private func face(art: PencilArt, k: Double) -> some View {
        switch piece.kind {
        case .tool:
            PencilToolPicture(tool: piece.tool ?? .ruler, left: store.length(piece.tool ?? .ruler), k: k * PencilToolArt.onLid)
        case .shaving:
            PencilImages.image(art.file).resizable()
        case .thing:
            if let thing = piece.thing, thing.play != nil {
                PencilThingFace(thing: thing, k: k, played: played)
            } else {
                PencilImages.image(art.file).resizable()
            }
            if piece.thing == .calendar { PencilCalendarPage(k: k) }
            if piece.thing == .ginkgoLeaf {
                PencilImages.image(PencilArt.tape.file).resizable()
                    .frame(width: PencilArt.tape.size.width * k, height: PencilArt.tape.size.height * k)
                    .rotationEffect(.radians(PencilArt.leafTapeTurn))
                    .offset(x: PencilArt.leafTape.x * k, y: PencilArt.leafTape.y * k)
            }
        case .photo:
            photoPicture(k: k)
            PencilImages.image(art.file).resizable()
            if magnets { magnet(at: PencilArt.photoMagnet, k: k) }
        case .note:
            PencilImages.image(art.file).resizable()
            PencilNoteFace(id: piece.id, k: k, revision: store.revision)
            if magnets { magnet(at: PencilArt.noteMagnet, k: k) }
        case .postcard:
            PencilImages.image(art.file).resizable()
            // (11-16: made one's own: a picture of one's own on its front; on its back its stamp, postcode and words)
            if piece.back == true {
                PencilCardBack(piece: piece, k: k, revision: store.revision)
            } else if piece.ownFront == true {
                cardFront(k: k)
            } else if piece.isMadeCard {
                blankFront(k: k)
            }
            if magnets { magnet(at: PencilArt.postcardMagnet, k: k) }
        }
    }

    /// 11-17: the front of a postcard made here that has no picture yet: bare paper where its picture goes, a
    /// pencilled frame in it.
    private func blankFront(k: Double) -> some View {
        let window = PencilCard.frontWindow
        return Rectangle().fill(Color(red: 0.957, green: 0.933, blue: 0.87))
            .overlay(Rectangle().strokeBorder(PencilCardBack.line, lineWidth: max(0.5, 0.45 * k)))
            .overlay(RoundedRectangle(cornerRadius: 1.2 * k)
                .strokeBorder(Color(red: 0.36, green: 0.36, blue: 0.40).opacity(0.6), style: StrokeStyle(lineWidth: max(0.6, 0.5 * k), dash: [3.2 * k, 2.6 * k]))
                .padding(3.4 * k))
            .frame(width: window.width * k, height: window.height * k)
            .offset(x: window.midX * k, y: window.midY * k)
    }
    @ViewBuilder private func cardFront(k: Double) -> some View {
        #if os(iOS)
        if let picture = store.cardFront(piece.id) {
            let window = PencilCard.frontWindow
            Image(uiImage: picture).resizable().scaledToFill()
                .frame(width: window.width * k, height: window.height * k)
                .clipped()
                .overlay(Rectangle().strokeBorder(PencilCardBack.line, lineWidth: max(0.5, 0.45 * k)))
                .offset(x: window.midX * k, y: window.midY * k)
        }
        #endif
    }

    @ViewBuilder private func photoPicture(k: Double) -> some View {
        let window = PencilArt.photoWindow
        #if os(iOS)
        if let photo = store.photo(piece.id) {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: window.width * k, height: window.height * k)
                .clipped()
                .offset(x: window.midX * k, y: window.midY * k)
        } else {
            Color(white: 0.8).frame(width: window.width * k, height: window.height * k).offset(x: window.midX * k, y: window.midY * k)
        }
        #else
        Color(white: 0.8).frame(width: window.width * k, height: window.height * k).offset(x: window.midX * k, y: window.midY * k)
        #endif
    }

    private func magnet(at point: CGPoint, k: Double) -> some View {
        let art = (piece.magnet ?? .red).art
        return PencilImages.image(art.file).resizable()
            .frame(width: art.size.width * k, height: art.size.height * k)
            .offset(x: point.x * k, y: point.y * k)
    }
}

/// One of the box's tools as drawn, lying along its length (its back on the left, its point on the right), `k`
/// screen points a point of the drawing: the ruler; a pencil, its body cut to what is left of it, the point on.
/// `template`: its shape only (for its shadow, or the hollow it leaves).
struct PencilToolPicture: View {
    var tool: PencilTool
    var left: Double
    var k: Double
    var template = false
    static let shade = Color(red: 0.46, green: 0.40, blue: 0.35).opacity(0.55)
    static func size(_ tool: PencilTool, left: Double) -> CGSize {
        tool == .ruler ? PencilToolArt.ruler : CGSize(width: PencilToolArt.pencilWidth(left), height: PencilToolArt.body.height)
    }
    var body: some View {
        let size = Self.size(tool, left: left)
        Group {
            if tool == .ruler {
                picture(tool.bodyFile)
            } else {
                HStack(spacing: 0) {
                    picture(tool.bodyFile)
                        .frame(width: PencilToolArt.body.width * k, height: PencilToolArt.body.height * k)
                        .frame(width: (PencilToolArt.bodyBack + PencilToolArt.bodyLength * left) * k, alignment: .leading)
                        .clipped()
                    picture(tool.tipFile).frame(width: PencilToolArt.tip.width * k, height: PencilToolArt.tip.height * k)
                }
            }
        }
        .frame(width: size.width * k, height: size.height * k)
        .allowsHitTesting(false)
    }
    private func picture(_ file: String) -> some View {
        PencilImages.image(file).renderingMode(template ? .template : .original).resizable()
    }
}

/// A photo up close, to change it for another: swiped left or right through the console's album (the photo as it
/// is first), 就用这张 puts the one shown into its frame — where it is, its turn, its size and its magnet stay;
/// Photos' own picker below it (only what is picked comes to the app); a tap beside it changes nothing.
struct PencilPhotoSwap: View {
    var piece: PencilPiece
    /// What the picture is for: a photo's frame; 11-16: a postcard's front, or its stamp.
    var target: Target = .photo
    var close: () -> Void
    enum Target { case photo, cardFront, stamp }
    /// What is shown up close, in points of its drawing: the photo in its frame, the postcard's front, the stamp alone.
    private var frameSize: CGSize {
        switch target {
        case .photo: return PencilArt.photoFrame.size
        case .cardFront: return PencilArt.postcard(.campfire).size
        case .stamp: return CGSize(width: 26, height: 31)
        }
    }
    /// The picture's place in it, from its middle.
    private var window: CGRect {
        switch target {
        case .photo: return PencilArt.photoWindow
        case .cardFront: return PencilCard.frontWindow
        case .stamp:
            let size = PencilCard.stampPicture
            return CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        }
    }
    /// The picture as it is now.
    @ViewBuilder private var current: some View {
        switch target {
        case .photo:
            #if os(iOS)
            if let photo = store.photo(piece.id) { Image(uiImage: photo).resizable().scaledToFill() } else { Color(white: 0.8) }
            #else
            Color(white: 0.8)
            #endif
        case .cardFront:
            #if os(iOS)
            if piece.ownFront == true, let picture = store.cardFront(piece.id) { Image(uiImage: picture).resizable().scaledToFill() } else { Color.clear }
            #else
            Color.clear
            #endif
        case .stamp:
            GeometryReader { proxy in
                PencilStampPicture(id: piece.id, own: piece.ownStamp == true, scene: piece.stampScene ?? piece.scene ?? .campfire,
                                   k: proxy.size.width / PencilCard.stampPicture.width, revision: store.revision)
            }
        }
    }
    /// Under the picture: a postcard's front as printed, a stamp's paper. Over it: a photo's frame.
    @ViewBuilder private func under(k: Double) -> some View {
        switch target {
        case .photo: EmptyView()
        case .cardFront: PencilImages.image(PencilArt.postcard(piece.scene ?? .campfire).file).resizable()
        case .stamp:
            RoundedRectangle(cornerRadius: 1.4 * k).fill(Color(red: 0.98, green: 0.97, blue: 0.94))
                .overlay(RoundedRectangle(cornerRadius: 1.4 * k).strokeBorder(Self.ink.opacity(0.4), style: StrokeStyle(lineWidth: max(1, 0.45 * k), dash: [1.5 * k, 1.1 * k])))
        }
    }
    private func put(_ data: Data) -> Bool {
        switch target {
        case .photo: return store.replacePhoto(piece.id, with: data)
        case .cardFront: return store.setCardFront(piece.id, picture: data)
        case .stamp: return store.setStamp(piece.id, picture: data)
        }
    }
    @ObservedObject private var store = PencilBoxStore.shared
    @State private var album: [CameraPhoto] = []
    @State private var index = 0
    @State private var slide: CGFloat = 0
    @State private var shown: CGImage?
    #if os(iOS)
    @State private var item: PhotosPickerItem?
    #endif
    private static let ink = Color(red: 0.23, green: 0.17, blue: 0.14)
    private static let paper = Color(red: 0.97, green: 0.94, blue: 0.87)
    var body: some View {
        GeometryReader { proxy in
            let frame = frameSize, window = self.window
            let k = target == .stamp ? min(proxy.size.width * 0.45 / frame.width, proxy.size.height * 0.34 / frame.height)
                                     : min(proxy.size.width * 0.84 / frame.width, proxy.size.height * 0.5 / frame.height)
            let u = max(0.7, min(1.4, proxy.size.width / 466))
            ZStack {
                Color.black.opacity(0.42).contentShape(Rectangle()).onTapGesture { close() }
                    .accessibilityLabel(Text("不换了")).accessibilityAddTraits(.isButton)
                VStack(spacing: 14 * u) {
                    ZStack {
                        under(k: k).frame(width: frame.width * k, height: frame.height * k).allowsHitTesting(false)
                        Group {
                            if index == 0 {
                                current
                            } else if let shown {
                                Image(decorative: shown, scale: 1).resizable().scaledToFill()
                            } else {
                                Color(white: 0.85)
                            }
                        }
                        .frame(width: window.width * k, height: window.height * k).clipped()
                        .offset(x: window.midX * k, y: window.midY * k)
                        if target == .photo {
                            PencilImages.image(PencilArt.photoFrame.file).resizable().frame(width: frame.width * k, height: frame.height * k).allowsHitTesting(false)
                        }
                    }
                    .frame(width: frame.width * k, height: frame.height * k)
                    .rotationEffect(.radians(piece.angle * 0.3))
                    .offset(x: slide)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 8).onChanged { slide = $0.translation.width * 0.6 }.onEnded { value in
                        let next = value.translation.width < -50 ? index + 1 : (value.translation.width > 50 ? index - 1 : index)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { slide = 0 }
                        go(to: next)
                    })
                    .accessibilityElement()
                    .accessibilityLabel(Text("照片"))
                    .accessibilityValue(Text(verbatim: index == 0 ? String(localized: "现在这张") : "\(index) / \(album.count)"))
                    .accessibilityAdjustableAction { direction in go(to: direction == .increment ? index + 1 : index - 1) }
                    .accessibilityIdentifier("pencil-photo-swap")
                    Text(verbatim: album.isEmpty ? String(localized: "掌机相册里还没有照片：用相机拍几张") :
                            (index == 0 ? String(localized: "左右滑，换成掌机相册里的照片") : String(localized: "掌机相册 \(index) / \(album.count)")))
                        .font(.system(size: 12.5 * u, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                    HStack(spacing: 10 * u) {
                        Button { use() } label: {
                            Text("就用这张").font(.system(size: 14 * u, weight: .bold, design: .rounded))
                                .padding(.horizontal, 16 * u).frame(minHeight: max(40, 40 * u))
                                .background(Capsule().fill(index == 0 ? Self.paper.opacity(0.5) : Self.paper))
                        }
                        .disabled(index == 0)
                        .accessibilityIdentifier("pencil-photo-use")
                        #if os(iOS)
                        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                            Label("从 iPhone 照片里选", systemImage: "photo.on.rectangle")
                                .font(.system(size: 13 * u, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14 * u).frame(minHeight: max(40, 40 * u))
                                .background(Capsule().fill(Self.paper))
                        }
                        .accessibilityIdentifier("pencil-photo-picker")
                        #endif
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Self.ink)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .transition(.opacity)
        .task { album = CameraRoll.list().filter { !$0.isVideo }.sorted { $0.date > $1.date }.prefix(90).map { $0 } }
        #if os(iOS)
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            Task { @MainActor in
                if let data = try? await chosen.loadTransferable(type: Data.self), put(data) { ConsoleSounds.shared.play(.click) }
                close()
            }
        }
        #endif
    }
    private func go(to next: Int) {
        let to = min(max(0, next), album.count)
        guard to != index else { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        index = to
        ConsoleSounds.shared.play(.move)
        shown = nil
        guard to > 0 else { return }
        let url = album[to - 1].url
        Task {
            let picture = await Task.detached(priority: .userInitiated) { PencilPhotoSwap.read(url) }.value
            if index == to { shown = picture }
        }
    }
    private func use() {
        guard index > 0, let data = try? Data(contentsOf: album[index - 1].url) else { return }
        if put(data) { ConsoleSounds.shared.play(.click) }
        close()
    }
    nonisolated static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// What a postcard's back has been given (PencilCard): another stamp over the printed one, the postmark still
/// across its corner; its postcode's digits in their boxes; the words along its three lines, in the handwriting
/// typeface. Drawn from the picture's middle, `k` screen points a point of the picture.
struct PencilCardBack: View {
    var piece: PencilPiece
    var k: Double
    var revision: Int
    @ObservedObject private var hand = PencilHandFont.shared
    static let ink = Color(red: 0.22, green: 0.22, blue: 0.28)
    static let line = Color(red: 0.27, green: 0.22, blue: 0.18).opacity(0.62)
    var body: some View {
        let digits = Array(piece.postcode ?? "")
        let lines = PencilCard.lines(of: piece.words ?? "")
        ZStack {
            stamp
            ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                Text(verbatim: String(digit))
                    .font(.system(size: 6.4 * k, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .offset(x: PencilCard.box(index).x * k, y: PencilCard.box(index).y * k)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { index, words in
                Text(verbatim: words)
                    .font(hand.font(.notes, size: PencilCard.wordSize * k))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: PencilCard.lineLength * k, height: 10 * k, alignment: .bottomLeading)
                    .offset(x: (PencilCard.lineStart + PencilCard.lineLength / 2) * k, y: (PencilCard.lineYs[index] - 5.4) * k)
            }
        }
        .onAppear { if piece.words != nil { hand.ensure(.notes) } }
    }

    /// The stamp's picture changed: the scenery of another postcard's front, or one's own; the postmark over it.
    @ViewBuilder private var stamp: some View {
        if piece.ownStamp == true || piece.stampScene != nil {
            let size = PencilCard.stampPicture, at = PencilCard.stampMiddle
            PencilStampPicture(id: piece.id, own: piece.ownStamp == true, scene: piece.stampScene ?? piece.scene ?? .campfire, k: k, revision: revision)
                .frame(width: size.width * k, height: size.height * k)
                .clipped()
                .overlay(Rectangle().strokeBorder(Self.line, lineWidth: max(0.5, 0.4 * k)))
                .rotationEffect(.degrees(PencilCard.stampTurn))
                .offset(x: at.x * k, y: at.y * k)
            PencilImages.image("pencilbox-postcard-\((piece.scene ?? .campfire).rawValue)-mark.png").resizable()
        }
    }
}

/// A stamp's little picture: a scenery as its postcard's front has it (the picture in its middle filling the
/// stamp), or a picture of one's own.
struct PencilStampPicture: View {
    var id: UUID
    var own: Bool
    var scene: FrameScene
    var k: Double
    var revision: Int
    var body: some View {
        let size = PencilCard.stampPicture
        Group {
            if own {
                #if os(iOS)
                if let picture = PencilBoxStore.shared.stampPicture(id) {
                    Image(uiImage: picture).resizable().scaledToFill()
                } else {
                    Color(white: 0.85)
                }
                #else
                Color(white: 0.85)
                #endif
            } else {
                let art = PencilArt.postcard(scene), window = PencilCard.frontWindow
                let fill = max(size.width / window.width, size.height / window.height)
                PencilImages.image(art.file).resizable()
                    .frame(width: art.size.width * fill * k, height: art.size.height * fill * k)
            }
        }
        .frame(width: size.width * k, height: size.height * k)
        .clipped()
    }
}

/// The calendar's page: today, the weekend in red.
struct PencilCalendarPage: View {
    var k: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let date = context.date
            let weekday = Calendar.current.component(.weekday, from: date)
            let weekend = weekday == 1 || weekday == 7
            let red = Color(red: 0.76, green: 0.20, blue: 0.17), ink = Color(red: 0.24, green: 0.24, blue: 0.26)
            ZStack {
                HStack(spacing: 0) {
                    Text(verbatim: String(Calendar.current.component(.year, from: date))).font(.system(size: 7.0 * k, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(verbatim: Self.month(date)).font(.system(size: 7.6 * k, weight: .bold))
                }
                .foregroundStyle(ink)
                .frame(width: 54 * k)
                .offset(y: -13.4 * k)
                Text(verbatim: String(Calendar.current.component(.day, from: date))).font(.system(size: 37 * k, weight: .bold, design: .serif))
                    .foregroundStyle(weekend ? red : ink)
                    .offset(x: 1.2 * k, y: 9 * k)
                Text(verbatim: date.formatted(.dateTime.weekday(.wide))).font(.system(size: 9.2 * k, weight: .heavy))
                    .foregroundStyle(weekend ? red : ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 56 * k)
                    .offset(y: 32.2 * k)
            }
            .opacity(0.9)
        }
    }
    /// 十一月 in Chinese (as such calendars print it), Nov elsewhere.
    static func month(_ date: Date) -> String {
        let chinese = Locale.current.language.languageCode == .chinese
        return date.formatted(.dateTime.month(chinese ? .wide : .abbreviated))
    }
}

/// A note's writing: its strokes and its typed words, in the paper's area.
struct PencilNoteFace: View {
    var id: UUID
    var k: Double
    var revision: Int
    @ObservedObject private var hand = PencilHandFont.shared
    var body: some View {
        let area = PencilArt.noteArea
        let note = PencilBoxStore.shared.note(id)
        ZStack(alignment: .topLeading) {
            #if os(iOS)
            if let note, let picture = PencilNoteFace.strokes(note, id: id, revision: revision) {
                Image(uiImage: picture).resizable().scaledToFit()
                    .frame(width: area.width * k, height: area.height * k)
            }
            #endif
            if let note, !note.text.isEmpty {
                Text(verbatim: note.text)
                    .font(hand.font(note.hand ?? .notes, size: 9.5 * k))
                    .foregroundStyle(Color(red: 0.22, green: 0.22, blue: 0.28))
                    .lineSpacing(1.5 * k)
                    .padding(.horizontal, 3 * k).padding(.top, 2 * k)
                    .frame(width: area.width * k, height: area.height * k, alignment: .topLeading)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: area.width * k, height: area.height * k)
        .offset(x: area.midX * k, y: area.midY * k)
        .onAppear { if let note, !note.text.isEmpty { hand.ensure(note.hand ?? .notes) } }
    }
    #if os(iOS)
    @MainActor private static var drawn: [UUID: (Int, UIImage)] = [:]
    @MainActor static func strokes(_ note: PencilNote, id: UUID, revision: Int) -> UIImage? {
        guard !note.drawing.isEmpty else { return nil }
        if let hit = drawn[id], hit.0 == revision { return hit.1 }
        guard let drawing = try? PKDrawing(data: note.drawing) else { return nil }
        let image = drawing.image(from: CGRect(x: 0, y: 0, width: note.width, height: note.height), scale: 3)
        drawn[id] = (revision, image)
        return image
    }
    #endif
}
