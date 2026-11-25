import SwiftUI
#if os(iOS)
import RealityKit
import CoreText
import UIKit
import Metal
#endif

// Round 27: the game card as a solid, the same one
// on the shelf, in the hand and in the console's slot, lit by the console's
// studio. Round 28: built
// after a real game card rather than a toy of one:
//
//  - a real card's proportions (35 × 33 × 3.8 mm: a little wider than it is
//    tall; round 27's was taller than wide);
//  - a shell of two halves with the parting line between them, its rims
//    softly rounded, a fine grip across the top, a small arrow;
//  - a shallow recess on the front with a paper sticker in it (its white
//    edge, a satin laminate over the print), printed like a product label:
//    a white brand band, the picture, the title, a small catalogue code;
//  - on the back a window of seventeen gold contacts on a dark board, each
//    between plastic dividers, and small moulded lettering;
//  - mid-grey moulded plastic, the marks the same plastic as the shell.
//
// Round 29: the
// light grey of real cards' plastic, satin rather than glossy; its rims
// rounded wider, so the studio's lights run along them in lines; the
// label's laminate a full gloss with a faint orange peel, so the lights in
// it waver as on a real sticker; the label's picture painted (light and
// shade, depth, glow), its title set like a logo, the small print along its
// foot. The studio itself (ConsoleStage) is now a dim room with bright soft
// boxes, which is what makes gloss read as gloss.
//
// Everything is FoldArc's own design, generated here; no picture, model or
// mark of anyone else's is used.

/// The card's layout in design units (round 28; the solid and the flat
/// face both follow it). x across the face (left to right as the label is
/// read), y up toward the grip, the middle of the card at the origin.
enum CardLayout {
    static let width = CardDimensions.width
    static let length = CardDimensions.length
    static let thickness = CardDimensions.thickness
    /// The top-left corner cut off (the key), the other corners' radius.
    static let cut: Double = 16
    static let cornerRadius: Double = 6.5
    /// The label's recess on the front and the paper label in it.
    static let wellSize = CGSize(width: 168, height: 138)
    static let labelSize = CGSize(width: 164, height: 134)
    static let labelCentreY: Double = -12
    static let labelCornerRadius: Double = 3.2
    /// The grip: fine ribs across the top of the face.
    static let ribCount = 28
    static let ribWidth: Double = 1.8
    static let ribPitch: Double = 4.4
    static let ribsCentreX: Double = -1
    static let ribsBottom: Double = 64
    static let ribsTop: Double = 77
    /// The arrow toward the contacts, top right on the front.
    static let arrow = [CGPoint(x: 72, y: 77), CGPoint(x: 82, y: 77), CGPoint(x: 77, y: 69)]
    /// The contacts' window on the back (in front-view x; the back mirrors it).
    static let window = CGRect(x: -76, y: -84, width: 152, height: 20)
    static let contactCount = 17
    static let contactPitch: Double = 8.7
    static let contactWidth: Double = 6.0

    /// The outline (y up), `d` inward all round: rounded corners, the
    /// top-left one cut off, its two corners eased a little.
    static func outline(inset d: Double = 0) -> Path {
        let w = width - 2 * d, l = length - 2 * d
        let c = cut - d * (2 - 2.0.squareRoot())
        let radius = max(0.4, cornerRadius - d), small = max(0.3, 1.6 - d * 0.5)
        let points: [(CGPoint, Double)] = [
            (CGPoint(x: -w / 2, y: l / 2 - c), small),
            (CGPoint(x: -w / 2 + c, y: l / 2), small),
            (CGPoint(x: w / 2, y: l / 2), radius),
            (CGPoint(x: w / 2, y: -l / 2), radius),
            (CGPoint(x: -w / 2, y: -l / 2), radius)]
        var p = Path()
        let last = points[points.count - 1].0, first = points[0].0
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in 0..<points.count {
            let corner = points[i].0, next = points[(i + 1) % points.count].0
            p.addArc(tangent1End: corner, tangent2End: next, radius: points[i].1)
        }
        p.closeSubpath()
        return p
    }
    /// The small catalogue code printed on the label (FA- and four hex
    /// digits of the title's FNV-1a hash: the same on every run).
    static func productCode(_ card: GameCardInfo) -> String {
        String(format: "FA-%04X", seed(card) & 0xFFFF)
    }
    static func seed(_ card: GameCardInfo) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in card.title.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return h
    }
}

/// The label of a card (round 28: printed like a real game card's label, a
/// paper sticker): a white band with the FOLDARC mark along the top, the
/// picture under it — the demo's own box art, an imported title's icon
/// spread into its colours with the icon itself printed sharp in a white
/// frame — the title and who made it bottom left, the grain of paper over it
/// all. Round 29: the picture painted rather than
/// flat (light and shade, depth, glow), the title set like a logo, and a
/// dark strip along the foot with the small print a real label carries (a
/// copyright line, the catalogue code). Frame it at CardLayout.labelSize (or
/// in proportion).
struct GameCardLabelArt: View {
    var card: GameCardInfo
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let band = (h * 0.15).rounded()
            let foot = max(1, (h * 0.075).rounded())
            let art = max(1, h - band - foot)
            VStack(spacing: 0) {
                LabelBand(height: band, cartridge: card.cartridge)
                    .frame(width: w, height: band)
                ZStack(alignment: .bottomLeading) {
                    LabelPicture(card: card)
                        .frame(width: w, height: art)
                    LabelTitle(card: card, width: w, height: art)
                }
                .frame(width: w, height: art)
                .clipped()
                LabelFoot(card: card, height: foot)
                    .frame(width: w, height: foot)
            }
            .overlay(PaperGrain(seed: CardLayout.seed(card)))
            // Ink on paper: nothing on it is quite black.
            .overlay(Color.white.opacity(0.03))
        }
        .accessibilityHidden(true)
    }
}

/// The label's band along the top: Zero's mark and name, the kind of thing
/// it is, a thin coloured rule under them.
private struct LabelBand: View {
    var height: CGFloat
    /// A 典藏卡带's card: the band in its metal's leaf, its rule in a darker one.
    var cartridge: Cartridge? = nil
    var body: some View {
        let tint = cartridge?.tint
        return ZStack(alignment: .bottom) {
            if let tint {
                LinearGradient(colors: [tint.bandTop, tint.bandLow], startPoint: .top, endPoint: .bottom)
            } else {
                Color(white: 0.965)
            }
            HStack(spacing: height * 0.18) {
                // Zero's mark (half of the icon's ring, 11-07), then the name.
                MenuArcMark(size: height * 0.62, color: Color(white: 0.17))
                Text("ZERO").font(.system(size: height * 0.42, weight: .black, design: .rounded)).tracking(height * 0.09)
                    .foregroundStyle(Color(white: 0.17))
                Spacer(minLength: height * 0.3)
                Text(verbatim: cartridge?.bandWord ?? "GAME CARD").font(.system(size: height * 0.25, weight: .heavy, design: .rounded)).tracking(height * 0.05)
                    .foregroundStyle(tint?.bandInk ?? Color(white: 0.42))
            }
            .padding(.horizontal, height * 0.42)
            .frame(maxHeight: .infinity)
            Rectangle().fill(tint?.rule ?? Color(red: 0.07, green: 0.50, blue: 0.48)).frame(height: max(0.5, height * 0.08))
        }
    }
}

/// The strip along the label's foot (round 29): the small print — whose
/// it is, the year, the catalogue code — light on dark, as real labels carry.
private struct LabelFoot: View {
    var card: GameCardInfo
    var height: CGFloat
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.075, blue: 0.085)
            HStack(spacing: height * 0.5) {
                Text(card.isCartridge ? "© 2026 ZERO · No. \(GoldReelPlan.stored().code)" : (card.isDemo ? "© 2026 ZERO · 原创演示" : "© \(card.subtitle.isEmpty ? "ZERO" : card.subtitle)"))
                    .lineLimit(1)
                Spacer(minLength: height * 0.4)
                Text(CardLayout.productCode(card))
            }
            .font(.system(size: height * 0.46, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(white: 0.78))
            .padding(.horizontal, height * 0.7)
        }
    }
}

/// The picture under the band.
private struct LabelPicture: View {
    var card: GameCardInfo
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            if let cartridge = card.cartridge {
                CartridgeLabelPicture(cartridge: cartridge)
            } else if card.isDemo {
                DemoLabelPicture()
            } else if let icon = card.icon {
                ZStack {
                    // The icon's colours spread across the whole picture.
                    Image(decorative: icon, scale: 1).resizable().interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: w * 1.3, height: h * 1.3)
                        .blur(radius: h * 0.12)
                        .saturation(1.35)
                        .frame(width: w, height: h)
                        .clipped()
                    // Round 29: lit like key art — a light behind the icon,
                    // a few rays from it, the corners falling off to dark.
                    RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)], center: UnitPoint(x: 0.74, y: 0.36), startRadius: 0, endRadius: h * 0.75)
                    LabelRays(centre: CGPoint(x: w * 0.74, y: h * 0.36))
                        .blendMode(.screen)
                    RadialGradient(colors: [.clear, .black.opacity(0.55)], center: UnitPoint(x: 0.6, y: 0.4), startRadius: h * 0.35, endRadius: h * 1.05)
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                    // The icon itself, printed sharp in a white frame, turned a little.
                    Image(decorative: icon, scale: 1).resizable().interpolation(.none)
                        .frame(width: h * 0.54, height: h * 0.54)
                        .clipShape(RoundedRectangle(cornerRadius: h * 0.05, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: h * 0.05, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)))
                        .padding(h * 0.024)
                        .background(RoundedRectangle(cornerRadius: h * 0.07, style: .continuous)
                            .fill(LinearGradient(colors: [Color(white: 1.0), Color(white: 0.88)], startPoint: .top, endPoint: .bottom)))
                        .shadow(color: .black.opacity(0.55), radius: h * 0.05, y: h * 0.025)
                        .rotationEffect(.degrees(-4))
                        .position(x: w * 0.74, y: h * 0.38)
                }
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.20, green: 0.27, blue: 0.40), Color(red: 0.09, green: 0.11, blue: 0.17)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.74, y: 0.36), startRadius: 0, endRadius: h * 0.7)
                    Image(systemName: "gamecontroller.fill").font(.system(size: h * 0.30)).foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: h * 0.03, y: h * 0.02)
                        .position(x: w * 0.74, y: h * 0.37)
                }
            }
        }
    }
}

/// A 典藏卡带's label: one of its films stopped (银 and 金: the way home at
/// sundown; 铜: a page of the flip book, the rope overhead), under a wash
/// of its metal.
private struct CartridgeLabelPicture: View {
    var cartridge: Cartridge
    var body: some View {
        let wash = cartridge.tint.wash
        return GeometryReader { proxy in
            ZStack {
                Color(red: 0.16, green: 0.10, blue: 0.20)
                Canvas { context, size in
                    if cartridge == .bronze {
                        FlipBookPainter(game: .jumpRope, random: ReelRandom(seed: 1988), t: 6.25).draw(context, size: size)
                    } else {
                        GoldScenePainter(scene: .wayHome, random: ReelRandom(seed: 1988), t: 6).draw(context, size: size)
                    }
                }
                .aspectRatio(CGFloat(ReelSheet.width / ReelSheet.height), contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                LinearGradient(colors: [wash.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
            }
        }
    }
}

/// Light rays from a point, fading out (key art's light behind its subject).
private struct LabelRays: View {
    var centre: CGPoint
    var body: some View {
        Canvas { context, size in
            let reach = max(size.width, size.height) * 1.3
            var rays = context
            rays.addFilter(.blur(radius: size.height * 0.02))
            for i in 0..<9 {
                let a = Double(i) / 9 * 2 * .pi + 0.21
                let spread = 0.07 + Double(i % 3) * 0.025
                var p = Path()
                p.move(to: centre)
                p.addLine(to: CGPoint(x: centre.x + reach * cos(a - spread), y: centre.y + reach * sin(a - spread)))
                p.addLine(to: CGPoint(x: centre.x + reach * cos(a + spread), y: centre.y + reach * sin(a + spread)))
                p.closeSubpath()
                rays.fill(p, with: .radialGradient(Gradient(colors: [.white.opacity(0.20), .white.opacity(0)]), center: centre, startRadius: 0, endRadius: reach * 0.55))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Who made it and the title, bottom left, set like a game's logo (round
/// 29: a light gradient in the letters, a hard dark edge and a soft
/// shadow under them, rather than plain white type).
private struct LabelTitle: View {
    var card: GameCardInfo
    var width: CGFloat
    var height: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: height * 0.012) {
            Text(card.isDemo ? String(localized: "原创演示") : card.subtitle)
                .font(.system(size: height * 0.064, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
            if card.isDemo {
                VStack(alignment: .leading, spacing: -height * 0.035) {
                    Text("ORBIT").foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                    Text("GARDEN").foregroundStyle(LinearGradient(colors: [Color(red: 0.80, green: 1.0, blue: 0.88), Color(red: 0.36, green: 0.80, blue: 0.62)], startPoint: .top, endPoint: .bottom))
                }
                .font(.system(size: height * 0.175, weight: .black, design: .rounded))
            } else {
                Text(card.title)
                    .font(.system(size: height * (card.isCartridge ? 0.17 : 0.13), weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: card.cartridge.map { [$0.tint.titleTop, $0.tint.titleLow] } ?? [.white, Color(white: 0.84)],
                                                    startPoint: .top, endPoint: .bottom))
                    .lineLimit(2).minimumScaleFactor(0.55)
            }
        }
        .frame(maxWidth: width * (card.isDemo || card.isCartridge ? 0.9 : 0.6), alignment: .leading)
        // A hard dark edge under the letters, then a soft shadow.
        .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: height * 0.008)
        .shadow(color: .black.opacity(0.55), radius: height * 0.025, y: height * 0.012)
        .padding(.leading, width * 0.055).padding(.bottom, height * 0.06)
        .frame(width: width, height: height, alignment: .bottomLeading)
    }
}

/// The grain of the paper: faint light and dark specks, the same for a
/// card every time it is printed.
private struct PaperGrain: View {
    var seed: UInt32
    var body: some View {
        Canvas { context, size in
            var state = seed | 1
            func next() -> CGFloat {
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                return CGFloat(state % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 14)
            for i in 0..<count {
                let x = next() * size.width, y = next() * size.height
                let r = 0.35 + next() * 0.45
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(i % 2 == 0 ? .white.opacity(0.07) : .black.opacity(0.06)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The demo's box art (round 27; round 29 painted): deep space with clouds
/// of colour and a field of stars, a ringed planet lit from the upper left
/// (its bands, the night side, the rim of its air, the ring passing behind
/// and in front of it), the star the ship flies to with its glare, the ship
/// with its engine lit and a glowing trail; the title goes over it.
private struct DemoLabelPicture: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let bounds = CGRect(origin: .zero, size: size)
            var seed: UInt32 = 0x0B17_2026
            func random() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                return CGFloat(seed % 100_000) / 100_000
            }
            context.fill(Path(bounds), with: .linearGradient(Gradient(stops: [
                .init(color: Color(red: 0.06, green: 0.22, blue: 0.27), location: 0),
                .init(color: Color(red: 0.035, green: 0.08, blue: 0.14), location: 0.55),
                .init(color: Color(red: 0.015, green: 0.02, blue: 0.05), location: 1)]),
                startPoint: CGPoint(x: w * 0.85, y: 0), endPoint: CGPoint(x: w * 0.15, y: h)))
            // Clouds of colour, blurred.
            var clouds = context
            clouds.addFilter(.blur(radius: w * 0.07))
            let nebulae: [(CGFloat, CGFloat, CGFloat, Color)] = [
                (0.16, 0.66, 0.30, Color(red: 0.42, green: 0.20, blue: 0.60).opacity(0.50)),
                (0.50, 0.86, 0.26, Color(red: 0.10, green: 0.42, blue: 0.55).opacity(0.40)),
                (0.95, 0.10, 0.26, Color(red: 0.18, green: 0.58, blue: 0.52).opacity(0.40)),
                (0.30, 0.18, 0.16, Color(red: 0.95, green: 0.48, blue: 0.26).opacity(0.22))]
            for (cx, cy, r, color) in nebulae {
                clouds.fill(Path(ellipseIn: CGRect(x: w * cx - w * r, y: h * cy - w * r * 0.7, width: 2 * w * r, height: 1.4 * w * r)), with: .color(color))
            }
            // Stars: faint dust, brighter ones, a few with a cross of glare.
            for _ in 0..<170 {
                let x = random() * w, y = random() * h
                let b = random()
                let r = (0.25 + b * b * 1.1) * w / 160
                context.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(.white.opacity(0.18 + 0.7 * b * b)))
            }
            for (sx, sy, len) in [(0.08, 0.12, 0.05), (0.58, 0.07, 0.035), (0.90, 0.55, 0.04), (0.40, 0.62, 0.03)] as [(CGFloat, CGFloat, CGFloat)] {
                let c = CGPoint(x: w * sx, y: h * sy), l = w * len
                for (dx, dy) in [(1.0, 0.0), (0.0, 1.0)] as [(CGFloat, CGFloat)] {
                    var spike = Path()
                    spike.move(to: CGPoint(x: c.x - dx * l, y: c.y - dy * l)); spike.addLine(to: CGPoint(x: c.x + dx * l, y: c.y + dy * l))
                    context.stroke(spike, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.8), .white.opacity(0)]),
                                                                startPoint: CGPoint(x: c.x - dx * l, y: c.y - dy * l), endPoint: CGPoint(x: c.x + dx * l, y: c.y + dy * l)),
                                   lineWidth: w * 0.0035)
                }
                context.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.004, y: c.y - w * 0.004, width: w * 0.008, height: w * 0.008)), with: .color(.white))
            }
            // The planet.
            let centre = CGPoint(x: w * 0.75, y: h * 0.30), radius = h * 0.215
            let tilt = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: -0.32).translatedBy(x: -centre.x, y: -centre.y)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - radius * 2.4, y: centre.y - radius * 2.4, width: radius * 4.8, height: radius * 4.8)),
                         with: .radialGradient(Gradient(colors: [Palette.mint.opacity(0.26), Palette.mint.opacity(0)]), center: centre, startRadius: radius * 0.7, endRadius: radius * 2.4))
            func ring(_ k: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: centre.x - radius * 1.8 * k, y: centre.y - radius * 0.44 * k, width: radius * 3.6 * k, height: radius * 0.88 * k)).applying(tilt)
            }
            func rings(into ctx: GraphicsContext, alpha: Double) {
                ctx.stroke(ring(1.0), with: .color(Color(red: 0.98, green: 0.66, blue: 0.40).opacity(0.85 * alpha)), lineWidth: radius * 0.16)
                ctx.stroke(ring(1.0), with: .color(Color(red: 0.25, green: 0.12, blue: 0.08).opacity(0.55 * alpha)), lineWidth: radius * 0.018)
                ctx.stroke(ring(1.13), with: .color(Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.7 * alpha)), lineWidth: radius * 0.05)
                ctx.stroke(ring(0.89), with: .color(Color(red: 0.86, green: 0.52, blue: 0.32).opacity(0.6 * alpha)), lineWidth: radius * 0.04)
            }
            var back = context
            back.clip(to: Path(CGRect(x: -w, y: -h, width: 3 * w, height: h + centre.y)).applying(tilt))
            rings(into: back, alpha: 0.7)
            let planet = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(planet, with: .radialGradient(Gradient(colors: [Color(red: 0.88, green: 1.0, blue: 0.93), Color(red: 0.50, green: 0.88, blue: 0.74), Color(red: 0.14, green: 0.40, blue: 0.40)]),
                                                       center: CGPoint(x: centre.x - radius * 0.38, y: centre.y - radius * 0.42), startRadius: 0, endRadius: radius * 2.0))
            var surface = context
            surface.clip(to: planet)
            // Bands across it, along the ring's tilt.
            for i in 0..<7 {
                let y = centre.y - radius + CGFloat(i) * radius * 0.31 + radius * 0.12
                let band = Path(CGRect(x: centre.x - radius * 1.2, y: y, width: radius * 2.4, height: radius * (i % 2 == 0 ? 0.10 : 0.06))).applying(tilt)
                surface.fill(band, with: .color(i % 2 == 0 ? Color(red: 0.20, green: 0.50, blue: 0.45).opacity(0.28) : Color.white.opacity(0.14)))
            }
            // The night side.
            surface.fill(planet, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.42), .init(color: .black.opacity(0.62), location: 1)]),
                                                       startPoint: CGPoint(x: centre.x - radius * 0.7, y: centre.y - radius * 0.7), endPoint: CGPoint(x: centre.x + radius * 0.9, y: centre.y + radius * 0.9)))
            // The ring's shadow on it, just below where the ring crosses.
            surface.stroke(ring(1.0).applying(CGAffineTransform(translationX: 0, y: radius * 0.16)), with: .color(.black.opacity(0.32)), lineWidth: radius * 0.12)
            // The rim of its air and a soft highlight.
            var air = context
            air.addFilter(.blur(radius: radius * 0.05))
            air.stroke(planet, with: .color(Color(red: 0.72, green: 1.0, blue: 0.90).opacity(0.55)), lineWidth: radius * 0.05)
            air.fill(Path(ellipseIn: CGRect(x: centre.x - radius * 0.62, y: centre.y - radius * 0.66, width: radius * 0.5, height: radius * 0.34)), with: .color(.white.opacity(0.35)))
            var front = context
            front.clip(to: Path(CGRect(x: -w, y: centre.y, width: 3 * w, height: 2 * h)).applying(tilt))
            rings(into: front, alpha: 1)
            // The star the ship flies to: its glow, four points, the glare.
            let star = CGPoint(x: w * 0.22, y: h * 0.30), arm = w * 0.075
            context.fill(Path(ellipseIn: CGRect(x: star.x - arm * 2, y: star.y - arm * 2, width: arm * 4, height: arm * 4)),
                         with: .radialGradient(Gradient(colors: [Palette.orange.opacity(0.55), Palette.orange.opacity(0)]), center: star, startRadius: 0, endRadius: arm * 2))
            for (dx, dy, l) in [(1.0, 0.0, 2.6), (0.0, 1.0, 2.0), (0.7, 0.7, 1.1), (0.7, -0.7, 1.1)] as [(CGFloat, CGFloat, CGFloat)] {
                var glare = Path()
                glare.move(to: CGPoint(x: star.x - dx * arm * l, y: star.y - dy * arm * l)); glare.addLine(to: CGPoint(x: star.x + dx * arm * l, y: star.y + dy * arm * l))
                context.stroke(glare, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0), Color(red: 1, green: 0.92, blue: 0.75).opacity(0.85), Color(red: 1, green: 0.85, blue: 0.6).opacity(0)]),
                                                            startPoint: CGPoint(x: star.x - dx * arm * l, y: star.y - dy * arm * l), endPoint: CGPoint(x: star.x + dx * arm * l, y: star.y + dy * arm * l)),
                               lineWidth: w * 0.004)
            }
            var spark = Path()
            spark.move(to: CGPoint(x: star.x, y: star.y - arm))
            spark.addQuadCurve(to: CGPoint(x: star.x + arm, y: star.y), control: CGPoint(x: star.x + arm * 0.16, y: star.y - arm * 0.16))
            spark.addQuadCurve(to: CGPoint(x: star.x, y: star.y + arm), control: CGPoint(x: star.x + arm * 0.16, y: star.y + arm * 0.16))
            spark.addQuadCurve(to: CGPoint(x: star.x - arm, y: star.y), control: CGPoint(x: star.x - arm * 0.16, y: star.y + arm * 0.16))
            spark.addQuadCurve(to: CGPoint(x: star.x, y: star.y - arm), control: CGPoint(x: star.x - arm * 0.16, y: star.y - arm * 0.16))
            context.fill(spark, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.88), Palette.orange]), center: star, startRadius: 0, endRadius: arm))
            // The ship, climbing toward it from the right, its trail glowing.
            let ship = CGPoint(x: w * 0.45, y: h * 0.45)
            var trail = Path()
            trail.move(to: CGPoint(x: w * 0.88, y: h * 0.62))
            trail.addQuadCurve(to: CGPoint(x: ship.x + w * 0.045, y: ship.y + h * 0.03), control: CGPoint(x: w * 0.66, y: h * 0.62))
            var glow = context
            glow.addFilter(.blur(radius: w * 0.012))
            glow.stroke(trail, with: .linearGradient(Gradient(colors: [Palette.mint.opacity(0), Palette.mint.opacity(0.75)]), startPoint: CGPoint(x: w * 0.88, y: h * 0.62), endPoint: ship),
                        style: StrokeStyle(lineWidth: w * 0.02, lineCap: .round))
            context.stroke(trail, with: .linearGradient(Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.9)]), startPoint: CGPoint(x: w * 0.88, y: h * 0.62), endPoint: ship),
                           style: StrokeStyle(lineWidth: w * 0.0045, lineCap: .round))
            let heading = CGAffineTransform(translationX: ship.x, y: ship.y).rotated(by: -1.08)
            let sz = w * 0.05
            var flame = Path()
            flame.move(to: CGPoint(x: -sz * 0.5, y: sz * 0.85)); flame.addLine(to: CGPoint(x: 0, y: sz * 2.0)); flame.addLine(to: CGPoint(x: sz * 0.5, y: sz * 0.85)); flame.closeSubpath()
            var engine = context
            engine.addFilter(.blur(radius: w * 0.006))
            engine.fill(flame.applying(heading), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.8), Palette.orange.opacity(0)]),
                                                                        startPoint: CGPoint(x: 0, y: sz * 0.85).applying(heading), endPoint: CGPoint(x: 0, y: sz * 2.0).applying(heading)))
            var hull = Path()
            hull.move(to: CGPoint(x: 0, y: -sz * 1.3)); hull.addLine(to: CGPoint(x: -sz, y: sz * 0.9))
            hull.addQuadCurve(to: CGPoint(x: sz, y: sz * 0.9), control: CGPoint(x: 0, y: sz * 0.3)); hull.closeSubpath()
            let hullPath = hull.applying(heading)
            context.fill(hullPath, with: .linearGradient(Gradient(colors: [Color(red: 0.90, green: 1.0, blue: 0.95), Palette.mint, Color(red: 0.20, green: 0.48, blue: 0.42)]),
                                                         startPoint: CGPoint(x: -sz, y: -sz).applying(heading), endPoint: CGPoint(x: sz, y: sz).applying(heading)))
            context.stroke(hullPath, with: .color(Color(red: 0.05, green: 0.16, blue: 0.16).opacity(0.7)), lineWidth: w * 0.002)
            context.fill(Path(ellipseIn: CGRect(x: -sz * 0.18, y: -sz * 0.45, width: sz * 0.36, height: sz * 0.36)).applying(heading), with: .color(Color(red: 0.08, green: 0.20, blue: 0.26)))
        }
        .accessibilityHidden(true)
    }
}

/// Labels printed once per card (round 27; round 26's CardFacePrints).
@MainActor enum CardArtPrints {
    private static var labels: [String: CGImage] = [:]
    private static var order: [String] = []
    static func key(_ card: GameCardInfo) -> String {
        "\(card.title)|\(card.subtitle)|\(card.isDemo ? 1 : 0)|\(card.icon == nil ? 0 : 1)|\(card.cartridge?.rawValue ?? "-")"
    }
    /// The label at 3 pixels per design point (492 × 402).
    static func label(_ card: GameCardInfo) -> CGImage? {
        let key = Self.key(card)
        if let image = labels[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return image
        }
        let renderer = ImageRenderer(content: GameCardLabelArt(card: card).frame(width: CardLayout.labelSize.width, height: CardLayout.labelSize.height))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { return nil }
        labels[key] = image
        order.append(key)
        if order.count > 40 { labels.removeValue(forKey: order.removeFirst()) }
        return image
    }

    // 11-07 (删除): the card's whole face, flat, and its colours in blocks,
    // for the card coming apart into pixels (PixelCardView).
    private static var faces: [String: CGImage] = [:]
    private static var faceOrder: [String] = []
    /// The card's face at 3 pixels per design point (561 × 528).
    static func face(_ card: GameCardInfo) -> CGImage? {
        let key = Self.key(card)
        if let image = faces[key] { return image }
        let renderer = ImageRenderer(content: GameCardFace(card: card, s: 1).frame(width: CardLayout.width, height: CardLayout.length))
        renderer.scale = 3
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        faces[key] = image
        faceOrder.append(key)
        if faceOrder.count > 12 { faces.removeValue(forKey: faceOrder.removeFirst()) }
        return image
    }
    struct BlockGrid {
        struct Sample {
            var column: Int
            var row: Int
            var color: Color
            /// Each block's own way of slipping and flying (fixed per block).
            var vx: Double
            var vy: Double
            var delay: Double
        }
        var columns: Int
        var rows: Int
        var samples: [Sample]
    }
    private static var grids: [String: BlockGrid] = [:]
    /// The face averaged into `across` blocks along its width (as many down
    /// its length as fit square), each with its colour; empty blocks (the
    /// shell's cut corner) left out.
    static func blocks(_ card: GameCardInfo, across: Int) -> BlockGrid? {
        let key = Self.key(card) + "|\(across)"
        if let grid = grids[key] { return grid }
        guard let face = face(card) else { return nil }
        let columns = across
        let rows = max(1, Int((Double(face.height) / Double(face.width) * Double(columns)).rounded()))
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(face, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        var samples: [BlockGrid.Sample] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for row in 0..<rows {
            for column in 0..<columns {
                // The bitmap's rows run bottom-up (CG's origin): row 0 of the
                // grid is the top of the face.
                let i = ((rows - 1 - row) * columns + column) * 4
                let a = Double(bytes[i + 3]) / 255
                let vx = next() * 2 - 1, vy = 0.35 + next() * 0.9, delay = next() * 0.25
                guard a > 0.35 else { continue }
                let color = Color(red: Double(bytes[i]) / 255 / a, green: Double(bytes[i + 1]) / 255 / a, blue: Double(bytes[i + 2]) / 255 / a)
                samples.append(.init(column: column, row: row, color: color, vx: vx, vy: vy, delay: delay))
            }
        }
        let grid = BlockGrid(columns: columns, rows: rows, samples: samples)
        grids[key] = grid
        if grids.count > 12 { grids.removeValue(forKey: grids.keys.first!) }
        return grid
    }
}

#if os(iOS)
/// The card as a solid (round 27; round 28 after a real card). Model space:
/// x across the label (left to right as it is read), y up toward the grip,
/// z out of the label; the middle of the card at the origin; one design unit
/// is ConsoleModel.u, the card CardLayout's 187 × 176 × 21 units, as the
/// console's slot takes it.
@MainActor enum CardModel3D {
    /// The front and back edges: how deep (the label's recess and the
    /// contacts' window go through them) and how round their outer rims.
    static let edge: Double = 2.4
    static let edgeRound: Double = 2.1
    /// The parting line between the shell's two halves, a little toward the back.
    static let seamZ: Double = -0.5
    static let seamHeight: Double = 0.7
    static let seamInset: Double = 0.45
    /// The paper label's thickness; the board and the contacts in the window.
    static let sticker: Double = 0.45
    static let boardDepth: Double = 0.15
    static let contactDepth: Double = 0.22

    /// A card ready to be placed: its root carries the name (the console's
    /// part names), its children the shell, the label, the moulded marks.
    static func make(_ card: GameCardInfo, name: String) -> ModelEntity {
        let root = ModelEntity()
        root.name = name
        let u = ConsoleModel.u
        let parts = meshes()
        func add(_ mesh: MeshResource?, _ material: RealityKit.Material, z: Float, flip: Bool = false) {
            guard let mesh else { return }
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.name = name
            // Extruded meshes run from their near end (min z) to their far
            // end; each part is placed by its near end, at `z` (turned over
            // to face the back, about the upright: its far end then lies
            // toward -z).
            let b = mesh.bounds
            if flip {
                e.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                e.position = [0, 0, z + b.min.z]
            } else {
                e.position = [0, 0, z - b.min.z]
            }
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(e)
        }
        // A 典藏卡带's card is the same moulding in its metal.
        let plastic: RealityKit.Material = card.cartridge.map { Self.metalShell($0) } ?? Self.plastic
        let t = Float(CardLayout.thickness) * u
        // The cores' outer faces (the label's recess and the window floors).
        let face = t / 2 - Float(edge) * u
        let seamLow = Float(seamZ - seamHeight / 2) * u, seamHigh = Float(seamZ + seamHeight / 2) * u
        // Back to front: the back edge, the back half, the parting line, the
        // front half, the front edge.
        add(parts.backEdge, plastic, z: -face, flip: true)
        add(parts.coreBack, plastic, z: -face)
        add(parts.seam, seam, z: seamLow)
        add(parts.coreFront, plastic, z: seamHigh)
        add(parts.frontEdge, plastic, z: face)
        // Moulded on: the grip, the arrows, the lettering on the back.
        add(parts.ribs, plastic, z: t / 2)
        add(parts.ribsBack, plastic, z: -t / 2, flip: true)
        add(parts.arrowFront, plastic, z: t / 2)
        add(parts.arrowBack, plastic, z: -t / 2, flip: true)
        add(parts.markBack, plastic, z: -t / 2, flip: true)
        add(parts.lineBack, plastic, z: -t / 2, flip: true)
        // The window on the back: the board, the contacts on it, the
        // dividers between them up to the back face.
        add(parts.board, board, z: -face, flip: true)
        add(parts.contacts, gold, z: -face - Float(boardDepth) * u, flip: true)
        add(parts.dividers, plastic, z: -face, flip: true)
        // The label: a paper sticker in the recess, the print on top of it.
        add(parts.sticker, paper, z: face)
        let labelEntity = ModelEntity(mesh: labelPlane(), materials: [labelMaterial(card)])
        labelEntity.name = name
        labelEntity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        labelEntity.position = [0, Float(CardLayout.labelCentreY) * u, face + Float(sticker + 0.03) * u]
        labelEntity.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(labelEntity)
        return root
    }

    /// Prints a card's label ahead of time (while the library is idle).
    static func prepare(_ card: GameCardInfo) {
        _ = meshes()
        _ = labelMaterial(card)
        _ = reflectionMaterial(card)
    }

    // MARK: Materials

    /// Moulded plastic (round 29): the light grey of real cards, a satin
    /// finish — the studio's lights broad and soft in it, sharper along the
    /// rounded rims.
    static let plastic: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.74, green: 0.745, blue: 0.75, alpha: 1))
        m.roughness = 0.46
        m.metallic = 0.0
        m.clearcoat = 0.12
        m.clearcoatRoughness = 0.32
        // The mould's fine texture (b2): the extruded parts' texture
        // coordinates run 0…1 across the card (logged by b1), so the grain is
        // laid 26 times across it, a little under 1.5 mm a tile.
        if let grain = mouldGrain {
            m.normal = .init(texture: .init(grain))
            m.textureCoordinateTransform = .init(scale: [26, 26])
        }
        return m
    }()
    /// A 典藏卡带's shell: the same moulding, its metal all through.
    static func metalShell(_ cartridge: Cartridge) -> PhysicallyBasedMaterial {
        if let made = metalShells[cartridge] { return made }
        let tint = cartridge.tint
        var m = plastic
        m.baseColor = .init(tint: UIColor(red: CGFloat(tint.metal.0), green: CGFloat(tint.metal.1), blue: CGFloat(tint.metal.2), alpha: 1))
        // Gold and silver polished, bronze a little duller.
        switch cartridge {
        case .gold: m.roughness = 0.30
        case .silver: m.roughness = 0.26
        case .bronze: m.roughness = 0.38
        }
        m.metallic = 0.85
        m.clearcoat = 0.35
        m.clearcoatRoughness = 0.20
        metalShells[cartridge] = m
        return m
    }
    private static var metalShells: [Cartridge: PhysicallyBasedMaterial] = [:]
    /// The parting line: the shadowed gap between the halves.
    static let seam: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.30, green: 0.305, blue: 0.31, alpha: 1))
        m.roughness = 0.8
        m.metallic = 0.0
        return m
    }()
    static let gold: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.98, green: 0.79, blue: 0.42, alpha: 1))
        m.metallic = 1.0
        m.roughness = 0.22
        return m
    }()
    /// The board the contacts are on.
    static let board: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.07, green: 0.10, blue: 0.08, alpha: 1))
        m.roughness = 0.45
        m.metallic = 0.0
        return m
    }()
    /// The label's paper, seen at its cut edge.
    static let paper: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1))
        m.roughness = 0.85
        m.metallic = 0.0
        return m
    }()
    private static var labelMaterials: [String: RealityKit.Material] = [:]
    private static var labelOrder: [String] = []
    /// The print under a laminate: the studio's lights slide over it as the
    /// card turns (round 29: a full gloss with a faint orange peel, the
    /// print itself satin under it).
    static func labelMaterial(_ card: GameCardInfo) -> RealityKit.Material {
        let key = CardArtPrints.key(card)
        if let m = labelMaterials[key] { return m }
        var m = PhysicallyBasedMaterial()
        if let image = CardArtPrints.label(card), let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) {
            m.baseColor = .init(tint: .white, texture: clamped(texture))
        } else {
            m.baseColor = .init(tint: UIColor(red: 0.20, green: 0.24, blue: 0.32, alpha: 1))
        }
        m.roughness = 0.38
        m.metallic = 0.0
        m.clearcoat = 1.0
        m.clearcoatRoughness = 0.07
        if let peel = peelNormals { m.clearcoatNormal = .init(texture: .init(peel)) }
        labelMaterials[key] = m
        labelOrder.append(key)
        if labelOrder.count > 32 { labelMaterials.removeValue(forKey: labelOrder.removeFirst()) }
        return m
    }
    private static var reflectionMaterials: [String: RealityKit.Material] = [:]
    private static var reflectionOrder: [String] = []
    /// The card's front upside down, fading away from the floor: its
    /// reflection in the shelf's floor (round 28: fainter and softer).
    static func reflectionMaterial(_ card: GameCardInfo) -> RealityKit.Material {
        let key = CardArtPrints.key(card)
        if let m = reflectionMaterials[key] { return m }
        var m = UnlitMaterial(applyPostProcessToneMap: true)
        let renderer = ImageRenderer(content: GameCardFace(card: card, s: 1).frame(width: CardLayout.width, height: CardLayout.length)
            .scaleEffect(x: 1, y: -1).blur(radius: 2.2))
        renderer.scale = 1
        renderer.isOpaque = false
        if let image = renderer.cgImage, let texture = try? TextureResource(image: image, withName: nil, options: .init(semantic: .color)) {
            m.color = .init(tint: UIColor(white: 0.9, alpha: 1), texture: clamped(texture))
        } else {
            m.color = .init(tint: UIColor(white: 0.6, alpha: 1))
        }
        if let ramp = reflectionRamp {
            m.blending = .transparent(opacity: .init(scale: 1, texture: clamped(ramp)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.08))
        }
        m.writesDepth = false
        reflectionMaterials[key] = m
        reflectionOrder.append(key)
        if reflectionOrder.count > 32 { reflectionMaterials.removeValue(forKey: reflectionOrder.removeFirst()) }
        return m
    }
    /// Textures sampled up to their edges and no further. The default
    /// sampler repeats them: the reflection's far edge, where it has faded
    /// to nothing, then took in the near edge's opacity and showed as a thin
    /// light line under every card (seen slanting under the turned ones,
    /// round 27's first build).
    static let clampSampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        return MaterialParameters.Texture.Sampler(d)
    }()
    static func clamped(_ resource: TextureResource) -> MaterialParameters.Texture {
        MaterialParameters.Texture(resource, sampler: clampSampler)
    }
    /// Down the reflection: strongest at the floor, gone a third of the way
    /// down (the same value in every channel, whichever the opacity reads).
    private static let reflectionRamp: TextureResource? = {
        let w = 4, h = 64
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let t = Float(y) / Float(h - 1)
            let a = 0.16 * pow(max(0, 1 - t / 0.34), 1.8)
            let v = UInt8(max(0, min(255, (a * 255).rounded())))
            for x in 0..<w {
                let k = (y * w + x) * 4
                pixels[k] = v; pixels[k + 1] = v; pixels[k + 2] = v; pixels[k + 3] = v
            }
        }
        return rawTexture(pixels, width: w, height: h)
    }()
    /// A soft round spot (the shadows under a card).
    static let spotTexture: TextureResource? = {
        let w = 64
        var pixels = [UInt8](repeating: 0, count: w * w * 4)
        for y in 0..<w {
            for x in 0..<w {
                let dx = (Float(x) + 0.5) / Float(w) * 2 - 1, dy = (Float(y) + 0.5) / Float(w) * 2 - 1
                let r = min(1, (dx * dx + dy * dy).squareRoot())
                let a = r >= 1 ? 0 : pow(1 - r * r, 2.0)
                let v = UInt8(max(0, min(255, (a * 255).rounded())))
                let k = (y * w + x) * 4
                pixels[k] = v; pixels[k + 1] = v; pixels[k + 2] = v; pixels[k + 3] = v
            }
        }
        return rawTexture(pixels, width: w, height: w)
    }()
    static func rawTexture(_ pixels: [UInt8], width: Int, height: Int, semantic: TextureResource.Semantic = .raw) -> TextureResource? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return try? TextureResource(image: image, withName: nil, options: .init(semantic: semantic))
    }
    /// The mould's fine grain (round 29): the texture moulded plastic has,
    /// as a normal map — light caught by it is broken up a little rather than
    /// lying on the card like on glass. Smoothed noise on a wrapping grid.
    static let mouldGrain: TextureResource? = {
        let n = 128
        var state: UInt32 = 0x6EA1_0029
        var noise = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            noise[i] = Float(state % 10_000) / 10_000
        }
        // Two passes of a small blur (wrapping), for grains a few texels wide.
        for _ in 0..<2 {
            var next = noise
            for y in 0..<n {
                for x in 0..<n {
                    var sum: Float = 0
                    for dy in -1...1 { for dx in -1...1 { sum += noise[((y + dy + n) % n) * n + (x + dx + n) % n] } }
                    next[y * n + x] = sum / 9
                }
            }
            noise = next
        }
        var steepest: Float = 0
        var slopes = [SIMD2<Float>](repeating: .zero, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let dx = noise[y * n + (x + 1) % n] - noise[y * n + (x + n - 1) % n]
                let dy = noise[((y + 1) % n) * n + x] - noise[((y + n - 1) % n) * n + x]
                slopes[y * n + x] = [dx, dy]
                steepest = max(steepest, simd_length(SIMD2<Float>(dx, dy)))
            }
        }
        let k = steepest > 0 ? 0.16 / steepest : 0
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let normal = simd_normalize(SIMD3<Float>(-slopes[i].x * k, -slopes[i].y * k, 1))
            pixels[i * 4] = UInt8(max(0, min(255, ((normal.x * 0.5 + 0.5) * 255).rounded())))
            pixels[i * 4 + 1] = UInt8(max(0, min(255, ((normal.y * 0.5 + 0.5) * 255).rounded())))
            pixels[i * 4 + 2] = UInt8(max(0, min(255, ((normal.z * 0.5 + 0.5) * 255).rounded())))
        }
        return rawTexture(pixels, width: n, height: n, semantic: .normal)
    }()
    /// The laminate's orange peel (round 29): a gentle unevenness, as a
    /// normal map for the label's clear coat, so that the studio's lights in
    /// its gloss waver a little as on a real sticker instead of sliding as on
    /// glass. Sums of waves with whole periods across the picture (no seam).
    static let peelNormals: TextureResource? = {
        let n = 128
        var state: UInt32 = 0x5EED_0029
        func random() -> Float {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Float(state % 10_000) / 10_000
        }
        var waves: [(fx: Float, fy: Float, phase: Float, amplitude: Float)] = []
        while waves.count < 28 {
            let fx = Float(Int(random() * 19) - 9), fy = Float(Int(random() * 19) - 9)
            let f = (fx * fx + fy * fy).squareRoot()
            guard f >= 2 else { continue }
            waves.append((fx, fy, random() * 2 * .pi, 1 / f))
        }
        var heights = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let s = Float(x) / Float(n), t = Float(y) / Float(n)
                var h: Float = 0
                for w in waves { h += w.amplitude * sin(2 * .pi * (w.fx * s + w.fy * t) + w.phase) }
                heights[y * n + x] = h
            }
        }
        // Slopes from neighbours (wrapping round), scaled to a gentle tilt at most.
        var slopes = [SIMD2<Float>](repeating: .zero, count: n * n)
        var steepest: Float = 0
        for y in 0..<n {
            for x in 0..<n {
                let dx = heights[y * n + (x + 1) % n] - heights[y * n + (x + n - 1) % n]
                let dy = heights[((y + 1) % n) * n + x] - heights[((y + n - 1) % n) * n + x]
                slopes[y * n + x] = [dx, dy]
                steepest = max(steepest, simd_length(SIMD2<Float>(dx, dy)))
            }
        }
        let k = steepest > 0 ? 0.07 / steepest : 0
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let normal = simd_normalize(SIMD3<Float>(-slopes[i].x * k, -slopes[i].y * k, 1))
            pixels[i * 4] = UInt8(max(0, min(255, ((normal.x * 0.5 + 0.5) * 255).rounded())))
            pixels[i * 4 + 1] = UInt8(max(0, min(255, ((normal.y * 0.5 + 0.5) * 255).rounded())))
            pixels[i * 4 + 2] = UInt8(max(0, min(255, ((normal.z * 0.5 + 0.5) * 255).rounded())))
        }
        return rawTexture(pixels, width: n, height: n, semantic: .normal)
    }()

    // MARK: Meshes (made once)

    struct Parts {
        var coreBack: MeshResource?
        var seam: MeshResource?
        var coreFront: MeshResource?
        var frontEdge: MeshResource?
        var backEdge: MeshResource?
        var ribs: MeshResource?
        var ribsBack: MeshResource?
        var arrowFront: MeshResource?
        var arrowBack: MeshResource?
        var markBack: MeshResource?
        var lineBack: MeshResource?
        var board: MeshResource?
        var contacts: MeshResource?
        var dividers: MeshResource?
        var sticker: MeshResource?
    }
    private static var made: Parts?
    static func meshes() -> Parts {
        if let made { return made }
        let started = Date()
        let face = CardLayout.thickness / 2 - edge
        let outline = CardLayout.outline()
        // Parts for the back are drawn as seen from the front and mirrored
        // before they are extruded: turned over, they lie the right way round.
        let mirror = CGAffineTransform(scaleX: -1, y: 1)
        let label = CardLayout.labelSize, wellSize = CardLayout.wellSize
        let well = Path(roundedRect: CGRect(x: -wellSize.width / 2, y: CardLayout.labelCentreY - wellSize.height / 2, width: wellSize.width, height: wellSize.height),
                        cornerRadius: CardLayout.labelCornerRadius + 1.2, style: .continuous)
        let window = Path(roundedRect: CardLayout.window, cornerRadius: 1.2, style: .continuous)
        var parts = Parts()
        // The shell: two halves and the parting line between them; the
        // edges, rounded outward, with the label's recess and the
        // contacts' window through them.
        parts.coreBack = extrude(outline, depth: (seamZ - seamHeight / 2) + face, chamfer: 0, rounded: nil)
        parts.seam = extrude(CardLayout.outline(inset: seamInset), depth: seamHeight, chamfer: 0, rounded: nil)
        parts.coreFront = extrude(outline, depth: face - (seamZ + seamHeight / 2), chamfer: 0, rounded: nil)
        parts.frontEdge = extrude(outline.subtracting(well), depth: edge, chamfer: edgeRound, rounded: .far)
        parts.backEdge = extrude(outline.applying(mirror).subtracting(window.applying(mirror)), depth: edge, chamfer: edgeRound, rounded: .far)
        // The grip: fine ribs across the top, front and back.
        var ribs = Path()
        let span = Double(CardLayout.ribCount - 1) * CardLayout.ribPitch + CardLayout.ribWidth
        for i in 0..<CardLayout.ribCount {
            let x = CardLayout.ribsCentreX - span / 2 + Double(i) * CardLayout.ribPitch
            ribs.addPath(Path(roundedRect: CGRect(x: x, y: CardLayout.ribsBottom, width: CardLayout.ribWidth, height: CardLayout.ribsTop - CardLayout.ribsBottom),
                              cornerRadius: 0.8, style: .continuous))
        }
        parts.ribs = extrude(ribs, depth: 0.7, chamfer: 0.3, rounded: .far)
        parts.ribsBack = extrude(ribs.applying(mirror), depth: 0.6, chamfer: 0.25, rounded: .far)
        // The arrows toward the contacts.
        var arrow = Path()
        arrow.addLines(CardLayout.arrow)
        arrow.closeSubpath()
        parts.arrowFront = extrude(arrow, depth: 0.5, chamfer: 0.2, rounded: .far)
        var back = Path()
        back.addLines([CGPoint(x: -6, y: -6), CGPoint(x: 6, y: -6), CGPoint(x: 0, y: -16)])
        back.closeSubpath()
        parts.arrowBack = extrude(back.applying(mirror), depth: 0.45, chamfer: 0.18, rounded: .far)
        // Small lettering moulded on the back.
        if let mark = textPath("ZERO", size: 9.5, tracking: 1.9, weight: .heavy) {
            parts.markBack = extrude(mark.applying(CGAffineTransform(translationX: 0, y: 24)).applying(mirror), depth: 0.4, chamfer: 0.15, rounded: .far)
        }
        if let line = textPath("GAME CARD", size: 4.8, tracking: 1.2, weight: .bold) {
            parts.lineBack = extrude(line.applying(CGAffineTransform(translationX: 0, y: 12)).applying(mirror), depth: 0.3, chamfer: 0.1, rounded: .far)
        }
        // The window: a dark board, seventeen contacts, plastic between them.
        let w = CardLayout.window
        parts.board = extrude(Path(roundedRect: w.insetBy(dx: 0.8, dy: 0.8), cornerRadius: 0.8, style: .continuous).applying(mirror),
                              depth: boardDepth, chamfer: 0, rounded: nil)
        var pads = Path(), dividers = Path()
        let padSpan = Double(CardLayout.contactCount - 1) * CardLayout.contactPitch + CardLayout.contactWidth
        for i in 0..<CardLayout.contactCount {
            let x = -padSpan / 2 + Double(i) * CardLayout.contactPitch
            pads.addPath(Path(roundedRect: CGRect(x: x, y: w.minY + 2, width: CardLayout.contactWidth, height: w.height - 5), cornerRadius: 0.7, style: .continuous))
            if i < CardLayout.contactCount - 1 {
                dividers.addRect(CGRect(x: x + CardLayout.contactWidth + 0.25, y: w.minY, width: CardLayout.contactPitch - CardLayout.contactWidth - 0.5, height: w.height))
            }
        }
        parts.contacts = extrude(pads.applying(mirror), depth: contactDepth, chamfer: 0, rounded: nil)
        parts.dividers = extrude(dividers.applying(mirror), depth: edge, chamfer: 0.25, rounded: .far)
        // The label's paper, in the recess (its print is a plane on top).
        let stickerPath = Path(roundedRect: CGRect(x: -label.width / 2, y: CardLayout.labelCentreY - label.height / 2, width: label.width, height: label.height),
                               cornerRadius: CardLayout.labelCornerRadius, style: .continuous)
        parts.sticker = extrude(stickerPath, depth: sticker, chamfer: 0, rounded: nil)
        made = parts
        NSLog("[card] model made in %.0f ms (front rounds the %@ end)", Date().timeIntervalSince(started) * 1000, frontRoundsFarEnd == false ? "near" : "far")
        #if DEBUG
        // Round 29: what texture coordinates an extruded part carries (for
        // a moulded texture on the plastic, if they run across it).
        for (what, mesh) in [("front edge", parts.frontEdge), ("front core", parts.coreFront)] {
            guard let mesh else { continue }
            var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude), high = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
            var count = 0
            for model in mesh.contents.models {
                for part in model.parts {
                    guard let uvs = part.textureCoordinates?.elements else { continue }
                    for uv in uvs { low = pointwiseMin(low, uv); high = pointwiseMax(high, uv) }
                    count += uvs.count
                }
            }
            NSLog("[card] %@: %d texture coordinates, u %.4f…%.4f, v %.4f…%.4f", what, count, count > 0 ? low.x : 0, count > 0 ? high.x : 0, count > 0 ? low.y : 0, count > 0 ? high.y : 0)
        }
        #endif
        return parts
    }

    /// A word's outline in design units (y up), centred on the origin.
    private static func textPath(_ string: String, size: CGFloat, tracking: CGFloat, weight: UIFont.Weight) -> Path? {
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: size) }
        let ctFont = font as CTFont
        let characters = Array(string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, characters.count) else { return nil }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        _ = CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)
        let path = CGMutablePath()
        var x: CGFloat = 0
        for (i, glyph) in glyphs.enumerated() {
            if let outline = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                path.addPath(outline, transform: CGAffineTransform(translationX: x, y: 0))
            }
            x += advances[i].width + (i < glyphs.count - 1 ? tracking : 0)
        }
        let box = path.boundingBoxOfPath
        guard box.width > 0 else { return nil }
        return Path(path).applying(CGAffineTransform(translationX: -box.midX, y: -box.midY))
    }

    enum RoundedEnd { case far, near }
    /// Which end of an extrusion `.front` rounds, read from the first mesh
    /// made that way (the console found the far one, round 24).
    private static var frontRoundsFarEnd: Bool?
    /// The path (design units, y up) extruded along z by `depth` units in
    /// all, its far end (max z) or near end rounded by `chamfer`, or
    /// neither (nil).
    private static func extrude(_ path: Path, depth: Double, chamfer: Double, rounded: RoundedEnd?) -> MeshResource? {
        let u = ConsoleModel.u
        let scaled = path.applying(CGAffineTransform(scaleX: CGFloat(u), y: CGFloat(u)))
        func make(_ mode: MeshResource.ShapeExtrusionOptions.ChamferMode?, ends: Double) -> MeshResource? {
            var options = MeshResource.ShapeExtrusionOptions()
            // The chamfers add their radius to the depth: ask for the rest.
            options.extrusionMethod = .linear(depth: max(0.00005, Float(depth - ends * chamfer) * u))
            if let mode, chamfer > 0 {
                options.chamferRadius = Float(chamfer) * u
                options.chamferMode = mode
                options.chamferResolution = .uniformSegmentsPerSpan(segmentCount: 4)
            } else {
                options.chamferRadius = 0
            }
            options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 8)
            return try? MeshResource(extruding: scaled, extrusionOptions: options)
        }
        guard let rounded, chamfer > 0 else { return make(nil, ends: 0) }
        if frontRoundsFarEnd == nil, let probe = make(.front, ends: 1) { frontRoundsFarEnd = roundedEndIsFar(probe) }
        let farWanted = rounded == .far
        return make((frontRoundsFarEnd ?? true) == farWanted ? .front : .back, ends: 1)
    }
    /// The rounded end of a one-sided extrusion is the one whose outline is
    /// the smaller (the rounding draws it in).
    private static func roundedEndIsFar(_ mesh: MeshResource) -> Bool {
        var points: [SIMD3<Float>] = []
        for model in mesh.contents.models { for part in model.parts { points.append(contentsOf: part.positions.elements) } }
        guard let first = points.first else { return true }
        var near = first.z, far = first.z
        for p in points { near = min(near, p.z); far = max(far, p.z) }
        let slack = max(1e-7, (far - near) * 0.002)
        func width(at z: Float) -> Float {
            var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
            for p in points where abs(p.z - z) <= slack { low = min(low, p.x); high = max(high, p.x) }
            return high - low
        }
        return width(at: far) < width(at: near)
    }
    /// The label's print: a plane (lying in XZ, turned up to face +z by its entity).
    private static var labelMesh: MeshResource?
    private static func labelPlane() -> MeshResource {
        if let labelMesh { return labelMesh }
        let u = ConsoleModel.u
        let mesh = MeshResource.generatePlane(width: Float(CardLayout.labelSize.width) * u, depth: Float(CardLayout.labelSize.height) * u,
                                              cornerRadius: Float(CardLayout.labelCornerRadius) * u)
        labelMesh = mesh
        return mesh
    }
}
#endif
