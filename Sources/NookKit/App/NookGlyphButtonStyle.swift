// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// A glyph button in the chrome's palette, sized with the companion it sits in, with every part
/// adjustable: size, glyph, colors, shape, fill, fade, hover, press, and animation.
///
/// Inside a companion it takes the companion's `NookCompanionSize`, so a row of these in a
/// capsule and a single one in a circle line up. Elsewhere it uses
/// `NookCompanionSize.regular`.
///
/// ```swift
/// HStack(spacing: 2) {
///     Button("Previous", systemImage: "backward.fill") { player.previous() }
///     Button("Play", systemImage: "play.fill") { player.toggle() }
///     Button("Next", systemImage: "forward.fill") { player.next() }
/// }
/// .buttonStyle(.nookGlyph)
///
/// // A button that is its own round surface, in a companion with the plain style:
/// Button("Leave", systemImage: "phone.down.fill") { call.leave() }
///     .buttonStyle(.nookGlyph(size: .surface, foreground: .white, fill: .color(.red)))
/// ```
///
/// Only the glyph shows; the title stays the button's accessibility label, and `help(_:)` on the
/// button adds a tooltip. A button whose label has no image shows its title instead, and reads
/// best with a capsule shape.
public struct NookGlyphButtonStyle: ButtonStyle {
    /// How big the button is.
    public enum Size: Hashable, Sendable {
        /// The shared `NookCompanionSize.controlSize`, for a control inside a surface.
        case control
        /// The shared `NookCompanionSize.height`, for a button that is a surface of its own.
        case surface
        /// A side of this many points.
        case points(CGFloat)
    }

    /// What the button is filled with.
    public enum Fill: Equatable, Sendable {
        /// Nothing until hovered.
        case none
        /// The palette's subtle fill.
        case subtle
        /// A flat color.
        case color(Color)
        /// The chrome's own material, whatever the user picked for it.
        case chromeBackdrop
    }

    public var size: Size
    /// The glyph's point size. `nil` scales the shared `NookCompanionSize.glyphSize` with the
    /// button.
    public var glyphSize: CGFloat?
    public var weight: Font.Weight
    /// The glyph's color. `nil` uses the palette's primary label.
    public var foreground: Color?
    public var shape: NookCompanionShape
    public var fill: Fill
    /// Thins the fill from the top down, the way the chrome's glass shading does.
    public var fade: NookStandardCompanionStyle.Fade?
    /// What changes under the pointer. The wash is drawn in the button's shape.
    public var hover: NookStandardCompanionStyle.Hover
    /// The button's scale while it is pressed.
    public var pressedScale: CGFloat
    /// The curve hover and press animate on.
    public var animation: Animation

    public init(
        size: Size = .control,
        glyphSize: CGFloat? = nil,
        weight: Font.Weight = .semibold,
        foreground: Color? = nil,
        shape: NookCompanionShape = .circle,
        fill: Fill = .none,
        fade: NookStandardCompanionStyle.Fade? = nil,
        hover: NookStandardCompanionStyle.Hover = .highlight,
        pressedScale: CGFloat = 0.92,
        animation: Animation = .snappy(duration: 0.18)
    ) {
        self.size = size
        self.glyphSize = glyphSize
        self.weight = weight
        self.foreground = foreground
        self.shape = shape
        self.fill = fill
        self.fade = fade
        self.hover = hover
        self.pressedScale = pressedScale
        self.animation = animation
    }

    public func makeBody(configuration: Configuration) -> some View {
        NookGlyphButtonBody(style: self, configuration: configuration)
    }

    /// The button's side at `companionSize`.
    public func side(in companionSize: NookCompanionSize) -> CGFloat {
        switch size {
            case .control: companionSize.controlSize
            case .surface: companionSize.height
            case .points(let points): max(points, 0)
        }
    }

    /// The glyph's point size at `companionSize`: ``glyphSize``, or the shared glyph size scaled
    /// from a control to this button's side.
    public func resolvedGlyphSize(in companionSize: NookCompanionSize) -> CGFloat {
        if let glyphSize { return glyphSize }
        guard companionSize.controlSize > 0 else { return companionSize.glyphSize }
        return (companionSize.glyphSize * side(in: companionSize) / companionSize.controlSize).rounded()
    }
}

extension ButtonStyle where Self == NookGlyphButtonStyle {
    /// A glyph button in the chrome's palette at the companion's control size.
    public static var nookGlyph: NookGlyphButtonStyle {
        NookGlyphButtonStyle()
    }

    /// A glyph button with the parts you pass changed.
    public static func nookGlyph(
        size: NookGlyphButtonStyle.Size = .control,
        glyphSize: CGFloat? = nil,
        weight: Font.Weight = .semibold,
        foreground: Color? = nil,
        shape: NookCompanionShape = .circle,
        fill: NookGlyphButtonStyle.Fill = .none,
        fade: NookStandardCompanionStyle.Fade? = nil,
        hover: NookStandardCompanionStyle.Hover = .highlight,
        pressedScale: CGFloat = 0.92,
        animation: Animation = .snappy(duration: 0.18)
    ) -> NookGlyphButtonStyle {
        NookGlyphButtonStyle(
            size: size,
            glyphSize: glyphSize,
            weight: weight,
            foreground: foreground,
            shape: shape,
            fill: fill,
            fade: fade,
            hover: hover,
            pressedScale: pressedScale,
            animation: animation
        )
    }
}

private struct NookGlyphButtonBody: View {
    let style: NookGlyphButtonStyle
    let configuration: ButtonStyleConfiguration

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookCompanionSize) private var companionSize
    @Environment(\.nookChromeBackdrop) private var chromeBackdrop
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let size = companionSize ?? .regular
        let side = style.side(in: size)
        let outline = style.shape.outline
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: style.resolvedGlyphSize(in: size), weight: style.weight))
            .foregroundStyle(style.foreground ?? theme.primaryLabel)
            .lineLimit(1)
            .padding(.horizontal, style.shape == .capsule ? side * 0.3 : 0)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .background {
                if let glow = style.hover.glow {
                    NookOutlineShadow(outline, color: glow.resolvedColor, radius: glow.radius, fade: style.fade)
                        .opacity(isHovered && isEnabled ? 1 : 0)
                }
                fill(in: outline)
            }
            .overlay {
                outline
                    .fill(Color.white.opacity(isHovered && isEnabled ? style.hover.wash : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(outline)
            .scaleEffect(scale)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(style.animation, value: isHovered)
            .animation(style.animation, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }

    private var scale: CGFloat {
        if configuration.isPressed { return style.pressedScale }
        return isHovered && isEnabled ? style.hover.scale : 1
    }

    @ViewBuilder
    private func fill(in outline: AnyShape) -> some View {
        let fade = NookCompanionFadeMask(fade: style.fade, edge: .below)
        switch style.fill {
            case .none:
                Color.clear
            case .subtle:
                outline.fill(theme.subtleFill).mask { fade }
            case .color(let color):
                outline.fill(color).mask { fade }
            case .chromeBackdrop:
                if let chromeBackdrop {
                    NookBackdropView(chromeBackdrop, in: outline).mask { fade }
                }
        }
    }
}
