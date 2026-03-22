// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HiDPITool",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HiDPITool",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "SkyLight",
                    "-framework", "CoreDisplay",
                ]),
            ]
        ),
    ]
)
