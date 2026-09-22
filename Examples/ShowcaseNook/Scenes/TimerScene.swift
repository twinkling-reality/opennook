// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

enum FocusPalette {
    static let warm = Color(red: 1.00, green: 0.55, blue: 0.26)
    static let hot = Color(red: 1.00, green: 0.33, blue: 0.40)
}

/// A countdown dial beside the time and its controls. The rim glows while the timer runs.
struct TimerHome: View {
    @ObservedObject var timer: FocusTimerModel
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookContentInsets) private var insets

    var body: some View {
        HStack(spacing: 26) {
            TickDial(
                progress: timer.progress,
                isRunning: timer.isRunning,
                session: timer.session,
                sessions: timer.sessions
            )
            .frame(width: 138, height: 138)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(FocusPalette.warm)
                    Text("Deep work")
                        .foregroundStyle(theme.primaryLabel)
                    Text("Session \(timer.session) of \(timer.sessions)")
                        .foregroundStyle(theme.tertiaryLabel)
                        .padding(.leading, 2)
                }
                .font(.system(size: 12, weight: .semibold))

                Text(Format.timer(timer.remaining))
                    .font(.system(size: 56, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.primaryLabel)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.remaining)
                    .padding(.top, 2)

                Text(endsAt)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryLabel)

                HStack(spacing: 8) {
                    Button {
                        timer.toggle()
                    } label: {
                        Label(
                            timer.isRunning ? "Pause" : "Resume",
                            systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(.white))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        timer.addFiveMinutes()
                    } label: {
                        Text("+5 min")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(theme.subtleFill.opacity(2)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        timer.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(NookGlyphButtonStyle(size: .points(30), glyphSize: 12, fill: .subtle))
                    .accessibilityLabel("Reset")
                }
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.top, 4)
        .padding(.bottom, max(insets.bottom, 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookRimGlow(timer.isRunning ? FocusPalette.warm : nil)
    }

    private var endsAt: String {
        let end = Date().addingTimeInterval(timer.remaining)
        return timer.isRunning ? "Ends at \(end.formatted(date: .omitted, time: .shortened))" : "Paused"
    }
}

/// A ring of minute ticks, lit up to the time that has passed, with the session dots inside.
private struct TickDial: View {
    let progress: Double
    let isRunning: Bool
    let session: Int
    let sessions: Int
    @Environment(\.nookResolvedTheme) private var theme

    private let tickCount = 60

    // Split into three properties: as one expression the compiler could not type-check
    // this body in reasonable time on CI.
    var body: some View {
        ZStack {
            ticks
            ring
            center
        }
    }

    /// The minute ticks, lit up to the time that has passed.
    private var ticks: some View {
        // Every value is typed on purpose: mixing CGFloat and Double through the trig and
        // the ternaries left the compiler unable to type-check this in reasonable time.
        Canvas { context, size in
            let centerX: CGFloat = size.width / 2
            let centerY: CGFloat = size.height / 2
            let radius: CGFloat = min(size.width, size.height) / 2
            let lit = Int((progress * Double(tickCount)).rounded(.down))

            for tick in 0..<tickCount {
                let isMajor: Bool = tick % 5 == 0
                let angle: Double = Double(tick) / Double(tickCount) * 2 * .pi - .pi / 2
                let cosAngle = CGFloat(cos(angle))
                let sinAngle = CGFloat(sin(angle))
                let outer: CGFloat = radius - 1
                let inner: CGFloat = outer - (isMajor ? 12 : 7)

                var path = Path()
                path.move(to: CGPoint(x: centerX + cosAngle * inner, y: centerY + sinAngle * inner))
                path.addLine(to: CGPoint(x: centerX + cosAngle * outer, y: centerY + sinAngle * outer))

                let color: Color
                if tick < lit {
                    color = blend(Double(tick) / Double(tickCount))
                } else {
                    let opacity: Double = isMajor ? 0.26 : 0.13
                    color = Color.white.opacity(opacity)
                }
                let width: CGFloat = isMajor ? 2.4 : 1.6
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    /// The progress ring over the ticks.
    private var ring: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(
                    colors: [FocusPalette.warm, FocusPalette.hot],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360 * max(progress, 0.01))
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(19)
    }

    /// The state glyph and the session dots inside the dial.
    private var center: some View {
        VStack(spacing: 6) {
            Image(systemName: isRunning ? "flame.fill" : "pause.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [FocusPalette.warm, FocusPalette.hot],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            HStack(spacing: 4) {
                ForEach(1...sessions, id: \.self) { index in
                    Capsule()
                        .fill(
                            index < session
                                ? FocusPalette.warm
                                : (index == session ? theme.primaryLabel : theme.quaternaryLabel)
                        )
                        .frame(width: index == session ? 10 : 4, height: 4)
                }
            }
        }
    }

    private func blend(_ fraction: Double) -> Color {
        fraction < 0.5 ? FocusPalette.warm : FocusPalette.hot
    }
}

// MARK: - Companion

/// Session lengths under the timer.
struct TimerPresetsCompanion: View {
    @ObservedObject var timer: FocusTimerModel
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        HStack(spacing: size?.controlSpacing ?? 2) {
            ForEach(FocusTimerModel.presets, id: \.self) { minutes in
                CapsuleButton(symbol: "", label: "\(minutes) min", isSelected: timer.presetMinutes == minutes) {
                    timer.select(minutes: minutes)
                }
            }
        }
    }
}

// MARK: - Compact

/// The time left beside the notch, with a small ring. With `lightsRim`, it keeps the rim lit
/// while the session runs and the nook is collapsed.
struct CompactTimer: View {
    @ObservedObject var timer: FocusTimerModel
    var lightsRim = false
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(theme.primaryLabel.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(FocusPalette.warm, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text(Format.timer(timer.remaining))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(FocusPalette.warm)
        }
        .frame(height: 24)
        .nookRimGlow(lightsRim && timer.isRunning ? FocusPalette.warm : nil)
    }
}
