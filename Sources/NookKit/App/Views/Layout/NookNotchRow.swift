// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// A row split around the hardware notch: `leading` on one side of it and `trailing` on the
/// other, each kept out of the stretch the notch covers.
///
/// The row reads `\.nookNotchCutout`, so it works wherever the notch reaches into its frame,
/// and it is at least as tall as that reach. With no notch in its frame it is an ordinary
/// row, `leading` at the leading edge and `trailing` at the trailing edge.
///
/// To put a row beside the notch while the top bar is hidden, apply
/// `nookNotchAccessories(leading:trailing:)` to the home view rather than placing the row
/// yourself: it also keeps the rest of the content below the notch.
public struct NookNotchRow<Leading: View, Trailing: View>: View {
    private let spacing: CGFloat?
    private let leading: Leading
    private let trailing: Trailing

    @Environment(\.nookNotchCutout) private var cutout
    @Environment(\.nookChromeMetrics) private var metrics

    /// - Parameters:
    ///   - spacing: The least gap between each side and the notch, or between the two sides
    ///     when there is no notch. `nil` uses ``NookChromeMetrics/topBarItemSpacing``.
    ///   - leading: The views before the notch.
    ///   - trailing: The views after the notch.
    public init(
        spacing: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.spacing = spacing
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        NookNotchRowLayout(cutout: cutout, spacing: spacing ?? metrics.topBarItemSpacing) {
            // One subview per side, however many views each builder produces.
            HStack { leading }
            HStack { trailing }
        }
    }
}

/// Places a leading and a trailing subview on either side of the notch.
struct NookNotchRowLayout: Layout {
    var cutout: NookNotchCutout
    var spacing: CGFloat

    /// The widths the two sides may take in a row `width` points wide. With a notch each side
    /// ends `spacing` short of it. Without one the trailing side keeps its ideal width, as
    /// far as the row allows, and the leading side takes the rest.
    static func sideWidths(
        width: CGFloat,
        cutout: NookNotchCutout,
        spacing: CGFloat,
        trailingIdealWidth: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat) {
        guard !cutout.isEmpty else {
            let trailing = min(trailingIdealWidth, max(0, width - spacing))
            return (max(0, width - trailing - spacing), trailing)
        }
        let span = cutout.horizontalSpan(inFrameWidth: width)
        return (
            max(0, min(span.lowerBound, width) - spacing),
            max(0, width - max(span.upperBound, 0) - spacing)
        )
    }

    /// The narrowest row that fits both sides at their ideal widths.
    static func idealWidth(
        leading: CGFloat,
        trailing: CGFloat,
        cutout: NookNotchCutout,
        spacing: CGFloat
    ) -> CGFloat {
        guard !cutout.isEmpty else { return leading + spacing + trailing }
        let halfWidth = max(leading - cutout.centerOffset, trailing + cutout.centerOffset)
        return 2 * (halfWidth + spacing) + cutout.width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let leadingIdeal = subviews[0].sizeThatFits(.unspecified)
        let trailingIdeal = subviews[1].sizeThatFits(.unspecified)
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            width = Self.idealWidth(
                leading: leadingIdeal.width,
                trailing: trailingIdeal.width,
                cutout: cutout,
                spacing: spacing
            )
        }
        let sides = Self.sideWidths(
            width: width,
            cutout: cutout,
            spacing: spacing,
            trailingIdealWidth: trailingIdeal.width
        )
        let leadingHeight = subviews[0].sizeThatFits(ProposedViewSize(width: sides.leading, height: proposal.height))
            .height
        let trailingHeight = subviews[1].sizeThatFits(ProposedViewSize(width: sides.trailing, height: proposal.height))
            .height
        return CGSize(width: width, height: max(leadingHeight, trailingHeight, cutout.isEmpty ? 0 : cutout.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let sides = Self.sideWidths(
            width: bounds.width,
            cutout: cutout,
            spacing: spacing,
            trailingIdealWidth: subviews[1].sizeThatFits(.unspecified).width
        )
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: sides.leading, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(width: sides.trailing, height: bounds.height)
        )
    }
}

extension View {
    /// Puts small views, such as icons and buttons, on either side of the hardware notch, in
    /// the band the top bar fills when it is showing.
    ///
    /// Apply it to the outermost view of the home view's body. While the top bar is hidden
    /// and ``NookTopBarConfiguration/notchClearance`` is ``NookNotchClearance/automatic``,
    /// the chrome starts the content below the notch and the accessories take the band above
    /// it. With ``NookNotchClearance/manual`` they fill the band at the top of the view and
    /// the content follows them. Where there is no band to take, below the top bar or in the
    /// floating form, they are the view's first row.
    ///
    /// ```swift
    /// struct PlayerHome: View {
    ///     var body: some View {
    ///         PlayerView()
    ///             .nookNotchAccessories {
    ///                 Image(systemName: "music.note")
    ///             } trailing: {
    ///                 NookKeepOpenButton()
    ///             }
    ///     }
    /// }
    ///
    /// var configuration = NookConfiguration()
    /// configuration.topBar.showsTopBar = false
    /// configuration.setHome { PlayerHome() }
    /// ```
    ///
    /// The modifier goes inside a view type because ``NookConfiguration/setHome(_:)`` takes
    /// a `Sendable` view, which a modified view is not.
    public func nookNotchAccessories<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(NookNotchAccessoriesModifier(row: NookNotchRow(leading: leading, trailing: trailing)))
    }
}

private struct NookNotchAccessoriesModifier<Leading: View, Trailing: View>: ViewModifier {
    let row: NookNotchRow<Leading, Trailing>

    @Environment(\.nookNotchBand) private var band
    @Environment(\.nookNotchCutout) private var cutout
    @Environment(\.nookChromeMetrics) private var metrics

    func body(content: Content) -> some View {
        if band.reservedHeight > 0 {
            content
                .environment(\.nookNotchBand, .none)
                .overlay(alignment: .top) {
                    row
                        .environment(\.nookNotchCutout, band.cutout)
                        .frame(height: band.cutout.height)
                        // Drawn over the band the chrome kept free. An overlay takes no space,
                        // so the content stays where the chrome put it.
                        .offset(y: -band.reservedHeight)
                }
        } else {
            VStack(alignment: .leading, spacing: metrics.expandedColumnSpacing) {
                row
                content
                    .environment(\.nookNotchCutout, cutout.insetBy(top: cutout.height))
            }
        }
    }
}
