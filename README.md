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
swift run robot-vision-lab --output ./GeneratedDataset --splat ./Fixtures/sample_gaussian_splats.ply --render-metal-splats
swift run robot-vision-lab --output ./GeneratedDataset --export-sample-capture
swift run robot-vision-lab --output ./GeneratedDataset --import-robotcapture ./GeneratedDataset/CaptureBundle --capture-holdout-every 5
swift run robot-vision-lab --output ./GeneratedDataset --capture-route ./GeneratedDataset/PreparedCapture/capture_route.json --align-capture-route
swift run robot-vision-lab --output ./GeneratedDataset --use-aligned-route --expand-capture-route --route-lateral-offsets=-0.2,0,0.2 --route-height-offsets=0 --route-yaw-offsets=-5,0,5
swift run robot-vision-lab --output ./GeneratedDataset --use-expanded-route --render-preview --evaluate-baseline --export-robotscene
swift run robot-vision-lab --output ./GeneratedDataset --evaluate-coreml --evaluate-model ./Model.mlpackage
swift run robot-vision-lab --output ./GeneratedDataset --plan-mlx-evaluation --evaluate-model ./mlx-model
swift run robot-vision-lab --output ./GeneratedDataset --write-model-adapter-schemas
swift run robot-vision-lab --output ./GeneratedDataset --plan-splat-training
swift run robot-vision-lab --output ./GeneratedDataset --metal-render-plan
```

The CLI writes `GeneratedDataset/dataset.json`, route files, import reports,
training plans, evaluation reports, and `.robotscene` packages. It remains a
developer tool for exercising the native contracts.

## Current Implementation

- `AppleDeviceCaptureSession`: iOS-gated capture coordinator that records
  `video.mov`, writes ARKit camera pose/intrinsics/tracking records to
  `frames.jsonl`, writes Core Motion records to `motion.jsonl`, captures LiDAR
  depth snapshots where available, exports RoomPlan geometry, and writes
  `.robotcapture` metadata.
- `RobotCaptureMultipeerTransfer`: app-controlled nearby iPhone-to-Mac transfer
  using Multipeer Connectivity resource transfer, progress, completion, and
  receipt reporting.
- `RobotSceneStudioMacApp`: native SwiftUI Mac workstation shell with
  `NavigationSplitView`, package import controls, pipeline actions, diagnostics,
  artifact browsing, and `.robotscene` export.
- `WorkstationModel`: Observation-backed Mac workstation controller that imports
  captures, prepares routes, links splats, builds dataset manifests, plans Metal
  rendering, plans Apple-native MLX training, evaluates baseline model outputs,
  and exports Vision Pro scene packages.
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
  properties, uploads splats into Metal buffers, projects splats in the vertex
  shader, builds tile bins with back-to-front draw ordering, projects
  anisotropic covariance into screen space, composites Gaussian point discs on
  the GPU, and writes RGB, depth, visibility, and tile-bin products.
- `SplatTrainingJob`: Apple-native training plan for MLX/Create ML/Metal
  Performance Shaders workflows.
- `CoreMLDatasetEvaluator`: Core ML evaluation path for deployed on-device
  models.
- `MLXEvaluationPlan`: Apple Silicon MLX research/evaluation plan metadata.
- `NativeModelAdapterSchema`: Core ML and MLX input/output schema contract for
  image, depth, pose, intrinsics, confidence, obstacle/free-space probability,
  localization uncertainty, and failure-kind outputs.
- `RobotScenePackageExporter`: writes `.robotscene` packages for Vision Pro
  spatial review.
- `FailureMapMarker`: spatial markers for confident, blocked, uncertain,
  missing-view, ambiguous-view, bad-lighting, and low-texture regions.

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
   - Move tile binning/sorting from CPU preparation into Metal compute passes.
   - Use covariance ellipse orientation in fragment weighting, not just radius.
   - Add compute-pass depth and visibility textures instead of JSON summaries.
   - Add tile-based memory and large-scene streaming.

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
