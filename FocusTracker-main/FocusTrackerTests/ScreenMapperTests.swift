import XCTest
import simd
@testable import FocusTracker

final class ScreenMapperTests: XCTestCase {

    /// Standard test screen size matching a typical iPhone (390 x 844 points).
    private let testScreenSize = CGSize(width: 390, height: 844)

    // MARK: - Helpers

    /// Builds an identity 4x4 matrix with the specified translation, simulating a
    /// face positioned in front of the camera.
    private func makeFaceTransform(
        tx: Float = 0.0,
        ty: Float = 0.0,
        tz: Float = 0.35
    ) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = simd_float4(tx, ty, tz, 1.0)
        return m
    }

    // MARK: - Tests

    /// A gaze directed roughly straight ahead should map to approximately the center
    /// of the screen.
    func testCenterGazeMapsToCenterScreen() {
        let mapper = ScreenMapper(screenSize: testScreenSize)

        // lookAtPoint straight ahead along -Z in face-local space.
        // In ARKit, the face looks toward -Z. A point at (0, 0, -0.05) is directly
        // in front of the nose.
        let lookAt = simd_float3(0.0, 0.0, -0.05)
        let faceTransform = makeFaceTransform()

        let result = mapper.map(lookAtPoint: lookAt, faceTransform: faceTransform)

        // The mapped point should be roughly near the center of the screen.
        let centerX = testScreenSize.width / 2
        let centerY = testScreenSize.height / 2

        XCTAssertEqual(
            result.point.x, centerX,
            accuracy: testScreenSize.width * 0.25,
            "Gaze straight ahead should map near screen center X."
        )
        XCTAssertEqual(
            result.point.y, centerY,
            accuracy: testScreenSize.height * 0.25,
            "Gaze straight ahead should map near screen center Y."
        )
        XCTAssertTrue(result.isOnScreen, "Center gaze should be on screen.")
    }

    /// A gaze directed far to the right or far upward should be detected as off-screen.
    func testOffScreenGazeDetected() {
        let mapper = ScreenMapper(screenSize: testScreenSize)

        // Look far to the right in face-local space (large positive X).
        let lookAtFarRight = simd_float3(0.5, 0.0, -0.05)
        let faceTransform = makeFaceTransform()

        let result = mapper.map(lookAtPoint: lookAtFarRight, faceTransform: faceTransform)

        XCTAssertFalse(
            result.isOnScreen,
            "Gaze directed far to the side should be off screen. Point: \(result.point)"
        )
    }

    /// Applying a non-identity calibration should shift the output compared to
    /// uncalibrated mapping.
    func testCalibrationApplied() {
        let mapper = ScreenMapper(screenSize: testScreenSize)

        let lookAt = simd_float3(0.0, 0.0, -0.05)
        let faceTransform = makeFaceTransform()

        // Uncalibrated baseline.
        let uncalibrated = mapper.map(lookAtPoint: lookAt, faceTransform: faceTransform)

        // Apply a calibration with a noticeable offset.
        let calibration = CalibrationResult(
            points: [],
            scaleX: 1.1,
            scaleY: 0.9,
            offsetX: 20.0,
            offsetY: -15.0,
            rotationAngle: 0.0,
            accuracy: 5.0,
            calibratedAt: .now
        )
        mapper.setCalibration(calibration)

        let calibrated = mapper.map(lookAtPoint: lookAt, faceTransform: faceTransform)

        // The calibrated output should differ from the uncalibrated output.
        let distance = hypot(
            calibrated.point.x - uncalibrated.point.x,
            calibrated.point.y - uncalibrated.point.y
        )

        XCTAssertGreaterThan(
            distance, 5.0,
            "Calibrated output should differ from uncalibrated by at least a few points. "
            + "Uncalibrated: \(uncalibrated.point), Calibrated: \(calibrated.point)"
        )
    }

    /// The identity calibration should produce output identical (or nearly identical)
    /// to having no calibration at all.
    func testIdentityCalibrationNoChange() {
        let mapper = ScreenMapper(screenSize: testScreenSize)

        let lookAt = simd_float3(0.01, -0.01, -0.05)
        let faceTransform = makeFaceTransform()

        // Baseline with no calibration.
        let baseline = mapper.map(lookAtPoint: lookAt, faceTransform: faceTransform)

        // Apply identity calibration.
        mapper.setCalibration(.identity)

        let withIdentity = mapper.map(lookAtPoint: lookAt, faceTransform: faceTransform)

        XCTAssertEqual(
            withIdentity.point.x, baseline.point.x,
            accuracy: 0.01,
            "Identity calibration should not change the X coordinate."
        )
        XCTAssertEqual(
            withIdentity.point.y, baseline.point.y,
            accuracy: 0.01,
            "Identity calibration should not change the Y coordinate."
        )
        XCTAssertEqual(
            withIdentity.isOnScreen, baseline.isOnScreen,
            "Identity calibration should not change on-screen status."
        )
    }
}
