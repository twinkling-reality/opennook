// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

struct NookCompanionAnchorKey: LayoutValueKey {
    static let defaultValue = NookCompanionAnchor.below
}

struct NookCompanionPresentedKey: LayoutValueKey {
    static let defaultValue = true
}

struct NookCompanionSpacingKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

struct NookCompanionGapKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

struct NookCompanionRowAlignmentKey: LayoutValueKey {
    static let defaultValue = NookCompanionAnchor.Alignment.center
}

/// Places every companion around the chrome.
///
/// Used as an overlay on the chrome, so the bounds it is handed are the chrome's own frame.
/// Companions that share an anchor form a row, in the order they are given, and each row is
/// placed against that frame by its anchor, entirely outside it if need be: that floats
/// companions beside the panel without changing the chrome's size, and because the rows are
/// positioned from the chrome's frame, they move with it through every expand, collapse, and
/// compact re-centering animation.
///
/// Every companion is a direct subview, rather than a child of a row container, so a companion
/// added or removed is the view SwiftUI inserts or removes and plays its own transition, even
/// when it is the first or last one on its anchor.
struct NookCompanionLayerLayout: Layout {
    /// Distance from the chrome's frame to its visible body on each side - the notch ears in
    /// the notch form, zero for the floating panel.
    let bodyInset: CGFloat
    /// Whether a row beside the chrome is kept from rising above the chrome's top edge. The
    /// notch form's top edge is the top of the screen, so anything above it would be cut off.
    let keepsSideRowsBelowTop: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // The overlay is proposed the chrome's size; claiming exactly that keeps the layer
        // from influencing the chrome's layout.
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let items = subviews.map { subview in
            NookCompanionRowGeometry.Item(
                anchor: subview[NookCompanionAnchorKey.self],
                size: subview.sizeThatFits(.unspecified),
                spacing: subview[NookCompanionSpacingKey.self],
                isPresented: subview[NookCompanionPresentedKey.self],
                gap: subview[NookCompanionGapKey.self],
                rowAlignment: subview[NookCompanionRowAlignmentKey.self]
            )
        }
        let frames = Self.frames(
            of: items,
            in: bounds,
            bodyInset: bodyInset,
            keepsSideRowsBelowTop: keepsSideRowsBelowTop
        )
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    /// Each item's frame: items grouped into rows by anchor, in first-appearance order, each row
    /// placed against the chrome and laid out within its own frame.
    static func frames(
        of items: [NookCompanionRowGeometry.Item],
        in bounds: CGRect,
        bodyInset: CGFloat,
        keepsSideRowsBelowTop: Bool
    ) -> [CGRect] {
        var frames = [CGRect](repeating: .zero, count: items.count)
        for row in rows(of: items) {
            let rowItems = row.indices.map { items[$0] }
            let rowFrame = frame(
                ofRowSized: NookCompanionRowGeometry.size(of: rowItems, edge: row.anchor.edge),
                anchor: row.anchor,
                in: bounds,
                bodyInset: bodyInset,
                keepsSideRowsBelowTop: keepsSideRowsBelowTop
            )
            let rowFrames = NookCompanionRowGeometry.frames(of: rowItems, anchor: row.anchor, in: rowFrame)
            for (index, frame) in zip(row.indices, rowFrames) {
                frames[index] = frame
            }
        }
        return frames
    }

    /// The anchors in first-appearance order, each with the indices of its items in order.
    static func rows(
        of items: [NookCompanionRowGeometry.Item]
    ) -> [(anchor: NookCompanionAnchor, indices: [Int])] {
        var rows: [(anchor: NookCompanionAnchor, indices: [Int])] = []
        for (index, item) in items.enumerated() {
            if let row = rows.firstIndex(where: { $0.anchor == item.anchor }) {
                rows[row].indices.append(index)
            } else {
                rows.append((item.anchor, [index]))
            }
        }
        return rows
    }

    /// Where a row of `size` sits against the chrome.
    static func frame(
        ofRowSized size: CGSize,
        anchor: NookCompanionAnchor,
        in bounds: CGRect,
        bodyInset: CGFloat,
        keepsSideRowsBelowTop: Bool
    ) -> CGRect {
        let placement = placement(for: anchor, in: bounds, bodyInset: bodyInset)
        var origin = CGPoint(
            x: placement.point.x - placement.anchor.x * size.width,
            y: placement.point.y - placement.anchor.y * size.height
        )
        if keepsSideRowsBelowTop, anchor.edge != .below {
            origin.y = max(origin.y, bounds.minY)
        }
        return CGRect(origin: origin, size: size)
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

/// The geometry of one row of companions.
///
/// Every companion arrives already padded toward the chrome by its own `spacing` (see
/// ``NookCompanionItemView``), so a side row simply abuts its items and a `.below` row adds
/// each item's gap between neighbours. Every shown companion is given the row's full height
/// and places its surface across it by its row alignment, so a short companion beside a tall
/// one still reaches the chrome with its hover region.
///
/// A `.below` row hangs every surface from one drop, the largest spacing among its shown
/// companions, so surfaces in the row line up whatever spacing each one asks for. A companion
/// with less spacing starts that much lower, which keeps its surface level with the rest.
///
/// Only shown companions take up room; a hidden one waits folded against the chrome edge, so
/// showing it grows it out of the chrome and hiding it folds it back in.
enum NookCompanionRowGeometry {
    struct Item: Equatable {
        var anchor: NookCompanionAnchor = .below
        var size: CGSize
        var spacing: CGFloat
        var isPresented: Bool
        /// The gap to the item before it in a `.below` row. `nil` uses `spacing`.
        var gap: CGFloat? = nil
        /// Where the item's surface sits across its row.
        var rowAlignment: NookCompanionAnchor.Alignment = .center

        var effectiveGap: CGFloat { gap ?? spacing }
    }

    /// How far a `.below` row hangs its surfaces under the chrome: the largest spacing among its
    /// shown items.
    static func drop(of items: [Item]) -> CGFloat {
        items.filter(\.isPresented).map(\.spacing).max() ?? 0
    }

    static func size(of items: [Item], edge: NookCompanionAnchor.Edge) -> CGSize {
        let shown = items.filter(\.isPresented)
        guard !shown.isEmpty else { return .zero }
        let widths = shown.map(\.size.width).reduce(0, +)
        switch edge {
            case .below:
                // Each item's height holds its own spacing; the row holds the shared drop and
                // the tallest surface under it. Every later item's gap separates it from the
                // item before it.
                let drop = drop(of: items)
                let surface = shown.map { $0.size.height - $0.spacing }.max() ?? 0
                let gaps = shown.dropFirst().map(\.effectiveGap).reduce(0, +)
                return CGSize(width: widths + gaps, height: drop + surface)
            case .leading, .trailing:
                return CGSize(width: widths, height: shown.map(\.size.height).max() ?? 0)
        }
    }

    /// Each item's frame. A shown item spans the row's height at its own width, less any drop it
    /// is short of; a hidden one keeps its own size at its folded position.
    static func frames(of items: [Item], anchor: NookCompanionAnchor, in bounds: CGRect) -> [CGRect] {
        var frames: [CGRect] = []
        let drop = anchor.edge == .below ? drop(of: items) : 0
        // A leading row grows leftward from the chrome, so its cursor starts at the edge
        // nearest the chrome and walks away from it.
        var cursor = anchor.edge == .leading ? bounds.maxX : bounds.minX
        var placedAny = false
        for item in items {
            guard item.isPresented else {
                frames.append(foldedFrame(of: item, anchor: anchor, in: bounds))
                continue
            }
            switch anchor.edge {
                case .below:
                    if placedAny { cursor += item.effectiveGap }
                    let lowered = max(drop - item.spacing, 0)
                    frames.append(
                        CGRect(
                            x: cursor,
                            y: bounds.minY + lowered,
                            width: item.size.width,
                            height: bounds.height - lowered
                        )
                    )
                    cursor += item.size.width
                case .trailing:
                    frames.append(CGRect(x: cursor, y: bounds.minY, width: item.size.width, height: bounds.height))
                    cursor += item.size.width
                case .leading:
                    cursor -= item.size.width
                    frames.append(CGRect(x: cursor, y: bounds.minY, width: item.size.width, height: bounds.height))
            }
            placedAny = true
        }
        return frames
    }

    /// Where a hidden companion waits: flush against the chrome edge its row hangs from, and
    /// across a side row where its row alignment would put it.
    static func foldedFrame(of item: Item, anchor: NookCompanionAnchor, in bounds: CGRect) -> CGRect {
        let size = item.size
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
                let y = crossAxisY(height: size.height, alignment: item.rowAlignment, in: bounds)
                return CGRect(origin: CGPoint(x: bounds.maxX - size.width, y: y), size: size)
            case .trailing:
                let y = crossAxisY(height: size.height, alignment: item.rowAlignment, in: bounds)
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

extension NookCompanionAnchor.Edge {
    /// The side of a companion that faces the chrome - the point it folds toward while
    /// hidden.
    var foldAnchor: UnitPoint {
        towardChrome
    }

    /// The side of a companion's cell that the gap to the chrome is on.
    var chromeSide: SwiftUI.Edge.Set {
        switch self {
            case .below: .top
            case .leading: .trailing
            case .trailing: .leading
        }
    }
}

extension NookCompanionAnchor.Alignment {
    /// Where a surface sits across a row with this alignment.
    var rowPosition: Alignment {
        switch self {
            case .start: .top
            case .center: .center
            case .end: .bottom
        }
    }
}

/// One companion surface: the host content drawn by its style, with the accessibility
/// identity, the hover bridge, and the presence effect for states it is not shown in.
struct NookCompanionItemView: View {
    let surface: NookCompanionSurface
    let chromeState: NookState
    /// The backdrop after ``NookCompanionBackdrop/resolved(inheriting:)``; `nil` paints nothing.
    let backdrop: NookBackdrop?
    /// The chrome's own backdrop, published to the content.
    let chromeBackdrop: NookBackdrop
    /// The tallest the surface may be: the chrome's height for a companion beside it, `nil` below
    /// it. The companion's size is fitted to it.
    let heightLimit: CGFloat?
    let reduceMotion: Bool
    /// The chrome's compact<->expanded animation, reused for content-driven show and hide
    /// so a companion appearing on its own moves like one appearing with the chrome, unless
    /// its presence sets a curve of its own.
    let presenceAnimation: Animation
    let onHover: (Bool) -> Void
    let onVisibilityRestriction: (NookCompanionVisibility?) -> Void
    let onExtent: (CGFloat) -> Void

    @State private var restriction: NookCompanionVisibility?
    @State private var hasReceivedRestriction = false
    @State private var isHovered = false

    var isPresented: Bool {
        surface.visibility.intersection(restriction ?? .both).includes(chromeState)
    }

    /// The size the surface and its content use: the companion's own, fitted to ``heightLimit``.
    var size: NookCompanionSize {
        heightLimit.map { surface.size.fitting(height: $0) } ?? surface.size
    }

    var body: some View {
        let isPresented = isPresented
        cell(surfaceBody(isPresented: isPresented))
            .onHover(perform: onHover)
            .allowsHitTesting(isPresented)
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }, action: onExtent)
            .modifier(
                NookCompanionPresenceModifier(
                    presence: surface.presence,
                    isPresented: isPresented,
                    edge: surface.anchor.edge,
                    reduceMotion: reduceMotion
                )
            )
            // A show or hide that animates runs on the presence's own curve, if it has one. One
            // that does not animate, such as the first state as the panel is built, stays
            // instant.
            .transaction(value: isPresented) { transaction in
                if transaction.animation != nil, let animation = surface.presence.animation {
                    transaction.animation = animation
                }
            }
            .onChange(of: isPresented) { _, shown in
                // SwiftUI reports no hover exit for a view that stops being hit-testable.
                if !shown { isHovered = false }
            }
            .layoutValue(key: NookCompanionAnchorKey.self, value: surface.anchor)
            .layoutValue(key: NookCompanionPresentedKey.self, value: isPresented)
            .layoutValue(key: NookCompanionSpacingKey.self, value: surface.spacing)
            .layoutValue(key: NookCompanionGapKey.self, value: surface.gap)
            .layoutValue(key: NookCompanionRowAlignmentKey.self, value: surface.effectiveRowAlignment)
    }

    /// The visible companion: content inside its style, as one accessibility group.
    private func surfaceBody(isPresented: Bool) -> some View {
        let size = size
        let configuration = NookCompanionStyleConfiguration(
            content: sized(surface.content.fixedSize()),
            shape: surface.shape,
            backdrop: backdrop,
            edge: surface.anchor.edge,
            size: size,
            isHovered: isHovered,
            isPresented: isPresented
        )
        return surface.style.makeBody(configuration: configuration)
            .fixedSize()
            .environment(\.nookCompanionIsPresented, isPresented)
            .environment(\.nookCompanionIsHovered, isHovered)
            .environment(\.nookCompanionSize, size)
            .environment(\.nookChromeBackdrop, chromeBackdrop)
            .onPreferenceChange(NookCompanionVisibilityPreferenceKey.self) { value in
                receiveRestriction(value)
            }
            // Consume the restriction here so it cannot leak up and hide some other surface.
            .transformPreference(NookCompanionVisibilityPreferenceKey.self) { $0 = nil }
            .contentShape(surface.shape.outline)
            .onHover { hovering in isHovered = hovering }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(surface.accessibilityIdentifier)
            .modifier(NookCompanionAccessibilityLabel(label: surface.accessibilityLabel))
            .accessibilityHidden(!isPresented)
    }

    /// The cell the row lays out: the surface placed across the row by its row alignment,
    /// padded toward the chrome by its spacing, over a hover bridge.
    ///
    /// The bridge is a transparent fill of the whole cell with a content shape of its own, so
    /// the pointer crossing the gap to the chrome, or the space beside a surface shorter than
    /// its row, never leaves the companion's hover region. It draws nothing, so clicks on it
    /// still fall through to whatever is behind the panel. It sits behind the surface rather
    /// than around it: a content shape on an ancestor also becomes the accessibility frame of
    /// the group inside it, which would stretch VoiceOver's highlight across the gap.
    private func cell(_ body: some View) -> some View {
        body
            .frame(maxHeight: .infinity, alignment: surface.effectiveRowAlignment.rowPosition)
            .padding(surface.anchor.edge.chromeSide, surface.spacing)
            .background {
                Color.clear.contentShape(Rectangle())
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
        withAnimation(surface.presence.animation ?? presenceAnimation) { restriction = value }
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
