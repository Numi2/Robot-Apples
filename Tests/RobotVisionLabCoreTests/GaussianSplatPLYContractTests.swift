import XCTest
@testable import RobotVisionLabCore

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
}
