import Foundation
import RobotVisionLabCore

struct MLXEvaluationRunner {
    func run(job: MLXEvaluationJob, environment: [String: String] = [:]) throws -> MLXEvaluationProcessReport {
        let startedAt = Date()
        let process = Process()
        process.executableURL = job.executableURL
        process.arguments = job.arguments
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
        let producedReportURL = FileManager.default.fileExists(atPath: job.outputReportURL.path) ? job.outputReportURL : nil
        return MLXEvaluationProcessReport(
            job: job,
            startedAt: startedAt,
            finishedAt: Date(),
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error,
            producedReportURL: producedReportURL
        )
    }
}

struct MLXEvaluationProcessReportWriter {
    func write(_ report: MLXEvaluationProcessReport, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: outputURL)
    }
}
