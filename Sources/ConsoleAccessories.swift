import SwiftUI

// The stylus and the earphones on the drawn console (round 23). The 3D
// console in the library has both as parts (ConsoleStage3D): the stylus
// comes out of its hole at the back when tapped, the earphones sit in the
// jack while headphones are connected. Here, on the console being played,
// the stylus shows where it presses the touch screen, and the earphone plug
// stands in the jack on the front edge. Shapes drawn here; FoldArc's own.

/// The stylus in the hand: while it is out of the console, a touch on the
/// lower screen shows the stylus's tip pressing there, the stylus slanting
/// away to the lower right as a right hand holds it, its shadow on the
/// glass. Only drawn: the touches reach the screen's content as before.
struct StylusTrace: ViewModifier {
    /// On-screen points per LCD design point (the stylus is drawn at the
    /// console's scale; the lower LCD is 400 design points wide).
    var scale: Double = 1
    @ObservedObject private var settings = ConsoleSettings.shared
    @GestureState private var touch: CGPoint?
    /// DEBUG `--foldarc-stylus-preview=<x>,<y>`: the stylus held at that
    /// point of the screen (0…1), for screenshots (a UI test cannot take one
    /// while it holds a touch down).
    private static func preview(in size: CGSize) -> CGPoint? {
        #if DEBUG
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--foldarc-stylus-preview=") }) else { return nil }
        let parts = argument.dropFirst("--foldarc-stylus-preview=".count).split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0] * size.width, y: parts[1] * size.height)
        #else
        return nil
        #endif
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touch) { value, state, _ in state = value.location },
                including: settings.stylusOut ? .all : .subviews)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    if settings.stylusOut, let point = touch ?? Self.preview(in: proxy.size) {
                        StylusGlyph(scale: scale, at: point)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.12), value: touch == nil)
    }
}

/// The stylus as seen from above, its tip at `at`.
struct StylusGlyph: View {
    var scale: Double
    var at: CGPoint
    /// How it slants from the tip (degrees, clockwise from pointing right).
    var angle = 38.0
    var body: some View {
        let length = 168 * scale, width = 7.5 * scale
        ZStack(alignment: .topLeading) {
            // The shadow on the glass: the stylus hovers over it, only the
            // tip touches, so the shadow starts at the tip and falls away.
            StylusBody(length: length, width: width, shadow: true)
                .frame(width: length, height: width)
                .rotationEffect(.degrees(angle - 4), anchor: .leading)
                .blur(radius: 2.5 * scale)
                .offset(x: 3 * scale, y: 7 * scale)
                .position(x: at.x + length / 2, y: at.y)
            StylusBody(length: length, width: width, shadow: false)
                .frame(width: length, height: width)
                .rotationEffect(.degrees(angle), anchor: .leading)
                .position(x: at.x + length / 2, y: at.y)
            // Where it presses: a small ring in the glass.
            Circle().strokeBorder(.white.opacity(0.55), lineWidth: max(0.8, 1.1 * scale))
                .frame(width: 11 * scale, height: 11 * scale)
                .position(at)
        }
    }
}

/// A slim telescoping stylus lying along x, its tip at the leading edge:
/// the dark tip, the bright metal shaft, a collar, the plastic grip and its
/// rounded end; shaded across its width so it reads round.
private struct StylusBody: View {
    var length: Double
    var width: Double
    var shadow: Bool
    var body: some View {
        let round = { (light: Double, dark: Double) -> LinearGradient in
            LinearGradient(stops: [.init(color: Color(white: light), location: 0), .init(color: Color(white: (light + dark) / 2 + 0.08), location: 0.35),
                                   .init(color: Color(white: dark), location: 1)], startPoint: .top, endPoint: .bottom)
        }
        ZStack(alignment: .leading) {
            if shadow {
                Capsule().fill(.black.opacity(0.38)).frame(width: length * 0.98, height: width)
            } else {
                // Grip.
                Capsule().fill(round(0.80, 0.30))
                    .frame(width: length * 0.56, height: width)
                    .offset(x: length * 0.44)
                // Shaft.
                Capsule().fill(round(0.97, 0.48))
                    .frame(width: length * 0.42, height: width * 0.66)
                    .offset(x: length * 0.05)
                // Collar between them.
                Capsule().fill(round(0.55, 0.15))
                    .frame(width: width * 0.62, height: width * 0.84)
                    .offset(x: length * 0.44 - width * 0.3)
                // Tip.
                StylusTipShape().fill(round(0.45, 0.10))
                    .frame(width: length * 0.075, height: width * 0.66)
            }
        }
        .frame(width: length, height: width, alignment: .leading)
    }
}

/// The tip: rounded at the point, widening to the shaft.
private struct StylusTipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.height * 0.28
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.midY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.midY + r), control: CGPoint(x: rect.minX - r * 0.4, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The earphones' plug in the jack on the console's front edge, seen from
/// above, its cable falling away: drawn while headphones are connected.
/// 160 × 150 points; the middle of its top edge is the jack.
struct EarphonePlugTop: View {
    var finish: ShellFinish
    @ObservedObject private var audio = SystemAudio.shared
    var body: some View {
        if audio.headphones {
            Canvas { context, size in
                let midX = size.width / 2
                // The metal ring at the jack's mouth.
                context.fill(Path(roundedRect: CGRect(x: midX - 6, y: 0, width: 12, height: 5), cornerRadius: 1.5),
                             with: .linearGradient(Gradient(colors: [Color(white: 0.92), Color(white: 0.55)]), startPoint: CGPoint(x: midX - 6, y: 0), endPoint: CGPoint(x: midX + 6, y: 0)))
                // The white housing, rounded at its end.
                let housing = Path(roundedRect: CGRect(x: midX - 9, y: 4, width: 18, height: 34), cornerRadius: 7)
                context.fill(housing, with: .linearGradient(Gradient(colors: [Color(white: 0.84), .white, Color(white: 0.80)]),
                                                            startPoint: CGPoint(x: midX - 9, y: 0), endPoint: CGPoint(x: midX + 9, y: 0)))
                context.stroke(housing, with: .color(.black.opacity(0.18)), lineWidth: 0.8)
                // The strain relief.
                let relief = Path(roundedRect: CGRect(x: midX - 4.5, y: 36, width: 9, height: 16), cornerRadius: 4)
                context.fill(relief, with: .linearGradient(Gradient(colors: [Color(white: 0.82), .white, Color(white: 0.78)]),
                                                          startPoint: CGPoint(x: midX - 4.5, y: 0), endPoint: CGPoint(x: midX + 4.5, y: 0)))
                // The cable, curving away to the lower left.
                var cable = Path()
                cable.move(to: CGPoint(x: midX, y: 50))
                cable.addCurve(to: CGPoint(x: midX - 70, y: size.height), control1: CGPoint(x: midX, y: 90), control2: CGPoint(x: midX - 60, y: size.height - 40))
                context.stroke(cable, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                context.stroke(cable, with: .color(Color(white: 0.97)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .frame(width: 160, height: 150)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
            .transition(.opacity)
            .accessibilityElement()
            .accessibilityLabel("耳机：插在耳机孔里")
        }
    }
}
