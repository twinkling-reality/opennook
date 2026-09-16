// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The files one command line request needs, and where they live.
public struct AssistantScratchFiles: Sendable, Equatable {
    /// The directory holding them, which is also where the tool is run.
    public var directory: URL
    /// The JSON schema, for a tool that can be told to answer against one.
    public var schema: URL?
    /// The reference images, in the order they were attached.
    public var images: [URL]

    public init(directory: URL, schema: URL? = nil, images: [URL] = []) {
        self.directory = directory
        self.schema = schema
        self.images = images
    }
}

/// Somewhere to put the few files a command line tool has to be handed by path.
///
/// A command line tool cannot be given an image over a pipe, so `codex --image` needs a real file.
/// That is the one place the media pipeline's "stays in memory" rule bends, so it bends narrowly and
/// visibly: one directory per request, readable only by this user, deleted as soon as the tool exits,
/// whether it succeeded, failed, or was cancelled. Nothing is written anywhere the person keeps their
/// own files, and nothing outlives the request.
public protocol AssistantScratchSpace: Sendable {
    func makeFiles(
        for request: AssistantRequest,
        capabilities: AssistantCapabilities
    ) throws -> AssistantScratchFiles

    /// Removes everything ``makeFiles(for:capabilities:)`` created.
    func discard(_ files: AssistantScratchFiles)
}

/// A per-request directory under the system temporary directory.
public struct AssistantTemporaryDirectory: AssistantScratchSpace {
    public init() {}

    public func makeFiles(
        for request: AssistantRequest,
        capabilities: AssistantCapabilities
    ) throws -> AssistantScratchFiles {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opennook-playground-assistant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            // This directory holds a screenshot someone dropped in. Nobody else on the machine needs
            // to be able to read it.
            attributes: [.posixPermissions: 0o700]
        )

        var files = AssistantScratchFiles(directory: directory)
        if capabilities.enforcesSchema {
            let schema = directory.appendingPathComponent("answer-schema.json")
            try request.schema.data.write(to: schema, options: .atomic)
            files.schema = schema
        }
        if capabilities.acceptsImages {
            for (index, attachment) in request.attachments.enumerated() {
                let image = directory.appendingPathComponent("reference-\(index + 1).jpg")
                try attachment.jpeg.write(to: image, options: .atomic)
                files.images.append(image)
            }
        }
        return files
    }

    public func discard(_ files: AssistantScratchFiles) {
        try? FileManager.default.removeItem(at: files.directory)
    }
}
