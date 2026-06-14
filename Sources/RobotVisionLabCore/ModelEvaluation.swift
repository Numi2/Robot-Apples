import Foundation

public struct ModelEvaluationRequest: Codable, Equatable, Sendable {
    public var id: String
    public var model: LocalModelReference
    public var datasetManifestURL: URL
    public var tasks: Set<VisionTask>

    public init(id: String, model: LocalModelReference, datasetManifestURL: URL, tasks: Set<VisionTask>) {
        self.id = id
        self.model = model
        self.datasetManifestURL = datasetManifestURL
        self.tasks = tasks
    }
}

public struct LocalModelReference: Codable, Equatable, Sendable {
    public var name: String
    public var runtime: LocalModelRuntime
    public var url: URL?

    public init(name: String, runtime: LocalModelRuntime, url: URL? = nil) {
        self.name = name
        self.runtime = runtime
        self.url = url
    }
}

public enum LocalModelRuntime: String, Codable, Sendable {
    case coreML
    case mlx
}

public enum VisionTask: String, Codable, CaseIterable, Sendable {
    case navigationTargetDetection
    case obstacleDetection
    case segmentation
    case failureCaseDetection
}

public struct ModelEvaluationReport: Codable, Equatable, Sendable {
    public var request: ModelEvaluationRequest
    public var generatedAt: Date
    public var frameResults: [FrameEvaluationResult]
    public var summary: EvaluationSummary

    public init(request: ModelEvaluationRequest, generatedAt: Date = Date(), frameResults: [FrameEvaluationResult], summary: EvaluationSummary) {
        self.request = request
        self.generatedAt = generatedAt
        self.frameResults = frameResults
        self.summary = summary
    }
}

public struct FrameEvaluationResult: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var rgbURL: URL?
    public var predictions: [VisionPrediction]
    public var warnings: [String]

    public init(frameIndex: Int, rgbURL: URL?, predictions: [VisionPrediction], warnings: [String] = []) {
        self.frameIndex = frameIndex
        self.rgbURL = rgbURL
        self.predictions = predictions
        self.warnings = warnings
    }
}

public struct VisionPrediction: Codable, Equatable, Sendable {
    public var task: VisionTask
    public var label: String
    public var confidence: Double
    public var source: String
    public var failureKind: FailureMarkerKind?

    public init(
        task: VisionTask,
        label: String,
        confidence: Double,
        source: String,
        failureKind: FailureMarkerKind? = nil
    ) {
        self.task = task
        self.label = label
        self.confidence = confidence
        self.source = source
        self.failureKind = failureKind
    }
}

public struct EvaluationSummary: Codable, Equatable, Sendable {
    public var frameCount: Int
    public var warningCount: Int
    public var taskCounts: [VisionTask: Int]
    public var averageConfidence: Double
    public var failureMarkerCounts: [FailureMarkerKind: Int]

    public init(
        frameCount: Int,
        warningCount: Int,
        taskCounts: [VisionTask: Int],
        averageConfidence: Double = 0,
        failureMarkerCounts: [FailureMarkerKind: Int] = [:]
    ) {
        self.frameCount = frameCount
        self.warningCount = warningCount
        self.taskCounts = taskCounts
        self.averageConfidence = averageConfidence
        self.failureMarkerCounts = failureMarkerCounts
    }
}

public struct FailureMapCalibrationReport: Codable, Equatable, Sendable {
    public var reportID: String
    public var frameCount: Int
    public var calibratedFailureCounts: [FailureMarkerKind: Int]
    public var meanConfidenceByKind: [FailureMarkerKind: Double]
    public var blockedFrameRate: Double
    public var uncertainFrameRate: Double
    public var missingViewFrameRate: Double
    public var notes: [String]

    public init(
        reportID: String,
        frameCount: Int,
        calibratedFailureCounts: [FailureMarkerKind: Int],
        meanConfidenceByKind: [FailureMarkerKind: Double],
        blockedFrameRate: Double,
        uncertainFrameRate: Double,
        missingViewFrameRate: Double,
        notes: [String]
    ) {
        self.reportID = reportID
        self.frameCount = frameCount
        self.calibratedFailureCounts = calibratedFailureCounts
        self.meanConfidenceByKind = meanConfidenceByKind
        self.blockedFrameRate = blockedFrameRate
        self.uncertainFrameRate = uncertainFrameRate
        self.missingViewFrameRate = missingViewFrameRate
        self.notes = notes
    }
}

public struct ModelComparisonReport: Codable, Equatable, Sendable {
    public var baselineModelName: String
    public var candidateModelName: String
    public var frameCount: Int
    public var sharedPredictionCount: Int
    public var labelAgreementRate: Double
    public var averageConfidenceDelta: Double
    public var candidateWarningDelta: Int
    public var changedFrames: [ModelComparisonFrameDelta]
    public var recommendation: String

    public init(
        baselineModelName: String,
        candidateModelName: String,
        frameCount: Int,
        sharedPredictionCount: Int,
        labelAgreementRate: Double,
        averageConfidenceDelta: Double,
        candidateWarningDelta: Int,
        changedFrames: [ModelComparisonFrameDelta],
        recommendation: String
    ) {
        self.baselineModelName = baselineModelName
        self.candidateModelName = candidateModelName
        self.frameCount = frameCount
        self.sharedPredictionCount = sharedPredictionCount
        self.labelAgreementRate = labelAgreementRate
        self.averageConfidenceDelta = averageConfidenceDelta
        self.candidateWarningDelta = candidateWarningDelta
        self.changedFrames = changedFrames
        self.recommendation = recommendation
    }
}

public struct ModelComparisonFrameDelta: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(frameIndex)-\(task.rawValue)" }
    public var frameIndex: Int
    public var task: VisionTask
    public var baselineLabel: String
    public var candidateLabel: String
    public var confidenceDelta: Double

    public init(
        frameIndex: Int,
        task: VisionTask,
        baselineLabel: String,
        candidateLabel: String,
        confidenceDelta: Double
    ) {
        self.frameIndex = frameIndex
        self.task = task
        self.baselineLabel = baselineLabel
        self.candidateLabel = candidateLabel
        self.confidenceDelta = confidenceDelta
    }
}

public struct EvaluationReportWriter: Sendable {
    public init() {}

    public func write(_ report: ModelEvaluationReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }
}

public struct FailureMapCalibrationReporter: Sendable {
    public init() {}

    public func makeReport(from evaluationReport: ModelEvaluationReport) -> FailureMapCalibrationReport {
        var confidencesByKind: [FailureMarkerKind: [Double]] = [:]
        var frameKinds: [Int: Set<FailureMarkerKind>] = [:]
        for result in evaluationReport.frameResults {
            for prediction in result.predictions {
                guard let kind = prediction.failureKind ?? failureKind(from: prediction), kind != .confident else {
                    continue
                }
                confidencesByKind[kind, default: []].append(min(max(prediction.confidence, 0), 1))
                frameKinds[result.frameIndex, default: []].insert(kind)
            }
        }
        let counts = confidencesByKind.mapValues(\.count)
        let means = confidencesByKind.mapValues { values in
            values.reduce(0, +) / Double(max(values.count, 1))
        }
        let frameCount = max(evaluationReport.summary.frameCount, 1)
        return FailureMapCalibrationReport(
            reportID: "\(evaluationReport.request.id)-failure-calibration",
            frameCount: evaluationReport.summary.frameCount,
            calibratedFailureCounts: counts,
            meanConfidenceByKind: means,
            blockedFrameRate: frameRate(.blockedPrediction, frameKinds: frameKinds, frameCount: frameCount),
            uncertainFrameRate: frameRate(.uncertainLocalization, frameKinds: frameKinds, frameCount: frameCount),
            missingViewFrameRate: frameRate(.missingTrainingViews, frameKinds: frameKinds, frameCount: frameCount),
            notes: [
                "Calibrates Core ML or MLX-origin model outputs into Robot Scene failure-map marker kinds.",
                "Rates are frame-level rates, so multiple predictions on one frame count once per marker kind."
            ]
        )
    }

    public func write(_ report: FailureMapCalibrationReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }

    private func frameRate(_ kind: FailureMarkerKind, frameKinds: [Int: Set<FailureMarkerKind>], frameCount: Int) -> Double {
        Double(frameKinds.values.filter { $0.contains(kind) }.count) / Double(frameCount)
    }

    private func failureKind(from prediction: VisionPrediction) -> FailureMarkerKind? {
        let normalized = prediction.label.lowercased()
        if normalized.contains("blocked") || normalized.contains("collision") || normalized.contains("obstacle") {
            return .blockedPrediction
        }
        if normalized.contains("uncertain") || normalized.contains("localization") {
            return .uncertainLocalization
        }
        if normalized.contains("missing") || normalized.contains("view") {
            return .missingTrainingViews
        }
        if normalized.contains("ambiguous") || normalized.contains("repeat") {
            return .visualAmbiguity
        }
        if normalized.contains("texture") {
            return .lowTexture
        }
        if normalized.contains("lighting") || normalized.contains("blur") || normalized.contains("exposure") {
            return .badLighting
        }
        return nil
    }
}

public struct ModelComparisonReporter: Sendable {
    public init() {}

    public func compare(baseline: ModelEvaluationReport, candidate: ModelEvaluationReport) -> ModelComparisonReport {
        let baselineByFrame = Dictionary(uniqueKeysWithValues: baseline.frameResults.map { ($0.frameIndex, $0) })
        let candidateByFrame = Dictionary(uniqueKeysWithValues: candidate.frameResults.map { ($0.frameIndex, $0) })
        let frameIndexes = Set(baselineByFrame.keys).intersection(candidateByFrame.keys).sorted()
        var sharedCount = 0
        var labelAgreementCount = 0
        var confidenceDeltaSum = 0.0
        var changedFrames: [ModelComparisonFrameDelta] = []

        for frameIndex in frameIndexes {
            guard let baselineFrame = baselineByFrame[frameIndex],
                  let candidateFrame = candidateByFrame[frameIndex] else { continue }
            let baselineByTask = Dictionary(grouping: baselineFrame.predictions, by: \.task)
            let candidateByTask = Dictionary(grouping: candidateFrame.predictions, by: \.task)
            for task in Set(baselineByTask.keys).intersection(candidateByTask.keys) {
                guard let baselinePrediction = baselineByTask[task]?.first,
                      let candidatePrediction = candidateByTask[task]?.first else { continue }
                sharedCount += 1
                if baselinePrediction.label == candidatePrediction.label {
                    labelAgreementCount += 1
                }
                let delta = candidatePrediction.confidence - baselinePrediction.confidence
                confidenceDeltaSum += delta
                if baselinePrediction.label != candidatePrediction.label || abs(delta) >= 0.2 {
                    changedFrames.append(ModelComparisonFrameDelta(
                        frameIndex: frameIndex,
                        task: task,
                        baselineLabel: baselinePrediction.label,
                        candidateLabel: candidatePrediction.label,
                        confidenceDelta: delta
                    ))
                }
            }
        }

        let agreement = sharedCount == 0 ? 0 : Double(labelAgreementCount) / Double(sharedCount)
        let confidenceDelta = sharedCount == 0 ? 0 : confidenceDeltaSum / Double(sharedCount)
        let warningDelta = candidate.summary.warningCount - baseline.summary.warningCount
        return ModelComparisonReport(
            baselineModelName: baseline.request.model.name,
            candidateModelName: candidate.request.model.name,
            frameCount: frameIndexes.count,
            sharedPredictionCount: sharedCount,
            labelAgreementRate: agreement,
            averageConfidenceDelta: confidenceDelta,
            candidateWarningDelta: warningDelta,
            changedFrames: Array(changedFrames.prefix(100)),
            recommendation: recommendation(agreement: agreement, confidenceDelta: confidenceDelta, warningDelta: warningDelta)
        )
    }

    public func write(_ report: ModelComparisonReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }

    private func recommendation(agreement: Double, confidenceDelta: Double, warningDelta: Int) -> String {
        if warningDelta > 0 {
            return "Review candidate model warnings before promotion."
        }
        if agreement < 0.6 {
            return "Inspect changed frames in Vision Pro before promotion; candidate behavior diverges strongly."
        }
        if confidenceDelta > 0.05 {
            return "Candidate improves confidence on shared predictions; inspect failure-map calibration before promotion."
        }
        return "Candidate is comparable to baseline; inspect high-impact changed frames before promotion."
    }
}

#if canImport(CoreML)
import CoreML

public struct CoreMLDatasetEvaluator: Sendable {
    public init() {}

    public func evaluate(request: ModelEvaluationRequest, manifest: DatasetManifest, generatedAt: Date = Date()) throws -> ModelEvaluationReport {
        guard let modelURL = request.model.url else {
            throw ModelEvaluationError.missingModelURL(.coreML)
        }
        let model = try MLModel(contentsOf: modelURL)
        let schema = try CoreMLModelSchemaInspector().inspect(modelURL: modelURL)
        let loader = RenderedDatasetLoader()
        let samplesByFrame = Dictionary(uniqueKeysWithValues: loader.loadSamples(from: manifest).map { ($0.frameIndex, $0) })
        let frameResults = manifest.frames.map { frame in
            evaluate(
                frame: frame,
                sample: samplesByFrame[frame.index],
                requestedTasks: request.tasks,
                model: model,
                schema: schema
            )
        }
        return ModelEvaluationReport(
            request: request,
            generatedAt: generatedAt,
            frameResults: frameResults,
            summary: makeSummary(frameResults)
        )
    }

    private func evaluate(
        frame: DatasetFrame,
        sample: RenderedModelSample?,
        requestedTasks: Set<VisionTask>,
        model: MLModel,
        schema: NativeModelAdapterSchema
    ) -> FrameEvaluationResult {
        var warnings = sample?.warnings ?? ["Unable to load rendered model sample for frame \(frame.index)."]
        let rgbURL = frame.productURL(for: .rgb)
        guard let sample else {
            return FrameEvaluationResult(frameIndex: frame.index, rgbURL: rgbURL, predictions: [], warnings: warnings)
        }

        do {
            let input = CoreMLRenderedSampleFeatureProvider(sample: sample, schema: schema)
            let output = try model.prediction(from: input)
            let values = CoreMLModelOutputAdapter(schema: schema).outputValues(from: output)
            let predictions = NativeModelPredictionAdapter(schema: schema).predictions(from: values, tasks: requestedTasks)
            return FrameEvaluationResult(frameIndex: frame.index, rgbURL: rgbURL, predictions: predictions, warnings: warnings)
        } catch {
            warnings.append("Core ML prediction failed for frame \(frame.index): \(error.localizedDescription)")
        }

        return FrameEvaluationResult(frameIndex: frame.index, rgbURL: rgbURL, predictions: [], warnings: warnings)
    }
}
#else
public struct CoreMLDatasetEvaluator: Sendable {
    public init() {}

    public func evaluate(request: ModelEvaluationRequest, manifest: DatasetManifest, generatedAt: Date = Date()) throws -> ModelEvaluationReport {
        throw ModelEvaluationError.runtimeUnavailable(.coreML)
    }
}
#endif

public struct MLXEvaluationPlan: Codable, Equatable, Sendable {
    public var request: ModelEvaluationRequest
    public var datasetManifestURL: URL
    public var expectedReportURL: URL
    public var notes: [String]

    public init(
        request: ModelEvaluationRequest,
        datasetManifestURL: URL,
        expectedReportURL: URL,
        notes: [String] = []
    ) {
        self.request = request
        self.datasetManifestURL = datasetManifestURL
        self.expectedReportURL = expectedReportURL
        self.notes = notes
    }
}

public struct MLXEvaluationPlanWriter: Sendable {
    public init() {}

    public func write(_ plan: MLXEvaluationPlan, to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.robotVisionLabEncoder.encode(plan).write(to: outputURL)
    }
}

public enum ModelEvaluationError: Error, LocalizedError {
    case missingModelURL(LocalModelRuntime)
    case runtimeUnavailable(LocalModelRuntime)

    public var errorDescription: String? {
        switch self {
        case .missingModelURL(let runtime):
            "\(runtime.rawValue) evaluation requires a model URL."
        case .runtimeUnavailable(let runtime):
            "\(runtime.rawValue) evaluation is unavailable on this platform or build."
        }
    }
}

public func makeSummary(_ frameResults: [FrameEvaluationResult]) -> EvaluationSummary {
    let taskCounts = Dictionary(grouping: frameResults.flatMap(\.predictions), by: \.task).mapValues(\.count)
    return makeSummary(frameResults, taskCounts: taskCounts)
}

private func makeSummary(_ frameResults: [FrameEvaluationResult], taskCounts: [VisionTask: Int]) -> EvaluationSummary {
    let predictions = frameResults.flatMap(\.predictions)
    let averageConfidence = predictions.isEmpty ? 0 : predictions.reduce(0) { $0 + $1.confidence } / Double(predictions.count)
    let failureMarkerCounts = Dictionary(grouping: predictions.compactMap(\.failureKind), by: { $0 }).mapValues(\.count)
    return EvaluationSummary(
        frameCount: frameResults.count,
        warningCount: frameResults.reduce(0) { $0 + $1.warnings.count },
        taskCounts: taskCounts,
        averageConfidence: averageConfidence,
        failureMarkerCounts: failureMarkerCounts
    )
}
