import RobotSceneStudioiPhone
import SwiftUI

@main
struct RobotSceneStudioiPhoneApp: App {
    @State private var model = CaptureClientModel()

    var body: some Scene {
        WindowGroup {
            CaptureClientRootView(model: model)
        }
    }
}

struct CaptureClientRootView: View {
    @Bindable var model: CaptureClientModel

    var body: some View {
        TabView {
            CaptureScreen(model: model)
                .tabItem {
                    Label("Capture", systemImage: "camera.viewfinder")
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
