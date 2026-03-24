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
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, position
        case dueDate = "due_date"
        case priority
        case columnID = "column_id"
        case assigneeID = "assignee_id"
        case isCompleted = "is_completed"
    }
}
