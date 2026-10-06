// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookApp
import NookComponents
import SwiftUI

/// The showcase's scenes. One runs per launch, picked with `--scene <id>`.
enum ShowcaseScene: String, CaseIterable {
    case player
    case agenda
    case timer
    case progress
    case shelf
    case hud
    case compact

    var title: String {
        switch self {
            case .player, .compact: "Now Playing"
            case .agenda: "Today"
            case .timer: "Focus"
            case .progress: "Builds"
            case .shelf: "Shelf"
            case .hud: "Sound"
        }
    }

    var icon: String {
        switch self {
            case .player, .compact: "music.note"
            case .agenda: "calendar"
            case .timer: "timer"
            case .progress: "shippingbox"
            case .shelf: "tray.full"
            case .hud: "speaker.wave.2"
        }
    }

    /// The width of the expanded content column, sized to each scene's layout.
    var expandedWidth: CGFloat {
        switch self {
            case .player, .compact: 640
            case .agenda: 560
            case .timer: 440
            case .progress: 500
            case .shelf: 548
            case .hud: 380
        }
    }
}

/// `--scene <id>` picks the scene (default `player`). `--expand` opens the nook at launch and
/// `--expand-after <seconds>` opens it after a delay, so a recording can start on the pill.
/// `--keep-open` holds the nook open once it opens, without saving the keep-open preference.
enum LaunchOptions {
    static var scene: ShowcaseScene {
        value(after: "--scene").flatMap(ShowcaseScene.init(rawValue:)) ?? .player
    }

    /// When to open the nook, or `nil` to leave it collapsed. `--keep-open` on its own opens it.
    static var expandDelay: Duration? {
        if let seconds = value(after: "--expand-after").flatMap(Double.init) {
            return .milliseconds(Int(seconds * 1000))
        }
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--expand") || arguments.contains("--keep-open") ? .milliseconds(500) : nil
    }

    static var keepsNookOpen: Bool {
        ProcessInfo.processInfo.arguments.contains("--keep-open")
    }

    /// `--peek`: the player shows its peek shortly after launch and holds it, for a recording.
    /// In the `compact` scene, the song activity's peek.
    static var peeks: Bool {
        ProcessInfo.processInfo.arguments.contains("--peek")
    }

    /// `--open-activity`: in the `compact` scene, the nook opens onto the song activity's
    /// expanded view shortly after launch and stays, for a recording.
    static var opensActivity: Bool {
        ProcessInfo.processInfo.arguments.contains("--open-activity")
    }

    /// `--alert-after <seconds>`: when `--peek` or `--open-activity` alerts the song activity in
    /// the `compact` scene. 0.9 s by default.
    static var alertDelay: Duration {
        .milliseconds(Int((value(after: "--alert-after").flatMap(Double.init) ?? 0.9) * 1000))
    }

    /// `--theme <file.json>`: a theme file for the chrome, followed as it changes.
    static var themePath: String? {
        value(after: "--theme")
    }

    /// `--scene board`: the player, agenda, and timer scenes run side by side as resident
    /// modules, and a board shows a widget from each.
    static var showsBoard: Bool {
        value(after: "--scene") == "board"
    }

    /// The pin that holds the nook open for `--keep-open`, kept for the life of the process.
    @MainActor private static var keepOpenPin: NookPresentationPinHandle?

    /// Opens the nook after `--expand`, `--expand-after`, or `--keep-open`, and holds it open for
    /// `--keep-open` with a pin rather than the keep-open preference, so a recording leaves no
    /// setting behind.
    @MainActor
    static func openIfAsked(_ coordinator: AppCoordinator) {
        guard let delay = expandDelay else { return }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            coordinator.showNook()
            if keepsNookOpen {
                keepOpenPin = coordinator.moduleHost.registry.presentationPinning.pin(reason: "showcase-keep-open")
            }
        }
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

/// One module that builds the configuration for the scene it was launched with. Each scene's
/// models are created only when that scene runs, so the HUD's CoreAudio listeners and the
/// shelf's store stay out of the other scenes.
@MainActor
final class ShowcaseModule: NookModule {
    // `nonisolated` so the top-level (nonisolated) host setup can reference it. The
    // descriptor is an immutable `Sendable` value, so this is safe outside the actor.
    nonisolated static let moduleDescriptor = NookModuleDescriptor(
        id: "com.opennook.example.showcase",
        displayName: "Showcase",
        icon: "sparkles"
    )

    /// The scene's own descriptor in a board run (`descriptor(for:)`), this one otherwise.
    let descriptor: NookModuleDescriptor
    private let scene: ShowcaseScene
    private let context: NookModuleContext

    private lazy var player = PlayerModel()
    private lazy var timer = FocusTimerModel()
    private lazy var run = BuildRunModel()
    private lazy var activities = NookActivityQueue()
    private lazy var shelf = ShelfStore(persistenceKey: "showcase.shelf.items", defaults: context.defaults)
    private lazy var volume = SystemVolumeObserver()
    private lazy var outputLabel = OutputDevice.currentLabel()

    private var volumeObservation: AnyCancellable?
    private var trackObservation: AnyCancellable?
    private var trackPeek: NookSurfaceToken?
    private var trackPeekGeneration = 0
    private var hudToken: NookSurfaceToken?
    private var hudGeneration = 0

    init(scene: ShowcaseScene, context: NookModuleContext) {
        self.scene = scene
        self.context = context
        self.descriptor = context.descriptor
        if scene == .shelf {
            // A fresh shelf each launch: last run's files are gone from the temporary folder.
            shelf.clear()
            shelf.accept(SampleFiles.make())
        }
        // The host calls `onActivate()` only when the user switches *to* a module, not for
        // the module it launches with, so the clocks also start here.
        onActivate()
        if scene == .compact { startCompactActivities() }
    }

    /// The `compact` scene's two live things as live activities: the focus session first,
    /// then the song, so the song (started last) holds the pill and the session sits in the
    /// capsule beside it. Their views read the models, so they tick in place.
    private func startCompactActivities() {
        let activities = context.services.resolve(NookLiveActivitiesKey.self)
        let timer = timer
        let player = player
        activities.start(
            NookLiveActivity(id: "focus", accessibilityLabel: "Focus session") {
                CompactGlyph(symbol: "flame.fill", tint: FocusPalette.warm)
            } compactTrailing: {
                CompactTimer(timer: timer, lightsRim: true)
            } minimal: {
                FocusMinimal(timer: timer)
            }
        )
        var song = NookLiveActivity(id: "song", accessibilityLabel: "Now playing") {
            CompactCover(player: player)
        } compactTrailing: {
            CompactEqualizer(player: player)
        } minimal: {
            CoverArt(design: player.track.cover, size: 16, cornerRadius: 4)
        }
        song.setPeek { PlayerPeek(player: player) }
        song.setExpanded { PlayerHome(player: player) }
        activities.start(song)

        // For a recording: hold the song's peek, or open onto it, shortly after launch.
        let alert: NookLiveActivity.Alert? =
            LaunchOptions.peeks ? .peek(.seconds(60)) : LaunchOptions.opensActivity ? .expand(.seconds(60)) : nil
        if let alert {
            Task { @MainActor in
                try? await Task.sleep(for: LaunchOptions.alertDelay)
                activities.alert("song", alert)
            }
        }
    }

    func makeConfiguration() -> NookConfiguration {
        var configuration = NookConfiguration()
        let scene = scene
        configuration.expandedWidth = scene.expandedWidth
        configuration.topBar.leadingTitle = { _ in scene.title }
        configuration.topBar.leadingIcon = scene.icon
        configuration.topBar.showsKeepOpenButton = false
        configuration.companionSize = .regular
        configuration.scrollEdgeFade = .standard

        switch scene {
            case .player, .compact:
                configurePlayer(&configuration)
            case .agenda:
                configuration.setHome { AgendaHome() }
                configuration.setCompactLeading { CompactGlyph(symbol: "calendar", tint: AgendaPalette.today) }
                configuration.setCompactTrailing { CompactNextEvent() }
            case .timer:
                let timer = timer
                configuration.setHome { TimerHome(timer: timer) }
                configuration.setCompactLeading { CompactGlyph(symbol: "flame.fill", tint: FocusPalette.warm) }
                configuration.setCompactTrailing { CompactTimer(timer: timer) }
                configuration.addCompanion(id: "presets", spacing: 10, accessibilityLabel: "Session length") {
                    TimerPresetsCompanion(timer: timer)
                }
            case .progress:
                let run = run
                let activities = activities
                configuration.setHome {
                    NookActivityHost(queue: activities) { ProgressHome(run: run) }
                }
                configuration.setCompactLeading { CompactGlyph(symbol: "shippingbox.fill", tint: BuildPalette.running) }
                configuration.setCompactTrailing { CompactBuildStatus(run: run) }
                configuration.addCompanion(id: "build-actions", spacing: 10, accessibilityLabel: "Build actions") {
                    BuildCompanion(run: run)
                }
            case .shelf:
                let shelf = shelf
                configuration.setHome { ShelfHome(store: shelf) }
                configuration.setCompactLeading { CompactGlyph(symbol: "tray.full.fill") }
                configuration.setCompactTrailing { CompactShelfCount(store: shelf) }
                configuration.onFileDrop = { urls in shelf.accept(urls) }
                configuration.addCompanion(id: "shelf-actions", spacing: 10, accessibilityLabel: "Shelf actions") {
                    ShelfCompanion(store: shelf)
                }
            case .hud:
                let volume = volume
                let label = outputLabel
                configuration.setHome { VolumeHUD(volume: volume, deviceName: label) }
                configuration.setPeek { VolumePeek(volume: volume) }
                configuration.setCompactLeading { CompactGlyph(symbol: "hifispeaker.fill") }
                configuration.setCompactTrailing { NookVolumeIndicator(observer: volume) }
        }

        addWidgets(to: &configuration)
        configuration.onReady = { [weak self] coordinator in
            self?.ready(coordinator)
        }
        return configuration
    }

    /// The scene's widget, for a board (`--scene board`). Scenes without one add nothing.
    private func addWidgets(to configuration: inout NookConfiguration) {
        switch scene {
            case .player:
                let player = player
                configuration.addWidget(
                    NookWidget(id: "now-playing", title: "Now playing", symbol: "music.note", sizes: [.medium, .large])
                    {
                        size in
                        NowPlayingWidget(player: player, size: size)
                    }
                )
            case .agenda:
                configuration.addWidget(
                    NookWidget(id: "next", title: "Next event", symbol: "calendar", sizes: [.medium]) { _ in
                        NextEventWidget()
                    }
                )
            case .timer:
                let timer = timer
                configuration.addWidget(
                    NookWidget(id: "focus", title: "Focus", symbol: "timer", sizes: [.small, .medium]) { _ in
                        FocusWidget(timer: timer)
                    }
                )
            case .progress, .shelf, .hud, .compact:
                break
        }
    }

    /// A scene's own module, resident and loaded at launch, for a board run.
    nonisolated static func descriptor(for scene: ShowcaseScene) -> NookModuleDescriptor {
        var descriptor = NookModuleDescriptor(
            id: "com.opennook.example.showcase.\(scene.rawValue)",
            displayName: scene.title,
            icon: scene.icon,
            backgroundPolicy: .stayResident
        )
        descriptor.loadsAtLaunch = true
        return descriptor
    }

    private func configurePlayer(_ configuration: inout NookConfiguration) {
        let player = player
        configuration.setHome { PlayerHome(player: player) }
        configuration.setCompactLeading { CompactCover(player: player) }
        if scene == .compact {
            // The song and the focus session run as live activities that hold the pill (see
            // `startCompactActivities()`); these slots show only once both have ended.
            configuration.setCompactTrailing { CompactEqualizer(player: player) }
        } else {
            configuration.setCompactTrailing { CompactEqualizer(player: player) }
            configuration.setPeek { PlayerPeek(player: player) }
            configuration.addCompanion(id: "player-actions", spacing: 10, accessibilityLabel: "Playback") {
                PlayerCompanion(player: player)
            }
        }
    }

    // MARK: - Lifecycle

    func onActivate() {
        switch scene {
            case .player: player.start()
            case .compact:
                player.start()
                timer.start()
            case .timer: timer.start()
            case .progress: run.start()
            case .agenda, .shelf, .hud: break
        }
    }

    /// A module that owns a `NookActivityQueue` quiesces it before it is switched away, so a
    /// card on screen is drained and its surface claim released.
    func prepareForSwitchAway() async {
        if scene == .progress {
            await activities.quiesce()
        }
    }

    func onDeactivate() {
        switch scene {
            case .player: player.stop()
            case .compact:
                player.stop()
                timer.stop()
            case .timer: timer.stop()
            case .progress: run.stop()
            case .agenda, .shelf, .hud: break
        }
    }

    private func ready(_ coordinator: AppCoordinator) {
        switch scene {
            case .progress:
                activities.bind(to: coordinator, moduleID: descriptor.id)
                let activities = activities
                run.onFinish = {
                    activities.enqueue(
                        NookActivity(
                            coalescingKey: "build",
                            title: "Build succeeded",
                            subtitle: "\(SampleBuild.project) \(SampleBuild.version) is on the release channel",
                            systemImage: "checkmark.seal.fill",
                            tint: BuildPalette.done,
                            dwell: .seconds(3)
                        )
                    )
                }
            case .player:
                // A new song peeks under the notch for a moment, unless the person is using the
                // nook. Another change while it shows moves its end rather than peeking again.
                trackObservation = player.$index
                    .dropFirst()
                    .removeDuplicates()
                    .sink { [weak self] _ in
                        MainActor.assumeIsolated { self?.peekTrackChange(on: coordinator) }
                    }
                if LaunchOptions.peeks {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(800))
                        self?.peekTrackChange(on: coordinator, holding: true)
                    }
                }
            case .hud:
                if LaunchOptions.peeks {
                    // For a recording: hold the volume peek without touching the volume.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(800))
                        guard let self else { return }
                        let claim = NookSurfaceClaim(
                            moduleID: self.descriptor.id,
                            priority: .ambient,
                            maxDuration: nil,
                            presentation: .peek
                        )
                        self.hudToken = await coordinator.beginTransientPresentation(claim)
                    }
                }
                // `@Published` sends the new value before storing it, so a change is passed
                // along rather than read back.
                volumeObservation = volume.$volume
                    .dropFirst()
                    .removeDuplicates()
                    .sink { [weak self] _ in
                        MainActor.assumeIsolated { self?.showHUD(on: coordinator) }
                    }
            default:
                break
        }

        // Only the module the nook opens on: in a board run the others load in the background.
        if descriptor.id == coordinator.activeModuleID {
            LaunchOptions.openIfAsked(coordinator)
        }
    }

    /// Shows the song in the pill's peek for a few seconds. Each change moves the end, so a
    /// quick run of skips shows one peek. `holding` keeps it up until the person opens the
    /// nook, for `--peek`.
    private func peekTrackChange(on coordinator: AppCoordinator, holding: Bool = false) {
        trackPeekGeneration += 1
        let generation = trackPeekGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<2 {
                if self.trackPeek == nil {
                    let claim = NookSurfaceClaim(
                        moduleID: self.descriptor.id,
                        priority: .ambient,
                        maxDuration: holding ? nil : .seconds(10),
                        presentation: .peek
                    )
                    // A claim denied because another change's claim got there first leaves
                    // that one in place.
                    if let token = await coordinator.beginTransientPresentation(claim) { self.trackPeek = token }
                }
                guard let token = self.trackPeek, !holding else { return }
                if await coordinator.endTransientPresentation(token, after: .milliseconds(2600)) { break }
                // The claim already ended (the person opened the nook, say): peek afresh once.
                self.trackPeek = nil
            }
            try? await Task.sleep(for: .milliseconds(2700))
            // No later change moved the end, so the claim is over.
            if generation == self.trackPeekGeneration { self.trackPeek = nil }
        }
    }

    /// Grows the pill into the volume peek while the volume is changing, and shrinks it a
    /// moment after the last change: each change moves the claim's scheduled end. A change made
    /// while the nook is open just updates the HUD in place.
    private func showHUD(on coordinator: AppCoordinator) {
        hudGeneration += 1
        let generation = hudGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.hudToken == nil {
                let claim = NookSurfaceClaim(
                    moduleID: self.descriptor.id,
                    priority: .ambient,
                    maxDuration: .seconds(10),
                    presentation: .peek
                )
                if let token = await coordinator.beginTransientPresentation(claim) { self.hudToken = token }
            }
            guard let token = self.hudToken else { return }
            guard await coordinator.endTransientPresentation(token, after: .milliseconds(1600)) else {
                self.hudToken = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(1700))
            // No later change moved the end, so the claim is over.
            if generation == self.hudGeneration { self.hudToken = nil }
        }
    }
}
