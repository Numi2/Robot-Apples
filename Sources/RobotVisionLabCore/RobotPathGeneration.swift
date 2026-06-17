import Foundation
import simd

public enum RobotPathGenerationStrategy: Codable, Equatable, Sendable {
    case lawnmower(rows: Int, columns: Int)
    case randomWalk(frameCount: Int, stepMeters: Double, seed: UInt64)
}

public struct RobotPathGenerationRequest: Codable, Equatable, Sendable {
    public var strategy: RobotPathGenerationStrategy
    public var bounds: AxisAlignedBounds
    public var robotHeightMeters: Double
    public var frameInterval: TimeInterval
    public var navigationTarget: NavigationTarget?

    public init(
        strategy: RobotPathGenerationStrategy,
        bounds: AxisAlignedBounds,
        robotHeightMeters: Double = 0,
        frameInterval: TimeInterval = 1.0 / 30.0,
        navigationTarget: NavigationTarget? = nil
    ) {
        self.strategy = strategy
        self.bounds = bounds
        self.robotHeightMeters = robotHeightMeters
        self.frameInterval = frameInterval
        self.navigationTarget = navigationTarget
    }
}

public struct RobotPathGenerator: Sendable {
    public init() {}

    public func generate(_ request: RobotPathGenerationRequest) -> RobotPath {
        switch request.strategy {
        case .lawnmower(let rows, let columns):
            return lawnmowerPath(rows: rows, columns: columns, request: request)
        case .randomWalk(let frameCount, let stepMeters, let seed):
            return randomWalkPath(frameCount: frameCount, stepMeters: stepMeters, seed: seed, request: request)
        }
    }

    private func lawnmowerPath(rows: Int, columns: Int, request: RobotPathGenerationRequest) -> RobotPath {
        let rows = max(1, rows)
        let columns = max(1, columns)
        let xValues = interpolatedValues(
            from: request.bounds.minimum.x,
            to: request.bounds.maximum.x,
            count: columns
        )
        let zValues = interpolatedValues(
            from: request.bounds.minimum.z,
            to: request.bounds.maximum.z,
            count: rows
        )

        var keyframes: [RobotPathKeyframe] = []
        keyframes.reserveCapacity(rows * columns)
        for row in 0..<rows {
            let rowXValues = row.isMultiple(of: 2) ? xValues : xValues.reversed()
            for x in rowXValues {
                let index = keyframes.count
                keyframes.append(
                    RobotPathKeyframe(
                        timestamp: Double(index) * request.frameInterval,
                        pose: pose(
                            at: SIMD3<Double>(x, request.robotHeightMeters, zValues[row]),
                            request: request
                        ),
                        navigationTarget: request.navigationTarget
                    )
                )
            }
        }
        return RobotPath(keyframes: keyframes)
    }

    private func randomWalkPath(frameCount: Int, stepMeters: Double, seed: UInt64, request: RobotPathGenerationRequest) -> RobotPath {
        let frameCount = max(0, frameCount)
        guard frameCount > 0 else { return RobotPath(keyframes: []) }

        var rng = PathSeededGenerator(seed: seed)
        var position = SIMD3<Double>(
            (request.bounds.minimum.x + request.bounds.maximum.x) / 2.0,
            request.robotHeightMeters,
            (request.bounds.minimum.z + request.bounds.maximum.z) / 2.0
        )
        var keyframes: [RobotPathKeyframe] = []
        keyframes.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            if index > 0 {
                let angle = rng.nextUnit() * 2.0 * .pi
                position.x += cos(angle) * stepMeters
                position.z += sin(angle) * stepMeters
                position.x = position.x.clamped(to: request.bounds.minimum.x...request.bounds.maximum.x)
                position.z = position.z.clamped(to: request.bounds.minimum.z...request.bounds.maximum.z)
            }
            keyframes.append(
                RobotPathKeyframe(
                    timestamp: Double(index) * request.frameInterval,
                    pose: pose(at: position, request: request),
                    navigationTarget: request.navigationTarget
                )
            )
        }

        return RobotPath(keyframes: keyframes)
    }

    private func interpolatedValues(from start: Double, to end: Double, count: Int) -> [Double] {
        guard count > 1 else {
            return [(start + end) / 2.0]
        }
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return start + ((end - start) * t)
        }
    }

    private func pose(at position: SIMD3<Double>, request: RobotPathGenerationRequest) -> Pose3D {
        let target = request.navigationTarget?.position ?? SIMD3<Double>(
            (request.bounds.minimum.x + request.bounds.maximum.x) / 2.0,
            (request.bounds.minimum.y + request.bounds.maximum.y) / 2.0,
            (request.bounds.minimum.z + request.bounds.maximum.z) / 2.0
        )
        return Pose3D(position: position, orientation: cameraOrientation(from: position, to: target))
    }

    private func cameraOrientation(from position: SIMD3<Double>, to target: SIMD3<Double>) -> simd_quatd {
        var direction = target - position
        if simd_length_squared(direction) < 0.0001 {
            direction = SIMD3<Double>(0, 0, -1)
        } else {
            direction = simd_normalize(direction)
        }
        return simd_quatd(from: SIMD3<Double>(0, 0, -1), to: direction)
    }
}

private struct PathSeededGenerator: Sendable {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xA076_1D64_78BD_642F : seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value = value ^ (value >> 31)
        return Double(value & 0x1F_FFFF) / Double(0x1F_FFFF)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
