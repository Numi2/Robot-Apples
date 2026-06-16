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
    private var lastPackageURLByPeer: [String: URL] = [:]

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
    }

    public func acceptInvitation(from peerDisplayName: String) {
        guard let handler = pendingInvitations.removeValue(forKey: peerDisplayName) else { return }
        handler(role == .receiver, session)
        delegate?.robotCaptureTransferDidEmit(.pairingAccepted(peerDisplayName))
    }

    public func rejectInvitation(from peerDisplayName: String) {
        guard let handler = pendingInvitations.removeValue(forKey: peerDisplayName) else { return }
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
            let progress = session.sendResource(
                at: packageURL,
                withName: packageURL.lastPathComponent,
                toPeer: peer
            ) { [weak self] error in
                if let error {
                    self?.delegate?.robotCaptureTransferDidEmit(.failed(error.localizedDescription))
                } else {
                    self?.delegate?.robotCaptureTransferDidEmit(.packageSendFinished(packageURL, peer.displayName))
                }
            }
            if let progress {
                sendProgress.append(progress)
                observe(progress: progress, resourceName: packageURL.lastPathComponent, peerDisplayName: peer.displayName, sendingURL: packageURL)
                progress.cancellationHandler = { [weak self] in
                    self?.delegate?.robotCaptureTransferDidEmit(.failed("Robot capture package transfer was cancelled."))
                }
            }
        }
    }

    private func updateConnectedPeers() {
        connectedPeers = session.connectedPeers.map(\.displayName).sorted()
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
        delegate?.robotCaptureTransferDidEmit(.peerFound(peerID.displayName))
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        delegate?.robotCaptureTransferDidEmit(.peerLost(peerID.displayName))
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
            let destination = uniqueDestinationURL(for: resourceName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: localURL, to: destination)
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
        certificateHandler(true)
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

    public var errorDescription: String? {
        switch self {
        case .noConnectedPeers:
            "No Multipeer Connectivity peers are connected."
        case .noRecoverablePackage:
            "No previous package is available to retry."
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
