// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// The rim's crisp line. Drawn inside the chrome's compositing group, before the chrome is
/// clipped to its shape: the stroke is centered on the outline, so the clip removes its
/// outer half and leaves a line of exactly ``NookRimGlowRendering/lineWidth`` on the inside
/// of the edge - the same trick the shimmer overlay uses.
struct NookRimLine<S: Shape>: View {
    let shape: S
    let color: Color
    let rendering: NookRimGlowRendering
    /// See ``NookRimHalo/topFadeHeight``. Without it the notch form traces a line along the
    /// top of the screen, where the chrome is fused with the menu bar.
    let topFadeHeight: CGFloat?

    var body: some View {
        shape
            .stroke(color, lineWidth: rendering.lineWidth * 2)
            .opacity(rendering.lineOpacity)
            .mask { NookRimTopFade(height: topFadeHeight) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The rim's soft halo. Drawn behind the already-clipped chrome so it can spill past the
/// edge.
struct NookRimHalo<S: Shape>: View {
    let shape: S
    let color: Color
    let rendering: NookRimGlowRendering
    /// Height of the band at the top of the chrome the halo fades out across, or `nil` for
    /// none. The notch form passes the menu-bar height: its top edge is fused with the menu
    /// bar and the hardware notch, where a glow reads as a smear across the menu bar rather
    /// than a rim.
    let topFadeHeight: CGFloat?

    var body: some View {
        shape
            .stroke(color, lineWidth: rendering.haloWidth)
            .blur(radius: rendering.haloRadius)
            .opacity(rendering.haloOpacity)
            .modifier(NookRimPulse(isActive: rendering.pulses))
            .mask { mask }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The mask must extend past the chrome's frame by the blur's reach, or it would clip
    /// the halo back to the frame it is meant to spill out of.
    private var mask: some View {
        let reach = rendering.haloRadius * 3 + rendering.haloWidth
        return NookRimTopFade(height: topFadeHeight)
            .padding(.horizontal, -reach)
            .padding(.bottom, -reach)
            // The notch form's top edge is the top of the screen, so nothing above it is
            // ever on screen; the floating form floats, and needs the halo above it too.
            .padding(.top, topFadeHeight == nil ? -reach : 0)
    }
}

/// Opaque, except for an optional band at the top that eases in from clear.
private struct NookRimTopFade: View {
    let height: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            if let height, height > 0 {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
            Color.black
        }
    }
}

/// Breathes the halo's opacity while active. A phase animator hands each half-cycle to the
/// render server, so a rim left lit for minutes does not re-evaluate the view every frame.
private struct NookRimPulse: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([1.0, NookRimGlowRendering.pulseFloor]) { view, phase in
                view.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
        } else {
            content
        }
    }
}
