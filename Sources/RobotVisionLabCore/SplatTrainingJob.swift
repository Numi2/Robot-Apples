import Foundation

public struct SplatTrainingJob: Codable, Equatable, Sendable {
    public var id: String
    public var manifest: SplatTrainingManifest
    public var trainer: SplatTrainerReference
    public var mode: SplatTrainingMode

    public init(
        id: String,
        manifest: SplatTrainingManifest,
        trainer: SplatTrainerReference,
        mode: SplatTrainingMode
    ) {
        self.id = id
        self.manifest = manifest
        self.trainer = trainer
        self.mode = mode
    }
}

public struct SplatTrainerReference: Codable, Equatable, Sendable {
    public var name: String
    public var executableURL: URL?
    public var arguments: [String]

    public init(name: String, executableURL: URL? = nil, arguments: [String] = []) {
        self.name = name
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public enum SplatTrainingMode: String, Codable, Sendable {
    case dryRun
    case externalProcess
}

public enum SplatTrainingStatus: String, Codable, Sendable {
    case planned
    case running
    case completed
    case failed
}

public struct SplatTrainingReport: Codable, Equatable, Sendable {
    public var job: SplatTrainingJob
    public var status: SplatTrainingStatus
    public var startedAt: Date?
    public var finishedAt: Date?
    public var exitCode: Int32?
    public var standardOutput: String
    public var standardError: String
    public var outputAsset: GaussianSplatAsset?
    public var outputScene: GaussianSplatScene?

    public init(
        job: SplatTrainingJob,
        status: SplatTrainingStatus,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        exitCode: Int32? = nil,
        standardOutput: String = "",
        standardError: String = "",
        outputAsset: GaussianSplatAsset? = nil,
        outputScene: GaussianSplatScene? = nil
    ) {
        self.job = job
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.outputAsset = outputAsset
        self.outputScene = outputScene
    }
}

public struct SplatTrainingReportWriter: Sendable {
    public init() {}

    public func write(_ report: SplatTrainingReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }
}

public struct SplatTrainingReportBuilder: Sendable {
    public init() {}

    public func dryRunReport(job: SplatTrainingJob, generatedAt: Date = Date()) -> SplatTrainingReport {
        SplatTrainingReport(
            job: job,
            status: .planned,
            startedAt: generatedAt,
            finishedAt: generatedAt,
            standardOutput: "Dry run: \(job.manifest.imageFrames.count) RGB frames prepared for Gaussian Splat training."
        )
    }

    public func completedReport(
        job: SplatTrainingJob,
        startedAt: Date,
        finishedAt: Date,
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) -> SplatTrainingReport {
        let outputURL = job.manifest.expectedOutput.targetURL
        let asset = try? GaussianSplatImporter().inspect(url: outputURL)
        return SplatTrainingReport(
            job: job,
            status: exitCode == 0 ? .completed : .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: exitCode,
            standardOutput: standardOutput,
            standardError: standardError,
            outputAsset: asset,
            outputScene: asset?.makeScene(id: outputURL.deletingPathExtension().lastPathComponent)
        )
    }
}
