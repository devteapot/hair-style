import Foundation
import CoreGraphics
import CoreVideo
import Vision

public struct ImageFlowField: Sendable {
    public var width: Int
    public var height: Int
    /// Interleaved native-image pixel offsets dx,dy (x right, y down).
    public var offsets: [Float]

    public func sample(x: Double, y: Double) -> PixelPoint? {
        guard x.isFinite,y.isFinite,x>=0,y>=0,x<=Double(width-1),y<=Double(height-1),offsets.count==width*height*2 else { return nil }
        let x0=Int(x),y0=Int(y),x1=min(x0+1,width-1),y1=min(y0+1,height-1)
        let tx=x-Double(x0),ty=y-Double(y0)
        func component(_ c:Int) -> Double {
            let a=Double(offsets[(y0*width+x0)*2+c]),b=Double(offsets[(y0*width+x1)*2+c])
            let d=Double(offsets[(y1*width+x0)*2+c]),e=Double(offsets[(y1*width+x1)*2+c])
            return (a*(1-tx)+b*tx)*(1-ty)+(d*(1-tx)+e*tx)*ty
        }
        let dx=component(0),dy=component(1)
        guard dx.isFinite,dy.isFinite else { return nil }
        return PixelPoint(x:dx,y:dy)
    }
}

public enum ImageOpticalFlow {
    /// Model-estimated correspondence, not depth/registration acceptance. Images must share native orientation.
    public static func estimate(source: CGImage, target: CGImage) throws -> ImageFlowField {
        guard source.width==target.width,source.height==target.height,
              source.width>=64,source.height>=64,source.width*source.height<=4_000_000 else {
            throw CaptureError.invalid("Optical flow requires equal image dimensions, at least 64 pixels per side and at most 4 million pixels.")
        }
        return try autoreleasepool {
            let handler=VNImageRequestHandler(cgImage:source,orientation:.up,options:[:])
            let request=VNGenerateOpticalFlowRequest(targetedCGImage:target,options:[:])
            request.revision=VNGenerateOpticalFlowRequestRevision1
            request.computationAccuracy = .high
            request.outputPixelFormat=kCVPixelFormatType_TwoComponent32Float
            request.keepNetworkOutput=false
            try handler.perform([request])
            guard let buffer=request.results?.first?.pixelBuffer,
                  CVPixelBufferGetWidth(buffer)==source.width,CVPixelBufferGetHeight(buffer)==source.height,
                  CVPixelBufferGetPixelFormatType(buffer)==kCVPixelFormatType_TwoComponent32Float else {
                throw CaptureError.invalid("Optical flow returned unexpected dimensions or encoding.")
            }
            CVPixelBufferLockBaseAddress(buffer,.readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
            guard let base=CVPixelBufferGetBaseAddress(buffer) else { throw CaptureError.invalid("Optical flow buffer unavailable.") }
            var offsets:[Float]=[];offsets.reserveCapacity(source.width*source.height*2)
            for y in 0..<source.height {
                let row=base.advanced(by:y*CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to:Float.self)
                offsets.append(contentsOf:UnsafeBufferPointer(start:row,count:source.width*2))
            }
            return ImageFlowField(width:source.width,height:source.height,offsets:offsets)
        }
    }
}
