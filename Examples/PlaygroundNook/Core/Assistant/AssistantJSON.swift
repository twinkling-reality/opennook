// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// A JSON value the assistant can build, compare, and print back byte for byte.
///
/// `JSONSerialization` hands back `Any`, which is neither `Sendable` nor `Equatable`, and its
/// dictionaries lose their order. Both matter here: the schema and the field guide are compared
/// against fixtures in tests, and the schema is written to a file for `codex exec
/// --output-schema`, so the same catalog has to produce the same bytes every time. Objects keep
/// the order their members were added in, which is also the order the model is asked to answer
/// in (the explanation first, so it can be shown while the rest is still arriving).
public enum AssistantJSON: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([AssistantJSON])
    case object([Member])

    /// One key and value of an ``AssistantJSON/object(_:)``.
    public struct Member: Sendable, Equatable {
        public var name: String
        public var value: AssistantJSON

        public init(_ name: String, _ value: AssistantJSON) {
            self.name = name
            self.value = value
        }
    }

    public static func object(_ members: [(String, AssistantJSON)]) -> AssistantJSON {
        .object(members.map { Member($0.0, $0.1) })
    }
}

// MARK: - Reading

extension AssistantJSON {
    /// Parses `data` as JSON, or returns `nil` when it is not JSON at all.
    ///
    /// Fragments are allowed, so a model that answers with a bare string or number is read
    /// rather than rejected outright; the parser's job is to report what arrived, and the
    /// response parser decides whether it is usable.
    public init?(parsing data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        self.init(converting: object)
    }

    public init?(parsing text: String) {
        self.init(parsing: Data(text.utf8))
    }

    private init?(converting object: Any) {
        switch object {
            case let value as String:
                self = .string(value)
            case let value as NSNumber:
                // `NSNumber` bridges both, and `CFBooleanGetTypeID` is the only reliable way to
                // tell a JSON `true` from the number 1 once it has been through the bridge.
                if CFGetTypeID(value) == CFBooleanGetTypeID() {
                    self = .bool(value.boolValue)
                } else {
                    self = .number(value.doubleValue)
                }
            case is NSNull:
                self = .null
            case let values as [Any]:
                var members: [AssistantJSON] = []
                members.reserveCapacity(values.count)
                for value in values {
                    guard let converted = AssistantJSON(converting: value) else { return nil }
                    members.append(converted)
                }
                self = .array(members)
            case let fields as [String: Any]:
                // Sorted, because a parsed object has no order of its own and an arbitrary one
                // would make equality and printing depend on hashing.
                var members: [Member] = []
                members.reserveCapacity(fields.count)
                for name in fields.keys.sorted() {
                    guard let converted = AssistantJSON(converting: fields[name] as Any) else { return nil }
                    members.append(Member(name, converted))
                }
                self = .object(members)
            default:
                return nil
        }
    }
}

// MARK: - Members

extension AssistantJSON {
    /// The members of an object, or `nil` for every other kind of value.
    public var members: [Member]? {
        guard case .object(let members) = self else { return nil }
        return members
    }

    /// The value for `name`, when this is an object that has one.
    public subscript(name: String) -> AssistantJSON? {
        members?.first { $0.name == name }?.value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [AssistantJSON]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}

// MARK: - Writing

extension AssistantJSON {
    /// The value as JSON text, indented two spaces per level, with no trailing newline.
    public var text: String {
        var output = ""
        write(into: &output, depth: 0)
        return output
    }

    public var data: Data {
        Data(text.utf8)
    }

    private func write(into output: inout String, depth: Int) {
        switch self {
            case .string(let value):
                output += Self.quoted(value)
            case .number(let value):
                output += Self.numberText(value)
            case .bool(let value):
                output += value ? "true" : "false"
            case .null:
                output += "null"
            case .array(let values):
                guard !values.isEmpty else {
                    output += "[]"
                    return
                }
                let inner = String(repeating: "  ", count: depth + 1)
                output += "[\n"
                for (index, value) in values.enumerated() {
                    output += inner
                    value.write(into: &output, depth: depth + 1)
                    output += index < values.count - 1 ? ",\n" : "\n"
                }
                output += String(repeating: "  ", count: depth) + "]"
            case .object(let members):
                guard !members.isEmpty else {
                    output += "{}"
                    return
                }
                let inner = String(repeating: "  ", count: depth + 1)
                output += "{\n"
                for (index, member) in members.enumerated() {
                    output += inner + Self.quoted(member.name) + ": "
                    member.value.write(into: &output, depth: depth + 1)
                    output += index < members.count - 1 ? ",\n" : "\n"
                }
                output += String(repeating: "  ", count: depth) + "}"
        }
    }

    /// A number as text that reads back as the same number.
    ///
    /// Exactness matters more than tidiness here, because this is how a preset is written on the way
    /// through a patch merge. Rounding for looks would quietly rewrite every value with more precision
    /// than the format shows: a damping fraction a slider left at `0.8300000000000001` would come back
    /// as `0.83`, and the proposal would then list a change to a field nobody touched. `Double`'s own
    /// description is the shortest text that round trips, so it is used for everything except whole
    /// numbers, which print without a decimal point so a schema's bounds read as `100`.
    static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return value.description
    }

    static func quoted(_ text: String) -> String {
        var literal = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
                case "\\": literal += "\\\\"
                case "\"": literal += "\\\""
                case "\n": literal += "\\n"
                case "\r": literal += "\\r"
                case "\t": literal += "\\t"
                default:
                    if scalar.value < 0x20 {
                        literal += String(format: "\\u%04X", scalar.value)
                    } else {
                        literal.unicodeScalars.append(scalar)
                    }
            }
        }
        return literal + "\""
    }
}
