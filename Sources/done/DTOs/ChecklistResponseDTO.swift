import Vapor

struct ChecklistItemResponseDTO: Content {
    var id: UUID?
    var content: String
    var isCompleted: Bool
    var position: Int
}

struct ChecklistResponseDTO: Content {
    var id: UUID?
    var title: String
    var items: [ChecklistItemResponseDTO]?
}
