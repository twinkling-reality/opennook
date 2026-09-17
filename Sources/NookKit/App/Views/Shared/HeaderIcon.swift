// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// Static header icon (no hover, no action) used by the persistent "Home" cluster.
///
/// Mirrors `HeaderIcon`'s glyph font and frame styling (``NookChromeTypography/headerIcon``
/// / ``NookChromeMetrics/headerIconSize``) so the home glyph reads at the same minimal
/// weight as the lock / gear / search icons on the right side of the topbar. The
/// deliberately muted tone (vs. `primaryLabel`) keeps it as chrome rather than competing
/// with whatever the user actually came to do.
struct StaticHeaderIcon: View {
    let systemName: String

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics

    var body: some View {
        Image(systemName: systemName)
            .font(typography.headerIcon)
            .foregroundStyle(theme.headerInactiveIcon)
            .frame(width: metrics.headerIconSize, height: metrics.headerIconSize)
    }
}

/// Hover-and-tap topbar button generic over its glyph: an SF Symbol (via ``HeaderIcon``)
/// or any custom mark, e.g. the host brand mark when the leading cluster collapses into
/// the breadcrumb's back control. The glyph closure receives the resolved foreground
/// color so custom marks track the same idle/hover/active tones as symbol glyphs, and
/// every glyph shares the `headerIconSize` frame so the hover chip reads identically
/// across the bar.
struct HeaderGlyphButton<Glyph: View>: View {
    let isActive: Bool
    let activeColor: Color
    let help: String
    /// A frame of its own instead of the top bar's, for a glyph that sits somewhere else.
    var geometry: HeaderGlyphGeometry?
    let action: () -> Void
    @ViewBuilder let glyph: (Color) -> Glyph

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeMetrics) private var metrics
    @State private var isHovering = false

    var body: some View {
        let side = geometry?.side ?? metrics.headerIconSize
        let chip = RoundedRectangle(
            cornerRadius: geometry?.cornerRadius ?? metrics.headerIconCornerRadius,
            style: .continuous
        )
        Button(action: action) {
            glyph(foreground)
                .frame(width: side, height: side)
                .background(isHovering ? theme.subtleFill : .clear, in: chip)
                .overlay(
                    chip.stroke(isHovering ? theme.subtleStroke : .clear, lineWidth: metrics.headerIconStrokeWidth)
                )
                .contentShape(chip)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }

    /// Active state wins; otherwise the glyph lifts to the emphasized primary label on
    /// hover and rests on the muted inactive tone.
    private var foreground: Color {
        if isActive { return activeColor }
        return isHovering ? theme.primaryLabel.opacity(metrics.headerIconHoverLabelOpacity) : theme.headerInactiveIcon
    }
}

/// Hover-and-tap glyph in the topbar (sidebar toggle, settings, search, etc.). Active state
/// is colored by `activeColor`; idle by the resolved theme.
struct HeaderIcon: View {
    let systemName: String
    let isActive: Bool
    let activeColor: Color
    let help: String
    var geometry: HeaderGlyphGeometry?
    let action: () -> Void

    @Environment(\.nookChromeTypography) private var typography

    var body: some View {
        HeaderGlyphButton(
            isActive: isActive,
            activeColor: activeColor,
            help: help,
            geometry: geometry,
            action: action
        ) { color in
            Image(systemName: systemName)
                .font(geometry?.font ?? typography.headerIcon)
                .foregroundStyle(color)
        }
    }
}

/// A header glyph's frame, hover chip, and font, when it sits outside the top bar.
struct HeaderGlyphGeometry: Equatable {
    var side: CGFloat
    var cornerRadius: CGFloat
    var font: Font

    /// A round chip at a companion's control size, so the lock and gear line up with the
    /// companion's other controls.
    static func companion(_ size: NookCompanionSize) -> HeaderGlyphGeometry {
        HeaderGlyphGeometry(
            side: size.controlSize,
            cornerRadius: size.controlSize / 2,
            font: .system(size: size.glyphSize, weight: .semibold)
        )
    }
}
