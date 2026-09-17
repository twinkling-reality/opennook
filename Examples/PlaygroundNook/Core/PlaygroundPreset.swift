// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookKit

/// A shareable playground state: the chrome settings plus the appearance preferences they were
/// tuned against. Stored as JSON by ``PlaygroundPresetCoder``:
///
/// ```json
/// {
///   "appearance" : { "chromePalette" : "dark", "surfaceStyle" : "liquidGlass", ... },
///   "format" : "opennook.playground-preset",
///   "settings" : { "panel" : { "expandedWidth" : 440, ... }, ... },
///   "version" : 1
/// }
/// ```
///
/// `keepNookOpen` is never part of a preset. It is a working aid - it keeps the nook open
/// while you tweak it - rather than part of a look, so it is cleared on the way in and out.
public struct PlaygroundPreset: Equatable, Sendable {
    /// The value of the `format` key every preset carries.
    public static let formatIdentifier = "opennook.playground-preset"

    /// The newest format version this playground reads and the one it writes. Raise it only
    /// for a change an older playground would misread; added keys need no new version, since
    /// a missing key decodes to its default and an unknown key is ignored.
    public static let currentVersion = 1

    public var appearance: NookAppearancePreferences {
        didSet { appearance.keepNookOpen = false }
    }
    public var settings: PlaygroundSettings

    public init(appearance: NookAppearancePreferences = .default, settings: PlaygroundSettings = .default) {
        var appearance = appearance
        appearance.keepNookOpen = false
        self.appearance = appearance
        self.settings = settings
    }
}

extension PlaygroundPreset: Codable {
    private enum CodingKeys: String, CodingKey {
        case format
        case version
        case appearance
        case settings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let appearance = try container.decodeIfPresent(NookAppearancePreferences.self, forKey: .appearance)
        let settings = try container.decodeIfPresent(PlaygroundSettings.self, forKey: .settings)
        self.init(appearance: appearance ?? .default, settings: settings ?? .default)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatIdentifier, forKey: .format)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(settings, forKey: .settings)
    }
}

/// Why a preset could not be read.
public enum PlaygroundPresetError: Error, Equatable, LocalizedError {
    /// The data is not JSON at all.
    case notJSON
    /// The JSON is not a playground preset: it has no `format` key naming one, or no `version`.
    case notAPreset
    /// The preset was written by a newer playground in a format this one cannot read.
    case unsupportedVersion(Int)
    /// A value has the wrong type or is not one of the allowed values.
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
            case .notJSON:
                "The text is not valid JSON."
            case .notAPreset:
                "This JSON is not a playground preset. A preset has \"format\": "
                    + "\"\(PlaygroundPreset.formatIdentifier)\" and a \"version\" number."
            case .unsupportedVersion(let version):
                "This preset uses format version \(version), and this playground reads up to "
                    + "version \(PlaygroundPreset.currentVersion)."
            case .invalidValue(let detail):
                "The preset has a value the playground cannot use: \(detail)."
        }
    }
}

/// Reads and writes ``PlaygroundPreset`` JSON. Pure: no files, no pasteboard.
public enum PlaygroundPresetCoder {
    /// Pretty-printed JSON with sorted keys, so a preset diffs cleanly under version control.
    public static func encode(_ preset: PlaygroundPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(preset)
    }

    /// ``encode(_:)`` as text, ending in a newline.
    public static func encodeString(_ preset: PlaygroundPreset) throws -> String {
        String(decoding: try encode(preset), as: UTF8.self) + "\n"
    }

    /// Reads a preset, checking its format and version first so the error names the real
    /// problem, and normalizes the settings (see `PlaygroundSettings.normalized()`).
    public static func decode(_ data: Data) throws -> PlaygroundPreset {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PlaygroundPresetError.notJSON
        }
        guard let fields = object as? [String: Any],
            fields["format"] as? String == PlaygroundPreset.formatIdentifier,
            let version = fields["version"] as? Int
        else {
            throw PlaygroundPresetError.notAPreset
        }
        guard (1...PlaygroundPreset.currentVersion).contains(version) else {
            throw PlaygroundPresetError.unsupportedVersion(version)
        }
        do {
            var preset = try JSONDecoder().decode(PlaygroundPreset.self, from: data)
            preset.settings = preset.settings.normalized()
            return preset
        } catch let error as DecodingError {
            throw PlaygroundPresetError.invalidValue(describe(error))
        }
    }

    /// ``decode(_:)`` for text.
    public static func decode(_ string: String) throws -> PlaygroundPreset {
        try decode(Data(string.utf8))
    }

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
        return path.isEmpty ? "The preset" : path
    }

    private static func typeDescription(_ type: Any.Type) -> String {
        switch type {
            case is Bool.Type: "true or false"
            case is String.Type: "a string"
            case is Double.Type, is Float.Type, is Int.Type: "a number"
            case is [String: Any].Type: "an object"
            case is [Any].Type: "a list"
            default: "a \(type)"
        }
    }
}

// MARK: - Samples

extension PlaygroundPreset {
    /// A built-in preset, offered by the playground as a starting point.
    public struct Sample: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let summary: String
        public let preset: PlaygroundPreset
    }

    public static let samples: [Sample] = [
        Sample(
            id: "defaults",
            name: "Framework defaults",
            summary: "The stock chrome",
            preset: PlaygroundPreset()
        ),
        Sample(
            id: "media",
            name: "Media player",
            summary: "Dark and narrow, with companions",
            preset: mediaPlayer
        ),
        Sample(
            id: "glass",
            name: "Floating glass",
            summary: "Floating Liquid Glass, rounded type",
            preset: floatingGlass
        ),
        Sample(
            id: "glance",
            name: "Bare glance",
            summary: "Content only, no top bar",
            preset: bareGlance
        ),
        Sample(
            id: "call",
            name: "Call controls",
            summary: "Two faded groups and a red leave button",
            preset: callControls
        ),
    ]

    private static var mediaPlayer: PlaygroundPreset {
        var settings = PlaygroundSettings()
        settings.panel.expandedWidth = 420
        settings.topBar.leadingTitle = "Music"
        settings.topBar.leadingIcon = "music.note"
        settings.topBar.showsKeepOpenButton = false
        settings.topBar.showsSettingsButton = false

        var sections = PlaygroundSettings.Companion(
            id: "sections",
            template: .actions,
            accessibilityLabel: "Player sections"
        )
        sections.spacing = 10
        var timer = PlaygroundSettings.Companion(
            id: "sleep-timer",
            template: .button,
            accessibilityLabel: "Sleep timer"
        )
        timer.spacing = 10
        timer.gap = 14
        timer.visibility = .both
        var controls = PlaygroundSettings.Companion(
            id: "controls",
            template: .controls,
            accessibilityLabel: "Nook controls"
        )
        controls.spacing = 10
        settings.companions = [sections, timer, controls]

        settings.scrollEdgeFade.isEnabled = true
        return PlaygroundPreset(
            appearance: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .solid),
            settings: settings
        )
    }

    private static var floatingGlass: PlaygroundPreset {
        var settings = PlaygroundSettings()
        settings.theme.fontDesign = .rounded
        settings.panel.topCornerRadius = 22
        settings.panel.bottomCornerRadius = 30
        settings.panel.insetBottom = 12
        settings.rimGlow.glowRadius = 14
        settings.rimGlow.intensity = 0.8

        var chip = PlaygroundSettings.Companion(id: "status", template: .chip, accessibilityLabel: "Status")
        chip.alignment = .end
        chip.spacing = 12
        settings.companions = [chip]
        settings.companionDefaults.hover = .lift
        return PlaygroundPreset(
            appearance: NookAppearancePreferences(
                surfaceStyle: .liquidGlass,
                presentation: .floating,
                accentPreset: .violet,
                backdropStrength: 0.7
            ),
            settings: settings
        )
    }

    /// Two groups of call controls below the panel, drawn with the fade, and a leave button that is
    /// a red surface of its own.
    private static var callControls: PlaygroundPreset {
        var settings = PlaygroundSettings()
        settings.panel.expandedWidth = 440
        settings.companionDefaults.fade = 0.35
        settings.companionDefaults.hover = .highlight
        settings.companionDefaults.presence = .slide

        let media = PlaygroundSettings.Companion(
            id: "media",
            items: [
                PlaygroundSettings.Item(symbol: "mic.fill", title: "Mute"),
                PlaygroundSettings.Item(symbol: "video.fill", title: "Camera"),
            ],
            accessibilityLabel: "Microphone and camera"
        )
        let share = PlaygroundSettings.Companion(
            id: "share",
            items: [
                PlaygroundSettings.Item(symbol: "rectangle.on.rectangle", title: "Share screen"),
                PlaygroundSettings.Item(symbol: "hand.raised.fill", title: "Raise hand"),
            ],
            accessibilityLabel: "Sharing"
        )
        var leaveItem = PlaygroundSettings.Item(symbol: "phone.down.fill", title: "Leave", action: .collapse)
        leaveItem.tint = PlaygroundColor(red: 1, green: 1, blue: 1)
        leaveItem.fill = .color
        leaveItem.fillColor = PlaygroundColor(red: 1, green: 0.23, blue: 0.19)
        leaveItem.size = .surface
        leaveItem.fade = 0.55
        var leave = PlaygroundSettings.Companion(id: "leave", items: [leaveItem], accessibilityLabel: "Leave call")
        leave.outline = .circle
        leave.backdrop = .none
        leave.gap = 16
        leave.presence = .pop
        settings.companions = [media, share, leave]
        return PlaygroundPreset(
            appearance: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .solid),
            settings: settings
        )
    }

    private static var bareGlance: PlaygroundPreset {
        var settings = PlaygroundSettings()
        settings.topBar.showsTopBar = false
        settings.topBar.showsSettings = false
        settings.panel.expandedWidth = 380
        settings.panel.bottomCornerRadius = 20
        settings.metrics.edgePadding = 12
        settings.theme.accent = PlaygroundColor(red: 1, green: 0.55, blue: 0.3)
        return PlaygroundPreset(settings: settings)
    }
}
