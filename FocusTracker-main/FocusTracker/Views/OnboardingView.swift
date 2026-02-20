import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            onboardingPage(
                icon: "brain.head.profile",
                iconColor: .blue,
                title: "Track Your Focus",
                description: "FocusTracker uses your iPhone's front camera and ARKit to measure where you look during study and work sessions. Get real-time feedback and track your focus over time.",
                pageIndex: 0
            )
            .tag(0)

            onboardingPage(
                icon: "eye.circle",
                iconColor: .green,
                title: "Camera Privacy",
                description: "All eye tracking is processed entirely on your device using Apple's ARKit. No camera data, gaze data, or session information ever leaves your phone. Your privacy is fully protected.",
                pageIndex: 1
            )
            .tag(1)

            onboardingPage(
                icon: "checkmark.circle",
                iconColor: .purple,
                title: "Get Started",
                description: "Run a quick calibration, pick an activity, and start your first focus session. You will see a real-time gaze dot and get a detailed focus score when you finish.",
                pageIndex: 2,
                showButton: true
            )
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .ignoresSafeArea()
    }

    // MARK: - Onboarding Page

    private func onboardingPage(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        pageIndex: Int,
        showButton: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(iconColor)
            }

            Spacer()
                .frame(height: 40)

            // Title
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 16)

            // Description
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()
                .frame(height: 48)

            // Button (only on last page)
            if showButton {
                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("Begin")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
            }

            Spacer()
                .frame(height: 80)
        }
    }
}

#Preview {
    OnboardingView()
}
