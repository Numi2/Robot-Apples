import Foundation
import RobotVisionLabCore

struct ExternalSplatTrainerRunner {
    func run(job: SplatTrainingJob, environment: [String: String] = [:]) throws -> SplatTrainingReport {
        guard let executableURL = job.trainer.executableURL else {
            throw SplatTrainingCLIError.missingExecutable
        }

        let startedAt = Date()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = job.trainer.arguments
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
        return SplatTrainingReportBuilder().completedReport(
            job: job,
            startedAt: startedAt,
            finishedAt: Date(),
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
    }
}

enum SplatTrainingCLIError: Error, LocalizedError {
    case missingExecutable
    case missingPreparedManifest(URL)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "External splat training requires --trainer-command."
        case .missingPreparedManifest(let url):
            "Prepared splat training manifest was not found at \(url.path)."
        }
    }
}
