// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Widgets laid out on a column grid, each in a card, in the order given.
///
/// Use it in a module's home to compose the module's own widgets. A board
/// (``NookBoardConfiguration``) uses the same grid for widgets from every loaded module.
///
/// ```swift
/// configuration.setHome {
///     NookWidgetGrid(widgets, sizes: ["calendar": .large])
/// }
/// ```
///
/// The grid is as wide as the space it is given, split into `columns` equal columns, and as
/// tall as its rows: `widget.rowHeight` each, `widget.gap` apart. Widgets go in reading
/// order; one that does not fit beside the last starts the next row, and nothing moves back to
/// fill a gap. Cards take their corner radius, padding, and colors from the `widget.card.*`
/// tokens. With a theme's `motion.stagger` above 0, the cards cascade in as the nook opens.
public struct NookWidgetGrid: View, Sendable {
    /// How each widget is framed.
    public enum CardStyle: Sendable {
        /// A rounded card with a fill and a hairline, from the `widget.card.*` tokens. The default.
        case card
        /// No card: widgets draw straight on the chrome, still on the grid.
        case plain
    }

    /// One widget on the grid, at the size it is shown, with what a click does.
    struct Item: Identifiable, Sendable {
        var id: String
        var widget: NookWidget
        var size: NookWidgetSize
        /// What a click on the widget does, or `nil` for nothing.
        var open: (@Sendable @MainActor () -> Void)?
        /// Gives the widget the scope of the module it came from.
        var scope: (@Sendable @MainActor (AnyView) -> AnyView)?
    }

    let items: [Item]
    let columns: Int
    let cardStyle: CardStyle

    @Environment(\.nookThemeTokens) private var tokens

    /// A grid of `widgets` in order, each at the size `sizes` gives for its id when the widget
    /// offers it, or its preferred size otherwise.
    public init(
        _ widgets: [NookWidget],
        sizes: [String: NookWidgetSize] = [:],
        columns: Int = 4,
        cardStyle: CardStyle = .card
    ) {
        self.items = widgets.map { widget in
            let perform: (@Sendable @MainActor () -> Void)? =
                switch widget.action {
                    case .perform(let action): { action() }
                    // A module's own grid is already the module on screen.
                    case .none, .openModule: nil
                }
            return Item(id: widget.id, widget: widget, size: widget.supportedSize(sizes[widget.id]), open: perform)
        }
        self.columns = max(columns, 1)
        self.cardStyle = cardStyle
    }

    init(items: [Item], columns: Int, cardStyle: CardStyle) {
        self.items = items
        self.columns = max(columns, 1)
        self.cardStyle = cardStyle
    }

    public var body: some View {
        NookWidgetGridLayout(columns: columns, rowHeight: tokens[.widgetRowHeight], gap: tokens[.widgetGap]) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NookWidgetCell(item: item, cardStyle: cardStyle)
                    .layoutValue(key: NookWidgetSpanKey.self, value: item.size)
                    .nookStaggered(index: index)
            }
        }
        .animation(tokens[.widgetLayout], value: items.map(\.id))
        .animation(tokens[.widgetLayout], value: items.map(\.size))
    }

    /// The grid's height for `items` on `columns` columns, from the resolved `tokens`.
    static func height(of sizes: [NookWidgetSize], columns: Int, tokens: NookResolvedTokens) -> CGFloat {
        let rows = NookWidgetLayout.place(sizes, columns: columns).rows
        return NookWidgetLayout.height(rows: rows, rowHeight: tokens[.widgetRowHeight], gap: tokens[.widgetGap])
    }
}

/// One widget in its card, clickable when it has somewhere to go.
struct NookWidgetCell: View {
    let item: NookWidgetGrid.Item
    let cardStyle: NookWidgetGrid.CardStyle

    @Environment(\.nookThemeTokens) private var tokens
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeColors) private var colors

    var body: some View {
        let content = item.widget.content(item.size)
        let scoped = item.scope?(content) ?? content
        framed(scoped.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.widget.title)
            .accessibilityIdentifier("widget.\(item.id)")
            .modifier(NookWidgetOpenModifier(open: item.open))
    }

    @ViewBuilder
    private func framed(_ content: some View) -> some View {
        switch cardStyle {
            case .card:
                let shape = RoundedRectangle(cornerRadius: tokens[.widgetCardCornerRadius], style: .continuous)
                content
                    .padding(tokens[.widgetCardPadding])
                    .background(shape.fill(colors.widgetCardBackground ?? theme.subtleFill))
                    .overlay(shape.strokeBorder(colors.widgetCardBorder ?? theme.subtleStroke, lineWidth: 0.5))
                    .clipShape(shape)
                    .contentShape(shape)
            case .plain:
                content
                    .contentShape(Rectangle())
        }
    }
}

/// Makes a widget clickable when it has an action. Controls inside the widget keep their own
/// clicks.
private struct NookWidgetOpenModifier: ViewModifier {
    let open: (@Sendable @MainActor () -> Void)?

    func body(content: Content) -> some View {
        if let open {
            content
                .onTapGesture { open() }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
        } else {
            content
        }
    }
}
