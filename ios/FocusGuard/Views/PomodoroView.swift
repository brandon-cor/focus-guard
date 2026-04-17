import SwiftUI

struct PomodoroView: View {
    @EnvironmentObject var pomodoro: PomodoroEngine
    @EnvironmentObject var blocking: BlockingService

    var body: some View {
        VStack(spacing: 24) {
            // phase label
            Text(pomodoro.phase.label)
                .font(.headline)
                .foregroundStyle(.secondary)

            // circular progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                    Text(pomodoro.phase.isWork ? "Focus" : "Rest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)

            // session dots — shows how many work sessions completed this round
            sessionDots

            // stop button
            Button(role: .destructive) {
                pomodoro.stop()
                blocking.removePomodoroBlock()
            } label: {
                Label("End Session", systemImage: "stop.fill")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    // MARK: — Helpers

    private var timeString: String {
        let m = pomodoro.secondsRemaining / 60
        let s = pomodoro.secondsRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var progress: CGFloat {
        // derive total seconds for this phase from config
        let total: Int
        switch pomodoro.phase {
        case .idle:             return 0
        case .work:             total = pomodoro.config.workMinutes * 60
        case .shortBreak:       total = pomodoro.config.shortBreakMin * 60
        case .longBreak:        total = pomodoro.config.longBreakMin * 60
        }
        guard total > 0 else { return 0 }
        return CGFloat(total - pomodoro.secondsRemaining) / CGFloat(total)
    }

    private var ringColor: Color {
        pomodoro.phase.isWork ? .blue : .green
    }

    private var sessionDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pomodoro.config.sessionsBeforeLongBreak, id: \.self) { i in
                Circle()
                    .fill(i < pomodoro.completedSessions % pomodoro.config.sessionsBeforeLongBreak
                          ? Color.blue
                          : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
    }
}
