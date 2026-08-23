// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Paddr",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "PaddrCore", targets: ["PaddrCore"]),
        .executable(name: "Paddr", targets: ["PaddrMenu"]),
        .executable(name: "PaddrCLI", targets: ["PaddrCLI"])
    ],
    targets: [
        .target(name: "PaddrCore"),
        .target(name: "PaddrCLIKit", dependencies: ["PaddrCore"]),
        .executableTarget(name: "PaddrCLI", dependencies: ["PaddrCore", "PaddrCLIKit"]),
        .target(
            name: "PaddrAppSupport",
            dependencies: ["PaddrCore"]
        ),
        .executableTarget(
            name: "PaddrMenu",
            dependencies: ["PaddrCore", "PaddrAppSupport"]
        ),
        .testTarget(name: "PaddrTests", dependencies: ["PaddrCore"]),
        .testTarget(name: "PaddrCLITests", dependencies: ["PaddrCLIKit"]),
        .testTarget(
            name: "PaddrAppSupportTests",
            dependencies: ["PaddrAppSupport", "PaddrCore", "PaddrMenu"]
        )
    ]
)
