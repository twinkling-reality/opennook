// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookSurface
import SwiftUI

/// Keeps the surface in step with the host's live activities: the activity holding the pill
/// (the compact router reads it directly), the capsules beside it, the peek, alerts, and the
/// expanded view the nook opens onto from an activity.
extension AppCoordinator {
    /// The host's live activities.
    var liveActivities: NookActivityCenter { moduleHost.registry.liveActivities }

    func bindLiveActivities() {
        liveActivities.onAlert = { [weak self] entry, alert in
            self?.presentActivityAlert(entry, alert)
        }
        // `@Published` sends from `willSet`, so the new list is passed along rather than read
        // back, and the surface changes in the same transaction as the activities.
        liveActivities.$activities
            .dropFirst()
            .sink { [weak self] entries in
                MainActor.assumeIsolated { self?.liveActivitiesChanged(entries) }
            }
            .store(in: &liveActivitySubscriptions)
        // Also from `willSet`: while the state changes, the surface still reports whether it
        // was peeking, which is what says the nook is opening from a peek.
        surface.statePublisher
            .removeDuplicates()
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.surfaceStateWillChange(to: state) }
            }
            .store(in: &liveActivitySubscriptions)
        appState.$moduleBreadcrumb
            .dropFirst()
            .sink { [weak self] breadcrumb in
                MainActor.assumeIsolated { self?.breadcrumbWillChange(to: breadcrumb) }
            }
            .store(in: &liveActivitySubscriptions)
    }

    private func liveActivitiesChanged(_ entries: [NookActivityCenter.Entry]) {
        let configuration = moduleHost.displayedConfiguration
        let source = configuration.companionSource?.companions ?? []
        projectCompanions(
            configuration.companions + source + activityCapsuleCompanions(entries),
            of: configuration
        )
        projectPeek(configuration, activities: entries)
        // An activity that ended, or lost its expanded view, takes the view down with it.
        if let presented = appState.presentedLiveActivity,
            !entries.contains(where: { $0.id == presented && $0.activity.expanded != nil })
        {
            clearActivityPresentation()
        }
    }

    /// The activity whose peek the surface shows: one whose alert is showing, else the one
    /// holding the pill, when it has a peek.
    func peekActivity(_ entries: [NookActivityCenter.Entry]) -> NookActivityCenter.Entry? {
        if let alerting = entries.first(where: { $0.isAlerting && $0.activity.peek != nil }) {
            return alerting
        }
        guard let primary = entries.first, primary.activity.peek != nil else { return nil }
        return primary
    }

    /// The capsules beside the pill, one companion per activity after the first, as many as the
    /// host's ``NookActivityPolicy`` shows. The last one counts the activities left out.
    func activityCapsuleCompanions(_ entries: [NookActivityCenter.Entry]) -> [NookCompanion] {
        let policy = moduleHost.registry.activityPolicy
        let shown = Array(entries.dropFirst().prefix(policy.capsules))
        let leftOut = max(entries.count - 1 - shown.count, 0)
        return shown.enumerated().map { index, entry in
            let minimal = entry.activity.minimal
            let overflow = index == shown.count - 1 ? leftOut : 0
            return NookCompanion(
                id: "opennook.activity.\(entry.moduleID).\(entry.activity.id)",
                // Top-aligned, so the capsule stays beside the slots while the pill peeks.
                anchor: policy.side == .trailing ? .trailing(alignment: .start) : .leading(alignment: .start),
                visibility: .compact,
                shape: .capsule,
                hidesInSettings: false,
                accessibilityLabel: entry.activity.accessibilityLabel
            ) {
                NookActivityCapsule(minimal: minimal, overflow: overflow)
            }
        }
    }

    /// Presents an activity's alert as a surface claim, so it waits while the person is using
    /// the nook. A background module's alert takes the surface only at high priority; a lower
    /// one updates the pill and nothing more.
    private func presentActivityAlert(_ entry: NookActivityCenter.Entry, _ alert: NookLiveActivity.Alert) {
        let priority: NookSurfacePriority =
            switch entry.activity.priority {
                case .low: .ambient
                case .normal: .normal
                case .high: .urgent
            }
        guard entry.moduleID == moduleHost.activeModuleID || priority == .urgent else { return }
        let duration: Duration
        var presentation: NookSurfacePresentation
        switch alert {
            case .none:
                return
            case .peek(let length):
                duration = length
                presentation = .peek
            case .expand(let length):
                duration = length
                presentation = .expanded
        }
        // An activity without a peek opens the nook instead, so its alert is still seen.
        if presentation == .peek, entry.activity.peek == nil { presentation = .expanded }
        let opensOntoActivity = presentation == .expanded && entry.activity.expanded != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if opensOntoActivity { self.presentActivity(entry) }
            let claim = NookSurfaceClaim(
                moduleID: entry.moduleID,
                priority: priority,
                maxDuration: duration + .seconds(5),
                presentation: presentation
            )
            guard let token = await self.beginTransientPresentation(claim) else {
                if opensOntoActivity, self.appState.presentedLiveActivity == entry.id {
                    self.clearActivityPresentation()
                }
                return
            }
            _ = await self.endTransientPresentation(token, after: duration)
        }
    }

    /// Shows `entry`'s expanded view in place of the home view, under its own breadcrumb.
    func presentActivity(_ entry: NookActivityCenter.Entry) {
        let label = entry.activity.accessibilityLabel
        activityBreadcrumb = label
        appState.presentedLiveActivity = entry.id
        appState.moduleBreadcrumb = label
    }

    /// Takes down a presented activity's expanded view, and its breadcrumb if that is still up.
    func clearActivityPresentation() {
        guard appState.presentedLiveActivity != nil || activityBreadcrumb != nil else { return }
        appState.presentedLiveActivity = nil
        if let breadcrumb = activityBreadcrumb, appState.moduleBreadcrumb == breadcrumb {
            appState.moduleBreadcrumb = nil
        }
        activityBreadcrumb = nil
    }

    /// Opening from an activity's peek opens onto its expanded view; collapsing takes it down.
    private func surfaceStateWillChange(to state: NookState) {
        switch state {
            case .expanded:
                guard appState.presentedLiveActivity == nil, surface.isPeeking,
                    let owner = peekOwnerActivity,
                    let entry = liveActivities.activities.first(where: { $0.id == owner }),
                    entry.activity.expanded != nil
                else { return }
                presentActivity(entry)
            case .compact:
                clearActivityPresentation()
            case .hidden:
                // Also passed through on the way from compact to expanded, so it ends nothing.
                break
        }
    }

    /// The person went back (or the module put up its own breadcrumb): the activity's view goes.
    private func breadcrumbWillChange(to breadcrumb: String?) {
        guard let current = activityBreadcrumb, breadcrumb != current else { return }
        appState.presentedLiveActivity = nil
        activityBreadcrumb = nil
    }
}

/// An activity's minimal view in its capsule beside the pill, with a count of the activities
/// left out when it is the last capsule shown.
struct NookActivityCapsule: View, Sendable {
    let minimal: @Sendable @MainActor () -> AnyView
    let overflow: Int

    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            minimal()
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
    }
}
