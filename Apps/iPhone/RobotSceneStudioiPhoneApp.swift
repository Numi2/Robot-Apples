import RobotSceneStudioiPhone
import RobotSceneStudioSplatViewer
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
@preconcurrency import _RealityKit_SwiftUI

@main
struct RobotSceneStudioiPhoneApp: App {
    @State private var model = CaptureClientModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            CaptureClientRootView(model: model)
        }
    }
}

struct CaptureClientRootView: View {
    @Bindable var model: CaptureClientModel
    @State private var exploratorySplatURL: URL?
    @State private var isImportingSplat = false

    var body: some View {
        TabView {
            CaptureScreen(model: model)
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
                }
            ObjectCaptureScreen(model: model)
                .tabItem {
                    Label("Objects", systemImage: "cube.viewfinder")
                }
            PackageBrowserScreen(model: model)
                .tabItem {
                    Label("Packages", systemImage: "shippingbox")
                }
            TransferScreen(model: model)
                .tabItem {
                    Label("Transfer", systemImage: "dot.radiowaves.left.and.right")
                }
            FinderFallbackScreen(model: model)
                .tabItem {
                    Label("Finder", systemImage: "cable.connector")
                }
            SplatExplorerScreen(splatURL: $exploratorySplatURL, isImportingSplat: $isImportingSplat)
                .tabItem {
                    Label("Splats", systemImage: "camera.metering.matrix")
                }
        }
        .fileImporter(
            isPresented: $isImportingSplat,
            allowedContentTypes: [.gaussianSplatPLY, .gaussianSplatAsset, .gaussianSplatSPZ],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                exploratorySplatURL = url
            } catch {
                model.recordFileImportError("Unable to import Gaussian splat", error: error)
            }
        }
    }
}

private struct ObjectCaptureScreen: View {
    @Bindable var model: CaptureClientModel
    @State private var session = ObjectCaptureSession()
    @State private var objectLabel = "object"
    @State private var draft: ObjectCaptureDraft?
    @State private var captureStateTitle = "Ready"
    @State private var feedbackTitle = "No feedback"
    @State private var trackingTitle = "Unknown"
    @State private var canCaptureImage = false
    @State private var shotsTaken = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if ObjectCaptureSession.isSupported {
                        ObjectCaptureView(session: session)
                            .frame(height: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .listRowInsets(EdgeInsets())
                    } else {
                        ContentUnavailableView("Object Capture unavailable", systemImage: "cube.viewfinder")
                    }
                }

                Section("Object") {
                    TextField("Label", text: $objectLabel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Package", value: model.state.selectedPackageURL?.lastPathComponent ?? "None")
                    LabeledContent("State", value: captureStateTitle)
                    LabeledContent("Tracking", value: trackingTitle)
                    LabeledContent("Shots", value: "\(shotsTaken)")
                    Text(feedbackTitle)
                        .foregroundStyle(.secondary)
                }

                Section("Capture") {
                    if session.state.isInitialOrCompleted {
                        Button {
                            startObjectCapture()
                        } label: {
                            Label("Start Object Capture", systemImage: "cube.viewfinder")
                        }
                        .disabled(!ObjectCaptureSession.isSupported)
                    }
                    if session.state.isReady {
                        Button {
                            _ = session.startDetecting()
                        } label: {
                            Label("Detect Object", systemImage: "viewfinder")
                        }
                    }
                    if session.state.isDetecting {
                        Button {
                            session.startCapturing()
                        } label: {
                            Label("Begin Scan Pass", systemImage: "camera.aperture")
                        }
                    }
                    if session.state.isCapturing {
                        Button {
                            session.requestImageCapture()
                        } label: {
                            Label("Capture Shot", systemImage: "camera")
                        }
                        .disabled(!canCaptureImage)

                        HStack {
                            Button {
                                session.beginNewScanPass()
                            } label: {
                                Label("New Pass", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Button {
                                session.beginNewScanPassAfterFlip()
                            } label: {
                                Label("Flip Pass", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            }
                        }

                        Button(role: .destructive) {
                            session.finish()
                        } label: {
                            Label("Finish Object", systemImage: "checkmark.circle")
                        }
                    }
                    if session.state.isCompleted {
                        Button {
                            attachObjectCapture()
                        } label: {
                            Label("Attach to Package", systemImage: "shippingbox.and.arrow.backward")
                        }
                        .disabled(model.state.selectedPackageURL == nil)
                    }
                    if session.state.isActive {
                        Button(role: .destructive) {
                            session.cancel()
                            resetSession()
                        } label: {
                            Label("Cancel Object", systemImage: "xmark.circle")
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Object Capture")
            .task(id: session.id) {
                await observeSessionState()
            }
            .task(id: session.id) {
                await observeSessionFeedback()
            }
            .task(id: session.id) {
                await observeSessionTracking()
            }
            .task(id: session.id) {
                await observeCaptureAvailability()
            }
            .task(id: session.id) {
                await observeShotCount()
            }
        }
    }

    private func startObjectCapture() {
        do {
            let nextDraft = try ObjectCaptureDraft.make(label: objectLabel, documentsURL: model.documentsURL)
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = nextDraft.checkpointDirectoryURL
            configuration.isOverCaptureEnabled = true
            session = ObjectCaptureSession()
            draft = nextDraft
            errorMessage = nil
            shotsTaken = 0
            canCaptureImage = false
            captureStateTitle = "Initializing"
            session.start(imagesDirectory: nextDraft.imagesDirectoryURL, configuration: configuration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachObjectCapture() {
        guard let draft else { return }
        do {
            _ = try model.attachObjectCaptureImageSet(
                label: draft.label,
                imagesDirectoryURL: draft.imagesDirectoryURL,
                checkpointDirectoryURL: draft.checkpointDirectoryURL,
                createdAt: draft.createdAt
            )
            errorMessage = nil
            resetSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetSession() {
        session = ObjectCaptureSession()
        draft = nil
        captureStateTitle = "Ready"
        feedbackTitle = "No feedback"
        trackingTitle = "Unknown"
        canCaptureImage = false
        shotsTaken = 0
    }

    private func observeSessionState() async {
        captureStateTitle = session.state.title
        for await state in session.stateUpdates {
            captureStateTitle = state.title
            if case .failed(let error) = state {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func observeSessionFeedback() async {
        feedbackTitle = session.feedback.feedbackTitle
        for await feedback in session.feedbackUpdates {
            feedbackTitle = feedback.feedbackTitle
        }
    }

    private func observeSessionTracking() async {
        trackingTitle = session.cameraTracking.title
        for await tracking in session.cameraTrackingUpdates {
            trackingTitle = tracking.title
        }
    }

    private func observeCaptureAvailability() async {
        canCaptureImage = session.canRequestImageCapture
        for await canRequest in session.canRequestImageCaptureUpdates {
            canCaptureImage = canRequest
        }
    }

    private func observeShotCount() async {
        shotsTaken = session.numberOfShotsTaken
        for await count in session.numberOfShotsTakenUpdates {
            shotsTaken = count
        }
    }
}

private struct ObjectCaptureDraft: Equatable {
    var label: String
    var imagesDirectoryURL: URL
    var checkpointDirectoryURL: URL
    var createdAt: Date

    static func make(label: String, documentsURL: URL) throws -> ObjectCaptureDraft {
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeLabel = safeFileComponent(cleanedLabel.isEmpty ? "object" : cleanedLabel)
        let createdAt = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: createdAt).replacingOccurrences(of: ":", with: "-")
        let rootURL = documentsURL
            .appendingPathComponent("ObjectCaptureDrafts", isDirectory: true)
            .appendingPathComponent("\(timestamp)-\(safeLabel)", isDirectory: true)
        let imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        let checkpointURL = rootURL.appendingPathComponent("checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpointURL, withIntermediateDirectories: true)
        return ObjectCaptureDraft(
            label: cleanedLabel.isEmpty ? safeLabel : cleanedLabel,
            imagesDirectoryURL: imagesURL,
            checkpointDirectoryURL: checkpointURL,
            createdAt: createdAt
        )
    }

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let characters = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(characters).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "object" : sanitized
    }
}

extension UTType {
    static var gaussianSplatPLY: UTType {
        UTType(filenameExtension: "ply") ?? .data
    }

    static var gaussianSplatAsset: UTType {
        UTType(filenameExtension: "splat") ?? .data
    }

    static var gaussianSplatSPZ: UTType {
        UTType(filenameExtension: "spz") ?? .data
    }
}

private struct SplatExplorerScreen: View {
    @Binding var splatURL: URL?
    @Binding var isImportingSplat: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let splatURL {
                    MetalSplatterKitSceneView(splatURL: splatURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("No splat selected", systemImage: "camera.metering.matrix")
                }
            }
            .navigationTitle("Splat Explorer")
            .toolbar {
                Button {
                    isImportingSplat = true
                } label: {
                    Image(systemName: "folder")
                }
            }
        }
    }
}

private struct CaptureScreen: View {
    @Bindable var model: CaptureClientModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusHeader(model: model)
                }

                if let previewCaptureSession = model.previewCaptureSession {
                    Section {
                        CameraPreviewView(session: previewCaptureSession)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .listRowInsets(EdgeInsets())
                }

                Section("Permissions") {
                    PermissionRow(title: "Camera", status: model.permissions.camera, systemImage: "camera")
                    PermissionRow(title: "ARKit", status: model.permissions.arkit, systemImage: "arkit")
                    PermissionRow(title: "Motion", status: model.permissions.motion, systemImage: "gyroscope")
                    Button {
                        model.requestPermissions()
                    } label: {
                        Label("Request Permissions", systemImage: "checkmark.shield")
                    }
                }

                Section("Quality") {
                    QualityRow(title: "Tracking", level: model.quality.tracking, systemImage: "location.viewfinder")
                    QualityRow(title: "Lighting", level: model.quality.lighting, systemImage: "sun.max")
                    QualityRow(title: "Motion", level: model.quality.motion, systemImage: "waveform.path")
                    Text(model.quality.message)
                        .foregroundStyle(.secondary)
                }

                Section("Capture") {
                    Toggle("AVFoundation video.mov", isOn: $model.configuration.recordsVideo)
                    Toggle("ARKit pose/intrinsics stream", isOn: $model.configuration.recordsARKitPose)
                    Toggle("Core Motion stream", isOn: $model.configuration.recordsCoreMotion)
                    Toggle("LiDAR depth when available", isOn: $model.configuration.recordsLiDAR)
                    Toggle("RoomPlan when useful", isOn: $model.configuration.recordsRoomPlan)
                    Stepper(value: $model.configuration.targetFPS, in: 15...60, step: 15) {
                        LabeledContent("Target FPS", value: "\(model.configuration.targetFPS)")
                    }
                }

                Section {
                    if model.state.stage == .recording {
                        Button(role: .destructive) {
                            model.finishRecording()
                        } label: {
                            Label("Finish Package", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            model.beginRecording()
                        } label: {
                            Label("Start Capture", systemImage: "record.circle")
                        }
                        .disabled(model.permissions.camera == .denied || model.permissions.camera == .unavailable)
                    }
                }
            }
            .navigationTitle("Robot Capture")
            .toolbar {
                Button {
                    model.refreshPermissionStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewSurface, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

private struct PackageBrowserScreen: View {
    @Bindable var model: CaptureClientModel

    var body: some View {
        NavigationStack {
            List {
                Section("Finder-visible Documents") {
                    Text(model.documentsURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                Section("Packages") {
                    if model.packages.isEmpty {
                        ContentUnavailableView("No capture packages", systemImage: "shippingbox")
                    } else {
                        ForEach(model.packages) { package in
                            Button {
                                model.selectPackage(package.url)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(package.url.lastPathComponent)
                                            .font(.headline)
                                        Text(package.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(byteCount(package.sizeBytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if model.state.selectedPackageURL == package.url {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Packages")
            .toolbar {
                Button {
                    model.refreshPackageBrowser()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct TransferScreen: View {
    @Bindable var model: CaptureClientModel

    var body: some View {
        NavigationStack {
            List {
                Section("Selected Package") {
                    LabeledContent("Package", value: model.state.selectedPackageURL?.lastPathComponent ?? "None")
                    ProgressView(value: model.state.transferProgress)
                    Text(model.state.latestMessage)
                        .foregroundStyle(.secondary)
                }

                Section("Nearby Mac") {
                    Button {
                        model.isBrowsingForMac ? model.stopMacDiscovery() : model.startMacDiscovery()
                    } label: {
                        Label(
                            model.isBrowsingForMac ? "Stop Discovery" : "Find Mac Workstation",
                            systemImage: model.isBrowsingForMac ? "stop.circle" : "dot.radiowaves.left.and.right"
                        )
                    }

                    if !model.discoveredMacs.isEmpty {
                        ForEach(model.discoveredMacs, id: \.self) { mac in
                            Label(mac, systemImage: "macbook.and.iphone")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if model.connectedMacs.isEmpty {
                        Text("No connected Mac receiver.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.connectedMacs, id: \.self) { mac in
                            Button {
                                model.sendSelectedPackage(to: mac)
                            } label: {
                                Label(mac, systemImage: "macbook")
                            }
                        }
                    }

                    Button {
                        model.sendSelectedPackage()
                    } label: {
                        Label("Send to Connected Mac", systemImage: "paperplane")
                    }
                    .disabled(model.state.selectedPackageURL == nil)

                    HStack {
                        Button {
                            model.cancelTransfer()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .disabled(model.state.stage != .transferring)

                        Button {
                            model.retryLastTransfer()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Events") {
                    if model.transferEvents.isEmpty {
                        ContentUnavailableView("No transfer events", systemImage: "clock")
                    } else {
                        ForEach(model.transferEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                Text(event.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transfer")
        }
    }
}

private struct FinderFallbackScreen: View {
    @Bindable var model: CaptureClientModel

    var body: some View {
        let guide = model.finderSharingSummary()
        NavigationStack {
            List {
                Section("Wired Fallback") {
                    LabeledContent("Package", value: ".\(guide.packageExtension)")
                    LabeledContent("Method", value: guide.transferMethod.rawValue)
                }

                Section("Requirements") {
                    ForEach(guide.requirements, id: \.self) { requirement in
                        Label(requirement, systemImage: "checkmark.circle")
                    }
                }

                Section("Copy to Mac") {
                    ForEach(Array(guide.copyToMacSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .background(.quaternary, in: Circle())
                            Text(step)
                        }
                    }
                }

                Section("Notes") {
                    ForEach(guide.notes, id: \.self) { note in
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Finder")
        }
    }
}

private struct StatusHeader: View {
    @Bindable var model: CaptureClientModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.state.stage.title, systemImage: model.state.stage.symbol)
                    .font(.headline)
                Spacer()
                Text("\(model.state.deviceCaptureState.rgbFrameCount) frames")
                    .foregroundStyle(.secondary)
            }
            Text(model.state.packageURL?.lastPathComponent ?? "No active package")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
    var title: String
    var status: CapturePermissionStatus
    var systemImage: String

    var body: some View {
        Label {
            LabeledContent(title, value: status.title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(status.tint)
        }
    }
}

private struct QualityRow: View {
    var title: String
    var level: CaptureQualityLevel
    var systemImage: String

    var body: some View {
        Label {
            LabeledContent(title, value: level.title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(level.tint)
        }
    }
}

private extension CaptureClientStage {
    var title: String {
        switch self {
        case .idle: "Ready"
        case .requestingPermissions: "Permissions"
        case .recording: "Recording"
        case .packaging: "Packaging"
        case .browsingMacs: "Finding Mac"
        case .transferring: "Transferring"
        case .complete: "Complete"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .requestingPermissions: "checkmark.shield"
        case .recording: "record.circle"
        case .packaging: "shippingbox"
        case .browsingMacs: "dot.radiowaves.left.and.right"
        case .transferring: "paperplane"
        case .complete: "checkmark.circle"
        case .failed: "xmark.octagon"
        }
    }
}

private extension CapturePermissionStatus {
    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .granted: "Ready"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        }
    }

    var tint: Color {
        switch self {
        case .granted: .green
        case .denied, .unavailable: .red
        case .unknown: .secondary
        }
    }
}

private extension CaptureQualityLevel {
    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .good: "Good"
        case .warning: "Check"
        case .bad: "Bad"
        }
    }

    var tint: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .bad: .red
        case .unknown: .secondary
        }
    }
}

private extension ObjectCaptureSession.CaptureState {
    var title: String {
        switch self {
        case .initializing: "Initializing"
        case .ready: "Ready"
        case .detecting: "Detecting"
        case .capturing: "Capturing"
        case .finishing: "Finishing"
        case .completed: "Completed"
        case .failed: "Failed"
        @unknown default: "Unknown"
        }
    }

    var isInitialOrCompleted: Bool {
        switch self {
        case .initializing, .completed, .failed:
            return true
        case .ready, .detecting, .capturing, .finishing:
            return false
        @unknown default:
            return false
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDetecting: Bool {
        if case .detecting = self { return true }
        return false
    }

    var isCapturing: Bool {
        if case .capturing = self { return true }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .ready, .detecting, .capturing, .finishing:
            return true
        case .initializing, .completed, .failed:
            return false
        @unknown default:
            return false
        }
    }
}

private extension Set where Element == ObjectCaptureSession.Feedback {
    var feedbackTitle: String {
        guard !isEmpty else { return "No feedback" }
        return map(\.title).sorted().joined(separator: ", ")
    }
}

private extension ObjectCaptureSession.Feedback {
    var title: String {
        switch self {
        case .objectTooClose: "Object too close"
        case .objectTooFar: "Object too far"
        case .movingTooFast: "Moving too fast"
        case .environmentLowLight: "Low light"
        case .environmentTooDark: "Too dark"
        case .outOfFieldOfView: "Out of view"
        case .objectNotFlippable: "Not flippable"
        case .overCapturing: "Over capture"
        case .objectNotDetected: "Object not detected"
        @unknown default: "Unknown feedback"
        }
    }
}

private extension ObjectCaptureSession.Tracking {
    var title: String {
        switch self {
        case .notAvailable: "Unavailable"
        case .normal: "Normal"
        case .limited(let reason): "Limited: \(reason.title)"
        @unknown default: "Unknown"
        }
    }
}

private extension ObjectCaptureSession.Tracking.Reason {
    var title: String {
        switch self {
        case .initializing: "initializing"
        case .relocalizing: "relocalizing"
        case .excessiveMotion: "excessive motion"
        case .insufficientFeatures: "insufficient features"
        @unknown default: "unknown"
        }
    }
}
