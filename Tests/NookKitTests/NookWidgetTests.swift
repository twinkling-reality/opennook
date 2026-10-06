// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// Widgets and boards: where the grid puts widgets, what each module offers, how a board orders,
/// saves, and edits its layout, and the scope each widget draws in.
@MainActor
final class NookWidgetTests: XCTestCase {
    private func widget(
        _ id: String,
        sizes: [NookWidgetSize] = [.small],
        action: NookWidget.Action = .none
    ) -> NookWidget {
        NookWidget(id: id, title: id.capitalized, sizes: sizes, action: action) { _ in Text(id) }
    }

    private func cells(_ sizes: [NookWidgetSize], columns: Int = 4) -> [NookWidgetLayout.Cell] {
        NookWidgetLayout.place(sizes, columns: columns).cells
    }

    // MARK: - Layout

    func testSmallWidgetsFillARowThenWrap() {
        let placed = NookWidgetLayout.place(Array(repeating: .small, count: 5), columns: 4)
        XCTAssertEqual(placed.cells.map(\.column), [0, 1, 2, 3, 0])
        XCTAssertEqual(placed.cells.map(\.row), [0, 0, 0, 0, 1])
        XCTAssertEqual(placed.rows, 2)
    }

    func testWidgetsFlowAroundALargeOne() {
        let placed = cells([.large, .small, .small, .small, .small])
        XCTAssertEqual(placed[0], NookWidgetLayout.Cell(column: 0, row: 0, columns: 2, rows: 2))
        XCTAssertEqual(placed[1...].map { [$0.column, $0.row] }, [[2, 0], [3, 0], [2, 1], [3, 1]])
    }

    func testNothingMovesBackToFillAGap() {
        let placed = cells([.small, .wide, .small])
        XCTAssertEqual(placed[1], NookWidgetLayout.Cell(column: 0, row: 1, columns: 4, rows: 1))
        XCTAssertEqual([placed[2].column, placed[2].row], [0, 2], "the last widget stays after the wide one")
    }

    func testSpansAreClampedToTheGrid() {
        let placed = cells([.medium, .wide, NookWidgetSize(columns: 9, rows: 1)], columns: 1)
        XCTAssertEqual(placed.map(\.columns), [1, 1, 1])
        XCTAssertEqual(placed.map(\.row), [0, 1, 2])
        XCTAssertEqual(NookWidgetSize(columns: 0, rows: -2), .small)
    }

    func testHeightCountsRowsAndGaps() {
        XCTAssertEqual(NookWidgetLayout.height(rows: 3, rowHeight: 72, gap: 8), 232)
        XCTAssertEqual(NookWidgetLayout.height(rows: 0, rowHeight: 72, gap: 8), 0)
        XCTAssertEqual(
            NookWidgetGrid.height(of: [.large, .small], columns: 4, tokens: .standard),
            NookWidgetLayout.height(rows: 2, rowHeight: 72, gap: 8)
        )
    }

    /// Where a probe widget records the size it was given.
    @MainActor
    private final class Frames {
        var sizes: [String: CGSize] = [:]
    }

    private struct SizeProbe: View, Sendable {
        let id: String
        let frames: Frames

        var body: some View {
            Color.clear.onGeometryChange(for: CGSize.self, of: \.size) { frames.sizes[id] = $0 }
        }
    }

    func testTheGridGivesEachWidgetItsCell() {
        let frames = Frames()
        let widgets = ["a", "b"].map { id in
            NookWidget(id: id, title: id, sizes: [.small, .medium]) { _ in SizeProbe(id: id, frames: frames) }
        }
        let grid = NookWidgetGrid(widgets, sizes: ["b": .medium], cardStyle: .plain)
        let hosting = NSHostingView(rootView: grid.frame(width: 4 * 100 + 3 * 8))
        hosting.frame = NSRect(x: 0, y: 0, width: 4 * 100 + 3 * 8, height: 200)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(frames.sizes["a"], CGSize(width: 100, height: 72))
        XCTAssertEqual(frames.sizes["b"], CGSize(width: 208, height: 72))
    }

    // MARK: - Widgets

    func testAWidgetFallsBackToItsPreferredSize() {
        var widget = widget("w", sizes: [.medium, .large])
        XCTAssertEqual(widget.preferredSize, .medium)
        XCTAssertEqual(widget.supportedSize(.large), .large)
        XCTAssertEqual(widget.supportedSize(.small), .medium, "a size it does not offer")
        XCTAssertEqual(widget.supportedSize(nil), .medium)
        widget.sizes = []
        XCTAssertEqual(widget.sizes, [.small])
        XCTAssertEqual(NookWidgetSize.large.name, "Large")
        XCTAssertEqual(NookWidgetSize(columns: 3, rows: 1).name, "3 x 1")
    }

    func testTheWidgetTokensHaveTheirDefaults() {
        let tokens = NookResolvedTokens.standard
        XCTAssertEqual(tokens[.widgetGap], 8)
        XCTAssertEqual(tokens[.widgetRowHeight], 72)
        XCTAssertEqual(tokens[.widgetBoardMaxHeight], 320)
        XCTAssertEqual(tokens[.widgetCardCornerRadius], 16)
        XCTAssertEqual(tokens[.widgetCardPadding], 10)

        var theme = NookTheme()
        theme.radius = .large
        XCTAssertEqual(theme.resolvedTokens()[.widgetCardCornerRadius], 16 * 1.4, accuracy: 0.001)
        XCTAssertEqual(NookTheme.standard.chromeColors(in: NookThemeContext(isDark: true)).widgetCardBackground, nil)
    }

    // MARK: - Catalog

    func testTheCatalogListsModulesInRegistrationOrderAndFollowsSources() {
        let catalog = NookWidgetCatalog(moduleOrder: ["a", "b"])
        let source = NookWidgetSource([widget("live"), widget("one")])
        var b = NookConfiguration()
        b.addWidget(widget("one"))
        b.widgetSource = source
        var a = NookConfiguration()
        a.addWidget(widget("clock"))

        catalog.record(b, moduleID: "b", services: AppServices())
        catalog.record(a, moduleID: "a", services: AppServices())
        XCTAssertEqual(catalog.entries.map(\.id), ["a/clock", "b/one", "b/live"], "a repeated id is left out")

        source.remove(id: "live")
        source.set(widget("call"))
        XCTAssertEqual(catalog.entries.map(\.id), ["a/clock", "b/one", "b/call"])

        catalog.remove(moduleID: "b")
        XCTAssertEqual(catalog.entries.map(\.id), ["a/clock"])
        source.set(widget("late"))
        XCTAssertEqual(catalog.entries.map(\.id), ["a/clock"], "an unloaded module's source is no longer followed")
    }

    // MARK: - Board layout

    private func entries(_ ids: [String]) -> [NookWidgetCatalog.Entry] {
        ids.map { key in
            let parts = key.split(separator: "/").map(String.init)
            return NookWidgetCatalog.Entry(
                moduleID: parts[0],
                widget: widget(parts[1], sizes: [.small, .medium]),
                services: AppServices()
            )
        }
    }

    func testABoardOrdersSavedThenDefaultThenNew() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let board = NookBoardConfiguration(
                id: "board",
                displayName: "Board",
                defaultLayout: [NookWidgetPlacement(moduleID: "b", widgetID: "two", size: .medium)]
            )
            let store = NookBoardLayoutStore(board: board)
            let available = entries(["a/one", "b/two", "c/three"])
            XCTAssertEqual(store.visible(available).map(\.id), ["b/two", "a/one", "c/three"])
            XCTAssertEqual(store.visible(available).first?.size, .medium)

            store.move("c/three", to: "b/two", in: available)
            XCTAssertEqual(store.visible(available).map(\.id), ["c/three", "b/two", "a/one"])
            XCTAssertEqual(
                NookBoardLayoutStore(board: board).visible(available).map(\.id),
                ["c/three", "b/two", "a/one"],
                "saved"
            )

            store.reset()
            XCTAssertEqual(store.visible(available).map(\.id), ["b/two", "a/one", "c/three"])
            XCTAssertNil(NookBoardLayoutStore(board: board).saved)
        }
    }

    func testAWidgetThatIsNotLoadedKeepsItsPlace() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let board = NookBoardConfiguration(id: "board", displayName: "Board")
            let store = NookBoardLayoutStore(board: board)
            let all = entries(["a/one", "b/two", "c/three"])
            store.setHidden(false, for: "a/one", in: all)  // saves the layout as it stands

            let withoutB = entries(["a/one", "c/three"])
            XCTAssertEqual(store.visible(withoutB).map(\.id), ["a/one", "c/three"])
            store.move("c/three", to: "a/one", in: withoutB)
            XCTAssertEqual(store.placements(for: withoutB).map(\.key), ["c/three", "b/two", "a/one"])

            XCTAssertEqual(store.visible(all).map(\.id), ["c/three", "b/two", "a/one"], "b comes back in its slot")
        }
    }

    func testHidingResizingAndMovingByOffset() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let board = NookBoardConfiguration(id: "board", displayName: "Board")
            let store = NookBoardLayoutStore(board: board)
            let all = entries(["a/one", "a/two", "a/three"])

            store.setHidden(true, for: "a/two", in: all)
            XCTAssertEqual(store.visible(all).map(\.id), ["a/one", "a/three"])
            XCTAssertEqual(store.arranged(all).map(\.id), ["a/one", "a/two", "a/three"], "the editor still lists it")

            store.setSize(.medium, for: "a/one", in: all)
            XCTAssertEqual(store.visible(all).first?.size, .medium)
            store.setSize(.large, for: "a/one", in: all)
            XCTAssertEqual(store.visible(all).first?.size, .small, "a size the widget does not offer")

            store.move("a/one", by: 5, in: all)
            XCTAssertEqual(store.arranged(all).map(\.id), ["a/two", "a/three", "a/one"])
            store.move("a/one", by: -1, in: all)
            XCTAssertEqual(store.arranged(all).map(\.id), ["a/two", "a/one", "a/three"])
        }
    }

    func testABoardAdmitsOnlyTheModulesItNames() {
        var board = NookBoardConfiguration(id: "board", displayName: "Board", admits: .modules(["b"]))
        let store = NookBoardLayoutStore(board: board)
        XCTAssertEqual(store.visible(entries(["a/one", "b/two", "board/self"])).map(\.id), ["b/two"])
        board.admits = .all
        XCTAssertFalse(board.admits(moduleID: "board"), "a board never shows itself")
    }

    // MARK: - Boards in a host

    private final class WidgetModule: NookModule {
        let descriptor: NookModuleDescriptor
        let make: @MainActor () -> NookConfiguration

        init(id: String, make: @escaping @MainActor () -> NookConfiguration) {
            var descriptor = NookModuleDescriptor(id: id, displayName: id, backgroundPolicy: .stayResident)
            descriptor.loadsAtLaunch = true
            self.descriptor = descriptor
            self.make = make
        }

        func makeConfiguration() -> NookConfiguration { make() }
    }

    /// Records the module whose activities a widget could see.
    @MainActor
    private final class ScopeCapture {
        var moduleIDs: [String] = []
    }

    private struct ScopeProbe: View {
        let capture: ScopeCapture
        @Environment(\.nookLiveActivities) private var activities

        var body: some View {
            Color.clear.onAppear { capture.moduleIDs.append(activities.moduleID) }
        }
    }

    private func makeHost(capture: ScopeCapture) -> AppCoordinator {
        var host = NookHostConfiguration()
        host.registerBoard(NookBoardConfiguration(id: "board", displayName: "Board"))
        for id in ["music", "clock"] {
            let descriptor = WidgetModule(id: id) { NookConfiguration() }.descriptor
            host.register(descriptor) { _ in
                WidgetModule(id: id) {
                    var configuration = NookConfiguration()
                    configuration.addWidget(
                        NookWidget(id: "main", title: id, action: .openModule) { _ in ScopeProbe(capture: capture) }
                    )
                    return configuration
                }
            }
        }
        return AppCoordinator(moduleHost: ModuleHost(registry: host.makeRegistry()), surface: FakeNookSurface())
    }

    func testABoardShowsTheLoadedModulesWidgetsEachInItsOwnScope() throws {
        let capture = ScopeCapture()
        let coordinator = makeHost(capture: capture)
        let registry = coordinator.moduleHost.registry
        XCTAssertEqual(coordinator.moduleHost.activeModuleID, "board")
        XCTAssertTrue(registry.widgets.entries.isEmpty, "nothing else is loaded yet")

        coordinator.loadModulesAtLaunch()
        XCTAssertEqual(registry.widgets.entries.map(\.id), ["music/main", "clock/main"])

        let board = try XCTUnwrap(registry.module(for: "board") as? NookBoardModule)
        let home = coordinator.moduleHost.configuration.home
        _ = ImageRenderer(content: home().frame(width: 500)).nsImage
        XCTAssertEqual(capture.moduleIDs.sorted(), ["clock", "music"])

        @MainActor final class Switches { var ids: [String] = [] }
        let switches = Switches()
        let items = NookBoardHome.items(board.store.visible(registry.widgets.entries)) { switches.ids.append($0) }
        items.first?.open?()
        XCTAssertEqual(switches.ids, ["music"], "a widget that opens its module switches to it")

        registry.unload("music")
        XCTAssertEqual(registry.widgets.entries.map(\.id), ["clock/main"])
    }

    func testALockedBoardHasNoEditor() {
        var host = NookHostConfiguration()
        host.registerBoard(NookBoardConfiguration(id: "open", displayName: "Open"))
        host.registerBoard(NookBoardConfiguration(id: "locked", displayName: "Locked", isLayoutLocked: true))
        let registry = host.makeRegistry()
        XCTAssertEqual(registry.module(for: "open")?.makeConfiguration().settingsSections.map(\.title), ["Widgets"])
        XCTAssertEqual(registry.module(for: "locked")?.makeConfiguration().settingsSections.count, 0)
        XCTAssertEqual(registry.module(for: "open")?.makeConfiguration().topBar.leadingIcon, "square.grid.2x2")
    }

    // MARK: - Entrance

    func testTheGridsCardsStaggerInOrder() {
        @MainActor final class CountBox { var count = 0 }
        let box = CountBox()
        var theme = NookTheme()
        theme.tokens[.stagger] = 0.03
        let grid = NookWidgetGrid((0..<5).map { widget("w\($0)") })
            .environment(\.nookThemeTokens, theme.resolvedTokens())
            .onPreferenceChange(NookStaggeredRowsPreferenceKey.self) { count in
                MainActor.assumeIsolated { box.count = count }
            }
        let hosting = NSHostingView(rootView: grid.frame(width: 400))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(box.count, 5)
    }
}
