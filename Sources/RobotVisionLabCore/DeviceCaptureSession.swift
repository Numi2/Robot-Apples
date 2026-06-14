import Foundation

public enum DeviceCapturePhase: String, Codable, Equatable, Sendable {
    case idle
    case capturing
    case paused
    case finished
    case failed
}

public struct DeviceCaptureState: Codable, Equatable, Sendable {
    public var phase: DeviceCapturePhase
    public var rgbFrameCount: Int
    public var lidarFrameCount: Int
    public var hasRoomPlanModel: Bool
    public var objectCaptureAssetCount: Int
    public var lastErrorDescription: String?

    public init(
        phase: DeviceCapturePhase = .idle,
        rgbFrameCount: Int = 0,
        lidarFrameCount: Int = 0,
        hasRoomPlanModel: Bool = false,
        objectCaptureAssetCount: Int = 0,
        lastErrorDescription: String? = nil
    ) {
        self.phase = phase
        self.rgbFrameCount = rgbFrameCount
        self.lidarFrameCount = lidarFrameCount
        self.hasRoomPlanModel = hasRoomPlanModel
        self.objectCaptureAssetCount = objectCaptureAssetCount
        self.lastErrorDescription = lastErrorDescription
    }
}

public enum DeviceCaptureEvent: Equatable, Sendable {
    case start
    case pause
    case resume
    case appendRGBFrame
    case appendLiDARFrame
    case setRoomPlanModel
    case appendObjectCaptureAsset
    case finish
    case fail(String)
}

public struct DeviceCaptureReducer: Sendable {
    public init() {}

    public func reduce(_ state: DeviceCaptureState, event: DeviceCaptureEvent) -> DeviceCaptureState {
        var next = state
        switch event {
        case .start:
            next.phase = .capturing
            next.lastErrorDescription = nil
        case .pause:
            if state.phase == .capturing {
                next.phase = .paused
            }
        case .resume:
            if state.phase == .paused {
                next.phase = .capturing
            }
        case .appendRGBFrame:
            if state.phase == .capturing {
                next.rgbFrameCount += 1
            }
        case .appendLiDARFrame:
            if state.phase == .capturing {
                next.lidarFrameCount += 1
            }
        case .setRoomPlanModel:
            next.hasRoomPlanModel = true
        case .appendObjectCaptureAsset:
            next.objectCaptureAssetCount += 1
        case .finish:
            next.phase = .finished
        case .fail(let message):
            next.phase = .failed
            next.lastErrorDescription = message
        }
        return next
    }
}

public protocol DeviceCaptureSessionControlling: AnyObject {
    var state: DeviceCaptureState { get }
    func start(plan: CapturePlan, outputDirectory: URL) throws
    func pause()
    func resume()
    func finish() throws -> ScanSession
}

#if os(iOS)
import ARKit
import AVFoundation
import CoreMotion
import RoomPlan
import UIKit

@available(iOS 17.0, *)
public final class AppleDeviceCaptureSession: NSObject, DeviceCaptureSessionControlling, ARSessionDelegate, AVCaptureFileOutputRecordingDelegate, RoomCaptureSessionDelegate {
    public private(set) var state = DeviceCaptureState()

    private let reducer = DeviceCaptureReducer()
    private let arSession = ARSession()
    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let roomCaptureSession = RoomCaptureSession()
    private var plan: CapturePlan?
    private var outputDirectory: URL?
    private var rgbFrames: [CapturedRGBFrame] = []
    private var lidarFrames: [CapturedLiDARFrame] = []
    private var roomPlanModelURL: URL?
    private var objectCaptureAssetURLs: [URL] = []
    private var videoURL: URL?
    private var framesJSONLURL: URL?
    private var motionJSONLURL: URL?
    private var sessionJSONURL: URL?
    private var frameRecordIndex = 0
    private var framesJSONLHandle: FileHandle?
    private var motionJSONLHandle: FileHandle?

    public override init() {
        super.init()
        arSession.delegate = self
        roomCaptureSession.delegate = self
        motionQueue.name = "RobotVisionLabCore.MotionCapture"
    }

    public func start(plan: CapturePlan, outputDirectory: URL) throws {
        try plan.validate()
        self.plan = plan
        self.outputDirectory = outputDirectory
        try createCaptureDirectories(at: outputDirectory)
        try openMetadataStreams(at: outputDirectory)
        frameRecordIndex = 0
        rgbFrames.removeAll()
        lidarFrames.removeAll()
        roomPlanModelURL = nil
        objectCaptureAssetURLs.removeAll()
        state = reducer.reduce(state, event: .start)

        if plan.captureModes.contains(.rgbVideo) || plan.captureModes.contains(.lidarDepth) {
            let configuration = ARWorldTrackingConfiguration()
            if plan.captureModes.contains(.lidarDepth), ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            arSession.run(configuration)
        }
        if plan.captureModes.contains(.rgbVideo) {
            try startMovieCapture(plan: plan, outputDirectory: outputDirectory)
        }
        startMotionCapture()
        if plan.captureModes.contains(.roomPlan) {
            roomCaptureSession.run(configuration: RoomCaptureSession.Configuration())
        }
    }

    public func pause() {
        arSession.pause()
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        motionManager.stopDeviceMotionUpdates()
        roomCaptureSession.stop()
        state = reducer.reduce(state, event: .pause)
    }

    public func resume() {
        guard let plan, let outputDirectory else { return }
        try? start(plan: plan, outputDirectory: outputDirectory)
    }

    public func finish() throws -> ScanSession {
        arSession.pause()
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        motionManager.stopDeviceMotionUpdates()
        roomCaptureSession.stop()
        try closeMetadataStreams()
        if let outputDirectory {
            try writeSessionMetadata(to: outputDirectory)
            try writeCaptureBundleMetadata(to: outputDirectory)
            try writeRobotCaptureManifest(to: outputDirectory)
        }
        state = reducer.reduce(state, event: .finish)

        return ScanSession(
            id: outputDirectory?.lastPathComponent ?? UUID().uuidString,
            rgbFrames: rgbFrames,
            lidarFrames: lidarFrames,
            roomPlanModelURL: roomPlanModelURL,
            objectCaptureAssetURLs: objectCaptureAssetURLs
        )
    }

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard state.phase == .capturing, let outputDirectory else { return }
        let pose = Pose3D(matrix: frame.camera.transform)
        let timestamp = frame.timestamp

        if plan?.captureModes.contains(.rgbVideo) == true {
            let frameURL = videoURL ?? outputDirectory.appendingPathComponent("video.mov")
            rgbFrames.append(CapturedRGBFrame(imageURL: frameURL, pose: pose, timestamp: timestamp))
            writeFrameRecord(frame: frame, pose: pose, imageURL: frameURL)
            state = reducer.reduce(state, event: .appendRGBFrame)
        }

        if plan?.captureModes.contains(.lidarDepth) == true, let sceneDepth = frame.sceneDepth {
            if let lidarFrame = try? writeLiDARFrameArtifacts(
                sceneDepth: sceneDepth,
                frame: frame,
                pose: pose,
                to: outputDirectory.appendingPathComponent("lidar"),
                timestamp: timestamp
            ) {
                lidarFrames.append(lidarFrame)
                state = reducer.reduce(state, event: .appendLiDARFrame)
            }
        }
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            state = reducer.reduce(state, event: .fail(error.localizedDescription))
        }
    }

    public func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error {
            state = reducer.reduce(state, event: .fail(error.localizedDescription))
        }
    }

    public func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        guard let outputDirectory else { return }
        let url = outputDirectory.appendingPathComponent("roomplan").appendingPathComponent("room.usdz")
        do {
            try room.export(to: url, exportOptions: .parametric)
            roomPlanModelURL = url
            state = reducer.reduce(state, event: .setRoomPlanModel)
        } catch {
            state = reducer.reduce(state, event: .fail(error.localizedDescription))
        }
    }

    private func createCaptureDirectories(at outputDirectory: URL) throws {
        let fileManager = FileManager.default
        for folder in ["rgb", "lidar", "roomplan", "object-capture", "splats"] {
            try fileManager.createDirectory(
                at: outputDirectory.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func writeLiDARFrameArtifacts(
        sceneDepth: ARDepthData,
        frame: ARFrame,
        pose: Pose3D,
        to directory: URL,
        timestamp: TimeInterval
    ) throws -> CapturedLiDARFrame {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestampMilliseconds = Int((timestamp * 1000).rounded())
        let depthURL = directory.appendingPathComponent(String(format: "depth_%06d.f32", timestampMilliseconds))
        let confidenceURL = sceneDepth.confidenceMap.map { _ in
            directory.appendingPathComponent(String(format: "confidence_%06d.bin", timestampMilliseconds))
        }
        let metadataURL = directory.appendingPathComponent(String(format: "depth_%06d.json", timestampMilliseconds))

        let depthSize = try writeFloat32DepthBuffer(sceneDepth.depthMap, to: depthURL)
        if let confidenceMap = sceneDepth.confidenceMap, let confidenceURL {
            try writeUInt8PixelBuffer(confidenceMap, to: confidenceURL)
        }

        let metadata = CapturedLiDARDepthMetadata(
            timestamp: timestamp,
            width: depthSize.width,
            height: depthSize.height,
            confidenceFormat: confidenceURL == nil ? nil : "uint8-arkit-confidence-row-major",
            cameraPose: pose,
            intrinsics: CameraIntrinsics(matrix: frame.camera.intrinsics, resolution: frame.camera.imageResolution),
            depthURL: depthURL,
            confidenceURL: confidenceURL,
            notes: "ARKit sceneDepth.depthMap captured as Float32 meters without PNG quantization."
        )
        try JSONEncoder.robotVisionLabEncoder.encode(metadata).write(to: metadataURL)
        return CapturedLiDARFrame(
            depthURL: depthURL,
            confidenceURL: confidenceURL,
            metadataURL: metadataURL,
            pose: pose,
            timestamp: timestamp
        )
    }

    private func writeFloat32DepthBuffer(_ pixelBuffer: CVPixelBuffer, to url: URL) throws -> (width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw AppleDeviceCaptureError.missingPixelBufferBaseAddress
        }
        var data = Data(capacity: width * height * MemoryLayout<Float32>.stride)
        for row in 0..<height {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for column in 0..<width {
                var value = rowPointer[column]
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
        }
        try data.write(to: url, options: .atomic)
        return (width, height)
    }

    private func writeUInt8PixelBuffer(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw AppleDeviceCaptureError.missingPixelBufferBaseAddress
        }
        var data = Data(capacity: width * height)
        for row in 0..<height {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            data.append(rowPointer, count: width)
        }
        try data.write(to: url, options: .atomic)
    }

    private func startMovieCapture(plan: CapturePlan, outputDirectory: URL) throws {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        captureSession.sessionPreset = sessionPreset(for: plan.rgbVideo?.targetResolution)

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw AppleDeviceCaptureError.missingVideoDevice
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw AppleDeviceCaptureError.cannotAddVideoInput
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(movieOutput) else {
            throw AppleDeviceCaptureError.cannotAddMovieOutput
        }
        captureSession.addOutput(movieOutput)

        if let targetFPS = plan.rgbVideo?.targetFPS {
            try device.lockForConfiguration()
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
        }

        let url = outputDirectory.appendingPathComponent("video.mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        videoURL = url
        captureSession.startRunning()
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    private func sessionPreset(for resolution: Resolution?) -> AVCaptureSession.Preset {
        guard let resolution else { return .hd1280x720 }
        if resolution.width >= 3840 || resolution.height >= 2160 {
            return .hd4K3840x2160
        }
        return .hd1280x720
    }

    private func openMetadataStreams(at outputDirectory: URL) throws {
        framesJSONLURL = outputDirectory.appendingPathComponent("frames.jsonl")
        motionJSONLURL = outputDirectory.appendingPathComponent("motion.jsonl")
        sessionJSONURL = outputDirectory.appendingPathComponent("session.json")
        for url in [framesJSONLURL, motionJSONLURL].compactMap({ $0 }) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        framesJSONLHandle = try framesJSONLURL.map { try FileHandle(forWritingTo: $0) }
        motionJSONLHandle = try motionJSONLURL.map { try FileHandle(forWritingTo: $0) }
    }

    private func closeMetadataStreams() throws {
        try framesJSONLHandle?.close()
        try motionJSONLHandle?.close()
        framesJSONLHandle = nil
        motionJSONLHandle = nil
    }

    private func writeFrameRecord(frame: ARFrame, pose: Pose3D, imageURL: URL) {
        let intrinsics = CameraIntrinsics(matrix: frame.camera.intrinsics, resolution: frame.camera.imageResolution)
        let record = RobotCaptureFrameRecord(
            index: frameRecordIndex,
            timestamp: frame.timestamp,
            imageURL: imageURL,
            cameraTransform: Transform3D(translation: pose.position, rotation: pose.orientation.value),
            intrinsics: intrinsics,
            trackingQuality: TrackingQuality(frame.camera.trackingState)
        )
        frameRecordIndex += 1
        writeJSONLine(record, to: framesJSONLHandle)
    }

    private func startMotionCapture() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / Double(plan?.rgbVideo?.targetFPS ?? 60)
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion, self.state.phase == .capturing else { return }
            let record = RobotCaptureMotionRecord(motion)
            self.writeJSONLine(record, to: self.motionJSONLHandle)
        }
    }

    private func writeSessionMetadata(to outputDirectory: URL) throws {
        let metadata = RobotCaptureSessionMetadata(
            id: outputDirectory.lastPathComponent,
            createdAt: Date(),
            deviceModel: UIDevice.current.model,
            operatingSystem: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            lensDescription: "AVCaptureDevice builtInWideAngleCamera back",
            resolution: plan?.rgbVideo?.targetResolution,
            targetFPS: plan?.rgbVideo?.targetFPS,
            notes: "Recorded with AVFoundation video.mov, ARKit camera pose/intrinsics frames.jsonl, and Core Motion motion.jsonl."
        )
        try JSONEncoder.robotVisionLabEncoder.encode(metadata).write(to: outputDirectory.appendingPathComponent("session.json"))
    }

    private func writeRobotCaptureManifest(to outputDirectory: URL) throws {
        let tools = SharedProjectFormatTools()
        let lidarArtifactURLs = lidarFrames.flatMap { frame in
            [
                ("lidar-depth", frame.depthURL),
                ("lidar-metadata", frame.metadataURL)
            ] + [frame.confidenceURL.map { ("lidar-confidence", $0) }].compactMap { $0 }
        }
        let structuredGeometryArtifactURLs: [(String, URL)] =
            [roomPlanModelURL.map { ("roomplan-geometry", $0) }].compactMap { $0 }
            + objectCaptureAssetURLs.map { ("object-capture-geometry", $0) }
        let artifactURLs: [(String, URL)] = [
            ("video", outputDirectory.appendingPathComponent("video.mov")),
            ("frames", outputDirectory.appendingPathComponent("frames.jsonl")),
            ("motion", outputDirectory.appendingPathComponent("motion.jsonl")),
            ("session", outputDirectory.appendingPathComponent("session.json")),
            ("capture-bundle", outputDirectory.appendingPathComponent("capture_bundle.json")),
            ("splat-training-manifest", outputDirectory.appendingPathComponent("splat_training_manifest.json"))
        ] + lidarArtifactURLs + structuredGeometryArtifactURLs
        let artifacts = artifactURLs.map { tools.artifactRecord(role: $0.0, url: $0.1, packageRoot: outputDirectory) }
        let report = tools.validate(
            packageID: "\(outputDirectory.lastPathComponent)-robot-capture",
            packageKind: "robotcapture",
            schemaVersion: .robotCaptureV1,
            artifacts: artifacts,
            policy: PackageArtifactSizePolicy(),
            packageRoot: outputDirectory
        )
        let reportURLs = try tools.writeReports(report, to: outputDirectory, title: ".robotcapture Project Report")

        let capturePackage = RobotCapturePackageManifest(
            id: "\(outputDirectory.lastPathComponent)-robot-capture",
            artifacts: artifacts,
            validationReportURL: reportURLs.json,
            humanReportURL: reportURLs.markdown,
            videoURL: outputDirectory.appendingPathComponent("video.mov"),
            framesJSONLURL: outputDirectory.appendingPathComponent("frames.jsonl"),
            motionJSONLURL: outputDirectory.appendingPathComponent("motion.jsonl"),
            sessionJSONURL: outputDirectory.appendingPathComponent("session.json"),
            captureBundleURL: outputDirectory.appendingPathComponent("capture_bundle.json"),
            notes: "Primary transfer path is Multipeer Connectivity from iPhone/iPad to Mac."
        )
        try JSONEncoder.robotVisionLabEncoder.encode(capturePackage).write(to: outputDirectory.appendingPathComponent("robotcapture.json"))
    }

    private func writeCaptureBundleMetadata(to outputDirectory: URL) throws {
        let scanSession = ScanSession(
            id: outputDirectory.lastPathComponent,
            createdAt: Date(),
            rgbFrames: rgbFrames,
            lidarFrames: lidarFrames,
            roomPlanModelURL: roomPlanModelURL,
            objectCaptureAssetURLs: objectCaptureAssetURLs
        )
        let splatTrainingManifest = SplatTrainingManifest(
            id: "\(scanSession.id)-splat-training",
            imageFrames: rgbFrames.map {
                SplatTrainingFrame(
                    imageURL: $0.imageURL,
                    pose: $0.pose,
                    timestamp: $0.timestamp,
                    calibration: SplatFrameCalibration(
                        intrinsics: plan?.rgbVideo.map {
                            CameraIntrinsics(
                                width: $0.targetResolution.width,
                                height: $0.targetResolution.height,
                                focalLengthPixels: SIMD2(
                                    Double($0.targetResolution.width),
                                    Double($0.targetResolution.width)
                                ),
                                principalPointPixels: SIMD2(
                                    Double($0.targetResolution.width) / 2.0,
                                    Double($0.targetResolution.height) / 2.0
                                )
                            )
                        },
                        resolution: plan?.rgbVideo?.targetResolution,
                        trackingQuality: .normal
                    )
                )
            },
            lidarFrames: lidarFrames,
            roomPlanGeometryURL: roomPlanModelURL,
            objectGeometryURLs: objectCaptureAssetURLs,
            expectedOutput: SplatTrainingOutput(
                targetURL: outputDirectory
                    .appendingPathComponent("splats", isDirectory: true)
                    .appendingPathComponent("\(scanSession.id).ply")
            )
        )
        let splatTrainingManifestURL = outputDirectory.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(splatTrainingManifest).write(to: splatTrainingManifestURL)

        let captureBundle = CaptureBundleManifest(
            scanSession: scanSession,
            capturePlan: plan,
            rgbFrames: rgbFrames,
            lidarFrames: lidarFrames,
            roomPlanModelURL: roomPlanModelURL,
            objectCaptureAssetURLs: objectCaptureAssetURLs,
            splatTrainingManifestURL: splatTrainingManifestURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(captureBundle).write(to: outputDirectory.appendingPathComponent("capture_bundle.json"))
    }

    private func writeJSONLine<T: Encodable>(_ value: T, to handle: FileHandle?) {
        guard let handle else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        handle.write(data)
        handle.write(Data([0x0A]))
    }
}

@available(iOS 17.0, *)
private extension Pose3D {
    init(matrix: simd_float4x4) {
        let position = SIMD3<Double>(
            Double(matrix.columns.3.x),
            Double(matrix.columns.3.y),
            Double(matrix.columns.3.z)
        )
        let rotationMatrix = simd_double3x3(columns: (
            SIMD3<Double>(Double(matrix.columns.0.x), Double(matrix.columns.0.y), Double(matrix.columns.0.z)),
            SIMD3<Double>(Double(matrix.columns.1.x), Double(matrix.columns.1.y), Double(matrix.columns.1.z)),
            SIMD3<Double>(Double(matrix.columns.2.x), Double(matrix.columns.2.y), Double(matrix.columns.2.z))
        ))
        let rotation = simd_quatd(rotationMatrix)
        self.init(position: position, orientation: rotation)
    }
}

@available(iOS 17.0, *)
private extension CameraIntrinsics {
    init(matrix: simd_float3x3, resolution: CGSize) {
        self.init(
            width: Int(resolution.width),
            height: Int(resolution.height),
            focalLengthPixels: SIMD2(Double(matrix.columns.0.x), Double(matrix.columns.1.y)),
            principalPointPixels: SIMD2(Double(matrix.columns.2.x), Double(matrix.columns.2.y))
        )
    }
}

@available(iOS 17.0, *)
private extension TrackingQuality {
    init(_ trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            self = .normal
        case .limited:
            self = .limited
        case .notAvailable:
            self = .notAvailable
        }
    }
}

@available(iOS 17.0, *)
private extension RobotCaptureMotionRecord {
    init(_ motion: CMDeviceMotion) {
        self.init(
            timestamp: motion.timestamp,
            angularVelocityRadiansPerSecond: SIMD3(
                motion.rotationRate.x,
                motion.rotationRate.y,
                motion.rotationRate.z
            ),
            accelerationMetersPerSecondSquared: SIMD3(
                motion.userAcceleration.x,
                motion.userAcceleration.y,
                motion.userAcceleration.z
            ),
            attitude: QuaternionCodable(
                simd_quatd(
                    ix: motion.attitude.quaternion.x,
                    iy: motion.attitude.quaternion.y,
                    iz: motion.attitude.quaternion.z,
                    r: motion.attitude.quaternion.w
                )
            )
        )
    }
}

@available(iOS 17.0, *)
public enum AppleDeviceCaptureError: Error, LocalizedError {
    case missingVideoDevice
    case cannotAddVideoInput
    case cannotAddMovieOutput
    case missingPixelBufferBaseAddress

    public var errorDescription: String? {
        switch self {
        case .missingVideoDevice:
            "No back wide-angle AVCaptureDevice is available."
        case .cannotAddVideoInput:
            "AVCaptureSession could not add the video input."
        case .cannotAddMovieOutput:
            "AVCaptureSession could not add AVCaptureMovieFileOutput."
        case .missingPixelBufferBaseAddress:
            "ARKit LiDAR pixel buffer did not expose a readable base address."
        }
    }
}
#endif
