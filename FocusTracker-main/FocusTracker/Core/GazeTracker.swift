import ARKit
import Combine
import simd

/// Primary ARKit face tracking engine.
///
/// Captures face anchor data at ~30 FPS (downsampled from the native 60 FPS
/// TrueDepth camera rate) and publishes `GazeFrame` values through a Combine
/// subject. Consumers subscribe to `gazeSubject` to receive the raw eye
/// tracking signal for downstream processing (smoothing, fixation detection,
/// focus scoring, etc.).
final class GazeTracker: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: - Public Properties

    let session = ARSession()
    let gazeSubject = PassthroughSubject<GazeFrame, Never>()

    @Published var isTracking = false
    @Published var trackingQuality: Float = 0

    // MARK: - Private Properties

    private var lastFrameTime: TimeInterval = 0
    private let targetFPS: Double = 30

    /// Minimum inter-frame interval used to downsample from 60 FPS to ~30 FPS.
    private var minFrameInterval: TimeInterval { 1.0 / targetFPS }

    /// Screen mapper used to project 3D lookAtPoint into 2D screen coordinates.
    private let screenMapper = ScreenMapper()

    // MARK: - Tracking Control

    /// Configures and starts the ARKit face tracking session.
    ///
    /// Requires a device with a TrueDepth camera (iPhone X or later).
    /// The session runs at 60 FPS natively; frames are downsampled to
    /// `targetFPS` in the delegate callback.
    func startTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("[GazeTracker] Face tracking is not supported on this device.")
            return
        }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1

        if #available(iOS 17.0, *) {
            configuration.videoHDRAllowed = false
        }

        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        lastFrameTime = 0
        isTracking = true
    }

    /// Pauses the ARKit session and stops publishing gaze frames.
    func stopTracking() {
        session.pause()
        isTracking = false
        trackingQuality = 0
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isTracking else { return }

        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }

            let currentTime = faceAnchor.transform.timestamp ?? CACurrentMediaTime()

            // Downsample: skip frames that arrive faster than our target rate.
            if lastFrameTime > 0 && (currentTime - lastFrameTime) < minFrameInterval {
                continue
            }
            lastFrameTime = currentTime

            let frame = buildGazeFrame(from: faceAnchor, at: currentTime)
            gazeSubject.send(frame)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[GazeTracker] Session failed: \(error.localizedDescription)")
        isTracking = false
        trackingQuality = 0
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .notAvailable:
            trackingQuality = 0
        case .limited(let reason):
            switch reason {
            case .initializing:
                trackingQuality = 0.25
            case .excessiveMotion:
                trackingQuality = 0.3
            case .insufficientFeatures:
                trackingQuality = 0.2
            case .relocalizing:
                trackingQuality = 0.1
            @unknown default:
                trackingQuality = 0.2
            }
        case .normal:
            trackingQuality = 1.0
        }
    }

    // MARK: - Frame Construction

    /// Builds a `GazeFrame` from an ARKit face anchor.
    ///
    /// Extracts eye transforms, blink blend shapes, head orientation, and
    /// projects the 3D gaze direction onto 2D screen coordinates using
    /// `ScreenMapper`.
    private func buildGazeFrame(from faceAnchor: ARFaceAnchor, at timestamp: TimeInterval) -> GazeFrame {
        // Eye positions (columns 3 of the 4x4 transform = translation component).
        let leftEyePos = simd_float3(
            faceAnchor.leftEyeTransform.columns.3.x,
            faceAnchor.leftEyeTransform.columns.3.y,
            faceAnchor.leftEyeTransform.columns.3.z
        )
        let rightEyePos = simd_float3(
            faceAnchor.rightEyeTransform.columns.3.x,
            faceAnchor.rightEyeTransform.columns.3.y,
            faceAnchor.rightEyeTransform.columns.3.z
        )

        // lookAtPoint is relative to the face anchor's coordinate space.
        let lookAt = faceAnchor.lookAtPoint

        // Blink blend shapes (0.0 = open, 1.0 = fully closed).
        let leftBlink = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let rightBlink = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0

        // Head orientation: extract Euler angles from the anchor's world transform.
        let (pitch, yaw, roll) = eulerAngles(from: faceAnchor.transform)

        // Project the 3D gaze direction onto the 2D screen plane.
        let mapping = screenMapper.map(lookAtPoint: lookAt, faceTransform: faceAnchor.transform)

        // Tracking quality derived from face anchor state.
        let quality: Float
        if #available(iOS 17.0, *) {
            quality = faceAnchor.isTracked ? 1.0 : 0.0
        } else {
            quality = faceAnchor.isTracked ? 1.0 : 0.0
        }

        return GazeFrame(
            timestamp: timestamp,
            gazePointX: mapping.point.x,
            gazePointY: mapping.point.y,
            leftEyePosition: leftEyePos,
            rightEyePosition: rightEyePos,
            lookAtPoint: lookAt,
            leftBlinkValue: leftBlink,
            rightBlinkValue: rightBlink,
            headEulerX: pitch,
            headEulerY: yaw,
            headEulerZ: roll,
            isOnScreen: mapping.isOnScreen,
            trackingQuality: quality
        )
    }

    /// Extracts Euler angles (pitch, yaw, roll) from a 4x4 transformation matrix.
    ///
    /// Uses the ZYX (yaw-pitch-roll) convention consistent with ARKit's
    /// coordinate system where:
    /// - X (pitch): rotation around the horizontal axis (nodding)
    /// - Y (yaw): rotation around the vertical axis (shaking head)
    /// - Z (roll): rotation around the depth axis (tilting head)
    private func eulerAngles(from transform: simd_float4x4) -> (pitch: Float, yaw: Float, roll: Float) {
        let m = transform
        let sy = sqrt(m.columns.0.x * m.columns.0.x + m.columns.1.x * m.columns.1.x)

        let singular = sy < 1e-6

        let pitch: Float
        let yaw: Float
        let roll: Float

        if !singular {
            pitch = atan2(m.columns.2.y, m.columns.2.z)
            yaw   = atan2(-m.columns.2.x, sy)
            roll  = atan2(m.columns.1.x, m.columns.0.x)
        } else {
            pitch = atan2(-m.columns.1.z, m.columns.1.y)
            yaw   = atan2(-m.columns.2.x, sy)
            roll  = 0
        }

        return (pitch, yaw, roll)
    }
}

// MARK: - simd_float4x4 Timestamp Helper

private extension simd_float4x4 {
    /// ARKit anchors do not carry an explicit timestamp on the transform,
    /// so this is a placeholder that returns nil. The caller falls back
    /// to `CACurrentMediaTime()`.
    var timestamp: TimeInterval? { nil }
}
