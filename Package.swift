// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIUsageLocal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIUsageLocal", targets: ["AIUsageLocal"])
    ],
    targets: [
        .executableTarget(
            name: "AIUsageLocal",
            path: "App/Sources/AIUsageLocal",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "AIUsageLocalTests",
            dependencies: ["AIUsageLocal"],
            path: "App/Tests/AIUsageLocalTests"
        )
    ]
)
