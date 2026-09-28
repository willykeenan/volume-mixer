import Foundation
import XCTest
@testable import KEVolumeMixer

final class LaunchAtLoginServiceTests: XCTestCase {
    private let exactExecutable = URL(
        fileURLWithPath:
            "/Applications/KE Volume Mixer.app/Contents/MacOS/KEVolumeMixer"
    )

    func testPreviewLaunchAgentIsMinimalExactAndVerifiable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ke-volume-mixer-login-\(UUID().uuidString)",
            isDirectory: true
        )
        let file = root.appendingPathComponent(
            "\(LaunchAtLoginService.previewLabel).plist"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try LaunchAtLoginService.installPreviewFallback(
            at: file,
            executableURL: exactExecutable
        )
        XCTAssertTrue(
            try LaunchAtLoginService.verifyPreviewFallback(
                at: file,
                executableURL: exactExecutable
            )
        )

        let data = try Data(contentsOf: file)
        let propertyList = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(
            Set(propertyList.keys),
            Set(["Label", "ProgramArguments", "RunAtLoad"])
        )
        XCTAssertEqual(
            propertyList["ProgramArguments"] as? [String],
            [LaunchAtLoginService.expectedExecutablePath]
        )
        XCTAssertEqual(propertyList["RunAtLoad"] as? Bool, true)
        XCTAssertNil(propertyList["KeepAlive"])

        let attributes = try FileManager.default.attributesOfItem(
            atPath: file.path
        )
        XCTAssertEqual(
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            getuid()
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            0o644
        )

        try LaunchAtLoginService.removePreviewFallbackFile(
            at: file,
            executableURL: exactExecutable
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testPreviewLaunchAgentFailsClosedOnForeignContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ke-volume-mixer-login-drift-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(
            "\(LaunchAtLoginService.previewLabel).plist"
        )
        let foreign: [String: Any] = [
            "Label": LaunchAtLoginService.previewLabel,
            "ProgramArguments": ["/bin/sh", "-c", "true"],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: foreign,
            format: .xml,
            options: 0
        )
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: file.path
        )

        XCTAssertThrowsError(
            try LaunchAtLoginService.installPreviewFallback(
                at: file,
                executableURL: exactExecutable
            )
        )
        XCTAssertThrowsError(
            try LaunchAtLoginService.removePreviewFallbackFile(
                at: file,
                executableURL: exactExecutable
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPreviewLaunchAgentFailsClosedOnMetadataDrift() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ke-volume-mixer-login-mode-\(UUID().uuidString)",
            isDirectory: true
        )
        let file = root.appendingPathComponent(
            "\(LaunchAtLoginService.previewLabel).plist"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try LaunchAtLoginService.installPreviewFallback(
            at: file,
            executableURL: exactExecutable
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: file.path
        )

        XCTAssertThrowsError(
            try LaunchAtLoginService.verifyPreviewFallback(
                at: file,
                executableURL: exactExecutable
            )
        )
        XCTAssertThrowsError(
            try LaunchAtLoginService.removePreviewFallbackFile(
                at: file,
                executableURL: exactExecutable
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPreviewLaunchAgentRejectsSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ke-volume-mixer-login-symlink-\(UUID().uuidString)",
            isDirectory: true
        )
        let target = root.appendingPathComponent("target.plist")
        let link = root.appendingPathComponent(
            "\(LaunchAtLoginService.previewLabel).plist"
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try LaunchAtLoginService.installPreviewFallback(
            at: target,
            executableURL: exactExecutable
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try LaunchAtLoginService.verifyPreviewFallback(
                at: link,
                executableURL: exactExecutable
            )
        )
        XCTAssertThrowsError(
            try LaunchAtLoginService.installPreviewFallback(
                at: link,
                executableURL: exactExecutable
            )
        )
    }

    func testPreviewFallbackRequiresExactApplicationsExecutable() {
        let wrongExecutable = URL(
            fileURLWithPath: "/tmp/KE Volume Mixer.app/KEVolumeMixer"
        )
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).plist"
        )

        XCTAssertThrowsError(
            try LaunchAtLoginService.installPreviewFallback(
                at: file,
                executableURL: wrongExecutable
            )
        )
    }
}
