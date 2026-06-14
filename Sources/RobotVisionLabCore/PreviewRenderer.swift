import Foundation
import simd

public struct PreviewSyntheticRenderer: SplatRenderer {
    public init() {}

    public func render(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig, outputDirectory: URL) async throws {
        try renderSynchronously(frame: frame, scene: scene, cameraRig: cameraRig, outputDirectory: outputDirectory)
    }

    public func renderSynchronously(
        frame: DatasetFrame,
        scene: GaussianSplatScene,
        cameraRig: RobotCameraRig,
        outputDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("rgb", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("depth", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("segmentation", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("obstacleMask", isDirectory: true), withIntermediateDirectories: true)

        let ppmURL = outputDirectory
            .appendingPathComponent("rgb", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.ppm", frame.index))
        try makePreviewPPM(frame: frame, scene: scene, cameraRig: cameraRig).write(to: ppmURL)

        let depthURL = outputDirectory
            .appendingPathComponent("depth", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.json", frame.index))
        try JSONEncoder.robotVisionLabEncoder.encode(makeDepthApproximation(frame: frame, scene: scene)).write(to: depthURL)

        let segmentationURL = outputDirectory
            .appendingPathComponent("segmentation", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.json", frame.index))
        try JSONEncoder.robotVisionLabEncoder.encode(makeSegmentationApproximation(frame: frame)).write(to: segmentationURL)

        let obstacleURL = outputDirectory
            .appendingPathComponent("obstacleMask", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.json", frame.index))
        try JSONEncoder.robotVisionLabEncoder.encode(makeObstacleApproximation(frame: frame, scene: scene)).write(to: obstacleURL)
    }

    private func makePreviewPPM(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig) -> Data {
        let width = min(cameraRig.intrinsics.width, 320)
        let height = min(cameraRig.intrinsics.height, 180)
        var bytes = Array("P6\n\(width) \(height)\n255\n".utf8)

        let pose = frame.cameraPose.position
        let sceneSpan = max(scene.bounds.maximum - scene.bounds.minimum, SIMD3<Double>(0.001, 0.001, 0.001))
        let normalized = (pose - scene.bounds.minimum) / sceneSpan

        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x) / Double(max(width - 1, 1))
                let v = Double(y) / Double(max(height - 1, 1))
                let red = UInt8(clamping: Int((u * 160.0) + normalized.x * 95.0))
                let green = UInt8(clamping: Int((v * 150.0) + normalized.y * 105.0))
                let blue = UInt8(clamping: Int(((1.0 - u) * 90.0) + normalized.z * 140.0))
                bytes.append(contentsOf: [red, green, blue])
            }
        }

        return Data(bytes)
    }

    private func makeDepthApproximation(frame: DatasetFrame, scene: GaussianSplatScene) -> DepthApproximation {
        let position = frame.cameraPose.position
        let distances = [
            abs(position.x - scene.bounds.minimum.x),
            abs(scene.bounds.maximum.x - position.x),
            abs(position.z - scene.bounds.minimum.z),
            abs(scene.bounds.maximum.z - position.z)
        ]
        let nearestObstacle = distances.min() ?? 0
        return DepthApproximation(
            frameIndex: frame.index,
            units: .meters,
            nearestObstacleMeters: nearestObstacle,
            farClipMeters: 20,
            method: "axis_aligned_scene_bounds_preview"
        )
    }

    private func makeSegmentationApproximation(frame: DatasetFrame) -> SegmentationApproximation {
        SegmentationApproximation(
            frameIndex: frame.index,
            classes: [
                SegmentationClass(id: 0, name: "background", source: "preview"),
                SegmentationClass(id: 1, name: "floor", source: "RoomPlan"),
                SegmentationClass(id: 2, name: "wall", source: "RoomPlan"),
                SegmentationClass(id: 3, name: "navigation_target", source: frame.navigationTarget?.label ?? "none")
            ]
        )
    }

    private func makeObstacleApproximation(frame: DatasetFrame, scene: GaussianSplatScene) -> ObstacleApproximation {
        let depth = makeDepthApproximation(frame: frame, scene: scene)
        return ObstacleApproximation(
            frameIndex: frame.index,
            hasObstacleAhead: depth.nearestObstacleMeters < 0.45,
            nearestObstacleMeters: depth.nearestObstacleMeters,
            method: depth.method
        )
    }
}

public struct DepthApproximation: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var units: WorldUnit
    public var nearestObstacleMeters: Double
    public var farClipMeters: Double
    public var method: String

    public init(frameIndex: Int, units: WorldUnit, nearestObstacleMeters: Double, farClipMeters: Double, method: String) {
        self.frameIndex = frameIndex
        self.units = units
        self.nearestObstacleMeters = nearestObstacleMeters
        self.farClipMeters = farClipMeters
        self.method = method
    }
}

public struct SegmentationApproximation: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var classes: [SegmentationClass]

    public init(frameIndex: Int, classes: [SegmentationClass]) {
        self.frameIndex = frameIndex
        self.classes = classes
    }
}

public struct SegmentationClass: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var source: String

    public init(id: Int, name: String, source: String) {
        self.id = id
        self.name = name
        self.source = source
    }
}

public struct ObstacleApproximation: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var hasObstacleAhead: Bool
    public var nearestObstacleMeters: Double
    public var method: String

    public init(frameIndex: Int, hasObstacleAhead: Bool, nearestObstacleMeters: Double, method: String) {
        self.frameIndex = frameIndex
        self.hasObstacleAhead = hasObstacleAhead
        self.nearestObstacleMeters = nearestObstacleMeters
        self.method = method
    }
}

