// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Works out what changed between two presets, in the vocabulary of the catalog.
///
/// The diff is driven by ``AssistantSettingsCatalog`` rather than by walking the JSON, so a value
/// the assistant is not allowed to touch can never show up as a row, and every row that does show
/// up has a title, a unit, and a group to sit under. Companions are matched by name, so replacing
/// the whole list to add one shows a single "Add sleep-timer" row rather than a rewrite of every
/// companion that happened to move down the list.
///
/// Pure, and independent of the model: the same code diffs a preset a person imported.
public enum AssistantDiff {
    /// Every change from `base` to `proposed`, in catalog order, with companions last within their
    /// group.
    public static func changes(from base: PlaygroundPreset, to proposed: PlaygroundPreset) throws -> [AssistantChange] {
        let baseJSON = try AssistantPatch.encoded(base)
        let proposedJSON = try AssistantPatch.encoded(proposed)
        var changes = fieldChanges(from: baseJSON, to: proposedJSON)
        changes += companionChanges(from: baseJSON, to: proposedJSON)
        return changes
    }

    /// A proposal from a model's answer: the patch merged onto `base`, then diffed against it.
    ///
    /// A patch that takes the lock or gear out of the companions also puts it back in the top bar,
    /// so a proposal can never leave the nook without them; the rows show it like any other change.
    public static func proposal(
        base: PlaygroundPreset,
        patch: AssistantJSON,
        explanation: String,
        notReproduced: [String]
    ) throws -> AssistantProposal {
        var proposed = try AssistantPatch.apply(patch, to: base)
        proposed.settings.restoreChromeControls(heldBy: base.settings.companions)
        return AssistantProposal(
            explanation: explanation,
            notReproduced: notReproduced,
            changes: try changes(from: base, to: proposed),
            proposed: proposed,
            base: base
        )
    }

    // MARK: - Plain fields

    private static func fieldChanges(from base: AssistantJSON, to proposed: AssistantJSON) -> [AssistantChange] {
        var changes: [AssistantChange] = []
        for field in AssistantSettingsCatalog.fields {
            // Companions are a list, matched by name below rather than compared position by
            // position.
            guard !field.path.components.contains(.eachElement) else { continue }
            let oldJSON = AssistantProposal.value(at: field.path.components[...], in: base) ?? .null
            let newJSON = AssistantProposal.value(at: field.path.components[...], in: proposed) ?? .null
            guard oldJSON != newJSON else { continue }
            changes.append(
                AssistantChange(
                    id: field.path.text,
                    group: field.group,
                    kind: .value,
                    subject: nil,
                    title: field.title,
                    oldValue: value(oldJSON, as: field),
                    newValue: value(newJSON, as: field),
                    location: .field(field.path),
                    oldJSON: oldJSON,
                    newJSON: newJSON
                )
            )
        }
        return changes
    }

    // MARK: - Companions

    private static func companionChanges(from base: AssistantJSON, to proposed: AssistantJSON) -> [AssistantChange] {
        let path = AssistantFieldPath("settings.companions").components[...]
        let baseList = AssistantProposal.value(at: path, in: base)?.arrayValue ?? []
        let proposedList = AssistantProposal.value(at: path, in: proposed)?.arrayValue ?? []
        let baseByID = identified(baseList)
        let proposedByID = identified(proposedList)

        var changes: [AssistantChange] = []

        // Removed first, then changed, then added, so a proposal reads as a list that shrinks
        // before it grows rather than jumping about.
        for (index, companion) in baseList.enumerated() {
            guard let id = companion["id"]?.stringValue, proposedByID[id] == nil else { continue }
            changes.append(
                AssistantChange(
                    id: "settings.companions[\(id)].removed",
                    group: .companions,
                    kind: .companionRemoved,
                    subject: id,
                    title: id,
                    oldValue: .text(describe(companion)),
                    newValue: .none,
                    location: .companion(id: id, index: index),
                    oldJSON: companion,
                    newJSON: .null
                )
            )
        }

        for field in companionFields {
            guard case .key(let key)? = field.path.components.last else { continue }
            for (id, companion) in proposedByID {
                guard let original = baseByID[id] else { continue }
                let oldJSON = original[key] ?? field.defaultValue
                let newJSON = companion[key] ?? field.defaultValue
                guard oldJSON != newJSON else { continue }
                changes.append(
                    AssistantChange(
                        id: "settings.companions[\(id)].\(key)",
                        group: .companions,
                        kind: .value,
                        subject: id,
                        title: field.title,
                        oldValue: value(oldJSON, as: field),
                        newValue: value(newJSON, as: field),
                        location: .companionField(id: id, key: key),
                        oldJSON: oldJSON,
                        newJSON: newJSON
                    )
                )
            }
        }

        // A companion's items are one decision, like the list of companions: a row says what the
        // content was and what it becomes, and switching the row off puts the old items back.
        for (id, companion) in proposedByID {
            guard let original = baseByID[id] else { continue }
            let oldJSON = original["items"] ?? .array([])
            let newJSON = companion["items"] ?? .array([])
            guard oldJSON != newJSON else { continue }
            changes.append(
                AssistantChange(
                    id: "settings.companions[\(id)].items",
                    group: .companions,
                    kind: .value,
                    subject: id,
                    title: "Content",
                    oldValue: .text(itemTitles(oldJSON)),
                    newValue: .text(itemTitles(newJSON)),
                    location: .companionField(id: id, key: "items"),
                    oldJSON: oldJSON,
                    newJSON: newJSON
                )
            )
        }

        // A new order for the companions that stay is one decision of its own. Without a row it
        // would go unseen, and a proposal that only reorders would look empty.
        let baseOrder = ids(of: baseList).filter { proposedByID[$0] != nil }
        let proposedOrder = ids(of: proposedList).filter { baseByID[$0] != nil }
        if baseOrder != proposedOrder {
            changes.append(
                AssistantChange(
                    id: "settings.companions.order",
                    group: .companions,
                    kind: .value,
                    subject: nil,
                    title: "Order",
                    oldValue: .text(baseOrder.joined(separator: ", ")),
                    newValue: .text(proposedOrder.joined(separator: ", ")),
                    location: .companionOrder,
                    oldJSON: .array(baseOrder.map { .string($0) }),
                    newJSON: .array(proposedOrder.map { .string($0) })
                )
            )
        }

        for (index, companion) in proposedList.enumerated() {
            guard let id = companion["id"]?.stringValue, baseByID[id] == nil else { continue }
            changes.append(
                AssistantChange(
                    id: "settings.companions[\(id)].added",
                    group: .companions,
                    kind: .companionAdded,
                    subject: id,
                    title: id,
                    oldValue: .none,
                    newValue: .text(describe(companion)),
                    location: .companion(id: id, index: index),
                    oldJSON: .null,
                    newJSON: companion
                )
            )
        }

        // Changed companions come out of a dictionary, so they are sorted to keep the order of a
        // proposal stable between runs.
        let ordering = ["removed": 0, "changed": 1, "added": 2]
        return changes.sorted { lhs, rhs in
            let lhsRank = ordering[rank(of: lhs)] ?? 1
            let rhsRank = ordering[rank(of: rhs)] ?? 1
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.id < rhs.id
        }
    }

    private static func rank(of change: AssistantChange) -> String {
        switch change.kind {
            case .companionRemoved: "removed"
            case .companionAdded: "added"
            case .value: "changed"
        }
    }

    private static func ids(of companions: [AssistantJSON]) -> [String] {
        companions.compactMap { $0["id"]?.stringValue }
    }

    private static func identified(_ companions: [AssistantJSON]) -> [String: AssistantJSON] {
        var byID: [String: AssistantJSON] = [:]
        for companion in companions {
            if let id = companion["id"]?.stringValue {
                byID[id] = companion
            }
        }
        return byID
    }

    /// The catalog fields a companion holds directly, one row each. Its items are compared as a
    /// whole instead, since a list has no per-field rows.
    private static var companionFields: [AssistantField] {
        AssistantSettingsCatalog.fields(in: .companions).filter { field in
            let components = field.path.components
            return components.count == 4 && components.dropLast().last == .eachElement
        }
    }

    /// A companion in a few words, for the row that adds or removes it: `3 buttons, trailing`.
    private static func describe(_ companion: AssistantJSON) -> String {
        var parts = [PlaygroundSettings.Item.summary(of: items(in: companion["items"] ?? .array([])))]
        if let anchor = companion["anchor"]?.stringValue {
            parts.append(AssistantWording.choiceTitle(anchor).lowercased())
        }
        return parts.joined(separator: ", ")
    }

    /// Items as their names, for a content row: `Previous, Play, Next`.
    private static func itemTitles(_ json: AssistantJSON) -> String {
        PlaygroundSettings.Item.titles(of: items(in: json))
    }

    /// The items a JSON list holds, skipping any that do not decode.
    private static func items(in json: AssistantJSON) -> [PlaygroundSettings.Item] {
        guard let elements = json.arrayValue else { return [] }
        return elements.compactMap { element in
            try? JSONDecoder().decode(PlaygroundSettings.Item.self, from: element.data)
        }
    }

    // MARK: - Values

    /// A raw JSON value as the kind of value its field holds, so a row can show a swatch for a
    /// color and a percentage for a fraction.
    static func value(_ json: AssistantJSON, as field: AssistantField) -> AssistantChange.Value {
        if case .null = json { return .none }
        switch field.kind {
            case .number(_, _, let unit):
                guard case .number(let number) = json else { return .none }
                return .number(number, unit)
            case .flag:
                guard case .bool(let flag) = json else { return .none }
                return .flag(flag)
            case .text:
                guard let text = json.stringValue else { return .none }
                return .text(text)
            case .color:
                guard let hex = json.stringValue, let color = PlaygroundColor(hex: hex) else { return .none }
                return .color(color)
            case .choice:
                guard let name = json.stringValue else { return .none }
                return .choice(AssistantWording.choiceTitle(name))
        }
    }
}
