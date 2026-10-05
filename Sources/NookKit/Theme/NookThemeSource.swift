// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import Foundation

/// A chrome theme that can change while the nook runs: replaced in code, or reloaded from a
/// theme file whenever the file is saved.
///
/// Set one on ``NookConfiguration/chromeThemeSource`` (or the host's
/// ``NookHostConfiguration/chromeThemeSource``) and the chrome follows it: each new theme is
/// applied the way ``AppCoordinator/reloadActiveConfiguration()`` applies a configuration, with
/// no relaunch.
///
/// ```swift
/// NookApp.main {
///     var configuration = NookConfiguration()
///     configuration.setHome { MyHomeView() }
///     configuration.chromeThemeSource = .watching(fileAt: themeURL)
///     return configuration
/// }
/// ```
///
/// Watching is opt-in and cheap: it observes the file's folder for changes, so an editor's
/// save-by-replace is seen too, reads the file only after a change settles, and does no work
/// while nothing changes. A file that fails to load leaves the last good theme in place and
/// reports why in ``loadError``.
@MainActor
public final class NookThemeSource: ObservableObject {
    /// The current theme.
    @Published public private(set) var theme: NookTheme {
        didSet { changes.send(theme) }
    }

    /// What the last load did not use as written. Empty for a theme set in code.
    @Published public private(set) var issues: [NookThemeIssue] = []

    /// Why the last load failed, or `nil` when it succeeded. The theme is the last good one.
    @Published public private(set) var loadError: String?

    /// The file this source follows, or `nil` for one changed only in code.
    public let fileURL: URL?

    /// Sends each new theme after it is set - unlike `$theme`, which sends before - so a
    /// subscriber reading ``theme`` sees the new one.
    let changes = PassthroughSubject<NookTheme, Never>()

    private var folderWatcher: NookPathWatcher?
    private var fileWatcher: NookPathWatcher?
    private var pendingLoad: Task<Void, Never>?
    private var lastData: Data?
    private let debounce: Duration

    /// A source holding `theme`, changed with ``replace(_:)``.
    public init(_ theme: NookTheme = .standard) {
        self.theme = theme.validated().theme
        self.fileURL = nil
        self.debounce = .zero
    }

    private init(fileURL: URL, debounce: Duration) {
        self.theme = .standard
        self.fileURL = fileURL
        self.debounce = debounce
        load()
        folderWatcher = NookPathWatcher(path: fileURL.deletingLastPathComponent().path) { [weak self] in
            MainActor.assumeIsolated { self?.fileMayHaveChanged() }
        }
        watchFile()
    }

    /// Watches the file itself, for an editor that writes it in place. Opened again after
    /// every change, since a save by replacement leaves the old watch on a deleted file.
    private func watchFile() {
        guard let fileURL else { return }
        fileWatcher = NookPathWatcher(path: fileURL.path) { [weak self] in
            MainActor.assumeIsolated { self?.fileMayHaveChanged() }
        }
    }

    /// A source that loads the theme file at `url` now and again each time it changes.
    ///
    /// Until the file loads, the theme is ``NookTheme/standard``. Changes are applied
    /// `debounce` after the last write, so a burst of writes loads once.
    public static func watching(fileAt url: URL, debounce: Duration = .milliseconds(150)) -> NookThemeSource {
        NookThemeSource(fileURL: url, debounce: debounce)
    }

    /// Replaces the theme. Its numbers are brought into range, as a loaded theme's are.
    public func replace(_ theme: NookTheme) {
        let validated = theme.validated()
        issues = validated.issues
        loadError = nil
        if validated.theme != self.theme {
            self.theme = validated.theme
        }
    }

    /// Reads the file again now, whether or not it changed.
    public func reload() {
        lastData = nil
        load()
    }

    private func fileMayHaveChanged() {
        pendingLoad?.cancel()
        let debounce = debounce
        pendingLoad = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.watchFile()
            self?.load()
        }
    }

    private func load() {
        guard let fileURL else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            loadError = "The theme file could not be read: \(error.localizedDescription)"
            return
        }
        guard data != lastData else { return }
        lastData = data
        do {
            let result = try NookThemeCoder.decode(data)
            issues = result.issues
            loadError = nil
            if result.theme != theme {
                theme = result.theme
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

/// Calls `onChange` on the main queue whenever the file or folder at `path` is written,
/// extended, renamed, or deleted - for a folder, whenever an entry in it is added, removed, or
/// renamed, which catches an editor that saves by renaming a new file over the old one. Does
/// nothing when `path` does not exist.
final class NookPathWatcher {
    private let source: DispatchSourceFileSystemObject?

    init(path: String, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
