import Foundation
import Combine
import UIKit

/// A 5-point calibration system that computes an affine correction transform
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
/// Five points are used in normalized (0-1) coordinates:
/// - Center (0.5, 0.5)
/// - Top-left (0.15, 0.15)
/// - Top-right (0.85, 0.15)
/// - Bottom-left (0.15, 0.85)
/// - Bottom-right (0.85, 0.85)
///
/// These are converted to screen coordinates by multiplying by screen size
/// at render time.
final class CalibrationEngine: ObservableObject {

    // MARK: - Published State

    /// Index of the current target point being calibrated (0-4).
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

    /// The five target points in normalized (0-1) screen coordinates.
    let targetPoints: [CGPoint] = [
        CGPoint(x: 0.5,  y: 0.5),   // Center
        CGPoint(x: 0.15, y: 0.15),  // Top-left
        CGPoint(x: 0.85, y: 0.15),  // Top-right
        CGPoint(x: 0.15, y: 0.85),  // Bottom-left
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
        collectedData = Array(repeating: [], count: 5)
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
    /// Uses a least-squares approach to find the affine parameters (scaleX,
    /// scaleY, offsetX, offsetY) that best map measured gaze points to the
    /// known target positions.
    ///
    /// - Returns: A `CalibrationResult` with the computed transform and
    ///   accuracy metric.
    @discardableResult
    func computeCalibration() -> CalibrationResult {
        isCalibrating = false

        // Step 1: Compute the average measured point for each target.
        var measuredAverages: [CGPoint] = []
        var targetScreenPoints: [CGPoint] = []

        // We need screen size to convert normalized targets to screen coordinates.
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

        guard measuredAverages.count >= 2 else {
            // Not enough data -- return identity calibration.
            let identity = CalibrationResult.identity
            calibrationResult = identity
            return identity
        }

        // Step 2: Compute the affine transform via least squares.
        //
        // We solve for parameters that map measured -> target:
        //   targetX = scaleX * measuredX + offsetX
        //   targetY = scaleY * measuredY + offsetY
        //
        // This is a simplified affine model (no rotation in the least-squares
        // fit). Rotation is computed separately from the residuals.
        let (scaleX, offsetX) = leastSquaresLinear(
            xs: measuredAverages.map(\.x),
            ys: targetScreenPoints.map(\.x)
        )
        let (scaleY, offsetY) = leastSquaresLinear(
            xs: measuredAverages.map(\.y),
            ys: targetScreenPoints.map(\.y)
        )

        // Step 3: Compute rotation angle from the residual pattern.
        //
        // After applying scale and offset, any systematic angular error is
        // estimated by computing the average angular deviation of residuals.
        let rotationAngle = computeRotation(
            measured: measuredAverages,
            targets: targetScreenPoints,
            scaleX: scaleX, scaleY: scaleY,
            offsetX: offsetX, offsetY: offsetY
        )

        // Step 4: Build CalibrationPoint records (needed for correct rotation
        // center in the accuracy computation).
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

        // Step 5: Compute accuracy as average Euclidean error after transform.
        let accuracy = computeAccuracy(
            measured: measuredAverages,
            targets: targetScreenPoints,
            calibrationPoints: calibrationPoints,
            scaleX: scaleX, scaleY: scaleY,
            offsetX: offsetX, offsetY: offsetY,
            rotation: rotationAngle
        )

        let result = CalibrationResult(
            points: calibrationPoints,
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: offsetX,
            offsetY: offsetY,
            rotationAngle: rotationAngle,
            accuracy: accuracy,
            calibratedAt: Date()
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

    // MARK: - Private: Least Squares

    /// Solves a 1D least-squares linear fit: y = a * x + b.
    ///
    /// Returns (a, b) where `a` is the scale and `b` is the offset.
    private func leastSquaresLinear(xs: [CGFloat], ys: [CGFloat]) -> (CGFloat, CGFloat) {
        let n = CGFloat(xs.count)
        guard n >= 2 else { return (1.0, 0.0) }

        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXX = zip(xs, xs).map(*).reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-10 else { return (1.0, 0.0) }

        let a = (n * sumXY - sumX * sumY) / denominator
        let b = (sumY - a * sumX) / n

        return (a, b)
    }

    // MARK: - Private: Rotation Estimation

    /// Estimates a small rotation angle from the residual error pattern.
    ///
    /// After applying scale and offset, if there is a consistent angular
    /// misalignment, the residuals will show a rotational pattern. We compute
    /// the average angle of the error vectors relative to the origin.
    private func computeRotation(
        measured: [CGPoint],
        targets: [CGPoint],
        scaleX: CGFloat, scaleY: CGFloat,
        offsetX: CGFloat, offsetY: CGFloat
    ) -> CGFloat {
        guard measured.count >= 3 else { return 0 }

        var totalAngle: CGFloat = 0
        var count: CGFloat = 0

        let centerX = targets.map(\.x).reduce(0, +) / CGFloat(targets.count)
        let centerY = targets.map(\.y).reduce(0, +) / CGFloat(targets.count)

        for i in 0..<measured.count {
            let transformedX = measured[i].x * scaleX + offsetX
            let transformedY = measured[i].y * scaleY + offsetY

            // Vectors from center to target and to transformed point.
            let targetVecX = targets[i].x - centerX
            let targetVecY = targets[i].y - centerY
            let transVecX = transformedX - centerX
            let transVecY = transformedY - centerY

            let targetAngle = atan2(targetVecY, targetVecX)
            let transAngle = atan2(transVecY, transVecX)

            var angleDiff = targetAngle - transAngle
            // Normalize to [-pi, pi].
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }

            totalAngle += angleDiff
            count += 1
        }

        return count > 0 ? totalAngle / count : 0
    }

    // MARK: - Private: Accuracy

    /// Computes the average Euclidean error after applying the full transform
    /// (scale + offset + rotation around target centroid) to the measured points.
    private func computeAccuracy(
        measured: [CGPoint],
        targets: [CGPoint],
        calibrationPoints: [CalibrationPoint],
        scaleX: CGFloat, scaleY: CGFloat,
        offsetX: CGFloat, offsetY: CGFloat,
        rotation: CGFloat
    ) -> Double {
        guard !measured.isEmpty else { return 0 }

        let tempResult = CalibrationResult(
            points: calibrationPoints,
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: offsetX,
            offsetY: offsetY,
            rotationAngle: rotation,
            accuracy: 0,
            calibratedAt: Date()
        )

        var totalError: Double = 0
        for i in 0..<measured.count {
            let corrected = tempResult.apply(to: measured[i])
            let dx = Double(corrected.x - targets[i].x)
            let dy = Double(corrected.y - targets[i].y)
            totalError += sqrt(dx * dx + dy * dy)
        }

        return totalError / Double(measured.count)
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
