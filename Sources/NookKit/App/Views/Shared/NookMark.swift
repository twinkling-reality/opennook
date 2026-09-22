// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// The OpenNook brand mark - a notch cut from a pair of wings, drawn as one filled shape.
/// Matches `site/public/nook-mark.svg`; the path is fitted by aspect into the rect,
/// centred, so a non-matching rect letterboxes rather than distorts it.
public struct NookMark: Shape {
    /// Width over height of the mark's frame (the SVG's `1056 x 189` view box).
    public static let aspectRatio: CGFloat = 1056 / 189

    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Source coordinates are the SVG's, whose view box starts at (98, 531).
        let scale = min(rect.width / 1056, rect.height / 189)
        let origin = CGPoint(
            x: rect.midX - (98 + 528) * scale,
            y: rect.midY - (531 + 94.5) * scale
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()
        path.move(to: point(124, 539))
        // Left wing's top edge, then the notch: down, across its floor, and back up.
        path.addArc(tangent1End: point(459, 539), tangent2End: point(459, 628), radius: 40 * scale)
        path.addArc(tangent1End: point(459, 669), tangent2End: point(752, 669), radius: 41 * scale)
        path.addArc(tangent1End: point(793, 669), tangent2End: point(793, 579), radius: 41 * scale)
        path.addArc(tangent1End: point(793, 539), tangent2End: point(1128, 539), radius: 40 * scale)
        path.addLine(to: point(1128, 539))
        // Right wing tip, sloping underside, and the rounded base.
        path.addCurve(to: point(1140, 561), control1: point(1146, 539), control2: point(1154, 549))
        path.addLine(to: point(1010, 679))
        path.addQuadCurve(to: point(935, 712), control: point(975, 712))
        path.addLine(to: point(317, 712))
        path.addQuadCurve(to: point(242, 679), control: point(277, 712))
        path.addLine(to: point(112, 561))
        path.addCurve(to: point(124, 539), control1: point(98, 549), control2: point(106, 539))
        path.closeSubpath()
        return path
    }

    /// The brand gradient for the mark on light backgrounds.
    public static let brandGradient = gradient("#8fd3fd", "#8590fd", "#a99efc", "#d9a8fb")

    /// The pale brand gradient for the mark on dark backgrounds.
    public static let paleBrandGradient = gradient("#d6ecfd", "#cbd6fb", "#d1cdfc", "#e3c9fb")

    /// Runs across the shape's own extent (x 106 to 1147 of the view box), as the SVG does.
    private static func gradient(_ hexes: String...) -> LinearGradient {
        let locations: [CGFloat] = [0, 0.33, 0.62, 1]
        return LinearGradient(
            stops: zip(hexes, locations).map { Gradient.Stop(color: color(hex: $0), location: $1) },
            startPoint: UnitPoint(x: 8.0 / 1056, y: 0.5),
            endPoint: UnitPoint(x: 1049.0 / 1056, y: 0.5)
        )
    }

    private static func color(hex: String) -> Color {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Renders ``NookMark`` filled, `size` points wide and `size / NookMark.aspectRatio` tall.
public struct NookMarkView: View {
    /// The mark's width. Its height follows from ``NookMark/aspectRatio``.
    public var size: CGFloat
    /// Unused: the mark is filled, not stroked. Kept so existing callers still compile.
    public var strokeWidth: CGFloat
    public var color: Color
    private var fill: AnyShapeStyle

    public init(size: CGFloat = 24, strokeWidth: CGFloat = 1.75, color: Color = .primary) {
        self.size = size
        self.strokeWidth = strokeWidth
        self.color = color
        self.fill = AnyShapeStyle(color)
    }

    /// A mark filled with any shape style, such as ``NookMark/brandGradient``.
    public init(size: CGFloat = 24, fill: some ShapeStyle) {
        self.size = size
        self.strokeWidth = 0
        self.color = .primary
        self.fill = AnyShapeStyle(fill)
    }

    public var body: some View {
        NookMark()
            .fill(fill)
            .frame(width: size, height: size / NookMark.aspectRatio)
    }
}

#if canImport(AppKit)
    import AppKit

    extension NookMarkView {
        /// Renders the mark into a template `NSImage` for menu-bar and other AppKit chrome,
        /// `size` points wide. Around `28` reads well in the menu bar.
        @MainActor
        public static func makeTemplateImage(size: CGFloat = 28, color: Color = .primary) -> NSImage? {
            let renderer = ImageRenderer(content: NookMarkView(size: size, color: color))
            renderer.scale = 2
            guard let image = renderer.nsImage else { return nil }
            image.isTemplate = true
            return image
        }
    }
#endif
