// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import SwiftUI

/// Per-edge insets, expressed in the leading/trailing reading direction (matching
/// SwiftUI's `EdgeInsets`). Used by ``NookStyle/expandedContentInsets`` to describe
/// the safe-area strip the chrome reserves around the host's expanded content.
public struct NookEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat
    public var leading: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }

    /// Same inset on all four edges.
    public init(_ all: CGFloat) {
        self.init(top: all, bottom: all, leading: all, trailing: all)
    }

    public static let zero = NookEdgeInsets()
}

/// Notch shape parameters and the spring/snap defaults the surface animates with.
///
/// Outer radius = inner radius + padding. Top is the small rounding into the notch arch,
/// bottom is the larger rounding where the panel meets the wallpaper.
///
/// ``topCornerRadius`` and ``bottomCornerRadius`` shape the expanded chrome in the notch
/// form. The compact pill and the floating form have radii of their own below; each
/// defaults to the value the chrome has always used, so a style that sets only the two
/// expanded radii draws exactly as before.
public struct NookStyle: Equatable, Sendable {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    /// Safe-area strip the chrome reserves around the host's expanded content, applied
    /// as `.safeAreaInset` on each edge of the expanded surface. This is the chrome's
    /// own clearance - distinct from any padding a host wrapper (e.g. `NookExpandedView`)
    /// adds inside it.
    ///
    /// The default (``standardExpandedContentInsets``) reproduces the historical fixed
    /// geometry: 0 on top (the top corner curve is meant to land inside the host frame,
    /// so the published ``NookContentInsets/top`` reports the full `topCornerRadius`) and
    /// 8 on the other three edges.
    ///
    /// Tightening `bottom` lets content sit closer to the rounded bottom - useful when a
    /// host wants to reclaim the dead band below its last row. Because the bottom corners
    /// curve inward by `bottomCornerRadius`, content pinned into a *bottom corner* will
    /// intersect that curve once `bottom` drops below it; the published
    /// `\.nookContentInsets` reports the residual a host must apply to
    /// clear it. Centered content (e.g. a command row) stays horizontally clear of the
    /// corners and is unaffected, so it can safely sit at the reduced bottom inset.
    public var expandedContentInsets: NookEdgeInsets

    /// The compact pill's ear radius in the notch form - how far its top edge curves in to
    /// meet the menu bar. 6 by default. It is also the pill's horizontal padding, so it
    /// moves the compact slots in or out.
    public var compactTopCornerRadius: CGFloat

    /// The compact pill's bottom corner radius in the notch form. 14 by default.
    public var compactBottomCornerRadius: CGFloat

    /// The floating form's top corner radius while expanded, or `nil` (the default) for
    /// ``bottomCornerRadius``, which makes the floating card round evenly on all four corners.
    /// Like the notch form's ears, it is also the expanded content's horizontal padding.
    public var floatingExpandedTopCornerRadius: CGFloat?

    /// The floating form's bottom corner radius while expanded, or `nil` (the default) for
    /// ``bottomCornerRadius``.
    public var floatingExpandedBottomCornerRadius: CGFloat?

    /// The floating form's compact pill radius on every corner, or `nil` (the default) for a
    /// capsule: half the pill's height, and at least 8.
    public var floatingCompactCornerRadius: CGFloat?

    /// What turns the form and radii into the chrome's outline. ``NookOutline/standard`` by
    /// default. See ``NookOutline`` for what a custom outline must keep true.
    public var outline: NookOutline

    public init(
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        expandedContentInsets: NookEdgeInsets = NookStyle.standardExpandedContentInsets,
        compactTopCornerRadius: CGFloat = NookStyle.standardCompactTopCornerRadius,
        compactBottomCornerRadius: CGFloat = NookStyle.standardCompactBottomCornerRadius,
        floatingExpandedTopCornerRadius: CGFloat? = nil,
        floatingExpandedBottomCornerRadius: CGFloat? = nil,
        floatingCompactCornerRadius: CGFloat? = nil,
        outline: NookOutline = .standard
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.expandedContentInsets = expandedContentInsets
        self.compactTopCornerRadius = compactTopCornerRadius
        self.compactBottomCornerRadius = compactBottomCornerRadius
        self.floatingExpandedTopCornerRadius = floatingExpandedTopCornerRadius
        self.floatingExpandedBottomCornerRadius = floatingExpandedBottomCornerRadius
        self.floatingCompactCornerRadius = floatingCompactCornerRadius
        self.outline = outline
    }

    /// The historical expanded-content safe-area strip: no top inset (the top corner
    /// curve lands inside the host frame), 8 pt on the other three edges.
    public static let standardExpandedContentInsets = NookEdgeInsets(
        top: 0,
        bottom: 8,
        leading: 8,
        trailing: 8
    )

    /// The compact pill's built-in ear radius in the notch form.
    public static let standardCompactTopCornerRadius: CGFloat = 6

    /// The compact pill's built-in bottom corner radius in the notch form.
    public static let standardCompactBottomCornerRadius: CGFloat = 14

    /// Reasonable default that reads well next to the system menu bar on most notched MacBooks.
    public static let standard = NookStyle(topCornerRadius: 15, bottomCornerRadius: 20)

    /// The floating form's expanded radii with the `nil` fallbacks applied.
    var resolvedFloatingExpandedRadii: (top: CGFloat, bottom: CGFloat) {
        (
            top: floatingExpandedTopCornerRadius ?? bottomCornerRadius,
            bottom: floatingExpandedBottomCornerRadius ?? bottomCornerRadius
        )
    }

    /// The floating form's compact radius for a pill `pillHeight` tall, with the `nil`
    /// fallback applied.
    func resolvedFloatingCompactRadius(pillHeight: CGFloat) -> CGFloat {
        floatingCompactCornerRadius ?? max(pillHeight / 2, 8)
    }

    // MARK: Animation

    // Precedence for every curve below: a non-nil value on the nook's
    // `NookTransitionConfiguration` wins; otherwise the surface uses these. They are fixed on
    // purpose, so there is exactly one override path.

    /// The surface's built-in expand animation, used only when the nook's
    /// ``NookTransitionConfiguration/openingAnimation`` is `nil`.
    ///
    /// These curves are not settable: ``NookTransitionConfiguration`` is the one place to
    /// override them, per nook (`Nook.transitionConfiguration`). NookKit always sets its own
    /// springs there (or the host's `NookConfiguration.transitions`), so a NookKit host never
    /// sees these.
    public var openingAnimation: Animation { .bouncy(duration: 0.4) }
    /// The surface's built-in collapse animation, used only when
    /// ``NookTransitionConfiguration/closingAnimation`` is `nil`. See ``openingAnimation``.
    public var closingAnimation: Animation { .smooth(duration: 0.4) }
    /// The surface's built-in compact<->expanded animation, used only when
    /// ``NookTransitionConfiguration/conversionAnimation`` is `nil`. See ``openingAnimation``.
    public var conversionAnimation: Animation { .snappy(duration: 0.4) }
}
