import Foundation

public struct CaptureBundleManifest: Codable, Equatable, Sendable {
    public var scanSession: ScanSession
    public var capturePlan: CapturePlan?
    public var rgbFrames: [CapturedRGBFrame]
    public var lidarFrames: [CapturedLiDARFrame]
    public var roomPlanModelURL: URL?
    public var objectCaptureAssetURLs: [URL]
    public var objectCaptureImageSets: [ObjectCaptureImageSet]
    public var splatTrainingManifestURL: URL

    public init(
        scanSession: ScanSession,
        capturePlan: CapturePlan?,
        rgbFrames: [CapturedRGBFrame],
        lidarFrames: [CapturedLiDARFrame],
        roomPlanModelURL: URL?,
        objectCaptureAssetURLs: [URL],
        objectCaptureImageSets: [ObjectCaptureImageSet] = [],
        splatTrainingManifestURL: URL
    ) {
        self.scanSession = scanSession
        self.capturePlan = capturePlan
        self.rgbFrames = rgbFrames
        self.lidarFrames = lidarFrames
        self.roomPlanModelURL = roomPlanModelURL
        self.objectCaptureAssetURLs = objectCaptureAssetURLs
        self.objectCaptureImageSets = objectCaptureImageSets
        self.splatTrainingManifestURL = splatTrainingManifestURL
    }

    private enum CodingKeys: String, CodingKey {
        case scanSession
        case capturePlan
        case rgbFrames
        case lidarFrames
        case roomPlanModelURL
        case objectCaptureAssetURLs
        case objectCaptureImageSets
        case splatTrainingManifestURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanSession = try container.decode(ScanSession.self, forKey: .scanSession)
        capturePlan = try container.decodeIfPresent(CapturePlan.self, forKey: .capturePlan)
        rgbFrames = try container.decodeIfPresent([CapturedRGBFrame].self, forKey: .rgbFrames) ?? scanSession.rgbFrames
        lidarFrames = try container.decodeIfPresent([CapturedLiDARFrame].self, forKey: .lidarFrames) ?? scanSession.lidarFrames
        roomPlanModelURL = try container.decodeIfPresent(URL.self, forKey: .roomPlanModelURL) ?? scanSession.roomPlanModelURL
        objectCaptureAssetURLs = try container.decodeIfPresent([URL].self, forKey: .objectCaptureAssetURLs) ?? scanSession.objectCaptureAssetURLs
        objectCaptureImageSets = try container.decodeIfPresent([ObjectCaptureImageSet].self, forKey: .objectCaptureImageSets) ?? scanSession.objectCaptureImageSets
        if scanSession.objectCaptureImageSets.isEmpty, !objectCaptureImageSets.isEmpty {
            scanSession.objectCaptureImageSets = objectCaptureImageSets
        }
        splatTrainingManifestURL = try container.decode(URL.self, forKey: .splatTrainingManifestURL)
    }
}

public struct RobotCaptureFrameRecord: Codable, Equatable, Sendable {
    public var index: Int
    public var timestamp: TimeInterval
    public var imageURL: URL
    public var cameraTransform: Transform3D
    public var intrinsics: CameraIntrinsics?
    public var trackingQuality: TrackingQuality

    public init(
        index: Int,
        timestamp: TimeInterval,
        imageURL: URL,
        cameraTransform: Transform3D,
        intrinsics: CameraIntrinsics? = nil,
        trackingQuality: TrackingQuality = .normal
    ) {
        self.index = index
        self.timestamp = timestamp
        self.imageURL = imageURL
        self.cameraTransform = cameraTransform
        self.intrinsics = intrinsics
        self.trackingQuality = trackingQuality
    }
}

public enum TrackingQuality: String, Codable, Equatable, Sendable {
    case normal
    case limited
    case notAvailable
}

public struct RobotCaptureMotionRecord: Codable, Equatable, Sendable {
    public var timestamp: TimeInterval
    public var angularVelocityRadiansPerSecond: SIMD3<Double>?
    public var accelerationMetersPerSecondSquared: SIMD3<Double>?
    public var attitude: QuaternionCodable?

    public init(
        timestamp: TimeInterval,
        angularVelocityRadiansPerSecond: SIMD3<Double>? = nil,
        accelerationMetersPerSecondSquared: SIMD3<Double>? = nil,
        attitude: QuaternionCodable? = nil
    ) {
        self.timestamp = timestamp
        self.angularVelocityRadiansPerSecond = angularVelocityRadiansPerSecond
        self.accelerationMetersPerSecondSquared = accelerationMetersPerSecondSquared
        self.attitude = attitude
    }
}

public struct RobotCaptureSessionMetadata: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public var deviceModel: String
    public var operatingSystem: String
    public var lensDescription: String
    public var resolution: Resolution?
    public var targetFPS: Int?
    public var worldUnit: WorldUnit
    public var notes: String

    public init(
        id: String,
        createdAt: Date,
        deviceModel: String,
        operatingSystem: String,
        lensDescription: String,
        resolution: Resolution? = nil,
        targetFPS: Int? = nil,
        worldUnit: WorldUnit = .meters,
        notes: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.deviceModel = deviceModel
        self.operatingSystem = operatingSystem
        self.lensDescription = lensDescription
        self.resolution = resolution
        self.targetFPS = targetFPS
        self.worldUnit = worldUnit
        self.notes = notes
    }
}

public struct SplatTrainingManifest: Codable, Equatable, Sendable {
    public var id: String
    public var imageFrames: [SplatTrainingFrame]
    public var lidarFrames: [CapturedLiDARFrame]
    public var coordinateSystem: CoordinateSystem
    public var roomPlanGeometryURL: URL?
    public var objectGeometryURLs: [URL]
    public var expectedOutput: SplatTrainingOutput

    public init(
        id: String,
        imageFrames: [SplatTrainingFrame],
        lidarFrames: [CapturedLiDARFrame] = [],
        coordinateSystem: CoordinateSystem = .arkitWorldMeters,
        roomPlanGeometryURL: URL? = nil,
        objectGeometryURLs: [URL] = [],
        expectedOutput: SplatTrainingOutput
    ) {
        self.id = id
        self.imageFrames = imageFrames
        self.lidarFrames = lidarFrames
        self.coordinateSystem = coordinateSystem
        self.roomPlanGeometryURL = roomPlanGeometryURL
        self.objectGeometryURLs = objectGeometryURLs
        self.expectedOutput = expectedOutput
    }
}

public struct SplatTrainingFrame: Codable, Equatable, Sendable {
    public var imageURL: URL
    public var pose: Pose3D
    public var timestamp: TimeInterval
    public var calibration: SplatFrameCalibration?
    public var split: SplatTrainingFrameRole?

    public init(
        imageURL: URL,
        pose: Pose3D,
        timestamp: TimeInterval,
        calibration: SplatFrameCalibration? = nil,
        split: SplatTrainingFrameRole? = nil
    ) {
        self.imageURL = imageURL
        self.pose = pose
        self.timestamp = timestamp
        self.calibration = calibration
        self.split = split
    }
}

public enum SplatTrainingFrameRole: String, Codable, Equatable, Sendable {
    case train
    case validation
}

public struct SplatFrameCalibration: Codable, Equatable, Sendable {
    public var intrinsics: CameraIntrinsics?
    public var resolution: Resolution?
    public var trackingQuality: TrackingQuality

    public init(
        intrinsics: CameraIntrinsics? = nil,
        resolution: Resolution? = nil,
        trackingQuality: TrackingQuality = .normal
    ) {
        self.intrinsics = intrinsics
        self.resolution = resolution
        self.trackingQuality = trackingQuality
    }
}

public enum CoordinateSystem: String, Codable, Sendable {
    case arkitWorldMeters
    case roomPlanAlignedMeters
}

public struct SplatTrainingOutput: Codable, Equatable, Sendable {
    public var targetURL: URL
    public var preferredFormat: GaussianSplatFormat

    public init(targetURL: URL, preferredFormat: GaussianSplatFormat = .ply) {
        self.targetURL = targetURL
        self.preferredFormat = preferredFormat
    }
}

public enum CaptureBundleExportError: Error, LocalizedError, CustomStringConvertible {
    case missingSourceAsset(role: String, url: URL)

    public var errorDescription: String? {
        description
    }

    public var description: String {
        switch self {
        case .missingSourceAsset(let role, let url):
            return "\(role) source asset is missing and cannot be packaged: \(url.path)"
        }
    }
}

public struct CaptureBundleExporter: Sendable {
    public init() {}

    public func writeBundle(
        scanSession: ScanSession,
        capturePlan: CapturePlan? = nil,
        to outputDirectory: URL
    ) throws -> CaptureBundleManifest {
        if let capturePlan {
            try capturePlan.validate()
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("rgb", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("lidar", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("roomplan", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("object-capture", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: outputDirectory.appendingPathComponent("object-capture/image-sets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("splats", isDirectory: true), withIntermediateDirectories: true)
        let packagedScanSession = rebase(scanSession, into: outputDirectory)
        try copyReferencedAssets(from: scanSession, to: packagedScanSession, packageRoot: outputDirectory)
        let portableScanSession = packageRelative(packagedScanSession, packageRoot: outputDirectory)

        let intrinsics = capturePlan?.rgbVideo.map {
            CameraIntrinsics(
                width: $0.targetResolution.width,
                height: $0.targetResolution.height,
                focalLengthPixels: SIMD2(
                    Double($0.targetResolution.width),
                    Double($0.targetResolution.width)
                ),
                principalPointPixels: SIMD2(
                    Double($0.targetResolution.width) / 2.0,
                    Double($0.targetResolution.height) / 2.0
                )
            )
        }
        let resolution = capturePlan?.rgbVideo?.targetResolution
        let trainingManifest = SplatTrainingManifest(
            id: "\(portableScanSession.id)-splat-training",
            imageFrames: portableScanSession.rgbFrames.map {
                SplatTrainingFrame(
                    imageURL: $0.imageURL,
                    pose: $0.pose,
                    timestamp: $0.timestamp,
                    calibration: SplatFrameCalibration(
                        intrinsics: intrinsics,
                        resolution: resolution,
                        trackingQuality: .normal
                    )
                )
            },
            lidarFrames: portableScanSession.lidarFrames,
            roomPlanGeometryURL: portableScanSession.roomPlanModelURL,
            objectGeometryURLs: portableScanSession.objectCaptureAssetURLs,
            expectedOutput: SplatTrainingOutput(
                targetURL: PackageURLTools.relativeURL(path: "splats/\(portableScanSession.id).ply")
            )
        )
        let trainingManifestURL = outputDirectory.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(trainingManifest).write(to: trainingManifestURL)

        let bundle = CaptureBundleManifest(
            scanSession: portableScanSession,
            capturePlan: capturePlan,
            rgbFrames: portableScanSession.rgbFrames,
            lidarFrames: portableScanSession.lidarFrames,
            roomPlanModelURL: portableScanSession.roomPlanModelURL,
            objectCaptureAssetURLs: portableScanSession.objectCaptureAssetURLs,
            objectCaptureImageSets: portableScanSession.objectCaptureImageSets,
            splatTrainingManifestURL: PackageURLTools.packageRelativeURL(for: trainingManifestURL, packageRoot: outputDirectory)
        )
        try JSONEncoder.robotVisionLabEncoder.encode(bundle).write(to: outputDirectory.appendingPathComponent("capture_bundle.json"))
        let videoURL = outputDirectory.appendingPathComponent("video.mov")
        let framesJSONLURL = outputDirectory.appendingPathComponent("frames.jsonl")
        let motionJSONLURL = outputDirectory.appendingPathComponent("motion.jsonl")
        let sessionJSONURL = outputDirectory.appendingPathComponent("session.json")
        let frameRecords = portableScanSession.rgbFrames.enumerated().map { index, frame in
            RobotCaptureFrameRecord(
                index: index,
                timestamp: frame.timestamp,
                imageURL: frame.imageURL,
                cameraTransform: Transform3D(translation: frame.pose.position, rotation: frame.pose.orientation.value),
                intrinsics: intrinsics
            )
        }
        try writeJSONLines(frameRecords, to: framesJSONLURL)

        let motionRecords = packagedScanSession.rgbFrames.map {
            RobotCaptureMotionRecord(timestamp: $0.timestamp)
        }
        try writeJSONLines(motionRecords, to: motionJSONLURL)

        let sessionMetadata = RobotCaptureSessionMetadata(
            id: packagedScanSession.id,
            createdAt: packagedScanSession.createdAt,
            deviceModel: "Apple capture device",
            operatingSystem: "iOS/iPadOS",
            lensDescription: "AVFoundation capture device lens",
            resolution: capturePlan?.rgbVideo?.targetResolution,
            targetFPS: capturePlan?.rgbVideo?.targetFPS,
            worldUnit: packagedScanSession.worldUnit,
            notes: "Capture package contract for AVFoundation video, ARKit camera poses, optional Core Motion records, and RoomPlan/Object Capture side data."
        )
        try JSONEncoder.robotVisionLabEncoder.encode(sessionMetadata).write(to: sessionJSONURL)

        let tools = SharedProjectFormatTools()
        let packageVideoURL = FileManager.default.fileExists(atPath: videoURL.path) ? videoURL : nil
        let lidarArtifactURLs = packagedScanSession.lidarFrames.flatMap { frame in
            [
                ("lidar-depth", frame.depthURL),
                ("lidar-metadata", frame.metadataURL)
            ] + [frame.confidenceURL.map { ("lidar-confidence", $0) }].compactMap { $0 }
        }
        let structuredGeometryArtifactURLs: [(String, URL)] =
            [packagedScanSession.roomPlanModelURL.map { ("roomplan-geometry", $0) }].compactMap { $0 }
            + packagedScanSession.objectCaptureAssetURLs.map { ("object-capture-geometry", $0) }
        let objectCaptureImageSetArtifactURLs = packagedScanSession.objectCaptureImageSets.flatMap { imageSet in
            [
                ("object-capture-image-set", imageSet.imagesDirectoryURL),
                imageSet.checkpointDirectoryURL.map { ("object-capture-checkpoint", $0) }
            ].compactMap { $0 }
        }
        let artifactURLs: [(String, URL)] = [
            ("rgb-directory", outputDirectory.appendingPathComponent("rgb", isDirectory: true)),
            ("frames", framesJSONLURL),
            ("motion", motionJSONLURL),
            ("session", sessionJSONURL),
            ("capture-bundle", outputDirectory.appendingPathComponent("capture_bundle.json")),
            ("splat-training-manifest", trainingManifestURL)
        ] + [packageVideoURL.map { ("video", $0) }].compactMap { $0 }
            + lidarArtifactURLs
            + structuredGeometryArtifactURLs
            + objectCaptureImageSetArtifactURLs
        let artifacts = artifactURLs.map { tools.artifactRecord(role: $0.0, url: $0.1, packageRoot: outputDirectory) }
        let report = tools.validate(
            packageID: "\(packagedScanSession.id)-robot-capture",
            packageKind: "robotcapture",
            schemaVersion: .robotCaptureV1,
            artifacts: artifacts,
            policy: PackageArtifactSizePolicy(),
            packageRoot: outputDirectory
        )
        let reportURLs = try tools.writeReports(report, to: outputDirectory, title: ".robotcapture Project Report")

        let capturePackage = RobotCapturePackageManifest(
            id: "\(packagedScanSession.id)-robot-capture",
            artifacts: artifacts,
            validationReportURL: PackageURLTools.packageRelativeURL(for: reportURLs.json, packageRoot: outputDirectory),
            humanReportURL: PackageURLTools.packageRelativeURL(for: reportURLs.markdown, packageRoot: outputDirectory),
            videoURL: packageVideoURL.map { PackageURLTools.packageRelativeURL(for: $0, packageRoot: outputDirectory) },
            framesJSONLURL: PackageURLTools.packageRelativeURL(for: framesJSONLURL, packageRoot: outputDirectory),
            motionJSONLURL: PackageURLTools.packageRelativeURL(for: motionJSONLURL, packageRoot: outputDirectory),
            sessionJSONURL: PackageURLTools.packageRelativeURL(for: sessionJSONURL, packageRoot: outputDirectory),
            captureBundleURL: PackageURLTools.relativeURL(path: "capture_bundle.json"),
            notes: "Use Multipeer Connectivity for primary nearby iPhone-to-Mac transfer."
        )
        try JSONEncoder.robotVisionLabEncoder.encode(capturePackage).write(to: outputDirectory.appendingPathComponent("robotcapture.json"))
        return bundle
    }

    private func rebase(_ scanSession: ScanSession, into outputDirectory: URL) -> ScanSession {
        ScanSession(
            id: scanSession.id,
            createdAt: scanSession.createdAt,
            worldUnit: scanSession.worldUnit,
            rgbFrames: scanSession.rgbFrames.map {
                CapturedRGBFrame(
                    imageURL: outputDirectory
                        .appendingPathComponent("rgb", isDirectory: true)
                        .appendingPathComponent($0.imageURL.lastPathComponent),
                    pose: $0.pose,
                    timestamp: $0.timestamp
                )
            },
            lidarFrames: scanSession.lidarFrames.map {
                CapturedLiDARFrame(
                    depthURL: outputDirectory
                        .appendingPathComponent("lidar", isDirectory: true)
                        .appendingPathComponent($0.depthURL.lastPathComponent),
                    confidenceURL: $0.confidenceURL.map {
                        outputDirectory
                            .appendingPathComponent("lidar", isDirectory: true)
                            .appendingPathComponent($0.lastPathComponent)
                    },
                    metadataURL: outputDirectory
                        .appendingPathComponent("lidar", isDirectory: true)
                        .appendingPathComponent($0.metadataURL.lastPathComponent),
                    pose: $0.pose,
                    timestamp: $0.timestamp
                )
            },
            roomPlanModelURL: scanSession.roomPlanModelURL.map {
                outputDirectory
                    .appendingPathComponent("roomplan", isDirectory: true)
                    .appendingPathComponent($0.lastPathComponent)
            },
            objectCaptureAssetURLs: scanSession.objectCaptureAssetURLs.map {
                outputDirectory
                    .appendingPathComponent("object-capture", isDirectory: true)
                    .appendingPathComponent($0.lastPathComponent)
            },
            objectCaptureImageSets: scanSession.objectCaptureImageSets.enumerated().map { index, imageSet in
                let imageSetRoot = outputDirectory
                    .appendingPathComponent("object-capture/image-sets", isDirectory: true)
                    .appendingPathComponent(safeObjectCaptureImageSetDirectoryName(for: imageSet, index: index), isDirectory: true)
                return ObjectCaptureImageSet(
                    id: imageSet.id,
                    label: imageSet.label,
                    imagesDirectoryURL: imageSetRoot.appendingPathComponent("images", isDirectory: true),
                    checkpointDirectoryURL: imageSet.checkpointDirectoryURL.map { _ in
                        imageSetRoot.appendingPathComponent("checkpoint", isDirectory: true)
                    },
                    imageCount: imageSet.imageCount,
                    createdAt: imageSet.createdAt,
                    notes: imageSet.notes
                )
            }
        )
    }

    private func copyReferencedAssets(from source: ScanSession, to destination: ScanSession, packageRoot: URL) throws {
        for (sourceFrame, destinationFrame) in zip(source.rgbFrames, destination.rgbFrames) {
            try copyRequiredFile(from: sourceFrame.imageURL, to: destinationFrame.imageURL, role: "RGB frame")
        }
        for (sourceFrame, destinationFrame) in zip(source.lidarFrames, destination.lidarFrames) {
            try copyRequiredFile(from: sourceFrame.depthURL, to: destinationFrame.depthURL, role: "LiDAR depth")
            try copyRequiredFile(from: sourceFrame.metadataURL, to: destinationFrame.metadataURL, role: "LiDAR metadata")
            if let sourceConfidenceURL = sourceFrame.confidenceURL, let destinationConfidenceURL = destinationFrame.confidenceURL {
                try copyRequiredFile(from: sourceConfidenceURL, to: destinationConfidenceURL, role: "LiDAR confidence")
            }
            try rewriteLiDARMetadata(sourceURL: sourceFrame.metadataURL, destinationFrame: destinationFrame, packageRoot: packageRoot)
        }
        if let sourceRoomPlanURL = source.roomPlanModelURL, let destinationRoomPlanURL = destination.roomPlanModelURL {
            try copyRequiredFile(from: sourceRoomPlanURL, to: destinationRoomPlanURL, role: "RoomPlan geometry")
        }
        for (sourceURL, destinationURL) in zip(source.objectCaptureAssetURLs, destination.objectCaptureAssetURLs) {
            try copyRequiredFile(from: sourceURL, to: destinationURL, role: "Object Capture geometry")
        }
        for (sourceImageSet, destinationImageSet) in zip(source.objectCaptureImageSets, destination.objectCaptureImageSets) {
            try copyRequiredDirectory(
                from: sourceImageSet.imagesDirectoryURL,
                to: destinationImageSet.imagesDirectoryURL,
                role: "Object Capture image set"
            )
            if let sourceCheckpointURL = sourceImageSet.checkpointDirectoryURL,
               let destinationCheckpointURL = destinationImageSet.checkpointDirectoryURL {
                try copyRequiredDirectory(
                    from: sourceCheckpointURL,
                    to: destinationCheckpointURL,
                    role: "Object Capture checkpoint"
                )
            }
        }
    }

    private func copyRequiredFile(from sourceURL: URL, to destinationURL: URL, role: String) throws {
        let fileManager = FileManager.default
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                throw CaptureBundleExportError.missingSourceAsset(role: role, url: sourceURL)
            }
            return
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CaptureBundleExportError.missingSourceAsset(role: role, url: sourceURL)
        }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func copyRequiredDirectory(from sourceURL: URL, to destinationURL: URL, role: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CaptureBundleExportError.missingSourceAsset(role: role, url: sourceURL)
            }
            return
        }
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CaptureBundleExportError.missingSourceAsset(role: role, url: sourceURL)
        }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func rewriteLiDARMetadata(
        sourceURL: URL,
        destinationFrame: CapturedLiDARFrame,
        packageRoot: URL
    ) throws {
        let metadataURL = FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : destinationFrame.metadataURL
        guard var metadata = try? JSONDecoder.robotVisionLabDecoder.decode(
            CapturedLiDARDepthMetadata.self,
            from: Data(contentsOf: metadataURL)
        ) else {
            return
        }
        metadata.depthURL = PackageURLTools.packageRelativeURL(for: destinationFrame.depthURL, packageRoot: packageRoot)
        metadata.confidenceURL = destinationFrame.confidenceURL.map {
            PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot)
        }
        try JSONEncoder.robotVisionLabEncoder.encode(metadata).write(to: destinationFrame.metadataURL)
    }

    private func packageRelative(_ scanSession: ScanSession, packageRoot: URL) -> ScanSession {
        ScanSession(
            id: scanSession.id,
            createdAt: scanSession.createdAt,
            worldUnit: scanSession.worldUnit,
            rgbFrames: scanSession.rgbFrames.map {
                CapturedRGBFrame(
                    imageURL: PackageURLTools.packageRelativeURL(for: $0.imageURL, packageRoot: packageRoot),
                    pose: $0.pose,
                    timestamp: $0.timestamp
                )
            },
            lidarFrames: scanSession.lidarFrames.map {
                CapturedLiDARFrame(
                    depthURL: PackageURLTools.packageRelativeURL(for: $0.depthURL, packageRoot: packageRoot),
                    confidenceURL: $0.confidenceURL.map {
                        PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot)
                    },
                    metadataURL: PackageURLTools.packageRelativeURL(for: $0.metadataURL, packageRoot: packageRoot),
                    pose: $0.pose,
                    timestamp: $0.timestamp
                )
            },
            roomPlanModelURL: scanSession.roomPlanModelURL.map {
                PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot)
            },
            objectCaptureAssetURLs: scanSession.objectCaptureAssetURLs.map {
                PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot)
            },
            objectCaptureImageSets: scanSession.objectCaptureImageSets.map {
                ObjectCaptureImageSet(
                    id: $0.id,
                    label: $0.label,
                    imagesDirectoryURL: PackageURLTools.packageRelativeURL(for: $0.imagesDirectoryURL, packageRoot: packageRoot),
                    checkpointDirectoryURL: $0.checkpointDirectoryURL.map {
                        PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot)
                    },
                    imageCount: $0.imageCount,
                    createdAt: $0.createdAt,
                    notes: $0.notes
                )
            }
        )
    }

    private func safeObjectCaptureImageSetDirectoryName(for imageSet: ObjectCaptureImageSet, index: Int) -> String {
        let fallback = "object-\(index + 1)"
        let rawName = imageSet.id.isEmpty ? fallback : imageSet.id
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? fallback : sanitized
    }

    private func writeJSONLines<T: Encodable>(_ records: [T], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = try records.map { record in
            String(decoding: try encoder.encode(record), as: UTF8.self)
        }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
