// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Every way of asking, in the order the setup panel offers them.
///
/// The order is the point. What someone already has comes first, then the way that needs nothing at
/// all, then a local model, and only then the two that charge per request. Customizing an open source
/// app should not start with a billing page, so nothing in the default path does.
public enum AssistantProviderOption: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The `codex` command, using its own sign-in.
    case codexCLI
    /// The `claude` command, using its own sign-in.
    case claudeCLI
    /// Copy the prompt, paste the reply. Needs nothing installed and sends nothing.
    case clipboard
    /// A model running on this Mac.
    case ollama
    case anthropic
    case openAI

    public var id: String { rawValue }

    public var identity: AssistantProviderIdentity {
        switch self {
            case .codexCLI: AssistantCLIProvider.Tool.codex.identity
            case .claudeCLI: AssistantCLIProvider.Tool.claude.identity
            case .clipboard: AssistantClipboardExchange.identity
            case .ollama: AssistantHTTPProvider.Service.ollama.identity
            case .anthropic: AssistantHTTPProvider.Service.anthropic.identity
            case .openAI: AssistantHTTPProvider.Service.openAI.identity
        }
    }

    /// What this option can do with the given model. Ollama's answer depends on the model, so every
    /// option is asked the same way.
    public func capabilities(model: String) -> AssistantCapabilities {
        switch self {
            case .codexCLI: AssistantCLIProvider.Tool.codex.capabilities
            case .claudeCLI: AssistantCLIProvider.Tool.claude.capabilities
            case .clipboard: AssistantClipboardExchange.capabilities
            case .ollama: AssistantHTTPProvider.Service.ollama.capabilities(model: model)
            case .anthropic: AssistantHTTPProvider.Service.anthropic.capabilities(model: model)
            case .openAI: AssistantHTTPProvider.Service.openAI.capabilities(model: model)
        }
    }

    /// The command this option needs installed, when it needs one.
    public var command: String? {
        switch self {
            case .codexCLI: AssistantCLIProvider.Tool.codex.command
            case .claudeCLI: AssistantCLIProvider.Tool.claude.command
            case .clipboard, .ollama, .anthropic, .openAI: nil
        }
    }

    /// Whether the person carries the message themselves, which changes Send into Copy Prompt.
    public var isManual: Bool { self == .clipboard }

    public var model: String {
        switch self {
            case .codexCLI: AssistantCLIProvider.Tool.codex.defaultModel
            case .claudeCLI: AssistantCLIProvider.Tool.claude.defaultModel
            case .clipboard: ""
            case .ollama: AssistantHTTPProvider.Service.ollama.suggestedModels.first ?? ""
            case .anthropic: AssistantHTTPProvider.Service.anthropic.suggestedModels.first ?? ""
            case .openAI: ""
        }
    }

    /// Models worth offering as a starting point. Empty where naming one here would only go stale,
    /// which is why the setup panel always has a field for typing any id the provider accepts.
    public var suggestedModels: [String] {
        switch self {
            case .codexCLI, .clipboard: []
            case .claudeCLI: ["sonnet", "opus"]
            case .ollama: AssistantHTTPProvider.Service.ollama.suggestedModels
            case .anthropic: AssistantHTTPProvider.Service.anthropic.suggestedModels
            case .openAI: AssistantHTTPProvider.Service.openAI.suggestedModels
        }
    }

    /// Whether a model has to be named before this option can be used. Both command line tools pick
    /// their own by default, and the clipboard has no model of its own at all.
    public var requiresModel: Bool {
        switch self {
            case .codexCLI, .claudeCLI, .clipboard: false
            case .ollama, .anthropic, .openAI: true
        }
    }

    /// Whether this option has a model of its own to name. The clipboard has none: the model is
    /// whoever the person pastes into.
    public var hasModel: Bool { self != .clipboard }

    /// Whether an empty model is a real choice (the tool's own default) rather than an unfinished
    /// setup.
    public var allowsEmptyModel: Bool { !requiresModel }

    public var needsAPIKey: Bool {
        switch self {
            case .anthropic, .openAI: true
            case .codexCLI, .claudeCLI, .clipboard, .ollama: false
        }
    }

    /// Where this option sits in the setup list. What someone already has is offered first.
    public var section: Section {
        switch self {
            case .codexCLI, .claudeCLI, .clipboard, .ollama: .alreadyYours
            case .anthropic, .openAI: .billed
        }
    }

    public enum Section: String, CaseIterable, Sendable {
        case alreadyYours
        case billed

        public var title: String {
            switch self {
                case .alreadyYours: "Already yours"
                case .billed: "Charged per request"
            }
        }
    }

    public static func options(in section: Section) -> [AssistantProviderOption] {
        allCases.filter { $0.section == section }
    }

    /// The name on the chip and in the menu. Title case, not the command, so the control reads like
    /// a product and not like a shell prompt.
    public var displayTitle: String {
        switch self {
            case .codexCLI: "Codex"
            case .claudeCLI: "Claude"
            case .clipboard: "Clipboard"
            case .ollama: "Ollama"
            case .anthropic: "Claude API"
            case .openAI: "OpenAI"
        }
    }

    /// A model id as people say it: "Sonnet", not "claude-sonnet-5". Unknown ids are left alone.
    public func friendlyName(for model: String) -> String {
        switch model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "sonnet", "claude-sonnet-5": "Sonnet"
            case "opus", "claude-opus-5": "Opus"
            case "llama3.2-vision": "Llama 3.2 Vision"
            case "llama3.2": "Llama 3.2"
            case "qwen2.5vl": "Qwen 2.5 VL"
            default: model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// One line on what using this costs, so the list does not hide the billed paths among the free
    /// ones.
    public var usage: String {
        switch self {
            case .codexCLI:
                "Uses the codex command you are already signed in to. No key, no extra cost."
            case .claudeCLI:
                "Uses the claude command you are already signed in to. No key, no extra cost."
            case .clipboard:
                "You copy the prompt and paste a reply. This app sends nothing."
            case .ollama:
                "A model on this Mac. Free, and it never goes to the network."
            case .anthropic:
                "Your Anthropic API key. Charged per request."
            case .openAI:
                "Your OpenAI API key. Charged per request."
        }
    }

    /// The model field's prompt, which says what to type rather than guessing a version.
    public var modelPrompt: String {
        switch self {
            case .codexCLI: "Model id"
            case .claudeCLI: "sonnet, opus, or a model id"
            case .clipboard: ""
            case .ollama: "A model you have pulled"
            case .anthropic: "The exact model id"
            case .openAI: "The exact model id"
        }
    }
}

/// Which way of asking is in use, and with what model. Stored in the playground's own defaults.
///
/// A key is never part of this. Keys live in the Keychain, and this is written to `UserDefaults`,
/// where it can be read by anything that can read the plist and would end up in a copied preferences
/// file or a screenshot of one.
public struct AssistantConfiguration: Codable, Equatable, Sendable {
    public var option: AssistantProviderOption
    public var model: String
    /// The last model named for each option, so switching tools does not lose a careful choice.
    public var rememberedModels: [String: String]

    public init(
        option: AssistantProviderOption,
        model: String? = nil,
        rememberedModels: [String: String] = [:]
    ) {
        self.option = option
        let resolved = model ?? option.model
        self.model = resolved
        var remembered = rememberedModels
        remembered[option.rawValue] = resolved
        self.rememberedModels = remembered
    }

    /// Switches tools and restores the last model named for that tool, or its default.
    public mutating func select(_ option: AssistantProviderOption) {
        self.option = option
        model = rememberedModels[option.rawValue] ?? option.model
    }

    /// Pins the next request to `model`. Whitespace is trimmed so a pasted id with a newline does
    /// not become a different name.
    public mutating func setModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmed
        rememberedModels[option.rawValue] = trimmed
    }

    /// What the chip shows, the way Claude writes "Opus 5": a spoken name, never a slug and never
    /// the word "default".
    public var usageLabel: String {
        guard option.hasModel else { return option.displayTitle }
        let named = model.trimmingCharacters(in: .whitespaces)
        if named.isEmpty { return option.displayTitle }
        return option.friendlyName(for: named)
    }

    /// One sentence for the setup panel, so someone particular about usage can see what will be
    /// asked before they send.
    public var nextRequestSummary: String {
        let name = option.displayTitle
        let named = model.trimmingCharacters(in: .whitespaces)
        switch option {
            case .clipboard:
                return "The next request is a prompt you copy. This app sends nothing."
            case .codexCLI, .claudeCLI:
                if named.isEmpty {
                    return "The next request uses \(name)'s default model."
                }
                return "The next request uses \(name), \(named)."
            case .ollama:
                if named.isEmpty {
                    return "Name a model you have pulled. It stays on this Mac."
                }
                return "The next request uses \(named) on this Mac. Nothing is sent to a network."
            case .anthropic, .openAI:
                if named.isEmpty {
                    return "Name the exact model id. \(name) charges per request."
                }
                return "The next request uses \(named) through \(name). Charged per request."
        }
    }

    /// What the assistant starts as before anything is chosen: whatever is already on the machine,
    /// and the clipboard when nothing is.
    ///
    /// This is why the assistant is never a dead end. Someone who has never heard of an API key opens
    /// the composer and it either found their tools or falls back to a path that always works.
    public static func detected(
        locate: (String) -> String? = { AssistantToolLocator.locate($0) }
    ) -> AssistantConfiguration {
        for option in AssistantProviderOption.allCases {
            guard let command = option.command else { continue }
            if locate(command) != nil {
                return AssistantConfiguration(option: option)
            }
        }
        return AssistantConfiguration(option: .clipboard)
    }

    /// Whether this configuration can be used as it stands, or still needs something.
    public func readiness(hasKey: Bool) -> Readiness {
        let capabilities = option.capabilities(model: model)
        if option.requiresModel, model.trimmingCharacters(in: .whitespaces).isEmpty {
            return .needsModel
        }
        if capabilities.needsAPIKey, !hasKey {
            return .needsKey
        }
        return .ready
    }

    public enum Readiness: Equatable, Sendable {
        case ready
        case needsKey
        case needsModel
    }

    private enum CodingKeys: String, CodingKey {
        case option
        case model
        case rememberedModels
    }

    /// Decoding tolerates an option this version does not have, which keeps a preferences file written
    /// by a newer playground from disabling the assistant entirely. An older file with no remembered
    /// models still loads: the current model becomes the one remembered for the current option.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .option) ?? ""
        let option = AssistantProviderOption(rawValue: name) ?? .clipboard
        self.init(
            option: option,
            model: try container.decodeIfPresent(String.self, forKey: .model),
            rememberedModels: try container.decodeIfPresent([String: String].self, forKey: .rememberedModels)
                ?? [:]
        )
    }
}
