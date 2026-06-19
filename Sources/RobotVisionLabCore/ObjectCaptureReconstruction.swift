import Foundation

#if os(macOS)
import RealityKit
#endif

public struct ObjectCaptureReconstructionRequest: Codable, Equatable, Sendable {
    public var imageSet: ObjectCaptureImageSet
    public var outputURL: URL
    public var detail: ObjectCaptureDetail
    public var featureSensitivity: ObjectCaptureFeatureSensitivity
    public var isObjectMaskingEnabled: Bool

    public init(
        imageSet: ObjectCaptureImageSet,
        outputURL: URL,
        detail: ObjectCaptureDetail = .medium,
        featureSensitivity: ObjectCaptureFeatureSensitivity = .normal,
        isObjectMaskingEnabled: Bool = true
    ) {
        self.imageSet = imageSet
        self.outputURL = outputURL
        self.detail = detail
        self.featureSensitivity = featureSensitivity
        self.isObjectMaskingEnabled = isObjectMaskingEnabled
    }
}

public enum ObjectCaptureFeatureSensitivity: String, Codable, Equatable, Sendable {
    case normal
    case high
}

public enum ObjectCaptureReconstructionStatus: String, Codable, Equatable, Sendable {
    case completed
}

public struct ObjectCaptureReconstructionProgressEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var fractionComplete: Double?
    public var stage: String?
    public var message: String

    public init(
        timestamp: Date = Date(),
        fractionComplete: Double? = nil,
        stage: String? = nil,
        message: String
    ) {
        self.timestamp = timestamp
        self.fractionComplete = fractionComplete
        self.stage = stage
        self.message = message
    }
}

public struct ObjectCaptureReconstructionReport: Codable, Equatable, Sendable {
    public var imageSetID: String
    public var label: String?
    public var imagesDirectoryURL: URL
    public var outputURL: URL
    public var detail: ObjectCaptureDetail
    public var status: ObjectCaptureReconstructionStatus
    public var completedAt: Date
    public var inputImageCount: Int
    public var progressEvents: [ObjectCaptureReconstructionProgressEvent]
    public var warnings: [String]

    public init(
        imageSetID: String,
        label: String?,
        imagesDirectoryURL: URL,
        outputURL: URL,
        detail: ObjectCaptureDetail,
        status: ObjectCaptureReconstructionStatus = .completed,
        completedAt: Date = Date(),
        inputImageCount: Int,
        progressEvents: [ObjectCaptureReconstructionProgressEvent],
        warnings: [String]
    ) {
        self.imageSetID = imageSetID
        self.label = label
        self.imagesDirectoryURL = imagesDirectoryURL
        self.outputURL = outputURL
        self.detail = detail
        self.status = status
        self.completedAt = completedAt
        self.inputImageCount = inputImageCount
        self.progressEvents = progressEvents
        self.warnings = warnings
    }
}

public struct ObjectCaptureReconstructionPlanner: Sendable {
    public init() {}

    public func makeRequests(
        for importedCapture: RobotCaptureImport,
        outputDirectory: URL,
        detail: ObjectCaptureDetail? = nil
    ) -> [ObjectCaptureReconstructionRequest] {
        let selectedDetail = detail ?? importedCapture.captureBundle.capturePlan?.objectCapture?.preferredDetail ?? .medium
        return importedCapture.captureBundle.objectCaptureImageSets.enumerated().map { index, imageSet in
            var resolvedImageSet = imageSet
            resolvedImageSet.imagesDirectoryURL = resolve(imageSet.imagesDirectoryURL, relativeTo: importedCapture.packageRoot)
            resolvedImageSet.checkpointDirectoryURL = imageSet.checkpointDirectoryURL.map {
                resolve($0, relativeTo: importedCapture.packageRoot)
            }
            return ObjectCaptureReconstructionRequest(
                imageSet: resolvedImageSet,
                outputURL: outputDirectory
                    .appendingPathComponent(safeOutputName(for: imageSet, index: index))
                    .appendingPathExtension("usdz"),
                detail: selectedDetail
            )
        }
    }

    private func resolve(_ url: URL, relativeTo packageRoot: URL) -> URL {
        PackageURLTools.resolve(url, relativeTo: packageRoot)
    }

    private func safeOutputName(for imageSet: ObjectCaptureImageSet, index: Int) -> String {
        let fallback = "object-\(index + 1)"
        let rawName = imageSet.label ?? imageSet.id
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = (rawName.isEmpty ? fallback : rawName).unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? fallback : sanitized
    }
}

public struct ObjectCaptureReconstructor: Sendable {
    public init() {}

    public func reconstruct(
        _ request: ObjectCaptureReconstructionRequest,
        progress: (@Sendable (ObjectCaptureReconstructionProgressEvent) -> Void)? = nil
    ) async throws -> ObjectCaptureReconstructionReport {
        #if os(macOS)
        guard #available(macOS 14.0, *) else {
            throw ObjectCaptureReconstructionError.unsupportedPlatform("Photogrammetry reconstruction requires macOS 14 or newer.")
        }
        return try await reconstructOnMac(request, progress: progress)
        #else
        throw ObjectCaptureReconstructionError.unsupportedPlatform("Photogrammetry reconstruction is only available on macOS.")
        #endif
    }
}

public enum ObjectCaptureReconstructionError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case unsupportedPlatform(String)
    case noSupportedImages(URL)
    case cancelled
    case failed(String)
    case noModelOutput(URL)

    public var errorDescription: String? {
        description
    }

    public var description: String {
        switch self {
        case .unsupportedPlatform(let message):
            message
        case .noSupportedImages(let url):
            "Object Capture image set contains no supported images: \(url.path)"
        case .cancelled:
            "Object Capture reconstruction was cancelled."
        case .failed(let message):
            "Object Capture reconstruction failed: \(message)"
        case .noModelOutput(let url):
            "Object Capture reconstruction finished without writing a model at \(url.path)."
        }
    }
}

#if os(macOS)
@available(macOS 14.0, *)
private func reconstructOnMac(
    _ request: ObjectCaptureReconstructionRequest,
    progress: (@Sendable (ObjectCaptureReconstructionProgressEvent) -> Void)?
) async throws -> ObjectCaptureReconstructionReport {
    let inputImageCount = countSupportedImages(in: request.imageSet.imagesDirectoryURL)
    guard inputImageCount > 0 else {
        throw ObjectCaptureReconstructionError.noSupportedImages(request.imageSet.imagesDirectoryURL)
    }

    let fileManager = FileManager.default
    try fileManager.createDirectory(at: request.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: request.outputURL.path) {
        try fileManager.removeItem(at: request.outputURL)
    }

    var configuration = PhotogrammetrySession.Configuration()
    configuration.isObjectMaskingEnabled = request.isObjectMaskingEnabled
    configuration.sampleOrdering = .unordered
    configuration.featureSensitivity = request.featureSensitivity.photogrammetryValue
    if let checkpointDirectoryURL = request.imageSet.checkpointDirectoryURL {
        try fileManager.createDirectory(at: checkpointDirectoryURL, withIntermediateDirectories: true)
        configuration.checkpointDirectory = checkpointDirectoryURL
    }

    let session = try PhotogrammetrySession(input: request.imageSet.imagesDirectoryURL, configuration: configuration)
    let modelRequest = PhotogrammetrySession.Request.modelFile(
        url: request.outputURL,
        detail: request.detail.photogrammetryValue
    )
    var events: [ObjectCaptureReconstructionProgressEvent] = []
    var warnings: [String] = []
    var completedModelURL: URL?

    func record(_ event: ObjectCaptureReconstructionProgressEvent) {
        events.append(event)
        progress?(event)
    }

    record(ObjectCaptureReconstructionProgressEvent(message: "Started Object Capture reconstruction."))
    try session.process(requests: [modelRequest])

    outputLoop: for try await output in session.outputs {
        switch output {
        case .inputComplete:
            record(ObjectCaptureReconstructionProgressEvent(message: "Input images loaded."))
        case .requestProgress(_, let fractionComplete):
            record(ObjectCaptureReconstructionProgressEvent(
                fractionComplete: fractionComplete,
                message: "Reconstruction progress \(Int(fractionComplete * 100))%."
            ))
        case .requestProgressInfo(_, let progressInfo):
            record(ObjectCaptureReconstructionProgressEvent(
                stage: progressInfo.processingStage?.description,
                message: progressInfo.processingStage.map { "Processing stage: \($0.description)." } ?? "Processing."
            ))
        case .requestComplete(_, let result):
            if case .modelFile(let url) = result {
                completedModelURL = url
                record(ObjectCaptureReconstructionProgressEvent(
                    fractionComplete: 1,
                    message: "Reconstruction wrote \(url.lastPathComponent)."
                ))
            }
        case .requestError(_, let error):
            throw ObjectCaptureReconstructionError.failed(error.localizedDescription)
        case .processingComplete:
            record(ObjectCaptureReconstructionProgressEvent(fractionComplete: 1, message: "Processing complete."))
            break outputLoop
        case .processingCancelled:
            throw ObjectCaptureReconstructionError.cancelled
        case .invalidSample(let id, let reason):
            warnings.append("Invalid Object Capture sample \(id): \(reason)")
        case .skippedSample(let id):
            warnings.append("Skipped Object Capture sample \(id).")
        case .automaticDownsampling:
            warnings.append("Object Capture automatically downsampled input images.")
        case .stitchingIncomplete:
            warnings.append("Object Capture reported incomplete stitching.")
        @unknown default:
            warnings.append("Object Capture emitted an unknown progress event.")
        }
    }

    let outputURL = completedModelURL ?? request.outputURL
    guard fileManager.fileExists(atPath: outputURL.path) else {
        throw ObjectCaptureReconstructionError.noModelOutput(outputURL)
    }

    return ObjectCaptureReconstructionReport(
        imageSetID: request.imageSet.id,
        label: request.imageSet.label,
        imagesDirectoryURL: request.imageSet.imagesDirectoryURL,
        outputURL: outputURL,
        detail: request.detail,
        inputImageCount: inputImageCount,
        progressEvents: events,
        warnings: warnings
    )
}

@available(macOS 14.0, *)
private extension ObjectCaptureDetail {
    var photogrammetryValue: PhotogrammetrySession.Request.Detail {
        switch self {
        case .preview:
            return .preview
        case .reduced:
            return .reduced
        case .medium:
            return .medium
        case .full:
            return .full
        case .raw:
            return .raw
        }
    }
}

@available(macOS 14.0, *)
private extension ObjectCaptureFeatureSensitivity {
    var photogrammetryValue: PhotogrammetrySession.Configuration.FeatureSensitivity {
        switch self {
        case .normal:
            return .normal
        case .high:
            return .high
        }
    }
}

@available(macOS 14.0, *)
private extension PhotogrammetrySession.Output.ProcessingStage {
    var description: String {
        switch self {
        case .preProcessing:
            return "pre-processing"
        case .imageAlignment:
            return "image alignment"
        case .pointCloudGeneration:
            return "point cloud generation"
        case .meshGeneration:
            return "mesh generation"
        case .textureMapping:
            return "texture mapping"
        case .optimization:
            return "optimization"
        @unknown default:
            return "unknown"
        }
    }
}
#endif

private func countSupportedImages(in directoryURL: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return 0
    }
    return enumerator.compactMap { item -> URL? in
        guard let url = item as? URL else { return nil }
        guard isSupportedObjectCaptureImage(url) else { return nil }
        let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        return isRegularFile ? url : nil
    }.count
}

private func isSupportedObjectCaptureImage(_ url: URL) -> Bool {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff":
        return true
    default:
        return false
    }
}
