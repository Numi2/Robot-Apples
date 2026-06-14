import Foundation
import simd

public struct RouteAlignmentControlPoint: Codable, Equatable, Sendable {
    public var arkitPosition: SIMD3<Double>
    public var scenePosition: SIMD3<Double>

    public init(arkitPosition: SIMD3<Double>, scenePosition: SIMD3<Double>) {
        self.arkitPosition = arkitPosition
        self.scenePosition = scenePosition
    }
}

public enum RouteAlignmentMethod: String, Codable, Sendable {
    case identity
    case routeBoundsToSceneBounds
    case controlPointCentroids
}

public struct RouteAlignmentRequest: Codable, Equatable, Sendable {
    public var sourceRoute: RobotPath
    public var sceneBounds: AxisAlignedBounds
    public var method: RouteAlignmentMethod
    public var controlPoints: [RouteAlignmentControlPoint]
    public var preserveVerticalScale: Bool

    public init(
        sourceRoute: RobotPath,
        sceneBounds: AxisAlignedBounds,
        method: RouteAlignmentMethod = .routeBoundsToSceneBounds,
        controlPoints: [RouteAlignmentControlPoint] = [],
        preserveVerticalScale: Bool = true
    ) {
        self.sourceRoute = sourceRoute
        self.sceneBounds = sceneBounds
        self.method = method
        self.controlPoints = controlPoints
        self.preserveVerticalScale = preserveVerticalScale
    }
}

public struct RouteAlignmentReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var method: RouteAlignmentMethod
    public var sourceRouteBounds: AxisAlignedBounds?
    public var sceneBounds: AxisAlignedBounds
    public var alignmentTransform: Transform3D
    public var sourceKeyframeCount: Int
    public var alignedKeyframeCount: Int
    public var alignedRouteURL: URL
    public var warnings: [String]

    public init(
        generatedAt: Date = Date(),
        method: RouteAlignmentMethod,
        sourceRouteBounds: AxisAlignedBounds?,
        sceneBounds: AxisAlignedBounds,
        alignmentTransform: Transform3D,
        sourceKeyframeCount: Int,
        alignedKeyframeCount: Int,
        alignedRouteURL: URL,
        warnings: [String]
    ) {
        self.generatedAt = generatedAt
        self.method = method
        self.sourceRouteBounds = sourceRouteBounds
        self.sceneBounds = sceneBounds
        self.alignmentTransform = alignmentTransform
        self.sourceKeyframeCount = sourceKeyframeCount
        self.alignedKeyframeCount = alignedKeyframeCount
        self.alignedRouteURL = alignedRouteURL
        self.warnings = warnings
    }
}

public struct RouteAlignmentOutput: Codable, Equatable, Sendable {
    public var alignedRoute: RobotPath
    public var report: RouteAlignmentReport

    public init(alignedRoute: RobotPath, report: RouteAlignmentReport) {
        self.alignedRoute = alignedRoute
        self.report = report
    }
}

public struct RobotRouteAligner: Sendable {
    public init() {}

    public func align(
        request: RouteAlignmentRequest,
        outputDirectory: URL,
        generatedAt: Date = Date()
    ) throws -> RouteAlignmentOutput {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let routeBounds = bounds(for: request.sourceRoute)
        let transform = estimateTransform(request: request, routeBounds: routeBounds)
        let aligned = RobotPath(keyframes: request.sourceRoute.keyframes.map {
            RobotPathKeyframe(
                timestamp: $0.timestamp,
                pose: $0.pose.applying(transform),
                navigationTarget: $0.navigationTarget
            )
        })

        let alignedRouteURL = outputDirectory.appendingPathComponent("aligned_capture_route.json")
        try JSONEncoder.robotVisionLabEncoder.encode(aligned).write(to: alignedRouteURL)

        let report = RouteAlignmentReport(
            generatedAt: generatedAt,
            method: request.method,
            sourceRouteBounds: routeBounds,
            sceneBounds: request.sceneBounds,
            alignmentTransform: transform,
            sourceKeyframeCount: request.sourceRoute.keyframes.count,
            alignedKeyframeCount: aligned.keyframes.count,
            alignedRouteURL: alignedRouteURL,
            warnings: warnings(request: request, routeBounds: routeBounds, transform: transform)
        )
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(
            to: outputDirectory.appendingPathComponent("route_alignment_report.json")
        )

        return RouteAlignmentOutput(alignedRoute: aligned, report: report)
    }

    private func estimateTransform(request: RouteAlignmentRequest, routeBounds: AxisAlignedBounds?) -> Transform3D {
        switch request.method {
        case .identity:
            return .identity
        case .controlPointCentroids where !request.controlPoints.isEmpty:
            let arkitCentroid = centroid(request.controlPoints.map(\.arkitPosition))
            let sceneCentroid = centroid(request.controlPoints.map(\.scenePosition))
            return Transform3D(translation: sceneCentroid - arkitCentroid)
        case .controlPointCentroids:
            return .identity
        case .routeBoundsToSceneBounds:
            guard let routeBounds else { return .identity }
            let routeCenter = (routeBounds.minimum + routeBounds.maximum) / 2.0
            let sceneCenter = (request.sceneBounds.minimum + request.sceneBounds.maximum) / 2.0
            let routeSpan = max(routeBounds.maximum - routeBounds.minimum, SIMD3<Double>(0.001, 0.001, 0.001))
            let sceneSpan = max(request.sceneBounds.maximum - request.sceneBounds.minimum, SIMD3<Double>(0.001, 0.001, 0.001))
            let horizontalScale = min(sceneSpan.x / routeSpan.x, sceneSpan.z / routeSpan.z)
            let scale = SIMD3<Double>(
                horizontalScale,
                request.preserveVerticalScale ? 1.0 : horizontalScale,
                horizontalScale
            )
            let translation = sceneCenter - (routeCenter * scale)
            return Transform3D(translation: translation, scale: scale)
        }
    }

    private func bounds(for route: RobotPath) -> AxisAlignedBounds? {
        guard let first = route.keyframes.first?.pose.position else { return nil }
        var minimum = first
        var maximum = first
        for keyframe in route.keyframes.dropFirst() {
            minimum = min(minimum, keyframe.pose.position)
            maximum = max(maximum, keyframe.pose.position)
        }
        return AxisAlignedBounds(minimum: minimum, maximum: maximum)
    }

    private func centroid(_ points: [SIMD3<Double>]) -> SIMD3<Double> {
        guard !points.isEmpty else { return .zero }
        return points.reduce(.zero, +) / Double(points.count)
    }

    private func warnings(
        request: RouteAlignmentRequest,
        routeBounds: AxisAlignedBounds?,
        transform: Transform3D
    ) -> [String] {
        var warnings: [String] = []
        if routeBounds == nil {
            warnings.append("Source route is empty; identity alignment was used.")
        }
        if request.method == .controlPointCentroids && request.controlPoints.isEmpty {
            warnings.append("Control-point alignment requested without control points; identity alignment was used.")
        }
        if transform.scale.x > 10 || transform.scale.z > 10 || transform.scale.x < 0.1 || transform.scale.z < 0.1 {
            warnings.append("Estimated horizontal scale is large; verify ARKit-to-splat units and scene bounds.")
        }
        if request.method == .routeBoundsToSceneBounds {
            warnings.append("Bounds alignment is an initial estimate; refine with manual control points when real splat landmarks are available.")
        }
        return warnings
    }
}
