import Foundation
import Combine

/// Classification of saccade magnitude based on angular amplitude.
enum SaccadeType: String {
    /// Sub-degree eye movements, often involuntary.
    case micro  // < 1 degree

    /// Typical reading or scanning saccades.
    case small  // 1-5 degrees

    /// Large gaze shifts, often indicating distraction or context switching.
    case large  // > 5 degrees

    static func classify(amplitudeDegrees: Double) -> SaccadeType {
        if amplitudeDegrees < 1.0 {
            return .micro
        } else if amplitudeDegrees <= 5.0 {
            return .small
        } else {
            return .large
        }
    }
}

/// A detected saccade: a rapid, ballistic eye movement between two fixation
/// points.
struct Saccade: Identifiable {
    let id: UUID
    let startPoint: CGPoint
    let endPoint: CGPoint

    /// Angular amplitude in degrees.
    let amplitude: Double

    /// Duration of the saccade in seconds.
    let duration: TimeInterval

    /// Direction of the saccade in radians (0 = rightward, pi/2 = upward).
    let direction: Double

    /// Classification based on amplitude.
    let type: SaccadeType

    /// Timestamp of the saccade onset.
    let startTime: TimeInterval

    init(
        id: UUID = UUID(),
        startPoint: CGPoint,
        endPoint: CGPoint,
        amplitude: Double,
        duration: TimeInterval,
        direction: Double,
        type: SaccadeType,
        startTime: TimeInterval
    ) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.amplitude = amplitude
        self.duration = duration
        self.direction = direction
        self.type = type
        self.startTime = startTime
    }
}

/// Detects rapid eye movements (saccades) using a velocity threshold method.
///
/// A saccade begins when the gaze velocity exceeds `velocityThreshold` and
/// ends when the velocity drops back below the threshold. The amplitude,
/// direction, and type are computed from the start and end points.
///
/// ## Velocity-to-Degrees Conversion
///
/// Screen pixel distances are converted to approximate visual degrees using
/// the device's PPI and an assumed viewing distance. This allows the velocity
/// threshold and amplitude classification to use perceptually meaningful units.
final class SaccadeDetector: ObservableObject {

    // MARK: - Configuration

    /// Velocity threshold in approximate degrees per second.
    ///
    /// Eye movements faster than this are classified as saccadic. Typical
    /// saccade peak velocities range from 100-700 deg/s.
    var velocityThreshold: Double = 100.0

    // MARK: - Published State

    /// All detected saccades in the current session.
    @Published var saccades: [Saccade] = []

    // MARK: - Internal State

    /// Whether we are currently inside a saccade event.
    private var inSaccade = false

    /// The gaze position at saccade onset.
    private var saccadeStartPoint: CGPoint?

    /// The timestamp at saccade onset.
    private var saccadeStartTime: TimeInterval?

    /// The most recent gaze sample.
    private var lastPoint: CGPoint?

    /// The most recent sample timestamp.
    private var lastTimestamp: TimeInterval?

    // MARK: - Constants

    /// Approximate pixels per inch for the target device.
    /// 326 PPI is standard for iPhone Retina displays (non-Plus/Max models).
    private let devicePPI: Double = 326.0

    /// Assumed viewing distance in inches (~14 inches = 35 cm).
    private let viewingDistanceInches: Double = 14.0

    // MARK: - Public API

    /// Processes a new gaze sample for saccade detection.
    ///
    /// - Parameters:
    ///   - point: The smoothed gaze coordinate in screen points.
    ///   - timestamp: The sample timestamp in seconds.
    func process(point: CGPoint, timestamp: TimeInterval) {
        defer {
            lastPoint = point
            lastTimestamp = timestamp
        }

        guard let prevPoint = lastPoint, let prevTime = lastTimestamp else {
            return
        }

        let dt = timestamp - prevTime
        guard dt > 0 else { return }

        // Compute velocity in degrees per second.
        let dx = Double(point.x - prevPoint.x)
        let dy = Double(point.y - prevPoint.y)
        let pixelDistance = sqrt(dx * dx + dy * dy)
        let degreesDistance = pixelsToDegrees(pixelDistance)
        let velocityDegPerSec = degreesDistance / dt

        if !inSaccade && velocityDegPerSec > velocityThreshold {
            // Saccade onset.
            inSaccade = true
            saccadeStartPoint = prevPoint
            saccadeStartTime = prevTime
        } else if inSaccade && velocityDegPerSec <= velocityThreshold {
            // Saccade offset: finalize the saccade.
            if let startPt = saccadeStartPoint, let startTs = saccadeStartTime {
                let endPoint = prevPoint
                let duration = prevTime - startTs

                let totalDx = Double(endPoint.x - startPt.x)
                let totalDy = Double(endPoint.y - startPt.y)
                let totalPixels = sqrt(totalDx * totalDx + totalDy * totalDy)
                let amplitude = pixelsToDegrees(totalPixels)
                let direction = atan2(-totalDy, totalDx)  // Negate Y because screen Y is inverted.

                let saccade = Saccade(
                    startPoint: startPt,
                    endPoint: endPoint,
                    amplitude: amplitude,
                    duration: duration,
                    direction: direction,
                    type: SaccadeType.classify(amplitudeDegrees: amplitude),
                    startTime: startTs
                )
                saccades.append(saccade)
            }

            inSaccade = false
            saccadeStartPoint = nil
            saccadeStartTime = nil
        }
    }

    /// Resets all internal state and clears detected saccades.
    func reset() {
        saccades.removeAll()
        inSaccade = false
        saccadeStartPoint = nil
        saccadeStartTime = nil
        lastPoint = nil
        lastTimestamp = nil
    }

    // MARK: - Private Helpers

    /// Converts a pixel distance to approximate visual degrees.
    ///
    /// Uses the small-angle approximation:
    ///   degrees = atan(pixelDistance / PPI / viewingDistance) * (180 / pi)
    ///
    /// For typical screen distances this approximation is accurate to within 1%.
    ///
    /// - Parameter pixels: Distance in screen points (at Retina scale, 1 pt = 2-3 px,
    ///   but UIKit works in points so we treat 1 point ~ 1/PPI inches for simplicity).
    /// - Returns: Approximate angular displacement in degrees.
    private func pixelsToDegrees(_ pixels: Double) -> Double {
        let distanceInches = pixels / devicePPI
        let radians = atan(distanceInches / viewingDistanceInches)
        return radians * (180.0 / .pi)
    }
}
