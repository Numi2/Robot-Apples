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

## macOS

Open `RobotSceneStudio.xcodeproj`, select the `RobotSceneStudioMac` scheme, and
run on `My Mac`.

The macOS target enables:

- App Sandbox.
- User-selected read/write file access for `.robotcapture` and `.robotscene`.
- Local network client/server access for Multipeer Connectivity.
- Hardened runtime.

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

## Vision Pro

Open `RobotSceneStudio.xcodeproj`, select the `RobotSceneStudioVision` scheme,
choose a Vision Pro device or simulator, and run.

The visionOS target declares `.robotscene` document support so review packages
can open into the spatial inspection app.
