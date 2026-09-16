// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// Where a companion surface sits relative to the nook chrome.
///
/// A companion is placed against the chrome's *body* - the visible panel, not the notch
/// ears that flare into the menu bar - so the gap a host asks for is the gap the user sees
/// in both the notch and the floating form.
///
/// Companions that share an anchor form one row, in registration order. A ``Edge/below``
/// row runs left to right under the chrome; a ``Edge/leading`` or ``Edge/trailing`` row
/// runs outward from the chrome's side, the first companion nearest the chrome.
public struct NookCompanionAnchor: Hashable, Sendable {
    /// The side of the chrome a companion row hangs from.
    public enum Edge: Hashable, Sendable {
        /// Under the chrome's bottom edge.
        case below
        /// Beside the chrome's leading edge, extending outward.
        case leading
        /// Beside the chrome's trailing edge, extending outward.
        case trailing
    }

    /// Where a companion row sits along the chrome edge it hangs from.
    public enum Alignment: Hashable, Sendable {
        /// The leading end of the bottom edge, or the top of a side edge.
        case start
        /// The middle of the edge.
        case center
        /// The trailing end of the bottom edge, or the bottom of a side edge.
        case end
    }

    /// The chrome edge the row hangs from.
    public var edge: Edge

    /// Where the row sits along ``edge``.
    public var alignment: Alignment

    public init(edge: Edge, alignment: Alignment = .center) {
        self.edge = edge
        self.alignment = alignment
    }

    /// Centered under the chrome. The default anchor.
    public static let below = NookCompanionAnchor(edge: .below)

    /// Beside the chrome's leading edge, vertically centered on it.
    public static let leading = NookCompanionAnchor(edge: .leading)

    /// Beside the chrome's trailing edge, vertically centered on it.
    public static let trailing = NookCompanionAnchor(edge: .trailing)

    /// Under the chrome, at `alignment` along its bottom edge.
    public static func below(alignment: Alignment) -> NookCompanionAnchor {
        NookCompanionAnchor(edge: .below, alignment: alignment)
    }

    /// Beside the chrome's leading edge, at `alignment` along it.
    public static func leading(alignment: Alignment) -> NookCompanionAnchor {
        NookCompanionAnchor(edge: .leading, alignment: alignment)
    }

    /// Beside the chrome's trailing edge, at `alignment` along it.
    public static func trailing(alignment: Alignment) -> NookCompanionAnchor {
        NookCompanionAnchor(edge: .trailing, alignment: alignment)
    }
}

/// The nook states a companion surface is shown in.
///
/// A companion that is not shown in the current state stays mounted but folds into the
/// chrome edge it hangs from, so it rides the chrome's expand and collapse instead of
/// popping in once the animation has finished.
public struct NookCompanionVisibility: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Shown beside the compact pill.
    public static let compact = NookCompanionVisibility(rawValue: 1 << 0)

    /// Shown beside the expanded surface.
    public static let expanded = NookCompanionVisibility(rawValue: 1 << 1)

    /// Shown in both the compact and the expanded state.
    public static let both: NookCompanionVisibility = [.compact, .expanded]

    /// Whether a companion with this visibility is shown while the chrome is in `state`.
    /// Never `true` for ``NookState/hidden``: there is no chrome to anchor to.
    public func includes(_ state: NookState) -> Bool {
        switch state {
            case .compact: return contains(.compact)
            case .expanded: return contains(.expanded)
            case .hidden: return false
        }
    }
}

/// The outline a companion surface is filled and hit-tested with.
public enum NookCompanionShape: Hashable, Sendable {
    /// A capsule - the pill shape. The default.
    case capsule

    /// A circle. The surface is squared to the larger of its content's width and height,
    /// so the content sits centered in a true circle rather than an ellipse.
    case circle

    /// A rectangle with continuous rounded corners.
    case roundedRectangle(cornerRadius: CGFloat)
}

/// What a companion surface paints behind its content.
public enum NookCompanionBackdrop: Equatable, Sendable {
    /// The chrome's own ``Nook/backdrop`` - solid, vibrancy, or Liquid Glass - so the
    /// companion reads as part of the same surface and follows the user's appearance
    /// settings. The default.
    case inherit

    /// A backdrop of the companion's own, independent of the chrome's.
    case custom(NookBackdrop)

    /// Nothing. The content draws its own background.
    case none

    /// The backdrop to paint, given the chrome's current one. `nil` paints nothing.
    public func resolved(inheriting chromeBackdrop: NookBackdrop) -> NookBackdrop? {
        switch self {
            case .inherit: return chromeBackdrop
            case .custom(let backdrop): return backdrop
            case .none: return nil
        }
    }
}

/// A host view floated beside the nook chrome and anchored to it - an action pill under the
/// expanded panel, a round button beside the compact pill.
///
/// Companions render inside the chrome's own panel, laid out against the chrome's frame.
/// That is what keeps them in step with the surface: they ride the same expand and collapse
/// animation, follow the chrome through every ``NookPresentation`` and onto every display,
/// share its backdrop and window appearance, and clicking one can never move focus away
/// from the nook, because it is the same non-activating panel. The pointer moving from the
/// chrome onto a companion is one continuous hover, so the nook does not collapse under it.
///
/// Set companions on ``Nook/companions``. Their content stays mounted for as long as the
/// panel exists and folds away in states it is not shown in: read
/// `\.nookCompanionIsPresented` to pause work while hidden, and
/// narrow the states it appears in from inside with
/// `nookCompanionVisibility(_:)`.
///
/// Each companion carries the accessibility identifier ``accessibilityIdentifier``
/// (`opennook.companion.<id>`), alongside the panel's own `opennook.panel`.
public struct NookCompanionSurface: Identifiable {
    /// Stable identity. Keys hover tracking, the SwiftUI identity of the surface, and its
    /// accessibility identifier. Must be unique among a chrome's companions.
    public let id: String

    /// Where the companion sits relative to the chrome.
    public var anchor: NookCompanionAnchor

    /// Gap, in points, between the companion and whatever is on its chrome side: the
    /// chrome itself, or the previous companion in the same row. A `.below` companion
    /// uses it both for its drop under the chrome and for its gap to the companion before
    /// it in the row.
    public var spacing: CGFloat

    /// The chrome states the companion is shown in.
    public var visibility: NookCompanionVisibility

    /// The outline the companion is filled and hit-tested with.
    public var shape: NookCompanionShape

    /// What the companion paints behind its content.
    public var backdrop: NookCompanionBackdrop

    /// A label for the companion as a whole, read by VoiceOver before its contents. `nil`
    /// leaves the group unlabeled so VoiceOver reads the contents directly.
    public var accessibilityLabel: String?

    /// The companion's content.
    public var content: AnyView

    @MainActor
    public init<Content: View>(
        id: String,
        anchor: NookCompanionAnchor = .below,
        spacing: CGFloat = NookCompanionSurface.defaultSpacing,
        visibility: NookCompanionVisibility = .expanded,
        shape: NookCompanionShape = .capsule,
        backdrop: NookCompanionBackdrop = .inherit,
        accessibilityLabel: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.anchor = anchor
        self.spacing = spacing
        self.visibility = visibility
        self.shape = shape
        self.backdrop = backdrop
        self.accessibilityLabel = accessibilityLabel
        self.content = AnyView(content())
    }

    /// The default gap between a companion and the chrome - the same 8 pt the chrome
    /// leaves around its own expanded content.
    public static let defaultSpacing: CGFloat = 8

    /// The accessibility identifier the chrome stamps on a companion with `id`.
    public static func accessibilityIdentifier(for id: String) -> String {
        "opennook.companion.\(id)"
    }

    /// The accessibility identifier the chrome stamps on this companion.
    public var accessibilityIdentifier: String {
        Self.accessibilityIdentifier(for: id)
    }
}

// MARK: - Content-driven visibility

/// Carries the visibility a companion's content narrowed itself to. Internal: content sets it
/// through `nookCompanionVisibility(_:)`, and the companion surface reads and
/// consumes it, so it never leaks past the companion that owns it.
struct NookCompanionVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: NookCompanionVisibility? { nil }

    /// Sibling restrictions intersect: a companion shows only in states every part of its
    /// content allows.
    static func reduce(value: inout NookCompanionVisibility?, nextValue: () -> NookCompanionVisibility?) {
        value = combine(value, nextValue())
    }

    static func combine(
        _ lhs: NookCompanionVisibility?,
        _ rhs: NookCompanionVisibility?
    ) -> NookCompanionVisibility? {
        switch (lhs, rhs) {
            case (let lhs?, let rhs?): return lhs.intersection(rhs)
            case (let lhs?, nil): return lhs
            case (nil, let rhs): return rhs
        }
    }
}

extension View {
    /// Narrows the chrome states the enclosing companion surface is shown in, from inside the
    /// companion's own content - for a companion whose presence depends on host state, like
    /// a "Show results" pill that appears once there are results.
    ///
    /// The effective visibility is the companion's registered visibility intersected with
    /// every restriction its content applies, so this can only hide a companion, never show
    /// it in a state it was not registered for. Changes animate like a chrome state change.
    ///
    /// ```swift
    /// SleepTimerButton()
    ///     .nookCompanionVisibility(timer.isRunning ? .both : .expanded)
    /// ```
    ///
    /// Outside a companion surface this has no effect.
    public func nookCompanionVisibility(_ visibility: NookCompanionVisibility) -> some View {
        transformPreference(NookCompanionVisibilityPreferenceKey.self) { value in
            value = NookCompanionVisibilityPreferenceKey.combine(value, visibility)
        }
    }

    /// Hides the enclosing companion surface while `hidden` is `true`. Shorthand for
    /// ``nookCompanionVisibility(_:)`` with an empty visibility.
    public func nookCompanionHidden(_ hidden: Bool = true) -> some View {
        nookCompanionVisibility(hidden ? [] : .both)
    }
}

private struct NookCompanionIsPresentedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `true` while the enclosing companion surface is shown. Companion content stays mounted
    /// in chrome states it is not shown in, so read this to pause timers or animations while
    /// it is folded away. Always `true` outside a companion surface.
    public var nookCompanionIsPresented: Bool {
        get { self[NookCompanionIsPresentedKey.self] }
        set { self[NookCompanionIsPresentedKey.self] = newValue }
    }
}
