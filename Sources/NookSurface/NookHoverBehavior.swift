// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit

/// Side-effects to apply while the cursor is over the nook chrome. Combine via option-set syntax.
public struct NookHoverBehavior: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Hover keeps the surface visible past hide animations.
    public static let keepVisible = NookHoverBehavior(rawValue: 1 << 0)

    /// Trigger a subtle haptic on hover-state transitions. Which one is
    /// ``Nook/hoverHaptic``; the `.alignment` pattern by default.
    public static let hapticFeedback = NookHoverBehavior(rawValue: 1 << 1)

    public static let all: NookHoverBehavior = [.keepVisible, .hapticFeedback]
}

/// The trackpad haptic played on hover changes. See ``Nook/hoverHaptic``.
///
/// macOS plays it only on a Force Touch trackpad with haptic feedback turned on in System
/// Settings, so a missed pulse on a mouse is expected.
public struct NookHoverHaptic: Equatable, Sendable {
    /// The AppKit haptic pattern: `.alignment`, `.levelChange`, or `.generic`.
    public var pattern: NSHapticFeedbackManager.FeedbackPattern
    /// When the haptic plays relative to the hover change.
    public var performanceTime: NSHapticFeedbackManager.PerformanceTime

    /// A hover haptic playing `pattern` at `performanceTime`.
    public init(
        pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment,
        performanceTime: NSHapticFeedbackManager.PerformanceTime = .default
    ) {
        self.pattern = pattern
        self.performanceTime = performanceTime
    }

    /// The built-in hover haptic: the `.alignment` pattern at the default time.
    public static let standard = NookHoverHaptic()
}
