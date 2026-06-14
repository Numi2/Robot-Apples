import RobotSceneStudioMac
import SwiftUI

@main
struct RobotSceneStudioMacApp: App {
    @State private var model = WorkstationModel()

    var body: some Scene {
        WindowGroup("Robot Scene Studio") {
            WorkstationRootView(model: model)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Workspace Folder") {
                    NSWorkspace.shared.open(model.state.workspaceURL)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
