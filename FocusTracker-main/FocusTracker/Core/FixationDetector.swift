import Foundation
import Combine

/// A detected fixation: a period during which the gaze remains relatively
/// stable within a small spatial region.
struct Fixation: Identifiable {
    let id: UUID
    let centerX: CGFloat
    let centerY: CGFloat
    let startTime: TimeInterval
    let endTime: TimeInterval
    let pointCount: Int

    /// Duration of the fixation in seconds.
    var duration: TimeInterval {
        endTime - startTime
    }

    /// The spatial center of the fixation as a `CGPoint`.
    var center: CGPoint {
        CGPoint(x: centerX, y: centerY)
    }

    init(
        id: UUID = UUID(),
        centerX: CGFloat,
        centerY: CGFloat,
        startTime: TimeInterval,
        endTime: TimeInterval,
        pointCount: Int
    ) {
        self.id = id
        self.centerX = centerX
        self.centerY = centerY
        self.startTime = startTime
        self.endTime = endTime
        self.pointCount = pointCount
    }
}

/// Fixation detection using the I-VT (Velocity Threshold Identification)
/// algorithm.
///
/// Each incoming gaze sample is classified as belonging to either a fixation
/// or a saccade based on the instantaneous point-to-point velocity. When
/// consecutive below-threshold samples accumulate for at least
/// `minimumDuration`, a fixation is recorded.
///
/// Consecutive fixations whose centers fall within `mergeRadius` are merged
/// into a single, longer fixation.
///
/// ## Reference
/// Salvucci, D. D., & Goldberg, J. H. (2000). Identifying fixations and
/// saccades in eye-tracking protocols. *ETRA '00*.
final class FixationDetector: ObservableObject {

    // MARK: - Configuration

    /// Velocity threshold in points per second.
    ///
    /// Gaze samples with velocity below this threshold are classified as
    /// fixation points. The default of 30 pts/s works well for a phone
    /// held at arm's length at ~326 PPI.
    var velocityThreshold: Double = 30.0

    /// Minimum fixation duration in seconds.
    ///
    /// Clusters of below-threshold samples shorter than this value are
    /// discarded as noise.
    var minimumDuration: TimeInterval = 0.070

    /// Maximum distance (in points) between consecutive fixation centers
    /// to trigger a merge.
    var mergeRadius: CGFloat = 50.0

    // MARK: - Published State

    /// All finalized fixations detected so far.
    @Published var fixations: [Fixation] = []

    /// The fixation currently being accumulated (not yet finalized).
    @Published var currentFixation: Fixation?

    // MARK: - Internal State

    /// Points accumulated for the in-progress fixation candidate.
    private var pendingPoints: [(point: CGPoint, timestamp: TimeInterval)] = []

    /// The most recent sample, used to compute inter-sample velocity.
    private var lastSample: (point: CGPoint, timestamp: TimeInterval)?

    // MARK: - Public API

    /// Processes a new gaze sample.
    ///
    /// - Parameters:
    ///   - point: The smoothed gaze coordinate in screen points.
    ///   - timestamp: The sample timestamp in seconds.
    func process(point: CGPoint, timestamp: TimeInterval) {
        defer { lastSample = (point, timestamp) }

        guard let last = lastSample else {
            // First sample -- begin accumulating.
            pendingPoints.append((point, timestamp))
            return
        }

        let dt = timestamp - last.timestamp
        guard dt > 0 else { return }

        let vel = velocity(from: last.point, to: point, deltaTime: dt)

        if vel < velocityThreshold {
            // Below threshold -- accumulate into the current fixation candidate.
            pendingPoints.append((point, timestamp))
            updateCurrentFixation()
        } else {
            // Above threshold -- finalize any pending fixation, then discard
            // the current sample (it belongs to a saccade).
            finalizeCurrentFixation()
            pendingPoints.removeAll()
            currentFixation = nil
        }
    }

    /// Finalizes any in-progress fixation and returns all detected fixations.
    @discardableResult
    func finalize() -> [Fixation] {
        finalizeCurrentFixation()
        pendingPoints.removeAll()
        currentFixation = nil
        return fixations
    }

    /// Resets all internal state and clears detected fixations.
    func reset() {
        fixations.removeAll()
        pendingPoints.removeAll()
        currentFixation = nil
        lastSample = nil
    }

    // MARK: - Private Helpers

    /// Computes the point-to-point velocity in points per second.
    private func velocity(from p1: CGPoint, to p2: CGPoint, deltaTime: TimeInterval) -> Double {
        let dx = Double(p2.x - p1.x)
        let dy = Double(p2.y - p1.y)
        let distance = sqrt(dx * dx + dy * dy)
        return distance / deltaTime
    }

    /// Updates the `currentFixation` published property from the pending
    /// points buffer (provides a live preview of the in-progress fixation).
    private func updateCurrentFixation() {
        guard pendingPoints.count >= 2 else { return }

        let (center, start, end) = computeClusterStats()
        let fixation = Fixation(
            centerX: center.x,
            centerY: center.y,
            startTime: start,
            endTime: end,
            pointCount: pendingPoints.count
        )
        currentFixation = fixation
    }

    /// Finalizes the current pending fixation if it meets the minimum
    /// duration requirement, then attempts to merge it with the previous
    /// fixation if their centers are close enough.
    private func finalizeCurrentFixation() {
        guard pendingPoints.count >= 2 else { return }

        let (center, start, end) = computeClusterStats()
        let duration = end - start

        guard duration >= minimumDuration else { return }

        let fixation = Fixation(
            centerX: center.x,
            centerY: center.y,
            startTime: start,
            endTime: end,
            pointCount: pendingPoints.count
        )

        // Attempt to merge with the most recent finalized fixation.
        if let last = fixations.last, canMerge(last, fixation) {
            let merged = merge(last, fixation)
            fixations[fixations.count - 1] = merged
        } else {
            fixations.append(fixation)
        }
    }

    /// Computes the centroid and time span of the pending points.
    private func computeClusterStats() -> (center: CGPoint, start: TimeInterval, end: TimeInterval) {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var earliest = TimeInterval.greatestFiniteMagnitude
        var latest: TimeInterval = 0

        for (pt, ts) in pendingPoints {
            sumX += pt.x
            sumY += pt.y
            earliest = min(earliest, ts)
            latest = max(latest, ts)
        }

        let n = CGFloat(pendingPoints.count)
        let center = CGPoint(x: sumX / n, y: sumY / n)
        return (center, earliest, latest)
    }

    /// Determines whether two fixations are close enough to merge.
    private func canMerge(_ a: Fixation, _ b: Fixation) -> Bool {
        let dx = a.centerX - b.centerX
        let dy = a.centerY - b.centerY
        let dist = sqrt(dx * dx + dy * dy)
        return dist <= mergeRadius
    }

    /// Merges two spatially proximate fixations into one.
    private func merge(_ a: Fixation, _ b: Fixation) -> Fixation {
        let totalPoints = a.pointCount + b.pointCount
        let weightA = CGFloat(a.pointCount) / CGFloat(totalPoints)
        let weightB = CGFloat(b.pointCount) / CGFloat(totalPoints)

        return Fixation(
            centerX: a.centerX * weightA + b.centerX * weightB,
            centerY: a.centerY * weightA + b.centerY * weightB,
            startTime: min(a.startTime, b.startTime),
            endTime: max(a.endTime, b.endTime),
            pointCount: totalPoints
        )
    }
}
