// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

/// Now playing on the left, the queue on the right. The panel washes toward the cover's color
/// through `nookAmbientColor`.
struct PlayerHome: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.nookContentInsets) private var insets

    static let coverSize: CGFloat = 156

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            CoverArt(design: player.track.cover, size: Self.coverSize, cornerRadius: 14)
            NowPlayingColumn(player: player)
                .frame(height: Self.coverSize)
            ColumnRule()
                .frame(height: Self.coverSize)
            UpNextColumn(player: player)
                .frame(width: 196, height: Self.coverSize, alignment: .top)
        }
        .padding(.top, 2)
        .padding(.bottom, max(insets.bottom, 6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookAmbientColor(player.track.cover.colors[2])
        .animation(.snappy(duration: 0.3), value: player.index)
    }
}

private struct NowPlayingColumn: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(player.track.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                EqualizerBars(isPlaying: player.isPlaying, tint: player.track.cover.accent, height: 13)
            }
            Text(player.track.artist)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
                .lineLimit(1)
                .padding(.top, 3)
            HStack(spacing: 6) {
                Text(player.track.album)
                Text("·")
                Text("Lossless")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.tertiaryLabel)
            .lineLimit(1)
            .padding(.top, 4)

            Spacer(minLength: 0)

            Scrubber(elapsed: player.elapsed, duration: player.track.duration)
                .padding(.bottom, 10)

            HStack(spacing: 0) {
                TransportGlyph(symbol: "shuffle", size: 13, isDim: !player.isShuffled, help: "Shuffle") {
                    player.isShuffled.toggle()
                }
                Spacer(minLength: 0)
                TransportGlyph(symbol: "backward.fill", size: 17, help: "Previous") { player.skip(by: -1) }
                Spacer(minLength: 0)
                PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlayback() }
                Spacer(minLength: 0)
                TransportGlyph(symbol: "forward.fill", size: 17, help: "Next") { player.skip(by: 1) }
                Spacer(minLength: 0)
                TransportGlyph(symbol: "repeat", size: 13, isDim: !player.repeats, help: "Repeat") {
                    player.repeats.toggle()
                }
            }
        }
    }
}

private struct Scrubber: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 5) {
            ProgressTrack(value: elapsed / duration, tint: theme.primaryLabel, height: 5)
                .animation(.linear(duration: 1), value: elapsed)
            HStack {
                Text(Format.clock(elapsed))
                Spacer()
                Text("-" + Format.clock(duration - elapsed))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(theme.tertiaryLabel)
        }
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

private struct TransportGlyph: View {
    let symbol: String
    let size: CGFloat
    var isDim = false
    let help: String
    let action: () -> Void
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isDim ? theme.tertiaryLabel : theme.primaryLabel)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct UpNextColumn: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Up Next")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryLabel)
                Spacer()
                Text("\(player.upNext.count) songs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.quaternaryLabel)
            }
            VStack(spacing: 2) {
                ForEach(player.upNext.prefix(4)) { track in
                    Button {
                        player.play(track)
                    } label: {
                        QueueRow(track: track)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct QueueRow: View {
    let track: Track
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            CoverArt(design: track.cover, size: 28, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryLabel)
                Text(track.artist)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.tertiaryLabel)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.clock(track.duration))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.quaternaryLabel)
        }
        .frame(height: 32)
        .contentShape(Rectangle())
    }
}

// MARK: - Companion

/// The capsule under the player: where it plays, and a like button.
struct PlayerCompanion: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        HStack(spacing: size?.controlSpacing ?? 2) {
            CapsuleButton(symbol: player.output.symbol, label: player.output.name) {
                withAnimation(.snappy) { player.toggleOutput() }
            }
            Button {
                player.isLiked.toggle()
            } label: {
                Image(systemName: player.isLiked ? "heart.fill" : "heart")
            }
            .buttonStyle(NookGlyphButtonStyle(foreground: player.isLiked ? Color(red: 1, green: 0.4, blue: 0.5) : nil))
            .accessibilityLabel(player.isLiked ? "Unlike" : "Like")
        }
    }
}

// MARK: - Compact

/// The cover beside the notch.
struct CompactCover: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        CoverArt(design: player.track.cover, size: 20, cornerRadius: 5)
            .frame(height: 24)
    }
}

/// Bars in the cover's color beside the notch.
struct CompactEqualizer: View {
    @ObservedObject var player: PlayerModel

    var body: some View {
        EqualizerBars(isPlaying: player.isPlaying, tint: player.track.cover.accent, height: 13)
            .frame(width: 24, height: 24)
    }
}
