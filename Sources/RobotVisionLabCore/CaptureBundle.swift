import Foundation

public struct CaptureBundleManifest: Codable, Equatable, Sendable {
    public var scanSession: ScanSession
    public var capturePlan: CapturePlan?
    public var rgbFrames: [CapturedRGBFrame]
    public var lidarFrames: [CapturedLiDARFrame]
    public var roomPlanModelURL: URL?
    public var objectCaptureAssetURLs: [URL]
    public var splatTrainingManifestURL: URL

    public init(
        scanSession: ScanSession,
        capturePlan: CapturePlan?,
        rgbFrames: [CapturedRGBFrame],
        lidarFrames: [CapturedLiDARFrame],
        roomPlanModelURL: URL?,
        objectCaptureAssetURLs: [URL],
        splatTrainingManifestURL: URL
    ) {
        self.scanSession = scanSession
        self.capturePlan = capturePlan
        self.rgbFrames = rgbFrames
        self.lidarFrames = lidarFrames
        self.roomPlanModelURL = roomPlanModelURL
        self.objectCaptureAssetURLs = objectCaptureAssetURLs
        self.splatTrainingManifestURL = splatTrainingManifestURL
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
    public var coordinateSystem: CoordinateSystem
    public var roomPlanGeometryURL: URL?
    public var objectGeometryURLs: [URL]
    public var expectedOutput: SplatTrainingOutput

    public init(
        id: String,
        imageFrames: [SplatTrainingFrame],
        coordinateSystem: CoordinateSystem = .arkitWorldMeters,
        roomPlanGeometryURL: URL? = nil,
        objectGeometryURLs: [URL] = [],
        expectedOutput: SplatTrainingOutput
    ) {
        self.id = id
        self.imageFrames = imageFrames
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

    public init(
        imageURL: URL,
        pose: Pose3D,
        timestamp: TimeInterval,
        calibration: SplatFrameCalibration? = nil
    ) {
        self.imageURL = imageURL
        self.pose = pose
        self.timestamp = timestamp
        self.calibration = calibration
    }
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
        try fileManager.createDirectory(at: outputDirectory.appendingPathComponent("splats", isDirectory: true), withIntermediateDirectories: true)
        let packagedScanSession = rebase(scanSession, into: outputDirectory)

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
            id: "\(packagedScanSession.id)-splat-training",
            imageFrames: packagedScanSession.rgbFrames.map {
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
            roomPlanGeometryURL: packagedScanSession.roomPlanModelURL,
            objectGeometryURLs: packagedScanSession.objectCaptureAssetURLs,
            expectedOutput: SplatTrainingOutput(
                targetURL: outputDirectory
                    .appendingPathComponent("splats", isDirectory: true)
                    .appendingPathComponent("\(packagedScanSession.id).ply")
            )
        )
        let trainingManifestURL = outputDirectory.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(trainingManifest).write(to: trainingManifestURL)

        let bundle = CaptureBundleManifest(
            scanSession: packagedScanSession,
            capturePlan: capturePlan,
            rgbFrames: packagedScanSession.rgbFrames,
            lidarFrames: packagedScanSession.lidarFrames,
            roomPlanModelURL: packagedScanSession.roomPlanModelURL,
            objectCaptureAssetURLs: packagedScanSession.objectCaptureAssetURLs,
            splatTrainingManifestURL: trainingManifestURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(bundle).write(to: outputDirectory.appendingPathComponent("capture_bundle.json"))
        let videoURL = outputDirectory.appendingPathComponent("video.mov")
        let framesJSONLURL = outputDirectory.appendingPathComponent("frames.jsonl")
        let motionJSONLURL = outputDirectory.appendingPathComponent("motion.jsonl")
        let sessionJSONURL = outputDirectory.appendingPathComponent("session.json")
        let frameRecords = packagedScanSession.rgbFrames.enumerated().map { index, frame in
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
        let artifactURLs: [(String, URL)] = [
            ("frames", framesJSONLURL),
            ("motion", motionJSONLURL),
            ("session", sessionJSONURL),
            ("capture-bundle", outputDirectory.appendingPathComponent("capture_bundle.json")),
            ("splat-training-manifest", trainingManifestURL)
        ] + [packageVideoURL.map { ("video", $0) }].compactMap { $0 }
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
            validationReportURL: reportURLs.json,
            humanReportURL: reportURLs.markdown,
            videoURL: packageVideoURL,
            framesJSONLURL: framesJSONLURL,
            motionJSONLURL: motionJSONLURL,
            sessionJSONURL: sessionJSONURL,
            captureBundleURL: outputDirectory.appendingPathComponent("capture_bundle.json"),
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
            }
        )
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
