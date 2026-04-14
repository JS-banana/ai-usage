// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageLocal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Support", targets: ["Support"]),
        .library(name: "ParserCore", targets: ["ParserCore"]),
        .executable(name: "AIUsageLocal", targets: ["AIUsageLocal"])
    ],
    targets: [
        .target(
            name: "Domain",
            path: "Packages/Domain/Sources/Domain"
        ),
        .target(
            name: "Support",
            dependencies: ["Domain"],
            path: "Packages/Support/Sources/Support"
        ),
        .target(
            name: "ParserCore",
            dependencies: ["Domain", "Support"],
            path: "Packages/ParserCore/Sources/ParserCore"
        ),
        .executableTarget(
            name: "AIUsageLocal",
            dependencies: ["Domain", "ParserCore", "Support"],
            path: "App/Sources/AIUsageLocal",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "ParserCoreTests",
            dependencies: ["ParserCore", "Domain", "Support"],
            path: "Packages/ParserCore/Tests/ParserCoreTests",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AIUsageLocalTests",
            dependencies: ["AIUsageLocal"],
            path: "App/Tests/AIUsageLocalTests"
        )
    ]
)
