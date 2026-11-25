import SwiftUI

// Explicitly use the property-wrapper type, keeping CLI builds independent of SDK macro plug-ins.
typealias ViewState<Value> = SwiftUI.State<Value>

struct PrototypeScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        #if RENDER_PREVIEW
        // ImageRenderer cannot snapshot AppKit-backed scrolling containers.
        content()
        #else
        ScrollView { content() }
        #endif
    }
}

enum Palette {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.10)
    static let panel = Color(red: 0.105, green: 0.12, blue: 0.17)
    static let mint = Color(red: 0.65, green: 0.94, blue: 0.77)
    static let muted = Color(red: 0.59, green: 0.64, blue: 0.73)
    static let orange = Color(red: 1, green: 0.66, blue: 0.41)
}

struct Pill: View {
    let text: String
    var color = Palette.mint
    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }
}

struct ActionStyle: ButtonStyle {
    var primary = false
    /// Ends something (closing the running software).
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(primary ? Palette.background : (destructive ? Palette.orange : Color.white))
            .background(primary ? Palette.mint : (destructive ? Palette.orange.opacity(0.14) : Color.white.opacity(0.07)),
                        in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// What the demo's screens draw (round 22): its state without the clock,
/// which moves every frame. The screens are drawn again only when this
/// changes; with the whole state, the clock made both of them redraw 60 times
/// a second with nothing moving.
struct DemoScene: Equatable {
    var player: Point
    var target: Point
    var beacon: Point
    var collected: Int
    init(_ state: DemoState) {
        player = state.player; target = state.target; beacon = state.beacon; collected = state.collected
    }
}

struct StarField: View {
    let state: DemoState
    var squareCorners = false
    /// The 3D slider, 0…1 (round 16). Above 0 the scene is drawn twice, the
    /// left eye in red and the right eye in cyan, each layer shifted by its
    /// depth: far stars barely, the ship most. Red/cyan glasses show the depth.
    var depth = 0.0
    var body: some View {
        StarFieldPicture(scene: DemoScene(state), squareCorners: squareCorners, depth: depth)
        #if DEBUG
            // Round 29 (the UI tests):
            // where the ship and the beacon are, in percent of the screen,
            // and the stars caught, so a test can see A, the D-pad, the
            // Circle Pad and the C Stick do what they should. DEBUG only;
            // nothing on the screen.
            .overlay(alignment: .topTrailing) {
                Color.clear.frame(width: 2, height: 2)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel("demo-positions")
                    .accessibilityValue(Self.positions(state))
                    .accessibilityIdentifier("demo-positions")
            }
        #endif
    }
    #if DEBUG
    /// "ship x,y beacon x,y stars n", positions in percent (0…100).
    static func positions(_ state: DemoState) -> String {
        func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
        return "ship \(percent(state.player.x)),\(percent(state.player.y)) beacon \(percent(state.beacon.x)),\(percent(state.beacon.y)) stars \(state.collected)"
    }
    #endif
}

/// The upper screen's picture, from the scene alone (see DemoScene).
private struct StarFieldPicture: View {
    let scene: DemoScene
    var squareCorners: Bool
    var depth: Double
    var body: some View {
        Canvas { context, size in
            if depth > 0 {
                // Additive red + cyan of the same picture is the picture again,
                // so anything at zero depth looks as in 2D.
                context.drawLayer { left in
                    left.addFilter(.colorMultiply(Color(red: 1, green: 0, blue: 0)))
                    draw(in: &left, size: size, eye: -1)
                }
                context.blendMode = .plusLighter
                context.drawLayer { right in
                    right.addFilter(.colorMultiply(Color(red: 0, green: 1, blue: 1)))
                    draw(in: &right, size: size, eye: 1)
                }
            } else {
                draw(in: &context, size: size, eye: 0)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("✦  \(String(format: "%02d", scene.collected))").font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.orange).padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: squareCorners ? 1 : 14))
        .accessibilityLabel("演示主屏，已收集 \(scene.collected) 颗星星")
    }

    /// One eye's picture. `eye` is -1 (left), 1 (right) or 0 (2D); `z` of each
    /// layer 0 (screen plane) … 1 (nearest), shifted by up to 2.2 % of the width.
    private func draw(in context: inout GraphicsContext, size: CGSize, eye: Double) {
        func shift(_ z: Double) -> Double { eye * depth * z * size.width * 0.022 }
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(Path(bounds), with: .linearGradient(Gradient(colors: [Color(red: 0.09, green: 0.20, blue: 0.22), Palette.background]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        for i in 0..<44 {
            let near = i % 5 == 0
            let x = Double((i * 71 + 19) % 400) / 400 * size.width - shift(near ? 0.25 : 0.1)
            let y = Double((i * 43 + 13) % 240) / 240 * size.height
            let r = near ? 2.0 : 1.0
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.30)))
        }
        let planet = CGRect(x: size.width * 0.67 - shift(0.35), y: size.height * 0.11, width: size.height * 0.4, height: size.height * 0.4)
        context.fill(Path(ellipseIn: planet), with: .color(Palette.mint.opacity(0.08)))
        context.stroke(Path(ellipseIn: planet.insetBy(dx: -10, dy: -10)), with: .color(Palette.mint.opacity(0.13)), lineWidth: 1)
        let tx = scene.target.x * size.width - shift(0.6), ty = scene.target.y * size.height
        context.draw(Text("✦").font(.system(size: 30)).foregroundColor(Palette.orange), at: CGPoint(x: tx, y: ty))
        let bx = scene.beacon.x * size.width - shift(0.75), by = scene.beacon.y * size.height
        context.stroke(Path(ellipseIn: CGRect(x: bx - 12, y: by - 12, width: 24, height: 24)), with: .color(Palette.mint.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        let px = scene.player.x * (size.width - 28) + 14 - shift(1), py = scene.player.y * (size.height - 28) + 14
        var ship = Path()
        ship.move(to: CGPoint(x: px, y: py - 13)); ship.addLine(to: CGPoint(x: px - 10, y: py + 9))
        ship.addQuadCurve(to: CGPoint(x: px + 10, y: py + 9), control: CGPoint(x: px, y: py + 3)); ship.closeSubpath()
        context.fill(ship, with: .color(Palette.mint))
        context.draw(Text("ORBIT GARDEN").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(Palette.mint.opacity(0.6)), at: CGPoint(x: 18, y: size.height - 18), anchor: .leading)
    }
}

struct TouchMap: View {
    let state: DemoState
    var touch: ((Point) -> Void)?
    var squareCorners = false
    var showCoordinates = false
    var body: some View {
        GeometryReader { geometry in
            TouchMapPicture(scene: DemoScene(state))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                touch?(Point(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height))
            })
        }
        .overlay(alignment: .bottom) {
            Text(showCoordinates ? String(format: "X %03d   Y %03d", Int(state.beacon.x * 319), Int(state.beacon.y * 239)) : String(localized: "TOUCH · 设置信标")).font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.muted).padding(8).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: squareCorners ? 1 : 10))
        .accessibilityLabel("触摸副屏，点击设置信标后按 A 传送")
    }
}

/// The touch screen's picture, from the scene alone (see DemoScene).
private struct TouchMapPicture: View {
    let scene: DemoScene
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.10, green: 0.16, blue: 0.20)))
            for i in 1..<8 {
                var path = Path()
                let x = Double(i) / 8 * size.width, y = Double(i) / 8 * size.height
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Palette.mint.opacity(0.09)), lineWidth: 1)
            }
            let b = CGPoint(x: scene.beacon.x * size.width, y: scene.beacon.y * size.height)
            context.stroke(Path(ellipseIn: CGRect(x: b.x - 9, y: b.y - 9, width: 18, height: 18)), with: .color(Palette.mint), lineWidth: 1.5)
            context.draw(Text("✦").foregroundColor(Palette.orange), at: CGPoint(x: scene.target.x * size.width, y: scene.target.y * size.height))
            context.fill(Path(ellipseIn: CGRect(x: scene.player.x * size.width - 3, y: scene.player.y * size.height - 3, width: 6, height: 6)), with: .color(.white))
        }
    }
}
