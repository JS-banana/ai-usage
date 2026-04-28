// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AiUsage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "ProviderKit", targets: ["ProviderKit"]),
        .library(name: "Support", targets: ["Support"]),
        .library(name: "ParserCore", targets: ["ParserCore"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Ingestion", targets: ["Ingestion"]),
        .library(name: "Query", targets: ["Query"]),
        .executable(name: "AiUsage", targets: ["AiUsage"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.5.0")
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
            name: "ProviderKit",
            dependencies: ["Domain"],
            path: "Packages/ProviderKit/Sources/ProviderKit"
        ),
        .target(
            name: "ParserCore",
            dependencies: ["Domain", "Support"],
            path: "Packages/ParserCore/Sources/ParserCore"
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                "Support",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Packages/Persistence/Sources/Persistence"
        ),
        .target(
            name: "Ingestion",
            dependencies: ["Domain", "ProviderKit", "ParserCore", "Support"],
            path: "Packages/Ingestion/Sources/Ingestion"
        ),
        .target(
            name: "Query",
            dependencies: ["Domain", "Persistence"],
            path: "Packages/Query/Sources/Query"
        ),
        .executableTarget(
            name: "AiUsage",
            dependencies: ["Domain", "ProviderKit", "Ingestion", "Persistence", "Query"],
            path: "App/Sources/AiUsage",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "ParserCoreTests",
            dependencies: ["ParserCore", "Domain", "Support"],
            path: "Packages/ParserCore/Tests/ParserCoreTests",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "IngestionTests",
            dependencies: ["Ingestion", "ParserCore", "Domain", "Support"],
            path: "Packages/Ingestion/Tests/IngestionTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Domain", "Support"],
            path: "Packages/Persistence/Tests/PersistenceTests"
        ),
        .testTarget(
            name: "QueryTests",
            dependencies: ["Query", "Persistence", "Domain", "Support"],
            path: "Packages/Query/Tests/QueryTests"
        ),
        .testTarget(
            name: "AiUsageTests",
            dependencies: ["AiUsage", "Support"],
            path: "App/Tests/AiUsageTests"
        )
    ]
)
