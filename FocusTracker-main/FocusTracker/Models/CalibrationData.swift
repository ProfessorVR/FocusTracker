import Foundation

struct CalibrationPoint: Codable {
    let targetX: CGFloat
    let targetY: CGFloat
    let measuredX: CGFloat
    let measuredY: CGFloat
    let timestamp: Date
}

struct CalibrationResult: Codable {
    let points: [CalibrationPoint]
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotationAngle: CGFloat
    let accuracy: Double  // average error in points
    let calibratedAt: Date

    /// Applies the affine transform (scale + offset, then rotation around
    /// screen center) to a raw gaze point.
    func apply(to point: CGPoint) -> CGPoint {
        // Step 1: Apply the linear correction (from least-squares fit).
        let correctedX = point.x * scaleX + offsetX
        let correctedY = point.y * scaleY + offsetY

        // Step 2: Apply rotation around the centroid of the calibration
        // targets (approximately screen center). Rotating around (0,0)
        // would wildly distort screen-space coordinates.
        guard abs(rotationAngle) > 1e-6 else {
            return CGPoint(x: correctedX, y: correctedY)
        }

        let cosR = cos(rotationAngle)
        let sinR = sin(rotationAngle)

        // Use the calibration points' centroid as rotation center if
        // available, otherwise fall back to the midpoint of the corrected
        // coordinate (a safe approximation of screen center).
        let centerX: CGFloat
        let centerY: CGFloat
        if !points.isEmpty {
            centerX = points.map(\.targetX).reduce(0, +) / CGFloat(points.count)
            centerY = points.map(\.targetY).reduce(0, +) / CGFloat(points.count)
        } else {
            centerX = correctedX
            centerY = correctedY
        }

        let dx = correctedX - centerX
        let dy = correctedY - centerY

        return CGPoint(
            x: dx * cosR - dy * sinR + centerX,
            y: dx * sinR + dy * cosR + centerY
        )
    }

    /// Identity calibration that passes points through unchanged.
    static let identity = CalibrationResult(
        points: [],
        scaleX: 1.0,
        scaleY: 1.0,
        offsetX: 0.0,
        offsetY: 0.0,
        rotationAngle: 0.0,
        accuracy: 0.0,
        calibratedAt: .now
    )

    // MARK: - Persistence

    private static let storageKey = "com.focustracker.calibrationResult"

    /// Persists this calibration result to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: CalibrationResult.storageKey)
    }

    /// Loads the most recent calibration from UserDefaults, if any.
    static func loadSaved() -> CalibrationResult? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let result = try? JSONDecoder().decode(CalibrationResult.self, from: data)
        else { return nil }
        return result
    }

    /// Removes the persisted calibration.
    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
