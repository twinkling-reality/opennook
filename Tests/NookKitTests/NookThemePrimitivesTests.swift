// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import SwiftUI
import XCTest

@testable import NookKit

/// The Codable building blocks of a theme: colors, fonts, animations, numbers, transitions,
/// sounds, shadows, gradients, and backdrop descriptions.
final class NookThemePrimitivesTests: XCTestCase {
    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func encodedString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
    }

    // MARK: - NookRGBA

    func testRGBAReadsAndWritesHex() throws {
        let color = try XCTUnwrap(NookRGBA(hex: "#3F8CFA"))
        XCTAssertEqual(color.hex, "#3F8CFA")
        XCTAssertEqual(color.opacity, 1)
        XCTAssertEqual(NookRGBA(hex: "ff3b30cc")?.hex, "#FF3B30CC")
        XCTAssertNil(NookRGBA(hex: "#12345"))
        XCTAssertNil(NookRGBA(hex: "#-12345"))
        XCTAssertNil(NookRGBA(hex: "#GGGGGG"))
    }

    func testRGBAQuantizesToEightBits() {
        let color = NookRGBA(red: 0.2, green: 0.5, blue: 1.4, opacity: -1)
        XCTAssertEqual(color.red, 51.0 / 255)
        XCTAssertEqual(color.green, 128.0 / 255)
        XCTAssertEqual(color.blue, 1)
        XCTAssertEqual(color.opacity, 0)
    }

    func testRGBACodesAsAHexString() throws {
        XCTAssertEqual(try encodedString(NookRGBA(red: 1, green: 0, blue: 0)), ##""#FF0000""##)
        XCTAssertEqual(try decode(NookRGBA.self, ##""#00FF0080""##).hex, "#00FF0080")
        XCTAssertThrowsError(try decode(NookRGBA.self, #""blue""#))
    }

    // MARK: - NookColorValue

    func testColorStringForms() throws {
        XCTAssertEqual(try decode(NookColorValue.self, ##""#3399FF""##), .hex(NookRGBA(hex: "#3399FF")!))
        XCTAssertEqual(try decode(NookColorValue.self, #""accent""#), .accent)
        XCTAssertEqual(
            try decode(NookColorValue.self, #""{color.label.primary}""#),
            .reference("color.label.primary", opacity: nil)
        )
        XCTAssertEqual(try decode(NookColorValue.self, #""white""#), .white(opacity: 1))
        XCTAssertThrowsError(try decode(NookColorValue.self, #""chartreuse""#))
    }

    func testColorObjectForms() throws {
        XCTAssertEqual(try decode(NookColorValue.self, #"{"white": 0.95}"#), .white(opacity: 0.95))
        XCTAssertEqual(try decode(NookColorValue.self, #"{"black": 0.42}"#), .black(opacity: 0.42))
        XCTAssertEqual(
            try decode(NookColorValue.self, #"{"srgb": [0.2, 0.78, 0.73]}"#),
            .srgb(red: 0.2, green: 0.78, blue: 0.73, opacity: 1)
        )
        XCTAssertEqual(try decode(NookColorValue.self, #"{"system": "red"}"#), .system(.red))
        XCTAssertEqual(
            try decode(NookColorValue.self, #"{"ref": "{color.accent}", "opacity": 0.6}"#),
            .reference("color.accent", opacity: 0.6)
        )
        XCTAssertEqual(try decode(NookColorValue.self, #"{"hierarchical": "secondary"}"#), .hierarchical(.secondary))
        XCTAssertEqual(
            try decode(NookColorValue.self, ##"{"dark": {"white": 0.62}, "light": "#000000"}"##),
            .adaptive(NookAdaptiveColor(dark: .white(opacity: 0.62), light: .hex(NookRGBA(hex: "#000000")!)))
        )
        XCTAssertThrowsError(try decode(NookColorValue.self, #"{"srgb": [1, 0]}"#))
        XCTAssertThrowsError(try decode(NookColorValue.self, #"{"tone": 3}"#))
    }

    func testEveryColorFormRoundTrips() throws {
        let values: [NookColorValue] = [
            "#3399FF", "#3399FF80", .srgb(red: 0.2, green: 0.78, blue: 0.73, opacity: 0.5), .white(opacity: 0.055),
            .black(opacity: 1), .system(.controlAccent), .accent, .reference("color.fill.subtle", opacity: 0.5),
            .hierarchical(.tertiary),
            .adaptive(
                NookAdaptiveColor(
                    dark: .white(opacity: 0.055),
                    light: .black(opacity: 0.03),
                    darkSolid: .white(opacity: 0.07),
                    lightSolid: .black(opacity: 0.045),
                    darkReducedTransparency: .white(opacity: 0.12),
                    lightReducedTransparency: .black(opacity: 0.055)
                )
            ),
        ]
        for value in values {
            try assertRoundTrip(value)
        }
        XCTAssertEqual(try encodedString(NookColorValue.accent), #""accent""#)
    }

    func testAdaptiveColorPicksTheVariantForTheSurface() {
        let fill = NookAdaptiveColor(
            dark: .white(opacity: 0.055),
            light: .black(opacity: 0.03),
            darkSolid: .white(opacity: 0.07),
            lightSolid: nil,
            darkReducedTransparency: .white(opacity: 0.12)
        )
        XCTAssertEqual(
            fill.variant(isDark: true, isSolidSurface: false, reduceTransparency: false),
            .white(opacity: 0.055)
        )
        XCTAssertEqual(
            fill.variant(isDark: true, isSolidSurface: true, reduceTransparency: true),
            .white(opacity: 0.07)
        )
        XCTAssertEqual(
            fill.variant(isDark: true, isSolidSurface: false, reduceTransparency: true),
            .white(opacity: 0.12)
        )
        // No solid or reduced-transparency variant for light: the plain one stands in.
        XCTAssertEqual(
            fill.variant(isDark: false, isSolidSurface: true, reduceTransparency: false),
            .black(opacity: 0.03)
        )
        XCTAssertEqual(
            fill.variant(isDark: false, isSolidSurface: false, reduceTransparency: true),
            .black(opacity: 0.03)
        )
    }

    func testSystemColorsMatchTheColorsTheChromeUses() {
        XCTAssertEqual(NookSystemColor.controlAccent.color, Color(nsColor: .controlAccentColor))
        XCTAssertEqual(NookSystemColor.red.color, Color.red)
        XCTAssertEqual(NookSystemColor.orange.color, Color.orange)
        XCTAssertEqual(NookSystemColor.green.color, Color.green)
    }

    // MARK: - NookDimension

    func testDimensionForms() throws {
        XCTAssertEqual(try decode(NookDimension.self, "12"), .points(12))
        XCTAssertEqual(try decode(NookDimension.self, "10.5"), .points(10.5))
        XCTAssertEqual(try decode(NookDimension.self, #""{radius.lg}""#), .token("radius.lg"))
        XCTAssertEqual(
            try decode(NookDimension.self, #"{"ref": "space.md", "times": 1.5}"#),
            .reference("space.md", times: 1.5)
        )
        XCTAssertThrowsError(try decode(NookDimension.self, #""wide""#))
        for value: NookDimension in [7, 0.5, .token("space.md"), .reference("space.md", times: 2)] {
            try assertRoundTrip(value)
        }
    }

    func testAdaptiveNumberForms() throws {
        XCTAssertEqual(try decode(NookAdaptiveNumber.self, "0.3"), NookAdaptiveNumber(0.3))
        XCTAssertEqual(
            try decode(NookAdaptiveNumber.self, #"{"dark": 0.52, "light": 0.1}"#),
            NookAdaptiveNumber(dark: 0.52, light: 0.1)
        )
        try assertRoundTrip(NookAdaptiveNumber(dark: 0.52, light: 0.1))
        try assertRoundTrip(NookAdaptiveNumber(0.4))
    }

    // MARK: - Fonts

    func testFontSpecForms() throws {
        XCTAssertEqual(try decode(NookFontSpec.self, #""{type.glyph}""#), .role("type.glyph"))
        XCTAssertEqual(
            try decode(NookFontSpec.self, #"{"size": "{type.size.md}", "weight": "semibold", "design": "rounded"}"#),
            NookFontSpec(size: .token("type.size.md"), weight: .semibold, design: .rounded)
        )
        // The playground's FontSpec JSON reads unchanged.
        XCTAssertEqual(
            try decode(NookFontSpec.self, #"{"size": 11, "weight": "medium"}"#),
            NookFontSpec(size: 11, weight: .medium)
        )
        XCTAssertThrowsError(try decode(NookFontSpec.self, #""Helvetica""#))
        try assertRoundTrip(NookFontSpec.role("type.body"))
        try assertRoundTrip(
            NookFontSpec(role: "type.body", weight: .bold, width: .condensed, family: "Menlo", monospacedDigits: true)
        )
    }

    func testResolvedFontsUseTheSameCallAsTheDefaults() {
        XCTAssertEqual(NookResolvedFontSpec(size: 11).font, Font.system(size: 11))
        XCTAssertEqual(NookResolvedFontSpec(size: 11, weight: .semibold).font, Font.system(size: 11, weight: .semibold))
        XCTAssertEqual(NookResolvedFontSpec(size: 10.5, weight: .medium).font, Font.system(size: 10.5, weight: .medium))
        XCTAssertEqual(
            NookResolvedFontSpec(size: 10, weight: .regular, design: .monospaced).font,
            Font.system(size: 10, weight: .regular, design: .monospaced)
        )
        XCTAssertEqual(
            NookResolvedFontSpec(size: 12, weight: .bold, width: .condensed).font,
            Font.system(size: 12, weight: .bold).width(.condensed)
        )
    }

    // MARK: - Animations

    func testAnimationForms() throws {
        XCTAssertEqual(
            try decode(NookAnimationSpec.self, #"{"response": 0.38, "dampingFraction": 0.84}"#),
            .spring(response: 0.38, dampingFraction: 0.84)
        )
        XCTAssertEqual(
            try decode(NookAnimationSpec.self, #"{"response": 0.52, "dampingFraction": 0.88, "blendDuration": 0.12}"#),
            .spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.12)
        )
        XCTAssertEqual(
            try decode(NookAnimationSpec.self, #"{"duration": 0.4, "bounce": 0.15}"#),
            .springDuration(duration: 0.4, bounce: 0.15)
        )
        XCTAssertEqual(
            try decode(NookAnimationSpec.self, #"{"preset": "snappy", "duration": 0.2}"#),
            .preset(.snappy, duration: 0.2)
        )
        XCTAssertEqual(
            try decode(NookAnimationSpec.self, #"{"curve": "easeOut", "duration": 0.18}"#),
            .curve(.easeOut, duration: 0.18)
        )
        XCTAssertEqual(
            try decode(NookAnimationSpec.self, #"{"bezier": [0.2, 0, 0, 1], "duration": 0.3}"#),
            .bezier(x1: 0.2, y1: 0, x2: 0, y2: 1, duration: 0.3)
        )
        XCTAssertEqual(try decode(NookAnimationSpec.self, #""{spring.default}""#), .reference("spring.default"))
        XCTAssertThrowsError(try decode(NookAnimationSpec.self, #"{"bezier": [0.2, 0]}"#))
        XCTAssertThrowsError(try decode(NookAnimationSpec.self, #"{"speed": 2}"#))

        let all: [NookAnimationSpec] = [
            .spring(response: 0.38, dampingFraction: 0.84),
            .spring(response: 0.5, dampingFraction: 0.9, blendDuration: 0.1),
            .springDuration(duration: 0.4, bounce: 0.2), .preset(.bouncy, duration: 0.4, extraBounce: 0.1),
            .curve(.linear, duration: 1), .bezier(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4, duration: 0.5),
            .reference("curve.quick"),
        ]
        for spec in all {
            try assertRoundTrip(spec)
        }
    }

    func testAnimationsUseTheSameCallAsTheDefaults() {
        XCTAssertEqual(
            NookAnimationSpec.spring(response: 0.38, dampingFraction: 0.84).animation(),
            Animation.spring(response: 0.38, dampingFraction: 0.84)
        )
        XCTAssertEqual(
            NookAnimationSpec.spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.12).animation(),
            Animation.spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.12)
        )
        XCTAssertEqual(NookAnimationSpec.curve(.easeOut, duration: 0.18).animation(), Animation.easeOut(duration: 0.18))
        XCTAssertEqual(NookAnimationSpec.preset(.snappy, duration: 0.18).animation(), Animation.snappy(duration: 0.18))
        XCTAssertNil(NookAnimationSpec.reference("spring.default").animation())
    }

    func testMotionSchemesTransformSpringsOnly() {
        let spring = NookAnimationSpec.spring(response: 0.34, dampingFraction: 0.86)
        XCTAssertEqual(NookMotionScheme.standard.applied(to: spring), spring)
        XCTAssertEqual(NookMotionScheme.calm.applied(to: spring), .spring(response: 0.34, dampingFraction: 1))
        XCTAssertEqual(
            NookMotionScheme.expressive.applied(to: spring),
            .spring(response: 0.34, dampingFraction: 0.86 * 0.8)
        )
        XCTAssertEqual(
            NookMotionScheme.calm.applied(to: .preset(.bouncy, duration: 0.4)),
            .preset(.smooth, duration: 0.4)
        )
        let curve = NookAnimationSpec.curve(.easeOut, duration: 0.18)
        XCTAssertEqual(NookMotionScheme.calm.applied(to: curve), curve)
        XCTAssertEqual(NookMotionScheme.expressive.applied(to: curve), curve)
    }

    // MARK: - Content transitions

    func testContentTransitionExpressesAStaggeredChoreography() throws {
        let exit = try decode(
            NookContentTransitionSpec.self,
            #"{"opacity": 0, "blur": 8, "scale": 0.97, "animation": {"curve": "easeOut", "duration": 0.16}}"#
        )
        XCTAssertEqual(
            exit,
            NookContentTransitionSpec(blur: 8, scaleX: 0.97, scaleY: 0.97, animation: .curve(.easeOut, duration: 0.16))
        )
        let today = try decode(
            NookContentTransitionSpec.self,
            #"{"opacity": 0, "blur": 6, "scaleY": 0.72, "anchor": "top"}"#
        )
        XCTAssertEqual(today, .expandedContentDefault)
        XCTAssertNil(today.animation)
        try assertRoundTrip(exit)
        try assertRoundTrip(NookContentTransitionSpec.expandedContentDefault)
        try assertRoundTrip(NookContentTransitionSpec(anchor: NookUnitPointSpec(x: 0.25, y: 0.1), offsetY: -6))
    }

    func testUnitPointForms() throws {
        XCTAssertEqual(try decode(NookUnitPointSpec.self, #""bottomTrailing""#), .bottomTrailing)
        XCTAssertEqual(try decode(NookUnitPointSpec.self, #"{"x": 0.2, "y": 0.9}"#), NookUnitPointSpec(x: 0.2, y: 0.9))
        XCTAssertThrowsError(try decode(NookUnitPointSpec.self, #""middle""#))
        XCTAssertEqual(NookUnitPointSpec.top.unitPoint, UnitPoint.top)
    }

    // MARK: - Sounds

    func testSoundForms() throws {
        XCTAssertEqual(
            try decode(NookSoundSpec.self, #"{"system": "Glass", "volume": 0.6}"#),
            .system("Glass", volume: 0.6)
        )
        XCTAssertEqual(try decode(NookSoundSpec.self, #"{"resource": "pop.caf"}"#), NookSoundSpec(.resource("pop.caf")))
        XCTAssertEqual(
            try decode(NookSoundSpec.self, #"{"file": "/tmp/pop.caf"}"#),
            NookSoundSpec(.file(URL(fileURLWithPath: "/tmp/pop.caf")))
        )
        XCTAssertEqual(
            try decode(NookSoundSpec.self, #"{"file": "file:///tmp/pop.caf"}"#),
            NookSoundSpec(.file(URL(string: "file:///tmp/pop.caf")!))
        )
        XCTAssertThrowsError(try decode(NookSoundSpec.self, #"{"volume": 1}"#))
        try assertRoundTrip(NookSoundSpec.system("Pop", volume: 0.25))
        try assertRoundTrip(NookSoundSpec(.file(URL(fileURLWithPath: "/tmp/a b.caf"))))
    }

    func testSoundVolumeMultipliesAndClamps() {
        XCTAssertEqual(NookSoundSpec.system("Pop", volume: 0.5).effectiveVolume(masterVolume: 0.5), 0.25)
        XCTAssertEqual(NookSoundSpec.system("Pop").effectiveVolume(masterVolume: 0.8), 0.8)
        XCTAssertEqual(NookSoundSpec.system("Pop", volume: 3).effectiveVolume(masterVolume: 1), 1)
        XCTAssertEqual(NookSoundSpec.system("Pop", volume: -1).effectiveVolume(masterVolume: 1), 0)
    }

    // MARK: - Shadows and gradients

    func testShadowAndGradientForms() throws {
        XCTAssertEqual(
            try decode(NookShadowSpec.self, #"{"color": {"black": 0.35}, "radius": 8, "y": 3}"#),
            NookShadowSpec()
        )
        try assertRoundTrip(NookShadowSpec(color: "accent", radius: 12, x: 2, y: -1))

        let even = try decode(NookGradientSpec.self, ##"["#101014", {"black": 1}]"##)
        XCTAssertEqual(even, NookGradientSpec(colors: ["#101014", .black(opacity: 1)]))
        XCTAssertEqual(even.resolvedLocations, [0, 1])
        let placed = try decode(
            NookGradientSpec.self,
            ##"{"stops": [{"color": "#000000", "location": 0.2}, "#FFFFFF"]}"##
        )
        XCTAssertEqual(placed.stops.first?.location, 0.2)
        try assertRoundTrip(placed)
    }

    // MARK: - Backdrop descriptions

    func testEveryBackdropKindRoundTrips() throws {
        let gradient = NookGradientSpec(colors: ["#101014", .black(opacity: 1)])
        let descriptions: [NookBackdropDescription] = [
            .framework,
            .solid("{color.surface}"),
            .vibrancy(
                .init(material: .hudWindow, blending: .withinWindow, darken: NookAdaptiveNumber(dark: 0.52, light: 0.1))
            ),
            .liquidGlass(
                .init(
                    tint: "accent",
                    tintStrength: NookAdaptiveNumber(dark: 0.3, light: 0.42),
                    shading: .init(gradient: gradient),
                    scalesWithStrength: false
                )
            ),
            .linearGradient(.init(gradient: gradient, start: .topLeading, end: .bottomTrailing)),
            .radialGradient(.init(gradient: gradient, center: .top, endRadius: 240)),
            .angularGradient(.init(gradient: gradient, startAngle: 90, endAngle: 450)),
            .mesh(
                .init(
                    width: 2,
                    height: 2,
                    points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                    colors: ["#000000", "#111111", "#222222", "#333333"]
                )
            ),
            .custom(id: "com.example.aurora", fallback: .solid(.black(opacity: 1))),
        ]
        for description in descriptions {
            try assertRoundTrip(description)
        }
    }

    func testUnknownBackdropKindsDecodeWithTheirFallback() throws {
        let decoded = try decode(
            NookBackdropDescription.self,
            ##"{"kind": "shader", "name": "plasma", "fallback": {"kind": "solid", "color": "#000000"}}"##
        )
        XCTAssertEqual(decoded, .unknown(kind: "shader", fallback: .solid("#000000")))
        try assertRoundTrip(decoded)
    }

    func testAMalformedMeshIsRejected() {
        XCTAssertThrowsError(
            try decode(
                NookBackdropDescription.self,
                ##"{"kind": "mesh", "width": 2, "height": 2, "points": [[0, 0]], "colors": ["#000000"]}"##
            )
        )
    }
}
