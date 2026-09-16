// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The HTTP providers, against a fake transport. No request leaves the machine and no key is real:
/// what is checked is the body each service is sent, where each one hides the answer in its stream,
/// and what its failures mean.
final class AssistantHTTPProviderTests: XCTestCase {
    // MARK: - Doubles

    /// A transport that replays a scripted response and remembers the request.
    private struct FakeTransport: AssistantTransport {
        var status = 200
        var lines: [String] = []
        let log = Log()

        func send(_ request: URLRequest) -> AsyncThrowingStream<AssistantHTTPEvent, any Error> {
            AsyncThrowingStream { continuation in
                Task {
                    await log.record(request)
                    continuation.yield(.response(status: status, headers: [:]))
                    for line in lines {
                        continuation.yield(.body(Data((line + "\n").utf8)))
                    }
                    continuation.finish()
                }
            }
        }

        actor Log {
            private(set) var requests: [URLRequest] = []

            func record(_ request: URLRequest) {
                requests.append(request)
            }
        }
    }

    private struct FailingTransport: AssistantTransport {
        let error: any Error

        func send(_ request: URLRequest) -> AsyncThrowingStream<AssistantHTTPEvent, any Error> {
            AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private func request(
        service: AssistantHTTPProvider.Service,
        model: String,
        attachments: [AssistantAttachment] = []
    ) throws -> AssistantRequest {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it dark", attachments: attachments))
        return try conversation.request(
            preset: PlaygroundPreset(),
            model: model,
            capabilities: service.capabilities(model: model)
        )
    }

    private func body(
        service: AssistantHTTPProvider.Service,
        model: String = "a-model",
        attachments: [AssistantAttachment] = []
    ) throws -> AssistantJSON {
        AssistantHTTPProvider.body(
            service: service,
            model: model,
            request: try request(service: service, model: model, attachments: attachments)
        )
    }

    private func attachment() -> AssistantAttachment {
        AssistantAttachment(jpeg: Data([0xFF, 0xD8, 0xEE]), pixelWidth: 400, pixelHeight: 300)
    }

    private func collect(_ provider: AssistantHTTPProvider, _ request: AssistantRequest) async throws -> String {
        var answer = ""
        for try await event in provider.stream(request) {
            if case .text(let text) = event {
                answer += text
            }
        }
        return answer
    }

    // MARK: - Keys

    /// A key must not be printable, because the easiest way to leak one is to interpolate it into a
    /// log line by accident.
    func testASecretDoesNotPrintItself() {
        let secret = AssistantSecret("sk-ant-not-a-real-key-9932")
        XCTAssertEqual("\(secret)", "(hidden)")
        XCTAssertEqual(String(describing: secret), "(hidden)")
        XCTAssertEqual(String(reflecting: secret), "(hidden)")
        XCTAssertFalse("\(secret)".contains("9932"))
        // And it is still there when it is actually needed.
        XCTAssertEqual(secret.reveal(), "sk-ant-not-a-real-key-9932")
    }

    func testASecretShowsOnlyAHintOfItself() {
        XCTAssertEqual(AssistantSecret("sk-ant-abcd1234").hint, "...1234")
        XCTAssertEqual(AssistantSecret("abc").hint, "(stored)")
    }

    func testASecretIgnoresWhitespaceAroundAPastedKey() {
        XCTAssertEqual(AssistantSecret("  sk-key-1234\n").reveal(), "sk-key-1234")
        XCTAssertTrue(AssistantSecret("   ").isEmpty)
    }

    func testAServiceThatNeedsAKeyRefusesWithoutOne() async throws {
        let provider = AssistantHTTPProvider(
            service: .anthropic,
            model: "claude-sonnet-5",
            transport: FakeTransport()
        )
        do {
            _ = try await collect(provider, try request(service: .anthropic, model: "claude-sonnet-5"))
            XCTFail("expected a missing key to be refused")
        } catch {
            XCTAssertEqual(error as? AssistantProviderError, .notAuthorized(provider: "Claude API", detail: nil))
        }
    }

    func testOllamaNeedsNoKeyAndNoNetwork() {
        let capabilities = AssistantHTTPProvider.Service.ollama.capabilities(model: "llama3.2")
        XCTAssertFalse(capabilities.needsAPIKey)
        XCTAssertFalse(capabilities.usesNetwork, "a model on this Mac is not a network request")
    }

    // MARK: - Ollama

    func testOllamaIsSentTheSchemaAndTheSystemPromptAsAMessage() throws {
        let body = try body(service: .ollama, model: "llama3.2")

        XCTAssertEqual(body["model"], .string("llama3.2"))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertNotNil(body["format"]?["properties"]?["patch"], "the schema was not sent")
        let messages = try XCTUnwrap(body["messages"]?.arrayValue)
        XCTAssertEqual(messages.first?["role"], .string("system"))
        XCTAssertEqual(messages.last?["role"], .string("user"))
    }

    /// The schema is a whole document on disk and a fragment in a request body; the two keys that only
    /// make sense standalone are dropped.
    func testTheEmbeddedSchemaDropsTheDocumentKeys() throws {
        let format = try XCTUnwrap(try body(service: .ollama)["format"])
        XCTAssertNil(format["$schema"])
        XCTAssertNil(format["title"])
        XCTAssertEqual(format["type"], .string("object"))
    }

    /// Ollama has no way to ask what a model can do, so it goes by name, and anything unrecognized is
    /// treated as text only rather than being sent an image it will ignore.
    func testOnlyAVisionModelIsOfferedTheImageControl() {
        for model in ["llama3.2-vision", "llava:13b", "qwen2.5vl", "moondream", "gemma3:4b"] {
            XCTAssertTrue(
                AssistantHTTPProvider.Service.ollama.capabilities(model: model).acceptsImages,
                "\(model) should be able to see images"
            )
        }
        for model in ["llama3.2", "mistral", "deepseek-r1", ""] {
            let capabilities = AssistantHTTPProvider.Service.ollama.capabilities(model: model)
            XCTAssertFalse(capabilities.acceptsImages, "\(model) should not be offered images")
            XCTAssertNotNil(capabilities.imageLimit, "\(model) should say why not")
        }
    }

    func testTheOllamaImageLimitNamesTheModelAndSuggestsOne() {
        let limit = AssistantHTTPProvider.Service.ollama.capabilities(model: "mistral").imageLimit ?? ""
        XCTAssertTrue(limit.contains("mistral"), limit)
        XCTAssertTrue(limit.contains("llama3.2-vision"), limit)
    }

    func testAVisionModelIsSentTheImageAsBase64() throws {
        let body = try body(service: .ollama, model: "llama3.2-vision", attachments: [attachment()])
        let images = try XCTUnwrap(body["messages"]?.arrayValue?.last?["images"]?.arrayValue)
        XCTAssertEqual(images.first?.stringValue, Data([0xFF, 0xD8, 0xEE]).base64EncodedString())
    }

    func testATextOnlyLocalModelIsSentNoImages() throws {
        let body = try body(service: .ollama, model: "llama3.2", attachments: [attachment()])
        XCTAssertNil(body["messages"]?.arrayValue?.last?["images"])
    }

    func testOllamaAnswersAreReadFromItsLines() throws {
        let lines = [
            #"{"message":{"role":"assistant","content":"{\"explanation\":"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"\"Dark.\",\"patch\":{}}"},"done":false}"#,
            #"{"done":true,"total_duration":1234}"#,
        ]
        var answer = ""
        for line in lines {
            if let delta = try AssistantHTTPProvider.delta(in: line, service: .ollama) {
                answer += delta
            }
        }
        XCTAssertEqual(answer, #"{"explanation":"Dark.","patch":{}}"#)
    }

    func testAnOllamaErrorLineIsReported() {
        XCTAssertThrowsError(
            try AssistantHTTPProvider.delta(in: #"{"error":"model not found"}"#, service: .ollama)
        ) { error in
            XCTAssertEqual(error as? AssistantProviderError, .badResponse(detail: "model not found"))
        }
    }

    /// The most likely failure by far: Ollama installed but not running. "Nothing answered at
    /// 127.0.0.1" is not useful, so it becomes the instruction that fixes it.
    func testOllamaNotRunningSaysHowToStartIt() async throws {
        let provider = AssistantHTTPProvider(
            service: .ollama,
            model: "llama3.2",
            transport: FailingTransport(
                error: AssistantProviderError.transport(detail: "nothing answered at 127.0.0.1")
            )
        )
        do {
            _ = try await collect(provider, try request(service: .ollama, model: "llama3.2"))
            XCTFail("expected a failure")
        } catch {
            guard case .serviceUnavailable(let name, let hint) = error as? AssistantProviderError else {
                return XCTFail("expected serviceUnavailable, got \(error)")
            }
            XCTAssertEqual(name, "Ollama")
            XCTAssertTrue(hint.contains("ollama serve"), hint)
        }
    }

    func testAMissingLocalModelSaysToPullIt() {
        let error = AssistantHTTPProvider.failure(
            service: .ollama,
            status: 404,
            body: #"{"error":"model \"llama3.2-vision\" not found"}"#
        )
        guard case .serviceUnavailable(_, let hint) = error else {
            return XCTFail("expected serviceUnavailable, got \(error)")
        }
        XCTAssertTrue(hint.contains("Pull the model"), hint)
    }

    // MARK: - Anthropic

    /// Anthropic has no JSON mode, so the answer is forced by making it a call to a tool whose
    /// arguments are the schema.
    func testAnthropicIsMadeToAnswerThroughATool() throws {
        let body = try body(service: .anthropic, model: "claude-sonnet-5")

        let tools = try XCTUnwrap(body["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["name"], .string(AssistantHTTPProvider.toolName))
        XCTAssertNotNil(tools[0]["input_schema"]?["properties"]?["explanation"])
        XCTAssertEqual(body["tool_choice"]?["type"], .string("tool"))
        XCTAssertEqual(body["tool_choice"]?["name"], .string(AssistantHTTPProvider.toolName))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertEqual(body["system"]?.stringValue?.isEmpty, false)
    }

    func testAnthropicIsSentTheKeyInItsOwnHeader() throws {
        let urlRequest = try AssistantHTTPProvider.urlRequest(
            service: .anthropic,
            endpoint: AssistantHTTPProvider.Service.anthropic.defaultEndpoint,
            model: "claude-sonnet-5",
            key: AssistantSecret("sk-ant-test"),
            request: try request(service: .anthropic, model: "claude-sonnet-5")
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(urlRequest.httpMethod, "POST")
    }

    func testAnthropicIsSentImagesBeforeTheTextThatRefersToThem() throws {
        let body = try body(service: .anthropic, model: "claude-sonnet-5", attachments: [attachment()])
        let content = try XCTUnwrap(body["messages"]?.arrayValue?.last?["content"]?.arrayValue)

        XCTAssertEqual(content.first?["type"], .string("image"))
        XCTAssertEqual(content.first?["source"]?["media_type"], .string("image/jpeg"))
        XCTAssertEqual(
            content.first?["source"]?["data"]?.stringValue,
            Data([0xFF, 0xD8, 0xEE]).base64EncodedString()
        )
        XCTAssertEqual(content.last?["type"], .string("text"))
    }

    /// The answer arrives as pieces of the tool's arguments, which are the JSON object itself.
    func testAnthropicAnswersAreReadFromItsToolArguments() throws {
        let lines = [
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":0}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"explanation\": \"Going"#
                + #" dark.\""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":", \"patch\": {}}"}}"#,
            #"data: {"type":"message_stop"}"#,
            "data: [DONE]",
        ]
        var answer = ""
        for line in lines {
            if let delta = try AssistantHTTPProvider.delta(in: line, service: .anthropic) {
                answer += delta
            }
        }
        XCTAssertEqual(answer, #"{"explanation": "Going dark.", "patch": {}}"#)
    }

    /// A model that answers in plain text rather than through the tool still streams, and the parser
    /// sorts out what it said afterwards.
    func testAnthropicPlainTextIsAlsoRead() throws {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"{\"explanation\""}}"#
        XCTAssertEqual(try AssistantHTTPProvider.delta(in: line, service: .anthropic), #"{"explanation""#)
    }

    func testAnAnthropicErrorEventIsReported() {
        let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        XCTAssertThrowsError(try AssistantHTTPProvider.delta(in: line, service: .anthropic)) { error in
            XCTAssertEqual(error as? AssistantProviderError, .badResponse(detail: "Overloaded"))
        }
    }

    // MARK: - OpenAI

    func testOpenAIIsAskedForJSONAgainstTheSchema() throws {
        let body = try body(service: .openAI, model: "a-model")
        let format = try XCTUnwrap(body["text"]?["format"])

        XCTAssertEqual(format["type"], .string("json_schema"))
        XCTAssertNotNil(format["schema"]?["properties"]?["patch"])
        // Strict mode would demand every field be required, which is the opposite of a patch.
        XCTAssertEqual(format["strict"], .bool(false))
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertEqual(body["instructions"]?.stringValue?.isEmpty, false)
    }

    func testOpenAIIsSentTheKeyAsABearerToken() throws {
        let urlRequest = try AssistantHTTPProvider.urlRequest(
            service: .openAI,
            endpoint: AssistantHTTPProvider.Service.openAI.defaultEndpoint,
            model: "a-model",
            key: AssistantSecret("sk-openai-test"),
            request: try request(service: .openAI, model: "a-model")
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai-test")
    }

    func testOpenAIIsSentImagesAsDataURLs() throws {
        let body = try body(service: .openAI, attachments: [attachment()])
        let content = try XCTUnwrap(body["input"]?.arrayValue?.last?["content"]?.arrayValue)
        let image = try XCTUnwrap(content.first)

        XCTAssertEqual(image["type"], .string("input_image"))
        XCTAssertEqual(
            image["image_url"]?.stringValue,
            "data:image/jpeg;base64,\(Data([0xFF, 0xD8, 0xEE]).base64EncodedString())"
        )
    }

    func testOpenAIAnswersAreReadFromItsTextDeltas() throws {
        let lines = [
            #"data: {"type":"response.created","response":{"id":"resp_1"}}"#,
            #"data: {"type":"response.output_text.delta","delta":"{\"explanation\":"}"#,
            #"data: {"type":"response.output_text.delta","delta":"\"Dark.\"}"}"#,
            #"data: {"type":"response.completed"}"#,
        ]
        var answer = ""
        for line in lines {
            if let delta = try AssistantHTTPProvider.delta(in: line, service: .openAI) {
                answer += delta
            }
        }
        XCTAssertEqual(answer, #"{"explanation":"Dark."}"#)
    }

    func testAnOpenAIErrorEventIsReported() {
        let line = #"data: {"type":"error","error":{"message":"model not found"}}"#
        XCTAssertThrowsError(try AssistantHTTPProvider.delta(in: line, service: .openAI)) { error in
            XCTAssertEqual(error as? AssistantProviderError, .badResponse(detail: "model not found"))
        }
    }

    // MARK: - Shared behavior

    /// A bookkeeping event or a comment is not an answer. Ignoring what is not recognized means a new
    /// event type in a service's stream cannot corrupt one.
    func testLinesThatCarryNoAnswerAreIgnored() throws {
        let noise = [
            "",
            ": keep-alive",
            "event: ping",
            "data: [DONE]",
            "data: not json at all",
            #"data: {"type":"response.in_progress"}"#,
        ]
        for service in AssistantHTTPProvider.Service.allCases {
            for line in noise {
                XCTAssertNil(
                    try AssistantHTTPProvider.delta(in: line, service: service),
                    "\(service.rawValue) read an answer out of \(line)"
                )
            }
        }
    }

    func testAWholeAnswerStreamsThroughToAProposal() async throws {
        let answer = AssistantFakeProvider.answer(
            explanation: "Going dark.",
            patch: #"{ "appearance": { "chromePalette": "dark" } }"#
        )
        // Sent the way Ollama sends it, one JSON line per piece.
        let lines = AssistantFakeProvider.pieces(of: answer, every: 20).map { piece in
            AssistantJSON.object([
                ("message", .object([("content", .string(piece))])),
                ("done", .bool(false)),
            ]).text.replacingOccurrences(of: "\n", with: "")
        }
        let provider = AssistantHTTPProvider(
            service: .ollama,
            model: "llama3.2",
            transport: FakeTransport(lines: lines)
        )

        var outcomes: [AssistantOutcome] = []
        for try await outcome in AssistantRunner(provider: provider)
            .run(try request(service: .ollama, model: "llama3.2"), base: PlaygroundPreset())
        {
            outcomes.append(outcome)
        }

        guard case .proposal(let proposal)? = outcomes.last else {
            return XCTFail("no proposal: \(outcomes)")
        }
        XCTAssertEqual(proposal.changes.map(\.summary), ["Palette Follow the system -> Dark"])
    }

    func testABadKeyIsReportedAsSomethingToFix() {
        let error = AssistantHTTPProvider.failure(
            service: .anthropic,
            status: 401,
            body: #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        )
        XCTAssertEqual(error, .notAuthorized(provider: "Claude API", detail: "invalid x-api-key"))
        XCTAssertFalse(error.isWorthRetrying)
    }

    func testRateLimitingIsReportedAsWorthRetrying() {
        let error = AssistantHTTPProvider.failure(service: .openAI, status: 429, body: "")
        XCTAssertEqual(error, .rateLimited(provider: "OpenAI API", retryAfter: nil))
        XCTAssertTrue(error.isWorthRetrying)
    }

    func testAnyOtherStatusShowsWhateverTheServiceSaid() {
        XCTAssertEqual(
            AssistantHTTPProvider.failure(
                service: .openAI,
                status: 400,
                body: #"{"error":{"message":"unsupported model"}}"#
            ),
            .badResponse(detail: "unsupported model")
        )
        XCTAssertEqual(
            AssistantHTTPProvider.failure(service: .openAI, status: 503, body: "<html>Gateway</html>"),
            .badResponse(detail: "<html>Gateway</html>")
        )
        XCTAssertEqual(
            AssistantHTTPProvider.failure(service: .openAI, status: 500, body: ""),
            .badResponse(detail: "the service answered with status 500")
        )
    }

    func testAFailureBodyIsNotMistakenForAnAnswer() async throws {
        let provider = AssistantHTTPProvider(
            service: .anthropic,
            model: "claude-sonnet-5",
            key: AssistantSecret("sk-ant-test"),
            transport: FakeTransport(
                status: 401,
                lines: [#"{"error":{"message":"invalid x-api-key"}}"#]
            )
        )
        do {
            _ = try await collect(provider, try request(service: .anthropic, model: "claude-sonnet-5"))
            XCTFail("expected the bad key to be reported")
        } catch {
            XCTAssertEqual(
                error as? AssistantProviderError,
                .notAuthorized(provider: "Claude API", detail: "invalid x-api-key")
            )
        }
    }

    func testEveryServiceHasAnEndpointAndASummary() {
        for service in AssistantHTTPProvider.Service.allCases {
            XCTAssertFalse(service.identity.summary.isEmpty)
            XCTAssertFalse(service.identity.id.isEmpty)
            XCTAssertNotNil(service.defaultEndpoint.host())
        }
        XCTAssertEqual(AssistantHTTPProvider.Service.ollama.defaultEndpoint.host(), "127.0.0.1")
    }

    /// A hosted service costs money per request, so it says so where a person chooses.
    func testTheHostedServicesSayTheyAreChargedFor() {
        for service in [AssistantHTTPProvider.Service.anthropic, .openAI] {
            XCTAssertTrue(service.identity.summary.contains("Charged"), service.identity.summary)
            XCTAssertTrue(service.capabilities(model: "any").needsAPIKey)
        }
        XCTAssertTrue(
            AssistantHTTPProvider.Service.ollama.identity.summary.contains("Free"),
            AssistantHTTPProvider.Service.ollama.identity.summary
        )
    }

    // MARK: - Reading lines

    /// A chunk off the wire can end mid-line, and a lost line is a truncated answer rather than a
    /// crash, so this is worth pinning down.
    func testALineSplitAcrossChunksIsPutBackTogether() {
        var reader = AssistantLineReader()
        XCTAssertEqual(reader.lines(from: Data("data: {\"a\":".utf8)), [])
        XCTAssertEqual(reader.lines(from: Data("1}\ndata: {\"b\":2}\n".utf8)), ["data: {\"a\":1}", "data: {\"b\":2}"])
        XCTAssertEqual(reader.flush(), [])
    }

    func testAFinalLineWithNoNewlineIsNotLost() {
        var reader = AssistantLineReader()
        XCTAssertEqual(reader.lines(from: Data("{\"done\":true}".utf8)), [])
        XCTAssertEqual(reader.flush(), ["{\"done\":true}"])
        XCTAssertEqual(reader.flush(), [])
    }

    func testServerSentPayloadsAreUnwrapped() {
        XCTAssertEqual(AssistantLineReader.serverSentPayload(of: "data: {\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(AssistantLineReader.serverSentPayload(of: "data:{\"a\":1}"), "{\"a\":1}")
        XCTAssertNil(AssistantLineReader.serverSentPayload(of: "event: ping"))
        XCTAssertNil(AssistantLineReader.serverSentPayload(of: ": comment"))
        XCTAssertNil(AssistantLineReader.serverSentPayload(of: "data: [DONE]"))
        XCTAssertNil(AssistantLineReader.serverSentPayload(of: "data:"))
        XCTAssertNil(AssistantLineReader.serverSentPayload(of: ""))
    }
}
