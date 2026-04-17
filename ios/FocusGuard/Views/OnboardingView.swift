import SwiftUI

// Shown once on first launch. Walks the user through:
// 1. Granting FamilyControls authorization (required for all blocking)
// 2. Explaining that no bypass exists while the app is installed
struct OnboardingView: View {
    @EnvironmentObject var blocking: BlockingService
    @Environment(\.dismiss) var dismiss
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomeStep.tag(0)
                permissionStep.tag(1)
                noBypassStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if step == 2 {
                Button("Get Started") {
                    UserDefaults.standard.set(true, forKey: "onboardingDone")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 40)
                .padding(.horizontal, 40)
                .disabled(!blocking.isAuthorized)
            }
        }
    }

    private var welcomeStep: some View {
        OnboardingStepView(
            icon: "timer",
            title: "Focus Guard",
            body: "Block distracting apps and enable Do Not Disturb automatically — on a schedule, or when you start a Pomodoro session.",
            action: nil
        ) {
            step = 1
        }
    }

    private var permissionStep: some View {
        OnboardingStepView(
            icon: "lock.shield",
            title: "Screen Time Access",
            body: "Focus Guard uses Screen Time to block apps at the system level. Tap below to grant access — you'll see a system prompt.",
            action: blocking.isAuthorized ? nil : {
                Task { await blocking.requestAuthorization() }
            }
        ) {
            step = 2
        }
    }

    private var noBypassStep: some View {
        OnboardingStepView(
            icon: "exclamationmark.triangle",
            title: "No Bypass",
            body: "Once a block is active, there is no way to override it from within the app. The only way out is to delete Focus Guard entirely. This is intentional.",
            action: nil
        ) {
            step = 2  // already on last step; "Next" becomes "Get Started" above
        }
    }
}

private struct OnboardingStepView: View {
    let icon: String
    let title: String
    let body: String
    let action: (() -> Void)?
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text(title).font(.largeTitle.bold())
            Text(body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if let action {
                Button("Grant Permission", action: action)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
            Button("Next") { onNext() }
                .padding(.bottom, 8)
        }
    }
}
