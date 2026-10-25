// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartEntry",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SmartEntry", targets: ["SmartEntry"]),
    ],
    dependencies: [
        .package(path: "../AviationCatalogCore"),
    ],
    targets: [
        .target(
            name: "SmartEntry",
            dependencies: [
                .product(name: "AviationCatalog", package: "AviationCatalogCore"),
            ]
        ),
        .testTarget(
            name: "SmartEntryTests",
            dependencies: [
                "SmartEntry",
                .product(name: "AviationCatalog", package: "AviationCatalogCore"),
            ]
        ),
    ]
)
