// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
        .executable(name: "QuotaBar", targets: ["QuotaBar"]),
    ],
    targets: [
        .target(name: "QuotaBarCore"),
        .executableTarget(name: "QuotaBar", dependencies: ["QuotaBarCore"]),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]),
        .testTarget(
            name: "QuotaBarAppTests",
            dependencies: ["QuotaBar"]),
    ],
    swiftLanguageModes: [.v5])
