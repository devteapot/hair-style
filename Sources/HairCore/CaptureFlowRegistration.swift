import Foundation
import ImageIO

public struct CaptureFlowRequest: Codable, Sendable {
    public var sourceFrameID: String
    public var targetFrameID: String
    public var sourceMask: SurfaceMask
    public var targetMask: SurfaceMask
    public var depthGridStride: Int = 2
    public var maximumRoundTripPixels: Double = 1.5
    public var minimumConfidence: UInt8 = 1
    public init(sourceFrameID:String,targetFrameID:String,sourceMask:SurfaceMask,targetMask:SurfaceMask) {
        self.sourceFrameID=sourceFrameID;self.targetFrameID=targetFrameID;self.sourceMask=sourceMask;self.targetMask=targetMask
    }
}

public struct CaptureFlowReport: Codable, Sendable {
    public var method = "vision_optical_flow_r1_depth_rigid_candidate_v1"
    public var requestSHA256: String
    public var sourceFrameSHA256: String
    public var targetFrameSHA256: String
    public var counts: [String:Int]
    public var selection: CaptureLandmarkSelection?
    public var registration: CapturedRegistrationReport?
    public var failureReason: String?
    public var acceptedForFullHead = false
    public var notes: [String]
}

public enum CaptureFlowRegistration {
    public static func estimate(bundle:URL,request:CaptureFlowRequest) throws -> CaptureFlowReport {
        guard request.sourceFrameID != request.targetFrameID,(1...8).contains(request.depthGridStride),
              (0.25...3).contains(request.maximumRoundTripPixels),request.minimumConfidence<=2 else { throw CaptureError.invalid("Invalid flow selection settings.") }
        guard try CaptureBundle.inspect(bundle).valid else { throw CaptureError.invalid("Flow matching requires intact capture payloads.") }
        let manifest=try CaptureBundle.load(bundle)
        guard manifest.status == .completed,[.rearHead,.frontFace].contains(manifest.kind),
              let source=manifest.frames.first(where: { $0.metadata.id==request.sourceFrameID }),
              let target=manifest.frames.first(where: { $0.metadata.id==request.targetFrameID }),
              source.metadata.imageSize==target.metadata.imageSize,
              source.metadata.depthSize==request.sourceMask.size,target.metadata.depthSize==request.targetMask.size else {
            throw CaptureError.invalid("Flow matching requires two compatible completed geometry frames and masks.")
        }
        for frame in [source,target] {
            try CalibratedLandmarks.requireSynchronizedDepth(frame.metadata)
            guard !frame.metadata.mirrored,frame.metadata.pixelOrientation=="sensor_native" else { throw CaptureError.invalid("Flow requires unmirrored native coordinates.") }
            if manifest.kind == .rearHead {
                guard frame.metadata.depthRectification=="arkit_aligned_scene_depth",frame.metadata.quality.trackingState=="normal",frame.confidence != nil else {
                    throw CaptureError.invalid("Rear flow requires normal tracking, aligned depth and confidence.")
                }
            } else {
                guard frame.metadata.depthRectification=="not_applied" else { throw CaptureError.invalid("Front flow requires original calibrated TrueDepth.") }
                _ = try CalibratedDepthCamera(frame:frame.metadata)
            }
        }
        if manifest.source != .syntheticFixture && [request.sourceMask,request.targetMask].contains(where: { $0.provenance == .syntheticFixture }) {
            throw CaptureError.invalid("Sensor frames cannot use synthetic masks.")
        }
        func image(_ frame:StoredFrame) throws -> CGImage {
            let bytes=try CaptureBundle.payload(frame.image,in:bundle)
            guard let decoder=CGImageSourceCreateWithData(bytes as CFData,nil),let image=CGImageSourceCreateImageAtIndex(decoder,0,nil),
                  image.width==frame.metadata.imageSize.width,image.height==frame.metadata.imageSize.height else { throw CaptureError.invalid("Invalid image payload dimensions.") }
            return image
        }
        let a=try image(source),b=try image(target)
        let forward=try ImageOpticalFlow.estimate(source:a,target:b)
        let backward=try ImageOpticalFlow.estimate(source:b,target:a)
        let sourceMask=try request.sourceMask.decode(),targetMask=try request.targetMask.decode()
        guard let sourceDepth=source.depth,let targetDepth=target.depth else { throw CaptureError.invalid("Missing native depth.") }
        let av=try DepthGeometry.decode(CaptureBundle.payload(sourceDepth,in:bundle),size:request.sourceMask.size)
        let bv=try DepthGeometry.decode(CaptureBundle.payload(targetDepth,in:bundle),size:request.targetMask.size)
        let ac=try source.confidence.map { try CaptureBundle.payload($0,in:bundle) }
        let bc=try target.confidence.map { try CaptureBundle.payload($0,in:bundle) }
        let size=request.sourceMask.size,ts=request.targetMask.size
        var counts:[String:Int]=[:],pairs:[PixelLandmarkPair]=[]
        for y in stride(from:0,to:size.height,by:request.depthGridStride) { for x in stride(from:0,to:size.width,by:request.depthGridStride) {
            counts["gridSamples",default:0]+=1
            guard sourceMask[y*size.width+x] else { counts["outsideSourceMask",default:0]+=1;continue }
            let p=PixelPoint(x:Double(x)*Double(a.width)/Double(size.width),y:Double(y)*Double(a.height)/Double(size.height))
            guard let f=forward.sample(x:p.x,y:p.y) else { counts["invalidForwardFlow",default:0]+=1;continue }
            let q=PixelPoint(x:p.x+f.x,y:p.y+f.y)
            guard q.x>=0,q.y>=0,q.x<Double(b.width),q.y<Double(b.height),let back=backward.sample(x:q.x,y:q.y) else { counts["outsideTargetImage",default:0]+=1;continue }
            guard hypot(f.x+back.x,f.y+back.y)<=request.maximumRoundTripPixels else { counts["roundTripRejected",default:0]+=1;continue }
            let tx=min(ts.width-1,Int((q.x*Double(ts.width)/Double(b.width)).rounded())),ty=min(ts.height-1,Int((q.y*Double(ts.height)/Double(b.height)).rounded()))
            guard targetMask[ty*ts.width+tx] else { counts["outsideTargetMask",default:0]+=1;continue }
            do {
                _=try CalibratedLandmarks.sample(p,frame:source.metadata,values:av,confidence:ac,minimumConfidence:request.minimumConfidence)
                _=try CalibratedLandmarks.sample(q,frame:target.metadata,values:bv,confidence:bc,minimumConfidence:request.minimumConfidence)
            } catch { counts["unusableDepth",default:0]+=1;continue }
            pairs.append(PixelLandmarkPair(id:"flow:\(x):\(y)",source:p,target:q))
        } }
        counts["consistentDepthMatches"]=pairs.count
        var result=CaptureFlowReport(requestSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(request)),
            sourceFrameSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(source)),
            targetFrameSHA256:EvidenceHash.sha256(try ManifestCoding.encoder().encode(target)),counts:counts,
            notes:["Vision optical-flow revision 1, high accuracy, unmirrored native RGB coordinates. No camera-pose initializer or inferred focal length.",
                   "Source grid, target mask, original confidence/depth and forward-backward image consistency constrain candidate correspondences.",
                   "Front RGB flow is evaluated in native distorted pixels; selected 3D rays use original inverse lens calibration. Missing front confidence is not replaced with an invented score.",
                   "Up to 400 spatially distributed matches are split alternately for rigid fitting and validation; nearby samples remain correlated.",
                   "A local registration gate does not establish independent physical accuracy, loop closure or complete head registration.",
                   "Hair and other material inside the spatial masks remain. Image consistency is not a semantic or rigid-body guarantee."])
        guard pairs.count>=14 else { result.failureReason="Insufficient consistent RGB/depth matches.";return result }
        let count=min(400,pairs.count)
        let chosen=(0..<count).map { pairs[Int((Double($0)*Double(pairs.count-1)/Double(count-1)).rounded())] }
        let selection=CaptureLandmarkSelection(sourceFrameID:request.sourceFrameID,targetFrameID:request.targetFrameID,
            fitPairs:chosen.enumerated().filter { $0.offset%2==0 }.map(\.element),validationPairs:chosen.enumerated().filter { $0.offset%2==1 }.map(\.element))
        result.selection=selection
        do { result.registration=try CalibratedLandmarks.register(sourceBundle:bundle,targetBundle:bundle,selection:selection,minimumConfidence:request.minimumConfidence) }
        catch { result.failureReason=error.localizedDescription }
        return result
    }
}
