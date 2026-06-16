import Foundation

public enum RobotCaptureTransferRole: String, Codable, Sendable {
    case sender
    case receiver
}

public enum RobotCaptureTransferEvent: Equatable, Sendable {
    case peerFound(String)
    case peerLost(String)
    case pairingInvitation(String)
    case pairingAccepted(String)
    case pairingRejected(String)
    case peerConnected(String)
    case peerDisconnected(String)
    case packageSendStarted(URL, String)
    case packageSendProgress(URL, String, Double)
    case packageSendFinished(URL, String)
    case packageReceiveStarted(String, String)
    case packageReceiveProgress(String, String, Double)
    case packageReceiveFinished(String, URL)
    case transferReceiptWritten(URL)
    case recoverableFailure(String, URL?)
    case failed(String)
}

public protocol RobotCaptureTransferDelegate: AnyObject {
    func robotCaptureTransferDidEmit(_ event: RobotCaptureTransferEvent)
}

public struct RobotCaptureTransferReceipt: Codable, Equatable, Sendable {
    public var receivedAt: Date
    public var peerDisplayName: String
    public var packageName: String
    public var packageURL: URL
    public var transferMethod: LocalTransferMethod

    public init(
        receivedAt: Date = Date(),
        peerDisplayName: String,
        packageName: String,
        packageURL: URL,
        transferMethod: LocalTransferMethod = .multipeerConnectivity
    ) {
        self.receivedAt = receivedAt
        self.peerDisplayName = peerDisplayName
        self.packageName = packageName
        self.packageURL = packageURL
        self.transferMethod = transferMethod
    }
}

public struct RobotCaptureTransferPlan: Codable, Equatable, Sendable {
    public var role: RobotCaptureTransferRole
    public var serviceType: String
    public var transferMethod: LocalTransferMethod
    public var packageURL: URL?
    public var inboxDirectory: URL?
    public var expectedManifestName: String
    public var notes: [String]

    public init(
        role: RobotCaptureTransferRole,
        serviceType: String = "robotcapture",
        transferMethod: LocalTransferMethod = .multipeerConnectivity,
        packageURL: URL? = nil,
        inboxDirectory: URL? = nil,
        expectedManifestName: String = "robotcapture.json",
        notes: [String] = []
    ) {
        self.role = role
        self.serviceType = serviceType
        self.transferMethod = transferMethod
        self.packageURL = packageURL
        self.inboxDirectory = inboxDirectory
        self.expectedManifestName = expectedManifestName
        self.notes = notes
    }
}

public struct FinderFileSharingFallbackGuide: Codable, Equatable, Sendable {
    public var transferMethod: LocalTransferMethod
    public var packageExtension: String
    public var requirements: [String]
    public var copyToMacSteps: [String]
    public var notes: [String]

    public init(
        transferMethod: LocalTransferMethod = .finderFileSharing,
        packageExtension: String = "robotcapture",
        requirements: [String] = [
            "Mac running macOS Catalina or later.",
            "iPhone or iPad connected to the Mac with a USB cable.",
            "The capture app must expose its documents through iOS/iPadOS File Sharing."
        ],
        copyToMacSteps: [String] = [
            "Open Finder on the Mac.",
            "Select the connected iPhone or iPad in Finder.",
            "Open the Files tab.",
            "Select the capture app's shared files.",
            "Drag the .robotcapture package to the Mac ingest folder."
        ],
        notes: [String] = [
            "Use this as a wired fallback when Multipeer Connectivity is unavailable or too slow for large recordings.",
            "After copying, run the normal Mac import path against the copied .robotcapture package."
        ]
    ) {
        self.transferMethod = transferMethod
        self.packageExtension = packageExtension
        self.requirements = requirements
        self.copyToMacSteps = copyToMacSteps
        self.notes = notes
    }
}

public struct RobotCapturePackageArchive: Sendable {
    public static let archiveExtension = "robotcapturearchive"

    private static let magic = Data("ROBOT_CAPTURE_ARCHIVE_V1\n".utf8)
    private static let chunkSize = 1_048_576

    public init() {}

    public func writeArchive(for packageURL: URL, to archiveURL: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RobotCapturePackageArchiveError.packageMustBeDirectory(packageURL)
        }

        let parent = archiveURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        fileManager.createFile(atPath: archiveURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: archiveURL)
        defer { try? output.close() }
        output.write(Self.magic)

        let entries = try archiveEntries(in: packageURL)
        for entry in entries {
            let relativePath = try relativePath(for: entry.url, root: packageURL)
            guard !relativePath.isEmpty else { continue }
            let record = ArchiveRecord(
                relativePath: relativePath,
                byteCount: entry.byteCount,
                isDirectory: entry.isDirectory,
                end: false
            )
            try writeRecord(record, to: output)
            if !entry.isDirectory {
                try appendFile(entry.url, byteCount: entry.byteCount, to: output)
                output.write(Data([0x0A]))
            }
        }
        try writeRecord(ArchiveRecord(relativePath: nil, byteCount: nil, isDirectory: nil, end: true), to: output)
    }

    public func extractArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).partial-\(UUID().uuidString)", isDirectory: true)
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: stagingURL)
            }
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }
        let magic = try input.read(upToCount: Self.magic.count)
        guard magic == Self.magic else {
            throw RobotCapturePackageArchiveError.invalidArchive(archiveURL)
        }

        while true {
            guard let line = try readLine(from: input), !line.isEmpty else {
                throw RobotCapturePackageArchiveError.invalidArchive(archiveURL)
            }
            let record = try JSONDecoder.robotVisionLabDecoder.decode(ArchiveRecord.self, from: line)
            if record.end == true {
                break
            }
            guard let relativePath = record.relativePath,
                  let byteCount = record.byteCount,
                  let isDirectory = record.isDirectory else {
                throw RobotCapturePackageArchiveError.invalidArchive(archiveURL)
            }
            let outputURL = try safeOutputURL(for: relativePath, under: stagingURL)
            if isDirectory {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try copyBytes(byteCount, from: input, to: outputURL)
                let separator = try input.read(upToCount: 1)
                guard separator == Data([0x0A]) else {
                    throw RobotCapturePackageArchiveError.invalidArchive(archiveURL)
                }
            }
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        completed = true
    }

    public func archiveURL(for packageURL: URL, temporaryDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let baseName = packageURL.deletingPathExtension().lastPathComponent
        return temporaryDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(Self.archiveExtension)
    }

    private func archiveEntries(in packageURL: URL) throws -> [ArchiveEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            throw RobotCapturePackageArchiveError.packageMustBeDirectory(packageURL)
        }
        var entries: [ArchiveEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                entries.append(ArchiveEntry(url: url, isDirectory: true, byteCount: 0))
            } else if values.isRegularFile == true {
                entries.append(ArchiveEntry(url: url, isDirectory: false, byteCount: Int64(values.fileSize ?? 0)))
            } else {
                throw RobotCapturePackageArchiveError.unsupportedPackageItem(url)
            }
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.url.path < $1.url.path
        }
    }

    private func relativePath(for url: URL, root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            throw RobotCapturePackageArchiveError.unsafeRelativePath(path)
        }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        try validateRelativePath(relative)
        return relative
    }

    private func safeOutputURL(for relativePath: String, under destinationURL: URL) throws -> URL {
        try validateRelativePath(relativePath)
        let outputURL = destinationURL.appendingPathComponent(relativePath)
        let destinationPath = destinationURL.standardizedFileURL.path
        let outputPath = outputURL.standardizedFileURL.path
        guard outputPath == destinationPath || outputPath.hasPrefix(destinationPath + "/") else {
            throw RobotCapturePackageArchiveError.unsafeRelativePath(relativePath)
        }
        return outputURL
    }

    private func validateRelativePath(_ relativePath: String) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains("..") else {
            throw RobotCapturePackageArchiveError.unsafeRelativePath(relativePath)
        }
    }

    private func writeRecord(_ record: ArchiveRecord, to output: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        output.write(data)
        output.write(Data([0x0A]))
    }

    private func appendFile(_ url: URL, byteCount: Int64, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var remaining = byteCount
        while remaining > 0 {
            let count = min(Self.chunkSize, Int(remaining))
            guard let chunk = try input.read(upToCount: count), !chunk.isEmpty else {
                throw RobotCapturePackageArchiveError.invalidArchive(url)
            }
            output.write(chunk)
            remaining -= Int64(chunk.count)
        }
    }

    private func readLine(from input: FileHandle) throws -> Data? {
        var line = Data()
        while true {
            guard let byte = try input.read(upToCount: 1), !byte.isEmpty else {
                return line.isEmpty ? nil : line
            }
            if byte == Data([0x0A]) {
                return line
            }
            line.append(contentsOf: byte)
        }
    }

    private func copyBytes(_ byteCount: Int64, from input: FileHandle, to outputURL: URL) throws {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        var remaining = byteCount
        while remaining > 0 {
            let count = min(Self.chunkSize, Int(remaining))
            guard let chunk = try input.read(upToCount: count), !chunk.isEmpty else {
                throw RobotCapturePackageArchiveError.invalidArchive(outputURL)
            }
            output.write(chunk)
            remaining -= Int64(chunk.count)
        }
    }

    private struct ArchiveEntry {
        var url: URL
        var isDirectory: Bool
        var byteCount: Int64
    }

    private struct ArchiveRecord: Codable {
        var relativePath: String?
        var byteCount: Int64?
        var isDirectory: Bool?
        var end: Bool?
    }
}

public enum RobotCapturePackageArchiveError: Error, LocalizedError {
    case packageMustBeDirectory(URL)
    case unsupportedPackageItem(URL)
    case invalidArchive(URL)
    case unsafeRelativePath(String)

    public var errorDescription: String? {
        switch self {
        case .packageMustBeDirectory(let url):
            "Multipeer transfer requires a .robotcapture directory package at \(url.path)."
        case .unsupportedPackageItem(let url):
            "Robot capture package contains an unsupported non-file item at \(url.path)."
        case .invalidArchive(let url):
            "Robot capture transfer archive is invalid or truncated at \(url.path)."
        case .unsafeRelativePath(let path):
            "Robot capture transfer archive contains an unsafe relative path: \(path)."
        }
    }
}

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity

public final class RobotCaptureMultipeerTransfer: NSObject, @unchecked Sendable {
    public static let serviceType = "robotcapture"

    public weak var delegate: RobotCaptureTransferDelegate?

    public private(set) var connectedPeers: [String] = []
    public var automaticallyAcceptInvitations: Bool

    private let role: RobotCaptureTransferRole
    private let inboxDirectory: URL
    private let peerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var sendProgress: [Progress] = []
    private var progressObservers: [NSKeyValueObservation] = []
    private var pendingInvitations: [String: (Bool, MCSession?) -> Void] = [:]
    private var knownPeers: [String: MCPeerID] = [:]
    private var approvedPeerNames: Set<String> = []
    private var lastPackageURLByPeer: [String: URL] = [:]
    private var temporaryTransferArchiveURLs: Set<URL> = []

    public init(
        role: RobotCaptureTransferRole,
        displayName: String = RobotCaptureMultipeerTransfer.defaultDisplayName(),
        inboxDirectory: URL,
        automaticallyAcceptInvitations: Bool = true
    ) {
        self.role = role
        self.inboxDirectory = inboxDirectory
        self.automaticallyAcceptInvitations = automaticallyAcceptInvitations
        self.peerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        self.session.delegate = self
    }

    public static func defaultDisplayName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    deinit {
        stop()
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        switch role {
        case .sender:
            let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        case .receiver:
            let advertiser = MCNearbyServiceAdvertiser(
                peer: peerID,
                discoveryInfo: ["package": "robotcapture"],
                serviceType: Self.serviceType
            )
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        }
    }

    public func stop() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        browser = nil
        advertiser = nil
        session.disconnect()
        connectedPeers = []
        sendProgress.forEach { $0.cancel() }
        sendProgress.removeAll()
        progressObservers.removeAll()
        pendingInvitations.removeAll()
        knownPeers.removeAll()
        approvedPeerNames.removeAll()
        temporaryTransferArchiveURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryTransferArchiveURLs.removeAll()
    }

    public func acceptInvitation(from peerDisplayName: String) {
        guard let handler = pendingInvitations.removeValue(forKey: peerDisplayName) else { return }
        approvedPeerNames.insert(peerDisplayName)
        handler(role == .receiver, session)
        delegate?.robotCaptureTransferDidEmit(.pairingAccepted(peerDisplayName))
    }

    public func rejectInvitation(from peerDisplayName: String) {
        guard let handler = pendingInvitations.removeValue(forKey: peerDisplayName) else { return }
        approvedPeerNames.remove(peerDisplayName)
        handler(false, nil)
        delegate?.robotCaptureTransferDidEmit(.pairingRejected(peerDisplayName))
    }

    public func cancelTransfers() {
        sendProgress.forEach { $0.cancel() }
        sendProgress.removeAll()
        progressObservers.removeAll()
        delegate?.robotCaptureTransferDidEmit(.failed("Active transfer was cancelled."))
    }

    public func retryLastPackage(to peerDisplayName: String? = nil) throws {
        let packageURL: URL?
        if let peerDisplayName {
            packageURL = lastPackageURLByPeer[peerDisplayName]
        } else {
            packageURL = lastPackageURLByPeer.values.first
        }
        guard let packageURL else {
            throw RobotCaptureTransferError.noRecoverablePackage
        }
        try sendRobotCapturePackage(at: packageURL, to: peerDisplayName)
    }

    public func sendRobotCapturePackage(at packageURL: URL, to peerDisplayName: String? = nil) throws {
        let peers = session.connectedPeers.filter { peer in
            peerDisplayName.map { $0 == peer.displayName } ?? true
        }
        guard !peers.isEmpty else {
            throw RobotCaptureTransferError.noConnectedPeers
        }

        for peer in peers {
            lastPackageURLByPeer[peer.displayName] = packageURL
            delegate?.robotCaptureTransferDidEmit(.packageSendStarted(packageURL, peer.displayName))
            let resourceURL = try transferResourceURL(for: packageURL)
            let resourceName = transferResourceName(packageURL: packageURL, resourceURL: resourceURL)
            let progress = session.sendResource(
                at: resourceURL,
                withName: resourceName,
                toPeer: peer
            ) { [weak self] error in
                self?.cleanupTemporaryTransferArchive(resourceURL)
                if let error {
                    self?.delegate?.robotCaptureTransferDidEmit(.failed(error.localizedDescription))
                } else {
                    self?.delegate?.robotCaptureTransferDidEmit(.packageSendFinished(packageURL, peer.displayName))
                }
            }
            if let progress {
                sendProgress.append(progress)
                observe(progress: progress, resourceName: resourceName, peerDisplayName: peer.displayName, sendingURL: packageURL)
                progress.cancellationHandler = { [weak self] in
                    self?.cleanupTemporaryTransferArchive(resourceURL)
                    self?.delegate?.robotCaptureTransferDidEmit(.failed("Robot capture package transfer was cancelled."))
                }
            }
        }
    }

    private func updateConnectedPeers() {
        connectedPeers = session.connectedPeers.map(\.displayName).sorted()
    }

    private func transferResourceURL(for packageURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: packageURL.path, isDirectory: &isDirectory) else {
            throw RobotCaptureTransferError.packageDoesNotExist(packageURL)
        }
        guard isDirectory.boolValue else {
            return packageURL
        }
        let archive = RobotCapturePackageArchive()
        let archiveURL = try archive.archiveURL(
            for: packageURL,
            temporaryDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("RobotCaptureMultipeerTransfer", isDirectory: true)
        )
        try archive.writeArchive(for: packageURL, to: archiveURL)
        temporaryTransferArchiveURLs.insert(archiveURL)
        return archiveURL
    }

    private func transferResourceName(packageURL: URL, resourceURL: URL) -> String {
        if resourceURL.pathExtension == RobotCapturePackageArchive.archiveExtension {
            return packageURL.deletingPathExtension().lastPathComponent
                .appending(".\(RobotCapturePackageArchive.archiveExtension)")
        }
        return packageURL.lastPathComponent
    }

    private func cleanupTemporaryTransferArchive(_ url: URL) {
        guard temporaryTransferArchiveURLs.remove(url) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension RobotCaptureMultipeerTransfer: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        knownPeers[peerID.displayName] = peerID
        delegate?.robotCaptureTransferDidEmit(.pairingInvitation(peerID.displayName))
        if automaticallyAcceptInvitations {
            approvedPeerNames.insert(peerID.displayName)
            invitationHandler(role == .receiver, session)
            delegate?.robotCaptureTransferDidEmit(.pairingAccepted(peerID.displayName))
        } else {
            pendingInvitations[peerID.displayName] = invitationHandler
        }
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        delegate?.robotCaptureTransferDidEmit(.failed(error.localizedDescription))
    }
}

extension RobotCaptureMultipeerTransfer: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        knownPeers[peerID.displayName] = peerID
        approvedPeerNames.insert(peerID.displayName)
        delegate?.robotCaptureTransferDidEmit(.peerFound(peerID.displayName))
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        delegate?.robotCaptureTransferDidEmit(.peerLost(peerID.displayName))
        knownPeers.removeValue(forKey: peerID.displayName)
        approvedPeerNames.remove(peerID.displayName)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        delegate?.robotCaptureTransferDidEmit(.failed(error.localizedDescription))
    }
}

extension RobotCaptureMultipeerTransfer: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        updateConnectedPeers()
        switch state {
        case .connected:
            delegate?.robotCaptureTransferDidEmit(.peerConnected(peerID.displayName))
        case .notConnected:
            delegate?.robotCaptureTransferDidEmit(.peerDisconnected(peerID.displayName))
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        delegate?.robotCaptureTransferDidEmit(.packageReceiveStarted(resourceName, peerID.displayName))
        observe(progress: progress, resourceName: resourceName, peerDisplayName: peerID.displayName, sendingURL: nil)
    }

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        if let error {
            delegate?.robotCaptureTransferDidEmit(.recoverableFailure(error.localizedDescription, nil))
            delegate?.robotCaptureTransferDidEmit(.failed(error.localizedDescription))
            return
        }
        guard let localURL else {
            delegate?.robotCaptureTransferDidEmit(.failed("Multipeer Connectivity finished without a local resource URL."))
            return
        }

        do {
            try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
            let destination: URL
            if resourceName.hasSuffix(".\(RobotCapturePackageArchive.archiveExtension)") {
                destination = uniqueDestinationURL(
                    for: resourceName
                        .replacingOccurrences(of: ".\(RobotCapturePackageArchive.archiveExtension)", with: ".robotcapture")
                )
                try RobotCapturePackageArchive().extractArchive(at: localURL, to: destination)
                try? FileManager.default.removeItem(at: localURL)
            } else {
                destination = uniqueDestinationURL(for: resourceName)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: localURL, to: destination)
            }
            let receipt = RobotCaptureTransferReceipt(
                peerDisplayName: peerID.displayName,
                packageName: resourceName,
                packageURL: destination
            )
            try JSONEncoder.robotVisionLabEncoder
                .encode(receipt)
                .write(to: receiptURL(for: destination))
            delegate?.robotCaptureTransferDidEmit(.transferReceiptWritten(receiptURL(for: destination)))
            delegate?.robotCaptureTransferDidEmit(.packageReceiveFinished(peerID.displayName, destination))
        } catch {
            delegate?.robotCaptureTransferDidEmit(.failed(error.localizedDescription))
        }
    }

    public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    public func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        let displayName = peerID.displayName
        let accepted = knownPeers[displayName] != nil && approvedPeerNames.contains(displayName)
        certificateHandler(accepted)
        if !accepted {
            delegate?.robotCaptureTransferDidEmit(.failed("Rejected unapproved Multipeer certificate from \(displayName)."))
        }
    }

    private func uniqueDestinationURL(for resourceName: String) -> URL {
        let baseURL = inboxDirectory.appendingPathComponent(resourceName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let suffix = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return inboxDirectory.appendingPathComponent("\(baseURL.deletingPathExtension().lastPathComponent)-\(suffix).\(baseURL.pathExtension)")
    }

    private func receiptURL(for destination: URL) -> URL {
        destination.deletingPathExtension().appendingPathExtension("transfer-receipt.json")
    }

    private func observe(progress: Progress, resourceName: String, peerDisplayName: String, sendingURL: URL?) {
        let observer = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            let fraction = max(0, min(1, progress.fractionCompleted))
            if let sendingURL {
                self?.delegate?.robotCaptureTransferDidEmit(.packageSendProgress(sendingURL, peerDisplayName, fraction))
            } else {
                self?.delegate?.robotCaptureTransferDidEmit(.packageReceiveProgress(resourceName, peerDisplayName, fraction))
            }
        }
        progressObservers.append(observer)
    }
}

public enum RobotCaptureTransferError: Error, LocalizedError {
    case noConnectedPeers
    case noRecoverablePackage
    case packageDoesNotExist(URL)

    public var errorDescription: String? {
        switch self {
        case .noConnectedPeers:
            "No Multipeer Connectivity peers are connected."
        case .noRecoverablePackage:
            "No previous package is available to retry."
        case .packageDoesNotExist(let url):
            "Robot capture package does not exist at \(url.path)."
        }
    }
}
#else
public final class RobotCaptureMultipeerTransfer {
    public var automaticallyAcceptInvitations = true
    public init(role: RobotCaptureTransferRole, displayName: String = "", inboxDirectory: URL, automaticallyAcceptInvitations: Bool = true) {}
    public func start() throws {}
    public func stop() {}
    public func acceptInvitation(from peerDisplayName: String) {}
    public func rejectInvitation(from peerDisplayName: String) {}
    public func cancelTransfers() {}
    public func retryLastPackage(to peerDisplayName: String? = nil) throws {}
    public func sendRobotCapturePackage(at packageURL: URL, to peerDisplayName: String? = nil) throws {}
}
#endif
