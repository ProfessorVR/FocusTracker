import Foundation

/// Temporal noise filter using exponential moving average (EMA).
///
/// Raw gaze coordinates from ARKit jitter at high frequency. This filter
/// applies an EMA independently to X and Y to produce a stable gaze signal
/// while preserving responsiveness to intentional eye movements.
///
/// The filter automatically resets when a gap exceeding `maxGapDuration` is
/// detected between consecutive frames, preventing stale state from dragging
/// the smoothed position after tracking interruptions.
final class GazeSmoothing {

    // MARK: - Properties

    /// Smoothing factor in the range (0, 1].
    ///
    /// - `alpha = 1.0`: no smoothing (output = raw input)
    /// - `alpha -> 0`: heavy smoothing (output changes very slowly)
    ///
    /// A value of 0.3 provides a good balance between stability and
    /// responsiveness at 30 FPS.
    var alpha: Double

    /// Maximum allowable gap (in seconds) between consecutive samples.
    /// If the gap exceeds this threshold the filter resets, treating the
    /// next sample as the first in a new sequence.
    var maxGapDuration: TimeInterval = 0.1

    // MARK: - Internal State

    private var smoothedX: Double?
    private var smoothedY: Double?
    private var lastTimestamp: TimeInterval?

    // MARK: - Initialization

    /// Creates a gaze smoothing filter.
    ///
    /// - Parameter alpha: The EMA smoothing factor. Defaults to 0.3.
    init(alpha: Double = 0.3) {
        self.alpha = max(0.01, min(1.0, alpha))
    }

    // MARK: - Public API

    /// Applies EMA smoothing to a raw gaze point.
    ///
    /// - Parameters:
    ///   - point: The raw (unsmoothed) gaze coordinate.
    ///   - timestamp: The frame timestamp in seconds.
    /// - Returns: The smoothed gaze coordinate.
    ///
    /// On the first call (or after a reset / large gap), the input point is
    /// returned unchanged and used to initialize the internal state.
    func smooth(point: CGPoint, timestamp: TimeInterval) -> CGPoint {

        // Detect frame drops or tracking interruptions.
        if let lastTime = lastTimestamp, (timestamp - lastTime) > maxGapDuration {
            resetInternal()
        }

        lastTimestamp = timestamp

        // First sample after initialization or reset.
        guard let prevX = smoothedX, let prevY = smoothedY else {
            smoothedX = Double(point.x)
            smoothedY = Double(point.y)
            return point
        }

        // EMA: smoothed = alpha * new + (1 - alpha) * previous
        let newX = alpha * Double(point.x) + (1.0 - alpha) * prevX
        let newY = alpha * Double(point.y) + (1.0 - alpha) * prevY

        smoothedX = newX
        smoothedY = newY

        return CGPoint(x: newX, y: newY)
    }

    /// Resets the filter state.
    ///
    /// The next call to `smooth(point:timestamp:)` will treat its input as
    /// the first sample in a new sequence.
    func reset() {
        resetInternal()
    }

    // MARK: - Private

    private func resetInternal() {
        smoothedX = nil
        smoothedY = nil
        lastTimestamp = nil
    }
}
