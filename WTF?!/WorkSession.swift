import Foundation
import SwiftData

@Model
final class WorkSession {
    // Unique identifier is provided by SwiftData implicitly, but we can add one if needed later.
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var note: String
    var isCompleted: Bool

    init(startedAt: Date = .now, endedAt: Date? = nil, durationSeconds: Int = 0, note: String = "", isCompleted: Bool = false) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.note = note
        self.isCompleted = isCompleted
    }
}
