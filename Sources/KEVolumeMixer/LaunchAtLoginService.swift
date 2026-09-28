import Darwin
import Foundation
import OSLog
import ServiceManagement

enum LaunchAtLoginService {
    static let previewLabel = "dev.kestudios.volume-mixer.login"
    static let expectedExecutablePath =
        "/Applications/KE Volume Mixer.app/Contents/MacOS/KEVolumeMixer"

    private static let logger = Logger(
        subsystem: "dev.kestudios.volume-mixer",
        category: "launch-at-login"
    )

    private static var currentExecutableURL: URL? {
        Bundle.main.executableURL?.standardizedFileURL
    }

    private static var defaultLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(previewLabel).plist")
    }

    static var usesPreviewFallback: Bool {
        SMAppService.mainApp.status == .notFound
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled {
            return true
        }

        guard let executableURL = currentExecutableURL else { return false }
        return (try? verifyPreviewFallback(
            at: defaultLaunchAgentURL,
            executableURL: executableURL
        )) == true
    }

    static var statusDetail: String? {
        if SMAppService.mainApp.status == .requiresApproval {
            return "Approval is required in System Settings."
        }

        guard let executableURL = currentExecutableURL else {
            return nil
        }

        if (
            try? verifyPreviewFallback(
                at: defaultLaunchAgentURL,
                executableURL: executableURL
            )
        ) == true {
            return previewJobIsLoaded()
                ? "Preview LaunchAgent is active."
                : "Preview LaunchAgent is saved; it starts next sign-in."
        }

        if usesPreviewFallback {
            return executableURL.standardizedFileURL.path
                == expectedExecutablePath
                ? "Preview startup uses an app-owned LaunchAgent."
                : "Move the Preview to Applications to enable startup."
        }

        return nil
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard let executableURL = currentExecutableURL else {
            throw LaunchAtLoginError.executableUnavailable
        }

        if enabled {
            try enable(executableURL: executableURL)
        } else {
            try disable(executableURL: executableURL)
        }
    }

    private static func enable(executableURL: URL) throws {
        switch SMAppService.mainApp.status {
        case .enabled:
            return
        case .requiresApproval:
            throw LaunchAtLoginError.requiresApproval
        case .notRegistered:
            try SMAppService.mainApp.register()
            switch SMAppService.mainApp.status {
            case .enabled:
                logger.info("Launch at Login enabled with SMAppService")
                return
            case .requiresApproval:
                throw LaunchAtLoginError.requiresApproval
            case .notFound:
                break
            case .notRegistered:
                throw LaunchAtLoginError.registrationDidNotPersist
            @unknown default:
                throw LaunchAtLoginError.unknownServiceStatus
            }
        case .notFound:
            break
        @unknown default:
            throw LaunchAtLoginError.unknownServiceStatus
        }

        try installPreviewFallback(
            at: defaultLaunchAgentURL,
            executableURL: executableURL
        )
        logger.info(
            "Launch at Login configured with the narrow Preview LaunchAgent"
        )
    }

    private static func disable(executableURL: URL) throws {
        let fallbackExists =
            try launchAgentMetadata(at: defaultLaunchAgentURL) != nil
        if fallbackExists {
            guard
                try verifyPreviewFallback(
                    at: defaultLaunchAgentURL,
                    executableURL: executableURL
                )
            else {
                throw LaunchAtLoginError.verificationFailed
            }
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            try SMAppService.mainApp.unregister()
        case .notRegistered, .notFound:
            break
        @unknown default:
            throw LaunchAtLoginError.unknownServiceStatus
        }

        if FileManager.default.fileExists(
            atPath: defaultLaunchAgentURL.path
        ) {
            try removePreviewFallbackFile(
                at: defaultLaunchAgentURL,
                executableURL: executableURL
            )
        }

        if previewJobIsLoaded() {
            try runLaunchctl([
                "bootout",
                "gui/\(getuid())/\(previewLabel)",
            ])
        }
        logger.info("Launch at Login disabled")
    }

    static func installPreviewFallback(
        at launchAgentURL: URL,
        executableURL: URL
    ) throws {
        try requireExpectedExecutable(executableURL)
        let fileManager = FileManager.default
        let directoryURL = launchAgentURL.deletingLastPathComponent()

        if try launchAgentMetadata(at: directoryURL) != nil {
            try verifyLaunchAgentsDirectory(directoryURL)
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: directoryURL.path
            )
            try verifyLaunchAgentsDirectory(directoryURL)
        }

        if try launchAgentMetadata(at: launchAgentURL) != nil {
            guard
                try verifyPreviewFallback(
                    at: launchAgentURL,
                    executableURL: executableURL
                )
            else {
                throw LaunchAtLoginError.conflictingLaunchAgent
            }
        }

        let propertyList: [String: Any] = [
            "Label": previewLabel,
            "ProgramArguments": [expectedExecutablePath],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: launchAgentURL.path
        )

        guard
            try verifyPreviewFallback(
                at: launchAgentURL,
                executableURL: executableURL
            )
        else {
            throw LaunchAtLoginError.verificationFailed
        }
    }

    @discardableResult
    static func verifyPreviewFallback(
        at launchAgentURL: URL,
        executableURL: URL
    ) throws -> Bool {
        try requireExpectedExecutable(executableURL)
        guard let metadata = try launchAgentMetadata(at: launchAgentURL) else {
            return false
        }

        guard
            metadata.st_mode & S_IFMT == S_IFREG,
            metadata.st_nlink == 1
        else {
            throw LaunchAtLoginError.unsafeLaunchAgentFile
        }

        guard
            metadata.st_uid == getuid(),
            metadata.st_mode & 0o777 == 0o644
        else {
            throw LaunchAtLoginError.unsafeLaunchAgentMetadata
        }

        let data = try Data(contentsOf: launchAgentURL)
        guard data.count <= 4_096 else {
            throw LaunchAtLoginError.unsafeLaunchAgentContent
        }
        guard
            let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            propertyList.count == 3,
            propertyList["Label"] as? String == previewLabel,
            propertyList["ProgramArguments"] as? [String]
                == [expectedExecutablePath],
            propertyList["RunAtLoad"] as? Bool == true,
            propertyList["KeepAlive"] == nil
        else {
            throw LaunchAtLoginError.unsafeLaunchAgentContent
        }
        return true
    }

    static func removePreviewFallbackFile(
        at launchAgentURL: URL,
        executableURL: URL
    ) throws {
        guard
            try verifyPreviewFallback(
                at: launchAgentURL,
                executableURL: executableURL
            )
        else {
            return
        }
        try FileManager.default.removeItem(at: launchAgentURL)
    }

    private static func requireExpectedExecutable(
        _ executableURL: URL
    ) throws {
        guard executableURL.standardizedFileURL.path == expectedExecutablePath
        else {
            throw LaunchAtLoginError.unexpectedInstallLocation
        }
    }

    private static func verifyLaunchAgentsDirectory(
        _ directoryURL: URL
    ) throws {
        guard let metadata = try launchAgentMetadata(at: directoryURL) else {
            throw LaunchAtLoginError.unsafeLaunchAgentsDirectory
        }
        guard
            metadata.st_mode & S_IFMT == S_IFDIR,
            metadata.st_uid == getuid(),
            metadata.st_mode & 0o022 == 0
        else {
            throw LaunchAtLoginError.unsafeLaunchAgentsDirectory
        }
    }

    private static func launchAgentMetadata(
        at url: URL
    ) throws -> stat? {
        var metadata = stat()
        let status = url.path.withCString {
            Darwin.lstat($0, &metadata)
        }
        if status == 0 {
            return metadata
        }
        if errno == ENOENT {
            return nil
        }
        throw LaunchAtLoginError.metadataUnavailable
    }

    private static func previewJobIsLoaded() -> Bool {
        (try? runLaunchctl([
            "print",
            "gui/\(getuid())/\(previewLabel)",
        ])) != nil
    }

    private static func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LaunchAtLoginError.launchctlFailed
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case executableUnavailable
    case unexpectedInstallLocation
    case requiresApproval
    case registrationDidNotPersist
    case unknownServiceStatus
    case unsafeLaunchAgentsDirectory
    case unsafeLaunchAgentFile
    case unsafeLaunchAgentMetadata
    case unsafeLaunchAgentContent
    case conflictingLaunchAgent
    case verificationFailed
    case metadataUnavailable
    case launchctlFailed

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "The app executable could not be resolved."
        case .unexpectedInstallLocation:
            return "Move KE Volume Mixer to Applications before enabling startup."
        case .requiresApproval:
            return "Approve KE Volume Mixer in System Settings > Login Items."
        case .registrationDidNotPersist:
            return "macOS did not retain the login-item registration."
        case .unknownServiceStatus:
            return "macOS returned an unknown login-item status."
        case .unsafeLaunchAgentsDirectory:
            return "The user LaunchAgents directory failed validation."
        case .unsafeLaunchAgentFile, .unsafeLaunchAgentMetadata,
            .unsafeLaunchAgentContent, .conflictingLaunchAgent:
            return "The existing Preview startup file failed validation."
        case .verificationFailed:
            return "The Preview startup file could not be verified."
        case .metadataUnavailable:
            return "The Preview startup file metadata could not be read."
        case .launchctlFailed:
            return "The exact Preview login job could not be removed."
        }
    }
}
