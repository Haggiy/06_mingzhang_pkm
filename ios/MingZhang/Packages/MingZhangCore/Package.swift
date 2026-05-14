// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MingZhangCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MingZhangCore",
            targets: ["MingZhangCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2")
    ],
    targets: [
        .target(
            name: "MingZhangCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CoreXLSX", package: "CoreXLSX")
            ]
        ),
        .testTarget(
            name: "MingZhangCoreTests",
            dependencies: ["MingZhangCore"],
            exclude: ["Fixtures"]
        )
    ]
)
