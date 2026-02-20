import XCTest
@testable import FocusTracker

final class FocusScorerTests: XCTestCase {

    private var scorer: FocusScorer!

    override func setUp() {
        super.setUp()
        scorer = FocusScorer()
    }

    override func tearDown() {
        scorer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates an array of fixations with uniform duration and spacing.
    private func makeFixations(
        count: Int,
        durationSeconds: Double,
        spacingSeconds: Double = 0.05,
        centerX: CGFloat = 200,
        centerY: CGFloat = 300
    ) -> [Fixation] {
        var fixations: [Fixation] = []
        var time: TimeInterval = 0.0

        for _ in 0..<count {
            let fixation = Fixation(
                centerX: centerX,
                centerY: centerY,
                startTime: time,
                endTime: time + durationSeconds,
                duration: durationSeconds,
                pointCount: max(1, Int(durationSeconds / 0.033))
            )
            fixations.append(fixation)
            time += durationSeconds + spacingSeconds
        }

        return fixations
    }

    /// Creates saccades of a given amplitude.
    private func makeSaccades(
        count: Int,
        amplitude: Double = 5.0,
        durationSeconds: Double = 0.04
    ) -> [Saccade] {
        var saccades: [Saccade] = []
        var time: TimeInterval = 0.0

        for _ in 0..<count {
            let saccade = Saccade(
                startPoint: CGPoint(x: 100, y: 100),
                endPoint: CGPoint(x: 100 + amplitude, y: 100),
                amplitude: amplitude,
                duration: durationSeconds,
                direction: 0.0,
                type: amplitude > 10 ? .large : .small,
                startTime: time
            )
            saccades.append(saccade)
            time += durationSeconds + 0.2
        }

        return saccades
    }

    /// Creates blink events at a given rate.
    private func makeBlinks(count: Int, intervalSeconds: Double = 3.5) -> [BlinkEvent] {
        (0..<count).map { i in
            BlinkEvent(
                timestamp: Double(i) * intervalSeconds,
                duration: 0.15,
                isDoubleBlink: false
            )
        }
    }

    // MARK: - Tests

    /// A session with long fixations (~300ms), high on-screen percentage, normal blink
    /// rate (~17 BPM), and few small saccades should score above 80.
    func testPerfectFocusSession() {
        let sessionDuration: TimeInterval = 120.0  // 2 minutes

        // ~40 fixations of 300ms each, closely spaced.
        let fixations = makeFixations(count: 40, durationSeconds: 0.300, spacingSeconds: 0.05)

        // Few small saccades (normal reading pattern).
        let saccades = makeSaccades(count: 10, amplitude: 3.0)

        // Normal blink rate: ~17 per minute over 2 minutes = ~34 blinks.
        let blinks = makeBlinks(count: 34, intervalSeconds: 120.0 / 34.0)

        let score = scorer.computeScore(
            fixations: fixations,
            saccades: saccades,
            blinks: blinks,
            gazeOnScreenPercent: 0.95,
            sessionDuration: sessionDuration,
            longestFocusStreak: 90.0
        )

        XCTAssertGreaterThan(score, 80,
                             "A focused session with long fixations and high on-screen time should score > 80. Got \(score).")
    }

    /// A session with very short fixations, lots of off-screen gaze, many large saccades,
    /// and abnormal blink rate should score below 30.
    func testDistractedSession() {
        let sessionDuration: TimeInterval = 120.0

        // Short fixations (~80ms), indicating scanning rather than focus.
        let fixations = makeFixations(count: 60, durationSeconds: 0.080, spacingSeconds: 0.03)

        // Many large saccades (erratic eye movement).
        let saccades = makeSaccades(count: 50, amplitude: 15.0, durationSeconds: 0.03)

        // High blink rate (stress/fatigue indicator).
        let blinks = makeBlinks(count: 80, intervalSeconds: 120.0 / 80.0)

        let score = scorer.computeScore(
            fixations: fixations,
            saccades: saccades,
            blinks: blinks,
            gazeOnScreenPercent: 0.30,
            sessionDuration: sessionDuration,
            longestFocusStreak: 8.0
        )

        XCTAssertLessThan(score, 30,
                          "A distracted session with short fixations and lots of off-screen should score < 30. Got \(score).")
    }

    /// A session with mixed signals should produce a moderate score between 40 and 70.
    func testModerateFocusSession() {
        let sessionDuration: TimeInterval = 120.0

        // Medium fixation durations (~180ms).
        let fixations = makeFixations(count: 30, durationSeconds: 0.180, spacingSeconds: 0.06)

        // Moderate saccade count with medium amplitudes.
        let saccades = makeSaccades(count: 20, amplitude: 8.0)

        // Normal blink rate.
        let blinks = makeBlinks(count: 36, intervalSeconds: 120.0 / 36.0)

        let score = scorer.computeScore(
            fixations: fixations,
            saccades: saccades,
            blinks: blinks,
            gazeOnScreenPercent: 0.65,
            sessionDuration: sessionDuration,
            longestFocusStreak: 40.0
        )

        XCTAssertGreaterThanOrEqual(score, 40,
                                    "Moderate session should score >= 40. Got \(score).")
        XCTAssertLessThanOrEqual(score, 70,
                                 "Moderate session should score <= 70. Got \(score).")
    }

    /// A session with zero fixations, zero saccades, and zero blinks should produce
    /// a score of 0 (or very close to it).
    func testEmptySession() {
        let score = scorer.computeScore(
            fixations: [],
            saccades: [],
            blinks: [],
            gazeOnScreenPercent: 0.0,
            sessionDuration: 0.0,
            longestFocusStreak: 0.0
        )

        XCTAssertLessThanOrEqual(score, 5,
                                 "An empty session should produce a score near 0. Got \(score).")
    }

    /// No matter how extreme the input values, the score should always be clamped
    /// to the 0-100 range.
    func testScoreClampedTo0_100() {
        // Extreme positive inputs.
        let highScore = scorer.computeScore(
            fixations: makeFixations(count: 1000, durationSeconds: 2.0),
            saccades: [],
            blinks: makeBlinks(count: 20),
            gazeOnScreenPercent: 1.0,
            sessionDuration: 3600.0,
            longestFocusStreak: 3600.0
        )

        XCTAssertGreaterThanOrEqual(highScore, 0,
                                    "Score must not be negative. Got \(highScore).")
        XCTAssertLessThanOrEqual(highScore, 100,
                                 "Score must not exceed 100. Got \(highScore).")

        // Extreme negative-signal inputs.
        let lowScore = scorer.computeScore(
            fixations: makeFixations(count: 500, durationSeconds: 0.030),
            saccades: makeSaccades(count: 500, amplitude: 50.0),
            blinks: makeBlinks(count: 500, intervalSeconds: 0.1),
            gazeOnScreenPercent: 0.0,
            sessionDuration: 60.0,
            longestFocusStreak: 0.0
        )

        XCTAssertGreaterThanOrEqual(lowScore, 0,
                                    "Score must not be negative. Got \(lowScore).")
        XCTAssertLessThanOrEqual(lowScore, 100,
                                 "Score must not exceed 100. Got \(lowScore).")
    }
}
