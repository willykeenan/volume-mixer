import Foundation

enum AudioMath {
    static let signalFloor: Float = 0.001

    static func clampedVolume(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    static func isSignalActive(_ peak: Float) -> Bool {
        peak >= signalFloor
    }

    static func smoothedPeak(current: Float, incoming: Float) -> Float {
        let coefficient: Float = incoming > current ? 0.52 : 0.14
        let next = current + coefficient * (incoming - current)
        return next < 0.000_01 ? 0 : min(max(next, 0), 1)
    }

    static func meterFraction(for peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        // A square-root curve keeps quiet speech and notification sounds visible
        // without claiming that the meter is a calibrated dBFS instrument.
        return min(max(sqrt(peak), 0), 1)
    }
}
