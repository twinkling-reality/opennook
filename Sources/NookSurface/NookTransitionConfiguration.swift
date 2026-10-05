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
/// transitions default to the surface's built-in blur, scale, and fade, played the same way
/// in and out on the surface's own curve.
///
/// Content can leave differently from how it arrives, and arrive late:
///
/// ```swift
/// var transitions = NookTransitionConfiguration()
/// // Arrive 0.16 s after the chrome starts growing, over 0.3 s.
/// transitions.expandedContentTransition = NookContentTransition(
///     blurRadius: 8, scale: 0.97, animation: .easeOut(duration: 0.3), delay: 0.16)
/// // Leave quickly, without waiting.
/// transitions.expandedContentRemoval = NookContentTransition(
///     blurRadius: 8, scale: 0.97, animation: .easeOut(duration: 0.16))
/// ```
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

    /// How the compact slots arrive, and leave unless ``compactContentRemoval`` says
    /// otherwise. Their scale runs horizontally, anchored on the side facing the notch, so
    /// the slots grow out of it. Defaults to ``NookContentTransition/standardCompact``.
    public var compactContentTransition: NookContentTransition

    /// How the expanded content arrives, and leaves unless ``expandedContentRemoval`` says
    /// otherwise. Its scale runs vertically, anchored on the top edge, so the content unfolds
    /// from the notch. Defaults to ``NookContentTransition/standardExpanded``.
    public var expandedContentTransition: NookContentTransition

    /// How the compact slots leave, when that differs from how they arrive. `nil` (the
    /// default) plays ``compactContentTransition`` in reverse, as the surface always has.
    /// Its ``NookContentTransition/delay`` is ignored: leaving never waits.
    public var compactContentRemoval: NookContentTransition?

    /// How the expanded content leaves, when that differs from how it arrives. `nil` (the
    /// default) plays ``expandedContentTransition`` in reverse, as the surface always has.
    /// Its ``NookContentTransition/delay`` is ignored: leaving never waits.
    public var expandedContentRemoval: NookContentTransition?

    public init(
        openingAnimation: Animation? = nil,
        closingAnimation: Animation? = nil,
        conversionAnimation: Animation? = nil,
        skipIntermediateHides: Bool = false,
        animationDuration: TimeInterval? = nil,
        layoutGraceDuration: TimeInterval? = nil,
        compactContentTransition: NookContentTransition = .standardCompact,
        expandedContentTransition: NookContentTransition = .standardExpanded,
        compactContentRemoval: NookContentTransition? = nil,
        expandedContentRemoval: NookContentTransition? = nil
    ) {
        self.openingAnimation = openingAnimation
        self.closingAnimation = closingAnimation
        self.conversionAnimation = conversionAnimation
        self.skipIntermediateHides = skipIntermediateHides
        self.animationDuration = animationDuration
        self.layoutGraceDuration = layoutGraceDuration
        self.compactContentTransition = compactContentTransition
        self.expandedContentTransition = expandedContentTransition
        self.compactContentRemoval = compactContentRemoval
        self.expandedContentRemoval = expandedContentRemoval
    }
}

/// How chrome content arrives and leaves as the surface changes state: a blur, a scale, and
/// a fade, played together on the surface's own curve unless ``animation`` names another, and
/// on arrival after ``delay``.
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

    /// The curve the transition plays on. `nil` (the default) plays it on the surface's own
    /// curve, the one the chrome changes shape on.
    public var animation: Animation?

    /// Seconds the content waits, after the chrome starts changing, before it arrives. 0 (the
    /// default) arrives with the chrome. While it waits the content is held at the transition's
    /// start: faded, blurred, and scaled. Leaving never waits, so a removal ignores it.
    ///
    /// A delay with no ``animation`` of its own waits and then plays on the surface's curve.
    public var delay: TimeInterval

    /// A transition with the given blur and scale, fading unless `fades` is `false`, on
    /// `animation` (the surface's curve when `nil`), arriving `delay` seconds late.
    /// Negative and non-finite values are treated as 0.
    public init(
        blurRadius: CGFloat = 0,
        scale: CGFloat = 1,
        fades: Bool = true,
        animation: Animation? = nil,
        delay: TimeInterval = 0
    ) {
        self.blurRadius = max(blurRadius, 0)
        self.scale = max(scale, 0)
        self.fades = fades
        self.animation = animation
        self.delay = delay.isFinite ? max(delay, 0) : 0
    }

    /// The built-in compact slot transition: blur 6, grow from zero width, fade.
    public static let standardCompact = NookContentTransition(blurRadius: 6, scale: 0)

    /// The built-in expanded content transition: blur 6, unfold from 72% height, fade.
    public static let standardExpanded = NookContentTransition(blurRadius: 6, scale: 0.72)

    /// A plain fade.
    public static let opacity = NookContentTransition()

    /// No transition: content appears and disappears with the chrome's shape.
    public static let identity = NookContentTransition(fades: false)

    /// The SwiftUI transition this describes, scaling along `axis` from `anchor`, on the
    /// transaction's curve.
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

/// The content transition the surface plays for one slot: what arrives and leaves, and on which
/// curve each side plays. Built by ``plan(insertion:removal:surfaceAnimation:)``.
struct NookContentTransitionPlan: Equatable {
    /// How the content arrives.
    var insertion: NookContentTransition
    /// How the content leaves.
    var removal: NookContentTransition
    /// The curve arrival plays on, with its delay. `nil` plays it on the transaction's curve.
    var insertionAnimation: Animation?
    /// The curve leaving plays on. `nil` plays it on the transaction's curve.
    var removalAnimation: Animation?

    /// `true` when both sides are one transition on the transaction's curve: the single,
    /// reversible transition the surface played before arrival and leaving could differ.
    var isHistorical: Bool {
        insertion == removal && insertionAnimation == nil && removalAnimation == nil
    }

    /// The plan for content that arrives with `insertion` and leaves with `removal` (with
    /// `insertion` again when `nil`). A side that names no curve of its own plays on the
    /// transaction's, unless it has to wait: a wait needs a curve to delay, so it takes
    /// `surfaceAnimation`, the curve the surface changes shape on.
    static func plan(
        insertion: NookContentTransition,
        removal: NookContentTransition?,
        surfaceAnimation: Animation
    ) -> NookContentTransitionPlan {
        let removal = removal ?? insertion
        var insertionAnimation = insertion.animation
        if insertion.delay > 0 {
            insertionAnimation = (insertionAnimation ?? surfaceAnimation).delay(insertion.delay)
        }
        return NookContentTransitionPlan(
            insertion: insertion,
            removal: removal,
            insertionAnimation: insertionAnimation,
            removalAnimation: removal.animation
        )
    }

    /// The SwiftUI transition, scaling along `axis` from `anchor`. The historical plan builds
    /// exactly the transition the surface always played.
    func anyTransition(axis: Axis, anchor: UnitPoint) -> AnyTransition {
        guard !isHistorical else { return insertion.anyTransition(axis: axis, anchor: anchor) }
        var arriving = insertion.anyTransition(axis: axis, anchor: anchor)
        if let insertionAnimation { arriving = arriving.animation(insertionAnimation) }
        var leaving = removal.anyTransition(axis: axis, anchor: anchor)
        if let removalAnimation { leaving = leaving.animation(removalAnimation) }
        return .asymmetric(insertion: arriving, removal: leaving)
    }
}
