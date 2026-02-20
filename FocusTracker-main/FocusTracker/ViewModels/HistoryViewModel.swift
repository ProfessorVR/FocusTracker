import SwiftUI
import SwiftData
import Combine

/// Manages session history queries and aggregate statistics via SwiftData.
///
/// Call `loadSessions(modelContext:)` whenever the view appears or after a
/// mutation to refresh the local `sessions` array and recompute derived stats
/// (average score, total count, weekly trend).
@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var sessions: [FocusSession] = []
    @Published var averageScore: Int = 0
    @Published var totalSessions: Int = 0
    @Published var weeklyTrend: [Int] = []

    // MARK: - Data Operations

    /// Fetches all persisted `FocusSession` records sorted by start time
    /// (most recent first) and recomputes aggregate statistics.
    func loadSessions(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        do {
            sessions = try modelContext.fetch(descriptor)
        } catch {
            sessions = []
        }

        computeStats()
    }

    /// Deletes a single session from the persistent store and refreshes
    /// the in-memory list.
    func deleteSession(_ session: FocusSession, modelContext: ModelContext) {
        modelContext.delete(session)
        try? modelContext.save()
        loadSessions(modelContext: modelContext)
    }

    /// Removes every persisted session and resets all statistics.
    func deleteAllSessions(modelContext: ModelContext) {
        for session in sessions {
            modelContext.delete(session)
        }
        try? modelContext.save()
        loadSessions(modelContext: modelContext)
    }

    // MARK: - Statistics

    /// Derives `averageScore`, `totalSessions`, and `weeklyTrend` from the
    /// current `sessions` array.
    private func computeStats() {
        totalSessions = sessions.count

        if sessions.isEmpty {
            averageScore = 0
            weeklyTrend = []
            return
        }

        let scoreSum = sessions.reduce(0) { $0 + $1.focusScore }
        averageScore = scoreSum / sessions.count

        // Weekly trend: the scores of the 7 most recent sessions, ordered
        // oldest-first so index 0 is the earliest of the seven.
        let recentSessions = Array(sessions.prefix(7))
        weeklyTrend = recentSessions.reversed().map(\.focusScore)
    }
}
