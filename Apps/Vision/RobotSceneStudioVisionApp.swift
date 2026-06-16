import CompositorServices
import RobotSceneStudioSplatViewer
import RobotSceneStudioVision
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var robotScenePackage: UTType {
        UTType(filenameExtension: "robotscene") ?? .package
    }
}

@main
struct RobotSceneStudioVisionApp: App {
    @State private var model = SpatialReviewModel()

    var body: some Scene {
        WindowGroup {
            SpatialReviewRootView(model: model)
        }
        .defaultSize(width: 900, height: 700)

        ImmersiveSpace(for: MetalSplatterImmersiveScene.self) { scene in
            CompositorLayer(configuration: MetalSplatterContentStageConfiguration()) { layerRenderer in
                MetalSplatterVisionSceneRenderer.startRendering(
                    layerRenderer,
                    splatURL: scene.wrappedValue?.splatURL
                )
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

struct SpatialReviewRootView: View {
    @Bindable var model: SpatialReviewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isOpeningRobotScene = false
    @State private var immersiveSpaceIsOpen = false

    var body: some View {
        NavigationStack {
            List {
                Section("Scene") {
                    Button {
                        isOpeningRobotScene = true
                    } label: {
                        Label("Open .robotscene", systemImage: "folder")
                    }
                    if let summary = model.state.summary {
                        LabeledContent("Scene", value: summary.sceneID)
                        LabeledContent("Frames", value: "\(summary.frameCount)")
                        LabeledContent("Route Poses", value: "\(summary.routePoseCount)")
                        LabeledContent("Graph", value: "\(summary.navigationNodeCount) nodes, \(summary.navigationEdgeCount) edges")
                        LabeledContent("Failures", value: "\(summary.failureMarkerCount)")
                        LabeledContent("Evaluated", value: "\(summary.evaluationFrameCount)")
                        if let splatURL = summary.splatURL {
                            Button {
                                Task {
                                    switch await openImmersiveSpace(value: MetalSplatterImmersiveScene(splatURL: splatURL)) {
                                    case .opened:
                                        immersiveSpaceIsOpen = true
                                    case .error, .userCancelled:
                                        break
                                    @unknown default:
                                        break
                                    }
                                }
                            } label: {
                                Label("Open Splat Space", systemImage: "visionpro")
                            }
                            .disabled(immersiveSpaceIsOpen)
                        }
                    } else {
                        Text("Open a Robot Scene package exported from the Mac workstation.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Review Layers") {
                    ForEach(SpatialReviewLayer.allCases, id: \.self) { layer in
                        Toggle(isOn: binding(for: layer)) {
                            Label(title(for: layer), systemImage: symbol(for: layer))
                        }
                        .disabled(!(model.state.summary?.availableLayers.contains(layer) ?? true))
                    }
                }

                if let summary = model.state.summary, summary.frameCount > 0 {
                    Section("Frame") {
                        Stepper(
                            value: Binding(
                                get: { model.state.selectedFrameIndex ?? 0 },
                                set: { model.selectFrame(index: min(max($0, 0), summary.frameCount - 1)) }
                            ),
                            in: 0...max(summary.frameCount - 1, 0)
                        ) {
                            Label("Frame \(model.state.selectedFrameIndex ?? 0)", systemImage: "film")
                        }
                    }
                }

                if !model.state.diagnostics.isEmpty {
                    Section("Diagnostics") {
                        ForEach(model.state.diagnostics, id: \.self) { diagnostic in
                            Text(diagnostic)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if immersiveSpaceIsOpen {
                    Section {
                        Button {
                            Task {
                                await dismissImmersiveSpace()
                                immersiveSpaceIsOpen = false
                            }
                        } label: {
                            Label("Close Splat Space", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Robot Scene Review")
        }
        .fileImporter(
            isPresented: $isOpeningRobotScene,
            allowedContentTypes: [.robotScenePackage, .json],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                model.openRobotSceneReportingErrors(at: url)
            }
        }
    }

    private func binding(for layer: SpatialReviewLayer) -> Binding<Bool> {
        Binding(
            get: { model.state.enabledLayers.contains(layer) },
            set: { model.setLayer(layer, isEnabled: $0) }
        )
    }

    private func title(for layer: SpatialReviewLayer) -> String {
        switch layer {
        case .gaussianSplat: "Gaussian Splat"
        case .robotRoutes: "Robot Routes"
        case .cameraFrustums: "Camera Frustums"
        case .navigationGraph: "Navigation Graph"
        case .failureMap: "Failure Map"
        case .predictions: "Predictions"
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
