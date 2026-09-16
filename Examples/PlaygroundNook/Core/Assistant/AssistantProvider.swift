// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Something that can answer a request about the playground's settings.
///
/// Deliberately small. A provider takes a built request and hands back a stream of text as it
/// arrives; it does not know about presets, patches, or proposals, and it never applies anything.
/// Everything above it (prompt building, parsing, the repair round, the diff) is shared, so a new
/// provider is a request builder and a response reader and nothing else.
///
/// Cancellation is the caller's task being cancelled. A provider must stop its work and finish its
/// stream when that happens, which for an HTTP provider means the URLSession task and for a command
/// line provider means the child process.
public protocol AssistantProvider: Sendable {
    var identity: AssistantProviderIdentity { get }
    var capabilities: AssistantCapabilities { get }

    /// The answer as it arrives. The text of every ``AssistantEvent/text(_:)`` joined in order is
    /// the whole answer.
    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, any Error>
}

/// Which provider this is, for the setup panel and for the record of what was sent.
public struct AssistantProviderIdentity: Sendable, Equatable, Identifiable {
    /// Stable, and stored in defaults, so it cannot be renamed casually.
    public let id: String
    /// What the composer's header calls it, such as `codex`.
    public let name: String
    /// One line for the setup panel, such as "Uses the codex you are already signed in to".
    public let summary: String

    public init(id: String, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// What a provider can and cannot do, so the composer can disable a control and say why rather
/// than letting a request fail halfway.
public struct AssistantCapabilities: Sendable, Equatable {
    /// Whether the provider can be sent images at all.
    public var acceptsImages: Bool
    /// Why not, in a sentence fit for a tooltip, when it cannot. Shown next to a disabled
    /// paperclip and in place of a silent failure when media is dropped.
    public var imageLimit: String?
    /// The longest edge, in pixels, images should be scaled to for this provider.
    public var imageEdge: Int
    /// How many attachments one turn may carry.
    public var maximumAttachments: Int
    /// Whether the provider makes the model answer against the schema. When it does, the field
    /// guide is left out of the prompt, since the schema already carries every name, bound, and
    /// one-line meaning.
    public var enforcesSchema: Bool
    /// Whether the provider needs a key in the Keychain before it can be used. False for the
    /// command line providers, which reuse a sign-in the person already has, and for a local model.
    public var needsAPIKey: Bool
    /// Whether the provider reaches the network at all.
    public var usesNetwork: Bool

    public init(
        acceptsImages: Bool,
        imageLimit: String? = nil,
        imageEdge: Int = 1568,
        maximumAttachments: Int = 4,
        enforcesSchema: Bool,
        needsAPIKey: Bool,
        usesNetwork: Bool
    ) {
        self.acceptsImages = acceptsImages
        self.imageLimit = imageLimit
        self.imageEdge = imageEdge
        self.maximumAttachments = maximumAttachments
        self.enforcesSchema = enforcesSchema
        self.needsAPIKey = needsAPIKey
        self.usesNetwork = usesNetwork
    }
}

/// One reference image, already processed: downscaled for the provider, re-encoded, and stripped of
/// everything a camera or a screenshot put in it.
///
/// The pixels are only sent to a provider that can see them. The measurements and the palette are
/// worked out on this machine either way, so "match this screenshot" still does something useful
/// through a provider that only takes text.
public struct AssistantAttachment: Sendable, Equatable, Identifiable {
    public enum Origin: Sendable, Equatable {
        case image
        /// A frame lifted out of a screen recording, and where it came from.
        case videoFrame(seconds: Double)
    }

    public let id: UUID
    public let origin: Origin
    /// JPEG, downscaled and with its metadata dropped. Never written to disk by the playground.
    public let jpeg: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Dominant colors, sampled from the pixels on this machine, most common first.
    public let palette: [PlaygroundColor]
    /// Short facts measured locally, such as "mostly dark", one per line in the prompt.
    public let measurements: [String]

    public init(
        id: UUID = UUID(),
        origin: Origin = .image,
        jpeg: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        palette: [PlaygroundColor] = [],
        measurements: [String] = []
    ) {
        self.id = id
        self.origin = origin
        self.jpeg = jpeg
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.palette = palette
        self.measurements = measurements
    }

    /// What VoiceOver and the thumbnail's tooltip call it.
    public var label: String {
        switch origin {
            case .image:
                return "Reference image, \(pixelWidth) by \(pixelHeight)"
            case .videoFrame(let seconds):
                let time = seconds.formatted(.number.precision(.fractionLength(1)))
                return "Recording frame at \(time) seconds, \(pixelWidth) by \(pixelHeight)"
        }
    }
}

/// One side of the conversation.
public struct AssistantTurn: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Equatable {
        case person
        case assistant
    }

    public let id: UUID
    public var role: Role
    public var text: String
    public var attachments: [AssistantAttachment]

    public init(id: UUID = UUID(), role: Role, text: String, attachments: [AssistantAttachment] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
    }
}

/// Everything a provider needs for one call, already built. Holding it as a value is what lets the
/// request inspector show a person exactly what would be sent, before it is sent.
public struct AssistantRequest: Sendable, Equatable {
    public var systemPrompt: String
    public var turns: [AssistantTurn]
    /// The schema the answer must match, for providers that can enforce one.
    public var schema: AssistantJSON
    public var model: String
    /// Whether the images on the turns will actually be sent.
    public var sendsImages: Bool

    public init(
        systemPrompt: String,
        turns: [AssistantTurn],
        schema: AssistantJSON = AssistantSchema.response,
        model: String,
        sendsImages: Bool
    ) {
        self.systemPrompt = systemPrompt
        self.turns = turns
        self.schema = schema
        self.model = model
        self.sendsImages = sendsImages
    }

    /// The images that would be sent, in order.
    public var attachments: [AssistantAttachment] {
        sendsImages ? turns.flatMap(\.attachments) : []
    }
}

/// Something a provider has to say while it works.
public enum AssistantEvent: Sendable, Equatable {
    /// The next piece of the answer.
    case text(String)
    /// Progress worth showing but not part of the answer, such as a command line tool reporting
    /// that it has started.
    case note(String)
}

/// Why a provider could not answer. Every case reads as a sentence a person can act on, because
/// every case can end up in the composer's error row.
public enum AssistantProviderError: Error, Equatable, LocalizedError {
    /// No key in the Keychain, or a key the service rejected.
    case notAuthorized(provider: String, detail: String?)
    /// The command line tool is not on the PATH any more.
    case toolMissing(command: String)
    /// The tool ran but failed. The detail is its last line of output, trimmed.
    case toolFailed(command: String, status: Int32, detail: String)
    /// A local server that is installed but not running.
    case serviceUnavailable(provider: String, hint: String)
    case rateLimited(provider: String, retryAfter: Double?)
    /// The transport failed: no network, a timeout, a refused connection.
    case transport(detail: String)
    /// The service answered, but not with anything usable.
    case badResponse(detail: String)
    /// The model was asked for images through a provider that cannot take them. The composer stops
    /// this before it happens, so reaching it is a bug rather than something a person can fix.
    case imagesNotSupported(provider: String)

    public var errorDescription: String? {
        switch self {
            case .notAuthorized(let provider, let detail):
                if let detail {
                    return Self.sentence("\(provider) would not accept the sign-in: \(detail)")
                }
                return "\(provider) needs to be signed in again."
            case .toolMissing(let command):
                return "\(command) is not on your PATH any more."
            case .toolFailed(let command, let status, let detail):
                return detail.isEmpty
                    ? "\(command) exited with status \(status)." : Self.sentence("\(command): \(detail)")
            case .serviceUnavailable(let provider, let hint):
                return "\(provider) is not running. \(hint)"
            case .rateLimited(let provider, let retryAfter):
                if let retryAfter {
                    let seconds = retryAfter.formatted(.number.precision(.fractionLength(0)))
                    return "\(provider) is rate limited. Try again in \(seconds) seconds."
                }
                return "\(provider) is rate limited. Try again in a moment."
            case .transport(let detail):
                return Self.sentence("The request could not be sent: \(detail)")
            case .badResponse(let detail):
                return Self.sentence("The answer could not be read: \(detail)")
            case .imagesNotSupported(let provider):
                return "\(provider) cannot see images."
        }
    }

    /// `text` ending in punctuation. The detail in these messages comes from a service or a command
    /// line tool, which rarely ends a sentence, and the composer shows the whole thing as one line.
    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return trimmed }
        return trimmed + "."
    }

    /// Whether offering Retry makes sense, or whether something has to change first.
    public var isWorthRetrying: Bool {
        switch self {
            case .transport, .rateLimited, .badResponse, .toolFailed:
                true
            case .notAuthorized, .toolMissing, .serviceUnavailable, .imagesNotSupported:
                false
        }
    }
}
