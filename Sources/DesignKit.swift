import SwiftUI
import AppKit

// MARK: - DesignKit
//
// Helpers distilled from the `apple-design` skill:
//  - §1 Response: feedback must be instant on press, not on release.
//  - §4 Behavior over animation: prefer springs (interruptible) over fixed durations.
//  - §14 Reduced motion: honor the system accessibility preference everywhere.

enum DesignKit {
    /// True when the user has asked the system to reduce motion.
    /// (§14) Every animated transition should consult this.
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Apple's critically-damped default (§4): graceful, no overshoot.
    /// Use for most UI transitions.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 1.0)

    /// Momentum-aware spring (§4): a little bounce, only for physical/flick gestures.
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Sheet/drawer spring (§4 table).
    static let springSheet = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Returns the appropriate animation, or `nil` when reduced motion is requested (§14).
    static func motion(_ animation: Animation) -> Animation? {
        prefersReducedMotion ? nil : animation
    }
}

/// A button style that responds on press (§1): the surface scales down and
/// dims the instant the pointer goes down, then springs back on release.
/// This keeps feedback continuous *during* the interaction rather than only
/// committing on click/touch-up.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            // Springs (§4) make the press/release interruptible and velocity-aware.
            .animation(DesignKit.motion(DesignKit.spring), value: configuration.isPressed)
    }
}

/// A plain (borderless) pressable style for icon/text buttons that should not
/// carry a filled background of their own.
struct PressablePlainStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(DesignKit.motion(DesignKit.spring), value: configuration.isPressed)
    }
}
