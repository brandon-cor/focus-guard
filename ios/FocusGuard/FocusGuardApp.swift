import SwiftUI

@main
struct FocusGuardApp: App {
    @StateObject private var api = APIClient.shared
    @StateObject private var blocking = BlockingService.shared
    @StateObject private var pomodoro = PomodoroEngine()

    var body: some Scene {
        WindowGroup {
            if api.isAuthenticated {
                HomeView()
                    .environmentObject(api)
                    .environmentObject(blocking)
                    .environmentObject(pomodoro)
            } else {
                AuthView()
                    .environmentObject(api)
            }
        }
    }
}
