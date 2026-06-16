import Foundation
import simd

public enum MetalSplatterSpatialOverlayLayer: String, Codable, Hashable, Sendable {
    case robotRoutes
    case cameraFrustums
    case navigationGraph
    case failureMap
    case predictions
}

public struct MetalSplatterSpatialOverlayPayload: Codable, Equatable, Hashable, Sendable {
    public var lineSegments: [MetalSplatterSpatialOverlayLineSegment]
    public var pointMarkers: [MetalSplatterSpatialOverlayPointMarker]

    public init(
        lineSegments: [MetalSplatterSpatialOverlayLineSegment] = [],
        pointMarkers: [MetalSplatterSpatialOverlayPointMarker] = []
    ) {
        self.lineSegments = lineSegments
        self.pointMarkers = pointMarkers
    }

    public static let empty = MetalSplatterSpatialOverlayPayload()

    public var isEmpty: Bool {
        lineSegments.isEmpty && pointMarkers.isEmpty
    }
}

public struct MetalSplatterSpatialOverlayLineSegment: Codable, Equatable, Hashable, Sendable {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    public var color: SIMD4<Float>
    public var layer: MetalSplatterSpatialOverlayLayer

    public init(
        start: SIMD3<Float>,
        end: SIMD3<Float>,
        color: SIMD4<Float>,
        layer: MetalSplatterSpatialOverlayLayer
    ) {
        self.start = start
        self.end = end
        self.color = color
        self.layer = layer
    }
}

public struct MetalSplatterSpatialOverlayPointMarker: Codable, Equatable, Hashable, Sendable {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
    public var radius: Float
    public var layer: MetalSplatterSpatialOverlayLayer

    public init(
        position: SIMD3<Float>,
        color: SIMD4<Float>,
        radius: Float,
        layer: MetalSplatterSpatialOverlayLayer
    ) {
        self.position = position
        self.color = color
        self.radius = radius
        self.layer = layer
    }
}

enum MetalSplatterSpatialOverlayShaders {
    static let lineOverlay = """
    #include <metal_stdlib>
    using namespace metal;

    struct OverlayVertex {
        float4 position;
        float4 color;
    };

    struct OverlayUniforms {
        float4x4 viewProjectionMatrix;
        uint renderTargetArrayIndex;
    };

    struct OverlayVertexOut {
        float4 position [[position]];
        float4 color;
        uint renderTargetArrayIndex [[render_target_array_index]];
    };

    vertex OverlayVertexOut robot_spatial_overlay_vertex(
        const device OverlayVertex *vertices [[buffer(0)]],
        constant OverlayUniforms &uniforms [[buffer(1)]],
        uint vertexID [[vertex_id]]
    ) {
        OverlayVertexOut out;
        OverlayVertex overlayVertex = vertices[vertexID];
        out.position = uniforms.viewProjectionMatrix * overlayVertex.position;
        out.color = overlayVertex.color;
        out.renderTargetArrayIndex = uniforms.renderTargetArrayIndex;
        return out;
    }

    fragment half4 robot_spatial_overlay_fragment(OverlayVertexOut in [[stage_in]]) {
        return half4(in.color);
    }
    """
}
