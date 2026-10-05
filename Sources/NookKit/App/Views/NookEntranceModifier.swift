// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// When the expanded content started entering, and how long the surface holds it back: the
/// clock the top bar's `motion.header.delay` and `nookStaggered(index:)` count from.
struct NookContentEntrance: Equatable, Sendable {
    /// The moment the expanded content was inserted, as the chrome started growing.
    var start: Date
    /// Seconds the surface waits before the content arrives
    /// (``NookContentTransition/delay``).
    var delay: TimeInterval
}

private struct NookContentEntranceKey: EnvironmentKey {
    static let defaultValue: NookContentEntrance? = nil
}

extension EnvironmentValues {
    /// The expanded content's entrance, set by the chrome's expanded router. `nil` outside it,
    /// where an item's wait counts from its own appearance.
    var nookContentEntrance: NookContentEntrance? {
        get { self[NookContentEntranceKey.self] }
        set { self[NookContentEntranceKey.self] = newValue }
    }
}

/// Holds a view back while the content enters, then brings it in with the theme's
/// `motion.content.enter` transition: the top bar after `motion.header.delay`, a staggered
/// item after its index times `motion.stagger`.
///
/// Each wait is counted from the moment the content's own arrival begins (the entrance plus the
/// surface's enter delay), so a view that appears after its turn has passed - the top bar of
/// a module switched to later, a lazily built row scrolled into view - shows at once. With
/// the wait's token at 0, the default, the view is drawn exactly as it would be without the
/// modifier.
struct NookEntranceModifier: ViewModifier {
    enum Timing: Equatable {
        /// The top bar: `motion.header.delay`.
        case header
        /// An item in a list: `index` times `motion.stagger`.
        case staggered(index: Int)
    }

    let timing: Timing

    @Environment(\.nookThemeTokens) private var tokens
    @Environment(\.nookContentEntrance) private var entrance
    @State private var appearedAt = Date()
    @State private var hasEntered = false

    /// Whether the theme makes this view wait at all.
    private var waits: Bool {
        Self.waits(timing, tokens: tokens)
    }

    /// When this view's turn comes.
    private var scheduled: Date {
        Self.scheduledEntrance(entrance: entrance, appearedAt: appearedAt, offset: Self.offset(timing, tokens: tokens))
    }

    /// Content the theme does not hold back is returned untouched, not wrapped in identity
    /// effects, so a theme with no waits draws the chrome exactly as before.
    @ViewBuilder
    func body(content: Content) -> some View {
        if waits {
            content
                .modifier(
                    NookEntranceAppearance(
                        transition: tokens.transition(.contentEnter),
                        isHeldBack: !hasEntered && scheduled > Date()
                    )
                )
                .onAppear(perform: enter)
        } else {
            content
        }
    }

    /// Brings the view in when its turn comes, on the enter transition's curve or the surface's
    /// conversion curve when it names none. A view whose turn has passed is already shown.
    private func enter() {
        guard !hasEntered else { return }
        let wait = scheduled.timeIntervalSinceNow
        guard wait > 0 else {
            hasEntered = true
            return
        }
        let curve = tokens.transition(.contentEnter).animation ?? tokens[.transitionConvert]
        withAnimation(curve.delay(wait)) { hasEntered = true }
    }

    /// Whether `tokens` make a view with `timing` wait: a nonzero `motion.header.delay` for the
    /// header, a nonzero `motion.stagger` for a row.
    static func waits(_ timing: Timing, tokens: NookResolvedTokens) -> Bool {
        switch timing {
            case .header: tokens[.headerDelay] > 0
            case .staggered: tokens[.stagger] > 0
        }
    }

    /// Seconds after the content's arrival begins that a view with `timing` gets its turn.
    static func offset(_ timing: Timing, tokens: NookResolvedTokens) -> TimeInterval {
        switch timing {
            case .header: Double(tokens[.headerDelay])
            case .staggered(let index): Double(tokens[.stagger]) * Double(max(index, 0))
        }
    }

    /// When a view's turn comes: `offset` seconds after the content's arrival begins, which is
    /// the entrance's start plus its delay, or the view's own appearance outside an entrance.
    static func scheduledEntrance(entrance: NookContentEntrance?, appearedAt: Date, offset: TimeInterval) -> Date {
        guard let entrance else { return appearedAt.addingTimeInterval(offset) }
        return entrance.start.addingTimeInterval(entrance.delay + offset)
    }
}

/// A view held at the start of the enter transition, or drawn as it is. Held back, it takes
/// the transition's blur, scale, offset, and opacity; otherwise each is at its identity.
struct NookEntranceAppearance: ViewModifier {
    let transition: NookResolvedContentTransition
    let isHeldBack: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isHeldBack ? transition.blur : 0)
            .scaleEffect(
                x: isHeldBack ? transition.scaleX : 1,
                y: isHeldBack ? transition.scaleY : 1,
                anchor: transition.anchor
            )
            .offset(isHeldBack ? transition.offset : .zero)
            .opacity(isHeldBack ? transition.opacity : 1)
    }
}

extension View {
    /// Brings this view in `index` turns after the nook's content starts arriving, one turn
    /// being the chrome theme's `motion.stagger` seconds, with the theme's
    /// `motion.content.enter` transition: a list that cascades in as the nook opens.
    ///
    /// ```swift
    /// ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
    ///     ItemRow(item).nookStaggered(index: index)
    /// }
    /// ```
    ///
    /// Turns count from when the content's arrival begins, after any
    /// `motion.content.enterDelay`, so the first row arrives with the content and each later
    /// row one turn after the last. A row that appears after its turn has passed (loaded late,
    /// or built lazily as it scrolls into view) shows at once. Outside the expanded content,
    /// turns count from the row's own appearance. With `motion.stagger` at 0, the default,
    /// this does nothing.
    public func nookStaggered(index: Int) -> some View {
        modifier(NookEntranceModifier(timing: .staggered(index: index)))
    }
}
