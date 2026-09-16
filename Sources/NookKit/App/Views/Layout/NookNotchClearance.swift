// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// How the expanded surface keeps the home and Settings content clear of the hardware notch.
///
/// In the notch form the notch covers the middle of the band at the top of the panel, the
/// band the top bar fills. Set it with ``NookTopBarConfiguration/notchClearance``. The
/// floating form has no notch, so both cases lay out the same there.
public enum NookNotchClearance: Sendable, Equatable {
    /// The content starts below the notch. The top bar grows to fill the band when the notch
    /// is taller than the bar. With the top bar hidden the band stays empty, apart from views
    /// placed there with `nookNotchAccessories(leading:trailing:)`, and the content starts
    /// where it would below the bar. The default.
    case automatic

    /// The content starts right below the top bar, or at the top of the panel when the bar is
    /// hidden, however far down the notch reaches. Lay it out around the notch with
    /// ``NookNotchRow`` or `\.nookNotchCutout`.
    case manual
}

/// The space the expanded column sets aside for the notch. A pure function of the chrome's
/// settings, so tests can pin it without a display.
struct NookNotchLayout: Equatable {
    /// The least height of the top bar row.
    var topBarMinHeight: CGFloat = 0
    /// The space above the home and Settings content.
    var contentTopPadding: CGFloat = 0

    /// - Parameters:
    ///   - band: How far the notch reaches into the expanded column, or zero without a notch.
    ///   - spacing: The column's spacing, which the bar would leave below itself.
    static func resolve(
        clearance: NookNotchClearance,
        band: CGFloat,
        showsTopBar: Bool,
        spacing: CGFloat
    ) -> NookNotchLayout {
        guard clearance == .automatic, band > 0 else { return NookNotchLayout() }
        if showsTopBar {
            return NookNotchLayout(topBarMinHeight: band)
        }
        // The same start the content has below a bar that exactly fills the band, so hiding
        // the bar leaves the content where it was.
        return NookNotchLayout(contentTopPadding: band + spacing)
    }
}

/// The band `NookExpandedView` kept free above content it moved below the notch, so
/// `nookNotchAccessories(leading:trailing:)` can draw into it.
struct NookNotchBand: Equatable {
    /// How far above the content's top edge the band begins.
    var reservedHeight: CGFloat
    /// The notch, relative to the band.
    var cutout: NookNotchCutout

    static let none = NookNotchBand(reservedHeight: 0, cutout: .none)
}

private struct NookNotchBandKey: EnvironmentKey {
    static let defaultValue = NookNotchBand.none
}

extension EnvironmentValues {
    var nookNotchBand: NookNotchBand {
        get { self[NookNotchBandKey.self] }
        set { self[NookNotchBandKey.self] = newValue }
    }
}
