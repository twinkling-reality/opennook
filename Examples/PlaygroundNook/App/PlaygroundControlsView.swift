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
            case .panel: "Size and Shape"
            case .typeAndMotion: "Type and Motion"
            case .topBar: "Top Bar"
            case .companions: "Companions"
            case .effects: "Rim Glow and Fade"
            case .behavior: "Behavior"
            case .presets: "Presets and Export"
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
            case .presets: "square.and.arrow.up"
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

struct PlaygroundControlsView: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState
    @State private var page: PlaygroundPage? = .appearance
    @State private var showsExport = true

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle("Playground")
                .navigationSubtitle((page ?? .appearance).title)
                .toolbar { toolbar }
                .inspector(isPresented: $showsExport) {
                    PlaygroundExportView(model: model, appState: appState)
                        .inspectorColumnWidth(min: 320, ideal: 420, max: 680)
                }
        }
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

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $page) {
            Section("Look") {
                row(.appearance)
                row(.theme)
                row(.panel)
                row(.typeAndMotion)
            }
            Section("Chrome") {
                row(.topBar)
                row(.companions)
                row(.effects)
                row(.behavior)
            }
            Section("Share") {
                row(.presets)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            nookStatus
        }
    }

    private func row(_ page: PlaygroundPage) -> some View {
        Label {
            HStack {
                Text(page.title)
                Spacer(minLength: 4)
                if page.isModified(model.settings, appearance: appState.appearancePreferences) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 6, height: 6)
                        .help("Changed from the defaults")
                        .accessibilityLabel("Changed")
                }
            }
        } icon: {
            Image(systemName: page.systemImage)
        }
        .tag(page)
    }

    private var nookStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isNookVisible ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(appState.isNookVisible ? "Nook is expanded" : "Nook is collapsed")
                    .font(.callout.weight(.medium))
            }
            // A line limit rather than an unbounded height: the split view measures the sidebar
            // at tiny widths, where unbounded text wraps a word per line and props the window up
            // to the height of the screen.
            Text(
                "Hover the notch or press \(appState.hotkey.display) to open it. "
                    + "Keep Expanded holds it open while you work here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch page ?? .appearance {
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

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Layout", selection: presentation) {
                Text("Auto").tag(NookPresentation.auto)
                Text("Notch").tag(NookPresentation.notch)
                Text("Floating").tag(NookPresentation.floating)
            }
            .pickerStyle(.segmented)
            .help("Where the nook sits: fused to the notch, floating below the menu bar, or chosen per display")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: keepsExpanded) {
                Label("Keep Expanded", systemImage: appState.keepNookOpen ? "lock.fill" : "lock.open")
            }
            .help("Keep the nook expanded when the pointer leaves it")
        }
        ToolbarItem(placement: .primaryAction) {
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
            .help(appState.isNookVisible ? "Collapse the nook" : "Expand the nook")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showsExport.toggle()
            } label: {
                Label("Export", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help(showsExport ? "Hide the export" : "Show the Swift and JSON export")
        }
    }

    private var presentation: Binding<NookPresentation> {
        Binding(
            get: { appState.appearancePreferences.presentation },
            set: { presentation in model.updateAppearance { $0.presentation = presentation } }
        )
    }

    private var keepsExpanded: Binding<Bool> {
        Binding(
            get: { appState.keepNookOpen },
            set: { model.setKeepsNookExpanded($0) }
        )
    }
}
