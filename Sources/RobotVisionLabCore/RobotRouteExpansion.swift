import Foundation
import simd

public struct RobotRouteExpansionRequest: Codable, Equatable, Sendable {
    public var sourceRoute: RobotPath
    public var lateralOffsetsMeters: [Double]
    public var cameraHeightOffsetsMeters: [Double]
    public var yawOffsetsDegrees: [Double]
    public var bounds: AxisAlignedBounds?
    public var navigationTarget: NavigationTarget?

    public init(
        sourceRoute: RobotPath,
        lateralOffsetsMeters: [Double] = [-0.25, 0, 0.25],
        cameraHeightOffsetsMeters: [Double] = [-0.08, 0, 0.08],
        yawOffsetsDegrees: [Double] = [-8, 0, 8],
        bounds: AxisAlignedBounds? = nil,
        navigationTarget: NavigationTarget? = nil
    ) {
        self.sourceRoute = sourceRoute
        self.lateralOffsetsMeters = lateralOffsetsMeters
        self.cameraHeightOffsetsMeters = cameraHeightOffsetsMeters
        self.yawOffsetsDegrees = yawOffsetsDegrees
        self.bounds = bounds
        self.navigationTarget = navigationTarget
    }
}

public struct RobotRouteExpansionReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var sourceKeyframeCount: Int
    public var expandedKeyframeCount: Int
    public var variantCount: Int
    public var lateralOffsetsMeters: [Double]
    public var cameraHeightOffsetsMeters: [Double]
    public var yawOffsetsDegrees: [Double]
    public var clippedKeyframeCount: Int
    public var expandedRouteURL: URL
    public var warnings: [String]

    public init(
        generatedAt: Date = Date(),
        sourceKeyframeCount: Int,
        expandedKeyframeCount: Int,
        variantCount: Int,
        lateralOffsetsMeters: [Double],
        cameraHeightOffsetsMeters: [Double],
        yawOffsetsDegrees: [Double],
        clippedKeyframeCount: Int,
        expandedRouteURL: URL,
        warnings: [String]
    ) {
        self.generatedAt = generatedAt
        self.sourceKeyframeCount = sourceKeyframeCount
        self.expandedKeyframeCount = expandedKeyframeCount
        self.variantCount = variantCount
        self.lateralOffsetsMeters = lateralOffsetsMeters
        self.cameraHeightOffsetsMeters = cameraHeightOffsetsMeters
        self.yawOffsetsDegrees = yawOffsetsDegrees
        self.clippedKeyframeCount = clippedKeyframeCount
        self.expandedRouteURL = expandedRouteURL
        self.warnings = warnings
    }
}

public struct RobotRouteExpansionOutput: Codable, Equatable, Sendable {
    public var route: RobotPath
    public var report: RobotRouteExpansionReport

    public init(route: RobotPath, report: RobotRouteExpansionReport) {
        self.route = route
        self.report = report
    }
}

public struct RobotRouteExpander: Sendable {
    public init() {}

    public func expand(
        request: RobotRouteExpansionRequest,
        outputDirectory: URL,
        generatedAt: Date = Date()
    ) throws -> RobotRouteExpansionOutput {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let lateralOffsets = request.lateralOffsetsMeters.isEmpty ? [0] : request.lateralOffsetsMeters
        let heightOffsets = request.cameraHeightOffsetsMeters.isEmpty ? [0] : request.cameraHeightOffsetsMeters
        let yawOffsets = request.yawOffsetsDegrees.isEmpty ? [0] : request.yawOffsetsDegrees

        var keyframes: [RobotPathKeyframe] = []
        var clippedCount = 0
        let source = request.sourceRoute.keyframes
        let frameInterval = estimatedFrameInterval(source)

        for sourceIndex in source.indices {
            let base = source[sourceIndex]
            let direction = routeDirection(at: sourceIndex, in: source)
            let lateral = SIMD3<Double>(-direction.z, 0, direction.x)

            for lateralOffset in lateralOffsets {
                for heightOffset in heightOffsets {
                    for yawOffset in yawOffsets {
                        let position = base.pose.position
                            + (lateral * lateralOffset)
                            + SIMD3<Double>(0, heightOffset, 0)
                        let clippedPosition = request.bounds.map { clip(position, to: $0) } ?? position
                        if clippedPosition != position {
                            clippedCount += 1
                        }
                        let yawRotation = simd_quatd(
                            angle: yawOffset * .pi / 180.0,
                            axis: SIMD3<Double>(0, 1, 0)
                        )
                        let pose = Pose3D(
                            position: clippedPosition,
                            orientation: yawRotation * base.pose.orientation.value
                        )
                        keyframes.append(
                            RobotPathKeyframe(
                                timestamp: Double(keyframes.count) * frameInterval,
                                pose: pose,
                                navigationTarget: base.navigationTarget ?? request.navigationTarget
                            )
                        )
                    }
                }
            }
        }

        let route = RobotPath(keyframes: keyframes)
        let routeURL = outputDirectory.appendingPathComponent("expanded_robot_route.json")
        try JSONEncoder.robotVisionLabEncoder.encode(route).write(to: routeURL)

        let variantCount = lateralOffsets.count * heightOffsets.count * yawOffsets.count
        let report = RobotRouteExpansionReport(
            generatedAt: generatedAt,
            sourceKeyframeCount: source.count,
            expandedKeyframeCount: route.keyframes.count,
            variantCount: variantCount,
            lateralOffsetsMeters: lateralOffsets,
            cameraHeightOffsetsMeters: heightOffsets,
            yawOffsetsDegrees: yawOffsets,
            clippedKeyframeCount: clippedCount,
            expandedRouteURL: routeURL,
            warnings: warnings(sourceKeyframeCount: source.count, variantCount: variantCount, clippedKeyframeCount: clippedCount)
        )
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(
            to: outputDirectory.appendingPathComponent("route_expansion_report.json")
        )

        return RobotRouteExpansionOutput(route: route, report: report)
    }

    private func estimatedFrameInterval(_ keyframes: [RobotPathKeyframe]) -> TimeInterval {
        guard keyframes.count > 1 else { return 1.0 / 30.0 }
        let timestamps = keyframes.map(\.timestamp).sorted()
        let deltas = zip(timestamps, timestamps.dropFirst()).map { max(0, $1 - $0) }.filter { $0 > 0 }
        guard !deltas.isEmpty else { return 1.0 / 30.0 }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    private func routeDirection(at index: Int, in keyframes: [RobotPathKeyframe]) -> SIMD3<Double> {
        let current = keyframes[index].pose.position
        let neighbor: SIMD3<Double>
        if keyframes.indices.contains(index + 1) {
            neighbor = keyframes[index + 1].pose.position
        } else if keyframes.indices.contains(index - 1) {
            neighbor = keyframes[index - 1].pose.position
        } else {
            return SIMD3<Double>(0, 0, -1)
        }
        let delta = SIMD3<Double>(neighbor.x - current.x, 0, neighbor.z - current.z)
        let length = simd_length(delta)
        guard length > 0.0001 else { return SIMD3<Double>(0, 0, -1) }
        return delta / length
    }

    private func clip(_ position: SIMD3<Double>, to bounds: AxisAlignedBounds) -> SIMD3<Double> {
        SIMD3<Double>(
            position.x.clamped(to: bounds.minimum.x...bounds.maximum.x),
            position.y.clamped(to: bounds.minimum.y...bounds.maximum.y),
            position.z.clamped(to: bounds.minimum.z...bounds.maximum.z)
        )
    }

    private func warnings(sourceKeyframeCount: Int, variantCount: Int, clippedKeyframeCount: Int) -> [String] {
        var warnings: [String] = []
        if sourceKeyframeCount < 10 {
            warnings.append("Source route has fewer than 10 keyframes; expanded route coverage is limited.")
        }
        if variantCount > 100 {
            warnings.append("Route expansion creates more than 100 variants per source frame; output size may grow quickly.")
        }
        if clippedKeyframeCount > 0 {
            warnings.append("\(clippedKeyframeCount) expanded keyframes were clipped to scene bounds.")
        }
        return warnings
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
