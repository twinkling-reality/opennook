// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookSurface
import SwiftUI

/// Companions a host can add, remove, and replace while the nook runs.
///
/// A companion's content can change on its own - a pill that shows two buttons or five just
/// observes its model. A source is for changing which surfaces exist: a separate button that
/// appears while a call is live, a group per open document. Set it on the configuration once,
/// then change it whenever you like; the chrome follows at once, with no configuration reload.
///
/// ```swift
/// let companions = NookCompanionSource()
///
/// var configuration = NookConfiguration()
/// configuration.companionSource = companions
///
/// // Later, from anywhere on the main actor:
/// companions.set(NookCompanion(id: "leave", shape: .circle) { LeaveButton() })
/// companions.remove(id: "leave")
/// ```
///
/// A companion added or removed plays its presence on the way in or out, on the chrome's curve;
/// make the change inside `withAnimation` to pick another one.
///
/// The source's companions come after the configuration's own ``NookConfiguration/companions``
/// and take its companion style, size, and presence unless they set their own. Like every
/// companion, they belong to the configuration that carries the source, so they leave the
/// surface when its module is switched away, and the surface shows what the source holds when
/// the module comes back. A module with the default
/// ``NookModuleDescriptor/BackgroundPolicy/unloadOnSwitchAway`` policy is rebuilt on its way
/// back, so a source it creates starts over; keep the source somewhere that outlives the module,
/// or make the module ``NookModuleDescriptor/BackgroundPolicy/stayResident``, to keep what it
/// holds.
@MainActor
public final class NookCompanionSource: ObservableObject {
    /// The companions, in order. Assigning replaces them all; the surface keeps the SwiftUI
    /// state of every companion whose id stays.
    @Published public var companions: [NookCompanion]

    public init(_ companions: [NookCompanion] = []) {
        self.companions = companions
    }

    /// The ids of the companions, in order.
    public var ids: [String] {
        companions.map(\.id)
    }

    /// The companion with `id`, if there is one.
    public func companion(id: String) -> NookCompanion? {
        companions.first { $0.id == id }
    }

    /// Replaces the companion with `companion`'s id where it stands, or appends it when there is
    /// none.
    public func set(_ companion: NookCompanion) {
        if let index = companions.firstIndex(where: { $0.id == companion.id }) {
            companions[index] = companion
        } else {
            companions.append(companion)
        }
    }

    /// Inserts `companion` at `index`, replacing any companion that already has its id.
    public func insert(_ companion: NookCompanion, at index: Int) {
        var updated = companions.filter { $0.id != companion.id }
        updated.insert(companion, at: min(max(index, 0), updated.count))
        companions = updated
    }

    /// Removes the companion with `id`. Nothing happens when there is none.
    public func remove(id: String) {
        companions.removeAll { $0.id == id }
    }

    /// Removes every companion.
    public func removeAll() {
        companions.removeAll()
    }

    /// Moves the companion with `id` to `index`, so it takes that place in its row.
    public func move(id: String, to index: Int) {
        guard let current = companions.firstIndex(where: { $0.id == id }) else { return }
        var updated = companions
        let companion = updated.remove(at: current)
        updated.insert(companion, at: min(max(index, 0), updated.count))
        companions = updated
    }
}
