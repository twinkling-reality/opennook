// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import PlaygroundNookCore
import SwiftUI

/// The menu on the model name. A short list, sentence case, the way Claude and ChatGPT name a model.
struct AssistantSetupView: View {
    @ObservedObject var model: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AssistantProviderOption.options(in: .alreadyYours)) { option in
                row(option)
            }
            Divider()
                .overlay(PlaygroundTheme.hairline)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            ForEach(AssistantProviderOption.options(in: .billed)) { option in
                row(option)
            }
        }
        .padding(8)
        .frame(width: 260)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How to ask")
        .accessibilityIdentifier("assistant.setup")
    }

    private func row(_ option: AssistantProviderOption) -> some View {
        let isSelected = model.configuration.option == option
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                model.choose(option)
            } label: {
                HStack(spacing: 10) {
                    AssistantProviderMark(option: option)
                        .frame(width: 15, height: 15)
                        .foregroundStyle(.primary)
                    Text(option.displayTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        status(for: option)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowButtonStyle(isSelected: isSelected))
            .disabled(model.isBusy)
            .accessibilityIdentifier("assistant.provider.\(option.rawValue)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                details(for: option)
                    .padding(.leading, 33)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func details(for option: AssistantProviderOption) -> some View {
        if option.hasModel {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(option.suggestedModels, id: \.self) { id in
                    let title = option.friendlyName(for: id)
                    Button {
                        model.setModel(id)
                    } label: {
                        HStack {
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.configuration.model == id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HighlightRowButtonStyle(isSelected: model.configuration.model == id))
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("assistant.model.\(id)")
                }
                if option.allowsEmptyModel || option.suggestedModels.isEmpty || option.requiresModel {
                    TextField(
                        "Model",
                        text: modelBinding,
                        prompt: Text(option.modelPrompt)
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PlaygroundTheme.controlFill)
                    )
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("assistant.model")
                    .accessibilityLabel("Model")
                }
            }
        }
        if option.needsAPIKey {
            AssistantKeyField(option: option, model: model)
        }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { model.configuration.model },
            set: { model.setModel($0) }
        )
    }

    @ViewBuilder
    private func status(for option: AssistantProviderOption) -> some View {
        if let installed = model.isInstalled(option), !installed {
            Text("Not installed")
                .font(.system(size: 11))
                .foregroundStyle(PlaygroundTheme.destructive)
        } else if option.needsAPIKey, !(option == model.configuration.option && model.hasStoredKey) {
            Text("Needs a key")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AssistantKeyField: View {
    let option: AssistantProviderOption
    @ObservedObject var model: AssistantModel
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField(
                    "API key",
                    text: $draft,
                    prompt: Text(model.hasStoredKey ? "Key saved" : "Paste a key")
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PlaygroundTheme.controlFill)
                )
                .onSubmit(save)
                .disabled(model.isBusy)
                .accessibilityIdentifier("assistant.key")
                if !draft.isEmpty {
                    Button("Save", action: save)
                        .buttonStyle(PillButtonStyle(kind: .primary))
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("assistant.key.save")
                } else if model.hasStoredKey {
                    Button("Clear", action: clear)
                        .buttonStyle(PillButtonStyle(kind: .destructive))
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("assistant.key.clear")
                }
            }
        }
        .onChange(of: option) {
            draft = ""
        }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.storeKey(AssistantSecret(trimmed))
        draft = ""
    }

    private func clear() {
        model.clearKey()
        draft = ""
    }
}
