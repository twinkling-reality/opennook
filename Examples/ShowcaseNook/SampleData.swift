// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Invented sample content. Every title, artist, and event here is made up for the showcase.

// MARK: - Music

struct Track: Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let cover: CoverArt.Design
}

enum SampleMusic {
    static let tracks: [Track] = [
        Track(
            id: 0,
            title: "Soft Machinery",
            artist: "Velvet Cartography",
            album: "Night Signals",
            duration: 224,
            cover: .init(
                colors: [
                    Color(red: 0.98, green: 0.47, blue: 0.36),
                    Color(red: 0.93, green: 0.27, blue: 0.45),
                    Color(red: 0.45, green: 0.18, blue: 0.62),
                    Color(red: 0.16, green: 0.09, blue: 0.33),
                ],
                motif: .sun
            )
        ),
        Track(
            id: 1,
            title: "Glass Orchard",
            artist: "Low Orbit Choir",
            album: "Greenhouse Tapes",
            duration: 197,
            cover: .init(
                colors: [
                    Color(red: 0.62, green: 0.96, blue: 0.80),
                    Color(red: 0.16, green: 0.72, blue: 0.66),
                    Color(red: 0.05, green: 0.38, blue: 0.47),
                    Color(red: 0.03, green: 0.15, blue: 0.22),
                ],
                motif: .rings
            )
        ),
        Track(
            id: 2,
            title: "Copper Weather",
            artist: "Marigold Engine",
            album: "Copper Weather",
            duration: 251,
            cover: .init(
                colors: [
                    Color(red: 1.00, green: 0.82, blue: 0.42),
                    Color(red: 0.96, green: 0.56, blue: 0.20),
                    Color(red: 0.72, green: 0.25, blue: 0.16),
                    Color(red: 0.29, green: 0.10, blue: 0.10),
                ],
                motif: .bands
            )
        ),
        Track(
            id: 3,
            title: "Northern Static",
            artist: "Tidewater Hymnal",
            album: "Longwave",
            duration: 183,
            cover: .init(
                colors: [
                    Color(red: 0.72, green: 0.86, blue: 1.00),
                    Color(red: 0.36, green: 0.52, blue: 0.96),
                    Color(red: 0.20, green: 0.22, blue: 0.62),
                    Color(red: 0.07, green: 0.08, blue: 0.24),
                ],
                motif: .waves
            )
        ),
        Track(
            id: 4,
            title: "Slow Satellites",
            artist: "Sable & Finch",
            album: "Quiet Hours",
            duration: 208,
            cover: .init(
                colors: [
                    Color(red: 0.99, green: 0.76, blue: 0.86),
                    Color(red: 0.86, green: 0.46, blue: 0.78),
                    Color(red: 0.46, green: 0.32, blue: 0.80),
                    Color(red: 0.14, green: 0.12, blue: 0.34),
                ],
                motif: .orb
            )
        ),
        Track(
            id: 5,
            title: "Paper Harbour",
            artist: "Coastal Radio Society",
            album: "Paper Harbour",
            duration: 239,
            cover: .init(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.84),
                    Color(red: 0.84, green: 0.72, blue: 0.56),
                    Color(red: 0.36, green: 0.44, blue: 0.40),
                    Color(red: 0.12, green: 0.17, blue: 0.17),
                ],
                motif: .arches
            )
        ),
    ]
}

// MARK: - Agenda

struct AgendaEvent: Identifiable, Hashable {
    enum Kind: Hashable {
        case call
        case room(String)
        case focus
        case personal(String)
    }

    let id: Int
    let title: String
    /// Minutes after midnight.
    let start: Int
    let end: Int
    let tint: Color
    let kind: Kind
}

enum SampleAgenda {
    /// The clock the agenda is drawn at, in minutes after midnight, so the schedule always has
    /// one event done, one under way, and the rest still to come.
    static let now = 10 * 60 + 42

    static let events: [AgendaEvent] = [
        AgendaEvent(
            id: 0,
            title: "Design standup",
            start: 9 * 60,
            end: 9 * 60 + 30,
            tint: Color(red: 0.62, green: 0.52, blue: 1.00),
            kind: .call
        ),
        AgendaEvent(
            id: 1,
            title: "Roadmap review",
            start: 10 * 60 + 30,
            end: 11 * 60 + 15,
            tint: Color(red: 1.00, green: 0.62, blue: 0.30),
            kind: .room("Studio B")
        ),
        AgendaEvent(
            id: 2,
            title: "Lunch with the platform team",
            start: 12 * 60 + 30,
            end: 13 * 60 + 30,
            tint: Color(red: 0.36, green: 0.84, blue: 0.56),
            kind: .room("Canteen")
        ),
        AgendaEvent(
            id: 3,
            title: "Write the release notes",
            start: 14 * 60,
            end: 15 * 60 + 30,
            tint: Color(red: 0.38, green: 0.68, blue: 1.00),
            kind: .focus
        ),
        AgendaEvent(
            id: 4,
            title: "Climbing",
            start: 18 * 60 + 15,
            end: 19 * 60 + 45,
            tint: Color(red: 1.00, green: 0.45, blue: 0.56),
            kind: .personal("Boulder Hall")
        ),
    ]

    /// Days in this month that carry at least one event, for the dots under the mini calendar.
    static let busyDays: Set<Int> = [2, 3, 8, 9, 11, 15, 16, 17, 22, 23, 25, 29, 30]
}

// MARK: - Build

struct BuildStep: Identifiable, Hashable {
    let id: Int
    let title: String
    let detail: String
    /// How long the step runs in the showcase, in seconds.
    let duration: Double
}

enum SampleBuild {
    static let project = "Lumen"
    static let version = "2.4.0"
    static let branch = "main"
    static let commit = "3f9c2e1"

    static let steps: [BuildStep] = [
        BuildStep(id: 0, title: "Resolve packages", detail: "14 packages", duration: 1.4),
        BuildStep(id: 1, title: "Compile sources", detail: "412 files", duration: 5.2),
        BuildStep(id: 2, title: "Link and embed frameworks", detail: "arm64, x86_64", duration: 3.1),
        BuildStep(id: 3, title: "Run tests", detail: "1,284 tests", duration: 4.6),
        BuildStep(id: 4, title: "Sign and notarize", detail: "Developer ID", duration: 3.8),
        BuildStep(id: 5, title: "Upload to release channel", detail: "38.2 MB", duration: 2.4),
    ]
}

// MARK: - Shelf

/// The files the shelf scene holds. They are written to a temporary folder at launch, never
/// into the repository, so the shelf shows real files. The shelf draws each file's Finder icon
/// rather than a QuickLook thumbnail, so every file also gets a custom icon rendered from its
/// own contents, and the row reads as previews instead of blank document glyphs.
@MainActor
enum SampleFiles {
    static func make() -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowcaseNook-Shelf", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var urls: [URL] = []
        func write(_ name: String, _ data: Data?, preview: CGImage?) {
            let url = folder.appendingPathComponent(name)
            guard let data, (try? data.write(to: url)) != nil else { return }
            if let preview, let icon = bitmap(FileIconArt(preview: preview), scale: 2) {
                NSWorkspace.shared.setIcon(
                    NSImage(cgImage: icon, size: NSSize(width: 256, height: 256)),
                    forFile: url.path
                )
            }
            urls.append(url)
        }

        let hero = bitmap(HeroRender(), scale: 2)
        let moodboard = bitmap(Moodboard(), scale: 2)
        write("Roadmap Q4.pdf", pdf(RoadmapSlide()), preview: bitmap(RoadmapSlide(), scale: 0.5))
        write("Hero Render.png", hero.flatMap { encoded($0, as: .png) }, preview: hero)
        write(
            "Release Notes.md",
            Data(ReleaseNotesPage.markdown.utf8),
            preview: bitmap(ReleaseNotesPage(), scale: 0.6)
        )
        write("Moodboard.jpg", moodboard.flatMap { encoded($0, as: .jpeg) }, preview: moodboard)
        write("Typeface.pdf", pdf(TypeSpecimenPage()), preview: bitmap(TypeSpecimenPage(), scale: 0.6))
        return urls
    }

    private static func bitmap(_ view: some View, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// One PDF page the size of `view`, drawn as vectors so its text stays sharp.
    private static func pdf(_ view: some View) -> Data? {
        let data = NSMutableData()
        var written = false
        ImageRenderer(content: view).render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data),
                let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            written = true
        }
        return written ? data as Data : nil
    }

    private static func encoded(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
