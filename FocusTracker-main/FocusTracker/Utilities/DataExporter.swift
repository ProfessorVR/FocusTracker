import Foundation
import UIKit
import UniformTypeIdentifiers

/// Handles exporting session data as JSON or CSV for sharing.
final class DataExporter {

    // MARK: - JSON Export

    /// Exports a single session's metrics and frames as pretty-printed JSON.
    ///
    /// The output structure contains `session` metadata, `metrics` (if available),
    /// and the full `frames` array.
    static func exportAsJSON(session: FocusSession) -> Data? {
        var payload: [String: Any] = [
            "id": session.id.uuidString,
            "startTime": ISO8601DateFormatter().string(from: session.startTime),
            "activityType": session.activityType,
            "focusScore": session.focusScore,
            "totalDurationSeconds": session.totalDurationSeconds
        ]

        if let endTime = session.endTime {
            payload["endTime"] = ISO8601DateFormatter().string(from: endTime)
        }

        if let metrics = session.metrics {
            payload["metrics"] = [
                "focusScore": metrics.focusScore,
                "gazeOnScreenPercent": metrics.gazeOnScreenPercent,
                "avgFixationDurationMs": metrics.avgFixationDurationMs,
                "maxFixationDurationMs": metrics.maxFixationDurationMs,
                "numFixations": metrics.numFixations,
                "numOffScreenGlances": metrics.numOffScreenGlances,
                "blinkRatePerMinute": metrics.blinkRatePerMinute,
                "saccadeCount": metrics.saccadeCount,
                "avgSaccadeAmplitude": metrics.avgSaccadeAmplitude,
                "longestFocusStreakSeconds": metrics.longestFocusStreakSeconds,
                "totalDurationSeconds": metrics.totalDurationSeconds
            ]
        }

        let frames = session.frames
        if !frames.isEmpty {
            payload["frames"] = frames.map { frame in
                [
                    "timestamp": frame.timestamp,
                    "gazePointX": Double(frame.gazePointX),
                    "gazePointY": Double(frame.gazePointY),
                    "isOnScreen": frame.isOnScreen,
                    "leftBlinkValue": Double(frame.leftBlinkValue),
                    "rightBlinkValue": Double(frame.rightBlinkValue),
                    "trackingQuality": Double(frame.trackingQuality)
                ] as [String: Any]
            }
        }

        guard JSONSerialization.isValidJSONObject(payload) else { return nil }

        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - CSV Export

    /// Exports the session's gaze frames as CSV data.
    ///
    /// Headers: `timestamp,gazeX,gazeY,isOnScreen,leftBlink,rightBlink,trackingQuality`
    static func exportAsCSV(session: FocusSession) -> Data? {
        var lines: [String] = []
        lines.append("timestamp,gazeX,gazeY,isOnScreen,leftBlink,rightBlink,trackingQuality")

        for frame in session.frames {
            let row = [
                String(format: "%.4f", frame.timestamp),
                String(format: "%.4f", frame.gazePointX),
                String(format: "%.4f", frame.gazePointY),
                frame.isOnScreen ? "1" : "0",
                String(format: "%.3f", frame.leftBlinkValue),
                String(format: "%.3f", frame.rightBlinkValue),
                String(format: "%.3f", frame.trackingQuality)
            ].joined(separator: ",")

            lines.append(row)
        }

        return lines.joined(separator: "\n").data(using: .utf8)
    }

    // MARK: - Batch JSON Export

    /// Exports an array of sessions as a JSON array of summaries.
    ///
    /// Each summary contains: `id`, `date`, `activity`, `score`, `duration`, and `metrics`.
    static func exportAllSessionsAsJSON(sessions: [FocusSession]) -> Data? {
        let isoFormatter = ISO8601DateFormatter()

        let summaries: [[String: Any]] = sessions.map { session in
            var summary: [String: Any] = [
                "id": session.id.uuidString,
                "date": isoFormatter.string(from: session.startTime),
                "activity": session.activityType,
                "score": session.focusScore,
                "duration": session.totalDurationSeconds
            ]

            if let metrics = session.metrics {
                summary["metrics"] = [
                    "gazeOnScreenPercent": metrics.gazeOnScreenPercent,
                    "avgFixationDurationMs": metrics.avgFixationDurationMs,
                    "numFixations": metrics.numFixations,
                    "blinkRatePerMinute": metrics.blinkRatePerMinute,
                    "saccadeCount": metrics.saccadeCount,
                    "longestFocusStreakSeconds": metrics.longestFocusStreakSeconds
                ]
            }

            return summary
        }

        guard JSONSerialization.isValidJSONObject(summaries) else { return nil }

        return try? JSONSerialization.data(
            withJSONObject: summaries,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - Share

    /// Presents a system share sheet for the given data, written to a temporary file.
    ///
    /// - Parameters:
    ///   - data: The file contents to share.
    ///   - filename: The name for the temporary file (e.g., `"session.json"`).
    ///   - viewController: The presenting view controller. Falls back to the key window's
    ///     root view controller if `nil`.
    static func shareData(_ data: Data, filename: String, from viewController: UIViewController?) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)
        } catch {
            print("[DataExporter] Failed to write temporary file: \(error.localizedDescription)")
            return
        }

        let presenter = viewController ?? Self.topViewController()
        guard let presenter else {
            print("[DataExporter] No view controller available to present share sheet.")
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        // iPad requires a source view for the popover.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
        }

        presenter.present(activityVC, animated: true)
    }

    // MARK: - Private Helpers

    /// Walks the view controller hierarchy to find the topmost presented controller.
    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
