import Vapor

struct ColumnDTO: Content {
    var id: UUID?
    var title: String
    var position: Int?
    var boardID: UUID
}
