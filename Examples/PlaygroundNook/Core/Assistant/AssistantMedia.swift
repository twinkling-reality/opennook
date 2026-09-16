// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What kinds of reference the assistant takes, and how much of them.
public struct AssistantMediaLimits: Sendable, Equatable {
    /// Four is enough to describe a look from a few angles and few enough that the person can see
    /// every thumbnail at once without the strip scrolling.
    public var maximumAttachments = 4
    /// Per file. A screenshot is well under this; the limit is there to catch a wrong drop, such as
    /// a whole photo library export.
    public var maximumBytes = 20 * 1024 * 1024
    /// A reference recording is a few seconds of someone using an app. Anything longer is almost
    /// certainly not what was meant.
    public var maximumVideoSeconds: Double = 60
    /// How many frames are lifted out of a recording, spread evenly across it.
    public var framesPerVideo = 4

    public init() {}

    public static let `default` = AssistantMediaLimits()
}

/// Why a file could not be used as a reference. Each case says which of the three things was wrong,
/// the type, the size, or the count, because a rejection that does not say why reads as a bug.
public enum AssistantMediaRejection: Error, Equatable, LocalizedError {
    case unsupportedType(name: String)
    case tooLarge(name: String, bytes: Int, limit: Int)
    case tooMany(limit: Int)
    case unreadable(name: String)
    case videoTooLong(name: String, seconds: Double, limit: Double)
    case noFrames(name: String)

    public var errorDescription: String? {
        switch self {
            case .unsupportedType(let name):
                "\(name) is not an image or a screen recording."
            case .tooLarge(let name, let bytes, let limit):
                "\(name) is \(Self.megabytes(bytes)), over the \(Self.megabytes(limit)) limit."
            case .tooMany(let limit):
                "Only \(limit) references at a time."
            case .unreadable(let name):
                "\(name) could not be read."
            case .videoTooLong(let name, let seconds, let limit):
                "\(name) is \(Self.seconds(seconds)) long, over the \(Self.seconds(limit)) limit."
            case .noFrames(let name):
                "No frames could be read from \(name)."
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        let value = Double(bytes) / (1024 * 1024)
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " MB"
    }

    private static func seconds(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(0))) + " s"
    }
}

/// Turns a dropped, pasted, or chosen file into an ``AssistantAttachment``.
///
/// Everything a provider could be sent is made here, and only here, which is what makes the privacy
/// promise checkable: the image is decoded, scaled down, and re-encoded from its pixels alone, so
/// the EXIF block, the GPS tag, the capture time, and the device name in the original never reach a
/// request. Nothing is written to disk.
///
/// Scaling, orientation, and metadata are all handled by asking ImageIO for a thumbnail with a
/// transform rather than by hand: it is the one path that reads the orientation tag, applies it, and
/// hands back bare pixels, and it takes the first frame of an animated GIF for free.
public enum AssistantMedia {
    /// The image types a reference can be.
    public static let imageTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .gif, .bmp, .webP]
    /// The recording types a reference can be.
    public static let videoTypes: [UTType] = [.quickTimeMovie, .mpeg4Movie]

    public static var allowedTypes: [UTType] { imageTypes + videoTypes }

    /// Whether a file of this type can be used at all, so a drop can be refused before it is read.
    public static func isSupported(_ type: UTType) -> Bool {
        allowedTypes.contains { type.conforms(to: $0) }
    }

    public static func isVideo(_ type: UTType) -> Bool {
        videoTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Images

    /// One image as an attachment: scaled to `edge` on its longest side, re-encoded, and measured.
    ///
    /// - Parameters:
    ///   - data: the file's bytes, as dropped or pasted.
    ///   - name: what to call it in a rejection.
    ///   - edge: the longest edge the chosen provider wants.
    public static func attachment(
        from data: Data,
        name: String,
        edge: Int,
        origin: AssistantAttachment.Origin = .image,
        limits: AssistantMediaLimits = .default
    ) throws -> AssistantAttachment {
        guard data.count <= limits.maximumBytes else {
            throw AssistantMediaRejection.tooLarge(name: name, bytes: data.count, limit: limits.maximumBytes)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else {
            throw AssistantMediaRejection.unreadable(name: name)
        }
        guard let scaled = thumbnail(from: source, edge: edge) else {
            throw AssistantMediaRejection.unreadable(name: name)
        }
        return try attachment(from: scaled, name: name, origin: origin)
    }

    /// An already decoded image as an attachment. Used by the video path, which has frames rather
    /// than files, and by tests.
    public static func attachment(
        from image: CGImage,
        name: String,
        origin: AssistantAttachment.Origin = .image
    ) throws -> AssistantAttachment {
        guard let jpeg = encodeJPEG(image) else {
            throw AssistantMediaRejection.unreadable(name: name)
        }
        let reading = AssistantPalette.read(image)
        return AssistantAttachment(
            origin: origin,
            jpeg: jpeg,
            pixelWidth: image.width,
            pixelHeight: image.height,
            palette: reading.palette,
            measurements: reading.measurements
        )
    }

    /// The image scaled so its longest edge is at most `edge`, with its orientation applied and its
    /// metadata gone. A smaller image is left at its own size rather than blown up.
    static func thumbnail(from source: CGImageSource, edge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the orientation tag, which matters because the tag itself is about to be
            // dropped: without this, a photo taken sideways would be sent sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image as JPEG, from its pixels only. No properties are passed to the destination, so
    /// nothing from the original file can come along.
    static func encodeJPEG(_ image: CGImage, quality: Double = 0.8) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
