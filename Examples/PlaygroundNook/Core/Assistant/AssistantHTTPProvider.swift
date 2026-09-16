// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The providers that talk to a service over HTTP: a local model through Ollama, and the two hosted
/// APIs for anyone who would rather use a key than a command line tool.
///
/// Ollama is the one to reach for here. It runs on the machine, costs nothing, and sends nothing
/// anywhere, which suits an app whose whole subject is someone's own desktop. The two hosted services
/// are last on purpose: they are the only paths that cost money per request, and nothing about the
/// playground should need them.
///
/// One type rather than three, because the difference between these services is a URL, a header, the
/// shape of one JSON body, and where the text sits in a streamed event. Everything else, the
/// streaming, the cancellation, the status handling, is the same, and the parts that do differ are
/// switched on ``Service`` so a new service has to answer every question rather than inherit a
/// default that happens to be wrong.
public struct AssistantHTTPProvider: AssistantProvider {
    public enum Service: String, CaseIterable, Sendable {
        /// A model running on this machine.
        case ollama
        case anthropic
        case openAI

        public var identity: AssistantProviderIdentity {
            switch self {
                case .ollama:
                    AssistantProviderIdentity(
                        id: "ollama",
                        name: "Ollama",
                        summary: "A model running on this Mac. Free and private, but needs a download."
                    )
                case .anthropic:
                    AssistantProviderIdentity(
                        id: "anthropic",
                        name: "Claude API",
                        summary: "Claude with your own API key. Charged per request."
                    )
                case .openAI:
                    AssistantProviderIdentity(
                        id: "openai",
                        name: "OpenAI API",
                        summary: "OpenAI with your own API key. Charged per request."
                    )
            }
        }

        /// Whether this service can be sent images depends on the model for Ollama, so the capability
        /// is asked for with a model in hand.
        public func capabilities(model: String) -> AssistantCapabilities {
            switch self {
                case .ollama:
                    let vision = Self.isVisionModel(model)
                    return AssistantCapabilities(
                        acceptsImages: vision,
                        imageLimit: vision
                            ? nil
                            : "The model \(model.isEmpty ? "you picked" : model) cannot see images. Pull a vision "
                                + "model such as llama3.2-vision or qwen2.5vl, or use codex.",
                        imageEdge: 1024,
                        enforcesSchema: true,
                        needsAPIKey: false,
                        usesNetwork: false
                    )
                case .anthropic:
                    return AssistantCapabilities(
                        acceptsImages: true,
                        imageEdge: 1568,
                        enforcesSchema: true,
                        needsAPIKey: true,
                        usesNetwork: true
                    )
                case .openAI:
                    return AssistantCapabilities(
                        acceptsImages: true,
                        imageEdge: 1536,
                        enforcesSchema: true,
                        needsAPIKey: true,
                        usesNetwork: true
                    )
            }
        }

        /// Which local models can see. Ollama has no way to ask, so this goes by name, and anything
        /// unrecognized is treated as text only rather than being sent an image it will ignore.
        static func isVisionModel(_ model: String) -> Bool {
            let name = model.lowercased()
            let markers = ["vision", "llava", "vl", "moondream", "bakllava", "minicpm-v", "gemma3"]
            return markers.contains { name.contains($0) }
        }

        public var defaultEndpoint: URL {
            switch self {
                case .ollama: URL(string: "http://127.0.0.1:11434/api/chat")!
                case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
                case .openAI: URL(string: "https://api.openai.com/v1/responses")!
            }
        }

        /// What the model field starts as. Nothing is guessed for the hosted services: naming a
        /// version here would go stale, and the setup panel asks instead.
        public var suggestedModels: [String] {
            switch self {
                case .ollama: ["llama3.2-vision", "qwen2.5vl", "llama3.2"]
                case .anthropic: ["claude-sonnet-5", "claude-opus-5"]
                case .openAI: []
            }
        }
    }

    public let service: Service
    public let model: String
    public let endpoint: URL
    private let key: AssistantSecret
    private let transport: any AssistantTransport

    public init(
        service: Service,
        model: String,
        key: AssistantSecret = AssistantSecret(""),
        endpoint: URL? = nil,
        transport: any AssistantTransport = AssistantURLSessionTransport()
    ) {
        self.service = service
        self.model = model
        self.key = key
        self.endpoint = endpoint ?? service.defaultEndpoint
        self.transport = transport
    }

    public var identity: AssistantProviderIdentity { service.identity }
    public var capabilities: AssistantCapabilities { service.capabilities(model: model) }

    // MARK: - Running

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !capabilities.needsAPIKey || !key.isEmpty else {
                        throw AssistantProviderError.notAuthorized(provider: identity.name, detail: nil)
                    }
                    let urlRequest = try Self.urlRequest(
                        service: service,
                        endpoint: endpoint,
                        model: model,
                        key: key,
                        request: request
                    )

                    var status = 200
                    var failureBody = ""
                    var reader = AssistantLineReader()

                    for try await event in transport.send(urlRequest) {
                        try Task.checkCancellation()
                        switch event {
                            case .response(let code, let headers):
                                status = code
                                if code != 200 {
                                    // A failure body is short and is not an answer, so it is collected
                                    // whole and turned into one sentence at the end.
                                    continue
                                }
                                _ = headers
                            case .body(let data):
                                guard status == 200 else {
                                    failureBody += String(decoding: data, as: UTF8.self)
                                    continue
                                }
                                for line in reader.lines(from: data) {
                                    if let text = try Self.delta(in: line, service: service) {
                                        continuation.yield(.text(text))
                                    }
                                }
                        }
                    }
                    if status == 200 {
                        for line in reader.flush() {
                            if let text = try Self.delta(in: line, service: service) {
                                continuation.yield(.text(text))
                            }
                        }
                        continuation.finish()
                    } else {
                        throw Self.failure(service: service, status: status, body: failureBody)
                    }
                } catch let error as AssistantProviderError {
                    continuation.finish(throwing: Self.adjusted(error, service: service))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Ollama not running is the failure a person is most likely to hit, and "nothing answered at
    /// 127.0.0.1" is not a useful thing to read, so it is turned into the instruction that fixes it.
    static func adjusted(_ error: AssistantProviderError, service: Service) -> AssistantProviderError {
        guard service == .ollama, case .transport = error else { return error }
        return .serviceUnavailable(provider: "Ollama", hint: "Start it with ollama serve, then try again.")
    }

    // MARK: - Building the request

    static func urlRequest(
        service: Service,
        endpoint: URL,
        model: String,
        key: AssistantSecret,
        request: AssistantRequest
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch service {
            case .ollama:
                break
            case .anthropic:
                urlRequest.setValue(key.reveal(), forHTTPHeaderField: "x-api-key")
                urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            case .openAI:
                urlRequest.setValue("Bearer \(key.reveal())", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = body(service: service, model: model, request: request).data
        return urlRequest
    }

    /// The JSON body for one service.
    static func body(service: Service, model: String, request: AssistantRequest) -> AssistantJSON {
        switch service {
            case .ollama:
                var messages: [AssistantJSON] = [
                    .object([
                        ("role", .string("system")),
                        ("content", .string(request.systemPrompt)),
                    ])
                ]
                messages += request.turns.map { turn in
                    var members: [(String, AssistantJSON)] = [
                        ("role", .string(turn.role == .person ? "user" : "assistant")),
                        ("content", .string(turn.text)),
                    ]
                    if request.sendsImages, !turn.attachments.isEmpty {
                        members.append(
                            ("images", .array(turn.attachments.map { .string($0.jpeg.base64EncodedString()) }))
                        )
                    }
                    return .object(members)
                }
                return .object([
                    ("model", .string(model)),
                    ("stream", .bool(true)),
                    // Ollama takes the schema itself, which is what keeps a small local model from
                    // wandering off into prose.
                    ("format", embeddable(request.schema)),
                    ("messages", .array(messages)),
                ])

            case .anthropic:
                let messages = request.turns.map { turn -> AssistantJSON in
                    var content: [AssistantJSON] = []
                    if request.sendsImages {
                        // Images first: the text refers to them, so they read better before it.
                        content += turn.attachments.map { attachment in
                            .object([
                                ("type", .string("image")),
                                (
                                    "source",
                                    .object([
                                        ("type", .string("base64")),
                                        ("media_type", .string("image/jpeg")),
                                        ("data", .string(attachment.jpeg.base64EncodedString())),
                                    ])
                                ),
                            ])
                        }
                    }
                    content.append(.object([("type", .string("text")), ("text", .string(turn.text))]))
                    return .object([
                        ("role", .string(turn.role == .person ? "user" : "assistant")),
                        ("content", .array(content)),
                    ])
                }
                return .object([
                    ("model", .string(model)),
                    ("max_tokens", .number(4096)),
                    ("stream", .bool(true)),
                    ("system", .string(request.systemPrompt)),
                    ("messages", .array(messages)),
                    // Anthropic has no JSON mode, so the shape is enforced by making the answer a
                    // call to a tool whose arguments are the schema.
                    (
                        "tools",
                        .array([
                            .object([
                                ("name", .string(toolName)),
                                (
                                    "description",
                                    .string(
                                        "Propose the settings that give the person what they asked "
                                            + "for."
                                    )
                                ),
                                ("input_schema", embeddable(request.schema)),
                            ])
                        ])
                    ),
                    ("tool_choice", .object([("type", .string("tool")), ("name", .string(toolName))])),
                ])

            case .openAI:
                let input = request.turns.map { turn -> AssistantJSON in
                    var content: [AssistantJSON] = []
                    if request.sendsImages {
                        content += turn.attachments.map { attachment in
                            .object([
                                ("type", .string("input_image")),
                                (
                                    "image_url",
                                    .string("data:image/jpeg;base64,\(attachment.jpeg.base64EncodedString())")
                                ),
                            ])
                        }
                    }
                    let isPerson = turn.role == .person
                    content.append(
                        .object([
                            ("type", .string(isPerson ? "input_text" : "output_text")),
                            ("text", .string(turn.text)),
                        ])
                    )
                    return .object([
                        ("role", .string(isPerson ? "user" : "assistant")),
                        ("content", .array(content)),
                    ])
                }
                return .object([
                    ("model", .string(model)),
                    ("stream", .bool(true)),
                    ("instructions", .string(request.systemPrompt)),
                    ("input", .array(input)),
                    (
                        "text",
                        .object([
                            (
                                "format",
                                .object([
                                    ("type", .string("json_schema")),
                                    ("name", .string(toolName)),
                                    // Not strict: strict mode requires every property to be required,
                                    // and the whole point of a patch is that everything is optional.
                                    ("strict", .bool(false)),
                                    ("schema", embeddable(request.schema)),
                                ])
                            )
                        ])
                    ),
                ])
        }
    }

    static let toolName = "propose_playground_settings"

    /// The schema without the two keys that belong to a standalone document. Embedded inside a
    /// request body, `$schema` and `title` are noise at best and rejected at worst.
    static func embeddable(_ schema: AssistantJSON) -> AssistantJSON {
        guard case .object(let members) = schema else { return schema }
        return .object(members.filter { $0.name != "$schema" && $0.name != "title" })
    }

    // MARK: - Reading the answer

    /// The next piece of the answer in one streamed line, or `nil` for a line that carries none.
    ///
    /// Each service buries the text somewhere different, and every one of them also sends bookkeeping
    /// events. Anything unrecognized is ignored rather than guessed at, so a new event type in a
    /// service's stream cannot corrupt an answer.
    static func delta(in line: String, service: Service) throws -> String? {
        switch service {
            case .ollama:
                // Newline-delimited JSON rather than server-sent events.
                guard let json = AssistantJSON(parsing: line.trimmingCharacters(in: .whitespaces)) else {
                    return nil
                }
                if let error = json["error"]?.stringValue {
                    throw AssistantProviderError.badResponse(detail: error)
                }
                return json["message"]?["content"]?.stringValue

            case .anthropic:
                guard let payload = AssistantLineReader.serverSentPayload(of: line),
                    let json = AssistantJSON(parsing: payload)
                else {
                    return nil
                }
                if json["type"]?.stringValue == "error" {
                    throw AssistantProviderError.badResponse(
                        detail: json["error"]?["message"]?.stringValue ?? "the service reported an error"
                    )
                }
                guard json["type"]?.stringValue == "content_block_delta", let delta = json["delta"] else {
                    return nil
                }
                // The answer arrives as the tool's arguments, in pieces of raw JSON text. A model that
                // answers in plain text instead still streams, and the parser sorts it out later.
                return delta["partial_json"]?.stringValue ?? delta["text"]?.stringValue

            case .openAI:
                guard let payload = AssistantLineReader.serverSentPayload(of: line),
                    let json = AssistantJSON(parsing: payload)
                else {
                    return nil
                }
                let type = json["type"]?.stringValue ?? ""
                if type == "error" || type == "response.failed" {
                    let message =
                        json["error"]?["message"]?.stringValue
                        ?? json["response"]?["error"]?["message"]?.stringValue
                    throw AssistantProviderError.badResponse(detail: message ?? "the service reported an error")
                }
                guard type == "response.output_text.delta" else { return nil }
                return json["delta"]?.stringValue
        }
    }

    /// What an HTTP status means, in the words the composer shows.
    static func failure(service: Service, status: Int, body: String) -> AssistantProviderError {
        let detail = message(in: body)
        switch status {
            case 401, 403:
                return .notAuthorized(provider: service.identity.name, detail: detail)
            case 404 where service == .ollama:
                return .serviceUnavailable(
                    provider: "Ollama",
                    hint: detail.isEmpty
                        ? "Pull the model first with ollama pull." : "Pull the model first: \(detail)"
                )
            case 429:
                return .rateLimited(provider: service.identity.name, retryAfter: nil)
            default:
                return .badResponse(
                    detail: detail.isEmpty ? "the service answered with status \(status)" : detail
                )
        }
    }

    /// The human-readable complaint inside a failure body, wherever the service put it.
    static func message(in body: String) -> String {
        guard let json = AssistantJSON(parsing: body.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return json["error"]?["message"]?.stringValue
            ?? json["error"]?.stringValue
            ?? json["message"]?.stringValue
            ?? ""
    }
}
