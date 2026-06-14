# Robot Scene Studio

Robot Scene Studio is an Apple-native, three-device robotics scene system.

- iPhone records real-world capture packages.
- Mac trains, aligns, renders, evaluates, and exports robotics scene assets.
- Vision Pro opens the resulting scene for spatial inspection.

This is not one app stretched across devices. It is one shared project format
with three Apple-native clients.

## Product Target

Shared package formats:

- `.robotcapture`: iPhone-to-Mac capture package.
- `.robotscene`: Mac-to-Vision-Pro review and robotics asset package.

Both package formats carry schema versions, artifact size policies, SHA-256
checksums where available, validation reports, and human-readable
`PROJECT_REPORT.md` summaries. Older unversioned manifests decode into v1
defaults and can be re-written through the validation/migration command.

Device roles:

- iPhone: SwiftUI capture client using AVFoundation, ARKit, Core Motion, LiDAR,
  and RoomPlan.
- Mac: SwiftUI/AppKit workstation using Metal, MLX, Core ML, and Apple Silicon
  for native splat rendering, training, route generation, model evaluation, and
  export.
- Vision Pro: SwiftUI/RealityKit spatial viewer for Gaussian splats, robot
  routes, camera frustums, navigation graphs, and failure overlays.

The product does not depend on generic renderer or trainer process bridges.
Developer CLI commands are support tools only; the product center is the native
Apple app stack.

## Apple Documentation Anchors

- AVFoundation `AVCaptureMovieFileOutput` records QuickTime movie files:
  https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput
- ARKit `ARCamera.transform` and `ARCamera.intrinsics` provide camera pose and
  calibration data:
  https://developer.apple.com/documentation/arkit/arcamera/transform
  https://developer.apple.com/documentation/arkit/arcamera/intrinsics
- Core Motion provides accelerometer, gyroscope, and device-motion data:
  https://developer.apple.com/documentation/coremotion
- RoomPlan `CapturedRoom` can export room results to USDZ:
  https://developer.apple.com/documentation/roomplan/capturedroom
- Multipeer Connectivity `MCSession` manages nearby peer communication and
  resource transfer:
  https://developer.apple.com/documentation/multipeerconnectivity/mcsession
  https://developer.apple.com/documentation/multipeerconnectivity/mcsession/sendresource(at:withname:topeer:withcompletionhandler:)
- Metal is Apple silicon's native graphics and compute API:
  https://developer.apple.com/metal/
- Core ML loads and runs models on Apple platforms:
  https://developer.apple.com/documentation/coreml
- visionOS documents new RealityKit Gaussian splat APIs in visionOS 27:
  https://developer.apple.com/documentation/visionos
- Finder file sharing is the wired fallback path for local package transfer:
  https://support.apple.com/en-us/119585

## Build

```bash
swift build
swift run robot-scene-studio-mac
swift run robot-vision-lab --output ./GeneratedDataset
swift run robot-vision-lab --output ./GeneratedDataset --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --path-mode lawnmower --path-rows 20 --path-columns 50 --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --path-mode random --frame-count 1000 --path-seed 7 --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --render-preview --augment-dataset --augmentation-seed 42
swift run robot-vision-lab --output ./GeneratedDataset --splat ./room.ply --render-splat-points
swift run robot-vision-lab --output ./GeneratedDataset --splat ./Fixtures/sample_gaussian_splats.ply --render-metal-splats --metal-tile-size 16 --metal-max-splats 1000000 --metal-streaming-chunk-splats 250000
swift run robot-vision-lab --output ./GeneratedDatasetBinaryPLY --splat ./Fixtures/sample_gaussian_splats_binary.ply --render-metal-splats
swift run robot-vision-lab --output ./GeneratedDatasetSplat --splat ./Fixtures/sample_gaussian_splats.splat --render-metal-splats
swift run robot-vision-lab --output ./GeneratedDataset --export-sample-capture
swift run robot-vision-lab --validate-package ./GeneratedDataset/CaptureBundle
swift run robot-vision-lab --output ./GeneratedDataset --import-robotcapture ./GeneratedDataset/CaptureBundle --capture-holdout-every 5
swift run robot-vision-lab --output ./GeneratedDataset --capture-route ./GeneratedDataset/PreparedCapture/capture_route.json --align-capture-route
swift run robot-vision-lab --output ./GeneratedDataset --use-aligned-route --expand-capture-route --route-lateral-offsets=-0.2,0,0.2 --route-height-offsets=0 --route-yaw-offsets=-5,0,5
swift run robot-vision-lab --output ./GeneratedDataset --use-expanded-route --render-preview --evaluate-baseline --export-robotscene
swift run robot-vision-lab --output ./GeneratedDataset --evaluate-coreml --evaluate-model ./Model.mlpackage
swift run robot-vision-lab --output ./GeneratedDataset --plan-mlx-evaluation --evaluate-model ./mlx-model
swift run robot-vision-lab --output ./GeneratedDataset --write-model-adapter-schemas
swift run robot-vision-lab --output ./GeneratedDataset --write-mlx-training-package
swift run robot-vision-lab --output ./GeneratedDataset --plan-splat-training
swift run robot-vision-lab --output ./GeneratedDataset --metal-render-plan
```

The CLI writes `GeneratedDataset/dataset.json`, route files, import reports,
training plans, evaluation reports, and `.robotscene` packages. It remains a
developer tool for exercising the native contracts.

## Xcode Apps

```bash
xcodegen generate
xcodebuild -project RobotSceneStudio.xcodeproj -scheme RobotSceneStudioMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RobotSceneStudio.xcodeproj -scheme RobotSceneStudioCapture -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RobotSceneStudio.xcodeproj -scheme RobotSceneStudioVision -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`project.yml` is the source of truth for the generated Xcode project. It defines
the Mac workstation, iPhone capture client, and Vision Pro review app targets
against the local Swift package products. The app configuration lives under
`AppConfig/`, including entitlements, privacy usage strings, local-network
descriptions, Bonjour service declarations, document types, and exported package
UTTypes for `.robotcapture` and `.robotscene`. App icon asset catalogs live
under `AppAssets/`.

Set `DEVELOPMENT_TEAM` in `project.yml`, regenerate the project, and let Xcode
manage signing for physical iPhone, Mac, and Vision Pro deployment.

## Current Implementation

- `RobotSceneStudio.xcodeproj`: generated Xcode project with app targets for
  macOS, iOS, and visionOS.
- `AppConfig`: platform Info.plist and entitlement files for sandboxed macOS
  document access, iPhone camera/motion/AR/local-network permissions, Vision Pro
  document opening, package UTTypes, and Bonjour discovery.
- `AppAssets`: native app icon catalogs for all three app targets.
- `AppleDeviceCaptureSession`: iOS-gated capture coordinator that records
  `video.mov`, writes ARKit camera pose/intrinsics/tracking records to
  `frames.jsonl`, writes Core Motion records to `motion.jsonl`, captures LiDAR
  depth snapshots where available, exports RoomPlan geometry, and writes
  `.robotcapture` metadata.
- `RobotSceneStudioiPhoneApp`: native SwiftUI iPhone capture client with capture
  controls around `AppleDeviceCaptureSession`, camera/motion/ARKit readiness
  flows, live tracking/lighting/motion quality indicators, Finder-visible
  `.robotcapture` package browsing, Multipeer sender controls, and wired Finder
  fallback guidance.
- `RobotCaptureMultipeerTransfer`: app-controlled nearby iPhone-to-Mac transfer
  using Multipeer Connectivity resource transfer, explicit receiver-side
  pairing approval, send/receive progress, cancel/retry recovery hooks,
  completion events, and receipt reporting.
- `RobotSceneStudioMacApp`: native SwiftUI Mac workstation shell with
  `NavigationSplitView`, project browser, `.robotscene` document opening,
  Multipeer receiver controls, pairing accept/reject UI, receive progress,
  transfer receipts, Finder-copied `.robotcapture` import, `.robotcapture`
  health inspection, splat linking/inspection, route alignment anchors, route
  variant controls, failure-map viewing, Metal renderer budget controls,
  diagnostics, artifact browsing, and `.robotscene` export.
- `WorkstationModel`: Observation-backed Mac workstation controller that imports
  captures, prepares routes, links splats, builds dataset manifests, plans Metal
  rendering, runs the native Metal splat renderer, records RGB/depth/visibility
  render artifacts, receives iPhone packages through Multipeer Connectivity,
  loads `.robotscene` manifests and failure maps, aligns captured ARKit routes
  with manual anchors, generates robot-camera route variants, plans
  Apple-native MLX training, evaluates baseline model outputs, and exports
  Vision Pro scene packages.
- `FinderFileSharingFallbackGuide`: wired local transfer fallback for large
  capture packages.
- `RobotCaptureImporter`: Mac-side `.robotcapture` validation and ingest.
- `RobotCapturePreparer`: converts capture packages into routes, train/eval
  splits, and `prepared_splat_training_manifest.json`.
- `RobotRouteAligner`: estimates ARKit-to-splat transforms.
- `RobotRouteExpander`: generates robot-camera route variants from captured
  routes.
- `GaussianSplatImporter`: inspects `.ply` and `.splat` assets.
- `SplatPointProjectionRenderer`: CPU reference renderer for camera geometry
  validation only.
- `MetalRenderPlanner`: validates native Metal render readiness and device
  capability before the real Gaussian splat renderer.
- `MetalGaussianSplatRenderer`: native Metal renderer that loads Gaussian PLY
  and binary `.splat` properties, uploads splats into Metal buffers, projects
  splats in the vertex shader, projects anisotropic covariance into screen
  space, runs Metal compute passes for tile counts, prefix offsets, compaction,
  per-tile depth sorting, and vertex-buffer construction, composites Gaussian
  point discs on the GPU, and writes RGB plus dense Gaussian-footprint
  depth/visibility images, diagnostic depth/visibility summaries, and tile-bin
  products. Render-budget LOD uses deterministic uniform splat decimation across
  the full cloud instead of file-prefix truncation, and GPU streaming chunks keep
  per-frame Metal working sets bounded for larger scenes.
- `MetalGaussianSplatRenderConfiguration`: controls tile size and per-frame
  splat budget for larger Apple Silicon render jobs.
- `SplatTrainingJob`: Apple-native training plan for MLX/Create ML/Metal
  Performance Shaders workflows.
- `CoreMLDatasetEvaluator`: Core ML evaluation path for deployed on-device
  models using rendered RGB/depth/pose/intrinsics sample adapters.
- `MLXEvaluationPlan`: Apple Silicon MLX research/evaluation plan metadata.
- `RenderedDatasetLoader` and `NativeModelAdapterSchema`: Core ML and MLX
  input/output adapters for rendered RGB/depth, pose, intrinsics, confidence,
  obstacle/free-space probability, localization uncertainty, and failure-kind
  outputs.
- `MLXTrainingPackageBuilder`: writes a local Apple Silicon MLX training package
  with rendered-dataset loader code and Core ML export/conversion artifacts.
- `RobotScenePackageExporter`: writes `.robotscene` packages for Vision Pro
  spatial review.
- `SharedProjectFormatTools`: versioned `.robotcapture`/`.robotscene` helpers
  for validation, migration, artifact size policy checks, SHA-256 checksums,
  compaction cleanup, and human-readable project reports.
- `FailureMapMarker`: spatial markers for confident, blocked, uncertain,
  missing-view, ambiguous-view, bad-lighting, and low-texture regions, including
  calibrated markers from Core ML/MLX obstacle, free-space, uncertainty, and
  failure-kind outputs.

## Roadmap

1. Add real native app targets.
   - iPhone capture app.
   - Mac workstation app.
   - visionOS spatial viewer.

2. Finish the iPhone capture client.
   - SwiftUI capture workflow.
   - Live capture quality indicators.
   - AVFoundation video recording.
   - ARKit pose/intrinsics/tracking stream.
   - Core Motion stream.
   - LiDAR and RoomPlan capture where available.

3. Finish native Multipeer transfer UX.
   - Nearby Mac discovery.
   - Transfer progress.
   - Retry/cancel.
   - Transfer receipt.
   - Finder wired fallback import.

4. Build the Mac workstation.
   - Import `.robotcapture`.
   - Import or create Gaussian splats.
   - Align ARKit route coordinates to splat coordinates.
   - Generate robot-valid route variants.
   - Render robot-camera views with Metal.
   - Train/evaluate using Apple Silicon MLX and Core ML.
   - Export `.robotscene`.

5. Deepen the native Metal Gaussian splat renderer.
   - GPU projection, tile-reference counting, prefix offsets, compaction,
     per-tile sort, and vertex-buffer construction are in place.
   - Compute covariance projection now follows the same scale/rotation plus
     camera-Jacobian path as the CPU diagnostic projection.
   - GPU-derived dense depth and visibility images are in place.
   - Tile size and per-frame splat budgets are configurable.
   - Per-frame splat budgets now use deterministic LOD decimation.
   - GPU streaming chunks are in place for bounded per-frame Metal working sets.

6. Build the Vision Pro reviewer.
   - Open `.robotscene`.
   - Render Gaussian splats with RealityKit where supported.
   - Show robot routes, frustums, failure maps, and prediction overlays.
   - Replay robot-camera views spatially.

## Bloat Policy

Generated datasets, capture packages, scene packages, and Swift build products
are ignored by git. The repository stores source, package definitions, and
documentation. Large recordings and generated assets belong in `.robotcapture`
or `.robotscene` packages outside source control.
