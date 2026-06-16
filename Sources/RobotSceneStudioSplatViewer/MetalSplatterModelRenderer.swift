import Metal
import MetalSplatter
import simd

public struct MetalSplatterViewportDescriptor {
    public var viewport: MTLViewport
    public var projectionMatrix: simd_float4x4
    public var viewMatrix: simd_float4x4
    public var screenSize: SIMD2<Int>

    public init(
        viewport: MTLViewport,
        projectionMatrix: simd_float4x4,
        viewMatrix: simd_float4x4,
        screenSize: SIMD2<Int>
    ) {
        self.viewport = viewport
        self.projectionMatrix = projectionMatrix
        self.viewMatrix = viewMatrix
        self.screenSize = screenSize
    }
}

public protocol MetalSplatterModelRendering: Sendable {
    var isReadyToRender: Bool { get }

    @discardableResult
    func render(
        viewports: [MetalSplatterViewportDescriptor],
        colorTexture: MTLTexture,
        colorStoreAction: MTLStoreAction,
        depthTexture: MTLTexture?,
        rasterizationRateMap: MTLRasterizationRateMap?,
        renderTargetArrayLength: Int,
        to commandBuffer: MTLCommandBuffer
    ) throws -> Bool
}

extension SplatRenderer: MetalSplatterModelRendering {
    public func render(
        viewports: [MetalSplatterViewportDescriptor],
        colorTexture: MTLTexture,
        colorStoreAction: MTLStoreAction,
        depthTexture: MTLTexture?,
        rasterizationRateMap: MTLRasterizationRateMap?,
        renderTargetArrayLength: Int,
        to commandBuffer: MTLCommandBuffer
    ) throws -> Bool {
        try render(
            viewports: viewports.map {
                ViewportDescriptor(
                    viewport: $0.viewport,
                    projectionMatrix: $0.projectionMatrix,
                    viewMatrix: $0.viewMatrix,
                    screenSize: $0.screenSize
                )
            },
            colorTexture: colorTexture,
            colorStoreAction: colorStoreAction,
            depthTexture: depthTexture,
            rasterizationRateMap: rasterizationRateMap,
            renderTargetArrayLength: renderTargetArrayLength,
            to: commandBuffer
        )
    }
}
