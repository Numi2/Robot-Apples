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
