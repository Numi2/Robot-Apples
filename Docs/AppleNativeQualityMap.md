# Apple-Native Quality Map

Robot Scene Studio is an Apple-native three-device system. Product code must use
iPhone capture frameworks, Mac Apple Silicon rendering/training/evaluation, and
Vision Pro spatial review. Developer fixtures may exist only behind explicit
fixture/export commands and must not be presented as production output.

## Removed Product Paths

- `PreviewSyntheticRenderer`: removed. It generated gradient RGB/depth and
  bounds-derived labels that could be mistaken for rendered scene products.
- `SplatPointProjectionRenderer`: removed. Point projection is not the product
  renderer; native Metal Gaussian splat rendering is the product path.
- `BaselineDatasetEvaluator`: removed. Evaluation must come from Core ML model
  execution or an MLX evaluation plan, not manifest heuristics.
- `LocalModelRuntime.baseline`: removed. Supported runtimes are `coreML` and
  `mlx`.

## Blocked Legacy CLI Flags

- `--render-preview`: rejected with a clean CLI error.
- `--render-dev-preview`: rejected with a clean CLI error.
- `--render-splat-points`: rejected with a clean CLI error.
- `--evaluate-baseline`: rejected with a clean CLI error.

Use `--render-apple-native` for native Metal Gaussian splat rendering. Use
`--evaluate-coreml --evaluate-model <Model.mlpackage>` for real on-device model
evaluation, or `--plan-mlx-evaluation` for Apple Silicon research evaluation.

## Retained Fixture Paths

- `--demo`: creates developer dataset recipes only when explicitly requested.
- `--export-demo-capture`: writes a fixture `.robotcapture` package for local
  validation of schemas, package validation, and import tooling.

Fixture paths must not be wired into Mac workstation product actions.

## Apple Documentation Anchors

- Metal command encoders and draw/compute dispatch are the renderer foundation.
  The product renderer must keep splat projection, binning, sorting,
  compositing, and dense depth/visibility generation in Metal.
- Core ML is the deployment/evaluation runtime for shipped models on Apple
  devices. CLI and workstation evaluation must execute real model outputs.
- MLX is the Apple Silicon research and fine-tuning path. MLX outputs must feed
  Core ML/Core AI deployment artifacts rather than becoming a separate product
  runtime.

## Remaining High-Ambition Replacement Targets

- Replace any generated fixture dataset dependencies in product docs with
  `.robotcapture` and imported splat workflows.
- Expand Metal output validation so dense RGB, depth, visibility, tile-bin, and
  timing products are required before training package generation.
- Make failure-map calibration require real Core ML reports when presenting
  model predictions; dataset-only markers should be labeled as capture/render
  diagnostics, not model evaluation.
- Promote structured geometry from metadata priors to spatial masks by parsing
  RoomPlan/Object Capture geometry into renderable, queryable scene layers.
- Add CI-quality command coverage for strict package validation, native Metal
  render planning, MLX package generation, and Core ML evaluation plumbing.
