import Foundation
import RobotSceneStudioVision
import RobotVisionLabCore
import simd

enum SplatTrainingCLIError: Error {
    case missingPreparedManifest(URL)
    case missingOutputDirectory
    case missingRequiredInput(String)
    case splatTrainingFailed(URL)
    case spatialReviewFailed(String)
}

extension SplatTrainingCLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingPreparedManifest(let url):
            "Missing prepared splat training manifest at \(url.path). Provide --splat-training-manifest or import/prepare a .robotcapture package first."
        case .missingOutputDirectory:
            "Missing --output <directory>. Production commands require an explicit workspace output directory."
        case .missingRequiredInput(let message):
            message
        case .splatTrainingFailed(let url):
            "Apple MLX splat training failed. Inspect \(url.path)."
        case .spatialReviewFailed(let message):
            message
        }
    }
}

struct RobotVisionLabCLI {
    static func main() throws {
        if let packageURL = parseValidationPackageURL() {
            try validatePackage(at: packageURL)
            return
        }
        if let packageURL = parseSpatialReviewValidationURL() {
            try validateSpatialReview(at: packageURL)
            return
        }

        let outputDirectory = try parseOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--render-dev-preview") || CommandLine.arguments.contains("--render-splat-points") {
            throw SplatTrainingCLIError.missingRequiredInput("Preview and point-projection render paths were removed from product CLI. Use --render-apple-native for native Metal Gaussian splat rendering.")
        }

        if CommandLine.arguments.contains("--export-demo-capture") {
            let captureURL = outputDirectory.appendingPathComponent("CaptureBundle", isDirectory: true)
            _ = try CaptureBundleExporter().writeBundle(
                scanSession: demoScanSession(),
                capturePlan: demoCapturePlan(),
                to: captureURL
            )
            print("Wrote demo capture bundle to \(captureURL.path)")
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
        if CommandLine.arguments.contains("--plan-splat-training") {
            let reportURL = outputDirectory.appendingPathComponent("splat_training_report.json")
            let manifestURL = try parseSplatTrainingManifestURL(outputDirectory: outputDirectory)
            let job = try splatTrainingJob(outputDirectory: outputDirectory, manifestURL: manifestURL)
            let report = SplatTrainingReportBuilder().preparationReport(
                job: job,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            try SplatTrainingReportWriter().write(report, to: reportURL)
            print("Using splat training manifest \(manifestURL.path)")
            print("Wrote Apple-native splat training plan to \(reportURL.path)")
        }
        if CommandLine.arguments.contains("--write-splat-training-package") {
            let manifestURL = try parseSplatTrainingManifestURL(outputDirectory: outputDirectory)
            let job = try splatTrainingJob(outputDirectory: outputDirectory, manifestURL: manifestURL)
            let package = try SplatTrainingPackageBuilder().writePackage(
                job: job,
                manifestURL: manifestURL,
                outputDirectory: outputDirectory.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
            )
            print("Wrote Apple-native splat training package to \(package.trainScriptURL.deletingLastPathComponent().path)")
            print("Frame index: \(package.frameIndexURL.path)")
            print("Training script: \(package.trainScriptURL.path)")
            print("Expected output: \(package.outputURL.path)")
        }
        if CommandLine.arguments.contains("--run-splat-training") {
            let manifestURL = try parseSplatTrainingManifestURL(outputDirectory: outputDirectory)
            let job = try splatTrainingJob(outputDirectory: outputDirectory, manifestURL: manifestURL)
            let package = try SplatTrainingPackageBuilder().writePackage(
                job: job,
                manifestURL: manifestURL,
                outputDirectory: outputDirectory.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
            )
            try runSplatTraining(package: package, job: job, outputDirectory: outputDirectory)
        }
        if CommandLine.arguments.contains("--write-model-adapter-schemas") {
            try writeModelAdapterSchemas(outputDirectory: outputDirectory)
        }

        if CommandLine.arguments.contains("--run-splat-training"), !hasDatasetActionFlag(), parseSplatURL() == nil, !routeURLArgumentIsPresent() {
            return
        }

        guard needsDatasetWorkflow() else {
            return
        }

        let recipe = try datasetRecipe()
        let manifest = DatasetGenerator().makeManifest(
            recipe: recipe,
            outputDirectory: outputDirectory,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try DatasetExporter().writeManifestAndLabels(manifest, to: outputDirectory)
        if CommandLine.arguments.contains("--render-apple-native") || CommandLine.arguments.contains("--render-metal-splats") {
            try renderMetalSplatFrames(manifest: manifest, outputDirectory: outputDirectory)
            _ = try DatasetExporter().writeStructuredGeometryProducts(manifest, to: outputDirectory)
            _ = try DatasetExporter().writeRenderedLiDARScans(manifest, to: outputDirectory)
            _ = try DatasetExporter().writeRenderedFailureLabels(manifest, to: outputDirectory)
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
        if CommandLine.arguments.contains("--expand-capture-route") {
            let expanded = try expandCaptureRouteIfRequested(recipe: recipe, outputDirectory: outputDirectory)
            print("Expanded capture route to \(expanded.report.expandedKeyframeCount) keyframes")
        }
        if CommandLine.arguments.contains("--align-capture-route") {
            let aligned = try alignCaptureRouteIfRequested(recipe: recipe, outputDirectory: outputDirectory)
            print("Aligned capture route to scene coordinates with \(aligned.report.alignedKeyframeCount) keyframes")
        }
        if CommandLine.arguments.contains("--write-mlx-training-package") {
            try writeMLXTrainingPackage(manifest: manifest, outputDirectory: outputDirectory)
        }
        if CommandLine.arguments.contains("--evaluate-baseline") {
            throw SplatTrainingCLIError.missingRequiredInput("--evaluate-baseline was removed. Evaluate a real Apple-native model with --evaluate-coreml --evaluate-model <Model.mlpackage>, or write an MLX evaluation plan with --plan-mlx-evaluation.")
        }
        if CommandLine.arguments.contains("--evaluate-coreml") || CommandLine.arguments.contains("--plan-mlx-evaluation") {
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
    }

    private static func needsDatasetWorkflow() -> Bool {
        hasDatasetActionFlag()
            || CommandLine.arguments.contains("--demo")
            || parseSplatURL() != nil
            || routeURLArgumentIsPresent()
    }

    private static func hasDatasetActionFlag() -> Bool {
        let datasetFlags = [
            "--render-apple-native",
            "--render-metal-splats",
            "--augment-dataset",
            "--metal-render-plan",
            "--expand-capture-route",
            "--align-capture-route",
            "--write-mlx-training-package",
            "--evaluate-coreml",
            "--plan-mlx-evaluation",
            "--export-robotscene"
        ]
        return datasetFlags.contains { CommandLine.arguments.contains($0) }
    }

    private static func routeURLArgumentIsPresent() -> Bool {
        CommandLine.arguments.contains("--capture-route")
            || CommandLine.arguments.contains("--use-aligned-route")
            || CommandLine.arguments.contains("--use-expanded-route")
            || CommandLine.arguments.contains("--path-mode")
    }

    private static func parseOutputDirectory() throws -> URL {
        let args = CommandLine.arguments
        guard let outputIndex = args.firstIndex(of: "--output"), args.indices.contains(outputIndex + 1) else {
            throw SplatTrainingCLIError.missingOutputDirectory
        }
        return URL(fileURLWithPath: args[outputIndex + 1], isDirectory: true)
    }

    private static func datasetRecipe() throws -> DatasetRecipe {
        if CommandLine.arguments.contains("--demo") {
            return try demoRecipe()
        }
        return try productionRecipe()
    }

    private static func productionRecipe() throws -> DatasetRecipe {
        guard let splatURL = parseSplatURL() else {
            throw SplatTrainingCLIError.missingRequiredInput("Production dataset generation requires --splat <scene.ply|scene.splat>.")
        }
        let asset = try GaussianSplatImporter().inspect(url: splatURL)
        let scene = asset.makeScene(
            id: stringValue(for: "--scene-id") ?? splatURL.deletingPathExtension().lastPathComponent,
            roomPlanModelURL: stringValue(for: "--roomplan").map { URL(fileURLWithPath: $0) }
        )
        print("Imported \(asset.format.rawValue) splat with \(asset.vertexCount) vertices from \(splatURL.path)")

        let target = NavigationTarget(
            label: stringValue(for: "--target-label") ?? "navigation_target",
            position: SIMD3<Double>(
                doubleValue(for: "--target-x", default: scene.bounds.maximum.x),
                doubleValue(for: "--target-y", default: scene.bounds.minimum.y),
                doubleValue(for: "--target-z", default: scene.bounds.maximum.z)
            )
        )
        guard let path = try captureRouteIfRequested(target: target) ?? generatedPathIfRequested(scene: scene, target: target) else {
            throw SplatTrainingCLIError.missingRequiredInput("Production dataset generation requires --capture-route, --use-aligned-route, --use-expanded-route, or --path-mode.")
        }

        return DatasetRecipe(
            id: stringValue(for: "--recipe-id") ?? "\(scene.id)-robot-camera-dataset",
            scene: scene,
            cameraRig: cameraRig(),
            path: path,
            requestedProducts: requestedProducts(),
            augmentations: [],
            labelSources: labelSources()
        )
    }

    private static func demoRecipe() throws -> DatasetRecipe {
        let fixtureSplatURL = URL(fileURLWithPath: "Fixtures/demo_native_gaussian_wall.ply")
        let scene: GaussianSplatScene
        if let splatURL = parseSplatURL() {
            let asset = try GaussianSplatImporter().inspect(url: splatURL)
            scene = asset.makeScene(
                id: splatURL.deletingPathExtension().lastPathComponent
            )
            print("Imported \(asset.format.rawValue) splat with \(asset.vertexCount) vertices from \(splatURL.path)")
        } else {
            let asset = try GaussianSplatImporter().inspect(url: fixtureSplatURL)
            scene = asset.makeScene(id: "demo-native-gaussian-wall")
            print("Imported \(asset.format.rawValue) splat with \(asset.vertexCount) vertices from \(fixtureSplatURL.path)")
        }

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
            id: "demo-robot-camera-dataset",
            scene: scene,
            cameraRig: cameraRig(),
            path: path,
            requestedProducts: [.rgb, .depth, .visibility, .pose, .segmentation, .obstacleMask, .lidarScan, .failureLabels, .navigationTarget],
            augmentations: [
                .exposureEV(-0.5),
                .gaussianNoise(sigma: 0.015),
                .motionBlur(samples: 5, shutterSeconds: 1.0 / 60.0),
                .compressionJPEG(quality: 0.82),
                .cameraHeightJitterMeters(0.03),
                .yawJitterDegrees(2.0)
            ],
            labelSources: labelSources()
        )
    }

    private static func cameraRig() -> RobotCameraRig {
        let width = intValue(for: "--camera-width", default: 1280)
        let height = intValue(for: "--camera-height", default: 720)
        let mountHeight = doubleValue(for: "--camera-mount-height", default: 0.62)
        return RobotCameraRig(
            name: stringValue(for: "--camera-name") ?? "robot-front-camera",
            mountHeightMeters: mountHeight,
            intrinsics: .fromHorizontalFOV(
                width: width,
                height: height,
                horizontalFOVDegrees: doubleValue(for: "--camera-hfov", default: 82)
            ),
            bodyToCamera: Transform3D(translation: SIMD3<Double>(
                doubleValue(for: "--camera-offset-x", default: 0),
                mountHeight,
                doubleValue(for: "--camera-offset-z", default: 0.08)
            ))
        )
    }

    private static func requestedProducts() -> Set<RenderProduct> {
        guard let raw = stringValue(for: "--products") else {
            return [.rgb, .depth, .visibility, .pose, .segmentation, .obstacleMask, .lidarScan, .failureLabels, .navigationTarget]
        }
        let products = raw.split(separator: ",").compactMap { RenderProduct(rawValue: String($0.trimmingCharacters(in: .whitespaces))) }
        return products.isEmpty ? [.rgb, .depth, .visibility, .pose, .lidarScan, .failureLabels] : Set(products)
    }

    private static func labelSources() -> [LabelSource] {
        var sources: [LabelSource] = []
        if let roomPlan = stringValue(for: "--roomplan") {
            sources.append(.roomPlanGeometry(URL(fileURLWithPath: roomPlan)))
        }
        if let manual = stringValue(for: "--manual-labels") {
            sources.append(.manualAnnotations(URL(fileURLWithPath: manual)))
        }
        sources.append(contentsOf: urlListValue(for: "--object-meshes").map { .objectCaptureMesh($0) })
        return sources
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

    private static func parseSpatialReviewValidationURL() -> URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--validate-spatial-review"), args.indices.contains(index + 1) else {
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

    private static func validateSpatialReview(at packageURL: URL) throws {
        let model = SpatialReviewModel()
        try model.openRobotScene(at: packageURL)
        guard let summary = model.state.summary else {
            throw SplatTrainingCLIError.spatialReviewFailed("Spatial review validation did not produce a scene summary.")
        }
        if !model.state.diagnostics.isEmpty {
            throw SplatTrainingCLIError.spatialReviewFailed(model.state.diagnostics.joined(separator: "\n"))
        }
        guard summary.availableLayers.contains(.gaussianSplat), let splatURL = summary.splatURL else {
            throw SplatTrainingCLIError.spatialReviewFailed("Spatial review package has no resolvable Gaussian splat layer.")
        }
        print("Validated spatial review package \(summary.sceneID)")
        print("Resolved splat: \(splatURL.path)")
        print("Frames \(summary.frameCount), route poses \(summary.routePoseCount), failures \(summary.failureMarkerCount)")
        print("Layers: \(summary.availableLayers.map(\.rawValue).sorted().joined(separator: ", "))")
        if let overlay = model.state.overlay {
            print("Overlay route \(overlay.route.count), frustums \(overlay.cameraFrustums.count), graph nodes \(overlay.navigationNodes.count), graph edges \(overlay.navigationEdges.count), markers \(overlay.failureMarkers.count)")
            let modelEvidenceCount = overlay.failureMarkers.filter { $0.modelLabel != nil || $0.modelSource != nil }.count
            let lidarEvidenceCount = overlay.failureMarkers.filter { $0.lidarEvidence != nil }.count
            print("Overlay evidence model \(modelEvidenceCount), lidar \(lidarEvidenceCount)")
        }
    }

    private static func captureRouteIfRequested(target: NavigationTarget) throws -> RobotPath? {
        guard let routeURL = try routeURLForDataset() else {
            return nil
        }
        let route = try JSONDecoder.robotVisionLabDecoder.decode(RobotPath.self, from: Data(contentsOf: routeURL))
        print("Loaded capture route with \(route.keyframes.count) keyframes from \(routeURL.path)")
        return RobotPath(keyframes: route.keyframes.map {
            RobotPathKeyframe(timestamp: $0.timestamp, pose: $0.pose, navigationTarget: $0.navigationTarget ?? target)
        })
    }

    private static func routeURLForDataset() throws -> URL? {
        if CommandLine.arguments.contains("--use-expanded-route") {
            let expandedURL = try parseOutputDirectory()
                .appendingPathComponent("ExpandedRoutes", isDirectory: true)
                .appendingPathComponent("expanded_robot_route.json")
            if FileManager.default.fileExists(atPath: expandedURL.path) {
                return expandedURL
            }
        }
        if CommandLine.arguments.contains("--use-aligned-route") {
            let alignedURL = try parseOutputDirectory()
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

    private static func urlListValue(for flag: String) -> [URL] {
        guard let value = stringValue(for: flag) else { return [] }
        return value
            .split(separator: ",")
            .map { URL(fileURLWithPath: String($0.trimmingCharacters(in: .whitespaces))) }
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
            guard modelURL != nil else {
                throw SplatTrainingCLIError.missingRequiredInput("Missing --evaluate-model <Model.mlpackage> for Core ML evaluation.")
            }
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
            throw SplatTrainingCLIError.missingRequiredInput("No real evaluation backend selected. Use --evaluate-coreml or --plan-mlx-evaluation.")
        }
        try EvaluationReportWriter().write(report, to: reportURL)
        print("Wrote evaluation report to \(reportURL.path)")
        let calibrationURL = outputDirectory.appendingPathComponent("failure_map_calibration_report.json")
        let calibration = FailureMapCalibrationReporter().makeReport(from: report, manifest: manifest)
        try FailureMapCalibrationReporter().write(calibration, to: calibrationURL)
        print("Wrote failure-map calibration report to \(calibrationURL.path)")
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
        let readiness = NativeRenderProductValidator().validate(manifest)
        let readinessURL = outputDirectory.appendingPathComponent("native_render_product_readiness.json")
        try JSONEncoder.robotVisionLabEncoder.encode(readiness).write(to: readinessURL)
        guard readiness.isReady else {
            throw SplatTrainingCLIError.missingRequiredInput("Native render products are not ready for MLX training. Run --render-apple-native first and inspect \(readinessURL.path).")
        }
        let package = try MLXTrainingPackageBuilder().writePackage(
            manifest: manifest,
            datasetManifestURL: datasetManifestURL,
            outputDirectory: packageDirectory
        )
        print("Wrote native render product readiness report to \(readinessURL.path)")
        print("Wrote Apple Silicon MLX training package to \(packageDirectory.path)")
        print("Dataset loader: \(package.datasetLoaderURL.path)")
        print("Training script: \(package.trainScriptURL.path)")
        print("Core ML export script: \(package.exportScriptURL.path)")
    }

    private static func runSplatTraining(
        package: SplatTrainingPackageManifest,
        job: SplatTrainingJob,
        outputDirectory: URL
    ) throws {
        let startedAt = Date()
        let result = try runProcess(
            executableURL: splatTrainingPythonExecutableURL(),
            arguments: splatTrainingPythonPrefixArguments() + splatTrainingArguments(package: package),
            currentDirectoryURL: package.trainScriptURL.deletingLastPathComponent()
        )
        let finishedAt = Date()
        let report = SplatTrainingReportBuilder().completedReport(
            job: job,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: result.exitCode,
            standardOutput: result.standardOutput,
            standardError: result.standardError
        )
        let reportURL = outputDirectory.appendingPathComponent("splat_training_report.json")
        try SplatTrainingReportWriter().write(report, to: reportURL)
        print("Wrote Apple MLX splat training report to \(reportURL.path)")
        guard result.exitCode == 0 else {
            throw SplatTrainingCLIError.splatTrainingFailed(reportURL)
        }
        let asset = try GaussianSplatImporter().inspect(url: package.outputURL)
        let summaryURL = package.outputURL.deletingPathExtension().appendingPathExtension("training_summary.json")
        let metricsURL = package.outputURL.deletingPathExtension().appendingPathExtension("training_metrics.jsonl")
        print("Trained Gaussian splat: \(package.outputURL.path)")
        print("Imported trained \(asset.format.rawValue) splat with \(asset.vertexCount) vertices")
        if FileManager.default.fileExists(atPath: summaryURL.path) {
            print("Training summary: \(summaryURL.path)")
        }
        if FileManager.default.fileExists(atPath: metricsURL.path) {
            print("Training metrics: \(metricsURL.path)")
        }
    }

    private static func splatTrainingArguments(package: SplatTrainingPackageManifest) -> [String] {
        var arguments = [
            package.trainScriptURL.path,
            "--frames", package.frameIndexURL.path,
            "--output", package.outputURL.path,
            "--splats-per-frame", "\(intValue(for: "--splat-training-splats-per-frame", default: 24))",
            "--epochs", "\(intValue(for: "--splat-training-epochs", default: 25))"
        ]
        if let depthPriorIndexURL = package.depthPriorIndexURL {
            arguments.append(contentsOf: ["--depth-priors", depthPriorIndexURL.path])
        }
        if CommandLine.arguments.contains("--splat-training-ascii-ply") {
            arguments.append("--ascii-ply")
        }
        return arguments
    }

    private static func splatTrainingPythonExecutableURL() -> URL {
        if let explicit = stringValue(for: "--splat-training-python") ?? ProcessInfo.processInfo.environment["ROBOT_SCENE_PYTHON"] {
            return URL(fileURLWithPath: explicit)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private static func splatTrainingPythonPrefixArguments() -> [String] {
        if stringValue(for: "--splat-training-python") != nil || ProcessInfo.processInfo.environment["ROBOT_SCENE_PYTHON"] != nil {
            return []
        }
        return ["python3"]
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> (exitCode: Int32, standardOutput: String, standardError: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !output.isEmpty {
            print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
        }
        if !error.isEmpty {
            FileHandle.standardError.write(Data(error.utf8))
            if !error.hasSuffix("\n") {
                FileHandle.standardError.write(Data("\n".utf8))
            }
        }
        return (process.terminationStatus, output, error)
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
        let profile = MetalSplatRenderProfiler().profile(report)
        let profileURL = outputDirectory.appendingPathComponent("metal_splat_render_profile.json")
        try JSONEncoder.robotVisionLabEncoder.encode(profile).write(to: profileURL)
        print("Wrote Metal splat render report to \(reportURL.path)")
        print("Wrote Metal splat render profile to \(profileURL.path)")
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
        if CommandLine.arguments.contains("--demo") {
            return try writeDemoSplatTrainingManifest(outputDirectory: outputDirectory)
        }
        throw SplatTrainingCLIError.missingPreparedManifest(url)
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

    private static func writeDemoSplatTrainingManifest(outputDirectory: URL) throws -> URL {
        let capturePlan = demoCapturePlan()
        let calibration = capturePlan.rgbVideo.map {
            SplatFrameCalibration(
                intrinsics: CameraIntrinsics.fromHorizontalFOV(
                    width: $0.targetResolution.width,
                    height: $0.targetResolution.height,
                    horizontalFOVDegrees: 70
                ),
                resolution: $0.targetResolution,
                trackingQuality: .normal
            )
        }
        let manifest = SplatTrainingManifest(
            id: "demo-room-scan-splat-training",
            imageFrames: demoScanSession().rgbFrames.map {
                SplatTrainingFrame(imageURL: $0.imageURL, pose: $0.pose, timestamp: $0.timestamp, calibration: calibration)
            },
            lidarFrames: demoScanSession().lidarFrames,
            roomPlanGeometryURL: URL(fileURLWithPath: "CaptureBundle/roomplan/room.usdz"),
            objectGeometryURLs: [
                URL(fileURLWithPath: "CaptureBundle/object-capture/chair.usdz"),
                URL(fileURLWithPath: "CaptureBundle/object-capture/table.usdz")
            ],
            expectedOutput: SplatTrainingOutput(
                targetURL: outputDirectory.appendingPathComponent("splats/demo-room-scan.ply")
            )
        )
        let manifestURL = outputDirectory.appendingPathComponent("demo_splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        return manifestURL
    }

    private static func demoCapturePlan() -> CapturePlan {
        CapturePlan(
            id: "demo-iphone-lidar-room-capture",
            captureModes: [.roomPlan, .rgbVideo, .lidarDepth, .objectCapture],
            roomPlan: RoomPlanOptions(),
            objectCapture: ObjectCaptureOptions(objectLabels: ["chair", "table", "charging_dock"]),
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720),
            lidar: LiDAROptions()
        )
    }

    private static func demoScanSession() -> ScanSession {
        ScanSession(
            id: "demo-room-scan",
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
                    depthURL: URL(fileURLWithPath: "CaptureBundle/lidar/depth_000000.f32"),
                    confidenceURL: URL(fileURLWithPath: "CaptureBundle/lidar/confidence_000000.bin"),
                    metadataURL: URL(fileURLWithPath: "CaptureBundle/lidar/depth_000000.json"),
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

do {
    try RobotVisionLabCLI.main()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    Foundation.exit(1)
}
