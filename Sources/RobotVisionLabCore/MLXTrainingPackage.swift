import Foundation

public struct MLXTrainingPackageManifest: Codable, Equatable, Sendable {
    public var id: String
    public var datasetManifestURL: URL
    public var adapterSchemaURL: URL
    public var trainScriptURL: URL
    public var exportScriptURL: URL
    public var datasetLoaderURL: URL
    public var sampleCount: Int
    public var notes: [String]

    public init(
        id: String,
        datasetManifestURL: URL,
        adapterSchemaURL: URL,
        trainScriptURL: URL,
        exportScriptURL: URL,
        datasetLoaderURL: URL,
        sampleCount: Int,
        notes: [String]
    ) {
        self.id = id
        self.datasetManifestURL = datasetManifestURL
        self.adapterSchemaURL = adapterSchemaURL
        self.trainScriptURL = trainScriptURL
        self.exportScriptURL = exportScriptURL
        self.datasetLoaderURL = datasetLoaderURL
        self.sampleCount = sampleCount
        self.notes = notes
    }
}

public struct MLXTrainingPackageBuilder: Sendable {
    public init() {}

    public func writePackage(
        manifest: DatasetManifest,
        datasetManifestURL: URL,
        outputDirectory: URL,
        schema: NativeModelAdapterSchema = .defaultMLXTrainingSchema()
    ) throws -> MLXTrainingPackageManifest {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let schemaURL = outputDirectory.appendingPathComponent("native_model_adapter_schema.json")
        let loaderURL = outputDirectory.appendingPathComponent("robot_scene_dataset.py")
        let trainURL = outputDirectory.appendingPathComponent("train_robot_scene_mlx.py")
        let exportURL = outputDirectory.appendingPathComponent("export_coreml.py")
        let packageURL = outputDirectory.appendingPathComponent("mlx_training_package.json")

        try NativeModelAdapterSchemaWriter().write(schema, to: schemaURL)
        try datasetLoaderScript().write(to: loaderURL, atomically: true, encoding: .utf8)
        try trainingScript().write(to: trainURL, atomically: true, encoding: .utf8)
        try exportScript().write(to: exportURL, atomically: true, encoding: .utf8)

        let package = MLXTrainingPackageManifest(
            id: "\(manifest.recipeID)-mlx-training-package",
            datasetManifestURL: datasetManifestURL,
            adapterSchemaURL: schemaURL,
            trainScriptURL: trainURL,
            exportScriptURL: exportURL,
            datasetLoaderURL: loaderURL,
            sampleCount: manifest.frames.count,
            notes: [
                "Runs locally on Apple Silicon with MLX unified memory and automatic differentiation.",
                "Loads rendered RGB/depth/visibility plus pose/intrinsics and fused scene features from dataset.json through robot_scene_dataset.py.",
                "Exports deployment artifacts through Apple's Core ML Tools conversion path for Core ML app integration."
            ]
        )
        try JSONEncoder.robotVisionLabEncoder.encode(package).write(to: packageURL)
        return package
    }

    private func datasetLoaderScript() -> String {
        """
        #!/usr/bin/env python3
        import json
        from pathlib import Path

        import numpy as np

        def _read_pnm(path, magic):
            data = Path(path).read_bytes()
            tokens = []
            i = 0
            while len(tokens) < 4:
                while data[i] in b" \\n\\r\\t":
                    i += 1
                if data[i] == ord("#"):
                    while data[i] != ord("\\n"):
                        i += 1
                    continue
                start = i
                while data[i] not in b" \\n\\r\\t":
                    i += 1
                tokens.append(data[start:i].decode("ascii"))
            while data[i] in b" \\n\\r\\t":
                i += 1
            if tokens[0] != magic:
                raise ValueError(f"Unexpected image magic {tokens[0]} for {path}")
            width, height, max_value = int(tokens[1]), int(tokens[2]), max(int(tokens[3]), 1)
            return width, height, max_value, data[i:]

        def read_rgb_chw(path):
            width, height, max_value, payload = _read_pnm(path, "P6")
            image = np.frombuffer(payload[: width * height * 3], dtype=np.uint8).astype(np.float32) / float(max_value)
            return image.reshape(height, width, 3).transpose(2, 0, 1)

        def read_depth_chw(path):
            width, height, max_value, payload = _read_pnm(path, "P5")
            image = np.frombuffer(payload[: width * height], dtype=np.uint8).astype(np.float32) / float(max_value)
            return image.reshape(1, height, width)

        def read_visibility_chw(path):
            return read_depth_chw(path)

        def vector(value, count):
            if isinstance(value, dict):
                keys = ["x", "y", "z", "w"][:count]
                return [value[key] for key in keys]
            return value[:count]

        def pose_vector(frame):
            pose = frame["cameraPose"]
            p = vector(pose["position"], 3)
            q = vector(pose["orientation"]["vector"], 4)
            return np.array([p[0], p[1], p[2], q[0], q[1], q[2], q[3]], dtype=np.float32)

        def intrinsics_vector(camera):
            focal = vector(camera["focalLengthPixels"], 2)
            principal = vector(camera["principalPointPixels"], 2)
            fx = focal[0]
            fy = focal[1]
            cx = principal[0]
            cy = principal[1]
            return np.array([fx, fy, cx, cy], dtype=np.float32)

        def product_url(frame, product):
            for item in frame["products"]:
                if item["product"] == product:
                    return item["url"].replace("file://", "")
            return None

        def failure_signal(path):
            if not path:
                return np.array([0.65, 0.20, 0.35, 0.0], dtype=np.float32)
            report = json.loads(Path(path).read_text())
            labels = report.get("labels", [])
            kinds = {item.get("kind"): float(item.get("confidence", 0.0)) for item in labels}
            blocked = max(kinds.get("blockedPrediction", 0.0), 0.0)
            uncertain = max(kinds.get("uncertainLocalization", 0.0), kinds.get("missingTrainingViews", 0.0), kinds.get("visualAmbiguity", 0.0))
            degraded = max(kinds.get("badLighting", 0.0), kinds.get("lowTexture", 0.0))
            free_space = max(0.0, 1.0 - max(blocked, uncertain * 0.5))
            failure_score = max(blocked, uncertain, degraded)
            return np.array([free_space, blocked, uncertain, failure_score], dtype=np.float32)

        def lidar_summary(path):
            if not path:
                return None
            report = json.loads(Path(path).read_text())
            metrics = report.get("metrics", {})
            return {
                "ray_count": int(metrics.get("rayCount", 0)),
                "valid_ray_count": int(metrics.get("validRayCount", 0)),
                "dropout_rate": float(metrics.get("dropoutRate", 0.0)),
                "mean_range_meters": metrics.get("meanRangeMeters"),
                "mean_intensity": metrics.get("meanIntensity"),
                "low_support_rate": float(metrics.get("lowSupportRate", 0.0)),
            }

        def safe_stats(values, count):
            if values is None:
                return np.zeros((count,), dtype=np.float32)
            return values.astype(np.float32)

        def scene_feature_vector(pose_input, intrinsics, rgb, depth, visibility):
            if rgb is None:
                rgb_mean = np.zeros((3,), dtype=np.float32)
                rgb_std = np.zeros((3,), dtype=np.float32)
            else:
                rgb_mean = rgb.reshape(3, -1).mean(axis=1).astype(np.float32)
                rgb_std = rgb.reshape(3, -1).std(axis=1).astype(np.float32)
            if depth is None:
                depth_features = np.zeros((3,), dtype=np.float32)
            else:
                flat_depth = depth.reshape(-1).astype(np.float32)
                depth_features = np.array([
                    float(flat_depth.mean()),
                    float(flat_depth.std()),
                    float((flat_depth > 0.82).mean()),
                ], dtype=np.float32)
            if visibility is None:
                visibility_features = np.zeros((4,), dtype=np.float32)
            else:
                flat_visibility = visibility.reshape(-1).astype(np.float32)
                visibility_features = np.array([
                    float(flat_visibility.mean()),
                    float(flat_visibility.std()),
                    float((flat_visibility < 0.18).mean()),
                    float((flat_visibility > 0.65).mean()),
                ], dtype=np.float32)
            return np.concatenate([
                pose_input,
                intrinsics,
                rgb_mean,
                rgb_std,
                depth_features,
                visibility_features,
            ]).astype(np.float32)

        def load_samples(dataset_path):
            dataset_path = Path(dataset_path)
            dataset = json.loads(dataset_path.read_text())
            intrinsics = intrinsics_vector(dataset["cameraRig"]["intrinsics"])
            samples = []
            for frame in dataset["frames"]:
                rgb_path = product_url(frame, "rgb")
                depth_path = product_url(frame, "depth")
                visibility_path = product_url(frame, "visibility")
                lidar_path = product_url(frame, "lidarScan")
                failure_path = product_url(frame, "failureLabels")
                rgb = read_rgb_chw(rgb_path) if rgb_path else None
                depth = read_depth_chw(depth_path) if depth_path else None
                visibility = read_visibility_chw(visibility_path) if visibility_path else None
                lidar = lidar_summary(lidar_path)
                pose_input = pose_vector(frame)
                model_input = scene_feature_vector(pose_input, intrinsics, rgb, depth, visibility)
                target = failure_signal(failure_path)
                samples.append({
                    "frame_index": int(frame["index"]),
                    "rgb": rgb,
                    "depth": depth,
                    "visibility": visibility,
                    "lidar": lidar,
                    "scene_features": model_input,
                    "target": target,
                })
            return samples
        """
    }

    private func trainingScript() -> String {
        """
        #!/usr/bin/env python3
        import argparse
        import json
        from pathlib import Path

        import mlx.core as mx
        import mlx.nn as nn
        import mlx.optimizers as optim
        import numpy as np

        from robot_scene_dataset import load_samples

        class RobotSceneNet(nn.Module):
            def __init__(self):
                super().__init__()
                self.scene = nn.Sequential(
                    nn.Linear(24, 128),
                    nn.relu,
                    nn.Linear(128, 64),
                    nn.relu,
                    nn.Linear(64, 4),
                )

            def __call__(self, scene_features):
                return mx.sigmoid(self.scene(scene_features))

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--dataset", required=True)
            parser.add_argument("--output", required=True)
            parser.add_argument("--epochs", type=int, default=3)
            args = parser.parse_args()

            samples = [
                (mx.array(sample["scene_features"][None, :]), mx.array(sample["target"][None, :]))
                for sample in load_samples(args.dataset)
            ]

            model = RobotSceneNet()
            optimizer = optim.Adam(learning_rate=1e-3)

            def loss_fn(model, x, y):
                return mx.mean((model(x) - y) ** 2)

            loss_and_grad = nn.value_and_grad(model, loss_fn)
            for epoch in range(args.epochs):
                losses = []
                for x, y in samples:
                    loss, grads = loss_and_grad(model, x, y)
                    optimizer.update(model, grads)
                    mx.eval(model.parameters(), optimizer.state)
                    losses.append(float(loss))
                print(f"epoch={epoch} loss={sum(losses) / max(len(losses), 1):.6f}")

            output = Path(args.output)
            output.mkdir(parents=True, exist_ok=True)
            model.save_weights(str(output / "robot_scene_net.safetensors"))
            (output / "model_config.json").write_text(json.dumps({
                "model": "RobotSceneNet",
                "inputs": ["scene_features"],
                "outputs": ["free_space_probability", "obstacle_probability", "localization_uncertainty", "failure_kind_score"],
                "input_size": 24,
                "output_size": 4,
            }, indent=2))
            (output / "training_summary.json").write_text(json.dumps({"samples": len(samples), "epochs": args.epochs}, indent=2))

        if __name__ == "__main__":
            main()
        """
    }

    private func exportScript() -> String {
        """
        #!/usr/bin/env python3
        import argparse
        import json
        from pathlib import Path

        import coremltools as ct
        import mlx.core as mx
        import mlx.nn as nn
        import numpy as np
        from coremltools.converters.mil import Builder as mb

        class RobotSceneNet(nn.Module):
            def __init__(self):
                super().__init__()
                self.scene = nn.Sequential(
                    nn.Linear(24, 128),
                    nn.relu,
                    nn.Linear(128, 64),
                    nn.relu,
                    nn.Linear(64, 4),
                )

            def __call__(self, scene_features):
                return mx.sigmoid(self.scene(scene_features))

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--mlx-output", required=True)
            parser.add_argument("--coreml-output", required=True)
            args = parser.parse_args()
            mlx_output = Path(args.mlx_output)
            coreml_output = Path(args.coreml_output)
            coreml_output.parent.mkdir(parents=True, exist_ok=True)

            model = RobotSceneNet()
            model.load_weights(str(mlx_output / "robot_scene_net.safetensors"))
            example = mx.zeros((1, 24), dtype=mx.float32)
            mx.eval(model(example))

            params = dict(model.parameters())
            dense0_w = np.array(params["scene.layers.0.weight"])
            dense0_b = np.array(params["scene.layers.0.bias"])
            dense1_w = np.array(params["scene.layers.2.weight"])
            dense1_b = np.array(params["scene.layers.2.bias"])
            dense2_w = np.array(params["scene.layers.4.weight"])
            dense2_b = np.array(params["scene.layers.4.bias"])

            @mb.program(input_specs=[mb.TensorSpec(shape=(1, 24), dtype=mb.fp32)])
            def robot_scene_program(scene_features):
                x = mb.linear(x=scene_features, weight=dense0_w, bias=dense0_b)
                x = mb.relu(x=x)
                x = mb.linear(x=x, weight=dense1_w, bias=dense1_b)
                x = mb.relu(x=x)
                x = mb.linear(x=x, weight=dense2_w, bias=dense2_b)
                return mb.sigmoid(x=x, name="robot_scene_outputs")

            try:
                mlmodel = ct.convert(
                    robot_scene_program,
                    source="milinternal",
                    convert_to="mlprogram",
                    inputs=[ct.TensorType(name="scene_features", shape=(1, 24), dtype=np.float32)],
                    outputs=[ct.TensorType(name="robot_scene_outputs", dtype=np.float32)],
                    minimum_deployment_target=ct.target.macOS13,
                    compute_units=ct.ComputeUnit.ALL,
                )
                mlmodel.short_description = "Robot Scene Studio route evaluation model exported from Apple MLX training."
                mlmodel.input_description["scene_features"] = "Camera pose, intrinsics, and compact rendered RGB/depth/visibility statistics."
                mlmodel.output_description["robot_scene_outputs"] = "free_space, obstacle, localization_uncertainty, failure_kind_score."
                mlmodel.save(str(coreml_output))
                print(f"Wrote Core ML model package to {coreml_output}")
            except Exception as error:
                diagnostics = {
                    "source_weights": str((mlx_output / "robot_scene_net.safetensors").resolve()),
                    "target": str(coreml_output.resolve()),
                    "runtime": "Core ML",
                    "input": {"name": "scene_features", "shape": [1, 24], "dtype": "float32"},
                    "outputs": ["robot_scene_outputs"],
                    "coremltools_version": getattr(ct, "__version__", "unknown"),
                    "error": str(error),
                }
                diagnostic_url = coreml_output.with_suffix(".conversion_error.json")
                diagnostic_url.write_text(json.dumps(diagnostics, indent=2))
                raise RuntimeError(f"Core ML export failed; diagnostics written to {diagnostic_url}") from error

        if __name__ == "__main__":
            main()
        """
    }
}
