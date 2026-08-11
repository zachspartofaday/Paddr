// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Paddr",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TrackIsBackCore", targets: ["TrackIsBackCore"]),
        .executable(name: "Paddr", targets: ["TrackIsBackMenu"]),
        .executable(name: "PaddrCLI", targets: ["TrackIsBackCLI"])
    ],
    targets: [
        .target(name: "TrackIsBackCore"),
        .executableTarget(name: "TrackIsBackCLI", dependencies: ["TrackIsBackCore"]),
        .target(
            name: "PaddrAppSupport",
            dependencies: ["TrackIsBackCore"]
        ),
        .executableTarget(
            name: "TrackIsBackMenu",
            dependencies: ["TrackIsBackCore", "PaddrAppSupport"]
        ),
        .testTarget(name: "TrackIsBackTests", dependencies: ["TrackIsBackCore"]),
        .testTarget(
            name: "PaddrAppSupportTests",
            dependencies: ["PaddrAppSupport", "TrackIsBackCore"]
        )
    ]
)
