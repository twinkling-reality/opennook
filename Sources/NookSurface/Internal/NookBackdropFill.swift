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
    /// Stands in for the system's Reduce Transparency setting when set. Tests pin it here;
    /// the environment value it replaces is read-only.
    var reduceTransparencyOverride: Bool?

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        switch backdrop {
            case .vibrancy(let spec):
                ZStack {
                    VisualEffectView(
                        material: spec.material,
                        blendingMode: spec.blendingMode
                    )
                    if spec.darkenOpacity > 0 {
                        spec.darkenColor.opacity(spec.darkenOpacity)
                    }
                }
            case .solid(let color):
                color
            case .liquidGlass(let glass):
                liquidGlassBackdrop(glass)
            case .gradient(let fill):
                if reduceTransparency {
                    NookOpaqueBackdrop(backdrop: backdrop)
                } else {
                    NookGradientFillView(fill: fill)
                }
            case .meshGradient(let mesh):
                if reduceTransparency {
                    NookOpaqueBackdrop(backdrop: backdrop)
                } else {
                    NookMeshFillView(mesh: mesh)
                }
            case .custom(let custom):
                custom.makeView(
                    NookBackdrop.Custom.Context(shape: AnyShape(shape), reduceTransparency: reduceTransparency)
                )
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
            let base: Glass =
                switch glass.variant {
                    case .regular: .regular
                    case .clear: .clear
                }
            let tinted: Glass = {
                guard let tint = glass.tint, glass.tintStrength > 0 else { return base }
                return base.tint(tint.opacity(glass.tintStrength))
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
            VisualEffectView(material: glass.fallbackMaterial, blendingMode: .behindWindow)

            if let tint = glass.tint, glass.tintStrength > 0 {
                tint.opacity(glass.tintStrength)
            }

            glassShading(glass)

            if glass.highlightStrength > 0 {
                let highlight: Color = glass.highlightColor
                LinearGradient(
                    colors: [highlight.opacity(0.16 * glass.highlightStrength), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                if glass.rimWidth > 0 {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    highlight.opacity(0.5 * glass.highlightStrength),
                                    highlight.opacity(0.06 * glass.highlightStrength),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: glass.rimWidth
                        )
                }
            }
        }
    }
}

/// Paints a ``NookBackdrop/GradientFill`` in its layout.
struct NookGradientFillView: View {
    let fill: NookBackdrop.GradientFill

    var body: some View {
        let gradient: Gradient = fill.gradient
        switch fill.layout {
            case .linear(let startPoint, let endPoint):
                LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
            case .radial(let center, let startRadius, let endRadius):
                RadialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
            case .elliptical(let center, let startRadiusFraction, let endRadiusFraction):
                EllipticalGradient(
                    gradient: gradient,
                    center: center,
                    startRadiusFraction: startRadiusFraction,
                    endRadiusFraction: endRadiusFraction
                )
            case .angular(let center, let startAngle, let endAngle):
                AngularGradient(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
        }
    }
}

/// Paints a `MeshGradient`, or only its background when its points or colors do not match
/// its grid.
struct NookMeshFillView: View {
    let mesh: MeshGradient

    var body: some View {
        if mesh.hasConsistentGrid {
            Rectangle().fill(mesh)
        } else {
            mesh.background
        }
    }
}

/// A gradient or mesh backdrop with every color made opaque, for Reduce Transparency.
/// Resolving a color needs the environment, which only this view reads, so the rest of the
/// backdrop does not re-render on every environment change.
private struct NookOpaqueBackdrop: View {
    let backdrop: NookBackdrop
    @Environment(\.self) private var environment

    var body: some View {
        switch backdrop {
            case .gradient(let fill):
                NookGradientFillView(fill: fill.opaque(in: environment))
            case .meshGradient(let mesh):
                NookMeshFillView(mesh: mesh.opaque(in: environment))
            default:
                EmptyView()
        }
    }
}

extension Color {
    /// This color resolved in `environment` with its alpha dropped.
    func opaque(in environment: EnvironmentValues) -> Color {
        var resolved = resolve(in: environment)
        resolved.opacity = 1
        return Color(resolved)
    }
}

extension NookBackdrop.GradientFill {
    /// The same gradient with every stop's color fully opaque.
    func opaque(in environment: EnvironmentValues) -> Self {
        var copy = self
        copy.gradient = Gradient(
            stops: gradient.stops.map { stop in
                Gradient.Stop(color: stop.color.opaque(in: environment), location: stop.location)
            }
        )
        return copy
    }
}

extension MeshGradient {
    /// `true` when the mesh has a point and a color for every vertex of its grid, which is what
    /// `MeshGradient` needs to draw.
    var hasConsistentGrid: Bool {
        guard width > 0, height > 0 else { return false }
        let count = width * height
        let pointCount: Int =
            switch locations {
                case .points(let points): points.count
                case .bezierPoints(let points): points.count
                @unknown default: 0
            }
        let colorCount: Int =
            switch colors {
                case .colors(let colors): colors.count
                case .resolvedColors(let colors): colors.count
                @unknown default: 0
            }
        return pointCount == count && colorCount == count
    }

    /// The same mesh with every color, and its background, fully opaque.
    func opaque(in environment: EnvironmentValues) -> MeshGradient {
        var copy = self
        switch colors {
            case .colors(let colors):
                copy.colors = .colors(colors.map { $0.opaque(in: environment) })
            case .resolvedColors(let colors):
                copy.colors = .resolvedColors(
                    colors.map { color in
                        var opaque = color
                        opaque.opacity = 1
                        return opaque
                    }
                )
            @unknown default:
                break
        }
        copy.background = background.opaque(in: environment)
        return copy
    }
}
