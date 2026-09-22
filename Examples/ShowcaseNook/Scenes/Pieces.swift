// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

/// Animated equalizer bars, flat while paused.
struct EqualizerBars: View {
    let isPlaying: Bool
    let tint: Color
    var barCount = 4
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: height * 0.16) {
                ForEach(0..<barCount, id: \.self) { bar in
                    let phase = time * (2.6 + Double(bar) * 0.7) + Double(bar) * 1.3
                    let level = isPlaying ? 0.3 + 0.7 * abs(sin(phase)) : 0.18
                    Capsule()
                        .fill(tint)
                        .frame(width: height * 0.18, height: max(height * level, height * 0.18))
                }
            }
            .frame(height: height)
        }
    }
}

/// A thin determinate bar in the palette's subtle fill.
struct ProgressTrack: View {
    let value: Double
    var tint: Color = .white
    var height: CGFloat = 4
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Capsule()
            .fill(theme.subtleFill.opacity(2.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if value > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(proxy.size.width * min(value, 1), height))
                    }
                }
            }
            .frame(height: height)
    }
}

/// A small spinning arc for work under way. Drawn rather than an `NSProgressIndicator`, so it
/// takes the step's tint.
struct Spinner: View {
    var tint: Color
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: size * 0.14)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
        }
    }
}

/// A plain text button in a capsule, for the companions under the panel.
struct CapsuleButton: View {
    let symbol: String
    let label: String
    var isSelected = false
    let action: () -> Void
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if !symbol.isEmpty {
                    Image(systemName: symbol)
                }
                Text(label)
            }
            .font(.system(size: (size?.glyphSize ?? 13) - 1, weight: .semibold))
            .foregroundStyle(isSelected ? theme.primaryLabel : theme.secondaryLabel)
            .padding(.horizontal, 11)
            .frame(minHeight: size?.controlSize ?? 32)
            .background {
                Capsule().fill(isSelected ? theme.primaryLabel.opacity(0.16) : .clear)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A 1 pt vertical rule between columns.
struct ColumnRule: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.subtleStroke.opacity(0.7))
            .frame(width: 1)
            .padding(.vertical, 4)
    }
}

/// A glyph in a compact slot beside the notch.
struct CompactGlyph: View {
    let symbol: String
    var tint: Color?
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint ?? theme.primaryLabel.opacity(0.82))
            .frame(width: 24, height: 24)
    }
}
