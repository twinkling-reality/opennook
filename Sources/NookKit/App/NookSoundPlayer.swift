// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit

/// Plays a theme's sounds. The seam ``AppCoordinator`` plays through, so tests can record what
/// would play instead of making a noise.
@MainActor
protocol NookSoundPlaying: AnyObject {
    /// Loads `sounds` so their first play starts without a disk read.
    func preload(_ sounds: [NookSoundSpec])

    /// Plays `sound` at its ``NookSoundSpec/volume`` (full volume when `nil`), over any sound
    /// already playing, the same one included.
    func play(_ sound: NookSoundSpec)
}

/// Plays sounds with `NSSound`.
///
/// Each source is loaded once and kept. `NSSound` plays one instance at a time, so a sound
/// asked for again while it is still playing plays from a copy, which shares the loaded data;
/// finished copies are reused, and at most ``maximumVoices`` play at once per source.
@MainActor
final class NookSystemSoundPlayer: NookSoundPlaying {
    /// The most copies of one sound that play at once. A request beyond it is dropped: a burst
    /// that fast is one sound to the ear.
    static let maximumVoices = 4

    /// Every loaded instance of each source; the first is the one loaded from the source.
    private var voices: [NookSoundSpec.Source: [NSSound]] = [:]

    /// Sources that failed to load, so a missing file is looked for once, not on every play.
    private var missing: Set<NookSoundSpec.Source> = []

    /// `true` inside a test process, where nothing is ever played. Tests replace the player
    /// with a recording one; this keeps a test that forgets to from making a noise.
    private let isSilenced: Bool

    init(isSilenced: Bool = NSClassFromString("XCTestCase") != nil) {
        self.isSilenced = isSilenced
    }

    func preload(_ sounds: [NookSoundSpec]) {
        for sound in sounds { _ = loaded(sound.source) }
    }

    func play(_ sound: NookSoundSpec) {
        guard !isSilenced, let voice = idleVoice(for: sound.source) else { return }
        voice.volume = Float(min(max(sound.volume ?? 1, 0), 1))
        voice.play()
    }

    /// The instance loaded from `source`, loading it the first time; `nil` when it cannot be
    /// found or read.
    func loaded(_ source: NookSoundSpec.Source) -> NSSound? {
        if let first = voices[source]?.first { return first }
        guard !missing.contains(source), let sound = Self.load(source) else {
            missing.insert(source)
            return nil
        }
        voices[source] = [sound]
        return sound
    }

    /// An instance of `source` that is not playing, copying the loaded one when every instance
    /// is busy and there is room for another.
    private func idleVoice(for source: NookSoundSpec.Source) -> NSSound? {
        guard let original = loaded(source) else { return nil }
        let instances = voices[source] ?? [original]
        if let idle = instances.first(where: { !$0.isPlaying }) { return idle }
        guard instances.count < Self.maximumVoices, let copy = original.copy() as? NSSound else { return nil }
        voices[source] = instances + [copy]
        return copy
    }

    /// Reads `source`: a system sound by name, a main-bundle resource by file name, or a file.
    static func load(_ source: NookSoundSpec.Source) -> NSSound? {
        switch source {
            case .system(let name):
                // `NSSound(named:)` hands back one shared instance per name; copy it, so this
                // player's volume changes never reach anyone else's use of the sound.
                return NSSound(named: name)?.copy() as? NSSound
            case .resource(let name):
                let file = name as NSString
                let ext = file.pathExtension
                guard
                    let url = Bundle.main.url(
                        forResource: file.deletingPathExtension,
                        withExtension: ext.isEmpty ? nil : ext
                    )
                else { return nil }
                return NSSound(contentsOf: url, byReference: true)
            case .file(let url):
                return NSSound(contentsOf: url, byReference: true)
        }
    }
}
