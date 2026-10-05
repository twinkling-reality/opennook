// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// The SF Symbols the framework top bar draws - the keep-open lock in both states, the
/// Settings gear, the breadcrumb separator, the back control, and the in-surface module
/// switcher's glyphs. Defaults reproduce today's glyphs.
///
/// Set via ``NookTopBarConfiguration/symbols``:
///
/// ```swift
/// configuration.topBar.symbols.keepOpenOn = "pin.fill"
/// configuration.topBar.symbols.keepOpenOff = "pin"
/// configuration.topBar.symbols.settings = "slider.horizontal.3"
/// ```
///
/// The values reach the chrome through `\.nookChromeSymbols`, so ``NookKeepOpenButton`` and
/// ``NookSettingsButton`` draw the same glyphs as the bar. A name that is not an SF Symbol
/// draws nothing, as with any `Image(systemName:)`.
public struct NookChromeSymbols: Sendable, Equatable {
    /// The keep-open lock while the nook stays expanded.
    public var keepOpenOn: String

    /// The keep-open lock while the nook closes when the pointer leaves.
    public var keepOpenOff: String

    /// The Settings gear.
    public var settings: String

    /// The separator between the leading cluster and the Settings or module breadcrumb.
    public var breadcrumbSeparator: String

    /// The glyph of the leading cluster's back control - shown in Settings or under a module
    /// breadcrumb, where clicking the leading glyph goes back. `nil` (the default) keeps the
    /// leading icon or brand mark there, so the bar reads as a breadcrumb (`[mark] > Settings`)
    /// rather than as browser back and forward buttons next to the separator.
    public var back: String?

    /// The chevron after the active module's name on the in-surface module switcher.
    public var moduleSwitcherIndicator: String

    /// The check beside the active module in the switcher's list.
    public var moduleSwitcherActive: String

    public init(
        keepOpenOn: String = "lock.fill",
        keepOpenOff: String = "lock.open",
        settings: String = "gearshape",
        breadcrumbSeparator: String = "chevron.right",
        back: String? = nil,
        moduleSwitcherIndicator: String = "chevron.down",
        moduleSwitcherActive: String = "checkmark"
    ) {
        self.keepOpenOn = keepOpenOn
        self.keepOpenOff = keepOpenOff
        self.settings = settings
        self.breadcrumbSeparator = breadcrumbSeparator
        self.back = back
        self.moduleSwitcherIndicator = moduleSwitcherIndicator
        self.moduleSwitcherActive = moduleSwitcherActive
    }

    /// The framework-default glyphs.
    public static let `default` = NookChromeSymbols()

    /// The lock glyph for the keep-open state `isOn`.
    public func keepOpen(_ isOn: Bool) -> String {
        isOn ? keepOpenOn : keepOpenOff
    }
}

private struct NookChromeSymbolsKey: EnvironmentKey {
    static let defaultValue: NookChromeSymbols = .default
}

extension EnvironmentValues {
    /// The top bar's SF Symbols. See ``NookChromeSymbols``.
    public var nookChromeSymbols: NookChromeSymbols {
        get { self[NookChromeSymbolsKey.self] }
        set { self[NookChromeSymbolsKey.self] = newValue }
    }
}
