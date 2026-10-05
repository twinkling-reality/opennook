// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Something a theme file had that was not used as written. The theme still loads.
public struct NookThemeIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        /// A member or token id this version does not know. It is ignored.
        case unknownKey
        /// A token id that was renamed. It is read as its new id.
        case renamed
        /// A token id that was removed. It is ignored.
        case removed
        /// A token listed under `tokens` that belongs under `components`, or the other way
        /// round. It is used anyway.
        case misplaced
        /// A number outside the range the chrome can use. It is brought into range.
        case clamped
        /// A reference to a token that does not exist, or to one of another kind. The token
        /// that refers to it keeps its default.
        case unknownReference
        /// An animation longer than two seconds. It is used as written; Apple caps Live
        /// Activity animations at two seconds, and a notch reads best within that.
        case longDuration
        /// A value this version reads but does not render as written, such as a hierarchical
        /// color.
        case unsupported
    }

    /// Where the issue is, as a JSON path such as `tokens.space.md` or `scale`.
    public var path: String
    public var kind: Kind
    /// A sentence saying what happened.
    public var message: String

    public init(path: String, kind: Kind, message: String) {
        self.path = path
        self.kind = kind
        self.message = message
    }

    public var description: String { "\(path): \(message)" }
}

/// Why a theme file could not be read at all.
public enum NookThemeError: Error, Equatable, LocalizedError {
    /// The data is not JSON.
    case notJSON
    /// The JSON is not a theme: it has no `"format": "opennook.theme"`, or no integer `version`.
    case notATheme
    /// The theme was written in a newer format than this version reads.
    case unsupportedVersion(Int)
    /// A value has the wrong type or is not one of the allowed values. The text leads with
    /// its JSON path.
    case invalidValue(String)
    /// Tokens refer to each other in a loop. Names one token in the loop.
    case referenceLoop(String)

    public var errorDescription: String? {
        switch self {
            case .notJSON:
                "The text is not valid JSON."
            case .notATheme:
                "This JSON is not an OpenNook theme. A theme has \"format\": \"\(NookThemeCoder.formatIdentifier)\" "
                    + "and a \"version\" number."
            case .unsupportedVersion(let version):
                "This theme uses format version \(version), and this version of OpenNook reads up to version "
                    + "\(NookThemeCoder.currentVersion)."
            case .invalidValue(let detail):
                "The theme has a value OpenNook cannot use: \(detail)."
            case .referenceLoop(let id):
                "The theme's tokens refer to each other in a loop through \(id)."
        }
    }
}

/// A theme read from a file, with what was not used as written.
public struct NookThemeLoadResult: Equatable, Sendable {
    public var theme: NookTheme
    public var issues: [NookThemeIssue]

    public init(theme: NookTheme, issues: [NookThemeIssue]) {
        self.theme = theme
        self.issues = issues
    }
}

/// Reads and writes theme files. Pure: no files, no pasteboard.
///
/// A theme file is a ``NookTheme`` with an envelope:
///
/// ```json
/// {
///   "format": "opennook.theme",
///   "version": 1,
///   "accent": "#3399FF",
///   "radius": "large",
///   "tokens": { "space.md": 9 },
///   "components": { "banner.cornerRadius": "{radius.lg}" }
/// }
/// ```
///
/// Reading is forgiving where it can be: a missing member has its default, an unknown member
/// or token id is ignored, a renamed id is read as its new one, and a number out of range is
/// brought into range; each is reported as a ``NookThemeIssue``. A value of the wrong type,
/// or tokens that refer to each other in a loop, are errors.
public enum NookThemeCoder {
    /// The value of the `format` member every theme file has.
    public static let formatIdentifier = "opennook.theme"

    /// The newest format version this version reads, and the one it writes. Raised only for a
    /// change an older reader would misread; an added member or token needs no new version.
    public static let currentVersion = 1

    /// Pretty-printed JSON with sorted keys and only what differs from ``NookTheme/standard``,
    /// so a theme diffs cleanly under version control.
    public static func encode(_ theme: NookTheme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Document(theme: theme))
    }

    /// ``encode(_:)`` as text, ending in a newline.
    public static func encodeString(_ theme: NookTheme) throws -> String {
        String(decoding: try encode(theme), as: UTF8.self) + "\n"
    }

    /// Reads a theme file: checks the envelope, decodes, brings values into range, and checks
    /// every reference.
    public static func decode(_ data: Data) throws -> NookThemeLoadResult {
        try decode(data, renames: NookTokenRenames.map)
    }

    /// ``decode(_:)`` for text.
    public static func decode(_ string: String) throws -> NookThemeLoadResult {
        try decode(Data(string.utf8))
    }

    static func decode(_ data: Data, renames: [String: String?]) throws -> NookThemeLoadResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NookThemeError.notJSON
        }
        guard let members = object as? [String: Any],
            members["format"] as? String == formatIdentifier,
            let versionNumber = members["version"] as? NSNumber,
            CFGetTypeID(versionNumber) != CFBooleanGetTypeID(),
            let version = Int(exactly: versionNumber.doubleValue)
        else {
            throw NookThemeError.notATheme
        }
        guard (1...currentVersion).contains(version) else {
            throw NookThemeError.unsupportedVersion(version)
        }

        var theme: NookTheme
        do {
            theme = try JSONDecoder().decode(NookTheme.self, from: data)
        } catch let error as DecodingError {
            throw NookThemeError.invalidValue(describe(error))
        }
        // `NookTheme`'s own decoding reads the shipped renames; read them again with `renames`
        // so a test can supply its own.
        if renames != NookTokenRenames.map {
            theme.tokens = try retokenized(data, renames: renames)
        }

        var issues = memberIssues(members, renames: renames)
        let validated = theme.validated()
        theme = validated.theme
        issues += validated.issues
        issues += try referenceIssues(theme)
        return NookThemeLoadResult(theme: theme, issues: issues)
    }

    // MARK: Envelope

    private struct Document: Encodable {
        let theme: NookTheme

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: NookCodingKey.self)
            try container.put(formatIdentifier, "format")
            try container.put(currentVersion, "version")
            try theme.encode(to: encoder)
        }
    }

    private static func retokenized(_ data: Data, renames: [String: String?]) throws -> NookThemeTokens {
        // Decoding with a different rename map only happens in tests; it re-reads the token
        // sections by hand rather than threading the map through `Decodable`.
        guard let members = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return NookThemeTokens()
        }
        var tokens = NookThemeTokens()
        for section in ["tokens", "components"] {
            guard let entries = members[section] as? [String: Any] else { continue }
            var renamed: [String: Any] = [:]
            for (key, value) in entries {
                if let id = NookTokenRenames.currentID(for: key, renames: renames) { renamed[id] = value }
            }
            let sectionData = try JSONSerialization.data(withJSONObject: ["tokens": renamed])
            let partial = try JSONDecoder().decode(NookTheme.self, from: sectionData)
            tokens.merge(partial.tokens)
        }
        return tokens
    }

    // MARK: Unknown members

    private static func memberIssues(_ members: [String: Any], renames: [String: String?]) -> [NookThemeIssue] {
        var issues: [NookThemeIssue] = []
        for key in members.keys.sorted()
        where key != "format" && key != "version" && !NookTheme.memberNames.contains(key) {
            issues.append(NookThemeIssue(path: key, kind: .unknownKey, message: "not a theme member; ignored"))
        }
        for section in ["tokens", "components"] {
            guard let entries = members[section] as? [String: Any] else { continue }
            let sectionTier: NookTokenTier = section == "tokens" ? .semantic : .component
            for key in entries.keys.sorted() {
                let path = "\(section).\(key)"
                guard let current = NookTokenRenames.currentID(for: key, renames: renames) else {
                    issues.append(
                        NookThemeIssue(path: path, kind: .removed, message: "this token was removed; ignored")
                    )
                    continue
                }
                guard let entry = NookTokenRegistry.entry(for: current) else {
                    issues.append(NookThemeIssue(path: path, kind: .unknownKey, message: "not a token id; ignored"))
                    continue
                }
                if current != key {
                    issues.append(
                        NookThemeIssue(path: path, kind: .renamed, message: "renamed to \(current); read as it")
                    )
                }
                if entry.tier != sectionTier {
                    let other = sectionTier == .semantic ? "components" : "tokens"
                    issues.append(
                        NookThemeIssue(path: path, kind: .misplaced, message: "belongs under \(other); used anyway")
                    )
                }
            }
        }
        if let backdrops = members["backdrops"] as? [String: Any] {
            let known: Set<String> = ["solid", "translucent", "liquidGlass", "glassShading"]
            for key in backdrops.keys.sorted() where !known.contains(key) {
                issues.append(
                    NookThemeIssue(path: "backdrops.\(key)", kind: .unknownKey, message: "not a surface style; ignored")
                )
            }
        }
        return issues
    }

    // MARK: References

    /// Resolves everything once to find references that point nowhere. A reference loop is
    /// an error: the theme as written has no meaning.
    private static func referenceIssues(_ theme: NookTheme) throws -> [NookThemeIssue] {
        let resolver = NookThemeResolver(theme: theme)
        _ = resolver.resolveAll()
        for isDark in [true, false] {
            for surface in NookSurfaceStyle.allCases {
                let context = NookThemeContext(isDark: isDark, surfaceStyle: surface)
                for token in NookTokenRegistry.colorTokens {
                    _ = resolver.color(token.id, in: context)
                }
            }
        }
        if let loop = resolver.issues.first(where: { $0.kind == .cycle }) {
            throw NookThemeError.referenceLoop(loop.id)
        }
        return resolver.issues.compactMap { issue in
            guard case .unknownReference(let target) = issue.kind else { return nil }
            return NookThemeIssue(
                path: target,
                kind: .unknownReference,
                message: "no token of the right kind is named \(target); what refers to it keeps its default"
            )
        }
    }

    // MARK: Error text

    /// A one-line account of a decoding error, led by the JSON path of the bad value.
    static func describe(_ error: DecodingError) -> String {
        switch error {
            case .typeMismatch(let type, let context):
                return "\(path(of: context)) should be \(typeDescription(type))"
            case .valueNotFound(let type, let context):
                return "\(path(of: context)) should be \(typeDescription(type)), not null"
            case .keyNotFound(let key, let context):
                return "\(path(of: context, appending: key)) is missing"
            case .dataCorrupted(let context):
                return "\(path(of: context)): \(context.debugDescription)"
            @unknown default:
                return String(describing: error)
        }
    }

    private static func path(of context: DecodingError.Context, appending key: (any CodingKey)? = nil) -> String {
        let keys = context.codingPath + (key.map { [$0] } ?? [])
        var path = ""
        for key in keys {
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return path.isEmpty ? "The theme" : path
    }

    private static func typeDescription(_ type: Any.Type) -> String {
        switch type {
            case is Bool.Type: "true or false"
            case is String.Type: "a string"
            case is Double.Type, is Float.Type, is Int.Type: "a number"
            default: "a \(type)"
        }
    }
}

extension NookThemeTokens {
    /// Puts every override in `other` over this one's.
    mutating func merge(_ other: NookThemeTokens) {
        colors.merge(other.colors) { $1 }
        dimensions.merge(other.dimensions) { $1 }
        fonts.merge(other.fonts) { $1 }
        animations.merge(other.animations) { $1 }
        transitions.merge(other.transitions) { $1 }
        sounds.merge(other.sounds) { $1 }
        shadows.merge(other.shadows) { $1 }
    }
}

// MARK: - Loading and saving

extension NookTheme {
    /// Reads a theme file, dropping the issues. Use `NookThemeCoder.decode(_:)` to see them.
    public init(jsonData: Data) throws {
        self = try NookThemeCoder.decode(jsonData).theme
    }

    /// Reads a theme file from disk, dropping the issues.
    public init(contentsOf url: URL) throws {
        try self.init(jsonData: try Data(contentsOf: url))
    }

    /// The theme as a theme file. See ``NookThemeCoder/encode(_:)``.
    public func jsonData() throws -> Data {
        try NookThemeCoder.encode(self)
    }
}

// MARK: - Validation

extension NookTheme {
    /// The theme with every number brought into the range the chrome can use, and what was
    /// changed or will not render as written. A theme loaded from a file has already been
    /// through this.
    public func validated() -> (theme: NookTheme, issues: [NookThemeIssue]) {
        var validator = NookThemeValidator()
        let theme = validator.validate(self)
        return (theme, validator.issues)
    }
}

private struct NookThemeValidator {
    var issues: [NookThemeIssue] = []

    private mutating func clamp(_ value: Double, _ range: ClosedRange<Double>, _ path: String) -> Double {
        guard value.isFinite else {
            let fallback = min(max(0, range.lowerBound), range.upperBound)
            issues.append(
                NookThemeIssue(path: path, kind: .clamped, message: "not a finite number; read as \(fallback)")
            )
            return fallback
        }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if clamped != value {
            issues.append(
                NookThemeIssue(
                    path: path,
                    kind: .clamped,
                    message: "\(value) is outside \(range.lowerBound)...\(range.upperBound); read as \(clamped)"
                )
            )
        }
        return clamped
    }

    private static func section(of id: String) -> String {
        NookThemeTokens.tier(of: id) == .semantic ? "tokens" : "components"
    }

    mutating func validate(_ input: NookTheme) -> NookTheme {
        var theme = input
        theme.scale = clamp(theme.scale, 0.5...2, "scale")
        if case .factor(let factor) = theme.radius {
            theme.radius = .factor(clamp(factor, 0...4, "radius"))
        }
        theme.backdropStrength = theme.backdropStrength.map { clamp($0, 0.15...1, "backdropStrength") }
        theme.soundVolume = clamp(theme.soundVolume, 0...1, "soundVolume")
        theme.accent = color(theme.accent, "accent")

        for (id, value) in theme.tokens.colors {
            theme.tokens.colors[id] = color(value, "\(Self.section(of: id.rawValue)).\(id.rawValue)")
        }
        for (id, value) in theme.tokens.dimensions {
            let path = "\(Self.section(of: id.rawValue)).\(id.rawValue)"
            let range = NookTokenRegistry.dimensionsByID[id]?.range ?? .length
            switch value {
                case .points(let points):
                    let clamped = clamp(points, range.bounds, path)
                    theme.tokens.dimensions[id] = .points(clamped)
                    if range == .duration, clamped > 2 { longDuration(clamped, path) }
                case .reference(let reference, let times):
                    theme.tokens.dimensions[id] = .reference(reference, times: clamp(times, -100...100, path))
            }
        }
        for (id, spec) in theme.tokens.fonts {
            var spec = spec
            if case .points(let size) = spec.size {
                spec.size = .points(clamp(size, 1...200, "\(Self.section(of: id.rawValue)).\(id.rawValue).size"))
            }
            theme.tokens.fonts[id] = spec
        }
        for (id, spec) in theme.tokens.animations {
            theme.tokens.animations[id] = animation(spec, "\(Self.section(of: id.rawValue)).\(id.rawValue)")
        }
        for (id, spec) in theme.tokens.transitions {
            let path = "tokens.\(id.rawValue)"
            var spec = spec
            spec.opacity = clamp(spec.opacity, 0...1, "\(path).opacity")
            spec.blur = clamp(spec.blur, 0...100, "\(path).blur")
            spec.scaleX = clamp(spec.scaleX, 0...4, "\(path).scaleX")
            spec.scaleY = clamp(spec.scaleY, 0...4, "\(path).scaleY")
            spec.animation = spec.animation.map { animation($0, "\(path).animation") }
            theme.tokens.transitions[id] = spec
        }
        for (id, sound) in theme.tokens.sounds {
            var sound = sound
            sound.volume = sound.volume.map { clamp($0, 0...1, "tokens.\(id.rawValue).volume") }
            theme.tokens.sounds[id] = sound
        }
        for (id, shadow) in theme.tokens.shadows {
            let path = "tokens.\(id.rawValue)"
            var shadow = shadow
            shadow.color = color(shadow.color, "\(path).color")
            shadow.radius = clamp(shadow.radius, 0...200, "\(path).radius")
            theme.tokens.shadows[id] = shadow
        }
        return theme
    }

    private mutating func longDuration(_ seconds: Double, _ path: String) {
        issues.append(
            NookThemeIssue(
                path: path,
                kind: .longDuration,
                message: "\(seconds) s is longer than two seconds; used as written"
            )
        )
    }

    private mutating func animation(_ spec: NookAnimationSpec, _ path: String) -> NookAnimationSpec {
        let clamped = spec.clampedForPlayback
        if clamped != spec {
            issues.append(
                NookThemeIssue(
                    path: path,
                    kind: .clamped,
                    message: "a number is outside what SwiftUI can play; brought into range"
                )
            )
        }
        if let duration = clamped.nominalDuration, duration > 2 { longDuration(duration, path) }
        return clamped
    }

    private mutating func color(_ value: NookColorValue, _ path: String) -> NookColorValue {
        switch value {
            case .hex, .system:
                return value
            case .srgb(let red, let green, let blue, let opacity):
                return .srgb(
                    red: clamp(red, 0...1, "\(path).srgb[0]"),
                    green: clamp(green, 0...1, "\(path).srgb[1]"),
                    blue: clamp(blue, 0...1, "\(path).srgb[2]"),
                    opacity: clamp(opacity, 0...1, "\(path).opacity")
                )
            case .white(let opacity):
                return .white(opacity: clamp(opacity, 0...1, "\(path).white"))
            case .black(let opacity):
                return .black(opacity: clamp(opacity, 0...1, "\(path).black"))
            case .reference(let id, let opacity):
                return .reference(id, opacity: opacity.map { clamp($0, 0...1, "\(path).opacity") })
            case .adaptive(var adaptive):
                adaptive.dark = color(adaptive.dark, "\(path).dark")
                adaptive.light = color(adaptive.light, "\(path).light")
                adaptive.darkSolid = adaptive.darkSolid.map { color($0, "\(path).darkSolid") }
                adaptive.lightSolid = adaptive.lightSolid.map { color($0, "\(path).lightSolid") }
                adaptive.darkReducedTransparency = adaptive.darkReducedTransparency.map {
                    color($0, "\(path).darkReducedTransparency")
                }
                adaptive.lightReducedTransparency = adaptive.lightReducedTransparency.map {
                    color($0, "\(path).lightReducedTransparency")
                }
                return .adaptive(adaptive)
            case .hierarchical(let level):
                issues.append(
                    NookThemeIssue(
                        path: path,
                        kind: .unsupported,
                        message: "hierarchical colors are not drawn with vibrancy on the chrome; "
                            + "read as \(level.labelRole.rawValue)"
                    )
                )
                return value
        }
    }
}
