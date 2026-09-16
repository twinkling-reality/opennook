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
    /// A list replaces rather than merges, which is what makes `settings.companions` a single
    /// decision. Merging by position would let "add a sleep timer" silently rewrite the companion
    /// that happened to be first, and merging by id would need a patch format of its own. The
    /// field guide says so plainly, and the proposal still diffs companions by id, so a replaced
    /// list that keeps a companion untouched shows no rows for it.
    ///
    /// An explicit null is a value, not a deletion: it is how a theme color goes back to following
    /// the user's palette.
    static func merge(_ patch: AssistantJSON, onto base: AssistantJSON) -> AssistantJSON {
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

    // MARK: - Validating

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
