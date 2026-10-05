// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// The theme's choreography tokens reaching the chrome: `motion.content.exit` and
/// `motion.content.enterDelay` on the surface's transitions, `motion.header.delay` on the top
/// bar, and `motion.stagger` through `nookStaggered(index:)`. Every one defaults to the chrome
/// as it was before the tokens were drawn.
@MainActor
final class NookChoreographyTests: XCTestCase {
    /// The coucou notch app's choreography, written with the framework's token ids.
    private func choreographedTheme() -> NookTheme {
        var theme = NookTheme()
        theme.tokens[.contentExit] = NookContentTransitionSpec(
            blur: 8,
            scaleX: 0.97,
            scaleY: 0.97,
            animation: .curve(.easeOut, duration: 0.16)
        )
        theme.tokens[.contentEnter] = NookContentTransitionSpec(
            blur: 8,
            scaleX: 0.97,
            scaleY: 0.97,
            animation: .curve(.easeOut, duration: 0.3)
        )
        theme.tokens[.contentEnterDelay] = 0.16
        theme.tokens[.headerDelay] = 0.3
        theme.tokens[.stagger] = 0.035
        return theme
    }

    // MARK: - Surface transitions

    func testTheStandardThemeKeepsTodaysContentTransitions() {
        let transitions = NookResolvedTokens.standard.transitionConfiguration
        let defaults = NookTransitionConfiguration()
        XCTAssertEqual(transitions.expandedContentTransition, defaults.expandedContentTransition)
        XCTAssertEqual(transitions.compactContentTransition, defaults.compactContentTransition)
        XCTAssertNil(transitions.expandedContentRemoval)
        XCTAssertNil(transitions.compactContentRemoval)
        XCTAssertEqual(transitions.expandedContentTransition.delay, 0)
        XCTAssertNil(transitions.expandedContentTransition.animation)
        XCTAssertNil(transitions.compactContentTransition.animation)
    }

    func testAThemesExitEnterDelayAndCurvesReachTheSurface() {
        let transitions = choreographedTheme().resolvedTokens().transitionConfiguration
        XCTAssertEqual(
            transitions.expandedContentTransition,
            NookContentTransition(blurRadius: 8, scale: 0.97, animation: .easeOut(duration: 0.3), delay: 0.16)
        )
        XCTAssertEqual(
            transitions.expandedContentRemoval,
            NookContentTransition(blurRadius: 8, scale: 0.97, animation: .easeOut(duration: 0.16))
        )
        XCTAssertNil(transitions.compactContentRemoval)
    }

    /// With the standard theme the peek draws as the surface's own defaults, on the snappy spring.
    func testTheStandardThemeKeepsTheSurfacesPeekDefaults() {
        let tokens = NookResolvedTokens.standard
        XCTAssertEqual(tokens.style.peekBottomCornerRadius, NookStyle.standardPeekBottomCornerRadius)
        XCTAssertEqual(tokens.style.peekContentInsets, NookStyle.standardPeekContentInsets)
        XCTAssertEqual(tokens.style.peekMaxHeight, NookStyle.standardPeekMaxHeight)
        XCTAssertEqual(tokens.transitionConfiguration.peekContentTransition, .standardPeek)
        XCTAssertNil(tokens.transitionConfiguration.peekContentRemoval)
        XCTAssertEqual(tokens.transitionConfiguration.peekAnimation, tokens[.springSnappy])
    }

    /// A theme's peek shape, curve, and exit reach the surface.
    func testAThemesPeekTokensReachTheSurface() {
        var theme = NookTheme()
        theme.tokens[.peekBottomRadius] = 30
        theme.tokens[.peekMaxHeight] = 80
        theme.tokens[.peekInsetLeading] = 20
        theme.tokens[.transitionPeek] = NookAnimationSpec.curve(.easeOut, duration: 0.2)
        theme.tokens[.peekExit] = NookContentTransitionSpec(opacity: 0, blur: 2, scaleY: 1)
        let tokens = theme.resolvedTokens()

        XCTAssertEqual(tokens.style.peekBottomCornerRadius, 30)
        XCTAssertEqual(tokens.style.peekMaxHeight, 80)
        XCTAssertEqual(tokens.style.peekContentInsets.leading, 20)
        XCTAssertEqual(tokens.transitionConfiguration.peekAnimation, .easeOut(duration: 0.2))
        XCTAssertEqual(
            tokens.transitionConfiguration.peekContentRemoval,
            NookContentTransition(blurRadius: 2, scale: 1)
        )
    }

    /// The top bar's `motion.header.delay` becomes the surface's expanded entrance, so an
    /// awaited expand waits for the held-back top bar. The standard theme adds no wait.
    func testTheHeaderDelayIsTheExpandedEntrance() {
        XCTAssertEqual(NookResolvedTokens.standard.transitionConfiguration.expandedEntranceDuration, 0)
        let transitions = choreographedTheme().resolvedTokens().transitionConfiguration
        XCTAssertEqual(transitions.expandedEntranceDuration, 0.3, accuracy: 0.0001)
    }

    /// Host-supplied transitions replace the theme's curves, but the theme's header delay still
    /// holds the top bar back, so the coordinator keeps it in the entrance.
    func testHostTransitionsKeepTheThemesHeaderDelayInTheEntrance() {
        var configuration = NookConfiguration()
        configuration.chromeTheme = choreographedTheme()
        configuration.transitions = NookTransitionConfiguration(animationDuration: 0.7)
        let coordinator = AppCoordinator(configuration: configuration)
        coordinator.configureNotchAnimations()

        XCTAssertEqual(coordinator.surface.transitionConfiguration.animationDuration, 0.7)
        XCTAssertEqual(coordinator.surface.transitionConfiguration.expandedEntranceDuration, 0.3, accuracy: 0.0001)
    }

    /// A theme that writes only `motion.content.enter` leaves with it in reverse, as it did
    /// before exits were drawn.
    func testAThemeWithoutAnExitLeavesTheWayItArrives() {
        var theme = NookTheme()
        theme.tokens[.contentEnter] = NookContentTransitionSpec(blur: 3, scaleY: 0.9)
        let transitions = theme.resolvedTokens().transitionConfiguration
        XCTAssertNil(transitions.expandedContentRemoval)
        XCTAssertEqual(transitions.expandedContentTransition, NookContentTransition(blurRadius: 3, scale: 0.9))
    }

    func testTheCompactTransitionTakesItsCurve() {
        var theme = NookTheme()
        theme.tokens[.compactContent] = NookContentTransitionSpec(
            blur: 2,
            scaleX: 0.5,
            animation: .curve(.linear, duration: 0.2)
        )
        let transitions = theme.resolvedTokens().transitionConfiguration
        XCTAssertEqual(
            transitions.compactContentTransition,
            NookContentTransition(blurRadius: 2, scale: 0.5, animation: .linear(duration: 0.2))
        )
    }

    /// The theme file in the theming guide's Choreography section reads cleanly and means the
    /// same as the theme built in code here.
    func testTheGuidesThemeFileReadsAsWritten() throws {
        let json = """
            {
              "format": "opennook.theme",
              "version": 1,
              "name": "Cascade",
              "tokens": {
                "motion.content.exit": { "opacity": 0, "blur": 8, "scale": 0.97, "animation": { "curve": "easeOut", "duration": 0.16 } },
                "motion.content.enter": { "opacity": 0, "blur": 8, "scale": 0.97, "animation": { "curve": "easeOut", "duration": 0.3 } },
                "motion.content.enterDelay": 0.16,
                "motion.header.delay": 0.3,
                "motion.stagger": 0.035,
                "sound.open": { "system": "Pop", "volume": 0.5 },
                "sound.close": { "system": "Bottle", "volume": 0.4 },
                "sound.peek": { "system": "Tink", "volume": 0.4 },
                "sound.alert": { "system": "Sosumi" },
                "sound.finish": { "system": "Glass", "volume": 0.6 },
                "sound.hover": { "system": "Morse", "volume": 0.2 }
              },
              "soundVolume": 0.8
            }
            """
        let result = try NookThemeCoder.decode(json)
        XCTAssertEqual(result.issues, [])
        let tokens = result.theme.resolvedTokens()
        let transitions = tokens.transitionConfiguration
        let expected = choreographedTheme().resolvedTokens().transitionConfiguration
        XCTAssertEqual(transitions.expandedContentTransition, expected.expandedContentTransition)
        XCTAssertEqual(transitions.expandedContentRemoval, expected.expandedContentRemoval)
        XCTAssertEqual(tokens[.headerDelay], 0.3, accuracy: 1e-9)
        XCTAssertEqual(tokens[.stagger], 0.035, accuracy: 1e-9)
        XCTAssertEqual(tokens.sound(.open), .system("Pop", volume: 0.4))
        XCTAssertEqual(tokens.sound(.alert), .system("Sosumi", volume: 0.8))
        XCTAssertNil(tokens.sound(.feedback))
    }

    // MARK: - Entrance timing

    func testAnEntranceCountsFromTheContentsArrival() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let entrance = NookContentEntrance(start: start, delay: 0.16)
        XCTAssertEqual(
            NookEntranceModifier.scheduledEntrance(entrance: entrance, appearedAt: start + 5, offset: 0.3),
            start + 0.46,
            "the header waits its delay after the content's own"
        )
        XCTAssertEqual(
            NookEntranceModifier.scheduledEntrance(entrance: nil, appearedAt: start, offset: 0.07),
            start + 0.07,
            "outside an entrance the wait counts from the view's own appearance"
        )
    }

    // MARK: - Rendering

    private func bitmap(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: 60, height: 30))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the view did not render")
        return NSBitmapImageRep(cgImage: image)
    }

    private func bytes(_ image: NSBitmapImageRep) -> [UInt8] {
        guard let data = image.bitmapData else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: image.bytesPerRow * image.pixelsHigh))
    }

    private func maxAlpha(_ image: NSBitmapImageRep) -> CGFloat {
        var alpha: CGFloat = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                alpha = max(alpha, image.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        return alpha
    }

    private var sample: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red)
            Text("Row").foregroundStyle(Color.blue)
        }
    }

    private func entering(
        _ timing: NookEntranceModifier.Timing,
        tokens: NookResolvedTokens,
        entrance: NookContentEntrance? = nil
    ) -> some View {
        sample
            .modifier(NookEntranceModifier(timing: timing))
            .environment(\.nookThemeTokens, tokens)
            .environment(\.nookContentEntrance, entrance)
    }

    /// At the default tokens the header and a staggered row are drawn exactly as without the
    /// modifier.
    func testTheDefaultTokensDrawTheViewUnchanged() throws {
        let plain = bytes(try bitmap(sample))
        for timing in [NookEntranceModifier.Timing.header, .staggered(index: 0), .staggered(index: 5)] {
            XCTAssertEqual(bytes(try bitmap(entering(timing, tokens: .standard))), plain, "\(timing)")
        }
        XCTAssertEqual(bytes(try bitmap(sample.nookStaggered(index: 3))), plain)
    }

    /// Held back, a view takes the enter transition's start: with an enter opacity of 0,
    /// nothing shows. Not held back, it is drawn exactly as without the modifier.
    func testAHeldBackViewIsDrawnAtTheEnterTransitionsStart() throws {
        let transition = choreographedTheme().resolvedTokens().transition(.contentEnter)
        let held = sample.modifier(NookEntranceAppearance(transition: transition, isHeldBack: true))
        XCTAssertEqual(maxAlpha(try bitmap(held)), 0)
        let shown = sample.modifier(NookEntranceAppearance(transition: transition, isHeldBack: false))
        XCTAssertEqual(bytes(try bitmap(shown)), bytes(try bitmap(sample)))

        // A transition that keeps some opacity shows the view faded, not gone.
        var faded = NookTheme()
        faded.tokens[.contentEnter] = NookContentTransitionSpec(opacity: 0.5)
        let half = sample.modifier(
            NookEntranceAppearance(transition: faded.resolvedTokens().transition(.contentEnter), isHeldBack: true)
        )
        XCTAssertEqual(maxAlpha(try bitmap(half)), 0.5, accuracy: 0.02)
    }

    /// Only its own token makes a view wait: a stagger does not hold the header back, and a
    /// header delay does not hold a row back. A row's turn is its index times the stagger.
    func testEachTimingFollowsItsOwnToken() {
        let standard = NookResolvedTokens.standard
        XCTAssertFalse(NookEntranceModifier.waits(.header, tokens: standard))
        XCTAssertFalse(NookEntranceModifier.waits(.staggered(index: 3), tokens: standard))

        var stagger = NookTheme()
        stagger.tokens[.stagger] = 0.05
        stagger.tokens[.contentEnterDelay] = 0.2
        let staggered = stagger.resolvedTokens()
        XCTAssertFalse(NookEntranceModifier.waits(.header, tokens: staggered))
        XCTAssertTrue(NookEntranceModifier.waits(.staggered(index: 0), tokens: staggered))
        XCTAssertEqual(NookEntranceModifier.offset(.staggered(index: 3), tokens: staggered), 0.15, accuracy: 1e-9)
        XCTAssertEqual(NookEntranceModifier.offset(.staggered(index: -2), tokens: staggered), 0)

        let choreographed = choreographedTheme().resolvedTokens()
        XCTAssertTrue(NookEntranceModifier.waits(.header, tokens: choreographed))
        XCTAssertEqual(NookEntranceModifier.offset(.header, tokens: choreographed), 0.3, accuracy: 1e-9)

        var header = NookTheme()
        header.tokens[.headerDelay] = 0.3
        XCTAssertFalse(NookEntranceModifier.waits(.staggered(index: 2), tokens: header.resolvedTokens()))
    }
}
