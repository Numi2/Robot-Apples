import Foundation

public struct RenderedLiDARScanReport: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var generatedAt: Date
    public var specification: RenderedLiDARSpecification
    public var metrics: RenderedLiDARMetrics
    public var rays: [RenderedLiDARRay]
    public var warnings: [String]

    public init(
        frameIndex: Int,
        generatedAt: Date = Date(),
        specification: RenderedLiDARSpecification,
        metrics: RenderedLiDARMetrics,
        rays: [RenderedLiDARRay],
        warnings: [String] = []
    ) {
        self.frameIndex = frameIndex
        self.generatedAt = generatedAt
        self.specification = specification
        self.metrics = metrics
        self.rays = rays
        self.warnings = warnings
    }
}

public struct RenderedLiDARSpecification: Codable, Equatable, Sendable {
    public var horizontalSamples: Int
    public var verticalSamples: Int
    public var horizontalFOVDegrees: Double
    public var verticalFOVDegrees: Double
    public var nearRangeMeters: Double
    public var farRangeMeters: Double
    public var sourceDepthProduct: URL?
    public var sourceVisibilityProduct: URL?

    public init(
        horizontalSamples: Int = 64,
        verticalSamples: Int = 16,
        horizontalFOVDegrees: Double = 90,
        verticalFOVDegrees: Double = 30,
        nearRangeMeters: Double = 0.15,
        farRangeMeters: Double = 20,
        sourceDepthProduct: URL? = nil,
        sourceVisibilityProduct: URL? = nil
    ) {
        self.horizontalSamples = horizontalSamples
        self.verticalSamples = verticalSamples
        self.horizontalFOVDegrees = horizontalFOVDegrees
        self.verticalFOVDegrees = verticalFOVDegrees
        self.nearRangeMeters = nearRangeMeters
        self.farRangeMeters = farRangeMeters
        self.sourceDepthProduct = sourceDepthProduct
        self.sourceVisibilityProduct = sourceVisibilityProduct
    }
}

public struct RenderedLiDARMetrics: Codable, Equatable, Sendable {
    public var rayCount: Int
    public var validRayCount: Int
    public var dropoutRate: Double
    public var meanRangeMeters: Double?
    public var meanIntensity: Double?
    public var lowSupportRate: Double

    public init(
        rayCount: Int,
        validRayCount: Int,
        dropoutRate: Double,
        meanRangeMeters: Double? = nil,
        meanIntensity: Double? = nil,
        lowSupportRate: Double
    ) {
        self.rayCount = rayCount
        self.validRayCount = validRayCount
        self.dropoutRate = dropoutRate
        self.meanRangeMeters = meanRangeMeters
        self.meanIntensity = meanIntensity
        self.lowSupportRate = lowSupportRate
    }
}

public struct RenderedLiDARRay: Codable, Equatable, Sendable {
    public var index: Int
    public var row: Int
    public var column: Int
    public var imageX: Int
    public var imageY: Int
    public var azimuthDegrees: Double
    public var elevationDegrees: Double
    public var rangeMeters: Double?
    public var intensity: Double
    public var visibilitySupport: Double
    public var droppedOut: Bool
    public var dropoutReason: String?

    public init(
        index: Int,
        row: Int,
        column: Int,
        imageX: Int,
        imageY: Int,
        azimuthDegrees: Double,
        elevationDegrees: Double,
        rangeMeters: Double?,
        intensity: Double,
        visibilitySupport: Double,
        droppedOut: Bool,
        dropoutReason: String? = nil
    ) {
        self.index = index
        self.row = row
        self.column = column
        self.imageX = imageX
        self.imageY = imageY
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
        self.rangeMeters = rangeMeters
        self.intensity = intensity
        self.visibilitySupport = visibilitySupport
        self.droppedOut = droppedOut
        self.dropoutReason = dropoutReason
    }
}

public struct RenderedLiDARSimulator: Sendable {
    public var specification: RenderedLiDARSpecification

    public init(specification: RenderedLiDARSpecification = RenderedLiDARSpecification()) {
        self.specification = specification
    }

    public func writeReports(for manifest: DatasetManifest, to outputDirectory: URL) throws -> [RenderedLiDARScanReport] {
        let reports = manifest.frames.map { makeReport(for: $0, generatedAt: manifest.generatedAt) }
        for report in reports {
            let url = outputDirectory
                .appendingPathComponent(RenderProduct.lidarScan.rawValue, isDirectory: true)
                .appendingPathComponent(String(format: "frame_%06d.json", report.frameIndex))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: url)
        }
        return reports
    }

    public func makeReport(for frame: DatasetFrame, generatedAt: Date = Date()) -> RenderedLiDARScanReport {
        var warnings: [String] = []
        let depthURL = frame.productURL(for: .depth)
        let visibilityURL = frame.productURL(for: .visibility)
        let depth = depthURL.flatMap { try? PNMImage.read(url: $0, expectedMagic: "P5") }
        let visibility = visibilityURL.flatMap { try? PNMImage.read(url: $0, expectedMagic: "P5") }

        if depthURL != nil, depth == nil {
            warnings.append("Depth product could not be parsed; all LiDAR rays are marked as dropped out.")
        }
        if visibilityURL != nil, visibility == nil {
            warnings.append("Visibility product could not be parsed; LiDAR support uses neutral visibility.")
        }
        if depthURL == nil {
            warnings.append("Depth product is missing; LiDAR ranges cannot be synthesized.")
        }

        var spec = specification
        spec.sourceDepthProduct = depthURL
        spec.sourceVisibilityProduct = visibilityURL

        let depthValues = depth?.normalizedGrayValues() ?? []
        let visibilityValues = visibility?.normalizedGrayValues() ?? []
        let rays = makeRays(frameIndex: frame.index, depth: depth, depthValues: depthValues, visibility: visibility, visibilityValues: visibilityValues)
        let valid = rays.filter { !$0.droppedOut && $0.rangeMeters != nil }
        let lowSupportCount = rays.filter { $0.visibilitySupport < 0.18 }.count
        let metrics = RenderedLiDARMetrics(
            rayCount: rays.count,
            validRayCount: valid.count,
            dropoutRate: rays.isEmpty ? 0 : Double(rays.count - valid.count) / Double(rays.count),
            meanRangeMeters: mean(valid.compactMap(\.rangeMeters)),
            meanIntensity: mean(valid.map(\.intensity)),
            lowSupportRate: rays.isEmpty ? 0 : Double(lowSupportCount) / Double(rays.count)
        )

        return RenderedLiDARScanReport(
            frameIndex: frame.index,
            generatedAt: generatedAt,
            specification: spec,
            metrics: metrics,
            rays: rays,
            warnings: warnings
        )
    }

    private func makeRays(
        frameIndex: Int,
        depth: PNMImage?,
        depthValues: [Double],
        visibility: PNMImage?,
        visibilityValues: [Double]
    ) -> [RenderedLiDARRay] {
        let horizontalSamples = max(1, specification.horizontalSamples)
        let verticalSamples = max(1, specification.verticalSamples)
        let horizontalLast = max(1, horizontalSamples - 1)
        let verticalLast = max(1, verticalSamples - 1)
        var rays: [RenderedLiDARRay] = []
        rays.reserveCapacity(horizontalSamples * verticalSamples)

        for row in 0..<verticalSamples {
            for column in 0..<horizontalSamples {
                let index = row * horizontalSamples + column
                let u = Double(column) / Double(horizontalLast)
                let v = Double(row) / Double(verticalLast)
                let azimuth = (u - 0.5) * specification.horizontalFOVDegrees
                let elevation = (0.5 - v) * specification.verticalFOVDegrees
                let x = pixelCoordinate(u, count: depth?.width ?? visibility?.width ?? 1)
                let y = pixelCoordinate(v, count: depth?.height ?? visibility?.height ?? 1)
                let support = sampledValue(image: visibility, values: visibilityValues, x: x, y: y) ?? 0.5

                guard let depthValue = sampledValue(image: depth, values: depthValues, x: x, y: y), depthValue > 0.005 else {
                    rays.append(RenderedLiDARRay(
                        index: index,
                        row: row,
                        column: column,
                        imageX: x,
                        imageY: y,
                        azimuthDegrees: azimuth,
                        elevationDegrees: elevation,
                        rangeMeters: nil,
                        intensity: 0,
                        visibilitySupport: support,
                        droppedOut: true,
                        dropoutReason: "missing-depth"
                    ))
                    continue
                }

                let range = rangeMeters(fromDepthVisualization: depthValue)
                let dropoutProbability = dropoutProbability(rangeMeters: range, visibilitySupport: support)
                let deterministicSample = deterministicUnitSample(frameIndex: frameIndex, rayIndex: index)
                let dropped = support < 0.05 || deterministicSample < dropoutProbability
                let reason: String?
                if support < 0.05 {
                    reason = "low-visibility-support"
                } else if dropped {
                    reason = "range-visibility-dropout"
                } else {
                    reason = nil
                }

                rays.append(RenderedLiDARRay(
                    index: index,
                    row: row,
                    column: column,
                    imageX: x,
                    imageY: y,
                    azimuthDegrees: azimuth,
                    elevationDegrees: elevation,
                    rangeMeters: dropped ? nil : range,
                    intensity: dropped ? 0 : intensity(rangeMeters: range, visibilitySupport: support),
                    visibilitySupport: support,
                    droppedOut: dropped,
                    dropoutReason: reason
                ))
            }
        }
        return rays
    }

    private func pixelCoordinate(_ normalized: Double, count: Int) -> Int {
        min(max(Int((normalized * Double(max(1, count - 1))).rounded()), 0), max(0, count - 1))
    }

    private func sampledValue(image: PNMImage?, values: [Double], x: Int, y: Int) -> Double? {
        guard let image, !values.isEmpty else { return nil }
        let clampedX = min(max(x, 0), max(0, image.width - 1))
        let clampedY = min(max(y, 0), max(0, image.height - 1))
        let index = clampedY * image.width + clampedX
        guard index < values.count else { return nil }
        return values[index]
    }

    private func rangeMeters(fromDepthVisualization value: Double) -> Double {
        let near = max(0.01, specification.nearRangeMeters)
        let far = max(near + 0.01, specification.farRangeMeters)
        let normalizedFar = 1 - min(max(value, 0), 1)
        return near + normalizedFar * (far - near)
    }

    private func dropoutProbability(rangeMeters: Double, visibilitySupport: Double) -> Double {
        let near = max(0.01, specification.nearRangeMeters)
        let far = max(near + 0.01, specification.farRangeMeters)
        let rangeFactor = min(max((rangeMeters - near) / (far - near), 0), 1)
        let visibilityFactor = 1 - min(max(visibilitySupport, 0), 1)
        return min(0.92, 0.03 + rangeFactor * 0.22 + visibilityFactor * 0.55)
    }

    private func intensity(rangeMeters: Double, visibilitySupport: Double) -> Double {
        let rangeFalloff = 1 / (1 + max(0, rangeMeters) * max(0, rangeMeters) * 0.08)
        return min(max(0.08 + visibilitySupport * 0.82 * rangeFalloff, 0), 1)
    }

    private func deterministicUnitSample(frameIndex: Int, rayIndex: Int) -> Double {
        var value = UInt64(bitPattern: Int64(frameIndex &* 1_000_003 &+ rayIndex &* 97_531))
        value ^= value >> 33
        value &*= 0xff51afd7ed558ccd
        value ^= value >> 33
        value &*= 0xc4ceb9fe1a85ec53
        value ^= value >> 33
        return Double(value % 10_000) / 10_000.0
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
