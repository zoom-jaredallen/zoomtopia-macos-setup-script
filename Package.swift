// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZoomtopiaSetup",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ZoomtopiaSetupApp", targets: ["ZoomtopiaSetupApp"])
    ],
    targets: [
        .executableTarget(
            name: "ZoomtopiaSetupApp",
            path: "Sources/ZoomtopiaSetupApp"
        )
    ]
)
