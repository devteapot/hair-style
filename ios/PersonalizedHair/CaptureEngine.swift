import Foundation
import AVFoundation
import ARKit
import CoreImage
import HairCore

struct CaptureUpdate {
    var jpeg: Data
    var metadata: FrameMetadata
    var frameCount: Int
}

/// All mutable state and writer I/O are confined to `queue`.
final class CaptureEngine: NSObject, AVCaptureDataOutputSynchronizerDelegate, ARSessionDelegate {
    private let queue = DispatchQueue(label: "dev.personalizedhair.capture", qos: .userInitiated)
    private let avSession = AVCaptureSession()
    private let arSession = ARSession()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var videoOutput: AVCaptureVideoDataOutput?
    private var depthOutput: AVCaptureDepthDataOutput?
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var writer: CaptureBundleWriter?
    private var lastSample: Double = -.infinity
    private var activeKind: CaptureKind?
    private var trackedFrontCapture = false
    private var trackedAnchorID: UUID?
    private var lastTrackedDepthTime: Double = -.infinity
    private var trackedWaitStart: Double?
    private var trackedCameraRate: Double?
    private var notifications: [NSObjectProtocol] = []
    var onUpdate: ((CaptureUpdate) -> Void)?
    var onStarted: ((URL) -> Void)?
    var onStopped: ((URL?) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        arSession.delegate = self
        arSession.delegateQueue = queue
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: avSession, queue: nil) { [weak self] _ in
                self?.stop(interrupted: true, note: "Camera session interrupted. Start a new pass when ready.")
            })
        }
    }

    deinit { notifications.forEach(NotificationCenter.default.removeObserver) }

    func start(kind: CaptureKind, root: URL, subjectSessionID: String, device: DeviceReport, denseFrontSampling: Bool = false, trackedFrontCapture: Bool = false, hairCondition: HairCaptureCondition = .unknown) {
        queue.async {
            guard self.writer == nil else { return }
            do {
                guard device.eligible else { throw CaptureError.invalid("This scan requires front TrueDepth, rear LiDAR, and face tracking on a physical iPhone.") }
                self.activeKind = kind
                self.lastSample = -.infinity
                self.trackedFrontCapture = kind == .frontFace && trackedFrontCapture
                self.trackedAnchorID = nil
                self.lastTrackedDepthTime = -.infinity
                self.trackedWaitStart = nil
                self.trackedCameraRate = nil
                if kind == .frontFace && !self.trackedFrontCapture { try self.configureFront() }
                let writer = try CaptureBundleWriter(root: root, subjectSessionID: subjectSessionID, kind: kind,
                    source: .sensor, device: device, consentVersion: "local-capture-adult-v1", sampleRateHz: kind == .frontFace && denseFrontSampling ? 15 : 3,
                    declaredHairCondition: hairCondition)
                self.writer = writer
                if self.trackedFrontCapture {
                    guard ARFaceTrackingConfiguration.isSupported else { throw CaptureError.invalid("Face tracking is unavailable.") }
                    let config = ARFaceTrackingConfiguration()
                    config.maximumNumberOfTrackedFaces = 1
                    self.trackedCameraRate = Double(config.videoFormat.framesPerSecond)
                    self.arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
                } else if kind == .frontFace { self.avSession.startRunning() }
                else {
                    let config = ARWorldTrackingConfiguration()
                    config.frameSemantics = [.sceneDepth]
                    config.environmentTexturing = .none
                    self.arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
                }
                DispatchQueue.main.async { self.onStarted?(writer.url) }
            } catch { self.fail(error.localizedDescription) }
        }
    }

    func stop(interrupted: Bool = false, note: String? = nil) {
        queue.async { self.stopOnQueue(interrupted: interrupted, note: note) }
    }

    private func stopOnQueue(interrupted: Bool, note: String?) {
        arSession.pause()
        if avSession.isRunning { avSession.stopRunning() }
        let url = writer?.url
        do { try writer?.finish(interrupted: interrupted, note: note) }
        catch { DispatchQueue.main.async { self.onError?(error.localizedDescription) } }
        writer = nil; activeKind = nil
        DispatchQueue.main.async { self.onStopped?(url) }
    }

    private func fail(_ message: String) {
        stopOnQueue(interrupted: true, note: message)
        DispatchQueue.main.async { self.onError?(message) }
    }

    private func configureFront() throws {
        avSession.beginConfiguration()
        defer { avSession.commitConfiguration() }
        avSession.inputs.forEach(avSession.removeInput)
        avSession.outputs.forEach(avSession.removeOutput)
        avSession.sessionPreset = .inputPriority
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
            throw CaptureError.invalid("TrueDepth camera is unavailable.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard avSession.canAddInput(input) else { throw CaptureError.invalid("Could not configure TrueDepth input.") }
        avSession.addInput(input)

        let candidates = device.formats.flatMap { format -> [(AVCaptureDevice.Format, CMFormatDescription)] in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard size.width <= 1920, format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }) else { return [] }
            return format.supportedDepthDataFormats.filter {
                [kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32].contains(CMFormatDescriptionGetMediaSubType($0.formatDescription))
                    && $0.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 })
            }.map { (format, $0.formatDescription) }
        }
        guard let best = candidates.max(by: { CMVideoFormatDescriptionGetDimensions($0.1).width < CMVideoFormatDescriptionGetDimensions($1.1).width }),
              let depthFormat = best.0.supportedDepthDataFormats.first(where: { CMFormatDescriptionEqual($0.formatDescription, otherFormatDescription: best.1) }) else {
            throw CaptureError.invalid("No supported synchronized depth format found.")
        }
        try device.lockForConfiguration()
        device.activeFormat = best.0
        device.activeDepthDataFormat = depthFormat
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
        device.unlockForConfiguration()

        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let depth = AVCaptureDepthDataOutput()
        depth.isFilteringEnabled = false
        depth.alwaysDiscardsLateDepthData = true
        guard avSession.canAddOutput(video), avSession.canAddOutput(depth) else {
            throw CaptureError.invalid("Synchronized camera outputs are unavailable.")
        }
        avSession.addOutput(video); avSession.addOutput(depth)
        for connection in [video.connection(with: .video), depth.connection(with: .depthData)].compactMap({ $0 }) {
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            connection.isEnabled = true
        }
        let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [video, depth])
        sync.setDelegate(self, queue: queue)
        videoOutput = video; depthOutput = depth; synchronizer = sync
    }

    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput collection: AVCaptureSynchronizedDataCollection) {
        guard activeKind == .frontFace, !trackedFrontCapture, let videoOutput, let depthOutput, let writer,
              let video = collection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              let depth = collection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
              !video.sampleBufferWasDropped, !depth.depthDataWasDropped,
              let image = CMSampleBufferGetImageBuffer(video.sampleBuffer) else { return }
        let time = CMTimeGetSeconds(video.timestamp)
        // In dense mode save each distinct synchronized callback from the fixed
        // 15 Hz camera; a floating-point 1/15 threshold could skip alternate frames.
        if writer.manifest.requestedSampleRateHz == 15 {
            guard time > lastSample else { return }
        } else {
            guard time - lastSample >= 1 / writer.manifest.requestedSampleRateHz else { return }
        }
        lastSample = time
        do {
            let converted = depth.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            guard let calibration = converted.cameraCalibrationData else { throw CaptureError.invalid("TrueDepth did not supply camera calibration.") }
            let (depthData, quality) = try CameraEvidence.depth(converted.depthDataMap)
            let reference = calibration.intrinsicMatrixReferenceDimensions
            var q = quality
            let depthTime = CMTimeGetSeconds(depth.timestamp)
            q.synchronizationDeltaSeconds = abs(time - depthTime)
            q.notes = ["Head pose unavailable; later registration required."]
            var metadata = FrameMetadata(imageTimestamp: time, depthTimestamp: depthTime,
                imageSize: CameraEvidence.size(image), depthSize: CameraEvidence.size(converted.depthDataMap),
                intrinsics: CameraEvidence.intrinsics(calibration.intrinsicMatrix, referenceSize: PixelSize(Int(reference.width), Int(reference.height))),
                lensCalibration: CameraEvidence.lens(calibration), depthFiltered: converted.isDepthDataFiltered,
                quality: q)
            metadata.sourceImagePixelFormat = CVPixelBufferGetPixelFormatType(image)
            metadata.sourceDepthPixelFormat = depth.depthData.depthDataType
            metadata.nominalCameraFrameRate = 15
            try persist(image: image, metadata: metadata, depth: depthData)
        } catch { fail(error.localizedDescription) }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if activeKind == .frontFace && trackedFrontCapture {
            captureTrackedFront(frame)
            return
        }
        guard activeKind != .frontFace, let writer, frame.timestamp - lastSample >= 1 / writer.manifest.requestedSampleRateHz else { return }
        lastSample = frame.timestamp
        do {
            guard let sceneDepth = frame.sceneDepth else { return }
            let (data, quality) = try CameraEvidence.depth(sceneDepth.depthMap)
            var q = quality
            q.synchronizationDeltaSeconds = 0
            q.trackingState = String(describing: frame.camera.trackingState)
            q.notes = ["World pose does not compensate for subject movement."]
            var metadata = FrameMetadata(imageTimestamp: frame.timestamp, depthTimestamp: frame.timestamp,
                imageSize: CameraEvidence.size(frame.capturedImage), depthSize: CameraEvidence.size(sceneDepth.depthMap),
                intrinsics: CameraEvidence.intrinsics(frame.camera.intrinsics, referenceSize: CameraEvidence.size(frame.capturedImage)),
                depthFiltered: false, depthRectification: "arkit_aligned_scene_depth",
                worldFromOpticalCamera: CameraEvidence.worldFromOptical(frame.camera.transform), poseSource: "arkit_world_tracking", quality: q)
            metadata.sourceImagePixelFormat = CVPixelBufferGetPixelFormatType(frame.capturedImage)
            metadata.sourceDepthPixelFormat = CVPixelBufferGetPixelFormatType(sceneDepth.depthMap)
            try persist(image: frame.capturedImage, metadata: metadata, depth: data,
                confidence: sceneDepth.confidenceMap.flatMap(CameraEvidence.confidence), exif: frame.exifData)
        } catch { fail(error.localizedDescription) }
    }

    private func captureTrackedFront(_ frame: ARFrame) {
        guard let writer else { return }
        // Depth arrives on only some AR frames. Never reuse it with a later pose.
        if trackedWaitStart == nil { trackedWaitStart = frame.timestamp }
        let faces = frame.anchors.compactMap { $0 as? ARFaceAnchor }.filter { $0.isTracked }
        if let anchorID = trackedAnchorID, faces.contains(where: { $0.identifier != anchorID }) {
            fail("Face tracking changed identity. Capture preserved; start a new pass.")
            return
        }
        guard case .normal = frame.camera.trackingState,
              faces.count == 1, let face = faces.first,
              let depth = frame.capturedDepthData,
              frame.capturedDepthDataTimestamp.isFinite,
              frame.capturedDepthDataTimestamp > lastTrackedDepthTime,
              abs(frame.timestamp - frame.capturedDepthDataTimestamp) <= 0.01 else {
            if frame.timestamp - (trackedWaitStart ?? frame.timestamp) > 5 {
                fail("No synchronized tracked face depth for five seconds. Keep your face visible and start a new pass.")
            }
            return
        }
        trackedWaitStart = frame.timestamp
        trackedAnchorID = face.identifier
        guard frame.timestamp - lastSample >= 1 / writer.manifest.requestedSampleRateHz else { return }
        do {
            let converted = depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            guard let calibration = converted.cameraCalibrationData else {
                throw CaptureError.invalid("Tracked TrueDepth did not supply camera calibration.")
            }
            let (data, quality) = try CameraEvidence.depth(converted.depthDataMap)
            let reference = calibration.intrinsicMatrixReferenceDimensions
            var q = quality
            q.headPoseAvailable = true
            q.synchronizationDeltaSeconds = abs(frame.timestamp - frame.capturedDepthDataTimestamp)
            q.trackingState = String(describing: frame.camera.trackingState)
            q.notes = ["Experimental ARKit face-local pose estimate; not measured skull geometry.",
                       "Raw depth/RGB calibration and tracker alignment require physical validation."]
            var metadata = FrameMetadata(imageTimestamp: frame.timestamp, depthTimestamp: frame.capturedDepthDataTimestamp,
                imageSize: CameraEvidence.size(frame.capturedImage), depthSize: CameraEvidence.size(converted.depthDataMap),
                intrinsics: CameraEvidence.intrinsics(calibration.intrinsicMatrix, referenceSize: PixelSize(Int(reference.width), Int(reference.height))),
                lensCalibration: CameraEvidence.lens(calibration), depthFiltered: converted.isDepthDataFiltered, quality: q)
            metadata.headPose = HeadPoseEvidence(
                headFromOpticalCamera: CameraEvidence.worldFromOptical(simd_inverse(face.transform) * frame.camera.transform),
                timestamp: frame.timestamp, anchorID: face.identifier.uuidString)
            metadata.sourceImagePixelFormat = CVPixelBufferGetPixelFormatType(frame.capturedImage)
            metadata.sourceDepthPixelFormat = depth.depthDataType
            metadata.nominalCameraFrameRate = trackedCameraRate
            lastSample = frame.timestamp
            lastTrackedDepthTime = frame.capturedDepthDataTimestamp
            try persist(image: frame.capturedImage, metadata: metadata, depth: data, exif: frame.exifData)
        } catch { fail(error.localizedDescription) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) { fail(error.localizedDescription) }
    func sessionWasInterrupted(_ session: ARSession) { stopOnQueue(interrupted: true, note: "AR session interrupted. Capture preserved.") }

    private func persist(image: CVPixelBuffer, metadata: FrameMetadata, depth: Data, confidence: Data? = nil, exif: [String:Any] = [:]) throws {
        guard let writer else { return }
        var metadata = metadata
        // Diagnostic failure must not discard otherwise usable sensor evidence.
        metadata.quality.imageDetail = try? ImageDetailEvidence.measure(image: CIImage(cvPixelBuffer: image), context: context)
        let jpeg = try CameraEvidence.imageJPEG(image, context: context, exif:exif)
        try writer.append(metadata: metadata, imageJPEG: jpeg, depth: depth, confidence: confidence)
        let update = CaptureUpdate(jpeg: jpeg, metadata: metadata, frameCount: writer.manifest.frames.count)
        DispatchQueue.main.async { self.onUpdate?(update) }
        if writer.manifest.frames.count >= 900 {
            stopOnQueue(interrupted: false, note: "Stopped at the 900-frame limit. Additional coverage needs a new pass.")
        } else if ProcessInfo.processInfo.thermalState == .critical {
            stopOnQueue(interrupted: true, note: "Device temperature is too high. Allow it to cool before another pass.")
        }
    }
}
