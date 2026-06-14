import Foundation

public struct RobotCaptureImport: Codable, Equatable, Sendable {
    public var manifest: RobotCapturePackageManifest
    public var session: RobotCaptureSessionMetadata
    public var frames: [RobotCaptureFrameRecord]
    public var motion: [RobotCaptureMotionRecord]
    public var captureBundle: CaptureBundleManifest

    public init(
        manifest: RobotCapturePackageManifest,
        session: RobotCaptureSessionMetadata,
        frames: [RobotCaptureFrameRecord],
        motion: [RobotCaptureMotionRecord],
        captureBundle: CaptureBundleManifest
    ) {
        self.manifest = manifest
        self.session = session
        self.frames = frames
        self.motion = motion
        self.captureBundle = captureBundle
    }
}

public struct RobotCaptureImportReport: Codable, Equatable, Sendable {
    public var packageURL: URL
    public var importedAt: Date
    public var manifestID: String
    public var sessionID: String
    public var frameCount: Int
    public var motionSampleCount: Int
    public var lidarFrameCount: Int
    public var hasVideo: Bool
    public var hasRoomPlanModel: Bool
    public var objectCaptureAssetCount: Int
    public var primaryTransferMethod: LocalTransferMethod
    public var warnings: [String]

    public init(
        packageURL: URL,
        importedAt: Date = Date(),
        manifestID: String,
        sessionID: String,
        frameCount: Int,
        motionSampleCount: Int,
        lidarFrameCount: Int,
        hasVideo: Bool,
        hasRoomPlanModel: Bool,
        objectCaptureAssetCount: Int,
        primaryTransferMethod: LocalTransferMethod,
        warnings: [String]
    ) {
        self.packageURL = packageURL
        self.importedAt = importedAt
        self.manifestID = manifestID
        self.sessionID = sessionID
        self.frameCount = frameCount
        self.motionSampleCount = motionSampleCount
        self.lidarFrameCount = lidarFrameCount
        self.hasVideo = hasVideo
        self.hasRoomPlanModel = hasRoomPlanModel
        self.objectCaptureAssetCount = objectCaptureAssetCount
        self.primaryTransferMethod = primaryTransferMethod
        self.warnings = warnings
    }
}

public struct RobotCaptureImporter: Sendable {
    public init() {}

    public func importPackage(at packageURL: URL) throws -> RobotCaptureImport {
        let manifestURL = manifestURL(for: packageURL)
        let packageRoot = manifestURL.deletingLastPathComponent()
        let decoder = JSONDecoder.robotVisionLabDecoder
        let manifest = try decoder.decode(RobotCapturePackageManifest.self, from: Data(contentsOf: manifestURL))

        let sessionURL = resolve(manifest.sessionJSONURL, relativeTo: packageRoot)
        let framesURL = resolve(manifest.framesJSONLURL, relativeTo: packageRoot)
        let motionURL = manifest.motionJSONLURL.map { resolve($0, relativeTo: packageRoot) }
        let captureBundleURL = resolve(manifest.captureBundleURL, relativeTo: packageRoot)

        let session = try decoder.decode(RobotCaptureSessionMetadata.self, from: Data(contentsOf: sessionURL))
        let frames: [RobotCaptureFrameRecord] = try decodeJSONLines(at: framesURL)
        let motion: [RobotCaptureMotionRecord] = try motionURL.map { try decodeJSONLines(at: $0) } ?? []
        let captureBundle = try decoder.decode(CaptureBundleManifest.self, from: Data(contentsOf: captureBundleURL))

        return RobotCaptureImport(
            manifest: manifest,
            session: session,
            frames: frames,
            motion: motion,
            captureBundle: captureBundle
        )
    }

    public func makeReport(
        for importedPackage: RobotCaptureImport,
        packageURL: URL,
        importedAt: Date = Date()
    ) -> RobotCaptureImportReport {
        let packageRoot = manifestURL(for: packageURL).deletingLastPathComponent()
        let manifest = importedPackage.manifest
        var warnings: [String] = []
        let validation = SharedProjectFormatTools().validate(
            packageID: manifest.id,
            packageKind: "robotcapture",
            schemaVersion: manifest.schemaVersion,
            artifacts: manifest.artifacts,
            policy: manifest.artifactPolicy,
            packageRoot: packageRoot
        )

        if manifest.schemaVersion < .robotCaptureV1 {
            warnings.append("robotcapture.json uses an older schema and was migrated to v1 defaults.")
        }
        warnings.append(contentsOf: validation.issues.map { "\($0.severity.rawValue): \($0.message)" })

        if importedPackage.frames.isEmpty {
            warnings.append("frames.jsonl contains no camera pose records.")
        }
        if importedPackage.frames.contains(where: { $0.intrinsics == nil }) {
            warnings.append("One or more frame records are missing camera intrinsics.")
        }
        if importedPackage.motion.isEmpty {
            warnings.append("motion.jsonl contains no Core Motion samples.")
        }
        if importedPackage.session.id != importedPackage.captureBundle.scanSession.id {
            warnings.append("session.json id does not match capture_bundle.json scan session id.")
        }
        if importedPackage.frames.count != importedPackage.captureBundle.rgbFrames.count {
            warnings.append("frames.jsonl count does not match capture_bundle.json RGB frame count.")
        }

        let hasVideo: Bool
        if let videoURL = manifest.videoURL.map({ resolve($0, relativeTo: packageRoot) }) {
            hasVideo = FileManager.default.fileExists(atPath: videoURL.path)
            if !hasVideo {
                warnings.append("video.mov is referenced but not present in the package.")
            }
        } else {
            hasVideo = false
            warnings.append("robotcapture.json does not reference an AVFoundation video file.")
        }

        let roomPlanURL = importedPackage.captureBundle.roomPlanModelURL.map { resolve($0, relativeTo: packageRoot) }
        let hasRoomPlanModel = roomPlanURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if roomPlanURL != nil && !hasRoomPlanModel {
            warnings.append("RoomPlan model is referenced but not present in the package.")
        }

        for assetURL in importedPackage.captureBundle.objectCaptureAssetURLs.map({ resolve($0, relativeTo: packageRoot) }) {
            if !FileManager.default.fileExists(atPath: assetURL.path) {
                warnings.append("Object Capture asset is referenced but missing: \(assetURL.lastPathComponent)")
            }
        }

        return RobotCaptureImportReport(
            packageURL: packageURL,
            importedAt: importedAt,
            manifestID: manifest.id,
            sessionID: importedPackage.session.id,
            frameCount: importedPackage.frames.count,
            motionSampleCount: importedPackage.motion.count,
            lidarFrameCount: importedPackage.captureBundle.lidarFrames.count,
            hasVideo: hasVideo,
            hasRoomPlanModel: hasRoomPlanModel,
            objectCaptureAssetCount: importedPackage.captureBundle.objectCaptureAssetURLs.count,
            primaryTransferMethod: manifest.transferPolicy.primary,
            warnings: warnings
        )
    }

    public func writeReport(_ report: RobotCaptureImportReport, to url: URL) throws {
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: url)
    }

    private func manifestURL(for packageURL: URL) -> URL {
        if packageURL.pathExtension == "json" {
            return packageURL
        }
        return packageURL.appendingPathComponent("robotcapture.json")
    }

    private func resolve(_ url: URL, relativeTo packageRoot: URL) -> URL {
        if url.isFileURL && url.path.hasPrefix("/") {
            return url
        }
        return packageRoot.appendingPathComponent(url.relativePath)
    }

    private func decodeJSONLines<T: Decodable>(at url: URL) throws -> [T] {
        let data = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .map { lineIndex, line in
                do {
                    return try decoder.decode(T.self, from: Data(line.utf8))
                } catch {
                    throw RobotCaptureImportError.invalidJSONLine(url: url, line: lineIndex + 1, underlying: error)
                }
            }
    }
}

public enum RobotCaptureImportError: Error, CustomStringConvertible {
    case invalidJSONLine(url: URL, line: Int, underlying: Error)

    public var description: String {
        switch self {
        case .invalidJSONLine(let url, let line, let underlying):
            return "Invalid JSONL record at \(url.path):\(line): \(underlying)"
        }
    }
}
