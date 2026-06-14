import Foundation
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

    public init(
        robotSceneURL: URL? = nil,
        enabledLayers: Set<SpatialReviewLayer> = Set(SpatialReviewLayer.allCases),
        selectedFrameIndex: Int? = nil
    ) {
        self.robotSceneURL = robotSceneURL
        self.enabledLayers = enabledLayers
        self.selectedFrameIndex = selectedFrameIndex
    }
}

public final class SpatialReviewModel {
    public private(set) var state: SpatialReviewState

    public init(state: SpatialReviewState = SpatialReviewState()) {
        self.state = state
    }

    public func openRobotScene(at packageURL: URL) {
        state.robotSceneURL = packageURL
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
}
