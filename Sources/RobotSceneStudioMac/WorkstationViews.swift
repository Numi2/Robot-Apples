import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    static var robotCapturePackage: UTType {
        UTType(filenameExtension: "robotcapture") ?? .package
    }

    static var robotScenePackage: UTType {
        UTType(filenameExtension: "robotscene") ?? .package
    }

    static var gaussianSplatPLY: UTType {
        UTType(filenameExtension: "ply") ?? .data
    }

    static var gaussianSplatAsset: UTType {
        UTType(filenameExtension: "splat") ?? .data
    }
}

public struct WorkstationRootView: View {
    @Bindable private var model: WorkstationModel
    @State private var selectedSection: WorkstationSection? = .ingest
    @State private var isImportingCapture = false
    @State private var isImportingSplat = false

    public init(model: WorkstationModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(WorkstationSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("Robot Scene Studio")
        } content: {
            WorkstationControlPanel(
                model: model,
                isImportingCapture: $isImportingCapture,
                isImportingSplat: $isImportingSplat
            )
            .navigationTitle(selectedSection?.title ?? "Workstation")
        } detail: {
            WorkstationDetailPanel(model: model)
        }
        .fileImporter(
            isPresented: $isImportingCapture,
            allowedContentTypes: [.robotCapturePackage, .json],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                model.importCapture(at: url)
            }
        }
        .fileImporter(
            isPresented: $isImportingSplat,
            allowedContentTypes: [.gaussianSplatPLY, .gaussianSplatAsset],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                model.linkSplat(at: url)
            }
        }
    }
}

public struct WorkstationControlPanel: View {
    @Bindable var model: WorkstationModel
    @Binding var isImportingCapture: Bool
    @Binding var isImportingSplat: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatusStrip(state: model.state)

            GroupBox("Ingest") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isImportingCapture = true
                    } label: {
                        Label("Import .robotcapture", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        model.prepareCapture()
                    } label: {
                        Label("Prepare Capture", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .disabled(model.state.activeCaptureURL == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Scene") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        isImportingSplat = true
                    } label: {
                        Label("Link Gaussian Splat", systemImage: "cube.transparent")
                    }

                    Button {
                        model.buildDatasetManifest()
                    } label: {
                        Label("Build Dataset Manifest", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(model.state.frameCount == 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Apple Silicon") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        model.planMetalRender()
                    } label: {
                        Label("Plan Metal Render", systemImage: "cpu")
                    }
                    .disabled(model.state.frameCount == 0)

                    Button {
                        model.planTraining()
                    } label: {
                        Label("Plan MLX Training", systemImage: "brain")
                    }
                    .disabled(model.state.frameCount == 0)

                    Button {
                        model.evaluateBaselineModel()
                    } label: {
                        Label("Evaluate Model", systemImage: "waveform.path.ecg")
                    }
                    .disabled(model.state.frameCount == 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Export") {
                Button {
                    model.exportRobotScene()
                } label: {
                    Label("Export .robotscene", systemImage: "visionpro")
                }
                .disabled(model.state.frameCount == 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
    }
}

public struct WorkstationDetailPanel: View {
    @Bindable var model: WorkstationModel
    @Environment(\.openURL) private var openURL

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace")
                    .font(.headline)
                Text(model.state.workspaceURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            MetricsGrid(state: model.state)

            if !model.state.artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Artifacts")
                        .font(.headline)
                    List(model.state.artifacts) { artifact in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(artifact.title)
                                Text(artifact.url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                openURL(artifact.url)
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(minHeight: 180)
                }
            }

            if !model.state.diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diagnostics")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(model.state.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                Label(diagnostic, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 460, minHeight: 520)
    }
}

private struct StatusStrip: View {
    var state: WorkstationState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mac Workstation")
                .font(.title2.weight(.semibold))
            HStack {
                Label(state.stage.title, systemImage: state.stage.symbol)
                Spacer()
                Text(state.activeCaptureURL?.lastPathComponent ?? "No capture")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}

private struct MetricsGrid: View {
    var state: WorkstationState

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                MetricCell(title: "Frames", value: "\(state.frameCount)")
                MetricCell(title: "Motion", value: "\(state.motionSampleCount)")
                MetricCell(title: "Warnings", value: "\(state.warningCount)")
            }
        }
    }
}

private struct MetricCell: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

public enum WorkstationSection: String, CaseIterable, Identifiable {
    case ingest
    case scene
    case appleSilicon
    case export

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .ingest: "Ingest"
        case .scene: "Scene"
        case .appleSilicon: "Apple Silicon"
        case .export: "Export"
        }
    }

    var symbol: String {
        switch self {
        case .ingest: "square.and.arrow.down"
        case .scene: "cube.transparent"
        case .appleSilicon: "cpu"
        case .export: "visionpro"
        }
    }
}

private extension WorkstationStage {
    var title: String {
        switch self {
        case .idle: "Idle"
        case .importingCapture: "Importing Capture"
        case .preparingCapture: "Preparing Capture"
        case .linkingSplat: "Linking Splat"
        case .buildingDataset: "Building Dataset"
        case .planningMetalRender: "Planning Metal Render"
        case .planningTraining: "Planning Training"
        case .evaluatingModel: "Evaluating Model"
        case .exportingRobotScene: "Exporting Robot Scene"
        case .complete: "Complete"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .failed: "xmark.octagon"
        case .complete: "checkmark.circle"
        case .idle: "circle"
        default: "gearshape.2"
        }
    }
}
