import XCTest
import MixerAtomics
@testable import MixerCore

final class GainDSPTests: XCTestCase {
    func testUnityGainIsExactAfterSettling() {
        var gain: Float = 1
        let input: [Float] = [-1, -0.5, 0, 0.5, 1]
        let result = GainDSP.process(samples: input, targetGain: 1, currentGain: &gain)

        XCTAssertEqual(result.samples, input)
        XCTAssertEqual(result.rawPeak, 1)
        XCTAssertEqual(gain, 1)
    }

    func testGainRampsWithoutOvershoot() {
        var gain: Float = 1
        let input = [Float](repeating: 1, count: 1_100)
        let result = GainDSP.process(
            samples: input,
            targetGain: 0,
            currentGain: &gain,
            rampPerFrame: 0.001
        )

        XCTAssertGreaterThan(result.samples[0], result.samples[500])
        XCTAssertGreaterThanOrEqual(result.samples.min() ?? -1, 0)
        XCTAssertLessThanOrEqual(result.samples.max() ?? 2, 1)
        XCTAssertEqual(gain, 0, accuracy: 0.000_01)
    }

    func testAttenuationAppliesAtSettledGain() {
        var gain: Float = 0.25
        let result = GainDSP.process(
            samples: [1, -0.8, 0.4],
            targetGain: 0.25,
            currentGain: &gain
        )

        XCTAssertEqual(result.samples[0], 0.25, accuracy: 0.000_01)
        XCTAssertEqual(result.samples[1], -0.2, accuracy: 0.000_01)
        XCTAssertEqual(result.samples[2], 0.1, accuracy: 0.000_01)
        XCTAssertEqual(result.rawPeak, 1)
    }

    func testMeterAttackAndReleaseRemainBounded() {
        let attack = GainDSP.smoothedPeak(rawPeak: 1, previous: 0)
        let release = GainDSP.smoothedPeak(rawPeak: 0, previous: attack)

        XCTAssertGreaterThan(attack, 0)
        XCTAssertLessThan(attack, 1)
        XCTAssertGreaterThan(release, 0)
        XCTAssertLessThan(release, attack)
    }

    func testGainClampsToSafeRange() {
        XCTAssertEqual(GainDSP.clampedGain(-2), 0)
        XCTAssertEqual(GainDSP.clampedGain(0.4), 0.4)
        XCTAssertEqual(GainDSP.clampedGain(8), 1)
    }

    func testCallbackFloatStorageIsLockFree() {
        guard let storage = KEMixerAtomicFloatCreate(0.25) else {
            return XCTFail("atomic float allocation failed")
        }
        defer { KEMixerAtomicFloatDestroy(storage) }

        XCTAssertTrue(KEMixerAtomicFloatIsLockFree(storage))
        XCTAssertEqual(KEMixerAtomicFloatLoad(storage), 0.25)
        KEMixerAtomicFloatStore(storage, 0.75)
        XCTAssertEqual(KEMixerAtomicFloatLoad(storage), 0.75)
    }
}
