// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import Foundation

/// What resting the pointer on the compact pill does, and how long it takes.
///
/// The standard intent opens the nook the moment the pointer arrives, as the surface always
/// has. A peek-first intent grows the pill into its peek region (``Nook/peekContent``) instead,
/// and opens the full nook on a click, or on its own once the pointer has dwelt on the peek:
///
/// ```swift
/// nook.hoverIntent = NookHoverIntent(action: .peek, delay: .milliseconds(120), dwellToExpand: .seconds(1))
/// ```
///
/// Whatever the action, a click on the compact pill opens the nook whenever the intent is not
/// ``standard``, so a pill that no longer opens on hover is never out of reach.
public struct NookHoverIntent: Equatable, Sendable {
    /// What the pointer arriving on the compact pill does.
    public enum Action: Equatable, Sendable {
        /// Opens the full nook.
        case expand
        /// Grows the pill into its peek region. Opens the full nook instead when there is no
        /// ``Nook/peekContent`` to show.
        case peek
        /// Nothing: the nook opens on a click, or from the host.
        case none
    }

    /// What the pointer arriving does. ``Action/expand`` by default.
    public var action: Action

    /// How long the pointer rests on the pill before ``action`` happens. Leaving sooner cancels
    /// it. Zero by default.
    public var delay: Duration

    /// ``delay`` on a display other than the Mac's built-in one, where the pill sits under a
    /// pointer that crosses the top of the screen more often. `nil` (the default) uses
    /// ``delay`` everywhere.
    public var externalDisplayDelay: Duration?

    /// How long the pointer rests on a peek before the full nook opens on its own. `nil` (the
    /// default) waits for a click.
    public var dwellToExpand: Duration?

    public init(
        action: Action = .expand,
        delay: Duration = .zero,
        externalDisplayDelay: Duration? = nil,
        dwellToExpand: Duration? = nil
    ) {
        self.action = action
        self.delay = max(delay, .zero)
        self.externalDisplayDelay = externalDisplayDelay.map { max($0, .zero) }
        self.dwellToExpand = dwellToExpand.map { max($0, .zero) }
    }

    /// Opens the nook the moment the pointer arrives: the surface's behavior before intents
    /// existed.
    public static let standard = NookHoverIntent()

    /// The delay to wait on a display that is, or is not, the built-in one.
    func delay(onBuiltInDisplay isBuiltIn: Bool) -> Duration {
        isBuiltIn ? delay : (externalDisplayDelay ?? delay)
    }
}
