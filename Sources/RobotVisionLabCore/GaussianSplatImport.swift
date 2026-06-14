import Foundation
import simd

public struct GaussianSplatAsset: Codable, Equatable, Sendable {
    public var url: URL
    public var format: GaussianSplatFormat
    public var vertexCount: Int
    public var bounds: AxisAlignedBounds
    public var properties: Set<GaussianSplatProperty>

    public init(
        url: URL,
        format: GaussianSplatFormat,
        vertexCount: Int,
        bounds: AxisAlignedBounds,
        properties: Set<GaussianSplatProperty>
    ) {
        self.url = url
        self.format = format
        self.vertexCount = vertexCount
        self.bounds = bounds
        self.properties = properties
    }

    public func makeScene(id: String, alignmentTransform: Transform3D = .identity, roomPlanModelURL: URL? = nil) -> GaussianSplatScene {
        GaussianSplatScene(
            id: id,
            source: format == .ply ? .importedPLY(url) : .importedSplat(url),
            alignmentTransform: alignmentTransform,
            bounds: bounds,
            roomPlanModelURL: roomPlanModelURL
        )
    }
}

public enum GaussianSplatFormat: String, Codable, Sendable {
    case ply
    case splat
}

public enum GaussianSplatProperty: String, Codable, CaseIterable, Sendable {
    case position
    case color
    case opacity
    case scale
    case rotation
    case sphericalHarmonics
}

public struct GaussianSplatImporter: Sendable {
    public init() {}

    public func inspect(url: URL) throws -> GaussianSplatAsset {
        switch url.pathExtension.lowercased() {
        case "ply", "splat":
            let cloud = try GaussianSplatCloudLoader().load(url: url)
            return GaussianSplatAsset(
                url: url,
                format: url.pathExtension.lowercased() == "ply" ? .ply : .splat,
                vertexCount: cloud.splats.count,
                bounds: cloud.bounds,
                properties: cloud.properties
            )
        default:
            throw GaussianSplatImportError.unsupportedFormat(url.pathExtension)
        }
    }
}

public struct RouteDerivedSplatSeedWriter: Sendable {
    public init() {}

    public func writeSeedPLY(route: RobotPath, to outputURL: URL) throws -> GaussianSplatAsset {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let points = makeSeedPoints(route: route)
        var body = """
        ply
        format ascii 1.0
        comment Robot Scene Studio route-derived Gaussian splat seed
        element vertex \(points.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header

        """
        for point in points {
            body += String(
                format: "%.6f %.6f %.6f %d %d %d %.4f %.4f %.4f %.4f %.6f %.6f %.6f %.6f\n",
                point.position.x,
                point.position.y,
                point.position.z,
                point.red,
                point.green,
                point.blue,
                point.opacity,
                point.scale.x,
                point.scale.y,
                point.scale.z,
                point.rotation.vector.x,
                point.rotation.vector.y,
                point.rotation.vector.z,
                point.rotation.vector.w
            )
        }
        try body.write(to: outputURL, atomically: true, encoding: .utf8)
        return try GaussianSplatImporter().inspect(url: outputURL)
    }

    private func makeSeedPoints(route: RobotPath) -> [RouteSeedPoint] {
        let keyframes = route.keyframes
        guard !keyframes.isEmpty else {
            return [
                RouteSeedPoint(position: SIMD3<Double>(0, 0, 0), red: 80, green: 160, blue: 255),
                RouteSeedPoint(position: SIMD3<Double>(0, 0.6, 0), red: 255, green: 255, blue: 255)
            ]
        }

        var points: [RouteSeedPoint] = []
        for (index, keyframe) in keyframes.enumerated() {
            let position = keyframe.pose.position
            points.append(RouteSeedPoint(position: position, red: 60, green: 180, blue: 255))
            points.append(RouteSeedPoint(position: SIMD3<Double>(position.x, max(0, position.y - 0.62), position.z), red: 80, green: 220, blue: 120, opacity: 0.65))
            if index > 0 {
                let previous = keyframes[index - 1].pose.position
                let mid = (previous + position) / 2
                points.append(RouteSeedPoint(position: mid, red: 255, green: 200, blue: 80, opacity: 0.55))
            }
        }
        return points
    }
}

private struct RouteSeedPoint {
    var position: SIMD3<Double>
    var red: Int
    var green: Int
    var blue: Int
    var opacity: Double
    var scale: SIMD3<Double>
    var rotation: simd_quatd

    init(
        position: SIMD3<Double>,
        red: Int,
        green: Int,
        blue: Int,
        opacity: Double = 0.85,
        scale: SIMD3<Double> = SIMD3<Double>(0.08, 0.08, 0.08),
        rotation: simd_quatd = simd_quatd(angle: 0, axis: SIMD3<Double>(0, 1, 0))
    ) {
        self.position = position
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
        self.scale = scale
        self.rotation = rotation
    }
}

public enum GaussianSplatImportError: Error, Equatable, LocalizedError {
    case unsupportedFormat(String)
    case invalidPLY(String)
    case invalidSplat(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            "Unsupported Gaussian splat format: \(fileExtension)"
        case .invalidPLY(let message):
            "Invalid PLY Gaussian splat: \(message)"
        case .invalidSplat(let message):
            "Invalid binary splat: \(message)"
        }
    }
}
