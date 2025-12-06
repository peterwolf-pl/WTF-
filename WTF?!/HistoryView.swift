import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context

    @State private var totalThisMonth: Int = 0
    @State private var totalLastMonth: Int = 0
    @State private var thisMonthNotes: [(note: String, seconds: Int)] = []
    @State private var lastMonthNotes: [(note: String, seconds: Int)] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Podsumowanie") {
                    HStack {
                        Text("Ten miesiąc")
                        Spacer()
                        Text(format(duration: TimeInterval(totalThisMonth)))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    HStack {
                        Text("Ubiegły miesiąc")
                        Spacer()
                        Text(format(duration: TimeInterval(totalLastMonth)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Ten miesiąc — notatki") {
                    if thisMonthNotes.isEmpty {
                        Text("Brak notatek")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(thisMonthNotes, id: \.note) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.note.isEmpty ? "Bez notatki" : item.note)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text(format(duration: TimeInterval(item.seconds)))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                Section("Ubiegły miesiąc — notatki") {
                    if lastMonthNotes.isEmpty {
                        Text("Brak notatek")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lastMonthNotes, id: \.note) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.note.isEmpty ? "Bez notatki" : item.note)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text(format(duration: TimeInterval(item.seconds)))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Historia")
            .task { await reloadTotals() }
            .onReceive(NotificationCenter.default.publisher(for: .workSessionSaved)) { _ in
                Task { await reloadTotals() }
            }
        }
    }

    // MARK: - Data loading & aggregation
    private func reloadTotals() async {
        await MainActor.run {
            self.totalThisMonth = 0
            self.totalLastMonth = 0
        }
        do {
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            let thisMonthRange = monthDateRange(offsetBy: 0)
            let lastMonthRange = monthDateRange(offsetBy: -1)

            var thisTotal = 0
            var lastTotal = 0

            var thisBuckets: [String: Int] = [:]
            var lastBuckets: [String: Int] = [:]

            for s in sessions where s.isCompleted {
                let started = s.startedAt
                let ended = s.endedAt ?? s.startedAt.addingTimeInterval(TimeInterval(s.durationSeconds))
                let entryRange = started..<ended

                let thisOverlap = Int(overlapDuration(between: entryRange, and: thisMonthRange))
                let lastOverlap = Int(overlapDuration(between: entryRange, and: lastMonthRange))

                thisTotal += thisOverlap
                lastTotal += lastOverlap

                // Aggregate by note (trimmed), group empty as "Bez notatki"
                let trimmed = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
                let noteKey = trimmed.isEmpty ? "Bez notatki" : trimmed
                if thisOverlap > 0 { thisBuckets[noteKey, default: 0] += thisOverlap }
                if lastOverlap > 0 { lastBuckets[noteKey, default: 0] += lastOverlap }
            }

            await MainActor.run {
                self.totalThisMonth = max(thisTotal, 0)
                self.totalLastMonth = max(lastTotal, 0)
                self.thisMonthNotes = thisBuckets.map { (note: $0.key, seconds: $0.value) }
                    .sorted { $0.seconds > $1.seconds }
                self.lastMonthNotes = lastBuckets.map { (note: $0.key, seconds: $0.value) }
                    .sorted { $0.seconds > $1.seconds }
            }
        } catch {
            print("Failed to fetch sessions: \(error)")
        }
    }

    private func monthDateRange(offsetBy monthOffset: Int) -> Range<Date> {
        let calendar = Calendar.current
        let now = Date()
        guard
            let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
            let start = calendar.date(byAdding: .month, value: monthOffset, to: startOfThisMonth),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else {
            return now..<now
        }
        return start..<end
    }

    private func overlapDuration(between a: Range<Date>, and b: Range<Date>) -> TimeInterval {
        let start = max(a.lowerBound, b.lowerBound)
        let end = min(a.upperBound, b.upperBound)
        return max(0, end.timeIntervalSince(start))
    }
}

private func format(duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    return String(format: "%02dh %02dm", hours, minutes)
}

#Preview {
    // In-memory container for preview
    let container = try! ModelContainer(for: WorkSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext

    // Sample sessions for preview
    let cal = Calendar.current
    let now = Date()
    let start1 = cal.date(byAdding: .day, value: -2, to: now)!
    let end1 = cal.date(byAdding: .hour, value: -2, to: now)!
    let s1 = WorkSession(startedAt: start1, endedAt: end1, durationSeconds: max(Int(end1.timeIntervalSince(start1)), 0), note: "", isCompleted: true)

    let start2 = cal.date(byAdding: .day, value: -25, to: now)!
    let end2 = start2.addingTimeInterval(3*3600 + 30*60)
    let s2 = WorkSession(startedAt: start2, endedAt: end2, durationSeconds: max(Int(end2.timeIntervalSince(start2)), 0), note: "", isCompleted: true)

    context.insert(s1)
    context.insert(s2)
    try! context.save()

    return HistoryView()
        .modelContainer(container)
}
