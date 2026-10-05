// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// What a host top bar needs to stand in for the framework's: the bar's state and the
/// actions behind the lock, the gear, and the leading cluster's back control. Handed to
/// ``NookTopBarConfiguration/content``.
///
/// ```swift
/// configuration.setTopBar { bar in
///     HStack {
///         if bar.canGoBack {
///             Button("Back", systemImage: "chevron.left") { bar.goBack() }
///         }
///         Text(bar.breadcrumb ?? bar.title)
///         Spacer()
///         Button(bar.isKeepOpen ? "Unpin" : "Pin") { bar.toggleKeepOpen() }
///         if bar.showsSettings {
///             Button("Settings", systemImage: "gearshape") { bar.toggleSettings() }
///         }
///     }
/// }
/// ```
///
/// The actions do exactly what the framework bar's controls do, with the same
/// ``NookChromeMotion`` curves. The host bar renders in the chrome environment, so it can
/// also read ``AppState`` as an environment object, `\.nookChromeActions`, the palette, the
/// labels, and the content insets (`\.nookContentInsets`) the framework bar pads by.
public struct NookTopBarContext: Sendable {
    /// The leading cluster's title: ``NookTopBarConfiguration/leadingTitle`` for the current
    /// state.
    public let title: String

    /// ``NookTopBarConfiguration/leadingIcon``.
    public let leadingIcon: String?

    /// Which chrome screen fills the surface.
    public let viewMode: NookViewMode

    /// Whether Settings exists at all (``NookTopBarConfiguration/showsSettings``). When
    /// `false`, ``toggleSettings()`` does nothing.
    public let showsSettings: Bool

    /// The module's breadcrumb (``AppState/moduleBreadcrumb``), or `nil` when it has none.
    public let breadcrumb: String?

    /// Whether the nook stays expanded after the pointer leaves.
    public let isKeepOpen: Bool

    /// The registered modules and a way to switch between them. Present only for a
    /// multi-module host whose ``NookHostConfiguration/moduleSwitcherPlacement`` is
    /// ``NookModuleSwitcherPlacement/leadingCluster`` - the placement that puts switching in
    /// the top bar, which a host bar now draws.
    public let moduleSwitcher: ModuleSwitcher?

    /// The configured glyphs (``NookTopBarConfiguration/symbols``), for a bar that keeps the
    /// framework's.
    public let symbols: NookChromeSymbols

    private let keepOpenAction: @Sendable @MainActor () -> Void
    private let settingsAction: @Sendable @MainActor () -> Void
    private let backAction: @Sendable @MainActor () -> Void

    /// A context with the given state and actions - for previews and tests. The chrome
    /// builds the live one.
    public init(
        title: String,
        leadingIcon: String? = nil,
        viewMode: NookViewMode = .home,
        showsSettings: Bool = true,
        breadcrumb: String? = nil,
        isKeepOpen: Bool = false,
        moduleSwitcher: ModuleSwitcher? = nil,
        symbols: NookChromeSymbols = .default,
        toggleKeepOpen: @escaping @Sendable @MainActor () -> Void = {},
        toggleSettings: @escaping @Sendable @MainActor () -> Void = {},
        goBack: @escaping @Sendable @MainActor () -> Void = {}
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.viewMode = viewMode
        self.showsSettings = showsSettings
        self.breadcrumb = breadcrumb
        self.isKeepOpen = isKeepOpen
        self.moduleSwitcher = moduleSwitcher
        self.symbols = symbols
        self.keepOpenAction = toggleKeepOpen
        self.settingsAction = toggleSettings
        self.backAction = goBack
    }

    /// Whether Settings fills the surface.
    public var isSettingsShown: Bool {
        viewMode == .settings
    }

    /// Whether ``goBack()`` has somewhere to go: Settings is showing, or the module pushed a
    /// breadcrumb. The framework bar turns its leading glyph into the back control then.
    public var canGoBack: Bool {
        isSettingsShown || breadcrumb != nil
    }

    /// Flips "stay expanded", like the framework bar's lock.
    @MainActor
    public func toggleKeepOpen() {
        keepOpenAction()
    }

    /// Switches between the home view and Settings, like the framework bar's gear. Does
    /// nothing when ``showsSettings`` is `false`.
    @MainActor
    public func toggleSettings() {
        settingsAction()
    }

    /// Leaves Settings, or clears the module's breadcrumb, like clicking the framework bar's
    /// leading glyph. The module observes the cleared breadcrumb and pops its own state.
    @MainActor
    public func goBack() {
        backAction()
    }
}

extension NookTopBarContext {
    /// The modules a host bar can switch between - what the framework's in-surface switcher
    /// lists (see ``NookModuleSwitcher``), in a `Sendable` form a host view can hold.
    public struct ModuleSwitcher: Sendable {
        /// Every registered module, in registration order.
        public let modules: [NookModuleDescriptor]

        /// The module filling the surface.
        public let activeID: String

        /// Backgrounded modules that asked for attention.
        public let attentionIDs: Set<String>

        private let switchAction: @Sendable @MainActor (String) -> Void

        public init(
            modules: [NookModuleDescriptor],
            activeID: String,
            attentionIDs: Set<String> = [],
            switchTo: @escaping @Sendable @MainActor (String) -> Void
        ) {
            self.modules = modules
            self.activeID = activeID
            self.attentionIDs = attentionIDs
            self.switchAction = switchTo
        }

        /// The active module's descriptor.
        public var activeDescriptor: NookModuleDescriptor? {
            modules.first { $0.id == activeID }
        }

        /// Brings the module `id` to the surface, as choosing it in the switcher does.
        @MainActor
        public func switchTo(_ id: String) {
            switchAction(id)
        }
    }
}

/// A main-actor action that is not itself `Sendable` - a closure the chrome was handed, or
/// one that captures ``AppState`` - made safe to share by keeping it on the main actor, so
/// ``NookTopBarContext`` can stay `Sendable`.
@MainActor
final class NookMainActorAction<Input> {
    let run: (Input) -> Void

    init(_ run: @escaping (Input) -> Void) {
        self.run = run
    }
}

extension NookTopBarContext.ModuleSwitcher {
    /// The switcher the framework bar would draw.
    @MainActor
    init(_ switcher: NookModuleSwitcher) {
        let action = NookMainActorAction(switcher.switchTo)
        self.init(
            modules: switcher.modules,
            activeID: switcher.activeID,
            attentionIDs: switcher.attentionIDs,
            switchTo: { action.run($0) }
        )
    }
}

extension NookTopBarContext {
    /// The live context for `appState`, with the framework bar's actions.
    @MainActor
    static func live(
        appState: AppState,
        topBar: NookTopBarConfiguration,
        motion: NookChromeMotion,
        moduleSwitcher: NookModuleSwitcher?,
        toggleKeepOpen: @escaping () -> Void
    ) -> NookTopBarContext {
        let breadcrumb = appState.moduleBreadcrumb.flatMap { $0.isEmpty ? nil : $0 }
        let showsSettings = topBar.showsSettings
        let keepOpen = NookMainActorAction<Void>(toggleKeepOpen)
        let settings = NookMainActorAction<Void> { _ in
            guard showsSettings else { return }
            NookTopBarCommands.toggleSettings(appState, animation: motion.viewModeChange)
        }
        let back = NookMainActorAction<Void> { _ in
            NookTopBarCommands.goBack(appState, animation: motion.leadingClusterBack)
        }
        return NookTopBarContext(
            title: topBar.leadingTitle(appState),
            leadingIcon: topBar.leadingIcon,
            viewMode: appState.viewMode,
            showsSettings: showsSettings,
            breadcrumb: breadcrumb,
            isKeepOpen: appState.keepNookOpen,
            moduleSwitcher: moduleSwitcher.map(ModuleSwitcher.init),
            symbols: topBar.symbols,
            toggleKeepOpen: { keepOpen.run(()) },
            toggleSettings: { settings.run(()) },
            goBack: { back.run(()) }
        )
    }
}

/// The top bar's gear and back actions, shared by the framework bar and
/// ``NookTopBarContext`` so a host bar behaves the same.
@MainActor
enum NookTopBarCommands {
    /// Home to Settings and back.
    static func toggleSettings(_ appState: AppState, animation: Animation) {
        withAnimation(animation) {
            if appState.isSettingsView {
                appState.showHome()
            } else {
                appState.showSettings()
            }
        }
    }

    /// Out of Settings, or out of the module's breadcrumb.
    static func goBack(_ appState: AppState, animation: Animation) {
        let hasBreadcrumb = appState.moduleBreadcrumb?.isEmpty == false
        withAnimation(animation) {
            if appState.isSettingsView {
                appState.showHome()
            } else if hasBreadcrumb {
                // An activity's expanded view sits under its own breadcrumb; back returns home.
                appState.moduleBreadcrumb = nil
                appState.presentedLiveActivity = nil
            } else {
                appState.showHome()
            }
        }
    }
}

extension NookTopBarConfiguration {
    /// Replaces the whole bar with a host view from a `@ViewBuilder` closure. See
    /// ``content``.
    public mutating func setContent<Content: View & Sendable>(
        @ViewBuilder _ content: @escaping @Sendable @MainActor (NookTopBarContext) -> Content
    ) {
        self.content = { AnyView(content($0)) }
    }

    /// Draws the leading cluster's icon with a host view from a `@ViewBuilder` closure. See
    /// ``leadingIconView``.
    public mutating func setLeadingIcon<Content: View & Sendable>(
        @ViewBuilder _ content: @escaping @Sendable @MainActor (Color) -> Content
    ) {
        leadingIconView = { AnyView(content($0)) }
    }
}

extension NookConfiguration {
    /// Replaces the framework top bar with a host view from a `@ViewBuilder` closure. The
    /// closure receives a ``NookTopBarContext`` with the bar's state and actions. See
    /// ``NookTopBarConfiguration/content``.
    public mutating func setTopBar<Content: View & Sendable>(
        @ViewBuilder _ content: @escaping @Sendable @MainActor (NookTopBarContext) -> Content
    ) {
        topBar.setContent(content)
    }
}
