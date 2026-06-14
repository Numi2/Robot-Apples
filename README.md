# LiDAR/Splat Robot Vision Lab

This repository is a Swift foundation for an Apple-first, three-device robotics
data pipeline:

1. Capture a real room with iPhone/iPad sensors.
2. Use RoomPlan/Object Capture metadata where it helps structured geometry.
3. Import or build a Gaussian Splat scene from RGB views.
4. Place a virtual robot camera inside the scene.
5. Render synthetic robot-camera datasets with labels and camera effects.
6. Export data for robot-vision training, evaluation, and Vision Pro review.

The product shape is deliberately not one app:

- iPhone: capture client for video, ARKit pose, LiDAR, motion, and RoomPlan data.
- Mac: training and dataset workstation for splat import/training, rendering,
  augmentation, MLX/Core ML evaluation, and package export.
- Vision Pro: immersive scene viewer for splats, robot routes, navigation
  graphs, predictions, and failure-map overlays.

Shared package formats:

- `.robotcapture`: iPhone-to-Mac capture package.
- `.robotscene`: Mac-to-Vision-Pro review and robotics asset package.

The primary local transfer policy is Multipeer Connectivity. Finder File
Sharing over USB, Bonjour/Network framework, iCloud/File Provider, and
AirDrop/share sheet are modeled as fallback paths.

The Multipeer service type is `robotcapture`. The iPhone/iPad capture client
uses the sender role to browse for a Mac receiver, and the Mac workstation uses
the receiver role to advertise, accept invitations, and store received capture
packages in an ingest inbox.

Finder File Sharing is the wired fallback for large local packages. Apple
documents that with macOS Catalina or later, Finder can share files between a
Mac and iOS/iPadOS devices over USB when the app supports File Sharing:
https://support.apple.com/en-us/119585

The current implementation is a buildable Swift package with core scene, camera,
path, augmentation, labeling, and dataset manifest types. It includes a CLI that
generates a deterministic dataset manifest from a sample robot path. Metal splat
rendering and iOS capture UI are the next integration layers.

## Build

```bash
swift build
swift run robot-vision-lab --output ./GeneratedDataset
swift run robot-vision-lab --output ./GeneratedDataset --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --path-mode lawnmower --path-rows 20 --path-columns 50 --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --path-mode random --frame-count 1000 --path-seed 7 --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --render-preview --augment-dataset --augmentation-seed 42
swift run robot-vision-lab --output ./GeneratedDataset --splat ./room.ply --render-preview
swift run robot-vision-lab --output ./GeneratedDataset --splat ./room.ply --render-splat-points
swift run robot-vision-lab --output ./GeneratedDataset --render-splat-external-dry-run
swift run robot-vision-lab --output ./GeneratedDataset --splat-renderer-command /path/to/splat-renderer --splat-renderer-args "--manifest {manifest} --output {output}"
swift run robot-vision-lab --output ./GeneratedDataset --export-sample-capture
swift run robot-vision-lab --output ./GeneratedDataset --import-robotcapture ./GeneratedDataset/CaptureBundle --capture-holdout-every 5
swift run robot-vision-lab --output ./GeneratedDataset --capture-route ./GeneratedDataset/PreparedCapture/capture_route.json --align-capture-route
swift run robot-vision-lab --output ./GeneratedDataset --use-aligned-route --render-preview --evaluate-baseline --export-robotscene
swift run robot-vision-lab --output ./GeneratedDataset --use-aligned-route --expand-capture-route --route-lateral-offsets=-0.2,0,0.2 --route-height-offsets=0 --route-yaw-offsets=-5,0,5
swift run robot-vision-lab --output ./GeneratedDataset --use-expanded-route --render-preview --evaluate-baseline --export-robotscene
swift run robot-vision-lab --output ./GeneratedDataset --capture-route ./GeneratedDataset/PreparedCapture/capture_route.json --render-preview --evaluate-baseline --export-robotscene
swift run robot-vision-lab --output ./GeneratedDataset --render-preview --evaluate-baseline
swift run robot-vision-lab --output ./GeneratedDataset --evaluate-coreml --evaluate-model ./Model.mlpackage
swift run robot-vision-lab --output ./GeneratedDataset --evaluate-mlx-command /path/to/mlx_eval.py --evaluate-model ./mlx-model --evaluate-mlx-args "--manifest {manifest} --output {output} --model {model}"
swift run robot-vision-lab --output ./GeneratedDataset --train-splat-dry-run
swift run robot-vision-lab --output ./GeneratedDataset --trainer-command /path/to/trainer
swift run robot-vision-lab --output ./GeneratedDataset --splat-training-manifest ./GeneratedDataset/PreparedCapture/prepared_splat_training_manifest.json --trainer-command /path/to/trainer --trainer-args "--manifest {manifest} --output {output}"
swift run robot-vision-lab --output ./GeneratedDataset --metal-render-plan
swift run robot-vision-lab --output ./GeneratedDataset --render-preview --evaluate-baseline --export-robotscene
```

The CLI writes `GeneratedDataset/dataset.json`, a manifest describing frames,
camera poses, expected render products, augmentations, and labels. With
`--render-preview`, it also writes deterministic preview RGB `.ppm` frames plus
depth, segmentation, and obstacle-label JSON files. These preview artifacts are
not photorealistic splats; they exercise the dataset contract until the Metal
Gaussian renderer is added.

With `--capture-route`, the CLI uses a prepared capture route instead of the
sample path or generated lawnmower/random paths. This is the route-driven Mac
workstation flow: import `.robotcapture`, prepare `capture_route.json`, render
synthetic robot-camera products from that captured path, evaluate failures, and
export the `.robotscene` review package.

With `--align-capture-route`, the CLI estimates an ARKit-to-splat scene
transform and writes `GeneratedDataset/AlignedCapture/aligned_capture_route.json`
plus `route_alignment_report.json`. The current automatic mode maps the captured
route bounds into the splat scene bounds, preserving vertical scale by default.
Use this as an initial alignment estimate; real projects should refine it with
landmark/control-point alignment once corresponding splat landmarks are known.
With `--use-aligned-route`, dataset generation uses the aligned route.

With `--expand-capture-route`, the CLI creates robot-camera route variants from
the prepared or aligned capture route and writes
`GeneratedDataset/ExpandedRoutes/expanded_robot_route.json` plus
`route_expansion_report.json`. Lateral, height, and yaw offsets multiply
together, so keep the lists tight for smoke runs and expand them intentionally
for larger dataset generation. With `--use-expanded-route`, dataset generation
uses the expanded route.

With `--render-splat-points` and an imported ASCII `.ply`, the CLI projects the
loaded splat points through the robot-camera intrinsics and writes RGB `.ppm`
frames. This is a CPU reference renderer for validating camera geometry before
the Metal Gaussian rasterizer replaces it.

With `--render-splat-external-dry-run`, the CLI writes
`GeneratedDataset/external_splat_render_report.json` describing how a supported
Gaussian Splat renderer would be invoked. With `--splat-renderer-command`, it
launches an external renderer against `GeneratedDataset/dataset.json`. If custom
args are omitted, the CLI passes `--manifest <dataset.json> --output
<GeneratedDataset>`. Custom renderer args can use `{manifest}` and `{output}`,
and the process environment receives `ROBOT_DATASET_MANIFEST` and
`ROBOT_RENDER_OUTPUT`. This is the current supported path for real
photorealistic splat rendering while native Metal rasterization is still under
development.

With `--augment-dataset`, the CLI applies deterministic image and pose
augmentation to rendered `.ppm` frames and pose labels. It writes
`rgb_augmented/`, `pose_augmented/`, and `augmentation_report.json`.

With `--path-mode lawnmower` or `--path-mode random`, the CLI replaces the
sample 5-frame path with a generated robot-camera path inside the scene bounds.
Use `--frame-count` for random walks or `--path-rows` and `--path-columns` for
grid coverage.

With `--export-sample-capture`, the CLI also writes a sample
`GeneratedDataset/CaptureBundle` package. The package includes
`robotcapture.json`, `video.mov` as the expected AVFoundation recording path,
`frames.jsonl` for timestamped ARKit camera transforms and intrinsics,
`motion.jsonl` for optional Core Motion samples, `session.json` for device and
lens metadata, `capture_bundle.json` for RGB/LiDAR/RoomPlan/Object Capture side
data, and `splat_training_manifest.json` for Gaussian Splat training handoff.

With `--import-robotcapture`, the CLI acts as the Mac workstation ingest step.
It accepts either a `.robotcapture` package directory or a direct
`robotcapture.json` path, decodes the frame/motion JSONL streams and session
metadata, and writes `GeneratedDataset/robotcapture_import_report.json` with
counts, transfer policy, and missing-resource warnings before training begins.
It also writes `GeneratedDataset/PreparedCapture/capture_route.json`,
`capture_evaluation_split.json`, `prepared_splat_training_manifest.json`, and
`robotcapture_prepare_report.json`. Use `--capture-holdout-every` to choose how
often captured frames are reserved for evaluation instead of splat training.

With `--evaluate-baseline`, the CLI writes
`GeneratedDataset/evaluation_report.json`, a local model-evaluation style report
over navigation targets, obstacle labels, segmentation availability, and
augmentation-driven failure cases. With `--evaluate-coreml --evaluate-model`, it
loads a Core ML model through Apple's `MLModel` APIs and writes predictions into
the same report schema. With `--evaluate-mlx-command`, it launches an external
MLX evaluator script or binary against `dataset.json`; args can use
`{manifest}`, `{output}`, and `{model}`, and the process environment receives
`ROBOT_DATASET_MANIFEST`, `ROBOT_EVALUATION_REPORT`, and `ROBOT_MODEL`.
Apple positions Core ML as the deployment path for on-device predictions and
MLX as the Apple-silicon research/fine-tuning path, so this split keeps the
workstation aligned with Apple's frameworks instead of reimplementing inference.

With `--train-splat-dry-run`, the CLI writes
`GeneratedDataset/splat_training_report.json` without launching a trainer. By
default it uses
`GeneratedDataset/PreparedCapture/prepared_splat_training_manifest.json` when
present, falling back to a generated sample manifest otherwise. With
`--trainer-command`, it launches an external Gaussian Splat trainer process
against that prepared manifest. If `--trainer-args` is omitted, the CLI passes
`--manifest <manifest path> --output <expected splat path>`. Custom trainer args
can use `{manifest}` and `{output}` placeholders, and the process environment
also receives `ROBOT_SPLAT_MANIFEST` and `ROBOT_SPLAT_OUTPUT`.

With `--metal-render-plan`, the CLI writes
`GeneratedDataset/metal_render_plan_report.json`, validating camera frames,
requested products, renderer settings, and local Metal device availability.

With `--export-robotscene`, the CLI writes
`GeneratedDataset/Project.robotscene/robotscene.json` plus a navigation graph,
failure map, route file, and dataset manifest for Vision Pro spatial review.
The failure map can now include multiple marker types per frame:
`badLighting` for exposure/blur/noise/compression risk, `blockedPrediction` for
blocked/free-space or scene-boundary risk, `uncertainLocalization` for
low-confidence evaluation signals, `missingTrainingViews` for isolated route
samples, `visualAmbiguity` for repeated/near-duplicate viewpoints, and
`lowTexture` for missing geometry/segmentation label support.

## Architecture

- `ScanSession`: describes a real-world capture session, including RGB frames,
  LiDAR frames, RoomPlan geometry, and Object Capture assets.
- `CapturePlan`: describes the intended Apple capture modes: RoomPlan, Object
  Capture, RGB video, and LiDAR depth.
- `CaptureBundleExporter`: writes a capture bundle and splat-training manifest
  that external Gaussian Splat training tools can consume.
- `RobotCapturePackageManifest`: describes the `.robotcapture` package sent from
  iPhone to Mac, with Multipeer Connectivity as the primary transfer method and
  Bonjour/Network framework, iCloud/File Provider, and AirDrop as fallbacks.
- `RobotCaptureFrameRecord`, `RobotCaptureMotionRecord`, and
  `RobotCaptureSessionMetadata`: define the JSONL/session contract for video,
  camera pose, intrinsics, tracking quality, optional IMU motion, and capture
  notes inside a `.robotcapture` package.
- `RobotCaptureImporter`: Mac-side ingest and validation for `.robotcapture`
  packages. It resolves package paths, decodes JSONL pose/motion streams, loads
  session and capture-bundle metadata, and reports missing large media or
  geometry assets.
- `RobotCaptureMultipeerTransfer`: app-controlled nearby transfer for
  `.robotcapture` packages. Sender mode browses for receivers and sends the
  package as an `MCSession` resource; receiver mode advertises, accepts
  invitations, moves the received resource into a Mac ingest inbox, and writes a
  transfer receipt.
- `FinderFileSharingFallbackGuide`: documents the wired Finder File Sharing
  fallback for copying `.robotcapture` packages from iPhone/iPad to the Mac
  ingest folder when Multipeer is unavailable or impractical for large files.
- `RobotCapturePreparer`: turns an imported capture package into a calibrated
  camera route, deterministic train/evaluation frame split, and prepared
  Gaussian Splat training manifest for the Mac workstation.
- `RobotRouteAligner`: estimates and applies an ARKit-to-splat scene transform,
  writes an aligned capture route, and reports the transform, source route
  bounds, scene bounds, and alignment warnings.
- `RobotRouteExpander`: generates robot-camera route variants from a captured
  camera path using lateral, height, and yaw offsets, with optional scene-bounds
  clipping and a report for dataset size control.
- `RobotScenePackageManifest`: describes the `.robotscene` package opened by
  Vision Pro, including splat scene, dataset, navigation graph, failure map, and
  review assets.
- `FailureMapMarker`: frame-positioned spatial review marker for confident,
  blocked, uncertain, missing-view, ambiguous-view, bad-lighting, and low-texture
  regions. The `.robotscene` exporter derives these from route geometry,
  requested products, augmentations, label sources, and optional evaluation
  report predictions.
- `AppleDeviceCaptureSession`: iOS-only capture coordinator that records
  `video.mov` with AVFoundation, streams ARKit camera pose/intrinsics/tracking
  records to `frames.jsonl`, streams Core Motion device-motion records to
  `motion.jsonl`, captures LiDAR depth snapshots where available, exports
  RoomPlan geometry, and writes the `.robotcapture` package metadata.
- `GaussianSplatScene`: points to an imported or trained splat and preserves the
  real-world alignment transform needed for robot-camera rendering.
- `GaussianSplatImporter`: inspects imported `.ply` and `.splat` assets. ASCII
  PLY inspection computes bounds and detects common Gaussian properties such as
  color, opacity, scale, rotation, and spherical harmonics.
- `SplatTrainingJob`: describes a Gaussian Splat training run from captured RGB
  views and writes a report for dry-run or external trainer execution.
- `MetalRenderPlanner`: validates the scene, robot camera, requested dataset
  products, render configuration, and Metal device capabilities before Gaussian
  splat rasterization.
- `SplatPointProjectionRenderer`: CPU reference renderer that projects imported
  ASCII PLY splat points into robot-camera RGB frames.
- `ExternalSplatRenderJob`: integration contract for supported Gaussian Splat
  renderer binaries. It passes the dataset manifest and output directory to an
  external renderer and records stdout, stderr, exit status, diagnostics, and
  rendered RGB frame counts.
- `DatasetAugmentor`: applies deterministic exposure, noise, blur,
  compression-like quantization, robot height jitter, and yaw jitter.
- `RobotCameraRig`: describes camera height, intrinsics, lens model, and mount.
- `RobotPath`: provides timestamped poses for synthetic frame generation.
- `RobotPathGenerator`: creates deterministic scene-bounded lawnmower and
  random-walk robot-camera paths for larger datasets.
- `DatasetGenerator`: combines a splat scene, robot camera rig, path, labels,
  and augmentations into an exportable manifest.
- `DatasetManifest`: stable JSON contract for later renderers and ML tooling.
- `BaselineDatasetEvaluator`: writes a local evaluation report over generated
  frames. It uses manifest labels and augmentation metadata today and establishes
  the contract for Core ML or MLX execution later.
- `CoreMLDatasetEvaluator`: loads a Core ML model with `MLModel` when Core ML is
  available and writes frame-level predictions into `evaluation_report.json`.
- `MLXEvaluationRunner`: process integration for Apple MLX research scripts or
  binaries. It passes `dataset.json`, output report path, and optional model path
  to the MLX command and records a process report.

## Near-Term Implementation Targets

- Add an iOS app target and SwiftUI capture screen around the AVFoundation /
  ARKit / Core Motion `AppleDeviceCaptureSession`.
- Add Mac and iPhone UI surfaces around `RobotCaptureMultipeerTransfer`,
  including peer selection, progress display, cancel/retry, and post-receive
  import.
- Replace the Metal render planner with actual `.ply`/`.splat` Gaussian
  rasterization shaders.
- Add depth approximation and segmentation projection from RoomPlan/Object
  Capture geometry.
- Replace the placeholder Core ML feature-provider assumptions with a model
  adapter layer for specific deployed model input/output schemas.
