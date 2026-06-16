import Foundation
import simd
import SplatIO

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
        let source: SplatSource = switch format {
        case .ply:
            .importedPLY(url)
        case .splat:
            .importedSplat(url)
        case .spz:
            .importedSPZ(url)
        }
        return GaussianSplatScene(
            id: id,
            source: source,
            alignmentTransform: alignmentTransform,
            bounds: bounds,
            roomPlanModelURL: roomPlanModelURL
        )
    }
}

public enum GaussianSplatFormat: String, Codable, Sendable {
    case ply
    case splat
    case spz
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
            let format: GaussianSplatFormat = url.pathExtension.lowercased() == "ply" ? .ply : .splat
            return GaussianSplatAsset(
                url: url,
                format: format,
                vertexCount: cloud.splats.count,
                bounds: cloud.bounds,
                properties: cloud.properties
            )
        case "spz":
            let points = try readSplatIOPoints(url: url)
            guard !points.isEmpty else {
                throw GaussianSplatImportError.invalidSPZ("SPZ contains no splat points.")
            }
            let bounds = bounds(for: points)
            return GaussianSplatAsset(
                url: url,
                format: .spz,
                vertexCount: points.count,
                bounds: bounds,
                properties: properties(for: points)
            )
        default:
            throw GaussianSplatImportError.unsupportedFormat(url.pathExtension)
        }
    }

    private func readSplatIOPoints(url: URL) throws -> [SplatPoint] {
        let semaphore = DispatchSemaphore(value: 0)
        let box = SplatIOReadBox()
        Task.detached {
            do {
                let reader = try AutodetectSceneReader(url)
                box.result = .success(try await reader.readAll())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result?.get() ?? []
    }

    private func bounds(for points: [SplatPoint]) -> AxisAlignedBounds {
        var minimum = SIMD3<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maximum = SIMD3<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
        for point in points {
            let position = SIMD3<Double>(Double(point.position.x), Double(point.position.y), Double(point.position.z))
            minimum = min(minimum, position)
            maximum = max(maximum, position)
        }
        return AxisAlignedBounds(minimum: minimum, maximum: maximum)
    }

    private func properties(for points: [SplatPoint]) -> Set<GaussianSplatProperty> {
        var properties: Set<GaussianSplatProperty> = [.position, .color, .opacity, .scale, .rotation]
        if points.contains(where: { $0.color.shDegree > .sh0 }) {
            properties.insert(.sphericalHarmonics)
        }
        return properties
    }
}

private final class SplatIOReadBox: @unchecked Sendable {
    var result: Result<[SplatPoint], Error>?
}

public enum GaussianSplatImportError: Error, Equatable, LocalizedError {
    case unsupportedFormat(String)
    case invalidPLY(String)
    case invalidSplat(String)
    case invalidSPZ(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            "Unsupported Gaussian splat format: \(fileExtension)"
        case .invalidPLY(let message):
            "Invalid PLY Gaussian splat: \(message)"
        case .invalidSplat(let message):
            "Invalid binary splat: \(message)"
        case .invalidSPZ(let message):
            "Invalid SPZ Gaussian splat: \(message)"
        }
    }
}
