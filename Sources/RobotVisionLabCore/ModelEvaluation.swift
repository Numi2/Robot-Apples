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
    public var modelEvidenceCounts: [FailureMarkerKind: Int]
    public var nativeEvidenceCounts: [FailureMarkerKind: Int]
    public var meanConfidenceByKind: [FailureMarkerKind: Double]
    public var agreementRateByKind: [FailureMarkerKind: Double]
    public var modelNativeAgreementRate: Double
    public var blockedFrameRate: Double
    public var uncertainFrameRate: Double
    public var missingViewFrameRate: Double
    public var lidarBlockedFrameRate: Double
    public var lowLidarSupportFrameRate: Double
    public var notes: [String]

    public init(
        reportID: String,
        frameCount: Int,
        calibratedFailureCounts: [FailureMarkerKind: Int],
        modelEvidenceCounts: [FailureMarkerKind: Int],
        nativeEvidenceCounts: [FailureMarkerKind: Int],
        meanConfidenceByKind: [FailureMarkerKind: Double],
        agreementRateByKind: [FailureMarkerKind: Double],
        modelNativeAgreementRate: Double,
        blockedFrameRate: Double,
        uncertainFrameRate: Double,
        missingViewFrameRate: Double,
        lidarBlockedFrameRate: Double,
        lowLidarSupportFrameRate: Double,
        notes: [String]
    ) {
        self.reportID = reportID
        self.frameCount = frameCount
        self.calibratedFailureCounts = calibratedFailureCounts
        self.modelEvidenceCounts = modelEvidenceCounts
        self.nativeEvidenceCounts = nativeEvidenceCounts
        self.meanConfidenceByKind = meanConfidenceByKind
        self.agreementRateByKind = agreementRateByKind
        self.modelNativeAgreementRate = modelNativeAgreementRate
        self.blockedFrameRate = blockedFrameRate
        self.uncertainFrameRate = uncertainFrameRate
        self.missingViewFrameRate = missingViewFrameRate
        self.lidarBlockedFrameRate = lidarBlockedFrameRate
        self.lowLidarSupportFrameRate = lowLidarSupportFrameRate
        self.notes = notes
    }
}

private struct LiDAREvidence: Sendable {
    var blockedFrames: Set<Int>
    var lowSupportFrames: Set<Int>

    static let empty = LiDAREvidence(blockedFrames: [], lowSupportFrames: [])

    func blockedFrameRate(frameCount: Int) -> Double {
        Double(blockedFrames.count) / Double(max(frameCount, 1))
    }

    func lowSupportFrameRate(frameCount: Int) -> Double {
        Double(lowSupportFrames.count) / Double(max(frameCount, 1))
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

    public func makeReport(from evaluationReport: ModelEvaluationReport, manifest: DatasetManifest? = nil) -> FailureMapCalibrationReport {
        var confidencesByKind: [FailureMarkerKind: [Double]] = [:]
        var modelFrameKinds: [Int: Set<FailureMarkerKind>] = [:]
        for result in evaluationReport.frameResults {
            for prediction in result.predictions {
                guard let kind = prediction.failureKind ?? failureKind(from: prediction), kind != .confident else {
                    continue
                }
                confidencesByKind[kind, default: []].append(min(max(prediction.confidence, 0), 1))
                modelFrameKinds[result.frameIndex, default: []].insert(kind)
            }
        }
        let nativeEvidence = manifest.map(nativeFrameKinds(from:)) ?? [:]
        let lidarEvidence = manifest.map(lidarEvidence(from:)) ?? LiDAREvidence.empty
        let modelCounts = counts(from: modelFrameKinds)
        let nativeCounts = counts(from: nativeEvidence)
        let counts = mergedCounts(modelCounts, nativeCounts)
        let means = confidencesByKind.mapValues { values in
            values.reduce(0, +) / Double(max(values.count, 1))
        }
        let frameCount = max(evaluationReport.summary.frameCount, 1)
        let agreement = agreementRates(model: modelFrameKinds, native: nativeEvidence)
        let notes = notes(
            hasNativeEvidence: manifest != nil,
            modelFrameKinds: modelFrameKinds,
            nativeFrameKinds: nativeEvidence,
            lidarEvidence: lidarEvidence
        )
        return FailureMapCalibrationReport(
            reportID: "\(evaluationReport.request.id)-failure-calibration",
            frameCount: evaluationReport.summary.frameCount,
            calibratedFailureCounts: counts,
            modelEvidenceCounts: modelCounts,
            nativeEvidenceCounts: nativeCounts,
            meanConfidenceByKind: means,
            agreementRateByKind: agreement.byKind,
            modelNativeAgreementRate: agreement.overall,
            blockedFrameRate: frameRate(.blockedPrediction, frameKinds: mergedFrameKinds(modelFrameKinds, nativeEvidence), frameCount: frameCount),
            uncertainFrameRate: frameRate(.uncertainLocalization, frameKinds: mergedFrameKinds(modelFrameKinds, nativeEvidence), frameCount: frameCount),
            missingViewFrameRate: frameRate(.missingTrainingViews, frameKinds: mergedFrameKinds(modelFrameKinds, nativeEvidence), frameCount: frameCount),
            lidarBlockedFrameRate: lidarEvidence.blockedFrameRate(frameCount: frameCount),
            lowLidarSupportFrameRate: lidarEvidence.lowSupportFrameRate(frameCount: frameCount),
            notes: notes
        )
    }

    public func write(_ report: FailureMapCalibrationReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }

    private func frameRate(_ kind: FailureMarkerKind, frameKinds: [Int: Set<FailureMarkerKind>], frameCount: Int) -> Double {
        Double(frameKinds.values.filter { $0.contains(kind) }.count) / Double(frameCount)
    }

    private func nativeFrameKinds(from manifest: DatasetManifest) -> [Int: Set<FailureMarkerKind>] {
        var frameKinds: [Int: Set<FailureMarkerKind>] = [:]
        for frame in manifest.frames {
            for label in renderedFailureLabels(frame) where label.kind != .confident {
                frameKinds[frame.index, default: []].insert(label.kind)
            }
            for kind in lidarKinds(frame) {
                frameKinds[frame.index, default: []].insert(kind)
            }
        }
        return frameKinds
    }

    private func renderedFailureLabels(_ frame: DatasetFrame) -> [RenderedFailureLabel] {
        guard let url = frame.productURL(for: .failureLabels),
              let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder.robotVisionLabDecoder.decode(RenderedFailureLabelReport.self, from: data) else {
            return []
        }
        return report.labels
    }

    private func lidarKinds(_ frame: DatasetFrame) -> Set<FailureMarkerKind> {
        guard let report = lidarReport(frame) else { return [] }
        var kinds: Set<FailureMarkerKind> = []
        let validRayCount = max(report.metrics.validRayCount, 1)
        let validFraction = Double(report.metrics.validRayCount) / Double(max(report.metrics.rayCount, 1))
        let nearRayRate = Double(report.rays.filter { ray in
            guard !ray.droppedOut, let point = ray.cameraPointMeters else { return false }
            return abs(point.z) < 1.0
        }.count) / Double(validRayCount)
        if nearRayRate > 0.42 || (report.metrics.meanRangeMeters ?? .greatestFiniteMagnitude) < 1.2 {
            kinds.insert(.blockedPrediction)
        }
        if report.metrics.dropoutRate > 0.45 || report.metrics.lowSupportRate > 0.38 {
            kinds.insert(.uncertainLocalization)
        }
        if validFraction < 0.35 || report.metrics.lowSupportRate > 0.52 {
            kinds.insert(.missingTrainingViews)
        }
        return kinds
    }

    private func lidarEvidence(from manifest: DatasetManifest) -> LiDAREvidence {
        var evidence = LiDAREvidence.empty
        for frame in manifest.frames {
            guard let report = lidarReport(frame) else { continue }
            let validRayCount = max(report.metrics.validRayCount, 1)
            let nearRayRate = Double(report.rays.filter { ray in
                guard !ray.droppedOut, let point = ray.cameraPointMeters else { return false }
                return abs(point.z) < 1.0
            }.count) / Double(validRayCount)
            if nearRayRate > 0.42 || (report.metrics.meanRangeMeters ?? .greatestFiniteMagnitude) < 1.2 {
                evidence.blockedFrames.insert(frame.index)
            }
            if report.metrics.dropoutRate > 0.45 || report.metrics.lowSupportRate > 0.38 {
                evidence.lowSupportFrames.insert(frame.index)
            }
        }
        return evidence
    }

    private func lidarReport(_ frame: DatasetFrame) -> RenderedLiDARScanReport? {
        guard let url = frame.productURL(for: .lidarScan),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.robotVisionLabDecoder.decode(RenderedLiDARScanReport.self, from: data)
    }

    private func counts(from frameKinds: [Int: Set<FailureMarkerKind>]) -> [FailureMarkerKind: Int] {
        var counts: [FailureMarkerKind: Int] = [:]
        for kinds in frameKinds.values {
            for kind in kinds where kind != .confident {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }

    private func mergedCounts(_ lhs: [FailureMarkerKind: Int], _ rhs: [FailureMarkerKind: Int]) -> [FailureMarkerKind: Int] {
        var merged = lhs
        for (kind, count) in rhs {
            merged[kind, default: 0] += count
        }
        return merged
    }

    private func mergedFrameKinds(_ lhs: [Int: Set<FailureMarkerKind>], _ rhs: [Int: Set<FailureMarkerKind>]) -> [Int: Set<FailureMarkerKind>] {
        var merged = lhs
        for (frameIndex, kinds) in rhs {
            merged[frameIndex, default: []].formUnion(kinds)
        }
        return merged
    }

    private func agreementRates(model: [Int: Set<FailureMarkerKind>], native: [Int: Set<FailureMarkerKind>]) -> (byKind: [FailureMarkerKind: Double], overall: Double) {
        let sharedFrames = Set(model.keys).intersection(native.keys)
        guard !sharedFrames.isEmpty else { return ([:], 0) }
        var byKind: [FailureMarkerKind: Double] = [:]
        for kind in FailureMarkerKind.allCases where kind != .confident {
            let relevantFrames = sharedFrames.filter {
                model[$0, default: []].contains(kind) || native[$0, default: []].contains(kind)
            }
            guard !relevantFrames.isEmpty else { continue }
            let agreed = relevantFrames.filter {
                model[$0, default: []].contains(kind) && native[$0, default: []].contains(kind)
            }
            byKind[kind] = Double(agreed.count) / Double(relevantFrames.count)
        }
        let agreedFrames = sharedFrames.filter { !model[$0, default: []].intersection(native[$0, default: []]).isEmpty }
        return (byKind, Double(agreedFrames.count) / Double(sharedFrames.count))
    }

    private func notes(
        hasNativeEvidence: Bool,
        modelFrameKinds: [Int: Set<FailureMarkerKind>],
        nativeFrameKinds: [Int: Set<FailureMarkerKind>],
        lidarEvidence: LiDAREvidence
    ) -> [String] {
        var notes = [
            "Calibrates Core ML or MLX-origin model outputs into Robot Scene failure-map marker kinds.",
            "Rates are frame-level rates, so multiple predictions on one frame count once per marker kind."
        ]
        if hasNativeEvidence {
            notes.append("Native rendered failure labels and synthetic LiDAR geometry are used as Apple-native calibration evidence.")
        } else {
            notes.append("No dataset manifest was supplied, so this report contains model-output calibration only.")
        }
        if !modelFrameKinds.isEmpty, nativeFrameKinds.isEmpty {
            notes.append("Model failures have no native render evidence yet; render RGB/depth/visibility, failure labels, and LiDAR scans before product review.")
        }
        if !lidarEvidence.blockedFrames.isEmpty || !lidarEvidence.lowSupportFrames.isEmpty {
            notes.append("LiDAR evidence contributes blocked/uncertain/missing-view markers from near-field occupancy, dropout, and low support.")
        }
        return notes
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
