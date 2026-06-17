import XCTest
@testable import RobotVisionLabCore
@testable import RobotSceneStudioiPhone
import simd

final class PipelineGateTests: XCTestCase {
    func testGeneratedRobotPathFacesNavigationTarget() throws {
        let target = NavigationTarget(label: "dock", position: SIMD3<Double>(0, 0, -2))
        let path = RobotPathGenerator().generate(RobotPathGenerationRequest(
            strategy: .lawnmower(rows: 1, columns: 3),
            bounds: AxisAlignedBounds(
                minimum: SIMD3<Double>(-1, 0, 0),
                maximum: SIMD3<Double>(1, 0, 0)
            ),
            robotHeightMeters: 0,
            navigationTarget: target
        ))

        XCTAssertEqual(path.keyframes.count, 3)
        for keyframe in path.keyframes {
            let forward = keyframe.pose.orientation.value.act(SIMD3<Double>(0, 0, -1))
            let expected = simd_normalize(target.position - keyframe.pose.position)
            XCTAssertGreaterThan(simd_dot(forward, expected), 0.99)
        }
    }

    func testImporterRejectsVideoMovAsTrainingFrameImage() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let videoURL = root.appendingPathComponent("video.mov")
        try Data("not a still image".utf8).write(to: videoURL)
        try writeMinimalRobotCapturePackage(root: root, frameImageURL: videoURL)

        XCTAssertThrowsError(try RobotCaptureImporter().importPackage(at: root)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("not a supported still image"), message)
        }
    }

    func testCaptureBundleExporterCopiesReferencedRGBAssets() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceImageURL = sourceRoot.appendingPathComponent("frame_000000.png")
        try Self.tinyPNG.write(to: sourceImageURL)

        let outputURL = root.appendingPathComponent("Exported.robotcapture", isDirectory: true)
        let scan = ScanSession(
            id: "copy-test",
            rgbFrames: [
                CapturedRGBFrame(
                    imageURL: sourceImageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0
                )
            ]
        )
        let plan = CapturePlan(
            id: "copy-test-plan",
            captureModes: [.rgbVideo],
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720)
        )

        _ = try CaptureBundleExporter().writeBundle(scanSession: scan, capturePlan: plan, to: outputURL)

        let copiedImageURL = outputURL.appendingPathComponent("rgb/frame_000000.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedImageURL.path))
        let imported = try RobotCaptureImporter().importPackage(at: outputURL)
        XCTAssertEqual(imported.frames.count, 1)
        XCTAssertEqual(imported.frames.first?.imageURL.lastPathComponent, "frame_000000.png")
    }

    func testCaptureBundleExporterCopiesObjectCaptureImageSetDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let sourceRGBURL = sourceRoot.appendingPathComponent("rgb/frame_000000.png")
        let sourceImagesURL = sourceRoot.appendingPathComponent("object-capture/chair/images", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRGBURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceImagesURL, withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: sourceRGBURL)
        try Self.tinyPNG.write(to: sourceImagesURL.appendingPathComponent("IMG_0001.jpg"))

        let outputURL = root.appendingPathComponent("Exported.robotcapture", isDirectory: true)
        let objectImageSet = ObjectCaptureImageSet(
            id: "chair scan",
            label: "chair",
            imagesDirectoryURL: sourceImagesURL,
            imageCount: 1,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let scan = ScanSession(
            id: "object-image-set-test",
            rgbFrames: [
                CapturedRGBFrame(
                    imageURL: sourceRGBURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0
                )
            ],
            objectCaptureImageSets: [objectImageSet]
        )
        let plan = CapturePlan(
            id: "object-image-set-plan",
            captureModes: [.rgbVideo, .objectCapture],
            objectCapture: ObjectCaptureOptions(objectLabels: ["chair"]),
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720)
        )

        let bundle = try CaptureBundleExporter().writeBundle(scanSession: scan, capturePlan: plan, to: outputURL)
        let copiedImageURL = bundle.objectCaptureImageSets[0].imagesDirectoryURL.appendingPathComponent("IMG_0001.jpg")

        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedImageURL.path))
        XCTAssertTrue(copiedImageURL.path.contains("object-capture/image-sets/chair_scan/images"))

        let imported = try RobotCaptureImporter().importPackage(at: outputURL)
        let report = RobotCaptureImporter().makeReport(for: imported, packageURL: outputURL, importedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(imported.captureBundle.objectCaptureImageSets.count, 1)
        XCTAssertEqual(report.objectCaptureImageSetCount, 1)
        XCTAssertEqual(report.objectCaptureAssetCount, 0)
        XCTAssertFalse(report.warnings.contains { $0.contains("contains no supported still images") })
    }

    func testObjectCaptureReconstructionPlannerResolvesImportedImageSets() throws {
        let packageRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let imageSet = ObjectCaptureImageSet(
            id: "chair scan",
            label: "chair",
            imagesDirectoryURL: URL(fileURLWithPath: "object-capture/image-sets/chair_scan/images", isDirectory: true),
            imageCount: 24,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let plan = CapturePlan(
            id: "planner-plan",
            captureModes: [.objectCapture],
            objectCapture: ObjectCaptureOptions(objectLabels: ["chair"], preferredDetail: .full)
        )
        let bundle = CaptureBundleManifest(
            scanSession: ScanSession(id: "planner", objectCaptureImageSets: [imageSet]),
            capturePlan: plan,
            rgbFrames: [],
            lidarFrames: [],
            roomPlanModelURL: nil,
            objectCaptureAssetURLs: [],
            objectCaptureImageSets: [imageSet],
            splatTrainingManifestURL: URL(fileURLWithPath: "splat_training_manifest.json")
        )
        let imported = RobotCaptureImport(
            packageRoot: packageRoot,
            manifest: RobotCapturePackageManifest(
                id: "planner-package",
                videoURL: nil,
                framesJSONLURL: URL(fileURLWithPath: "frames.jsonl"),
                motionJSONLURL: nil,
                sessionJSONURL: URL(fileURLWithPath: "session.json"),
                captureBundleURL: URL(fileURLWithPath: "capture_bundle.json")
            ),
            session: RobotCaptureSessionMetadata(
                id: "planner",
                createdAt: Date(timeIntervalSince1970: 0),
                deviceModel: "test",
                operatingSystem: "test",
                lensDescription: "test"
            ),
            frames: [],
            motion: [],
            captureBundle: bundle
        )

        let requests = ObjectCaptureReconstructionPlanner().makeRequests(
            for: imported,
            outputDirectory: packageRoot.appendingPathComponent("ReconstructedObjects", isDirectory: true)
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].detail, .full)
        XCTAssertEqual(
            requests[0].imageSet.imagesDirectoryURL.path,
            packageRoot.appendingPathComponent("object-capture/image-sets/chair_scan/images", isDirectory: true).path
        )
        XCTAssertEqual(requests[0].outputURL.lastPathComponent, "chair.usdz")
    }

    @MainActor
    func testCaptureClientAttachesObjectCaptureImageSetToSelectedPackage() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let sourceRGBURL = sourceRoot.appendingPathComponent("rgb/frame_000000.png")
        let objectImagesURL = root.appendingPathComponent("object-images", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRGBURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: objectImagesURL, withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: sourceRGBURL)
        try Self.tinyPNG.write(to: objectImagesURL.appendingPathComponent("IMG_0001.jpg"))

        let packageURL = root.appendingPathComponent("Capture.robotcapture", isDirectory: true)
        let scan = ScanSession(
            id: "attach-object-test",
            rgbFrames: [
                CapturedRGBFrame(
                    imageURL: sourceRGBURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0
                )
            ]
        )
        let plan = CapturePlan(
            id: "attach-object-plan",
            captureModes: [.rgbVideo],
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720)
        )
        _ = try CaptureBundleExporter().writeBundle(scanSession: scan, capturePlan: plan, to: packageURL)

        let model = CaptureClientModel(documentsURL: root)
        model.selectPackage(packageURL)
        let imageSet = try model.attachObjectCaptureImageSet(label: "chair scan", imagesDirectoryURL: objectImagesURL)

        XCTAssertEqual(imageSet.id, "chair_scan")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageSet.imagesDirectoryURL.appendingPathComponent("IMG_0001.jpg").path))

        let bundleURL = packageURL.appendingPathComponent("capture_bundle.json")
        let bundle = try JSONDecoder.robotVisionLabDecoder.decode(CaptureBundleManifest.self, from: Data(contentsOf: bundleURL))
        XCTAssertEqual(bundle.objectCaptureImageSets.count, 1)
        XCTAssertEqual(bundle.capturePlan?.objectCapture?.objectLabels, ["chair scan"])

        let manifestURL = packageURL.appendingPathComponent("robotcapture.json")
        let manifest = try JSONDecoder.robotVisionLabDecoder.decode(RobotCapturePackageManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertTrue(manifest.artifacts.contains { $0.role == "object-capture-image-set" })

        let imported = try RobotCaptureImporter().importPackage(at: packageURL)
        let report = RobotCaptureImporter().makeReport(for: imported, packageURL: packageURL, importedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(report.objectCaptureImageSetCount, 1)
    }

    func testSplatTrainingPackageRejectsMissingImages() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let missingImageURL = root.appendingPathComponent("missing.jpg")
        let manifest = SplatTrainingManifest(
            id: "missing-image",
            imageFrames: [
                SplatTrainingFrame(
                    imageURL: missingImageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0,
                    calibration: SplatFrameCalibration(intrinsics: Self.intrinsics, resolution: .hd1280x720)
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("out.ply"))
        )
        let manifestURL = root.appendingPathComponent("manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let job = SplatTrainingJob(
            id: "missing-image-job",
            manifest: manifest,
            backend: AppleNativeTrainingBackend(),
            mode: .nativeAppleSilicon
        )

        XCTAssertThrowsError(try SplatTrainingPackageBuilder().writePackage(
            job: job,
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("package", isDirectory: true)
        )) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("image is missing"), message)
        }
    }

    func testRobotCaptureTransferArchiveRoundTripsPackageDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let packageURL = root.appendingPathComponent("Capture.robotcapture", isDirectory: true)
        let rgbDirectory = packageURL.appendingPathComponent("rgb", isDirectory: true)
        try FileManager.default.createDirectory(at: rgbDirectory, withIntermediateDirectories: true)
        try Data("{\"id\":\"capture\"}".utf8).write(to: packageURL.appendingPathComponent("robotcapture.json"))
        try Self.tinyPNG.write(to: rgbDirectory.appendingPathComponent("frame_000000.png"))

        let archiveURL = root.appendingPathComponent("Capture.robotcapturearchive")
        let extractedURL = root.appendingPathComponent("Received.robotcapture", isDirectory: true)
        let archive = RobotCapturePackageArchive()
        try archive.writeArchive(for: packageURL, to: archiveURL)
        try archive.extractArchive(at: archiveURL, to: extractedURL)

        XCTAssertEqual(
            try Data(contentsOf: packageURL.appendingPathComponent("robotcapture.json")),
            try Data(contentsOf: extractedURL.appendingPathComponent("robotcapture.json"))
        )
        XCTAssertEqual(
            try Data(contentsOf: rgbDirectory.appendingPathComponent("frame_000000.png")),
            try Data(contentsOf: extractedURL.appendingPathComponent("rgb/frame_000000.png"))
        )
    }

    func testDeviceCaptureReducerStoresTrackingAndLightingQuality() {
        let reducer = DeviceCaptureReducer()
        let recording = reducer.reduce(DeviceCaptureState(), event: .start)
        let updated = reducer.reduce(recording, event: .appendRGBFrame(.limited, 72))

        XCTAssertEqual(updated.rgbFrameCount, 1)
        XCTAssertEqual(updated.lastTrackingQuality, .limited)
        XCTAssertEqual(updated.lastAmbientIntensity, 72)
    }

    private static let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8z8BQDwAFgwJ/lwOfGAAAAABJRU5ErkJggg==")!

    private static let intrinsics = CameraIntrinsics(
        width: 1280,
        height: 720,
        focalLengthPixels: SIMD2<Double>(900, 900),
        principalPointPixels: SIMD2<Double>(640, 360)
    )

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RobotVisionLabCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeMinimalRobotCapturePackage(root: URL, frameImageURL: URL) throws {
        let framesURL = root.appendingPathComponent("frames.jsonl")
        let motionURL = root.appendingPathComponent("motion.jsonl")
        let sessionURL = root.appendingPathComponent("session.json")
        let bundleURL = root.appendingPathComponent("capture_bundle.json")
        let manifestURL = root.appendingPathComponent("robotcapture.json")
        let pose = Pose3D(position: SIMD3<Double>(0, 0, 0))
        let frame = RobotCaptureFrameRecord(
            index: 0,
            timestamp: 0,
            imageURL: frameImageURL,
            cameraTransform: Transform3D(translation: pose.position, rotation: pose.orientation.value),
            intrinsics: Self.intrinsics
        )
        try writeJSONLines([frame], to: framesURL)
        try writeJSONLines([RobotCaptureMotionRecord(timestamp: 0)], to: motionURL)
        let session = RobotCaptureSessionMetadata(
            id: "bad-video-frame",
            createdAt: Date(timeIntervalSince1970: 0),
            deviceModel: "test",
            operatingSystem: "test",
            lensDescription: "test"
        )
        try JSONEncoder.robotVisionLabEncoder.encode(session).write(to: sessionURL)
        let capturedFrame = CapturedRGBFrame(imageURL: frameImageURL, pose: pose, timestamp: 0)
        let trainingManifestURL = root.appendingPathComponent("splat_training_manifest.json")
        let trainingManifest = SplatTrainingManifest(
            id: "bad-video-frame-training",
            imageFrames: [
                SplatTrainingFrame(
                    imageURL: frameImageURL,
                    pose: pose,
                    timestamp: 0,
                    calibration: SplatFrameCalibration(intrinsics: Self.intrinsics, resolution: .hd1280x720)
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("out.ply"))
        )
        try JSONEncoder.robotVisionLabEncoder.encode(trainingManifest).write(to: trainingManifestURL)
        let bundle = CaptureBundleManifest(
            scanSession: ScanSession(id: "bad-video-frame", rgbFrames: [capturedFrame]),
            capturePlan: nil,
            rgbFrames: [capturedFrame],
            lidarFrames: [],
            roomPlanModelURL: nil,
            objectCaptureAssetURLs: [],
            splatTrainingManifestURL: trainingManifestURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(bundle).write(to: bundleURL)
        let manifest = RobotCapturePackageManifest(
            id: "bad-video-frame-package",
            videoURL: frameImageURL,
            framesJSONLURL: framesURL,
            motionJSONLURL: motionURL,
            sessionJSONURL: sessionURL,
            captureBundleURL: bundleURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
    }

    private func writeJSONLines<T: Encodable>(_ records: [T], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = try records.map { record in
            String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
