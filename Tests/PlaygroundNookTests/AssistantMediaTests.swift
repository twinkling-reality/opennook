// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import PlaygroundNookCore

/// The media pipeline: what a dropped file becomes before anything is sent, and what it stops being.
final class AssistantMediaTests: XCTestCase {
    // MARK: - Scaling

    func testALargeImageIsScaledToTheProvidersEdge() throws {
        let data = AssistantMediaFixtures.png(
            AssistantMediaFixtures.solid(width: 3000, height: 1500, red: 0.1, green: 0.1, blue: 0.12)
        )
        let attachment = try AssistantMedia.attachment(from: data, name: "shot.png", edge: 1568)

        XCTAssertEqual(attachment.pixelWidth, 1568)
        XCTAssertEqual(attachment.pixelHeight, 784, "the aspect ratio was not kept")
    }

    func testATallImageIsScaledByItsLongestEdge() throws {
        let data = AssistantMediaFixtures.png(
            AssistantMediaFixtures.solid(width: 800, height: 2400, red: 0.9, green: 0.9, blue: 0.9)
        )
        let attachment = try AssistantMedia.attachment(from: data, name: "tall.png", edge: 1024)

        XCTAssertEqual(attachment.pixelHeight, 1024)
        XCTAssertLessThanOrEqual(attachment.pixelWidth, 1024)
    }

    /// A small screenshot is left alone rather than blown up, which would only cost bytes.
    func testASmallImageIsNotEnlarged() throws {
        let data = AssistantMediaFixtures.png(
            AssistantMediaFixtures.solid(width: 320, height: 200, red: 0.2, green: 0.4, blue: 0.9)
        )
        let attachment = try AssistantMedia.attachment(from: data, name: "small.png", edge: 1568)

        XCTAssertEqual(attachment.pixelWidth, 320)
        XCTAssertEqual(attachment.pixelHeight, 200)
    }

    func testEachProvidersEdgeIsHonoured() throws {
        let data = AssistantMediaFixtures.png(
            AssistantMediaFixtures.solid(width: 4000, height: 4000, red: 0.5, green: 0.5, blue: 0.5)
        )
        for edge in [1568, 1536, 1024] {
            let attachment = try AssistantMedia.attachment(from: data, name: "square.png", edge: edge)
            XCTAssertEqual(attachment.pixelWidth, edge)
        }
    }

    /// A PNG screenshot comes out as JPEG, which is what every provider wants and a fraction of the
    /// bytes.
    func testTheOutputIsAlwaysJPEG() throws {
        let data = AssistantMediaFixtures.png(
            AssistantMediaFixtures.solid(width: 600, height: 400, red: 0.15, green: 0.15, blue: 0.18)
        )
        let attachment = try AssistantMedia.attachment(from: data, name: "shot.png", edge: 1568)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(attachment.jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    }

    // MARK: - Privacy

    /// The point of re-encoding: nothing the original file carried about where and when it was taken
    /// can reach a provider.
    func testMetadataIsStrippedBeforeAnythingIsSent() throws {
        let original = AssistantMediaFixtures.jpegWithMetadata(
            AssistantMediaFixtures.solid(width: 900, height: 600, red: 0.4, green: 0.5, blue: 0.6)
        )
        // The fixture really does carry what the test is about to look for.
        let before = AssistantMediaFixtures.metadataKeys(of: original)
        XCTAssertTrue(before.contains(kCGImagePropertyExifDictionary as String), "\(before)")
        XCTAssertTrue(before.contains(kCGImagePropertyGPSDictionary as String), "\(before)")

        let attachment = try AssistantMedia.attachment(from: original, name: "photo.jpg", edge: 1568)
        let after = AssistantMediaFixtures.metadataKeys(of: attachment.jpeg)

        XCTAssertFalse(after.contains(kCGImagePropertyGPSDictionary as String), "the location survived: \(after)")
        XCTAssertFalse(after.contains(kCGImagePropertyTIFFDictionary as String), "the device survived: \(after)")
        for key in after {
            XCTAssertFalse(key.lowercased().contains("gps"), "\(key) survived")
        }
    }

    /// The orientation tag is applied on the way through, because the tag itself is dropped. Without
    /// this, a sideways photo would be sent sideways.
    func testOrientationIsAppliedRatherThanLost() throws {
        // Orientation 6 means the stored pixels are rotated a quarter turn.
        let sideways = AssistantMediaFixtures.jpegWithMetadata(
            AssistantMediaFixtures.solid(width: 400, height: 200, red: 0.3, green: 0.6, blue: 0.2),
            orientation: 6
        )
        let attachment = try AssistantMedia.attachment(from: sideways, name: "sideways.jpg", edge: 1568)

        XCTAssertEqual(attachment.pixelWidth, 200, "the orientation tag was ignored")
        XCTAssertEqual(attachment.pixelHeight, 400)
    }

    // MARK: - Rejections

    func testAFileOverTheSizeLimitSaysSo() {
        let big = Data(repeating: 0, count: 21 * 1024 * 1024)
        XCTAssertThrowsError(try AssistantMedia.attachment(from: big, name: "huge.png", edge: 1568)) { error in
            guard case .tooLarge(let name, _, let limit) = error as? AssistantMediaRejection else {
                return XCTFail("expected tooLarge, got \(error)")
            }
            XCTAssertEqual(name, "huge.png")
            XCTAssertEqual(limit, AssistantMediaLimits.default.maximumBytes)
            XCTAssertEqual(error.localizedDescription, "huge.png is 21 MB, over the 20 MB limit.")
        }
    }

    func testSomethingThatIsNotAnImageSaysSo() {
        let notAnImage = Data("this is a text file".utf8)
        XCTAssertThrowsError(try AssistantMedia.attachment(from: notAnImage, name: "notes.txt", edge: 1568)) { error in
            XCTAssertEqual(error as? AssistantMediaRejection, .unreadable(name: "notes.txt"))
        }
    }

    func testEveryRejectionSaysWhichOfTypeSizeOrCountWasWrong() {
        let rejections: [AssistantMediaRejection] = [
            .unsupportedType(name: "song.mp3"),
            .tooLarge(name: "huge.png", bytes: 30_000_000, limit: 20_971_520),
            .tooMany(limit: 4),
            .unreadable(name: "broken.png"),
            .videoTooLong(name: "clip.mov", seconds: 90, limit: 60),
            .noFrames(name: "clip.mov"),
        ]
        for rejection in rejections {
            let text = try? XCTUnwrap(rejection.errorDescription)
            XCTAssertNotNil(text)
            XCTAssertTrue(text?.hasSuffix(".") ?? false, "\(rejection) does not read as a sentence")
        }
        XCTAssertEqual(AssistantMediaRejection.tooMany(limit: 4).errorDescription, "Only 4 references at a time.")
    }

    // MARK: - Which files are taken

    func testScreenshotsAndRecordingsAreAccepted() {
        for type in [UTType.png, .jpeg, .heic, .tiff, .gif] {
            XCTAssertTrue(AssistantMedia.isSupported(type), "\(type.identifier) should be accepted")
            XCTAssertFalse(AssistantMedia.isVideo(type))
        }
        for type in [UTType.quickTimeMovie, .mpeg4Movie] {
            XCTAssertTrue(AssistantMedia.isSupported(type), "\(type.identifier) should be accepted")
            XCTAssertTrue(AssistantMedia.isVideo(type))
        }
    }

    func testOtherFilesAreNotAccepted() {
        for type in [UTType.pdf, .mp3, .plainText, .json, .zip] {
            XCTAssertFalse(AssistantMedia.isSupported(type), "\(type.identifier) should not be accepted")
        }
    }

    /// An animated GIF is taken as its first frame, since a still is what a reference needs to be.
    func testAnAnimatedGIFBecomesOneStill() throws {
        let frames = [
            AssistantMediaFixtures.solid(width: 200, height: 100, red: 0.1, green: 0.1, blue: 0.1),
            AssistantMediaFixtures.solid(width: 200, height: 100, red: 0.9, green: 0.9, blue: 0.9),
        ]
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, 2, nil)
        )
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let attachment = try AssistantMedia.attachment(from: data as Data, name: "loop.gif", edge: 1568)
        XCTAssertEqual(attachment.pixelWidth, 200)
        XCTAssertEqual(attachment.pixelHeight, 100)
        // The first frame is the dark one.
        let first = try XCTUnwrap(attachment.palette.first)
        XCTAssertLessThan(first.red, 0.3)
    }
}
