// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

private struct NookHasKeyboardFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` while the nook's panel has the keyboard, inside compact, expanded, and companion
    /// content; `false` anywhere else. See ``Nook/hasKeyboardFocus``.
    ///
    /// SwiftUI can give a text input focus while the panel does not have the keyboard - when
    /// content first appears, say - and typing then still goes to the app in front. Read this
    /// beside the input's focus state to tell the two apart.
    public var nookHasKeyboardFocus: Bool {
        get { self[NookHasKeyboardFocusKey.self] }
        set { self[NookHasKeyboardFocusKey.self] = newValue }
    }
}
