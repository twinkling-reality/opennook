// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import AppKit
import SwiftUI

/// What the chrome paints behind compact and expanded nook content.
///
/// Intentionally disjoint cases:
///
/// - ``vibrancy(_:)`` paints an `NSVisualEffectView` material with an optional darken
///   pass on top - the default frosted look, used when translucency is allowed.
/// - ``solid(_:)`` paints a flat opaque fill - used for `.solid` chrome styles and
///   whenever Reduce Transparency is on, where `NSVisualEffectView` is avoided.
/// - ``liquidGlass(_:)`` paints Apple's Liquid Glass material (macOS 26+), falling back
///   to a layered material-plus-specular-rim approximation on earlier systems.
/// - ``gradient(_:)`` paints a linear, radial, elliptical, or angular gradient.
/// - ``meshGradient(_:)`` paints a SwiftUI `MeshGradient`.
/// - ``custom(_:)`` paints a host view - an image, a shader, an animated view, anything
///   the other cases do not cover.
///
/// These are *modes*, not flags. A caller picks one and supplies only the parameters
/// that mode needs - no more eleven-field configuration struct where half the fields
/// are dead per branch.
///
/// ## Reduce Transparency
///
/// The surface paints ``vibrancy(_:)``, ``solid(_:)``, and ``liquidGlass(_:)`` exactly as
/// given; swapping them for an opaque fill under Reduce Transparency is the caller's job
/// (NookKit's backdrop mapping does it). The newer cases carry their own rule, because a
/// gradient is only as opaque as its colors:
///
/// - ``gradient(_:)`` and ``meshGradient(_:)`` paint every color fully opaque while Reduce
///   Transparency is on, so the desktop never shows through. Hues are kept; a stop's alpha
///   is dropped, so a fade to `.clear` becomes a fade to opaque black.
/// - ``custom(_:)`` is the host's view, so it is the host's call: the view reads
///   ``Custom/Context/reduceTransparency`` (or the environment) and paints something
///   opaque itself.
public enum NookBackdrop: Equatable, Sendable {
    /// Frosted vibrancy: a system material with an optional color overlay (black by
    /// default) for legibility on bright wallpapers.
    case vibrancy(Vibrancy)

    /// Flat opaque fill. Use this for `.solid` chrome styles and when Reduce
    /// Transparency is on - it avoids `NSVisualEffectView` entirely.
    case solid(Color)

    /// Liquid Glass: the macOS 26 Tahoe glass material when available, an approximation
    /// (a glassy `NSVisualEffectView` material with a tint pass, legibility darken, and
    /// a specular rim + top sheen) on macOS 15-25. See ``LiquidGlass`` for the knobs.
    case liquidGlass(LiquidGlass)

    /// A gradient filling the surface. See ``GradientFill`` for the shapes it can take.
    ///
    /// The gradient is painted with nothing behind it, so a translucent stop shows the
    /// desktop through unblurred. Under Reduce Transparency every color is painted opaque.
    case gradient(GradientFill)

    /// A SwiftUI `MeshGradient` filling the surface. Its `width * height` points and colors
    /// are the caller's; a mesh whose point or color count does not match its grid paints
    /// only its `background`. Under Reduce Transparency every color is painted opaque.
    case meshGradient(MeshGradient)

    /// A host view filling the surface: an image, a shader, an animated view. See
    /// ``Custom`` for how equality and Reduce Transparency work.
    case custom(Custom)

    /// Vibrancy parameters: which material to render, how to blend it against the
    /// content below the window, and how much darken to composite over it.
    public struct Vibrancy: Equatable, Sendable {
        /// The `NSVisualEffectView.Material` to render. `.sidebar` is the
        /// framework default; it matches Apple's translucent chrome conventions.
        public var material: NSVisualEffectView.Material

        /// `.behindWindow` (the default) samples the desktop wallpaper through the
        /// nook window. `.withinWindow` samples sibling content within the window.
        public var blendingMode: NSVisualEffectView.BlendingMode

        /// 0...1 opacity of the ``darkenColor`` overlay composited on top of the material
        /// for legibility. 0 disables the overlay entirely.
        public var darkenOpacity: CGFloat

        /// The color of the legibility overlay, painted at ``darkenOpacity``. Black (the
        /// default) darkens the material; white lightens it, for a light chrome that needs
        /// more contrast against a dark wallpaper.
        public var darkenColor: Color

        public init(
            material: NSVisualEffectView.Material = .sidebar,
            blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
            darkenOpacity: CGFloat = 0,
            darkenColor: Color = .black
        ) {
            self.material = material
            self.blendingMode = blendingMode
            self.darkenOpacity = darkenOpacity
            self.darkenColor = darkenColor
        }
    }

    /// Liquid Glass parameters. The same knobs drive both render paths: on macOS 26+
    /// they configure Apple's real glass material; on macOS 15-25 they drive the
    /// layered approximation. A host can build one directly and return it from a
    /// `NookChromeBehavior` backdrop resolver to paint brand-tinted glass - that
    /// closure, not this struct, is where the "more customizable than off-the-shelf"
    /// flexibility lives.
    public struct LiquidGlass: Equatable, Sendable {
        /// Optional color pushed through the glass. `nil` (the default) is neutral,
        /// clear glass that simply refracts the wallpaper.
        public var tint: Color?

        /// 0...1 strength of the ``tint``. Ignored when `tint` is `nil`. On macOS 26+
        /// this becomes the alpha of the glass's tint color; on the approximation it is
        /// the opacity of the tint overlay.
        public var tintStrength: CGFloat

        /// 0...1 intensity of the specular rim and top sheen that sell the glass read on
        /// pre-Tahoe systems. macOS 26+ supplies its own edge highlights, so this only
        /// adds a faint extra rim there.
        public var highlightStrength: CGFloat

        /// Legibility pass composited under chrome content, expressed as a gradient the
        /// caller fully owns - flat, bottom-weighted, top-weighted, banded, multi-stop,
        /// any direction, any color. `nil` leaves the glass pristine. The surface renders
        /// exactly this and imposes nothing of its own, so a coder building on OpenNook is
        /// never boxed into the framework's idea of the gradient; the framework's default
        /// mapping just supplies a sensible one (a top-to-bottom darken so the surface
        /// reads glassier near the wallpaper) that a host can replace wholesale.
        public var shading: Shading?

        /// Which of Apple's glass materials macOS 26 and later paints. Ignored by the
        /// pre-Tahoe approximation, which ``fallbackMaterial`` shapes instead.
        public var variant: Variant

        /// The `NSVisualEffectView` material the pre-Tahoe approximation starts from.
        /// `.hudWindow` (the default) is the glassiest of the system materials. Ignored on
        /// macOS 26 and later.
        public var fallbackMaterial: NSVisualEffectView.Material

        /// The color of the pre-Tahoe approximation's top sheen and rim, painted at
        /// ``highlightStrength``. White by default.
        public var highlightColor: Color

        /// The width, in points, of the pre-Tahoe approximation's rim. The surface clips
        /// the outer half, so the visible line is half this wide. 1 by default; 0 drops the
        /// rim and keeps the sheen.
        public var rimWidth: CGFloat

        public init(
            tint: Color? = nil,
            tintStrength: CGFloat = 0.18,
            highlightStrength: CGFloat = 0.6,
            shading: Shading? = nil,
            variant: Variant = .regular,
            fallbackMaterial: NSVisualEffectView.Material = .hudWindow,
            highlightColor: Color = .white,
            rimWidth: CGFloat = 1
        ) {
            self.tint = tint
            self.tintStrength = tintStrength
            self.highlightStrength = highlightStrength
            self.shading = shading
            self.variant = variant
            self.fallbackMaterial = fallbackMaterial
            self.highlightColor = highlightColor
            self.rimWidth = max(rimWidth, 0)
        }

        /// Apple's two Liquid Glass materials (SwiftUI `Glass.regular` and `Glass.clear`).
        public enum Variant: String, CaseIterable, Codable, Sendable {
            /// Blurs and adjusts the luminosity of what is behind it. Apple's default, and
            /// the right one for a surface that carries text.
            case regular

            /// Highly translucent, for a surface over visually rich media. Apple recommends
            /// a dimming layer behind content on clear glass; ``LiquidGlass/shading`` is
            /// where that goes.
            case clear
        }

        /// A shading pass: a `Gradient` plus the direction it runs across the surface.
        /// Build one directly for full control, or use ``uniform(_:)`` for a flat fill.
        /// Because it carries a whole gradient, a host can shape the glass any way it
        /// likes without the framework constraining it to a single knob.
        public struct Shading: Equatable, Sendable {
            /// The gradient painted over the glass. Its stops and colors are entirely the
            /// caller's; the framework never rewrites them.
            public var gradient: Gradient

            /// Where the gradient begins. Defaults to the top edge.
            public var startPoint: UnitPoint

            /// Where the gradient ends. Defaults to the bottom edge - so a two-stop
            /// gradient runs top-to-bottom, the common "glassier toward the bottom" case.
            public var endPoint: UnitPoint

            public init(
                gradient: Gradient,
                startPoint: UnitPoint = .top,
                endPoint: UnitPoint = .bottom
            ) {
                self.gradient = gradient
                self.startPoint = startPoint
                self.endPoint = endPoint
            }

            /// A flat, uniform shading of one color - no gradient falloff.
            public static func uniform(_ color: Color) -> Shading {
                Shading(gradient: Gradient(colors: [color, color]))
            }

            /// `color` in full where the chrome meets the hardware notch, thinning to nothing at
            /// the bottom so the wallpaper shows through lower down - the look of notch apps
            /// whose panel grows out of the notch. `strength` (clamped to 0...1) scales how dark
            /// the fade is below the top edge; the top edge itself always matches the notch.
            ///
            /// ```swift
            /// .liquidGlass(.init(shading: .notchFade()))
            /// ```
            public static func notchFade(_ color: Color = .black, strength: Double = 1) -> Shading {
                let strength = min(max(strength, 0), 1)
                return Shading(
                    gradient: Gradient(stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0.9 * strength), location: 0.22),
                        .init(color: color.opacity(0.4 * strength), location: 0.58),
                        .init(color: color.opacity(0), location: 1),
                    ])
                )
            }
        }
    }

    /// A gradient backdrop: a SwiftUI `Gradient` and the shape it is laid out in.
    ///
    /// ```swift
    /// nook.backdrop = .gradient(.linear(Gradient(colors: [.indigo, .black])))
    /// nook.backdrop = .gradient(.angular(Gradient(colors: [.pink, .orange, .pink])))
    /// ```
    public struct GradientFill: Equatable, Sendable {
        /// How a ``GradientFill`` lays its gradient out across the surface. Points are unit
        /// points of the surface's frame; elliptical radii are fractions of it, so an
        /// elliptical gradient keeps its look as the chrome grows from the compact pill to the
        /// expanded panel, where a radial one keeps its size in points.
        public enum Layout: Equatable, Sendable {
            /// SwiftUI `LinearGradient` from `startPoint` to `endPoint`.
            case linear(startPoint: UnitPoint, endPoint: UnitPoint)
            /// SwiftUI `RadialGradient` around `center`, radii in points.
            case radial(center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat)
            /// SwiftUI `EllipticalGradient` around `center`, radii as fractions of the frame.
            case elliptical(center: UnitPoint, startRadiusFraction: CGFloat, endRadiusFraction: CGFloat)
            /// SwiftUI `AngularGradient` around `center`, from `startAngle` to `endAngle`.
            case angular(center: UnitPoint, startAngle: Angle, endAngle: Angle)
        }

        /// The gradient's stops. Entirely the caller's; the surface only drops their alpha
        /// under Reduce Transparency.
        public var gradient: Gradient

        /// Where the gradient runs.
        public var layout: Layout

        public init(gradient: Gradient, layout: Layout) {
            self.gradient = gradient
            self.layout = layout
        }

        /// A linear gradient, top to bottom unless told otherwise.
        public static func linear(
            _ gradient: Gradient,
            startPoint: UnitPoint = .top,
            endPoint: UnitPoint = .bottom
        ) -> GradientFill {
            GradientFill(gradient: gradient, layout: .linear(startPoint: startPoint, endPoint: endPoint))
        }

        /// A radial gradient around `center`, with radii in points.
        public static func radial(
            _ gradient: Gradient,
            center: UnitPoint = .center,
            startRadius: CGFloat = 0,
            endRadius: CGFloat
        ) -> GradientFill {
            GradientFill(
                gradient: gradient,
                layout: .radial(center: center, startRadius: startRadius, endRadius: endRadius)
            )
        }

        /// An elliptical gradient around `center` that scales with the surface: radius 1 is
        /// half the frame's width horizontally and half its height vertically.
        public static func elliptical(
            _ gradient: Gradient,
            center: UnitPoint = .center,
            startRadiusFraction: CGFloat = 0,
            endRadiusFraction: CGFloat = 0.5
        ) -> GradientFill {
            GradientFill(
                gradient: gradient,
                layout: .elliptical(
                    center: center,
                    startRadiusFraction: startRadiusFraction,
                    endRadiusFraction: endRadiusFraction
                )
            )
        }

        /// An angular (conic) gradient around `center`, one full turn unless told otherwise.
        public static func angular(
            _ gradient: Gradient,
            center: UnitPoint = .center,
            startAngle: Angle = .zero,
            endAngle: Angle = .degrees(360)
        ) -> GradientFill {
            GradientFill(
                gradient: gradient,
                layout: .angular(center: center, startAngle: startAngle, endAngle: endAngle)
            )
        }
    }

    /// A host view painted as the backdrop, for anything the value cases do not cover:
    /// an image, a `Shader`, a `TimelineView` animation, a stack of materials.
    ///
    /// Views cannot be compared, so ``id`` stands in for the view in equality: two
    /// `Custom` values with the same id are equal whatever they draw. Give a different
    /// look a different id, or a change of backdrop that keeps the id may not repaint.
    ///
    /// ```swift
    /// nook.backdrop = .custom(.init(id: "aurora") { context in
    ///     if context.reduceTransparency {
    ///         Color.black
    ///     } else {
    ///         AuroraView()
    ///     }
    /// })
    /// ```
    ///
    /// The view fills the surface's frame and the surface clips it to the chrome's outline.
    /// It is the host's view end to end, Reduce Transparency included: paint something
    /// opaque when ``Context/reduceTransparency`` is `true`. Keep it cheap - it is on screen
    /// for as long as the chrome is, so pause animation you do not need (see
    /// `TimelineSchedule.animation(minimumInterval:paused:)`), and do not put shader or
    /// `drawingGroup()` effects over an `NSVisualEffectView`; they cannot render it.
    public struct Custom: Equatable, Sendable {
        /// What a custom backdrop knows about the surface it fills.
        public struct Context {
            /// The outline of the surface being painted - the chrome's ``NookShape`` or a
            /// companion's shape - in the view's own frame. Stroke or fill it to trace
            /// the edge.
            public var shape: AnyShape

            /// Whether the system's Reduce Transparency is on. When it is, paint
            /// something opaque.
            public var reduceTransparency: Bool

            public init(shape: AnyShape, reduceTransparency: Bool) {
                self.shape = shape
                self.reduceTransparency = reduceTransparency
            }
        }

        /// Identifies what the view draws. Equality compares this and nothing else.
        public let id: String

        private let body: any NookCustomBackdropBody

        /// A backdrop drawn by `content`, identified by `id`.
        public init<Content: View>(
            id: String,
            @ViewBuilder content: @escaping @MainActor @Sendable (Context) -> Content
        ) {
            self.id = id
            self.body = NookCustomBackdropContent(content: content)
        }

        /// The view for `context`.
        @MainActor
        func makeView(_ context: Context) -> AnyView {
            body.makeView(context)
        }

        public static func == (lhs: Custom, rhs: Custom) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// The default backdrop - a pure black solid, matching the menu-bar notch chrome
    /// when no other treatment is wanted. Equivalent to the historical
    /// `NookBackdropConfiguration.solidBlack`; rendering is byte-identical.
    public static let solidBlack = NookBackdrop.solid(.black)
}

/// Type-erases a custom backdrop's view builder. Held as an existential rather than an
/// `AnyView`-returning closure, which would capture the view's metatype in an isolated
/// closure.
private protocol NookCustomBackdropBody: Sendable {
    @MainActor func makeView(_ context: NookBackdrop.Custom.Context) -> AnyView
}

private struct NookCustomBackdropContent<Content: View>: NookCustomBackdropBody {
    let content: @MainActor @Sendable (NookBackdrop.Custom.Context) -> Content

    @MainActor
    func makeView(_ context: NookBackdrop.Custom.Context) -> AnyView {
        AnyView(content(context))
    }
}

/// Paints a ``NookBackdrop`` in a shape the way the chrome paints its own - solid, vibrancy, or
/// Liquid Glass, with the same availability fallbacks - for companion styles and content that
/// draw their own pieces, such as a segmented pill or separately filled buttons.
///
/// ```swift
/// @Environment(\.nookChromeBackdrop) private var chromeBackdrop
///
/// var body: some View {
///     if let chromeBackdrop {
///         NookBackdropView(chromeBackdrop, in: UnevenRoundedRectangle(topLeadingRadius: 20))
///     }
/// }
/// ```
///
/// The backdrop is clipped to `shape`.
public struct NookBackdropView<S: Shape>: View {
    let backdrop: NookBackdrop
    let shape: S

    public init(_ backdrop: NookBackdrop, in shape: S) {
        self.backdrop = backdrop
        self.shape = shape
    }

    public var body: some View {
        NookBackdropFill(backdrop: backdrop, shape: shape)
            .clipShape(shape)
    }
}

private struct NookChromeBackdropKey: EnvironmentKey {
    static let defaultValue: NookBackdrop? = nil
}

private struct NookChromeShapeKey: EnvironmentKey {
    static let defaultValue: NookShape? = nil
}

extension EnvironmentValues {
    /// The chrome's outline right now - its form, radii, and ``NookOutline`` - inside compact
    /// and expanded content. `nil` anywhere else.
    ///
    /// The shape describes the chrome's own frame, which is larger than the content's: the
    /// chrome pads content horizontally by the top radius and by
    /// ``NookStyle/expandedContentInsets``. Draw it in a frame of the chrome's size to trace
    /// the chrome's edge. It changes in the same transaction as the chrome, so a view drawing
    /// it springs along with it.
    public var nookChromeShape: NookShape? {
        get { self[NookChromeShapeKey.self] }
        set { self[NookChromeShapeKey.self] = newValue }
    }

    /// What the chrome is painted with right now, inside compact, expanded, and companion
    /// content. `nil` anywhere else. Paint it with ``NookBackdropView``.
    ///
    /// Inside companion content it is the backdrop companions inherit, which is the chrome's
    /// own unless the chrome sets a ``Nook/companionBackdrop``.
    public var nookChromeBackdrop: NookBackdrop? {
        get { self[NookChromeBackdropKey.self] }
        set { self[NookChromeBackdropKey.self] = newValue }
    }
}
