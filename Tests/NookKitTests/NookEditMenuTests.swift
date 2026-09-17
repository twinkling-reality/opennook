// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import XCTest

@testable import NookKit

/// The hidden Edit menu that gives text inputs in the nook their standard shortcuts.
@MainActor
final class NookEditMenuTests: XCTestCase {
    /// An app with no main menu gets one holding the standard editing shortcuts, each sent to
    /// the focused text input rather than a fixed target.
    func testAddsTheStandardShortcutsToAnAppWithoutAMenu() throws {
        let main = try XCTUnwrap(NookEditMenu.mainMenu(adding: nil))
        let edit = try XCTUnwrap(main.items.first?.submenu)
        let shortcuts = edit.items.filter { !$0.isSeparatorItem }.map {
            "\($0.action.map(NSStringFromSelector) ?? "") \($0.keyEquivalentModifierMask.rawValue) \($0.keyEquivalent)"
        }
        let command = NSEvent.ModifierFlags.command.rawValue
        let shiftCommand = NSEvent.ModifierFlags([.command, .shift]).rawValue
        XCTAssertEqual(
            shortcuts,
            [
                "undo: \(command) z", "redo: \(shiftCommand) z", "cut: \(command) x", "copy: \(command) c",
                "paste: \(command) v", "selectAll: \(command) a",
            ]
        )
        XCTAssertTrue(edit.items.allSatisfy { $0.target == nil })
    }

    /// A main menu that already pastes - the host's own Edit menu, at any depth - is left alone.
    func testLeavesAnAppsOwnEditMenuAlone() {
        let main = NSMenu()
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        file.submenu = NSMenu(title: "File")
        main.addItem(file)
        let edit = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Bearbeiten")
        edit.submenu?.addItem(NSMenuItem(title: "Einsetzen", action: Selector(("paste:")), keyEquivalent: "v"))
        main.addItem(edit)

        XCTAssertNil(NookEditMenu.mainMenu(adding: main))
    }

    /// A main menu without editing gains the Edit menu beside what it has, so a host that later
    /// looks for an "Edit" menu (as Feather does) finds this one.
    func testAddsEditBesideAnAppsOtherMenus() {
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "App", action: nil, keyEquivalent: ""))

        let result = NookEditMenu.mainMenu(adding: main)

        XCTAssertTrue(result === main)
        XCTAssertEqual(main.items.map(\.title), ["App", "Edit"])
        XCTAssertEqual(main.items.last?.submenu?.title, "Edit")
    }
}
