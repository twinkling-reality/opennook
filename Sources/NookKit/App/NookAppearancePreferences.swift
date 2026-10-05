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

    /// Scales the backdrop's legibility pass when ``surfaceStyle`` is `.translucent` or
    /// `.liquidGlass`: the frosted material's darken, or the glass's tint and shading. `1` is
    /// the framework default; lower values show more wallpaper. The framework mapping clamps
    /// it to `0.15...1`, the range the Settings slider offers.
    public var backdropStrength: Double

    /// Whether the chrome theme's sounds play. On by default; a theme with no sounds plays
    /// nothing either way. Settings offers it as the "Sounds" row while the theme has sounds
    /// and allows the person to turn them off (``NookTheme/allowsUserSoundToggle``). When off,
    /// nothing plays, whatever the theme says.
    public var soundsEnabled: Bool

    /// What resting the pointer on the compact pill does: open the nook at once (the default,
    /// as before this setting existed), grow the pill into its peek first, or nothing, so the
    /// nook opens on a click or the shortcut.
    public var openOnHover: NookOpenOnHover

    /// Seconds the pointer rests on the pill before ``openOnHover`` acts, on the Mac's built-in
    /// display. 0 by default. Settings offers ``hoverTimingRange``.
    public var hoverDelay: Double

    /// ``hoverDelay`` on any other display, where the pointer crosses the top of the screen more
    /// often. 0 by default.
    public var externalDisplayHoverDelay: Double

    /// Seconds the pointer rests on a peek before the nook opens on its own. 0 (the default)
    /// waits for a click. Settings offers ``peekDwellRange``.
    public var peekDwell: Double

    /// The range Settings offers for ``hoverDelay`` and ``externalDisplayHoverDelay``.
    public static let hoverTimingRange: ClosedRange<Double> = 0...1

    /// The range Settings offers for ``peekDwell``.
    public static let peekDwellRange: ClosedRange<Double> = 0...3

    /// The surface's hover intent for these choices. ``NookHoverIntent/standard`` for the
    /// defaults, so a person who changed nothing gets the chrome as it always was.
    public var hoverIntent: NookHoverIntent {
        let action: NookHoverIntent.Action =
            switch openOnHover {
                case .immediately: .expand
                case .peekFirst: .peek
                case .off: .none
            }
        let delay = Self.duration(hoverDelay)
        let external = Self.duration(externalDisplayHoverDelay)
        return NookHoverIntent(
            action: action,
            delay: delay,
            // Only a different delay is a separate one, so equal delays keep the intent standard.
            externalDisplayDelay: external == delay ? nil : external,
            dwellToExpand: peekDwell > 0 ? Self.duration(peekDwell) : nil
        )
    }

    /// `seconds` as a duration, never negative or non-finite.
    private static func duration(_ seconds: Double) -> Duration {
        seconds.isFinite && seconds > 0 ? .milliseconds(Int((seconds * 1000).rounded())) : .zero
    }

    /// The range the framework mapping clamps ``backdropStrength`` to, and the range the
    /// built-in Settings slider offers - one value, so the two cannot disagree.
    static let backdropStrengthRange: ClosedRange<Double> = 0.15...1

    /// ``backdropStrength`` clamped to ``backdropStrengthRange``.
    var clampedBackdropStrength: Double {
        min(max(backdropStrength, Self.backdropStrengthRange.lowerBound), Self.backdropStrengthRange.upperBound)
    }

    public init(
        chromePalette: NookChromePalette = .followSystem,
        surfaceStyle: NookSurfaceStyle = .solid,
        presentation: NookPresentation = .auto,
        hapticFeedbackEnabled: Bool = false,
        keepNookOpen: Bool = false,
        accentPreset: NookAccentPreset = .system,
        backdropStrength: Double = 1,
        soundsEnabled: Bool = true,
        openOnHover: NookOpenOnHover = .immediately,
        hoverDelay: Double = 0,
        externalDisplayHoverDelay: Double = 0,
        peekDwell: Double = 0
    ) {
        self.chromePalette = chromePalette
        self.surfaceStyle = surfaceStyle
        self.presentation = presentation
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.keepNookOpen = keepNookOpen
        self.accentPreset = accentPreset
        self.backdropStrength = backdropStrength
        self.soundsEnabled = soundsEnabled
        self.openOnHover = openOnHover
        self.hoverDelay = hoverDelay
        self.externalDisplayHoverDelay = externalDisplayHoverDelay
        self.peekDwell = peekDwell
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
        case soundsEnabled
        case openOnHover
        case hoverDelay
        case externalDisplayHoverDelay
        case peekDwell
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
        self.soundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        self.openOnHover = try container.decodeIfPresent(NookOpenOnHover.self, forKey: .openOnHover) ?? .immediately
        self.hoverDelay = try container.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? 0
        self.externalDisplayHoverDelay =
            try container.decodeIfPresent(Double.self, forKey: .externalDisplayHoverDelay) ?? 0
        self.peekDwell = try container.decodeIfPresent(Double.self, forKey: .peekDwell) ?? 0
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
        try container.encode(soundsEnabled, forKey: .soundsEnabled)
        try container.encode(openOnHover, forKey: .openOnHover)
        try container.encode(hoverDelay, forKey: .hoverDelay)
        try container.encode(externalDisplayHoverDelay, forKey: .externalDisplayHoverDelay)
        try container.encode(peekDwell, forKey: .peekDwell)
    }
}

/// What resting the pointer on the compact pill does. See
/// ``NookAppearancePreferences/openOnHover``.
public enum NookOpenOnHover: String, Codable, Sendable, CaseIterable {
    /// Opens the nook at once.
    case immediately
    /// Grows the pill into its peek first; a click, or resting on the peek, opens the nook.
    case peekFirst
    /// Nothing: the nook opens on a click or the shortcut.
    case off
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
    var soundsEnabled: Bool?
    var openOnHover: NookOpenOnHover?
    var hoverDelay: Double?
    var externalDisplayHoverDelay: Double?
    var peekDwell: Double?

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
            Field(\.soundsEnabled, \.soundsEnabled),
            Field(\.openOnHover, \.openOnHover),
            Field(\.hoverDelay, \.hoverDelay),
            Field(\.externalDisplayHoverDelay, \.externalDisplayHoverDelay),
            Field(\.peekDwell, \.peekDwell),
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
        case soundsEnabled
        case openOnHover
        case hoverDelay
        case externalDisplayHoverDelay
        case peekDwell
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
        soundsEnabled = try? container.decodeIfPresent(Bool.self, forKey: .soundsEnabled)
        openOnHover = try? container.decodeIfPresent(NookOpenOnHover.self, forKey: .openOnHover)
        hoverDelay = try? container.decodeIfPresent(Double.self, forKey: .hoverDelay)
        externalDisplayHoverDelay = try? container.decodeIfPresent(Double.self, forKey: .externalDisplayHoverDelay)
        peekDwell = try? container.decodeIfPresent(Double.self, forKey: .peekDwell)
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
