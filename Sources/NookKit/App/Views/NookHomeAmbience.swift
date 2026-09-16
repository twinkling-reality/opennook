// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// NookKit-level product concept: a host's *home surface* can pick a theme color, and the
/// expanded chrome (top bar + home) paints a soft wash behind it.
///
/// This is the "home screen's chosen color" semantics. It is deliberately kept *out* of the
/// MIT `NookSurface` engine, which only exposes the product-agnostic
/// `NookAmbientColorPreferenceKey` seam. NookKit attaches the meaning here.
extension View {
    /// Publishes the home surface's chosen theme color so the surface backdrop paints a
    /// matching ambient wash behind the full expanded chrome. Pass `nil` for no tint.
    ///
    /// Host home views call this to tie the backdrop to their selected theme:
    /// ```swift
    /// MyHomeView()
    ///     .nookHomeAmbience(selectedTheme.accentColor)
    /// ```
    ///
    /// Under the hood this forwards to `NookSurface`'s generic ambient-color seam.
    public func nookHomeAmbience(_ color: Color?) -> some View {
        nookAmbientColor(color)
    }
}
