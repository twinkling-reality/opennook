// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The stored choice of tool and model. The header chip and the setup list are a function of this,
/// so a forgotten model or a silent default would show up here before it showed up in the window.
final class AssistantConfigurationTests: XCTestCase {
    func testDetectionPicksAnInstalledCommandBeforeTheClipboard() {
        let configuration = AssistantConfiguration.detected { command in
            command == "claude" ? "/usr/local/bin/claude" : nil
        }
        XCTAssertEqual(configuration.option, .claudeCLI)
        XCTAssertEqual(configuration.model, "sonnet")
    }

    func testDetectionFallsBackToTheClipboardWhenNothingIsInstalled() {
        let configuration = AssistantConfiguration.detected { _ in nil }
        XCTAssertEqual(configuration.option, .clipboard)
        XCTAssertEqual(configuration.model, "")
    }

    func testSwitchingToolsRestoresTheLastModelNamedForEachOne() {
        var configuration = AssistantConfiguration(option: .codexCLI)
        configuration.setModel("gpt-5.2-codex")
        configuration.select(.ollama)
        XCTAssertEqual(configuration.model, "llama3.2-vision")
        configuration.setModel("qwen2.5vl")
        configuration.select(.codexCLI)
        XCTAssertEqual(configuration.option, .codexCLI)
        XCTAssertEqual(configuration.model, "gpt-5.2-codex")
        configuration.select(.ollama)
        XCTAssertEqual(configuration.model, "qwen2.5vl")
    }

    func testTheHeaderNamesTheExactModelTheNextRequestWillUse() {
        XCTAssertEqual(AssistantConfiguration(option: .clipboard).usageLabel, "Clipboard")
        XCTAssertEqual(AssistantConfiguration(option: .codexCLI).usageLabel, "Codex")
        XCTAssertEqual(
            AssistantConfiguration(option: .codexCLI, model: "gpt-5.2-codex").usageLabel,
            "gpt-5.2-codex"
        )
        XCTAssertEqual(AssistantConfiguration(option: .claudeCLI).usageLabel, "Sonnet")
        XCTAssertEqual(
            AssistantConfiguration(option: .ollama, model: "qwen2.5vl").usageLabel,
            "Qwen 2.5 VL"
        )
    }

    func testAHostedOptionIsNotReadyUntilBothTheModelAndTheKeyAreThere() {
        let openAI = AssistantConfiguration(option: .openAI)
        XCTAssertEqual(openAI.readiness(hasKey: false), .needsModel)
        var named = openAI
        named.setModel("gpt-5")
        XCTAssertEqual(named.readiness(hasKey: false), .needsKey)
        XCTAssertEqual(named.readiness(hasKey: true), .ready)
        XCTAssertEqual(named.nextRequestSummary, "The next request uses gpt-5 through OpenAI. Charged per request.")
    }

    func testAnOlderPreferencesFileWithoutRememberedModelsStillLoads() throws {
        let data = Data(#"{"option":"claudeCLI","model":"opus"}"#.utf8)
        let configuration = try JSONDecoder().decode(AssistantConfiguration.self, from: data)
        XCTAssertEqual(configuration.option, .claudeCLI)
        XCTAssertEqual(configuration.model, "opus")
        XCTAssertEqual(configuration.rememberedModels["claudeCLI"], "opus")
    }

    func testAnUnknownOptionDecodesAsTheClipboard() throws {
        let data = Data(#"{"option":"future-tool","model":"x"}"#.utf8)
        let configuration = try JSONDecoder().decode(AssistantConfiguration.self, from: data)
        XCTAssertEqual(configuration.option, .clipboard)
    }
}
