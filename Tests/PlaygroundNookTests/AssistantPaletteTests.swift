// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import CoreGraphics
import XCTest

@testable import PlaygroundNookCore

/// The palette read from a reference image. This is what makes "copy this style" produce the colors
/// that are really in the screenshot rather than a model's estimate of them, so it has to be right
/// and it has to be the same every time.
final class AssistantPaletteTests: XCTestCase {
    // MARK: - Reading colors

    func testASolidImageReadsAsThatOneColor() {
        let reading = AssistantPalette.read(
            AssistantMediaFixtures.solid(red: 0.11, green: 0.11, blue: 0.13)
        )
        let first = reading.palette.first
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.red ?? 0, 0.11, accuracy: 0.02)
        XCTAssertEqual(first?.blue ?? 0, 0.13, accuracy: 0.02)
        // One flat color is one entry, not five near-identical ones.
        XCTAssertEqual(reading.palette.count, 1)
    }

    /// The order is what the model is told to trust, so the color covering most of the image has to
    /// come first.
    func testTheMostCommonColorComesFirst() {
        let image = AssistantMediaFixtures.image(
            width: 120,
            height: 120,
            bands: [
                (0.05, 0.05, 0.07),
                (0.05, 0.05, 0.07),
                (0.05, 0.05, 0.07),
                (0.95, 0.35, 0.1),
            ]
        )
        let reading = AssistantPalette.read(image)

        XCTAssertEqual(reading.palette.count, 2)
        let background = try? XCTUnwrap(reading.palette.first)
        let accent = try? XCTUnwrap(reading.palette.last)
        XCTAssertLessThan(background?.red ?? 1, 0.2, "the dark background should be first")
        XCTAssertGreaterThan(accent?.red ?? 0, 0.8, "the orange accent should be second")
    }

    func testUpToFiveColorsAreReported() {
        let image = AssistantMediaFixtures.image(
            width: 140,
            height: 140,
            bands: [
                (0, 0, 0),
                (1, 1, 1),
                (0.9, 0.1, 0.1),
                (0.1, 0.9, 0.1),
                (0.1, 0.1, 0.9),
                (0.9, 0.9, 0.1),
                (0.9, 0.1, 0.9),
            ]
        )
        XCTAssertEqual(AssistantPalette.read(image).palette.count, AssistantPalette.colorCount)
    }

    func testHowManyColorsAreReportedCanBeAsked() {
        let image = AssistantMediaFixtures.image(
            width: 100,
            height: 100,
            bands: [(0, 0, 0), (1, 1, 1), (0.9, 0.1, 0.1), (0.1, 0.9, 0.1)]
        )
        XCTAssertEqual(AssistantPalette.read(image, colorCount: 2).palette.count, 2)
    }

    /// A gradient is one apparent color to a person, so it should not use up all five slots on
    /// shades of itself.
    func testAGradientDoesNotFillThePaletteWithNearlyTheSameColor() {
        let bands = (0..<24).map { index in
            (red: 0.10 + Double(index) * 0.001, green: 0.10, blue: 0.12)
        }
        let reading = AssistantPalette.read(AssistantMediaFixtures.image(width: 120, height: 120, bands: bands))
        XCTAssertLessThanOrEqual(reading.palette.count, 2, "\(reading.palette.map(\.hex))")
    }

    /// A transparent region has no color to contribute, and must not read as a vote for black.
    func testFullyTransparentPixelsAreIgnored() {
        let reading = AssistantPalette.read(AssistantMediaFixtures.halfTransparent())
        let first = try? XCTUnwrap(reading.palette.first)
        XCTAssertGreaterThan(first?.red ?? 0, 0.7, "\(reading.palette.map(\.hex))")
        XCTAssertFalse(reading.palette.contains { $0.hex == "#000000" }, "\(reading.palette.map(\.hex))")
    }

    /// A request has to be reproducible, which means the palette cannot depend on dictionary order.
    func testThePaletteIsTheSameEveryTime() {
        let image = AssistantMediaFixtures.image(
            width: 128,
            height: 128,
            bands: [(0.1, 0.1, 0.12), (0.94, 0.94, 0.96), (0.2, 0.5, 0.95), (0.9, 0.4, 0.1)]
        )
        let first = AssistantPalette.read(image).palette.map(\.hex)
        XCTAssertFalse(first.isEmpty)
        for _ in 0..<12 {
            XCTAssertEqual(AssistantPalette.read(image).palette.map(\.hex), first)
        }
    }

    // MARK: - Measurements

    func testADarkScreenshotIsMeasuredAsDark() {
        let reading = AssistantPalette.read(AssistantMediaFixtures.solid(red: 0.06, green: 0.06, blue: 0.07))
        XCTAssertTrue(reading.measurements.contains("Very dark overall"), "\(reading.measurements)")
    }

    func testALightScreenshotIsMeasuredAsLight() {
        let reading = AssistantPalette.read(AssistantMediaFixtures.solid(red: 0.96, green: 0.96, blue: 0.97))
        XCTAssertTrue(reading.measurements.contains("Mostly light"), "\(reading.measurements)")
    }

    func testAGreyScreenshotIsMeasuredAsNeutral() {
        let reading = AssistantPalette.read(AssistantMediaFixtures.solid(red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertTrue(
            reading.measurements.contains("Close to neutral greys, very little color"),
            "\(reading.measurements)"
        )
    }

    func testAColorfulScreenshotIsMeasuredAsColored() {
        let reading = AssistantPalette.read(AssistantMediaFixtures.solid(red: 0.95, green: 0.25, blue: 0.05))
        XCTAssertTrue(reading.measurements.contains("Strongly colored"), "\(reading.measurements)")
    }

    /// The measurements name the dominant color, because a provider that cannot see the image gets
    /// only these lines.
    func testTheMeasurementsNameTheDominantColor() {
        let reading = AssistantPalette.read(AssistantMediaFixtures.solid(red: 0.1, green: 0.1, blue: 0.12))
        let hex = try? XCTUnwrap(reading.palette.first?.hex)
        XCTAssertTrue(reading.measurements.contains { $0.contains(hex ?? "") }, "\(reading.measurements)")
    }

    func testAnImageWithNoOpaquePixelsReadsAsNothingRatherThanCrashing() {
        let clear = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!

        let reading = AssistantPalette.read(clear)
        XCTAssertEqual(reading.palette, [])
        XCTAssertEqual(reading.measurements, [])
    }

    // MARK: - Reaching the prompt

    /// The whole reason the palette is measured here: the hex values are in the text of the request
    /// even when the model cannot see the image.
    func testTheSampledColorsReachTheRequestWithoutTheImage() throws {
        let attachment = try AssistantMedia.attachment(
            from: AssistantMediaFixtures.png(
                AssistantMediaFixtures.image(
                    width: 400,
                    height: 300,
                    bands: [(0.07, 0.07, 0.09), (0.07, 0.07, 0.09), (0.95, 0.4, 0.15)]
                )
            ),
            name: "reference.png",
            edge: 1568
        )
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "match this style", attachments: [attachment]))

        let request = try conversation.request(
            preset: PlaygroundPreset(),
            model: "example",
            capabilities: .fakeWithoutImages
        )

        XCTAssertTrue(request.attachments.isEmpty)
        let text = request.turns[0].text
        for color in attachment.palette {
            XCTAssertTrue(text.contains(color.hex), "\(color.hex) is not in the request: \(text)")
        }
        XCTAssertTrue(text.contains("Mostly dark") || text.contains("Very dark overall"), text)
    }
}
