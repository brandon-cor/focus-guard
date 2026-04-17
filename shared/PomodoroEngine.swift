import Foundation
import Combine

// MARK: — Phase

enum PomodoroPhase: Equatable {
    case idle
    case work(sessionNumber: Int)
    case shortBreak(afterSession: Int)
    case longBreak(afterSession: Int)

    var label: String {
        switch self {
        case .idle:                        return "Ready"
        case .work(let n):                 return "Work · Session \(n)"
        case .shortBreak:                  return "Short Break"
        case .longBreak:                   return "Long Break"
        }
    }

    var isWork: Bool {
        if case .work = self { return true }
        return false
    }
}

// MARK: — Config

struct PomodoroConfig {
    var workMinutes: Int = 25
    var shortBreakMin: Int = 5
    var longBreakMin: Int = 15
    var sessionsBeforeLongBreak: Int = 4

    // convenience initialiser from a Schedule
    init(from schedule: Schedule? = nil) {
        guard let s = schedule, s.pomodoroEnabled else { return }
        workMinutes = s.workMinutes
        shortBreakMin = s.shortBreakMin
        longBreakMin = s.longBreakMin
        sessionsBeforeLongBreak = s.sessionsBeforeLongBreak
    }
}

// MARK: — Engine

// PomodoroEngine uses absolute Date targets rather than a countdown so the
// timer survives being backgrounded — when the app wakes it computes the
// remaining time from phaseEndsAt instead of trusting how long the Timer fired.
@MainActor
final class PomodoroEngine: ObservableObject {
    // current state
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var completedSessions: Int = 0

    var config = PomodoroConfig()

    private var phaseEndsAt: Date?
    private var timer: AnyCancellable?

    // true if blocking should currently be active
    var shouldBlock: Bool {
        switch phase {
        case .idle, .shortBreak, .longBreak: return false
        case .work:                           return true
        }
    }

    // MARK: — Controls

    func start(config: PomodoroConfig? = nil) {
        if let c = config { self.config = c }
        completedSessions = 0
        beginWork()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        phase = .idle
        secondsRemaining = 0
        phaseEndsAt = nil
    }

    // MARK: — Internals

    private func beginWork() {
        let session = completedSessions + 1
        let duration = config.workMinutes * 60
        setPhase(.work(sessionNumber: session), duration: duration)
    }

    private func beginBreak() {
        let isLong = completedSessions % config.sessionsBeforeLongBreak == 0
        let duration = isLong
            ? config.longBreakMin * 60
            : config.shortBreakMin * 60
        let p: PomodoroPhase = isLong
            ? .longBreak(afterSession: completedSessions)
            : .shortBreak(afterSession: completedSessions)
        setPhase(p, duration: duration)
    }

    private func setPhase(_ newPhase: PomodoroPhase, duration: Int) {
        timer?.cancel()
        phase = newPhase
        phaseEndsAt = Date().addingTimeInterval(TimeInterval(duration))
        secondsRemaining = duration
        startTicking()
    }

    private func startTicking() {
        // fire every second; use the absolute end date so backgrounding doesn't drift
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.tick() }
            }
    }

    private func tick() {
        guard let end = phaseEndsAt else { return }
        let remaining = max(0, Int(end.timeIntervalSinceNow.rounded()))
        secondsRemaining = remaining

        if remaining == 0 {
            advance()
        }
    }

    private func advance() {
        timer?.cancel()
        switch phase {
        case .work:
            completedSessions += 1
            beginBreak()
        case .shortBreak, .longBreak:
            beginWork()
        case .idle:
            break
        }
    }
}
