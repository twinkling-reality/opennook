// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import CoreAudio
import NookApp
import NookComponents
import SwiftUI

/// A volume HUD over the `NookComponents` `SystemVolumeObserver`. The level is the Mac's real
/// output volume; when it changes, the module takes the surface for a moment to show it.
struct VolumeHUD: View {
    @ObservedObject var volume: SystemVolumeObserver
    let deviceName: String
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookContentInsets) private var insets

    private let segments = 16

    var body: some View {
        HStack(spacing: 14) {
            Image(
                systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                variableValue: volume.volume
            )
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.primaryLabel)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 44, height: 44)
            .background(Circle().fill(theme.subtleFill.opacity(2)))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Volume")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primaryLabel)
                    Text(deviceName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryLabel)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(volume.isMuted ? "Muted" : "\(Int((volume.volume * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(theme.secondaryLabel)
                        .contentTransition(.numericText())
                }
                HStack(spacing: 3) {
                    ForEach(0..<segments, id: \.self) { index in
                        let lit = !volume.isMuted && Double(index) < (volume.volume * Double(segments)).rounded()
                        Capsule()
                            .fill(lit ? theme.primaryLabel : theme.subtleFill.opacity(2.2))
                            .frame(height: 6)
                    }
                }
                .animation(.snappy(duration: 0.18), value: volume.volume)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, max(insets.bottom, 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A plain description of the default output device, read once through CoreAudio. It names the
/// kind of device rather than the device, so a renamed pair of headphones never shows its
/// owner's name on screen.
enum OutputDevice {
    static func currentLabel() -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
                == noErr
        else { return "Output" }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return "Output"
        }
        switch transport {
            case kAudioDeviceTransportTypeBuiltIn: return "Built-in Speakers"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Headphones"
            case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "Display"
            case kAudioDeviceTransportTypeUSB: return "USB Audio"
            default: return "Output"
        }
    }
}
