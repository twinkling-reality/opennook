// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import SwiftUI

/// The chrome's outline. Two forms, selected by ``NookChromeForm``:
///
/// - ``NookChromeForm/notch`` - a notch-following shape: the top edge flares to full
///   width then curves *inward* by `topCornerRadius`, so the ears fuse flush with the
///   menu bar on either side of a physical notch; larger bottom-corners where the
///   panel meets the wallpaper.
/// - ``NookChromeForm/floating`` - a plain convex rounded rectangle, for a free-floating
///   panel on a display with no notch.
///
/// `form` is a discrete per-window configuration and isn't animated; the two corner
/// radii are, so a compact<->expanded transition still springs smoothly within a form.
///
/// The chrome draws, clips, hit-tests, and traces its rim and feedback along this one
/// shape. Hosts can build one to draw matching outlines - a preview of the chrome, a
/// companion that echoes it - and chrome content reads the live one as
/// ``EnvironmentValues/nookChromeShape``. The path itself comes from the shape's
/// ``NookOutline``, which ``NookStyle/outline`` sets.
public struct NookShape: Shape {
    /// Which outline family the shape draws.
    public let form: NookChromeForm
    /// The top corner radius: the ears in the notch form, the top corners when floating.
    public private(set) var topCornerRadius: CGFloat
    /// The bottom corner radius.
    public private(set) var bottomCornerRadius: CGFloat
    /// What turns the form and radii into a path.
    public let outline: NookOutline

    public init(
        form: NookChromeForm = .notch,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        outline: NookOutline = .standard
    ) {
        self.form = form
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.outline = outline
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        outline.path(
            NookOutline.Geometry(
                rect: rect,
                form: form,
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        )
    }
}

extension NookShape: Equatable {
    public static func == (lhs: NookShape, rhs: NookShape) -> Bool {
        lhs.form == rhs.form
            && lhs.topCornerRadius == rhs.topCornerRadius
            && lhs.bottomCornerRadius == rhs.bottomCornerRadius
            && lhs.outline == rhs.outline
    }
}

/// Turns the chrome's form and corner radii into its outline path.
///
/// ``standard`` is the built-in outline: eared in the notch form, a rounded rectangle when
/// floating. A host replaces it through ``NookStyle/outline`` for a different silhouette -
/// squarer ears, continuous corners, a notched bottom edge.
///
/// The chrome animates between compact and expanded by interpolating the two radii and
/// asking the outline for a path at each frame, so a custom outline animates for free as
/// long as its path changes smoothly with the radii. It is also the chrome's clip and
/// hit-test region, so keep it inside `rect` and closed. In the notch form, the chrome's
/// content is inset horizontally by `topCornerRadius`; an outline whose sides come in
/// further than that clips the content.
///
/// Closures cannot be compared, so ``id`` stands in for the path in equality. Give a
/// different path a different id.
///
/// ```swift
/// let squared = NookOutline(id: "squared") { geometry in
///     Path(roundedRect: geometry.rect, cornerRadius: geometry.bottomCornerRadius / 2)
/// }
/// nook.style.outline = squared
/// ```
public struct NookOutline: Equatable, Sendable {
    /// What an outline draws from: the frame and the chrome's current form and radii.
    public struct Geometry: Equatable, Sendable {
        public var rect: CGRect
        public var form: NookChromeForm
        public var topCornerRadius: CGFloat
        public var bottomCornerRadius: CGFloat

        public init(rect: CGRect, form: NookChromeForm, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
            self.rect = rect
            self.form = form
            self.topCornerRadius = topCornerRadius
            self.bottomCornerRadius = bottomCornerRadius
        }
    }

    /// Identifies the path. Equality compares this and nothing else.
    public let id: String

    private let makePath: @Sendable (Geometry) -> Path

    /// An outline drawn by `path`, identified by `id`.
    public init(id: String, path: @escaping @Sendable (Geometry) -> Path) {
        self.id = id
        self.makePath = path
    }

    /// The outline's path for `geometry`.
    public func path(_ geometry: Geometry) -> Path {
        makePath(geometry)
    }

    public static func == (lhs: NookOutline, rhs: NookOutline) -> Bool {
        lhs.id == rhs.id
    }

    /// The built-in outline: eared in the notch form, a convex rounded rectangle with its
    /// radii clamped to the frame when floating.
    public static let standard = NookOutline(id: "opennook.standard") { geometry in
        switch geometry.form {
            case .notch:
                standardNotchPath(
                    in: geometry.rect,
                    topCornerRadius: geometry.topCornerRadius,
                    bottomCornerRadius: geometry.bottomCornerRadius
                )
            case .floating:
                standardFloatingPath(
                    in: geometry.rect,
                    topCornerRadius: geometry.topCornerRadius,
                    bottomCornerRadius: geometry.bottomCornerRadius
                )
        }
    }

    /// The built-in notch-form path, for a custom outline that wants to start from it.
    public static func standardNotchPath(in rect: CGRect, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat)
        -> Path
    {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }

    /// Convex rounded rectangle flush to `rect`, with independent top and bottom corner
    /// radii. No flared ears - this is a panel that floats on its own, not one fused to
    /// a notch. Radii are clamped so they can't overrun a small compact pill.
    public static func standardFloatingPath(in rect: CGRect, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat)
        -> Path
    {
        let limit = min(rect.width, rect.height) / 2
        let rt = max(min(topCornerRadius, limit), 0)
        let rb = max(min(bottomCornerRadius, limit), 0)

        var path = Path()

        path.move(to: CGPoint(x: rect.minX + rt, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rt, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rt),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rb))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rb, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.minX + rb, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - rb),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rt))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rt, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
