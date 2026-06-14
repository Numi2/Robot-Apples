import Foundation

public struct MetalRenderConfiguration: Codable, Equatable, Sendable {
    public var colorPixelFormat: String
    public var depthPixelFormat: String
    public var preferredFramesInFlight: Int
    public var tileSize: Int
    public var enableDepthApproximation: Bool
    public var enableSegmentationProjection: Bool

    public init(
        colorPixelFormat: String = "bgra8Unorm_srgb",
        depthPixelFormat: String = "depth32Float",
        preferredFramesInFlight: Int = 3,
        tileSize: Int = 16,
        enableDepthApproximation: Bool = true,
        enableSegmentationProjection: Bool = true
    ) {
        self.colorPixelFormat = colorPixelFormat
        self.depthPixelFormat = depthPixelFormat
        self.preferredFramesInFlight = preferredFramesInFlight
        self.tileSize = tileSize
        self.enableDepthApproximation = enableDepthApproximation
        self.enableSegmentationProjection = enableSegmentationProjection
    }
}

public struct MetalRenderPlan: Codable, Equatable, Sendable {
    public var id: String
    public var scene: GaussianSplatScene
    public var cameraRig: RobotCameraRig
    public var frameCount: Int
    public var requestedProducts: Set<RenderProduct>
    public var configuration: MetalRenderConfiguration

    public init(
        id: String,
        scene: GaussianSplatScene,
        cameraRig: RobotCameraRig,
        frameCount: Int,
        requestedProducts: Set<RenderProduct>,
        configuration: MetalRenderConfiguration = MetalRenderConfiguration()
    ) {
        self.id = id
        self.scene = scene
        self.cameraRig = cameraRig
        self.frameCount = frameCount
        self.requestedProducts = requestedProducts
        self.configuration = configuration
    }
}

public struct MetalDeviceCapabilities: Codable, Equatable, Sendable {
    public var isAvailable: Bool
    public var deviceName: String?
    public var supportsRaytracing: Bool
    public var supportsFunctionPointers: Bool
    public var recommendedMaxWorkingSetSize: UInt64?

    public init(
        isAvailable: Bool,
        deviceName: String? = nil,
        supportsRaytracing: Bool = false,
        supportsFunctionPointers: Bool = false,
        recommendedMaxWorkingSetSize: UInt64? = nil
    ) {
        self.isAvailable = isAvailable
        self.deviceName = deviceName
        self.supportsRaytracing = supportsRaytracing
        self.supportsFunctionPointers = supportsFunctionPointers
        self.recommendedMaxWorkingSetSize = recommendedMaxWorkingSetSize
    }
}

public enum MetalRenderPlanStatus: String, Codable, Sendable {
    case ready
    case unavailable
    case invalid
}

public struct MetalRenderPlanReport: Codable, Equatable, Sendable {
    public var plan: MetalRenderPlan
    public var capabilities: MetalDeviceCapabilities
    public var status: MetalRenderPlanStatus
    public var diagnostics: [String]

    public init(
        plan: MetalRenderPlan,
        capabilities: MetalDeviceCapabilities,
        status: MetalRenderPlanStatus,
        diagnostics: [String]
    ) {
        self.plan = plan
        self.capabilities = capabilities
        self.status = status
        self.diagnostics = diagnostics
    }
}

public struct MetalRenderPlanner: Sendable {
    public init() {}

    public func makePlan(from recipe: DatasetRecipe, configuration: MetalRenderConfiguration = MetalRenderConfiguration()) -> MetalRenderPlan {
        MetalRenderPlan(
            id: "\(recipe.id)-metal-render-plan",
            scene: recipe.scene,
            cameraRig: recipe.cameraRig,
            frameCount: recipe.path.keyframes.count,
            requestedProducts: recipe.requestedProducts,
            configuration: configuration
        )
    }

    public func validate(plan: MetalRenderPlan, capabilities: MetalDeviceCapabilities) -> MetalRenderPlanReport {
        var diagnostics: [String] = []
        if !capabilities.isAvailable {
            diagnostics.append("No Metal device is available.")
        }
        if plan.frameCount == 0 {
            diagnostics.append("Render plan contains no robot-camera frames.")
        }
        if !plan.requestedProducts.contains(.rgb) {
            diagnostics.append("Render plan does not request RGB output.")
        }
        if plan.cameraRig.intrinsics.width <= 0 || plan.cameraRig.intrinsics.height <= 0 {
            diagnostics.append("Camera intrinsics must have positive dimensions.")
        }

        let status: MetalRenderPlanStatus
        if diagnostics.contains("No Metal device is available.") {
            status = .unavailable
        } else if diagnostics.isEmpty {
            status = .ready
        } else {
            status = .invalid
        }

        return MetalRenderPlanReport(
            plan: plan,
            capabilities: capabilities,
            status: status,
            diagnostics: diagnostics
        )
    }
}

public struct MetalRenderPlanReportWriter: Sendable {
    public init() {}

    public func write(_ report: MetalRenderPlanReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }
}

#if canImport(Metal)
import Metal

public struct MetalDeviceProbe: Sendable {
    public init() {}

    public func capabilities() -> MetalDeviceCapabilities {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MetalDeviceCapabilities(isAvailable: false)
        }
        return MetalDeviceCapabilities(
            isAvailable: true,
            deviceName: device.name,
            supportsRaytracing: device.supportsRaytracing,
            supportsFunctionPointers: device.supportsFunctionPointers,
            recommendedMaxWorkingSetSize: device.recommendedMaxWorkingSetSize
        )
    }
}
#else
public struct MetalDeviceProbe: Sendable {
    public init() {}

    public func capabilities() -> MetalDeviceCapabilities {
        MetalDeviceCapabilities(isAvailable: false)
    }
}
#endif
