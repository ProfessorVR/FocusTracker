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

    /// Second-order polynomial coefficients for X correction.
    /// [a0, a1, a2, a3, a4, a5] where:
    ///   correctedX = a0 + a1*x + a2*y + a3*x*y + a4*x^2 + a5*y^2
    /// When nil, falls back to the affine transform (scaleX, offsetX, rotationAngle).
    let polyCoeffsX: [Double]?

    /// Second-order polynomial coefficients for Y correction.
    let polyCoeffsY: [Double]?

    /// Applies the calibration transform to a raw gaze point.
    ///
    /// Uses polynomial regression if coefficients are available, otherwise
    /// falls back to the legacy affine transform (scale + rotation + offset).
    func apply(to point: CGPoint) -> CGPoint {
        if let polyX = polyCoeffsX, let polyY = polyCoeffsY,
           polyX.count >= 3, polyY.count >= 3 {
            return applyPolynomial(to: point, polyX: polyX, polyY: polyY)
        } else {
            return applyAffine(to: point)
        }
    }

    /// Polynomial correction: target = a0 + a1*x + a2*y + a3*x*y + a4*x^2 + a5*y^2
    private func applyPolynomial(to point: CGPoint, polyX: [Double], polyY: [Double]) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)

        let features = [1.0, x, y, x * y, x * x, y * y]

        var correctedX = 0.0
        var correctedY = 0.0
        for i in 0..<min(features.count, polyX.count) {
            correctedX += polyX[i] * features[i]
        }
        for i in 0..<min(features.count, polyY.count) {
            correctedY += polyY[i] * features[i]
        }

        return CGPoint(x: correctedX, y: correctedY)
    }

    /// Legacy affine transform (scale, rotation, offset).
    private func applyAffine(to point: CGPoint) -> CGPoint {
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
        calibratedAt: .now,
        polyCoeffsX: nil,
        polyCoeffsY: nil
    )

    // MARK: - Backward-compatible initializer (legacy 5-point affine)

    init(
        points: [CalibrationPoint],
        scaleX: CGFloat,
        scaleY: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        rotationAngle: CGFloat,
        accuracy: Double,
        calibratedAt: Date,
        polyCoeffsX: [Double]? = nil,
        polyCoeffsY: [Double]? = nil
    ) {
        self.points = points
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotationAngle = rotationAngle
        self.accuracy = accuracy
        self.calibratedAt = calibratedAt
        self.polyCoeffsX = polyCoeffsX
        self.polyCoeffsY = polyCoeffsY
    }
}
