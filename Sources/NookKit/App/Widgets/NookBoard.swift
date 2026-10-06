// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// A board: a module whose home is a grid of widgets from every loaded module.
///
/// Register one with ``NookHostConfiguration/registerBoard(_:)``. It is a module like any other:
/// it shows in the module switcher, can have a hotkey, and has its own Settings, where the
/// person reorders, resizes, shows, and hides its widgets. Several boards ("Work", "Home") can
/// show different widgets.
///
/// ```swift
/// var board = NookBoardConfiguration(id: "board", displayName: "Today")
/// board.defaultLayout = [
///     NookWidgetPlacement(moduleID: "music", widgetID: "now-playing", size: .large),
///     NookWidgetPlacement(moduleID: "calendar", widgetID: "next"),
/// ]
/// host.registerBoard(board)
/// ```
///
/// Widgets come from modules that are loaded. A module that should always be on the board is
/// ``NookModuleDescriptor/BackgroundPolicy/stayResident`` with
/// ``NookModuleDescriptor/loadsAtLaunch``; a board never loads or unloads other modules.
///
/// The order is the person's saved layout, then the host's ``defaultLayout``, then every other
/// widget the board admits, by module registration order. A saved widget whose module is not
/// loaded keeps its place and comes back to it.
public struct NookBoardConfiguration: Sendable {
    /// Which modules' widgets a board shows.
    public enum Admission: Equatable, Sendable {
        /// Every module's. The default.
        case all
        /// Only these modules'.
        case modules([String])
    }

    /// The board's module id.
    public var id: String
    /// The board's name in the switcher and its top bar.
    public var displayName: String
    /// The board's SF Symbol in the switcher.
    public var icon: String
    /// A hotkey that switches to the board, or `nil` for none.
    public var hotkey: NookHotkey?
    /// Columns on the grid. 4 by default.
    public var columns: Int
    /// The expanded panel's width while the board shows, or `nil` for the standard width.
    public var width: CGFloat?
    /// The host's starting order and sizes. Empty by default: every widget at its preferred
    /// size, by module registration order.
    public var defaultLayout: [NookWidgetPlacement]
    /// Which modules' widgets the board shows. ``Admission/all`` by default.
    public var admits: Admission
    /// `true` to keep the host's layout as it is: the board's Settings leave out the editor.
    public var isLayoutLocked: Bool
    /// Changes the board's configuration before it is used: its theme, labels, top bar, or
    /// anything else a module's configuration holds.
    public var customize: (@Sendable @MainActor (inout NookConfiguration) -> Void)?

    public init(
        id: String,
        displayName: String,
        icon: String = "square.grid.2x2",
        hotkey: NookHotkey? = nil,
        columns: Int = 4,
        width: CGFloat? = nil,
        defaultLayout: [NookWidgetPlacement] = [],
        admits: Admission = .all,
        isLayoutLocked: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.hotkey = hotkey
        self.columns = max(columns, 1)
        self.width = width
        self.defaultLayout = defaultLayout
        self.admits = admits
        self.isLayoutLocked = isLayoutLocked
    }

    /// Whether the board shows widgets of the module `moduleID`.
    func admits(moduleID: String) -> Bool {
        guard moduleID != id else { return false }
        switch admits {
            case .all: return true
            case .modules(let ids): return ids.contains(moduleID)
        }
    }
}

/// One widget's place on a board: which widget, at what size, and whether it shows.
public struct NookWidgetPlacement: Codable, Hashable, Sendable {
    /// The module the widget belongs to.
    public var moduleID: String
    /// The widget's id within its module.
    public var widgetID: String
    /// The size it shows at, or `nil` for the widget's preferred size. A size the widget does
    /// not offer reads as its preferred size.
    public var size: NookWidgetSize?
    /// `true` to keep the widget off the board while it keeps its place in the order.
    public var isHidden: Bool

    public init(moduleID: String, widgetID: String, size: NookWidgetSize? = nil, isHidden: Bool = false) {
        self.moduleID = moduleID
        self.widgetID = widgetID
        self.size = size
        self.isHidden = isHidden
    }

    /// "module id/widget id": what identifies the widget across modules.
    public var key: String { Self.key(moduleID: moduleID, widgetID: widgetID) }

    static func key(moduleID: String, widgetID: String) -> String {
        "\(moduleID)/\(widgetID)"
    }
}

extension NookHostConfiguration {
    /// Registers a board: a module whose home is a grid of the loaded modules' widgets. See
    /// ``NookBoardConfiguration``.
    public mutating func registerBoard(_ board: NookBoardConfiguration) {
        register(
            NookModuleDescriptor(id: board.id, displayName: board.displayName, icon: board.icon, hotkey: board.hotkey)
        ) { context in
            NookBoardModule(board: board, context: context)
        }
    }
}

// MARK: - The board module

/// The module behind a board: its home is the grid, its Settings the editor.
@MainActor
final class NookBoardModule: NookModule {
    let descriptor: NookModuleDescriptor
    let board: NookBoardConfiguration
    let store: NookBoardLayoutStore
    private let catalog: NookWidgetCatalog

    init(board: NookBoardConfiguration, context: NookModuleContext) {
        self.descriptor = context.descriptor
        self.board = board
        self.catalog = context.services.resolve(NookWidgetCatalogKey.self)
        self.store = NookBoardLayoutStore(board: board)
    }

    func makeConfiguration() -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.expandedWidth = board.width
        board.customize?(&configuration)
        let board = board
        let catalog = catalog
        let store = store
        configuration.setHome {
            NookBoardHome(board: board, catalog: catalog, store: store)
        }
        if !board.isLayoutLocked {
            configuration.addSettingsSection(
                id: "opennook.board.widgets",
                title: configuration.labels.widgets.sectionTitle
            ) {
                NookBoardEditor(board: board, catalog: catalog, store: store)
            }
        }
        return configuration
    }
}

// MARK: - Layout

/// A board's layout: the person's saved one, or the host's until they change something.
/// Saved in the host's preferences under `opennook.board.<id>.layout.v1`.
@MainActor
final class NookBoardLayoutStore: ObservableObject {
    /// A widget on the board, with its placement.
    struct Arranged: Identifiable {
        let placement: NookWidgetPlacement
        let entry: NookWidgetCatalog.Entry

        var id: String { placement.key }
        /// The size it shows at: the placement's, when the widget offers it.
        var size: NookWidgetSize { entry.widget.supportedSize(placement.size) }
    }

    let board: NookBoardConfiguration
    /// The person's layout, or `nil` while it is the host's.
    @Published private(set) var saved: [NookWidgetPlacement]?

    init(board: NookBoardConfiguration) {
        self.board = board
        self.saved = Self.load(key: Self.storageKey(board.id))
    }

    static func storageKey(_ boardID: String) -> String {
        "opennook.board.\(boardID).layout.v1"
    }

    /// Every placement in order: the saved layout or the host's, then each admitted widget in
    /// `entries` that neither names. Placements of widgets that are not loaded stay in place.
    func placements(for entries: [NookWidgetCatalog.Entry]) -> [NookWidgetPlacement] {
        var result: [NookWidgetPlacement] = []
        var seen = Set<String>()
        for placement in saved ?? board.defaultLayout where seen.insert(placement.key).inserted {
            result.append(placement)
        }
        for entry in entries where board.admits(moduleID: entry.moduleID) && !seen.contains(entry.id) {
            seen.insert(entry.id)
            result.append(NookWidgetPlacement(moduleID: entry.moduleID, widgetID: entry.widget.id))
        }
        return result
    }

    /// The admitted widgets in `entries` in board order, hidden ones included.
    func arranged(_ entries: [NookWidgetCatalog.Entry]) -> [Arranged] {
        let available = Dictionary(
            entries.filter { board.admits(moduleID: $0.moduleID) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return placements(for: entries).compactMap { placement in
            available[placement.key].map { Arranged(placement: placement, entry: $0) }
        }
    }

    /// The widgets the board shows: ``arranged(_:)`` without the hidden ones.
    func visible(_ entries: [NookWidgetCatalog.Entry]) -> [Arranged] {
        arranged(entries).filter { !$0.placement.isHidden }
    }

    /// Moves the widget `key` to where `target` is now, among the widgets in `entries`.
    func move(_ key: String, to target: String, in entries: [NookWidgetCatalog.Entry]) {
        var order = arranged(entries).map(\.id)
        guard key != target, let from = order.firstIndex(of: key), let to = order.firstIndex(of: target) else {
            return
        }
        order.remove(at: from)
        order.insert(key, at: to)
        reorder(order, in: entries)
    }

    /// Moves the widget `key` `offset` places later (or earlier, for a negative offset).
    func move(_ key: String, by offset: Int, in entries: [NookWidgetCatalog.Entry]) {
        var order = arranged(entries).map(\.id)
        guard let from = order.firstIndex(of: key) else { return }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return }
        order.remove(at: from)
        order.insert(key, at: to)
        reorder(order, in: entries)
    }

    /// Shows or hides the widget `key`.
    func setHidden(_ hidden: Bool, for key: String, in entries: [NookWidgetCatalog.Entry]) {
        update(key, in: entries) { $0.isHidden = hidden }
    }

    /// Shows the widget `key` at `size`.
    func setSize(_ size: NookWidgetSize, for key: String, in entries: [NookWidgetCatalog.Entry]) {
        update(key, in: entries) { $0.size = size }
    }

    /// Back to the host's layout.
    func reset() {
        saved = nil
        NookPreferenceStorage.defaults.removeObject(forKey: Self.storageKey(board.id))
    }

    /// Puts the available widgets in `order` into the slots they hold now, so widgets that are
    /// not loaded keep their places.
    private func reorder(_ order: [String], in entries: [NookWidgetCatalog.Entry]) {
        let available = Set(order)
        var next = order.makeIterator()
        let placements = placements(for: entries)
        let byKey = Dictionary(placements.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        save(
            placements.map { placement in
                guard available.contains(placement.key), let key = next.next(), let moved = byKey[key] else {
                    return placement
                }
                return moved
            }
        )
    }

    private func update(
        _ key: String,
        in entries: [NookWidgetCatalog.Entry],
        _ change: (inout NookWidgetPlacement) -> Void
    ) {
        var placements = placements(for: entries)
        guard let index = placements.firstIndex(where: { $0.key == key }) else { return }
        change(&placements[index])
        save(placements)
    }

    private func save(_ placements: [NookWidgetPlacement]) {
        saved = placements
        if let data = try? JSONEncoder().encode(placements) {
            NookPreferenceStorage.defaults.set(data, forKey: Self.storageKey(board.id))
        }
    }

    private static func load(key: String) -> [NookWidgetPlacement]? {
        guard let data = NookPreferenceStorage.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([NookWidgetPlacement].self, from: data)
    }
}

// MARK: - Views

/// Switches the host to a module, for widgets whose action opens their module.
private struct NookSwitchModuleKey: EnvironmentKey {
    static let defaultValue: (@Sendable @MainActor (String) -> Void)? = nil
}

extension EnvironmentValues {
    /// Switches to a module by id. Set by the expanded router; `nil` outside the chrome.
    var nookSwitchModule: (@Sendable @MainActor (String) -> Void)? {
        get { self[NookSwitchModuleKey.self] }
        set { self[NookSwitchModuleKey.self] = newValue }
    }
}

/// A board's home: its visible widgets on the grid, scrolling past `widget.board.maxHeight`.
struct NookBoardHome: View, Sendable {
    let board: NookBoardConfiguration
    @ObservedObject var catalog: NookWidgetCatalog
    @ObservedObject var store: NookBoardLayoutStore

    @Environment(\.nookThemeTokens) private var tokens
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeLabels) private var labels
    @Environment(\.nookSwitchModule) private var switchModule

    var body: some View {
        let items = Self.items(store.visible(catalog.entries), switchModule: switchModule)
        if items.isEmpty {
            Text(labels.widgets.emptyBoard)
                .font(typography.settingsCaption)
                .foregroundStyle(theme.tertiaryLabel)
                .frame(maxWidth: .infinity, minHeight: tokens[.widgetRowHeight])
        } else {
            let grid = NookWidgetGrid(items: items, columns: board.columns, cardStyle: .card)
            let height = NookWidgetGrid.height(of: items.map(\.size), columns: board.columns, tokens: tokens)
            let maxHeight = tokens[.widgetBoardMaxHeight]
            if height > maxHeight {
                ScrollView(.vertical) { grid }
                    .scrollIndicators(.never)
                    .frame(height: maxHeight)
            } else {
                grid
            }
        }
    }

    /// The grid's items for `arranged`: each widget in its module's scope, and clickable when
    /// its action goes somewhere.
    static func items(
        _ arranged: [NookBoardLayoutStore.Arranged],
        switchModule: (@Sendable @MainActor (String) -> Void)?
    ) -> [NookWidgetGrid.Item] {
        arranged.map { arranged in
            let entry = arranged.entry
            let moduleID = entry.moduleID
            let open: (@Sendable @MainActor () -> Void)? =
                switch entry.widget.action {
                    case .none: nil
                    case .openModule: switchModule.map { switchTo in { switchTo(moduleID) } }
                    case .perform(let action): { action() }
                }
            let services = entry.services
            return NookWidgetGrid.Item(
                id: arranged.id,
                widget: entry.widget,
                size: arranged.size,
                open: open,
                scope: { AnyView($0.modifier(NookModuleScope(moduleID: moduleID, services: services))) }
            )
        }
    }
}

/// A board's editor in Settings: every widget it can show, in order, to drag, resize, show, or
/// hide, with each widget's own settings under it.
struct NookBoardEditor: View, Sendable {
    let board: NookBoardConfiguration
    @ObservedObject var catalog: NookWidgetCatalog
    @ObservedObject var store: NookBoardLayoutStore

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookChromeLabels) private var labels

    var body: some View {
        let arranged = store.arranged(catalog.entries)
        VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
            Text(labels.widgets.editorCaption)
                .font(typography.settingsCaption)
                .foregroundStyle(theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            if arranged.isEmpty {
                Text(labels.widgets.emptyBoard)
                    .font(typography.settingsCaption)
                    .foregroundStyle(theme.secondaryLabel)
            }
            ForEach(arranged) { item in
                row(item)
            }
            Button(labels.widgets.resetLayout) { store.reset() }
                .controlSize(.small)
                .disabled(store.saved == nil)
        }
        .padding(.vertical, metrics.settingsRowVerticalPadding)
    }

    private func row(_ item: NookBoardLayoutStore.Arranged) -> some View {
        let widget = item.entry.widget
        let entries = catalog.entries
        return VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
            HStack(spacing: metrics.settingsGroupSpacing) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(theme.tertiaryLabel)
                    .accessibilityHidden(true)
                Image(systemName: widget.symbol ?? "square.grid.2x2")
                    .font(typography.settingsEmphasis)
                    .foregroundStyle(theme.headerInactiveIcon)
                    .frame(width: metrics.settingsIconWidth)
                    .accessibilityHidden(true)
                Text(widget.title)
                    .font(typography.settingsRowTitle)
                    .foregroundStyle(theme.primaryLabel.opacity(item.placement.isHidden ? 0.5 : 1))
                Spacer(minLength: 0)
                if widget.sizes.count > 1 {
                    Picker(
                        labels.widgets.sizeTitle,
                        selection: Binding(
                            get: { item.size },
                            set: { store.setSize($0, for: item.id, in: entries) }
                        )
                    ) {
                        ForEach(widget.sizes, id: \.self) { size in
                            Text(size.name).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel(labels.widgets.sizeTitle)
                }
                Toggle(
                    labels.widgets.showWidget(widget.title),
                    isOn: Binding(
                        get: { !item.placement.isHidden },
                        set: { store.setHidden(!$0, for: item.id, in: entries) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .contentShape(Rectangle())
            .draggable(item.id)
            .dropDestination(for: String.self) { keys, _ in
                guard let key = keys.first else { return false }
                withAnimation(.default) { store.move(key, to: item.id, in: entries) }
                return true
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: labels.widgets.moveUp) { store.move(item.id, by: -1, in: entries) }
            .accessibilityAction(named: labels.widgets.moveDown) { store.move(item.id, by: 1, in: entries) }

            if let settings = widget.settings, !item.placement.isHidden {
                settings()
                    .modifier(NookModuleScope(moduleID: item.entry.moduleID, services: item.entry.services))
                    .padding(.leading, metrics.settingsIconWidth + metrics.settingsGroupSpacing * 2 + 12)
            }
        }
    }
}
