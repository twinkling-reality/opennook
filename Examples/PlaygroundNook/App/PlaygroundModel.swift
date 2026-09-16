// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookApp
import PlaygroundNookCore
import SwiftUI
import UniformTypeIdentifiers

/// The playground's state and the one place that applies it to the running nook.
@MainActor
final class PlaygroundModel: ObservableObject {
    /// Everything the controls edit except the appearance preferences, which live in
    /// `AppState`. Every change is saved and applied to the chrome on the next main-actor turn.
    @Published var settings: PlaygroundSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.behavior != oldValue.behavior {
                coordinator?.replaceChromeBehavior(settings.chromeBehavior)
            }
            scheduleApply()
        }
    }

    /// Demo-only state: the rim demo, the scrolling list, the banner message.
    @Published var demo: PlaygroundDemo {
        didSet {
            guard demo != oldValue else { return }
            store.saveDemo(demo)
        }
    }

    /// A message for the controls window to show in an alert, such as why a preset did not open.
    @Published var alertMessage: String?

    /// A short confirmation shown under the export, such as "Copied".
    @Published private(set) var toast: String?

    /// Weak because the coordinator owns this model, through the module host.
    private(set) weak var coordinator: AppCoordinator?

    private let store: PlaygroundStore
    private var isApplyScheduled = false
    private var toastTask: Task<Void, Never>?
    private var controlsWindow: PlaygroundControlsWindowController?

    init(store: PlaygroundStore) {
        self.store = store
        settings = store.loadSettings()
        demo = store.loadDemo()
    }

    /// Called from `onReady`, once the chrome is running.
    func attach(to coordinator: AppCoordinator) {
        self.coordinator = coordinator
        // The configuration was built from the saved settings at launch; the chrome behavior
        // is host-wide, so it is applied separately.
        coordinator.replaceChromeBehavior(settings.chromeBehavior)
        showControls(activating: false)
        if let path = LaunchOptions.presetPath {
            importPreset(from: URL(fileURLWithPath: path))
        }
        if LaunchOptions.expandsNook {
            coordinator.showNook()
        }
    }

    /// `--preset <path>` opens a preset at launch and `--expand` opens the nook, so a preset can
    /// be previewed with one command.
    private enum LaunchOptions {
        static var presetPath: String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--preset"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        static var expandsNook: Bool {
            ProcessInfo.processInfo.arguments.contains("--expand")
        }
    }

    // MARK: - Applying

    /// A slider drag changes the settings many times a second. Saving and applying once per
    /// main-actor turn keeps the chrome and the controls responsive.
    private func scheduleApply() {
        guard !isApplyScheduled else { return }
        isApplyScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isApplyScheduled = false
            self.store.saveSettings(self.settings)
            withAnimation(.snappy(duration: 0.3)) {
                self.coordinator?.reloadActiveConfiguration()
            }
        }
    }

    // MARK: - Appearance

    var appearance: NookAppearancePreferences {
        coordinator?.appState.appearancePreferences ?? .default
    }

    /// Changes the user's appearance preferences the way the built-in Settings screen does: the
    /// framework persists them and restyles the chrome.
    func updateAppearance(_ change: (inout NookAppearancePreferences) -> Void) {
        guard let appState = coordinator?.appState else { return }
        var preferences = appState.appearancePreferences
        change(&preferences)
        appState.replaceAppearancePreferences(preferences)
    }

    // MARK: - The nook

    func expandNook() {
        coordinator?.showNook()
    }

    func collapseNook() {
        coordinator?.hideNook()
    }

    /// Opens the nook on Settings, or back on home when Settings is already showing.
    func toggleNookSettings() {
        guard let coordinator else { return }
        if coordinator.appState.isSettingsView {
            coordinator.showHome()
        } else {
            coordinator.showSettings()
        }
    }

    func setKeepsNookExpanded(_ keepsExpanded: Bool) {
        guard let coordinator, coordinator.appState.keepNookOpen != keepsExpanded else { return }
        coordinator.toggleKeepNookOpen()
        if keepsExpanded {
            coordinator.showNook()
        }
    }

    /// Posts the demo status banner.
    func postStatus() {
        postStatus(demo.statusMessage, severity: NookStatusSeverity(rawValue: demo.statusSeverity) ?? .info)
    }

    /// `showNook()` clears the transient status as it opens the nook, so the banner is posted
    /// after asking it to open.
    func postStatus(_ message: String, severity: NookStatusSeverity) {
        guard let coordinator else { return }
        coordinator.showNook()
        coordinator.appState.showStatus(message, severity: severity)
    }

    func clearStatus() {
        coordinator?.appState.resetTransientStatus()
    }

    // MARK: - Presets

    var preset: PlaygroundPreset {
        PlaygroundPreset(appearance: appearance, settings: settings)
    }

    var swiftSnippet: String {
        PlaygroundSwiftExporter.snippet(for: preset)
    }

    var presetJSON: String {
        (try? PlaygroundPresetCoder.encodeString(preset)) ?? ""
    }

    /// Replaces the settings and the appearance with the preset's. Keep-open is a working aid
    /// rather than part of a look, so it stays as it is.
    func apply(_ preset: PlaygroundPreset) {
        settings = preset.settings.normalized()
        updateAppearance { preferences in
            let keepsOpen = preferences.keepNookOpen
            preferences = preset.appearance
            preferences.keepNookOpen = keepsOpen
        }
    }

    func resetEverything() {
        apply(PlaygroundPreset())
    }

    func copySwift() {
        copy(swiftSnippet, toast: "Copied the Swift snippet")
    }

    func copyJSON() {
        copy(presetJSON, toast: "Copied the preset JSON")
    }

    func pasteJSON() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            alertMessage = "The clipboard has no text to read a preset from."
            return
        }
        do {
            apply(try PlaygroundPresetCoder.decode(text))
            flash("Applied the preset from the clipboard")
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func saveJSON() {
        guard let window = controlsWindow?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "nook-preset.json"
        panel.canCreateDirectories = true
        Task {
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
            do {
                try PlaygroundPresetCoder.encode(preset).write(to: url, options: .atomic)
                flash("Saved \(url.lastPathComponent)")
            } catch {
                alertMessage = "The preset could not be saved: \(error.localizedDescription)"
            }
        }
    }

    func openJSON() {
        guard let window = controlsWindow?.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        Task {
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
            importPreset(from: url)
        }
    }

    private func importPreset(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            apply(try PlaygroundPresetCoder.decode(data))
            flash("Opened \(url.lastPathComponent)")
        } catch let error as PlaygroundPresetError {
            alertMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
        } catch {
            alertMessage = "\(url.lastPathComponent) could not be read: \(error.localizedDescription)"
        }
    }

    private func copy(_ text: String, toast: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        flash(toast)
    }

    private func flash(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Controls window

    /// Shows the controls window. At launch it comes up without taking focus from the app in
    /// front; from the nook's button it activates the playground too.
    func showControls(activating: Bool) {
        guard let coordinator else { return }
        let controller =
            controlsWindow ?? PlaygroundControlsWindowController(model: self, appState: coordinator.appState)
        controlsWindow = controller
        controller.present(activating: activating)
    }
}
