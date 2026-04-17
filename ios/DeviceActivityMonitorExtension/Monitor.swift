import DeviceActivity
import ManagedSettings
import FamilyControls

// This extension runs in a separate process managed by the OS.
// It fires automatically when a registered DeviceActivity schedule
// interval starts or ends — the main app does not need to be running.
//
// IMPORTANT: This target must be added to the App Group
// "group.com.focusguard" so it can read the saved FamilyActivitySelection.
final class FocusGuardMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()
    private let defaults = UserDefaults(suiteName: "group.com.focusguard")!

    // The schedule ID is embedded in the DeviceActivityName we registered.
    // We extract it to look up the saved app selection.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        let scheduleId = activity.rawValue
        let selection = loadSelection(forSchedule: scheduleId)
        applyShields(selection: selection)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        store.clearAllSettings()
    }

    // MARK: — Shield application

    private func applyShields(selection: FamilyActivitySelection?) {
        if let selection {
            if !selection.applicationTokens.isEmpty {
                store.shield.applications = selection.applicationTokens
            }
            if !selection.categoryTokens.isEmpty {
                store.shield.applicationCategories =
                    .specific(selection.categoryTokens)
            }
        } else {
            // fallback: block everything if no selection was saved
            store.shield.applicationCategories = .all()
        }
    }

    // MARK: — Read selection from shared UserDefaults

    private func loadSelection(forSchedule id: String) -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: "selection_\(id)") else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}
