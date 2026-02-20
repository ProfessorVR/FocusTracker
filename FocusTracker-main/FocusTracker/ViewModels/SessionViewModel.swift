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

    /// Whether a calibration is active. When true, heavier smoothing is used
    /// because calibration scale factors amplify per-frame noise.
    private var hasCalibration = false

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

        // Load persisted calibration (if any) and apply to both the
        // geometric ScreenMapper and CNN prediction paths.
        if let cal = CalibrationResult.loadSaved() {
            gazeTracker.setCalibration(cal)
            screenMapper.setCalibration(cal)
            hasCalibration = true
            // Calibration scale factors amplify per-frame noise. Use heavier
            // smoothing (alpha 0.15 vs default 0.3) to stabilize the signal.
            smoother.alpha = 0.15
        } else {
            hasCalibration = false
            smoother.alpha = 0.3
        }

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

        trackingState = .notStarted

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
        // GazeTracker.buildGazeFrame() already maps gaze to screen coordinates
        // via the geometric or CNN path. Trust that computed result directly.
        let gazePoint = frame.screenPoint

        let smoothed = smoother.smooth(
            point: gazePoint,
            timestamp: frame.timestamp
        )

        currentGazePoint = smoothed

        // Determine on-screen status from the SMOOTHED point rather than the
        // raw per-frame value. Calibration amplifies per-frame noise, so the
        // raw isOnScreen flag flickers constantly. The smoothed signal is
        // stable enough for reliable on-screen detection.
        let screenSize = UIScreen.main.bounds.size
        let margin: CGFloat = hasCalibration ? 80 : 40
        let onScreen = smoothed.x >= -margin
            && smoothed.x <= screenSize.width + margin
            && smoothed.y >= -margin
            && smoothed.y <= screenSize.height + margin
        isOnScreen = onScreen

        fixationDetector.process(point: smoothed, timestamp: frame.timestamp)
        saccadeDetector.process(point: smoothed, timestamp: frame.timestamp)
        blinkDetector.process(
            leftBlink: frame.leftBlinkValue,
            rightBlink: frame.rightBlinkValue,
            timestamp: frame.timestamp
        )

        if onScreen {
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
