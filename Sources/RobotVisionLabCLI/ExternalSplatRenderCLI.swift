import Foundation
import RobotVisionLabCore

struct ExternalSplatRenderRunner {
    func run(job: ExternalSplatRenderJob, environment: [String: String] = [:]) throws -> ExternalSplatRenderReport {
        guard let executableURL = job.renderer.executableURL else {
            throw ExternalSplatRenderCLIError.missingExecutable
        }

        let startedAt = Date()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = job.renderer.arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return ExternalSplatRenderReportBuilder().completedReport(
            job: job,
            startedAt: startedAt,
            finishedAt: Date(),
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
    }
}

enum ExternalSplatRenderCLIError: Error, LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "External splat rendering requires --splat-renderer-command."
        }
    }
}
