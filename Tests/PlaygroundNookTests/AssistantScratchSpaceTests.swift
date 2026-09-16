// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The one place a reference image is written to disk, because `codex --image` takes a path. The
/// privacy promise rests on these tests: only in a private directory, only for the length of the
/// request, and only when the provider can actually use it.
final class AssistantScratchSpaceTests: XCTestCase {
    private let space = AssistantTemporaryDirectory()
    private var made: [AssistantScratchFiles] = []

    override func tearDown() {
        for files in made {
            space.discard(files)
        }
        made = []
        super.tearDown()
    }

    private func makeFiles(
        attachments: [AssistantAttachment] = [],
        capabilities: AssistantCapabilities = AssistantCLIProvider.Tool.codex.capabilities
    ) throws -> AssistantScratchFiles {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "match this", attachments: attachments))
        let request = try conversation.request(
            preset: PlaygroundPreset(),
            model: "",
            capabilities: capabilities
        )
        let files = try space.makeFiles(for: request, capabilities: capabilities)
        made.append(files)
        return files
    }

    private func attachment(_ byte: UInt8) -> AssistantAttachment {
        AssistantAttachment(jpeg: Data([0xFF, 0xD8, byte]), pixelWidth: 400, pixelHeight: 300)
    }

    func testTheSchemaIsWrittenWhereTheToolCanReadIt() throws {
        let files = try makeFiles()
        let schema = try XCTUnwrap(files.schema)

        XCTAssertTrue(FileManager.default.fileExists(atPath: schema.path))
        let written = try Data(contentsOf: schema)
        XCTAssertEqual(written, AssistantSchema.response.data)
        XCTAssertNotNil(AssistantJSON(parsing: written), "the tool would be handed something that is not JSON")
    }

    func testEachImageIsWrittenInOrder() throws {
        let files = try makeFiles(attachments: [attachment(1), attachment(2)])

        XCTAssertEqual(files.images.count, 2)
        XCTAssertEqual(files.images.map { $0.lastPathComponent }, ["reference-1.jpg", "reference-2.jpg"])
        XCTAssertEqual(try Data(contentsOf: files.images[0]).last, 1)
        XCTAssertEqual(try Data(contentsOf: files.images[1]).last, 2)
    }

    /// A screenshot of someone's screen is nobody else's business, so the directory is readable only
    /// by its owner.
    func testTheDirectoryIsPrivateToThisUser() throws {
        let files = try makeFiles(attachments: [attachment(1)])
        let attributes = try FileManager.default.attributesOfItem(atPath: files.directory.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.int16Value, 0o700, "the directory is readable by others")
    }

    /// Nothing is written for a provider that cannot use it. claude cannot take an image, so no image
    /// touches the disk on its behalf.
    func testNothingIsWrittenForAProviderThatCannotUseIt() throws {
        let files = try makeFiles(
            attachments: [attachment(1)],
            capabilities: AssistantCLIProvider.Tool.claude.capabilities
        )
        XCTAssertNil(files.schema)
        XCTAssertEqual(files.images, [])
        let contents = try FileManager.default.contentsOfDirectory(atPath: files.directory.path)
        XCTAssertEqual(contents, [], "\(contents) was written for a provider that cannot read it")
    }

    func testDiscardingRemovesEverything() throws {
        let files = try makeFiles(attachments: [attachment(1), attachment(2)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.directory.path))

        space.discard(files)

        XCTAssertFalse(FileManager.default.fileExists(atPath: files.directory.path))
        for image in files.images {
            XCTAssertFalse(FileManager.default.fileExists(atPath: image.path), "\(image.path) survived")
        }
    }

    /// Two requests cannot see each other's references.
    func testEachRequestGetsItsOwnDirectory() throws {
        let first = try makeFiles(attachments: [attachment(1)])
        let second = try makeFiles(attachments: [attachment(2)])
        XCTAssertNotEqual(first.directory, second.directory)

        space.discard(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directory.path))
    }

    /// Nothing is written anywhere the person keeps their own work.
    func testTheDirectoryIsUnderTheSystemTemporaryDirectory() throws {
        let files = try makeFiles()
        XCTAssertTrue(
            files.directory.path.hasPrefix(FileManager.default.temporaryDirectory.path),
            files.directory.path
        )
        XCTAssertTrue(files.directory.lastPathComponent.hasPrefix("opennook-playground-assistant-"))
    }
}
