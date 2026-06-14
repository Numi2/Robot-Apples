import Foundation

public struct NativeModelInputBundle: Codable, Equatable, Sendable {
    public var featureNames: [String]
    public var sample: RenderedModelSample

    public init(featureNames: [String], sample: RenderedModelSample) {
        self.featureNames = featureNames
        self.sample = sample
    }
}

public struct NativeModelPredictionAdapter: Sendable {
    public var schema: NativeModelAdapterSchema

    public init(schema: NativeModelAdapterSchema) {
        self.schema = schema
    }

    public func inputBundle(for sample: RenderedModelSample) -> NativeModelInputBundle {
        NativeModelInputBundle(featureNames: schema.inputs.map(\.name), sample: sample)
    }

    public func predictions(from outputs: [String: NativeModelOutputValue], tasks: Set<VisionTask>) -> [VisionPrediction] {
        var predictions: [VisionPrediction] = []
        for mapping in schema.predictionMappings where tasks.contains(mapping.visionTask) {
            guard let value = outputs[mapping.outputName] else { continue }
            let label = label(for: value, mapping: mapping)
            let confidence = confidence(for: mapping, outputs: outputs)
            predictions.append(VisionPrediction(
                task: mapping.visionTask,
                label: label,
                confidence: confidence,
                source: "\(schema.runtime.rawValue):\(mapping.outputName)",
                failureKind: failureKind(for: label, outputKind: mapping.outputKind)
            ))
        }
        return predictions
    }

    private func label(for value: NativeModelOutputValue, mapping: ModelAdapterPredictionMapping) -> String {
        switch mapping.outputKind {
        case .classLabel, .failureKind:
            if mapping.outputKind == .failureKind, let score = value.doubleValue {
                return score >= 0.5 ? "failure_detected" : "confident"
            }
            let rawLabel = value.stringValue ?? value.bestLabel ?? "prediction"
            return mapping.labelMap[rawLabel] ?? rawLabel
        case .obstacleProbability:
            return (value.doubleValue ?? 0) >= 0.5 ? "blocked" : "free_path"
        case .freeSpaceProbability:
            return (value.doubleValue ?? 0) >= 0.5 ? "free_path" : "not_free"
        case .localizationUncertainty:
            return (value.doubleValue ?? 0) >= 0.5 ? "uncertain_localization" : "localized"
        case .confidence:
            return "confidence"
        case .segmentationMask:
            return "segmentation"
        }
    }

    private func confidence(for mapping: ModelAdapterPredictionMapping, outputs: [String: NativeModelOutputValue]) -> Double {
        if mapping.outputKind == .confidence {
            return outputs[mapping.outputName]?.doubleValue ?? 0
        }
        if let confidenceOutput = schema.outputs.first(where: { $0.semantic == ModelAdapterOutputKind.confidence.rawValue }),
           let confidence = outputs[confidenceOutput.name]?.doubleValue {
            return min(max(confidence, 0), 1)
        }
        let raw = min(max(outputs[mapping.outputName]?.doubleValue ?? 1, 0), 1)
        if mapping.outputKind == .freeSpaceProbability {
            return raw >= 0.5 ? raw : 1 - raw
        }
        return raw
    }

    private func failureKind(for label: String, outputKind: ModelAdapterOutputKind) -> FailureMarkerKind? {
        if outputKind == .failureKind, let mapped = schema.failureLabels[label] {
            return mapped
        }
        let normalized = label.lowercased()
        return schema.failureLabels.first { normalized.contains($0.key) }?.value
    }
}

public enum NativeModelOutputValue: Codable, Equatable, Sendable {
    case string(String)
    case double(Double)
    case dictionary([String: Double])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .dictionary(let values):
            return values.values.max()
        case .string:
            return nil
        }
    }

    public var bestLabel: String? {
        if case .dictionary(let values) = self {
            return values.max { $0.value < $1.value }?.key
        }
        return nil
    }
}

#if canImport(CoreML)
import CoreML

public final class CoreMLRenderedSampleFeatureProvider: MLFeatureProvider {
    private let sample: RenderedModelSample
    private let schema: NativeModelAdapterSchema
    public let featureNames: Set<String>

    public init(sample: RenderedModelSample, schema: NativeModelAdapterSchema) {
        self.sample = sample
        self.schema = schema
        self.featureNames = Set(schema.inputs.map(\.name))
    }

    public func featureValue(for featureName: String) -> MLFeatureValue? {
        guard let feature = schema.inputs.first(where: { $0.name == featureName }) else {
            return nil
        }
        switch ModelAdapterInputKind(rawValue: feature.semantic) {
        case .image:
            return multiArrayValue(sample.rgbCHW, shape: feature.shape)
        case .depth:
            return multiArrayValue(sample.depthCHW, shape: feature.shape)
        case .visibility:
            return multiArrayValue(sample.visibilityCHW, shape: feature.shape)
        case .renderedFeatures:
            return multiArrayValue(renderedFeatureVector(sample), shape: feature.shape.isEmpty ? [1, 70] : feature.shape)
        case .cameraPose:
            return multiArrayValue(sample.poseVector, shape: feature.shape.isEmpty ? [1, 7] : feature.shape)
        case .intrinsics:
            return multiArrayValue(sample.intrinsicsVector, shape: feature.shape.isEmpty ? [1, 4] : feature.shape)
        case .frameIndex:
            return MLFeatureValue(int64: Int64(sample.frameIndex))
        case .timestamp:
            return MLFeatureValue(double: sample.timestamp)
        case .none:
            if feature.name.localizedCaseInsensitiveContains("path"), let rgbURL = sample.rgbURL {
                return MLFeatureValue(string: rgbURL.path)
            }
            return nil
        }
    }

    private func renderedFeatureVector(_ sample: RenderedModelSample) -> [Float] {
        sample.poseVector
            + sample.intrinsicsVector
            + channelMeans(sample.rgbCHW, channels: 3)
            + channelStandardDeviations(sample.rgbCHW, channels: 3)
            + scalarImageFeatures(sample.depthCHW, highThreshold: 0.82)
            + visibilityFeatures(sample.visibilityCHW)
            + lidarFeatures(sample)
            + structuredGeometryFeatures(sample)
    }

    private func channelMeans(_ values: [Float], channels: Int) -> [Float] {
        guard channels > 0, values.count >= channels else {
            return Array(repeating: 0, count: channels)
        }
        let pixelsPerChannel = max(1, values.count / channels)
        return (0..<channels).map { channel in
            let start = channel * pixelsPerChannel
            let end = min(start + pixelsPerChannel, values.count)
            guard start < end else { return 0 }
            return values[start..<end].reduce(0, +) / Float(end - start)
        }
    }

    private func channelStandardDeviations(_ values: [Float], channels: Int) -> [Float] {
        let means = channelMeans(values, channels: channels)
        let pixelsPerChannel = max(1, values.count / max(channels, 1))
        return (0..<channels).map { channel in
            let start = channel * pixelsPerChannel
            let end = min(start + pixelsPerChannel, values.count)
            guard start < end else { return 0 }
            let mean = means[channel]
            let variance = values[start..<end].reduce(Float(0)) { $0 + pow($1 - mean, 2) } / Float(end - start)
            return sqrt(variance)
        }
    }

    private func scalarImageFeatures(_ values: [Float], highThreshold: Float) -> [Float] {
        guard !values.isEmpty else { return [0, 0, 0] }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(Float(0)) { $0 + pow($1 - mean, 2) } / Float(values.count)
        let highCoverage = Float(values.filter { $0 > highThreshold }.count) / Float(values.count)
        return [mean, sqrt(variance), highCoverage]
    }

    private func visibilityFeatures(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [0, 0, 0, 0] }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(Float(0)) { $0 + pow($1 - mean, 2) } / Float(values.count)
        let lowCoverage = Float(values.filter { $0 < 0.18 }.count) / Float(values.count)
        let highCoverage = Float(values.filter { $0 > 0.65 }.count) / Float(values.count)
        return [mean, sqrt(variance), lowCoverage, highCoverage]
    }

    private func lidarFeatures(_ sample: RenderedModelSample) -> [Float] {
        if sample.lidarFeatureVector.count == 30 {
            return sample.lidarFeatureVector
        }
        return Array(sample.lidarFeatureVector.prefix(30)) + Array(repeating: 0, count: max(0, 30 - sample.lidarFeatureVector.count))
    }

    private func structuredGeometryFeatures(_ sample: RenderedModelSample) -> [Float] {
        if sample.structuredGeometryFeatureVector.count == 16 {
            return sample.structuredGeometryFeatureVector
        }
        return Array(sample.structuredGeometryFeatureVector.prefix(16)) + Array(repeating: 0, count: max(0, 16 - sample.structuredGeometryFeatureVector.count))
    }

    private func multiArrayValue(_ values: [Float], shape: [Int]) -> MLFeatureValue? {
        let resolvedShape = shape.isEmpty ? [values.count] : shape
        do {
            let array = try MLMultiArray(shape: resolvedShape.map(NSNumber.init(value:)), dataType: .float32)
            let count = min(values.count, array.count)
            for index in 0..<count {
                array[index] = NSNumber(value: values[index])
            }
            return MLFeatureValue(multiArray: array)
        } catch {
            return nil
        }
    }
}

public struct CoreMLModelOutputAdapter: Sendable {
    public var schema: NativeModelAdapterSchema

    public init(schema: NativeModelAdapterSchema) {
        self.schema = schema
    }

    public func outputValues(from provider: MLFeatureProvider) -> [String: NativeModelOutputValue] {
        var values: [String: NativeModelOutputValue] = [:]
        for name in provider.featureNames {
            guard let value = provider.featureValue(for: name) else { continue }
            if value.type == .string {
                values[name] = .string(value.stringValue)
                continue
            }
            if value.type == .double {
                values[name] = .double(value.doubleValue)
                continue
            }
            if value.type == .int64 {
                values[name] = .double(Double(value.int64Value))
                continue
            }
            if let dictionary = value.dictionaryValue as? [String: Double] {
                values[name] = .dictionary(dictionary)
                continue
            }
            if let multiArray = value.multiArrayValue, multiArray.count > 0 {
                values[name] = .double(multiArray[0].doubleValue)
                if name == "robot_scene_outputs", multiArray.count >= 4 {
                    values["free_space_probability"] = .double(multiArray[0].doubleValue)
                    values["obstacle_probability"] = .double(multiArray[1].doubleValue)
                    values["localization_uncertainty"] = .double(multiArray[2].doubleValue)
                    values["failure_kind_score"] = .double(multiArray[3].doubleValue)
                }
            }
        }
        return values
    }
}
#endif
