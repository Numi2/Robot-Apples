#if os(visionOS)

import CompositorServices
import Foundation
import Metal
import os
import simd
import SwiftUI

public struct MetalSplatterImmersiveScene: Codable, Hashable, Sendable {
    public var sessionID: String
    public var splatURL: URL
    public var modelTransform: [Float]
    public var spatialOverlay: MetalSplatterSpatialOverlayPayload

    public init(
        sessionID: String = UUID().uuidString,
        splatURL: URL,
        modelTransform: [Float] = metalSplatterIdentityMatrixPayload,
        spatialOverlay: MetalSplatterSpatialOverlayPayload = .empty
    ) {
        self.sessionID = sessionID
        self.splatURL = splatURL
        self.modelTransform = modelTransform
        self.spatialOverlay = spatialOverlay
    }
}

public struct MetalSplatterImmersiveSceneControls: Codable, Equatable, Hashable, Sendable {
    public var recenterOffsetX: Float
    public var recenterOffsetY: Float
    public var recenterOffsetZ: Float
    public var scale: Float
    public var yawRadians: Float
    public var pitchRadians: Float
    public var rollRadians: Float
    public var automaticRotationEnabled: Bool

    public init(
        recenterOffsetX: Float = 0,
        recenterOffsetY: Float = 0,
        recenterOffsetZ: Float = 0,
        scale: Float = 1,
        yawRadians: Float = 0,
        pitchRadians: Float = 0,
        rollRadians: Float = 0,
        automaticRotationEnabled: Bool = true
    ) {
        self.recenterOffsetX = recenterOffsetX
        self.recenterOffsetY = recenterOffsetY
        self.recenterOffsetZ = recenterOffsetZ
        self.scale = min(max(scale, 0.1), 8)
        self.yawRadians = yawRadians
        self.pitchRadians = min(max(pitchRadians, -Float.pi / 2), Float.pi / 2)
        self.rollRadians = rollRadians
        self.automaticRotationEnabled = automaticRotationEnabled
    }

    public static let `default` = MetalSplatterImmersiveSceneControls()
}

public enum MetalSplatterImmersiveSceneStatusKind: String, Codable, Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed
}

public struct MetalSplatterImmersiveSceneStatus: Codable, Equatable, Sendable {
    public var kind: MetalSplatterImmersiveSceneStatusKind
    public var message: String
    public var updatedAt: Date

    public init(
        kind: MetalSplatterImmersiveSceneStatusKind = .idle,
        message: String = "Splat space is idle.",
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.message = message
        self.updatedAt = updatedAt
    }
}

public final class MetalSplatterVisionSceneSessionStore: @unchecked Sendable {
    public static let shared = MetalSplatterVisionSceneSessionStore()

    private let lock = NSLock()
    private var controlsBySessionID: [String: MetalSplatterImmersiveSceneControls] = [:]
    private var statusBySessionID: [String: MetalSplatterImmersiveSceneStatus] = [:]

    private init() {}

    public func controls(for sessionID: String) -> MetalSplatterImmersiveSceneControls {
        lock.withLock {
            controlsBySessionID[sessionID] ?? .default
        }
    }

    public func setControls(_ controls: MetalSplatterImmersiveSceneControls, for sessionID: String) {
        lock.withLock {
            controlsBySessionID[sessionID] = controls
        }
    }

    public func status(for sessionID: String) -> MetalSplatterImmersiveSceneStatus {
        lock.withLock {
            statusBySessionID[sessionID] ?? MetalSplatterImmersiveSceneStatus()
        }
    }

    public func setStatus(_ status: MetalSplatterImmersiveSceneStatus, for sessionID: String) {
        lock.withLock {
            statusBySessionID[sessionID] = status
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

public struct MetalSplatterContentStageConfiguration: CompositorLayerConfiguration {
    public init() {}

    public func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {
        configuration.depthFormat = .depth32Float
        configuration.colorFormat = .bgra8Unorm_srgb

        let foveationEnabled = capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveationEnabled

        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions = foveationEnabled ? [.foveationEnabled] : []
        let supportedLayouts = capabilities.supportedLayouts(options: options)
        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated
    }
}

public extension LayerRenderer.Clock.Instant.Duration {
    var robotSceneStudioTimeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}

public final class MetalSplatterVisionSceneRenderer: @unchecked Sendable {
    private static let log = Logger(subsystem: "RobotSceneStudioSplatViewer", category: "MetalSplatterVisionSceneRenderer")

    private let layerRenderer: LayerRenderer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private let inFlightSemaphore = DispatchSemaphore(value: MetalSplatterViewerConstants.maxSimultaneousRenders)

    private var modelRenderer: (any MetalSplatterModelRendering)?
    private var overlayRenderer: MetalSplatterSpatialOverlayRenderer?
    private var sessionID: String = UUID().uuidString
    private var spatialOverlay: MetalSplatterSpatialOverlayPayload = .empty
    private var modelTransform: simd_float4x4 = matrix_identity_float4x4
    private var lastRotationUpdateTimestamp: Date?
    private var rotationRadians: Float = 0

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    public init(_ layerRenderer: LayerRenderer) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        self.commandQueue = device.makeCommandQueue()
        if self.commandQueue == nil {
            Self.log.error("Unable to create a Metal command queue for visionOS splat rendering.")
        }
        do {
            self.overlayRenderer = try MetalSplatterSpatialOverlayRenderer(
                device: device,
                colorFormat: layerRenderer.configuration.colorFormat,
                depthFormat: layerRenderer.configuration.depthFormat
            )
        } catch {
            Self.log.error("Unable to create spatial overlay renderer: \(error.localizedDescription)")
        }
    }

    public static func startRendering(
        _ layerRenderer: LayerRenderer,
        sessionID: String = UUID().uuidString,
        splatURL: URL?,
        modelTransform: [Float] = metalSplatterIdentityMatrixPayload,
        spatialOverlay: MetalSplatterSpatialOverlayPayload = .empty
    ) {
        let renderer = MetalSplatterVisionSceneRenderer(layerRenderer)
        renderer.sessionID = sessionID
        renderer.modelTransform = metalSplatterMatrix(from: modelTransform)
        renderer.spatialOverlay = spatialOverlay
        Task {
            do {
                try await renderer.load(splatURL)
            } catch {
                MetalSplatterVisionSceneSessionStore.shared.setStatus(
                    MetalSplatterImmersiveSceneStatus(kind: .failed, message: error.localizedDescription),
                    for: sessionID
                )
                log.error("Unable to load Gaussian splat: \(error.localizedDescription)")
            }
            renderer.startRenderLoop()
        }
    }

    public func load(_ splatURL: URL?) async throws {
        modelRenderer = nil
        guard let splatURL else {
            MetalSplatterVisionSceneSessionStore.shared.setStatus(
                MetalSplatterImmersiveSceneStatus(kind: .idle, message: "No Gaussian splat is linked to this scene."),
                for: sessionID
            )
            return
        }
        MetalSplatterVisionSceneSessionStore.shared.setStatus(
            MetalSplatterImmersiveSceneStatus(kind: .loading, message: "Loading \(splatURL.lastPathComponent)."),
            for: sessionID
        )
        modelRenderer = try await MetalSplatterSceneLoader.makeRenderer(
            for: splatURL,
            device: device,
            colorFormat: layerRenderer.configuration.colorFormat,
            depthFormat: layerRenderer.configuration.depthFormat,
            sampleCount: 1,
            maxViewCount: layerRenderer.properties.viewCount,
            maxSimultaneousRenders: MetalSplatterViewerConstants.maxSimultaneousRenders
        )
        MetalSplatterVisionSceneSessionStore.shared.setStatus(
            MetalSplatterImmersiveSceneStatus(kind: .ready, message: "Rendering \(splatURL.lastPathComponent)."),
            for: sessionID
        )
    }

    public func startRenderLoop() {
        Task(executorPreference: MetalSplatterRendererTaskExecutor.shared) {
            do {
                try await self.arSession.run([self.worldTracking])
            } catch {
                Self.log.error("Unable to initialize ARKit world tracking: \(error.localizedDescription)")
            }
            self.renderLoop()
        }
    }

    private func renderLoop() {
        while true {
            autoreleasepool {
                switch layerRenderer.state {
                case .invalidated:
                    return
                case .paused:
                    layerRenderer.waitUntilRunning()
                default:
                    renderFrame()
                }
            }
            if layerRenderer.state == .invalidated {
                return
            }
        }
    }

    private func renderFrame() {
        guard let commandQueue else {
            MetalSplatterVisionSceneSessionStore.shared.setStatus(
                MetalSplatterImmersiveSceneStatus(kind: .failed, message: "Metal command queue is unavailable."),
                for: sessionID
            )
            return
        }
        guard let frame = layerRenderer.queryNextFrame() else { return }

        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        let drawables = frame.queryDrawables()
        guard !drawables.isEmpty else { return }

        guard let modelRenderer, modelRenderer.isReadyToRender else {
            frame.startSubmission()
            for drawable in drawables {
                guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }
                drawable.encodePresent(commandBuffer: commandBuffer)
                commandBuffer.commit()
            }
            frame.endSubmission()
            return
        }

        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        frame.startSubmission()

        updateRotation()
        let controls = MetalSplatterVisionSceneSessionStore.shared.controls(for: sessionID)
        let primaryDrawable = drawables[0]
        let time = LayerRenderer.Clock.Instant.epoch
            .duration(to: primaryDrawable.frameTiming.presentationTime)
            .robotSceneStudioTimeInterval
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)

        for (index, drawable) in drawables.enumerated() {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { continue }
            drawable.deviceAnchor = deviceAnchor

            if index == drawables.count - 1 {
                let semaphore = inFlightSemaphore
                commandBuffer.addCompletedHandler { _ in
                    semaphore.signal()
                }
            }

            do {
                let splatViewports = viewports(
                    drawable: drawable,
                    deviceAnchor: deviceAnchor,
                    sceneTransform: controlledSceneTransform(controls) * modelTransform,
                    controls: controls
                )
                _ = try modelRenderer.render(
                    viewports: splatViewports,
                    colorTexture: drawable.colorTextures[0],
                    colorStoreAction: .store,
                    depthTexture: drawable.depthTextures[0],
                    rasterizationRateMap: drawable.rasterizationRateMaps.first,
                    renderTargetArrayLength: layerRenderer.configuration.layout == .layered ? drawable.views.count : 1,
                    to: commandBuffer
                )
                try overlayRenderer?.render(
                    payload: spatialOverlay,
                    viewports: viewports(
                        drawable: drawable,
                        deviceAnchor: deviceAnchor,
                        sceneTransform: matrix_identity_float4x4
                    ),
                    colorTexture: drawable.colorTextures[0],
                    depthTexture: drawable.depthTextures[0],
                    rasterizationRateMap: drawable.rasterizationRateMaps.first,
                    renderTargetArrayLength: layerRenderer.configuration.layout == .layered ? drawable.views.count : 1,
                    to: commandBuffer
                )
            } catch {
                Self.log.error("Unable to render Gaussian splat: \(error.localizedDescription)")
            }

            drawable.encodePresent(commandBuffer: commandBuffer)
            commandBuffer.commit()
        }

        frame.endSubmission()
    }

    private func viewports(
        drawable: LayerRenderer.Drawable,
        deviceAnchor: DeviceAnchor?,
        sceneTransform: simd_float4x4,
        controls: MetalSplatterImmersiveSceneControls = .default
    ) -> [MetalSplatterViewportDescriptor] {
        let simdDeviceAnchor = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4
        let modelView = metalSplatterDefaultModelViewMatrix(
            rotationRadians: controls.automaticRotationEnabled ? rotationRadians : 0,
            sceneTransform: sceneTransform
        )
        return drawable.views.enumerated().map { index, view in
            let userViewpoint = (simdDeviceAnchor * view.transform).inverse
            let projection = drawable.computeProjection(viewIndex: index)
            let screenSize = SIMD2(
                x: Int(view.textureMap.viewport.width),
                y: Int(view.textureMap.viewport.height)
            )
            return MetalSplatterViewportDescriptor(
                viewport: view.textureMap.viewport,
                projectionMatrix: projection,
                viewMatrix: userViewpoint * modelView,
                screenSize: screenSize
            )
        }
    }

    private func updateRotation() {
        guard MetalSplatterVisionSceneSessionStore.shared.controls(for: sessionID).automaticRotationEnabled else {
            lastRotationUpdateTimestamp = Date()
            return
        }
        let now = Date()
        defer { lastRotationUpdateTimestamp = now }
        guard let lastRotationUpdateTimestamp else { return }
        rotationRadians += MetalSplatterViewerConstants.rotationRadiansPerSecond * Float(now.timeIntervalSince(lastRotationUpdateTimestamp))
    }

    private func controlledSceneTransform(_ controls: MetalSplatterImmersiveSceneControls) -> simd_float4x4 {
        let translation = metalSplatterTranslationMatrix(
            controls.recenterOffsetX,
            controls.recenterOffsetY,
            controls.recenterOffsetZ
        )
        let scale = simd_float4x4(diagonal: SIMD4<Float>(controls.scale, controls.scale, controls.scale, 1))
        let yaw = metalSplatterRotationMatrix(radians: controls.yawRadians, axis: SIMD3<Float>(0, 1, 0))
        let pitch = metalSplatterRotationMatrix(radians: controls.pitchRadians, axis: SIMD3<Float>(1, 0, 0))
        let roll = metalSplatterRotationMatrix(radians: controls.rollRadians, axis: SIMD3<Float>(0, 0, 1))
        return translation * roll * pitch * yaw * scale
    }
}

private final class MetalSplatterSpatialOverlayRenderer {
    private let pipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState?
    private let device: MTLDevice

    init(device: MTLDevice, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) throws {
        self.device = device
        let library = try device.makeLibrary(source: MetalSplatterSpatialOverlayShaders.lineOverlay, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "robot_spatial_overlay_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "robot_spatial_overlay_fragment")
        descriptor.inputPrimitiveTopology = .line
        descriptor.colorAttachments[0].pixelFormat = colorFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = depthFormat
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = false
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    func render(
        payload: MetalSplatterSpatialOverlayPayload,
        viewports: [MetalSplatterViewportDescriptor],
        colorTexture: MTLTexture,
        depthTexture: MTLTexture?,
        rasterizationRateMap: MTLRasterizationRateMap?,
        renderTargetArrayLength: Int,
        to commandBuffer: MTLCommandBuffer
    ) throws {
        guard !payload.isEmpty, !viewports.isEmpty else { return }
        let vertices = makeVertices(payload: payload)
        guard !vertices.isEmpty else { return }
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<OverlayVertex>.stride * vertices.count
        ) else {
            return
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = colorTexture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        if let depthTexture {
            descriptor.depthAttachment.texture = depthTexture
            descriptor.depthAttachment.loadAction = .load
            descriptor.depthAttachment.storeAction = .store
        }
        descriptor.rasterizationRateMap = rasterizationRateMap
        descriptor.renderTargetArrayLength = max(renderTargetArrayLength, 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.setRenderPipelineState(pipelineState)
        if let depthStencilState {
            encoder.setDepthStencilState(depthStencilState)
        }
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        for (index, viewport) in viewports.enumerated() {
            var uniforms = OverlayUniforms(
                viewProjectionMatrix: viewport.projectionMatrix * viewport.viewMatrix,
                renderTargetArrayIndex: UInt32(index)
            )
            encoder.setViewport(viewport.viewport)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<OverlayUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertices.count)
        }
        encoder.endEncoding()
    }

    private func makeVertices(payload: MetalSplatterSpatialOverlayPayload) -> [OverlayVertex] {
        var vertices: [OverlayVertex] = []
        vertices.reserveCapacity(payload.lineSegments.count * 2 + payload.pointMarkers.count * 6)
        for segment in payload.lineSegments {
            vertices.append(OverlayVertex(position: SIMD4<Float>(segment.start, 1), color: segment.color))
            vertices.append(OverlayVertex(position: SIMD4<Float>(segment.end, 1), color: segment.color))
        }
        for marker in payload.pointMarkers {
            let radius = max(marker.radius, 0.01)
            appendCross(center: marker.position, radius: radius, color: marker.color, to: &vertices)
        }
        return vertices
    }

    private func appendCross(
        center: SIMD3<Float>,
        radius: Float,
        color: SIMD4<Float>,
        to vertices: inout [OverlayVertex]
    ) {
        let axes = [
            SIMD3<Float>(radius, 0, 0),
            SIMD3<Float>(0, radius, 0),
            SIMD3<Float>(0, 0, radius)
        ]
        for axis in axes {
            vertices.append(OverlayVertex(position: SIMD4<Float>(center - axis, 1), color: color))
            vertices.append(OverlayVertex(position: SIMD4<Float>(center + axis, 1), color: color))
        }
    }

    private struct OverlayVertex {
        var position: SIMD4<Float>
        var color: SIMD4<Float>
    }

    private struct OverlayUniforms {
        var viewProjectionMatrix: simd_float4x4
        var renderTargetArrayIndex: UInt32
    }

}

public final class MetalSplatterRendererTaskExecutor: TaskExecutor {
    public static let shared = MetalSplatterRendererTaskExecutor()
    private let queue = DispatchQueue(label: "RobotSceneStudioSplatViewer.RenderThread", qos: .userInteractive)

    public func enqueue(_ job: UnownedJob) {
        queue.async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    public nonisolated func asUnownedSerialExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}

#endif
