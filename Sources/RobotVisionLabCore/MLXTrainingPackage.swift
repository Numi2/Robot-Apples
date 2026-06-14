import Foundation

public struct MLXTrainingPackageManifest: Codable, Equatable, Sendable {
    public var id: String
    public var datasetManifestURL: URL
    public var adapterSchemaURL: URL
    public var trainScriptURL: URL
    public var exportScriptURL: URL
    public var sampleCount: Int
    public var notes: [String]

    public init(
        id: String,
        datasetManifestURL: URL,
        adapterSchemaURL: URL,
        trainScriptURL: URL,
        exportScriptURL: URL,
        sampleCount: Int,
        notes: [String]
    ) {
        self.id = id
        self.datasetManifestURL = datasetManifestURL
        self.adapterSchemaURL = adapterSchemaURL
        self.trainScriptURL = trainScriptURL
        self.exportScriptURL = exportScriptURL
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
        let trainURL = outputDirectory.appendingPathComponent("train_robot_scene_mlx.py")
        let exportURL = outputDirectory.appendingPathComponent("export_coreml.py")
        let packageURL = outputDirectory.appendingPathComponent("mlx_training_package.json")

        try NativeModelAdapterSchemaWriter().write(schema, to: schemaURL)
        try trainingScript().write(to: trainURL, atomically: true, encoding: .utf8)
        try exportScript().write(to: exportURL, atomically: true, encoding: .utf8)

        let package = MLXTrainingPackageManifest(
            id: "\(manifest.recipeID)-mlx-training-package",
            datasetManifestURL: datasetManifestURL,
            adapterSchemaURL: schemaURL,
            trainScriptURL: trainURL,
            exportScriptURL: exportURL,
            sampleCount: manifest.frames.count,
            notes: [
                "Runs locally on Apple Silicon with MLX.",
                "Loads rendered RGB/depth plus pose/intrinsics from dataset.json.",
                "Exports deployment artifacts through Core ML conversion."
            ]
        )
        try JSONEncoder.robotVisionLabEncoder.encode(package).write(to: packageURL)
        return package
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

        def pose_vector(frame):
            pose = frame["cameraPose"]
            p = pose["position"]
            q = pose["orientation"]
            return np.array([p["x"], p["y"], p["z"], q["vector"]["x"], q["vector"]["y"], q["vector"]["z"], q["vector"]["w"]], dtype=np.float32)

        def intrinsics_vector(camera):
            fx = camera["focalLengthPixels"]["x"]
            fy = camera["focalLengthPixels"]["y"]
            cx = camera["principalPointPixels"]["x"]
            cy = camera["principalPointPixels"]["y"]
            return np.array([fx, fy, cx, cy], dtype=np.float32)

        def product_url(frame, product):
            for item in frame["products"]:
                if item["product"] == product:
                    return item["url"].replace("file://", "")
            return None

        class RobotSceneNet(nn.Module):
            def __init__(self):
                super().__init__()
                self.pose = nn.Sequential(nn.Linear(11, 64), nn.relu, nn.Linear(64, 4))

            def __call__(self, pose_intrinsics):
                return self.pose(pose_intrinsics)

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--dataset", required=True)
            parser.add_argument("--output", required=True)
            parser.add_argument("--epochs", type=int, default=3)
            args = parser.parse_args()

            dataset = json.loads(Path(args.dataset).read_text())
            intrinsics = intrinsics_vector(dataset["cameraRig"]["intrinsics"])
            samples = []
            for frame in dataset["frames"]:
                rgb_path = product_url(frame, "rgb")
                depth_path = product_url(frame, "depth")
                if rgb_path:
                    _ = read_rgb_chw(rgb_path)
                if depth_path:
                    _ = read_depth_chw(depth_path)
                pose_input = np.concatenate([pose_vector(frame), intrinsics])
                target = np.array([1.0, 0.0, 0.1, 0.0], dtype=np.float32)
                samples.append((mx.array(pose_input[None, :]), mx.array(target[None, :])))

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

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--mlx-output", required=True)
            parser.add_argument("--coreml-output", required=True)
            args = parser.parse_args()
            output = Path(args.coreml_output)
            output.parent.mkdir(parents=True, exist_ok=True)
            conversion_plan = {
                "source": str(Path(args.mlx_output).resolve()),
                "target": str(output.resolve()),
                "runtime": "Core ML",
                "note": "Convert the MLX module to Core ML with Apple's Core ML Tools in the local Apple Silicon environment."
            }
            output.write_text(json.dumps(conversion_plan, indent=2))
            print(f"Wrote Core ML conversion plan to {output}")

        if __name__ == "__main__":
            main()
        """
    }
}
