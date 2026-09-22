// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

enum BuildPalette {
    static let running = Color(red: 0.38, green: 0.66, blue: 1.00)
    static let done = Color(red: 0.30, green: 0.84, blue: 0.52)
}

/// A release build as it runs: the overall bar, then each step. When the run finishes, the
/// module posts a "Build succeeded" activity through the `NookActivityQueue`.
struct ProgressHome: View {
    @ObservedObject var run: BuildRunModel
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookContentInsets) private var insets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            SegmentedProgress(run: run)
            VStack(spacing: 0) {
                ForEach(run.steps) { step in
                    StepRow(step: step, state: run.state(of: step))
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, max(insets.bottom, 4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookRimGlow(run.isRunning ? BuildPalette.running : nil)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.45, green: 0.62, blue: 1.0), Color(red: 0.36, green: 0.30, blue: 0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(SampleBuild.project) \(SampleBuild.version)")
                        .foregroundStyle(theme.primaryLabel)
                    Text("Release")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BuildPalette.running)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(BuildPalette.running.opacity(0.16)))
                }
                .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(SampleBuild.branch)
                    Text("·")
                    Text(SampleBuild.commit)
                        .monospaced()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiaryLabel)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(run.isFinished ? "Done" : "\(Int((run.progress * 100).rounded()))%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(run.isFinished ? BuildPalette.done : theme.primaryLabel)
                    .contentTransition(.numericText())
                Text(run.isFinished ? "in \(Format.clock(run.elapsed))" : "\(Format.clock(run.remaining)) left")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.tertiaryLabel)
            }
        }
    }
}

/// One segment per step, each as wide as its share of the run, filling as the run goes.
private struct SegmentedProgress: View {
    @ObservedObject var run: BuildRunModel

    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let total = run.steps.reduce(0) { $0 + $1.duration }
            let available = proxy.size.width - spacing * CGFloat(run.steps.count - 1)
            HStack(spacing: spacing) {
                ForEach(run.steps) { step in
                    let fill: Double =
                        switch run.state(of: step) {
                            case .done: 1
                            case .running(let fraction): fraction
                            case .waiting: 0
                        }
                    ProgressTrack(
                        value: fill,
                        tint: run.isFinished ? BuildPalette.done : BuildPalette.running,
                        height: 5
                    )
                    .frame(width: available * step.duration / total)
                }
            }
        }
        .frame(height: 5)
    }
}

private struct StepRow: View {
    let step: BuildStep
    let state: BuildRunModel.StepState
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 16, height: 16)
            Text(step.title)
                .font(.system(size: 12.5, weight: state == .waiting ? .medium : .semibold))
                .foregroundStyle(state == .waiting ? theme.tertiaryLabel : theme.primaryLabel)
            Text(step.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.quaternaryLabel)
            Spacer(minLength: 8)
            trailing
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .lineLimit(1)
        .frame(height: 24)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BuildPalette.done)
            case .running:
                Spinner(tint: BuildPalette.running, size: 13)
            case .waiting:
                Circle()
                    .strokeBorder(theme.quaternaryLabel, style: StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
                    .frame(width: 13, height: 13)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
            case .done:
                Text("\(Int((step.duration * BuildRunModel.displayScale).rounded()))s")
                    .foregroundStyle(theme.tertiaryLabel)
            case .running(let fraction):
                Text("\(Int((fraction * 100).rounded()))%")
                    .foregroundStyle(BuildPalette.running)
            case .waiting:
                Text("Queued")
                    .foregroundStyle(theme.quaternaryLabel)
        }
    }
}

// MARK: - Companion

/// Starts the run over.
struct BuildCompanion: View {
    @ObservedObject var run: BuildRunModel
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        HStack(spacing: size?.controlSpacing ?? 2) {
            CapsuleButton(symbol: "arrow.clockwise", label: "Restart") { run.restart() }
        }
    }
}

// MARK: - Compact

/// A spinner and the percentage beside the notch, or a check once the run is done.
struct CompactBuildStatus: View {
    @ObservedObject var run: BuildRunModel
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            if run.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BuildPalette.done)
            } else {
                Spinner(tint: BuildPalette.running, size: 11)
            }
            Text(run.isFinished ? "Done" : "\(Int((run.progress * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.primaryLabel)
        }
        .frame(height: 24)
    }
}
