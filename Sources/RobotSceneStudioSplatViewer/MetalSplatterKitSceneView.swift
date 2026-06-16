#if os(iOS) || os(macOS)

import Metal
import MetalKit
import os
import SwiftUI

#if os(macOS)
private typealias PlatformViewRepresentable = NSViewRepresentable
#else
private typealias PlatformViewRepresentable = UIViewRepresentable
#endif

public struct MetalSplatterKitSceneView: PlatformViewRepresentable {
    public var splatURL: URL?

    public init(splatURL: URL?) {
        self.splatURL = splatURL
    }

    public final class Coordinator {
        var renderer: MetalSplatterKitSceneRenderer?
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    #if os(macOS)
    public func makeNSView(context: NSViewRepresentableContext<MetalSplatterKitSceneView>) -> MTKView {
        makeView(context.coordinator)
    }

    public func updateNSView(_ view: MTKView, context: NSViewRepresentableContext<MetalSplatterKitSceneView>) {
        updateView(context.coordinator)
    }
    #else
    public func makeUIView(context: UIViewRepresentableContext<MetalSplatterKitSceneView>) -> MTKView {
        makeView(context.coordinator)
    }

    public func updateUIView(_ view: MTKView, context: UIViewRepresentableContext<MetalSplatterKitSceneView>) {
        updateView(context.coordinator)
    }
    #endif

    private func makeView(_ coordinator: Coordinator) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        let renderer = MetalSplatterKitSceneRenderer(view)
        coordinator.renderer = renderer
        view.delegate = renderer
        updateView(coordinator)
        return view
    }

    private func updateView(_ coordinator: Coordinator) {
        guard let renderer = coordinator.renderer else { return }
        Task {
            do {
                try await renderer.load(splatURL)
            } catch {
                renderer.recordLoadFailure(error)
            }
        }
    }
}

@MainActor
public final class MetalSplatterKitSceneRenderer: NSObject, MTKViewDelegate {
    private static let log = Logger(subsystem: "RobotSceneStudioSplatViewer", category: "MetalSplatterKitSceneRenderer")

    private let view: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let inFlightSemaphore = DispatchSemaphore(value: MetalSplatterViewerConstants.maxSimultaneousRenders)

    private var splatURL: URL?
    private var modelRenderer: (any MetalSplatterModelRendering)?
    private var lastRotationUpdateTimestamp: Date?
    private var rotationRadians: Float = 0
    private var drawableSize: CGSize = .zero

    public init?(_ view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.view = view
        self.device = device
        self.commandQueue = commandQueue
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    public func load(_ url: URL?) async throws {
        guard url != splatURL else { return }
        splatURL = url
        modelRenderer = nil
        guard let url else { return }
        modelRenderer = try await MetalSplatterSceneLoader.makeRenderer(
            for: url,
            device: device,
            colorFormat: view.colorPixelFormat,
            depthFormat: view.depthStencilPixelFormat,
            sampleCount: view.sampleCount,
            maxViewCount: 1,
            maxSimultaneousRenders: MetalSplatterViewerConstants.maxSimultaneousRenders
        )
    }

    public func recordLoadFailure(_ error: Error) {
        Self.log.error("Unable to load Gaussian splat: \(error.localizedDescription)")
    }

    public func draw(in view: MTKView) {
        guard let modelRenderer, modelRenderer.isReadyToRender else { return }
        guard let drawable = view.currentDrawable else { return }

        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }
        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        updateRotation()

        do {
            let didRender = try modelRenderer.render(
                viewports: [viewport],
                colorTexture: view.multisampleColorTexture ?? drawable.texture,
                colorStoreAction: view.multisampleColorTexture == nil ? .store : .multisampleResolve,
                depthTexture: view.depthStencilTexture,
                rasterizationRateMap: nil,
                renderTargetArrayLength: 0,
                to: commandBuffer
            )
            if didRender {
                commandBuffer.present(drawable)
            }
        } catch {
            Self.log.error("Unable to render Gaussian splat: \(error.localizedDescription)")
        }

        commandBuffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }

    private var viewport: MetalSplatterViewportDescriptor {
        let width = max(drawableSize.width, 1)
        let height = max(drawableSize.height, 1)
        let projection = metalSplatterPerspectiveMatrix(
            fovyRadians: MetalSplatterViewerConstants.fieldOfViewYRadians,
            aspectRatio: Float(width / height),
            nearZ: 0.1,
            farZ: 100
        )
        return MetalSplatterViewportDescriptor(
            viewport: MTLViewport(originX: 0, originY: 0, width: width, height: height, znear: 0, zfar: 1),
            projectionMatrix: projection,
            viewMatrix: metalSplatterDefaultModelViewMatrix(rotationRadians: rotationRadians),
            screenSize: SIMD2(x: Int(width), y: Int(height))
        )
    }

    private func updateRotation() {
        let now = Date()
        defer { lastRotationUpdateTimestamp = now }
        guard let lastRotationUpdateTimestamp else { return }
        rotationRadians += MetalSplatterViewerConstants.rotationRadiansPerSecond * Float(now.timeIntervalSince(lastRotationUpdateTimestamp))
    }
}

#endif

