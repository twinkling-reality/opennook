// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// PlaygroundNook - change the nook's look and behavior while it runs, then export the result.
//
// A controls window beside the live nook edits one `PlaygroundSettings` value. Each change
// rebuilds the module's `NookConfiguration` and applies it to the running chrome with
// `AppCoordinator.reloadActiveConfiguration()`. Hover behavior goes through
// `replaceChromeBehavior(_:)`, and the palette, surface, layout, and accent preferences go
// through `AppState`, as the built-in Settings screen does. The Presets section exports the
// result as Swift that sets only what differs from the defaults, and saves and opens JSON
// presets.
//
// The playground is bigger than the other examples, so it spans several files. The settings
// model and the Swift and JSON exporters live in the `PlaygroundNookCore` target, which
// `PlaygroundNookTests` covers.
//
// Run with `swift run PlaygroundNook`. `--preset <file.json>` or `--sample <id>` opens a look
// at launch; `--expand` and `--keep-open` open the nook; `--hide-controls` skips the window.

import NookApp

var host = NookHostConfiguration()
host.register(PlaygroundModule.moduleDescriptor) { context in
    PlaygroundModule(context: context)
}
host.branding = NookHostBranding(
    hostName: "PlaygroundNook",
    hostTagline: "Change the nook live, then export the configuration."
)

NookApp.main(host)
