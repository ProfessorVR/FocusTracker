import Foundation
import simd
import UIKit

/// Converts 3D ARKit `lookAtPoint` vectors into 2D screen coordinates.
///
/// ## Coordinate Systems
///
/// ARKit uses a right-handed coordinate system anchored to the face:
/// - **X**: positive to the right (from the viewer's perspective, the face's left)
/// - **Y**: positive upward
/// - **Z**: positive toward the viewer (out of the face, toward the camera)
///
/// The `lookAtPoint` from `ARFaceAnchor` is expressed in the face anchor's
/// local coordinate system. To determine where on the phone screen the user
/// is looking, we need to:
///
/// 1. Transform `lookAtPoint` from face-local space into world space using
///    the face anchor's `transform` (a 4x4 matrix).
/// 2. Compute a gaze direction ray from the face position toward the
///    transformed lookAtPoint.
/// 3. Intersect that ray with the screen plane (approximated as a plane
///    perpendicular to the Z axis at the phone's estimated distance).
/// 4. Map the intersection from meters to screen points (0,0 at top-left).
///
/// ## Assumptions
///
/// - The phone is held roughly upright in portrait orientation, facing the user.
/// - The TrueDepth camera is at the top center of the device.
/// - The user sits approximately 35 cm from the phone (adjustable via
///   `estimatedPhoneDistance`).
/// - Screen coordinate origin (0,0) is at the top-left corner.
final class ScreenMapper {

    // MARK: - Properties

    /// Device screen size in points.
    let screenSize: CGSize

    /// Optional calibration transform to improve accuracy.
    private(set) var calibration: CalibrationResult?

    // MARK: - Constants

    /// Estimated distance from the user's face to the phone screen in meters.
    /// Most users hold their phone 25-40 cm away; 35 cm is a reasonable default.
    private let estimatedPhoneDistance: Float = 0.35

    /// Vertical offset from the TrueDepth camera to the center of the screen,
    /// in meters. The camera sits at the top notch/Dynamic Island; the screen
    /// center is roughly 7 cm below. Positive Y is up in ARKit, so the screen
    /// center is at a negative offset.
    private let cameraToScreenCenterY: Float = -0.07

    /// Horizontal half-width of the screen in meters (~3.3 cm for a 6.1" iPhone).
    private let screenHalfWidthMeters: Float = 0.033

    /// Vertical half-height of the screen in meters (~7.1 cm for a 6.1" iPhone).
    private let screenHalfHeightMeters: Float = 0.071

    /// Extra margin (in points) around the screen edges within which gaze is
    /// still considered "on screen." Accounts for mapping imprecision.
    private let onScreenMargin: CGFloat = 40.0

    // MARK: - Initialization

    init(screenSize: CGSize? = nil) {
        self.screenSize = screenSize ?? UIScreen.main.bounds.size
    }

    // MARK: - Public API

    /// Maps a 3D ARKit `lookAtPoint` to a 2D screen coordinate.
    ///
    /// - Parameters:
    ///   - lookAtPoint: The `ARFaceAnchor.lookAtPoint` in face-local coordinates.
    ///   - faceTransform: The face anchor's world transform (`ARFaceAnchor.transform`).
    /// - Returns: A tuple of the projected screen point and whether it falls
    ///   within the visible screen area (with margin).
    ///
    /// ## Algorithm
    ///
    /// ```
    /// Face-local lookAtPoint
    ///        |
    ///        v
    /// [faceTransform] ---> World-space lookAtPoint
    ///        |
    ///        v
    /// Gaze direction = worldLookAt - facePosition
    ///        |
    ///        v
    /// Ray-plane intersection at Z = 0 (screen plane)
    ///        |
    ///        v
    /// Convert meters to screen points
    ///        |
    ///        v
    /// Apply calibration (optional)
    /// ```
    func map(lookAtPoint: simd_float3, faceTransform: simd_float4x4) -> (point: CGPoint, isOnScreen: Bool) {

        // Step 1: Transform the lookAtPoint from face-local space to world space.
        //
        // ARKit's lookAtPoint is relative to the face anchor. We multiply by the
        // face anchor's world transform to get a world-space target position.
        // We use a homogeneous coordinate (w=1) for a point (not a direction).
        let localPoint = simd_float4(lookAtPoint.x, lookAtPoint.y, lookAtPoint.z, 1.0)
        let worldPoint4 = faceTransform * localPoint
        let worldLookAt = simd_float3(worldPoint4.x, worldPoint4.y, worldPoint4.z)

        // Step 2: Get the face position in world space.
        //
        // The translation component of the face transform is in column 3.
        let facePosition = simd_float3(
            faceTransform.columns.3.x,
            faceTransform.columns.3.y,
            faceTransform.columns.3.z
        )

        // Step 3: Compute the gaze direction ray.
        //
        // Direction from the face toward the point the user is looking at.
        let gazeDirection = worldLookAt - facePosition
        let gazeLength = simd_length(gazeDirection)

        // Guard against degenerate zero-length direction.
        guard gazeLength > 1e-6 else {
            let center = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            return (center, true)
        }
        let gazeNormalized = gazeDirection / gazeLength

        // Step 4: Intersect the gaze ray with the screen plane.
        //
        // We model the screen as a plane at Z = 0 in world space. The camera
        // (and face) have a positive Z value since ARKit places the world origin
        // at the session start and the face is in front of the camera.
        //
        // However, in practice the face Z position changes as the user moves,
        // so instead of intersecting with Z=0, we project forward by the
        // estimated phone distance along the gaze direction.
        //
        // The intersection X/Y coordinates (in meters) tell us how far left/right
        // and up/down the gaze lands relative to the camera position.

        // Project the gaze ray forward to the screen distance.
        // The Z component of the gaze direction tells us how "forward" the ray goes.
        // We want to reach a plane at distance `estimatedPhoneDistance` from the face
        // along the Z axis.
        let zComponent = abs(gazeNormalized.z)
        guard zComponent > 1e-6 else {
            let center = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
            return (center, false)
        }

        // Parameter t at which the ray reaches the screen plane distance.
        let t = estimatedPhoneDistance / zComponent

        // Intersection point in world space, relative to the face position.
        let intersectionX = gazeNormalized.x * t
        let intersectionY = gazeNormalized.y * t

        // Step 5: Convert from meters to screen coordinates.
        //
        // The intersection X is in meters, with 0 = straight ahead from the face.
        // Negative X in ARKit (right-hand rule) = user's right = screen's left.
        //
        // Screen coordinate system:
        //   (0,0) = top-left
        //   (+X)  = rightward
        //   (+Y)  = downward
        //
        // ARKit coordinate system (from the face's perspective looking at the camera):
        //   (+X)  = face's left = screen's right (camera is mirrored)
        //   (+Y)  = upward
        //
        // So: screenX = center + intersectionX * scale (X maps directly since
        //     ARKit +X = user's left = screen right when camera mirrors)
        //     screenY = center - intersectionY * scale (ARKit +Y is up, screen +Y is down)

        // Map horizontal: 0 meters = screen center X.
        // intersectionX ranges roughly from -screenHalfWidth to +screenHalfWidth.
        let normalizedX = (intersectionX / screenHalfWidthMeters + 1.0) / 2.0
        let screenX = CGFloat(normalizedX) * screenSize.width

        // Map vertical: account for camera-to-screen-center offset.
        // The camera is above the screen center, so we shift the Y coordinate.
        let adjustedY = intersectionY - cameraToScreenCenterY
        let normalizedY = (1.0 - adjustedY / screenHalfHeightMeters) / 2.0
        let screenY = CGFloat(normalizedY) * screenSize.height

        var point = CGPoint(x: screenX, y: screenY)

        // Step 6: Apply calibration correction if available.
        if let cal = calibration {
            point = cal.apply(to: point)
        }

        // Step 7: Determine whether the gaze point falls on the screen.
        let isOnScreen = point.x >= -onScreenMargin
            && point.x <= screenSize.width + onScreenMargin
            && point.y >= -onScreenMargin
            && point.y <= screenSize.height + onScreenMargin

        return (point, isOnScreen)
    }

    // MARK: - Calibration

    /// Applies a calibration result to improve mapping accuracy.
    func setCalibration(_ cal: CalibrationResult) {
        calibration = cal
    }

    /// Removes the current calibration, reverting to the default projection.
    func clearCalibration() {
        calibration = nil
    }
}
