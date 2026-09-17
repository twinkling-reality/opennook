// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit
import SwiftUI
import XCTest

@testable import NookSurface

/// Coverage for the surface side of companion surfaces, the rim glow, and the scroll edge
/// fade: the value types, the pure layout math, the one-hover-state model across the chrome
/// and its companions, and the panel growing to fit.
///
/// The hover tests drive a real `Nook` on the main display (skipped without one), like the
/// layout-grace test in `NookSurfaceConcurrencyTests`, because the rules under test are about
/// how hover interacts with real expand and compact transitions.
@MainActor
final class NookCompanionSurfaceTests: XCTestCase {

    private func companion(
        _ id: String,
        anchor: NookCompanionAnchor = .below,
        spacing: CGFloat = 8,
        visibility: NookCompanionVisibility = .expanded
    ) -> NookCompanionSurface {
        NookCompanionSurface(id: id, anchor: anchor, spacing: spacing, visibility: visibility) {
            Text(id)
        }
    }

    /// No hover behavior: `.keepVisible` would hold `hide()` open while a test holds hover.
    private func makeNook() -> Nook<Text, Text, EmptyView> {
        Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
    }

    /// A nook on the main display in `state`, with fast transitions, torn down after the test.
    private func liveNook(
        _ state: NookState = .expanded,
        companions: [NookCompanionSurface] = []
    ) async throws -> (Nook<Text, Text, EmptyView>, NSScreen) {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No main display attached")
        }
        let nook = makeNook()
        nook.transitionConfiguration.animationDuration = 0.05
        // The expanded content's first layout opens a layout grace that swallows hover
        // exits; keep it short so the tests below exercise companion hover alone.
        nook.transitionConfiguration.layoutGraceDuration = 0
        nook.companionHoverExitGrace = .milliseconds(150)
        nook.companions = companions
        switch state {
            case .expanded: await nook.expand(on: screen)
            case .compact: await nook.compact(on: screen)
            case .hidden: break
        }
        addTeardownBlock { await nook.hide() }
        await waitUntil { !nook.isLayoutGraceActive }
        return (nook, screen)
    }

    /// Poll until `condition` holds; fixed sleeps flake under a parallel CI load.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition not met within \(timeout)", file: file, line: line)
    }

    // MARK: - Value types

    func testVisibilityIncludesOnlyItsStates() {
        XCTAssertTrue(NookCompanionVisibility.expanded.includes(.expanded))
        XCTAssertFalse(NookCompanionVisibility.expanded.includes(.compact))
        XCTAssertTrue(NookCompanionVisibility.compact.includes(.compact))
        XCTAssertFalse(NookCompanionVisibility.compact.includes(.expanded))
        XCTAssertTrue(NookCompanionVisibility.both.includes(.compact))
        XCTAssertTrue(NookCompanionVisibility.both.includes(.expanded))
        XCTAssertFalse(NookCompanionVisibility.both.includes(.hidden), "no chrome, no companion")
        XCTAssertFalse(NookCompanionVisibility([]).includes(.expanded))
    }

    func testAnchorShorthandsCenterOnTheirEdge() {
        XCTAssertEqual(NookCompanionAnchor.below, NookCompanionAnchor(edge: .below, alignment: .center))
        XCTAssertEqual(NookCompanionAnchor.leading, NookCompanionAnchor(edge: .leading, alignment: .center))
        XCTAssertEqual(NookCompanionAnchor.trailing, NookCompanionAnchor(edge: .trailing, alignment: .center))
        XCTAssertEqual(NookCompanionAnchor.below(alignment: .end).alignment, .end)
        XCTAssertEqual(NookCompanionAnchor.leading(alignment: .start).edge, .leading)
    }

    func testBackdropInheritsOverridesOrOmits() {
        let chrome = NookBackdrop.solid(.black)
        let custom = NookBackdrop.solid(.red)
        XCTAssertEqual(NookCompanionBackdrop.inherit.resolved(inheriting: chrome), chrome)
        XCTAssertEqual(NookCompanionBackdrop.custom(custom).resolved(inheriting: chrome), custom)
        XCTAssertNil(NookCompanionBackdrop.none.resolved(inheriting: chrome))
    }

    func testContentRestrictionsIntersect() {
        typealias Key = NookCompanionVisibilityPreferenceKey
        XCTAssertNil(Key.combine(nil, nil))
        XCTAssertEqual(Key.combine(.both, nil), .both)
        XCTAssertEqual(Key.combine(nil, .compact), .compact)
        XCTAssertEqual(Key.combine(.both, .expanded), .expanded)
        XCTAssertEqual(Key.combine(.compact, .expanded), [], "disjoint restrictions hide the companion")

        var value: NookCompanionVisibility? = .both
        Key.reduce(value: &value) { .compact }
        XCTAssertEqual(value, .compact)
    }

    func testAccessibilityIdentifierIsNamespaced() {
        XCTAssertEqual(companion("actions").accessibilityIdentifier, "opennook.companion.actions")
        XCTAssertEqual(NookCompanionSurface.accessibilityIdentifier(for: "x"), "opennook.companion.x")
    }

    // MARK: - Layout

    /// Every companion is laid out by the one layer, grouped into rows by anchor in the order the
    /// anchors first appear.
    func testLayerGroupsCompanionsIntoRowsByAnchor() {
        typealias Item = NookCompanionRowGeometry.Item
        let items = [
            Item(anchor: .below, size: CGSize(width: 100, height: 48), spacing: 8, isPresented: true),
            Item(anchor: .trailing, size: CGSize(width: 48, height: 40), spacing: 8, isPresented: true),
            Item(anchor: .below, size: CGSize(width: 48, height: 48), spacing: 8, isPresented: true),
            Item(
                anchor: .below(alignment: .start),
                size: CGSize(width: 60, height: 48),
                spacing: 8,
                isPresented: true
            ),
        ]
        let rows = NookCompanionLayerLayout.rows(of: items)
        XCTAssertEqual(rows.map(\.anchor), [.below, .trailing, .below(alignment: .start)])
        XCTAssertEqual(rows.map(\.indices), [[0, 2], [1], [3]])

        let chrome = CGRect(x: 0, y: 0, width: 400, height: 200)
        let frames = NookCompanionLayerLayout.frames(
            of: items,
            in: chrome,
            bodyInset: 0,
            keepsSideRowsBelowTop: true
        )
        // The centered row below is 100 + 8 + 48 wide, centered under the chrome.
        XCTAssertEqual(frames[0], CGRect(x: 122, y: 200, width: 100, height: 48))
        XCTAssertEqual(frames[2], CGRect(x: 230, y: 200, width: 48, height: 48))
        XCTAssertEqual(frames[1], CGRect(x: 400, y: 80, width: 48, height: 40), "centered beside the chrome")
        XCTAssertEqual(frames[3], CGRect(x: 0, y: 200, width: 60, height: 48), "a row of its own")
    }

    /// The notch form's top edge is the top of the screen, so a side row taller than the chrome
    /// is held below it instead of being cut off. A floating pill has room above.
    func testSideRowsNeverRiseAboveTheNotchFormsTopEdge() {
        typealias Item = NookCompanionRowGeometry.Item
        let chrome = CGRect(x: 0, y: 0, width: 200, height: 32)
        let tall = [Item(anchor: .trailing, size: CGSize(width: 48, height: 40), spacing: 8, isPresented: true)]
        XCTAssertEqual(
            NookCompanionLayerLayout.frames(of: tall, in: chrome, bodyInset: 6, keepsSideRowsBelowTop: true),
            [CGRect(x: 194, y: 0, width: 48, height: 40)]
        )
        XCTAssertEqual(
            NookCompanionLayerLayout.frames(of: tall, in: chrome, bodyInset: 0, keepsSideRowsBelowTop: false),
            [CGRect(x: 200, y: -4, width: 48, height: 40)]
        )

        let bottomPinned = [
            Item(
                anchor: .leading(alignment: .end),
                size: CGSize(width: 48, height: 40),
                spacing: 8,
                isPresented: true,
                rowAlignment: .end
            )
        ]
        XCTAssertEqual(
            NookCompanionLayerLayout.frames(of: bottomPinned, in: chrome, bodyInset: 6, keepsSideRowsBelowTop: true),
            [CGRect(x: -42, y: 0, width: 48, height: 40)]
        )

        let below = [Item(anchor: .below, size: CGSize(width: 48, height: 48), spacing: 8, isPresented: true)]
        let hanging = NookCompanionLayerLayout.frames(of: below, in: chrome, bodyInset: 6, keepsSideRowsBelowTop: true)
        XCTAssertEqual(hanging[0].minY, 32, "a row below the chrome is never moved")
    }

    /// The notch form measures from the visible body, inside the ears.
    func testLayerPinsRowsToTheChromeBodyInTheNotchForm() {
        let chrome = CGRect(x: 0, y: 0, width: 400, height: 200)
        func place(_ anchor: NookCompanionAnchor) -> (CGPoint, UnitPoint) {
            let placement = NookCompanionLayerLayout.placement(for: anchor, in: chrome, bodyInset: 19)
            return (placement.point, placement.anchor)
        }
        XCTAssertEqual(place(.below(alignment: .start)).0, CGPoint(x: 19, y: 200))
        XCTAssertEqual(place(.below(alignment: .start)).1, .topLeading)
        XCTAssertEqual(place(.below).0, CGPoint(x: 200, y: 200))
        XCTAssertEqual(place(.below).1, .top)
        XCTAssertEqual(place(.below(alignment: .end)).0, CGPoint(x: 381, y: 200))
        XCTAssertEqual(place(.below(alignment: .end)).1, .topTrailing)
        XCTAssertEqual(place(.leading(alignment: .start)).0, CGPoint(x: 19, y: 0))
        XCTAssertEqual(place(.leading(alignment: .start)).1, .topTrailing)
        XCTAssertEqual(place(.leading).0, CGPoint(x: 19, y: 100))
        XCTAssertEqual(place(.leading).1, .trailing)
        XCTAssertEqual(place(.leading(alignment: .end)).0, CGPoint(x: 19, y: 200))
        XCTAssertEqual(place(.leading(alignment: .end)).1, .bottomTrailing)
        XCTAssertEqual(place(.trailing(alignment: .start)).0, CGPoint(x: 381, y: 0))
        XCTAssertEqual(place(.trailing(alignment: .start)).1, .topLeading)
        XCTAssertEqual(place(.trailing).0, CGPoint(x: 381, y: 100))
        XCTAssertEqual(place(.trailing).1, .leading)
        XCTAssertEqual(place(.trailing(alignment: .end)).0, CGPoint(x: 381, y: 200))
        XCTAssertEqual(place(.trailing(alignment: .end)).1, .bottomLeading)
    }

    /// The floating panel has no ears, so its body is its whole frame.
    func testLayerPinsRowsToTheFrameInTheFloatingForm() {
        let chrome = CGRect(x: 10, y: 40, width: 300, height: 100)
        let start = NookCompanionLayerLayout.placement(for: .below(alignment: .start), in: chrome, bodyInset: 0)
        let side = NookCompanionLayerLayout.placement(for: .trailing, in: chrome, bodyInset: 0)
        XCTAssertEqual(start.point, CGPoint(x: 10, y: 140))
        XCTAssertEqual(side.point, CGPoint(x: 310, y: 90))
    }

    func testBelowRowRunsLeftToRightWithSpacingBetweenNeighbours() {
        typealias Item = NookCompanionRowGeometry.Item
        let items = [
            Item(size: CGSize(width: 100, height: 50), spacing: 10, isPresented: true),
            Item(size: CGSize(width: 40, height: 52), spacing: 12, isPresented: true),
        ]
        // The first spacing is inside its height already; the second is also a gap.
        XCTAssertEqual(NookCompanionRowGeometry.size(of: items, edge: .below), CGSize(width: 152, height: 52))

        let bounds = CGRect(x: 0, y: 0, width: 152, height: 52)
        let frames = NookCompanionRowGeometry.frames(of: items, anchor: .below, in: bounds)
        // Every shown companion is given the row's height, less the drop it is short of.
        XCTAssertEqual(
            frames,
            [
                CGRect(x: 0, y: 2, width: 100, height: 50),
                CGRect(x: 112, y: 0, width: 40, height: 52),
            ]
        )
    }

    /// Surfaces in one row line up whatever spacing each asks for: the row hangs them all from
    /// its largest drop.
    func testBelowRowHangsEverySurfaceFromTheLargestDrop() {
        typealias Item = NookCompanionRowGeometry.Item
        // Two 40 pt surfaces asking for 8 and 12 pt drops, and a hidden one asking for 20.
        let items = [
            Item(size: CGSize(width: 40, height: 48), spacing: 8, isPresented: true),
            Item(size: CGSize(width: 40, height: 52), spacing: 12, isPresented: true),
            Item(size: CGSize(width: 40, height: 60), spacing: 20, isPresented: false),
        ]
        XCTAssertEqual(NookCompanionRowGeometry.drop(of: items), 12, "a hidden companion's spacing does not count")
        XCTAssertEqual(NookCompanionRowGeometry.size(of: items, edge: .below), CGSize(width: 92, height: 52))

        let bounds = CGRect(x: 0, y: 0, width: 92, height: 52)
        let frames = NookCompanionRowGeometry.frames(of: items, anchor: .below, in: bounds)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 4, width: 40, height: 48))
        XCTAssertEqual(frames[1], CGRect(x: 52, y: 0, width: 40, height: 52))
        // Each cell pads toward the chrome by its own spacing, so both surfaces start 12 pt down
        // and share the band below that.
        XCTAssertEqual(frames[0].minY + items[0].spacing, 12)
        XCTAssertEqual(frames[1].minY + items[1].spacing, 12)
        XCTAssertEqual(frames[0].maxY, frames[1].maxY)
    }

    /// A gap of its own moves a companion away from its neighbour without moving it away from the
    /// chrome: its spacing, the drop, is unchanged.
    func testBelowRowGapSeparatesNeighboursWithoutChangingTheDrop() {
        typealias Item = NookCompanionRowGeometry.Item
        let items = [
            Item(size: CGSize(width: 120, height: 48), spacing: 8, isPresented: true),
            Item(size: CGSize(width: 48, height: 48), spacing: 8, isPresented: true, gap: 24),
            Item(size: CGSize(width: 48, height: 48), spacing: 8, isPresented: false, gap: 99),
        ]
        XCTAssertEqual(NookCompanionRowGeometry.size(of: items, edge: .below), CGSize(width: 192, height: 48))

        let bounds = CGRect(x: 0, y: 0, width: 192, height: 48)
        let frames = NookCompanionRowGeometry.frames(of: items, anchor: .below, in: bounds)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: 120, height: 48))
        XCTAssertEqual(frames[1], CGRect(x: 144, y: 0, width: 48, height: 48), "24 pt gap, same top")
        XCTAssertEqual(items[1].effectiveGap, 24)
        XCTAssertEqual(items[0].effectiveGap, 8, "no gap of its own falls back to the spacing")

        let surface = NookCompanionSurface(id: "a", spacing: 6, gap: 20) { Text("a") }
        XCTAssertEqual(surface.effectiveGap, 20)
        XCTAssertEqual(companion("b", spacing: 6).effectiveGap, 6)
    }

    func testHiddenCompanionsTakeNoRoomAndFoldIntoTheChromeEdge() {
        typealias Item = NookCompanionRowGeometry.Item
        let items = [
            Item(size: CGSize(width: 60, height: 40), spacing: 8, isPresented: false),
            Item(size: CGSize(width: 100, height: 50), spacing: 8, isPresented: true),
        ]
        XCTAssertEqual(NookCompanionRowGeometry.size(of: items, edge: .below), CGSize(width: 100, height: 50))

        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let frames = NookCompanionRowGeometry.frames(of: items, anchor: .below, in: bounds)
        // The hidden one waits centered against the chrome's bottom edge; the shown one
        // gets the row to itself, with no gap for the hidden one before it.
        XCTAssertEqual(frames[0], CGRect(x: 20, y: 0, width: 60, height: 40))
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 0, width: 100, height: 50))

        XCTAssertEqual(
            NookCompanionRowGeometry.size(of: [items[0]], edge: .trailing),
            .zero,
            "a row with nothing shown takes no room"
        )
    }

    func testLeadingRowGrowsOutwardFromTheChrome() {
        typealias Item = NookCompanionRowGeometry.Item
        let items = [
            Item(size: CGSize(width: 30, height: 30), spacing: 6, isPresented: true),
            Item(size: CGSize(width: 50, height: 20), spacing: 6, isPresented: true),
        ]
        XCTAssertEqual(NookCompanionRowGeometry.size(of: items, edge: .leading), CGSize(width: 80, height: 30))

        let bounds = CGRect(x: 0, y: 0, width: 80, height: 30)
        let frames = NookCompanionRowGeometry.frames(of: items, anchor: .leading, in: bounds)
        // The first companion is nearest the chrome - the row's trailing end.
        XCTAssertEqual(frames[0], CGRect(x: 50, y: 0, width: 30, height: 30))
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 0, width: 50, height: 30), "the row's full height")

        let folded = NookCompanionRowGeometry.foldedFrame(
            of: Item(size: CGSize(width: 50, height: 20), spacing: 6, isPresented: false, rowAlignment: .end),
            anchor: .leading(alignment: .end),
            in: bounds
        )
        XCTAssertEqual(folded, CGRect(x: 30, y: 10, width: 50, height: 20), "folds against the chrome side")
    }

    /// A hidden companion waits where its own row alignment would show it, not where the anchor's
    /// alignment would.
    func testHiddenSideCompanionsFoldWhereTheirRowAlignmentPutsThem() {
        typealias Item = NookCompanionRowGeometry.Item
        let bounds = CGRect(x: 0, y: 0, width: 0, height: 100)
        func foldedY(_ alignment: NookCompanionAnchor.Alignment) -> CGFloat {
            let item = Item(
                size: CGSize(width: 40, height: 20),
                spacing: 8,
                isPresented: false,
                rowAlignment: alignment
            )
            return NookCompanionRowGeometry.foldedFrame(of: item, anchor: .trailing, in: bounds).minY
        }
        XCTAssertEqual(foldedY(.start), 0)
        XCTAssertEqual(foldedY(.center), 40)
        XCTAssertEqual(foldedY(.end), 80)
    }

    /// A short companion spans its row, so its hover region reaches the chrome, and its surface
    /// sits across the row by its row alignment.
    func testCompanionsSpanTheirRowAndAlignWithinIt() {
        typealias Item = NookCompanionRowGeometry.Item
        let items = [
            Item(size: CGSize(width: 30, height: 40), spacing: 6, isPresented: true),
            Item(size: CGSize(width: 30, height: 10), spacing: 6, isPresented: true),
        ]
        let bounds = CGRect(x: 100, y: 0, width: 60, height: 40)
        let frames = NookCompanionRowGeometry.frames(of: items, anchor: .trailing(alignment: .end), in: bounds)
        XCTAssertEqual(frames[1], CGRect(x: 130, y: 0, width: 30, height: 40))

        // Below the chrome a companion centers by default; beside it, it follows the anchor.
        XCTAssertEqual(companion("a").effectiveRowAlignment, .center)
        XCTAssertEqual(companion("b", anchor: .trailing(alignment: .end)).effectiveRowAlignment, .end)
        XCTAssertEqual(companion("c", anchor: .leading(alignment: .start)).effectiveRowAlignment, .start)
        let pinned = NookCompanionSurface(id: "d", rowAlignment: .start) { Text("d") }
        XCTAssertEqual(pinned.effectiveRowAlignment, .start, "an explicit alignment wins")

        XCTAssertEqual(NookCompanionAnchor.Alignment.start.rowPosition, .top)
        XCTAssertEqual(NookCompanionAnchor.Alignment.center.rowPosition, .center)
        XCTAssertEqual(NookCompanionAnchor.Alignment.end.rowPosition, .bottom)
    }

    func testEdgesKnowWhichSideFacesTheChrome() {
        XCTAssertEqual(NookCompanionAnchor.Edge.below.towardChrome, .top)
        XCTAssertEqual(NookCompanionAnchor.Edge.below.awayFromChrome, .bottom)
        XCTAssertEqual(NookCompanionAnchor.Edge.leading.towardChrome, .trailing)
        XCTAssertEqual(NookCompanionAnchor.Edge.leading.awayFromChrome, .leading)
        XCTAssertEqual(NookCompanionAnchor.Edge.trailing.towardChrome, .leading)
        XCTAssertEqual(NookCompanionAnchor.Edge.trailing.awayFromChrome, .trailing)
        XCTAssertEqual(NookCompanionAnchor.Edge.below.chromeSide, .top)
        XCTAssertEqual(NookCompanionAnchor.Edge.leading.chromeSide, .trailing)
        XCTAssertEqual(NookCompanionAnchor.Edge.trailing.chromeSide, .leading)
        XCTAssertEqual(NookCompanionAnchor.Edge.below.foldAnchor, .top)
    }

    /// Two surfaces with one id would share a SwiftUI identity and a hover key, so only the first
    /// is kept, and the chrome's hover bookkeeping never sees the other.
    func testCompanionsKeepOnlyTheFirstWithAnID() {
        let unique = NookCompanionSurface.removingDuplicateIDs([
            companion("a", spacing: 4),
            companion("a", anchor: .trailing, spacing: 9),
            companion("b"),
        ])
        XCTAssertEqual(unique.map(\.id), ["a", "b"])
        XCTAssertEqual(unique[0].spacing, 4)

        let nook = makeNook()
        nook.companions = [
            companion("x", visibility: .expanded),
            companion("x", visibility: .both),
            companion("y"),
        ]
        XCTAssertEqual(nook.companions.map(\.id), ["x", "y"])
        XCTAssertEqual(nook.companions[0].visibility, .expanded)
        XCTAssertEqual(nook.presentedCompanionIDs(in: .compact), [], "the dropped companion is not counted as shown")
    }

    // MARK: - Hover across the chrome and its companions

    /// Without companions a hover exit is what it always was: an immediate collapse.
    func testChromeHoverExitWithoutCompanionsCollapsesImmediately() async throws {
        let (nook, _) = try await liveNook()
        var compacted = false
        nook.onCompact = { compacted = true }

        nook.updateChromeHoverState(true)
        XCTAssertTrue(nook.isHovering)
        nook.updateChromeHoverState(false)

        XCTAssertNil(nook.companionHoverExitTask, "no grace without companions")
        XCTAssertFalse(nook.isHovering)
        await waitUntil { compacted }
    }

    /// The pointer leaving the chrome for a companion is one continuous hover.
    func testMovingFromTheChromeOntoACompanionKeepsTheNookOpen() async throws {
        let (nook, _) = try await liveNook(companions: [companion("pill")])
        var compacted = false
        nook.onCompact = { compacted = true }

        nook.updateChromeHoverState(true)
        nook.updateChromeHoverState(false)
        nook.updateCompanionHoverState(id: "pill", hovering: true)

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(compacted)
        XCTAssertEqual(nook.state, .expanded)
        XCTAssertTrue(nook.isHovering)
        XCTAssertEqual(nook.hoveredCompanionIDs, ["pill"])

        // Leaving the companion for empty space is a real exit, after the grace.
        nook.updateCompanionHoverState(id: "pill", hovering: false)
        XCTAssertEqual(nook.state, .expanded, "the exit waits out the grace")
        await waitUntil { compacted }
    }

    func testReenteringWithinTheGraceCancelsTheExit() async throws {
        let (nook, _) = try await liveNook(companions: [companion("pill")])
        var compacted = false
        nook.onCompact = { compacted = true }

        nook.updateChromeHoverState(true)
        nook.updateChromeHoverState(false)
        XCTAssertNotNil(nook.companionHoverExitTask)
        nook.updateChromeHoverState(true)
        XCTAssertNil(nook.companionHoverExitTask)

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(compacted)
        XCTAssertTrue(nook.isHovering)
    }

    /// A companion shown beside the compact pill only keeps the surface hovered. Expanding
    /// here would hide a compact-only companion under the pointer and loop.
    func testHoveringACompanionDoesNotExpandTheCompactNook() async throws {
        let (nook, _) = try await liveNook(.compact, companions: [companion("timer", visibility: .both)])
        var expanded = false
        nook.onExpand = { expanded = true }

        nook.updateCompanionHoverState(id: "timer", hovering: true)

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(expanded)
        XCTAssertEqual(nook.state, .compact)
        XCTAssertTrue(nook.isHovering, "still counts as hovering the surface")
    }

    func testHoverOnACompanionThatIsNotShownIsIgnored() async throws {
        let (nook, _) = try await liveNook(companions: [companion("mini", visibility: .compact)])

        nook.updateCompanionHoverState(id: "mini", hovering: true)

        XCTAssertTrue(nook.hoveredCompanionIDs.isEmpty)
        XCTAssertFalse(nook.isHovering)
    }

    /// A module switch removing the hovered companion leaves the pointer over empty space.
    func testRemovingAHoveredCompanionEndsTheHover() async throws {
        let (nook, _) = try await liveNook(companions: [companion("pill")])
        var compacted = false
        nook.onCompact = { compacted = true }
        nook.updateCompanionHoverState(id: "pill", hovering: true)
        XCTAssertTrue(nook.isHovering)

        nook.companions = []

        XCTAssertTrue(nook.hoveredCompanionIDs.isEmpty)
        await waitUntil { compacted }
    }

    /// Collapsing folds away an expanded-only companion under the pointer; SwiftUI sends no
    /// exit for it, so the model drops the hover itself - without starting a transition.
    func testCollapsingDropsHoverHeldByAnExpandedOnlyCompanion() async throws {
        let (nook, screen) = try await liveNook(companions: [companion("pill")])
        nook.updateCompanionHoverState(id: "pill", hovering: true)
        XCTAssertTrue(nook.isHovering)

        await nook.compact(on: screen)

        XCTAssertEqual(nook.state, .compact)
        XCTAssertTrue(nook.hoveredCompanionIDs.isEmpty)
        XCTAssertFalse(nook.isHovering)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(nook.state, .compact, "dropping the hover starts no transition")
    }

    func testContentHidingAHoveredCompanionEndsTheHover() async throws {
        let (nook, _) = try await liveNook(companions: [companion("results")])
        var compacted = false
        nook.onCompact = { compacted = true }
        nook.updateCompanionHoverState(id: "results", hovering: true)

        nook.noteCompanionVisibilityRestriction(id: "results", restriction: [])

        XCTAssertFalse(nook.isCompanionPresented(nook.companions[0], in: .expanded))
        XCTAssertTrue(nook.hoveredCompanionIDs.isEmpty)
        await waitUntil { compacted }
    }

    func testHideForgetsEveryHoverSource() async throws {
        let (nook, _) = try await liveNook(companions: [companion("pill")])
        nook.updateChromeHoverState(true)
        nook.updateCompanionHoverState(id: "pill", hovering: true)

        await nook.hide()

        XCTAssertFalse(nook.isChromeHovered)
        XCTAssertTrue(nook.hoveredCompanionIDs.isEmpty)
        XCTAssertNil(nook.companionHoverExitTask)
        XCTAssertFalse(nook.isHovering)
    }

    func testReplacingCompanionsForgetsBookkeepingForRemovedOnes() {
        let nook = makeNook()
        nook.companions = [companion("a"), companion("b")]
        nook.companionVisibilityRestrictions = ["a": .compact, "b": []]
        nook.companionExtents = ["a": 100, "b": 200]

        nook.companions = [companion("b")]

        XCTAssertEqual(nook.companionVisibilityRestrictions, ["b": []])
        XCTAssertEqual(nook.companionExtents, ["b": 200])
    }

    // MARK: - Panel size

    func testPanelHeightOnlyGrowsAndStopsAtTheScreen() {
        XCTAssertEqual(
            Nook<Text, Text, EmptyView>.panelHeight(fitting: 300, currentHeight: 500, screenHeight: 1000),
            500
        )
        XCTAssertEqual(
            Nook<Text, Text, EmptyView>.panelHeight(fitting: 600, currentHeight: 500, screenHeight: 1000),
            624
        )
        XCTAssertEqual(
            Nook<Text, Text, EmptyView>.panelHeight(fitting: 990, currentHeight: 500, screenHeight: 1000),
            1000
        )
    }

    /// A companion reaching past the panel grows it downward, top edge pinned, while the
    /// file-drag region keeps the height it always had.
    func testPanelGrowsDownwardToFitACompanion() async throws {
        let (nook, screen) = try await liveNook(companions: [companion("basket")])
        let window = try XCTUnwrap(nook.windowController?.window)
        let startFrame = window.frame
        let interceptor = try XCTUnwrap(
            window.contentView?.subviews.first { $0 is NookDragInterceptingView }
        )

        // Set the extent and grow synchronously: the scheduled path would race the real
        // companion's own (smaller) extent reports.
        let extent = (startFrame.height + 120).rounded()
        nook.companionExtents["basket"] = extent
        nook.growPanelToFitCompanions()

        XCTAssertEqual(window.frame.height, min(extent + 24, screen.frame.height))
        XCTAssertEqual(window.frame.maxY, startFrame.maxY, "the top edge stays pinned")
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(interceptor.frame.height, startFrame.height, "the drag region does not grow")
        XCTAssertEqual(interceptor.frame.maxY, window.contentView?.bounds.maxY, "and stays at the top")
    }

    func testExtentsAreRecordedOnlyForKnownCompanions() {
        let nook = makeNook()
        nook.companions = [companion("basket")]
        nook.noteCompanionExtent(id: "ghost", maxY: 5_000)
        nook.noteCompanionExtent(id: "basket", maxY: 300)
        XCTAssertEqual(nook.companionExtents, ["basket": 300])
        XCTAssertTrue(nook.isPanelGrowthScheduled)
    }

    // MARK: - Size, style, and presence

    func testSizePresetsCenterControlsInTheirSurfaces() {
        XCTAssertEqual(NookCompanionSize.small.inset, 3)
        XCTAssertEqual(NookCompanionSize.regular.inset, 4)
        XCTAssertEqual(NookCompanionSize.large.inset, 4)
        XCTAssertEqual(NookCompanionSize.regular.height, 40)
        XCTAssertEqual(NookCompanionSize.regular.controlSize, 32)

        let odd = NookCompanionSize(height: 20, controlSize: 30, glyphSize: 0, controlSpacing: -2)
        XCTAssertEqual(odd.inset, 0, "a control larger than its surface has no inset")
        XCTAssertEqual(odd.glyphSize, 1)
        XCTAssertEqual(odd.controlSpacing, 0)
    }

    /// Beside the compact pill a companion is fitted to the pill: the regular size fitted to a
    /// 32 pt notch is the small size.
    func testSizesFitTheChromeBesideThem() {
        XCTAssertEqual(NookCompanionSize.regular.fitting(height: 32), .small)
        XCTAssertEqual(NookCompanionSize.regular.fitting(height: 40), .regular)
        XCTAssertEqual(NookCompanionSize.regular.fitting(height: 48), .regular, "a size that fits is unchanged")
        XCTAssertEqual(
            NookCompanionSize.regular.fitting(height: 38),
            NookCompanionSize(height: 38, controlSize: 30, glyphSize: 12)
        )
        XCTAssertEqual(
            NookCompanionSize.large.fitting(height: 32),
            NookCompanionSize(height: 32, controlSize: 27, glyphSize: 11, controlSpacing: 4)
        )
        let nothing = NookCompanionSize.regular.fitting(height: -5)
        XCTAssertEqual(nothing.height, 0)
        XCTAssertEqual(nothing.controlSize, 0)
    }

    func testStandardStylePresets() {
        XCTAssertEqual(NookStandardCompanionStyle.standard, NookStandardCompanionStyle())
        XCTAssertEqual(NookStandardCompanionStyle.faded.fade, .standard)
        XCTAssertEqual(NookStandardCompanionStyle.raised.stroke, .hairline)
        XCTAssertEqual(NookStandardCompanionStyle.raised.shadow, .soft)
        XCTAssertEqual(NookStandardCompanionStyle.raised.hover, .lift)
        XCTAssertEqual(NookStandardCompanionStyle.plain.fill, .none)
        XCTAssertEqual(NookStandardCompanionStyle.plain.height, .content)

        let standard = NookStandardCompanionStyle.standard
        XCTAssertEqual(standard.minimumHeight(for: .large), 48)
        XCTAssertEqual(
            standard.resolvedPadding(for: .regular),
            EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        )
        XCTAssertNil(NookStandardCompanionStyle.plain.minimumHeight(for: .regular))
        XCTAssertEqual(NookStandardCompanionStyle.plain.resolvedPadding(for: .regular), EdgeInsets())
        XCTAssertEqual(NookStandardCompanionStyle(height: .minimum(-5)).minimumHeight(for: .regular), 0)
        XCTAssertEqual(NookStandardCompanionStyle(height: .fixed(52)).minimumHeight(for: .regular), 52)

        XCTAssertTrue(AnyNookCompanionStyle.faded.base is NookStandardCompanionStyle)
        XCTAssertEqual(AnyNookCompanionStyle.plain.base as? NookStandardCompanionStyle, .plain)
        XCTAssertEqual(
            AnyNookCompanionStyle.standard(fade: .toClear, hover: .glow).base as? NookStandardCompanionStyle,
            NookStandardCompanionStyle(fade: .toClear, hover: .glow)
        )
    }

    func testStyleValuesStayInRange() {
        let fade = NookStandardCompanionStyle.Fade(start: 2, end: -1)
        XCTAssertEqual(fade.start, 1)
        XCTAssertEqual(fade.end, 0)
        let hover = NookStandardCompanionStyle.Hover(wash: 3, scale: -1)
        XCTAssertEqual(hover.wash, 1)
        XCTAssertEqual(hover.scale, 0)
        XCTAssertEqual(NookStandardCompanionStyle.Glow(radius: -4).radius, 0)
        XCTAssertEqual(NookStandardCompanionStyle.Stroke(width: -1).width, 0)
        XCTAssertEqual(NookStandardCompanionStyle.Shadow(radius: -1).radius, 0)
    }

    /// The point of the shared size: one control in a circle and three in a capsule come out the
    /// same height, and a surface never shrinks below it.
    func testStandardStyleSizesSurfacesToTheSharedHeight() {
        func measure(
            _ style: NookStandardCompanionStyle,
            shape: NookCompanionShape = .capsule,
            size: NookCompanionSize = .regular,
            content: CGSize
        ) -> CGSize {
            let body = Color.clear.frame(width: content.width, height: content.height)
            let squared = shape == .circle ? AnyView(NookCompanionSquareLayout { body }) : AnyView(body)
            let configuration = NookCompanionStyleConfiguration(
                content: squared,
                shape: shape,
                backdrop: .solid(.black),
                edge: .below,
                size: size,
                isHovered: false,
                isPresented: true
            )
            return NSHostingView(rootView: style.makeBody(configuration: configuration).fixedSize()).fittingSize
        }

        let one = measure(.standard, shape: .circle, content: CGSize(width: 32, height: 32))
        let three = measure(.standard, content: CGSize(width: 100, height: 32))
        XCTAssertEqual(one, CGSize(width: 40, height: 40))
        XCTAssertEqual(three, CGSize(width: 108, height: 40))
        XCTAssertEqual(
            measure(.standard, shape: .circle, content: CGSize(width: 20, height: 12)),
            CGSize(width: 40, height: 40)
        )
        XCTAssertEqual(measure(.standard, content: CGSize(width: 60, height: 15)), CGSize(width: 68, height: 40))
        XCTAssertEqual(
            measure(.standard, size: .large, content: CGSize(width: 40, height: 40)),
            CGSize(width: 48, height: 48)
        )
        XCTAssertEqual(measure(.plain, content: CGSize(width: 32, height: 32)), CGSize(width: 32, height: 32))
        XCTAssertEqual(
            measure(NookStandardCompanionStyle(height: .fixed(30)), content: CGSize(width: 50, height: 40)).height,
            30
        )
        XCTAssertEqual(
            measure(.standard, content: CGSize(width: 50, height: 60)).height,
            68,
            "content taller than the shared height grows the surface"
        )
    }

    func testPresenceEffectsWaitWhereTheyFoldTo() {
        typealias Modifier = NookCompanionPresenceModifier
        let hidden = { (effect: NookCompanionPresence.Effect, edge: NookCompanionAnchor.Edge) in
            Modifier.transform(for: effect, isPresented: false, edge: edge, reduceMotion: false)
        }
        XCTAssertEqual(
            hidden(.fold(scale: 0.6, blur: 6), .below),
            Modifier.Transform(scale: 0.6, scaleAnchor: .top, blur: 6)
        )
        XCTAssertEqual(hidden(.fade, .below), Modifier.Transform())
        XCTAssertEqual(hidden(.slide(distance: 14), .below), Modifier.Transform(offset: CGSize(width: 0, height: -14)))
        XCTAssertEqual(hidden(.slide(distance: 14), .leading), Modifier.Transform(offset: CGSize(width: 14, height: 0)))
        XCTAssertEqual(
            hidden(.slide(distance: 14), .trailing),
            Modifier.Transform(offset: CGSize(width: -14, height: 0))
        )
        XCTAssertEqual(hidden(.pop(scale: 0.3), .trailing), Modifier.Transform(scale: 0.3))

        XCTAssertEqual(
            Modifier.transform(for: .pop(scale: 0.3), isPresented: true, edge: .below, reduceMotion: false),
            Modifier.Transform(),
            "a shown companion is untransformed"
        )
        XCTAssertEqual(
            Modifier.transform(for: .fold(scale: 0.6, blur: 6), isPresented: false, edge: .below, reduceMotion: true),
            Modifier.Transform(),
            "Reduce Motion leaves only the fade"
        )
    }

    func testPresencePresetsAndCurves() {
        XCTAssertEqual(NookCompanionPresence.fold.effect, .fold(scale: 0.6, blur: 6))
        XCTAssertNil(NookCompanionPresence.fold.animation, "the default follows the chrome's curve")
        XCTAssertEqual(NookCompanionPresence.slide.effect, .slide(distance: 14))
        let bouncy = NookCompanionPresence.pop.animation(.bouncy)
        XCTAssertEqual(bouncy.effect, NookCompanionPresence.pop.effect)
        XCTAssertEqual(bouncy.animation, .bouncy)
        XCTAssertNotEqual(bouncy, .pop)

        let surface = companion("a")
        XCTAssertEqual(surface.presence, .fold)
        XCTAssertEqual(surface.size, .regular)
        XCTAssertEqual(surface.style.base as? NookStandardCompanionStyle, .standard)
    }

    /// Companion content reads the size, the hover state, and the chrome's backdrop from the
    /// environment, the way NookKit's controls do.
    func testCompanionContentSeesItsSizeAndTheChromeBackdrop() {
        final class Seen {
            var size: NookCompanionSize?
            var backdrop: NookBackdrop?
            var isHovered: Bool?
        }
        struct Probe: View {
            let seen: Seen
            @Environment(\.nookCompanionSize) private var size
            @Environment(\.nookChromeBackdrop) private var backdrop
            @Environment(\.nookCompanionIsHovered) private var isHovered

            var body: some View {
                seen.size = size
                seen.backdrop = backdrop
                seen.isHovered = isHovered
                return Color.clear.frame(width: 10, height: 10)
            }
        }

        func render(_ surface: NookCompanionSurface, heightLimit: CGFloat?) {
            let item = NookCompanionItemView(
                surface: surface,
                chromeState: .compact,
                backdrop: .solid(.blue),
                chromeBackdrop: .solid(.red),
                heightLimit: heightLimit,
                reduceMotion: false,
                presenceAnimation: .default,
                onHover: { _ in },
                onVisibilityRestriction: { _ in },
                onExtent: { _ in }
            )
            _ = ImageRenderer(content: item.frame(width: 80, height: 80)).nsImage
        }

        let seen = Seen()
        let probe = NookCompanionSurface(id: "probe", visibility: .both, size: .large) { Probe(seen: seen) }
        render(probe, heightLimit: nil)
        XCTAssertEqual(seen.size, .large)
        XCTAssertEqual(seen.backdrop, .solid(.red))
        XCTAssertEqual(seen.isHovered, false)

        let fitted = Seen()
        render(
            NookCompanionSurface(id: "fitted", anchor: .trailing, visibility: .both) { Probe(seen: fitted) },
            heightLimit: 32
        )
        XCTAssertEqual(fitted.size, .small, "content beside the compact pill sees the fitted size")
    }

    /// The outline casts the shadow, and nothing is drawn under the shape itself, so a surface
    /// with no fill still shows its shadow or glow.
    func testOutlineShadowDrawsOnlyOutsideItsShape() throws {
        typealias Alphas = (center: CGFloat, above: CGFloat, below: CGFloat, far: CGFloat)
        func alphas(_ shadow: NookOutlineShadow) throws -> Alphas {
            let view = Color.clear
                .frame(width: 40, height: 40)
                .background { shadow }
                .padding(20)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            XCTAssertEqual(bitmap.pixelsWide, 80)
            func alpha(_ x: Int, _ y: Int) -> CGFloat {
                bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            }
            return (alpha(40, 40), alpha(40, 17), alpha(40, 62), alpha(1, 1))
        }

        let plain = try alphas(NookOutlineShadow(Circle(), color: .black, radius: 4))
        XCTAssertEqual(plain.center, 0, "nothing under the shape")
        XCTAssertGreaterThan(plain.above, 0.05, "a shadow just outside it")
        XCTAssertGreaterThan(plain.below, 0.05)
        XCTAssertEqual(plain.far, 0, "and none far from it")

        let faded = try alphas(NookOutlineShadow(Circle(), color: .black, radius: 4, fade: .toClear, edge: .below))
        XCTAssertGreaterThan(faded.above, 0.05, "full strength on the chrome's side")
        XCTAssertLessThan(faded.below, 0.01, "thinned away to nothing on the far side")
        XCTAssertEqual(faded.center, 0)
    }

    // MARK: - Rim glow

    func testRimRenderingDefaultsToALineAndABreathingHalo() {
        let rendering = NookRimGlowRendering.resolve(
            style: .standard,
            reduceMotion: false,
            increaseContrast: false,
            reduceTransparency: false
        )
        XCTAssertEqual(rendering.lineWidth, 1.5)
        XCTAssertEqual(rendering.lineOpacity, 0.9)
        XCTAssertEqual(rendering.haloRadius, 8)
        XCTAssertTrue(rendering.drawsHalo)
        XCTAssertTrue(rendering.pulses)
    }

    func testReduceMotionStillsTheHalo() {
        let rendering = NookRimGlowRendering.resolve(
            style: .standard,
            reduceMotion: true,
            increaseContrast: false,
            reduceTransparency: false
        )
        XCTAssertTrue(rendering.drawsHalo)
        XCTAssertFalse(rendering.pulses)
    }

    func testIncreaseContrastTradesTheHaloForABolderOpaqueLine() {
        let rendering = NookRimGlowRendering.resolve(
            style: .standard,
            reduceMotion: false,
            increaseContrast: true,
            reduceTransparency: false
        )
        XCTAssertEqual(rendering.lineWidth, 3)
        XCTAssertEqual(rendering.lineOpacity, 1)
        XCTAssertFalse(rendering.drawsHalo)
        XCTAssertFalse(rendering.pulses)
    }

    func testReduceTransparencyDropsTheTranslucentHalo() {
        let rendering = NookRimGlowRendering.resolve(
            style: .standard,
            reduceMotion: false,
            increaseContrast: false,
            reduceTransparency: true
        )
        XCTAssertFalse(rendering.drawsHalo)
        XCTAssertFalse(rendering.pulses)
        XCTAssertEqual(rendering.lineOpacity, 0.9, "the line itself stays")
    }

    func testRimStyleValuesAreClamped() {
        let style = NookRimGlowStyle(lineWidth: -2, glowRadius: 0, intensity: 3, pulses: true)
        let rendering = NookRimGlowRendering.resolve(
            style: style,
            reduceMotion: false,
            increaseContrast: false,
            reduceTransparency: false
        )
        XCTAssertEqual(rendering.lineWidth, 0)
        XCTAssertEqual(rendering.lineOpacity, 1)
        XCTAssertFalse(rendering.drawsHalo, "no radius, no halo")
        XCTAssertFalse(rendering.pulses, "nothing to breathe")
    }

    func testRimFollowsTheAmbientColorOnlyWhenAsked() {
        XCTAssertNil(NookRimGlowStyle.standard.color(rimColor: nil, ambientColor: .blue))
        XCTAssertEqual(NookRimGlowStyle.standard.color(rimColor: .red, ambientColor: .blue), .red)

        let following = NookRimGlowStyle(followsAmbientColor: true)
        XCTAssertEqual(following.color(rimColor: nil, ambientColor: .blue), .blue)
        XCTAssertEqual(following.color(rimColor: .red, ambientColor: .blue), .red, "a published rim color wins")
    }

    func testRimPreferenceKeepsTheLastPublishedColor() {
        var value: Color? = nil
        NookRimGlowPreferenceKey.reduce(value: &value) { .blue }
        NookRimGlowPreferenceKey.reduce(value: &value) { nil }
        XCTAssertEqual(value, .blue)
    }

    // MARK: - Scroll edge fade

    func testFadeKeepsOnlyTheEdgesAlongTheScrollAxes() {
        let fade = NookScrollEdgeFade.standard
        XCTAssertEqual(fade.restricted(to: .vertical).edges, .vertical)
        XCTAssertEqual(fade.restricted(to: .horizontal).edges, .horizontal)
        XCTAssertEqual(fade.restricted(to: [.horizontal, .vertical]).edges, .all)
        XCTAssertEqual(NookScrollEdgeFade(edges: .bottom).restricted(to: .horizontal).edges, [])
        XCTAssertEqual(fade.restricted(to: .vertical).length, fade.length)
    }

    func testFadeSplitsBetweenTheSystemEffectAndTheMask() {
        let split = NookScrollEdgeFade(edges: [.bottom, .trailing], length: 24).systemAndMaskedEdges
        XCTAssertEqual(split.system, NookScrollEdgeFade(edges: .bottom, length: 24))
        XCTAssertEqual(split.masked, NookScrollEdgeFade(edges: .trailing, length: 24))
    }

    func testSystemBarNeverLaysOutSixteenPointsTall() {
        XCTAssertEqual(NookScrollEdgeFade.systemBarLength(for: 16), 17)
        XCTAssertEqual(NookScrollEdgeFade.systemBarLength(for: 16.25), 17)
        XCTAssertEqual(NookScrollEdgeFade.systemBarLength(for: 15.5), 17)
        XCTAssertEqual(NookScrollEdgeFade.systemBarLength(for: 20), 20)
        XCTAssertEqual(NookScrollEdgeFade.systemBarLength(for: 12), 12)
    }

    func testEmptyFadesChangeNothing() {
        XCTAssertTrue(NookScrollEdgeFade(edges: [], length: 20).isEmpty)
        XCTAssertTrue(NookScrollEdgeFade(edges: .all, length: 0).isEmpty)
        XCTAssertFalse(NookScrollEdgeFade.standard.isEmpty)
        XCTAssertEqual(NookScrollEdgeFade.standard.length, 20)
    }
}
