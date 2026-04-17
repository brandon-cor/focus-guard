import Foundation
import Combine

// ScheduleDaemon polls the API for schedules, caches them locally, and fires
// DND enable/disable at each schedule boundary. It runs continuously in the
// background and survives the app being hidden (it's a menu bar app so it's
// always "running"). A LaunchAgent plist keeps the whole app alive across reboots.
@MainActor
final class ScheduleDaemon: ObservableObject {
    static let shared = ScheduleDaemon()

    @Published private(set) var currentlyBlocking = false
    @Published private(set) var schedules: [Schedule] = []

    private let focusMode = FocusModeService()
    private var checkTimer: AnyCancellable?
    private var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appending(path: "FocusGuard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "schedules.json")
    }

    private init() {}

    func start() async {
        // load whatever we have cached first so blocking works immediately on wake
        loadCached()
        // fetch fresh schedules from API
        await syncSchedules()
        // then check every minute whether a schedule boundary has been crossed
        checkTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.evaluateSchedules()
                }
            }
        evaluateSchedules()
    }

    // MARK: — Schedule sync

    func syncSchedules() async {
        guard APIClient.shared.isAuthenticated else { return }
        do {
            let fresh = try await APIClient.shared.fetchSchedules()
            schedules = fresh
            persist(fresh)
        } catch {
            print("ScheduleDaemon: sync failed, using cache — \(error)")
        }
    }

    // MARK: — Boundary evaluation

    // Called every minute and on wake. Checks if any active schedule's window
    // covers the current time and enables/disables DND accordingly.
    func evaluateSchedules() {
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute

        let shouldBlock = schedules.contains { schedule in
            guard schedule.isActive, schedule.daysOfWeek.contains(weekday) else { return false }

            let start = minutesFromTimeString(schedule.startTime)
            let end = minutesFromTimeString(schedule.endTime)
            return nowMinutes >= start && nowMinutes < end
        }

        if shouldBlock && !currentlyBlocking {
            focusMode.enable()
            currentlyBlocking = true
        } else if !shouldBlock && currentlyBlocking {
            focusMode.disable()
            currentlyBlocking = false
        }
    }

    // MARK: — Persistence (local JSON cache)

    private func persist(_ schedules: [Schedule]) {
        if let data = try? JSONEncoder().encode(schedules) {
            try? data.write(to: cacheURL)
        }
    }

    private func loadCached() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([Schedule].self, from: data)
        else { return }
        schedules = cached
    }

    // MARK: — Helpers

    private func minutesFromTimeString(_ s: String) -> Int {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}
