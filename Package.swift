// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwishLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SwishLite",
            path: "Sources/SwishLite",
            linkerSettings: [
                .unsafeFlags([
                    "-F/System/Library/PrivateFrameworks",
                    "-framework", "MultitouchSupport",
                    "-framework", "IOKit"
                ])
            ]
        )
    ]
)
