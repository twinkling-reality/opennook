// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import PlaygroundNookCore
import SwiftUI

/// The mark for a way of asking. Drawn as paths, not as a system symbol, so Codex, Claude, and
/// Ollama each have a face of their own.
struct AssistantProviderMark: View {
    let option: AssistantProviderOption
    var body: some View {
        mark
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch option {
            case .codexCLI, .openAI: CodexBlossom()
            case .claudeCLI, .anthropic: ClaudeAsterisk()
            case .ollama: OllamaLlama()
            case .clipboard: ClipboardMark()
        }
    }
}

/// Six interlocking petals, the knot people already read as Codex and OpenAI.
private struct CodexBlossom: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<6 {
                var path = Path()
                let turn = Angle.degrees(Double(i) * 60 - 90)
                context.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: turn)
                    let length = r * 0.92
                    let width = r * 0.34
                    path.addEllipse(
                        in: CGRect(x: r * 0.06, y: -width / 2, width: length * 0.72, height: width)
                    )
                    layer.fill(path, with: .foreground)
                }
            }
            var eye = Path()
            eye.addEllipse(
                in: CGRect(
                    x: center.x - r * 0.16,
                    y: center.y - r * 0.16,
                    width: r * 0.32,
                    height: r * 0.32
                )
            )
            context.blendMode = .destinationOut
            context.fill(eye, with: .color(.white))
        }
        .compositingGroup()
    }
}

/// Four tapered arms, the asterisk people already read as Claude.
private struct ClaudeAsterisk: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<4 {
                var path = Path()
                context.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .degrees(Double(i) * 45))
                    path.move(to: CGPoint(x: 0, y: -r * 0.18))
                    path.addLine(to: CGPoint(x: r * 0.16, y: -r * 0.18))
                    path.addQuadCurve(
                        to: CGPoint(x: 0, y: -r * 0.96),
                        control: CGPoint(x: r * 0.22, y: -r * 0.55)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: -r * 0.16, y: -r * 0.18),
                        control: CGPoint(x: -r * 0.22, y: -r * 0.55)
                    )
                    path.closeSubpath()
                    layer.fill(path, with: .foreground)
                }
            }
        }
    }
}

/// A llama head in profile. Enough of Ollama that it is not a computer.
private struct OllamaLlama: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: y * s)
            }
            var body = Path()
            body.move(to: p(0.22, 0.86))
            body.addQuadCurve(to: p(0.18, 0.52), control: p(0.08, 0.74))
            body.addQuadCurve(to: p(0.42, 0.34), control: p(0.20, 0.36))
            body.addLine(to: p(0.48, 0.12))
            body.addQuadCurve(to: p(0.58, 0.30), control: p(0.62, 0.10))
            body.addLine(to: p(0.64, 0.16))
            body.addQuadCurve(to: p(0.70, 0.36), control: p(0.78, 0.16))
            body.addQuadCurve(to: p(0.88, 0.48), control: p(0.86, 0.38))
            body.addQuadCurve(to: p(0.78, 0.62), control: p(0.94, 0.58))
            body.addQuadCurve(to: p(0.70, 0.86), control: p(0.86, 0.78))
            body.addQuadCurve(to: p(0.22, 0.86), control: p(0.46, 0.96))
            context.fill(body, with: .foreground)

            var eye = Path()
            eye.addEllipse(in: CGRect(x: 0.68 * s, y: 0.42 * s, width: 0.10 * s, height: 0.10 * s))
            context.blendMode = .destinationOut
            context.fill(eye, with: .color(.white))
        }
        .compositingGroup()
    }
}

/// A clipboard with a clip, so the manual path is not a generic document.
private struct ClipboardMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let board = CGRect(x: 0.22 * s, y: 0.18 * s, width: 0.56 * s, height: 0.70 * s)
            let body = Path(roundedRect: board, cornerRadius: 0.10 * s)
            context.stroke(
                body,
                with: .foreground,
                style: StrokeStyle(lineWidth: s * 0.08, lineJoin: .round)
            )
            let clip = Path(
                roundedRect: CGRect(x: 0.36 * s, y: 0.08 * s, width: 0.28 * s, height: 0.20 * s),
                cornerRadius: 0.05 * s
            )
            context.fill(clip, with: .foreground)
            for (index, y) in [0.42, 0.56, 0.70].enumerated() {
                var line = Path()
                let inset: CGFloat = index == 2 ? 0.22 : 0.16
                line.move(to: CGPoint(x: 0.34 * s, y: y * s))
                line.addLine(to: CGPoint(x: (0.78 - inset) * s, y: y * s))
                context.stroke(
                    line,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round)
                )
            }
        }
    }
}
