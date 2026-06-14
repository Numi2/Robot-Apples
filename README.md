# Robot Scene Studio

Robot Scene Studio is an Apple-native robotics scene system with three device
roles and one shared project format.

- iPhone captures real robot-environment sessions.
- Mac imports captures, aligns routes, renders datasets, trains/evaluates
  models, and exports review packages.
- Vision Pro opens exported scenes for spatial inspection of splats, routes,
  navigation assets, and failure maps.

The product center is the native Apple app stack. The command-line tool is only
developer tooling for exercising package contracts and pipeline components.

## Shared Formats

- `.robotcapture`: iPhone-to-Mac capture package containing `video.mov`,
  ARKit pose/intrinsics/tracking records, Core Motion records, optional LiDAR
  and RoomPlan artifacts, session metadata, checksums, and a project report.
- `.robotscene`: Mac-to-Vision-Pro package containing the splat scene, robot
  routes, dataset manifest, navigation graph, failure map, evaluation reports,
  package validation data, checksums, and a project report.

Both formats are versioned, migratable, validated, and governed by artifact
size policies.

## Native Apps

### iPhone Capture

- SwiftUI capture client.
- AVFoundation `AVCaptureMovieFileOutput` recording to `video.mov`.
- ARKit camera/world tracking written to `frames.jsonl` with timestamp, camera
  transform, intrinsics, and tracking quality.
- Core Motion accelerometer, gyroscope, and device-motion records written to
  `motion.jsonl`.
- `session.json` with device, lens, resolution, fps, user notes, and capture
  package metadata.
- LiDAR depth snapshots and RoomPlan export where available.
- Capture quality indicators.
- `.robotcapture` package browser.
- Multipeer sender to Mac.
- Finder file sharing support for wired local transfer.

The required iPhone capture output is a `.robotcapture` package containing:

- `video.mov`
- `frames.jsonl`
- `motion.jsonl`
- `session.json`
- Optional LiDAR, RoomPlan, and object-capture artifacts
- Manifest, checksums, and package report

### Mac Workstation

- SwiftUI/AppKit workstation shell.
- Project browser and `.robotscene` document flow.
- Multipeer receiver with pairing, progress, cancel/retry, receipts, and inbox
  ingest.
- Finder-copied `.robotcapture` import.
- Capture health inspection and route preparation.
- Splat import/linking plus route-derived splat seed generation when no trained
  or imported splat is linked.
- Manual ARKit-to-splat anchor alignment, coordinate transform editing, and
  floor/height constraints.
- Robot-valid route generation, route variants, navigation graph editing, and
  coverage analysis.
- Native Metal Gaussian splat renderer with GPU projection, covariance
  projection, tile counting, prefix offsets, compaction, per-tile sort,
  compositing, dense depth/visibility products, LOD decimation, streaming
  chunks, and render timing reports.
- Apple Silicon ML package generation for MLX training and Core ML export.
- Core ML evaluation, failure-map calibration, and model comparison reports.
- `.robotscene` export for Vision Pro review.

### Vision Pro Review

- SwiftUI/RealityKit spatial review app shell.
- `.robotscene` package loading.
- Gaussian splat scene reference, route overlays, camera frustums, navigation
  graph, and failure-map markers.

## Core Modules

- `AppleDeviceCaptureSession`: iOS capture coordinator for AVFoundation,
  ARKit, Core Motion, LiDAR, RoomPlan, and `.robotcapture` packaging.
- `RobotCaptureMultipeerTransfer`: Multipeer Connectivity sender/receiver,
  pairing, progress, retry/cancel, and receipts.
- `RobotCaptureImporter` and `RobotCapturePreparer`: Mac ingest, validation,
  route creation, train/eval split, and `prepared_splat_training_manifest.json`.
- `SplatTrainingPackageBuilder`: writes Apple MLX training assets for building
  a Gaussian splat PLY from captured RGB views, ARKit/RoomPlan-aligned poses,
  camera intrinsics, tracking quality, and deterministic train/validation splits.
- `GaussianSplatImporter`: `.ply` and binary `.splat` inspection.
- `RouteDerivedSplatSeedWriter`: valid route-derived Gaussian splat seed PLY
  generation from captured camera poses.
- `RobotRouteAligner`, `RobotRouteExpander`, and `RouteIntelligenceAnalyzer`:
  coordinate alignment, route variants, robot-valid paths, graph edits,
  confidence metrics, and coverage analysis.
- `MetalGaussianSplatRenderer`: native Apple Metal Gaussian splat renderer and
  dataset render backend.
- `RenderedDatasetLoader`, `NativeModelAdapterSchema`, `CoreMLDatasetEvaluator`,
  `MLXTrainingPackageBuilder`, `FailureMapCalibrationReporter`, and
  `ModelComparisonReporter`: Apple Silicon ML dataset loading, adapter schemas,
  dense RGB/depth/visibility tensor loading, Core ML evaluation, MLX training
  package generation, failure-map calibration, and model comparison.
- `RenderedFailureLabeler`: derives blocked, missing-view, ambiguity,
  low-texture, and lighting failure labels from rendered RGB/depth/visibility
  products for MLX/Core ML supervision and Vision Pro review markers.
- `MLXTrainingPackageBuilder`: trains a compact Apple MLX model from fused
  pose, intrinsics, RGB statistics, depth coverage, visibility coverage, and
  rendered failure labels, then provides a Core ML export path.
- `CoreMLDatasetEvaluator`: inspects Core ML models, supplies fused
  `scene_features` inputs when exported from MLX, and maps vector outputs back
  to free-space, obstacle, localization uncertainty, and failure-score
  predictions.
- `RobotScenePackageExporter` and `SharedProjectFormatTools`: `.robotscene`
  export, validation, migration, checksum, compaction, and reporting.

## Build

```bash
swift build
xcodegen generate
xcodebuild -project RobotSceneStudio.xcodeproj -scheme RobotSceneStudioMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RobotSceneStudio.xcodeproj -scheme RobotSceneStudioCapture -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RobotSceneStudio.xcodeproj -scheme RobotSceneStudioVision -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`project.yml` is the source of truth for the generated Xcode project. App
configuration lives under `AppConfig/`; icon asset catalogs live under
`AppAssets/`. Set `DEVELOPMENT_TEAM` in `project.yml` before physical-device
deployment.

## Developer CLI

Production CLI commands require explicit inputs.

```bash
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --path-mode lawnmower --path-rows 20 --path-columns 50 --render-preview
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --capture-route ./PreparedCapture/capture_route.json --align-capture-route
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-aligned-route --expand-capture-route
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-expanded-route --render-metal-splats
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-expanded-route --evaluate-coreml --evaluate-model ./Model.mlpackage --export-robotscene
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-expanded-route --write-mlx-training-package
swift run robot-vision-lab --output ./RobotSceneWork --splat-training-manifest ./PreparedCapture/prepared_splat_training_manifest.json --plan-splat-training
swift run robot-vision-lab --output ./RobotSceneWork --splat-training-manifest ./PreparedCapture/prepared_splat_training_manifest.json --write-splat-training-package
swift run robot-vision-lab --validate-package ./RobotSceneWork/Project.robotscene
```

Synthetic developer data is isolated behind explicit demo flags:

```bash
swift run robot-vision-lab --output ./DemoRobotScene --demo --render-preview
swift run robot-vision-lab --output ./DemoRobotScene --export-demo-capture
```

## Apple Documentation Anchors

- AVFoundation movie recording: https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput
- ARKit camera pose/intrinsics: https://developer.apple.com/documentation/arkit/arcamera/transform
- Core Motion: https://developer.apple.com/documentation/coremotion
- RoomPlan captured room export: https://developer.apple.com/documentation/roomplan/capturedroom
- Multipeer Connectivity `MCSession`: https://developer.apple.com/documentation/multipeerconnectivity/mcsession
- Metal: https://developer.apple.com/metal/
- Core ML: https://developer.apple.com/documentation/coreml
- visionOS / RealityKit: https://developer.apple.com/documentation/visionos
- Finder wired transfer: https://support.apple.com/en-us/119585

## Next Work

- Add full RealityKit Gaussian splat rendering on visionOS SDKs that expose the
  native splat APIs.
- Add visual anchor picking in the Mac workstation renderer instead of numeric
  anchor entry only.
- Add signed physical-device deployment validation runs for iPhone, Mac, and
  Vision Pro.

## Repository Policy

Generated datasets, capture packages, scene packages, recordings, and Swift
build products stay out of source control. The repository stores source code,
app configuration, package definitions, fixtures, and documentation.
