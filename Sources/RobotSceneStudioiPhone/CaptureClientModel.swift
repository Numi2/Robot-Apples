import Foundation
import Observation
import RobotVisionLabCore

#if os(iOS)
import ARKit
import AVFoundation
import CoreMotion
import UIKit
#endif

public enum CaptureClientStage: String, Codable, Sendable {
    case idle
    case requestingPermissions
    case recording
    case packaging
    case browsingMacs
    case transferring
    case complete
    case failed
}

public enum CapturePermissionStatus: String, Codable, Sendable {
    case unknown
    case granted
    case denied
    case unavailable
}

public struct CapturePermissionState: Codable, Equatable, Sendable {
    public var camera: CapturePermissionStatus
    public var motion: CapturePermissionStatus
    public var arkit: CapturePermissionStatus

    public init(
        camera: CapturePermissionStatus = .unknown,
        motion: CapturePermissionStatus = .unknown,
        arkit: CapturePermissionStatus = .unknown
    ) {
        self.camera = camera
        self.motion = motion
        self.arkit = arkit
    }
}

public enum CaptureQualityLevel: String, Codable, Sendable {
    case unknown
    case good
    case warning
    case bad
}

public struct CaptureQualityState: Codable, Equatable, Sendable {
    public var tracking: CaptureQualityLevel
    public var lighting: CaptureQualityLevel
    public var motion: CaptureQualityLevel
    public var message: String

    public init(
        tracking: CaptureQualityLevel = .unknown,
        lighting: CaptureQualityLevel = .unknown,
        motion: CaptureQualityLevel = .unknown,
        message: String = "Quality indicators update while recording."
    ) {
        self.tracking = tracking
        self.lighting = lighting
        self.motion = motion
        self.message = message
    }
}

public struct CapturePackageRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var url: URL
    public var createdAt: Date
    public var sizeBytes: Int64

    public init(id: String = UUID().uuidString, url: URL, createdAt: Date, sizeBytes: Int64) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
    }
}

public struct CaptureTransferEvent: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var detail: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), title: String, detail: String) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.detail = detail
    }
}

public struct CaptureClientState: Codable, Equatable, Sendable {
    public var stage: CaptureClientStage
    public var packageURL: URL?
    public var selectedPackageURL: URL?
    public var transferProgress: Double
    public var latestMessage: String
    public var deviceCaptureState: DeviceCaptureState

    public init(
        stage: CaptureClientStage = .idle,
        packageURL: URL? = nil,
        selectedPackageURL: URL? = nil,
        transferProgress: Double = 0,
        latestMessage: String = "Ready",
        deviceCaptureState: DeviceCaptureState = DeviceCaptureState()
    ) {
        self.stage = stage
        self.packageURL = packageURL
        self.selectedPackageURL = selectedPackageURL
        self.transferProgress = transferProgress
        self.latestMessage = latestMessage
        self.deviceCaptureState = deviceCaptureState
    }
}

public struct CaptureClientConfiguration: Codable, Equatable, Sendable {
    public var serviceType: String
    public var recordsVideo: Bool
    public var recordsARKitPose: Bool
    public var recordsCoreMotion: Bool
    public var recordsLiDAR: Bool
    public var recordsRoomPlan: Bool
    public var targetFPS: Int

    public init(
        serviceType: String = "robotcapture",
        recordsVideo: Bool = true,
        recordsARKitPose: Bool = true,
        recordsCoreMotion: Bool = true,
        recordsLiDAR: Bool = true,
        recordsRoomPlan: Bool = true,
        targetFPS: Int = 30
    ) {
        self.serviceType = serviceType
        self.recordsVideo = recordsVideo
        self.recordsARKitPose = recordsARKitPose
        self.recordsCoreMotion = recordsCoreMotion
        self.recordsLiDAR = recordsLiDAR
        self.recordsRoomPlan = recordsRoomPlan
        self.targetFPS = targetFPS
    }
}

@MainActor
@Observable
public final class CaptureClientModel {
    public var configuration: CaptureClientConfiguration
    public private(set) var state: CaptureClientState
    public private(set) var permissions = CapturePermissionState()
    public private(set) var quality = CaptureQualityState()
    public private(set) var packages: [CapturePackageRecord] = []
    public private(set) var transferEvents: [CaptureTransferEvent] = []
    public private(set) var discoveredMacs: [String] = []
    public private(set) var connectedMacs: [String] = []
    public private(set) var isBrowsingForMac = false
    public private(set) var documentsURL: URL

    #if os(iOS)
    public var previewCaptureSession: AVCaptureSession? {
        (captureSession as? AppleDeviceCaptureSession)?.previewCaptureSession
    }
    #endif

    private var captureSession: DeviceCaptureSessionControlling?
    private var sender: RobotCaptureMultipeerTransfer?
    private var senderDelegate: CaptureTransferDelegate?
    private var qualityTimer: Timer?
    private var lastTransferPackageURL: URL?
    private var lastTransferPeerName: String?

    public init(
        configuration: CaptureClientConfiguration = CaptureClientConfiguration(),
        state: CaptureClientState = CaptureClientState(),
        documentsURL: URL = CaptureClientPaths.documentsURL()
    ) {
        self.configuration = configuration
        self.state = state
        self.documentsURL = documentsURL
        refreshPackageBrowser()
        refreshPermissionStatus()
    }

    public func requestPermissions() {
        state.stage = .requestingPermissions
        state.latestMessage = "Requesting camera, motion, and ARKit readiness."

        #if os(iOS)
        Task { @MainActor in
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            permissions.camera = cameraGranted ? .granted : .denied
            permissions.arkit = ARWorldTrackingConfiguration.isSupported ? .granted : .unavailable
            permissions.motion = CMMotionManager().isDeviceMotionAvailable ? .granted : .unavailable
            state.stage = cameraGranted ? .idle : .failed
            state.latestMessage = cameraGranted ? "Capture permissions ready." : "Camera access is required for robot capture."
        }
        #else
        permissions = CapturePermissionState(camera: .unavailable, motion: .unavailable, arkit: .unavailable)
        state.stage = .failed
        state.latestMessage = "iPhone capture requires iOS."
        #endif
    }

    public func refreshPermissionStatus() {
        #if os(iOS)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissions.camera = .granted
        case .denied, .restricted:
            permissions.camera = .denied
        case .notDetermined:
            permissions.camera = .unknown
        @unknown default:
            permissions.camera = .unknown
        }
        permissions.arkit = ARWorldTrackingConfiguration.isSupported ? .granted : .unavailable
        permissions.motion = CMMotionManager().isDeviceMotionAvailable ? .granted : .unavailable
        #else
        permissions = CapturePermissionState(camera: .unavailable, motion: .unavailable, arkit: .unavailable)
        #endif
    }

    public func beginRecording() {
        #if !os(iOS)
        fail(CaptureClientError.iOSRequired.localizedDescription)
        #else
        do {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            let packageURL = documentsURL.appendingPathComponent("\(timestampedCaptureName()).robotcapture", isDirectory: true)
            let plan = makeCapturePlan(id: packageURL.deletingPathExtension().lastPathComponent)

            let session = AppleDeviceCaptureSession()
            try session.start(plan: plan, outputDirectory: packageURL)
            captureSession = session

            state = CaptureClientState(
                stage: .recording,
                packageURL: packageURL,
                selectedPackageURL: packageURL,
                latestMessage: "Recording video.mov, ARKit pose stream, and Core Motion stream.",
                deviceCaptureState: captureSession?.state ?? DeviceCaptureState()
            )
            quality = CaptureQualityState(tracking: .good, lighting: .good, motion: .good, message: "Capture running.")
            startQualityTimer()
        } catch {
            fail(error.localizedDescription)
        }
        #endif
    }

    public func finishRecording() {
        do {
            state.stage = .packaging
            state.latestMessage = "Finalizing .robotcapture package."
            _ = try captureSession?.finish()
            state.deviceCaptureState = captureSession?.state ?? state.deviceCaptureState
            captureSession = nil
            stopQualityTimer()
            refreshPackageBrowser()
            if let packageURL = state.packageURL {
                selectPackage(packageURL)
            }
            state.stage = .complete
            state.latestMessage = "Capture package ready."
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func cancelRecording() {
        captureSession?.pause()
        captureSession = nil
        stopQualityTimer()
        state.stage = .idle
        state.latestMessage = "Capture stopped."
    }

    public func refreshPackageBrowser() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        packages = urls
            .filter { $0.pathExtension == "robotcapture" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .totalFileAllocatedSizeKey])
                return CapturePackageRecord(
                    url: url,
                    createdAt: values?.creationDate ?? Date(timeIntervalSince1970: 0),
                    sizeBytes: Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func selectPackage(_ url: URL) {
        state.selectedPackageURL = url
        state.packageURL = url
        state.latestMessage = "Selected \(url.lastPathComponent)."
    }

    public func recordFileImportError(_ context: String, error: Error) {
        state.latestMessage = "\(context): \(error.localizedDescription)"
    }

    @discardableResult
    public func attachObjectCaptureImageSet(
        label: String,
        imagesDirectoryURL: URL,
        checkpointDirectoryURL: URL? = nil,
        createdAt: Date = Date()
    ) throws -> ObjectCaptureImageSet {
        guard let packageURL = state.selectedPackageURL ?? state.packageURL else {
            throw CaptureClientError.noSelectedPackage
        }
        let imageCount = countSupportedStillImages(in: imagesDirectoryURL)
        guard imageCount > 0 else {
            throw CaptureClientError.emptyObjectCaptureImageSet(imagesDirectoryURL)
        }

        let captureBundleURL = packageURL.appendingPathComponent("capture_bundle.json")
        let packageManifestURL = packageURL.appendingPathComponent("robotcapture.json")
        var captureBundle = try JSONDecoder.robotVisionLabDecoder.decode(
            CaptureBundleManifest.self,
            from: Data(contentsOf: captureBundleURL)
        )
        var packageManifest = try JSONDecoder.robotVisionLabDecoder.decode(
            RobotCapturePackageManifest.self,
            from: Data(contentsOf: packageManifestURL)
        )

        let imageSetID = uniqueObjectCaptureImageSetID(label: label, existing: captureBundle.objectCaptureImageSets)
        let imageSetRootURL = packageURL
            .appendingPathComponent("object-capture/image-sets", isDirectory: true)
            .appendingPathComponent(imageSetID, isDirectory: true)
        let packagedImagesURL = imageSetRootURL.appendingPathComponent("images", isDirectory: true)
        let packagedCheckpointURL = checkpointDirectoryURL.map { _ in
            imageSetRootURL.appendingPathComponent("checkpoint", isDirectory: true)
        }

        try copyDirectoryReplacingExisting(from: imagesDirectoryURL, to: packagedImagesURL)
        if let checkpointDirectoryURL, let packagedCheckpointURL {
            try copyDirectoryReplacingExisting(from: checkpointDirectoryURL, to: packagedCheckpointURL)
        }

        let imageSet = ObjectCaptureImageSet(
            id: imageSetID,
            label: label.isEmpty ? nil : label,
            imagesDirectoryURL: packagedImagesURL,
            checkpointDirectoryURL: packagedCheckpointURL,
            imageCount: imageCount,
            createdAt: createdAt,
            notes: "Captured with iPhone ObjectCaptureSession."
        )
        captureBundle.objectCaptureImageSets.append(imageSet)
        captureBundle.scanSession.objectCaptureImageSets = captureBundle.objectCaptureImageSets
        captureBundle.capturePlan = capturePlanByAddingObjectCapture(
            to: captureBundle.capturePlan,
            id: captureBundle.scanSession.id,
            label: imageSet.label ?? imageSet.id
        )

        try JSONEncoder.robotVisionLabEncoder.encode(captureBundle).write(to: captureBundleURL)

        let tools = SharedProjectFormatTools()
        upsertArtifact(
            role: "capture-bundle",
            url: captureBundleURL,
            packageRoot: packageURL,
            manifest: &packageManifest,
            tools: tools
        )
        upsertArtifact(
            role: "object-capture-image-set",
            url: packagedImagesURL,
            packageRoot: packageURL,
            manifest: &packageManifest,
            tools: tools
        )
        if let packagedCheckpointURL {
            upsertArtifact(
                role: "object-capture-checkpoint",
                url: packagedCheckpointURL,
                packageRoot: packageURL,
                manifest: &packageManifest,
                tools: tools
            )
        }
        let report = tools.validate(
            packageID: packageManifest.id,
            packageKind: "robotcapture",
            schemaVersion: packageManifest.schemaVersion,
            artifacts: packageManifest.artifacts,
            policy: packageManifest.artifactPolicy,
            packageRoot: packageURL
        )
        let reportURLs = try tools.writeReports(report, to: packageURL, title: ".robotcapture Project Report")
        packageManifest.validationReportURL = reportURLs.json
        packageManifest.humanReportURL = reportURLs.markdown
        try JSONEncoder.robotVisionLabEncoder.encode(packageManifest).write(to: packageManifestURL)

        refreshPackageBrowser()
        selectPackage(packageURL)
        transferEvents.insert(
            CaptureTransferEvent(
                title: "Object Capture Attached",
                detail: "\(imageSet.label ?? imageSet.id), \(imageCount) images"
            ),
            at: 0
        )
        return imageSet
    }

    public func startMacDiscovery() {
        do {
            let delegate = CaptureTransferDelegate { [weak self] event in
                self?.handleTransferEvent(event)
            }
            let sender = RobotCaptureMultipeerTransfer(role: .sender, inboxDirectory: documentsURL)
            sender.delegate = delegate
            try sender.start()
            self.sender = sender
            senderDelegate = delegate
            isBrowsingForMac = true
            state.stage = .browsingMacs
            state.latestMessage = "Looking for Robot Scene Studio on nearby Macs."
            transferEvents.insert(CaptureTransferEvent(title: "Discovery Started", detail: "Browsing for nearby Mac receivers."), at: 0)
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func stopMacDiscovery() {
        sender?.stop()
        sender = nil
        senderDelegate = nil
        connectedMacs.removeAll()
        discoveredMacs.removeAll()
        isBrowsingForMac = false
        state.stage = .idle
        transferEvents.insert(CaptureTransferEvent(title: "Discovery Stopped", detail: "Multipeer browser stopped."), at: 0)
    }

    public func sendSelectedPackage(to macName: String? = nil) {
        guard let packageURL = state.selectedPackageURL ?? state.packageURL else {
            fail("Select a .robotcapture package before sending.")
            return
        }
        do {
            if sender == nil {
                startMacDiscovery()
            }
            state.stage = .transferring
            state.transferProgress = 0.05
            state.latestMessage = "Sending \(packageURL.lastPathComponent) to Mac."
            lastTransferPackageURL = packageURL
            lastTransferPeerName = macName
            try sender?.sendRobotCapturePackage(at: packageURL, to: macName)
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func cancelTransfer() {
        sender?.cancelTransfers()
        state.stage = .idle
        state.latestMessage = "Transfer cancelled."
        state.transferProgress = 0
    }

    public func retryLastTransfer() {
        do {
            if sender == nil {
                startMacDiscovery()
            }
            if let packageURL = lastTransferPackageURL {
                try sender?.sendRobotCapturePackage(at: packageURL, to: lastTransferPeerName)
            } else {
                try sender?.retryLastPackage(to: lastTransferPeerName)
            }
            state.stage = .transferring
            state.latestMessage = "Retrying transfer."
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func finderSharingSummary() -> FinderFileSharingFallbackGuide {
        FinderFileSharingFallbackGuide()
    }

    private func makeCapturePlan(id: String) -> CapturePlan {
        var modes: Set<CaptureMode> = []
        if configuration.recordsVideo || configuration.recordsARKitPose {
            modes.insert(.rgbVideo)
        }
        if configuration.recordsLiDAR {
            modes.insert(.lidarDepth)
        }
        if configuration.recordsRoomPlan {
            modes.insert(.roomPlan)
        }
        if configuration.recordsCoreMotion {
            modes.insert(.coreMotion)
        }
        return CapturePlan(
            id: id,
            captureModes: modes,
            roomPlan: configuration.recordsRoomPlan ? RoomPlanOptions() : nil,
            rgbVideo: RGBVideoOptions(targetFPS: configuration.targetFPS),
            lidar: configuration.recordsLiDAR ? LiDAROptions() : nil
        )
    }

    private func handleTransferEvent(_ event: RobotCaptureTransferEvent) {
        switch event {
        case .peerFound(let name):
            if !discoveredMacs.contains(name) {
                discoveredMacs.append(name)
            }
            transferEvents.insert(CaptureTransferEvent(title: "Mac Found", detail: name), at: 0)
        case .peerLost(let name):
            discoveredMacs.removeAll { $0 == name }
            connectedMacs.removeAll { $0 == name }
            transferEvents.insert(CaptureTransferEvent(title: "Mac Lost", detail: name), at: 0)
        case .pairingInvitation(let name):
            transferEvents.insert(CaptureTransferEvent(title: "Pairing Requested", detail: name), at: 0)
        case .pairingAccepted(let name):
            transferEvents.insert(CaptureTransferEvent(title: "Pairing Accepted", detail: name), at: 0)
        case .pairingRejected(let name):
            transferEvents.insert(CaptureTransferEvent(title: "Pairing Rejected", detail: name), at: 0)
        case .peerConnected(let name):
            if !connectedMacs.contains(name) {
                connectedMacs.append(name)
            }
            transferEvents.insert(CaptureTransferEvent(title: "Mac Connected", detail: name), at: 0)
        case .peerDisconnected(let name):
            connectedMacs.removeAll { $0 == name }
            transferEvents.insert(CaptureTransferEvent(title: "Mac Disconnected", detail: name), at: 0)
        case .packageSendStarted(let url, let peer):
            state.stage = .transferring
            state.transferProgress = 0.2
            lastTransferPackageURL = url
            lastTransferPeerName = peer
            transferEvents.insert(CaptureTransferEvent(title: "Transfer Started", detail: "\(url.lastPathComponent) to \(peer)"), at: 0)
        case .packageSendProgress(_, let peer, let progress):
            state.stage = .transferring
            state.transferProgress = progress
            state.latestMessage = "Sending to \(peer): \(Int(progress * 100))%."
        case .packageSendFinished(let url, let peer):
            state.stage = .complete
            state.transferProgress = 1
            state.latestMessage = "Transfer complete."
            transferEvents.insert(CaptureTransferEvent(title: "Transfer Complete", detail: "\(url.lastPathComponent) to \(peer)"), at: 0)
        case .failed(let message):
            fail(message)
        case .recoverableFailure(let message, let packageURL):
            if let packageURL {
                lastTransferPackageURL = packageURL
            }
            transferEvents.insert(CaptureTransferEvent(title: "Recoverable Failure", detail: message), at: 0)
        case .packageReceiveStarted, .packageReceiveProgress, .packageReceiveFinished, .transferReceiptWritten:
            break
        }
        if transferEvents.count > 30 {
            transferEvents.removeLast(transferEvents.count - 30)
        }
    }

    private func startQualityTimer() {
        qualityTimer?.invalidate()
        qualityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickQuality()
            }
        }
    }

    private func stopQualityTimer() {
        qualityTimer?.invalidate()
        qualityTimer = nil
    }

    private func tickQuality() {
        guard let captureSession else { return }
        state.deviceCaptureState = captureSession.state
        let frameCount = captureSession.state.rgbFrameCount
        let lidarCount = captureSession.state.lidarFrameCount
        let trackingLevel: CaptureQualityLevel
        switch captureSession.state.lastTrackingQuality {
        case .normal:
            trackingLevel = .good
        case .limited:
            trackingLevel = .warning
        case .notAvailable:
            trackingLevel = .bad
        case nil:
            trackingLevel = frameCount > 0 ? .good : .warning
        }
        let lightingLevel: CaptureQualityLevel
        if let ambientIntensity = captureSession.state.lastAmbientIntensity {
            if ambientIntensity >= 180 {
                lightingLevel = .good
            } else if ambientIntensity >= 80 {
                lightingLevel = .warning
            } else {
                lightingLevel = .bad
            }
        } else {
            lightingLevel = frameCount > 10 ? .good : .unknown
        }
        let trackingText = captureSession.state.lastTrackingQuality?.rawValue ?? "warming-up"
        let lightingText = captureSession.state.lastAmbientIntensity.map { "\(Int($0.rounded())) ambient" } ?? "no light estimate"
        quality = CaptureQualityState(
            tracking: trackingLevel,
            lighting: lightingLevel,
            motion: permissions.motion == .granted ? .good : .warning,
            message: "\(frameCount) pose frames, \(lidarCount) LiDAR frames, tracking \(trackingText), \(lightingText)."
        )
    }

    private func timestampedCaptureName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "capture-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
    }

    private func fail(_ message: String) {
        state.stage = .failed
        state.latestMessage = message
        transferEvents.insert(CaptureTransferEvent(title: "Error", detail: message), at: 0)
    }

    private func capturePlanByAddingObjectCapture(to plan: CapturePlan?, id: String, label: String) -> CapturePlan {
        var next = plan ?? CapturePlan(id: id, captureModes: [])
        next.captureModes.insert(.objectCapture)
        if var objectCapture = next.objectCapture {
            if !objectCapture.objectLabels.contains(label) {
                objectCapture.objectLabels.append(label)
            }
            next.objectCapture = objectCapture
        } else {
            next.objectCapture = ObjectCaptureOptions(objectLabels: [label])
        }
        return next
    }

    private func uniqueObjectCaptureImageSetID(label: String, existing: [ObjectCaptureImageSet]) -> String {
        let base = safeFileComponent(label.isEmpty ? "object" : label)
        let existingIDs = Set(existing.map(\.id))
        if !existingIDs.contains(base) {
            return base
        }
        var suffix = 2
        while existingIDs.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    private func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let characters = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(characters).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "object" : sanitized
    }

    private func copyDirectoryReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CaptureClientError.missingObjectCaptureImageSet(sourceURL)
        }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func upsertArtifact(
        role: String,
        url: URL,
        packageRoot: URL,
        manifest: inout RobotCapturePackageManifest,
        tools: SharedProjectFormatTools
    ) {
        let record = tools.artifactRecord(role: role, url: url, packageRoot: packageRoot)
        manifest.artifacts.removeAll {
            $0.role == role && $0.url.standardizedFileURL.path == url.standardizedFileURL.path
        }
        manifest.artifacts.append(record)
    }

    private func countSupportedStillImages(in directoryURL: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, isSupportedStillImage(url) else { return nil }
            let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isRegularFile ? url : nil
        }.count
    }

    private func isSupportedStillImage(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff":
            return true
        default:
            return false
        }
    }
}

public enum CaptureClientPaths {
    public static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}

public enum CaptureClientError: Error, LocalizedError {
    case iOSRequired
    case noSelectedPackage
    case missingObjectCaptureImageSet(URL)
    case emptyObjectCaptureImageSet(URL)

    public var errorDescription: String? {
        switch self {
        case .iOSRequired:
            "AppleDeviceCaptureSession requires iOS."
        case .noSelectedPackage:
            "Select a .robotcapture package before attaching Object Capture images."
        case .missingObjectCaptureImageSet(let url):
            "Object Capture image directory is missing: \(url.path)"
        case .emptyObjectCaptureImageSet(let url):
            "Object Capture image directory contains no supported still images: \(url.path)"
        }
    }
}

private final class CaptureTransferDelegate: RobotCaptureTransferDelegate, @unchecked Sendable {
    private let handler: @MainActor @Sendable (RobotCaptureTransferEvent) -> Void

    init(handler: @escaping @MainActor @Sendable (RobotCaptureTransferEvent) -> Void) {
        self.handler = handler
    }

    func robotCaptureTransferDidEmit(_ event: RobotCaptureTransferEvent) {
        let handler = handler
        Task { @MainActor in
            handler(event)
        }
    }
}
