// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// Coverage for how the expanded surface keeps content clear of the notch: the space the
/// column sets aside, the row that splits around the notch, and where
/// `nookNotchAccessories(leading:trailing:)` draws. The drawing tests render real views and
/// read back which color is where, since the placement is the behavior that matters.
@MainActor
final class NookNotchClearanceTests: XCTestCase {
    private let notch = NookNotchCutout(width: 40, height: 24)

    // MARK: - Column layout

    func testClearanceDefaultsToAutomatic() {
        XCTAssertEqual(NookTopBarConfiguration().notchClearance, .automatic)
        XCTAssertEqual(NookConfiguration().topBar.notchClearance, .automatic)
    }

    /// With the bar showing, the bar fills the band and the content follows it as before.
    func testAutomaticWithTopBarMakesTheBarFillTheBand() {
        let layout = NookNotchLayout.resolve(clearance: .automatic, band: 30, showsTopBar: true, spacing: 8)
        XCTAssertEqual(layout, NookNotchLayout(topBarMinHeight: 30, contentTopPadding: 0))
    }

    /// With the bar hidden, the content starts where it would below a bar filling the band.
    func testAutomaticWithoutTopBarStartsTheContentBelowTheBand() {
        let layout = NookNotchLayout.resolve(clearance: .automatic, band: 24, showsTopBar: false, spacing: 8)
        XCTAssertEqual(layout, NookNotchLayout(topBarMinHeight: 0, contentTopPadding: 32))
    }

    func testNoBandOrNoClearanceLeavesTheColumnAlone() {
        XCTAssertEqual(
            NookNotchLayout.resolve(clearance: .automatic, band: 0, showsTopBar: false, spacing: 8),
            NookNotchLayout()
        )
        XCTAssertEqual(
            NookNotchLayout.resolve(clearance: .manual, band: 24, showsTopBar: false, spacing: 8),
            NookNotchLayout()
        )
        XCTAssertEqual(
            NookNotchLayout.resolve(clearance: .manual, band: 24, showsTopBar: true, spacing: 8),
            NookNotchLayout()
        )
    }

    // MARK: - Row geometry

    func testSidesStopShortOfTheNotch() {
        let centered = NookNotchRowLayout.sideWidths(width: 200, cutout: notch, spacing: 8, trailingIdealWidth: 10)
        XCTAssertEqual(centered.leading, 72)
        XCTAssertEqual(centered.trailing, 72)

        let shifted = NookNotchCutout(width: 40, height: 24, centerOffset: 10)
        let offCenter = NookNotchRowLayout.sideWidths(width: 200, cutout: shifted, spacing: 8, trailingIdealWidth: 10)
        XCTAssertEqual(offCenter.leading, 82)
        XCTAssertEqual(offCenter.trailing, 62)
    }

    func testNotchWiderThanTheRowLeavesNoRoom() {
        let sides = NookNotchRowLayout.sideWidths(width: 30, cutout: notch, spacing: 8, trailingIdealWidth: 10)
        XCTAssertEqual(sides.leading, 0)
        XCTAssertEqual(sides.trailing, 0)
    }

    func testWithoutANotchTheTrailingSideKeepsItsWidth() {
        let sides = NookNotchRowLayout.sideWidths(width: 200, cutout: .none, spacing: 8, trailingIdealWidth: 50)
        XCTAssertEqual(sides.leading, 142)
        XCTAssertEqual(sides.trailing, 50)

        let crowded = NookNotchRowLayout.sideWidths(width: 200, cutout: .none, spacing: 8, trailingIdealWidth: 300)
        XCTAssertEqual(crowded.leading, 0)
        XCTAssertEqual(crowded.trailing, 192)
    }

    func testIdealWidthFitsBothSidesAroundTheNotch() {
        XCTAssertEqual(NookNotchRowLayout.idealWidth(leading: 50, trailing: 30, cutout: notch, spacing: 8), 156)
        XCTAssertEqual(NookNotchRowLayout.idealWidth(leading: 50, trailing: 30, cutout: .none, spacing: 8), 88)

        let shifted = NookNotchCutout(width: 40, height: 24, centerOffset: 10)
        let width = NookNotchRowLayout.idealWidth(leading: 50, trailing: 30, cutout: shifted, spacing: 8)
        XCTAssertEqual(width, 136)
        let sides = NookNotchRowLayout.sideWidths(width: width, cutout: shifted, spacing: 8, trailingIdealWidth: 30)
        XCTAssertEqual(sides.leading, 50)
        XCTAssertEqual(sides.trailing, 30)
    }

    // MARK: - Drawing

    /// The chrome moved the content below the notch; the accessories take the band above it
    /// without moving the content.
    func testAccessoriesDrawIntoTheBandTheChromeKeptFree() throws {
        let view = accessorized(leadingHeight: 24)
            .environment(\.nookNotchBand, NookNotchBand(reservedHeight: 32, cutout: notch))
            .padding(.top, 32)

        XCTAssertEqual(try runs(in: view, column: 10), [.init("R", 0), .init("W", 24), .init("B", 32), .init("W", 72)])
        XCTAssertEqual(
            try runs(in: view, column: 190),
            [.init("G", 0), .init("W", 24), .init("B", 32), .init("W", 72)]
        )
        // Nothing is drawn under the notch.
        XCTAssertEqual(try runs(in: view, column: 100), [.init("W", 0), .init("B", 32), .init("W", 72)])
    }

    /// Without a free band the accessories fill the notch's reach at the top of the view, and
    /// the content follows after the column spacing.
    func testAccessoriesFillTheNotchWhenTheContentStartsBesideIt() throws {
        let view = accessorized(leadingHeight: 10)
            .environment(\.nookNotchCutout, notch)

        XCTAssertEqual(
            try runs(in: view, column: 10),
            [.init("W", 0), .init("R", 7), .init("W", 17), .init("B", 32), .init("W", 72)]
        )
    }

    /// Clear of any notch the accessories are simply the first row.
    func testAccessoriesAreTheFirstRowWithoutANotch() throws {
        let view = accessorized(leadingHeight: 10)

        XCTAssertEqual(try runs(in: view, column: 10), [.init("R", 0), .init("W", 10), .init("B", 18), .init("W", 58)])
    }

    /// A flexible side stretches up to the notch, and no further.
    func testRowKeepsFlexibleSidesOutOfTheNotch() throws {
        let view = NookNotchRow {
            Self.red.frame(height: 10)
        } trailing: {
            Self.green.frame(height: 10)
        }
        .environment(\.nookNotchCutout, NookNotchCutout(width: 40, height: 24, centerOffset: 10))

        XCTAssertEqual(try runs(in: view, row: 12), [.init("R", 0), .init("W", 82), .init("G", 138)])
    }

    // MARK: - Rendering

    private static let red = Color(red: 1, green: 0, blue: 0)
    private static let green = Color(red: 0, green: 1, blue: 0)
    private static let blue = Color(red: 0, green: 0, blue: 1)

    private func accessorized(leadingHeight: CGFloat) -> some View {
        Self.blue
            .frame(height: 40)
            .nookNotchAccessories {
                Self.red.frame(width: 30, height: leadingHeight)
            } trailing: {
                Self.green.frame(width: 30, height: leadingHeight)
            }
    }

    /// A stretch of one color along a line of the rendered image.
    struct Run: Equatable, CustomStringConvertible {
        let color: Character
        let start: Int

        init(_ color: Character, _ start: Int) {
            self.color = color
            self.start = start
        }

        var description: String { "\(color)@\(start)" }
    }

    private func runs(in view: some View, column: Int) throws -> [Run] {
        let image = try render(view)
        return colorRuns((0..<image.pixelsHigh).map { image.colorAt(x: column, y: $0) })
    }

    private func runs(in view: some View, row: Int) throws -> [Run] {
        let image = try render(view)
        return colorRuns((0..<image.pixelsWide).map { image.colorAt(x: $0, y: row) })
    }

    private func render(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(
            content:
                view
                .frame(width: 200, height: 120, alignment: .top)
                .background(Color.white)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the view did not render")
        return NSBitmapImageRep(cgImage: image)
    }

    private func colorRuns(_ colors: [NSColor?]) -> [Run] {
        var runs: [Run] = []
        for (index, color) in colors.enumerated() {
            let name = name(of: color)
            if runs.last?.color != name {
                runs.append(Run(name, index))
            }
        }
        return runs
    }

    private func name(of color: NSColor?) -> Character {
        guard let color = color?.usingColorSpace(.sRGB) else { return "?" }
        switch (color.redComponent > 0.5, color.greenComponent > 0.5, color.blueComponent > 0.5) {
            case (true, true, true): return "W"
            case (true, false, false): return "R"
            case (false, true, false): return "G"
            case (false, false, true): return "B"
            default: return "?"
        }
    }
}
