// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

// The widgets the player, agenda, and timer scenes offer. They show only on a board: run
// `--scene board` to see all three side by side.

/// The song: its cover, title, artist, and progress. Larger, the cover grows.
struct NowPlayingWidget: View {
    @ObservedObject var player: PlayerModel
    let size: NookWidgetSize
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        let roomy = size.rows > 1
        HStack(alignment: .center, spacing: 10) {
            CoverArt(design: player.track.cover, size: roomy ? 96 : 48, cornerRadius: roomy ? 10 : 7)
                .nookSharedElement("cover", style: .scale)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.track.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                Text(player.track.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
                ProgressTrack(value: player.elapsed / player.track.duration, tint: theme.primaryLabel, height: 3)
                    .padding(.top, 6)
                    .animation(.linear(duration: 1), value: player.elapsed)
            }
            .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
    }
}

/// The next event on today's agenda, and how soon it starts.
struct NextEventWidget: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        if let next = SampleAgenda.events.first(where: { $0.start > SampleAgenda.now }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(next.tint).frame(width: 7, height: 7)
                    Text("In \(Format.span(next.start - SampleAgenda.now))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(next.tint)
                }
                Spacer(minLength: 0)
                Text(next.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                    .lineLimit(1)
                Text("\(Format.time(next.start)) - \(Format.time(next.end))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.tertiaryLabel)
            }
        }
    }
}

/// The focus session: the time left on a ring.
struct FocusWidget: View {
    @ObservedObject var timer: FocusTimerModel
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(theme.primaryLabel.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(FocusPalette.warm, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.timer(timer.remaining))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.primaryLabel)
                Text("left in session \(timer.session)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.tertiaryLabel)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
