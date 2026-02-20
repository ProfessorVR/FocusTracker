import SwiftUI
import SwiftData
import Combine

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .onAppear {
                viewModel.loadSessions(modelContext: modelContext)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Sessions Yet")
                .font(.title3.bold())

            Text("Start your first focus session!\nYour history and trends will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            // Header stats
            Section {
                HStack(spacing: 24) {
                    statItem(
                        label: "Total Sessions",
                        value: "\(viewModel.totalSessions)"
                    )

                    Divider()
                        .frame(height: 32)

                    statItem(
                        label: "Average Score",
                        value: String(format: "%.0f%%", viewModel.averageScore)
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            // Trend chart
            if viewModel.sessions.count >= 2 {
                Section("Recent Trend") {
                    trendChart
                        .frame(height: 100)
                        .padding(.vertical, 8)
                }
            }

            // Session rows
            Section("Sessions") {
                ForEach(viewModel.sessions) { session in
                    NavigationLink {
                        DashboardView(session: session)
                    } label: {
                        sessionRow(session)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let session = viewModel.sessions[index]
                        viewModel.deleteSession(session, modelContext: modelContext)
                    }
                }
            }
        }
    }

    // MARK: - Stat Item

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        let recentSessions = Array(viewModel.sessions.prefix(7).reversed())

        return Canvas { context, size in
            guard recentSessions.count >= 2 else { return }

            let padding: CGFloat = 16
            let chartWidth = size.width - padding * 2
            let chartHeight = size.height - padding * 2
            let stepX = chartWidth / CGFloat(recentSessions.count - 1)

            // Build points
            var points: [CGPoint] = []
            for (index, session) in recentSessions.enumerated() {
                let x = padding + CGFloat(index) * stepX
                let normalizedScore = CGFloat(session.focusScore) / 100.0
                let y = padding + chartHeight * (1.0 - normalizedScore)
                points.append(CGPoint(x: x, y: y))
            }

            // Draw connecting line
            if points.count >= 2 {
                var linePath = Path()
                linePath.move(to: points[0])
                for i in 1..<points.count {
                    linePath.addLine(to: points[i])
                }
                context.stroke(
                    linePath,
                    with: .color(.blue.opacity(0.5)),
                    lineWidth: 2
                )
            }

            // Draw dots
            for (index, point) in points.enumerated() {
                let session = recentSessions[index]
                let dotRect = CGRect(
                    x: point.x - 5,
                    y: point.y - 5,
                    width: 10,
                    height: 10
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(session.focusLevel.color)
                )
            }
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ session: FocusSession) -> some View {
        HStack(spacing: 12) {
            // Activity icon
            Image(systemName: activityIcon(for: session.activity))
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            // Date and activity
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate(session.startTime))
                    .font(.subheadline.weight(.medium))

                Text("\(session.activity.rawValue.capitalized) - \(session.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Score badge
            ZStack {
                Circle()
                    .fill(session.focusLevel.color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Text("\(Int(session.focusScore))")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(session.focusLevel.color)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private func activityIcon(for activity: ActivityType) -> String {
        switch activity {
        case .studying: return "book"
        case .reading: return "text.book.closed"
        case .working: return "briefcase"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .other: return "circle.grid.2x2"
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: FocusSession.self, inMemory: true)
}
