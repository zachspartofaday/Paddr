// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "PuckPads",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TrackIsBackCore", targets: ["TrackIsBackCore"]),
        .executable(name: "PuckPads", targets: ["TrackIsBackCLI"]),
        .executable(name: "PuckPadsMenu", targets: ["TrackIsBackMenu"])
    ],
    targets: [
        .target(name: "TrackIsBackCore"),
        .executableTarget(name: "TrackIsBackCLI", dependencies: ["TrackIsBackCore"]),
        .executableTarget(name: "TrackIsBackMenu", dependencies: ["TrackIsBackCore"]),
        .testTarget(name: "TrackIsBackTests", dependencies: ["TrackIsBackCore"])
    ]
)
