import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import HairCore

final class ImageOpticalFlowTests: XCTestCase {
    private func image(dx:Int=0,dy:Int=0) -> CGImage {
        let width=256,height=192
        var bytes=[UInt8](repeating:0,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let xx=x-dx,yy=y-dy
            let value=UInt8(clamping:((xx/4*37+yy/4*61+(xx/4)*(yy/4)*13)%193+193)%193+30)
            let i=(y*width+x)*4
            bytes[i]=value;bytes[i+1]=value;bytes[i+2]=value;bytes[i+3]=255
        } }
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
            provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
    }
    func testKnownImageTranslationEstablishesDirectionUnitsAndRoundTrip() throws {
        let a=image(),b=image(dx:8,dy:5)
        let forward=try ImageOpticalFlow.estimate(source:a,target:b)
        let backward=try ImageOpticalFlow.estimate(source:b,target:a)
        var xs:[Double]=[],ys:[Double]=[],errors:[Double]=[]
        for y in stride(from:48,to:144,by:16) { for x in stride(from:48,to:208,by:16) {
            let flow=try XCTUnwrap(forward.sample(x:Double(x),y:Double(y)))
            let reverse=try XCTUnwrap(backward.sample(x:Double(x)+flow.x,y:Double(y)+flow.y))
            xs.append(flow.x);ys.append(flow.y);errors.append(hypot(flow.x+reverse.x,flow.y+reverse.y))
        } }
        XCTAssertEqual(xs.sorted()[xs.count/2],8,accuracy:0.8)
        XCTAssertEqual(ys.sorted()[ys.count/2],5,accuracy:0.8)
        XCTAssertLessThan(errors.sorted()[errors.count/2],1)
    }
    func testCaptureFlowRecoversMetricTranslationFromEncodedRGBAndDepth() throws {
        try checkCaptureFlow(front:false)
    }
    func testFrontFlowUsesLensCorrectedDepthWithoutInventedConfidence() throws {
        try checkCaptureFlow(front:true)
    }
    func testFrontFlowRejectsMissingLensCalibration() throws {
        try checkCaptureFlow(front:true,missingCalibration:true)
    }
    private func checkCaptureFlow(front: Bool, missingCalibration: Bool = false) throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let device=DeviceReport(model:"synthetic-flow",osVersion:"fixture",build:"1",
            hasTrueDepth:false,hasRearSceneDepth:false,hasFaceTracking:false,isSimulator:true)
        let writer=try CaptureBundleWriter(root:root,subjectSessionID:"flow-fixture",kind:front ? .frontFace : .rearHead,
            source:.syntheticFixture,device:device,consentVersion:"synthetic-no-subject")
        let size=PixelSize(64,48),rgbSize=PixelSize(256,192)
        let intrinsics=Intrinsics(fx:200,fy:200,cx:128,cy:96,referenceSize:rgbSize)
        for i in 0..<2 {
            let data=NSMutableData()
            let destination=try XCTUnwrap(CGImageDestinationCreateWithData(data,UTType.jpeg.identifier as CFString,1,nil))
            CGImageDestinationAddImage(destination,image(dx:i*8,dy:i*5),
                [kCGImageDestinationLossyCompressionQuality:1] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            var metadata=FrameMetadata(imageTimestamp:Double(i+1),depthTimestamp:Double(i+1),
                imageSize:rgbSize,depthSize:size,intrinsics:intrinsics,depthFiltered:false,
                depthRectification:"arkit_aligned_scene_depth",
                quality:FrameQuality(validDepthFraction:1,medianDepthMeters:0.5,
                    synchronizationDeltaSeconds:0,trackingState:"normal"))
            if front {
                metadata.depthRectification="not_applied"
                metadata.quality.trackingState="unavailable"
                metadata.lensCalibration=LensCalibration(centerX:128,centerY:96,lookupTable:nil,inverseLookupTable:[0.1,0.1,0.1],
                    extrinsicRowMajor:[1,0,0,0,0,1,0,0,0,0,1,0],pixelSizeMillimeters:0.001)
                if missingCalibration { metadata.lensCalibration=nil }
            }
            try writer.append(metadata:metadata,imageJPEG:data as Data,
                depth:DepthGeometry.encode([Float](repeating:0.5,count:64*48)),
                confidence:front ? nil : Data(repeating:2,count:64*48))
        }
        try writer.finish()
        let mask=SurfaceMask(size:size,provenance:.syntheticFixture,method:"central fixture plane",
            includedRuns:(8..<40).map { MaskRun(start:$0*64+8,count:48) })
        let request=CaptureFlowRequest(sourceFrameID:writer.manifest.frames[0].metadata.id,
            targetFrameID:writer.manifest.frames[1].metadata.id,sourceMask:mask,targetMask:mask)
        if missingCalibration {
            XCTAssertThrowsError(try CaptureFlowRegistration.estimate(bundle:writer.url,request:request))
            return
        }
        let report=try CaptureFlowRegistration.estimate(bundle:writer.url,request:request)
        let registration=try XCTUnwrap(report.registration?.registration,report.failureReason ?? "No registration")
        XCTAssertTrue(registration.accepted)
        XCTAssertFalse(report.acceptedForFullHead)
        let matrix=registration.targetFromSource.rowMajor
        XCTAssertEqual(matrix[3],front ? 0.022 : 0.020,accuracy:0.001)
        XCTAssertEqual(matrix[7],front ? 0.01375 : 0.0125,accuracy:0.001)
        XCTAssertEqual(matrix[11],0,accuracy:0.001)
        for index in [0,5,10] { XCTAssertEqual(matrix[index],1,accuracy:0.002) }
        XCTAssertEqual(report.counts.filter { $0.key != "gridSamples" }.values.reduce(0,+),report.counts["gridSamples"])
        XCTAssertEqual(registration.evidenceSource,.syntheticFixture)
        if front {
            XCTAssertTrue(report.registration!.sourceLensCorrection)
            XCTAssertTrue(report.registration!.targetLensCorrection)
        }
    }
    func testBilinearSamplingRejectsInvalidAndOutsideOffsets() {
        var field=ImageFlowField(width:2,height:2,offsets:[0,0,2,0,0,2,2,2])
        XCTAssertEqual(field.sample(x:0.5,y:0.5)?.x,1)
        XCTAssertEqual(field.sample(x:0.5,y:0.5)?.y,1)
        XCTAssertNil(field.sample(x:-0.1,y:0))
        field.offsets[0] = .nan
        XCTAssertNil(field.sample(x:0.5,y:0.5))
    }
}
