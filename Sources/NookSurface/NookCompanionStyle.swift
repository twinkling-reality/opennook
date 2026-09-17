// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

// MARK: - Protocol

/// Draws a companion surface around its content: its fill, edge, shadow, padding, size, and how
/// it answers the pointer.
///
/// The framework positions the surface, folds it away in states it is not shown in, and keeps it
/// in the chrome's hover region; the style decides everything the surface looks like. Configure
/// ``NookStandardCompanionStyle`` for the common looks, or conform to this protocol for full
/// control:
///
/// ```swift
/// struct OutlinedStyle: NookCompanionStyle {
///     var color: Color
///
///     func makeBody(configuration: Configuration) -> some View {
///         configuration.content
///             .padding(configuration.size.inset)
///             .frame(minHeight: configuration.size.height)
///             .overlay {
///                 configuration.shape.outline.stroke(color, lineWidth: configuration.isHovered ? 2 : 1)
///             }
///     }
/// }
///
/// configuration.addCompanion(id: "live", style: .custom(OutlinedStyle(color: .cyan))) { LiveBadge() }
/// ```
///
/// A style draws the whole surface, so one that should show the companion's backdrop paints
/// `configuration.backdrop`, for example with ``NookBackdropView``.
public protocol NookCompanionStyle: Sendable {
    associatedtype Body: View

    typealias Configuration = NookCompanionStyleConfiguration

    /// The surface for one companion.
    @MainActor @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// What a ``NookCompanionStyle`` draws with.
public struct NookCompanionStyleConfiguration {
    /// The companion's content. A circle companion's content arrives squared to its larger
    /// dimension.
    public struct Content: View {
        let base: AnyView

        public var body: some View {
            base
        }
    }

    /// The companion's content.
    public let content: Content

    /// The companion's outline, which it is also hit-tested with. Draw it with
    /// ``NookCompanionShape/outline``.
    public let shape: NookCompanionShape

    /// What the companion's backdrop resolves to: the chrome's own for
    /// ``NookCompanionBackdrop/inherit``, the companion's for ``NookCompanionBackdrop/custom(_:)``,
    /// and `nil` for ``NookCompanionBackdrop/none``.
    public let backdrop: NookBackdrop?

    /// The chrome edge the companion hangs from, for effects that run away from the chrome.
    public let edge: NookCompanionAnchor.Edge

    /// The size the companion shares with its controls.
    public let size: NookCompanionSize

    /// Whether the pointer is over the surface. Settable, so one style can draw another in a
    /// state of its choosing.
    public var isHovered: Bool

    /// Whether the companion is shown in the chrome's current state. A hidden companion stays
    /// mounted while it folds away.
    public let isPresented: Bool

    @MainActor
    public init(
        content: some View,
        shape: NookCompanionShape,
        backdrop: NookBackdrop?,
        edge: NookCompanionAnchor.Edge,
        size: NookCompanionSize,
        isHovered: Bool,
        isPresented: Bool
    ) {
        self.content = Content(base: AnyView(content))
        self.shape = shape
        self.backdrop = backdrop
        self.edge = edge
        self.size = size
        self.isHovered = isHovered
        self.isPresented = isPresented
    }
}

/// Any ``NookCompanionStyle``, so a `Sendable` configuration can carry one.
///
/// Pick a preset, adjust the standard style, or wrap your own:
///
/// ```swift
/// configuration.companionStyle = .faded
/// configuration.addCompanion(id: "send", style: .standard(shadow: .soft, hover: .lift)) { SendButton() }
/// configuration.addCompanion(id: "live", style: .custom(OutlinedStyle(color: .cyan))) { LiveBadge() }
/// ```
public struct AnyNookCompanionStyle: Sendable {
    /// The wrapped style, for inspection.
    public let base: any NookCompanionStyle

    private let make: @Sendable @MainActor (NookCompanionStyleConfiguration) -> AnyView

    public init<Style: NookCompanionStyle>(_ style: Style) {
        base = style
        make = { configuration in AnyView(style.makeBody(configuration: configuration)) }
    }

    /// The wrapped style's surface for `configuration`.
    @MainActor
    public func makeBody(configuration: NookCompanionStyleConfiguration) -> AnyView {
        make(configuration)
    }

    /// The framework's look: the companion's backdrop at the shared size. See
    /// ``NookStandardCompanionStyle``.
    public static var standard: AnyNookCompanionStyle {
        AnyNookCompanionStyle(NookStandardCompanionStyle.standard)
    }

    /// Solid where the companion meets the chrome, fading as it leaves it - the way the Liquid
    /// Glass chrome's own shading thins toward the wallpaper.
    public static var faded: AnyNookCompanionStyle {
        AnyNookCompanionStyle(NookStandardCompanionStyle.faded)
    }

    /// A hairline edge and a soft shadow, lifting under the pointer.
    public static var raised: AnyNookCompanionStyle {
        AnyNookCompanionStyle(NookStandardCompanionStyle.raised)
    }

    /// No surface: no fill and no padding, so the content draws every piece itself, such as
    /// separately filled buttons.
    public static var plain: AnyNookCompanionStyle {
        AnyNookCompanionStyle(NookStandardCompanionStyle.plain)
    }

    /// The standard style with the parts you pass changed.
    public static func standard(
        fill: NookStandardCompanionStyle.Fill = .backdrop,
        fade: NookStandardCompanionStyle.Fade? = nil,
        stroke: NookStandardCompanionStyle.Stroke? = nil,
        shadow: NookStandardCompanionStyle.Shadow? = nil,
        hover: NookStandardCompanionStyle.Hover = .none,
        padding: EdgeInsets? = nil,
        height: NookStandardCompanionStyle.Height = .shared,
        animation: Animation = NookStandardCompanionStyle.defaultAnimation
    ) -> AnyNookCompanionStyle {
        AnyNookCompanionStyle(
            NookStandardCompanionStyle(
                fill: fill,
                fade: fade,
                stroke: stroke,
                shadow: shadow,
                hover: hover,
                padding: padding,
                height: height,
                animation: animation
            )
        )
    }

    /// A style of your own.
    public static func custom(_ style: some NookCompanionStyle) -> AnyNookCompanionStyle {
        AnyNookCompanionStyle(style)
    }
}

// MARK: - Standard style

/// The framework's companion style, with every part adjustable: fill, fade, edge, shadow, hover,
/// padding, height, and the curve hover animates on.
///
/// By default it paints the companion's backdrop in its shape, pads the content by the shared
/// ``NookCompanionSize/inset``, and makes the surface at least ``NookCompanionSize/height`` tall -
/// so a circle holding one control and a capsule holding several are the same height.
public struct NookStandardCompanionStyle: NookCompanionStyle, Equatable {
    /// What the surface is filled with.
    public enum Fill: Equatable, Sendable {
        /// The companion's backdrop: the chrome's own unless the companion sets one.
        case backdrop
        /// Nothing, whatever the backdrop is.
        case none
    }

    /// A fill that thins as it runs away from the chrome.
    public struct Fade: Equatable, Sendable {
        /// The fill's opacity where the companion meets the chrome, from 0 to 1.
        public var start: Double
        /// The fill's opacity at the companion's far side, from 0 to 1.
        public var end: Double

        public init(start: Double = 1, end: Double = 0.25) {
            self.start = min(max(start, 0), 1)
            self.end = min(max(end, 0), 1)
        }

        /// Solid at the chrome, a quarter strength at the far side.
        public static let standard = Fade()

        /// Solid at the chrome, gone at the far side.
        public static let toClear = Fade(start: 1, end: 0)
    }

    /// What changes while the pointer is over the surface. The parts combine.
    public struct Hover: Equatable, Sendable {
        /// The opacity of a white wash over the surface, from 0 (none) to 1.
        public var wash: Double
        /// The surface's scale. 1 for none.
        public var scale: CGFloat
        /// A glow around the surface.
        public var glow: Glow?

        public init(wash: Double = 0, scale: CGFloat = 1, glow: Glow? = nil) {
            self.wash = min(max(wash, 0), 1)
            self.scale = max(scale, 0)
            self.glow = glow
        }

        /// No change.
        public static let none = Hover()

        /// A faint wash.
        public static let highlight = Hover(wash: 0.08)

        /// A slight grow and a fainter wash.
        public static let lift = Hover(wash: 0.04, scale: 1.05)

        /// A soft white glow.
        public static let glow = Hover(glow: Glow())
    }

    /// A soft light around a surface.
    public struct Glow: Equatable, Sendable {
        /// The glow's color. `nil` glows in soft white.
        public var color: Color?
        public var radius: CGFloat

        public init(color: Color? = nil, radius: CGFloat = 10) {
            self.color = color
            self.radius = max(radius, 0)
        }

        /// ``color``, or the soft white a glow without one uses.
        public var resolvedColor: Color {
            color ?? .white.opacity(0.55)
        }
    }

    /// A line along the inside of the surface's edge.
    public struct Stroke: Equatable, Sendable {
        public var color: Color
        public var width: CGFloat

        public init(color: Color = .white.opacity(0.16), width: CGFloat = 1) {
            self.color = color
            self.width = max(width, 0)
        }

        /// A 1 pt line in faint white.
        public static let hairline = Stroke()
    }

    /// A shadow around the surface, cast by its outline.
    public struct Shadow: Equatable, Sendable {
        public var color: Color
        public var radius: CGFloat
        public var y: CGFloat

        public init(color: Color = .black.opacity(0.35), radius: CGFloat = 8, y: CGFloat = 3) {
            self.color = color
            self.radius = max(radius, 0)
            self.y = y
        }

        /// A short, soft shadow.
        public static let soft = Shadow()
    }

    /// How tall the surface is.
    public enum Height: Equatable, Sendable {
        /// At least the shared ``NookCompanionSize/height``, growing if the content needs more.
        case shared
        /// The content's own height plus the padding.
        case content
        /// At least this tall.
        case minimum(CGFloat)
        /// Exactly this tall.
        case fixed(CGFloat)
    }

    public var fill: Fill
    public var fade: Fade?
    public var stroke: Stroke?
    public var shadow: Shadow?
    public var hover: Hover
    /// Padding around the content. `nil` pads every side by the shared
    /// ``NookCompanionSize/inset``.
    public var padding: EdgeInsets?
    public var height: Height
    /// The curve hover changes animate on.
    public var animation: Animation

    /// The curve hover changes animate on unless a style says otherwise.
    public static let defaultAnimation = Animation.snappy(duration: 0.2)

    public init(
        fill: Fill = .backdrop,
        fade: Fade? = nil,
        stroke: Stroke? = nil,
        shadow: Shadow? = nil,
        hover: Hover = .none,
        padding: EdgeInsets? = nil,
        height: Height = .shared,
        animation: Animation = NookStandardCompanionStyle.defaultAnimation
    ) {
        self.fill = fill
        self.fade = fade
        self.stroke = stroke
        self.shadow = shadow
        self.hover = hover
        self.padding = padding
        self.height = height
        self.animation = animation
    }

    /// The companion's backdrop at the shared size, with no effects.
    public static let standard = NookStandardCompanionStyle()

    /// Solid where the companion meets the chrome, fading as it leaves it.
    public static let faded = NookStandardCompanionStyle(fade: .standard)

    /// A hairline edge and a soft shadow, lifting under the pointer.
    public static let raised = NookStandardCompanionStyle(stroke: .hairline, shadow: .soft, hover: .lift)

    /// No fill and no padding, at the content's own size.
    public static let plain = NookStandardCompanionStyle(fill: .none, padding: EdgeInsets(), height: .content)

    public func makeBody(configuration: Configuration) -> some View {
        NookStandardCompanionBody(style: self, configuration: configuration)
    }

    /// The least height the style gives a surface at `size`, or `nil` for none. A circle is at
    /// least this wide too.
    func minimumHeight(for size: NookCompanionSize) -> CGFloat? {
        switch height {
            case .shared: size.height
            case .content: nil
            case .minimum(let height): max(height, 0)
            case .fixed(let height): max(height, 0)
        }
    }

    /// The padding the style puts around the content at `size`.
    func resolvedPadding(for size: NookCompanionSize) -> EdgeInsets {
        padding ?? EdgeInsets(top: size.inset, leading: size.inset, bottom: size.inset, trailing: size.inset)
    }
}

private struct NookStandardCompanionBody: View {
    let style: NookStandardCompanionStyle
    let configuration: NookCompanionStyleConfiguration

    var body: some View {
        let outline = configuration.shape.outline
        let isCircle = configuration.shape == .circle
        let minimum = style.minimumHeight(for: configuration.size)
        let fixed: CGFloat? =
            if case .fixed(let height) = style.height { max(height, 0) } else { nil }
        configuration.content
            .padding(style.resolvedPadding(for: configuration.size))
            .frame(minWidth: isCircle ? minimum : nil, minHeight: minimum)
            .frame(width: isCircle ? fixed : nil, height: fixed)
            .background {
                shadows(in: outline)
                fill(in: outline)
            }
            .overlay {
                if let stroke = style.stroke, stroke.width > 0 {
                    // Twice the width, clipped to the outline, leaves a line of `width` inside it.
                    outline
                        .stroke(stroke.color, lineWidth: stroke.width * 2)
                        .clipShape(outline)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                outline
                    .fill(Color.white.opacity(configuration.isHovered ? style.hover.wash : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isHovered ? style.hover.scale : 1)
            .animation(style.animation, value: configuration.isHovered)
    }

    /// The shadow, and the glow that takes its place under the pointer so the two never stack.
    /// Both are cast by the outline, so they show whether or not the surface is filled.
    @ViewBuilder
    private func shadows(in outline: AnyShape) -> some View {
        let glowing = configuration.isHovered && style.hover.glow != nil
        if let shadow = style.shadow {
            NookOutlineShadow(
                outline,
                color: shadow.color,
                radius: shadow.radius,
                y: shadow.y,
                fade: style.fade,
                edge: configuration.edge
            )
            .opacity(glowing ? 0 : 1)
        }
        if let glow = style.hover.glow {
            NookOutlineShadow(
                outline,
                color: glow.resolvedColor,
                radius: glow.radius,
                fade: style.fade,
                edge: configuration.edge
            )
            .opacity(glowing ? 1 : 0)
        }
    }

    @ViewBuilder
    private func fill(in outline: AnyShape) -> some View {
        switch style.fill {
            case .backdrop:
                if let backdrop = configuration.backdrop {
                    NookBackdropView(backdrop, in: outline)
                        .mask { NookCompanionFadeMask(fade: style.fade, edge: configuration.edge) }
                }
            case .none:
                Color.clear
        }
    }
}

/// A shadow or glow cast by a shape's outline and drawn only outside it.
///
/// Because the shape itself is never drawn, the shadow shows the same whether the shape is
/// filled, faded, or empty, and never darkens a translucent fill. With a fade it thins away from
/// the chrome the way a fill with that fade does.
///
/// ```swift
/// Circle().fill(.clear)
///     .background { NookOutlineShadow(Circle(), color: .cyan, radius: 8) }
/// ```
public struct NookOutlineShadow: View {
    let shape: AnyShape
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    let fade: NookStandardCompanionStyle.Fade?
    let edge: NookCompanionAnchor.Edge

    /// A shadow of `shape` in `color`, blurred by `radius` and offset by `x` and `y`, thinned by
    /// `fade` away from a chrome on `edge`'s side.
    public init(
        _ shape: some Shape,
        color: Color,
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat = 0,
        fade: NookStandardCompanionStyle.Fade? = nil,
        edge: NookCompanionAnchor.Edge = .below
    ) {
        self.shape = AnyShape(shape)
        self.color = color
        self.radius = max(radius, 0)
        self.x = x
        self.y = y
        self.fade = fade
        self.edge = edge
    }

    /// How far past the shape the shadow can reach.
    var reach: CGFloat {
        (radius * 2 + max(abs(x), abs(y))).rounded(.up)
    }

    public var body: some View {
        let reach = reach
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: reach, dy: reach)
            guard rect.width > 0, rect.height > 0 else { return }
            let path = shape.path(in: rect)
            var shadow = context
            shadow.addFilter(.shadow(color: color, radius: radius, x: x, y: y, options: .shadowOnly))
            shadow.fill(path, with: .color(.black))
            if let fade {
                context.blendMode = .destinationIn
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [.black.opacity(fade.start), .black.opacity(fade.end)]),
                        startPoint: rect.point(at: edge.towardChrome),
                        endPoint: rect.point(at: edge.awayFromChrome)
                    )
                )
            }
            // Leave nothing under the shape itself.
            context.blendMode = .destinationOut
            context.fill(path, with: .color(.black))
        }
        .padding(-reach)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension CGRect {
    fileprivate func point(at unitPoint: UnitPoint) -> CGPoint {
        CGPoint(x: minX + unitPoint.x * width, y: minY + unitPoint.y * height)
    }
}

/// A mask that thins a fill away from the chrome, or leaves it whole with no fade.
public struct NookCompanionFadeMask: View {
    let fade: NookStandardCompanionStyle.Fade?
    let edge: NookCompanionAnchor.Edge

    /// A mask for a fill on a companion hanging from `edge`. `nil` leaves the fill whole.
    public init(fade: NookStandardCompanionStyle.Fade?, edge: NookCompanionAnchor.Edge) {
        self.fade = fade
        self.edge = edge
    }

    public var body: some View {
        if let fade {
            LinearGradient(
                colors: [.black.opacity(fade.start), .black.opacity(fade.end)],
                startPoint: edge.towardChrome,
                endPoint: edge.awayFromChrome
            )
        } else {
            Color.black
        }
    }
}

// MARK: - Geometry helpers

extension NookCompanionAnchor.Edge {
    /// The side of a companion that faces the chrome: the top of one below it, the trailing
    /// side of one on its leading edge, the leading side of one on its trailing edge.
    public var towardChrome: UnitPoint {
        switch self {
            case .below: .top
            case .leading: .trailing
            case .trailing: .leading
        }
    }

    /// The side of a companion that faces away from the chrome.
    public var awayFromChrome: UnitPoint {
        switch self {
            case .below: .bottom
            case .leading: .leading
            case .trailing: .trailing
        }
    }
}

extension NookCompanionShape {
    /// The outline as a SwiftUI shape, for styles and content that draw in it.
    public var outline: AnyShape {
        switch self {
            case .capsule: AnyShape(Capsule(style: .continuous))
            case .circle: AnyShape(Circle())
            case .roundedRectangle(let cornerRadius):
                AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
