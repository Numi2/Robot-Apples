import Foundation

public enum ModelAdapterInputKind: String, Codable, CaseIterable, Sendable {
    case image
    case depth
    case visibility
    case cameraPose
    case intrinsics
    case renderedFeatures
    case frameIndex
    case timestamp
}

public enum ModelAdapterOutputKind: String, Codable, CaseIterable, Sendable {
    case classLabel
    case confidence
    case obstacleProbability
    case freeSpaceProbability
    case localizationUncertainty
    case segmentationMask
    case failureKind
}

public struct ModelAdapterFeature: Codable, Equatable, Sendable {
    public var name: String
    public var kind: String
    public var shape: [Int]
    public var semantic: String

    public init(name: String, kind: String, shape: [Int] = [], semantic: String) {
        self.name = name
        self.kind = kind
        self.shape = shape
        self.semantic = semantic
    }
}

public struct ModelAdapterPredictionMapping: Codable, Equatable, Sendable {
    public var outputName: String
    public var outputKind: ModelAdapterOutputKind
    public var visionTask: VisionTask
    public var labelMap: [String: String]

    public init(
        outputName: String,
        outputKind: ModelAdapterOutputKind,
        visionTask: VisionTask,
        labelMap: [String: String] = [:]
    ) {
        self.outputName = outputName
        self.outputKind = outputKind
        self.visionTask = visionTask
        self.labelMap = labelMap
    }
}

public struct NativeModelAdapterSchema: Codable, Equatable, Sendable {
    public var id: String
    public var runtime: LocalModelRuntime
    public var inputs: [ModelAdapterFeature]
    public var outputs: [ModelAdapterFeature]
    public var predictionMappings: [ModelAdapterPredictionMapping]
    public var failureLabels: [String: FailureMarkerKind]

    public init(
        id: String,
        runtime: LocalModelRuntime,
        inputs: [ModelAdapterFeature],
        outputs: [ModelAdapterFeature],
        predictionMappings: [ModelAdapterPredictionMapping],
        failureLabels: [String: FailureMarkerKind] = [
            "blocked": .blockedPrediction,
            "uncertain": .uncertainLocalization,
            "missing_view": .missingTrainingViews,
            "ambiguous": .visualAmbiguity,
            "low_texture": .lowTexture,
            "bad_lighting": .badLighting,
            "failure_detected": .uncertainLocalization,
            "confident": .confident
        ]
    ) {
        self.id = id
        self.runtime = runtime
        self.inputs = inputs
        self.outputs = outputs
        self.predictionMappings = predictionMappings
        self.failureLabels = failureLabels
    }

    public static func defaultCoreMLVisionSchema() -> NativeModelAdapterSchema {
        NativeModelAdapterSchema(
            id: "coreml-robot-vision-default",
            runtime: .coreML,
            inputs: [
                ModelAdapterFeature(name: "rgb", kind: "Float32", shape: [1, 3, 720, 1280], semantic: ModelAdapterInputKind.image.rawValue),
                ModelAdapterFeature(name: "depth", kind: "Float32", shape: [1, 1, 720, 1280], semantic: ModelAdapterInputKind.depth.rawValue),
                ModelAdapterFeature(name: "pose", kind: "Float32", shape: [1, 7], semantic: ModelAdapterInputKind.cameraPose.rawValue),
                ModelAdapterFeature(name: "intrinsics", kind: "Float32", shape: [1, 4], semantic: ModelAdapterInputKind.intrinsics.rawValue),
                ModelAdapterFeature(name: "frameIndex", kind: "Int64", semantic: ModelAdapterInputKind.frameIndex.rawValue),
                ModelAdapterFeature(name: "timestamp", kind: "Double", semantic: ModelAdapterInputKind.timestamp.rawValue)
            ],
            outputs: [
                ModelAdapterFeature(name: "label", kind: "String", semantic: ModelAdapterOutputKind.classLabel.rawValue),
                ModelAdapterFeature(name: "confidence", kind: "Double", semantic: ModelAdapterOutputKind.confidence.rawValue),
                ModelAdapterFeature(name: "obstacle_probability", kind: "Double", semantic: ModelAdapterOutputKind.obstacleProbability.rawValue),
                ModelAdapterFeature(name: "free_space_probability", kind: "Double", semantic: ModelAdapterOutputKind.freeSpaceProbability.rawValue),
                ModelAdapterFeature(name: "localization_uncertainty", kind: "Double", semantic: ModelAdapterOutputKind.localizationUncertainty.rawValue),
                ModelAdapterFeature(name: "failure_kind", kind: "String", semantic: ModelAdapterOutputKind.failureKind.rawValue)
            ],
            predictionMappings: [
                ModelAdapterPredictionMapping(outputName: "label", outputKind: .classLabel, visionTask: .failureCaseDetection),
                ModelAdapterPredictionMapping(outputName: "obstacle_probability", outputKind: .obstacleProbability, visionTask: .obstacleDetection),
                ModelAdapterPredictionMapping(outputName: "free_space_probability", outputKind: .freeSpaceProbability, visionTask: .obstacleDetection),
                ModelAdapterPredictionMapping(outputName: "localization_uncertainty", outputKind: .localizationUncertainty, visionTask: .failureCaseDetection),
                ModelAdapterPredictionMapping(outputName: "failure_kind", outputKind: .failureKind, visionTask: .failureCaseDetection)
            ]
        )
    }

    public static func defaultMLXTrainingSchema() -> NativeModelAdapterSchema {
        NativeModelAdapterSchema(
            id: "mlx-robot-vision-training",
            runtime: .mlx,
            inputs: [
                ModelAdapterFeature(name: "rgb", kind: "Float32", shape: [1, 3, 720, 1280], semantic: ModelAdapterInputKind.image.rawValue),
                ModelAdapterFeature(name: "depth", kind: "Float32", shape: [1, 1, 720, 1280], semantic: ModelAdapterInputKind.depth.rawValue),
                ModelAdapterFeature(name: "visibility", kind: "Float32", shape: [1, 1, 720, 1280], semantic: ModelAdapterInputKind.visibility.rawValue),
                ModelAdapterFeature(name: "scene_features", kind: "Float32", shape: [1, 30], semantic: ModelAdapterInputKind.renderedFeatures.rawValue),
                ModelAdapterFeature(name: "pose", kind: "Float32", shape: [1, 7], semantic: ModelAdapterInputKind.cameraPose.rawValue),
                ModelAdapterFeature(name: "intrinsics", kind: "Float32", shape: [1, 4], semantic: ModelAdapterInputKind.intrinsics.rawValue)
            ],
            outputs: [
                ModelAdapterFeature(name: "free_space_probability", kind: "Float32", shape: [1], semantic: ModelAdapterOutputKind.freeSpaceProbability.rawValue),
                ModelAdapterFeature(name: "obstacle_probability", kind: "Float32", shape: [1], semantic: ModelAdapterOutputKind.obstacleProbability.rawValue),
                ModelAdapterFeature(name: "localization_uncertainty", kind: "Float32", shape: [1], semantic: ModelAdapterOutputKind.localizationUncertainty.rawValue),
                ModelAdapterFeature(name: "failure_kind", kind: "String", semantic: ModelAdapterOutputKind.failureKind.rawValue)
            ],
            predictionMappings: [
                ModelAdapterPredictionMapping(outputName: "free_space_probability", outputKind: .freeSpaceProbability, visionTask: .obstacleDetection),
                ModelAdapterPredictionMapping(outputName: "obstacle_probability", outputKind: .obstacleProbability, visionTask: .obstacleDetection),
                ModelAdapterPredictionMapping(outputName: "localization_uncertainty", outputKind: .localizationUncertainty, visionTask: .failureCaseDetection),
                ModelAdapterPredictionMapping(outputName: "failure_kind", outputKind: .failureKind, visionTask: .failureCaseDetection)
            ]
        )
    }
}

public struct NativeModelAdapterSchemaWriter: Sendable {
    public init() {}

    public func write(_ schema: NativeModelAdapterSchema, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(schema).write(to: outputURL)
    }
}

#if canImport(CoreML)
import CoreML

public struct CoreMLModelSchemaInspector: Sendable {
    public init() {}

    public func inspect(modelURL: URL, id: String? = nil) throws -> NativeModelAdapterSchema {
        let model = try MLModel(contentsOf: modelURL)
        let inputs = model.modelDescription.inputDescriptionsByName.map { name, description in
            ModelAdapterFeature(
                name: name,
                kind: String(describing: description.type),
                shape: [],
                semantic: semanticForInput(name)
            )
        }.sorted { $0.name < $1.name }
        let outputs = model.modelDescription.outputDescriptionsByName.map { name, description in
            ModelAdapterFeature(
                name: name,
                kind: String(describing: description.type),
                shape: [],
                semantic: semanticForOutput(name)
            )
        }.sorted { $0.name < $1.name }
        let expandedOutputs = expandedOutputFeatures(outputs)
        let mappings = expandedOutputs.map {
            ModelAdapterPredictionMapping(
                outputName: $0.name,
                outputKind: outputKind(for: $0.semantic),
                visionTask: visionTask(for: $0.semantic)
            )
        }
        return NativeModelAdapterSchema(
            id: id ?? modelURL.deletingPathExtension().lastPathComponent,
            runtime: .coreML,
            inputs: inputs,
            outputs: expandedOutputs,
            predictionMappings: mappings.isEmpty ? NativeModelAdapterSchema.defaultCoreMLVisionSchema().predictionMappings : mappings
        )
    }

    private func expandedOutputFeatures(_ outputs: [ModelAdapterFeature]) -> [ModelAdapterFeature] {
        guard outputs.contains(where: { $0.name == "robot_scene_outputs" }) else {
            return outputs
        }
        return outputs + [
            ModelAdapterFeature(name: "free_space_probability", kind: "Double", shape: [1], semantic: ModelAdapterOutputKind.freeSpaceProbability.rawValue),
            ModelAdapterFeature(name: "obstacle_probability", kind: "Double", shape: [1], semantic: ModelAdapterOutputKind.obstacleProbability.rawValue),
            ModelAdapterFeature(name: "localization_uncertainty", kind: "Double", shape: [1], semantic: ModelAdapterOutputKind.localizationUncertainty.rawValue),
            ModelAdapterFeature(name: "failure_kind_score", kind: "Double", shape: [1], semantic: ModelAdapterOutputKind.failureKind.rawValue)
        ]
    }

    private func semanticForInput(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("scene_features") || lower.contains("scenefeatures") {
            return ModelAdapterInputKind.renderedFeatures.rawValue
        }
        if lower.contains("image") || lower.contains("rgb") { return ModelAdapterInputKind.image.rawValue }
        if lower.contains("depth") { return ModelAdapterInputKind.depth.rawValue }
        if lower.contains("visibility") { return ModelAdapterInputKind.visibility.rawValue }
        if lower.contains("pose") { return ModelAdapterInputKind.cameraPose.rawValue }
        if lower.contains("intrinsic") { return ModelAdapterInputKind.intrinsics.rawValue }
        if lower.contains("time") { return ModelAdapterInputKind.timestamp.rawValue }
        if lower.contains("index") { return ModelAdapterInputKind.frameIndex.rawValue }
        return "unknown"
    }

    private func semanticForOutput(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("confidence") { return ModelAdapterOutputKind.confidence.rawValue }
        if lower.contains("obstacle") { return ModelAdapterOutputKind.obstacleProbability.rawValue }
        if lower.contains("free") { return ModelAdapterOutputKind.freeSpaceProbability.rawValue }
        if lower.contains("uncertain") { return ModelAdapterOutputKind.localizationUncertainty.rawValue }
        if lower.contains("segment") { return ModelAdapterOutputKind.segmentationMask.rawValue }
        if lower.contains("failure") { return ModelAdapterOutputKind.failureKind.rawValue }
        return ModelAdapterOutputKind.classLabel.rawValue
    }

    private func outputKind(for semantic: String) -> ModelAdapterOutputKind {
        ModelAdapterOutputKind(rawValue: semantic) ?? .classLabel
    }

    private func visionTask(for semantic: String) -> VisionTask {
        switch ModelAdapterOutputKind(rawValue: semantic) {
        case .obstacleProbability, .freeSpaceProbability:
            return .obstacleDetection
        case .segmentationMask:
            return .segmentation
        case .failureKind, .localizationUncertainty:
            return .failureCaseDetection
        default:
            return .navigationTargetDetection
        }
    }
}
#else
public struct CoreMLModelSchemaInspector: Sendable {
    public init() {}

    public func inspect(modelURL: URL, id: String? = nil) throws -> NativeModelAdapterSchema {
        throw ModelEvaluationError.runtimeUnavailable(.coreML)
    }
}
#endif
