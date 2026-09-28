import CoreAudio
import Darwin
import Foundation

enum CoreAudioUtils {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    static func processObjectList() -> [AudioObjectID] {
        var property = address(kAudioHardwarePropertyProcessObjectList)
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

        var list = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            systemObject,
            &property,
            0,
            nil,
            &size,
            &list
        ) == noErr else {
            return []
        }
        return Array(list.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func pid(of process: AudioObjectID) -> pid_t? {
        var property = address(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(
            process,
            &property,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }

    static func bundleID(of process: AudioObjectID) -> String? {
        cfString(object: process, selector: kAudioProcessPropertyBundleID)
    }

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var property = address(kAudioProcessPropertyIsRunningOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            process,
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

    static func defaultOutputDevice() -> AudioDeviceID? {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            systemObject,
            &property,
            0,
            nil,
            &size,
            &value
        ) == noErr, value != kAudioObjectUnknown else {
            return nil
        }
        return value
    }

    static func deviceUID(_ device: AudioDeviceID) -> String? {
        cfString(object: device, selector: kAudioDevicePropertyDeviceUID)
    }

    static func deviceName(_ device: AudioDeviceID) -> String? {
        cfString(object: device, selector: kAudioObjectPropertyName)
    }

    static func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1_024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func cfString(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var property = address(selector)
        // The SDK explicitly says callers release kAudioObjectPropertyName,
        // kAudioDevicePropertyDeviceUID, and kAudioProcessPropertyBundleID.
        // Receive that +1 as Unmanaged, then transfer it exactly once to ARC.
        // No second release or unretained bridge is applied.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            object,
            &property,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr,
              let string = value?.takeRetainedValue() as String?,
              !string.isEmpty else {
            return nil
        }
        return string
    }
}
