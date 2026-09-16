// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import SwiftUI

/// Paints a ``NookBackdrop`` for a surface outlined by `shape`.
///
/// Extracted from `NookView` so the chrome and its companion surfaces draw backdrops through
/// one code path: a companion that inherits the chrome's backdrop gets the same material,
/// the same Liquid Glass availability gates, and the same legibility shading. `shape` is
/// what glass is cut to and what the pre-Tahoe rim is traced along; the solid and vibrancy
/// cases fill their frame and rely on the caller's clip.
struct NookBackdropFill<S: Shape>: View {
    let backdrop: NookBackdrop
    let shape: S

    var body: some View {
        switch backdrop {
            case .vibrancy(let spec):
                ZStack {
                    VisualEffectView(
                        material: spec.material,
                        blendingMode: spec.blendingMode
                    )
                    if spec.darkenOpacity > 0 {
                        Color.black.opacity(spec.darkenOpacity)
                    }
                }
            case .solid(let color):
                color
            case .liquidGlass(let glass):
                liquidGlassBackdrop(glass)
        }
    }

    /// Liquid Glass backdrop. Apple's real glass material on macOS 26 Tahoe and later;
    /// a layered approximation on earlier systems. Both shape the glass to `shape`, so the
    /// rim and the eared/floating outline stay in register.
    @ViewBuilder
    private func liquidGlassBackdrop(_ glass: NookBackdrop.LiquidGlass) -> some View {
        // `Glass` / `.glassEffect` exist only in the macOS 26 SDK (Xcode 26+, Swift 6.2).
        // `@available` is a runtime gate and still needs those symbols present in the SDK
        // being compiled against, so an older Xcode cannot build the real path at all.
        // Gate it at compile time too: an older toolchain uses the approximation
        // unconditionally, while the macOS 26 SDK keeps the real material (runtime-gated
        // to macOS 26). This lets a consumer on an earlier Xcode still build the package.
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                realLiquidGlass(glass)
            } else {
                approximateLiquidGlass(glass)
            }
        #else
            approximateLiquidGlass(glass)
        #endif
    }

    #if compiler(>=6.2)
        @available(macOS 26.0, *)
        @ViewBuilder
        private func realLiquidGlass(_ glass: NookBackdrop.LiquidGlass) -> some View {
            let tinted: Glass = {
                guard let tint = glass.tint, glass.tintStrength > 0 else { return .regular }
                return Glass.regular.tint(tint.opacity(glass.tintStrength))
            }()
            Color.clear
                .glassEffect(tinted, in: shape)
                // The legibility pass is whatever the spec carries - the surface adds no
                // darken of its own on top of Apple's self-contrasting material.
                .overlay { glassShading(glass) }
        }
    #endif

    /// The host-supplied legibility shading, rendered as a gradient. `nil` shading draws
    /// nothing, leaving the glass pristine. The gradient, its stops, and its direction all
    /// come from the ``NookBackdrop/LiquidGlass`` spec - the surface never substitutes its
    /// own, so a host can shape the falloff however it likes.
    @ViewBuilder
    private func glassShading(_ glass: NookBackdrop.LiquidGlass) -> some View {
        if let shading = glass.shading {
            LinearGradient(
                gradient: shading.gradient,
                startPoint: shading.startPoint,
                endPoint: shading.endPoint
            )
        }
    }

    /// Pre-Tahoe approximation: a glassy material, an optional tint, a legibility darken,
    /// then the specular treatment that actually reads as "glass" - a top-down sheen and
    /// a bright rim traced along `shape`. The caller's clip trims the rim's outer half,
    /// leaving an inner highlight along the edge.
    @ViewBuilder
    private func approximateLiquidGlass(_ glass: NookBackdrop.LiquidGlass) -> some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            if let tint = glass.tint, glass.tintStrength > 0 {
                tint.opacity(glass.tintStrength)
            }

            glassShading(glass)

            if glass.highlightStrength > 0 {
                LinearGradient(
                    colors: [Color.white.opacity(0.16 * glass.highlightStrength), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5 * glass.highlightStrength),
                                Color.white.opacity(0.06 * glass.highlightStrength),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        }
    }
}
