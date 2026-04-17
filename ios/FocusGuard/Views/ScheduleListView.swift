import SwiftUI

struct ScheduleListView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var blocking: BlockingService
    @Binding var schedules: [Schedule]

    @State private var showAddSheet = false
    @State private var editingSchedule: Schedule?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach($schedules) { $schedule in
                ScheduleRow(schedule: $schedule) {
                    // toggle active inline
                    Task { await toggleActive(&schedule) }
                } onTap: {
                    editingSchedule = schedule
                }
            }
            .onDelete { indexSet in
                Task { await deleteSchedules(at: indexSet) }
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ScheduleEditView(schedule: nil) { saved in
                schedules.append(saved)
            }
            .environmentObject(api)
            .environmentObject(blocking)
        }
        .sheet(item: $editingSchedule) { schedule in
            ScheduleEditView(schedule: schedule) { updated in
                if let i = schedules.firstIndex(where: { $0.id == updated.id }) {
                    schedules[i] = updated
                }
            }
            .environmentObject(api)
            .environmentObject(blocking)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggleActive(_ schedule: inout Schedule) async {
        let newActive = !schedule.isActive
        do {
            let updated = try await api.updateSchedule(
                id: schedule.id,
                ScheduleUpdate(isActive: newActive)
            )
            schedule = updated
            // sync the DeviceActivity registration
            if updated.isActive {
                blocking.registerSchedule(updated, selection: nil)
            } else {
                blocking.removeSchedule(id: updated.id)
            }
        } catch {
            errorMessage = "Failed to update schedule: \(error.localizedDescription)"
        }
    }

    private func deleteSchedules(at indexSet: IndexSet) async {
        for i in indexSet {
            let schedule = schedules[i]
            do {
                try await api.deleteSchedule(id: schedule.id)
                blocking.removeSchedule(id: schedule.id)
            } catch {
                errorMessage = "Failed to delete: \(error.localizedDescription)"
                return
            }
        }
        schedules.remove(atOffsets: indexSet)
    }
}

struct ScheduleRow: View {
    @Binding var schedule: Schedule
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.headline)
                Text("\(formattedTime(schedule.startTime)) – \(formattedTime(schedule.endTime))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(daysSummary(schedule.daysOfWeek))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: .init(
                get: { schedule.isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private func formattedTime(_ t: String) -> String {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return t }
        let h = parts[0], m = parts[1]
        let suffix = h >= 12 ? "PM" : "AM"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", h12, m, suffix)
    }

    private func daysSummary(_ days: [Int]) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days.sorted().compactMap { names[safe: $0 - 1] }.joined(separator: " · ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
