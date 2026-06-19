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
- LiDAR depth snapshots where available, stored as Float32 meters with per-frame
  metadata and optional ARKit confidence maps; RoomPlan export where available.
- Capture quality indicators.
- `.robotcapture` package browser.
- Multipeer sender to Mac.
- Finder file sharing support for wired local transfer.

The required iPhone capture output is a `.robotcapture` package containing:

- `video.mov`
- `frames.jsonl`
- `motion.jsonl`
- `session.json`
- LiDAR `lidar/depth_*.f32` plus `lidar/depth_*.json` metadata when LiDAR mode
  is enabled, optional `lidar/confidence_*.bin`, RoomPlan, and object-capture
  artifacts
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
- MetalSplatter-backed interactive splat preview for linked PLY, SPZ, and
  `.splat` assets.
- Manual ARKit-to-splat anchor alignment, coordinate transform editing, and
  floor/height constraints.
- Robot-valid route generation, route variants, navigation graph editing, and
  coverage analysis.
- Native Metal Gaussian splat renderer with GPU projection, covariance
  projection, tile counting, prefix offsets, compaction, per-tile sort,
  compositing, dense depth/visibility products, Float32 metric depth sidecars,
  synthetic LiDAR scan products,
  LOD decimation, streaming chunks, and render timing reports.
- Training-ready dataset augmentation that writes `dataset_augmented.json` with
  augmented RGB products and pose labels plus a native product readiness report.
- Mac and CLI MLX package generation prefer `dataset_augmented.json` when it is
  present and ready, so Apple Silicon training consumes the robot-camera
  degradation set rather than only the clean render path.
- Apple Silicon ML package generation for MLX training and Core ML export.
- Core ML evaluation, failure-map calibration, and model comparison reports.
- `.robotscene` export for Vision Pro review.

### Vision Pro Review

- SwiftUI/RealityKit spatial review app shell.
- `.robotscene` package loading.
- Gaussian splat scene reference, route overlays, camera frustums, navigation
  graph, and failure-map markers.
- MetalSplatter-backed immersive Gaussian splat exploration for exported scene
  splats on visionOS 26+.

## Core Modules

- `AppleDeviceCaptureSession`: iOS capture coordinator for AVFoundation,
  ARKit, Core Motion, LiDAR, RoomPlan, and `.robotcapture` packaging.
- `RobotCaptureMultipeerTransfer`: Multipeer Connectivity sender/receiver,
  pairing, progress, retry/cancel, and receipts.
- `RobotCaptureImporter` and `RobotCapturePreparer`: Mac ingest, validation,
  route creation, train/eval split, and `prepared_splat_training_manifest.json`.
- `StructuredGeometryAnalyzer`: validates RoomPlan and Object Capture geometry
  assets, records format/size/existence, and writes a structured-geometry report
  for alignment, obstacle, and segmentation priors.
- `StructuredGeometryProductWriter`: promotes RoomPlan/Object Capture inputs
  into queryable scene layers, per-frame segmentation hints, obstacle-prior
  reports, and failure-map evidence.
- `SplatTrainingPackageBuilder`: writes Apple MLX training assets for building
  a Gaussian splat PLY from captured RGB views, ARKit/RoomPlan-aligned poses,
  camera intrinsics, strict ARKit LiDAR Float32 depth priors, tracking quality,
  and deterministic train/validation splits.
- `SplatTrainingPackageBuilder` also writes the production Splatfacto/gsplat
  path: a self-contained Nerfstudio dataset, `transforms.json`,
  depth-derived `sparse_pc.ply` initialization when available,
  `run_production_splat_optimizer.py`, dataset preflight output, PSNR/SSIM/LPIPS
  eval gates, export provenance, and SHA-256 summaries.
- `GaussianSplatImporter`: `.ply`, `.spz`, and binary `.splat` inspection/linking.
- `RobotSceneStudioSplatViewer`: shared MetalSplatter integration for iOS,
  macOS, and visionOS. It uses MetalSplatter/SplatIO for PLY, SPZ, and `.splat`
  loading, MetalKit preview rendering on iOS/macOS, and a visionOS compositor
  renderer for stereo immersive review.
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
  dense RGB/metric-depth/visibility tensors, synthetic LiDAR geometry features,
  structured RoomPlan/Object Capture priors, Core ML evaluation, MLX training
  package generation, native-evidence failure-map calibration, and model
  comparison.
- `RenderedFailureLabeler`: derives blocked, missing-view, ambiguity,
  low-texture, and lighting failure labels from rendered RGB/depth/visibility
  products, preferring Float32 meter depth sidecars over visualization images
  for near-field geometry, for MLX/Core ML supervision and Vision Pro review
  markers.
- `RenderedLiDARSimulator`: derives fixed-ring LiDAR-style ray scans from
  rendered Float32 camera-space depth and visibility products, including
  robot-camera intrinsics ray reconstruction, camera z-depth to ray-range
  conversion, deterministic dropout, intensity, range, support metrics, 3D
  camera/world returns, and JSON reports for robot datasets.
- `FailureMapCalibrationReporter`: fuses Core ML/MLX model outputs with native
  rendered failure labels and synthetic LiDAR geometry, reporting model/native
  agreement plus blocked, uncertain, and missing-view rates for Mac and Vision
  Pro review.
- `FailureMapMarker`: stores review-ready marker provenance, including model
  prediction source, native render evidence, synthetic LiDAR geometry metrics,
  route coverage, image quality, scene-boundary, and geometry-prior sources.
- `MLXTrainingPackageBuilder`: trains a compact Apple MLX model from fused
  pose, intrinsics, RGB statistics, depth coverage, visibility coverage, and
  synthetic LiDAR geometry/occupancy metrics plus structured segmentation and
  obstacle priors, then provides a Core ML export path for the same
  `scene_features` contract.
- `CoreMLDatasetEvaluator`: inspects Core ML models, supplies fused
  70-value `scene_features` inputs when exported from MLX, and maps vector
  outputs back to free-space, obstacle, localization uncertainty, and
  failure-score predictions.
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

The package uses Swift tools 6.2 and requires macOS 15+, iOS 18+, and
visionOS 26+ for the immersive MetalSplatter renderer path.

`project.yml` is the source of truth for the generated Xcode project. App
configuration lives under `AppConfig/`; icon asset catalogs live under
`AppAssets/`. Set `DEVELOPMENT_TEAM` in `project.yml` before physical-device
deployment.

## Developer CLI

Production CLI commands require explicit inputs.
The active quality map is maintained in
[`Docs/AppleNativeQualityMap.md`](Docs/AppleNativeQualityMap.md).

```bash
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --path-mode lawnmower --path-rows 20 --path-columns 50 --render-apple-native
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --capture-route ./PreparedCapture/capture_route.json --align-capture-route
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-aligned-route --expand-capture-route
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-expanded-route --render-apple-native
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-expanded-route --evaluate-coreml --evaluate-model ./Model.mlpackage --export-robotscene
swift run robot-vision-lab --output ./RobotSceneWork --splat ./room.ply --use-expanded-route --write-mlx-training-package
swift run robot-vision-lab --output ./RobotSceneWork --splat-training-manifest ./PreparedCapture/prepared_splat_training_manifest.json --plan-splat-training
swift run robot-vision-lab --output ./RobotSceneWork --splat-training-manifest ./PreparedCapture/prepared_splat_training_manifest.json --write-splat-training-package
swift run robot-vision-lab --output ./RobotSceneWork --splat-training-manifest ./PreparedCapture/prepared_splat_training_manifest.json --run-splat-training --splat-training-python /path/to/mlx/bin/python3 --splat-training-splats-per-frame 64 --splat-training-epochs 100
swift run robot-vision-lab --validate-package ./RobotSceneWork/Project.robotscene
```

Set `ROBOT_SCENE_PYTHON=/path/to/mlx/bin/python3` to make the Mac workstation
app and CLI use the same Apple MLX Python environment.

Developer fixture capture export remains isolated behind an explicit demo flag:

```bash
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
