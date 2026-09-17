// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Builds what the model is told. Pure text in, pure text out, so the request inspector can show a
/// person the whole prompt and a test can assert on it.
///
/// Two things are worth knowing about the shape of it. The instructions say plainly what these
/// settings cannot express, because a model that does not know its limits invents fields instead of
/// admitting them, and the honest "not reproduced" list is most of what makes matching a screenshot
/// trustworthy. And the field guide is only included for providers that cannot enforce the schema,
/// since the schema already carries every name, bound, and meaning.
public enum AssistantPrompt {
    /// What the model is for, what it may change, and the shape of its answer.
    public static func systemPrompt(capabilities: AssistantCapabilities) -> String {
        var sections = [instructions]
        if !capabilities.enforcesSchema {
            sections.append(answerShape)
            sections.append("The settings, as name: type, default, meaning.\n\(AssistantSchema.fieldGuide)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static let instructions = """
        You are tuning the chrome of OpenNook, a macOS app that lives in the notch, while someone \
        watches it change live. They describe what they want in ordinary words. You answer with the \
        settings that get them there.

        What you can change is the chrome around the content: the palette and material, the theme \
        colors, the type design, the panel's width and corners and insets, the top bar and what sits \
        in it, companion surfaces floated beside the panel, the rim glow, the scroll edge fade, and \
        how it behaves on hover.

        Companions are where controls live outside the panel, and you can compose them freely: a \
        companion holds items (glyph buttons, labels, and the nook's own lock and gear) in a row or a \
        column, with its own shape, backdrop, size, fade, edge, shadow, hover, and entrance. A group \
        of controls is one companion with several items; a control that stands apart is a companion \
        of its own. Companions on the same side with the same alignment form one row, in list order, \
        and settings.companionDefaults sets the size and look they share, so neighbours match.

        What you cannot change is what the app puts inside the panel: its home content and layout, \
        artwork, album grids, waveforms, controls inside the panel, and any font outside the four \
        system designs. When something asked for needs one of those, leave it out of the patch and name it \
        in notReproduced, in a few plain words. Saying you could not do something is more useful than \
        approximating it with a setting that does not mean the same thing.

        Change as little as possible. Only include a field you are actually changing, never a field \
        that already holds the value you want, and never a default restated. When a request is vague, \
        make the smallest confident change rather than a sweeping one.

        Listing settings.companions sets which companions exist and in what order, so include every \
        companion that should exist afterwards, each with its id. A companion that already exists \
        keeps any field you leave out, so list only its id and what changes. A new companion needs \
        its items; listing items replaces that companion's items. Use SF Symbol names for symbols. \
        To put the nook's own lock and gear beside the panel, add a companion with items of type \
        keepOpen and settings, and turn off settings.topBar.showsKeepOpenButton and \
        settings.topBar.showsSettingsButton.
        """

    private static let answerShape = """
        Answer with one JSON object and nothing else. No markdown, no code fence, no text around it. \
        Its members, in this order:

        explanation: one or two plain sentences saying what you changed and why. No markdown, no \
        lists, no field names.
        notReproduced: a list of short phrases for anything asked for that these settings cannot \
        express. An empty list when there is nothing.
        patch: an object holding only the fields you are changing, nested exactly as the names below \
        are, so settings.panel.expandedWidth is written as { "settings": { "panel": \
        { "expandedWidth": 420 } } }.
        """

    /// What the person's turn looks like once the reference images have been described.
    ///
    /// The colors and measurements are worked out on this machine, so they are in the text whether or
    /// not the provider can see the pixels. A provider that cannot gets a request that still says
    /// what the screenshot is like; a provider that can gets both, which stops it guessing at hex
    /// values it can only estimate by eye.
    public static func personTurn(_ turn: AssistantTurn, sendsImages: Bool) -> String {
        var lines: [String] = []
        let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            lines.append(text)
        }

        guard !turn.attachments.isEmpty else { return lines.joined(separator: "\n") }

        lines.append("")
        let count = turn.attachments.count
        let noun = count == 1 ? "reference" : "references"
        if sendsImages {
            lines.append("There \(count == 1 ? "is" : "are") \(count) \(noun) attached, described below too.")
        } else {
            lines.append(
                "There \(count == 1 ? "is" : "are") \(count) \(noun), which you cannot see. "
                    + "What was measured from \(count == 1 ? "it" : "them") on this machine:"
            )
        }

        for (index, attachment) in turn.attachments.enumerated() {
            lines.append("")
            lines.append("Reference \(index + 1) (\(attachment.pixelWidth) by \(attachment.pixelHeight)):")
            for measurement in attachment.measurements {
                lines.append("- \(measurement)")
            }
            if !attachment.palette.isEmpty {
                let hexes = attachment.palette.map(\.hex).joined(separator: ", ")
                lines.append("- Dominant colors, most common first: \(hexes)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The state the model is changing, as the JSON of the preset. Sent as part of the person's
    /// first turn so the model can tell what is already true and answer with a small patch.
    public static func currentState(_ preset: PlaygroundPreset) throws -> String {
        let json = try AssistantPatch.encoded(preset)
        return "The settings as they are now:\n\(json.text)"
    }

    /// The whole request as one piece of text, for the ways of asking that have no notion of a
    /// conversation: a command line tool, or a person pasting into a chat window.
    ///
    /// The newest turn stays last, which is where a model weights its attention.
    public static func flattened(_ request: AssistantRequest, adding note: String? = nil) -> String {
        var sections = [request.systemPrompt]
        if let note {
            sections.append(note)
        }
        for turn in request.turns {
            switch turn.role {
                case .person:
                    sections.append("The person said:\n\(turn.text)")
                case .assistant:
                    sections.append("You answered:\n\(turn.text)")
            }
        }
        return sections.joined(separator: "\n\n")
    }
}
