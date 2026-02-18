import Foundation
import Combine

/// A detected blink event derived from ARKit eye blink blend shapes.
struct BlinkEvent: Identifiable {
    let id: UUID
    let timestamp: TimeInterval
    let duration: TimeInterval
    let isDoubleBlink: Bool

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        duration: TimeInterval,
        isDoubleBlink: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.isDoubleBlink = isDoubleBlink
    }
}

/// Detects blink events from ARKit's `eyeBlinkLeft` and `eyeBlinkRight`
/// blend shape coefficients.
///
/// A blink is registered when **both** eyes simultaneously exceed the
/// `blinkThreshold` for a duration within the valid range
/// (`minBlinkDuration`...`maxBlinkDuration`). Blinks longer than
/// `maxBlinkDuration` are ignored as potential drowsiness or tracking
/// artifacts.
///
/// Double-blinks (two blinks within 500ms) are flagged and can be used
/// as intentional input gestures.
final class BlinkDetector: ObservableObject {

    // MARK: - Configuration

    /// Blend shape value above which an eye is considered closed.
    /// ARKit blend shapes range from 0.0 (open) to 1.0 (fully closed).
    var blinkThreshold: Float = 0.5

    /// Minimum blink duration in seconds.
    /// Blinks shorter than this are likely noise.
    var minBlinkDuration: TimeInterval = 0.05

    /// Maximum blink duration in seconds.
    /// Events longer than this are likely drowsiness or tracking loss.
    var maxBlinkDuration: TimeInterval = 0.4

    /// Maximum interval between two blinks to classify them as a double-blink.
    var doubleBlinkInterval: TimeInterval = 0.5

    // MARK: - Published State

    /// All validated blink events detected so far.
    @Published var blinks: [BlinkEvent] = []

    /// Rolling blink rate computed over the last 60 seconds.
    @Published var blinksPerMinute: Double = 0

    // MARK: - Internal State

    /// Whether the user is currently in a blink (both eyes closed).
    private var isBlinking = false

    /// Timestamp at which the current blink began.
    private var blinkStartTime: TimeInterval?

    /// Timestamps of recent blinks within the rolling window, used for BPM.
    private var rollingWindow: [TimeInterval] = []

    /// Duration of the rolling window for BPM computation (60 seconds).
    private let windowDuration: TimeInterval = 60.0

    // MARK: - Public API

    /// Processes a pair of eye blink blend shape values.
    ///
    /// - Parameters:
    ///   - leftBlink: The `eyeBlinkLeft` blend shape value (0.0-1.0).
    ///   - rightBlink: The `eyeBlinkRight` blend shape value (0.0-1.0).
    ///   - timestamp: The frame timestamp in seconds.
    ///
    /// A blink is detected when both values exceed `blinkThreshold`
    /// simultaneously. The blink event is finalized when either eye
    /// opens again.
    func process(leftBlink: Float, rightBlink: Float, timestamp: TimeInterval) {
        let bothClosed = leftBlink >= blinkThreshold && rightBlink >= blinkThreshold

        if bothClosed && !isBlinking {
            // Blink onset.
            isBlinking = true
            blinkStartTime = timestamp
        } else if !bothClosed && isBlinking {
            // Blink offset: validate and record.
            isBlinking = false

            guard let startTime = blinkStartTime else { return }
            let duration = timestamp - startTime

            // Validate duration.
            guard duration >= minBlinkDuration && duration <= maxBlinkDuration else {
                blinkStartTime = nil
                return
            }

            // Check for double-blink by comparing with the most recent blink.
            let isDoubleBlink: Bool
            if let lastBlink = blinks.last {
                let gap = startTime - (lastBlink.timestamp + lastBlink.duration)
                isDoubleBlink = gap <= doubleBlinkInterval && gap >= 0
            } else {
                isDoubleBlink = false
            }

            let event = BlinkEvent(
                timestamp: startTime,
                duration: duration,
                isDoubleBlink: isDoubleBlink
            )
            blinks.append(event)

            // Update rolling window and BPM.
            rollingWindow.append(startTime)
            pruneRollingWindow(currentTime: timestamp)
            computeBPM(currentTime: timestamp)

            blinkStartTime = nil
        }
    }

    /// Resets all internal state and clears detected blinks.
    func reset() {
        blinks.removeAll()
        rollingWindow.removeAll()
        blinksPerMinute = 0
        isBlinking = false
        blinkStartTime = nil
    }

    // MARK: - Private Helpers

    /// Removes entries from the rolling window that are older than
    /// `windowDuration` seconds.
    private func pruneRollingWindow(currentTime: TimeInterval) {
        let cutoff = currentTime - windowDuration
        rollingWindow.removeAll { $0 < cutoff }
    }

    /// Computes the blink rate in blinks per minute from the rolling window.
    private func computeBPM(currentTime: TimeInterval) {
        guard let earliest = rollingWindow.first else {
            blinksPerMinute = 0
            return
        }

        let elapsed = currentTime - earliest
        if elapsed > 0 {
            // Scale the count within the observed window to a per-minute rate.
            // Use max(elapsed, 10) to avoid inflated rates during the first
            // few seconds of tracking.
            let effectiveWindow = max(elapsed, 10.0)
            blinksPerMinute = Double(rollingWindow.count) / effectiveWindow * 60.0
        } else {
            blinksPerMinute = 0
        }
    }
}
