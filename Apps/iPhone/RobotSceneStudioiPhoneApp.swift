import RobotSceneStudioiPhone
import SwiftUI

@main
struct RobotSceneStudioiPhoneApp: App {
    @State private var model = CaptureClientModel()

    var body: some Scene {
        WindowGroup {
            CaptureClientRootView(model: model)
        }
    }
}

struct CaptureClientRootView: View {
    let model: CaptureClientModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    LabeledContent("Video", value: model.configuration.recordsVideo ? "AVFoundation" : "Off")
                    LabeledContent("Pose", value: model.configuration.recordsARKitPose ? "ARKit" : "Off")
                    LabeledContent("Motion", value: model.configuration.recordsCoreMotion ? "Core Motion" : "Off")
                    LabeledContent("Depth", value: model.configuration.recordsLiDAR ? "LiDAR" : "Optional")
                    LabeledContent("Room", value: model.configuration.recordsRoomPlan ? "RoomPlan" : "Optional")
                }

                Section("Transfer") {
                    LabeledContent("Nearby", value: model.configuration.serviceType)
                    ProgressView(value: model.state.transferProgress)
                    Text(model.state.latestMessage)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Robot Capture")
        }
    }
}
