// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Turns the names in the settings model into the words a proposal shows.
///
/// A row in a proposal reads "Width 520 -> 420 pt", not
/// "settings.panel.expandedWidth 520 -> 420", so every field needs a short label and every choice
/// needs a name. Most come out of the property name itself; the rest are named here, in one place,
/// in the words the controls window already uses for the same setting.
enum AssistantWording {
    /// `expandedWidth` as `Expanded width`: the first word capitalized, the rest lowercased, split
    /// where the case changes.
    static func sentenceCase(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character).lowercased()
            } else {
                current += String(character)
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        guard var first = words.first else { return name }
        first = first.prefix(1).uppercased() + first.dropFirst()
        return ([first] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }

    /// What a choice is called in a proposal. `liquidGlass` reads as `Liquid Glass`, Apple's own
    /// name for the material; everything else follows the property-name rule.
    static func choiceTitle(_ value: String) -> String {
        switch value {
            case "liquidGlass": "Liquid Glass"
            case "followSystem": "Follow the system"
            case "roundedRectangle": "Rounded rectangle"
            case "contentColumn": "Content column"
            case "keepOpen": "Lock"
            case "settings": "Gear"
            default: sentenceCase(value)
        }
    }
}

extension AssistantField {
    /// The field's name in a proposal row, kept short because the row already sits under the name
    /// of its group. Where the controls window has a word for a setting, that word wins.
    public var title: String {
        let keys = path.components.compactMap { component -> String? in
            guard case .key(let name) = component else { return nil }
            return name
        }
        guard let last = keys.last else { return path.text }

        // A font or a spring is one control holding two values, so its row has to say which role
        // it belongs to: "Top bar label size" rather than a second, indistinguishable "Size".
        if keys.count == 4, keys[1] == "typography" || keys[1] == "motion" {
            let role = AssistantWording.sentenceCase(keys[2])
            return "\(role) \(AssistantWording.sentenceCase(last).lowercased())"
        }

        switch path.text {
            case "appearance.chromePalette": return "Palette"
            case "appearance.surfaceStyle": return "Surface"
            case "appearance.hapticFeedbackEnabled": return "Haptics"
            case "appearance.accentPreset": return "Accent"
            case "appearance.backdropStrength": return "Backdrop"

            case "settings.theme.fontDesign": return "Type design"

            case "settings.panel.expandedWidth": return "Width"
            case "settings.panel.topCornerRadius": return "Top corners"
            case "settings.panel.bottomCornerRadius": return "Bottom corners"
            case "settings.panel.insetTop": return "Top inset"
            case "settings.panel.insetBottom": return "Bottom inset"
            case "settings.panel.insetLeading": return "Leading inset"
            case "settings.panel.insetTrailing": return "Trailing inset"

            case "settings.metrics.expandedColumnSpacing": return "Row spacing"
            case "settings.metrics.headerIconSize": return "Header icons"
            case "settings.metrics.headerIconCornerRadius": return "Icon corners"
            case "settings.metrics.compactSlotSize": return "Compact slots"
            case "settings.metrics.bannerCornerRadius": return "Banner corners"

            case "settings.topBar.showsTopBar": return "Top bar"
            case "settings.topBar.showsSettings": return "Settings screen"
            case "settings.topBar.showsKeepOpenButton": return "Lock button"
            case "settings.topBar.showsSettingsButton": return "Gear button"
            case "settings.topBar.showsStatusBanner": return "Status banner"
            case "settings.topBar.notchAccessories": return "Header beside the notch"
            case "settings.topBar.leadingTitle": return "Title"
            case "settings.topBar.leadingIcon": return "Icon"

            case "settings.companionDefaults.size": return "Companion size"
            case "settings.companionDefaults.presence": return "Companions appear"
            case "settings.companionDefaults.fade": return "Companion fade"
            case "settings.companionDefaults.stroke": return "Companion edges"
            case "settings.companionDefaults.shadow": return "Companion shadows"
            case "settings.companionDefaults.hover": return "Companion hover"

            case "settings.companions[].id": return "Name"
            case "settings.companions[].anchor": return "Side"
            case "settings.companions[].rowAlignment": return "Row alignment"
            case "settings.companions[].visibility": return "Shown"
            case "settings.companions[].outline": return "Shape"
            case "settings.companions[].cornerRadius": return "Corners"
            case "settings.companions[].presence": return "Appears"
            case "settings.companions[].stroke": return "Edge"
            case "settings.companions[].hidesInSettings": return "Hidden in Settings"

            case "settings.rimGlow.glowRadius": return "Glow"

            case "settings.scrollEdgeFade.isEnabled": return "Scroll edge fade"
            case "settings.scrollEdgeFade.top": return "Fade at the top"
            case "settings.scrollEdgeFade.bottom": return "Fade at the bottom"
            case "settings.scrollEdgeFade.leading": return "Fade at the leading edge"
            case "settings.scrollEdgeFade.trailing": return "Fade at the trailing edge"
            case "settings.scrollEdgeFade.length": return "Fade length"

            case "settings.behavior.hoverKeepsVisible": return "Hover keeps it open"

            default: return AssistantWording.sentenceCase(last)
        }
    }
}
