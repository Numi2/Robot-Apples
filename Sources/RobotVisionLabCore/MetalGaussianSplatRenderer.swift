import Foundation
import simd

public struct RenderableGaussianSplat: Codable, Equatable, Sendable {
    public var position: SIMD3<Float>
    public var color: SIMD4<Float>
    public var scale: SIMD3<Float>
    public var rotation: SIMD4<Float>

    public init(
        position: SIMD3<Float>,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        scale: SIMD3<Float> = SIMD3<Float>(0.015, 0.015, 0.015),
        rotation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    ) {
        self.position = position
        self.color = color
        self.scale = scale
        self.rotation = rotation
    }
}

public struct RenderableGaussianSplatCloud: Codable, Equatable, Sendable {
    public var sourceURL: URL
    public var splats: [RenderableGaussianSplat]
    public var bounds: AxisAlignedBounds
    public var properties: Set<GaussianSplatProperty>

    public init(
        sourceURL: URL,
        splats: [RenderableGaussianSplat],
        bounds: AxisAlignedBounds,
        properties: Set<GaussianSplatProperty>
    ) {
        self.sourceURL = sourceURL
        self.splats = splats
        self.bounds = bounds
        self.properties = properties
    }
}

public struct MetalSplatRenderProducts: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var rgbURL: URL
    public var depthURL: URL
    public var visibilityURL: URL
    public var tileBinURL: URL
    public var visibleSplatCount: Int
    public var drawCommandCount: Int
    public var totalSplatCount: Int

    public init(
        frameIndex: Int,
        rgbURL: URL,
        depthURL: URL,
        visibilityURL: URL,
        tileBinURL: URL,
        visibleSplatCount: Int,
        drawCommandCount: Int,
        totalSplatCount: Int
    ) {
        self.frameIndex = frameIndex
        self.rgbURL = rgbURL
        self.depthURL = depthURL
        self.visibilityURL = visibilityURL
        self.tileBinURL = tileBinURL
        self.visibleSplatCount = visibleSplatCount
        self.drawCommandCount = drawCommandCount
        self.totalSplatCount = totalSplatCount
    }
}

public struct MetalSplatRenderReport: Codable, Equatable, Sendable {
    public var sceneID: String
    public var renderedAt: Date
    public var frameProducts: [MetalSplatRenderProducts]
    public var diagnostics: [String]

    public init(
        sceneID: String,
        renderedAt: Date = Date(),
        frameProducts: [MetalSplatRenderProducts],
        diagnostics: [String] = []
    ) {
        self.sceneID = sceneID
        self.renderedAt = renderedAt
        self.frameProducts = frameProducts
        self.diagnostics = diagnostics
    }
}

public struct MetalSplatRenderReportWriter: Sendable {
    public init() {}

    public func write(_ report: MetalSplatRenderReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }
}

public struct ProjectedGaussianSplat: Codable, Equatable, Sendable {
    public var splatIndex: Int
    public var centerPixels: SIMD2<Float>
    public var depthMeters: Float
    public var covariance2D: SIMD4<Float>
    public var majorRadiusPixels: Float
    public var minorRadiusPixels: Float
    public var tileRange: MetalTileRange
    public var color: SIMD4<Float>

    public init(
        splatIndex: Int,
        centerPixels: SIMD2<Float>,
        depthMeters: Float,
        covariance2D: SIMD4<Float>,
        majorRadiusPixels: Float,
        minorRadiusPixels: Float,
        tileRange: MetalTileRange,
        color: SIMD4<Float>
    ) {
        self.splatIndex = splatIndex
        self.centerPixels = centerPixels
        self.depthMeters = depthMeters
        self.covariance2D = covariance2D
        self.majorRadiusPixels = majorRadiusPixels
        self.minorRadiusPixels = minorRadiusPixels
        self.tileRange = tileRange
        self.color = color
    }
}

public struct MetalTileRange: Codable, Equatable, Sendable {
    public var minX: Int
    public var minY: Int
    public var maxX: Int
    public var maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public struct MetalTileBin: Codable, Equatable, Sendable {
    public var tileX: Int
    public var tileY: Int
    public var splatIndexesBackToFront: [Int]

    public init(tileX: Int, tileY: Int, splatIndexesBackToFront: [Int]) {
        self.tileX = tileX
        self.tileY = tileY
        self.splatIndexesBackToFront = splatIndexesBackToFront
    }
}

public struct MetalTileBinReport: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var tileSize: Int
    public var tileColumns: Int
    public var tileRows: Int
    public var projectedSplatCount: Int
    public var drawCommandCount: Int
    public var bins: [MetalTileBin]

    public init(
        frameIndex: Int,
        tileSize: Int,
        tileColumns: Int,
        tileRows: Int,
        projectedSplatCount: Int,
        drawCommandCount: Int,
        bins: [MetalTileBin]
    ) {
        self.frameIndex = frameIndex
        self.tileSize = tileSize
        self.tileColumns = tileColumns
        self.tileRows = tileRows
        self.projectedSplatCount = projectedSplatCount
        self.drawCommandCount = drawCommandCount
        self.bins = bins
    }
}

public struct GaussianSplatCloudLoader: Sendable {
    public init() {}

    public func load(url: URL) throws -> RenderableGaussianSplatCloud {
        switch url.pathExtension.lowercased() {
        case "ply":
            return try loadASCIIPLY(url: url)
        default:
            throw GaussianSplatImportError.unsupportedFormat(url.pathExtension)
        }
    }

    public func loadASCIIPLY(url: URL) throws -> RenderableGaussianSplatCloud {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "ply" else {
            throw GaussianSplatImportError.invalidPLY("Missing ply magic header.")
        }
        guard lines.contains("format ascii 1.0") else {
            throw GaussianSplatImportError.invalidPLY("Only ASCII PLY files are supported by the native Metal loader.")
        }
        guard let endHeaderIndex = lines.firstIndex(of: "end_header") else {
            throw GaussianSplatImportError.invalidPLY("Missing end_header.")
        }

        var vertexCount = 0
        var vertexProperties: [String] = []
        var readingVertexElement = false
        for line in lines[..<endHeaderIndex] {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count == 3, parts[0] == "element", parts[1] == "vertex", let count = Int(parts[2]) {
                vertexCount = count
                readingVertexElement = true
                continue
            }
            if parts.first == "element", parts.dropFirst().first != "vertex" {
                readingVertexElement = false
            }
            if readingVertexElement, parts.count >= 3, parts[0] == "property" {
                vertexProperties.append(parts.last ?? "")
            }
        }

        guard let xIndex = vertexProperties.firstIndex(of: "x"),
              let yIndex = vertexProperties.firstIndex(of: "y"),
              let zIndex = vertexProperties.firstIndex(of: "z") else {
            throw GaussianSplatImportError.invalidPLY("PLY vertices must contain x, y, and z properties.")
        }

        let redIndex = vertexProperties.firstIndex(of: "red") ?? vertexProperties.firstIndex(of: "f_dc_0")
        let greenIndex = vertexProperties.firstIndex(of: "green") ?? vertexProperties.firstIndex(of: "f_dc_1")
        let blueIndex = vertexProperties.firstIndex(of: "blue") ?? vertexProperties.firstIndex(of: "f_dc_2")
        let opacityIndex = vertexProperties.firstIndex(of: "opacity")
        let scale0Index = vertexProperties.firstIndex(of: "scale_0") ?? vertexProperties.firstIndex(of: "scale")
        let scale1Index = vertexProperties.firstIndex(of: "scale_1")
        let scale2Index = vertexProperties.firstIndex(of: "scale_2")
        let rot0Index = vertexProperties.firstIndex(of: "rot_0") ?? vertexProperties.firstIndex(of: "rotation_0")
        let rot1Index = vertexProperties.firstIndex(of: "rot_1") ?? vertexProperties.firstIndex(of: "rotation_1")
        let rot2Index = vertexProperties.firstIndex(of: "rot_2") ?? vertexProperties.firstIndex(of: "rotation_2")
        let rot3Index = vertexProperties.firstIndex(of: "rot_3") ?? vertexProperties.firstIndex(of: "rotation_3")

        var splats: [RenderableGaussianSplat] = []
        splats.reserveCapacity(vertexCount)
        var minimum = SIMD3<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maximum = SIMD3<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)

        for line in lines.dropFirst(endHeaderIndex + 1).prefix(vertexCount) {
            let values = line.split(separator: " ")
            guard values.count >= vertexProperties.count,
                  let x = Float(values[xIndex]),
                  let y = Float(values[yIndex]),
                  let z = Float(values[zIndex]) else {
                throw GaussianSplatImportError.invalidPLY("Invalid vertex row.")
            }

            let rgb = SIMD3<Float>(
                redIndex.flatMap { Float(colorComponent: values[$0]) } ?? 1,
                greenIndex.flatMap { Float(colorComponent: values[$0]) } ?? 1,
                blueIndex.flatMap { Float(colorComponent: values[$0]) } ?? 1
            )
            let opacity = opacityIndex.flatMap { Float(opacityComponent: values[$0]) } ?? 1
            let scale = SIMD3<Float>(
                scale0Index.flatMap { Float(scaleComponent: values[$0]) } ?? 0.015,
                scale1Index.flatMap { Float(scaleComponent: values[$0]) } ?? scale0Index.flatMap { Float(scaleComponent: values[$0]) } ?? 0.015,
                scale2Index.flatMap { Float(scaleComponent: values[$0]) } ?? scale0Index.flatMap { Float(scaleComponent: values[$0]) } ?? 0.015
            )
            let rotation = SIMD4<Float>(
                rot0Index.flatMap { Float(values[$0]) } ?? 0,
                rot1Index.flatMap { Float(values[$0]) } ?? 0,
                rot2Index.flatMap { Float(values[$0]) } ?? 0,
                rot3Index.flatMap { Float(values[$0]) } ?? 1
            )
            let position = SIMD3<Float>(x, y, z)
            splats.append(RenderableGaussianSplat(
                position: position,
                color: SIMD4<Float>(rgb.x, rgb.y, rgb.z, opacity),
                scale: scale,
                rotation: rotation
            ))
            minimum = min(minimum, SIMD3<Double>(Double(x), Double(y), Double(z)))
            maximum = max(maximum, SIMD3<Double>(Double(x), Double(y), Double(z)))
        }

        return RenderableGaussianSplatCloud(
            sourceURL: url,
            splats: splats,
            bounds: AxisAlignedBounds(minimum: minimum, maximum: maximum),
            properties: detectedProperties(from: Set(vertexProperties))
        )
    }

    private func detectedProperties(from propertyNames: Set<String>) -> Set<GaussianSplatProperty> {
        var properties: Set<GaussianSplatProperty> = [.position]
        if propertyNames.isSuperset(of: ["red", "green", "blue"]) || propertyNames.isSuperset(of: ["f_dc_0", "f_dc_1", "f_dc_2"]) {
            properties.insert(.color)
        }
        if propertyNames.contains("opacity") {
            properties.insert(.opacity)
        }
        if propertyNames.contains("scale_0") || propertyNames.contains("scale") {
            properties.insert(.scale)
        }
        if propertyNames.contains("rot_0") || propertyNames.contains("rotation_0") {
            properties.insert(.rotation)
        }
        if propertyNames.contains(where: { $0.hasPrefix("f_rest_") }) {
            properties.insert(.sphericalHarmonics)
        }
        return properties
    }
}

private extension Float {
    init?(colorComponent value: String.SubSequence) {
        if let integer = Int(value) {
            self = max(0, min(255, Float(integer))) / 255
        } else if let float = Float(value) {
            self = max(0, min(1, float))
        } else {
            return nil
        }
    }

    init?(opacityComponent value: String.SubSequence) {
        guard let float = Float(value) else { return nil }
        self = max(0, min(1, 1 / (1 + exp(-float))))
    }

    init?(scaleComponent value: String.SubSequence) {
        guard let float = Float(value) else { return nil }
        self = max(0.001, min(0.5, exp(float)))
    }
}

#if canImport(Metal)
import Metal

private struct MetalSplatVertex {
    var projectedCenterDepth: SIMD4<Float>
    var covarianceRadius: SIMD4<Float>
    var colorOpacity: SIMD4<Float>
}

private struct MetalCameraUniforms {
    var cameraPosition: SIMD4<Float>
    var focalPrincipal: SIMD4<Float>
    var viewport: SIMD4<Float>
}

public final class MetalGaussianSplatRenderer: SplatRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else {
            throw MetalGaussianSplatRenderError.deviceUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalGaussianSplatRenderError.commandQueueUnavailable
        }
        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = try Self.makePipeline(device: device)
    }

    public func render(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig, outputDirectory: URL) async throws {
        try renderSynchronously(frame: frame, scene: scene, cameraRig: cameraRig, outputDirectory: outputDirectory)
    }

    public func renderSynchronously(
        frame: DatasetFrame,
        scene: GaussianSplatScene,
        cameraRig: RobotCameraRig,
        outputDirectory: URL
    ) throws {
        guard case .importedPLY(let url) = scene.source else {
            throw MetalGaussianSplatRenderError.unsupportedSceneSource
        }
        let cloud = try GaussianSplatCloudLoader().load(url: url)
        _ = try render(frame: frame, scene: scene, cameraRig: cameraRig, cloud: cloud, outputDirectory: outputDirectory)
    }

    public func renderDataset(_ manifest: DatasetManifest, outputDirectory: URL) throws -> MetalSplatRenderReport {
        guard case .importedPLY(let url) = manifest.scene.source else {
            throw MetalGaussianSplatRenderError.unsupportedSceneSource
        }
        let cloud = try GaussianSplatCloudLoader().load(url: url)
        let products = try manifest.frames.map {
            try render(
                frame: $0,
                scene: manifest.scene,
                cameraRig: manifest.cameraRig,
                cloud: cloud,
                outputDirectory: outputDirectory
            )
        }
        return MetalSplatRenderReport(sceneID: manifest.scene.id, frameProducts: products)
    }

    private func render(
        frame: DatasetFrame,
        scene: GaussianSplatScene,
        cameraRig: RobotCameraRig,
        cloud: RenderableGaussianSplatCloud,
        outputDirectory: URL
    ) throws -> MetalSplatRenderProducts {
        let width = cameraRig.intrinsics.width
        let height = cameraRig.intrinsics.height
        let prepared = prepareTileSortedSplats(
            cloud.splats,
            frame: frame,
            cameraRig: cameraRig,
            width: width,
            height: height,
            tileSize: 16
        )
        let vertices = prepared.drawSplats.map { splat in
            MetalSplatVertex(
                projectedCenterDepth: SIMD4<Float>(
                    splat.centerPixels.x,
                    splat.centerPixels.y,
                    splat.depthMeters,
                    1
                ),
                covarianceRadius: SIMD4<Float>(
                    splat.covariance2D.x,
                    splat.covariance2D.y,
                    splat.covariance2D.z,
                    splat.majorRadiusPixels
                ),
                colorOpacity: splat.color
            )
        }

        guard !vertices.isEmpty else {
            throw MetalGaussianSplatRenderError.noVisibleSplats
        }
        guard let splatBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<MetalSplatVertex>.stride * vertices.count,
            options: [.storageModeShared]
        ) else {
            throw MetalGaussianSplatRenderError.bufferAllocationFailed
        }

        var uniforms = MetalCameraUniforms(
            cameraPosition: SIMD4<Float>(
                Float(frame.cameraPose.position.x),
                Float(frame.cameraPose.position.y),
                Float(frame.cameraPose.position.z),
                1
            ),
            focalPrincipal: SIMD4<Float>(
                Float(cameraRig.intrinsics.focalLengthPixels.x),
                Float(cameraRig.intrinsics.focalLengthPixels.y),
                Float(cameraRig.intrinsics.principalPointPixels.x),
                Float(cameraRig.intrinsics.principalPointPixels.y)
            ),
            viewport: SIMD4<Float>(Float(width), Float(height), 0, 0)
        )
        guard let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<MetalCameraUniforms>.stride,
            options: [.storageModeShared]
        ) else {
            throw MetalGaussianSplatRenderError.bufferAllocationFailed
        }

        let colorTexture = try makeTexture(width: width, height: height, pixelFormat: .bgra8Unorm)
        let depthTexture = try makeTexture(width: width, height: height, pixelFormat: .r32Float)
        let visibilityTexture = try makeTexture(width: width, height: height, pixelFormat: .r8Uint)
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = colorTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.03, green: 0.035, blue: 0.04, alpha: 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            throw MetalGaussianSplatRenderError.commandEncodingFailed
        }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(splatBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }

        let rgbURL = outputDirectory.appendingPathComponent("rgb", isDirectory: true).appendingPathComponent(String(format: "frame_%06d_metal.ppm", frame.index))
        let depthURL = outputDirectory.appendingPathComponent("depth", isDirectory: true).appendingPathComponent(String(format: "frame_%06d_depth.json", frame.index))
        let visibilityURL = outputDirectory.appendingPathComponent("visibility", isDirectory: true).appendingPathComponent(String(format: "frame_%06d_visibility.json", frame.index))
        let tileBinURL = outputDirectory.appendingPathComponent("tile_bins", isDirectory: true).appendingPathComponent(String(format: "frame_%06d_tile_bins.json", frame.index))
        try FileManager.default.createDirectory(at: rgbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: depthURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: visibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tileBinURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try readPPM(texture: colorTexture, width: width, height: height).write(to: rgbURL)
        try writeDepthAndVisibility(
            frame: frame,
            splats: prepared.projectedSplats,
            depthURL: depthURL,
            visibilityURL: visibilityURL
        )
        try JSONEncoder.robotVisionLabEncoder.encode(prepared.tileReport).write(to: tileBinURL)

        _ = depthTexture
        _ = visibilityTexture

        return MetalSplatRenderProducts(
            frameIndex: frame.index,
            rgbURL: rgbURL,
            depthURL: depthURL,
            visibilityURL: visibilityURL,
            tileBinURL: tileBinURL,
            visibleSplatCount: prepared.projectedSplats.count,
            drawCommandCount: vertices.count,
            totalSplatCount: cloud.splats.count
        )
    }

    private func prepareTileSortedSplats(
        _ splats: [RenderableGaussianSplat],
        frame: DatasetFrame,
        cameraRig: RobotCameraRig,
        width: Int,
        height: Int,
        tileSize: Int
    ) -> (projectedSplats: [ProjectedGaussianSplat], drawSplats: [ProjectedGaussianSplat], tileReport: MetalTileBinReport) {
        let tileColumns = max(1, Int(ceil(Double(width) / Double(tileSize))))
        let tileRows = max(1, Int(ceil(Double(height) / Double(tileSize))))
        let projected = splats.enumerated().compactMap { index, splat in
            project(
                splat: splat,
                splatIndex: index,
                frame: frame,
                cameraRig: cameraRig,
                width: width,
                height: height,
                tileSize: tileSize,
                tileColumns: tileColumns,
                tileRows: tileRows
            )
        }

        var binsByTile: [Int: [ProjectedGaussianSplat]] = [:]
        for splat in projected {
            for tileY in splat.tileRange.minY...splat.tileRange.maxY {
                for tileX in splat.tileRange.minX...splat.tileRange.maxX {
                    binsByTile[tileY * tileColumns + tileX, default: []].append(splat)
                }
            }
        }

        let sortedBins = binsByTile.keys.sorted().map { tileKey -> MetalTileBin in
            let sortedSplats = (binsByTile[tileKey] ?? []).sorted { $0.depthMeters > $1.depthMeters }
            return MetalTileBin(
                tileX: tileKey % tileColumns,
                tileY: tileKey / tileColumns,
                splatIndexesBackToFront: sortedSplats.map(\.splatIndex)
            )
        }
        let drawSplats = sortedBins.flatMap { bin in
            bin.splatIndexesBackToFront.compactMap { splatIndex in
                projected.first { $0.splatIndex == splatIndex }
            }
        }
        let report = MetalTileBinReport(
            frameIndex: frame.index,
            tileSize: tileSize,
            tileColumns: tileColumns,
            tileRows: tileRows,
            projectedSplatCount: projected.count,
            drawCommandCount: drawSplats.count,
            bins: sortedBins
        )
        return (projected, drawSplats, report)
    }

    private func project(
        splat: RenderableGaussianSplat,
        splatIndex: Int,
        frame: DatasetFrame,
        cameraRig: RobotCameraRig,
        width: Int,
        height: Int,
        tileSize: Int,
        tileColumns: Int,
        tileRows: Int
    ) -> ProjectedGaussianSplat? {
        let cameraSpace = SIMD3<Float>(
            splat.position.x - Float(frame.cameraPose.position.x),
            splat.position.y - Float(frame.cameraPose.position.y),
            splat.position.z - Float(frame.cameraPose.position.z)
        )
        let depth = -cameraSpace.z
        guard depth > 0.01 else { return nil }

        let fx = Float(cameraRig.intrinsics.focalLengthPixels.x)
        let fy = Float(cameraRig.intrinsics.focalLengthPixels.y)
        let cx = Float(cameraRig.intrinsics.principalPointPixels.x)
        let cy = Float(cameraRig.intrinsics.principalPointPixels.y)
        let center = SIMD2<Float>(
            cameraSpace.x * fx / depth + cx,
            -cameraSpace.y * fy / depth + cy
        )

        let covariance3D = covarianceMatrix(scale: splat.scale, rotation: splat.rotation)
        let covariance2DMatrix = projectCovariance2D(covariance3D, cameraSpace: cameraSpace, fx: fx, fy: fy)
        let covariance2D = regularizedCovariance(covariance2DMatrix)
        let radii = eigenRadii(covariance2D)
        let majorRadius = min(max(radii.major * 3, 1), 512)
        let minorRadius = min(max(radii.minor * 3, 1), 512)
        let minX = max(0, Int(floor((Double(center.x - majorRadius)) / Double(tileSize))))
        let minY = max(0, Int(floor((Double(center.y - majorRadius)) / Double(tileSize))))
        let maxX = min(tileColumns - 1, Int(floor((Double(center.x + majorRadius)) / Double(tileSize))))
        let maxY = min(tileRows - 1, Int(floor((Double(center.y + majorRadius)) / Double(tileSize))))
        guard maxX >= 0, maxY >= 0, minX < tileColumns, minY < tileRows else {
            return nil
        }

        return ProjectedGaussianSplat(
            splatIndex: splatIndex,
            centerPixels: center,
            depthMeters: depth,
            covariance2D: SIMD4<Float>(covariance2D[0, 0], covariance2D[0, 1], covariance2D[1, 1], 0),
            majorRadiusPixels: majorRadius,
            minorRadiusPixels: minorRadius,
            tileRange: MetalTileRange(minX: minX, minY: minY, maxX: maxX, maxY: maxY),
            color: splat.color
        )
    }

    private func covarianceMatrix(scale: SIMD3<Float>, rotation: SIMD4<Float>) -> simd_float3x3 {
        let q = simd_quatf(ix: rotation.x, iy: rotation.y, iz: rotation.z, r: rotation.w).normalized
        let rotationMatrix = simd_float3x3(q)
        let variance = simd_float3x3(diagonal: SIMD3<Float>(
            scale.x * scale.x,
            scale.y * scale.y,
            scale.z * scale.z
        ))
        return rotationMatrix * variance * rotationMatrix.transpose
    }

    private func projectCovariance2D(
        _ covariance: simd_float3x3,
        cameraSpace: SIMD3<Float>,
        fx: Float,
        fy: Float
    ) -> simd_float2x2 {
        let z = max(-cameraSpace.z, 0.001)
        let rowU = SIMD3<Float>(fx / z, 0, fx * cameraSpace.x / (z * z))
        let rowV = SIMD3<Float>(0, -fy / z, -fy * cameraSpace.y / (z * z))
        return simd_float2x2(rows: [
            SIMD2<Float>(dot(rowU, covariance * rowU), dot(rowU, covariance * rowV)),
            SIMD2<Float>(dot(rowV, covariance * rowU), dot(rowV, covariance * rowV))
        ])
    }

    private func regularizedCovariance(_ covariance: simd_float2x2) -> simd_float2x2 {
        var output = covariance
        output[0, 0] = max(output[0, 0], 0.25)
        output[1, 1] = max(output[1, 1], 0.25)
        return output
    }

    private func eigenRadii(_ covariance: simd_float2x2) -> (major: Float, minor: Float) {
        let a = covariance[0, 0]
        let b = covariance[0, 1]
        let d = covariance[1, 1]
        let trace = a + d
        let determinantTerm = sqrt(max((a - d) * (a - d) + 4 * b * b, 0))
        let lambdaMax = max((trace + determinantTerm) * 0.5, 0.25)
        let lambdaMin = max((trace - determinantTerm) * 0.5, 0.25)
        return (sqrt(lambdaMax), sqrt(lambdaMin))
    }

    private func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalGaussianSplatRenderError.textureAllocationFailed
        }
        return texture
    }

    private func readPPM(texture: MTLTexture, width: Int, height: Int) -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = Array(repeating: UInt8(0), count: bytesPerRow * height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        var ppm = Array("P6\n\(width) \(height)\n255\n".utf8)
        ppm.reserveCapacity(ppm.count + width * height * 3)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            ppm.append(bytes[index + 2])
            ppm.append(bytes[index + 1])
            ppm.append(bytes[index])
        }
        return Data(ppm)
    }

    private func writeDepthAndVisibility(
        frame: DatasetFrame,
        splats: [ProjectedGaussianSplat],
        depthURL: URL,
        visibilityURL: URL
    ) throws {
        let depths = splats.prefix(4096).map { Double($0.depthMeters) }
        let depthSummary = MetalDepthSummary(
            frameIndex: frame.index,
            sampleCount: depths.count,
            nearestMeters: depths.min() ?? 0,
            farthestMeters: depths.max() ?? 0,
            medianMeters: depths.sorted().dropFirst(depths.count / 2).first ?? 0
        )
        let visibility = MetalVisibilitySummary(
            frameIndex: frame.index,
            visibleSplatCount: splats.count,
            sampledVisibleSplatIndexes: splats.prefix(4096).map(\.splatIndex)
        )
        try JSONEncoder.robotVisionLabEncoder.encode(depthSummary).write(to: depthURL)
        try JSONEncoder.robotVisionLabEncoder.encode(visibility).write(to: visibilityURL)
    }

    private static func makePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "robot_splat_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "robot_splat_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

public struct MetalDepthSummary: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var sampleCount: Int
    public var nearestMeters: Double
    public var farthestMeters: Double
    public var medianMeters: Double
}

public struct MetalVisibilitySummary: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var visibleSplatCount: Int
    public var sampledVisibleSplatIndexes: [Int]
}

public enum MetalGaussianSplatRenderError: Error, LocalizedError {
    case deviceUnavailable
    case commandQueueUnavailable
    case unsupportedSceneSource
    case bufferAllocationFailed
    case textureAllocationFailed
    case commandEncodingFailed
    case noVisibleSplats

    public var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            "No Metal device is available."
        case .commandQueueUnavailable:
            "Unable to create a Metal command queue."
        case .unsupportedSceneSource:
            "Native Metal splat rendering currently supports imported ASCII PLY scenes."
        case .bufferAllocationFailed:
            "Unable to allocate Metal buffers for splat rendering."
        case .textureAllocationFailed:
            "Unable to allocate Metal render textures."
        case .commandEncodingFailed:
            "Unable to encode Metal render commands."
        case .noVisibleSplats:
            "No splats are visible from this robot camera pose."
        }
    }
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct SplatVertex {
    float4 projectedCenterDepth;
    float4 covarianceRadius;
    float4 colorOpacity;
};

struct CameraUniforms {
    float4 cameraPosition;
    float4 focalPrincipal;
    float4 viewport;
};

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex VertexOut robot_splat_vertex(
    uint vertexID [[vertex_id]],
    const device SplatVertex *splats [[buffer(0)]],
    constant CameraUniforms &camera [[buffer(1)]]
) {
    SplatVertex splat = splats[vertexID];
    float u = splat.projectedCenterDepth.x;
    float v = splat.projectedCenterDepth.y;
    float x = (u / camera.viewport.x) * 2.0 - 1.0;
    float y = 1.0 - (v / camera.viewport.y) * 2.0;

    VertexOut out;
    out.position = float4(x, y, 0.5, 1.0);
    out.pointSize = clamp(splat.covarianceRadius.w * 2.0, 1.0, 128.0);
    out.color = splat.colorOpacity;
    return out;
}

fragment float4 robot_splat_fragment(VertexOut in [[stage_in]], float2 pointCoord [[point_coord]]) {
    float2 centered = pointCoord * 2.0 - 1.0;
    float radius2 = dot(centered, centered);
    if (radius2 > 1.0) {
        discard_fragment();
    }
    float alpha = in.color.a * exp(-radius2 * 2.5);
    return float4(in.color.rgb, alpha);
}
"""
#else
public final class MetalGaussianSplatRenderer: SplatRenderer {
    public init() throws {
        throw MetalGaussianSplatRenderError.deviceUnavailable
    }

    public func render(frame: DatasetFrame, scene: GaussianSplatScene, cameraRig: RobotCameraRig, outputDirectory: URL) async throws {
        throw MetalGaussianSplatRenderError.deviceUnavailable
    }
}

public enum MetalGaussianSplatRenderError: Error, LocalizedError {
    case deviceUnavailable

    public var errorDescription: String? {
        "Metal is unavailable on this platform or build."
    }
}
#endif
