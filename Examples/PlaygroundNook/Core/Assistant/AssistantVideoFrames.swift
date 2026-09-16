// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AVFoundation
import CoreGraphics
import Foundation

/// Lifts a few still frames out of a screen recording, so a recording can be a reference the same
/// way a screenshot can.
///
/// A recording of someone using a notch app is mostly the same shot, so a handful of evenly spread
/// frames say as much as the whole clip and cost a fraction as much to send. The frames are handed
/// to the person to keep or drop, since only they know which moment they meant.
public enum AssistantVideoFrames {
    /// Frames from the recording at `url`, evenly spread, each already processed for `edge`.
    ///
    /// The file is read but never copied: the frames exist only as the returned attachments, in
    /// memory, for as long as the conversation lasts.
    public static func frames(
        at url: URL,
        edge: Int,
        limits: AssistantMediaLimits = .default
    ) async throws -> [AssistantAttachment] {
        let name = url.lastPathComponent
        let asset = AVURLAsset(url: url)

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw AssistantMediaRejection.unreadable(name: name)
        }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw AssistantMediaRejection.unreadable(name: name)
        }
        guard seconds <= limits.maximumVideoSeconds else {
            throw AssistantMediaRejection.videoTooLong(
                name: name,
                seconds: seconds,
                limit: limits.maximumVideoSeconds
            )
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: edge, height: edge)

        var attachments: [AssistantAttachment] = []
        for time in times(across: seconds, count: limits.framesPerVideo) {
            try Task.checkCancellation()
            let requested = CMTime(seconds: time, preferredTimescale: 600)
            guard let image = try? await generator.image(at: requested).image else { continue }
            let attachment = try AssistantMedia.attachment(
                from: image,
                name: name,
                origin: .videoFrame(seconds: time)
            )
            attachments.append(attachment)
        }
        guard !attachments.isEmpty else {
            throw AssistantMediaRejection.noFrames(name: name)
        }
        return attachments
    }

    /// Where to take frames from, in seconds.
    ///
    /// Spread across the middle of the clip rather than from its ends: a screen recording almost
    /// always starts or finishes mid-gesture, on a fade, or on a frame of empty desktop, and those
    /// are the least useful frames in it.
    static func times(across duration: Double, count: Int) -> [Double] {
        guard count > 0, duration > 0 else { return [] }
        guard count > 1 else { return [duration / 2] }
        let usable = duration * 0.8
        let start = duration * 0.1
        let gap = usable / Double(count - 1)
        return (0..<count).map { start + Double($0) * gap }
    }
}
