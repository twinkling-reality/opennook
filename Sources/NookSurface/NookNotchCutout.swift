// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// The part of a view's frame that the hardware notch covers.
///
/// In the notch form the expanded panel's top edge is the top of the screen, so the camera
/// housing covers a band across the middle of the content's top edge: ``width`` wide,
/// centered on the panel, and reaching ``height`` down into the frame. Anything drawn there
/// is hidden. The floating form has no notch and reports ``none``.
///
/// Read it with `@Environment(\.nookNotchCutout)` to keep a view clear of the notch or to
/// put views on either side of it:
///
/// ```swift
/// @Environment(\.nookNotchCutout) private var notch
///
/// var body: some View {
///     VStack(alignment: .leading) {
///         Header()
///         Rows()
///     }
///     .padding(.top, notch.height)
/// }
/// ```
///
/// Like ``NookContentInsets``, the value is relative to the frame of the view that reads it.
/// A wrapper that pads its content should re-inject an adjusted copy, made with
/// ``insetBy(top:leading:trailing:)``, so the content sees the notch relative to its own
/// frame.
public struct NookNotchCutout: Equatable, Sendable {
    /// The notch's width, or zero when there is no notch.
    public var width: CGFloat

    /// How far the notch reaches down into the frame from its top edge, or zero when it
    /// stops above the frame.
    public var height: CGFloat

    /// The notch center's horizontal distance from the frame's center, positive toward the
    /// trailing edge. Nonzero when the frame sits unevenly inside the panel.
    public var centerOffset: CGFloat

    public init(width: CGFloat = 0, height: CGFloat = 0, centerOffset: CGFloat = 0) {
        self.width = width
        self.height = height
        self.centerOffset = centerOffset
    }

    /// No notch in the frame.
    public static let none = NookNotchCutout()

    /// Whether the notch covers none of the frame.
    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    /// The cutout as seen by a frame inset from this one: the notch reaches `top` less far
    /// into it, never less than zero, and its center shifts by half the difference between
    /// the side insets.
    public func insetBy(top: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0) -> NookNotchCutout {
        NookNotchCutout(
            width: width,
            height: max(0, height - top),
            centerOffset: centerOffset + (trailing - leading) / 2
        )
    }

    /// The horizontal stretch the notch covers in a frame `frameWidth` points wide, measured
    /// from the frame's leading edge.
    public func horizontalSpan(inFrameWidth frameWidth: CGFloat) -> ClosedRange<CGFloat> {
        let center = frameWidth / 2 + centerOffset
        let halfWidth = max(0, width) / 2
        return (center - halfWidth)...(center + halfWidth)
    }
}

extension NookNotchCutout {
    /// The cutout `NookView` injects into the host's expanded view. Pulled out as a pure
    /// function so tests can pin it without a display.
    ///
    /// The chrome's horizontal padding by `topCornerRadius` is the same on both sides, so
    /// only the safe-area strips move the notch within the host's frame.
    static func expanded(
        form: NookChromeForm,
        notchSize: CGSize,
        chromeSafeAreaInsets: NookEdgeInsets
    ) -> NookNotchCutout {
        guard form == .notch, notchSize.width > 0, notchSize.height > 0 else { return .none }
        return NookNotchCutout(width: notchSize.width, height: notchSize.height)
            .insetBy(
                top: chromeSafeAreaInsets.top,
                leading: chromeSafeAreaInsets.leading,
                trailing: chromeSafeAreaInsets.trailing
            )
    }
}

private struct NookNotchCutoutEnvironmentKey: EnvironmentKey {
    static let defaultValue: NookNotchCutout = .none
}

extension EnvironmentValues {
    /// The part of the expanded view's frame the hardware notch covers. See
    /// ``NookNotchCutout``.
    public var nookNotchCutout: NookNotchCutout {
        get { self[NookNotchCutoutEnvironmentKey.self] }
        set { self[NookNotchCutoutEnvironmentKey.self] = newValue }
    }
}
