// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AviationCatalog",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AviationCatalog", targets: ["AviationCatalog"]),
    ],
    targets: [
        .target(
            name: "AviationCatalog",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AviationCatalogTests",
            dependencies: ["AviationCatalog"],
            resources: [.process("Fixtures")]
        ),
    ]
)
