// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import PlaygroundNookCore
import SwiftUI

/// The composer's state, and the one place a request is started, watched, and stopped.
///
/// Everything that could be reasoned about without a window is already in `PlaygroundNookCore`. What
/// is left here is the part that is genuinely about the interface: which of the composer's states is
/// showing, what the person has typed, and making sure a request in flight never holds up the window
/// or the nook.
@MainActor
final class AssistantModel: ObservableObject {
    /// Where the composer is in one exchange. The whole interface is a function of this, so a state
    /// that is not in this list cannot be shown.
    enum Phase: Equatable {
        case empty
        /// The request has gone, nothing has come back yet.
        case sending
        /// The explanation as far as it has arrived.
        case streaming(String)
        /// The first answer could not be used and is being corrected once.
        case repairing(reason: String)
        case proposal(AssistantProposal)
        /// Stopped by the person, with whatever had arrived.
        case cancelled(partial: String)
        case failed(message: String, canRetry: Bool)

        var isBusy: Bool {
            switch self {
                case .sending, .streaming, .repairing: true
                case .empty, .proposal, .cancelled, .failed: false
            }
        }
    }

    @Published var isPresented = false
    /// The model menu on the composer chip.
    @Published var isSetupPresented = false
    @Published var text = ""
    @Published private(set) var phase = Phase.empty
    @Published var configuration: AssistantConfiguration
    /// What Copy Prompt put on the clipboard, so the composer can offer Paste Reply next.
    @Published private(set) var hasCopiedPrompt = false

    private let store: PlaygroundStore
    private unowned let playground: PlaygroundModel
    private var conversation = AssistantConversation()
    private var run: Task<Void, Never>?
    /// The settings the current proposal was measured against, so a preview can be undone exactly.
    private var previewBaseline: PlaygroundPreset?

    init(store: PlaygroundStore, playground: PlaygroundModel) {
        self.store = store
        self.playground = playground
        configuration = store.loadAssistant()
    }

    // MARK: - Opening and closing

    func toggle() {
        if isPresented {
            close()
        } else {
            open()
        }
    }

    func open() {
        isPresented = true
    }

    func toggleSetup() {
        isSetupPresented.toggle()
    }

    /// Closing leaves a request running: someone who asks for something and then goes back to the
    /// sliders should find the answer waiting rather than cancelled.
    func close() {
        isPresented = false
    }

    // MARK: - What the composer shows

    var capabilities: AssistantCapabilities {
        configuration.option.capabilities(model: configuration.model)
    }

    var isBusy: Bool { phase.isBusy }

    /// Whether the current option has everything it needs: a model where one is required, a key
    /// where one is required. The clipboard is always ready.
    var isReady: Bool {
        configuration.readiness(hasKey: AssistantKeychain.hasKey(for: configuration.option)) == .ready
    }

    /// Whether there is anything to send, and a provider that can take it.
    var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isReady
    }

    var hasConversation: Bool {
        !conversation.isEmpty
    }

    /// The one-line suggestions under an empty field. They fill the field rather than send, so a
    /// person can adjust one before it goes.
    var suggestions: [String] {
        [
            "Media player vibe",
            "Softer and glassier",
            "Hide the top bar, keep the lock",
        ]
    }

    // MARK: - Sending

    func send() {
        guard !phase.isBusy else { return }
        guard isReady else {
            isSetupPresented = true
            return
        }
        guard canSend else { return }
        let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.add(AssistantTurn(role: .person, text: asked))
        text = ""
        start()
    }

    /// Sends the last turn again, after a failure.
    func retry() {
        guard !phase.isBusy, hasConversation else { return }
        start()
    }

    private func start() {
        let base = playground.preset
        phase = .sending
        playground.assistantIsBusy = true

        run = Task { [weak self] in
            guard let self else { return }
            defer {
                self.playground.assistantIsBusy = false
                self.run = nil
            }
            do {
                let provider = try self.makeProvider()
                let request = try self.conversation.request(
                    preset: base,
                    model: self.configuration.model,
                    capabilities: self.capabilities
                )
                for try await outcome in AssistantRunner(provider: provider).run(request, base: base) {
                    switch outcome {
                        case .note:
                            // The composer's own sheen already says work is happening, so a provider's
                            // progress note is not worth a line of its own.
                            break
                        case .explanation(let explanation):
                            self.phase = .streaming(explanation)
                        case .repairing(let reason):
                            self.phase = .repairing(reason: reason)
                        case .proposal(let proposal):
                            self.accept(proposal)
                    }
                }
                // A stream that ends without a proposal was stopped.
                if self.phase.isBusy {
                    self.phase = .cancelled(partial: self.streamedExplanation)
                }
            } catch is CancellationError {
                self.phase = .cancelled(partial: self.streamedExplanation)
            } catch {
                self.fail(with: error)
            }
        }
    }

    func stop() {
        run?.cancel()
        run = nil
        playground.assistantIsBusy = false
        phase = .cancelled(partial: streamedExplanation)
    }

    private var streamedExplanation: String {
        switch phase {
            case .streaming(let text): text
            case .cancelled(let partial): partial
            default: ""
        }
    }

    private func accept(_ proposal: AssistantProposal) {
        conversation.add(AssistantTurn(role: .assistant, text: proposal.explanation))
        phase = .proposal(proposal)
    }

    private func fail(with error: any Error) {
        let message = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
        let canRetry = (error as? AssistantProviderError)?.isWorthRetrying ?? true
        // On the clipboard path the person is the transport, so a reply that could not be used comes
        // with the correction to paste back rather than an automatic second try.
        pendingCorrection = configuration.option.isManual ? AssistantClipboardExchange.correction(for: error) : nil
        phase = .failed(message: message, canRetry: canRetry)
    }

    /// Clears the conversation so the next request starts fresh.
    func newConversation() {
        run?.cancel()
        run = nil
        playground.assistantIsBusy = false
        discardPreview()
        conversation.clear()
        phase = .empty
        hasCopiedPrompt = false
    }

    // MARK: - The clipboard round trip

    /// Puts the whole request on the clipboard, for the way of asking that has no transport but a
    /// person.
    func copyPrompt() {
        guard canSend || hasConversation else { return }
        let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !asked.isEmpty {
            conversation.add(AssistantTurn(role: .person, text: asked))
            text = ""
        }
        do {
            let request = try conversation.request(
                preset: playground.preset,
                model: configuration.model,
                capabilities: capabilities
            )
            copy(AssistantClipboardExchange.prompt(for: request))
            hasCopiedPrompt = true
            phase = .empty
        } catch {
            fail(with: error)
        }
    }

    /// Reads a reply the person pasted back.
    func pasteReply() {
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        do {
            let proposal = try AssistantClipboardExchange.proposal(from: pasted, base: playground.preset)
            hasCopiedPrompt = false
            accept(proposal)
        } catch {
            fail(with: error)
        }
    }

    /// The correction to paste back into the same chat, when a reply could not be used.
    var correctionToCopy: String? {
        guard case .failed = phase, configuration.option.isManual else { return nil }
        return pendingCorrection
    }

    private var pendingCorrection: String?

    func copyCorrection() {
        guard let pendingCorrection else { return }
        copy(pendingCorrection)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Applying

    /// Applies the change to the running nook without committing it, so it can be compared against
    /// the real thing and taken back.
    func preview(_ proposal: AssistantProposal, selection: Set<String>) {
        do {
            if previewBaseline == nil {
                previewBaseline = playground.preset
            }
            playground.apply(try proposal.preset(applying: selection))
        } catch {
            fail(with: error)
        }
    }

    /// Puts back what a preview replaced.
    func discardPreview() {
        guard let previewBaseline else { return }
        self.previewBaseline = nil
        playground.apply(previewBaseline)
    }

    var isPreviewing: Bool { previewBaseline != nil }

    /// Commits the selected changes, with the existing toast offering Undo.
    func apply(_ proposal: AssistantProposal, selection: Set<String>) {
        do {
            let result = try proposal.preset(applying: selection)
            // What Undo goes back to is the state before the preview, not the preview itself.
            let undoTo = previewBaseline ?? playground.preset
            previewBaseline = nil
            let count = selection.count
            playground.apply(
                result,
                replacing: undoTo,
                announcing: count == 1 ? "Applied 1 change" : "Applied \(count) changes"
            )
        } catch {
            fail(with: error)
        }
    }

    func discard() {
        discardPreview()
        phase = .empty
    }

    // MARK: - Providers

    /// Switches tools and writes the choice down. A request in flight keeps the provider it started
    /// with; this is for the next one.
    func choose(_ option: AssistantProviderOption) {
        guard !isBusy, configuration.option != option else { return }
        configuration.select(option)
        persist()
        if !isReady {
            isSetupPresented = true
        }
    }

    /// Pins the next request to this model id. Empty is allowed where the tool has a default.
    func setModel(_ model: String) {
        guard !isBusy else { return }
        configuration.setModel(model)
        persist()
    }

    /// Whether a key is stored for the current option. The value itself stays in the Keychain.
    var hasStoredKey: Bool {
        AssistantKeychain.hasKey(for: configuration.option)
    }

    func storeKey(_ secret: AssistantSecret) {
        AssistantKeychain.store(secret, for: configuration.option)
        objectWillChange.send()
    }

    func clearKey() {
        AssistantKeychain.remove(for: configuration.option)
        objectWillChange.send()
    }

    /// Whether the command this option needs is on the PATH. Nil when the option needs no command.
    func isInstalled(_ option: AssistantProviderOption) -> Bool? {
        guard let command = option.command else { return nil }
        return AssistantToolLocator.locate(command) != nil
    }

    private func persist() {
        store.saveAssistant(configuration)
    }

    /// The provider for the current configuration.
    private func makeProvider() throws -> any AssistantProvider {
        if let fake = Self.scriptedProvider {
            return fake
        }
        switch configuration.option {
            case .codexCLI, .claudeCLI:
                let tool: AssistantCLIProvider.Tool = configuration.option == .codexCLI ? .codex : .claude
                guard let executable = AssistantCLIProvider.locate(tool) else {
                    throw AssistantProviderError.toolMissing(command: tool.command)
                }
                return AssistantCLIProvider(tool: tool, executable: executable, model: configuration.model)
            case .ollama, .anthropic, .openAI:
                let service: AssistantHTTPProvider.Service =
                    switch configuration.option {
                        case .anthropic: .anthropic
                        case .openAI: .openAI
                        default: .ollama
                    }
                return AssistantHTTPProvider(
                    service: service,
                    model: configuration.model,
                    key: AssistantKeychain.key(for: configuration.option)
                )
            case .clipboard:
                // The clipboard has no stream to await; the composer offers Copy Prompt instead.
                throw AssistantProviderError.badResponse(detail: "the clipboard path has no provider")
        }
    }

    /// A scripted provider, when `OPENNOOK_ASSISTANT_FAKE` is set.
    ///
    /// This is how every state of the composer is reached for a screenshot or an accessibility driven
    /// check without calling a model or spending anyone's tokens.
    static var scriptedProvider: AssistantFakeProvider? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENNOOK_ASSISTANT_FAKE"] == "1" else { return nil }
        let script: AssistantFakeProvider.Script =
            switch environment["OPENNOOK_ASSISTANT_SCRIPT"] {
                case "fails": .fails(.serviceUnavailable(provider: "Ollama", hint: "Start it with ollama serve."))
                case "waits": .waits
                case "repairs":
                    .answers([
                        AssistantFakeProvider.answer(
                            explanation: "Rounding the panel.",
                            patch: #"{ "settings": { "panel": { "cornerRadius": 20 } } }"#
                        ),
                        AssistantFakeProvider.mediaPlayerAnswer,
                    ])
                default: .answers([AssistantFakeProvider.mediaPlayerAnswer])
            }
        return AssistantFakeProvider(
            script: script,
            chunk: 6,
            // Slow enough that the streaming can be seen and captured.
            pace: .milliseconds(30)
        )
    }
}
