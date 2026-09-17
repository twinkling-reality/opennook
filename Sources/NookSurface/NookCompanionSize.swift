// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// The size a companion surface and the controls inside it share, so companions side by side
/// line up without any arithmetic in their content.
///
/// A companion styled with ``NookStandardCompanionStyle`` is at least ``height`` tall, and a
/// circle companion is that wide too. Controls sized from ``controlSize`` - such as NookKit's
/// glyph button style - sit ``inset`` in from the surface's edge, so a single control in a
/// circle and a row of them in a capsule come out the same height:
///
/// ```swift
/// configuration.companionSize = .large
/// ```
///
/// Read it inside companion content from `\.nookCompanionSize`.
public struct NookCompanionSize: Hashable, Sendable {
    /// A companion surface's height, and a circle companion's width.
    public var height: CGFloat

    /// The side of one control inside a companion: a glyph button's frame and hit area.
    public var controlSize: CGFloat

    /// The point size of a control's glyph.
    public var glyphSize: CGFloat

    /// The space between controls in a row or column of them.
    public var controlSpacing: CGFloat

    public init(height: CGFloat, controlSize: CGFloat, glyphSize: CGFloat, controlSpacing: CGFloat = 2) {
        self.height = max(height, 0)
        self.controlSize = max(controlSize, 0)
        self.glyphSize = max(glyphSize, 1)
        self.controlSpacing = max(controlSpacing, 0)
    }

    /// The space between a control and the edge of the surface around it, so a control centered
    /// in a surface of ``height`` is concentric with its rounded end.
    public var inset: CGFloat {
        max((height - controlSize) / 2, 0)
    }

    /// This size scaled down, if need be, so a surface is no taller than `height`, with its
    /// controls and glyphs scaled to match. A size that already fits is returned as it is.
    ///
    /// The chrome fits every companion beside it to the chrome's own height, so a companion
    /// shown beside the compact pill is never taller than the pill.
    public func fitting(height limit: CGFloat) -> NookCompanionSize {
        guard limit < height, height > 0 else { return self }
        let limit = max(limit, 0)
        let control = (controlSize * limit / height).rounded()
        let glyph = controlSize > 0 ? (glyphSize * control / controlSize).rounded() : glyphSize
        return NookCompanionSize(
            height: limit,
            controlSize: control,
            glyphSize: glyph,
            controlSpacing: controlSpacing
        )
    }

    /// 32 pt surfaces around 26 pt controls, a fit for the compact pill on most displays.
    public static let small = NookCompanionSize(height: 32, controlSize: 26, glyphSize: 11)

    /// 40 pt surfaces around 32 pt controls. The default.
    public static let regular = NookCompanionSize(height: 40, controlSize: 32, glyphSize: 13)

    /// 48 pt surfaces around 40 pt controls.
    public static let large = NookCompanionSize(height: 48, controlSize: 40, glyphSize: 16, controlSpacing: 4)
}

private struct NookCompanionSizeKey: EnvironmentKey {
    static let defaultValue: NookCompanionSize? = nil
}

extension EnvironmentValues {
    /// The size the enclosing companion surface shares with its controls. `nil` outside a
    /// companion surface, so a control can tell whether it sits in one.
    public var nookCompanionSize: NookCompanionSize? {
        get { self[NookCompanionSizeKey.self] }
        set { self[NookCompanionSizeKey.self] = newValue }
    }
}
