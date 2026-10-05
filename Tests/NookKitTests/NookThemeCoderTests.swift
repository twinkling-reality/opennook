// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import XCTest

@testable import NookKit

/// Theme files: the envelope, tolerance, ranges, references, and errors.
final class NookThemeCoderTests: XCTestCase {
    private typealias Coder = NookThemeCoder

    private func decodingError(_ json: String) -> NookThemeError? {
        do {
            _ = try Coder.decode(json)
            return nil
        } catch {
            return error as? NookThemeError
        }
    }

    private func issues(_ json: String) throws -> [NookThemeIssue] {
        try Coder.decode(json).issues
    }

    // MARK: - Envelope

    func testAStandardThemeWritesOnlyTheEnvelope() throws {
        let text = try Coder.encodeString(.standard)
        XCTAssertEqual(text, "{\n  \"format\" : \"opennook.theme\",\n  \"version\" : 1\n}\n")
        XCTAssertEqual(try Coder.decode(text), NookThemeLoadResult(theme: .standard, issues: []))
    }

    func testAFullThemeRoundTripsThroughAFile() throws {
        var theme = NookTheme(name: "Graphite", accent: "#3399FF", palette: .dark, radius: .large, motion: .calm)
        theme.tokens[.spaceMD] = 9
        theme.tokens[.bannerCornerRadius] = .token(.radiusLG)
        theme.tokens[.contentExit] = NookContentTransitionSpec(blur: 8, scaleX: 0.97, scaleY: 0.97)
        theme.tokens[.stagger] = 0.035
        theme.tokens[.alert] = .system("Sosumi", volume: 0.4)
        theme.backdrops.solid = .linearGradient(.init(gradient: NookGradientSpec(colors: ["#101014", "#000000"])))
        let data = try theme.jsonData()
        XCTAssertEqual(try NookTheme(jsonData: data), theme)
        let result = try Coder.decode(data)
        XCTAssertEqual(result.issues, [])
    }

    func testTheExampleThemeFromTheDesignLoads() throws {
        let json = ##"""
            {
              "format": "opennook.theme",
              "version": 1,
              "name": "Graphite",
              "accent": "#3399FF",
              "allowsUserAccent": false,
              "palette": "dark",
              "radius": "large",
              "scale": 1.05,
              "fontDesign": "rounded",
              "motion": "calm",
              "soundVolume": 0.6,
              "tokens": {
                "color.label.secondary": { "dark": { "white": 0.66 }, "light": { "black": 0.55 } },
                "color.destructive": "#FF453A",
                "space.md": 9,
                "spring.default": { "response": 0.3, "dampingFraction": 0.9 },
                "shape.chrome.bottomRadius": 28,
                "motion.content.exit": { "opacity": 0, "blur": 8, "scale": 0.97, "animation": { "curve": "easeOut", "duration": 0.16 } },
                "motion.content.enter": { "opacity": 0, "blur": 8, "scale": 0.97, "animation": { "curve": "easeOut", "duration": 0.3 } },
                "motion.content.enterDelay": 0.16,
                "motion.header.delay": 0.3,
                "motion.stagger": 0.035,
                "sound.open": { "system": "Pop" },
                "sound.close": null
              },
              "components": {
                "banner.cornerRadius": "{radius.lg}",
                "banner.message.font": { "size": "{type.size.md}", "weight": "semibold" }
              },
              "backdrops": {
                "liquidGlass": { "kind": "liquidGlass", "tint": "accent", "tintStrength": { "dark": 0.25, "light": 0.35 } },
                "translucent": { "kind": "custom", "id": "com.example.aurora", "fallback": { "kind": "framework" } },
                "glassShading": "notchFade"
              }
            }
            """##
        let result = try Coder.decode(json)
        XCTAssertEqual(result.issues, [])
        let theme = result.theme
        XCTAssertEqual(theme.name, "Graphite")
        XCTAssertFalse(theme.allowsUserAccent)
        XCTAssertEqual(theme.radius, .large)
        XCTAssertEqual(theme.tokens.count, 13)
        XCTAssertEqual(theme.backdrops.glassShading, .notchFade)
        let tokens = theme.resolvedTokens()
        XCTAssertEqual(tokens[.stagger], 0.035)
        XCTAssertEqual(tokens.metrics.bannerCornerRadius, 12 * 1.4)
        XCTAssertEqual(tokens.sound(.open)?.volume, 0.6)
    }

    // MARK: - Tolerance

    func testUnknownMembersAndIdsAreIgnoredAndReported() throws {
        let found = try issues(
            #"""
            {"format": "opennook.theme", "version": 1, "wobble": 3,
             "tokens": {"space.huge": 1, "space.md": 9},
             "backdrops": {"neon": {"kind": "framework"}}}
            """#
        )
        XCTAssertEqual(found.map(\.path), ["wobble", "tokens.space.huge", "backdrops.neon"])
        XCTAssertTrue(found.allSatisfy { $0.kind == .unknownKey })
    }

    func testATokenUnderTheOtherSectionIsUsedAndReported() throws {
        let result = try Coder.decode(
            #"{"format": "opennook.theme", "version": 1, "tokens": {"banner.cornerRadius": 4}, "components": {"space.md": 9}}"#
        )
        XCTAssertEqual(result.theme.tokens[.bannerCornerRadius], 4)
        XCTAssertEqual(result.theme.tokens[.spaceMD], 9)
        XCTAssertEqual(result.issues.map(\.kind), [.misplaced, .misplaced])
        XCTAssertEqual(result.issues.map(\.path), ["tokens.banner.cornerRadius", "components.space.md"])
    }

    func testRenamedIdsAreReadAsTheirNewIdAndRemovedOnesSkipped() throws {
        var renames: [String: String?] = ["space.medium": "space.md"]
        renames["banner.glow"] = .some(nil)
        let data = Data(
            #"{"format": "opennook.theme", "version": 1, "tokens": {"space.medium": 9}, "components": {"banner.glow": 2}}"#
                .utf8
        )
        let result = try Coder.decode(data, renames: renames)
        XCTAssertEqual(result.theme.tokens[.spaceMD], 9)
        XCTAssertEqual(result.theme.tokens.count, 1)
        XCTAssertEqual(
            result.issues,
            [
                NookThemeIssue(path: "tokens.space.medium", kind: .renamed, message: "renamed to space.md; read as it"),
                NookThemeIssue(
                    path: "components.banner.glow",
                    kind: .removed,
                    message: "this token was removed; ignored"
                ),
            ]
        )
    }

    // MARK: - Ranges

    func testNumbersOutOfRangeAreBroughtIntoRange() throws {
        let result = try Coder.decode(
            #"""
            {"format": "opennook.theme", "version": 1, "scale": 7, "radius": -1, "backdropStrength": 0,
             "soundVolume": 2,
             "tokens": {"space.md": -4, "color.label.primary": {"white": 1.5}, "motion.stagger": 0.5,
                        "sound.open": {"system": "Pop", "volume": 3}},
             "components": {"banner.stroke.opacity": 4, "banner.message.font": {"size": 900},
                            "motion.statusBanner": {"response": 0, "dampingFraction": 9}}}
            """#
        )
        let theme = result.theme
        XCTAssertEqual(theme.scale, 2)
        XCTAssertEqual(theme.radius, .factor(0))
        XCTAssertEqual(theme.backdropStrength, 0.15)
        XCTAssertEqual(theme.soundVolume, 1)
        XCTAssertEqual(theme.tokens[.spaceMD], 0)
        XCTAssertEqual(theme.tokens[.labelPrimary], .white(opacity: 1))
        XCTAssertEqual(theme.tokens[.bannerStrokeOpacity], 1)
        XCTAssertEqual(theme.tokens[.bannerMessage]?.size, 200)
        XCTAssertEqual(theme.tokens[.statusBanner], .spring(response: 0.01, dampingFraction: 2))
        XCTAssertEqual(theme.tokens[.open]?.volume, 1)
        let clampedPaths = Set(result.issues.filter { $0.kind == .clamped }.map(\.path))
        XCTAssertEqual(
            clampedPaths,
            [
                "scale", "radius", "backdropStrength", "soundVolume", "tokens.space.md",
                "tokens.color.label.primary.white",
                "tokens.sound.open.volume", "components.banner.stroke.opacity", "components.banner.message.font.size",
                "components.motion.statusBanner",
            ]
        )
    }

    func testLongAnimationsAndHierarchicalColorsAreReportedButKept() throws {
        let result = try Coder.decode(
            #"""
            {"format": "opennook.theme", "version": 1,
             "tokens": {"motion.header.delay": 3, "color.label.secondary": {"hierarchical": "secondary"}},
             "components": {"motion.breadcrumb": {"curve": "linear", "duration": 2.5}}}
            """#
        )
        XCTAssertEqual(result.theme.tokens[.headerDelay], 3)
        XCTAssertEqual(result.theme.tokens[.breadcrumb], .curve(.linear, duration: 2.5))
        XCTAssertEqual(
            Set(result.issues.map { "\($0.path) \($0.kind)" }),
            [
                "tokens.motion.header.delay longDuration", "components.motion.breadcrumb longDuration",
                "tokens.color.label.secondary unsupported",
            ]
        )
    }

    func testValidatingASwiftThemeClampsTheSameWay() {
        var theme = NookTheme(scale: 0.1)
        theme.tokens[.spaceMD] = -2
        let validated = theme.validated()
        XCTAssertEqual(validated.theme.scale, 0.5)
        XCTAssertEqual(validated.theme.tokens[.spaceMD], 0)
        XCTAssertEqual(validated.issues.map(\.path), ["scale", "tokens.space.md"])
        XCTAssertEqual(NookTheme.standard.validated().issues, [])
    }

    // MARK: - References

    func testReferencesToMissingTokensAreReported() throws {
        let result = try Coder.decode(
            #"{"format": "opennook.theme", "version": 1, "components": {"banner.cornerRadius": "{radius.huge}"}}"#
        )
        XCTAssertEqual(result.issues.map(\.kind), [.unknownReference])
        XCTAssertEqual(result.issues.first?.path, "radius.huge")
    }

    func testAReferenceLoopIsAnError() {
        XCTAssertEqual(
            decodingError(
                #"{"format": "opennook.theme", "version": 1, "tokens": {"space.md": "{space.lg}", "space.lg": "{space.md}"}}"#
            ),
            .referenceLoop("space.md")
        )
        XCTAssertNotNil(
            decodingError(
                #"""
                {"format": "opennook.theme", "version": 1,
                 "tokens": {"color.label.primary": "{color.label.secondary}", "color.label.secondary": "{color.label.primary}"}}
                """#
            )
        )
    }

    // MARK: - Errors

    func testRejectsTextThatIsNotJSON() {
        XCTAssertEqual(decodingError("theme"), .notJSON)
    }

    func testRejectsJSONThatIsNotATheme() {
        XCTAssertEqual(decodingError("[]"), .notATheme)
        XCTAssertEqual(decodingError(#"{"version": 1}"#), .notATheme)
        XCTAssertEqual(decodingError(#"{"format": "opennook.playground-preset", "version": 1}"#), .notATheme)
        XCTAssertEqual(decodingError(#"{"format": "opennook.theme"}"#), .notATheme)
        XCTAssertEqual(decodingError(#"{"format": "opennook.theme", "version": "1"}"#), .notATheme)
        XCTAssertEqual(decodingError(#"{"format": "opennook.theme", "version": true}"#), .notATheme)
        XCTAssertEqual(decodingError(#"{"format": "opennook.theme", "version": 1.5}"#), .notATheme)
    }

    func testRejectsFormatVersionsItCannotRead() {
        XCTAssertEqual(decodingError(#"{"format": "opennook.theme", "version": 2}"#), .unsupportedVersion(2))
        XCTAssertEqual(decodingError(#"{"format": "opennook.theme", "version": 0}"#), .unsupportedVersion(0))
    }

    func testNamesThePathOfAValueWithTheWrongType() {
        guard
            case .invalidValue(let detail)? = decodingError(
                #"{"format": "opennook.theme", "version": 1, "scale": "big"}"#
            )
        else {
            return XCTFail("expected an invalid value")
        }
        XCTAssertTrue(detail.hasPrefix("scale should be a number"), detail)
        guard
            case .invalidValue(let nested)? = decodingError(
                #"{"format": "opennook.theme", "version": 1, "components": {"banner.cornerRadius": true}}"#
            )
        else {
            return XCTFail("expected an invalid value")
        }
        XCTAssertTrue(nested.hasPrefix("components.banner.cornerRadius"), nested)
        XCTAssertNotNil(NookThemeError.invalidValue(nested).errorDescription)
    }

    func testLoadsAThemeFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "opennook-theme-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let theme = NookTheme(accent: "#FF8C4D", scale: 1.1)
        try theme.jsonData().write(to: url)
        XCTAssertEqual(try NookTheme(contentsOf: url), theme)
    }
}

/// Every token id that has ever shipped keeps working: it is defined, or the rename map says
/// what became of it. And every defined id is on the list, so the next change that removes one
/// is caught.
final class NookThemeTokenIDTests: XCTestCase {
    private func shippedIDs() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/theme-token-ids.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func testEveryShippedIDIsDefinedOrRenamed() throws {
        for id in try shippedIDs() {
            let known = NookTokenRegistry.entry(for: id) != nil || NookTokenRenames.map[id] != nil
            XCTAssertTrue(known, "\(id) shipped but is neither defined nor in NookTokenRenames.map")
            if let current = NookTokenRenames.currentID(for: id) {
                XCTAssertNotNil(
                    NookTokenRegistry.entry(for: current),
                    "\(id) is renamed to \(current), which is not defined"
                )
            }
        }
    }

    func testEveryDefinedIDIsListed() throws {
        let shipped = Set(try shippedIDs())
        for entry in NookTokenRegistry.allIDs {
            XCTAssertTrue(shipped.contains(entry.id), "\(entry.id) is defined but missing from theme-token-ids.txt")
        }
    }

    func testTheListIsSortedWithoutDuplicates() throws {
        let ids = try shippedIDs()
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

/// The theme files in Examples/Themes load cleanly, so a token rename or a stricter check
/// cannot leave a sample people copy from reporting issues.
final class NookExampleThemeFilesTests: XCTestCase {
    func testEveryExampleThemeLoadsWithoutIssues() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Examples/Themes")
            .standardizedFileURL
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty, "no theme files in \(folder.path)")
        for file in files {
            let result = try NookThemeCoder.decode(Data(contentsOf: file))
            XCTAssertEqual(result.issues, [], file.lastPathComponent)
            XCTAssertNotNil(result.theme.name, file.lastPathComponent)
            XCTAssertNotNil(result.theme.backdrops.solid, file.lastPathComponent)
            XCTAssertNotEqual(result.theme, .standard, file.lastPathComponent)
        }
    }
}
