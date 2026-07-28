// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TermiNap",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "TermiNap", targets: ["TermiNap"]),
    ],
    targets: [
        .target(
            name: "TermiNapCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "TermiNap",
            dependencies: ["TermiNapCore"]
        ),
        .testTarget(
            name: "TermiNapCoreTests",
            dependencies: ["TermiNapCore"]
        ),
    ]
)
