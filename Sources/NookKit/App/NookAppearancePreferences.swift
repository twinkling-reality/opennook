// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookSurface
import SwiftUI

/// Persistent personalization for the Nook chrome - appearance (materials, palette),
/// layout, and chrome behavior that should survive across launches.
public struct NookAppearancePreferences: Equatable, Codable, Sendable {
    /// Follow the macOS appearance, or pin the chrome to dark / light.
    public var chromePalette: NookChromePalette

    /// Solid (opaque, matches the notch) or translucent (frosted, shows the wallpaper).
    public var surfaceStyle: NookSurfaceStyle

    /// Notch-fused or free-floating chrome - `.auto` follows the display. See
    /// `NookPresentation`. This is what lets OpenNook work on a Mac with no notch.
    public var presentation: NookPresentation

    /// When on, completion-style events play a one-shot trackpad haptic via
    /// `NSHapticFeedbackManager`. Off by default - macOS haptics only fire when the user's
    /// hand is on a Force Touch trackpad with system haptics enabled, so this is a bonus
    /// completion signal, never the primary feedback channel.
    public var hapticFeedbackEnabled: Bool

    /// When on, the expanded nook stays open after the pointer leaves instead of
    /// auto-collapsing on hover-exit (the top-bar lock / Settings "stay expanded"
    /// toggle). Persisted so a pinned-open nook survives a relaunch.
    public var keepNookOpen: Bool

    /// Chrome control tint (lock, gear, toggles). `.system` follows macOS accent.
    public var accentPreset: NookAccentPreset

    /// Scales the frosted backdrop's legibility darken pass when ``surfaceStyle`` is
    /// `.translucent`. `1` is the framework default; lower values show more wallpaper.
    public var backdropStrength: Double

    public init(
        chromePalette: NookChromePalette = .followSystem,
        surfaceStyle: NookSurfaceStyle = .solid,
        presentation: NookPresentation = .auto,
        hapticFeedbackEnabled: Bool = false,
        keepNookOpen: Bool = false,
        accentPreset: NookAccentPreset = .system,
        backdropStrength: Double = 1
    ) {
        self.chromePalette = chromePalette
        self.surfaceStyle = surfaceStyle
        self.presentation = presentation
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.keepNookOpen = keepNookOpen
        self.accentPreset = accentPreset
        self.backdropStrength = backdropStrength
    }

    /// Framework defaults - what `NookApp.main()` ships if the host has never written
    /// preferences.
    public static let `default` = NookAppearancePreferences()

    private enum CodingKeys: String, CodingKey {
        case chromePalette
        case surfaceStyle
        case presentation
        case hapticFeedbackEnabled
        case keepNookOpen
        case accentPreset
        case backdropStrength
    }

    // Custom decode so JSON written by an older build (missing a later-added field)
    // round-trips to the current defaults instead of failing the whole record back to
    // `.default` and wiping the user's saved preferences. To add a field: give it a
    // default in the initializer and a matching `decodeIfPresent` line here.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chromePalette =
            try container.decodeIfPresent(NookChromePalette.self, forKey: .chromePalette) ?? .followSystem
        self.surfaceStyle = try container.decodeIfPresent(NookSurfaceStyle.self, forKey: .surfaceStyle) ?? .solid
        self.presentation = try container.decodeIfPresent(NookPresentation.self, forKey: .presentation) ?? .auto
        self.hapticFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled) ?? false
        self.keepNookOpen = try container.decodeIfPresent(Bool.self, forKey: .keepNookOpen) ?? false
        self.accentPreset = try container.decodeIfPresent(NookAccentPreset.self, forKey: .accentPreset) ?? .system
        self.backdropStrength = try container.decodeIfPresent(Double.self, forKey: .backdropStrength) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chromePalette, forKey: .chromePalette)
        try container.encode(surfaceStyle, forKey: .surfaceStyle)
        try container.encode(presentation, forKey: .presentation)
        try container.encode(hapticFeedbackEnabled, forKey: .hapticFeedbackEnabled)
        try container.encode(keepNookOpen, forKey: .keepNookOpen)
        try container.encode(accentPreset, forKey: .accentPreset)
        try container.encode(backdropStrength, forKey: .backdropStrength)
    }
}

/// Pins the chrome palette to follow macOS or to a fixed light/dark - independent of
/// the wallpaper-aware ``NookSurfaceStyle``.
public enum NookChromePalette: String, Codable, Sendable, CaseIterable {
    case followSystem
    case dark
    case light
}

/// `.solid` paints the chrome the same opaque color as the menu-bar notch - true black on
/// dark, true white on light - so the expanded panel reads as one continuous surface.
/// `.translucent` shows the wallpaper through a frosted material instead. `.liquidGlass`
/// renders Apple's Liquid Glass material (macOS 26+), with a layered approximation on
/// earlier systems; Reduce Transparency collapses both translucent styles to `.solid`.
public enum NookSurfaceStyle: String, Codable, Sendable, CaseIterable {
    case solid
    case translucent
    case liquidGlass
}

// MARK: - Persistence

/// The appearance fields a person has changed, and only those.
///
/// Stored instead of a whole ``NookAppearancePreferences`` so every field the person never
/// touched keeps following the host's launch defaults (``NookPreferenceDefaults``): a host that
/// later changes a default reaches everyone who never chose that field, even after they changed
/// a different one.
struct NookAppearanceChoices: Codable, Equatable, Sendable {
    var chromePalette: NookChromePalette?
    var surfaceStyle: NookSurfaceStyle?
    var presentation: NookPresentation?
    var hapticFeedbackEnabled: Bool?
    var keepNookOpen: Bool?
    var accentPreset: NookAccentPreset?
    var backdropStrength: Double?

    init() {}

    /// The fields where `preferences` differs from `defaults`, as choices.
    init(differencesFrom defaults: NookAppearancePreferences, to preferences: NookAppearancePreferences) {
        record(from: defaults, to: preferences)
    }

    /// `true` when the person has chosen nothing.
    var isEmpty: Bool { self == NookAppearanceChoices() }

    /// Records as chosen every field that changes from `old` to `new`. Fields that do not change
    /// keep whatever was recorded for them before.
    mutating func record(from old: NookAppearancePreferences, to new: NookAppearancePreferences) {
        for field in Self.fields { field.record(&self, old, new) }
    }

    /// `defaults` with every chosen field put in.
    func applied(to defaults: NookAppearancePreferences) -> NookAppearancePreferences {
        var preferences = defaults
        for field in Self.fields { field.apply(self, &preferences) }
        return preferences
    }

    /// One field of ``NookAppearancePreferences`` and where its choice is kept. Adding a field to
    /// the preferences takes a matching optional property here and one entry in ``fields``.
    private struct Field {
        let record: (inout NookAppearanceChoices, NookAppearancePreferences, NookAppearancePreferences) -> Void
        let apply: (NookAppearanceChoices, inout NookAppearancePreferences) -> Void

        init<Value: Equatable>(
            _ preference: WritableKeyPath<NookAppearancePreferences, Value>,
            _ choice: WritableKeyPath<NookAppearanceChoices, Value?>
        ) {
            record = { choices, old, new in
                if old[keyPath: preference] != new[keyPath: preference] {
                    choices[keyPath: choice] = new[keyPath: preference]
                }
            }
            apply = { choices, preferences in
                if let value = choices[keyPath: choice] {
                    preferences[keyPath: preference] = value
                }
            }
        }
    }

    private static var fields: [Field] {
        [
            Field(\.chromePalette, \.chromePalette),
            Field(\.surfaceStyle, \.surfaceStyle),
            Field(\.presentation, \.presentation),
            Field(\.hapticFeedbackEnabled, \.hapticFeedbackEnabled),
            Field(\.keepNookOpen, \.keepNookOpen),
            Field(\.accentPreset, \.accentPreset),
            Field(\.backdropStrength, \.backdropStrength),
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case chromePalette
        case surfaceStyle
        case presentation
        case hapticFeedbackEnabled
        case keepNookOpen
        case accentPreset
        case backdropStrength
    }

    // Each field decodes on its own, so a value a newer build wrote that this one cannot read
    // (a new surface style, say) drops only that choice rather than every choice.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chromePalette = try? container.decodeIfPresent(NookChromePalette.self, forKey: .chromePalette)
        surfaceStyle = try? container.decodeIfPresent(NookSurfaceStyle.self, forKey: .surfaceStyle)
        presentation = try? container.decodeIfPresent(NookPresentation.self, forKey: .presentation)
        hapticFeedbackEnabled = try? container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled)
        keepNookOpen = try? container.decodeIfPresent(Bool.self, forKey: .keepNookOpen)
        accentPreset = try? container.decodeIfPresent(NookAccentPreset.self, forKey: .accentPreset)
        backdropStrength = try? container.decodeIfPresent(Double.self, forKey: .backdropStrength)
    }
}

/// Persists the appearance fields a person changed. See ``NookAppearanceChoices``.
enum NookAppearanceStore {
    /// Where the chosen fields are kept.
    static let choicesKey = "opennook.appearance.choices.v2"

    /// Where builds before per-field storage kept a whole ``NookAppearancePreferences`` record,
    /// written whenever any field changed. Read once, to migrate, and never written. It is left in
    /// place so an older build still finds its own record.
    static let legacyKey = "opennook.appearance.v1"

    static func load() -> NookAppearancePreferences {
        load(default: .default)
    }

    /// The person's choices put over `fallback`, the host's launch defaults (see
    /// ``NookPreferenceDefaults``). `fallback` itself is never written.
    static func load(default fallback: NookAppearancePreferences) -> NookAppearancePreferences {
        loadChoices(default: fallback).applied(to: fallback)
    }

    /// The stored choices, migrating a record from an earlier build when there are none yet.
    ///
    /// A whole record cannot tell a person's choice from a default that was in place when it was
    /// saved. Its fields that match `fallback` are taken as never chosen, so they follow later
    /// default changes; every other field is kept as a choice, so nobody's appearance changes
    /// when they upgrade. The result is stored right away, so the migration runs once rather than
    /// again against whatever the defaults are at a later launch.
    static func loadChoices(default fallback: NookAppearancePreferences) -> NookAppearanceChoices {
        let defaults = NookPreferenceStorage.defaults
        if let data = defaults.data(forKey: choicesKey) {
            return (try? JSONDecoder().decode(NookAppearanceChoices.self, from: data)) ?? NookAppearanceChoices()
        }
        guard let data = defaults.data(forKey: legacyKey),
            let legacy = try? JSONDecoder().decode(NookAppearancePreferences.self, from: data)
        else { return NookAppearanceChoices() }
        let migrated = NookAppearanceChoices(differencesFrom: fallback, to: legacy)
        saveChoices(migrated)
        return migrated
    }

    /// Stores `choices`, including an empty set: an empty record, not a missing one, is what
    /// keeps an earlier build's record from being migrated again after a reset.
    static func saveChoices(_ choices: NookAppearanceChoices) {
        guard let data = try? JSONEncoder().encode(choices) else { return }
        NookPreferenceStorage.defaults.set(data, forKey: choicesKey)
    }
}
