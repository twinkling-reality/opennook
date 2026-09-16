// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Playground state that only drives the demo content - whether the rim is lit, which status
/// message the banner button posts. It is remembered between launches but is never exported:
/// it is not configuration.
public struct PlaygroundDemo: Codable, Equatable, Sendable {
    public var rimGlowLit = false
    public var rimGlowColor = PlaygroundColor(red: 0.25, green: 0.55, blue: 0.98)
    public var showsScrollDemo = true
    public var statusMessage = "Saved 3 files"
    /// A `NookStatusSeverity` raw value.
    public var statusSeverity = "success"

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        rimGlowLit = try container.decodeIfPresent(Bool.self, forKey: .rimGlowLit) ?? fallback.rimGlowLit
        rimGlowColor =
            try container.decodeIfPresent(PlaygroundColor.self, forKey: .rimGlowColor) ?? fallback.rimGlowColor
        showsScrollDemo =
            try container.decodeIfPresent(Bool.self, forKey: .showsScrollDemo) ?? fallback.showsScrollDemo
        statusMessage = try container.decodeIfPresent(String.self, forKey: .statusMessage) ?? fallback.statusMessage
        statusSeverity =
            try container.decodeIfPresent(String.self, forKey: .statusSeverity) ?? fallback.statusSeverity
    }
}

/// Persists the playground in the module's own `UserDefaults` suite
/// (`NookModuleContext.defaults`), as JSON, so it survives a relaunch.
public struct PlaygroundStore {
    static let settingsKey = "playground.settings"
    static let demoKey = "playground.demo"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The saved settings, or the defaults when nothing readable was saved.
    public func loadSettings() -> PlaygroundSettings {
        load(PlaygroundSettings.self, forKey: Self.settingsKey)?.normalized() ?? .default
    }

    public func saveSettings(_ settings: PlaygroundSettings) {
        save(settings, forKey: Self.settingsKey)
    }

    public func loadDemo() -> PlaygroundDemo {
        load(PlaygroundDemo.self, forKey: Self.demoKey) ?? PlaygroundDemo()
    }

    public func saveDemo(_ demo: PlaygroundDemo) {
        save(demo, forKey: Self.demoKey)
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
