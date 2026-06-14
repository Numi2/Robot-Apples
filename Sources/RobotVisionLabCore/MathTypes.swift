import Foundation
import simd

public struct Pose3D: Codable, Equatable, Sendable {
    public var position: SIMD3<Double>
    public var orientation: QuaternionCodable

    public init(position: SIMD3<Double>, orientation: simd_quatd = simd_quatd(angle: 0, axis: SIMD3<Double>(0, 1, 0))) {
        self.position = position
        self.orientation = QuaternionCodable(orientation)
    }

    public func applying(_ transform: Transform3D) -> Pose3D {
        let scaledPosition = position * transform.scale
        let rotatedPosition = transform.rotation.value.act(scaledPosition)
        let nextPosition = rotatedPosition + transform.translation
        let nextOrientation = transform.rotation.value * orientation.value
        return Pose3D(position: nextPosition, orientation: nextOrientation)
    }
}

public struct Transform3D: Codable, Equatable, Sendable {
    public var translation: SIMD3<Double>
    public var rotation: QuaternionCodable
    public var scale: SIMD3<Double>

    public init(
        translation: SIMD3<Double> = SIMD3<Double>(0, 0, 0),
        rotation: simd_quatd = simd_quatd(angle: 0, axis: SIMD3<Double>(0, 1, 0)),
        scale: SIMD3<Double> = SIMD3<Double>(1, 1, 1)
    ) {
        self.translation = translation
        self.rotation = QuaternionCodable(rotation)
        self.scale = scale
    }

    public static let identity = Transform3D()
}

public struct AxisAlignedBounds: Codable, Equatable, Sendable {
    public var minimum: SIMD3<Double>
    public var maximum: SIMD3<Double>

    public init(minimum: SIMD3<Double>, maximum: SIMD3<Double>) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct QuaternionCodable: Codable, Equatable, Sendable {
    public var vector: SIMD4<Double>

    public init(_ value: simd_quatd) {
        self.vector = value.vector
    }

    public var value: simd_quatd {
        simd_quatd(vector: vector)
    }
}
