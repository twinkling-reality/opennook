// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI
import XCTest

@testable import NookSurface

/// Coverage for ``NookNotchCutout``: the value `NookView` injects for the expanded content,
/// and the helpers wrappers use to re-inject it relative to their own frames.
final class NookNotchCutoutTests: XCTestCase {
    /// The notch of a 14-inch MacBook Pro at the default scaling.
    private let notchSize = CGSize(width: 185, height: 32)

    // MARK: - Chrome derivation

    func testNotchFormReportsTheNotchWithTheStandardStrip() {
        let cutout = NookNotchCutout.expanded(
            form: .notch,
            notchSize: notchSize,
            chromeSafeAreaInsets: NookStyle.standardExpandedContentInsets
        )
        XCTAssertEqual(cutout, NookNotchCutout(width: 185, height: 32, centerOffset: 0))
        XCTAssertFalse(cutout.isEmpty)
    }

    /// The floating panel sits below the menu bar, clear of any notch.
    func testFloatingFormReportsNone() {
        let cutout = NookNotchCutout.expanded(
            form: .floating,
            notchSize: notchSize,
            chromeSafeAreaInsets: NookStyle.standardExpandedContentInsets
        )
        XCTAssertEqual(cutout, .none)
    }

    /// Before the surface has measured a screen its notch size is zero, which must not read
    /// as a notch.
    func testUnmeasuredNotchReportsNone() {
        let cutout = NookNotchCutout.expanded(
            form: .notch,
            notchSize: .zero,
            chromeSafeAreaInsets: NookStyle.standardExpandedContentInsets
        )
        XCTAssertEqual(cutout, .none)
        XCTAssertTrue(cutout.isEmpty)
    }

    /// A top strip lowers the host's frame, and uneven side strips move its center away from
    /// the notch's.
    func testSafeAreaStripsShiftTheCutout() {
        let cutout = NookNotchCutout.expanded(
            form: .notch,
            notchSize: notchSize,
            chromeSafeAreaInsets: NookEdgeInsets(top: 10, bottom: 8, leading: 8, trailing: 20)
        )
        XCTAssertEqual(cutout.width, 185)
        XCTAssertEqual(cutout.height, 22)
        XCTAssertEqual(cutout.centerOffset, 6)
    }

    // MARK: - Helpers

    func testInsetByFloorsTheHeightAndComposes() {
        let cutout = NookNotchCutout(width: 185, height: 32)
        XCTAssertEqual(cutout.insetBy(top: 40).height, 0)
        XCTAssertTrue(cutout.insetBy(top: 40).isEmpty)
        XCTAssertEqual(cutout.insetBy(top: 40).width, 185)

        let twice = cutout.insetBy(top: 8, leading: 8, trailing: 8).insetBy(top: 4, leading: 10, trailing: 2)
        XCTAssertEqual(twice, NookNotchCutout(width: 185, height: 20, centerOffset: -4))
    }

    func testHorizontalSpanIsCenteredOnTheOffset() {
        XCTAssertEqual(NookNotchCutout(width: 40, height: 24).horizontalSpan(inFrameWidth: 200), 80...120)
        XCTAssertEqual(
            NookNotchCutout(width: 40, height: 24, centerOffset: -10).horizontalSpan(inFrameWidth: 200),
            70...110
        )
        // A malformed negative width collapses to the center rather than trapping.
        XCTAssertEqual(NookNotchCutout(width: -10, height: 24).horizontalSpan(inFrameWidth: 200), 100...100)
    }

    func testEnvironmentDefaultsToNone() {
        XCTAssertEqual(EnvironmentValues().nookNotchCutout, .none)
    }
}
