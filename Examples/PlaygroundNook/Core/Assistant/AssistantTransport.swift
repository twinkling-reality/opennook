// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// A secret that does not print itself.
///
/// A key held as a `String` ends up in a log line, an error message, or a screenshot sooner or later,
/// because interpolating a string is the easiest thing in the world to do by accident. This type
/// makes that accident harmless: it describes itself as hidden everywhere a string would have shown
/// itself, and the value can only be reached through ``reveal()``, which is easy to search for.
public struct AssistantSecret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String

    public init(_ value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool { value.isEmpty }

    /// The secret itself. Called only where it is actually sent.
    public func reveal() -> String { value }

    public var description: String { "(hidden)" }
    public var debugDescription: String { "(hidden)" }

    /// The last few characters, for a settings row that has to show which key is stored without
    /// showing the key.
    public var hint: String {
        guard value.count > 4 else { return "(stored)" }
        return "..." + String(value.suffix(4))
    }
}

public enum AssistantHTTPEvent: Sendable, Equatable {
    case response(status: Int, headers: [String: String])
    case body(Data)
}

/// Sends one HTTP request and streams the reply.
///
/// Behind a protocol so every provider's request building and response reading is tested against a
/// fake, with no network and no keys. `URLSession` is the only implementation; the framework promises
/// no third-party dependencies and this needs none.
public protocol AssistantTransport: Sendable {
    func send(_ request: URLRequest) -> AsyncThrowingStream<AssistantHTTPEvent, any Error>
}

public struct AssistantURLSessionTransport: AssistantTransport {
    private let session: URLSession

    public init(session: URLSession = .assistantDefault) {
        self.session = session
    }

    public func send(_ request: URLRequest) -> AsyncThrowingStream<AssistantHTTPEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let response = response as? HTTPURLResponse {
                        var headers: [String: String] = [:]
                        for (name, value) in response.allHeaderFields {
                            if let name = name as? String, let value = value as? String {
                                headers[name.lowercased()] = value
                            }
                        }
                        continuation.yield(.response(status: response.statusCode, headers: headers))
                    }
                    // Line by line, because every service here streams either server-sent events or
                    // newline-delimited JSON, and both are line based.
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(.body(Data((line + "\n").utf8)))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: AssistantTransportFailure.urlError(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension URLSession {
    /// A session for the assistant: no caching of model answers, and a timeout long enough for a
    /// large local model to think but short enough that a dead endpoint does not hang the composer.
    public static let assistantDefault: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()
}

/// Turns a `URLError` into the provider error the composer shows.
enum AssistantTransportFailure {
    static func urlError(_ error: URLError) -> AssistantProviderError {
        switch error.code {
            case .cancelled:
                return .transport(detail: "the request was cancelled")
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .transport(detail: "there is no network connection")
            case .timedOut:
                return .transport(detail: "the service did not answer in time")
            case .cannotConnectToHost, .cannotFindHost:
                return .transport(detail: "nothing answered at \(error.failingURL?.host() ?? "that address")")
            default:
                return .transport(detail: error.localizedDescription)
        }
    }
}

/// Reads the two streaming formats these services use.
///
/// Both are line based, and a chunk of bytes off the wire can end mid-line, so the reader holds a
/// remainder between calls. Kept apart from the providers because it is the part most likely to be
/// wrong in a way that is invisible: a lost line is a truncated answer, not a crash.
public struct AssistantLineReader: Sendable {
    private var remainder = ""

    public init() {}

    /// The complete lines in `data`, with anything unfinished kept for next time.
    public mutating func lines(from data: Data) -> [String] {
        remainder += String(decoding: data, as: UTF8.self)
        var lines = remainder.components(separatedBy: "\n")
        // The last piece is either an unfinished line or empty; either way it waits.
        remainder = lines.removeLast()
        return lines
    }

    /// Whatever is left when the stream ends, if it is a line in its own right.
    public mutating func flush() -> [String] {
        let last = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        remainder = ""
        return last.isEmpty ? [] : [last]
    }
}

extension AssistantLineReader {
    /// The payload of a server-sent event line, or `nil` for the comments, event names, and blank
    /// lines that carry no data.
    public static func serverSentPayload(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        // The conventional end marker is not JSON and is not an answer.
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return payload
    }
}
