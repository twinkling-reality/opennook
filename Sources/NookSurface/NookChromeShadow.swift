// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// A shadow the chrome casts onto the desktop. Set it on ``Nook/chromeShadow``.
///
/// The panel's window shadow stays off, since a window shadow is cast by the whole
/// rectangular panel. This one is cast by the chrome's outline instead, so it follows the
/// notch shape through every compact and expanded spring.
///
/// ```swift
/// nook.chromeShadow = NookChromeShadow(color: .black.opacity(0.4), radius: 14, y: 6)
/// ```
public struct NookChromeShadow: Equatable, Sendable {
    public var color: Color
    /// The blur radius, in points.
    public var radius: CGFloat
    /// Horizontal offset, in points.
    public var x: CGFloat
    /// Vertical offset, in points. Positive moves the shadow down.
    public var y: CGFloat

    public init(color: Color = .black.opacity(0.35), radius: CGFloat = 12, x: CGFloat = 0, y: CGFloat = 4) {
        self.color = color
        self.radius = max(radius, 0)
        self.x = x
        self.y = y
    }

    /// A soft shadow just below the chrome.
    public static let soft = NookChromeShadow()

    /// How far past the chrome's frame the shadow can reach.
    var reach: CGFloat {
        (radius * 3 + max(abs(x), abs(y))).rounded(.up)
    }
}

/// Draws a ``NookChromeShadow`` behind the clipped chrome.
///
/// The outline is filled and shadowed, then masked by everything outside the outline, so
/// only the shadow past the edge survives. Both the filled outline and the mask's cut-out are
/// `Shape` views rather than a `Canvas`, so they interpolate the chrome's radii frame by frame
/// as it springs. In the notch form the mask also fades the shadow across the menu-bar band,
/// where the chrome is fused with the menu bar and the top of the screen: a shadow there
/// would read as a smear along the menu bar.
struct NookChromeShadowView: View {
    let shadow: NookChromeShadow
    let shape: NookShape
    /// Height of the band at the top of the chrome the shadow fades out across, or `nil`
    /// for none. See ``NookRimHalo/topFadeHeight``.
    let topFadeHeight: CGFloat?

    var body: some View {
        shape
            .fill(Color.black)
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            .mask { mask }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var mask: some View {
        let reach = shadow.reach
        return ZStack {
            NookRimTopFade(height: topFadeHeight)
                .padding(.horizontal, -reach)
                .padding(.bottom, -reach)
                // The notch form's top edge is the top of the screen; the floating form
                // floats, so its shadow can show above it.
                .padding(.top, topFadeHeight == nil ? -reach : 0)
            shape
                .fill(Color.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
