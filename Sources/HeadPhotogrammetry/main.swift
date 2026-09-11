import Foundation
import HairCore
#if os(macOS)
import RealityKit
import CoreVideo

@available(macOS 15.0, *)
func reconstruct(bundle: URL, requestURL: URL, output: URL, inferFocalHint: Bool = false, coordinateAudit: Bool = false) async throws {
    let preparationStart = Date()
    guard PhotogrammetrySession.isSupported else { throw CaptureError.invalid("Object Capture is unsupported on this Mac.") }
    guard !FileManager.default.fileExists(atPath:output.path) else { throw CaptureError.invalid("Output directory must be new.") }
    let request = try ManifestCoding.decoder().decode(WorldRegionRequest.self,from:Data(contentsOf:requestURL))
    let masks = try WorldRegionMasks.build(bundle:bundle,request:request)
    let manifest = try CaptureBundle.load(bundle)
    let eligible = masks.frames.filter { $0.includedSamples >= 100 && $0.mask != nil }
    guard (20...120).contains(eligible.count), eligible.count <= PhotogrammetrySession.limits.maximumNumberOfInputImages else {
        throw CaptureError.invalid("This experiment requires 20..120 usable rear frames within the platform limit.")
    }
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    try ManifestCoding.encoder().encode(masks).write(to:output.appendingPathComponent("masks.json"),options:.atomic)
    var samples: [PhotogrammetrySample] = [], evidence: [[String:Any]] = []
    for record in eligible {
        guard let index = manifest.frames.firstIndex(where: { $0.metadata.id == record.frameID }), let mask = record.mask else { continue }
        let frame = manifest.frames[index], size = frame.metadata.imageSize
        guard let depthSize = frame.metadata.depthSize, let depthFile = frame.depth, let confidenceFile = frame.confidence,
              size.width <= PhotogrammetrySession.limits.maximumInputImageDimension,
              size.height <= PhotogrammetrySession.limits.maximumInputImageDimension else { throw CaptureError.invalid("Unsupported image/depth dimensions.") }
        // Bundle inspection and payload() protect the original inputs before vendor decoding.
        let bytes = try CaptureBundle.payload(frame.image,in:bundle)
        let imageURL = output.appendingPathComponent("sample-\(index).jpg")
        try bytes.write(to:imageURL,options:.atomic)
        let loaded = try await PhotogrammetrySample(contentsOf:imageURL)
        guard CVPixelBufferGetWidth(loaded.image) == size.width, CVPixelBufferGetHeight(loaded.image) == size.height else {
            throw CaptureError.invalid("Vendor decoding changed image dimensions/orientation.")
        }
        var sample = PhotogrammetrySample(id:index,image:loaded.image); sample.metadata = loaded.metadata
        var inferredFocal35: Double?
        if inferFocalHint, let k = frame.metadata.intrinsics {
            // Experimental equivalent focal hint from the diagonal FOV. This is not captured EXIF.
            let diagonal = hypot(Double(k.referenceSize.width),Double(k.referenceSize.height))
            let hint = sqrt(k.fx*k.fy)*hypot(36.0,24.0)/diagonal
            sample.metadata["ExifFocalLengthIn35mmFilm"] = hint
            inferredFocal35 = hint
        }
        var included = [UInt8](repeating:0,count:depthSize.width*depthSize.height)
        for run in mask.includedRuns { for pixel in run.start..<(run.start+run.count) { included[pixel] = 255 } }
        let imageMask = try buffer(width:size.width,height:size.height,format:kCVPixelFormatType_OneComponent8)
        CVPixelBufferLockBaseAddress(imageMask,[])
        let maskBase = CVPixelBufferGetBaseAddress(imageMask)!.assumingMemoryBound(to:UInt8.self)
        let maskStride = CVPixelBufferGetBytesPerRow(imageMask)
        for y in 0..<size.height { for x in 0..<size.width {
            maskBase[y*maskStride+x] = included[(y*depthSize.height/size.height)*depthSize.width+x*depthSize.width/size.width]
        } }
        CVPixelBufferUnlockBaseAddress(imageMask,[]); sample.objectMask = imageMask
        let values = try DepthGeometry.decode(CaptureBundle.payload(depthFile,in:bundle),size:depthSize)
        let confidence = try CaptureBundle.payload(confidenceFile,in:bundle)
        let depth = try buffer(width:depthSize.width,height:depthSize.height,format:kCVPixelFormatType_DepthFloat32)
        CVPixelBufferLockBaseAddress(depth,[])
        let depthBase = CVPixelBufferGetBaseAddress(depth)!, stride = CVPixelBufferGetBytesPerRow(depth)
        for y in 0..<depthSize.height {
            let row = depthBase.advanced(by:y*stride).assumingMemoryBound(to:Float.self)
            for x in 0..<depthSize.width {
                let i = y*depthSize.width+x
                row[x] = included[i] != 0 && confidence[i] >= request.minimumConfidence && confidence[i] <= 2 && values[i].isFinite && (0.05...2).contains(values[i]) ? values[i] : .nan
            }
        }
        CVPixelBufferUnlockBaseAddress(depth,[]);sample.depthDataMap = depth
        samples.append(sample)
        var sampleEvidence: [String:Any] = ["sampleID":index,"frameID":record.frameID,"frameSHA256":record.frameSHA256,"imageSHA256":frame.image.sha256]
        if let hint = inferredFocal35 { sampleEvidence["modelInferredFocalLength35mmHint"] = hint }
        evidence.append(sampleEvidence)
        if samples.count % 10 == 0 { print("Prepared \(samples.count) samples.");fflush(stdout) }
    }
    func write(_ value: Any, _ name:String) throws {
        try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent(name),options:.atomic)
    }
    try write(["method":"apple_object_capture_masked_rgb_depth_experiment_v1","captureID":manifest.id,
        "regionRequestSHA256":masks.requestSHA256,"samples":evidence,"acceptedForHeadFitting":false,
        "configuration":["sampleOrdering":"sequential","featureSensitivity":"high","objectMasking":true,"detail":"preview","inferredFocalHint":inferFocalHint,"coordinateAudit":coordinateAudit],
        "notes":["Local reconstruction experiment; not an accepted scalp/head asset.","RGB samples use the original native orientation; masks use nearest depth-to-image mapping.","Native aligned depth supplied in meters; output scale and registration require independent verification.","Spatial masks can retain hair and bun. Reconstruction may interpolate or complete unseen geometry without per-vertex provenance.","No externally estimated gravity or camera pose supplied; Object Capture estimates image alignment."]],"input.json")
    var configuration = PhotogrammetrySession.Configuration()
    configuration.sampleOrdering = .sequential;configuration.featureSensitivity = .high;configuration.isObjectMaskingEnabled = true
    let session = try PhotogrammetrySession(input:samples,configuration:configuration)
    let modelURL = output.appendingPathComponent("preview.usdz")
    var events: [[String:Any]] = [], failed = false, modelComplete = false
    let start = Date()
    let timeout = Task { try? await Task.sleep(for:.seconds(600)); if !Task.isCancelled { session.cancel() } }
    defer { timeout.cancel() }
    print("Object Capture started with \(samples.count) RGB/depth samples; local processing.");fflush(stdout)
    var requests: [PhotogrammetrySession.Request] = [.modelFile(url:modelURL,detail:.preview),.poses,.bounds]
    if coordinateAudit {
        requests += [.modelFile(url:output.appendingPathComponent("identity-preview.usdz"),detail:.preview,geometry:.init()),.pointCloud]
    }
    try session.process(requests:requests)
    for try await event in session.outputs {
        var record: [String:Any] = ["elapsedSeconds":Date().timeIntervalSince(start),"event":event.localizedDescription]
        switch event {
        case .requestComplete(_,let result):
            switch result {
            case .modelFile(let url): modelComplete = true;record["modelFile"] = url.lastPathComponent
            case .poses(let poses):
                var entries: [[String:Any]] = []
                for (id,pose) in poses.posesBySample.sorted(by: { $0.key < $1.key }) {
                    let m = pose.transform.matrix
                    var entry: [String:Any] = ["sampleID":id,"transformColumnMajor":(0..<4).flatMap { c in (0..<4).map { Double(m[c][$0]) } }]
                    if #available(macOS 26.0, *) {
                        if let k = pose.intrinsics { entry["estimatedIntrinsicsColumnMajor"] = (0..<3).flatMap { c in (0..<3).map { Double(k[c][$0]) } } }
                        if let distortion = pose.lensDistortionData {
                            entry["lensDistortion"] = ["center":[distortion.center.x,distortion.center.y],"radialLookupTable":distortion.radialLookupTable]
                        }
                    }
                    entries.append(entry)
                }
                try write(["poses":entries,"coordinateConvention":"Object Capture estimated coordinates; relationship to capture world not validated"],"poses.json")
            case .bounds(let bounds):
                try write(["minimum":[bounds.min.x,bounds.min.y,bounds.min.z],"maximum":[bounds.max.x,bounds.max.y,bounds.max.z]],"bounds.json")
            case .pointCloud(let cloud):
                try write(["positions":cloud.points.map { [$0.position.x,$0.position.y,$0.position.z] },
                           "colors":cloud.points.map { [$0.color.x,$0.color.y,$0.color.z,$0.color.w] },
                           "coordinateConvention":"Object Capture estimated coordinates; not accepted head geometry"],"point-cloud.json")
            default: break
            }
        case .requestError(_,let error): failed = true;record["error"] = error.localizedDescription
        case .invalidSample(let id,let reason):record["sampleID"] = id;record["reason"] = reason
        case .skippedSample(let id):record["sampleID"] = id
        case .processingCancelled: failed = true
        default: break
        }
        events.append(record);try write(events,"events.json")
        print(event.localizedDescription);fflush(stdout)
        if case .processingComplete = event { break }
        if case .processingCancelled = event { break }
    }
    let succeeded = modelComplete && !failed && FileManager.default.fileExists(atPath:modelURL.path)
    var result: [String:Any] = ["processingSucceeded":succeeded,"acceptedForHeadFitting":false,"elapsedSeconds":Date().timeIntervalSince(start),
        "totalElapsedSeconds":Date().timeIntervalSince(preparationStart),"modelCompleted":modelComplete,"sampleCount":samples.count]
    if modelComplete { result["modelSHA256"] = EvidenceHash.sha256(try Data(contentsOf:modelURL)) }
    try write(result,"result.json")
    guard succeeded else { throw CaptureError.invalid("Object Capture did not produce a successful model. See events.json.") }
}

func buffer(width:Int,height:Int,format:OSType) throws -> CVPixelBuffer {
    var result: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault,width,height,format,nil,&result)
    guard status == kCVReturnSuccess, let result else { throw CaptureError.invalid("Pixel buffer allocation failed.") }
    return result
}
#endif

@main struct Main {
    static func main() async {
        do {
            #if os(macOS)
            if #available(macOS 15.0, *) {
                let args = CommandLine.arguments
                let flags = Array(args.dropFirst(4))
                guard (4...6).contains(args.count), Set(flags).count == flags.count,
                      flags.allSatisfy({ ["--infer-focal-hint","--coordinate-audit"].contains($0) }) else { throw CaptureError.invalid("Usage: head-photogrammetry CAPTURE_BUNDLE REGION_REQUEST.json NEW_OUTPUT_DIRECTORY [--infer-focal-hint] [--coordinate-audit]") }
                try await reconstruct(bundle:URL(fileURLWithPath:args[1]),requestURL:URL(fileURLWithPath:args[2]),output:URL(fileURLWithPath:args[3]),inferFocalHint:flags.contains("--infer-focal-hint"),coordinateAudit:flags.contains("--coordinate-audit"))
            } else { throw CaptureError.invalid("This experiment requires macOS 15 or later.") }
            #else
            throw CaptureError.invalid("Run this reconstruction experiment on a supported Mac.")
            #endif
        } catch { FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1) }
    }
}
