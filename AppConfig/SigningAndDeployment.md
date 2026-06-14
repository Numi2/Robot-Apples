# Signing and Local Deployment

Robot Scene Studio uses `project.yml` as the source of truth for Xcode targets.
Run `xcodegen generate` after changing target settings.

## Development Team

Set the Apple Development Team ID in `project.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "YOURTEAMID"
```

Regenerate the project:

```bash
xcodegen generate
```

Xcode automatic signing is enabled for the Mac workstation, iPhone capture app,
and Vision Pro review app.

Before device deployment, verify each generated target still has:

- `CODE_SIGN_STYLE = Automatic`.
- A real `DEVELOPMENT_TEAM`.
- A bundle identifier owned by that team.
- Matching `Info.plist` document types for `.robotcapture` and `.robotscene`
  where the target imports or opens those packages.

## macOS

Open `RobotSceneStudio.xcodeproj`, select the `RobotSceneStudioMac` scheme, and
run on `My Mac`.

The macOS target enables:

- App Sandbox.
- User-selected read/write file access for `.robotcapture` and `.robotscene`.
- Local network client/server access for Multipeer Connectivity.
- Hardened runtime.

Deployment checklist:

- Confirm `com.apple.security.network.client` and
  `com.apple.security.network.server` remain enabled for Multipeer receive.
- Confirm user-selected file read/write entitlement remains enabled for package
  import/export.
- Run the `RobotSceneStudioMac` scheme once with `CODE_SIGNING_ALLOWED=NO` for
  CI-style validation, then with normal signing for local app launch.

## iPhone

Open `RobotSceneStudio.xcodeproj`, select the `RobotSceneStudioCapture` scheme,
choose a connected iPhone, and run.

The iPhone target declares:

- Camera usage for `video.mov` capture.
- Microphone usage for AVFoundation movie capture when audio is enabled.
- Motion usage for Core Motion streams.
- Local network usage and Bonjour services for native Mac transfer.
- File sharing and open-in-place support for Finder wired fallback transfer.

ARKit and LiDAR features are gated by device capability at runtime.

Deployment checklist:

- Confirm camera, microphone, motion, local-network, and Bonjour usage strings
  are present in `AppConfig/iPhone/Info.plist`.
- Confirm the local-network Bonjour service name matches the Multipeer service
  type used by `RobotCaptureMultipeerTransfer`.
- Confirm `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` remain
  enabled for Finder wired transfer.
- Test on physical iPhone for ARKit, LiDAR, RoomPlan, and Core Motion behavior;
  simulator builds only validate UI and packaging.

## Vision Pro

Open `RobotSceneStudio.xcodeproj`, select the `RobotSceneStudioVision` scheme,
choose a Vision Pro device or simulator, and run.

The visionOS target declares `.robotscene` document support so review packages
can open into the spatial inspection app.

Deployment checklist:

- Confirm `.robotscene` document type is present in
  `AppConfig/Vision/Info.plist`.
- Confirm package-open flows work from Files and from the app file importer.
- Confirm RealityKit/visionOS Gaussian splat rendering paths are compiled only
  where the SDK supports them, with package inspection still available on older
  simulators.
