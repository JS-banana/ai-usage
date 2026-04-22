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
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Ingestion", targets: ["Ingestion"]),
        .library(name: "Query", targets: ["Query"]),
        .executable(name: "AIUsageLocal", targets: ["AIUsageLocal"])
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
            name: "ParserCore",
            dependencies: ["Domain", "Support"],
            path: "Packages/ParserCore/Sources/ParserCore"
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                "Support",
                "Ingestion",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Packages/Persistence/Sources/Persistence"
        ),
        .target(
            name: "Ingestion",
            dependencies: ["Domain", "ParserCore", "Support"],
            path: "Packages/Ingestion/Sources/Ingestion"
        ),
        .target(
            name: "Query",
            dependencies: ["Domain", "Persistence"],
            path: "Packages/Query/Sources/Query"
        ),
        .executableTarget(
            name: "AIUsageLocal",
            dependencies: ["Domain", "Ingestion", "Persistence", "Query"],
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
            name: "IngestionTests",
            dependencies: ["Ingestion", "ParserCore", "Domain", "Support"],
            path: "Packages/Ingestion/Tests/IngestionTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Ingestion", "Domain", "Support"],
            path: "Packages/Persistence/Tests/PersistenceTests"
        ),
        .testTarget(
            name: "QueryTests",
            dependencies: ["Query", "Persistence", "Ingestion", "Domain", "Support"],
            path: "Packages/Query/Tests/QueryTests"
        ),
        .testTarget(
            name: "AIUsageLocalTests",
            dependencies: ["AIUsageLocal", "Support"],
            path: "App/Tests/AIUsageLocalTests"
        )
    ]
)
