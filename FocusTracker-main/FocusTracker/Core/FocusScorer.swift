import Foundation

/// Computes a weighted composite focus score (0-100) from multiple gaze
/// behavior signals.
///
/// The score combines five independently normalized sub-scores, each
/// targeting a different aspect of attentional engagement:
///
/// | Component            | Weight | Peak Condition                     |
/// |----------------------|--------|------------------------------------|
/// | Gaze Stability       | 0.25   | Mean fixation ~300ms               |
/// | Screen Engagement    | 0.20   | 100% on-screen gaze               |
/// | Blink Pattern        | 0.15   | ~17.5 BPM (normal resting rate)    |
/// | Saccade Quality      | 0.20   | Few large saccades, fixation-heavy |
/// | Temporal Consistency | 0.20   | Long unbroken focus streaks        |
///
/// Each sub-score uses a domain-appropriate scoring function (Gaussian peak,
/// linear, or inverse penalty) to map raw metrics to a 0-100 range.
final class FocusScorer {

    // MARK: - Weight Constants

    static let gazeStabilityWeight: Double     = 0.25
    static let screenEngagementWeight: Double  = 0.20
    static let blinkPatternWeight: Double      = 0.15
    static let saccadeQualityWeight: Double    = 0.20
    static let temporalConsistencyWeight: Double = 0.20

    // MARK: - Focus Score

    /// Computes the composite focus score from processed gaze behavior data.
    ///
    /// - Parameters:
    ///   - fixations: All detected fixations in the session.
    ///   - saccades: All detected saccades in the session.
    ///   - blinks: All detected blink events in the session.
    ///   - gazeOnScreenPercent: Fraction of frames where gaze was on screen (0.0-1.0).
    ///   - sessionDuration: Total session duration in seconds.
    ///   - longestFocusStreak: Longest unbroken on-screen focus period in seconds.
    /// - Returns: An integer score clamped to [0, 100].
    func computeScore(
        fixations: [Fixation],
        saccades: [Saccade],
        blinks: [BlinkEvent],
        gazeOnScreenPercent: Double,
        sessionDuration: TimeInterval,
        longestFocusStreak: TimeInterval
    ) -> Int {
        let stability = gazeStabilityScore(fixations: fixations)
        let engagement = screenEngagementScore(gazeOnScreenPercent: gazeOnScreenPercent)
        let blink = blinkPatternScore(blinks: blinks, sessionDuration: sessionDuration)
        let saccade = saccadeQualityScore(saccades: saccades, fixations: fixations)
        let temporal = temporalConsistencyScore(
            longestStreak: longestFocusStreak,
            sessionDuration: sessionDuration
        )

        let weighted =
            stability * Self.gazeStabilityWeight +
            engagement * Self.screenEngagementWeight +
            blink * Self.blinkPatternWeight +
            saccade * Self.saccadeQualityWeight +
            temporal * Self.temporalConsistencyWeight

        return Int(min(100, max(0, weighted.rounded())))
    }

    // MARK: - Session Metrics

    /// Computes the full `SessionMetrics` struct from raw session data.
    ///
    /// This aggregates all individual metrics and uses `computeScore` for
    /// the overall focus score.
    func computeMetrics(
        frames: [GazeFrame],
        fixations: [Fixation],
        saccades: [Saccade],
        blinks: [BlinkEvent],
        sessionDuration: TimeInterval
    ) -> SessionMetrics {

        // Gaze on-screen percentage.
        let onScreenCount = frames.filter(\.isOnScreen).count
        let gazeOnScreenPercent = frames.isEmpty ? 0.0 : Double(onScreenCount) / Double(frames.count)

        // Fixation statistics.
        let fixationDurations = fixations.map { $0.duration * 1000.0 }  // Convert to ms.
        let avgFixationMs = fixationDurations.isEmpty ? 0.0 : fixationDurations.reduce(0, +) / Double(fixationDurations.count)
        let maxFixationMs = fixationDurations.max() ?? 0.0

        // Off-screen glances: count transitions from on-screen to off-screen.
        let offScreenGlances = countOffScreenGlances(frames: frames)

        // Blink rate.
        let blinkRate: Double
        if sessionDuration > 0 {
            blinkRate = Double(blinks.count) / sessionDuration * 60.0
        } else {
            blinkRate = 0
        }

        // Saccade statistics.
        let avgSaccadeAmp = saccades.isEmpty ? 0.0 : saccades.map(\.amplitude).reduce(0, +) / Double(saccades.count)

        // Longest focus streak (consecutive on-screen frames).
        let longestStreak = computeLongestFocusStreak(frames: frames)

        // Composite focus score.
        let focusScore = computeScore(
            fixations: fixations,
            saccades: saccades,
            blinks: blinks,
            gazeOnScreenPercent: gazeOnScreenPercent,
            sessionDuration: sessionDuration,
            longestFocusStreak: longestStreak
        )

        return SessionMetrics(
            focusScore: focusScore,
            gazeOnScreenPercent: gazeOnScreenPercent,
            avgFixationDurationMs: avgFixationMs,
            maxFixationDurationMs: maxFixationMs,
            numFixations: fixations.count,
            numOffScreenGlances: offScreenGlances,
            blinkRatePerMinute: blinkRate,
            saccadeCount: saccades.count,
            avgSaccadeAmplitude: avgSaccadeAmp,
            longestFocusStreakSeconds: longestStreak,
            totalDurationSeconds: sessionDuration
        )
    }

    // MARK: - Sub-Score Functions

    /// Gaze stability score: Gaussian peak at 300ms mean fixation duration.
    ///
    /// Research suggests optimal reading/focus fixations average ~250-350ms.
    /// Very short fixations indicate scanning; very long ones indicate zoning out.
    private func gazeStabilityScore(fixations: [Fixation]) -> Double {
        guard !fixations.isEmpty else { return 0 }

        let meanDurationMs = fixations.map { $0.duration * 1000.0 }.reduce(0, +) / Double(fixations.count)
        return gaussian(value: meanDurationMs, mean: 300.0, sigma: 150.0) * 100.0
    }

    /// Screen engagement score: linear mapping of on-screen gaze percentage.
    private func screenEngagementScore(gazeOnScreenPercent: Double) -> Double {
        return min(1.0, max(0.0, gazeOnScreenPercent)) * 100.0
    }

    /// Blink pattern score: Gaussian peak at 17.5 BPM (normal resting rate).
    ///
    /// The normal blink rate is 15-20 per minute. Significantly lower rates
    /// may indicate screen hypnosis; higher rates may indicate fatigue or
    /// discomfort.
    private func blinkPatternScore(blinks: [BlinkEvent], sessionDuration: TimeInterval) -> Double {
        guard sessionDuration > 0 else { return 50 }

        let bpm = Double(blinks.count) / sessionDuration * 60.0
        return gaussian(value: bpm, mean: 17.5, sigma: 5.0) * 100.0
    }

    /// Saccade quality score: penalizes large saccades, rewards fixation-dominant
    /// behavior.
    ///
    /// A session dominated by fixations with few large saccades indicates
    /// focused attention. Many large saccades indicate visual search or
    /// distraction.
    private func saccadeQualityScore(saccades: [Saccade], fixations: [Fixation]) -> Double {
        guard !saccades.isEmpty || !fixations.isEmpty else { return 50 }

        let largeSaccadeCount = saccades.filter { $0.type == .large }.count
        let totalEvents = saccades.count + fixations.count

        guard totalEvents > 0 else { return 50 }

        // Fraction of events that are large saccades (0 = perfect, 1 = all large saccades).
        let largeFraction = Double(largeSaccadeCount) / Double(totalEvents)

        // Fixation dominance ratio: higher is better.
        let fixationRatio = Double(fixations.count) / Double(totalEvents)

        // Combine: penalize large saccade fraction, reward fixation dominance.
        let penalty = largeFraction * 60.0    // Up to 60 points penalty.
        let bonus = fixationRatio * 40.0      // Up to 40 points bonus.

        return min(100, max(0, 100.0 - penalty + bonus - 40.0))
    }

    /// Temporal consistency score: ratio of longest focus streak to session length.
    ///
    /// A user who maintains focus for a large fraction of the session scores
    /// higher than one with frequent interruptions.
    private func temporalConsistencyScore(longestStreak: TimeInterval, sessionDuration: TimeInterval) -> Double {
        guard sessionDuration > 0 else { return 0 }
        let ratio = longestStreak / sessionDuration
        return min(1.0, max(0.0, ratio)) * 100.0
    }

    // MARK: - Helpers

    /// Gaussian function centered at `mean` with standard deviation `sigma`.
    /// Returns a value in [0, 1] where 1.0 is at the peak.
    private func gaussian(value: Double, mean: Double, sigma: Double) -> Double {
        let exponent = -0.5 * pow((value - mean) / sigma, 2)
        return exp(exponent)
    }

    /// Counts the number of transitions from on-screen to off-screen gaze.
    private func countOffScreenGlances(frames: [GazeFrame]) -> Int {
        var count = 0
        var wasOnScreen = true

        for frame in frames {
            if wasOnScreen && !frame.isOnScreen {
                count += 1
            }
            wasOnScreen = frame.isOnScreen
        }

        return count
    }

    /// Computes the longest consecutive run of on-screen frames, converted
    /// to seconds using frame timestamps.
    private func computeLongestFocusStreak(frames: [GazeFrame]) -> TimeInterval {
        guard frames.count >= 2 else { return 0 }

        var longestStreak: TimeInterval = 0
        var streakStart: TimeInterval?

        for frame in frames {
            if frame.isOnScreen {
                if streakStart == nil {
                    streakStart = frame.timestamp
                }
            } else {
                if let start = streakStart {
                    let streak = frame.timestamp - start
                    longestStreak = max(longestStreak, streak)
                    streakStart = nil
                }
            }
        }

        // Handle case where the session ends while still on-screen.
        if let start = streakStart, let lastFrame = frames.last {
            let streak = lastFrame.timestamp - start
            longestStreak = max(longestStreak, streak)
        }

        return longestStreak
    }
}
