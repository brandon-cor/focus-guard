import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var focusMode: FocusModeService
    @EnvironmentObject var daemon: ScheduleDaemon

    @StateObject private var pomodoro = PomodoroEngine()
    @State private var pomodoroActive = false

    var body: some View {
        VStack(spacing: 0) {
            // header
            HStack {
                Image(systemName: "timer")
                Text("Focus Guard")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(daemon.currentlyBlocking ? .green : .gray.opacity(0.4))
                    .frame(width: 10, height: 10)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection
                    Divider()
                    pomodoroSection
                    Divider()
                    scheduleSummary
                    Divider()
                    actionsSection
                }
                .padding()
            }
        }
        .frame(width: 300)
        .onChange(of: pomodoro.phase) { _, newPhase in
            // enable DND when Pomodoro work starts, disable when idle/break ends
            if case .work = newPhase {
                focusMode.enable()
            } else if newPhase == .idle {
                // only disable DND from Pomodoro if a scheduled block isn't active
                if !daemon.currentlyBlocking {
                    focusMode.disable()
                }
            }
        }
    }

    // MARK: — Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status")
                .font(.caption.uppercased())
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: daemon.currentlyBlocking || focusMode.isDNDActive
                      ? "moon.fill" : "moon")
                    .foregroundStyle(daemon.currentlyBlocking ? .blue : .secondary)
                Text(daemon.currentlyBlocking ? "DND Active (Schedule)" :
                     focusMode.isDNDActive ? "DND Active (Pomodoro)" : "Not blocking")
                    .font(.subheadline)
            }
        }
    }

    private var pomodoroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pomodoro")
                .font(.caption.uppercased())
                .foregroundStyle(.secondary)

            if pomodoro.phase != .idle {
                HStack {
                    VStack(alignment: .leading) {
                        Text(pomodoro.phase.label)
                            .font(.subheadline.bold())
                        Text(timeString(pomodoro.secondsRemaining))
                            .font(.system(.title2, design: .monospaced).bold())
                    }
                    Spacer()
                    Button("Stop") {
                        pomodoro.stop()
                        if !daemon.currentlyBlocking {
                            focusMode.disable()
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    pomodoro.start()
                    focusMode.enable()
                } label: {
                    Label("Start Pomodoro", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var scheduleSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Schedules")
                .font(.caption.uppercased())
                .foregroundStyle(.secondary)
            if daemon.schedules.isEmpty {
                Text("No schedules configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(daemon.schedules.filter { $0.isActive }) { schedule in
                    HStack {
                        Text(schedule.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(shortTime(schedule.startTime))–\(shortTime(schedule.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button("Refresh Schedules") {
                Task { await daemon.syncSchedules() }
            }
            .frame(maxWidth: .infinity)
            .controlSize(.small)

            Button("Sign Out") {
                api.signOut()
            }
            .frame(maxWidth: .infinity)
            .controlSize(.small)
            .foregroundStyle(.red)

            Button("Quit Focus Guard") {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: — Helpers

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func shortTime(_ s: String) -> String {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return s }
        let h = parts[0], m = parts[1]
        return String(format: "%d:%02d", h, m)
    }
}
