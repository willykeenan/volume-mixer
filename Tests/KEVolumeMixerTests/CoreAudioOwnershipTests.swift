import XCTest
@testable import KEVolumeMixer

final class CoreAudioOwnershipTests: XCTestCase {
    func testCallerOwnedCFPropertiesBridgeRepeatedlyUnderARC() throws {
        guard let device = CoreAudioUtils.defaultOutputDevice() else {
            throw XCTSkip("This machine has no default output device.")
        }

        for _ in 0..<2_000 {
            autoreleasepool {
                XCTAssertFalse(
                    CoreAudioUtils.deviceName(device)?.isEmpty ?? true
                )
                XCTAssertFalse(
                    CoreAudioUtils.deviceUID(device)?.isEmpty ?? true
                )
                for process in CoreAudioUtils.processObjectList().prefix(8) {
                    _ = CoreAudioUtils.bundleID(of: process)
                }
            }
        }
    }
}
