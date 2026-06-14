import Foundation
import RobotVisionLabCore
import simd

enum SplatTrainingCLIError: Error {
    case missingPreparedManifest(URL)
}

struct RobotVisionLabCLI {
    static func main() throws {
        let outputDirectory = parseOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if let packageURL = parseValidationPackageURL() {
            try validatePackage(at: packageURL)
            return
        }

        let recipe = try sampleRecipe()
        let manifest = DatasetGenerator().makeManifest(
            recipe: recipe,
            outputDirectory: outputDirectory,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try DatasetExporter().writeManifestAndLabels(manifest, to: outputDirectory)
        if CommandLine.arguments.contains("--render-preview") {
            try DatasetExporter().renderFrames(manifest, to: outputDirectory, renderer: PreviewSyntheticRenderer())
        }
        if CommandLine.arguments.contains("--render-splat-points") {
            try renderSplatPointFrames(manifest: manifest, outputDirectory: outputDirectory)
            print("Rendered splat point-projection RGB artifacts")
        }
        if CommandLine.arguments.contains("--render-metal-splats") {
            try renderMetalSplatFrames(manifest: manifest, outputDirectory: outputDirectory)
            print("Rendered native Metal Gaussian splat artifacts")
        }
        if CommandLine.arguments.contains("--augment-dataset") {
            let report = try DatasetAugmentor().augmentPPMImagesAndPoseLabels(
                manifest: manifest,
                datasetDirectory: outputDirectory,
                seed: parseAugmentationSeed()
            )
            let reportURL = outputDirectory.appendingPathComponent("augmentation_report.json")
            try DatasetAugmentor().writeReport(report, to: reportURL)
            print("Wrote augmentation report to \(reportURL.path)")
        }
        if CommandLine.arguments.contains("--metal-render-plan") {
            let plan = MetalRenderPlanner().makePlan(from: recipe)
            let report = MetalRenderPlanner().validate(
                plan: plan,
                capabilities: MetalDeviceProbe().capabilities()
            )
            let reportURL = outputDirectory.appendingPathComponent("metal_render_plan_report.json")
            try MetalRenderPlanReportWriter().write(report, to: reportURL)
            print("Wrote Metal render plan report to \(reportURL.path)")
        }
        if CommandLine.arguments.contains("--export-sample-capture") {
            let captureURL = outputDirectory.appendingPathComponent("CaptureBundle", isDirectory: true)
            _ = try CaptureBundleExporter().writeBundle(
                scanSession: sampleScanSession(),
                capturePlan: sampleCapturePlan(),
                to: captureURL
            )
            print("Wrote sample capture bundle to \(captureURL.path)")
        }
        if let robotCaptureURL = parseRobotCaptureImportURL() {
            let importer = RobotCaptureImporter()
            let imported = try importer.importPackage(at: robotCaptureURL)
            let report = importer.makeReport(
                for: imported,
                packageURL: robotCaptureURL,
                importedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let reportURL = outputDirectory.appendingPathComponent("robotcapture_import_report.json")
            try importer.writeReport(report, to: reportURL)
            let preparation = try RobotCapturePreparer().prepare(
                importedCapture: imported,
                outputDirectory: outputDirectory.appendingPathComponent("PreparedCapture", isDirectory: true),
                holdoutEveryNthFrame: intValue(for: "--capture-holdout-every", default: 5),
                preparedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            print("Imported robot capture package \(report.manifestID) with \(report.frameCount) frame records")
            print("Wrote robot capture import report to \(reportURL.path)")
            print("Prepared capture route with \(preparation.report.routeKeyframeCount) keyframes")
        }
        if CommandLine.arguments.contains("--expand-capture-route") {
            let expanded = try expandCaptureRouteIfRequested(recipe: recipe, outputDirectory: outputDirectory)
            print("Expanded capture route to \(expanded.report.expandedKeyframeCount) keyframes")
        }
        if CommandLine.arguments.contains("--align-capture-route") {
            let aligned = try alignCaptureRouteIfRequested(recipe: recipe, outputDirectory: outputDirectory)
            print("Aligned capture route to scene coordinates with \(aligned.report.alignedKeyframeCount) keyframes")
        }
        if CommandLine.arguments.contains("--plan-splat-training") {
            let reportURL = outputDirectory.appendingPathComponent("splat_training_report.json")
            let manifestURL = try parseSplatTrainingManifestURL(outputDirectory: outputDirectory)
            let job = try splatTrainingJob(outputDirectory: outputDirectory, manifestURL: manifestURL)
            let report = SplatTrainingReportBuilder().dryRunReport(
                job: job,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            try SplatTrainingReportWriter().write(report, to: reportURL)
            print("Using splat training manifest \(manifestURL.path)")
            print("Wrote Apple-native splat training plan to \(reportURL.path)")
        }
        if CommandLine.arguments.contains("--write-model-adapter-schemas") {
            try writeModelAdapterSchemas(outputDirectory: outputDirectory)
        }
        if CommandLine.arguments.contains("--write-mlx-training-package") {
            try writeMLXTrainingPackage(manifest: manifest, outputDirectory: outputDirectory)
        }
        if CommandLine.arguments.contains("--evaluate-baseline") || CommandLine.arguments.contains("--evaluate-coreml") || CommandLine.arguments.contains("--plan-mlx-evaluation") {
            try runModelEvaluation(manifest: manifest, outputDirectory: outputDirectory)
        }
        if CommandLine.arguments.contains("--export-robotscene") {
            let packageURL = outputDirectory.appendingPathComponent("Project.robotscene", isDirectory: true)
            let evaluationURL = outputDirectory.appendingPathComponent("evaluation_report.json")
            _ = try RobotScenePackageExporter().writeRobotScenePackage(
                manifest: manifest,
                evaluationReportURL: FileManager.default.fileExists(atPath: evaluationURL.path) ? evaluationURL : nil,
                capturePackageURL: outputDirectory.appendingPathComponent("CaptureBundle/robotcapture.json"),
                to: packageURL
            )
            print("Wrote robot scene package to \(packageURL.path)")
        }
        let manifestURL = outputDirectory.appendingPathComponent("dataset.json")
        print("Wrote \(manifest.frames.count) planned frames to \(manifestURL.path)")
        if CommandLine.arguments.contains("--render-preview") {
            print("Rendered preview RGB/depth/segmentation/obstacle artifacts")
        }
    }

    private static func parseOutputDirectory() -> URL {
        let args = CommandLine.arguments
        guard let outputIndex = args.firstIndex(of: "--output"), args.indices.contains(outputIndex + 1) else {
            return URL(fileURLWithPath: "GeneratedDataset", isDirectory: true)
        }
        return URL(fileURLWithPath: args[outputIndex + 1], isDirectory: true)
    }

    private static func sampleRecipe() throws -> DatasetRecipe {
        let scene: GaussianSplatScene
        if let splatURL = parseSplatURL() {
            let asset = try GaussianSplatImporter().inspect(url: splatURL)
            scene = asset.makeScene(
                id: splatURL.deletingPathExtension().lastPathComponent,
                roomPlanModelURL: URL(fileURLWithPath: "Assets/RoomPlan/sample_room.usdz")
            )
            print("Imported \(asset.format.rawValue) splat with \(asset.vertexCount) vertices from \(splatURL.path)")
        } else {
            scene = GaussianSplatScene(
                id: "sample-room-splat",
                source: .importedPLY(URL(fileURLWithPath: "Assets/Splats/sample_room.ply")),
                bounds: AxisAlignedBounds(
                    minimum: SIMD3<Double>(-3.0, 0.0, -3.0),
                    maximum: SIMD3<Double>(3.0, 2.8, 3.0)
                ),
                roomPlanModelURL: URL(fileURLWithPath: "Assets/RoomPlan/sample_room.usdz")
            )
        }

        let camera = RobotCameraRig(
            name: "mobile-base-front-camera",
            mountHeightMeters: 0.62,
            intrinsics: .fromHorizontalFOV(width: 1280, height: 720, horizontalFOVDegrees: 82),
            bodyToCamera: Transform3D(translation: SIMD3<Double>(0, 0.62, 0.08))
        )

        let target = NavigationTarget(label: "charging_dock", position: SIMD3<Double>(2.4, 0.0, -1.8))
        let path = try captureRouteIfRequested(target: target)
            ?? generatedPathIfRequested(scene: scene, target: target)
            ?? RobotPath(keyframes: [
            RobotPathKeyframe(timestamp: 0.0, pose: Pose3D(position: SIMD3<Double>(-2.0, 0.0, 1.6)), navigationTarget: target),
            RobotPathKeyframe(timestamp: 0.5, pose: Pose3D(position: SIMD3<Double>(-1.2, 0.0, 1.0)), navigationTarget: target),
            RobotPathKeyframe(timestamp: 1.0, pose: Pose3D(position: SIMD3<Double>(-0.2, 0.0, 0.4)), navigationTarget: target),
            RobotPathKeyframe(timestamp: 1.5, pose: Pose3D(position: SIMD3<Double>(0.8, 0.0, -0.6)), navigationTarget: target),
            RobotPathKeyframe(timestamp: 2.0, pose: Pose3D(position: SIMD3<Double>(1.8, 0.0, -1.4)), navigationTarget: target)
        ])

        return DatasetRecipe(
            id: "sample-robot-camera-dataset",
            scene: scene,
            cameraRig: camera,
            path: path,
            requestedProducts: [.rgb, .depth, .pose, .segmentation, .obstacleMask, .navigationTarget],
            augmentations: [
                .exposureEV(-0.5),
                .gaussianNoise(sigma: 0.015),
                .motionBlur(samples: 5, shutterSeconds: 1.0 / 60.0),
                .compressionJPEG(quality: 0.82),
                .cameraHeightJitterMeters(0.03),
                .yawJitterDegrees(2.0)
            ],
            labelSources: [
                .roomPlanGeometry(URL(fileURLWithPath: "Assets/RoomPlan/sample_room.usdz")),
                .manualAnnotations(URL(fileURLWithPath: "Assets/Labels/sample_room_labels.json"))
            ]
        )
    }

    private static func parseSplatURL() -> URL? {
        let args = CommandLine.arguments
        guard let splatIndex = args.firstIndex(of: "--splat"), args.indices.contains(splatIndex + 1) else {
            return nil
        }
        return URL(fileURLWithPath: args[splatIndex + 1])
    }

    private static func parseRobotCaptureImportURL() -> URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--import-robotcapture"), args.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: args[index + 1])
    }

    private static func parseValidationPackageURL() -> URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--validate-package"), args.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: args[index + 1])
    }

    private static func validatePackage(at packageURL: URL) throws {
        let migrator = SharedProjectPackageMigrator()
        let report: PackageValidationReport
        if packageURL.pathExtension == "robotscene"
            || FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("robotscene.json").path) {
            report = try migrator.migrateRobotScenePackage(at: packageURL)
        } else {
            report = try migrator.migrateRobotCapturePackage(at: packageURL)
        }
        print("Validated \(report.packageKind) package \(report.packageID)")
        print("Schema \(report.schemaVersion.major).\(report.schemaVersion.minor).\(report.schemaVersion.patch), \(report.artifactCount) artifacts, \(report.totalByteCount) bytes")
        if report.hasErrors {
            print("Validation completed with errors")
        }
    }

    private static func captureRouteIfRequested(target: NavigationTarget) throws -> RobotPath? {
        guard let routeURL = routeURLForDataset() else {
            return nil
        }
        let route = try JSONDecoder.robotVisionLabDecoder.decode(RobotPath.self, from: Data(contentsOf: routeURL))
        print("Loaded capture route with \(route.keyframes.count) keyframes from \(routeURL.path)")
        return RobotPath(keyframes: route.keyframes.map {
            RobotPathKeyframe(timestamp: $0.timestamp, pose: $0.pose, navigationTarget: $0.navigationTarget ?? target)
        })
    }

    private static func routeURLForDataset() -> URL? {
        if CommandLine.arguments.contains("--use-expanded-route") {
            let expandedURL = parseOutputDirectory()
                .appendingPathComponent("ExpandedRoutes", isDirectory: true)
                .appendingPathComponent("expanded_robot_route.json")
            if FileManager.default.fileExists(atPath: expandedURL.path) {
                return expandedURL
            }
        }
        if CommandLine.arguments.contains("--use-aligned-route") {
            let alignedURL = parseOutputDirectory()
                .appendingPathComponent("AlignedCapture", isDirectory: true)
                .appendingPathComponent("aligned_capture_route.json")
            if FileManager.default.fileExists(atPath: alignedURL.path) {
                return alignedURL
            }
        }
        return stringValue(for: "--capture-route").map { URL(fileURLWithPath: $0) }
    }

    private static func alignCaptureRouteIfRequested(recipe: DatasetRecipe, outputDirectory: URL) throws -> RouteAlignmentOutput {
        let routeURL = stringValue(for: "--capture-route")
            .map { URL(fileURLWithPath: $0) }
            ?? outputDirectory
            .appendingPathComponent("PreparedCapture", isDirectory: true)
            .appendingPathComponent("capture_route.json")
        let route = try JSONDecoder.robotVisionLabDecoder.decode(RobotPath.self, from: Data(contentsOf: routeURL))
        let request = RouteAlignmentRequest(
            sourceRoute: route,
            sceneBounds: recipe.scene.bounds,
            method: parseRouteAlignmentMethod(),
            preserveVerticalScale: !CommandLine.arguments.contains("--align-scale-y")
        )
        return try RobotRouteAligner().align(
            request: request,
            outputDirectory: outputDirectory.appendingPathComponent("AlignedCapture", isDirectory: true),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func parseRouteAlignmentMethod() -> RouteAlignmentMethod {
        switch stringValue(for: "--route-alignment-method") {
        case "identity":
            return .identity
        case "control-points":
            return .controlPointCentroids
        default:
            return .routeBoundsToSceneBounds
        }
    }

    private static func expandCaptureRouteIfRequested(recipe: DatasetRecipe, outputDirectory: URL) throws -> RobotRouteExpansionOutput {
        let routeURL = routeURLForExpansion(outputDirectory: outputDirectory)
        let route = try JSONDecoder.robotVisionLabDecoder.decode(RobotPath.self, from: Data(contentsOf: routeURL))
        let request = RobotRouteExpansionRequest(
            sourceRoute: route,
            lateralOffsetsMeters: doubleListValue(for: "--route-lateral-offsets", default: [-0.25, 0, 0.25]),
            cameraHeightOffsetsMeters: doubleListValue(for: "--route-height-offsets", default: [-0.08, 0, 0.08]),
            yawOffsetsDegrees: doubleListValue(for: "--route-yaw-offsets", default: [-8, 0, 8]),
            bounds: recipe.scene.bounds,
            navigationTarget: recipe.path.keyframes.first?.navigationTarget
        )
        return try RobotRouteExpander().expand(
            request: request,
            outputDirectory: outputDirectory.appendingPathComponent("ExpandedRoutes", isDirectory: true),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func routeURLForExpansion(outputDirectory: URL) -> URL {
        if CommandLine.arguments.contains("--use-aligned-route") {
            let alignedURL = outputDirectory
                .appendingPathComponent("AlignedCapture", isDirectory: true)
                .appendingPathComponent("aligned_capture_route.json")
            if FileManager.default.fileExists(atPath: alignedURL.path) {
                return alignedURL
            }
        }
        return stringValue(for: "--capture-route")
            .map { URL(fileURLWithPath: $0) }
            ?? outputDirectory
            .appendingPathComponent("PreparedCapture", isDirectory: true)
            .appendingPathComponent("capture_route.json")
    }

    private static func generatedPathIfRequested(scene: GaussianSplatScene, target: NavigationTarget) -> RobotPath? {
        guard let mode = stringValue(for: "--path-mode") else {
            return nil
        }
        let bounds = insetXZBounds(scene.bounds, by: doubleValue(for: "--path-inset", default: 0.25))
        let request: RobotPathGenerationRequest
        switch mode {
        case "lawnmower":
            request = RobotPathGenerationRequest(
                strategy: .lawnmower(
                    rows: intValue(for: "--path-rows", default: 10),
                    columns: intValue(for: "--path-columns", default: 10)
                ),
                bounds: bounds,
                robotHeightMeters: 0,
                frameInterval: 1.0 / doubleValue(for: "--path-fps", default: 30),
                navigationTarget: target
            )
        case "random":
            request = RobotPathGenerationRequest(
                strategy: .randomWalk(
                    frameCount: intValue(for: "--frame-count", default: 300),
                    stepMeters: doubleValue(for: "--path-step", default: 0.15),
                    seed: uint64Value(for: "--path-seed", default: 1)
                ),
                bounds: bounds,
                robotHeightMeters: 0,
                frameInterval: 1.0 / doubleValue(for: "--path-fps", default: 30),
                navigationTarget: target
            )
        default:
            return nil
        }
        return RobotPathGenerator().generate(request)
    }

    private static func insetXZBounds(_ bounds: AxisAlignedBounds, by inset: Double) -> AxisAlignedBounds {
        let minX = min(bounds.minimum.x + inset, bounds.maximum.x)
        let maxX = max(bounds.maximum.x - inset, minX)
        let minZ = min(bounds.minimum.z + inset, bounds.maximum.z)
        let maxZ = max(bounds.maximum.z - inset, minZ)
        return AxisAlignedBounds(
            minimum: SIMD3<Double>(minX, bounds.minimum.y, minZ),
            maximum: SIMD3<Double>(maxX, bounds.maximum.y, maxZ)
        )
    }

    private static func parseAugmentationSeed() -> UInt64 {
        uint64Value(for: "--augmentation-seed", default: 0)
    }

    private static func stringValue(for flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            let prefix = "\(flag)="
            return args.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        return args[index + 1]
    }

    private static func intValue(for flag: String, default defaultValue: Int) -> Int {
        stringValue(for: flag).flatMap(Int.init) ?? defaultValue
    }

    private static func uint64Value(for flag: String, default defaultValue: UInt64) -> UInt64 {
        stringValue(for: flag).flatMap(UInt64.init) ?? defaultValue
    }

    private static func doubleValue(for flag: String, default defaultValue: Double) -> Double {
        stringValue(for: flag).flatMap(Double.init) ?? defaultValue
    }

    private static func doubleListValue(for flag: String, default defaultValue: [Double]) -> [Double] {
        guard let value = stringValue(for: flag) else {
            return defaultValue
        }
        let values = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return values.isEmpty ? defaultValue : values
    }

    private static func runModelEvaluation(manifest: DatasetManifest, outputDirectory: URL) throws {
        let datasetManifestURL = outputDirectory.appendingPathComponent("dataset.json")
        let tasks: Set<VisionTask> = [.navigationTargetDetection, .obstacleDetection, .segmentation, .failureCaseDetection]

        if CommandLine.arguments.contains("--plan-mlx-evaluation") {
            let expectedReportURL = outputDirectory.appendingPathComponent("evaluation_report.json")
            let modelURL = stringValue(for: "--evaluate-model").map { URL(fileURLWithPath: $0) }
            let request = ModelEvaluationRequest(
                id: "mlx-evaluation",
                model: LocalModelReference(name: modelURL?.lastPathComponent ?? "mlx-model", runtime: .mlx, url: modelURL),
                datasetManifestURL: datasetManifestURL,
                tasks: tasks
            )
            let plan = MLXEvaluationPlan(
                request: request,
                datasetManifestURL: datasetManifestURL,
                expectedReportURL: expectedReportURL,
                notes: [
                    "Use Apple MLX on Apple Silicon for research and fine-tuning.",
                    "Promote deployment models through Core ML/Core AI app integration.",
                    "The product evaluates through Apple-native app integrations."
                ]
            )
            let planURL = outputDirectory.appendingPathComponent("mlx_evaluation_plan.json")
            try MLXEvaluationPlanWriter().write(plan, to: planURL)
            print("Wrote Apple MLX evaluation plan to \(planURL.path)")
            return
        }

        let reportURL = outputDirectory.appendingPathComponent("evaluation_report.json")
        let report: ModelEvaluationReport
        if CommandLine.arguments.contains("--evaluate-coreml") {
            let modelURL = stringValue(for: "--evaluate-model").map { URL(fileURLWithPath: $0) }
            let request = ModelEvaluationRequest(
                id: "coreml-evaluation",
                model: LocalModelReference(name: modelURL?.lastPathComponent ?? "CoreMLModel", runtime: .coreML, url: modelURL),
                datasetManifestURL: datasetManifestURL,
                tasks: tasks
            )
            report = try CoreMLDatasetEvaluator().evaluate(
                request: request,
                manifest: manifest,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        } else {
            let request = ModelEvaluationRequest(
                id: "baseline-preview-evaluation",
                model: LocalModelReference(name: "manifest-baseline", runtime: .baseline),
                datasetManifestURL: datasetManifestURL,
                tasks: tasks
            )
            report = BaselineDatasetEvaluator().evaluate(
                request: request,
                manifest: manifest,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
        try EvaluationReportWriter().write(report, to: reportURL)
        print("Wrote evaluation report to \(reportURL.path)")
    }

    private static func writeModelAdapterSchemas(outputDirectory: URL) throws {
        let schemaDirectory = outputDirectory.appendingPathComponent("ModelSchemas", isDirectory: true)
        let writer = NativeModelAdapterSchemaWriter()
        try writer.write(
            .defaultCoreMLVisionSchema(),
            to: schemaDirectory.appendingPathComponent("coreml_robot_vision_schema.json")
        )
        try writer.write(
            .defaultMLXTrainingSchema(),
            to: schemaDirectory.appendingPathComponent("mlx_robot_vision_training_schema.json")
        )
        if let modelURL = stringValue(for: "--evaluate-model").map({ URL(fileURLWithPath: $0) }) {
            let inspected = try CoreMLModelSchemaInspector().inspect(modelURL: modelURL)
            try writer.write(inspected, to: schemaDirectory.appendingPathComponent("inspected_coreml_schema.json"))
        }
        print("Wrote native model adapter schemas to \(schemaDirectory.path)")
    }

    private static func writeMLXTrainingPackage(manifest: DatasetManifest, outputDirectory: URL) throws {
        let datasetManifestURL = outputDirectory.appendingPathComponent("dataset.json")
        let packageDirectory = outputDirectory.appendingPathComponent("MLXTrainingPackage", isDirectory: true)
        let package = try MLXTrainingPackageBuilder().writePackage(
            manifest: manifest,
            datasetManifestURL: datasetManifestURL,
            outputDirectory: packageDirectory
        )
        print("Wrote Apple Silicon MLX training package to \(packageDirectory.path)")
        print("Training script: \(package.trainScriptURL.path)")
        print("Core ML export script: \(package.exportScriptURL.path)")
    }

    private static func renderSplatPointFrames(manifest: DatasetManifest, outputDirectory: URL) throws {
        let renderer = SplatPointProjectionRenderer()
        for frame in manifest.frames {
            try renderer.renderSynchronously(
                frame: frame,
                scene: manifest.scene,
                cameraRig: manifest.cameraRig,
                outputDirectory: outputDirectory
            )
        }
    }

    private static func renderMetalSplatFrames(manifest: DatasetManifest, outputDirectory: URL) throws {
        let renderer = try MetalGaussianSplatRenderer(configuration: MetalGaussianSplatRenderConfiguration(
            tileSize: intValue(for: "--metal-tile-size", default: 16),
            maxSplatsPerFrame: stringValue(for: "--metal-max-splats").flatMap(Int.init),
            streamingChunkSplatCount: stringValue(for: "--metal-streaming-chunk-splats").flatMap(Int.init)
        ))
        let report = try renderer.renderDataset(manifest, outputDirectory: outputDirectory)
        let reportURL = outputDirectory.appendingPathComponent("metal_splat_render_report.json")
        try MetalSplatRenderReportWriter().write(report, to: reportURL)
        print("Wrote Metal splat render report to \(reportURL.path)")
    }

    private static func parseSplatTrainingManifestURL(outputDirectory: URL) throws -> URL {
        let explicitURL = stringValue(for: "--splat-training-manifest").map { URL(fileURLWithPath: $0) }
        let preparedURL = outputDirectory
            .appendingPathComponent("PreparedCapture", isDirectory: true)
            .appendingPathComponent("prepared_splat_training_manifest.json")
        let url = explicitURL ?? preparedURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if explicitURL != nil {
            throw SplatTrainingCLIError.missingPreparedManifest(url)
        }
        return try writeSampleSplatTrainingManifest(outputDirectory: outputDirectory)
    }

    private static func splatTrainingJob(outputDirectory: URL, manifestURL: URL) throws -> SplatTrainingJob {
        let manifest = try JSONDecoder.robotVisionLabDecoder.decode(
            SplatTrainingManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        return SplatTrainingJob(
            id: "\(manifest.id)-job",
            manifest: manifest,
            backend: AppleNativeTrainingBackend(),
            mode: .planning
        )
    }

    private static func writeSampleSplatTrainingManifest(outputDirectory: URL) throws -> URL {
        let manifest = SplatTrainingManifest(
            id: "sample-room-scan-splat-training",
            imageFrames: sampleScanSession().rgbFrames.map {
                SplatTrainingFrame(imageURL: $0.imageURL, pose: $0.pose, timestamp: $0.timestamp)
            },
            roomPlanGeometryURL: URL(fileURLWithPath: "CaptureBundle/roomplan/room.usdz"),
            objectGeometryURLs: [
                URL(fileURLWithPath: "CaptureBundle/object-capture/chair.usdz"),
                URL(fileURLWithPath: "CaptureBundle/object-capture/table.usdz")
            ],
            expectedOutput: SplatTrainingOutput(
                targetURL: outputDirectory.appendingPathComponent("splats/sample-room-scan.ply")
            )
        )
        let manifestURL = outputDirectory.appendingPathComponent("sample_splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        return manifestURL
    }

    private static func sampleCapturePlan() -> CapturePlan {
        CapturePlan(
            id: "sample-iphone-lidar-room-capture",
            captureModes: [.roomPlan, .rgbVideo, .lidarDepth, .objectCapture],
            roomPlan: RoomPlanOptions(),
            objectCapture: ObjectCaptureOptions(objectLabels: ["chair", "table", "charging_dock"]),
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720),
            lidar: LiDAROptions()
        )
    }

    private static func sampleScanSession() -> ScanSession {
        ScanSession(
            id: "sample-room-scan",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            rgbFrames: [
                CapturedRGBFrame(
                    imageURL: URL(fileURLWithPath: "CaptureBundle/rgb/frame_000000.heic"),
                    pose: Pose3D(position: SIMD3<Double>(-2, 1.4, 1.5)),
                    timestamp: 0
                ),
                CapturedRGBFrame(
                    imageURL: URL(fileURLWithPath: "CaptureBundle/rgb/frame_000001.heic"),
                    pose: Pose3D(position: SIMD3<Double>(-1, 1.4, 0.9)),
                    timestamp: 0.033
                ),
                CapturedRGBFrame(
                    imageURL: URL(fileURLWithPath: "CaptureBundle/rgb/frame_000002.heic"),
                    pose: Pose3D(position: SIMD3<Double>(0, 1.4, 0.2)),
                    timestamp: 0.066
                )
            ],
            lidarFrames: [
                CapturedLiDARFrame(
                    depthURL: URL(fileURLWithPath: "CaptureBundle/lidar/depth_000000.exr"),
                    confidenceURL: URL(fileURLWithPath: "CaptureBundle/lidar/confidence_000000.png"),
                    pose: Pose3D(position: SIMD3<Double>(-2, 1.4, 1.5)),
                    timestamp: 0
                )
            ],
            roomPlanModelURL: URL(fileURLWithPath: "CaptureBundle/roomplan/room.usdz"),
            objectCaptureAssetURLs: [
                URL(fileURLWithPath: "CaptureBundle/object-capture/chair.usdz"),
                URL(fileURLWithPath: "CaptureBundle/object-capture/table.usdz")
            ]
        )
    }
}

try RobotVisionLabCLI.main()
