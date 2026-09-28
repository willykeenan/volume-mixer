import AudioToolbox
import CoreAudio
import Foundation
import MixerAtomics
import MixerCore
import os

enum ProcessTapError: LocalizedError {
    case atomicStateUnavailable
    case tapCreationFailed(OSStatus)
    case noOutputDevice
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .atomicStateUnavailable:
            return "This Mac does not provide the lock-free audio state required for safe real-time mixing."
        case .tapCreationFailed(let status):
            return "Could not hear this app (\(status)). Allow KE Volume Mixer in Privacy & Security > Screen & System Audio Recording, then reopen it."
        case .noOutputDevice:
            return "No default audio output is available."
        case .aggregateCreationFailed(let status):
            return "Could not create the private audio route (\(status))."
        case .ioProcCreationFailed(let status):
            return "Could not start the private audio processor (\(status))."
        case .deviceStartFailed(let status):
            return "The selected output device did not start (\(status))."
        }
    }
}

/// Creates one private Core Audio process tap per visible app. The tap reads
/// actual PCM energy for the activity meter, mutes the app's direct path only
/// while it is being read, and immediately re-renders it to the current output
/// with a click-free gain ramp.
final class ProcessTap {
    private static let logger = Logger(
        subsystem: "dev.kestudios.volume-mixer",
        category: "ProcessTap"
    )

    let processObjectIDs: [AudioObjectID]
    private let displayName: String

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(
        label: "dev.kestudios.volume-mixer.tap-io",
        qos: .userInteractive
    )
    private let gainState: OpaquePointer
    private let currentGainState: OpaquePointer
    private let levelState: OpaquePointer
    private var invalidated = false

    var gain: Float {
        get { KEMixerAtomicFloatLoad(gainState) }
        set {
            KEMixerAtomicFloatStore(
                gainState,
                GainDSP.clampedGain(newValue)
            )
        }
    }

    var audioLevel: Float {
        KEMixerAtomicFloatLoad(levelState)
    }

    init(
        processObjectIDs: [AudioObjectID],
        name: String,
        initialGain: Float
    ) throws {
        self.processObjectIDs = processObjectIDs
        displayName = name
        let gain = GainDSP.clampedGain(initialGain)
        let atomicState = try Self.makeAtomicState(initialGain: gain)
        gainState = atomicState.gain
        currentGainState = atomicState.currentGain
        levelState = atomicState.level

        do {
            try activate(name: name)
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
        KEMixerAtomicFloatDestroy(gainState)
        KEMixerAtomicFloatDestroy(currentGainState)
        KEMixerAtomicFloatDestroy(levelState)
    }

    private func activate(name: String) throws {
        let description = CATapDescription(
            stereoMixdownOfProcesses: processObjectIDs
        )
        description.uuid = UUID()
        description.name = "KE Volume Mixer — \(name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw ProcessTapError.tapCreationFailed(status)
        }
        tapID = tap

        guard let outputDevice = CoreAudioUtils.defaultOutputDevice(),
              let outputUID = CoreAudioUtils.deviceUID(outputDevice) else {
            throw ProcessTapError.noOutputDevice
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "KE Volume Mixer — \(name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregate
        )
        guard status == noErr, aggregate != kAudioObjectUnknown else {
            throw ProcessTapError.aggregateCreationFailed(status)
        }
        aggregateID = aggregate

        let targetGain = gainState
        let currentGain = currentGainState
        let meter = levelState
        status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateID,
            ioQueue
        ) { _, inputData, _, outputData, _ in
            let target = KEMixerAtomicFloatLoad(targetGain)
            var current = KEMixerAtomicFloatLoad(currentGain)
            let previousLevel = KEMixerAtomicFloatLoad(meter)
            let level = Self.render(
                input: inputData,
                output: outputData,
                targetGain: target,
                currentGain: &current,
                previousLevel: previousLevel
            )
            KEMixerAtomicFloatStore(currentGain, current)
            KEMixerAtomicFloatStore(meter, level)
        }
        guard status == noErr, let ioProcID else {
            throw ProcessTapError.ioProcCreationFailed(status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            throw ProcessTapError.deviceStartFailed(status)
        }

        Self.logger.info(
            "Private tap active for \(name, privacy: .public) (\(self.processObjectIDs.count) process object(s))"
        )
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true

        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        // AudioDeviceStop prevents new callbacks; this barrier drains any
        // callback already submitted before deinit frees the atomic state.
        ioQueue.sync {}
        KEMixerAtomicFloatStore(levelState, 0)
        Self.logger.info(
            "Private tap stopped for \(self.displayName, privacy: .public)"
        )
    }

    private static func makeAtomicState(
        initialGain: Float
    ) throws -> (
        gain: OpaquePointer,
        currentGain: OpaquePointer,
        level: OpaquePointer
    ) {
        let gain = KEMixerAtomicFloatCreate(initialGain)
        let currentGain = KEMixerAtomicFloatCreate(initialGain)
        let level = KEMixerAtomicFloatCreate(0)

        guard let gain, let currentGain, let level else {
            KEMixerAtomicFloatDestroy(gain)
            KEMixerAtomicFloatDestroy(currentGain)
            KEMixerAtomicFloatDestroy(level)
            throw ProcessTapError.atomicStateUnavailable
        }
        guard KEMixerAtomicFloatIsLockFree(gain),
              KEMixerAtomicFloatIsLockFree(currentGain),
              KEMixerAtomicFloatIsLockFree(level) else {
            KEMixerAtomicFloatDestroy(gain)
            KEMixerAtomicFloatDestroy(currentGain)
            KEMixerAtomicFloatDestroy(level)
            throw ProcessTapError.atomicStateUnavailable
        }
        return (gain, currentGain, level)
    }

    private static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        targetGain: Float,
        currentGain: inout Float,
        previousLevel: Float
    ) -> Float {
        let inputList = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: input)
        )
        let outputList = UnsafeMutableAudioBufferListPointer(output)

        var rawPeak: Float = 0
        var firstBase: UnsafeMutablePointer<Float32>?
        var firstStride = 1
        var firstFrames = 0
        var secondBase: UnsafeMutablePointer<Float32>?
        var secondStride = 1
        var secondFrames = 0
        var inputChannelCount = 0

        for buffer in inputList {
            guard let data = buffer.mData else { continue }
            let channelCount = max(Int(buffer.mNumberChannels), 1)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let frameCount = sampleCount / channelCount
            let base = data.assumingMemoryBound(to: Float32.self)

            for sample in 0..<sampleCount {
                rawPeak = max(rawPeak, abs(base[sample]))
            }
            for channel in 0..<channelCount {
                guard inputChannelCount < 2 else { break }
                if inputChannelCount == 0 {
                    firstBase = base + channel
                    firstStride = channelCount
                    firstFrames = frameCount
                } else {
                    secondBase = base + channel
                    secondStride = channelCount
                    secondFrames = frameCount
                }
                inputChannelCount += 1
            }
        }

        var maximumFrames = 0
        var outputChannelIndex = 0
        for buffer in outputList {
            guard let data = buffer.mData else { continue }
            guard inputChannelCount > 0, let firstBase else {
                memset(data, 0, Int(buffer.mDataByteSize))
                continue
            }

            let channelCount = max(Int(buffer.mNumberChannels), 1)
            let frameCount =
                Int(buffer.mDataByteSize)
                / (MemoryLayout<Float32>.size * channelCount)
            maximumFrames = max(maximumFrames, frameCount)
            let base = data.assumingMemoryBound(to: Float32.self)

            for channel in 0..<channelCount {
                let useSecond =
                    inputChannelCount > 1
                    && outputChannelIndex % inputChannelCount == 1
                let sourceBase = useSecond ? (secondBase ?? firstBase) : firstBase
                let sourceStride = useSecond ? secondStride : firstStride
                let sourceFrames = useSecond ? secondFrames : firstFrames
                let copiedFrames = min(frameCount, sourceFrames)
                for frame in 0..<copiedFrames {
                    let frameGain = GainDSP.gain(
                        startingAt: currentGain,
                        toward: targetGain,
                        frame: frame
                    )
                    base[frame * channelCount + channel] =
                        sourceBase[frame * sourceStride] * frameGain
                }
                if copiedFrames < frameCount {
                    for frame in copiedFrames..<frameCount {
                        base[frame * channelCount + channel] = 0
                    }
                }
                outputChannelIndex += 1
            }
        }

        currentGain = GainDSP.advancedGain(
            startingAt: currentGain,
            toward: targetGain,
            frameCount: maximumFrames
        )
        return GainDSP.smoothedPeak(
            rawPeak: rawPeak,
            previous: previousLevel
        )
    }
}
