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
//     plays.
//   - `agenda`: this month beside today's schedule.
//   - `timer`: a focus countdown on a tick dial, session lengths in a companion, the rim lit
//     while it runs (`nookRimGlow`).
//   - `progress`: a release build step by step. When it finishes, a `NookActivityQueue` card
//     (NookComponents) says so once the nook is free.
//   - `shelf`: the NookComponents file shelf holding sample files written to a temporary folder.
//   - `hud`: a volume HUD over `SystemVolumeObserver` (NookComponents) that takes the surface
//     for a moment when the volume changes, with `NookVolumeIndicator` beside the notch.
//   - `compact`: the collapsed pill carrying the song on one side and a focus session on the
//     other.
//
// Every song, artist, event, and build here is invented.
//
// Run with `swift run ShowcaseNook --scene <id>`. `--expand` opens the nook at launch,
// `--expand-after <seconds>` opens it later, and `--keep-open` holds it open.

import NookApp

var host = NookHostConfiguration()
host.register(ShowcaseModule.moduleDescriptor) { context in
    ShowcaseModule(scene: LaunchOptions.scene, context: context)
}
host.defaultModule = ShowcaseModule.moduleDescriptor.id
host.branding = NookHostBranding(
    hostName: "ShowcaseNook",
    hostTagline: "Finished-looking notch scenes built on OpenNook."
)
// Launch seed: the solid dark chrome that fuses with the notch. A Settings change wins.
host.preferenceDefaults = NookPreferenceDefaults(
    appearance: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .solid)
)

NookApp.main(host)
