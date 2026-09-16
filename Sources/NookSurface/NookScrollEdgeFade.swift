// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// A soft fade where scrolling content meets the edges of the panel, instead of a hard clip.
///
/// On macOS 26 and later the top and bottom edges use Apple's own soft scroll edge effect.
/// Everywhere else - every edge on macOS 15-25, where that effect does not exist, and the
/// leading and trailing edges on macOS 26, where the system does not draw it - the fade is a
/// gradient mask. Both reserve ``length`` as a content margin on each faded edge, so content
/// at rest is never faded; only content that scrolls into the margin is.
///
/// Apply one to a scroll view with `nookScrollEdgeFade(_:axes:)`, or turn the
/// fade on for the whole panel with ``Nook/scrollEdgeFade`` and let each scroll view adopt it
/// with `nookScrollEdgeFade(axes:)`.
public struct NookScrollEdgeFade: Equatable, Sendable {
    /// The edges that may fade. A scroll view only fades the edges along its own scroll axes,
    /// so the default of all four edges suits vertical and horizontal scroll views alike;
    /// narrow it to fade, say, only the bottom of a list whose top never scrolls away.
    public var edges: Edge.Set

    /// Depth of the fade, in points - how far into the scroll view content fades.
    public var length: CGFloat

    public init(edges: Edge.Set = .all, length: CGFloat = 20) {
        self.edges = edges
        self.length = length
    }

    /// Every edge, 20 pt deep.
    public static let standard = NookScrollEdgeFade()

    /// This fade limited to the edges that lie along `axes`: top and bottom for vertical
    /// scrolling, leading and trailing for horizontal.
    public func restricted(to axes: Axis.Set) -> NookScrollEdgeFade {
        var along: Edge.Set = []
        if axes.contains(.vertical) { along.formUnion(.vertical) }
        if axes.contains(.horizontal) { along.formUnion(.horizontal) }
        return NookScrollEdgeFade(edges: edges.intersection(along), length: length)
    }

    /// `true` when the fade would change nothing.
    var isEmpty: Bool { edges.isEmpty || length <= 0 }
}

private struct NookScrollEdgeFadeKey: EnvironmentKey {
    static let defaultValue: NookScrollEdgeFade? = nil
}

extension EnvironmentValues {
    /// The panel-wide scroll edge fade from ``Nook/scrollEdgeFade``, or `nil` while the fade
    /// is off. Scroll views adopt it with `nookScrollEdgeFade(axes:)`.
    public var nookScrollEdgeFade: NookScrollEdgeFade? {
        get { self[NookScrollEdgeFadeKey.self] }
        set { self[NookScrollEdgeFadeKey.self] = newValue }
    }
}

extension View {
    /// Fades this scroll view's content at `fade`'s edges along `axes` - the axes the view
    /// scrolls on. Apply it to the `ScrollView` (or `List`) itself.
    ///
    /// ```swift
    /// ScrollView { rows }
    ///     .nookScrollEdgeFade(NookScrollEdgeFade(length: 28))
    /// ScrollView(.horizontal) { chips }
    ///     .nookScrollEdgeFade(.standard, axes: .horizontal)
    /// ```
    public func nookScrollEdgeFade(_ fade: NookScrollEdgeFade, axes: Axis.Set = .vertical) -> some View {
        modifier(NookScrollEdgeFadeModifier(fade: fade.restricted(to: axes)))
    }

    /// Adopts the panel-wide scroll edge fade (`\.nookScrollEdgeFade`) for
    /// the edges along `axes`, and does nothing while the panel's fade is off. This is how
    /// a scroll view follows the host's single opt-in rather than hard-coding a fade.
    ///
    /// ```swift
    /// ScrollView(.horizontal) { chips }
    ///     .nookScrollEdgeFade(axes: .horizontal)
    /// ```
    public func nookScrollEdgeFade(axes: Axis.Set = .vertical) -> some View {
        modifier(NookPanelScrollEdgeFadeModifier(axes: axes))
    }
}

/// Follows the panel-wide fade from the environment.
struct NookPanelScrollEdgeFadeModifier: ViewModifier {
    let axes: Axis.Set
    @Environment(\.nookScrollEdgeFade) private var panelFade

    func body(content: Content) -> some View {
        // With the fade off the scroll view is returned untouched, so a host that never
        // opts in renders exactly as it did before this modifier existed.
        if let fade = panelFade?.restricted(to: axes), !fade.isEmpty {
            content.modifier(NookScrollEdgeFadeModifier(fade: fade))
        } else {
            content
        }
    }
}

/// Picks the system effect where it exists and the mask everywhere else.
struct NookScrollEdgeFadeModifier: ViewModifier {
    let fade: NookScrollEdgeFade

    func body(content: Content) -> some View {
        if fade.isEmpty {
            content
        } else {
            fadedContent(content)
        }
    }

    @ViewBuilder
    private func fadedContent(_ content: Content) -> some View {
        // `scrollEdgeEffectStyle` and `safeAreaBar` exist only in the macOS 26 SDK, so the
        // system path is compile-gated as well as runtime-gated - the same two gates the
        // Liquid Glass backdrop uses - letting an older Xcode still build the package.
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let split = fade.systemAndMaskedEdges
                content
                    .modifier(NookSystemScrollEdgeFade(fade: split.system))
                    .modifier(NookMaskedScrollEdgeFade(fade: split.masked))
            } else {
                content.modifier(NookMaskedScrollEdgeFade(fade: fade))
            }
        #else
            content.modifier(NookMaskedScrollEdgeFade(fade: fade))
        #endif
    }
}

extension NookScrollEdgeFade {
    /// This fade split between the two macOS 26 techniques: the system soft edge effect for
    /// the top and bottom edges, and the mask for the leading and trailing edges, which the
    /// system does not draw an effect for.
    var systemAndMaskedEdges: (system: NookScrollEdgeFade, masked: NookScrollEdgeFade) {
        (
            NookScrollEdgeFade(edges: edges.intersection(.vertical), length: length),
            NookScrollEdgeFade(edges: edges.intersection(.horizontal), length: length)
        )
    }
}

#if compiler(>=6.2)
    /// Apple's soft scroll edge effect for the top and bottom edges. The system draws it only
    /// where scroll content passes under a bar, and a nook has no bars, so each faded edge gets a
    /// `safeAreaBar` of `length`: it gives the effect a region to render in, and insets resting
    /// content by the same amount the fallback's content margin does.
    @available(macOS 26.0, *)
    struct NookSystemScrollEdgeFade: ViewModifier {
        let fade: NookScrollEdgeFade

        func body(content: Content) -> some View {
            if fade.isEmpty {
                content
            } else {
                content
                    .scrollEdgeEffectStyle(.soft, for: fade.edges)
                    .safeAreaBar(edge: .top, spacing: 0) { bar(for: .top) }
                    .safeAreaBar(edge: .bottom, spacing: 0) { bar(for: .bottom) }
            }
        }

        /// The system skips a bar that draws nothing - an empty or `Color.clear` bar gets no edge
        /// effect at all - so a faded edge's bar paints a color too faint to see. An edge that is
        /// not faded gets a zero-height bar, which leaves it exactly as it was.
        @ViewBuilder
        private func bar(for edge: Edge.Set) -> some View {
            if fade.edges.contains(edge) {
                Color.black.opacity(0.001).frame(height: NookScrollEdgeFade.systemBarLength(for: fade.length))
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }
#endif

extension NookScrollEdgeFade {
    /// The height of the bar the system effect is drawn under, for a fade `length` deep.
    ///
    /// On macOS 26 SwiftUI draws no edge effect at all under a bar that lays out exactly
    /// 16 pt tall (15 and 17 pt bars both work, as does 16.5 pt on a Retina display). A bar
    /// within a point of 16 is drawn 17 pt tall instead, a difference no one can see in a
    /// fade.
    static func systemBarLength(for length: CGFloat) -> CGFloat {
        abs(length - 16) < 1 ? 17 : length
    }
}

/// The gradient-mask fade - every edge on macOS 15-25, and the leading and trailing edges on
/// macOS 26 - with a matching content margin so resting content starts clear of the fade.
struct NookMaskedScrollEdgeFade: ViewModifier {
    let fade: NookScrollEdgeFade

    func body(content: Content) -> some View {
        if fade.isEmpty {
            content
        } else {
            content
                .contentMargins(fade.edges, fade.length, for: .scrollContent)
                .mask { NookScrollEdgeFadeMask(edges: fade.edges, length: fade.length) }
        }
    }
}

/// Opaque in the middle, easing to clear across `length` at each faded edge. The vertical
/// and horizontal ramps are multiplied (one masks the other) so a corner fades on both axes.
struct NookScrollEdgeFadeMask: View {
    let edges: Edge.Set
    let length: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if edges.contains(.top) {
                ramp(from: .top, to: .bottom).frame(height: length)
            }
            Color.black
            if edges.contains(.bottom) {
                ramp(from: .bottom, to: .top).frame(height: length)
            }
        }
        .mask {
            HStack(spacing: 0) {
                if edges.contains(.leading) {
                    ramp(from: .leading, to: .trailing).frame(width: length)
                }
                Color.black
                if edges.contains(.trailing) {
                    ramp(from: .trailing, to: .leading).frame(width: length)
                }
            }
        }
    }

    /// An eased ramp - linear alpha reads as a visible band at the fade's inner edge.
    private func ramp(from start: UnitPoint, to end: UnitPoint) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.55), location: 0.55),
                .init(color: .black, location: 1),
            ],
            startPoint: start,
            endPoint: end
        )
    }
}
