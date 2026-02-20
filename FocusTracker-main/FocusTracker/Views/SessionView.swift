import SwiftUI
import SwiftData

struct SessionView: View {
    @StateObject private var viewModel = SessionViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var selectedActivity: ActivityType = .studying
    @State private var completedSession: FocusSession?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                switch viewModel.trackingState {
                case .notStarted:
                    notStartedView
                case .tracking:
                    trackingView
                case .paused:
                    pausedView
                case .stopped:
                    stoppedView
                }
            }
            .navigationTitle("Focus Session")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $completedSession) { session in
                DashboardView(session: session)
            }
        }
    }

    // MARK: - Not Started

    private var notStartedView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "eye.tracking.on")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Ready to Focus")
                    .font(.title2.bold())

                Text("Select an activity and start tracking your focus using eye tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                Text("Activity")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Activity", selection: $selectedActivity) {
                    ForEach(ActivityType.allCases, id: \.self) { activity in
                        Text(activity.rawValue.capitalized)
                            .tag(activity)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }

            Button {
                viewModel.startSession(activity: selectedActivity)
            } label: {
                Text("Start Focus Session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Tracking

    private var trackingView: some View {
        GeometryReader { geometry in
            ZStack {
                // Screen border indicator
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        viewModel.isOnScreen ? Color.green.opacity(0.4) : Color.red.opacity(0.4),
                        lineWidth: 4
                    )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: viewModel.isOnScreen)

                // Gaze dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: .red.opacity(0.6), radius: 8, x: 0, y: 0)
                    .position(
                        x: viewModel.currentGazePoint.x,
                        y: viewModel.currentGazePoint.y
                    )
                    .animation(.interpolatingSpring(stiffness: 80, damping: 12), value: viewModel.currentGazePoint)

                // Top bar
                VStack {
                    HStack {
                        // Elapsed time
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.subheadline)
                            Text(formattedTime(viewModel.elapsedTime))
                                .font(.system(.title3, design: .monospaced).bold())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        // Running score
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.subheadline)
                                .foregroundStyle(.yellow)
                            Text("\(Int(viewModel.runningScore))%")
                                .font(.system(.title3, design: .rounded).bold())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }

                // Bottom controls
                VStack {
                    Spacer()

                    HStack(spacing: 16) {
                        Button {
                            viewModel.pauseSession()
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.title3)
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .clipShape(Circle())

                        Button {
                            completedSession = viewModel.stopSession(modelContext: modelContext)
                        } label: {
                            Text("Stop Session")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .clipShape(Capsule())
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Paused

    private var pausedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pause.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("Session Paused")
                .font(.title2.bold())

            Text(formattedTime(viewModel.elapsedTime))
                .font(.system(.largeTitle, design: .monospaced).bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    viewModel.resumeSession()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())

                Button {
                    completedSession = viewModel.stopSession(modelContext: modelContext)
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Stopped

    private var stoppedView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView("Saving session...")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview {
    SessionView()
        .modelContainer(for: FocusSession.self, inMemory: true)
}
