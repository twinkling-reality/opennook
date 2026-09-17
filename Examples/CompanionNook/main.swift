// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// CompanionNook - companion surfaces floated beside the nook.
//
// The expanded nook is a small media player. Two companion surfaces float below it,
// registered with `NookConfiguration.addCompanion`:
//   - a pill of three icon buttons that switches what the player shows, and
//   - a separate round button that starts a sleep timer.
// Companions ride the nook's expand and collapse, follow it in the notch, floating, and
// auto layouts, paint with the chrome's backdrop (switch to Liquid Glass in Settings), and
// never take focus from the nook. Every companion shares one size
// (`NookConfiguration.companionSize`), so the pill and the round button are the same height.
//
// A third companion hangs beside the panel: the framework's own keep-open lock and Settings
// gear, moved out of the top bar (`showsKeepOpenButton` / `showsSettingsButton` off,
// `NookKeepOpenButton` / `NookSettingsButton` in the companion).
//
// A fourth comes and goes while the app runs. Send the music to the living room speaker
// with the speaker button, and a small chip saying so appears beside the compact pill; send
// it back, and the chip leaves. The module adds and removes it on a `NookCompanionSource`,
// with no configuration reload, and draws it with the faded style and the pop presence.
//
// Two smaller seams ride along. While the sleep timer runs, the round button stays beside
// the compact pill (`nookCompanionVisibility`) and lights the rim blue (`nookRimGlow`). The
// Up Next and Library lists fade where they meet the panel's edges (`scrollEdgeFade`).
//
// It is written as a `NookModule` class, like ActivityNook, so the module owns its player
// and stops the playback clock when it is switched away (`onDeactivate`). The framework
// takes the module's companions off the surface in that same switch.
//
// Run with `swift run CompanionNook`, then press ⌥⌘; to expand.

import Combine
import NookApp
import SwiftUI

// MARK: - Model

struct Track: Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let duration: TimeInterval
    let tint: Color
    let symbol: String
    var isExplicit = false
    var isLossless = true
}

/// The player every view observes. A single instance lives on the module.
@MainActor
final class MediaPlayer: ObservableObject {
    enum Section: CaseIterable {
        case nowPlaying
        case upNext
        case library
    }

    /// Shortened for the demo so the timer visibly runs out.
    static let sleepTimerDuration: TimeInterval = 30

    let tracks: [Track] = [
        Track(
            id: 0,
            title: "Midnight Drive",
            artist: "Neon Coast",
            duration: 154,
            tint: .teal,
            symbol: "car.fill",
            isExplicit: true
        ),
        Track(
            id: 1,
            title: "Paper Planes",
            artist: "The Driftwood",
            duration: 201,
            tint: .orange,
            symbol: "paperplane.fill"
        ),
        Track(id: 2, title: "Low Tide", artist: "Marisol", duration: 183, tint: .blue, symbol: "water.waves"),
        Track(
            id: 3,
            title: "Glasshouse",
            artist: "Aurora Lines",
            duration: 227,
            tint: .purple,
            symbol: "sparkles",
            isLossless: false
        ),
        Track(
            id: 4,
            title: "Static Bloom",
            artist: "Violet Hour",
            duration: 176,
            tint: .pink,
            symbol: "camera.macro",
            isExplicit: true
        ),
        Track(id: 5, title: "Northbound", artist: "Field Notes", duration: 245, tint: .green, symbol: "leaf.fill"),
    ]

    /// Where the music plays.
    enum Output: Equatable {
        case thisMac
        case speaker(String)

        var symbol: String {
            switch self {
                case .thisMac: "laptopcomputer"
                case .speaker: "hifispeaker.fill"
            }
        }

        var label: String {
            switch self {
                case .thisMac: "Playing on this Mac"
                case .speaker(let name): "Playing on \(name)"
            }
        }
    }

    @Published private(set) var index = 0
    @Published private(set) var elapsed: TimeInterval = 26
    @Published private(set) var isPlaying = true
    @Published var section: Section = .nowPlaying
    @Published private(set) var sleepTimerEndsAt: Date?
    @Published private(set) var now = Date()
    @Published private(set) var output = Output.thisMac

    private var clock: Timer?

    var track: Track { tracks[index] }

    /// The tracks after the current one, wrapping around.
    var upNext: [Track] {
        Array(tracks[(index + 1)...] + tracks[..<index])
    }

    var isSleepTimerRunning: Bool { sleepTimerEndsAt != nil }

    /// How much of the sleep timer is left, from 1 down to 0, or `nil` when it is off.
    var sleepTimerFraction: Double? {
        guard let sleepTimerEndsAt else { return nil }
        return min(max(sleepTimerEndsAt.timeIntervalSince(now) / Self.sleepTimerDuration, 0), 1)
    }

    func startClock() {
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor to advance playback.
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    func togglePlayback() {
        isPlaying.toggle()
    }

    func skip(by offset: Int) {
        index = (index + offset + tracks.count) % tracks.count
        elapsed = 0
    }

    func play(_ track: Track) {
        guard let position = tracks.firstIndex(of: track) else { return }
        index = position
        elapsed = 0
        isPlaying = true
        section = .nowPlaying
    }

    func toggleSleepTimer() {
        now = Date()
        sleepTimerEndsAt = isSleepTimerRunning ? nil : now.addingTimeInterval(Self.sleepTimerDuration)
    }

    /// Moves the music between this Mac and the living room speaker.
    func toggleOutput() {
        output = output == .thisMac ? .speaker("Living Room") : .thisMac
    }

    private func tick() {
        now = Date()
        if isPlaying {
            elapsed += 1
            if elapsed >= track.duration { skip(by: 1) }
        }
        if let sleepTimerEndsAt, now >= sleepTimerEndsAt {
            self.sleepTimerEndsAt = nil
            isPlaying = false
        }
    }
}

// MARK: - Expanded home

/// Switches on the section the companion pill picked. A fixed height keeps the panel from
/// resizing as the sections change.
struct MediaHomeView: View {
    @ObservedObject var player: MediaPlayer

    var body: some View {
        Group {
            switch player.section {
                case .nowPlaying: NowPlayingView(player: player)
                case .upNext: UpNextList(player: player)
                case .library: LibraryGrid(player: player)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 164)
        .padding(.bottom, 4)
        .animation(.snappy(duration: 0.25), value: player.section)
    }
}

struct NowPlayingView: View {
    @ObservedObject var player: MediaPlayer
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Artwork(track: player.track, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(player.track.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.primaryLabel)
                            .lineLimit(1)
                        if player.track.isExplicit { Badge(letter: "E") }
                        if player.track.isLossless { Badge(letter: "L") }
                    }
                    Text(player.track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryLabel)
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.track.tint)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: player.isPlaying)
            }

            PlaybackProgress(elapsed: player.elapsed, duration: player.track.duration)

            HStack {
                TransportButton(symbol: "list.bullet", help: "Up Next") { player.section = .upNext }
                Spacer()
                TransportButton(symbol: "backward.fill", help: "Previous") { player.skip(by: -1) }
                Spacer()
                TransportButton(
                    symbol: player.isPlaying ? "pause.fill" : "play.fill",
                    size: 24,
                    help: player.isPlaying ? "Pause" : "Play"
                ) { player.togglePlayback() }
                Spacer()
                TransportButton(symbol: "forward.fill", help: "Next") { player.skip(by: 1) }
                Spacer()
                TransportButton(symbol: player.output.symbol, help: player.output.label) {
                    withAnimation(.snappy) { player.toggleOutput() }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct UpNextList: View {
    @ObservedObject var player: MediaPlayer
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Up Next")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.secondaryLabel)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(player.upNext) { track in
                        Button {
                            player.play(track)
                        } label: {
                            HStack(spacing: 10) {
                                Artwork(track: track, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(theme.primaryLabel)
                                    Text(track.artist)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.tertiaryLabel)
                                }
                                Spacer(minLength: 0)
                                Text(Duration.seconds(track.duration).formatted(.time(pattern: .minuteSecond)))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(theme.tertiaryLabel)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // Follows the panel-wide `scrollEdgeFade` set on the configuration below.
            .nookScrollEdgeFade(axes: .vertical)
        }
    }
}

struct LibraryGrid: View {
    @ObservedObject var player: MediaPlayer
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                ForEach(player.tracks) { track in
                    Button {
                        player.play(track)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Artwork(track: track, size: 84)
                            Text(track.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.primaryLabel)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .nookScrollEdgeFade(axes: .vertical)
    }
}

// MARK: - Companion surfaces

/// The pill of three icon buttons under the expanded nook. The companion's style pads it and
/// gives it its height; the buttons take their size from the companion.
struct MediaSectionsPill: View {
    @ObservedObject var player: MediaPlayer
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        HStack(spacing: size?.controlSpacing ?? 2) {
            sectionButton(.nowPlaying, symbol: "house.fill", label: "Now Playing")
            sectionButton(.upNext, symbol: "tray.fill", label: "Up Next", count: player.upNext.count)
            sectionButton(.library, symbol: "square.grid.2x2.fill", label: "Library")
        }
    }

    private func sectionButton(
        _ section: MediaPlayer.Section,
        symbol: String,
        label: String,
        count: Int? = nil
    ) -> some View {
        let isSelected = player.section == section
        let side = size?.controlSize ?? 32
        let glyph = size?.glyphSize ?? 13
        return Button {
            player.section = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: glyph, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(isSelected ? theme.primaryLabel : theme.secondaryLabel)
            .frame(minWidth: side, minHeight: side)
            .padding(.horizontal, count == nil ? 0 : 8)
            .background {
                Capsule().fill(isSelected ? theme.primaryLabel.opacity(0.16) : .clear)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The separate round button. It is registered for both nook states, and its content
/// narrows that to the expanded state unless the sleep timer is running - so a running
/// timer stays visible beside the compact pill, glowing blue.
struct SleepTimerButton: View {
    @ObservedObject var player: MediaPlayer
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        Button {
            player.toggleSleepTimer()
        } label: {
            ZStack {
                if let fraction = player.sleepTimerFraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(.linear(duration: 1), value: fraction)
                }
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: size?.glyphSize ?? 13, weight: .semibold))
                    .foregroundStyle(player.isSleepTimerRunning ? Color.blue : theme.primaryLabel)
            }
            .frame(width: size?.controlSize ?? 32, height: size?.controlSize ?? 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(player.isSleepTimerRunning ? "Cancel the sleep timer" : "Pause playback in 30 seconds")
        .accessibilityLabel(player.isSleepTimerRunning ? "Cancel sleep timer" : "Start sleep timer")
        .nookCompanionVisibility(player.isSleepTimerRunning ? .both : .expanded)
        .nookRimGlow(player.isSleepTimerRunning ? .blue : nil)
    }
}

/// The framework's keep-open lock and Settings gear, stacked in a companion beside the
/// panel instead of the top bar. In a companion they take its control size.
struct ChromeControls: View {
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        VStack(spacing: size?.controlSpacing ?? 2) {
            NookKeepOpenButton()
            NookSettingsButton()
        }
    }
}

/// Where the music is going, beside the compact pill while it plays on a speaker.
struct OutputChip: View {
    let name: String
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(theme.accent)
            Text(name)
                .foregroundStyle(theme.primaryLabel)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
    }
}

// MARK: - Compact slots

struct CompactArtwork: View {
    @ObservedObject var player: MediaPlayer

    var body: some View {
        Artwork(track: player.track, size: 18, showsAppBadge: false)
            .frame(width: 24, height: 24)
    }
}

struct CompactWaveform: View {
    @ObservedObject var player: MediaPlayer

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(player.track.tint)
            .symbolEffect(.variableColor.iterative.reversing, isActive: player.isPlaying)
            .frame(width: 24, height: 24)
    }
}

// MARK: - Pieces

/// Stand-in album art: a tinted gradient tile with a symbol, so the example needs no assets.
struct Artwork: View {
    let track: Track
    let size: CGFloat
    var showsAppBadge = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [track.tint.opacity(0.95), track.tint.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: track.symbol)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .overlay(alignment: .bottomTrailing) {
                if showsAppBadge {
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .fill(Color.red.gradient)
                        .frame(width: size * 0.3, height: size * 0.3)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: size * 0.16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(size * 0.06)
                }
            }
            .frame(width: size, height: size)
    }
}

/// A small rounded letter badge, knocked out of a label-colored tile so it reads on any
/// backdrop and theme.
struct Badge: View {
    let letter: String
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Text(letter)
            .font(.system(size: 10, weight: .heavy))
            .frame(width: 15, height: 15)
            .foregroundStyle(.black)
            .blendMode(.destinationOut)
            .background(theme.primaryLabel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .compositingGroup()
    }
}

struct PlaybackProgress: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(format(elapsed))
            Capsule()
                .fill(theme.subtleFill)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(theme.primaryLabel)
                            .frame(width: proxy.size.width * min(max(elapsed / duration, 0), 1))
                            .animation(.linear(duration: 1), value: elapsed)
                    }
                }
                .frame(height: 6)
            Text("-" + format(duration - elapsed))
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(theme.tertiaryLabel)
    }

    private func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.time(pattern: .minuteSecond))
    }
}

struct TransportButton: View {
    let symbol: String
    var size: CGFloat = 17
    let help: String
    let action: () -> Void
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(theme.primaryLabel)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Module

/// Owns the player and registers the home view, compact slots, and companion surfaces.
@MainActor
final class MediaModule: NookModule {
    // `nonisolated` so the top-level (nonisolated) host setup can reference it. The
    // descriptor is an immutable `Sendable` value, so this is safe outside the actor.
    nonisolated static let moduleDescriptor = NookModuleDescriptor(
        id: "com.opennook.example.companion",
        displayName: "Music",
        icon: "music.note",
        accent: .pink
    )

    let descriptor = MediaModule.moduleDescriptor
    private let player = MediaPlayer()

    /// The companions that come and go while the app runs. The configuration carries the
    /// source; the module changes what is on it.
    private let liveCompanions = NookCompanionSource()
    private var outputObservation: AnyCancellable?

    /// The host calls `onActivate()` only when the user switches *to* a module, not for the
    /// module it launches with, so the clock also starts here.
    init() {
        player.startClock()
        // `@Published` sends the new value before storing it, on the main actor, so it is
        // passed along rather than read back, and a change made in `withAnimation` animates.
        outputObservation = player.$output
            .removeDuplicates()
            .sink { [liveCompanions] output in
                MainActor.assumeIsolated {
                    Self.show(output, on: liveCompanions)
                }
            }
    }

    /// Adds the output chip while the music plays on a speaker, and removes it when it comes
    /// back to this Mac.
    private static func show(_ output: MediaPlayer.Output, on companions: NookCompanionSource) {
        switch output {
            case .thisMac:
                companions.remove(id: "output")
            case .speaker(let name):
                companions.set(
                    NookCompanion(
                        id: "output",
                        anchor: .trailing,
                        spacing: 8,
                        visibility: .compact,
                        style: .faded,
                        size: .small,
                        presence: .pop,
                        accessibilityLabel: "Playing on \(name)"
                    ) {
                        OutputChip(name: name)
                    }
                )
        }
    }

    func makeConfiguration() -> NookConfiguration {
        let player = player
        var configuration = NookConfiguration()
        configuration.setHome { MediaHomeView(player: player) }
        configuration.setCompactLeading { CompactArtwork(player: player) }
        configuration.setCompactTrailing { CompactWaveform(player: player) }
        configuration.expandedWidth = 420
        configuration.topBar.leadingTitle = { _ in "Music" }
        configuration.topBar.leadingIcon = "music.note"
        // Every companion is 40 pt tall around 32 pt controls unless it says otherwise.
        configuration.companionSize = .regular
        configuration.companionSource = liveCompanions

        // The two companion surfaces. Both hang below the nook, so they share one row,
        // centered, in registration order. The round button keeps a wider gap to the pill
        // without dropping any further below the nook.
        configuration.addCompanion(
            id: "sections",
            anchor: .below,
            spacing: 10,
            visibility: .expanded,
            shape: .capsule,
            accessibilityLabel: "Player sections"
        ) {
            MediaSectionsPill(player: player)
        }
        configuration.addCompanion(
            id: "sleep-timer",
            anchor: .below,
            spacing: 10,
            gap: 14,
            visibility: .both,
            shape: .circle,
            accessibilityLabel: "Sleep timer"
        ) {
            SleepTimerButton(player: player)
        }

        // The lock and gear, moved from the top bar to a companion beside the panel. It
        // stays up while Settings is showing, since its gear is the way back.
        configuration.topBar.showsKeepOpenButton = false
        configuration.topBar.showsSettingsButton = false
        configuration.addCompanion(
            id: "chrome-controls",
            anchor: .trailing,
            spacing: 10,
            visibility: .expanded,
            shape: .capsule,
            hidesInSettings: false,
            accessibilityLabel: "Nook controls"
        ) {
            ChromeControls()
        }

        // One opt-in for every scroll view that follows the panel setting: the Up Next
        // and Library lists above, and the framework's Settings screen.
        configuration.scrollEdgeFade = .standard
        return configuration
    }

    func onActivate() {
        player.startClock()
    }

    /// The companions leave the surface with the module; stopping the clock here keeps a
    /// backgrounded player from ticking - the same place ActivityNook stops its timer.
    func onDeactivate() {
        player.stopClock()
    }
}

var host = NookHostConfiguration()
host.register(MediaModule.moduleDescriptor) { _ in MediaModule() }
host.defaultModule = MediaModule.moduleDescriptor.id
host.branding = NookHostBranding(
    hostName: "CompanionNook",
    hostTagline: "Companion surfaces floated beside the nook."
)
// Launch seed: the solid dark chrome a media player usually wears. A Settings change wins.
host.preferenceDefaults = NookPreferenceDefaults(
    appearance: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .solid)
)

NookApp.main(host)
