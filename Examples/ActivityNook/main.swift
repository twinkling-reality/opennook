// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// ActivityNook - the live-activity queue from the NookComponents add-on.
//
// A NookActivityQueue collects transient activities and presents them one at a time,
// briefly taking over the expanded surface for each. This demo enqueues a sample
// activity on a timer so the takeover is visible. Run with `swift run ActivityNook`.
//
// It is written as a full `NookModule` class (rather than a `NookConfiguration`
// closure) so it can implement `prepareForSwitchAway()`: a module that owns a
// `NookActivityQueue` must `quiesce()` that queue before it is switched away, so an
// in-flight transient presentation is drained and its surface claim released before
// the incoming module takes the surface.

import NookApp
import NookComponents
import SwiftUI

/// Shown when the queue is idle - the host's normal home content.
struct ActivityNookHome: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.secondaryLabel)
            Text("Activity queue idle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryLabel)
            Text("A sample activity surfaces every few seconds.")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// A module that owns a `NookActivityQueue`. Because the queue is a transient surface
/// presenter, the module must `quiesce()` it before being switched away - that is the
/// purpose of `prepareForSwitchAway()`.
@MainActor
final class ActivityModule: NookModule {
    // `nonisolated` so the top-level (nonisolated) host setup can reference it. The
    // descriptor is an immutable `Sendable` value, so this is safe outside the actor.
    nonisolated static let moduleDescriptor = NookModuleDescriptor(
        id: "com.opennook.example.activity",
        displayName: "Activity",
        icon: "bell",
        accent: .orange
    )

    let descriptor = ActivityModule.moduleDescriptor
    private let queue = NookActivityQueue()
    private var sampleTimer: Timer?

    /// The host calls `onActivate()` only when the user switches *to* a module, not for the
    /// module it launches with, so the sample timer also starts here.
    init() {
        startSampleTimer()
    }

    func makeConfiguration() -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.setHome {
            NookActivityHost(queue: self.queue) { ActivityNookHome() }
        }
        configuration.onReady = { [queue, descriptor] coordinator in
            queue.bind(to: coordinator, moduleID: descriptor.id)
        }
        return configuration
    }

    func onActivate() {
        startSampleTimer()
    }

    /// Stops surface activity before the switch: joins the queue's drain loop and
    /// releases any claim it holds, so the incoming module takes a clean surface.
    func prepareForSwitchAway() async {
        await queue.quiesce()
    }

    func onDeactivate() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    /// Demo only: enqueues a rotating sample activity on a timer so the takeover is
    /// visible. A real app enqueues in response to its own events. Safe to call when the
    /// timer is already running, since both `init()` and `onActivate()` call it.
    private func startSampleTimer() {
        guard sampleTimer == nil else { return }
        let samples = [
            NookActivity(
                priority: .normal,
                title: "Build finished",
                subtitle: "Debug · 12.4s",
                systemImage: "hammer",
                tint: .green
            ),
            NookActivity(
                priority: .high,
                title: "Backup complete",
                subtitle: "3,204 files",
                systemImage: "externaldrive.badge.checkmark",
                tint: .blue
            ),
            NookActivity(
                priority: .low,
                title: "New message",
                subtitle: "from the notch",
                systemImage: "message",
                tint: .orange
            ),
        ]
        let timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [queue] _ in
            // Timer fires on the main run loop; hop to the main actor to enqueue.
            MainActor.assumeIsolated {
                let index = Int(Date.now.timeIntervalSince1970 / 6) % samples.count
                queue.enqueue(samples[index])
            }
        }
        sampleTimer = timer
    }
}

var host = NookHostConfiguration()
host.register(ActivityModule.moduleDescriptor) { _ in ActivityModule() }
host.defaultModule = ActivityModule.moduleDescriptor.id

NookApp.main(host)
