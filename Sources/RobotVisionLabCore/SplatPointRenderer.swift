import Foundation
import simd

public struct RenderableSplatPoint: Codable, Equatable, Sendable {
    public var position: SIMD3<Double>
    public var color: SIMD3<UInt8>
    public var opacity: Double

    public init(position: SIMD3<Double>, color: SIMD3<UInt8> = SIMD3<UInt8>(255, 255, 255), opacity: Double = 1) {
        self.position = position
        self.color = color
        self.opacity = opacity
    }
}

public struct RenderableSplatCloud: Codable, Equatable, Sendable {
    public var sourceURL: URL
    public var points: [RenderableSplatPoint]
    public var bounds: AxisAlignedBounds

    public init(sourceURL: URL, points: [RenderableSplatPoint], bounds: AxisAlignedBounds) {
        self.sourceURL = sourceURL
        self.points = points
        self.bounds = bounds
    }
}

public struct SplatPointCloudLoader: Sendable {
    public init() {}

    public func loadASCIIPLY(url: URL) throws -> RenderableSplatCloud {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "ply" else {
            throw GaussianSplatImportError.invalidPLY("Missing ply magic header.")
        }
        guard lines.contains("format ascii 1.0") else {
            throw GaussianSplatImportError.invalidPLY("Only ASCII PLY files are supported by the point renderer.")
        }
        guard let endHeaderIndex = lines.firstIndex(of: "end_header") else {
            throw GaussianSplatImportError.invalidPLY("Missing end_header.")
        }

        var vertexCount = 0
        var vertexProperties: [String] = []
        var readingVertexElement = false
        for line in lines[..<endHeaderIndex] {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count == 3, parts[0] == "element", parts[1] == "vertex", let count = Int(parts[2]) {
                vertexCount = count
                readingVertexElement = true
                continue
            }
            if parts.first == "element", parts.dropFirst().first != "vertex" {
                readingVertexElement = false
            }
            if readingVertexElement, parts.count >= 3, parts[0] == "property" {
                vertexProperties.append(parts.last ?? "")
            }
        }

        guard let xIndex = vertexProperties.firstIndex(of: "x"),
              let yIndex = vertexProperties.firstIndex(of: "y"),
              let zIndex = vertexProperties.firstIndex(of: "z") else {
            throw GaussianSplatImportError.invalidPLY("PLY vertices must contain x, y, and z properties.")
        }

        let redIndex = vertexProperties.firstIndex(of: "red") ?? vertexProperties.firstIndex(of: "f_dc_0")
        let greenIndex = vertexProperties.firstIndex(of: "green") ?? vertexProperties.firstIndex(of: "f_dc_1")
        let blueIndex = vertexProperties.firstIndex(of: "blue") ?? vertexProperties.firstIndex(of: "f_dc_2")
        let opacityIndex = vertexProperties.firstIndex(of: "opacity")

        var points: [RenderableSplatPoint] = []
        points.reserveCapacity(vertexCount)
        var minimum = SIMD3<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maximum = SIMD3<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)

        for line in lines.dropFirst(endHeaderIndex + 1).prefix(vertexCount) {
            let values = line.split(separator: " ")
            guard values.count >= vertexProperties.count,
                  let x = Double(values[xIndex]),
                  let y = Double(values[yIndex]),
                  let z = Double(values[zIndex]) else {
                throw GaussianSplatImportError.invalidPLY("Invalid vertex row.")
            }
            let position = SIMD3<Double>(x, y, z)
            let color = SIMD3<UInt8>(
                redIndex.flatMap { UInt8(clampingText: values[$0]) } ?? 255,
                greenIndex.flatMap { UInt8(clampingText: values[$0]) } ?? 255,
                blueIndex.flatMap { UInt8(clampingText: values[$0]) } ?? 255
            )
            let opacity = opacityIndex.flatMap { Double(values[$0]) } ?? 1
            points.append(RenderableSplatPoint(position: position, color: color, opacity: opacity))
            minimum = min(minimum, position)
            maximum = max(maximum, position)
        }

        return RenderableSplatCloud(
            sourceURL: url,
            points: points,
            bounds: AxisAlignedBounds(minimum: minimum, maximum: maximum)
        )
    }
}

public struct SplatPointProjectionRenderer: SplatRenderer {
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
        guard case .importedPLY(let url) = scene.source else {
            throw SplatPointRenderError.unsupportedSceneSource
        }
        let cloud = try SplatPointCloudLoader().loadASCIIPLY(url: url)
        try FileManager.default.createDirectory(
            at: outputDirectory.appendingPathComponent("rgb", isDirectory: true),
            withIntermediateDirectories: true
        )
        let ppmURL = outputDirectory
            .appendingPathComponent("rgb", isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d_splat.ppm", frame.index))
        try renderPPM(frame: frame, cameraRig: cameraRig, cloud: cloud).write(to: ppmURL)
    }

    public func renderPPM(frame: DatasetFrame, cameraRig: RobotCameraRig, cloud: RenderableSplatCloud) -> Data {
        let width = min(cameraRig.intrinsics.width, 640)
        let height = min(cameraRig.intrinsics.height, 360)
        var pixels = Array(repeating: SIMD3<UInt8>(8, 10, 12), count: width * height)
        var depth = Array(repeating: Double.greatestFiniteMagnitude, count: width * height)

        for point in cloud.points {
            let cameraSpace = point.position - frame.cameraPose.position
            // The current convention treats negative Z as forward, matching common camera coordinates.
            let forwardDepth = -cameraSpace.z
            guard forwardDepth > 0.01 else { continue }
            let u = Int((cameraSpace.x * cameraRig.intrinsics.focalLengthPixels.x / forwardDepth) + cameraRig.intrinsics.principalPointPixels.x)
            let v = Int((-cameraSpace.y * cameraRig.intrinsics.focalLengthPixels.y / forwardDepth) + cameraRig.intrinsics.principalPointPixels.y)
            let scaledU = u * width / max(cameraRig.intrinsics.width, 1)
            let scaledV = v * height / max(cameraRig.intrinsics.height, 1)
            guard scaledU >= 0, scaledU < width, scaledV >= 0, scaledV < height else { continue }
            let index = scaledV * width + scaledU
            if forwardDepth < depth[index] {
                depth[index] = forwardDepth
                pixels[index] = point.color
            }
        }

        var bytes = Array("P6\n\(width) \(height)\n255\n".utf8)
        for pixel in pixels {
            bytes.append(contentsOf: [pixel.x, pixel.y, pixel.z])
        }
        return Data(bytes)
    }
}

public enum SplatPointRenderError: Error, Equatable, LocalizedError {
    case unsupportedSceneSource

    public var errorDescription: String? {
        switch self {
        case .unsupportedSceneSource:
            "Splat point projection currently supports imported ASCII PLY scenes."
        }
    }
}

private extension UInt8 {
    init?(clampingText value: String.SubSequence) {
        if let integer = Int(value) {
            self = UInt8(clamping: integer)
        } else if let double = Double(value) {
            self = UInt8(clamping: Int((Swift.max(0, Swift.min(1, double)) * 255).rounded()))
        } else {
            return nil
        }
    }
}
