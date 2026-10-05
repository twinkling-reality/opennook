// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// Every string the framework draws comes from `NookChromeLabels`, with today's English as
/// the default, and the templates fill their placeholders.
final class NookChromeLabelsTests: XCTestCase {
    /// The defaults are the strings the framework drew before they were labels, except that
    /// the em dashes became " - ".
    func testDefaultsReproduceTheFrameworkStrings() {
        let labels = NookChromeLabels.default

        XCTAssertEqual(labels.topBar.switchModuleHelp, "Switch module")
        XCTAssertEqual(labels.topBar.moduleAttention("Clock"), "Clock  •")
        XCTAssertEqual(labels.placeholderMessage, "Register your own view with NookConfiguration to start building.")

        let settings = labels.settings
        XCTAssertEqual(settings.appearanceTitle, "Appearance")
        XCTAssertEqual(settings.displayTitle, "Display")
        XCTAssertEqual(settings.shortcutTitle, "Shortcut & nook")
        XCTAssertEqual(settings.dataTitle, "Data")
        XCTAssertEqual(settings.aboutTitle, "About")
        XCTAssertEqual(settings.previewBannerTitle, "Preview status banner")
        XCTAssertEqual(settings.previewBannerDetail, "Shows the transient message channel under the top bar")
        XCTAssertEqual(settings.previewBannerMessage, "Something went wrong - try again.")
        XCTAssertEqual(settings.resetTitle, "Reset All Settings")
        XCTAssertEqual(settings.resetDetail, "Theme, surface, layout, display, hotkey, stay expanded")
        XCTAssertEqual(settings.version("0.4.0"), "v0.4.0")
        XCTAssertEqual(
            settings.defaultTagline,
            "A demo notch app built with OpenNook, an open-source framework for macOS notch apps."
        )

        let appearance = labels.appearance
        XCTAssertEqual(appearance.themeTitle, "Theme")
        XCTAssertEqual(appearance.themeAccessibilityLabel, "Theme")
        XCTAssertEqual(appearance.themeFollowSystem, "Match Mac")
        XCTAssertEqual(appearance.themeDark, "Dark")
        XCTAssertEqual(appearance.themeLight, "Light")
        XCTAssertEqual(appearance.surfaceTitle, "Surface")
        XCTAssertEqual(appearance.surfaceAccessibilityLabel, "Chrome surface")
        XCTAssertEqual(appearance.surfaceSolid, "Solid")
        XCTAssertEqual(appearance.surfaceTranslucent, "Translucent")
        XCTAssertEqual(appearance.surfaceLiquidGlass, "Liquid Glass")
        XCTAssertEqual(
            appearance.surfaceSolidDetail,
            "Solid paints the chrome the same color as the notch - true black on dark, true white on light."
        )
        XCTAssertEqual(
            appearance.surfaceTranslucentDetail,
            "Translucent shows the wallpaper through a frosted material."
        )
        XCTAssertEqual(
            appearance.surfaceLiquidGlassDetail,
            "Liquid Glass refracts the wallpaper through Apple's glass material on macOS 26, "
                + "with a frosted-glass fallback on earlier versions."
        )
        XCTAssertEqual(appearance.layoutTitle, "Layout")
        XCTAssertEqual(appearance.layoutAccessibilityLabel, "Chrome layout")
        XCTAssertEqual(appearance.layoutAuto, "Auto")
        XCTAssertEqual(appearance.layoutNotch, "Notch")
        XCTAssertEqual(appearance.layoutFloating, "Floating")
        XCTAssertEqual(
            appearance.layoutAutoDetail,
            "Auto uses the notch shape on a notched display and a floating panel on any other."
        )
        XCTAssertEqual(
            appearance.layoutNotchDetail,
            "Notch always uses the notch shape, even on a display without one."
        )
        XCTAssertEqual(
            appearance.layoutFloatingDetail,
            "Floating always shows a free-standing panel below the menu bar."
        )
        XCTAssertEqual(appearance.accentTitle, "Accent")
        for preset in NookAccentPreset.allCases {
            XCTAssertEqual(appearance.accentName(preset), preset.displayName)
        }
        XCTAssertEqual(appearance.glassStrengthTitle, "Glass strength")
        XCTAssertEqual(appearance.translucencyStrengthTitle, "Translucency strength")
        XCTAssertEqual(appearance.strengthDetail, "Lower shows more wallpaper through the chrome.")

        let display = labels.display
        XCTAssertEqual(display.pickerTitle, "Display")
        XCTAssertEqual(display.builtIn, "Built-in display")
        XCTAssertEqual(display.main, "Display with active menu bar")
        XCTAssertEqual(display.savedDisconnected, "Saved display (not connected)")
        XCTAssertEqual(display.builtInDetail, "The chrome stays on the built-in (notched) display.")
        XCTAssertEqual(display.mainDetail, "The chrome follows the display that currently hosts the menu bar.")
        XCTAssertEqual(display.specificDetail, "The chrome is pinned to a specific display.")
        XCTAssertEqual(
            display.specificDisconnectedDetail,
            "The chosen display isn't connected - using the built-in display until it returns."
        )

        let shortcut = labels.shortcut
        XCTAssertEqual(shortcut.showHost("Nook"), "Show Nook")
        XCTAssertEqual(shortcut.changeHint, "Global shortcut - click to change")
        XCTAssertEqual(shortcut.recordingHint, "Press a shortcut - Esc to cancel")
        XCTAssertEqual(shortcut.listening, "Listening…")
        XCTAssertEqual(
            shortcut.rowAccessibilityLabel(host: "Nook", keys: ["⌥", "⌘", ";"]),
            "Show Nook shortcut, currently ⌥ ⌘ ;"
        )
        XCTAssertEqual(shortcut.rowAccessibilityHint, "Activates to record a new shortcut")
        XCTAssertEqual(shortcut.unavailable("⌥⌘;"), "⌥⌘; is unavailable - another app may be using it.")
        XCTAssertEqual(shortcut.cycleModulesName, "Cycle Modules")
        XCTAssertEqual(shortcut.stayExpandedTitle, "Stay expanded")
        XCTAssertEqual(shortcut.stayExpandedOn, "On - nook stays open after hover ends")
        XCTAssertEqual(shortcut.stayExpandedOff, "Off - closes when the pointer leaves")
        XCTAssertEqual(shortcut.hapticTitle, "Haptic feedback")
        XCTAssertEqual(shortcut.hapticOn, "On - trackpad pulse on confirmation")
        XCTAssertEqual(shortcut.hapticOff, "Off - silent confirmation")

        let menuBar = labels.menuBar
        XCTAssertEqual(menuBar.showHost("Nook"), "Show Nook")
        XCTAssertEqual(menuBar.settings, "Settings…")
        XCTAssertEqual(menuBar.toggleStayExpanded, "Toggle Stay Expanded")
        XCTAssertEqual(menuBar.modules, "Modules")
        XCTAssertEqual(menuBar.quit, "Quit")

        let components = labels.components
        XCTAssertEqual(components.shelfDropHint, "Drop files onto the notch to shelve them")
        XCTAssertEqual(components.shelfDropOrImportHint, "Drop files here, or click to import")
        XCTAssertEqual(components.shelfFileCount(1), "1 file")
        XCTAssertEqual(components.shelfFileCount(3), "3 files")
        XCTAssertEqual(components.shelfImportHelp, "Import files")
        XCTAssertEqual(components.shelfClear, "Clear")
        XCTAssertEqual(components.shelfRemoveHelp, "Remove from shelf")
        XCTAssertEqual(components.volumeMuted, "Volume muted")
        XCTAssertEqual(components.volumeLevel(percent: 40), "Volume 40 percent")
    }

    /// No default string carries an em dash - the one visible change of the labels pass.
    func testNoDefaultContainsAnEmDash() {
        func strings(in value: Any) -> [String] {
            if let string = value as? String { return [string] }
            if let names = value as? [NookAccentPreset: String] { return Array(names.values) }
            return Mirror(reflecting: value).children.flatMap { strings(in: $0.value) }
        }
        let all = strings(in: NookChromeLabels.default)
        XCTAssertGreaterThan(all.count, 70)
        for string in all {
            XCTAssertFalse(string.contains("\u{2014}"), string)
        }
    }

    /// The failure message the Settings screen shows by default is the label's.
    func testHotkeyFailureMessageUsesTheDefaultLabel() {
        let failure = HotkeyRegistrationFailure(shortcutName: "Cycle Modules", combination: "⌃⌥C")
        XCTAssertEqual(failure.message, "⌃⌥C is unavailable - another app may be using it.")
        XCTAssertEqual(
            NookChromeLabels.default.shortcut.failureAccessibilityLabel(failure),
            "Cycle Modules shortcut unavailable: ⌃⌥C is unavailable - another app may be using it."
        )
    }

    /// A host's templates move and repeat the values; an accent the host left out keeps its
    /// own name.
    func testHostTemplatesAndNames() {
        var labels = NookChromeLabels()
        labels.shortcut.showHostFormat = "{host} anzeigen"
        labels.shortcut.unavailableFormat = "{combination}: belegt"
        labels.components.shelfFileCountOtherFormat = "{count} Dateien"
        labels.menuBar.showHostFormat = "{host} - {host}"
        labels.appearance.accentNames = [.teal: "Petrol"]

        XCTAssertEqual(labels.shortcut.showHost("Nook"), "Nook anzeigen")
        XCTAssertEqual(
            labels.shortcut.failureAccessibilityLabel(
                HotkeyRegistrationFailure(shortcutName: "Clock", combination: "⌃C")
            ),
            "Clock shortcut unavailable: ⌃C: belegt"
        )
        XCTAssertEqual(labels.components.shelfFileCount(2), "2 Dateien")
        XCTAssertEqual(labels.menuBar.showHost("Nook"), "Nook - Nook")
        XCTAssertEqual(labels.appearance.accentName(.teal), "Petrol")
        XCTAssertEqual(labels.appearance.accentName(.rose), "Rose")
        XCTAssertNotEqual(labels, .default)
    }

    func testFillReplacesKnownPlaceholdersInOnePass() {
        XCTAssertEqual(NookChromeLabels.fill("Show {host}", ["host": "Nook"]), "Show Nook")
        // A value's braces are inserted as written, not filled again.
        XCTAssertEqual(
            NookChromeLabels.fill("{a} and {b}", ["a": "{b}", "b": "two"]),
            "{b} and two"
        )
        // Unknown and unclosed placeholders stay as written.
        XCTAssertEqual(NookChromeLabels.fill("{x} {host", ["host": "Nook"]), "{x} {host")
        XCTAssertEqual(NookChromeLabels.fill("no placeholders", [:]), "no placeholders")
        XCTAssertEqual(NookChromeLabels.fill("{}{host}", ["host": "N"]), "{}N")
    }

    /// The labels the chrome injects are the configuration's, so every view that reads
    /// `\.nookChromeLabels` draws the host's strings.
    func testConfigurationCarriesTheGroups() {
        var configuration = NookConfiguration()
        XCTAssertEqual(configuration.labels, .default)
        configuration.labels.settings.appearanceTitle = "Look"
        configuration.labels.menuBar.quit = "Quit Constellation"
        XCTAssertEqual(configuration.labels.settings.appearanceTitle, "Look")
        XCTAssertEqual(configuration.labels.menuBar.quit, "Quit Constellation")
    }
}
