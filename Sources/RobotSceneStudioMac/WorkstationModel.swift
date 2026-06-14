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
    case runningSplatTraining
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
    public var activeRobotSceneID: String?
    public var failureMarkerCount: Int

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
        diagnostics: [String] = [],
        activeRobotSceneID: String? = nil,
        failureMarkerCount: Int = 0
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
        self.activeRobotSceneID = activeRobotSceneID
        self.failureMarkerCount = failureMarkerCount
    }
}

public struct RouteAlignmentAnchorDraft: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var arkitX: Double
    public var arkitY: Double
    public var arkitZ: Double
    public var sceneX: Double
    public var sceneY: Double
    public var sceneZ: Double

    public init(
        id: UUID = UUID(),
        arkitX: Double = 0,
        arkitY: Double = 0,
        arkitZ: Double = 0,
        sceneX: Double = 0,
        sceneY: Double = 0,
        sceneZ: Double = 0
    ) {
        self.id = id
        self.arkitX = arkitX
        self.arkitY = arkitY
        self.arkitZ = arkitZ
        self.sceneX = sceneX
        self.sceneY = sceneY
        self.sceneZ = sceneZ
    }

    public var controlPoint: RouteAlignmentControlPoint {
        RouteAlignmentControlPoint(
            arkitPosition: SIMD3<Double>(arkitX, arkitY, arkitZ),
            scenePosition: SIMD3<Double>(sceneX, sceneY, sceneZ)
        )
    }
}

public struct WorkstationTransferEvent: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var detail: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), title: String, detail: String) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.detail = detail
    }
}

public struct WorkstationTransferReceiptRecord: Identifiable, Equatable, Sendable {
    public var id: String
    public var receipt: RobotCaptureTransferReceipt
    public var receiptURL: URL

    public init(receipt: RobotCaptureTransferReceipt, receiptURL: URL) {
        self.id = receiptURL.path
        self.receipt = receipt
        self.receiptURL = receiptURL
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
    public private(set) var importHealthReport: RobotCaptureImportReport?
    public private(set) var splatAsset: GaussianSplatAsset?
    public private(set) var robotSceneManifest: RobotScenePackageManifest?
    public private(set) var failureMarkers: [FailureMapMarker] = []
    public private(set) var routeAlignmentReport: RouteAlignmentReport?
    public private(set) var routeExpansionReport: RobotRouteExpansionReport?
    public var routeAlignmentAnchors: [RouteAlignmentAnchorDraft] = []
    public var routeExpansionLateralOffsets = "-0.25,0,0.25"
    public var routeExpansionHeightOffsets = "-0.08,0,0.08"
    public var routeExpansionYawOffsets = "-8,0,8"
    public var floorY = 0.0
    public var minimumCameraHeight = 0.2
    public var maximumCameraHeight = 2.0
    public var transformTranslationX = 0.0
    public var transformTranslationY = 0.0
    public var transformTranslationZ = 0.0
    public var transformYawDegrees = 0.0
    public var transformScaleX = 1.0
    public var transformScaleY = 1.0
    public var transformScaleZ = 1.0
    public var robotPathRowSpacing = 0.75
    public var robotPathColumnSpacing = 0.75
    public private(set) var routeConfidenceMetrics: RouteConfidenceMetrics?
    public private(set) var coverageReport: RouteCoverageReport?
    public private(set) var navigationGraph: NavigationGraph?
    public private(set) var metalRenderProfile: MetalSplatRenderProfile?
    public private(set) var mlxTrainingPackage: MLXTrainingPackageManifest?
    public private(set) var splatTrainingPackage: SplatTrainingPackageManifest?
    public private(set) var splatTrainingReport: SplatTrainingReport?
    public private(set) var failureMapCalibrationReport: FailureMapCalibrationReport?
    public private(set) var isMultipeerReceiverRunning = false
    public private(set) var transferEvents: [WorkstationTransferEvent] = []
    public private(set) var pendingPairingInvitations: [String] = []
    public private(set) var receivingProgressByPeer: [String: Double] = [:]
    public private(set) var transferReceipts: [WorkstationTransferReceiptRecord] = []

    private var importedCapture: RobotCaptureImport?
    private var preparation: RobotCapturePreparationOutput?
    private var alignedRoute: RobotPath?
    private var expandedRoute: RobotPath?
    private var datasetManifest: DatasetManifest?
    private var evaluationReportURL: URL?
    private var multipeerReceiver: RobotCaptureMultipeerTransfer?
    private var multipeerDelegate: WorkstationMultipeerReceiverDelegate?

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
            importHealthReport = report
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
            appendArtifact(title: "Structured Geometry Report", url: output.report.structuredGeometryReportURL, kind: "structured-geometry")
        }
    }

    public func linkSplat(at splatURL: URL) {
        perform(stage: .linkingSplat) {
            let asset = try GaussianSplatImporter().inspect(url: splatURL)
            splatAsset = asset
            state.activeSplatURL = splatURL
            datasetManifest = nil
            metalRenderProfile = nil
            appendArtifact(title: "Gaussian Splat", url: splatURL, kind: "splat")
            appendDiagnostic("Linked \(asset.format.rawValue.uppercased()) splat with \(asset.vertexCount) splats.")
        }
    }

    public func openRobotScene(at packageURL: URL) {
        perform(stage: .idle) {
            let manifestURL = packageURL.pathExtension == "json" ? packageURL : packageURL.appendingPathComponent("robotscene.json")
            let packageRoot = manifestURL.deletingLastPathComponent()
            let manifest = try JSONDecoder.robotVisionLabDecoder.decode(
                RobotScenePackageManifest.self,
                from: Data(contentsOf: manifestURL)
            )
            let failureMapURL = resolve(manifest.failureMapURL, relativeTo: packageRoot)
            let markers = try JSONDecoder.robotVisionLabDecoder.decode(
                [FailureMapMarker].self,
                from: Data(contentsOf: failureMapURL)
            )
            robotSceneManifest = manifest
            failureMarkers = markers
            state.activeRobotSceneURL = packageRoot
            state.activeRobotSceneID = manifest.id
            state.activeSplatURL = manifest.splatScene.sourceURL.map { resolve($0, relativeTo: packageRoot) }
            if let activeSplatURL = state.activeSplatURL,
               FileManager.default.fileExists(atPath: activeSplatURL.path) {
                splatAsset = try? GaussianSplatImporter().inspect(url: activeSplatURL)
            } else {
                splatAsset = nil
            }
            datasetManifest = nil
            metalRenderProfile = nil
            state.failureMarkerCount = markers.count
            appendArtifact(title: "Opened Robot Scene", url: packageRoot, kind: "robotscene")
            appendArtifact(title: "Failure Map", url: failureMapURL, kind: "failure-map")
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

    public func addRouteAlignmentAnchor() {
        routeAlignmentAnchors.append(RouteAlignmentAnchorDraft())
    }

    public func removeRouteAlignmentAnchor(id: UUID) {
        routeAlignmentAnchors.removeAll { $0.id == id }
    }

    public func alignRoute(method: RouteAlignmentMethod = .controlPointCentroids, preserveVerticalScale: Bool = true) {
        perform(stage: .preparingCapture) {
            guard let preparation else {
                throw WorkstationError.missingPreparedCapture
            }
            let editedSourceRoute = RouteIntelligenceAnalyzer().apply(
                route: preparation.route,
                transformEditor: routeTransformEditor,
                floorConstraint: floorConstraint
            )
            let sceneBounds = try activeSceneBounds(for: editedSourceRoute)
            let request = RouteAlignmentRequest(
                sourceRoute: editedSourceRoute,
                sceneBounds: sceneBounds,
                method: method,
                controlPoints: routeAlignmentAnchors.map(\.controlPoint),
                preserveVerticalScale: preserveVerticalScale
            )
            let output = try RobotRouteAligner().align(
                request: request,
                outputDirectory: state.workspaceURL.appendingPathComponent("RouteAlignment", isDirectory: true)
            )
            alignedRoute = output.alignedRoute
            routeAlignmentReport = output.report
            routeConfidenceMetrics = RouteIntelligenceAnalyzer().confidence(
                sourceRoute: preparation.route,
                alignedRoute: output.alignedRoute,
                anchors: routeAlignmentAnchors.map(\.controlPoint),
                floorConstraint: floorConstraint
            )
            state.warningCount += output.report.warnings.count
            state.diagnostics.append(contentsOf: output.report.warnings)
            state.diagnostics.append(contentsOf: routeConfidenceMetrics?.warnings ?? [])
            appendArtifact(title: "Aligned Route", url: output.report.alignedRouteURL, kind: "aligned-route")
            appendArtifact(
                title: "Route Alignment Report",
                url: state.workspaceURL.appendingPathComponent("RouteAlignment/route_alignment_report.json"),
                kind: "route-alignment"
            )
        }
    }

    public func applyCoordinateTransformEditor() {
        perform(stage: .preparingCapture) {
            guard let preparation else {
                throw WorkstationError.missingPreparedCapture
            }
            let route = RouteIntelligenceAnalyzer().apply(
                route: alignedRoute ?? preparation.route,
                transformEditor: routeTransformEditor,
                floorConstraint: floorConstraint
            )
            alignedRoute = route
            let routeURL = state.workspaceURL.appendingPathComponent("RouteAlignment/edited_aligned_route.json")
            try FileManager.default.createDirectory(at: routeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.robotVisionLabEncoder.encode(route).write(to: routeURL)
            routeConfidenceMetrics = RouteIntelligenceAnalyzer().confidence(
                sourceRoute: preparation.route,
                alignedRoute: route,
                anchors: routeAlignmentAnchors.map(\.controlPoint),
                floorConstraint: floorConstraint
            )
            appendArtifact(title: "Edited Aligned Route", url: routeURL, kind: "aligned-route")
        }
    }

    public func generateRouteVariants() {
        perform(stage: .preparingCapture) {
            guard let preparation else {
                throw WorkstationError.missingPreparedCapture
            }
            let sourceRoute = alignedRoute ?? preparation.route
            let request = RobotRouteExpansionRequest(
                sourceRoute: sourceRoute,
                lateralOffsetsMeters: parseNumberList(routeExpansionLateralOffsets),
                cameraHeightOffsetsMeters: parseNumberList(routeExpansionHeightOffsets),
                yawOffsetsDegrees: parseNumberList(routeExpansionYawOffsets),
                bounds: try activeSceneBounds(for: sourceRoute)
            )
            let output = try RobotRouteExpander().expand(
                request: request,
                outputDirectory: state.workspaceURL.appendingPathComponent("RouteVariants", isDirectory: true)
            )
            expandedRoute = output.route
            routeExpansionReport = output.report
            state.frameCount = output.report.expandedKeyframeCount
            state.warningCount += output.report.warnings.count
            state.diagnostics.append(contentsOf: output.report.warnings)
            appendArtifact(title: "Expanded Robot Route", url: output.report.expandedRouteURL, kind: "route-variants")
            appendArtifact(
                title: "Route Variant Report",
                url: state.workspaceURL.appendingPathComponent("RouteVariants/route_expansion_report.json"),
                kind: "route-variants"
            )
        }
    }

    public func generateRobotValidPath() {
        perform(stage: .preparingCapture) {
            let route = expandedRoute ?? alignedRoute ?? preparation?.route
            let bounds = try activeSceneBounds(for: route ?? RobotPath(keyframes: []))
            let output = try RouteIntelligenceAnalyzer().generateRobotValidPath(
                RobotValidPathRequest(
                    bounds: bounds,
                    floorConstraint: floorConstraint,
                    rowSpacingMeters: robotPathRowSpacing,
                    columnSpacingMeters: robotPathColumnSpacing
                ),
                outputDirectory: state.workspaceURL.appendingPathComponent("RobotValidPaths", isDirectory: true)
            )
            expandedRoute = output.route
            navigationGraph = output.navigationGraph
            state.frameCount = output.route.keyframes.count
            appendArtifact(title: "Robot-Valid Route", url: output.routeURL, kind: "robot-valid-route")
            appendArtifact(title: "Editable Navigation Graph", url: output.navigationGraphURL, kind: "navigation-graph")
        }
    }

    public func analyzeRouteCoverage() {
        perform(stage: .preparingCapture) {
            guard let route = expandedRoute ?? alignedRoute ?? preparation?.route else {
                throw WorkstationError.missingPreparedCapture
            }
            let report = RouteIntelligenceAnalyzer().analyzeCoverage(route: route)
            coverageReport = report
            let reportURL = state.workspaceURL.appendingPathComponent("route_coverage_report.json")
            try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: reportURL)
            appendArtifact(title: "Route Coverage Report", url: reportURL, kind: "coverage")
        }
    }

    public func addNavigationNode() {
        let existing = navigationGraph ?? NavigationGraph(nodes: [], edges: [])
        let index = existing.nodes.count
        let position = (expandedRoute ?? alignedRoute ?? preparation?.route)?.keyframes.first?.pose.position ?? .zero
        navigationGraph = RouteIntelligenceAnalyzer().addNode(
            to: existing,
            node: NavigationNode(id: "manual_\(index)", position: position, label: "Manual")
        )
    }

    public func removeNavigationNode(id: String) {
        guard let navigationGraph else { return }
        self.navigationGraph = RouteIntelligenceAnalyzer().removeNode(from: navigationGraph, nodeID: id)
    }

    public func connectNavigationNodes(from: String, to: String) {
        guard let navigationGraph else { return }
        self.navigationGraph = RouteIntelligenceAnalyzer().addEdge(
            to: navigationGraph,
            edge: NavigationEdge(from: from, to: to, traversalCost: 1)
        )
    }

    public func startMultipeerReceiver() {
        do {
            let inboxURL = state.workspaceURL.appendingPathComponent("Inbox", isDirectory: true)
            let delegate = WorkstationMultipeerReceiverDelegate { [weak self] event in
                self?.handleTransferEvent(event)
            }
            let receiver = RobotCaptureMultipeerTransfer(
                role: .receiver,
                inboxDirectory: inboxURL,
                automaticallyAcceptInvitations: false
            )
            receiver.delegate = delegate
            try receiver.start()
            multipeerDelegate = delegate
            multipeerReceiver = receiver
            isMultipeerReceiverRunning = true
            transferEvents.insert(WorkstationTransferEvent(title: "Receiver Started", detail: inboxURL.path), at: 0)
        } catch {
            appendDiagnostic(error.localizedDescription)
            transferEvents.insert(WorkstationTransferEvent(title: "Receiver Failed", detail: error.localizedDescription), at: 0)
        }
    }

    public func stopMultipeerReceiver() {
        multipeerReceiver?.stop()
        multipeerReceiver = nil
        multipeerDelegate = nil
        isMultipeerReceiverRunning = false
        transferEvents.insert(WorkstationTransferEvent(title: "Receiver Stopped", detail: "Multipeer Connectivity advertising stopped."), at: 0)
    }

    public func acceptPairingInvitation(from peerName: String) {
        multipeerReceiver?.acceptInvitation(from: peerName)
        pendingPairingInvitations.removeAll { $0 == peerName }
    }

    public func rejectPairingInvitation(from peerName: String) {
        multipeerReceiver?.rejectInvitation(from: peerName)
        pendingPairingInvitations.removeAll { $0 == peerName }
    }

    public func importFinderCopiedCapture(at packageURL: URL) {
        transferEvents.insert(WorkstationTransferEvent(title: "Finder Import", detail: packageURL.path), at: 0)
        importCapture(at: packageURL)
    }

    public func refreshTransferReceipts() {
        let inboxURL = state.workspaceURL.appendingPathComponent("Inbox", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        transferReceipts = urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasSuffix("transfer-receipt.json") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let receipt = try? JSONDecoder.robotVisionLabDecoder.decode(RobotCaptureTransferReceipt.self, from: data)
                else { return nil }
                return WorkstationTransferReceiptRecord(receipt: receipt, receiptURL: url)
            }
            .sorted { $0.receipt.receivedAt > $1.receipt.receivedAt }
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

    public func renderMetalSplats(
        tileSize: Int = 16,
        maxSplatsPerFrame: Int? = nil,
        streamingChunkSplatCount: Int? = nil
    ) {
        perform(stage: .renderingMetalSplats) {
            guard state.activeSplatURL != nil else {
                throw WorkstationError.missingSplat
            }
            let manifest = try ensureDatasetManifest()
            let renderer = try MetalGaussianSplatRenderer(
                configuration: MetalGaussianSplatRenderConfiguration(
                    tileSize: tileSize,
                    maxSplatsPerFrame: maxSplatsPerFrame,
                    streamingChunkSplatCount: streamingChunkSplatCount
                )
            )
            let report = try renderer.renderDataset(manifest, outputDirectory: state.workspaceURL)
            _ = try DatasetExporter().writeStructuredGeometryProducts(manifest, to: state.workspaceURL)
            _ = try DatasetExporter().writeRenderedLiDARScans(manifest, to: state.workspaceURL)
            _ = try DatasetExporter().writeRenderedFailureLabels(manifest, to: state.workspaceURL)
            let reportURL = state.workspaceURL.appendingPathComponent("metal_splat_render_report.json")
            try MetalSplatRenderReportWriter().write(report, to: reportURL)
            let profile = MetalSplatRenderProfiler().profile(report)
            let profileURL = state.workspaceURL.appendingPathComponent("metal_splat_render_profile.json")
            try JSONEncoder.robotVisionLabEncoder.encode(profile).write(to: profileURL)
            metalRenderProfile = profile

            appendArtifact(title: "Metal Splat Render Report", url: reportURL, kind: "metal-render")
            appendArtifact(title: "Metal Render Profile", url: profileURL, kind: "metal-profile")
            appendArtifact(title: "Metal RGB Frames", url: state.workspaceURL.appendingPathComponent("rgb", isDirectory: true), kind: "rgb")
            appendArtifact(title: "Metal Depth Products", url: state.workspaceURL.appendingPathComponent("depth", isDirectory: true), kind: "depth")
            appendArtifact(title: "Metal Visibility Products", url: state.workspaceURL.appendingPathComponent("visibility", isDirectory: true), kind: "visibility")
            appendArtifact(title: "Structured Geometry Layers", url: state.workspaceURL.appendingPathComponent("structured_geometry_layers.json"), kind: "structured-geometry-layers")
            appendArtifact(title: "Geometry Segmentation Products", url: state.workspaceURL.appendingPathComponent("segmentation", isDirectory: true), kind: "segmentation")
            appendArtifact(title: "Geometry Obstacle Products", url: state.workspaceURL.appendingPathComponent("obstacleMask", isDirectory: true), kind: "obstacle-mask")
            appendArtifact(title: "Synthetic LiDAR Scans", url: state.workspaceURL.appendingPathComponent("lidarScan", isDirectory: true), kind: "lidar-scan")
            appendArtifact(title: "Rendered Failure Labels", url: state.workspaceURL.appendingPathComponent("failureLabels", isDirectory: true), kind: "failure-labels")
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
            let report = SplatTrainingReportBuilder().preparationReport(job: job)
            let reportURL = state.workspaceURL.appendingPathComponent("splat_training_report.json")
            try SplatTrainingReportWriter().write(report, to: reportURL)
            appendArtifact(title: "Apple Native Training Plan", url: reportURL, kind: "training")
        }
    }

    public func writeSplatTrainingPackage() {
        perform(stage: .planningTraining) {
            guard let preparation else {
                throw WorkstationError.missingPreparedCapture
            }
            let job = SplatTrainingJob(
                id: "\(preparation.splatTrainingManifest.id)-apple-native-splat-package",
                manifest: preparation.splatTrainingManifest,
                backend: AppleNativeTrainingBackend(),
                mode: .nativeAppleSilicon
            )
            let package = try SplatTrainingPackageBuilder().writePackage(
                job: job,
                manifestURL: preparation.report.splatTrainingManifestURL,
                outputDirectory: state.workspaceURL.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
            )
            splatTrainingPackage = package
            appendArtifact(title: "Splat Training Package", url: package.trainScriptURL.deletingLastPathComponent(), kind: "splat-training-package")
            appendArtifact(title: "Splat Training Frame Index", url: package.frameIndexURL, kind: "splat-training-index")
            appendArtifact(title: "Capture Splat MLX Script", url: package.trainScriptURL, kind: "splat-training-script")
        }
    }

    public func runSplatTraining(splatsPerFrame: Int = 24, epochs: Int = 25, asciiPLY: Bool = false) {
        perform(stage: .runningSplatTraining) {
            let package: SplatTrainingPackageManifest
            if let existingPackage = splatTrainingPackage {
                package = existingPackage
            } else {
                guard let preparation else {
                    throw WorkstationError.missingPreparedCapture
                }
                let job = SplatTrainingJob(
                    id: "\(preparation.splatTrainingManifest.id)-apple-native-splat-package",
                    manifest: preparation.splatTrainingManifest,
                    backend: AppleNativeTrainingBackend(),
                    mode: .nativeAppleSilicon
                )
                package = try SplatTrainingPackageBuilder().writePackage(
                    job: job,
                    manifestURL: preparation.report.splatTrainingManifestURL,
                    outputDirectory: state.workspaceURL.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
                )
                splatTrainingPackage = package
                appendArtifact(title: "Splat Training Package", url: package.trainScriptURL.deletingLastPathComponent(), kind: "splat-training-package")
                appendArtifact(title: "Splat Training Frame Index", url: package.frameIndexURL, kind: "splat-training-index")
                appendArtifact(title: "Capture Splat MLX Script", url: package.trainScriptURL, kind: "splat-training-script")
            }

            let job = SplatTrainingJob(
                id: "\(package.id)-run",
                manifest: try JSONDecoder.robotVisionLabDecoder.decode(
                    SplatTrainingManifest.self,
                    from: Data(contentsOf: package.sourceManifestURL)
                ),
                backend: AppleNativeTrainingBackend(),
                mode: .nativeAppleSilicon
            )
            let startedAt = Date()
            let result = try runProcess(
                executableURL: splatTrainingPythonExecutableURL(),
                arguments: splatTrainingPythonPrefixArguments() + splatTrainingArguments(package: package, splatsPerFrame: splatsPerFrame, epochs: epochs, asciiPLY: asciiPLY),
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
            let reportURL = state.workspaceURL.appendingPathComponent("splat_training_report.json")
            try SplatTrainingReportWriter().write(report, to: reportURL)
            splatTrainingReport = report
            appendArtifact(title: "Splat Training Report", url: reportURL, kind: "training-report")

            guard result.exitCode == 0 else {
                throw WorkstationError.trainingFailed(reportURL)
            }

            let outputURL = package.outputURL
            let summaryURL = outputURL.deletingPathExtension().appendingPathExtension("training_summary.json")
            let metricsURL = outputURL.deletingPathExtension().appendingPathExtension("training_metrics.jsonl")
            appendArtifact(title: "Trained Gaussian Splat", url: outputURL, kind: "splat-training-output")
            if FileManager.default.fileExists(atPath: summaryURL.path) {
                appendArtifact(title: "Splat Training Summary", url: summaryURL, kind: "training-summary")
            }
            if FileManager.default.fileExists(atPath: metricsURL.path) {
                appendArtifact(title: "Splat Training Metrics", url: metricsURL, kind: "training-metrics")
            }
            let asset = try GaussianSplatImporter().inspect(url: outputURL)
            splatAsset = asset
            state.activeSplatURL = outputURL
            datasetManifest = nil
            metalRenderProfile = nil
            appendArtifact(title: "Gaussian Splat", url: outputURL, kind: "splat")
            appendDiagnostic("Apple MLX splat training complete: \(outputURL.lastPathComponent) linked as the active Gaussian splat.")
        }
    }

    public func writeMLXTrainingPackage() {
        perform(stage: .planningTraining) {
            let manifest = try ensureDatasetManifest()
            let manifestURL = state.workspaceURL.appendingPathComponent("dataset.json")
            if !FileManager.default.fileExists(atPath: manifestURL.path) {
                try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
            }
            let readiness = NativeRenderProductValidator().validate(manifest)
            let readinessURL = state.workspaceURL.appendingPathComponent("native_render_product_readiness.json")
            try JSONEncoder.robotVisionLabEncoder.encode(readiness).write(to: readinessURL)
            appendArtifact(title: "Native Render Product Readiness", url: readinessURL, kind: "render-readiness")
            guard readiness.isReady else {
                throw WorkstationError.nativeRenderProductsNotReady(readinessURL)
            }
            let package = try MLXTrainingPackageBuilder().writePackage(
                manifest: manifest,
                datasetManifestURL: manifestURL,
                outputDirectory: state.workspaceURL.appendingPathComponent("MLXTrainingPackage", isDirectory: true)
            )
            mlxTrainingPackage = package
            appendArtifact(title: "MLX Training Package", url: package.trainScriptURL.deletingLastPathComponent(), kind: "mlx-training")
            appendArtifact(title: "MLX Dataset Loader", url: package.datasetLoaderURL, kind: "mlx-loader")
            appendArtifact(title: "Core ML Export Script", url: package.exportScriptURL, kind: "coreml-export")
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
            openRobotScene(at: packageURL)
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
        exportRobotScene()
    }

    public var floorConstraint: RouteFloorHeightConstraint {
        RouteFloorHeightConstraint(
            floorY: floorY,
            minimumCameraHeight: minimumCameraHeight,
            maximumCameraHeight: maximumCameraHeight
        )
    }

    public var routeTransformEditor: RouteTransformEditor {
        RouteTransformEditor(
            translation: SIMD3<Double>(transformTranslationX, transformTranslationY, transformTranslationZ),
            yawDegrees: transformYawDegrees,
            scale: SIMD3<Double>(transformScaleX, transformScaleY, transformScaleZ)
        )
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

    private func splatTrainingArguments(
        package: SplatTrainingPackageManifest,
        splatsPerFrame: Int,
        epochs: Int,
        asciiPLY: Bool
    ) -> [String] {
        var arguments = [
            package.trainScriptURL.path,
            "--frames", package.frameIndexURL.path,
            "--output", package.outputURL.path,
            "--splats-per-frame", "\(max(splatsPerFrame, 1))",
            "--epochs", "\(max(epochs, 1))"
        ]
        if let depthPriorIndexURL = package.depthPriorIndexURL {
            arguments.append(contentsOf: ["--depth-priors", depthPriorIndexURL.path])
        }
        if asciiPLY {
            arguments.append("--ascii-ply")
        }
        return arguments
    }

    private func splatTrainingPythonExecutableURL() -> URL {
        if let explicit = ProcessInfo.processInfo.environment["ROBOT_SCENE_PYTHON"] {
            return URL(fileURLWithPath: explicit)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private func splatTrainingPythonPrefixArguments() -> [String] {
        ProcessInfo.processInfo.environment["ROBOT_SCENE_PYTHON"] == nil ? ["python3"] : []
    }

    private func runProcess(
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
        return (process.terminationStatus, output, error)
    }

    private func makeDatasetManifest() throws -> DatasetManifest {
        guard let preparation else {
            throw WorkstationError.missingPreparedCapture
        }
        let route = expandedRoute ?? alignedRoute ?? preparation.route
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
            requestedProducts: [.rgb, .depth, .visibility, .pose, .segmentation, .obstacleMask, .lidarScan, .failureLabels, .navigationTarget],
            labelSources: labelSourcesForDataset(scene: scene)
        )
        return DatasetGenerator().makeManifest(recipe: recipe, outputDirectory: state.workspaceURL)
    }

    private func labelSourcesForDataset(scene: GaussianSplatScene) -> [LabelSource] {
        var sources: [LabelSource] = []
        var seen = Set<String>()

        func append(_ source: LabelSource) {
            let key: String
            switch source {
            case .roomPlanGeometry(let url):
                key = "roomplan:\(url.standardizedFileURL.path)"
            case .objectCaptureMesh(let url):
                key = "object:\(url.standardizedFileURL.path)"
            case .manualAnnotations(let url):
                key = "manual:\(url.standardizedFileURL.path)"
            }
            guard !seen.contains(key) else { return }
            seen.insert(key)
            sources.append(source)
        }

        if let roomPlanModelURL = scene.roomPlanModelURL {
            append(.roomPlanGeometry(resolveCaptureAssetURL(roomPlanModelURL)))
        }
        if let roomPlanModelURL = importedCapture?.captureBundle.roomPlanModelURL {
            append(.roomPlanGeometry(resolveCaptureAssetURL(roomPlanModelURL)))
        }
        for objectCaptureURL in importedCapture?.captureBundle.objectCaptureAssetURLs ?? [] {
            append(.objectCaptureMesh(resolveCaptureAssetURL(objectCaptureURL)))
        }
        return sources
    }

    private func resolveCaptureAssetURL(_ url: URL) -> URL {
        guard url.scheme == nil, let packageRoot = importedCapture?.packageRoot else {
            return url
        }
        return packageRoot.appendingPathComponent(url.relativePath)
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
            let asset: GaussianSplatAsset
            if let splatAsset {
                asset = splatAsset
            } else {
                asset = try GaussianSplatImporter().inspect(url: splatURL)
            }
            return asset.makeScene(
                id: splatURL.deletingPathExtension().lastPathComponent,
                roomPlanModelURL: importedCapture?.captureBundle.roomPlanModelURL
            )
        }

        let seedURL = state.workspaceURL.appendingPathComponent("splats/capture_route_seed.ply")
        let seedAsset = try RouteDerivedSplatSeedWriter().writeSeedPLY(route: route, to: seedURL)
        splatAsset = seedAsset
        state.activeSplatURL = seedURL
        appendArtifact(title: "Route-Derived Splat Seed", url: seedURL, kind: "splat-seed")
        return GaussianSplatScene(
            id: "capture-route-splat-seed",
            source: .importedPLY(seedURL),
            bounds: seedAsset.bounds,
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

    private func activeSceneBounds(for route: RobotPath) throws -> AxisAlignedBounds {
        if let splatAsset {
            return splatAsset.bounds
        }
        if let sceneBounds = robotSceneManifest?.splatScene.bounds {
            return sceneBounds
        }
        return bounds(from: route)
    }

    private func parseNumberList(_ text: String) -> [Double] {
        text.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func resolve(_ url: URL, relativeTo root: URL) -> URL {
        if url.isFileURL && url.path.hasPrefix("/") {
            return url
        }
        return root.appendingPathComponent(url.relativePath)
    }

    private func handleTransferEvent(_ event: RobotCaptureTransferEvent) {
        switch event {
        case .peerFound(let name):
            transferEvents.insert(WorkstationTransferEvent(title: "iPhone Found", detail: name), at: 0)
        case .peerLost(let name):
            transferEvents.insert(WorkstationTransferEvent(title: "iPhone Lost", detail: name), at: 0)
        case .pairingInvitation(let name):
            if !pendingPairingInvitations.contains(name) {
                pendingPairingInvitations.append(name)
            }
            transferEvents.insert(WorkstationTransferEvent(title: "Pairing Requested", detail: name), at: 0)
        case .pairingAccepted(let name):
            pendingPairingInvitations.removeAll { $0 == name }
            transferEvents.insert(WorkstationTransferEvent(title: "Pairing Accepted", detail: name), at: 0)
        case .pairingRejected(let name):
            pendingPairingInvitations.removeAll { $0 == name }
            transferEvents.insert(WorkstationTransferEvent(title: "Pairing Rejected", detail: name), at: 0)
        case .peerConnected(let name):
            transferEvents.insert(WorkstationTransferEvent(title: "iPhone Connected", detail: name), at: 0)
        case .peerDisconnected(let name):
            transferEvents.insert(WorkstationTransferEvent(title: "iPhone Disconnected", detail: name), at: 0)
            receivingProgressByPeer[name] = nil
        case .packageReceiveStarted(let packageName, let peer):
            receivingProgressByPeer[peer] = 0
            transferEvents.insert(WorkstationTransferEvent(title: "Receiving Capture", detail: "\(packageName) from \(peer)"), at: 0)
        case .packageReceiveProgress(let packageName, let peer, let progress):
            receivingProgressByPeer[peer] = progress
            if progress >= 1 {
                transferEvents.insert(WorkstationTransferEvent(title: "Receive Complete", detail: "\(packageName) from \(peer)"), at: 0)
            }
        case .packageReceiveFinished(let peer, let url):
            receivingProgressByPeer[peer] = nil
            transferEvents.insert(WorkstationTransferEvent(title: "Capture Received", detail: "\(url.lastPathComponent) from \(peer)"), at: 0)
            refreshTransferReceipts()
            importCapture(at: url)
        case .transferReceiptWritten(let url):
            transferEvents.insert(WorkstationTransferEvent(title: "Receipt Written", detail: url.lastPathComponent), at: 0)
            refreshTransferReceipts()
        case .recoverableFailure(let message, _):
            transferEvents.insert(WorkstationTransferEvent(title: "Recoverable Transfer Failure", detail: message), at: 0)
        case .failed(let message):
            transferEvents.insert(WorkstationTransferEvent(title: "Transfer Failed", detail: message), at: 0)
            appendDiagnostic(message)
        case .packageSendStarted, .packageSendProgress, .packageSendFinished:
            break
        }
        if transferEvents.count > 20 {
            transferEvents.removeLast(transferEvents.count - 20)
        }
    }
}

private final class WorkstationMultipeerReceiverDelegate: RobotCaptureTransferDelegate {
    private let handler: @MainActor (RobotCaptureTransferEvent) -> Void

    init(handler: @escaping @MainActor (RobotCaptureTransferEvent) -> Void) {
        self.handler = handler
    }

    func robotCaptureTransferDidEmit(_ event: RobotCaptureTransferEvent) {
        Task { @MainActor in
            handler(event)
        }
    }
}

public enum WorkstationError: Error, LocalizedError {
    case missingCapture
    case missingPreparedCapture
    case missingSplat
    case nativeRenderProductsNotReady(URL)
    case trainingFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .missingCapture:
            "Import a .robotcapture package first."
        case .missingPreparedCapture:
            "Prepare a capture package before running this workstation step."
        case .missingSplat:
            "Link a .ply or .splat scene before rendering Metal splats."
        case .nativeRenderProductsNotReady(let url):
            "Native render products are not ready for MLX training. Render Metal splats first and inspect \(url.path)."
        case .trainingFailed(let url):
            "Apple MLX splat training failed. Inspect \(url.path)."
        }
    }
}
