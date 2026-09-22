// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookApp
import NookComponents
import SwiftUI

/// The `NookComponents` file shelf, filled at launch with a few sample files written to a
/// temporary folder. Files dropped on the notch join them.
struct ShelfHome: View {
    let store: ShelfStore
    @Environment(\.nookContentInsets) private var insets

    var body: some View {
        NookShelfView(store: store)
            .padding(.horizontal, 8)
            .padding(.bottom, max(insets.bottom - 4, 0))
    }
}

// MARK: - Companion

/// Shows the shelved files in Finder.
struct ShelfCompanion: View {
    @ObservedObject var store: ShelfStore
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        HStack(spacing: size?.controlSpacing ?? 2) {
            CapsuleButton(symbol: "folder", label: "Show in Finder") {
                let urls = store.items.compactMap { $0.resolveURL() }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
    }
}

// MARK: - Compact

/// The file count beside the notch.
struct CompactShelfCount: View {
    @ObservedObject var store: ShelfStore
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Text("\(store.items.count)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(theme.primaryLabel)
            .frame(minWidth: 24, minHeight: 24)
    }
}
