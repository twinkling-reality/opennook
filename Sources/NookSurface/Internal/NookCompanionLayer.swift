// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// Companions that share an anchor, in registration order. Each row is laid out as a unit
/// and placed against the chrome by its anchor.
struct NookCompanionRow: Identifiable {
    let anchor: NookCompanionAnchor
    var surfaces: [NookCompanionSurface]

    var id: NookCompanionAnchor { anchor }

    /// Groups `companions` by anchor. Rows appear in the order their first companion does.
    static func rows(from companions: [NookCompanionSurface]) -> [NookCompanionRow] {
        var rows: [NookCompanionRow] = []
        for companion in companions {
            if let index = rows.firstIndex(where: { $0.anchor == companion.anchor }) {
                rows[index].surfaces.append(companion)
            } else {
                rows.append(NookCompanionRow(anchor: companion.anchor, surfaces: [companion]))
            }
        }
        return rows
    }
}

struct NookCompanionRowAnchorKey: LayoutValueKey {
    static let defaultValue = NookCompanionAnchor.below
}

struct NookCompanionPresentedKey: LayoutValueKey {
    static let defaultValue = true
}

struct NookCompanionSpacingKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// Places companion rows around the chrome.
///
/// Used as an overlay on the chrome, so the bounds it is handed are the chrome's own frame.
/// Each row is placed against that frame by its anchor, entirely outside it if need be:
/// that floats companions beside the panel without changing the chrome's size, and because
/// the rows are positioned from the chrome's frame, they move with it through every
/// expand, collapse, and compact re-centering animation.
struct NookCompanionLayerLayout: Layout {
    /// Distance from the chrome's frame to its visible body on each side - the notch ears in
    /// the notch form, zero for the floating panel.
    let bodyInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // The overlay is proposed the chrome's size; claiming exactly that keeps the layer
        // from influencing the chrome's layout.
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let placement = Self.placement(
                for: subview[NookCompanionRowAnchorKey.self],
                in: bounds,
                bodyInset: bodyInset
            )
            subview.place(at: placement.point, anchor: placement.anchor, proposal: ProposedViewSize(size))
        }
    }

    /// The point on the chrome a row with `anchor` is pinned to, and which point of the row
    /// is pinned there.
    static func placement(
        for anchor: NookCompanionAnchor,
        in bounds: CGRect,
        bodyInset: CGFloat
    ) -> (point: CGPoint, anchor: UnitPoint) {
        let bodyMinX = bounds.minX + bodyInset
        let bodyMaxX = bounds.maxX - bodyInset
        switch (anchor.edge, anchor.alignment) {
            case (.below, .start): return (CGPoint(x: bodyMinX, y: bounds.maxY), .topLeading)
            case (.below, .center): return (CGPoint(x: bounds.midX, y: bounds.maxY), .top)
            case (.below, .end): return (CGPoint(x: bodyMaxX, y: bounds.maxY), .topTrailing)
            case (.leading, .start): return (CGPoint(x: bodyMinX, y: bounds.minY), .topTrailing)
            case (.leading, .center): return (CGPoint(x: bodyMinX, y: bounds.midY), .trailing)
            case (.leading, .end): return (CGPoint(x: bodyMinX, y: bounds.maxY), .bottomTrailing)
            case (.trailing, .start): return (CGPoint(x: bodyMaxX, y: bounds.minY), .topLeading)
            case (.trailing, .center): return (CGPoint(x: bodyMaxX, y: bounds.midY), .leading)
            case (.trailing, .end): return (CGPoint(x: bodyMaxX, y: bounds.maxY), .bottomLeading)
        }
    }
}

/// Lays out one row of companions.
///
/// Every companion arrives already padded toward the chrome by its own `spacing` (the
/// hover bridge, see ``NookCompanionItemView``), so a side row simply abuts its items and a
/// `.below` row adds `spacing` between neighbours. Only shown companions take up room; a
/// hidden one waits folded against the chrome edge, so showing it grows it out of the
/// chrome and hiding it folds it back in.
struct NookCompanionRowLayout: Layout {
    let anchor: NookCompanionAnchor

    struct Item: Equatable {
        var size: CGSize
        var spacing: CGFloat
        var isPresented: Bool
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.size(of: items(of: subviews), edge: anchor.edge)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = Self.frames(of: items(of: subviews), anchor: anchor, in: bounds)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func items(of subviews: Subviews) -> [Item] {
        subviews.map { subview in
            Item(
                size: subview.sizeThatFits(.unspecified),
                spacing: subview[NookCompanionSpacingKey.self],
                isPresented: subview[NookCompanionPresentedKey.self]
            )
        }
    }

    static func size(of items: [Item], edge: NookCompanionAnchor.Edge) -> CGSize {
        let shown = items.filter(\.isPresented)
        guard !shown.isEmpty else { return .zero }
        let height = shown.map(\.size.height).max() ?? 0
        let widths = shown.map(\.size.width).reduce(0, +)
        switch edge {
            case .below:
                // The first item's spacing is its drop under the chrome, already inside its
                // height; every later item's spacing is also its gap to the item before it.
                let gaps = shown.dropFirst().map(\.spacing).reduce(0, +)
                return CGSize(width: widths + gaps, height: height)
            case .leading, .trailing:
                return CGSize(width: widths, height: height)
        }
    }

    static func frames(of items: [Item], anchor: NookCompanionAnchor, in bounds: CGRect) -> [CGRect] {
        var frames: [CGRect] = []
        // A leading row grows leftward from the chrome, so its cursor starts at the edge
        // nearest the chrome and walks away from it.
        var cursor = anchor.edge == .leading ? bounds.maxX : bounds.minX
        var placedAny = false
        for item in items {
            guard item.isPresented else {
                frames.append(foldedFrame(size: item.size, anchor: anchor, in: bounds))
                continue
            }
            let y =
                anchor.edge == .below
                ? bounds.minY
                : crossAxisY(height: item.size.height, alignment: anchor.alignment, in: bounds)
            switch anchor.edge {
                case .below:
                    if placedAny { cursor += item.spacing }
                    frames.append(CGRect(origin: CGPoint(x: cursor, y: y), size: item.size))
                    cursor += item.size.width
                case .trailing:
                    frames.append(CGRect(origin: CGPoint(x: cursor, y: y), size: item.size))
                    cursor += item.size.width
                case .leading:
                    cursor -= item.size.width
                    frames.append(CGRect(origin: CGPoint(x: cursor, y: y), size: item.size))
            }
            placedAny = true
        }
        return frames
    }

    /// Where a hidden companion waits: flush against the chrome edge its row hangs from.
    static func foldedFrame(size: CGSize, anchor: NookCompanionAnchor, in bounds: CGRect) -> CGRect {
        let y = crossAxisY(height: size.height, alignment: anchor.alignment, in: bounds)
        switch anchor.edge {
            case .below:
                let x: CGFloat
                switch anchor.alignment {
                    case .start: x = bounds.minX
                    case .center: x = bounds.midX - size.width / 2
                    case .end: x = bounds.maxX - size.width
                }
                return CGRect(origin: CGPoint(x: x, y: bounds.minY), size: size)
            case .leading:
                return CGRect(origin: CGPoint(x: bounds.maxX - size.width, y: y), size: size)
            case .trailing:
                return CGRect(origin: CGPoint(x: bounds.minX, y: y), size: size)
        }
    }

    static func crossAxisY(
        height: CGFloat,
        alignment: NookCompanionAnchor.Alignment,
        in bounds: CGRect
    ) -> CGFloat {
        switch alignment {
            case .start: return bounds.minY
            case .center: return bounds.midY - height / 2
            case .end: return bounds.maxY - height
        }
    }
}

/// Squares a circle companion to its content's larger dimension, content centered.
struct NookCompanionSquareLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        let side = max(size.width, size.height)
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}

extension NookCompanionShape {
    var anyShape: AnyShape {
        switch self {
            case .capsule: return AnyShape(Capsule(style: .continuous))
            case .circle: return AnyShape(Circle())
            case .roundedRectangle(let cornerRadius):
                return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension NookCompanionAnchor.Edge {
    /// The side of a companion that faces the chrome - the point it folds toward while
    /// hidden.
    var foldAnchor: UnitPoint {
        switch self {
            case .below: return .top
            case .leading: return .trailing
            case .trailing: return .leading
        }
    }
}

/// One companion surface: the host content on its backdrop, cut to its shape, with the
/// accessibility identity, the hover bridge, and the fold for states it is not shown in.
struct NookCompanionItemView: View {
    let surface: NookCompanionSurface
    let chromeState: NookState
    /// The backdrop after ``NookCompanionBackdrop/resolved(inheriting:)``; `nil` paints nothing.
    let backdrop: NookBackdrop?
    let reduceMotion: Bool
    /// The chrome's compact<->expanded animation, reused for content-driven show and hide
    /// so a companion appearing on its own moves like one appearing with the chrome.
    let presenceAnimation: Animation
    let onHover: (Bool) -> Void
    let onVisibilityRestriction: (NookCompanionVisibility?) -> Void
    let onExtent: (CGFloat) -> Void

    @State private var restriction: NookCompanionVisibility?
    @State private var hasReceivedRestriction = false

    /// How small, and how blurred, a hidden companion is while folded into the chrome.
    static let foldedScale: CGFloat = 0.6
    static let foldedBlur: CGFloat = 6

    var isPresented: Bool {
        surface.visibility.intersection(restriction ?? .both).includes(chromeState)
    }

    var body: some View {
        let isPresented = isPresented
        bridged(surface: surfaceBody(isPresented: isPresented))
            .onHover(perform: onHover)
            .allowsHitTesting(isPresented)
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }, action: onExtent)
            .scaleEffect(
                isPresented || reduceMotion ? 1 : Self.foldedScale,
                anchor: surface.anchor.edge.foldAnchor
            )
            .blur(radius: isPresented || reduceMotion ? 0 : Self.foldedBlur)
            .opacity(isPresented ? 1 : 0)
            .layoutValue(key: NookCompanionPresentedKey.self, value: isPresented)
            .layoutValue(key: NookCompanionSpacingKey.self, value: surface.spacing)
    }

    /// The visible companion: content on its backdrop, cut to its shape, as one
    /// accessibility group.
    private func surfaceBody(isPresented: Bool) -> some View {
        let shape = surface.shape.anyShape
        return sized(surface.content.fixedSize())
            .environment(\.nookCompanionIsPresented, isPresented)
            .onPreferenceChange(NookCompanionVisibilityPreferenceKey.self) { value in
                receiveRestriction(value)
            }
            // Consume the restriction here so it cannot leak up and hide some other surface.
            .transformPreference(NookCompanionVisibilityPreferenceKey.self) { $0 = nil }
            .background {
                if let backdrop {
                    NookBackdropFill(backdrop: backdrop, shape: shape)
                        .clipShape(shape)
                }
            }
            .contentShape(shape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(surface.accessibilityIdentifier)
            .modifier(NookCompanionAccessibilityLabel(label: surface.accessibilityLabel))
            .accessibilityHidden(!isPresented)
    }

    /// Adds the hover bridge: a transparent strip across the gap to the chrome with a content
    /// shape of its own, so the pointer crossing the gap never leaves the companion's hover
    /// region. The strip draws nothing, so clicks on it still fall through to whatever is
    /// behind the panel. The strip carries the content shape rather than the whole stack:
    /// a content shape on an ancestor also becomes the accessibility frame of the group
    /// inside it, which would stretch VoiceOver's highlight across the gap.
    @ViewBuilder
    private func bridged(surface body: some View) -> some View {
        let bridge = Color.clear.contentShape(Rectangle())
        switch surface.anchor.edge {
            case .below:
                VStack(spacing: 0) {
                    bridge.frame(height: surface.spacing)
                    body
                }
            case .leading:
                HStack(spacing: 0) {
                    body
                    bridge.frame(width: surface.spacing)
                }
            case .trailing:
                HStack(spacing: 0) {
                    bridge.frame(width: surface.spacing)
                    body
                }
        }
    }

    @ViewBuilder
    private func sized(_ content: some View) -> some View {
        if surface.shape == .circle {
            NookCompanionSquareLayout { content }
        } else {
            content
        }
    }

    private func receiveRestriction(_ value: NookCompanionVisibility?) {
        onVisibilityRestriction(value)
        // The first value arrives as the panel is built, which is already faded in; only a
        // later change is a visible show or hide worth animating.
        guard hasReceivedRestriction else {
            hasReceivedRestriction = true
            restriction = value
            return
        }
        guard value != restriction else { return }
        withAnimation(presenceAnimation) { restriction = value }
    }
}

private struct NookCompanionAccessibilityLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}
