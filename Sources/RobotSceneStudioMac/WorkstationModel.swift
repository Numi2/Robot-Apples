import Foundation
import Observation
import RobotVisionLabCore
import simd

public enum WorkstationStage: String, Codable, CaseIterable, Sendable {
    case idle
    case importingCapture
    case preparingCapture
    case reconstructingObjectCapture
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
    public private(set) var objectCaptureReconstructionReports: [ObjectCaptureReconstructionReport] = []
    public private(set) var splatAsset: GaussianSplatAsset?
    public private(set) var robotSceneManifest: RobotScenePackageManifest?
    public private(set) var spatialReviewSummary: RobotSceneSpatialReviewSummary?
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

    public func recordFileImportError(_ context: String, error: Error) {
        appendDiagnostic("\(context): \(error.localizedDescription)")
    }

    public func importCapture(at packageURL: URL) {
        perform(stage: .importingCapture) {
            try FileManager.default.createDirectory(at: state.workspaceURL, withIntermediateDirectories: true)
            let importer = RobotCaptureImporter()
            let imported = try importer.importPackage(at: packageURL)
            let report = importer.makeReport(for: imported, packageURL: packageURL)
            let reportURL = state.workspaceURL.appendingPathComponent("robotcapture_import_report.json")
            try importer.writeReport(report, to: reportURL)

            resetPreparedCaptureProducts(clearLinkedSplat: true)
            state.artifacts = []
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
            resetPreparedCaptureProducts(clearLinkedSplat: false)
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

    public func reconstructObjectCaptureImageSets() async {
        await performAsync(stage: .reconstructingObjectCapture) {
            guard var importedCapture else {
                throw WorkstationError.missingCapture
            }
            let reconstructionDirectory = state.workspaceURL.appendingPathComponent("ObjectCaptureReconstruction", isDirectory: true)
            let requests = ObjectCaptureReconstructionPlanner().makeRequests(
                for: importedCapture,
                outputDirectory: reconstructionDirectory
            )
            guard !requests.isEmpty else {
                appendDiagnostic("No Object Capture image sets are linked in the imported package.")
                return
            }

            var reports: [ObjectCaptureReconstructionReport] = []
            for request in requests {
                var report = try await ObjectCaptureReconstructor().reconstruct(request)
                report.outputURL = try persistReconstructedObject(report: report, importedCapture: &importedCapture)
                reports.append(report)
                appendArtifact(
                    title: "Object Capture \(report.label ?? report.imageSetID)",
                    url: report.outputURL,
                    kind: "object-capture-geometry"
                )
                state.warningCount += report.warnings.count
                state.diagnostics.append(contentsOf: report.warnings)
            }

            let reportURL = state.workspaceURL.appendingPathComponent("object_capture_reconstruction_report.json")
            try JSONEncoder.robotVisionLabEncoder.encode(reports).write(to: reportURL)
            self.importedCapture = importedCapture
            objectCaptureReconstructionReports = reports
            if var importHealthReport {
                importHealthReport.objectCaptureAssetCount = importedCapture.captureBundle.objectCaptureAssetURLs.count
                self.importHealthReport = importHealthReport
            }
            appendArtifact(title: "Object Capture Reconstruction Report", url: reportURL, kind: "object-capture-reconstruction")
            appendDiagnostic("Object Capture reconstruction complete: \(reports.count) model(s).")
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
            spatialReviewSummary = try manifest.visionProReviewAsset.reviewSummaryURL.flatMap { summaryURL in
                let resolvedURL = resolve(summaryURL, relativeTo: packageRoot)
                guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return nil }
                return try JSONDecoder.robotVisionLabDecoder.decode(
                    RobotSceneSpatialReviewSummary.self,
                    from: Data(contentsOf: resolvedURL)
                )
            }
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
            if let summaryURL = manifest.visionProReviewAsset.reviewSummaryURL {
                let resolvedURL = resolve(summaryURL, relativeTo: packageRoot)
                if FileManager.default.fileExists(atPath: resolvedURL.path) {
                    appendArtifact(title: "Spatial Review Summary", url: resolvedURL, kind: "spatial-review-summary")
                }
            }
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
            let package = try makeSplatTrainingPackage()
            splatTrainingPackage = package
            appendSplatTrainingPackageArtifacts(package)
        }
    }

    private func makeSplatTrainingPackage() throws -> SplatTrainingPackageManifest {
        guard let preparation else {
            throw WorkstationError.missingPreparedCapture
        }
        let job = SplatTrainingJob(
            id: "\(preparation.splatTrainingManifest.id)-apple-native-splat-package",
            manifest: preparation.splatTrainingManifest,
            backend: AppleNativeTrainingBackend(),
            mode: .nativeAppleSilicon
        )
        return try SplatTrainingPackageBuilder().writePackage(
            job: job,
            manifestURL: preparation.report.splatTrainingManifestURL,
            outputDirectory: state.workspaceURL.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
    }

    private func appendSplatTrainingPackageArtifacts(_ package: SplatTrainingPackageManifest) {
        appendArtifact(title: "Splat Training Package", url: package.trainScriptURL.deletingLastPathComponent(), kind: "splat-training-package")
        appendArtifact(title: "Splat Training Frame Index", url: package.frameIndexURL, kind: "splat-training-index")
        appendArtifact(title: "Capture Splat MLX Script", url: package.trainScriptURL, kind: "splat-training-script")
        if let optimizerPlanURL = package.optimizerPlanURL {
            appendArtifact(title: "Production Splat Optimization Plan", url: optimizerPlanURL, kind: "splat-optimization-plan")
        }
        if let productionDatasetURL = package.productionDatasetURL {
            appendArtifact(title: "Production Splat Dataset", url: productionDatasetURL, kind: "splat-training-dataset")
        }
        if let productionRunnerURL = package.productionRunnerURL {
            appendArtifact(title: "Production Splat Optimizer Runner", url: productionRunnerURL, kind: "splat-training-script")
        }
    }

    public func runSplatTraining(splatsPerFrame: Int = 24, epochs: Int = 25, asciiPLY: Bool = false) {
        Task {
            await runSplatTrainingAsync(splatsPerFrame: splatsPerFrame, epochs: epochs, asciiPLY: asciiPLY)
        }
    }

    public func runSplatTrainingAsync(splatsPerFrame: Int = 24, epochs: Int = 25, asciiPLY: Bool = false) async {
        await performAsync(stage: .runningSplatTraining) {
            let package: SplatTrainingPackageManifest
            if let existingPackage = splatTrainingPackage {
                package = existingPackage
            } else {
                package = try makeSplatTrainingPackage()
                splatTrainingPackage = package
                appendSplatTrainingPackageArtifacts(package)
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
            let result = try await runProcessAsync(
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

    public func runProductionSplatOptimization(
        maxIterations: Int = 30_000,
        method: String = "splatfacto",
        minTrainFrames: Int = ProductionSplatDatasetRequirements.production.minTrainingFrameCount,
        minEvalFrames: Int = ProductionSplatDatasetRequirements.production.minValidationFrameCount,
        minTotalFrames: Int = ProductionSplatDatasetRequirements.production.minTotalFrameCount,
        minPSNR: Double? = nil,
        minSSIM: Double? = nil,
        maxLPIPS: Double? = nil
    ) {
        Task {
            await runProductionSplatOptimizationAsync(
                maxIterations: maxIterations,
                method: method,
                minTrainFrames: minTrainFrames,
                minEvalFrames: minEvalFrames,
                minTotalFrames: minTotalFrames,
                minPSNR: minPSNR,
                minSSIM: minSSIM,
                maxLPIPS: maxLPIPS
            )
        }
    }

    public func runProductionSplatOptimizationAsync(
        maxIterations: Int = 30_000,
        method: String = "splatfacto",
        minTrainFrames: Int = ProductionSplatDatasetRequirements.production.minTrainingFrameCount,
        minEvalFrames: Int = ProductionSplatDatasetRequirements.production.minValidationFrameCount,
        minTotalFrames: Int = ProductionSplatDatasetRequirements.production.minTotalFrameCount,
        minPSNR: Double? = nil,
        minSSIM: Double? = nil,
        maxLPIPS: Double? = nil
    ) async {
        await performAsync(stage: .runningSplatTraining) {
            let package: SplatTrainingPackageManifest
            if let existingPackage = splatTrainingPackage {
                package = existingPackage
            } else {
                package = try makeSplatTrainingPackage()
                splatTrainingPackage = package
                appendSplatTrainingPackageArtifacts(package)
            }
            guard let runnerURL = package.productionRunnerURL else {
                throw WorkstationError.missingProductionOptimizerPackage
            }
            let manifest = try JSONDecoder.robotVisionLabDecoder.decode(
                SplatTrainingManifest.self,
                from: Data(contentsOf: package.sourceManifestURL)
            )
            let job = SplatTrainingJob(
                id: "\(package.id)-production-run",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(
                    name: "Production Splatfacto/gsplat Optimizer",
                    framework: .nerfstudioGSplat,
                    deploymentTarget: .coreML
                ),
                mode: .productionGSplat
            )
            var runnerArguments = [
                runnerURL.path,
                "--method", method,
                "--max-num-iterations", "\(max(maxIterations, 1))",
                "--output", package.outputURL.path,
                "--min-train-frames", "\(max(minTrainFrames, 1))",
                "--min-eval-frames", "\(max(minEvalFrames, 0))",
                "--min-total-frames", "\(max(minTotalFrames, 0))"
            ]
            if let minPSNR {
                runnerArguments.append(contentsOf: ["--min-psnr", "\(minPSNR)"])
            }
            if let minSSIM {
                runnerArguments.append(contentsOf: ["--min-ssim", "\(minSSIM)"])
            }
            if let maxLPIPS {
                runnerArguments.append(contentsOf: ["--max-lpips", "\(maxLPIPS)"])
            }
            let startedAt = Date()
            let result = try await runProcessAsync(
                executableURL: splatTrainingPythonExecutableURL(),
                arguments: splatTrainingPythonPrefixArguments() + runnerArguments,
                currentDirectoryURL: runnerURL.deletingLastPathComponent()
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
            let reportURL = state.workspaceURL.appendingPathComponent("production_splat_optimization_report.json")
            try SplatTrainingReportWriter().write(report, to: reportURL)
            splatTrainingReport = report
            appendArtifact(title: "Production Splat Optimization Report", url: reportURL, kind: "training-report")

            guard result.exitCode == 0 else {
                throw WorkstationError.splatOptimizationFailed(reportURL)
            }

            let asset = try GaussianSplatImporter().inspect(url: package.outputURL)
            splatAsset = asset
            state.activeSplatURL = package.outputURL
            datasetManifest = nil
            metalRenderProfile = nil
            appendArtifact(title: "Production Gaussian Splat", url: package.outputURL, kind: "splat")
            let summaryURL = package.outputURL.deletingPathExtension().appendingPathExtension("production_training_summary.json")
            if FileManager.default.fileExists(atPath: summaryURL.path) {
                appendArtifact(title: "Production Splat Summary", url: summaryURL, kind: "training-summary")
            }
            let evalMetricsURL = runnerURL.deletingLastPathComponent().appendingPathComponent("production_eval_metrics.json")
            if FileManager.default.fileExists(atPath: evalMetricsURL.path) {
                appendArtifact(title: "Production Splat Eval Metrics", url: evalMetricsURL, kind: "training-metrics")
            }
            appendDiagnostic("Production splat optimization complete: \(package.outputURL.lastPathComponent) linked as the active Gaussian splat.")
        }
    }

    public func writeMLXTrainingPackage() {
        perform(stage: .planningTraining) {
            let manifest = try trainingDatasetManifest()
            let manifestURL = datasetManifestURL(for: manifest)
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

    public func augmentRenderedDataset(seed: UInt64 = 0) {
        perform(stage: .buildingDataset) {
            let manifest = try ensureDatasetManifest()
            let report = try DatasetAugmentor().augmentPPMImagesAndPoseLabels(
                manifest: manifest,
                datasetDirectory: state.workspaceURL,
                seed: seed
            )
            let reportURL = state.workspaceURL.appendingPathComponent("augmentation_report.json")
            try DatasetAugmentor().writeReport(report, to: reportURL)
            let augmentedManifest = try JSONDecoder.robotVisionLabDecoder.decode(
                DatasetManifest.self,
                from: Data(contentsOf: report.augmentedManifestURL)
            )
            let readiness = NativeRenderProductValidator().validate(augmentedManifest)
            let readinessURL = state.workspaceURL.appendingPathComponent("native_render_product_readiness_augmented.json")
            try JSONEncoder.robotVisionLabEncoder.encode(readiness).write(to: readinessURL)
            appendArtifact(title: "Augmented Dataset Manifest", url: report.augmentedManifestURL, kind: "dataset-augmented")
            appendArtifact(title: "Augmentation Report", url: reportURL, kind: "dataset-augmentation")
            appendArtifact(title: "Augmented Product Readiness", url: readinessURL, kind: "render-readiness")
            appendArtifact(title: "Augmented RGB Frames", url: state.workspaceURL.appendingPathComponent("rgb_augmented", isDirectory: true), kind: "rgb-augmented")
            appendArtifact(title: "Augmented Pose Labels", url: state.workspaceURL.appendingPathComponent("pose_augmented", isDirectory: true), kind: "pose-augmented")
            appendDiagnostic("Augmented dataset ready: \(report.augmentedFrameCount) frames, \(report.imageOutputs.count) RGB images, \(report.poseOutputs.count) pose labels.")
            if !readiness.isReady {
                throw WorkstationError.nativeRenderProductsNotReady(readinessURL)
            }
        }
    }

    public func exportRobotScene() {
        perform(stage: .exportingRobotScene) {
            let manifest = try ensureDatasetManifest()
            let readiness = NativeRenderProductValidator().validate(manifest)
            let readinessURL = state.workspaceURL.appendingPathComponent("robot_scene_export_readiness.json")
            try JSONEncoder.robotVisionLabEncoder.encode(readiness).write(to: readinessURL)
            appendArtifact(title: "Robot Scene Export Readiness", url: readinessURL, kind: "render-readiness")
            guard readiness.isReady else {
                throw WorkstationError.nativeRenderProductsNotReady(readinessURL)
            }
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

    public func runCurrentPipeline(
        captureURL: URL,
        splatURL: URL? = nil,
        productionMaxIterations: Int = 30_000,
        productionMethod: String = "splatfacto",
        productionMinTrainFrames: Int = ProductionSplatDatasetRequirements.production.minTrainingFrameCount,
        productionMinEvalFrames: Int = ProductionSplatDatasetRequirements.production.minValidationFrameCount,
        productionMinTotalFrames: Int = ProductionSplatDatasetRequirements.production.minTotalFrameCount,
        minPSNR: Double? = nil,
        minSSIM: Double? = nil,
        maxLPIPS: Double? = nil
    ) {
        Task {
            await runCurrentPipelineAsync(
                captureURL: captureURL,
                splatURL: splatURL,
                productionMaxIterations: productionMaxIterations,
                productionMethod: productionMethod,
                productionMinTrainFrames: productionMinTrainFrames,
                productionMinEvalFrames: productionMinEvalFrames,
                productionMinTotalFrames: productionMinTotalFrames,
                minPSNR: minPSNR,
                minSSIM: minSSIM,
                maxLPIPS: maxLPIPS
            )
        }
    }

    public func runCurrentPipelineAsync(
        captureURL: URL,
        splatURL: URL? = nil,
        productionMaxIterations: Int = 30_000,
        productionMethod: String = "splatfacto",
        productionMinTrainFrames: Int = ProductionSplatDatasetRequirements.production.minTrainingFrameCount,
        productionMinEvalFrames: Int = ProductionSplatDatasetRequirements.production.minValidationFrameCount,
        productionMinTotalFrames: Int = ProductionSplatDatasetRequirements.production.minTotalFrameCount,
        minPSNR: Double? = nil,
        minSSIM: Double? = nil,
        maxLPIPS: Double? = nil
    ) async {
        importCapture(at: captureURL)
        guard state.stage != .failed else { return }
        prepareCapture()
        guard state.stage != .failed else { return }
        if let splatURL {
            linkSplat(at: splatURL)
            guard state.stage != .failed else { return }
        } else {
            appendDiagnostic("No linked splat supplied; running production Splatfacto/gsplat optimization before render and export.")
            await runProductionSplatOptimizationAsync(
                maxIterations: productionMaxIterations,
                method: productionMethod,
                minTrainFrames: productionMinTrainFrames,
                minEvalFrames: productionMinEvalFrames,
                minTotalFrames: productionMinTotalFrames,
                minPSNR: minPSNR,
                minSSIM: minSSIM,
                maxLPIPS: maxLPIPS
            )
            guard state.stage != .failed else { return }
        }
        buildDatasetManifest()
        guard state.stage != .failed else { return }
        planMetalRender()
        guard state.stage != .failed else { return }
        renderMetalSplats()
        guard state.stage != .failed else { return }
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

    private func performAsync(stage: WorkstationStage, _ work: () async throws -> Void) async {
        state.stage = stage
        do {
            try await work()
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

    private nonisolated func runProcessAsync(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) async throws -> (exitCode: Int32, standardOutput: String, standardError: String) {
        try await Task.detached(priority: .utility) {
            try Self.runProcessCollectingOutput(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL
            )
        }.value
    }

    private nonisolated static func runProcessCollectingOutput(
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

        let standardOutput = ProcessOutputBuffer()
        let standardError = ProcessOutputBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                standardOutput.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                standardError.append(data)
            }
        }
        try process.run()
        process.waitUntilExit()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        standardOutput.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        standardError.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
        let output = String(data: standardOutput.data, encoding: .utf8) ?? ""
        let error = String(data: standardError.data, encoding: .utf8) ?? ""
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
            augmentations: [
                .exposureEV(-0.5),
                .gaussianNoise(sigma: 0.015),
                .motionBlur(samples: 5, shutterSeconds: 1.0 / 60.0),
                .compressionJPEG(quality: 0.82),
                .cameraHeightJitterMeters(0.03),
                .yawJitterDegrees(2.0)
            ],
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
        guard let packageRoot = importedCapture?.packageRoot else {
            return url
        }
        return PackageURLTools.resolve(url, relativeTo: packageRoot)
    }

    private func ensureDatasetManifest() throws -> DatasetManifest {
        if let datasetManifest {
            return datasetManifest
        }
        let manifest = try makeDatasetManifest()
        datasetManifest = manifest
        return manifest
    }

    private func trainingDatasetManifest() throws -> DatasetManifest {
        let augmentedURL = state.workspaceURL.appendingPathComponent("dataset_augmented.json")
        guard FileManager.default.fileExists(atPath: augmentedURL.path) else {
            return try ensureDatasetManifest()
        }
        return try JSONDecoder.robotVisionLabDecoder.decode(DatasetManifest.self, from: Data(contentsOf: augmentedURL))
    }

    private func datasetManifestURL(for manifest: DatasetManifest) -> URL {
        let augmentedURL = state.workspaceURL.appendingPathComponent("dataset_augmented.json")
        if manifest.recipeID.hasSuffix("-augmented"), FileManager.default.fileExists(atPath: augmentedURL.path) {
            return augmentedURL
        }
        return state.workspaceURL.appendingPathComponent("dataset.json")
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
        _ = route
        throw WorkstationError.missingSplat
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

    private func resetPreparedCaptureProducts(clearLinkedSplat: Bool) {
        preparation = nil
        objectCaptureReconstructionReports = []
        alignedRoute = nil
        expandedRoute = nil
        datasetManifest = nil
        evaluationReportURL = nil
        robotSceneManifest = nil
        spatialReviewSummary = nil
        failureMarkers = []
        routeAlignmentReport = nil
        routeExpansionReport = nil
        routeConfidenceMetrics = nil
        coverageReport = nil
        navigationGraph = nil
        metalRenderProfile = nil
        mlxTrainingPackage = nil
        splatTrainingPackage = nil
        splatTrainingReport = nil
        failureMapCalibrationReport = nil
        state.activeRobotSceneURL = nil
        state.activeRobotSceneID = nil
        state.failureMarkerCount = 0
        if clearLinkedSplat {
            splatAsset = nil
            state.activeSplatURL = nil
        }
    }

    private func persistReconstructedObject(
        report: ObjectCaptureReconstructionReport,
        importedCapture: inout RobotCaptureImport
    ) throws -> URL {
        let packageRoot = importedCapture.packageRoot
        let destinationDirectory = packageRoot.appendingPathComponent("object-capture/reconstructed", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = safeFileComponent(report.label ?? report.imageSetID)
        let destinationURL = uniqueFileURL(
            in: destinationDirectory,
            baseName: baseName.isEmpty ? "object" : baseName,
            pathExtension: report.outputURL.pathExtension.isEmpty ? "usdz" : report.outputURL.pathExtension
        )
        if report.outputURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: report.outputURL, to: destinationURL)
        }

        var captureBundle = importedCapture.captureBundle
        captureBundle.objectCaptureAssetURLs.removeAll {
            PackageURLTools.resolve($0, relativeTo: packageRoot).standardizedFileURL.path == destinationURL.standardizedFileURL.path
        }
        captureBundle.objectCaptureAssetURLs.append(destinationURL)
        captureBundle.scanSession.objectCaptureAssetURLs = captureBundle.objectCaptureAssetURLs
        let portableCaptureBundle = packageRelative(captureBundle, packageRoot: packageRoot)
        try JSONEncoder.robotVisionLabEncoder.encode(portableCaptureBundle).write(to: packageRoot.appendingPathComponent("capture_bundle.json"))

        var manifest = importedCapture.manifest
        let tools = SharedProjectFormatTools()
        manifest.artifacts.removeAll {
            $0.role == "object-capture-geometry"
                && PackageURLTools.resolve($0.url, relativeTo: packageRoot).standardizedFileURL.path == destinationURL.standardizedFileURL.path
        }
        manifest.artifacts.append(tools.artifactRecord(role: "object-capture-geometry", url: destinationURL, packageRoot: packageRoot))
        let validation = tools.validate(
            packageID: manifest.id,
            packageKind: "robotcapture",
            schemaVersion: manifest.schemaVersion,
            artifacts: manifest.artifacts,
            policy: manifest.artifactPolicy,
            packageRoot: packageRoot
        )
        let reportURLs = try tools.writeReports(validation, to: packageRoot, title: ".robotcapture Project Report")
        manifest.validationReportURL = PackageURLTools.packageRelativeURL(for: reportURLs.json, packageRoot: packageRoot)
        manifest.humanReportURL = PackageURLTools.packageRelativeURL(for: reportURLs.markdown, packageRoot: packageRoot)
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: packageRoot.appendingPathComponent("robotcapture.json"))

        importedCapture.manifest = manifest
        importedCapture.captureBundle = captureBundle
        return destinationURL
    }

    private func packageRelative(_ bundle: CaptureBundleManifest, packageRoot: URL) -> CaptureBundleManifest {
        let scanSession = packageRelative(bundle.scanSession, packageRoot: packageRoot)
        return CaptureBundleManifest(
            scanSession: scanSession,
            capturePlan: bundle.capturePlan,
            rgbFrames: bundle.rgbFrames.map { packageRelative($0, packageRoot: packageRoot) },
            lidarFrames: bundle.lidarFrames.map { packageRelative($0, packageRoot: packageRoot) },
            roomPlanModelURL: bundle.roomPlanModelURL.map { PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot) },
            objectCaptureAssetURLs: bundle.objectCaptureAssetURLs.map { PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot) },
            objectCaptureImageSets: bundle.objectCaptureImageSets.map { packageRelative($0, packageRoot: packageRoot) },
            splatTrainingManifestURL: PackageURLTools.packageRelativeURL(for: bundle.splatTrainingManifestURL, packageRoot: packageRoot)
        )
    }

    private func packageRelative(_ scanSession: ScanSession, packageRoot: URL) -> ScanSession {
        ScanSession(
            id: scanSession.id,
            createdAt: scanSession.createdAt,
            worldUnit: scanSession.worldUnit,
            rgbFrames: scanSession.rgbFrames.map { packageRelative($0, packageRoot: packageRoot) },
            lidarFrames: scanSession.lidarFrames.map { packageRelative($0, packageRoot: packageRoot) },
            roomPlanModelURL: scanSession.roomPlanModelURL.map { PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot) },
            objectCaptureAssetURLs: scanSession.objectCaptureAssetURLs.map { PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot) },
            objectCaptureImageSets: scanSession.objectCaptureImageSets.map { packageRelative($0, packageRoot: packageRoot) }
        )
    }

    private func packageRelative(_ frame: CapturedRGBFrame, packageRoot: URL) -> CapturedRGBFrame {
        CapturedRGBFrame(
            imageURL: PackageURLTools.packageRelativeURL(for: frame.imageURL, packageRoot: packageRoot),
            pose: frame.pose,
            timestamp: frame.timestamp
        )
    }

    private func packageRelative(_ frame: CapturedLiDARFrame, packageRoot: URL) -> CapturedLiDARFrame {
        CapturedLiDARFrame(
            depthURL: PackageURLTools.packageRelativeURL(for: frame.depthURL, packageRoot: packageRoot),
            confidenceURL: frame.confidenceURL.map { PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot) },
            metadataURL: PackageURLTools.packageRelativeURL(for: frame.metadataURL, packageRoot: packageRoot),
            pose: frame.pose,
            timestamp: frame.timestamp
        )
    }

    private func packageRelative(_ imageSet: ObjectCaptureImageSet, packageRoot: URL) -> ObjectCaptureImageSet {
        ObjectCaptureImageSet(
            id: imageSet.id,
            label: imageSet.label,
            imagesDirectoryURL: PackageURLTools.packageRelativeURL(for: imageSet.imagesDirectoryURL, packageRoot: packageRoot),
            checkpointDirectoryURL: imageSet.checkpointDirectoryURL.map {
                PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageRoot)
            },
            imageCount: imageSet.imageCount,
            createdAt: imageSet.createdAt,
            notes: imageSet.notes
        )
    }

    private func uniqueFileURL(in directory: URL, baseName: String, pathExtension: String) -> URL {
        var index = 1
        while true {
            let suffix = index == 1 ? "" : "-\(index)"
            let candidate = directory.appendingPathComponent("\(baseName)\(suffix)").appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "object" : sanitized
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
        PackageURLTools.resolve(url, relativeTo: root)
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

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class WorkstationMultipeerReceiverDelegate: RobotCaptureTransferDelegate, @unchecked Sendable {
    private let handler: @MainActor @Sendable (RobotCaptureTransferEvent) -> Void

    init(handler: @escaping @MainActor @Sendable (RobotCaptureTransferEvent) -> Void) {
        self.handler = handler
    }

    func robotCaptureTransferDidEmit(_ event: RobotCaptureTransferEvent) {
        let handler = handler
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
    case missingProductionOptimizerPackage
    case splatOptimizationFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .missingCapture:
            "Import a .robotcapture package first."
        case .missingPreparedCapture:
            "Prepare a capture package before running this workstation step."
        case .missingSplat:
            "Link an imported .ply/.spz/.splat scene or run capture splat training before building/exporting a Robot Scene."
        case .nativeRenderProductsNotReady(let url):
            "Native render products are not ready for MLX training. Render Metal splats first and inspect \(url.path)."
        case .trainingFailed(let url):
            "Apple MLX splat training failed. Inspect \(url.path)."
        case .missingProductionOptimizerPackage:
            "Write a splat training package before running production splat optimization."
        case .splatOptimizationFailed(let url):
            "Production splat optimization failed. Inspect \(url.path)."
        }
    }
}
