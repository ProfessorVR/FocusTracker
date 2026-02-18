import Foundation
import simd
import SwiftUI

// MARK: - simd_float4x4

extension simd_float4x4 {

    /// Extracts Euler angles (pitch, yaw, roll) from a 4x4 transformation matrix.
    ///
    /// Uses the ZYX rotation convention:
    /// - **x** (pitch): rotation around the horizontal axis (nodding)
    /// - **y** (yaw): rotation around the vertical axis (shaking head)
    /// - **z** (roll): rotation around the depth axis (tilting head)
    var eulerAngles: simd_float3 {
        let sy = sqrt(columns.0.x * columns.0.x + columns.1.x * columns.1.x)
        let singular = sy < 1e-6

        let pitch: Float
        let yaw: Float
        let roll: Float

        if !singular {
            pitch = atan2(columns.2.y, columns.2.z)
            yaw   = atan2(-columns.2.x, sy)
            roll  = atan2(columns.1.x, columns.0.x)
        } else {
            pitch = atan2(-columns.1.z, columns.1.y)
            yaw   = atan2(-columns.2.x, sy)
            roll  = 0
        }

        return simd_float3(pitch, yaw, roll)
    }
}

// MARK: - Date

extension Date {

    /// A short human-readable format, e.g. "Feb 14, 2:30 PM".
    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }

    /// A day-level format, e.g. "Mon, Feb 14".
    var dayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: self)
    }
}

// MARK: - TimeInterval

extension TimeInterval {

    /// Formats the interval as `MM:SS`, e.g. `"05:23"`.
    var formattedMMSS: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Formats the interval as a readable duration, e.g. `"5m 23s"`.
    ///
    /// Includes hours when the interval exceeds 60 minutes (e.g. `"1h 5m 23s"`).
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - CGPoint

extension CGPoint {

    /// Euclidean distance from this point to another.
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Int (Focus Score Color)

extension Int {

    /// Maps a focus score (0-100) to a semantic color.
    ///
    /// - 70-100: green (deep focus)
    /// - 40-69: yellow (moderate)
    /// - 20-39: orange (low)
    /// - 0-19: red (distracted)
    var focusColor: Color {
        switch self {
        case 70...100:
            return .green
        case 40...69:
            return .yellow
        case 20...39:
            return .orange
        default:
            return .red
        }
    }
}
