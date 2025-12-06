import Foundation
import SwiftData

@Model
final class TaskTemplate {
    var title: String

    init(title: String) {
        self.title = title
    }
}
