import SwiftUI
import Combine

/// Drives the multi-step calibration flow: instructions, per-point sample
/// collection, result computation, and success/failure reporting.
///
/// Starts the gaze tracker, subscribes to gaze frames, feeds them to the
/// calibration engine, and auto-advances through the 9 target points.
@MainActor
final class CalibrationViewModel: ObservableObject {

    // MARK: - Calibration Phase

    enum CalibrationPhase: Equatable {
        case instructions
        case collecting
        case processing
        case complete
        case failed
    }

    // MARK: - Published State

    @Published var phase: CalibrationPhase = .instructions
    @Published var currentPointIndex: Int = 0
    @Published var progress: Double = 0
    @Published var accuracy: Double = 0
    @Published var targetPosition: CGPoint = .zero

    /// Total number of calibration points (exposed for UI progress display).
    var totalPoints: Int { engine.targetPoints.count }

    // MARK: - Private Dependencies

    private let engine = CalibrationEngine()
    private let gazeTracker: GazeTracker
    private var cancellables = Set<AnyCancellable>()
    private var sampleCount = 0

    /// Samples per point — use the engine's value so they stay in sync.
    private var samplesPerPoint: Int { engine.samplesPerPoint }

    /// Captured screen size for use in the gaze subscription closure.
    private var currentScreenSize: CGSize = .zero

    // MARK: - Initialisation

    /// - Parameter gazeTracker: An existing tracker instance. Defaults to a
    ///   new `GazeTracker()` when none is injected.
    init(gazeTracker: GazeTracker = GazeTracker()) {
        self.gazeTracker = gazeTracker
    }

    // MARK: - Calibration Lifecycle

    /// Begins the calibration sequence. Resets all state, starts the gaze
    /// tracker, subscribes to gaze frames, and transitions to `.collecting`.
    func startCalibration(screenSize: CGSize) {
        sampleCount = 0
        currentPointIndex = 0
        progress = 0
        accuracy = 0
        currentScreenSize = screenSize

        engine.startCalibration()

        updateTargetPosition(screenSize: screenSize)

        phase = .collecting

        // Start the gaze tracker and subscribe to incoming frames.
        gazeTracker.startTracking()

        gazeTracker.gazeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.handleGazeFrame(frame)
            }
            .store(in: &cancellables)
    }

    /// Resets all calibration state back to the initial instruction screen.
    func reset() {
        gazeTracker.stopTracking()
        cancellables.removeAll()
        sampleCount = 0
        currentPointIndex = 0
        progress = 0
        accuracy = 0
        targetPosition = .zero
        phase = .instructions
    }

    // MARK: - Private: Frame Handling

    /// Processes each incoming gaze frame during calibration.
    private func handleGazeFrame(_ frame: GazeFrame) {
        guard phase == .collecting else { return }

        // Feed the gaze sample to the engine.
        engine.addSample(measuredPoint: frame.screenPoint)
        sampleCount += 1

        // Update progress bar for the current point.
        progress = min(Double(sampleCount) / Double(samplesPerPoint), 1.0)

        // When enough samples are collected for this point, advance.
        if sampleCount >= samplesPerPoint {
            advanceOrFinish()
        }
    }

    /// Advances to the next calibration point, or finalizes if all are done.
    private func advanceOrFinish() {
        let hasMore = engine.advanceToNextPoint()

        if hasMore {
            // Move to the next dot.
            currentPointIndex += 1
            sampleCount = 0
            progress = 0
            updateTargetPosition(screenSize: currentScreenSize)
        } else {
            // All 9 points collected — stop tracking and compute result.
            gazeTracker.stopTracking()
            cancellables.removeAll()
            finishCalibration()
        }
    }

    /// Computes the calibration result from all collected samples.
    private func finishCalibration() {
        phase = .processing

        let result = engine.computeCalibration()

        // result.accuracy is average pixel error. Convert to a 0-1 score
        // where 0 px error = 100% and >= 100 px error = 0%.
        let maxAcceptableError: Double = 100.0
        accuracy = max(0, min(1.0, 1.0 - result.accuracy / maxAcceptableError))

        // Apply the calibration to the gaze tracker for future sessions.
        gazeTracker.setCalibration(result)

        phase = .complete
    }

    // MARK: - Helpers

    /// Converts the engine's normalised target point (0-1) to screen
    /// coordinates.
    private func updateTargetPosition(screenSize: CGSize) {
        guard currentPointIndex < engine.targetPoints.count else { return }

        let target = engine.targetPoints[currentPointIndex]
        targetPosition = CGPoint(
            x: target.x * screenSize.width,
            y: target.y * screenSize.height
        )
    }
}
