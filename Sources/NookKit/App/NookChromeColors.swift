// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Colors for single parts of the chrome, beyond the shared palette in ``NookResolvedTheme``.
///
/// Each is optional: `nil` (the default) draws the part the way it has always been drawn,
/// from the palette. A theme sets them through the `banner.severity.*.color` tokens, for
/// example to give errors the theme's `color.destructive`:
///
/// ```json
/// "components": { "banner.severity.error.color": "{color.destructive}" }
/// ```
///
/// The values reach the views through the chrome environment (`\.nookChromeColors`).
public struct NookChromeColors: Equatable, Sendable {
    /// The status banner's glyph for an error. `nil` uses the palette's accent.
    public var bannerSeverityError: Color?
    /// The status banner's glyph for a warning. `nil` uses the palette's accent.
    public var bannerSeverityWarning: Color?
    /// The status banner's glyph for information. `nil` uses the palette's accent.
    public var bannerSeverityInfo: Color?
    /// The status banner's glyph for a success. `nil` uses the palette's accent.
    public var bannerSeveritySuccess: Color?

    public init(
        bannerSeverityError: Color? = nil,
        bannerSeverityWarning: Color? = nil,
        bannerSeverityInfo: Color? = nil,
        bannerSeveritySuccess: Color? = nil
    ) {
        self.bannerSeverityError = bannerSeverityError
        self.bannerSeverityWarning = bannerSeverityWarning
        self.bannerSeverityInfo = bannerSeverityInfo
        self.bannerSeveritySuccess = bannerSeveritySuccess
    }

    /// Every part drawn from the palette, as the chrome always has.
    public static let `default` = NookChromeColors()

    /// The banner glyph color for `severity`, or `nil` to use the palette's accent.
    public func bannerSeverity(_ severity: NookStatusSeverity) -> Color? {
        switch severity {
            case .error: bannerSeverityError
            case .warning: bannerSeverityWarning
            case .info: bannerSeverityInfo
            case .success: bannerSeveritySuccess
        }
    }
}

extension NookTheme {
    /// The theme's colors for single parts of the chrome in `context`. Each token the theme
    /// leaves at its default (the palette's accent) stays `nil`, so the part keeps following
    /// the palette.
    public func chromeColors(in context: NookThemeContext) -> NookChromeColors {
        let resolver = NookThemeResolver(theme: self)
        func color(_ id: NookColorID) -> Color? {
            tokens[id] == nil ? nil : resolver.color(id, in: context)
        }
        return NookChromeColors(
            bannerSeverityError: color(.bannerSeverityError),
            bannerSeverityWarning: color(.bannerSeverityWarning),
            bannerSeverityInfo: color(.bannerSeverityInfo),
            bannerSeveritySuccess: color(.bannerSeveritySuccess)
        )
    }
}

private struct NookChromeColorsKey: EnvironmentKey {
    static let defaultValue: NookChromeColors = .default
}

extension EnvironmentValues {
    /// Colors for single parts of the chrome. See ``NookChromeColors``.
    public var nookChromeColors: NookChromeColors {
        get { self[NookChromeColorsKey.self] }
        set { self[NookChromeColorsKey.self] = newValue }
    }
}
