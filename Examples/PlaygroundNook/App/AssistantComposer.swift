// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import PlaygroundNookCore
import SwiftUI

/// The pill in the title strip that the composer grows out of.
struct AssistantPill: View {
    @ObservedObject var model: AssistantModel
    /// The namespace the pill and the composer share, so one becomes the other rather than one
    /// appearing over the top of it.
    let namespace: Namespace.ID

    var body: some View {
        Button(action: model.toggle) {
            Label("Assistant", systemImage: "sparkles")
        }
        .buttonStyle(TopPillButtonStyle(isOn: model.isPresented))
        .opacity(model.isPresented ? 0 : 1)
        .overlay(alignment: .topTrailing) {
            // While a request runs with the composer closed, the pill keeps a quiet dot rather than a
            // spinner: it says something is happening without asking to be looked at.
            if model.isBusy && !model.isPresented {
                Circle()
                    .fill(PlaygroundTheme.accent)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .matchedGeometryEffect(id: AssistantComposer.geometryID, in: namespace, isSource: !model.isPresented)
        .help(helpText)
        .accessibilityIdentifier("toolbar.assistant")
        .accessibilityLabel(model.isBusy ? "Assistant, working" : "Assistant")
        .keyboardShortcut("k", modifiers: .command)
    }

    private var helpText: String {
        if model.isBusy {
            return "The assistant is working"
        }
        return model.isPresented
            ? "Close the assistant" : "What should the nook be like? (Command-K)"
    }
}

/// The composer: a floating surface over the page that takes a description, streams the answer back,
/// and shows what it would change.
///
/// It sits in an overlay rather than in the page's own column, so opening it never moves a control
/// underneath it, and it is never a sheet, because a sheet would stop the person watching the nook,
/// which is the whole point of the playground.
struct AssistantComposer: View {
    @ObservedObject var model: AssistantModel
    let namespace: Namespace.ID
    @FocusState private var isFieldFocused: Bool

    /// The identity the pill and this surface share while one turns into the other.
    static let geometryID = "assistant.surface"

    /// The radius of the composer and its shelf. A capsule, like Claude's bar, not a page card.
    private static let radius: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.phase != .empty {
                piece {
                    body(for: model.phase)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { workingSheen }
                }
            }
            HStack(alignment: .center, spacing: 10) {
                piece {
                    HStack(alignment: .center, spacing: 10) {
                        AssistantTextField(
                            text: $model.text,
                            isFocused: $isFieldFocused,
                            onSubmit: submit
                        )
                        .accessibilityIdentifier("assistant.field")
                        modelChip
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                sendCircle
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .animation(.snappy(duration: 0.22), value: model.phase)
        .animation(.snappy(duration: 0.15), value: model.canSend)
        .matchedGeometryEffect(id: Self.geometryID, in: namespace, isSource: model.isPresented)
        .onAppear { isFieldFocused = true }
        .onExitCommand(perform: model.close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant")
    }

    // MARK: - Surface

    /// Liquid Glass where the system has it, the neutral material everywhere else, over a scrim so the
    /// page underneath reads as depth rather than as content.
    ///
    /// The scrim goes behind, not over: glass is meant to have something under it to refract, and
    /// painting a fill on top of the effect fights it instead of feeding it.
    private var surface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(PlaygroundTheme.floatingScrim)
            glass
        }
    }

    @ViewBuilder
    private var glass: some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    )
            } else {
                fallbackSurface
            }
        #else
            fallbackSurface
        #endif
    }

    private var fallbackSurface: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(.regularMaterial)
    }

    /// A thin sheen travelling along the top edge while a request is in flight. Calmer than a spinner
    /// and it cannot be mistaken for something to click.
    @ViewBuilder
    private var workingSheen: some View {
        if model.isBusy {
            AssistantWorkingSheen()
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, 12)
                .transition(.opacity)
        }
    }

    private func piece<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(PlaygroundTheme.stroke)
            }
    }

    /// Quiet text, like Claude's "Opus 5". Not a chip and not next to send.
    private var modelChip: some View {
        Button(action: model.toggleSetup) {
            HStack(spacing: 5) {
                AssistantProviderMark(option: model.configuration.option)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.secondary)
                Text(model.configuration.usageLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $model.isSetupPresented, arrowEdge: .bottom) {
            AssistantSetupView(model: model)
        }
        .help("Choose how to ask, and which model")
        .accessibilityIdentifier("assistant.provider")
        .accessibilityLabel(model.configuration.usageLabel)
        .accessibilityHint("Shows every way of asking and the model the next request will use")
    }

    // MARK: - The exchange

    @ViewBuilder
    private func body(for phase: AssistantModel.Phase) -> some View {
        switch phase {
            case .empty:
                EmptyView()
            case .sending:
                AssistantNote(text: "Thinking", isDimmed: true)
            case .streaming(let explanation):
                AssistantExplanation(text: explanation, isSettled: false)
            case .repairing(let reason):
                VStack(alignment: .leading, spacing: 6) {
                    AssistantNote(text: "Asking again", isDimmed: true)
                    Text(reason)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.tertiary)
                }
            case .proposal(let proposal):
                AssistantProposalView(model: model, proposal: proposal)
            case .cancelled(let partial):
                VStack(alignment: .leading, spacing: 6) {
                    if !partial.isEmpty {
                        Text(partial)
                            .font(PlaygroundTheme.body)
                            .foregroundStyle(.tertiary)
                    }
                    AssistantNote(text: "Stopped", isDimmed: true)
                }
            case .failed(let message, let canRetry):
                AssistantErrorRow(model: model, message: message, canRetry: canRetry)
        }
    }

    /// A circle outside the field, on its center line. Dim when there is nothing to send, lit when
    /// there is.
    private var sendCircle: some View {
        let isActive = model.isBusy || model.canSend || (model.configuration.option.isManual && model.hasCopiedPrompt)
        return Button(action: sendAction) {
            Image(systemName: sendSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                .frame(width: 36, height: 36)
                .background(Circle().fill(isActive ? Color.primary : PlaygroundTheme.controlFill))
        }
        .buttonStyle(.plain)
        .disabled(!isActive && !model.isBusy)
        .help(sendHelp)
        .accessibilityIdentifier(sendIdentifier)
        .accessibilityLabel(sendLabel)
    }

    private var sendSymbol: String {
        if model.isBusy { return "stop.fill" }
        if model.configuration.option.isManual {
            return model.hasCopiedPrompt ? "doc.on.clipboard" : "plus"
        }
        return model.canSend ? "arrow.up" : "plus"
    }

    private func sendAction() {
        if model.isBusy {
            model.stop()
        } else if model.configuration.option.isManual {
            manualAction()
        } else {
            model.send()
        }
    }

    private var sendHelp: String {
        if model.isBusy { return "Stop" }
        if model.configuration.option.isManual {
            return model.hasCopiedPrompt
                ? "Read the reply you copied from your chat"
                : "Copy the whole prompt, to paste into any chat or agent"
        }
        return model.isReady ? "Send" : readinessHint
    }

    private var sendIdentifier: String {
        if model.isBusy { return "assistant.stop" }
        if model.configuration.option.isManual {
            return model.hasCopiedPrompt ? "assistant.paste" : "assistant.copyPrompt"
        }
        return "assistant.send"
    }

    private var sendLabel: String {
        if model.isBusy { return "Stop" }
        if model.configuration.option.isManual {
            return model.hasCopiedPrompt ? "Paste reply" : "Copy prompt"
        }
        return "Send"
    }

    private var readinessHint: String {
        switch model.configuration.readiness(hasKey: model.hasStoredKey) {
            case .ready: ""
            case .needsModel: "Name the model this request should use"
            case .needsKey: "Add an API key to use \(model.configuration.option.identity.name)"
        }
    }

    private func submit() {
        if model.configuration.option.isManual {
            manualAction()
        } else {
            model.send()
        }
    }

    private func manualAction() {
        if model.hasCopiedPrompt {
            model.pasteReply()
        } else {
            model.copyPrompt()
        }
    }

    /// Quiet starting points on the shelf, not filled pills.
    private var suggestions: some View {
        HStack(spacing: 14) {
            ForEach(model.suggestions, id: \.self) { suggestion in
                Button {
                    model.text = suggestion
                    isFieldFocused = true
                } label: {
                    Text(suggestion)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant.suggestion.\(suggestion.prefix(12))")
            }
        }
    }
}

// MARK: - Parts

/// The growing text field. An `NSTextView` behind the scenes, because a SwiftUI `TextField` cannot
/// both send on Return and add a line on Shift-Return.
struct AssistantTextField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void
    /// The width the text has to wrap into. It only changes when the window does, so it cannot chase
    /// the height the way a height reported back from the field would.
    @State private var width: CGFloat = 0

    /// About five lines before it scrolls instead of growing.
    private static let maximumHeight: CGFloat = 92
    private static let minimumHeight: CGFloat = 22

    var body: some View {
        AssistantTextViewBridge(
            text: $text,
            placeholder: "What should the nook be like?",
            onSubmit: onSubmit
        )
        .frame(height: height)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, newWidth in
                        width = newWidth
                    }
            }
        }
        .animation(.snappy(duration: 0.15), value: height)
        .padding(.horizontal, 4)
        .focused($isFocused)
        .accessibilityLabel("What the nook should be like")
    }

    private var height: CGFloat {
        min(
            max(AssistantTextViewBridge.height(of: text, width: width), Self.minimumHeight),
            Self.maximumHeight
        )
    }
}

/// The explanation, as it arrives.
private struct AssistantExplanation: View {
    let text: String
    let isSettled: Bool

    var body: some View {
        Text(text)
            .font(PlaygroundTheme.body)
            .foregroundStyle(isSettled ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("assistant.explanation")
    }
}

/// A short status line, such as Thinking or Stopped.
private struct AssistantNote: View {
    let text: String
    var isDimmed = false

    var body: some View {
        Text(text)
            .font(PlaygroundTheme.caption)
            .foregroundStyle(isDimmed ? .tertiary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("assistant.note")
    }
}

/// A failure, in a sentence, with the one action worth offering.
private struct AssistantErrorRow: View {
    @ObservedObject var model: AssistantModel
    let message: String
    let canRetry: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(PlaygroundTheme.destructive)
            Text(message)
                .font(PlaygroundTheme.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if model.correctionToCopy != nil {
                Button(action: model.copyCorrection) {
                    Label("Copy Fix", systemImage: "doc.on.doc")
                }
                .buttonStyle(PillButtonStyle())
                .help("Copy a correction to paste back into the same chat")
                .accessibilityIdentifier("assistant.copyCorrection")
            } else if canRetry {
                Button(action: model.retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("assistant.retry")
            }
        }
        .accessibilityIdentifier("assistant.error")
    }
}

/// A sheen that travels along the composer's edge while a request is in flight.
private struct AssistantWorkingSheen: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: [.clear, PlaygroundTheme.accent.opacity(0.9), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.4)
            .offset(x: reduceMotion ? width * 0.3 : phase * width)
            .opacity(reduceMotion ? 0.5 : 1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
