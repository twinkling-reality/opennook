// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// Seam D - unified identity: single-module branding, the brand-mark override, and the
/// menu-bar disable flag. Defaults reproduce today's chrome.
@MainActor
final class NookBrandingSeamTests: XCTestCase {
    func testBrandingAndMenuFlagDefaults() {
        XCTAssertEqual(NookConfiguration().branding, .default)
        XCTAssertTrue(NookConfiguration().showsMenuBarExtra)
        XCTAssertTrue(NookHostConfiguration().showsMenuBarExtra)
        XCTAssertNil(NookHostBranding.default.mark)
    }

    /// The single-module path forwards `NookConfiguration.branding` and
    /// `showsMenuBarExtra` onto the synthesized host (reached via `ModuleHost`).
    func testSingleModuleForwardsBrandingAndMenuFlag() {
        var configuration = NookConfiguration()
        configuration.branding = NookHostBranding(hostName: "ContextNook", hostTagline: "Tag.")
        configuration.showsMenuBarExtra = false

        let moduleHost = ModuleHost(configuration: configuration)

        XCTAssertEqual(moduleHost.branding.hostName, "ContextNook")
        XCTAssertEqual(moduleHost.branding.hostTagline, "Tag.")
        XCTAssertFalse(moduleHost.showsMenuBarExtra)
    }

    /// The menu-bar flag threads host -> registry -> ModuleHost.
    func testMenuBarFlagThreadsFromHost() {
        var host = NookHostConfiguration()
        host.showsMenuBarExtra = false
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) { NookConfiguration() }

        let moduleHost = ModuleHost(registry: host.makeRegistry())

        XCTAssertFalse(moduleHost.showsMenuBarExtra)
    }

    /// Branding equality ignores the mark closure - two brandings are equal when their
    /// strings match, so existing `== .default` checks keep working with a mark set.
    func testBrandingEqualityIgnoresMark() {
        let plain = NookHostBranding(hostName: "X")
        let withMark = NookHostBranding(
            hostName: "X",
            mark: { size, _ in
                AnyView(Color.clear.frame(width: size, height: size))
            }
        )
        XCTAssertEqual(plain, withMark)
        XCTAssertEqual(NookHostBranding(mark: { s, _ in AnyView(Color.clear.frame(width: s)) }), .default)
    }

    /// `markView` invokes the host mark when set, and falls back to the framework mark
    /// otherwise (no crash, distinct paths).
    func testMarkViewUsesHostMarkWhenSet() {
        final class Flag: @unchecked Sendable { var built = false }
        let flag = Flag()
        let branding = NookHostBranding(mark: { size, _ in
            flag.built = true
            return AnyView(Color.clear.frame(width: size, height: size))
        })

        _ = branding.markView(size: 11, strokeWidth: 1.1, color: .black)
        XCTAssertTrue(flag.built)

        // Fallback path builds without invoking a (nil) host mark.
        _ = NookHostBranding.default.markView(size: 11, strokeWidth: 1.1, color: .black)
    }

    /// The menu-bar template image renders for both the framework mark and a host mark.
    func testMenuBarTemplateImageRenders() {
        XCTAssertNotNil(NookHostBranding.default.menuBarTemplateImage(size: 14))

        let branding = NookHostBranding(mark: { size, color in
            AnyView(Image(systemName: "bolt.fill").font(.system(size: size)).foregroundStyle(color))
        })
        XCTAssertNotNil(branding.menuBarTemplateImage(size: 14))
    }

    /// A menu-bar icon of its own is drawn in the menu bar in place of the mark, which keeps
    /// marking the rest of the chrome.
    func testMenuBarIconTakesPrecedenceOverTheMark() {
        final class Calls: @unchecked Sendable { var mark = 0, icon = 0 }
        let calls = Calls()
        let branding = NookHostBranding(
            mark: { size, _ in
                calls.mark += 1
                return AnyView(Color.clear.frame(width: size, height: size))
            },
            menuBarIcon: { size, color in
                calls.icon += 1
                return NookHostBranding.symbol("sparkles")(size, color)
            }
        )

        let image = branding.menuBarTemplateImage(size: 14)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.isTemplate, true)
        XCTAssertEqual(calls.icon, 1)
        XCTAssertEqual(calls.mark, 0, "the mark is not drawn in the menu bar when an icon is set")

        _ = branding.markView(size: 11, strokeWidth: 1.1, color: .black)
        XCTAssertEqual(calls.mark, 1, "the chrome still uses the mark")
        XCTAssertEqual(branding, NookHostBranding(), "equality ignores the icon")
    }
}
