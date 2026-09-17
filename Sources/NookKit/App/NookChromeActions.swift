// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// The chrome's own actions - what the top bar's keep-open lock and Settings gear do, the
/// Settings reset, and handing the keyboard to the nook and back - for host views that place
/// those controls somewhere else, such as a companion surface or a Settings screen of their own.
///
/// Read it from the environment in home, compact, or companion content:
///
/// ```swift
/// @Environment(\.nookChromeActions) private var chromeActions
///
/// Button("Settings", systemImage: "gearshape") { chromeActions.toggleSettings() }
/// ```
///
/// Or use the ready-made ``NookKeepOpenButton`` and ``NookSettingsButton``. To move the
/// controls out of the top bar entirely, turn off
/// ``NookTopBarConfiguration/showsKeepOpenButton`` and
/// ``NookTopBarConfiguration/showsSettingsButton`` and register a companion that shows them.
///
/// `Sendable`, with `@Sendable @MainActor` closures, like the configuration closures: the
/// actions drive the main-actor coordinator.
public struct NookChromeActions: Sendable {
    /// Flips "stay expanded" - the keep-open lock - and applies it to the surface
    /// immediately. The choice persists, like the lock's.
    public var toggleKeepOpen: @Sendable @MainActor () -> Void

    /// Switches the expanded surface between the home view and Settings. When the nook is
    /// collapsed it expands straight into Settings. Does nothing when the host disabled
    /// Settings (``NookTopBarConfiguration/showsSettings``).
    public var toggleSettings: @Sendable @MainActor () -> Void

    /// Collapses the nook to its compact pill.
    public var collapse: @Sendable @MainActor () -> Void

    /// Returns appearance, the global shortcut, and the display to the host's defaults and
    /// forgets the person's choices - what Settings' "Reset All Settings" does. See
    /// ``AppCoordinator/resetAllSettingsToDefaults()``.
    public var resetSettings: @Sendable @MainActor () -> Void

    /// Gives the nook the keyboard, so typing reaches its focused text input without a click -
    /// for a field focused when it appears, say. See ``AppCoordinator/takeNookKeyboardFocus()``.
    public var takeKeyboardFocus: @Sendable @MainActor () -> Void

    /// Hands the keyboard back to the app in front. See
    /// ``AppCoordinator/releaseNookKeyboardFocus()``.
    public var releaseKeyboardFocus: @Sendable @MainActor () -> Void

    public init(
        toggleKeepOpen: @escaping @Sendable @MainActor () -> Void,
        toggleSettings: @escaping @Sendable @MainActor () -> Void,
        collapse: @escaping @Sendable @MainActor () -> Void,
        resetSettings: @escaping @Sendable @MainActor () -> Void = {},
        takeKeyboardFocus: @escaping @Sendable @MainActor () -> Void = {},
        releaseKeyboardFocus: @escaping @Sendable @MainActor () -> Void = {}
    ) {
        self.toggleKeepOpen = toggleKeepOpen
        self.toggleSettings = toggleSettings
        self.collapse = collapse
        self.resetSettings = resetSettings
        self.takeKeyboardFocus = takeKeyboardFocus
        self.releaseKeyboardFocus = releaseKeyboardFocus
    }

    /// Actions that do nothing - the value outside a live chrome, such as in a preview.
    public static let inert = NookChromeActions(toggleKeepOpen: {}, toggleSettings: {}, collapse: {})
}

private struct NookChromeActionsKey: EnvironmentKey {
    static let defaultValue: NookChromeActions = .inert
}

extension EnvironmentValues {
    /// The live chrome's actions. See ``NookChromeActions``. Inert outside the chrome.
    public var nookChromeActions: NookChromeActions {
        get { self[NookChromeActionsKey.self] }
        set { self[NookChromeActionsKey.self] = newValue }
    }
}

/// The chrome's keep-open control - the lock the top bar shows - as a standalone view, for
/// placing it outside the top bar (see ``NookChromeActions``). It behaves exactly like the top
/// bar's lock, in the chrome's palette; inside a companion it takes the companion's control
/// size (`\.nookCompanionSize`), so it lines up with the controls beside it.
///
/// Use it inside chrome content - home, compact, or companion - which supplies ``AppState``
/// as an environment object.
public struct NookKeepOpenButton: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookChromeActions) private var actions
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeLabels) private var labels
    @Environment(\.nookCompanionSize) private var companionSize

    public init() {}

    public var body: some View {
        HeaderIcon(
            systemName: appState.keepNookOpen ? "lock.fill" : "lock.open",
            isActive: appState.keepNookOpen,
            activeColor: theme.accent,
            help: labels.keepOpenHelp,
            geometry: companionSize.map(HeaderGlyphGeometry.companion)
        ) {
            actions.toggleKeepOpen()
        }
        .accessibilityLabel(labels.keepOpenHelp)
        .accessibilityAddTraits(appState.keepNookOpen ? .isSelected : [])
    }
}

/// The chrome's Settings control - the gear the top bar shows - as a standalone view, for
/// placing it outside the top bar (see ``NookChromeActions``). It behaves exactly like the top
/// bar's gear, in the chrome's palette; inside a companion it takes the companion's control
/// size (`\.nookCompanionSize`), so it lines up with the controls beside it.
///
/// Use it inside chrome content - home, compact, or companion - which supplies ``AppState``
/// as an environment object. A companion hosting it should pass `hidesInSettings: false`,
/// so the control that leaves Settings stays on screen while Settings is.
public struct NookSettingsButton: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookChromeActions) private var actions
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeLabels) private var labels
    @Environment(\.nookCompanionSize) private var companionSize

    public init() {}

    public var body: some View {
        HeaderIcon(
            systemName: "gearshape",
            isActive: appState.isSettingsView,
            activeColor: theme.accent,
            help: labels.settingsHelp,
            geometry: companionSize.map(HeaderGlyphGeometry.companion)
        ) {
            actions.toggleSettings()
        }
        .accessibilityLabel(labels.settingsHelp)
        .accessibilityAddTraits(appState.isSettingsView ? .isSelected : [])
    }
}
