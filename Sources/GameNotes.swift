import SwiftUI
import Combine
import ImageIO
#if os(iOS)
import PencilKit
import UIKit
#endif

// 游戏笔记 (round 32): one of the small icons along the top of the menu.
// A thick pad of sticky
// notes on the lower screen, each a sheet of old paper glued along its top
// edge; the sheet up is written on with the finger or an Apple Pencil
// (PencilKit); two fingers pushed up fold it over the glue strip (a real
// flip, the sheet turning in perspective), pulled down they bring a
// folded sheet back. The pad is used as a real one is —
// the written sheets in the order they were written, the blank rest of the
// pad under the last of them; turning the last written sheet over opens a
// new page, and there is no 新的一张. A sheet is kept as soon as it is left
// (a blank one is not kept); 保存 keeps a copy of it as a picture in the
// notes' own folder (not the album). The suspended software's screen
// can be laid under the strokes. Everything drawn is FoldArc's own.
// 新的一张 back as it was (and A); no counts along the top; a sheet
// torn off takes its saved copies with it; twelve inks in a small menu off
// the tool row; a trackpad's two fingers turn the page too; and the sheets
// turned over lie above the glue, their backs showing — a strip of the last
// one, what is written on it showing through faintly, upside down, as
// paper held to the light does; the first page has nothing above it.
// The black, red and
// third pen and the eraser along the tool row's left again, the third pen
// the twelve inks' menu (blue until another is picked); a saved copy is torn
// off (撕掉), not deleted.
// A sheet can
// have a photo of the album on the upper screen while it is written on —
// chosen with a small print taped to the pad's top left (照片), kept with
// the sheet and its saved copies (a copy's picture is the two screens, the
// photo above the sheet).

/// One sheet of the pad as kept on disk (`notes/sheet-<id>.json`, its
/// screen picture `sheet-<id>-top|bottom.png` beside it).
struct StickySheet: Codable, Equatable, Identifiable {
    var id: String
    var created: Date
    var saved: Date
    /// Which paper of the pad (StickyPaper.all), and the sheet's small tilt
    /// on the pad (degrees).
    var paper: Int
    var tilt: Double
    /// The strokes (PencilKit's own data) and how many; the sheet's size in
    /// points when they were drawn (scaled to the screen shown on).
    var drawing: Data
    var strokes: Int
    var width: Double
    var height: Double
    /// The suspended software's screen laid under the strokes, if one was.
    var background: String?
    /// What was running when the sheet was made.
    var software: String?
    /// 11-07: the album's name of the
    /// photo shown on the upper screen while this sheet is up; the sheet
    /// keeps its own copy of it (`sheet-<id>-photo.jpeg`). Files written
    /// before have none.
    var photo: String? = nil
    /// 铁皮盒's squared exercise paper (StickyPaper.squaredSheet) rather
    /// than the pad's own stock. Files written before have none.
    var grid: Bool? = nil

    var isBlank: Bool { strokes == 0 && background == nil && photo == nil }
    /// A new sheet; every fourth one is squared paper once 铁皮盒 has it.
    @MainActor static func fresh(paper: Int, software: String?) -> StickySheet {
        let squared = TinBoxStore.shared.has(.gridPaper) && paper % 4 == 3
        return StickySheet(id: UUID().uuidString, created: Date(), saved: Date(), paper: paper,
                           tilt: Double.random(in: -1.6...1.6), drawing: Data(), strokes: 0, width: 320, height: 212,
                           background: nil, software: software, grid: squared ? true : nil)
    }
}

/// The pad's order on disk (`notes/pad.json`): the sheets from the pad's
/// first page on, and the one that was up when the pad was left (a
/// real pad stays open where it was). Files written before (no
/// `firstPageFirst`) kept the newest sheet on top: they are read in the
/// order the sheets were made.
struct StickyPadIndex: Codable {
    var sheets: [String]
    var firstPageFirst: Bool?
    var current: String?
}

/// The pad's files.
enum StickyPadFiles {
    static var folder: URL { Storage.root.appendingPathComponent("notes", isDirectory: true) }
    static var index: URL { folder.appendingPathComponent("pad.json") }
    static func sheet(_ id: String) -> URL { folder.appendingPathComponent("sheet-\(id).json") }
    static func picture(_ id: String, side: String) -> URL { folder.appendingPathComponent("sheet-\(id)-\(side).png") }
    /// A sheet's photo (11-07): the album's JPEG copied as it is. `.jpeg`,
    /// so that a saved copy's photo (`<base>-photo.jpeg`) is never taken
    /// for one of the saved pictures (`.jpg`).
    static func photo(_ id: String) -> URL { folder.appendingPathComponent("sheet-\(id)-photo.jpeg") }
    /// 保存: the saved copies
    /// of sheets, pictures of their own in `notes/saved/` (`<stamp>-<id>.jpg`
    /// and a small `…-thumb.jpg`), for the pad's own gallery.
    static var saved: URL { folder.appendingPathComponent("saved", isDirectory: true) }
    static func savedPictures() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: saved, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jpg" && !$0.lastPathComponent.hasSuffix("-thumb.jpg") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    /// The pad from its first page on, and the sheet that was up (sheets
    /// the index names but that are not there are left out; sheets there
    /// but not in the index go in by when they were made).
    static func load() -> (sheets: [StickySheet], current: String?) {
        let stored = (try? Data(contentsOf: index)).flatMap { try? decoder.decode(StickyPadIndex.self, from: $0) }
        var sheets: [StickySheet] = []
        var seen = Set<String>()
        for id in stored?.sheets ?? [] {
            if let data = try? Data(contentsOf: sheet(id)), let s = try? decoder.decode(StickySheet.self, from: data) {
                sheets.append(s); seen.insert(s.id)
            }
        }
        var strays: [StickySheet] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix("sheet-") && url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let s = try? decoder.decode(StickySheet.self, from: data), !seen.contains(s.id) {
                strays.append(s); seen.insert(s.id)
            }
        }
        guard stored?.firstPageFirst == true else {
            // Earlier a new sheet went on top: the pad in the order the
            // sheets were made, opened at its fresh page.
            return ((sheets + strays).sorted { $0.created < $1.created }, nil)
        }
        return (sheets + strays.sorted { $0.created < $1.created }, stored?.current)
    }
    static func save(_ sheet: StickySheet) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(sheet).write(to: self.sheet(sheet.id), options: .atomic)
    }
    static func saveIndex(_ sheets: [StickySheet], current: String?) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(StickyPadIndex(sheets: sheets.map(\.id), firstPageFirst: true, current: current)).write(to: index, options: .atomic)
    }
    static func remove(_ sheet: StickySheet) {
        let fm = FileManager.default
        for url in [self.sheet(sheet.id), picture(sheet.id, side: "top"), picture(sheet.id, side: "bottom"), picture(sheet.id, side: "copy"), photo(sheet.id)] {
            try? fm.removeItem(at: url)
        }
    }
    /// The saved copies (存稿), the newest first. Each is `<stamp>-<the
    /// first 8 of its sheet's id>`: the picture `.jpg`, the small one
    /// `-thumb.jpg`, and (newer ones) the sheet as it was `.sheet.json` with
    /// its screen picture `-top.png` / `-bottom.png`, for 放回便签.
    static func drafts() -> [StickyDraft] {
        savedPictures().map { StickyDraft(base: $0.deletingPathExtension().lastPathComponent) }
    }
    /// A sheet's saved copies.
    static func drafts(of sheet: StickySheet) -> [StickyDraft] {
        let tag = "-\(sheet.id.prefix(8))"
        return drafts().filter { $0.base.hasSuffix(tag) }
    }
    /// A saved copy taken away: all its files.
    static func remove(_ draft: StickyDraft) {
        let files = (try? FileManager.default.contentsOfDirectory(at: saved, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix(draft.base) { try? FileManager.default.removeItem(at: url) }
    }
    /// The saved copies go with the
    /// sheet; how many there were.
    @discardableResult static func removeDrafts(of sheet: StickySheet) -> Int {
        let copies = drafts(of: sheet)
        copies.forEach(remove)
        return copies.count
    }
    static func encode(_ sheet: StickySheet) throws -> Data { try encoder.encode(sheet) }
    static func decode(_ data: Data) throws -> StickySheet { try decoder.decode(StickySheet.self, from: data) }
}

/// One saved copy (存稿): its files in `notes/saved/`, by their common name.
struct StickyDraft: Identifiable, Equatable {
    var base: String
    var id: String { base }
    var picture: URL { StickyPadFiles.saved.appendingPathComponent("\(base).jpg") }
    var thumb: URL { StickyPadFiles.saved.appendingPathComponent("\(base)-thumb.jpg") }
    var sheetFile: URL { StickyPadFiles.saved.appendingPathComponent("\(base).sheet.json") }
    func screen(_ side: String) -> URL { StickyPadFiles.saved.appendingPathComponent("\(base)-\(side).png") }
    /// The sheet's photo as it was (11-07), for 放回便签.
    var photo: URL { StickyPadFiles.saved.appendingPathComponent("\(base)-photo.jpeg") }
    /// When it was saved (its name's stamp).
    var saved: Date? { StickyDraft.stamp.date(from: String(base.prefix(15))) }
    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

/// The inks: twelve, an
/// old stationer's — dark enough to read on every paper of the pad (the
/// yellow is an ochre). The one in hand is kept for the next time.
enum GameNoteInk: String, CaseIterable, Identifiable {
    case black, gray, brown, red, orange, yellow, green, teal, blue, indigo, purple, pink
    static let storedKey = "foldarc.notes.ink"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .black: return String(localized: "黑")
        case .gray: return String(localized: "灰")
        case .brown: return String(localized: "棕")
        case .red: return String(localized: "红")
        case .orange: return String(localized: "橙")
        case .yellow: return String(localized: "黄")
        case .green: return String(localized: "绿")
        case .teal: return String(localized: "青")
        case .blue: return String(localized: "蓝")
        case .indigo: return String(localized: "靛")
        case .purple: return String(localized: "紫")
        case .pink: return String(localized: "粉")
        }
    }
    var color: Color {
        switch self {
        case .black: return Color(red: 0.16, green: 0.15, blue: 0.17)
        case .gray: return Color(red: 0.42, green: 0.42, blue: 0.44)
        case .brown: return Color(red: 0.48, green: 0.31, blue: 0.18)
        case .red: return Color(red: 0.72, green: 0.20, blue: 0.16)
        case .orange: return Color(red: 0.85, green: 0.47, blue: 0.17)
        case .yellow: return Color(red: 0.77, green: 0.60, blue: 0.17)
        case .green: return Color(red: 0.31, green: 0.54, blue: 0.24)
        case .teal: return Color(red: 0.18, green: 0.54, blue: 0.52)
        case .blue: return Color(red: 0.16, green: 0.30, blue: 0.56)
        case .indigo: return Color(red: 0.23, green: 0.23, blue: 0.55)
        case .purple: return Color(red: 0.48, green: 0.25, blue: 0.56)
        case .pink: return Color(red: 0.79, green: 0.36, blue: 0.52)
        }
    }
    static var stored: GameNoteInk {
        UserDefaults.standard.string(forKey: storedKey).flatMap(GameNoteInk.init(rawValue:)) ?? .black
    }
}

/// What is in hand: a pen of one ink, or the eraser.
enum GameNoteTool: Equatable {
    case pen(GameNoteInk)
    case eraser
    /// 铁皮盒's red flower: a tap on the sheet stamps one.
    case flower
    var title: String {
        switch self {
        case .pen(let ink): return String(localized: "\(ink.title)笔")
        case .eraser: return String(localized: "橡皮")
        case .flower: return String(localized: "小红花印章")
        }
    }
    var color: Color {
        switch self {
        case .pen(let ink): return ink.color
        case .eraser: return Color(red: 0.90, green: 0.78, blue: 0.66)
        case .flower: return Color(red: 0.85, green: 0.13, blue: 0.16)
        }
    }
    #if os(iOS)
    var uiColor: UIColor { UIColor(color) }
    #endif
}

/// The four circles at the tool row's left: the black and
/// the red pen as before, the third pen's ink picked in the inks' menu (blue
/// until one is picked, so the row looks as it did), and the eraser.
enum GameNotePen: String, CaseIterable, Identifiable {
    /// (`flower`: 铁皮盒's red flower stamp, among them once the tin has it.)
    case black, red, more, eraser, flower
    /// The circles the tool row shows.
    @MainActor static var offered: [GameNotePen] {
        allCases.filter { $0 != .flower || TinBoxStore.shared.has(.redFlower) }
    }
    static let storedKey = "foldarc.notes.pen"
    static let moreKey = "foldarc.notes.moreInk"
    var id: String { rawValue }
    /// The pen in hand last time; b25 kept only an ink (`foldarc.notes.ink`):
    /// black and red are their own pens, any other ink was the menu's.
    static var stored: (pen: GameNotePen, more: GameNoteInk) {
        let defaults = UserDefaults.standard
        var more = defaults.string(forKey: moreKey).flatMap(GameNoteInk.init(rawValue:)) ?? .blue
        if let pen = defaults.string(forKey: storedKey).flatMap(GameNotePen.init(rawValue:)) { return (pen, more) }
        switch defaults.string(forKey: GameNoteInk.storedKey).flatMap(GameNoteInk.init(rawValue:)) {
        case .red?: return (.red, more)
        case let ink? where ink != .black: more = ink; return (.more, more)
        default: return (.black, more)
        }
    }
}

/// The pad's papers: old sticky-note stock — an aged yellow, manila, a
/// faded sage, a faded rose, a dusty blue — and their glue strips.
struct StickyPaper {
    var face: Color
    var strip: Color
    var back: Color
    /// Squared (铁皮盒's exercise paper) rather than ruled.
    var squared = false
    /// 铁皮盒's squared exercise paper: off-white, its squares green.
    static let squaredSheet = StickyPaper(face: Color(red: 0.97, green: 0.97, blue: 0.93), strip: Color(red: 0.70, green: 0.82, blue: 0.72),
                                          back: Color(red: 0.94, green: 0.95, blue: 0.91), squared: true)
    /// A sheet's paper.
    static func of(_ sheet: StickySheet) -> StickyPaper { sheet.grid == true ? squaredSheet : at(sheet.paper) }
    static let square = Color(red: 0.36, green: 0.62, blue: 0.44)
    static let all: [StickyPaper] = [
        StickyPaper(face: Color(red: 0.93, green: 0.86, blue: 0.62), strip: Color(red: 0.85, green: 0.76, blue: 0.50), back: Color(red: 0.95, green: 0.90, blue: 0.72)),
        StickyPaper(face: Color(red: 0.87, green: 0.80, blue: 0.64), strip: Color(red: 0.78, green: 0.70, blue: 0.53), back: Color(red: 0.91, green: 0.86, blue: 0.73)),
        StickyPaper(face: Color(red: 0.79, green: 0.85, blue: 0.70), strip: Color(red: 0.68, green: 0.76, blue: 0.58), back: Color(red: 0.86, green: 0.90, blue: 0.79)),
        StickyPaper(face: Color(red: 0.90, green: 0.77, blue: 0.70), strip: Color(red: 0.81, green: 0.65, blue: 0.58), back: Color(red: 0.93, green: 0.85, blue: 0.80)),
        StickyPaper(face: Color(red: 0.75, green: 0.80, blue: 0.84), strip: Color(red: 0.64, green: 0.70, blue: 0.76), back: Color(red: 0.84, green: 0.87, blue: 0.90)),
    ]
    static func at(_ index: Int) -> StickyPaper { all[((index % all.count) + all.count) % all.count] }
    static let rule = Color(red: 0.45, green: 0.38, blue: 0.28)
}

/// The program: the pad, which sheet is up, the tool in hand.
@MainActor final class GameNotesModel: ObservableObject {
    /// The sheets from the pad's first page on: the written ones in the
    /// order they were written, then the pad's fresh page (kept in memory
    /// only while it is blank). `index` is the one up now; the ones before
    /// it are folded up over the glue strip.
    @Published private(set) var sheets: [StickySheet] = []
    @Published private(set) var index = 0
    /// Which of the four circles is in hand (11-06: black, red, the menu's
    /// pen, the eraser).
    @Published private(set) var pen = GameNotePen.stored.pen
    /// The third pen's ink, picked in the inks' menu.
    @Published private(set) var moreInk = GameNotePen.stored.more
    /// The pen before the eraser was taken (the D-pad's up / down goes back).
    private var lastPen = GameNotePen.black
    /// What the hand draws with.
    var tool: GameNoteTool {
        switch pen {
        case .black: return .pen(.black)
        case .red: return .pen(.red)
        case .more: return .pen(moreInk)
        case .eraser: return .eraser
        case .flower: return .flower
        }
    }
    /// The inks' small menu, up over the tool row from the third pen.
    @Published private(set) var paletteOpen = false
    /// The sheet up, as it is being written: its strokes (PencilKit's data;
    /// never empty, so the count says), the screen laid under them.
    @Published var drawing = Data()
    @Published private(set) var strokes = 0
    @Published private(set) var background: CGImage?
    @Published private(set) var backgroundSide: String?
    @Published private(set) var confirmingTear = false
    @Published private(set) var message: String?
    /// What the canvas is asked to do (undo, clear), counted so each
    /// request is seen once.
    @Published private(set) var undoRequests = 0
    @Published private(set) var clearRequests = 0
    /// A flip asked by a key (L / R) or 新的一张: the pad view animates it,
    /// then calls `flip(forward:)` (or `turnToNewPage()`).
    @Published private(set) var flipRequests = 0
    private(set) var flipRequested: Bool?
    private(set) var flipToNewPage = false
    func requestFlip(forward: Bool, toNewPage: Bool = false) {
        guard !confirmingTear else { return }
        closePalette()
        flipRequested = forward
        flipToNewPage = forward && toNewPage
        flipRequests += 1
    }
    /// The suspended software's screens, if any: what a sheet can take
    /// under its strokes (PlayView gives them; the library has none).
    var screens: () -> (top: CGImage, bottom: CGImage)? = { nil }
    var hasScreens = false
    var softwareTitle: String?
    var leave: () -> Void = {}
    /// The sheet's size as last drawn (the canvas tells it), for the file.
    var canvasSize = CGSize(width: 320, height: 212)
    private var opened = false
    private var messageTask: Task<Void, Never>?

    var current: StickySheet? { sheets.indices.contains(index) ? sheets[index] : nil }
    var count: Int { sheets.count }
    /// How many sheets have something on them (the one up as it is now).
    var written: Int {
        sheets.indices.reduce(0) { n, i in n + ((i == index ? isBlank : sheets[i].isBlank) ? 0 : 1) }
    }
    /// The sheets folded up over the top, and the ones still under this one
    /// that are kept (under the last of them, the blank rest of the pad).
    var above: Int { index }
    var below: Int { max(0, sheets.count - index - 1) }
    var isBlank: Bool { strokes == 0 && background == nil && photo == nil }

    func openProgram() {
        guard !opened else { return }
        opened = true
        // (The flower stamp in hand last time, and the tin without it now: the black pen.)
        if !GameNotePen.offered.contains(pen) { pen = .black }
        let pad = StickyPadFiles.load()
        sheets = pad.sheets
        addFreshPage()
        // Open where it was left (as a real pad is), else at its fresh page.
        index = pad.current.flatMap { id in sheets.firstIndex { $0.id == id } } ?? sheets.count - 1
        take(sheets[index])
        refreshDrafts()
        NSLog("[notes] open: %d sheets, sheet %d up", sheets.count, index + 1)
    }
    /// The pad's fresh page under the last written sheet (a pad is never
    /// used up). A blank last sheet is that page already.
    private func addFreshPage() {
        if let last = sheets.last, last.isBlank { return }
        sheets.append(.fresh(paper: (sheets.last?.paper ?? -1) + 1, software: softwareTitle))
    }
    /// The pad's order and the sheet up, on disk (a pad with nothing
    /// written on leaves no file behind).
    private func keepPad() {
        if sheets.allSatisfy(\.isBlank) && !sheets.contains(where: { FileManager.default.fileExists(atPath: StickyPadFiles.sheet($0.id).path) }) {
            try? FileManager.default.removeItem(at: StickyPadFiles.index)
        } else {
            try? StickyPadFiles.saveIndex(sheets, current: current?.id)
        }
    }
    func closeProgram() {
        guard opened else { return }
        commit()
        opened = false
        confirmingTear = false
        paletteOpen = false
        galleryOpen = false
        confirmingDraftDelete = false
        draftPicture = nil
        draftThumbs = [:]
        closePhotoPicker(sound: false)
        NSLog("[notes] closed (%d sheets)", sheets.count)
    }
    /// The sheet at `index` into the working state.
    private func take(_ sheet: StickySheet) {
        drawing = sheet.drawing
        strokes = sheet.strokes
        backgroundSide = sheet.background
        background = sheet.background.flatMap { CameraRoll.image(at: StickyPadFiles.picture(sheet.id, side: $0), maxPixel: 1024) }
        canvasSize = CGSize(width: sheet.width, height: sheet.height)
        pendingPhoto = nil
        photoName = sheet.photo
        photo = sheet.photo == nil ? nil : CameraRoll.image(at: StickyPadFiles.photo(sheet.id), maxPixel: 1024)
    }
    /// The working state back into the sheet and onto disk (a sheet still
    /// blank is kept in memory only).
    @discardableResult func commit() -> Bool {
        guard var sheet = current else { return false }
        let wasBlank = sheet.isBlank
        sheet.drawing = drawing
        sheet.strokes = strokes
        sheet.width = canvasSize.width
        sheet.height = canvasSize.height
        sheet.background = background == nil ? nil : backgroundSide
        sheet.photo = photo == nil ? nil : photoName
        if sheet.software == nil { sheet.software = softwareTitle }
        if sheet.isBlank && wasBlank { sheets[index] = sheet; return false }
        sheet.saved = Date()
        sheets[index] = sheet
        do {
            try FileManager.default.createDirectory(at: StickyPadFiles.folder, withIntermediateDirectories: true)
            // 11-07: the photo on the upper screen — the album's picture
            // just chosen copied in; none, the copy goes.
            let photoFile = StickyPadFiles.photo(sheet.id)
            if photo == nil {
                try? FileManager.default.removeItem(at: photoFile)
            } else if let chosen = pendingPhoto {
                try? FileManager.default.removeItem(at: photoFile)
                try FileManager.default.copyItem(at: chosen, to: photoFile)
                pendingPhoto = nil
            }
            if let background, let side = backgroundSide {
                try Self.writePNG(background, to: StickyPadFiles.picture(sheet.id, side: side))
                for other in ["top", "bottom"] where other != side { try? FileManager.default.removeItem(at: StickyPadFiles.picture(sheet.id, side: other)) }
            } else {
                for side in ["top", "bottom"] { try? FileManager.default.removeItem(at: StickyPadFiles.picture(sheet.id, side: side)) }
            }
            try StickyPadFiles.save(sheet)
            try StickyPadFiles.saveIndex(sheets, current: sheet.id)
            NSLog("[notes] sheet %@ kept (%d strokes, background %@, photo %@)", String(sheet.id.prefix(8)), strokes, backgroundSide ?? "none", sheet.photo ?? "none")
            return true
        } catch {
            say(String(localized: "没能保存这一张：\(error.localizedDescription)"))
            return false
        }
    }

    // MARK: The pad

    /// The sheet up folded over the glue strip (the one under it is up
    /// now), or a folded sheet pulled down again. Turning the last
    /// written sheet over opens a new page — the pad's blank rest is under
    /// it, as on a real pad; a blank page turned over leaves another blank
    /// one (a page with nothing on it is not kept).
    func flip(forward: Bool) {
        guard !confirmingTear else { return }
        if !forward, index == 0 { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        commit()
        if !forward {
            index -= 1
        } else if index + 1 < sheets.count {
            index += 1
        } else if let turned = current, turned.isBlank {
            StickyPadFiles.remove(turned)
            sheets[index] = .fresh(paper: turned.paper + 1, software: softwareTitle)
        } else {
            addFreshPage()
            index += 1
        }
        take(sheets[index])
        keepPad()
        ConsoleSounds.shared.play(.move)
        ConsoleHaptics.shared.play(.smallButton, .press)
        NSLog("[notes] sheet %d of %d up (%d written)", index + 1, sheets.count, written)
    }
    /// 新的一张 (and A): the
    /// pad's new page up, the sheet up turned over with an animation (every
    /// sheet after it goes over too). The new page up already: nothing.
    func newSheet() {
        guard !confirmingTear else { return }
        closePalette()
        if index == sheets.count - 1, isBlank {
            say(String(localized: "这一张还是空的"))
            ConsoleHaptics.shared.play(.sliderStop, .press)
            return
        }
        requestFlip(forward: true, toNewPage: true)
    }
    /// The turn of 新的一张, once its animation is over.
    func turnToNewPage() {
        guard !confirmingTear else { return }
        commit()
        addFreshPage()
        index = sheets.count - 1
        take(sheets[index])
        keepPad()
        ConsoleSounds.shared.play(.select)
        ConsoleHaptics.shared.play(.smallButton, .press)
        NSLog("[notes] 新的一张: sheet %d of %d up (%d written)", index + 1, sheets.count, written)
    }
    func askTear() {
        guard current != nil else { return }
        closePalette()
        ConsoleSounds.shared.play(.select)
        confirmingTear = true
    }
    /// Whether the sheet up has saved copies (撕掉 says they go too).
    var currentHasSavedCopies: Bool { current.map { !StickyPadFiles.drafts(of: $0).isEmpty } ?? false }
    func cancelTear() {
        guard confirmingTear else { return }
        confirmingTear = false
        ConsoleSounds.shared.play(.back)
    }
    /// The sheet torn off the pad (撕掉) and thrown away: the one under it
    /// is up (the next written one, or the pad's fresh page).
    func tearChosen() {
        confirmingTear = false
        guard let sheet = current else { return }
        StickyPadFiles.remove(sheet)
        // Its saved copies go with it.
        let copies = StickyPadFiles.removeDrafts(of: sheet)
        if copies > 0 { refreshDrafts() }
        sheets.remove(at: index)
        if !(sheets.last?.isBlank ?? false) {
            sheets.append(.fresh(paper: max(sheet.paper, sheets.last?.paper ?? sheet.paper) + 1, software: softwareTitle))
        }
        index = min(index, sheets.count - 1)
        take(sheets[index])
        keepPad()
        ConsoleSounds.shared.play(.back)
        ConsoleHaptics.shared.play(.lidShut, .press)
        say(copies > 0 ? String(localized: "撕掉了一张，存稿里的那份也撕掉了") : String(localized: "撕掉了一张"))
        NSLog("[notes] sheet torn off (%d left; %d saved cop%@ with it)", sheets.count, copies, copies == 1 ? "y" : "ies")
    }

    // MARK: The sheet

    /// One of the four circles in hand. The third one is the inks' menu
    /// (11-06): a touch on it takes that pen and opens the menu (or puts the
    /// menu away again).
    func pick(_ next: GameNotePen) {
        if next == .more {
            let opening = !paletteOpen
            take(.more, sound: false)
            paletteOpen = opening
            ConsoleSounds.shared.play(opening ? .select : .back)
            return
        }
        closePalette()
        take(next)
    }
    private func take(_ next: GameNotePen, sound: Bool = true) {
        guard next != pen else { return }
        if pen != .eraser { lastPen = pen }
        pen = next
        UserDefaults.standard.set(next.rawValue, forKey: GameNotePen.storedKey)
        if sound { ConsoleSounds.shared.play(.click) }
        NSLog("[notes] pen: %@%@", next.rawValue, next == .more ? " (\(moreInk.rawValue))" : "")
    }
    /// An ink chosen in the menu: the third pen takes it and is in hand.
    func choose(_ next: GameNoteInk, closing: Bool = true) {
        if closing { paletteOpen = false }
        let changed = next != moreInk || pen != .more
        moreInk = next
        UserDefaults.standard.set(next.rawValue, forKey: GameNotePen.moreKey)
        take(.more, sound: false)
        guard changed else { return }
        ConsoleSounds.shared.play(.click)
        NSLog("[notes] ink: %@", next.rawValue)
    }
    func togglePalette() { pick(.more) }
    func closePalette() {
        guard paletteOpen else { return }
        paletteOpen = false
    }
    /// The eraser, or back to the pen before it.
    func toggleEraser() {
        closePalette()
        take(pen == .eraser ? lastPen : .eraser)
    }
    /// The D-pad's left / right: along the four circles, as before.
    func stepPen(_ delta: Int) {
        let all = GameNotePen.offered
        let at = all.firstIndex(of: pen) ?? 0
        closePalette()
        take(all[((at + delta) % all.count + all.count) % all.count])
    }
    /// In the menu: the ink `delta` along the twelve (a row of six is ±6).
    func stepInk(_ delta: Int, closing: Bool = false) {
        let all = GameNoteInk.allCases
        let at = all.firstIndex(of: moreInk) ?? 0
        choose(all[((at + delta) % all.count + all.count) % all.count], closing: closing)
    }
    func undo() { undoRequests += 1; ConsoleSounds.shared.play(.click) }
    func clear() { drawing = Data(); strokes = 0; clearRequests += 1; ConsoleSounds.shared.play(.back) }
    /// The canvas says what the hand drew.
    func drew(_ data: Data, strokes count: Int, size: CGSize) {
        drawing = data
        strokes = count
        if size.width > 1 { canvasSize = size }
    }
    /// A red flower stamped (its strokes come to `drew` as the hand's do).
    func stamped() {
        ConsoleSounds.shared.play(.click)
        NSLog("[notes] a red flower stamped")
    }
    static func strokeCount(_ data: Data) -> Int {
        #if os(iOS)
        return (try? PKDrawing(data: data))?.strokes.count ?? 0
        #else
        return data.isEmpty ? 0 : 1
        #endif
    }
    /// The suspended software's screen under the strokes: the upper, the
    /// lower, or none.
    func takeScreen(_ side: String?) {
        guard let side else {
            background = nil; backgroundSide = nil
            ConsoleSounds.shared.play(.back)
            return
        }
        guard let screens = screens() else { say(String(localized: "没有在运行的软件，没有画面可以截")); return }
        background = side == "top" ? screens.top : screens.bottom
        backgroundSide = side
        ConsoleSounds.shared.play(.shutter, atLeast: 0.2)
        say(side == "top" ? String(localized: "上屏的画面放到了这一张下面") : String(localized: "下屏的画面放到了这一张下面"))
        NSLog("[notes] sheet %d took the %@ screen", index + 1, side)
    }
    /// SELECT / 截屏: the upper screen, then the lower, then none.
    func cycleScreen() {
        guard hasScreens else { say(String(localized: "没有在运行的软件，没有画面可以截")); return }
        switch backgroundSide {
        case nil: takeScreen("top")
        case "top"?: takeScreen("bottom")
        default: takeScreen(nil)
        }
    }

    // MARK: 照片

    /// The photo on the upper screen while the sheet up is written on the
    /// lower one: a picture of the album (the camera's, on the SD card),
    /// chosen with the small photo stuck on the pad's top left. The sheet
    /// keeps a copy of its own, so the album's picture can be edited or
    /// thrown away; `photoName` is the album's name for it.
    @Published private(set) var photo: CGImage?
    @Published private(set) var photoName: String?
    /// The album's picture just chosen, copied into the sheet by `commit()`.
    private var pendingPhoto: URL?
    /// 选照片: the album's pictures (no videos) four by two a page on the
    /// lower screen, the newest first; the one chosen at size on the upper.
    @Published private(set) var photoPickerOpen = false
    @Published private(set) var albumPhotos: [CameraPhoto] = []
    @Published private(set) var albumIndex = 0
    @Published private(set) var albumThumbs: [URL: CGImage] = [:]
    @Published private(set) var albumPicture: CGImage?
    static let photosPerPage = 8
    var selectedAlbumPhoto: CameraPhoto? { albumPhotos.indices.contains(albumIndex) ? albumPhotos[albumIndex] : nil }
    var albumPage: Int { albumIndex / Self.photosPerPage }
    var albumPages: Int { max(1, (albumPhotos.count + Self.photosPerPage - 1) / Self.photosPerPage) }

    func openPhotoPicker() {
        guard current != nil, !confirmingTear, !galleryOpen, !photoPickerOpen else { return }
        closePalette()
        albumPhotos = CameraRoll.list().filter { !$0.isVideo }
        // The sheet's own photo chosen while it is still in the album.
        albumIndex = photoName.flatMap { name in albumPhotos.firstIndex { $0.name == name } } ?? 0
        albumThumbs = [:]
        photoPickerOpen = true
        loadAlbumPage()
        ConsoleSounds.shared.play(.select)
        NSLog("[notes] 照片 open (%d pictures in the album)", albumPhotos.count)
    }
    func closePhotoPicker(sound: Bool = true) {
        guard photoPickerOpen else { return }
        photoPickerOpen = false
        albumPhotos = []
        albumThumbs = [:]
        albumPicture = nil
        if sound { ConsoleSounds.shared.play(.back) }
    }
    func selectAlbumPhoto(_ index: Int) {
        guard albumPhotos.indices.contains(index), index != albumIndex else { return }
        albumIndex = index
        loadAlbumPage()
        ConsoleSounds.shared.play(.move)
    }
    func moveAlbumPhoto(_ delta: Int) {
        guard !albumPhotos.isEmpty else { return }
        let next = min(max(0, albumIndex + delta), albumPhotos.count - 1)
        if next == albumIndex { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        selectAlbumPhoto(next)
    }
    /// The page's small pictures and the one chosen at size.
    private func loadAlbumPage() {
        let first = albumPage * Self.photosPerPage
        var thumbs: [URL: CGImage] = [:]
        for picture in albumPhotos.dropFirst(first).prefix(Self.photosPerPage) {
            thumbs[picture.url] = albumThumbs[picture.url] ?? CameraRoll.image(at: picture.url, maxPixel: 240)
        }
        albumThumbs = thumbs
        albumPicture = selectedAlbumPhoto.flatMap { CameraRoll.image(at: $0.url, maxPixel: 1024) }
    }
    /// 放到上屏 (A): the picture chosen goes with the sheet up, kept at once.
    func putPhotoUp() {
        guard let chosen = selectedAlbumPhoto else { return }
        guard let image = albumPicture ?? CameraRoll.image(at: chosen.url, maxPixel: 1024) else { say(String(localized: "这张照片打不开")); return }
        photo = image
        photoName = chosen.name
        pendingPhoto = chosen.url
        closePhotoPicker(sound: false)
        guard commit() else { return }
        ConsoleSounds.shared.play(.select)
        say(String(localized: "照片放到上屏了，在下屏写字"))
        NSLog("[notes] sheet %d: %@ on the upper screen", index + 1, chosen.name)
    }
    /// 不要照片 (X in 选照片): the sheet up without its photo.
    func removePhoto() {
        guard photo != nil else { return }
        photo = nil
        photoName = nil
        pendingPhoto = nil
        closePhotoPicker(sound: false)
        commit()
        ConsoleSounds.shared.play(.back)
        say(String(localized: "拿掉了上屏的照片"))
        NSLog("[notes] sheet %d: photo taken away", index + 1)
    }
    /// 保存: a copy of this sheet as a picture of its own in the notes'
    /// `saved/` folder (and a small one for the gallery to come), the sheet
    /// itself staying on the pad. Nothing goes to the album.
    @Published private(set) var savedCount = StickyPadFiles.savedPictures().count
    /// The newest saved copies' small pictures (the paper clip holds two).
    @Published private(set) var clipThumbs: [CGImage] = []

    // MARK: 存稿 (the sketch, its light backdrop; the way in: C,
    // a paper clip on the pad)

    @Published private(set) var galleryOpen = false
    @Published private(set) var drafts: [StickyDraft] = []
    @Published private(set) var draftIndex = 0
    @Published private(set) var confirmingDraftDelete = false
    /// The small pictures of the drafts shown, by name.
    @Published private(set) var draftThumbs: [String: CGImage] = [:]
    var selectedDraft: StickyDraft? { drafts.indices.contains(draftIndex) ? drafts[draftIndex] : nil }
    /// Eight a page, four by two.
    static let draftsPerPage = 8
    var draftPage: Int { draftIndex / Self.draftsPerPage }
    var draftPages: Int { max(1, (drafts.count + Self.draftsPerPage - 1) / Self.draftsPerPage) }
    /// The selected draft's picture at size (the upper screen).
    @Published private(set) var draftPicture: CGImage?

    func refreshDrafts() {
        savedCount = StickyPadFiles.savedPictures().count
        clipThumbs = StickyPadFiles.drafts().prefix(2).compactMap { CameraRoll.image(at: $0.thumb, maxPixel: 240) }
        if galleryOpen {
            drafts = StickyPadFiles.drafts()
            draftIndex = min(draftIndex, max(0, drafts.count - 1))
            loadDraftPage()
        }
    }
    func openGallery() {
        guard !confirmingTear, !photoPickerOpen else { return }
        closePalette()
        commit()
        drafts = StickyPadFiles.drafts()
        draftIndex = 0
        galleryOpen = true
        loadDraftPage()
        ConsoleSounds.shared.play(.select)
        NSLog("[notes] 存稿 open (%d)", drafts.count)
    }
    func closeGallery() {
        guard galleryOpen else { return }
        galleryOpen = false
        confirmingDraftDelete = false
        draftPicture = nil
        draftThumbs = [:]
        ConsoleSounds.shared.play(.back)
    }
    func selectDraft(_ index: Int) {
        guard drafts.indices.contains(index), index != draftIndex else { return }
        draftIndex = index
        loadDraftPage()
        ConsoleSounds.shared.play(.move)
    }
    func moveDraft(_ delta: Int) {
        guard !drafts.isEmpty else { return }
        let next = min(max(0, draftIndex + delta), drafts.count - 1)
        if next == draftIndex { ConsoleHaptics.shared.play(.sliderStop, .press); return }
        selectDraft(next)
    }
    /// The page's small pictures and the selected one at size.
    private func loadDraftPage() {
        let first = draftPage * Self.draftsPerPage
        var thumbs: [String: CGImage] = [:]
        for draft in drafts.dropFirst(first).prefix(Self.draftsPerPage) {
            thumbs[draft.base] = draftThumbs[draft.base] ?? CameraRoll.image(at: draft.thumb, maxPixel: 320)
        }
        draftThumbs = thumbs
        draftPicture = selectedDraft.flatMap { CameraRoll.image(at: $0.picture, maxPixel: 1200) }
    }
    /// 放回便签: the copy as a sheet again, at the pad's new page (the blank
    /// one at its end, or after the last), and up.
    func putDraftBack() {
        guard let draft = selectedDraft else { return }
        commit()
        var sheet = StickySheet.fresh(paper: (sheets.last?.paper ?? -1) + 1, software: softwareTitle)
        if let data = try? Data(contentsOf: draft.sheetFile), let kept = try? StickyPadFiles.decode(data) {
            sheet.drawing = kept.drawing
            sheet.strokes = kept.strokes
            sheet.width = kept.width
            sheet.height = kept.height
            sheet.paper = kept.paper
            sheet.grid = kept.grid
            sheet.software = kept.software
            if let side = kept.background, FileManager.default.fileExists(atPath: draft.screen(side).path) {
                try? FileManager.default.createDirectory(at: StickyPadFiles.folder, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: draft.screen(side), to: StickyPadFiles.picture(sheet.id, side: side))
                sheet.background = side
            }
            // 11-07: its photo on the upper screen again.
            if let name = kept.photo, FileManager.default.fileExists(atPath: draft.photo.path) {
                try? FileManager.default.createDirectory(at: StickyPadFiles.folder, withIntermediateDirectories: true)
                if (try? FileManager.default.copyItem(at: draft.photo, to: StickyPadFiles.photo(sheet.id))) != nil { sheet.photo = name }
            }
        } else if let picture = CameraRoll.image(at: draft.picture, maxPixel: 1200) {
            // An older copy (no sheet kept with it): the picture itself
            // under the new sheet.
            try? FileManager.default.createDirectory(at: StickyPadFiles.folder, withIntermediateDirectories: true)
            if (try? Self.writePNG(picture, to: StickyPadFiles.picture(sheet.id, side: "copy"))) != nil { sheet.background = "copy" }
        }
        if sheet.isBlank { say(String(localized: "这份存稿打不开了")); return }
        if let last = sheets.last, last.isBlank { sheets[sheets.count - 1] = sheet } else { sheets.append(sheet) }
        index = sheets.count - 1
        do { try StickyPadFiles.save(sheet) } catch { say(String(localized: "没能放回：\(error.localizedDescription)")); return }
        take(sheet)
        keepPad()
        galleryOpen = false
        draftPicture = nil
        draftThumbs = [:]
        ConsoleSounds.shared.play(.select)
        say(String(localized: "放回便签了，是第 \(index + 1) 张"))
        NSLog("[notes] 存稿 %@ put back as sheet %d", draft.base, index + 1)
    }
    /// 11-07: 存到照片 — the chosen copy's picture (as 存稿 has it: with the photo
    /// over it when the sheet has one) into the iPhone's Photos, as the
    /// camera's pictures go (SystemPhotos: add only, the system asks the
    /// first time). 存稿 keeps it.
    @Published private(set) var savingDraftToPhotos = false
    func saveDraftToPhotos() {
        guard let draft = selectedDraft, !savingDraftToPhotos else { return }
        guard FileManager.default.fileExists(atPath: draft.picture.path) else { say(String(localized: "这份存稿的图片找不到了")); return }
        savingDraftToPhotos = true
        ConsoleSounds.shared.play(.select)
        Task { @MainActor [weak self] in
            let outcome = await SystemPhotos.add(draft.picture)
            guard let self else { return }
            self.savingDraftToPhotos = false
            switch outcome {
            case .added:
                ConsoleHaptics.shared.play(.smallButton, .press)
                self.say(String(localized: "已存到「照片」"))
            case .notAllowed:
                self.say(String(localized: "没有存：Zero EMU 不能往「照片」里添加（设置 › Zero EMU › 照片）"))
            case .failed(let reason):
                self.say(String(localized: "没能存到「照片」：\(reason)"))
            case .off:
                self.say(String(localized: "测试运行：没有存到「照片」"))
            }
            NSLog("[notes] 存稿 %@ to Photos: %@", draft.base, String(describing: outcome))
        }
    }
    func askDeleteDraft() {
        guard selectedDraft != nil else { return }
        ConsoleSounds.shared.play(.select)
        confirmingDraftDelete = true
    }
    func cancelDeleteDraft() {
        guard confirmingDraftDelete else { return }
        confirmingDraftDelete = false
        ConsoleSounds.shared.play(.back)
    }
    func deleteDraftChosen() {
        confirmingDraftDelete = false
        guard let draft = selectedDraft else { return }
        StickyPadFiles.remove(draft)
        refreshDrafts()
        ConsoleSounds.shared.play(.back)
        ConsoleHaptics.shared.play(.lidShut, .press)
        say(String(localized: "撕掉了这份存稿"))
        NSLog("[notes] 存稿 %@ torn off", draft.base)
    }

    func save() {
        guard current != nil else { return }
        if isBlank { say(String(localized: "这一张还是空的")); ConsoleHaptics.shared.play(.sliderStop, .press); return }
        commit()
        guard let sheet = current, let picture = savedPicture(of: sheet, scale: 3),
              let thumb = savedThumbnail(of: sheet),
              let jpeg = CameraRoll.jpeg(picture, side: .outer, lens: .normal, note: nil, date: Date()),
              let small = CameraRoll.jpeg(thumb, side: .outer, lens: .normal, note: nil, date: Date()) else { say(String(localized: "没能做成图片")); return }
        do {
            try FileManager.default.createDirectory(at: StickyPadFiles.saved, withIntermediateDirectories: true)
            let stamp = Self.stampFormatter.string(from: Date())
            let name = "\(stamp)-\(sheet.id.prefix(8))"
            let draft = StickyDraft(base: name)
            try jpeg.write(to: draft.picture, options: .atomic)
            try small.write(to: draft.thumb, options: .atomic)
            // The sheet itself too, for 放回便签 (its strokes, and the
            // screen under them).
            try StickyPadFiles.encode(sheet).write(to: draft.sheetFile, options: .atomic)
            if let side = sheet.background {
                try? FileManager.default.copyItem(at: StickyPadFiles.picture(sheet.id, side: side), to: draft.screen(side))
            }
            if sheet.photo != nil {
                try? FileManager.default.copyItem(at: StickyPadFiles.photo(sheet.id), to: draft.photo)
            }
            refreshDrafts()
            ConsoleSounds.shared.play(.shutter, atLeast: 0.2)
            say(String(localized: "已保存到笔记的存稿里"))
            NSLog("[notes] sheet %d saved into the notes as %@ (%d saved)", index + 1, name, savedCount)
        } catch {
            say(String(localized: "没能保存：\(error.localizedDescription)"))
        }
    }
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
    /// The sheet as one picture: its paper (or the screen under the
    /// strokes), then the strokes.
    func render(sheet: StickySheet, size: CGSize, scale: CGFloat) -> CGImage? {
        #if os(iOS)
        let drawing = (try? PKDrawing(data: sheet.drawing)) ?? PKDrawing()
        let sheetSize = CGSize(width: sheet.width, height: sheet.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let paper = StickyPaper.of(sheet)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(paper.face).setFill()
            context.fill(rect)
            if let side = sheet.background, let background = CameraRoll.image(at: StickyPadFiles.picture(sheet.id, side: side), maxPixel: 1024) {
                UIImage(cgImage: background).draw(in: Self.fit(CGSize(width: background.width, height: background.height), in: rect), blendMode: .normal, alpha: 0.92)
            } else if paper.squared {
                StickyPaperArt.drawSquares(in: context.cgContext, rect: rect)
            } else {
                StickyPaperArt.drawLines(in: context.cgContext, rect: rect)
            }
            UIColor(paper.strip).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.07))
            let fitted = drawing.transformed(using: CGAffineTransform(scaleX: size.width / max(1, sheetSize.width), y: size.height / max(1, sheetSize.height)))
            // PencilKit adapts ink colours to the current interface style
            // (black ink comes out pale under a dark one): drawn as light.
            var strokes: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent { strokes = fitted.image(from: rect, scale: scale) }
            strokes?.draw(in: rect)
        }
        return image.cgImage
        #else
        return nil
        #endif
    }
    /// A saved copy's picture: the sheet; with a photo (11-07), the photo
    /// above it as the two screens are — the upper screen's 4:3 picture on
    /// black, a dark strip for the hinge, the sheet under it.
    func savedPicture(of sheet: StickySheet, scale: CGFloat) -> CGImage? {
        let sheetSize = CGSize(width: 320, height: 212)
        guard let page = render(sheet: sheet, size: sheetSize, scale: scale) else { return nil }
        #if os(iOS)
        guard sheet.photo != nil, let photo = CameraRoll.image(at: StickyPadFiles.photo(sheet.id), maxPixel: 1280) else { return page }
        let top = CGRect(x: 0, y: 0, width: sheetSize.width, height: 240)
        let gap: CGFloat = 8
        let size = CGSize(width: sheetSize.width, height: top.height + gap + sheetSize.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(FixedMenuStyle.status).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(top)
            UIImage(cgImage: photo).draw(in: Self.fit(CGSize(width: photo.width, height: photo.height), in: top))
            UIImage(cgImage: page, scale: scale, orientation: .up).draw(in: CGRect(x: 0, y: top.height + gap, width: sheetSize.width, height: sheetSize.height))
        }
        return image.cgImage
        #else
        return page
        #endif
    }
    /// A saved copy's small picture: the sheet, its photo (11-07) stuck on
    /// its top right as a small print.
    func savedThumbnail(of sheet: StickySheet) -> CGImage? {
        let size = CGSize(width: 160, height: 106)
        guard let page = render(sheet: sheet, size: size, scale: 2) else { return nil }
        #if os(iOS)
        guard sheet.photo != nil, let photo = CameraRoll.image(at: StickyPadFiles.photo(sheet.id), maxPixel: 240) else { return page }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: page, scale: 2, orientation: .up).draw(in: CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: size.width - 36, y: 30)
            cg.rotate(by: 5 * .pi / 180)
            let card = CGRect(x: -28, y: -22, width: 56, height: 44)
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            UIColor.white.setFill()
            cg.fill(card)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIImage(cgImage: photo).draw(in: Self.fit(CGSize(width: photo.width, height: photo.height), in: card.insetBy(dx: 3, dy: 3)))
            cg.restoreGState()
        }
        return image.cgImage
        #else
        return page
        #endif
    }
    static func fit(_ picture: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / max(1, picture.width), rect.height / max(1, picture.height))
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "FoldArc.notes", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "写不了图片")])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "FoldArc.notes", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "写不了图片")])
        }
    }

    // MARK: Keys

    /// The console's keys: L lifts the sheet up over (the next one up; past
    /// the last written one, a new page), R pulls a folded one down; A turns
    /// to the new page (新的一张); X tears the sheet off
    /// (asked); the D-pad's left / right change the ink, up / down take the
    /// eraser and give it back (with the inks' menu up, the D-pad moves in
    /// it, A or B puts it away); Y undoes; SELECT lays the suspended
    /// software's screen under the strokes (upper → lower → none); START
    /// saves a copy into the notes; B leaves.
    @discardableResult func handle(_ key: PadButton, down: Bool) -> Bool {
        guard down else { return true }
        if confirmingTear {
            switch key {
            case .a: tearChosen()
            case .b: cancelTear()
            default: break
            }
            return true
        }
        if confirmingDraftDelete {
            switch key {
            case .a: deleteDraftChosen()
            case .b: cancelDeleteDraft()
            default: break
            }
            return true
        }
        if galleryOpen {
            // 存稿: the D-pad moves among the copies (four a row), L / R a
            // page; A puts the one chosen back on the pad, Y puts it into
            // the iPhone's Photos (11-07: 存到照片), X deletes it (asked), B
            // goes back to the pad.
            switch key {
            case .left: moveDraft(-1)
            case .right: moveDraft(1)
            case .up: moveDraft(-4)
            case .down: moveDraft(4)
            case .l: moveDraft(-Self.draftsPerPage)
            case .r: moveDraft(Self.draftsPerPage)
            case .a: putDraftBack()
            case .y: saveDraftToPhotos()
            case .x: askDeleteDraft()
            case .b: closeGallery()
            default: break
            }
            return true
        }
        if photoPickerOpen {
            // 选照片 (11-07): the D-pad moves among the album's pictures
            // (four a row), L / R a page; A puts the one chosen on the upper
            // screen, X takes the sheet's photo away, B goes back to the pad.
            switch key {
            case .left: moveAlbumPhoto(-1)
            case .right: moveAlbumPhoto(1)
            case .up: moveAlbumPhoto(-4)
            case .down: moveAlbumPhoto(4)
            case .l: moveAlbumPhoto(-Self.photosPerPage)
            case .r: moveAlbumPhoto(Self.photosPerPage)
            case .a: putPhotoUp()
            case .x: removePhoto()
            case .b: closePhotoPicker()
            default: break
            }
            return true
        }
        if paletteOpen {
            switch key {
            case .left: stepInk(-1)
            case .right: stepInk(1)
            case .up: stepInk(-6)
            case .down: stepInk(6)
            case .a, .b: togglePalette()
            default: break
            }
            return true
        }
        switch key {
        case .l: requestFlip(forward: true)
        case .r: requestFlip(forward: false)
        case .a: newSheet()
        case .x: askTear()
        case .left: stepPen(-1)
        case .right: stepPen(1)
        case .up: pick(.more)
        case .down: toggleEraser()
        case .y: undo()
        case .select: cycleScreen()
        case .start: save()
        case .b: leave()
        default: break
        }
        return true
    }
    private func say(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.message = nil }
        }
    }
}

/// The paper's faint rules (drawn into a picture).
enum StickyPaperArt {
    static func drawLines(in context: CGContext, rect: CGRect) {
        #if os(iOS)
        context.setStrokeColor(UIColor(StickyPaper.rule).withAlphaComponent(0.28).cgColor)
        #else
        context.setStrokeColor(CGColor(red: 0.45, green: 0.38, blue: 0.28, alpha: 0.28))
        #endif
        context.setLineWidth(max(0.5, rect.height / 300))
        let step = rect.height / 8
        var y = rect.minY + step * 1.5
        while y < rect.maxY - 1 {
            context.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: y))
            context.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: y))
            y += step
        }
        context.strokePath()
    }
    /// 铁皮盒's squared paper: faint green squares.
    static func drawSquares(in context: CGContext, rect: CGRect) {
        #if os(iOS)
        context.setStrokeColor(UIColor(StickyPaper.square).withAlphaComponent(0.34).cgColor)
        #else
        context.setStrokeColor(CGColor(red: 0.36, green: 0.62, blue: 0.44, alpha: 0.34))
        #endif
        context.setLineWidth(max(0.5, rect.height / 320))
        let step = rect.height / 10
        var y = rect.minY + rect.height * 0.07 + step * 0.5
        while y < rect.maxY - 1 {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        var x = rect.minX + step * 0.5
        while x < rect.maxX - 1 {
            context.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.07))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        context.strokePath()
    }
}

// MARK: - The drawing view

#if os(iOS)
/// The sheet drawn on: PencilKit's canvas (the finger and an Apple Pencil
/// both draw; palm rejection is the Pencil's), with FoldArc's tools.
struct GameNoteCanvas: UIViewRepresentable {
    @ObservedObject var model: GameNotesModel
    /// The sheet's size in points (the strokes are scaled to it).
    var size: CGSize
    /// Which sheet the canvas holds (a change loads its strokes).
    var sheetID: String
    /// Two fingers on the sheet: how far they have moved, then let go.
    var twoFingers: (TwoFingers) -> Void = { _ in }
    enum TwoFingers { case moved(dy: CGFloat), ended(dy: CGFloat, velocity: CGFloat), cancelled }
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        // Two fingers together: a pan of their own, beside PencilKit's
        // drawing (one finger draws; the second cancels the stroke).
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.twoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        // A trackpad's two fingers (the
        // Simulator on a Mac, a keyboard's trackpad) scroll rather than
        // touch — the same turn, from the scroll alone (no touches).
        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.twoFingerPan(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []
        scroll.delegate = context.coordinator
        view.addGestureRecognizer(scroll)
        view.backgroundColor = .clear
        view.isOpaque = false
        // The paper is light wherever the program runs: the inks keep
        // their own colours.
        view.overrideUserInterfaceStyle = .light
        view.drawingPolicy = .anyInput
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.tool = context.coordinator.tool(for: model.tool)
        // 铁皮盒's flower stamp: a tap stamps (only while it is in hand).
        let stamp = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.stamp(_:)))
        stamp.isEnabled = false
        view.addGestureRecognizer(stamp)
        context.coordinator.stampTap = stamp
        if let drawing = try? PKDrawing(data: model.drawing) { view.drawing = drawing }
        // The delegate after the strokes are in: what it hears is the hand's.
        view.delegate = context.coordinator
        context.coordinator.view = view
        return view
    }
    func updateUIView(_ view: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.twoFingers = twoFingers
        view.tool = coordinator.tool(for: model.tool)
        let stamping = model.tool == .flower
        if coordinator.stamping != stamping {
            coordinator.stamping = stamping
            view.drawingGestureRecognizer.isEnabled = !stamping
            coordinator.stampTap?.isEnabled = stamping
        }
        // Another sheet up, or the paper resized: its strokes, scaled to
        // this canvas.
        let resized = abs(size.width - coordinator.loadedSize.width) > 0.5 || abs(size.height - coordinator.loadedSize.height) > 0.5
        if coordinator.loadedSheet != sheetID || resized {
            coordinator.loadedSheet = sheetID
            coordinator.loadedSize = size
            var drawing = (try? PKDrawing(data: model.drawing)) ?? PKDrawing()
            if size.width > 1, size.height > 1, model.canvasSize.width > 1, model.canvasSize.height > 1,
               abs(size.width - model.canvasSize.width) > 0.5 || abs(size.height - model.canvasSize.height) > 0.5 {
                drawing = drawing.transformed(using: CGAffineTransform(scaleX: size.width / model.canvasSize.width, y: size.height / model.canvasSize.height))
            }
            coordinator.settingDrawing = true
            view.drawing = drawing
            coordinator.settingDrawing = false
            view.undoManager?.removeAllActions()
            if size.width > 1 { model.canvasSize = size }
        }
        if coordinator.undoSeen != model.undoRequests {
            coordinator.undoSeen = model.undoRequests
            view.undoManager?.undo()
        }
        if coordinator.clearSeen != model.clearRequests {
            coordinator.clearSeen = model.clearRequests
            coordinator.settingDrawing = true
            view.drawing = PKDrawing()
            coordinator.settingDrawing = false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        let model: GameNotesModel
        weak var view: PKCanvasView?
        var loadedSheet = ""
        var loadedSize = CGSize.zero
        var undoSeen = 0
        var clearSeen = 0
        var settingDrawing = false
        var twoFingers: (TwoFingers) -> Void = { _ in }
        /// 铁皮盒's flower in hand: taps stamp, the hand does not draw.
        var stamping = false
        weak var stampTap: UITapGestureRecognizer?
        init(model: GameNotesModel) { self.model = model }
        /// A tap with the flower in hand: one red flower pressed onto the
        /// sheet, as strokes of ink (撤销 takes it off again).
        @objc func stamp(_ tap: UITapGestureRecognizer) {
            guard tap.state == .ended, let canvas = view else { return }
            let before = canvas.drawing
            var after = before
            after.strokes.append(contentsOf: StickyFlowerStamp.strokes(at: tap.location(in: canvas), size: 34))
            canvas.undoManager?.registerUndo(withTarget: canvas) { target in target.drawing = before }
            canvas.drawing = after
            MainActor.assumeIsolated { model.stamped() }
        }
        @objc func twoFingerPan(_ pan: UIPanGestureRecognizer) {
            let dy = pan.translation(in: pan.view).y
            if pan.state == .began, let canvas = view {
                // The first finger's stroke, begun a moment before the second
                // came, is not drawn (switching PencilKit's own recogniser
                // off and on cancels it).
                canvas.drawingGestureRecognizer.isEnabled = false
                canvas.drawingGestureRecognizer.isEnabled = !stamping
                NSLog("[notes] two fingers on the sheet (%@)", pan.numberOfTouches == 0 ? "trackpad" : "touch")
            }
            switch pan.state {
            case .began, .changed: twoFingers(.moved(dy: dy))
            case .ended: twoFingers(.ended(dy: dy, velocity: pan.velocity(in: pan.view).y))
            case .cancelled, .failed: twoFingers(.cancelled)
            default: break
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func tool(for tool: GameNoteTool) -> PKTool {
            switch tool {
            case .eraser: return PKEraserTool(.bitmap, width: 18)
            case .pen, .flower: return PKInkingTool(.pen, color: tool.uiColor, width: 3.2)
            }
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !settingDrawing else { return }
            let size = canvasView.bounds.size
            let drawing = canvasView.drawing
            Task { @MainActor in
                model.drew(drawing.dataRepresentation(), strokes: drawing.strokes.count, size: size)
            }
        }
    }
}

/// 铁皮盒's red flower stamp pressed onto a sheet: strokes of red ink, so
/// it is kept, drawn and undone as the sheet's writing is.
enum StickyFlowerStamp {
    static func strokes(at center: CGPoint, size: CGFloat) -> [PKStroke] {
        let red = UIColor(red: 0.85, green: 0.13, blue: 0.16, alpha: 1)
        let deep = UIColor(red: 0.66, green: 0.06, blue: 0.12, alpha: 1)
        let yellow = UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1)
        var made: [PKStroke] = []
        func dab(from a: CGPoint, to b: CGPoint, width: CGFloat, _ colour: UIColor) {
            var points: [PKStrokePoint] = []
            for i in 0...3 {
                let u = CGFloat(i) / 3
                let at = CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
                points.append(PKStrokePoint(location: at, timeOffset: TimeInterval(i) * 0.01, size: CGSize(width: width, height: width),
                                            opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
            }
            made.append(PKStroke(ink: PKInk(.pen, color: colour), path: PKStrokePath(controlPoints: points, creationDate: Date())))
        }
        func around(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * 2 * .pi
            dab(from: around(a, size * 0.12), to: around(a, size * 0.34), width: size * 0.26, red)
        }
        for k in 0..<6 {
            let a = (CGFloat(k) + 0.5) / 6 * 2 * .pi
            dab(from: around(a, size * 0.05), to: around(a, size * 0.16), width: size * 0.15, deep)
        }
        dab(from: around(.pi, size * 0.01), to: around(0, size * 0.01), width: size * 0.16, yellow)
        return made
    }
}
#else
/// The Mac preview has no PencilKit canvas: the sheet is shown, not drawn on.
struct GameNoteCanvas: View {
    @ObservedObject var model: GameNotesModel
    var size: CGSize
    var sheetID: String
    var twoFingers: (TwoFingers) -> Void = { _ in }
    enum TwoFingers { case moved(dy: CGFloat), ended(dy: CGFloat, velocity: CGFloat), cancelled }
    var body: some View { Color.clear }
}
#endif

// MARK: - The screens

/// The upper screen: the pad's facts, the screen laid under the sheet at
/// full size, what the program says along the bottom.
struct GameNotesTopScreen: View {
    @ObservedObject var model: GameNotesModel
    var body: some View {
        GeometryReader { proxy in
            let s = max(0.4, proxy.size.width / 400)
            ZStack {
                SystemMenuBackdrop(palette: .standard)
                if model.galleryOpen {
                    GameNotesDraftTop(model: model, s: s)
                } else if model.photoPickerOpen {
                    GameNotesPhotoPickTop(model: model, s: s)
                } else if let photo = model.photo {
                    // 11-07: the sheet's photo, as large as the upper screen
                    // takes it, while the lower screen is written on.
                    GameNotesPhotoTop(image: photo, name: model.photoName, s: s)
                } else if let background = model.background {
                    Image(decorative: background, scale: 1).resizable().interpolation(.none).scaledToFit()
                        .padding(6 * s)
                        .accessibilityHidden(true)
                    VStack {
                        HStack {
                            Text(model.backgroundSide == "top" ? "这一张下面是上屏的画面" : (model.backgroundSide == "copy" ? "这一张下面是存稿的样子" : "这一张下面是下屏的画面"))
                                .font(.system(size: 9 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .padding(.horizontal, 8 * s).padding(.vertical, 3 * s).background(Capsule().fill(FixedMenuStyle.bar.opacity(0.85)))
                            Spacer()
                        }
                        .padding(8 * s)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 7 * s) {
                        Image(systemName: "note.text").font(.system(size: 28 * s, weight: .semibold)).foregroundStyle(FixedMenuStyle.ink)
                        Text("游戏笔记").font(.system(size: 20 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                        Text(facts).font(.system(size: 10 * s, weight: .semibold, design: .rounded)).foregroundStyle(FixedMenuStyle.inkSoft)
                        Text((model.hasScreens
                              ? String(localized: "在下屏的便签上写字画画；两个手指往上推（触控板上两指往上滑也行），这一张翻过去，往下拉翻回来；「新的一张」（A）直接翻到新的一页。「截屏」（或 SELECT）把暂停的软件的画面放到这一张下面。")
                              : String(localized: "在下屏的便签上写字画画；两个手指往上推（触控板上两指往上滑也行），这一张翻过去，往下拉翻回来；「新的一张」（A）直接翻到新的一页。"))
                             + String(localized: "L / R 翻页，X 撕掉，十字键左右换笔、上开更多颜色、下拿橡皮，Y 撤销，START 保存进存稿。便签左上角的「照片」把相册里的一张照片放到上屏，对着它写。"))
                            .font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(FixedMenuStyle.inkSoft)
                            .multilineTextAlignment(.center).padding(.horizontal, 28 * s)
                        HStack(spacing: 6 * s) {
                            Circle().fill(model.tool.color).frame(width: 13 * s, height: 13 * s)
                                .overlay(Circle().strokeBorder(FixedMenuStyle.ink.opacity(0.35), lineWidth: 1 * s))
                            Text("现在：\(model.tool.title)").font(.system(size: 9.5 * s, weight: .bold, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("notes-title")
                }
                if let message = model.message {
                    VStack {
                        Spacer()
                        Text(message).font(.system(size: 10 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 10 * s).padding(.vertical, 5 * s)
                            .background(Capsule().fill(FixedMenuStyle.status.opacity(0.92)))
                            .padding(.bottom, 8 * s)
                            .accessibilityIdentifier("notes-message")
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notes-top")
        }
    }
    /// The sheet up (no counts).
    private var facts: String {
        guard let sheet = model.current else { return String(localized: "一叠便签") }
        guard !model.isBlank else { return String(localized: "第 \(model.index + 1) 张 · 空白") }
        let when = sheet.created.formatted(.dateTime.locale(UILanguage.locale).month().day().hour().minute(.twoDigits))
        return String(localized: "第 \(model.index + 1) 张 · \(when)") + (sheet.software.map { " · \($0)" } ?? "")
    }
}

/// The lower screen: the pad of sticky notes, the tools along the bottom;
/// or 存稿, the saved copies.
struct GameNotesBottomScreen: View {
    @ObservedObject var model: GameNotesModel
    var body: some View {
        GeometryReader { proxy in
            let s = max(0.4, proxy.size.width / 320)
            ZStack {
                // The system menu's light
                // backdrop and its dark title bar, the pad on it; no desk.
                // (存稿 on the same backdrop.)
                SystemMenuBackdrop(palette: .standard)
                VStack(spacing: 0) {
                    HStack(spacing: 6 * s) {
                        Image(systemName: model.galleryOpen ? "paperclip" : (model.photoPickerOpen ? "photo" : "pencil.and.outline")).font(.system(size: 10 * s, weight: .bold))
                        // The pad has no end (a new page under the last
                        // written one), so no count of pages: the page only.
                        Text(model.galleryOpen ? "游戏笔记 · 存稿" : (model.photoPickerOpen ? "游戏笔记 · 选照片" : "游戏笔记 · 第 \(model.index + 1) 张"))
                            .font(.system(size: 11 * s, weight: .heavy, design: .rounded))
                            .accessibilityIdentifier("notes-count")
                        Spacer(minLength: 0)
                        if model.galleryOpen, !model.drafts.isEmpty {
                            Text("A 放回便签 · Y 存到照片 · X 撕掉 · B 返回").font(.system(size: 8.5 * s, weight: .semibold, design: .rounded)).opacity(0.75)
                        } else if model.photoPickerOpen, !model.albumPhotos.isEmpty {
                            Text(model.photo == nil ? "A 放到上屏 · B 返回" : "A 放到上屏 · X 不要照片 · B 返回")
                                .font(.system(size: 8.5 * s, weight: .semibold, design: .rounded)).opacity(0.75)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10 * s)
                    .frame(height: 24 * s)
                    .background(FixedMenuStyle.status)
                    if model.galleryOpen {
                        StickyGallery(model: model, s: s)
                            .frame(maxHeight: .infinity)
                        StickyGalleryBar(model: model, s: s)
                    } else if model.photoPickerOpen {
                        StickyPhotoPicker(model: model, s: s)
                            .frame(maxHeight: .infinity)
                        StickyPhotoBar(model: model, s: s)
                    } else {
                        StickyPadView(model: model, s: s)
                            .frame(maxHeight: .infinity)
                        StickyToolRow(model: model, s: s)
                    }
                }
                if model.paletteOpen {
                    // A touch anywhere else puts the inks' menu away.
                    Color.black.opacity(0.001)
                        .onTapGesture { model.togglePalette() }
                        .accessibilityHidden(true)
                    StickyPalette(model: model, s: s)
                }
                if model.confirmingTear {
                    StickyTearDialog(model: model, s: s)
                }
                if model.confirmingDraftDelete {
                    StickyAskDialog(title: String(localized: "撕掉这份存稿？"), note: String(localized: "只撕掉存稿里的这一份，便签本上的那张还在。"), confirm: String(localized: "撕掉"), s: s,
                                    identifier: "notes-draft-tear", cancel: { model.cancelDeleteDraft() }, chosen: { model.deleteDraftChosen() })
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes-bottom")
    }
}

/// 存稿 on the upper screen: the copy chosen, at size, and when it was saved.
private struct GameNotesDraftTop: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        VStack(spacing: 6 * s) {
            if let picture = model.draftPicture {
                Image(decorative: picture, scale: 1).resizable().interpolation(.medium).scaledToFit()
                    .shadow(color: .black.opacity(0.3), radius: 8 * s, y: 4 * s)
                    .rotationEffect(.degrees(-0.8))
                    .padding(.horizontal, 34 * s).padding(.top, 14 * s)
                Text(caption).font(.system(size: 9 * s, weight: .bold, design: .rounded)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .padding(.bottom, 8 * s)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "paperclip").font(.system(size: 26 * s, weight: .semibold)).foregroundStyle(FixedMenuStyle.inkSoft)
                Text("还没有存稿").font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                Text("在便签上写好，按「保存」（或 START），这一张的样子就夹到便签右上角的别针上。")
                    .font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .multilineTextAlignment(.center).padding(.horizontal, 34 * s)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notes-draft-top")
    }
    private var caption: String {
        guard let draft = model.selectedDraft else { return "" }
        let when = draft.saved.map { $0.formatted(.dateTime.locale(UILanguage.locale).month().day().hour().minute(.twoDigits)) } ?? ""
        let sheet = model.sheets.first { $0.id.hasPrefix(String(draft.base.dropFirst(16))) }
        return String(localized: "保存于 \(when)") + (sheet?.software.map { " · \($0)" } ?? "")
    }
}

/// 照片 on the upper screen (11-07): the sheet's photo, as large as the
/// screen takes it, on black; what it is along the top.
private struct GameNotesPhotoTop: View {
    var image: CGImage
    var name: String?
    var s: Double
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            ZStack {
                Image(decorative: image, scale: 1).resizable().interpolation(.medium).scaledToFit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "上屏的照片") + (name.map { String(localized: "，\($0)") } ?? ""))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("notes-top-photo")
            Text(String(localized: "这一张的照片") + (name.map { " · \($0)" } ?? ""))
                .font(.system(size: 9 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(FixedMenuStyle.bar.opacity(0.85)))
                .padding(8 * s)
                .accessibilityHidden(true)
        }
    }
}

/// 选照片 on the upper screen (11-07): the album's picture chosen, at size,
/// and what A does; or that the album has none yet.
private struct GameNotesPhotoPickTop: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        if let picture = model.albumPicture, let chosen = model.selectedAlbumPhoto {
            ZStack(alignment: .bottom) {
                Color.black
                ZStack {
                    Image(decorative: picture, scale: 1).resizable().interpolation(.medium).scaledToFit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel("要放到上屏的照片，\(chosen.name)")
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("notes-photo-chosen")
                Text("\(chosen.name) · \(chosen.date.formatted(.dateTime.locale(UILanguage.locale).month().day().hour().minute(.twoDigits))) · A 放到上屏")
                    .font(.system(size: 9 * s, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10 * s).padding(.vertical, 4 * s)
                    .background(Capsule().fill(FixedMenuStyle.bar.opacity(0.85)))
                    .padding(.bottom, 8 * s)
                    .accessibilityHidden(true)
            }
        } else {
            VStack(spacing: 7 * s) {
                Image(systemName: "photo").font(.system(size: 26 * s, weight: .semibold)).foregroundStyle(FixedMenuStyle.inkSoft)
                Text("相册里还没有照片").font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                Text("用「相机」拍几张，就能放一张到上屏，在下屏的便签上对着它写。")
                    .font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .multilineTextAlignment(.center).padding(.horizontal, 34 * s)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notes-photo-none")
        }
    }
}

/// A small deterministic random (the paper's grain, the block's edges).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0x1F_FFFF) / Double(0x20_0000)
    }
}

/// The pad: a thick block of sheets, the top one drawn on, the ones turned
/// over lying above the glue with their backs up. Two fingers on the sheet
/// (a trackpad's two fingers too) turn it: up lifts the sheet
/// up and over the glue strip (the next one is up), down brings the last
/// one turned over back; the sheet follows the fingers in perspective and
/// goes over or falls back when they let go. Above the pad a
/// strip of the last sheet turned over — its back, what is written on it
/// showing through faintly, upside down, as paper held to the light does;
/// nothing above the first page.
private struct StickyPadView: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    /// The turn: 0 flat on the pad, 1 over and lying above it — the sheet
    /// up's while lifting, the last turned sheet's (coming down from 1)
    /// while pulling.
    @State private var lift = 0.0
    @State private var pulling = false
    @State private var dragging = false
    /// Which way the two fingers went first (decided once they have moved).
    @State private var direction = 0
    /// How thick the pad looks at least (a fresh pad is still a pad).
    private static let thickness = 26
    /// How much of the sheets turned over shows above the pad.
    private var band: Double { 26 * s }
    var body: some View {
        GeometryReader { proxy in
            let pad = padRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                // The block under this sheet: the written ones that are
                // under it, then the blank rest of the pad — a pad is thick
                // and never used up; a blank page's paper
                // is the one a new page will get.
                let under = max(min(model.below, 34), Self.thickness)
                ForEach(0..<under, id: \.self) { i in
                    let depth = under - i    // the deepest first
                    let position = model.index + depth
                    let sheet = model.sheets.indices.contains(position) ? model.sheets[position] : nil
                    let beyond = position - (model.sheets.count - 1)
                    let paper = sheet.map { StickyPaper.of($0) } ?? StickyPaper.at((model.sheets.last?.paper ?? 0) + beyond)
                    StickySheetFace(paper: paper, tilt: sheet?.tilt ?? Self.tilt(at: depth), s: s, seed: UInt64(depth), content: { EmptyView() })
                        .frame(width: pad.width, height: pad.height)
                        .offset(x: pad.minX + Self.sway(at: depth) * s, y: pad.minY + Double(depth) * 0.85 * s)
                        .accessibilityHidden(true)
                }
                // The sheets turned over (a few; the last on top), lying above
                // the glue with their backs up — the screen's edge cuts them.
                let over = min(model.above, 4)
                ForEach(0..<over, id: \.self) { i in
                    let depth = over - i    // the deepest first
                    let position = model.index - depth
                    if (depth > 1 || !pulling), model.sheets.indices.contains(position) {
                        StickySheetBack(sheet: model.sheets[position], s: s, seeThrough: depth == 1)
                            .frame(width: pad.width, height: pad.height)
                            .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
                            .shadow(color: .black.opacity(depth == 1 ? 0.2 : 0.1), radius: 1.5 * s)
                            .offset(x: pad.minX + Self.sway(at: depth + 40) * 0.9 * s, y: pad.minY - Double(depth - 1) * 0.8 * s)
                            .zIndex(1)
                            .accessibilityHidden(true)
                    }
                }
                // The sheet up: written on; two fingers lift it. Past upright
                // its back is what faces the screen.
                if let sheet = model.current {
                    let turn = pulling ? 0 : lift
                    let rise = sin(turn * .pi)
                    StickySheetFace(paper: StickyPaper.of(sheet), tilt: sheet.tilt, s: s, seed: UInt64(sheet.paper), content: {
                        ZStack {
                            if let background = model.background {
                                Image(decorative: background, scale: 1).resizable().interpolation(.none).scaledToFit()
                                    .opacity(0.92)
                                    .accessibilityHidden(true)
                            }
                            GameNoteCanvas(model: model, size: pad.size, sheetID: sheet.id, twoFingers: { twoFingers($0, pad: pad) })
                            if turn > 0.5 {
                                StickySheetBackLayer(sheet: live(sheet), s: s)
                                    .allowsHitTesting(false)
                            }
                        }
                    })
                    .frame(width: pad.width, height: pad.height)
                    .overlay(alignment: .bottom) {
                        // The bottom edge: curled a little, a shadow under it
                        // (and, for VoiceOver and the tests, the way to the
                        // next sheet).
                        StickyLiftEdge(s: s)
                            .frame(height: 26 * s)
                            .opacity(turn > 0.5 ? 0 : 1)
                            .allowsHitTesting(false)
                            .accessibilityElement()
                            .accessibilityLabel("便签的下边")
                            .accessibilityValue(model.below > 0 ? "双指往上推，翻到下一张" : "双指往上推，翻开新的一页")
                            .accessibilityIdentifier("notes-next")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { flipAnimated(forward: true) }
                    }
                    .rotation3DEffect(.degrees(-180 * turn), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
                    .shadow(color: .black.opacity(0.25 + 0.3 * rise), radius: (4 + 14 * rise) * s, y: (3 + 10 * rise) * s)
                    .offset(x: pad.minX, y: pad.minY)
                    .zIndex(2)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("便签")
                    .accessibilityValue("第 \(model.index + 1) 张，写了 \(model.written) 张，\(model.isBlank ? String(localized: "空白") : String(localized: "写过"))")
                    .accessibilityIdentifier("notes-pad")
                }
                // 存稿 (C): the paper clip on the top right, once
                // something is saved.
                if model.savedCount > 0 {
                    StickyClip(model: model, s: s)
                        .offset(x: pad.maxX - 64 * s, y: max(0, pad.minY - 24 * s))
                        .zIndex(3)
                }
                // 照片 (11-07): a small print taped on the top left — the
                // sheet's photo when it has one; a touch chooses one from the
                // album for the upper screen.
                StickyPhotoCorner(model: model, s: s)
                    .offset(x: pad.minX - 4 * s, y: max(0, pad.minY - 26 * s))
                    .zIndex(3)
                if model.above > 0 {
                    // The crease the sheets turned over make at the glue.
                    LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(width: pad.width, height: 3 * s)
                        .offset(x: pad.minX, y: pad.minY)
                        .allowsHitTesting(false)
                        .zIndex(2.5)
                        .accessibilityHidden(true)
                    // The last sheet turned over, coming back down: its back
                    // until it is upright, then its face.
                    if pulling {
                        let previous = model.sheets[model.index - 1]
                        let rise = sin(lift * .pi)
                        StickySheetFace(paper: StickyPaper.of(previous), tilt: previous.tilt, s: s, seed: UInt64(previous.paper), content: {
                            ZStack {
                                StickySheetPrint(sheet: previous, s: s)
                                if lift > 0.5 { StickySheetBackLayer(sheet: previous, s: s) }
                            }
                        })
                        .frame(width: pad.width, height: pad.height)
                        .rotation3DEffect(.degrees(-180 * lift), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
                        .shadow(color: .black.opacity(0.25 + 0.3 * rise), radius: (4 + 14 * rise) * s, y: (3 + 10 * rise) * s)
                        .offset(x: pad.minX, y: pad.minY)
                        .zIndex(4)
                        .accessibilityHidden(true)
                    }
                    Color.clear
                        .frame(width: pad.width, height: max(8 * s, pad.minY))
                        .offset(x: pad.minX, y: 0)
                        .allowsHitTesting(false)
                        .zIndex(5)
                        .accessibilityElement()
                        .accessibilityLabel("翻过去的便签")
                        .accessibilityValue("\(model.above) 张，双指往下拉翻回来")
                        .accessibilityIdentifier("notes-prev")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { flipAnimated(forward: false) }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // The sheets turned over go up under the top of the screen.
            .clipped()
            .onChange(of: model.flipRequests) { _, _ in
                // L / R, 新的一张 and the keys: the same turn as the fingers'.
                guard let forward = model.flipRequested else { return }
                flipAnimated(forward: forward, toNewPage: model.flipToNewPage)
            }
        }
    }
    /// The sheet up as it is being written (its back shows what is on it now).
    private func live(_ sheet: StickySheet) -> StickySheet {
        var copy = sheet
        copy.drawing = model.drawing
        copy.width = model.canvasSize.width
        copy.height = model.canvasSize.height
        return copy
    }
    /// The edges of the block: a slight waver so it does not look cut by a
    /// machine, and a little twist deeper down.
    private static func sway(at depth: Int) -> Double {
        var g = SeededRandom(seed: UInt64(depth) &* 31 &+ 7)
        return (g.next() - 0.5) * 1.6 + Double(depth) * 0.12 * (depth % 2 == 0 ? 1 : -1)
    }
    private static func tilt(at depth: Int) -> Double {
        var g = SeededRandom(seed: UInt64(depth) &* 17 &+ 3)
        return (g.next() - 0.5) * 1.2
    }
    /// Where the pad lies: a strip at the top for the sheets turned over,
    /// the pad under it nearly as wide as the screen, 3:2 at most
    /// as a sticky note's pad, its block's lower edges (22 points) below.
    private func padRect(in size: CGSize) -> CGRect {
        let margin = 16 * s
        let width = size.width - 2 * margin
        let room = size.height - band - 30 * s
        let height = max(40 * s, min(room, width * 0.66))
        return CGRect(x: margin, y: band + min(max(0, (room - height) / 2), 8 * s), width: width, height: height)
    }
    /// Two fingers on the sheet: up lifts this sheet (the turn follows), down
    /// brings the last one turned over back; let go past 42% of the pad's
    /// height (or quickly) and it goes over, else it falls back.
    private func twoFingers(_ event: GameNoteCanvas.TwoFingers, pad: CGRect) {
        let height = max(1, pad.height)
        switch event {
        case .moved(let dy):
            if direction == 0 {
                guard abs(dy) > 6 * s else { return }
                model.closePalette()
                direction = dy < 0 ? -1 : 1
                dragging = true
                pulling = direction > 0
                if pulling, model.above == 0 { pulling = false; direction = -1 }
            }
            if direction < 0 {
                let travel = max(0, -dy) / height
                lift = min(1, travel * 1.15)
            } else {
                let travel = max(0, dy) / height
                lift = max(0, 1 - travel * 1.15)
            }
        case .ended(let dy, let velocity):
            guard direction != 0 else { return }
            if direction < 0 {
                // Over at the last written sheet too: the page under
                // it is a new one.
                let travel = max(0, -dy) / height
                let fast = velocity < -700
                if travel > 0.42 || fast { finish(forward: true) } else { fallBack() }
            } else {
                let travel = max(0, dy) / height
                let fast = velocity > 700
                if travel > 0.42 || fast { finish(forward: false) } else { fallBack() }
            }
        case .cancelled:
            if direction != 0 { fallBack() }
        }
    }
    /// The sheet goes the rest of the way over (or down), then the model
    /// turns the page.
    private func finish(forward: Bool) {
        let target = forward ? 1.0 : 0.0
        withAnimation(.easeIn(duration: 0.24)) { lift = target }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            model.flip(forward: forward)
            lift = 0
            pulling = false
            dragging = false
            direction = 0
        }
    }
    private func fallBack() {
        let rest = pulling ? 1.0 : 0.0
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { lift = rest }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            pulling = false
            lift = 0
            dragging = false
            direction = 0
        }
    }
    /// A turn asked by a key, 新的一张 or VoiceOver: the whole animation, as if
    /// two fingers had done it (新的一张 then goes on to the new page).
    private func flipAnimated(forward: Bool, toNewPage: Bool = false) {
        guard !dragging else { return }
        if forward {
            dragging = true; pulling = false; direction = -1
            withAnimation(.easeInOut(duration: 0.5)) { lift = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(510))
                if toNewPage { model.turnToNewPage() } else { model.flip(forward: true) }
                lift = 0; pulling = false; dragging = false; direction = 0
            }
        } else {
            guard model.above > 0 else { model.flip(forward: false); return }
            dragging = true; pulling = true; direction = 1
            lift = 1
            withAnimation(.easeInOut(duration: 0.5)) { lift = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(510))
                model.flip(forward: false)
                lift = 0; pulling = false; dragging = false; direction = 0
            }
        }
    }
}

/// One sheet of the pad: old paper with a grain, faint rules, the glue
/// strip along the top, a little tilt; `content` lies on it.
private struct StickySheetFace<Content: View>: View {
    var paper: StickyPaper
    var tilt: Double
    var s: Double
    var seed: UInt64
    /// The printed rules (a sheet's back has none of its own).
    var ruleOpacity: Double = 0.28
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous).fill(paper.face)
                // The grain: specks and a faint mottling, the same for the
                // same paper; and the rules.
                Canvas { context, size in
                    var generator = SeededRandom(seed: seed &+ 11)
                    for _ in 0..<220 {
                        let x = generator.next() * size.width, y = generator.next() * size.height
                        let r = 0.3 + generator.next() * 0.9
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * s, height: r * s)), with: .color(.black.opacity(0.03 + generator.next() * 0.05)))
                    }
                    for _ in 0..<6 {
                        let x = generator.next() * size.width, y = generator.next() * size.height
                        let r = (10 + generator.next() * 30) * s
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.brown.opacity(0.03)))
                    }
                    guard ruleOpacity > 0 else { return }
                    if paper.squared {
                        // 铁皮盒's exercise paper: squares under the glue strip.
                        let step = size.height / 10
                        var squares = Path()
                        var y = size.height * 0.07 + step * 0.5
                        while y < size.height - 1 {
                            squares.move(to: CGPoint(x: 0, y: y))
                            squares.addLine(to: CGPoint(x: size.width, y: y))
                            y += step
                        }
                        var x = step * 0.5
                        while x < size.width - 1 {
                            squares.move(to: CGPoint(x: x, y: size.height * 0.07))
                            squares.addLine(to: CGPoint(x: x, y: size.height))
                            x += step
                        }
                        context.stroke(squares, with: .color(StickyPaper.square.opacity(ruleOpacity * 1.2)), lineWidth: max(0.5, 0.6 * s))
                        return
                    }
                    let step = size.height / 8
                    var y = step * 1.5
                    var rules = Path()
                    while y < size.height - 2 {
                        rules.move(to: CGPoint(x: size.width * 0.04, y: y))
                        rules.addLine(to: CGPoint(x: size.width * 0.96, y: y))
                        y += step
                    }
                    context.stroke(rules, with: .color(StickyPaper.rule.opacity(ruleOpacity)), lineWidth: max(0.5, 0.7 * s))
                }
                .allowsHitTesting(false)
                content()
                // The glue strip along the top (a little darker, a crease
                // under it).
                VStack(spacing: 0) {
                    Rectangle().fill(paper.strip.opacity(0.75)).frame(height: size.height * 0.07)
                    Rectangle().fill(.black.opacity(0.06)).frame(height: 1 * s)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous))
            .rotationEffect(.degrees(tilt), anchor: .top)
        }
    }
}

/// A sheet turned over, lying above the pad: its paper's back; the last
/// one turned over (`seeThrough`) held to the light — its rules and its
/// writing showing through faintly (drawn as on its face: lying turned
/// over, they show upside down).
private struct StickySheetBack: View {
    var sheet: StickySheet
    var s: Double
    var seeThrough: Bool
    var body: some View {
        let paper = StickyPaper.of(sheet)
        StickySheetFace(paper: StickyPaper(face: paper.back, strip: paper.strip, back: paper.back, squared: paper.squared), tilt: sheet.tilt, s: s,
                        seed: UInt64(sheet.paper) &+ 97, ruleOpacity: seeThrough ? 0.07 : 0, content: {
            if seeThrough { StickySeeThrough(sheet: sheet, s: s) }
        })
    }
}

/// The back laid over a sheet's face while it is turned past upright (the
/// sheet up going over, the last one coming back).
private struct StickySheetBackLayer: View {
    var sheet: StickySheet
    var s: Double
    var body: some View {
        ZStack {
            Rectangle().fill(StickyPaper.of(sheet).back)
            StickySeeThrough(sheet: sheet, s: s)
        }
        .accessibilityHidden(true)
    }
}

/// What shows through a sheet's back: its writing, faint and soft.
private struct StickySeeThrough: View {
    var sheet: StickySheet
    var s: Double
    var body: some View {
        StickySheetPrint(sheet: sheet, s: s)
            .opacity(0.17)
            .blur(radius: 0.6 * s)
            .allowsHitTesting(false)
    }
}

/// A kept sheet's strokes as a picture (the sheet coming back down, and
/// showing through a sheet's back).
private struct StickySheetPrint: View {
    var sheet: StickySheet
    var s: Double
    var body: some View {
        Group {
            #if os(iOS)
            GeometryReader { proxy in
                if let image = Self.image(of: sheet, size: proxy.size) {
                    Image(uiImage: image).resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            #endif
        }
        .accessibilityHidden(true)
    }
    #if os(iOS)
    /// The pictures made (a turn draws the view again many times; the
    /// strokes are drawn into a picture once).
    @MainActor private static var made: [String: UIImage] = [:]
    @MainActor private static var order: [String] = []
    @MainActor private static func image(of sheet: StickySheet, size: CGSize) -> UIImage? {
        guard size.width > 1, size.height > 1, !sheet.drawing.isEmpty else { return nil }
        let key = "\(sheet.id)-\(sheet.drawing.count)-\(sheet.drawing.hashValue)-\(Int(size.width))x\(Int(size.height))"
        if let image = made[key] { return image }
        guard let drawing = try? PKDrawing(data: sheet.drawing) else { return nil }
        let fitted = drawing.transformed(using: CGAffineTransform(scaleX: size.width / max(1, sheet.width), y: size.height / max(1, sheet.height)))
        // PencilKit adapts ink colours to the interface style: drawn as light.
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = fitted.image(from: CGRect(origin: .zero, size: size), scale: 2)
        }
        made[key] = image
        order.append(key)
        if order.count > 12 { made.removeValue(forKey: order.removeFirst()) }
        return image
    }
    #endif
}

/// The top sheet's bottom edge: a slight curl, the shadow under it, the
/// place to lift it from.
private struct StickyLiftEdge: View {
    var s: Double
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [.clear, .black.opacity(0.07)], startPoint: .top, endPoint: .bottom)
            // The curled corner.
            Path { path in
                path.move(to: CGPoint(x: 0, y: 22 * s))
                path.addLine(to: CGPoint(x: 22 * s, y: 22 * s))
                path.addLine(to: CGPoint(x: 22 * s, y: 0))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [.white.opacity(0.55), .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 22 * s, height: 22 * s)
            .padding(.trailing, 2 * s).padding(.bottom, 1 * s)
        }
    }
}

/// The tools along the bottom, tight (a 3DS-sized lower screen is 320
/// points wide): the pen — its ink; a touch opens the inks' menu —
/// and the eraser, 撤销; 截屏, 新的一张 (back as it was),
/// 撕掉, 保存.
private struct StickyToolRow: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        HStack(spacing: 4 * s) {
            // 11-06: the pens as before (black, red, blue, the eraser),
            // the third one now the inks' menu: it shows the ink last picked
            // there and opens the menu.
            HStack(spacing: 2 * s) {
                ForEach(GameNotePen.offered) { pen in
                    Button { model.pick(pen) } label: {
                        ZStack {
                            switch pen {
                            case .black: Circle().fill(GameNoteInk.black.color)
                            case .red: Circle().fill(GameNoteInk.red.color)
                            case .more:
                                Circle().fill(model.moreInk.color)
                                // Three dots: there is a menu behind it.
                                HStack(spacing: 1.2 * s) {
                                    ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.9)).frame(width: 2.2 * s, height: 2.2 * s) }
                                }
                            case .eraser:
                                Circle().fill(GameNoteTool.eraser.color)
                                Image(systemName: "eraser.fill").font(.system(size: 8 * s, weight: .bold)).foregroundStyle(FixedMenuStyle.ink)
                            case .flower:
                                Circle().fill(Color(red: 1.0, green: 0.93, blue: 0.9))
                                Canvas { context, size in
                                    TinArt().draw(.redFlower, in: context, rect: CGRect(x: size.width * 0.08, y: size.height * 0.1, width: size.width * 0.84, height: size.height * 0.84))
                                }
                            }
                        }
                        .frame(width: 16 * s, height: 16 * s)
                        .overlay(Circle().strokeBorder(.white, lineWidth: model.pen == pen ? 2.5 * s : 0))
                        .frame(width: 20 * s, height: 24 * s)
                        .background(Capsule().fill(.white.opacity(pen == .more && model.paletteOpen ? 0.22 : 0)).frame(width: 22 * s, height: 26 * s))
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityLabel(pen == .more ? "更多颜色：\(model.moreInk.title)" : (pen == .black ? "黑笔" : pen == .red ? "红笔" : pen == .flower ? "小红花印章" : "橡皮"))
                    .accessibilityIdentifier("notes.tool.\(pen.rawValue)")
                    .accessibilityAddTraits(model.pen == pen ? [.isButton, .isSelected] : .isButton)
                }
            }
            GameNotePill(title: String(localized: "撤销"), symbol: "arrow.uturn.backward", color: FixedMenuStyle.inkSoft, s: s, identifier: "notes-undo", compact: true) { model.undo() }
            Spacer(minLength: 0)
            if model.hasScreens {
                GameNotePill(title: model.backgroundSide == nil ? String(localized: "截屏") : (model.backgroundSide == "top" ? String(localized: "截下屏") : String(localized: "去掉画面")), symbol: "rectangle.inset.filled", color: FixedMenuStyle.accent, s: s, identifier: "notes-take", compact: true) { model.cycleScreen() }
            } else if model.background != nil {
                GameNotePill(title: String(localized: "去掉画面"), symbol: "xmark.rectangle", color: FixedMenuStyle.inkSoft, s: s, identifier: "notes-take-none", compact: true) { model.takeScreen(nil) }
            }
            GameNotePill(title: String(localized: "新的一张"), symbol: "plus", color: FixedMenuStyle.go, s: s, identifier: "notes-new", compact: true) { model.newSheet() }
            GameNotePill(title: String(localized: "撕掉"), symbol: "trash", color: FixedMenuStyle.stop, s: s, identifier: "notes-tear", compact: true) { model.askTear() }
            GameNotePill(title: String(localized: "保存"), symbol: "square.and.arrow.down", color: FixedMenuStyle.accent, s: s, identifier: "notes-save", compact: true) { model.save() }
        }
        .padding(.horizontal, 6 * s)
        .frame(height: 34 * s)
        .background(FixedMenuStyle.bar)
    }
}

/// The inks' menu: up over the tool row from the
/// pen; a touch on an ink takes it and puts the menu away (the D-pad moves
/// in it; A or B puts it away).
private struct StickyPalette: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack(spacing: 4 * s) {
                Text("更多颜色").font(.system(size: 9.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                Spacer(minLength: 4 * s)
                Text("十字键也能换").font(.system(size: 8 * s, weight: .semibold)).foregroundStyle(FixedMenuStyle.inkSoft)
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6 * s) {
                    ForEach(Array(GameNoteInk.allCases[(row * 6)..<(row * 6 + 6)])) { ink in
                        Button { model.choose(ink) } label: {
                            Circle().fill(ink.color).frame(width: 22 * s, height: 22 * s)
                                .padding(3 * s)
                                .overlay(Circle().strokeBorder(FixedMenuStyle.accent, lineWidth: model.moreInk == ink ? 2 * s : 0))
                        }
                        .buttonStyle(MenuPressStyle())
                        .accessibilityLabel("\(ink.title)笔")
                        .accessibilityIdentifier("notes.ink.\(ink.rawValue)")
                        .accessibilityAddTraits(model.moreInk == ink ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .padding(.horizontal, 7 * s).padding(.vertical, 7 * s)
        .background(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).fill(Color.white)
            .shadow(color: .black.opacity(0.28), radius: 7 * s, y: 3 * s))
        .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(FixedMenuStyle.tileEdge.opacity(0.6), lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            // The point toward the third pen (its centre 60 s from the row's edge).
            Rectangle().fill(Color.white).frame(width: 10 * s, height: 10 * s)
                .rotationEffect(.degrees(45)).offset(x: 50 * s, y: 5 * s)
        }
        .padding(.leading, 5 * s)
        .padding(.bottom, 39 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes-palette")
    }
}

private struct StickyTearDialog: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 10 * s) {
                Text("撕掉这一张？").font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                // The sheet's saved copies go with it.
                Text(model.currentHasSavedCopies ? "上面的字和画面都没了；存稿里这一张的那份也一起撕掉。" : "上面的字和画面都没了。")
                    .font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8 * s) {
                    GameNotePill(title: String(localized: "取消"), symbol: "xmark", color: FixedMenuStyle.inkSoft, s: s, identifier: "notes-tear-cancel") { model.cancelTear() }
                    GameNotePill(title: String(localized: "撕掉"), symbol: "trash", color: FixedMenuStyle.stop, s: s, identifier: "notes-tear-confirm") { model.tearChosen() }
                }
            }
            .padding(14 * s)
            .frame(width: 230 * s)
            .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(FixedMenuStyle.tile))
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// 存稿's way in (C): a paper clip on the pad's top right, holding
/// the newest saved copies (their small pictures); a touch opens 存稿. It
/// is there once something has been saved.
private struct StickyClip: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        Button { model.openGallery() } label: {
            ZStack(alignment: .topLeading) {
                ForEach(Array(model.clipThumbs.enumerated().reversed()), id: \.offset) { offset, image in
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: 40 * s, height: 27 * s)
                        .clipped()
                        .overlay(Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5 * s))
                        .shadow(color: .black.opacity(0.3), radius: 1.5 * s, y: 1 * s)
                        .rotationEffect(.degrees(offset == 0 ? -5 : 8))
                        .offset(x: offset == 0 ? 6 * s : 15 * s, y: offset == 0 ? 8 * s : 4 * s)
                }
                PaperClipShape()
                    .stroke(LinearGradient(colors: [Color(white: 0.52), Color(white: 0.96), Color(white: 0.5)], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.35), radius: 0.8 * s, x: 0.6 * s, y: 0.8 * s)
                    .frame(width: 12 * s, height: 34 * s)
                    .rotationEffect(.degrees(-9))
                    .offset(x: 22 * s, y: 0)
            }
            .frame(width: 62 * s, height: 44 * s, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel("存稿")
        .accessibilityHint("看保存过的便签")
        .accessibilityIdentifier("notes-drafts")
    }
}

/// 照片's way in (11-07): a small print taped to the pad's top left, its
/// wide lower margin saying 照片 — the sheet's photo in it when it has one.
private struct StickyPhotoCorner: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        Button { model.openPhotoPicker() } label: {
            VStack(spacing: 0) {
                ZStack {
                    if let photo = model.photo {
                        Image(decorative: photo, scale: 1).resizable().scaledToFill()
                            .frame(width: 34 * s, height: 25.5 * s)
                    } else {
                        FixedMenuStyle.paper
                        Image(systemName: "photo").font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(FixedMenuStyle.inkSoft)
                    }
                }
                .frame(width: 34 * s, height: 25.5 * s)
                .clipped()
                Text("照片").font(.system(size: 7 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .frame(height: 10 * s)
            }
            .padding([.top, .horizontal], 3 * s)
            .background(Rectangle().fill(Color.white).shadow(color: .black.opacity(0.3), radius: 1.5 * s, y: 1 * s))
            .overlay(alignment: .top) {
                // A bit of tape holding it.
                Rectangle().fill(Color(red: 0.98, green: 0.94, blue: 0.76).opacity(0.78))
                    .frame(width: 18 * s, height: 6 * s)
                    .rotationEffect(.degrees(5))
                    .offset(y: -3 * s)
            }
            .rotationEffect(.degrees(-6))
            .frame(width: 50 * s, height: 48 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityLabel("照片")
        .accessibilityValue(model.photoName.map { "上屏是 \($0)" } ?? "还没有照片")
        .accessibilityHint("选一张相册里的照片放到上屏，在下屏对着它写")
        .accessibilityIdentifier("notes-photo")
    }
}

/// 选照片 (11-07): the album's pictures four by two a page, the newest
/// first, as small prints; the one chosen is at size on the upper screen.
/// A touch chooses one.
private struct StickyPhotoPicker: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        GeometryReader { proxy in
            let page = model.albumPage
            let first = page * GameNotesModel.photosPerPage
            let shown = Array(model.albumPhotos.dropFirst(first).prefix(GameNotesModel.photosPerPage))
            let columns = 4
            let gap = 10 * s
            let cellWidth = (proxy.size.width - 28 * s - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let cellHeight = cellWidth * 0.75
            ZStack(alignment: .topLeading) {
                if model.albumPhotos.isEmpty {
                    VStack(spacing: 6 * s) {
                        Image(systemName: "photo").font(.system(size: 20 * s, weight: .semibold))
                        Text("相册里还没有照片").font(.system(size: 12 * s, weight: .heavy, design: .rounded))
                        Text("用「相机」拍几张再来").font(.system(size: 9 * s, weight: .medium))
                    }
                    .foregroundStyle(FixedMenuStyle.inkSoft)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { offset, picture in
                    let row = offset / columns, column = offset % columns
                    let selected = first + offset == model.albumIndex
                    Button { model.selectAlbumPhoto(first + offset) } label: {
                        StickyPhotoThumb(image: model.albumThumbs[picture.url], s: s)
                            .frame(width: cellWidth, height: cellHeight)
                            .overlay(RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                                .strokeBorder(selected ? FixedMenuStyle.accent : .clear, lineWidth: 2.5 * s).padding(-4 * s))
                    }
                    .buttonStyle(MenuPressStyle())
                    .offset(x: 14 * s + CGFloat(column) * (cellWidth + gap), y: 14 * s + CGFloat(row) * (cellHeight + 14 * s))
                    .accessibilityLabel("照片 \(picture.name)")
                    .accessibilityIdentifier("notes-photo-\(first + offset)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
                if model.albumPages > 1 {
                    HStack(spacing: 5 * s) {
                        ForEach(0..<model.albumPages, id: \.self) { p in
                            Circle().fill(FixedMenuStyle.ink.opacity(p == page ? 0.7 : 0.2)).frame(width: 5 * s, height: 5 * s)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height - 6 * s, alignment: .bottom)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes-photos")
    }
}

/// An album picture's small print: a white edge round it.
private struct StickyPhotoThumb: View {
    var image: CGImage?
    var s: Double
    var body: some View {
        Rectangle().fill(Color.white)
            .overlay(
                Group {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    } else {
                        FixedMenuStyle.paperDeep
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .padding(2 * s)
            )
            .shadow(color: .black.opacity(0.22), radius: 2 * s, y: 1.5 * s)
    }
}

/// 选照片's keys along the bottom.
private struct StickyPhotoBar: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        HStack(spacing: 6 * s) {
            GameNotePill(title: String(localized: "返回便签"), symbol: "chevron.left", color: FixedMenuStyle.inkSoft, s: s, identifier: "notes-photo-back") { model.closePhotoPicker() }
            GameNotePill(title: String(localized: "放到上屏"), symbol: "arrow.up", color: FixedMenuStyle.go, s: s, identifier: "notes-photo-put", enabled: model.selectedAlbumPhoto != nil) { model.putPhotoUp() }
            if model.photo != nil {
                GameNotePill(title: String(localized: "不要照片"), symbol: "xmark", color: FixedMenuStyle.stop, s: s, identifier: "notes-photo-remove") { model.removePhoto() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6 * s)
        .frame(height: 34 * s)
        .background(FixedMenuStyle.bar)
    }
}

/// A wire bent into a paper clip, standing.
private struct PaperClipShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var p = Path()
        p.move(to: at(0.32, 0.70))
        p.addLine(to: at(0.32, 0.22))
        p.addCurve(to: at(0.68, 0.22), control1: at(0.32, 0.04), control2: at(0.68, 0.04))
        p.addLine(to: at(0.68, 0.82))
        p.addCurve(to: at(0.10, 0.82), control1: at(0.68, 1.0), control2: at(0.10, 1.0))
        p.addLine(to: at(0.10, 0.14))
        p.addCurve(to: at(0.90, 0.14), control1: at(0.10, -0.05), control2: at(0.90, -0.05))
        p.addLine(to: at(0.90, 0.62))
        return p
    }
}

/// 存稿 (as the afternoon's sketch, on the first version's light
/// backdrop): the saved copies four by two a page, the
/// newest first; the one chosen is at size on the upper screen. A touch
/// chooses one.
private struct StickyGallery: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        GeometryReader { proxy in
            let page = model.draftPage
            let first = page * GameNotesModel.draftsPerPage
            let shown = Array(model.drafts.dropFirst(first).prefix(GameNotesModel.draftsPerPage))
            let columns = 4
            let gap = 10 * s
            let cellWidth = (proxy.size.width - 28 * s - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let cellHeight = cellWidth * 0.66
            ZStack(alignment: .topLeading) {
                if model.drafts.isEmpty {
                    VStack(spacing: 6 * s) {
                        Image(systemName: "paperclip").font(.system(size: 20 * s, weight: .semibold))
                        Text("还没有存稿").font(.system(size: 12 * s, weight: .heavy, design: .rounded))
                        Text("在便签上写好，按「保存」").font(.system(size: 9 * s, weight: .medium))
                    }
                    .foregroundStyle(FixedMenuStyle.inkSoft)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { offset, draft in
                    let row = offset / columns, column = offset % columns
                    let selected = first + offset == model.draftIndex
                    Button { model.selectDraft(first + offset) } label: {
                        StickyDraftThumb(image: model.draftThumbs[draft.base], s: s)
                            .frame(width: cellWidth, height: cellHeight)
                            .rotationEffect(.degrees(Self.tilt(for: draft.base)))
                            .overlay(RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                                .strokeBorder(selected ? FixedMenuStyle.accent : .clear, lineWidth: 2.5 * s).padding(-4 * s))
                    }
                    .buttonStyle(MenuPressStyle())
                    .offset(x: 14 * s + CGFloat(column) * (cellWidth + gap), y: 14 * s + CGFloat(row) * (cellHeight + 16 * s))
                    .accessibilityLabel(draft.saved.map { "存稿，\($0.formatted(.dateTime.locale(UILanguage.locale).month().day().hour().minute(.twoDigits)))" } ?? "存稿")
                    .accessibilityIdentifier("notes-draft-\(first + offset)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
                if model.draftPages > 1 {
                    HStack(spacing: 5 * s) {
                        ForEach(0..<model.draftPages, id: \.self) { p in
                            Circle().fill(FixedMenuStyle.ink.opacity(p == page ? 0.7 : 0.2)).frame(width: 5 * s, height: 5 * s)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height - 6 * s, alignment: .bottom)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes-gallery")
    }
    /// Each copy lies a little askew, the same way each time.
    private static func tilt(for name: String) -> Double {
        var g = SeededRandom(seed: name.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) })
        return (g.next() - 0.5) * 2.4
    }
}

/// A saved copy's small picture, as a slip of paper.
private struct StickyDraftThumb: View {
    var image: CGImage?
    var s: Double
    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                StickyPaper.all[0].face
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 2 * s, y: 1.5 * s)
    }
}

/// 存稿's keys along the bottom.
private struct StickyGalleryBar: View {
    @ObservedObject var model: GameNotesModel
    var s: Double
    var body: some View {
        HStack(spacing: 6 * s) {
            GameNotePill(title: String(localized: "返回便签"), symbol: "chevron.left", color: FixedMenuStyle.inkSoft, s: s, identifier: "notes-gallery-back") { model.closeGallery() }
            GameNotePill(title: String(localized: "放回便签"), symbol: "arrow.uturn.left", color: FixedMenuStyle.go, s: s, identifier: "notes-draft-put-back", enabled: model.selectedDraft != nil) { model.putDraftBack() }
            GameNotePill(title: String(localized: "撕掉"), symbol: "trash", color: FixedMenuStyle.stop, s: s, identifier: "notes-draft-tear", enabled: model.selectedDraft != nil) { model.askDeleteDraft() }
            Spacer(minLength: 0)
            // 11-07: 存到照片, at the bar's other end.
            GameNotePill(title: String(localized: "存到照片"), symbol: "square.and.arrow.down", color: FixedMenuStyle.accent, s: s, identifier: "notes-draft-photos",
                         enabled: model.selectedDraft != nil && !model.savingDraftToPhotos) { model.saveDraftToPhotos() }
        }
        .padding(.horizontal, 6 * s)
        .frame(height: 34 * s)
        .background(FixedMenuStyle.bar)
    }
}

/// A question over the lower screen (删掉这份存稿？).
private struct StickyAskDialog: View {
    var title: String
    var note: String
    var confirm: String
    var s: Double
    var identifier: String
    var cancel: () -> Void
    var chosen: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 10 * s) {
                Text(title).font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(FixedMenuStyle.ink)
                Text(note).font(.system(size: 9.5 * s, weight: .medium)).foregroundStyle(FixedMenuStyle.inkSoft)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8 * s) {
                    GameNotePill(title: String(localized: "取消"), symbol: "xmark", color: FixedMenuStyle.inkSoft, s: s, identifier: "\(identifier)-cancel", action: cancel)
                    GameNotePill(title: confirm, symbol: "trash", color: FixedMenuStyle.stop, s: s, identifier: "\(identifier)-confirm", action: chosen)
                }
            }
            .padding(14 * s)
            .frame(width: 230 * s)
            .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(FixedMenuStyle.tile))
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private struct GameNotePill: View {
    var title: String
    var symbol: String
    var color: Color
    var s: Double
    var identifier: String
    var enabled = true
    /// Words only, tight (the row of tools).
    var compact = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4 * s) {
                if !compact { Image(systemName: symbol).font(.system(size: 9 * s, weight: .bold)) }
                Text(title).font(.system(size: (compact ? 9.5 : 10) * s, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, (compact ? 6 : 8) * s)
            .frame(height: (compact ? 24 : 26) * s)
            .background(Capsule().fill(color.opacity(enabled ? 1 : 0.45)))
        }
        .buttonStyle(MenuPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// On LCDs too small to draw on (a phone's 掌机模式): over the whole display,
/// with a way out below (the console's keys are under it).
struct GameNotesFullScreen: View {
    @ObservedObject var model: GameNotesModel
    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let topHeight = min(proxy.size.height * 0.3, proxy.size.width * 0.6)
            VStack(spacing: 0) {
                GameNotesTopScreen(model: model)
                    .frame(width: proxy.size.width, height: topHeight)
                    .padding(.top, insets.top)
                    .background(FixedMenuStyle.paper)
                Rectangle().fill(FixedMenuStyle.bar).frame(height: 4)
                GameNotesBottomScreen(model: model)
                    .background(FixedMenuStyle.bar)
                // The way out, and — with no console keys under the pad on a
                // phone — the two flips (L / R on the console).
                HStack(spacing: 0) {
                    Button {
                        // 存稿 or 选照片 up: back to the pad first.
                        if model.galleryOpen { model.closeGallery(); return }
                        if model.photoPickerOpen { model.closePhotoPicker(); return }
                        ConsoleSounds.shared.play(.back)
                        model.leave()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                            Text("返回").font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityIdentifier("notes-leave")
                    Button {
                        if model.galleryOpen { model.moveDraft(-GameNotesModel.draftsPerPage) }
                        else if model.photoPickerOpen { model.moveAlbumPhoto(-GameNotesModel.photosPerPage) }
                        else { model.requestFlip(forward: false) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 12, weight: .bold))
                            Text("上一张").font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(model.above > 0 ? 1 : 0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityIdentifier("notes-prev-button")
                    Button {
                        if model.galleryOpen { model.moveDraft(GameNotesModel.draftsPerPage) }
                        else if model.photoPickerOpen { model.moveAlbumPhoto(GameNotesModel.photosPerPage) }
                        else { model.requestFlip(forward: true) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.to.line").font(.system(size: 12, weight: .bold))
                            Text("下一张").font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)    // past the last written sheet, a new page
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(MenuPressStyle())
                    .accessibilityIdentifier("notes-next-button")
                }
                .padding(.bottom, insets.bottom)
                .background(FixedMenuStyle.bar)
            }
            .ignoresSafeArea()
        }
    }
}
