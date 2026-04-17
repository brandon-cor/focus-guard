import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings

// BlockingService is the bridge between our schedules and Apple's Screen Time APIs.
// It handles two separate triggering paths:
//   1. Schedule-based: registers DeviceActivity schedules that fire automatically
//   2. Pomodoro-based: applies/removes shields directly when the user taps Start/Stop
@MainActor
final class BlockingService: ObservableObject {
    static let shared = BlockingService()

    @Published private(set) var isAuthorized = false

    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore()

    private init() {
        // check current authorization status
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: — Authorization

    // Must be called during onboarding before any blocking can happen.
    // Presents the system Screen Time authorization prompt.
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual())
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        } catch {
            print("FamilyControls authorization failed: \(error)")
        }
    }

    // MARK: — Schedule-based blocking (DeviceActivity)

    // Registers a DeviceActivity schedule for the given schedule.
    // The DeviceActivityMonitorExtension will apply / clear shields when the
    // window starts and ends — this works even when the app is not running.
    func registerSchedule(_ schedule: Schedule, selection: FamilyActivitySelection?) {
        guard isAuthorized else { return }

        let activityName = DeviceActivityName(schedule.id)

        // convert our 1-based day array [1=Sun … 7=Sat] to DateComponents weekdays
        let weekdays = schedule.daysOfWeek.map { DateComponents(weekday: $0) }

        guard
            let startComponents = timeComponents(from: schedule.startTime),
            let endComponents = timeComponents(from: schedule.endTime)
        else {
            print("BlockingService: could not parse times for schedule \(schedule.id)")
            return
        }

        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: true,
            warningTime: nil
        )

        // store the selection so the extension can read it
        if let selection {
            saveSelection(selection, forSchedule: schedule.id)
        }

        do {
            try center.startMonitoring(activityName, during: deviceSchedule)
        } catch {
            print("BlockingService: startMonitoring failed: \(error)")
        }
    }

    func removeSchedule(id: String) {
        center.stopMonitoring([DeviceActivityName(id)])
        clearSavedSelection(forSchedule: id)
    }

    func removeAllSchedules() {
        center.stopMonitoring()
    }

    // MARK: — Pomodoro-based blocking (direct ManagedSettings)

    // Called when the user starts a Pomodoro session.
    // Reads the selection for the given schedule (or blocks all apps if nil).
    func applyPomodoroBlock(forSchedule scheduleId: String?) {
        guard isAuthorized else { return }
        let selection = scheduleId.flatMap { loadSelection(forSchedule: $0) }
        applyShields(selection: selection)
    }

    func removePomodoroBlock() {
        store.clearAllSettings()
    }

    // MARK: — Shield application (used by both paths)

    // Internal — also called from the DeviceActivityMonitorExtension
    func applyShields(selection: FamilyActivitySelection?) {
        if let selection {
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil
                : ShieldSettings.ActivityCategoryPolicy.specific(selection.categoryTokens)
        } else {
            // no specific selection saved — block all apps as a fallback
            store.shield.applicationCategories = .all()
        }
    }

    // MARK: — Persisting FamilyActivitySelection

    // FamilyActivitySelection tokens are opaque — we encode them to UserDefaults
    // (in the App Group shared container) so the extension can read them.
    private let defaults = UserDefaults(suiteName: "group.com.focusguard")!

    private func saveSelection(_ selection: FamilyActivitySelection, forSchedule id: String) {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: "selection_\(id)")
        }
    }

    private func loadSelection(forSchedule id: String) -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: "selection_\(id)") else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func clearSavedSelection(forSchedule id: String) {
        defaults.removeObject(forKey: "selection_\(id)")
    }

    // MARK: — Helpers

    private func timeComponents(from timeString: String) -> DateComponents? {
        // expects "HH:MM:SS" or "HH:MM"
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return DateComponents(hour: parts[0], minute: parts[1])
    }
}
