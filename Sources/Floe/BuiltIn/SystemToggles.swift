//
//  SystemToggles.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreAudio
import CoreWLAN
import Foundation
import IOKit.pwr_mgt

/// The system commands that flip a setting. Each returns the line the HUD shows, which says
/// what the setting is now or why it did not change.
enum SystemToggle {
    // MARK: Wi-Fi

    static func flipWiFi() -> String {
        guard let interface = CWWiFiClient.shared().interface() else { return String(localized: "This Mac has no Wi-Fi", bundle: .floe) }
        let turnOn = !interface.powerOn()
        do {
            try interface.setPower(turnOn)
            return turnOn ? String(localized: "Wi-Fi On", bundle: .floe) : String(localized: "Wi-Fi Off", bundle: .floe)
        } catch {
            return turnOn
                ? String(localized: "Couldn't turn Wi-Fi on", bundle: .floe)
                : String(localized: "Couldn't turn Wi-Fi off", bundle: .floe)
        }
    }

    // MARK: Mute

    static func flipMute() -> String {
        guard let device = defaultOutputDevice() else { return String(localized: "No sound output", bundle: .floe) }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return String(localized: "This output can't be muted", bundle: .floe) }
        var flipped: UInt32 = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &flipped) == noErr else { return String(localized: "Couldn't change the sound", bundle: .floe) }
        return flipped == 1 ? String(localized: "Muted", bundle: .floe, comment: "Said after the sound was turned off.") : String(localized: "Unmuted", bundle: .floe, comment: "Said after the sound was turned back on.")
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    // MARK: Keep awake

    /// The assertion that holds the display awake; 0 while there is none. Only touched on the main thread.
    private static var awakeAssertion: IOPMAssertionID = 0

    static var isKeepingAwake: Bool {
        awakeAssertion != 0
    }

    /// Lasts until it is flipped back or Floe quits: the system drops the assertion with the process.
    static func flipKeepAwake() -> String {
        if awakeAssertion != 0 {
            IOPMAssertionRelease(awakeAssertion)
            awakeAssertion = 0
            return String(localized: "Your Mac can sleep again", bundle: .floe)
        }
        var assertion: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Floe: Keep Awake" as CFString,
            &assertion
        )
        guard status == kIOReturnSuccess else { return String(localized: "Couldn't keep your Mac awake", bundle: .floe) }
        awakeAssertion = assertion
        return String(localized: "Keeping your Mac awake", bundle: .floe)
    }
}
