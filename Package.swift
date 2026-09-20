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
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarCore"],
            // The real provider marks, carried as resources rather than redrawn
            // in Swift. `.process` flattens them into the generated
            // QuotaBar_QuotaBar.bundle, which build.sh copies into the app.
            resources: [.process("Resources/ProviderMarks")]),
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
