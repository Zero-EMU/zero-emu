import SwiftUI
#if os(iOS)
import AVKit
import AVFoundation
import UIKit
#endif

// 相机控制: the
// iPhone's Camera Control, and the other capture keys (the volume keys,
// the Action button set to the camera), in FoldArc's camera.
//
// Two system paths, both verified in the SDK (q/885, q/887):
// - The press: AVKit's AVCaptureEventInteraction (iOS 17.2). A primary
//   event (Camera Control, volume down, the Action button) or a secondary
//   one (volume up) ends → a picture, as L, R and A take one. The system
//   sends these only to an app capturing in the foreground; adopting the
//   interaction overrides the keys' default behaviour, so it is enabled
//   only while FoldArc's camera is open and live.
// - The light press: the session's controls (AVFoundation, iOS 18) — the
//   small menu the Camera Control slides out over the picture. FoldArc puts
//   its seven lenses there (an index picker) and the system's zoom slider;
//   the delegate the session requires is below.
//
// Neither exists on the Simulator (no key, no camera): a device is the only
// test (not run yet).

#if os(iOS)
/// A view that hears the capture keys for the camera program: a tiny UIView
/// carrying the interaction, laid into the camera's screens.
struct CaptureKeyCatcher: UIViewRepresentable {
    /// Off when the camera is not live (the keys fall back to the system).
    var enabled: Bool
    /// The key let go: a picture.
    var pressed: @MainActor () -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        // CameraTry.bare: neither the keys nor the direction map.
        if CameraTry.bare { NSLog("[camera] capture keys and direction map left out (bare)"); return view }
        let coordinator = context.coordinator
        let interaction = AVCaptureEventInteraction(primary: { event in coordinator.handle(event, secondary: false) },
                                                    secondary: { event in coordinator.handle(event, secondary: true) })
        interaction.isEnabled = enabled
        view.addInteraction(interaction)
        coordinator.interaction = interaction
        NSLog("[camera] capture keys: interaction added (enabled %d)", enabled ? 1 : 0)
        // Which cameras face the person looking at this view's
        // display, and which face away (iPhone Duo, iOS 27.1).
        #if FOLDARC_DUO_SDK
        if #available(iOS 27.1, *) { coordinator.directions = CameraDirectionWatch.make(on: view) }
        #endif
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.pressed = pressed
        if let interaction = context.coordinator.interaction, interaction.isEnabled != enabled {
            interaction.isEnabled = enabled
            NSLog("[camera] capture keys: %@", enabled ? "enabled" : "disabled")
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(pressed: pressed) }
    final class Coordinator: NSObject {
        var interaction: AVCaptureEventInteraction?
        /// The direction coordinator (iOS 27.1), kept for as long as the view.
        var directions: AnyObject?
        var pressed: @MainActor () -> Void
        init(pressed: @escaping @MainActor () -> Void) { self.pressed = pressed }
        func handle(_ event: AVCaptureEvent, secondary: Bool) {
            switch event.phase {
            case .began:
                NSLog("[camera] capture key down (%@)", secondary ? "secondary" : "primary")
            case .ended:
                NSLog("[camera] capture key up (%@): picture", secondary ? "secondary" : "primary")
                let pressed = self.pressed
                Task { @MainActor in pressed() }
            case .cancelled:
                NSLog("[camera] capture key cancelled")
            @unknown default:
                break
            }
        }
    }
}

#if FOLDARC_DUO_SDK
/// AVKit's AVCaptureDeviceDirectionCoordinator (iOS 27.1, in the
/// SDK's AVKit/AVCaptureDeviceDirectionCoordinator.h, q/943): for a view, the
/// cameras that face forward (the scene in front of its display) and
/// backward. Its handler runs on the main queue; what it says goes to
/// CameraDirections (no AVFoundation calls here).
@available(iOS 27.1, *)
enum CameraDirectionWatch {
    static let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera,
                                                      .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera,
                                                      .builtInDualWideCamera]
    /// Forward: the front camera that follows the display first (no swap
    /// needed when the console opens or shuts), then the display's own.
    /// Backward: the dual camera first (its ultra wide gives 0.5×).
    static func rank(_ type: AVCaptureDevice.DeviceType, forward: Bool) -> Int {
        let order: [AVCaptureDevice.DeviceType] = forward
            ? [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera]
            : [.builtInDualWideCamera, .builtInWideAngleCamera, .builtInUltraWideCamera]
        return order.firstIndex(of: type) ?? order.count
    }
    static func make(on view: UIView) -> AnyObject {
        AVCaptureDeviceDirectionCoordinator(view: view, deviceTypes: types) { map in
            let forward = map.forwardFacingDeviceDescriptors.sorted { rank($0.deviceType, forward: true) < rank($1.deviceType, forward: true) }
            let backward = map.backwardFacingDeviceDescriptors.sorted { rank($0.deviceType, forward: false) < rank($1.deviceType, forward: false) }
            NSLog("[camera] directions: forward %@; backward %@",
                  forward.map(\.deviceType.rawValue).joined(separator: ","), backward.map(\.deviceType.rawValue).joined(separator: ","))
            CameraDirections.shared.update(forward: forward.map(\.uniqueID), backward: backward.map(\.uniqueID))
        }
    }
}
#endif

/// The delegate the session's controls need to become active (the Camera
/// Control's light press). What it hears is logged; when the system's
/// overlay goes full screen the camera's own banner is kept quiet.
final class CaptureControlsWatcher: NSObject, AVCaptureSessionControlsDelegate {
    var onChange: (@Sendable (_ active: Bool, _ fullscreen: Bool) -> Void)?
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        NSLog("[camera] controls active")
        onChange?(true, false)
    }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        NSLog("[camera] controls full screen")
        onChange?(true, true)
    }
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        NSLog("[camera] controls leave full screen")
        onChange?(true, false)
    }
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        NSLog("[camera] controls inactive")
        onChange?(false, false)
    }
}
#else
/// The Mac preview: no capture keys.
struct CaptureKeyCatcher: View {
    var enabled: Bool
    var pressed: () -> Void
    var body: some View { Color.clear.frame(width: 1, height: 1) }
}
#endif

// MARK: - Duo Preview

/// The console open, the rear dual camera
/// taking someone — the cover, on the same side as that camera, shows them
/// the picture and the count. iOS 27.1's camera capture accessory (SwiftUI
/// `CameraCaptureAccessory` and `sceneAccessory`, in the 27.1 SDK's SwiftUI
/// interface, q/943); the system shows it only while FoldArc is capturing,
/// full screen on the inner display, so it is asked for only with 外侧 on
/// the console's screens. Nothing of it exists on the Simulator (no camera
/// runs there): a device is the only test.
struct CameraSubjectAccessory: ViewModifier {
    @ObservedObject var model: CameraAppModel
    @State private var enabled = false
    private var wanted: Bool {
        !CameraTry.plain && model.side == .outer && model.deck == .screens && (model.phase == .live || model.phase == .starting)
    }
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS) && FOLDARC_DUO_SDK
        if #available(iOS 27.1, *) {
            content
                .sceneAccessory {
                    CameraCaptureAccessory(isEnabled: $enabled) {
                        CameraSubjectPreview(model: model)
                    }
                    .onAvailabilityChange { available in
                        NSLog("[camera] the cover's picture for the people taken: %@", available ? "available" : "not available")
                    }
                }
                .onChange(of: wanted, initial: true) { _, value in
                    enabled = value
                    NSLog("[camera] the cover's picture for the people taken: %@", value ? String(localized: "asked for (外侧)") : "not asked for")
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// What the cover shows the people the rear camera is taking: the picture
/// as large as fits, the count in big numbers.
struct CameraSubjectPreview: View {
    @ObservedObject var model: CameraAppModel
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let pictureWidth = max(0, min(w - 24, (h - 96) * 5 / 3))
            VStack(spacing: 12) {
                Text(model.countdown != nil ? "看镜头！" : "正在拍你")
                    .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                CameraTopScreen(model: model, countdownScale: 1.6)
                    .frame(width: pictureWidth, height: pictureWidth * 3 / 5)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("镜头在这一面的相机上")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: w, height: h)
        }
        .background(Color.black.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera-subject-preview")
    }
}
