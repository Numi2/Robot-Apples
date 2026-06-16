import XCTest
@testable import RobotSceneStudioVision
import RobotSceneStudioSplatViewer
import RobotVisionLabCore
import simd

final class SpatialReviewOverlayPayloadTests: XCTestCase {
    func testImmersiveOverlayPayloadIncludesEnabledReviewLayers() {
        let model = SpatialReviewModel(state: SpatialReviewState(
            enabledLayers: [.robotRoutes, .cameraFrustums, .navigationGraph, .failureMap, .predictions],
            overlay: makeOverlay()
        ))

        let payload = model.immersiveOverlayPayload()

        XCTAssertTrue(payload.lineSegments.contains { $0.layer == .robotRoutes })
        XCTAssertTrue(payload.lineSegments.contains { $0.layer == .cameraFrustums })
        XCTAssertTrue(payload.lineSegments.contains { $0.layer == .navigationGraph })
        XCTAssertTrue(payload.pointMarkers.contains { $0.layer == .navigationGraph })
        XCTAssertTrue(payload.pointMarkers.contains { $0.layer == .failureMap })
        XCTAssertTrue(payload.pointMarkers.contains { $0.layer == .predictions })
    }

    func testImmersiveOverlayPayloadRespectsLayerToggles() {
        let model = SpatialReviewModel(state: SpatialReviewState(
            enabledLayers: [.robotRoutes],
            overlay: makeOverlay()
        ))

        let payload = model.immersiveOverlayPayload()

        XCTAssertFalse(payload.lineSegments.isEmpty)
        XCTAssertTrue(payload.lineSegments.allSatisfy { $0.layer == .robotRoutes })
        XCTAssertTrue(payload.pointMarkers.isEmpty)
    }

    private func makeOverlay() -> SpatialReviewOverlay {
        let route = [
            SpatialReviewRoutePose(
                frameIndex: 0,
                timestamp: 0,
                pose: Pose3D(position: SIMD3<Double>(0, 0, 0))
            ),
            SpatialReviewRoutePose(
                frameIndex: 1,
                timestamp: 1,
                pose: Pose3D(position: SIMD3<Double>(1, 0, 0))
            )
        ]
        let frustum = SpatialReviewCameraFrustum(
            frameIndex: 0,
            origin: SIMD3<Double>(0, 0, 0),
            forward: SIMD3<Double>(0, 0, -1),
            up: SIMD3<Double>(0, 1, 0),
            right: SIMD3<Double>(1, 0, 0),
            nearMeters: 0.05,
            farMeters: 0.45
        )
        let nodes = [
            SpatialReviewNavigationNode(id: "a", position: SIMD3<Double>(0, 0, 0), label: "A"),
            SpatialReviewNavigationNode(id: "b", position: SIMD3<Double>(1, 0, 0), label: "B")
        ]
        let marker = SpatialReviewFailureMarker(
            id: "failure",
            frameIndex: 0,
            position: SIMD3<Double>(0.5, 0, -0.5),
            kind: .blockedPrediction,
            confidence: 0.8,
            displayColor: SIMD3<Double>(1, 0.15, 0.12),
            label: "Blocked prediction",
            note: "test",
            evidenceSources: [.modelPrediction],
            modelLabel: "obstacle",
            modelSource: "test",
            lidarEvidence: nil
        )
        let risk = SpatialReviewFrameRisk(
            frameIndex: 0,
            position: SIMD3<Double>(0, 0, 0),
            riskScore: 0.7,
            dominantKind: .blockedPrediction,
            markerCount: 1,
            modelEvidenceCount: 1,
            lidarEvidenceCount: 0,
            evidenceSources: [.modelPrediction],
            summary: "risk"
        )
        return SpatialReviewOverlay(
            route: route,
            cameraFrustums: [frustum],
            navigationNodes: nodes,
            navigationEdges: [SpatialReviewNavigationEdge(from: "a", to: "b", traversalCost: 1)],
            failureMarkers: [marker],
            frameRisks: [risk]
        )
    }
}
