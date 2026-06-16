// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LiDARSplatRobotVisionLab",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v26)
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
        .library(
            name: "RobotSceneStudioSplatViewer",
            targets: ["RobotSceneStudioSplatViewer"]
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
    dependencies: [
        .package(url: "https://github.com/scier/MetalSplatter.git", branch: "main")
    ],
    targets: [
        .target(
            name: "RobotVisionLabCore",
            dependencies: [
                .product(name: "SplatIO", package: "MetalSplatter")
            ]
        ),
        .target(
            name: "RobotSceneStudioiPhone",
            dependencies: [
                "RobotVisionLabCore",
                "RobotSceneStudioSplatViewer"
            ]
        ),
        .target(
            name: "RobotSceneStudioMac",
            dependencies: [
                "RobotVisionLabCore",
                "RobotSceneStudioSplatViewer"
            ]
        ),
        .target(
            name: "RobotSceneStudioVision",
            dependencies: [
                "RobotVisionLabCore",
                "RobotSceneStudioSplatViewer"
            ]
        ),
        .target(
            name: "RobotSceneStudioSplatViewer",
            dependencies: [
                "RobotVisionLabCore",
                .product(name: "MetalSplatter", package: "MetalSplatter"),
                .product(name: "SplatIO", package: "MetalSplatter")
            ]
        ),
        .executableTarget(
            name: "RobotSceneStudioMacApp",
            dependencies: ["RobotSceneStudioMac"]
        ),
        .executableTarget(
            name: "RobotVisionLabCLI",
            dependencies: ["RobotVisionLabCore", "RobotSceneStudioVision"]
        )
    ],
    swiftLanguageModes: [.v6]
)
