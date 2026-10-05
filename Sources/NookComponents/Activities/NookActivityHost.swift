// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import SwiftUI

/// A home-view wrapper that shows the activity currently being presented by a
/// ``NookActivityQueue``, falling back to the host's own content when the queue is idle.
///
/// Register it as the home view so queued activities can take over the expanded surface:
///
/// ```swift
/// configuration.setHome {
///     NookActivityHost(queue: queue) { MyNormalHomeView() }
/// }
/// ```
public struct NookActivityHost<Content: View>: View {
    @ObservedObject private var queue: NookActivityQueue
    private let content: () -> Content

    /// The card's takeover curve, ``NookChromeMotion/activityCard``.
    @Environment(\.nookChromeMotion) private var motion

    public init(queue: NookActivityQueue, @ViewBuilder content: @escaping () -> Content) {
        self.queue = queue
        self.content = content
    }

    public var body: some View {
        ZStack {
            if let activity = queue.current {
                NookActivityCard(activity: activity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                content()
            }
        }
        .animation(motion.activityCard, value: queue.current?.id)
    }
}

/// The default activity card - icon, title, subtitle. Reads `\.nookResolvedTheme` from
/// the environment so it tracks the configured chrome palette.
public struct NookActivityCard: View {
    private let activity: NookActivity
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics

    public init(activity: NookActivity) {
        self.activity = activity
    }

    public var body: some View {
        HStack(spacing: metrics.activityCardSpacing) {
            if let systemImage = activity.systemImage {
                Image(systemName: systemImage)
                    .font(typography.activityIcon)
                    .foregroundStyle(activity.tint)
                    .frame(width: metrics.activityIconWidth)
            }
            VStack(alignment: .leading, spacing: metrics.activityTextSpacing) {
                Text(activity.title)
                    .font(typography.activityTitle)
                    .foregroundStyle(theme.primaryLabel)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(typography.activitySubtitle)
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, metrics.activityCardVerticalPadding)
        .padding(.horizontal, metrics.activityCardHorizontalPadding)
    }
}
