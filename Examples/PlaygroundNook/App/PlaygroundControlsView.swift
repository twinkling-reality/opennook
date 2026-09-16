// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookApp
import PlaygroundNookCore
import SwiftUI

/// A page of the controls window.
enum PlaygroundPage: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case theme
    case panel
    case typeAndMotion
    case topBar
    case companions
    case effects
    case behavior
    case presets

    var id: String { rawValue }

    var title: String {
        switch self {
            case .appearance: "Appearance"
            case .theme: "Theme"
            case .panel: "Panel"
            case .typeAndMotion: "Type and Motion"
            case .topBar: "Top Bar"
            case .companions: "Companions"
            case .effects: "Effects"
            case .behavior: "Behavior"
            case .presets: "Presets"
        }
    }

    var systemImage: String {
        switch self {
            case .appearance: "circle.lefthalf.filled"
            case .theme: "paintpalette"
            case .panel: "rectangle.dashed"
            case .typeAndMotion: "textformat"
            case .topBar: "menubar.rectangle"
            case .companions: "capsule.on.rectangle"
            case .effects: "sparkles"
            case .behavior: "cursorarrow.motionlines"
            case .presets: "square.stack"
        }
    }

    /// Whether anything on the page differs from the defaults.
    func isModified(_ settings: PlaygroundSettings, appearance: NookAppearancePreferences) -> Bool {
        switch self {
            case .appearance:
                var appearance = appearance
                appearance.keepNookOpen = NookAppearancePreferences.default.keepNookOpen
                return appearance != .default
            case .theme:
                return settings.theme != .init()
            case .panel:
                return settings.panel != .init() || settings.metrics != .init()
            case .typeAndMotion:
                return settings.typography != .init() || settings.motion != .init()
            case .topBar:
                return settings.topBar != .init() || settings.labels != .init()
            case .companions:
                return !settings.companions.isEmpty
            case .effects:
                return settings.rimGlow != .init() || settings.scrollEdgeFade != .init()
            case .behavior:
                return settings.behavior != .init()
            case .presets:
                return false
        }
    }
}

/// The controls window: a floating sidebar, the page, and the code in a card beside it, over a
/// quiet gradient. The window has no toolbar; its few actions sit at the top right.
struct PlaygroundControlsView: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState
    @State private var page = PlaygroundPage.appearance
    @AppStorage("playground.showsCode") private var showsCode = true
    /// The strip the traffic lights sit in, centered on them. The window's own actions share it,
    /// and the cards start a little below it.
    var titleBarHeight: CGFloat = 50

    var body: some View {
        content
            .ignoresSafeArea()
            .background(PlaygroundBackdrop())
            .animation(.snappy(duration: 0.3), value: showsCode)
            .alert(
                "Playground",
                isPresented: Binding(
                    get: { model.alertMessage != nil },
                    set: { if !$0 { model.alertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
    }

    private var content: some View {
        HStack(spacing: 12) {
            PlaygroundSidebar(page: $page, model: model, appState: appState)
                .frame(width: 208)
            pageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    ToastView(model: model)
                }
            if showsCode {
                CodePanel(model: model, appState: appState)
                    .frame(width: 380)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, titleBarHeight + 6)
        .padding(.bottom, 12)
        .overlay(alignment: .top) {
            titleBar
                .frame(height: titleBarHeight)
        }
    }

    @ViewBuilder
    private var pageView: some View {
        switch page {
            case .appearance: AppearancePage(model: model, appState: appState)
            case .theme: ThemePage(model: model, appState: appState)
            case .panel: PanelPage(model: model)
            case .typeAndMotion: TypeAndMotionPage(model: model)
            case .topBar: TopBarPage(model: model)
            case .companions: CompanionsPage(model: model)
            case .effects: EffectsPage(model: model)
            case .behavior: BehaviorPage(model: model)
            case .presets: PresetsPage(model: model)
        }
    }

    /// The strip beside the traffic lights: a drag area, with the window's actions on the right.
    private var titleBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Toggle(isOn: keepsExpanded) {
                Label("Keep Open", systemImage: appState.keepNookOpen ? "lock.fill" : "lock.open")
            }
            .toggleStyle(TopPillToggleStyle())
            .help(appState.keepNookOpen ? "Let the nook collapse again" : "Keep the nook expanded while you work")
            .accessibilityIdentifier("toolbar.keepExpanded")

            Button {
                if appState.isNookVisible {
                    model.collapseNook()
                } else {
                    model.expandNook()
                }
            } label: {
                Label(
                    appState.isNookVisible ? "Collapse" : "Expand",
                    systemImage: appState.isNookVisible
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                )
            }
            .buttonStyle(TopPillButtonStyle())
            .help(appState.isNookVisible ? "Collapse the nook" : "Expand the nook")
            .accessibilityIdentifier("toolbar.expand")

            Toggle(isOn: $showsCode) {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .toggleStyle(TopPillToggleStyle())
            .help(showsCode ? "Hide the code" : "Show the code")
            .accessibilityIdentifier("toolbar.code")
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }

    private var keepsExpanded: Binding<Bool> {
        Binding(
            get: { appState.keepNookOpen },
            set: { model.setKeepsNookExpanded($0) }
        )
    }
}

/// The page list, floating on the backdrop.
private struct PlaygroundSidebar: View {
    @Binding var page: PlaygroundPage
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(PlaygroundPage.Group.allCases) { group in
                    Text(group.title)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, group == .look ? 2 : 14)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.pages) { item in
                        row(item)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
        .surface(PlaygroundTheme.panel, radius: PlaygroundTheme.panelRadius)
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            let pages = PlaygroundPage.allCases
            guard let index = pages.firstIndex(of: page) else { return }
            switch direction {
                case .up where index > 0: page = pages[index - 1]
                case .down where index < pages.count - 1: page = pages[index + 1]
                default: break
            }
        }
    }

    private func row(_ item: PlaygroundPage) -> some View {
        let isSelected = item == page
        let isModified = item.isModified(model.settings, appearance: appState.appearancePreferences)
        return Button {
            page = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                Text(item.title)
                    .font(PlaygroundTheme.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isModified {
                    ModifiedDot()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowButtonStyle(isSelected: isSelected))
        .accessibilityIdentifier("page.\(item.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if item != .presets {
                Button("Reset \(item.title)") { model.reset(item) }
                    .disabled(!isModified)
            }
        }
    }
}

/// The model's current confirmation, floating over the bottom of the page.
private struct ToastView: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        ZStack {
            if let toast = model.toast {
                HStack(spacing: 12) {
                    Text(toast.message)
                        .font(PlaygroundTheme.body)
                        .lineLimit(1)
                    if toast.canUndo {
                        Button(action: model.undo) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, toast.canUndo ? 6 : 16)
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(PlaygroundTheme.stroke) }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
    }
}
