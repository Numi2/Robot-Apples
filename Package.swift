// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LiDARSplatRobotVisionLab",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "RobotVisionLabCore",
            targets: ["RobotVisionLabCore"]
        ),
        .library(
            name: "RobotSceneStudioiPhone",
            targets: ["RobotSceneStudioiPhone"]
        ),
        .library(
            name: "RobotSceneStudioMac",
            targets: ["RobotSceneStudioMac"]
        ),
        .library(
            name: "RobotSceneStudioVision",
            targets: ["RobotSceneStudioVision"]
        ),
        .executable(
            name: "robot-scene-studio-mac",
            targets: ["RobotSceneStudioMacApp"]
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
        .target(
            name: "RobotSceneStudioiPhone",
            dependencies: ["RobotVisionLabCore"]
        ),
        .target(
            name: "RobotSceneStudioMac",
            dependencies: ["RobotVisionLabCore"]
        ),
        .target(
            name: "RobotSceneStudioVision",
            dependencies: ["RobotVisionLabCore"]
        ),
        .executableTarget(
            name: "RobotSceneStudioMacApp",
            dependencies: ["RobotSceneStudioMac"]
        ),
        .executableTarget(
            name: "RobotVisionLabCLI",
            dependencies: ["RobotVisionLabCore"]
        )
    ]
)
