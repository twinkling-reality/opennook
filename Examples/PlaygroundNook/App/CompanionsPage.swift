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

/// `NookConfiguration.addCompanion` and the companion defaults: how every companion looks, the
/// companions themselves, and an editor for the selected one.
struct CompanionsPage: View {
    @ObservedObject var model: PlaygroundModel
    @State private var selectedID: String?
    @State private var editorTab = CompanionEditor.Tab.content
    @State private var isAdding = false

    private typealias Companion = PlaygroundSettings.Companion

    var body: some View {
        PlaygroundPageView(page: .companions) {
            CompanionDefaultsCard(defaults: $model.settings.companionDefaults)

            if companions.isEmpty {
                emptyState
            } else {
                SectionCard(
                    title: "Companions",
                    help: "Views that float beside the nook. Companions on the same side and alignment form a row, "
                        + "in this order."
                ) {
                    ForEach(companions) { companion in
                        CompanionListRow(
                            companion: companion,
                            isSelected: companion.id == selection?.id,
                            canMoveUp: companion.id != companions.first?.id,
                            canMoveDown: companion.id != companions.last?.id,
                            select: { selectedID = companion.id },
                            move: { move(companion.id, by: $0) },
                            duplicate: { duplicate(companion.id) },
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
                    otherIDs: Set(companions.map(\.id)).subtracting([selection.id]),
                    defaults: model.settings.companionDefaults
                )
                // A different companion starts with no item selected.
                .id(selection.id)
            }
        }
    }

    private var companions: [Companion] {
        model.settings.companions
    }

    /// The selected companion, or the first one when nothing valid is selected.
    private var selection: Companion? {
        companions.first { $0.id == selectedID } ?? companions.first
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No companions yet")
                .font(.system(size: 15, weight: .light))
            Text("Buttons, groups, and labels that float beside the nook.")
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
                canAddControls: !companions.contains(where: \.holdsChromeControls),
                add: { template in
                    isAdding = false
                    add(template)
                }
            )
        }
    }

    /// A binding that follows the companion by id, and moves the selection along when the id
    /// is edited. An edit that takes the lock or gear out of the companions puts it back in the
    /// top bar.
    private func binding(for id: String) -> Binding<Companion>? {
        guard let current = companions.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.settings.companions.first { $0.id == id } ?? current },
            set: { companion in
                var settings = model.settings
                guard let index = settings.companions.firstIndex(where: { $0.id == id }) else { return }
                let previous = settings.companions
                settings.companions[index] = companion
                settings.restoreChromeControls(heldBy: previous)
                model.settings = settings
                if companion.id != id {
                    selectedID = companion.id
                }
            }
        )
    }

    /// Nook controls move the lock and gear out of the top bar, as CompanionNook does; the
    /// companion stays up in Settings, since its gear is the way back out.
    private func add(_ template: Companion.Template) {
        var settings = model.settings
        var companion = Companion(id: "", template: template, accessibilityLabel: template.suggestedAccessibilityLabel)
        companion.id = PlaygroundSettings.uniqueID(for: companion, avoiding: Set(companions.map(\.id)))
        settings.companions.append(companion)
        if template == .controls {
            settings.topBar.showsKeepOpenButton = false
            settings.topBar.showsSettingsButton = false
        }
        model.settings = settings
        selectedID = companion.id
        editorTab = .content
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = companions.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard companions.indices.contains(destination) else { return }
        model.settings.companions.swapAt(index, destination)
    }

    private func duplicate(_ id: String) {
        guard let index = companions.firstIndex(where: { $0.id == id }) else { return }
        var copy = companions[index]
        copy.id = PlaygroundSettings.uniqueID(for: copy, avoiding: Set(companions.map(\.id)))
        model.settings.companions.insert(copy, at: index + 1)
        selectedID = copy.id
    }

    /// Removing the last companion that holds the lock or gear puts it back in the top bar, so
    /// it is never lost.
    private func remove(_ id: String) {
        guard let index = companions.firstIndex(where: { $0.id == id }) else { return }
        var settings = model.settings
        let previous = settings.companions
        settings.companions.remove(at: index)
        settings.restoreChromeControls(heldBy: previous)
        model.settings = settings
        if selectedID == id {
            let remaining = settings.companions
            selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }
}

// MARK: - Defaults

/// `NookConfiguration.companionSize`, `companionStyle`, and `companionPresence`.
private struct CompanionDefaultsCard: View {
    @Binding var defaults: PlaygroundSettings.CompanionDefaults

    private let fallback = PlaygroundSettings.CompanionDefaults()

    var body: some View {
        SectionCard(
            title: "Every Companion",
            help: "The size, look, and entrance every companion shares, so companions side by side match. "
                + "A companion can set its own on its Style tab.",
            isModified: defaults != fallback,
            reset: reset
        ) {
            SegmentedRow(
                title: "Size",
                selection: $defaults.size,
                choices: CompanionChoices.sizes,
                help: "32, 40, or 48 pt tall, with the controls inside sized to match."
            )
            SegmentedRow(
                title: "Appear",
                selection: $defaults.presence,
                choices: CompanionChoices.presences,
                help: "How companions come and go as the nook expands and collapses."
            )
            SliderRow(
                title: "Fade",
                value: fadeAmount,
                range: 0...1,
                step: 0.05,
                defaultValue: 0,
                format: .percent,
                help: "How much a companion's fill thins as it runs away from the nook."
            )
            SwitchRow(title: "Edge", isOn: $defaults.stroke, help: "A hairline around each companion.")
            SwitchRow(title: "Shadow", isOn: $defaults.shadow, help: "A soft shadow under each companion.")
            SegmentedRow(
                title: "Hover",
                selection: $defaults.hover,
                choices: CompanionChoices.hovers,
                help: "What a companion does while the pointer is over it."
            )
        }
    }

    private func reset() {
        defaults = fallback
    }

    /// The slider shows how much fades away; the setting stores how much is left.
    private var fadeAmount: Binding<Double> {
        Binding(
            get: { 1 - defaults.fade },
            set: { defaults.fade = 1 - $0 }
        )
    }
}

/// The choice lists the companion rows share. Main-actor bound, since only views read them.
@MainActor
private enum CompanionChoices {
    typealias Companion = PlaygroundSettings.Companion
    typealias Item = PlaygroundSettings.Item

    static let sizes = [Choice(Companion.Size.small, "Small"), Choice(.regular, "Regular"), Choice(.large, "Large")]
    static let presences = [
        Choice(Companion.Presence.fold, "Fold"), Choice(.fade, "Fade"), Choice(.slide, "Slide"), Choice(.pop, "Pop"),
    ]
    static let hovers = [
        Choice(Companion.Hover.none, "None"), Choice(.highlight, "Highlight"), Choice(.lift, "Lift"),
        Choice(.glow, "Glow"),
    ]
    static let alignments = [
        Choice(Companion.AnchorAlignment?.none, "Default"), Choice(.start, "Top"), Choice(.center, "Middle"),
        Choice(.end, "Bottom"),
    ]
    static let switches = [Choice(Bool?.none, "Default"), Choice(true, "On"), Choice(false, "Off")]
    static let itemTypes = [
        Choice(Item.Kind.button, "Button"), Choice(.label, "Label"), Choice(.keepOpen, "Lock"),
        Choice(.settings, "Gear"),
    ]
    static let fills = [
        Choice(Item.Fill.none, "None"), Choice(.subtle, "Subtle"), Choice(.color, "Color"), Choice(.chrome, "Chrome"),
    ]
    static let itemSizes = [Choice(Item.Size.control, "Control"), Choice(.surface, "Surface")]

    static func optional<Value: Hashable>(_ choices: [Choice<Value>]) -> [Choice<Value?>] {
        [Choice(Value?.none, "Default")] + choices.map { Choice(Optional($0.value), $0.title) }
    }
}

extension PlaygroundSettings.Item.Action {
    var title: String {
        switch self {
            case .none: "Nothing"
            case .status: "Post a status"
            case .rimGlow: "Toggle the rim glow"
            case .keepOpen: "Toggle keep open"
            case .settings: "Open Settings"
            case .collapse: "Collapse the nook"
        }
    }
}

extension PlaygroundSettings.Companion {
    /// A glyph for the companion in the list.
    var listSymbol: String {
        if holdsChromeControls { return "gearshape" }
        switch items.count {
            case 0: return "square.dashed"
            case 1: return items[0].type == .label ? "tag" : "circle"
            default: return "capsule"
        }
    }
}

// MARK: - Adding

/// The templates a companion can start from, each with a line on what it is.
private struct AddCompanionList: View {
    let canAddControls: Bool
    let add: (PlaygroundSettings.Companion.Template) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(PlaygroundSettings.Companion.Template.allCases, id: \.self) { template in
                let isEnabled = template != .controls || canAddControls
                Button {
                    add(template)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(template))
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(PlaygroundTheme.controlFill))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.title)
                                .font(PlaygroundTheme.body)
                            Text(isEnabled ? blurb(template) : "The lock and gear are already in a companion")
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
        .frame(width: 300)
    }

    private func symbol(_ template: PlaygroundSettings.Companion.Template) -> String {
        switch template {
            case .actions: "capsule"
            case .button: "circle"
            case .controls: "gearshape"
            case .chip: "tag"
            case .empty: "square.dashed"
        }
    }

    private func blurb(_ template: PlaygroundSettings.Companion.Template) -> String {
        switch template {
            case .actions: "A group of three buttons"
            case .button: "One round button"
            case .controls: "The lock and gear, out of the top bar"
            case .chip: "A short status label"
            case .empty: "Nothing yet; add items on its Content tab"
        }
    }
}

// MARK: - List

private struct CompanionListRow: View {
    let companion: PlaygroundSettings.Companion
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let move: (Int) -> Void
    let duplicate: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: companion.listSymbol)
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
                actions
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .modifier(HoverCircle(size: 26))
            .help("Move, duplicate, or remove")
            .accessibilityLabel("Actions for \(companion.id)")
        }
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Move Up") { move(-1) }
            .disabled(!canMoveUp)
        Button("Move Down") { move(1) }
            .disabled(!canMoveDown)
        Button("Duplicate", action: duplicate)
        Divider()
        Button("Remove", role: .destructive, action: remove)
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
        return "\(companion.contentSummary.prefix(1).uppercased() + companion.contentSummary.dropFirst()), "
            + "\(side), \(shown)"
    }
}

// MARK: - Editor

/// The selected companion's settings, a tab at a time.
struct CompanionEditor: View {
    enum Tab: Hashable {
        case content
        case placement
        case style
        case details
    }

    @Binding var companion: PlaygroundSettings.Companion
    @Binding var tab: Tab
    let otherIDs: Set<String>
    let defaults: PlaygroundSettings.CompanionDefaults
    @State private var selectedItem: Int?

    private typealias Companion = PlaygroundSettings.Companion
    private typealias Item = PlaygroundSettings.Item

    var body: some View {
        SectionCard(title: companion.id) {
            switch tab {
                case .content: contentRows
                case .placement: placementRows
                case .style: styleRows
                case .details: detailRows
            }
        } accessory: {
            PillPicker(
                title: "Editor",
                selection: $tab,
                choices: [
                    Choice(.content, "Content"), Choice(.placement, "Place"), Choice(.style, "Style"),
                    Choice(.details, "Details"),
                ]
            )
            .frame(width: 290)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentRows: some View {
        SegmentedRow(
            title: "Layout",
            selection: $companion.layout,
            choices: [Choice(.automatic, "Automatic"), Choice(.row, "Row"), Choice(.column, "Column")],
            help: "Automatic is a row below the nook and a column beside it."
        )
        addItemRow
        ForEach(Array(companion.items.enumerated()), id: \.offset) { index, item in
            CompanionItemRow(
                item: item,
                isSelected: index == selectedItem,
                canMoveUp: index > 0,
                canMoveDown: index < companion.items.count - 1,
                select: { selectedItem = selectedItem == index ? nil : index },
                move: { moveItem(at: index, by: $0) },
                duplicate: { duplicateItem(at: index) },
                remove: { removeItem(at: index) }
            )
        }
        if let index = selectedItem, companion.items.indices.contains(index) {
            itemRows(for: itemBinding(at: index))
        }
    }

    private var addItemRow: some View {
        ControlRow(
            title: companion.items.isEmpty ? "Nothing here yet" : "Items",
            help: "Buttons run an action, labels show text, and the lock and gear are the nook's own."
        ) {
            Menu {
                addItemButton("Button", symbol: "circle", Item(symbol: "star.fill", title: "Favorite"))
                addItemButton("Label", symbol: "tag", Item(type: .label, symbol: "sparkles", title: "New"))
                Divider()
                addItemButton("The Nook's Lock", symbol: "lock", Item(type: .keepOpen))
                addItemButton("The Nook's Gear", symbol: "gearshape", Item(type: .settings))
            } label: {
                Label("Add Item", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(PillButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(companion.items.count >= Companion.maximumItems)
            .help("Add an item to this companion")
        }
    }

    private func addItemButton(_ title: String, symbol: String, _ item: Item) -> some View {
        Button {
            companion.items.append(item)
            selectedItem = companion.items.count - 1
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    @ViewBuilder
    private func itemRows(for item: Binding<Item>) -> some View {
        SegmentedRow(
            title: "Type",
            selection: item.type,
            choices: CompanionChoices.itemTypes,
            help: "A glyph button, a label, or the nook's own lock or gear."
        )
        switch item.wrappedValue.type {
            case .button:
                SymbolRow(symbol: item.symbol, fallback: item.wrappedValue.action.defaultSymbol)
                OptionalTextRow(title: "Name", text: item.title, prompt: item.wrappedValue.action.defaultTitle)
                actionRow(item.action)
                OptionalColorRow(title: "Glyph", color: item.tint, help: "The glyph's color. Off follows the palette.")
                SegmentedRow(
                    title: "Fill",
                    selection: item.fill,
                    choices: CompanionChoices.fills,
                    help: "Behind the glyph: nothing, the palette's subtle fill, a color, or the nook's material."
                )
                if item.wrappedValue.fill == .color {
                    OptionalColorRow(title: "Fill color", color: item.fillColor, help: "Off uses the accent.")
                }
                if item.wrappedValue.fill != .none {
                    OptionalFadeRow(
                        title: "Fill fade",
                        fade: item.fade,
                        help: "How much the fill thins toward the bottom."
                    )
                }
                SegmentedRow(
                    title: "Size",
                    selection: item.size,
                    choices: CompanionChoices.itemSizes,
                    help: "Surface makes the button as tall as the companion, a surface of its own. "
                        + "A companion of only those draws no surface around them."
                )
            case .label:
                SymbolRow(symbol: item.symbol, fallback: nil)
                OptionalTextRow(title: "Text", text: item.title, prompt: "None")
                OptionalColorRow(title: "Icon", color: item.tint, help: "The icon's color. Off uses the accent.")
            case .keepOpen, .settings:
                EmptyView()
        }
    }

    private func actionRow(_ action: Binding<Item.Action>) -> some View {
        ControlRow(title: "Action", help: "What the button does here. The Swift export leaves a place for yours.") {
            Menu {
                ForEach(Item.Action.allCases, id: \.self) { choice in
                    Button(choice.title) { action.wrappedValue = choice }
                }
            } label: {
                Text(action.wrappedValue.title)
                    .font(PlaygroundTheme.body)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func itemBinding(at index: Int) -> Binding<Item> {
        Binding(
            get: { companion.items.indices.contains(index) ? companion.items[index] : Item() },
            set: { item in
                guard companion.items.indices.contains(index) else { return }
                companion.items[index] = item
            }
        )
    }

    private func moveItem(at index: Int, by offset: Int) {
        let destination = index + offset
        guard companion.items.indices.contains(index), companion.items.indices.contains(destination) else { return }
        companion.items.swapAt(index, destination)
        selectedItem = destination
    }

    private func duplicateItem(at index: Int) {
        guard companion.items.indices.contains(index), companion.items.count < Companion.maximumItems else { return }
        companion.items.insert(companion.items[index], at: index + 1)
        selectedItem = index + 1
    }

    private func removeItem(at index: Int) {
        guard companion.items.indices.contains(index) else { return }
        companion.items.remove(at: index)
        selectedItem = nil
    }

    // MARK: Placement

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
            help: "Where it sits along that edge. Companions with the same side and alignment share a row."
        )
        SliderRow(
            title: "Spacing",
            value: $companion.spacing,
            range: 0...40,
            defaultValue: Double(NookCompanionSurface.defaultSpacing),
            help: "The gap to the nook, and to the companion before it unless Gap is set."
        )
        if companion.anchor == .below {
            OptionalSliderRow(
                title: "Gap",
                value: $companion.gap,
                range: 0...40,
                fallback: companion.spacing,
                help: "The gap to the companion before it, without moving this one further from the nook."
            )
        }
        SegmentedRow(
            title: "In its row",
            selection: $companion.rowAlignment,
            choices: CompanionChoices.alignments,
            help: "Where it sits beside a taller companion in its row."
        )
        SegmentedRow(
            title: "Shown",
            selection: $companion.visibility,
            choices: [Choice(.expanded, "Expanded"), Choice(.compact, "Collapsed"), Choice(.both, "Always")],
            help: "Whether it shows with the nook expanded, beside the collapsed pill, or both."
        )
    }

    // MARK: Style

    @ViewBuilder
    private var styleRows: some View {
        if companion.itemsAreSurfaces {
            Text("Every item is a surface of its own, so the companion draws none. Style the items on the Content tab.")
                .font(PlaygroundTheme.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            surfaceRows
        }
        SegmentedRow(
            title: "Size",
            selection: $companion.size,
            choices: CompanionChoices.optional(CompanionChoices.sizes),
            help: "Default follows Every Companion."
        )
        SegmentedRow(
            title: "Appear",
            selection: $companion.presence,
            choices: CompanionChoices.optional(CompanionChoices.presences),
            help: "How it comes and goes. Default follows Every Companion."
        )
        OptionalColorRow(title: "Accent", color: $companion.accent, help: "Its own accent. Off uses the theme's.")
    }

    /// What the companion paints around its items.
    @ViewBuilder
    private var surfaceRows: some View {
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
            help: "Chrome matches the nook. None paints nothing behind the items."
        )
        if companion.backdrop == .solid || companion.backdrop == .glass {
            ControlRow(title: companion.backdrop == .solid ? "Fill" : "Tint") {
                ColorSwatch(title: "Backdrop color", color: backdropColor, supportsOpacity: true)
            }
        }
        OptionalFadeRow(
            title: "Fade",
            fade: $companion.fade,
            inherited: defaults.fade,
            help: "How much the fill thins away from the nook. Default follows Every Companion."
        )
        SegmentedRow(
            title: "Edge",
            selection: $companion.stroke,
            choices: CompanionChoices.switches,
            help: "A hairline around it. Default follows Every Companion."
        )
        SegmentedRow(
            title: "Shadow",
            selection: $companion.shadow,
            choices: CompanionChoices.switches,
            help: "A soft shadow around it. Default follows Every Companion."
        )
        SegmentedRow(
            title: "Hover",
            selection: $companion.hover,
            choices: CompanionChoices.optional(CompanionChoices.hovers),
            help: "What it does under the pointer. Default follows Every Companion."
        )
    }

    // MARK: Details

    @ViewBuilder
    private var detailRows: some View {
        CompanionIDField(id: $companion.id, otherIDs: otherIDs)
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

// MARK: - Item rows

private struct CompanionItemRow: View {
    let item: PlaygroundSettings.Item
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let move: (Int) -> Void
    let duplicate: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(item.tint.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(PlaygroundTheme.controlFill))
                    Text(item.displayTitle)
                        .font(PlaygroundTheme.body)
                        .lineLimit(1)
                    Text(kind)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowButtonStyle(isSelected: isSelected))
            .accessibilityLabel("\(item.displayTitle), \(kind)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Menu {
                Button("Move Up") { move(-1) }
                    .disabled(!canMoveUp)
                Button("Move Down") { move(1) }
                    .disabled(!canMoveDown)
                Button("Duplicate", action: duplicate)
                Divider()
                Button("Remove", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .modifier(HoverCircle(size: 26))
            .help("Move, duplicate, or remove")
            .accessibilityLabel("Actions for \(item.displayTitle)")
        }
    }

    private var symbol: String {
        guard let name = item.displaySymbol, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        else { return item.type == .label ? "textformat" : "questionmark.circle" }
        return name
    }

    private var kind: String {
        switch item.type {
            case .button: item.action.title
            case .label: "Label"
            case .keepOpen: "The nook's lock"
            case .settings: "The nook's gear"
        }
    }
}

/// An SF Symbol name with a preview and a few suggestions.
private struct SymbolRow: View {
    @Binding var symbol: String?
    /// What shows while no name is set.
    let fallback: String?

    private static let suggestions = [
        "play.fill", "pause.fill", "backward.fill", "forward.fill", "mic.fill", "video.fill", "phone.down.fill",
        "hand.raised.fill", "star.fill", "heart.fill", "bell.fill", "timer", "square.and.arrow.up", "sparkles",
    ]

    var body: some View {
        ControlRow(title: "Symbol", help: "Any SF Symbol name.", isModified: symbol != nil) {
            HStack(spacing: 8) {
                TextField("Symbol", text: name, prompt: Text(fallback ?? "None"))
                    .labelsHidden()
                    .playgroundField()
                preview
                Menu {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button {
                            symbol = suggestion
                        } label: {
                            Label(suggestion, systemImage: suggestion)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .modifier(HoverCircle(size: 26))
                .help("Suggested symbols")
                .accessibilityLabel("Suggested symbols")
            }
        } reset: {
            symbol = nil
        }
    }

    private var name: Binding<String> {
        Binding(
            get: { symbol ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                symbol = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let name = symbol ?? fallback {
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                Image(systemName: name)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("No SF Symbol has this name, so a question mark shows instead")
            }
        } else {
            Image(systemName: "textformat")
                .foregroundStyle(.tertiary)
        }
    }
}

/// Text that is `nil` while empty.
private struct OptionalTextRow: View {
    let title: String
    @Binding var text: String?
    var prompt = ""

    var body: some View {
        TextRow(
            title: title,
            text: Binding(
                get: { text ?? "" },
                set: { text = $0.isEmpty ? nil : $0 }
            ),
            prompt: prompt
        )
    }
}

/// A color that is `nil` until picked, with a switch to turn it off again.
private struct OptionalColorRow: View {
    let title: String
    @Binding var color: PlaygroundColor?
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help, isModified: color != nil) {
            HStack(spacing: 10) {
                if color != nil {
                    ColorSwatch(title: title, color: swatch, supportsOpacity: true)
                }
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        } reset: {
            color = nil
        }
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { color != nil },
            set: { color = $0 ? PlaygroundColor(red: 1, green: 1, blue: 1) : nil }
        )
    }

    private var swatch: Binding<Color> {
        Binding(
            get: { color?.color ?? .white },
            set: { color = PlaygroundColor($0) }
        )
    }
}

/// A length that is `nil` until set, falling back to another value.
private struct OptionalSliderRow: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let fallback: Double
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help, isModified: value != nil) {
            HStack(spacing: 10) {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                Slider(value: current, in: range)
                    .controlSize(.small)
                    .disabled(value == nil)
                    .accessibilityLabel(title)
                Text(ValueFormat.points.text(value ?? fallback, step: 1))
                    .font(PlaygroundTheme.caption.monospacedDigit())
                    .foregroundStyle(value == nil ? .tertiary : .secondary)
                    .frame(width: RowLayout.valueWidth, alignment: .trailing)
            }
        } reset: {
            value = nil
        }
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { value != nil },
            set: { value = $0 ? fallback : nil }
        )
    }

    private var current: Binding<Double> {
        Binding(
            get: { value ?? fallback },
            set: { value = $0.rounded() }
        )
    }
}

/// A fade shown as how much fades away: stored as the strength left at the far side, `nil` for
/// the inherited value.
private struct OptionalFadeRow: View {
    let title: String
    @Binding var fade: Double?
    /// What `nil` means: the defaults' fade for a companion, no fade for a button.
    var inherited: Double = 1
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help, isModified: fade != nil) {
            HStack(spacing: 10) {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                Slider(value: amount, in: 0...1)
                    .controlSize(.small)
                    .disabled(fade == nil)
                    .accessibilityLabel(title)
                Text(ValueFormat.percent.text(1 - (fade ?? inherited), step: 0.05))
                    .font(PlaygroundTheme.caption.monospacedDigit())
                    .foregroundStyle(fade == nil ? .tertiary : .secondary)
                    .frame(width: RowLayout.valueWidth, alignment: .trailing)
            }
        } reset: {
            fade = nil
        }
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { fade != nil },
            set: { fade = $0 ? min(inherited, 0.4) : nil }
        )
    }

    private var amount: Binding<Double> {
        Binding(
            get: { 1 - (fade ?? inherited) },
            set: { fade = 1 - ($0 * 20).rounded() / 20 }
        )
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
