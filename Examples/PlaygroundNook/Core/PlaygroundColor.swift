// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit

/// An sRGB color the playground can store, export, and compare: the framework's `NookRGBA`, an
/// 8-bit color written as `#RRGGBB` or `#RRGGBBAA`. `Color` itself is neither `Codable` nor
/// reliably comparable once it has been through a color picker.
///
/// Components are kept at 8 bits per channel, the precision of the hex string it is stored as,
/// so a color survives a JSON round trip unchanged - exactly as before it moved into NookKit.
public typealias PlaygroundColor = NookRGBA
