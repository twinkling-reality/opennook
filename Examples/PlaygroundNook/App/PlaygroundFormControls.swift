// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import PlaygroundNookCore
import SwiftUI

extension PlaygroundColor {
    /// The color as the color picker produced it, in sRGB.
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: resolved.redComponent,
            green: resolved.greenComponent,
            blue: resolved.blueComponent,
            opacity: resolved.alphaComponent
        )
    }
}

/// A slider for one number, with its value and a reset button once it has left its default.
struct NumberRow: View {
    /// One width for every slider, so rows line up whatever their label.
    static let sliderWidth: CGFloat = 190

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let defaultValue: Double
    var unit = "pt"

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                // Snapping in the binding rather than with `step:` avoids a tick mark per step.
                Slider(value: snapped, in: range)
                    .frame(width: Self.sliderWidth)
                    .accessibilityLabel(title)
                    .accessibilityValue(formatted)
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
                ResetButton(isVisible: isChanged) { value = defaultValue }
            }
        } label: {
            Text(title)
        }
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = ($0 / step).rounded() * step }
        )
    }

    private var isChanged: Bool {
        abs(value - defaultValue) > 0.0005
    }

    private var formatted: String {
        let digits = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// Puts a changed value back to its default. Present but invisible otherwise, so rows keep
/// their alignment.
struct ResetButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .help("Reset to the default")
        .accessibilityLabel("Reset to the default")
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
    }
}

/// A theme color that either follows the live palette or is overridden with a picked color.
struct ColorOverrideRow: View {
    let title: String
    @Binding var override: PlaygroundColor?
    /// What the chrome shows while the color is not overridden.
    let liveColor: Color

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(override == nil ? "Live" : "Custom")
                    .foregroundStyle(.secondary)
                Toggle("Override \(title)", isOn: isOverriding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                ColorPicker(title, selection: color, supportsOpacity: true)
                    .labelsHidden()
                    .disabled(override == nil)
            }
        } label: {
            Text(title)
        }
    }

    private var isOverriding: Binding<Bool> {
        Binding(
            get: { override != nil },
            set: { override = $0 ? PlaygroundColor(liveColor) : nil }
        )
    }

    private var color: Binding<Color> {
        Binding(
            get: { override?.color ?? liveColor },
            set: { override = PlaygroundColor($0) }
        )
    }
}

/// A section footer that explains the section and offers to reset it.
struct SectionFooter: View {
    let text: String
    var isResettable = false
    var reset: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if isResettable {
                Button("Reset Section", action: reset)
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
    }
}
