import Foundation
import simd

public struct AugmentationRunReport: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var augmentedFrameCount: Int
    public var imageOutputs: [URL]
    public var poseOutputs: [URL]

    public init(seed: UInt64, augmentedFrameCount: Int, imageOutputs: [URL], poseOutputs: [URL]) {
        self.seed = seed
        self.augmentedFrameCount = augmentedFrameCount
        self.imageOutputs = imageOutputs
        self.poseOutputs = poseOutputs
    }
}

public struct DatasetAugmentor: Sendable {
    public init() {}

    public func augmentPPMImagesAndPoseLabels(
        manifest: DatasetManifest,
        datasetDirectory: URL,
        seed: UInt64 = 0
    ) throws -> AugmentationRunReport {
        let outputImageDirectory = datasetDirectory.appendingPathComponent("rgb_augmented", isDirectory: true)
        let outputPoseDirectory = datasetDirectory.appendingPathComponent("pose_augmented", isDirectory: true)
        try FileManager.default.createDirectory(at: outputImageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputPoseDirectory, withIntermediateDirectories: true)

        var imageOutputs: [URL] = []
        var poseOutputs: [URL] = []
        for frame in manifest.frames {
            let rng = SeededGenerator(seed: seed &+ UInt64(frame.index))
            let sourceURL = existingPPMURL(for: frame, datasetDirectory: datasetDirectory)
            if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) {
                let image = try PPMImage(data: Data(contentsOf: sourceURL))
                let augmented = applyImageAugmentations(frame.augmentations, to: image, generator: rng)
                let outputURL = outputImageDirectory.appendingPathComponent(String(format: "frame_%06d.ppm", frame.index))
                try augmented.data().write(to: outputURL)
                imageOutputs.append(outputURL)
            }

            let pose = applyPoseAugmentations(frame.augmentations, to: frame.cameraPose, generator: rng)
            let poseURL = outputPoseDirectory.appendingPathComponent(String(format: "frame_%06d.json", frame.index))
            try JSONEncoder.robotVisionLabEncoder.encode(PoseLabel(frameIndex: frame.index, timestamp: frame.timestamp, cameraPose: pose)).write(to: poseURL)
            poseOutputs.append(poseURL)
        }

        return AugmentationRunReport(
            seed: seed,
            augmentedFrameCount: manifest.frames.count,
            imageOutputs: imageOutputs,
            poseOutputs: poseOutputs
        )
    }

    public func writeReport(_ report: AugmentationRunReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }

    private func existingPPMURL(for frame: DatasetFrame, datasetDirectory: URL) -> URL? {
        let previewURL = datasetDirectory
            .appendingPathComponent("rgb", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.ppm", frame.index))
        if FileManager.default.fileExists(atPath: previewURL.path) {
            return previewURL
        }
        let splatURL = datasetDirectory
            .appendingPathComponent("rgb", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d_splat.ppm", frame.index))
        if FileManager.default.fileExists(atPath: splatURL.path) {
            return splatURL
        }
        return nil
    }

    private func applyImageAugmentations(_ augmentations: [FrameAugmentation], to image: PPMImage, generator: SeededGenerator) -> PPMImage {
        var working = image
        for augmentation in augmentations {
            switch augmentation {
            case .exposureEV(let ev):
                working = working.mapPixels { pixel, _ in
                    let multiplier = pow(2.0, ev)
                    return pixel.scaled(by: multiplier)
                }
            case .gaussianNoise(let sigma):
                working = working.mapPixels { pixel, index in
                    let local = SeededGenerator(seed: generator.state &+ UInt64(index) &* 0x9E37_79B9)
                    return pixel.noisy(sigma: sigma, generator: local)
                }
            case .motionBlur(let samples, _):
                working = working.horizontalBlur(radius: max(1, samples / 2))
            case .compressionJPEG(let quality):
                let levels = max(2, Int((quality.clamped01 * 31).rounded()))
                working = working.mapPixels { pixel, _ in
                    pixel.quantized(levels: levels)
                }
            case .cameraHeightJitterMeters, .yawJitterDegrees:
                continue
            }
        }
        return working
    }

    private func applyPoseAugmentations(_ augmentations: [FrameAugmentation], to pose: Pose3D, generator: SeededGenerator) -> Pose3D {
        var position = pose.position
        var orientation = pose.orientation.value
        for augmentation in augmentations {
            switch augmentation {
            case .cameraHeightJitterMeters(let meters):
                position.y += generator.signedUnit(at: 17) * meters
            case .yawJitterDegrees(let degrees):
                let radians = generator.signedUnit(at: 29) * degrees * .pi / 180.0
                orientation = simd_quatd(angle: radians, axis: SIMD3<Double>(0, 1, 0)) * orientation
            case .exposureEV, .gaussianNoise, .motionBlur, .compressionJPEG:
                continue
            }
        }
        return Pose3D(position: position, orientation: orientation)
    }
}

public struct PPMImage: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [SIMD3<UInt8>]

    public init(width: Int, height: Int, pixels: [SIMD3<UInt8>]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(data: Data) throws {
        let bytes = Array(data)
        var cursor = 0
        func token() throws -> String {
            while cursor < bytes.count, bytes[cursor] == 10 || bytes[cursor] == 13 || bytes[cursor] == 32 || bytes[cursor] == 9 {
                cursor += 1
            }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13, bytes[cursor] != 32, bytes[cursor] != 9 {
                cursor += 1
            }
            guard start < cursor else { throw PPMError.invalidHeader }
            return String(decoding: bytes[start..<cursor], as: UTF8.self)
        }

        guard try token() == "P6",
              let width = Int(try token()),
              let height = Int(try token()),
              try token() == "255" else {
            throw PPMError.invalidHeader
        }
        while cursor < bytes.count, bytes[cursor] == 10 || bytes[cursor] == 13 || bytes[cursor] == 32 || bytes[cursor] == 9 {
            cursor += 1
        }
        let pixelByteCount = width * height * 3
        guard bytes.count - cursor >= pixelByteCount else {
            throw PPMError.invalidPixelData
        }
        var pixels: [SIMD3<UInt8>] = []
        pixels.reserveCapacity(width * height)
        for offset in stride(from: cursor, to: cursor + pixelByteCount, by: 3) {
            pixels.append(SIMD3<UInt8>(bytes[offset], bytes[offset + 1], bytes[offset + 2]))
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    public func data() -> Data {
        var bytes = Array("P6\n\(width) \(height)\n255\n".utf8)
        for pixel in pixels {
            bytes.append(contentsOf: [pixel.x, pixel.y, pixel.z])
        }
        return Data(bytes)
    }

    func mapPixels(_ transform: (SIMD3<UInt8>, Int) -> SIMD3<UInt8>) -> PPMImage {
        PPMImage(width: width, height: height, pixels: pixels.enumerated().map { transform($0.element, $0.offset) })
    }

    func horizontalBlur(radius: Int) -> PPMImage {
        guard radius > 0 else { return self }
        var output = pixels
        for y in 0..<height {
            for x in 0..<width {
                var sumRed = 0
                var sumGreen = 0
                var sumBlue = 0
                var count = 0
                for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                    let pixel = pixels[y * width + sampleX]
                    sumRed += Int(pixel.x)
                    sumGreen += Int(pixel.y)
                    sumBlue += Int(pixel.z)
                    count += 1
                }
                output[y * width + x] = SIMD3<UInt8>(
                    UInt8(clamping: sumRed / count),
                    UInt8(clamping: sumGreen / count),
                    UInt8(clamping: sumBlue / count)
                )
            }
        }
        return PPMImage(width: width, height: height, pixels: output)
    }
}

public enum PPMError: Error, Equatable, LocalizedError {
    case invalidHeader
    case invalidPixelData
}

private struct SeededGenerator: Sendable {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value = value ^ (value >> 31)
        return Double(value & 0x1F_FFFF) / Double(0x1F_FFFF)
    }

    func signedUnit(at offset: UInt64) -> Double {
        var copy = SeededGenerator(seed: state &+ offset &* 0xBF58_476D)
        return (copy.nextUnit() * 2.0) - 1.0
    }

}

private extension SIMD3 where Scalar == UInt8 {
    func scaled(by multiplier: Double) -> SIMD3<UInt8> {
        SIMD3<UInt8>(
            UInt8(clamping: Int((Double(x) * multiplier).rounded())),
            UInt8(clamping: Int((Double(y) * multiplier).rounded())),
            UInt8(clamping: Int((Double(z) * multiplier).rounded()))
        )
    }

    func noisy(sigma: Double, generator: SeededGenerator) -> SIMD3<UInt8> {
        var local = generator
        func channel(_ value: UInt8) -> UInt8 {
            let noise = (local.nextUnit() + local.nextUnit() + local.nextUnit() - 1.5) * sigma * 255.0
            return UInt8(clamping: Int((Double(value) + noise).rounded()))
        }
        return SIMD3<UInt8>(channel(x), channel(y), channel(z))
    }

    func quantized(levels: Int) -> SIMD3<UInt8> {
        func channel(_ value: UInt8) -> UInt8 {
            let normalized = Double(value) / 255.0
            let quantized = (normalized * Double(levels - 1)).rounded() / Double(levels - 1)
            return UInt8(clamping: Int((quantized * 255.0).rounded()))
        }
        return SIMD3<UInt8>(channel(x), channel(y), channel(z))
    }
}

private extension Double {
    var clamped01: Double {
        Swift.max(0, Swift.min(1, self))
    }
}
