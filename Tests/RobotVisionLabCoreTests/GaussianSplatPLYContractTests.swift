import XCTest
import SplatIO
@testable import RobotVisionLabCore
import simd

final class GaussianSplatPLYContractTests: XCTestCase {
    func testNativePLYLoaderReadsStandardGaussianSplatComponents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianSplatPLYContractTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plyURL = root.appendingPathComponent("standard.ply")
        try """
        ply
        format ascii 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        0 0 0 255 0 0 0 -3 -4 -5 1 0 0 0

        """.write(to: plyURL, atomically: true, encoding: .utf8)

        let cloud = try GaussianSplatCloudLoader().load(url: plyURL)
        let splat = try XCTUnwrap(cloud.splats.first)

        XCTAssertEqual(splat.color.x, 1, accuracy: 0.0001)
        XCTAssertEqual(splat.color.y, 0, accuracy: 0.0001)
        XCTAssertEqual(splat.color.z, 0, accuracy: 0.0001)
        XCTAssertEqual(splat.color.w, 0.5, accuracy: 0.0001)
        XCTAssertEqual(splat.scale.x, exp(-3), accuracy: 0.0001)
        XCTAssertEqual(splat.scale.y, exp(-4), accuracy: 0.0001)
        XCTAssertEqual(splat.scale.z, exp(-5), accuracy: 0.0001)
        XCTAssertEqual(splat.rotation.x, 0, accuracy: 0.0001)
        XCTAssertEqual(splat.rotation.y, 0, accuracy: 0.0001)
        XCTAssertEqual(splat.rotation.z, 0, accuracy: 0.0001)
        XCTAssertEqual(splat.rotation.w, 1, accuracy: 0.0001)
    }

    func testNativePLYLoaderDecodesStandardFDCColorsAsSH0() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plyURL = root.appendingPathComponent("fdc.ply")
        try """
        ply
        format ascii 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        0 0 0 0 0 0 0 -3 -3 -3 1 0 0 0

        """.write(to: plyURL, atomically: true, encoding: .utf8)

        let cloud = try GaussianSplatCloudLoader().load(url: plyURL)
        let splat = try XCTUnwrap(cloud.splats.first)

        XCTAssertEqual(splat.color.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(splat.color.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(splat.color.z, 0.5, accuracy: 0.0001)
    }

    func testNativeCloudLoaderReadsSPZThroughSplatIO() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let spzURL = root.appendingPathComponent("one-point.spz")
        let writer = try SPZSceneWriter(toFileAtPath: spzURL.path)
        try await writer.start(numPoints: 1)
        try await writer.write([
            SplatPoint(
                position: SIMD3<Float>(1, 2, 3),
                color: .sRGBUInt8(SIMD3<UInt8>(64, 128, 255)),
                opacity: .linearFloat(0.75),
                scale: .linearFloat(SIMD3<Float>(0.02, 0.03, 0.04)),
                rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            )
        ])
        try await writer.close()

        let cloud = try GaussianSplatCloudLoader().load(url: spzURL)
        let splat = try XCTUnwrap(cloud.splats.first)

        XCTAssertEqual(cloud.splats.count, 1)
        XCTAssertEqual(splat.position.x, 1, accuracy: 0.01)
        XCTAssertEqual(splat.position.y, 2, accuracy: 0.01)
        XCTAssertEqual(splat.position.z, 3, accuracy: 0.01)
        XCTAssertEqual(splat.color.w, 0.75, accuracy: 0.02)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianSplatPLYContractTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
