import Foundation
import ImageIO
import simd
import UniformTypeIdentifiers

public enum SplatOptimizerProfile: String, Codable, Equatable, Sendable {
    case mlxRayDepthSupervised
    case productionGSplatSplatfacto
}

public struct ProductionSplatDatasetRequirements: Codable, Equatable, Sendable {
    public var minTrainingFrameCount: Int
    public var minValidationFrameCount: Int
    public var minTotalFrameCount: Int
    public var requiresValidationSplit: Bool

    public init(
        minTrainingFrameCount: Int = 2,
        minValidationFrameCount: Int = 1,
        minTotalFrameCount: Int = 3,
        requiresValidationSplit: Bool = true
    ) {
        self.minTrainingFrameCount = max(minTrainingFrameCount, 1)
        self.minValidationFrameCount = max(minValidationFrameCount, 0)
        self.requiresValidationSplit = requiresValidationSplit
        let splitMinimum = self.minTrainingFrameCount + (requiresValidationSplit ? self.minValidationFrameCount : 0)
        self.minTotalFrameCount = max(minTotalFrameCount, splitMinimum)
    }

    public static let production = ProductionSplatDatasetRequirements()

    public static let skipEvaluation = ProductionSplatDatasetRequirements(
        minTrainingFrameCount: 2,
        minValidationFrameCount: 0,
        minTotalFrameCount: 2,
        requiresValidationSplit: false
    )
}

public struct SplatOptimizationStage: Codable, Equatable, Sendable {
    public var name: String
    public var purpose: String
    public var startStep: Int
    public var endStep: Int
    public var settings: [String: String]

    public init(name: String, purpose: String, startStep: Int, endStep: Int, settings: [String: String]) {
        self.name = name
        self.purpose = purpose
        self.startStep = startStep
        self.endStep = endStep
        self.settings = settings
    }
}

public struct SplatOptimizationPlan: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var profile: SplatOptimizerProfile
    public var trainer: String
    public var datasetURL: URL
    public var transformsJSONURL: URL
    public var initialPointCloudURL: URL?
    public var runnerURL: URL
    public var checkpointDirectoryURL: URL
    public var exportDirectoryURL: URL
    public var targetOutputURL: URL
    public var recommendedCommand: [String]
    public var optimizationStages: [SplatOptimizationStage]
    public var requiredCapabilities: [String]
    public var qualityGates: [String]
    public var notes: [String]

    public init(
        schemaVersion: String = "splat-optimization-plan-v1",
        profile: SplatOptimizerProfile,
        trainer: String,
        datasetURL: URL,
        transformsJSONURL: URL,
        initialPointCloudURL: URL? = nil,
        runnerURL: URL,
        checkpointDirectoryURL: URL,
        exportDirectoryURL: URL,
        targetOutputURL: URL,
        recommendedCommand: [String],
        optimizationStages: [SplatOptimizationStage],
        requiredCapabilities: [String],
        qualityGates: [String],
        notes: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.trainer = trainer
        self.datasetURL = datasetURL
        self.transformsJSONURL = transformsJSONURL
        self.initialPointCloudURL = initialPointCloudURL
        self.runnerURL = runnerURL
        self.checkpointDirectoryURL = checkpointDirectoryURL
        self.exportDirectoryURL = exportDirectoryURL
        self.targetOutputURL = targetOutputURL
        self.recommendedCommand = recommendedCommand
        self.optimizationStages = optimizationStages
        self.requiredCapabilities = requiredCapabilities
        self.qualityGates = qualityGates
        self.notes = notes
    }
}

public struct SplatTrainingPackageManifest: Codable, Equatable, Sendable {
    public var id: String
    public var sourceManifestURL: URL
    public var frameIndexURL: URL
    public var depthPriorIndexURL: URL?
    public var trainScriptURL: URL
    public var optimizerProfile: SplatOptimizerProfile?
    public var optimizerPlanURL: URL?
    public var productionDatasetURL: URL?
    public var nerfstudioTransformsURL: URL?
    public var productionPointCloudURL: URL?
    public var productionRunnerURL: URL?
    public var checkpointDirectoryURL: URL?
    public var exportedModelDirectoryURL: URL?
    public var outputURL: URL
    public var frameCount: Int
    public var lidarFrameCount: Int
    public var trainingFrameCount: Int
    public var validationFrameCount: Int
    public var calibratedFrameCount: Int
    public var notes: [String]

    public init(
        id: String,
        sourceManifestURL: URL,
        frameIndexURL: URL,
        depthPriorIndexURL: URL? = nil,
        trainScriptURL: URL,
        optimizerProfile: SplatOptimizerProfile? = nil,
        optimizerPlanURL: URL? = nil,
        productionDatasetURL: URL? = nil,
        nerfstudioTransformsURL: URL? = nil,
        productionPointCloudURL: URL? = nil,
        productionRunnerURL: URL? = nil,
        checkpointDirectoryURL: URL? = nil,
        exportedModelDirectoryURL: URL? = nil,
        outputURL: URL,
        frameCount: Int,
        lidarFrameCount: Int,
        trainingFrameCount: Int,
        validationFrameCount: Int,
        calibratedFrameCount: Int,
        notes: [String]
    ) {
        self.id = id
        self.sourceManifestURL = sourceManifestURL
        self.frameIndexURL = frameIndexURL
        self.depthPriorIndexURL = depthPriorIndexURL
        self.trainScriptURL = trainScriptURL
        self.optimizerProfile = optimizerProfile
        self.optimizerPlanURL = optimizerPlanURL
        self.productionDatasetURL = productionDatasetURL
        self.nerfstudioTransformsURL = nerfstudioTransformsURL
        self.productionPointCloudURL = productionPointCloudURL
        self.productionRunnerURL = productionRunnerURL
        self.checkpointDirectoryURL = checkpointDirectoryURL
        self.exportedModelDirectoryURL = exportedModelDirectoryURL
        self.outputURL = outputURL
        self.frameCount = frameCount
        self.lidarFrameCount = lidarFrameCount
        self.trainingFrameCount = trainingFrameCount
        self.validationFrameCount = validationFrameCount
        self.calibratedFrameCount = calibratedFrameCount
        self.notes = notes
    }
}

public struct SplatTrainingPackageBuilder: Sendable {
    public var productionRequirements: ProductionSplatDatasetRequirements

    public init(productionRequirements: ProductionSplatDatasetRequirements = .production) {
        self.productionRequirements = productionRequirements
    }

    public func writePackage(
        job: SplatTrainingJob,
        manifestURL: URL,
        outputDirectory: URL
    ) throws -> SplatTrainingPackageManifest {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let manifestRoot = manifestURL.deletingLastPathComponent()
        let resolvedOutputURL = resolve(job.manifest.expectedOutput.targetURL, relativeTo: manifestRoot)
        try validateTrainingInputs(job.manifest, relativeTo: manifestRoot, requirements: productionRequirements)
        let frameIndexURL = outputDirectory.appendingPathComponent("capture_splat_frames.jsonl")
        let depthPriorIndexURL = outputDirectory.appendingPathComponent("capture_lidar_depth_priors.jsonl")
        let trainScriptURL = outputDirectory.appendingPathComponent("train_capture_splat_mlx.py")
        let productionDatasetURL = outputDirectory.appendingPathComponent("production_gsplat_dataset", isDirectory: true)
        let nerfstudioTransformsURL = productionDatasetURL.appendingPathComponent("transforms.json")
        let productionPointCloudURL = productionDatasetURL.appendingPathComponent("sparse_pc.ply")
        let productionRunnerURL = outputDirectory.appendingPathComponent("run_production_splat_optimizer.py")
        let optimizerPlanURL = outputDirectory.appendingPathComponent("production_splat_optimization_plan.json")
        let checkpointDirectoryURL = outputDirectory.appendingPathComponent("production_checkpoints", isDirectory: true)
        let exportedModelDirectoryURL = outputDirectory.appendingPathComponent("production_exports", isDirectory: true)
        let packageURL = outputDirectory.appendingPathComponent("splat_training_package.json")

        try writeFrameIndex(job.manifest, manifestRoot: manifestRoot, to: frameIndexURL)
        try writeDepthPriorIndex(job.manifest, manifestRoot: manifestRoot, to: depthPriorIndexURL)
        try trainingScript().write(to: trainScriptURL, atomically: true, encoding: .utf8)
        try writeProductionDataset(
            job.manifest,
            manifestRoot: manifestRoot,
            datasetURL: productionDatasetURL,
            transformsURL: nerfstudioTransformsURL,
            pointCloudURL: productionPointCloudURL
        )
        try FileManager.default.createDirectory(at: checkpointDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportedModelDirectoryURL, withIntermediateDirectories: true)
        try productionRunnerScript().write(to: productionRunnerURL, atomically: true, encoding: .utf8)
        let optimizationPlan = makeProductionOptimizationPlan(
            datasetURL: productionDatasetURL,
            transformsURL: nerfstudioTransformsURL,
            pointCloudURL: FileManager.default.fileExists(atPath: productionPointCloudURL.path) ? productionPointCloudURL : nil,
            runnerURL: productionRunnerURL,
            checkpointDirectoryURL: checkpointDirectoryURL,
            exportDirectoryURL: exportedModelDirectoryURL,
            outputURL: resolvedOutputURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(optimizationPlan).write(to: optimizerPlanURL)
        let frameRoles = resolvedFrameRoles(for: job.manifest.imageFrames)
        let calibratedFrameCount = job.manifest.imageFrames.filter { $0.calibration?.intrinsics != nil }.count

        let package = SplatTrainingPackageManifest(
            id: "\(job.manifest.id)-apple-splat-training-package",
            sourceManifestURL: manifestURL,
            frameIndexURL: frameIndexURL,
            depthPriorIndexURL: job.manifest.lidarFrames.isEmpty ? nil : depthPriorIndexURL,
            trainScriptURL: trainScriptURL,
            optimizerProfile: .productionGSplatSplatfacto,
            optimizerPlanURL: optimizerPlanURL,
            productionDatasetURL: productionDatasetURL,
            nerfstudioTransformsURL: nerfstudioTransformsURL,
            productionPointCloudURL: FileManager.default.fileExists(atPath: productionPointCloudURL.path) ? productionPointCloudURL : nil,
            productionRunnerURL: productionRunnerURL,
            checkpointDirectoryURL: checkpointDirectoryURL,
            exportedModelDirectoryURL: exportedModelDirectoryURL,
            outputURL: resolvedOutputURL,
            frameCount: job.manifest.imageFrames.count,
            lidarFrameCount: job.manifest.lidarFrames.count,
            trainingFrameCount: frameRoles.filter { $0 == .train }.count,
            validationFrameCount: frameRoles.filter { $0 == .validation }.count,
            calibratedFrameCount: calibratedFrameCount,
            notes: [
                "Primary production path: use run_production_splat_optimizer.py to train Nerfstudio Splatfacto/gsplat with differentiable rasterization, spherical harmonics, checkpointing, densification, and pruning.",
                "The production_gsplat_dataset folder is self-contained and writes Nerfstudio-compatible transforms.json from calibrated capture poses.",
                "When LiDAR priors are present, the package writes sparse_pc.ply as a metric depth-derived point cloud for Splatfacto/gsplat initialization.",
                "production_splat_optimization_plan.json records optimizer stages, quality gates, dependency requirements, checkpoint/export locations, and the recommended runner command.",
                "The MLX script remains packaged as a local fallback; production optimization should use the generated Splatfacto/gsplat runner.",
                "Consumes RGB frame URLs, camera intrinsics, tracking quality, and aligned camera poses.",
                "Consumes strict Float32 meter depth priors when present and indexes them separately from RGB frame records.",
                "Exports a Gaussian PLY asset for the native Metal renderer and .robotscene packaging.",
                "Writes dataset preflight, eval metrics, export validation, command transcript, and SHA-256 output provenance for workstation auditability."
            ]
        )
        try JSONEncoder.robotVisionLabEncoder.encode(package).write(to: packageURL)
        return package
    }

    private func validateTrainingInputs(
        _ manifest: SplatTrainingManifest,
        relativeTo manifestRoot: URL,
        requirements: ProductionSplatDatasetRequirements
    ) throws {
        var issues: [String] = []
        if manifest.imageFrames.isEmpty {
            issues.append("Splat training manifest has no RGB image frames.")
        }
        let frameRoles = resolvedFrameRoles(for: manifest.imageFrames)
        let trainingFrameCount = frameRoles.filter { $0 == .train }.count
        let validationFrameCount = frameRoles.filter { $0 == .validation }.count
        if trainingFrameCount < requirements.minTrainingFrameCount {
            issues.append("Production splat optimization requires at least \(requirements.minTrainingFrameCount) train split frames; found \(trainingFrameCount).")
        }
        if requirements.requiresValidationSplit, validationFrameCount < requirements.minValidationFrameCount {
            issues.append("Production splat optimization requires at least \(requirements.minValidationFrameCount) validation split frames; found \(validationFrameCount).")
        }
        if manifest.imageFrames.count < requirements.minTotalFrameCount {
            issues.append("Production splat optimization requires at least \(requirements.minTotalFrameCount) total frames; found \(manifest.imageFrames.count).")
        }
        for (index, frame) in manifest.imageFrames.enumerated() {
            let imageURL = resolve(frame.imageURL, relativeTo: manifestRoot)
            if !isSupportedTrainingImageURL(imageURL) {
                issues.append("Training frame \(index) references \(frame.imageURL.lastPathComponent), which is not a supported still image.")
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: imageURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                issues.append("Training frame \(index) image is missing: \(frame.imageURL.path).")
                continue
            }
            let byteCount = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            if byteCount <= 0 {
                issues.append("Training frame \(index) image is empty: \(frame.imageURL.lastPathComponent).")
            }
            if frame.calibration?.intrinsics == nil {
                issues.append("Training frame \(index) is missing camera intrinsics.")
            }
        }
        if !issues.isEmpty {
            throw SplatTrainingPackageBuildError.invalidTrainingInputs(issues)
        }
    }

    private func resolve(_ url: URL, relativeTo root: URL) -> URL {
        PackageURLTools.resolve(url, relativeTo: root)
    }

    private func isSupportedTrainingImageURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff":
            return true
        default:
            return false
        }
    }

    private func resolvedFrameRoles(for frames: [SplatTrainingFrame]) -> [SplatTrainingFrameRole] {
        let fallbackSplit = SplatTrainingFrameSplit(frameCount: frames.count)
        return frames.enumerated().map { index, frame in
            frame.split ?? fallbackSplit.role(for: index)
        }
    }

    private func writeFrameIndex(_ manifest: SplatTrainingManifest, manifestRoot: URL, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let frameRoles = resolvedFrameRoles(for: manifest.imageFrames)
        let lines = try manifest.imageFrames.enumerated().map { index, frame in
            let record = SplatTrainingFrameRecord(
                index: index,
                split: frameRoles[index],
                imageURL: resolve(frame.imageURL, relativeTo: manifestRoot),
                timestamp: frame.timestamp,
                position: frame.pose.position,
                orientation: frame.pose.orientation.vector,
                intrinsics: frame.calibration?.intrinsics,
                resolution: frame.calibration?.resolution,
                trackingQuality: frame.calibration?.trackingQuality ?? .normal
            )
            return String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func writeDepthPriorIndex(_ manifest: SplatTrainingManifest, manifestRoot: URL, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lines = try manifest.lidarFrames.enumerated().map { index, frame in
            let record = SplatTrainingDepthPriorRecord(
                index: index,
                depthURL: resolve(frame.depthURL, relativeTo: manifestRoot),
                confidenceURL: frame.confidenceURL.map { resolve($0, relativeTo: manifestRoot) },
                metadataURL: resolve(frame.metadataURL, relativeTo: manifestRoot),
                timestamp: frame.timestamp,
                position: frame.pose.position,
                orientation: frame.pose.orientation.vector
            )
            return String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func writeProductionDataset(
        _ manifest: SplatTrainingManifest,
        manifestRoot: URL,
        datasetURL: URL,
        transformsURL: URL,
        pointCloudURL: URL
    ) throws {
	        let imagesURL = datasetURL.appendingPathComponent("images", isDirectory: true)
	        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
	        let pointCloud = try writeDepthInitializationPointCloud(
	            manifest.lidarFrames,
	            manifestRoot: manifestRoot,
	            to: pointCloudURL
	        )
	        var transcodedImageCount = 0
	        let frameRoles = resolvedFrameRoles(for: manifest.imageFrames)
	        let frames = try manifest.imageFrames.enumerated().map { index, frame in
	            let sourceURL = resolve(frame.imageURL, relativeTo: manifestRoot)
	            let imageExtension = productionDatasetImageExtension(for: sourceURL)
	            let imageName = String(format: "frame_%06d.%@", index, imageExtension)
	            let role = frameRoles[index]
	            let splitDirectoryName = role == .validation ? "eval" : "train"
	            let splitImagesURL = imagesURL.appendingPathComponent(splitDirectoryName, isDirectory: true)
	            try FileManager.default.createDirectory(at: splitImagesURL, withIntermediateDirectories: true)
            let destinationURL = splitImagesURL.appendingPathComponent(imageName)
            if sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
	                if FileManager.default.fileExists(atPath: destinationURL.path) {
	                    try FileManager.default.removeItem(at: destinationURL)
	                }
	                let transcoded = try writeProductionTrainingImage(from: sourceURL, to: destinationURL)
	                if transcoded {
	                    transcodedImageCount += 1
	                }
	            }
	            let intrinsics = frame.calibration?.intrinsics ?? fallbackIntrinsics(for: frame)
	            return NerfstudioTransformFrame(
                file_path: "images/\(splitDirectoryName)/\(imageName)",
                transform_matrix: transformMatrix(for: frame.pose),
                fl_x: intrinsics.focalLengthPixels.x,
                fl_y: intrinsics.focalLengthPixels.y,
                cx: intrinsics.principalPointPixels.x,
                cy: intrinsics.principalPointPixels.y,
                w: intrinsics.width,
                h: intrinsics.height,
                split: role.rawValue,
                timestamp: frame.timestamp,
                tracking_quality: frame.calibration?.trackingQuality.rawValue ?? TrackingQuality.normal.rawValue
            )
        }
        let referenceIntrinsics = manifest.imageFrames.first.flatMap { $0.calibration?.intrinsics } ?? frames.first.map {
            CameraIntrinsics(
                width: $0.w,
                height: $0.h,
                focalLengthPixels: SIMD2<Double>($0.fl_x, $0.fl_y),
                principalPointPixels: SIMD2<Double>($0.cx, $0.cy)
            )
        }
        let transforms = NerfstudioTransforms(
            camera_model: "OPENCV",
            coordinate_system: manifest.coordinateSystem.rawValue,
            fl_x: referenceIntrinsics?.focalLengthPixels.x,
            fl_y: referenceIntrinsics?.focalLengthPixels.y,
            cx: referenceIntrinsics?.principalPointPixels.x,
            cy: referenceIntrinsics?.principalPointPixels.y,
            w: referenceIntrinsics?.width,
            h: referenceIntrinsics?.height,
            ply_file_path: pointCloud == nil ? nil : pointCloudURL.lastPathComponent,
            frames: frames
        )
        try JSONEncoder.robotVisionLabEncoder.encode(transforms).write(to: transformsURL)
        let metadata = ProductionSplatDatasetMetadata(
	            id: manifest.id,
	            frameCount: manifest.imageFrames.count,
	            lidarDepthPriorCount: manifest.lidarFrames.count,
	            transcodedImageCount: transcodedImageCount,
	            depthInitializationPointCount: pointCloud?.pointCount ?? 0,
	            depthInitializationPointCloudURL: pointCloud.map { _ in pointCloudURL },
	            coordinateSystem: manifest.coordinateSystem.rawValue,
	            sourceManifestExpectedOutput: manifest.expectedOutput.targetURL,
	            notes: [
	                "Images are copied into this dataset so external trainers do not depend on the mutable capture package layout.",
	                "Non-PNG/JPEG still images are transcoded to PNG inside production_gsplat_dataset for trainer and preflight compatibility.",
	                "Camera transforms are camera-to-world matrices from calibrated capture poses.",
	                "Depth priors remain indexed in capture_lidar_depth_priors.jsonl for trainer extensions that consume metric depth supervision.",
	                "sparse_pc.ply is generated from metric depth priors when available and referenced by transforms.json ply_file_path for 3DGS point initialization."
            ]
        )
	        try JSONEncoder.robotVisionLabEncoder.encode(metadata)
	            .write(to: datasetURL.appendingPathComponent("robot_scene_dataset_metadata.json"))
	    }

	    private func productionDatasetImageExtension(for sourceURL: URL) -> String {
	        switch sourceURL.pathExtension.lowercased() {
	        case "jpg", "jpeg":
	            return sourceURL.pathExtension.lowercased()
	        case "png":
	            return "png"
	        default:
	            return "png"
	        }
	    }

	    @discardableResult
	    private func writeProductionTrainingImage(from sourceURL: URL, to destinationURL: URL) throws -> Bool {
	        switch sourceURL.pathExtension.lowercased() {
	        case "jpg", "jpeg", "png":
	            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
	            return false
	        default:
	            try transcodeTrainingImageToPNG(from: sourceURL, to: destinationURL)
	            return true
	        }
	    }

	    private func transcodeTrainingImageToPNG(from sourceURL: URL, to destinationURL: URL) throws {
	        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
	              CGImageSourceGetCount(source) > 0 else {
	            throw SplatTrainingPackageBuildError.invalidTrainingInputs([
	                "Training frame \(sourceURL.lastPathComponent) could not be decoded for production PNG normalization."
	            ])
	        }
	        guard let destination = CGImageDestinationCreateWithURL(
	            destinationURL as CFURL,
	            UTType.png.identifier as CFString,
	            1,
	            nil
	        ) else {
	            throw SplatTrainingPackageBuildError.invalidTrainingInputs([
	                "Could not create PNG destination for \(destinationURL.lastPathComponent)."
	            ])
	        }
	        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
	        guard CGImageDestinationFinalize(destination) else {
	            throw SplatTrainingPackageBuildError.invalidTrainingInputs([
	                "Training frame \(sourceURL.lastPathComponent) could not be transcoded to PNG for production optimization."
	            ])
	        }
	    }

    private func writeDepthInitializationPointCloud(
        _ lidarFrames: [CapturedLiDARFrame],
        manifestRoot: URL,
        to outputURL: URL,
        maximumPointCount: Int = 200_000
    ) throws -> DepthInitializationPointCloudSummary? {
        guard !lidarFrames.isEmpty else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }
        var points: [DepthInitializationPoint] = []
        let maxPointsPerFrame = max(maximumPointCount / max(lidarFrames.count, 1), 1)
        for frame in lidarFrames {
            let metadataURL = resolve(frame.metadataURL, relativeTo: manifestRoot)
            let metadata = try JSONDecoder.robotVisionLabDecoder.decode(
                CapturedLiDARDepthMetadata.self,
                from: Data(contentsOf: metadataURL)
            )
            let depthURL = resolve(frame.depthURL, relativeTo: manifestRoot)
            let confidenceURL = frame.confidenceURL.map { resolve($0, relativeTo: manifestRoot) }
            let depthData = try Data(contentsOf: depthURL)
            let expectedDepthBytes = metadata.width * metadata.height * MemoryLayout<Float32>.stride
            guard depthData.count == expectedDepthBytes else {
                throw SplatTrainingPackageBuildError.invalidTrainingInputs([
                    "LiDAR depth prior \(depthURL.lastPathComponent) byte count \(depthData.count) does not match \(metadata.width)x\(metadata.height) Float32 metadata."
                ])
            }
            let confidenceData = confidenceURL.flatMap { try? Data(contentsOf: $0) }
            let pixelCount = metadata.width * metadata.height
            let sampleStride = max(1, Int(ceil(sqrt(Double(pixelCount) / Double(maxPointsPerFrame)))))
            for y in stride(from: 0, to: metadata.height, by: sampleStride) {
                for x in stride(from: 0, to: metadata.width, by: sampleStride) {
                    let index = y * metadata.width + x
                    let confidence = confidenceData.flatMap { data -> UInt8? in
                        data.indices.contains(index) ? data[index] : nil
                    }
                    if let confidence, confidence == 0 {
                        continue
                    }
                    let depth = readFloat32LittleEndian(depthData, index: index)
                    guard depth.isFinite, depth > 0.02, depth < 20 else { continue }
                    let point = depthPoint(
                        x: x,
                        y: y,
                        depth: Double(depth),
                        confidence: confidence,
                        metadata: metadata
                    )
                    points.append(point)
                }
            }
        }
        guard !points.isEmpty else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }
        if points.count > maximumPointCount {
            let stride = max(points.count / maximumPointCount, 1)
            points = points.enumerated().compactMap { index, point in
                index.isMultiple(of: stride) ? point : nil
            }
            if points.count > maximumPointCount {
                points = Array(points.prefix(maximumPointCount))
            }
        }
        try writePointCloudPLY(points, to: outputURL)
        return DepthInitializationPointCloudSummary(pointCount: points.count, url: outputURL)
    }

    private func readFloat32LittleEndian(_ data: Data, index: Int) -> Float {
        let byteOffset = index * MemoryLayout<Float32>.stride
        let raw = data.withUnsafeBytes { buffer -> UInt32 in
            buffer.loadUnaligned(fromByteOffset: byteOffset, as: UInt32.self)
        }
        return Float(bitPattern: UInt32(littleEndian: raw))
    }

    private func depthPoint(
        x: Int,
        y: Int,
        depth: Double,
        confidence: UInt8?,
        metadata: CapturedLiDARDepthMetadata
    ) -> DepthInitializationPoint {
        let u = Double(x) + 0.5
        let v = Double(y) + 0.5
        let fx = max(metadata.intrinsics.focalLengthPixels.x, 1)
        let fy = max(metadata.intrinsics.focalLengthPixels.y, 1)
        let cx = metadata.intrinsics.principalPointPixels.x
        let cy = metadata.intrinsics.principalPointPixels.y
        let cameraPoint = SIMD3<Double>(
            (u - cx) / fx * depth,
            -(v - cy) / fy * depth,
            -depth
        )
        let worldPoint = metadata.cameraPose.orientation.value.act(cameraPoint) + metadata.cameraPose.position
        let intensity: UInt8 = {
            guard let confidence else { return 190 }
            switch confidence {
            case 2...UInt8.max: return 230
            case 1: return 170
            default: return 120
            }
        }()
        return DepthInitializationPoint(position: worldPoint, color: SIMD3<UInt8>(intensity, intensity, intensity))
    }

    private func writePointCloudPLY(_ points: [DepthInitializationPoint], to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = """
        ply
        format ascii 1.0
        comment Robot Scene Studio metric depth initialization point cloud
        element vertex \(points.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        for point in points {
            text += String(
                format: "%.6f %.6f %.6f %d %d %d\n",
                point.position.x,
                point.position.y,
                point.position.z,
                Int(point.color.x),
                Int(point.color.y),
                Int(point.color.z)
            )
        }
        try text.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func fallbackIntrinsics(for frame: SplatTrainingFrame) -> CameraIntrinsics {
        if let resolution = frame.calibration?.resolution {
            return CameraIntrinsics.fromHorizontalFOV(width: resolution.width, height: resolution.height, horizontalFOVDegrees: 70)
        }
        return CameraIntrinsics.fromHorizontalFOV(width: 1920, height: 1080, horizontalFOVDegrees: 70)
    }

    private func transformMatrix(for pose: Pose3D) -> [[Double]] {
        let rotation = pose.orientation.value
        let xAxis = rotation.act(SIMD3<Double>(1, 0, 0))
        let yAxis = rotation.act(SIMD3<Double>(0, 1, 0))
        let zAxis = rotation.act(SIMD3<Double>(0, 0, 1))
        return [
            [xAxis.x, yAxis.x, zAxis.x, pose.position.x],
            [xAxis.y, yAxis.y, zAxis.y, pose.position.y],
            [xAxis.z, yAxis.z, zAxis.z, pose.position.z],
            [0, 0, 0, 1]
        ]
    }

    private func makeProductionOptimizationPlan(
        datasetURL: URL,
        transformsURL: URL,
        pointCloudURL: URL?,
        runnerURL: URL,
        checkpointDirectoryURL: URL,
        exportDirectoryURL: URL,
        outputURL: URL
    ) -> SplatOptimizationPlan {
        SplatOptimizationPlan(
            profile: .productionGSplatSplatfacto,
            trainer: "Nerfstudio Splatfacto / gsplat",
            datasetURL: datasetURL,
            transformsJSONURL: transformsURL,
            initialPointCloudURL: pointCloudURL,
            runnerURL: runnerURL,
            checkpointDirectoryURL: checkpointDirectoryURL,
            exportDirectoryURL: exportDirectoryURL,
            targetOutputURL: outputURL,
            recommendedCommand: [
                "python3",
                runnerURL.path,
                "--method",
                "splatfacto",
                "--max-num-iterations",
                "30000",
                "--eval-mode",
                "filename",
                "--cache-images",
                "disk",
                "--output",
                outputURL.path
            ],
            optimizationStages: [
                SplatOptimizationStage(
                    name: "pose-normalized dataset ingest",
                    purpose: "Load calibrated images and camera-to-world transforms without recomputing capture poses.",
                    startStep: 0,
                    endStep: 0,
                    settings: [
                        "dataparser": "nerfstudio-data",
                        "transforms": transformsURL.lastPathComponent,
                        "image_source": "self-contained production_gsplat_dataset/images/train and images/eval",
                        "eval_mode": "filename",
                        "point_initialization": "sparse_pc.ply via ply_file_path when metric depth priors are available"
                    ]
                ),
                SplatOptimizationStage(
                    name: "anisotropic gaussian warmup",
                    purpose: "Optimize means, RGB/SH color, opacity, anisotropic covariance, and rotations with differentiable rasterization.",
                    startStep: 1,
                    endStep: 500,
                    settings: [
                        "sh_degree": "3",
                        "opacity_reset": "enabled",
                        "visibility_aware_rasterization": "enabled",
                        "initial_points": "depth-derived sparse point cloud when present, otherwise trainer initialization"
                    ]
                ),
                SplatOptimizationStage(
                    name: "densification and pruning",
                    purpose: "Interleave split/clone densification with opacity and scale pruning to allocate Gaussians only where image gradients need detail.",
                    startStep: 500,
                    endStep: 15000,
                    settings: [
                        "densification": "screen-space gradient split/clone",
                        "pruning": "low-opacity and oversized-screen-radius gaussian removal",
                        "checkpointing": checkpointDirectoryURL.lastPathComponent
                    ]
                ),
                SplatOptimizationStage(
                    name: "quality convergence and export",
                    purpose: "Keep optimizing after density control, export Gaussian PLY, and validate it through the native importer/renderer.",
                    startStep: 15000,
                    endStep: 30000,
                    settings: [
                        "evaluation": "ns-eval --load-config config.yml --output-path production_eval_metrics.json",
                        "export": "ns-export gaussian-splat",
                        "target": outputURL.lastPathComponent,
                        "audit": "production_training_summary.json plus SHA-256 and eval metrics"
                    ]
                )
            ],
            requiredCapabilities: [
                "Python environment with nerfstudio CLI commands: ns-train, ns-eval, and ns-export.",
                "Splatfacto/gsplat differentiable Gaussian rasterization backend.",
                "Enough GPU memory for the requested frame count and target Gaussian budget.",
                "Disk space for copied training images, checkpoints, exported PLY, and run summaries."
            ],
            qualityGates: [
                "All images in transforms.json must exist under production_gsplat_dataset/images.",
                "If transforms.json references ply_file_path, sparse_pc.ply must exist and be reported in dataset_preflight.json.",
                "Production preflight must require at least 2 train frames, 1 validation/eval frame when evaluation runs, and 3 total frames by default.",
                "Dataset preflight must write dataset_preflight.json with frame counts, byte counts, split counts, and missing-file count of zero.",
                "Training must write a Nerfstudio config.yml checkpoint before export.",
                "ns-eval must write production_eval_metrics.json against the preserved validation split.",
                "Optional PSNR, SSIM, and LPIPS gates must pass when configured.",
                "ns-export gaussian-splat must produce a PLY that GaussianSplatImporter can inspect.",
                "The exported PLY SHA-256, dataset preflight, eval metrics, and command transcript must be recorded in production_training_summary.json.",
                "The exported splat must be linked back as the active scene source before render/export."
            ],
            notes: [
                "This is the production-quality path; the generated MLX script remains a local fallback for small captures or machines without the external training stack.",
                "The plan follows the 3DGS pattern of visibility-aware differentiable rasterization, anisotropic covariance optimization, spherical harmonics color, interleaved densification, and pruning.",
                "Depth priors are preserved for custom trainer extensions, and sparse_pc.ply gives stock Splatfacto a metric point-cloud initialization through Nerfstudio's 3D point loading path."
            ]
        )
    }

    private func productionRunnerScript() -> String {
        """
        #!/usr/bin/env python3
        import argparse
        import hashlib
        import json
        import math
        import shutil
        import struct
        import subprocess
        import sys
        from pathlib import Path

        def checksum(path):
            digest = hashlib.sha256()
            with Path(path).open("rb") as handle:
                for block in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(block)
            return digest.hexdigest()

        def file_state(path):
            path = Path(path)
            if not path.exists():
                return None
            stat = path.stat()
            return {
                "path": str(path),
                "size": stat.st_size,
                "mtime_ns": stat.st_mtime_ns,
                "sha256": checksum(path),
            }

        def run(command):
            print(json.dumps({"running": command}, indent=2))
            subprocess.run(command, check=True)

        def finite_number(value):
            return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))

        def positive_number(value):
            return finite_number(value) and float(value) > 0

        def positive_integer(value):
            return isinstance(value, int) and not isinstance(value, bool) and value > 0

        def camera_value(frame, transforms, key):
            return frame[key] if key in frame else transforms.get(key)

        def image_size(path):
            path = Path(path)
            try:
                with path.open("rb") as handle:
                    header = handle.read(32)
                    if header.startswith(b"\\x89PNG\\r\\n\\x1a\\n") and len(header) >= 24:
                        return struct.unpack(">II", header[16:24])
                    if header[:2] == b"\\xff\\xd8":
                        handle.seek(2)
                        while True:
                            prefix = handle.read(1)
                            if not prefix:
                                return None
                            if prefix != b"\\xff":
                                continue
                            marker = handle.read(1)
                            while marker == b"\\xff":
                                marker = handle.read(1)
                            if not marker or marker in (b"\\xd8", b"\\xd9"):
                                continue
                            length_data = handle.read(2)
                            if len(length_data) != 2:
                                return None
                            length = struct.unpack(">H", length_data)[0]
                            if length < 2:
                                return None
                            marker_value = marker[0]
                            if marker_value in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
                                payload = handle.read(5)
                                if len(payload) != 5:
                                    return None
                                height, width = struct.unpack(">HH", payload[1:5])
                                return int(width), int(height)
                            handle.seek(length - 2, 1)
            except OSError:
                return None
            return None

        def validate_dataset(dataset, require_eval_split=False, min_train_frames=2, min_eval_frames=1, min_total_frames=0):
            dataset = Path(dataset)
            transforms_path = dataset / "transforms.json"
            if not transforms_path.exists():
                raise FileNotFoundError(f"Missing transforms.json in {dataset}")
            transforms = json.loads(transforms_path.read_text())
            frames = transforms.get("frames") or []
            if not frames:
                raise ValueError(f"Nerfstudio transforms.json has no frames: {transforms_path}")
            missing_files = []
            invalid_frames = []
            total_image_bytes = 0
            split_counts = {}
            image_dimensions_checked = 0
            point_cloud = transforms.get("ply_file_path")
            point_cloud_path = dataset / point_cloud if point_cloud else None
            point_cloud_bytes = 0
            if point_cloud_path is not None:
                if not point_cloud_path.exists():
                    missing_files.append(str(point_cloud_path))
                else:
                    point_cloud_bytes = point_cloud_path.stat().st_size
            for index, frame in enumerate(frames):
                relative_path = frame.get("file_path")
                matrix = frame.get("transform_matrix")
                split = str(frame.get("split") or "train").lower()
                split_counts[split] = split_counts.get(split, 0) + 1
                if split not in ("train", "validation", "eval"):
                    invalid_frames.append({"index": index, "reason": f"unsupported split {split}"})
                if not relative_path:
                    invalid_frames.append({"index": index, "reason": "missing file_path"})
                    continue
                image_path = dataset / relative_path
                if not image_path.exists():
                    missing_files.append(str(image_path))
                else:
                    total_image_bytes += image_path.stat().st_size
                camera_fields = {}
                for key in ("fl_x", "fl_y", "cx", "cy", "w", "h"):
                    value = camera_value(frame, transforms, key)
                    if value is None:
                        invalid_frames.append({"index": index, "reason": f"missing camera field {key}"})
                    else:
                        camera_fields[key] = value
                for key in ("fl_x", "fl_y"):
                    if key in camera_fields and not positive_number(camera_fields[key]):
                        invalid_frames.append({"index": index, "reason": f"camera field {key} must be a finite positive number"})
                for key in ("cx", "cy"):
                    if key in camera_fields and not finite_number(camera_fields[key]):
                        invalid_frames.append({"index": index, "reason": f"camera field {key} must be a finite number"})
                for key in ("w", "h"):
                    if key in camera_fields and not positive_integer(camera_fields[key]):
                        invalid_frames.append({"index": index, "reason": f"camera field {key} must be a positive integer"})
                expected_width = int(camera_fields["w"]) if positive_integer(camera_fields.get("w")) else None
                expected_height = int(camera_fields["h"]) if positive_integer(camera_fields.get("h")) else None
                if not isinstance(matrix, list) or len(matrix) != 4 or any(not isinstance(row, list) or len(row) != 4 for row in matrix):
                    invalid_frames.append({"index": index, "reason": "transform_matrix must be 4x4"})
                elif any(not finite_number(value) for row in matrix for value in row):
                    invalid_frames.append({"index": index, "reason": "transform_matrix values must be finite numbers"})
                if image_path.exists():
                    detected_size = image_size(image_path)
                    if detected_size is not None:
                        image_dimensions_checked += 1
                        if expected_width is not None and expected_height is not None and detected_size != (expected_width, expected_height):
                            invalid_frames.append({
                                "index": index,
                                "reason": f"image dimensions {detected_size[0]}x{detected_size[1]} do not match camera fields {expected_width}x{expected_height}"
                            })
            train_count = split_counts.get("train", 0)
            eval_count = split_counts.get("validation", 0) + split_counts.get("eval", 0)
            total_minimum = max(min_total_frames, min_train_frames + (min_eval_frames if require_eval_split else 0))
            minimums = {
                "train_frames": min_train_frames,
                "eval_frames": min_eval_frames if require_eval_split else 0,
                "total_frames": total_minimum,
            }
            if len(frames) < total_minimum:
                invalid_frames.append({"index": None, "reason": f"dataset has {len(frames)} frames but production preflight requires at least {total_minimum} total frames"})
            if train_count < min_train_frames:
                invalid_frames.append({"index": None, "reason": f"dataset has {train_count} train split frames but production preflight requires at least {min_train_frames}"})
            if require_eval_split and eval_count < min_eval_frames:
                invalid_frames.append({"index": None, "reason": f"dataset has {eval_count} validation split frames for ns-eval but production preflight requires at least {min_eval_frames}"})
            if missing_files or invalid_frames:
                raise ValueError(json.dumps({
                    "dataset": str(dataset),
                    "missing_files": missing_files,
                    "invalid_frames": invalid_frames,
                    "split_counts": split_counts,
                    "minimums": minimums,
                    "image_dimensions_checked": image_dimensions_checked,
                }, indent=2))
            preflight = {
                "dataset": str(dataset),
                "transforms": str(transforms_path),
                "frame_count": len(frames),
                "split_counts": split_counts,
                "minimums": minimums,
                "validation_split_required": require_eval_split,
                "total_image_bytes": total_image_bytes,
                "image_dimensions_checked": image_dimensions_checked,
                "point_cloud": str(point_cloud_path) if point_cloud_path is not None else None,
                "point_cloud_bytes": point_cloud_bytes,
                "missing_file_count": 0,
                "invalid_frame_count": 0,
                "camera_model": transforms.get("camera_model"),
            }
            preflight_path = dataset / "dataset_preflight.json"
            preflight_path.write_text(json.dumps(preflight, indent=2))
            preflight["preflight_path"] = str(preflight_path)
            return preflight

        def path_key(path):
            return str(Path(path).resolve())

        def snapshot_files(root, pattern):
            return {path_key(path) for path in Path(root).rglob(pattern)}

        def newest_file(root, pattern, excluded=None):
            excluded = excluded or set()
            candidates = [
                path for path in Path(root).rglob(pattern)
                if path_key(path) not in excluded
            ]
            return sorted(candidates, key=lambda path: path.stat().st_mtime, reverse=True)

        def latest_config(checkpoint_root, excluded=None):
            configs = newest_file(checkpoint_root, "config.yml", excluded=excluded)
            if not configs:
                raise FileNotFoundError(f"No Nerfstudio config.yml was written under {checkpoint_root}")
            return configs[0]

        def latest_config_or_none(checkpoint_root, excluded=None):
            configs = newest_file(checkpoint_root, "config.yml", excluded=excluded)
            return configs[0] if configs else None

        def newest_ply(export_root, excluded=None):
            candidates = newest_file(export_root, "*.ply", excluded=excluded)
            if not candidates:
                raise FileNotFoundError(f"No Gaussian PLY export was written under {export_root}")
            return candidates[0]

        def newest_ply_or_none(export_root, excluded=None):
            candidates = newest_file(export_root, "*.ply", excluded=excluded)
            return candidates[0] if candidates else None

        def load_json_if_present(path):
            path = Path(path)
            if not path.exists():
                return None
            return json.loads(path.read_text())

        def inspect_gaussian_ply(path):
            path = Path(path)
            if path.suffix.lower() != ".ply":
                raise ValueError(f"Gaussian export must be a .ply file, got {path}")
            if not path.exists():
                raise FileNotFoundError(f"Gaussian PLY export is missing: {path}")
            header_bytes = path.read_bytes()[:262144]
            marker = b"end_header"
            header_end = header_bytes.find(marker)
            if header_end < 0:
                raise ValueError(f"Gaussian PLY export is missing end_header: {path}")
            header_text = header_bytes[:header_end + len(marker)].decode("ascii", errors="strict")
            lines = [line.strip() for line in header_text.splitlines() if line.strip()]
            if not lines or lines[0] != "ply":
                raise ValueError(f"Gaussian PLY export does not start with a PLY header: {path}")
            format_line = next((line for line in lines if line.startswith("format ")), None)
            if format_line is None:
                raise ValueError(f"Gaussian PLY export is missing a format line: {path}")
            vertex_count = None
            vertex_properties = []
            current_element = None
            for line in lines:
                tokens = line.split()
                if len(tokens) >= 3 and tokens[0] == "element":
                    current_element = tokens[1]
                    if current_element == "vertex":
                        try:
                            vertex_count = int(tokens[2])
                        except ValueError as error:
                            raise ValueError(f"Gaussian PLY export has invalid vertex count: {path}") from error
                elif len(tokens) >= 3 and tokens[0] == "property" and current_element == "vertex":
                    vertex_properties.append(tokens[-1])
            if vertex_count is None or vertex_count <= 0:
                raise ValueError(f"Gaussian PLY export must contain at least one vertex: {path}")
            property_set = set(vertex_properties)
            required = {"x", "y", "z", "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"}
            missing = sorted(required - property_set)
            has_rgb = {"red", "green", "blue"}.issubset(property_set)
            has_fdc = {"f_dc_0", "f_dc_1", "f_dc_2"}.issubset(property_set)
            if not has_rgb and not has_fdc:
                missing.append("red/green/blue or f_dc_0/f_dc_1/f_dc_2")
            if missing:
                raise ValueError("Gaussian PLY export is missing required properties: " + ", ".join(missing))
            return {
                "path": str(path),
                "format": format_line,
                "vertex_count": vertex_count,
                "property_count": len(vertex_properties),
                "color_model": "rgb" if has_rgb else "f_dc",
            }

        def metric_value(metrics, candidate_names):
            if metrics is None:
                return None
            candidates = {name.lower().replace("-", "_") for name in candidate_names}
            values = []

            def visit(value, path):
                if isinstance(value, dict):
                    for key, child in value.items():
                        visit(child, path + [str(key)])
                elif isinstance(value, (int, float)) and not isinstance(value, bool):
                    normalized_key = path[-1].lower().replace("-", "_") if path else ""
                    normalized_path = "_".join(path).lower().replace("-", "_")
                    if normalized_key in candidates or normalized_path in candidates:
                        values.append(float(value))

            visit(metrics, [])
            return values[0] if values else None

        def main():
            package_root = Path(__file__).resolve().parent
            parser = argparse.ArgumentParser(description="Run the production Splatfacto/gsplat optimizer for this capture package.")
            parser.add_argument("--dataset", default=str(package_root / "production_gsplat_dataset"))
            parser.add_argument("--checkpoints", default=str(package_root / "production_checkpoints"))
            parser.add_argument("--exports", default=str(package_root / "production_exports"))
            parser.add_argument("--output", default=None, help="Final PLY path to copy the exported splat to.")
            parser.add_argument("--method", default="splatfacto", help="Nerfstudio method, for example splatfacto, splatfacto-big, or a locally installed gsplat variant.")
            parser.add_argument("--max-num-iterations", type=int, default=30000)
            parser.add_argument("--steps-per-save", type=int, default=5000)
            parser.add_argument("--eval-mode", default="filename", help="Nerfstudio eval split mode. Filename mode matches the generated images/train and images/eval layout.")
            parser.add_argument("--eval-output", default=str(package_root / "production_eval_metrics.json"), help="JSON metrics path written by ns-eval.")
            parser.add_argument("--eval-render-output", default=None, help="Optional directory for ns-eval rendered output images.")
            parser.add_argument("--min-psnr", type=float, default=None, help="Optional minimum PSNR gate; fails the run if ns-eval reports a lower PSNR.")
            parser.add_argument("--min-ssim", type=float, default=None, help="Optional minimum SSIM gate; fails the run if ns-eval reports a lower SSIM.")
            parser.add_argument("--max-lpips", type=float, default=None, help="Optional maximum LPIPS gate; fails the run if ns-eval reports a higher LPIPS.")
            parser.add_argument("--min-train-frames", type=int, default=2, help="Minimum train split frames required by production preflight.")
            parser.add_argument("--min-eval-frames", type=int, default=1, help="Minimum validation/eval split frames required when ns-eval runs.")
            parser.add_argument("--min-total-frames", type=int, default=0, help="Minimum total frames required by production preflight. Default is min train plus required eval frames.")
            parser.add_argument("--cache-images", default="disk", choices=["default", "cpu", "gpu", "disk"], help="Splatfacto image cache mode; disk is safer for large captures.")
            parser.add_argument("--load-depth-point-cloud", action=argparse.BooleanOptionalAction, default=True, help="Load sparse_pc.ply depth initialization points when transforms.json references them.")
            parser.add_argument("--skip-train", action="store_true")
            parser.add_argument("--skip-eval", action="store_true")
            parser.add_argument("--skip-export", action="store_true")
            parser.add_argument("--preflight-only", action="store_true")
            parser.add_argument("--print-commands", action="store_true")
            parser.add_argument("--extra-ns-train-arg", action="append", default=[], help="Additional argument forwarded to ns-train. Repeat for each token.")
            args = parser.parse_args()

            dataset = Path(args.dataset).resolve()
            checkpoint_root = Path(args.checkpoints).resolve()
            export_root = Path(args.exports).resolve()
            checkpoint_root.mkdir(parents=True, exist_ok=True)
            export_root.mkdir(parents=True, exist_ok=True)
            min_train_frames = max(args.min_train_frames, 1)
            min_eval_frames = max(args.min_eval_frames, 0)
            min_total_frames = max(args.min_total_frames, 0)
            preflight = validate_dataset(
                dataset,
                require_eval_split=not args.skip_eval,
                min_train_frames=min_train_frames,
                min_eval_frames=min_eval_frames,
                min_total_frames=min_total_frames,
            )
            quality_gate_requested = args.min_psnr is not None or args.min_ssim is not None or args.max_lpips is not None

            ns_train = shutil.which("ns-train")
            ns_eval = shutil.which("ns-eval")
            ns_export = shutil.which("ns-export")
            tool_report = {
                "ns_train": ns_train,
                "ns_eval": ns_eval,
                "ns_export": ns_export,
            }
            commands = []
            missing_tools = []
            if not args.skip_train and ns_train is None:
                missing_tools.append("ns-train")
            if not args.skip_eval and ns_eval is None:
                missing_tools.append("ns-eval")
            if not args.skip_export and ns_export is None:
                missing_tools.append("ns-export")
            if args.preflight_only:
                print(json.dumps({"preflight": preflight, "tools": tool_report, "missing_tools": missing_tools, "commands": commands}, indent=2))
                return
            if missing_tools:
                raise RuntimeError("Nerfstudio CLI is required for production splat optimization. Missing commands on PATH: " + ", ".join(missing_tools))

            prior_configs = snapshot_files(checkpoint_root, "config.yml")
            config = None
            if not args.skip_train:
                train_command = [
                    ns_train,
                    args.method,
                    "--max-num-iterations",
                    str(max(args.max_num_iterations, 1)),
                    "--steps-per-save",
                    str(max(args.steps_per_save, 1)),
                    "--output-dir",
                    str(checkpoint_root),
                ]
                if args.cache_images != "default":
                    train_command += ["--pipeline.datamanager.cache-images", args.cache_images]
                train_command += args.extra_ns_train_arg + [
                    "nerfstudio-data",
                    "--data",
                    str(dataset),
                    "--eval-mode",
                    args.eval_mode,
                ]
                if args.load_depth_point_cloud and preflight.get("point_cloud") is not None:
                    train_command += ["--load-3D-points", "True"]
                commands.append(train_command)
                if args.print_commands:
                    print(json.dumps({"train_command": train_command}, indent=2))
                run(train_command)
                config = latest_config(checkpoint_root, excluded=prior_configs)
            else:
                needs_config = not args.skip_eval or not args.skip_export
                config = latest_config(checkpoint_root) if needs_config else latest_config_or_none(checkpoint_root)

            eval_output = None
            eval_metrics = None
            eval_metrics_sha256 = None
            quality_gates = []
            exported_ply = None
            exported_ply_validation = None
            final_output_validation = None

            def add_quality_gate(metric, candidate_names, minimum=None, maximum=None):
                value = metric_value(eval_metrics, candidate_names)
                if value is None:
                    raise RuntimeError(f"ns-eval metrics did not include a {metric.upper()} value for quality gating.")
                passed = True
                if minimum is not None and value < minimum:
                    passed = False
                if maximum is not None and value > maximum:
                    passed = False
                gate = {
                    "metric": metric,
                    "minimum": minimum,
                    "maximum": maximum,
                    "value": value,
                    "passed": passed,
                }
                quality_gates.append(gate)
                if not passed:
                    if minimum is not None:
                        raise RuntimeError(f"{metric.upper()} quality gate failed: {value:.4f} < {minimum:.4f}")
                    raise RuntimeError(f"{metric.upper()} quality gate failed: {value:.4f} > {maximum:.4f}")

            def apply_quality_gates():
                if args.min_psnr is not None:
                    add_quality_gate("psnr", ["psnr", "eval_psnr", "mean_psnr", "psnr_mean"], minimum=args.min_psnr)
                if args.min_ssim is not None:
                    add_quality_gate("ssim", ["ssim", "eval_ssim", "mean_ssim", "ssim_mean"], minimum=args.min_ssim)
                if args.max_lpips is not None:
                    add_quality_gate("lpips", ["lpips", "eval_lpips", "mean_lpips", "lpips_mean"], maximum=args.max_lpips)

            if not args.skip_eval:
                if config is None:
                    raise FileNotFoundError(f"No Nerfstudio config.yml was written under {checkpoint_root}")
                eval_output = Path(args.eval_output).resolve()
                eval_output.parent.mkdir(parents=True, exist_ok=True)
                prior_eval_state = file_state(eval_output)
                eval_command = [
                    ns_eval,
                    "--load-config",
                    str(config),
                    "--output-path",
                    str(eval_output),
                ]
                if args.eval_render_output:
                    eval_render_output = Path(args.eval_render_output).resolve()
                    eval_render_output.mkdir(parents=True, exist_ok=True)
                    eval_command += ["--render-output-path", str(eval_render_output)]
                commands.append(eval_command)
                if args.print_commands:
                    print(json.dumps({"eval_command": eval_command}, indent=2))
                run(eval_command)
                eval_output_state = file_state(eval_output)
                if eval_output_state is None:
                    raise RuntimeError(f"ns-eval completed but did not write metrics JSON at {eval_output}.")
                if prior_eval_state is not None and eval_output_state == prior_eval_state:
                    raise RuntimeError(f"ns-eval completed but did not replace stale metrics JSON at {eval_output}.")
                eval_metrics = load_json_if_present(eval_output)
                if eval_metrics is None:
                    raise RuntimeError(f"ns-eval completed but did not write metrics JSON at {eval_output}.")
                eval_metrics_sha256 = eval_output_state.get("sha256")
                apply_quality_gates()
            elif quality_gate_requested:
                eval_output = Path(args.eval_output).resolve()
                eval_metrics = load_json_if_present(eval_output)
                if eval_metrics is None:
                    raise RuntimeError(f"Quality gates require eval metrics, but --skip-eval was used and no metrics JSON exists at {eval_output}.")
                eval_metrics_sha256 = checksum(eval_output)
                apply_quality_gates()
            if not args.skip_export:
                if config is None:
                    raise FileNotFoundError(f"No Nerfstudio config.yml was written under {checkpoint_root}")
                prior_exports = snapshot_files(export_root, "*.ply")
                export_command = [
                    ns_export,
                    "gaussian-splat",
                    "--load-config",
                    str(config),
                    "--output-dir",
                    str(export_root),
                ]
                commands.append(export_command)
                if args.print_commands:
                    print(json.dumps({"export_command": export_command}, indent=2))
                run(export_command)
                exported_ply = newest_ply(export_root, excluded=prior_exports)

            final_output = Path(args.output).resolve() if args.output else None
            if args.skip_export:
                if final_output is not None and final_output.exists():
                    exported_ply = final_output
                else:
                    exported_ply = newest_ply_or_none(export_root)
                if exported_ply is None:
                    raise FileNotFoundError("--skip-export requires --output to reference an existing PLY or the export directory to contain a prior .ply export.")
            else:
                if exported_ply is None:
                    exported_ply = newest_ply(export_root)
            if final_output is None:
                final_output = exported_ply
            exported_ply_validation = inspect_gaussian_ply(exported_ply)
            if final_output != exported_ply:
                final_output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(exported_ply, final_output)
            final_output_validation = inspect_gaussian_ply(final_output)

            summary = {
                "trainer": "nerfstudio",
                "method": args.method,
                "dataset": str(dataset),
                "config": str(config) if config is not None else None,
                "eval_output": str(eval_output) if eval_output is not None else None,
                "eval_metrics": eval_metrics,
                "eval_metrics_sha256": eval_metrics_sha256,
                "quality_gate": quality_gates[0] if quality_gates else None,
                "quality_gates": quality_gates,
                "exported_ply": str(exported_ply),
                "exported_ply_validation": exported_ply_validation,
                "export_reused": args.skip_export,
                "final_output": str(final_output),
                "final_output_validation": final_output_validation,
                "final_output_sha256": checksum(final_output),
                "preflight": preflight,
                "tools": tool_report,
                "commands": commands,
            }
            summary_path = final_output.with_suffix(".production_training_summary.json")
            summary_path.write_text(json.dumps(summary, indent=2))
            print(json.dumps(summary, indent=2))

        if __name__ == "__main__":
            try:
                main()
            except Exception as error:
                print(json.dumps({"error": str(error)}, indent=2), file=sys.stderr)
                raise
        """
    }

    private func trainingScript() -> String {
        """
        #!/usr/bin/env python3
        import argparse
        import json
        import struct
        from pathlib import Path
        from urllib.parse import unquote, urlparse

        import mlx.core as mx
        import numpy as np

        try:
            from PIL import Image
        except Exception:
            Image = None

        def load_jsonl(path):
            return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]

        def image_path_or_raise(path):
            image_path = file_path(path)
            if not image_path.exists():
                raise FileNotFoundError(f"RGB training image is missing: {image_path}")
            if image_path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".heic", ".heif", ".tif", ".tiff"}:
                raise ValueError(f"RGB training frame must be a still image, got: {image_path}")
            return image_path

        def average_rgb(path):
            if Image is None:
                raise RuntimeError("Pillow is required to read RGB training images.")
            image_path = image_path_or_raise(path)
            image = Image.open(image_path).convert("RGB").resize((32, 32))
            return np.asarray(image, dtype=np.float32).reshape(-1, 3).mean(axis=0) / 255.0

        def load_rgb_image(path):
            if Image is None:
                raise RuntimeError("Pillow is required to read RGB training images.")
            image_path = image_path_or_raise(path)
            return np.asarray(Image.open(image_path).convert("RGB"), dtype=np.float32) / 255.0

        def file_path(path):
            value = str(path)
            parsed = urlparse(value)
            if parsed.scheme == "file":
                return Path(unquote(parsed.path))
            return Path(unquote(value))

        def load_depth_priors(path):
            if not path:
                return []
            index_path = Path(path)
            if not index_path.exists():
                return []
            priors = []
            for record in load_jsonl(index_path):
                metadata_path = file_path(record["metadataURL"])
                depth_path = file_path(record["depthURL"])
                confidence_path = file_path(record["confidenceURL"]) if record.get("confidenceURL") else None
                if not metadata_path.exists() or not depth_path.exists():
                    continue
                metadata = json.loads(metadata_path.read_text())
                width = int(metadata["width"])
                height = int(metadata["height"])
                depth = np.fromfile(depth_path, dtype="<f4")
                if depth.size != width * height:
                    raise ValueError(f"Depth prior byte count does not match metadata dimensions for {depth_path}")
                depth = depth.reshape(height, width)
                confidence = None
                if confidence_path is not None and confidence_path.exists():
                    confidence = np.fromfile(confidence_path, dtype=np.uint8)
                    if confidence.size == width * height:
                        confidence = confidence.reshape(height, width).astype(np.float32) / 2.0
                    else:
                        confidence = None
                priors.append({
                    "timestamp": float(record["timestamp"]),
                    "position": vector3(record["position"]),
                    "orientation": quaternion(record["orientation"]),
                    "depth": depth,
                    "confidence": confidence,
                    "metadata": metadata,
                })
            return priors

        def nearest_depth_prior(frame, priors, max_delta_seconds=0.075):
            if not priors:
                return None
            timestamp = float(frame["timestamp"])
            nearest = min(priors, key=lambda prior: abs(prior["timestamp"] - timestamp))
            if abs(nearest["timestamp"] - timestamp) > max_delta_seconds:
                return None
            return nearest

        def sample_depth_prior(prior, u, v, fallback):
            if prior is None:
                return fallback, 0.0
            depth = prior["depth"]
            height, width = depth.shape
            x = int(np.clip(round(u / max(prior["metadata"].get("intrinsics", {}).get("width", width), 1) * width), 0, width - 1))
            y = int(np.clip(round(v / max(prior["metadata"].get("intrinsics", {}).get("height", height), 1) * height), 0, height - 1))
            value = float(depth[y, x])
            if not np.isfinite(value) or value <= 0.02:
                return fallback, 0.0
            confidence = 1.0
            if prior["confidence"] is not None:
                confidence = float(np.clip(prior["confidence"][y, x], 0.0, 1.0))
            return value, confidence

        def sample_rgb(frame, u, v):
            image = load_rgb_image(frame["imageURL"])
            height, width = image.shape[:2]
            x = int(np.clip(round(u / max(frame_intrinsics(frame)[0], 1) * width), 0, width - 1))
            y = int(np.clip(round(v / max(frame_intrinsics(frame)[1], 1) * height), 0, height - 1))
            return image[y, x]

        def vector3(value):
            if isinstance(value, dict):
                return np.array([value["x"], value["y"], value["z"]], dtype=np.float32)
            return np.array(value[:3], dtype=np.float32)

        def quaternion(value):
            if isinstance(value, dict):
                return np.array([value["x"], value["y"], value["z"], value["w"]], dtype=np.float32)
            return np.array(value[:4], dtype=np.float32)

        def rotate_vector(q, v):
            q_xyz = q[:3]
            q_w = q[3]
            t = 2.0 * np.cross(q_xyz, v)
            return v + q_w * t + np.cross(q_xyz, t)

        def frame_intrinsics(frame):
            intrinsics = frame.get("intrinsics") or {}
            resolution = frame.get("resolution") or {}
            width = int(intrinsics.get("width") or resolution.get("width") or 1920)
            height = int(intrinsics.get("height") or resolution.get("height") or 1080)
            focal = intrinsics.get("focalLengthPixels") or [float(width), float(width)]
            principal = intrinsics.get("principalPointPixels") or [float(width) / 2.0, float(height) / 2.0]
            return width, height, vector2(focal), vector2(principal)

        def vector2(value):
            if isinstance(value, dict):
                return np.array([value["x"], value["y"]], dtype=np.float32)
            return np.array(value[:2], dtype=np.float32)

        def camera_ray(frame, offset, splats_per_frame):
            width, height, focal, principal = frame_intrinsics(frame)
            columns = max(int(np.ceil(np.sqrt(splats_per_frame))), 1)
            row = offset // columns
            column = offset % columns
            u = (column + 0.5) / float(columns) * width
            v = (row + 0.5) / float(columns) * height
            camera_direction = np.array(
                [
                    (u - principal[0]) / max(focal[0], 1.0),
                    -(v - principal[1]) / max(focal[1], 1.0),
                    -1.0,
                ],
                dtype=np.float32,
            )
            camera_direction /= max(np.linalg.norm(camera_direction), 1e-6)
            return rotate_vector(quaternion(frame["orientation"]), camera_direction), u, v

        def seed_gaussians(frames, depth_priors, splats_per_frame):
            positions = []
            colors = []
            source_origins = []
            source_rays = []
            target_colors = []
            target_depths = []
            depth_weights = []
            for frame in frames:
                if frame.get("split") != "train":
                    continue
                if frame.get("trackingQuality") == "notAvailable":
                    continue
                origin = vector3(frame["position"])
                color = average_rgb(frame["imageURL"])
                depth_prior = nearest_depth_prior(frame, depth_priors)
                for offset in range(splats_per_frame):
                    t = (offset + 1) / float(splats_per_frame + 1)
                    ray, u, v = camera_ray(frame, offset, splats_per_frame)
                    fallback_depth = 0.4 + t * 2.0
                    depth_meters, depth_weight = sample_depth_prior(depth_prior, u, v, fallback_depth)
                    seed_depth = 0.35 * fallback_depth + 0.65 * depth_meters if depth_weight > 0 else fallback_depth
                    positions.append(origin + ray * seed_depth)
                    sampled_color = sample_rgb(frame, u, v)
                    colors.append(0.5 * color + 0.5 * sampled_color)
                    source_origins.append(origin)
                    source_rays.append(ray)
                    target_colors.append(sampled_color)
                    target_depths.append(depth_meters)
                    depth_weights.append(depth_weight)
            return (
                np.asarray(positions, dtype=np.float32),
                np.asarray(colors, dtype=np.float32),
                np.asarray(source_origins, dtype=np.float32),
                np.asarray(source_rays, dtype=np.float32),
                np.asarray(target_colors, dtype=np.float32),
                np.asarray(target_depths, dtype=np.float32).reshape(-1, 1),
                np.asarray(depth_weights, dtype=np.float32).reshape(-1, 1),
            )

        def gaussian_rotation_from_ray(ray):
            ray = ray / max(np.linalg.norm(ray), 1e-6)
            forward = np.array([0.0, 0.0, -1.0], dtype=np.float32)
            dot = float(np.clip(np.dot(forward, ray), -1.0, 1.0))
            if dot > 0.9999:
                return np.array([0.0, 0.0, 0.0, 1.0], dtype=np.float32)
            if dot < -0.9999:
                return np.array([0.0, 1.0, 0.0, 0.0], dtype=np.float32)
            axis = np.cross(forward, ray)
            axis = axis / max(np.linalg.norm(axis), 1e-6)
            angle = np.arccos(dot)
            s = np.sin(angle * 0.5)
            return np.array([axis[0] * s, axis[1] * s, axis[2] * s, np.cos(angle * 0.5)], dtype=np.float32)

        def logit(value):
            value = np.clip(value, 1e-4, 1.0 - 1e-4)
            return np.log(value / (1.0 - value))

        def log_scale(value):
            return np.log(np.clip(value, 1e-4, 2.0))

        def write_ply(path, positions, colors, opacity, scale, rotations, ascii_output=False):
            path = Path(path)
            path.parent.mkdir(parents=True, exist_ok=True)
            header = [
                "ply",
                "format ascii 1.0" if ascii_output else "format binary_little_endian 1.0",
                "comment Robot Scene Studio Apple MLX splat training output",
                f"element vertex {len(positions)}",
                "property float x",
                "property float y",
                "property float z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
                "property float opacity",
                "property float scale_0",
                "property float scale_1",
                "property float scale_2",
                "property float rot_0",
                "property float rot_1",
                "property float rot_2",
                "property float rot_3",
                "end_header",
            ]
            if ascii_output:
                with path.open("w") as f:
                    f.write("\\n".join(header) + "\\n")
                    for p, c, o, s, r in zip(positions, colors, opacity, scale, rotations):
                        rgb = np.clip(np.round(c * 255.0), 0, 255).astype(np.uint8)
                        f.write(
                            f"{p[0]:.6f} {p[1]:.6f} {p[2]:.6f} "
                            f"{int(rgb[0])} {int(rgb[1])} {int(rgb[2])} "
                            f"{float(logit(o)):.4f} {float(log_scale(s[0])):.5f} {float(log_scale(s[1])):.5f} {float(log_scale(s[2])):.5f} "
                            f"{float(r[3]):.6f} {float(r[0]):.6f} {float(r[1]):.6f} {float(r[2]):.6f}\\n"
                        )
                return
            with path.open("wb") as f:
                f.write(("\\n".join(header) + "\\n").encode("ascii"))
                for p, c, o, s, r in zip(positions, colors, opacity, scale, rotations):
                    rgb = np.clip(np.round(c * 255.0), 0, 255).astype(np.uint8)
                    f.write(struct.pack(
                        "<fffBBBffffffff",
                        float(p[0]), float(p[1]), float(p[2]),
                        int(rgb[0]), int(rgb[1]), int(rgb[2]),
                        float(logit(o)),
                        float(log_scale(s[0])), float(log_scale(s[1])), float(log_scale(s[2])),
                        float(r[3]), float(r[0]), float(r[1]), float(r[2]),
                    ))

        def write_training_metrics(path, records):
            metrics_path = Path(path).with_suffix(".training_metrics.jsonl")
            metrics_path.parent.mkdir(parents=True, exist_ok=True)
            metrics_path.write_text("\\n".join(json.dumps(record, sort_keys=True) for record in records) + "\\n")
            return metrics_path

        def compute_loss_terms(position_values, color_values, opacity_values, scale_values, camera_origins, camera_rays, observed_colors, observed_depths, observed_depth_weights):
            centroid = mx.mean(position_values, axis=0, keepdims=True)
            origin_to_splat = position_values - camera_origins
            projected_distance = mx.sum(origin_to_splat * camera_rays, axis=1, keepdims=True)
            closest_on_ray = camera_origins + camera_rays * projected_distance
            ray_alignment = mx.mean((position_values - closest_on_ray) ** 2)
            forward_depth = mx.mean(mx.maximum(0.05 - projected_distance, 0.0) ** 2)
            depth_prior = mx.mean(observed_depth_weights * (projected_distance - observed_depths) ** 2)
            photometric = mx.mean((mx.clip(color_values, 0.0, 1.0) - observed_colors) ** 2)
            spatial_reg = mx.mean((position_values - centroid) ** 2) * 0.0005
            color_reg = mx.mean((color_values - mx.clip(color_values, 0.0, 1.0)) ** 2)
            opacity_reg = mx.mean((mx.sigmoid(opacity_values) - 0.75) ** 2) * 0.01
            scale_reg = mx.mean((mx.exp(scale_values) - 0.05) ** 2) * 0.01
            total = photometric + ray_alignment * 0.05 + forward_depth * 0.05 + depth_prior * 0.15 + spatial_reg + color_reg + opacity_reg + scale_reg
            return {
                "total": total,
                "photometric_rgb": photometric,
                "camera_ray_alignment": ray_alignment,
                "positive_depth": forward_depth,
                "arkit_lidar_depth_prior": depth_prior,
                "spatial_regularization": spatial_reg,
                "color_regularization": color_reg,
                "opacity_regularization": opacity_reg,
                "scale_regularization": scale_reg,
            }

        def scalar_terms(terms):
            return {key: float(value) for key, value in terms.items()}

        def output_format_for_path(path, force_ascii):
            if force_ascii:
                return "ascii_ply"
            return "binary_little_endian_ply"

        def stable_file_checksum(path):
            import hashlib
            digest = hashlib.sha256()
            with Path(path).open("rb") as f:
                for block in iter(lambda: f.read(1024 * 1024), b""):
                    digest.update(block)
            return digest.hexdigest()

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--frames", required=True)
            parser.add_argument("--depth-priors")
            parser.add_argument("--output", required=True)
            parser.add_argument("--splats-per-frame", type=int, default=24)
            parser.add_argument("--epochs", type=int, default=25)
            parser.add_argument("--ascii-ply", action="store_true", help="Write an ASCII PLY for inspection; binary little-endian PLY is the default production format.")
            args = parser.parse_args()

            frames = load_jsonl(args.frames)
            depth_priors = load_depth_priors(args.depth_priors)
            if not frames:
                raise ValueError("No training frames were provided.")
            seed_positions, seed_colors, source_origins, source_rays, target_colors, target_depths, depth_weights = seed_gaussians(
                frames,
                depth_priors,
                max(args.splats_per_frame, 1),
            )
            if len(seed_positions) == 0:
                raise ValueError("No trainable frames were available after split and tracking-quality filtering.")
            positions = mx.array(seed_positions)
            colors = mx.array(seed_colors)
            camera_origins = mx.array(source_origins)
            camera_rays = mx.array(source_rays)
            observed_colors = mx.array(target_colors)
            observed_depths = mx.array(target_depths)
            observed_depth_weights = mx.array(depth_weights)
            opacity_logits = mx.zeros((seed_positions.shape[0],), dtype=mx.float32)
            log_scale = mx.full((seed_positions.shape[0], 3), -3.0, dtype=mx.float32)
            learning_rate = 1e-3

            def loss_fn(position_values, color_values, opacity_values, scale_values):
                return compute_loss_terms(
                    position_values,
                    color_values,
                    opacity_values,
                    scale_values,
                    camera_origins,
                    camera_rays,
                    observed_colors,
                    observed_depths,
                    observed_depth_weights,
                )["total"]

            grad_fn = mx.grad(loss_fn, argnums=[0, 1, 2, 3])
            metric_records = []
            for epoch in range(args.epochs):
                grads = grad_fn(positions, colors, opacity_logits, log_scale)
                positions = positions - learning_rate * grads[0]
                colors = colors - learning_rate * grads[1]
                opacity_logits = opacity_logits - learning_rate * grads[2]
                log_scale = log_scale - learning_rate * grads[3]
                mx.eval(positions, colors, opacity_logits, log_scale)
                terms = compute_loss_terms(
                    positions,
                    colors,
                    opacity_logits,
                    log_scale,
                    camera_origins,
                    camera_rays,
                    observed_colors,
                    observed_depths,
                    observed_depth_weights,
                )
                mx.eval(*terms.values())
                metric_record = {"epoch": epoch, **scalar_terms(terms)}
                metric_records.append(metric_record)
                if epoch % max(args.epochs // 5, 1) == 0:
                    print(f"epoch={epoch} loss={metric_record['total']:.6f} photometric={metric_record['photometric_rgb']:.6f} depth={metric_record['arkit_lidar_depth_prior']:.6f}")

            rotations = np.asarray([gaussian_rotation_from_ray(ray) for ray in source_rays], dtype=np.float32)
            write_ply(
                args.output,
                np.array(positions),
                np.clip(np.array(colors), 0.0, 1.0),
                np.array(mx.sigmoid(opacity_logits)),
                np.array(mx.exp(log_scale)),
                rotations,
                ascii_output=args.ascii_ply,
            )
            metrics_path = write_training_metrics(args.output, metric_records)
            summary = {
                "frames": len(frames),
                "train_frames": len([frame for frame in frames if frame.get("split") == "train"]),
                "validation_frames": len([frame for frame in frames if frame.get("split") == "validation"]),
                "calibrated_frames": len([frame for frame in frames if frame.get("intrinsics") is not None]),
                "lidar_depth_priors": len(depth_priors),
                "depth_supervised_splats": int(np.count_nonzero(depth_weights)),
                "splats": int(seed_positions.shape[0]),
                "output": str(Path(args.output).resolve()),
                "output_format": output_format_for_path(args.output, args.ascii_ply),
                "output_sha256": stable_file_checksum(args.output),
                "metrics": str(metrics_path.resolve()),
                "final_metrics": metric_records[-1] if metric_records else {},
                "runtime": "Apple MLX",
                "trainer": {
                    "framework": "MLX",
                    "device_memory_model": "Apple Silicon unified memory",
                    "output_gaussian_fields": ["position", "rgb", "logit_opacity", "log_anisotropic_scale", "wxyz_ray_aligned_rotation"],
                },
                "loss_terms": ["photometric_rgb", "camera_ray_alignment", "arkit_lidar_depth_prior", "positive_depth", "scale_opacity_regularization"],
            }
            Path(args.output).with_suffix(".training_summary.json").write_text(json.dumps(summary, indent=2))
            print(json.dumps(summary, indent=2))

        if __name__ == "__main__":
            main()
        """
    }
}

private struct SplatTrainingFrameRecord: Codable {
    var index: Int
    var split: SplatTrainingFrameRole
    var imageURL: URL
    var timestamp: TimeInterval
    var position: SIMD3<Double>
    var orientation: SIMD4<Double>
    var intrinsics: CameraIntrinsics?
    var resolution: Resolution?
    var trackingQuality: TrackingQuality
}

private struct SplatTrainingDepthPriorRecord: Codable {
    var index: Int
    var depthURL: URL
    var confidenceURL: URL?
    var metadataURL: URL
    var timestamp: TimeInterval
    var position: SIMD3<Double>
    var orientation: SIMD4<Double>
}

private struct NerfstudioTransforms: Codable {
    var camera_model: String
    var coordinate_system: String
    var fl_x: Double?
    var fl_y: Double?
    var cx: Double?
    var cy: Double?
    var w: Int?
    var h: Int?
    var ply_file_path: String?
    var frames: [NerfstudioTransformFrame]
}

private struct NerfstudioTransformFrame: Codable {
    var file_path: String
    var transform_matrix: [[Double]]
    var fl_x: Double
    var fl_y: Double
    var cx: Double
    var cy: Double
    var w: Int
    var h: Int
    var split: String
    var timestamp: TimeInterval
    var tracking_quality: String
}

private struct ProductionSplatDatasetMetadata: Codable {
	    var id: String
	    var frameCount: Int
	    var lidarDepthPriorCount: Int
	    var transcodedImageCount: Int
	    var depthInitializationPointCount: Int
	    var depthInitializationPointCloudURL: URL?
	    var coordinateSystem: String
    var sourceManifestExpectedOutput: URL
    var notes: [String]
}

private struct DepthInitializationPointCloudSummary {
    var pointCount: Int
    var url: URL
}

private struct DepthInitializationPoint {
    var position: SIMD3<Double>
    var color: SIMD3<UInt8>
}

public enum SplatTrainingPackageBuildError: Error, LocalizedError, CustomStringConvertible {
    case invalidTrainingInputs([String])

    public var errorDescription: String? {
        description
    }

    public var description: String {
        switch self {
        case .invalidTrainingInputs(let issues):
            return "Splat training inputs are not usable:\n- \(issues.joined(separator: "\n- "))"
        }
    }
}

private struct SplatTrainingFrameSplit {
    let frameCount: Int

    var trainingCount: Int {
        (0..<frameCount).filter { role(for: $0) == .train }.count
    }

    var validationCount: Int {
        (0..<frameCount).filter { role(for: $0) == .validation }.count
    }

    func role(for index: Int) -> SplatTrainingFrameRole {
        guard frameCount > 1 else { return .train }
        return (index + 1).isMultiple(of: 5) || index == frameCount - 1 ? .validation : .train
    }
}
