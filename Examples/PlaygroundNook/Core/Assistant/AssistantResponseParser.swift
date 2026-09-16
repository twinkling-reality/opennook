// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The three parts of a well-formed answer.
public struct AssistantAnswer: Sendable, Equatable {
    public var explanation: String
    public var notReproduced: [String]
    public var patch: AssistantJSON

    public init(explanation: String, notReproduced: [String], patch: AssistantJSON) {
        self.explanation = explanation
        self.notReproduced = notReproduced
        self.patch = patch
    }
}

/// Why an answer could not be read. Like ``AssistantPatchError``, every case knows how to ask the
/// model for a fix, since the repair round is automatic and only happens once.
public enum AssistantResponseError: Error, Equatable, LocalizedError {
    /// Nothing that looked like a JSON object was in the answer.
    case noJSON(answer: String)
    /// A JSON object arrived but could not be parsed.
    case malformedJSON
    case missingKey(String)
    case wrongType(key: String, expected: String)

    public var errorDescription: String? {
        switch self {
            case .noJSON:
                "The model did not answer with JSON."
            case .malformedJSON:
                "The model's JSON was incomplete."
            case .missingKey(let key):
                "The model's answer has no \(key)."
            case .wrongType(let key, let expected):
                "The model's \(key) should be \(expected)."
        }
    }

    public var repairRequest: String {
        switch self {
            case .noJSON:
                "That was not JSON. Answer with one JSON object holding explanation, notReproduced, "
                    + "and patch, and nothing else."
            case .malformedJSON:
                "That JSON was incomplete. Answer with the whole JSON object again, and nothing else."
            case .missingKey(let key):
                "Your answer has no \(key). Answer with the whole JSON object again, including \(key), "
                    + "and nothing else."
            case .wrongType(let key, let expected):
                "Your \(key) should be \(expected). Answer with the corrected JSON object and nothing else."
        }
    }
}

/// Reads a model's answer into an ``AssistantAnswer``.
///
/// Lenient about what surrounds the JSON and strict about the JSON itself. A command line tool wraps
/// its answer in its own chatter, and a chat window pasted through the clipboard path arrives inside
/// a code fence, so the object is found rather than assumed to be the whole text. What is inside it
/// then has to be exactly right, because a value that is quietly coerced is a change nobody asked
/// for.
public enum AssistantResponseParser {
    public static func parse(_ raw: String) throws -> AssistantAnswer {
        guard let object = outermostObject(in: raw) else {
            throw AssistantResponseError.noJSON(answer: raw)
        }
        guard let json = AssistantJSON(parsing: object), case .object = json else {
            throw AssistantResponseError.malformedJSON
        }

        let explanationKey = AssistantSchema.ResponseKey.explanation.rawValue
        guard let explanationValue = json[explanationKey] else {
            throw AssistantResponseError.missingKey(explanationKey)
        }
        guard let explanation = explanationValue.stringValue else {
            throw AssistantResponseError.wrongType(key: explanationKey, expected: "a string")
        }

        let notReproducedKey = AssistantSchema.ResponseKey.notReproduced.rawValue
        var notReproduced: [String] = []
        if let value = json[notReproducedKey] {
            // A model that has nothing to report sometimes writes null rather than an empty list.
            // That is the same thing, so it is read rather than sent back for repair.
            if case .null = value {
                notReproduced = []
            } else if let items = value.arrayValue {
                notReproduced = try items.map { item in
                    guard let text = item.stringValue else {
                        throw AssistantResponseError.wrongType(key: notReproducedKey, expected: "a list of strings")
                    }
                    return text
                }
            } else {
                throw AssistantResponseError.wrongType(key: notReproducedKey, expected: "a list of strings")
            }
        }

        let patchKey = AssistantSchema.ResponseKey.patch.rawValue
        guard let patchValue = json[patchKey] else {
            throw AssistantResponseError.missingKey(patchKey)
        }
        guard case .object = patchValue else {
            throw AssistantResponseError.wrongType(key: patchKey, expected: "an object")
        }

        return AssistantAnswer(
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            notReproduced: notReproduced.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            patch: patchValue
        )
    }

    /// The outermost `{ ... }` in `text`, brace matched so a nested object cannot end it early and
    /// a brace inside a string cannot either.
    static func outermostObject(in text: String) -> String? {
        let characters = Array(text)
        guard let start = characters.firstIndex(of: "{") else { return nil }

        var depth = 0
        var isInString = false
        var isEscaped = false
        for index in start..<characters.count {
            let character = characters[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if isInString {
                switch character {
                    case "\\": isEscaped = true
                    case "\"": isInString = false
                    default: break
                }
                continue
            }
            switch character {
                case "\"": isInString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(characters[start...index])
                    }
                default: break
            }
        }
        return nil
    }
}
