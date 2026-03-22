// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HiDPIApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HiDPIApp",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "SkyLight",
                    "-framework", "CoreDisplay",
                    "-framework", "DisplayServices",
                    "-framework", "CoreBrightness",
                    "-framework", "BezelServices",
                    "-framework", "OSD",
                ]),
            ]
        ),
    ]
)
