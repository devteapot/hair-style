import Foundation

/// Bidirectional native depth projection. Raw front-camera projection inverts
/// the same supplied inverse radial map used by point reconstruction; it does
/// not assume that a rectified pixel is already a native sensor pixel.
public struct CalibratedDepthCamera: Sendable {
    public let size: PixelSize
    private let intrinsics: Intrinsics
    private let lens: LensCalibration?
    private let maximumRadius: Double
    private let mappedRadii: [Double]

    public init(frame: FrameMetadata) throws {
        try CaptureBundle.validate(frame)
        try CalibratedLandmarks.requireSynchronizedDepth(frame)
        guard let size = frame.depthSize, let k = frame.intrinsics,
              !frame.mirrored, frame.pixelOrientation == "sensor_native" else {
            throw CaptureError.invalid("Native depth projection requires calibrated unmirrored pixels.")
        }
        self.size = size; intrinsics = k
        switch frame.depthRectification {
        case "arkit_aligned_scene_depth", "synthetic_pinhole":
            lens = nil; maximumRadius = 0; mappedRadii = []
        case "not_applied":
            guard let calibration = frame.lensCalibration,
                  let table = calibration.inverseLookupTable, (2...4096).contains(table.count) else {
                throw CaptureError.invalid("Raw depth needs a bounded inverse lens calibration.")
            }
            _ = try LensGeometry.undistort(PixelPoint(x: 0, y: 0), lens: calibration, referenceSize: k.referenceSize)
            let radius = hypot(max(calibration.centerX, Double(k.referenceSize.width)-calibration.centerX),
                               max(calibration.centerY, Double(k.referenceSize.height)-calibration.centerY))
            let step = radius / Double(table.count-1)
            // Check the derivative across every linearly interpolated table
            // interval. A folded radial map cannot be inverted unambiguously.
            for index in 0..<(table.count-1) {
                let r0 = Double(index)*step, r1 = r0+step
                let slope = (Double(table[index+1])-Double(table[index]))/step
                let intercept = 1+Double(table[index])-slope*r0
                guard intercept+2*slope*r0 > 1e-6, intercept+2*slope*r1 > 1e-6 else {
                    throw CaptureError.invalid("Lens radial map is not strictly invertible.")
                }
            }
            lens = calibration; maximumRadius = radius
            mappedRadii = table.enumerated().map { Double($0.offset)*step*(1+Double($0.element)) }
        default: throw CaptureError.invalid("Unsupported depth rectification convention.")
        }
    }

    public func point(pixel: PixelPoint, depth: Double) throws -> Point3D {
        guard pixel.x.isFinite, pixel.y.isFinite, depth.isFinite, (0.05...2).contains(depth),
              pixel.x >= 0, pixel.y >= 0, pixel.x < Double(size.width), pixel.y < Double(size.height) else {
            throw CaptureError.invalid("Invalid native depth pixel or metric depth.")
        }
        var p = PixelPoint(x: pixel.x*Double(intrinsics.referenceSize.width)/Double(size.width),
                           y: pixel.y*Double(intrinsics.referenceSize.height)/Double(size.height))
        if let lens { p = try LensGeometry.undistort(p, lens: lens, referenceSize: intrinsics.referenceSize) }
        return Point3D(x: (p.x-intrinsics.cx)*depth/intrinsics.fx, y: (p.y-intrinsics.cy)*depth/intrinsics.fy, z: depth)
    }

    /// Nil means behind the camera or outside its calibrated image domain.
    public func pixel(point: Point3D) -> PixelPoint? {
        guard point.finite, point.z > 0 else { return nil }
        var x = intrinsics.fx*point.x/point.z+intrinsics.cx
        var y = intrinsics.fy*point.y/point.z+intrinsics.cy
        guard x.isFinite, y.isFinite else { return nil }
        if let lens, let table = lens.inverseLookupTable {
            let dx = x-lens.centerX, dy = y-lens.centerY, target = hypot(dx, dy)
            guard target <= mappedRadii.last! else { return nil }
            if target > 1e-12 {
                var low = 0, high = mappedRadii.count-1
                while high-low > 1 {
                    let middle = (low+high)/2
                    if mappedRadii[middle] < target { low = middle } else { high = middle }
                }
                let step = maximumRadius/Double(table.count-1)
                let start = Double(low)*step
                var a = start, b = Double(high)*step
                let m0 = Double(table[low]), dm = Double(table[high])-m0
                for _ in 0..<32 {
                    let radius = (a+b)/2, mapped = radius*(1+m0+dm*(radius-start)/step)
                    if mapped < target { a = radius } else { b = radius }
                }
                let scale = (a+b)/(2*target)
                x = lens.centerX+dx*scale; y = lens.centerY+dy*scale
            }
        }
        x *= Double(size.width)/Double(intrinsics.referenceSize.width)
        y *= Double(size.height)/Double(intrinsics.referenceSize.height)
        // Numerical radial inversion can place an exact border pixel a tiny
        // distance outside. Clamp roundoff only, never an off-image projection.
        guard x >= -1e-7, y >= -1e-7, x < Double(size.width), y < Double(size.height) else { return nil }
        return PixelPoint(x: max(0,x), y: max(0,y))
    }
}
