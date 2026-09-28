import XCTest
@testable import KEVolumeMixer

final class AudioMathTests: XCTestCase {
    func testVolumeClamp() {
        XCTAssertEqual(AudioMath.clampedVolume(-0.5), 0)
        XCTAssertEqual(AudioMath.clampedVolume(0.42), 0.42)
        XCTAssertEqual(AudioMath.clampedVolume(2), 1)
    }

    func testSignalThresholdSeparatesSilenceFromRealSamples() {
        XCTAssertFalse(AudioMath.isSignalActive(0))
        XCTAssertFalse(AudioMath.isSignalActive(0.000_99))
        XCTAssertTrue(AudioMath.isSignalActive(0.001))
        XCTAssertTrue(AudioMath.isSignalActive(0.25))
    }

    func testMeterCurveKeepsQuietSignalsVisibleAndBounded() {
        XCTAssertEqual(AudioMath.meterFraction(for: 0), 0)
        XCTAssertEqual(AudioMath.meterFraction(for: 1), 1)
        XCTAssertEqual(AudioMath.meterFraction(for: 4), 1)
        XCTAssertGreaterThan(AudioMath.meterFraction(for: 0.01), 0.01)
    }

    func testPeakSmoothingAttacksFasterThanItDecays() {
        let attack = AudioMath.smoothedPeak(current: 0, incoming: 1)
        let decay = AudioMath.smoothedPeak(current: 1, incoming: 0)
        XCTAssertEqual(attack, 0.52, accuracy: 0.000_1)
        XCTAssertEqual(decay, 0.86, accuracy: 0.000_1)
    }
}
