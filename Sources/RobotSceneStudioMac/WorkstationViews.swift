import SwiftUI
import UniformTypeIdentifiers
import RobotVisionLabCore

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
    @State private var selectedSection: WorkstationSection? = .project
    @State private var isImportingCapture = false
    @State private var isImportingSplat = false
    @State private var isOpeningRobotScene = false

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
                section: selectedSection ?? .project,
                isImportingCapture: $isImportingCapture,
                isImportingSplat: $isImportingSplat,
                isOpeningRobotScene: $isOpeningRobotScene
            )
            .navigationTitle(selectedSection?.title ?? "Workstation")
        } detail: {
            WorkstationDetailPanel(model: model, section: selectedSection ?? .project)
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
        .fileImporter(
            isPresented: $isOpeningRobotScene,
            allowedContentTypes: [.robotScenePackage, .json],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                model.openRobotScene(at: url)
            }
        }
    }
}

public struct WorkstationControlPanel: View {
    @Bindable var model: WorkstationModel
    var section: WorkstationSection
    @Binding var isImportingCapture: Bool
    @Binding var isImportingSplat: Bool
    @Binding var isOpeningRobotScene: Bool
    @State private var metalTileSize = 16
    @State private var metalMaxSplats = ""
    @State private var metalStreamingChunkSplats = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatusStrip(state: model.state)
            switch section {
            case .project:
                ProjectControlPanel(model: model, isOpeningRobotScene: $isOpeningRobotScene)
            case .receiver:
                ReceiverControlPanel(model: model)
            case .capture:
                CaptureControlPanel(model: model, isImportingCapture: $isImportingCapture)
            case .splat:
                SplatControlPanel(model: model, isImportingSplat: $isImportingSplat)
            case .routes:
                RouteControlPanel(model: model)
            case .failureMap:
                FailureMapControlPanel(model: model)
            case .appleSilicon:
                AppleSiliconControlPanel(
                    model: model,
                    metalTileSize: $metalTileSize,
                    metalMaxSplats: $metalMaxSplats,
                    metalStreamingChunkSplats: $metalStreamingChunkSplats
                )
            case .export:
                ExportControlPanel(model: model)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
    }

    private func optionalPositiveInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else {
            return nil
        }
        return value
    }
}

private struct ProjectControlPanel: View {
    @Bindable var model: WorkstationModel
    @Binding var isOpeningRobotScene: Bool

    var body: some View {
        GroupBox("Project Browser") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    isOpeningRobotScene = true
                } label: {
                    Label("Open .robotscene", systemImage: "folder")
                }
                Button {
                    NSWorkspace.shared.open(model.state.workspaceURL)
                } label: {
                    Label("Open Workspace", systemImage: "macwindow")
                }
                ProjectPathRow(title: "Scene", url: model.state.activeRobotSceneURL)
                ProjectPathRow(title: "Capture", url: model.state.activeCaptureURL)
                ProjectPathRow(title: "Splat", url: model.state.activeSplatURL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReceiverControlPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        GroupBox("iPhone Receiver") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.isMultipeerReceiverRunning ? model.stopMultipeerReceiver() : model.startMultipeerReceiver()
                } label: {
                    Label(
                        model.isMultipeerReceiverRunning ? "Stop Receiver" : "Start Receiver",
                        systemImage: model.isMultipeerReceiverRunning ? "stop.circle" : "dot.radiowaves.left.and.right"
                    )
                }
                ProjectPathRow(title: "Inbox", url: model.state.workspaceURL.appendingPathComponent("Inbox", isDirectory: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CaptureControlPanel: View {
    @Bindable var model: WorkstationModel
    @Binding var isImportingCapture: Bool

    var body: some View {
        GroupBox("Capture Import") {
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
    }
}

private struct SplatControlPanel: View {
    @Bindable var model: WorkstationModel
    @Binding var isImportingSplat: Bool

    var body: some View {
        GroupBox("Splat Linking") {
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
    }
}

private struct RouteControlPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        GroupBox("Route Tools") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.addRouteAlignmentAnchor()
                } label: {
                    Label("Add Anchor", systemImage: "mappin.and.ellipse")
                }
                Button {
                    model.alignRoute(method: model.routeAlignmentAnchors.isEmpty ? .routeBoundsToSceneBounds : .controlPointCentroids)
                } label: {
                    Label("Align Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
                .disabled(model.state.activeCaptureURL == nil)
                TextField("Lateral offsets", text: $model.routeExpansionLateralOffsets)
                    .textFieldStyle(.roundedBorder)
                TextField("Height offsets", text: $model.routeExpansionHeightOffsets)
                    .textFieldStyle(.roundedBorder)
                TextField("Yaw offsets", text: $model.routeExpansionYawOffsets)
                    .textFieldStyle(.roundedBorder)
                Button {
                    model.generateRouteVariants()
                } label: {
                    Label("Generate Variants", systemImage: "arrow.triangle.branch")
                }
                .disabled(model.state.activeCaptureURL == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FailureMapControlPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        GroupBox("Failure Map") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.evaluateBaselineModel()
                    model.exportRobotScene()
                } label: {
                    Label("Refresh Failure Map", systemImage: "map")
                }
                .disabled(model.state.frameCount == 0)
                Text("\(model.failureMarkers.count) markers loaded")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AppleSiliconControlPanel: View {
    @Bindable var model: WorkstationModel
    @Binding var metalTileSize: Int
    @Binding var metalMaxSplats: String
    @Binding var metalStreamingChunkSplats: String

    var body: some View {
        GroupBox("Apple Silicon") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.planMetalRender()
                } label: {
                    Label("Plan Metal Render", systemImage: "cpu")
                }
                .disabled(model.state.frameCount == 0)

                Stepper(value: $metalTileSize, in: 4...64, step: 4) {
                    Label("Tile \(metalTileSize)", systemImage: "square.grid.3x3")
                }

                TextField("Max splats", text: $metalMaxSplats)
                    .textFieldStyle(.roundedBorder)

                TextField("Streaming chunk", text: $metalStreamingChunkSplats)
                    .textFieldStyle(.roundedBorder)

                Button {
                    model.renderMetalSplats(
                        tileSize: metalTileSize,
                        maxSplatsPerFrame: optionalPositiveInt(metalMaxSplats),
                        streamingChunkSplatCount: optionalPositiveInt(metalStreamingChunkSplats)
                    )
                } label: {
                    Label("Render Metal Splats", systemImage: "rectangle.stack.badge.play")
                }
                .disabled(model.state.frameCount == 0 || model.state.activeSplatURL == nil)

                Button {
                    model.planTraining()
                } label: {
                    Label("Plan MLX Training", systemImage: "brain")
                }
                .disabled(model.state.frameCount == 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionalPositiveInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else {
            return nil
        }
        return value
    }
}

private struct ExportControlPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        GroupBox("Export") {
            Button {
                model.exportRobotScene()
            } label: {
                Label("Export .robotscene", systemImage: "visionpro")
            }
            .disabled(model.state.frameCount == 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public struct WorkstationDetailPanel: View {
    @Bindable var model: WorkstationModel
    var section: WorkstationSection
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

            switch section {
            case .project:
                ArtifactList(model: model, openURL: openURL)
            case .receiver:
                TransferEventList(model: model)
            case .capture:
                ImportHealthPanel(model: model)
            case .splat:
                SplatInspectorPanel(model: model)
            case .routes:
                RouteAlignmentPanel(model: model)
            case .failureMap:
                FailureMapViewer(model: model)
            case .appleSilicon, .export:
                ArtifactList(model: model, openURL: openURL)
                DiagnosticsPanel(model: model)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 460, minHeight: 520)
    }
}

private struct ImportHealthPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        if let report = model.importHealthReport {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import Health")
                    .font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        MetricCell(title: "Video", value: report.hasVideo ? "Present" : "Missing")
                        MetricCell(title: "LiDAR", value: "\(report.lidarFrameCount)")
                        MetricCell(title: "RoomPlan", value: report.hasRoomPlanModel ? "Present" : "None")
                    }
                    GridRow {
                        MetricCell(title: "Objects", value: "\(report.objectCaptureAssetCount)")
                        MetricCell(title: "Transfer", value: report.primaryTransferMethod.rawValue)
                        MetricCell(title: "Warnings", value: "\(report.warnings.count)")
                    }
                }
                DiagnosticsList(messages: report.warnings)
            }
        } else {
            EmptyState(title: "No capture imported", systemImage: "square.and.arrow.down")
        }
    }
}

private struct SplatInspectorPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        if let asset = model.splatAsset {
            VStack(alignment: .leading, spacing: 12) {
                Text("Linked Splat")
                    .font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        MetricCell(title: "Format", value: asset.format.rawValue.uppercased())
                        MetricCell(title: "Splats", value: "\(asset.vertexCount)")
                        MetricCell(title: "Properties", value: "\(asset.properties.count)")
                    }
                }
                Text(asset.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        } else {
            EmptyState(title: "No splat linked", systemImage: "cube.transparent")
        }
    }
}

private struct RouteAlignmentPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Anchors")
                .font(.headline)
            if model.routeAlignmentAnchors.isEmpty {
                EmptyState(title: "No anchors", systemImage: "mappin.slash")
            } else {
                List {
                    ForEach($model.routeAlignmentAnchors) { $anchor in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Anchor")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button {
                                    model.removeRouteAlignmentAnchor(id: anchor.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack {
                                NumberField(title: "AR X", value: $anchor.arkitX)
                                NumberField(title: "AR Y", value: $anchor.arkitY)
                                NumberField(title: "AR Z", value: $anchor.arkitZ)
                            }
                            HStack {
                                NumberField(title: "Scene X", value: $anchor.sceneX)
                                NumberField(title: "Scene Y", value: $anchor.sceneY)
                                NumberField(title: "Scene Z", value: $anchor.sceneZ)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(minHeight: 180)
            }
            if let report = model.routeAlignmentReport {
                Text("Aligned \(report.alignedKeyframeCount) keyframes with \(report.method.rawValue).")
                    .foregroundStyle(.secondary)
            }
            if let report = model.routeExpansionReport {
                Text("Generated \(report.variantCount) variants and \(report.expandedKeyframeCount) keyframes.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FailureMapViewer: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Failure Map")
                .font(.headline)
            if model.failureMarkers.isEmpty {
                EmptyState(title: "No failure map loaded", systemImage: "map")
            } else {
                List {
                    ForEach(model.failureMarkers, id: \.id) { marker in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: marker.kind.symbol)
                                .foregroundStyle(marker.kind.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(marker.kind.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(marker.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Frame \(marker.frameIndex.map(String.init) ?? "-") · \(String(format: "%.2f", marker.confidence))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }
}

private struct ArtifactList: View {
    @Bindable var model: WorkstationModel
    var openURL: OpenURLAction

    var body: some View {
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
    }
}

private struct TransferEventList: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receiver Events")
                .font(.headline)
            if model.transferEvents.isEmpty {
                EmptyState(title: "Receiver idle", systemImage: "dot.radiowaves.left.and.right")
            } else {
                List(model.transferEvents) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }
}

private struct DiagnosticsPanel: View {
    @Bindable var model: WorkstationModel

    var body: some View {
        if !model.state.diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics")
                    .font(.headline)
                DiagnosticsList(messages: model.state.diagnostics)
            }
        }
    }
}

private struct DiagnosticsList: View {
    var messages: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, diagnostic in
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

private struct NumberField: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        TextField(title, value: $value, format: .number.precision(.fractionLength(3)))
            .textFieldStyle(.roundedBorder)
    }
}

private struct ProjectPathRow: View {
    var title: String
    var url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(url?.lastPathComponent ?? "Not set")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct EmptyState: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
            GridRow {
                MetricCell(title: "Failures", value: "\(state.failureMarkerCount)")
                MetricCell(title: "Scene", value: state.activeRobotSceneID == nil ? "None" : "Open")
                MetricCell(title: "Stage", value: state.stage.title)
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
    case project
    case receiver
    case capture
    case splat
    case routes
    case failureMap
    case appleSilicon
    case export

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .project: "Project"
        case .receiver: "Receiver"
        case .capture: "Capture Health"
        case .splat: "Splat"
        case .routes: "Routes"
        case .failureMap: "Failure Map"
        case .appleSilicon: "Apple Silicon"
        case .export: "Export"
        }
    }

    var symbol: String {
        switch self {
        case .project: "folder"
        case .receiver: "dot.radiowaves.left.and.right"
        case .capture: "waveform.and.magnifyingglass"
        case .splat: "cube.transparent"
        case .routes: "point.3.connected.trianglepath.dotted"
        case .failureMap: "map"
        case .appleSilicon: "cpu"
        case .export: "visionpro"
        }
    }
}

private extension FailureMarkerKind {
    var title: String {
        switch self {
        case .confident: "Confident"
        case .uncertainLocalization: "Uncertain Localization"
        case .blockedPrediction: "Blocked"
        case .missingTrainingViews: "Missing Views"
        case .visualAmbiguity: "Ambiguity"
        case .badLighting: "Lighting"
        case .lowTexture: "Low Texture"
        }
    }

    var symbol: String {
        switch self {
        case .confident: "checkmark.circle"
        case .uncertainLocalization: "location.slash"
        case .blockedPrediction: "xmark.octagon"
        case .missingTrainingViews: "camera.badge.ellipsis"
        case .visualAmbiguity: "eye.trianglebadge.exclamationmark"
        case .badLighting: "lightbulb.slash"
        case .lowTexture: "square.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .confident: .green
        case .uncertainLocalization: .yellow
        case .blockedPrediction: .red
        case .missingTrainingViews: .blue
        case .visualAmbiguity: .purple
        case .badLighting: .orange
        case .lowTexture: .gray
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
        case .renderingMetalSplats: "Rendering Metal Splats"
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
