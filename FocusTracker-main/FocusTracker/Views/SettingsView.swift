import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var showCalibration = false

    @AppStorage("captureFrameRate") private var captureFrameRate: Double = 30
    @AppStorage("showGazeDotOverlay") private var showGazeDotOverlay = true
    @AppStorage("lastCalibrationDate") private var lastCalibrationDate: Double = 0
    @AppStorage("lastCalibrationAccuracy") private var lastCalibrationAccuracy: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                calibrationSection
                trackingSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showCalibration) {
                CalibrationView()
            }
            .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteAllSessions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all focus sessions and their data. This action cannot be undone.")
            }
        }
    }

    // MARK: - Calibration Section

    private var calibrationSection: some View {
        Section("Calibration") {
            Button {
                showCalibration = true
            } label: {
                HStack {
                    Label("Run Calibration", systemImage: "viewfinder.circle")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            if lastCalibrationDate > 0 {
                HStack {
                    Label("Last Calibrated", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedCalibrationDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Accuracy", systemImage: "target")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", lastCalibrationAccuracy * 100))
                        .font(.subheadline)
                        .foregroundStyle(calibrationAccuracyColor)
                }
            } else {
                HStack {
                    Label("Status", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Not calibrated")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Tracking Section

    private var trackingSection: some View {
        Section("Tracking") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Capture Rate", systemImage: "speedometer")
                    Spacer()
                    Text("\(Int(captureFrameRate)) FPS")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $captureFrameRate,
                    in: 15...30,
                    step: 15
                )
                .tint(.blue)

                HStack {
                    Text("15 FPS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("30 FPS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $showGazeDotOverlay) {
                Label("Gaze Dot Overlay", systemImage: "circle.fill")
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section("Data") {
            Button {
                exportSessions()
            } label: {
                Label("Export All Sessions", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete All Data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text("0.1.0")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("How It Works", systemImage: "eye.tracking.on")
                    .font(.subheadline.weight(.medium))

                Text("FocusTracker uses ARKit face tracking to estimate where you are looking on screen. Gaze data is combined with fixation analysis, blink detection, and saccade tracking to compute a focus score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.green)

                Text("All data stays on your device. No information is collected or transmitted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Actions

    private func deleteAllSessions() {
        do {
            try modelContext.delete(model: FocusSession.self)
            try modelContext.save()
        } catch {
            print("Failed to delete sessions: \(error)")
        }
    }

    private func exportSessions() {
        // Trigger data export flow; actual implementation depends on DataExporter utility
    }

    // MARK: - Helpers

    private var formattedCalibrationDate: String {
        let date = Date(timeIntervalSince1970: lastCalibrationDate)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private var calibrationAccuracyColor: Color {
        switch lastCalibrationAccuracy {
        case 0.9...: return .green
        case 0.7..<0.9: return .yellow
        default: return .orange
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: FocusSession.self, inMemory: true)
}
