// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookApp
import PlaygroundNookCore
import SwiftUI

// MARK: - Top bar

/// `NookConfiguration.topBar` and `labels`, plus a status banner to try them on.
struct TopBarPage: View {
    @ObservedObject var model: PlaygroundModel

    private static let iconSuggestions = [
        "house", "music.note", "sun.max", "calendar", "bolt.fill", "sparkles", "timer", "tray.full", "bell",
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Show the top bar", isOn: $model.settings.topBar.showsTopBar)
                Toggle("Offer Settings", isOn: $model.settings.topBar.showsSettings)
                Toggle("Keep-open lock in the top bar", isOn: $model.settings.topBar.showsKeepOpenButton)
                    .disabled(!topBar.showsTopBar)
                Toggle("Settings gear in the top bar", isOn: $model.settings.topBar.showsSettingsButton)
                    .disabled(!topBar.showsTopBar || !topBar.showsSettings)
                Toggle("Status banner", isOn: $model.settings.topBar.showsStatusBanner)
                    .disabled(!topBar.showsTopBar)
                Picker("Width", selection: $model.settings.topBar.width) {
                    Text("Content column").tag(PlaygroundSettings.TopBar.Width.contentColumn)
                    Text("Intrinsic").tag(PlaygroundSettings.TopBar.Width.intrinsic)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Top bar")
            } footer: {
                SectionFooter(
                    text: "Offer Settings off removes Settings everywhere. The lock and gear toggles only take the "
                        + "buttons out of the bar; the Companions page can put them in a companion instead.",
                    isResettable: flagsAreModified,
                    reset: resetFlags
                )
            }

            Section {
                TextField("Title", text: $model.settings.topBar.leadingTitle, prompt: Text("Home"))
                LabeledContent("Icon") {
                    HStack(spacing: 8) {
                        TextField("Icon", text: iconName, prompt: Text("Brand mark"))
                            .labelsHidden()
                        iconPreview
                        Menu {
                            Button("Brand Mark") { model.settings.topBar.leadingIcon = nil }
                            Divider()
                            ForEach(Self.iconSuggestions, id: \.self) { name in
                                Button {
                                    model.settings.topBar.leadingIcon = name
                                } label: {
                                    Label(name, systemImage: name)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Suggested icons")
                    }
                }
            } header: {
                Text("Leading title and icon")
            } footer: {
                SectionFooter(
                    text: iconIsValid
                        ? "Any SF Symbol name works. Leave the icon empty to show the brand mark."
                        : "There is no SF Symbol named \"\(topBar.leadingIcon ?? "")\", so the top bar shows no icon.",
                    isResettable: topBar.leadingTitle != "Home" || topBar.leadingIcon != nil,
                    reset: {
                        model.settings.topBar.leadingTitle = PlaygroundSettings.TopBar().leadingTitle
                        model.settings.topBar.leadingIcon = nil
                    }
                )
            }

            Section {
                TextField("Settings breadcrumb", text: $model.settings.labels.settingsBreadcrumb)
                TextField("Keep-open tooltip", text: $model.settings.labels.keepOpenHelp)
                TextField("Settings tooltip", text: $model.settings.labels.settingsHelp)
                TextField("Dismiss tooltip", text: $model.settings.labels.dismissHelp)
            } header: {
                Text("Labels")
            } footer: {
                SectionFooter(
                    text: "The chrome's own strings, for localization or product naming.",
                    isResettable: model.settings.labels != .init(),
                    reset: { model.settings.labels = .init() }
                )
            }

            Section {
                TextField("Message", text: $model.demo.statusMessage)
                Picker("Severity", selection: $model.demo.statusSeverity) {
                    ForEach(NookStatusSeverity.allCases, id: \.self) { severity in
                        Text(severity.rawValue.capitalized).tag(severity.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("Post Banner") { model.postStatus() }
                    Button("Clear Banner") { model.clearStatus() }
                }
            } header: {
                Text("Status banner demo")
            } footer: {
                SectionFooter(
                    text: "Posts the message with AppState.showStatus(_:severity:), opening the nook first. "
                        + "The banner needs the top bar and its banner switched on."
                )
            }
        }
        .formStyle(.grouped)
    }

    private var topBar: PlaygroundSettings.TopBar { model.settings.topBar }

    private var flagsAreModified: Bool {
        var flags = topBar
        flags.leadingTitle = PlaygroundSettings.TopBar().leadingTitle
        flags.leadingIcon = nil
        return flags != PlaygroundSettings.TopBar()
    }

    /// Resets the switches and the width, leaving the title and icon to their own section.
    private func resetFlags() {
        var reset = PlaygroundSettings.TopBar()
        reset.leadingTitle = topBar.leadingTitle
        reset.leadingIcon = topBar.leadingIcon
        model.settings.topBar = reset
    }

    private var iconName: Binding<String> {
        Binding(
            get: { model.settings.topBar.leadingIcon ?? "" },
            set: { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                model.settings.topBar.leadingIcon = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var iconIsValid: Bool {
        guard let name = topBar.leadingIcon else { return true }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    @ViewBuilder
    private var iconPreview: some View {
        Group {
            if let name = topBar.leadingIcon {
                Image(systemName: iconIsValid ? name : "questionmark.square.dashed")
            } else {
                Image(systemName: "seal")
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
    }
}

// MARK: - Companions

/// `NookConfiguration.addCompanion`, one section per companion.
struct CompanionsPage: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        Form {
            Section {
                if model.settings.companions.isEmpty {
                    Text("No companions yet. Add one to float a view beside the nook.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Menu("Add Companion") {
                        ForEach(PlaygroundSettings.Companion.Kind.allCases, id: \.self) { kind in
                            Button(kind.title) { add(kind) }
                        }
                    }
                    .fixedSize()
                    Button("Move the Lock and Gear into a Companion", action: moveControlsIntoCompanion)
                        .disabled(controlsAreInCompanion)
                }
            } header: {
                Text("Companions")
            } footer: {
                SectionFooter(
                    text: "Companions share an anchor to form a row, in the order listed here. Most show only "
                        + "while the nook is expanded; choose Compact or Both to keep one beside the collapsed "
                        + "pill.",
                    isResettable: !model.settings.companions.isEmpty,
                    reset: { model.settings.companions = [] }
                )
            }

            ForEach($model.settings.companions) { $companion in
                CompanionEditor(
                    companion: $companion,
                    otherIDs: Set(model.settings.companions.map(\.id)).subtracting([companion.id]),
                    canMoveUp: model.settings.companions.first?.id != companion.id,
                    canMoveDown: model.settings.companions.last?.id != companion.id,
                    move: { offset in move(companion.id, by: offset) },
                    remove: { remove(companion.id) }
                )
            }
        }
        .formStyle(.grouped)
    }

    private var controlsAreInCompanion: Bool {
        !model.settings.topBar.showsKeepOpenButton && !model.settings.topBar.showsSettingsButton
            && model.settings.companions.contains { $0.kind == .controls }
    }

    private func newCompanion(_ kind: PlaygroundSettings.Companion.Kind) -> PlaygroundSettings.Companion {
        var companion = PlaygroundSettings.Companion(
            id: "",
            kind: kind,
            accessibilityLabel: kind.suggestedAccessibilityLabel
        )
        companion.id = PlaygroundSettings.uniqueID(
            for: companion,
            avoiding: Set(model.settings.companions.map(\.id))
        )
        switch kind {
            case .button:
                companion.outline = .circle
            case .controls:
                companion.anchor = .trailing
                companion.hidesInSettings = false
            case .actions, .chip:
                break
        }
        return companion
    }

    private func add(_ kind: PlaygroundSettings.Companion.Kind) {
        model.settings.companions.append(newCompanion(kind))
    }

    /// The same move CompanionNook makes: the lock and gear leave the top bar for a companion
    /// that stays up in Settings, since its gear is the way back out.
    private func moveControlsIntoCompanion() {
        var settings = model.settings
        settings.topBar.showsKeepOpenButton = false
        settings.topBar.showsSettingsButton = false
        if !settings.companions.contains(where: { $0.kind == .controls }) {
            settings.companions.append(newCompanion(.controls))
        }
        model.settings = settings
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = model.settings.companions.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard model.settings.companions.indices.contains(destination) else { return }
        model.settings.companions.swapAt(index, destination)
    }

    private func remove(_ id: String) {
        model.settings.companions.removeAll { $0.id == id }
    }
}

private struct CompanionEditor: View {
    @Binding var companion: PlaygroundSettings.Companion
    let otherIDs: Set<String>
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        Section {
            CompanionIDField(id: $companion.id, otherIDs: otherIDs)
            Picker("Content", selection: $companion.kind) {
                ForEach(PlaygroundSettings.Companion.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            TextField("Accessibility label", text: accessibilityLabel, prompt: Text("None"))
            Picker("Anchor", selection: $companion.anchor) {
                Text("Below").tag(PlaygroundSettings.Companion.Anchor.below)
                Text("Leading").tag(PlaygroundSettings.Companion.Anchor.leading)
                Text("Trailing").tag(PlaygroundSettings.Companion.Anchor.trailing)
            }
            .pickerStyle(.segmented)
            Picker("Alignment", selection: $companion.alignment) {
                Text(companion.anchor == .below ? "Leading" : "Top").tag(
                    PlaygroundSettings.Companion.AnchorAlignment.start
                )
                Text("Center").tag(PlaygroundSettings.Companion.AnchorAlignment.center)
                Text(companion.anchor == .below ? "Trailing" : "Bottom").tag(
                    PlaygroundSettings.Companion.AnchorAlignment.end
                )
            }
            .pickerStyle(.segmented)
            NumberRow(
                title: "Spacing",
                value: $companion.spacing,
                range: 0...40,
                defaultValue: Double(NookCompanionSurface.defaultSpacing)
            )
            Picker("Shown", selection: $companion.visibility) {
                Text("Expanded").tag(PlaygroundSettings.Companion.Visibility.expanded)
                Text("Compact").tag(PlaygroundSettings.Companion.Visibility.compact)
                Text("Both").tag(PlaygroundSettings.Companion.Visibility.both)
            }
            .pickerStyle(.segmented)
            Picker("Shape", selection: $companion.outline) {
                Text("Capsule").tag(PlaygroundSettings.Companion.Outline.capsule)
                Text("Circle").tag(PlaygroundSettings.Companion.Outline.circle)
                Text("Rounded").tag(PlaygroundSettings.Companion.Outline.roundedRectangle)
            }
            .pickerStyle(.segmented)
            if companion.outline == .roundedRectangle {
                NumberRow(title: "Corner radius", value: $companion.cornerRadius, range: 0...30, defaultValue: 12)
            }
            Picker("Backdrop", selection: $companion.backdrop) {
                Text("Chrome").tag(PlaygroundSettings.Companion.Backdrop.inherit)
                Text("Solid").tag(PlaygroundSettings.Companion.Backdrop.solid)
                Text("Glass").tag(PlaygroundSettings.Companion.Backdrop.glass)
                Text("None").tag(PlaygroundSettings.Companion.Backdrop.none)
            }
            .pickerStyle(.segmented)
            if companion.backdrop == .solid || companion.backdrop == .glass {
                ColorPicker(
                    companion.backdrop == .solid ? "Fill" : "Tint",
                    selection: backdropColor,
                    supportsOpacity: true
                )
            }
            Toggle("Step aside while Settings is showing", isOn: $companion.hidesInSettings)
        } header: {
            HStack {
                Text(companion.id)
                    .font(.headline.monospaced())
                Text(companion.kind.title)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    move(-1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMoveUp)
                .help("Move up")
                .accessibilityLabel("Move \(companion.id) up")
                Button {
                    move(1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMoveDown)
                .help("Move down")
                .accessibilityLabel("Move \(companion.id) down")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .help("Remove")
                .accessibilityLabel("Remove \(companion.id)")
            }
            .buttonStyle(.borderless)
        }
    }

    private var accessibilityLabel: Binding<String> {
        Binding(
            get: { companion.accessibilityLabel ?? "" },
            set: { companion.accessibilityLabel = $0.isEmpty ? nil : $0 }
        )
    }

    private var backdropColor: Binding<Color> {
        Binding(
            get: { companion.backdropColor.color },
            set: { companion.backdropColor = PlaygroundColor($0) }
        )
    }
}

/// Edits a companion id. The id is the companion's identity - in the list here and in the
/// chrome - so it changes only when editing ends, and only to a unique, non-empty value
/// (`NookConfiguration.addCompanion` traps on a duplicate).
private struct CompanionIDField: View {
    @Binding var id: String
    let otherIDs: Set<String>
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent("ID") {
            VStack(alignment: .trailing, spacing: 2) {
                TextField("ID", text: $draft)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .onSubmit(commit)
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { draft = id }
        .onChange(of: id) { draft = id }
        .onChange(of: isFocused) {
            if !isFocused { commit() }
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var problem: String? {
        if trimmedDraft.isEmpty { return "An ID cannot be empty." }
        if otherIDs.contains(trimmedDraft) { return "Another companion uses this ID." }
        return nil
    }

    private func commit() {
        guard problem == nil else {
            draft = id
            return
        }
        id = trimmedDraft
    }
}

// MARK: - Effects

/// `NookConfiguration.rimGlow` and `scrollEdgeFade`, with demos for both.
struct EffectsPage: View {
    @ObservedObject var model: PlaygroundModel

    private let rimDefaults = PlaygroundSettings.RimGlow()
    private let fadeDefaults = PlaygroundSettings.ScrollEdgeFade()

    var body: some View {
        Form {
            Section {
                Toggle("Light the rim", isOn: $model.demo.rimGlowLit)
                ColorPicker("Rim color", selection: rimColor, supportsOpacity: false)
            } header: {
                Text("Rim glow demo")
            } footer: {
                SectionFooter(
                    text: "While this is on, the home view and the compact slots light the rim with "
                        + "nookRimGlow(_:), so it stays lit after the nook collapses. The round button companion "
                        + "toggles it too."
                )
            }

            Section {
                NumberRow(
                    title: "Line width",
                    value: $model.settings.rimGlow.lineWidth,
                    range: 0...6,
                    step: 0.5,
                    defaultValue: rimDefaults.lineWidth
                )
                NumberRow(
                    title: "Glow radius",
                    value: $model.settings.rimGlow.glowRadius,
                    range: 0...30,
                    defaultValue: rimDefaults.glowRadius
                )
                NumberRow(
                    title: "Intensity",
                    value: $model.settings.rimGlow.intensity,
                    range: 0...1,
                    step: 0.01,
                    defaultValue: rimDefaults.intensity,
                    unit: ""
                )
                Toggle("Breathe while lit", isOn: $model.settings.rimGlow.pulses)
                Toggle(
                    "Follow the ambient color when nothing lights it",
                    isOn: $model.settings.rimGlow.followsAmbientColor
                )
            } header: {
                Text("Rim glow style")
            } footer: {
                SectionFooter(
                    text: "Reduce Motion stills the breathing, Increase Contrast draws a bolder line, and Reduce "
                        + "Transparency drops the halo.",
                    isResettable: model.settings.rimGlow != rimDefaults,
                    reset: { model.settings.rimGlow = rimDefaults }
                )
            }

            Section {
                Toggle("Fade scrolling content at the panel's edges", isOn: $model.settings.scrollEdgeFade.isEnabled)
                LabeledContent("Edges") {
                    HStack(spacing: 12) {
                        Toggle("Top", isOn: $model.settings.scrollEdgeFade.top)
                        Toggle("Bottom", isOn: $model.settings.scrollEdgeFade.bottom)
                        Toggle("Leading", isOn: $model.settings.scrollEdgeFade.leading)
                        Toggle("Trailing", isOn: $model.settings.scrollEdgeFade.trailing)
                    }
                    .toggleStyle(.checkbox)
                }
                .disabled(!model.settings.scrollEdgeFade.isEnabled)
                NumberRow(
                    title: "Length",
                    value: $model.settings.scrollEdgeFade.length,
                    range: 0...60,
                    defaultValue: fadeDefaults.length
                )
                .disabled(!model.settings.scrollEdgeFade.isEnabled)
                Toggle("Show the scrolling demo in the nook", isOn: $model.demo.showsScrollDemo)
            } header: {
                Text("Scroll edge fade")
            } footer: {
                SectionFooter(
                    text: "On macOS 26 the top and bottom edges use the system's soft scroll edge effect; the "
                        + "sides, and every edge on earlier systems, use a gradient mask. The demo list and chips "
                        + "opt in with nookScrollEdgeFade(axes:), as the Settings screen does.",
                    isResettable: model.settings.scrollEdgeFade != fadeDefaults,
                    reset: { model.settings.scrollEdgeFade = fadeDefaults }
                )
            }
        }
        .formStyle(.grouped)
    }

    private var rimColor: Binding<Color> {
        Binding(
            get: { model.demo.rimGlowColor.color },
            set: { model.demo.rimGlowColor = PlaygroundColor($0) }
        )
    }
}

// MARK: - Behavior

/// `NookChromeBehavior.hoverBehavior`, applied with `replaceChromeBehavior(_:)`.
struct BehaviorPage: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        Form {
            Section {
                Toggle("Stay visible while hovered", isOn: $model.settings.behavior.hoverKeepsVisible)
                Toggle("Haptic feedback on hover", isOn: $model.settings.behavior.hoverHaptics)
            } header: {
                Text("Hover")
            } footer: {
                SectionFooter(
                    text: "Stay visible makes a request to hide the nook wait until the pointer leaves it. The "
                        + "haptic plays on a Force Touch trackpad as the pointer enters and leaves the nook. Both "
                        + "apply at once, through AppCoordinator.replaceChromeBehavior(_:).",
                    isResettable: model.settings.behavior != .init(),
                    reset: { model.settings.behavior = .init() }
                )
            }
        }
        .formStyle(.grouped)
    }
}
