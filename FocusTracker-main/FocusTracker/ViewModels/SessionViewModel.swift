import SwiftUI
import Combine
import SwiftData
import ARKit

/// Central orchestrator for an active eye-tracking session.
///
/// Subscribes to raw gaze frames from `GazeTracker`, pipes each frame through
/// screen mapping, smoothing, and the three event detectors (fixation, saccade,
/// blink), then periodically recomputes a running focus score. When the session
/// stops, it finalises all detectors, computes full metrics via `FocusScorer`,
/// and persists a `FocusSession` to SwiftData.
@MainActor
final class SessionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var trackingState: TrackingState = .notStarted
    @Published var currentGazePoint: CGPoint = .zero
    @Published var isOnScreen: Bool = true
    @Published var elapsedTime: TimeInterval = 0
    @Published var runningScore: Int = 0
    @Published var currentActivity: ActivityType = .other

    // MARK: - Private Dependencies

    private let gazeTracker = GazeTracker()
    private let screenMapper = ScreenMapper()
    private let smoother = GazeSmoothing()
    private let fixationDetector = FixationDetector()
    private let saccadeDetector = SaccadeDetector()
    private let blinkDetector = BlinkDetector()
    private let focusScorer = FocusScorer()

    // MARK: - Private State

    private var frames: [GazeFrame] = []
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var timer: Timer?
    private var onScreenFrameCount = 0
    private var longestFocusStreak: TimeInterval = 0
    private var currentStreakStart: TimeInterval?

    // MARK: - Session Lifecycle

    /// Resets all detectors, starts the gaze tracker, subscribes to incoming
    /// frames, and kicks off the elapsed-time timer.
    func startSession(activity: ActivityType) {
        currentActivity = activity
        frames.removeAll()
        onScreenFrameCount = 0
        longestFocusStreak = 0
        currentStreakStart = nil
        elapsedTime = 0
        runningScore = 0

        smoother.reset()
        fixationDetector.reset()
        saccadeDetector.reset()
        blinkDetector.reset()

        sessionStartTime = Date()
        trackingState = .tracking

        gazeTracker.startTracking()

        gazeTracker.gazeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.processFrame(frame)
            }
            .store(in: &cancellables)

        startTimer()
    }

    /// Stops tracking, finalises detectors, computes session metrics, persists
    /// a `FocusSession` to the supplied model context, and returns it.
    @discardableResult
    func stopSession(modelContext: ModelContext) -> FocusSession? {
        gazeTracker.stopTracking()
        cancellables.removeAll()
        stopTimer()

        trackingState = .stopped

        fixationDetector.finalize()

        guard let startTime = sessionStartTime else { return nil }
        let endTime = Date()

        let gazeOnScreenPercent: Double = frames.isEmpty
            ? 0
            : Double(onScreenFrameCount) / Double(frames.count)

        let metrics = focusScorer.computeMetrics(
            frames: frames,
            fixations: fixationDetector.fixations,
            saccades: saccadeDetector.saccades,
            blinks: blinkDetector.blinks,
            sessionDuration: endTime.timeIntervalSince(startTime)
        )

        let score = focusScorer.computeScore(
            fixations: fixationDetector.fixations,
            saccades: saccadeDetector.saccades,
            blinks: blinkDetector.blinks,
            gazeOnScreenPercent: gazeOnScreenPercent, // ✅ Already 0.0 - 1.0
            sessionDuration: endTime.timeIntervalSince(startTime),
            longestFocusStreak: longestFocusStreak
        )

        let session = FocusSession(
            id: UUID(),
            startTime: startTime,
            endTime: endTime,
            activityType: currentActivity.rawValue,
            focusScore: score,
            totalDurationSeconds: endTime.timeIntervalSince(startTime)
        )
        session.setMetrics(metrics)
        session.setFrames(frames)

        modelContext.insert(session)
        try? modelContext.save()

        return session
    }

    /// Pauses tracking without discarding accumulated data.
    func pauseSession() {
        gazeTracker.stopTracking()
        cancellables.removeAll()
        stopTimer()
        trackingState = .paused
    }

    /// Resumes a previously paused session.
    func resumeSession() {
        trackingState = .tracking
        gazeTracker.startTracking()

        gazeTracker.gazeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.processFrame(frame)
            }
            .store(in: &cancellables)

        startTimer()
    }

    // MARK: - Frame Processing

    private func processFrame(_ frame: GazeFrame) {
        let mapped = screenMapper.map(
            lookAtPoint: frame.lookAtPoint,
            faceTransform: matrix_identity_float4x4 // ✅ Standard global constant for a 4x4 identity matrix
        )

        let smoothed = smoother.smooth(
            point: mapped.point,
            timestamp: frame.timestamp
        )

        currentGazePoint = smoothed
        isOnScreen = mapped.isOnScreen

        fixationDetector.process(point: smoothed, timestamp: frame.timestamp)
        saccadeDetector.process(point: smoothed, timestamp: frame.timestamp)
        blinkDetector.process(
            leftBlink: frame.leftBlinkValue,
            rightBlink: frame.rightBlinkValue,
            timestamp: frame.timestamp
        )

        if mapped.isOnScreen {
            onScreenFrameCount += 1
            if currentStreakStart == nil {
                currentStreakStart = frame.timestamp
            }
        } else {
            if let streakStart = currentStreakStart {
                let streak = frame.timestamp - streakStart
                longestFocusStreak = max(longestFocusStreak, streak)
            }
            currentStreakStart = nil
        }

        frames.append(frame)

        if frames.count % 30 == 0 {
            recomputeRunningScore()
        }
    }

    // MARK: - Running Score

    private func recomputeRunningScore() {
        let gazeOnScreenPercent: Double = frames.isEmpty
            ? 0
            : Double(onScreenFrameCount) / Double(frames.count)

        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0

        let score = focusScorer.computeScore(
            fixations: fixationDetector.fixations,
            saccades: saccadeDetector.saccades,
            blinks: blinkDetector.blinks,
            gazeOnScreenPercent: gazeOnScreenPercent, // ✅ Already 0.0 - 1.0
            sessionDuration: duration,
            longestFocusStreak: longestFocusStreak
        )
        runningScore = score
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.sessionStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
