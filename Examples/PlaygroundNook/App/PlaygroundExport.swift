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

// MARK: - Presets page

struct PresetsPage: View {
    @ObservedObject var model: PlaygroundModel
    @State private var isConfirmingReset = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        PlaygroundPageView(page: .presets) {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "Starting Points", help: "Applying one replaces every setting. You can undo it.") {
                    EmptyView()
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PlaygroundPreset.samples) { sample in
                        PresetTile(sample: sample) {
                            model.apply(sample.preset, announcing: "Applied \(sample.name)")
                        }
                    }
                }
            }

            SectionCard(title: "Share") {
                ControlRow(
                    title: "Swift",
                    help: "What differs from the defaults, as a single-module NookConfiguration."
                ) {
                    Button {
                        model.copySwift()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                }
                ControlRow(
                    title: "Preset",
                    help: "The settings and appearance as JSON. Open a file at launch with "
                        + "swift run PlaygroundNook --preset <file>."
                ) {
                    HStack(spacing: 8) {
                        Button {
                            model.copyJSON()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(action: model.saveJSON) {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
                ControlRow(title: "Import", help: "Apply a preset from the clipboard or a file. You can undo it.") {
                    HStack(spacing: 8) {
                        Button(action: model.pasteJSON) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        Button(action: model.openJSON) {
                            Label("Open", systemImage: "folder")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            SectionCard(title: "Reset") {
                ControlRow(title: "Everything", help: "Every setting and appearance preference back to its default.") {
                    Button {
                        isConfirmingReset = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PillButtonStyle(kind: .destructive))
                }
            }
        }
        .confirmationDialog("Reset everything to the defaults?", isPresented: $isConfirmingReset) {
            Button("Reset Everything", role: .destructive, action: model.resetEverything)
        } message: {
            Text("You can undo it right after.")
        }
    }
}

/// A built-in preset as a tile that applies it.
private struct PresetTile: View {
    let sample: PlaygroundPreset.Sample
    let apply: () -> Void

    var body: some View {
        Button(action: apply) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(PlaygroundTheme.controlFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sample.name)
                        .font(PlaygroundTheme.body)
                    Text(sample.summary)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowButtonStyle())
        .surface()
        .help("Apply \(sample.name)")
        .accessibilityLabel("Apply \(sample.name)")
        .accessibilityHint(sample.summary)
    }

    private var symbol: String {
        switch sample.id {
            case "media": "music.note"
            case "glass": "drop"
            case "glance": "rectangle.compress.vertical"
            default: "circle.dashed"
        }
    }
}

// MARK: - Code panel

/// The live export in a floating card beside the page: the Swift snippet or the JSON preset.
struct CodePanel: View {
    @ObservedObject var model: PlaygroundModel
    /// Observed so the export follows appearance changes too.
    @ObservedObject var appState: AppState
    @State private var format = Format.swift
    @State private var copiedFormat: Format?
    @State private var copiedReset: Task<Void, Never>?

    enum Format: Hashable {
        case swift
        case json
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PillPicker(
                    title: "Format",
                    selection: $format,
                    choices: [Choice(.swift, "Swift"), Choice(.json, "JSON")]
                )
                .frame(width: 128)
                Spacer(minLength: 8)
                Text("\(lineCount) lines")
                    .font(PlaygroundTheme.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Button(action: copy) {
                    Label(copyTitle, systemImage: copiedFormat == format ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help(copyTitle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(PlaygroundTheme.hairline)
                .frame(height: 1)

            CodeView(text: text, language: format == .swift ? .swift : .json)
                .accessibilityLabel(format == .swift ? "Swift export" : "JSON preset")
        }
        .background(
            RoundedRectangle(cornerRadius: PlaygroundTheme.panelRadius, style: .continuous)
                .fill(PlaygroundTheme.codeBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: PlaygroundTheme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PlaygroundTheme.panelRadius, style: .continuous)
                .strokeBorder(PlaygroundTheme.stroke)
        }
    }

    private var text: String {
        format == .swift ? model.swiftSnippet : model.presetJSON
    }

    private var lineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
    }

    private var copyTitle: String {
        format == .swift ? "Copy the Swift" : "Copy the JSON"
    }

    private func copy() {
        if format == .swift {
            model.copySwift(announcing: false)
        } else {
            model.copyJSON(announcing: false)
        }
        copiedFormat = format
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedFormat = nil
        }
    }
}

// MARK: - Code view

/// Read-only, selectable, unwrapped code with light syntax coloring. An `NSTextView`, since a
/// SwiftUI `Text` in a two-axis scroll view neither scrolls long lines nor selects well.
struct CodeView: NSViewRepresentable {
    enum Language {
        case swift
        case json
    }

    let text: String
    let language: Language

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        // The card behind it provides the background.
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
            textView.string != text || context.coordinator.language != language
        else { return }
        context.coordinator.language = language
        textView.textStorage?.setAttributedString(CodeHighlighter.highlight(text, as: language))
    }

    /// Takes whatever space it is offered. Left to AppKit, the scroll view reports the text's
    /// full height as its size and props the whole window up.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 240)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var language: Language?
    }
}

/// Colors Swift and JSON well enough to read at a glance. It is not a parser: it knows
/// comments, strings, numbers, and a handful of keywords, which is all the export contains.
enum CodeHighlighter {
    private static let keywords: Set<String> = ["import", "var", "let", "return", "in", "true", "false", "nil", "null"]

    static func highlight(_ text: String, as language: CodeView.Language) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        let characters = Array(text.utf16)
        var index = 0

        func color(_ range: Range<Int>, _ color: NSColor) {
            result.addAttribute(
                .foregroundColor,
                value: color,
                range: NSRange(location: range.lowerBound, length: range.count)
            )
        }

        func isIdentifier(_ unit: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || unit == UInt16(UInt8(ascii: "_"))
        }

        while index < characters.count {
            let unit = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : 0
            if language == .swift, unit == UInt16(UInt8(ascii: "/")), next == UInt16(UInt8(ascii: "/")) {
                let start = index
                while index < characters.count, characters[index] != UInt16(UInt8(ascii: "\n")) { index += 1 }
                color(start..<index, .secondaryLabelColor)
            } else if unit == UInt16(UInt8(ascii: "\"")) {
                let start = index
                index += 1
                while index < characters.count, characters[index] != UInt16(UInt8(ascii: "\"")) {
                    index += characters[index] == UInt16(UInt8(ascii: "\\")) ? 2 : 1
                }
                index = min(index + 1, characters.count)
                var lookahead = index
                while lookahead < characters.count, characters[lookahead] == UInt16(UInt8(ascii: " ")) {
                    lookahead += 1
                }
                let isKey =
                    language == .json && lookahead < characters.count
                    && characters[lookahead] == UInt16(UInt8(ascii: ":"))
                color(start..<index, isKey ? .systemPurple : .systemRed)
            } else if isIdentifier(unit) {
                let start = index
                while index < characters.count, isIdentifier(characters[index]) { index += 1 }
                let word = String(decoding: characters[start..<index], as: UTF16.self)
                if keywords.contains(word) {
                    color(start..<index, .systemPink)
                } else if let first = word.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
                    color(start..<index, .systemBlue)
                } else if language == .swift, let first = word.first, first.isUppercase {
                    color(start..<index, .systemTeal)
                }
            } else {
                index += 1
            }
        }
        return result
    }
}
