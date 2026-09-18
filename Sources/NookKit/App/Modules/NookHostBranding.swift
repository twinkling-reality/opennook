// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// A host brand mark - builds the mark view at a requested size and color. The framework
/// renders it in the top-bar leading cluster (when no `leadingIcon` is set), the About
/// card, and (as a template image) the menu-bar status item.
///
/// `@Sendable @MainActor`: builds a SwiftUI view during main-actor rendering, carried by
/// a `Sendable` ``NookHostBranding``.
public typealias NookBrandMark = @Sendable @MainActor (_ size: CGFloat, _ color: Color) -> AnyView

/// Host-level identity surfaced through the framework chrome.
///
/// Strings here name the *host product* (the `.app` the user installed), not any
/// individual module - they are how the chrome labels itself across the multi-module
/// host's shared surface. The About card reads ``hostName`` and ``hostTagline``; the
/// show/hide hotkey label and the menu-bar fallback read ``hostName``; the brand ``mark``
/// replaces the OpenNook glyph across the chrome.
///
/// A single-module host can set these on ``NookConfiguration/branding`` (forwarded onto
/// the synthesized host); multi-module hosts set ``NookHostConfiguration/branding``.
public struct NookHostBranding: Sendable, Equatable {
    /// Display name of the host product. Used in About, in the show/hide hotkey label
    /// ("Show \(hostName)"), and in the menu-bar fallback's "Show \(hostName)" / icon
    /// accessibility text.
    public var hostName: String

    /// One-line "about" tagline. `nil` falls back to the framework's stock line, which
    /// describes the host as built with OpenNook.
    public var hostTagline: String?

    /// Replaces the OpenNook ``NookMark`` glyph wherever the chrome renders the brand
    /// mark - the top-bar leading cluster (when ``NookTopBarConfiguration/leadingIcon`` is
    /// `nil`), the About card, and the menu-bar status icon. `nil` (the default) keeps the
    /// OpenNook mark. Not part of `Equatable` (a closure can't be compared) - two
    /// brandings are equal when their strings match.
    public var mark: NookBrandMark?

    /// The menu-bar status item's icon, when it should differ from ``mark``. `nil` (the default)
    /// draws ``mark`` there, or the OpenNook mark when that is `nil` too. Like the mark, it is
    /// drawn as a template image, so the menu bar tints it for light and dark menu bars. Not part
    /// of `Equatable`.
    ///
    /// ```swift
    /// configuration.branding.menuBarIcon = NookHostBranding.symbol("sparkles")
    /// configuration.branding.menuBarIcon = { size, _ in
    ///     AnyView(Image("MenuIcon", bundle: .module).resizable().frame(width: size, height: size))
    /// }
    /// ```
    public var menuBarIcon: NookBrandMark?

    public init(
        hostName: String = "Nook",
        hostTagline: String? = nil,
        mark: NookBrandMark? = nil,
        menuBarIcon: NookBrandMark? = nil
    ) {
        self.hostName = hostName
        self.hostTagline = hostTagline
        self.mark = mark
        self.menuBarIcon = menuBarIcon
    }

    /// A mark or menu-bar icon drawn from the SF Symbol `name`, sized to the requested size.
    public static func symbol(_ name: String) -> NookBrandMark {
        { size, color in
            AnyView(
                Image(systemName: name)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            )
        }
    }

    /// Equality ignores ``mark`` (closures aren't comparable): two brandings are equal
    /// when their `hostName` and `hostTagline` match.
    public static func == (lhs: NookHostBranding, rhs: NookHostBranding) -> Bool {
        lhs.hostName == rhs.hostName && lhs.hostTagline == rhs.hostTagline
    }

    /// The single-module / unconfigured-host default. Reproduces the demo's strings
    /// exactly so `NookApp.main { ... }` is unchanged.
    public static let `default` = NookHostBranding()

    /// Builds the brand mark view at the given size/color - the host's ``mark`` if set,
    /// otherwise the framework ``NookMarkView`` at the supplied `strokeWidth`.
    @MainActor
    public func markView(size: CGFloat, strokeWidth: CGFloat, color: Color) -> AnyView {
        if let mark {
            return mark(size, color)
        }
        return AnyView(NookMarkView(size: size, strokeWidth: strokeWidth, color: color))
    }
}

#if canImport(AppKit)
    import AppKit

    extension NookHostBranding {
        /// Renders the menu-bar status item's icon into a template `NSImage` - the host's
        /// ``menuBarIcon`` if set, then its ``mark``, otherwise the framework mark.
        @MainActor
        public func menuBarTemplateImage(size: CGFloat = 14) -> NSImage? {
            guard let icon = menuBarIcon ?? mark else {
                return NookMarkView.makeTemplateImage(size: size)
            }
            let renderer = ImageRenderer(content: icon(size, .primary))
            renderer.scale = 2
            guard let image = renderer.nsImage else { return nil }
            image.isTemplate = true
            return image
        }
    }
#endif

private struct NookHostBrandingKey: EnvironmentKey {
    static let defaultValue: NookHostBranding = .default
}

extension EnvironmentValues {
    /// Host branding (``NookHostBranding``) injected by the expanded router so any
    /// framework chrome view can read it from the environment instead of taking it
    /// through every init in the path.
    public var nookHostBranding: NookHostBranding {
        get { self[NookHostBrandingKey.self] }
        set { self[NookHostBrandingKey.self] = newValue }
    }
}
