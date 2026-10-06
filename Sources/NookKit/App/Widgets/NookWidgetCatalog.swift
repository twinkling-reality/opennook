// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import SwiftUI

/// The widgets of every loaded module, for boards: what each module's configuration offers
/// (``NookConfiguration/widgets`` and ``NookConfiguration/widgetSource``), recorded when the
/// host builds the configuration and dropped when the module unloads.
///
/// One per host, owned by ``NookModuleRegistry``.
@MainActor
final class NookWidgetCatalog: ObservableObject {
    /// One module's widget, with the services its views read.
    struct Entry: Identifiable {
        let moduleID: String
        let widget: NookWidget
        let services: AppServices

        /// "module id/widget id", the key boards save layouts by.
        var id: String { NookWidgetPlacement.key(moduleID: moduleID, widgetID: widget.id) }
    }

    /// Every loaded module's widgets: modules in registration order, each module's widgets in
    /// its own order, the configuration's before its source's. A widget whose id its module
    /// already listed is left out.
    @Published private(set) var entries: [Entry] = []

    /// Module ids in registration order.
    private let moduleOrder: [String]
    private var modules: [String: (widgets: [NookWidget], services: AppServices)] = [:]
    private var sources: [String: (source: NookWidgetSource, widgets: [NookWidget])] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    nonisolated init(moduleOrder: [String]) {
        self.moduleOrder = moduleOrder
    }

    /// Records `configuration`'s widgets for the module `moduleID`, replacing what it had, and
    /// follows its widget source from now on.
    func record(_ configuration: NookConfiguration, moduleID: String, services: AppServices) {
        modules[moduleID] = (configuration.widgets, services)
        if let source = configuration.widgetSource {
            if sources[moduleID]?.source !== source {
                sources[moduleID] = (source, source.widgets)
                subscriptions[moduleID] = source.$widgets
                    .dropFirst()
                    .sink { [weak self] widgets in
                        MainActor.assumeIsolated {
                            guard let self, self.sources[moduleID]?.source === source else { return }
                            self.sources[moduleID]?.widgets = widgets
                            self.rebuild()
                        }
                    }
            }
        } else {
            sources[moduleID] = nil
            subscriptions[moduleID] = nil
        }
        rebuild()
    }

    /// Drops the module `moduleID`'s widgets, when it unloads.
    func remove(moduleID: String) {
        guard modules[moduleID] != nil || sources[moduleID] != nil else { return }
        modules[moduleID] = nil
        sources[moduleID] = nil
        subscriptions[moduleID] = nil
        rebuild()
    }

    /// The module `moduleID`'s widgets, in order.
    func widgets(of moduleID: String) -> [NookWidget] {
        entries.filter { $0.moduleID == moduleID }.map(\.widget)
    }

    private func rebuild() {
        var result: [Entry] = []
        let known = Set(moduleOrder)
        let order = moduleOrder + modules.keys.filter { !known.contains($0) }.sorted()
        for moduleID in order {
            guard let module = modules[moduleID] else { continue }
            var seen = Set<String>()
            for widget in module.widgets + (sources[moduleID]?.widgets ?? []) where seen.insert(widget.id).inserted {
                result.append(Entry(moduleID: moduleID, widget: widget, services: module.services))
            }
        }
        entries = result
    }
}

/// Resolves the host's widget catalog from a module's services, for the board module.
struct NookWidgetCatalogKey: ServiceKey {
    static let defaultValue = NookWidgetCatalog(moduleOrder: [])
}
