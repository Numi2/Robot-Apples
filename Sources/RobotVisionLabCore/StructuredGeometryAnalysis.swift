import Foundation

public enum StructuredGeometryAssetRole: String, Codable, Sendable {
    case roomPlan
    case objectCapture
}

public enum StructuredGeometryFormat: String, Codable, Sendable {
    case usdz
    case usd
    case obj
    case ply
    case reality
    case unknown
}

public struct StructuredGeometryAssetReport: Codable, Equatable, Sendable {
    public var role: StructuredGeometryAssetRole
    public var label: String?
    public var url: URL
    public var exists: Bool
    public var byteCount: Int64
    public var format: StructuredGeometryFormat
    public var supportsStructuredAlignment: Bool
    public var supportsObjectPriors: Bool
    public var warnings: [String]

    public init(
        role: StructuredGeometryAssetRole,
        label: String?,
        url: URL,
        exists: Bool,
        byteCount: Int64,
        format: StructuredGeometryFormat,
        supportsStructuredAlignment: Bool,
        supportsObjectPriors: Bool,
        warnings: [String]
    ) {
        self.role = role
        self.label = label
        self.url = url
        self.exists = exists
        self.byteCount = byteCount
        self.format = format
        self.supportsStructuredAlignment = supportsStructuredAlignment
        self.supportsObjectPriors = supportsObjectPriors
        self.warnings = warnings
    }
}

public struct StructuredGeometryAnalysisReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var roomPlanAssetCount: Int
    public var objectCaptureAssetCount: Int
    public var existingAssetCount: Int
    public var totalByteCount: Int64
    public var assets: [StructuredGeometryAssetReport]
    public var recommendedCoordinateSystem: CoordinateSystem
    public var alignmentNotes: [String]
    public var warnings: [String]

    public init(
        generatedAt: Date = Date(),
        roomPlanAssetCount: Int,
        objectCaptureAssetCount: Int,
        existingAssetCount: Int,
        totalByteCount: Int64,
        assets: [StructuredGeometryAssetReport],
        recommendedCoordinateSystem: CoordinateSystem,
        alignmentNotes: [String],
        warnings: [String]
    ) {
        self.generatedAt = generatedAt
        self.roomPlanAssetCount = roomPlanAssetCount
        self.objectCaptureAssetCount = objectCaptureAssetCount
        self.existingAssetCount = existingAssetCount
        self.totalByteCount = totalByteCount
        self.assets = assets
        self.recommendedCoordinateSystem = recommendedCoordinateSystem
        self.alignmentNotes = alignmentNotes
        self.warnings = warnings
    }
}

public struct StructuredGeometryAnalyzer: Sendable {
    public init() {}

    public func analyze(
        captureBundle: CaptureBundleManifest,
        packageRoot: URL,
        generatedAt: Date = Date()
    ) -> StructuredGeometryAnalysisReport {
        var assets: [StructuredGeometryAssetReport] = []
        if let roomPlanModelURL = captureBundle.roomPlanModelURL {
            assets.append(makeAssetReport(
                role: .roomPlan,
                label: "RoomPlan room model",
                url: resolve(roomPlanModelURL, relativeTo: packageRoot),
                packageURL: roomPlanModelURL
            ))
        }

        let objectLabels = captureBundle.capturePlan?.objectCapture?.objectLabels ?? []
        for (index, objectURL) in captureBundle.objectCaptureAssetURLs.enumerated() {
            assets.append(makeAssetReport(
                role: .objectCapture,
                label: index < objectLabels.count ? objectLabels[index] : objectURL.deletingPathExtension().lastPathComponent,
                url: resolve(objectURL, relativeTo: packageRoot),
                packageURL: objectURL
            ))
        }

        let roomPlanCount = assets.filter { $0.role == .roomPlan }.count
        let objectCount = assets.filter { $0.role == .objectCapture }.count
        let existingCount = assets.filter(\.exists).count
        let totalBytes = assets.reduce(Int64(0)) { $0 + $1.byteCount }
        let warnings = analysisWarnings(assets: assets, roomPlanCount: roomPlanCount, objectCount: objectCount)
        return StructuredGeometryAnalysisReport(
            generatedAt: generatedAt,
            roomPlanAssetCount: roomPlanCount,
            objectCaptureAssetCount: objectCount,
            existingAssetCount: existingCount,
            totalByteCount: totalBytes,
            assets: assets,
            recommendedCoordinateSystem: roomPlanCount > 0 ? .roomPlanAlignedMeters : .arkitWorldMeters,
            alignmentNotes: alignmentNotes(roomPlanCount: roomPlanCount, objectCount: objectCount),
            warnings: warnings
        )
    }

    public func write(_ report: StructuredGeometryAnalysisReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }

    private func makeAssetReport(
        role: StructuredGeometryAssetRole,
        label: String?,
        url: URL,
        packageURL: URL
    ) -> StructuredGeometryAssetReport {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let format = StructuredGeometryFormat(pathExtension: url.pathExtension)
        var warnings: [String] = []
        if !exists {
            warnings.append("\(role.rawValue) asset is referenced but missing: \(packageURL.path).")
        }
        if exists && byteCount == 0 {
            warnings.append("\(role.rawValue) asset is empty: \(packageURL.path).")
        }
        if !format.isAppleGeometryContainer {
            warnings.append("\(role.rawValue) asset format \(url.pathExtension) has limited Apple-native geometry semantics.")
        }
        return StructuredGeometryAssetReport(
            role: role,
            label: label,
            url: packageURL,
            exists: exists,
            byteCount: byteCount,
            format: format,
            supportsStructuredAlignment: role == .roomPlan && format.isAppleGeometryContainer,
            supportsObjectPriors: role == .objectCapture && exists,
            warnings: warnings
        )
    }

    private func analysisWarnings(assets: [StructuredGeometryAssetReport], roomPlanCount: Int, objectCount: Int) -> [String] {
        var warnings = assets.flatMap(\.warnings)
        if roomPlanCount == 0 {
            warnings.append("No RoomPlan asset is linked; Mac alignment will rely on ARKit route bounds, LiDAR depth priors, or manual anchors.")
        }
        if objectCount == 0 {
            warnings.append("No Object Capture assets are linked; object-level priors will not be available for segmentation or obstacle labels.")
        }
        return warnings
    }

    private func alignmentNotes(roomPlanCount: Int, objectCount: Int) -> [String] {
        var notes: [String] = []
        if roomPlanCount > 0 {
            notes.append("Use RoomPlan geometry as the meter-scale structured scene frame before manual ARKit-to-splat anchor refinement.")
            notes.append("Use floors and walls from RoomPlan as route height and obstacle constraints when available.")
            notes.append("RoomPlan USDZ is available for Apple-native spatial alignment; add semantic room-element extraction when richer RoomPlan JSON export is present.")
        }
        if objectCount > 0 {
            notes.append("Use Object Capture assets as object priors for obstacle labels, segmentation hints, and repeated-object ambiguity review.")
        }
        if notes.isEmpty {
            notes.append("No structured geometry assets were linked for this capture.")
        }
        return notes
    }

    private func resolve(_ url: URL, relativeTo packageRoot: URL) -> URL {
        PackageURLTools.resolve(url, relativeTo: packageRoot)
    }
}

private extension StructuredGeometryFormat {
    init(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "usdz":
            self = .usdz
        case "usd", "usda", "usdc":
            self = .usd
        case "obj":
            self = .obj
        case "ply":
            self = .ply
        case "reality":
            self = .reality
        default:
            self = .unknown
        }
    }

    var isAppleGeometryContainer: Bool {
        switch self {
        case .usdz, .usd, .reality:
            return true
        case .obj, .ply, .unknown:
            return false
        }
    }
}
