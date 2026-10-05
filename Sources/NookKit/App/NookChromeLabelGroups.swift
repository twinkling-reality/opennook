// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

extension NookChromeLabels {
    /// Top-bar strings beyond the breadcrumb and the lock and gear tooltips.
    public struct TopBar: Sendable, Equatable {
        /// Tooltip on the in-surface module switcher.
        public var switchModuleHelp = "Switch module"

        /// A module that asked for attention, in the switcher's list. Placeholder: `{module}`,
        /// the module's display name.
        public var moduleAttentionFormat = "{module}  •"

        public init() {}

        /// ``moduleAttentionFormat`` for `module`.
        public func moduleAttention(_ module: String) -> String {
            NookChromeLabels.fill(moduleAttentionFormat, ["module": module])
        }
    }

    /// The built-in Settings screen's group titles and the Data and About groups.
    public struct Settings: Sendable, Equatable {
        /// The Appearance group's title.
        public var appearanceTitle = "Appearance"
        /// The Display group's title.
        public var displayTitle = "Display"
        /// The Shortcut & nook group's title.
        public var shortcutTitle = "Shortcut & nook"
        /// The Data group's title.
        public var dataTitle = "Data"
        /// The About group's title.
        public var aboutTitle = "About"

        /// The Data group's banner preview row.
        public var previewBannerTitle = "Preview status banner"
        /// The banner preview row's detail line.
        public var previewBannerDetail = "Shows the transient message channel under the top bar"
        /// The message the banner preview posts.
        public var previewBannerMessage = "Something went wrong - try again."

        /// The reset row (``NookResetSettingsSection``).
        public var resetTitle = "Reset All Settings"
        /// The reset row's detail line.
        public var resetDetail = "Theme, surface, layout, display, hotkey, stay expanded"

        /// The version beside the host name in About. Placeholder: `{version}`.
        public var versionFormat = "v{version}"
        /// The About tagline when the host set no ``NookHostBranding/hostTagline``.
        public var defaultTagline =
            "A demo notch app built with OpenNook, an open-source framework for macOS notch apps."

        public init() {}

        /// ``versionFormat`` for `version`.
        public func version(_ version: String) -> String {
            NookChromeLabels.fill(versionFormat, ["version": version])
        }
    }

    /// The Appearance group (``NookAppearanceSettingsSection``).
    public struct Appearance: Sendable, Equatable {
        /// The Theme picker's label.
        public var themeTitle = "Theme"
        /// The Theme picker's accessibility label.
        public var themeAccessibilityLabel = "Theme"
        /// The Theme option that follows the Mac's appearance.
        public var themeFollowSystem = "Match Mac"
        /// The dark Theme option.
        public var themeDark = "Dark"
        /// The light Theme option.
        public var themeLight = "Light"

        /// The Surface picker's label.
        public var surfaceTitle = "Surface"
        /// The Surface picker's accessibility label.
        public var surfaceAccessibilityLabel = "Chrome surface"
        /// The solid Surface option.
        public var surfaceSolid = "Solid"
        /// The translucent Surface option.
        public var surfaceTranslucent = "Translucent"
        /// The Liquid Glass Surface option.
        public var surfaceLiquidGlass = "Liquid Glass"
        /// The caption under the Surface picker while Solid is chosen.
        public var surfaceSolidDetail =
            "Solid paints the chrome the same color as the notch - true black on dark, true white on light."
        /// The caption under the Surface picker while Translucent is chosen.
        public var surfaceTranslucentDetail = "Translucent shows the wallpaper through a frosted material."
        /// The caption under the Surface picker while Liquid Glass is chosen.
        public var surfaceLiquidGlassDetail =
            "Liquid Glass refracts the wallpaper through Apple's glass material on macOS 26, "
            + "with a frosted-glass fallback on earlier versions."

        /// The Layout picker's label.
        public var layoutTitle = "Layout"
        /// The Layout picker's accessibility label.
        public var layoutAccessibilityLabel = "Chrome layout"
        /// The automatic Layout option.
        public var layoutAuto = "Auto"
        /// The notch Layout option.
        public var layoutNotch = "Notch"
        /// The floating Layout option.
        public var layoutFloating = "Floating"
        /// The caption under the Layout picker while Auto is chosen.
        public var layoutAutoDetail =
            "Auto uses the notch shape on a notched display and a floating panel on any other."
        /// The caption under the Layout picker while Notch is chosen.
        public var layoutNotchDetail = "Notch always uses the notch shape, even on a display without one."
        /// The caption under the Layout picker while Floating is chosen.
        public var layoutFloatingDetail = "Floating always shows a free-standing panel below the menu bar."

        /// The Accent swatches' label.
        public var accentTitle = "Accent"
        /// Each accent swatch's accessibility label. A preset missing here uses its
        /// ``NookAccentPreset/displayName``.
        public var accentNames: [NookAccentPreset: String] = Dictionary(
            uniqueKeysWithValues: NookAccentPreset.allCases.map { ($0, $0.displayName) }
        )

        /// The strength slider's label while Liquid Glass is chosen.
        public var glassStrengthTitle = "Glass strength"
        /// The strength slider's label while Translucent is chosen.
        public var translucencyStrengthTitle = "Translucency strength"
        /// The caption under the strength slider.
        public var strengthDetail = "Lower shows more wallpaper through the chrome."

        public init() {}

        /// The accessibility label for `preset`'s swatch.
        public func accentName(_ preset: NookAccentPreset) -> String {
            accentNames[preset] ?? preset.displayName
        }
    }

    /// The Display group (``NookDisplaySettingsSection``).
    public struct Display: Sendable, Equatable {
        /// The display picker's title and accessibility label.
        public var pickerTitle = "Display"
        /// The option that keeps the nook on the built-in display.
        public var builtIn = "Built-in display"
        /// The option that follows the display with the active menu bar.
        public var main = "Display with active menu bar"
        /// The option for a saved display that is not connected.
        public var savedDisconnected = "Saved display (not connected)"
        /// The caption while the built-in display is chosen.
        public var builtInDetail = "The chrome stays on the built-in (notched) display."
        /// The caption while the menu-bar display is chosen.
        public var mainDetail = "The chrome follows the display that currently hosts the menu bar."
        /// The caption while a specific, connected display is chosen.
        public var specificDetail = "The chrome is pinned to a specific display."
        /// The caption while a specific display is chosen but not connected.
        public var specificDisconnectedDetail =
            "The chosen display isn't connected - using the built-in display until it returns."

        public init() {}
    }

    /// The Shortcut & nook group (``NookShortcutSettingsSection``).
    public struct Shortcut: Sendable, Equatable {
        /// The global shortcut row's title. Placeholder: `{host}`, the host name.
        public var showHostFormat = "Show {host}"
        /// The shortcut row's hint while idle.
        public var changeHint = "Global shortcut - click to change"
        /// The shortcut row's hint while recording.
        public var recordingHint = "Press a shortcut - Esc to cancel"
        /// The recorder's label while it waits for a key combination.
        public var listening = "Listening…"
        /// The shortcut row's accessibility label. Placeholders: `{host}`, the host name;
        /// `{keys}`, the current combination's symbols separated by spaces.
        public var rowAccessibilityFormat = "Show {host} shortcut, currently {keys}"
        /// The shortcut row's accessibility hint.
        public var rowAccessibilityHint = "Activates to record a new shortcut"
        /// A shortcut that failed to register. Placeholder: `{combination}`.
        public var unavailableFormat = "{combination} is unavailable - another app may be using it."
        /// The accessibility label of a failed shortcut's row. Placeholders: `{shortcut}`, the
        /// shortcut's name; `{message}`, the filled ``unavailableFormat``.
        public var failureAccessibilityFormat = "{shortcut} shortcut unavailable: {message}"
        /// The module-cycle shortcut's name, shown when it fails to register.
        public var cycleModulesName = "Cycle Modules"

        /// The "Stay expanded" row's title.
        public var stayExpandedTitle = "Stay expanded"
        /// The "Stay expanded" row's detail while on.
        public var stayExpandedOn = "On - nook stays open after hover ends"
        /// The "Stay expanded" row's detail while off.
        public var stayExpandedOff = "Off - closes when the pointer leaves"
        /// The haptic feedback row's title.
        public var hapticTitle = "Haptic feedback"
        /// The haptic feedback row's detail while on.
        public var hapticOn = "On - trackpad pulse on confirmation"
        /// The haptic feedback row's detail while off.
        public var hapticOff = "Off - silent confirmation"

        public init() {}

        /// ``showHostFormat`` for `host`.
        public func showHost(_ host: String) -> String {
            NookChromeLabels.fill(showHostFormat, ["host": host])
        }

        /// ``rowAccessibilityFormat`` for `host` and the combination's `keys`.
        public func rowAccessibilityLabel(host: String, keys: [String]) -> String {
            NookChromeLabels.fill(rowAccessibilityFormat, ["host": host, "keys": keys.joined(separator: " ")])
        }

        /// ``unavailableFormat`` for `combination`.
        public func unavailable(_ combination: String) -> String {
            NookChromeLabels.fill(unavailableFormat, ["combination": combination])
        }

        /// ``failureAccessibilityFormat`` for `failure`.
        public func failureAccessibilityLabel(_ failure: HotkeyRegistrationFailure) -> String {
            NookChromeLabels.fill(
                failureAccessibilityFormat,
                ["shortcut": failure.shortcutName, "message": unavailable(failure.combination)]
            )
        }
    }

    /// The framework's menu-bar item.
    public struct MenuBar: Sendable, Equatable {
        /// The item that shows the nook. Placeholder: `{host}`, the host name.
        public var showHostFormat = "Show {host}"
        /// The item that opens Settings.
        public var settings = "Settings…"
        /// The item that flips "Stay expanded".
        public var toggleStayExpanded = "Toggle Stay Expanded"
        /// The header over the module list.
        public var modules = "Modules"
        /// The item that quits the app.
        public var quit = "Quit"

        public init() {}

        /// ``showHostFormat`` for `host`.
        public func showHost(_ host: String) -> String {
            NookChromeLabels.fill(showHostFormat, ["host": host])
        }
    }

    /// The `NookComponents` views.
    public struct Components: Sendable, Equatable {
        /// The empty shelf's caption when it has no import action.
        public var shelfDropHint = "Drop files onto the notch to shelve them"
        /// The empty shelf's caption and tooltip when it has an import action.
        public var shelfDropOrImportHint = "Drop files here, or click to import"
        /// The shelf header for one file. Placeholder: `{count}`.
        public var shelfFileCountOneFormat = "{count} file"
        /// The shelf header for several files. Placeholder: `{count}`.
        public var shelfFileCountOtherFormat = "{count} files"
        /// Tooltip on the shelf's import button.
        public var shelfImportHelp = "Import files"
        /// The shelf's clear button.
        public var shelfClear = "Clear"
        /// Tooltip on a shelved file's remove button.
        public var shelfRemoveHelp = "Remove from shelf"
        /// The volume glyph's accessibility label while muted.
        public var volumeMuted = "Volume muted"
        /// The volume glyph's accessibility label. Placeholder: `{percent}`, 0 to 100.
        public var volumeLevelFormat = "Volume {percent} percent"

        public init() {}

        /// The shelf header for `count` files.
        public func shelfFileCount(_ count: Int) -> String {
            NookChromeLabels.fill(
                count == 1 ? shelfFileCountOneFormat : shelfFileCountOtherFormat,
                ["count": count.formatted()]
            )
        }

        /// ``volumeLevelFormat`` for `percent`.
        public func volumeLevel(percent: Int) -> String {
            NookChromeLabels.fill(volumeLevelFormat, ["percent": String(percent)])
        }
    }
}
