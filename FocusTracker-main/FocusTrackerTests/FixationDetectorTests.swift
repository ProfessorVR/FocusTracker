import XCTest
@testable import FocusTracker

final class FixationDetectorTests: XCTestCase {

    private var detector: FixationDetector!

    override func setUp() {
        super.setUp()
        detector = FixationDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Tests

    /// A single gaze point should not produce a finalized fixation, since a fixation
    /// requires sustained gaze over a minimum duration.
    func testNoFixationForSinglePoint() {
        let point = CGPoint(x: 200, y: 300)
        detector.process(point: point, timestamp: 0.0)
        detector.finalize()

        // A single point spanning zero duration cannot meet the 70ms minimum.
        XCTAssertTrue(
            detector.fixations.isEmpty,
            "A single point should not produce a fixation."
        )
    }

    /// Feeding 10 points at approximately the same location over 200ms (well above
    /// the 70ms minimum duration) should produce exactly one fixation.
    func testFixationFromStationaryGaze() {
        let center = CGPoint(x: 200, y: 300)
        let startTime: TimeInterval = 1.0
        let interval: TimeInterval = 0.020  // 50 FPS, 10 points = 200ms span

        for i in 0..<10 {
            // Add tiny sub-threshold jitter to simulate natural micro-movements.
            let jitterX = CGFloat.random(in: -0.5...0.5)
            let jitterY = CGFloat.random(in: -0.5...0.5)
            let point = CGPoint(x: center.x + jitterX, y: center.y + jitterY)
            detector.process(point: point, timestamp: startTime + Double(i) * interval)
        }
        detector.finalize()

        XCTAssertEqual(
            detector.fixations.count, 1,
            "Stationary gaze over 200ms should produce exactly one fixation."
        )

        if let fixation = detector.fixations.first {
            // The center of the fixation should be near the input cluster.
            XCTAssertEqual(fixation.centerX, center.x, accuracy: 5.0)
            XCTAssertEqual(fixation.centerY, center.y, accuracy: 5.0)
        }
    }

    /// Verifies that the fixation's `startTime`, `endTime`, and `duration` fields
    /// are consistent and approximately match the input timestamps.
    func testFixationDurationComputation() {
        let point = CGPoint(x: 100, y: 100)
        let startTime: TimeInterval = 2.0
        let interval: TimeInterval = 0.020
        let pointCount = 15  // 300ms span

        for i in 0..<pointCount {
            detector.process(point: point, timestamp: startTime + Double(i) * interval)
        }
        detector.finalize()

        XCTAssertEqual(detector.fixations.count, 1)

        if let fixation = detector.fixations.first {
            let expectedDuration = Double(pointCount - 1) * interval
            XCTAssertEqual(fixation.duration, expectedDuration, accuracy: 0.005,
                           "Duration should approximately equal the time span of the input points.")
            XCTAssertEqual(fixation.startTime, startTime, accuracy: 0.001)
            XCTAssertEqual(fixation.endTime, startTime + expectedDuration, accuracy: 0.005)
            XCTAssertEqual(fixation.pointCount, pointCount)
        }
    }

    /// A sequence of stationary points followed by a large spatial jump (saccade)
    /// should end the first fixation at the moment of the jump.
    func testSaccadeBreaksFixation() {
        let firstCluster = CGPoint(x: 100, y: 100)
        let jumpTarget = CGPoint(x: 500, y: 500)
        let startTime: TimeInterval = 0.0
        let interval: TimeInterval = 0.020

        // First cluster: 10 points at (100,100) over 200ms.
        for i in 0..<10 {
            detector.process(point: firstCluster, timestamp: startTime + Double(i) * interval)
        }

        // Saccade: jump to (500,500).
        let jumpTime = startTime + 10.0 * interval
        detector.process(point: jumpTarget, timestamp: jumpTime)

        // A few more points at the new location.
        for i in 1...5 {
            detector.process(point: jumpTarget, timestamp: jumpTime + Double(i) * interval)
        }
        detector.finalize()

        XCTAssertGreaterThanOrEqual(
            detector.fixations.count, 1,
            "At least the first cluster should register as a fixation."
        )

        if let first = detector.fixations.first {
            // The first fixation should end before the jump target.
            XCTAssertEqual(first.centerX, firstCluster.x, accuracy: 5.0)
            XCTAssertEqual(first.centerY, firstCluster.y, accuracy: 5.0)
            XCTAssertLessThanOrEqual(first.endTime, jumpTime + 0.001,
                                     "Fixation should end at or before the saccade jump.")
        }
    }

    /// Points spanning only 50ms (below the 70ms minimum duration threshold) should
    /// not produce any fixation.
    func testMinimumDurationFilter() {
        let point = CGPoint(x: 200, y: 200)
        let startTime: TimeInterval = 0.0
        let interval: TimeInterval = 0.010  // 100 FPS
        let pointCount = 5  // 50ms total, below 70ms threshold

        for i in 0..<pointCount {
            detector.process(point: point, timestamp: startTime + Double(i) * interval)
        }
        detector.finalize()

        XCTAssertTrue(
            detector.fixations.isEmpty,
            "A 50ms gaze cluster should be filtered out (below 70ms minimum)."
        )
    }

    /// Two clusters of stationary points separated by a clear saccade should produce
    /// exactly two fixations.
    func testMultipleFixations() {
        let clusterA = CGPoint(x: 100, y: 100)
        let clusterB = CGPoint(x: 400, y: 400)
        let interval: TimeInterval = 0.020
        var time: TimeInterval = 0.0

        // Cluster A: 12 points (240ms).
        for _ in 0..<12 {
            detector.process(point: clusterA, timestamp: time)
            time += interval
        }

        // Saccade jump.
        time += interval

        // Cluster B: 12 points (240ms).
        for _ in 0..<12 {
            detector.process(point: clusterB, timestamp: time)
            time += interval
        }

        detector.finalize()

        XCTAssertEqual(
            detector.fixations.count, 2,
            "Two separated clusters should produce exactly two fixations."
        )

        if detector.fixations.count == 2 {
            XCTAssertEqual(detector.fixations[0].centerX, clusterA.x, accuracy: 5.0)
            XCTAssertEqual(detector.fixations[0].centerY, clusterA.y, accuracy: 5.0)
            XCTAssertEqual(detector.fixations[1].centerX, clusterB.x, accuracy: 5.0)
            XCTAssertEqual(detector.fixations[1].centerY, clusterB.y, accuracy: 5.0)
        }
    }

    /// Calling `reset()` should clear all accumulated fixations and internal state,
    /// so that subsequent processing starts fresh.
    func testResetClearsState() {
        let point = CGPoint(x: 200, y: 200)

        // Build up a fixation.
        for i in 0..<10 {
            detector.process(point: point, timestamp: Double(i) * 0.020)
        }
        detector.finalize()
        XCTAssertFalse(detector.fixations.isEmpty, "Precondition: should have a fixation before reset.")

        // Reset.
        detector.reset()

        XCTAssertTrue(
            detector.fixations.isEmpty,
            "Fixations array should be empty after reset()."
        )

        // Process new data and verify it does not inherit old state.
        let newPoint = CGPoint(x: 500, y: 500)
        for i in 0..<10 {
            detector.process(point: newPoint, timestamp: 10.0 + Double(i) * 0.020)
        }
        detector.finalize()

        XCTAssertEqual(detector.fixations.count, 1)
        if let fixation = detector.fixations.first {
            XCTAssertEqual(fixation.centerX, newPoint.x, accuracy: 5.0,
                           "Post-reset fixation should reflect only new data.")
        }
    }
}
