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

    var body: some View {
        Form {
            Section {
                ForEach(PlaygroundPreset.samples) { sample in
                    LabeledContent {
                        Button("Apply") { model.apply(sample.preset) }
                            .accessibilityLabel("Apply \(sample.name)")
                    } label: {
                        Text(sample.name)
                        Text(sample.summary)
                    }
                }
            } header: {
                Text("Starting points")
            } footer: {
                SectionFooter(text: "Applying a preset replaces every setting and appearance preference.")
            }

            Section {
                LabeledContent("Swift") {
                    Button("Copy Swift", action: model.copySwift)
                }
                LabeledContent("JSON preset") {
                    HStack {
                        Button("Copy JSON", action: model.copyJSON)
                        Button("Save JSON\u{2026}", action: model.saveJSON)
                    }
                }
                LabeledContent("Open a preset") {
                    HStack {
                        Button("Paste JSON", action: model.pasteJSON)
                        Button("Open JSON\u{2026}", action: model.openJSON)
                    }
                }
                if let toast = model.toast {
                    Text(toast)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Export and import")
            } footer: {
                SectionFooter(
                    text: "The Swift sets only what differs from the defaults, for a single-module "
                        + "NookConfiguration; replace the placeholder views with your own. A JSON preset holds "
                        + "the same settings plus the appearance preferences, and opens here or with "
                        + "swift run PlaygroundNook --preset <file>."
                )
            }

            Section {
                Button("Reset Everything\u{2026}", role: .destructive) {
                    isConfirmingReset = true
                }
            } footer: {
                SectionFooter(text: "Returns every setting and appearance preference to the framework default.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset everything to the defaults?", isPresented: $isConfirmingReset) {
            Button("Reset Everything", role: .destructive, action: model.resetEverything)
        } message: {
            Text("Your current settings are replaced. Copy or save them first to keep them.")
        }
    }
}

// MARK: - Export inspector

/// The live export beside the controls: the Swift snippet or the JSON preset.
struct PlaygroundExportView: View {
    @ObservedObject var model: PlaygroundModel
    /// Observed so the export follows appearance changes too.
    @ObservedObject var appState: AppState
    @State private var format = Format.swift

    enum Format: Hashable {
        case swift
        case json
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Format", selection: $format) {
                Text("Swift").tag(Format.swift)
                Text("JSON").tag(Format.json)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            CodeView(text: text, language: format == .swift ? .swift : .json)
                .accessibilityLabel(format == .swift ? "Swift export" : "JSON preset")

            Divider()

            HStack(spacing: 8) {
                Text(model.toast ?? caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(format == .swift ? "Copy Swift" : "Copy JSON") {
                    if format == .swift {
                        model.copySwift()
                    } else {
                        model.copyJSON()
                    }
                }
            }
            .padding(12)
        }
    }

    private var text: String {
        format == .swift ? model.swiftSnippet : model.presetJSON
    }

    private var caption: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        return format == .swift
            ? "\(lines) lines. Only values that differ from the defaults are set."
            : "\(lines) lines. Save it, or paste it into another playground."
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
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 10)
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
