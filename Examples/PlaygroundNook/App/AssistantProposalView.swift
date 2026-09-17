// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import PlaygroundNookCore
import SwiftUI

/// What the assistant would change, as a list a person reads and edits before anything happens.
///
/// Every row can be switched off, because a proposal is usually mostly right: someone asks for a dark
/// media player and wants the palette and the width but not the title. Reading old and new side by
/// side, in the words the controls use, is what makes it possible to agree with part of an answer
/// rather than all of it.
struct AssistantProposalView: View {
    @ObservedObject var model: AssistantModel
    let proposal: AssistantProposal
    /// Which rows are on. Everything starts on, since the answer is a whole suggestion.
    @State private var selection: Set<String> = []
    @State private var showsNotReproduced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !proposal.explanation.isEmpty {
                Text(proposal.explanation)
                    .font(PlaygroundTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assistant.explanation")
            }

            if proposal.isEmpty {
                Text("Nothing to change. The settings already say that.")
                    .font(PlaygroundTheme.caption)
                    .foregroundStyle(.secondary)
            } else {
                changes
                if !proposal.notReproduced.isEmpty {
                    notReproduced
                }
                actions
            }
        }
        .onAppear { selection = Set(proposal.changes.map(\.id)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Proposed changes")
    }

    // MARK: - Changes

    private var changes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(proposal.groups, id: \.group.id) { group, changes in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(group.title, systemImage: PlaygroundPage(group).systemImage)
                            .font(PlaygroundTheme.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(changes) { change in
                            AssistantChangeRow(
                                change: change,
                                isOn: binding(for: change)
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 260)
        .scrollIndicators(.automatic)
    }

    private func binding(for change: AssistantChange) -> Binding<Bool> {
        Binding(
            get: { selection.contains(change.id) },
            set: { isOn in
                if isOn {
                    selection.insert(change.id)
                } else {
                    selection.remove(change.id)
                }
                // A preview already on screen follows the row that just changed, so the nook always
                // shows what the checkboxes say.
                if model.isPreviewing {
                    model.preview(proposal, selection: selection)
                }
            }
        )
    }

    // MARK: - What could not be done

    /// The honest part. These settings describe the chrome, not what the app puts inside it, so a
    /// screenshot with an album grid in it can only ever be half reproduced. Saying which half is
    /// more useful than approximating the rest.
    private var notReproduced: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { showsNotReproduced.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .rotationEffect(.degrees(showsNotReproduced ? 90 : 0))
                    Text("Not reproduced (\(proposal.notReproduced.count))")
                        .font(PlaygroundTheme.caption)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("What these settings cannot express")
            .accessibilityIdentifier("assistant.notReproduced")

            if showsNotReproduced {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(proposal.notReproduced, id: \.self) { item in
                        Text("- \(item)")
                            .font(PlaygroundTheme.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Build the rest in your own views, starting from the Swift export.")
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .padding(.leading, 14)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Text(countText)
                .font(PlaygroundTheme.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 8)
            Button {
                if model.isPreviewing {
                    model.discardPreview()
                } else {
                    model.preview(proposal, selection: selection)
                }
            } label: {
                Label(
                    model.isPreviewing ? "Revert" : "Preview",
                    systemImage: model.isPreviewing ? "arrow.uturn.backward" : "play.fill"
                )
            }
            .buttonStyle(PillButtonStyle())
            .disabled(selection.isEmpty)
            .help(
                model.isPreviewing
                    ? "Put the nook back the way it was" : "Show it on the nook without keeping it"
            )
            .accessibilityIdentifier("assistant.preview")

            Button(action: model.discard) {
                Label("Discard", systemImage: "xmark")
            }
            .buttonStyle(PillButtonStyle())
            .help("Throw this suggestion away")
            .accessibilityIdentifier("assistant.discard")

            Button {
                model.apply(proposal, selection: selection)
            } label: {
                Label("Apply", systemImage: "checkmark")
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .disabled(selection.isEmpty)
            .help("Keep these changes. You can undo it right after.")
            .accessibilityIdentifier("assistant.apply")
        }
        .padding(.top, 2)
    }

    private var countText: String {
        let count = selection.count
        let total = proposal.changes.count
        if count == total {
            return total == 1 ? "1 change" : "\(total) changes"
        }
        return "\(count) of \(total)"
    }
}

/// One line of a proposal: what it is, what it was, and what it becomes.
struct AssistantChangeRow: View {
    let change: AssistantChange
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                if let subject = change.subject {
                    Text(subject)
                        .font(PlaygroundTheme.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(change.title)
                    .font(PlaygroundTheme.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                values
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .opacity(isOn ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowButtonStyle())
        .accessibilityIdentifier("assistant.change.\(change.id)")
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(isOn ? "Will be applied" : "Left out")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Old on the left, new on the right, with a swatch for a color so a hex value does not have to be
    /// imagined.
    private var values: some View {
        HStack(spacing: 6) {
            value(change.oldValue, isNew: false)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.quaternary)
            value(change.newValue, isNew: true)
        }
    }

    @ViewBuilder
    private func value(_ value: AssistantChange.Value, isNew: Bool) -> some View {
        HStack(spacing: 4) {
            if case .color(let color) = value {
                Circle()
                    .fill(color.color)
                    .frame(width: 10, height: 10)
                    .overlay { Circle().strokeBorder(PlaygroundTheme.stroke) }
            }
            Text(value.text)
                .font(PlaygroundTheme.caption.monospacedDigit())
                .foregroundStyle(isNew ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .lineLimit(1)
        }
    }

    private var accessibilityText: String {
        let subject = change.subject.map { "\($0), " } ?? ""
        return subject + change.summary
    }
}

extension PlaygroundPage {
    /// The page a group of changes belongs to, so a proposal is grouped and iconed the way the window
    /// already is.
    init(_ group: AssistantFieldGroup) {
        switch group {
            case .appearance: self = .appearance
            case .theme: self = .theme
            case .panel: self = .panel
            case .typeAndMotion: self = .typeAndMotion
            case .topBar: self = .topBar
            case .companions: self = .companions
            case .effects: self = .effects
            case .behavior: self = .behavior
        }
    }
}
