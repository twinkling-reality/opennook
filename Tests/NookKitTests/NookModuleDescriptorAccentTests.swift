// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// `NookModuleDescriptor.accent` is deprecated (it was never read) but keeps compiling and
/// keeps its value.
final class NookModuleDescriptorAccentTests: XCTestCase {
    func testADescriptorWithoutAnAccent() {
        let descriptor = NookModuleDescriptor(id: "a", displayName: "A", icon: "star")
        XCTAssertEqual(descriptor.icon, "star")
        XCTAssertEqual(descriptor.backgroundPolicy, .unloadOnSwitchAway)
    }

    @available(*, deprecated, message: "exercises the deprecated accent")
    func testTheDeprecatedAccentStillCompilesAndKeepsItsValue() {
        var descriptor = NookModuleDescriptor(id: "a", displayName: "A", accent: .orange)
        XCTAssertEqual(descriptor.accent, .orange)
        descriptor.accent = .pink
        XCTAssertEqual(descriptor.accent, .pink)
        XCTAssertEqual(NookModuleDescriptor(id: "b", displayName: "B").accent, .accentColor)
    }
}
