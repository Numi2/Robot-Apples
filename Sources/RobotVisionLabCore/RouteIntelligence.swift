import Foundation
import simd

public struct RouteFloorHeightConstraint: Codable, Equatable, Sendable {
    public var floorY: Double
    public var minimumCameraHeight: Double
    public var maximumCameraHeight: Double
    public var clampToFloorPlane: Bool

    public init(
        floorY: Double = 0,
        minimumCameraHeight: Double = 0.2,
        maximumCameraHeight: Double = 2.0,
        clampToFloorPlane: Bool = true
    ) {
        self.floorY = floorY
        self.minimumCameraHeight = minimumCameraHeight
        self.maximumCameraHeight = maximumCameraHeight
        self.clampToFloorPlane = clampToFloorPlane
    }

    public func constrained(_ position: SIMD3<Double>) -> SIMD3<Double> {
        var next = position
        let minY = floorY + minimumCameraHeight
        let maxY = floorY + maximumCameraHeight
        next.y = clampToFloorPlane ? min(max(position.y, minY), maxY) : position.y
        return next
    }
}

public struct RouteTransformEditor: Codable, Equatable, Sendable {
    public var translation: SIMD3<Double>
    public var yawDegrees: Double
    public var scale: SIMD3<Double>

    public init(
        translation: SIMD3<Double> = .zero,
        yawDegrees: Double = 0,
        scale: SIMD3<Double> = SIMD3<Double>(1, 1, 1)
    ) {
        self.translation = translation
        self.yawDegrees = yawDegrees
        self.scale = scale
    }

    public var transform: Transform3D {
        Transform3D(
            translation: translation,
            rotation: simd_quatd(angle: yawDegrees * .pi / 180.0, axis: SIMD3<Double>(0, 1, 0)),
            scale: scale
        )
    }
}

public struct RouteConfidenceMetrics: Codable, Equatable, Sendable {
    public var alignmentConfidence: Double
    public var anchorCount: Int
    public var meanAnchorResidualMeters: Double?
    public var routeKeyframeCount: Int
    public var constrainedKeyframeCount: Int
    public var warnings: [String]

    public init(
        alignmentConfidence: Double,
        anchorCount: Int,
        meanAnchorResidualMeters: Double? = nil,
        routeKeyframeCount: Int,
        constrainedKeyframeCount: Int,
        warnings: [String] = []
    ) {
        self.alignmentConfidence = alignmentConfidence
        self.anchorCount = anchorCount
        self.meanAnchorResidualMeters = meanAnchorResidualMeters
        self.routeKeyframeCount = routeKeyframeCount
        self.constrainedKeyframeCount = constrainedKeyframeCount
        self.warnings = warnings
    }
}

public enum CoverageIssueKind: String, Codable, Sendable {
    case missingViews
    case repeatedViews
    case lowParallax
}

public struct RouteCoverageIssue: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: CoverageIssueKind
    public var frameIndex: Int
    public var position: SIMD3<Double>
    public var severity: Double
    public var note: String

    public init(id: String, kind: CoverageIssueKind, frameIndex: Int, position: SIMD3<Double>, severity: Double, note: String) {
        self.id = id
        self.kind = kind
        self.frameIndex = frameIndex
        self.position = position
        self.severity = severity
        self.note = note
    }
}

public struct RouteCoverageReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var keyframeCount: Int
    public var issueCount: Int
    public var missingViewCount: Int
    public var repeatedViewCount: Int
    public var lowParallaxCount: Int
    public var issues: [RouteCoverageIssue]

    public init(generatedAt: Date = Date(), keyframeCount: Int, issues: [RouteCoverageIssue]) {
        self.generatedAt = generatedAt
        self.keyframeCount = keyframeCount
        self.issueCount = issues.count
        self.missingViewCount = issues.filter { $0.kind == .missingViews }.count
        self.repeatedViewCount = issues.filter { $0.kind == .repeatedViews }.count
        self.lowParallaxCount = issues.filter { $0.kind == .lowParallax }.count
        self.issues = issues
    }
}

public struct RobotValidPathRequest: Codable, Equatable, Sendable {
    public var bounds: AxisAlignedBounds
    public var floorConstraint: RouteFloorHeightConstraint
    public var rowSpacingMeters: Double
    public var columnSpacingMeters: Double
    public var frameInterval: TimeInterval

    public init(
        bounds: AxisAlignedBounds,
        floorConstraint: RouteFloorHeightConstraint = RouteFloorHeightConstraint(),
        rowSpacingMeters: Double = 0.75,
        columnSpacingMeters: Double = 0.75,
        frameInterval: TimeInterval = 1.0 / 30.0
    ) {
        self.bounds = bounds
        self.floorConstraint = floorConstraint
        self.rowSpacingMeters = rowSpacingMeters
        self.columnSpacingMeters = columnSpacingMeters
        self.frameInterval = frameInterval
    }
}

public struct RobotValidPathOutput: Codable, Equatable, Sendable {
    public var route: RobotPath
    public var navigationGraph: NavigationGraph
    public var routeURL: URL
    public var navigationGraphURL: URL
}

public struct RouteIntelligenceAnalyzer: Sendable {
    public init() {}

    public func apply(
        route: RobotPath,
        transformEditor: RouteTransformEditor,
        floorConstraint: RouteFloorHeightConstraint
    ) -> RobotPath {
        RobotPath(keyframes: route.keyframes.map { keyframe in
            let transformed = keyframe.pose.applying(transformEditor.transform)
            let constrained = Pose3D(
                position: floorConstraint.constrained(transformed.position),
                orientation: transformed.orientation.value
            )
            return RobotPathKeyframe(timestamp: keyframe.timestamp, pose: constrained, navigationTarget: keyframe.navigationTarget)
        })
    }

    public func confidence(
        sourceRoute: RobotPath,
        alignedRoute: RobotPath,
        anchors: [RouteAlignmentControlPoint],
        floorConstraint: RouteFloorHeightConstraint
    ) -> RouteConfidenceMetrics {
        let residual = meanAnchorResidual(anchors: anchors)
        let constrainedCount = alignedRoute.keyframes.filter {
            floorConstraint.constrained($0.pose.position) != $0.pose.position
        }.count
        var score = 0.45
        score += min(0.3, Double(anchors.count) * 0.075)
        score += min(0.2, Double(alignedRoute.keyframes.count) / 500.0)
        if let residual {
            score -= min(0.35, residual / 5.0)
        }
        if sourceRoute.keyframes.count < 10 {
            score -= 0.15
        }
        let confidence = min(max(score, 0), 1)
        var warnings: [String] = []
        if anchors.count < 3 {
            warnings.append("Fewer than three manual anchors; transform confidence is limited.")
        }
        if constrainedCount > 0 {
            warnings.append("\(constrainedCount) keyframes were adjusted by floor/height constraints.")
        }
        return RouteConfidenceMetrics(
            alignmentConfidence: confidence,
            anchorCount: anchors.count,
            meanAnchorResidualMeters: residual,
            routeKeyframeCount: alignedRoute.keyframes.count,
            constrainedKeyframeCount: constrainedCount,
            warnings: warnings
        )
    }

    public func analyzeCoverage(route: RobotPath, missingDistanceMeters: Double = 1.4, repeatedDistanceMeters: Double = 0.08, lowParallaxDegrees: Double = 3) -> RouteCoverageReport {
        let frames = route.keyframes
        var issues: [RouteCoverageIssue] = []
        guard !frames.isEmpty else {
            return RouteCoverageReport(keyframeCount: 0, issues: [])
        }
        for index in frames.indices {
            let frame = frames[index]
            if index > 0 {
                let previous = frames[index - 1]
                let delta = distance(frame.pose.position, previous.pose.position)
                if delta > missingDistanceMeters {
                    issues.append(RouteCoverageIssue(
                        id: "missing_\(index)",
                        kind: .missingViews,
                        frameIndex: index,
                        position: frame.pose.position,
                        severity: min(delta / missingDistanceMeters, 3) / 3,
                        note: "Gap from previous viewpoint is \(String(format: "%.2f", delta))m."
                    ))
                }
                if delta < repeatedDistanceMeters {
                    issues.append(RouteCoverageIssue(
                        id: "repeated_\(index)",
                        kind: .repeatedViews,
                        frameIndex: index,
                        position: frame.pose.position,
                        severity: 0.7,
                        note: "Viewpoint is nearly duplicated."
                    ))
                }
                let yawDelta = yawDifferenceDegrees(frame.pose.orientation.value, previous.pose.orientation.value)
                if delta < 0.25 && yawDelta < lowParallaxDegrees {
                    issues.append(RouteCoverageIssue(
                        id: "parallax_\(index)",
                        kind: .lowParallax,
                        frameIndex: index,
                        position: frame.pose.position,
                        severity: 0.65,
                        note: "Low motion and low yaw change reduce parallax."
                    ))
                }
            }
        }
        return RouteCoverageReport(keyframeCount: frames.count, issues: issues)
    }

    public func generateRobotValidPath(_ request: RobotValidPathRequest, outputDirectory: URL) throws -> RobotValidPathOutput {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let span = request.bounds.maximum - request.bounds.minimum
        let rows = max(1, Int(ceil(span.z / max(request.rowSpacingMeters, 0.1))) + 1)
        let columns = max(1, Int(ceil(span.x / max(request.columnSpacingMeters, 0.1))) + 1)
        let generator = RobotPathGenerator()
        let route = generator.generate(RobotPathGenerationRequest(
            strategy: .lawnmower(rows: rows, columns: columns),
            bounds: request.bounds,
            robotHeightMeters: request.floorConstraint.floorY + request.floorConstraint.minimumCameraHeight,
            frameInterval: request.frameInterval
        ))
        let constrained = apply(route: route, transformEditor: RouteTransformEditor(), floorConstraint: request.floorConstraint)
        let graph = navigationGraph(from: constrained)
        let routeURL = outputDirectory.appendingPathComponent("robot_valid_route.json")
        let graphURL = outputDirectory.appendingPathComponent("navigation_graph_editable.json")
        try JSONEncoder.robotVisionLabEncoder.encode(constrained).write(to: routeURL)
        try JSONEncoder.robotVisionLabEncoder.encode(graph).write(to: graphURL)
        return RobotValidPathOutput(route: constrained, navigationGraph: graph, routeURL: routeURL, navigationGraphURL: graphURL)
    }

    public func addNode(to graph: NavigationGraph, node: NavigationNode) -> NavigationGraph {
        var next = graph
        if !next.nodes.contains(where: { $0.id == node.id }) {
            next.nodes.append(node)
        }
        return next
    }

    public func removeNode(from graph: NavigationGraph, nodeID: String) -> NavigationGraph {
        NavigationGraph(
            nodes: graph.nodes.filter { $0.id != nodeID },
            edges: graph.edges.filter { $0.from != nodeID && $0.to != nodeID }
        )
    }

    public func addEdge(to graph: NavigationGraph, edge: NavigationEdge) -> NavigationGraph {
        var next = graph
        if next.nodes.contains(where: { $0.id == edge.from }) && next.nodes.contains(where: { $0.id == edge.to }) {
            next.edges.append(edge)
        }
        return next
    }

    private func navigationGraph(from route: RobotPath) -> NavigationGraph {
        let nodes = route.keyframes.enumerated().map { index, keyframe in
            NavigationNode(id: "route_\(index)", position: keyframe.pose.position)
        }
        let edges = zip(nodes, nodes.dropFirst()).map {
            NavigationEdge(from: $0.id, to: $1.id, traversalCost: distance($0.position, $1.position))
        }
        return NavigationGraph(nodes: nodes, edges: edges)
    }

    private func meanAnchorResidual(anchors: [RouteAlignmentControlPoint]) -> Double? {
        guard !anchors.isEmpty else { return nil }
        let total = anchors.reduce(0) { $0 + distance($1.arkitPosition, $1.scenePosition) }
        return total / Double(anchors.count)
    }

    private func yawDifferenceDegrees(_ lhs: simd_quatd, _ rhs: simd_quatd) -> Double {
        let delta = lhs.inverse * rhs
        return abs(delta.angle * 180.0 / .pi)
    }
}
