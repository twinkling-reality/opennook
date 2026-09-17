// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Why a patch could not be turned into a preset. Each case carries the JSON path of the value at
/// fault, in the same dotted form the field guide uses, so ``repairRequest`` can hand the model a
/// correction it can act on rather than a restatement of the rules.
public enum AssistantPatchError: Error, Equatable, LocalizedError {
    /// The patch is not a JSON object.
    case notAnObject
    /// A field the playground does not have. The model invented it, or guessed at a name.
    case unknownField(path: String)
    /// A field that holds a value was given an object or a list, or the other way round.
    case wrongShape(path: String, expected: String)
    /// The merged preset would not decode. The detail comes from ``PlaygroundPresetCoder`` and
    /// already names the path.
    case invalidValue(detail: String)
    /// A companion the patch adds does not say what it holds.
    case missingItems(companion: String)

    public var errorDescription: String? {
        switch self {
            case .notAnObject:
                "The patch is not a JSON object."
            case .unknownField(let path):
                "There is no setting called \(path)."
            case .wrongShape(let path, let expected):
                "\(path) should be \(expected)."
            case .invalidValue(let detail):
                "The patch has a value the playground cannot use: \(detail)."
            case .missingItems(let companion):
                "The new companion \(companion) has no items."
        }
    }

    /// What to send back to the model for its one repair round. It states the mistake and the fix
    /// in the vocabulary of the field guide, and nothing else.
    public var repairRequest: String {
        switch self {
            case .notAnObject:
                "Your answer was not a JSON object. Answer with one JSON object and nothing else."
            case .unknownField(let path):
                "There is no setting called \(path). Remove it, or use the closest name from the "
                    + "field list. Answer with the corrected JSON object and nothing else."
            case .wrongShape(let path, let expected):
                "\(path) should be \(expected). Answer with the corrected JSON object and nothing else."
            case .invalidValue(let detail):
                "The patch could not be read: \(detail). Answer with the corrected JSON object and "
                    + "nothing else."
            case .missingItems(let companion):
                "The new companion \(companion) needs its items: list what it holds in its items. Answer "
                    + "with the corrected JSON object and nothing else."
        }
    }
}

/// Merges a model's patch onto the preset it was asked about.
///
/// The patch is checked against ``AssistantSettingsCatalog`` before anything is merged, so a made
/// up field name is reported as itself rather than being silently dropped by the lenient preset
/// decoder. Only then is the merged JSON handed to ``PlaygroundPresetCoder``, which decodes and
/// normalizes it, meaning a value out of range is clamped exactly as an imported preset would be
/// and never reaches the chrome unchecked.
///
/// Pure: no files, no network, no shared state.
public enum AssistantPatch {
    /// `preset` with the patch applied.
    public static func apply(_ patch: AssistantJSON, to preset: PlaygroundPreset) throws -> PlaygroundPreset {
        guard case .object = patch else { throw AssistantPatchError.notAnObject }
        try validate(patch)
        let current = try encoded(preset)
        try requireItems(ofCompanionsAddedBy: patch, to: current)
        let merged = merge(patch, onto: current)
        do {
            return try PlaygroundPresetCoder.decode(merged.data)
        } catch let error as PlaygroundPresetError {
            switch error {
                case .invalidValue(let detail):
                    throw AssistantPatchError.invalidValue(detail: detail)
                default:
                    throw AssistantPatchError.invalidValue(detail: error.localizedDescription)
            }
        }
    }

    /// The preset as the JSON a patch is merged onto.
    static func encoded(_ preset: PlaygroundPreset) throws -> AssistantJSON {
        let data = try PlaygroundPresetCoder.encode(preset)
        guard let json = AssistantJSON(parsing: data) else {
            throw AssistantPatchError.invalidValue(detail: "the current preset could not be read back")
        }
        return json
    }

    // MARK: - Merging

    /// `patch` laid over `base`: objects merge key by key, and everything else replaces.
    ///
    /// A list is the patch's own: which elements it holds, and in what order, is what the patch
    /// says, which is what makes `settings.companions` a single decision. A list whose elements
    /// all carry an `id` also merges each element onto the base element with the same id, so a
    /// patch that lists a companion to move it keeps the items and style it does not mention;
    /// merging by position would let "add a sleep timer" rewrite whichever companion happened to
    /// be first. A list without ids, such as a companion's items, replaces outright. The field
    /// guide says both plainly, and the proposal diffs companions by id, so a companion that comes
    /// through unchanged shows no rows.
    ///
    /// An explicit null is a value, not a deletion: it is how a theme color goes back to following
    /// the user's palette.
    static func merge(_ patch: AssistantJSON, onto base: AssistantJSON) -> AssistantJSON {
        if case .array(let patchElements) = patch, case .array(let baseElements) = base {
            return .array(mergingByID(patchElements, onto: baseElements))
        }
        guard case .object(let patchMembers) = patch, case .object(let baseMembers) = base else {
            return patch
        }
        var members = baseMembers
        for patchMember in patchMembers {
            if let index = members.firstIndex(where: { $0.name == patchMember.name }) {
                members[index].value = merge(patchMember.value, onto: members[index].value)
            } else {
                members.append(patchMember)
            }
        }
        return .object(members)
    }

    /// `patch`'s elements, each merged onto the element of `base` with the same `id`. A list
    /// whose elements do not all have one is returned as it is.
    private static func mergingByID(_ patch: [AssistantJSON], onto base: [AssistantJSON]) -> [AssistantJSON] {
        let ids = patch.map { $0["id"]?.stringValue }
        guard !patch.isEmpty, ids.allSatisfy({ $0 != nil }) else { return patch }
        return zip(patch, ids).map { element, id in
            guard let original = base.first(where: { $0["id"]?.stringValue == id }) else { return element }
            return merge(element, onto: original)
        }
    }

    // MARK: - Validating

    /// A companion the patch adds must list its items. Without them the preset decoder would
    /// fall back to the content an older preset's missing `kind` means, and the proposal would
    /// show buttons nobody asked for.
    static func requireItems(ofCompanionsAddedBy patch: AssistantJSON, to base: AssistantJSON) throws {
        let path = AssistantFieldPath("settings.companions").components[...]
        guard let listed = AssistantProposal.value(at: path, in: patch)?.arrayValue else { return }
        let existing = Set(
            (AssistantProposal.value(at: path, in: base)?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        )
        for companion in listed {
            guard let id = companion["id"]?.stringValue, !existing.contains(id), companion["items"] == nil else {
                continue
            }
            throw AssistantPatchError.missingItems(companion: id)
        }
    }

    /// Checks every path in the patch against the catalog before a merge, so the error names the
    /// field the model got wrong.
    static func validate(_ patch: AssistantJSON) throws {
        try validate(patch, at: AssistantFieldPath(components: []))
    }

    private static func validate(_ json: AssistantJSON, at path: AssistantFieldPath) throws {
        let index = AssistantPatchIndex.shared

        if index.isLeaf(path) {
            switch json {
                case .object, .array:
                    throw AssistantPatchError.wrongShape(path: path.text, expected: "a single value")
                default:
                    return
            }
        }

        if index.isList(path) {
            guard case .array(let elements) = json else {
                throw AssistantPatchError.wrongShape(path: path.text, expected: "a list")
            }
            let elementPath = AssistantFieldPath(components: path.components + [.eachElement])
            for element in elements {
                guard case .object = element else {
                    throw AssistantPatchError.wrongShape(path: elementPath.text, expected: "an object")
                }
                try validate(element, at: elementPath)
            }
            return
        }

        guard case .object(let members) = json else {
            throw AssistantPatchError.wrongShape(path: path.text, expected: "an object")
        }
        for member in members {
            let child = AssistantFieldPath(components: path.components + [.key(member.name)])
            guard index.isKnown(child) else {
                throw AssistantPatchError.unknownField(path: child.text)
            }
            try validate(member.value, at: child)
        }
    }
}

/// Which paths the catalog knows, and which of them hold a value, are a list, or are neither.
///
/// Built once from ``AssistantSettingsCatalog`` rather than searched each time, because validating
/// a patch asks about every path in it and a proposal asks again for every row.
struct AssistantPatchIndex: Sendable {
    static let shared = AssistantPatchIndex()

    private let leaves: Set<String>
    private let lists: Set<String>
    private let containers: Set<String>

    init() {
        var leaves = Set<String>()
        var lists = Set<String>()
        var containers = Set<String>()
        for field in AssistantSettingsCatalog.fields {
            leaves.insert(field.path.text)
            var prefix: [AssistantFieldPath.Component] = []
            for component in field.path.components.dropLast() {
                if case .eachElement = component {
                    lists.insert(AssistantFieldPath(components: prefix).text)
                }
                prefix.append(component)
                containers.insert(AssistantFieldPath(components: prefix).text)
            }
        }
        self.leaves = leaves
        self.lists = lists
        self.containers = containers
    }

    func isLeaf(_ path: AssistantFieldPath) -> Bool {
        leaves.contains(path.text)
    }

    func isList(_ path: AssistantFieldPath) -> Bool {
        lists.contains(path.text)
    }

    /// Whether the catalog has this path at all, as a value or as something on the way to one.
    func isKnown(_ path: AssistantFieldPath) -> Bool {
        leaves.contains(path.text) || containers.contains(path.text)
    }
}
