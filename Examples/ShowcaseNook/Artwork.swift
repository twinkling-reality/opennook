// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Original cover art drawn in code: a mesh gradient in the track's palette, one graphic motif,
/// and a film grain, so the showcase needs no image assets and no one else's artwork.
struct CoverArt: View {
    struct Design: Hashable {
        /// Light to dark. The first color is also the track's accent.
        let colors: [Color]
        let motif: Motif

        var accent: Color { colors[0] }
    }

    enum Motif: Hashable {
        case sun
        case rings
        case bands
        case waves
        case orb
        case arches

        /// A stable seed for the grain, so a cover's texture is the same on every launch.
        var seed: Int {
            switch self {
                case .sun: 11
                case .rings: 23
                case .bands: 37
                case .waves: 41
                case .orb: 53
                case .arches: 67
            }
        }
    }

    let design: Design
    let size: CGFloat
    var cornerRadius: CGFloat?

    var body: some View {
        ZStack {
            mesh
            motif
            Grain(seed: design.motif.seed, opacity: size > 60 ? 0.10 : 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var mesh: some View {
        let c = design.colors
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                c[1], c[0], c[1],
                c[2], c[1], c[2],
                c[3], c[2], c[3],
            ]
        )
    }

    @ViewBuilder
    private var motif: some View {
        let c = design.colors
        switch design.motif {
            case .sun:
                // A low sun sliced by horizon lines.
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.95), c[0]],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.56)
                        .offset(y: size * 0.08)
                        .mask {
                            VStack(spacing: 0) {
                                Rectangle().frame(height: size * 0.5)
                                ForEach(0..<6, id: \.self) { index in
                                    Rectangle()
                                        .frame(height: size * (0.05 - CGFloat(index) * 0.006))
                                    Spacer().frame(height: size * (0.012 + CGFloat(index) * 0.008))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: size, height: size, alignment: .top)
                        }
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [.clear, c[3].opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(height: size * 0.34)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            case .rings:
                ZStack {
                    ForEach(0..<6, id: \.self) { index in
                        Circle()
                            .stroke(Color.white.opacity(0.55 - Double(index) * 0.07), lineWidth: size * 0.018)
                            .frame(width: size * (0.18 + CGFloat(index) * 0.17))
                    }
                    Circle()
                        .fill(c[0])
                        .frame(width: size * 0.12)
                }
                .offset(x: size * 0.18, y: size * 0.16)
            case .bands:
                // Diagonal ribbons in the palette.
                ZStack {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index.isMultiple(of: 2) ? c[0].opacity(0.9) : c[3].opacity(0.55))
                            .frame(width: size * 1.6, height: size * 0.09)
                            .offset(y: CGFloat(index - 2) * size * 0.17)
                    }
                }
                .rotationEffect(.degrees(-28))
                .blendMode(.plusLighter)
            case .waves:
                Canvas { context, canvasSize in
                    for line in 0..<9 {
                        var path = Path()
                        let baseline = canvasSize.height * (0.22 + CGFloat(line) * 0.075)
                        let amplitude = canvasSize.height * (0.02 + CGFloat(line) * 0.006)
                        path.move(to: CGPoint(x: 0, y: baseline))
                        for step in stride(from: 0, through: canvasSize.width, by: 2) {
                            let phase = step / canvasSize.width * .pi * 2.4 + CGFloat(line) * 0.5
                            path.addLine(to: CGPoint(x: step, y: baseline + sin(phase) * amplitude))
                        }
                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.18 + Double(line) * 0.06)),
                            lineWidth: max(canvasSize.width * 0.008, 0.6)
                        )
                    }
                }
            case .orb:
                ZStack {
                    Circle()
                        .fill(c[0])
                        .frame(width: size * 0.7)
                        .blur(radius: size * 0.12)
                        .offset(x: -size * 0.12, y: -size * 0.1)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, c[1]],
                                center: .init(x: 0.35, y: 0.3),
                                startRadius: 0,
                                endRadius: size * 0.14
                            )
                        )
                        .frame(width: size * 0.22)
                        .shadow(color: c[3].opacity(0.6), radius: size * 0.04, y: size * 0.02)
                        .offset(x: size * 0.2, y: size * 0.18)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: max(size * 0.006, 0.5))
                        .frame(width: size * 0.62, height: size * 0.62)
                        .scaleEffect(x: 1, y: 0.32)
                        .rotationEffect(.degrees(-18))
                        .offset(x: size * 0.2, y: size * 0.18)
                }
            case .arches:
                HStack(alignment: .bottom, spacing: size * 0.04) {
                    ForEach(0..<3, id: \.self) { index in
                        UnevenRoundedRectangle(
                            topLeadingRadius: size * 0.13,
                            topTrailingRadius: size * 0.13,
                            style: .continuous
                        )
                        .fill(index == 1 ? c[0] : c[2].opacity(0.9))
                        .frame(width: size * 0.26, height: size * (index == 1 ? 0.58 : 0.42))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, size * 0.1)
        }
    }
}

/// A fixed film grain, seeded so each cover keeps its own texture from frame to frame.
private struct Grain: View {
    let seed: Int
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            var state = UInt64(truncatingIfNeeded: seed) | 1
            func next() -> CGFloat {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(state >> 40) / CGFloat(1 << 24)
            }
            let count = Int(size.width * size.height / 9)
            for _ in 0..<count {
                let point = CGPoint(x: next() * size.width, y: next() * size.height)
                let bright = next() > 0.5
                context.fill(
                    Path(CGRect(origin: point, size: CGSize(width: 0.8, height: 0.8))),
                    with: .color(bright ? .white.opacity(opacity) : .black.opacity(opacity * 1.4))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
