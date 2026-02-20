import SwiftUI

struct DashboardView: View {
    let session: FocusSession

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Score circle
                scoreCircle
                    .padding(.top, 8)

                // Focus level label
                Text(session.focusLevel.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(session.focusLevel.color)

                // Session info
                sessionInfoSection

                Divider()
                    .padding(.horizontal)

                // Metrics grid
                if let metrics = session.metrics {
                    metricsGrid(metrics)
                } else {
                    Text("No detailed metrics available")
                        .foregroundStyle(.secondary)
                        .padding()
                }

                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Session Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Score Circle

    private var scoreCircle: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 12)
                .frame(width: 160, height: 160)

            Circle()
                .trim(from: 0, to: CGFloat(session.focusScore) / 100.0)
                .stroke(
                    session.focusLevel.color,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("\(Int(session.focusScore))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(session.focusLevel.color)

                Text("Focus Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Session Info

    private var sessionInfoSection: some View {
        HStack(spacing: 24) {
            sessionInfoItem(
                icon: "clock",
                label: "Duration",
                value: session.formattedDuration
            )

            sessionInfoItem(
                icon: activityIcon(for: session.activity),
                label: "Activity",
                value: session.activity.rawValue.capitalized
            )

            sessionInfoItem(
                icon: "calendar",
                label: "Date",
                value: formattedDate(session.startTime)
            )
        }
        .padding(.horizontal)
    }

    private func sessionInfoItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)

            Text(value)
                .font(.subheadline.weight(.medium))

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metrics Grid

    private func metricsGrid(_ metrics: SessionMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Metrics")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                metricCard(
                    icon: "eye",
                    label: "Gaze on Screen",
                    value: String(format: "%.0f%%", metrics.gazeOnScreenPercent)
                )

                metricCard(
                    icon: "scope",
                    label: "Avg Fixation",
                    value: String(format: "%.0fms", metrics.avgFixationDurationMs)
                )

                metricCard(
                    icon: "number",
                    label: "Fixation Count",
                    value: "\(metrics.numFixations)"
                )

                metricCard(
                    icon: "eye.slash",
                    label: "Blink Rate",
                    value: String(format: "%.1f/min", metrics.blinkRatePerMinute)
                )

                metricCard(
                    icon: "arrow.triangle.swap",
                    label: "Saccade Count",
                    value: "\(metrics.saccadeCount)"
                )

                metricCard(
                    icon: "flame",
                    label: "Longest Streak",
                    value: String(format: "%.0fs", metrics.longestFocusStreakSeconds)
                )
            }
            .padding(.horizontal)
        }
    }

    private func metricCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.blue)

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.weight(.semibold))

                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
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

// MARK: - FocusLevel Label Extension

private extension FocusLevel {
    var label: String {
        switch self {
        case _ where color == .green: return "Deep Focus"
        case _ where color == .yellow: return "Moderate Focus"
        case _ where color == .orange: return "Light Focus"
        default: return "Distracted"
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView(session: FocusSession(
              startTime: .now,
              endTime: .now,
              activityType: "studying",
              focusScore: 75,
              totalDurationSeconds: 300
          ))
    }
}
