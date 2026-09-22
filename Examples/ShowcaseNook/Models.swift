// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

/// A repeating main-run-loop timer that a model starts when its scene is showing and stops when it
/// is switched away.
@MainActor
final class Clock {
    private var timer: Timer?
    private let interval: TimeInterval
    private let tick: @Sendable @MainActor () -> Void

    init(interval: TimeInterval, tick: @escaping @Sendable @MainActor () -> Void) {
        self.interval = interval
        self.tick = tick
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [tick] _ in
            // Timer fires on the main run loop; hop to the main actor to advance the model.
            MainActor.assumeIsolated { tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Player

@MainActor
final class PlayerModel: ObservableObject {
    enum Output: Equatable {
        case thisMac
        case speaker(String)

        var symbol: String {
            switch self {
                case .thisMac: "laptopcomputer"
                case .speaker: "hifispeaker.fill"
            }
        }

        var name: String {
            switch self {
                case .thisMac: "This Mac"
                case .speaker(let name): name
            }
        }
    }

    let tracks = SampleMusic.tracks

    @Published private(set) var index = 0
    @Published private(set) var elapsed: TimeInterval = 81
    @Published private(set) var isPlaying = true
    @Published var isLiked = true
    @Published var isShuffled = false
    @Published var repeats = false
    @Published var output = Output.speaker("Living Room")

    private lazy var clock = Clock(interval: 1) { [weak self] in self?.tick() }

    var track: Track { tracks[index] }

    /// The tracks after the current one, wrapping around.
    var upNext: [Track] {
        Array(tracks[(index + 1)...] + tracks[..<index])
    }

    func start() { clock.start() }
    func stop() { clock.stop() }

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
    }

    func toggleOutput() {
        output = output == .thisMac ? .speaker("Living Room") : .thisMac
    }

    private func tick() {
        guard isPlaying else { return }
        elapsed += 1
        if elapsed >= track.duration { skip(by: 1) }
    }
}

// MARK: - Focus timer

@MainActor
final class FocusTimerModel: ObservableObject {
    static let presets: [Int] = [15, 25, 50]

    @Published private(set) var length: TimeInterval = 25 * 60
    @Published private(set) var remaining: TimeInterval = 18 * 60 + 42
    @Published private(set) var isRunning = true
    @Published private(set) var session = 2
    let sessions = 4

    private lazy var clock = Clock(interval: 1) { [weak self] in self?.tick() }

    /// How much of the session has passed, from 0 to 1.
    var progress: Double {
        guard length > 0 else { return 0 }
        return min(max(1 - remaining / length, 0), 1)
    }

    var presetMinutes: Int { Int(length / 60) }

    func start() { clock.start() }
    func stop() { clock.stop() }

    func toggle() {
        if remaining <= 0 { remaining = length }
        isRunning.toggle()
    }

    func addFiveMinutes() {
        remaining += 5 * 60
        length = max(length, remaining)
    }

    func reset() {
        remaining = length
        isRunning = false
    }

    func select(minutes: Int) {
        length = TimeInterval(minutes * 60)
        remaining = length
        isRunning = true
    }

    private func tick() {
        guard isRunning else { return }
        remaining = max(remaining - 1, 0)
        if remaining == 0 {
            isRunning = false
            session = session % sessions + 1
        }
    }
}

// MARK: - Build run

@MainActor
final class BuildRunModel: ObservableObject {
    enum StepState: Equatable {
        case done
        case running(Double)
        case waiting
    }

    let steps = SampleBuild.steps
    /// Shown durations are the showcase's own, scaled up so the list reads like a real build.
    static let displayScale = 9.0

    @Published private(set) var current = 2
    @Published private(set) var stepElapsed = 1.2
    @Published private(set) var isFinished = false

    /// Called once each time the run finishes.
    var onFinish: (@MainActor () -> Void)?

    private static let interval = 0.1
    private lazy var clock = Clock(interval: Self.interval) { [weak self] in self?.tick() }
    private var restartCountdown = 0.0

    var isRunning: Bool { !isFinished }

    func state(of step: BuildStep) -> StepState {
        if isFinished || step.id < current { return .done }
        if step.id == current { return .running(min(stepElapsed / step.duration, 1)) }
        return .waiting
    }

    /// The whole run's progress, from 0 to 1, weighted by step length.
    var progress: Double {
        let total = steps.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return 0 }
        if isFinished { return 1 }
        let done = steps.prefix(current).reduce(0) { $0 + $1.duration }
        return min((done + stepElapsed) / total, 1)
    }

    /// Seconds the run has taken so far, on the scaled clock.
    var elapsed: Double {
        let done = steps.prefix(isFinished ? steps.count : current).reduce(0) { $0 + $1.duration }
        return (done + (isFinished ? 0 : stepElapsed)) * Self.displayScale
    }

    /// Seconds still to go, on the scaled clock.
    var remaining: Double {
        let total = steps.reduce(0) { $0 + $1.duration } * Self.displayScale
        return max(total - elapsed, 0)
    }

    func start() { clock.start() }
    func stop() { clock.stop() }

    func restart() {
        current = 0
        stepElapsed = 0
        isFinished = false
    }

    private func tick() {
        if isFinished {
            restartCountdown -= Self.interval
            if restartCountdown <= 0 { restart() }
            return
        }
        stepElapsed += Self.interval
        guard stepElapsed >= steps[current].duration else { return }
        if current + 1 < steps.count {
            current += 1
            stepElapsed = 0
        } else {
            isFinished = true
            restartCountdown = 9
            onFinish?()
        }
    }
}

// MARK: - Formatting

enum Format {
    /// `m:ss`, or `h:mm:ss` from an hour up.
    static func clock(_ seconds: TimeInterval) -> String {
        let value = Int(max(seconds, 0).rounded(.down))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
        }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    /// `18:42`, always two-digit minutes, for the focus timer.
    static func timer(_ seconds: TimeInterval) -> String {
        let value = Int(max(seconds, 0).rounded(.up))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// `09:30` from minutes after midnight.
    static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// `1h 48m`, `25m`.
    static func span(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
