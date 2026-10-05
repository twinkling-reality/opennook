// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Something ongoing or short-lived that a module shows in the compact pill, the way the
/// Dynamic Island shows a live activity: a timer counting down, a song playing, a build running.
///
/// An activity is views plus a little metadata. The views read the module's own state, so a timer
/// ticking or a song changing updates the activity in place; the activity itself only changes
/// when its metadata does. Start one through the module's ``NookLiveActivities``:
///
/// ```swift
/// let activities = context.services.resolve(NookLiveActivitiesKey.self)
/// var focus = NookLiveActivity(id: "focus", accessibilityLabel: "Focus session") {
///     Image(systemName: "flame.fill").foregroundStyle(.orange)
/// } compactTrailing: {
///     TimerText(timer: timer)
/// } minimal: {
///     Image(systemName: "flame.fill").foregroundStyle(.orange)
/// }
/// focus.setPeek { FocusPeek(timer: timer) }
/// focus.setExpanded { FocusExpanded(timer: timer) }
/// activities.start(focus)
/// ```
///
/// The framework draws the pill, the peek, the capsule beside the notch, and their motion; an
/// activity supplies content only. Keep compact content to a symbol and one short value, and put
/// text in the peek.
public struct NookLiveActivity: Identifiable, Sendable {
    /// How an activity ranks for the pill against the others running.
    public enum Priority: Int, Comparable, Sendable, CaseIterable {
        /// Background information, such as the weather.
        case low
        /// Most activities.
        case normal
        /// Something the person should not miss, such as a timer that finished. A high
        /// priority alert from a background module may take the surface; lower ones only update
        /// the pill.
        case high

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How long an activity lasts on its own.
    public enum Lifetime: Equatable, Sendable {
        /// Until the module ends it.
        case ongoing
        /// For this long after it starts, unless the module ends it sooner. Restarting it starts
        /// the clock again.
        case transient(Duration)
    }

    /// How an activity calls for attention when it starts, or when ``NookLiveActivities/alert(_:_:)``
    /// is called.
    public enum Alert: Equatable, Sendable {
        /// It only appears in the pill.
        case none
        /// The pill grows into the activity's peek for this long.
        case peek(Duration)
        /// The nook opens on the activity's expanded view for this long.
        case expand(Duration)
    }

    /// Identifies the activity within its module. Starting another activity with the same id
    /// replaces it in place.
    public var id: String
    /// How it ranks for the pill. ``Priority/normal`` by default.
    public var priority: Priority
    /// How long it lasts on its own. ``Lifetime/ongoing`` by default.
    public var lifetime: Lifetime
    /// How it calls for attention when it starts. ``Alert/none`` by default.
    public var alert: Alert
    /// What VoiceOver says for the activity, and the breadcrumb over its expanded view.
    public var accessibilityLabel: String

    /// The view left of the notch while the activity holds the pill.
    public var compactLeading: @Sendable @MainActor () -> AnyView
    /// The view right of the notch while the activity holds the pill.
    public var compactTrailing: @Sendable @MainActor () -> AnyView
    /// The view in the small capsule beside the pill while another activity holds it: a symbol,
    /// or a symbol and a very short value.
    public var minimal: @Sendable @MainActor () -> AnyView
    /// The view the pill grows to show when the activity peeks. `nil` (the default) means the
    /// activity has no peek; then a peek alert opens the nook instead.
    public var peek: (@Sendable @MainActor () -> AnyView)?
    /// The view the nook opens onto from the activity's peek or an expand alert. `nil` (the
    /// default) opens onto the module's home instead.
    public var expanded: (@Sendable @MainActor () -> AnyView)?

    public init<Leading: View & Sendable, Trailing: View & Sendable, Minimal: View & Sendable>(
        id: String,
        priority: Priority = .normal,
        lifetime: Lifetime = .ongoing,
        alert: Alert = .none,
        accessibilityLabel: String,
        @ViewBuilder compactLeading: @escaping @Sendable @MainActor () -> Leading,
        @ViewBuilder compactTrailing: @escaping @Sendable @MainActor () -> Trailing,
        @ViewBuilder minimal: @escaping @Sendable @MainActor () -> Minimal
    ) {
        self.id = id
        self.priority = priority
        self.lifetime = lifetime
        self.alert = alert
        self.accessibilityLabel = accessibilityLabel
        self.compactLeading = { AnyView(compactLeading()) }
        self.compactTrailing = { AnyView(compactTrailing()) }
        self.minimal = { AnyView(minimal()) }
    }

    /// Sets the view the pill grows to show when the activity peeks. See ``peek``.
    public mutating func setPeek<Content: View & Sendable>(
        @ViewBuilder _ content: @escaping @Sendable @MainActor () -> Content
    ) {
        peek = { AnyView(content()) }
    }

    /// Sets the view the nook opens onto for the activity. See ``expanded``.
    public mutating func setExpanded<Content: View & Sendable>(
        @ViewBuilder _ content: @escaping @Sendable @MainActor () -> Content
    ) {
        expanded = { AnyView(content()) }
    }
}
