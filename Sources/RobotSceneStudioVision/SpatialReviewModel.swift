import Foundation
import Observation
import RobotVisionLabCore

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
    public var diagnostics: [String]

    public init(
        robotSceneURL: URL? = nil,
        enabledLayers: Set<SpatialReviewLayer> = Set(SpatialReviewLayer.allCases),
        selectedFrameIndex: Int? = nil,
        summary: SpatialReviewSceneSummary? = nil,
        diagnostics: [String] = []
    ) {
        self.robotSceneURL = robotSceneURL
        self.enabledLayers = enabledLayers
        self.selectedFrameIndex = selectedFrameIndex
        self.summary = summary
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
        self.evaluationFrameCount = evaluationFrameCount
        self.availableLayers = availableLayers
    }
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
        var layers: Set<SpatialReviewLayer> = [.robotRoutes, .cameraFrustums, .navigationGraph, .failureMap]
        if manifest.splatScene.sourceURL != nil {
            layers.insert(.gaussianSplat)
        }
        if evaluation != nil {
            layers.insert(.predictions)
        }
        state.summary = SpatialReviewSceneSummary(
            sceneID: manifest.id,
            splatURL: manifest.splatScene.sourceURL,
            frameCount: dataset?.frames.count ?? 0,
            routePoseCount: routeLabels.count,
            navigationNodeCount: graph?.nodes.count ?? 0,
            navigationEdgeCount: graph?.edges.count ?? 0,
            failureMarkerCount: failureMap.count,
            evaluationFrameCount: evaluation?.summary.frameCount ?? 0,
            availableLayers: layers
        )
        state.enabledLayers = layers
        state.robotSceneURL = packageURL
        state.diagnostics = []
    }

    public func openRobotSceneReportingErrors(at packageURL: URL) {
        do {
            try openRobotScene(at: packageURL)
        } catch {
            state.robotSceneURL = packageURL
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

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, _ url: URL, relativeTo root: URL) throws -> T? {
        let resolved = url.isFileURL && url.path.hasPrefix("/") ? url : root.appendingPathComponent(url.path)
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        return try JSONDecoder.robotVisionLabDecoder.decode(T.self, from: Data(contentsOf: resolved))
    }
}
