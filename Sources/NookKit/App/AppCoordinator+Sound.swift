// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookSurface

/// Plays the displayed module's chrome theme sounds when the chrome's events happen.
///
/// | Sound | Plays when |
/// | --- | --- |
/// | `sound.open` | the nook expands, from the compact pill or from hidden |
/// | `sound.close` | the nook leaves the expanded state |
/// | `sound.hover` | the pointer reaches the nook, the chrome or a companion |
/// | `sound.feedback` | a peripheral cue plays: ``AppCoordinator/playFeedback(_:duration:repeats:)`` or the launch shimmer |
/// | `sound.alert` | a status of `.error` or `.warning` severity is posted, or an `.urgent` surface claim is granted |
/// | `sound.finish` | a status of `.success` severity is posted |
/// | `sound.peek` | only when the host plays it with ``AppCoordinator/playSound(_:)`` |
///
/// Nothing plays while the person has turned sounds off
/// (``NookAppearancePreferences/soundsEnabled``), and a theme with no sounds, the default,
/// plays nothing and loads nothing.
extension AppCoordinator {
    /// Plays the displayed theme's sound for `id`, at the theme's volume, unless the theme has
    /// no sound for it or the person turned sounds off. For the events the framework cannot see
    /// itself: a task the host finished, a peek the host drew.
    ///
    /// ```swift
    /// coordinator.playSound(.finish)
    /// ```
    ///
    /// Host content can play one through ``NookChromeActions/playSound`` instead.
    public func playSound(_ id: NookSoundID) {
        guard let sound = moduleHost.displayedConfiguration.effectiveThemeTokens.sound(id),
            appState.appearancePreferences.soundsEnabled
        else { return }
        soundPlayer.play(sound)
    }

    /// Loads the displayed theme's sounds ahead of their first play. Does nothing for a theme
    /// without sounds, so the player is never made.
    func preloadThemeSounds() {
        let tokens = moduleHost.displayedConfiguration.effectiveThemeTokens
        guard tokens.hasSounds else { return }
        soundPlayer.preload(NookSoundID.allEvents.compactMap { tokens.sound($0) })
    }

    /// Follows the surface and the status channel for the events that play a sound. The sinks
    /// run synchronously, inside the change, so a sound starts with what it marks.
    func bindSounds() {
        let initialState = surface.state
        surface.statePublisher
            .removeDuplicates()
            .scan((previous: initialState, current: initialState)) { pair, state in
                (previous: pair.current, current: state)
            }
            .sink { [weak self] change in
                if change.current == .expanded, change.previous != .expanded {
                    self?.playSound(.open)
                } else if change.previous == .expanded, change.current != .expanded {
                    self?.playSound(.close)
                }
            }
            .store(in: &cancellables)

        surface.isHoveringPublisher
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.playSound(.hover) }
            .store(in: &cancellables)

        appState.$status
            .dropFirst()  // the current value, published on subscribe
            .compactMap { $0?.severity.sound }
            .sink { [weak self] id in self?.playSound(id) }
            .store(in: &cancellables)
    }
}

extension NookStatusSeverity {
    /// The sound a status of this severity plays: `sound.alert` for an error or a warning,
    /// `sound.finish` for a success, none for information.
    var sound: NookSoundID? {
        switch self {
            case .error, .warning: .alert
            case .success: .finish
            case .info: nil
        }
    }
}
