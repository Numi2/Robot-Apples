import Foundation

public struct CapturePlan: Codable, Equatable, Sendable {
    public var id: String
    public var captureModes: Set<CaptureMode>
    public var roomPlan: RoomPlanOptions?
    public var objectCapture: ObjectCaptureOptions?
    public var rgbVideo: RGBVideoOptions?
    public var lidar: LiDAROptions?

    public init(
        id: String,
        captureModes: Set<CaptureMode>,
        roomPlan: RoomPlanOptions? = nil,
        objectCapture: ObjectCaptureOptions? = nil,
        rgbVideo: RGBVideoOptions? = nil,
        lidar: LiDAROptions? = nil
    ) {
        self.id = id
        self.captureModes = captureModes
        self.roomPlan = roomPlan
        self.objectCapture = objectCapture
        self.rgbVideo = rgbVideo
        self.lidar = lidar
    }

    public func validate() throws {
        if captureModes.isEmpty {
            throw CapturePlanError.noCaptureModes
        }
        if captureModes.contains(.roomPlan), roomPlan == nil {
            throw CapturePlanError.missingOptions("RoomPlan")
        }
        if captureModes.contains(.objectCapture), objectCapture == nil {
            throw CapturePlanError.missingOptions("Object Capture")
        }
        if captureModes.contains(.rgbVideo), rgbVideo == nil {
            throw CapturePlanError.missingOptions("RGB video")
        }
        if captureModes.contains(.lidarDepth), lidar == nil {
            throw CapturePlanError.missingOptions("LiDAR")
        }
    }
}

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case roomPlan
    case objectCapture
    case rgbVideo
    case coreMotion
    case lidarDepth
}

public struct RoomPlanOptions: Codable, Equatable, Sendable {
    public var exportUSDZ: Bool
    public var preserveSemanticCategories: Bool

    public init(exportUSDZ: Bool = true, preserveSemanticCategories: Bool = true) {
        self.exportUSDZ = exportUSDZ
        self.preserveSemanticCategories = preserveSemanticCategories
    }
}

public struct ObjectCaptureOptions: Codable, Equatable, Sendable {
    public var objectLabels: [String]
    public var preferredDetail: ObjectCaptureDetail

    public init(objectLabels: [String], preferredDetail: ObjectCaptureDetail = .medium) {
        self.objectLabels = objectLabels
        self.preferredDetail = preferredDetail
    }
}

public enum ObjectCaptureDetail: String, Codable, Equatable, Sendable {
    case preview
    case reduced
    case medium
    case full
    case raw
}

public struct RGBVideoOptions: Codable, Equatable, Sendable {
    public var targetFPS: Int
    public var targetResolution: Resolution
    public var saveCameraPoses: Bool

    public init(targetFPS: Int = 30, targetResolution: Resolution = .hd1280x720, saveCameraPoses: Bool = true) {
        self.targetFPS = targetFPS
        self.targetResolution = targetResolution
        self.saveCameraPoses = saveCameraPoses
    }
}

public struct LiDAROptions: Codable, Equatable, Sendable {
    public var saveDepth: Bool
    public var saveConfidence: Bool
    public var alignToRGB: Bool

    public init(saveDepth: Bool = true, saveConfidence: Bool = true, alignToRGB: Bool = true) {
        self.saveDepth = saveDepth
        self.saveConfidence = saveConfidence
        self.alignToRGB = alignToRGB
    }
}

public struct Resolution: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let hd1280x720 = Resolution(width: 1280, height: 720)
    public static let uhd3840x2160 = Resolution(width: 3840, height: 2160)
}

public enum CapturePlanError: Error, Equatable, LocalizedError {
    case noCaptureModes
    case missingOptions(String)

    public var errorDescription: String? {
        switch self {
        case .noCaptureModes:
            "Capture plan must include at least one capture mode."
        case .missingOptions(let mode):
            "Capture plan includes \(mode) but does not include its options."
        }
    }
}
