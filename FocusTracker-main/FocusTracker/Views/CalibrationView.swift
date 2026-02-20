import SwiftUI
import Combine

struct CalibrationView: View {
    @StateObject private var viewModel = CalibrationViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastCalibrationDate") private var lastCalibrationDate: Double = 0
    @AppStorage("lastCalibrationAccuracy") private var lastCalibrationAccuracy: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                switch viewModel.phase {
                case .instructions:
                    instructionsView(screenSize: geometry.size)
                case .collecting:
                    collectingView(screenSize: geometry.size)
                case .processing:
                    processingView
                case .complete:
                    completeView
                case .failed:
                    failedView(screenSize: geometry.size)
                }
            }
        }
    }

    // MARK: - Instructions

    private func instructionsView(screenSize: CGSize) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "viewfinder.circle")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Calibration")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                Text("We need to calibrate the eye tracker to your eyes.")
                    .font(.body)

                Text("You will see 5 dots appear on screen. Look directly at each dot and hold your gaze steady until it moves to the next position.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            VStack(spacing: 8) {
                instructionStep(number: 1, text: "Hold your phone at a comfortable distance")
                instructionStep(number: 2, text: "Look at each dot as it appears")
                instructionStep(number: 3, text: "Keep your head still")
            }
            .padding(.horizontal, 32)

            Button {
                viewModel.startCalibration(screenSize: screenSize)
            } label: {
                Text("Begin Calibration")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1), in: Circle())
                .foregroundStyle(.blue)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Collecting

    private func collectingView(screenSize: CGSize) -> some View {
        ZStack {
            // Target dot
            CalibrationDot()
                .position(
                    x: viewModel.targetPosition.x,
                    y: viewModel.targetPosition.y
                )
                .animation(.easeInOut(duration: 0.4), value: viewModel.targetPosition)

            // Instructions and progress at bottom
            VStack {
                Spacer()

                VStack(spacing: 12) {
                    Text("Look at the dot")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Point \(viewModel.currentPointIndex + 1) of 5")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(.horizontal, 60)
                }
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Computing calibration...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Calibration Complete")
                .font(.title2.bold())

            VStack(spacing: 8) {
                Text("Accuracy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(String(format: "%.0f%%", viewModel.accuracy * 100))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(accuracyColor)
            }

            Text(accuracyDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                lastCalibrationDate = Date().timeIntervalSince1970
                lastCalibrationAccuracy = viewModel.accuracy
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Failed

    private func failedView(screenSize: CGSize) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("Calibration Failed")
                .font(.title2.bold())

            Text("We could not complete the calibration. Make sure your face is visible to the camera and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button {
                    viewModel.startCalibration(screenSize: screenSize)
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var accuracyColor: Color {
        switch viewModel.accuracy {
        case 0.9...: return .green
        case 0.7..<0.9: return .yellow
        default: return .orange
        }
    }

    private var accuracyDescription: String {
        switch viewModel.accuracy {
        case 0.9...: return "Excellent calibration. Tracking should be very accurate."
        case 0.7..<0.9: return "Good calibration. Tracking should work well for most activities."
        default: return "Fair calibration. Consider recalibrating in better lighting."
        }
    }
}

// MARK: - Calibration Dot

private struct CalibrationDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                .frame(width: 40, height: 40)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.6)

            // Inner dot
            Circle()
                .fill(Color.blue)
                .frame(width: 16, height: 16)

            // Center point
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    CalibrationView()
}
