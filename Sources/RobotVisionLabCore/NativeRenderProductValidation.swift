import Foundation

public struct NativeRenderProductValidationReport: Codable, Equatable, Sendable {
    public var frameCount: Int
    public var requiredProducts: [RenderProduct]
    public var missingProducts: [NativeRenderProductIssue]
    public var unreadableProducts: [NativeRenderProductIssue]
    public var warnings: [String]

    public init(
        frameCount: Int,
        requiredProducts: [RenderProduct],
        missingProducts: [NativeRenderProductIssue],
        unreadableProducts: [NativeRenderProductIssue],
        warnings: [String] = []
    ) {
        self.frameCount = frameCount
        self.requiredProducts = requiredProducts
        self.missingProducts = missingProducts
        self.unreadableProducts = unreadableProducts
        self.warnings = warnings
    }

    public var isReady: Bool {
        missingProducts.isEmpty && unreadableProducts.isEmpty
    }
}

public struct NativeRenderProductIssue: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var product: RenderProduct
    public var url: URL?
    public var reason: String

    public init(frameIndex: Int, product: RenderProduct, url: URL?, reason: String) {
        self.frameIndex = frameIndex
        self.product = product
        self.url = url
        self.reason = reason
    }
}

public struct NativeRenderProductValidator: Sendable {
    public var requiredProducts: [RenderProduct]

    public init(requiredProducts: [RenderProduct] = [.rgb, .depth, .visibility, .lidarScan, .failureLabels]) {
        self.requiredProducts = requiredProducts
    }

    public func validate(_ manifest: DatasetManifest) -> NativeRenderProductValidationReport {
        var missing: [NativeRenderProductIssue] = []
        var unreadable: [NativeRenderProductIssue] = []
        var warnings: [String] = []

        for frame in manifest.frames {
            for product in requiredProducts {
                guard let url = frame.productURL(for: product) else {
                    missing.append(NativeRenderProductIssue(
                        frameIndex: frame.index,
                        product: product,
                        url: nil,
                        reason: "Dataset manifest does not declare a \(product.rawValue) product URL."
                    ))
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    missing.append(NativeRenderProductIssue(
                        frameIndex: frame.index,
                        product: product,
                        url: url,
                        reason: "Required native render product file does not exist."
                    ))
                    continue
                }
                if let reason = unreadableReason(product: product, url: url) {
                    unreadable.append(NativeRenderProductIssue(
                        frameIndex: frame.index,
                        product: product,
                        url: url,
                        reason: reason
                    ))
                }
            }
        }

        if manifest.frames.isEmpty {
            warnings.append("Dataset manifest contains no frames.")
        }

        return NativeRenderProductValidationReport(
            frameCount: manifest.frames.count,
            requiredProducts: requiredProducts,
            missingProducts: missing,
            unreadableProducts: unreadable,
            warnings: warnings
        )
    }

    public func requireReady(_ manifest: DatasetManifest) throws -> NativeRenderProductValidationReport {
        let report = validate(manifest)
        guard report.isReady else {
            throw NativeRenderProductValidationError.notReady(report)
        }
        return report
    }

    private func unreadableReason(product: RenderProduct, url: URL) -> String? {
        do {
            switch product {
            case .rgb:
                _ = try RenderedProductHeaderReader.readPNMHeader(url: url, expectedMagic: "P6")
            case .depth:
                let header = try RenderedProductHeaderReader.readPNMHeader(url: url, expectedMagic: "P5")
                guard let metricDepth = MetricDepthProductIO.readIfPresent(forVisualizationURL: url) else {
                    return "Depth product is missing the required Float32 meter sidecar."
                }
                if metricDepth.metadata.width != header.width || metricDepth.metadata.height != header.height {
                    return "Depth sidecar dimensions \(metricDepth.metadata.width)x\(metricDepth.metadata.height) do not match visualization \(header.width)x\(header.height)."
                }
                if metricDepth.valuesMeters.count < header.width * header.height {
                    return "Depth sidecar does not contain one Float32 value per pixel."
                }
            case .visibility:
                _ = try RenderedProductHeaderReader.readPNMHeader(url: url, expectedMagic: "P5")
            case .lidarScan:
                let report = try JSONDecoder.robotVisionLabDecoder.decode(RenderedLiDARScanReport.self, from: Data(contentsOf: url))
                if report.metrics.rayCount <= 0 {
                    return "LiDAR scan contains no rays."
                }
            case .failureLabels:
                _ = try JSONDecoder.robotVisionLabDecoder.decode(RenderedFailureLabelReport.self, from: Data(contentsOf: url))
            case .pose, .segmentation, .obstacleMask, .navigationTarget:
                _ = try Data(contentsOf: url)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

public enum NativeRenderProductValidationError: Error, LocalizedError {
    case notReady(NativeRenderProductValidationReport)

    public var errorDescription: String? {
        switch self {
        case .notReady(let report):
            let missing = report.missingProducts.count
            let unreadable = report.unreadableProducts.count
            return "Native render products are not ready for Apple Silicon training: \(missing) missing, \(unreadable) unreadable."
        }
    }
}

private enum RenderedProductHeaderReader {
    static func readPNMHeader(url: URL, expectedMagic: String) throws -> (width: Int, height: Int, maxValue: Int) {
        let data = try Data(contentsOf: url)
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
                throw RenderedProductHeaderError.invalidHeader
            }
            tokens.append(token)
        }

        guard tokens.count == 4,
              tokens[0] == expectedMagic,
              let width = Int(tokens[1]),
              let height = Int(tokens[2]),
              let maxValue = Int(tokens[3]),
              width > 0,
              height > 0,
              maxValue > 0 else {
            throw RenderedProductHeaderError.invalidHeader
        }
        return (width, height, maxValue)
    }
}

private enum RenderedProductHeaderError: Error, LocalizedError {
    case invalidHeader

    var errorDescription: String? {
        "Rendered product has an invalid PNM header."
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
