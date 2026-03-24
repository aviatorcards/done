import Fluent
import Vapor

final class BoardMember: Model, Content, @unchecked Sendable {
    static let schema = "board_members"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "board_id")
    var board: Board
    
    @Parent(key: "user_id")
    var user: User
    
    @Field(key: "role")
    var role: String // "admin", "viewer", "editor"
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, boardID: Board.IDValue, userID: User.IDValue, role: String = "member") {
        self.id = id
        self.$board.id = boardID
        self.$user.id = userID
        self.role = role
    }
}
