// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZoomtopiaSetup",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ZoomtopiaSetupApp", targets: ["ZoomtopiaSetupApp"])
    ],
    targets: [
        .target(name: "SetupCore"),
        .testTarget(name: "SetupCoreTests", dependencies: ["SetupCore"]),
        .executableTarget(name: "PayloadVerifier", dependencies: ["SetupCore"]),
        .executableTarget(
            name: "ZoomtopiaSetupApp",
            dependencies: ["SetupCore"],
            path: "Sources/ZoomtopiaSetupApp"
        )
    ]
)
