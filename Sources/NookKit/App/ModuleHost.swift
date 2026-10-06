// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import SwiftUI

/// The indirection layer between ``AppCoordinator`` and the active ``NookModule``.
///
/// `AppCoordinator` builds the notch surface exactly once, but a multi-module host
/// swaps which module's content the surface shows at runtime. `ModuleHost` is the
/// single observable seam that makes that possible: the surface's expanded and compact
/// content are *router views* observing this object, so re-publishing
/// ``configuration`` re-renders the surface with the new module's content, theme, and
/// chrome - without rebuilding the `Nook` or its window.
///
/// In a single-module host the active module never changes; the object still exists so
/// the coordinator has a uniform path to the active configuration and context.
@MainActor
public final class ModuleHost: ObservableObject {
    /// All registered modules and their lazily-built instances.
    public let registry: NookModuleRegistry

    /// The id of the module whose content currently fills the surface.
    @Published public private(set) var activeModuleID: String

    /// The active module's surface configuration - home/compact content, theme, chrome
    /// opt-outs, lifecycle hooks. Re-publishing this is what a module switch *is*; the
    /// router views observe it.
    @Published public private(set) var configuration: NookConfiguration

    public init(registry: NookModuleRegistry) {
        self.registry = registry
        let id = registry.defaultModuleID
        self.activeModuleID = id
        self.configuration = Self.prepared(
            registry.module(for: id)?.makeConfiguration() ?? NookConfiguration(),
            of: id,
            registry: registry
        )
        self.chromeBehavior = registry.chromeBehavior
    }

    /// Single-module convenience - wraps one ``NookConfiguration`` as a lone module so
    /// the existing `NookApp.main(_:)` entry points stay a special case of the host.
    public convenience init(configuration: NookConfiguration) {
        var host = NookHostConfiguration()
        // Forward the single-module path's host-global concerns onto the host that
        // actually owns them (matches `NookApp.main(_ configuration:)`).
        host.chromeBehavior = configuration.chromeBehavior
        host.branding = configuration.branding
        host.showsMenuBarExtra = configuration.showsMenuBarExtra
        host.register(
            NookModuleDescriptor(id: ModuleHost.singleModuleID, displayName: "Nook")
        ) { configuration }
        self.init(registry: host.makeRegistry())
    }

    /// Descriptor id used for the implicit lone module of a single-configuration host.
    public nonisolated static let singleModuleID = "opennook.module.default"

    /// All registered modules' descriptors, in registration order.
    public var descriptors: [NookModuleDescriptor] { registry.descriptors }

    /// The live active module, constructed on first access.
    public var activeModule: NookModule? { registry.module(for: activeModuleID) }

    /// The active module's isolated context.
    public var activeContext: NookModuleContext? { registry.context(for: activeModuleID) }

    /// The active module's service bag - what the surface binds to `\.appServices`.
    /// Falls back to an empty bag in the impossible case that no context can be resolved
    /// (the active module is always registered, so in practice this branch is unreachable).
    public var activeServices: AppServices { activeContext?.services ?? AppServices() }

    /// `true` when more than one module is registered - i.e. a switcher is meaningful.
    public var isMultiModule: Bool { registry.descriptors.count > 1 }

    /// Optional global shortcut that cycles modules, as configured by the host.
    public var cycleHotkey: NookHotkey? { registry.cycleHotkey }

    /// Host-product identity surfaced through the framework chrome (the About card,
    /// the show/hide hotkey label, the menu-bar fallback). See ``NookHostBranding``.
    public var branding: NookHostBranding { registry.branding }

    /// Process-global chrome behavior - hover side-effects, the cold-launch shimmer, and
    /// the appearance->backdrop mapping. See ``NookChromeBehavior``.
    ///
    /// Starts as the host's ``NookHostConfiguration/chromeBehavior``;
    /// ``AppCoordinator/replaceChromeBehavior(_:)`` replaces it at runtime.
    public internal(set) var chromeBehavior: NookChromeBehavior

    /// Whether the framework installs its menu-bar status item. See
    /// ``NookHostConfiguration/showsMenuBarExtra``.
    public var showsMenuBarExtra: Bool { registry.showsMenuBarExtra }

    /// Where the module switcher appears. See ``NookModuleSwitcherPlacement`` and
    /// ``NookHostConfiguration/moduleSwitcherPlacement``.
    public var switcherPlacement: NookModuleSwitcherPlacement { registry.switcherPlacement }

    /// Modules that want the user's attention while in the background - the switcher
    /// badges these. A backgrounded module (or a component running on its behalf) calls
    /// ``requestAttention(for:)``; switching to a module clears its badge.
    @Published public private(set) var attentionModuleIDs: Set<String> = []

    /// Flags `moduleID` as wanting attention. Ignored for the foreground module - it is
    /// already on screen, so there is nothing to badge.
    public func requestAttention(for moduleID: String) {
        guard moduleID != activeModuleID else { return }
        attentionModuleIDs.insert(moduleID)
    }

    /// Clears the attention badge for `moduleID`.
    public func clearAttention(for moduleID: String) {
        attentionModuleIDs.remove(moduleID)
    }

    /// Switches the foreground module: activates and re-configures the incoming module.
    ///
    /// The outgoing module is *not* deactivated here. Its documented order is
    /// ``NookModule/prepareForSwitchAway()``, then ``NookModule/onDeactivate()``, then any
    /// ``NookModuleDescriptor/backgroundPolicy``-driven unload, and the first of those is
    /// async, so ``AppCoordinator`` runs it after the switch and then calls
    /// ``finishSwitchAway(from:)`` for the rest.
    ///
    /// This is pure module bookkeeping. The surface-side effects of a switch - re-wiring
    /// the `Nook`'s lifecycle hooks, the once-per-module `onReady`, the synthetic
    /// `onExpand` - are ``AppCoordinator``'s, driven off the `$configuration` re-publish.
    ///
    /// Returns `false` without changing anything when `id` is unregistered or already
    /// the active module.
    @discardableResult
    func switchModule(to id: String) -> Bool {
        guard id != activeModuleID, registry.descriptor(for: id) != nil else { return false }
        guard let incoming = registry.module(for: id) else { return false }

        incoming.onActivate()
        activeModuleID = id
        attentionModuleIDs.remove(id)
        configuration = prepared(incoming.makeConfiguration(), of: id)
        // The incoming module's own content now fills the surface; it is no longer a
        // background module presenting over another.
        if presentedBackgroundModuleID == id {
            presentBackgroundModule(nil)
        }
        return true
    }

    /// Completes switching away from `id` once its ``NookModule/prepareForSwitchAway()``
    /// has returned: calls ``NookModule/onDeactivate()``, then unloads the module when its
    /// ``NookModuleDescriptor/backgroundPolicy`` is `.unloadOnSwitchAway`.
    ///
    /// A no-op when `id` is the active module again (the user switched back before the
    /// switch away finished) or is not loaded. Returns `true` when the module was unloaded.
    @discardableResult
    func finishSwitchAway(from id: String) -> Bool {
        guard id != activeModuleID, registry.isLoaded(id) else { return false }
        registry.module(for: id)?.onDeactivate()
        guard registry.descriptor(for: id)?.backgroundPolicy == .unloadOnSwitchAway else { return false }
        if presentedBackgroundModuleID == id {
            presentBackgroundModule(nil)
        }
        registry.unload(id)
        return true
    }

    // MARK: - Background presentation

    /// The background module whose content fills the surface while one of its claims is
    /// the top surface claim - an `.urgent` activity from a `.stayResident` module the user
    /// is not looking at. `nil` while the surface shows the active module, which is almost
    /// always. Driven by ``AppCoordinator`` from the surface arbiter.
    @Published private(set) var presentedBackgroundModuleID: String?

    /// The configuration of ``presentedBackgroundModuleID``, built when its claim reached
    /// the top of the stack.
    @Published private(set) var presentedBackgroundConfiguration: NookConfiguration?

    /// The id of the module whose content the surface shows right now: the presenting
    /// background module, otherwise the active module.
    var displayedModuleID: String { presentedBackgroundModuleID ?? activeModuleID }

    /// The configuration the router views render: the presenting background module's,
    /// otherwise the active module's.
    var displayedConfiguration: NookConfiguration { presentedBackgroundConfiguration ?? configuration }

    /// The service bag of ``displayedModuleID`` - what the surface binds to `\.appServices`.
    var displayedServices: AppServices {
        guard let id = presentedBackgroundModuleID, registry.isLoaded(id),
            let services = registry.context(for: id)?.services
        else {
            return activeServices
        }
        return services
    }

    /// Shows `id`'s content on the surface in place of the active module's, or goes back to
    /// the active module's for `nil`. Ignored for the active module (its content is already
    /// there) and for a module that is not loaded (building one just to show it would run a
    /// module nobody activated). Returns `true` when the displayed module changed.
    @discardableResult
    func presentBackgroundModule(_ id: String?) -> Bool {
        let target: String? = {
            guard let id, id != activeModuleID, registry.isLoaded(id) else { return nil }
            return id
        }()
        guard target != presentedBackgroundModuleID else { return false }
        presentedBackgroundConfiguration = target.flatMap { id in
            registry.module(for: id).map { prepared($0.makeConfiguration(), of: id) }
        }
        presentedBackgroundModuleID = target
        return true
    }

    /// Builds the active module's configuration again and re-publishes it, so the router
    /// views re-render from it. Bookkeeping only, like ``switchModule(to:)``: projecting the
    /// result onto the surface is ``AppCoordinator/reloadActiveConfiguration()``'s job, which
    /// is why this stays internal.
    func reloadConfiguration() {
        guard let module = activeModule else { return }
        configuration = prepared(module.makeConfiguration(), of: activeModuleID)
    }

    // MARK: - Theme

    /// `configuration` with the theme the chrome draws it with filled in, so everything that
    /// reads ``NookConfiguration/chromeTheme`` downstream sees it. In order: the
    /// configuration's own ``NookConfiguration/chromeThemeSource``, its own theme, the host's
    /// source, the host's theme.
    static func themed(_ configuration: NookConfiguration, registry: NookModuleRegistry) -> NookConfiguration {
        var themed = configuration
        if let source = configuration.chromeThemeSource {
            themed.chromeTheme = source.theme
        } else if configuration.chromeTheme == nil {
            if let source = registry.chromeThemeSource {
                themed.chromeTheme = source.theme
            } else if let hostTheme = registry.chromeTheme {
                themed.chromeTheme = hostTheme
            }
        }
        return themed
    }

    /// `configuration`, just built by the module `id`, themed, with its widgets recorded for
    /// boards. Every configuration the host builds passes through here.
    static func prepared(_ configuration: NookConfiguration, of id: String, registry: NookModuleRegistry)
        -> NookConfiguration
    {
        if registry.isLoaded(id), let services = registry.context(for: id)?.services {
            registry.widgets.record(configuration, moduleID: id, services: services)
        }
        return themed(configuration, registry: registry)
    }

    private func prepared(_ configuration: NookConfiguration, of id: String) -> NookConfiguration {
        Self.prepared(configuration, of: id, registry: registry)
    }

    /// Builds the presenting background module's configuration again, for a theme that
    /// changed under it. A no-op while the active module is on the surface.
    func reloadPresentedBackgroundConfiguration() {
        guard let id = presentedBackgroundModuleID else { return }
        presentedBackgroundConfiguration = registry.module(for: id).map { prepared($0.makeConfiguration(), of: id) }
    }
}
