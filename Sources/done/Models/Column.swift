import Fluent
import Vapor

final class Column: Model, Content, @unchecked Sendable {
    static let schema = "columns"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "title")
    var title: String
    
    @Field(key: "position")
    var position: Int
    
    @Parent(key: "board_id")
    var board: Board
    
    @Children(for: \.$column)
    var cards: [Card]
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, title: String, position: Int, boardID: Board.IDValue) {
        self.id = id
        self.title = title
        self.position = position
        self.$board.id = boardID
    }
}
