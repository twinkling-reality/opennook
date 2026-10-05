// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin

import SwiftUI

/// A SwiftUI preference that lets *any* expanded content propagate a single ambient color
/// up to the surface backdrop.
///
/// This is a product-agnostic presentation seam: the engine knows nothing about *why* a
/// color was chosen or *which* view chose it. Content sets the preference (directly with
/// `.preference(key:value:)`, or via a layer that wraps it); the surface reads it and
/// paints a soft wash behind the whole expanded chrome, including edge and safe-area
/// padding, so the wash is not clipped to the content's own bounds.
///
/// When several views in the content tree set a value, the last non-nil value wins.
public struct NookAmbientColorPreferenceKey: PreferenceKey {
    public static var defaultValue: Color? { nil }

    public static func reduce(value: inout Color?, nextValue: () -> Color?) {
        value = nextValue() ?? value
    }
}

/// The shape of the ambient wash: how strongly the ambient color shows at each point of a
/// linear gradient across the expanded chrome. Set it on ``Nook/ambientWash``.
///
/// ``standard`` is the built-in wash: strongest at the top where the chrome meets the notch,
/// thinning toward the bottom.
///
/// ```swift
/// nook.ambientWash = NookAmbientWash(opacities: [0.5, 0], startPoint: .top, endPoint: .center)
/// ```
public struct NookAmbientWash: Equatable, Sendable {
    /// One point of the wash: the ambient color at `opacity`, `location` of the way along
    /// the gradient.
    public struct Stop: Equatable, Sendable {
        /// 0...1 opacity the ambient color is painted at.
        public var opacity: Double
        /// 0...1 position along the gradient.
        public var location: CGFloat

        public init(opacity: Double, location: CGFloat) {
            self.opacity = min(max(opacity, 0), 1)
            self.location = location
        }
    }

    /// The wash's stops, in order. Empty draws nothing.
    public var stops: [Stop]
    /// Where the gradient begins. The top edge by default.
    public var startPoint: UnitPoint
    /// Where the gradient ends. The bottom edge by default.
    public var endPoint: UnitPoint

    public init(stops: [Stop], startPoint: UnitPoint = .top, endPoint: UnitPoint = .bottom) {
        self.stops = stops
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// A wash through `opacities` spaced evenly from `startPoint` to `endPoint`.
    public init(opacities: [Double], startPoint: UnitPoint = .top, endPoint: UnitPoint = .bottom) {
        let last = CGFloat(max(opacities.count - 1, 1))
        self.init(
            stops: opacities.enumerated().map { index, opacity in
                Stop(opacity: opacity, location: opacities.count == 1 ? 0 : CGFloat(index) / last)
            },
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// The built-in wash: 34%, 16%, 6%, then 2% of the ambient color, top to bottom.
    public static let standard = NookAmbientWash(opacities: [0.34, 0.16, 0.06, 0.02])

    /// The gradient this wash paints in `color`.
    func gradient(for color: Color) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: color.opacity($0.opacity), location: $0.location) })
    }
}

/// A wash rendered behind expanded surface content when a `NookAmbientColorPreferenceKey`
/// value is present, shaped by a ``NookAmbientWash``. Purely decorative and non-interactive -
/// the engine draws it but does not interpret it.
public struct NookAmbientColorBackground: View {
    let color: Color
    let wash: NookAmbientWash

    public init(color: Color, wash: NookAmbientWash = .standard) {
        self.color = color
        self.wash = wash
    }

    public var body: some View {
        LinearGradient(
            gradient: wash.gradient(for: color),
            startPoint: wash.startPoint,
            endPoint: wash.endPoint
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Propagates an ambient color up to the surface backdrop via
    /// ``NookAmbientColorPreferenceKey``. Pass `nil` to contribute nothing.
    ///
    /// This is the generic seam. Product layers may wrap it to attach their own
    /// semantics (e.g. "the home screen's theme color").
    public func nookAmbientColor(_ color: Color?) -> some View {
        preference(key: NookAmbientColorPreferenceKey.self, value: color)
    }
}
