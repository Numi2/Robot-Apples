import Foundation

public struct MetricDepthProductMetadata: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var depthFormat: String
    public var invalidValue: String
    public var depthURL: URL
    public var sourceVisualizationURL: URL
    public var notes: String

    public init(
        width: Int,
        height: Int,
        depthFormat: String = "float32-little-endian-meters-row-major",
        invalidValue: String = "infinity",
        depthURL: URL,
        sourceVisualizationURL: URL,
        notes: String = "Native Metal Gaussian splat depth buffer in camera-space meters; non-finite values are rays with no supported return."
    ) {
        self.width = width
        self.height = height
        self.depthFormat = depthFormat
        self.invalidValue = invalidValue
        self.depthURL = depthURL
        self.sourceVisualizationURL = sourceVisualizationURL
        self.notes = notes
    }
}

public struct MetricDepthProduct: Equatable, Sendable {
    public var metadata: MetricDepthProductMetadata
    public var valuesMeters: [Float]

    public init(metadata: MetricDepthProductMetadata, valuesMeters: [Float]) {
        self.metadata = metadata
        self.valuesMeters = valuesMeters
    }

    public func sampleMeters(x: Int, y: Int) -> Double? {
        guard metadata.width > 0, metadata.height > 0, !valuesMeters.isEmpty else { return nil }
        let clampedX = min(max(x, 0), metadata.width - 1)
        let clampedY = min(max(y, 0), metadata.height - 1)
        let index = clampedY * metadata.width + clampedX
        guard index < valuesMeters.count else { return nil }
        let value = valuesMeters[index]
        guard value.isFinite, value > 0 else { return nil }
        return Double(value)
    }
}

public enum MetricDepthProductIO {
    public static func depthURL(forVisualizationURL url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("meters.f32")
    }

    public static func metadataURL(forVisualizationURL url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("meters.json")
    }

    public static func write(
        depthPointer: UnsafePointer<Float>,
        pixelCount: Int,
        width: Int,
        height: Int,
        visualizationURL: URL
    ) throws -> MetricDepthProductMetadata {
        let depthURL = depthURL(forVisualizationURL: visualizationURL)
        let metadataURL = metadataURL(forVisualizationURL: visualizationURL)
        try FileManager.default.createDirectory(at: depthURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var data = Data()
        data.reserveCapacity(pixelCount * MemoryLayout<UInt32>.size)
        for index in 0..<pixelCount {
            let value = depthPointer[index]
            let stored = value.isFinite && value < Float.greatestFiniteMagnitude ? value : Float.infinity
            var bits = stored.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        try data.write(to: depthURL, options: .atomic)

        let metadata = MetricDepthProductMetadata(
            width: width,
            height: height,
            depthURL: depthURL,
            sourceVisualizationURL: visualizationURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(metadata).write(to: metadataURL)
        return metadata
    }

    public static func readIfPresent(forVisualizationURL url: URL) -> MetricDepthProduct? {
        let depthURL = depthURL(forVisualizationURL: url)
        let metadataURL = metadataURL(forVisualizationURL: url)
        guard FileManager.default.fileExists(atPath: depthURL.path),
              FileManager.default.fileExists(atPath: metadataURL.path),
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder.robotVisionLabDecoder.decode(MetricDepthProductMetadata.self, from: metadataData),
              let depthData = try? Data(contentsOf: depthURL) else {
            return nil
        }
        let expectedCount = max(0, metadata.width * metadata.height)
        guard depthData.count >= expectedCount * MemoryLayout<UInt32>.size else { return nil }
        var values: [Float] = []
        values.reserveCapacity(expectedCount)
        for index in 0..<expectedCount {
            let byteOffset = index * MemoryLayout<UInt32>.size
            let bits = depthData.withUnsafeBytes { rawBuffer in
                rawBuffer.loadUnaligned(fromByteOffset: byteOffset, as: UInt32.self)
            }
            values.append(Float(bitPattern: UInt32(littleEndian: bits)))
        }
        return MetricDepthProduct(metadata: metadata, valuesMeters: values)
    }
}
