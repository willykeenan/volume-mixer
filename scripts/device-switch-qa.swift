#!/usr/bin/env swift

import CoreAudio
import Foundation

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func address(
    _ selector: AudioObjectPropertySelector
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

func ownedString(
    object: AudioObjectID,
    selector: AudioObjectPropertySelector
) -> String? {
    var property = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(
        object,
        &property,
        0,
        nil,
        &size,
        &value
    ) == noErr else {
        return nil
    }
    return value?.takeRetainedValue() as String?
}

var outputProperty = address(kAudioHardwarePropertyDefaultOutputDevice)
var originalOutput = AudioDeviceID(kAudioObjectUnknown)
var outputSize = UInt32(MemoryLayout<AudioDeviceID>.size)
guard AudioObjectGetPropertyData(
    systemObject,
    &outputProperty,
    0,
    nil,
    &outputSize,
    &originalOutput
) == noErr,
let originalUID = ownedString(
    object: originalOutput,
    selector: kAudioDevicePropertyDeviceUID
) else {
    fputs("could not resolve the current output device\n", stderr)
    exit(1)
}

let aggregateUID = "dev.kestudios.volume-mixer.qa-output.\(UUID().uuidString)"
let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceNameKey: "KE Volume Mixer QA Output",
    kAudioAggregateDeviceUIDKey: aggregateUID,
    kAudioAggregateDeviceMainSubDeviceKey: originalUID,
    kAudioAggregateDeviceIsPrivateKey: false,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: originalUID],
    ],
]

var aggregate = AudioObjectID(kAudioObjectUnknown)
let createStatus = AudioHardwareCreateAggregateDevice(
    aggregateDescription as CFDictionary,
    &aggregate
)
guard createStatus == noErr, aggregate != kAudioObjectUnknown else {
    fputs("aggregate creation failed: \(createStatus)\n", stderr)
    exit(1)
}

defer {
    var restore = originalOutput
    let restoreSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectSetPropertyData(
        systemObject,
        &outputProperty,
        0,
        nil,
        restoreSize,
        &restore
    )
    Thread.sleep(forTimeInterval: 2)
    _ = AudioHardwareDestroyAggregateDevice(aggregate)
}

var temporaryOutput = aggregate
let setStatus = AudioObjectSetPropertyData(
    systemObject,
    &outputProperty,
    0,
    nil,
    UInt32(MemoryLayout<AudioDeviceID>.size),
    &temporaryOutput
)
guard setStatus == noErr else {
    fputs("default-output switch failed: \(setStatus)\n", stderr)
    exit(1)
}

print("temporaryOutput=\(aggregate)")
print("temporaryName=KE Volume Mixer QA Output")
Thread.sleep(forTimeInterval: 5)
print("restoreOutput=\(originalOutput)")
