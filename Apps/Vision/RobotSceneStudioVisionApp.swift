import RobotSceneStudioVision
import SwiftUI

@main
struct RobotSceneStudioVisionApp: App {
    @State private var model = SpatialReviewModel()

    var body: some Scene {
        WindowGroup {
            SpatialReviewRootView(model: model)
        }
        .defaultSize(width: 900, height: 700)
    }
}

struct SpatialReviewRootView: View {
    let model: SpatialReviewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Review Layers") {
                    ForEach(SpatialReviewLayer.allCases, id: \.self) { layer in
                        Label(layer.rawValue, systemImage: symbol(for: layer))
                    }
                }
            }
            .navigationTitle("Robot Scene Review")
        }
    }

    private func symbol(for layer: SpatialReviewLayer) -> String {
        switch layer {
        case .gaussianSplat: "camera.metering.matrix"
        case .robotRoutes: "point.topleft.down.curvedto.point.bottomright.up"
        case .cameraFrustums: "video"
        case .navigationGraph: "point.3.connected.trianglepath.dotted"
        case .failureMap: "exclamationmark.triangle"
        case .predictions: "brain"
        }
    }
}
