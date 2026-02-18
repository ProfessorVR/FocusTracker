import Foundation

struct SessionMetrics: Codable {
    var focusScore: Int              // 0-100
    var gazeOnScreenPercent: Double
    var avgFixationDurationMs: Double
    var maxFixationDurationMs: Double
    var numFixations: Int
    var numOffScreenGlances: Int
    var blinkRatePerMinute: Double
    var saccadeCount: Int
    var avgSaccadeAmplitude: Double
    var longestFocusStreakSeconds: Double
    var totalDurationSeconds: Double

    var focusLevel: FocusLevel {
        FocusLevel.from(score: focusScore)
    }

    static let empty = SessionMetrics(
        focusScore: 0,
        gazeOnScreenPercent: 0,
        avgFixationDurationMs: 0,
        maxFixationDurationMs: 0,
        numFixations: 0,
        numOffScreenGlances: 0,
        blinkRatePerMinute: 0,
        saccadeCount: 0,
        avgSaccadeAmplitude: 0,
        longestFocusStreakSeconds: 0,
        totalDurationSeconds: 0
    )
}
