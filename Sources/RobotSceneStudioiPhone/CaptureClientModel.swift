import Foundation
import RobotVisionLabCore

public enum CaptureClientStage: String, Codable, Sendable {
    case idle
    case recording
    case packaging
    case transferring
    case complete
    case failed
}

public struct CaptureClientState: Codable, Equatable, Sendable {
    public var stage: CaptureClientStage
    public var packageURL: URL?
    public var transferProgress: Double
    public var latestMessage: String

    public init(
        stage: CaptureClientStage = .idle,
        packageURL: URL? = nil,
        transferProgress: Double = 0,
        latestMessage: String = "Ready"
    ) {
        self.stage = stage
        self.packageURL = packageURL
        self.transferProgress = transferProgress
        self.latestMessage = latestMessage
    }
}

public struct CaptureClientConfiguration: Codable, Equatable, Sendable {
    public var serviceType: String
    public var recordsVideo: Bool
    public var recordsARKitPose: Bool
    public var recordsCoreMotion: Bool
    public var recordsLiDAR: Bool
    public var recordsRoomPlan: Bool

    public init(
        serviceType: String = "robotcapture",
        recordsVideo: Bool = true,
        recordsARKitPose: Bool = true,
        recordsCoreMotion: Bool = true,
        recordsLiDAR: Bool = true,
        recordsRoomPlan: Bool = true
    ) {
        self.serviceType = serviceType
        self.recordsVideo = recordsVideo
        self.recordsARKitPose = recordsARKitPose
        self.recordsCoreMotion = recordsCoreMotion
        self.recordsLiDAR = recordsLiDAR
        self.recordsRoomPlan = recordsRoomPlan
    }
}

public final class CaptureClientModel {
    public private(set) var configuration: CaptureClientConfiguration
    public private(set) var state: CaptureClientState

    public init(
        configuration: CaptureClientConfiguration = CaptureClientConfiguration(),
        state: CaptureClientState = CaptureClientState()
    ) {
        self.configuration = configuration
        self.state = state
    }

    public func beginRecording() {
        state = CaptureClientState(stage: .recording, latestMessage: "Recording AVFoundation video, ARKit poses, and Core Motion samples.")
    }

    public func packageCapture(at packageURL: URL) {
        state = CaptureClientState(stage: .packaging, packageURL: packageURL, latestMessage: "Packaging .robotcapture bundle.")
    }

    public func updateTransfer(progress: Double) {
        state.transferProgress = min(max(progress, 0), 1)
        state.stage = state.transferProgress >= 1 ? .complete : .transferring
        state.latestMessage = state.stage == .complete ? "Transfer complete." : "Transferring to Mac over Multipeer Connectivity."
    }

    public func fail(_ message: String) {
        state.stage = .failed
        state.latestMessage = message
    }
}
