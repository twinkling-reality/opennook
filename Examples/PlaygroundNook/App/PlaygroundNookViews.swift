// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookApp
import PlaygroundNookCore
import SwiftUI

// MARK: - Home

/// The expanded home view. It is plain host content styled from the chrome environment, so it
/// shows what the theme, the insets, and the scroll edge fade do to a real view.
struct PlaygroundHomeView: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        if model.settings.topBar.notchAccessories {
            content
                .nookNotchAccessories {
                    HeaderTitle()
                } trailing: {
                    ControlsButton(model: model)
                }
        } else {
            content
        }
    }

    private var content: some View {
        HomeContent(model: model, showsHeader: !model.settings.topBar.notchAccessories)
    }
}

private struct HomeContent: View {
    @ObservedObject var model: PlaygroundModel
    let showsHeader: Bool
    @Environment(\.nookContentInsets) private var insets
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                HStack(spacing: 8) {
                    HeaderTitle()
                    Spacer(minLength: 8)
                    ControlsButton(model: model)
                }
            }
            if model.demo.showsScrollDemo {
                TagStrip()
                AgendaList()
            } else {
                PaletteSpecimen()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // A fixed height keeps the panel from resizing as the demo content changes.
        .frame(height: showsHeader ? 196 : 162, alignment: .top)
        .padding(.bottom, insets.bottom)
        .nookRimGlow(model.rimColor(whileWorking: theme.accent))
    }
}

/// The playground's mark and name, small enough to sit beside the notch. Where the band beside
/// a narrow panel's notch has no room for the name, only the mark shows.
private struct HeaderTitle: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                mark
                Text("Playground")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryLabel)
                    .lineLimit(1)
                    .fixedSize()
            }
            mark
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playground")
    }

    private var mark: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.accent.gradient)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

/// Opens the controls window. It drops its label where there is no room for it.
private struct ControlsButton: View {
    @ObservedObject var model: PlaygroundModel
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Button {
            model.showControls(activating: true)
        } label: {
            ViewThatFits(in: .horizontal) {
                pill(Label("Controls", systemImage: "slider.horizontal.below.rectangle").labelStyle(.titleAndIcon))
                pill(Label("Controls", systemImage: "slider.horizontal.below.rectangle").labelStyle(.iconOnly))
            }
        }
        .buttonStyle(.plain)
        .help("Show the playground's controls window")
        .accessibilityLabel("Controls")
    }

    private func pill(_ label: some View) -> some View {
        label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.primaryLabel)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(theme.subtleFill, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.subtleStroke) }
            .contentShape(Capsule())
    }
}

/// A horizontal row that overflows, to show the fade on the leading and trailing edges.
private struct TagStrip: View {
    @Environment(\.nookResolvedTheme) private var theme

    private let tags = [
        "Design", "Build", "Review", "Ship", "Focus", "Inbox", "Music", "Travel", "Reading", "Fitness", "Photos",
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.subtleFill, in: Capsule())
                }
            }
        }
        .nookScrollEdgeFade(axes: .horizontal)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A vertical list that overflows, to show the fade on the top and bottom edges.
private struct AgendaList: View {
    @Environment(\.nookResolvedTheme) private var theme

    private struct Item: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
        let time: String
    }

    private let items = [
        Item(id: 0, symbol: "paintbrush.pointed", title: "Design review", detail: "Nook chrome, round 3", time: "9:30"),
        Item(id: 1, symbol: "hammer", title: "Release build", detail: "OpenNook 0.5", time: "10:15"),
        Item(id: 2, symbol: "person.2", title: "Pairing", detail: "Companion surfaces", time: "11:00"),
        Item(id: 3, symbol: "fork.knife", title: "Lunch", detail: "Somewhere sunny", time: "12:30"),
        Item(id: 4, symbol: "doc.text", title: "Write the guide", detail: "Playground page", time: "14:00"),
        Item(id: 5, symbol: "checkmark.seal", title: "Ship it", detail: "Tag and publish", time: "16:45"),
        Item(id: 6, symbol: "figure.walk", title: "Walk", detail: "Around the block", time: "18:00"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.primaryLabel)
                            Text(item.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.tertiaryLabel)
                        }
                        Spacer(minLength: 8)
                        Text(item.time)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(theme.secondaryLabel)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .nookScrollEdgeFade(axes: .vertical)
    }
}

/// The palette's roles side by side, shown in place of the scrolling demo.
private struct PaletteSpecimen: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                swatch("Primary", theme.primaryLabel)
                swatch("Secondary", theme.secondaryLabel)
                swatch("Tertiary", theme.tertiaryLabel)
                swatch("Accent", theme.accent)
            }
            Text("The quick brown fox jumps over the lazy dog.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.primaryLabel)
            Text("Every color here comes from the resolved theme, so it follows the Theme page.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryLabel)
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(height: 34)
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .padding(6)
        .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Wraps chrome content so it lights the rim while the demo asks for it.
struct RimGlowSource<Content: View>: View {
    @ObservedObject var model: PlaygroundModel
    @Environment(\.nookResolvedTheme) private var theme
    let content: Content

    var body: some View {
        content.nookRimGlow(model.rimColor(whileWorking: theme.accent))
    }
}

extension PlaygroundDemo {
    /// The color the demo content lights the rim with, or `nil` while the rim is off.
    var litRimColor: Color? {
        rimGlowLit ? rimGlowColor.color : nil
    }
}

extension PlaygroundModel {
    /// What the rim shows: the assistant working, if it is, and otherwise whatever the demo asks for.
    ///
    /// A request lights the nook itself rather than only the composer, so the thing being changed is
    /// what says something is happening, and it stays visible when the composer is closed.
    func rimColor(whileWorking working: Color) -> Color? {
        assistantIsBusy ? working : demo.litRimColor
    }
}

// MARK: - Companions

/// A companion's content: its items in a row or a column, spaced by the companion's size.
struct PlaygroundCompanionView: View {
    @ObservedObject var model: PlaygroundModel
    let companion: PlaygroundSettings.Companion
    @Environment(\.nookCompanionSize) private var size

    var body: some View {
        let spacing = size?.controlSpacing ?? 2
        let layout =
            companion.resolvedLayout == .column
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(Array(companion.items.enumerated()), id: \.offset) { _, item in
                PlaygroundCompanionItemView(model: model, item: item)
            }
        }
        // An empty companion has nothing to show, so it stays out of the way until it holds
        // something.
        .nookCompanionHidden(companion.items.isEmpty)
    }
}

/// One item: a glyph button, a label, or the framework's lock or gear.
private struct PlaygroundCompanionItemView: View {
    @ObservedObject var model: PlaygroundModel
    let item: PlaygroundSettings.Item
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeActions) private var chromeActions

    var body: some View {
        switch item.type {
            case .keepOpen:
                NookKeepOpenButton()
            case .settings:
                NookSettingsButton()
            case .label:
                label
            case .button:
                Button(item.displayTitle, systemImage: symbol) { perform(item.action) }
                    .buttonStyle(style)
                    .help(item.displayTitle)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if let symbol = item.displaySymbol {
                Image(systemName: Self.shown(symbol))
                    .foregroundStyle(item.tint?.color ?? theme.accent)
            }
            if let title = item.title {
                Text(title)
                    .foregroundStyle(theme.primaryLabel)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    /// The rim toggle shows whether the rim is lit, like the Effects page's switch.
    private var isLit: Bool {
        item.action == .rimGlow && model.demo.rimGlowLit
    }

    private var symbol: String {
        let symbol = item.displaySymbol ?? item.action.defaultSymbol
        guard isLit, NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: nil) != nil else {
            return Self.shown(symbol)
        }
        return symbol + ".fill"
    }

    private var style: NookGlyphButtonStyle {
        let fill: NookGlyphButtonStyle.Fill =
            switch item.fill {
                case .none: .none
                case .subtle: .subtle
                case .color: .color(item.fillColor?.color ?? theme.accent)
                case .chrome: .chromeBackdrop
            }
        return NookGlyphButtonStyle(
            size: item.size == .surface ? .surface : .control,
            foreground: isLit ? model.demo.rimGlowColor.color : item.tint?.color,
            fill: fill,
            fade: item.fade.map { NookStandardCompanionStyle.Fade(start: 1, end: $0) }
        )
    }

    private func perform(_ action: PlaygroundSettings.Item.Action) {
        switch action {
            case .none:
                break
            case .status:
                model.postStatus("\(item.displayTitle) pressed", severity: .info)
            case .rimGlow:
                model.demo.rimGlowLit.toggle()
            case .keepOpen:
                chromeActions.toggleKeepOpen()
            case .settings:
                chromeActions.toggleSettings()
            case .collapse:
                chromeActions.collapse()
        }
    }

    /// `symbol`, or a question mark when no SF Symbol has that name, so a typo shows as one.
    static func shown(_ symbol: String) -> String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "questionmark.circle" : symbol
    }
}
