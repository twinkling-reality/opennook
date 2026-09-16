// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import PlaygroundNookCore
import SwiftUI

/// The playground as a module. A module rather than a plain `NookConfiguration`, because
/// `reloadActiveConfiguration()` works by calling `makeConfiguration()` again, and only a
/// module can build a different configuration each time.
@MainActor
final class PlaygroundModule: NookModule {
    // `nonisolated` so the top-level (nonisolated) host setup can reference it. The
    // descriptor is an immutable `Sendable` value, so this is safe outside the actor.
    nonisolated static let moduleDescriptor = NookModuleDescriptor(
        id: "com.opennook.example.playground",
        displayName: "Playground",
        icon: "slider.horizontal.3",
        accent: .purple
    )

    let descriptor = PlaygroundModule.moduleDescriptor
    private let model: PlaygroundModel

    init(context: NookModuleContext) {
        // The module's own defaults suite keeps the playground apart from the framework's
        // preferences and from any other module.
        model = PlaygroundModel(store: PlaygroundStore(defaults: context.defaults))
    }

    /// Runs at launch and on every reload, so each call reads the model's current settings.
    func makeConfiguration() -> NookConfiguration {
        let model = model
        var configuration = model.settings.makeConfiguration(
            home: { PlaygroundHomeView(model: model) },
            companion: { companion in PlaygroundCompanionView(model: model, companion: companion) }
        )
        // The home view lights the rim only while the nook is expanded, so the compact slots
        // light it too, keeping the demo rim on after the nook collapses.
        let leading = configuration.compactLeading
        let trailing = configuration.compactTrailing
        configuration.compactLeading = { AnyView(RimGlowSource(model: model, content: leading())) }
        configuration.compactTrailing = { AnyView(RimGlowSource(model: model, content: trailing())) }
        configuration.onReady = { coordinator in
            model.attach(to: coordinator)
        }
        return configuration
    }
}
