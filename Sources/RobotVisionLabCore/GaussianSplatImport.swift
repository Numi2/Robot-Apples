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
        case "ply":
            return try inspectASCIIPLY(url: url)
        case "splat":
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            let estimatedCount = max(0, (fileSize?.intValue ?? 0) / 32)
            return GaussianSplatAsset(
                url: url,
                format: .splat,
                vertexCount: estimatedCount,
                bounds: AxisAlignedBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(0, 0, 0)),
                properties: [.position, .color, .opacity, .scale, .rotation]
            )
        default:
            throw GaussianSplatImportError.unsupportedFormat(url.pathExtension)
        }
    }

    private func inspectASCIIPLY(url: URL) throws -> GaussianSplatAsset {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "ply" else {
            throw GaussianSplatImportError.invalidPLY("Missing ply magic header.")
        }
        guard lines.contains("format ascii 1.0") else {
            throw GaussianSplatImportError.invalidPLY("Only ASCII PLY files are supported by this importer.")
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

        guard vertexCount > 0 else {
            throw GaussianSplatImportError.invalidPLY("PLY file does not declare vertex elements.")
        }

        let xIndex = vertexProperties.firstIndex(of: "x")
        let yIndex = vertexProperties.firstIndex(of: "y")
        let zIndex = vertexProperties.firstIndex(of: "z")
        guard let xIndex, let yIndex, let zIndex else {
            throw GaussianSplatImportError.invalidPLY("PLY vertices must contain x, y, and z properties.")
        }

        var minimum = SIMD3<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maximum = SIMD3<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
        let vertexLines = lines.dropFirst(endHeaderIndex + 1).prefix(vertexCount)
        for line in vertexLines {
            let values = line.split(separator: " ")
            guard values.count >= vertexProperties.count,
                  let x = Double(values[xIndex]),
                  let y = Double(values[yIndex]),
                  let z = Double(values[zIndex]) else {
                throw GaussianSplatImportError.invalidPLY("Invalid vertex row.")
            }
            let point = SIMD3<Double>(x, y, z)
            minimum = min(minimum, point)
            maximum = max(maximum, point)
        }

        return GaussianSplatAsset(
            url: url,
            format: .ply,
            vertexCount: vertexCount,
            bounds: AxisAlignedBounds(minimum: minimum, maximum: maximum),
            properties: detectedProperties(from: Set(vertexProperties))
        )
    }

    private func detectedProperties(from propertyNames: Set<String>) -> Set<GaussianSplatProperty> {
        var properties: Set<GaussianSplatProperty> = [.position]
        if propertyNames.isSuperset(of: ["red", "green", "blue"]) || propertyNames.isSuperset(of: ["f_dc_0", "f_dc_1", "f_dc_2"]) {
            properties.insert(.color)
        }
        if propertyNames.contains("opacity") {
            properties.insert(.opacity)
        }
        if propertyNames.contains("scale_0") || propertyNames.contains("scale") {
            properties.insert(.scale)
        }
        if propertyNames.contains("rot_0") || propertyNames.contains("rotation_0") {
            properties.insert(.rotation)
        }
        if propertyNames.contains(where: { $0.hasPrefix("f_rest_") }) {
            properties.insert(.sphericalHarmonics)
        }
        return properties
    }
}

public enum GaussianSplatImportError: Error, Equatable, LocalizedError {
    case unsupportedFormat(String)
    case invalidPLY(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            "Unsupported Gaussian splat format: \(fileExtension)"
        case .invalidPLY(let message):
            "Invalid PLY Gaussian splat: \(message)"
        }
    }
}
