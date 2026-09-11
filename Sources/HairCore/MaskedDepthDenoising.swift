import Foundation

/// Optional reconstruction preprocessing. Original capture payloads are never changed.
public struct DepthDenoisingSettings: Codable, Sendable {
    public var radiusPixels = 2
    public var spatialSigmaPixels = 1.5
    public var rangeSigmaMeters = 0.002
    public var maximumNeighborDifferenceMeters = 0.004
    public var maximumAdjustmentMeters = 0.001
    public var minimumNeighbors = 5
    public init() {}
}

enum MaskedDepthDenoising {
    struct Result {
        var values: [Float]
        var counts: [String: Int]
        var maximumAdjustmentMeters: Double
    }

    static func apply(_ depth: [Float], usable: [Bool], size: PixelSize, settings s: DepthDenoisingSettings) throws -> Result {
        guard size.isValid, depth.count == size.width*size.height, usable.count == depth.count,
              (1...3).contains(s.radiusPixels), (0.5...3).contains(s.spatialSigmaPixels),
              (0.0005...0.004).contains(s.rangeSigmaMeters),
              (0.001...0.008).contains(s.maximumNeighborDifferenceMeters),
              (0.0001...0.002).contains(s.maximumAdjustmentMeters),
              s.maximumAdjustmentMeters <= s.maximumNeighborDifferenceMeters,
              (3...(2*s.radiusPixels+1)*(2*s.radiusPixels+1)).contains(s.minimumNeighbors),
              zip(depth,usable).allSatisfy({ !$0.1 || ($0.0.isFinite && (0.05...2).contains($0.0)) }) else {
            throw CaptureError.invalid("Invalid masked depth denoising settings or samples.")
        }
        var output = depth
        var counts = ["denoisingAdjustedPixels":0,"denoisingInsufficientNeighbors":0,"denoisingClampedPixels":0,
                      "denoisingRejectedNeighborSamples":0]
        var maximum = 0.0
        var offsets: [(Int,Int,Double)] = []
        for dy in -s.radiusPixels...s.radiusPixels { for dx in -s.radiusPixels...s.radiusPixels {
            offsets.append((dx,dy,exp(-Double(dx*dx+dy*dy)/(2*s.spatialSigmaPixels*s.spatialSigmaPixels))))
        } }
        for y in 0..<size.height { for x in 0..<size.width {
            let index = y*size.width+x
            guard usable[index] else { continue }
            let center = Double(depth[index])
            var sum = 0.0, weight = 0.0, neighbors = 0
            for (dx,dy,spatial) in offsets {
                let xx=x+dx, yy=y+dy
                guard xx>=0, yy>=0, xx<size.width, yy<size.height else { continue }
                let j=yy*size.width+xx
                guard usable[j] else { continue }
                let delta=Double(depth[j])-center
                guard abs(delta)<=s.maximumNeighborDifferenceMeters else {
                    counts["denoisingRejectedNeighborSamples",default:0] += 1; continue
                }
                let w=spatial*exp(-delta*delta/(2*s.rangeSigmaMeters*s.rangeSigmaMeters))
                sum += w*Double(depth[j]); weight += w; neighbors += 1
            }
            guard neighbors>=s.minimumNeighbors else { counts["denoisingInsufficientNeighbors",default:0] += 1; continue }
            let proposed=sum/weight-center
            if abs(proposed)>s.maximumAdjustmentMeters { counts["denoisingClampedPixels",default:0] += 1 }
            let delta=max(-s.maximumAdjustmentMeters,min(s.maximumAdjustmentMeters,proposed))
            // A rounded Float must also stay inside the declared adjustment bound.
            var value=Float(center+delta)
            if Double(value)-center>s.maximumAdjustmentMeters { value=value.nextDown }
            if center-Double(value)>s.maximumAdjustmentMeters { value=value.nextUp }
            output[index]=value
            let adjustment=abs(Double(value)-center)
            if adjustment>0 { counts["denoisingAdjustedPixels",default:0] += 1 }
            maximum=max(maximum,adjustment)
        } }
        return Result(values:output,counts:counts,maximumAdjustmentMeters:maximum)
    }
}
