import Foundation

public enum DepthGeometry {
    public static func encode(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func decode(_ data: Data, size: PixelSize) throws -> [Float] {
        guard size.isValid, data.count == size.width * size.height * 4 else {
            throw CaptureError.invalid("Depth payload does not match dimensions or float32 encoding.")
        }
        return data.withUnsafeBytes { bytes in
            (0..<(size.width * size.height)).map {
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
            }
        }
    }

    public static func quality(_ values: [Float]) -> (fraction: Double, median: Double?) {
        guard !values.isEmpty else { return (0, nil) }
        let valid = values.filter { $0.isFinite && $0 > 0 }.sorted()
        let median: Double? = valid.isEmpty ? nil : Double(valid[valid.count / 2])
        return (Double(valid.count) / Double(values.count), median)
    }

    /// Pinhole back-projection in the optical frame. Does not imply head registration.
    /// Source lens distortion must be handled before precision measurement.
    public static func pointCloud(values: [Float], size: PixelSize, intrinsics: Intrinsics,
                                  stride: Int = 1, range: ClosedRange<Double> = 0.05...2,
                                  worldFromCamera: RigidTransform? = nil) throws -> [Point3D] {
        guard size.isValid, values.count == size.width * size.height, intrinsics.isValid, stride > 0,
              range.lowerBound.isFinite, range.upperBound.isFinite else {
            throw CaptureError.invalid("Invalid projection inputs.")
        }
        if let transform = worldFromCamera, !transform.isValid {
            throw CaptureError.invalid("Camera transform must be a finite right-handed rigid transform.")
        }
        let k = intrinsics.scaled(to: size)
        var result: [Point3D] = []
        for y in Swift.stride(from: 0, to: size.height, by: stride) {
            for x in Swift.stride(from: 0, to: size.width, by: stride) {
                let z = Double(values[y * size.width + x])
                guard z.isFinite, range.contains(z) else { continue }
                let p = Point3D(x: (Double(x) - k.cx) * z / k.fx,
                                y: (Double(y) - k.cy) * z / k.fy, z: z)
                result.append(worldFromCamera?.apply(p) ?? p)
            }
        }
        return result
    }

    public static func ply(_ points: [Point3D]) -> Data {
        let header = "ply\nformat ascii 1.0\ncomment camera-space inspection; not a reconstructed head\nelement vertex \(points.count)\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        let rows = points.map { "\($0.x) \($0.y) \($0.z)" }.joined(separator: "\n")
        return Data((header + rows + "\n").utf8)
    }
}
