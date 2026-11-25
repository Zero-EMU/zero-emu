import Foundation
import CryptoKit
import CoreGraphics
import ImageIO

struct GameRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fileName: String
    let byteCount: Int64
    let importedAt: Date
    /// Container format detected at import. Records written before 2026-10-27
    /// have no value and are NCSD cartridge images (the only format then).
    var format: ROMFormat? = nil
    /// From the title's SMDH (HOME Menu metadata), when it has one.
    var publisher: String? = nil
    /// Large SMDH icon, saved as PNG under `Icons/` in the data root.
    var iconFileName: String? = nil
    /// Which metadata pass has looked at this record (nil = imported before
    /// FoldArc read SMDH; the library refreshes those once from the copy).
    var metadataVersion: Int? = nil
    /// 11-07: where the file
    /// came from (a security-scoped bookmark of the file picked in Files or
    /// opened in place), so that deleting the card deletes it too. nil for
    /// records from before, and for copies the system handed over (AirDrop,
    /// Mail: those were FoldArc's own and went at import).
    var originBookmark: Data? = nil

    var resolvedFormat: ROMFormat { format ?? .cartridge }
}

/// What a file is, decided by its magic bytes (the extension only narrows
/// the candidates). FoldArc never ships any of these; the user imports them.
enum ROMFormat: String, Codable, CaseIterable, Sendable {
    /// NCSD cartridge image (.3ds / .cci).
    case cartridge
    /// Single NCCH executable (.cxi / .app).
    case executable
    /// Homebrew 3DSX (.3dsx).
    case homebrew
    /// Homebrew ELF (.elf).
    case elf

    var label: String {
        switch self {
        case .cartridge: return String(localized: "3DS 卡带镜像（NCSD）")
        case .executable: return String(localized: "3DS 程序（NCCH）")
        case .homebrew: return String(localized: "Homebrew（3DSX）")
        case .elf: return String(localized: "Homebrew（ELF）")
        }
    }
    /// Extension used for the managed copy; Azahar's loader goes by content
    /// but a few paths still look at the suffix, so keep a canonical one.
    var fileExtension: String {
        switch self {
        case .cartridge: return "cci"
        case .executable: return "cxi"
        case .homebrew: return "3dsx"
        case .elf: return "elf"
        }
    }
    /// The extension of a managed copy kept compressed (Z3DS), as the core
    /// names them; nil: the core runs no compressed file of this kind.
    var compressedExtension: String? {
        switch self {
        case .cartridge: return "zcci"
        case .executable: return "zcxi"
        case .homebrew: return "z3dsx"
        case .elf: return nil
        }
    }
    static let allExtensions: [String] = ["3ds", "cci", "cxi", "app", "3dsx", "elf", "zcci", "zcxi", "z3dsx", "cia"]
    static func candidates(forExtension ext: String) -> [ROMFormat] {
        switch ext.lowercased() {
        case "3ds", "cci", "zcci": return [.cartridge]
        case "cxi", "app", "zcxi", "cia": return [.executable]
        case "3dsx", "z3dsx": return [.homebrew]
        case "elf": return [.elf]
        default: return []
        }
    }
}

enum ImportFailure: LocalizedError {
    case invalidHeader, encrypted, duplicate, missingFile
    /// No 3DS software Zero EMU runs, and what it is instead (one line for every such file told the user nothing).
    case notSoftware(ForeignFile)
    /// Not enough free space for the library copy (the file's size).
    case noSpace(Int64)
    var errorDescription: String? {
        switch self {
        case .noSpace(let size):
            return String(localized: "存储空间不足：这个文件有 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))，设备上的可用空间不够把它复制进游戏库。清理一些空间后再导入。")
        case .notSoftware(let file): return file.explanation
        case .invalidHeader: return String(localized: "这个文件的内容不是 3DS 游戏（开头没有 NCSD / NCCH / 3DSX / ELF 标记），可能没下载完整，或者已经损坏。")
        case .encrypted: return String(localized: "这个文件带加密保护，没有导入。Zero EMU 只接受不带加密保护的文件，也不提供去除保护的办法。")
        case .duplicate: return String(localized: "这个文件已经在游戏库里了。")
        case .missingFile: return String(localized: "找不到原文件，请重新选择。")
        }
    }
    /// What the alert says when an import fails (11-07): the file's
    /// name over the reason, shortened in the middle when long.
    static func message(for error: Error, name: String) -> String {
        let shown = name.count > 48 ? String(name.prefix(30)) + "…" + String(name.suffix(15)) : name
        return shown.isEmpty ? error.localizedDescription : String(localized: "「\(shown)」\n\(error.localizedDescription)")
    }
}

/// What a file the importer turns away is (11-07): told by its first
/// bytes where they say it, else by its extension.
enum ForeignFile: Equatable, Sendable {
    /// A CIA install package: the libretro core runs no CIA (its extensions
    /// leave it out); it would have to be installed into the console first.
    case cia
    /// Azahar's own compression ("Z3DS": .zcci / .zcxi / .z3dsx / .zcia).
    case compressed
    /// An archive the game is in: "zip", "7z", "rar", "gz"…
    case archive(String)
    /// Anything else: its extension ("" without one).
    case other(String)

    static func identify(header: Data, extension ext: String) -> ForeignFile? {
        let suffix = ext.lowercased()
        func starts(_ bytes: [UInt8]) -> Bool {
            header.count >= bytes.count && Array(header.prefix(bytes.count)) == bytes
        }
        if starts(Array("Z3DS".utf8)) { return .compressed }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return .archive("zip") }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .archive("7z") }
        if starts(Array("Rar!".utf8) + [0x1A, 0x07]) { return .archive("rar") }
        if starts([0x1F, 0x8B]) { return .archive("gz") }
        // A CIA starts with its header's size (0x2020), type and version 0
        // and the certificate chain's size (0xA00).
        if starts([0x20, 0x20, 0, 0, 0, 0, 0, 0, 0x00, 0x0A, 0, 0]) { return .cia }
        switch suffix {
        case "cia": return .cia
        case "zcci", "zcxi", "z3dsx", "zcia", "z3ds": return .compressed
        case "zip", "7z", "rar", "gz", "tgz", "xz", "bz2", "tar": return .archive(suffix)
        default: return nil
        }
    }

    var explanation: String {
        switch self {
        // (A CIA and a compressed file are taken in since 11-11; these two
        // are for the ones that still cannot be: a CIA whose first content
        // is not there or not a program, a compressed file this build's core
        // cannot open or whose inside the core does not run compressed.)
        case .cia:
            return String(localized: "这个 CIA 安装包里没有能直接运行的程序（可能是更新或追加内容，或者文件不完整），导入不了。")
        case .compressed:
            return String(localized: "这个压缩文件打不开，或者里面不是能压缩着运行的游戏（能导入的是 .zcci / .zcxi / .z3dsx），导入不了。")
        case .archive("zip"):
            return String(localized: "这是 .zip 压缩包，游戏在它里面。先在「文件」App 里点一下它解压，再导入解压出来的 .3ds 或 .cci。")
        case .archive(let kind):
            return String(localized: "这是 .\(kind) 压缩包，游戏在它里面。先把里面的 .3ds 或 .cci 解压出来，再导入。")
        case .other(let suffix):
            let named = suffix.isEmpty ? String(localized: "（它没有后缀名）") : String(localized: "（.\(suffix)）")
            return String(localized: "认不出这个文件\(named)，它不是 3DS 游戏或 Homebrew。能导入的是 .3ds / .cci / .cxi / .app，以及 Homebrew 的 .3dsx / .elf。")
        }
    }
    /// For the log: the kind, no name.
    var kind: String {
        switch self {
        case .cia: return "cia"
        case .compressed: return "z3ds"
        case .archive(let kind): return "archive \(kind)"
        case .other(let suffix): return "other .\(suffix)"
        }
    }
}

enum Storage {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["FOLDARC_DATA_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldArc", isDirectory: true)
    }
    /// The folder the Files app shows as "FoldArc" (Info.plist
    /// `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`): the
    /// app's Documents folder. With FOLDARC_DATA_DIRECTORY set (tests), and in
    /// the Mac preview, a `Documents` folder inside `root` instead.
    static var filesFolder: URL {
        #if os(iOS)
        if ProcessInfo.processInfo.environment["FOLDARC_DATA_DIRECTORY"] == nil {
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        #endif
        return root.appendingPathComponent("Documents", isDirectory: true)
    }
    /// The core's save directory. Azahar keeps its user folder `Azahar/` in
    /// it: the emulated SD card (`sdmc`), NAND, the games' own save data,
    /// cheats and the shader cache. It is the Files folder, so the console's
    /// storage can be backed up, copied to a computer, or given homebrew.
    ///
    /// Builds up to the 14th round kept that folder in Application Support
    /// (`Azahar/saves/Azahar`). It is moved over once, as a whole: a rename
    /// inside the app's container, nothing copied or deleted (LibraryModel
    /// does it at launch; every core load checks again). If the Files folder
    /// already has an `Azahar` folder, an old one that still holds files is
    /// renamed into the Files folder as `Azahar（迁移前）` (numbered if that
    /// exists too), so nothing stays hidden. If a rename fails, the old
    /// place is used again this time.
    static func consoleStorage(root: URL = Storage.root, filesFolder folder: URL = Storage.filesFolder) -> URL {
        let fm = FileManager.default
        let legacy = root.appendingPathComponent("Azahar/saves", isDirectory: true)
        let legacyUser = legacy.appendingPathComponent("Azahar", isDirectory: true)
        let user = folder.appendingPathComponent("Azahar", isDirectory: true)
        if fm.fileExists(atPath: legacyUser.path) {
            var target = user
            if fm.fileExists(atPath: user.path) {
                // An empty leftover (only folders) is left alone.
                let hasFiles = fm.enumerator(at: legacyUser, includingPropertiesForKeys: [.isRegularFileKey])?
                    .contains { (($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile }) == true } ?? false
                if !hasFiles { target = legacyUser }
                else {
                    var n = 1
                    repeat {
                        target = folder.appendingPathComponent(n == 1 ? String(localized: "Azahar（迁移前）") : String(localized: "Azahar（迁移前 \(n)）"), isDirectory: true)
                        n += 1
                    } while fm.fileExists(atPath: target.path)
                }
            }
            if target != legacyUser {
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    try fm.moveItem(at: legacyUser, to: target)
                    NSLog("[storage] moved the console storage to %@", target.lastPathComponent)
                } catch {
                    NSLog("[storage] console storage stays in Application Support: %@", error.localizedDescription)
                    if target == user { return legacy }
                }
            }
        }
        // The shader cache is rebuilt by the core when it is missing: kept
        // out of device backups (a directory's flag covers its contents).
        var shaders = user.appendingPathComponent("shaders", isDirectory: true)
        if (try? fm.createDirectory(at: shaders, withIntermediateDirectories: true)) != nil {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? shaders.setResourceValues(values)
        }
        return folder
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}


/// 浓淡 (相机 › 机型): how much of a body's look is laid on the picture —
/// six steps, the fourth the look as it was made. Lighter, the body's
/// picture is mixed with the one before it (the date, the paper and the
/// black bars stay whole); stronger, the body's own amounts are taken
/// further. Each body keeps its own step; 原生 has none.
/// 两联 and 四连拍 (11-19): where each of the pictures goes on the one sheet
/// kept, and the part of each that is used. 两联: two upright half frames
/// side by side, a narrow dark gap between them (each the middle of its
/// picture). 四连拍: four whole pictures, two by two, on pale paper.
enum CameraSheetLayout {
    /// The cells, in the order the pictures were taken; rows are counted
    /// from the top.
    static func cells(count: Int, width: Double, height: Double) -> [CGRect] {
        if count == 2 {
            let gap = (height * 0.025).rounded()
            let w = (width - gap) / 2
            return [CGRect(x: 0, y: 0, width: w, height: height), CGRect(x: w + gap, y: 0, width: w, height: height)]
        }
        guard count == 4 else { return [CGRect(x: 0, y: 0, width: width, height: height)] }
        // Each cell 4:3; above and below the rows 6 % of a cell's height,
        // between them (and between the columns) 4 %.
        let h = height / 2.16, w = h * 4 / 3, gap = h * 0.04, top = h * 0.06
        let left = (width - 2 * w - gap) / 2
        return (0..<4).map { i in CGRect(x: left + Double(i % 2) * (w + gap), y: top + Double(i / 2) * (h + gap), width: w, height: h) }
    }
    /// The part of a picture used, in shares of it (x, y, width, height):
    /// 两联 takes the middle, as wide as its cell is for its height; 四连拍
    /// the whole.
    static func part(count: Int, width: Double, height: Double) -> CGRect {
        guard count == 2, let cell = cells(count: 2, width: width, height: height).first, cell.height > 0, width > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let share = min(1, cell.width / cell.height * height / width)
        return CGRect(x: (1 - share) / 2, y: 0, width: share, height: 1)
    }
    /// The sheet's own colour: nearly black between two half frames, pale
    /// paper round four pictures.
    static func ground(count: Int) -> (r: Double, g: Double, b: Double) {
        count == 2 ? (0.047, 0.043, 0.039) : (0.965, 0.957, 0.933)
    }
}

/// A colour grade: what a film or a sensor makes of each colour, as
/// numbers. Each channel's tone (what 0, ¼, ½, ¾ and 1 of it become: the
/// black's and the white's own colour, the tint of what lies between); how
/// strong colour is; and eight colours round the wheel — red, orange,
/// yellow, green, aqua, blue, purple, magenta — each turned towards a
/// neighbour (degrees), made stronger or weaker, lighter or darker. A
/// picture's colours are looked up in a cube made from it once.
struct CameraGrade: Hashable {
    var red: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var green: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var blue: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var saturation = 1.0
    var turn: [Double] = [0, 0, 0, 0, 0, 0, 0, 0]
    var strength: [Double] = [1, 1, 1, 1, 1, 1, 1, 1]
    var light: [Double] = [0, 0, 0, 0, 0, 0, 0, 0]

    /// Where the eight colours sit (degrees of hue).
    static let centres: [Double] = [0, 30, 60, 120, 180, 240, 280, 320]

    /// The grade taken `k` times as far from none.
    func stronger(_ k: Double) -> CameraGrade {
        guard k != 1 else { return self }
        var g = self
        func further(_ ys: [Double]) -> [Double] {
            ys.enumerated().map { i, y in min(1, max(0, Double(i) * 0.25 + (y - Double(i) * 0.25) * k)) }
        }
        g.red = further(red); g.green = further(green); g.blue = further(blue)
        g.saturation = max(0, 1 + (saturation - 1) * k)
        g.turn = turn.map { $0 * k }
        g.strength = strength.map { max(0, 1 + ($0 - 1) * k) }
        g.light = light.map { $0 * k }
        return g
    }

    /// `values` (one for each of the eight colours) at a hue between them.
    static func along(_ hue: Double, _ values: [Double]) -> Double {
        guard values.count == centres.count else { return values.first ?? 0 }
        let h = min(359.999, max(0, hue))
        for i in 0..<centres.count {
            let from = centres[i], to = i + 1 < centres.count ? centres[i + 1] : 360
            if h >= from, h < to {
                let next = values[i + 1 < centres.count ? i + 1 : 0]
                return values[i] + (next - values[i]) * (h - from) / (to - from)
            }
        }
        return values[0]
    }

    /// A smooth curve through (0, ¼, ½, ¾, 1) → `ys` that never turns back
    /// on itself (cubic pieces; the slope at a point the harmonic mean of
    /// the slopes on either side, flat where they disagree).
    static func curve(_ x: Double, _ ys: [Double]) -> Double {
        guard ys.count == 5 else { return x }
        let d = (0..<4).map { (ys[$0 + 1] - ys[$0]) / 0.25 }
        var m = [d[0], 0, 0, 0, d[3]]
        for i in 1...3 { m[i] = d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]) }
        let v = min(1, max(0, x))
        let i = min(3, Int(v * 4))
        let t = v * 4 - Double(i), t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * 0.25 * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * 0.25 * m[i + 1]
    }

    /// What the grade makes of a colour (all 0…1): its hue turned and its
    /// strength and lightness changed as its place on the wheel says (a
    /// grey has no place and is left alone), then each channel's tone.
    func made(_ red: Double, _ green: Double, _ blue: Double) -> (r: Double, g: Double, b: Double) {
        let r = min(1, max(0, red)), g = min(1, max(0, green)), b = min(1, max(0, blue))
        let high = max(r, g, b), low = min(r, g, b), c = high - low
        var hue = 0.0
        if c > 1e-6 {
            if high == r {
                hue = ((g - b) / c).truncatingRemainder(dividingBy: 6)
                if hue < 0 { hue += 6 }
            } else if high == g {
                hue = (b - r) / c + 2
            } else {
                hue = (r - g) / c + 4
            }
            hue *= 60
        }
        let y = 0.299 * r + 0.587 * g + 0.114 * b
        let cb = 0.564 * (b - y), cr = 0.713 * (r - y)
        let angle = Self.along(hue, turn) * Double.pi / 180
        let much = Self.along(hue, strength) * saturation
        let lighter = Self.along(hue, light)
        let cb2 = (cb * cos(angle) - cr * sin(angle)) * much
        let cr2 = (cb * sin(angle) + cr * cos(angle)) * much
        let y2 = y * (1 + lighter * min(1, c / 0.3))
        let r2 = y2 + cr2 / 0.713, b2 = y2 + cb2 / 0.564
        let g2 = (y2 - 0.299 * r2 - 0.114 * b2) / 0.587
        func kept(_ v: Double) -> Double { min(1, max(0, v)) }
        return (kept(Self.curve(r2, self.red)), kept(Self.curve(g2, self.green)), kept(Self.curve(b2, self.blue)))
    }

    /// The cube: `side`³ colours, red running fastest, then green, then
    /// blue; each r, g, b and 1.
    func cube(side: Int) -> [Float] {
        let n = max(2, side)
        var out: [Float] = []
        out.reserveCapacity(n * n * n * 4)
        let step = 1 / Double(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let c = made(Double(r) * step, Double(g) * step, Double(b) * step)
                    out.append(Float(c.r)); out.append(Float(c.g)); out.append(Float(c.b)); out.append(1)
                }
            }
        }
        return out
    }
}

/// The shape of the picture on the cover's camera: the whole 4:3 the
/// camera makes, or its middle cut square, wide or upright. What is cut is
/// the same on both sides, so the part kept is the same counted from the
/// top or from the bottom.
enum CameraAspect: String, CaseIterable, Identifiable, Codable, Sendable {
    case full, square, wide, tall
    static let defaultsKey = "FoldArc.camera.coverAspect"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return "4:3"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .tall: return "3:4"
        }
    }
    /// The part of a 640 × 480 picture kept.
    var crop: CGRect {
        switch self {
        case .full: return CGRect(x: 0, y: 0, width: 640, height: 480)
        case .square: return CGRect(x: 80, y: 0, width: 480, height: 480)
        case .wide: return CGRect(x: 0, y: 60, width: 640, height: 360)
        case .tall: return CGRect(x: 140, y: 0, width: 360, height: 480)
        }
    }
    /// Width over height.
    var ratio: Double { Double(crop.width / crop.height) }
    var next: CameraAspect {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

enum CameraBodyStrength {
    static let values: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5]
    /// Steps from the look as made (0).
    static let range = -3...2
    static let defaultsKey = "FoldArc.camera.bodyStrength"
    static func value(_ step: Int) -> Double { values[min(values.count - 1, max(0, step - range.lowerBound))] }
    /// As it is shown: a share of the look, 100% as made.
    static func title(_ step: Int) -> String { "\(Int((value(step) * 100).rounded()))%" }
    /// `step` moved by `delta`, kept within the steps there are.
    static func moved(_ step: Int, by delta: Int) -> Int { min(range.upperBound, max(range.lowerBound, step + delta)) }
    /// What was kept, made sound: only the bodies in `names`, only steps
    /// there are, none at 0 (a body not in it is at 0).
    static func kept(_ stored: [String: Any]?, names: Set<String>) -> [String: Int] {
        var out: [String: Int] = [:]
        for (name, value) in stored ?? [:] {
            guard names.contains(name), let step = value as? Int, range.contains(step), step != 0 else { continue }
            out[name] = step
        }
        return out
    }
}

/// The camera's file names (round 25), the way cameras name them on a
/// memory card (DCF): folders `100_ZERO`, `101_ZERO`… under DCIM, pictures
/// `ZERO0001.JPG`… in them (they were
/// `100FOLDA` / `FARC0001.JPG`; `renamed` gives the new name of an old one,
/// CameraRoll.renameOldPictures moves them over once, numbers kept). Other
/// cameras' folders and files are left as they are. Plain logic, so the
/// checks can try it.
enum CameraFileNames {
    static let folderSuffix = "_ZERO"
    static let prefix = "ZERO"
    static let perFolder = 9999
    /// Before 11-07.
    static let oldFolderSuffix = "FOLDA"
    static let oldPrefix = "FARC"

    /// The new name of an old folder ("100FOLDA" → "100_ZERO"), else nil.
    static func renamed(folder name: String) -> String? {
        guard name.hasSuffix(oldFolderSuffix), let number = folderNumber(name) else { return nil }
        return folder(number)
    }
    /// The new name of an old picture or video ("FARC0042.JPG" → "ZERO0042.JPG"), else nil.
    static func renamed(file name: String) -> String? {
        let upper = name.uppercased()
        guard upper.count == 12, upper.hasPrefix(oldPrefix), upper.hasSuffix(".JPG") || upper.hasSuffix(".MP4") else { return nil }
        let digits = upper.dropFirst(oldPrefix.count).prefix(4)
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits), number >= 1 else { return nil }
        return file(number, ext: String(upper.suffix(3)))
    }

    /// The number of a DCF folder ("100" to "999" and five capitals, digits
    /// or underscores), else nil.
    static func folderNumber(_ name: String) -> Int? {
        guard name.count == 8, let number = Int(name.prefix(3)), (100...999).contains(number) else { return nil }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard name.dropFirst(3).allSatisfy({ allowed.contains($0) }) else { return nil }
        return number
    }
    /// The number of one of Zero's pictures ("ZERO0042.JPG" → 42) or
    /// (11-06, 录像) videos ("ZERO0043.MP4" → 43): one row of numbers.
    static func fileNumber(_ name: String) -> Int? {
        let upper = name.uppercased()
        guard upper.count == 12, upper.hasPrefix(prefix), upper.hasSuffix(".JPG") || upper.hasSuffix(".MP4") else { return nil }
        let digits = upper.dropFirst(prefix.count).prefix(4)
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits), number >= 1 else { return nil }
        return number
    }
    static func file(_ number: Int, ext: String = "JPG") -> String { prefix + String(format: "%04d", number) + "." + ext }
    static func folder(_ number: Int) -> String { String(number) + folderSuffix }

    /// Where the next picture goes, from the folders under DCIM and the files
    /// in one of them: the next number in FoldArc's newest folder, or a new
    /// folder once that one is full. Nil when all numbers are used.
    static func next(folders: [String], files: (String) -> [String], ext: String = "JPG") -> (folder: String, file: String)? {
        let ours = folders.filter { $0.hasSuffix(folderSuffix) }.compactMap { folderNumber($0) }.sorted()
        guard let newest = ours.last else { return (folder(100), file(1, ext: ext)) }
        let top = files(folder(newest)).compactMap { fileNumber($0) }.max() ?? 0
        if top < perFolder { return (folder(newest), file(top + 1, ext: ext)) }
        guard newest < 999 else { return nil }
        return (folder(newest + 1), file(1, ext: ext))
    }

    /// Pictures that can still be taken. 11-07: what the iPhone really has room for — its free
    /// space (for important use, as the system reports it), 200 MB kept
    /// free for everything else, over the size of a picture on the card (the
    /// average of the newest ones; 120 KB until there are any). No longer
    /// capped at a handheld's 3000; only when the free space is unknown is
    /// that count what it says.
    static func remaining(count: Int, freeBytes: Int64?, pictureBytes: Int64? = nil, limit: Int = 3000) -> Int {
        guard let freeBytes else { return max(0, limit - count) }
        let each = max(20_000, pictureBytes ?? 120_000)
        return Int(max(0, freeBytes - 200_000_000) / each)
    }
    /// The count as the chip prints it: as it is under ten thousand, then in
    /// 万 to one place ("41.5 万").
    /// The app's interface language is Chinese (the catalog's zh-Hans is in
    /// use): 万 then, thousands otherwise. (The unit checks say which.)
    static var chineseUI: Bool { UILanguage.isChinese }
    static func remainingText(_ count: Int, chinese: Bool = chineseUI) -> String {
        guard count >= 10_000 else { return "\(count)" }
        // 11-07 (English UI): thousands outside Chinese ("415k"), 万 in it.
        if !chinese {
            // (on the device: "3125.4k" — millions as M.)
            if count >= 1_000_000 {
                let m = (Double(count) / 1_000_000 * 10).rounded(.down) / 10
                return m == m.rounded() ? "\(Int(m))M" : String(format: "%.1fM", m)
            }
            let k = (Double(count) / 1000 * 10).rounded(.down) / 10
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", k)
        }
        let wan = (Double(count) / 10_000 * 10).rounded(.down) / 10
        return wan == wan.rounded() ? String(localized: "\(Int(wan)) 万") : String(format: String(localized: "%.1f 万"), wan)
    }
}

/// 11-07 (the English UI): the language the interface is in, for the
/// dates it formats (the console's clock, the camera's and the notes' dates
/// were fixed to Chinese while the app was Chinese only; Text(_:format:)
/// would otherwise take the Simulator's own locale).
/// A console part's or a data kind's name as the interface shows it. The
/// names themselves ("A 键", "十字键", "即时存档") stay as they are in the
/// code — other code matches on them, the sync folders carry them — and
/// the catalog has an English line for each (Localizable.xcstrings, the
/// hand-kept keys at its end).
func shownName(_ identifier: String) -> String { NSLocalizedString(identifier, comment: "") }

enum UILanguage {
    static let code: String = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
    /// (A bare executable — the unit checks, the renderer — has no
    /// localizations at all: Chinese, as the keys are.)
    static let isChinese: Bool = code.hasPrefix("zh") || Bundle.main.localizations.isEmpty
    /// (en_GB: a 24-hour clock, as the handheld's is, and "7 Nov".)
    static let locale: Locale = Locale(identifier: isChinese ? "zh_Hans_CN" : "en_GB")
    /// Between two sentences joined in code: nothing in Chinese, a space in English.
    static let gap: String = isChinese ? "" : " "
}

enum ROMImporter {
    /// The format of a file from its container marker (`header`: its first
    /// 0x200 bytes), the extension's format first. Does not verify full
    /// integrity or playability. 11-07: the extension
    /// is only a hint — a file whose name lost or changed its suffix, or a
    /// .3ds that is really a .cxi, is taken for what its bytes say (the core
    /// goes by content too); a file that is no 3DS software says what it is
    /// (ForeignFile), not only which suffixes are taken.
    @discardableResult
    static func validateHeader(_ header: Data, extension ext: String) throws -> ROMFormat {
        let hinted = ROMFormat.candidates(forExtension: ext)
        for format in hinted where hasMagic(header, of: format) { return format }
        for format in ROMFormat.allCases where !hinted.contains(format) && hasMagic(header, of: format, strict: true) {
            return format
        }
        if let foreign = ForeignFile.identify(header: header, extension: ext) { throw ImportFailure.notSoftware(foreign) }
        throw hinted.isEmpty ? ImportFailure.notSoftware(.other(ext.lowercased())) : ImportFailure.invalidHeader
    }
    private static func bytes(_ data: Data, _ range: Range<Int>) -> [UInt8]? {
        guard data.count >= range.upperBound else { return nil }
        return Array(data[data.startIndex + range.lowerBound ..< data.startIndex + range.upperBound])
    }
    /// `strict` (a file not named .elf): an ELF only when it is a 32-bit
    /// little-endian ARM one, as 3DS homebrew is, not any program's.
    static func hasMagic(_ header: Data, of format: ROMFormat, strict: Bool = false) -> Bool {
        switch format {
        case .cartridge: return bytes(header, 0x100..<0x104) == Array("NCSD".utf8)
        case .executable: return bytes(header, 0x100..<0x104) == Array("NCCH".utf8)
        case .homebrew: return bytes(header, 0..<4) == Array("3DSX".utf8)
        case .elf:
            guard bytes(header, 0..<4) == [0x7F, 0x45, 0x4C, 0x46] else { return false }
            // EI_CLASS 1 (32-bit), EI_DATA 1 (little-endian), e_machine 40 (ARM).
            return !strict || (bytes(header, 4..<6) == [1, 1] && bytes(header, 0x12..<0x14) == [0x28, 0])
        }
    }

    /// NCCH header flag byte 7 (offset 0x18F): bit 2 = NoCrypto, bit 0 =
    /// FixedCryptoKey (the all-zero developer key, which the core handles).
    /// Anything else needs console keys FoldArc does not have or ask for.
    static func ncchIsUsable(flags: UInt8) -> Bool {
        flags & 0x04 != 0 || flags & 0x01 != 0
    }

    /// Reads the first NCCH header of a cartridge image or executable and
    /// throws `.encrypted` when it would need keys. Homebrew is never
    /// encrypted. `read` must return `count` bytes at `offset` (fewer at EOF).
    static func checkEncryption(format: ROMFormat, header: Data, read: (UInt64, Int) throws -> Data) throws {
        switch format {
        case .homebrew, .elf: return
        case .executable:
            guard let flags = bytes(header, 0x18F..<0x190)?.first else { throw ImportFailure.invalidHeader }
            if !ncchIsUsable(flags: flags) { throw ImportFailure.encrypted }
        case .cartridge:
            // Partition table at 0x120: 8 × (offset, size) in 0x200-byte media units.
            guard let entry = bytes(header, 0x120..<0x128) else { throw ImportFailure.invalidHeader }
            let offset = UInt64(entry[0]) | UInt64(entry[1]) << 8 | UInt64(entry[2]) << 16 | UInt64(entry[3]) << 24
            let size = UInt64(entry[4]) | UInt64(entry[5]) << 8 | UInt64(entry[6]) << 16 | UInt64(entry[7]) << 24
            guard offset > 0, size > 0 else { throw ImportFailure.invalidHeader }
            let ncch = try read(offset * 0x200, 0x200)
            guard hasMagic(ncch, of: .executable), let flags = bytes(ncch, 0x18F..<0x190)?.first else { throw ImportFailure.invalidHeader }
            if !ncchIsUsable(flags: flags) { throw ImportFailure.encrypted }
        }
    }

    /// Title, publisher and icon for a record imported before FoldArc read
    /// SMDH. Reads only the managed copy; a file without SMDH keeps its
    /// file-name title and is marked as looked at.
    static func refreshMetadata(_ record: GameRecord, root: URL) -> GameRecord {
        let copy = root.appendingPathComponent("ROMs").appendingPathComponent(record.fileName)
        let smdh: SMDH? = GameFile.reading(copy) { header, read in
            try SMDH.locate(format: record.resolvedFormat, header: header, read: read)
        }
        let title = smdh?.preferredTitle
        return GameRecord(id: record.id, title: title?.short ?? record.title, fileName: record.fileName,
                          byteCount: record.byteCount, importedAt: record.importedAt, format: record.format,
                          publisher: title.flatMap { $0.publisher.isEmpty ? nil : $0.publisher },
                          iconFileName: smdh.flatMap { saveIcon($0, id: record.id, root: root) } ?? record.iconFileName,
                          metadataVersion: SMDH.metadataVersion)
    }

    /// Writes the large icon as `Icons/<id>.png`; nil if it could not be written.
    static func saveIcon(_ smdh: SMDH, id: String, root: URL) -> String? {
        guard let png = smdh.largeIconPNG() else { return nil }
        let folder = root.appendingPathComponent("Icons", isDirectory: true)
        let name = id + ".png"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch { return nil }
    }

    /// `copy` inside a coordinated read: a file in iCloud Drive or another
    /// file provider is brought down first, and nobody writes it meanwhile.
    static func copyCoordinated(_ source: URL, into root: URL, progress: ((Double) -> Void)? = nil) throws -> GameRecord {
        var coordinationError: NSError?
        var result: Result<GameRecord, Error> = .failure(ImportFailure.missingFile)
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { url in
            result = Result { try copy(url, into: root, progress: progress) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Imports leave `ROMs/<uuid>.partial` while they copy and remove it when
    /// they end, however they end; one cut short by the app being ended
    /// leaves it behind. No import runs before the library is loaded, so any
    /// found then is such a leftover. Only these files are touched.
    @discardableResult
    static func removeUnfinishedImports(root: URL) -> Int {
        let folder = root.appendingPathComponent("ROMs", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var removed = 0
        for name in names where name.hasSuffix(".partial") {
            if (try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))) != nil { removed += 1 }
        }
        return removed
    }

    /// Free space on the volume that holds `folder`, for important use (the
    /// system counts what it can purge for it); nil when unknown. DEBUG
    /// builds take `--foldarc-free-space=<bytes>` instead, to act out a full
    /// device.
    static func availableCapacity(at folder: URL) -> Int64? {
        #if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-free-space=") }) {
            return Int64(arg.dropFirst("--foldarc-free-space=".count))
        }
        #endif
        #if os(iOS)
        return (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        #else
        return (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
        #endif
    }

    /// A write that failed because the volume is full.
    static func isOutOfSpace(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError { return true }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }

    /// A compressed file (Z3DS) read as what is inside it. The app gives the
    /// way (the core's own reader, AzaharSession.swift); without the core
    /// there is none, and a compressed file is turned away.
    static var openCompressed: ((URL) -> CompressedSource?)?

    /// Copies a checked file into `ROMs/<sha256>.<ext>` and returns its
    /// record. The copy goes through `<uuid>.partial`, removed whatever
    /// happens; a file larger than the free space is refused before copying.
    /// `progress` gets 0…1 at most once per percent; `freeSpace` is the free
    /// space check and `chunkSize` the read size (tests replace them).
    /// A compressed file (Z3DS) is checked through what is inside it and
    /// kept as it is, compressed (the core runs it so). Of a CIA package the
    /// first content — the program — is what is kept, as a .cxi.
    static func copy(_ source: URL, into root: URL, progress: ((Double) -> Void)? = nil,
                     freeSpace: (URL) -> Int64? = ROMImporter.availableCapacity(at:),
                     chunkSize: Int = 1024 * 1024) throws -> GameRecord {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw ImportFailure.missingFile }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        func raw(_ offset: UInt64, _ count: Int) throws -> Data {
            try input.seek(toOffset: offset)
            return try input.read(upToCount: count) ?? Data()
        }
        let first = try raw(0, 0x200)
        let fileSize = try input.seekToEnd()
        // What is checked (`read`: the software's own bytes), what is copied
        // (`range` of the file), and the copy's extension.
        var read: (UInt64, Int) throws -> Data = raw
        var range: (offset: UInt64, length: UInt64) = (0, fileSize)
        var compressed: CompressedSource?
        defer { compressed?.close() }
        var hint = source.pathExtension
        var kind = GameFile.Kind.plain
        if GameFile.isCompressed(first) {
            guard let opened = openCompressed?(source) else { throw ImportFailure.notSoftware(.compressed) }
            compressed = opened
            read = { offset, count in opened.read(offset: offset, count: count) }
            kind = .compressed
            hint = GameFile.plainExtension(forCompressed: hint)
        } else if CIAPackage.looksLikeOne(first) || (hint.lowercased() == "cia" && (try? validateHeader(first, extension: "")) == nil) {
            // (A file that only carries the suffix and is a program by its
            // bytes is taken as that program, like any misnamed file.)
            let content = try CIAPackage.mainContent(fileSize: fileSize, read: raw)
            range = content
            read = { offset, count in
                guard offset < content.length else { return Data() }
                return try raw(content.offset + offset, Int(min(UInt64(count), content.length - offset)))
            }
            kind = .cia
            hint = "cxi"
        }
        let header = try (kind == .plain ? first : read(0, 0x200))
        let format: ROMFormat
        do { format = try validateHeader(header, extension: hint) } catch {
            // (What is inside is not software: said as the file it came in.)
            if kind == .cia { throw ImportFailure.notSoftware(.cia) }
            if kind == .compressed { throw ImportFailure.notSoftware(.compressed) }
            throw error
        }
        if kind == .cia, format != .executable { throw ImportFailure.notSoftware(.cia) }
        var fileExtension = format.fileExtension
        if kind == .compressed {
            guard let name = format.compressedExtension else { throw ImportFailure.notSoftware(.compressed) }
            fileExtension = name
        }
        try checkEncryption(format: format, header: header, read: read)
        // HOME Menu title and icon; a file without them still imports.
        let smdh = (try? SMDH.locate(format: format, header: header, read: read)) ?? nil
        let size = Int64(range.length)
        try input.seek(toOffset: range.offset)
        let folder = root.appendingPathComponent("ROMs", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let free = freeSpace(folder), free < size { throw ImportFailure.noSpace(size) }
        let temporary = folder.appendingPathComponent(UUID().uuidString + ".partial")
        guard fm.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? fm.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        var hash = SHA256()
        var total: Int64 = 0
        var reported = -1
        do {
            while total < size, let chunk = try input.read(upToCount: Int(min(Int64(chunkSize), size - total))), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
                try output.write(contentsOf: chunk)
                total += Int64(chunk.count)
                if let progress, size > 0 {
                    let percent = Int(total * 100 / size)
                    if percent != reported { reported = percent; progress(Double(min(total, size)) / Double(size)) }
                }
            }
            try output.synchronize()
            try output.close()
        } catch let error where isOutOfSpace(error) {
            throw ImportFailure.noSpace(size)
        }
        // (A package cut short: its program is not all there.)
        if total < size { throw ImportFailure.invalidHeader }
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let fileName = id + "." + fileExtension
        let destination = folder.appendingPathComponent(fileName)
        if !fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: temporary, to: destination)
        }
        let title = smdh?.preferredTitle
        return GameRecord(id: id, title: title?.short ?? source.deletingPathExtension().lastPathComponent,
                          fileName: fileName, byteCount: total, importedAt: Date(), format: format,
                          publisher: title.flatMap { $0.publisher.isEmpty ? nil : $0.publisher },
                          iconFileName: smdh.flatMap { saveIcon($0, id: id, root: root) },
                          metadataVersion: SMDH.metadataVersion)
    }
}

/// What is inside a compressed game file, decompressed (the core's reader
/// behind it in the app; the unit checks have one of their own).
protocol CompressedSource: AnyObject {
    var size: UInt64 { get }
    /// `count` bytes at `offset` (fewer at the end).
    func read(offset: UInt64, count: Int) -> Data
    func close()
}

/// A game file as the library keeps or meets it: plain, compressed (Z3DS:
/// "Z3DS" first, then what the core's reader gives), or a CIA package.
enum GameFile {
    enum Kind { case plain, compressed, cia }
    static func isCompressed(_ header: Data) -> Bool { header.prefix(4).elementsEqual(Array("Z3DS".utf8)) }
    /// ".zcci" is a ".cci" inside, and so on (the hint for what is inside).
    static func plainExtension(forCompressed ext: String) -> String {
        switch ext.lowercased() {
        case "zcci": return "cci"
        case "zcxi": return "cxi"
        case "z3dsx": return "3dsx"
        default: return ext
        }
    }
    /// The software's own bytes of a file of the library, for whoever reads
    /// its header, title or icon: `body` gets the first 0x200 bytes and the
    /// way to read on. nil: the file cannot be opened (or is compressed and
    /// there is no reader).
    static func reading<Result>(_ url: URL, _ body: (Data, (UInt64, Int) throws -> Data) throws -> Result?) -> Result? {
        guard let input = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? input.close() }
        guard let first = try? input.read(upToCount: 0x200) else { return nil }
        if isCompressed(first) {
            guard let opened = ROMImporter.openCompressed?(url) else { return nil }
            defer { opened.close() }
            return (try? body(opened.read(offset: 0, count: 0x200)) { offset, count in opened.read(offset: offset, count: count) }) ?? nil
        }
        return (try? body(first) { offset, count in
            try input.seek(toOffset: offset)
            return try input.read(upToCount: count) ?? Data()
        }) ?? nil
    }
}

/// A CIA package (an installer's file): a header, certificates, a ticket,
/// the title's list of contents (TMD), then the contents one after another,
/// each part starting on a multiple of 0x40. The first content is the
/// program (an NCCH), which is what the library keeps. A content the list
/// marks encrypted is turned away like any encrypted file.
enum CIAPackage {
    static let headerSize: UInt64 = 0x2020
    /// The header's own size, type and version 0, the certificates' size.
    static func looksLikeOne(_ header: Data) -> Bool {
        header.count >= 12 && Array(header.prefix(12)) == [0x20, 0x20, 0, 0, 0, 0, 0, 0, 0x00, 0x0A, 0, 0]
    }
    static func align(_ value: UInt64) -> UInt64 { (value + 0x3F) & ~UInt64(0x3F) }
    /// Signature sizes by type (the list of contents begins with one).
    static func signatureSize(_ type: UInt32) -> UInt64? {
        switch type {
        case 0x10000, 0x10003: return 0x200
        case 0x10001, 0x10004: return 0x100
        case 0x10002, 0x10005: return 0x3C
        default: return nil
        }
    }
    /// Where the first content is in the file, and how long.
    static func mainContent(fileSize: UInt64, read: (UInt64, Int) throws -> Data) throws -> (offset: UInt64, length: UInt64) {
        func le32(_ data: Data, _ at: Int) -> UInt64 {
            (0..<4).reduce(UInt64(0)) { $0 | UInt64(data[data.startIndex + at + $1]) << (8 * UInt64($1)) }
        }
        func be(_ data: Data, _ at: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(UInt64(0)) { $0 << 8 | UInt64(data[data.startIndex + at + $1]) }
        }
        let head = try read(0, 0x20)
        guard head.count >= 0x20, le32(head, 0) == headerSize else { throw ImportFailure.notSoftware(.cia) }
        let certificates = le32(head, 8), ticket = le32(head, 12), list = le32(head, 16)
        let listOffset = align(align(align(headerSize) + certificates) + ticket)
        let contents = align(listOffset + list)
        guard list >= 4, list <= 0x10_0000, contents < fileSize else { throw ImportFailure.notSoftware(.cia) }
        // The first content must be in the package (bit 7 of the first byte of the header's table).
        let present = try read(0x20, 1)
        guard let bits = present.first, bits & 0x80 != 0 else { throw ImportFailure.notSoftware(.cia) }
        let tmd = try read(listOffset, Int(list))
        guard tmd.count == Int(list), let signature = signatureSize(UInt32(be(tmd, 0, 4))) else { throw ImportFailure.notSoftware(.cia) }
        // The list's body starts on a multiple of 0x40 after the signature;
        // it is 0x9C4 long, the number of contents at 0x9E in it, and the
        // contents' entries (0x30 each: id, index, type, size, hash) follow.
        let body = Int(align(signature + 4))
        guard tmd.count >= body + 0x9C4 else { throw ImportFailure.notSoftware(.cia) }
        // The title's kind is the upper half of its number (at 0x4C): a
        // program or a demo is taken; an update or added content has
        // nothing here that runs by itself.
        let category = be(tmd, body + 0x4C, 8) >> 32
        guard category == 0x0004_0000 || category == 0x0004_0002 else { throw ImportFailure.notSoftware(.cia) }
        let count = Int(be(tmd, body + 0x9E, 2))
        guard count >= 1, tmd.count >= body + 0x9C4 + count * 0x30 else { throw ImportFailure.notSoftware(.cia) }
        for entry in 0..<count {
            let at = body + 0x9C4 + entry * 0x30
            guard be(tmd, at + 4, 2) == 0 else { continue }
            if be(tmd, at + 6, 2) & 1 != 0 { throw ImportFailure.encrypted }
            // (The contents are in the list's order; the one with index 0 is
            // the first of the package only when it is the first entry.)
            guard entry == 0 else { throw ImportFailure.notSoftware(.cia) }
            let length = be(tmd, at + 8, 8)
            // (`contents` is below `fileSize`, checked above: the subtraction
            // cannot go under, and a made-up length cannot run the sum over.)
            guard length >= 0x200, length <= fileSize - contents else { throw ImportFailure.invalidHeader }
            return (contents, length)
        }
        throw ImportFailure.notSoftware(.cia)
    }
}

/// System Menu Data Header: the title strings and icons a 3DS title carries
/// for the HOME Menu (layout per 3DBrew "SMDH"). FoldArc reads it from a
/// 3DSX's extended header or from the "icon" file in the ExeFS of an
/// unencrypted NCCH, so the library can show the real title and icon.
struct SMDH: Equatable, Sendable {
    struct Title: Equatable, Sendable {
        var short: String
        var long: String
        var publisher: String
    }
    /// Bumped when the metadata pass reads more; records with an older value
    /// are refreshed once.
    static let metadataVersion = 1
    static let size = 0x36C0
    /// 16 entries in HOME Menu language order (0 Japanese, 1 English, …,
    /// 6 Simplified Chinese, 7 Korean, …, 11 Traditional Chinese).
    let titles: [Title]
    /// Large icon: 48 × 48 RGBA8, row-major, top row first.
    let largeIcon: [UInt8]

    init?(data: Data) {
        guard data.count >= Self.size else { return nil }
        let base = data.startIndex
        guard Array(data[base ..< base + 4]) == Array("SMDH".utf8) else { return nil }
        func text(_ offset: Int, _ length: Int) -> String {
            var units: [UInt16] = []
            var i = offset
            while i + 1 < offset + length {
                let unit = UInt16(data[base + i]) | (UInt16(data[base + i + 1]) << 8)
                if unit == 0 { break }
                units.append(unit)
                i += 2
            }
            return String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        titles = (0..<16).map { n in
            let o = 0x8 + n * 0x200
            return Title(short: text(o, 0x80), long: text(o + 0x80, 0x100), publisher: text(o + 0x180, 0x80))
        }
        // RGB565 in 8 × 8 tiles (left to right, top to bottom), Morton
        // (Z) order inside each tile, like the GPU's tiled textures.
        var rgba = [UInt8](repeating: 0, count: 48 * 48 * 4)
        let icon = base + 0x24C0
        for tile in 0..<36 {
            let tileX = (tile % 6) * 8, tileY = (tile / 6) * 8
            for i in 0..<64 {
                let x = (i & 1) | ((i >> 1) & 2) | ((i >> 2) & 4)
                let y = ((i >> 1) & 1) | ((i >> 2) & 2) | ((i >> 3) & 4)
                let o = icon + (tile * 64 + i) * 2
                let pixel = UInt16(data[o]) | (UInt16(data[o + 1]) << 8)
                let r = UInt8((pixel >> 11) & 0x1F), g = UInt8((pixel >> 5) & 0x3F), b = UInt8(pixel & 0x1F)
                let d = ((tileY + y) * 48 + tileX + x) * 4
                rgba[d] = (r << 3) | (r >> 2)
                rgba[d + 1] = (g << 2) | (g >> 4)
                rgba[d + 2] = (b << 3) | (b >> 2)
                rgba[d + 3] = 255
            }
        }
        largeIcon = rgba
    }

    /// The entry a Chinese-speaking player expects first: Simplified Chinese,
    /// Traditional Chinese, English, Japanese, then any non-empty one.
    var preferredTitle: Title? {
        for index in [6, 11, 1, 0] where !titles[index].short.isEmpty { return titles[index] }
        return titles.first { !$0.short.isEmpty }
    }

    /// The large icon as a 48 × 48 image.
    func largeIconImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(largeIcon) as CFData) else { return nil }
        return CGImage(width: 48, height: 48, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 48 * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The large icon as PNG data.
    func largeIconPNG() -> Data? {
        guard let image = largeIconImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func le16(_ data: Data, _ offset: Int) -> UInt64? {
        guard data.count >= offset + 2 else { return nil }
        let b = data.startIndex + offset
        return UInt64(data[b]) | (UInt64(data[b + 1]) << 8)
    }
    private static func le32(_ data: Data, _ offset: Int) -> UInt64? {
        guard data.count >= offset + 4 else { return nil }
        let b = data.startIndex + offset
        return UInt64(data[b]) | (UInt64(data[b + 1]) << 8) | (UInt64(data[b + 2]) << 16) | (UInt64(data[b + 3]) << 24)
    }

    /// The SMDH of a game file (managed copy or test file), if it has one.
    static func read(contentsOf url: URL) -> SMDH? {
        GameFile.reading(url) { header, read in
            let format = try ROMImporter.validateHeader(header, extension: GameFile.plainExtension(forCompressed: url.pathExtension))
            return try locate(format: format, header: header, read: read)
        }
    }

    /// Finds the SMDH of a validated import. `header` is the file's first
    /// 0x200 bytes; `read` returns `count` bytes at `offset` (fewer at EOF).
    /// nil when there is none: ELF, a 3DSX without the extended header, or an
    /// NCCH whose ExeFS is encrypted (the fixed key still means AES-CTR) or
    /// has no icon. The library then keeps the file name and a generic icon.
    static func locate(format: ROMFormat, header: Data, read: (UInt64, Int) throws -> Data) throws -> SMDH? {
        switch format {
        case .elf:
            return nil
        case .homebrew:
            // 0x20-byte header; with the extended header (size ≥ 0x2C) come
            // SMDH offset and size at 0x20 / 0x24.
            guard let headerSize = le16(header, 4), headerSize >= 0x2C,
                  let offset = le32(header, 0x20), let size = le32(header, 0x24), size >= UInt64(Self.size) else { return nil }
            return SMDH(data: try read(offset, Self.size))
        case .executable:
            return try fromNCCH(at: 0, header: header, read: read)
        case .cartridge:
            // Partition 0's offset, in 0x200-byte media units, at 0x120.
            guard let partition = le32(header, 0x120), partition > 0 else { return nil }
            let base = partition * 0x200
            return try fromNCCH(at: base, header: try read(base, 0x200), read: read)
        }
    }

    private static func fromNCCH(at base: UInt64, header: Data, read: (UInt64, Int) throws -> Data) throws -> SMDH? {
        guard header.count >= 0x1A8, header[header.startIndex + 0x18F] & 0x04 != 0,
              let exefs = le32(header, 0x1A0), exefs > 0 else { return nil }
        let exefsBase = base + exefs * 0x200
        let table = try read(exefsBase, 0x200)
        guard table.count >= 0xA0 else { return nil }
        // Ten 16-byte entries: name (8, zero-padded), offset, size; file data
        // starts after the 0x200-byte header.
        for entry in 0..<10 {
            let o = entry * 16
            let name = table[(table.startIndex + o) ..< (table.startIndex + o + 8)].prefix { $0 != 0 }
            guard Array(name) == Array("icon".utf8),
                  let offset = le32(table, o + 8), let size = le32(table, o + 12), size >= UInt64(Self.size) else { continue }
            return SMDH(data: try read(exefsBase + 0x200 + offset, Self.size))
        }
        return nil
    }
}

struct Point: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var clamped: Point { Point(x: min(1, max(0, x)), y: min(1, max(0, y))) }
}

enum PadButton: String, CaseIterable, Sendable { case up, down, left, right, a, b, x, y, l, r, zl, zr, start, select }

/// 按键点屏: for software played on the touch screen alone.
/// With it on (HOME's row, per software, off unless turned on), A B X Y tap
/// the touch screen where a finger last touched it in that software, the
/// middle until then. Kept by the software's own name (its library copy's).
enum KeyTaps {
    static let keys: Set<PadButton> = [.a, .b, .x, .y]
    static let onKey = "FoldArc.keyTaps"
    static let pointsKey = "FoldArc.keyTaps.points"
    static let middle = Point(x: 0.5, y: 0.5)
    static func isOn(_ game: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let game else { return false }
        return (defaults.stringArray(forKey: onKey) ?? []).contains(game)
    }
    static func set(_ on: Bool, for game: String?, defaults: UserDefaults = .standard) {
        guard let game else { return }
        var list = (defaults.stringArray(forKey: onKey) ?? []).filter { $0 != game }
        if on { list.append(game) }
        defaults.set(list, forKey: onKey)
    }
    /// Where the keys tap (0…1 of the touch screen's picture).
    static func point(for game: String?, defaults: UserDefaults = .standard) -> Point {
        guard let game, let text = (defaults.dictionary(forKey: pointsKey) as? [String: String])?[game] else { return middle }
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return middle }
        return Point(x: parts[0], y: parts[1]).clamped
    }
    static func remember(_ point: Point, for game: String?, defaults: UserDefaults = .standard) {
        guard let game else { return }
        var all = (defaults.dictionary(forKey: pointsKey) as? [String: String]) ?? [:]
        let p = point.clamped
        all[game] = String(format: "%.4f,%.4f", p.x, p.y)
        defaults.set(all, forKey: pointsKey)
    }
    /// The software that has been told of 按键点屏 once (KeyTapsHint).
    static let hintedKey = "FoldArc.keyTaps.hinted"
    static func wasHinted(_ game: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let game else { return true }
        return (defaults.stringArray(forKey: hintedKey) ?? []).contains(game)
    }
    static func setHinted(_ game: String?, defaults: UserDefaults = .standard) {
        guard let game, !wasHinted(game, defaults: defaults) else { return }
        defaults.set((defaults.stringArray(forKey: hintedKey) ?? []) + [game], forKey: hintedKey)
    }
}

/// When to say that 按键点屏 exists: software played on the touch screen alone
/// does nothing when A B X Y are pressed, and the switch is out of sight in
/// HOME's row. The sign taken for it: the touch screen touched three times or
/// more, then one of A B X Y pressed three times within two and a half
/// seconds. Software played with its keys from the start never shows it
/// (its first keys come before three touches, and each run of presses asks
/// for three new touches before it).
struct KeyTapsHint {
    static let touchesNeeded = 3
    static let pressesNeeded = 3
    static let within = 2.5
    private var touches = 0
    private var runCounts = false
    private var presses: [Date] = []
    /// A finger came down on the touch screen.
    mutating func touched() { touches += 1 }
    /// One of A B X Y went down with 按键点屏 off: true when the hint is due.
    mutating func pressed(at now: Date = Date()) -> Bool {
        presses = presses.filter { now.timeIntervalSince($0) <= Self.within }
        if presses.isEmpty {
            // A new run of presses: it counts when the screen was used before it.
            runCounts = touches >= Self.touchesNeeded
            touches = 0
        }
        presses.append(now)
        guard runCounts, presses.count >= Self.pressesNeeded else { return false }
        runCounts = false
        presses.removeAll()
        return true
    }
}

/// 画面滤镜: what is laid over the game's two
/// screens (the core's picture and the demo's), in every mode and on the TV.
/// FoldArc's own small set, drawn over the picture (ScreenFilterOverlay):
/// the pixels as they are, softened, scanlines, an LCD's grid, an old TV.
enum ScreenFilter: String, CaseIterable, Identifiable, Sendable {
    case sharp, smooth, scanlines, lcd, crt
    static let defaultsKey = "foldarc.screenFilter"
    var id: Self { self }
    var title: String {
        switch self {
        case .sharp: return String(localized: "原样")
        case .smooth: return String(localized: "柔和")
        case .scanlines: return String(localized: "扫描线")
        case .lcd: return String(localized: "LCD 网格")
        case .crt: return String(localized: "老电视")
        }
    }
    var summary: String {
        switch self {
        case .sharp: return String(localized: "每个像素方方正正，和原机的屏一样清楚。")
        case .smooth: return String(localized: "把像素的边抹平一点，放大很多时不那么颗粒。")
        case .scanlines: return String(localized: "每行像素之间一条暗线，像老式显示器。")
        case .lcd: return String(localized: "每个像素四周一圈细缝，像凑近了看掌机的液晶屏。")
        case .crt: return String(localized: "扫描线、边角变暗、颜色浓一点，像显像管电视。")
        }
    }
    /// The picture scaled smoothly rather than pixel by pixel.
    var smooths: Bool { self == .smooth || self == .crt }
    static var stored: ScreenFilter {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ScreenFilter.init(rawValue:)) ?? .sharp
    }
    /// How strongly the lines show when a 3DS pixel is `pointsPerPixel`
    /// points on screen: none below about one point (they would only darken
    /// the picture into a moiré), full from about two.
    static func strength(pointsPerPixel: Double) -> Double {
        min(1, max(0, (pointsPerPixel - 0.9) / 1.2))
    }
}

struct DemoState: Codable, Equatable, Sendable {
    var player = Point(x: 0.5, y: 0.55)
    var target = Point(x: 0.76, y: 0.32)
    var beacon = Point(x: 0.5, y: 0.55)
    var collected = 0
    var seconds: Double = 0

    var isValid: Bool {
        [player.x, player.y, target.x, target.y, beacon.x, beacon.y].allSatisfy { $0.isFinite && (0...1).contains($0) }
            && seconds.isFinite && seconds >= 0 && (0...1_000_000).contains(collected)
    }
    mutating func tick(delta: Double, buttons: Set<PadButton>, analog: Point = Point(x: 0, y: 0)) {
        let dt = max(0, min(delta, 0.05))
        seconds += dt
        let speed = buttons.contains(.b) ? 0.55 : 0.28
        var dx = (buttons.contains(.right) ? 1.0 : 0) - (buttons.contains(.left) ? 1.0 : 0) + analog.x
        var dy = (buttons.contains(.down) ? 1.0 : 0) - (buttons.contains(.up) ? 1.0 : 0) + analog.y
        let magnitude = hypot(dx, dy)
        if magnitude > 1 { dx /= magnitude; dy /= magnitude }
        player.x += dx * speed * dt
        player.y += dy * speed * dt
        player = player.clamped
        collectIfNear()
    }
    mutating func touch(_ point: Point) { beacon = point.clamped }
    mutating func activate() { player = beacon; collectIfNear() }
    private mutating func collectIfNear() {
        guard hypot(player.x - target.x, player.y - target.y) < 0.09 else { return }
        collected += 1
        target = Point(x: 0.15 + Double((collected * 37) % 70) / 100,
                       y: 0.16 + Double((collected * 23) % 66) / 100)
    }
}

/// Boundary for a future audited 3DS core. No 3DS implementation is shipped in this prototype.
/// A real adapter must separately implement audio/video timing, GPU output, input, and lifecycle.
@MainActor protocol ThreeDSCore {
    var isRunning: Bool { get }
    func load(rom: URL) async throws
    func start() throws
    func pause()
    func stop()
    func setButton(_ button: PadButton, pressed: Bool)
    func setTouch(x: UInt16, y: UInt16, pressed: Bool)
}

/// One reading of an external controller's extended gamepad. The face
/// buttons are named by position, as GameController lays them out (A at the
/// bottom, B on the right, X on the left, Y at the top: GCExtendedGamepad.h),
/// so the mapping below does not depend on the letters a controller prints.
/// Sticks: x to the right and y up, −1…1, as GameController reports them.
struct GamepadReading: Equatable, Sendable {
    var south = false, east = false, west = false, north = false
    var leftShoulder = false, rightShoulder = false
    var leftTrigger = 0.0, rightTrigger = 0.0
    var up = false, down = false, left = false, right = false
    var leftStick = Point(x: 0, y: 0), rightStick = Point(x: 0, y: 0)
    var menu = false, options = false, home = false
}

/// What a controller reading means on the 3DS. Face buttons go by position,
/// as on the handheld: A on the right, B at the bottom, X at the top, Y on
/// the left, whatever the controller prints on them. Shoulders are L / R,
/// triggers ZL / ZR, the left stick the Circle Pad, the right stick the
/// C Stick, Menu is START and Options SELECT. The controller's Home button
/// is FoldArc's HOME (handled by the caller, not a 3DS input).
enum GamepadMapping {
    /// Analog triggers count as pressed from half travel.
    static let triggerThreshold = 0.5
    /// Radial dead zone of the sticks; travel beyond it is rescaled to 0…1.
    static let stickDeadZone = 0.15

    static func buttons(_ r: GamepadReading) -> Set<PadButton> {
        var keys: Set<PadButton> = []
        if r.east { keys.insert(.a) }
        if r.south { keys.insert(.b) }
        if r.north { keys.insert(.x) }
        if r.west { keys.insert(.y) }
        if r.leftShoulder { keys.insert(.l) }
        if r.rightShoulder { keys.insert(.r) }
        if r.leftTrigger >= triggerThreshold { keys.insert(.zl) }
        if r.rightTrigger >= triggerThreshold { keys.insert(.zr) }
        if r.menu { keys.insert(.start) }
        if r.options { keys.insert(.select) }
        return keys
    }

    /// The D-pad, opposite directions cancelling out as on the handheld's cross.
    static func directions(_ r: GamepadReading) -> Set<PadButton> {
        var keys: Set<PadButton> = []
        if r.up != r.down { keys.insert(r.up ? .up : .down) }
        if r.left != r.right { keys.insert(r.left ? .left : .right) }
        return keys
    }

    /// A stick as FoldArc's pads take it: screen axes (x right, y down, like
    /// the on-screen Circle Pad), the dead zone removed, length at most 1.
    static func stick(_ s: Point) -> Point {
        let length = hypot(s.x, s.y)
        guard length > stickDeadZone else { return Point(x: 0, y: 0) }
        let scale = min(1, (length - stickDeadZone) / (1 - stickDeadZone)) / length
        return Point(x: s.x * scale, y: -s.y * scale)
    }
}

extension GamepadMapping {
    /// The buttons as `layout` maps them (round 31: 按键重新映射).
    static func buttons(_ r: GamepadReading, layout: GamepadLayout) -> Set<PadButton> { layout.buttons(r) }
}

/// A button of an external controller, by where it sits (round 31: 按键重新
/// 映射): the face buttons by side, the shoulders and triggers, Menu, Options.
enum GamepadSource: String, CaseIterable, Codable, Sendable {
    case east, south, north, west, leftShoulder, rightShoulder, leftTrigger, rightTrigger, menu, options
    var title: String {
        switch self {
        case .east: return String(localized: "右键")
        case .south: return String(localized: "下键")
        case .north: return String(localized: "上键")
        case .west: return String(localized: "左键")
        case .leftShoulder: return String(localized: "左肩键")
        case .rightShoulder: return String(localized: "右肩键")
        case .leftTrigger: return String(localized: "左扳机")
        case .rightTrigger: return String(localized: "右扳机")
        case .menu: return String(localized: "菜单键")
        case .options: return String(localized: "选项键")
        }
    }
    /// What it is printed as on the common controllers.
    var detail: String {
        switch self {
        case .east: return String(localized: "Xbox 的 B，PlayStation 的 ○")
        case .south: return String(localized: "Xbox 的 A，PlayStation 的 ✕")
        case .north: return String(localized: "Xbox 的 Y，PlayStation 的 △")
        case .west: return String(localized: "Xbox 的 X，PlayStation 的 □")
        case .leftShoulder: return String(localized: "LB，L1")
        case .rightShoulder: return String(localized: "RB，R1")
        case .leftTrigger: return String(localized: "LT，L2")
        case .rightTrigger: return String(localized: "RT，R2")
        case .menu: return String(localized: "Xbox 的 ☰，PlayStation 的 OPTIONS")
        case .options: return String(localized: "Xbox 的 ⧉，PlayStation 的 Create / Share")
        }
    }
    func isPressed(_ r: GamepadReading) -> Bool {
        switch self {
        case .east: return r.east
        case .south: return r.south
        case .north: return r.north
        case .west: return r.west
        case .leftShoulder: return r.leftShoulder
        case .rightShoulder: return r.rightShoulder
        case .leftTrigger: return r.leftTrigger >= GamepadMapping.triggerThreshold
        case .rightTrigger: return r.rightTrigger >= GamepadMapping.triggerThreshold
        case .menu: return r.menu
        case .options: return r.options
        }
    }
    static func pressed(_ r: GamepadReading) -> Set<GamepadSource> { Set(allCases.filter { $0.isPressed(r) }) }
}

/// Which controller button is which 3DS key (round 31: 按键重新映射). The
/// D-pad, the sticks and the Home button stay as they are.
struct GamepadLayout: Codable, Equatable, Sendable {
    /// The 3DS key's name (PadButton's raw value) → the controller's button.
    var sources: [String: GamepadSource]
    static let keys: [PadButton] = [.a, .b, .x, .y, .l, .r, .zl, .zr, .start, .select]
    /// As on the handheld: the face buttons by position (GamepadMapping).
    static let byPosition = GamepadLayout(sources: ["a": .east, "b": .south, "x": .north, "y": .west,
                                                    "l": .leftShoulder, "r": .rightShoulder, "zl": .leftTrigger, "zr": .rightTrigger,
                                                    "start": .menu, "select": .options])
    /// By the letters on an Xbox-style controller: its A is the 3DS's A.
    static let byLetter = GamepadLayout(sources: ["a": .south, "b": .east, "x": .west, "y": .north,
                                                  "l": .leftShoulder, "r": .rightShoulder, "zl": .leftTrigger, "zr": .rightTrigger,
                                                  "start": .menu, "select": .options])
    static let defaultsKey = "foldarc.gamepad.layout"
    /// 接上手柄自动换到手柄模式 (round 31), on unless turned off.
    static let autoModeKey = "foldarc.gamepad.autoMode"
    func source(for key: PadButton) -> GamepadSource? { sources[key.rawValue] }
    /// `source` now gives `key`; the key that had it takes `key`'s old
    /// button, so no button is lost and none does two things.
    mutating func assign(_ source: GamepadSource, to key: PadButton) {
        guard Self.keys.contains(key) else { return }
        let previous = sources[key.rawValue]
        if let other = sources.first(where: { $0.value == source && $0.key != key.rawValue })?.key { sources[other] = previous }
        sources[key.rawValue] = source
    }
    func buttons(_ r: GamepadReading) -> Set<PadButton> {
        var keys: Set<PadButton> = []
        for key in Self.keys { if let source = sources[key.rawValue], source.isPressed(r) { keys.insert(key) } }
        return keys
    }
    /// The 3DS key a controller button gives now, if any.
    func key(for source: GamepadSource) -> PadButton? { Self.keys.first { sources[$0.rawValue] == source } }
    var presetName: String {
        if self == .byPosition { return String(localized: "按位置") }
        if self == .byLetter { return String(localized: "按字母") }
        return String(localized: "自定义")
    }
    static var stored: GamepadLayout {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let layout = try? JSONDecoder().decode(GamepadLayout.self, from: data),
              Set(layout.sources.keys) == Set(keys.map(\.rawValue)) else { return .byPosition }
        return layout
    }
    func store() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }
}

/// A message from the core meaning the running software cannot go on, worded
/// for the player. citra_libretro's retro_run reports an error of Azahar's run
/// loop as "Fatal Error encountered (<status>): <details>" and missing system
/// files as "Azahar was unable to locate a 3DS system archive: <name>". Until
/// the 15th round only the status line showed it; during play the picture
/// just stopped (10-28: one .3dsx starting another).
struct SoftwareStop: Equatable, Sendable {
    let title: String
    let message: String

    /// nil for messages that do not stop the software.
    init?(coreMessage text: String) {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if let range = line.range(of: "unable to locate a 3DS system archive:") {
            let archive = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            title = String(localized: "缺少系统文件")
            message = String(localized: "这个软件需要主机的系统文件") + (archive.isEmpty ? "" : String(localized: "（\(archive)）"))
                + String(localized: "。Zero EMU 不附带系统文件，所以它没法接着运行。")
            return
        }
        let prefix = "Fatal Error encountered ("
        guard line.hasPrefix(prefix), let close = line.firstIndex(of: ")"),
              let status = Int(line[line.index(line.startIndex, offsetBy: prefix.count)..<close]) else { return nil }
        switch status {
        // Not about the software: no game running (1); FoldArc's own save
        // states take another way than the run loop's (11, 15).
        case 1, 11, 15:
            return nil
        case 16:   // ShutdownRequested: the software ended itself
            title = String(localized: "软件已结束")
            message = String(localized: "这个软件自己结束了运行（在主机上会回到主菜单）。")
        case 14:   // ErrorCoreExceptionRaised
            title = String(localized: "软件出错，已停止运行")
            message = String(localized: "模拟的处理器在这个软件里遇到了无法继续的错误。可以关闭软件后重新打开；每次都在同一个地方出错的话，可能是 Zero EMU 的模拟还不支持它。")
        case 17:   // ErrorUnknown: the software reported a fatal error (err:f)
            title = String(localized: "软件出错，已停止运行")
            message = String(localized: "这个软件报告了一个无法继续的错误。可以关闭软件后重新打开。")
        default:
            title = String(localized: "软件出错，已停止运行")
            message = String(localized: "核心报告了无法继续的错误（代码 \(status)）。可以关闭软件后重新打开。")
        }
    }
}

/// Sources/ThirdPartyLicenses.txt: one block per component, each a header
/// (name, licence, the file's path in the source tree) and the licence's
/// text, the parts fenced by lines of fifty "=" and nothing else.
/// 11-11: read by whole lines. (Until b77h the text was cut wherever fifty
/// "=" stood in a row — and LibreSSL's and glslang's own texts have longer
/// rules of them: a block named "=====" turned up in 开源许可's list, and the
/// three components after glslang came out with pieces of its text for
/// their names. Found 11-11.)
enum LicenceFile {
    static let fence = String(repeating: "=", count: 50)
    static func parse(_ whole: String) -> [(name: String, licence: String, text: String)] {
        // sections: [intro, header1, text1, header2, text2, …]
        var sections: [[Substring]] = [[]]
        for line in whole.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == fence { sections.append([]) } else { sections[sections.count - 1].append(line) }
        }
        var out: [(name: String, licence: String, text: String)] = []
        var index = 1
        while index + 1 < sections.count {
            let header = sections[index].map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let text = sections[index + 1].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if header.count >= 2 { out.append((header[0], header[1], text)) }
            index += 2
        }
        return out
    }
}

/// Addresses the App Store build needs, in one place. Fill them in before the
/// first TestFlight build (Docs/APPSTORE-READINESS-20261028.md): the GPL needs
/// the source link inside the app; App Store Connect asks for a support page
/// and a privacy policy. A nil link is left out of the interface.
enum AppLinks {
    /// Public repository with the complete corresponding source.
    static let source: URL? = URL(string: "https://github.com/Zero-EMU/zero-emu")
    /// Support page, or a mailto: address ("反馈与支持").
    static let support: URL? = URL(string: "https://zero-emu.github.io/zero-emu/support.html")
    /// Privacy policy page.
    static let privacy: URL? = URL(string: "https://zero-emu.github.io/zero-emu/privacy.html")
    /// Zero EMU's own user agreement (the App Store page's License Agreement
    /// is the same text): the Pro page's 使用条款 and the 用户协议 page link to it.
    static let terms: URL? = URL(string: "https://zero-emu.github.io/zero-emu/terms.html")
    /// The ones still missing (Scripts/test.sh prints them).
    static var missing: [String] {
        [("source", source), ("support", support), ("privacy", privacy), ("terms", terms)].filter { $0.1 == nil }.map(\.0)
    }
}

/// The 3D slider (round 16). Its position is what a game reads as the 3DS's
/// 3D slider (the core's `citra_factor_3d`, 0–100 % in 10 % steps), and while
/// it is up FoldArc shows the stereo picture as red/cyan anaglyph
/// (`citra_render_3d`): an iPhone has no glasses-free 3D screen.
enum Stereo3D {
    static let defaultsKey = "foldarc.depth3D"
    /// Slider position 0…1 -> the core's percentage, rounded to its 10 % steps.
    static func percent(slider: Double) -> Int {
        guard slider.isFinite else { return 0 }
        return Int((min(1, max(0, slider)) * 10).rounded()) * 10
    }
    /// The two core options for a percentage.
    static func coreOptions(percent: Int) -> [String: String] {
        let value = min(100, max(0, (percent + 5) / 10 * 10))
        return ["citra_factor_3d": String(value), "citra_render_3d": value > 0 ? "anaglyph" : "off"]
    }
    /// The slider position the user left it at (UserDefaults), 0…1.
    static var storedSlider: Double {
        let value = UserDefaults.standard.double(forKey: defaultsKey)
        return value.isFinite ? min(1, max(0, value)) : 0
    }
}


/// 11-07: what the play mode
/// becomes when the iPhone is turned on its side, or upright again
/// (PlayView), by ScreenLayout's raw values — no SwiftUI here, for the
/// checks. On its side 掌机模式 and 桌面模式 become 手柄模式 (its across
/// layout), the mode before kept; upright again it comes back while
/// 手柄模式 is still up. 手柄模式 and TV模式 stay as they are; a mode
/// chosen while on its side forgets the one before (PlayView's setMode).
enum SidewaysMode {
    static let turned: Set<String> = ["handheld", "tabletop"]
    static let across = "controller"
    static func next(mode: String, sideways: Bool, before: String?) -> (mode: String, before: String?) {
        if sideways {
            guard before == nil, turned.contains(mode) else { return (mode, before) }
            return (across, mode)
        }
        guard let before else { return (mode, nil) }
        return (mode == across ? before : mode, nil)
    }
    /// PlayView's state (and the checks'): the hold last acted on and the
    /// mode to come back to. It acts only on a change of hold — a mode
    /// chosen by hand while on its side stays until the iPhone is turned
    /// again (b70's first check: a program closing must not undo it).
    struct State: Equatable {
        var seen: Bool? = nil
        var before: String? = nil
        /// The mode for this hold, nil when it stays.
        mutating func settle(mode: String, sideways: Bool) -> String? {
            guard sideways != seen else { return nil }
            seen = sideways
            let next = SidewaysMode.next(mode: mode, sideways: sideways, before: before)
            before = next.before
            return next.mode == mode ? nil : next.mode
        }
        /// A mode chosen by hand: nothing to come back to.
        mutating func chosen() { before = nil }
    }
    /// Whether a Duo's game window on the inner display turns with the hold
    /// (CoverOrientationPolicy.playFollowsHold): held across, the lid open —
    /// in every mode since 11-07 (掌机模式
    /// and 桌面模式 stayed in the handheld's window, the system's small 469 ×
    /// 669 one with black either side; they are drawn as 手柄模式 now, see
    /// `presented`).
    static func followsHold(mode: String, across: Bool, cover: Bool) -> Bool {
        !cover && across
    }
    /// What is drawn for `mode` on a Duo's inner display (11-07): held
    /// across, 掌机模式 and 桌面模式 as 手柄模式 (flat the screens in the
    /// middle, half folded one on each page); upright, 掌机模式 as 手柄模式
    /// when a controller style is chosen for it (`uprightController`,
    /// DuoUprightLook), else the console. The mode itself is not changed:
    /// turned back, it is drawn as it was.
    static func presented(mode: String, across sideways: Bool, cover: Bool, uprightController: Bool) -> String {
        guard !cover else { return mode }
        if sideways, turned.contains(mode) { return across }
        if !sideways, mode == "handheld", uprightController { return across }
        return mode
    }
    /// How a Duo is held, by UIDevice's reading — the inner display is a
    /// quarter turned against the device (CoverOrientationPolicy.
    /// innerInterface): the handheld's pose (crease across, the side-button
    /// half down) is the device's landscapeRight, upside down landscapeLeft;
    /// across like a book is the device's portrait (USB-C edge down) or
    /// portraitUpsideDown; flat on a table says nothing (the last hold
    /// stays). `across`: nil for flat.
    enum Hold: String, CaseIterable {
        case handheld, handheldDown = "handheld-down", book, bookDown = "book-down", flat
        var across: Bool? {
            switch self {
            case .handheld, .handheldDown: return false
            case .book, .bookDown: return true
            case .flat: return nil
            }
        }
    }
}


/// 11-07 沉浸模式: where the game's two screens go on the whole display — no SwiftUI here,
/// for the checks. The display is cut in two halves, either side of the
/// fold where there is one (a Duo's crease, which the screens are never
/// on), else of the middle; the upper screen (5:3) as big as its half
/// allows, the touch screen (4:3) in the other, both against the middle as
/// a console has them: upright one over the other, across side by side.
enum ImmersiveLayout {
    enum Toward { case top, bottom, leading, trailing }
    /// The two halves of `area`; `across` when it is wider than tall. A fold
    /// that does not cut it that way is left out (the middle is used).
    static func halves(of area: CGRect, fold: CGRect?, gap: CGFloat = 10) -> (first: CGRect, second: CGRect, across: Bool) {
        let across = area.width > area.height
        if across {
            var lo = area.midX - gap / 2, hi = area.midX + gap / 2
            if let fold, fold.height >= fold.width, fold.midX > area.minX, fold.midX < area.maxX { lo = fold.minX; hi = fold.maxX }
            return (CGRect(x: area.minX, y: area.minY, width: max(0, lo - area.minX), height: area.height),
                    CGRect(x: hi, y: area.minY, width: max(0, area.maxX - hi), height: area.height), true)
        }
        var lo = area.midY - gap / 2, hi = area.midY + gap / 2
        if let fold, fold.width >= fold.height, fold.midY > area.minY, fold.midY < area.maxY { lo = fold.minY; hi = fold.maxY }
        return (CGRect(x: area.minX, y: area.minY, width: area.width, height: max(0, lo - area.minY)),
                CGRect(x: area.minX, y: hi, width: area.width, height: max(0, area.maxY - hi)), false)
    }
    /// The largest rectangle of `aspect` (width ÷ height) in `rect` less a
    /// margin, against its `toward` edge, centred the other way.
    static func fit(aspect: CGFloat, in rect: CGRect, toward: Toward, margin: CGFloat = 4) -> CGRect {
        let inner = rect.insetBy(dx: margin, dy: margin)
        guard inner.width > 0, inner.height > 0, aspect > 0 else { return .zero }
        let width = min(inner.width, inner.height * aspect), height = width / aspect
        switch toward {
        case .leading: return CGRect(x: inner.minX, y: inner.midY - height / 2, width: width, height: height)
        case .trailing: return CGRect(x: inner.maxX - width, y: inner.midY - height / 2, width: width, height: height)
        case .top: return CGRect(x: inner.midX - width / 2, y: inner.minY, width: width, height: height)
        case .bottom: return CGRect(x: inner.midX - width / 2, y: inner.maxY - height, width: width, height: height)
        }
    }
}

/// A body colour stored under the name an earlier build gave it (another
/// note in the brackets after it): its name now, if it has one. Names that
/// are still names are left alone.
enum StoredFinishName {
    static let key = "foldarc.finish"
    static func current(for stored: String, isName: (String) -> Bool) -> String? {
        guard !isName(stored), let open = stored.lastIndex(of: "（") else { return nil }
        let renamed = String(stored[..<open]) + "（缤纷）"
        return isName(renamed) ? renamed : nil
    }
}

// MARK: - Zero EMU Pro

/// What is sold: two subscriptions that renew, and one purchase kept for
/// good. The raw value ends the product's identifier in App Store Connect.
enum ProPlan: String, CaseIterable, Sendable {
    case monthly, yearly, lifetime
    static let prefix = "com.zeroemu.app.pro."
    var productID: String { Self.prefix + rawValue }
    init?(productID: String) {
        guard productID.hasPrefix(Self.prefix) else { return nil }
        self.init(rawValue: String(productID.dropFirst(Self.prefix.count)))
    }
    /// A subscription: it renews until it is cancelled.
    var renews: Bool { self != .lifetime }
}

/// 典藏卡带: the three cards. Each comes with one purchase — 铜卡带 with 月付,
/// 银卡带 with 年付, 金卡带 with 永久 — and stands on the shelf while that
/// purchase is owned (永久 brings the gold one alone). Each plays films of
/// its own. Any one of them opens what ProAccess keeps for buyers.
enum Cartridge: String, CaseIterable, Sendable {
    case bronze, silver, gold
    var plan: ProPlan {
        switch self {
        case .bronze: return .monthly
        case .silver: return .yearly
        case .gold: return .lifetime
        }
    }
    init(plan: ProPlan) {
        switch plan {
        case .monthly: self = .bronze
        case .yearly: self = .silver
        case .lifetime: self = .gold
        }
    }
    /// The card's name where cards are remembered by name (the slot, the shelf).
    var cardID: String { rawValue }
    /// The cards these purchases bring, in the shelf's order.
    static func owned(_ plans: Set<ProPlan>) -> [Cartridge] { allCases.filter { plans.contains($0.plan) } }
}

/// 金卡带 bought at the launch price — to the end of 2027-01-01, by the
/// clock where it was bought — carries 首发版 on its 卡带证; no other card does.
enum CartridgeEdition {
    static func launch(_ cartridge: Cartridge, since: Date?, calendar: Calendar = .current) -> Bool {
        guard cartridge == .gold, let since,
              let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 2)) else { return false }
        return since < end
    }
}

/// What Pro opens and what stays free, as plain rules (the store itself is
/// ProStore.swift, the page ProPage in SystemSettingsApp.swift). Free: the
/// first ten body colours and the first eight camera bodies, in the order
/// their pickers show them. Pro only: the rest of both, 存档同步, 倍速.
enum ProAccess {
    /// Whether Pro is open, as the store last said. ProStore keeps it: a
    /// launch goes by the last answer until the store has answered again.
    static let entitledKey = "FoldArc.pro.entitled"
    static var isPro: Bool { UserDefaults.standard.bool(forKey: entitledKey) }
    /// Which purchases are owned, as the store last said: the cards on the
    /// shelf go by it until the store has answered again.
    static let plansKey = "FoldArc.pro.plans"
    static var plans: Set<ProPlan> {
        plans(kept: UserDefaults.standard.string(forKey: plansKey), entitled: isPro)
    }
    /// (An answer kept before the cards were three named no purchase: what
    /// was open then counts as 永久.)
    static func plans(kept text: String?, entitled: Bool) -> Set<ProPlan> {
        guard let text else { return entitled ? [.lifetime] : [] }
        return Set(text.split(separator: ",").compactMap { ProPlan(rawValue: String($0)) })
    }
    static func keep(_ plans: Set<ProPlan>, in defaults: UserDefaults = .standard) {
        defaults.set(!plans.isEmpty, forKey: entitledKey)
        defaults.set(plans.map(\.rawValue).sorted().joined(separator: ","), forKey: plansKey)
    }
    static var cartridges: [Cartridge] { Cartridge.owned(plans) }
    /// A card stays where it is (the shelf, the slot) while what it needs is
    /// owned: a 典藏卡带 goes back when its purchase is gone; every other
    /// card stays.
    static func keepsCard(id: String, plans: Set<ProPlan>) -> Bool {
        guard let cartridge = Cartridge(rawValue: id) else { return true }
        return plans.contains(cartridge.plan)
    }

    static let freeFinishes = 10
    static let freeBodies = 8
    /// 即时存档: the first five 存档位 of each game are everybody's to save
    /// into (StateSlots); what is in a further one can still be read.
    static let freeStateSlots = 5
    /// The choice at `position` in its picker (from 0) is among the `free`
    /// first. A choice the picker does not have is left alone.
    static func isFree(position: Int?, of free: Int) -> Bool {
        guard let position else { return true }
        return position < free
    }

    /// The plan to name for what is owned: 永久 before 年付 before 月付.
    static func plan(owning plans: Set<ProPlan>) -> ProPlan? {
        [ProPlan.lifetime, .yearly, .monthly].first { plans.contains($0) }
    }

    /// A setting whose choice only Pro has: what it holds, and what was put
    /// aside when Pro ended.
    struct Choice: Equatable {
        var current: String
        var aside: String?
    }
    /// Pro ended: a choice only Pro has is put aside and `fallback` (free)
    /// stands in for it. Pro is back: what was put aside comes back, unless
    /// something other than the stand-in was chosen meanwhile.
    static func settle(_ choice: Choice, pro: Bool, fallback: String, isFree: (String) -> Bool) -> Choice {
        if pro {
            guard let aside = choice.aside else { return choice }
            return Choice(current: choice.current == fallback ? aside : choice.current, aside: nil)
        }
        guard !isFree(choice.current) else { return choice }
        return Choice(current: fallback, aside: choice.current)
    }

    /// 永久's launch price: the last moment the page says "首发价" — the
    /// end of the first day of 2027, as the place the iPhone is in counts
    /// the day (the price schedule in App Store Connect has to run at least
    /// that long in every storefront; nil: no launch price is announced).
    /// The price itself is always the store's.
    static var launchOfferEnd: Date? { launchOfferEnd(in: .current) }
    static func launchOfferEnd(in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 23, minute: 59, second: 59))
    }
    static func offerRuns(until end: Date?, now: Date) -> Bool {
        guard let end else { return false }
        return now < end
    }
}

// MARK: - 存档位

/// A 典藏卡带 is a card of its own on the shelf while its purchase is owned:
/// in the console it plays short films of being small. Each cartridge has a
/// number of its own (drawn once on the device and kept). These scenes are
/// drawn by the app — the way home from school, a classroom in the
/// afternoon, a summer night, a window in the rain, the playground at dusk —
/// and one of them is the picture on 银卡带's label; the order and the small
/// things in each come from a cartridge's number.
enum GoldScene: String, CaseIterable, Sendable {
    case wayHome, classroom, summerNight, rainyWindow, playground
}

/// 银卡带's films: the four seasons of being small, drawn in coloured pencil,
/// a minute each, each a video with its sound in the app — 春 · 风筝,
/// 夏 · 夏夜, 秋 · 回家路上, 冬 · 下雪了. The card begins with the season it
/// is and goes on round the year; after the fourth its last picture stays.
enum SilverSeason: String, CaseIterable, Sendable {
    case spring, summer, autumn, winter
    /// Each film's length (seconds); it goes dark in its last moment.
    static let length = 60.0
    /// After the fourth film its last picture is held from here (before it goes dark).
    static let holdAt = 58.2
    /// Where each film's shots begin (seconds): the same nine places in all four.
    static let shotStarts: [Double] = [0, 5.8, 12.0, 18.0, 23.8, 30.4, 37.0, 43.0, 50.4]
    /// The video (`silver-film-<season>.mp4`).
    var file: String { "silver-film-\(rawValue)" }
    /// Its first picture (dim behind the opening), its last before it goes
    /// dark (held after the fourth film) and its small picture on the strip.
    var opening: String { "silver-film-\(rawValue)-open.jpg" }
    var held: String { "silver-film-\(rawValue)-end.jpg" }
    var picture: String { "silver-shot-\(rawValue).jpg" }
    /// The season of a month (1 … 12): March to May spring, June to August
    /// summer, September to November autumn, December to February winter.
    static func of(month: Int) -> SilverSeason {
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
    /// The four from `first`, on round the year.
    static func order(from first: SilverSeason) -> [SilverSeason] {
        let start = allCases.firstIndex(of: first) ?? 0
        return allCases.indices.map { allCases[(start + $0) % allCases.count] }
    }
    /// The four as the card plays them on `date`: the season it is, then the ones after it.
    static func order(on date: Date, calendar: Calendar = .current) -> [SilverSeason] {
        order(from: of(month: calendar.component(.month, from: date)))
    }
}

/// 铜卡带's films: the games of the ten minutes between lessons, as pencil
/// people in the corner of a schoolbook, moving as its pages are flipped.
enum FlipGame: String, CaseIterable, Sendable {
    case jumpRope, shuttlecock
}

/// The same numbers for the same seed on every device (SplitMix64).
struct ReelRandom: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// 0 ..< 1.
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
    /// 0 ..< n.
    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    /// low ... high.
    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
}

struct GoldReelPlan: Equatable, Sendable {
    static let cardID = "gold"
    static let seedKey = "FoldArc.gold.seed"
    /// How long one film plays before the next comes (seconds).
    static let sceneSeconds = 16.0
    let seed: UInt64
    /// The drawn scenes, every one once, in this cartridge's order.
    let order: [GoldScene]
    /// 铜卡带's games, every one once, in an order of its own.
    let games: [FlipGame]
    init(seed: UInt64) {
        self.seed = seed
        var random = ReelRandom(seed: seed)
        var left = GoldScene.allCases
        var order: [GoldScene] = []
        while !left.isEmpty { order.append(left.remove(at: random.int(left.count))) }
        self.order = order
        var flips = ReelRandom(seed: seed ^ 0xB5AD_4ECE_DA1C_E2A9)
        var rest = FlipGame.allCases
        var games: [FlipGame] = []
        while !rest.isEmpty { games.append(rest.remove(at: flips.int(rest.count))) }
        self.games = games
    }
    /// How many films a card has (银卡带: its seasons; 金卡带: its one film's shots, GoldFilm).
    func count(_ cartridge: Cartridge) -> Int {
        switch cartridge {
        case .bronze: return games.count
        case .silver: return SilverSeason.allCases.count
        case .gold: return GoldFilm.shots.count
        }
    }
    /// How long one of a card's films plays before the next comes (seconds).
    static func seconds(_ cartridge: Cartridge) -> Double { cartridge == .bronze ? 12.0 : sceneSeconds }
    /// The numbers one game is drawn from.
    func random(for game: FlipGame) -> ReelRandom {
        let index = UInt64(FlipGame.allCases.firstIndex(of: game) ?? 0)
        return ReelRandom(seed: seed ^ ((index &+ 7) &* 0x9E6C_63D0_676A_9A99))
    }
    /// The numbers one film is drawn from: its own run, the same each time.
    func random(for scene: GoldScene) -> ReelRandom {
        let index = UInt64(GoldScene.allCases.firstIndex(of: scene) ?? 0)
        return ReelRandom(seed: seed ^ ((index &+ 1) &* 0xD1B5_4A32_D192_ED03))
    }
    /// Which of a film's captions this cartridge shows (0 ..< count).
    func caption(for scene: GoldScene, of count: Int) -> Int {
        var random = self.random(for: scene)
        return random.int(max(1, count))
    }
    /// The cartridge's number as printed (four hexadecimal digits).
    var code: String {
        let digits = Array("0123456789ABCDEF")
        return String((0..<4).map { digits[Int((seed >> UInt64(12 - 4 * $0)) & 0xF)] })
    }
    /// This device's cartridge: drawn the first time, kept after.
    static func stored(_ defaults: UserDefaults = .standard) -> GoldReelPlan {
        if let text = defaults.string(forKey: seedKey), let seed = UInt64(text) { return GoldReelPlan(seed: seed) }
        let seed = UInt64.random(in: 1...UInt64.max)
        defaults.set(String(seed), forKey: seedKey)
        return GoldReelPlan(seed: seed)
    }
}

/// 金卡带's own film, 「一台掌机的回忆」: one film of nine shots, a minute
/// long, drawn in coloured pencil and played straight through (a video with
/// its sound in the app). After it the last picture stays — the console's
/// screens lit, 「好久不见。」 on the upper one — the dust still drifting in
/// their light (drawn by the app over a still of that picture).
enum GoldFilm {
    /// The video (`gold-film.mp4`).
    static let file = "gold-film"
    /// Its length (seconds); from here the last picture is held.
    static let length = 62.0
    /// The shots: a name for the logs and the tests, and where each begins (seconds).
    static let shots: [(key: String, start: Double)] = [
        ("birthday", 0), ("quilt", 7), ("classroom", 14), ("summer", 21), ("desk", 27),
        ("packing", 33), ("attic", 39), ("found", 45), ("lit", 53),
    ]
    /// The shot playing `t` seconds into the film.
    static func shot(at t: Double) -> Int { shots.lastIndex { $0.start <= t } ?? 0 }
    /// A shot's small picture on the strip.
    static func picture(_ index: Int) -> String { "gold-shot-\(min(max(index, 0), shots.count - 1) + 1).jpg" }
    /// The last picture without its dust (the hold), and a picture of the
    /// first shot (dim behind the opening's words).
    static let held = "gold-film-end.jpg"
    static let opening = "gold-film-open.jpg"
    /// The camera on the last picture: its left, top and width on the film's
    /// sheet (1000 x 600 units; the picture is 1280 x 768).
    static let lastCamera = (x: 96.0, y: 58.0, width: 808.0)
    static let pictureSize = (width: 1280.0, height: 768.0)
    /// Where the dust drifts in the screens' light there: the middle, and half
    /// the reach across and down (sheet units); how many motes.
    static let dust = (x: 500.0, y: 230.0, rx: 230.0, ry: 200.0, count: 70)
    /// One mote at `seconds` (any running clock): where it is on the sheet,
    /// its radius in the picture's pixels, how bright it glints (0 ... 1).
    /// Each drifts up and a little sideways, round again from the bottom.
    static func mote(_ index: Int, at seconds: Double) -> (x: Double, y: Double, radius: Double, glint: Double) {
        var random = ReelRandom(seed: 0x6475_7374 &+ UInt64(index) &* 0x9E37_79B9)
        let u0 = random.unit(), v0 = random.unit(), phase = random.unit(), speed = random.unit(), size = random.unit()
        func wrap(_ x: Double) -> Double { x - x.rounded(.down) }
        let v = wrap(v0 - seconds * (0.004 + 0.01 * speed) - seconds * 0.018)
        let u = wrap(u0 + 0.03 * sin(seconds * (0.3 + speed) + phase * 6.28))
        let glint = 0.45 + 0.55 * (0.5 + 0.5 * sin(seconds * (1.5 + 2 * speed) + phase * 9))
        let k = pictureSize.width / lastCamera.width
        return (dust.x + (u - 0.5) * 2 * dust.rx, dust.y + (v - 0.5) * 2 * dust.ry, (0.7 + size * 0.9) * k / 2.4, glint)
    }
}

/// The film's timeline as it was laid (gold_film.py's CLIPS): each picture, when it shows, the
/// camera's window on the sheet at its start and its end (left, top, width; the height is 0.6 of the
/// width), its fade in and out. The app needs it to lay what answers the wind exactly over the film.
extension GoldFilm {
    struct Window: Sendable, Equatable { var x: Double, y: Double, w: Double }
    struct Clip: Sendable {
        let picture: String
        let start: Double, end: Double
        let from: Window, to: Window
        let fadeIn: Double, fadeOut: Double
    }
    static let clips: [Clip] = [
        Clip(picture: "gold1_still", start: 0.0, end: 5.0, from: Window(x: 0, y: 0, w: 1000), to: Window(x: 130, y: 70, w: 740), fadeIn: 0.9, fadeOut: 0.6),
        Clip(picture: "gold1_b", start: 4.4, end: 7.6, from: Window(x: 130, y: 70, w: 740), to: Window(x: 165, y: 90, w: 670), fadeIn: 0.6, fadeOut: 0.6),
        Clip(picture: "gold2_a", start: 7.0, end: 12.2, from: Window(x: 30, y: 18, w: 940), to: Window(x: 60, y: 36, w: 880), fadeIn: 0.6, fadeOut: 0.2),
        Clip(picture: "gold2_b", start: 12.0, end: 14.6, from: Window(x: 55, y: 33, w: 890), to: Window(x: 70, y: 42, w: 860), fadeIn: 0.2, fadeOut: 0.6),
        Clip(picture: "gold3_a", start: 14.0, end: 18.8, from: Window(x: 0, y: 0, w: 1000), to: Window(x: 70, y: 42, w: 860), fadeIn: 0.6, fadeOut: 0.25),
        Clip(picture: "gold3_b", start: 18.55, end: 21.6, from: Window(x: 70, y: 42, w: 860), to: Window(x: 85, y: 51, w: 830), fadeIn: 0.25, fadeOut: 0.6),
        Clip(picture: "gold4_a", start: 21.0, end: 27.6, from: Window(x: 80, y: 48, w: 840), to: Window(x: 30, y: 18, w: 940), fadeIn: 0.6, fadeOut: 0.6),
        Clip(picture: "gold5_a", start: 27.0, end: 31.0, from: Window(x: 0, y: 0, w: 1000), to: Window(x: 30, y: 18, w: 940), fadeIn: 0.6, fadeOut: 1.0),
        Clip(picture: "gold5_b", start: 30.0, end: 33.6, from: Window(x: 25, y: 15, w: 950), to: Window(x: 50, y: 30, w: 900), fadeIn: 1.0, fadeOut: 0.6),
        Clip(picture: "gold6_a", start: 33.0, end: 36.6, from: Window(x: 60, y: 36, w: 880), to: Window(x: 85, y: 51, w: 830), fadeIn: 0.6, fadeOut: 0.4),
        Clip(picture: "gold6_b", start: 36.2, end: 39.9, from: Window(x: 85, y: 51, w: 830), to: Window(x: 100, y: 60, w: 800), fadeIn: 0.4, fadeOut: 0.9),
        Clip(picture: "gold7_a", start: 39.0, end: 45.8, from: Window(x: 0, y: 0, w: 1000), to: Window(x: 60, y: 36, w: 880), fadeIn: 0.9, fadeOut: 0.8),
        Clip(picture: "gold8_a", start: 45.0, end: 50.2, from: Window(x: 60, y: 72, w: 880), to: Window(x: 60, y: 0, w: 880), fadeIn: 0.8, fadeOut: 0.6),
        Clip(picture: "gold8_b", start: 49.6, end: 53.6, from: Window(x: 40, y: 24, w: 920), to: Window(x: 70, y: 42, w: 860), fadeIn: 0.6, fadeOut: 0.6),
        Clip(picture: "gold9_a", start: 53.0, end: 56.35, from: Window(x: 40, y: 24, w: 920), to: Window(x: 70, y: 42, w: 860), fadeIn: 0.6, fadeOut: 0.35),
        Clip(picture: "gold9_b", start: 56.0, end: 62.0, from: Window(x: 70, y: 42, w: 860), to: Window(x: 96, y: 58, w: 808), fadeIn: 0.35, fadeOut: 0.0),
    ]
    static func ease(_ x: Double) -> Double { let k = min(1, max(0, x)); return k * k * (3 - 2 * k) }
    /// The camera's window on the sheet at `t` (eased from its start to its end, as the film moves it).
    static func camera(_ clip: Clip, at t: Double) -> Window {
        let u = ease((t - clip.start) / (clip.end - clip.start))
        return Window(x: clip.from.x + (clip.to.x - clip.from.x) * u, y: clip.from.y + (clip.to.y - clip.from.y) * u, w: clip.from.w + (clip.to.w - clip.from.w) * u)
    }
    /// How much of the picture at `t` each clip makes, as the film laid them one over another
    /// (each comes in over what is under it by its fade-in; the last fades out by its own fade-out).
    static func weights(at t: Double) -> [(index: Int, weight: Double)] {
        let active = clips.indices.filter { clips[$0].start <= t && t <= clips[$0].end }
        var alphas: [(Int, Double)] = []
        for (n, i) in active.enumerated() {
            let c = clips[i]
            var a = c.fadeIn > 0 ? ease((t - c.start) / c.fadeIn) : 1
            let laterStarted = active.contains { $0 != i && clips[$0].start > c.start && clips[$0].start <= t + 1e-6 }
            if n == active.count - 1, c.fadeOut > 0, !laterStarted, c.end < length { a *= ease((c.end - t) / c.fadeOut) }
            if a > 0 { alphas.append((i, a)) }
        }
        var out: [(index: Int, weight: Double)] = []
        for (k, (i, a)) in alphas.enumerated() {
            let over = alphas[(k + 1)...].reduce(1.0) { $0 * (1 - $1.1) }
            out.append((i, a * over))
        }
        return out
    }
    /// A gust over the film: how far the things that answer it are moved, `age` seconds in (a gust lasts
    /// `gustSeconds`): paper corners flutter up (0 … 1); curtains swing, a fan on the mat rocks, a
    /// carton's flap leans, and flames, children's hair and torn wrapping paper lean and tremble toward
    /// where the wind blows (-1 … 1, negative to the left).
    static let gustSeconds = 2.4
    static func windLevel(_ kind: String, age: Double, right: Bool) -> Double {
        windLevel(kind, age: age, right: right, strength: gustStrength(age: age))
    }
    /// A finger's gust, `age` seconds in: up within 0.3 s, dying away over its last 1.4 s (0 … 1).
    static func gustStrength(age: Double) -> Double {
        guard age >= 0, age < gustSeconds else { return 0 }
        return ease(age / 0.3) * ease((gustSeconds - age) / 1.4)
    }
    /// The same at a strength of the wind's own (ReelWind: a breath's holds while it lasts); `age` keeps the
    /// fluttering and swaying going.
    static func windLevel(_ kind: String, age: Double, right: Bool, strength e: Double) -> Double {
        guard age >= 0, e > 0 else { return 0 }
        let d = right ? 1.0 : -1.0
        switch kind {
        case "flutter": return e * (0.55 + 0.45 * sin(age * 2 * .pi * 4.2))
        case "sway": return d * e * (0.75 + 0.25 * sin(age * 2 * .pi * 1.3))
        case "flicker": return d * e * (0.8 + 0.2 * sin(age * 2 * .pi * 7.0))
        default: return 0
        }
    }
    /// The two drawn strengths a level falls between, and how far from the first to the second.
    static func frames(for level: Double, in levels: [Double]) -> (Int, Int, Double) {
        guard levels.count > 1 else { return (0, 0, 0) }
        let l = min(levels[levels.count - 1], max(levels[0], level))
        for i in 0..<(levels.count - 1) where l <= levels[i + 1] {
            let span = levels[i + 1] - levels[i]
            return (i, i + 1, span > 0 ? (l - levels[i]) / span : 0)
        }
        return (levels.count - 1, levels.count - 1, 0)
    }
    /// Where the light falls through the air in a picture (the film's sheet units): the beams the dust
    /// floats in (corners in order, top edge first), or a round reach (middle and half-widths). The
    /// classroom's windows (课间), the attic's (落灰, 翻出来, and down into the box), the sun on the
    /// floor of the half-emptied room (收拾), the evening window behind the console and then its
    /// screens' own light (屏幕亮了).
    static let beams: [String: [[(Double, Double)]]] = [
        "gold3_a": [[(-136.4, 7.3), (33.3, 66.7), (164.6, 406.2), (35.6, 474.0)], [(111.1, 93.9), (181.8, 118.6), (274.3, 348.6), (222.4, 375.8)]],
        "gold3_b": [[(-136.4, 7.3), (33.3, 66.7), (164.6, 406.2), (35.6, 474.0)], [(111.1, 93.9), (181.8, 118.6), (274.3, 348.6), (222.4, 375.8)]],
        "gold7_a": [[(150, 120), (230, 110), (760, 560), (520, 600)]],
        "gold8_a": [[(150, 120), (230, 110), (760, 560), (520, 600)]],
        "gold8_b": [[(0, 0), (380, 0), (1000, 560), (700, 600)]],
    ]
    static let lightAreas: [String: (x: Double, y: Double, rx: Double, ry: Double)] = [
        "gold6_a": (200, 360, 170, 130),
        "gold8_a": (470, 330, 170, 130),
        "gold8_b": (500, 295, 190, 150),
        "gold9_a": (800, 330, 200, 190),
        "gold9_b": (500, 230, 230, 200),
    ]
    /// A point inside a beam at (u, v) in 0 … 1 across and down it.
    static func point(in quad: [(Double, Double)], u: Double, v: Double) -> (Double, Double) {
        let top = (quad[0].0 + (quad[1].0 - quad[0].0) * u, quad[0].1 + (quad[1].1 - quad[0].1) * u)
        let bottom = (quad[3].0 + (quad[2].0 - quad[3].0) * u, quad[3].1 + (quad[2].1 - quad[3].1) * u)
        return (top.0 + (bottom.0 - top.0) * v, top.1 + (bottom.1 - top.1) * v)
    }
    /// A mote the gust stirs up in the light, `age` seconds in: where (u, v in its beam or reach), how
    /// big (the picture's pixels at its camera's scale over 2.4) and how bright. It is blown along the
    /// way the wind goes, turning as it goes.
    static func gustMote(_ index: Int, age: Double, right: Bool) -> (u: Double, v: Double, size: Double, glint: Double) {
        var random = ReelRandom(seed: 0x7769_6E64 &+ UInt64(index) &* 0x2545_F491)
        let u0 = random.unit(), v0 = random.unit(), phase = random.unit(), speed = random.unit(), size = random.unit()
        let d = right ? 1.0 : -1.0
        let push = ease(age / 1.6)
        let u = u0 + d * push * (0.18 + 0.16 * speed) + 0.03 * sin(age * (2.2 + speed * 2) + phase * 6.28)
        let v = v0 - push * 0.08 + 0.05 * sin(age * (1.6 + speed) + phase * 9)
        let glint = (0.5 + 0.5 * sin(age * (5 + 4 * speed) + phase * 7)) * ease(age / 0.25) * ease((gustSeconds - age) / 0.9)
        return (u, v, 0.8 + size * 1.0, glint)
    }
    /// Dust blown off, `age` seconds after the gust: how much of it still lies there (gone in under a
    /// second; it stays gone).
    static func dustLeft(_ age: Double) -> Double { age < 0 ? 1 : 1 - ease(age / 0.7) }
    /// How long the blown-off grains are in the air (all gone by then).
    static let dustBlowSeconds = 2.4
    /// A grain of the blown-off dust, `age` seconds after the gust: how far it has gone from where it
    /// lay (sheet units: the way the wind blows, slowing, and a little up), how big (units) and how much
    /// it shows (0 … 1).
    static func blownGrain(_ index: Int, age: Double, right: Bool) -> (dx: Double, dy: Double, size: Double, alpha: Double) {
        var random = ReelRandom(seed: 0x6475_7374_6F66 &+ UInt64(index) &* 0x9E37_79B9)
        let delay = random.unit() * 0.35, life = 1.1 + random.unit() * 0.9, speed = 140 + random.unit() * 220
        let rise = 10 + random.unit() * 50, phase = random.unit() * 6.28, size = 1.0 + random.unit() * 2.0
        let tau = age - delay
        guard tau > 0, tau < life else { return (0, 0, size, 0) }
        let d = right ? 1.0 : -1.0
        let dx = d * speed * (tau - 0.25 * tau * tau)
        let dy = -rise * tau + 8 * sin(tau * 4 + phase)
        let alpha = ease(tau / 0.12) * (1 - ease((tau - 0.3) / (life - 0.3)))
        return (dx, dy, size, alpha)
    }
}

/// Dust blown off one of the things in 金卡带's film: when, and which way the wind went.
struct GoldDustBlow: Equatable, Sendable {
    var at: Date
    var right: Bool
}

/// The wind over a cartridge's film. A finger's gust runs its own course (GoldFilm.gustSeconds). A breath on the
/// microphone sends a gust as it begins and another every little while as it goes on (GoldReel.tick); a breath's
/// gusts hold at full strength while it lasts and die down within `calmSeconds` once it ends: wind while someone
/// blows, none once they stop.
struct ReelWind: Equatable, Sendable {
    struct Gust: Equatable, Sendable {
        var at: Date
        var right: Bool
        var breath: Bool
        /// When its breath ended (nil: it goes on, or a finger's gust).
        var calmAt: Date?
    }
    /// A gust at a moment: seconds since it began, which way, how strong (0 … 1: its course, and its breath's
    /// ending), and how much of its breath is left (1 until the breath ends, then down to 0 within calmSeconds).
    struct Blow: Equatable, Sendable {
        var age: Double
        var right: Bool
        var strength: Double
        var left: Double
        var breath: Bool
    }
    static let calmSeconds = 0.6
    /// The most kept (a breath of six seconds sends five or six).
    static let kept = 8
    private(set) var gusts: [Gust] = []
    var isEmpty: Bool { gusts.isEmpty }
    mutating func blow(at now: Date, right: Bool, breath: Bool) {
        gusts.removeAll { !Self.blowing($0, at: now) }
        gusts.append(Gust(at: now, right: right, breath: breath, calmAt: nil))
        if gusts.count > Self.kept { gusts.removeFirst(gusts.count - Self.kept) }
    }
    /// The breath has ended: its gusts die down.
    mutating func calm(at now: Date) {
        for i in gusts.indices where gusts[i].breath && gusts[i].calmAt == nil { gusts[i].calmAt = now }
    }
    /// Gusts there were, and none blows any more (time to let them go).
    func isStill(at now: Date) -> Bool { !gusts.isEmpty && !gusts.contains { Self.blowing($0, at: now) } }
    static func left(_ gust: Gust, at now: Date) -> Double {
        guard gust.breath, let calmAt = gust.calmAt else { return 1 }
        return 1 - GoldFilm.ease(now.timeIntervalSince(calmAt) / calmSeconds)
    }
    static func blowing(_ gust: Gust, at now: Date) -> Bool {
        let age = now.timeIntervalSince(gust.at)
        guard age >= 0 else { return true }
        return gust.breath ? left(gust, at: now) > 0 : age < GoldFilm.gustSeconds
    }
    /// Every gust still blowing at `now`, oldest first.
    func blows(at now: Date) -> [Blow] {
        gusts.compactMap { gust in
            let age = now.timeIntervalSince(gust.at)
            guard age >= 0, Self.blowing(gust, at: now) else { return nil }
            let left = Self.left(gust, at: now)
            let strength = gust.breath ? GoldFilm.ease(age / 0.3) * left : GoldFilm.gustStrength(age: age)
            return Blow(age: age, right: gust.right, strength: strength, left: left, breath: gust.breath)
        }
    }
    /// The one the things in the picture follow: the strongest — the oldest of those as strong, so that a
    /// breath's swaying goes on from its first gust without a jump as the next ones come.
    func strongest(at now: Date) -> Blow? {
        let all = blows(at: now)
        guard let top = all.map(\.strength).max(), top > 0 else { return nil }
        return all.first { $0.strength >= top - 0.02 }
    }
}

/// Dust the app lays over what was left in the attic in 金卡带's film (gold-dust.json, cut out of the
/// pictures drawn with it): where it lies on the sheet (units), its see-through picture, what it lies
/// on (the box, the console: blown off one, it stays off wherever that shows again), and the points
/// the blown-off dust leaves from.
struct GoldDustPlace: Decodable, Sendable, Equatable {
    let picture: String
    let file: String
    let thing: String
    let x: Double, y: Double, w: Double, h: Double
    let seeds: [[Double]]
    static func decode(_ data: Data) -> [GoldDustPlace] {
        struct List: Decodable { let places: [GoldDustPlace] }
        return (try? JSONDecoder().decode(List.self, from: data))?.places ?? []
    }
}

/// A place in one of the film's pictures that moves in the wind (gold-wind.json, made with the
/// pictures): where it is on the sheet (units), its strip (the place drawn at each strength, side by
/// side, its edges feathered), the strengths, and how it moves (GoldFilm.windLevel).
struct GoldWindPlace: Decodable, Sendable, Equatable {
    let picture: String
    let file: String
    let x: Double, y: Double, w: Double, h: Double
    let levels: [Double]
    let kind: String
    static func decode(_ data: Data) -> [GoldWindPlace] {
        struct List: Decodable { let places: [GoldWindPlace] }
        return (try? JSONDecoder().decode(List.self, from: data))?.places ?? []
    }
}

// MARK: - 画框

/// 画框 (the picture frame): a program of the console's menu, free for
/// everyone. A scenery that keeps moving fills the upper screen; the lower
/// one is dim, with the clock and a few switches. Each scenery is drawn
/// from nothing every frame, its light following the hour of the clock.
enum FrameScene: String, CaseIterable, Identifiable, Codable, Sendable {
    case campfire, roofs, tramStop, airship
    var id: String { rawValue }
    /// Drawn so far (all four now; one still being drawn is named on the
    /// lower screen and waits).
    var isReady: Bool { true }
}

/// How much of the day's light a scenery has: 0 deep night, 1 the day's.
/// The light comes over two hours at dawn and goes over two at dusk.
enum FrameLight {
    static let dawnStart = 5.0, dawnEnd = 7.0, duskStart = 17.5, duskEnd = 19.5
    /// For an hour of the clock (0 ..< 24, a fraction for the minutes).
    static func level(hour: Double) -> Double {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        let h = wrapped < 0 ? wrapped + 24 : wrapped
        if h < dawnStart || h >= duskEnd { return 0 }
        if h < dawnEnd { return ease((h - dawnStart) / (dawnEnd - dawnStart)) }
        if h < duskStart { return 1 }
        return 1 - ease((h - duskStart) / (duskEnd - duskStart))
    }
    /// The hour of the clock at `date`, with its minutes and seconds.
    static func hour(of date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }
    private static func ease(_ x: Double) -> Double {
        let k = min(1, max(0, x))
        return k * k * (3 - 2 * k)
    }
}

/// A scenery's sounds: what is heard in it all day (the campfire's fire; the
/// wind over the roofs), what is heard by night (crickets), what by day
/// (birds). How loud each is follows the scenery's light.
enum FrameSoundLayer: String, CaseIterable, Sendable {
    case always, night, day
    /// 0 ... 1 for a light (0 the night, a half the low sun, 1 the day).
    func level(light: Double, in scene: FrameScene = .campfire) -> Double {
        let level = min(1, max(0, light))
        let lowSun = min(1, level * 2), day = max(0, level * 2 - 1)
        switch (self, scene) {
        case (.always, .roofs): return 0.8 + 0.2 * lowSun
        case (.always, .tramStop): return 1 - 0.1 * lowSun
        case (.always, .airship): return 1 - 0.15 * lowSun
        case (.always, _): return 1 - 0.6 * lowSun - 0.1 * day
        case (.night, _): return (1 - lowSun) * (1 - lowSun)
        case (.day, .roofs): return lowSun * (1 - 0.2 * day)
        case (.day, _): return lowSun * (1 - 0.35 * day)
        }
    }
    /// The loops a scenery has. Over the clouds no birds are heard by day:
    /// the few that fly by are seen only now and then, and a sound with
    /// nothing in the picture to make it is left out.
    static func layers(in scene: FrameScene) -> [FrameSoundLayer] {
        scene == .airship ? [.always, .night] : allCases
    }
    /// The name of its file in the app (without the extension) for a scenery.
    func file(in scene: FrameScene) -> String {
        guard self == .always else { return "frame-\(scene.rawValue)-\(rawValue)" }
        switch scene {
        case .campfire: return "frame-campfire-fire"
        case .roofs: return "frame-roofs-air"
        case .tramStop: return "frame-tramStop-rain"
        case .airship: return "frame-airship-wind"
        }
    }
}

/// What a scenery plays once at its moments on its own clock (seconds since
/// the frame opened), over its loops: by the tram stop, the thunder a little
/// after each flash of lightning, and the tram from a few seconds before it
/// comes into the picture (it is heard coming) until it has gone.
enum FrameCue: String, CaseIterable, Sendable {
    case thunder, tram
    /// The lightning: the first flash, and the seconds from one to the next.
    static let flashAt = 17.0, flashPeriod = 61.0
    /// The tram: the first time it comes into the picture, and the seconds from one to the next.
    static let tramAt = 30.0, tramPeriod = 240.0
    /// How long before it comes into the picture its sound begins.
    static let tramHeard = 8.0
    static func cues(in scene: FrameScene) -> [FrameCue] { scene == .tramStop ? allCases : [] }
    /// The name of its file in the app (without the extension).
    var file: String { "frame-tramStop-\(rawValue)" }
    /// Its first moment (the thunder 2.6 seconds after the flash; the tram
    /// heard before it is seen), and the seconds from one to the next.
    var first: Double { self == .thunder ? Self.flashAt + 2.6 : Self.tramAt - Self.tramHeard }
    var period: Double { self == .thunder ? Self.flashPeriod : Self.tramPeriod }
    /// Seconds since the latest of its moments, if that came after `from`
    /// and by `to`; nil if none did.
    func began(after from: Double, upTo to: Double) -> Double? {
        guard to >= first, to > from else { return nil }
        let at = first + ((to - first) / period).rounded(.down) * period
        return at > from ? to - at : nil
    }
}

/// What a scenery plays now and then besides its loops, so that nothing in
/// it comes round on a beat: an owl far off in the pines, a wind chime on a
/// balcony, sparrows settling for the night (over the clouds nothing: what
/// would make a sound there is not in the picture). Each
/// comes at times that look chosen at random but are the same for the same
/// clock (seconds since the frame opened): the clock is cut into turns of
/// `gap` seconds, and in each turn it comes once at a place of its own, or
/// (one turn in five) not at all. It has a few variants; all of a scenery's
/// moments are in one file, each variant in a stretch of `slot` seconds, in
/// the order of `moments(in:)`. How loud it is follows its layer (the
/// night's owl is not heard by day).
enum FrameMoment: String, CaseIterable, Sendable {
    case owl, chime, sparrows

    var scene: FrameScene {
        switch self {
        case .owl: return .campfire
        case .chime, .sparrows: return .roofs
        }
    }
    var layer: FrameSoundLayer {
        switch self {
        case .owl: return .night
        case .sparrows: return .day
        case .chime: return .always
        }
    }
    /// The seconds of a turn (it comes about every gap ÷ 0.8 seconds).
    var gap: Double {
        switch self {
        case .owl: return 56
        case .chime: return 24
        case .sparrows: return 36
        }
    }
    var variants: Int {
        switch self {
        case .owl: return 3
        case .chime: return 4
        case .sparrows: return 2
        }
    }
    /// The seconds each variant has in the file.
    var slot: Double {
        switch self {
        case .chime: return 7.0
        case .owl, .sparrows: return 6.0
        }
    }
    /// The first turn begins this many seconds after the frame opens.
    static let first = 2.0
    static func moments(in scene: FrameScene) -> [FrameMoment] { allCases.filter { $0.scene == scene } }
    /// The file holding a scenery's moments (without the extension).
    static func file(in scene: FrameScene) -> String { "frame-\(scene.rawValue)-moments" }
    /// Where a variant begins in its scenery's file (seconds).
    func start(variant: Int) -> Double {
        var at = 0.0
        for moment in Self.moments(in: scene) {
            if moment == self { return at + Double(variant) * slot }
            at += Double(moment.variants) * moment.slot
        }
        return at
    }
    /// When in turn `k` it comes, and which variant; nil for a turn it skips.
    func occurrence(_ k: Int) -> (at: Double, variant: Int)? {
        guard k >= 0 else { return nil }
        let index = UInt32(Self.allCases.firstIndex(of: self) ?? 0)
        let a = Self.mix(index &* 0x9E37_79B9 ^ UInt32(truncatingIfNeeded: k) &* 0x85EB_CA6B)
        let b = Self.mix(a ^ 0x68E3_1DA4), c = Self.mix(b ^ 0xB529_7A4D)
        let unit = { (h: UInt32) in Double(h) / 4_294_967_296.0 }
        guard unit(a) >= 0.2 else { return nil }
        let at = Self.first + (Double(k) + 0.15 + 0.7 * unit(b)) * gap
        return (at, min(variants - 1, Int(unit(c) * Double(variants))))
    }
    /// The latest of its times after `from` and by `to` (a stretch shorter
    /// than a turn): how long ago, and which variant; nil if none came.
    func began(after from: Double, upTo to: Double) -> (ago: Double, variant: Int)? {
        guard to > from, to > Self.first else { return nil }
        let last = Int(((to - Self.first) / gap).rounded(.down))
        for k in stride(from: last, through: max(0, last - 1), by: -1) {
            if let hit = occurrence(k), hit.at > from, hit.at <= to { return (to - hit.at, hit.variant) }
        }
        return nil
    }
    /// A number's bits well stirred (so that the turns next to each other
    /// do not look alike).
    private static func mix(_ x: UInt32) -> UInt32 {
        var h = x
        h ^= h >> 16
        h = h &* 0x85EB_CA6B
        h ^= h >> 13
        h = h &* 0xC2B2_AE35
        h ^= h >> 16
        return h
    }
}

/// The clock tower's bell over the roofs: on the hour, as many strokes as
/// the hour on a twelve-hour clock, from seven in the morning to nine in the
/// evening; quiet at night.
enum FrameBell {
    static let file = "frame-roofs-bell"
    static func rings(in scene: FrameScene) -> Bool { scene == .roofs }
    /// For an hour of the clock (0 ..< 24).
    static func strokes(hour: Int) -> Int {
        guard (7...21).contains(hour) else { return 0 }
        let twelve = hour % 12
        return twelve == 0 ? 12 : twelve
    }
}

/// 多久以后熄屏: the frame stays lit, or goes dark after so many minutes
/// with nobody touching it (the iPhone may then lock itself as usual).
enum FrameSleep {
    /// 0: never.
    static let choices = [0, 15, 30, 60]
    static func choice(after minutes: Int, by delta: Int) -> Int {
        let index = choices.firstIndex(of: minutes) ?? 0
        let count = choices.count
        return choices[((index + delta) % count + count) % count]
    }
    /// The frame has been left alone long enough to go dark (`minute`: how
    /// long one of its minutes is; a test's are a second).
    static func isDue(minutes: Int, idle: TimeInterval, minute: TimeInterval = 60) -> Bool { minutes > 0 && idle >= Double(minutes) * minute }
}

/// A clock in a scenery (the tower's over the roofs, the station's at the
/// tram stop, the gondola's, the alarm clock by the fire): where its two
/// hands point for an hour of the day with its minutes (21.5 is half past
/// nine at night). Radians, clockwise from twelve.
enum FrameClock {
    static func hands(hour: Double) -> (hour: Double, minute: Double) {
        let turn = 2 * Double.pi
        let h = hour.truncatingRemainder(dividingBy: 12), m = hour - hour.rounded(.down)
        return ((h < 0 ? h + 12 : h) / 12 * turn, m * turn)
    }
}

/// What the Duo's cover shows when the system puts Zero EMU there (the lid
/// shut, or the Duo stood half open): it goes with what is inside. The
/// library inside, the library goes on on the cover; the console full screen
/// inside (a game, its own menu, a program), the console's shell, the game
/// asleep. What has a cover of its own keeps it either way: 铅笔盒 its lid,
/// 画框 its scenery, the camera (its album too) the cover's camera.
enum CoverFace: Equatable, Sendable {
    case library, shell, pencilLid, frame, camera
    /// What is open inside, as far as the cover goes.
    enum Inside: Equatable, Sendable { case console, pencilBox, pictureFrame, camera }
    static func shown(fullScreen: Bool, inside: Inside) -> CoverFace {
        switch inside {
        case .pencilBox: return .pencilLid
        case .pictureFrame: return .frame
        case .camera: return .camera
        case .console: return fullScreen ? .shell : .library
        }
    }
}

/// 画框 on the cover: with 画框 open inside, the cover is its scenery when
/// the system shows Zero EMU there, the Duo shut or stood half open like a
/// tent, unless a game is being played on the cover. Nothing else brings the
/// frame up (CoverFace). Plugged in, it stays lit; on the battery it lets the
/// iPhone lock as it would.
enum FrameStand {
    static func shows(frameOpen: Bool, onCover: Bool, playsOnCover: Bool) -> Bool {
        frameOpen && onCover && !playsOnCover
    }
    /// The frame's 多久以后熄屏 while it stands (0: never).
    static func sleepMinutes(charging: Bool, chosen: Int) -> Int { charging ? 0 : chosen }
}

/// The Duo left half open although the system calls its hinge closed. The
/// system's "closed" is its decision to use the cover, not an angle: a Duo
/// stood half open is reported closed at 30° to 85° and beyond (and its
/// angle goes on being reported), so the status alone cannot tell a Duo
/// stood up from one shut. This reads the angle: half open is at least
/// `enter` and holding still (within `steady`) for `settle` seconds; it
/// lasts until the angle is `leave` or less, or the status is no longer
/// closed. A lid on its way shut passes through without holding still. It
/// is kept in the trace (HingePosture); the cover does not choose by it.
struct HalfOpenRest: Sendable {
    /// Radians: 0 shut, π flat.
    static let enter = 0.50, leave = 0.26, steady = 0.10
    static let settle: TimeInterval = 0.6
    private(set) var rests = false
    /// The angle the hinge is holding at, and since when.
    private var held: (angle: Double, since: TimeInterval)?
    /// When `tick` should be called if nothing is reported before (a hinge
    /// holding still reports nothing).
    var due: TimeInterval? { rests ? nil : held.map { $0.since + Self.settle } }

    /// A report of the hinge. `closed`: the system's status is closed.
    @discardableResult mutating func report(closed: Bool, angle: Double?, at now: TimeInterval) -> Bool {
        guard closed, let angle else { rests = false; held = nil; return false }
        if rests {
            if angle <= Self.leave { rests = false; held = nil }
            return rests
        }
        guard angle >= Self.enter else { held = nil; return false }
        if let h = held, abs(angle - h.angle) <= Self.steady {
            if now - h.since >= Self.settle { rests = true }
        } else {
            held = (angle, now)
        }
        return rests
    }
    /// Time has passed with no report.
    @discardableResult mutating func tick(at now: TimeInterval) -> Bool {
        if !rests, let h = held, now - h.since >= Self.settle { rests = true }
        return rests
    }
}

// MARK: - 铁皮盒

/// 铁皮盒: small things that come as the shelf fills, each when the library
/// holds so many games of the player's own (imported; the demo card is not
/// one). Once a thing is in the box it stays, whatever leaves the shelf.
enum TinThing: String, CaseIterable, Identifiable, Sendable {
    case redFlower, lollipop, musicBox, gridPaper, schoolDays, playthings
    var id: String { rawValue }
    /// How many of the player's own games bring it.
    var games: Int {
        switch self {
        case .redFlower: return 1
        case .lollipop: return 3
        case .musicBox: return 5
        case .gridPaper: return 8
        case .schoolDays: return 12
        case .playthings: return 18
        }
    }
    /// The things `count` games bring.
    static func brought(byGames count: Int) -> [TinThing] { allCases.filter { $0.games <= count } }
    /// The first thing still to come after `count` games, and how many more games it wants.
    static func next(afterGames count: Int) -> (thing: TinThing, more: Int)? {
        guard let thing = allCases.first(where: { $0.games > count }) else { return nil }
        return (thing, thing.games - count)
    }
}

/// 即时存档 has numbered places, 存档位, for each game: 保存进度 and 读取进度
/// use the one chosen (the first until another is). The first is the file
/// there was before there were places ("<game>.state"); the others are
/// "<game>.s<N>.state". Without Pro the first five can be saved into.
enum StateSlots {
    static let most = 99
    static func fileName(base: String, slot: Int) -> String {
        slot <= 1 ? base + ".state" : base + ".s\(slot).state"
    }
    /// The place a file of the states folder is, for the game named `base`
    /// (nil: another game's, the state kept for 继续上次, or not a state).
    static func slot(ofFile name: String, base: String) -> Int? {
        if name == base + ".state" { return 1 }
        let head = base + ".s", tail = ".state"
        guard name.hasPrefix(head), name.hasSuffix(tail), name.count > head.count + tail.count else { return nil }
        let digits = name.dropFirst(head.count).dropLast(tail.count)
        guard digits.allSatisfy(\.isNumber), let slot = Int(digits), slot >= 2, slot <= most else { return nil }
        return slot
    }
    static func canSave(slot: Int, pro: Bool) -> Bool { pro || slot <= ProAccess.freeStateSlots }
    enum Step: Equatable {
        case to(Int)
        /// The first or the last: no further.
        case end
        /// The next one is Pro's and empty.
        case needsPro
    }
    /// One place on or back from `slot`. Without Pro the places past the
    /// free ones are passed over unless something is in them (`used`).
    static func step(from slot: Int, by delta: Int, pro: Bool, used: Set<Int>) -> Step {
        let next = slot + (delta > 0 ? 1 : -1)
        guard next >= 1, next <= most else { return .end }
        if pro || next <= ProAccess.freeStateSlots || used.contains(next) { return .to(next) }
        // Back down over empty ones only Pro has, to the nearest that can be stood on.
        if delta < 0 { return .to(max(ProAccess.freeStateSlots, used.filter { $0 < next }.max() ?? 1)) }
        if let further = used.filter({ $0 > next }).min() { return .to(further) }
        return .needsPro
    }
}

// MARK: - 铅笔盒

// What goes on 铅笔盒's lid and where (the store, the pictures and the
// screens: PencilBox.swift, PencilBoxLid.swift, PencilBoxProgram.swift).

/// One of the box's pictures: its file, its frame in points as drawn for
/// the 466 × 678-point lid, and how far its shadow falls (right, down).
struct PencilArt: Equatable, Sendable {
    let file: String
    let size: CGSize
    let shadow: CGSize
    /// Its shadow's picture (its own, or `shadowOf`'s: things of one shape share one).
    let shadowFile: String
    init(_ name: String, _ w: Double, _ h: Double, _ dx: Double, _ dy: Double, shadowOf: String? = nil) {
        file = name + ".png"
        size = CGSize(width: w, height: h)
        shadow = CGSize(width: dx, height: dy)
        shadowFile = (shadowOf ?? name) + "-shadow.png"
    }
    /// The lid as drawn (the cover's own portrait frame, its hinge on the left).
    static let lid = CGSize(width: 466, height: 678)
    static let letterA = PencilArt("pencilbox-letter-a", 82.71, 82.71, 3.6, 4.5)
    static let letterO = PencilArt("pencilbox-letter-o", 82.71, 82.71, 3.6, 4.5)
    static let letterE = PencilArt("pencilbox-letter-e", 82.71, 82.71, 3.6, 4.5)
    static let calendar = PencilArt("pencilbox-calendar", 98.75, 122.71, 3.4, 4.2)
    static let noteGrid = PencilArt("pencilbox-note-grid", 115.42, 123.33, 2.5, 3.1)
    static let notePlain = PencilArt("pencilbox-note-plain", 115.42, 123.33, 2.5, 3.1)
    static let photoFrame = PencilArt("pencilbox-photo-frame", 124.58, 100.62, 2.3, 2.8)
    static let magnetRed = PencilArt("pencilbox-magnet-red", 48.33, 48.33, 2.8, 3.5)
    static let magnetBlue = PencilArt("pencilbox-magnet-blue", 48.33, 48.33, 2.8, 3.5)
    static let magnetYellow = PencilArt("pencilbox-magnet-yellow", 48.33, 48.33, 2.8, 3.5)
    static let musicBox = PencilArt("pencilbox-music-box", 117.5, 81.46, 3.5, 4.4)
    static let lollipop = PencilArt("pencilbox-lollipop", 81.88, 141.88, 3.4, 4.3)
    static let flowerStamp = PencilArt("pencilbox-flower-stamp", 62.29, 80.21, 3.0, 3.8)
    static let bicycle = PencilArt("pencilbox-bicycle-badge", 93.33, 65.42, 2.1, 2.6)
    static let schoolBag = PencilArt("pencilbox-school-bag", 78.75, 82.71, 3.1, 3.9)
    static let ginkgoLeaf = PencilArt("pencilbox-ginkgo-leaf", 76.88, 90.83, 1.3, 1.7)
    // (more of the box's own things, on the tray's lower layers)
    static let shuttlecock = PencilArt("pencilbox-shuttlecock", 67.5, 84.58, 2.6, 3.3)
    static let pinwheel = PencilArt("pencilbox-pinwheel", 55.42, 91.25, 2.5, 3.1)
    static let rubberBall = PencilArt("pencilbox-rubber-ball", 70.21, 70.21, 3.5, 4.5)
    static let spinningTop = PencilArt("pencilbox-spinning-top", 64.17, 82.29, 3.1, 3.9)
    static let tinFrog = PencilArt("pencilbox-tin-frog", 92.5, 62.29, 2.6, 3.3)
    static let skippingRope = PencilArt("pencilbox-skipping-rope", 80.21, 74.58, 2.1, 2.6)
    static let marbleJar = PencilArt("pencilbox-marble-jar", 62.92, 80.21, 3.3, 4.2)
    static let tinPencilBox = PencilArt("pencilbox-tin-pencil-box", 88.96, 60.62, 3.0, 3.8)
    static let pencilStub = PencilArt("pencilbox-pencil-stub", 105.83, 31.04, 2.3, 2.9)
    static let thermos = PencilArt("pencilbox-thermos", 65.21, 97.92, 3.2, 4.0)
    static let enamelMug = PencilArt("pencilbox-enamel-mug", 76.88, 66.25, 3.3, 4.1)
    static let sodaBottle = PencilArt("pencilbox-soda-bottle", 41.67, 101.04, 3.1, 3.9)
    static let biscuitTin = PencilArt("pencilbox-biscuit-tin", 83.75, 67.5, 3.5, 4.4)
    static let exerciseBook = PencilArt("pencilbox-exercise-book", 66.25, 80.0, 2.3, 2.8)
    static let inkBottle = PencilArt("pencilbox-ink-bottle", 59.58, 74.17, 3.3, 4.1)
    static let abacus = PencilArt("pencilbox-abacus", 93.12, 63.33, 2.8, 3.5)
    static let rotaryPhone = PencilArt("pencilbox-rotary-phone", 96.67, 71.88, 3.1, 3.9)
    static let tape = PencilArt("pencilbox-tape", 43.33, 23.33, 0.6, 0.8)
    /// 11-15: the woven ZERO tag (it was sewn on the canvas lid; now one of the box's things, on the lid or not).
    static let zeroTag = PencilArt("pencilbox-zero-tag", 100.83, 38.75, 1.0, 1.3)
    /// A print's window (where its picture shows) and a note's writing, from
    /// the picture's middle, in points.
    static let photoWindow = CGRect(x: -42.9, y: -31.2, width: 85.8, height: 62.4)
    static let noteArea = CGRect(x: -36.4, y: -35.1, width: 76.4, height: 76.4)
    /// The magnet that holds a print or a note, from the picture's middle.
    static let photoMagnet = CGPoint(x: 0, y: -35)
    static let noteMagnet = CGPoint(x: 0, y: -41)
    /// The tape over a leaf's stem, from the leaf's middle, and its turn.
    static let leafTape = CGPoint(x: 5, y: 30)
    static let leafTapeTurn = -0.62
    /// 11-15: a postcard of one of 画框's sceneries, its picture side or its back (the postcode's six boxes,
    /// a stamp with the scenery in small, a round postmark, the address's lines); all four share one shadow.
    /// The card is 132 x 88 points, with 10 points of room round it.
    static func postcard(_ scene: FrameScene, back: Bool = false) -> PencilArt {
        PencilArt("pencilbox-postcard-\(scene.rawValue)" + (back ? "-back" : ""), 152.08, 107.92, 2.2, 2.7, shadowOf: "pencilbox-postcard")
    }
    /// The magnet that holds a postcard, from its middle (beside the postcode's boxes on its back).
    static let postcardMagnet = CGPoint(x: 12, y: -38)
}

/// The box's own things (drawn), each with what brings it.
enum PencilThing: String, CaseIterable, Identifiable, Codable, Sendable {
    case letterA, letterO, letterE, calendar, zeroTag, flowerStamp, lollipop, musicBox, bicycle, schoolBag, ginkgoLeaf
    /// (11-16: old everyday things, on the tray's second and third layers)
    case shuttlecock, pinwheel, rubberBall, spinningTop, tinFrog, skippingRope, marbleJar, tinPencilBox, pencilStub, thermos, enamelMug, sodaBottle, biscuitTin, exerciseBook, inkBottle, abacus, rotaryPhone
    var id: String { rawValue }
    var art: PencilArt {
        switch self {
        case .letterA: return .letterA
        case .letterO: return .letterO
        case .letterE: return .letterE
        case .calendar: return .calendar
        case .zeroTag: return .zeroTag
        case .flowerStamp: return .flowerStamp
        case .lollipop: return .lollipop
        case .musicBox: return .musicBox
        case .bicycle: return .bicycle
        case .schoolBag: return .schoolBag
        case .ginkgoLeaf: return .ginkgoLeaf
        case .shuttlecock: return .shuttlecock
        case .pinwheel: return .pinwheel
        case .rubberBall: return .rubberBall
        case .spinningTop: return .spinningTop
        case .tinFrog: return .tinFrog
        case .skippingRope: return .skippingRope
        case .marbleJar: return .marbleJar
        case .tinPencilBox: return .tinPencilBox
        case .pencilStub: return .pencilStub
        case .thermos: return .thermos
        case .enamelMug: return .enamelMug
        case .sodaBottle: return .sodaBottle
        case .biscuitTin: return .biscuitTin
        case .exerciseBook: return .exerciseBook
        case .inkBottle: return .inkBottle
        case .abacus: return .abacus
        case .rotaryPhone: return .rotaryPhone
        }
    }
    var title: String {
        switch self {
        case .letterA: return String(localized: "字母 a")
        case .letterO: return String(localized: "字母 o")
        case .letterE: return String(localized: "字母 e")
        case .calendar: return String(localized: "撕页日历")
        case .zeroTag: return String(localized: "ZERO 布标")
        case .flowerStamp: return String(localized: "小红花印章")
        case .lollipop: return String(localized: "棒棒糖")
        case .musicBox: return String(localized: "八音盒")
        case .bicycle: return String(localized: "自行车徽章")
        case .schoolBag: return String(localized: "小书包")
        case .ginkgoLeaf: return String(localized: "银杏叶")
        case .shuttlecock: return String(localized: "毽子")
        case .pinwheel: return String(localized: "纸风车")
        case .rubberBall: return String(localized: "小皮球")
        case .spinningTop: return String(localized: "陀螺")
        case .tinFrog: return String(localized: "铁皮青蛙")
        case .skippingRope: return String(localized: "跳绳")
        case .marbleJar: return String(localized: "一罐玻璃弹珠")
        case .tinPencilBox: return String(localized: "小铁皮文具盒")
        case .pencilStub: return String(localized: "铅笔头")
        case .thermos: return String(localized: "暖水瓶")
        case .enamelMug: return String(localized: "搪瓷杯")
        case .sodaBottle: return String(localized: "玻璃瓶汽水")
        case .biscuitTin: return String(localized: "饼干铁盒")
        case .exerciseBook: return String(localized: "作业本")
        case .inkBottle: return String(localized: "墨水")
        case .abacus: return String(localized: "算盘")
        case .rotaryPhone: return String(localized: "转盘电话")
        }
    }
    /// Held to the lid by a magnet of its own (the plastic letters).
    var isMagnet: Bool { self == .letterA || self == .letterO || self == .letterE }
    /// What it is, or does, on the lid.
    var use: String {
        switch self {
        case .letterA, .letterO, .letterE: return String(localized: "塑料字母磁贴，想怎么摆都行。")
        case .calendar: return String(localized: "每天自己翻到今天。")
        case .zeroTag: return String(localized: "一块织出来的布标，想贴就贴上。")
        case .flowerStamp: return String(localized: "游戏笔记里也能用它盖小红花。")
        case .lollipop: return String(localized: "相册编辑里也有它的贴画。")
        case .musicBox: return String(localized: "在盒盖上点一下，放片子里那段小曲。")
        case .bicycle: return String(localized: "一枚老铁皮徽章。")
        case .schoolBag: return String(localized: "上学背的小书包。")
        case .ginkgoLeaf: return String(localized: "秋天捡的银杏叶，用胶带贴着。")
        case .shuttlecock: return String(localized: "课间踢的，看谁踢得多。")
        case .pinwheel: return String(localized: "举着跑起来它才转。")
        case .rubberBall: return String(localized: "拍一下，弹得老高。")
        case .spinningTop: return String(localized: "抽一鞭子，能转好久。")
        case .tinFrog: return String(localized: "上紧发条，一蹦一蹦地跳。")
        case .skippingRope: return String(localized: "两头是木头把手。")
        case .marbleJar: return String(localized: "赢来的都攒在这只罐子里。")
        case .tinPencilBox: return String(localized: "盒子里的小盒子。")
        case .pencilStub: return String(localized: "用短了的铅笔，套上笔套接着用。")
        case .thermos: return String(localized: "灌满开水，能热到第二天早上。")
        case .enamelMug: return String(localized: "磕掉了两块瓷，照样用。")
        case .sodaBottle: return String(localized: "橘子味的，喝完瓶子要还回去。")
        case .biscuitTin: return String(localized: "打开一看，里面多半是针线。")
        case .exerciseBook: return String(localized: "封面上要写姓名和班级。")
        case .inkBottle: return String(localized: "蓝黑墨水，灌钢笔用的。")
        case .abacus: return String(localized: "上面一颗当五，下面一颗当一。")
        case .rotaryPhone: return String(localized: "拨一个号码要转上一圈。")
        }
    }
    /// The tin's thing that brings it (nil: in the box from the start).
    var source: TinThing? {
        switch self {
        case .letterA, .letterO, .letterE, .calendar, .zeroTag: return nil
        case .rubberBall, .spinningTop, .skippingRope, .marbleJar, .tinPencilBox, .pencilStub, .thermos, .enamelMug, .sodaBottle, .biscuitTin, .abacus, .rotaryPhone: return nil
        case .flowerStamp: return .redFlower
        case .lollipop: return .lollipop
        case .musicBox: return .musicBox
        case .bicycle, .schoolBag, .ginkgoLeaf: return .schoolDays
        case .exerciseBook, .inkBottle, .shuttlecock, .pinwheel, .tinFrog: return .playthings
        }
    }
}

// MARK: - 铅笔盒: a thing touched (11-17)

/// How a thing, or a part of it, is placed for a moment: moved (points of its picture as the lid has it; down is
/// positive), turned (radians) and stretched, about a point of its picture.
struct PencilPartPose: Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    var angle = 0.0
    var sx = 1.0
    var sy = 1.0
    static let still = PencilPartPose()
}

/// A thing at a moment of its play: all of it, and each of its moving parts.
struct PencilPose: Equatable, Sendable {
    var whole = PencilPartPose.still
    var parts: [PencilPartPose] = []
    static let still = PencilPose()
    func part(_ index: Int?) -> PencilPartPose {
        guard let index, index >= 0, index < parts.count else { return .still }
        return parts[index]
    }
}

/// One layer of a thing drawn in layers, bottom first: the part that moves it (nil: it keeps still), the point
/// it turns about (points of the picture), and whether it shows only through the thing's window (the marbles in
/// their jar).
struct PencilLayer: Equatable, Sendable {
    let file: String
    var part: Int? = nil
    var pivot = CGPoint.zero
    var windowed = false
}

/// The moments of the plays (seconds from the touch): what moves and what is heard keep to the same ones.
enum PencilPlayTimes {
    /// 小皮球: off the lid, and down on it three times, each bounce lower.
    static let ball = [0.0, 0.36, 0.62, 0.78]
    static let ballHeights = [22.0, 10, 4]
    /// 铁皮青蛙: it crouches, then two hops (from, to, how high).
    static let frogCrouch = 0.07
    static let frogHops: [(from: Double, to: Double, height: Double)] = [(0.07, 0.37, 16), (0.41, 0.63, 8)]
    /// 转盘电话: two bursts of ringing, the clapper's strikes a second.
    static let rings: [(from: Double, to: Double)] = [(0, 0.42), (0.58, 1.0)]
    static let ringHz = 24.0
    /// 一罐玻璃弹珠: the two lots of marbles up and down again (from, to, how high), each with a smaller bounce after.
    static let marbles: [[(from: Double, to: Double, height: Double)]] = [[(0.02, 0.34, 7), (0.34, 0.5, 2.2), (0.5, 0.58, 0.7)], [(0.06, 0.42, 5), (0.42, 0.56, 1.6)]]
    /// 暖水瓶: its cup up, down, and a little hop more. 饼干铁盒: its lid likewise.
    static let cup: [(from: Double, to: Double, height: Double)] = [(0, 0.34, 9), (0.34, 0.46, 1.8)]
    static let tinLid: [(from: Double, to: Double, height: Double)] = [(0, 0.26, 7), (0.26, 0.37, 1.6)]
    /// 毽子: kicked up, down, and a small bounce.
    static let kick: [(from: Double, to: Double, height: Double)] = [(0.02, 0.54, 30), (0.54, 0.68, 3)]
    /// 跳绳: two swings of the rope, then its handles knock twice.
    static let rope = [0.0, 0.22]
    static let ropeHandles = [0.5, 0.57]
    /// 纸风车: how long its sails turn, and how many times round.
    static let wheel = 1.4
    static let wheelTurns = 2.0
    /// The moment the sails have come `part` of the way round (they start fast and slow to a stop).
    static func wheelMoment(_ part: Double) -> Double { (1 - pow(1 - max(0, min(1, part)), 1.0 / 3)) * wheel }
    /// 搪瓷杯 rocks, 墨水 sways: swings a second (each half swing a knock, or a gulp of the ink).
    static let mugHz = 4.2
    static let inkHz = 3.6
    /// 小铁皮文具盒: the pencils inside knock about.
    static let rattle = [0.0, 0.045, 0.09, 0.14, 0.185, 0.24, 0.31, 0.39]
    /// 铅笔头: strokes a second, there and back.
    static let scribbleHz = 6.5
    /// 作业本: its cover lifted by this moment, held, coming down from this one, shut at this.
    static let cover = (open: 0.24, hold: 0.32, shut: 0.5)
    /// 算盘: its beads knock.
    static let beads = [0.0, 0.03, 0.062, 0.09, 0.125, 0.155, 0.19, 0.235, 0.28, 0.33, 0.39, 0.46]
}

/// The curves the plays are made of.
enum PencilMotion {
    /// 1, then down to 0 over the last `fade` seconds: everything is back where it was when the play ends.
    static func settle(_ t: Double, _ length: Double, fade: Double = 0.14) -> Double {
        let left = (length - t) / fade
        return left >= 1 ? 1 : (left <= 0 ? 0 : left * left * (3 - 2 * left))
    }
    /// A hop between two moments: 0 at both, `height` half way.
    static func hop(_ t: Double, _ from: Double, _ to: Double, _ height: Double) -> Double {
        guard t > from, t < to else { return 0 }
        let u = (t - from) / (to - from)
        return 4 * height * u * (1 - u)
    }
    static func hops(_ t: Double, _ list: [(from: Double, to: Double, height: Double)]) -> Double {
        list.reduce(0) { $0 + hop(t, $1.from, $1.to, $1.height) }
    }
    /// A swing dying away.
    static func swing(_ t: Double, hz: Double, decay: Double, phase: Double = 0) -> Double {
        sin(2 * Double.pi * hz * t + phase) * exp(-decay * t)
    }
    /// 0 → 1 → 0 round `at`, `width` seconds wide.
    static func bump(_ t: Double, at: Double, width: Double) -> Double {
        let u = abs(t - at) / (width / 2)
        return u >= 1 ? 0 : (1 - u * u) * (1 - u * u)
    }
    /// 0 before `from`, 1 after `to`, eased between.
    static func ease(_ t: Double, _ from: Double, _ to: Double) -> Double {
        let u = max(0, min(1, (t - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }
}

/// What one of the box's things does when it is touched (11-17, the old everyday things): for `length` seconds it
/// moves, all of it or a part, and a sound of its own is heard (ConsoleSoundSynth makes it; its moments are
/// PencilPlayTimes's, as the movement's are).
struct PencilPlay: Sendable {
    let sound: ConsoleSound
    let length: Double
    /// What all of it turns and stretches about (points of its picture).
    let pivot: CGPoint
    /// Drawn in layers (bottom first), or, with none, its one picture.
    var layers: [PencilLayer] = []
    /// The picture of its window (for its `windowed` layers).
    var window: String? = nil
    let pose: @Sendable (Double) -> PencilPose
    /// Where it is `t` seconds after the touch: before it and from its end on, at rest.
    func placed(at t: Double) -> PencilPose { t > 0 && t < length ? pose(t) : .still }

    private typealias M = PencilMotion
    private typealias T = PencilPlayTimes
    /// A picture's middle, or a point of the drawing in it: the drawing's own origin in the picture (points),
    /// `k` picture points a drawn unit, and the point as drawn.
    private static func at(_ ox: Double, _ oy: Double, _ k: Double = 1, _ x: Double = 0, _ y: Double = 0) -> CGPoint {
        CGPoint(x: ox + x * k, y: oy + y * k)
    }

    static let all: [PencilThing: PencilPlay] = [
        // the jar is jolted; the marbles in it jump, the two lots a moment apart, and come down with a bounce
        .marbleJar: PencilPlay(sound: .marbles, length: 0.7, pivot: at(31.46, 39.17, 2.4, 0, 13),
                               layers: [PencilLayer(file: "pencilbox-marble-jar-back.png"),
                                        PencilLayer(file: "pencilbox-marble-jar-ma.png", part: 0, windowed: true),
                                        PencilLayer(file: "pencilbox-marble-jar-mb.png", part: 1, windowed: true),
                                        PencilLayer(file: "pencilbox-marble-jar-front.png")],
                               window: "pencilbox-marble-jar-mask.png") { t in
            let s = M.settle(t, 0.7)
            var pose = PencilPose()
            pose.whole.y = -M.hop(t, 0, 0.2, 3.5)
            pose.whole.angle = 0.035 * M.swing(t, hz: 7, decay: 7) * s
            pose.parts = [PencilPartPose(x: 0.9 * M.swing(t, hz: 9, decay: 6) * s, y: -M.hops(t, T.marbles[0])),
                          PencilPartPose(x: -0.9 * M.swing(t, hz: 9, decay: 6) * s, y: -M.hops(t, T.marbles[1]))]
            return pose
        },
        // it rings twice: the handset shakes on its cradle, the body a little under it
        .rotaryPhone: PencilPlay(sound: .phoneRing, length: 1.1, pivot: at(52.29, 35.83, 2.4, 0, 11),
                                 layers: [PencilLayer(file: "pencilbox-rotary-phone-body.png"),
                                          PencilLayer(file: "pencilbox-rotary-phone-set.png", part: 0, pivot: at(52.29, 35.83, 2.4, 0, -8))]) { t in
            var ringing = 0.0
            for ring in T.rings {
                let coming: Double = min(1, max(0, (t - ring.from) / 0.03))
                let going: Double = min(1, max(0, (ring.to - t) / 0.05))
                ringing += coming * going
            }
            let beat: Double = sin(2 * Double.pi * T.ringHz * t)
            var pose = PencilPose()
            pose.whole.x = 0.7 * beat * ringing
            let lifted: Double = (-2.0 - 0.8 * abs(beat)) * ringing
            pose.parts = [PencilPartPose(y: lifted, angle: 0.07 * beat * ringing)]
            return pose
        },
        // it crouches and hops twice, flattening a little each time it lands
        .tinFrog: PencilPlay(sound: .tinFrog, length: 0.8, pivot: at(42.08, 31.25, 2.3, 0, 9.6)) { t in
            var pose = PencilPose()
            let up = M.hops(t, T.frogHops)
            var flat = 0.12 * M.bump(t, at: T.frogCrouch / 2, width: T.frogCrouch)
            flat += 0.1 * M.bump(t, at: T.frogHops[0].to + 0.015, width: 0.07)
            flat += 0.07 * M.bump(t, at: T.frogHops[1].to + 0.015, width: 0.07)
            pose.whole.y = -up
            pose.whole.sy = 1 - flat + 0.004 * up
            pose.whole.sx = 1 + flat * 0.6
            pose.whole.angle = -0.004 * up
            return pose
        },
        // whipped: it leans and goes round on its point, steadying
        .spinningTop: PencilPlay(sound: .topSpin, length: 1.3, pivot: at(32.08, 39.17, 2.4, 0, 14.2)) { t in
            let s = M.settle(t, 1.3, fade: 0.25)
            var pose = PencilPose()
            pose.whole.angle = 0.2 * M.swing(t, hz: 2.4, decay: 1.6) * s
            let round: Double = sin(2 * Double.pi * 1.2 * t) * exp(-1.6 * t)
            let shimmer: Double = (0.5 + 0.5 * sin(2 * Double.pi * 14 * t)) * exp(-1.2 * t)
            pose.whole.x = 3.2 * round * s
            pose.whole.sx = 1 - 0.035 * shimmer * s
            return pose
        },
        // it bounces three times, each lower, squashed as it lands
        .rubberBall: PencilPlay(sound: .ballBounce, length: 0.95, pivot: at(35.0, 35.21, 2.4, 0, 10.5)) { t in
            var pose = PencilPose()
            var up = 0.0
            var flat = 0.12 * M.bump(t, at: 0, width: 0.1)
            for (index, height) in T.ballHeights.enumerated() {
                up += M.hop(t, T.ball[index], T.ball[index + 1], height)
                flat += (0.14 - 0.045 * Double(index)) * M.bump(t, at: T.ball[index + 1] + 0.01, width: 0.09)
            }
            pose.whole.y = -up
            pose.whole.sy = 1 - flat
            pose.whole.sx = 1 + flat * 0.7
            return pose
        },
        // kicked up high; it leans over in the air and comes down on its washers
        .shuttlecock: PencilPlay(sound: .shuttleKick, length: 0.8, pivot: at(33.75, 46.25, 2.3, 0, 13)) { t in
            var pose = PencilPose()
            pose.whole.y = -M.hops(t, T.kick)
            let flown: Double = min(1, t / T.kick[0].to)
            pose.whole.angle = 0.3 * sin(2 * Double.pi * flown)
            pose.whole.sy = 1 - 0.06 * M.bump(t, at: T.kick[0].to + 0.01, width: 0.08)
            return pose
        },
        // its sails go round twice, fast at first, and stop where they began
        .pinwheel: PencilPlay(sound: .pinwheel, length: T.wheel, pivot: at(27.71, 39.58, 2.4, 0, 18),
                              layers: [PencilLayer(file: "pencilbox-pinwheel-stick.png"),
                                       PencilLayer(file: "pencilbox-pinwheel-wheel.png", part: 0, pivot: at(27.71, 39.58, 2.4, 0, -5))]) { t in
            let left = 1 - t / T.wheel
            var pose = PencilPose()
            pose.whole.angle = 0.03 * M.swing(t, hz: 3, decay: 3) * M.settle(t, T.wheel)
            let turned: Double = 2 * Double.pi * T.wheelTurns * (1 - left * left * left)
            pose.parts = [PencilPartPose(angle: turned)]
            return pose
        },
        // swung twice
        .skippingRope: PencilPlay(sound: .ropeSwing, length: 0.75, pivot: at(45.0, 47.92)) { t in
            let s = M.settle(t, 0.75)
            var pose = PencilPose()
            pose.whole.angle = 0.16 * M.swing(t, hz: 2.7, decay: 3.2) * s
            pose.whole.y = -M.hop(t, T.rope[0], T.rope[0] + 0.18, 4) - M.hop(t, T.rope[1], T.rope[1] + 0.18, 3)
            return pose
        },
        // shaken from side to side
        .tinPencilBox: PencilPlay(sound: .tinRattle, length: 0.55, pivot: at(44.58, 28.54)) { t in
            let s = M.settle(t, 0.55)
            var pose = PencilPose()
            pose.whole.x = 3.2 * M.swing(t, hz: 11, decay: 5.5) * s
            pose.whole.angle = 0.03 * M.swing(t, hz: 11, decay: 5.5, phase: 1) * s
            return pose
        },
        // a few strokes on the paper, there and back
        .pencilStub: PencilPlay(sound: .scribble, length: 0.6, pivot: at(52.29, 15.62)) { t in
            let s = M.settle(t, 0.6) * M.ease(t, 0, 0.04)
            var pose = PencilPose()
            let stroke: Double = 2 * Double.pi * T.scribbleHz * t
            pose.whole.x = 3.0 * sin(stroke) * s
            pose.whole.y = 1.0 * sin(stroke * 2) * s
            pose.whole.angle = 0.03 * sin(stroke + 0.8) * s
            return pose
        },
        // the stopper lets go: its cup jumps off and drops back on
        .thermos: PencilPlay(sound: .corkPop, length: 0.6, pivot: at(26.88, 53.54, 2.3, 0, 15),
                             layers: [PencilLayer(file: "pencilbox-thermos-body.png"),
                                      PencilLayer(file: "pencilbox-thermos-cup.png", part: 0, pivot: at(26.88, 53.54, 2.3, 0, -13.4))]) { t in
            var pose = PencilPose()
            pose.whole.sy = 1 - 0.03 * M.bump(t, at: 0.03, width: 0.08)
            let tipped: Double = t < T.cup[0].to ? 0.12 * sin(Double.pi * t / T.cup[0].to) : 0
            pose.parts = [PencilPartPose(y: -M.hops(t, T.cup), angle: tipped)]
            return pose
        },
        // knocked: it rocks on its foot and stands still again
        .enamelMug: PencilPlay(sound: .enamelClang, length: 0.9, pivot: at(31.25, 33.12, 2.5, 0, 9.2)) { t in
            var pose = PencilPose()
            pose.whole.angle = 0.13 * M.swing(t, hz: T.mugHz, decay: 3.6) * M.settle(t, 0.9)
            return pose
        },
        // shaken up and down; it stands still while the fizz dies away
        .sodaBottle: PencilPlay(sound: .sodaFizz, length: 0.8, pivot: at(20.83, 54.17, 2.4, 0, 15.6)) { t in
            let s = M.settle(t, 0.8)
            var pose = PencilPose()
            pose.whole.y = 2.6 * M.swing(t, hz: 9, decay: 6) * s
            pose.whole.angle = 0.025 * M.swing(t, hz: 9, decay: 6, phase: 0.7) * s
            return pose
        },
        // its lid springs up and clatters back on
        .biscuitTin: PencilPlay(sound: .tinLid, length: 0.55, pivot: at(41.67, 33.75, 2.5, 0, 9.4),
                                layers: [PencilLayer(file: "pencilbox-biscuit-tin-body.png"),
                                         PencilLayer(file: "pencilbox-biscuit-tin-lid.png", part: 0, pivot: at(41.67, 33.75, 2.5, 0, -6.1))]) { t in
            var pose = PencilPose()
            pose.whole.y = 0.6 * M.bump(t, at: T.tinLid[0].to + 0.02, width: 0.06)
            let tipped: Double = t < T.tinLid[0].to ? 0.09 * sin(Double.pi * t / T.tinLid[0].to) : 0
            pose.parts = [PencilPartPose(y: -M.hops(t, T.tinLid), angle: tipped)]
            return pose
        },
        // its cover lifted half open (the ruled page under it), and let fall shut
        .exerciseBook: PencilPlay(sound: .pageFlip, length: 0.6, pivot: at(32.92, 40.0),
                                  layers: [PencilLayer(file: "pencilbox-exercise-book-pages.png"),
                                           PencilLayer(file: "pencilbox-exercise-book-cover.png", part: 0, pivot: at(32.92, 40.0, 2.6, -9.4, -0.2))]) { t in
            let open = M.ease(t, 0, T.cover.open) * (1 - M.ease(t, T.cover.hold, T.cover.shut))
            var pose = PencilPose()
            pose.parts = [PencilPartPose(sx: 1 - 0.62 * open)]
            return pose
        },
        // the bottle sways, the ink in it going from side to side
        .inkBottle: PencilPlay(sound: .inkGlug, length: 0.85, pivot: at(29.79, 39.17, 2.5, 0, 10)) { t in
            var pose = PencilPose()
            pose.whole.angle = 0.11 * M.swing(t, hz: T.inkHz, decay: 3.4) * M.settle(t, 0.85)
            return pose
        },
        // its beads jump on their rods, every other rod's the other way
        .abacus: PencilPlay(sound: .beads, length: 0.65, pivot: at(46.67, 31.67),
                            layers: [PencilLayer(file: "pencilbox-abacus-frame.png"),
                                     PencilLayer(file: "pencilbox-abacus-ba.png", part: 0),
                                     PencilLayer(file: "pencilbox-abacus-bb.png", part: 1),
                                     PencilLayer(file: "pencilbox-abacus-beam.png")]) { t in
            let s = M.settle(t, 0.65)
            var pose = PencilPose()
            pose.whole.angle = 0.02 * M.swing(t, hz: 8, decay: 5) * s
            pose.parts = [PencilPartPose(y: 1.6 * M.swing(t, hz: 8, decay: 5) * s),
                          PencilPartPose(y: 1.6 * M.swing(t, hz: 8, decay: 5, phase: 2.5) * s)]
            return pose
        },
    ]
}

extension PencilThing {
    /// What it does when it is touched (nil: nothing of its own).
    var play: PencilPlay? { PencilPlay.all[self] }
}

/// Where a touch plays one of the old everyday things: on the lid, always, and in its well. In its well it then
/// goes onto the lid as every other thing does (`staysInTray` false), or stays there to be touched again, the
/// lid a held touch's menu away (true).
enum PencilPlayRule {
    static let staysInTray = false
}

/// The magnets that hold a print or a note.
enum PencilMagnet: String, Codable, CaseIterable, Sendable {
    case red, blue, yellow
    var art: PencilArt {
        switch self {
        case .red: return .magnetRed
        case .blue: return .magnetBlue
        case .yellow: return .magnetYellow
        }
    }
}

/// One thing on the lid, or waiting in the tray: the box's own, a photo, or
/// a note (written here, or a page of 游戏笔记). Where it is: its middle as a
/// part of the lid's width and height; its turn (radians) and size; which is
/// over which.
struct PencilPiece: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case thing, photo, note, tool, shaving, postcard }
    var id: UUID
    var kind: Kind
    var thing: PencilThing?
    /// One of the box's tools (the ruler, a pencil), or the pencil a curl of shaving came off.
    var tool: PencilTool? = nil
    /// Which of the drawn curls a shaving is.
    var shape: Int? = nil
    var x: Double
    var y: Double
    var angle: Double
    var scale: Double
    var z: Int
    var magnet: PencilMagnet?
    /// A note's paper: squared (once the tin has it) or ruled.
    var grid: Bool?
    /// 11-15: a postcard's scenery (画框's), and whether it lies turned over (its back up).
    /// (11-16: no scenery: a postcard made here of a picture of one's own, which may be thrown away.)
    var scene: FrameScene? = nil
    var back: Bool? = nil
    /// 11-16: a postcard made one's own (PencilCard). A picture of one's own on its front (kept beside the box,
    /// card-<id>.jpg); on its back the words along its lines and its postcode's digits; another stamp: a
    /// scenery's, or a picture of one's own (stamp-<id>.jpg).
    var ownFront: Bool? = nil
    /// 11-22: where that picture sits in the front's window, as it was dragged and pinched on the card: the
    /// picture's point at the window's middle (0…1 across, 0…1 down) and how far it is brought in (1: the window
    /// just filled). Nil: its middle, filling the window (PencilCardPlace).
    var frontPlace: [Double]? = nil
    var words: String? = nil
    var postcode: String? = nil
    var stampScene: FrameScene? = nil
    var ownStamp: Bool? = nil
    var art: PencilArt {
        switch kind {
        case .thing: return thing?.art ?? .letterA
        case .photo: return .photoFrame
        case .note: return grid == true ? .noteGrid : .notePlain
        case .tool: return (tool ?? .ruler).lidArt
        case .shaving: return PencilToolArt.lidShaving(tool ?? .green, shape ?? 0)
        case .postcard: return .postcard(scene ?? .campfire, back: back == true)
        }
    }
    var title: String {
        switch kind {
        case .thing: return thing?.title ?? ""
        case .photo: return String(localized: "照片")
        case .note: return String(localized: "便条")
        case .tool: return tool?.title ?? ""
        case .shaving: return String(localized: "木屑")
        case .postcard: return String(localized: "明信片")
        }
    }
    var ownFile: String? {
        switch kind {
        case .thing, .tool, .shaving, .postcard: return nil
        case .photo: return "photo-\(id.uuidString).jpg"
        case .note: return "note-\(id.uuidString).json"
        }
    }
    /// One's own: a photo, a note, a postcard (off the lid, tucked under the strap).
    var isOwn: Bool { kind == .photo || kind == .note || kind == .postcard }
    /// A postcard made here of a picture of one's own (not one 画框 sent).
    var isMadeCard: Bool { kind == .postcard && scene == nil }
    /// 11-17: one made here with nothing on it yet: no picture, no stamp chosen, nothing written.
    var isBlankCard: Bool {
        isMadeCard && ownFront != true && ownStamp != true && stampScene == nil && (words ?? "").isEmpty && (postcode ?? "").isEmpty
    }
}

/// 11-22: where a picture of one's own sits in a postcard front's window (PencilPiece.frontPlace), and the part of
/// it the window shows: never past the picture's edge, from the window just filled to four times as close.
enum PencilCardPlace {
    static let nearest = 4.0
    static let middle = [0.5, 0.5, 1.0]
    /// The part of a picture `size` (pixels) the window shows for `place` ([x, y, how close]).
    static func part(of size: CGSize, place: [Double]?) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let p = (place?.count ?? 0) >= 3 ? place! : middle
        let aspect = PencilCard.frontWindow.width / PencilCard.frontWindow.height
        let close = min(nearest, max(1, p[2]))
        var w = size.width, h = size.height
        if w / h > aspect { w = h * aspect } else { h = w / aspect }
        w /= close; h /= close
        let x = min(max(p[0] * size.width - w / 2, 0), size.width - w)
        let y = min(max(p[1] * size.height - h / 2, 0), size.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    /// `place` as far as the picture allows (its point kept where the window stays on the picture).
    static func kept(_ place: [Double], size: CGSize) -> [Double] {
        let part = part(of: size, place: place)
        guard part.width > 0 else { return middle }
        return [part.midX / size.width, part.midY / size.height, min(nearest, max(1, place.count >= 3 ? place[2] : 1))]
    }
    /// `place` after a finger moved the picture `moved` (points) in a window `window` (points) wide and high, and
    /// pinched it `pinched` times as close.
    static func moved(_ place: [Double]?, size: CGSize, window: CGSize, moved: CGSize, pinched: Double) -> [Double] {
        let p = (place?.count ?? 0) >= 3 ? place! : middle
        let close = min(nearest, max(1, p[2] * pinched))
        let part = part(of: size, place: [p[0], p[1], close])
        guard part.width > 0, window.width > 0 else { return p }
        // (points to the picture's pixels: the window shows `part`)
        let k = part.width / window.width
        return kept([(part.midX - moved.width * k) / size.width, (part.midY - moved.height * k) / size.height, close], size: size)
    }
}

/// 11-16: a postcard's two faces, for what is put on them (a postcard made one's own): in points of its picture
/// (PencilArt.postcard, 152.08 × 107.92, the card 132 × 88 in its middle), from the picture's middle. The front's
/// picture; on the back the postcode's six boxes, the stamp's little picture inside its perforated edge (the
/// stamp lies a little aslant) and the three lines for words. And what may be written: a postcode's digits, six
/// at most; the words as the three lines hold them.
enum PencilCard {
    /// Its picture (with the room its shadow takes) and the card itself, in a lid's points.
    static let size = CGSize(width: 152.08, height: 107.92)
    static let face = CGSize(width: 132.5, height: 88.3)
    static let frontWindow = CGRect(x: -60, y: -38, width: 120, height: 76)
    static let boxes = 6
    static let boxSide = 8.2
    /// A postcode box's middle.
    static func box(_ index: Int) -> CGPoint { CGPoint(x: -53.94 + 10.1 * Double(index), y: -31.86) }
    static let stampMiddle = CGPoint(x: 44.27, y: -20.73)
    static let stampPicture = CGSize(width: 20.6, height: 25.6)
    /// Degrees, clockwise.
    static let stampTurn = 2.2
    /// The three lines: where each begins, how long it is, how far down; the size of the words on them.
    static let lineStart = 14.9
    static let lineLength = 43.1
    static let lineYs: [Double] = [1.8, 15.88, 29.96]
    static let wordSize = 7.0
    /// How much of a line a character takes, in characters of full width.
    static func width(of character: Character) -> Double {
        if character == " " { return 0.32 }
        guard let scalar = character.unicodeScalars.first else { return 0 }
        return scalar.value < 0x2E80 ? 0.56 : 1
    }
    static var perLine: Double { lineLength / wordSize }
    /// The words as the lines hold them: a line filled, the next begun; a new line where one was typed; what the
    /// last line cannot hold is left off.
    static func lines(of words: String) -> [String] {
        var lines: [String] = [], line = "", used = 0.0
        for character in words {
            let wide = width(of: character)
            if character.isNewline || used + wide > perLine + 0.001 {
                lines.append(line); line = ""; used = 0
                if lines.count == lineYs.count { return lines }
                if character.isNewline { continue }
            }
            line.append(character); used += wide
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
    /// The words cut to what the lines hold (the new lines typed are kept).
    static func held(_ words: String) -> String {
        var kept = "", count = 0, used = 0.0
        for character in words {
            let wide = width(of: character)
            if character.isNewline || used + wide > perLine + 0.001 {
                guard count < lineYs.count - 1 else { return kept }
                count += 1; used = 0
                if character.isNewline { kept.append("\n"); continue }
            }
            kept.append(character); used += wide
        }
        return kept
    }
    /// A postcode as typed: its digits, six at most.
    static func digits(_ typed: String) -> String { String(typed.filter { $0.isASCII && $0.isNumber }.prefix(boxes)) }

    /// 11-22: what a touch on its back is on, at a point of the card (its middle at 0, 0, in a lid's points): the
    /// postcode's row (its boxes and the paper round them), the stamp, the lines (the whole right part under the
    /// stamp, the paper between the lines too), or nothing to write on (the left part under the postcode).
    enum Part: Equatable { case postcode, stamp, lines, none }
    static func part(at point: CGPoint) -> Part {
        guard abs(point.x) <= face.width / 2, abs(point.y) <= face.height / 2 else { return .none }
        let first = box(0), last = box(boxes - 1)
        if point.y <= first.y + boxSide / 2 + 6, point.x <= last.x + boxSide / 2 + 6 { return .postcode }
        if CGRect(x: stampMiddle.x - 16, y: stampMiddle.y - 18, width: 32, height: 36).contains(point) { return .stamp }
        if point.x >= lineStart - 9 { return .lines }
        return .none
    }
}

// MARK: - 铅笔盒: the lid's mirror and its timetable (11-19)

/// The plastic box's little mirror (the only box that has one), in the open box's picture (points): its glass. A
/// touch opens it — the camera facing the person, in the glass — and another shuts it, the drawn glass again.
enum PencilMirror {
    static let corner = 14.0
    static func glass(_ style: PencilBoxStyle, across: Bool) -> CGRect? {
        guard style == .plastic else { return nil }
        return across ? CGRect(x: 44, y: 62, width: 150, height: 52) : CGRect(x: 44, y: 66, width: 150, height: 98)
    }
}

/// The class timetable in every box's lid: five days across, five lessons down, a row of the days' names over
/// them. The pictures have the card, its lines and the days; what is written in its boxes is the app's, and can
/// be changed (PencilTimetableSheet). It starts with what each box's picture had printed, and is one's own from
/// the first change: one timetable then, whichever box is in use.
enum PencilTimetable {
    static let days = 5
    static let lessons = 5
    static var count: Int { days * lessons }
    static let dayNames = ["一", "二", "三", "四", "五"]

    /// Where it is in the open box's picture (points): its card; its grid's corner; a box's size. The days' row
    /// is the grid's first, the lessons the five under it.
    struct Place: Equatable, Sendable {
        let card: CGRect
        let grid: CGPoint
        let cell: CGSize
        /// A card as the styles draw it: the grid 14 in from its sides, 30 from its top, 10 from its foot.
        init(card: CGRect) {
            self.card = card
            grid = CGPoint(x: card.minX + 14, y: card.minY + 30)
            cell = CGSize(width: (card.width - 28) / Double(PencilTimetable.days), height: (card.height - 40) / Double(PencilTimetable.lessons + 1))
        }
        init(card: CGRect, grid: CGPoint, cell: CGSize) {
            self.card = card
            self.grid = grid
            self.cell = cell
        }
    }
    static func place(_ style: PencilBoxStyle, across: Bool) -> Place {
        switch (style, across) {
        case (.tin, false): return Place(card: CGRect(x: 410, y: 46, width: 210, height: 148), grid: CGPoint(x: 422, y: 74), cell: CGSize(width: 37, height: 18.3))
        case (.tin, true): return Place(card: CGRect(x: 217, y: 39, width: 203, height: 138), grid: CGPoint(x: 226, y: 70), cell: CGSize(width: 37, height: 15))
        case (.plastic, false): return Place(card: CGRect(x: 408, y: 44, width: 214, height: 152))
        case (.plastic, true): return Place(card: CGRect(x: 224, y: 38, width: 194, height: 166))
        case (.wood, false): return Place(card: CGRect(x: 404, y: 40, width: 222, height: 160))
        case (.wood, true): return Place(card: CGRect(x: 218, y: 34, width: 214, height: 178))
        case (.canvas, false): return Place(card: CGRect(x: 400, y: 44, width: 214, height: 152))
        case (.canvas, true): return Place(card: CGRect(x: 224, y: 38, width: 196, height: 166))
        }
    }
    /// Which box a lesson (0 the first) of a day (0 Monday) is, of the twenty-five (lesson by lesson, each one's
    /// five days), and the middle of that box in the picture.
    static func index(day: Int, lesson: Int) -> Int { lesson * days + day }
    static func middle(_ place: Place, index: Int) -> CGPoint {
        CGPoint(x: place.grid.x + place.cell.width * (Double(index % days) + 0.5),
                y: place.grid.y + place.cell.height * (Double(index / days) + 1.5))
    }
    /// The box written in after this one: the same day's next lesson; after a day's last, the next day's first;
    /// after Friday's last, none.
    static func next(after index: Int) -> Int? {
        let day = index % days, lesson = index / days
        if lesson + 1 < lessons { return self.index(day: day, lesson: lesson + 1) }
        return day + 1 < days ? self.index(day: day + 1, lesson: 0) : nil
    }

    /// What each box's picture had printed: what its timetable starts with.
    static func printed(_ style: PencilBoxStyle) -> [String] {
        switch style {
        case .tin: return ["", "美术", "", "自然", "语文", "", "", "", "", "数学", "", "体育", "", "体育", "", "", "", "", "美术", "", "", "", "", "", ""]
        case .plastic: return ["体育", "美术", "", "美术", "", "", "", "", "音乐", "", "", "数学", "", "音乐", "", "", "", "", "数学", "", "", "", "", "", ""]
        case .wood: return ["美术", "", "", "", "", "", "数学", "", "美术", "", "", "", "", "", "", "数学", "", "语文", "", "", "自然", "数学", "体育", "", ""]
        case .canvas: return ["", "数学", "", "", "", "", "音乐", "", "音乐", "", "", "语文", "", "", "", "语文", "", "语文", "自然", "", "", "", "", "", "体育"]
        }
    }
    /// What one box holds of what is typed: one line, four characters' width (a Latin letter or a digit takes
    /// half of one).
    static let widest = 4.0
    static func held(_ typed: String) -> String {
        var kept = "", used = 0.0
        for character in typed where !character.isNewline {
            let wide = character.isASCII ? 0.5 : 1.0
            if used + wide > widest { break }
            kept.append(character)
            used += wide
        }
        return kept
    }
    /// Twenty-five boxes of them, each cut to what a box holds.
    static func whole(_ cells: [String]) -> [String] {
        (0..<count).map { $0 < cells.count ? held(cells[$0]) : "" }
    }
}

/// 11-17: the postcards' tin (明信片's sheet), in points of its picture: the postcards stand in a row in it, each
/// its top over the one in front, and in front of them all a blank one (a new one's place); the tin's front wall
/// hides their feet from its rim down.
enum PencilCardTinLayout {
    static let size = CGSize(width: 360, height: 430)
    static let rim = 297.0
    /// The top of the blank one in front; the highest the one at the back stands before the steps are at their
    /// narrowest (a longer row asks for room over the picture).
    static let frontTop = 258.0
    static let highest = 42.0
    static let widestStep = 34.0
    static let narrowestStep = 10.0
    /// How far each postcard stands above the one in front of it: less as there are more of them.
    static func step(count: Int) -> Double {
        guard count > 0 else { return widestStep }
        return max(narrowestStep, min(widestStep, (frontTop - highest) / Double(count)))
    }
    /// The card at `index` of the row (0 at the back; `count`, after all the postcards, the blank one): its size
    /// (of a postcard on the lid), its top, and its middle. Those farther back are a little smaller.
    static func place(_ index: Int, count: Int) -> (scale: Double, top: Double, middle: CGPoint) {
        let behind = Double(max(0, count - index))
        let scale = max(1.26, 1.5 - 0.03 * behind)
        let top = frontTop - behind * step(count: count)
        return (scale, top, CGPoint(x: size.width / 2, y: top + PencilCard.face.height * scale / 2))
    }
    /// How much of the card at `index` shows, from its top down: to the top of the one in front of it; the blank
    /// one, to the tin's rim. (What a touch on it has to land on.)
    static func shows(_ index: Int, count: Int) -> Double { index < count ? step(count: count) : rim - frontTop }
    /// Room wanted over the picture when the row is so long that its back cards stand above the lid's edge.
    static func headroom(count: Int) -> Double { max(0, 12 - place(0, count: count).top) }
}

/// 11-15: 铅笔盒's postcards. Each of 画框's sceneries, once it has been looked at a little while, sends one into
/// the box: it comes under the straps with the photos and notes, goes onto the lid held by a yellow magnet and
/// is turned over there with a tap; it is never thrown away, and each scenery sends one only.
enum PencilPostcards {
    /// How long a scenery shows before its postcard comes (seconds).
    static let seenSeconds = 6.0
    /// The sceneries whose postcards the box has, on the lid or in it.
    static func had(_ pieces: [PencilPiece]) -> Set<FrameScene> { Set(pieces.compactMap { $0.kind == .postcard ? $0.scene : nil }) }
}

/// A note: strokes (PencilKit's own data, drawn on a square of `width` ×
/// `height` points) and typed words, on squared or ruled paper.
/// The handwriting a note's typed words are in: three of the typefaces iOS
/// fetches the first time they are asked for (the app carries none).
enum PencilHand: String, Codable, CaseIterable, Sendable {
    case notes = "HannotateSC-W5", pen = "HanziPenSC-W3", doll = "DFWaWaSC-W5"
    var title: String {
        switch self {
        case .notes: return String(localized: "手札体")
        case .pen: return String(localized: "翩翩体")
        case .doll: return String(localized: "娃娃体")
        }
    }
    var next: PencilHand {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

struct PencilNote: Codable, Equatable, Sendable {
    var drawing: Data
    var width: Double
    var height: Double
    var text: String
    var grid: Bool
    /// The typed words' handwriting (notes kept before there was a choice: 手札体).
    var hand: PencilHand? = nil
    static func blank(grid: Bool) -> PencilNote { PencilNote(drawing: Data(), width: 300, height: 300, text: "", grid: grid) }
    var isBlank: Bool { drawing.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The lid's arithmetic, apart from the store (the unit checks use it).
enum PencilLayout {
    /// A new box's lid: a, o, e, the calendar, a blank note.
    static let first: [(PencilThing?, Double, Double, Double)] = [
        (.letterA, 100, 150, -0.16), (.letterO, 162, 166, 0.07), (.letterE, 226, 148, -0.05),
        (.calendar, 366, 166, 0.05), (nil, 132, 336, -0.06),
    ]
    /// A middle kept on the lid (a part of its width and height).
    static func clamp(_ x: Double, _ y: Double) -> (Double, Double) {
        (min(0.95, max(0.05, x)), min(0.96, max(0.06, y)))
    }
    static func clampScale(_ scale: Double) -> Double { min(1.6, max(0.6, scale)) }
    /// Within four degrees of upright: upright.
    static func snapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if a > Double.pi { a -= 2 * Double.pi }
        if a < -Double.pi { a += 2 * Double.pi }
        return abs(a) < 4 * Double.pi / 180 ? 0 : a
    }
    /// Where something new goes: of a few places on the lid (none under the
    /// cover's camera, none at the very top where the menu is pulled down),
    /// the one farthest from what is there already.
    static func freeSpot(among taken: [(Double, Double)]) -> (Double, Double) {
        var best = (0.5, 0.5), bestGap = -1.0
        for row in 0..<6 {
            for column in 0..<4 {
                let x = 0.2 + Double(column) * 0.2, y = 0.26 + Double(row) * 0.125
                let gap = taken.map { hypot(($0.0 - x) * PencilArt.lid.width, ($0.1 - y) * PencilArt.lid.height) }.min() ?? 1e9
                if gap > bestGap + 0.5 { best = (x, y); bestGap = gap }
            }
        }
        return best
    }
}

/// The lid's frame in the window: upright in the cover's own portrait frame
/// (its hinge along the left, as the box's is), whatever the window's
/// interface orientation; a preview (a phone with no cover) fits it upright
/// in what there is.
struct PencilLidPlacement: Equatable {
    let canvas: CGSize
    let rotation: Double
    static func calculate(size: CGSize, flipped: Bool = false, interfaceRotation: Double? = nil) -> Self {
        guard let turn = interfaceRotation else {
            let k = min(size.width / PencilArt.lid.width, size.height / PencilArt.lid.height)
            return Self(canvas: CGSize(width: PencilArt.lid.width * k, height: PencilArt.lid.height * k), rotation: flipped ? 180 : 0)
        }
        var angle = (-turn + (flipped ? 180 : 0)).truncatingRemainder(dividingBy: 360)
        if angle <= -180 { angle += 360 }
        if angle > 180 { angle -= 360 }
        let across = abs(abs(angle) - 90) < 1
        return Self(canvas: across ? CGSize(width: size.height, height: size.width) : size, rotation: angle)
    }
}

/// The box open over the whole inner display (PencilBoxOpen): where each
/// thing lies, in points of the drawing, as its pictures are drawn. Two
/// drawings of one box: an iPhone Duo held upright (669 × 951, the hinge
/// 455–496 down the middle across: the lid's inside above, the box below)
/// and held across (951 × 669, the hinge down the middle: the lid on the
/// left, the box on the right), every word upright in both. The lid's
/// inside: the multiplication table, the timetable in its sleeve, two
/// elastic straps with one's own photos and notes under them, paper tags.
/// (11-16: one strap, its things side by side under it and larger, two
/// upright and three across; the rest a page away, PencilOpenLayout.pages.)
/// The box: a well for each of its own things (the three letters share
/// one), the rack and its red button, the red ribbon at the foot.
struct PencilOpenLayout: Sendable {
    /// A thing in its well: from the well's middle, its turn (radians) and
    /// its size (points to a lid point of its picture).
    struct Spot: Equatable, Sendable {
        let thing: PencilThing
        let dx: Double
        let dy: Double
        let turn: Double
        let u: Double
    }
    /// A place under the strap: the middle of what is tucked in there, its turn.
    struct Slot: Equatable, Sendable {
        let x: Double
        let y: Double
        let turn: Double
    }
    let size: CGSize
    let background: String
    let strapsFile: String
    /// The eight wells, and what each holds on the tray's top layer (the same things in both drawings); what they
    /// hold on the layers under it (the red ribbon lifts a layer out to the next).
    let wells: [CGRect]
    let spots: [[Spot]]
    let lower: [[[Spot]]]
    let slots: [Slot]
    /// The straps' own picture, laid over what is under them.
    let straps: CGRect
    /// The paper tags: 返回, and 贴照片 · 游戏笔记 · 写便条 over the straps.
    let back: CGRect
    /// A phone (no cover to close the box onto), 11-15: the tag 往下拉，合上盒盖 hung under the lid's latch
    /// (held across, turned a quarter to the left along the lid's edge: this is the rect it covers then); what a
    /// finger takes there (the drawn latch and its tag): pulled toward the hinge, the lid turns over onto the box
    /// with it; from the lid's edge to the hinge; and where the shut lid lies over the box (its outside, upright:
    /// its hinge at the top).
    let lidTag: CGRect
    let latch: CGRect
    let lidReach: Double
    let lidOutside: CGRect
    let photo: CGRect
    let notes: CGRect
    let write: CGRect
    let ribbon: CGRect
    /// Where the strap says what goes under it while nothing does yet.
    let strapsHint: CGPoint
    /// The size of a photo or a note under the strap; where the pages' dots are.
    let strapScale: Double
    let pageDots: CGPoint
    /// The words that come and go.
    let toast: CGPoint
    /// The rack's pictures (folded flat, sprung up) and where they lie; its red button's middle.
    let rack: CGRect
    let rackFile: String
    let rackUpFile: String
    let button: CGPoint
    /// The elastic strap (bent by the app, PencilStrapString): the line it lies on (its top), where it is held
    /// at the ends, how wide the band is.
    let strapLines: [Double]
    let strapX0: Double
    let strapX1: Double
    let strapH: Double
    /// The tools' channel: held across they lie down it, points down, 0.85 the size; the line the backs
    /// are on (x upright, y across); the ruler's middle line and each of the two pencil grooves' (y upright,
    /// x across).
    let toolsAcross: Bool
    let toolScale: Double
    let toolBack: Double
    let rulerLine: Double
    let grooveLines: [Double]
    /// The sharpener: the hole a point goes into (it goes in along the tools' length, toward the point); where
    /// the shavings come to lie.
    let hole: CGPoint
    let shavings: CGRect
    /// The rack stood up: where its nine holes are (a pencil of each colour has its own, PencilTool.hole).
    let rackHoles: [CGPoint]

    static let upright = PencilOpenLayout(
        size: CGSize(width: 669, height: 951), background: "pencilbox-open.jpg", strapsFile: "pencilbox-open-straps.png",
        wells: [734.0, 832.0].flatMap { y in [32.0, 184.0, 336.0, 488.0].map { CGRect(x: $0, y: y, width: 144, height: 90) } },
        spots: [
            [Spot(thing: .letterA, dx: -40, dy: 2, turn: -0.12, u: 0.78), Spot(thing: .letterO, dx: 0, dy: -3, turn: 0.08, u: 0.78),
             Spot(thing: .letterE, dx: 40, dy: 3, turn: -0.05, u: 0.78)],
            [Spot(thing: .calendar, dx: -30, dy: 0, turn: 0.04, u: 0.70), Spot(thing: .zeroTag, dx: 38, dy: 6, turn: -0.08, u: 0.62)],
            [Spot(thing: .flowerStamp, dx: 0, dy: 0, turn: 0.15, u: 1.2)],
            [Spot(thing: .lollipop, dx: 0, dy: 0, turn: 1.1, u: 0.85)],
            [Spot(thing: .musicBox, dx: -2, dy: 1, turn: -0.06, u: 1.25)],
            [Spot(thing: .bicycle, dx: 0, dy: 0, turn: -0.1, u: 1.35)],
            [Spot(thing: .schoolBag, dx: 0, dy: 0, turn: 0.06, u: 1.2)],
            [Spot(thing: .ginkgoLeaf, dx: 0, dy: -2, turn: 0.25, u: 1.0)],
        ],
        lower: [[
            [Spot(thing: .shuttlecock, dx: 0, dy: 0, turn: 0.08, u: 1.03)],
            [Spot(thing: .pinwheel, dx: 0, dy: 0, turn: -1.22, u: 1.18)],
            [Spot(thing: .rubberBall, dx: 0, dy: 0, turn: 0.05, u: 1.25)],
            [Spot(thing: .spinningTop, dx: 0, dy: 0, turn: -0.09, u: 1.09)],
            [Spot(thing: .tinFrog, dx: 0, dy: 0, turn: 0.06, u: 1.25)],
            [Spot(thing: .skippingRope, dx: 0, dy: 0, turn: -0.05, u: 1.18)],
            [Spot(thing: .marbleJar, dx: 0, dy: 0, turn: 0.07, u: 1.15)],
            [Spot(thing: .tinPencilBox, dx: 0, dy: -11.1, turn: -0.03, u: 1.02), Spot(thing: .pencilStub, dx: 2, dy: 25, turn: 0.05, u: 1.1)]
        ], [
            [Spot(thing: .thermos, dx: 0, dy: 0, turn: 1.22, u: 1.03)],
            [Spot(thing: .enamelMug, dx: 0, dy: 0, turn: -0.06, u: 1.25)],
            [Spot(thing: .sodaBottle, dx: 0, dy: 0, turn: 1.22, u: 1.25)],
            [Spot(thing: .biscuitTin, dx: 0, dy: 0, turn: -0.09, u: 1.25)],
            [Spot(thing: .exerciseBook, dx: 0, dy: 0, turn: 0.06, u: 1.11)],
            [Spot(thing: .inkBottle, dx: 0, dy: 0, turn: -0.05, u: 1.25)],
            [Spot(thing: .abacus, dx: 0, dy: 0, turn: 0.07, u: 1.25)],
            [Spot(thing: .rotaryPhone, dx: 0, dy: 0, turn: -0.08, u: 1.23)]
        ]],
        slots: [Slot(x: 464.5, y: 331, turn: -0.05), Slot(x: 585.5, y: 331, turn: 0.04)],
        straps: CGRect(x: 394, y: 282, width: 262, height: 132),
        back: CGRect(x: 26, y: 24, width: 78, height: 28), lidTag: CGRect(x: 259.5, y: 24, width: 150, height: 32),
        latch: CGRect(x: 254.5, y: 0, width: 160, height: 60), lidReach: 455, lidOutside: CGRect(x: 18, y: 496, width: 633, height: 435),
        photo: CGRect(x: 408, y: 213, width: 72, height: 28), notes: CGRect(x: 489, y: 214, width: 72, height: 28),
        write: CGRect(x: 570, y: 213, width: 72, height: 28), ribbon: CGRect(x: 264.5, y: 921, width: 140, height: 22),
        strapsHint: CGPoint(x: 525, y: 322), strapScale: 1.08, pageDots: CGPoint(x: 525, y: 411), toast: CGPoint(x: 334.5, y: 428),
        rack: CGRect(x: 22, y: 656, width: 540, height: 84), rackFile: "pencilbox-open-rack.png", rackUpFile: "pencilbox-open-rack-up.png",
        button: CGPoint(x: 597, y: 694),
        strapLines: [345], strapX0: 404, strapX1: 646, strapH: 11,
        toolsAcross: false, toolScale: 1, toolBack: 56, rulerLine: 546, grooveLines: [589, 619],
        hole: CGPoint(x: 575, y: 546), shavings: CGRect(x: 566, y: 572, width: 62, height: 72),
        rackHoles: (0..<9).map { CGPoint(x: 66 + 55.5 * Double($0), y: 683.1) })

    static let across = PencilOpenLayout(
        size: CGSize(width: 951, height: 669), background: "pencilbox-across.jpg", strapsFile: "pencilbox-across-straps.png",
        wells: [30.0, 178.0, 326.0, 474.0].flatMap { y in [524.0, 642.0].map { CGRect(x: $0, y: y, width: 110, height: 140) } },
        spots: [
            [Spot(thing: .letterA, dx: -24, dy: -28, turn: -0.12, u: 0.78), Spot(thing: .letterO, dx: 20, dy: -10, turn: 0.08, u: 0.78),
             Spot(thing: .letterE, dx: -8, dy: 30, turn: -0.05, u: 0.78)],
            [Spot(thing: .calendar, dx: 0, dy: -14, turn: 0.04, u: 0.74), Spot(thing: .zeroTag, dx: 0, dy: 50, turn: 0.06, u: 0.62)],
            [Spot(thing: .flowerStamp, dx: 0, dy: 0, turn: 0.12, u: 1.35)],
            [Spot(thing: .lollipop, dx: 0, dy: 0, turn: 0.35, u: 0.95)],
            [Spot(thing: .musicBox, dx: 0, dy: 2, turn: -0.06, u: 1.2)],
            [Spot(thing: .bicycle, dx: 0, dy: 0, turn: -0.1, u: 1.25)],
            [Spot(thing: .schoolBag, dx: 0, dy: 0, turn: 0.06, u: 1.45)],
            [Spot(thing: .ginkgoLeaf, dx: 0, dy: -2, turn: 0.25, u: 1.35)],
        ],
        lower: [[
            [Spot(thing: .shuttlecock, dx: 0, dy: 0, turn: 0.08, u: 1.25)],
            [Spot(thing: .pinwheel, dx: 0, dy: 0, turn: -0.06, u: 1.25)],
            [Spot(thing: .rubberBall, dx: 0, dy: 0, turn: 0.05, u: 1.25)],
            [Spot(thing: .spinningTop, dx: 0, dy: 0, turn: -0.09, u: 1.25)],
            [Spot(thing: .tinFrog, dx: 0, dy: 0, turn: 0.06, u: 1.15)],
            [Spot(thing: .skippingRope, dx: 0, dy: 0, turn: -0.05, u: 1.25)],
            [Spot(thing: .marbleJar, dx: 0, dy: 0, turn: 0.07, u: 1.25)],
            [Spot(thing: .tinPencilBox, dx: 0, dy: -10.5, turn: -0.03, u: 1.15), Spot(thing: .pencilStub, dx: 2, dy: 27.8, turn: 0.05, u: 1.02)]
        ], [
            [Spot(thing: .thermos, dx: 0, dy: 0, turn: 0.08, u: 1.25)],
            [Spot(thing: .enamelMug, dx: 0, dy: 0, turn: -0.06, u: 1.25)],
            [Spot(thing: .sodaBottle, dx: 0, dy: 0, turn: 0.05, u: 1.25)],
            [Spot(thing: .biscuitTin, dx: 0, dy: 0, turn: -0.09, u: 1.25)],
            [Spot(thing: .exerciseBook, dx: 0, dy: 0, turn: 0.06, u: 1.25)],
            [Spot(thing: .inkBottle, dx: 0, dy: 0, turn: -0.05, u: 1.25)],
            [Spot(thing: .abacus, dx: 0, dy: 0, turn: 0.07, u: 1.15)],
            [Spot(thing: .rotaryPhone, dx: 0, dy: 0, turn: -0.08, u: 1.1)]
        ]],
        slots: [Slot(x: 100, y: 547, turn: -0.05), Slot(x: 231, y: 547, turn: 0.04), Slot(x: 362, y: 547, turn: -0.03)],
        straps: CGRect(x: 24, y: 504, width: 414, height: 120),
        back: CGRect(x: 24, y: 24, width: 76, height: 28), lidTag: CGRect(x: 17, y: 259.5, width: 30, height: 150),
        latch: CGRect(x: 0, y: 254.5, width: 52, height: 160), lidReach: 455, lidOutside: CGRect(x: 496, y: 18, width: 435, height: 633),
        photo: CGRect(x: 50, y: 432, width: 100, height: 28), notes: CGRect(x: 181, y: 433, width: 100, height: 28),
        write: CGRect(x: 312, y: 432, width: 100, height: 28), ribbon: CGRect(x: 568, y: 637, width: 140, height: 22),
        strapsHint: CGPoint(x: 231, y: 540), strapScale: 1.15, pageDots: CGPoint(x: 231, y: 626), toast: CGPoint(x: 231, y: 640),
        rack: CGRect(x: 760, y: 20, width: 80, height: 470), rackFile: "pencilbox-across-rack.png", rackUpFile: "pencilbox-across-rack-up.png",
        button: CGPoint(x: 795, y: 528),
        strapLines: [562], strapX0: 34, strapX1: 428, strapH: 11,
        toolsAcross: true, toolScale: 0.85, toolBack: 46, rulerLine: 847, grooveLines: [880, 900],
        hole: CGPoint(x: 853, y: 509), shavings: CGRect(x: 844, y: 556, width: 64, height: 56),
        rackHoles: (0..<9).map { CGPoint(x: 784.5, y: 438 - 46.75 * Double($0)) })

    /// The tray's layers, and what each well holds on one (the same in both drawings).
    static var trays: Int { 1 + upright.lower.count }
    func spots(layer: Int) -> [[Spot]] { layer <= 0 || lower.isEmpty ? spots : lower[min(layer, lower.count) - 1] }
    static func things(layer: Int) -> [[PencilThing]] { upright.spots(layer: layer).map { $0.map(\.thing) } }
    static var things: [[PencilThing]] { things(layer: 0) }
    /// The layer after this one: under the last, the top one again.
    static func tray(after layer: Int) -> Int { (max(0, layer) + 1) % max(1, trays) }
    /// How many of one's own a page under the strap holds: as many as it has places.
    var perPage: Int { slots.count }
    /// The pages one's own make under the strap (one at least).
    static func pages(own: Int, perPage: Int) -> Int { max(1, (max(0, own) + max(1, perPage) - 1) / max(1, perPage)) }
    /// Which of one's own a page holds.
    static func onPage(_ page: Int, own: Int, perPage: Int) -> Range<Int> {
        let start = min(max(0, own), max(0, page) * max(1, perPage))
        return start..<min(max(0, own), start + max(1, perPage))
    }
    /// The page one of one's own is on.
    static func page(of index: Int, perPage: Int) -> Int { max(0, index) / max(1, perPage) }
}

/// The postcards' slot on the lid's inside: a well like the box's own, the same size in every box; each box's
/// drawing has its own place for it, upright and across. The pile of postcards lies in it, the one on top showing;
/// a paper tag hangs over it (明信片: all of them laid out, and a new one made).
enum PencilCardSlot {
    static let size = CGSize(width: 150, height: 110)
    /// A postcard in the slot, points to a point of its picture (the card itself 132.5 × 88.3: the well shows round it).
    static let scale = 1.0
    static func rect(_ style: PencilBoxStyle, across: Bool) -> CGRect {
        let origin: CGPoint
        switch (style, across) {
        case (.tin, false), (.plastic, false), (.wood, false): origin = CGPoint(x: 232, y: 94)
        case (.canvas, false): origin = CGPoint(x: 227, y: 245)
        case (.tin, true): origin = CGPoint(x: 283, y: 226)
        case (.plastic, true): origin = CGPoint(x: 54, y: 158)
        case (.wood, true): origin = CGPoint(x: 270, y: 250)
        case (.canvas, true): origin = CGPoint(x: 255, y: 281)
        }
        return CGRect(origin: origin, size: size)
    }
    /// The paper tag over a slot.
    static func tag(over slot: CGRect) -> CGRect { CGRect(x: slot.midX - 42, y: slot.minY - 32, width: 84, height: 28) }
    /// The card after this one round the pile (`by` 1) or the one before (-1): after the last comes the first again.
    static func turned(_ index: Int, by: Int, count: Int) -> Int { count > 0 ? ((index + by) % count + count) % count : 0 }
}

/// The open box's frame in a view: on a Duo its hinge on the fold, the
/// drawing for the way it is held; anywhere else the drawing for the
/// view's shape (taller: upright; wider: across), as big as fits, in the middle.
struct PencilOpenPlacement: Equatable {
    /// Points on the display to a point of the drawing.
    let k: Double
    let across: Bool
    let center: CGPoint
    var layout: PencilOpenLayout { across ? .across : .upright }
    static func calculate(size: CGSize, fold: CGRect?) -> Self {
        // (In both drawings the hinge is the middle: on the fold's middle.)
        if let fold, fold.width > 0, fold.height > 0 {
            if fold.width >= fold.height {
                return Self(k: size.width / PencilOpenLayout.upright.size.width, across: false, center: CGPoint(x: size.width / 2, y: fold.midY))
            }
            return Self(k: size.height / PencilOpenLayout.across.size.height, across: true, center: CGPoint(x: fold.midX, y: size.height / 2))
        }
        let across = size.width > size.height
        let art = across ? PencilOpenLayout.across.size : PencilOpenLayout.upright.size
        let k = min(size.width / art.width, size.height / art.height)
        return Self(k: k, across: across, center: CGPoint(x: size.width / 2, y: size.height / 2))
    }
}


// MARK: - 铅笔盒's tools

/// The box's tools: the ruler in its groove, and nine pencils, one of each colour (the red-and-blue pencil with
/// a point at each end is gone: which end is being sharpened must be plain to see). Two pencils lie in the
/// grooves beside the ruler (PencilBoxStore.grooves); the others stand in the rack, each in its own hole, seen end
/// on while the rack is up. The ruler and a pencil in a groove can go onto the lid; a pencil held in the
/// sharpener is sharpened, shorter each turn, a curl of shaving coming out.
enum PencilTool: String, CaseIterable, Identifiable, Codable, Sendable {
    case ruler, red, orange, yellow, green, teal, blue, purple, pink, brown
    var id: String { rawValue }
    var isPencil: Bool { self != .ruler }
    /// In the order of the rack's holes.
    static let pencils: [PencilTool] = [.red, .orange, .yellow, .green, .teal, .blue, .purple, .pink, .brown]
    /// What a new box has in its two grooves.
    static let firstGrooves: [PencilTool?] = [.red, .blue]
    /// Its hole in the rack (PencilOpenLayout.rackHoles).
    var hole: Int? { Self.pencils.firstIndex(of: self) }
    var title: String {
        switch self {
        case .ruler: return String(localized: "尺子")
        case .red: return String(localized: "红铅笔")
        case .orange: return String(localized: "橙铅笔")
        case .yellow: return String(localized: "黄铅笔")
        case .green: return String(localized: "绿铅笔")
        case .teal: return String(localized: "青铅笔")
        case .blue: return String(localized: "蓝铅笔")
        case .purple: return String(localized: "紫铅笔")
        case .pink: return String(localized: "粉铅笔")
        case .brown: return String(localized: "棕铅笔")
        }
    }
    var use: String {
        isPencil ? String(localized: "按住拖到卷笔刀里，越削越短，削下来的木屑也能贴；拖到笔架上就插回去。") : String(localized: "十五厘米的木头尺子。")
    }
    /// Standing in the rack, seen end on (PencilToolArt.butt).
    var buttFile: String { "pencilbox-butt-\(rawValue).png" }
    /// Its pictures: the ruler's; a pencil's body (cut to what is left of it) and its point.
    var bodyFile: String { self == .ruler ? "pencilbox-ruler.png" : "pencilbox-pencil-\(rawValue).png" }
    var tipFile: String { "pencilbox-pencil-\(rawValue)-tip.png" }
    func shavingFile(_ shape: Int) -> String { "pencilbox-shaving-\(rawValue)-\(min(2, max(0, shape))).png" }
    /// On the lid (its size there: the box's tools are drawn bigger).
    var lidArt: PencilArt {
        let k = PencilToolArt.onLid
        if self == .ruler { return PencilArt("pencilbox-ruler", PencilToolArt.ruler.width * k, PencilToolArt.ruler.height * k, 1.6, 2.0) }
        return PencilArt("pencilbox-pencil-\(rawValue)", (PencilToolArt.body.width + PencilToolArt.tip.width) * k, PencilToolArt.body.height * k, 1.4, 1.8)
    }
}

/// A curl of shaving in the sharpener: the pencil it came off, which drawn curl it is, how it lies (its middle as a
/// part of the place the shavings lie in, its turn).
struct PencilShaving: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var tool: PencilTool
    var shape: Int
    var x: Double
    var y: Double
    var turn: Double
}

/// The tools' pictures, in points of the box as drawn (held upright; held across, `toolScale` of it).
enum PencilToolArt {
    static let ruler = CGSize(width: 472.4, height: 32.8)
    /// A pencil's body: its back 4.2 points in from the picture's left edge; 417.2 points of it when new; the
    /// point's picture goes on where the body is cut. The pencil itself is 20.16 points thick.
    static let body = CGSize(width: 421.4, height: 25.76)
    static let bodyBack = 4.2
    static let bodyLength = 417.2
    static let tip = CGSize(width: 38.64, height: 25.76)
    static let thickness = 20.16
    static let shaving = CGSize(width: 36, height: 32)
    /// On the lid the tools are this part of their size in the box; a shaving a little bigger than in the box.
    static let onLid = 0.62
    static let shavingOnLid = 1.3
    /// A pencil standing in the rack, seen end on: its back and the long thin shade it throws, a picture this
    /// big (points of the box as drawn upright; held across, `toolScale` of it), the back's middle here in it (on
    /// the hole's middle).
    static let butt = CGSize(width: 44, height: 48)
    static let buttMiddle = CGPoint(x: 9, y: 9)
    static func lidShaving(_ tool: PencilTool, _ shape: Int) -> PencilArt {
        let name = tool.shavingFile(shape).replacingOccurrences(of: ".png", with: "")
        return PencilArt(name, shaving.width * shavingOnLid, shaving.height * shavingOnLid, 0.8, 1.0)
    }
    /// A pencil's picture, long as `left` (1 new … `shortest`) makes it: the body cut, the point on.
    static func pencilWidth(_ left: Double) -> Double { bodyBack + bodyLength * left + tip.width }
}

/// Sharpening: each turn in the sharpener takes a little off a pencil, a curl of shaving coming off every other
/// turn; a pencil is not sharpened shorter than a stub.
enum PencilSharpening {
    static let turn = 0.012
    static let shortest = 0.3
    /// Seconds a turn takes while the pencil is held in.
    static let turnSeconds = 0.36
    /// How many curls lie in the sharpener (the oldest go when more come).
    static let held = 12
    static func after(_ left: Double) -> Double { max(shortest, left - turn) }
    static func canSharpen(_ left: Double) -> Bool { left - turn >= shortest - 1e-9 }
    /// A curl comes off on this turn (the turns counted from the first).
    static func sheds(onTurn count: Int) -> Bool { count % 2 == 1 }
    /// A new box's sharpener has three curls in its window already (11-15, as the drawing had them): a blue one
    /// at the top, a green and a red below.
    static func firstShavings() -> [PencilShaving] {
        [PencilShaving(id: UUID(), tool: .blue, shape: 0, x: 0.56, y: 0.27, turn: -0.6),
         PencilShaving(id: UUID(), tool: .green, shape: 1, x: 0.33, y: 0.6, turn: 0.45),
         PencilShaving(id: UUID(), tool: .red, shape: 2, x: 0.69, y: 0.82, turn: -0.3)]
    }
    /// 11-17: each style of box has a sharpener of its own (a style with no list here is a new box: its first
    /// three). What was kept, sorted: a list for each style; or, kept before that, the one list there was, which
    /// stays with the style in use.
    static func kept(_ lists: [String: [PencilShaving]]?, shared: [PencilShaving]?, style: PencilBoxStyle) -> [PencilBoxStyle: [PencilShaving]] {
        var out: [PencilBoxStyle: [PencilShaving]] = [:]
        if let lists {
            for (name, list) in lists { if let named = PencilBoxStyle(rawValue: name) { out[named] = Array(list.suffix(held)) } }
        } else if let shared {
            out[style] = Array(shared.suffix(held))
        }
        return out
    }
}

/// The two grooves beside the ruler (11-15): which one a pencil taken out of the rack goes into — an empty one;
/// else the one not filled last whose pencil is not on the lid (that pencil goes back into the rack); with both
/// pencils on the lid, the one not filled last (its pencil stays on the lid, and goes into the rack when it comes
/// off).
enum PencilGrooves {
    static let count = 2
    static func choose(_ grooves: [PencilTool?], onLid: (PencilTool) -> Bool, lastFilled: Int) -> Int {
        if let empty = grooves.firstIndex(where: { $0 == nil }) { return empty }
        let order = grooves.indices.filter { $0 != lastFilled } + grooves.indices.filter { $0 == lastFilled }
        return order.first { index in grooves[index].map { pencil in !onLid(pencil) } ?? true } ?? order.first ?? 0
    }
    /// What was kept, made sound: two grooves, pencils only, none twice (nothing kept: a new box's).
    static func sound(_ kept: [PencilTool?]?) -> [PencilTool?] {
        guard let kept else { return PencilTool.firstGrooves }
        var seen = Set<PencilTool>()
        return (0..<count).map { index in
            guard index < kept.count, let tool = kept[index], tool.isPencil, !seen.contains(tool) else { return nil }
            seen.insert(tool)
            return tool
        }
    }
}

/// An elastic strap across the lid's inside, plucked: a string held at both ends (a damped wave), so a pull let
/// go of bounces once or twice and settles. Its give, sideways, at `nodes` points between the ends.
struct PencilStrapString: Equatable, Sendable {
    static let nodes = 23
    /// The lowest bounce's frequency (a second) and how fast the bouncing dies away.
    static let frequency = 4.0
    /// (12: over, back and over a little — a bounce or two, as a plucked elastic does; 7.5 bounced six times.)
    static let damping = 12.0
    static let farthest = 34.0
    let length: Double
    private(set) var y: [Double] = Array(repeating: 0, count: Self.nodes)
    private(set) var v: [Double] = Array(repeating: 0, count: Self.nodes)
    init(length: Double) { self.length = length }
    private var dx: Double { length / Double(Self.nodes + 1) }
    private func at(_ i: Int) -> Double { Double(i + 1) * dx }
    var moving: Bool { y.contains { abs($0) > 0.12 } || v.contains { abs($0) > 2 } }
    var largest: Double { y.map(abs).max() ?? 0 }
    /// Held by a finger at `x` (0 … length), pulled `by` points: straight from each end to the finger.
    mutating func pull(at x: Double, by d: Double) {
        let apex = min(length - dx, max(dx, x)), pull = min(Self.farthest, max(-Self.farthest, d))
        for i in 0..<Self.nodes {
            let u = at(i)
            y[i] = u <= apex ? pull * u / apex : pull * (length - u) / (length - apex)
            v[i] = 0
        }
    }
    /// Let go of: it runs on by itself (`seconds` of it, in small steps).
    mutating func step(_ seconds: Double) {
        let c = 2 * length * Self.frequency, h = 1.0 / 480
        var left = min(seconds, 0.1)
        while left > 1e-9 {
            let dt = min(h, left)
            left -= dt
            var a = [Double](repeating: 0, count: Self.nodes)
            for i in 0..<Self.nodes {
                let l = i > 0 ? y[i - 1] : 0, r = i < Self.nodes - 1 ? y[i + 1] : 0
                a[i] = c * c * (l - 2 * y[i] + r) / (dx * dx) - Self.damping * v[i]
            }
            for i in 0..<Self.nodes { v[i] += a[i] * dt; y[i] += v[i] * dt }
        }
        if !moving { for i in 0..<Self.nodes { y[i] = 0; v[i] = 0 } }
    }
    /// The give at `x` (0 at the ends).
    func give(at x: Double) -> Double {
        let f = x / dx - 1
        if f <= -1 || f >= Double(Self.nodes) { return 0 }
        let i = Int(f.rounded(.down)), t = f - Double(i)
        let a = i >= 0 ? y[i] : 0, b = i + 1 < Self.nodes ? y[i + 1] : 0
        return a + (b - a) * t
    }
}


// MARK: - 铅笔盒的款式和配色

/// A colour of a pencil box (主题 › 铅笔盒): its name and its sRGB. A light colour brings
/// the shade under the shell's own colour up a little (`contrast` under 1); without it a pale box
/// looks dusty.
struct PencilBoxColour: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let red: Double
    let green: Double
    let blue: Double
    let contrast: Double
    init(_ id: String, _ name: String, _ hex: UInt32, contrast: Double = 1) {
        self.id = id
        self.name = name
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
        self.contrast = contrast
    }
    var rgb: SIMD3<Double> { SIMD3(red, green, blue) }
}

/// The pencil box's styles: tin, push-button plastic, wood, canvas. Every style keeps its wells,
/// straps, rack, red button and ribbon in the same places (PencilOpenLayout is every style's);
/// only the pictures differ. Each style's pictures are drawn in its first colour; the others are
/// made on the device from them, the shell alone (PencilRecolour, through each picture's mask).
enum PencilBoxStyle: String, CaseIterable, Identifiable, Sendable {
    case tin, plastic, wood, canvas
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tin: return String(localized: "铁皮文具盒")
        case .plastic: return String(localized: "按键塑料文具盒")
        case .wood: return String(localized: "木头笔盒")
        case .canvas: return String(localized: "帆布笔盒")
        }
    }
    var blurb: String {
        switch self {
        case .tin: return String(localized: "上了漆的铁皮，盒盖里印着乘法口诀表，课程表插在塑料套里。")
        case .plastic: return String(localized: "亮面塑料，鼓鼓的边。盒盖里有小镜子和彩色拼音表，侧面三个小按键。")
        case .wood: return String(localized: "木框、枫木内板，铜合页、铜包角。盒盖里一张《静夜思》，一片压干的枫叶。")
        case .canvas: return String(localized: "布面硬壳，一圈拉链。盒盖里一个网兜，课程表放在透明窗里。")
        }
    }
    /// The first is the colour the pictures are drawn in.
    var colours: [PencilBoxColour] {
        switch self {
        case .tin:
            return [PencilBoxColour("teal", String(localized: "青绿"), 0x3f857b), PencilBoxColour("sky", String(localized: "天蓝"), 0x4a8cc4),
                    PencilBoxColour("navy", String(localized: "藏青"), 0x2e4170), PencilBoxColour("grape", String(localized: "葡萄紫"), 0x7e62a8),
                    PencilBoxColour("sakura", String(localized: "樱花粉"), 0xe3929f, contrast: 0.9), PencilBoxColour("cherry", String(localized: "樱桃红"), 0xb5423a),
                    PencilBoxColour("orange", String(localized: "橘子橙"), 0xdc7a38), PencilBoxColour("goose", String(localized: "鹅黄"), 0xe0b444, contrast: 0.9),
                    PencilBoxColour("mint", String(localized: "薄荷"), 0x7fc2a9, contrast: 0.9), PencilBoxColour("cream", String(localized: "奶白"), 0xece3cc, contrast: 0.7)]
        case .plastic:
            return [PencilBoxColour("sky", String(localized: "天蓝"), 0x4f97d1), PencilBoxColour("sakura", String(localized: "樱花粉"), 0xec97a8, contrast: 0.9),
                    PencilBoxColour("mint", String(localized: "薄荷"), 0x6cc4a4, contrast: 0.9), PencilBoxColour("grape", String(localized: "葡萄紫"), 0x9a7bc8),
                    PencilBoxColour("lemon", String(localized: "柠檬黄"), 0xecc845, contrast: 0.85)]
        case .wood:
            return [PencilBoxColour("natural", String(localized: "原木"), 0xb9814d), PencilBoxColour("walnut", String(localized: "胡桃"), 0x6e4a30),
                    PencilBoxColour("cherry", String(localized: "樱桃木"), 0x9a4e36), PencilBoxColour("oak", String(localized: "白橡"), 0xd9c8a8, contrast: 0.75),
                    PencilBoxColour("green", String(localized: "墨绿漆"), 0x3f6650)]
        case .canvas:
            return [PencilBoxColour("denim", String(localized: "牛仔蓝"), 0x557a9c), PencilBoxColour("khaki", String(localized: "卡其"), 0xb39a6c, contrast: 0.9),
                    PencilBoxColour("olive", String(localized: "军绿"), 0x66704a), PencilBoxColour("wine", String(localized: "酒红"), 0x8a3a3e),
                    PencilBoxColour("oat", String(localized: "燕麦"), 0xd8ccb4, contrast: 0.75)]
        }
    }
    /// The box's own pictures (the things in it are every style's, and so is the red button).
    static let boxFiles: Set<String> = [
        "pencilbox-open.jpg", "pencilbox-across.jpg", "pencilbox-open-straps.png", "pencilbox-across-straps.png",
        "pencilbox-open-rack.png", "pencilbox-open-rack-up.png", "pencilbox-across-rack.png", "pencilbox-across-rack-up.png",
        "pencilbox-lid.jpg", "pencilbox-lid-inside.jpg", "pencilbox-tray.jpg", "pencilbox-icon-open.png", "pencilbox-icon-closed.png",
        "pencilbox-strap-band.png", "pencilbox-strap-end.png",
    ]
    /// Those whose colour changes, each with a mask beside it (the straps keep theirs).
    static let colouredFiles: Set<String> = boxFiles.subtracting(["pencilbox-open-straps.png", "pencilbox-across-straps.png",
                                                                  "pencilbox-strap-band.png", "pencilbox-strap-end.png"])
    /// A box picture in this style: the tin's go by the first names, another's have its name after
    /// "pencilbox-"; anything else is every style's.
    func file(_ name: String) -> String {
        guard self != .tin, Self.boxFiles.contains(name) else { return name }
        return "pencilbox-\(rawValue)-" + name.dropFirst("pencilbox-".count)
    }
    /// The mask beside a picture: white where the colour changes.
    func mask(_ name: String) -> String {
        let own = file(name)
        guard let dot = own.lastIndex(of: ".") else { return own + "-mask.png" }
        return String(own[..<dot]) + "-mask.png"
    }
}

/// The style and the colour chosen in 主题 › 铅笔盒, kept as "style.colour"; each style's own
/// last colour is kept too, for when it is chosen again.
struct PencilBoxLook: Equatable, Sendable {
    let style: PencilBoxStyle
    let colour: PencilBoxColour
    static let key = "FoldArc.pencilBox"
    static func colourKey(_ style: PencilBoxStyle) -> String { "FoldArc.pencilBox.\(style.rawValue)" }
    static let standard = PencilBoxLook(style: .tin, colour: PencilBoxStyle.tin.colours[0])
    init(style: PencilBoxStyle, colour: PencilBoxColour) {
        self.style = style
        self.colour = colour
    }
    init(id: String?) {
        let parts = (id ?? "").split(separator: ".", maxSplits: 1).map(String.init)
        let style = parts.first.flatMap(PencilBoxStyle.init(rawValue:)) ?? .tin
        let colour = parts.count > 1 ? style.colours.first { $0.id == parts[1] } : nil
        self.init(style: style, colour: colour ?? style.colours[0])
    }
    var id: String { "\(style.rawValue).\(colour.id)" }
    /// In the colour its pictures are drawn in: nothing to change.
    var isDrawn: Bool { colour.id == style.colours.first?.id }
    static var stored: PencilBoxLook { PencilBoxLook(id: UserDefaults.standard.string(forKey: key)) }
    /// A style in its last colour (or its first).
    static func remembered(_ style: PencilBoxStyle, defaults: UserDefaults = .standard) -> PencilBoxLook {
        let id = defaults.string(forKey: colourKey(style))
        return PencilBoxLook(style: style, colour: style.colours.first { $0.id == id } ?? style.colours[0])
    }
    /// What the change does to one colour of the shell (sRGB in and out): in Lab the lightness
    /// moves so the drawn colour lands on the new one (black stays black, white white), the chroma
    /// is scaled and the hue turned by the difference. PencilRecolour lays it out as a colour cube.
    func recolour(_ c: SIMD3<Double>) -> SIMD3<Double> {
        guard !isDrawn, let drawn = style.colours.first else { return c }
        let b = PencilLab.lab(drawn.rgb), t = PencilLab.lab(colour.rgb), p = PencilLab.lab(c)
        let l: Double = p.x < b.x ? t.x - (b.x - p.x) * (t.x / b.x) * colour.contrast : t.x + (p.x - b.x) * (100 - t.x) / (100 - b.x)
        let scale = hypot(t.y, t.z) / max(hypot(b.y, b.z), 1e-6)
        let turn = atan2(t.z, t.y) - atan2(b.z, b.y)
        let chroma = hypot(p.y, p.z) * scale, hue = atan2(p.z, p.y) + turn
        return PencilLab.rgb(SIMD3(l, chroma * cos(hue), chroma * sin(hue)))
    }
    /// Round the box where the display shows more than it (a phone): its colour, deep.
    var backdrop: SIMD3<Double> { colour.rgb * 0.55 }
}

/// sRGB ⇄ CIE Lab (D65).
enum PencilLab {
    private static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func gamma(_ c: Double) -> Double { let c = min(1, max(0, c)); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
    private static let white = SIMD3(0.95047, 1.0, 1.08883)
    private static func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : t * 24389 / 27 / 116 + 16.0 / 116 }
    private static func fi(_ t: Double) -> Double { t > 6.0 / 29 ? t * t * t : 3 * (6.0 / 29) * (6.0 / 29) * (t - 4.0 / 29) }
    static func lab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let r = linear(rgb.x), g = linear(rgb.y), b = linear(rgb.z)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / white.x
        let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / white.y
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / white.z
        let fx = f(x), fy = f(y), fz = f(z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
    static func rgb(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let fy = (lab.x + 16) / 116, fx = fy + lab.y / 500, fz = fy - lab.z / 200
        let x = fi(fx) * white.x, y = fi(fy) * white.y, z = fi(fz) * white.z
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return SIMD3(gamma(r), gamma(g), gamma(b))
    }
}

/// A breath on the iPhone's microphone for the cartridges' films. MicAnalysis gives it, buffer by buffer, the level
/// under ~300 Hz, the whole level (dBFS) and how long the buffer is (the system hands over about a tenth of a second
/// at a time). The wind of a breath on a microphone is loud and nearly all low; a film's own sound from the speaker
/// is not (a phone's speaker gives little under 300 Hz), nor a voice. So a breath is the low level within `windy` dB
/// of the whole level and `over` dB over what is heard anyway (and over `least`), for `startSeconds` running. It
/// ends once the sound has stopped being one for `endSeconds`: the low level `back` dB under where it had to begin,
/// or the sound no longer nearly all low (`stillWindy`: the film's sound again). What is heard anyway follows the
/// sound that is not a breath (down within a few tenths of a second, up within a couple of seconds). A breath longer
/// than `longest` is cut off and none begins until the sound stops being one (wind outdoors). A buffer of nothing at
/// all (digital silence: the input starting, or the system giving the app none) is no sound and changes nothing.
/// (11-23: before, the first buffer — silence — set what is heard anyway, which then took minutes to come up: a
/// film's loud passage passed as a breath and kept one going, and the wind with it.)
struct BreathGate: Sendable {
    /// What is heard anyway (dBFS, the low level); NaN until the first buffer with any sound in it.
    private(set) var floor = Double.nan
    private(set) var on = false
    private var loudFor = 0.0
    private var quietFor = 0.0
    private var lasted = 0.0
    /// The level the breath had to pass as it began (kept while it lasts).
    private var began = BreathGate.least
    /// A breath was cut off as too long: none until the sound stops being one.
    private var waiting = false
    static let windy = 5.0
    static let stillWindy = 7.0
    static let over = 8.0
    static let least = -38.0
    static let back = 4.0
    static let startSeconds = 0.15
    static let endSeconds = 0.2
    static let longest = 6.0
    /// A buffer at or under this (dBFS) has nothing in it: every sample zero.
    static let silence = -110.0
    /// The low level a breath has to pass now.
    var level: Double { floor.isNaN ? Self.least : max(Self.least, floor + Self.over) }
    /// A buffer that sounds like a breath now.
    func breathLike(_ low: Double, all: Double) -> Bool { low > level && all - low < Self.windy }
    /// One buffer: its low level, its whole level (dBFS) and its length (seconds).
    @discardableResult mutating func add(_ low: Double, all: Double, seconds: Double) -> Bool {
        guard all > Self.silence else { return on }
        let dt = max(0.001, seconds)
        if floor.isNaN { floor = low }
        if !on {
            let like = breathLike(low, all: all)
            if waiting {
                // (what goes on and on is what is heard anyway, soon enough)
                follow(low, dt)
                if like { return false }
                waiting = false
            }
            if like {
                loudFor += dt
                if loudFor >= Self.startSeconds - 1e-9 {
                    on = true
                    began = level
                    lasted = 0; quietFor = 0; loudFor = 0
                }
            } else {
                loudFor = 0
                follow(low, dt)
            }
        } else {
            lasted += dt
            let still = low > began - Self.back && all - low < Self.stillWindy
            quietFor = still ? 0 : quietFor + dt
            if quietFor >= Self.endSeconds - 1e-9 {
                on = false
                quietFor = 0; loudFor = 0
            } else if lasted >= Self.longest {
                on = false
                quietFor = 0; loudFor = 0
                waiting = true
            }
        }
        return on
    }
    /// What is heard anyway follows `low`: down within a few tenths of a second, up within a couple of seconds.
    private mutating func follow(_ low: Double, _ dt: Double) {
        let tau = low < floor ? 0.3 : 2.0
        floor += (low - floor) * min(1, dt / tau)
    }
}

/// 11-23: a hint shown only on a new console, the first time (only a console as it leaves the factory needs
/// one; after 格式化主机 it is new again): remembered under FoldArc.hint.<name>. DEBUG
/// `--foldarc-hints-again`: every hint as on a new console, and nothing remembered (the tests that look for one).
enum OnceHint {
    static let prefix = "FoldArc.hint."
    static func key(_ name: String) -> String { prefix + name }
    static var again: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--foldarc-hints-again")
        #else
        return false
        #endif
    }
    static func seen(_ name: String, in defaults: UserDefaults = .standard) -> Bool { !again && defaults.bool(forKey: key(name)) }
    static func mark(_ name: String, in defaults: UserDefaults = .standard) {
        guard !again else { return }
        defaults.set(true, forKey: key(name))
    }
    /// 格式化主机: a new console again.
    static func forgetAll(in defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) { defaults.removeObject(forKey: key) }
    }
}
