// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// Lifting frames out of a screen recording. The recordings are written in code into a temporary
/// directory, so no fixture files are checked in and nothing outside that directory is touched.
final class AssistantVideoFramesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssistantVideoFramesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private func movie(seconds: Double) async throws -> URL {
        let url = directory.appendingPathComponent("clip-\(Int(seconds * 10)).mov")
        try await AssistantMediaFixtures.movie(at: url, seconds: seconds)
        return url
    }

    // MARK: - Where the frames come from

    func testFramesAreSpreadAcrossTheMiddleOfTheClip() {
        let times = AssistantVideoFrames.times(across: 10, count: 4)
        XCTAssertEqual(times, [1, 3.6666666666666665, 6.333333333333333, 9])
    }

    /// The first and last moments of a screen recording are the least useful in it, so nothing is
    /// taken from the very start or the very end.
    func testNoFrameIsTakenFromTheVeryStartOrEnd() {
        for duration in [1.0, 4.0, 12.0, 60.0] {
            let times = AssistantVideoFrames.times(across: duration, count: 4)
            XCTAssertGreaterThan(times.first ?? 0, 0)
            XCTAssertLessThan(times.last ?? duration, duration)
        }
    }

    func testOneFrameComesFromTheMiddle() {
        XCTAssertEqual(AssistantVideoFrames.times(across: 8, count: 1), [4])
    }

    func testAClipOfNoLengthAsksForNoFrames() {
        XCTAssertEqual(AssistantVideoFrames.times(across: 0, count: 4), [])
        XCTAssertEqual(AssistantVideoFrames.times(across: 10, count: 0), [])
    }

    // MARK: - Real recordings

    func testARecordingBecomesAFewStills() async throws {
        let url = try await movie(seconds: 3)
        let frames = try await AssistantVideoFrames.frames(at: url, edge: 1024)

        XCTAssertEqual(frames.count, AssistantMediaLimits.default.framesPerVideo)
        for frame in frames {
            guard case .videoFrame(let seconds) = frame.origin else {
                return XCTFail("a frame did not know it came from a recording")
            }
            XCTAssertGreaterThan(seconds, 0)
            XCTAssertFalse(frame.jpeg.isEmpty)
            XCTAssertEqual(frame.pixelWidth, 160)
            XCTAssertEqual(frame.pixelHeight, 120)
            XCTAssertFalse(frame.palette.isEmpty, "a frame was not measured")
        }
    }

    /// Different moments give different frames, which is the point of taking several.
    func testDifferentMomentsGiveDifferentFrames() async throws {
        let url = try await movie(seconds: 3)
        let frames = try await AssistantVideoFrames.frames(at: url, edge: 1024)

        let firstColor = try XCTUnwrap(frames.first?.palette.first)
        let lastColor = try XCTUnwrap(frames.last?.palette.first)
        XCTAssertNotEqual(firstColor.hex, lastColor.hex)
    }

    /// A frame says where in the clip it came from, so the strip can label it and the person can tell
    /// which moment they are keeping.
    func testAFrameSaysWhereItCameFrom() async throws {
        let url = try await movie(seconds: 3)
        let frames = try await AssistantVideoFrames.frames(at: url, edge: 1024)

        let label = try XCTUnwrap(frames.first?.label)
        XCTAssertTrue(label.hasPrefix("Recording frame at"), label)
        XCTAssertTrue(label.contains("160 by 120"), label)
    }

    func testHowManyFramesAreTakenCanBeAsked() async throws {
        let url = try await movie(seconds: 3)
        var limits = AssistantMediaLimits.default
        limits.framesPerVideo = 2

        let frames = try await AssistantVideoFrames.frames(at: url, edge: 1024, limits: limits)
        XCTAssertEqual(frames.count, 2)
    }

    // MARK: - Rejections

    func testALongRecordingSaysHowLongItIs() async throws {
        let url = try await movie(seconds: 3)
        var limits = AssistantMediaLimits.default
        limits.maximumVideoSeconds = 1

        do {
            _ = try await AssistantVideoFrames.frames(at: url, edge: 1024, limits: limits)
            XCTFail("expected the recording to be refused")
        } catch {
            guard case .videoTooLong(let name, let seconds, let limit) = error as? AssistantMediaRejection else {
                return XCTFail("expected videoTooLong, got \(error)")
            }
            XCTAssertEqual(name, url.lastPathComponent)
            XCTAssertEqual(seconds, 3, accuracy: 0.3)
            XCTAssertEqual(limit, 1)
        }
    }

    func testAFileThatIsNotARecordingIsRefused() async throws {
        let url = directory.appendingPathComponent("notes.mov")
        try Data("not a movie".utf8).write(to: url)

        do {
            _ = try await AssistantVideoFrames.frames(at: url, edge: 1024)
            XCTFail("expected the file to be refused")
        } catch {
            XCTAssertEqual(error as? AssistantMediaRejection, .unreadable(name: "notes.mov"))
        }
    }

    func testAMissingFileIsRefused() async throws {
        do {
            _ = try await AssistantVideoFrames.frames(at: directory.appendingPathComponent("gone.mov"), edge: 1024)
            XCTFail("expected the missing file to be refused")
        } catch {
            XCTAssertEqual(error as? AssistantMediaRejection, .unreadable(name: "gone.mov"))
        }
    }

    /// Nothing from a recording is left on disk by the pipeline: the frames live in memory only.
    func testNoFilesAreLeftBehind() async throws {
        let url = try await movie(seconds: 2)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

        _ = try await AssistantVideoFrames.frames(at: url, edge: 1024)

        let after = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(before, after)
    }
}
