import Foundation
import SwiftUI

// MARK: - ActivityType

enum ActivityType: String, Codable, CaseIterable {
    case studying
    case reading
    case working
    case coding
    case other
}

// MARK: - FocusLevel

enum FocusLevel: String, Codable {
    case deep       // 70-100
    case moderate   // 40-69
    case low        // 20-39
    case distracted // 0-19

    static func from(score: Int) -> FocusLevel {
        switch score {
        case 70...100:
            return .deep
        case 40...69:
            return .moderate
        case 20...39:
            return .low
        default:
            return .distracted
        }
    }

    var color: Color {
        switch self {
        case .deep:
            return .green
        case .moderate:
            return .yellow
        case .low:
            return .orange
        case .distracted:
            return .red
        }
    }
}

// MARK: - TrackingState

enum TrackingState: String {
    case notStarted
    case tracking
    case paused
    case stopped
}
