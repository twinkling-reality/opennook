// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// How a shared element is drawn while it moves between the pill, the peek, and the expanded
/// content.
public enum NookSharedElementStyle: Sendable {
    /// Laid out at each in-between frame: right for artwork, images, and shapes. The default.
    case resize
    /// Laid out once at its destination size and scaled: right for text and numbers, which
    /// would otherwise rewrap mid-move.
    case scale
}

extension View {
    /// Marks this view as a shared element: when the nook moves between the compact pill, the
    /// peek, and the expanded content, and a view with the same `id` is on the other side, the
    /// element moves from where it was to where it lands instead of leaving and arriving with
    /// its slot.
    ///
    /// ```swift
    /// // In the compact leading slot:
    /// CoverArt(track).frame(width: 20, height: 20).nookSharedElement("cover")
    /// // In the expanded content:
    /// CoverArt(track).frame(width: 156, height: 156).nookSharedElement("cover")
    /// ```
    ///
    /// The element draws in place, exactly as it would without the modifier, until the nook
    /// moves. Then the copy on the far side is drawn moving from the old frame to the new one,
    /// on the chrome's own curve, inside the chrome's shape, and lands in place. Everything
    /// around it keeps its own transition. While the pill peeks, an element in both the pill
    /// and the peek shows in the peek only.
    ///
    /// Use the same view on both sides, at different sizes, for a seamless move; two different
    /// views cross-fade inside the moving frame. The moving copy is a second instance of the
    /// view with the same environment, so keep its state in a model rather than in `@State`.
    /// Ids are matched within ``EnvironmentValues/nookSharedElementScope``. With Reduce Motion
    /// on, nothing moves: each copy comes and goes with its slot.
    ///
    /// Outside a nook's pill, peek, and expanded content (in a companion, say), the modifier
    /// does nothing.
    public func nookSharedElement(_ id: String, style: NookSharedElementStyle = .resize) -> some View {
        NookSharedElementView(id: id, style: style, content: self)
    }
}

extension EnvironmentValues {
    /// The scope shared element ids are matched in. NookKit sets it to the module that supplied
    /// the view, so two modules can both have a "cover". A host using `NookSurface` alone can
    /// leave it empty, the default.
    @Entry public var nookSharedElementScope: String = ""

    /// Which part of the chrome a view is in, for shared elements. `nil` outside the chrome.
    @Entry var nookSharedElementRegion: NookSharedElementRegion? = nil

    /// The nook's shared element bookkeeping. `nil` outside the chrome.
    @Entry var nookSharedElements: NookSharedElementCoordinator? = nil
}

/// The parts of the chrome a shared element can be in.
enum NookSharedElementRegion: Hashable, Sendable {
    case compact
    case peek
    case expanded
    /// The moving copy itself, which registers nothing.
    case flight

    /// The part of the chrome on screen for a surface in `state`, peeking or not. `nil` while
    /// hidden.
    static func onScreen(state: NookState, isPeeking: Bool) -> NookSharedElementRegion? {
        switch state {
            case .expanded: .expanded
            case .compact: isPeeking ? .peek : .compact
            case .hidden: nil
        }
    }
}

/// A shared element as it was drawn: its key, part of the chrome, bounds, and a copy of the
/// view for the moving element.
struct NookSharedElementRecord {
    let key: String
    let region: NookSharedElementRegion
    let anchor: Anchor<CGRect>
    let content: AnyView
    let style: NookSharedElementStyle
}

/// A shared element where the chrome laid it out, in the chrome's coordinates.
struct NookSharedElementDrawn {
    let key: String
    let region: NookSharedElementRegion
    let frame: CGRect
    let content: AnyView
    let style: NookSharedElementStyle
}

struct NookSharedElementRecordsKey: PreferenceKey {
    static var defaultValue: [NookSharedElementRecord] { [] }

    static func reduce(value: inout [NookSharedElementRecord], nextValue: () -> [NookSharedElementRecord]) {
        value.append(contentsOf: nextValue())
    }
}

/// Keeps track of where each shared element was drawn and which ones are moving.
///
/// The surface tells it when the part of the chrome on screen changes, inside the same
/// transaction as the change. It answers which copies to hide, and the flight layer draws the
/// moving ones.
@MainActor
final class NookSharedElementCoordinator: ObservableObject {
    /// One move between two parts of the chrome.
    struct Transition: Equatable {
        let generation: Int
        let from: NookSharedElementRegion
        let to: NookSharedElementRegion
        /// Where each element was in `from` when the move began, by key.
        let sources: [String: CGRect]
        /// The elements that also have a copy in `to`, and so fly.
        var matched: Set<String> = []
        /// The elements whose flight has landed.
        var landed: Set<String> = []

        /// Whether the element `key` is still on its way.
        func isMoving(_ key: String) -> Bool {
            sources[key] != nil && !landed.contains(key)
        }
    }

    /// How long a move can take before it is called done, landed or not: Apple's ceiling for
    /// an island animation, with room to spare.
    static let longestMove: Duration = .seconds(2)

    @Published private(set) var transition: Transition?
    /// The parts of the chrome each element has a copy in, by key.
    @Published private(set) var presence: [String: Set<NookSharedElementRegion>] = [:]
    /// The curve the current move rides.
    private(set) var animation: Animation = .default
    /// The part of the chrome on screen.
    private(set) var region: NookSharedElementRegion?
    /// With Reduce Motion on, nothing moves.
    var reduceMotion = false

    /// Where each element was last drawn, by key and part of the chrome. Written by the flight
    /// layer as the chrome lays out; never published.
    private(set) var frames: [String: [NookSharedElementRegion: CGRect]] = [:]
    private var generation = 0
    private var pendingPublish = false
    private var pending: (presence: [String: Set<NookSharedElementRegion>], matched: Set<String>?)?

    /// `true` while an element is drawn in the part of the chrome on screen: the surface then
    /// converts without dipping through hidden, so the element can move.
    var holdsElements: Bool {
        guard let region else { return false }
        return frames.values.contains { $0[region] != nil }
    }

    /// The part of the chrome on screen is about to become `newRegion`, moving on `animation`.
    /// Called inside the transaction of the change.
    func surfaceWillMove(to newRegion: NookSharedElementRegion?, animation: Animation) {
        let old = region
        guard old != newRegion else { return }
        region = newRegion
        guard let newRegion else {
            // Hidden: the window may be rebuilt before it shows again, so nothing carries over.
            frames = [:]
            transition = nil
            presence = [:]
            return
        }
        guard let old, !reduceMotion else {
            transition = nil
            return
        }
        var sources: [String: CGRect] = [:]
        for (key, regions) in frames {
            if let frame = regions[old] { sources[key] = frame }
        }
        // An element still on its way keeps flying, from wherever it is now.
        if let previous = transition {
            for (key, frame) in previous.sources where previous.isMoving(key) && sources[key] == nil {
                sources[key] = frame
            }
        }
        generation += 1
        self.animation = animation
        transition =
            sources.isEmpty ? nil : Transition(generation: generation, from: old, to: newRegion, sources: sources)
        let ending = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.longestMove)
            guard let self, self.transition?.generation == ending else { return }
            self.transition = nil
        }
    }

    /// Whether the copy of `key` in `region` stays out of sight: while it is the destination
    /// of a move, while it is the source of one that has a destination, and at rest when the
    /// part of the chrome on screen has its own copy.
    func isHidden(_ key: String, in region: NookSharedElementRegion) -> Bool {
        guard region != .flight else { return false }
        if let transition, transition.isMoving(key) {
            if region == transition.to { return true }
            if region == transition.from, transition.matched.contains(key) { return true }
        }
        if let current = self.region, region != current, presence[key]?.contains(current) == true {
            return true
        }
        return false
    }

    /// The moves to draw for the elements as they are laid out now: each element of the current
    /// move that has a copy in its destination, flying to that copy's frame.
    func flights(for drawn: [NookSharedElementDrawn]) -> [NookSharedElementFlight.Plan] {
        guard let transition else { return [] }
        return drawn.compactMap { element in
            guard element.region == transition.to, transition.isMoving(element.key),
                let start = transition.sources[element.key]
            else { return nil }
            return NookSharedElementFlight.Plan(
                key: element.key,
                generation: transition.generation,
                start: start,
                target: element.frame,
                content: element.content,
                style: element.style
            )
        }
    }

    /// Notes where each element is drawn now. Called by the flight layer as the chrome lays
    /// out; what the views observe changes on the next turn of the run loop, never during the
    /// layout itself.
    func record(_ drawn: [NookSharedElementDrawn]) {
        var frames: [String: [NookSharedElementRegion: CGRect]] = [:]
        var presence: [String: Set<NookSharedElementRegion>] = [:]
        for element in drawn where element.region != .flight {
            frames[element.key, default: [:]][element.region] = element.frame
            presence[element.key, default: []].insert(element.region)
        }
        self.frames = frames
        var matched: Set<String>?
        if let transition {
            let found = Set(transition.sources.keys.filter { presence[$0]?.contains(transition.to) == true })
            if found != transition.matched { matched = found }
        }
        guard presence != self.presence || matched != nil else { return }
        pending = (presence, matched)
        guard !pendingPublish else { return }
        pendingPublish = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingPublish = false
            guard let pending = self.pending else { return }
            self.pending = nil
            if pending.presence != self.presence { self.presence = pending.presence }
            if let matched = pending.matched, self.transition != nil, self.transition?.matched != matched {
                self.transition?.matched = matched
            }
        }
    }

    /// The flight of `key` in the move `generation` landed.
    func land(_ key: String, generation: Int) {
        guard var transition, transition.generation == generation, !transition.landed.contains(key) else { return }
        transition.landed.insert(key)
        if transition.matched.isSubset(of: transition.landed), !transition.matched.isEmpty {
            self.transition = nil
        } else {
            self.transition = transition
        }
    }
}

/// A view marked with ``SwiftUI/View/nookSharedElement(_:style:)``.
struct NookSharedElementView<Content: View>: View {
    let id: String
    let style: NookSharedElementStyle
    let content: Content

    @Environment(\.nookSharedElementRegion) private var region
    @Environment(\.nookSharedElementScope) private var scope
    @Environment(\.nookSharedElements) private var coordinator

    var body: some View {
        if let region, region != .flight, let coordinator {
            NookSharedElementBody(
                key: scope.isEmpty ? id : "\(scope)/\(id)",
                region: region,
                style: style,
                content: content,
                coordinator: coordinator
            )
        } else {
            content
        }
    }
}

/// A shared element in the chrome: drawn in place, out of sight while its copy elsewhere is
/// the one showing or moving, and reported to the flight layer.
private struct NookSharedElementBody<Content: View>: View {
    let key: String
    let region: NookSharedElementRegion
    let style: NookSharedElementStyle
    let content: Content
    @ObservedObject var coordinator: NookSharedElementCoordinator

    @Environment(\.self) private var environment

    var body: some View {
        let hidden = coordinator.isHidden(key, in: region)
        // The moving copy carries this copy's environment, marked as the flight so it
        // registers nothing itself.
        let copy = AnyView(content.environment(\.nookSharedElementRegion, .flight).environment(\.self, environment))
        content
            .opacity(hidden ? 0 : 1)
            .animation(nil, value: hidden)
            .anchorPreference(key: NookSharedElementRecordsKey.self, value: .bounds) { anchor in
                [NookSharedElementRecord(key: key, region: region, anchor: anchor, content: copy, style: style)]
            }
    }
}

/// Draws the shared elements that are moving, above the chrome's content and inside its shape.
struct NookSharedElementLayer: View {
    let records: [NookSharedElementRecord]
    @ObservedObject var coordinator: NookSharedElementCoordinator

    var body: some View {
        GeometryReader { proxy in
            // Frames are kept in the window's coordinates: the chrome's own bounds change size and
            // place from one state to the next, but the window does not, so a frame noted in the
            // pill still says where the element was once the panel has taken over.
            let origin = proxy.frame(in: .global).origin
            let drawn = records.map { record in
                NookSharedElementDrawn(
                    key: record.key,
                    region: record.region,
                    frame: proxy[record.anchor].offsetBy(dx: origin.x, dy: origin.y),
                    content: record.content,
                    style: record.style
                )
            }
            let flights = coordinator.flights(for: drawn)
            let _ = coordinator.record(drawn)
            ZStack(alignment: .topLeading) {
                ForEach(flights, id: \.key) { plan in
                    NookSharedElementFlight(plan: plan, origin: origin, animation: coordinator.animation) {
                        key,
                        generation in
                        coordinator.land(key, generation: generation)
                    }
                    // The element is already on screen: it neither fades in nor out.
                    .transition(.identity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One shared element on its way: drawn at its start frame, then moved to its target on the
/// move's curve. A new target (the nook changed course) moves it on from where it is.
struct NookSharedElementFlight: View {
    struct Plan {
        let key: String
        let generation: Int
        let start: CGRect
        let target: CGRect
        let content: AnyView
        let style: NookSharedElementStyle
    }

    let plan: Plan
    /// Where the layer sits in the window: plans are in window coordinates.
    let origin: CGPoint
    let animation: Animation
    let land: @MainActor (String, Int) -> Void

    @State private var frame: CGRect?

    var body: some View {
        let rect = (frame ?? plan.start).offsetBy(dx: -origin.x, dy: -origin.y)
        placed(rect)
            .onAppear(perform: fly)
            .onChange(of: plan.target) { fly() }
            .onChange(of: plan.generation) { fly() }
    }

    private func fly() {
        let key = plan.key
        let generation = plan.generation
        let land = land
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            frame = plan.target
        } completion: {
            land(key, generation)
        }
    }

    @ViewBuilder
    private func placed(_ rect: CGRect) -> some View {
        switch plan.style {
            case .resize:
                plan.content
                    .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                    .position(x: rect.midX, y: rect.midY)
            case .scale:
                let target = plan.target.offsetBy(dx: -origin.x, dy: -origin.y)
                let scaleX: CGFloat = target.width > 0 ? rect.width / target.width : 1
                let scaleY: CGFloat = target.height > 0 ? rect.height / target.height : 1
                plan.content
                    .frame(width: max(target.width, 0), height: max(target.height, 0))
                    .scaleEffect(x: scaleX, y: scaleY)
                    .position(x: rect.midX, y: rect.midY)
        }
    }
}
