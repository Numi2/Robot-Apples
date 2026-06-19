import CoreGraphics
import ImageIO
import XCTest
import UniformTypeIdentifiers
@testable import RobotVisionLabCore
@testable import RobotSceneStudioiPhone
@testable import RobotSceneStudioMac
@testable import RobotSceneStudioVision
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
        let copiedImageURL = PackageURLTools
            .resolve(bundle.objectCaptureImageSets[0].imagesDirectoryURL, relativeTo: outputURL)
            .appendingPathComponent("IMG_0001.jpg")

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
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: PackageURLTools
                .resolve(imageSet.imagesDirectoryURL, relativeTo: packageURL)
                .appendingPathComponent("IMG_0001.jpg")
                .path
        ))

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

    func testRobotCapturePackageUsesRelativeURLsAndImportsAfterRelocation() throws {
        let originalRoot = try makeTemporaryDirectory()
        let movedRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: originalRoot)
            try? FileManager.default.removeItem(at: movedRoot)
        }

        let sourceRoot = originalRoot.appendingPathComponent("source", isDirectory: true)
        let sourceImageURL = sourceRoot.appendingPathComponent("rgb/frame_000000.png")
        try FileManager.default.createDirectory(at: sourceImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: sourceImageURL)

        let packageURL = originalRoot.appendingPathComponent("Capture.robotcapture", isDirectory: true)
        let scan = ScanSession(
            id: "portable-capture",
            rgbFrames: [
                CapturedRGBFrame(
                    imageURL: sourceImageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0
                )
            ]
        )
        let plan = CapturePlan(
            id: "portable-capture-plan",
            captureModes: [.rgbVideo],
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720)
        )
        _ = try CaptureBundleExporter().writeBundle(scanSession: scan, capturePlan: plan, to: packageURL)

        let manifest = try JSONDecoder.robotVisionLabDecoder.decode(
            RobotCapturePackageManifest.self,
            from: Data(contentsOf: packageURL.appendingPathComponent("robotcapture.json"))
        )
        let bundle = try JSONDecoder.robotVisionLabDecoder.decode(
            CaptureBundleManifest.self,
            from: Data(contentsOf: packageURL.appendingPathComponent("capture_bundle.json"))
        )
        XCTAssertFalse(manifest.sessionJSONURL.isFileURL)
        XCTAssertFalse(manifest.framesJSONLURL.isFileURL)
        XCTAssertFalse(bundle.rgbFrames[0].imageURL.isFileURL)
        XCTAssertFalse(bundle.splatTrainingManifestURL.isFileURL)

        let movedPackageURL = movedRoot.appendingPathComponent("Moved.robotcapture", isDirectory: true)
        try FileManager.default.copyItem(at: packageURL, to: movedPackageURL)
        try FileManager.default.removeItem(at: originalRoot)

        let imported = try RobotCaptureImporter().importPackage(at: movedPackageURL)
        XCTAssertEqual(imported.frames.count, 1)
        XCTAssertTrue(imported.frames[0].imageURL.isFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.frames[0].imageURL.path))
    }

    func testRobotCaptureImportRejectsRelativePathTraversal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let packageURL = root.appendingPathComponent("Escape.robotcapture", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let outsideImageURL = root.appendingPathComponent("outside.png")
        try Self.tinyPNG.write(to: outsideImageURL)

        try writeMinimalRobotCapturePackage(
            root: packageURL,
            frameImageURL: PackageURLTools.relativeURL(path: "../outside.png")
        )

        XCTAssertThrowsError(try RobotCaptureImporter().importPackage(at: packageURL)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("image is missing"), message)
            XCTAssertFalse(message.contains(outsideImageURL.path), message)
        }
    }

    func testRobotScenePackageUsesRelativeReviewURLsAndOpensAfterRelocation() throws {
        let originalRoot = try makeTemporaryDirectory()
        let movedRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: originalRoot)
            try? FileManager.default.removeItem(at: movedRoot)
        }

        let splatURL = originalRoot.appendingPathComponent("scene.ply")
        try Self.singlePointGaussianPLY.write(to: splatURL, atomically: true, encoding: .utf8)
        let asset = try GaussianSplatImporter().inspect(url: splatURL)
        let scene = asset.makeScene(id: "portable-scene")
        let rig = RobotCameraRig(
            name: "test-rig",
            mountHeightMeters: 0.5,
            intrinsics: Self.intrinsics
        )
        let manifest = DatasetManifest(
            recipeID: "portable-scene-recipe",
            scene: scene,
            cameraRig: rig,
            frames: [
                DatasetFrame(
                    index: 0,
                    timestamp: 0,
                    cameraPose: Pose3D(position: SIMD3<Double>(0, 0, 1)),
                    navigationTarget: nil,
                    products: [],
                    augmentations: [],
                    labelSources: []
                )
            ]
        )
        let packageURL = originalRoot.appendingPathComponent("Project.robotscene", isDirectory: true)
        _ = try RobotScenePackageExporter().writeRobotScenePackage(manifest: manifest, to: packageURL)

        let sceneManifest = try JSONDecoder.robotVisionLabDecoder.decode(
            RobotScenePackageManifest.self,
            from: Data(contentsOf: packageURL.appendingPathComponent("robotscene.json"))
        )
        XCTAssertFalse(sceneManifest.datasetManifestURL.isFileURL)
        XCTAssertFalse(sceneManifest.failureMapURL.isFileURL)
        XCTAssertFalse(sceneManifest.visionProReviewAsset.robotRouteURL.isFileURL)
        XCTAssertFalse(sceneManifest.visionProReviewAsset.datasetManifestURL.isFileURL)

        let movedPackageURL = movedRoot.appendingPathComponent("Moved.robotscene", isDirectory: true)
        try FileManager.default.copyItem(at: packageURL, to: movedPackageURL)
        try FileManager.default.removeItem(at: originalRoot)

        let model = SpatialReviewModel()
        try model.openRobotScene(at: movedPackageURL)
        XCTAssertEqual(model.state.summary?.frameCount, 1)
        XCTAssertNotNil(model.state.summary?.splatURL)
        XCTAssertTrue(model.state.diagnostics.isEmpty)
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

	    func testSplatTrainingPackageWritesProductionOptimizationArtifacts() throws {
	        let root = try makeTemporaryDirectory()
	        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)

        let manifest = SplatTrainingManifest(
            id: "production-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("out/scene.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(productionRequirements: .skipEvaluation).writePackage(
            job: SplatTrainingJob(
                id: "production-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .nativeAppleSilicon
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        XCTAssertEqual(package.optimizerProfile, .productionBrush)
        let planURL = try XCTUnwrap(package.optimizerPlanURL)
        let transformsURL = try XCTUnwrap(package.nerfstudioTransformsURL)
        let runnerURL = try XCTUnwrap(package.productionRunnerURL)
        let brushDatasetURL = try XCTUnwrap(package.brushDatasetURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: planURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transformsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runnerURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: brushDatasetURL.path))

        let plan = try JSONDecoder.robotVisionLabDecoder.decode(SplatOptimizationPlan.self, from: Data(contentsOf: planURL))
        XCTAssertEqual(plan.profile, .productionBrush)
        XCTAssertTrue(plan.trainer.contains("Brush"))
        XCTAssertTrue(plan.optimizationStages.contains { $0.name.contains("refinement") && $0.purpose.contains("pruning") })
        XCTAssertTrue(plan.qualityGates.contains { $0.contains("GaussianSplatImporter") })

        let transformsObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: transformsURL)) as? [String: Any]
        )
        let frames = try XCTUnwrap(transformsObject["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0]["file_path"] as? String, "images/train/frame_000000.png")
        XCTAssertEqual(frames[0]["split"] as? String, "train")
        XCTAssertEqual(frames[1]["file_path"] as? String, "images/train/frame_000001.png")
        XCTAssertEqual(frames[1]["split"] as? String, "train")
        XCTAssertEqual(frames[2]["file_path"] as? String, "images/eval/frame_000002.png")
        XCTAssertEqual(frames[2]["split"] as? String, "validation")
        let copiedImageURL = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("images/train/frame_000000.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedImageURL.path))

        let runner = try String(contentsOf: runnerURL, encoding: .utf8)
        XCTAssertTrue(runner.contains("brush-cli"))
        XCTAssertTrue(runner.contains("prepare_brush_dataset"))
        XCTAssertTrue(runner.contains("ns-train"))
        XCTAssertTrue(runner.contains("ns-eval"))
        XCTAssertTrue(runner.contains("ns-export"))
	        XCTAssertTrue(runner.contains("gaussian-splat"))
		    }

    func testSplatTrainingPackageRejectsBelowProductionFrameMinimums() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "undersized-production-splat",
            imageFrames: [
                SplatTrainingFrame(
                    imageURL: imageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0,
                    calibration: Self.tinyImageCalibration,
                    split: .train
                ),
                SplatTrainingFrame(
                    imageURL: imageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, -0.05)),
                    timestamp: 1,
                    calibration: Self.tinyImageCalibration,
                    split: .validation
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("out/undersized.ply"))
        )
        let manifestURL = root.appendingPathComponent("undersized_splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)

        XCTAssertThrowsError(try SplatTrainingPackageBuilder().writePackage(
            job: SplatTrainingJob(
                id: "undersized-production-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("UndersizedSplatTrainingPackage", isDirectory: true)
        )) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            XCTAssertTrue(message.contains("requires at least 2 train split frames"), message)
            XCTAssertTrue(message.contains("requires at least 3 total frames"), message)
        }
    }

		    func testProductionDatasetTranscodesTIFFFramesToPNGForNerfstudioPreflight() throws {
	        let root = try makeTemporaryDirectory()
	        defer { try? FileManager.default.removeItem(at: root) }
	        let pythonURL = try python3URLOrSkip()

	        let imageURL = root.appendingPathComponent("source/frame.tiff")
	        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
	        try writeTinyTIFF(to: imageURL)
	        let manifest = SplatTrainingManifest(
	            id: "tiff-production-splat",
	            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
	            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/tiff-scene.ply"))
	        )
	        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
	        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
	        let package = try SplatTrainingPackageBuilder().writePackage(
	            job: SplatTrainingJob(
	                id: "tiff-production-splat-job",
	                manifest: manifest,
	                backend: AppleNativeTrainingBackend(),
	                mode: .productionGSplat
	            ),
	            manifestURL: manifestURL,
	            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
	        )

	        let transformsObject = try XCTUnwrap(
	            JSONSerialization.jsonObject(with: Data(contentsOf: try XCTUnwrap(package.nerfstudioTransformsURL))) as? [String: Any]
	        )
        let frames = try XCTUnwrap(transformsObject["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.map { $0["file_path"] as? String }, [
            "images/train/frame_000000.png",
            "images/train/frame_000001.png",
            "images/eval/frame_000002.png"
        ])
        let trainPNG = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("images/train/frame_000000.png")
        let secondTrainPNG = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("images/train/frame_000001.png")
        let evalPNG = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("images/eval/frame_000002.png")
        XCTAssertEqual(Array(try Data(contentsOf: trainPNG).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(Array(try Data(contentsOf: secondTrainPNG).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(Array(try Data(contentsOf: evalPNG).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let metadataURL = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("robot_scene_dataset_metadata.json")
        let metadata = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any]
        )
        XCTAssertEqual(metadata["transcodedImageCount"] as? Int, 3)

	        let process = Process()
	        process.executableURL = pythonURL
	        process.arguments = [
	            "python3",
	            try XCTUnwrap(package.productionRunnerURL).path,
	            "--preflight-only"
	        ]
	        let outputPipe = Pipe()
	        let errorPipe = Pipe()
	        process.standardOutput = outputPipe
	        process.standardError = errorPipe
	        try process.run()
	        process.waitUntilExit()
	        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
	        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
	        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")
	        let report = try XCTUnwrap(
	            JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        )
        let preflight = try XCTUnwrap(report["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["frame_count"] as? Int, 3)
        XCTAssertEqual(preflight["image_dimensions_checked"] as? Int, 3)
        XCTAssertEqual(preflight["invalid_frame_count"] as? Int, 0)
	    }

	    func testSplatTrainingPackageResolvesManifestRelativeIndexesAndOutputTarget() throws {
	        struct FrameIndexRecord: Decodable {
            var imageURL: URL
            var split: SplatTrainingFrameRole
        }
        struct DepthIndexRecord: Decodable {
            var depthURL: URL
            var confidenceURL: URL?
            var metadataURL: URL
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let captureRoot = root.appendingPathComponent("Capture.robotcapture", isDirectory: true)
        let imageURL = captureRoot.appendingPathComponent("rgb/frame_000000.png")
        let depthURL = captureRoot.appendingPathComponent("lidar/depth_000000.f32")
        let confidenceURL = captureRoot.appendingPathComponent("lidar/confidence_000000.bin")
        let metadataURL = captureRoot.appendingPathComponent("lidar/depth_000000.json")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: depthURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        try littleEndianFloat32Data([1.0]).write(to: depthURL)
        try Data([2]).write(to: confidenceURL)
        let metadata = CapturedLiDARDepthMetadata(
            timestamp: 0,
            width: 1,
            height: 1,
            confidenceFormat: "uint8-arkit-confidence-row-major",
            cameraPose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
            intrinsics: CameraIntrinsics(
                width: 1,
                height: 1,
                focalLengthPixels: SIMD2<Double>(1, 1),
                principalPointPixels: SIMD2<Double>(0.5, 0.5)
            ),
            depthURL: PackageURLTools.relativeURL(path: "lidar/depth_000000.f32"),
            confidenceURL: PackageURLTools.relativeURL(path: "lidar/confidence_000000.bin")
        )
        try JSONEncoder.robotVisionLabEncoder.encode(metadata).write(to: metadataURL)

        let manifest = SplatTrainingManifest(
            id: "relative-splat-package",
            imageFrames: [
                SplatTrainingFrame(
                    imageURL: PackageURLTools.relativeURL(path: "rgb/frame_000000.png"),
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0,
                    calibration: SplatFrameCalibration(
                        intrinsics: Self.intrinsics,
                        resolution: .hd1280x720,
                        trackingQuality: .normal
                    )
                )
            ],
            lidarFrames: [
                CapturedLiDARFrame(
                    depthURL: PackageURLTools.relativeURL(path: "lidar/depth_000000.f32"),
                    confidenceURL: PackageURLTools.relativeURL(path: "lidar/confidence_000000.bin"),
                    metadataURL: PackageURLTools.relativeURL(path: "lidar/depth_000000.json"),
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: PackageURLTools.relativeURL(path: "splats/relative-output.ply"))
        )
        let manifestURL = captureRoot.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)

        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 0,
                minTotalFrameCount: 1,
                requiresValidationSplit: false
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "relative-splat-package-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        XCTAssertEqual(package.outputURL.path, captureRoot.appendingPathComponent("splats/relative-output.ply").path)

        let frameLine = try XCTUnwrap(String(contentsOf: package.frameIndexURL, encoding: .utf8).split(whereSeparator: \.isNewline).first)
        let frameRecord = try JSONDecoder.robotVisionLabDecoder.decode(FrameIndexRecord.self, from: Data(frameLine.utf8))
        XCTAssertEqual(frameRecord.imageURL.path, imageURL.path)
        XCTAssertEqual(frameRecord.split, .train)

        let depthLine = try XCTUnwrap(String(contentsOf: try XCTUnwrap(package.depthPriorIndexURL), encoding: .utf8).split(whereSeparator: \.isNewline).first)
        let depthRecord = try JSONDecoder.robotVisionLabDecoder.decode(DepthIndexRecord.self, from: Data(depthLine.utf8))
        XCTAssertEqual(depthRecord.depthURL.path, depthURL.path)
        XCTAssertEqual(depthRecord.confidenceURL?.path, confidenceURL.path)
        XCTAssertEqual(depthRecord.metadataURL.path, metadataURL.path)
    }

    func testPreparedSplatTrainingPackagePreservesHoldoutSplitForProductionDataset() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appendingPathComponent("source/rgb", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let sourceFrames = try (0..<6).map { index -> CapturedRGBFrame in
            let imageURL = sourceRoot.appendingPathComponent(String(format: "frame_%06d.png", index))
            try Self.tinyPNG.write(to: imageURL)
            return CapturedRGBFrame(
                imageURL: imageURL,
                pose: Pose3D(position: SIMD3<Double>(Double(index) * 0.1, 0, -1)),
                timestamp: Double(index)
            )
        }
        let captureURL = root.appendingPathComponent("Capture.robotcapture", isDirectory: true)
        let plan = CapturePlan(
            id: "holdout-plan",
            captureModes: [.rgbVideo],
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720)
        )
        _ = try CaptureBundleExporter().writeBundle(
            scanSession: ScanSession(id: "holdout-capture", rgbFrames: sourceFrames),
            capturePlan: plan,
            to: captureURL
        )

        let imported = try RobotCaptureImporter().importPackage(at: captureURL)
        let prepared = try RobotCapturePreparer().prepare(
            importedCapture: imported,
            outputDirectory: root.appendingPathComponent("PreparedCapture", isDirectory: true),
            holdoutEveryNthFrame: 3,
            preparedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(prepared.split.trainingFrameIndexes, [0, 1, 3, 4])
        XCTAssertEqual(prepared.split.evaluationFrameIndexes, [2, 5])
        XCTAssertEqual(prepared.splatTrainingManifest.imageFrames.count, 6)
        XCTAssertEqual(prepared.splatTrainingManifest.imageFrames.filter { $0.split == .train }.count, 4)
        XCTAssertEqual(prepared.splatTrainingManifest.imageFrames.filter { $0.split == .validation }.count, 2)

        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 1,
                minTotalFrameCount: 2,
                requiresValidationSplit: true
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "holdout-production-job",
                manifest: prepared.splatTrainingManifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: prepared.report.splatTrainingManifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        let transformsObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: try XCTUnwrap(package.nerfstudioTransformsURL))) as? [String: Any]
        )
        let frames = try XCTUnwrap(transformsObject["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.filter { $0["split"] as? String == "train" }.count, 4)
        XCTAssertEqual(frames.filter { $0["split"] as? String == "validation" }.count, 2)
        XCTAssertTrue(frames.contains { $0["file_path"] as? String == "images/eval/frame_000002.png" })
        XCTAssertTrue(frames.contains { $0["file_path"] as? String == "images/eval/frame_000005.png" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(package.productionDatasetURL).appendingPathComponent("images/eval/frame_000002.png").path))
    }

    @MainActor
    func testWorkstationImportInvalidatesGeneratedSplatPackageState() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspaceURL = root.appendingPathComponent("Workspace", isDirectory: true)
        let firstCaptureURL = try writeWorkstationCapturePackage(root: root, id: "first-capture")
        let secondCaptureURL = try writeWorkstationCapturePackage(root: root, id: "second-capture")
        let model = WorkstationModel(state: WorkstationState(workspaceURL: workspaceURL))

        model.importCapture(at: firstCaptureURL)
        XCTAssertEqual(model.state.stage, .complete)
        model.prepareCapture(holdoutEveryNthFrame: 3)
        XCTAssertEqual(model.state.stage, .complete)
        model.writeSplatTrainingPackage()
        XCTAssertEqual(model.state.stage, .complete)
        XCTAssertNotNil(model.splatTrainingPackage)
        XCTAssertGreaterThan(model.state.artifacts.count, 1)

        model.importCapture(at: secondCaptureURL)

        XCTAssertEqual(model.state.stage, .complete)
        XCTAssertNil(model.splatTrainingPackage)
        XCTAssertNil(model.splatTrainingReport)
        XCTAssertNil(model.splatAsset)
        XCTAssertNil(model.state.activeSplatURL)
        XCTAssertNil(model.state.activeRobotSceneURL)
        XCTAssertTrue(model.state.artifacts.allSatisfy { $0.kind == "robotcapture-import" })
    }

    func testGeneratedProductionOptimizerRunnerExecutesTrainExportAndWritesSummary() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let lidarDirectory = root.appendingPathComponent("source/lidar", isDirectory: true)
        try FileManager.default.createDirectory(at: lidarDirectory, withIntermediateDirectories: true)
        let depthURL = lidarDirectory.appendingPathComponent("depth_000000.f32")
        let confidenceURL = lidarDirectory.appendingPathComponent("confidence_000000.bin")
        let metadataURL = lidarDirectory.appendingPathComponent("depth_000000.json")
        try littleEndianFloat32Data([1.25]).write(to: depthURL)
        try Data([2]).write(to: confidenceURL)
        let depthIntrinsics = CameraIntrinsics(
            width: 1,
            height: 1,
            focalLengthPixels: SIMD2<Double>(1, 1),
            principalPointPixels: SIMD2<Double>(0.5, 0.5)
        )
        let depthMetadata = CapturedLiDARDepthMetadata(
            timestamp: 0,
            width: 1,
            height: 1,
            confidenceFormat: "uint8-arkit-confidence-row-major",
            cameraPose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
            intrinsics: depthIntrinsics,
            depthURL: depthURL,
            confidenceURL: confidenceURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(depthMetadata).write(to: metadataURL)
        let manifest = SplatTrainingManifest(
            id: "runner-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            lidarFrames: [
                CapturedLiDARFrame(
                    depthURL: depthURL,
                    confidenceURL: confidenceURL,
                    metadataURL: metadataURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/scene.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 0,
                minTotalFrameCount: 1,
                requiresValidationSplit: false
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "runner-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .nativeAppleSilicon
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        let toolDirectory = root.appendingPathComponent("mock-tools", isDirectory: true)
        try writeMockNerfstudioTools(to: toolDirectory)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--backend", "nerfstudio",
            "--output", package.outputURL.path,
            "--max-num-iterations", "3",
            "--steps-per-save", "1",
            "--min-psnr", "30",
            "--min-ssim", "0.90",
            "--max-lpips", "0.20"
        ]
        process.environment = [
            "PATH": "\(toolDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: package.outputURL.path))
        let summaryURL = package.outputURL.deletingPathExtension().appendingPathExtension("production_training_summary.json")
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: summaryURL)) as? [String: Any]
        )
        XCTAssertEqual(summary["method"] as? String, "splatfacto")
        XCTAssertNotNil(summary["final_output_sha256"])
        XCTAssertNotNil(summary["eval_metrics_sha256"])
        let evalMetrics = try XCTUnwrap(summary["eval_metrics"] as? [String: Any])
        let evalResults = try XCTUnwrap(evalMetrics["results"] as? [String: Any])
        XCTAssertEqual(evalResults["psnr"] as? Double, 31.25)
        XCTAssertEqual(evalResults["ssim"] as? Double, 0.91)
        XCTAssertEqual(evalResults["lpips"] as? Double, 0.12)
        let qualityGates = try XCTUnwrap(summary["quality_gates"] as? [[String: Any]])
        XCTAssertEqual(qualityGates.count, 3)
        XCTAssertEqual(qualityGates.compactMap { $0["metric"] as? String }, ["psnr", "ssim", "lpips"])
        XCTAssertTrue(qualityGates.allSatisfy { $0["passed"] as? Bool == true })
        XCTAssertEqual((summary["quality_gate"] as? [String: Any])?["metric"] as? String, "psnr")
        let commands = try XCTUnwrap(summary["commands"] as? [[String]])
        XCTAssertEqual(commands.count, 3)
        XCTAssertTrue(commands[0].contains("--eval-mode"))
        XCTAssertTrue(commands[0].contains("filename"))
        XCTAssertTrue(commands[0].contains("--pipeline.datamanager.cache-images"))
        XCTAssertTrue(commands[0].contains("disk"))
        XCTAssertTrue(commands[0].contains("nerfstudio-data"))
        XCTAssertTrue(commands[0].contains("--load-3D-points"))
        let dataparserIndex = try XCTUnwrap(commands[0].firstIndex(of: "nerfstudio-data"))
        let dataIndex = try XCTUnwrap(commands[0].firstIndex(of: "--data"))
        let evalModeIndex = try XCTUnwrap(commands[0].firstIndex(of: "--eval-mode"))
        let loadPointsIndex = try XCTUnwrap(commands[0].firstIndex(of: "--load-3D-points"))
        XCTAssertLessThan(dataparserIndex, dataIndex)
        XCTAssertLessThan(dataparserIndex, evalModeIndex)
        XCTAssertLessThan(dataparserIndex, loadPointsIndex)
        XCTAssertTrue(commands[1][0].contains("ns-eval"))
        XCTAssertTrue(commands[1].contains("--output-path"))
        XCTAssertTrue(commands[2][0].contains("ns-export"))
        let exportedValidation = try XCTUnwrap(summary["exported_ply_validation"] as? [String: Any])
        XCTAssertEqual(exportedValidation["vertex_count"] as? Int, 1)
        XCTAssertEqual(exportedValidation["color_model"] as? String, "rgb")
        let finalOutputValidation = try XCTUnwrap(summary["final_output_validation"] as? [String: Any])
        XCTAssertEqual(finalOutputValidation["vertex_count"] as? Int, 1)
        XCTAssertEqual(finalOutputValidation["color_model"] as? String, "rgb")
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["frame_count"] as? Int, 3)
        XCTAssertEqual(preflight["missing_file_count"] as? Int, 0)
        XCTAssertEqual(preflight["image_dimensions_checked"] as? Int, 3)
        XCTAssertEqual(preflight["validation_split_required"] as? Bool, true)
        let minimums = try XCTUnwrap(preflight["minimums"] as? [String: Any])
        XCTAssertEqual(minimums["train_frames"] as? Int, 2)
        XCTAssertEqual(minimums["eval_frames"] as? Int, 1)
        XCTAssertEqual(minimums["total_frames"] as? Int, 3)
        let splitCounts = try XCTUnwrap(preflight["split_counts"] as? [String: Any])
        XCTAssertEqual(splitCounts["train"] as? Int, 2)
        XCTAssertEqual(splitCounts["validation"] as? Int, 1)
        XCTAssertNotNil(preflight["point_cloud"])
        XCTAssertGreaterThan(preflight["point_cloud_bytes"] as? Int ?? 0, 0)
        let preflightURL = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("dataset_preflight.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preflightURL.path))

        let pointCloudURL = try XCTUnwrap(package.productionPointCloudURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pointCloudURL.path))
        let transformsObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: try XCTUnwrap(package.nerfstudioTransformsURL))) as? [String: Any]
        )
        XCTAssertEqual(transformsObject["ply_file_path"] as? String, "sparse_pc.ply")

        let optimizedCloud = try GaussianSplatCloudLoader().load(url: package.outputURL)
        XCTAssertEqual(optimizedCloud.splats.count, 1)
    }

    func testProductionOptimizerRunnerUsesBrushBackendByDefault() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "brush-runner-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/brush-scene.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder().writePackage(
            job: SplatTrainingJob(
                id: "brush-runner-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        let toolDirectory = root.appendingPathComponent("mock-tools", isDirectory: true)
        try writeMockBrushTool(to: toolDirectory)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--output", package.outputURL.path,
            "--max-num-iterations", "3",
            "--min-psnr", "30",
            "--min-ssim", "0.90"
        ]
        process.environment = [
            "PATH": "\(toolDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")

        let summaryURL = package.outputURL.deletingPathExtension().appendingPathExtension("production_training_summary.json")
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: summaryURL)) as? [String: Any]
        )
        XCTAssertEqual(summary["backend"] as? String, "brush")
        XCTAssertEqual(summary["trainer"] as? String, "brush")
        XCTAssertEqual(summary["method"] as? String, "brush")
        XCTAssertNotNil(summary["final_output_sha256"])
        XCTAssertNotNil(summary["eval_metrics_sha256"])
        let evalMetrics = try XCTUnwrap(summary["eval_metrics"] as? [String: Any])
        let evalResults = try XCTUnwrap(evalMetrics["results"] as? [String: Any])
        XCTAssertEqual(evalResults["psnr"] as? Double, 32.5)
        XCTAssertEqual(evalResults["ssim"] as? Double, 0.94)
        let qualityGates = try XCTUnwrap(summary["quality_gates"] as? [[String: Any]])
        XCTAssertEqual(qualityGates.compactMap { $0["metric"] as? String }, ["psnr", "ssim"])
        XCTAssertTrue(qualityGates.allSatisfy { $0["passed"] as? Bool == true })
        let commands = try XCTUnwrap(summary["commands"] as? [[String]])
        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0][0].contains("brush-cli"))
        XCTAssertTrue(commands[0].contains("--with-viewer=false"))
        XCTAssertTrue(commands[0].contains("--total-train-iters"))

        let brushPreflight = try XCTUnwrap(summary["brush_preflight"] as? [String: Any])
        XCTAssertEqual(brushPreflight["train_frame_count"] as? Int, 2)
        XCTAssertEqual(brushPreflight["eval_frame_count"] as? Int, 1)
        let brushDatasetURL = try XCTUnwrap(package.brushDatasetURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: brushDatasetURL.appendingPathComponent("transforms_train.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: brushDatasetURL.appendingPathComponent("transforms_val.json").path))

        let optimizedCloud = try GaussianSplatCloudLoader().load(url: package.outputURL)
        XCTAssertEqual(optimizedCloud.splats.count, 1)
    }

    func testProductionOptimizerRunnerFailsWhenQualityGateDoesNotPass() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "quality-gated-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/quality-gated.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(productionRequirements: .skipEvaluation).writePackage(
            job: SplatTrainingJob(
                id: "quality-gated-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        let toolDirectory = root.appendingPathComponent("mock-tools", isDirectory: true)
        try writeMockNerfstudioTools(to: toolDirectory)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--backend", "nerfstudio",
            "--output", package.outputURL.path,
            "--max-num-iterations", "3",
            "--steps-per-save", "1",
            "--max-lpips", "0.01"
        ]
        process.environment = [
            "PATH": "\(toolDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("LPIPS quality gate failed"), stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.outputURL.path))
    }

    func testProductionOptimizerRunnerIgnoresStaleConfigAndExportArtifacts() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "fresh-artifact-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/fresh-artifact.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 1,
                minTotalFrameCount: 2,
                requiresValidationSplit: true
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "fresh-artifact-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        let staleConfigURL = try XCTUnwrap(package.checkpointDirectoryURL)
            .appendingPathComponent("stale-run/config.yml")
        try FileManager.default.createDirectory(at: staleConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("method: stale\n".utf8).write(to: staleConfigURL)
        let staleExportURL = try XCTUnwrap(package.exportedModelDirectoryURL)
            .appendingPathComponent("stale-export.ply")
        try FileManager.default.createDirectory(at: staleExportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.singlePointGaussianPLY.write(to: staleExportURL, atomically: true, encoding: .utf8)

        let toolDirectory = root.appendingPathComponent("mock-tools", isDirectory: true)
        try writeMockNerfstudioTools(to: toolDirectory)
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--backend", "nerfstudio",
            "--output", package.outputURL.path,
            "--max-num-iterations", "3",
            "--steps-per-save", "1"
        ]
        process.environment = [
            "PATH": "\(toolDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")

        let summaryURL = package.outputURL.deletingPathExtension().appendingPathExtension("production_training_summary.json")
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: summaryURL)) as? [String: Any]
        )
        let configPath = try XCTUnwrap(summary["config"] as? String)
        let exportedPath = try XCTUnwrap(summary["exported_ply"] as? String)
        XCTAssertTrue(configPath.hasSuffix("mock-run/config.yml"), configPath)
        XCTAssertFalse(configPath.hasSuffix("stale-run/config.yml"), configPath)
        XCTAssertTrue(exportedPath.hasSuffix("mock-export.ply"), exportedPath)
        XCTAssertFalse(exportedPath.hasSuffix("stale-export.ply"), exportedPath)
    }

    func testProductionOptimizerRunnerRejectsStaleEvalMetricsWhenEvalDoesNotRewriteOutput() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "stale-eval-metrics-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/stale-eval-metrics.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 0,
                minTotalFrameCount: 1,
                requiresValidationSplit: false
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "stale-eval-metrics-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        let staleEvalURL = root.appendingPathComponent("stale-eval-metrics.json")
        try Data(#"{"results":{"psnr":99,"ssim":1,"lpips":0},"stale":true}"#.utf8).write(to: staleEvalURL)
        let toolDirectory = root.appendingPathComponent("mock-tools", isDirectory: true)
        try writeMockNerfstudioTools(to: toolDirectory, writesEvalMetrics: false)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--backend", "nerfstudio",
            "--output", package.outputURL.path,
            "--eval-output", staleEvalURL.path,
            "--max-num-iterations", "3",
            "--steps-per-save", "1"
        ]
        process.environment = [
            "PATH": "\(toolDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("did not replace stale metrics JSON"), stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.outputURL.path))
    }

    func testProductionOptimizerRunnerRejectsInvalidGaussianPLYExport() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "invalid-export-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/invalid-export.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder().writePackage(
            job: SplatTrainingJob(
                id: "invalid-export-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        let toolDirectory = root.appendingPathComponent("mock-tools", isDirectory: true)
        try writeMockNerfstudioTools(to: toolDirectory, exportPLY: Self.positionOnlyPLY)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--backend", "nerfstudio",
            "--output", package.outputURL.path,
            "--max-num-iterations", "3",
            "--steps-per-save", "1"
        ]
        process.environment = [
            "PATH": "\(toolDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("Gaussian PLY export is missing required properties"), stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.outputURL.path))
    }

    func testProductionOptimizerRunnerRejectsQualityGateWhenEvalIsSkippedWithoutMetrics() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "skip-eval-gate-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL, includeValidation: false),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/skip-eval-gate.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(productionRequirements: .skipEvaluation).writePackage(
            job: SplatTrainingJob(
                id: "skip-eval-gate-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--skip-train",
            "--skip-eval",
            "--skip-export",
            "--min-psnr", "30"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("Quality gates require eval metrics"), stderr)
        XCTAssertTrue(stderr.contains("--skip-eval"), stderr)
    }

    func testProductionOptimizerRunnerCanSummarizeExistingOutputWhenExportSkipped() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "reuse-existing-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL, includeValidation: false),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/existing.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(productionRequirements: .skipEvaluation).writePackage(
            job: SplatTrainingJob(
                id: "reuse-existing-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: package.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.singlePointGaussianPLY.write(to: package.outputURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--skip-train",
            "--skip-eval",
            "--skip-export",
            "--output", package.outputURL.path
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")

        let summaryURL = package.outputURL.deletingPathExtension().appendingPathExtension("production_training_summary.json")
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: summaryURL)) as? [String: Any]
        )
        XCTAssertNil(summary["config"] as? String)
        XCTAssertEqual(summary["export_reused"] as? Bool, true)
        let normalizePath: (String) -> String = { path in
            path.replacingOccurrences(of: "/private/var/", with: "/var/")
        }
        let outputPath = normalizePath(package.outputURL.path)
        XCTAssertEqual(normalizePath(try XCTUnwrap(summary["exported_ply"] as? String)), outputPath)
        XCTAssertEqual(normalizePath(try XCTUnwrap(summary["final_output"] as? String)), outputPath)
        XCTAssertEqual((summary["commands"] as? [[String]])?.count, 0)

        let optimizedCloud = try GaussianSplatCloudLoader().load(url: package.outputURL)
        XCTAssertEqual(optimizedCloud.splats.count, 1)
    }

    func testProductionOptimizerRunnerPreflightOnlyAcceptsForwardedTrainArguments() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "preflight-production-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/preflight.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder().writePackage(
            job: SplatTrainingJob(
                id: "preflight-production-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--preflight-only",
            "--print-commands",
            "--extra-brush-arg=--max-resolution",
            "--extra-brush-arg=1024"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "stdout:\n\(stdout)\nstderr:\n\(stderr)")

        let report = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        )
        let preflight = try XCTUnwrap(report["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["frame_count"] as? Int, 3)
        XCTAssertEqual(preflight["missing_file_count"] as? Int, 0)
        XCTAssertEqual(preflight["image_dimensions_checked"] as? Int, 3)
        let minimums = try XCTUnwrap(preflight["minimums"] as? [String: Any])
        XCTAssertEqual(minimums["train_frames"] as? Int, 2)
        XCTAssertEqual(minimums["eval_frames"] as? Int, 1)
        XCTAssertEqual(minimums["total_frames"] as? Int, 3)
        XCTAssertEqual((report["commands"] as? [[String]])?.count, 0)
        XCTAssertNotNil(report["tools"] as? [String: Any])
        XCTAssertNotNil(report["missing_tools"] as? [String])
        let preflightURL = try XCTUnwrap(package.productionDatasetURL)
            .appendingPathComponent("dataset_preflight.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preflightURL.path))
    }

    func testProductionOptimizerRunnerPreflightRejectsMissingValidationSplitWhenEvalRuns() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "missing-validation-splat",
            imageFrames: tinyOptimizerFrames(imageURL: imageURL, includeValidation: false),
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/missing-validation.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(productionRequirements: .skipEvaluation).writePackage(
            job: SplatTrainingJob(
                id: "missing-validation-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--preflight-only"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("validation/eval split frames"), stderr)
    }

    func testProductionOptimizerRunnerPreflightRejectsInsufficientTrainingFrames() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "insufficient-train-splat",
            imageFrames: [
                SplatTrainingFrame(
                    imageURL: imageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0,
                    calibration: Self.tinyImageCalibration,
                    split: .train
                ),
                SplatTrainingFrame(
                    imageURL: imageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, -0.05)),
                    timestamp: 1,
                    calibration: Self.tinyImageCalibration,
                    split: .validation
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/insufficient-train.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 1,
                minTotalFrameCount: 2,
                requiresValidationSplit: true
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "insufficient-train-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--preflight-only"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("production preflight requires at least 2"), stderr)
    }

    func testProductionOptimizerRunnerPreflightRejectsImageDimensionMismatch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pythonURL = try python3URLOrSkip()

        let imageURL = root.appendingPathComponent("source/frame.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.tinyPNG.write(to: imageURL)
        let manifest = SplatTrainingManifest(
            id: "dimension-mismatch-splat",
            imageFrames: [
                SplatTrainingFrame(
                    imageURL: imageURL,
                    pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
                    timestamp: 0,
                    calibration: SplatFrameCalibration(
                        intrinsics: Self.intrinsics,
                        resolution: .hd1280x720,
                        trackingQuality: .normal
                    ),
                    split: .train
                )
            ],
            expectedOutput: SplatTrainingOutput(targetURL: root.appendingPathComponent("optimized/dimension-mismatch.ply"))
        )
        let manifestURL = root.appendingPathComponent("splat_training_manifest.json")
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let package = try SplatTrainingPackageBuilder(
            productionRequirements: ProductionSplatDatasetRequirements(
                minTrainingFrameCount: 1,
                minValidationFrameCount: 0,
                minTotalFrameCount: 1,
                requiresValidationSplit: false
            )
        ).writePackage(
            job: SplatTrainingJob(
                id: "dimension-mismatch-splat-job",
                manifest: manifest,
                backend: AppleNativeTrainingBackend(),
                mode: .productionGSplat
            ),
            manifestURL: manifestURL,
            outputDirectory: root.appendingPathComponent("SplatTrainingPackage", isDirectory: true)
        )

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [
            "python3",
            try XCTUnwrap(package.productionRunnerURL).path,
            "--preflight-only",
            "--skip-eval"
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(stderr.contains("image dimensions 1x1 do not match camera fields 1280x720"), stderr)
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

    private func python3URLOrSkip() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw XCTSkip("python3 is not available for generated runner verification.")
        }
        guard process.terminationStatus == 0 else {
            throw XCTSkip("python3 is not available for generated runner verification.")
	        }
	        return URL(fileURLWithPath: "/usr/bin/env")
	    }

	    private func writeTinyTIFF(to url: URL) throws {
	        let pixels = Data([255, 0, 0, 255])
	        guard let provider = CGDataProvider(data: pixels as CFData) else {
	            throw NSError(domain: "PipelineGateTests", code: 1)
	        }
	        guard let image = CGImage(
	            width: 1,
	            height: 1,
	            bitsPerComponent: 8,
	            bitsPerPixel: 32,
	            bytesPerRow: 4,
	            space: CGColorSpaceCreateDeviceRGB(),
	            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
	            provider: provider,
	            decode: nil,
	            shouldInterpolate: false,
	            intent: .defaultIntent
	        ) else {
	            throw NSError(domain: "PipelineGateTests", code: 2)
	        }
	        guard let destination = CGImageDestinationCreateWithURL(
	            url as CFURL,
	            UTType.tiff.identifier as CFString,
	            1,
	            nil
	        ) else {
	            throw NSError(domain: "PipelineGateTests", code: 3)
	        }
	        CGImageDestinationAddImage(destination, image, nil)
	        guard CGImageDestinationFinalize(destination) else {
	            throw NSError(domain: "PipelineGateTests", code: 4)
	        }
	    }

	    private func tinyOptimizerFrames(imageURL: URL, includeValidation: Bool = true) -> [SplatTrainingFrame] {
        let firstTrainFrame = SplatTrainingFrame(
            imageURL: imageURL,
            pose: Pose3D(position: SIMD3<Double>(0, 0, 0)),
            timestamp: 0,
            calibration: Self.tinyImageCalibration,
            split: .train
        )
        let secondTrainFrame = SplatTrainingFrame(
            imageURL: imageURL,
            pose: Pose3D(position: SIMD3<Double>(0.05, 0, -0.05)),
            timestamp: 0.5,
            calibration: Self.tinyImageCalibration,
            split: .train
        )
        guard includeValidation else {
            return [firstTrainFrame, secondTrainFrame]
        }
        return [
            firstTrainFrame,
            secondTrainFrame,
            SplatTrainingFrame(
                imageURL: imageURL,
                pose: Pose3D(position: SIMD3<Double>(0, 0, -0.05)),
                timestamp: 1,
                calibration: Self.tinyImageCalibration,
                split: .validation
            )
        ]
    }

    private func writeMockNerfstudioTools(
        to directory: URL,
        writesEvalMetrics: Bool = true,
        exportPLY: String? = nil
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let trainURL = directory.appendingPathComponent("ns-train")
        let evalURL = directory.appendingPathComponent("ns-eval")
        let exportURL = directory.appendingPathComponent("ns-export")
        let exportPLY = exportPLY ?? Self.singlePointGaussianPLY
        try """
        #!/usr/bin/env python3
        import pathlib
        import sys
        args = sys.argv[1:]
        output_dir = pathlib.Path(args[args.index("--output-dir") + 1])
        run_dir = output_dir / "mock-run"
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / "config.yml").write_text("method: mock-splatfacto\\n")

        """.write(to: trainURL, atomically: true, encoding: .utf8)
        if writesEvalMetrics {
            try """
            #!/usr/bin/env python3
            import json
            import pathlib
            import sys
            args = sys.argv[1:]
            output_path = pathlib.Path(args[args.index("--output-path") + 1])
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(json.dumps({
                "results": {
                    "psnr": 31.25,
                    "ssim": 0.91,
                    "lpips": 0.12
                },
                "mock": True
            }))

            """.write(to: evalURL, atomically: true, encoding: .utf8)
        } else {
            try """
            #!/usr/bin/env python3
            import sys
            _ = sys.argv[1:]

            """.write(to: evalURL, atomically: true, encoding: .utf8)
        }
        try """
        #!/usr/bin/env python3
        import pathlib
        import sys
        args = sys.argv[1:]
        output_dir = pathlib.Path(args[args.index("--output-dir") + 1])
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "mock-export.ply").write_text(\(String(reflecting: exportPLY)))

        """.write(to: exportURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trainURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evalURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exportURL.path)
    }

    private func writeMockBrushTool(to directory: URL, exportPLY: String? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let brushURL = directory.appendingPathComponent("brush-cli")
        let exportPLY = exportPLY ?? Self.singlePointGaussianPLY
        try """
        #!/usr/bin/env python3
        import pathlib
        import sys

        args = sys.argv[1:]
        dataset = pathlib.Path(args[0])
        assert (dataset / "transforms_train.json").exists(), "missing transforms_train.json"
        assert (dataset / "transforms_val.json").exists(), "missing transforms_val.json"
        export_path = pathlib.Path(args[args.index("--export-path") + 1])
        export_name = args[args.index("--export-name") + 1]
        export_path.mkdir(parents=True, exist_ok=True)
        (export_path / export_name).write_text('''\(exportPLY)''')
        print("Eval iter 3: PSNR 32.5, ssim 0.94")

        """.write(to: brushURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brushURL.path)
    }

    private func littleEndianFloat32Data(_ values: [Float32]) -> Data {
        var data = Data()
        for value in values {
            var littleEndian = value.bitPattern.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        return data
    }

    private static let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8z8BQDwAFgwJ/lwOfGAAAAABJRU5ErkJggg==")!

    private static let singlePointGaussianPLY = """
    ply
    format ascii 1.0
    element vertex 1
    property float x
    property float y
    property float z
    property uchar red
    property uchar green
    property uchar blue
    property float opacity
    property float scale_0
    property float scale_1
    property float scale_2
    property float rot_0
    property float rot_1
    property float rot_2
    property float rot_3
    end_header
    0 0 0 255 0 0 0 -3 -3 -3 1 0 0 0

    """

    private static let positionOnlyPLY = """
    ply
    format ascii 1.0
    element vertex 1
    property float x
    property float y
    property float z
    end_header
    0 0 0

    """

    private static let intrinsics = CameraIntrinsics(
        width: 1280,
        height: 720,
        focalLengthPixels: SIMD2<Double>(900, 900),
        principalPointPixels: SIMD2<Double>(640, 360)
    )

    private static let tinyImageCalibration = SplatFrameCalibration(
        intrinsics: CameraIntrinsics(
            width: 1,
            height: 1,
            focalLengthPixels: SIMD2<Double>(1, 1),
            principalPointPixels: SIMD2<Double>(0.5, 0.5)
        ),
        resolution: Resolution(width: 1, height: 1),
        trackingQuality: .normal
    )

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RobotVisionLabCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeWorkstationCapturePackage(root: URL, id: String) throws -> URL {
        let sourceRoot = root.appendingPathComponent("\(id)-source/rgb", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let frames = try (0..<6).map { index -> CapturedRGBFrame in
            let imageURL = sourceRoot.appendingPathComponent(String(format: "frame_%06d.png", index))
            try Self.tinyPNG.write(to: imageURL)
            return CapturedRGBFrame(
                imageURL: imageURL,
                pose: Pose3D(position: SIMD3<Double>(Double(index) * 0.1, 0, -1)),
                timestamp: Double(index)
            )
        }
        let captureURL = root.appendingPathComponent("\(id).robotcapture", isDirectory: true)
        let plan = CapturePlan(
            id: "\(id)-plan",
            captureModes: [.rgbVideo],
            rgbVideo: RGBVideoOptions(targetFPS: 30, targetResolution: .hd1280x720)
        )
        _ = try CaptureBundleExporter().writeBundle(
            scanSession: ScanSession(id: id, rgbFrames: frames),
            capturePlan: plan,
            to: captureURL
        )
        return captureURL
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
