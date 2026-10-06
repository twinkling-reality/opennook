// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Host-overridable strings the framework draws - for localization or product naming
/// (e.g. "Preferences" instead of "Settings"). Defaults reproduce today's English.
///
/// Every user-visible string the framework draws comes from here: the top bar, the status
/// banner, the built-in Settings screen and its public sections, the menu-bar item, the
/// placeholder home view, and the `NookComponents` views. The four top-bar strings sit at
/// the top level; the rest are grouped by where they appear (``topBar``, ``settings``,
/// ``appearance``, ``display``, ``shortcut``, ``menuBar``, ``components``):
///
/// ```swift
/// var labels = NookChromeLabels()
/// labels.settingsBreadcrumb = "Preferences"
/// labels.settings.appearanceTitle = "Look"
/// labels.menuBar.quit = "Quit Constellation"
/// configuration.labels = labels
/// ```
///
/// A string that carries a value - a host name, a key combination - is a template whose
/// `{name}` placeholders are filled in when it is drawn, so a translation can move the
/// value: `labels.shortcut.showHostFormat = "{host} anzeigen"`. Each template documents
/// its placeholders.
///
/// Set via ``NookConfiguration/labels``. The values reach the views through the chrome
/// environment (`\.nookChromeLabels`); the menu-bar item reads the active module's.
public struct NookChromeLabels: Sendable, Equatable {
    /// The Settings breadcrumb shown after the leading cluster (`[icon] Title › Settings`).
    public var settingsBreadcrumb: String

    /// Tooltip on the keep-open lock glyph.
    public var keepOpenHelp: String

    /// Tooltip on the Settings gear glyph.
    public var settingsHelp: String

    /// Tooltip on the status banner's dismiss button.
    public var dismissHelp: String

    /// The rest of the top bar: the in-surface module switcher.
    public var topBar: TopBar

    /// The built-in Settings screen's group titles, the Data and About groups.
    public var settings: Settings

    /// The Appearance group (``NookAppearanceSettingsSection``).
    public var appearance: Appearance

    /// The Display group (``NookDisplaySettingsSection``).
    public var display: Display

    /// The Shortcut & nook group (``NookShortcutSettingsSection``) and the shortcut names
    /// that appear in its failure rows.
    public var shortcut: Shortcut

    /// The framework's menu-bar item (`NookApp`).
    public var menuBar: MenuBar

    /// The `NookComponents` views: the file shelf and the volume glyph.
    public var components: Components

    /// Boards of widgets: the empty board and the board's editor in Settings.
    public var widgets: Widgets

    /// The line under the host name on ``NookPlaceholderHomeView``.
    public var placeholderMessage: String

    public init(
        settingsBreadcrumb: String = "Settings",
        keepOpenHelp: String = "Stay expanded after hover",
        settingsHelp: String = "Settings",
        dismissHelp: String = "Dismiss",
        topBar: TopBar = TopBar(),
        settings: Settings = Settings(),
        appearance: Appearance = Appearance(),
        display: Display = Display(),
        shortcut: Shortcut = Shortcut(),
        menuBar: MenuBar = MenuBar(),
        components: Components = Components(),
        widgets: Widgets = Widgets(),
        placeholderMessage: String = "Register your own view with NookConfiguration to start building."
    ) {
        self.settingsBreadcrumb = settingsBreadcrumb
        self.keepOpenHelp = keepOpenHelp
        self.settingsHelp = settingsHelp
        self.dismissHelp = dismissHelp
        self.topBar = topBar
        self.settings = settings
        self.appearance = appearance
        self.display = display
        self.shortcut = shortcut
        self.menuBar = menuBar
        self.components = components
        self.widgets = widgets
        self.placeholderMessage = placeholderMessage
    }

    /// The framework-default English strings.
    public static let `default` = NookChromeLabels()

    /// `template` with every `{key}` placeholder replaced by its value, in one pass, so a
    /// value that itself contains braces is inserted as written. Placeholders with no value
    /// are left as written.
    ///
    /// ```swift
    /// NookChromeLabels.fill("Show {host}", ["host": "Constellation"])  // "Show Constellation"
    /// ```
    public static func fill(_ template: String, _ values: [String: String]) -> String {
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}"),
                let value = values[String(rest[afterOpen..<close])]
            else {
                result.append("{")
                rest = rest[afterOpen...]
                continue
            }
            result += value
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

private struct NookChromeLabelsKey: EnvironmentKey {
    static let defaultValue: NookChromeLabels = .default
}

extension EnvironmentValues {
    /// Host-overridable chrome strings. See ``NookChromeLabels``.
    public var nookChromeLabels: NookChromeLabels {
        get { self[NookChromeLabelsKey.self] }
        set { self[NookChromeLabelsKey.self] = newValue }
    }
}
