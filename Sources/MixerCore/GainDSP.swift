import Foundation

/// Allocation-free gain and meter helpers shared by the Core Audio callback
/// and deterministic unit tests.
public enum GainDSP {
    public static let defaultRampPerFrame: Float = 0.001

    public static func clampedGain(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    public static func gain(
        startingAt current: Float,
        toward target: Float,
        frame: Int,
        rampPerFrame: Float = defaultRampPerFrame
    ) -> Float {
        guard frame >= 0 else { return current }
        let distance = rampPerFrame * Float(frame + 1)
        if current < target {
            return min(current + distance, target)
        }
        if current > target {
            return max(current - distance, target)
        }
        return target
    }

    public static func advancedGain(
        startingAt current: Float,
        toward target: Float,
        frameCount: Int,
        rampPerFrame: Float = defaultRampPerFrame
    ) -> Float {
        guard frameCount > 0 else { return current }
        return gain(
            startingAt: current,
            toward: target,
            frame: frameCount - 1,
            rampPerFrame: rampPerFrame
        )
    }

    /// Fast attack and slower release keep the menu meter legible without
    /// claiming that an open-but-silent audio session is making noise.
    public static func smoothedPeak(rawPeak: Float, previous: Float) -> Float {
        let peak = min(max(rawPeak, 0), 1)
        let coefficient: Float = peak >= previous ? 0.42 : 0.12
        let value = previous + coefficient * (peak - previous)
        return value < 0.000_01 ? 0 : value
    }

    /// Reference implementation for deterministic verification. The live audio
    /// callback uses the same frame-gain helpers without allocating arrays.
    public static func process(
        samples: [Float],
        targetGain: Float,
        currentGain: inout Float,
        rampPerFrame: Float = defaultRampPerFrame
    ) -> (samples: [Float], rawPeak: Float) {
        let target = clampedGain(targetGain)
        var peak: Float = 0
        var output = [Float]()
        output.reserveCapacity(samples.count)

        for (index, sample) in samples.enumerated() {
            peak = max(peak, abs(sample))
            let frameGain = gain(
                startingAt: currentGain,
                toward: target,
                frame: index,
                rampPerFrame: rampPerFrame
            )
            output.append(sample * frameGain)
        }

        currentGain = advancedGain(
            startingAt: currentGain,
            toward: target,
            frameCount: samples.count,
            rampPerFrame: rampPerFrame
        )
        return (output, peak)
    }
}
