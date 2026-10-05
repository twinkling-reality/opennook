// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import SwiftUI

/// Every live activity the host's modules are running, in the order they claim the pill.
///
/// One per host process, owned by the module registry. A module never talks to it directly: it
/// gets a ``NookLiveActivities``, a view of the center that starts, alerts, and ends that module's
/// activities only (``NookLiveActivitiesKey``, `\.nookLiveActivities`).
///
/// The order is the pill's: higher ``NookLiveActivity/Priority`` first, then an activity whose
/// alert is showing, then the most recently started. Restarting an activity keeps its place, so
/// activities do not shuffle while they update. The first holds the pill's compact slots; the next
/// ones show their minimal view in capsules beside it (``NookActivityPolicy``).
@MainActor
public final class NookActivityCenter: ObservableObject {
    /// A running activity and the module that started it.
    public struct Entry: Identifiable, Sendable {
        /// The module that started the activity.
        public let moduleID: String
        /// The activity as it was last started.
        public let activity: NookLiveActivity
        /// `true` while the activity's alert is showing.
        public internal(set) var isAlerting: Bool
        /// When the activity first started, relative to the others: later is larger.
        let sequence: Int

        /// Unique across modules.
        public var id: String { Self.key(moduleID, activity.id) }

        static func key(_ moduleID: String, _ activityID: String) -> String {
            moduleID + "\u{1F}" + activityID
        }
    }

    /// Every running activity, in pill order.
    @Published public private(set) var activities: [Entry] = []

    /// Called when an activity alerts, for the coordinator to present the alert.
    var onAlert: (@MainActor (Entry, NookLiveActivity.Alert) -> Void)?

    private var nextSequence = 0
    private var endTasks: [String: Task<Void, Never>] = [:]
    private var alertTasks: [String: Task<Void, Never>] = [:]
    private var scopes: [String: NookLiveActivities] = [:]

    public nonisolated init() {}

    /// The view of the center that `moduleID` gets: its own activities, and nothing else.
    public func activities(for moduleID: String) -> NookLiveActivities {
        if let scope = scopes[moduleID] { return scope }
        let scope = NookLiveActivities(moduleID: moduleID, center: self)
        scopes[moduleID] = scope
        return scope
    }

    /// The activity holding the pill, if any.
    public var primary: Entry? { activities.first }

    /// The activities whose minimal views show beside the pill, at most `limit` of them.
    public func capsules(limit: Int) -> [Entry] {
        Array(activities.dropFirst().prefix(max(limit, 0)))
    }

    /// The activity with `id` that `moduleID` started, if it is running.
    public func entry(moduleID: String, id: String) -> Entry? {
        activities.first { $0.moduleID == moduleID && $0.activity.id == id }
    }

    // MARK: - Changes, through a module's ``NookLiveActivities``

    func start(_ activity: NookLiveActivity, moduleID: String) {
        let key = Entry.key(moduleID, activity.id)
        let existing = activities.firstIndex { $0.id == key }
        let sequence: Int
        if let existing {
            sequence = activities[existing].sequence
        } else {
            sequence = nextSequence
            nextSequence += 1
        }
        let entry = Entry(
            moduleID: moduleID,
            activity: activity,
            isAlerting: existing.map { activities[$0].isAlerting } ?? false,
            sequence: sequence
        )
        var next = activities
        if let existing {
            next[existing] = entry
        } else {
            next.append(entry)
        }
        activities = Self.ordered(next)

        endTasks.removeValue(forKey: key)?.cancel()
        if case .transient(let duration) = activity.lifetime {
            scheduleEnd(key, after: duration)
        }
        if activity.alert != .none {
            raiseAlert(key, activity.alert)
        }
    }

    func alert(_ id: String, moduleID: String, _ alert: NookLiveActivity.Alert) {
        let key = Entry.key(moduleID, id)
        guard alert != .none, activities.contains(where: { $0.id == key }) else { return }
        raiseAlert(key, alert)
    }

    func end(_ id: String, moduleID: String, after delay: Duration) {
        let key = Entry.key(moduleID, id)
        guard activities.contains(where: { $0.id == key }) else { return }
        if delay > .zero {
            scheduleEnd(key, after: delay)
        } else {
            remove(key)
        }
    }

    /// Ends every activity `moduleID` is running: the module is going away.
    func endAll(moduleID: String) {
        for entry in activities where entry.moduleID == moduleID {
            endTasks.removeValue(forKey: entry.id)?.cancel()
            alertTasks.removeValue(forKey: entry.id)?.cancel()
        }
        let remaining = activities.filter { $0.moduleID != moduleID }
        if remaining.count != activities.count { activities = remaining }
    }

    // MARK: - Internals

    private func remove(_ key: String) {
        endTasks.removeValue(forKey: key)?.cancel()
        alertTasks.removeValue(forKey: key)?.cancel()
        activities.removeAll { $0.id == key }
    }

    private func scheduleEnd(_ key: String, after delay: Duration) {
        endTasks.removeValue(forKey: key)?.cancel()
        endTasks[key] = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil, let self else { return }
            self.endTasks[key] = nil
            self.remove(key)
        }
    }

    private func raiseAlert(_ key: String, _ alert: NookLiveActivity.Alert) {
        guard let index = activities.firstIndex(where: { $0.id == key }) else { return }
        let duration: Duration =
            switch alert {
                case .none: .zero
                case .peek(let duration), .expand(let duration): duration
            }
        var next = activities
        next[index].isAlerting = true
        activities = Self.ordered(next)
        alertTasks.removeValue(forKey: key)?.cancel()
        alertTasks[key] = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil, let self else { return }
            self.alertTasks[key] = nil
            guard let index = self.activities.firstIndex(where: { $0.id == key }) else { return }
            var next = self.activities
            next[index].isAlerting = false
            self.activities = Self.ordered(next)
        }
        if let entry = activities.first(where: { $0.id == key }) {
            onAlert?(entry, alert)
        }
    }

    /// Pill order: higher priority, then alerting, then most recently started.
    static func ordered(_ entries: [Entry]) -> [Entry] {
        entries.sorted { lhs, rhs in
            if lhs.activity.priority != rhs.activity.priority {
                return lhs.activity.priority > rhs.activity.priority
            }
            if lhs.isAlerting != rhs.isAlerting { return lhs.isAlerting }
            return lhs.sequence > rhs.sequence
        }
    }
}

/// One module's view of the host's live activities: it starts, alerts, and ends that module's
/// activities, and can see only those. Resolve it from the module's services
/// (``NookLiveActivitiesKey``) or read it in a view (`\.nookLiveActivities`).
@MainActor
public final class NookLiveActivities {
    /// The module whose activities these are.
    public nonisolated let moduleID: String
    private weak var center: NookActivityCenter?

    nonisolated init(moduleID: String, center: NookActivityCenter?) {
        self.moduleID = moduleID
        self.center = center
    }

    /// Starts `activity`, or replaces the running one with the same id in place: it keeps its
    /// place in the pill, and its views carry on. Its ``NookLiveActivity/alert``, when not
    /// ``NookLiveActivity/Alert/none``, plays now.
    public func start(_ activity: NookLiveActivity) {
        center?.start(activity, moduleID: moduleID)
    }

    /// Plays `alert` for the running activity `id`, such as a peek when a song changes. Does
    /// nothing for an activity that is not running.
    public func alert(_ id: String, _ alert: NookLiveActivity.Alert) {
        center?.alert(id, moduleID: moduleID, alert)
    }

    /// Ends the activity `id`, now or `delay` from now. Ending it again, or starting it again,
    /// replaces a pending end.
    public func end(_ id: String, after delay: Duration = .zero) {
        center?.end(id, moduleID: moduleID, after: delay)
    }

    /// Ends every activity this module is running.
    public func endAll() {
        center?.endAll(moduleID: moduleID)
    }

    /// This module's running activities, in pill order.
    public var running: [NookLiveActivity] {
        center?.activities.filter { $0.moduleID == moduleID }.map(\.activity) ?? []
    }
}

private struct NookLiveActivitiesEnvironmentKey: EnvironmentKey {
    static let defaultValue = NookLiveActivitiesKey.defaultValue
}

extension EnvironmentValues {
    /// The displayed module's live activities, for a view that starts or ends one. Outside the
    /// chrome it starts nothing.
    public var nookLiveActivities: NookLiveActivities {
        get { self[NookLiveActivitiesEnvironmentKey.self] }
        set { self[NookLiveActivitiesEnvironmentKey.self] = newValue }
    }
}

/// Resolves a module's ``NookLiveActivities`` from its ``AppServices``. Registered for every
/// module the registry builds; the default, outside one, starts nothing.
public struct NookLiveActivitiesKey: ServiceKey {
    public static let defaultValue = NookLiveActivities(moduleID: "", center: nil)
}

/// How the pill shares itself among live activities. See
/// ``NookHostConfiguration/activityPolicy``.
public struct NookActivityPolicy: Equatable, Sendable {
    /// Which side of the pill the capsules sit on.
    public enum Side: Equatable, Sendable {
        case leading
        case trailing
    }

    /// How many activities after the first show their minimal view in a capsule beside the
    /// pill. 1 by default; 0 shows only the first. There is no upper bound: each capsule is a
    /// companion in a row beside the pill, so more of them reach further from the notch. When
    /// more activities run than show, the last capsule counts the rest.
    public var capsules: Int
    /// The side the capsules sit on. ``Side/trailing`` by default.
    public var side: Side

    public init(capsules: Int = 1, side: Side = .trailing) {
        self.capsules = max(capsules, 0)
        self.side = side
    }

    /// One capsule, on the trailing side.
    public static let standard = NookActivityPolicy()
}
