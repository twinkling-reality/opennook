// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookSurface

extension AppCoordinator {
    /// Deterministic expand-then-compact cycle for launch smoke tests
    /// (`OPENNOOK_SMOKE_TEST=1`). Returns `false` if any step times out.
    public func runLaunchSmokeTest(timeout: TimeInterval = 20) async -> Bool {
        guard await waitForSurfaceState(.compact, timeout: timeout, step: "settle to compact") else {
            return false
        }
        showNook()
        guard await waitForSurfaceState(.expanded, timeout: timeout, step: "expand") else { return false }
        // `isNookVisible` follows the surface state on a later run-loop pass, so reading it the
        // moment the state flips failed a few percent of runs. Wait for it instead.
        guard await waitUntil(timeout: timeout, { appState.isNookVisible }) else {
            reportSmokeTimeout(step: "become visible")
            return false
        }
        hideNook()
        return await waitForSurfaceState(.compact, timeout: timeout, step: "compact again")
    }

    /// Says which step ran out of time and what the surface was doing. A failing smoke test
    /// exits without a message otherwise, which leaves a CI-only failure with nothing to read.
    private func reportSmokeTimeout(step: String) {
        FileHandle.standardError.write(
            Data(
                """
                [smoke] timed out waiting to \(step): state=\(surface.state) \
                visible=\(appState.isNookVisible)

                """.utf8
            )
        )
    }

    /// Expands the chrome and waits for the expanded state. Used by UI smoke tests
    /// (`OPENNOOK_UI_SMOKE_TEST=1`) so XCUITest can assert on the real panel window.
    public func prepareForUISmokeTest(timeout: TimeInterval = 20) async -> Bool {
        guard await waitForSurfaceState(.compact, timeout: timeout, step: "settle to compact") else {
            return false
        }
        showNook()
        return await waitForSurfaceState(.expanded, timeout: timeout, step: "expand")
    }

    private func waitForSurfaceState(
        _ expected: NookState,
        timeout: TimeInterval,
        step: String
    ) async -> Bool {
        let reached = await waitUntil(timeout: timeout) { surface.state == expected }
        if !reached { reportSmokeTimeout(step: step) }
        return reached
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let pollNanoseconds: UInt64 = 50_000_000
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return condition()
    }
}
