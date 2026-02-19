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

    /// Applies the affine transform (scale, rotation, offset) to a raw gaze point.
    func apply(to point: CGPoint) -> CGPoint {
        let cosR = cos(rotationAngle)
        let sinR = sin(rotationAngle)

        // Scale
        let scaledX = point.x * scaleX
        let scaledY = point.y * scaleY

        // Rotate
        let rotatedX = scaledX * cosR - scaledY * sinR
        let rotatedY = scaledX * sinR + scaledY * cosR

        // Translate
        return CGPoint(
            x: rotatedX + offsetX,
            y: rotatedY + offsetY
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
