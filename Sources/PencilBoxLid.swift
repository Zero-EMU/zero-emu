import SwiftUI

// 铅笔盒's lid on the cover (PencilBox.swift): the box closed, what has been
// gathered stuck on it. A finger moves a thing (it lifts, its shadow falls
// farther, it is put down with a click); two fingers anywhere turn and size
// the one touched last; a tap: the music box plays, a photo or a note comes
// up close (a photo to be swiped through the album and changed for
// another; a note, touched again there, to be typed on), a postcard turns
// over (its back, its picture again), the rest give a little hop; held, a
// thing offers 放回铅笔盒, 摆正, 大一点, 小一点, and what can be done to the
// side that is up: a photo 换一张, a note 写字, a postcard's picture 换照片
// (换回原来的风景 once it is one's own), its back 写字 (its lines, its
// postcode, its stamp: PencilBigCard). Printed on the lid, it stays
// fixed to the hardware as the shell's print does. Held on a bare place
// (11-16), the lid draws back toward its hinge and the box's styles come
// beside it (PencilLidLooks): a touch puts one on, what is stuck on the
// lid staying where it is; a touch on the lid, or 选好了, and it is whole
// again.

// (The lid's frame in the window: PencilLidPlacement, Domain.swift.)

struct PencilBoxLid: View {
    var flipped = false
    var interfaceRotation: Double? = nil
    /// 11-22: drawn on the cover itself (not a phone's drawn lid): a hair larger than the display, so the lid's own
    /// rounded corners lie under the display's (the plastic box's are a little rounder: its pale ground showed in
    /// the corners).
    var fillsCover = false
    @ObservedObject private var store = PencilBoxStore.shared
    @ObservedObject private var music = TinMusicBox.shared
    /// The style and colour chosen in 主题 › 铅笔盒: the lid is that box's.
    @AppStorage(PencilBoxLook.key) private var lookID = PencilBoxLook.standard.id
    private static let space = "pencil-lid"
    private struct Twist: Equatable { var scale: Double; var angle: Double }
    @State private var selected: UUID?
    @State private var dragging: UUID?
    @State private var shift: CGSize = .zero
    @State private var twist: Twist?
    @State private var menu: UUID?
    @State private var shown: UUID?
    @State private var hopping: UUID?
    /// 11-17: the things that are playing (touched: PencilPlay), and since when.
    @State private var played: [UUID: Date] = [:]
    /// A postcard half way over (squeezed to its edge, to come back the other side up).
    @State private var turning: UUID?
    /// 11-15: a note being written on, here on the cover (typed: the cover
    /// takes no Apple Pencil). 11-16: or a postcard's back.
    @State private var writing: Writing?
    /// 11-16: the box's styles are beside the lid (held on a bare place of it).
    @State private var choosing = false
    /// 11-22: 存为壁纸 — being saved; what was said of it for a moment.
    @State private var savingWallpaper = false
    @State private var wallpaperSaid: String?
    @Environment(\.displayScale) private var displayScale
    private enum Writing: Identifiable {
        /// A postcard: written on where it was touched (nil: on its lines, as 写字 has it).
        case note(UUID), card(UUID, PencilBigCard.Field?)
        var id: String {
            switch self {
            case .note(let id): return "note-\(id.uuidString)"
            case .card(let id, _): return "card-\(id.uuidString)"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let placement = PencilLidPlacement.calculate(size: proxy.size, flipped: flipped, interfaceRotation: interfaceRotation)
            lid(placement.canvas)
                .frame(width: placement.canvas.width, height: placement.canvas.height)
                .rotationEffect(.degrees(placement.rotation))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onDisappear { music.stop() }
        .sheet(item: $writing) { what in
            switch what {
            case .note(let id): PencilNoteEditor(id: id, typingFirst: true) { writing = nil }
            case .card(let id, let first): PencilCardDesk(start: .card(id), writeFirst: first) { _ in writing = nil }
            }
        }
    }

    /// The lid's size while its styles are beside it.
    private static let chooserScale = 0.72
    private static let dark = Color(red: 0.07, green: 0.07, blue: 0.08)

    private func lid(_ canvas: CGSize) -> some View {
        let u = canvas.width / PencilArt.lid.width
        let small = Self.chooserScale
        return ZStack(alignment: .topLeading) {
            if choosing { Self.dark }
            ZStack(alignment: .topLeading) {
                PencilImages.image("pencilbox-lid.jpg", look: PencilBoxLook(id: lookID)).resizable()
                    .frame(width: canvas.width, height: canvas.height)
                    .scaleEffect(fillsCover && !choosing ? 1.02 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { menu = nil; shown = nil; selected = nil } }
                    // held on a bare place: the box's styles, beside the lid
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.55, maximumDistance: 12).onEnded { _ in startChoosing() })
                    .accessibilityHidden(true)
                ForEach(store.lid.sorted { $0.z < $1.z }) { piece in
                    pieceView(piece, u: u, canvas: canvas)
                }
                if let id = menu, let piece = store.lid.first(where: { $0.id == id }) {
                    menuCard(piece, u: u, canvas: canvas)
                }
                if let id = shown, let piece = store.lid.first(where: { $0.id == id }) {
                    closeUp(piece, u: u, canvas: canvas)
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            // (drawn back, it has the cover's own corners: the hinge's small, the others wide)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: choosing ? 8 * u : 0, bottomLeadingRadius: choosing ? 8 * u : 0,
                                              bottomTrailingRadius: choosing ? 59 * u : 0, topTrailingRadius: choosing ? 59 * u : 0, style: .continuous))
            .scaleEffect(choosing ? small : 1, anchor: .leading)
            .allowsHitTesting(!choosing)
            if choosing {
                Color.clear
                    .frame(width: canvas.width * small, height: canvas.height)
                    .contentShape(Rectangle())
                    .onTapGesture { stopChoosing() }
                    .accessibilityElement()
                    .accessibilityLabel(Text("选好了"))
                    .accessibilityAddTraits(.isButton)
                PencilLidLooks(lookID: lookID, u: u, choose: wear, done: stopChoosing)
                    .frame(width: canvas.width * (1 - small) - 4 * u, height: canvas.height)
                    .offset(x: canvas.width * small + 4 * u)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                wallpaperKey(canvas, u: u, small: small)
                    .transition(.opacity)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .clipped()
        .coordinateSpace(name: Self.space)
        .simultaneousGesture(twistGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pencil-lid")
    }

    // MARK: The lid as a wallpaper (11-22)

    /// Under the lid while its styles are beside it: 存为壁纸, a see-through key; what it said for a moment above it.
    private func wallpaperKey(_ canvas: CGSize, u: Double, small: Double) -> some View {
        let below = canvas.height * (1 + small) / 2
        let room = canvas.height - below
        return VStack(spacing: 6 * u) {
            if let said = wallpaperSaid {
                Text(verbatim: said)
                    .font(.system(size: 11 * u, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            Button { saveWallpaper(canvas) } label: {
                Label("存为壁纸", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13 * u, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 16 * u).frame(minHeight: max(44, 36 * u))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .opacity(savingWallpaper ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(savingWallpaper)
            .accessibilityIdentifier("pencil-lid-wallpaper")
        }
        .frame(width: canvas.width * small - 16 * u)
        .position(x: canvas.width * small / 2, y: below + room / 2)
    }
    /// The lid as the cover shows it (the box's look, what is stuck on it, upright), at the display's own pixels,
    /// into Photos (add only: the system asks the first time).
    private func saveWallpaper(_ canvas: CGSize) {
        guard !savingWallpaper else { return }
        let picture = PencilLidPicture(look: PencilBoxLook(id: lookID), canvas: canvas, pieces: store.lid.sorted { $0.z < $1.z })
        let renderer = ImageRenderer(content: picture)
        renderer.scale = displayScale
        #if os(iOS)
        guard let image = renderer.uiImage, let jpeg = image.jpegData(compressionQuality: 0.92) else { said(String(localized: "没存上")); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zero-lid-\(UUID().uuidString).jpg")
        do { try jpeg.write(to: url, options: .atomic) } catch { said(String(localized: "没存上")); return }
        savingWallpaper = true
        ConsoleSounds.shared.play(.click)
        Task { @MainActor in
            let outcome = await SystemPhotos.add(url)
            try? FileManager.default.removeItem(at: url)
            savingWallpaper = false
            switch outcome {
            case .added:
                said(String(localized: "已存到「照片」"))
                ConsoleHaptics.shared.play(.faceButton, .press)
                NSLog("[pencil] the lid saved as a wallpaper (%ld x %ld)", Int(image.size.width * image.scale), Int(image.size.height * image.scale))
            case .notAllowed:
                said(String(localized: "「照片」没让存：设置 › Zero EMU › 照片"))
                NSLog("[pencil] the lid as a wallpaper: Photos did not allow it")
            case .failed, .off:
                said(String(localized: "没存上"))
                NSLog("[pencil] the lid as a wallpaper: not saved")
            }
        }
        #endif
    }
    private func said(_ words: String) {
        withAnimation(.easeOut(duration: 0.15)) { wallpaperSaid = words }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if wallpaperSaid == words { withAnimation(.easeOut(duration: 0.3)) { wallpaperSaid = nil } }
        }
    }

    // MARK: The box's styles, beside the lid (11-16)

    private func startChoosing() {
        guard dragging == nil, !choosing else { return }
        menu = nil; shown = nil; selected = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { choosing = true }
        ConsoleHaptics.shared.play(.faceButton, .press)
        NSLog("[pencil] the box's styles, beside the lid")
    }
    private func stopChoosing() {
        guard choosing else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { choosing = false }
        ConsoleSounds.shared.play(.back)
    }
    /// A style and colour put on: the lid here, the open box and the library's small one with it.
    private func wear(_ look: PencilBoxLook) {
        guard look.id != lookID else { ConsoleHaptics.shared.play(.smallButton, .press); return }
        lookID = look.id
        UserDefaults.standard.set(look.colour.id, forKey: PencilBoxLook.colourKey(look.style))
        ConsoleSounds.shared.play(.select)
        ConsoleHaptics.shared.play(.faceButton, .press)
        NSLog("[pencil] look %@, from the lid", look.id)
    }

    // MARK: A piece

    private struct Live { var x: Double; var y: Double; var angle: Double; var scale: Double }
    private func live(_ piece: PencilPiece, canvas: CGSize) -> Live {
        var at = Live(x: piece.x * canvas.width, y: piece.y * canvas.height, angle: piece.angle, scale: piece.scale)
        if dragging == piece.id { at.x += shift.width; at.y += shift.height }
        if let twist, selected == piece.id { at.angle += twist.angle; at.scale = PencilLayout.clampScale(at.scale * twist.scale) }
        return at
    }

    private func pieceView(_ piece: PencilPiece, u: Double, canvas: CGSize) -> some View {
        let at = live(piece, canvas: canvas)
        let art = piece.art
        // Lifted, its shadow falls farther and softer.
        let lift = dragging == piece.id ? 1.7 : 1.0
        let squeeze = turning == piece.id ? 0.04 : 1.0
        return ZStack {
            PencilPieceView(piece: piece, u: u, scale: at.scale, layer: .shadow)
                .scaleEffect(x: squeeze, y: 1)
                .rotationEffect(.radians(at.angle))
                .offset(x: art.shadow.width * u * at.scale * lift, y: art.shadow.height * u * at.scale * lift)
                .opacity(dragging == piece.id ? 0.8 : 1)
            PencilPieceView(piece: piece, u: u, scale: at.scale, layer: .face, played: played[piece.id])
                .scaleEffect(x: squeeze, y: 1)
                .rotationEffect(.radians(at.angle))
                .scaleEffect(hopping == piece.id ? 1.1 : (dragging == piece.id ? 1.04 : 1))
            Color.clear
                .frame(width: art.size.width * u * at.scale * 0.78, height: art.size.height * u * at.scale * 0.78)
                .contentShape(Rectangle())
                .rotationEffect(.radians(at.angle))
                .gesture(drag(piece, canvas: canvas))
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in hold(piece) })
                .gesture(SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { value in tap(piece, at: value.location, u: u, canvas: canvas) })
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: piece.fullTitle))
                .accessibilityValue(Text(verbatim: piece.kind == .postcard ? cardWords(piece) : noteWords(piece)))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("pencil-piece-\(piece.thing?.rawValue ?? piece.tool.map { "tool-\($0.rawValue)" } ?? piece.scene.map { "postcard-\($0.rawValue)" } ?? piece.kind.rawValue)")
                .accessibilityAction(named: Text("放回铅笔盒")) { store.takeOff(piece.id) }
                .accessibilityAction(named: Text("往上挪")) { nudge(piece, 0, -0.04) }
                .accessibilityAction(named: Text("往下挪")) { nudge(piece, 0, 0.04) }
                .accessibilityAction(named: Text("往左挪")) { nudge(piece, -0.05, 0) }
                .accessibilityAction(named: Text("往右挪")) { nudge(piece, 0.05, 0) }
                .accessibilityAction(named: Text("大一点")) { store.set(piece.id, angle: piece.angle, scale: piece.scale * 1.15) }
                .accessibilityAction(named: Text("小一点")) { store.set(piece.id, angle: piece.angle, scale: piece.scale / 1.15) }
                .accessibilityAction(named: Text("转一下")) { store.set(piece.id, angle: piece.angle + 0.26, scale: piece.scale) }
                .accessibilityAction(named: Text("摆正")) { store.set(piece.id, angle: 0, scale: piece.scale) }
        }
        .position(x: at.x, y: at.y)
    }

    /// A postcard read out: the side that is up; its back, with what is written on it.
    private func cardWords(_ piece: PencilPiece) -> String {
        guard piece.back == true else { return String(localized: "正面") }
        return ([String(localized: "背面")] + [piece.postcode, piece.words].compactMap { $0 }).joined(separator: "，")
    }
    private func noteWords(_ piece: PencilPiece) -> String {
        guard piece.kind == .note else { return "" }
        return store.note(piece.id)?.text ?? ""
    }

    private func nudge(_ piece: PencilPiece, _ dx: Double, _ dy: Double) {
        store.move(piece.id, x: piece.x + dx, y: piece.y + dy)
    }

    private func drag(_ piece: PencilPiece, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragging != piece.id {
                    dragging = piece.id
                    selected = piece.id
                    menu = nil
                    shown = nil
                    store.raise(piece.id)
                    ConsoleHaptics.shared.play(.smallButton, .press)
                }
                shift = value.translation
            }
            .onEnded { value in
                let x = (piece.x * canvas.width + value.translation.width) / max(1, canvas.width)
                let y = (piece.y * canvas.height + value.translation.height) / max(1, canvas.height)
                store.move(piece.id, x: x, y: y)
                dragging = nil
                shift = .zero
                ConsoleHaptics.shared.play(.smallButton, .release)
                // put down: a magnet (a print's, a note's, a postcard's, a plastic letter) snaps onto the lid
                ConsoleSounds.shared.play(piece.magnet != nil || piece.thing?.isMagnet == true ? .magnet : .click)
            }
    }

    private var twistGesture: some Gesture {
        MagnifyGesture().simultaneously(with: RotateGesture())
            .onChanged { value in
                guard selected != nil else { return }
                twist = Twist(scale: Double(value.first?.magnification ?? 1), angle: value.second?.rotation.radians ?? 0)
            }
            .onEnded { value in
                defer { twist = nil }
                guard let id = selected, let piece = store.lid.first(where: { $0.id == id }) else { return }
                store.set(id, angle: piece.angle + (value.second?.rotation.radians ?? 0), scale: piece.scale * Double(value.first?.magnification ?? 1))
            }
    }

    /// A touch on a piece, where it was on the lid. 11-22: a postcard with its back up, touched on its postcode's
    /// row or on its lines (the right part under the stamp), is written on there, straight away; touched anywhere
    /// else it turns over, as any postcard does.
    private func tap(_ piece: PencilPiece, at point: CGPoint, u: Double, canvas: CGSize) {
        selected = piece.id
        menu = nil
        switch piece.kind {
        case .photo, .note:
            withAnimation(.easeOut(duration: 0.2)) { shown = piece.id }
            ConsoleSounds.shared.play(.select)
        case .postcard:
            if piece.back == true {
                // the point on the card itself: its middle at 0, 0, turned back as the card is turned, in a lid's points
                let at = live(piece, canvas: canvas), size = max(0.01, u * at.scale)
                let dx = Double(point.x) - at.x, dy = Double(point.y) - at.y
                let c = cos(at.angle), s = sin(at.angle)
                let onCard = CGPoint(x: (dx * c + dy * s) / size, y: (-dx * s + dy * c) / size)
                let part = PencilCard.part(at: onCard)
                if part == .postcode || part == .lines {
                    ConsoleSounds.shared.play(.select)
                    writing = .card(piece.id, part == .postcode ? .postcode : .words)
                    NSLog("[pencil] a postcard's back touched to be written on, on the lid")
                    return
                }
            }
            // turned over: squeezed to its edge, then back the other side up
            guard turning == nil else { return }
            withAnimation(.easeIn(duration: 0.11)) { turning = piece.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                store.flip(piece.id)
                withAnimation(.easeOut(duration: 0.14)) { turning = nil }
            }
            ConsoleSounds.shared.play(.cardFlip)
            ConsoleHaptics.shared.play(.smallButton, .press)
        case .thing, .tool, .shaving:
            if piece.thing == .musicBox { music.toggle() }
            if let play = piece.thing?.play {
                // (11-17) one of the old everyday things: it does what it does, and is heard
                let now = Date()
                played[piece.id] = now
                ConsoleSounds.shared.play(play.sound)
                DispatchQueue.main.asyncAfter(deadline: .now() + play.length + 0.05) { if played[piece.id] == now { played[piece.id] = nil } }
            } else {
                withAnimation(.spring(response: 0.16, dampingFraction: 0.45)) { hopping = piece.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { if hopping == piece.id { hopping = nil } }
                }
            }
            ConsoleHaptics.shared.play(.smallButton, .press)
        }
    }

    private func hold(_ piece: PencilPiece) {
        guard dragging == nil else { return }
        selected = piece.id
        withAnimation(.easeOut(duration: 0.15)) { menu = piece.id; shown = nil }
        ConsoleHaptics.shared.play(.faceButton, .press)
    }

    // MARK: The held thing's card

    private func menuCard(_ piece: PencilPiece, u: Double, canvas: CGSize) -> some View {
        let at = live(piece, canvas: canvas)
        let width = min(canvas.width * 0.56, 196 * u)
        let faceUp = piece.kind == .postcard && piece.back != true
        // (its own rows: a photo's, a note's, a postcard's back, one; a postcard's picture one, two once it is one's own)
        // (one's own picture on a postcard 画框 sent: its scenery can come back; a postcard made here has none)
        let ownFace = faceUp && piece.ownFront == true && !piece.isMadeCard
        let own: Int = piece.kind == .postcard ? (ownFace ? 2 : 1) : (piece.kind == .photo || piece.kind == .note ? 1 : 0)
        let height = Double(5 + own) * 40 * u + 12 * u
        let below = at.y + piece.art.size.height * u * at.scale * 0.42 + height / 2
        let y = below + height / 2 < canvas.height - 8 ? below : at.y - piece.art.size.height * u * at.scale * 0.42 - height / 2
        let x = min(max(at.x, width / 2 + 10 * u), canvas.width - width / 2 - 10 * u)
        return VStack(spacing: 0) {
            if piece.kind == .photo {
                menuRow(String(localized: "换一张"), symbol: "photo.on.rectangle.angled", u: u) {
                    withAnimation(.easeOut(duration: 0.15)) { menu = nil; shown = piece.id }
                }
            }
            if piece.kind == .note {
                menuRow(String(localized: "写字"), symbol: "pencil.line", u: u) { close(); write(piece) }
            }
            if piece.kind == .postcard {
                if faceUp {
                    menuRow(String(localized: "换照片"), symbol: "photo.on.rectangle.angled", u: u) {
                        withAnimation(.easeOut(duration: 0.15)) { menu = nil; shown = piece.id }
                    }
                    if ownFace {
                        menuRow(String(localized: "换回原来的风景"), symbol: "arrow.uturn.backward", u: u) { store.clearCardFront(piece.id); close() }
                    }
                } else {
                    menuRow(String(localized: "写字"), symbol: "pencil.line", u: u) {
                        close()
                        writing = .card(piece.id, nil)
                        NSLog("[pencil] a postcard's back written on, on the cover")
                    }
                }
            }
            menuRow(String(localized: "放回铅笔盒"), symbol: "tray.and.arrow.down", u: u) { store.takeOff(piece.id); close() }
            menuRow(String(localized: "摆正"), symbol: "arrow.counterclockwise", u: u) { store.set(piece.id, angle: 0, scale: piece.scale); close() }
            menuRow(String(localized: "大一点"), symbol: "plus.magnifyingglass", u: u) { store.set(piece.id, angle: piece.angle, scale: piece.scale * 1.15) }
            menuRow(String(localized: "小一点"), symbol: "minus.magnifyingglass", u: u) { store.set(piece.id, angle: piece.angle, scale: piece.scale / 1.15) }
            menuRow(String(localized: "取消"), symbol: "xmark", u: u) { close() }
        }
        .padding(.vertical, 6 * u)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 12 * u, style: .continuous).fill(Color(red: 0.97, green: 0.94, blue: 0.87)))
        .overlay(RoundedRectangle(cornerRadius: 12 * u, style: .continuous).strokeBorder(Color(red: 0.23, green: 0.17, blue: 0.14), lineWidth: max(1, 1.6 * u)))
        .shadow(color: .black.opacity(0.25), radius: 6 * u, x: 2 * u, y: 3 * u)
        .position(x: x, y: min(max(y, height / 2 + 8), canvas.height - height / 2 - 8))
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pencil-menu")
    }

    private func menuRow(_ title: String, symbol: String, u: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8 * u) {
                Image(systemName: symbol).font(.system(size: 13 * u, weight: .semibold)).frame(width: 20 * u).accessibilityHidden(true)
                Text(verbatim: title).font(.system(size: 14 * u, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12 * u)
            .frame(maxWidth: .infinity, minHeight: max(36, 40 * u))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.14))
    }

    private func close() { withAnimation(.easeOut(duration: 0.15)) { menu = nil } }

    // MARK: A photo or a note up close

    @ViewBuilder private func closeUp(_ piece: PencilPiece, u: Double, canvas: CGSize) -> some View {
        if piece.kind == .photo || piece.kind == .postcard {
            // (a postcard: its picture changed for one of one's own)
            PencilPhotoSwap(piece: piece, target: piece.kind == .postcard ? .cardFront : .photo) { withAnimation(.easeOut(duration: 0.15)) { shown = nil } }
                .frame(width: canvas.width, height: canvas.height)
                .accessibilityIdentifier("pencil-close-up")
        } else {
            noteCloseUp(piece, u: u, canvas: canvas)
        }
    }

    private func noteCloseUp(_ piece: PencilPiece, u: Double, canvas: CGSize) -> some View {
        let art = piece.art
        let k = min(canvas.width * 0.86 / art.size.width, canvas.height * 0.6 / art.size.height)
        return ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { shown = nil } }
            VStack(spacing: 14 * u) {
                ZStack {
                    PencilPieceView(piece: piece, u: 1, scale: k, layer: .shadow).offset(x: art.shadow.width * k, y: art.shadow.height * k)
                    PencilPieceView(piece: piece, u: 1, scale: k, layer: .face)
                }
                .rotationEffect(.radians(piece.angle * 0.3))
                .contentShape(Rectangle())
                // The note itself, touched again: written on (typed: the cover
                // takes no Apple Pencil; a finger still draws once the editor
                // is open). No button for it (11-16): the note is the button.
                .onTapGesture { write(piece) }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: piece.fullTitle))
                .accessibilityValue(Text(verbatim: noteWords(piece)))
                .accessibilityHint(Text("点一下，打字接着写"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("pencil-note-write")
                Text("再点一下便条，打字接着写")
                    .font(.system(size: 12.5 * u, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pencil-close-up")
    }
    private func write(_ piece: PencilPiece) {
        writing = .note(piece.id)
        withAnimation(.easeOut(duration: 0.15)) { shown = nil }
        NSLog("[pencil] a note written on, on the cover")
    }
}


/// 11-16: the box's styles and colours beside the lid, to change it there: a strip of small lids under each
/// style's name (the name stays up while its colours pass under it); the one worn a little larger than the rest,
/// a tick on it. A touch puts one on: the lid beside it changes at once, what is stuck on it stays where it is.
struct PencilLidLooks: View {
    var lookID: String
    var u: Double
    var choose: (PencilBoxLook) -> Void
    var done: () -> Void
    private static let ink = Color(red: 0.23, green: 0.17, blue: 0.14)
    private static let paper = Color(red: 0.97, green: 0.94, blue: 0.87)
    private static let dark = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        GeometryReader { proxy in
            let width = max(40, proxy.size.width - 14 * u)
            VStack(spacing: 6 * u) {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 8 * u, pinnedViews: [.sectionHeaders]) {
                            ForEach(PencilBoxStyle.allCases) { style in
                                Section {
                                    // (each known by its look's own id, so the strip can be brought to the one worn)
                                    ForEach(style.colours.map { PencilBoxLook(style: style, colour: $0) }, id: \.id) { look in
                                        thumb(look, width: width)
                                    }
                                } header: {
                                    Text(verbatim: style.title)
                                        .font(.system(size: 10.5 * u, weight: .bold, design: .rounded))
                                        .foregroundStyle(Self.paper)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4 * u)
                                        .background(Self.dark.opacity(0.94))
                                        .accessibilityAddTraits(.isHeader)
                                }
                            }
                        }
                        .padding(.vertical, 4 * u)
                    }
                    .onAppear { scroll.scrollTo(lookID, anchor: .center) }
                }
                Button(action: done) {
                    Label("选好了", systemImage: "checkmark")
                        .font(.system(size: 12 * u, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: max(40, 40 * u))
                        .background(Capsule().fill(Self.paper))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Self.ink)
                .accessibilityIdentifier("pencil-looks-done")
            }
            .padding(.horizontal, 5 * u)
            .padding(.vertical, 12 * u)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pencil-looks")
    }

    private func thumb(_ look: PencilBoxLook, width: Double) -> some View {
        let height = width * PencilArt.lid.height / PencilArt.lid.width
        let worn = look.id == lookID
        let corner = width * 59 / PencilArt.lid.width
        return Button { choose(look) } label: {
            Group {
                if let picture = PencilImages.preview("pencilbox-lid.jpg", look: look, height: 330) {
                    PencilImages.image(picture).resizable()
                } else {
                    Color(red: look.colour.red, green: look.colour.green, blue: look.colour.blue)
                }
            }
            .frame(width: width, height: height)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2 * u, bottomLeadingRadius: 2 * u, bottomTrailingRadius: corner, topTrailingRadius: corner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if worn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16 * u, weight: .bold))
                        .foregroundStyle(.white, Color(red: 0.17, green: 0.37, blue: 0.34))
                        .padding(5 * u)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(worn ? 1 : 0.88)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: worn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(look.style.title)：\(look.colour.name)"))
        .accessibilityAddTraits(worn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("pencil-look-\(look.id)")
    }
}

/// 11-22: the lid as the cover shows it, for 存为壁纸: the box's lid in its look and what is stuck on it, each at
/// its place, turn and size (no menu, no close-up, nothing lifted).
struct PencilLidPicture: View {
    var look: PencilBoxLook
    var canvas: CGSize
    var pieces: [PencilPiece]
    var body: some View {
        let u = canvas.width / PencilArt.lid.width
        ZStack(alignment: .topLeading) {
            PencilImages.image("pencilbox-lid.jpg", look: look).resizable()
                .frame(width: canvas.width, height: canvas.height)
            ForEach(pieces) { piece in
                let art = piece.art
                ZStack {
                    PencilPieceView(piece: piece, u: u, scale: piece.scale, layer: .shadow)
                        .rotationEffect(.radians(piece.angle))
                        .offset(x: art.shadow.width * u * piece.scale, y: art.shadow.height * u * piece.scale)
                    PencilPieceView(piece: piece, u: u, scale: piece.scale, layer: .face)
                        .rotationEffect(.radians(piece.angle))
                }
                .position(x: piece.x * canvas.width, y: piece.y * canvas.height)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}
