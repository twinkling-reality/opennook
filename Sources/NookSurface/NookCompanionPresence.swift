// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// How a companion appears and disappears: when the chrome changes state, when its content
/// narrows its visibility, and when it is added or removed.
///
/// ```swift
/// configuration.companionPresence = .slide
/// configuration.addCompanion(id: "badge", presence: .pop.animation(.bouncy)) { Badge() }
/// ```
///
/// Under Reduce Motion every effect becomes a plain fade.
public struct NookCompanionPresence: Equatable, Sendable {
    /// The movement a companion makes on its way out, and reverses on its way in.
    public enum Effect: Hashable, Sendable {
        /// Shrinks toward the chrome edge and blurs as it fades. The default.
        case fold(scale: CGFloat, blur: CGFloat)
        /// Fades in place.
        case fade
        /// Slides back toward the chrome as it fades.
        case slide(distance: CGFloat)
        /// Shrinks toward its own center as it fades.
        case pop(scale: CGFloat)
    }

    public var effect: Effect

    /// The curve the companion appears and disappears on. `nil` uses the curve of whatever
    /// caused it: the chrome's expand and collapse curve for a state change, and for a companion
    /// added or removed, the curve the change was made with, or the chrome's curve for a change
    /// made without one.
    public var animation: Animation?

    public init(effect: Effect, animation: Animation? = nil) {
        self.effect = effect
        self.animation = animation
    }

    /// This presence on a curve of its own.
    public func animation(_ animation: Animation?) -> NookCompanionPresence {
        var presence = self
        presence.animation = animation
        return presence
    }

    /// Shrinks toward the chrome edge and blurs as it fades. The default.
    public static let fold = NookCompanionPresence(effect: .fold(scale: 0.6, blur: 6))

    /// Fades in place.
    public static let fade = NookCompanionPresence(effect: .fade)

    /// Slides back toward the chrome as it fades.
    public static let slide = NookCompanionPresence(effect: .slide(distance: 14))

    /// Shrinks toward its own center as it fades.
    public static let pop = NookCompanionPresence(effect: .pop(scale: 0.3))

    /// The effect as a transition, for a companion being added or removed.
    func transition(edge: NookCompanionAnchor.Edge, reduceMotion: Bool) -> AnyTransition {
        .modifier(
            active: NookCompanionPresenceModifier(
                presence: self,
                isPresented: false,
                edge: edge,
                reduceMotion: reduceMotion
            ),
            identity: NookCompanionPresenceModifier(
                presence: self,
                isPresented: true,
                edge: edge,
                reduceMotion: reduceMotion
            )
        )
    }
}

/// Applies a ``NookCompanionPresence`` to a companion that stays mounted while it is hidden.
struct NookCompanionPresenceModifier: ViewModifier {
    let presence: NookCompanionPresence
    let isPresented: Bool
    let edge: NookCompanionAnchor.Edge
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let transform = Self.transform(
            for: presence.effect,
            isPresented: isPresented,
            edge: edge,
            reduceMotion: reduceMotion
        )
        content
            .scaleEffect(transform.scale, anchor: transform.scaleAnchor)
            .offset(transform.offset)
            .blur(radius: transform.blur)
            .opacity(isPresented ? 1 : 0)
    }

    /// Where a hidden companion waits, relative to where it is shown.
    struct Transform: Equatable {
        var scale: CGFloat = 1
        var scaleAnchor: UnitPoint = .center
        var offset: CGSize = .zero
        var blur: CGFloat = 0
    }

    /// The transform for `effect`: none while the companion is shown, or under Reduce Motion, where
    /// only the fade is left.
    static func transform(
        for effect: NookCompanionPresence.Effect,
        isPresented: Bool,
        edge: NookCompanionAnchor.Edge,
        reduceMotion: Bool
    ) -> Transform {
        guard !isPresented, !reduceMotion else { return Transform() }
        switch effect {
            case .fold(let scale, let blur):
                return Transform(scale: scale, scaleAnchor: edge.foldAnchor, blur: blur)
            case .fade:
                return Transform()
            case .slide(let distance):
                return Transform(offset: towardChrome(distance, from: edge))
            case .pop(let scale):
                return Transform(scale: scale)
        }
    }

    private static func towardChrome(_ distance: CGFloat, from edge: NookCompanionAnchor.Edge) -> CGSize {
        switch edge {
            case .below: CGSize(width: 0, height: -distance)
            case .leading: CGSize(width: distance, height: 0)
            case .trailing: CGSize(width: -distance, height: 0)
        }
    }
}
