// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// A small view a module offers for boards and grids, next to its home: the way an app on a
/// phone has both its app and its widgets.
///
/// A module adds its widgets to its configuration with
/// ``NookConfiguration/addWidget(_:)``, or keeps a changing set in a ``NookWidgetSource``. A
/// board (``NookBoardConfiguration``) shows the widgets of every loaded module together, and a
/// module's own home can lay out its widgets with ``NookWidgetGrid``.
///
/// ```swift
/// configuration.addWidget(
///     NookWidget(id: "now-playing", title: "Now playing", symbol: "music.note", sizes: [.medium, .large]) { size in
///         NowPlayingWidget(player: player, roomy: size == .large)
///     }
/// )
/// ```
///
/// The content reads the module's own observable state, so it updates in place. It draws
/// content only: the grid draws the card around it, from the theme's `widget.*` tokens.
public struct NookWidget: Identifiable, Sendable {
    /// What happens when the person clicks the widget.
    public enum Action: Sendable {
        /// Nothing beyond the widget's own controls. The default.
        case none
        /// Switches to the module the widget belongs to.
        case openModule
        /// Runs `perform`.
        case perform(@Sendable @MainActor () -> Void)
    }

    /// Identifies the widget within its module. Boards save layouts by module id and this id.
    public var id: String
    /// The widget's name in the board editor, and what VoiceOver says for it.
    public var title: String
    /// An SF Symbol for the board editor, or `nil` for none.
    public var symbol: String?
    /// The sizes the widget can be shown at, the preferred one first. Never empty: an empty
    /// list reads as ``NookWidgetSize/small``.
    public var sizes: [NookWidgetSize] {
        didSet { if sizes.isEmpty { sizes = [.small] } }
    }
    /// What a click does. ``Action/none`` by default.
    public var action: Action
    /// The widget's view at a size. A widget that offers more than one size can lay itself
    /// out differently for each.
    public var content: @Sendable @MainActor (NookWidgetSize) -> AnyView
    /// The widget's own settings, shown under its row in the board editor, or `nil` for none.
    public var settings: (@Sendable @MainActor () -> AnyView)?

    public init<Content: View & Sendable>(
        id: String,
        title: String,
        symbol: String? = nil,
        sizes: [NookWidgetSize] = [.small],
        action: Action = .none,
        @ViewBuilder content: @escaping @Sendable @MainActor (NookWidgetSize) -> Content
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.sizes = sizes.isEmpty ? [.small] : sizes
        self.action = action
        self.content = { AnyView(content($0)) }
    }

    /// The size the widget is shown at until someone picks another: the first of ``sizes``.
    public var preferredSize: NookWidgetSize {
        sizes.first ?? .small
    }

    /// `size` when the widget offers it, otherwise its preferred size.
    public func supportedSize(_ size: NookWidgetSize?) -> NookWidgetSize {
        guard let size, sizes.contains(size) else { return preferredSize }
        return size
    }

    /// Sets the widget's own settings. See ``settings``.
    public mutating func setSettings<Content: View & Sendable>(
        @ViewBuilder _ content: @escaping @Sendable @MainActor () -> Content
    ) {
        settings = { AnyView(content()) }
    }
}

/// How much of a widget grid a widget takes: a number of columns and a number of rows.
///
/// The presets follow the sizes people know from widgets elsewhere. A grid has four columns
/// by default (``NookWidgetGrid``), so ``wide`` and ``medium`` differ only in wider grids.
/// Any other span works too:
///
/// ```swift
/// NookWidgetSize(columns: 3, rows: 1)
/// ```
public struct NookWidgetSize: Hashable, Codable, Sendable {
    /// Columns the widget spans, at least 1. Wider than the grid means the whole row.
    public var columns: Int
    /// Rows the widget spans, at least 1.
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
    }

    /// One column, one row.
    public static let small = NookWidgetSize(columns: 1, rows: 1)
    /// Two columns, one row.
    public static let medium = NookWidgetSize(columns: 2, rows: 1)
    /// Two columns, two rows.
    public static let large = NookWidgetSize(columns: 2, rows: 2)
    /// The whole row, one row tall.
    public static let wide = NookWidgetSize(columns: .max, rows: 1)

    /// A short name for the editor: the preset's, or "columns x rows".
    public var name: String {
        switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .wide: "Wide"
            default: "\(columns) x \(rows)"
        }
    }
}
