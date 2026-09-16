// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import CoreGraphics
import Foundation

/// Reads the colors out of a reference image on this machine.
///
/// This exists so that "copy this style" produces the colors that are actually in the screenshot. A
/// model looking at an image estimates hex values by eye and is confidently wrong by a shade or two;
/// a model that is only sent text cannot see it at all. Counting pixels is exact, costs nothing, and
/// works the same for every provider, so the palette is measured here and handed over as hex values
/// the model is told to use.
///
/// Deliberately deterministic: the same image always gives the same palette in the same order, so a
/// request is reproducible and a test can assert on it.
public enum AssistantPalette {
    /// What was read from an image: its dominant colors and a few plain facts about it.
    public struct Reading: Sendable, Equatable {
        public var palette: [PlaygroundColor]
        public var measurements: [String]
    }

    /// How many colors are reported. Five covers a background, a surface, a text color, and an
    /// accent, with one spare.
    public static let colorCount = 5

    /// The colors and measurements of `image`.
    public static func read(_ image: CGImage, colorCount: Int = colorCount) -> Reading {
        guard let pixels = samplePixels(of: image) else {
            return Reading(palette: [], measurements: [])
        }
        let palette = dominantColors(in: pixels, count: colorCount)
        return Reading(palette: palette, measurements: measurements(of: pixels, palette: palette))
    }

    // MARK: - Sampling

    /// One pixel per cell of a small grid, as 8 bits per channel.
    ///
    /// The image is drawn into a fixed 64 by 64 box rather than read at full size: it is two orders
    /// of magnitude less work, the averaging that happens on the way down is what makes the counts
    /// stable against noise and dithering, and a fixed size means the palette of a screenshot does
    /// not depend on the display it was taken on.
    static let sampleEdge = 64

    struct Pixels: Sendable {
        var red: [UInt8]
        var green: [UInt8]
        var blue: [UInt8]
        var count: Int { red.count }
    }

    static func samplePixels(of image: CGImage) -> Pixels? {
        let edge = sampleEdge
        var bytes = [UInt8](repeating: 0, count: edge * edge * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = bytes.withUnsafeMutableBytes({ buffer in
                CGContext(
                    data: buffer.baseAddress,
                    width: edge,
                    height: edge,
                    bitsPerComponent: 8,
                    bytesPerRow: edge * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            })
        else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        guard let data = context.data else { return nil }

        let buffer = data.bindMemory(to: UInt8.self, capacity: edge * edge * 4)
        var pixels = Pixels(red: [], green: [], blue: [])
        pixels.red.reserveCapacity(edge * edge)
        pixels.green.reserveCapacity(edge * edge)
        pixels.blue.reserveCapacity(edge * edge)
        for index in 0..<(edge * edge) {
            let offset = index * 4
            let alpha = buffer[offset + 3]
            // A fully transparent pixel has no color to contribute, and its premultiplied channels
            // are zero, which would otherwise read as a vote for black.
            guard alpha > 8 else { continue }
            pixels.red.append(buffer[offset])
            pixels.green.append(buffer[offset + 1])
            pixels.blue.append(buffer[offset + 2])
        }
        return pixels.count > 0 ? pixels : nil
    }

    // MARK: - Dominant colors

    /// The most common colors, most common first.
    ///
    /// Colors are counted in coarse buckets so that a gradient or a compression artifact does not
    /// split one apparent color across hundreds of near-identical values. Each bucket then reports
    /// the average of the pixels in it, so the color that comes out is one that is really in the
    /// image rather than the bucket's midpoint.
    static func dominantColors(in pixels: Pixels, count: Int) -> [PlaygroundColor] {
        // 32 levels per channel: fine enough to keep two greys apart, coarse enough to gather a
        // gradient into one entry.
        let levels = 32
        let step = 256 / levels

        struct Bucket {
            var count = 0
            var red = 0
            var green = 0
            var blue = 0
        }
        var buckets: [Int: Bucket] = [:]
        for index in 0..<pixels.count {
            let red = Int(pixels.red[index])
            let green = Int(pixels.green[index])
            let blue = Int(pixels.blue[index])
            let key = (red / step) << 10 | (green / step) << 5 | (blue / step)
            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            buckets[key] = bucket
        }

        // Sorted by how common it is, then by the bucket itself, so a tie cannot come out in a
        // different order on a different run.
        let ordered = buckets.sorted { lhs, rhs in
            lhs.value.count != rhs.value.count ? lhs.value.count > rhs.value.count : lhs.key < rhs.key
        }

        var palette: [PlaygroundColor] = []
        for (_, bucket) in ordered {
            let color = PlaygroundColor(
                red: Double(bucket.red) / Double(bucket.count) / 255,
                green: Double(bucket.green) / Double(bucket.count) / 255,
                blue: Double(bucket.blue) / Double(bucket.count) / 255
            )
            // Two entries a person would call the same color are not worth one of the five slots.
            guard !palette.contains(where: { isNearly($0, color) }) else { continue }
            palette.append(color)
            if palette.count == count { break }
        }
        return palette
    }

    /// Whether two colors are close enough that reporting both would waste a slot.
    static func isNearly(_ lhs: PlaygroundColor, _ rhs: PlaygroundColor) -> Bool {
        let distance =
            abs(lhs.red - rhs.red) + abs(lhs.green - rhs.green) + abs(lhs.blue - rhs.blue)
        return distance < 0.12
    }

    // MARK: - Measurements

    /// A few plain facts, worded for the prompt. Only things that can be measured: whether it is
    /// dark or light, how colorful it is, and what the most common color is.
    static func measurements(of pixels: Pixels, palette: [PlaygroundColor]) -> [String] {
        var lines: [String] = []

        var totalLuminance = 0.0
        var totalSaturation = 0.0
        for index in 0..<pixels.count {
            let red = Double(pixels.red[index]) / 255
            let green = Double(pixels.green[index]) / 255
            let blue = Double(pixels.blue[index]) / 255
            totalLuminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let highest = max(red, green, blue)
            let lowest = min(red, green, blue)
            totalSaturation += highest <= 0 ? 0 : (highest - lowest) / highest
        }
        let luminance = totalLuminance / Double(pixels.count)
        let saturation = totalSaturation / Double(pixels.count)

        switch luminance {
            case ..<0.2: lines.append("Very dark overall")
            case ..<0.45: lines.append("Mostly dark")
            case ..<0.7: lines.append("Mid brightness")
            default: lines.append("Mostly light")
        }

        if saturation < 0.12 {
            lines.append("Close to neutral greys, very little color")
        } else if saturation > 0.4 {
            lines.append("Strongly colored")
        }

        if let background = palette.first {
            lines.append("Most common color \(background.hex)")
        }
        return lines
    }
}
