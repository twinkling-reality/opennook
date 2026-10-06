// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// MultiNook - one host process, several interchangeable notch apps.
//
// A NookHostConfiguration registers a set of modules; the host shows one at a time and
// the user switches between them from the Modules menu-bar section (the default
// `moduleSwitcherPlacement`), or with the module-cycle shortcut. See the placement
// options near the bottom of this file. Run with `swift run MultiNook`.
//
// It opens on a board: a module whose home shows a widget from each of the other three,
// side by side. The three are resident and load at launch, so their widgets are there
// from the start. Arrange the board in its Settings.

import NookApp
import SwiftUI

/// A plain home view shared by the example modules.
struct ModuleHome: View {
    let headline: String
    let detail: String
    let symbol: String
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.secondaryLabel)
            Text(headline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryLabel)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// A trivial service whose only job is to be resolved through `AppServices` - the
/// counter module's persistence, lifted behind a type so its views need not know how
/// the count is stored. Not actor-isolated: a `ServiceKey`'s `defaultValue` is
/// nonisolated (the SwiftUI `EnvironmentKey` pattern), so its backing type must be too.
final class LaunchTracker: Sendable {
    let launchCount: Int

    init(launchCount: Int) {
        self.launchCount = launchCount
    }

    /// Builds a tracker from a module's isolated defaults, bumping the persisted count.
    static func bumping(_ defaults: UserDefaults) -> LaunchTracker {
        let next = defaults.integer(forKey: "launchCount") + 1
        defaults.set(next, forKey: "launchCount")
        return LaunchTracker(launchCount: next)
    }

    /// The default used when no `LaunchTracker` was registered for the key.
    static let unregistered = LaunchTracker(launchCount: 0)
}

/// The `ServiceKey` the counter module registers its `LaunchTracker` against. Resolving
/// `LaunchTrackerKey.self` is total - it falls back to `defaultValue` if unregistered.
struct LaunchTrackerKey: ServiceKey {
    static let defaultValue: LaunchTracker = .unregistered
}

/// A module that carries its own product state - a launch counter persisted in the
/// module's isolated `UserDefaults` suite, exposed to its views through the type-safe
/// `AppServices` container keyed by `LaunchTrackerKey`. Shows the full `NookModule`
/// protocol; the simpler modules below register a `NookConfiguration` closure directly.
@MainActor
final class CounterModule: NookModule {
    // `nonisolated` so the top-level (nonisolated) host setup can reference it. The
    // descriptor is an immutable `Sendable` value, so this is safe outside the actor.
    nonisolated static let moduleDescriptor = resident(
        NookModuleDescriptor(id: "com.opennook.example.counter", displayName: "Counter", icon: "number")
    )

    let descriptor = CounterModule.moduleDescriptor
    private let context: NookModuleContext

    init(context: NookModuleContext) {
        self.context = context
        // Build the service from the module's isolated defaults and register it in the
        // module's own `AppServices` bag under its `ServiceKey`. The module's views
        // resolve it back with `services.resolve(LaunchTrackerKey.self)`.
        let tracker = LaunchTracker.bumping(context.defaults)
        context.services.register(LaunchTrackerKey.self, tracker)
    }

    func makeConfiguration() -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.setHome { CounterHome() }
        configuration.topBar.leadingTitle = { _ in "Counter" }
        configuration.topBar.leadingIcon = "number"
        // Each module has its own accent: the chrome applies a module's theme when a switch
        // puts its content on the surface.
        configuration.chromeTheme = NookTheme(accent: .system(.orange))
        configuration.addWidget(
            NookWidget(id: "launches", title: "Launches", symbol: "number", action: .openModule) { _ in
                CounterWidget()
            }
        )
        return configuration
    }
}

/// The counter's widget: the same launch count, small. It draws in the counter module's scope
/// on the board, so it resolves the counter's own services.
struct CounterWidget: View {
    @Environment(\.appServices) private var services
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
            Text("\(services.resolve(LaunchTrackerKey.self).launchCount)")
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.primaryLabel)
            Text("launches")
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryLabel)
        }
    }
}

/// The clock's widget: the time, and the date when it has the room.
struct ClockWidget: View {
    let size: NookWidgetSize
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer(minLength: 0)
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.primaryLabel)
                if size != .small {
                    Text(context.date, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryLabel)
                }
            }
        }
    }
}

/// The notes module's widget: the latest note.
struct NoteWidget: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Latest note", systemImage: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
            Text("Boards show a widget from every loaded module. Drag them around in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
                .lineLimit(2)
        }
    }
}

/// `descriptor`, resident and loaded at launch, so its widgets are on the board from the start.
nonisolated func resident(_ descriptor: NookModuleDescriptor) -> NookModuleDescriptor {
    var descriptor = descriptor
    descriptor.backgroundPolicy = .stayResident
    descriptor.loadsAtLaunch = true
    return descriptor
}

/// The counter module's home view. It resolves the launch count out of the module's
/// `AppServices` bag - never optional, thanks to `LaunchTrackerKey.defaultValue`.
struct CounterHome: View {
    @Environment(\.appServices) private var services

    var body: some View {
        let count = services.resolve(LaunchTrackerKey.self).launchCount
        ModuleHome(
            headline: "Counter module",
            detail: "Opened \(count) time\(count == 1 ? "" : "s") - count resolved from this module's AppServices.",
            symbol: "number"
        )
    }
}

@MainActor
func clockConfiguration() -> NookConfiguration {
    var configuration = NookConfiguration()
    configuration.setHome {
        ModuleHome(
            headline: "Clock module",
            detail: "A second notch app sharing the same surface.",
            symbol: "clock"
        )
    }
    configuration.topBar.leadingTitle = { _ in "Clock" }
    configuration.topBar.leadingIcon = "clock"
    configuration.chromeTheme = NookTheme(accent: .system(.blue))
    configuration.addWidget(
        NookWidget(id: "time", title: "Time", symbol: "clock", sizes: [.medium, .small], action: .openModule) { size in
            ClockWidget(size: size)
        }
    )
    return configuration
}

@MainActor
func notesConfiguration() -> NookConfiguration {
    var configuration = NookConfiguration()
    configuration.setHome {
        ModuleHome(
            headline: "Notes module",
            detail: "Switch from the menu-bar Modules section, or press Control-Option-Grave.",
            symbol: "note.text"
        )
    }
    configuration.topBar.leadingTitle = { _ in "Notes" }
    configuration.topBar.leadingIcon = "note.text"
    configuration.chromeTheme = NookTheme(accent: .system(.green))
    configuration.addWidget(
        NookWidget(id: "latest", title: "Latest note", symbol: "note.text", sizes: [.wide, .medium]) { _ in
            NoteWidget()
        }
    )
    return configuration
}

var host = NookHostConfiguration()

host.register(CounterModule.moduleDescriptor) { context in
    CounterModule(context: context)
}
host.register(
    resident(NookModuleDescriptor(id: "com.opennook.example.clock", displayName: "Clock", icon: "clock")),
    configuration: { clockConfiguration() }
)
host.register(
    resident(NookModuleDescriptor(id: "com.opennook.example.notes", displayName: "Notes", icon: "note.text")),
    configuration: { notesConfiguration() }
)

// A board: its home is the other modules' widgets. Without a saved layout it shows them in
// registration order at their preferred sizes; this one leads with the clock.
host.registerBoard(
    NookBoardConfiguration(
        id: "com.opennook.example.board",
        displayName: "Today",
        defaultLayout: [NookWidgetPlacement(moduleID: "com.opennook.example.clock", widgetID: "time")]
    )
)

// Control-Option-Grave cycles to the next module. (Carbon: controlKey | optionKey.)
host.moduleCycleHotkey = NookHotkey(keyCode: 50, carbonModifiers: 4096 | 2048, keySymbol: "`")
host.defaultModule = "com.opennook.example.board"

// Where the switcher lives. The default (.menuBar) keeps the expanded surface entirely
// the module's own and lists modules in the menu-bar item; switch there or with the cycle
// hotkey above. Opt into an on-screen switcher folded into the top bar's leading cluster:
//   host.moduleSwitcherPlacement = .leadingCluster
// or drop the on-screen affordance entirely (hotkeys only):
//   host.moduleSwitcherPlacement = .none

NookApp.main(host)
