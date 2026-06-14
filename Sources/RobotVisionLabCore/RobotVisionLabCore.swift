import Foundation
import simd

public struct ScanSession: Codable, Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public var worldUnit: WorldUnit
    public var rgbFrames: [CapturedRGBFrame]
    public var lidarFrames: [CapturedLiDARFrame]
    public var roomPlanModelURL: URL?
    public var objectCaptureAssetURLs: [URL]

    public init(
        id: String,
        createdAt: Date = Date(),
        worldUnit: WorldUnit = .meters,
        rgbFrames: [CapturedRGBFrame] = [],
        lidarFrames: [CapturedLiDARFrame] = [],
        roomPlanModelURL: URL? = nil,
        objectCaptureAssetURLs: [URL] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.worldUnit = worldUnit
        self.rgbFrames = rgbFrames
        self.lidarFrames = lidarFrames
        self.roomPlanModelURL = roomPlanModelURL
        self.objectCaptureAssetURLs = objectCaptureAssetURLs
    }
}

public enum WorldUnit: String, Codable, Equatable, Sendable {
    case meters
}

public struct CapturedRGBFrame: Codable, Equatable, Sendable {
    public var imageURL: URL
    public var pose: Pose3D
    public var timestamp: TimeInterval

    public init(imageURL: URL, pose: Pose3D, timestamp: TimeInterval) {
        self.imageURL = imageURL
        self.pose = pose
        self.timestamp = timestamp
    }
}

public struct CapturedLiDARFrame: Codable, Equatable, Sendable {
    public var depthURL: URL
    public var confidenceURL: URL?
    public var pose: Pose3D
    public var timestamp: TimeInterval

    public init(depthURL: URL, confidenceURL: URL? = nil, pose: Pose3D, timestamp: TimeInterval) {
        self.depthURL = depthURL
        self.confidenceURL = confidenceURL
        self.pose = pose
        self.timestamp = timestamp
    }
}

public struct GaussianSplatScene: Codable, Equatable, Sendable {
    public var id: String
    public var source: SplatSource
    public var alignmentTransform: Transform3D
    public var bounds: AxisAlignedBounds
    public var roomPlanModelURL: URL?

    public init(
        id: String,
        source: SplatSource,
        alignmentTransform: Transform3D = .identity,
        bounds: AxisAlignedBounds,
        roomPlanModelURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.alignmentTransform = alignmentTransform
        self.bounds = bounds
        self.roomPlanModelURL = roomPlanModelURL
    }
}

public enum SplatSource: Codable, Equatable, Sendable {
    case importedPLY(URL)
    case importedSplat(URL)
    case trainingOutput(URL)
}

public struct RobotCameraRig: Codable, Equatable, Sendable {
    public var name: String
    public var mountHeightMeters: Double
    public var intrinsics: CameraIntrinsics
    public var lens: LensModel
    public var bodyToCamera: Transform3D

    public init(
        name: String,
        mountHeightMeters: Double,
        intrinsics: CameraIntrinsics,
        lens: LensModel = .pinhole,
        bodyToCamera: Transform3D = .identity
    ) {
        self.name = name
        self.mountHeightMeters = mountHeightMeters
        self.intrinsics = intrinsics
        self.lens = lens
        self.bodyToCamera = bodyToCamera
    }
}

public struct CameraIntrinsics: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var focalLengthPixels: SIMD2<Double>
    public var principalPointPixels: SIMD2<Double>

    public init(width: Int, height: Int, focalLengthPixels: SIMD2<Double>, principalPointPixels: SIMD2<Double>) {
        self.width = width
        self.height = height
        self.focalLengthPixels = focalLengthPixels
        self.principalPointPixels = principalPointPixels
    }

    public static func fromHorizontalFOV(width: Int, height: Int, horizontalFOVDegrees: Double) -> Self {
        let focal = Double(width) / (2.0 * tan(horizontalFOVDegrees * .pi / 360.0))
        return Self(
            width: width,
            height: height,
            focalLengthPixels: SIMD2(focal, focal),
            principalPointPixels: SIMD2(Double(width) / 2.0, Double(height) / 2.0)
        )
    }
}

public enum LensModel: Codable, Equatable, Sendable {
    case pinhole
    case fisheye(equivalentFOVDegrees: Double)
}

public struct RobotPath: Codable, Equatable, Sendable {
    public var keyframes: [RobotPathKeyframe]

    public init(keyframes: [RobotPathKeyframe]) {
        self.keyframes = keyframes.sorted { $0.timestamp < $1.timestamp }
    }
}

public struct RobotPathKeyframe: Codable, Equatable, Sendable {
    public var timestamp: TimeInterval
    public var pose: Pose3D
    public var navigationTarget: NavigationTarget?

    public init(timestamp: TimeInterval, pose: Pose3D, navigationTarget: NavigationTarget? = nil) {
        self.timestamp = timestamp
        self.pose = pose
        self.navigationTarget = navigationTarget
    }
}

public struct NavigationTarget: Codable, Equatable, Sendable {
    public var label: String
    public var position: SIMD3<Double>

    public init(label: String, position: SIMD3<Double>) {
        self.label = label
        self.position = position
    }
}

public struct DatasetRecipe: Codable, Equatable, Sendable {
    public var id: String
    public var scene: GaussianSplatScene
    public var cameraRig: RobotCameraRig
    public var path: RobotPath
    public var requestedProducts: Set<RenderProduct>
    public var augmentations: [FrameAugmentation]
    public var labelSources: [LabelSource]

    public init(
        id: String,
        scene: GaussianSplatScene,
        cameraRig: RobotCameraRig,
        path: RobotPath,
        requestedProducts: Set<RenderProduct> = [.rgb, .pose],
        augmentations: [FrameAugmentation] = [],
        labelSources: [LabelSource] = []
    ) {
        self.id = id
        self.scene = scene
        self.cameraRig = cameraRig
        self.path = path
        self.requestedProducts = requestedProducts
        self.augmentations = augmentations
        self.labelSources = labelSources
    }
}

public enum RenderProduct: String, Codable, CaseIterable, Sendable {
    case rgb
    case depth
    case visibility
    case pose
    case segmentation
    case obstacleMask
    case lidarScan
    case failureLabels
    case navigationTarget
}

public enum FrameAugmentation: Codable, Equatable, Sendable {
    case exposureEV(Double)
    case gaussianNoise(sigma: Double)
    case motionBlur(samples: Int, shutterSeconds: Double)
    case compressionJPEG(quality: Double)
    case cameraHeightJitterMeters(Double)
    case yawJitterDegrees(Double)
}

public enum LabelSource: Codable, Equatable, Sendable {
    case roomPlanGeometry(URL)
    case objectCaptureMesh(URL)
    case manualAnnotations(URL)
}

public struct DatasetManifest: Codable, Equatable, Sendable {
    public var recipeID: String
    public var generatedAt: Date
    public var scene: GaussianSplatScene
    public var cameraRig: RobotCameraRig
    public var frames: [DatasetFrame]

    public init(recipeID: String, generatedAt: Date = Date(), scene: GaussianSplatScene, cameraRig: RobotCameraRig, frames: [DatasetFrame]) {
        self.recipeID = recipeID
        self.generatedAt = generatedAt
        self.scene = scene
        self.cameraRig = cameraRig
        self.frames = frames
    }
}

public struct DatasetFrame: Codable, Equatable, Sendable {
    public var index: Int
    public var timestamp: TimeInterval
    public var cameraPose: Pose3D
    public var navigationTarget: NavigationTarget?
    public var products: [FrameProduct]
    public var augmentations: [FrameAugmentation]
    public var labelSources: [LabelSource]

    public init(
        index: Int,
        timestamp: TimeInterval,
        cameraPose: Pose3D,
        navigationTarget: NavigationTarget?,
        products: [FrameProduct],
        augmentations: [FrameAugmentation],
        labelSources: [LabelSource]
    ) {
        self.index = index
        self.timestamp = timestamp
        self.cameraPose = cameraPose
        self.navigationTarget = navigationTarget
        self.products = products
        self.augmentations = augmentations
        self.labelSources = labelSources
    }

    public func productURL(for product: RenderProduct) -> URL? {
        products.first { $0.product == product }?.url
    }
}

public struct FrameProduct: Codable, Equatable, Sendable {
    public var product: RenderProduct
    public var url: URL

    public init(product: RenderProduct, url: URL) {
        self.product = product
        self.url = url
    }
}

public struct DatasetGenerator: Sendable {
    public init() {}

    public func makeManifest(recipe: DatasetRecipe, outputDirectory: URL, generatedAt: Date = Date()) -> DatasetManifest {
        let frames = recipe.path.keyframes.enumerated().map { index, keyframe in
            DatasetFrame(
                index: index,
                timestamp: keyframe.timestamp,
                cameraPose: keyframe.pose.applying(recipe.cameraRig.bodyToCamera),
                navigationTarget: keyframe.navigationTarget,
                products: productURLs(for: recipe.requestedProducts, frameIndex: index, outputDirectory: outputDirectory),
                augmentations: recipe.augmentations,
                labelSources: recipe.labelSources
            )
        }

        return DatasetManifest(
            recipeID: recipe.id,
            generatedAt: generatedAt,
            scene: recipe.scene,
            cameraRig: recipe.cameraRig,
            frames: frames
        )
    }

    private func productURLs(for products: Set<RenderProduct>, frameIndex: Int, outputDirectory: URL) -> [FrameProduct] {
        products.sorted { $0.rawValue < $1.rawValue }.map { product in
            let filename = String(format: "frame_%06d.%@", frameIndex, product.fileExtension)
            return FrameProduct(
                product: product,
                url: outputDirectory.appendingPathComponent(product.rawValue).appendingPathComponent(filename)
            )
        }
    }
}

public struct DatasetExporter: Sendable {
    public init() {}

    public func writeManifestAndLabels(_ manifest: DatasetManifest, to outputDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder.robotVisionLabEncoder
        try encoder.encode(manifest).write(to: outputDirectory.appendingPathComponent("dataset.json"))

        for product in RenderProduct.allCases {
            let productDirectory = outputDirectory.appendingPathComponent(product.rawValue, isDirectory: true)
            if fileManager.fileExists(atPath: productDirectory.path) {
                try fileManager.removeItem(at: productDirectory)
            }
            try fileManager.createDirectory(at: productDirectory, withIntermediateDirectories: true)
        }

        for frame in manifest.frames {
            try writePose(frame, encoder: encoder, outputDirectory: outputDirectory)
            if frame.navigationTarget != nil {
                try writeNavigationTarget(frame, encoder: encoder, outputDirectory: outputDirectory)
            }
        }
    }

    public func renderFrames(
        _ manifest: DatasetManifest,
        to outputDirectory: URL,
        renderer: PreviewSyntheticRenderer
    ) throws {
        for frame in manifest.frames {
            try renderer.renderSynchronously(
                frame: frame,
                scene: manifest.scene,
                cameraRig: manifest.cameraRig,
                outputDirectory: outputDirectory
            )
        }
    }

    public func writeRenderedFailureLabels(_ manifest: DatasetManifest, to outputDirectory: URL) throws -> [RenderedFailureLabelReport] {
        try RenderedFailureLabeler().writeReports(for: manifest, to: outputDirectory)
    }

    public func writeRenderedLiDARScans(_ manifest: DatasetManifest, to outputDirectory: URL) throws -> [RenderedLiDARScanReport] {
        try RenderedLiDARSimulator().writeReports(for: manifest, to: outputDirectory)
    }

    private func writePose(_ frame: DatasetFrame, encoder: JSONEncoder, outputDirectory: URL) throws {
        let poseURL = outputDirectory
            .appendingPathComponent(RenderProduct.pose.rawValue, isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.json", frame.index))
        let payload = PoseLabel(frameIndex: frame.index, timestamp: frame.timestamp, cameraPose: frame.cameraPose)
        try encoder.encode(payload).write(to: poseURL)
    }

    private func writeNavigationTarget(_ frame: DatasetFrame, encoder: JSONEncoder, outputDirectory: URL) throws {
        let targetURL = outputDirectory
            .appendingPathComponent(RenderProduct.navigationTarget.rawValue, isDirectory: true)
            .appendingPathComponent(String(format: "frame_%06d.json", frame.index))
        let payload = NavigationTargetLabel(
            frameIndex: frame.index,
            timestamp: frame.timestamp,
            target: frame.navigationTarget
        )
        try encoder.encode(payload).write(to: targetURL)
    }
}

public struct PoseLabel: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var timestamp: TimeInterval
    public var cameraPose: Pose3D

    public init(frameIndex: Int, timestamp: TimeInterval, cameraPose: Pose3D) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.cameraPose = cameraPose
    }
}

public struct NavigationTargetLabel: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var timestamp: TimeInterval
    public var target: NavigationTarget?

    public init(frameIndex: Int, timestamp: TimeInterval, target: NavigationTarget?) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.target = target
    }
}

public protocol SplatRenderer: Sendable {
    func render(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig, outputDirectory: URL) async throws
}

public extension JSONEncoder {
    static var robotVisionLabEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var robotVisionLabDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension RenderProduct {
    var fileExtension: String {
        switch self {
        case .rgb:
            "ppm"
        case .depth, .visibility:
            "pgm"
        case .pose, .segmentation, .obstacleMask, .lidarScan, .failureLabels, .navigationTarget:
            "json"
        }
    }
}
