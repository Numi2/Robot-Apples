import Foundation
import simd

public enum AppleDeviceRole: String, Codable, CaseIterable, Sendable {
    case iPhoneCaptureClient
    case macTrainingWorkstation
    case visionProSpatialReviewer
}

public enum LocalTransferMethod: String, Codable, CaseIterable, Sendable {
    case multipeerConnectivity
    case finderFileSharing
    case bonjourNetworkFramework
    case iCloudFileProvider
    case airDropShareSheet
}

public struct TransferPolicy: Codable, Equatable, Sendable {
    public var primary: LocalTransferMethod
    public var fallbacks: [LocalTransferMethod]
    public var packageExtension: String
    public var supportsLargeResourceTransfer: Bool

    public init(
        primary: LocalTransferMethod = .multipeerConnectivity,
        fallbacks: [LocalTransferMethod] = [.finderFileSharing, .bonjourNetworkFramework, .iCloudFileProvider, .airDropShareSheet],
        packageExtension: String,
        supportsLargeResourceTransfer: Bool = true
    ) {
        self.primary = primary
        self.fallbacks = fallbacks
        self.packageExtension = packageExtension
        self.supportsLargeResourceTransfer = supportsLargeResourceTransfer
    }
}

public struct RobotCapturePackageManifest: Codable, Equatable, Sendable {
    public var schemaVersion: ProjectSchemaVersion
    public var id: String
    public var createdAt: Date
    public var producerRole: AppleDeviceRole
    public var transferPolicy: TransferPolicy
    public var artifactPolicy: PackageArtifactSizePolicy
    public var artifacts: [PackageArtifactRecord]
    public var validationReportURL: URL?
    public var humanReportURL: URL?
    public var videoURL: URL?
    public var framesJSONLURL: URL
    public var motionJSONLURL: URL?
    public var sessionJSONURL: URL
    public var captureBundleURL: URL
    public var notes: String

    public init(
        schemaVersion: ProjectSchemaVersion = .robotCaptureV1,
        id: String,
        createdAt: Date = Date(),
        producerRole: AppleDeviceRole = .iPhoneCaptureClient,
        transferPolicy: TransferPolicy = TransferPolicy(packageExtension: "robotcapture"),
        artifactPolicy: PackageArtifactSizePolicy = PackageArtifactSizePolicy(),
        artifacts: [PackageArtifactRecord] = [],
        validationReportURL: URL? = nil,
        humanReportURL: URL? = nil,
        videoURL: URL? = nil,
        framesJSONLURL: URL,
        motionJSONLURL: URL? = nil,
        sessionJSONURL: URL,
        captureBundleURL: URL,
        notes: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.producerRole = producerRole
        self.transferPolicy = transferPolicy
        self.artifactPolicy = artifactPolicy
        self.artifacts = artifacts
        self.validationReportURL = validationReportURL
        self.humanReportURL = humanReportURL
        self.videoURL = videoURL
        self.framesJSONLURL = framesJSONLURL
        self.motionJSONLURL = motionJSONLURL
        self.sessionJSONURL = sessionJSONURL
        self.captureBundleURL = captureBundleURL
        self.notes = notes
    }
}

public extension RobotCapturePackageManifest {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(ProjectSchemaVersion.self, forKey: .schemaVersion) ?? .robotCaptureV1,
            id: try container.decode(String.self, forKey: .id),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0),
            producerRole: try container.decodeIfPresent(AppleDeviceRole.self, forKey: .producerRole) ?? .iPhoneCaptureClient,
            transferPolicy: try container.decodeIfPresent(TransferPolicy.self, forKey: .transferPolicy) ?? TransferPolicy(packageExtension: "robotcapture"),
            artifactPolicy: try container.decodeIfPresent(PackageArtifactSizePolicy.self, forKey: .artifactPolicy) ?? PackageArtifactSizePolicy(),
            artifacts: try container.decodeIfPresent([PackageArtifactRecord].self, forKey: .artifacts) ?? [],
            validationReportURL: try container.decodeIfPresent(URL.self, forKey: .validationReportURL),
            humanReportURL: try container.decodeIfPresent(URL.self, forKey: .humanReportURL),
            videoURL: try container.decodeIfPresent(URL.self, forKey: .videoURL),
            framesJSONLURL: try container.decode(URL.self, forKey: .framesJSONLURL),
            motionJSONLURL: try container.decodeIfPresent(URL.self, forKey: .motionJSONLURL),
            sessionJSONURL: try container.decode(URL.self, forKey: .sessionJSONURL),
            captureBundleURL: try container.decode(URL.self, forKey: .captureBundleURL),
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case producerRole
        case transferPolicy
        case artifactPolicy
        case artifacts
        case validationReportURL
        case humanReportURL
        case videoURL
        case framesJSONLURL
        case motionJSONLURL
        case sessionJSONURL
        case captureBundleURL
        case notes
    }
}

public struct NavigationGraph: Codable, Equatable, Sendable {
    public var nodes: [NavigationNode]
    public var edges: [NavigationEdge]

    public init(nodes: [NavigationNode], edges: [NavigationEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct NavigationNode: Codable, Equatable, Sendable {
    public var id: String
    public var position: SIMD3<Double>
    public var label: String?

    public init(id: String, position: SIMD3<Double>, label: String? = nil) {
        self.id = id
        self.position = position
        self.label = label
    }
}

public struct NavigationEdge: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var traversalCost: Double

    public init(from: String, to: String, traversalCost: Double = 1) {
        self.from = from
        self.to = to
        self.traversalCost = traversalCost
    }
}

public enum FailureMarkerKind: String, Codable, CaseIterable, Sendable {
    case confident
    case uncertainLocalization
    case blockedPrediction
    case missingTrainingViews
    case visualAmbiguity
    case badLighting
    case lowTexture
}

public enum FailureEvidenceSource: String, Codable, CaseIterable, Sendable {
    case modelPrediction
    case nativeRenderedLabel
    case syntheticLiDARGeometry
    case routeCoverage
    case sceneBoundary
    case imageQuality
    case geometryPrior
}

public struct FailureMapLiDAREvidence: Codable, Equatable, Sendable {
    public var validRayFraction: Double
    public var dropoutRate: Double
    public var lowSupportRate: Double
    public var nearFieldOccupancyRate: Double
    public var meanRangeMeters: Double?

    public init(
        validRayFraction: Double,
        dropoutRate: Double,
        lowSupportRate: Double,
        nearFieldOccupancyRate: Double,
        meanRangeMeters: Double?
    ) {
        self.validRayFraction = validRayFraction
        self.dropoutRate = dropoutRate
        self.lowSupportRate = lowSupportRate
        self.nearFieldOccupancyRate = nearFieldOccupancyRate
        self.meanRangeMeters = meanRangeMeters
    }
}

public struct FailureMapMarker: Codable, Equatable, Sendable {
    public var id: String
    public var frameIndex: Int?
    public var position: SIMD3<Double>
    public var kind: FailureMarkerKind
    public var confidence: Double
    public var note: String
    public var evidenceSources: Set<FailureEvidenceSource>
    public var modelLabel: String?
    public var modelSource: String?
    public var lidarEvidence: FailureMapLiDAREvidence?

    public init(
        id: String,
        frameIndex: Int?,
        position: SIMD3<Double>,
        kind: FailureMarkerKind,
        confidence: Double,
        note: String,
        evidenceSources: Set<FailureEvidenceSource> = [],
        modelLabel: String? = nil,
        modelSource: String? = nil,
        lidarEvidence: FailureMapLiDAREvidence? = nil
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.position = position
        self.kind = kind
        self.confidence = confidence
        self.note = note
        self.evidenceSources = evidenceSources
        self.modelLabel = modelLabel
        self.modelSource = modelSource
        self.lidarEvidence = lidarEvidence
    }
}

public struct VisionProReviewAsset: Codable, Equatable, Sendable {
    public var splatSceneURL: URL?
    public var robotRouteURL: URL
    public var failureMapURL: URL
    public var datasetManifestURL: URL
    public var evaluationReportURL: URL?
    public var reviewSummaryURL: URL?

    public init(
        splatSceneURL: URL? = nil,
        robotRouteURL: URL,
        failureMapURL: URL,
        datasetManifestURL: URL,
        evaluationReportURL: URL? = nil,
        reviewSummaryURL: URL? = nil
    ) {
        self.splatSceneURL = splatSceneURL
        self.robotRouteURL = robotRouteURL
        self.failureMapURL = failureMapURL
        self.datasetManifestURL = datasetManifestURL
        self.evaluationReportURL = evaluationReportURL
        self.reviewSummaryURL = reviewSummaryURL
    }
}

public struct RobotSceneSpatialReviewSummary: Codable, Equatable, Sendable {
    public var sceneID: String
    public var frameCount: Int
    public var markerCount: Int
    public var modelEvidenceMarkerCount: Int
    public var lidarEvidenceMarkerCount: Int
    public var frameRisks: [RobotSceneSpatialReviewFrameRisk]

    public init(
        sceneID: String,
        frameCount: Int,
        markerCount: Int,
        modelEvidenceMarkerCount: Int,
        lidarEvidenceMarkerCount: Int,
        frameRisks: [RobotSceneSpatialReviewFrameRisk]
    ) {
        self.sceneID = sceneID
        self.frameCount = frameCount
        self.markerCount = markerCount
        self.modelEvidenceMarkerCount = modelEvidenceMarkerCount
        self.lidarEvidenceMarkerCount = lidarEvidenceMarkerCount
        self.frameRisks = frameRisks
    }
}

public struct RobotSceneSpatialReviewFrameRisk: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var position: SIMD3<Double>
    public var riskScore: Double
    public var dominantKind: FailureMarkerKind?
    public var markerCount: Int
    public var modelEvidenceCount: Int
    public var lidarEvidenceCount: Int
    public var evidenceSources: Set<FailureEvidenceSource>
    public var summary: String
}

public struct RobotScenePackageManifest: Codable, Equatable, Sendable {
    public var schemaVersion: ProjectSchemaVersion
    public var id: String
    public var createdAt: Date
    public var deviceRoles: [AppleDeviceRole]
    public var transferPolicy: TransferPolicy
    public var artifactPolicy: PackageArtifactSizePolicy
    public var artifacts: [PackageArtifactRecord]
    public var validationReportURL: URL?
    public var humanReportURL: URL?
    public var capturePackageURL: URL?
    public var splatScene: GaussianSplatScene
    public var datasetManifestURL: URL
    public var navigationGraphURL: URL
    public var failureMapURL: URL
    public var visionProReviewAsset: VisionProReviewAsset

    public init(
        schemaVersion: ProjectSchemaVersion = .robotSceneV1,
        id: String,
        createdAt: Date = Date(),
        deviceRoles: [AppleDeviceRole] = AppleDeviceRole.allCases,
        transferPolicy: TransferPolicy = TransferPolicy(packageExtension: "robotscene"),
        artifactPolicy: PackageArtifactSizePolicy = PackageArtifactSizePolicy(),
        artifacts: [PackageArtifactRecord] = [],
        validationReportURL: URL? = nil,
        humanReportURL: URL? = nil,
        capturePackageURL: URL? = nil,
        splatScene: GaussianSplatScene,
        datasetManifestURL: URL,
        navigationGraphURL: URL,
        failureMapURL: URL,
        visionProReviewAsset: VisionProReviewAsset
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.deviceRoles = deviceRoles
        self.transferPolicy = transferPolicy
        self.artifactPolicy = artifactPolicy
        self.artifacts = artifacts
        self.validationReportURL = validationReportURL
        self.humanReportURL = humanReportURL
        self.capturePackageURL = capturePackageURL
        self.splatScene = splatScene
        self.datasetManifestURL = datasetManifestURL
        self.navigationGraphURL = navigationGraphURL
        self.failureMapURL = failureMapURL
        self.visionProReviewAsset = visionProReviewAsset
    }
}

public extension RobotScenePackageManifest {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(ProjectSchemaVersion.self, forKey: .schemaVersion) ?? .robotSceneV1,
            id: try container.decode(String.self, forKey: .id),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0),
            deviceRoles: try container.decodeIfPresent([AppleDeviceRole].self, forKey: .deviceRoles) ?? AppleDeviceRole.allCases,
            transferPolicy: try container.decodeIfPresent(TransferPolicy.self, forKey: .transferPolicy) ?? TransferPolicy(packageExtension: "robotscene"),
            artifactPolicy: try container.decodeIfPresent(PackageArtifactSizePolicy.self, forKey: .artifactPolicy) ?? PackageArtifactSizePolicy(),
            artifacts: try container.decodeIfPresent([PackageArtifactRecord].self, forKey: .artifacts) ?? [],
            validationReportURL: try container.decodeIfPresent(URL.self, forKey: .validationReportURL),
            humanReportURL: try container.decodeIfPresent(URL.self, forKey: .humanReportURL),
            capturePackageURL: try container.decodeIfPresent(URL.self, forKey: .capturePackageURL),
            splatScene: try container.decode(GaussianSplatScene.self, forKey: .splatScene),
            datasetManifestURL: try container.decode(URL.self, forKey: .datasetManifestURL),
            navigationGraphURL: try container.decode(URL.self, forKey: .navigationGraphURL),
            failureMapURL: try container.decode(URL.self, forKey: .failureMapURL),
            visionProReviewAsset: try container.decode(VisionProReviewAsset.self, forKey: .visionProReviewAsset)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case deviceRoles
        case transferPolicy
        case artifactPolicy
        case artifacts
        case validationReportURL
        case humanReportURL
        case capturePackageURL
        case splatScene
        case datasetManifestURL
        case navigationGraphURL
        case failureMapURL
        case visionProReviewAsset
    }
}

public struct RobotScenePackageExporter: Sendable {
    public init() {}

    public func writeRobotScenePackage(
        manifest: DatasetManifest,
        evaluationReportURL: URL? = nil,
        capturePackageURL: URL? = nil,
        to packageDirectory: URL
    ) throws -> RobotScenePackageManifest {
        let fileManager = FileManager.default
        let tools = SharedProjectFormatTools()
        try fileManager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageDirectory.appendingPathComponent("review", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageDirectory.appendingPathComponent("assets/splat", isDirectory: true), withIntermediateDirectories: true)
        _ = try tools.compactBundle(at: packageDirectory)

        let packagedScene = try packageSplatScene(manifest.scene, packageDirectory: packageDirectory)
        let datasetManifestURL = packageDirectory.appendingPathComponent("dataset.json")
        let packagedDatasetManifest = DatasetManifest(
            recipeID: manifest.recipeID,
            generatedAt: manifest.generatedAt,
            scene: packagedScene,
            cameraRig: manifest.cameraRig,
            frames: manifest.frames
        )
        try JSONEncoder.robotVisionLabEncoder.encode(packagedDatasetManifest).write(to: datasetManifestURL)

        let navigationGraph = makeNavigationGraph(from: packagedDatasetManifest)
        let navigationGraphURL = packageDirectory.appendingPathComponent("navigation_graph.json")
        try JSONEncoder.robotVisionLabEncoder.encode(navigationGraph).write(to: navigationGraphURL)

        let packagedEvaluationReportURL = try packageEvaluationReport(evaluationReportURL, packageDirectory: packageDirectory)
        let evaluationReport = packagedEvaluationReportURL.flatMap {
            try? JSONDecoder.robotVisionLabDecoder.decode(ModelEvaluationReport.self, from: Data(contentsOf: $0))
        }
        let failureMap = makeFailureMap(from: packagedDatasetManifest, evaluationReport: evaluationReport)
        let failureMapURL = packageDirectory.appendingPathComponent("failure_map.json")
        try JSONEncoder.robotVisionLabEncoder.encode(failureMap).write(to: failureMapURL)

        let routeURL = packageDirectory.appendingPathComponent("review/robot_route.json")
        try JSONEncoder.robotVisionLabEncoder.encode(packagedDatasetManifest.frames.map {
            PoseLabel(frameIndex: $0.index, timestamp: $0.timestamp, cameraPose: $0.cameraPose)
        }).write(to: routeURL)

        let reviewSummary = makeSpatialReviewSummary(sceneID: "\(manifest.recipeID)-robot-scene", manifest: packagedDatasetManifest, failureMap: failureMap)
        let reviewSummaryReferenceURL = URL(string: "review/spatial_review_summary.json") ?? URL(fileURLWithPath: "review/spatial_review_summary.json")
        let reviewSummaryURL = packageDirectory.appendingPathComponent(reviewSummaryReferenceURL.relativePath)
        try JSONEncoder.robotVisionLabEncoder.encode(reviewSummary).write(to: reviewSummaryURL)

        let reviewAsset = VisionProReviewAsset(
            splatSceneURL: packagedScene.sourceURL,
            robotRouteURL: PackageURLTools.packageRelativeURL(for: routeURL, packageRoot: packageDirectory),
            failureMapURL: PackageURLTools.packageRelativeURL(for: failureMapURL, packageRoot: packageDirectory),
            datasetManifestURL: PackageURLTools.packageRelativeURL(for: datasetManifestURL, packageRoot: packageDirectory),
            evaluationReportURL: packagedEvaluationReportURL.map {
                PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageDirectory)
            },
            reviewSummaryURL: reviewSummaryReferenceURL
        )
        let artifactURLs: [(String, URL)] = [
            ("dataset-manifest", datasetManifestURL),
            ("splat-scene", packagedScene.sourceURL),
            ("navigation-graph", navigationGraphURL),
            ("failure-map", failureMapURL),
            ("review-route", routeURL),
            ("spatial-review-summary", reviewSummaryURL)
        ].compactMap { role, url in url.map { (role, $0) } }
            + [packagedEvaluationReportURL.map { ("evaluation-report", $0) }].compactMap { $0 }
        let artifacts = artifactURLs.map { tools.artifactRecord(role: $0.0, url: $0.1, packageRoot: packageDirectory) }
        let report = tools.validate(
            packageID: "\(manifest.recipeID)-robot-scene",
            packageKind: "robotscene",
            schemaVersion: .robotSceneV1,
            artifacts: artifacts,
            policy: PackageArtifactSizePolicy(),
            packageRoot: packageDirectory
        )
        let reportURLs = try tools.writeReports(report, to: packageDirectory, title: ".robotscene Project Report")
        let package = RobotScenePackageManifest(
            id: "\(manifest.recipeID)-robot-scene",
            artifacts: artifacts,
            validationReportURL: PackageURLTools.packageRelativeURL(for: reportURLs.json, packageRoot: packageDirectory),
            humanReportURL: PackageURLTools.packageRelativeURL(for: reportURLs.markdown, packageRoot: packageDirectory),
            capturePackageURL: capturePackageURL.map {
                PackageURLTools.packageRelativeURL(for: $0, packageRoot: packageDirectory)
            },
            splatScene: packagedScene,
            datasetManifestURL: PackageURLTools.packageRelativeURL(for: datasetManifestURL, packageRoot: packageDirectory),
            navigationGraphURL: PackageURLTools.packageRelativeURL(for: navigationGraphURL, packageRoot: packageDirectory),
            failureMapURL: PackageURLTools.packageRelativeURL(for: failureMapURL, packageRoot: packageDirectory),
            visionProReviewAsset: reviewAsset
        )
        try JSONEncoder.robotVisionLabEncoder.encode(package).write(to: packageDirectory.appendingPathComponent("robotscene.json"))
        return package
    }

    private func packageSplatScene(_ scene: GaussianSplatScene, packageDirectory: URL) throws -> GaussianSplatScene {
        guard let sourceURL = scene.sourceURL else {
            return scene
        }
        let fileName = sourceURL.lastPathComponent.isEmpty ? "scene.ply" : sourceURL.lastPathComponent
        let relativeURL = PackageURLTools.relativeURL(path: "assets/splat/\(fileName)")
        let targetURL = packageDirectory.appendingPathComponent(relativeURL.relativePath)
        if sourceURL.standardizedFileURL.path != targetURL.standardizedFileURL.path {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        }
        return GaussianSplatScene(
            id: scene.id,
            source: packagedSource(from: scene.source, packagedURL: relativeURL),
            alignmentTransform: scene.alignmentTransform,
            bounds: scene.bounds,
            roomPlanModelURL: scene.roomPlanModelURL
        )
    }

    private func packageEvaluationReport(_ sourceURL: URL?, packageDirectory: URL) throws -> URL? {
        guard let sourceURL else { return nil }
        let destinationURL = packageDirectory.appendingPathComponent("review/evaluation_report.json")
        let resolvedSourceURL = PackageURLTools.resolve(sourceURL, relativeTo: packageDirectory)
        guard FileManager.default.fileExists(atPath: resolvedSourceURL.path) else {
            return nil
        }
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if resolvedSourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: resolvedSourceURL, to: destinationURL)
        }
        return destinationURL
    }

    private func packagedSource(from source: SplatSource, packagedURL: URL) -> SplatSource {
        switch source {
        case .importedPLY:
            return .importedPLY(packagedURL)
        case .importedSplat:
            return .importedSplat(packagedURL)
        case .importedSPZ:
            return .importedSPZ(packagedURL)
        case .trainingOutput:
            return .trainingOutput(packagedURL)
        }
    }

    private func makeSpatialReviewSummary(
        sceneID: String,
        manifest: DatasetManifest,
        failureMap: [FailureMapMarker]
    ) -> RobotSceneSpatialReviewSummary {
        let markersByFrame = Dictionary(grouping: failureMap.compactMap { marker -> (Int, FailureMapMarker)? in
            guard let frameIndex = marker.frameIndex else { return nil }
            return (frameIndex, marker)
        }, by: \.0).mapValues { $0.map(\.1) }
        let frameRisks = manifest.frames.map { frame -> RobotSceneSpatialReviewFrameRisk in
            let markers = markersByFrame[frame.index] ?? []
            return reviewFrameRisk(frame: frame, markers: markers)
        }
        return RobotSceneSpatialReviewSummary(
            sceneID: sceneID,
            frameCount: manifest.frames.count,
            markerCount: failureMap.count,
            modelEvidenceMarkerCount: failureMap.filter { $0.modelLabel != nil || $0.modelSource != nil }.count,
            lidarEvidenceMarkerCount: failureMap.filter { $0.lidarEvidence != nil }.count,
            frameRisks: frameRisks
        )
    }

    private func reviewFrameRisk(frame: DatasetFrame, markers: [FailureMapMarker]) -> RobotSceneSpatialReviewFrameRisk {
        let dominant = markers.max { lhs, rhs in markerRisk(lhs) < markerRisk(rhs) }
        let risk = min(markers.reduce(0) { $0 + markerRisk($1) }, 1)
        let evidenceSources = markers.reduce(into: Set<FailureEvidenceSource>()) { partial, marker in
            partial.formUnion(marker.evidenceSources)
        }
        return RobotSceneSpatialReviewFrameRisk(
            frameIndex: frame.index,
            position: frame.cameraPose.position,
            riskScore: risk,
            dominantKind: dominant?.kind,
            markerCount: markers.count,
            modelEvidenceCount: markers.filter { $0.modelLabel != nil || $0.modelSource != nil }.count,
            lidarEvidenceCount: markers.filter { $0.lidarEvidence != nil }.count,
            evidenceSources: evidenceSources,
            summary: reviewFrameRiskSummary(frameIndex: frame.index, risk: risk, dominant: dominant, markers: markers)
        )
    }

    private func markerRisk(_ marker: FailureMapMarker) -> Double {
        var score = marker.confidence * marker.kind.reviewRiskWeight
        if marker.modelLabel != nil || marker.modelSource != nil {
            score += 0.08
        }
        if let lidar = marker.lidarEvidence {
            score += min(max(lidar.dropoutRate, lidar.lowSupportRate) * 0.12, 0.12)
            score += min(lidar.nearFieldOccupancyRate * 0.08, 0.08)
        }
        return min(score, 1)
    }

    private func reviewFrameRiskSummary(
        frameIndex: Int,
        risk: Double,
        dominant: FailureMapMarker?,
        markers: [FailureMapMarker]
    ) -> String {
        guard let dominant else {
            return "Frame \(frameIndex): no review failures."
        }
        return "Frame \(frameIndex): \(dominant.kind.reviewLabel) risk \(Int((risk * 100).rounded()))%, \(markers.count) markers."
    }

    private func makeNavigationGraph(from manifest: DatasetManifest) -> NavigationGraph {
        let nodes = manifest.frames.map {
            NavigationNode(id: "frame_\($0.index)", position: $0.cameraPose.position, label: $0.navigationTarget?.label)
        }
        let edges = zip(nodes, nodes.dropFirst()).map {
            NavigationEdge(from: $0.id, to: $1.id, traversalCost: distance($0.position, $1.position))
        }
        return NavigationGraph(nodes: nodes, edges: edges)
    }

    private func makeFailureMap(from manifest: DatasetManifest, evaluationReport: ModelEvaluationReport?) -> [FailureMapMarker] {
        let evaluationByFrame = Dictionary(uniqueKeysWithValues: (evaluationReport?.frameResults ?? []).map { ($0.frameIndex, $0) })
        let positions = manifest.frames.map(\.cameraPose.position)
        return manifest.frames.flatMap { frame in
            markers(for: frame, manifest: manifest, allPositions: positions, evaluation: evaluationByFrame[frame.index])
        }
    }

    private func markers(
        for frame: DatasetFrame,
        manifest: DatasetManifest,
        allPositions: [SIMD3<Double>],
        evaluation: FrameEvaluationResult?
    ) -> [FailureMapMarker] {
        var markers: [FailureMapMarker] = []
        var markerOrdinal = 0

        func append(
            _ kind: FailureMarkerKind,
            confidence: Double,
            note: String,
            evidenceSources: Set<FailureEvidenceSource>,
            modelLabel: String? = nil,
            modelSource: String? = nil,
            lidarEvidence: FailureMapLiDAREvidence? = nil
        ) {
            markerOrdinal += 1
            markers.append(FailureMapMarker(
                id: "frame_\(frame.index)_\(kind.rawValue)_\(markerOrdinal)",
                frameIndex: frame.index,
                position: frame.cameraPose.position,
                kind: kind,
                confidence: confidence,
                note: note,
                evidenceSources: evidenceSources,
                modelLabel: modelLabel,
                modelSource: modelSource,
                lidarEvidence: lidarEvidence
            ))
        }

        if hasLightingOrImageDegradation(frame) {
            append(
                .badLighting,
                confidence: 0.72,
                note: "Camera augmentation includes exposure, blur, noise, or compression degradation.",
                evidenceSources: [.imageQuality]
            )
        }
        for label in renderedFailureLabels(frame) {
            append(label.kind, confidence: label.confidence, note: label.note, evidenceSources: [.nativeRenderedLabel])
        }
        for marker in calibratedModelMarkers(evaluation) {
            append(
                marker.kind,
                confidence: marker.confidence,
                note: marker.note,
                evidenceSources: [.modelPrediction],
                modelLabel: marker.label,
                modelSource: marker.source
            )
        }
        for marker in lidarFailureMarkers(frame) {
            append(
                marker.kind,
                confidence: marker.confidence,
                note: marker.note,
                evidenceSources: [.syntheticLiDARGeometry],
                lidarEvidence: marker.evidence
            )
        }
        for marker in structuredGeometryFailureMarkers(frame) {
            append(
                marker.kind,
                confidence: marker.confidence,
                note: marker.note,
                evidenceSources: [.geometryPrior]
            )
        }
        if isNearSceneBoundary(frame.cameraPose.position, bounds: manifest.scene.bounds) {
            append(
                .blockedPrediction,
                confidence: 0.62,
                note: "Frame is near the splat scene boundary; inspect for incomplete capture or invalid robot traversal.",
                evidenceSources: [.sceneBoundary]
            )
        }
        if hasLowConfidencePrediction(evaluation) {
            append(
                .uncertainLocalization,
                confidence: 0.68,
                note: "Evaluation report contains low-confidence predictions or frame warnings.",
                evidenceSources: [.modelPrediction]
            )
        }
        if hasMissingTrainingView(frame, allPositions: allPositions) {
            append(
                .missingTrainingViews,
                confidence: 0.7,
                note: "Pose is isolated from nearby route samples; additional capture views may improve coverage.",
                evidenceSources: [.routeCoverage]
            )
        }
        if hasVisualAmbiguity(frame, allPositions: allPositions) {
            append(
                .visualAmbiguity,
                confidence: 0.58,
                note: "Nearby route samples have very similar positions, which may indicate repeated or ambiguous viewpoints.",
                evidenceSources: [.routeCoverage]
            )
        }
        if hasLowTextureSignals(frame) {
            append(
                .lowTexture,
                confidence: 0.6,
                note: "Frame lacks segmentation/manual/object label sources that would help disambiguate low-texture geometry.",
                evidenceSources: [.geometryPrior]
            )
        }
        if markers.isEmpty {
            append(.confident, confidence: 0.95, note: "No baseline failure marker.", evidenceSources: [])
        }
        return markers
    }

    private func hasLightingOrImageDegradation(_ frame: DatasetFrame) -> Bool {
        frame.augmentations.contains { augmentation in
            if case .exposureEV = augmentation { return true }
            if case .motionBlur = augmentation { return true }
            if case .compressionJPEG = augmentation { return true }
            if case .gaussianNoise = augmentation { return true }
            return false
        }
    }

    private func renderedFailureLabels(_ frame: DatasetFrame) -> [RenderedFailureLabel] {
        guard let url = frame.productURL(for: .failureLabels),
              let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder.robotVisionLabDecoder.decode(RenderedFailureLabelReport.self, from: data) else {
            return []
        }
        return report.labels.filter { $0.kind != .confident }
    }

    private func isNearSceneBoundary(_ position: SIMD3<Double>, bounds: AxisAlignedBounds) -> Bool {
        let margin = 0.25
        return abs(position.x - bounds.minimum.x) < margin
            || abs(position.x - bounds.maximum.x) < margin
            || abs(position.z - bounds.minimum.z) < margin
            || abs(position.z - bounds.maximum.z) < margin
    }

    private func predictsBlocked(_ evaluation: FrameEvaluationResult?) -> Bool {
        evaluation?.predictions.contains {
            $0.task == .obstacleDetection
                && (
                    $0.label.localizedCaseInsensitiveContains("blocked")
                    || $0.label.localizedCaseInsensitiveContains("not_free")
                    || $0.label.localizedCaseInsensitiveContains("collision")
                )
                && $0.confidence >= 0.55
        } ?? false
    }

    private func hasLowConfidencePrediction(_ evaluation: FrameEvaluationResult?) -> Bool {
        guard let evaluation else { return false }
        return !evaluation.warnings.isEmpty || evaluation.predictions.contains { $0.confidence < 0.55 }
    }

    private func calibratedModelMarkers(_ evaluation: FrameEvaluationResult?) -> [(kind: FailureMarkerKind, confidence: Double, note: String, label: String, source: String)] {
        guard let evaluation else { return [] }
        var markers: [(kind: FailureMarkerKind, confidence: Double, note: String, label: String, source: String)] = []
        for prediction in evaluation.predictions {
            let label = prediction.label.lowercased()
            switch prediction.task {
            case .obstacleDetection:
                if (label.contains("blocked") || label.contains("not_free")) && prediction.confidence >= 0.55 {
                    markers.append((
                        .blockedPrediction,
                        min(max(prediction.confidence, 0), 1),
                        "Calibrated obstacle output \(prediction.label) from \(prediction.source).",
                        prediction.label,
                        prediction.source
                    ))
                }
                if label.contains("free_path") && prediction.confidence >= 0.8 {
                    markers.append((
                        .confident,
                        min(max(prediction.confidence, 0), 1),
                        "Calibrated free-space output from \(prediction.source).",
                        prediction.label,
                        prediction.source
                    ))
                }
            case .failureCaseDetection:
                if label.contains("uncertain") && prediction.confidence >= 0.45 {
                    markers.append((
                        .uncertainLocalization,
                        min(max(prediction.confidence, 0), 1),
                        "Calibrated localization uncertainty from \(prediction.source).",
                        prediction.label,
                        prediction.source
                    ))
                }
                if let kind = prediction.failureKind, kind != .confident, prediction.confidence >= 0.45 {
                    markers.append((
                        kind,
                        min(max(prediction.confidence, 0), 1),
                        "Calibrated failure-kind output \(prediction.label) from \(prediction.source).",
                        prediction.label,
                        prediction.source
                    ))
                }
            case .segmentation:
                if label.contains("missing") && prediction.confidence >= 0.5 {
                    markers.append((
                        .missingTrainingViews,
                        min(max(prediction.confidence, 0), 1),
                        "Calibrated segmentation gap from \(prediction.source).",
                        prediction.label,
                        prediction.source
                    ))
                }
            case .navigationTargetDetection:
                continue
            }
        }
        return markers
    }

    private func lidarFailureMarkers(_ frame: DatasetFrame) -> [(kind: FailureMarkerKind, confidence: Double, note: String, evidence: FailureMapLiDAREvidence)] {
        guard let report = renderedLiDARReport(frame) else { return [] }
        let rayCount = max(report.metrics.rayCount, 1)
        let validRayCount = max(report.metrics.validRayCount, 1)
        let validFraction = Double(report.metrics.validRayCount) / Double(rayCount)
        let nearFieldOccupancy = Double(report.rays.filter { ray in
            guard !ray.droppedOut, let point = ray.cameraPointMeters else { return false }
            return abs(point.z) < 1.0
        }.count) / Double(validRayCount)
        let evidence = FailureMapLiDAREvidence(
            validRayFraction: validFraction,
            dropoutRate: report.metrics.dropoutRate,
            lowSupportRate: report.metrics.lowSupportRate,
            nearFieldOccupancyRate: nearFieldOccupancy,
            meanRangeMeters: report.metrics.meanRangeMeters
        )
        var markers: [(kind: FailureMarkerKind, confidence: Double, note: String, evidence: FailureMapLiDAREvidence)] = []
        if nearFieldOccupancy > 0.42 || (report.metrics.meanRangeMeters ?? .greatestFiniteMagnitude) < 1.2 {
            markers.append((
                .blockedPrediction,
                min(0.94, 0.55 + nearFieldOccupancy * 0.55),
                "Synthetic LiDAR returns show dense near-field occupancy in the robot camera frustum.",
                evidence
            ))
        }
        if report.metrics.dropoutRate > 0.45 || report.metrics.lowSupportRate > 0.38 {
            markers.append((
                .uncertainLocalization,
                min(0.9, 0.45 + max(report.metrics.dropoutRate, report.metrics.lowSupportRate) * 0.5),
                "Synthetic LiDAR geometry has high dropout or weak visibility support.",
                evidence
            ))
        }
        if validFraction < 0.35 || report.metrics.lowSupportRate > 0.52 {
            markers.append((
                .missingTrainingViews,
                min(0.88, 0.5 + max(1 - validFraction, report.metrics.lowSupportRate) * 0.38),
                "Synthetic LiDAR scan has low valid return coverage; capture additional views around this pose.",
                evidence
            ))
        }
        return markers
    }

    private func renderedLiDARReport(_ frame: DatasetFrame) -> RenderedLiDARScanReport? {
        guard let url = frame.productURL(for: .lidarScan),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.robotVisionLabDecoder.decode(RenderedLiDARScanReport.self, from: data)
    }

    private func structuredGeometryFailureMarkers(_ frame: DatasetFrame) -> [(kind: FailureMarkerKind, confidence: Double, note: String)] {
        guard let report = structuredGeometryReport(frame) else { return [] }
        var markers: [(kind: FailureMarkerKind, confidence: Double, note: String)] = []
        if report.obstacleProbability >= 0.5 {
            markers.append((
                .blockedPrediction,
                min(0.9, 0.45 + report.obstacleProbability * 0.45),
                "RoomPlan/Object Capture geometry indicates obstacle-prior overlap in the robot camera view."
            ))
        }
        if hasStructuredGeometrySources(frame), report.segmentationHints.isEmpty {
            markers.append((
                .missingTrainingViews,
                0.62,
                "Structured geometry is linked, but no RoomPlan/Object Capture layer projects into this frame."
            ))
        }
        return markers
    }

    private func structuredGeometryReport(_ frame: DatasetFrame) -> StructuredGeometryFrameProductReport? {
        guard let url = frame.productURL(for: .obstacleMask) ?? frame.productURL(for: .segmentation),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.robotVisionLabDecoder.decode(StructuredGeometryFrameProductReport.self, from: data)
    }

    private func failureKind(from label: String) -> FailureMarkerKind? {
        let normalized = label.lowercased()
        if normalized.contains("blocked") || normalized.contains("collision") || normalized.contains("obstacle") {
            return .blockedPrediction
        }
        if normalized.contains("uncertain") || normalized.contains("localization") {
            return .uncertainLocalization
        }
        if normalized.contains("missing") || normalized.contains("view") {
            return .missingTrainingViews
        }
        if normalized.contains("ambiguous") || normalized.contains("repeat") {
            return .visualAmbiguity
        }
        if normalized.contains("texture") {
            return .lowTexture
        }
        if normalized.contains("lighting") || normalized.contains("blur") || normalized.contains("exposure") {
            return .badLighting
        }
        return nil
    }

    private func hasMissingTrainingView(_ frame: DatasetFrame, allPositions: [SIMD3<Double>]) -> Bool {
        let nearest = allPositions
            .filter { distance($0, frame.cameraPose.position) > 0.001 }
            .map { distance($0, frame.cameraPose.position) }
            .min() ?? 0
        return nearest > 1.25
    }

    private func hasVisualAmbiguity(_ frame: DatasetFrame, allPositions: [SIMD3<Double>]) -> Bool {
        let closeCount = allPositions.filter { distance($0, frame.cameraPose.position) < 0.08 }.count
        return closeCount >= 3
    }

    private func hasLowTextureSignals(_ frame: DatasetFrame) -> Bool {
        return !hasStructuredGeometrySources(frame) || !hasSegmentationHints(frame)
    }

    private func hasStructuredGeometrySources(_ frame: DatasetFrame) -> Bool {
        frame.labelSources.contains {
            if case .roomPlanGeometry = $0 { return true }
            if case .objectCaptureMesh = $0 { return true }
            if case .manualAnnotations = $0 { return true }
            return false
        }
    }

    private func hasSegmentationHints(_ frame: DatasetFrame) -> Bool {
        guard let url = frame.productURL(for: .segmentation),
              let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder.robotVisionLabDecoder.decode(StructuredGeometryFrameProductReport.self, from: data) else {
            return false
        }
        return !report.segmentationHints.isEmpty
    }
}

public extension GaussianSplatScene {
    var sourceURL: URL? {
        switch source {
        case .importedPLY(let url), .importedSplat(let url), .importedSPZ(let url), .trainingOutput(let url):
            return url
        }
    }
}

public extension FailureMarkerKind {
    var reviewLabel: String {
        switch self {
        case .confident: "Confident"
        case .uncertainLocalization: "Uncertain localization"
        case .blockedPrediction: "Blocked"
        case .missingTrainingViews: "Missing views"
        case .visualAmbiguity: "Visual ambiguity"
        case .badLighting: "Lighting"
        case .lowTexture: "Low texture"
        }
    }

    var reviewRiskWeight: Double {
        switch self {
        case .confident: 0.05
        case .blockedPrediction: 1.0
        case .uncertainLocalization: 0.86
        case .missingTrainingViews: 0.78
        case .visualAmbiguity: 0.72
        case .badLighting: 0.58
        case .lowTexture: 0.52
        }
    }
}
