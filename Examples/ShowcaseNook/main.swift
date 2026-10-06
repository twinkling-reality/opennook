// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// ShowcaseNook - finished-looking notch scenes, built only from OpenNook's public API.
//
// Where the other examples each teach one seam, this one puts several together the way a
// shipping notch app would, one scene per launch:
//   - `player`: now playing with original cover art drawn in code, and the queue beside it.
//     The panel takes the cover's color (`nookAmbientColor`); a companion below says where it
//     plays. A new song peeks under the notch for a moment (`setPeek` and a peek claim).
//   - `agenda`: this month beside today's schedule.
//   - `timer`: a focus countdown on a tick dial, session lengths in a companion, the rim lit
//     while it runs (`nookRimGlow`).
//   - `progress`: a release build step by step. When it finishes, a `NookActivityQueue` card
//     (NookComponents) says so once the nook is free.
//   - `shelf`: the NookComponents file shelf holding sample files written to a temporary folder.
//   - `hud`: a volume HUD over `SystemVolumeObserver` (NookComponents): when the volume
//     changes, the pill grows into a volume peek and shrinks a moment after the last change (a
//     peek claim with a scheduled end), with `NookVolumeIndicator` beside the notch.
//   - `compact`: two live activities sharing the collapsed pill: the song holds it, and the
//     focus session waits in a capsule beside it (`NookLiveActivity`).
//   - `board`: the player, agenda, and timer run side by side as resident modules, and a board
//     shows a widget from each (`NookWidget`, `NookBoardConfiguration`).
//
// Every song, artist, event, and build here is invented.
//
// Run with `swift run ShowcaseNook --scene <id>`. `--expand` opens the nook at launch,
// `--expand-after <seconds>` opens it later, and `--keep-open` holds it open.
// `--peek` shows the player's (or, in `compact`, the song activity's) peek shortly after launch
// and holds it, and `--open-activity` opens `compact` onto the song activity, for a recording;
// `--alert-after <seconds>` sets when.
// `--theme <file.json>` paints the chrome with a theme file and follows it as it is saved;
// Examples/Themes holds a few to start from.

import Foundation
import NookApp

var host = NookHostConfiguration()
if LaunchOptions.showsBoard {
    for scene in [ShowcaseScene.player, .agenda, .timer] {
        host.register(ShowcaseModule.descriptor(for: scene)) { context in
            ShowcaseModule(scene: scene, context: context)
        }
    }
    var board = NookBoardConfiguration(
        id: "com.opennook.example.showcase.board",
        displayName: "Today",
        icon: "square.grid.2x2",
        width: 520,
        defaultLayout: [
            NookWidgetPlacement(
                moduleID: "com.opennook.example.showcase.player",
                widgetID: "now-playing",
                size: .large
            ),
            NookWidgetPlacement(moduleID: "com.opennook.example.showcase.agenda", widgetID: "next"),
            NookWidgetPlacement(moduleID: "com.opennook.example.showcase.timer", widgetID: "focus", size: .medium),
        ]
    )
    board.customize = { configuration in
        configuration.topBar.showsKeepOpenButton = false
        configuration.onReady = { coordinator in LaunchOptions.openIfAsked(coordinator) }
    }
    host.registerBoard(board)
    host.defaultModule = board.id
} else {
    host.register(ShowcaseModule.moduleDescriptor) { context in
        ShowcaseModule(scene: LaunchOptions.scene, context: context)
    }
    host.defaultModule = ShowcaseModule.moduleDescriptor.id
}
host.branding = NookHostBranding(
    hostName: "ShowcaseNook",
    hostTagline: "Finished-looking notch scenes built on OpenNook."
)
// Launch seed: the solid dark chrome that fuses with the notch. A Settings change wins.
host.preferenceDefaults = NookPreferenceDefaults(
    appearance: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .solid)
)
if let themePath = LaunchOptions.themePath {
    host.chromeThemeSource = .watching(fileAt: URL(fileURLWithPath: themePath))
}

NookApp.main(host)
