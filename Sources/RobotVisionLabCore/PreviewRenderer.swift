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
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("visibility", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("segmentation", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("obstacleMask", isDirectory: true), withIntermediateDirectories: true)

        let ppmURL = outputDirectory
            .appendingPathComponent("rgb", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.ppm", frame.index))
        try makePreviewPPM(frame: frame, scene: scene, cameraRig: cameraRig).write(to: ppmURL)

        let depthURL = outputDirectory
            .appendingPathComponent("depth", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.pgm", frame.index))
        try makePreviewDepthPGM(frame: frame, scene: scene, cameraRig: cameraRig).write(to: depthURL)

        let depthMetadataURL = outputDirectory
            .appendingPathComponent("depth", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d_summary.json", frame.index))
        try JSONEncoder.robotVisionLabEncoder.encode(makeDepthApproximation(frame: frame, scene: scene)).write(to: depthMetadataURL)

        let visibilityURL = outputDirectory
            .appendingPathComponent("visibility", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.pgm", frame.index))
        try makePreviewVisibilityPGM(frame: frame, scene: scene, cameraRig: cameraRig).write(to: visibilityURL)

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

    private func makePreviewDepthPGM(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig) -> Data {
        let width = min(cameraRig.intrinsics.width, 320)
        let height = min(cameraRig.intrinsics.height, 180)
        let depth = makeDepthApproximation(frame: frame, scene: scene)
        let nearest = max(depth.nearestObstacleMeters, 0.05)
        let far = max(depth.farClipMeters, nearest + 0.001)
        var bytes = Array("P5\n\(width) \(height)\n255\n".utf8)
        bytes.reserveCapacity(bytes.count + width * height)
        for y in 0..<height {
            for x in 0..<width {
                let horizontal = abs(Double(x) / Double(max(width - 1, 1)) - 0.5)
                let vertical = abs(Double(y) / Double(max(height - 1, 1)) - 0.5)
                let meters = min(far, nearest + (horizontal + vertical) * 2.5)
                let normalized = UInt8(clamping: Int(((meters - nearest) / (far - nearest) * 255.0).rounded()))
                bytes.append(255 &- normalized)
            }
        }
        return Data(bytes)
    }

    private func makePreviewVisibilityPGM(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig) -> Data {
        let width = min(cameraRig.intrinsics.width, 320)
        let height = min(cameraRig.intrinsics.height, 180)
        let position = frame.cameraPose.position
        let center = (scene.bounds.minimum + scene.bounds.maximum) / 2
        let distance = simd_length(position - center)
        let baseCoverage = max(0.1, min(1.0, 1.0 / max(distance, 0.5)))
        var bytes = Array("P5\n\(width) \(height)\n255\n".utf8)
        bytes.reserveCapacity(bytes.count + width * height)
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x) / Double(max(width - 1, 1))
                let v = Double(y) / Double(max(height - 1, 1))
                let radial = 1.0 - min(1.0, hypot(u - 0.5, v - 0.5) * 1.8)
                bytes.append(UInt8(clamping: Int((baseCoverage * radial * 255.0).rounded())))
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
        let context = StructuredGeometryLabelContext(labelSources: frame.labelSources)
        var classes = [
            SegmentationClass(id: 0, name: "background", source: "renderer_preview")
        ]
        var nextID = 1
        for semanticClass in context.semanticClasses {
            classes.append(SegmentationClass(id: nextID, name: semanticClass.name, source: semanticClass.sourceDescription))
            nextID += 1
        }
        if let target = frame.navigationTarget {
            classes.append(SegmentationClass(id: nextID, name: "navigation_target", source: target.label))
        }
        return SegmentationApproximation(
            frameIndex: frame.index,
            classes: classes,
            labelSourceSummary: context.summary,
            notes: context.notes
        )
    }

    private func makeObstacleApproximation(frame: DatasetFrame, scene: GaussianSplatScene) -> ObstacleApproximation {
        let depth = makeDepthApproximation(frame: frame, scene: scene)
        let context = StructuredGeometryLabelContext(labelSources: frame.labelSources)
        return ObstacleApproximation(
            frameIndex: frame.index,
            hasObstacleAhead: depth.nearestObstacleMeters < 0.45,
            nearestObstacleMeters: depth.nearestObstacleMeters,
            method: depth.method,
            labelSourceSummary: context.summary,
            structuredGeometryObstaclePriors: context.obstaclePriorDescriptions
        )
    }
}

public struct StructuredGeometryLabelContext: Equatable, Sendable {
    public var summary: GeometryLabelSourceSummary
    public var semanticClasses: [GeometrySemanticClass]
    public var obstaclePriorDescriptions: [String]
    public var notes: [String]

    public init(labelSources: [LabelSource]) {
        var roomPlanURLs: [URL] = []
        var objectCaptureURLs: [URL] = []
        var manualAnnotationURLs: [URL] = []

        for source in labelSources {
            switch source {
            case .roomPlanGeometry(let url):
                roomPlanURLs.append(url)
            case .objectCaptureMesh(let url):
                objectCaptureURLs.append(url)
            case .manualAnnotations(let url):
                manualAnnotationURLs.append(url)
            }
        }

        self.summary = GeometryLabelSourceSummary(
            roomPlanGeometryURLs: roomPlanURLs,
            objectCaptureMeshURLs: objectCaptureURLs,
            manualAnnotationURLs: manualAnnotationURLs
        )

        var classes: [GeometrySemanticClass] = []
        if !roomPlanURLs.isEmpty {
            classes.append(contentsOf: [
                GeometrySemanticClass(name: "floor", sourceDescription: "RoomPlan geometry"),
                GeometrySemanticClass(name: "wall", sourceDescription: "RoomPlan geometry"),
                GeometrySemanticClass(name: "opening", sourceDescription: "RoomPlan geometry"),
                GeometrySemanticClass(name: "room_boundary", sourceDescription: "RoomPlan geometry")
            ])
        }
        for url in objectCaptureURLs {
            let stem = url.deletingPathExtension().lastPathComponent
            let objectName = StructuredGeometryLabelContext.semanticName(from: stem)
            classes.append(GeometrySemanticClass(name: objectName, sourceDescription: "Object Capture mesh"))
        }
        if !manualAnnotationURLs.isEmpty {
            classes.append(GeometrySemanticClass(name: "manual_annotation", sourceDescription: "curated annotation layer"))
        }
        self.semanticClasses = classes

        self.obstaclePriorDescriptions = objectCaptureURLs.map {
            "Object Capture mesh \($0.lastPathComponent) contributes an obstacle prior."
        }

        var notes: [String] = []
        if roomPlanURLs.isEmpty {
            notes.append("No RoomPlan geometry source was provided for floor, wall, opening, or room-boundary semantics.")
        }
        if objectCaptureURLs.isEmpty {
            notes.append("No Object Capture meshes were provided for object obstacle priors.")
        }
        if manualAnnotationURLs.isEmpty {
            notes.append("No manual annotation layer was provided.")
        }
        self.notes = notes
    }

    private static func semanticName(from stem: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).lowercased().replacingOccurrences(of: "-", with: "_")
        return sanitized.isEmpty ? "object_capture_asset" : "object_\(sanitized)"
    }
}

public struct GeometryLabelSourceSummary: Codable, Equatable, Sendable {
    public var roomPlanGeometryURLs: [URL]
    public var objectCaptureMeshURLs: [URL]
    public var manualAnnotationURLs: [URL]

    public init(roomPlanGeometryURLs: [URL], objectCaptureMeshURLs: [URL], manualAnnotationURLs: [URL]) {
        self.roomPlanGeometryURLs = roomPlanGeometryURLs
        self.objectCaptureMeshURLs = objectCaptureMeshURLs
        self.manualAnnotationURLs = manualAnnotationURLs
    }
}

public struct GeometrySemanticClass: Codable, Equatable, Sendable {
    public var name: String
    public var sourceDescription: String

    public init(name: String, sourceDescription: String) {
        self.name = name
        self.sourceDescription = sourceDescription
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
    public var labelSourceSummary: GeometryLabelSourceSummary
    public var notes: [String]

    public init(
        frameIndex: Int,
        classes: [SegmentationClass],
        labelSourceSummary: GeometryLabelSourceSummary,
        notes: [String]
    ) {
        self.frameIndex = frameIndex
        self.classes = classes
        self.labelSourceSummary = labelSourceSummary
        self.notes = notes
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
    public var labelSourceSummary: GeometryLabelSourceSummary
    public var structuredGeometryObstaclePriors: [String]

    public init(
        frameIndex: Int,
        hasObstacleAhead: Bool,
        nearestObstacleMeters: Double,
        method: String,
        labelSourceSummary: GeometryLabelSourceSummary,
        structuredGeometryObstaclePriors: [String]
    ) {
        self.frameIndex = frameIndex
        self.hasObstacleAhead = hasObstacleAhead
        self.nearestObstacleMeters = nearestObstacleMeters
        self.method = method
        self.labelSourceSummary = labelSourceSummary
        self.structuredGeometryObstaclePriors = structuredGeometryObstaclePriors
    }
}
