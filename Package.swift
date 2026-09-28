// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KEVolumeMixer",
    platforms: [
        .macOS("14.4"),
    ],
    products: [
        .executable(name: "KEVolumeMixer", targets: ["KEVolumeMixer"]),
    ],
    targets: [
        .target(
            name: "MixerAtomics",
            path: "Sources/MixerAtomics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MixerCore",
            path: "Sources/MixerCore"
        ),
        .executableTarget(
            name: "KEVolumeMixer",
            dependencies: ["MixerAtomics", "MixerCore"],
            path: "Sources/KEVolumeMixer"
        ),
        .testTarget(
            name: "MixerCoreTests",
            dependencies: ["MixerAtomics", "MixerCore"],
            path: "Tests/MixerCoreTests"
        ),
        .testTarget(
            name: "KEVolumeMixerTests",
            dependencies: ["KEVolumeMixer"],
            path: "Tests/KEVolumeMixerTests"
        ),
    ]
)
