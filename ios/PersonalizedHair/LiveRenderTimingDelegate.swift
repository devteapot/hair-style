import ARKit
import HairCore

/// Each camera run owns a separate delegate. Callbacks may arrive off-main;
/// the lock protects the bounded recorder and rejects callbacks after stop.
final class LiveRenderTimingDelegate: NSObject, ARSCNViewDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: RenderTimingRecorder?

    init(haircutSHA256: String, context: RenderTimingContext = .liveCamera) throws {
        recorder = try RenderTimingRecorder(haircutSHA256: haircutSHA256, context: context)
        super.init()
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        lock.lock(); defer { lock.unlock() }
        recorder?.append(timestamp: CACurrentMediaTime(), thermalState: thermal)
    }

    func stop() -> RenderTimingReport? {
        lock.lock(); defer { lock.unlock() }
        let result = recorder?.report(); recorder = nil
        return result
    }
}
