// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// The public, read-only view of the token registry: descriptors, values by id, flat token
/// coding, and resolved values.
final class NookTokenDescriptorTests: XCTestCase {
    // MARK: - Descriptors

    func testEveryRegisteredTokenIsDescribedOnceInRegistryOrder() {
        XCTAssertEqual(NookTokenDescriptor.all.map(\.id), NookTokenRegistry.allIDs.map(\.id))
        XCTAssertEqual(Set(NookTokenDescriptor.all.map(\.id)).count, NookTokenDescriptor.all.count)
        for entry in NookTokenRegistry.allIDs {
            let descriptor = NookTokenDescriptor.named(entry.id)
            XCTAssertEqual(descriptor?.id, entry.id)
            XCTAssertEqual(descriptor?.tier == .semantic, entry.tier == .semantic, entry.id)
        }
    }

    func testDescriptorsCarryTheRegistryDefaults() {
        XCTAssertEqual(NookTokenDescriptor.named("color.label.primary")?.kind, .color)
        XCTAssertEqual(
            NookTokenDescriptor.named("color.destructive")?.defaultValue,
            .color(.system(.red))
        )

        let banner = NookTokenDescriptor.named("banner.cornerRadius")
        XCTAssertEqual(banner?.kind, .dimension)
        XCTAssertEqual(banner?.tier, .component)
        XCTAssertEqual(banner?.defaultValue, .dimension(.token(.radiusMD)))
        XCTAssertEqual(banner?.scaling, .radius)
        XCTAssertEqual(banner?.unit, .points)
        XCTAssertEqual(banner?.group, "banner")

        XCTAssertEqual(NookTokenDescriptor.named("banner.stroke.opacity")?.unit, .opacity)
        XCTAssertEqual(NookTokenDescriptor.named("motion.stagger")?.unit, .seconds)
        XCTAssertEqual(NookTokenDescriptor.named("settings.sectionLabel.tracking")?.unit?.bounds, -100...100)
        XCTAssertEqual(NookTokenDescriptor.named("space.md")?.scaling, .spacing)

        XCTAssertEqual(
            NookTokenDescriptor.named("type.body")?.defaultValue,
            .font(NookFontSpec(size: .token(.typeSizeMD), weight: .regular))
        )
        XCTAssertEqual(
            NookTokenDescriptor.named("motion.statusBanner")?.defaultValue,
            .animation(.reference(.springDefault))
        )
        XCTAssertEqual(
            NookTokenDescriptor.named("motion.content.exit")?.defaultValue,
            .transition(.expandedContentDefault)
        )

        let sound = NookTokenDescriptor.named("sound.open")
        XCTAssertEqual(sound?.kind, .sound)
        XCTAssertNil(sound?.defaultValue)
        XCTAssertNil(sound?.unit)
        XCTAssertEqual(NookTokenDescriptor.named("shadow.chrome")?.kind, .shadow)
    }

    func testOnlyDimensionsHaveAUnitAndEveryOtherKindHasADefaultUnlessItIsNone() {
        for descriptor in NookTokenDescriptor.all {
            XCTAssertEqual(descriptor.unit != nil, descriptor.kind == .dimension, descriptor.id)
            if descriptor.kind != .dimension {
                XCTAssertEqual(descriptor.scaling, .none, descriptor.id)
            }
            switch descriptor.kind {
                case .sound, .shadow: XCTAssertNil(descriptor.defaultValue, descriptor.id)
                default: XCTAssertEqual(descriptor.defaultValue?.kind, descriptor.kind, descriptor.id)
            }
        }
    }

    func testAnUnknownIDHasNoDescriptor() {
        XCTAssertNil(NookTokenDescriptor.named("color.nope"))
        XCTAssertNil(NookTokenDescriptor.named(""))
    }

    // MARK: - Values by id

    func testValuesAreReadAndWrittenByIDThroughTheTypedStorage() {
        var tokens = NookThemeTokens()
        XCTAssertTrue(tokens.setValue(.dimension(12), for: "banner.cornerRadius"))
        XCTAssertTrue(tokens.setValue(.color("#FF0000"), for: "color.destructive"))
        XCTAssertTrue(tokens.setValue(.sound(.system("Pop")), for: "sound.open"))
        XCTAssertTrue(tokens.setValue(.shadow(NookShadowSpec(radius: 4)), for: "shadow.chrome"))

        XCTAssertEqual(tokens[.bannerCornerRadius], 12)
        XCTAssertEqual(tokens[.destructive], "#FF0000")
        XCTAssertEqual(tokens[.open], .system("Pop"))
        XCTAssertEqual(tokens.value(for: "banner.cornerRadius"), .dimension(12))
        XCTAssertEqual(tokens.value(for: "shadow.chrome"), .shadow(NookShadowSpec(radius: 4)))
        XCTAssertNil(tokens.value(for: "space.md"))
        XCTAssertEqual(tokens.count, 4)

        XCTAssertTrue(tokens.setValue(nil, for: "banner.cornerRadius"))
        XCTAssertNil(tokens[.bannerCornerRadius])
        XCTAssertEqual(tokens.count, 3)
    }

    func testAValueOfTheWrongKindOrAnUnknownIDChangesNothing() {
        var tokens = NookThemeTokens()
        XCTAssertFalse(tokens.setValue(.color("#FF0000"), for: "banner.cornerRadius"))
        XCTAssertFalse(tokens.setValue(.dimension(3), for: "color.nope"))
        XCTAssertFalse(tokens.setValue(nil, for: "color.nope"))
        XCTAssertTrue(tokens.isEmpty)
    }

    // MARK: - Coding

    func testTokensEncodeAsOneFlatObjectAndDecodeBack() throws {
        var tokens = NookThemeTokens()
        tokens[.spaceMD] = 9
        tokens[.bannerCornerRadius] = .token(.radiusLG)
        tokens[.labelSecondary] = .adaptive(NookAdaptiveColor(dark: "#FFFFFFA8", light: .black(opacity: 0.5)))
        tokens[.statusBanner] = .reference(.springSnappy)
        tokens[.chrome] = NookShadowSpec(radius: 10, y: 4)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(tokens)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"banner.cornerRadius\":\"{radius.lg}\""), text)
        XCTAssertTrue(text.contains("\"space.md\":9"), text)
        XCTAssertEqual(try JSONDecoder().decode(NookThemeTokens.self, from: data), tokens)
    }

    func testDecodingSkipsUnknownIDsAndNullsAndNamesTheWrongKind() throws {
        let json = #"{ "space.md": 9, "made.up": 3, "color.accent": null }"#
        let tokens = try JSONDecoder().decode(NookThemeTokens.self, from: Data(json.utf8))
        XCTAssertEqual(tokens.ids, ["space.md"])

        let wrong = ##"{ "space.md": "#FF0000" }"##
        XCTAssertThrowsError(try JSONDecoder().decode(NookThemeTokens.self, from: Data(wrong.utf8)))
    }

    // MARK: - Resolved values

    private let darkContext = NookThemeContext(isDark: true)

    func testResolvedValuesFollowReferencesAndApplyTheKnobs() {
        var theme = NookTheme(radius: .factor(2), scale: 1.5, motion: .calm)
        theme.tokens[.typeBody] = NookFontSpec(role: .typeLabel, weight: .bold)

        XCTAssertEqual(theme.resolvedValue(for: "banner.cornerRadius", in: darkContext), .dimension(20))
        XCTAssertEqual(theme.resolvedValue(for: "space.md", in: darkContext), .dimension(12))
        XCTAssertEqual(
            theme.resolvedValue(for: "type.body", in: darkContext),
            .font(NookFontSpec(size: .points(16.5), weight: .bold))
        )
        // A reference is followed, and calm raises damping to critical.
        XCTAssertEqual(
            theme.resolvedValue(for: "motion.statusBanner", in: darkContext),
            .animation(.spring(response: 0.34, dampingFraction: 1))
        )
        XCTAssertEqual(
            theme.resolvedValue(for: "color.label.primary", in: darkContext),
            .color(Color.white.opacity(0.95))
        )
    }

    func testSoundsAndShadowsResolveToNoneUntilSet() {
        var theme = NookTheme(soundVolume: 0.5)
        XCTAssertEqual(theme.resolvedValue(for: "sound.open", in: darkContext), .sound(nil))
        XCTAssertEqual(theme.resolvedValue(for: "shadow.chrome", in: darkContext), .shadow(nil))

        theme.tokens[.open] = .system("Pop", volume: 0.8)
        theme.tokens[.chrome] = NookShadowSpec(radius: 6)
        XCTAssertEqual(theme.resolvedValue(for: "sound.open", in: darkContext), .sound(.system("Pop", volume: 0.4)))
        XCTAssertEqual(theme.resolvedValue(for: "shadow.chrome", in: darkContext), .shadow(NookShadowSpec(radius: 6)))
    }

    func testATransitionsAnimationReferenceIsFollowed() {
        var theme = NookTheme()
        theme.tokens[.contentExit] = NookContentTransitionSpec(blur: 4, animation: .reference(.curveQuick))
        XCTAssertEqual(
            theme.resolvedValue(for: "motion.content.exit", in: darkContext),
            .transition(NookContentTransitionSpec(blur: 4, animation: .curve(.easeOut, duration: 0.18)))
        )
        XCTAssertEqual(
            NookTheme.standard.resolvedValue(for: "motion.compact.transition", in: darkContext),
            .transition(.compactContentDefault)
        )
    }

    func testEveryTokenResolvesUnderTheStandardTheme() {
        for descriptor in NookTokenDescriptor.all {
            XCTAssertNotNil(NookTheme.standard.resolvedValue(for: descriptor.id, in: darkContext), descriptor.id)
        }
        XCTAssertNil(NookTheme.standard.resolvedValue(for: "made.up", in: darkContext))
    }
}
