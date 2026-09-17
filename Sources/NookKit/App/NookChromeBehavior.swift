// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// Host-process-global *chrome behavior* knobs that the framework otherwise hardcodes:
/// hover side-effects, the cold-launch greeting, how appearance preferences map to the
/// surface backdrop, and how the nook shares the keyboard.
///
/// These are distinct from ``NookConfiguration``'s per-surface content/theme seams -
/// they describe how the single shared notch surface *behaves*, so they live at the
/// host-process level (``NookHostConfiguration/chromeBehavior``). The single-module path
/// mirrors them on ``NookConfiguration/chromeBehavior`` and forwards onto the synthesized
/// host. The default value reproduces today's framework behavior exactly.
///
/// `Sendable`: assembled at a `main.swift`'s nonisolated top level and handed to
/// `NookApp.main`, which crosses to the main actor - like the configurations that carry
/// it. Not `Equatable` because ``backdrop`` carries a closure.
public struct NookChromeBehavior: Sendable {
    /// Resolves the surface backdrop from the live appearance state. Returns the
    /// `NSVisualEffectView` material / darken / solid fill the chrome paints behind its
    /// content. Receives the current ``NookAppearancePreferences``, the effective
    /// `ColorScheme` (after the host's palette override + the system scheme), and whether
    /// the system's Reduce Transparency is on.
    ///
    /// `@Sendable @MainActor`: invoked during the main-actor backdrop sync and carried by
    /// a `Sendable` `NookChromeBehavior`.
    public typealias BackdropResolver =
        @Sendable @MainActor (NookAppearancePreferences, ColorScheme, Bool) -> NookBackdrop

    /// Side-effects to apply while the cursor is over the chrome. Defaults to `[]` (the
    /// framework default - neither hover-keep-visible nor hover haptics). Set to
    /// `NookHoverBehavior.all` (or a subset) to opt in. Applied when the surface is built;
    /// ``AppCoordinator/replaceChromeBehavior(_:)`` changes it at runtime.
    public var hoverBehavior: NookHoverBehavior

    /// Whether the one-shot perimeter shimmer plays at cold launch. Defaults to `true`
    /// (today's greeting). Set to `false` for a silent launch - the chrome still settles
    /// into its compact launch state, it just skips the feedback flourish.
    public var showsLaunchShimmer: Bool

    /// Overrides how appearance preferences map to the surface backdrop. `nil` (the
    /// default) uses the framework mapping (``NookBackdropMapping/notchBackdrop(preferences:effectiveColorScheme:reduceTransparency:)``):
    /// solid black/white for `.solid` or Reduce Transparency, otherwise a `.sidebar`
    /// vibrancy with a legibility darken pass. Supply a resolver to paint a brand-specific
    /// material, darken, or solid color while still reacting to the live appearance state.
    public var backdrop: BackdropResolver?

    /// What companions inheriting the chrome's backdrop paint (`NookCompanionBackdrop.inherit`),
    /// resolved from the same live appearance state as ``backdrop``. `nil` (the default) uses
    /// the framework's choice: the chrome's own backdrop, except under
    /// ``NookGlassShading/notchFade``, where companions get the same glass with a light even
    /// tint instead of a squeezed copy of the tall fade. A resolver that returns `nil` gives
    /// companions the chrome's backdrop.
    public var companionBackdrop: CompanionBackdropResolver?

    /// Resolves the backdrop companions inherit; `nil` means the chrome's own. See
    /// ``companionBackdrop``.
    public typealias CompanionBackdropResolver =
        @Sendable @MainActor (NookAppearancePreferences, ColorScheme, Bool) -> NookBackdrop?

    /// How the framework's Liquid Glass is shaded when the person picks Liquid Glass. Defaults
    /// to ``NookGlassShading/even``. Ignored when ``backdrop`` supplies a resolver of its own.
    ///
    /// ```swift
    /// configuration.chromeBehavior.glassShading = .notchFade  // black at the notch, clear below
    /// ```
    public var glassShading: NookGlassShading

    /// How the nook shares the keyboard with the app in front: whether the global shortcut gives
    /// it the keyboard, and whether the framework installs the Edit menu text inputs need for
    /// their shortcuts. See ``NookKeyboardBehavior``.
    public var keyboard: NookKeyboardBehavior

    public init(
        hoverBehavior: NookHoverBehavior = [],
        showsLaunchShimmer: Bool = true,
        backdrop: BackdropResolver? = nil,
        glassShading: NookGlassShading = .even,
        companionBackdrop: CompanionBackdropResolver? = nil,
        keyboard: NookKeyboardBehavior = .default
    ) {
        self.hoverBehavior = hoverBehavior
        self.showsLaunchShimmer = showsLaunchShimmer
        self.backdrop = backdrop
        self.glassShading = glassShading
        self.companionBackdrop = companionBackdrop
        self.keyboard = keyboard
    }

    /// The framework defaults - what ships when a host sets no chrome behavior. Using
    /// this reproduces today's behavior exactly.
    public static let `default` = NookChromeBehavior()
}

/// How the nook shares the keyboard with the app in front.
///
/// The nook's panel never activates the app: the app the person was using stays in front, and
/// the nook takes the keyboard only for typing into it. A click on a text input in the nook
/// always gives it the keyboard, and the keyboard goes back to the app in front when the nook
/// collapses or hides. These knobs cover the rest.
public struct NookKeyboardBehavior: Sendable, Equatable {
    /// When the global show/hide shortcut opens the nook, also give the nook the keyboard, so a
    /// text input that has focus takes typing without a click. Defaults to `false`: the shortcut
    /// only shows the nook, and typing still goes to the app in front.
    public var shortcutTakesKeyboardFocus: Bool

    /// Install the hidden Edit menu (``NookEditMenu``) at launch when the app has no Edit menu of
    /// its own, so Command-X, C, V, A, Z, and Shift-Command-Z work in text inputs. Defaults to
    /// `true`.
    public var installsEditMenu: Bool

    public init(shortcutTakesKeyboardFocus: Bool = false, installsEditMenu: Bool = true) {
        self.shortcutTakesKeyboardFocus = shortcutTakesKeyboardFocus
        self.installsEditMenu = installsEditMenu
    }

    /// The framework defaults: the shortcut only shows the nook, and the Edit menu is installed.
    public static let `default` = NookKeyboardBehavior()
}
