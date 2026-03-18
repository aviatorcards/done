import Vapor

struct CardDTO: Content {
    var id: UUID?
    var title: String?
    var description: String?
    var position: Int?
    var dueDate: String?
    var priority: String?
    var columnID: UUID?
    var assigneeID: UUID?
    var isCompleted: Bool?
}
