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
    case baseline
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

    public init(task: VisionTask, label: String, confidence: Double, source: String) {
        self.task = task
        self.label = label
        self.confidence = confidence
        self.source = source
    }
}

public struct EvaluationSummary: Codable, Equatable, Sendable {
    public var frameCount: Int
    public var warningCount: Int
    public var taskCounts: [VisionTask: Int]

    public init(frameCount: Int, warningCount: Int, taskCounts: [VisionTask: Int]) {
        self.frameCount = frameCount
        self.warningCount = warningCount
        self.taskCounts = taskCounts
    }
}

public struct BaselineDatasetEvaluator: Sendable {
    public init() {}

    public func evaluate(request: ModelEvaluationRequest, manifest: DatasetManifest, generatedAt: Date = Date()) -> ModelEvaluationReport {
        let frameResults = manifest.frames.map { frame in
            evaluate(frame: frame, requestedTasks: request.tasks)
        }
        let taskCounts = Dictionary(grouping: frameResults.flatMap(\.predictions), by: \.task)
            .mapValues(\.count)
        return ModelEvaluationReport(
            request: request,
            generatedAt: generatedAt,
            frameResults: frameResults,
            summary: EvaluationSummary(
                frameCount: frameResults.count,
                warningCount: frameResults.reduce(0) { $0 + $1.warnings.count },
                taskCounts: taskCounts
            )
        )
    }

    private func evaluate(frame: DatasetFrame, requestedTasks: Set<VisionTask>) -> FrameEvaluationResult {
        var predictions: [VisionPrediction] = []
        var warnings: [String] = []
        let rgbURL = frame.productURL(for: .rgb)

        if rgbURL == nil {
            warnings.append("Frame has no RGB product URL.")
        }
        if requestedTasks.contains(.navigationTargetDetection) {
            predictions.append(VisionPrediction(
                task: .navigationTargetDetection,
                label: frame.navigationTarget?.label ?? "none",
                confidence: frame.navigationTarget == nil ? 0 : 1,
                source: "manifest_navigation_target"
            ))
        }
        if requestedTasks.contains(.obstacleDetection) {
            predictions.append(VisionPrediction(
                task: .obstacleDetection,
                label: frame.productURL(for: .obstacleMask) == nil ? "unknown" : "obstacle_mask_available",
                confidence: frame.productURL(for: .obstacleMask) == nil ? 0 : 0.5,
                source: "dataset_product_presence"
            ))
        }
        if requestedTasks.contains(.segmentation) {
            predictions.append(VisionPrediction(
                task: .segmentation,
                label: frame.productURL(for: .segmentation) == nil ? "missing" : "segmentation_available",
                confidence: frame.productURL(for: .segmentation) == nil ? 0 : 0.5,
                source: "dataset_product_presence"
            ))
        }
        if requestedTasks.contains(.failureCaseDetection) {
            let degraded = frame.augmentations.contains { augmentation in
                if case .motionBlur = augmentation { return true }
                if case .compressionJPEG = augmentation { return true }
                return false
            }
            predictions.append(VisionPrediction(
                task: .failureCaseDetection,
                label: degraded ? "degraded_camera_frame" : "nominal",
                confidence: degraded ? 0.8 : 0.4,
                source: "augmentation_metadata"
            ))
        }

        return FrameEvaluationResult(frameIndex: frame.index, rgbURL: rgbURL, predictions: predictions, warnings: warnings)
    }
}

public struct EvaluationReportWriter: Sendable {
    public init() {}

    public func write(_ report: ModelEvaluationReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
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
        let frameResults = manifest.frames.map { frame in
            evaluate(frame: frame, requestedTasks: request.tasks, model: model)
        }
        return ModelEvaluationReport(
            request: request,
            generatedAt: generatedAt,
            frameResults: frameResults,
            summary: makeSummary(frameResults)
        )
    }

    private func evaluate(frame: DatasetFrame, requestedTasks: Set<VisionTask>, model: MLModel) -> FrameEvaluationResult {
        var predictions: [VisionPrediction] = []
        var warnings: [String] = []
        let rgbURL = frame.productURL(for: .rgb)
        guard let rgbURL else {
            return FrameEvaluationResult(frameIndex: frame.index, rgbURL: nil, predictions: [], warnings: ["Frame has no RGB product URL."])
        }

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "imagePath": MLFeatureValue(string: rgbURL.path),
                "frameIndex": MLFeatureValue(int64: Int64(frame.index)),
                "timestamp": MLFeatureValue(double: frame.timestamp)
            ])
            let output = try model.prediction(from: input)
            let label = output.featureNames.compactMap { output.featureValue(for: $0)?.stringValue }.first ?? "prediction"
            for task in requestedTasks {
                predictions.append(VisionPrediction(task: task, label: label, confidence: 1.0, source: "coreml:\(model.modelDescription.metadata[.creatorDefinedKey] ?? "model")"))
            }
        } catch {
            warnings.append("Core ML prediction failed for frame \(frame.index): \(error.localizedDescription)")
        }

        return FrameEvaluationResult(frameIndex: frame.index, rgbURL: rgbURL, predictions: predictions, warnings: warnings)
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

public struct MLXEvaluationJob: Codable, Equatable, Sendable {
    public var request: ModelEvaluationRequest
    public var datasetManifestURL: URL
    public var outputReportURL: URL
    public var executableURL: URL
    public var arguments: [String]

    public init(
        request: ModelEvaluationRequest,
        datasetManifestURL: URL,
        outputReportURL: URL,
        executableURL: URL,
        arguments: [String]
    ) {
        self.request = request
        self.datasetManifestURL = datasetManifestURL
        self.outputReportURL = outputReportURL
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public struct MLXEvaluationProcessReport: Codable, Equatable, Sendable {
    public var job: MLXEvaluationJob
    public var startedAt: Date
    public var finishedAt: Date
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String
    public var producedReportURL: URL?

    public init(
        job: MLXEvaluationJob,
        startedAt: Date,
        finishedAt: Date,
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        producedReportURL: URL? = nil
    ) {
        self.job = job
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.producedReportURL = producedReportURL
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
    return EvaluationSummary(
        frameCount: frameResults.count,
        warningCount: frameResults.reduce(0) { $0 + $1.warnings.count },
        taskCounts: taskCounts
    )
}
