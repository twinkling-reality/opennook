// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import SwiftUI

/// The composer's text field.
///
/// An `NSTextView` rather than a SwiftUI `TextField` or `TextEditor`, for three things none of them
/// will do together: Return sends while Shift-Return adds a line, the field grows from one line to
/// about five and then scrolls instead of growing, and it has no background of its own so it can sit
/// on the composer's fill.
///
/// It has no say in its own height. The caller measures the text and gives it a frame, because every
/// arrangement where the view has an opinion ends badly: an ideal size or a flexible frame is asked
/// for before the text container has a width, and measures the text wrapped into almost nothing, so an
/// empty one-line field comes out several lines tall. Reporting the height back after layout instead
/// puts the measurement inside the thing it changes, and the two chase each other at seventy percent
/// of a core.
struct AssistantTextViewBridge: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    /// The font the field draws with, and the one the caller measures against.
    static let font = NSFont.systemFont(ofSize: 13)
    /// The padding inside the text container, top and bottom each.
    static let verticalInset: CGFloat = 3

    /// How tall `text` is at `width`, for the caller's frame.
    ///
    /// Measured from the string with the same font the view uses, rather than from the view, so the
    /// number cannot depend on the layout it is about to decide.
    static func height(of text: String, width: CGFloat) -> CGFloat {
        guard width > 0 else { return oneLineHeight }
        // The text container insets its lines by this much on each side.
        let padding = NSTextContainer().lineFragmentPadding * 2
        let measured = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font])
            .boundingRect(
                with: CGSize(width: max(width - padding, 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        return measured.height.rounded(.up) + verticalInset * 2
    }

    static let oneLineHeight = height(of: "", width: 200)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = TextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.placeholder = placeholder
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = Self.font
        textView.textContainerInset = NSSize(width: 0, height: Self.verticalInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        // Whatever someone is pasting in, what the assistant wants is words.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TextView else { return }
        textView.onSubmit = onSubmit
        textView.placeholder = placeholder
        // Only when it really differs, or every keystroke would move the insertion point.
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }

    /// Sends on Return, adds a line on Shift-Return, and draws its own placeholder.
    private final class TextView: NSTextView {
        var onSubmit: () -> Void = {}
        var placeholder = ""

        override func insertNewline(_ sender: Any?) {
            // Shift-Return, or Option-Return, means a line break rather than sending.
            if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.option) {
                super.insertNewline(sender)
                return
            }
            onSubmit()
        }

        /// The placeholder is drawn here rather than layered behind in SwiftUI. A `Text` behind the
        /// field is a second view the layout has to account for, and it lands in the accessibility
        /// tree under the field's own identifier, where it is read out as a second nameless control.
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, !placeholder.isEmpty, let font else { return }
            let origin = NSPoint(
                x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                y: textContainerInset.height
            )
            placeholder.draw(
                at: origin,
                withAttributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            )
        }
    }
}
