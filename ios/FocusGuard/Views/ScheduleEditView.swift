import SwiftUI
import FamilyControls

// Used for both creating a new schedule and editing an existing one.
// Pass nil for `schedule` to create, or a Schedule value to edit.
struct ScheduleEditView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var blocking: BlockingService
    @Environment(\.dismiss) var dismiss

    let schedule: Schedule?
    let onSave: (Schedule) -> Void

    // form state
    @State private var name: String
    @State private var isActive: Bool
    @State private var selectedDays: Set<Int>      // 1=Sun … 7=Sat
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var pomodoroEnabled: Bool
    @State private var workMinutes: Int
    @State private var shortBreakMin: Int
    @State private var longBreakMin: Int
    @State private var sessionsBeforeLongBreak: Int

    // app picker state
    @State private var selection = FamilyActivitySelection()
    @State private var showAppPicker = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let daysOfWeek = [(1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
                               (5, "Thu"), (6, "Fri"), (7, "Sat")]

    init(schedule: Schedule?, onSave: @escaping (Schedule) -> Void) {
        self.schedule = schedule
        self.onSave = onSave

        // pre-fill from existing schedule or set sensible defaults
        _name = State(initialValue: schedule?.name ?? "")
        _isActive = State(initialValue: schedule?.isActive ?? true)
        _selectedDays = State(initialValue: Set(schedule?.daysOfWeek ?? [2, 3, 4, 5, 6]))
        _startTime = State(initialValue: timeFromString(schedule?.startTime ?? "09:00:00"))
        _endTime = State(initialValue: timeFromString(schedule?.endTime ?? "12:00:00"))
        _pomodoroEnabled = State(initialValue: schedule?.pomodoroEnabled ?? false)
        _workMinutes = State(initialValue: schedule?.workMinutes ?? 25)
        _shortBreakMin = State(initialValue: schedule?.shortBreakMin ?? 5)
        _longBreakMin = State(initialValue: schedule?.longBreakMin ?? 15)
        _sessionsBeforeLongBreak = State(initialValue: schedule?.sessionsBeforeLongBreak ?? 4)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Morning Deep Work", text: $name)
                }

                Section("Time Window") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section("Days") {
                    HStack(spacing: 8) {
                        ForEach(daysOfWeek, id: \.0) { (num, label) in
                            DayToggle(label: label, isSelected: selectedDays.contains(num)) {
                                if selectedDays.contains(num) {
                                    selectedDays.remove(num)
                                } else {
                                    selectedDays.insert(num)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Blocked Apps") {
                    Button {
                        showAppPicker = true
                    } label: {
                        HStack {
                            Label("Choose Apps to Block", systemImage: "app.badge.fill")
                            Spacer()
                            if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
                                Text("Configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .familyActivityPicker(isPresented: $showAppPicker, selection: $selection)
                }

                Section {
                    Toggle("Enable Pomodoro Timer", isOn: $pomodoroEnabled)
                }

                if pomodoroEnabled {
                    Section("Pomodoro Config") {
                        Stepper("Work: \(workMinutes) min", value: $workMinutes, in: 5...90, step: 5)
                        Stepper("Short break: \(shortBreakMin) min", value: $shortBreakMin, in: 1...30, step: 1)
                        Stepper("Long break: \(longBreakMin) min", value: $longBreakMin, in: 5...60, step: 5)
                        Stepper("Sessions before long break: \(sessionsBeforeLongBreak)", value: $sessionsBeforeLongBreak, in: 2...8, step: 1)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(schedule == nil ? "New Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || selectedDays.isEmpty || isSaving)
                }
            }
        }
    }

    // MARK: — Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let tz = TimeZone.current.identifier
        let startStr = timeString(from: startTime)
        let endStr = timeString(from: endTime)
        let days = Array(selectedDays).sorted()

        do {
            let saved: Schedule
            if let existing = schedule {
                // update
                let updates = ScheduleUpdate(
                    name: name,
                    isActive: isActive,
                    daysOfWeek: days,
                    startTime: startStr,
                    endTime: endStr,
                    timezone: tz,
                    pomodoroEnabled: pomodoroEnabled,
                    workMinutes: workMinutes,
                    shortBreakMin: shortBreakMin,
                    longBreakMin: longBreakMin,
                    sessionsBeforeLongBreak: sessionsBeforeLongBreak
                )
                saved = try await api.updateSchedule(id: existing.id, updates)
            } else {
                // create
                let new = NewSchedule(
                    name: name,
                    isActive: isActive,
                    daysOfWeek: days,
                    startTime: startStr,
                    endTime: endStr,
                    timezone: tz,
                    pomodoroEnabled: pomodoroEnabled,
                    workMinutes: workMinutes,
                    shortBreakMin: shortBreakMin,
                    longBreakMin: longBreakMin,
                    sessionsBeforeLongBreak: sessionsBeforeLongBreak
                )
                saved = try await api.createSchedule(new)
            }

            // persist app selection to shared container + API
            let selectionData = selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
                ? nil
                : (try? JSONEncoder().encode(selection)).flatMap { Data($0).base64EncodedString() as String? }

            _ = try? await api.updateBlockedApps(
                scheduleId: saved.id,
                iosActivitySelection: selectionData,
                blockedDomains: []
            )

            // register with DeviceActivity so it works in background
            if saved.isActive {
                blocking.registerSchedule(saved, selection: selection.applicationTokens.isEmpty ? nil : selection)
            }

            onSave(saved)
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: — Helpers

private struct DayToggle: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { onTap() }
    }
}

private func timeFromString(_ s: String) -> Date {
    let parts = s.split(separator: ":").compactMap { Int($0) }
    var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    c.hour = parts[safe: 0] ?? 9
    c.minute = parts[safe: 1] ?? 0
    return Calendar.current.date(from: c) ?? Date()
}

private func timeString(from date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d:00", c.hour ?? 0, c.minute ?? 0)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
