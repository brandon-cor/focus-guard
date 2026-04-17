import SwiftUI
import AppKit

@main
struct FocusMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var api = APIClient.shared
    @StateObject private var focusMode = FocusModeService()
    @StateObject private var daemon = ScheduleDaemon.shared

    var body: some Scene {
        // no main window — this is a menu bar only app
        Settings {
            EmptyView()
        }
    }
}

// AppDelegate sets up the NSStatusItem (menu bar icon)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // hide from Dock and app switcher — menu bar only
        NSApp.setActivationPolicy(.accessory)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(APIClient.shared)
                .environmentObject(FocusModeService())
                .environmentObject(ScheduleDaemon.shared)
        )
        self.popover = popover

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Focus Guard")
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = item

        // start the schedule daemon
        Task { await ScheduleDaemon.shared.start() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
