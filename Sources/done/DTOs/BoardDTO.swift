import Vapor

struct BoardDTO: Content {
    var id: UUID?
    var title: String
}
