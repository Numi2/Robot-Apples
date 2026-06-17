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
                    sessionID: scene.wrappedValue?.sessionID ?? UUID().uuidString,
                    splatURL: scene.wrappedValue?.splatURL,
                    modelTransform: scene.wrappedValue?.modelTransform ?? metalSplatterIdentityMatrixPayload,
                    spatialOverlay: scene.wrappedValue?.spatialOverlay ?? .empty
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
    @State private var splatSessionID = UUID().uuidString
    @State private var splatControls = MetalSplatterImmersiveSceneControls.default
    @State private var splatStatus = MetalSplatterImmersiveSceneStatus()

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
                                    await openSplatSpace(splatURL: splatURL, summary: summary)
                                }
                            } label: {
                                Label(immersiveSpaceIsOpen ? "Reopen Splat Space" : "Open Splat Space", systemImage: "visionpro")
                            }
                        }
                    } else {
                        Text("Open a Robot Scene package exported from the Mac workstation.")
                            .foregroundStyle(.secondary)
                    }
                }

                if model.state.summary?.splatURL != nil {
                    Section("Splat Space") {
                        LabeledContent("Status", value: splatStatus.message)
                        Toggle("Auto Rotate", isOn: Binding(
                            get: { splatControls.automaticRotationEnabled },
                            set: { splatControls.automaticRotationEnabled = $0 }
                        ))
                        SliderRow(title: "Scale", value: floatBinding(\.scale), range: 0.1...8, format: "%.2fx")
                        SliderRow(title: "Yaw", value: floatBinding(\.yawRadians), range: -Float.pi...Float.pi, format: "%.2f rad")
                        SliderRow(title: "Pitch", value: floatBinding(\.pitchRadians), range: -Float.pi / 2...Float.pi / 2, format: "%.2f rad")
                        SliderRow(title: "Roll", value: floatBinding(\.rollRadians), range: -Float.pi...Float.pi, format: "%.2f rad")
                        SliderRow(title: "Offset X", value: floatBinding(\.recenterOffsetX), range: -2...2, format: "%.2fm")
                        SliderRow(title: "Offset Y", value: floatBinding(\.recenterOffsetY), range: -2...2, format: "%.2fm")
                        SliderRow(title: "Offset Z", value: floatBinding(\.recenterOffsetZ), range: -2...2, format: "%.2fm")
                        HStack {
                            Button {
                                splatControls.recenterOffsetX = 0
                                splatControls.recenterOffsetY = 0
                                splatControls.recenterOffsetZ = 0
                            } label: {
                                Label("Recenter", systemImage: "scope")
                            }
                            Button {
                                splatControls = .default
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                        }
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
        .task {
            while !Task.isCancelled {
                splatStatus = MetalSplatterVisionSceneSessionStore.shared.status(for: splatSessionID)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .onChange(of: splatControls) { _, controls in
            MetalSplatterVisionSceneSessionStore.shared.setControls(controls, for: splatSessionID)
        }
        .onChange(of: model.state.summary?.sceneID) { _, _ in
            splatControls = .default
            splatSessionID = UUID().uuidString
            immersiveSpaceIsOpen = false
            splatStatus = MetalSplatterImmersiveSceneStatus()
        }
        .fileImporter(
            isPresented: $isOpeningRobotScene,
            allowedContentTypes: [.robotScenePackage, .json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                model.openRobotSceneReportingErrors(at: url)
            } catch {
                model.recordDiagnostic("Unable to open Robot Scene package: \(error.localizedDescription)")
            }
        }
        .onOpenURL { url in
            let isRobotScenePackage = url.pathExtension.lowercased() == "robotscene"
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("robotscene.json").path)
            let isRobotSceneManifest = url.lastPathComponent == "robotscene.json"
            if isRobotScenePackage || isRobotSceneManifest {
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

    private func openSplatSpace(splatURL: URL, summary: SpatialReviewSceneSummary) async {
        if immersiveSpaceIsOpen {
            await dismissImmersiveSpace()
            immersiveSpaceIsOpen = false
        }
        MetalSplatterVisionSceneSessionStore.shared.setControls(splatControls, for: splatSessionID)
        MetalSplatterVisionSceneSessionStore.shared.setStatus(
            MetalSplatterImmersiveSceneStatus(kind: .loading, message: "Opening \(splatURL.lastPathComponent)."),
            for: splatSessionID
        )
        switch await openImmersiveSpace(value: MetalSplatterImmersiveScene(
            sessionID: splatSessionID,
            splatURL: splatURL,
            modelTransform: summary.splatModelTransform,
            spatialOverlay: model.immersiveOverlayPayload()
        )) {
        case .opened:
            immersiveSpaceIsOpen = true
        case .error:
            model.recordDiagnostic("Unable to open the immersive splat space.")
            MetalSplatterVisionSceneSessionStore.shared.setStatus(
                MetalSplatterImmersiveSceneStatus(kind: .failed, message: "Unable to open the immersive splat space."),
                for: splatSessionID
            )
        case .userCancelled:
            MetalSplatterVisionSceneSessionStore.shared.setStatus(
                MetalSplatterImmersiveSceneStatus(kind: .idle, message: "Splat space opening was cancelled."),
                for: splatSessionID
            )
        @unknown default:
            model.recordDiagnostic("The immersive splat space returned an unknown open result.")
        }
    }

    private func floatBinding(_ keyPath: WritableKeyPath<MetalSplatterImmersiveSceneControls, Float>) -> Binding<Float> {
        Binding(
            get: { splatControls[keyPath: keyPath] },
            set: { splatControls[keyPath: keyPath] = $0 }
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

private struct SliderRow: View {
    var title: String
    @Binding var value: Float
    var range: ClosedRange<Float>
    var format: String

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: String(format: format, value))
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
        }
    }
}
