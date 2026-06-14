import Foundation

public struct RenderedFailureLabelReport: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var generatedAt: Date
    public var labels: [RenderedFailureLabel]
    public var metrics: RenderedFailureMetrics
    public var warnings: [String]

    public init(
        frameIndex: Int,
        generatedAt: Date = Date(),
        labels: [RenderedFailureLabel],
        metrics: RenderedFailureMetrics,
        warnings: [String] = []
    ) {
        self.frameIndex = frameIndex
        self.generatedAt = generatedAt
        self.labels = labels
        self.metrics = metrics
        self.warnings = warnings
    }
}

public struct RenderedFailureLabel: Codable, Equatable, Sendable {
    public var kind: FailureMarkerKind
    public var confidence: Double
    public var note: String

    public init(kind: FailureMarkerKind, confidence: Double, note: String) {
        self.kind = kind
        self.confidence = confidence
        self.note = note
    }
}

public struct RenderedFailureMetrics: Codable, Equatable, Sendable {
    public var usesMetricDepthMeters: Bool
    public var meanDepth: Double?
    public var nearDepthCoverage: Double?
    public var meanVisibility: Double?
    public var lowVisibilityCoverage: Double?
    public var luminanceMean: Double?
    public var luminanceVariance: Double?
    public var edgeEnergy: Double?

    public init(
        usesMetricDepthMeters: Bool = false,
        meanDepth: Double? = nil,
        nearDepthCoverage: Double? = nil,
        meanVisibility: Double? = nil,
        lowVisibilityCoverage: Double? = nil,
        luminanceMean: Double? = nil,
        luminanceVariance: Double? = nil,
        edgeEnergy: Double? = nil
    ) {
        self.usesMetricDepthMeters = usesMetricDepthMeters
        self.meanDepth = meanDepth
        self.nearDepthCoverage = nearDepthCoverage
        self.meanVisibility = meanVisibility
        self.lowVisibilityCoverage = lowVisibilityCoverage
        self.luminanceMean = luminanceMean
        self.luminanceVariance = luminanceVariance
        self.edgeEnergy = edgeEnergy
    }
}

public struct RenderedFailureLabeler: Sendable {
    public init() {}

    public func writeReports(for manifest: DatasetManifest, to outputDirectory: URL) throws -> [RenderedFailureLabelReport] {
        let reports = manifest.frames.map { makeReport(for: $0, generatedAt: manifest.generatedAt) }
        for report in reports {
            let url = outputDirectory
                .appendingPathComponent(RenderProduct.failureLabels.rawValue, isDirectory: true)
                .appendingPathComponent(String(format: "frame_%06d.json", report.frameIndex))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: url)
        }
        return reports
    }

    public func makeReport(for frame: DatasetFrame, generatedAt: Date = Date()) -> RenderedFailureLabelReport {
        var warnings: [String] = []
        let depthURL = frame.productURL(for: .depth)
        let metricDepth = depthURL.flatMap { MetricDepthProductIO.readIfPresent(forVisualizationURL: $0) }
        let depth = depthURL.flatMap { try? PNMImage.read(url: $0, expectedMagic: "P5") }
        let visibility = frame.productURL(for: .visibility).flatMap { try? PNMImage.read(url: $0, expectedMagic: "P5") }
        let rgb = frame.productURL(for: .rgb).flatMap { try? PNMImage.read(url: $0, expectedMagic: "P6") }

        if depthURL != nil, depth == nil, metricDepth == nil {
            warnings.append("Depth product could not be parsed.")
        }
        if frame.productURL(for: .visibility) != nil, visibility == nil {
            warnings.append("Visibility product could not be parsed.")
        }
        if frame.productURL(for: .rgb) != nil, rgb == nil {
            warnings.append("RGB product could not be parsed.")
        }

        let metricDepthValues = metricDepth?.valuesMeters.compactMap { value -> Double? in
            guard value.isFinite, value > 0 else { return nil }
            return Double(value)
        }
        let depthValues = depth?.normalizedGrayValues()
        let visibilityValues = visibility?.normalizedGrayValues()
        let luminanceValues = rgb?.luminanceValues()
        let metrics = RenderedFailureMetrics(
            usesMetricDepthMeters: metricDepthValues != nil,
            meanDepth: metricDepthValues.map(mean) ?? depthValues.map(mean),
            nearDepthCoverage: metricDepthValues.map { coverage(values: $0, where: { $0 <= 1.25 }) }
                ?? depthValues.map { coverage(values: $0, where: { $0 > 0.82 }) },
            meanVisibility: visibilityValues.map(mean),
            lowVisibilityCoverage: visibilityValues.map { coverage(values: $0, where: { $0 < 0.18 }) },
            luminanceMean: luminanceValues.map(mean),
            luminanceVariance: luminanceValues.map(variance),
            edgeEnergy: luminanceValues.flatMap { values in rgb.map { edgeEnergy(values: values, width: $0.width, height: $0.height) } }
        )
        return RenderedFailureLabelReport(
            frameIndex: frame.index,
            generatedAt: generatedAt,
            labels: labels(metrics: metrics, frame: frame),
            metrics: metrics,
            warnings: warnings
        )
    }

    private func labels(metrics: RenderedFailureMetrics, frame: DatasetFrame) -> [RenderedFailureLabel] {
        var labels: [RenderedFailureLabel] = []
        if let nearDepthCoverage = metrics.nearDepthCoverage, nearDepthCoverage > 0.55 {
            labels.append(RenderedFailureLabel(
                kind: .blockedPrediction,
                confidence: min(0.95, 0.5 + nearDepthCoverage * 0.45),
                note: "Dense depth indicates a large near-field region in the robot camera."
            ))
        }
        if let meanVisibility = metrics.meanVisibility, meanVisibility < 0.16 {
            labels.append(RenderedFailureLabel(
                kind: .missingTrainingViews,
                confidence: min(0.9, 0.55 + (0.16 - meanVisibility) * 2.0),
                note: "Visibility product has low mean coverage; this viewpoint needs more capture views."
            ))
        }
        if let lowVisibilityCoverage = metrics.lowVisibilityCoverage, lowVisibilityCoverage > 0.65 {
            labels.append(RenderedFailureLabel(
                kind: .visualAmbiguity,
                confidence: min(0.9, 0.45 + lowVisibilityCoverage * 0.45),
                note: "Most pixels have weak splat visibility support, which can create ambiguous robot-camera input."
            ))
        }
        if let luminanceMean = metrics.luminanceMean,
           let luminanceVariance = metrics.luminanceVariance,
           luminanceMean < 0.08 || luminanceMean > 0.92 || luminanceVariance < 0.002 {
            labels.append(RenderedFailureLabel(
                kind: .badLighting,
                confidence: 0.72,
                note: "RGB luminance statistics indicate underexposure, overexposure, or very flat illumination."
            ))
        }
        if let edgeEnergy = metrics.edgeEnergy, edgeEnergy < 0.018 {
            labels.append(RenderedFailureLabel(
                kind: .lowTexture,
                confidence: 0.68,
                note: "RGB edge energy is low; visual localization or segmentation may be weak here."
            ))
        }
        if frame.productURL(for: .visibility) == nil || frame.productURL(for: .depth) == nil {
            labels.append(RenderedFailureLabel(
                kind: .uncertainLocalization,
                confidence: 0.55,
                note: "Dense depth or visibility products are missing, reducing confidence in this frame."
            ))
        }
        if labels.isEmpty {
            labels.append(RenderedFailureLabel(kind: .confident, confidence: 0.92, note: "Rendered products did not trigger dataset-quality failure labels."))
        }
        return labels
    }

    private func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let average = mean(values)
        return values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
    }

    private func coverage(values: [Double], where predicate: (Double) -> Bool) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.filter(predicate).count) / Double(values.count)
    }

    private func edgeEnergy(values: [Double], width: Int, height: Int) -> Double {
        guard width > 1, height > 1, values.count >= width * height else { return 0 }
        var total = 0.0
        var count = 0
        for y in 1..<height {
            for x in 1..<width {
                let index = y * width + x
                total += abs(values[index] - values[index - 1])
                total += abs(values[index] - values[index - width])
                count += 2
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
}

struct PNMImage {
    var magic: String
    var width: Int
    var height: Int
    var maxValue: Int
    var payload: Data

    static func read(url: URL, expectedMagic: String) throws -> PNMImage {
        let data = try Data(contentsOf: url)
        var tokens: [String] = []
        var index = data.startIndex
        while tokens.count < 4, index < data.endIndex {
            while index < data.endIndex, data[index].isASCIISpace {
                index += 1
            }
            guard index < data.endIndex else { break }
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
                throw RenderedFailureLabelError.invalidPNM(url)
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
              let maxValue = Int(tokens[3]) else {
            throw RenderedFailureLabelError.invalidPNM(url)
        }
        return PNMImage(
            magic: tokens[0],
            width: width,
            height: height,
            maxValue: max(maxValue, 1),
            payload: Data(data[index..<data.endIndex])
        )
    }

    func normalizedGrayValues() -> [Double] {
        let pixelCount = width * height
        let count = min(payload.count, pixelCount)
        return (0..<count).map { Double(payload[$0]) / Double(maxValue) }
    }

    func luminanceValues() -> [Double] {
        let pixelCount = width * height
        guard magic == "P6", payload.count >= pixelCount * 3 else {
            return normalizedGrayValues()
        }
        return (0..<pixelCount).map { pixel in
            let offset = pixel * 3
            let red = Double(payload[offset]) / Double(maxValue)
            let green = Double(payload[offset + 1]) / Double(maxValue)
            let blue = Double(payload[offset + 2]) / Double(maxValue)
            return red * 0.2126 + green * 0.7152 + blue * 0.0722
        }
    }
}

public enum RenderedFailureLabelError: Error, LocalizedError {
    case invalidPNM(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidPNM(let url):
            "Rendered product is not a valid PNM image: \(url.path)."
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
