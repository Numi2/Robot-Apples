import Foundation

public struct ExternalSplatRenderJob: Codable, Equatable, Sendable {
    public var id: String
    public var datasetManifestURL: URL
    public var outputDirectory: URL
    public var renderer: ExternalSplatRendererReference
    public var expectedRGBDirectory: URL

    public init(
        id: String,
        datasetManifestURL: URL,
        outputDirectory: URL,
        renderer: ExternalSplatRendererReference,
        expectedRGBDirectory: URL? = nil
    ) {
        self.id = id
        self.datasetManifestURL = datasetManifestURL
        self.outputDirectory = outputDirectory
        self.renderer = renderer
        self.expectedRGBDirectory = expectedRGBDirectory ?? outputDirectory.appendingPathComponent("rgb", isDirectory: true)
    }
}

public struct ExternalSplatRendererReference: Codable, Equatable, Sendable {
    public var name: String
    public var executableURL: URL?
    public var arguments: [String]

    public init(name: String, executableURL: URL? = nil, arguments: [String] = []) {
        self.name = name
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public enum ExternalSplatRenderStatus: String, Codable, Sendable {
    case planned
    case completed
    case failed
}

public struct ExternalSplatRenderReport: Codable, Equatable, Sendable {
    public var job: ExternalSplatRenderJob
    public var status: ExternalSplatRenderStatus
    public var startedAt: Date?
    public var finishedAt: Date?
    public var exitCode: Int32?
    public var renderedRGBFrameCount: Int
    public var standardOutput: String
    public var standardError: String
    public var diagnostics: [String]

    public init(
        job: ExternalSplatRenderJob,
        status: ExternalSplatRenderStatus,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        exitCode: Int32? = nil,
        renderedRGBFrameCount: Int = 0,
        standardOutput: String = "",
        standardError: String = "",
        diagnostics: [String] = []
    ) {
        self.job = job
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.renderedRGBFrameCount = renderedRGBFrameCount
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.diagnostics = diagnostics
    }
}

public struct ExternalSplatRenderReportWriter: Sendable {
    public init() {}

    public func write(_ report: ExternalSplatRenderReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }
}

public struct ExternalSplatRenderReportBuilder: Sendable {
    public init() {}

    public func plannedReport(job: ExternalSplatRenderJob, generatedAt: Date = Date()) -> ExternalSplatRenderReport {
        ExternalSplatRenderReport(
            job: job,
            status: .planned,
            startedAt: generatedAt,
            finishedAt: generatedAt,
            diagnostics: [
                "Dry run: external renderer would consume dataset.json and write RGB/depth products into the dataset output directory."
            ]
        )
    }

    public func completedReport(
        job: ExternalSplatRenderJob,
        startedAt: Date,
        finishedAt: Date,
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) -> ExternalSplatRenderReport {
        let frameCount = renderedRGBFrameCount(in: job.expectedRGBDirectory)
        var diagnostics: [String] = []
        if frameCount == 0 {
            diagnostics.append("No RGB frames were found in \(job.expectedRGBDirectory.path) after renderer execution.")
        }
        return ExternalSplatRenderReport(
            job: job,
            status: exitCode == 0 ? .completed : .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: exitCode,
            renderedRGBFrameCount: frameCount,
            standardOutput: standardOutput,
            standardError: standardError,
            diagnostics: diagnostics
        )
    }

    private func renderedRGBFrameCount(in directory: URL) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return files.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "ppm" || ext == "exr"
        }.count
    }
}
