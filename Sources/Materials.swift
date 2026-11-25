import SwiftUI

// Procedural "materials" for the vector-drawn casing. Everything here is
// gradients and strokes on SwiftUI shapes: no photographs, no bitmaps, so
// it scales to any display and keeps the project free of third-party art.

/// A soft diagonal reflection band, the kind glossy plastic shows under a
/// ceiling light. `angle` tilts the band; `width` is the fraction of the
/// diagonal it covers; `strength` is the peak white opacity.
struct GlossSweep: View {
    var strength = 0.14
    var center = 0.30
    var width = 0.28
    var angle = -32.0
    var body: some View {
        GeometryReader { proxy in
            let d = hypot(proxy.size.width, proxy.size.height)
            Rectangle()
                .fill(LinearGradient(stops: [
                    .init(color: .clear, location: max(0, center - width)),
                    .init(color: .white.opacity(strength * 0.55), location: max(0, center - width * 0.35)),
                    .init(color: .white.opacity(strength), location: center),
                    .init(color: .white.opacity(strength * 0.25), location: min(1, center + width * 0.3)),
                    .init(color: .clear, location: min(1, center + width))
                ], startPoint: .leading, endPoint: .trailing))
                .frame(width: d * 1.6, height: d * 1.6)
                .rotationEffect(.degrees(angle))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

/// Darkens edges and corners the way a slightly curved panel falls away from
/// the light. Cheap: one radial gradient.
struct Vignette: View {
    var strength = 0.28
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            RadialGradient(stops: [
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(strength * 0.35), location: 0.85),
                .init(color: .black.opacity(strength), location: 1)
            ], center: .center, startRadius: 0, endRadius: hypot(w, h) * 0.58)
        }
        .allowsHitTesting(false)
    }
}

/// Fine plastic grain: deterministic speckle, two sizes.
struct Grain: View {
    var opacity = 0.07
    var count = 1600
    var body: some View {
        Canvas { context, size in
            for i in 0..<count {
                let x = Double((i * 431 + 17) % 2003) / 2003 * size.width
                let y = Double((i * 787 + 53) % 2011) / 2011 * size.height
                let r = i % 7 == 0 ? 0.9 : 0.6
                let bright = i % 3 == 0
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                             with: .color(bright ? .white.opacity(opacity) : .black.opacity(opacity * 0.8)))
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Inner shadow + rim light: the view reads as pressed into the casing.
    func recessed<S: InsettableShape>(_ shape: S, depth: Double = 2, light: Double = 0.18, dark: Double = 0.7) -> some View {
        self
            .overlay {
                shape.stroke(.black.opacity(dark), lineWidth: depth * 1.5)
                    .blur(radius: depth * 0.9)
                    .offset(y: depth * 0.6)
                    .mask(shape)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.black.opacity(dark * 0.5), .white.opacity(light)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
    /// Raised rim: light on top, dark underneath, plus a contact shadow.
    func raised<S: InsettableShape>(_ shape: S, light: Double = 0.28, dark: Double = 0.55, lift: Double = 2) -> some View {
        self
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(light), .clear, .black.opacity(dark)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: lift, x: 0, y: lift)
    }
}

/// A domed key cap: radial highlight top-left, darker rim, sits in a well.
struct DomeCap: View {
    var color: Color
    var pressed = false
    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.78))
            Circle().fill(color).padding(1.5)
            Circle().fill(RadialGradient(stops: [
                .init(color: .white.opacity(pressed ? 0.10 : 0.34), location: 0),
                .init(color: .white.opacity(0.06), location: 0.45),
                .init(color: .black.opacity(0.22), location: 1)
            ], center: UnitPoint(x: 0.36, y: 0.30), startRadius: 0, endRadius: 30)).padding(1.5)
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.38), .clear, .black.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).padding(1.5)
        }
    }
}

/// Concave dish for the Circle Pad base and similar wells.
struct Dish: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.04), Color(white: 0.10), Color(white: 0.05)], center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0, endRadius: 60))
            Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1).padding(2)
        }
    }
}
