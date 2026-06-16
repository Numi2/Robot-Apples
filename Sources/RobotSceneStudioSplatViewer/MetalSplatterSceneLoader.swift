import Foundation
import Metal
import MetalSplatter
import simd
import SplatIO

public enum MetalSplatterSceneLoader {
    public static func makeRenderer(
        for url: URL,
        device: MTLDevice,
        colorFormat: MTLPixelFormat,
        depthFormat: MTLPixelFormat,
        sampleCount: Int,
        maxViewCount: Int,
        maxSimultaneousRenders: Int,
        highQualityDepth: Bool = true
    ) async throws -> SplatRenderer {
        let renderer = try SplatRenderer(
            device: device,
            colorFormat: colorFormat,
            depthFormat: depthFormat,
            sampleCount: sampleCount,
            maxViewCount: maxViewCount,
            maxSimultaneousRenders: maxSimultaneousRenders,
            highQualityDepth: highQualityDepth
        )
        let reader = try AutodetectSceneReader(url)
        let points = try await reader.readAll()
        let chunk = try SplatChunk(device: device, from: points)
        await renderer.addChunk(chunk)
        return renderer
    }
}

public enum MetalSplatterViewerConstants {
    public static let maxSimultaneousRenders = 3
    public static let rotationRadiansPerSecond: Float = 7 * .pi / 180
    public static let rotationAxis = SIMD3<Float>(0, 1, 0)
    public static let modelCenterZ: Float = -8
    public static let fieldOfViewYRadians: Float = 65 * .pi / 180
}

public let metalSplatterIdentityMatrixPayload: [Float] = [
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
]

public func metalSplatterMatrix(from payload: [Float]) -> simd_float4x4 {
    guard payload.count == 16 else {
        return matrix_identity_float4x4
    }
    return simd_float4x4(columns: (
        SIMD4<Float>(payload[0], payload[1], payload[2], payload[3]),
        SIMD4<Float>(payload[4], payload[5], payload[6], payload[7]),
        SIMD4<Float>(payload[8], payload[9], payload[10], payload[11]),
        SIMD4<Float>(payload[12], payload[13], payload[14], payload[15])
    ))
}

public func metalSplatterRotationMatrix(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let axisLength = max(sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z), .leastNonzeroMagnitude)
    let unitAxis = axis / axisLength
    let cosine = cosf(radians)
    let sine = sinf(radians)
    let oneMinusCosine = 1 - cosine
    let x = unitAxis.x
    let y = unitAxis.y
    let z = unitAxis.z
    return simd_float4x4(columns: (
        SIMD4<Float>(cosine + x * x * oneMinusCosine, y * x * oneMinusCosine + z * sine, z * x * oneMinusCosine - y * sine, 0),
        SIMD4<Float>(x * y * oneMinusCosine - z * sine, cosine + y * y * oneMinusCosine, z * y * oneMinusCosine + x * sine, 0),
        SIMD4<Float>(x * z * oneMinusCosine + y * sine, y * z * oneMinusCosine - x * sine, cosine + z * z * oneMinusCosine, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

public func metalSplatterTranslationMatrix(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

public func metalSplatterPerspectiveMatrix(
    fovyRadians fovy: Float,
    aspectRatio: Float,
    nearZ: Float,
    farZ: Float
) -> simd_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return simd_float4x4(columns: (
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, zs * nearZ, 0)
    ))
}

public func metalSplatterDefaultModelViewMatrix(rotationRadians: Float, sceneTransform: simd_float4x4 = matrix_identity_float4x4) -> simd_float4x4 {
    let rotation = metalSplatterRotationMatrix(
        radians: rotationRadians,
        axis: MetalSplatterViewerConstants.rotationAxis
    )
    let translation = metalSplatterTranslationMatrix(0, 0, MetalSplatterViewerConstants.modelCenterZ)
    let commonUpCalibration = metalSplatterRotationMatrix(radians: Float.pi, axis: SIMD3<Float>(0, 0, 1))
    return translation * rotation * commonUpCalibration * sceneTransform
}

public func metalSplatterInteractiveModelViewMatrix(
    autoRotationRadians: Float,
    yawRadians: Float,
    pitchRadians: Float,
    distanceScale: Float,
    sceneTransform: simd_float4x4 = matrix_identity_float4x4
) -> simd_float4x4 {
    let clampedDistance = min(max(distanceScale, 0.35), 4)
    let translation = metalSplatterTranslationMatrix(
        0,
        0,
        MetalSplatterViewerConstants.modelCenterZ * clampedDistance
    )
    let yaw = metalSplatterRotationMatrix(
        radians: autoRotationRadians + yawRadians,
        axis: SIMD3<Float>(0, 1, 0)
    )
    let pitch = metalSplatterRotationMatrix(
        radians: min(max(pitchRadians, -1.2), 1.2),
        axis: SIMD3<Float>(1, 0, 0)
    )
    let commonUpCalibration = metalSplatterRotationMatrix(radians: Float.pi, axis: SIMD3<Float>(0, 0, 1))
    return translation * pitch * yaw * commonUpCalibration * sceneTransform
}
