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

func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var property = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        systemObject,
        &property,
        0,
        nil,
        &size
    ) == noErr, size > 0 else {
        return []
    }
    var values = [AudioObjectID](
        repeating: kAudioObjectUnknown,
        count: Int(size) / MemoryLayout<AudioObjectID>.size
    )
    guard AudioObjectGetPropertyData(
        systemObject,
        &property,
        0,
        nil,
        &size,
        &values
    ) == noErr else {
        return []
    }
    return Array(
        values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size)
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

func processPID(_ object: AudioObjectID) -> pid_t? {
    var property = address(kAudioProcessPropertyPID)
    var pid: pid_t = -1
    var size = UInt32(MemoryLayout<pid_t>.size)
    guard AudioObjectGetPropertyData(
        object,
        &property,
        0,
        nil,
        &size,
        &pid
    ) == noErr else {
        return nil
    }
    return pid
}

func processRunningOutput(_ object: AudioObjectID) -> Bool {
    var property = address(kAudioProcessPropertyIsRunningOutput)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(
        object,
        &property,
        0,
        nil,
        &size,
        &value
    ) == noErr else {
        return false
    }
    return value != 0
}

let processes = objectList(kAudioHardwarePropertyProcessObjectList).compactMap {
    object -> [String: Any]? in
    guard let bundleID = ownedString(
        object: object,
        selector: kAudioProcessPropertyBundleID
    ), bundleID.hasPrefix("dev.kestudios.volume-mixer.qa.") else {
        return nil
    }
    return [
        "audioObjectID": object,
        "bundleID": bundleID,
        "pid": processPID(object) ?? -1,
        "runningOutput": processRunningOutput(object),
    ]
}

let taps = objectList(kAudioHardwarePropertyTapList).compactMap {
    object -> [String: Any]? in
    let name = ownedString(object: object, selector: kAudioObjectPropertyName)
        ?? ""
    guard name.hasPrefix("KE Volume Mixer") else { return nil }
    return [
        "audioObjectID": object,
        "name": name,
        "uid": ownedString(object: object, selector: kAudioTapPropertyUID) ?? "",
    ]
}

let devices = objectList(kAudioHardwarePropertyDevices).compactMap {
    object -> [String: Any]? in
    let name = ownedString(object: object, selector: kAudioObjectPropertyName)
        ?? ""
    guard name.hasPrefix("KE Volume Mixer") else { return nil }
    return [
        "audioObjectID": object,
        "name": name,
        "uid": ownedString(
            object: object,
            selector: kAudioDevicePropertyDeviceUID
        ) ?? "",
    ]
}

var defaultOutput = AudioDeviceID(kAudioObjectUnknown)
var defaultOutputProperty = address(kAudioHardwarePropertyDefaultOutputDevice)
var defaultOutputSize = UInt32(MemoryLayout<AudioDeviceID>.size)
_ = AudioObjectGetPropertyData(
    systemObject,
    &defaultOutputProperty,
    0,
    nil,
    &defaultOutputSize,
    &defaultOutput
)

let snapshot: [String: Any] = [
    "defaultOutput": [
        "audioObjectID": defaultOutput,
        "name": ownedString(
            object: defaultOutput,
            selector: kAudioObjectPropertyName
        ) ?? "",
    ],
    "fixtureProcesses": processes,
    "keMixerTaps": taps,
    "keMixerDevices": devices,
]

let data = try JSONSerialization.data(
    withJSONObject: snapshot,
    options: [.prettyPrinted, .sortedKeys]
)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
