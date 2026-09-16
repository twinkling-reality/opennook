// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookApp
import SwiftUI

/// The playground's controls live in an ordinary resizable window rather than in the nook:
/// the nook changes shape as you edit it, collapses when the pointer leaves, and is too small
/// for text fields and color pickers. A window beside it stays put while you watch the result.
///
/// While the window is open the playground is a regular app, with a Dock icon and a menu bar,
/// so it can be reached with Command-Tab and its text fields get the standard editing
/// shortcuts. Closing the window returns it to the menu-bar-only accessory app every nook is.
@MainActor
final class PlaygroundControlsWindowController: NSWindowController, NSWindowDelegate {
    init(model: PlaygroundModel, appState: AppState) {
        let hostingController = NSHostingController(
            rootView: PlaygroundControlsView(model: model, appState: appState)
        )
        // Lets the SwiftUI toolbar and inspector become the window's own.
        hostingController.sceneBridgingOptions = [.toolbars]
        // Otherwise the window takes the forms' ideal height, which can be taller than the screen.
        hostingController.sizingOptions = []
        // The window takes its content size from this frame when the controller is installed.
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 1040, height: 700)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "OpenNook Playground"
        window.toolbarStyle = .unified
        // The nook shows on every space, including beside a full-screen app, so the window that
        // edits it comes to whichever space it is opened from.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        // Restores the frame from the last run, when there is one, and saves it from now on.
        window.setFrameUsingName(Self.frameName)
        window.setFrameAutosaveName(Self.frameName)
        super.init(window: window)
        window.delegate = self
    }

    private static let frameName = "PlaygroundNook.Controls"

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present(activating: Bool) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.mainMenu = Self.makeMainMenu()
        }
        guard let window else { return }
        if activating {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            // Shown without activating, so launching the playground from a terminal does not
            // take the keyboard away from it. A click on the window activates the app.
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About PlaygroundNook",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PlaygroundNook", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit PlaygroundNook",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        mainMenu.addItem(submenu: appMenu, title: "PlaygroundNook")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenu: editMenu, title: "Edit")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}

extension NSMenu {
    fileprivate func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
