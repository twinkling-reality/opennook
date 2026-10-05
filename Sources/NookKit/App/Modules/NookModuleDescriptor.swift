// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// The cheap, registration-time identity of a notch module - everything the host and
/// the module switcher need *before* the module itself is instantiated.
///
/// A ``NookModule`` carries product state and views; a descriptor carries only the
/// metadata to list it, key its persistence, and route a hotkey to it. The split keeps
/// registration free of side effects: a host can register a dozen modules and pay the
/// construction cost only for the ones the user actually opens.
/// `Sendable`: a descriptor is a value type of `Sendable` members (`String`, SwiftUI
/// `Color`, `NookHotkey`, the `BackgroundPolicy` enum). It is built at launch and
/// handed to the main actor as part of a ``NookHostConfiguration``, so it genuinely
/// crosses an isolation boundary and the conformance must be real.
public struct NookModuleDescriptor: Identifiable, Sendable {
    /// Stable, unique identifier - reverse-DNS by convention (`"com.you.nuggie"`).
    /// Used as the switcher key, the per-module `UserDefaults` suite name, and the
    /// on-disk container folder name, so it must not change across releases.
    public let id: String

    /// Human-readable name shown in the module switcher.
    public var displayName: String

    /// SF Symbol shown for this module in the module switcher. (The top-bar leading
    /// cluster is driven separately by ``NookTopBarConfiguration/leadingIcon`` and the
    /// host brand mark - not by this descriptor.)
    public var icon: String

    /// Never read by the framework: the switcher is a menu whose entries cannot take a tint.
    /// To give a module its own accent, set it on the module's configuration:
    /// `configuration.chromeTheme = NookTheme(accent: ...)`, which the chrome applies when the
    /// module's content is on the surface.
    @available(
        *,
        deprecated,
        message: "Never read. Give a module its own accent with its configuration's chromeTheme.accent."
    )
    public var accent: Color {
        get { storedAccent }
        set { storedAccent = newValue }
    }

    private var storedAccent: Color

    /// Optional global hotkey that jumps straight to this module. `nil` - the default -
    /// means the module is reachable only via the switcher or the cycle hotkey.
    public var hotkey: NookHotkey?

    /// What happens to the module when the user switches away from it.
    public var backgroundPolicy: BackgroundPolicy

    /// Residency policy for a module that is not the foreground module.
    public enum BackgroundPolicy: Sendable {
        /// Tear the module down on switch-away; rebuild it on next activation. Cheapest;
        /// the module does no background work and posts no background activities.
        case unloadOnSwitchAway

        /// Keep the module instance alive in the background so its services and
        /// activity queue keep running. It can still post activities - the
        /// `SurfaceArbiter` gates whether a background module reaches the surface.
        case stayResident
    }

    public init(
        id: String,
        displayName: String,
        icon: String = "square.grid.2x2",
        hotkey: NookHotkey? = nil,
        backgroundPolicy: BackgroundPolicy = .unloadOnSwitchAway
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.storedAccent = .accentColor
        self.hotkey = hotkey
        self.backgroundPolicy = backgroundPolicy
    }

    /// A descriptor with an `accent` the framework never reads. See ``accent``.
    @available(
        *,
        deprecated,
        message: "accent is never read. Drop it, and give a module its own accent with its configuration's chromeTheme."
    )
    public init(
        id: String,
        displayName: String,
        icon: String = "square.grid.2x2",
        accent: Color,
        hotkey: NookHotkey? = nil,
        backgroundPolicy: BackgroundPolicy = .unloadOnSwitchAway
    ) {
        self.init(id: id, displayName: displayName, icon: icon, hotkey: hotkey, backgroundPolicy: backgroundPolicy)
        self.storedAccent = accent
    }
}
