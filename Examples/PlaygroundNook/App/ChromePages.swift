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
    @AppStorage("playground.topBar.showsLabels") private var showsLabels = false

    private static let iconSuggestions = [
        "house", "music.note", "sun.max", "calendar", "bolt.fill", "sparkles", "timer", "tray.full", "bell",
    ]

    var body: some View {
        PlaygroundPageView(page: .topBar) {
            SectionCard(title: "Bar", isModified: flagsAreModified, reset: resetFlags) {
                SwitchRow(
                    title: "Top bar",
                    isOn: $model.settings.topBar.showsTopBar,
                    help: "The row with the title, the lock, and the gear."
                )
                if topBar.showsTopBar {
                    SegmentedRow(
                        title: "Width",
                        selection: $model.settings.topBar.width,
                        choices: [Choice(.contentColumn, "Column"), Choice(.intrinsic, "Fit")],
                        help: "Column spans the content. Fit wraps the icons and centers them."
                    )
                    SwitchRow(title: "Lock button", isOn: $model.settings.topBar.showsKeepOpenButton)
                    if topBar.showsSettings {
                        SwitchRow(title: "Gear button", isOn: $model.settings.topBar.showsSettingsButton)
                    }
                    SwitchRow(
                        title: "Status banner",
                        isOn: $model.settings.topBar.showsStatusBanner,
                        help: "The message strip under the top bar."
                    )
                }
                SwitchRow(
                    title: "Settings",
                    isOn: $model.settings.topBar.showsSettings,
                    help: "Off removes Settings everywhere: the gear, the screen, and the menu item."
                )
            }

            if topBar.showsTopBar {
                SectionCard(
                    title: "Title",
                    isModified: topBar.leadingTitle != defaults.leadingTitle || topBar.leadingIcon != nil,
                    reset: {
                        model.settings.topBar.leadingTitle = defaults.leadingTitle
                        model.settings.topBar.leadingIcon = nil
                    }
                ) {
                    TextRow(title: "Title", text: $model.settings.topBar.leadingTitle, prompt: "Home")
                    iconRow
                }
            }

            SectionCard(
                title: "Notch",
                help: "What happens in the band beside the notch while the top bar is hidden.",
                isModified: notchIsModified,
                reset: {
                    model.settings.topBar.notchClearance = defaults.notchClearance
                    model.settings.topBar.notchAccessories = defaults.notchAccessories
                }
            ) {
                SegmentedRow(
                    title: "Clearance",
                    selection: $model.settings.topBar.notchClearance,
                    choices: [Choice(.automatic, "Automatic"), Choice(.manual, "Manual")],
                    help: "Automatic starts the content below the notch. Manual lets it run up beside the notch."
                )
                SwitchRow(
                    title: "Header beside notch",
                    isOn: $model.settings.topBar.notchAccessories,
                    help: "Moves the home view's header into the band beside the notch, with "
                        + "nookNotchAccessories(leading:trailing:)."
                )
            }

            CollapsibleCard(
                title: "Labels",
                help: "The chrome's own strings, for localization or product naming.",
                isExpanded: $showsLabels,
                isModified: model.settings.labels != .init(),
                reset: { model.settings.labels = .init() }
            ) {
                TextRow(title: "Breadcrumb", text: $model.settings.labels.settingsBreadcrumb)
                TextRow(title: "Lock tooltip", text: $model.settings.labels.keepOpenHelp)
                TextRow(title: "Gear tooltip", text: $model.settings.labels.settingsHelp)
                TextRow(title: "Close tooltip", text: $model.settings.labels.dismissHelp)
            }

            SectionCard(title: "Banner Preview") {
                TextRow(title: "Message", text: $model.demo.statusMessage)
                SegmentedRow(
                    title: "Severity",
                    selection: $model.demo.statusSeverity,
                    choices: NookStatusSeverity.allCases.map { Choice($0.rawValue, $0.rawValue.capitalized) }
                )
            } accessory: {
                Button(action: model.clearStatus) {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(IconButtonStyle())
                .help("Clear the banner")
                PreviewButton(help: bannerPreviewHelp, action: { model.postStatus() })
                    .disabled(!bannerIsShown)
            }
        }
    }

    private var topBar: PlaygroundSettings.TopBar { model.settings.topBar }
    private var defaults: PlaygroundSettings.TopBar { .init() }

    private var bannerIsShown: Bool {
        topBar.showsTopBar && topBar.showsStatusBanner
    }

    private var bannerPreviewHelp: String {
        bannerIsShown ? "Post the message in the nook" : "The banner needs the top bar and its status banner"
    }

    private var flagsAreModified: Bool {
        var flags = topBar
        flags.leadingTitle = defaults.leadingTitle
        flags.leadingIcon = nil
        flags.notchClearance = defaults.notchClearance
        flags.notchAccessories = defaults.notchAccessories
        return flags != defaults
    }

    private var notchIsModified: Bool {
        topBar.notchClearance != defaults.notchClearance || topBar.notchAccessories != defaults.notchAccessories
    }

    /// Resets the switches and the width, leaving the title and the notch to their cards.
    private func resetFlags() {
        var reset = defaults
        reset.leadingTitle = topBar.leadingTitle
        reset.leadingIcon = topBar.leadingIcon
        reset.notchClearance = topBar.notchClearance
        reset.notchAccessories = topBar.notchAccessories
        model.settings.topBar = reset
    }

    private var iconRow: some View {
        ControlRow(
            title: "Icon",
            help: "Any SF Symbol name. Leave it empty for the brand mark.",
            isModified: topBar.leadingIcon != nil
        ) {
            HStack(spacing: 8) {
                TextField("Icon", text: iconName, prompt: Text("Brand mark"))
                    .labelsHidden()
                    .playgroundField()
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
                    Image(systemName: "square.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .modifier(HoverCircle(size: 26))
                .help("Suggested icons")
                .accessibilityLabel("Suggested icons")
            }
        } reset: {
            model.settings.topBar.leadingIcon = nil
        }
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

    private var iconPreview: some View {
        Group {
            if let name = topBar.leadingIcon {
                if iconIsValid {
                    Image(systemName: name)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help("No SF Symbol has this name, so the top bar shows no icon")
                }
            } else {
                Image(systemName: "seal")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 13, weight: .light))
        .frame(width: 18)
    }
}

// MARK: - Companions

/// `NookConfiguration.addCompanion`: a list of companions, and an editor for the selected one.
struct CompanionsPage: View {
    @ObservedObject var model: PlaygroundModel
    @State private var selectedID: String?
    @State private var editorTab = CompanionEditor.Tab.placement
    @State private var isAdding = false

    var body: some View {
        PlaygroundPageView(page: .companions) {
            if companions.isEmpty {
                emptyState
            } else {
                SectionCard(
                    title: "Companions",
                    help: "Views that float beside the nook. Companions on the same side form a row, in this order."
                ) {
                    ForEach(companions) { companion in
                        CompanionListRow(
                            companion: companion,
                            isSelected: companion.id == selection?.id,
                            canMoveUp: companion.id != companions.first?.id,
                            canMoveDown: companion.id != companions.last?.id,
                            select: { selectedID = companion.id },
                            move: { move(companion.id, by: $0) },
                            remove: { remove(companion.id) }
                        )
                    }
                } accessory: {
                    addButton
                }
            }

            if let selection, let binding = binding(for: selection.id) {
                CompanionEditor(
                    companion: binding,
                    tab: $editorTab,
                    otherIDs: Set(companions.map(\.id)).subtracting([selection.id])
                )
            }
        }
    }

    private var companions: [PlaygroundSettings.Companion] {
        model.settings.companions
    }

    /// The selected companion, or the first one when nothing valid is selected.
    private var selection: PlaygroundSettings.Companion? {
        companions.first { $0.id == selectedID } ?? companions.first
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No companions yet")
                .font(.system(size: 15, weight: .light))
            Text("Views that float beside the nook.")
                .font(PlaygroundTheme.caption)
                .foregroundStyle(.secondary)
            addButton
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .surface()
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Add", systemImage: "plus")
        }
        .buttonStyle(PillButtonStyle(kind: .primary))
        .help("Add a companion")
        .popover(isPresented: $isAdding, arrowEdge: .bottom) {
            AddCompanionList(
                canAddControls: !companions.contains { $0.kind == .controls },
                add: { kind in
                    isAdding = false
                    add(kind)
                }
            )
        }
    }

    /// A binding that follows the companion by id, and moves the selection along when the id
    /// is edited.
    private func binding(for id: String) -> Binding<PlaygroundSettings.Companion>? {
        guard let current = companions.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.settings.companions.first { $0.id == id } ?? current },
            set: { companion in
                guard let index = model.settings.companions.firstIndex(where: { $0.id == id }) else { return }
                model.settings.companions[index] = companion
                if companion.id != id {
                    selectedID = companion.id
                }
            }
        )
    }

    private func newCompanion(_ kind: PlaygroundSettings.Companion.Kind) -> PlaygroundSettings.Companion {
        var companion = PlaygroundSettings.Companion(
            id: "",
            kind: kind,
            accessibilityLabel: kind.suggestedAccessibilityLabel
        )
        companion.id = PlaygroundSettings.uniqueID(for: companion, avoiding: Set(companions.map(\.id)))
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

    /// Nook controls move the lock and gear out of the top bar, as CompanionNook does; the
    /// companion stays up in Settings, since its gear is the way back out.
    private func add(_ kind: PlaygroundSettings.Companion.Kind) {
        var settings = model.settings
        let companion = newCompanion(kind)
        settings.companions.append(companion)
        if kind == .controls {
            settings.topBar.showsKeepOpenButton = false
            settings.topBar.showsSettingsButton = false
        }
        model.settings = settings
        selectedID = companion.id
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = companions.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard companions.indices.contains(destination) else { return }
        model.settings.companions.swapAt(index, destination)
    }

    /// Removing the last Nook controls companion puts the lock and gear back in the top bar,
    /// so they are never lost.
    private func remove(_ id: String) {
        guard let index = companions.firstIndex(where: { $0.id == id }) else { return }
        var settings = model.settings
        let removed = settings.companions.remove(at: index)
        if removed.kind == .controls, !settings.companions.contains(where: { $0.kind == .controls }) {
            settings.topBar.showsKeepOpenButton = true
            settings.topBar.showsSettingsButton = true
        }
        model.settings = settings
        if selectedID == id {
            let remaining = settings.companions
            selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }
}

extension PlaygroundSettings.Companion.Kind {
    var symbol: String {
        switch self {
            case .actions: "capsule"
            case .button: "circle"
            case .controls: "gearshape"
            case .chip: "tag"
        }
    }

    fileprivate var blurb: String {
        switch self {
            case .actions: "A pill of icon buttons"
            case .button: "One round button"
            case .controls: "The lock and gear, out of the top bar"
            case .chip: "A short status label"
        }
    }
}

/// The kinds of companion to add, each with a line on what it is.
private struct AddCompanionList: View {
    let canAddControls: Bool
    let add: (PlaygroundSettings.Companion.Kind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(PlaygroundSettings.Companion.Kind.allCases, id: \.self) { kind in
                let isEnabled = kind != .controls || canAddControls
                Button {
                    add(kind)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(PlaygroundTheme.controlFill))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.title)
                                .font(PlaygroundTheme.body)
                            Text(isEnabled ? kind.blurb : "Already added")
                                .font(PlaygroundTheme.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HighlightRowButtonStyle())
                .disabled(!isEnabled)
            }
        }
        .padding(8)
        .frame(width: 280)
    }
}

private struct CompanionListRow: View {
    let companion: PlaygroundSettings.Companion
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: companion.kind.symbol)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(PlaygroundTheme.controlFill))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(companion.id)
                            .font(PlaygroundTheme.body)
                            .lineLimit(1)
                        Text(summary)
                            .font(PlaygroundTheme.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowButtonStyle(isSelected: isSelected))
            .accessibilityLabel("\(companion.id), \(summary)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Menu {
                Button("Move Up") { move(-1) }
                    .disabled(!canMoveUp)
                Button("Move Down") { move(1) }
                    .disabled(!canMoveDown)
                Divider()
                Button("Remove", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .modifier(HoverCircle(size: 26))
            .help("Move or remove")
            .accessibilityLabel("Actions for \(companion.id)")
        }
        .contextMenu {
            Button("Move Up") { move(-1) }
                .disabled(!canMoveUp)
            Button("Move Down") { move(1) }
                .disabled(!canMoveDown)
            Divider()
            Button("Remove", role: .destructive, action: remove)
        }
    }

    private var summary: String {
        let side =
            switch companion.anchor {
                case .below: "below"
                case .leading: "leading side"
                case .trailing: "trailing side"
            }
        let shown =
            switch companion.visibility {
                case .expanded: "when expanded"
                case .compact: "when collapsed"
                case .both: "always"
            }
        return "\(companion.kind.title), \(side), \(shown)"
    }
}

/// The selected companion's settings, a few at a time.
struct CompanionEditor: View {
    enum Tab: Hashable {
        case placement
        case style
        case details
    }

    @Binding var companion: PlaygroundSettings.Companion
    @Binding var tab: Tab
    let otherIDs: Set<String>

    private typealias Companion = PlaygroundSettings.Companion

    var body: some View {
        SectionCard(title: companion.id) {
            switch tab {
                case .placement: placementRows
                case .style: styleRows
                case .details: detailRows
            }
        } accessory: {
            PillPicker(
                title: "Editor",
                selection: $tab,
                choices: [Choice(.placement, "Placement"), Choice(.style, "Style"), Choice(.details, "Details")]
            )
            .frame(width: 230)
        }
    }

    @ViewBuilder
    private var placementRows: some View {
        SegmentedRow(
            title: "Side",
            selection: $companion.anchor,
            choices: [Choice(.below, "Below"), Choice(.leading, "Leading"), Choice(.trailing, "Trailing")],
            help: "The edge of the nook it hangs from."
        )
        SegmentedRow(
            title: "Align",
            selection: $companion.alignment,
            choices: companion.anchor == .below
                ? [Choice(.start, "Leading"), Choice(.center, "Center"), Choice(.end, "Trailing")]
                : [Choice(.start, "Top"), Choice(.center, "Center"), Choice(.end, "Bottom")],
            help: "Where it sits along that edge."
        )
        SliderRow(
            title: "Spacing",
            value: $companion.spacing,
            range: 0...40,
            defaultValue: Double(NookCompanionSurface.defaultSpacing),
            help: "The gap to the nook, or to the companion before it."
        )
        SegmentedRow(
            title: "Shown",
            selection: $companion.visibility,
            choices: [Choice(.expanded, "Expanded"), Choice(.compact, "Collapsed"), Choice(.both, "Always")],
            help: "Whether it shows with the nook expanded, beside the collapsed pill, or both."
        )
    }

    @ViewBuilder
    private var styleRows: some View {
        SegmentedRow(
            title: "Shape",
            selection: $companion.outline,
            choices: [Choice(.capsule, "Capsule"), Choice(.circle, "Circle"), Choice(.roundedRectangle, "Rounded")]
        )
        if companion.outline == .roundedRectangle {
            SliderRow(title: "Corners", value: $companion.cornerRadius, range: 0...30, defaultValue: 12)
        }
        SegmentedRow(
            title: "Backdrop",
            selection: $companion.backdrop,
            choices: [
                Choice(.inherit, "Chrome"), Choice(.solid, "Solid"), Choice(.glass, "Glass"), Choice(.none, "None"),
            ],
            help: "Chrome matches the nook. None leaves the content to draw its own."
        )
        if companion.backdrop == .solid || companion.backdrop == .glass {
            ControlRow(title: companion.backdrop == .solid ? "Fill" : "Tint") {
                ColorSwatch(title: "Backdrop color", color: backdropColor, supportsOpacity: true)
            }
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        CompanionIDField(id: $companion.id, otherIDs: otherIDs)
        SegmentedRow(
            title: "Content",
            selection: $companion.kind,
            choices: Companion.Kind.allCases.map { Choice($0, $0.shortTitle) },
            help: "The demo view the companion shows."
        )
        TextRow(
            title: "VoiceOver label",
            text: accessibilityLabel,
            prompt: "None",
            help: "What VoiceOver reads for the companion."
        )
        SwitchRow(
            title: "Hide in Settings",
            isOn: $companion.hidesInSettings,
            help: "Steps aside while the Settings screen is showing."
        )
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

extension PlaygroundSettings.Companion.Kind {
    fileprivate var shortTitle: String {
        switch self {
            case .actions: "Pill"
            case .button: "Button"
            case .controls: "Controls"
            case .chip: "Chip"
        }
    }
}

/// Edits a companion id. The id is the companion's identity, in the list here and in the
/// chrome, so it changes only when editing ends, and only to a unique, non-empty value
/// (`NookConfiguration.addCompanion` traps on a duplicate).
private struct CompanionIDField: View {
    @Binding var id: String
    let otherIDs: Set<String>
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ControlRow(title: "ID", help: "The companion's identity. It must be unique.") {
            HStack(spacing: 6) {
                if let problem {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .help(problem)
                        .accessibilityLabel(problem)
                }
                TextField("ID", text: $draft)
                    .labelsHidden()
                    .playgroundField()
                    .focused($isFocused)
                    .onSubmit(commit)
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
        if trimmedDraft.isEmpty { return "An ID cannot be empty" }
        if otherIDs.contains(trimmedDraft) { return "Another companion uses this ID" }
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
        PlaygroundPageView(page: .effects) {
            SectionCard(
                title: "Rim Glow",
                isModified: model.settings.rimGlow != rimDefaults,
                reset: { model.settings.rimGlow = rimDefaults }
            ) {
                ControlRow(
                    title: "Light it",
                    help: "The home view and the compact slots light the rim with nookRimGlow(_:), so it stays lit "
                        + "after the nook collapses."
                ) {
                    HStack(spacing: 10) {
                        ColorSwatch(title: "Rim color", color: rimColor)
                        Toggle("Light the rim", isOn: $model.demo.rimGlowLit)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }
                SliderRow(
                    title: "Line width",
                    value: $model.settings.rimGlow.lineWidth,
                    range: 0...6,
                    step: 0.5,
                    defaultValue: rimDefaults.lineWidth,
                    help: "Increase Contrast draws it bolder."
                )
                SliderRow(
                    title: "Glow",
                    value: $model.settings.rimGlow.glowRadius,
                    range: 0...30,
                    defaultValue: rimDefaults.glowRadius,
                    help: "The halo's radius. Reduce Transparency drops the halo."
                )
                SliderRow(
                    title: "Intensity",
                    value: $model.settings.rimGlow.intensity,
                    range: 0...1,
                    step: 0.01,
                    defaultValue: rimDefaults.intensity,
                    format: .percent
                )
                SwitchRow(
                    title: "Breathe",
                    isOn: $model.settings.rimGlow.pulses,
                    help: "The halo pulses slowly while lit. Reduce Motion stills it."
                )
                SwitchRow(
                    title: "Ambient color",
                    isOn: $model.settings.rimGlow.followsAmbientColor,
                    help: "With nothing lighting the rim, it takes the ambient color content reports."
                )
            }

            SectionCard(
                title: "Scroll Edge Fade",
                isModified: model.settings.scrollEdgeFade != fadeDefaults,
                reset: { model.settings.scrollEdgeFade = fadeDefaults }
            ) {
                SwitchRow(
                    title: "Fade edges",
                    isOn: $model.settings.scrollEdgeFade.isEnabled,
                    help: "Scroll views that opt in with nookScrollEdgeFade(axes:) fade where they meet the "
                        + "panel's edges."
                )
                if model.settings.scrollEdgeFade.isEnabled {
                    ControlRow(title: "Edges") {
                        EdgeToggles(fade: $model.settings.scrollEdgeFade)
                    }
                    SliderRow(
                        title: "Length",
                        value: $model.settings.scrollEdgeFade.length,
                        range: 0...60,
                        defaultValue: fadeDefaults.length
                    )
                }
                SwitchRow(
                    title: "Scrolling demo",
                    isOn: $model.demo.showsScrollDemo,
                    help: "A scrolling list and tag row in the nook to try the fade on."
                )
            }
        }
    }

    private var rimColor: Binding<Color> {
        Binding(
            get: { model.demo.rimGlowColor.color },
            set: { model.demo.rimGlowColor = PlaygroundColor($0) }
        )
    }
}

/// The four fade edges as round toggles.
private struct EdgeToggles: View {
    @Binding var fade: PlaygroundSettings.ScrollEdgeFade

    var body: some View {
        HStack(spacing: 6) {
            edge("Top", "arrow.up.to.line", $fade.top)
            edge("Bottom", "arrow.down.to.line", $fade.bottom)
            edge("Leading", "arrow.left.to.line", $fade.leading)
            edge("Trailing", "arrow.right.to.line", $fade.trailing)
        }
    }

    private func edge(_ title: String, _ symbol: String, _ isOn: Binding<Bool>) -> some View {
        EdgeToggle(title: title, symbol: symbol, isOn: isOn)
    }
}

private struct EdgeToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(isHovered ? .primary : .secondary))
                .frame(width: 26, height: 26)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .trackingHover($isHovered)
        .help(isOn ? "Fade the \(title.lowercased()) edge: on" : "Fade the \(title.lowercased()) edge: off")
        .accessibilityLabel("Fade the \(title.lowercased()) edge")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        if isOn {
            return AnyShapeStyle(PlaygroundTheme.accent.opacity(isHovered ? 0.85 : 1))
        }
        return AnyShapeStyle(isHovered ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill)
    }
}

// MARK: - Behavior

/// `NookChromeBehavior.hoverBehavior`, applied with `replaceChromeBehavior(_:)`.
struct BehaviorPage: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        PlaygroundPageView(page: .behavior) {
            SectionCard(
                title: "Hover",
                isModified: model.settings.behavior != .init(),
                reset: { model.settings.behavior = .init() }
            ) {
                SwitchRow(
                    title: "Stay open while hovered",
                    isOn: $model.settings.behavior.hoverKeepsVisible,
                    help: "A request to hide the nook waits until the pointer leaves it."
                )
                SwitchRow(
                    title: "Hover haptics",
                    isOn: $model.settings.behavior.hoverHaptics,
                    help: "A tap on a Force Touch trackpad as the pointer enters and leaves the nook."
                )
            }
        }
    }
}
