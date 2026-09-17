// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import SwiftUI

/// The notch chrome itself: arches around the menu-bar notch, switches between expanded and
/// compact-with-side-slots, and paints the configured backdrop behind both.
struct NookView<Expanded, CompactLeading, CompactTrailing>: View
where Expanded: View, CompactLeading: View, CompactTrailing: View {
    @ObservedObject private var nook: Nook<Expanded, CompactLeading, CompactTrailing>
    @State private var compactLeadingWidth: CGFloat = 0
    @State private var compactTrailingWidth: CGFloat = 0
    @State private var trackedExpandedSize: CGSize = .zero
    @State private var ambientColor: Color?
    @State private var rimColor: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(nook: Nook<Expanded, CompactLeading, CompactTrailing>) {
        self.nook = nook
    }

    /// Safe-area strip the chrome reserves around the host's expanded content. Host-
    /// configurable per edge via ``NookStyle/expandedContentInsets``; the default
    /// reproduces the historical fixed geometry (0 top, 8 elsewhere).
    private var expandedContentInsets: NookEdgeInsets {
        nook.style.expandedContentInsets
    }

    /// `true` when the surface should render the free-floating panel instead of the
    /// notch-fused shape - a display with no notch, or a forced `.floating` presentation.
    private var isFloating: Bool {
        nook.layoutForm == .floating
    }

    /// Residual safe-area insets the host's expanded view can read via
    /// ``EnvironmentValues/nookContentInsets``. `.zero` while compact or hidden -
    /// no host expanded content is rendered in those states. The expanded value
    /// is the geometric clearance left over after the chrome's own paddings;
    /// see ``NookContentInsets/expanded(form:topCornerRadius:bottomCornerRadius:chromeSafeAreaInset:)``.
    private var contentInsets: NookContentInsets {
        guard nook.state == .expanded else { return .zero }
        return NookContentInsets.expanded(
            form: nook.layoutForm,
            topCornerRadius: nook.style.topCornerRadius,
            bottomCornerRadius: nook.style.bottomCornerRadius,
            chromeSafeAreaInsets: expandedContentInsets
        )
    }

    /// Where the hardware notch falls in the host's expanded view, read through
    /// ``EnvironmentValues/nookNotchCutout``. `.none` in the floating form and whenever the
    /// surface is not expanded.
    private var notchCutout: NookNotchCutout {
        guard nook.state == .expanded else { return .none }
        return NookNotchCutout.expanded(
            form: nook.layoutForm,
            notchSize: nook.notchSize,
            chromeSafeAreaInsets: expandedContentInsets
        )
    }

    private var expandedCornerRadii: (top: CGFloat, bottom: CGFloat) {
        (top: nook.style.topCornerRadius, bottom: nook.style.bottomCornerRadius)
    }

    private var compactCornerRadii: (top: CGFloat, bottom: CGFloat) {
        (top: 6, bottom: 14)
    }

    /// Floating panels use convex corners - a card when expanded, a capsule when
    /// compact (radius = half the pill height). No notch ears to fuse, so the same
    /// radius applies to all four corners.
    private var floatingExpandedRadius: CGFloat { expandedCornerRadii.bottom }
    private var floatingCompactRadius: CGFloat { max(nook.notchSize.height / 2, 8) }

    /// Vertical gap that drops the floating panel clear of the menu bar. Zero in notch
    /// mode, where the chrome is meant to sit flush against the top edge.
    private var floatingTopInset: CGFloat {
        isFloating ? nook.menubarHeight + 8 : 0
    }

    private var minWidth: CGFloat {
        // A floating panel is purely content-driven; only the notch shape needs a
        // minimum (the notch gap plus its ears).
        isFloating ? 0 : nook.notchSize.width + (topCornerRadius * 2)
    }

    private var topCornerRadius: CGFloat {
        if isFloating {
            return nook.state == .expanded ? floatingExpandedRadius : floatingCompactRadius
        }
        return nook.state == .expanded ? expandedCornerRadii.top : compactCornerRadii.top
    }

    private var bottomCornerRadius: CGFloat {
        if isFloating {
            return nook.state == .expanded ? floatingExpandedRadius : floatingCompactRadius
        }
        return nook.state == .expanded ? expandedCornerRadii.bottom : compactCornerRadii.bottom
    }

    /// In compact mode, slot-width asymmetry shifts the whole shape so the gap stays centered on the notch.
    private var xOffset: CGFloat {
        nook.state == .compact ? compactXOffset : 0
    }

    /// Notch mode re-centers the shape on the physical notch when the leading/trailing
    /// slots differ in width. A floating pill has no notch to center on, so it stays put.
    private var compactXOffset: CGFloat {
        isFloating ? 0 : (compactTrailingWidth - compactLeadingWidth) / 2
    }

    /// Backdrop sits behind chrome content, both flattened into a single layer, then clipped
    /// to the animatable notch shape. Compositing as one group means the spring animation can
    /// scale content + backdrop atomically - no magic overshoot padding required to plug
    /// edge gaps mid-bounce.
    ///
    /// The matching `.contentShape(NookShape)` is critical: `.clipShape` only clips drawing,
    /// not hit-testing. Without it, the hover region falls back to the rectangular bounds -
    /// which extend down into the would-be-expanded area because the expanded content's
    /// `.fixedSize()` doesn't actually collapse to 0×0 when wrapped in a max-frame. Result:
    /// hovering in the empty space below a compact nook triggers the hover-grow animation.
    /// Hit-testing the same `NookShape` we render confines hover to the visible chrome.
    ///
    /// Companion surfaces are an overlay applied *after* the clip and the content shape, so
    /// they are neither clipped to the chrome nor folded into its hover region; they report
    /// their own hover, which the nook combines with the chrome's (see
    /// `Nook+Companions.swift`). Applied *before* the offset and the floating inset, so they
    /// move with the chrome. The rim glow's line sits inside the compositing group, where
    /// the clip turns a centered stroke into an inner edge; its halo sits behind the
    /// clipped chrome, where it can spill past the edge.
    var body: some View {
        notchContent()
            .background { NookBackdropFill(backdrop: nook.backdrop, shape: notchShape) }
            .overlay { rimLine() }
            .overlay { feedbackOverlay() }
            .compositingGroup()
            .clipShape(notchShape)
            .background { rimHalo() }
            .contentShape(notchShape)
            .onHover(perform: nook.updateChromeHoverState)
            .overlay { companionLayer() }
            .offset(x: xOffset)
            // Floating mode drops the panel below the menu bar; notch mode keeps it
            // flush to the top edge (inset 0). Applied outside the clipped chrome so it
            // shifts the whole shape without distorting it or the hover region.
            .padding(.top, floatingTopInset)
            // Read above the companion overlay, so compact, expanded, and companion content
            // can all light the rim.
            .onPreferenceChange(NookRimGlowPreferenceKey.self) { color in
                withAnimation(Self.rimAnimation) { rimColor = color }
            }
            .animation(nook.effectiveConversionAnimation, value: nook.state)
            .animation(nook.effectiveConversionAnimation, value: [compactLeadingWidth, compactTrailingWidth])
            .environment(\.nookHasKeyboardFocus, nook.hasKeyboardFocus)
    }

    /// Peripheral cue overlay. Sits above backdrop+content but inside the compositing group,
    /// so the shimmer stroke flattens with the chrome before the notch shape carves the visible
    /// region - no edge gaps mid-bounce, no spillover beyond the arch.
    private func feedbackOverlay() -> some View {
        NookFeedbackOverlay(
            event: nook.feedbackEvent,
            form: nook.layoutForm,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            reduceMotion: reduceMotion
        )
    }

    private var notchShape: NookShape {
        NookShape(
            form: nook.layoutForm,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // MARK: Rim glow

    /// Fades the rim in and out, and between colors. Opacity only, so it is also right under
    /// Reduce Motion.
    private static var rimAnimation: Animation { .easeInOut(duration: 0.3) }

    /// The rim color to draw: whatever content published, else the ambient wash when the
    /// style follows it.
    private var effectiveRimColor: Color? {
        nook.rimGlowStyle.color(rimColor: rimColor, ambientColor: ambientColor)
    }

    private var rimRendering: NookRimGlowRendering {
        NookRimGlowRendering.resolve(
            style: nook.rimGlowStyle,
            reduceMotion: reduceMotion,
            increaseContrast: colorSchemeContrast == .increased,
            reduceTransparency: reduceTransparency
        )
    }

    /// The notch form's top band is fused with the menu bar and the hardware notch, so the
    /// rim fades out across it and rises out of the menu bar instead of outlining it.
    private var rimTopFadeHeight: CGFloat? {
        isFloating ? nil : nook.notchSize.height
    }

    @ViewBuilder
    private func rimLine() -> some View {
        let rendering = rimRendering
        if let color = effectiveRimColor, rendering.lineWidth > 0, rendering.lineOpacity > 0 {
            NookRimLine(shape: notchShape, color: color, rendering: rendering, topFadeHeight: rimTopFadeHeight)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func rimHalo() -> some View {
        let rendering = rimRendering
        if let color = effectiveRimColor, rendering.drawsHalo {
            NookRimHalo(
                shape: notchShape,
                color: color,
                rendering: rendering,
                topFadeHeight: rimTopFadeHeight
            )
            .transition(.opacity)
        }
    }

    // MARK: Companion surfaces

    /// Every companion, laid out around the chrome.
    ///
    /// The layer stays mounted with no companions, so the first one added is an insertion SwiftUI
    /// can animate. Adding or removing a companion animates like any other change to the
    /// surface: on the curve the change was made with, or the chrome's own if it was made
    /// without one, and on the companion's presence curve if it sets one.
    private func companionLayer() -> some View {
        let companions = nook.companions
        let conversionAnimation = nook.effectiveConversionAnimation
        return NookCompanionLayerLayout(
            bodyInset: isFloating ? 0 : topCornerRadius,
            keepsSideRowsBelowTop: !isFloating
        ) {
            ForEach(companions) { surface in
                companionItem(surface)
                    .transition(companionTransition(for: surface))
            }
        }
        .transaction(value: companions.map(\.id)) { transaction in
            if transaction.animation == nil, !transaction.disablesAnimations {
                transaction.animation = conversionAnimation
            }
        }
    }

    private func companionTransition(for surface: NookCompanionSurface) -> AnyTransition {
        let transition = surface.presence.transition(edge: surface.anchor.edge, reduceMotion: reduceMotion)
        guard let animation = surface.presence.animation else { return transition }
        return transition.animation(animation)
    }

    private func companionItem(_ surface: NookCompanionSurface) -> some View {
        let id = surface.id
        return NookCompanionItemView(
            surface: surface,
            chromeState: nook.state,
            backdrop: surface.backdrop.resolved(inheriting: nook.inheritedCompanionBackdrop),
            chromeBackdrop: nook.inheritedCompanionBackdrop,
            heightLimit: companionHeightLimit(for: surface),
            reduceMotion: reduceMotion,
            presenceAnimation: nook.effectiveConversionAnimation,
            onHover: { hovering in nook.updateCompanionHoverState(id: id, hovering: hovering) },
            onVisibilityRestriction: { restriction in
                nook.noteCompanionVisibilityRestriction(id: id, restriction: restriction)
            },
            onExtent: { maxY in nook.noteCompanionExtent(id: id, maxY: maxY) }
        )
        .environment(\.nookScrollEdgeFade, nook.scrollEdgeFade)
    }

    /// A companion beside the compact pill is fitted to the pill's height, so it is no taller than
    /// its neighbour and never reaches above the top of the screen. The expanded chrome is taller
    /// than any companion size, and a companion below the chrome has room to hang.
    private func companionHeightLimit(for surface: NookCompanionSurface) -> CGFloat? {
        guard surface.anchor.edge != .below, nook.state != .expanded, nook.notchSize.height > 0 else {
            return nil
        }
        return nook.notchSize.height
    }

    private func notchContent() -> some View {
        ZStack {
            compactContent()
                .fixedSize()
                .offset(x: nook.state == .compact ? 0 : compactXOffset)
                .frame(
                    // Notch mode reserves the notch width while expanded so the
                    // collapsed slots line up; a floating pill is content-driven.
                    width: (nook.state == .compact || isFloating) ? nil : nook.notchSize.width,
                    height: (nook.state == .compact && nook.isHovering) ? nook.menubarHeight : nook.notchSize.height
                )

            expandedContent()
                .fixedSize()
                .frame(
                    maxWidth: nook.state == .expanded ? nil : 0,
                    maxHeight: nook.state == .expanded ? nil : 0
                )
                .offset(x: nook.state == .compact ? -compactXOffset : 0)
        }
        .padding(.horizontal, topCornerRadius)
        .fixedSize()
        .frame(minWidth: minWidth, minHeight: nook.notchSize.height)
        .environment(\.nookChromeBackdrop, nook.backdrop)
    }

    private func compactContent() -> some View {
        HStack(spacing: 0) {
            if nook.state == .compact, !nook.disableCompactLeading {
                nook.compactLeadingContent
                    .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: 8) }
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { compactLeadingWidth = $0 }
                    .transition(
                        .blur(intensity: 6).combined(with: .scale(x: 0, anchor: .trailing)).combined(with: .opacity)
                    )
            }

            // Notch mode: a gap exactly the notch width, so the leading/trailing slots
            // straddle the physical notch. Floating mode: no notch - just a small gap
            // keeping the two slots from touching inside the pill.
            Spacer()
                .frame(width: isFloating ? 8 : nook.notchSize.width)

            if nook.state == .compact, !nook.disableCompactTrailing {
                nook.compactTrailingContent
                    .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: 8) }
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 4) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 8) }
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { compactTrailingWidth = $0 }
                    .transition(
                        .blur(intensity: 6).combined(with: .scale(x: 0, anchor: .leading)).combined(with: .opacity)
                    )
            }
        }
        .frame(height: nook.notchSize.height)
        // `disableCompactLeading/Trailing` are construction-time `let`s on `Nook` -
        // they cannot change at runtime, so no `.onChange` reconciliation is needed.
        // The `@State` `compactLeadingWidth`/`compactTrailingWidth` retain their last
        // measured value when the slot views disappear (SwiftUI doesn't fire
        // `onGeometryChange` for a vanishing view), but the values are only consulted
        // while the slots are present, so the stale carry-over is benign.
    }

    private func expandedContent() -> some View {
        HStack(spacing: 0) {
            if nook.state == .expanded {
                nook.expandedContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.nookContentInsets, contentInsets)
                    .environment(\.nookNotchCutout, notchCutout)
                    .environment(\.nookScrollEdgeFade, nook.scrollEdgeFade)
                    .transition(
                        .blur(intensity: 6).combined(with: .scale(y: 0.72, anchor: .top)).combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: expandedContentInsets.top) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: expandedContentInsets.bottom) }
        .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: expandedContentInsets.leading) }
        .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: expandedContentInsets.trailing) }
        .background {
            if let ambientColor {
                NookAmbientColorBackground(color: ambientColor)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: ambientColor)
        .onPreferenceChange(NookAmbientColorPreferenceKey.self) { ambientColor = $0 }
        .frame(minWidth: isFloating ? 0 : nook.notchSize.width)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            guard nook.state == .expanded, size != trackedExpandedSize else { return }
            trackedExpandedSize = size
            nook.noteExpandedContentSizeChange()
        }
    }
}
