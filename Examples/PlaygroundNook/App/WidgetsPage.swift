// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import SwiftUI

/// Widgets on a grid in the nook's home: sample widgets at the sizes you pick, on a grid of the
/// columns you pick, in cards or straight on the chrome. A live demo like the activities, so a
/// preset never carries it.
struct WidgetsPage: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        PlaygroundPageView(page: .widgets) {
            SectionCard(title: "Grid") {
                SwitchRow(
                    title: "Show in the nook",
                    isOn: Binding(
                        get: { model.widgetDemo != nil },
                        set: { model.widgetDemo = $0 ? PlaygroundWidgetDemo() : nil }
                    ),
                    help: "Replaces the home's sample content with the widget grid."
                )
                if model.widgetDemo != nil {
                    SegmentedRow(
                        title: "Columns",
                        selection: demo(\.columns),
                        choices: [3, 4, 5].map { Choice($0, "\($0)") }
                    )
                    SegmentedRow(
                        title: "Cards",
                        selection: demo(\.cards),
                        choices: [Choice(true, "Cards"), Choice(false, "Plain")]
                    )
                }
            }
            if model.widgetDemo != nil {
                SectionCard(title: "Sizes") {
                    ForEach(PlaygroundWidgetDemo.Sample.allCases) { sample in
                        SegmentedRow(
                            title: sample.title,
                            selection: Binding(
                                get: { model.widgetDemo?.sizes[sample] ?? sample.sizes[0] },
                                set: { model.widgetDemo?.sizes[sample] = $0 }
                            ),
                            choices: sample.sizes.map { Choice($0, $0.name) }
                        )
                    }
                }
            }
            SectionCard(title: "Boards") {
                Text(
                    "A board is a module whose home shows the widgets of every loaded module, which "
                        + "people arrange in its Settings. Register one with "
                        + "NookHostConfiguration.registerBoard(_:); MultiNook opens on one."
                )
                .font(PlaygroundTheme.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func demo<Value>(_ keyPath: WritableKeyPath<PlaygroundWidgetDemo, Value>) -> Binding<Value> {
        Binding(
            get: { (model.widgetDemo ?? PlaygroundWidgetDemo())[keyPath: keyPath] },
            set: { model.widgetDemo?[keyPath: keyPath] = $0 }
        )
    }
}

/// The widget grid shown in the nook's home while the Widgets page turns it on.
struct PlaygroundWidgetDemo: Equatable {
    enum Sample: String, CaseIterable, Identifiable {
        case clock
        case weather
        case calendar
        case battery

        var id: String { rawValue }

        var title: String {
            switch self {
                case .clock: "Clock"
                case .weather: "Weather"
                case .calendar: "Calendar"
                case .battery: "Battery"
            }
        }

        var sizes: [NookWidgetSize] {
            switch self {
                case .clock: [.small, .medium]
                case .weather: [.medium, .small]
                case .calendar: [.medium, .large, .wide]
                case .battery: [.small, .medium]
            }
        }
    }

    var columns = 4
    var cards = true
    var sizes: [Sample: NookWidgetSize] = [:]

    var widgets: [NookWidget] {
        Sample.allCases.map { sample in
            NookWidget(id: sample.rawValue, title: sample.title, sizes: sample.sizes) { size in
                PlaygroundSampleWidget(sample: sample, size: size)
            }
        }
    }

    var sizesByID: [String: NookWidgetSize] {
        Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.rawValue, $0.value) })
    }
}

/// A sample widget: a glyph, a value, and a caption when there is room.
private struct PlaygroundSampleWidget: View {
    let sample: PlaygroundWidgetDemo.Sample
    let size: NookWidgetSize
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: size.rows > 1 ? 30 : 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if size != .small {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryLabel)
                    .lineLimit(size.rows > 1 ? 3 : 1)
            }
        }
    }

    private var symbol: String {
        switch sample {
            case .clock: "clock"
            case .weather: "cloud.sun"
            case .calendar: "calendar"
            case .battery: "battery.75percent"
        }
    }

    private var value: String {
        switch sample {
            case .clock: "9:41"
            case .weather: "18\u{00B0}"
            case .calendar: "10:30"
            case .battery: "76%"
        }
    }

    private var caption: String {
        switch sample {
            case .clock: "Tuesday, October 6"
            case .weather: "Partly cloudy, high of 21\u{00B0}"
            case .calendar: "Design review with the team, then lunch at 12:30"
            case .battery: "About 5 hours left"
        }
    }
}
