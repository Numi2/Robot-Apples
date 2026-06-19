import Foundation

public struct RobotCaptureImport: Codable, Equatable, Sendable {
    public var packageRoot: URL
    public var manifest: RobotCapturePackageManifest
    public var session: RobotCaptureSessionMetadata
    public var frames: [RobotCaptureFrameRecord]
    public var motion: [RobotCaptureMotionRecord]
    public var captureBundle: CaptureBundleManifest

    public init(
        packageRoot: URL,
        manifest: RobotCapturePackageManifest,
        session: RobotCaptureSessionMetadata,
        frames: [RobotCaptureFrameRecord],
        motion: [RobotCaptureMotionRecord],
        captureBundle: CaptureBundleManifest
    ) {
        self.packageRoot = packageRoot
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
    public var objectCaptureImageSetCount: Int
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
        objectCaptureImageSetCount: Int = 0,
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
        self.objectCaptureImageSetCount = objectCaptureImageSetCount
        self.primaryTransferMethod = primaryTransferMethod
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case packageURL
        case importedAt
        case manifestID
        case sessionID
        case frameCount
        case motionSampleCount
        case lidarFrameCount
        case hasVideo
        case hasRoomPlanModel
        case objectCaptureAssetCount
        case objectCaptureImageSetCount
        case primaryTransferMethod
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageURL = try container.decode(URL.self, forKey: .packageURL)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        manifestID = try container.decode(String.self, forKey: .manifestID)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
        motionSampleCount = try container.decode(Int.self, forKey: .motionSampleCount)
        lidarFrameCount = try container.decode(Int.self, forKey: .lidarFrameCount)
        hasVideo = try container.decode(Bool.self, forKey: .hasVideo)
        hasRoomPlanModel = try container.decode(Bool.self, forKey: .hasRoomPlanModel)
        objectCaptureAssetCount = try container.decode(Int.self, forKey: .objectCaptureAssetCount)
        objectCaptureImageSetCount = try container.decodeIfPresent(Int.self, forKey: .objectCaptureImageSetCount) ?? 0
        primaryTransferMethod = try container.decode(LocalTransferMethod.self, forKey: .primaryTransferMethod)
        warnings = try container.decode([String].self, forKey: .warnings)
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

        let importedPackage = RobotCaptureImport(
            packageRoot: packageRoot,
            manifest: manifest,
            session: session,
            frames: frames,
            motion: motion,
            captureBundle: captureBundle
        )
        try assertPipelineReady(importedPackage)
        return normalize(importedPackage)
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
        warnings.append(contentsOf: frameImageWarnings(importedPackage: importedPackage, packageRoot: packageRoot))
        if importedPackage.motion.isEmpty {
            warnings.append("motion.jsonl contains no Core Motion samples.")
        }
        if importedPackage.session.id != importedPackage.captureBundle.scanSession.id {
            warnings.append("session.json id does not match capture_bundle.json scan session id.")
        }
        if importedPackage.frames.count != importedPackage.captureBundle.rgbFrames.count {
            warnings.append("frames.jsonl count does not match capture_bundle.json RGB frame count.")
        }
        warnings.append(contentsOf: lidarWarnings(importedPackage: importedPackage, packageRoot: packageRoot))

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
        warnings.append(contentsOf: objectCaptureImageSetWarnings(importedPackage: importedPackage, packageRoot: packageRoot))

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
            objectCaptureImageSetCount: importedPackage.captureBundle.objectCaptureImageSets.count,
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
        PackageURLTools.resolve(url, relativeTo: packageRoot)
    }

    private func normalize(_ importedPackage: RobotCaptureImport) -> RobotCaptureImport {
        let packageRoot = importedPackage.packageRoot
        return RobotCaptureImport(
            packageRoot: packageRoot,
            manifest: importedPackage.manifest,
            session: importedPackage.session,
            frames: importedPackage.frames.map { frame in
                RobotCaptureFrameRecord(
                    index: frame.index,
                    timestamp: frame.timestamp,
                    imageURL: resolve(frame.imageURL, relativeTo: packageRoot),
                    cameraTransform: frame.cameraTransform,
                    intrinsics: frame.intrinsics,
                    trackingQuality: frame.trackingQuality
                )
            },
            motion: importedPackage.motion,
            captureBundle: normalize(importedPackage.captureBundle, packageRoot: packageRoot)
        )
    }

    private func normalize(_ bundle: CaptureBundleManifest, packageRoot: URL) -> CaptureBundleManifest {
        let scanSession = normalize(bundle.scanSession, packageRoot: packageRoot)
        return CaptureBundleManifest(
            scanSession: scanSession,
            capturePlan: bundle.capturePlan,
            rgbFrames: bundle.rgbFrames.map { normalize($0, packageRoot: packageRoot) },
            lidarFrames: bundle.lidarFrames.map { normalize($0, packageRoot: packageRoot) },
            roomPlanModelURL: bundle.roomPlanModelURL.map { resolve($0, relativeTo: packageRoot) },
            objectCaptureAssetURLs: bundle.objectCaptureAssetURLs.map { resolve($0, relativeTo: packageRoot) },
            objectCaptureImageSets: bundle.objectCaptureImageSets.map { normalize($0, packageRoot: packageRoot) },
            splatTrainingManifestURL: resolve(bundle.splatTrainingManifestURL, relativeTo: packageRoot)
        )
    }

    private func normalize(_ scanSession: ScanSession, packageRoot: URL) -> ScanSession {
        ScanSession(
            id: scanSession.id,
            createdAt: scanSession.createdAt,
            worldUnit: scanSession.worldUnit,
            rgbFrames: scanSession.rgbFrames.map { normalize($0, packageRoot: packageRoot) },
            lidarFrames: scanSession.lidarFrames.map { normalize($0, packageRoot: packageRoot) },
            roomPlanModelURL: scanSession.roomPlanModelURL.map { resolve($0, relativeTo: packageRoot) },
            objectCaptureAssetURLs: scanSession.objectCaptureAssetURLs.map { resolve($0, relativeTo: packageRoot) },
            objectCaptureImageSets: scanSession.objectCaptureImageSets.map { normalize($0, packageRoot: packageRoot) }
        )
    }

    private func normalize(_ frame: CapturedRGBFrame, packageRoot: URL) -> CapturedRGBFrame {
        CapturedRGBFrame(
            imageURL: resolve(frame.imageURL, relativeTo: packageRoot),
            pose: frame.pose,
            timestamp: frame.timestamp
        )
    }

    private func normalize(_ frame: CapturedLiDARFrame, packageRoot: URL) -> CapturedLiDARFrame {
        CapturedLiDARFrame(
            depthURL: resolve(frame.depthURL, relativeTo: packageRoot),
            confidenceURL: frame.confidenceURL.map { resolve($0, relativeTo: packageRoot) },
            metadataURL: resolve(frame.metadataURL, relativeTo: packageRoot),
            pose: frame.pose,
            timestamp: frame.timestamp
        )
    }

    private func normalize(_ imageSet: ObjectCaptureImageSet, packageRoot: URL) -> ObjectCaptureImageSet {
        ObjectCaptureImageSet(
            id: imageSet.id,
            label: imageSet.label,
            imagesDirectoryURL: resolve(imageSet.imagesDirectoryURL, relativeTo: packageRoot),
            checkpointDirectoryURL: imageSet.checkpointDirectoryURL.map { resolve($0, relativeTo: packageRoot) },
            imageCount: imageSet.imageCount,
            createdAt: imageSet.createdAt,
            notes: imageSet.notes
        )
    }

    private func assertPipelineReady(_ importedPackage: RobotCaptureImport) throws {
        let packageRoot = importedPackage.packageRoot
        var issues: [String] = []
        let validation = SharedProjectFormatTools().validate(
            packageID: importedPackage.manifest.id,
            packageKind: "robotcapture",
            schemaVersion: importedPackage.manifest.schemaVersion,
            artifacts: importedPackage.manifest.artifacts,
            policy: importedPackage.manifest.artifactPolicy,
            packageRoot: packageRoot
        )
        issues.append(contentsOf: validation.issues
            .filter { $0.severity == .error }
            .map(\.message))

        if importedPackage.frames.isEmpty {
            issues.append("frames.jsonl contains no RGB frame records.")
        }
        if importedPackage.session.id != importedPackage.captureBundle.scanSession.id {
            issues.append("session.json id does not match capture_bundle.json scan session id.")
        }
        if importedPackage.frames.count != importedPackage.captureBundle.rgbFrames.count {
            issues.append("frames.jsonl count does not match capture_bundle.json RGB frame count.")
        }
        for frame in importedPackage.frames {
            if frame.intrinsics == nil {
                issues.append("Frame \(frame.index) is missing camera intrinsics.")
            }
            let imageURL = resolve(frame.imageURL, relativeTo: packageRoot)
            if !isSupportedTrainingImageURL(imageURL) {
                issues.append("Frame \(frame.index) references \(frame.imageURL.lastPathComponent), which is not a supported still image for splat training.")
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: imageURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                issues.append("Frame \(frame.index) image is missing: \(frame.imageURL.path).")
                continue
            }
            let byteCount = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            if byteCount <= 0 {
                issues.append("Frame \(frame.index) image is empty: \(frame.imageURL.lastPathComponent).")
            }
        }
        if !issues.isEmpty {
            throw RobotCaptureImportError.packageNotPipelineReady(issues)
        }
    }

    private func frameImageWarnings(importedPackage: RobotCaptureImport, packageRoot: URL) -> [String] {
        importedPackage.frames.flatMap { frame -> [String] in
            let imageURL = resolve(frame.imageURL, relativeTo: packageRoot)
            var warnings: [String] = []
            if !isSupportedTrainingImageURL(imageURL) {
                warnings.append("Frame \(frame.index) does not reference a supported still image: \(frame.imageURL.lastPathComponent).")
            }
            if !FileManager.default.fileExists(atPath: imageURL.path) {
                warnings.append("Frame \(frame.index) image is missing: \(frame.imageURL.path).")
            }
            return warnings
        }
    }

    private func isSupportedTrainingImageURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff":
            return true
        default:
            return false
        }
    }

    private func objectCaptureImageSetWarnings(importedPackage: RobotCaptureImport, packageRoot: URL) -> [String] {
        importedPackage.captureBundle.objectCaptureImageSets.flatMap { imageSet -> [String] in
            let imagesDirectoryURL = resolve(imageSet.imagesDirectoryURL, relativeTo: packageRoot)
            var isDirectory: ObjCBool = false
            var warnings: [String] = []
            guard FileManager.default.fileExists(atPath: imagesDirectoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return ["Object Capture image set \(imageSet.id) is referenced but missing: \(imageSet.imagesDirectoryURL.path)"]
            }

            let imageCount = countSupportedStillImages(in: imagesDirectoryURL)
            if imageCount == 0 {
                warnings.append("Object Capture image set \(imageSet.id) contains no supported still images.")
            }
            if imageSet.imageCount > 0, imageCount != imageSet.imageCount {
                warnings.append("Object Capture image set \(imageSet.id) reports \(imageSet.imageCount) images but contains \(imageCount).")
            }
            if let checkpointURL = imageSet.checkpointDirectoryURL.map({ resolve($0, relativeTo: packageRoot) }),
               !FileManager.default.fileExists(atPath: checkpointURL.path) {
                warnings.append("Object Capture checkpoint for image set \(imageSet.id) is referenced but missing: \(imageSet.checkpointDirectoryURL?.path ?? "")")
            }
            return warnings
        }
    }

    private func countSupportedStillImages(in directoryURL: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            guard isSupportedTrainingImageURL(url) else { return nil }
            let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isRegularFile ? url : nil
        }.count
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

    private func lidarWarnings(importedPackage: RobotCaptureImport, packageRoot: URL) -> [String] {
        var warnings: [String] = []
        let decoder = JSONDecoder.robotVisionLabDecoder
        for (index, frame) in importedPackage.captureBundle.lidarFrames.enumerated() {
            let depthURL = resolve(frame.depthURL, relativeTo: packageRoot)
            let metadataURL = resolve(frame.metadataURL, relativeTo: packageRoot)
            if depthURL.pathExtension.lowercased() != "f32" {
                warnings.append("LiDAR frame \(index) depth must be Float32 meters with .f32 extension.")
            }
            guard FileManager.default.fileExists(atPath: depthURL.path) else {
                warnings.append("LiDAR frame \(index) depth file is missing: \(frame.depthURL.path).")
                continue
            }
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                warnings.append("LiDAR frame \(index) metadata file is missing: \(frame.metadataURL.path).")
                continue
            }
            do {
                let metadata = try decoder.decode(CapturedLiDARDepthMetadata.self, from: Data(contentsOf: metadataURL))
                let expectedByteCount = metadata.width * metadata.height * MemoryLayout<Float32>.stride
                let attributes = try? FileManager.default.attributesOfItem(atPath: depthURL.path)
                let actualByteCount = (attributes?[.size] as? NSNumber)?.intValue ?? -1
                if actualByteCount != expectedByteCount {
                    warnings.append("LiDAR frame \(index) depth byte count \(actualByteCount) does not match metadata dimensions \(metadata.width)x\(metadata.height).")
                }
                if metadata.depthFormat != "float32-little-endian-meters-row-major" {
                    warnings.append("LiDAR frame \(index) depth format is \(metadata.depthFormat), expected float32-little-endian-meters-row-major.")
                }
                if resolve(metadata.depthURL, relativeTo: packageRoot).lastPathComponent != depthURL.lastPathComponent {
                    warnings.append("LiDAR frame \(index) metadata depthURL does not match capture bundle depthURL.")
                }
            } catch {
                warnings.append("LiDAR frame \(index) metadata could not be decoded: \(error.localizedDescription)")
            }
            if let confidenceURL = frame.confidenceURL.map({ resolve($0, relativeTo: packageRoot) }),
               !FileManager.default.fileExists(atPath: confidenceURL.path) {
                warnings.append("LiDAR frame \(index) confidence file is referenced but missing: \(confidenceURL.lastPathComponent).")
            }
        }
        return warnings
    }
}

public enum RobotCaptureImportError: Error, LocalizedError, CustomStringConvertible {
    case invalidJSONLine(url: URL, line: Int, underlying: Error)
    case packageNotPipelineReady([String])

    public var description: String {
        switch self {
        case .invalidJSONLine(let url, let line, let underlying):
            return "Invalid JSONL record at \(url.path):\(line): \(underlying)"
        case .packageNotPipelineReady(let issues):
            return "Robot capture package is not ready for preparation:\n- \(issues.joined(separator: "\n- "))"
        }
    }

    public var errorDescription: String? {
        description
    }
}
