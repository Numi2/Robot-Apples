import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct ProjectSchemaVersion: Codable, Equatable, Comparable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static let robotCaptureV1 = ProjectSchemaVersion(major: 1, minor: 0, patch: 0)
    public static let robotSceneV1 = ProjectSchemaVersion(major: 1, minor: 0, patch: 0)

    public static func < (lhs: ProjectSchemaVersion, rhs: ProjectSchemaVersion) -> Bool {
        [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes([rhs.major, rhs.minor, rhs.patch])
    }
}

public struct PackageArtifactRecord: Codable, Equatable, Sendable {
    public var role: String
    public var url: URL
    public var byteCount: Int64
    public var sha256: String?

    public init(role: String, url: URL, byteCount: Int64, sha256: String? = nil) {
        self.role = role
        self.url = url
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct PackageArtifactSizePolicy: Codable, Equatable, Sendable {
    public var maxManifestBytes: Int64
    public var maxInlineJSONBytes: Int64
    public var maxRecommendedPackageBytes: Int64
    public var cleanupPatterns: [String]

    public init(
        maxManifestBytes: Int64 = 4 * 1024 * 1024,
        maxInlineJSONBytes: Int64 = 32 * 1024 * 1024,
        maxRecommendedPackageBytes: Int64 = 25 * 1024 * 1024 * 1024,
        cleanupPatterns: [String] = [".DS_Store", "__MACOSX", ".tmp", ".partial"]
    ) {
        self.maxManifestBytes = maxManifestBytes
        self.maxInlineJSONBytes = maxInlineJSONBytes
        self.maxRecommendedPackageBytes = maxRecommendedPackageBytes
        self.cleanupPatterns = cleanupPatterns
    }
}

public enum PackageValidationSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct PackageValidationIssue: Codable, Equatable, Sendable {
    public var severity: PackageValidationSeverity
    public var message: String

    public init(_ severity: PackageValidationSeverity, _ message: String) {
        self.severity = severity
        self.message = message
    }
}

public struct PackageValidationReport: Codable, Equatable, Sendable {
    public var packageID: String
    public var packageKind: String
    public var schemaVersion: ProjectSchemaVersion
    public var generatedAt: Date
    public var artifactCount: Int
    public var totalByteCount: Int64
    public var issues: [PackageValidationIssue]

    public init(
        packageID: String,
        packageKind: String,
        schemaVersion: ProjectSchemaVersion,
        generatedAt: Date = Date(),
        artifactCount: Int,
        totalByteCount: Int64,
        issues: [PackageValidationIssue]
    ) {
        self.packageID = packageID
        self.packageKind = packageKind
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.artifactCount = artifactCount
        self.totalByteCount = totalByteCount
        self.issues = issues
    }

    public var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }
}

public struct SharedProjectFormatTools: Sendable {
    public init() {}

    public func artifactRecord(role: String, url: URL, packageRoot: URL) -> PackageArtifactRecord {
        let absoluteURL = PackageURLTools.resolve(url, relativeTo: packageRoot)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: absoluteURL.path)) ?? [:]
        let byteCount = attributes[.size] as? Int64 ?? 0
        return PackageArtifactRecord(
            role: role,
            url: PackageURLTools.packageRelativeURL(for: absoluteURL, packageRoot: packageRoot),
            byteCount: byteCount,
            sha256: sha256(for: absoluteURL)
        )
    }

    public func validate(
        packageID: String,
        packageKind: String,
        schemaVersion: ProjectSchemaVersion,
        artifacts: [PackageArtifactRecord],
        policy: PackageArtifactSizePolicy,
        packageRoot: URL
    ) -> PackageValidationReport {
        var issues: [PackageValidationIssue] = []
        var totalBytes: Int64 = 0
        for artifact in artifacts {
            totalBytes += artifact.byteCount
            let resolved = PackageURLTools.resolve(artifact.url, relativeTo: packageRoot)
            if !FileManager.default.fileExists(atPath: resolved.path) {
                issues.append(PackageValidationIssue(.error, "Missing artifact \(artifact.role): \(artifact.url.path)."))
            }
            if artifact.role.localizedCaseInsensitiveContains("manifest"), artifact.byteCount > policy.maxManifestBytes {
                issues.append(PackageValidationIssue(.warning, "Manifest \(artifact.url.lastPathComponent) is \(artifact.byteCount) bytes; keep manifests small and store large data as resources."))
            }
            if artifact.url.pathExtension.lowercased() == "json", artifact.byteCount > policy.maxInlineJSONBytes {
                issues.append(PackageValidationIssue(.warning, "Large JSON artifact \(artifact.url.lastPathComponent) risks package bloat."))
            }
            if artifact.byteCount > 0, artifact.sha256 == nil {
                issues.append(PackageValidationIssue(.warning, "Artifact \(artifact.url.lastPathComponent) has no SHA-256 checksum on this platform."))
            }
            if let expectedSHA = artifact.sha256,
               let actualSHA = sha256(for: resolved),
               expectedSHA != actualSHA {
                issues.append(PackageValidationIssue(.error, "Checksum mismatch for \(artifact.role): \(artifact.url.lastPathComponent)."))
            }
        }
        if totalBytes > policy.maxRecommendedPackageBytes {
            issues.append(PackageValidationIssue(.warning, "Package is \(totalBytes) bytes; consider compaction or moving generated caches out of the bundle."))
        }
        return PackageValidationReport(
            packageID: packageID,
            packageKind: packageKind,
            schemaVersion: schemaVersion,
            artifactCount: artifacts.count,
            totalByteCount: totalBytes,
            issues: issues
        )
    }

    public func writeReports(_ report: PackageValidationReport, to directory: URL, title: String) throws -> (json: URL, markdown: URL) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonURL = directory.appendingPathComponent("validation_report.json")
        let markdownURL = directory.appendingPathComponent("PROJECT_REPORT.md")
        try JSONEncoder.robotVisionLabEncoder.encode(report).write(to: jsonURL)
        try markdown(report, title: title).write(to: markdownURL, atomically: true, encoding: .utf8)
        return (jsonURL, markdownURL)
    }

    @discardableResult
    public func compactBundle(at packageRoot: URL, policy: PackageArtifactSizePolicy = PackageArtifactSizePolicy()) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var removed: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if policy.cleanupPatterns.contains(where: { name == $0 || name.hasSuffix($0) }) {
                try? FileManager.default.removeItem(at: url)
                removed.append(url)
            }
        }
        return removed
    }

    private func markdown(_ report: PackageValidationReport, title: String) -> String {
        let issueLines = report.issues.isEmpty
            ? "- No validation issues.\n"
            : report.issues.map { "- \($0.severity.rawValue): \($0.message)" }.joined(separator: "\n") + "\n"
        return """
        # \(title)

        - Package ID: \(report.packageID)
        - Package kind: \(report.packageKind)
        - Schema version: \(report.schemaVersion.major).\(report.schemaVersion.minor).\(report.schemaVersion.patch)
        - Artifact count: \(report.artifactCount)
        - Total bytes: \(report.totalByteCount)

        ## Validation

        \(issueLines)
        """
    }

    private func sha256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }
}

public struct PackageURLTools: Sendable {
    public init() {}

    public static func packageRelativeURL(for url: URL, packageRoot: URL) -> URL {
        if isRelativeFileReference(url) {
            return relativeURL(path: url.relativePath)
        }

        let resolvedURL = resolve(url, relativeTo: packageRoot)
        guard let relativePath = relativePathIfContained(resolvedURL, in: packageRoot) else {
            return url
        }
        return relativeURL(path: relativePath)
    }

    public static func resolve(_ url: URL, relativeTo packageRoot: URL) -> URL {
        if isRelativeFileReference(url) {
            let candidate = packageRoot
                .appendingPathComponent(url.relativePath)
                .standardizedFileURL
            guard relativePathIfContained(candidate, in: packageRoot) != nil else {
                return invalidPackageRelativeURL(for: url, packageRoot: packageRoot)
            }
            return candidate
        }

        if url.isFileURL, url.path.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            if !url.relativePath.hasPrefix("/") {
                return packageRoot.appendingPathComponent(url.relativePath)
            }
            if let recovered = recoverMovedPackageURL(url, packageRoot: packageRoot) {
                return recovered
            }
            return url
        }

        return url
    }

    public static func relativeURL(path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return URL(string: ".") ?? URL(fileURLWithPath: ".")
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%:")
        let encodedPath = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(component)
            }
            .joined(separator: "/")
        return URL(string: encodedPath) ?? URL(fileURLWithPath: encodedPath)
    }

    private static func isRelativeFileReference(_ url: URL) -> Bool {
        url.scheme == nil && !url.relativePath.hasPrefix("/")
    }

    private static func relativePathIfContained(_ url: URL, in packageRoot: URL) -> String? {
        let rootPath = packageRoot.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlPath = url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard urlPath == rootPath || urlPath.hasPrefix(rootPath + "/") else {
            return nil
        }
        if urlPath == rootPath {
            return "."
        }
        return String(urlPath.dropFirst(rootPath.count + 1))
    }

    private static func invalidPackageRelativeURL(for url: URL, packageRoot: URL) -> URL {
        let name = url.lastPathComponent.isEmpty ? "invalid" : url.lastPathComponent
        return packageRoot
            .appendingPathComponent("__invalid_package_relative_path__", isDirectory: true)
            .appendingPathComponent(name)
    }

    private static func recoverMovedPackageURL(_ url: URL, packageRoot: URL) -> URL? {
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard !components.isEmpty else { return nil }
        for startIndex in components.indices {
            let suffix = components[startIndex...].joined(separator: "/")
            let candidate = packageRoot.appendingPathComponent(suffix)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

public struct SharedProjectPackageMigrator: Sendable {
    public init() {}

    public func migrateRobotCapturePackage(at packageURL: URL) throws -> PackageValidationReport {
        let manifestURL = packageURL.pathExtension == "json" ? packageURL : packageURL.appendingPathComponent("robotcapture.json")
        let packageRoot = manifestURL.deletingLastPathComponent()
        let manifest = try JSONDecoder.robotVisionLabDecoder.decode(RobotCapturePackageManifest.self, from: Data(contentsOf: manifestURL))
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let tools = SharedProjectFormatTools()
        let report = tools.validate(
            packageID: manifest.id,
            packageKind: "robotcapture",
            schemaVersion: manifest.schemaVersion,
            artifacts: manifest.artifacts,
            policy: manifest.artifactPolicy,
            packageRoot: packageRoot
        )
        _ = try tools.writeReports(report, to: packageRoot, title: ".robotcapture Project Report")
        return report
    }

    public func migrateRobotScenePackage(at packageURL: URL) throws -> PackageValidationReport {
        let manifestURL = packageURL.pathExtension == "json" ? packageURL : packageURL.appendingPathComponent("robotscene.json")
        let packageRoot = manifestURL.deletingLastPathComponent()
        let manifest = try JSONDecoder.robotVisionLabDecoder.decode(RobotScenePackageManifest.self, from: Data(contentsOf: manifestURL))
        try JSONEncoder.robotVisionLabEncoder.encode(manifest).write(to: manifestURL)
        let tools = SharedProjectFormatTools()
        let report = tools.validate(
            packageID: manifest.id,
            packageKind: "robotscene",
            schemaVersion: manifest.schemaVersion,
            artifacts: manifest.artifacts,
            policy: manifest.artifactPolicy,
            packageRoot: packageRoot
        )
        _ = try tools.writeReports(report, to: packageRoot, title: ".robotscene Project Report")
        return report
    }
}
