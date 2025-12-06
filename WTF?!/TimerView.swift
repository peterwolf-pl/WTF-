import SwiftUI
import SwiftData
import Charts
internal import Combine

extension Notification.Name {
    static let workSessionSaved = Notification.Name("workSessionSaved")
}

struct TimerView: View {
    @Environment(\.modelContext) private var context

    // Live clock timer
    @State private var now: Date = Date()
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Work session state
    @State private var isRunning = false
    @State private var startDate: Date?

    // Saved tasks templates for checklist
    @Query(sort: [SortDescriptor(\TaskTemplate.title, order: .forward)]) private var taskTemplates: [TaskTemplate]

    // Note input state shown after finishing a session
    @State private var showingNoteSheet = false
    @State private var pendingNote: String = ""

    // Today's total (in seconds)
    @State private var todaysTotal: Int = 0

    // Today's tasks (from today's saved session notes) and current selection
    @State private var selectedTasks: Set<String> = []

    // Temporarily hold last finished session boundaries until user confirms note
    @State private var pendingSessionStart: Date?
    @State private var pendingSessionEnd: Date?

    var body: some View {
        VStack(spacing: 24) {
            // Live clock display
            VStack(spacing: 8) {
                Text(now, style: .time)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()

                if isRunning {
                    let elapsed = max(Int((now.timeIntervalSince(startDate ?? now))), 0)
                    Text(formattedDuration(elapsed))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .transition(.opacity)
                }

                Text(isRunning ? "Working…" : "Ready")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .onReceive(clockTimer) { value in
                now = value
            }

            // Big action button
            Button(action: handleToggle) {
                Text("WORK")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.white)
                    .background(isRunning ? .red : .green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            // Today's total summary
            VStack(spacing: 6) {
                Text("Dzisiaj w pracy")
                    .font(.headline)
                Text(formattedDuration(todaysTotal))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .task {
                await refreshTodaysTotal()
            }

            // Today's tasks checklist
            if !taskTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Co robiłeś dziś?")
                        .font(.headline)
                    ForEach(taskTemplates.map { $0.title }, id: \.self) { task in
                        Toggle(isOn: Binding<Bool>(
                            get: { selectedTasks.contains(task) },
                            set: { isOn in
                                if isOn { selectedTasks.insert(task) } else { selectedTasks.remove(task) }
                            }
                        )) {
                            Text(task)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // If the app terminated while running, we could restore state from a persisted flag in the future.
        }
        .sheet(isPresented: $showingNoteSheet) {
            NavigationStack {
                Form {
                    Section("Notatka do sesji") {
                        TextField("Czym się zajmowałeś?", text: $pendingNote, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                            .lineLimit(3, reservesSpace: true)
                    }
                    if let start = pendingSessionStart, let end = pendingSessionEnd {
                        let duration = max(Int(end.timeIntervalSince(start)), 0)
                        Section("Podsumowanie") {
                            HStack {
                                Text("Czas trwania")
                                Spacer()
                                Text(formattedDuration(duration)).monospacedDigit()
                            }
                            HStack {
                                Text("Start")
                                Spacer()
                                Text(start.formatted(date: .abbreviated, time: .shortened))
                            }
                            HStack {
                                Text("Koniec")
                                Spacer()
                                Text(end.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    }
                }
                .navigationTitle("Zapisz sesję")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Anuluj") {
                            // Discard pending session
                            pendingSessionStart = nil
                            pendingSessionEnd = nil
                            pendingNote = ""
                            showingNoteSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Zapisz") { savePendingSession() }
                            .disabled(pendingSessionStart == nil || pendingSessionEnd == nil)
                    }
                }
            }
        }
    }

    private func handleToggle() {
        if isRunning {
            // Stop: prepare to save session, then ask for a note
            let end = Date()
            let start = startDate ?? end
            let duration = max(Int(end.timeIntervalSince(start)), 0)
            // If duration is zero, just reset without prompting
            guard duration > 0 else {
                isRunning = false
                startDate = nil
                return
            }
            // Stash pending data and show note sheet
            pendingSessionStart = start
            pendingSessionEnd = end
            // Prefill note from selected tasks (bullet list)
            let ordered = taskTemplates.map { $0.title }.filter { selectedTasks.contains($0) }
            if ordered.isEmpty {
                pendingNote = ""
            } else {
                pendingNote = ordered.map { "• \($0)" }.joined(separator: "\n")
            }
            showingNoteSheet = true

            // Reset running state
            isRunning = false
            startDate = nil
        } else {
            // Start
            startDate = Date()
            isRunning = true
        }
    }

    private func savePendingSession() {
        guard let start = pendingSessionStart, let end = pendingSessionEnd else { return }
        let duration = max(Int(end.timeIntervalSince(start)), 0)
        let session = WorkSession(startedAt: start,
                                  endedAt: end,
                                  durationSeconds: duration,
                                  note: pendingNote.trimmingCharacters(in: .whitespacesAndNewlines),
                                  isCompleted: true)
        context.insert(session)
        do {
            try context.save()
            NotificationCenter.default.post(name: .workSessionSaved, object: nil)
        } catch {
            print("Failed to save session: \(error)")
        }
        // Clear pending state and dismiss
        pendingSessionStart = nil
        pendingSessionEnd = nil
        pendingNote = ""
        showingNoteSheet = false
        Task { await refreshTodaysTotal() }
    }

    // MARK: - Helpers

    private func refreshTodaysTotal() async {
        // Compute total seconds for sessions completed today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        // Build a fetch descriptor for WorkSession where startedAt or endedAt is today. We won't rely on @Query to keep logic explicit.
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { session in
                // Consider a session part of today if its startedAt is on/after startOfDay
                session.startedAt >= startOfDay && session.isCompleted == true
            }
        )
        do {
            let sessions = try context.fetch(descriptor)
            let total = sessions.reduce(0) { partial, s in partial + max(s.durationSeconds, 0) }
            // Replace building today's tasks from session notes with using saved taskTemplates
            let savedTasks = taskTemplates.map { $0.title }
            await MainActor.run {
                self.todaysTotal = total
                // Keep only selections that still exist in saved tasks
                self.selectedTasks = self.selectedTasks.intersection(Set(savedTasks))
            }
        } catch {
            print("Failed to fetch today's sessions: \(error)")
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Placeholder WorkHistoryView (Charts)
// Create a basic WorkHistoryView that you can place in a TabView elsewhere.
struct WorkHistoryView: View {
    @Environment(\.modelContext) private var context

    @State private var currentMonthDaily: [ChartPoint] = []
    @State private var previousMonthDaily: [ChartPoint] = []
    @State private var monthlyTotals: [ChartPoint] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Group {
                        Text("Bieżący miesiąc - podział na dni")
                            .font(.headline)
                        Chart(currentMonthDaily) { point in
                            BarMark(
                                x: .value("Dzień", point.label),
                                y: .value("Sekundy", point.value)
                            )
                        }
                        .frame(height: 220)
                    }

                    Group {
                        Text("Ubiegły miesiąc - podział na dni")
                            .font(.headline)
                        Chart(previousMonthDaily) { point in
                            BarMark(
                                x: .value("Dzień", point.label),
                                y: .value("Sekundy", point.value)
                            )
                        }
                        .frame(height: 220)
                    }

                    Group {
                        Text("Sumarycznie - podział na miesiące")
                            .font(.headline)
                        Chart(monthlyTotals) { point in
                            BarMark(
                                x: .value("Miesiąc", point.label),
                                y: .value("Sekundy", point.value)
                            )
                        }
                        .frame(height: 220)
                    }
                }
                .padding()
            }

            // Stały pasek na dole widoczny zawsze
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Link("by peterwolf.pl",
                         destination: URL(string: "https://peterwolf.pl")!)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .tint(.primary)
                        .underline()
                        .padding(.vertical, 10)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .shadow(radius: 4, x: 0, y: -1)
            }
        }
        .task { await reloadCharts() }
        .onReceive(NotificationCenter.default.publisher(for: .workSessionSaved)) { _ in
            Task { await reloadCharts() }
        }
    }

    private func reloadCharts() async {
        do {
            let all = try context.fetch(FetchDescriptor<WorkSession>())
            let calendar = Calendar.current

            func dayKey(_ date: Date) -> String {
                let comps = calendar.dateComponents([.year, .month, .day], from: date)
                return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            }

            func monthKey(_ date: Date) -> String {
                let comps = calendar.dateComponents([.year, .month], from: date)
                return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            }

            let now = Date()
            let currentMonth = calendar.dateComponents([.year, .month], from: now)
            let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let previousMonth = calendar.dateComponents([.year, .month], from: previousMonthDate)

            var currentMonthBuckets: [String: Int] = [:]
            var previousMonthBuckets: [String: Int] = [:]
            var monthlyBuckets: [String: Int] = [:]

            for s in all where s.isCompleted {
                let start = s.startedAt
                let comps = calendar.dateComponents([.year, .month, .day], from: start)

                if comps.year == currentMonth.year && comps.month == currentMonth.month {
                    currentMonthBuckets[dayKey(start), default: 0] += max(s.durationSeconds, 0)
                }
                if comps.year == previousMonth.year && comps.month == previousMonth.month {
                    previousMonthBuckets[dayKey(start), default: 0] += max(s.durationSeconds, 0)
                }
                monthlyBuckets[monthKey(start), default: 0] += max(s.durationSeconds, 0)
            }

            let currentPoints = currentMonthBuckets.keys.sorted().map { key in
                ChartPoint(label: String(key.suffix(2)), value: currentMonthBuckets[key] ?? 0)
            }
            let previousPoints = previousMonthBuckets.keys.sorted().map { key in
                ChartPoint(label: String(key.suffix(2)), value: previousMonthBuckets[key] ?? 0)
            }
            let monthlyPoints = monthlyBuckets.keys.sorted().map { key in
                // label like YYYY-MM -> show MM
                ChartPoint(label: String(key.suffix(2)), value: monthlyBuckets[key] ?? 0)
            }

            await MainActor.run {
                self.currentMonthDaily = currentPoints
                self.previousMonthDaily = previousPoints
                self.monthlyTotals = monthlyPoints
            }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
}
