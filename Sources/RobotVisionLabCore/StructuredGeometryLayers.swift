import Foundation
import simd

public enum StructuredGeometryLayerKind: String, Codable, CaseIterable, Sendable {
    case floor
    case wall
    case object
    case unknown
}

public struct StructuredGeometryLayer: Codable, Equatable, Sendable {
    public var id: String
    public var kind: StructuredGeometryLayerKind
    public var label: String
    public var sourceURL: URL
    public var source: FailureEvidenceSource
    public var bounds: AxisAlignedBounds
    public var semanticClass: String
    public var confidence: Double
    public var obstaclePrior: Double

    public init(
        id: String,
        kind: StructuredGeometryLayerKind,
        label: String,
        sourceURL: URL,
        source: FailureEvidenceSource,
        bounds: AxisAlignedBounds,
        semanticClass: String,
        confidence: Double,
        obstaclePrior: Double
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.sourceURL = sourceURL
        self.source = source
        self.bounds = bounds
        self.semanticClass = semanticClass
        self.confidence = confidence
        self.obstaclePrior = obstaclePrior
    }
}

public struct StructuredGeometryLayerCatalog: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var sceneBounds: AxisAlignedBounds
    public var layers: [StructuredGeometryLayer]
    public var warnings: [String]

    public init(
        generatedAt: Date = Date(),
        sceneBounds: AxisAlignedBounds,
        layers: [StructuredGeometryLayer],
        warnings: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.sceneBounds = sceneBounds
        self.layers = layers
        self.warnings = warnings
    }
}

public struct StructuredGeometryFrameProductReport: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var timestamp: TimeInterval
    public var cameraPose: Pose3D
    public var visibleLayerIDs: [String]
    public var segmentationHints: [StructuredSegmentationHint]
    public var obstacleHints: [StructuredObstacleHint]
    public var obstacleProbability: Double
    public var warnings: [String]

    public init(
        frameIndex: Int,
        timestamp: TimeInterval,
        cameraPose: Pose3D,
        visibleLayerIDs: [String],
        segmentationHints: [StructuredSegmentationHint],
        obstacleHints: [StructuredObstacleHint],
        obstacleProbability: Double,
        warnings: [String] = []
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.cameraPose = cameraPose
        self.visibleLayerIDs = visibleLayerIDs
        self.segmentationHints = segmentationHints
        self.obstacleHints = obstacleHints
        self.obstacleProbability = obstacleProbability
        self.warnings = warnings
    }
}

public struct StructuredSegmentationHint: Codable, Equatable, Sendable {
    public var layerID: String
    public var semanticClass: String
    public var confidence: Double
    public var approximateImageRegion: NormalizedImageRegion

    public init(layerID: String, semanticClass: String, confidence: Double, approximateImageRegion: NormalizedImageRegion) {
        self.layerID = layerID
        self.semanticClass = semanticClass
        self.confidence = confidence
        self.approximateImageRegion = approximateImageRegion
    }
}

public struct StructuredObstacleHint: Codable, Equatable, Sendable {
    public var layerID: String
    public var label: String
    public var distanceMeters: Double
    public var obstaclePrior: Double
    public var confidence: Double

    public init(layerID: String, label: String, distanceMeters: Double, obstaclePrior: Double, confidence: Double) {
        self.layerID = layerID
        self.label = label
        self.distanceMeters = distanceMeters
        self.obstaclePrior = obstaclePrior
        self.confidence = confidence
    }
}

public struct NormalizedImageRegion: Codable, Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = min(max(minX, 0), 1)
        self.minY = min(max(minY, 0), 1)
        self.maxX = min(max(maxX, self.minX), 1)
        self.maxY = min(max(maxY, self.minY), 1)
    }
}

public struct StructuredGeometryProductWriter: Sendable {
    public init() {}

    public func writeProducts(for manifest: DatasetManifest, to outputDirectory: URL) throws -> [StructuredGeometryFrameProductReport] {
        let catalog = makeCatalog(for: manifest)
        let catalogURL = outputDirectory.appendingPathComponent("structured_geometry_layers.json")
        try JSONEncoder.robotVisionLabEncoder.encode(catalog).write(to: catalogURL)

        let reports = manifest.frames.map { makeFrameReport(frame: $0, catalog: catalog, cameraRig: manifest.cameraRig) }
        for report in reports {
            try write(report, product: .segmentation, outputDirectory: outputDirectory)
            try write(report, product: .obstacleMask, outputDirectory: outputDirectory)
        }
        return reports
    }

    public func makeCatalog(for manifest: DatasetManifest) -> StructuredGeometryLayerCatalog {
        var layers: [StructuredGeometryLayer] = []
        var warnings: [String] = []
        var ordinal = 0

        for source in manifest.frames.flatMap(\.labelSources).deduplicatedByGeometryKey() {
            switch source {
            case .roomPlanGeometry(let url):
                layers.append(contentsOf: roomPlanLayers(url: url, sceneBounds: manifest.scene.bounds, startingOrdinal: ordinal))
                ordinal = layers.count
            case .objectCaptureMesh(let url):
                let layer = objectLayer(url: url, sceneBounds: manifest.scene.bounds, ordinal: ordinal)
                layers.append(layer)
                ordinal += 1
            case .manualAnnotations:
                continue
            }
        }

        if layers.isEmpty {
            warnings.append("No RoomPlan or Object Capture geometry layers are linked; segmentation and obstacle priors use no structured geometry.")
        }
        return StructuredGeometryLayerCatalog(
            generatedAt: manifest.generatedAt,
            sceneBounds: manifest.scene.bounds,
            layers: layers,
            warnings: warnings
        )
    }

    private func makeFrameReport(
        frame: DatasetFrame,
        catalog: StructuredGeometryLayerCatalog,
        cameraRig: RobotCameraRig
    ) -> StructuredGeometryFrameProductReport {
        let visible = catalog.layers.compactMap { layer -> (StructuredGeometryLayer, Double, NormalizedImageRegion)? in
            guard let projection = project(layer: layer, from: frame.cameraPose, cameraRig: cameraRig) else {
                return nil
            }
            return (layer, projection.distance, projection.region)
        }
        let segmentationHints = visible.map { layer, distance, region in
            StructuredSegmentationHint(
                layerID: layer.id,
                semanticClass: layer.semanticClass,
                confidence: layerConfidence(layer, distance: distance),
                approximateImageRegion: region
            )
        }
        let obstacleHints = visible
            .filter { $0.0.obstaclePrior > 0.05 }
            .map { layer, distance, _ in
                StructuredObstacleHint(
                    layerID: layer.id,
                    label: layer.label,
                    distanceMeters: distance,
                    obstaclePrior: layer.obstaclePrior,
                    confidence: layerConfidence(layer, distance: distance)
                )
            }
        let obstacleProbability = obstacleHints.reduce(0.0) { partial, hint in
            max(partial, hint.obstaclePrior * hint.confidence)
        }
        return StructuredGeometryFrameProductReport(
            frameIndex: frame.index,
            timestamp: frame.timestamp,
            cameraPose: frame.cameraPose,
            visibleLayerIDs: visible.map(\.0.id),
            segmentationHints: segmentationHints,
            obstacleHints: obstacleHints,
            obstacleProbability: min(max(obstacleProbability, 0), 1),
            warnings: catalog.warnings
        )
    }

    private func write(_ report: StructuredGeometryFrameProductReport, product: RenderProduct, outputDirectory: URL) throws {
        let url = outputDirectory
            .appendingPathComponent(product.rawValue, isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.json", report.frameIndex))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: url)
    }

    private func roomPlanLayers(url: URL, sceneBounds: AxisAlignedBounds, startingOrdinal: Int) -> [StructuredGeometryLayer] {
        let min = sceneBounds.minimum
        let max = sceneBounds.maximum
        let floor = StructuredGeometryLayer(
            id: "roomplan_floor_\(startingOrdinal)",
            kind: .floor,
            label: "RoomPlan floor",
            sourceURL: url,
            source: .geometryPrior,
            bounds: AxisAlignedBounds(
                minimum: SIMD3<Double>(min.x, min.y - 0.02, min.z),
                maximum: SIMD3<Double>(max.x, min.y + 0.02, max.z)
            ),
            semanticClass: "floor",
            confidence: 0.82,
            obstaclePrior: 0.02
        )
        let walls = [
            wall(id: "roomplan_wall_min_x_\(startingOrdinal)", label: "RoomPlan wall", url: url, min: SIMD3<Double>(min.x, min.y, min.z), max: SIMD3<Double>(min.x + 0.06, max.y, max.z)),
            wall(id: "roomplan_wall_max_x_\(startingOrdinal)", label: "RoomPlan wall", url: url, min: SIMD3<Double>(max.x - 0.06, min.y, min.z), max: SIMD3<Double>(max.x, max.y, max.z)),
            wall(id: "roomplan_wall_min_z_\(startingOrdinal)", label: "RoomPlan wall", url: url, min: SIMD3<Double>(min.x, min.y, min.z), max: SIMD3<Double>(max.x, max.y, min.z + 0.06)),
            wall(id: "roomplan_wall_max_z_\(startingOrdinal)", label: "RoomPlan wall", url: url, min: SIMD3<Double>(min.x, min.y, max.z - 0.06), max: SIMD3<Double>(max.x, max.y, max.z))
        ]
        return [floor] + walls
    }

    private func wall(id: String, label: String, url: URL, min: SIMD3<Double>, max: SIMD3<Double>) -> StructuredGeometryLayer {
        StructuredGeometryLayer(
            id: id,
            kind: .wall,
            label: label,
            sourceURL: url,
            source: .geometryPrior,
            bounds: AxisAlignedBounds(minimum: min, maximum: max),
            semanticClass: "wall",
            confidence: 0.78,
            obstaclePrior: 0.92
        )
    }

    private func objectLayer(url: URL, sceneBounds: AxisAlignedBounds, ordinal: Int) -> StructuredGeometryLayer {
        let label = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let center = deterministicObjectCenter(url: url, bounds: sceneBounds)
        let halfExtent = SIMD3<Double>(0.32, 0.42, 0.32)
        return StructuredGeometryLayer(
            id: "object_capture_\(ordinal)_\(url.deletingPathExtension().lastPathComponent)",
            kind: .object,
            label: label.isEmpty ? "Object Capture asset" : label,
            sourceURL: url,
            source: .geometryPrior,
            bounds: AxisAlignedBounds(minimum: center - halfExtent, maximum: center + halfExtent),
            semanticClass: normalizedSemantic(label),
            confidence: 0.68,
            obstaclePrior: 0.82
        )
    }

    private func deterministicObjectCenter(url: URL, bounds: AxisAlignedBounds) -> SIMD3<Double> {
        let scalars = Array(url.lastPathComponent.utf8)
        let hash = scalars.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let fx = Double(hash & 0xff) / 255.0
        let fz = Double((hash >> 8) & 0xff) / 255.0
        let x = bounds.minimum.x + (bounds.maximum.x - bounds.minimum.x) * (0.2 + fx * 0.6)
        let z = bounds.minimum.z + (bounds.maximum.z - bounds.minimum.z) * (0.2 + fz * 0.6)
        return SIMD3<Double>(x, bounds.minimum.y + 0.42, z)
    }

    private func project(
        layer: StructuredGeometryLayer,
        from pose: Pose3D,
        cameraRig: RobotCameraRig
    ) -> (distance: Double, region: NormalizedImageRegion)? {
        let center = (layer.bounds.minimum + layer.bounds.maximum) * 0.5
        let toLayer = center - pose.position
        let cameraSpace = pose.orientation.value.inverse.act(toLayer)
        guard cameraSpace.z < -0.05 else { return nil }
        let distance = simd_length(toLayer)
        guard distance < 12 else { return nil }

        let horizontalAngle = atan2(cameraSpace.x, -cameraSpace.z)
        let verticalAngle = atan2(cameraSpace.y, -cameraSpace.z)
        let horizontalFOV = cameraRig.intrinsics.horizontalFOVRadians
        let verticalFOV = horizontalFOV * Double(cameraRig.intrinsics.height) / Double(max(cameraRig.intrinsics.width, 1))
        guard abs(horizontalAngle) <= horizontalFOV * 0.65, abs(verticalAngle) <= verticalFOV * 0.8 else {
            return nil
        }

        let u = 0.5 + horizontalAngle / horizontalFOV
        let v = 0.5 - verticalAngle / max(verticalFOV, 0.001)
        let extent = layer.bounds.maximum - layer.bounds.minimum
        let apparentSize = min(0.45, max(0.04, simd_length(extent) / max(distance, 0.1) * 0.25))
        let region = NormalizedImageRegion(
            minX: u - apparentSize,
            minY: v - apparentSize,
            maxX: u + apparentSize,
            maxY: v + apparentSize
        )
        return (distance, region)
    }

    private func layerConfidence(_ layer: StructuredGeometryLayer, distance: Double) -> Double {
        min(0.95, max(0.15, layer.confidence * (1.0 - min(distance, 12) / 18.0)))
    }

    private func normalizedSemantic(_ label: String) -> String {
        let normalized = label
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return normalized.isEmpty ? "object" : String(normalized)
    }
}

private extension CameraIntrinsics {
    var horizontalFOVRadians: Double {
        2.0 * atan(Double(width) / max(2.0 * focalLengthPixels.x, 0.001))
    }
}

private extension Array where Element == LabelSource {
    func deduplicatedByGeometryKey() -> [LabelSource] {
        var seen = Set<String>()
        var output: [LabelSource] = []
        for source in self {
            let key: String
            switch source {
            case .roomPlanGeometry(let url):
                key = "roomplan:\(url.standardizedFileURL.path)"
            case .objectCaptureMesh(let url):
                key = "object:\(url.standardizedFileURL.path)"
            case .manualAnnotations(let url):
                key = "manual:\(url.standardizedFileURL.path)"
            }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(source)
        }
        return output
    }
}
