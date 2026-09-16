// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images and recordings built in code, so the media tests need no checked-in binaries and can say
/// exactly what is in a fixture: these colors, this orientation tag, this much EXIF.
enum AssistantMediaFixtures {
    /// An image of `bands` horizontal stripes, each a flat color, top to bottom.
    static func image(width: Int, height: Int, bands: [(red: Double, green: Double, blue: Double)]) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let bandHeight = Double(height) / Double(bands.count)
        for (index, band) in bands.enumerated() {
            context.setFillColor(red: band.red, green: band.green, blue: band.blue, alpha: 1)
            context.fill(
                CGRect(x: 0, y: Double(index) * bandHeight, width: Double(width), height: bandHeight)
            )
        }
        return context.makeImage()!
    }

    static func solid(
        width: Int = 120,
        height: Int = 80,
        red: Double,
        green: Double,
        blue: Double
    ) -> CGImage {
        image(width: width, height: height, bands: [(red, green, blue)])
    }

    /// An image with a fully transparent top half and an opaque bottom half.
    static func halfTransparent(width: Int = 80, height: Int = 80) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height) / 2))
        return context.makeImage()!
    }

    /// `image` as PNG.
    static func png(_ image: CGImage) -> Data {
        encode(image, as: .png, properties: nil)
    }

    /// `image` as JPEG carrying an EXIF block, a GPS position, and a maker note, so a test can prove
    /// they do not survive the pipeline.
    static func jpegWithMetadata(_ image: CGImage, orientation: Int? = nil) -> Data {
        var properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:16 14:02:11",
                kCGImagePropertyExifUserComment: "taken on a phone",
                kCGImagePropertyExifLensModel: "Some Lens 24mm",
            ] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194,
                kCGImagePropertyGPSLongitudeRef: "W",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Somebody",
                kCGImagePropertyTIFFModel: "Some Camera",
            ] as [CFString: Any],
        ]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        return encode(image, as: .jpeg, properties: properties)
    }

    private static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any]?) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            type.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The metadata keys of `data`, so a test can compare what went in with what came out.
    static func metadataKeys(of data: Data) -> Set<String> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            return []
        }
        return Set(properties.keys)
    }

    // MARK: - Recordings

    /// A silent recording of `seconds` at ten frames a second, cycling through `bands` so different
    /// moments look different. Written to a temporary file, which is the only way AVFoundation reads
    /// a movie.
    static func movie(
        at url: URL,
        seconds: Double,
        size: CGSize = CGSize(width: 160, height: 120)
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ]
        )
        input.expectsMediaDataInRealTime = false
        // The adaptor only has a pixel buffer pool when it is told what the source pixels look like.
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameRate = 10.0
        let frames = Int(seconds * frameRate)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let shade = Double(index) / Double(max(frames - 1, 1))
            let image = solid(
                width: Int(size.width),
                height: Int(size.height),
                red: shade,
                green: 0.2,
                blue: 1 - shade
            )
            guard let pool = adaptor.pixelBufferPool, let buffer = pixelBuffer(from: image, pool: pool) else {
                continue
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        // A fixture that quietly wrote nothing would look like a bug in the code under test.
        if writer.status != .completed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return nil
        }
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer)
            )
        )
        return buffer
    }
}
