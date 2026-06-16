import Metal
@testable import RobotSceneStudioSplatViewer
import XCTest

final class MetalSpatialOverlayShaderTests: XCTestCase {
    func testSpatialOverlayShaderCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device is available.")
        }

        let library = try device.makeLibrary(
            source: MetalSplatterSpatialOverlayShaders.lineOverlay,
            options: nil
        )

        XCTAssertNotNil(library.makeFunction(name: "robot_spatial_overlay_vertex"))
        XCTAssertNotNil(library.makeFunction(name: "robot_spatial_overlay_fragment"))
    }
}
