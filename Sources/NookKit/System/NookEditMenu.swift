// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit

/// The standard editing shortcuts for text inputs in the nook: Command-X, C, V, A, Z, and
/// Shift-Command-Z.
///
/// A Mac text field gets those shortcuts from the app's Edit menu. A notch app runs as an
/// accessory, shows no menu bar, and often has no main menu at all, so without one the shortcuts
/// do nothing. `AppCoordinator.start()` installs this menu when the app has none of its own
/// (see ``NookKeyboardBehavior/installsEditMenu``); the menu is never shown, only its key
/// equivalents are used. Its items have no target, so each action goes to whichever text input
/// has focus.
///
/// A host that builds its own main menu keeps it: the menu is added only when no item in the
/// app's main menu already pastes.
@MainActor
public enum NookEditMenu {
    /// Adds the Edit menu to the app's main menu unless that menu already has one. Returns
    /// `true` when it added the menu.
    @discardableResult
    public static func installIfNeeded(in application: NSApplication = .shared) -> Bool {
        guard let menu = mainMenu(adding: application.mainMenu) else { return false }
        application.mainMenu = menu
        return true
    }

    /// The main menu with an Edit menu added, or `nil` when `existing` already handles paste.
    static func mainMenu(adding existing: NSMenu?) -> NSMenu? {
        if let existing, handlesPaste(existing) { return nil }
        let main = existing ?? NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = makeEditMenu()
        main.addItem(editItem)
        return main
    }

    /// Undo, Redo, Cut, Copy, Paste, and Select All with their standard shortcuts.
    static func makeEditMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", "undo:", "z"))
        edit.addItem(item("Redo", "redo:", "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", "cut:", "x"))
        edit.addItem(item("Copy", "copy:", "c"))
        edit.addItem(item("Paste", "paste:", "v"))
        edit.addItem(item("Select All", "selectAll:", "a"))
        return edit
    }

    private static func handlesPaste(_ menu: NSMenu) -> Bool {
        menu.items.contains { item in
            item.action == Selector(("paste:")) || item.submenu.map(handlesPaste) == true
        }
    }

    private static func item(
        _ title: String,
        _ action: String,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
