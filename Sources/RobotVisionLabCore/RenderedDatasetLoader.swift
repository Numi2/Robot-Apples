import Foundation
import simd

public struct RenderedModelSample: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var timestamp: TimeInterval
    public var rgbURL: URL?
    public var depthURL: URL?
    public var visibilityURL: URL?
    public var pose: Pose3D
    public var intrinsics: CameraIntrinsics
    public var rgbCHW: [Float]
    public var depthCHW: [Float]
    public var visibilityCHW: [Float]
    public var poseVector: [Float]
    public var intrinsicsVector: [Float]
    public var warnings: [String]

    public init(
        frameIndex: Int,
        timestamp: TimeInterval,
        rgbURL: URL?,
        depthURL: URL?,
        visibilityURL: URL?,
        pose: Pose3D,
        intrinsics: CameraIntrinsics,
        rgbCHW: [Float],
        depthCHW: [Float],
        visibilityCHW: [Float],
        poseVector: [Float],
        intrinsicsVector: [Float],
        warnings: [String] = []
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.rgbURL = rgbURL
        self.depthURL = depthURL
        self.visibilityURL = visibilityURL
        self.pose = pose
        self.intrinsics = intrinsics
        self.rgbCHW = rgbCHW
        self.depthCHW = depthCHW
        self.visibilityCHW = visibilityCHW
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
        let rgb = rgbURL.flatMap { try? readPPMCHW(url: $0, expectedWidth: intrinsics.width, expectedHeight: intrinsics.height) }
        let depth = depthURL.flatMap { try? readPGMCHW(url: $0, expectedWidth: intrinsics.width, expectedHeight: intrinsics.height) }
        let visibility = visibilityURL.flatMap { try? readPGMCHW(url: $0, expectedWidth: intrinsics.width, expectedHeight: intrinsics.height) }

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

        return RenderedModelSample(
            frameIndex: frame.index,
            timestamp: frame.timestamp,
            rgbURL: rgbURL,
            depthURL: depthURL,
            visibilityURL: visibilityURL,
            pose: frame.cameraPose,
            intrinsics: intrinsics,
            rgbCHW: rgb ?? Array(repeating: 0, count: max(1, intrinsics.width * intrinsics.height * 3)),
            depthCHW: depth ?? Array(repeating: 0, count: max(1, intrinsics.width * intrinsics.height)),
            visibilityCHW: visibility ?? Array(repeating: 0, count: max(1, intrinsics.width * intrinsics.height)),
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
