import Foundation

// Controls macOS Do Not Disturb via the built-in `shortcuts` CLI.
// The user needs to have a Focus mode named "Focus Guard" set up in
// System Settings → Focus. We call it on/off at schedule boundaries.
//
// Why shortcuts CLI? It's the most reliable public API for controlling
// Focus modes programmatically without requiring private entitlements.
@MainActor
final class FocusModeService: ObservableObject {
    @Published private(set) var isDNDActive = false

    private let focusName = "Focus Guard"  // must match the Focus name in System Settings

    func enable() {
        run(shortcut: "Enable \(focusName) Focus")
        isDNDActive = true
    }

    func disable() {
        run(shortcut: "Disable \(focusName) Focus")
        isDNDActive = false
    }

    // MARK: — Shell helper

    private func run(shortcut name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]

        // fire-and-forget — if the shortcut fails (e.g. not set up), we log it
        let pipe = Pipe()
        task.standardError = pipe
        do {
            try task.launch()
        } catch {
            print("FocusModeService: failed to run shortcut '\(name)': \(error)")
        }
    }
}
