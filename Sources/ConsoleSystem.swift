import Foundation
import Combine
import CryptoKit
import Network
import os
#if os(iOS)
import AVFoundation
import UIKit
#endif
#if os(iOS) && !targetEnvironment(simulator)
import MediaPlayer
#endif

// The console's own system (round 23): what a handheld of this kind asks
// for the first time it is switched on and keeps in its system memory — the
// owner's name and birthday, the country, the language and region its
// software reads — and its system settings (sound, the touch screen, the
// Circle Pad, parental controls, power saving). The structure is a
// handheld's; the names, the layout and the marks are FoldArc's own.

/// The console's built-in programs (round 23): 系统设置, and the
/// first-time setup. They run on the console like software
/// (SystemSettingsApp.swift). Round 25: 相机 (CameraApp.swift).
enum ConsoleApp: String, Identifiable, Sendable {
    /// Round 26: the console's own menu on the handheld, full size (a pinch
    /// all the way into the console in the library; ConsoleHomeProgram.swift).
    /// Round 30: 游戏记录, 主题 and 说明书 are programs on the console's two
    /// screens too (they were pages over the shelf), as a handheld's play
    /// log and electronic manual are.
    /// Round 31: 游玩模式 is a
    /// program of the menu too (掌机、桌面、手柄、TV), no longer a small icon.
    /// Round 32 (11-05): 相册 (the camera's album as a program of its
    /// own) and 游戏笔记 (GameNotes.swift).
    /// 画框 (PictureFrame.swift): a scenery on the upper screen, the clock
    /// and a few switches on the lower. 铅笔盒 (PencilBox.swift; it was 铁皮盒): the small
    /// things a filling shelf brings.
    case settings, setup, camera, album, notes, home, activity, theme, manual, modes, pictureFrame, tinBox
    var id: String { rawValue }
    var title: String {
        switch self {
        case .settings: return String(localized: "系统设置")
        case .setup: return String(localized: "主机初始设置")
        case .camera: return String(localized: "相机")
        case .album: return String(localized: "相册")
        case .notes: return String(localized: "游戏笔记")
        case .home: return String(localized: "主菜单")
        case .activity: return String(localized: "游戏记录")
        case .theme: return String(localized: "主题")
        case .manual: return String(localized: "说明书")
        case .modes: return String(localized: "游玩模式")
        case .pictureFrame: return String(localized: "画框")
        case .tinBox: return String(localized: "铅笔盒")
        }
    }
    var symbol: String {
        switch self {
        case .settings: return "gearshape.fill"
        case .setup: return "sparkles"
        case .camera: return "camera.fill"
        case .album: return "photo.on.rectangle.angled"
        case .notes: return "pencil.and.outline"
        case .home: return "house.fill"
        case .activity: return "chart.bar.fill"
        case .theme: return "paintpalette.fill"
        case .manual: return "book.closed.fill"
        case .modes: return "rectangle.on.rectangle"
        case .pictureFrame: return "photo.artframe"
        case .tinBox: return "pencil.and.ruler"
        }
    }
}

/// The twelve languages the console's software can be told to use. The
/// core's names are Azahar's (`citra_language_value`, core_settings.cpp).
enum ConsoleLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case japanese, english, french, german, italian, spanish, simplifiedChinese, korean, dutch, portuguese, russian, traditionalChinese
    var id: String { rawValue }
    /// The iPhone's first language, as far as the console has it (English otherwise).
    static var deviceLanguage: ConsoleLanguage {
        let code = Locale.preferredLanguages.first ?? "en"
        if code.hasPrefix("zh") {
            return code.contains("Hant") || code.hasSuffix("TW") || code.hasSuffix("HK") || code.hasSuffix("MO") ? .traditionalChinese : .simplifiedChinese
        }
        let map: [String: ConsoleLanguage] = ["ja": .japanese, "en": .english, "fr": .french, "de": .german, "it": .italian, "es": .spanish,
                                              "ko": .korean, "nl": .dutch, "pt": .portuguese, "ru": .russian]
        return map[String(code.prefix(2))] ?? .english
    }
    var title: String {
        switch self {
        case .japanese: return String(localized: "日本語")
        case .english: return "English"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .spanish: return "Español"
        case .simplifiedChinese: return String(localized: "简体中文")
        case .korean: return "한국어"
        case .dutch: return "Nederlands"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        case .traditionalChinese: return String(localized: "繁體中文")
        }
    }
    /// 11-22: the app's own words come in Simplified Chinese and English: the console's language picks one of
    /// them (Chinese for either Chinese; English for the rest), as the console's own menus would follow it.
    var interfaceLanguage: String {
        switch self {
        case .simplifiedChinese, .traditionalChinese: return "zh-Hans"
        default: return "en"
        }
    }
    var coreValue: String {
        switch self {
        case .japanese: return "Japanese"
        case .english: return "English"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .spanish: return "Spanish"
        case .simplifiedChinese: return "Simplified Chinese"
        case .korean: return "Korean"
        case .dutch: return "Dutch"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .traditionalChinese: return "Traditional Chinese"
        }
    }
}

/// The console's hardware region. Software made for one region may refuse
/// another; "auto" lets the core pick the software's own (Azahar's
/// `citra_region_value`).
enum ConsoleRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto, japan, northAmerica, europe, australia, chinaMainland, korea, taiwan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return String(localized: "自动（跟着软件）")
        case .japan: return String(localized: "日本")
        case .northAmerica: return String(localized: "北美")
        case .europe: return String(localized: "欧洲")
        case .australia: return String(localized: "澳大利亚")
        case .chinaMainland: return String(localized: "中国大陆")
        case .korea: return String(localized: "韩国")
        case .taiwan: return String(localized: "中国台湾")
        }
    }
    var code: String {
        switch self {
        case .auto: return "AUTO"
        case .japan: return "JPN"
        case .northAmerica: return "USA"
        case .europe: return "EUR"
        case .australia: return "AUS"
        case .chinaMainland: return "CHN"
        case .korea: return "KOR"
        case .taiwan: return "TWN"
        }
    }
    var coreValue: String {
        switch self {
        case .auto: return "Auto"
        case .japan: return "Japan"
        case .northAmerica: return "USA"
        case .europe: return "Europe"
        case .australia: return "Australia"
        case .chinaMainland: return "China"
        case .korea: return "Korea"
        case .taiwan: return "Taiwan"
        }
    }
}

/// Where the owner lives (the profile's 国家/地区), with the region a
/// console bought there would have.
struct ConsoleCountry: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let region: ConsoleRegion
    var id: String { code }
    static let all: [ConsoleCountry] = [
        .init(code: "CN", name: String(localized: "中国大陆"), region: .chinaMainland),
        .init(code: "HK", name: String(localized: "中国香港"), region: .taiwan),
        .init(code: "MO", name: String(localized: "中国澳门"), region: .taiwan),
        .init(code: "TW", name: String(localized: "中国台湾"), region: .taiwan),
        .init(code: "JP", name: String(localized: "日本"), region: .japan),
        .init(code: "KR", name: String(localized: "韩国"), region: .korea),
        .init(code: "SG", name: String(localized: "新加坡"), region: .northAmerica),
        .init(code: "MY", name: String(localized: "马来西亚"), region: .northAmerica),
        .init(code: "US", name: String(localized: "美国"), region: .northAmerica),
        .init(code: "CA", name: String(localized: "加拿大"), region: .northAmerica),
        .init(code: "MX", name: String(localized: "墨西哥"), region: .northAmerica),
        .init(code: "BR", name: String(localized: "巴西"), region: .northAmerica),
        .init(code: "GB", name: String(localized: "英国"), region: .europe),
        .init(code: "FR", name: String(localized: "法国"), region: .europe),
        .init(code: "DE", name: String(localized: "德国"), region: .europe),
        .init(code: "IT", name: String(localized: "意大利"), region: .europe),
        .init(code: "ES", name: String(localized: "西班牙"), region: .europe),
        .init(code: "NL", name: String(localized: "荷兰"), region: .europe),
        .init(code: "PT", name: String(localized: "葡萄牙"), region: .europe),
        .init(code: "RU", name: String(localized: "俄罗斯"), region: .europe),
        .init(code: "AU", name: String(localized: "澳大利亚"), region: .australia),
        .init(code: "NZ", name: String(localized: "新西兰"), region: .australia),
    ]
    static func named(_ code: String) -> ConsoleCountry? { all.first { $0.code == code } }
}

/// The owner of the console: set in the first-time setup, changed in
/// 系统设置 › 其他设置 › 用户信息.
struct ConsoleProfile: Codable, Equatable, Sendable {
    var userName = ""
    var birthMonth = 1
    var birthDay = 1
    var country = ConsoleProfile.deviceCountry
    var language = ConsoleLanguage.deviceLanguage
    var region = ConsoleRegion.auto

    /// 11-07 (the English UI): a new console takes the iPhone's
    /// country and language (it was China and Simplified Chinese for all):
    /// the software it runs is told that language.
    static var deviceCountry: String {
        let code = Locale.current.region?.identifier ?? ""
        if ConsoleCountry.named(code) != nil { return code }
        return UILanguage.isChinese ? "CN" : "US"
    }

    /// A handheld's user name holds ten characters (UTF-16 units, as its
    /// system stores them).
    static let nameLimit = 10
    /// The name as it is kept: no line breaks or control characters, no
    /// spaces at the ends. (Nothing is cut while it is typed: cutting the
    /// text under an input method that is still composing — pinyin before
    /// the characters are chosen — breaks the composition. A name too long
    /// is shown so and cannot be confirmed.)
    static func cleanName(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }
    /// How long the name is, as the console counts it.
    var nameLength: Int { Self.cleanName(userName).utf16.count }
    var nameIsValid: Bool { nameLength > 0 && nameLength <= Self.nameLimit }
    /// The profile as it is kept (the name cleaned).
    var cleaned: ConsoleProfile {
        var copy = self
        copy.userName = Self.cleanName(userName)
        return copy
    }
    static func days(inMonth month: Int) -> Int {
        guard (1...12).contains(month) else { return 0 }
        return [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }
    var birthdayIsValid: Bool { (1...12).contains(birthMonth) && (1...Self.days(inMonth: birthMonth)).contains(birthDay) }
    var isValid: Bool { nameIsValid && birthdayIsValid && ConsoleCountry.named(country) != nil }
    var birthdayText: String { String(localized: "\(birthMonth)月\(birthDay)日") }
    var countryName: String { ConsoleCountry.named(country)?.name ?? country }
    /// Moves the birthday by days, wrapping through the year (the up and
    /// down arrows of the birthday page).
    mutating func stepBirthday(month delta: Int) {
        birthMonth = (birthMonth - 1 + delta + 12) % 12 + 1
        birthDay = min(birthDay, Self.days(inMonth: birthMonth))
    }
    mutating func stepBirthday(day delta: Int) {
        let days = Self.days(inMonth: birthMonth)
        birthDay = (birthDay - 1 + delta + days) % days + 1
    }
    /// What the core is told when software starts: the language and the
    /// region its system reports.
    var coreOptions: [String: String] {
        ["citra_language_value": language.coreValue, "citra_region_value": region.coreValue]
    }
}

/// How the game's sound comes out (系统设置 › 声音).
enum SoundOutput: String, CaseIterable, Identifiable, Codable, Sendable {
    case stereo, mono, surround
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stereo: return String(localized: "立体声")
        case .mono: return String(localized: "单声道")
        case .surround: return String(localized: "环绕声")
        }
    }
    var detail: String {
        switch self {
        case .stereo: return String(localized: "左右声道分开，原样输出")
        case .mono: return String(localized: "左右混成一路：只戴一只耳机、或者用单个扬声器时听得全")
        case .surround: return String(localized: "把左右的差别加大，声音听起来更宽")
        }
    }
    /// One stereo frame through this mode (interleaved Int16, in place).
    static func mix(_ mode: SoundOutput, left: inout Int16, right: inout Int16) {
        switch mode {
        case .stereo:
            return
        case .mono:
            let mid = (Int32(left) + Int32(right)) / 2
            left = Int16(mid); right = Int16(mid)
        case .surround:
            let mid = (Int32(left) + Int32(right)) / 2
            let side = (Int32(left) - Int32(right)) / 2
            let wide = side * 8 / 5
            left = Int16(clamping: mid + wide)
            right = Int16(clamping: mid - wide)
        }
    }
}

/// Parental controls: a four-digit PIN keeps the settings closed; behind it
/// three restrictions, and a secret question for a forgotten PIN.
struct ParentalControls: Codable, Equatable, Sendable {
    var pin: String?
    var question = 0
    var answer = ""
    var restrict3D = false
    var restrictImport = false
    var restrictDelete = false
    var isOn: Bool { pin != nil }
    static let questions = [String(localized: "你的第一只宠物叫什么？"), String(localized: "你出生在哪座城市？"), String(localized: "你最喜欢的游戏是什么？"), String(localized: "你最好的朋友叫什么？"), String(localized: "你上的第一所学校叫什么？")]
    static func isValidPIN(_ text: String) -> Bool { text.count == 4 && text.allSatisfy { $0.isASCII && $0.isNumber } }
    func unlocks(_ entered: String) -> Bool { pin != nil && pin == entered }
    static func normalized(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func answers(_ text: String) -> Bool { !answer.isEmpty && Self.normalized(text) == Self.normalized(answer) }
    var restrictions: Int { [restrict3D, restrictImport, restrictDelete].filter { $0 }.count }
}

/// The touch screen's correction (系统设置 › 触摸屏): where touches land
/// compared with where they were meant, as a fraction of the screen.
struct TouchCalibration: Codable, Equatable, Sendable {
    var dx = 0.0
    var dy = 0.0
    /// A correction larger than this is a missed target, not a skewed screen.
    static let limit = 0.06
    static let targets = [Point(x: 0.15, y: 0.2), Point(x: 0.85, y: 0.5), Point(x: 0.4, y: 0.82)]
    var isNeutral: Bool { abs(dx) < 0.0005 && abs(dy) < 0.0005 }
    func apply(_ point: Point) -> Point { Point(x: point.x + dx, y: point.y + dy).clamped }
    /// The correction that moves the touches onto the targets on average.
    static func fit(targets: [Point], touches: [Point]) -> TouchCalibration? {
        guard !targets.isEmpty, targets.count == touches.count else { return nil }
        var sx = 0.0, sy = 0.0
        for (target, touch) in zip(targets, touches) { sx += target.x - touch.x; sy += target.y - touch.y }
        let n = Double(targets.count)
        let dx = sx / n, dy = sy / n
        guard abs(dx) <= limit, abs(dy) <= limit else { return nil }
        return TouchCalibration(dx: dx, dy: dy)
    }
}

/// The Circle Pad's dead zone (系统设置 › 摇杆): small movements near the
/// middle count as none, the rest of the travel is stretched back to full.
enum StickTuning {
    static let maximumDeadzone = 0.3
    static func apply(_ point: Point, deadzone: Double) -> Point {
        let zone = min(maximumDeadzone, max(0, deadzone))
        let magnitude = hypot(point.x, point.y)
        guard magnitude > zone, magnitude > 0 else { return Point(x: 0, y: 0) }
        guard zone > 0 else { return point }
        let scaled = min(1, (magnitude - zone) / (1 - zone)) / magnitude
        return Point(x: point.x * scaled, y: point.y * scaled)
    }
}

/// One press of the iPhone's volume keys as FoldArc heard it (round 24):
/// which way, where the console's volume ended up, and whether it was
/// already at that end (then nothing moves, and the console says so).
struct VolumePress: Equatable {
    var up: Bool
    var level: Double
    var atLimit: Bool
    /// What the console shows for it.
    var label: String {
        if atLimit { return up ? String(localized: "音量 最大") : String(localized: "音量 静音") }
        return level == 0 ? String(localized: "音量 静音") : String(localized: "音量 \(Int((level * 100).rounded()))%")
    }
}

/// The iPhone's volume keys move the console's volume (round 23): the
/// system volume's change, applied to FoldArc's own slider.
enum VolumeKeys {
    static func level(after level: Double, systemFrom old: Float, to new: Float) -> Double {
        let next = min(1, max(0, level + Double(new - old)))
        return (next * 10_000).rounded() / 10_000
    }
}

/// Screen brightness in five steps, as the console's own setting has them
/// (over the same range as HOME › 画面与手感's slider, 40–100 %).
enum BrightnessSteps {
    static let levels = [0.4, 0.55, 0.7, 0.85, 1.0]
    static func level(for brightness: Double) -> Int {
        let nearest = levels.enumerated().min { abs($0.element - brightness) < abs($1.element - brightness) }
        return (nearest?.offset ?? 4) + 1
    }
    /// What the screens get: power saving keeps them a little darker.
    static func effective(_ brightness: Double, powerSaving: Bool) -> Double {
        powerSaving ? min(brightness, 0.75) : brightness
    }
}

/// Where the system settings are kept, and what is in them now.
@MainActor final class ConsoleSettings: ObservableObject {
    static let shared = ConsoleSettings()

    enum Key {
        static let setupDone = "FoldArc.setupDone"
        static let profile = "FoldArc.profile"
        static let soundOutput = "FoldArc.soundOutput"
        static let powerSaving = "FoldArc.powerSaving"
        static let touch = "FoldArc.touchCalibration"
        static let deadzone = "FoldArc.stickDeadzone"
        static let parental = "FoldArc.parental"
        static let stylusOut = "FoldArc.stylusOut"
        /// 11-05: silent mode, other apps' music.
        static let soundInSilentMode = "FoldArc.soundInSilentMode"
        static let otherAudio = "FoldArc.otherAudio"
        static let all = [setupDone, profile, soundOutput, powerSaving, touch, deadzone, parental, stylusOut, soundInSilentMode, otherAudio]
    }

    private let defaults: UserDefaults
    /// DEBUG `--foldarc-setup-pending` / `--foldarc-settings-dry-run`: the
    /// settings work for this run but nothing is kept (a UI test must not
    /// set up the Simulator's console for its owner, or change its
    /// settings).
    let dryRun: Bool
    @Published private(set) var setupDone: Bool
    @Published var profile: ConsoleProfile {
        didSet {
            store(profile, Key.profile)
            // 11-22: the menus follow the console's language from the next start (iOS picks the app's words
            // from AppleLanguages at launch; the iPhone's Settings › Zero EMU › Language writes the same key).
            if profile.language != oldValue.language, !dryRun {
                defaults.set([profile.language.interfaceLanguage], forKey: "AppleLanguages")
                NSLog("[system] the menus' language from the next start: %@", profile.language.interfaceLanguage)
            }
        }
    }
    @Published var soundOutput: SoundOutput { didSet { keep(soundOutput.rawValue, Key.soundOutput); SoundMix.shared.mode = soundOutput } }
    @Published var powerSaving: Bool { didSet { keep(powerSaving, Key.powerSaving) } }
    @Published var touch: TouchCalibration { didSet { store(touch, Key.touch) } }
    @Published var stickDeadzone: Double { didSet { keep(stickDeadzone, Key.deadzone) } }
    @Published var parental: ParentalControls { didSet { store(parental, Key.parental) } }
    /// The stylus is out of its hole in the console's back (in the hand).
    @Published var stylusOut: Bool { didSet { keep(stylusOut, Key.stylusOut) } }
    /// 系统设置 › 声音 (11-05): the game plays on with the iPhone in
    /// silent mode (as a handheld, only its own volume slider counts), and
    /// what happens to another app's music (AudioPolicy).
    @Published var soundInSilentMode: Bool {
        didSet { keep(soundInSilentMode, Key.soundInSilentMode); AudioPolicy.shared.soundInSilentMode = soundInSilentMode; AudioPolicy.shared.settingsChanged() }
    }
    @Published var otherAudio: OtherAudio {
        didSet { keep(otherAudio.rawValue, Key.otherAudio); AudioPolicy.shared.otherAudio = otherAudio; AudioPolicy.shared.settingsChanged() }
    }

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
            defaults.data(forKey: key).flatMap { try? decoder.decode(type, from: $0) }
        }
        var done = defaults.bool(forKey: Key.setupDone)
        var dry = false
        #if DEBUG
        // UI tests: set up (as far as this run knows; nothing is written),
        // not set up (and nothing it sets is kept), or nothing kept at all.
        if arguments.contains("--foldarc-setup-done") { done = true }
        if arguments.contains("--foldarc-setup-pending") { done = false; dry = true }
        if arguments.contains("--foldarc-settings-dry-run") { dry = true }
        #endif
        dryRun = dry
        setupDone = done
        profile = load(ConsoleProfile.self, Key.profile) ?? ConsoleProfile()
        soundOutput = defaults.string(forKey: Key.soundOutput).flatMap(SoundOutput.init(rawValue:)) ?? .stereo
        powerSaving = defaults.bool(forKey: Key.powerSaving)
        touch = load(TouchCalibration.self, Key.touch) ?? TouchCalibration()
        stickDeadzone = defaults.object(forKey: Key.deadzone) as? Double ?? 0.08
        parental = load(ParentalControls.self, Key.parental) ?? ParentalControls()
        stylusOut = defaults.bool(forKey: Key.stylusOut)
        soundInSilentMode = defaults.object(forKey: Key.soundInSilentMode) as? Bool ?? true
        otherAudio = defaults.string(forKey: Key.otherAudio).flatMap(OtherAudio.init(rawValue:)) ?? .mix
        SoundMix.shared.mode = soundOutput
        AudioPolicy.shared.soundInSilentMode = soundInSilentMode
        AudioPolicy.shared.otherAudio = otherAudio
    }

    private func keep(_ value: Any, _ key: String) {
        guard !dryRun else { return }
        defaults.set(value, forKey: key)
    }
    private func store<T: Encodable>(_ value: T, _ key: String) {
        guard !dryRun, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// The first-time setup is done: the console keeps its owner.
    func completeSetup(with profile: ConsoleProfile) {
        let profile = profile.cleaned
        self.profile = profile
        setupDone = true
        keep(true, Key.setupDone)
        // (what the owner gave — name, birthday, country — stays out of the log)
        NSLog("[system] setup done%@ (language %@)", dryRun ? " (not kept)" : "", profile.language.interfaceLanguage)
    }
    /// 系统设置 › 语言: the console's language, and the menus' from the next start — also when it is the
    /// language already chosen (before 11-22 the page only changed what the console told its software).
    func chooseLanguage(_ language: ConsoleLanguage) {
        profile.language = language
        guard !dryRun else { return }
        defaults.set([language.interfaceLanguage], forKey: "AppleLanguages")
    }
    /// 格式化: everything the console kept goes; the next start sets it up again.
    func forgetEverything() {
        if !dryRun { for key in Key.all { defaults.removeObject(forKey: key) } }
        setupDone = false
        profile = ConsoleProfile()
        // (the menus' language is the iPhone's again)
        if !dryRun { defaults.removeObject(forKey: "AppleLanguages") }
        soundOutput = .stereo
        powerSaving = false
        touch = TouchCalibration()
        stickDeadzone = 0.08
        parental = ParentalControls()
        stylusOut = false
        soundInSilentMode = true
        otherAudio = .mix
    }
}

/// How the game's sound is mixed right now, read on the audio thread (an
/// unfair lock: a few nanoseconds, no priority inversion to speak of).
final class SoundMix: Sendable {
    static let shared = SoundMix()
    private let current = OSAllocatedUnfairLock(initialState: SoundOutput.stereo)
    var mode: SoundOutput {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }
    /// Interleaved stereo Int16 frames, in place.
    func apply(_ samples: UnsafeMutablePointer<Int16>, frames: Int) {
        let mode = self.mode
        guard mode != .stereo, frames > 0 else { return }
        for frame in 0..<frames {
            var left = samples[frame * 2], right = samples[frame * 2 + 1]
            SoundOutput.mix(mode, left: &left, right: &right)
            samples[frame * 2] = left
            samples[frame * 2 + 1] = right
        }
    }
}

/// 别的 App 在放音乐时 (11-05): what a game
/// does with another app's music.
enum OtherAudio: String, CaseIterable, Identifiable, Codable, Sendable {
    case mix, pause, yield
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mix: return String(localized: "一起放")
        case .pause: return String(localized: "把音乐停掉")
        case .yield: return String(localized: "游戏不出声")
        }
    }
    var detail: String {
        switch self {
        case .mix: return String(localized: "游戏的声音和别的 App 的音乐混在一起。")
        case .pause: return String(localized: "开始玩游戏时，别的 App 的音乐停下；关掉游戏以后，它可以接着放。")
        case .yield: return String(localized: "别的 App 在放音乐时游戏不出声，音乐停了游戏的声音就回来（按键声照旧）。")
        }
    }
}

/// How FoldArc's audio session sits with the iPhone (系统设置 › 声音, 11-05;
/// the session was always
/// `.ambient`). Silent mode: by default FoldArc plays on, like a handheld
/// that only has its own volume slider (`.playback`); with the option off it
/// follows the switch (`.ambient`, as before). Another app's music: mixed;
/// stopped while a game holds the audio (a session that does not mix, given
/// back with `.notifyOthersOnDeactivation` when the game is closed); or the
/// game kept quiet while the system says secondary audio should be silenced
/// (`secondaryAudioShouldBeSilencedHint`, AzaharSession). The session is set
/// on the audio queues; this is read there (a lock, as SoundMix).
final class AudioPolicy: Sendable {
    static let shared = AudioPolicy()
    private struct State: Sendable {
        var soundInSilentMode = true
        var otherAudio = OtherAudio.mix
        /// A game's engine holds the audio (AzaharSession: start … stop).
        var gameHolds = false
        /// The microphone is on (MicListener).
        var listening = false
        /// 录像: the camera records its sound (CameraFeed).
        var recording = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "FoldArc.audioPolicy", qos: .utility)
    var soundInSilentMode: Bool {
        get { state.withLock { $0.soundInSilentMode } }
        set { state.withLock { $0.soundInSilentMode = newValue } }
    }
    var otherAudio: OtherAudio {
        get { state.withLock { $0.otherAudio } }
        set { state.withLock { $0.otherAudio = newValue } }
    }
    /// The game's sound is kept quiet now: 游戏不出声 while another app's
    /// primary audio plays.
    var gameYields: Bool {
        #if os(iOS)
        return otherAudio == .yield && AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        #else
        return false
        #endif
    }

    #if os(iOS)
    /// The category and options for now: everything mixes, except a game
    /// holding the audio when it is to stop the music.
    func session() -> (category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        let s = state.withLock { $0 }
        let exclusive = s.gameHolds && s.otherAudio == .pause
        // While the microphone is on, play and
        // record — out of the speaker (not the receiver), to Bluetooth and
        // AirPlay outputs as before; the silent switch is not heard then.
        if s.listening || s.recording {
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay]
            if !exclusive { options.insert(.mixWithOthers) }
            return (.playAndRecord, options)
        }
        if s.soundInSilentMode { return (.playback, exclusive ? [] : [.mixWithOthers]) }
        return (exclusive ? .soloAmbient : .ambient, [])
    }
    /// Sets the session as it should be now, if it is not (on the caller's
    /// queue — an audio queue; activating it is the caller's).
    func configure(_ reason: String) {
        let session = AVAudioSession.sharedInstance()
        let (category, options) = self.session()
        guard session.category != category || session.categoryOptions != options else { return }
        do {
            try session.setCategory(category, mode: .default, options: options)
            NSLog("[audio] session: %@%@ (%@)", Self.name(category), options.contains(.mixWithOthers) ? " + mixWithOthers" : "", reason)
        } catch {
            NSLog("[audio] session %@ not set (%@): %@", Self.name(category), reason, "\(error)")
        }
    }
    /// A game's sound starts (on its audio queue): with 把音乐停掉 the session
    /// stops mixing, and activating it takes the audio from the music app.
    func gameStarts() {
        state.withLock { $0.gameHolds = true }
        configure("game")
    }
    /// The game is closed (on its audio queue, its engine stopped): a session
    /// that held the audio lets go and tells the music app it can go on,
    /// then is active again, mixable (the volume keys are read from it).
    func gameEnds() {
        let held = state.withLock { s -> Bool in
            let held = s.gameHolds && s.otherAudio == .pause
            s.gameHolds = false
            return held
        }
        let session = AVAudioSession.sharedInstance()
        if held {
            do { try session.setActive(false, options: .notifyOthersOnDeactivation); NSLog("[audio] the game let the audio go (others told)") }
            catch { NSLog("[audio] the game's audio not let go: %@", "\(error)") }
        }
        configure("game closed")
        try? session.setActive(true)
    }
    /// 系统设置 › 声音 changed: the session follows at once.
    func settingsChanged() {
        queue.async { self.configure("settings") }
    }
    /// The microphone on or off (MicEngine, on its queue): the session
    /// is set for it and active again.
    func setListening(_ on: Bool) {
        state.withLock { $0.listening = on }
        configure(on ? "microphone on" : "microphone off")
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { NSLog("[audio] not active again (%@): %@", on ? "microphone on" : "microphone off", "\(error)") }
    }
    /// 录像: the camera's recording takes the microphone's sound (on
    /// the camera's session queue); the session plays and records meanwhile.
    func setRecording(_ on: Bool) {
        state.withLock { $0.recording = on }
        configure(on ? "recording video" : "video recorded")
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { NSLog("[audio] not active again (%@): %@", on ? "recording video" : "video recorded", "\(error)") }
    }
    static func name(_ category: AVAudioSession.Category) -> String {
        switch category {
        case .playback: return "playback"
        case .ambient: return "ambient"
        case .soloAmbient: return "soloAmbient"
        case .playAndRecord: return "playAndRecord"
        default: return category.rawValue
        }
    }
    #else
    func settingsChanged() {}
    #endif
}

/// What the iPhone's audio is doing (round 23): headphones plugged in or
/// connected, and the volume keys. (The Mac preview and the checks have no
/// audio session: nothing is heard there, the values stay as they are.)
@MainActor final class SystemAudio: ObservableObject {
    static let shared = SystemAudio()
    /// Headphones of any kind: wired, USB-C or Bluetooth.
    @Published private(set) var headphones = false
    @Published private(set) var outputName = ""
    /// Bumped each time the volume keys were pressed (round 24: also when
    /// the console's volume was already at that end and did not move).
    @Published private(set) var keyPresses = 0
    /// The last press: which way, and where the volume is (round 24).
    private(set) var lastPress: VolumePress?
    #if os(iOS)
    private var observation: NSKeyValueObservation?
    private var routeToken: NSObjectProtocol?
    private var activeToken: NSObjectProtocol?
    private var resignToken: NSObjectProtocol?
    /// The system volume as last heard (by the observation or the poll).
    private var heardVolume: Float = -1
    /// Reads the volume five times a second while FoldArc is in front. The
    /// observation is not always told: the iOS 27.1 simulator changes the
    /// value when its volume keys are pressed without telling observers
    /// (seen 10-30: 0.05 → 0.10 → 0.20 → 0.10 read, nothing observed).
    /// Whichever hears a change first reports it; the other then finds
    /// nothing new.
    private var poll: Timer?
    /// Volume changes until then are not the keys: a new route brings its
    /// own volume, and one changed while FoldArc was away is reported on
    /// the way back.
    private var quietUntil = Date.distantPast
    /// The outputs as last seen (a volume change can be reported before
    /// the route change it comes with).
    private var route = ""
    private var started = false
    static let headphonePorts: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio]
    /// The session is set up off the main thread: activating it there can
    /// stall the interface (the system logs it as a hang risk, 10-30: once
    /// per launch).
    nonisolated private static let sessionQueue = DispatchQueue(label: "FoldArc.systemAudio", qos: .utility)
    #endif

    /// Starts listening (once, at launch). The audio session is as 系统设置 ›
    /// 声音 says (AudioPolicy: mixable; with the silent switch or past it);
    /// it must be active for the system to report the volume.
    func start() {
        #if os(iOS)
        guard !started else { return }
        started = true
        Self.sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            AudioPolicy.shared.configure("launch")
            do { try session.setActive(true) } catch { NSLog("[audio] the audio session did not become active: %@", "\(error)") }
            Task { @MainActor in SystemAudio.shared.listen() }
        }
        #endif
    }

    #if os(iOS)
    private func listen() {
        let session = AVAudioSession.sharedInstance()
        heardVolume = session.outputVolume
        ConsoleVolume.shared.follow(system: session.outputVolume)
        observation = session.observe(\.outputVolume, options: [.new]) { _, change in
            guard let new = change.newValue else { return }
            Task { @MainActor in SystemAudio.shared.heard(new, by: "observed") }
        }
        routeToken = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemAudio.shared.updateRoute(changed: true) }
        }
        // Back from the background the session may have been let go: active
        // again, or the keys are not heard.
        activeToken = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            SystemAudio.sessionQueue.async { try? AVAudioSession.sharedInstance().setActive(true) }
            MainActor.assumeIsolated {
                SystemAudio.shared.quietUntil = Date().addingTimeInterval(1)
                SystemAudio.shared.updateRoute(changed: false)
                SystemAudio.shared.startPolling()
            }
        }
        // Away (HOME, Control Center, a call): the keys are the system's then.
        resignToken = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemAudio.shared.stopPolling() }
        }
        updateRoute(changed: false)
        startPolling()
        NSLog("[audio] listening: volume %.3f, headphones %@ (%@)", session.outputVolume, headphones ? "yes" : "no",
              session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ","))
        #if DEBUG
        VolumeViewProbe.runIfAsked()
        #endif
    }

    private func startPolling() {
        guard poll == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { SystemAudio.shared.heard(AVAudioSession.sharedInstance().outputVolume, by: "read") }
        }
        timer.tolerance = 0.05
        // Common modes: also while a finger is on a slider or a list.
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }
    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    /// A system volume, observed or read: a change from the last one heard
    /// is the keys (or Control Center), once.
    private func heard(_ volume: Float, by source: String) {
        guard volume != heardVolume else { return }
        let old = heardVolume
        heardVolume = volume
        guard old >= 0 else { return }
        volumeKeys(from: old, to: volume, by: source)
    }

    /// When the last tick was heard (round 26: a drag of the system's slider
    /// reports a change every few milliseconds; ticks come at most every
    /// 0.12 s then, and at every tenth).
    private var lastTick = Date.distantPast

    /// The system volume moved: by the keys, Control Center or (round 26)
    /// the console's own slider, which is the system's. The console's
    /// slider shows it. A new route brings its own volume (headphones keep
    /// theirs): the slider follows, quietly. (FoldArc's own volume, kept for
    /// the UI tests and the Mac preview, moves by as much, as in round 23.)
    private func volumeKeys(from old: Float, to new: Float, by source: String) {
        if Self.signature(AVAudioSession.sharedInstance().currentRoute) != route { updateRoute(changed: true) }
        guard Date() >= quietUntil else {
            NSLog("[audio] volume %.3f -> %.3f with a new route or on the way back: not a key", old, new)
            ConsoleVolume.shared.follow(system: new)
            return
        }
        let volume = ConsoleVolume.shared
        if volume.followsSystem {
            let before = volume.level
            volume.follow(system: new)
            NSLog("[audio] system volume (%@): %.3f -> %.3f", source, old, new)
            lastPress = VolumePress(up: new > old, level: volume.level, atLimit: false)
            keyPresses += 1
            let notch = Int((volume.level * 10).rounded(.down)) != Int((before * 10).rounded(.down)) || volume.level == 0
            if notch || Date().timeIntervalSince(lastTick) > 0.12 {
                lastTick = Date()
                ConsoleSounds.shared.play(.tick)
            }
            if notch { ConsoleHaptics.shared.play(volume.level == 0 || volume.level == 1 ? .sliderStop : .sliderNotch, .press) }
            return
        }
        let next = VolumeKeys.level(after: volume.level, systemFrom: old, to: new)
        NSLog("[audio] volume keys (%@): system %.3f -> %.3f, console %.2f -> %.2f", source, old, new, volume.level, next)
        // Every press shows (round 24): at an end of the slider nothing
        // moves, and before, nothing said so either (10-30: the console's
        // volume was at 100 % and the keys looked dead).
        let up = new > old
        let atLimit = next == volume.level
        let notch = Int((next * 10).rounded(.down)) != Int((volume.level * 10).rounded(.down)) || next == 0
        if !atLimit { volume.level = next }
        lastPress = VolumePress(up: up, level: volume.level, atLimit: atLimit)
        keyPresses += 1
        ConsoleSounds.shared.play(.tick)
        if atLimit { ConsoleHaptics.shared.play(.sliderStop, .press) }
        else if notch { ConsoleHaptics.shared.play(next == 0 ? .sliderStop : .sliderNotch, .press) }
    }

    private static func signature(_ route: AVAudioSessionRouteDescription) -> String {
        route.outputs.map { "\($0.portType.rawValue):\($0.uid)" }.joined(separator: ",")
    }
    private func updateRoute(changed: Bool) {
        let current = AVAudioSession.sharedInstance().currentRoute
        if changed { quietUntil = Date().addingTimeInterval(1) }
        route = Self.signature(current)
        let port = current.outputs.first { Self.headphonePorts.contains($0.portType) }
        var on = port != nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--foldarc-headphones") { on = true }
        #endif
        if headphones != on { NSLog("[audio] headphones %@ (%@)", on ? "in" : "out", port?.portName ?? "-") }
        headphones = on
        outputName = port?.portName ?? (on ? String(localized: "耳机") : "")
    }
    #endif
}

#if DEBUG && os(iOS) && !targetEnvironment(simulator)
/// `--foldarc-volume-probe` (round 26): what the system's volume slider
/// (MPVolumeView) is made of on this device — whether it shows a slider at
/// all (the Simulator has been known not to), its parts and their frames —
/// logged, and the view left on screen for a screenshot. (10-31, iOS 27.1
/// Simulator: no slider in it, only its hidden route button;
/// volumeSliderRect empty.)
@MainActor enum VolumeViewProbe {
    static func runIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("--foldarc-volume-probe") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let window = scenes.compactMap(\.keyWindow).first ?? scenes.first?.windows.first else {
                NSLog("[audio] probe: no window")
                return
            }
            let view = MPVolumeView(frame: CGRect(x: 30, y: 120, width: 260, height: 44))
            view.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.4)
            window.addSubview(view)
            view.layoutIfNeeded()
            @MainActor func dump(_ v: UIView, _ depth: Int) {
                NSLog("[audio] probe: %@%@ frame %@ hidden %d alpha %.2f enabled %d", String(repeating: "  ", count: depth), String(describing: type(of: v)),
                      NSCoder.string(for: v.frame), v.isHidden ? 1 : 0, v.alpha, v.isUserInteractionEnabled ? 1 : 0)
                if let slider = v as? UISlider { NSLog("[audio] probe: %@slider value %.3f min %.1f max %.1f", String(repeating: "  ", count: depth), slider.value, slider.minimumValue, slider.maximumValue) }
                for sub in v.subviews { dump(sub, depth + 1) }
            }
            dump(view, 0)
            NSLog("[audio] probe: volumeSliderRect %@, outputVolume %.3f", NSCoder.string(for: view.volumeSliderRect(forBounds: view.bounds)), AVAudioSession.sharedInstance().outputVolume)
            try? await Task.sleep(for: .seconds(1.5))
            NSLog("[audio] probe: after 1.5 s")
            dump(view, 0)
        }
    }
}
#elseif DEBUG && os(iOS)
/// The Simulator build does not link MediaPlayer (round 26); what the probe
/// found there, the first time (10-31, iOS 27.1): no slider in MPVolumeView,
/// only its hidden route button; volumeSliderRect empty.
@MainActor enum VolumeViewProbe {
    static func runIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("--foldarc-volume-probe") else { return }
        NSLog("[audio] probe: not in a Simulator build (MediaPlayer is not linked there; its MPVolumeView has no slider)")
    }
}
#endif

/// Whether the iPhone has a network, for 互联网设置.
@MainActor final class NetworkStatus: ObservableObject {
    static let shared = NetworkStatus()
    @Published private(set) var summary = String(localized: "正在检查…")
    private var monitor: NWPathMonitor?
    func start() {
        guard monitor == nil else { return }
        let made = NWPathMonitor()
        made.pathUpdateHandler = { path in
            let text: String
            if path.status != .satisfied { text = String(localized: "没有连接") }
            else if path.usesInterfaceType(.wifi) { text = String(localized: "已连接（Wi-Fi）") }
            else if path.usesInterfaceType(.cellular) { text = String(localized: "已连接（蜂窝网络）") }
            else if path.usesInterfaceType(.wiredEthernet) { text = String(localized: "已连接（有线网络）") }
            else { text = String(localized: "已连接") }
            Task { @MainActor in NetworkStatus.shared.summary = text }
        }
        made.start(queue: DispatchQueue(label: "FoldArc.network", qos: .utility))
        monitor = made
    }
}

/// The Circle Pad as the finger (or a controller's stick) holds it, before
/// the dead zone: 系统设置 › 摇杆 draws it. Kept only while that page is on
/// screen (`active`), so nothing is published during play.
@MainActor final class StickProbe: ObservableObject {
    static let shared = StickProbe()
    @Published private(set) var raw = Point(x: 0, y: 0)
    var active = false {
        didSet { if !active, raw != Point(x: 0, y: 0) { raw = Point(x: 0, y: 0) } }
    }
    func report(_ point: Point) {
        guard active, point != raw else { return }
        raw = point
    }
}

extension ParentalControls {
    /// The settings as kept, read where the main actor is not at hand (the
    /// 3D slider's stored position, read as a game loads).
    nonisolated static func stored(_ defaults: UserDefaults = .standard) -> ParentalControls {
        // ConsoleSettings.Key.parental (spelled out: that type is the main actor's).
        defaults.data(forKey: "FoldArc.parental").flatMap { try? JSONDecoder().decode(ParentalControls.self, from: $0) } ?? ParentalControls()
    }
}

/// Where FoldArc opens (round 23). A console that has been set up and holds
/// a card pushed home goes straight into that software; a console not set
/// up yet, or with no card in (or one only part of the way in), opens on the
/// library, where the first-time setup waits on its screens.
enum LaunchPlan: Equatable {
    case library
    case demo
    case game(URL, resume: Bool)

    /// The built-in demo's card (LibraryMenuView.cardID).
    static let demoCardID = "demo"

    /// `exists` answers for the game's copy and its resume state.
    static func decide(setupDone: Bool, insertedID: String, insertedOut: Double, games: [GameRecord], root: URL,
                       coreAvailable: Bool, arguments: [String], exists: (URL) -> Bool) -> LaunchPlan {
        // UI tests and checks by hand: the library, with an empty slot.
        if arguments.contains("--foldarc-library") || arguments.contains("--foldarc-eject") { return .library }
        guard setupDone, !insertedID.isEmpty, insertedOut < 0.0001 else { return .library }
        if insertedID == demoCardID { return .demo }
        guard coreAvailable, let game = games.first(where: { $0.id == insertedID }) else { return .library }
        let file = root.appendingPathComponent("ROMs").appendingPathComponent(game.fileName)
        guard exists(file) else { return .library }
        return .game(file, resume: exists(SaveStates.resume(for: file)))
    }

    /// What this launch finds: the settings kept, the card in the console,
    /// the library's index on disk.
    @MainActor static func atLaunch() -> LaunchPlan {
        let defaults = UserDefaults.standard
        let root = Storage.root
        let index = root.appendingPathComponent("library.json")
        let games = (try? JSONDecoder().decode([GameRecord].self, from: Data(contentsOf: index))) ?? []
        #if os(iOS)
        // 11-05: opened from a Home Screen quick action: that software
        // (on a console that is set up; a game needs the core).
        HomeScreenShortcuts.shared.launchDecided = true
        if let request = HomeScreenShortcuts.shared.atLaunch, ConsoleSettings.shared.setupDone,
           let plan = HomeScreenShortcuts.plan(for: request, games: games, root: root),
           plan == .demo || AzaharSession.isCoreAvailable {
            NSLog("[system] launch: %@ (Home Screen quick action)", plan.logText)
            return plan
        }
        #endif
        let plan = decide(setupDone: ConsoleSettings.shared.setupDone,
                          insertedID: defaults.string(forKey: "FoldArc.insertedCard") ?? "",
                          insertedOut: defaults.double(forKey: "FoldArc.insertedCardOut"),
                          games: games, root: root, coreAvailable: AzaharSession.isCoreAvailable,
                          arguments: ProcessInfo.processInfo.arguments,
                          exists: { FileManager.default.fileExists(atPath: $0.path) })
        NSLog("[system] launch: %@", plan.logText)
        return plan
    }

    var logText: String {
        switch self {
        case .library: return "library"
        case .demo: return "the demo's card"
        case .game(let url, let resume): return "\(url.lastPathComponent)\(resume ? " (resume)" : "")"
        }
    }
}

/// TV输出 (round 30; SystemSettingsApp.swift): where the console's two
/// screens go on a TV.
enum TVLayout: String, CaseIterable, Identifiable {
    case stacked, sideBySide, upperOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stacked: return String(localized: "上下两屏")
        case .sideBySide: return String(localized: "左右并排")
        case .upperOnly: return String(localized: "只显示上屏")
        }
    }
    /// Where the two screens go on a TV of `size` (the 3DS's 400 × 240 and
    /// 320 × 240, the same pixels big; the lower one nil when not shown).
    func frames(in size: CGSize) -> (top: CGRect, bottom: CGRect?) {
        let w = Double(size.width), h = Double(size.height)
        switch self {
        case .stacked:
            let u = min(w * 0.94 / 400, h * 0.94 / 492)
            let y0 = (h - 492 * u) / 2
            return (CGRect(x: (w - 400 * u) / 2, y: y0, width: 400 * u, height: 240 * u),
                    CGRect(x: (w - 320 * u) / 2, y: y0 + 252 * u, width: 320 * u, height: 240 * u))
        case .sideBySide:
            let u = min(w * 0.95 / 736, h * 0.9 / 240)
            let x0 = (w - 736 * u) / 2, y0 = (h - 240 * u) / 2
            return (CGRect(x: x0, y: y0, width: 400 * u, height: 240 * u),
                    CGRect(x: x0 + 416 * u, y: y0, width: 320 * u, height: 240 * u))
        case .upperOnly:
            let u = min(w * 0.96 / 400, h * 0.96 / 240)
            return (CGRect(x: (w - 400 * u) / 2, y: (h - 240 * u) / 2, width: 400 * u, height: 240 * u), nil)
        }
    }
}

/// 选电视: the TV that
/// TV模式 draws on the TV — seven old ones of FoldArc's own, after the sets of
/// their years (none of them a maker's model: no name, badge or logo), with
/// the upper screen in theirs; or 现代电视, none drawn, the screens as big as
/// the TV allows in 电视上的布局's layout. The lower screen stays on the
/// iPhone either way.
enum TVSet: String, CaseIterable, Identifiable, Sendable {
    case living, silver, game, combo, kids, lcd43, wide, modern
    static let defaultsKey = "foldarc.tv.set"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .living: return String(localized: "客厅大彩电")
        case .silver: return String(localized: "银灰平面")
        case .game: return String(localized: "游戏电视")
        case .combo: return String(localized: "录放一体机")
        case .kids: return String(localized: "儿童小彩电")
        case .lcd43: return String(localized: "银色液晶")
        case .wide: return String(localized: "黑色宽屏")
        case .modern: return String(localized: "现代电视")
        }
    }
    var era: String {
        switch self {
        case .living: return String(localized: "29 英寸显像管 · 2006 年前后")
        case .silver: return String(localized: "21 英寸显像管 · 1998–2004")
        case .game: return String(localized: "21 英寸显像管 · 1990 年前后")
        case .combo: return String(localized: "21 英寸显像管 · 2004 年前后")
        case .kids: return String(localized: "14 英寸显像管 · 2004 年前后")
        case .lcd43: return String(localized: "20 英寸液晶 · 2005 年前后")
        case .wide: return String(localized: "32 英寸液晶 · 2010 年前后")
        case .modern: return String(localized: "不画旧电视")
        }
    }
    var summary: String {
        switch self {
        case .living: return String(localized: "黑色前框、两边条形音箱孔、底下一条银色面板和圆形电源键：那几年客厅里最常见的平面直角彩电。")
        case .silver: return String(localized: "银灰外框，下沿微微弯出来，两边整片圆孔音箱，按键在右下角。")
        case .game: return String(localized: "顶上一个小台子插着卡带，电源、重置和一颗灯；屏幕角更圆、玻璃更鼓。")
        case .combo: return String(localized: "屏幕下面一个放录像带的口、一个放光碟的口，蓝色的小时间显示。")
        case .kids: return String(localized: "圆滚滚的薄荷绿外壳、提手、两个大旋钮、圆形喇叭。")
        case .lcd43: return String(localized: "早期液晶：4:3 的屏、细银框、下面一条长喇叭、圆底座。")
        case .wide: return String(localized: "亮黑边框、底边一道透明条、小底座，16:9。")
        case .modern: return String(localized: "画面直接铺满电视，按最好的画面显示；两块屏怎么摆，在「电视上的布局」里选。")
        }
    }
    /// A picture tube (the others are flat panels).
    var isTube: Bool {
        switch self {
        case .living, .silver, .game, .combo, .kids: return true
        case .lcd43, .wide, .modern: return false
        }
    }
    static var stored: TVSet {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(TVSet.init(rawValue:)) ?? .living
    }
}

/// 画面 for an old TV (b41): what a screen of its kind did to the picture
/// then, or the picture as sharp as it can be, still in that TV.
enum TVLook: String, CaseIterable, Identifiable, Sendable {
    case period, best
    static let defaultsKey = "foldarc.tv.look"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .period: return String(localized: "当年的画面")
        case .best: return String(localized: "最好的画面")
        }
    }
    func summary(on set: TVSet) -> String {
        switch self {
        case .period:
            return set.isTube ? String(localized: "显像管：一行一行的扫描线，亮的地方晕开一点，玻璃四角暗。")
                              : String(localized: "早期液晶：放大以后发虚，黑色发灰，四角漏一点光。")
        case .best: return String(localized: "像素方方正正、边缘锐利、颜色准；还是装在这台电视里。")
        }
    }
    /// The 画面滤镜 the upper screen is drawn with on such a TV (the rest of
    /// the look is the TV's own: see OldTVScreen).
    func filter(tube: Bool) -> ScreenFilter {
        switch self {
        case .period: return tube ? .crt : .smooth
        case .best: return .sharp
        }
    }
    static var stored: TVLook {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(TVLook.init(rawValue:)) ?? .period
    }
}

/// The old TVs drawn (b41): the shapes of the design sheet
/// (11-06, Docs/Design/round32-tv-sketches-20261106.jpg; the sheet's
/// script wrote these lists), one shape a line, in the drawing's widths (x
/// and y from its top left). The first line: S, the drawing's height, then
/// its screen's x, y, width, height and corner. Then each shape: its kind
/// (R a rectangle: x y w h corner; C a circle: x y r; E an ellipse: x y rx
/// ry; P a path: M L H V Q Z, absolute; T text: x y size, then | and the
/// text; D a grid of dots: x y columns rows dx dy r; G a grid of slots: x y
/// columns rows dx dy w h), its fill and stroke (- for none), the stroke's
/// width and the opacity, then the numbers.
enum TVArt {
    struct RGB: Equatable, Sendable {
        var red: Double, green: Double, blue: Double
        init?(hex: Substring) {
            guard hex.count == 7, hex.first == "#", let value = Int(hex.dropFirst(), radix: 16) else { return nil }
            red = Double((value >> 16) & 0xff) / 255
            green = Double((value >> 8) & 0xff) / 255
            blue = Double(value & 0xff) / 255
        }
    }
    enum Step: Equatable, Sendable {
        case move(Double, Double), line(Double, Double), horizontal(Double), vertical(Double)
        case quad(Double, Double, Double, Double), close
    }
    struct Mark: Equatable, Sendable {
        var kind: Character
        var fill: RGB?
        var stroke: RGB?
        var lineWidth: Double
        var opacity: Double
        var numbers: [Double]
        var steps: [Step] = []
        var text = ""
    }
    struct Drawing: Equatable, Sendable {
        /// Its height in widths.
        var height: Double
        /// Where its screen is, in widths, and the screen's corner.
        var screen: CGRect
        var screenCorner: Double
        var shapes: [Mark]
    }
    /// The TV drawn (nil for 现代电视, which has none).
    static func drawing(_ set: TVSet) -> Drawing? { drawings[set] }
    /// The upper screen (5:3) as big as fits in a TV's screen of `size`,
    /// centred: bars above and below on a 4:3 screen, at the sides on 16:9.
    static func upperScreen(in size: CGSize) -> CGRect {
        let w = min(size.width, size.height * 5 / 3), h = w * 3 / 5
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
    private static let drawings: [TVSet: Drawing] = {
        var all: [TVSet: Drawing] = [:]
        for set in TVSet.allCases {
            if let source = source(set), let drawing = parse(source) { all[set] = drawing }
        }
        return all
    }()

    /// A drawing from its lines; nil when one does not read.
    static func parse(_ source: String) -> Drawing? {
        let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let head = lines.first?.split(separator: " "), head.count == 7, head[0] == "S" else { return nil }
        let h = head.dropFirst().compactMap { Double($0) }
        guard h.count == 6 else { return nil }
        var shapes: [Mark] = []
        let counts: [Character: Int] = ["R": 5, "C": 3, "E": 4, "T": 3, "D": 7, "G": 8]
        for line in lines.dropFirst() {
            let text = line.firstIndex(of: "|").map { String(line[line.index(after: $0)...]) } ?? ""
            let body = line.firstIndex(of: "|").map { line[..<$0] } ?? Substring(line)
            let tokens = body.split(separator: " ")
            guard tokens.count >= 5, let kind = tokens[0].first, let lineWidth = Double(tokens[3]), let opacity = Double(tokens[4]) else { return nil }
            var shape = Mark(kind: kind, fill: RGB(hex: tokens[1]), stroke: RGB(hex: tokens[2]), lineWidth: lineWidth, opacity: opacity, numbers: [], text: text)
            if (tokens[1] != "-" && shape.fill == nil) || (tokens[2] != "-" && shape.stroke == nil) { return nil }
            let rest = tokens.dropFirst(5)
            if kind == "P" {
                var steps: [Step] = []
                var index = rest.startIndex
                func numbers(_ n: Int) -> [Double]? {
                    guard rest.distance(from: index, to: rest.endIndex) >= n else { return nil }
                    let values = rest[index..<rest.index(index, offsetBy: n)].compactMap { Double($0) }
                    index = rest.index(index, offsetBy: n)
                    return values.count == n ? values : nil
                }
                while index < rest.endIndex {
                    let command = rest[index]
                    index = rest.index(after: index)
                    switch command {
                    case "M": guard let v = numbers(2) else { return nil }; steps.append(.move(v[0], v[1]))
                    case "L": guard let v = numbers(2) else { return nil }; steps.append(.line(v[0], v[1]))
                    case "H": guard let v = numbers(1) else { return nil }; steps.append(.horizontal(v[0]))
                    case "V": guard let v = numbers(1) else { return nil }; steps.append(.vertical(v[0]))
                    case "Q": guard let v = numbers(4) else { return nil }; steps.append(.quad(v[0], v[1], v[2], v[3]))
                    case "Z": steps.append(.close)
                    default: return nil
                    }
                }
                guard !steps.isEmpty else { return nil }
                shape.steps = steps
            } else {
                guard let count = counts[kind], rest.count == count else { return nil }
                let values = rest.compactMap { Double($0) }
                guard values.count == count else { return nil }
                shape.numbers = values
            }
            shapes.append(shape)
        }
        return Drawing(height: h[0], screen: CGRect(x: h[1], y: h[2], width: h[3], height: h[4]), screenCorner: h[5], shapes: shapes)
    }

    private static func source(_ set: TVSet) -> String? {
        switch set {
        case .living:
            return """
            S 0.8 0.15 0.06 0.7 0.525 0.012
            R #202227 - 0 1 0 0 1 0.8 0.03
            R #ffffff - 0 0.06 0.006 0.0048 0.988 0.16 0.028
            G #0d0e11 - 0 1 0.035 0.128 3 9 0.028 0.0496 0.012 0.0352
            G #0d0e11 - 0 1 0.893 0.128 3 9 0.028 0.0496 0.012 0.0352
            R #0b0c0f - 0 1 0.138 0.048 0.724 0.549 0.02
            R #c3c8cf - 0 1 0 0.656 1 0.144 0.03
            R #c3c8cf - 0 1 0 0.656 1 0.04 0
            R #e6e9ed - 0 1 0 0.656 1 0.0096 0
            C #a9afb7 #8d939b 0.0042 1 0.5 0.728 0.022
            C #4fa3ff - 0 1 0.56 0.728 0.006
            G #9aa0a8 - 0 1 0.08 0.704 8 1 0.02 0 0.008 0.048
            R #aab0b8 - 0 1 0.82 0.708 0.11 0.04 0.016
            """
        case .silver:
            return """
            S 0.8837 0.1814 0.0728 0.6372 0.4779 0.0082
            P #cfd3d9 #a9afb7 0.0043 1 M 0.0067 0.0287 Q 0.0067 0.0021 0.0478 0.0021 H 0.9522 Q 0.9933 0.0021 0.9933 0.0287 V 0.7622 Q 1.0138 0.8418 0.9419 0.8594 Q 0.5 0.9036 0.0581 0.8594 Q -0.0138 0.8418 0.0067 0.7622 Z
            R #ffffff - 0 0.3 0.017 0.011 0.966 0.1591 0.0411
            R #bfc4cb - 0 1 0.0324 0.0905 0.1233 0.5833 0.0154
            D #7f858d - 0 1 0.0458 0.1126 6 22 0.0195 0.0256 0.0046
            R #bfc4cb - 0 1 0.8443 0.0905 0.1233 0.5833 0.0154
            D #7f858d - 0 1 0.8576 0.1126 6 22 0.0195 0.0256 0.0046
            R #3a3d43 - 0 1 0.1609 0.0523 0.6783 0.519 0.0154
            R #bfc4cb - 0 1 0.6028 0.7401 0.2672 0.053 0.0265
            R #9aa0a8 - 0 1 0.6182 0.7552 0.0267 0.0221 0.0088
            R #9aa0a8 - 0 1 0.6593 0.7552 0.0267 0.0221 0.0088
            R #9aa0a8 - 0 1 0.7004 0.7552 0.0267 0.0221 0.0088
            R #9aa0a8 - 0 1 0.7415 0.7552 0.0267 0.0221 0.0088
            C #aeb4bc #8d939b 0.0029 1 0.8391 0.7666 0.0164
            C #5ad16a - 0 1 0.1506 0.7666 0.0062
            """
        case .game:
            return """
            S 1.0267 0.12 0.2641 0.76 0.57 0.06
            P #45484f - 0 1 M 0.2 0.2067 L 0.27 0.0767 H 0.73 L 0.8 0.2067 Z
            R #5a5e66 - 0 1 0.27 0.0767 0.46 0.0156 0
            R #e9e6df #a49f96 0.0033 1 0.42 0.0017 0.16 0.0992 0.0096
            R #ff9f6b - 0 1 0.4328 0.0136 0.1344 0.0615 0.0064
            P #3bb7a5 - 0 1 M 0.4328 0.0632 L 0.5 0.0136 L 0.5352 0.0136 L 0.468 0.0751 Z
            C #fff3c4 - 0 1 0.5384 0.0433 0.0144
            R #1c1d21 - 0 1 0.4 0.1001 0.2 0.0234 0.0104
            C #3bb7a5 #2a8c7e 0.0033 1 0.32 0.1482 0.022
            R #9aa0a8 - 0 1 0.64 0.1313 0.07 0.0338 0.0104
            C #ff6b5c - 0 1 0.36 0.1482 0.006
            R #3a3c42 - 0 1 0 0.2067 1 0.82 0.05
            R #ffffff - 0 0.07 0.01 0.2149 0.98 0.1312 0.045
            R #26272c - 0 1 0.09 0.2341 0.82 0.63 0.07
            R #2c2e33 - 0 1 0.06 0.9119 0.88 0.0738 0.0164
            G #55585f - 0 1 0.1 0.9324 10 1 0.045 0 0.03 0.0328
            C #d9d9d9 - 0 1 0.86 0.9488 0.012
            C #e8c86a - 0 1 0.9 0.9488 0.012
            """
        case .combo:
            return """
            S 0.9203 0.1614 0.0662 0.6772 0.5079 0.006
            R #d3d7dc #a9afb7 0.0042 1 0.0021 0.0021 0.9959 0.9162 0.0249
            R #2a2c31 - 0 1 0.0419 0.0296 0.9162 0.6047 0.0199
            R #e4e7eb #b5bbc2 0.0028 1 0.0419 0.6617 0.9162 0.2199 0.0149
            R #c9ced5 #9aa0a8 0.0028 1 0.0817 0.6938 0.3585 0.0641 0.0092
            R #4a4d54 - 0 1 0.1017 0.7204 0.3187 0.011 0.0055
            R #c9ced5 #9aa0a8 0.0028 1 0.5199 0.6938 0.3585 0.0641 0.0092
            R #4a4d54 - 0 1 0.5398 0.7213 0.1992 0.0073 0.0037
            R #14324a - 0 1 0.7589 0.7075 0.0996 0.0366 0.0055
            T #7fd0ff - 0 1 0.8087 0.7369 0.0259 |0:00
            C #aab0b8 - 0 1 0.1216 0.8083 0.009
            C #aab0b8 - 0 1 0.1664 0.8083 0.009
            C #aab0b8 - 0 1 0.2112 0.8083 0.009
            C #aab0b8 - 0 1 0.256 0.8083 0.009
            C #aab0b8 - 0 1 0.3008 0.8083 0.009
            C #aab0b8 - 0 1 0.3456 0.8083 0.009
            C #aab0b8 - 0 1 0.3905 0.8083 0.009
            C #aab0b8 - 0 1 0.4353 0.8083 0.009
            C #aab0b8 - 0 1 0.4801 0.8083 0.009
            C #c3c8cf #8d939b 0.0028 1 0.8585 0.8083 0.0159
            """
        case .kids:
            return """
            S 0.8925 0.0923 0.1799 0.5967 0.4475 0.0696
            P - #4fae99 0.0348 1 M 0.3011 0.0858 Q 0.5 -0.051 0.6989 0.0858
            R #86d9c6 #4fae99 0.0056 1 0.0028 0.0773 0.9945 0.8125 0.1591
            E #ffffff - 0 0.35 0.3508 0.2056 0.2486 0.0684
            R #2f6f63 - 0 1 0.0575 0.1451 0.6663 0.5171 0.0895
            C #ffd166 #d9a43a 0.0056 1 0.8381 0.2911 0.0597
            R #d9a43a - 0 1 0.8302 0.2414 0.0159 0.0448 0.008
            C #ffd166 #d9a43a 0.0056 1 0.8381 0.4621 0.0597
            R #d9a43a - 0 1 0.8302 0.4124 0.0159 0.0448 0.008
            C - #4fae99 0.0056 1 0.8381 0.7016 0.0696
            C - #4fae99 0.0056 1 0.8381 0.7016 0.0497
            C - #4fae99 0.0056 1 0.8381 0.7016 0.0298
            C #ff8a5c - 0 1 0.4006 0.8042 0.0179
            """
        case .lcd43:
            return """
            S 1.1158 0.0446 0.0446 0.9109 0.6831 0
            R #b5bbc2 - 0 1 0.447 0.9713 0.1059 0.0953 0
            E #c3c8cf #9aa0a8 0.003 1 0.5 1.0772 0.2754 0.0371
            R #d6dade #a9afb7 0.0044 1 0.0022 0.0022 0.9956 0.9691 0.0318
            R #16171b - 0 1 0.0361 0.0361 0.9278 0.7001 0
            R #c1c6cd - 0 1 0.1293 0.8177 0.7414 0.0847 0.0424
            D #868c94 - 0 1 0.1611 0.841 34 3 0.0204 0.0191 0.0044
            C #4fa3ff - 0 1 0.9237 0.8601 0.0074
            """
        case .wide:
            return """
            S 0.6675 0.04 0.035 0.92 0.5175 0
            R #1a1b1f - 0 1 0.4 0.6075 0.2 0.035 0
            R #202227 - 0 1 0.3 0.6375 0.4 0.03 0.01
            R #121316 - 0 1 0 0 1 0.6075 0.012
            R #7a8796 - 0 0.6 0 0.5955 1 0.012 0.006
            P #ffffff - 0 0.05 M 0.5 0 L 0.62 0 L 0.38 0.6075 L 0.26 0.6075 Z
            C #4fa3ff - 0 1 0.5 0.5795 0.005
            """
        case .modern:
            return nil
        }
    }
}

// MARK: - 存档同步

/// 存档同步 (round 31):
/// the saves mirrored with a folder that syncs —
/// a folder of the user's in iCloud Drive (or another drive), picked once,
/// or the app's own iCloud container once the app has the iCloud
/// capability. Each file is compared three ways — here, there, and as both
/// were at the last sync (`Index`): what changed on one side goes to the
/// other; changed on both (or met for the first time and different), the
/// newer stays and the other is kept in 存档冲突 in the Files folder.
/// 11-05: a file is
/// known by its size and its contents (iCloud often stamps a new time on a
/// file it has uploaded: the time alone made copies and conflicts for
/// nothing); only the games' save folders go, never software installed in
/// the emulated SD card; a run tells how far it is; 修复同步 compares
/// everything again by content; a game's saves can be left out; and a save
/// state deleted here is deleted there too — by a note of what was deleted
/// (`Tombstone`: the file's path and contents), so only a copy that is
/// still exactly what was deleted goes, and it is moved aside (存档冲突 ›
/// 同步删掉的), not destroyed. Nothing else is ever deleted: a game's own
/// save gone on one side comes back from the other.
enum SaveSync {
    /// What is synced: a folder here, its name there, which of its files
    /// (by their path in it), and whether deletions go across.
    struct Area: Sendable {
        var name: String
        var local: URL
        var includes: @Sendable (String) -> Bool
        var syncsDeletions = false
    }
    struct Report: Equatable, Sendable {
        var uploaded = 0, downloaded = 0, conflicts = 0, unchanged = 0, waiting = 0, failed = 0
        /// Deleted here and there by a note from the other side (moved aside).
        var deletedThere = 0, deletedHere = 0
        var errors: [String] = []
        /// iCloud's placeholders asked for (their paths).
        var waitingFiles: [String] = []
        /// How much the saves take there.
        var bytes: Int64 = 0
        var repaired = false
        /// 11-22: stopped where it stood (a game started meanwhile): the rest at the next run.
        var stopped = false
        var summary: String {
            var parts: [String] = []
            if uploaded > 0 { parts.append(String(localized: "传上去 \(uploaded) 个")) }
            if downloaded > 0 { parts.append(String(localized: "拿下来 \(downloaded) 个")) }
            if deletedThere + deletedHere > 0 { parts.append(String(localized: "跟着删掉 \(deletedThere + deletedHere) 个即时存档")) }
            if conflicts > 0 { parts.append(String(localized: "\(conflicts) 个两边都改过（旧的那份在 Conflicts 里）")) }
            if waiting > 0 { parts.append(String(localized: "\(waiting) 个还在从云端下载")) }
            if failed > 0 { parts.append(String(localized: "\(failed) 个没成功")) }
            if stopped { parts.append(String(localized: "游戏开始了，剩下的等游戏关掉再同步")) }
            return parts.isEmpty ? String(localized: "都是最新的") : parts.joined(separator: String(localized: "，"))
        }
    }
    /// A file as it was: its size and modification time.
    struct Stamp: Codable, Equatable, Sendable {
        var size: Int64
        var modified: Double
    }
    struct Entry: Codable, Equatable, Sendable {
        var local: Stamp
        var cloud: Stamp
        /// The contents' SHA-256 at the last sync (the same on both sides
        /// then; nil in indexes written before 11-05).
        var hash: String? = nil
    }
    typealias Index = [String: Entry]
    /// A save state deleted on some device: what it was (11-05).
    struct Tombstone: Codable, Equatable, Sendable {
        var area: String
        var path: String
        var hash: String
        var deleted: Date
    }
    /// How far a run is.
    struct Progress: Equatable, Sendable {
        var done: Int
        var total: Int
        var current: String
    }
    /// The notes of deletions, there (beside the areas; hidden, so never
    /// taken for a save), kept 60 days.
    static let tombstoneName = ".foldarc-deleted.json"
    static let tombstoneDays = 60.0

    /// The saves: the games' own (the emulated SD card's `Nintendo 3DS`
    /// folder: save data and extra data) and the save states made with
    /// HOME's 保存进度 (not the 继续进度 made on leaving, nor the games).
    /// `leftOut`: games whose saves stay here (their states' names, their
    /// save folders' "title/<high>/<low>/").
    /// The areas' folders there. 11-07: in English — every device must use
    /// the same names whatever its language; they were 「3DS 存档」「即时存档」;
    /// a folder, an index key or
    /// a deletion note with an old name is read as the new one.
    static let gameSavesArea = "3DS Saves"
    static let statesArea = "Save States"
    static let oldAreaNames = ["3DS 存档": gameSavesArea, "即时存档": statesArea]
    /// What is kept aside here (in the app's Files folder) and, in it, what
    /// a deletion from another device moved out of the way. They were
    /// 「存档冲突」「同步删掉的」.
    static let conflictsName = "Conflicts"
    static let oldConflictsName = "存档冲突"
    static let deletedBySyncName = "Deleted by Sync"
    static func currentArea(_ name: String) -> String { oldAreaNames[name] ?? name }
    static func areas(console: URL, states: URL, leftOutStates: Set<String> = [], leftOutTitles: [String] = []) -> [Area] {
        [Area(name: gameSavesArea, local: console.appendingPathComponent("sdmc/Nintendo 3DS", isDirectory: true), includes: { path in
             isSaveData(path) && !leftOutTitles.contains { path.lowercased().contains($0) }
         }),
         Area(name: statesArea, local: states, includes: { path in
             !path.contains("/") && (path.hasSuffix(".state") || path.hasSuffix(".state.json")) && !path.contains(".resume.state")
                 && !leftOutStates.contains { path.hasPrefix($0 + ".") }
         }, syncsDeletions: true)]
    }
    /// A game's own save in the emulated SD card — its save data, extra data
    /// — and not software installed there (contents, its commands).
    static func isSaveData(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map { $0.lowercased() }
        if parts.contains("content") || parts.contains("cmd") { return false }
        return parts.contains("data") || parts.contains("extdata") || parts.contains("sysdata")
    }
    /// A title's save folder in the emulated SD card ("title/00040000/000ec300/").
    static func titleFolder(_ titleID: UInt64) -> String {
        String(format: "title/%08x/%08x/", UInt32(titleID >> 32), UInt32(titleID & 0xFFFF_FFFF))
    }

    static func sync(areas: [Area], cloud root: URL, index indexURL: URL, conflicts: URL, deletions pendingURL: URL? = nil,
                     repair: Bool = false, now: Date = Date(), shouldStop: @Sendable () -> Bool = { false },
                     progress: @Sendable (Progress) -> Void = { _ in }) -> Report {
        renameOldAreas(in: root)
        var report = Report()
        report.repaired = repair
        var index = repair ? [:] : loadIndex(indexURL)
        let previous = loadIndex(indexURL)
        // The deletions: this device's not sent yet, and everyone's there.
        let tombstoneURL = root.appendingPathComponent(tombstoneName)
        let pending = pendingURL.map(loadTombstones) ?? []
        let there = readTombstones(tombstoneURL)
        let fresh = (there + pending).filter { now.timeIntervalSince($0.deleted) < tombstoneDays * 86_400 }
        var tombstones: [Tombstone] = []
        for t in fresh where !tombstones.contains(where: { $0.area == t.area && $0.path == t.path && $0.hash == t.hash }) { tombstones.append(t) }
        if tombstones != there {
            do {
                try writeTombstones(tombstones, to: tombstoneURL)
                if let pendingURL { try? FileManager.default.removeItem(at: pendingURL) }
            } catch {
                report.errors.append(String(localized: "删除记录：\(error.localizedDescription)"))
            }
        } else if let pendingURL, !pending.isEmpty {
            try? FileManager.default.removeItem(at: pendingURL)
        }
        let moveAside = conflicts.appendingPathComponent(Self.stampName(now), isDirectory: true).appendingPathComponent(deletedBySyncName, isDirectory: true)
        for area in areas where area.syncsDeletions {
            let cloudArea = root.appendingPathComponent(area.name, isDirectory: true)
            for t in tombstones where t.area == area.name {
                let cloudURL = cloudArea.appendingPathComponent(t.path), localURL = area.local.appendingPathComponent(t.path)
                if FileManager.default.fileExists(atPath: cloudURL.path), fileHash(cloudURL) == t.hash {
                    do { try remove(cloudURL); report.deletedThere += 1 } catch { report.errors.append(String(localized: "\(area.name)/\(t.path)：\(error.localizedDescription)")) }
                }
                if FileManager.default.fileExists(atPath: localURL.path), fileHash(localURL) == t.hash {
                    do {
                        try copy(localURL, to: moveAside.appendingPathComponent(area.name, isDirectory: true).appendingPathComponent(t.path))
                        try FileManager.default.removeItem(at: localURL)
                        report.deletedHere += 1
                    } catch { report.errors.append(String(localized: "\(area.name)/\(t.path)：\(error.localizedDescription)")) }
                }
                index.removeValue(forKey: area.name + "/" + t.path)
            }
        }
        // What there is on both sides.
        var lists: [(area: Area, cloud: URL, here: [String: Stamp], there: [String: Stamp], waiting: Set<String>, paths: [String])] = []
        for area in areas {
            let cloudArea = root.appendingPathComponent(area.name, isDirectory: true)
            let here = files(in: area.local, includes: area.includes)
            let there = files(in: cloudArea, includes: area.includes)
            report.waiting += there.waiting.count
            report.waitingFiles += there.waiting.map { area.name + "/" + $0 }
            lists.append((area, cloudArea, here.files, there.files, Set(there.waiting), Set(here.files.keys).union(there.files.keys).sorted()))
        }
        let total = lists.reduce(0) { $0 + $1.paths.count }
        var done = 0
        walk: for list in lists {
            let area = list.area
            for relative in list.paths {
                // (11-22: a game started: what is done stays done and noted, the rest at the next run)
                if shouldStop() { report.stopped = true; break walk }
                progress(Progress(done: done, total: total, current: relative))
                done += 1
                // (11-22: in iCloud but not on this device yet, or not as it is there: asked for, and left alone till
                // it has come down — a copy made now would go over it unread)
                if list.waiting.contains(relative) { continue }
                let key = area.name + "/" + relative
                let localURL = area.local.appendingPathComponent(relative)
                let cloudURL = list.cloud.appendingPathComponent(relative)
                let last = index[key]
                var copied = false
                do {
                    switch (list.here[relative], list.there[relative]) {
                    case (.some, .none):
                        try copy(localURL, to: cloudURL)
                        report.uploaded += 1
                        copied = true
                    case (.none, .some):
                        try copy(cloudURL, to: localURL)
                        report.downloaded += 1
                        copied = true
                    case let (.some(l), .some(c)):
                        let localChanged = changed(l, since: last?.local, url: localURL, hash: last?.hash)
                        let cloudChanged = changed(c, since: last?.cloud, url: cloudURL, hash: last?.hash)
                        if last != nil, !localChanged, !cloudChanged {
                            report.unchanged += 1
                        } else if last != nil, localChanged, !cloudChanged {
                            try copy(localURL, to: cloudURL)
                            report.uploaded += 1
                            copied = true
                        } else if last != nil, !localChanged, cloudChanged {
                            try copy(cloudURL, to: localURL)
                            report.downloaded += 1
                            copied = true
                        } else if l.size == c.size, try sameContents(localURL, cloudURL) {
                            report.unchanged += 1
                        } else {
                            // Both changed: the newer stays on both sides,
                            // the other is kept in 存档冲突 (here).
                            let kept = conflicts.appendingPathComponent(Self.stampName(now), isDirectory: true)
                                .appendingPathComponent(area.name, isDirectory: true).appendingPathComponent(relative)
                            if l.modified >= c.modified {
                                try copy(cloudURL, to: kept)
                                try copy(localURL, to: cloudURL)
                            } else {
                                try copy(localURL, to: kept)
                                try copy(cloudURL, to: localURL)
                            }
                            report.conflicts += 1
                            copied = true
                        }
                    case (.none, .none):
                        continue
                    }
                    if let local = stamp(localURL), let cloud = stamp(cloudURL) {
                        // The contents' hash: worked out again only when they
                        // may have changed (a repair takes the old one when
                        // the file is as it was then).
                        let known = last?.hash ?? (previous[key].flatMap { $0.local == local ? $0.hash : nil })
                        index[key] = Entry(local: local, cloud: cloud, hash: copied || known == nil ? fileHash(localURL) : known)
                    }
                } catch {
                    report.failed += 1
                    report.errors.append(String(localized: "\(key)：\(error.localizedDescription)"))
                }
            }
        }
        progress(Progress(done: total, total: total, current: ""))
        report.bytes = areas.reduce(Int64(0)) { sum, area in
            sum + files(in: root.appendingPathComponent(area.name, isDirectory: true), includes: area.includes).files.values.reduce(0) { $0 + $1.size }
        }
        saveIndex(index, to: indexURL)
        return report
    }
    /// Whether a file differs from how it was at the last sync: its stamp,
    /// or — the size the same and only the time new — its contents.
    static func changed(_ now: Stamp, since then: Stamp?, url: URL, hash: String?) -> Bool {
        guard let then else { return true }
        if now == then { return false }
        if now.size == then.size, let hash, fileHash(url) == hash { return false }
        return true
    }

    /// The regular files under `folder` by their path in it, and the paths
    /// of iCloud's placeholders not downloaded yet (asked for: next time).
    static func files(in folder: URL, includes: (String) -> Bool) -> (files: [String: Stamp], waiting: [String]) {
        let fm = FileManager.default
        var result: [String: Stamp] = [:]
        var waiting: [String] = []
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else { return ([:], []) }
        let base = folder.standardizedFileURL.path
        func relative(_ url: URL) -> String? {
            var path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { return nil }
            path.removeFirst(base.count)
            while path.hasPrefix("/") { path.removeFirst() }
            return path
        }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                // `.<name>.icloud`: in iCloud, not on this device yet. The real path is worked out from the
                // placeholder's own: the enumerator hands out `/private/var/…`, and standardizing drops
                // `/private` only from a path that exists — the real file's does not yet, so it never matched `base`.
                if name.hasSuffix(".icloud"), let shown = relative(url), shown.hasSuffix(name) {
                    let path = String(shown.dropLast(name.count)) + String(name.dropFirst().dropLast(".icloud".count))
                    if includes(path) { waiting.append(path); try? fm.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(path)) }
                }
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]),
                  values.isRegularFile == true, let path = relative(url), includes(path) else { continue }
            // 11-22: in iCloud under its own name, but what is here is not what is there (not downloaded, or an older
            // version): asked for, and waiting like a placeholder. (A folder outside iCloud has no such status.)
            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                waiting.append(path)
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            result[path] = Stamp(size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
        return (result, waiting)
    }
    static func stamp(_ url: URL) -> Stamp? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        return Stamp(size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }
    /// The contents' SHA-256 (read a megabyte at a time).
    static func fileHash(_ url: URL) -> String? {
        var result: String?
        var coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordination) { readURL in
            guard let handle = try? FileHandle(forReadingFrom: readURL) else { return }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            result = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
    /// `source` copied over `destination`, both coordinated (the other side
    /// may be iCloud's or another provider's): into a temporary file first,
    /// then put in place in one step.
    static func copy(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], writingItemAt: destination, options: [.forReplacing],
                                       error: &coordination) { from, to in
            let temporary = to.deletingLastPathComponent().appendingPathComponent(".foldarc-sync-\(UUID().uuidString)")
            do {
                try fm.copyItem(at: from, to: temporary)
                if fm.fileExists(atPath: to.path) {
                    _ = try fm.replaceItemAt(to, withItemAt: temporary)
                } else {
                    try fm.moveItem(at: temporary, to: to)
                }
            } catch {
                try? fm.removeItem(at: temporary)
                failure = error
            }
        }
        if let error = coordination ?? failure { throw error }
    }
    /// A file there deleted (coordinated: a deletion noted on another device).
    static func remove(_ url: URL) throws {
        var coordination: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forDeleting], error: &coordination) { target in
            do { try FileManager.default.removeItem(at: target) } catch { failure = error }
        }
        if let error = coordination ?? failure { throw error }
    }
    static func sameContents(_ a: URL, _ b: URL) throws -> Bool {
        guard let one = fileHash(a), let two = fileHash(b) else { return false }
        return one == two
    }
    static func loadIndex(_ url: URL) -> Index {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let index = (try? JSONDecoder().decode(Index.self, from: data)) ?? [:]
        // Keys are "<area>/<path>": an old area name is read as the new one.
        guard index.keys.contains(where: { key in oldAreaNames.keys.contains { key.hasPrefix($0 + "/") } }) else { return index }
        var renamed: Index = [:]
        for (key, value) in index {
            let area = String(key.prefix { $0 != "/" })
            renamed[currentArea(area) + key.dropFirst(area.count)] = value
        }
        return renamed
    }
    static func saveIndex(_ index: Index, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: url, options: .atomic) }
    }
    private static var tombstoneCoder: (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }
    /// This device's deletions not sent yet.
    static func loadTombstones(_ url: URL) -> [Tombstone] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let list = (try? tombstoneCoder.1.decode([Tombstone].self, from: data)) ?? []
        return list.map { t in var t = t; t.area = currentArea(t.area); return t }
    }
    /// The old area folders there renamed (11-07), before a run: one
    /// left alone when the new one is there already (another device made it).
    static func renameOldAreas(in root: URL) {
        let fm = FileManager.default
        for (old, new) in oldAreaNames {
            let from = root.appendingPathComponent(old, isDirectory: true), to = root.appendingPathComponent(new, isDirectory: true)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            var coordination: NSError?
            NSFileCoordinator().coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing, error: &coordination) { a, b in
                do { try fm.moveItem(at: a, to: b); NSLog("[sync] 「%@」 renamed 「%@」", old, new) }
                catch { NSLog("[sync] 「%@」 could not be renamed: %@", old, error.localizedDescription) }
            }
        }
    }
    static func saveTombstones(_ list: [Tombstone], to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? tombstoneCoder.0.encode(list) { try? data.write(to: url, options: .atomic) }
    }
    /// The deletions noted there (coordinated).
    static func readTombstones(_ url: URL) -> [Tombstone] {
        var list: [Tombstone] = []
        var coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { readURL in
            list = loadTombstones(readURL)
        }
        return list
    }
    static func writeTombstones(_ list: [Tombstone], to url: URL) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("foldarc-deleted-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let data = try? tombstoneCoder.0.encode(list) else { return }
        try data.write(to: temporary, options: .atomic)
        try copy(temporary, to: url)
    }
    static func stampName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: date)
    }
    /// A 3DS title's ID from its copy (the cartridge's first partition, or
    /// the program itself): where its saves are in the emulated SD card.
    /// Homebrew has none.
    static func titleID(of copy: URL, format: ROMFormat) -> UInt64? {
        guard format == .cartridge || format == .executable else { return nil }
        func le64(_ data: Data, _ at: Int) -> UInt64? {
            guard data.count >= at + 8 else { return nil }
            return (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[data.startIndex + at + $1]) << (8 * UInt64($1)) }
        }
        // (A copy kept compressed is read as what is inside it.)
        guard let header: Data = GameFile.reading(copy, { header, _ in header }), header.count >= 0x200 else { return nil }
        if format == .executable {
            guard ROMImporter.hasMagic(header, of: .executable) else { return nil }
            return le64(header, 0x118)
        }
        // NCSD: the media ID at 0x108 is the title's.
        guard ROMImporter.hasMagic(header, of: .cartridge) else { return nil }
        return le64(header, 0x108)
    }
}

/// 存档同步's state and its runs (数据管理 › 存档同步): where, on or off, the
/// last result, how far a run is. Runs on a queue of its own; never while
/// a game is running (its saves stay as they are until it closes).
/// 11-07: the saves as one file, without iCloud — 数据管理 › 备份. 导出存档
/// copies the
/// games' own saves and the save states (the same two areas as 存档同步,
/// the same folder names) into "Zero EMU Saves <date>", zips it (the
/// system's own zipping: NSFileCoordinator `.forUploading`) and hands the
/// zip to the share sheet. 从备份恢复 takes such a folder back (a zip is
/// opened by a tap in Files first): what is not here is copied in, what is
/// the same is left, what differs replaces this device's copy, which is
/// kept in Conflicts first. Nothing is deleted.
enum SaveBackup {
    struct Report: Equatable, Sendable {
        var restored = 0
        var unchanged = 0
        var keptAside = 0
        var errors: [String] = []
        var summary: String {
            if restored + keptAside + unchanged == 0, errors.isEmpty { return String(localized: "这个文件夹里没有存档") }
            var parts: [String] = []
            if restored > 0 { parts.append(String(localized: "放回 \(restored) 个")) }
            if keptAside > 0 { parts.append(String(localized: "原来的 \(keptAside) 个放进了 Conflicts")) }
            if unchanged > 0 { parts.append(String(localized: "\(unchanged) 个本来就一样")) }
            if !errors.isEmpty { parts.append(String(localized: "\(errors.count) 个没成功")) }
            return parts.joined(separator: String(localized: "，"))
        }
    }
    enum Failure: LocalizedError {
        case nothing, zip(String)
        var errorDescription: String? {
            switch self {
            case .nothing: return String(localized: "还没有存档可以导出")
            case .zip(let reason): return String(localized: "没能打包：\(reason)")
            }
        }
    }
    static func folderName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "\(SaveSyncModel.folderName) \(formatter.string(from: date))"
    }
    /// The areas' files copied into `folder` ("<area>/<path>"): how many.
    static func stage(areas: [SaveSync.Area], into folder: URL) throws -> Int {
        let fm = FileManager.default
        var count = 0
        for area in areas {
            for (path, _) in SaveSync.files(in: area.local, includes: area.includes).files {
                let destination = folder.appendingPathComponent(area.name, isDirectory: true).appendingPathComponent(path)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: area.local.appendingPathComponent(path), to: destination)
                count += 1
            }
        }
        return count
    }
    /// The zip of the saves, in the temporary folder (the share sheet takes it from there).
    static func makeArchive(areas: [SaveSync.Area], now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
        let folder = work.appendingPathComponent(folderName(now), isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let count = try stage(areas: areas, into: folder)
        guard count > 0 else { try? fm.removeItem(at: work); throw Failure.nothing }
        let readme = """
        Zero EMU — saves backup / 存档备份

        3DS Saves: the games' own saves (from the emulated SD card).
        Save States: the save states made with Save state in the HOME Menu.

        To restore: unzip this file in Files (tap it), then in Zero EMU go to
        System Settings › Data Management › Backup › Restore from Backup and choose the folder.

        恢复：在「文件」里点一下这个 zip 解开，再到 Zero EMU 的
        系统设置 › 数据管理 › 备份 › 从备份恢复，选这个文件夹。
        """
        try readme.write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        var zipped: URL?
        var reason: String?
        var coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordination) { zip in
            // (The system's zip goes away after this block: copied out.)
            let destination = work.appendingPathComponent(folder.lastPathComponent + ".zip")
            do { try fm.copyItem(at: zip, to: destination); zipped = destination } catch { reason = error.localizedDescription }
        }
        if let coordination { reason = coordination.localizedDescription }
        guard let zipped else { throw Failure.zip(reason ?? "?") }
        NSLog("[backup] %d files into %@ (%lld bytes)", count, zipped.lastPathComponent, (try? zipped.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1)
        return zipped
    }
    /// A backup folder taken back (`backup` holds "3DS Saves", "Save States";
    /// or one folder up, the "Zero EMU Saves <date>" folder inside it).
    static func restore(from backup: URL, areas: [SaveSync.Area], conflicts: URL, now: Date = Date()) -> Report {
        let fm = FileManager.default
        var report = Report()
        var root = backup
        let names = Set(areas.map(\.name)).union(SaveSync.oldAreaNames.keys)
        if !names.contains(where: { fm.fileExists(atPath: backup.appendingPathComponent($0).path) }),
           let inner = (try? fm.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil))?
               .first(where: { $0.lastPathComponent.hasPrefix(SaveSyncModel.folderName) && $0.hasDirectoryPath }) {
            root = inner
        }
        let aside = conflicts.appendingPathComponent(SaveSync.stampName(now), isDirectory: true).appendingPathComponent("Replaced by Restore", isDirectory: true)
        for area in areas {
            var source = root.appendingPathComponent(area.name, isDirectory: true)
            if !fm.fileExists(atPath: source.path), let old = SaveSync.oldAreaNames.first(where: { $0.value == area.name })?.key {
                source = root.appendingPathComponent(old, isDirectory: true)
            }
            guard fm.fileExists(atPath: source.path) else { continue }
            for (path, _) in SaveSync.files(in: source, includes: area.includes).files.sorted(by: { $0.key < $1.key }) {
                let from = source.appendingPathComponent(path), to = area.local.appendingPathComponent(path)
                do {
                    if fm.fileExists(atPath: to.path) {
                        if SaveSync.fileHash(from) == SaveSync.fileHash(to) { report.unchanged += 1; continue }
                        try SaveSync.copy(to, to: aside.appendingPathComponent(area.name, isDirectory: true).appendingPathComponent(path))
                        report.keptAside += 1
                    }
                    try SaveSync.copy(from, to: to)
                    report.restored += 1
                } catch {
                    report.errors.append("\(area.name)/\(path)：\(error.localizedDescription)")
                }
            }
        }
        NSLog("[backup] restored from %@: %d in, %d the same, %d kept aside, %d failed", root.lastPathComponent, report.restored, report.unchanged, report.keptAside, report.errors.count)
        return report
    }
}

/// 11-22: a sync run told to stop where it stands (a game started, or the background time is up): asked for on the
/// main thread, read on the sync's queue between files.
final class SaveSyncStop: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = false
    var requested: Bool { lock.lock(); defer { lock.unlock() }; return asked }
    func request(_ stop: Bool) { lock.lock(); asked = stop; lock.unlock() }
}

@MainActor final class SaveSyncModel: ObservableObject {
    static let shared = SaveSyncModel()
    enum Place: String { case folder, iCloud }
    static let enabledKey = "foldarc.sync.enabled"
    static let placeKey = "foldarc.sync.place"
    static let bookmarkKey = "foldarc.sync.folderBookmark"
    static let folderNameKey = "foldarc.sync.folderName"
    static let lastKey = "foldarc.sync.last"
    /// Games whose saves stay on this device (11-05).
    static let leftOutKey = "foldarc.sync.leftOut"
    /// The folder made in the chosen place. 11-07: it was 「FoldArc 存档」; one found there is renamed before a run (its
    /// contents as they are, so nothing is copied again).
    /// 11-07: in English, the same on every device; it was
    /// 「Zero EMU 存档」 (from 11-07 afternoon) and 「FoldArc 存档」 before.
    static let folderName = "Zero EMU Saves"
    static let oldFolderNames = ["Zero EMU 存档", "FoldArc 存档"]
    /// Files › Zero EMU › Conflicts (the old 「存档冲突」 renamed, and in it
    /// each run's 「同步删掉的」 → Deleted by Sync).
    static func conflictsFolder() -> URL {
        let fm = FileManager.default
        let folder = Storage.filesFolder.appendingPathComponent(SaveSync.conflictsName, isDirectory: true)
        let old = Storage.filesFolder.appendingPathComponent(SaveSync.oldConflictsName, isDirectory: true)
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: folder.path) {
            do { try fm.moveItem(at: old, to: folder); NSLog("[sync] 「%@」 renamed 「%@」", SaveSync.oldConflictsName, SaveSync.conflictsName) }
            catch { NSLog("[sync] 「%@」 could not be renamed: %@", SaveSync.oldConflictsName, error.localizedDescription) }
            for stamp in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                let from = stamp.appendingPathComponent("同步删掉的", isDirectory: true)
                if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: stamp.appendingPathComponent(SaveSync.deletedBySyncName, isDirectory: true)) }
            }
        }
        return folder
    }

    @Published private(set) var enabled: Bool
    /// 存档同步 is Zero EMU Pro's (ProAccess): turned on and Pro open.
    /// Without Pro nothing is synced; what was set up stays as it was.
    var active: Bool { enabled && ProAccess.isPro }
    @Published private(set) var place: Place
    @Published private(set) var folderName: String?
    /// The app's iCloud container can be used (the capability is there and
    /// the device is signed in to iCloud).
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var running = false
    @Published private(set) var progress: SaveSync.Progress?
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastReport: SaveSync.Report?
    @Published private(set) var problem: String?
    @Published private(set) var leftOut: Set<String>
    /// A game is running: nothing is synced until it closes. 11-22: a run going on when a game starts stops at its
    /// next file (what it has done is noted), so a game never starts on saves being copied.
    var gameRunning = false {
        didSet {
            if gameRunning, running { stopper.request(true); NSLog("[sync] a game started: the run stops at its next file") }
            if oldValue && !gameRunning { syncSoon("game closed") }
        }
    }
    private let stopper = SaveSyncStop()
    #if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    /// 11-22: the folder picked last, by a name of its own (a new one each time a folder is picked).
    static let folderTagKey = "foldarc.sync.folderTag"
    private let queue = DispatchQueue(label: "foldarc.savesync", qos: .utility)
    private var pending: DispatchWorkItem?
    /// DEBUG `--foldarc-sync-folder=<tmp|path>`: a plain folder instead of a
    /// picked one (the tests' and the probe's).
    private var debugFolder: URL?

    private init() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: Self.enabledKey)
        place = Place(rawValue: defaults.string(forKey: Self.placeKey) ?? "") ?? .folder
        folderName = defaults.string(forKey: Self.folderNameKey)
        lastSync = defaults.object(forKey: Self.lastKey) as? Date
        leftOut = Set(defaults.stringArray(forKey: Self.leftOutKey) ?? [])
        #if DEBUG
        if let value = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-sync-folder=") }) {
            let path = String(value.dropFirst("--foldarc-sync-folder=".count))
            let folder = path == "tmp" ? FileManager.default.temporaryDirectory.appendingPathComponent("sync-test", isDirectory: true) : URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            debugFolder = folder
            folderName = folder.lastPathComponent
            place = .folder
            enabled = true
            NSLog("[sync] debug folder %@", folder.path)
        }
        #endif
        checkICloud()
    }

    /// Whether the app's iCloud container is there (asked off the main
    /// thread: it can take a while the first time).
    /// The container as last asked. Asking is a call to a system service
    /// that waits for its answer: on the device a sync started on the main
    /// thread held it 1.2 s there (a hang report, 11-11), so a run goes by
    /// this, and asks on the sync's queue first when there is none yet.
    private var container: URL?
    private var askingContainer = false
    func checkICloud() {
        queue.async {
            let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            // On the device: the row said 还不能用 with the entitlements in
            // place; what the system says, for the log: no iCloud account on
            // the iPhone (no identity token), or the container not given.
            NSLog("[sync] iCloud: %@; the app's container %@", FileManager.default.ubiquityIdentityToken == nil ? "no account signed in (no identity token)" : "an account is signed in",
                  container.map { "at …/\($0.lastPathComponent)" } ?? "not available")
            Task { @MainActor in
                self.iCloudAvailable = container != nil
                self.container = container
                if container == nil, self.place == .iCloud { self.problem = String(localized: "App 自己的 iCloud 空间现在用不了") }
            }
        }
    }
    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        NSLog("[sync] %@", on ? "on" : "off")
        if on { syncNow("turned on") }
    }
    /// A folder picked in the Files picker (security-scoped): kept as a
    /// bookmark for the next launches.
    func setFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.folderNameKey)
            UserDefaults.standard.set(UUID().uuidString, forKey: Self.folderTagKey)
            folderName = url.lastPathComponent
            place = .folder
            UserDefaults.standard.set(Place.folder.rawValue, forKey: Self.placeKey)
            problem = nil
            NSLog("[sync] folder %@", url.lastPathComponent)
            setEnabled(true)
        } catch {
            problem = String(localized: "记不住这个文件夹：\(error.localizedDescription)")
        }
    }
    /// Where the saves go: the app's own iCloud space or the folder picked.
    func use(_ next: Place) {
        guard next != place else { return }
        place = next
        UserDefaults.standard.set(place.rawValue, forKey: Self.placeKey)
        problem = nil
        NSLog("[sync] place: %@", next.rawValue)
        if enabled { syncNow("place changed") }
    }
    /// A game's saves kept on this device only (数据管理 › 软件 › the game).
    func setLeftOut(_ gameID: String, _ out: Bool) {
        if out { leftOut.insert(gameID) } else { leftOut.remove(gameID) }
        UserDefaults.standard.set(Array(leftOut).sorted(), forKey: Self.leftOutKey)
        NSLog("[sync] %@ %@", String(gameID.prefix(8)), out ? "left out" : "synced again")
    }
    /// A save state the user deleted (数据管理 › 即时存档): noted, so the
    /// copies elsewhere go too at the next run (only with 存档同步
    /// on, and only a copy that is still what was deleted).
    func noteDeleted(state url: URL) {
        guard enabled else { return }
        let names = [url.lastPathComponent, SaveStates.info(for: url).lastPathComponent]
        var list = SaveSync.loadTombstones(Self.pendingDeletions)
        for name in names {
            let file = url.deletingLastPathComponent().appendingPathComponent(name)
            guard let hash = SaveSync.fileHash(file) else { continue }
            list.append(SaveSync.Tombstone(area: SaveSync.statesArea, path: name, hash: hash, deleted: Date()))
        }
        SaveSync.saveTombstones(list, to: Self.pendingDeletions)
        NSLog("[sync] deletion noted: %@", url.lastPathComponent)
    }
    static var pendingDeletions: URL { Storage.root.appendingPathComponent("save-sync-deleted.json") }
    /// A sync a moment from now (several reasons in a row make one).
    func syncSoon(_ reason: String) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in Task { @MainActor in self?.syncNow(reason) } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }
    /// 修复同步: everything compared again by
    /// contents, the last run's notes not trusted; still nothing deleted.
    func repair() { syncNow("asked", repair: true) }
    func syncNow(_ reason: String, repair: Bool = false) {
        guard enabled, !running else { return }
        guard ProAccess.isPro else { NSLog("[sync] not run (%@): Pro is not open", reason); return }
        guard !gameRunning else { NSLog("[sync] waits: a game is running (%@)", reason); return }
        if debugFolder == nil, place == .iCloud, container == nil {
            guard !askingContainer else { return }
            askingContainer = true
            queue.async {
                let found = FileManager.default.url(forUbiquityContainerIdentifier: nil)
                Task { @MainActor in
                    self.askingContainer = false
                    self.iCloudAvailable = found != nil
                    guard let found else { self.problem = String(localized: "App 自己的 iCloud 空间现在用不了"); return }
                    self.container = found
                    self.syncNow(reason, repair: repair)
                }
            }
            return
        }
        guard let target = cloudRoot() else {
            problem = place == .iCloud ? String(localized: "App 自己的 iCloud 空间现在用不了") : String(localized: "还没选文件夹")
            return
        }
        let (root, scoped) = target
        running = true
        problem = nil
        progress = SaveSync.Progress(done: 0, total: 0, current: "")
        // (With the tests' folder its index and conflicts stay beside it.)
        let indexURL = debugFolder.map { $0.deletingLastPathComponent().appendingPathComponent("sync-test-index.json") } ?? placeIndex()
        let conflicts = debugFolder.map { $0.deletingLastPathComponent().appendingPathComponent("sync-test-conflicts", isDirectory: true) }
            ?? Self.conflictsFolder()
        let pendingURL = debugFolder.map { $0.deletingLastPathComponent().appendingPathComponent("sync-test-deleted.json") } ?? Self.pendingDeletions
        let cloud = root.appendingPathComponent(Self.folderName, isDirectory: true)
        for oldName in Self.oldFolderNames {
            let oldCloud = root.appendingPathComponent(oldName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: oldCloud.path), !FileManager.default.fileExists(atPath: cloud.path) else { continue }
            do {
                try FileManager.default.moveItem(at: oldCloud, to: cloud)
                NSLog("[sync] 「%@」 renamed 「%@」", oldName, Self.folderName)
            } catch {
                NSLog("[sync] 「%@」 could not be renamed: %@", oldName, error.localizedDescription)
            }
        }
        let console = Storage.consoleStorage(), states = SaveStates.folder
        let libraryIndex = Storage.root.appendingPathComponent("library.json")
        let leftOut = leftOut
        NSLog("[sync] start (%@%@) → %@", reason, repair ? ", repair" : "", cloud.path)
        let stop = self.stopper
        stop.request(false)
        #if os(iOS)
        // Leaving for the background: the run is let finish — or, when the system's time for it is up, told to stop
        // at its next file and let go of (11-22: else the system ends the app).
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "存档同步") { [weak self] in
            stop.request(true)
            self?.letGoOfBackground()
        }
        #endif
        queue.async {
            // The games left out: their states by name, their saves by title.
            let games = (try? JSONDecoder().decode([GameRecord].self, from: Data(contentsOf: libraryIndex))) ?? []
            let titles = games.filter { leftOut.contains($0.id) }.compactMap { game -> String? in
                let copy = Storage.root.appendingPathComponent("ROMs").appendingPathComponent(game.fileName)
                return SaveSync.titleID(of: copy, format: game.resolvedFormat).map(SaveSync.titleFolder)
            }
            let stateNames = Set(games.filter { leftOut.contains($0.id) }.map { ($0.fileName as NSString).deletingPathExtension })
            let areas = SaveSync.areas(console: console, states: states, leftOutStates: stateNames, leftOutTitles: titles)
            let report = SaveSync.sync(areas: areas, cloud: cloud, index: indexURL, conflicts: conflicts, deletions: pendingURL,
                                       repair: repair, shouldStop: { stop.requested }) { step in
                Task { @MainActor in if self.running { self.progress = step } }
            }
            if let scoped { scoped.stopAccessingSecurityScopedResource() }
            Task { @MainActor in
                #if os(iOS)
                self.letGoOfBackground()
                #endif
                self.running = false
                self.progress = nil
                self.lastReport = report
                self.lastSync = Date()
                UserDefaults.standard.set(self.lastSync, forKey: Self.lastKey)
                if !report.errors.isEmpty { self.problem = report.errors.first }
                NSLog("[sync] done%@: %@ (%lld bytes there)", repair ? " (repair)" : "", report.summary, report.bytes)
            }
        }
    }
    #if os(iOS)
    private func letGoOfBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    #endif
    /// 11-22: the last runs' notes, one file for each place the saves go — the app's iCloud space for the account
    /// signed in, or the folder picked last — so that notes about one place never stand for another (met again,
    /// a place is compared by contents first, as at the first run).
    private func placeIndex() -> URL {
        let name: String
        switch place {
        case .iCloud:
            let token = FileManager.default.ubiquityIdentityToken.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false) }
            name = "icloud-" + (token.map { SHA256.hash(data: $0).prefix(6).map { String(format: "%02x", $0) }.joined() } ?? "none")
        case .folder:
            var tag = UserDefaults.standard.string(forKey: Self.folderTagKey)
            if tag == nil {
                tag = UUID().uuidString
                UserDefaults.standard.set(tag, forKey: Self.folderTagKey)
            }
            name = "folder-" + String((tag ?? "").prefix(8)).lowercased()
        }
        return Storage.root.appendingPathComponent("save-sync-index-\(name).json")
    }
    /// Where the saves go now, and the security-scoped folder to let go of
    /// after the run (nil for the app's own container).
    private func cloudRoot() -> (URL, URL?)? {
        if let debugFolder { return (debugFolder, nil) }
        switch place {
        case .iCloud:
            guard let container else { return nil }
            return (container.appendingPathComponent("Documents", isDirectory: true), nil)
        case .folder:
            guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
                problem = String(localized: "找不到选的文件夹了，再选一次")
                return nil
            }
            let scoped = url.startAccessingSecurityScopedResource()
            if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
            return (url, scoped ? url : nil)
        }
    }
}

// MARK: - Awake

/// Whether the iPhone may dim and lock by itself. Nothing touches the
/// screen while software is played with a controller, or on the TV with
/// the phone put down, or while 画框 stands on a desk — so running software
/// and the frame each ask for it to stay awake, by name; it may sleep
/// again as soon as none of them asks.
@MainActor enum ScreenAwake {
    private static var reasons: Set<String> = []
    static var isHeld: Bool { !reasons.isEmpty }
    static func set(_ reason: String, _ on: Bool) {
        let before = !reasons.isEmpty
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        let now = !reasons.isEmpty
        guard now != before else { return }
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = now
        #endif
        NSLog("[awake] the iPhone %@", now ? "stays awake (\(reason))" : "may sleep again")
    }
}
