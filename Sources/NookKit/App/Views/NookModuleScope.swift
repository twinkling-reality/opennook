// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// Gives a view the services of the module that supplied it. The chrome around a view belongs
/// to the module on screen, but a live activity or a widget from another module still reads its
/// own `\.appServices` and `\.nookLiveActivities` inside it, and matches its shared elements
/// (`nookSharedElement(_:style:)`) within its own module.
struct NookModuleScope: ViewModifier {
    let moduleID: String
    let services: AppServices

    func body(content: Content) -> some View {
        content
            .environment(\.appServices, services)
            .environment(\.nookLiveActivities, services.resolve(NookLiveActivitiesKey.self))
            .environment(\.nookSharedElementScope, moduleID)
    }
}

extension ModuleHost {
    /// The service bag of the module `id`: its own while it is loaded, otherwise the displayed
    /// module's, which is what the chrome around the view already has.
    func services(forModule id: String) -> AppServices {
        if id == activeModuleID { return activeServices }
        guard registry.isLoaded(id), let services = registry.context(for: id)?.services else {
            return displayedServices
        }
        return services
    }

    /// `content` in the scope of the module `id`, for a view the surface shows on that
    /// module's behalf.
    func scoped(
        _ content: @escaping @Sendable @MainActor () -> AnyView,
        toModule id: String
    ) -> @Sendable @MainActor () -> AnyView {
        let services = services(forModule: id)
        return { AnyView(content().modifier(NookModuleScope(moduleID: id, services: services))) }
    }
}
