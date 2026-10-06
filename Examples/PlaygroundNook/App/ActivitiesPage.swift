// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookApp
import PlaygroundNookCore
import SwiftUI

/// Live activities to try: start, alert, and end three samples and watch the pill share itself
/// among them. Running activities are a live demo, not part of a look, so a preset never
/// carries them.
struct ActivitiesPage: View {
    @ObservedObject var model: PlaygroundModel
    @StateObject private var samples = PlaygroundActivitySamples()

    var body: some View {
        PlaygroundPageView(page: .activities) {
            SectionCard(title: "Samples") {
                ForEach(PlaygroundActivitySamples.Sample.allCases) { sample in
                    ControlRow(title: sample.title, help: sample.help) {
                        HStack(spacing: 6) {
                            if samples.isRunning(sample, in: activities) {
                                Button("Peek") { activities?.alert(sample.rawValue, .peek(.seconds(3))) }
                                Button("Open") { activities?.alert(sample.rawValue, .expand(.seconds(4))) }
                                Button("End") { activities?.end(sample.rawValue) }
                            } else {
                                Button("Start") {
                                    if let activities { samples.start(sample, in: activities) }
                                }
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            }

            SectionCard(title: "How the pill is shared") {
                Text(
                    "The newest activity of the highest priority holds the pill. The next one shows its "
                        + "minimal view in a capsule beside it, and the capsule counts any others. "
                        + "Pick Peek first on the Appearance page to see an activity's peek on hover. "
                        + "Open the song: its cover is a shared element, so it grows out of the pill."
                )
                .font(PlaygroundTheme.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { samples.objectWillChange.send() }
    }

    /// The playground module's own activities.
    private var activities: NookLiveActivities? {
        guard let coordinator = model.coordinator else { return nil }
        return coordinator.moduleHost.registry.liveActivities.activities(for: coordinator.activeModuleID)
    }
}

/// The three sample activities and the state their views read: a focus timer counting down, a
/// song playing, and a download filling up. One clock ticks all three while any runs.
@MainActor
final class PlaygroundActivitySamples: ObservableObject {
    enum Sample: String, CaseIterable, Identifiable {
        case focus
        case music
        case download

        var id: String { rawValue }

        var title: String {
            switch self {
                case .focus: "Focus timer"
                case .music: "Now playing"
                case .download: "Download"
            }
        }

        var help: String {
            switch self {
                case .focus: "Counts down a session. High priority, so it takes the pill from the others."
                case .music: "A song with its progress. Peeks with the title and artist."
                case .download: "A file filling up. Ends on its own when it is done."
            }
        }
    }

    @Published private(set) var focusRemaining: TimeInterval = 25 * 60
    @Published private(set) var songElapsed: TimeInterval = 64
    @Published private(set) var downloaded: Double = 0.18

    let focusLength: TimeInterval = 25 * 60
    let songLength: TimeInterval = 212

    private var clock: AnyCancellable?

    func isRunning(_ sample: Sample, in activities: NookLiveActivities?) -> Bool {
        activities?.running.contains { $0.id == sample.rawValue } ?? false
    }

    func start(_ sample: Sample, in activities: NookLiveActivities) {
        startClock()
        switch sample {
            case .focus: activities.start(focusActivity())
            case .music: activities.start(musicActivity())
            case .download:
                downloaded = 0.18
                activities.start(downloadActivity())
        }
    }

    private func startClock() {
        guard clock == nil else { return }
        clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        focusRemaining = max(focusRemaining - 1, 0)
        songElapsed = songElapsed >= songLength ? 0 : songElapsed + 1
        downloaded = min(downloaded + 0.04, 1)
    }

    private func focusActivity() -> NookLiveActivity {
        let samples = self
        var activity = NookLiveActivity(
            id: Sample.focus.rawValue,
            priority: .high,
            accessibilityLabel: "Focus"
        ) {
            SampleGlyph(symbol: "flame.fill", tint: .orange)
        } compactTrailing: {
            SampleClock(samples: samples)
        } minimal: {
            SampleRing(samples: samples, sample: .focus)
        }
        activity.setPeek { SamplePeek(samples: samples, sample: .focus) }
        activity.setExpanded { SampleExpanded(samples: samples, sample: .focus) }
        return activity
    }

    private func musicActivity() -> NookLiveActivity {
        let samples = self
        var activity = NookLiveActivity(id: Sample.music.rawValue, accessibilityLabel: "Now playing") {
            SampleCover()
        } compactTrailing: {
            SampleGlyph(symbol: "waveform", tint: .pink)
        } minimal: {
            SampleGlyph(symbol: "music.note", tint: .pink, size: 10)
        }
        activity.setPeek { SamplePeek(samples: samples, sample: .music) }
        activity.setExpanded { SampleExpanded(samples: samples, sample: .music) }
        return activity
    }

    private func downloadActivity() -> NookLiveActivity {
        let samples = self
        var activity = NookLiveActivity(
            id: Sample.download.rawValue,
            lifetime: .transient(.seconds(24)),
            accessibilityLabel: "Download"
        ) {
            SampleGlyph(symbol: "arrow.down.circle.fill", tint: .blue, size: 14)
        } compactTrailing: {
            SamplePercent(samples: samples)
        } minimal: {
            SampleRing(samples: samples, sample: .download)
        }
        activity.setPeek { SamplePeek(samples: samples, sample: .download) }
        return activity
    }

    /// How far along `sample` is, from 0 to 1.
    func progress(_ sample: Sample) -> Double {
        switch sample {
            case .focus: 1 - focusRemaining / focusLength
            case .music: songElapsed / songLength
            case .download: downloaded
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Sample views

private struct SampleGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
    }
}

/// The song's cover. The pill's small one grows into the expanded view's large one as the nook
/// opens onto the song: both are marked as the same shared element.
private struct SampleCover: View {
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
            .overlay { Image(systemName: "music.note").font(.system(size: size / 2, weight: .bold)) }
            .frame(width: size, height: size)
            .nookSharedElement("cover", style: .scale)
            .frame(height: max(size, 24))
    }
}

private struct SampleClock: View {
    @ObservedObject var samples: PlaygroundActivitySamples

    var body: some View {
        Text(PlaygroundActivitySamples.clock(samples.focusRemaining))
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.orange)
            .frame(height: 24)
    }
}

private struct SamplePercent: View {
    @ObservedObject var samples: PlaygroundActivitySamples

    var body: some View {
        Text("\(Int((samples.downloaded * 100).rounded()))%")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.blue)
            .frame(height: 24)
    }
}

private struct SampleRing: View {
    @ObservedObject var samples: PlaygroundActivitySamples
    let sample: PlaygroundActivitySamples.Sample

    var body: some View {
        let tint: Color = sample == .focus ? .orange : .blue
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: samples.progress(sample))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}

private struct SamplePeek: View {
    @ObservedObject var samples: PlaygroundActivitySamples
    let sample: PlaygroundActivitySamples.Sample
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
            }
            .lineLimit(1)
            ProgressView(value: samples.progress(sample))
                .progressViewStyle(.linear)
                .tint(tint)
                .controlSize(.mini)
        }
        .frame(width: 220, alignment: .leading)
    }

    private var title: String {
        switch sample {
            case .focus: "Focus session 2 of 4"
            case .music: "Soft Machinery"
            case .download: "Assets.zip"
        }
    }

    private var detail: String {
        switch sample {
            case .focus: "\(PlaygroundActivitySamples.clock(samples.focusRemaining)) left"
            case .music: "Velvet Cartography"
            case .download: "\(Int((samples.downloaded * 100).rounded()))% of 412 MB"
        }
    }

    private var tint: Color {
        switch sample {
            case .focus: .orange
            case .music: .pink
            case .download: .blue
        }
    }
}

private struct SampleExpanded: View {
    @ObservedObject var samples: PlaygroundActivitySamples
    let sample: PlaygroundActivitySamples.Sample
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            if sample == .music { SampleCover(size: 72) }
            details
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sample == .focus ? "Focus" : "Soft Machinery")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.primaryLabel)
            Text(
                sample == .focus
                    ? "\(PlaygroundActivitySamples.clock(samples.focusRemaining)) left in session 2 of 4"
                    : "Velvet Cartography"
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.secondaryLabel)
            ProgressView(value: samples.progress(sample))
                .progressViewStyle(.linear)
                .tint(sample == .focus ? .orange : .pink)
        }
    }
}
