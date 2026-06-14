import Foundation
import simd

public struct RenderedModelSample: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var timestamp: TimeInterval
    public var rgbURL: URL?
    public var depthURL: URL?
    public var visibilityURL: URL?
    public var lidarScanURL: URL?
    public var segmentationURL: URL?
    public var obstacleMaskURL: URL?
    public var pose: Pose3D
    public var intrinsics: CameraIntrinsics
    public var rgbCHW: [Float]
    public var depthCHW: [Float]
    public var visibilityCHW: [Float]
    public var lidarFeatureVector: [Float]
    public var structuredGeometryFeatureVector: [Float]
    public var poseVector: [Float]
    public var intrinsicsVector: [Float]
    public var warnings: [String]

    public init(
        frameIndex: Int,
        timestamp: TimeInterval,
        rgbURL: URL?,
        depthURL: URL?,
        visibilityURL: URL?,
        lidarScanURL: URL?,
        segmentationURL: URL?,
        obstacleMaskURL: URL?,
        pose: Pose3D,
        intrinsics: CameraIntrinsics,
        rgbCHW: [Float],
        depthCHW: [Float],
        visibilityCHW: [Float],
        lidarFeatureVector: [Float],
        structuredGeometryFeatureVector: [Float],
        poseVector: [Float],
        intrinsicsVector: [Float],
        warnings: [String] = []
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.rgbURL = rgbURL
        self.depthURL = depthURL
        self.visibilityURL = visibilityURL
        self.lidarScanURL = lidarScanURL
        self.segmentationURL = segmentationURL
        self.obstacleMaskURL = obstacleMaskURL
        self.pose = pose
        self.intrinsics = intrinsics
        self.rgbCHW = rgbCHW
        self.depthCHW = depthCHW
        self.visibilityCHW = visibilityCHW
        self.lidarFeatureVector = lidarFeatureVector
        self.structuredGeometryFeatureVector = structuredGeometryFeatureVector
        self.poseVector = poseVector
        self.intrinsicsVector = intrinsicsVector
        self.warnings = warnings
    }
}

public struct RenderedDatasetLoader: Sendable {
    public init() {}

    public func loadSamples(from manifest: DatasetManifest) -> [RenderedModelSample] {
        manifest.frames.map { loadSample(frame: $0, intrinsics: manifest.cameraRig.intrinsics) }
    }

    public func loadSample(frame: DatasetFrame, intrinsics: CameraIntrinsics) -> RenderedModelSample {
        var warnings: [String] = []
        let rgbURL = frame.productURL(for: .rgb)
        let depthURL = frame.productURL(for: .depth)
        let visibilityURL = frame.productURL(for: .visibility)
        let lidarScanURL = frame.productURL(for: .lidarScan)
        let segmentationURL = frame.productURL(for: .segmentation)
        let obstacleMaskURL = frame.productURL(for: .obstacleMask)
        let rgb = rgbURL.flatMap { try? readPPMCHW(url: $0, expectedWidth: intrinsics.width, expectedHeight: intrinsics.height) }
        let depth = depthURL.flatMap { try? readDepthCHW(url: $0, expectedWidth: intrinsics.width, expectedHeight: intrinsics.height) }
        let visibility = visibilityURL.flatMap { try? readPGMCHW(url: $0, expectedWidth: intrinsics.width, expectedHeight: intrinsics.height) }
        let loadedLiDARFeatures = lidarScanURL.flatMap { try? readLiDARFeatureVector(url: $0) }
        let lidarFeatures = loadedLiDARFeatures ?? Array(repeating: Float(0), count: 30)
        let loadedStructuredGeometryFeatures = readStructuredGeometryFeatureVector(segmentationURL: segmentationURL, obstacleMaskURL: obstacleMaskURL)
        let structuredGeometryFeatures = loadedStructuredGeometryFeatures ?? Array(repeating: Float(0), count: 16)

        if rgbURL == nil {
            warnings.append("Frame has no RGB product URL.")
        } else if rgb == nil {
            warnings.append("Unable to load RGB tensor from \(rgbURL?.path ?? "unknown").")
        }
        if depthURL == nil {
            warnings.append("Frame has no depth product URL.")
        } else if depth == nil {
            warnings.append("Unable to load depth tensor from \(depthURL?.path ?? "unknown").")
        }
        if visibilityURL == nil {
            warnings.append("Frame has no visibility product URL.")
        } else if visibility == nil {
            warnings.append("Unable to load visibility tensor from \(visibilityURL?.path ?? "unknown").")
        }
        if lidarScanURL == nil {
            warnings.append("Frame has no LiDAR scan product URL.")
        } else if loadedLiDARFeatures == nil {
            warnings.append("Unable to load LiDAR scan summary from \(lidarScanURL?.path ?? "unknown").")
        }
        if segmentationURL == nil && obstacleMaskURL == nil {
            warnings.append("Frame has no structured geometry segmentation or obstacle product URL.")
        } else if loadedStructuredGeometryFeatures == nil {
            warnings.append("Unable to load structured geometry products from \(obstacleMaskURL?.path ?? segmentationURL?.path ?? "unknown").")
        }

        return RenderedModelSample(
            frameIndex: frame.index,
            timestamp: frame.timestamp,
            rgbURL: rgbURL,
            depthURL: depthURL,
            visibilityURL: visibilityURL,
            lidarScanURL: lidarScanURL,
            segmentationURL: segmentationURL,
            obstacleMaskURL: obstacleMaskURL,
            pose: frame.cameraPose,
            intrinsics: intrinsics,
            rgbCHW: rgb ?? Array(repeating: 0, count: max(1, intrinsics.width * intrinsics.height * 3)),
            depthCHW: depth ?? Array(repeating: 0, count: max(1, intrinsics.width * intrinsics.height)),
            visibilityCHW: visibility ?? Array(repeating: 0, count: max(1, intrinsics.width * intrinsics.height)),
            lidarFeatureVector: lidarFeatures,
            structuredGeometryFeatureVector: structuredGeometryFeatures,
            poseVector: poseVector(frame.cameraPose),
            intrinsicsVector: intrinsicsVector(intrinsics),
            warnings: warnings
        )
    }

    private func poseVector(_ pose: Pose3D) -> [Float] {
        [
            Float(pose.position.x),
            Float(pose.position.y),
            Float(pose.position.z),
            Float(pose.orientation.vector.x),
            Float(pose.orientation.vector.y),
            Float(pose.orientation.vector.z),
            Float(pose.orientation.vector.w)
        ]
    }

    private func intrinsicsVector(_ intrinsics: CameraIntrinsics) -> [Float] {
        [
            Float(intrinsics.focalLengthPixels.x),
            Float(intrinsics.focalLengthPixels.y),
            Float(intrinsics.principalPointPixels.x),
            Float(intrinsics.principalPointPixels.y)
        ]
    }

    private func readPPMCHW(url: URL, expectedWidth: Int, expectedHeight: Int) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let parsed = try parsePNM(data: data, expectedMagic: "P6", expectedWidth: expectedWidth, expectedHeight: expectedHeight)
        let pixelCount = parsed.width * parsed.height
        guard parsed.payload.count >= pixelCount * 3 else {
            throw RenderedDatasetLoaderError.truncatedImage(url)
        }
        var output = Array(repeating: Float(0), count: pixelCount * 3)
        for pixel in 0..<pixelCount {
            output[pixel] = Float(parsed.payload[pixel * 3]) / 255
            output[pixelCount + pixel] = Float(parsed.payload[pixel * 3 + 1]) / 255
            output[pixelCount * 2 + pixel] = Float(parsed.payload[pixel * 3 + 2]) / 255
        }
        return output
    }

    private func readDepthCHW(url: URL, expectedWidth: Int, expectedHeight: Int) throws -> [Float] {
        if let metricDepth = MetricDepthProductIO.readIfPresent(forVisualizationURL: url),
           metricDepth.metadata.width == expectedWidth,
           metricDepth.metadata.height == expectedHeight {
            let farMeters: Float = 20
            return metricDepth.valuesMeters.map { value in
                guard value.isFinite, value > 0 else { return 0 }
                return min(max(value / farMeters, 0), 1)
            }
        }
        return try readPGMCHW(url: url, expectedWidth: expectedWidth, expectedHeight: expectedHeight)
    }

    private func readPGMCHW(url: URL, expectedWidth: Int, expectedHeight: Int) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let parsed = try parsePNM(data: data, expectedMagic: "P5", expectedWidth: expectedWidth, expectedHeight: expectedHeight)
        let pixelCount = parsed.width * parsed.height
        guard parsed.payload.count >= pixelCount else {
            throw RenderedDatasetLoaderError.truncatedImage(url)
        }
        let scale = Float(max(parsed.maxValue, 1))
        return (0..<pixelCount).map { Float(parsed.payload[$0]) / scale }
    }

    private func readLiDARFeatureVector(url: URL) throws -> [Float] {
        let report = try JSONDecoder.robotVisionLabDecoder.decode(RenderedLiDARScanReport.self, from: Data(contentsOf: url))
        let rayCount = max(report.metrics.rayCount, 1)
        let validFraction = Float(report.metrics.validRayCount) / Float(rayCount)
        let rayCountScale = min(Float(report.metrics.rayCount) / 1024, 4)
        let meanRangeScale = Float(max(report.specification.farRangeMeters, 0.01))
        let meanRange = Float(report.metrics.meanRangeMeters ?? 0) / meanRangeScale
        let validRays = report.rays.filter { !$0.droppedOut && $0.rangeMeters != nil }
        let worldPoints = validRays.compactMap(\.worldPointMeters)
        let cameraPoints = validRays.compactMap(\.cameraPointMeters)
        let ranges = validRays.compactMap(\.rangeMeters)
        let worldStats = pointCloudStats(worldPoints)
        let cameraStats = pointCloudStats(cameraPoints)
        let bandOccupancy = cameraOccupancyBands(cameraPoints)
        let rangeStats = scalarStats(ranges, scale: Double(max(report.specification.farRangeMeters, 0.01)))
        return [
            validFraction,
            Float(report.metrics.dropoutRate),
            min(max(meanRange, 0), 1),
            Float(report.metrics.meanIntensity ?? 0),
            Float(report.metrics.lowSupportRate),
            rayCountScale
        ] + worldStats + cameraStats + bandOccupancy + rangeStats
    }

    private func readStructuredGeometryFeatureVector(segmentationURL: URL?, obstacleMaskURL: URL?) -> [Float]? {
        guard let reportURL = obstacleMaskURL ?? segmentationURL,
              let data = try? Data(contentsOf: reportURL),
              let report = try? JSONDecoder.robotVisionLabDecoder.decode(StructuredGeometryFrameProductReport.self, from: data) else {
            return nil
        }

        let segmentationConfidences = report.segmentationHints.map(\.confidence)
        let obstaclePriors = report.obstacleHints.map(\.obstaclePrior)
        let obstacleDistances = report.obstacleHints.map(\.distanceMeters)
        let regionAreas = report.segmentationHints.map { hint in
            let region = hint.approximateImageRegion
            return max(0, region.maxX - region.minX) * max(0, region.maxY - region.minY)
        }
        let semanticClasses = Set(report.segmentationHints.map { $0.semanticClass.lowercased() })
        let obstacleLabels = Set(report.obstacleHints.map { $0.label.lowercased() })
        let hasFloor = semanticClasses.contains { $0.contains("floor") } || obstacleLabels.contains { $0.contains("floor") }
        let hasWall = semanticClasses.contains { $0.contains("wall") } || obstacleLabels.contains { $0.contains("wall") }
        let hasObject = semanticClasses.contains { $0.contains("object") } || obstacleLabels.contains { $0.contains("object") }
        let nearestDistance = obstacleDistances.min().map { min(max($0 / 12.0, 0), 1) } ?? 0
        let totalCoverage = min(regionAreas.reduce(0, +), 1)

        return [
            min(Float(report.visibleLayerIDs.count) / 16, 4),
            min(Float(report.segmentationHints.count) / 16, 4),
            min(Float(report.obstacleHints.count) / 16, 4),
            Float(min(max(report.obstacleProbability, 0), 1)),
            mean(segmentationConfidences),
            maxValue(segmentationConfidences),
            mean(obstaclePriors),
            maxValue(obstaclePriors),
            Float(nearestDistance),
            hasFloor ? 1 : 0,
            hasWall ? 1 : 0,
            hasObject ? 1 : 0,
            mean(regionAreas),
            maxValue(regionAreas),
            Float(totalCoverage),
            min(Float(report.warnings.count) / 8, 1)
        ]
    }

    private func mean(_ values: [Double]) -> Float {
        guard !values.isEmpty else { return 0 }
        return Float(values.reduce(0, +) / Double(values.count))
    }

    private func maxValue(_ values: [Double]) -> Float {
        Float(values.max() ?? 0)
    }

    private func pointCloudStats(_ points: [SIMD3<Double>]) -> [Float] {
        guard !points.isEmpty else {
            return Array(repeating: 0, count: 6)
        }
        let count = Double(points.count)
        let centroid = points.reduce(SIMD3<Double>(repeating: 0), +) / count
        let variance = points.reduce(SIMD3<Double>(repeating: 0)) { partial, point in
            let delta = point - centroid
            return partial + delta * delta
        } / count
        return [
            Float(centroid.x),
            Float(centroid.y),
            Float(centroid.z),
            Float(sqrt(max(variance.x, 0))),
            Float(sqrt(max(variance.y, 0))),
            Float(sqrt(max(variance.z, 0)))
        ]
    }

    private func cameraOccupancyBands(_ points: [SIMD3<Double>]) -> [Float] {
        guard !points.isEmpty else {
            return Array(repeating: 0, count: 6)
        }
        let count = Float(points.count)
        let left = Float(points.filter { $0.x < -0.35 }.count) / count
        let center = Float(points.filter { abs($0.x) <= 0.35 }.count) / count
        let right = Float(points.filter { $0.x > 0.35 }.count) / count
        let near = Float(points.filter { -$0.z < 1.0 }.count) / count
        let mid = Float(points.filter { -$0.z >= 1.0 && -$0.z < 3.0 }.count) / count
        let far = Float(points.filter { -$0.z >= 3.0 }.count) / count
        return [left, center, right, near, mid, far]
    }

    private func scalarStats(_ values: [Double], scale: Double) -> [Float] {
        guard !values.isEmpty else {
            return Array(repeating: 0, count: 6)
        }
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let minValue = sorted.first ?? 0
        let maxValue = sorted.last ?? 0
        let p10 = sorted[Int((Double(sorted.count - 1) * 0.10).rounded())]
        let p90 = sorted[Int((Double(sorted.count - 1) * 0.90).rounded())]
        let denominator = max(scale, 0.01)
        return [minValue, maxValue, mean, sqrt(max(variance, 0)), p10, p90].map {
            Float(min(max($0 / denominator, 0), 1))
        }
    }

    private func parsePNM(
        data: Data,
        expectedMagic: String,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws -> (width: Int, height: Int, maxValue: Int, payload: Data) {
        var tokens: [String] = []
        var index = data.startIndex
        while tokens.count < 4, index < data.endIndex {
            while index < data.endIndex, data[index].isASCIISpace {
                index += 1
            }
            if index < data.endIndex, data[index] == UInt8(ascii: "#") {
                while index < data.endIndex, data[index] != UInt8(ascii: "\n") {
                    index += 1
                }
                continue
            }
            let start = index
            while index < data.endIndex, !data[index].isASCIISpace {
                index += 1
            }
            guard start < index, let token = String(data: data[start..<index], encoding: .ascii) else {
                throw RenderedDatasetLoaderError.invalidHeader
            }
            tokens.append(token)
        }
        while index < data.endIndex, data[index].isASCIISpace {
            index += 1
        }
        guard tokens.count == 4,
              tokens[0] == expectedMagic,
              let width = Int(tokens[1]),
              let height = Int(tokens[2]),
              let maxValue = Int(tokens[3]),
              width == expectedWidth,
              height == expectedHeight else {
            throw RenderedDatasetLoaderError.invalidHeader
        }
        return (width, height, maxValue, data[index..<data.endIndex])
    }
}

public enum RenderedDatasetLoaderError: Error, LocalizedError {
    case invalidHeader
    case truncatedImage(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidHeader:
            "Rendered dataset image has an invalid PPM/PGM header."
        case .truncatedImage(let url):
            "Rendered dataset image is truncated: \(url.path)."
        }
    }
}

private extension UInt8 {
    var isASCIISpace: Bool {
        self == UInt8(ascii: " ")
            || self == UInt8(ascii: "\n")
            || self == UInt8(ascii: "\r")
            || self == UInt8(ascii: "\t")
    }
}
