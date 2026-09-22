// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

// The pages and pictures inside the shelf scene's sample files. `SampleFiles` renders each one
// into its file (PDF, PNG, or JPEG) and again into the file's icon, so the icon previews the
// file's real contents.

// MARK: - Roadmap Q4.pdf

/// A dark keynote-style slide with a quarter's swimlanes.
struct RoadmapSlide: View {
    private struct Lane {
        let name: String
        /// Start and length as fractions of the quarter.
        let start: CGFloat
        let length: CGFloat
        let tint: Color
    }

    private let lanes = [
        Lane(name: "Shelf", start: 0, length: 0.38, tint: Color(red: 0.98, green: 0.47, blue: 0.36)),
        Lane(name: "Sync", start: 0.22, length: 0.40, tint: Color(red: 0.16, green: 0.72, blue: 0.66)),
        Lane(name: "Widgets", start: 0.45, length: 0.40, tint: Color(red: 1.00, green: 0.72, blue: 0.30)),
        Lane(name: "Launch", start: 0.80, length: 0.20, tint: Color(red: 0.86, green: 0.46, blue: 0.78)),
    ]
    private let months = ["October", "November", "December"]
    private let labelWidth: CGFloat = 130
    private let trackWidth: CGFloat = 718

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LUMEN  /  PRODUCT")
                .font(.system(size: 15, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Color(red: 0.98, green: 0.62, blue: 0.50))
            Text("Roadmap Q4")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Spacer().frame(width: labelWidth)
                ForEach(months, id: \.self) { month in
                    Text(month)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: trackWidth / 3, alignment: .leading)
                }
            }
            .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(lanes, id: \.name) { lane in
                    HStack(spacing: 0) {
                        Text(lane.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: labelWidth, alignment: .leading)
                        Spacer().frame(width: trackWidth * lane.start)
                        Capsule()
                            .fill(lane.tint)
                            .frame(width: trackWidth * lane.length, height: 30)
                    }
                }
            }
            .background(alignment: .leading) {
                // Faint month dividers behind the lanes.
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 1)
                            .frame(width: trackWidth / 3, alignment: .leading)
                    }
                }
                .padding(.leading, labelWidth)
                .padding(.vertical, -8)
            }
        }
        .padding(56)
        .frame(width: 960, height: 540, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.24), Color(red: 0.25, green: 0.12, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Hero Render.png

/// A square render in its own palette, drawn with the player's cover art.
struct HeroRender: View {
    var body: some View {
        CoverArt(
            design: .init(
                colors: [
                    Color(red: 1.00, green: 0.78, blue: 0.56),
                    Color(red: 0.96, green: 0.44, blue: 0.47),
                    Color(red: 0.52, green: 0.22, blue: 0.56),
                    Color(red: 0.13, green: 0.08, blue: 0.27),
                ],
                motif: .waves
            ),
            size: 512,
            cornerRadius: 0
        )
    }
}

// MARK: - Release Notes.md

/// The release notes as a rendered page. `markdown` is the same text, for the file itself.
struct ReleaseNotesPage: View {
    static let title = "Lumen 2.4"
    static let subtitle = "Release notes, September 2026"
    static let sections: [(heading: String, items: [String])] = [
        (
            "New",
            ["Drop files on the notch to shelve them", "A focus timer beside the camera", "Build progress in the pill"]
        ),
        ("Improved", ["Launches twice as fast on Apple silicon", "Smoother expand and collapse"]),
        ("Fixed", ["The shelf keeps files across relaunches", "Artwork no longer flickers on skip"]),
    ]

    static var markdown: String {
        var text = "# \(title)\n\n_\(subtitle)_\n"
        for section in sections {
            text += "\n## \(section.heading)\n\n" + section.items.map { "- \($0)\n" }.joined()
        }
        return text
    }

    private let accent = Color(red: 0.38, green: 0.68, blue: 1.00)
    private let ink = Color(red: 0.11, green: 0.12, blue: 0.15)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.title)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(ink)
            Text(Self.subtitle)
                .font(.system(size: 16))
                .foregroundStyle(ink.opacity(0.5))
                .padding(.top, 6)
            Capsule()
                .fill(accent)
                .frame(width: 72, height: 6)
                .padding(.top, 22)
            ForEach(Self.sections, id: \.heading) { section in
                Text(section.heading)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ink)
                    .padding(.top, 34)
                ForEach(section.items, id: \.self) { item in
                    HStack(spacing: 12) {
                        Circle().fill(accent).frame(width: 8, height: 8)
                        Text(item)
                            .font(.system(size: 16))
                            .foregroundStyle(ink.opacity(0.75))
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(64)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(Color.white)
    }
}

// MARK: - Moodboard.jpg

/// Every album cover from the player, pinned up in a grid.
struct Moodboard: View {
    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(SampleMusic.tracks[row * 3..<row * 3 + 3]) { track in
                        CoverArt(design: track.cover, size: 180, cornerRadius: 10)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(red: 1.00, green: 0.99, blue: 0.97))
    }
}

// MARK: - Typeface.pdf

/// A one-page type specimen on warm paper.
struct TypeSpecimenPage: View {
    private let ink = Color(red: 0.14, green: 0.12, blue: 0.11)
    private let swatches = [
        Color(red: 0.93, green: 0.27, blue: 0.45),
        Color(red: 0.96, green: 0.56, blue: 0.20),
        Color(red: 0.16, green: 0.72, blue: 0.66),
        Color(red: 0.36, green: 0.52, blue: 0.96),
        Color(red: 0.14, green: 0.12, blue: 0.11),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Type Specimen")
                Spacer()
                Text("Lumen Serif")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ink.opacity(0.55))
            Text("Aa")
                .font(.system(size: 250, weight: .regular, design: .serif))
                .foregroundStyle(ink)
                .padding(.top, 10)
            Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 &?!")
                .font(.system(size: 21, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(ink.opacity(0.8))
            HStack(spacing: 18) {
                ForEach([Font.Weight.light, .regular, .semibold, .bold], id: \.self) { weight in
                    Text("Serif")
                        .font(.system(size: 26, weight: weight, design: .serif))
                }
            }
            .foregroundStyle(ink)
            .padding(.top, 30)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(swatches.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(swatches[index])
                        .frame(height: 52)
                }
            }
        }
        .padding(56)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(Color(red: 1.00, green: 0.99, blue: 0.97))
    }
}

// MARK: - Icon

/// A file's icon: its preview laid on a transparent square, the way Finder shows a thumbnail.
struct FileIconArt: View {
    let preview: CGImage

    var body: some View {
        Image(decorative: preview, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .padding(16)
            .frame(width: 256, height: 256)
    }
}
