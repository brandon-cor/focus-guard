import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var blocking: BlockingService
    @EnvironmentObject var pomodoro: PomodoroEngine

    @State private var schedules: [Schedule] = []
    @State private var selectedScheduleId: String?
    @State private var isLoadingSchedules = false
    @State private var showScheduleList = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingDone")

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                statusBanner
                pomodoroSection
                Spacer()
                nextScheduleLabel
            }
            .padding()
            .navigationTitle("Focus Guard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScheduleList = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
            }
            .navigationDestination(isPresented: $showScheduleList) {
                ScheduleListView(schedules: $schedules)
                    .environmentObject(api)
                    .environmentObject(blocking)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
                    .environmentObject(blocking)
            }
            .task {
                await loadSchedules()
            }
        }
    }

    // MARK: — Sub-views

    private var statusBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: blocking.isAuthorized ? "lock.shield.fill" : "lock.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(blocking.isAuthorized ? .green : .orange)
            Text(blocking.isAuthorized ? "Screen Time Authorized" : "Authorization Required")
                .font(.headline)
                .foregroundStyle(blocking.isAuthorized ? .primary : .orange)
        }
        .padding(.top, 24)
    }

    private var pomodoroSection: some View {
        Group {
            if pomodoro.phase != .idle {
                PomodoroView()
                    .environmentObject(pomodoro)
                    .environmentObject(blocking)
            } else {
                startPomodoroButton
            }
        }
    }

    private var startPomodoroButton: some View {
        VStack(spacing: 12) {
            // schedule picker — only shown if user has schedules with Pomodoro enabled
            let pomSchedules = schedules.filter { $0.pomodoroEnabled }
            if !pomSchedules.isEmpty {
                Picker("Schedule", selection: $selectedScheduleId) {
                    Text("No schedule").tag(String?.none)
                    ForEach(pomSchedules) { s in
                        Text(s.name).tag(String?.some(s.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Button {
                startPomodoro()
            } label: {
                Label("Start Pomodoro", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!blocking.isAuthorized)
        }
    }

    private var nextScheduleLabel: some View {
        Group {
            if let next = nextActiveSchedule() {
                Label("Next block: \(next.name) at \(next.startTime)", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: — Actions

    private func startPomodoro() {
        let config: PomodoroConfig
        if let id = selectedScheduleId,
           let schedule = schedules.first(where: { $0.id == id }) {
            config = PomodoroConfig(from: schedule)
        } else {
            config = PomodoroConfig()
        }
        pomodoro.start(config: config)
        blocking.applyPomodoroBlock(forSchedule: selectedScheduleId)
    }

    private func loadSchedules() async {
        isLoadingSchedules = true
        defer { isLoadingSchedules = false }
        do {
            schedules = try await api.fetchSchedules()
        } catch {
            print("Failed to load schedules: \(error)")
        }
    }

    private func nextActiveSchedule() -> Schedule? {
        // simple heuristic: find first active schedule that hasn't started today
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        return schedules
            .filter { $0.isActive && $0.daysOfWeek.contains(weekday) }
            .first
    }
}
