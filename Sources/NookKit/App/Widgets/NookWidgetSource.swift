// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import SwiftUI

/// Widgets a module can add, remove, and replace while the nook runs.
///
/// A widget's content can change on its own by observing the module's state. A source is for
/// changing which widgets exist: one per open project, a widget that appears while a call is
/// live. Set it on the configuration once (``NookConfiguration/widgetSource``) and change it
/// whenever you like; boards follow at once.
///
/// ```swift
/// let widgets = NookWidgetSource()
/// configuration.widgetSource = widgets
///
/// // Later, from anywhere on the main actor:
/// widgets.set(NookWidget(id: "call", title: "Call") { _ in CallWidget() })
/// widgets.remove(id: "call")
/// ```
///
/// A board keeps a removed widget's place in its saved layout, so it comes back where it was.
@MainActor
public final class NookWidgetSource: ObservableObject {
    /// The widgets, in order.
    @Published public var widgets: [NookWidget]

    public init(_ widgets: [NookWidget] = []) {
        self.widgets = widgets
    }

    /// Replaces the widget with `widget`'s id where it stands, or appends it when there is none.
    public func set(_ widget: NookWidget) {
        if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
            widgets[index] = widget
        } else {
            widgets.append(widget)
        }
    }

    /// Removes the widget with `id`. Nothing happens when there is none.
    public func remove(id: String) {
        widgets.removeAll { $0.id == id }
    }

    /// Removes every widget.
    public func removeAll() {
        widgets.removeAll()
    }
}
