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

/// Every row puts its control in a column of one width, so controls share a leading and a
/// trailing edge however long their labels are.
enum RowLayout {
    static let controlWidth: CGFloat = 250
    static let valueWidth: CGFloat = 50
}

extension View {
    /// `help(_:)` for a tooltip that may not exist.
    @ViewBuilder
    func help(ifPresent text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}

// MARK: - Pages

/// A page: its title and symbol, then its cards, in a scrolling column.
struct PlaygroundPageView<Content: View>: View {
    let page: PlaygroundPage
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 16) {
                    Text(page.title)
                        .font(PlaygroundTheme.pageTitle)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    PageBadge(page: page)
                }
                .padding(.top, 6)
                content
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            // Room for the confirmation that floats over the bottom.
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A titled card of rows, with hairlines between them.
struct SectionCard<Content: View, Accessory: View>: View {
    let title: String
    var help: String?
    var isModified = false
    var reset: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: title, help: help, isModified: isModified, reset: reset) {
                accessory
            }
            CardRows { content }
        }
    }
}

extension SectionCard where Accessory == EmptyView {
    init(
        title: String,
        help: String? = nil,
        isModified: Bool = false,
        reset: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, help: help, isModified: isModified, reset: reset, content: content) {
            EmptyView()
        }
    }
}

/// A card for settings most people never need, folded to a single row until opened. The
/// folded row shows a dot when something inside differs from the defaults, so no change goes
/// unseen.
struct CollapsibleCard<Content: View>: View {
    let title: String
    var help: String?
    @Binding var isExpanded: Bool
    var isModified = false
    var reset: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(PlaygroundTheme.body)
                        if isModified && !isExpanded {
                            ModifiedDot()
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(isHovered ? PlaygroundTheme.controlHoverFill : .clear))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .frame(minHeight: 28)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .trackingHover($isHovered)
                .help(isExpanded ? "Hide \(title)" : "Show \(title)")
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                if isExpanded {
                    if let help {
                        InfoBadge(text: help)
                    }
                    if isModified, let reset {
                        CardResetButton(title: title, action: reset)
                    }
                }
            }
            if isExpanded {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        Rectangle()
                            .fill(PlaygroundTheme.hairline)
                            .frame(height: 1)
                        row
                            .frame(minHeight: 28)
                            .padding(.vertical, 7)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .surface()
    }
}

/// A card's title line: the title, an optional tooltip, and its actions.
struct CardTitle<Accessory: View>: View {
    let title: String
    var help: String?
    var isModified = false
    var reset: (() -> Void)?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(PlaygroundTheme.sectionTitle)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let help {
                InfoBadge(text: help)
            }
            Spacer(minLength: 8)
            if isModified, let reset {
                CardResetButton(title: title, action: reset)
            }
            accessory
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 22)
    }
}

/// Rows on a card, with hairlines between them.
struct CardRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { rows in
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Rectangle()
                                .fill(PlaygroundTheme.hairline)
                                .frame(height: 1)
                        }
                        row
                            .frame(minHeight: 28)
                            .padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
                .surface()
            }
        }
    }
}

private struct CardResetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(PillButtonStyle())
        .help("Reset \(title) to the defaults")
    }
}

/// An info glyph whose tooltip carries the explanation a footer would otherwise spell out.
struct InfoBadge: View {
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(.tertiary)
            .help(text)
            .accessibilityLabel(text)
    }
}

/// Marks something changed from its defaults.
struct ModifiedDot: View {
    var body: some View {
        Circle()
            .fill(.tint)
            .frame(width: 6, height: 6)
            .accessibilityLabel("Changed")
    }
}

// MARK: - Rows

/// A label on the leading edge and a control in the fixed column on the trailing edge. A
/// changed value shows a reset button beside the label. `help` is the label's tooltip, which
/// keeps explanations out of sight until someone asks.
struct ControlRow<Control: View>: View {
    let title: String
    var help: String?
    var isModified = false
    @ViewBuilder var control: Control
    var reset: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text(title)
                    .font(PlaygroundTheme.body)
                    .lineLimit(1)
                    .help(ifPresent: help)
                if isModified, let reset {
                    ResetButton(action: reset)
                }
            }
            Spacer(minLength: 0)
            control
                .frame(width: RowLayout.controlWidth, alignment: .trailing)
        }
    }
}

struct ResetButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16)
                .background(
                    Circle().fill(isHovered ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .trackingHover($isHovered)
        .help("Reset to default")
        .accessibilityLabel("Reset to default")
    }
}

/// How a slider row shows its value.
enum ValueFormat {
    case points
    case seconds
    case number
    case percent

    func text(_ value: Double, step: Double) -> String {
        let digits = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return switch self {
            case .points: "\(number) pt"
            case .seconds: "\(number) s"
            case .number: number
            case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let defaultValue: Double
    var format = ValueFormat.points
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help, isModified: abs(value - defaultValue) > 0.0005) {
            HStack(spacing: 10) {
                // Snapping in the binding rather than with `step:` avoids a tick mark per step.
                Slider(value: snapped, in: range)
                    .controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityValue(format.text(value, step: step))
                Text(format.text(value, step: step))
                    .font(PlaygroundTheme.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: RowLayout.valueWidth, alignment: .trailing)
            }
        } reset: {
            value = defaultValue
        }
    }

    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = ($0 / step).rounded() * step }
        )
    }
}

struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

struct SegmentedRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Choice<Value>]
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help) {
            PillPicker(title: title, selection: $selection, choices: choices)
        }
    }
}

struct TextRow: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .playgroundField()
        }
    }
}

/// A theme color that follows the live palette until a color is picked for it.
struct ColorRow: View {
    let title: String
    @Binding var override: PlaygroundColor?
    /// What the chrome shows while the color is not overridden.
    let liveColor: Color
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help, isModified: override != nil) {
            HStack(spacing: 8) {
                if override == nil {
                    Text("Live")
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.tertiary)
                        .help("Follows the palette and accent until you pick a color")
                }
                ColorSwatch(title: title, color: color, supportsOpacity: true)
            }
        } reset: {
            override = nil
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: { override?.color ?? liveColor },
            set: { override = PlaygroundColor($0) }
        )
    }
}

/// A round swatch that opens the system color panel. The panel edits whichever swatch was
/// clicked last.
struct ColorSwatch: View {
    let title: String
    @Binding var color: Color
    var supportsOpacity = false
    @State private var isHovered = false

    var body: some View {
        Button {
            ColorPanelLink.shared.edit(color, supportsOpacity: supportsOpacity) { color = $0 }
        } label: {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(PlaygroundTheme.stroke),
                            lineWidth: 1.5
                        )
                }
                .background(Circle().fill(isHovered ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .trackingHover($isHovered)
        .help("Choose a color")
        .accessibilityLabel(title)
    }
}

/// Connects the shared color panel to one swatch at a time.
@MainActor
private final class ColorPanelLink: NSObject {
    static let shared = ColorPanelLink()

    private var onChange: ((Color) -> Void)?

    func edit(_ color: Color, supportsOpacity: Bool, onChange: @escaping (Color) -> Void) {
        let panel = NSColorPanel.shared
        // Detached first, so setting the starting color is not reported to the previous swatch.
        self.onChange = nil
        panel.showsAlpha = supportsOpacity
        panel.color = NSColor(color)
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        self.onChange = onChange
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))
    }
}

/// Plays a change on the nook.
struct PreviewButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Preview", systemImage: "play.fill")
        }
        .buttonStyle(PillButtonStyle(kind: .primary))
        .help(help)
    }
}
