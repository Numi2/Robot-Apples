import Foundation

public struct CaptureFrameSplit: Codable, Equatable, Sendable {
    public var trainingFrameIndexes: [Int]
    public var evaluationFrameIndexes: [Int]
    public var holdoutEveryNthFrame: Int

    public init(
        trainingFrameIndexes: [Int],
        evaluationFrameIndexes: [Int],
        holdoutEveryNthFrame: Int
    ) {
        self.trainingFrameIndexes = trainingFrameIndexes
        self.evaluationFrameIndexes = evaluationFrameIndexes
        self.holdoutEveryNthFrame = holdoutEveryNthFrame
    }
}

public struct RobotCapturePreparationReport: Codable, Equatable, Sendable {
    public var preparedAt: Date
    public var captureManifestID: String
    public var sessionID: String
    public var routeURL: URL
    public var splitURL: URL
    public var splatTrainingManifestURL: URL
    public var routeKeyframeCount: Int
    public var trainingFrameCount: Int
    public var evaluationFrameCount: Int
    public var lidarDepthFrameCount: Int
    public var estimatedDurationSeconds: TimeInterval
    public var warnings: [String]

    public init(
        preparedAt: Date = Date(),
        captureManifestID: String,
        sessionID: String,
        routeURL: URL,
        splitURL: URL,
        splatTrainingManifestURL: URL,
        routeKeyframeCount: Int,
        trainingFrameCount: Int,
        evaluationFrameCount: Int,
        lidarDepthFrameCount: Int,
        estimatedDurationSeconds: TimeInterval,
        warnings: [String]
    ) {
        self.preparedAt = preparedAt
        self.captureManifestID = captureManifestID
        self.sessionID = sessionID
        self.routeURL = routeURL
        self.splitURL = splitURL
        self.splatTrainingManifestURL = splatTrainingManifestURL
        self.routeKeyframeCount = routeKeyframeCount
        self.trainingFrameCount = trainingFrameCount
        self.evaluationFrameCount = evaluationFrameCount
        self.lidarDepthFrameCount = lidarDepthFrameCount
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.warnings = warnings
    }
}

public struct RobotCapturePreparationOutput: Codable, Equatable, Sendable {
    public var route: RobotPath
    public var split: CaptureFrameSplit
    public var splatTrainingManifest: SplatTrainingManifest
    public var report: RobotCapturePreparationReport

    public init(
        route: RobotPath,
        split: CaptureFrameSplit,
        splatTrainingManifest: SplatTrainingManifest,
        report: RobotCapturePreparationReport
    ) {
        self.route = route
        self.split = split
        self.splatTrainingManifest = splatTrainingManifest
        self.report = report
    }
}

public struct RobotCapturePreparer: Sendable {
    public init() {}

    public func prepare(
        importedCapture: RobotCaptureImport,
        outputDirectory: URL,
        holdoutEveryNthFrame: Int = 5,
        preparedAt: Date = Date()
    ) throws -> RobotCapturePreparationOutput {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outputDirectory.appendingPathComponent("splats", isDirectory: true),
            withIntermediateDirectories: true
        )

        let route = makeRoute(from: importedCapture)
        let split = makeSplit(
            frames: importedCapture.frames,
            holdoutEveryNthFrame: holdoutEveryNthFrame
        )
        let trainingManifest = makeSplatTrainingManifest(
            importedCapture: importedCapture,
            split: split,
            outputDirectory: outputDirectory
        )

        let routeURL = outputDirectory.appendingPathComponent("capture_route.json")
        let splitURL = outputDirectory.appendingPathComponent("capture_evaluation_split.json")
        let trainingManifestURL = outputDirectory.appendingPathComponent("prepared_splat_training_manifest.json")
        let reportURL = outputDirectory.appendingPathComponent("robotcapture_prepare_report.json")

        let encoder = JSONEncoder.robotVisionLabEncoder
        try encoder.encode(route).write(to: routeURL)
        try encoder.encode(split).write(to: splitURL)
        try encoder.encode(trainingManifest).write(to: trainingManifestURL)

        let report = RobotCapturePreparationReport(
            preparedAt: preparedAt,
            captureManifestID: importedCapture.manifest.id,
            sessionID: importedCapture.session.id,
            routeURL: routeURL,
            splitURL: splitURL,
            splatTrainingManifestURL: trainingManifestURL,
            routeKeyframeCount: route.keyframes.count,
            trainingFrameCount: split.trainingFrameIndexes.count,
            evaluationFrameCount: split.evaluationFrameIndexes.count,
            lidarDepthFrameCount: trainingManifest.lidarFrames.count,
            estimatedDurationSeconds: estimatedDuration(from: importedCapture.frames),
            warnings: preparationWarnings(importedCapture: importedCapture, split: split)
        )
        try encoder.encode(report).write(to: reportURL)

        return RobotCapturePreparationOutput(
            route: route,
            split: split,
            splatTrainingManifest: trainingManifest,
            report: report
        )
    }

    private func makeRoute(from importedCapture: RobotCaptureImport) -> RobotPath {
        RobotPath(keyframes: importedCapture.frames.map { frame in
            RobotPathKeyframe(
                timestamp: frame.timestamp,
                pose: Pose3D(
                    position: frame.cameraTransform.translation,
                    orientation: frame.cameraTransform.rotation.value
                )
            )
        })
    }

    private func makeSplit(frames: [RobotCaptureFrameRecord], holdoutEveryNthFrame: Int) -> CaptureFrameSplit {
        let holdoutInterval = max(2, holdoutEveryNthFrame)
        var training: [Int] = []
        var evaluation: [Int] = []

        for frame in frames.sorted(by: { $0.index < $1.index }) {
            if (frame.index + 1).isMultiple(of: holdoutInterval) {
                evaluation.append(frame.index)
            } else {
                training.append(frame.index)
            }
        }

        if evaluation.isEmpty, let last = training.popLast() {
            evaluation.append(last)
        }
        if training.isEmpty, let first = evaluation.first {
            training.append(first)
        }

        return CaptureFrameSplit(
            trainingFrameIndexes: training,
            evaluationFrameIndexes: evaluation,
            holdoutEveryNthFrame: holdoutInterval
        )
    }

    private func makeSplatTrainingManifest(
        importedCapture: RobotCaptureImport,
        split: CaptureFrameSplit,
        outputDirectory: URL
    ) -> SplatTrainingManifest {
        let frameByIndex = Dictionary(uniqueKeysWithValues: importedCapture.frames.map { ($0.index, $0) })
        let imageFrames = split.trainingFrameIndexes.compactMap { index -> SplatTrainingFrame? in
            guard let frame = frameByIndex[index] else { return nil }
            return SplatTrainingFrame(
                imageURL: frame.imageURL,
                pose: Pose3D(
                    position: frame.cameraTransform.translation,
                    orientation: frame.cameraTransform.rotation.value
                ),
                timestamp: frame.timestamp,
                calibration: SplatFrameCalibration(
                    intrinsics: frame.intrinsics,
                    resolution: frame.intrinsics.map { Resolution(width: $0.width, height: $0.height) },
                    trackingQuality: frame.trackingQuality
                )
            )
        }

        return SplatTrainingManifest(
            id: "\(importedCapture.session.id)-prepared-splat-training",
            imageFrames: imageFrames,
            lidarFrames: importedCapture.captureBundle.lidarFrames,
            coordinateSystem: .arkitWorldMeters,
            roomPlanGeometryURL: importedCapture.captureBundle.roomPlanModelURL,
            objectGeometryURLs: importedCapture.captureBundle.objectCaptureAssetURLs,
            expectedOutput: SplatTrainingOutput(
                targetURL: outputDirectory
                    .appendingPathComponent("splats", isDirectory: true)
                    .appendingPathComponent("\(importedCapture.session.id).ply")
            )
        )
    }

    private func estimatedDuration(from frames: [RobotCaptureFrameRecord]) -> TimeInterval {
        guard let first = frames.map(\.timestamp).min(), let last = frames.map(\.timestamp).max() else {
            return 0
        }
        return max(0, last - first)
    }

    private func preparationWarnings(
        importedCapture: RobotCaptureImport,
        split: CaptureFrameSplit
    ) -> [String] {
        var warnings: [String] = []
        if importedCapture.frames.count < 30 {
            warnings.append("Capture has fewer than 30 pose samples; splat training coverage will be weak.")
        }
        if split.evaluationFrameIndexes.count < 2 {
            warnings.append("Evaluation split has fewer than 2 holdout frames.")
        }
        if importedCapture.frames.contains(where: { $0.trackingQuality != .normal }) {
            warnings.append("Capture contains limited or unavailable ARKit tracking records.")
        }
        if importedCapture.captureBundle.roomPlanModelURL == nil {
            warnings.append("No RoomPlan geometry is linked for structured scene alignment.")
        }
        if importedCapture.captureBundle.lidarFrames.isEmpty {
            warnings.append("No strict ARKit LiDAR Float32 depth frames are linked for depth-prior splat training.")
        }
        return warnings
    }
}
