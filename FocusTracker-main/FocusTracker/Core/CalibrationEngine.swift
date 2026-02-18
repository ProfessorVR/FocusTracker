import Foundation
import Combine
import UIKit

/// A 9-point calibration system that computes a polynomial correction transform
/// to improve gaze-to-screen mapping accuracy.
///
/// ## Calibration Flow
///
/// 1. Call `startCalibration()` to begin.
/// 2. Display the target point for `targetPoints[currentPointIndex]` on screen.
/// 3. Feed measured gaze samples via `addSample(measuredPoint:)`.
/// 4. After `samplesPerPoint` samples are collected, call `advanceToNextPoint()`.
/// 5. Repeat steps 2-4 for each target point.
/// 6. When `advanceToNextPoint()` returns `false`, call `computeCalibration()`
///    to produce a `CalibrationResult`.
///
/// ## Target Points
///
/// Nine points are used in normalized (0-1) coordinates:
/// - Center (0.5, 0.5)
/// - Top-left (0.15, 0.15), Top-center (0.5, 0.15), Top-right (0.85, 0.15)
/// - Middle-left (0.15, 0.5), Middle-right (0.85, 0.5)
/// - Bottom-left (0.15, 0.85), Bottom-center (0.5, 0.85), Bottom-right (0.85, 0.85)
///
/// These are converted to screen coordinates by multiplying by screen size
/// at render time.
///
/// ## Polynomial Regression
///
/// Instead of a simple affine transform, this engine fits a second-order
/// polynomial (quadratic) to capture non-linear distortions in the gaze
/// mapping. The model is:
///
///     correctedX = a0 + a1*x + a2*y + a3*x*y + a4*x^2 + a5*y^2
///     correctedY = b0 + b1*x + b2*y + b3*x*y + b4*x^2 + b5*y^2
///
/// This captures barrel/pincushion distortion, asymmetric scaling, and
/// cross-axis coupling that a simple affine transform cannot model.
final class CalibrationEngine: ObservableObject {

    // MARK: - Published State

    /// Index of the current target point being calibrated (0-8).
    @Published var currentPointIndex = 0

    /// Whether a calibration session is in progress.
    @Published var isCalibrating = false

    /// The computed calibration result, available after `computeCalibration()`.
    @Published var calibrationResult: CalibrationResult?

    /// Progress within the current point (0.0 to 1.0).
    var currentPointProgress: Double {
        guard samplesPerPoint > 0 else { return 0 }
        let collected = collectedData[safe: currentPointIndex]?.count ?? 0
        return min(1.0, Double(collected) / Double(samplesPerPoint))
    }

    // MARK: - Configuration

    /// The nine target points in normalized (0-1) screen coordinates.
    /// A 3x3 grid provides better coverage for polynomial fitting than 5 points.
    let targetPoints: [CGPoint] = [
        CGPoint(x: 0.5,  y: 0.5),   // Center (first — allows user to settle)
        CGPoint(x: 0.15, y: 0.15),  // Top-left
        CGPoint(x: 0.5,  y: 0.15),  // Top-center
        CGPoint(x: 0.85, y: 0.15),  // Top-right
        CGPoint(x: 0.15, y: 0.5),   // Middle-left
        CGPoint(x: 0.85, y: 0.5),   // Middle-right
        CGPoint(x: 0.15, y: 0.85),  // Bottom-left
        CGPoint(x: 0.5,  y: 0.85),  // Bottom-center
        CGPoint(x: 0.85, y: 0.85),  // Bottom-right
    ]

    /// Number of gaze samples to collect per target point.
    /// At 30 FPS this equals approximately 2 seconds of data.
    let samplesPerPoint = 60

    // MARK: - Internal State

    /// Collected measured gaze points for each target, indexed by target point.
    private var collectedData: [[CGPoint]]

    // MARK: - Initialization

    init() {
        collectedData = Array(repeating: [], count: 9)
    }

    // MARK: - Public API

    /// Resets state and begins a new calibration session.
    func startCalibration() {
        currentPointIndex = 0
        isCalibrating = true
        calibrationResult = nil
        collectedData = Array(repeating: [], count: targetPoints.count)
    }

    /// Adds a measured gaze sample for the current target point.
    ///
    /// Samples beyond `samplesPerPoint` for the current point are silently
    /// discarded.
    ///
    /// - Parameter measuredPoint: The raw gaze coordinate in screen points.
    func addSample(measuredPoint: CGPoint) {
        guard isCalibrating,
              currentPointIndex < targetPoints.count,
              collectedData[currentPointIndex].count < samplesPerPoint else {
            return
        }
        collectedData[currentPointIndex].append(measuredPoint)
    }

    /// Advances to the next target point.
    ///
    /// - Returns: `true` if there are more points to calibrate, `false` if
    ///   all points have been collected and calibration is ready to compute.
    @discardableResult
    func advanceToNextPoint() -> Bool {
        guard isCalibrating else { return false }

        let nextIndex = currentPointIndex + 1
        if nextIndex < targetPoints.count {
            currentPointIndex = nextIndex
            return true
        } else {
            return false
        }
    }

    /// Computes the calibration transform from all collected data.
    ///
    /// Fits a second-order polynomial regression to map measured gaze points
    /// to the known target positions, capturing non-linear distortions.
    ///
    /// - Returns: A `CalibrationResult` with the computed transform and
    ///   accuracy metric.
    @discardableResult
    func computeCalibration() -> CalibrationResult {
        isCalibrating = false

        // Step 1: Compute the average measured point for each target.
        var measuredAverages: [CGPoint] = []
        var targetScreenPoints: [CGPoint] = []

        let screenSize = UIScreen.main.bounds.size

        for i in 0..<targetPoints.count {
            let samples = collectedData[i]
            guard !samples.isEmpty else { continue }

            let avgX = samples.map(\.x).reduce(0, +) / CGFloat(samples.count)
            let avgY = samples.map(\.y).reduce(0, +) / CGFloat(samples.count)
            measuredAverages.append(CGPoint(x: avgX, y: avgY))

            let target = targetPoints[i]
            targetScreenPoints.append(CGPoint(
                x: target.x * screenSize.width,
                y: target.y * screenSize.height
            ))
        }

        guard measuredAverages.count >= 3 else {
            // Not enough data — return identity calibration.
            let identity = CalibrationResult.identity
            calibrationResult = identity
            return identity
        }

        // Step 2: Fit polynomial regression for X and Y independently.
        let polyX = fitPolynomial(
            measured: measuredAverages,
            targetValues: targetScreenPoints.map(\.x)
        )
        let polyY = fitPolynomial(
            measured: measuredAverages,
            targetValues: targetScreenPoints.map(\.y)
        )

        // Step 3: Compute accuracy as average error after polynomial correction.
        let accuracy = computePolynomialAccuracy(
            measured: measuredAverages,
            targets: targetScreenPoints,
            polyX: polyX,
            polyY: polyY
        )

        // Step 4: Build calibration point records.
        var calibrationPoints: [CalibrationPoint] = []
        for i in 0..<measuredAverages.count {
            calibrationPoints.append(CalibrationPoint(
                targetX: targetScreenPoints[i].x,
                targetY: targetScreenPoints[i].y,
                measuredX: measuredAverages[i].x,
                measuredY: measuredAverages[i].y,
                timestamp: Date()
            ))
        }

        // Step 5: Store polynomial coefficients in CalibrationResult.
        // For backward compatibility, we encode the polynomial as:
        //   scaleX/scaleY = linear coefficients (a1, b2)
        //   offsetX/offsetY = intercepts (a0, b0)
        //   rotationAngle = 0 (not used in polynomial mode)
        // Plus the full polynomial coefficients in the new polyCoeffsX/Y fields.
        let result = CalibrationResult(
            points: calibrationPoints,
            scaleX: CGFloat(polyX[1]),   // Linear X coefficient
            scaleY: CGFloat(polyY[2]),   // Linear Y coefficient
            offsetX: CGFloat(polyX[0]),  // X intercept
            offsetY: CGFloat(polyY[0]),  // Y intercept
            rotationAngle: 0,
            accuracy: accuracy,
            calibratedAt: Date(),
            polyCoeffsX: polyX,
            polyCoeffsY: polyY
        )

        calibrationResult = result
        return result
    }

    /// Resets the engine to its initial state, discarding any collected data
    /// and computed results.
    func reset() {
        currentPointIndex = 0
        isCalibrating = false
        calibrationResult = nil
        collectedData = Array(repeating: [], count: targetPoints.count)
    }

    // MARK: - Private: Polynomial Regression

    /// Fits a second-order polynomial: target = a0 + a1*x + a2*y + a3*x*y + a4*x^2 + a5*y^2
    ///
    /// Uses least-squares normal equations (A^T A)^{-1} A^T b.
    ///
    /// - Parameters:
    ///   - measured: The averaged measured gaze points.
    ///   - targetValues: The target values (either X or Y component).
    /// - Returns: Array of 6 polynomial coefficients [a0, a1, a2, a3, a4, a5].
    private func fitPolynomial(measured: [CGPoint], targetValues: [CGFloat]) -> [Double] {
        let n = measured.count

        // If we have fewer points than coefficients, fall back to linear.
        if n < 6 {
            return fitLinearFallback(measured: measured, targetValues: targetValues)
        }

        // Build the design matrix A where each row is [1, x, y, x*y, x^2, y^2].
        let numCoeffs = 6
        var A = [[Double]](repeating: [Double](repeating: 0, count: numCoeffs), count: n)
        var b = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let x = Double(measured[i].x)
            let y = Double(measured[i].y)
            A[i] = [1.0, x, y, x * y, x * x, y * y]
            b[i] = Double(targetValues[i])
        }

        // Solve via normal equations: (A^T A) coeffs = A^T b
        return solveNormalEquations(A: A, b: b, numCoeffs: numCoeffs)
    }

    /// Linear fallback when insufficient points for full polynomial.
    private func fitLinearFallback(measured: [CGPoint], targetValues: [CGFloat]) -> [Double] {
        let n = measured.count
        guard n >= 2 else { return [0, 1, 0, 0, 0, 0] }  // Identity-ish

        let numCoeffs = 3  // a0 + a1*x + a2*y
        var A = [[Double]](repeating: [Double](repeating: 0, count: numCoeffs), count: n)
        var b = [Double](repeating: 0, count: n)

        for i in 0..<n {
            A[i] = [1.0, Double(measured[i].x), Double(measured[i].y)]
            b[i] = Double(targetValues[i])
        }

        let coeffs = solveNormalEquations(A: A, b: b, numCoeffs: numCoeffs)
        // Pad to 6 coefficients with zeros for the quadratic terms.
        return coeffs + [0, 0, 0]
    }

    /// Solves the normal equations (A^T A) x = A^T b using Gaussian elimination.
    private func solveNormalEquations(A: [[Double]], b: [Double], numCoeffs: Int) -> [Double] {
        let n = A.count

        // Compute A^T A (numCoeffs x numCoeffs).
        var ATA = [[Double]](repeating: [Double](repeating: 0, count: numCoeffs), count: numCoeffs)
        for i in 0..<numCoeffs {
            for j in 0..<numCoeffs {
                var sum = 0.0
                for k in 0..<n {
                    sum += A[k][i] * A[k][j]
                }
                ATA[i][j] = sum
            }
        }

        // Compute A^T b (numCoeffs x 1).
        var ATb = [Double](repeating: 0, count: numCoeffs)
        for i in 0..<numCoeffs {
            var sum = 0.0
            for k in 0..<n {
                sum += A[k][i] * b[k]
            }
            ATb[i] = sum
        }

        // Solve via Gaussian elimination with partial pivoting.
        return gaussianElimination(matrix: ATA, rhs: ATb)
    }

    /// Gaussian elimination with partial pivoting.
    private func gaussianElimination(matrix: [[Double]], rhs: [Double]) -> [Double] {
        let n = matrix.count
        var aug = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)

        // Build augmented matrix.
        for i in 0..<n {
            for j in 0..<n {
                aug[i][j] = matrix[i][j]
            }
            aug[i][n] = rhs[i]
        }

        // Forward elimination with partial pivoting.
        for col in 0..<n {
            // Find pivot.
            var maxVal = abs(aug[col][col])
            var maxRow = col
            for row in (col + 1)..<n {
                if abs(aug[row][col]) > maxVal {
                    maxVal = abs(aug[row][col])
                    maxRow = row
                }
            }

            // Swap rows.
            if maxRow != col {
                aug.swapAt(col, maxRow)
            }

            // Check for singular matrix.
            guard abs(aug[col][col]) > 1e-12 else {
                // Singular — return identity-like coefficients.
                var result = [Double](repeating: 0, count: n)
                if n > 1 { result[1] = 1.0 }  // Scale = 1
                return result
            }

            // Eliminate below.
            for row in (col + 1)..<n {
                let factor = aug[row][col] / aug[col][col]
                for j in col..<(n + 1) {
                    aug[row][j] -= factor * aug[col][j]
                }
            }
        }

        // Back substitution.
        var result = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = aug[i][n]
            for j in (i + 1)..<n {
                sum -= aug[i][j] * result[j]
            }
            result[i] = sum / aug[i][i]
        }

        return result
    }

    // MARK: - Private: Accuracy

    /// Computes average Euclidean error after polynomial correction.
    private func computePolynomialAccuracy(
        measured: [CGPoint],
        targets: [CGPoint],
        polyX: [Double],
        polyY: [Double]
    ) -> Double {
        guard !measured.isEmpty else { return 0 }

        var totalError = 0.0
        for i in 0..<measured.count {
            let corrected = applyPolynomial(point: measured[i], polyX: polyX, polyY: polyY)
            let dx = Double(corrected.x - targets[i].x)
            let dy = Double(corrected.y - targets[i].y)
            totalError += sqrt(dx * dx + dy * dy)
        }

        return totalError / Double(measured.count)
    }

    /// Applies polynomial coefficients to a point.
    private func applyPolynomial(point: CGPoint, polyX: [Double], polyY: [Double]) -> CGPoint {
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
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
