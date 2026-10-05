// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit
import SwiftUI
import XCTest

@testable import NookSurface

/// Coverage for the surface's visual customization seams: gradient, mesh, and custom
/// backdrops and their Reduce Transparency rule, the exposed vibrancy and glass knobs, the
/// compact and floating radii and custom outlines, content transitions (asymmetric and delayed
/// arrival included), the hover wash color, the chrome shadow, the feedback style and pulse,
/// the ambient wash, and the hover haptic.
///
/// Every seam defaults to the look the surface had before it existed. Where a piece renders
/// without an `NSView`, the defaults are pinned by rendering the new code next to a copy of
/// the code it replaced and comparing the pixels.
@MainActor
final class NookSurfaceVisualSeamsTests: XCTestCase {

    // MARK: - Rendering helpers

    private func bitmap(_ view: some View, size: CGSize = CGSize(width: 120, height: 80)) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the view did not render")
        return NSBitmapImageRep(cgImage: image)
    }

    /// Asserts the two views render to the same pixels, give or take `tolerance` per 8-bit
    /// channel. A blur can come back a step off between two renders of one view, so effects
    /// with a blur allow a step or two.
    private func assertSamePixels(
        _ lhs: some View,
        _ rhs: some View,
        size: CGSize = CGSize(width: 120, height: 80),
        tolerance: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let a = try bitmap(lhs, size: size)
        let b = try bitmap(rhs, size: size)
        XCTAssertEqual(a.pixelsWide, b.pixelsWide, file: file, line: line)
        XCTAssertEqual(a.pixelsHigh, b.pixelsHigh, file: file, line: line)
        XCTAssertLessThanOrEqual(maxChannelDifference(a, b), tolerance, "renders differ", file: file, line: line)
    }

    /// The largest difference between the two bitmaps in any 8-bit channel of any pixel.
    private func maxChannelDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
            let pa = a.bitmapData, let pb = b.bitmapData, a.bytesPerRow == b.bytesPerRow
        else { return .max }
        var worst = 0
        for index in 0..<(a.bytesPerRow * a.pixelsHigh) {
            worst = max(worst, abs(Int(pa[index]) - Int(pb[index])))
        }
        return worst
    }

    private func color(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
    }

    // MARK: - Backdrop: existing cases render as before

    func testVibrancyDefaultsKeepTheBlackDarken() throws {
        let spec = NookBackdrop.Vibrancy(darkenOpacity: 0.4)
        XCTAssertEqual(spec.darkenColor, .black)
        try assertSamePixels(
            NookBackdropFill(backdrop: .vibrancy(spec), shape: Rectangle()),
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                Color.black.opacity(0.4)
            }
        )
    }

    func testVibrancyDarkenColorLightens() throws {
        let image = try bitmap(
            NookBackdropFill(
                backdrop: .vibrancy(.init(darkenOpacity: 1, darkenColor: .white)),
                shape: Rectangle()
            )
        )
        XCTAssertGreaterThan(color(image, 60, 40).redComponent, 0.95)
    }

    func testLiquidGlassDefaultsMatchTheHistoricalKnobs() {
        let glass = NookBackdrop.LiquidGlass()
        XCTAssertEqual(glass.variant, .regular)
        XCTAssertEqual(glass.fallbackMaterial, .hudWindow)
        XCTAssertEqual(glass.highlightColor, .white)
        XCTAssertEqual(glass.rimWidth, 1)
        XCTAssertEqual(NookBackdrop.LiquidGlass(rimWidth: -3).rimWidth, 0)
        XCTAssertNotEqual(glass, NookBackdrop.LiquidGlass(variant: .clear))
    }

    /// The default glass, through whichever path this system takes, renders as the code it
    /// replaced did.
    func testLiquidGlassDefaultRendersAsBefore() throws {
        let glass = NookBackdrop.LiquidGlass(shading: .notchFade())
        let shape = RoundedRectangle(cornerRadius: 12)
        try assertSamePixels(
            NookBackdropFill(backdrop: .liquidGlass(glass), shape: shape),
            HistoricalLiquidGlass(glass: glass, shape: shape)
        )
        // Not vacuous: the shading at least draws.
        let image = try bitmap(NookBackdropFill(backdrop: .liquidGlass(glass), shape: shape))
        XCTAssertGreaterThan(color(image, 60, 2).alphaComponent, 0.5)
    }

    // MARK: - Backdrop: gradients

    func testGradientBackdropPaintsItsColors() throws {
        let backdrop = NookBackdrop.gradient(
            .linear(Gradient(colors: [.red, .blue]), startPoint: .leading, endPoint: .trailing)
        )
        let image = try bitmap(
            NookBackdropFill(backdrop: backdrop, shape: Rectangle(), reduceTransparencyOverride: false)
        )
        XCTAssertGreaterThan(color(image, 2, 40).redComponent, 0.9)
        XCTAssertGreaterThan(color(image, 117, 40).blueComponent, 0.9)
    }

    func testEveryGradientLayoutRenders() throws {
        let gradient = Gradient(colors: [.green, .green])
        let fills: [NookBackdrop.GradientFill] = [
            .linear(gradient),
            .radial(gradient, endRadius: 200),
            .elliptical(gradient, endRadiusFraction: 1),
            .angular(gradient),
        ]
        for fill in fills {
            let image = try bitmap(
                NookBackdropFill(backdrop: .gradient(fill), shape: Rectangle(), reduceTransparencyOverride: false)
            )
            XCTAssertGreaterThan(color(image, 60, 40).greenComponent, 0.4, "\(fill.layout)")
            XCTAssertGreaterThan(color(image, 60, 40).alphaComponent, 0.99, "\(fill.layout)")
        }
    }

    /// A translucent gradient lets the desktop through until Reduce Transparency is on, when
    /// every stop is painted opaque with its hue kept.
    func testGradientBackdropGoesOpaqueUnderReduceTransparency() throws {
        let backdrop = NookBackdrop.gradient(.linear(Gradient(colors: [.red.opacity(0.4), .red.opacity(0.4)])))
        let translucent = try bitmap(
            NookBackdropFill(backdrop: backdrop, shape: Rectangle(), reduceTransparencyOverride: false)
        )
        XCTAssertLessThan(color(translucent, 60, 40).alphaComponent, 0.5)

        let opaque = try bitmap(
            NookBackdropFill(backdrop: backdrop, shape: Rectangle(), reduceTransparencyOverride: true)
        )
        XCTAssertEqual(color(opaque, 60, 40).alphaComponent, 1, accuracy: 0.01)
        XCTAssertGreaterThan(color(opaque, 60, 40).redComponent, 0.9)
    }

    func testGradientOpaqueKeepsStopLocations() {
        let fill = NookBackdrop.GradientFill.linear(
            Gradient(stops: [.init(color: .clear, location: 0.2), .init(color: .blue.opacity(0.1), location: 0.7)])
        )
        let opaque = fill.opaque(in: EnvironmentValues())
        XCTAssertEqual(opaque.gradient.stops.map(\.location), [0.2, 0.7])
        for stop in opaque.gradient.stops {
            XCTAssertEqual(stop.color.resolve(in: EnvironmentValues()).opacity, 1)
        }
        XCTAssertEqual(opaque.layout, fill.layout)
    }

    func testGradientBackdropEquality() {
        let gradient = Gradient(colors: [.red, .blue])
        XCTAssertEqual(NookBackdrop.gradient(.linear(gradient)), .gradient(.linear(gradient)))
        XCTAssertNotEqual(NookBackdrop.gradient(.linear(gradient)), .gradient(.angular(gradient)))
        XCTAssertNotEqual(NookBackdrop.gradient(.linear(gradient)), .solid(.red))
    }

    // MARK: - Backdrop: mesh

    private func mesh(_ colors: [Color], background: Color = .clear) -> MeshGradient {
        MeshGradient(
            width: 2,
            height: 2,
            points: [[0, 0], [1, 0], [0, 1], [1, 1]],
            colors: colors,
            background: background
        )
    }

    func testMeshBackdropPaintsAndValidatesItsGrid() throws {
        XCTAssertTrue(mesh([.red, .red, .red, .red]).hasConsistentGrid)
        XCTAssertFalse(mesh([.red, .red]).hasConsistentGrid)

        let image = try bitmap(
            NookBackdropFill(
                backdrop: .meshGradient(mesh([.red, .red, .red, .red])),
                shape: Rectangle(),
                reduceTransparencyOverride: false
            )
        )
        XCTAssertGreaterThan(color(image, 60, 40).redComponent, 0.9)

        // A mesh whose colors do not match its grid paints only its background.
        let broken = try bitmap(
            NookBackdropFill(
                backdrop: .meshGradient(mesh([.red], background: .blue)),
                shape: Rectangle(),
                reduceTransparencyOverride: false
            )
        )
        XCTAssertGreaterThan(color(broken, 60, 40).blueComponent, 0.9)
    }

    func testMeshBackdropGoesOpaqueUnderReduceTransparency() throws {
        let translucent = mesh(Array(repeating: Color.green.opacity(0.3), count: 4), background: .clear)
        let opaque = translucent.opaque(in: EnvironmentValues())
        XCTAssertEqual(opaque.background.resolve(in: EnvironmentValues()).opacity, 1)
        let image = try bitmap(
            NookBackdropFill(backdrop: .meshGradient(translucent), shape: Rectangle(), reduceTransparencyOverride: true)
        )
        XCTAssertEqual(color(image, 60, 40).alphaComponent, 1, accuracy: 0.01)
    }

    // MARK: - Backdrop: custom

    func testCustomBackdropEqualityIsByID() {
        let a = NookBackdrop.custom(.init(id: "aurora") { _ in Color.red })
        let b = NookBackdrop.custom(.init(id: "aurora") { _ in Color.blue })
        let c = NookBackdrop.custom(.init(id: "dusk") { _ in Color.red })
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testCustomBackdropDrawsTheHostViewWithItsContext() throws {
        let backdrop = NookBackdrop.custom(
            .init(id: "probe") { context in
                context.reduceTransparency ? Color.blue : Color.red
            }
        )
        let normal = try bitmap(
            NookBackdropFill(backdrop: backdrop, shape: Rectangle(), reduceTransparencyOverride: false)
        )
        XCTAssertGreaterThan(color(normal, 60, 40).redComponent, 0.9)
        let reduced = try bitmap(
            NookBackdropFill(backdrop: backdrop, shape: Rectangle(), reduceTransparencyOverride: true)
        )
        XCTAssertGreaterThan(color(reduced, 60, 40).blueComponent, 0.9)
    }

    func testCustomBackdropContextCarriesTheShape() throws {
        // The context's shape is the one the fill was given: fill it and only the circle shows.
        let backdrop = NookBackdrop.custom(.init(id: "outline") { context in context.shape.fill(Color.red) })
        let image = try bitmap(NookBackdropFill(backdrop: backdrop, shape: Circle(), reduceTransparencyOverride: false))
        XCTAssertGreaterThan(color(image, 60, 40).redComponent, 0.9)
        XCTAssertEqual(color(image, 1, 1).alphaComponent, 0)
    }

    // MARK: - Shape

    func testStyleDefaultsKeepTheHistoricalRadii() {
        let style = NookStyle.standard
        XCTAssertEqual(style.compactTopCornerRadius, 6)
        XCTAssertEqual(style.compactBottomCornerRadius, 14)
        XCTAssertNil(style.floatingExpandedTopCornerRadius)
        XCTAssertNil(style.floatingExpandedBottomCornerRadius)
        XCTAssertNil(style.floatingCompactCornerRadius)
        XCTAssertEqual(style.outline, .standard)

        // Floating fallbacks: the expanded card rounds every corner by the bottom radius, and
        // the compact pill is a capsule of at least 8.
        XCTAssertEqual(style.resolvedFloatingExpandedRadii.top, 20)
        XCTAssertEqual(style.resolvedFloatingExpandedRadii.bottom, 20)
        XCTAssertEqual(style.resolvedFloatingCompactRadius(pillHeight: 32), 16)
        XCTAssertEqual(style.resolvedFloatingCompactRadius(pillHeight: 10), 8)
    }

    func testStyleRadiiOverrideTheFallbacks() {
        var style = NookStyle.standard
        style.floatingExpandedTopCornerRadius = 10
        style.floatingCompactCornerRadius = 4
        XCTAssertEqual(style.resolvedFloatingExpandedRadii.top, 10)
        XCTAssertEqual(style.resolvedFloatingExpandedRadii.bottom, 20)
        XCTAssertEqual(style.resolvedFloatingCompactRadius(pillHeight: 32), 4)
        XCTAssertNotEqual(style, .standard)
    }

    /// The standard outline is the path the chrome always drew.
    func testStandardOutlineMatchesTheHistoricalNotchPath() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 180)
        let path = NookShape(form: .notch, topCornerRadius: 15, bottomCornerRadius: 20).path(in: rect)
        XCTAssertEqual(path, historicalNotchPath(in: rect, top: 15, bottom: 20))
    }

    func testCustomOutlineReceivesTheInterpolatedRadii() {
        let outline = NookOutline(id: "probe") { geometry in
            Path(
                CGRect(
                    x: geometry.topCornerRadius,
                    y: geometry.bottomCornerRadius,
                    width: geometry.form == .notch ? 1 : 2,
                    height: 1
                )
            )
        }
        var shape = NookShape(form: .floating, topCornerRadius: 6, bottomCornerRadius: 14, outline: outline)
        // What SwiftUI does mid-spring: hand the shape interpolated radii.
        shape.animatableData = .init(10, 17)
        let bounds = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect
        XCTAssertEqual(bounds, CGRect(x: 10, y: 17, width: 2, height: 1))
    }

    func testOutlineEqualityIsByID() {
        let a = NookOutline(id: "x") { _ in Path() }
        let b = NookOutline(id: "x") { geometry in Path(geometry.rect) }
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, .standard)
        XCTAssertEqual(
            NookShape(topCornerRadius: 1, bottomCornerRadius: 2),
            NookShape(topCornerRadius: 1, bottomCornerRadius: 2)
        )
        XCTAssertNotEqual(
            NookShape(topCornerRadius: 1, bottomCornerRadius: 2),
            NookShape(topCornerRadius: 1, bottomCornerRadius: 2, outline: a)
        )
    }

    func testFloatingInsetsFromTheStylesOwnRadii() {
        let insets = NookContentInsets.floatingExpanded(
            topCornerRadius: 10,
            bottomCornerRadius: 30,
            chromeSafeAreaInsets: NookStyle.standardExpandedContentInsets
        )
        XCTAssertEqual(insets.top, 10)
        XCTAssertEqual(insets.bottom, 22)
        XCTAssertEqual(insets.leading, 12)
        XCTAssertEqual(insets.trailing, 12)
    }

    // MARK: - Content transitions

    func testContentTransitionDefaultsMatchTheHistoricalTransitions() {
        let configuration = NookTransitionConfiguration()
        XCTAssertEqual(
            configuration.compactContentTransition,
            NookContentTransition(blurRadius: 6, scale: 0, fades: true)
        )
        XCTAssertEqual(
            configuration.expandedContentTransition,
            NookContentTransition(blurRadius: 6, scale: 0.72, fades: true)
        )
        XCTAssertEqual(NookContentTransition(blurRadius: -1, scale: -1).blurRadius, 0)
        XCTAssertEqual(NookContentTransition(blurRadius: -1, scale: -1).scale, 0)
        XCTAssertFalse(NookContentTransition.identity.fades)
        // Arrival and leaving are one transition on the surface's curve, arriving at once.
        XCTAssertNil(configuration.compactContentRemoval)
        XCTAssertNil(configuration.expandedContentRemoval)
        for transition in [NookContentTransition.standardCompact, .standardExpanded, .opacity, .identity] {
            XCTAssertNil(transition.animation)
            XCTAssertEqual(transition.delay, 0)
        }
        XCTAssertEqual(NookContentTransition(delay: -1).delay, 0)
        XCTAssertEqual(NookContentTransition(delay: .infinity).delay, 0)
        XCTAssertEqual(NookContentTransition(delay: .nan).delay, 0)
    }

    /// The default configuration plans the single, reversible transition the surface always
    /// played, which builds through the historical code path.
    func testDefaultContentTransitionsPlanTheHistoricalTransition() {
        let configuration = NookTransitionConfiguration()
        for (insertion, removal) in [
            (configuration.expandedContentTransition, configuration.expandedContentRemoval),
            (configuration.compactContentTransition, configuration.compactContentRemoval),
        ] {
            let plan = NookContentTransitionPlan.plan(
                insertion: insertion,
                removal: removal,
                surfaceAnimation: .spring(response: 0.54, dampingFraction: 0.86)
            )
            XCTAssertTrue(plan.isHistorical)
            XCTAssertEqual(plan.insertion, insertion)
            XCTAssertEqual(plan.removal, insertion)
            XCTAssertNil(plan.insertionAnimation)
            XCTAssertNil(plan.removalAnimation)
        }
    }

    /// A delay with no curve of its own waits on the surface's curve; leaving does not wait.
    func testAnEnterDelayWaitsOnTheSurfaceCurve() {
        let surface = Animation.spring(response: 0.54, dampingFraction: 0.86)
        let insertion = NookContentTransition(blurRadius: 6, scale: 0.72, delay: 0.16)
        let plan = NookContentTransitionPlan.plan(insertion: insertion, removal: nil, surfaceAnimation: surface)
        XCTAssertFalse(plan.isHistorical)
        XCTAssertEqual(plan.insertionAnimation, surface.delay(0.16))
        XCTAssertEqual(plan.removal, insertion, "leaves the way it arrived")
        XCTAssertNil(plan.removalAnimation, "and on the transaction's curve, without waiting")
    }

    /// Arrival and leaving take their own transitions and curves; a removal's delay is ignored.
    func testRemovalAndCurvesAreSeparate() {
        let surface = Animation.spring(response: 0.54, dampingFraction: 0.86)
        let insertion = NookContentTransition(
            blurRadius: 8,
            scale: 0.97,
            animation: .easeOut(duration: 0.3),
            delay: 0.16
        )
        let removal = NookContentTransition(blurRadius: 8, scale: 0.97, animation: .easeOut(duration: 0.16), delay: 5)
        let plan = NookContentTransitionPlan.plan(insertion: insertion, removal: removal, surfaceAnimation: surface)
        XCTAssertFalse(plan.isHistorical)
        XCTAssertEqual(plan.insertion, insertion)
        XCTAssertEqual(plan.removal, removal)
        XCTAssertEqual(plan.insertionAnimation, Animation.easeOut(duration: 0.3).delay(0.16))
        XCTAssertEqual(plan.removalAnimation, .easeOut(duration: 0.16))

        // A removal alone, with no curve of its own, leaves on the transaction's curve.
        let exitOnly = NookContentTransitionPlan.plan(
            insertion: .standardExpanded,
            removal: .opacity,
            surfaceAnimation: surface
        )
        XCTAssertFalse(exitOnly.isHistorical)
        XCTAssertNil(exitOnly.insertionAnimation)
        XCTAssertNil(exitOnly.removalAnimation)
    }

    /// The configuration's new fields keep its initializer source compatible and default to
    /// today's behavior.
    func testTransitionConfigurationTakesARemoval() {
        let removal = NookContentTransition(blurRadius: 8, scale: 0.97)
        let configuration = NookTransitionConfiguration(
            compactContentRemoval: .opacity,
            expandedContentRemoval: removal
        )
        XCTAssertEqual(configuration.compactContentRemoval, .opacity)
        XCTAssertEqual(configuration.expandedContentRemoval, removal)
        XCTAssertEqual(configuration.expandedContentTransition, .standardExpanded)
        XCTAssertEqual(configuration.compactContentTransition, .standardCompact)
    }

    // MARK: - Hover wash

    func testHoverWashColorDefaultsToWhite() {
        XCTAssertEqual(NookStandardCompanionStyle.Hover().washColor, .white)
        XCTAssertEqual(NookStandardCompanionStyle.Hover.highlight.washColor, .white)
        XCTAssertNotEqual(NookStandardCompanionStyle.Hover(wash: 0.1, washColor: .black), .init(wash: 0.1))
    }

    // MARK: - Chrome shadow

    func testChromeShadowIsOffByDefault() {
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") })
        XCTAssertNil(nook.chromeShadow)
        XCTAssertEqual(nook.ambientWash, .standard)
        XCTAssertEqual(nook.hoverHaptic, .standard)
    }

    /// The shadow shows outside the outline only, and the notch form fades it across the
    /// menu-bar band at the top.
    func testChromeShadowDrawsOutsideTheOutlineAndFadesAtTheTop() throws {
        func render(_ form: NookChromeForm, topFade: CGFloat?) throws -> NSBitmapImageRep {
            let shadow = NookChromeShadow(color: .black, radius: 4, y: 0)
            let view = Color.clear
                .frame(width: 80, height: 40)
                .background {
                    NookChromeShadowView(
                        shadow: shadow,
                        shape: NookShape(form: form, topCornerRadius: 0, bottomCornerRadius: 0),
                        topFadeHeight: topFade
                    )
                }
                .frame(width: 120, height: 80)
            return try bitmap(view)
        }

        let floating = try render(.floating, topFade: nil)
        XCTAssertEqual(color(floating, 60, 40).alphaComponent, 0, "nothing under the chrome")
        XCTAssertGreaterThan(color(floating, 60, 62).alphaComponent, 0.05, "a shadow below it")
        XCTAssertGreaterThan(color(floating, 60, 18).alphaComponent, 0.05, "and above a floating chrome")
        XCTAssertEqual(color(floating, 2, 2).alphaComponent, 0, "and none far away")

        let notch = try render(.notch, topFade: 20)
        XCTAssertGreaterThan(color(notch, 60, 62).alphaComponent, 0.05, "a shadow below the notch chrome")
        XCTAssertEqual(color(notch, 60, 18).alphaComponent, 0, "none above the top of the screen")
        XCTAssertLessThan(
            color(notch, 18, 21).alphaComponent,
            color(notch, 18, 50).alphaComponent / 4,
            "faded beside the ears, where the chrome meets the menu bar"
        )
    }

    // MARK: - Feedback

    func testFeedbackStyleDefaults() {
        let style = NookFeedbackStyle.standard
        XCTAssertEqual(style.color, Color(nsColor: .controlAccentColor))
        XCTAssertEqual(style.coreColor, .white.opacity(0.75))
        XCTAssertNil(style.bandGradient)
        XCTAssertEqual(style.lineWidth, 6)
        XCTAssertEqual(style.pulseLineWidth, 4)
        XCTAssertEqual(style.glow, .standard)
        XCTAssertEqual(style.glow?.width, 8)
        XCTAssertEqual(style.glow?.radius, 3)
        XCTAssertEqual(style.blendMode, .plusLighter)
        XCTAssertEqual(style.resolvedGlowColor(.standard), Color(nsColor: .controlAccentColor).opacity(0.55))
    }

    func testPlayFeedbackWithATintUsesTheStandardStyleInThatColor() {
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") })
        nook.playFeedback(.shimmer, tint: .green)
        var expected = NookFeedbackStyle.standard
        expected.color = .green
        XCTAssertEqual(nook.pendingFeedback?.style, expected)

        let custom = NookFeedbackStyle(color: .orange, glow: nil, blendMode: .normal)
        nook.playFeedback(.pulse, style: custom)
        XCTAssertEqual(nook.pendingFeedback?.style, custom)
        XCTAssertEqual(nook.pendingFeedback?.effect, .pulse)
    }

    private func event(_ effect: NookFeedback, style: NookFeedbackStyle) -> NookFeedbackEvent {
        NookFeedbackEvent(
            id: UUID(),
            startedAt: Date(),
            effect: effect,
            duration: 1,
            style: style,
            respectsReduceMotion: true,
            repeats: false
        )
    }

    private var feedbackShape: NookShape {
        NookShape(form: .floating, topCornerRadius: 12, bottomCornerRadius: 12)
    }

    /// The default shimmer and its Reduce Motion pulse render as the code they replaced did.
    func testDefaultFeedbackRendersAsBefore() throws {
        let style = NookFeedbackStyle(color: .blue)
        for reduceMotion in [false, true] {
            for progress in [0.25, 0.5, 0.8] {
                let overlay = NookFeedbackOverlay(event: nil, shape: feedbackShape, reduceMotion: reduceMotion)
                try assertSamePixels(
                    overlay.overlayContent(event: event(.shimmer, style: style), progress: progress)
                        .background(Color.black),
                    HistoricalFeedback(
                        tint: .blue,
                        progress: progress,
                        reduceMotion: reduceMotion,
                        shape: feedbackShape
                    )
                    .background(Color.black),
                    tolerance: 2
                )
            }
        }
    }

    /// The pulse is the Reduce Motion rendering, with or without Reduce Motion.
    func testPulseRendersThePerimeterWithoutASweep() throws {
        let style = NookFeedbackStyle(color: .blue)
        let overlay = NookFeedbackOverlay(event: nil, shape: feedbackShape, reduceMotion: false)
        try assertSamePixels(
            overlay.overlayContent(event: event(.pulse, style: style), progress: 0.5).background(Color.black),
            HistoricalFeedback(tint: .blue, progress: 0.5, reduceMotion: true, shape: feedbackShape)
                .background(Color.black)
        )
    }

    func testFeedbackStyleChangesTheRender() throws {
        let overlay = NookFeedbackOverlay(event: nil, shape: feedbackShape, reduceMotion: false)
        let standard = try bitmap(
            overlay.overlayContent(event: event(.shimmer, style: NookFeedbackStyle(color: .blue)), progress: 0.5)
                .background(Color.black)
        )
        let restyled = try bitmap(
            overlay.overlayContent(
                event: event(.shimmer, style: NookFeedbackStyle(color: .red, lineWidth: 12, glow: nil)),
                progress: 0.5
            )
            .background(Color.black)
        )
        XCTAssertNotEqual(standard.tiffRepresentation, restyled.tiffRepresentation)
    }

    // MARK: - Ambient wash

    func testAmbientWashDefaultRendersAsBefore() throws {
        try assertSamePixels(
            NookAmbientColorBackground(color: .purple),
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.34),
                    Color.purple.opacity(0.16),
                    Color.purple.opacity(0.06),
                    Color.purple.opacity(0.02),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    func testAmbientWashSpacesOpacitiesEvenly() {
        let wash = NookAmbientWash(opacities: [1, 0.5, 2], startPoint: .leading, endPoint: .trailing)
        XCTAssertEqual(wash.stops.map(\.location), [0, 0.5, 1])
        XCTAssertEqual(wash.stops.map(\.opacity), [1, 0.5, 1])
        XCTAssertEqual(NookAmbientWash(opacities: [0.3]).stops.map(\.location), [0])
        XCTAssertTrue(NookAmbientWash(opacities: []).stops.isEmpty)
    }

    func testAmbientWashShapesTheRender() throws {
        let wash = NookAmbientWash(opacities: [1, 1], startPoint: .top, endPoint: .bottom)
        let image = try bitmap(NookAmbientColorBackground(color: .red, wash: wash))
        XCTAssertEqual(color(image, 60, 70).alphaComponent, 1, accuracy: 0.01)
    }

    // MARK: - Hover haptic

    func testHoverHapticPlaysTheConfiguredPattern() {
        let nook = Nook(hoverBehavior: [.hapticFeedback], expanded: { Text("x") })
        let performer = RecordingHapticPerformer()
        nook.hapticPerformer = performer

        nook.performHoverHapticIfEnabled()
        XCTAssertEqual(performer.played.map(\.pattern), [.alignment])
        XCTAssertEqual(performer.played.map(\.time), [.default])

        nook.hoverHaptic = NookHoverHaptic(pattern: .levelChange, performanceTime: .now)
        nook.performHoverHapticIfEnabled()
        XCTAssertEqual(performer.played.last?.pattern, .levelChange)
        XCTAssertEqual(performer.played.last?.time, .now)

        nook.hoverBehavior = []
        nook.performHoverHapticIfEnabled()
        XCTAssertEqual(performer.played.count, 2, "no haptic without .hapticFeedback")
    }
}

// MARK: - Fixtures

private final class RecordingHapticPerformer: NSObject, NSHapticFeedbackPerformer {
    var played: [(pattern: NSHapticFeedbackManager.FeedbackPattern, time: NSHapticFeedbackManager.PerformanceTime)] = []

    func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) {
        played.append((pattern, performanceTime))
    }
}

/// The notch path as `NookShape` drew it before outlines were customizable.
private func historicalNotchPath(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + top, y: rect.minY + top),
        control: CGPoint(x: rect.minX + top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
        control: CGPoint(x: rect.minX + top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
        control: CGPoint(x: rect.maxX - top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY),
        control: CGPoint(x: rect.maxX - top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    return path
}

/// The Liquid Glass backdrop as the surface drew it before its knobs were exposed.
private struct HistoricalLiquidGlass<S: Shape>: View {
    let glass: NookBackdrop.LiquidGlass
    let shape: S

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                real
            } else {
                approximate
            }
        #else
            approximate
        #endif
    }

    #if compiler(>=6.2)
        @available(macOS 26.0, *)
        private var real: some View {
            let tinted: Glass = {
                guard let tint = glass.tint, glass.tintStrength > 0 else { return .regular }
                return Glass.regular.tint(tint.opacity(glass.tintStrength))
            }()
            return Color.clear
                .glassEffect(tinted, in: shape)
                .overlay { shading }
        }
    #endif

    @ViewBuilder
    private var shading: some View {
        if let shading = glass.shading {
            LinearGradient(gradient: shading.gradient, startPoint: shading.startPoint, endPoint: shading.endPoint)
        }
    }

    private var approximate: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            if let tint = glass.tint, glass.tintStrength > 0 {
                tint.opacity(glass.tintStrength)
            }
            shading
            if glass.highlightStrength > 0 {
                LinearGradient(
                    colors: [Color.white.opacity(0.16 * glass.highlightStrength), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5 * glass.highlightStrength),
                            Color.white.opacity(0.06 * glass.highlightStrength),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
    }
}

/// The feedback cue as the overlay drew it before it took a style.
private struct HistoricalFeedback: View {
    let tint: Color
    let progress: Double
    let reduceMotion: Bool
    let shape: NookShape

    var body: some View {
        if reduceMotion {
            shape
                .stroke(tint, lineWidth: 4.0)
                .opacity(sin(progress * .pi) * 0.7)
                .blendMode(.plusLighter)
        } else {
            let startX = -0.5 + progress * 1.5
            let envelope = sin(progress * .pi)
            let highlight = tint.opacity(0.95)
            ZStack {
                shape
                    .stroke(tint.opacity(0.55), lineWidth: 8.0)
                    .blur(radius: 3.0)
                    .opacity(envelope * 0.9)
                    .blendMode(.plusLighter)
                shape
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: highlight, location: 0.42),
                                .init(color: Color.white.opacity(0.75), location: 0.5),
                                .init(color: highlight, location: 0.58),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: UnitPoint(x: startX, y: 0.5),
                            endPoint: UnitPoint(x: startX + 0.5, y: 0.5)
                        ),
                        lineWidth: 6.0
                    )
                    .opacity(envelope)
                    .blendMode(.plusLighter)
            }
        }
    }
}
