// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// Compact slots get the same chrome environment as the expanded content, and the default
/// compact trailing slot and placeholder home draw the host's brand mark.
@MainActor
final class NookCompactEnvironmentTests: XCTestCase {
    /// Where a probe view records the environment it was rendered in.
    @MainActor
    private final class EnvironmentCapture {
        var values: EnvironmentValues?
    }

    private struct EnvironmentProbe: View {
        let capture: EnvironmentCapture
        @Environment(\.self) private var environment

        var body: some View {
            Color.clear
                .frame(width: 10, height: 10)
                .onAppear { capture.values = environment }
        }
    }

    /// Records whether a host brand mark was built.
    @MainActor
    private final class MarkFlag {
        var built = false
    }

    private func brandingWithMark(_ flag: MarkFlag) -> NookHostBranding {
        NookHostBranding(
            hostName: "Constellation",
            mark: { size, _ in
                flag.built = true
                return AnyView(Color.clear.frame(width: size, height: size))
            }
        )
    }

    private func makeHost(configuration: NookConfiguration, branding: NookHostBranding = .default) -> ModuleHost {
        var host = NookHostConfiguration()
        host.branding = branding
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) { configuration }
        return ModuleHost(registry: host.makeRegistry())
    }

    private func render(_ view: some View) {
        _ = ImageRenderer(content: view.frame(width: 40, height: 40)).nsImage
    }

    /// A compact slot sees the services, labels, motion, branding, and metrics the expanded
    /// content sees. (The tint, color-scheme preference, and control state are applied by the
    /// same modifier but are not readable back from a probe outside a real window.)
    func testCompactSlotGetsTheExpandedChromeEnvironment() throws {
        let capture = EnvironmentCapture()
        var configuration = NookConfiguration()
        configuration.labels.dismissHelp = "Put away"
        configuration.motion.breadcrumb = .linear(duration: 0.4)
        configuration.metrics.compactSlotSize = 31
        configuration.setCompactLeading { EnvironmentProbe(capture: capture) }
        let host = makeHost(configuration: configuration, branding: NookHostBranding(hostName: "Constellation"))

        render(
            ModuleRouterCompactView(
                moduleHost: host,
                appState: AppState(),
                activities: host.registry.liveActivities,
                slot: .leading
            )
        )

        let environment = try XCTUnwrap(capture.values, "the probe rendered")
        XCTAssertTrue(environment.appServices === host.activeServices, "the module's services")
        XCTAssertEqual(environment.nookChromeLabels, configuration.labels)
        XCTAssertEqual(environment.nookChromeMotion, configuration.motion)
        XCTAssertEqual(environment.nookChromeMetrics.compactSlotSize, 31)
        XCTAssertEqual(environment.nookHostBranding.hostName, "Constellation")
    }

    /// The default compact trailing slot draws the host's mark, reached through the router.
    func testDefaultCompactTrailingDrawsHostMark() {
        let flag = MarkFlag()
        let host = makeHost(configuration: NookConfiguration(), branding: brandingWithMark(flag))

        render(
            ModuleRouterCompactView(
                moduleHost: host,
                appState: AppState(),
                activities: host.registry.liveActivities,
                slot: .trailing
            )
        )

        XCTAssertTrue(flag.built)
    }

    /// The placeholder home draws the host's mark.
    func testPlaceholderHomeDrawsHostMark() {
        let flag = MarkFlag()

        render(NookPlaceholderHomeView().environment(\.nookHostBranding, brandingWithMark(flag)))

        XCTAssertTrue(flag.built)
    }

    /// Without a host mark the slot-width helper draws the OpenNook mark at the slot's
    /// framework width, as those slots always did; a host mark gets the matching square.
    func testFrameworkWidthMarkSizes() {
        @MainActor final class SizeBox { var size: CGFloat? }
        let box = SizeBox()
        let branding = NookHostBranding(mark: { size, _ in
            box.size = size
            return AnyView(Color.clear)
        })

        _ = branding.markView(frameworkWidth: 20, strokeWidth: 1, color: .black)
        XCTAssertEqual(box.size, 20 / NookHostBranding.frameworkMarkWidthScale)

        let fallback = NSHostingView(
            rootView: NookHostBranding.default.markView(frameworkWidth: 20, strokeWidth: 1, color: .black)
        )
        XCTAssertEqual(fallback.fittingSize.width, 20, accuracy: 0.5)
    }
}
