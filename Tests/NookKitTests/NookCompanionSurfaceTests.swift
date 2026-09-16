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

    func testRowsGroupByAnchorInFirstAppearanceOrder() {
        let rows = NookCompanionRow.rows(from: [
            companion("a"),
            companion("b", anchor: .trailing),
            companion("c"),
            companion("d", anchor: .below(alignment: .start)),
        ])
        XCTAssertEqual(rows.map(\.anchor), [.below, .trailing, .below(alignment: .start)])
        XCTAssertEqual(rows.map { $0.surfaces.map(\.id) }, [["a", "c"], ["b"], ["d"]])
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
        typealias Item = NookCompanionRowLayout.Item
        let items = [
            Item(size: CGSize(width: 100, height: 50), spacing: 10, isPresented: true),
            Item(size: CGSize(width: 40, height: 52), spacing: 12, isPresented: true),
        ]
        // The first spacing is inside its height already; the second is also a gap.
        XCTAssertEqual(NookCompanionRowLayout.size(of: items, edge: .below), CGSize(width: 152, height: 52))

        let bounds = CGRect(x: 0, y: 0, width: 152, height: 52)
        let frames = NookCompanionRowLayout.frames(of: items, anchor: .below, in: bounds)
        XCTAssertEqual(
            frames,
            [
                CGRect(x: 0, y: 0, width: 100, height: 50),
                CGRect(x: 112, y: 0, width: 40, height: 52),
            ]
        )
    }

    func testHiddenCompanionsTakeNoRoomAndFoldIntoTheChromeEdge() {
        typealias Item = NookCompanionRowLayout.Item
        let items = [
            Item(size: CGSize(width: 60, height: 40), spacing: 8, isPresented: false),
            Item(size: CGSize(width: 100, height: 50), spacing: 8, isPresented: true),
        ]
        XCTAssertEqual(NookCompanionRowLayout.size(of: items, edge: .below), CGSize(width: 100, height: 50))

        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let frames = NookCompanionRowLayout.frames(of: items, anchor: .below, in: bounds)
        // The hidden one waits centered against the chrome's bottom edge; the shown one
        // gets the row to itself, with no gap for the hidden one before it.
        XCTAssertEqual(frames[0], CGRect(x: 20, y: 0, width: 60, height: 40))
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 0, width: 100, height: 50))

        XCTAssertEqual(
            NookCompanionRowLayout.size(of: [items[0]], edge: .trailing),
            .zero,
            "a row with nothing shown takes no room"
        )
    }

    func testLeadingRowGrowsOutwardFromTheChrome() {
        typealias Item = NookCompanionRowLayout.Item
        let items = [
            Item(size: CGSize(width: 30, height: 30), spacing: 6, isPresented: true),
            Item(size: CGSize(width: 50, height: 20), spacing: 6, isPresented: true),
        ]
        XCTAssertEqual(NookCompanionRowLayout.size(of: items, edge: .leading), CGSize(width: 80, height: 30))

        let bounds = CGRect(x: 0, y: 0, width: 80, height: 30)
        let frames = NookCompanionRowLayout.frames(of: items, anchor: .leading, in: bounds)
        // The first companion is nearest the chrome - the row's trailing end.
        XCTAssertEqual(frames[0], CGRect(x: 50, y: 0, width: 30, height: 30))
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 5, width: 50, height: 20), "centered on the cross axis")

        let folded = NookCompanionRowLayout.foldedFrame(
            size: CGSize(width: 50, height: 20),
            anchor: .leading(alignment: .end),
            in: bounds
        )
        XCTAssertEqual(folded, CGRect(x: 30, y: 10, width: 50, height: 20), "folds against the chrome side")
    }

    func testTrailingRowAlignsOnTheCrossAxis() {
        typealias Item = NookCompanionRowLayout.Item
        let items = [
            Item(size: CGSize(width: 30, height: 40), spacing: 6, isPresented: true),
            Item(size: CGSize(width: 30, height: 10), spacing: 6, isPresented: true),
        ]
        let bounds = CGRect(x: 100, y: 0, width: 60, height: 40)
        let top = NookCompanionRowLayout.frames(of: items, anchor: .trailing(alignment: .start), in: bounds)
        let bottom = NookCompanionRowLayout.frames(of: items, anchor: .trailing(alignment: .end), in: bounds)
        XCTAssertEqual(top[1], CGRect(x: 130, y: 0, width: 30, height: 10))
        XCTAssertEqual(bottom[1], CGRect(x: 130, y: 30, width: 30, height: 10))
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
        XCTAssertEqual(nook.companionRows.map(\.anchor), [.below])
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
