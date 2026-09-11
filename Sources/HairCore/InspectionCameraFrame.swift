import Foundation

/// Frames rendered geometry in a fixed three-quarter orthographic inspection view.
/// It changes only the inspection camera, never canonical or live-tracking coordinates.
public struct InspectionCameraFrame: Sendable {
    public let target: Point3D
    public let towardCamera: Point3D
    public let halfWidth: Double
    public let halfHeight: Double
    public let halfDepth: Double

    public init(points: [Point3D]) throws {
        guard !points.isEmpty, points.allSatisfy({ $0.finite }) else {
            throw CaptureError.invalid("Inspection framing needs finite geometry.")
        }
        let back = Point3D(x: 0.6, y: 0.3, z: 1).unit
        let right = Point3D(x: 0, y: 1, z: 0).cross(back).unit
        let up = back.cross(right).unit
        var low = [Double](repeating: .infinity, count: 3)
        var high = [Double](repeating: -.infinity, count: 3)
        for point in points {
            let coordinates = [point.dot(right), point.dot(up), point.dot(back)]
            for i in 0..<3 { low[i] = min(low[i], coordinates[i]); high[i] = max(high[i], coordinates[i]) }
        }
        target = right * ((low[0]+high[0])/2) + up * ((low[1]+high[1])/2) + back * ((low[2]+high[2])/2)
        towardCamera = back
        halfWidth = (high[0]-low[0])/2; halfHeight = (high[1]-low[1])/2; halfDepth = (high[2]-low[2])/2
    }

    /// SCN's vertical orthographic scale is a half-height. Leave a 15% margin.
    public func scale(viewportWidth: Double, viewportHeight: Double) throws -> Double {
        guard viewportWidth.isFinite, viewportHeight.isFinite, viewportWidth > 0, viewportHeight > 0 else {
            throw CaptureError.invalid("Inspection viewport must have positive finite dimensions.")
        }
        return max(0.001, max(halfHeight, halfWidth / (viewportWidth/viewportHeight)) / 0.85)
    }
}
