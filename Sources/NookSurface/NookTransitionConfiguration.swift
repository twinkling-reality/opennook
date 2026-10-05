// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import SwiftUI

/// Per-instance overrides for the surface's animation curves and content transitions.
///
/// Nil curves fall back to the fixed ``NookStyle`` defaults (``NookStyle/openingAnimation``
/// and its siblings); this struct is the only place to override them. The content
/// transitions default to the surface's built-in blur, scale, and fade.
public struct NookTransitionConfiguration: Sendable {
    /// Hidden -> expanded / hidden -> compact.
    public var openingAnimation: Animation?
    /// Expanded -> hidden / compact -> hidden.
    public var closingAnimation: Animation?
    /// Compact <-> expanded.
    public var conversionAnimation: Animation?
    /// When `true`, compact<->expanded skips the intermediate hide-and-show.
    public var skipIntermediateHides: Bool

    /// Longest duration, in seconds, of any animation supplied above.
    ///
    /// SwiftUI's `Animation` exposes no portable duration accessor, so the surface cannot
    /// introspect a custom animation to know when it has visibly finished. An awaited
    /// `expand()`/`compact()` documents that it "returns once the chrome has visibly
    /// arrived"; to honor that contract for a *non-default* (typically slower) animation,
    /// a host that overrides the curves should set this to the longest of their
    /// durations. The surface sizes its post-animation settle delay from this value.
    ///
    /// `nil` (the default) means "the animations use the built-in ~0.4 s curves," and
    /// the surface falls back to its default settle constants. Set this only when you
    /// pass a custom animation whose duration differs materially from the default.
    public var animationDuration: TimeInterval?

    /// Short-lived grace after expanded content resizes. While active, hover-exit
    /// auto-compact is suppressed so a stationary cursor does not dismiss the nook
    /// when the chrome shape shrinks underneath it. `nil` uses the built-in default
    /// (~600 ms).
    public var layoutGraceDuration: TimeInterval?

    /// How the compact slots arrive and leave. Their scale runs horizontally, anchored on
    /// the side facing the notch, so the slots grow out of it. Defaults to
    /// ``NookContentTransition/standardCompact``.
    public var compactContentTransition: NookContentTransition

    /// How the expanded content arrives and leaves. Its scale runs vertically, anchored on
    /// the top edge, so the content unfolds from the notch. Defaults to
    /// ``NookContentTransition/standardExpanded``.
    public var expandedContentTransition: NookContentTransition

    public init(
        openingAnimation: Animation? = nil,
        closingAnimation: Animation? = nil,
        conversionAnimation: Animation? = nil,
        skipIntermediateHides: Bool = false,
        animationDuration: TimeInterval? = nil,
        layoutGraceDuration: TimeInterval? = nil,
        compactContentTransition: NookContentTransition = .standardCompact,
        expandedContentTransition: NookContentTransition = .standardExpanded
    ) {
        self.openingAnimation = openingAnimation
        self.closingAnimation = closingAnimation
        self.conversionAnimation = conversionAnimation
        self.skipIntermediateHides = skipIntermediateHides
        self.animationDuration = animationDuration
        self.layoutGraceDuration = layoutGraceDuration
        self.compactContentTransition = compactContentTransition
        self.expandedContentTransition = expandedContentTransition
    }
}

/// How chrome content arrives and leaves as the surface changes state: a blur, a scale, and
/// a fade, played together on the surface's own curve.
///
/// A value rather than an `AnyTransition`, so it can be compared and stored in a theme.
/// The axis and anchor of the scale are fixed by where the content sits - see
/// ``NookTransitionConfiguration/compactContentTransition`` and
/// ``NookTransitionConfiguration/expandedContentTransition``.
public struct NookContentTransition: Equatable, Sendable {
    /// Blur radius, in points, the content starts from and leaves to. 0 for none.
    public var blurRadius: CGFloat

    /// Scale along the content's axis it starts from and leaves to. 1 for none, 0 to grow
    /// from nothing.
    public var scale: CGFloat

    /// Whether the content fades in and out as well.
    public var fades: Bool

    /// A transition with the given blur and scale, fading unless `fades` is `false`.
    /// Negative values are treated as 0.
    public init(blurRadius: CGFloat = 0, scale: CGFloat = 1, fades: Bool = true) {
        self.blurRadius = max(blurRadius, 0)
        self.scale = max(scale, 0)
        self.fades = fades
    }

    /// The built-in compact slot transition: blur 6, grow from zero width, fade.
    public static let standardCompact = NookContentTransition(blurRadius: 6, scale: 0)

    /// The built-in expanded content transition: blur 6, unfold from 72% height, fade.
    public static let standardExpanded = NookContentTransition(blurRadius: 6, scale: 0.72)

    /// A plain fade.
    public static let opacity = NookContentTransition()

    /// No transition: content appears and disappears with the chrome's shape.
    public static let identity = NookContentTransition(fades: false)

    /// The SwiftUI transition this describes, scaling along `axis` from `anchor`.
    func anyTransition(axis: Axis, anchor: UnitPoint) -> AnyTransition {
        let scaled: AnyTransition =
            switch axis {
                case .horizontal: .scale(x: scale, anchor: anchor)
                case .vertical: .scale(y: scale, anchor: anchor)
            }
        let transition = AnyTransition.blur(intensity: blurRadius).combined(with: scaled)
        return fades ? transition.combined(with: .opacity) : transition
    }
}
