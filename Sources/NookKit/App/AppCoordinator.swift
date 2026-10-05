// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import Combine
import NookSurface
import SwiftUI

/// App-wide coordinator. Owns the long-running state, constructs the notch chrome,
/// and exposes the lifecycle vocabulary (show/hide/toggle, reset-settings) that views
/// and the menu-bar fallback call into.
///
/// `@MainActor`-isolated: the coordinator drives `Nook`/`NSWindow` chrome, holds the
/// `@Published` ``AppState``, and arbitrates transient surface presenters - every one
/// of which is main-actor work. Conforms to ``NookSurfacePresenting`` so transient
/// presenters (e.g. `NookActivityQueue`) can take over the surface through it.
@MainActor
public final class AppCoordinator: ObservableObject {
    /// Framework-global, observable chrome state - appearance preferences, hotkey,
    /// display preference, visibility mirror, view mode.
    public let appState: AppState

    /// The indirection layer to the active host configuration. The surface's content
    /// observes this, so a module switch is a re-publish here rather than a rebuild.
    public let moduleHost: ModuleHost

    /// Host-supplied registration: home/compact content, theme, lifecycle hooks.
    /// Reads through ``moduleHost`` so it always reflects the active module.
    public var configuration: NookConfiguration { moduleHost.configuration }

    public let hotkeyController: HotkeyController
    var cancellables = Set<AnyCancellable>()

    /// An opaque `NotificationCenter` observer token, wrapped so the non-isolated
    /// `deinit` can read it to unregister.
    ///
    /// The token imports as a non-`Sendable` `NSObjectProtocol`. The wrapper is
    /// `@unchecked Sendable` because that is genuinely correct: the token is an opaque,
    /// immutable handle and its only use is `NotificationCenter.removeObserver`, which
    /// Apple documents as thread-safe. There is no mutable state to race.
    struct ObserverToken: @unchecked Sendable {
        let token: NSObjectProtocol
    }
    var accessibilityObserver: ObserverToken?

    /// Reads the system's Reduce Transparency setting when resolving backdrops. Always the
    /// live setting in an app; a seam for tests, which cannot depend on the machine they run
    /// on (a headless CI runner reports it on, collapsing every translucent style to solid).
    var reduceTransparencyProvider: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Reads the system's light/dark appearance when resolving backdrops under the
    /// `.followSystem` palette. Always the app's effective appearance in an app; a seam for
    /// tests, which cannot flip the machine's appearance.
    var systemColorSchemeProvider: () -> ColorScheme = {
        // `NSApplication.shared` rather than the `NSApp` global: the latter is nil until
        // the app object is first materialized, which a headless unit test never does.
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// Arbitrates the surface between competing transient presenters - the activity
    /// queues and ambient indicators of every loaded module. Lazy because it captures
    /// `surface`; layered over ``enqueueLifecycle`` so it serializes nothing itself.
    lazy var arbiter: SurfaceArbiter = {
        SurfaceArbiter(
            isUserEngaged: { [weak self] in self?.isUserEngaged ?? false },
            activeModuleID: { [weak self] in self?.moduleHost.activeModuleID ?? "" },
            currentState: { [weak self] in self?.surface.state ?? .hidden },
            runSerial: { [weak self] operation in
                await self?.enqueueLifecycle(operation).value
            },
            expand: { [weak self] in await self?.surface.expand(on: nil) },
            compact: { [weak self] in await self?.surface.compact(on: nil) },
            hide: { [weak self] in await self?.surface.hide() },
            topClaimChanged: { [weak self] in self?.syncPresentedModule() }
        )
    }()

    /// `true` once ``start()`` has run. Guards against a double `start()` registering
    /// duplicate observers, sinks, and `onReady` callbacks.
    private var hasStarted = false

    /// User-initiated open intent - `true` from the moment the user opens the surface
    /// (toggleNook / showNook / showHome / showSettings) until it leaves `.expanded`
    /// for any reason. Drives ``isUserEngaged`` together with `surface.isHovering`.
    ///
    /// This is *intent*, not a mirror of surface state. The arbiter's own `expand()`
    /// flips the surface to `.expanded` but does NOT set this flag - so a later
    /// higher-priority claim can preempt without the gate falsely tripping. The old
    /// model (engagement = `isNookVisible || isHovering`) had exactly that bug,
    /// because the mirror flipped from the arbiter's own expand and silently
    /// disabled all subsequent preemption.
    ///
    /// Read/written via ``setUserInitiatedOpen(_:)`` so changes publish through
    /// ``userInitiatedOpenSubject`` for ``userEngagementChanges``.
    private var userInitiatedOpen: Bool = false

    /// Backing publisher for ``userInitiatedOpen``; combined with the surface's hover
    /// publisher to drive ``userEngagementChanges``.
    private let userInitiatedOpenSubject = CurrentValueSubject<Bool, Never>(false)

    /// The host-wide ``NookPresentationPinning`` broker. Folded into
    /// ``isUserEngaged`` and ``userEngagementChanges`` so a popover/sheet pin
    /// suppresses the hover-exit auto-compact AND denies competing arbiter
    /// claims for the duration. See ``bindPresentationPinning()`` for the
    /// surface-side wiring (the `staysExpandedOnHoverExit` override).
    var presentationPinning: NookPresentationPinning { moduleHost.registry.presentationPinning }

    /// Single setter for ``userInitiatedOpen`` that publishes through
    /// ``userInitiatedOpenSubject``. Idempotent: a no-op when the value is unchanged.
    private func setUserInitiatedOpen(_ value: Bool) {
        guard userInitiatedOpen != value else { return }
        userInitiatedOpen = value
        userInitiatedOpenSubject.send(value)
    }

    /// Module ids whose `onReady` has already fired. A module's `onReady` runs once per
    /// *loaded instance* - when it is unloaded (`unloadOnSwitchAway`) the id is dropped
    /// so a rebuilt instance gets a fresh `onReady` (e.g. to re-bind an activity queue).
    private var modulesGivenOnReady: Set<String> = []

    /// Follows the active configuration's ``NookConfiguration/companionSource``, replaced
    /// whenever the surface decorations are projected again.
    private var companionSourceSubscription: AnyCancellable?

    /// Follows the host's and the displayed configuration's live chrome themes. Re-bound
    /// whenever the displayed configuration changes. See ``NookThemeSource``.
    var themeSourceSubscriptions: [AnyCancellable] = []

    /// Tail of the serial chain that all surface lifecycle transitions
    /// (expand/compact/hide) run through. Without this, two rapid triggers - a
    /// double hotkey press, a display change landing mid-show - each spawn an
    /// independent `Task` whose `await`s interleave, settling the surface in the
    /// opposite state from the user's last action.
    private var lifecycleTail: Task<Void, Never>?

    /// Tail of the *off-chain* switch-away work. A module switch flips identity inside
    /// the serial lifecycle chain (fast - no user-visible stall) and then finishes the
    /// outgoing module in a follow-on task: its `prepareForSwitchAway`, then its
    /// `onDeactivate`, then the unload its background policy asks for. The arbiter has
    /// already invalidated the outgoing module's claims and denies new ones until this
    /// finishes, so the user sees the new module immediately and the outgoing module
    /// drains under the covers. Two rapid switches enqueue their work here in order so
    /// `drainSwitchTailsForTesting()` can join them.
    ///
    /// Off the chain on purpose: a quiescing module typically awaits its own
    /// `endTransientPresentation`, which runs on the chain, so awaiting the quiesce on
    /// the chain would deadlock until the timeout.
    private var switchTailTask: Task<Void, Never>?

    /// Bounded budget for an outgoing module's `prepareForSwitchAway`. A misbehaving
    /// module that never returns is logged and the task is cancelled; the switch away
    /// then carries on with `onDeactivate` and the unload.
    static let switchAwayTimeout: Duration = .seconds(2)

    /// Counts switches away from each module. A switch-away tail finishes its module only
    /// while its count is still the latest, so after a quick A to B to A to B only the last
    /// switch away from A deactivates and unloads it.
    private var switchAwayGenerations: [String: Int] = [:]

    /// Each module's breadcrumb while another module's content is on the surface.
    /// ``AppState/moduleBreadcrumb`` always belongs to the displayed module; a module's
    /// entry is dropped when it is unloaded, since its rebuilt instance starts at its root.
    private var parkedBreadcrumbs: [String: String] = [:]

    /// The module whose content the surface showed when the breadcrumb was last handed
    /// off. See ``handOffBreadcrumbIfNeeded()``.
    private var breadcrumbOwnerID: String

    /// Awaits the current tail of the serial lifecycle chain - every transition and
    /// switch transaction enqueued so far has settled when this returns. Test-only seam.
    func drainLifecycleForTesting() async {
        await lifecycleTail?.value
    }

    /// Awaits all in-flight detached switch-quiesce drains. Test-only seam - production
    /// code never reads this because the arbiter already guarantees stale-token safety.
    func drainSwitchTailsForTesting() async {
        await switchTailTask?.value
    }

    /// Chains a switch-quiesce drain after every previously enqueued one so back-to-back
    /// switches drain in registration order.
    private func enqueueSwitchTail(_ work: @escaping @Sendable @MainActor () async -> Void) {
        let previous = switchTailTask
        switchTailTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Chains `operation` after every previously enqueued lifecycle transition so
    /// they run strictly in order. The returned task completes when `operation` does.
    @discardableResult
    func enqueueLifecycle(_ operation: @escaping @Sendable @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = lifecycleTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        lifecycleTail = task
        return task
    }

    /// The notch surface the coordinator drives. Injected behind the
    /// ``NookSurfaceDriving`` protocol so the coordinator's logic can be exercised
    /// against a windowless fake; in production it is a concrete `Nook`.
    let surface: any NookSurfaceDriving

    /// Builds the production `Nook` surface with the coordinator's router views.
    ///
    /// The router views capture `moduleHost`/`appState` and weak callbacks onto a
    /// coordinator that does not exist yet at call time - they are wired with a
    /// `coordinatorBox` that the designated `init` fills in once `self` is available.
    static func makeDefaultNook(
        moduleHost: ModuleHost,
        appState: AppState,
        coordinatorBox: CoordinatorBox
    ) -> Nook<AnyView, AnyView, AnyView> {
        let chromeActions = coordinatorBox.chromeActions
        return Nook<AnyView, AnyView, AnyView>(
            hoverBehavior: moduleHost.chromeBehavior.hoverBehavior,
            style: moduleHost.displayedConfiguration.effectiveStyle,
            expanded: {
                AnyView(
                    ModuleRouterExpandedView(
                        moduleHost: moduleHost,
                        appState: appState,
                        toggleKeepOpen: { coordinatorBox.coordinator?.toggleKeepNookOpen() },
                        hide: { coordinatorBox.coordinator?.hideNook() },
                        resetAllSettings: { coordinatorBox.coordinator?.resetAllSettingsToDefaults() },
                        switchModule: { id in coordinatorBox.coordinator?.switchModule(to: id) },
                        chromeActions: chromeActions
                    )
                )
            },
            compactLeading: {
                AnyView(
                    ModuleRouterCompactView(
                        moduleHost: moduleHost,
                        appState: appState,
                        slot: .leading,
                        chromeActions: chromeActions
                    )
                )
            },
            compactTrailing: {
                AnyView(
                    ModuleRouterCompactView(
                        moduleHost: moduleHost,
                        appState: appState,
                        slot: .trailing,
                        chromeActions: chromeActions
                    )
                )
            }
        )
    }

    /// A late-bound, weak handle to the coordinator, passed into the router-view
    /// closures so they can reach a coordinator that is constructed *after* the surface.
    @MainActor
    final class CoordinatorBox {
        weak var coordinator: AppCoordinator?

        /// The chrome actions, resolved through the box so they can be handed to views built
        /// before the coordinator exists. The box only holds the coordinator weakly, so the
        /// closures can hold the box itself, like the router closures above do.
        var chromeActions: NookChromeActions {
            NookChromeActions(
                toggleKeepOpen: { self.coordinator?.toggleKeepNookOpen() },
                toggleSettings: { self.coordinator?.toggleSettingsFromChrome() },
                collapse: { self.coordinator?.hideNook() },
                resetSettings: { self.coordinator?.resetAllSettingsToDefaults() },
                takeKeyboardFocus: { self.coordinator?.takeNookKeyboardFocus() },
                releaseKeyboardFocus: { self.coordinator?.releaseNookKeyboardFocus() }
            )
        }
    }

    /// Single-module convenience - wraps `configuration` as a lone-module ``ModuleHost``
    /// so a downstream that just wants a coordinator for one ``NookConfiguration`` does
    /// not have to construct the host plumbing manually.
    public convenience init(
        appState: AppState = AppState(),
        hotkeyController: HotkeyController = HotkeyController(),
        configuration: NookConfiguration = NookConfiguration()
    ) {
        self.init(
            appState: appState,
            hotkeyController: hotkeyController,
            moduleHost: ModuleHost(configuration: configuration)
        )
    }

    /// Multi-module entry - pass a fully built ``ModuleHost`` (e.g. from
    /// `NookHostConfiguration.makeRegistry()`).
    public convenience init(
        appState: AppState = AppState(),
        hotkeyController: HotkeyController = HotkeyController(),
        moduleHost: ModuleHost
    ) {
        self.init(
            appState: appState,
            hotkeyController: hotkeyController,
            moduleHost: moduleHost,
            surface: nil
        )
    }

    /// Designated initializer. `surface` is injectable behind the NookKit-internal
    /// ``NookSurfaceDriving`` seam: production passes `nil` and a `Nook` is built by
    /// ``makeDefaultNook(moduleHost:appState:coordinatorBox:)``; tests pass a windowless
    /// fake. Internal because ``NookSurfaceDriving`` is a NookKit-internal protocol.
    ///
    /// `systemAppearanceChanges` fires when the system's light/dark appearance changes.
    /// `nil` (production) observes `NSApplication.shared.effectiveAppearance`; tests pass a
    /// subject they drive.
    init(
        appState: AppState = AppState(),
        hotkeyController: HotkeyController = HotkeyController(),
        moduleHost: ModuleHost,
        surface: (any NookSurfaceDriving)?,
        systemAppearanceChanges: AnyPublisher<Void, Never>? = nil
    ) {
        self.appState = appState
        self.hotkeyController = hotkeyController
        self.moduleHost = moduleHost
        self.breadcrumbOwnerID = moduleHost.displayedModuleID

        let coordinatorBox = CoordinatorBox()
        self.surface =
            surface
            ?? AppCoordinator.makeDefaultNook(
                moduleHost: moduleHost,
                appState: appState,
                coordinatorBox: coordinatorBox
            )

        bindBackdropSynchronization()
        bindSystemAppearance(
            systemAppearanceChanges
                ?? NSApplication.shared.publisher(for: \.effectiveAppearance)
                .dropFirst()  // the current value, published on subscribe
                .map { _ in () }
                .eraseToAnyPublisher()
        )
        // Bind the surface-state mirror at init, not at start: it is pure observation
        // (writes only to `appState.isNookVisible` and clears `userInitiatedOpen` on
        // independent collapse), and the arbiter's engagement bookkeeping depends on
        // it being live from the moment the coordinator exists - including in tests
        // that construct a coordinator without calling `start()`.
        bindSurfaceVisibility()
        // Likewise bind the presentation-pin projection at init: tests that exercise
        // `pin()`/`release()` against a windowless coordinator depend on the
        // `staysExpandedOnHoverExit` override flipping without going through `start()`.
        bindPresentationPinning()

        coordinatorBox.coordinator = self
        // Project the active module's lifecycle callbacks onto the surface. The hooks
        // fire on the surface's own state transitions, so hover- and drag-driven changes
        // reach the host too - not just coordinator-initiated show/hide. `performSwitch`
        // re-wires them across a module switch.
        applyModuleHooks(configuration)
        applyModuleSurfaceDecorations(configuration)
    }

    /// The chrome actions a host view uses to show the lock or gear outside the top bar.
    /// See ``NookChromeActions``.
    var chromeActions: NookChromeActions {
        NookChromeActions(
            toggleKeepOpen: { [weak self] in self?.toggleKeepNookOpen() },
            toggleSettings: { [weak self] in self?.toggleSettingsFromChrome() },
            collapse: { [weak self] in self?.hideNook() },
            resetSettings: { [weak self] in self?.resetAllSettingsToDefaults() },
            takeKeyboardFocus: { [weak self] in self?.takeNookKeyboardFocus() },
            releaseKeyboardFocus: { [weak self] in self?.releaseNookKeyboardFocus() }
        )
    }

    /// What the gear does, wherever it is shown: switch between home and Settings in place
    /// while expanded, or expand straight into Settings from the compact pill. A no-op when
    /// the active module disabled Settings.
    func toggleSettingsFromChrome() {
        guard configuration.topBar.showsSettings else { return }
        guard surface.state == .expanded else {
            showSettings()
            return
        }
        withAnimation(configuration.effectiveMotion.viewModeChange) {
            if appState.isSettingsView {
                appState.showHome()
            } else {
                appState.showSettings()
            }
        }
    }

    deinit {
        if let accessibilityObserver {
            NotificationCenter.default.removeObserver(accessibilityObserver.token)
        }
    }

    /// Brings the coordinator online: sets the activation policy, syncs the chrome
    /// backdrop, registers global hotkeys, installs the surface bindings, plays the
    /// cold-launch shimmer, and fires the active module's `onReady`. Idempotent -
    /// safe to call more than once.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // `NSApplication.shared` - not the `NSApp` global. The global is nil until the
        // app object is first materialized; a unit-test process that constructs the
        // coordinator without ever calling `NSApplication.shared.run()` traps on
        // `NSApp.setActivationPolicy`. The shared accessor materializes lazily.
        NSApplication.shared.setActivationPolicy(.accessory)
        if moduleHost.chromeBehavior.keyboard.installsEditMenu {
            NookEditMenu.installIfNeeded()
        }

        syncNotchBackdrop()
        applySurfaceLook()
        configureDisplayTargeting()

        registerGlobalHotkey()
        registerModuleHotkeys()
        bindHotkeyRegistration()
        bindNookDragSession()
        // `bindSurfaceVisibility` was moved to `init` - it must be live before any
        // arbiter claim is granted, including in tests that don't call `start()`.

        // Cold-launch greeting: compact the chrome, then fire a one-shot shimmer along the
        // perimeter so the user sees the app is awake. Awaiting `compact()` first puts the
        // nook into a visible state so the event fires immediately instead of queuing.
        //
        // The cold-launch compact suppresses the host's `onCompact` hook for this one
        // transition - it is a boot artifact, not a user-driven collapse, and a host
        // wiring `onCompact = { /* user dismissed the nook */ }` would otherwise fire
        // on launch every time. Restored synchronously inside the same serial step so
        // any subsequent hover- or coordinator-driven compact fires the hook normally.
        enqueueLifecycle { [weak self] in
            guard let self else { return }
            self.surface.onCompact = nil
            await self.surface.compact(on: self.resolveScreen())
            // Restored from the active configuration rather than a copy saved before the
            // compact, so a configuration reload that lands mid-compact keeps its hook.
            self.surface.onCompact = self.configuration.onCompact
            // The greeting shimmer is opt-out: a host can launch silently while still
            // settling into the compact launch state. See `NookChromeBehavior`.
            if self.moduleHost.chromeBehavior.showsLaunchShimmer {
                // In the theme's feedback tint, which follows the accent.
                self.surface.playFeedback(.shimmer, style: self.themedFeedbackStyle, duration: 1.1, repeats: false)
            }
        }

        // Hand the host a post-launch handle on the live coordinator (e.g. for
        // NookComponents' activity queue to bind itself as a transient presenter).
        fireModuleReadyIfNeeded()
    }

    // MARK: - Module switching

    /// The registered modules available to switch between, in registration order.
    public var moduleDescriptors: [NookModuleDescriptor] { moduleHost.descriptors }

    /// The id of the foreground module.
    public var activeModuleID: String { moduleHost.activeModuleID }

    /// Switches the foreground module. The switch is enqueued as a transaction on the
    /// serial lifecycle chain (`enqueueLifecycle`), so it is ordered against - never
    /// interleaved with - surface transitions and other switches.
    ///
    /// The transaction invalidates the outgoing module's arbiter claims, activates the
    /// incoming module and flips identity, re-wires the surface hooks, and - when the
    /// surface is already expanded - fires a synthetic `onExpand` for the incoming
    /// module. The content cross-fades in place; the surface is not hidden, so the
    /// outgoing module gets no `onHide`. The outgoing module is then finished off the
    /// chain, in its documented order: `prepareForSwitchAway` (bounded by
    /// ``switchAwayTimeout``), `onDeactivate`, and the unload its background policy asks for.
    public func switchModule(to id: String) {
        enqueueLifecycle { [weak self] in await self?.performSwitch(to: id) }
    }

    /// The serialized module-switch transaction.
    ///
    /// On the serial chain - fast, user-facing:
    ///   1. **Invalidate** the outgoing module's arbiter claims (synchronous, in-memory)
    ///      and deny it new ones until its switch away finishes. After this, any
    ///      `endTransientPresentation` from the outgoing module is a guaranteed no-op.
    ///   2. **Read live surface state** - never the mirror, never a value captured
    ///      before this transaction reached the head of the queue.
    ///   3. **Flip identity**: `onActivate` on the incoming module, configuration
    ///      re-publish. The breadcrumb follows the displayed module.
    ///   4. **Re-wire surface hooks** so the synthetic `onExpand` below fires the
    ///      incoming module's hook.
    ///   5. **Clear stranded `viewMode == .settings`** if the incoming module disables
    ///      Settings.
    ///   6. **Fire `onReady`** for the incoming module (once per loaded instance).
    ///   7. **Synthesize `onExpand`** if the surface was already expanded.
    ///
    /// Off the serial chain - bounded, under the covers (``finishSwitchAway(from:generation:)``):
    ///   8. **Await the outgoing module's `prepareForSwitchAway`** with a hard timeout,
    ///      then call its `onDeactivate`, then unload it when its background policy is
    ///      `.unloadOnSwitchAway`. The user sees the new module immediately. This must
    ///      stay off the chain: a quiescing module awaits its own
    ///      `endTransientPresentation`, which runs on the chain.
    private func performSwitch(to id: String) async {
        let outgoingID = moduleHost.activeModuleID
        guard id != outgoingID, moduleHost.registry.descriptor(for: id) != nil else { return }

        // 1. Invalidate outgoing claims FIRST - stale-token safety is the contract the
        //    off-chain switch-away relies on.
        arbiter.invalidateClaims(ownedBy: outgoingID)

        // 2. Read live surface state on the serial chain.
        let wasExpanded = surface.state == .expanded

        // 3. Flip identity. The switch curve is read before the flip, from the module the
        //    surface is leaving, so the content and the chrome look below move together.
        let switchAnimation = moduleHost.configuration.effectiveMotion.moduleSwitch
        withAnimation(switchAnimation) {
            _ = moduleHost.switchModule(to: id)
        }
        guard moduleHost.activeModuleID == id else { return }
        // The outgoing module is quiescing: deny it the surface until it is finished. A
        // switch back to a module whose switch away is still running takes it back.
        arbiter.retiringModuleIDs.insert(outgoingID)
        arbiter.retiringModuleIDs.remove(id)
        let generation = (switchAwayGenerations[outgoingID] ?? 0) + 1
        switchAwayGenerations[outgoingID] = generation
        // A background claim from the incoming module is no longer a background one.
        syncPresentedModule()
        handOffBreadcrumbIfNeeded()

        // 4. Re-wire surface hooks in this same critical section, and swap the companion
        //    surfaces with them: the outgoing module's companions leave (releasing any
        //    hover they held) as the incoming module's arrive, cross-fading like the content.
        applyModuleHooks(moduleHost.configuration)
        withAnimation(switchAnimation) {
            applyModuleSurfaceDecorations(moduleHost.displayedConfiguration)
            // The incoming module's chrome look - shape, curves, wash, shadow, backdrop, and
            // window appearance - in the same animation as its content.
            applySurfaceLook()
            syncNotchBackdrop()
        }

        // 5. Drop a stranded `.settings` viewMode if the incoming module disables
        //    Settings (see testSwitchToModuleWithSettingsDisabledClearsStrandedSettingsViewMode).
        leaveSettingsIfDisabled()

        // 6. onReady for the incoming module (once per loaded instance).
        fireModuleReadyIfNeeded()

        // 7. Synthetic onExpand if the surface was already expanded.
        if wasExpanded {
            moduleHost.configuration.onExpand?()
        }

        // 8. Finish the outgoing module off the serial chain.
        enqueueSwitchTail { [weak self] in
            await self?.finishSwitchAway(from: outgoingID, generation: generation)
        }
    }

    /// The off-chain half of a switch away from `outgoingID`: `prepareForSwitchAway` under
    /// ``switchAwayTimeout``, then `onDeactivate`, then the unload the module's background
    /// policy asks for.
    ///
    /// Skipped, at either step, when the switch away was superseded: the user switched back
    /// to the module, or switched away from it again (a later `generation`, whose own tail
    /// finishes it). A module switched back to mid-quiesce therefore gets `onActivate`
    /// without a matching `onDeactivate`, which ``NookModule/onActivate()`` already has to
    /// tolerate for the launch module.
    ///
    /// The module instance is re-resolved here rather than captured: only the `Sendable` id
    /// crosses the `@Sendable` closure boundary, and a module that is no longer loaded is
    /// never rebuilt just to be torn down.
    private func finishSwitchAway(from outgoingID: String, generation: Int) async {
        let registry = moduleHost.registry
        func isCurrent() -> Bool {
            moduleHost.activeModuleID != outgoingID && switchAwayGenerations[outgoingID] == generation
        }
        guard isCurrent() else { return }
        if registry.isLoaded(outgoingID), let outgoingModule = registry.module(for: outgoingID) {
            await Self.runWithTimeout(Self.switchAwayTimeout, label: "prepareForSwitchAway[\(outgoingID)]") {
                await outgoingModule.prepareForSwitchAway()
            }
        }
        guard isCurrent() else { return }
        if moduleHost.finishSwitchAway(from: outgoingID) {
            // Unloaded: the next activation builds a fresh instance with a fresh `onReady`
            // (e.g. to re-bind an activity queue), starting at its root.
            modulesGivenOnReady.remove(outgoingID)
            parkedBreadcrumbs[outgoingID] = nil
        }
        arbiter.retiringModuleIDs.remove(outgoingID)
    }

    /// Puts the top surface claim's module on the surface: a background module's content
    /// while its claim holds the surface, the active module's otherwise. Called by the
    /// arbiter whenever the top claim changes hands, and after a module switch.
    private func syncPresentedModule() {
        let top = arbiter.topModuleID
        guard moduleHost.presentBackgroundModule(top) else { return }
        handOffBreadcrumbIfNeeded()
        applyModuleSurfaceDecorations(moduleHost.displayedConfiguration)
        applySurfaceLook()
        syncNotchBackdrop()
    }

    /// Keeps ``AppState/moduleBreadcrumb`` with the module whose content is on the surface.
    /// When that module changes, the outgoing module's breadcrumb is parked and the incoming
    /// module's parked one, if any, comes back - so a drill-in label never shows over
    /// another module's content, and a resident module returns to the label it left with.
    private func handOffBreadcrumbIfNeeded() {
        let displayedID = moduleHost.displayedModuleID
        guard displayedID != breadcrumbOwnerID else { return }
        parkedBreadcrumbs[breadcrumbOwnerID] = appState.moduleBreadcrumb
        appState.moduleBreadcrumb = parkedBreadcrumbs.removeValue(forKey: displayedID)
        breadcrumbOwnerID = displayedID
    }

    /// Runs `work` under a hard deadline. Past `timeout` the work task is cancelled and
    /// the timeout is logged via `print` - the coordinator does not fail the switch.
    ///
    /// `work` is `@MainActor` because every caller in `AppCoordinator` is - most notably
    /// the `prepareForSwitchAway` drain in ``performSwitch(to:)``, which calls a
    /// main-actor module method. Pinning the work closure to the main actor here lets
    /// the caller capture main-actor-isolated references (the resolved `NookModule`
    /// instance) without producing a non-`Sendable` capture warning on the outer
    /// `@Sendable` closure.
    ///
    /// The arbiter's stale-token guard makes an abandoned `prepareForSwitchAway` safe:
    /// any `endTransientPresentation` it issues against an invalidated claim is a
    /// no-op on the surface.
    ///
    /// `internal` rather than `private` so the test suite can exercise the deadline
    /// directly with short timeouts - driving the production path via
    /// ``performSwitch(to:)`` would require waiting the full ``switchAwayTimeout``
    /// (2 s) per case.
    static func runWithTimeout(
        _ timeout: Duration,
        label: String,
        _ work: @escaping @MainActor @Sendable () async -> Void
    ) async {
        let workTask = Task { @MainActor in await work() }
        let timerTask = Task<Bool, Never> {
            (try? await Task.sleep(for: timeout)) != nil
        }
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await workTask.value
                return false
            }
            group.addTask { await timerTask.value }
            if let timedOut = await group.next(), timedOut {
                workTask.cancel()
                print("[OpenNook] \(label) exceeded \(timeout); cancelled")
            } else {
                timerTask.cancel()
            }
            group.cancelAll()
        }
    }

    /// Projects a module's lifecycle hooks onto the surface. Called from initial wiring
    /// and from the switch transaction - the single seam for hook projection.
    private func applyModuleHooks(_ configuration: NookConfiguration) {
        surface.onExpand = configuration.onExpand
        surface.onCompact = configuration.onCompact
        surface.onHide = configuration.onHide
        surface.onFileDrop = configuration.onFileDrop ?? { _ in false }
    }

    /// Projects a module's surface decorations - its companion surfaces, rim glow style, and
    /// scroll edge fade - onto the surface. Called at init, in the switch transaction, and
    /// when a background module's claim takes or leaves the top of the arbiter's stack, so
    /// decorations always belong to the module whose content is on the surface.
    ///
    /// The companions are the configuration's own followed by its ``NookConfiguration/companionSource``,
    /// which is followed from here on, so a change to the source reaches the surface at once.
    private func applyModuleSurfaceDecorations(_ configuration: NookConfiguration) {
        let source = configuration.companionSource
        projectCompanions(configuration.companions + (source?.companions ?? []), of: configuration)
        // `@Published` sends from `willSet` on the main actor, so the new list is passed along
        // rather than read back, and it lands in the same transaction as the change itself: a
        // change made inside `withAnimation` animates on the surface too.
        companionSourceSubscription = source?.$companions
            .dropFirst()
            .sink { [weak self] companions in
                MainActor.assumeIsolated {
                    self?.projectCompanions(configuration.companions + companions, of: configuration)
                }
            }
        surface.rimGlowStyle = configuration.rimGlow
        surface.scrollEdgeFade = configuration.scrollEdgeFade
    }

    /// Wraps each companion in ``NookCompanionHost`` and hands the result to the surface.
    ///
    /// The wrapping happens here, not in the surface: the chrome environment (theme,
    /// `AppState`, services) is NookKit's, and the MIT surface only ever sees a finished view.
    /// A companion leaves its style, size, and presence unset to take the configuration's. A
    /// companion whose id an earlier one already has is dropped, since the id keys its hover
    /// tracking and its SwiftUI identity.
    private func projectCompanions(_ companions: [NookCompanion], of configuration: NookConfiguration) {
        let appState = appState
        let services = moduleHost.displayedServices
        let branding = moduleHost.branding
        let chromeActions = chromeActions
        let chromeTheme = configuration.effectiveChromeTheme
        let themeTokens = configuration.effectiveThemeTokens
        let metrics = configuration.effectiveMetrics
        let motion = configuration.effectiveMotion
        let typography = configuration.effectiveTypography
        var seen = Set<String>()
        var surfaces: [NookCompanionSurface] = []
        for companion in companions {
            guard seen.insert(companion.id).inserted else {
                print(
                    "[OpenNook] module '\(moduleHost.displayedModuleID)' has more than one companion with id "
                        + "'\(companion.id)'; only the first is shown"
                )
                continue
            }
            surfaces.append(
                NookCompanionSurface(
                    id: companion.id,
                    anchor: companion.anchor,
                    spacing: companion.spacing,
                    gap: companion.gap,
                    rowAlignment: companion.rowAlignment,
                    visibility: companion.visibility,
                    shape: companion.shape,
                    backdrop: companion.backdrop,
                    style: themedCompanionStyle(companion.style ?? configuration.companionStyle, theme: chromeTheme),
                    size: companion.size ?? configuration.companionSize,
                    presence: companion.presence ?? configuration.companionPresence,
                    accessibilityLabel: companion.accessibilityLabel
                ) {
                    NookCompanionHost(
                        appState: appState,
                        companion: companion,
                        theme: configuration.theme,
                        services: services,
                        labels: configuration.labels,
                        metrics: metrics,
                        motion: motion,
                        typography: typography,
                        branding: branding,
                        chromeActions: chromeActions,
                        symbols: configuration.topBar.symbols,
                        chromeTheme: chromeTheme,
                        themeTokens: themeTokens
                    )
                }
            )
        }
        surface.companions = surfaces
    }

    /// Returns to the home view when the active configuration turned Settings off while it
    /// was showing, since nothing would lead back out of it.
    private func leaveSettingsIfDisabled() {
        if !moduleHost.configuration.topBar.showsSettings, appState.viewMode == .settings {
            appState.showHome()
        }
    }

    /// Switches to the next registered module, wrapping around. No-op for a host with a
    /// single module.
    public func cycleModule() {
        let ids = moduleHost.descriptors.map(\.id)
        guard ids.count > 1, let index = ids.firstIndex(of: moduleHost.activeModuleID) else { return }
        switchModule(to: ids[(index + 1) % ids.count])
    }

    // MARK: - Live configuration

    /// Builds the active module's configuration again and applies it to the running chrome,
    /// for a module whose configuration depends on state that changes at runtime - its own
    /// preferences, a live preview, a design playground.
    ///
    /// The active module's `makeConfiguration()` runs again and the result is applied the way
    /// a module switch applies the incoming module's: the home and compact content, theme, top
    /// bar, labels, metrics, motion, typography, and width re-render in place; the lifecycle
    /// hooks, file-drop handler, companion surfaces, rim glow style, and scroll edge fade are
    /// projected onto the surface again; and the chrome leaves Settings if the new
    /// configuration turns Settings off. It also applies the configuration's surface look -
    /// ``NookConfiguration/style``, ``NookConfiguration/transitions``, and the
    /// ``NookConfiguration/chromeTheme``'s shape, curves, shadow, wash, and backdrop - which
    /// the chrome otherwise applies at launch and on a module switch.
    ///
    /// Nothing else changes. The module is not deactivated or activated again, `onReady` does
    /// not fire again, the nook keeps its current state, and SwiftUI state inside content
    /// whose identity is unchanged is kept. A module whose `makeConfiguration()` returns a
    /// fixed value gets that same value back. Wrap the call in `withAnimation` to animate the
    /// change:
    ///
    /// ```swift
    /// model.showsTimer.toggle()   // state the module's makeConfiguration() reads
    /// withAnimation(.snappy) { coordinator.reloadActiveConfiguration() }
    /// ```
    ///
    /// The process-global settings a single-module configuration carries -
    /// `preferenceDefaults`, `chromeBehavior`, `branding`, and `showsMenuBarExtra` - are read
    /// once at launch and are not reloaded. Use ``replaceChromeBehavior(_:)`` for chrome
    /// behavior.
    public func reloadActiveConfiguration() {
        moduleHost.reloadConfiguration()
        let configuration = moduleHost.configuration
        applyModuleHooks(configuration)
        // A background module presenting over the active one keeps its decorations until
        // its claim ends.
        applyModuleSurfaceDecorations(moduleHost.displayedConfiguration)
        applySurfaceLook()
        syncNotchBackdrop()
        leaveSettingsIfDisabled()
    }

    /// Replaces the process-global chrome behavior at runtime, for a host that lets people
    /// change it - an "on hover" preference, a backdrop that follows a brand setting.
    ///
    /// The new hover behavior applies from the next hover change, and the backdrop is
    /// resolved again right away with the new resolver. ``NookChromeBehavior/showsLaunchShimmer``
    /// only matters at launch, so replacing it changes nothing. ``ModuleHost/chromeBehavior``
    /// reads back the new value.
    public func replaceChromeBehavior(_ behavior: NookChromeBehavior) {
        moduleHost.chromeBehavior = behavior
        surface.hoverBehavior = behavior.hoverBehavior
        syncNotchBackdrop()
    }

    /// Fires the active module's `onReady` once per loaded instance.
    private func fireModuleReadyIfNeeded() {
        let id = moduleHost.activeModuleID
        guard !modulesGivenOnReady.contains(id) else { return }
        modulesGivenOnReady.insert(id)
        moduleHost.configuration.onReady?(self)
    }

    // MARK: - Display targeting

    /// Resolve the user's persisted display preference to a concrete screen.
    /// `nil` only when no display is attached at all.
    func resolveScreen() -> NSScreen? {
        NookScreenLocator.screen(matching: appState.displayPreference)
    }

    /// Project the persisted display preference onto the surface, and re-place the
    /// chrome live when the user picks a different display in Settings.
    ///
    /// `Nook.screenProvider` is what makes the preference stick *without* an explicit
    /// screen on every call site - the surface consults it on hover transitions and on
    /// display connect/disconnect too, so the disconnect fallback in
    /// ``NookScreenLocator/screen(matching:)`` flows through automatically.
    private func configureDisplayTargeting() {
        surface.screenProvider = { [weak self] in self?.resolveScreen() }

        appState.$displayPreference
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] preference in
                guard let self else { return }
                let screen = NookScreenLocator.screen(matching: preference)
                self.enqueueLifecycle { [weak self] in
                    guard let self else { return }
                    // Re-place whichever way the chrome is currently showing. A hidden
                    // nook needs nothing - its next expand/compact rebuilds on the new
                    // screen via `screenProvider`.
                    if self.surface.state == .expanded {
                        await self.surface.expand(on: screen)
                    } else if self.surface.hasLiveWindow {
                        await self.surface.compact(on: screen)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Chrome / backdrop

    /// Softer springs than NookSurface's bouncy defaults - smoother expand/compact with
    /// less overshoot. A host can override the whole set via
    /// ``NookConfiguration/transitions``; otherwise these defaults apply.
    func configureNotchAnimations() {
        surface.transitionConfiguration =
            moduleHost.displayedConfiguration.effectiveTransitions ?? AppCoordinator.defaultTransitions
    }

    /// The framework's default chrome animation curves, used when a host does not supply
    /// ``NookConfiguration/transitions``.
    static let defaultTransitions = NookTransitionConfiguration(
        openingAnimation: .spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.12),
        closingAnimation: .spring(response: 0.46, dampingFraction: 0.93, blendDuration: 0.10),
        conversionAnimation: .spring(response: 0.54, dampingFraction: 0.86, blendDuration: 0.12)
    )

    // MARK: - Global hotkey

    /// String id of the global show/hide registration in ``HotkeyController``.
    /// Hoisted to ``NookHotkeyIDs/toggle`` so view code can reference it without a
    /// magic-string literal that could drift.
    private static var toggleHotkeyID: String { NookHotkeyIDs.toggle }

    /// Registers the current `appState.hotkey` as the global show/hide shortcut.
    /// Skipped while the user is mid-recording so the old shortcut can't fire.
    func registerGlobalHotkey() {
        guard !appState.isRecordingHotkey else { return }

        let hotkey = appState.hotkey
        let status = hotkeyController.register(
            Self.toggleHotkeyID,
            keyCode: hotkey.keyCode,
            modifiers: hotkey.carbonModifiers
        ) { [weak self] in
            Task { @MainActor in
                self?.toggleNook(fromShortcut: true)
            }
        }
        // Record the CURRENT outcome on the durable failure channel: a failure stays
        // visible until a later attempt succeeds; a success clears this id's entry.
        recordHotkeyOutcome(
            id: Self.toggleHotkeyID,
            status: status,
            shortcutName: moduleHost.configuration.labels.shortcut.showHost(moduleHost.branding.hostName),
            hotkey: hotkey
        )
    }

    /// Registers the static module shortcuts: a direct-jump key per module that declares
    /// one, and the module-cycle key when the host configured it. These never change
    /// after launch, unlike the user-rebindable show/hide shortcut.
    private func registerModuleHotkeys() {
        for descriptor in moduleHost.descriptors {
            guard let hotkey = descriptor.hotkey else { continue }
            let id = descriptor.id
            let registrationID = NookHotkeyIDs.module(id)
            let status = hotkeyController.register(
                registrationID,
                keyCode: hotkey.keyCode,
                modifiers: hotkey.carbonModifiers
            ) { [weak self] in
                Task { @MainActor in self?.switchModule(to: id) }
            }
            recordHotkeyOutcome(
                id: registrationID,
                status: status,
                shortcutName: descriptor.displayName,
                hotkey: hotkey
            )
        }

        if let cycle = moduleHost.cycleHotkey {
            let status = hotkeyController.register(
                NookHotkeyIDs.cycle,
                keyCode: cycle.keyCode,
                modifiers: cycle.carbonModifiers
            ) { [weak self] in
                Task { @MainActor in self?.cycleModule() }
            }
            recordHotkeyOutcome(
                id: NookHotkeyIDs.cycle,
                status: status,
                shortcutName: moduleHost.configuration.labels.shortcut.cycleModulesName,
                hotkey: cycle
            )
        }
    }

    /// Projects one registration's outcome onto the durable hotkey-failure state. A
    /// non-`noErr` status records a failure for `id`; `noErr` clears any prior failure
    /// for that same `id`. Per-id, so failures never overwrite one another.
    private func recordHotkeyOutcome(
        id: String,
        status: OSStatus,
        shortcutName: String,
        hotkey: NookHotkey
    ) {
        let failure =
            status == noErr
            ? nil
            : HotkeyRegistrationFailure(shortcutName: shortcutName, combination: hotkey.display)
        appState.recordHotkeyRegistration(id: id, failure: failure)
    }

    /// The dedup key for the hotkey-registration sink: one *intent change* per user
    /// action, not one emission per upstream `@Published` update.
    private enum HotkeyRegistrationIntent: Equatable {
        /// Recorder is open - live registration is suspended.
        case suspended
        /// Recorder is closed - this hotkey should be registered.
        case bound(NookHotkey)
    }

    /// Keeps the live hotkey registration in sync with `appState`: re-register when the
    /// user picks a new shortcut, and suspend registration entirely while recording.
    ///
    /// `combineLatest` emits once per upstream `@Published` change. A user finishing
    /// recording flips both `$hotkey` (new value) and `$isRecordingHotkey` (false) on
    /// the same runloop turn - two emissions. A naive `removeDuplicates(by: ==)` on
    /// the raw pair wouldn't dedup them (they're distinct), so the sink would unregister
    /// then re-register an extra time, recording the registration outcome twice on the
    /// durable failure channel. Mapping to a `HotkeyRegistrationIntent` collapses the
    /// pair onto *what should happen* - and a recorder opened+cancelled without any
    /// key change deduces to one no-op.
    ///
    /// `internal`, not `private`, so tests can install the sink without bringing up
    /// `NSApp` via the full `start()` path.
    func bindHotkeyRegistration() {
        appState.$hotkey
            .combineLatest(appState.$isRecordingHotkey)
            .map { hotkey, isRecording -> HotkeyRegistrationIntent in
                isRecording ? .suspended : .bound(hotkey)
            }
            .dropFirst()  // skip the cold-launch publish of initial values
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] intent in
                guard let self else { return }
                switch intent {
                    case .suspended:
                        self.hotkeyController.unregister(Self.toggleHotkeyID)
                    case .bound:
                        self.registerGlobalHotkey()
                }
            }
            .store(in: &cancellables)
    }

    private func bindBackdropSynchronization() {
        // `dropFirst` skips the cold-launch publish of the current preferences:
        // `start()` calls `syncNotchBackdrop()` directly so the backdrop is correct
        // before any window appears, and we don't want this sink to fire again on the
        // same value the moment the subscription installs.
        appState.$appearancePreferences
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncNotchBackdrop() }
            .store(in: &cancellables)

        // The chrome is two surfaces, and they do not want the same backdrop: collapsed, a
        // notch-fused panel is the notch's own height with most of its width behind the
        // camera; expanded, it is a tall panel with room for a gradient. Re-resolve on every
        // transition so a resolver - the framework's `.notchFade` included - can answer
        // differently for each.
        //
        // Deliberately *not* `receive(on: RunLoop.main)`, unlike the sinks around it.
        // `@Published` emits in `willSet`, so this runs inside the `withAnimation` that is
        // setting the state: the new backdrop joins that transaction and cross-fades with the
        // transition instead of landing a frame late, after the panel has already resized.
        // The emitted value is what we resolve against - the surface's own `state` property
        // still reads the outgoing one at this point.
        //
        // `.hidden` is filtered out rather than resolved: nothing is painted while hidden, and
        // expand-from-compact routes through `.hidden` between the two visible states (see
        // `Nook._expand`), so resolving it would repaint the backdrop mid-transition and flash
        // whatever the collapsed state maps to across a panel that is on its way open.
        surface.statePublisher
            .filter { $0 != .hidden }
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                self.resolveBackdrops(state: state, form: self.surface.layoutForm)
            }
            .store(in: &cancellables)

        // The resolved layout is the other half of "which surface is this": `.auto` lands on
        // the notch form or the floating one depending on the display, and a backdrop meant to
        // read as the hardware notch is only right on the former. It changes when the window is
        // rebuilt - a new screen, a new presentation - so re-resolve there too. Deferred to the
        // next runloop turn because the publish happens in `willSet` *during* that rebuild;
        // reading the surface back on this one would see the outgoing form.
        surface.layoutFormPublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncNotchBackdrop() }
            .store(in: &cancellables)

        accessibilityObserver = ObserverToken(
            token: NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.systemAppearanceDidChange()
                }
            }
        )
    }

    /// Follows the system's light/dark appearance. Under the `.followSystem` palette both
    /// the backdrop and the default theme depend on it, and nothing else would re-resolve
    /// them until the next expand, collapse, or preference change.
    private func bindSystemAppearance(_ changes: AnyPublisher<Void, Never>) {
        changes
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.systemAppearanceDidChange() }
            .store(in: &cancellables)
    }

    /// Re-applies everything that reads a system appearance setting - light/dark or Reduce
    /// Transparency: the backdrop is resolved again, and every view observing ``appState``
    /// re-renders, which re-runs the configuration's theme resolver.
    private func systemAppearanceDidChange() {
        syncNotchBackdrop()
        appState.objectWillChange.send()
    }

    private func currentResolvedSystemScheme() -> ColorScheme {
        systemColorSchemeProvider()
    }

    func syncNotchBackdrop() {
        // Project the chrome-layout preference onto the surface. `Nook.presentation`
        // rebuilds a visible window in place when this changes, so flipping the
        // Layout picker re-places the chrome immediately.
        surface.presentation = appState.appearancePreferences.presentation

        // Pin the window appearance first: the backdrop's visual-effect material resolves
        // against it, so a forced light/dark theme needs both to agree. A theme that pins the
        // palette pins the window too.
        surface.chromeAppearance = effectiveAppearancePreferences.chromeAppearanceOverride

        resolveBackdrops(state: surface.state, form: surface.layoutForm)
        applyThemeColors()
        // Companions washing in the theme's hover color re-resolve it for the new appearance.
        if displayedTheme.tokens[.hoverWash] != nil {
            applyModuleSurfaceDecorations(moduleHost.displayedConfiguration)
        }
    }

    /// Resolves the chrome's backdrop, and the one companions inherit, for the chrome the
    /// surface is showing right now - and projects both onto it.
    ///
    /// Split out of ``syncNotchBackdrop()`` because it is called from two places with
    /// different ideas of "right now": the appearance path reads the state off the surface,
    /// while the state sink is running *inside* the transition that is changing it and passes
    /// the incoming value instead. Nothing here touches ``NookSurfaceDriving/presentation``,
    /// so a transition can re-resolve without any risk of rebuilding the window under itself.
    private func resolveBackdrops(state: NookState, form: NookChromeForm) {
        // The person's preferences with the displayed theme's pins: a theme that pins the
        // surface style or the strength is painted that way, and host resolvers see it too.
        let preferences = effectiveAppearancePreferences
        let scheme = preferences.effectiveColorScheme(systemScheme: currentResolvedSystemScheme())
        let reduceTransparency = reduceTransparencyProvider()
        // A host can override the state->backdrop mapping; the framework mapping is
        // the default. See `NookChromeBehavior.backdrop`.
        let behavior = moduleHost.chromeBehavior
        let context = NookBackdropContext(
            preferences: preferences,
            colorScheme: scheme,
            reduceTransparency: reduceTransparency,
            state: state,
            form: form
        )
        // The displayed theme's backdrop for this surface style, when it describes one. A
        // host resolver still wins; the framework mapping paints everything else, shaded the
        // theme's way unless the host chose a shading.
        let theme = displayedTheme
        let glassShading =
            behavior.glassShading == .even ? theme.backdrops.glassShading ?? .even : behavior.glassShading
        let themeBackdrop =
            behavior.backdrop == nil
            ? theme.backdrop(in: context, customBackdrops: moduleHost.displayedConfiguration.themeBackdrops) : nil
        let backdrop: NookBackdrop
        if let resolve = behavior.backdrop {
            backdrop = resolve(context)
        } else if let themeBackdrop {
            backdrop = themeBackdrop
        } else {
            backdrop = NookBackdropMapping.notchBackdrop(
                preferences: preferences,
                effectiveColorScheme: scheme,
                reduceTransparency: reduceTransparency,
                glassShading: glassShading,
                state: state
            )
        }
        if surface.backdrop != backdrop {
            surface.backdrop = backdrop
        }
        // Companions inherit their own backdrop only when one is resolved: a host resolver, or
        // the framework's for a glass shading that does not suit a small pill. A host that
        // replaces the chrome's backdrop keeps companions on it unless it resolves theirs too.
        let companionBackdrop: NookBackdrop?
        if let resolve = behavior.companionBackdrop {
            companionBackdrop = resolve(context)
        } else if behavior.backdrop == nil, themeBackdrop == nil {
            companionBackdrop = NookBackdropMapping.companionBackdrop(
                preferences: preferences,
                effectiveColorScheme: scheme,
                reduceTransparency: reduceTransparency,
                glassShading: glassShading,
                state: state
            )
        } else {
            companionBackdrop = nil
        }
        if surface.companionBackdrop != companionBackdrop {
            surface.companionBackdrop = companionBackdrop
        }
    }

    /// Mirrors the surface's live ``NookState`` onto `appState.isNookVisible`, and bounds
    /// ``userInitiatedOpen`` by it: any independent collapse - hover-exit auto-compact,
    /// drag dismiss, arbiter restore - cleanly clears intent without explicit teardown.
    ///
    /// This single sink is the only writer of `appState.isNookVisible` and the only
    /// path that clears `userInitiatedOpen` on independent collapse; the user-action
    /// entry points (``hideNook``, the compact branch of ``toggleNook``) clear intent
    /// synchronously *before* compact runs, then this sink confirms it.
    private func bindSurfaceVisibility() {
        surface.statePublisher
            .map { $0 == .expanded }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                guard let self else { return }
                self.appState.isNookVisible = expanded
                if !expanded {
                    self.setUserInitiatedOpen(false)
                }
            }
            .store(in: &cancellables)
    }

    private func bindNookDragSession() {
        surface.isDragInFlightPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] inFlight in
                self?.appState.isDragInFlight = inFlight
            }
            .store(in: &cancellables)
        // The file-drop handler is projected onto the surface by `applyModuleHooks`,
        // called from the designated `init` and from every switch transaction.
    }

    // MARK: - Nook lifecycle

    /// Toggles the expanded/compact state of the surface based on its live state at the
    /// moment the transition reaches the head of the serial lifecycle chain. A
    /// hover-expanded nook collapses; a compact nook expands.
    public func toggleNook() {
        toggleNook(fromShortcut: false)
    }

    /// ``toggleNook()``, knowing whether the global shortcut asked for it: an open from the
    /// shortcut also gives the nook the keyboard when the host opted in with
    /// ``NookKeyboardBehavior/shortcutTakesKeyboardFocus``.
    func toggleNook(fromShortcut: Bool) {
        appState.resetTransientStatus()
        enqueueLifecycle { [weak self] in
            guard let self else { return }
            // Decide off the surface's live state *at execution time*, not the mirror
            // and not when `toggleNook()` was called - a hover-expanded nook must
            // toggle closed even though no coordinator call opened it, and deciding
            // before the serial chain reaches us would race other queued transitions.
            if self.surface.state == .expanded {
                self.setUserInitiatedOpen(false)
                await self.surface.compact(on: nil)
            } else {
                self.setUserInitiatedOpen(true)
                self.projectStaysExpanded()
                await self.surface.expand(on: nil)
                if fromShortcut, self.moduleHost.chromeBehavior.keyboard.shortcutTakesKeyboardFocus,
                    self.surface.state == .expanded
                {
                    self.surface.takeKeyboardFocus()
                }
            }
        }
    }

    // MARK: - Keyboard focus

    /// `true` while the nook has the keyboard, so typing goes to its focused text input rather
    /// than the app in front.
    public var nookHasKeyboardFocus: Bool { surface.hasKeyboardFocus }

    /// Gives the nook the keyboard without activating the app, so typing reaches its focused text
    /// input - for a field focused when it appears, or a key handler in the nook. The app in front
    /// stays in front. Returns `false` while the nook is hidden.
    ///
    /// A click anywhere in the nook already gives it the keyboard, and a click on a text input
    /// always does. The nook hands the keyboard back by itself when it collapses or hides, and
    /// its text inputs give up focus when the person clicks into another app. Views in the nook
    /// can call ``NookChromeActions/takeKeyboardFocus`` instead.
    @discardableResult
    public func takeNookKeyboardFocus() -> Bool {
        surface.takeKeyboardFocus()
    }

    /// Hands the keyboard back to the app in front and ends editing in the nook's focused text
    /// input. Does nothing while the nook does not have the keyboard.
    public func releaseNookKeyboardFocus() {
        surface.releaseKeyboardFocus()
    }

    /// The nook's panel right now, or `nil` while the nook is hidden - for window-level work the
    /// framework has no API for. Read it when you need it rather than keeping it: the nook builds
    /// a new panel when it shows after being hidden and when it moves to another display. For
    /// typing, use ``takeNookKeyboardFocus()``.
    public var nookWindow: NSWindow? { surface.window }

    /// Expands the surface and marks the open as user-initiated, so a subsequent transient
    /// presenter is gated by ``isUserEngaged``.
    public func showNook() {
        appState.resetTransientStatus()
        enqueueLifecycle { [weak self] in
            guard let self else { return }
            self.setUserInitiatedOpen(true)
            self.projectStaysExpanded()
            await self.surface.expand(on: nil)
        }
    }

    /// Switches to the home view and expands the surface.
    public func showHome() {
        appState.showHome()
        showNook()
    }

    /// Shows the Settings screen. When the host disabled Settings
    /// (``NookTopBarConfiguration/showsSettings`` is `false`) there is no Settings UI, so this
    /// falls back to showing the home surface and `viewMode` stays `.home`.
    public func showSettings() {
        guard configuration.topBar.showsSettings else {
            showNook()
            return
        }
        appState.showSettings()
        showNook()
    }

    /// Compacts the surface back into the pill. Clears the user-initiated-open flag
    /// synchronously so any subsequent transient presenter is no longer gated.
    public func hideNook() {
        enqueueLifecycle { [weak self] in
            guard let self else { return }
            self.setUserInitiatedOpen(false)
            await self.surface.compact(on: nil)
        }
    }

    /// Flips the persisted "stay expanded on hover-exit" preference and projects the new
    /// value onto the surface immediately. Backed by ``NookAppearancePreferences/keepNookOpen``,
    /// so the choice survives across launches.
    public func toggleKeepNookOpen() {
        appState.keepNookOpen.toggle()
        projectStaysExpanded()
    }

    /// Projects the boolean "ignore hover-exit auto-compact" override onto the surface.
    /// Internal because modules should not flip this directly - they pin and unpin
    /// through ``NookPresentationPinning`` (resolved from `\.appServices`), which
    /// ref-counts overlapping presenters and folds into ``isUserEngaged`` for the
    /// arbiter. This method is the broker's lone client; it is also called by
    /// ``resetAllSettingsToDefaults()`` and the user-action entry points to project
    /// the persisted `keepNookOpen` preference back onto the surface.
    func setStaysExpandedOverride(_ active: Bool) {
        if active {
            surface.staysExpandedOnHoverExit = true
        } else {
            projectStaysExpanded()
        }
    }

    /// Projects every reason to hold the nook open past a hover exit onto the surface: the
    /// persisted keep-open lock, or an outstanding ``NookPresentationPinning`` pin. The one
    /// writer besides a pin's arrival, so turning the lock off, resetting settings, or opening
    /// the nook never drops a pin that is still held.
    ///
    /// When this turns the hold off after the pointer left during it, the surface collapses
    /// then, as if the pointer had just left.
    func projectStaysExpanded() {
        let stays = appState.keepNookOpen || presentationPinning.isPinned
        if surface.staysExpandedOnHoverExit != stays {
            surface.staysExpandedOnHoverExit = stays
        }
    }

    /// Subscribes the coordinator to the host-wide ``NookPresentationPinning``
    /// broker. The broker emits on 0->1 and N->0 pin-count edges; on each edge we
    /// project the boolean onto the surface via ``setStaysExpandedOverride(_:)``.
    /// The arbiter side is wired implicitly through ``isUserEngaged`` and
    /// ``userEngagementChanges`` - both already consult `presentationPinning`.
    private func bindPresentationPinning() {
        presentationPinning.pinChanges
            .receive(on: RunLoop.main)
            .sink { [weak self] pinned in
                self?.setStaysExpandedOverride(pinned)
            }
            .store(in: &cancellables)
    }

    // MARK: - Reset

    /// Returns appearance, the global hotkey, and the display preference to the host's launch
    /// defaults (``AppState/preferenceDefaults``) and forgets the person's choices, so each one
    /// follows the host's defaults again - including a default a later build changes. Every
    /// reset routes through `AppState`, so persistence and observers fire once per preference.
    ///
    /// The hold on the surface is then projected from the reset lock (and any pin still held)
    /// rather than a hardcoded `false`, and the backdrop is resolved again.
    public func resetAllSettingsToDefaults() {
        appState.resetAppearancePreferences()
        appState.resetHotkey()
        appState.resetDisplayPreference()
        projectStaysExpanded()
        syncNotchBackdrop()
    }
}

// MARK: - NookSurfacePresenting

extension AppCoordinator: NookSurfacePresenting {
    /// The user owns the surface while they're hovering it, while they opened it
    /// themselves, or while a module's transient presentation (popover/sheet) has the
    /// notch pinned via ``NookPresentationPinning``. A transient arbiter presenter
    /// pauses in any of those cases.
    ///
    /// Sources from `userInitiatedOpen` (user intent) - NOT `appState.isNookVisible`
    /// (surface mirror) - so the arbiter's own `expand()` never trips this gate on a
    /// subsequent preempting claim.
    ///
    /// **The pin disjunct closes a real hole**, not a theoretical one. A hover-opened
    /// surface has `userInitiatedOpen == false`; the moment a module presents a
    /// `.popover` the pointer leaves the notch window and `surface.isHovering` flips
    /// `false`; without the pin, a competing `.urgent` claim from another module would
    /// be granted at that exact moment and yank the surface from under the popover.
    public var isUserEngaged: Bool {
        userInitiatedOpen
            || surface.isHovering
            || presentationPinning.isPinned
            || surface.isLayoutGraceActive
    }

    /// Emits whenever ``isUserEngaged`` changes - the merge of the user-intent flag,
    /// the surface's hover publisher, and the presentation-pin broker, deduplicated.
    ///
    /// Verified: in-tree consumers of `isUserEngaged` / `userEngagementChanges`
    /// (`NookActivityQueue.waitWhileUserEngaged(_:)` at NookActivityQueue.swift:234,
    /// `SurfaceArbiter`'s engagement gate at SurfaceArbiter.swift:109/198) are
    /// idempotent under repeated same-value events - the activity queue polls in a
    /// while-loop, and the arbiter consults the flag fresh on each claim. Adding a
    /// third publisher to the `combineLatest` increases emission frequency only on
    /// pin transitions, which `removeDuplicates()` collapses to the true edges.
    public var userEngagementChanges: AnyPublisher<Bool, Never> {
        userInitiatedOpenSubject
            .combineLatest(
                surface.isHoveringPublisher,
                presentationPinning.pinChanges,
                surface.isLayoutGraceActivePublisher
            )
            .map { $0 || $1 || $2 || $3 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Grants or denies the claim through the `SurfaceArbiter`.
    public func beginTransientPresentation(_ claim: NookSurfaceClaim) async -> NookSurfaceToken? {
        await arbiter.begin(claim)
    }

    /// Releases the claim through the `SurfaceArbiter`.
    public func endTransientPresentation(_ token: NookSurfaceToken) async {
        await arbiter.end(token)
    }
}
