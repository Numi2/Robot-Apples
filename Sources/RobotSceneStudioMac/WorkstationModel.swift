import Foundation
import Observation
import RobotVisionLabCore
import simd

public enum WorkstationStage: String, Codable, CaseIterable, Sendable {
    case idle
    case importingCapture
    case preparingCapture
    case linkingSplat
    case buildingDataset
    case planningMetalRender
    case renderingMetalSplats
    case planningTraining
    case evaluatingModel
    case exportingRobotScene
    case complete
    case failed
}

public struct WorkstationArtifact: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: URL
    public var kind: String

    public init(id: String = UUID().uuidString, title: String, url: URL, kind: String) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
    }
}

public struct WorkstationState: Codable, Equatable, Sendable {
    public var stage: WorkstationStage
    public var workspaceURL: URL
    public var activeCaptureURL: URL?
    public var activeSplatURL: URL?
    public var activeRobotSceneURL: URL?
    public var frameCount: Int
    public var motionSampleCount: Int
    public var warningCount: Int
    public var artifacts: [WorkstationArtifact]
    public var diagnostics: [String]

    public init(
        stage: WorkstationStage = .idle,
        workspaceURL: URL = WorkstationPaths.defaultWorkspaceURL(),
        activeCaptureURL: URL? = nil,
        activeSplatURL: URL? = nil,
        activeRobotSceneURL: URL? = nil,
        frameCount: Int = 0,
        motionSampleCount: Int = 0,
        warningCount: Int = 0,
        artifacts: [WorkstationArtifact] = [],
        diagnostics: [String] = []
    ) {
        self.stage = stage
        self.workspaceURL = workspaceURL
        self.activeCaptureURL = activeCaptureURL
        self.activeSplatURL = activeSplatURL
        self.activeRobotSceneURL = activeRobotSceneURL
        self.frameCount = frameCount
        self.motionSampleCount = motionSampleCount
        self.warningCount = warningCount
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }
}

public enum WorkstationPaths {
    public static func defaultWorkspaceURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Robot Scene Studio", isDirectory: true)
    }
}

@MainActor
@Observable
public final class WorkstationModel {
    public private(set) var state: WorkstationState

    private var importedCapture: RobotCaptureImport?
    private var preparation: RobotCapturePreparationOutput?
    private var datasetManifest: DatasetManifest?
    private var evaluationReportURL: URL?

    public init(state: WorkstationState = WorkstationState()) {
        self.state = state
    }

    public func chooseWorkspace(_ url: URL) {
        state.workspaceURL = url
        appendDiagnostic("Workspace set to \(url.path).")
    }

    public func importCapture(at packageURL: URL) {
        perform(stage: .importingCapture) {
            try FileManager.default.createDirectory(at: state.workspaceURL, withIntermediateDirectories: true)
            let importer = RobotCaptureImporter()
            let imported = try importer.importPackage(at: packageURL)
            let report = importer.makeReport(for: imported, packageURL: packageURL)
            let reportURL = state.workspaceURL.appendingPathComponent("robotcapture_import_report.json")
            try importer.writeReport(report, to: reportURL)

            importedCapture = imported
            state.activeCaptureURL = packageURL
            state.frameCount = report.frameCount
            state.motionSampleCount = report.motionSampleCount
            state.warningCount = report.warnings.count
            state.diagnostics = report.warnings
            appendArtifact(title: "Capture Import Report", url: reportURL, kind: "robotcapture-import")
        }
    }

    public func prepareCapture(holdoutEveryNthFrame: Int = 5) {
        perform(stage: .preparingCapture) {
            guard let importedCapture else {
                throw WorkstationError.missingCapture
            }
            let outputURL = state.workspaceURL.appendingPathComponent("PreparedCapture", isDirectory: true)
            let output = try RobotCapturePreparer().prepare(
                importedCapture: importedCapture,
                outputDirectory: outputURL,
                holdoutEveryNthFrame: holdoutEveryNthFrame
            )
            preparation = output
            state.frameCount = output.report.routeKeyframeCount
            state.warningCount += output.report.warnings.count
            state.diagnostics.append(contentsOf: output.report.warnings)
            appendArtifact(title: "Prepared Route", url: output.report.routeURL, kind: "route")
            appendArtifact(title: "Training Manifest", url: output.report.splatTrainingManifestURL, kind: "splat-training")
            appendArtifact(title: "Evaluation Split", url: output.report.splitURL, kind: "capture-split")
        }
    }

    public func linkSplat(at splatURL: URL) {
        perform(stage: .linkingSplat) {
            _ = try GaussianSplatImporter().inspect(url: splatURL)
            state.activeSplatURL = splatURL
            appendArtifact(title: "Gaussian Splat", url: splatURL, kind: "splat")
        }
    }

    public func buildDatasetManifest() {
        perform(stage: .buildingDataset) {
            let manifest = try makeDatasetManifest()
            let manifestURL = state.workspaceURL.appendingPathComponent("dataset.json")
            try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
            datasetManifest = manifest
            state.frameCount = manifest.frames.count
            appendArtifact(title: "Dataset Manifest", url: manifestURL, kind: "dataset")
        }
    }

    public func planMetalRender() {
        perform(stage: .planningMetalRender) {
            let manifest = try ensureDatasetManifest()
            let recipe = DatasetRecipe(
                id: manifest.recipeID,
                scene: manifest.scene,
                cameraRig: manifest.cameraRig,
                path: RobotPath(keyframes: manifest.frames.map {
                    RobotPathKeyframe(timestamp: $0.timestamp, pose: $0.cameraPose, navigationTarget: $0.navigationTarget)
                }),
                requestedProducts: Set(manifest.frames.flatMap { $0.products.map(\.product) })
            )
            let plan = MetalRenderPlanner().makePlan(from: recipe)
            let report = MetalRenderPlanner().validate(plan: plan, capabilities: MetalDeviceProbe().capabilities())
            let reportURL = state.workspaceURL.appendingPathComponent("metal_render_plan_report.json")
            try MetalRenderPlanReportWriter().write(report, to: reportURL)
            state.diagnostics.append(contentsOf: report.diagnostics)
            appendArtifact(title: "Metal Render Plan", url: reportURL, kind: "metal")
        }
    }

    public func renderMetalSplats(tileSize: Int = 16, maxSplatsPerFrame: Int? = nil) {
        perform(stage: .renderingMetalSplats) {
            guard state.activeSplatURL != nil else {
                throw WorkstationError.missingSplat
            }
            let manifest = try ensureDatasetManifest()
            let renderer = try MetalGaussianSplatRenderer(
                configuration: MetalGaussianSplatRenderConfiguration(
                    tileSize: tileSize,
                    maxSplatsPerFrame: maxSplatsPerFrame
                )
            )
            let report = try renderer.renderDataset(manifest, outputDirectory: state.workspaceURL)
            let reportURL = state.workspaceURL.appendingPathComponent("metal_splat_render_report.json")

            appendArtifact(title: "Metal Splat Render Report", url: reportURL, kind: "metal-render")
            appendArtifact(title: "Metal RGB Frames", url: state.workspaceURL.appendingPathComponent("rgb", isDirectory: true), kind: "rgb")
            appendArtifact(title: "Metal Depth Products", url: state.workspaceURL.appendingPathComponent("depth", isDirectory: true), kind: "depth")
            appendArtifact(title: "Metal Visibility Products", url: state.workspaceURL.appendingPathComponent("visibility", isDirectory: true), kind: "visibility")
            appendArtifact(title: "Metal Tile Bins", url: state.workspaceURL.appendingPathComponent("tile_bins", isDirectory: true), kind: "metal-tile-bins")

            if let slowestFrame = report.frameProducts.max(by: { $0.timing.totalSeconds < $1.timing.totalSeconds }) {
                let visibleSplatCount = report.frameProducts.reduce(0) { $0 + $1.visibleSplatCount }
                let drawCommandCount = report.frameProducts.reduce(0) { $0 + $1.drawCommandCount }
                appendDiagnostic(
                    "Metal splat render complete: \(report.frameProducts.count) frames, \(visibleSplatCount) visible splats, \(drawCommandCount) draw commands, slowest frame \(String(format: "%.3f", slowestFrame.timing.totalSeconds))s."
                )
            } else {
                appendDiagnostic("Metal splat render complete: no route frames requested.")
            }
        }
    }

    public func planTraining() {
        perform(stage: .planningTraining) {
            guard let trainingManifest = preparation?.splatTrainingManifest else {
                throw WorkstationError.missingPreparedCapture
            }
            let job = SplatTrainingJob(
                id: "\(trainingManifest.id)-apple-native-job",
                manifest: trainingManifest,
                backend: AppleNativeTrainingBackend(),
                mode: .planning
            )
            let report = SplatTrainingReportBuilder().dryRunReport(job: job)
            let reportURL = state.workspaceURL.appendingPathComponent("splat_training_report.json")
            try SplatTrainingReportWriter().write(report, to: reportURL)
            appendArtifact(title: "Apple Native Training Plan", url: reportURL, kind: "training")
        }
    }

    public func evaluateBaselineModel() {
        perform(stage: .evaluatingModel) {
            let manifest = try ensureDatasetManifest()
            let manifestURL = state.workspaceURL.appendingPathComponent("dataset.json")
            let request = ModelEvaluationRequest(
                id: "mac-workstation-baseline",
                model: LocalModelReference(name: "manifest-baseline", runtime: .baseline),
                datasetManifestURL: manifestURL,
                tasks: [.navigationTargetDetection, .obstacleDetection, .segmentation, .failureCaseDetection]
            )
            let report = BaselineDatasetEvaluator().evaluate(request: request, manifest: manifest)
            let reportURL = state.workspaceURL.appendingPathComponent("evaluation_report.json")
            try EvaluationReportWriter().write(report, to: reportURL)
            evaluationReportURL = reportURL
            state.warningCount += report.summary.warningCount
            appendArtifact(title: "Evaluation Report", url: reportURL, kind: "evaluation")
        }
    }

    public func exportRobotScene() {
        perform(stage: .exportingRobotScene) {
            let manifest = try ensureDatasetManifest()
            let packageURL = state.workspaceURL.appendingPathComponent("Project.robotscene", isDirectory: true)
            _ = try RobotScenePackageExporter().writeRobotScenePackage(
                manifest: manifest,
                evaluationReportURL: evaluationReportURL,
                capturePackageURL: state.activeCaptureURL,
                to: packageURL
            )
            state.activeRobotSceneURL = packageURL
            appendArtifact(title: "Robot Scene Package", url: packageURL, kind: "robotscene")
        }
    }

    public func runCurrentPipeline(captureURL: URL, splatURL: URL? = nil) {
        importCapture(at: captureURL)
        guard state.stage != .failed else { return }
        prepareCapture()
        guard state.stage != .failed else { return }
        if let splatURL {
            linkSplat(at: splatURL)
            guard state.stage != .failed else { return }
        }
        buildDatasetManifest()
        guard state.stage != .failed else { return }
        planMetalRender()
        planTraining()
        evaluateBaselineModel()
        exportRobotScene()
    }

    private func perform(stage: WorkstationStage, _ work: () throws -> Void) {
        state.stage = stage
        do {
            try work()
            state.stage = .complete
        } catch {
            state.stage = .failed
            appendDiagnostic(error.localizedDescription)
        }
    }

    private func makeDatasetManifest() throws -> DatasetManifest {
        guard let preparation else {
            throw WorkstationError.missingPreparedCapture
        }
        let route = preparation.route
        let scene = try makeScene(route: route)
        let cameraRig = RobotCameraRig(
            name: "robot-front-camera",
            mountHeightMeters: 0.62,
            intrinsics: .fromHorizontalFOV(width: 1280, height: 720, horizontalFOVDegrees: 82),
            bodyToCamera: Transform3D(translation: SIMD3<Double>(0, 0.62, 0.08))
        )
        let recipe = DatasetRecipe(
            id: "mac-workstation-robot-scene",
            scene: scene,
            cameraRig: cameraRig,
            path: route,
            requestedProducts: [.rgb, .depth, .pose, .segmentation, .obstacleMask, .navigationTarget],
            labelSources: scene.roomPlanModelURL.map { [.roomPlanGeometry($0)] } ?? []
        )
        return DatasetGenerator().makeManifest(recipe: recipe, outputDirectory: state.workspaceURL)
    }

    private func ensureDatasetManifest() throws -> DatasetManifest {
        if let datasetManifest {
            return datasetManifest
        }
        let manifest = try makeDatasetManifest()
        datasetManifest = manifest
        return manifest
    }

    private func makeScene(route: RobotPath) throws -> GaussianSplatScene {
        if let splatURL = state.activeSplatURL {
            return try GaussianSplatImporter().inspect(url: splatURL).makeScene(
                id: splatURL.deletingPathExtension().lastPathComponent,
                roomPlanModelURL: importedCapture?.captureBundle.roomPlanModelURL
            )
        }

        return GaussianSplatScene(
            id: "capture-route-placeholder-splat",
            source: .importedPLY(state.workspaceURL.appendingPathComponent("splats/capture-generated.ply")),
            bounds: bounds(from: route),
            roomPlanModelURL: importedCapture?.captureBundle.roomPlanModelURL
        )
    }

    private func bounds(from route: RobotPath) -> AxisAlignedBounds {
        let positions = route.keyframes.map(\.pose.position)
        guard let first = positions.first else {
            return AxisAlignedBounds(minimum: SIMD3<Double>(-1, 0, -1), maximum: SIMD3<Double>(1, 2, 1))
        }
        var minimum = first
        var maximum = first
        for position in positions.dropFirst() {
            minimum = simd.min(minimum, position)
            maximum = simd.max(maximum, position)
        }
        let padding = SIMD3<Double>(0.5, 0.5, 0.5)
        return AxisAlignedBounds(minimum: minimum - padding, maximum: maximum + padding)
    }

    private func appendArtifact(title: String, url: URL, kind: String) {
        let artifact = WorkstationArtifact(title: title, url: url, kind: kind)
        if !state.artifacts.contains(where: { $0.url == url }) {
            state.artifacts.append(artifact)
        }
    }

    private func appendDiagnostic(_ message: String) {
        guard !message.isEmpty else { return }
        state.diagnostics.append(message)
    }
}

public enum WorkstationError: Error, LocalizedError {
    case missingCapture
    case missingPreparedCapture
    case missingSplat

    public var errorDescription: String? {
        switch self {
        case .missingCapture:
            "Import a .robotcapture package first."
        case .missingPreparedCapture:
            "Prepare a capture package before running this workstation step."
        case .missingSplat:
            "Link a .ply or .splat scene before rendering Metal splats."
        }
    }
}
