// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import SwiftUI

/// Picks which display the nook appears on - the body of the built-in Settings screen's
/// Display group, for a host that builds its own Settings screen. Writes through
/// ``AppState/replaceDisplayPreference(_:)``, so the nook moves at once.
///
/// Offers the two stable modes (built-in / main) plus one entry per attached display.
/// The display list refreshes on connect/disconnect; a previously-chosen display that's
/// since been unplugged stays selectable as a "(not connected)" row so the preference
/// isn't silently lost - the resolver falls back to the built-in display until it returns.
///
/// ```swift
/// NookSettingsGroup("Display") { NookDisplaySettingsSection(appState: appState) }
/// ```
public struct NookDisplaySettingsSection: View {
    @ObservedObject public var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookChromeLabels) private var labels

    @State private var displays: [NookScreenLocator.DisplayInfo] = NookScreenLocator.connectedDisplays()

    public init(appState: AppState) {
        self.appState = appState
    }

    private static let builtInTag = "builtIn"
    private static let mainTag = "main"
    private static let specificTagPrefix = "uuid:"

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
            Picker(labels.display.pickerTitle, selection: selectionBinding) {
                Text(labels.display.builtIn).tag(Self.builtInTag)
                Text(labels.display.main).tag(Self.mainTag)
                if !specificOptions.isEmpty {
                    Divider()
                    ForEach(specificOptions, id: \.tag) { option in
                        Text(option.label).tag(option.tag)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(labels.display.pickerTitle)

            Text(descriptionText)
                .font(typography.settingsCaption)
                .foregroundStyle(theme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            displays = NookScreenLocator.connectedDisplays()
        }
    }

    private var descriptionText: String {
        switch appState.displayPreference.mode {
            case .builtIn:
                return labels.display.builtInDetail
            case .main:
                return labels.display.mainDetail
            case .specific:
                let connected =
                    appState.displayPreference.displayUUID
                    .map { uuid in displays.contains { $0.uuid == uuid } } ?? false
                return connected
                    ? labels.display.specificDetail
                    : labels.display.specificDisconnectedDetail
        }
    }

    /// One option per attached display, plus a trailing "(not connected)" row when the
    /// saved `.specific` display isn't currently attached, so the picker can still show it.
    private var specificOptions: [(tag: String, label: String)] {
        var options = displays.map { display -> (tag: String, label: String) in
            (tag: Self.specificTagPrefix + display.uuid, label: display.name)
        }
        if appState.displayPreference.mode == .specific,
            let uuid = appState.displayPreference.displayUUID,
            !displays.contains(where: { $0.uuid == uuid })
        {
            options.append((tag: Self.specificTagPrefix + uuid, label: labels.display.savedDisconnected))
        }
        return options
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: {
                let preference = appState.displayPreference
                switch preference.mode {
                    case .builtIn: return Self.builtInTag
                    case .main: return Self.mainTag
                    case .specific: return Self.specificTagPrefix + (preference.displayUUID ?? "")
                }
            },
            set: { tag in
                let next: NookDisplayPreference
                if tag == Self.builtInTag {
                    next = .builtIn
                } else if tag == Self.mainTag {
                    next = .main
                } else if tag.hasPrefix(Self.specificTagPrefix) {
                    next = .specific(String(tag.dropFirst(Self.specificTagPrefix.count)))
                } else {
                    next = .default
                }
                appState.replaceDisplayPreference(next)
            }
        )
    }
}
