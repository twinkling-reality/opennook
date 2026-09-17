// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// One value a proposal would change, in the words a person reads and with enough of the JSON kept
/// to put it back if they switch it off.
public struct AssistantChange: Identifiable, Sendable, Equatable {
    /// A value before or after the change, already shaped for display.
    public enum Value: Sendable, Equatable {
        case number(Double, AssistantField.Unit)
        case flag(Bool)
        case text(String)
        case color(PlaygroundColor)
        /// One of a fixed set, as its display name.
        case choice(String)
        /// No value: a theme color that follows the palette, an absent icon, or the far side of a
        /// companion being added or removed.
        case none

        /// How the value reads in a row: `420 pt`, `on`, `Liquid Glass`, `#1C1C1E`.
        ///
        /// Rounded for reading, unlike the JSON it came from, which is kept exact. Nobody wants to read
        /// that a damping fraction went to `0.8300000000000001`.
        public var text: String {
            switch self {
                case .number(let value, let unit):
                    switch unit {
                        case .fraction:
                            return (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
                        case .points, .seconds, .none:
                            return value.formatted(.number.precision(.fractionLength(0...2))) + unit.suffix
                    }
                case .flag(let value):
                    return value ? "on" : "off"
                case .text(let value):
                    return value.isEmpty ? "empty" : value
                case .color(let color):
                    return color.hex
                case .choice(let name):
                    return name
                case .none:
                    return "none"
            }
        }
    }

    /// What kind of change it is. A companion is added or removed whole, since a companion with no
    /// name or kind is not a companion.
    public enum Kind: Sendable, Equatable {
        case value
        case companionAdded
        case companionRemoved
    }

    /// Where to put the old value back, when this change is switched off.
    enum Location: Sendable, Equatable {
        case field(AssistantFieldPath)
        case companionField(id: String, key: String)
        /// A whole companion, and where it sat in the list it came from.
        case companion(id: String, index: Int)
        /// The order of the companions in both lists.
        case companionOrder
    }

    public let id: String
    public let group: AssistantFieldGroup
    public let kind: Kind
    /// The companion this change belongs to, when it belongs to one.
    public let subject: String?
    /// The field's short name, such as `Width`.
    public let title: String
    public let oldValue: Value
    public let newValue: Value

    let location: Location
    let oldJSON: AssistantJSON
    let newJSON: AssistantJSON

    /// The whole change on one line: `Width 520 -> 420 pt`, or `Add sleep-timer`.
    public var summary: String {
        switch kind {
            case .value:
                let old = oldValue.text
                let new = newValue.text
                // A number keeps its unit only once, at the end, the way a person would say it.
                if case .number(_, let unit) = newValue, case .number = oldValue, !unit.suffix.isEmpty {
                    let bare = old.replacingOccurrences(of: unit.suffix, with: "")
                    return "\(title) \(bare) -> \(new)"
                }
                return "\(title) \(old) -> \(new)"
            case .companionAdded:
                return "Add \(subject ?? title)"
            case .companionRemoved:
                return "Remove \(subject ?? title)"
        }
    }
}

/// What the model came back with: its short explanation, what it could not do, and the changes it
/// would make, each of which can be switched off before anything is applied.
public struct AssistantProposal: Sendable, Equatable {
    public var explanation: String
    /// What the settings cannot express, in the model's own words.
    public var notReproduced: [String]
    public var changes: [AssistantChange]
    /// The preset the base becomes with every change applied.
    public let proposed: PlaygroundPreset
    /// The preset the changes were measured against.
    public let base: PlaygroundPreset

    public var isEmpty: Bool { changes.isEmpty }

    /// The changes grouped as the controls window groups its pages, in the window's own order.
    public var groups: [(group: AssistantFieldGroup, changes: [AssistantChange])] {
        AssistantFieldGroup.allCases.compactMap { group in
            let changes = changes.filter { $0.group == group }
            return changes.isEmpty ? nil : (group, changes)
        }
    }

    /// The preset with only the changes whose ids are in `selection`.
    ///
    /// Built by taking the proposal and undoing what was left out, rather than by replaying what
    /// was kept, so a change that cannot be expressed on its own (a companion's field, when the
    /// whole list is what gets written) still comes out right.
    public func preset(applying selection: Set<String>) throws -> PlaygroundPreset {
        guard selection.count != changes.count else { return proposed }
        var json = try AssistantPatch.encoded(proposed)
        // Putting companions back comes last, and in the order they were taken out, so each lands
        // at the index it held in the original list.
        let dropped = changes.filter { !selection.contains($0.id) }
        for change in dropped where change.kind != .companionRemoved {
            json = Self.undo(change, in: json)
        }
        for change in dropped where change.kind == .companionRemoved {
            json = Self.undo(change, in: json)
        }
        do {
            return try PlaygroundPresetCoder.decode(json.data)
        } catch let error as PlaygroundPresetError {
            throw AssistantPatchError.invalidValue(detail: error.localizedDescription)
        }
    }

    private static func undo(_ change: AssistantChange, in json: AssistantJSON) -> AssistantJSON {
        switch change.location {
            case .field(let path):
                return setting(path.components[...], to: change.oldJSON, in: json)
            case .companionField(let id, let key):
                return updatingCompanions(in: json) { companions in
                    guard let index = companions.firstIndex(where: { $0["id"]?.stringValue == id }) else { return }
                    companions[index] = setting([.key(key)], to: change.oldJSON, in: companions[index])
                }
            case .companionOrder:
                let order = change.oldJSON.arrayValue?.compactMap(\.stringValue) ?? []
                return updatingCompanions(in: json) { companions in
                    companions = reordered(companions, as: order)
                }
            case .companion(let id, let index):
                return updatingCompanions(in: json) { companions in
                    switch change.kind {
                        case .companionAdded:
                            companions.removeAll { $0["id"]?.stringValue == id }
                        case .companionRemoved:
                            companions.insert(change.oldJSON, at: min(index, companions.count))
                        case .value:
                            break
                    }
                }
        }
    }

    /// `companions` with the ones named in `order` put back in that order, in the places those
    /// companions hold now. Companions `order` does not name keep their places.
    static func reordered(_ companions: [AssistantJSON], as order: [String]) -> [AssistantJSON] {
        let named = Set(order)
        let slots = companions.indices.filter { named.contains(companions[$0]["id"]?.stringValue ?? "") }
        var byID: [String: AssistantJSON] = [:]
        for index in slots {
            if let id = companions[index]["id"]?.stringValue { byID[id] = companions[index] }
        }
        let ordered = order.compactMap { byID[$0] }
        guard ordered.count == slots.count else { return companions }
        var result = companions
        for (slot, companion) in zip(slots, ordered) {
            result[slot] = companion
        }
        return result
    }

    private static func updatingCompanions(
        in json: AssistantJSON,
        _ change: (inout [AssistantJSON]) -> Void
    ) -> AssistantJSON {
        let path = AssistantFieldPath("settings.companions")
        var companions = value(at: path.components[...], in: json)?.arrayValue ?? []
        change(&companions)
        return setting(path.components[...], to: .array(companions), in: json)
    }

    /// `json` with the value at `components` replaced, creating objects on the way down when the
    /// path is not there yet.
    static func setting(
        _ components: ArraySlice<AssistantFieldPath.Component>,
        to newValue: AssistantJSON,
        in json: AssistantJSON
    ) -> AssistantJSON {
        guard case .key(let name)? = components.first else { return newValue }
        var members = json.members ?? []
        let rest = components.dropFirst()
        if let index = members.firstIndex(where: { $0.name == name }) {
            members[index].value = setting(rest, to: newValue, in: members[index].value)
        } else {
            let empty = AssistantJSON.object([AssistantJSON.Member]())
            members.append(AssistantJSON.Member(name, setting(rest, to: newValue, in: empty)))
        }
        return .object(members)
    }

    /// The value at `components`, when there is one.
    static func value(
        at components: ArraySlice<AssistantFieldPath.Component>,
        in json: AssistantJSON
    ) -> AssistantJSON? {
        guard let first = components.first else { return json }
        guard case .key(let name) = first, let child = json[name] else { return nil }
        return value(at: components.dropFirst(), in: child)
    }
}
