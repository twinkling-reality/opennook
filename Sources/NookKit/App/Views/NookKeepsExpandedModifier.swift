// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Brief grace after a popover/menu/sheet binding goes `false` before the
/// presentation pin releases. Covers menu selection side-effects and the
/// layout resize that often follows popover dismissal.
enum NookKeepsExpandedGrace {
    static let postPresentationDuration: Duration = .milliseconds(400)
}

extension View {
    /// Hold the notch surface expanded while `condition.wrappedValue` is `true`.
    ///
    /// Pair with the same binding you pass to `.popover(isPresented:)`,
    /// `.sheet(isPresented:)`, or `.alert(_:isPresented:)`. While the binding is
    /// `true`, the surface stays open and counts as user-engaged (denying
    /// competing arbiter claims); on `false` the pin releases after a brief grace
    /// so menu selection and the ensuing layout resize do not immediately expose
    /// hover-exit auto-compact. View teardown releases immediately. See
    /// ``NookPresentationPinning``.
    ///
    /// ```swift
    /// Button("Pick time") { showingPicker = true }
    ///     .popover(isPresented: $showingPicker) { TimePicker() }
    ///     .nookKeepsExpanded(while: $showingPicker)
    /// ```
    public func nookKeepsExpanded(while condition: Binding<Bool>) -> some View {
        modifier(NookKeepsExpandedBoolModifier(condition: condition))
    }

    /// Hold the notch surface expanded while `item.wrappedValue != nil`.
    ///
    /// The item-binding variant for `.popover(item:)` / `.sheet(item:)` /
    /// `.alert(item:)`. Pin acquired on `nil` -> non-nil, released on
    /// non-nil -> `nil` or view teardown.
    ///
    /// ```swift
    /// .popover(item: $selectedTime) { TimeEditor(time: $0) }
    /// .nookKeepsExpanded(while: $selectedTime)
    /// ```
    public func nookKeepsExpanded<Item>(while item: Binding<Item?>) -> some View {
        modifier(NookKeepsExpandedItemModifier(item: item))
    }

    /// Hold the notch surface expanded while a text input has focus and the nook has the
    /// keyboard.
    ///
    /// Pass the same focus state you bind with `focused(_:)`. The nook stays open while the
    /// person types, even if the pointer wanders off it, and lets go after a brief grace once
    /// focus leaves or the keyboard goes to another app. If the pointer left while the input
    /// had focus, the nook then closes.
    ///
    /// Focus alone does not hold the nook: SwiftUI can focus an input when it first appears,
    /// before the person has clicked into the nook, and a hold then would keep a nook opened
    /// by hover from closing.
    ///
    /// ```swift
    /// TextField("Reply", text: $reply)
    ///     .focused($isReplyFocused)
    ///     .nookKeepsExpanded(whileFocused: $isReplyFocused)
    /// ```
    public func nookKeepsExpanded(whileFocused focus: FocusState<Bool>.Binding) -> some View {
        modifier(NookKeepsExpandedFocusModifier(focus: focus))
    }

    /// Gives the nook the keyboard and focuses this text input as it appears, so the person can
    /// type straight away - for an input that appears because they asked for it, such as a reply
    /// field a button reveals.
    ///
    /// Setting a `FocusState` from `onAppear`, `task`, or `defaultFocus(_:_:)` does not focus an
    /// input that has just appeared in the nook, and typing then goes nowhere. This focuses it
    /// once it is in place.
    ///
    /// ```swift
    /// TextField("Reply", text: $reply)
    ///     .focused($isReplyFocused)
    ///     .nookFocusOnAppear($isReplyFocused)
    ///     .nookKeepsExpanded(whileFocused: $isReplyFocused)
    /// ```
    ///
    /// Taking the keyboard moves typing away from the app in front, so don't use it on an input
    /// that shows whenever the nook opens: hovering the nook would take the keyboard.
    public func nookFocusOnAppear(_ focus: FocusState<Bool>.Binding) -> some View {
        modifier(NookFocusOnAppearModifier(focus: focus))
    }
}

/// Implementation for `nookFocusOnAppear(_:)`.
private struct NookFocusOnAppearModifier: ViewModifier {
    let focus: FocusState<Bool>.Binding
    @Environment(\.nookChromeActions) private var chromeActions

    func body(content: Content) -> some View {
        content.onAppear {
            chromeActions.takeKeyboardFocus()
            // A focus request made while the input is appearing is dropped; one made on the next
            // turn of the run loop, once the input is in the window, takes.
            DispatchQueue.main.async {
                focus.wrappedValue = true
            }
        }
    }
}

/// Implementation for the `FocusState<Bool>.Binding` overload: mirrors the focus into state
/// the Bool variant already pins on, so the pin and its grace behave identically.
private struct NookKeepsExpandedFocusModifier: ViewModifier {
    let focus: FocusState<Bool>.Binding
    @Environment(\.nookHasKeyboardFocus) private var hasKeyboardFocus
    @State private var isHolding = false

    func body(content: Content) -> some View {
        content
            .onAppear { isHolding = focus.wrappedValue && hasKeyboardFocus }
            .onChange(of: focus.wrappedValue) { _, focused in isHolding = focused && hasKeyboardFocus }
            .onChange(of: hasKeyboardFocus) { _, keyboard in isHolding = focus.wrappedValue && keyboard }
            .nookKeepsExpanded(while: $isHolding)
    }
}

/// Implementation for the `Binding<Bool>` overload.
///
/// `@State` owns the live ``NookPresentationPinHandle``. The handle's lifetime
/// is structurally bounded by the view: when the view disappears SwiftUI tears
/// down the `@State`, which drops the handle; the handle's deinit fallback
/// releases the pin even if `onDisappear` somehow does not run. The explicit
/// `release()` path runs on `onChange` / `onDisappear` so common cases release
/// promptly instead of waiting for the next ARC cycle.
private struct NookKeepsExpandedBoolModifier: ViewModifier {
    @Binding var condition: Bool
    @Environment(\.appServices) private var services
    @State private var handle: NookPresentationPinHandle?
    @State private var releaseTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { sync(to: condition) }
            .onChange(of: condition) { _, newValue in sync(to: newValue) }
            .onDisappear { releaseImmediately() }
    }

    private func sync(to active: Bool) {
        if active {
            releaseTask?.cancel()
            releaseTask = nil
            if handle == nil {
                handle = services.resolve(NookPresentationPinningKey.self).pin(reason: "view-modifier")
            }
        } else {
            scheduleRelease()
        }
    }

    private func scheduleRelease() {
        guard handle != nil else { return }
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: NookKeepsExpandedGrace.postPresentationDuration)
            guard !Task.isCancelled else { return }
            releaseImmediately()
        }
    }

    private func releaseImmediately() {
        releaseTask?.cancel()
        releaseTask = nil
        handle?.release()
        handle = nil
    }
}

/// Implementation for the `Binding<Item?>` overload. Mirrors the Bool variant
/// with `item != nil` as the condition.
private struct NookKeepsExpandedItemModifier<Item>: ViewModifier {
    @Binding var item: Item?
    @Environment(\.appServices) private var services
    @State private var handle: NookPresentationPinHandle?
    @State private var releaseTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { sync(to: item != nil) }
            .onChange(of: item == nil) { _, isNil in sync(to: !isNil) }
            .onDisappear { releaseImmediately() }
    }

    private func sync(to active: Bool) {
        if active {
            releaseTask?.cancel()
            releaseTask = nil
            if handle == nil {
                handle = services.resolve(NookPresentationPinningKey.self).pin(reason: "view-modifier")
            }
        } else {
            scheduleRelease()
        }
    }

    private func scheduleRelease() {
        guard handle != nil else { return }
        releaseTask?.cancel()
        releaseTask = Task {
            try? await Task.sleep(for: NookKeepsExpandedGrace.postPresentationDuration)
            guard !Task.isCancelled else { return }
            releaseImmediately()
        }
    }

    private func releaseImmediately() {
        releaseTask?.cancel()
        releaseTask = nil
        handle?.release()
        handle = nil
    }
}
