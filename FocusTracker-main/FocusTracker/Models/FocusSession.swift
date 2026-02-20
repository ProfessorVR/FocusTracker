import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var activityType: String
    var focusScore: Int
    var totalDurationSeconds: Double
    var metricsJSON: Data?
    var framesJSON: Data?

    init(
        id: UUID = UUID(),
        startTime: Date = .now,
        endTime: Date? = nil,
        activityType: String = "other",
        focusScore: Int = 0,
        totalDurationSeconds: Double = 0,
        metricsJSON: Data? = nil,
        framesJSON: Data? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.activityType = activityType
        self.focusScore = focusScore
        self.totalDurationSeconds = totalDurationSeconds
        self.metricsJSON = metricsJSON
        self.framesJSON = framesJSON
    }

    // MARK: - Metrics

    var metrics: SessionMetrics? {
        guard let data = metricsJSON else { return nil }
        return try? JSONDecoder().decode(SessionMetrics.self, from: data)
    }

    func setMetrics(_ metrics: SessionMetrics) {
        metricsJSON = try? JSONEncoder().encode(metrics)
    }

    // MARK: - Frames

    var frames: [GazeFrame] {
        guard let data = framesJSON else { return [] }
        return (try? JSONDecoder().decode([GazeFrame].self, from: data)) ?? []
    }

    func setFrames(_ frames: [GazeFrame]) {
        framesJSON = try? JSONEncoder().encode(frames)
    }

    // MARK: - Computed Properties

    var activity: ActivityType {
        ActivityType(rawValue: activityType) ?? .other
    }

    var focusLevel: FocusLevel {
        FocusLevel.from(score: focusScore)
    }

    var formattedDuration: String {
        let totalSeconds = Int(totalDurationSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}
