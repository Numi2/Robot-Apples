import Foundation
import simd

public struct SplatTrainingPackageManifest: Codable, Equatable, Sendable {
    public var id: String
    public var sourceManifestURL: URL
    public var frameIndexURL: URL
    public var trainScriptURL: URL
    public var outputURL: URL
    public var frameCount: Int
    public var trainingFrameCount: Int
    public var validationFrameCount: Int
    public var calibratedFrameCount: Int
    public var notes: [String]

    public init(
        id: String,
        sourceManifestURL: URL,
        frameIndexURL: URL,
        trainScriptURL: URL,
        outputURL: URL,
        frameCount: Int,
        trainingFrameCount: Int,
        validationFrameCount: Int,
        calibratedFrameCount: Int,
        notes: [String]
    ) {
        self.id = id
        self.sourceManifestURL = sourceManifestURL
        self.frameIndexURL = frameIndexURL
        self.trainScriptURL = trainScriptURL
        self.outputURL = outputURL
        self.frameCount = frameCount
        self.trainingFrameCount = trainingFrameCount
        self.validationFrameCount = validationFrameCount
        self.calibratedFrameCount = calibratedFrameCount
        self.notes = notes
    }
}

public struct SplatTrainingPackageBuilder: Sendable {
    public init() {}

    public func writePackage(
        job: SplatTrainingJob,
        manifestURL: URL,
        outputDirectory: URL
    ) throws -> SplatTrainingPackageManifest {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let frameIndexURL = outputDirectory.appendingPathComponent("capture_splat_frames.jsonl")
        let trainScriptURL = outputDirectory.appendingPathComponent("train_capture_splat_mlx.py")
        let packageURL = outputDirectory.appendingPathComponent("splat_training_package.json")

        try writeFrameIndex(job.manifest, to: frameIndexURL)
        try trainingScript().write(to: trainScriptURL, atomically: true, encoding: .utf8)
        let split = SplatTrainingFrameSplit(frameCount: job.manifest.imageFrames.count)
        let calibratedFrameCount = job.manifest.imageFrames.filter { $0.calibration?.intrinsics != nil }.count

        let package = SplatTrainingPackageManifest(
            id: "\(job.manifest.id)-apple-splat-training-package",
            sourceManifestURL: manifestURL,
            frameIndexURL: frameIndexURL,
            trainScriptURL: trainScriptURL,
            outputURL: job.manifest.expectedOutput.targetURL,
            frameCount: job.manifest.imageFrames.count,
            trainingFrameCount: split.trainingCount,
            validationFrameCount: split.validationCount,
            calibratedFrameCount: calibratedFrameCount,
            notes: [
                "Uses Apple MLX on Apple Silicon for local differentiable Gaussian parameter optimization.",
                "Consumes captured RGB frame URLs, camera intrinsics, tracking quality, and ARKit/RoomPlan-aligned camera poses.",
                "Seeds Gaussians along quaternion-rotated camera rays and optimizes against per-splat RGB/ray supervision from captured views.",
                "Exports a Gaussian PLY asset for the native Metal renderer and .robotscene packaging."
            ]
        )
        try JSONEncoder.robotVisionLabEncoder.encode(package).write(to: packageURL)
        return package
    }

    private func writeFrameIndex(_ manifest: SplatTrainingManifest, to outputURL: URL) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let split = SplatTrainingFrameSplit(frameCount: manifest.imageFrames.count)
        let lines = try manifest.imageFrames.enumerated().map { index, frame in
            let record = SplatTrainingFrameRecord(
                index: index,
                split: split.role(for: index),
                imageURL: frame.imageURL,
                timestamp: frame.timestamp,
                position: frame.pose.position,
                orientation: frame.pose.orientation.vector,
                intrinsics: frame.calibration?.intrinsics,
                resolution: frame.calibration?.resolution,
                trackingQuality: frame.calibration?.trackingQuality ?? .normal
            )
            return String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func trainingScript() -> String {
        """
        #!/usr/bin/env python3
        import argparse
        import json
        from pathlib import Path

        import mlx.core as mx
        import numpy as np

        try:
            from PIL import Image
        except Exception:
            Image = None

        def load_jsonl(path):
            return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]

        def average_rgb(path):
            if Image is None:
                return np.array([0.75, 0.78, 0.82], dtype=np.float32)
            image_path = Path(path.replace("file://", ""))
            if not image_path.exists():
                return np.array([0.75, 0.78, 0.82], dtype=np.float32)
            image = Image.open(image_path).convert("RGB").resize((32, 32))
            return np.asarray(image, dtype=np.float32).reshape(-1, 3).mean(axis=0) / 255.0

        def load_rgb_image(path):
            if Image is None:
                return None
            image_path = Path(path.replace("file://", ""))
            if not image_path.exists():
                return None
            return np.asarray(Image.open(image_path).convert("RGB"), dtype=np.float32) / 255.0

        def sample_rgb(frame, u, v):
            image = load_rgb_image(frame["imageURL"])
            if image is None:
                return average_rgb(frame["imageURL"])
            height, width = image.shape[:2]
            x = int(np.clip(round(u / max(frame_intrinsics(frame)[0], 1) * width), 0, width - 1))
            y = int(np.clip(round(v / max(frame_intrinsics(frame)[1], 1) * height), 0, height - 1))
            return image[y, x]

        def vector3(value):
            if isinstance(value, dict):
                return np.array([value["x"], value["y"], value["z"]], dtype=np.float32)
            return np.array(value[:3], dtype=np.float32)

        def quaternion(value):
            if isinstance(value, dict):
                return np.array([value["x"], value["y"], value["z"], value["w"]], dtype=np.float32)
            return np.array(value[:4], dtype=np.float32)

        def rotate_vector(q, v):
            q_xyz = q[:3]
            q_w = q[3]
            t = 2.0 * np.cross(q_xyz, v)
            return v + q_w * t + np.cross(q_xyz, t)

        def frame_intrinsics(frame):
            intrinsics = frame.get("intrinsics") or {}
            resolution = frame.get("resolution") or {}
            width = int(intrinsics.get("width") or resolution.get("width") or 1920)
            height = int(intrinsics.get("height") or resolution.get("height") or 1080)
            focal = intrinsics.get("focalLengthPixels") or [float(width), float(width)]
            principal = intrinsics.get("principalPointPixels") or [float(width) / 2.0, float(height) / 2.0]
            return width, height, vector2(focal), vector2(principal)

        def vector2(value):
            if isinstance(value, dict):
                return np.array([value["x"], value["y"]], dtype=np.float32)
            return np.array(value[:2], dtype=np.float32)

        def camera_ray(frame, offset, splats_per_frame):
            width, height, focal, principal = frame_intrinsics(frame)
            columns = max(int(np.ceil(np.sqrt(splats_per_frame))), 1)
            row = offset // columns
            column = offset % columns
            u = (column + 0.5) / float(columns) * width
            v = (row + 0.5) / float(columns) * height
            camera_direction = np.array(
                [
                    (u - principal[0]) / max(focal[0], 1.0),
                    -(v - principal[1]) / max(focal[1], 1.0),
                    -1.0,
                ],
                dtype=np.float32,
            )
            camera_direction /= max(np.linalg.norm(camera_direction), 1e-6)
            return rotate_vector(quaternion(frame["orientation"]), camera_direction), u, v

        def seed_gaussians(frames, splats_per_frame):
            positions = []
            colors = []
            source_origins = []
            source_rays = []
            target_colors = []
            for frame in frames:
                if frame.get("split") != "train":
                    continue
                if frame.get("trackingQuality") == "notAvailable":
                    continue
                origin = vector3(frame["position"])
                color = average_rgb(frame["imageURL"])
                for offset in range(splats_per_frame):
                    t = (offset + 1) / float(splats_per_frame + 1)
                    ray, u, v = camera_ray(frame, offset, splats_per_frame)
                    positions.append(origin + ray * (0.4 + t * 2.0))
                    sampled_color = sample_rgb(frame, u, v)
                    colors.append(0.5 * color + 0.5 * sampled_color)
                    source_origins.append(origin)
                    source_rays.append(ray)
                    target_colors.append(sampled_color)
            return (
                np.asarray(positions, dtype=np.float32),
                np.asarray(colors, dtype=np.float32),
                np.asarray(source_origins, dtype=np.float32),
                np.asarray(source_rays, dtype=np.float32),
                np.asarray(target_colors, dtype=np.float32),
            )

        def write_ply(path, positions, colors, opacity, scale):
            path = Path(path)
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("w") as f:
                f.write("ply\\n")
                f.write("format ascii 1.0\\n")
                f.write("comment Robot Scene Studio Apple MLX splat training output\\n")
                f.write(f"element vertex {len(positions)}\\n")
                f.write("property float x\\nproperty float y\\nproperty float z\\n")
                f.write("property uchar red\\nproperty uchar green\\nproperty uchar blue\\n")
                f.write("property float opacity\\n")
                f.write("property float scale_0\\nproperty float scale_1\\nproperty float scale_2\\n")
                f.write("property float rot_0\\nproperty float rot_1\\nproperty float rot_2\\nproperty float rot_3\\n")
                f.write("end_header\\n")
                for p, c, o, s in zip(positions, colors, opacity, scale):
                    rgb = np.clip(np.round(c * 255.0), 0, 255).astype(np.uint8)
                    f.write(
                        f"{p[0]:.6f} {p[1]:.6f} {p[2]:.6f} "
                        f"{int(rgb[0])} {int(rgb[1])} {int(rgb[2])} "
                        f"{float(o):.4f} {float(s[0]):.5f} {float(s[1]):.5f} {float(s[2]):.5f} "
                        "0.000000 0.000000 0.000000 1.000000\\n"
                    )

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--frames", required=True)
            parser.add_argument("--output", required=True)
            parser.add_argument("--splats-per-frame", type=int, default=24)
            parser.add_argument("--epochs", type=int, default=25)
            args = parser.parse_args()

            frames = load_jsonl(args.frames)
            if not frames:
                raise ValueError("No training frames were provided.")
            seed_positions, seed_colors, source_origins, source_rays, target_colors = seed_gaussians(
                frames,
                max(args.splats_per_frame, 1),
            )
            if len(seed_positions) == 0:
                raise ValueError("No trainable frames were available after split and tracking-quality filtering.")
            positions = mx.array(seed_positions)
            colors = mx.array(seed_colors)
            camera_origins = mx.array(source_origins)
            camera_rays = mx.array(source_rays)
            observed_colors = mx.array(target_colors)
            opacity_logits = mx.zeros((seed_positions.shape[0],), dtype=mx.float32)
            log_scale = mx.full((seed_positions.shape[0], 3), -3.0, dtype=mx.float32)
            learning_rate = 1e-3

            def loss_fn(position_values, color_values, opacity_values, scale_values):
                centroid = mx.mean(position_values, axis=0, keepdims=True)
                origin_to_splat = position_values - camera_origins
                projected_distance = mx.sum(origin_to_splat * camera_rays, axis=1, keepdims=True)
                closest_on_ray = camera_origins + camera_rays * projected_distance
                ray_alignment = mx.mean((position_values - closest_on_ray) ** 2)
                forward_depth = mx.mean(mx.maximum(0.05 - projected_distance, 0.0) ** 2)
                photometric = mx.mean((mx.clip(color_values, 0.0, 1.0) - observed_colors) ** 2)
                spatial_reg = mx.mean((position_values - centroid) ** 2) * 0.0005
                color_reg = mx.mean((color_values - mx.clip(color_values, 0.0, 1.0)) ** 2)
                opacity_reg = mx.mean((mx.sigmoid(opacity_values) - 0.75) ** 2) * 0.01
                scale_reg = mx.mean((mx.exp(scale_values) - 0.05) ** 2) * 0.01
                return photometric + ray_alignment * 0.05 + forward_depth * 0.05 + spatial_reg + color_reg + opacity_reg + scale_reg

            grad_fn = mx.grad(loss_fn, argnums=[0, 1, 2, 3])
            for epoch in range(args.epochs):
                grads = grad_fn(positions, colors, opacity_logits, log_scale)
                positions = positions - learning_rate * grads[0]
                colors = colors - learning_rate * grads[1]
                opacity_logits = opacity_logits - learning_rate * grads[2]
                log_scale = log_scale - learning_rate * grads[3]
                mx.eval(positions, colors, opacity_logits, log_scale)
                if epoch % max(args.epochs // 5, 1) == 0:
                    print(f"epoch={epoch} loss={float(loss_fn(positions, colors, opacity_logits, log_scale)):.6f}")

            write_ply(
                args.output,
                np.array(positions),
                np.clip(np.array(colors), 0.0, 1.0),
                np.array(mx.sigmoid(opacity_logits)),
                np.array(mx.exp(log_scale)),
            )
            summary = {
                "frames": len(frames),
                "train_frames": len([frame for frame in frames if frame.get("split") == "train"]),
                "validation_frames": len([frame for frame in frames if frame.get("split") == "validation"]),
                "calibrated_frames": len([frame for frame in frames if frame.get("intrinsics") is not None]),
                "splats": int(seed_positions.shape[0]),
                "output": str(Path(args.output).resolve()),
                "runtime": "Apple MLX",
                "loss_terms": ["photometric_rgb", "camera_ray_alignment", "positive_depth", "scale_opacity_regularization"],
            }
            Path(args.output).with_suffix(".training_summary.json").write_text(json.dumps(summary, indent=2))
            print(json.dumps(summary, indent=2))

        if __name__ == "__main__":
            main()
        """
    }
}

private struct SplatTrainingFrameRecord: Codable {
    var index: Int
    var split: SplatTrainingFrameSplit.Role
    var imageURL: URL
    var timestamp: TimeInterval
    var position: SIMD3<Double>
    var orientation: SIMD4<Double>
    var intrinsics: CameraIntrinsics?
    var resolution: Resolution?
    var trackingQuality: TrackingQuality
}

private struct SplatTrainingFrameSplit {
    enum Role: String, Codable {
        case train
        case validation
    }

    let frameCount: Int

    var trainingCount: Int {
        (0..<frameCount).filter { role(for: $0) == .train }.count
    }

    var validationCount: Int {
        (0..<frameCount).filter { role(for: $0) == .validation }.count
    }

    func role(for index: Int) -> Role {
        guard frameCount > 1 else { return .train }
        return (index + 1).isMultiple(of: 5) || index == frameCount - 1 ? .validation : .train
    }
}
