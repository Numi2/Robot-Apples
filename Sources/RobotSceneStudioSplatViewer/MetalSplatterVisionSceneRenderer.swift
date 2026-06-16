#if os(visionOS)

import CompositorServices
import Foundation
import Metal
import os
import simd
import SwiftUI

public struct MetalSplatterImmersiveScene: Codable, Hashable, Sendable {
    public var splatURL: URL

    public init(splatURL: URL) {
        self.splatURL = splatURL
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
    private let commandQueue: MTLCommandQueue
    private let inFlightSemaphore = DispatchSemaphore(value: MetalSplatterViewerConstants.maxSimultaneousRenders)

    private var modelRenderer: (any MetalSplatterModelRendering)?
    private var lastRotationUpdateTimestamp: Date?
    private var rotationRadians: Float = 0

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    public init(_ layerRenderer: LayerRenderer) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Unable to create a Metal command queue for visionOS splat rendering.")
        }
        self.commandQueue = commandQueue
    }

    public static func startRendering(_ layerRenderer: LayerRenderer, splatURL: URL?) {
        let renderer = MetalSplatterVisionSceneRenderer(layerRenderer)
        Task {
            do {
                try await renderer.load(splatURL)
            } catch {
                log.error("Unable to load Gaussian splat: \(error.localizedDescription)")
            }
            renderer.startRenderLoop()
        }
    }

    public func load(_ splatURL: URL?) async throws {
        modelRenderer = nil
        guard let splatURL else { return }
        modelRenderer = try await MetalSplatterSceneLoader.makeRenderer(
            for: splatURL,
            device: device,
            colorFormat: layerRenderer.configuration.colorFormat,
            depthFormat: layerRenderer.configuration.depthFormat,
            sampleCount: 1,
            maxViewCount: layerRenderer.properties.viewCount,
            maxSimultaneousRenders: MetalSplatterViewerConstants.maxSimultaneousRenders
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
                _ = try modelRenderer.render(
                    viewports: viewports(drawable: drawable, deviceAnchor: deviceAnchor),
                    colorTexture: drawable.colorTextures[0],
                    colorStoreAction: .store,
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

    private func viewports(drawable: LayerRenderer.Drawable, deviceAnchor: DeviceAnchor?) -> [MetalSplatterViewportDescriptor] {
        let simdDeviceAnchor = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4
        let modelView = metalSplatterDefaultModelViewMatrix(rotationRadians: rotationRadians)
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
        let now = Date()
        defer { lastRotationUpdateTimestamp = now }
        guard let lastRotationUpdateTimestamp else { return }
        rotationRadians += MetalSplatterViewerConstants.rotationRadiansPerSecond * Float(now.timeIntervalSince(lastRotationUpdateTimestamp))
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
