import Foundation
import Observation
import RobotVisionLabCore
import simd

public enum SpatialReviewLayer: String, Codable, CaseIterable, Sendable {
    case gaussianSplat
    case robotRoutes
    case cameraFrustums
    case navigationGraph
    case failureMap
    case predictions
}

public struct SpatialReviewState: Codable, Equatable, Sendable {
    public var robotSceneURL: URL?
    public var enabledLayers: Set<SpatialReviewLayer>
    public var selectedFrameIndex: Int?
    public var summary: SpatialReviewSceneSummary?
    public var overlay: SpatialReviewOverlay?
    public var diagnostics: [String]

    public init(
        robotSceneURL: URL? = nil,
        enabledLayers: Set<SpatialReviewLayer> = Set(SpatialReviewLayer.allCases),
        selectedFrameIndex: Int? = nil,
        summary: SpatialReviewSceneSummary? = nil,
        overlay: SpatialReviewOverlay? = nil,
        diagnostics: [String] = []
    ) {
        self.robotSceneURL = robotSceneURL
        self.enabledLayers = enabledLayers
        self.selectedFrameIndex = selectedFrameIndex
        self.summary = summary
        self.overlay = overlay
        self.diagnostics = diagnostics
    }
}

public struct SpatialReviewSceneSummary: Codable, Equatable, Sendable {
    public var sceneID: String
    public var splatURL: URL?
    public var frameCount: Int
    public var routePoseCount: Int
    public var navigationNodeCount: Int
    public var navigationEdgeCount: Int
    public var failureMarkerCount: Int
    public var failureMarkerCountsBySource: [FailureEvidenceSource: Int]
    public var evaluationFrameCount: Int
    public var availableLayers: Set<SpatialReviewLayer>

    public init(
        sceneID: String,
        splatURL: URL?,
        frameCount: Int,
        routePoseCount: Int,
        navigationNodeCount: Int,
        navigationEdgeCount: Int,
        failureMarkerCount: Int,
        failureMarkerCountsBySource: [FailureEvidenceSource: Int] = [:],
        evaluationFrameCount: Int,
        availableLayers: Set<SpatialReviewLayer>
    ) {
        self.sceneID = sceneID
        self.splatURL = splatURL
        self.frameCount = frameCount
        self.routePoseCount = routePoseCount
        self.navigationNodeCount = navigationNodeCount
        self.navigationEdgeCount = navigationEdgeCount
        self.failureMarkerCount = failureMarkerCount
        self.failureMarkerCountsBySource = failureMarkerCountsBySource
        self.evaluationFrameCount = evaluationFrameCount
        self.availableLayers = availableLayers
    }
}

public struct SpatialReviewOverlay: Codable, Equatable, Sendable {
    public var route: [SpatialReviewRoutePose]
    public var cameraFrustums: [SpatialReviewCameraFrustum]
    public var navigationNodes: [SpatialReviewNavigationNode]
    public var navigationEdges: [SpatialReviewNavigationEdge]
    public var failureMarkers: [SpatialReviewFailureMarker]

    public init(
        route: [SpatialReviewRoutePose] = [],
        cameraFrustums: [SpatialReviewCameraFrustum] = [],
        navigationNodes: [SpatialReviewNavigationNode] = [],
        navigationEdges: [SpatialReviewNavigationEdge] = [],
        failureMarkers: [SpatialReviewFailureMarker] = []
    ) {
        self.route = route
        self.cameraFrustums = cameraFrustums
        self.navigationNodes = navigationNodes
        self.navigationEdges = navigationEdges
        self.failureMarkers = failureMarkers
    }
}

public struct SpatialReviewRoutePose: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var timestamp: TimeInterval
    public var pose: Pose3D
}

public struct SpatialReviewCameraFrustum: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var origin: SIMD3<Double>
    public var forward: SIMD3<Double>
    public var up: SIMD3<Double>
    public var right: SIMD3<Double>
    public var nearMeters: Double
    public var farMeters: Double
}

public struct SpatialReviewNavigationNode: Codable, Equatable, Sendable {
    public var id: String
    public var position: SIMD3<Double>
    public var label: String?
}

public struct SpatialReviewNavigationEdge: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var traversalCost: Double
}

public struct SpatialReviewFailureMarker: Codable, Equatable, Sendable {
    public var id: String
    public var frameIndex: Int?
    public var position: SIMD3<Double>
    public var kind: FailureMarkerKind
    public var confidence: Double
    public var displayColor: SIMD3<Double>
    public var label: String
    public var note: String
    public var evidenceSources: Set<FailureEvidenceSource>
}

@Observable
public final class SpatialReviewModel {
    public var state: SpatialReviewState

    public init(state: SpatialReviewState = SpatialReviewState()) {
        self.state = state
    }

    public func openRobotScene(at packageURL: URL) throws {
        let manifestURL = packageURL.pathExtension == "json" ? packageURL : packageURL.appendingPathComponent("robotscene.json")
        let packageRoot = manifestURL.deletingLastPathComponent()
        let manifest = try JSONDecoder.robotVisionLabDecoder.decode(
            RobotScenePackageManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let dataset = try decodeIfPresent(DatasetManifest.self, manifest.datasetManifestURL, relativeTo: packageRoot)
        let graph = try decodeIfPresent(NavigationGraph.self, manifest.navigationGraphURL, relativeTo: packageRoot)
        let failureMap = try decodeIfPresent([FailureMapMarker].self, manifest.failureMapURL, relativeTo: packageRoot) ?? []
        let routeLabels = try decodeIfPresent(
            [PoseLabel].self,
            manifest.visionProReviewAsset.robotRouteURL,
            relativeTo: packageRoot
        ) ?? []
        let evaluation = try manifest.visionProReviewAsset.evaluationReportURL.flatMap {
            try decodeIfPresent(ModelEvaluationReport.self, $0, relativeTo: packageRoot)
        }
        let splatURL = resolvedSplatURL(from: manifest, relativeTo: packageRoot)
        var layers: Set<SpatialReviewLayer> = [.robotRoutes, .cameraFrustums, .navigationGraph, .failureMap]
        var diagnostics: [String] = []
        if splatURL != nil {
            layers.insert(.gaussianSplat)
        } else if manifest.visionProReviewAsset.splatSceneURL != nil || manifest.splatScene.sourceURL != nil {
            diagnostics.append("Gaussian splat asset is referenced by the .robotscene package but was not found.")
        }
        if evaluation != nil {
            layers.insert(.predictions)
        }
        let overlay = SpatialReviewOverlay(
            route: routeLabels.map { SpatialReviewRoutePose(frameIndex: $0.frameIndex, timestamp: $0.timestamp, pose: $0.cameraPose) },
            cameraFrustums: routeLabels.map { cameraFrustum(for: $0) },
            navigationNodes: graph?.nodes.map {
                SpatialReviewNavigationNode(id: $0.id, position: $0.position, label: $0.label)
            } ?? [],
            navigationEdges: graph?.edges.map {
                SpatialReviewNavigationEdge(from: $0.from, to: $0.to, traversalCost: $0.traversalCost)
            } ?? [],
            failureMarkers: failureMap.map { reviewFailureMarker($0) }
        )
        state.summary = SpatialReviewSceneSummary(
            sceneID: manifest.id,
            splatURL: splatURL,
            frameCount: dataset?.frames.count ?? 0,
            routePoseCount: routeLabels.count,
            navigationNodeCount: graph?.nodes.count ?? 0,
            navigationEdgeCount: graph?.edges.count ?? 0,
            failureMarkerCount: failureMap.count,
            failureMarkerCountsBySource: failureMarkerCountsBySource(failureMap),
            evaluationFrameCount: evaluation?.summary.frameCount ?? 0,
            availableLayers: layers
        )
        state.overlay = overlay
        state.enabledLayers = layers
        state.robotSceneURL = packageURL
        state.diagnostics = diagnostics
    }

    public func openRobotSceneReportingErrors(at packageURL: URL) {
        do {
            try openRobotScene(at: packageURL)
        } catch {
            state.robotSceneURL = packageURL
            state.overlay = nil
            state.diagnostics = [error.localizedDescription]
        }
    }

    public func setLayer(_ layer: SpatialReviewLayer, isEnabled: Bool) {
        if isEnabled {
            state.enabledLayers.insert(layer)
        } else {
            state.enabledLayers.remove(layer)
        }
    }

    public func selectFrame(index: Int?) {
        state.selectedFrameIndex = index
    }

    public var selectedRoutePose: SpatialReviewRoutePose? {
        guard let selectedFrameIndex = state.selectedFrameIndex else { return nil }
        return state.overlay?.route.first { $0.frameIndex == selectedFrameIndex }
    }

    public var selectedFailureMarkers: [SpatialReviewFailureMarker] {
        guard let selectedFrameIndex = state.selectedFrameIndex else {
            return state.overlay?.failureMarkers ?? []
        }
        return state.overlay?.failureMarkers.filter { $0.frameIndex == selectedFrameIndex } ?? []
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, _ url: URL, relativeTo root: URL) throws -> T? {
        let resolved = resolve(url, relativeTo: root)
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        return try JSONDecoder.robotVisionLabDecoder.decode(T.self, from: Data(contentsOf: resolved))
    }

    private func resolvedSplatURL(from manifest: RobotScenePackageManifest, relativeTo packageRoot: URL) -> URL? {
        let candidates = [
            manifest.visionProReviewAsset.splatSceneURL,
            manifest.splatScene.sourceURL
        ].compactMap { $0 }
        for candidate in candidates {
            let resolved = resolve(candidate, relativeTo: packageRoot)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }
        return nil
    }

    private func resolve(_ url: URL, relativeTo root: URL) -> URL {
        if url.isFileURL && url.path.hasPrefix("/") {
            return url
        }
        return root.appendingPathComponent(url.relativePath)
    }

    private func failureMarkerCountsBySource(_ markers: [FailureMapMarker]) -> [FailureEvidenceSource: Int] {
        var counts: [FailureEvidenceSource: Int] = [:]
        for marker in markers {
            for source in marker.evidenceSources {
                counts[source, default: 0] += 1
            }
        }
        return counts
    }

    private func cameraFrustum(for label: PoseLabel) -> SpatialReviewCameraFrustum {
        let orientation = label.cameraPose.orientation.vector
        return SpatialReviewCameraFrustum(
            frameIndex: label.frameIndex,
            origin: label.cameraPose.position,
            forward: rotate(SIMD3<Double>(0, 0, -1), by: orientation),
            up: rotate(SIMD3<Double>(0, 1, 0), by: orientation),
            right: rotate(SIMD3<Double>(1, 0, 0), by: orientation),
            nearMeters: 0.05,
            farMeters: 0.45
        )
    }

    private func reviewFailureMarker(_ marker: FailureMapMarker) -> SpatialReviewFailureMarker {
        SpatialReviewFailureMarker(
            id: marker.id,
            frameIndex: marker.frameIndex,
            position: marker.position,
            kind: marker.kind,
            confidence: marker.confidence,
            displayColor: marker.kind.spatialReviewColor,
            label: marker.kind.spatialReviewLabel,
            note: marker.note,
            evidenceSources: marker.evidenceSources
        )
    }

    private func rotate(_ vector: SIMD3<Double>, by quaternion: SIMD4<Double>) -> SIMD3<Double> {
        let q = SIMD3<Double>(quaternion.x, quaternion.y, quaternion.z)
        let t = 2 * simd_cross(q, vector)
        return vector + quaternion.w * t + simd_cross(q, t)
    }
}

private extension FailureMarkerKind {
    var spatialReviewLabel: String {
        switch self {
        case .confident: "Confident"
        case .uncertainLocalization: "Uncertain localization"
        case .blockedPrediction: "Blocked"
        case .missingTrainingViews: "Missing views"
        case .visualAmbiguity: "Visual ambiguity"
        case .badLighting: "Lighting"
        case .lowTexture: "Low texture"
        }
    }

    var spatialReviewColor: SIMD3<Double> {
        switch self {
        case .confident: SIMD3<Double>(0.0, 0.82, 0.35)
        case .uncertainLocalization: SIMD3<Double>(1.0, 0.78, 0.0)
        case .blockedPrediction: SIMD3<Double>(1.0, 0.15, 0.12)
        case .missingTrainingViews: SIMD3<Double>(0.15, 0.45, 1.0)
        case .visualAmbiguity: SIMD3<Double>(0.65, 0.35, 1.0)
        case .badLighting: SIMD3<Double>(1.0, 0.55, 0.08)
        case .lowTexture: SIMD3<Double>(0.55, 0.58, 0.62)
        }
    }
}
