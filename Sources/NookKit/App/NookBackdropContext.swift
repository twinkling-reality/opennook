// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// Everything a backdrop resolver gets to decide with: the live appearance state *and* the
/// chrome the answer is being painted into.
///
/// The chrome asks twice for two different surfaces. Collapsed, a notch-fused panel is barely
/// taller than the hardware notch and mostly hidden behind the camera, so a gradient sized for
/// the expanded panel does nothing there but fade the two small wings either side. Expanded,
/// the same panel is tall enough for a fade to read. A resolver that only saw the appearance
/// preferences had no way to answer differently, so the two states were stuck sharing one
/// backdrop; ``state`` and ``form`` are what break the tie.
///
/// ```swift
/// configuration.chromeBehavior.backdrop = { context in
///     switch context.state {
///         case .expanded: .liquidGlass(.init(shading: .notchFade()))
///         default: .solid(.black)   // collapsed: read as the hardware notch
///     }
/// }
/// ```
///
/// A struct rather than a parameter list so later additions stay source-compatible: a new
/// field is a new property, not a new closure signature.
///
/// `Sendable`: carried into the `@Sendable @MainActor` resolvers on ``NookChromeBehavior``.
public struct NookBackdropContext: Equatable, Sendable {
    /// The live appearance preferences - surface style, chrome palette, backdrop strength.
    public var preferences: NookAppearancePreferences

    /// The effective color scheme: the host's palette override resolved against the system
    /// scheme, so a chrome pinned to `.dark` reports `.dark` under a light system.
    public var colorScheme: ColorScheme

    /// Whether the system's Reduce Transparency is on. `true` means no `NSVisualEffectView`
    /// and no glass - paint an opaque fill.
    public var reduceTransparency: Bool

    /// What the chrome is showing right now.
    ///
    /// Only `NookState.compact` and `NookState.expanded` are resolved against: the chrome
    /// keeps its last backdrop across a hide, so nothing repaints mid-fade-out. `NookState.hidden`
    /// still reaches a resolver on the cold-launch sync, before the first window exists.
    public var state: NookState

    /// The layout the chrome resolved onto its current screen - notch-fused or floating.
    /// `NookPresentation.auto` lands on either depending on the display, so this is the
    /// answer to "is there a hardware notch to match", not the host's request.
    public var form: NookChromeForm

    public init(
        preferences: NookAppearancePreferences,
        colorScheme: ColorScheme,
        reduceTransparency: Bool,
        state: NookState,
        form: NookChromeForm
    ) {
        self.preferences = preferences
        self.colorScheme = colorScheme
        self.reduceTransparency = reduceTransparency
        self.state = state
        self.form = form
    }

    /// `true` while the chrome is collapsed to its compact pill - the state a tall gradient
    /// cannot express anything in.
    public var isCompact: Bool { state == .compact }

    /// `true` while the chrome is showing its expanded panel.
    public var isExpanded: Bool { state == .expanded }
}
