// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LiDARSplatRobotVisionLab",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RobotVisionLabCore",
            targets: ["RobotVisionLabCore"]
        ),
        .executable(
            name: "robot-vision-lab",
            targets: ["RobotVisionLabCLI"]
        )
    ],
    targets: [
        .target(
            name: "RobotVisionLabCore"
        ),
        .executableTarget(
            name: "RobotVisionLabCLI",
            dependencies: ["RobotVisionLabCore"]
        )
    ]
)
