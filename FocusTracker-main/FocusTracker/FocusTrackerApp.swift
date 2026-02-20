import SwiftUI
import SwiftData

@main
struct FocusTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else {
                ContentView()
            }
        }
        .modelContainer(for: FocusSession.self)
    }
}
