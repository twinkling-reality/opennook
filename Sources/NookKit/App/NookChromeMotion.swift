// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Host-tunable animation curves for the chrome's *in-panel* motion - the transitions
/// inside the expanded surface and top bar. Defaults reproduce today's springs exactly.
///
/// This is distinct from ``NookConfiguration/transitions`` (`NookTransitionConfiguration`),
/// which governs the surface-level expand / collapse / compact conversion. These curves
/// drive the home<->settings swap, the status banner, the breadcrumb, the leading
/// cluster's back / hover reveals, the Settings disclosure groups, the module switch, and
/// the `NookComponents` activity card.
///
/// Set via ``NookConfiguration/motion``. The values reach the views through the chrome
/// environment (`\.nookChromeMotion`).
public struct NookChromeMotion: Sendable, Equatable {
    /// Home<->Settings swap and the gear toggle (and the matching `viewMode` animations).
    public var viewModeChange: Animation

    /// The leading cluster's back-control activation (exiting Settings / clearing a
    /// breadcrumb).
    public var leadingClusterBack: Animation

    /// The leading cluster's hover-reveal of the title.
    public var leadingClusterHover: Animation

    /// The status banner's appearance / dismissal.
    public var statusBanner: Animation

    /// The module-breadcrumb's appearance / change.
    public var breadcrumb: Animation

    /// A Settings group opening or closing (``NookSettingsGroup``, and the built-in
    /// Settings screen's groups).
    public var settingsDisclosure: Animation

    /// The cross-fade when a multi-module host switches the module filling the surface.
    public var moduleSwitch: Animation

    /// A `NookComponents` activity card taking over the home view or handing it back
    /// (`NookActivityHost`).
    public var activityCard: Animation

    public init(
        viewModeChange: Animation = .spring(response: 0.38, dampingFraction: 0.84),
        leadingClusterBack: Animation = .spring(response: 0.34, dampingFraction: 0.85),
        leadingClusterHover: Animation = .spring(response: 0.26, dampingFraction: 0.82),
        statusBanner: Animation = .spring(response: 0.34, dampingFraction: 0.86),
        breadcrumb: Animation = .easeOut(duration: 0.18),
        settingsDisclosure: Animation = .spring(response: 0.30, dampingFraction: 0.86),
        moduleSwitch: Animation = .easeInOut(duration: 0.22),
        activityCard: Animation = .spring(response: 0.36, dampingFraction: 0.86)
    ) {
        self.viewModeChange = viewModeChange
        self.leadingClusterBack = leadingClusterBack
        self.leadingClusterHover = leadingClusterHover
        self.statusBanner = statusBanner
        self.breadcrumb = breadcrumb
        self.settingsDisclosure = settingsDisclosure
        self.moduleSwitch = moduleSwitch
        self.activityCard = activityCard
    }

    /// The framework-default springs - reproduces today's in-panel motion.
    public static let `default` = NookChromeMotion()
}

private struct NookChromeMotionKey: EnvironmentKey {
    static let defaultValue: NookChromeMotion = .default
}

extension EnvironmentValues {
    /// Host-tunable in-panel motion curves. See ``NookChromeMotion``.
    public var nookChromeMotion: NookChromeMotion {
        get { self[NookChromeMotionKey.self] }
        set { self[NookChromeMotionKey.self] = newValue }
    }
}
